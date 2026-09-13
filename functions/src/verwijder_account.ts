/**
 * verwijderAccount — AVG art. 17 (recht op verwijdering) cascade.
 *
 * HTTPS-callable. Aangeroepen vanuit familie_scherm.dart → Instellingen →
 * "Account verwijderen" na dubbele bevestiging. De uid komt uit
 * request.auth — geen params.
 *
 * SCENARIO A — EIGENAAR verwijdert account
 *   Voor ELKE kring waarvan uid eigenaarUid is (in deze volgorde):
 *     - andere leden' apparaten met kringId == K (per bekende userUid uit
 *       de leden-subcollectie; die tablets worden daarna door
 *       _KringWachter uitgelogd — expliciet in UI benoemd)
 *     - subcollectie leden/*
 *     - alle momenten, dagelijkse_momenten, gepland_momenten, notities
 *       met kringId == K
 *     - uitnodig_tokens met kringId == K
 *     - kringen/{K} zelf
 *     - Storage: momenten/{K}/*, dagelijkse_audio/{K}/*,
 *       dagelijkse_media/{K}/*, profielfotos/{K}.jpg
 *   Volgorde is bewust: apparaten-cleanup gebruikt leden als bron van
 *   userUids, dus leden verwijdert NA apparaten. Voorheen (t/m 12 sept
 *   2026) deed deze functie collectionGroup('apparaten').where('kringId'),
 *   wat crashte met FAILED_PRECONDITION zonder index — vervangen door
 *   per-user subcollectie-loop (geen index nodig).
 *
 * SCENARIO B — GAST verlaat andermans kringen
 *   Voor elke membership in andermans kring (collectionGroup leden):
 *     - eigen leden-doc delete
 *     - eigen momenten/notities anonymiseren
 *       (vanNaam='Voormalig kringlid', vanApparaatId=null) — Optie X:
 *       kring-geschiedenis blijft leesbaar voor overige leden;
 *       persoonsgegeven (uid + naam) weg.
 *
 * TOT SLOT (beide scenario's)
 *   - eigen apparaten-subcollectie recursiveDelete
 *   - eigen profielfotos/<uid>.jpg
 *   - gebruikers/{uid} zelf
 *   - admin.auth().deleteUser(uid)
 *
 * Idempotent: elk pad is check-then-delete; herhaalde runs zijn veilig.
 * Timeout 540s + 512MB voor kringen met veel content.
 * Admin SDK bypasst Firestore-rules — kringAantal-lock is dus geen issue.
 */

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import * as admin from 'firebase-admin';

const BATCH_MAX = 400; // Firestore hard limit 500 — 400 als veiligheids-margin

export const verwijderAccount = onCall(
  {
    timeoutSeconds: 540,
    memory: '512MiB',
    region: 'europe-west1',
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated',
        'Je moet ingelogd zijn om je account te verwijderen.');
    }

    const db = admin.firestore();
    const bucket = admin.storage().bucket();

    logger.info('verwijderAccount START', { uid });

    // ── Scenario A ─────────────────────────────────────────
    // Eigen kringen — cascade complete kring per stuk.
    const eigenKringenSnap = await db.collection('kringen')
      .where('eigenaarUid', '==', uid).get();
    const eigenKringIds = eigenKringenSnap.docs.map((d) => d.id);
    logger.info('eigen kringen gevonden', {
      uid, aantal: eigenKringIds.length,
    });

    for (const kringId of eigenKringIds) {
      await verwijderKringCascade(db, bucket, kringId);
    }

    // ── Scenario B ─────────────────────────────────────────
    // Memberships in ANDERMANS kringen — self-leave + anonimiseren.
    const membershipsSnap = await db.collectionGroup('leden')
      .where('userUid', '==', uid).get();
    const gastKringIds: string[] = [];
    for (const doc of membershipsSnap.docs) {
      const kringId = doc.ref.parent.parent?.id;
      if (!kringId) continue;
      // Skip al-gedeleted-in-scenario-A kringen (leden-doc is dan al weg,
      // maar collectionGroup kan cache-inconsistentie geven).
      if (eigenKringIds.includes(kringId)) continue;
      gastKringIds.push(kringId);
      try {
        await doc.ref.delete();
      } catch (e) {
        logger.warn('lid-doc delete faalde (idempotent — negeren)', {
          uid, kringId, error: String(e),
        });
      }
    }
    logger.info('gast-memberships gevonden', {
      uid, aantal: gastKringIds.length,
    });

    // Anonymiseer eigen momenten/notities in gast-kringen. Firestore 'in'
    // query max 30 waarden — chunking.
    const apparatenSnap = await db.collection('gebruikers').doc(uid)
      .collection('apparaten').get();
    const apparaatIds = apparatenSnap.docs.map((d) => d.id);
    logger.info('eigen apparaten gevonden', {
      uid, aantal: apparaatIds.length,
    });

    for (const gastKringId of gastKringIds) {
      await anonymiseerInKring(db, gastKringId, apparaatIds);
    }

    // ── Tot slot: eigen data ───────────────────────────────
    // recursiveDelete verwijdert gebruikers/{uid} + alle subcollecties
    // (apparaten/*). Beter dan handmatig batch want dekt eventuele
    // toekomstige subcollecties automatisch.
    try {
      await db.recursiveDelete(db.collection('gebruikers').doc(uid));
    } catch (e) {
      logger.warn('recursiveDelete gebruikers-doc faalde', {
        uid, error: String(e),
      });
    }

    // Storage: eigen profielfoto (setup_wizard uploadt op uid-basis).
    await deleteStorageFilesByPrefix(bucket, `profielfotos/${uid}`);

    // ── Firebase Auth ──────────────────────────────────────
    try {
      await admin.auth().deleteUser(uid);
      logger.info('auth.deleteUser OK', { uid });
    } catch (e) {
      logger.error('auth.deleteUser FAALDE — Firestore data is al weg', {
        uid, error: String(e),
      });
      throw new HttpsError('internal',
        'Je gegevens zijn verwijderd, maar het uitloggen zelf mislukte. '
        + 'Sluit de app en open opnieuw.');
    }

    logger.info('verwijderAccount KLAAR', {
      uid,
      eigenKringen: eigenKringIds.length,
      gastKringen: gastKringIds.length,
      apparaten: apparaatIds.length,
    });

    return {
      success: true,
      eigenKringenVerwijderd: eigenKringIds.length,
      gastKringenVerlaten: gastKringIds.length,
    };
  },
);

// ── Helpers ──────────────────────────────────────────────────

async function verwijderKringCascade(
  db: admin.firestore.Firestore,
  bucket: ReturnType<typeof admin.storage>['bucket'] extends () => infer B
    ? B : never,
  kringId: string,
): Promise<void> {
  logger.info('verwijderKringCascade START', { kringId });

  // DEEL D (13 sept 2026): eerst leden LEZEN om userUids te verzamelen.
  // Voorheen deden we `db.collectionGroup('apparaten').where('kringId')`
  // om cross-user apparaten op te ruimen — dat crashte met
  // FAILED_PRECONDITION omdat er geen collection-group-index bestaat op
  // apparaten.kringId (en er is geen firestore.indexes.json in de repo
  // om er één te definieren). Nieuwe aanpak: itereer per bekend
  // lidmaatschap door hun eigen apparaten-subcollectie — dat is een
  // gewone subcollectie-query per parent en vereist géén index.
  const ledenRef = db.collection('kringen').doc(kringId)
    .collection('leden');
  const ledenSnap = await ledenRef.get();
  const lidUserUids = new Set<string>();
  for (const doc of ledenSnap.docs) {
    const userUid = doc.get('userUid') as string | undefined;
    if (userUid && userUid.length > 0) lidUserUids.add(userUid);
  }
  logger.info('leden gevonden voor apparaten-cleanup', {
    kringId, aantal: lidUserUids.size,
  });

  // Per bekende lid: eigen apparaten-subcollectie waar kringId == deze
  // kring. Dat is een gewone parent-scoped query — subcollectie-index
  // op kringId is automatisch aanwezig via de single-field-index-mode
  // van Firestore.
  //
  // Edge-case: gast die zich zelf al uit de kring had verwijderd (dus
  // geen leden-doc meer) laat mogelijk een apparaat-doc met kringId
  // achter. Die wordt niet door deze cleanup gedekt — maar het is een
  // orphan die niets meer kan doen (client-side _KringWachter logt 'm
  // toch al uit, en de gast heeft geen leestoegang op deze kring meer).
  // Wachten op de eigenaar-account-delete: geen crisis, wél cleanup-
  // schuld die ooit via een periodieke sweep op orphan-apparaten kan.
  for (const lidUid of lidUserUids) {
    const appSnap = await db.collection('gebruikers').doc(lidUid)
      .collection('apparaten').where('kringId', '==', kringId).get();
    if (appSnap.empty) continue;
    logger.info('apparaten van lid verwijderen', {
      kringId, lidUid, aantal: appSnap.docs.length,
    });
    await verwijderDocsInBatches(db, appSnap.docs);
  }

  // NU pas leden-subcollectie verwijderen. Volgorde is bewust: we
  // hebben de userUids uit deze collectie nodig vóór delete.
  await verwijderDocsInBatches(db, ledenSnap.docs);

  // content-collecties (kringId is een top-level veld)
  for (const coll of [
    'momenten', 'dagelijkse_momenten', 'gepland_momenten', 'notities',
  ]) {
    await verwijderQueryInBatches(db,
      db.collection(coll).where('kringId', '==', kringId));
  }

  // uitnodig_tokens
  await verwijderQueryInBatches(db,
    db.collection('uitnodig_tokens').where('kringId', '==', kringId));

  // kring-doc zelf
  try {
    await db.collection('kringen').doc(kringId).delete();
  } catch (e) {
    logger.warn('kring-doc delete faalde (idempotent — negeren)', {
      kringId, error: String(e),
    });
  }

  // Storage
  await deleteStorageFilesByPrefix(bucket, `momenten/${kringId}/`);
  await deleteStorageFilesByPrefix(bucket, `dagelijkse_audio/${kringId}/`);
  await deleteStorageFilesByPrefix(bucket, `dagelijkse_media/${kringId}/`);
  await deleteStorageFilesByPrefix(bucket, `profielfotos/${kringId}`);

  logger.info('verwijderKringCascade KLAAR', { kringId });
}

async function verwijderQueryInBatches(
  db: admin.firestore.Firestore,
  query: admin.firestore.Query,
): Promise<void> {
  const snap = await query.get();
  await verwijderDocsInBatches(db, snap.docs);
}

async function verwijderDocsInBatches(
  db: admin.firestore.Firestore,
  docs: admin.firestore.QueryDocumentSnapshot[],
): Promise<void> {
  if (docs.length === 0) return;
  let batch = db.batch();
  let count = 0;
  for (const doc of docs) {
    batch.delete(doc.ref);
    count++;
    if (count % BATCH_MAX === 0) {
      await batch.commit();
      batch = db.batch();
    }
  }
  if (count % BATCH_MAX !== 0) {
    await batch.commit();
  }
}

async function anonymiseerInKring(
  db: admin.firestore.Firestore,
  kringId: string,
  apparaatIds: string[],
): Promise<void> {
  if (apparaatIds.length === 0) return;
  const CHUNK = 30; // Firestore 'in'-query max
  for (let i = 0; i < apparaatIds.length; i += CHUNK) {
    const chunk = apparaatIds.slice(i, i + CHUNK);
    if (chunk.length === 0) continue;
    for (const coll of ['momenten', 'notities']) {
      const snap = await db.collection(coll)
        .where('kringId', '==', kringId)
        .where('vanApparaatId', 'in', chunk)
        .get();
      if (snap.empty) continue;
      let batch = db.batch();
      let count = 0;
      for (const doc of snap.docs) {
        batch.update(doc.ref, {
          vanNaam: 'Voormalig kringlid',
          vanApparaatId: null,
        });
        count++;
        if (count % BATCH_MAX === 0) {
          await batch.commit();
          batch = db.batch();
        }
      }
      if (count % BATCH_MAX !== 0) await batch.commit();
      logger.info('anonymiseerInKring', {
        kringId, collectie: coll, chunk_i: i, aantal: count,
      });
    }
  }
}

async function deleteStorageFilesByPrefix(
  bucket: ReturnType<typeof admin.storage>['bucket'] extends () => infer B
    ? B : never,
  prefix: string,
): Promise<void> {
  try {
    // Admin SDK bucket.deleteFiles doet automatisch pagination via
    // interne getFiles+delete loop. Force:true zodat leeg-prefix niet
    // gooit maar leeg-lijst teruggeeft.
    await bucket.deleteFiles({ prefix, force: true });
    logger.info('storage delete OK', { prefix });
  } catch (e) {
    logger.warn('storage delete faalde (idempotent — negeren)', {
      prefix, error: String(e),
    });
  }
}
