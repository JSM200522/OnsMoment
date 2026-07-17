/**
 * Cloud Functions voor Ons Moment push-meldingen.
 *
 * onNieuwMoment: Firestore-trigger die bij elk nieuw moment een FCM-push
 * stuurt naar de juiste apparaten in de kring. Payload matcht de conventies
 * uit lib/services/push_service.dart (Fase 1/2):
 *
 *   notification.android.channel_id = channelIdVoorGeluid[kring.herkenningsgeluid]
 *   data.momentId                   = <firestore-doc-id>   (voor tap-open)
 *
 * De function schrijft NOOIT naar momenten/ — dat zou zelf-triggering
 * veroorzaken. Enige writes zijn dead-token cleanup op
 * gebruikers/{uid}/apparaten/{id}.
 *
 * Runtime: Node 22, region europe-west1 (matcht Firestore eur3).
 */

import { setGlobalOptions } from 'firebase-functions/v2';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';
import * as admin from 'firebase-admin';

setGlobalOptions({ region: 'europe-west1' });
admin.initializeApp();

// Fase VB-V0: LiveKit-token-endpoint voor videobellen. Aparte file zodat
// index.ts overzichtelijk blijft.
export { getVideoCallToken } from './videocall';

/**
 * Spiegel van PushService.channelIdVoorGeluid in
 * lib/services/push_service.dart. LET OP: bij wijziging beide files
 * synchroon houden — anders komt de melding binnen op een onbekend channel
 * en valt Android terug op default (ons_moment_twinkel) met het verkeerde
 * geluid.
 */
const channelIdVoorGeluid: Record<string, string> = {
  twinkel:  'ons_moment_twinkel',
  bel:      'ons_moment_bel',
  vogel:    'ons_moment_vogel',
  piano:    'ons_moment_piano',
  kerkklok: 'ons_moment_kerkklok',
  hart:     'ons_moment_hart',
};

const defaultChannelId = 'ons_moment_twinkel';

/**
 * Skip-drempel voor geplande momenten die nog in de toekomst liggen.
 * 5 min = tolerantie voor server-clock-drift zonder dat een normale
 * "direct verstuurd" (testModus) per ongeluk wordt geskipt. Een dedicated
 * scheduler-function die geplande momenten precies op geplandOp-tijd pusht
 * is scope voor later.
 */
const geplandeSkipMs = 5 * 60 * 1000;

/**
 * Zet moment-type + afzender-naam om in body-tekst. Simpele, dementie-
 * vriendelijke formulering (kernwaarde: 'helpt je DIERBARE').
 */
function bodyVoorType(type: unknown, vanNaam: string): string {
  switch (type) {
    case 'foto':   return `Een foto van ${vanNaam}`;
    case 'video':  return `Een video van ${vanNaam}`;
    case 'stem':   return `Een stemmetje van ${vanNaam}`;
    case 'lied':   return `Een liedje van ${vanNaam}`;
    case 'hartje': return `Een hartje van ${vanNaam} 💕`;
    default:       return `Een bericht van ${vanNaam}`;
  }
}

export const onNieuwMoment = onDocumentCreated(
  'momenten/{momentId}',
  async (event) => {
    const snap = event.data;
    if (!snap) {
      logger.warn('geen event.data — skip');
      return;
    }
    const momentId = event.params.momentId;
    const moment = snap.data();

    // 1. Skip geplande momenten die nog >5 min in de toekomst liggen.
    const geplandOp = moment.geplandOp as
      | admin.firestore.Timestamp
      | undefined;
    if (geplandOp && typeof geplandOp.toMillis === 'function') {
      const geplandMs = geplandOp.toMillis();
      const nowMs = Date.now();
      if (geplandMs > nowMs + geplandeSkipMs) {
        logger.info('gepland voor de toekomst — skip', {
          momentId,
          geplandMs,
          nowMs,
          verschilMs: geplandMs - nowMs,
        });
        return;
      }
    }

    // 2. Kring ophalen (1 read).
    const kringId = moment.kringId as string | undefined;
    if (!kringId) {
      logger.warn('moment zonder kringId — skip', { momentId });
      return;
    }
    const db = admin.firestore();
    const kringSnap = await db.collection('kringen').doc(kringId).get();
    if (!kringSnap.exists) {
      logger.warn('kring bestaat niet — skip', { momentId, kringId });
      return;
    }
    const kring = kringSnap.data() ?? {};
    const eigenaarUid = kring.eigenaarUid as string | undefined;
    if (!eigenaarUid) {
      logger.warn('kring zonder eigenaarUid — skip', { momentId, kringId });
      return;
    }
    const herkenningsgeluid =
      (kring.herkenningsgeluid as string | undefined) ?? 'twinkel';
    const channelId =
      channelIdVoorGeluid[herkenningsgeluid] ?? defaultChannelId;

    // 3. Target-apparaten bepalen (hybride):
    //    - aanApparaatIds als niet-lege array → gebruik die
    //    - anders → ALLE apparaten in deze kring (familie + ontvanger),
    //      zonder modus-filter. Zo krijgen ook familie-telefoons die in
    //      dezelfde kring zitten de melding (bv. Pixel die zowel verstuurt
    //      als meekijkt). De afzender-uitfilter hieronder voorkomt dat
    //      de verstuurder zichzelf pusht.
    //    - altijd → afzender (vanApparaatId) uitsluiten
    const vanApparaatId = moment.vanApparaatId as string | undefined;
    let targetIds: string[] = [];
    const aanApparaatIds = moment.aanApparaatIds;
    if (Array.isArray(aanApparaatIds) && aanApparaatIds.length > 0) {
      targetIds = aanApparaatIds.filter(
        (id): id is string => typeof id === 'string' && id.length > 0,
      );
    } else {
      const q = await db
        .collection('gebruikers').doc(eigenaarUid)
        .collection('apparaten')
        .where('kringId', '==', kringId)
        .get();
      targetIds = q.docs.map((d) => d.id);
    }
    if (vanApparaatId) {
      targetIds = targetIds.filter((id) => id !== vanApparaatId);
    }
    if (targetIds.length === 0) {
      logger.info('geen target-apparaten — skip', {
        momentId, kringId, vanApparaatId,
      });
      return;
    }

    // 4. Batch-get de apparaat-docs → tokens verzamelen.
    const apparaatRefs = targetIds.map((id) =>
      db.collection('gebruikers').doc(eigenaarUid).collection('apparaten').doc(id),
    );
    const apparaatSnaps = await db.getAll(...apparaatRefs);
    const tokens: string[] = [];
    const refPerToken: admin.firestore.DocumentReference[] = [];
    for (const s of apparaatSnaps) {
      if (!s.exists) continue;
      const data = s.data() ?? {};
      const t = data.fcmToken;
      if (typeof t !== 'string' || t.length === 0) continue;
      tokens.push(t);
      refPerToken.push(s.ref);
    }
    if (tokens.length === 0) {
      logger.info('geen fcmTokens — skip', {
        momentId, kringId, targetCount: targetIds.length,
      });
      return;
    }

    // 5. Message opbouwen — payload-conventie matcht Fase 1/2.
    const vanNaam =
      ((moment.vanNaam as string | undefined) ?? '').trim() || 'Iemand';
    const kringNaam = ((kring.naam as string | undefined) ?? '').trim();
    const titel = kringNaam.length > 0 ? kringNaam : 'Ons Moment';
    const body = bodyVoorType(moment.type, vanNaam);

    const message: admin.messaging.MulticastMessage = {
      tokens,
      notification: { title: titel, body },
      android: {
        priority: 'high',
        notification: {
          channelId,
          // Monochroom statusbar-icoon uit android/app/src/main/res/drawable-*
          // (Fase 1: ic_stat_ons_moment, 5 densities). Zonder expliciete
          // 'icon' pakt Android het launcher-icoon wit-op-wit in de statusbar.
          icon: 'ic_stat_ons_moment',
          // Peach-tint (matcht app-huisstijl) op het monochrome icoon.
          color: '#FF9B71',
        },
      },
      data: { momentId },
    };

    // 6. Versturen.
    let response: admin.messaging.BatchResponse;
    try {
      response = await admin.messaging().sendEachForMulticast(message);
    } catch (e) {
      logger.error('sendEachForMulticast gooide exception', {
        momentId, error: String(e),
      });
      return;
    }

    logger.info('FCM verzonden', {
      momentId,
      successCount: response.successCount,
      failureCount: response.failureCount,
    });

    // 7. Dead-token cleanup — enig soort write dat de function doet,
    //    en uitsluitend op gebruikers/{uid}/apparaten/{id}. Nooit op
    //    momenten/ (zou zelf-triggering geven).
    const cleanupPromises: Promise<unknown>[] = [];
    for (let i = 0; i < response.responses.length; i++) {
      const r = response.responses[i];
      if (r.success || !r.error) continue;
      const code = r.error.code;
      if (code !== 'messaging/registration-token-not-registered' &&
          code !== 'messaging/invalid-registration-token') {
        continue;
      }
      cleanupPromises.push(
        refPerToken[i].update({
          fcmToken: admin.firestore.FieldValue.delete(),
          fcmTokenBijgewerkt: admin.firestore.FieldValue.delete(),
          fcmPlatform: admin.firestore.FieldValue.delete(),
        }).catch((e) => {
          logger.warn('cleanup faalde voor token', {
            path: refPerToken[i].path, error: String(e),
          });
        }),
      );
    }
    if (cleanupPromises.length > 0) {
      await Promise.all(cleanupPromises);
      logger.info('dead tokens opgeruimd', { aantal: cleanupPromises.length });
    }
  },
);
