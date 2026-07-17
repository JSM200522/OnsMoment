/**
 * Videobellen — Cloud Function voor LiveKit-token-generatie (Fase VB-V0).
 *
 * getVideoCallToken: HTTPS callable die een korte JWT uitgeeft waarmee
 * een geauthenticeerde client kan verbinden met een LiveKit-room. De
 * API key + secret komen uit Firebase Secrets (LIVEKIT_API_KEY en
 * LIVEKIT_API_SECRET) via de Functions v2 secrets-binding — nooit uit
 * code, nooit uit een client-payload.
 *
 * Deze function schrijft niets naar Firestore en heeft geen bijeffecten
 * anders dan logging. Room-lifecycle (aanmaken/verwijderen) doet LiveKit
 * Cloud zelf op basis van deelnemers.
 *
 * Payload-conventie (V1+):
 *   request.data = {
 *     roomName: string,   // 'gesprek_{kringId}_{ms}' of 'test_*'
 *     identity: string,   // uniek per deelnemer, meestal apparaatId
 *   }
 *   return         = { token: string }   // 10 minuten geldig
 *
 * Runtime: Node 22, region europe-west1 (matcht Firestore eur3 en de
 * bestaande onNieuwMoment function).
 */

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { logger } from 'firebase-functions/v2';
import { AccessToken } from 'livekit-server-sdk';

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

    const roomName = request.data?.roomName;
    const identity = request.data?.identity;
    if (typeof roomName !== 'string' || roomName.length === 0) {
      throw new HttpsError('invalid-argument', 'roomName is verplicht');
    }
    if (typeof identity !== 'string' || identity.length === 0) {
      throw new HttpsError('invalid-argument', 'identity is verplicht');
    }

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
        uid, roomName, identity,
      });
      return { token };
    } catch (e) {
      logger.error('token-generatie faalde', {
        uid, roomName, identity, error: String(e),
      });
      throw new HttpsError('internal', 'Token-generatie faalde');
    }
  },
);
