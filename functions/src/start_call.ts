/**
 * Videobellen — startVideoCall Cloud Function (Fase VB-V2).
 *
 * Nieuwe HTTPS callable die een gesprek initieert: server genereert
 * een unieke roomName, maakt zowel caller- als callee-token, en pusht
 * de callee-token via high-priority data-FCM naar het doel-apparaat.
 * De caller krijgt zijn eigen token direct in de response.
 *
 * Security-lat identiek aan getVideoCallToken (V2-0): gedeelde rate-
 * limit-teller per uid, apparaat-verify onder auth.uid, kring-
 * membership check via leden-doc + eigenaar-fallback. Zie
 * call_helpers.ts voor de details.
 *
 * Payload:
 *   request.data = {
 *     kringId: string,
 *     bellerApparaatId: string,   // eigen apparaatId van de beller
 *     doelApparaatId: string,     // apparaatId van de callee
 *   }
 *   return         = {
 *     token: string,              // caller-token (10 min)
 *     roomName: string,           // gesprek_{kringId}_{ms}_{rand6}
 *     callId: string,             // = roomName (uniek per gesprek)
 *   }
 *
 * FCM naar doel-apparaat (data-only, high-priority):
 *   data = {
 *     type: 'inkomend_gesprek',
 *     roomName, callId, callerName, calleeToken, kringId,
 *   }
 * De app-kant (PushService, V2-3) publiceert dit op incomingCallNotifier
 * zodat tablet_scherm het inkomend-gesprek-scherm kan openen.
 *
 * Deze function schrijft niets naar momenten/ — recursie met
 * onNieuwMoment is dus per definitie onmogelijk. Enige writes komen
 * uit de rate-limit-helper op rate_limits/{uid}.
 *
 * Runtime: Node 22, region europe-west1 (matcht onNieuwMoment en
 * getVideoCallToken).
 */

import { randomBytes } from 'crypto';
import * as admin from 'firebase-admin';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { logger } from 'firebase-functions/v2';
import { AccessToken } from 'livekit-server-sdk';
import {
  eisIdString,
  verwerkRateLimit,
  verifyApparaatOnderUid,
  verifyKringMembership,
} from './call_helpers';

const LIVEKIT_API_KEY = defineSecret('LIVEKIT_API_KEY');
const LIVEKIT_API_SECRET = defineSecret('LIVEKIT_API_SECRET');

/**
 * TTL voor beide tokens (caller + callee). 10 minuten geeft de callee
 * ruim tijd om de melding te zien, op te nemen en te verbinden, zonder
 * dat de token na een gemiste oproep te lang bruikbaar blijft.
 */
const TOKEN_TTL = '10m';

/**
 * Zes hex-chars entropy naast de milliseconde-timestamp. Voorkomt
 * collision als twee gesprekken in dezelfde kring exact op dezelfde ms
 * gestart worden (praktisch onmogelijk maar zero-cost te vermijden).
 */
function genereerRoomSuffix(): string {
  return randomBytes(4).toString('hex').substring(0, 6);
}

/**
 * Bepaalt een leesbare naam voor de beller om in de FCM-payload mee te
 * sturen. Voorkeur: persoonsNaam uit het beller-apparaat-doc (die is al
 * geladen door verifyApparaatOnderUid). Fallback: 'Familie' — nooit
 * leeg naar de callee, want dat geeft een lege naam op het scherm.
 */
function callerNaamUit(
  apparaatSnap: admin.firestore.DocumentSnapshot,
): string {
  const naam = apparaatSnap.data()?.persoonsNaam;
  if (typeof naam !== 'string') return 'Familie';
  const trimmed = naam.trim();
  return trimmed.length > 0 ? trimmed : 'Familie';
}

// Pure helper — key en secret komen als parameter zodat de handler
// ze één keer valideert en de functie zelf geen module-globals leest.
async function maakToken(
  livekitKey: string,
  livekitSecret: string,
  identity: string,
  roomName: string,
): Promise<string> {
  const at = new AccessToken(livekitKey, livekitSecret, {
    identity,
    ttl: TOKEN_TTL,
  });
  at.addGrant({
    roomJoin: true,
    room: roomName,
    canPublish: true,
    canSubscribe: true,
  });
  return at.toJwt();
}

export const startVideoCall = onCall(
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

    // 1. Rate-limit vóór alle andere checks — gedeelde teller met
    //    getVideoCallToken zodat een aanvaller niet kan afwisselen.
    await verwerkRateLimit(db, uid);

    // 2. Payload valideren.
    const data = request.data ?? {};
    const kringId = eisIdString(data.kringId, 'kringId');
    const bellerApparaatId =
      eisIdString(data.bellerApparaatId, 'bellerApparaatId');
    const doelApparaatId =
      eisIdString(data.doelApparaatId, 'doelApparaatId');
    if (bellerApparaatId === doelApparaatId) {
      throw new HttpsError('invalid-argument',
        'Kan niet met jezelf bellen');
    }

    // 3. Beller-apparaat verify + kring-membership check in parallel.
    //    verifyApparaatOnderUid retourneert de snap zodat we hem voor
    //    callerName kunnen hergebruiken zonder extra read.
    const [bellerSnap, kringSnap] = await Promise.all([
      verifyApparaatOnderUid(db, uid, bellerApparaatId),
      verifyKringMembership(db, uid, kringId),
    ]);

    // 4. Doel-apparaat ophalen. In het V7 shared-account model hangen
    //    álle apparaten van een kring onder de eigenaarUid, dus we
    //    zoeken doelApparaatId onder gebruikers/{eigenaarUid}/apparaten.
    const eigenaarUid = kringSnap.data()?.eigenaarUid;
    if (typeof eigenaarUid !== 'string' || eigenaarUid.length === 0) {
      // Kring zonder eigenaarUid is corrupt state — permission-denied
      // ipv internal want de client kan er niks aan doen behalve
      // opnieuw proberen op een andere kring.
      logger.warn('kring zonder eigenaarUid', { uid, kringId });
      throw new HttpsError('permission-denied',
        'Kring is niet correct geconfigureerd');
    }
    const doelRef = db
      .collection('gebruikers').doc(eigenaarUid)
      .collection('apparaten').doc(doelApparaatId);
    const doelSnap = await doelRef.get();
    if (!doelSnap.exists) {
      throw new HttpsError('not-found', 'Doel-apparaat bestaat niet');
    }
    const doelData = doelSnap.data() ?? {};
    if (doelData.kringId !== kringId) {
      // Bewust permission-denied ipv not-found: onthult niet aan de
      // aanvrager of dit apparaatId in een andere kring bestaat.
      logger.warn('doel-apparaat zit niet in dezelfde kring', {
        uid, kringId, doelApparaatId,
        actueleKring: doelData.kringId ?? null,
      });
      throw new HttpsError('permission-denied',
        'Doel-apparaat zit niet in deze kring');
    }
    const doelFcmToken = doelData.fcmToken;
    if (typeof doelFcmToken !== 'string' || doelFcmToken.length === 0) {
      throw new HttpsError('failed-precondition',
        'Doel-apparaat is niet bereikbaar (geen actieve push-token)');
    }

    // 5. Secrets valideren. Expliciet binnen de handler lezen — garantie
    //    dat Cloud Run ze al gemount heeft. Lege waarde is een
    //    configuratiefout die we direct loggen zodat de oorzaak zichtbaar
    //    is in Cloud Logging i.p.v. als cryptische LiveKit-fout.
    const livekitKey = LIVEKIT_API_KEY.value().trim();
    const livekitSecret = LIVEKIT_API_SECRET.value().trim();
    if (!livekitKey || !livekitSecret) {
      logger.error('LiveKit-secrets ontbreken', {
        uid, kringId, hasKey: !!livekitKey, hasSecret: !!livekitSecret,
      });
      throw new HttpsError('internal', 'Server-configuratiefout');
    }

    // 6. Room-naam + tokens. Timestamp + rand-suffix maakt hem uniek
    //    per gesprek zodat gemiste oproepen niet in een oude sessie
    //    kunnen doorlekken.
    const nowMs = Date.now();
    const roomName = `gesprek_${kringId}_${nowMs}_${genereerRoomSuffix()}`;
    const callId = roomName;
    const callerIdentity = `${uid}_${bellerApparaatId}`;
    // Callee zit onder dezelfde uid als beller (V7 shared account) —
    // eigenaarUid == uid als beller de eigenaar is; anders is het een
    // gast maar de tablet hangt sowieso onder eigenaarUid want daar
    // heeft PushService hem geregistreerd.
    const calleeIdentity = `${eigenaarUid}_${doelApparaatId}`;

    let callerToken: string;
    let calleeToken: string;
    try {
      [callerToken, calleeToken] = await Promise.all([
        maakToken(livekitKey, livekitSecret, callerIdentity, roomName),
        maakToken(livekitKey, livekitSecret, calleeIdentity, roomName),
      ]);
    } catch (e) {
      logger.error('token-generatie faalde', {
        uid, kringId, bellerApparaatId, doelApparaatId, error: String(e),
      });
      throw new HttpsError('internal', 'Token-generatie faalde');
    }

    // 7. FCM naar doel-apparaat — data-only, high-priority. Geen
    //    'notification'-block: het scherm-opent-flow gaat via de
    //    incomingCallNotifier in PushService (V2-3), niet via een
    //    tray-melding. Bij V5 (full-screen intent) komt daar een
    //    minimale notification-block bij met channel ons_moment_gesprek.
    //
    // V4: autoAnswer wordt op bel-moment uit het kring-doc gelezen (al
    //    beschikbaar via kringSnap) en als string meegestuurd. De tablet
    //    vertrouwt deze server-waarde — de beller kan hem niet manipuleren.
    const callerName = callerNaamUit(bellerSnap);
    const autoAnswer: boolean = kringSnap.data()?.autoAnswer === true;
    const message: admin.messaging.Message = {
      token: doelFcmToken,
      data: {
        type: 'inkomend_gesprek',
        roomName,
        callId,
        callerName,
        calleeToken,
        kringId,
        autoAnswer: autoAnswer ? 'true' : 'false',
      },
      android: {
        priority: 'high',
      },
    };
    try {
      const fcmId = await admin.messaging().send(message);
      logger.info('inkomend-gesprek FCM verstuurd', {
        uid, kringId, bellerApparaatId, doelApparaatId,
        roomName, fcmId,
      });
    } catch (e) {
      // Dead-token cleanup laten we in deze fase over aan onNieuwMoment
      // (die doet het bij push-meldingen). Voor de belflow is een falende
      // FCM een harde fout — de callee gaat het scherm niet zien.
      logger.error('inkomend-gesprek FCM faalde', {
        uid, kringId, doelApparaatId, error: String(e),
      });
      throw new HttpsError('unavailable',
        'Kon doel-apparaat niet bereiken; probeer opnieuw');
    }

    return { token: callerToken, roomName, callId };
  },
);
