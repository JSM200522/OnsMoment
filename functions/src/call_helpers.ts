/**
 * Gedeelde security-helpers voor de video-callables.
 *
 * getVideoCallToken (V2-0) en startVideoCall (V2) moeten allebei
 * dezelfde security-lat hanteren: rate-limit per uid, apparaat-verify
 * onder de auth-uid, en kring-membership-check. Deze file bundelt die
 * checks zodat er één plek is om ze te wijzigen — twee callables die
 * onbedoeld uit sync raken zou een dun-dun-dunn-moment zijn.
 *
 * Alle helpers gooien `HttpsError` met een client-vriendelijke NL-
 * boodschap; de callable-caller propageert dat via de standaard
 * Firebase Functions-mechanismen.
 */

import * as admin from 'firebase-admin';
import { HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';

export const MODUS_TEST = 'test';
export const MODUS_GESPREK = 'gesprek';

/**
 * Bovengrens voor identifiers uit client-payload. Beschermt tegen
 * log-flooding of ongeldige LiveKit-JWTs door absurd lange strings;
 * ruim boven wat DeviceModusService/KringService.genereerKringId
 * ooit produceren (Firestore auto-IDs zijn 20 chars).
 */
export const MAX_ID_LEN = 128;

/**
 * Rate-limit: max RATE_LIMIT_MAX requests per uid per rollend
 * RATE_LIMIT_WINDOW_MS venster. Genoeg voor normale kring-flows
 * (bellen + accepteren + retry = ~5 requests) en tegelijk beperkend
 * genoeg om spam-misbruik zichtbaar te maken. De teller staat op één
 * doc per uid zodat álle video-callables gezamenlijk begrensd zijn —
 * anders zou een aanvaller getVideoCallToken en startVideoCall
 * afwisselen om onder de threshold te blijven.
 */
export const RATE_LIMIT_WINDOW_MS = 60_000;
export const RATE_LIMIT_MAX = 10;

/**
 * Verwerkt de rate-limit-teller voor deze uid in één Firestore-
 * transactie. Bij overschrijding gooit-ie HttpsError('resource-
 * exhausted') zonder de teller verder op te hogen (transaction schrijft
 * pas onder de threshold — de exception verhindert de tx.set-write).
 *
 * expireAt is een Timestamp op windowStart+60s. Firestore's TTL-policy
 * ruimt verlaten docs op zodra Joshua handmatig de policy zet in
 * Console (Firestore → TTL → collection group 'rate_limits', field
 * 'expireAt').
 */
export async function verwerkRateLimit(
  db: admin.firestore.Firestore,
  uid: string,
): Promise<void> {
  const nowMs = Date.now();
  const ref = db.collection('rate_limits').doc(uid);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const raw = snap.data() ?? {};
    const prevStart = typeof raw.windowStartMs === 'number'
      ? raw.windowStartMs : null;
    const prevCount = typeof raw.count === 'number' ? raw.count : 0;
    const inWindow =
      prevStart !== null && nowMs - prevStart < RATE_LIMIT_WINDOW_MS;
    const windowStartMs = inWindow ? prevStart : nowMs;
    const count = (inWindow ? prevCount : 0) + 1;
    if (count > RATE_LIMIT_MAX) {
      logger.warn('rate-limit overschreden', {
        uid, count, windowStartMs, windowSizeMs: RATE_LIMIT_WINDOW_MS,
      });
      throw new HttpsError('resource-exhausted',
        'Te veel token-verzoeken; probeer over een minuut opnieuw');
    }
    tx.set(ref, {
      windowStartMs,
      count,
      expireAt: admin.firestore.Timestamp.fromMillis(
        windowStartMs + RATE_LIMIT_WINDOW_MS,
      ),
    });
  });
}

/**
 * Verifieert dat het gegeven apparaat-doc bestaat onder deze uid.
 * Bewijs dat de aanvrager écht toegang heeft tot dit apparaat en
 * voorkomt dat iemand met identity={andermans-appId} spookt.
 *
 * Retourneert de snapshot zodat callers direct verdere velden kunnen
 * lezen (bv. persoonsNaam voor de callerName in de FCM-payload).
 */
export async function verifyApparaatOnderUid(
  db: admin.firestore.Firestore,
  uid: string,
  apparaatId: string,
): Promise<admin.firestore.DocumentSnapshot> {
  const ref = db
    .collection('gebruikers').doc(uid)
    .collection('apparaten').doc(apparaatId);
  const snap = await ref.get();
  if (!snap.exists) {
    logger.warn('apparaat niet gevonden onder deze uid', { uid, apparaatId });
    throw new HttpsError('permission-denied',
      'Apparaat hoort niet bij dit account');
  }
  return snap;
}

/**
 * Verifieert dat [uid] lid is van [kringId]. Bewijs via leden-
 * subcollectie (V9-schema) of eigenaarUid op de kring-doc (V7/V8-
 * fallback). Parallel-fetch — 2 reads, trivial in kosten.
 *
 * Retourneert de kring-snapshot zodat callers eventueel verdere velden
 * kunnen lezen (bv. naam voor logging of kring-eigenaarUid voor het
 * opzoeken van het doel-apparaat).
 */
export async function verifyKringMembership(
  db: admin.firestore.Firestore,
  uid: string,
  kringId: string,
): Promise<admin.firestore.DocumentSnapshot> {
  const kringRef = db.collection('kringen').doc(kringId);
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
  return kringSnap;
}

/**
 * Validator: gooit HttpsError('invalid-argument') bij niet-string of
 * lengte-overschrijding. Retourneert het gevalideerde veld zodat de
 * caller z'n type-narrowing houdt.
 */
export function eisIdString(veld: unknown, veldNaam: string): string {
  if (typeof veld !== 'string' || veld.length === 0
      || veld.length > MAX_ID_LEN) {
    throw new HttpsError('invalid-argument', `${veldNaam} ongeldig`);
  }
  return veld;
}

// ─────────────────────────────────────────────────────────────────────
// BEL-R3: bezet-slot per ontvanger (voorkomt dubbel-bellen)
// ─────────────────────────────────────────────────────────────────────

/**
 * TTL voor een actief-gesprek-reservering. 5 min is ruim genoeg voor de
 * meest voorkomende gesprekslengte + wat marge; te veel is niet erg omdat
 * cancel/hangup het slot direct opruimen. TTL is enkel het vangnet voor
 * app-crashes en netwerkverlies zodat een 2e beller nooit permanent
 * geblokkeerd raakt.
 */
export const BEZET_SLOT_TTL_MS = 5 * 60 * 1000;

/**
 * Firestore-doc voor de bezet-check. Sleutel = ontvangerApparaatId zodat
 * de check-and-reserve atomisch kan met één get+set in een transactie.
 * Één ontvanger = één actieve call.
 */
function bezetSlotRef(
  db: admin.firestore.Firestore,
  ontvangerApparaatId: string,
): admin.firestore.DocumentReference {
  return db.collection('actieveGesprekken').doc(ontvangerApparaatId);
}

/**
 * BEL-R3: reserveer een bezet-slot voor deze ontvanger, of throw met
 * bellerNaam als er al iemand actief is. Uitgevoerd als transactie zodat
 * twee gelijktijdige startVideoCall-verzoeken elkaar niet inhalen.
 *
 * Bij bezet gooit-ie `HttpsError('failed-precondition', ...)` met details
 * `{ code: 'ontvanger_in_gesprek', bellerNaam }` — de client kan hierop
 * matchen om een specifieke NL-dialog te tonen i.p.v. de generieke tekst.
 *
 * Stale-detectie: als een bestaand slot `expireAt <= now` heeft, wordt het
 * behandeld als vrij en simpelweg overschreven met de nieuwe reservering.
 * Dit is de TTL-vangnet-branch (voor het geval dat cancel/hangup faalde).
 */
export async function reserveerBezetSlot(
  db: admin.firestore.Firestore,
  ontvangerApparaatId: string,
  params: {
    callId: string;
    bellerNaam: string;
    bellerApparaatId: string;
    kringId: string;
  },
): Promise<void> {
  const nowMs = Date.now();
  const ref = bezetSlotRef(db, ontvangerApparaatId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists) {
      const raw = snap.data() ?? {};
      const expireAt = raw.expireAt as admin.firestore.Timestamp | undefined;
      const nogGeldig =
        expireAt !== undefined
        && typeof expireAt.toMillis === 'function'
        && expireAt.toMillis() > nowMs;
      if (nogGeldig) {
        const bestaandeBellerNaam =
          typeof raw.bellerNaam === 'string' && raw.bellerNaam.length > 0
            ? raw.bellerNaam
            : 'iemand anders';
        // Details worden door de HTTPS-callable client (Flutter's
        // FirebaseFunctionsException.details) integraal doorgestuurd,
        // zodat de UI-tekst zonder message-parsing kan werken.
        logger.info('bezet-slot geblokkeerd', {
          ontvangerApparaatId,
          bestaandeBeller: bestaandeBellerNaam,
          bestaandeCallId: raw.callId ?? null,
          nieuweCallId: params.callId,
        });
        throw new HttpsError(
          'failed-precondition',
          `Er is al iemand in gesprek met de ontvanger (${bestaandeBellerNaam})`,
          {
            code: 'ontvanger_in_gesprek',
            bellerNaam: bestaandeBellerNaam,
          },
        );
      }
      // Stale doc — TTL zou dit ook opruimen maar we mogen 'm meteen
      // overschrijven zonder te wachten.
      logger.info('bezet-slot verlopen, overschreven', {
        ontvangerApparaatId,
        vorigeCallId: raw.callId ?? null,
      });
    }
    tx.set(ref, {
      callId: params.callId,
      bellerNaam: params.bellerNaam,
      bellerApparaatId: params.bellerApparaatId,
      kringId: params.kringId,
      startTs: admin.firestore.Timestamp.fromMillis(nowMs),
      expireAt: admin.firestore.Timestamp.fromMillis(nowMs + BEZET_SLOT_TTL_MS),
    });
  });
}

/**
 * BEL-R3: rollback voor reserveerBezetSlot bij falen tussen reservering
 * en succesvolle FCM. Verwijdert alleen als de callId matcht — zo kan een
 * late rollback nooit een verse reservering wegvegen.
 *
 * Ook aangeroepen door cancelVideoCall + de client-side hangup-cleanup.
 * Fail-soft: elke fout in Firestore laten we logs — het gesprek is dan
 * al voorbij aan de andere kant en de TTL-vangnet houdt het schoon.
 */
export async function verwijderBezetSlotAls(
  db: admin.firestore.Firestore,
  ontvangerApparaatId: string,
  callId: string,
): Promise<void> {
  const ref = bezetSlotRef(db, ontvangerApparaatId);
  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return;
      const raw = snap.data() ?? {};
      if (raw.callId !== callId) {
        // Andere call heeft ondertussen de plek ingenomen — laat staan.
        logger.info('bezet-slot niet verwijderd (callId mismatch)', {
          ontvangerApparaatId,
          bewaardeCallId: raw.callId ?? null,
          gevraagdeCallId: callId,
        });
        return;
      }
      tx.delete(ref);
    });
  } catch (e) {
    logger.warn('verwijderBezetSlotAls faalde (niet blocking)', {
      ontvangerApparaatId, callId, error: String(e),
    });
  }
}
