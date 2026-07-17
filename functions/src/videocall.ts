/**
 * Videobellen — Cloud Function voor LiveKit-token-generatie.
 *
 * getVideoCallToken: HTTPS callable die een korte JWT uitgeeft waarmee
 * een geauthenticeerde client kan verbinden met een LiveKit-room. De
 * API key + secret komen uit Firebase Secrets (LIVEKIT_API_KEY en
 * LIVEKIT_API_SECRET) via de Functions v2 secrets-binding — nooit uit
 * code, nooit uit een client-payload.
 *
 * V2-0 security-hardening:
 * - roomName en identity worden SERVER-BEPAALD; de client kan zich niet
 *   als iemand anders identificeren en kan geen tokens voor willekeurige
 *   rooms opvragen.
 * - Bij modus='gesprek' verifieert de server dat de aanvrager lid is van
 *   de opgegeven kring — via de leden-subcollectie of (backwards-compat
 *   met V7/V8-kringen) de eigenaarUid op de kring-doc.
 * - Bij modus='test' verifieert de server dat het apparaatId onder deze
 *   uid valt; test-rooms zijn per-apparaat uniek zodat twee testers niet
 *   per ongeluk in hetzelfde gesprek belanden.
 *
 * Deze function schrijft niets naar Firestore en heeft geen bijeffecten
 * anders dan logging. Room-lifecycle (aanmaken/verwijderen) doet LiveKit
 * Cloud zelf op basis van deelnemers.
 *
 * Payload:
 *   request.data = {
 *     modus: 'gesprek' | 'test',
 *     apparaatId: string,   // altijd verplicht; bepaalt identity
 *     kringId?: string,     // verplicht als modus='gesprek'
 *   }
 *   return         = {
 *     token: string,        // 10 minuten geldig
 *     roomName: string,     // server-bepaald: test_{uid}_{appId}
 *                           //             of gesprek_{kringId}
 *     identity: string,     // server-bepaald: {uid}_{apparaatId}
 *   }
 *
 * Runtime: Node 22, region europe-west1 (matcht Firestore eur3 en de
 * bestaande onNieuwMoment function).
 */

import * as admin from 'firebase-admin';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { logger } from 'firebase-functions/v2';
import { AccessToken } from 'livekit-server-sdk';

const LIVEKIT_API_KEY = defineSecret('LIVEKIT_API_KEY');
const LIVEKIT_API_SECRET = defineSecret('LIVEKIT_API_SECRET');

const MODUS_TEST = 'test';
const MODUS_GESPREK = 'gesprek';

/**
 * Bovengrens voor identifiers uit client-payload. Beschermt tegen
 * poging tot log-flooding of ongeldige LiveKit-JWTs door absurd lange
 * strings; ruim boven wat DeviceModusService/KringService.genereerKringId
 * ooit produceren (Firestore auto-IDs zijn 20 chars).
 */
const MAX_ID_LEN = 128;

export const getVideoCallToken = onCall(
  {
    region: 'europe-west1',
    secrets: [LIVEKIT_API_KEY, LIVEKIT_API_SECRET],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Login vereist');
    }
    const uid = request.auth.uid;

    // 1. Payload valideren.
    const data = request.data ?? {};
    const modus = data.modus;
    const apparaatId = data.apparaatId;
    const kringId = data.kringId;

    if (modus !== MODUS_TEST && modus !== MODUS_GESPREK) {
      throw new HttpsError('invalid-argument',
        `modus moet '${MODUS_TEST}' of '${MODUS_GESPREK}' zijn`);
    }
    if (typeof apparaatId !== 'string' || apparaatId.length === 0
        || apparaatId.length > MAX_ID_LEN) {
      throw new HttpsError('invalid-argument', 'apparaatId ongeldig');
    }
    if (modus === MODUS_GESPREK) {
      if (typeof kringId !== 'string' || kringId.length === 0
          || kringId.length > MAX_ID_LEN) {
        throw new HttpsError('invalid-argument',
          'kringId is verplicht voor modus=gesprek');
      }
    }

    const db = admin.firestore();

    // 2. Apparaat-verify: het apparaat moet bestaan onder deze uid.
    //    Bewijst dat de aanvrager écht toegang heeft tot dit apparaat en
    //    voorkomt dat iemand met identity={andermans-appId} spookt.
    const apparaatRef = db
      .collection('gebruikers').doc(uid)
      .collection('apparaten').doc(apparaatId);
    const apparaatSnap = await apparaatRef.get();
    if (!apparaatSnap.exists) {
      logger.warn('apparaat niet gevonden onder deze uid', {
        uid, apparaatId,
      });
      throw new HttpsError('permission-denied',
        'Apparaat hoort niet bij dit account');
    }

    // 3. Kring-membership (alleen voor gesprek). Bewijs van lidmaatschap
    //    is óf een leden-subcollectie-doc (V9-schema) óf eigenaarUid op
    //    de kring-doc (V7/V8-fallback). Parallel-fetch — 2 reads,
    //    trivial in kosten.
    let roomName: string;
    if (modus === MODUS_TEST) {
      roomName = `test_${uid}_${apparaatId}`;
    } else {
      const kringRef = db.collection('kringen').doc(kringId as string);
      const [kringSnap, lidSnap] = await Promise.all([
        kringRef.get(),
        kringRef.collection('leden').doc(uid).get(),
      ]);
      if (!kringSnap.exists) {
        throw new HttpsError('not-found', 'Kring bestaat niet');
      }
      const isLid = lidSnap.exists;
      const eigenaarUid = kringSnap.data()?.eigenaarUid;
      const isEigenaar = typeof eigenaarUid === 'string' && eigenaarUid === uid;
      if (!isLid && !isEigenaar) {
        logger.warn('geen membership in kring', { uid, kringId });
        throw new HttpsError('permission-denied',
          'Geen toegang tot deze kring');
      }
      roomName = `gesprek_${kringId}`;
    }

    // 4. Identity is SERVER-BEPAALD. Elke client-input voor identity
    //    wordt genegeerd — voorkomt dat een aanvrager zichzelf in
    //    LiveKit als iemand anders presenteert (impersonation-risk).
    const identity = `${uid}_${apparaatId}`;

    // 5. Token uitgeven.
    try {
      const at = new AccessToken(
        LIVEKIT_API_KEY.value(),
        LIVEKIT_API_SECRET.value(),
        { identity, ttl: '10m' },
      );
      at.addGrant({
        roomJoin: true,
        room: roomName,
        canPublish: true,
        canSubscribe: true,
      });
      const token = await at.toJwt();
      logger.info('videocall-token uitgegeven', {
        uid, modus, kringId: kringId ?? null, apparaatId, roomName,
      });
      return { token, roomName, identity };
    } catch (e) {
      logger.error('token-generatie faalde', {
        uid, modus, kringId: kringId ?? null, apparaatId, error: String(e),
      });
      throw new HttpsError('internal', 'Token-generatie faalde');
    }
  },
);
