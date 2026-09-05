/**
 * Videobellen — cancelVideoCall Cloud Function (Fase VB-V3).
 *
 * Wordt aangeroepen door de beller wanneer hij ophangt vóórdat de
 * callee heeft opgenomen. Stuurt een high-priority data-FCM naar het
 * doel-apparaat met `type: 'gesprek_geannuleerd'` + callId, zodat het
 * inkomend-scherm daar automatisch sluit en de ringtone stopt.
 *
 * Zonder deze flow zou de tablet blijven rinkelen tot de 45-seconde
 * timeout (V3-4) — vervelend als de beller net z'n vergissing herstelt.
 * Met de cancel-FCM sluit de tablet binnen 1-2 seconden.
 *
 * Security-lat identiek aan startVideoCall: gedeelde rate-limit-teller
 * per uid + kring-membership check. Zie call_helpers.ts.
 *
 * Payload:
 *   request.data = {
 *     kringId: string,
 *     callId: string,             // roomName uit startVideoCall
 *     doelApparaatId: string,     // te sluiten apparaat
 *   }
 *   return         = { verzonden: boolean }
 *
 * Return-conventie: fouten in FCM-delivery of missende doel-data zijn
 * NIET fataal (return verzonden:false). De beller heeft al opgehangen;
 * een retry-of-throw-nu is nutteloos. De tablet valt terug op de 45s
 * timeout als fallback. Enige throws zijn de security-layer-fouten
 * (auth, rate, invalid, permission, not-found).
 *
 * Schrijft niets naar momenten/ — recursie met onNieuwMoment onmogelijk.
 * Enige writes komen uit de rate-limit-helper op rate_limits/{uid}.
 *
 * Runtime: Node 22, region europe-west1.
 */

import * as admin from 'firebase-admin';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import {
  eisIdString,
  verwerkRateLimit,
  verifyKringMembership,
  verwijderBezetSlotAls,
  MAX_ID_LEN,
} from './call_helpers';

export const cancelVideoCall = onCall(
  {
    region: 'europe-west1',
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Login vereist');
    }
    const uid = request.auth.uid;
    const db = admin.firestore();

    await verwerkRateLimit(db, uid);

    const data = request.data ?? {};
    const kringId = eisIdString(data.kringId, 'kringId');
    const callId = eisIdString(data.callId, 'callId');
    const doelApparaatId = eisIdString(data.doelApparaatId, 'doelApparaatId');
    // BEL-R3: optioneel. Client kent altijd wie de ontvanger is (bij
    // beller-cancel = doelApparaatId zelf; bij callee-decline = eigen
    // apparaatId). Als aanwezig ruimen we het bezet-slot direct op zodat
    // een 2e beller niet hoeft te wachten op de 5-min TTL. Optioneel
    // gemaakt zodat oudere client-builds (die dit veld nog niet meesturen)
    // niet breken op invalid-argument.
    const ontvangerApparaatIdRaw = data.ontvangerApparaatId;
    const ontvangerApparaatId =
      typeof ontvangerApparaatIdRaw === 'string'
      && ontvangerApparaatIdRaw.length > 0
      && ontvangerApparaatIdRaw.length <= MAX_ID_LEN
        ? ontvangerApparaatIdRaw
        : null;

    // Membership-check: beller moet lid zijn van de kring waar de
    // cancel bijhoort. Voorkomt dat iemand een cancel voor een ander
    // gesprek van een andere kring kan sturen.
    const kringSnap = await verifyKringMembership(db, uid, kringId);
    const eigenaarUid = kringSnap.data()?.eigenaarUid;
    if (typeof eigenaarUid !== 'string' || eigenaarUid.length === 0) {
      logger.warn('cancel: kring zonder eigenaarUid', { uid, kringId });
      throw new HttpsError('permission-denied',
        'Kring is niet correct geconfigureerd');
    }

    // Doel-apparaat ophalen. Onder gebruikers/{eigenaarUid} (V7 shared
    // account). Doel-verdwijnend is geen fout — beller heeft al
    // opgehangen, tablet zal via timeout vanzelf sluiten.
    const doelRef = db
      .collection('gebruikers').doc(eigenaarUid)
      .collection('apparaten').doc(doelApparaatId);
    const doelSnap = await doelRef.get();
    if (!doelSnap.exists) {
      logger.info('cancel: doel-apparaat weg, no-op', {
        uid, kringId, doelApparaatId, callId,
      });
      return { verzonden: false };
    }
    const doelData = doelSnap.data() ?? {};
    if (doelData.kringId !== kringId) {
      logger.warn('cancel: doel-apparaat in andere kring', {
        uid, kringId, doelApparaatId,
        actueleKring: doelData.kringId ?? null,
      });
      throw new HttpsError('permission-denied',
        'Doel-apparaat zit niet in deze kring');
    }
    const doelFcmToken = doelData.fcmToken;
    if (typeof doelFcmToken !== 'string' || doelFcmToken.length === 0) {
      logger.info('cancel: doel heeft geen fcmToken, no-op', {
        uid, kringId, doelApparaatId, callId,
      });
      return { verzonden: false };
    }

    const message: admin.messaging.Message = {
      token: doelFcmToken,
      data: {
        type: 'gesprek_geannuleerd',
        callId,
        kringId,
      },
      android: { priority: 'high' },
      // iOS: zie onNieuwMoment — background + priority 5 is het maximale
      // voor data-only FCM op iOS zonder PushKit/CallKit (Fase F).
      apns: {
        headers: {
          'apns-push-type': 'background',
          'apns-priority': '5',
        },
        payload: {
          aps: { contentAvailable: true },
        },
      },
    };
    let verzonden = false;
    try {
      const fcmId = await admin.messaging().send(message);
      logger.info('cancel FCM verstuurd', {
        uid, kringId, doelApparaatId, callId, fcmId,
      });
      verzonden = true;
    } catch (e) {
      // Delivery-fout: log en verder — tablet valt terug op de 45s
      // timeout, en de bezet-slot-cleanup mag hier NIET afhangen van
      // FCM-success (anders blijft het slot hangen tot TTL bij delivery-
      // problemen die zich uitzonderlijk voordoen).
      logger.warn('cancel FCM faalde (geen fout naar client)', {
        uid, kringId, doelApparaatId, callId, error: String(e),
      });
    }

    // BEL-R3: ruim bezet-slot op als de client de ontvanger meestuurt.
    // Fail-soft binnen de helper zelf — nooit blocking voor de client-
    // return. Zonder ontvangerApparaatId (oude client-builds): TTL doet
    // het werk over max 5 min.
    if (ontvangerApparaatId !== null) {
      await verwijderBezetSlotAls(db, ontvangerApparaatId, callId);
    }

    return { verzonden };
  },
);
