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
 * V2 (helpers-refactor): rate-limit, apparaat-verify en kring-
 * membership check leven nu in call_helpers.ts zodat startVideoCall
 * dezelfde security-lat gebruikt.
 *
 * Deze function schrijft niets naar Firestore (behalve rate_limits via
 * de helper) en heeft geen bijeffecten anders dan logging. Room-
 * lifecycle (aanmaken/verwijderen) doet LiveKit Cloud zelf op basis
 * van deelnemers.
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
import {
  MODUS_TEST,
  MODUS_GESPREK,
  eisIdString,
  verwerkRateLimit,
  verifyApparaatOnderUid,
  verifyKringMembership,
} from './call_helpers';

const LIVEKIT_API_KEY = defineSecret('LIVEKIT_API_KEY');
const LIVEKIT_API_SECRET = defineSecret('LIVEKIT_API_SECRET');

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

    const db = admin.firestore();

    // Rate-limit vóór alle andere checks. Beschermt óók tegen
    // aanvragers die spammen met invalid payloads.
    await verwerkRateLimit(db, uid);

    // Payload valideren.
    const data = request.data ?? {};
    const modus = data.modus;
    const rawKringId = data.kringId;

    if (modus !== MODUS_TEST && modus !== MODUS_GESPREK) {
      throw new HttpsError('invalid-argument',
        `modus moet '${MODUS_TEST}' of '${MODUS_GESPREK}' zijn`);
    }
    const apparaatId = eisIdString(data.apparaatId, 'apparaatId');
    const kringId = modus === MODUS_GESPREK
      ? eisIdString(rawKringId, 'kringId')
      : null;

    // Apparaat-verify.
    await verifyApparaatOnderUid(db, uid, apparaatId);

    // Kring-membership + roomName-conventie.
    let roomName: string;
    if (modus === MODUS_TEST) {
      roomName = `test_${uid}_${apparaatId}`;
    } else {
      await verifyKringMembership(db, uid, kringId as string);
      roomName = `gesprek_${kringId}`;
    }

    // Identity is SERVER-BEPAALD.
    const identity = `${uid}_${apparaatId}`;

    // Token uitgeven.
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
