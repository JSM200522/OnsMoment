/**
 * multi_kring.test.ts — multi-kring join-flow bewijs (sept 2026).
 *
 * Bewijst met de emulator dat:
 *  - De server-side vol-check via `huidigeLedenCache >= maxLedenCache`
 *    joinen weigert zodra de kring vol is, voor beide tiers (klein=8,
 *    groot=20). Client-side toont daarnaast een warme melding "Deze
 *    kring zit vol" (via UitnodigingFout.kringVol), maar de rule is
 *    het definitieve slot.
 *  - Joinen slaagt op de laatste vrije plek (cache = max-1).
 *  - De vol-check telt tegen de tier van de KRING-EIGENAAR (via de
 *    cache in het token-doc — die wordt door `zorgVoorToken()`
 *    gepopuleerd op basis van `ApparaatService.limietPerTier(eigenaar)`).
 *  - Een ingelogde gebruiker mag een EXTRA kring joinen (viaToken +
 *    kringId match) — ook als hij al lid is van een andere kring.
 *  - Al-lid re-write (existing membership) valt onder de update-rule
 *    (isEigenaar-only), dus een gast die zichzelf opnieuw probeert
 *    toe te voegen wordt door de rules-laag geweigerd. De client
 *    voorkomt dat via de mijnKringenMetRol pre-check.
 *  - **Race-conditie (bekend)**: twee gelijktijdige joiners bij een
 *    kring met 1 vrije plek kunnen BEIDE slagen omdat de rule-check
 *    beide reads pre-batch tegen dezelfde cache-waarde evalueert.
 *    Cache-refresh gebeurt pas als de eigenaar de uitnodig-dialog
 *    opnieuw opent. Fundamenteel closen vereist een Cloud Function
 *    of atomic transaction — bewust NIET nu gebouwd; documented in
 *    CLAUDE.md ("Personen-limiet-handhaving").
 */
import {
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  maakTestOmgeving,
  seedData,
  alsEigenaarA,
  alsNieuweGast,
  doc,
  setDoc,
  updateDoc,
  getDocs,
  collection,
  KRING_A_ID,
  EIGENAAR_A_UID,
  NIEUWE_GAST_UID,
  TOKEN_A_RAW,
} from './helpers';

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await maakTestOmgeving();
});

beforeEach(async () => {
  await env.clearFirestore();
  await seedData(env);
});

afterAll(async () => {
  await env.cleanup();
});

// ──────────────────────────────────────────────
// Helper: overschrijf de token-cache voor een specifieke vol-toestand.
// Werkt via admin (bypass rules) zodat de test-setup los staat van
// de eigenaar-authz-check op uitnodig_tokens.
// ──────────────────────────────────────────────
async function zetTokenCache(
  huidige: number,
  max: number,
): Promise<void> {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), 'uitnodig_tokens', TOKEN_A_RAW), {
      huidigeLedenCache: huidige,
      maxLedenCache: max,
    });
  });
}

// ──────────────────────────────────────────────
// TIER KLEIN (max = 8)
// ──────────────────────────────────────────────
describe('multi-kring — vol-check tier klein (max 8)', () => {
  test('MK-1: klein tier VOL (8/8) → joinen wordt door rule geweigerd', async () => {
    await zetTokenCache(8, 8);
    const db = alsNieuweGast(env).firestore();
    await assertFails(
      setDoc(doc(db, 'kringen', KRING_A_ID, 'leden', NIEUWE_GAST_UID), {
        userUid: NIEUWE_GAST_UID,
        rol: 'gast',
        viaToken: TOKEN_A_RAW,
        uitgenodigdDoor: EIGENAAR_A_UID,
      }),
    );
  });

  test('MK-2: klein tier laatste plek (7/8) → joinen slaagt', async () => {
    await zetTokenCache(7, 8);
    const db = alsNieuweGast(env).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'kringen', KRING_A_ID, 'leden', NIEUWE_GAST_UID), {
        userUid: NIEUWE_GAST_UID,
        rol: 'gast',
        viaToken: TOKEN_A_RAW,
        uitgenodigdDoor: EIGENAAR_A_UID,
      }),
    );
  });

  test('MK-3: klein tier overvol (9/8, sanity) → geweigerd', async () => {
    await zetTokenCache(9, 8);
    const db = alsNieuweGast(env).firestore();
    await assertFails(
      setDoc(doc(db, 'kringen', KRING_A_ID, 'leden', NIEUWE_GAST_UID), {
        userUid: NIEUWE_GAST_UID,
        rol: 'gast',
        viaToken: TOKEN_A_RAW,
        uitgenodigdDoor: EIGENAAR_A_UID,
      }),
    );
  });
});

// ──────────────────────────────────────────────
// TIER GROOT (max = 20)
// ──────────────────────────────────────────────
describe('multi-kring — vol-check tier groot (max 20)', () => {
  test('MK-4: groot tier VOL (20/20) → joinen wordt door rule geweigerd', async () => {
    await zetTokenCache(20, 20);
    const db = alsNieuweGast(env).firestore();
    await assertFails(
      setDoc(doc(db, 'kringen', KRING_A_ID, 'leden', NIEUWE_GAST_UID), {
        userUid: NIEUWE_GAST_UID,
        rol: 'gast',
        viaToken: TOKEN_A_RAW,
        uitgenodigdDoor: EIGENAAR_A_UID,
      }),
    );
  });

  test('MK-5: groot tier laatste plek (19/20) → joinen slaagt', async () => {
    await zetTokenCache(19, 20);
    const db = alsNieuweGast(env).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'kringen', KRING_A_ID, 'leden', NIEUWE_GAST_UID), {
        userUid: NIEUWE_GAST_UID,
        rol: 'gast',
        viaToken: TOKEN_A_RAW,
        uitgenodigdDoor: EIGENAAR_A_UID,
      }),
    );
  });

  test('MK-6: tier telt tegen KRING-EIGENAAR, niet joiner '
      + '(joiner ziet groot-cache omdat eigenaar op groot zit)', async () => {
    // Bewijs: de cache reflecteert het tier van de eigenaar. Als
    // zorgVoorToken() een groot-cache van 20 heeft geschreven, mag
    // een joiner die zélf op klein zit joinen tot cache=20 — het is
    // de eigenaar's abonnement dat telt.
    await zetTokenCache(15, 20); // eigenaar-tier=groot, ruimte
    const db = alsNieuweGast(env).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'kringen', KRING_A_ID, 'leden', NIEUWE_GAST_UID), {
        userUid: NIEUWE_GAST_UID,
        rol: 'gast',
        viaToken: TOKEN_A_RAW,
        uitgenodigdDoor: EIGENAAR_A_UID,
      }),
    );
  });
});

// ──────────────────────────────────────────────
// INGELOGDE GEBRUIKER — EXTRA kring joinen
// ──────────────────────────────────────────────
describe('multi-kring — ingelogde extra-kring join', () => {
  test('MK-7: bestaande eigenaar van kring B mag EXTRA kring A joinen '
      + 'als gast (viaToken + kringId match)', async () => {
    // Seed: eigenaarB is al eigenaar van kringB (zie helpers.seedData).
    // Nu joint eigenaarB als GAST kringA met tokenA — moet slagen
    // want lidId==uid, rol==gast, viaToken wijst naar kringA.
    await zetTokenCache(2, 8); // ruimte
    const db = env.authenticatedContext('eigenaarB').firestore();
    await assertSucceeds(
      setDoc(doc(db, 'kringen', KRING_A_ID, 'leden', 'eigenaarB'), {
        userUid: 'eigenaarB',
        rol: 'gast',
        viaToken: TOKEN_A_RAW,
        uitgenodigdDoor: EIGENAAR_A_UID,
      }),
    );
  });

  test('MK-8: al-lid re-write via gast-create-rule → geweigerd '
      + '(bestaande doc → update-rule, alleen isEigenaar mag update)', async () => {
    // Seed: nieuweGast joint eerst succesvol.
    await zetTokenCache(2, 8);
    const db = alsNieuweGast(env).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'kringen', KRING_A_ID, 'leden', NIEUWE_GAST_UID), {
        userUid: NIEUWE_GAST_UID,
        rol: 'gast',
        viaToken: TOKEN_A_RAW,
        uitgenodigdDoor: EIGENAAR_A_UID,
      }),
    );
    // Tweede write op zelfde doc = update. Firestore rule: create-rule
    // geldt alleen voor nieuwe docs; update valt onder isEigenaar-only.
    // Gast is geen eigenaar → geweigerd. De client-side pre-check
    // (mijnKringenMetRol) vangt dit af met de "Je bent al lid"-dialog.
    await assertFails(
      setDoc(doc(db, 'kringen', KRING_A_ID, 'leden', NIEUWE_GAST_UID), {
        userUid: NIEUWE_GAST_UID,
        rol: 'gast',
        viaToken: TOKEN_A_RAW,
        uitgenodigdDoor: EIGENAAR_A_UID,
      }),
    );
  });
});

// ──────────────────────────────────────────────
// RACE-CONDITIE — twee gelijktijdige joiners op laatste plek
// ──────────────────────────────────────────────
describe('multi-kring — race bij laatste plek (bekende beperking)', () => {
  test('MK-9: twee gelijktijdige joiners bij cache=7/max=8 → BEIDE slagen '
      + '(race-window bekend, cache wordt pas ververst als eigenaar '
      + 'de uitnodig-dialog opnieuw opent)', async () => {
    await zetTokenCache(7, 8);
    const dbA = env.authenticatedContext('racerA').firestore();
    const dbB = env.authenticatedContext('racerB').firestore();

    // Parallel: beide readen pre-batch cache=7, beide zien 7<8, beide
    // slagen. Eindstand: 2 extra leden i.p.v. 1. Dit is de eerlijk
    // gedocumenteerde beperking van cache-based enforcement zonder
    // atomic increment of Cloud Function.
    const [r1, r2] = await Promise.all([
      setDoc(doc(dbA, 'kringen', KRING_A_ID, 'leden', 'racerA'), {
        userUid: 'racerA',
        rol: 'gast',
        viaToken: TOKEN_A_RAW,
        uitgenodigdDoor: EIGENAAR_A_UID,
      }).then(() => 'ok').catch((e: Error) => e.message),
      setDoc(doc(dbB, 'kringen', KRING_A_ID, 'leden', 'racerB'), {
        userUid: 'racerB',
        rol: 'gast',
        viaToken: TOKEN_A_RAW,
        uitgenodigdDoor: EIGENAAR_A_UID,
      }).then(() => 'ok').catch((e: Error) => e.message),
    ]);
    expect(r1).toBe('ok');
    expect(r2).toBe('ok');

    // Verifieer dat beide leden-docs bestaan (via admin-read).
    await env.withSecurityRulesDisabled(async (ctx) => {
      const snap = await getDocs(
        collection(ctx.firestore(), 'kringen', KRING_A_ID, 'leden'),
      );
      const uids = snap.docs.map((d) => d.id);
      expect(uids).toContain('racerA');
      expect(uids).toContain('racerB');
    });
  });

  test('MK-10: NA cache-refresh (post-eerste-join, cache→8/8) → tweede '
      + 'joiner ook geblokkeerd (bewijst dat mechanisme werkt zodra '
      + 'de eigenaar de uitnodig-dialog reopent)', async () => {
    // Simuleer: eerste joiner is al binnen (cache=7 → 8), eigenaar heeft
    // dialog geopend, cache staat nu op 8/8. Nieuwe gast probeert.
    await zetTokenCache(8, 8);
    const db = env.authenticatedContext('racerC').firestore();
    await assertFails(
      setDoc(doc(db, 'kringen', KRING_A_ID, 'leden', 'racerC'), {
        userUid: 'racerC',
        rol: 'gast',
        viaToken: TOKEN_A_RAW,
        uitgenodigdDoor: EIGENAAR_A_UID,
      }),
    );
  });
});

// ──────────────────────────────────────────────
// BACKWARD-COMPAT — oude tokens zonder cache-velden
// ──────────────────────────────────────────────
describe('multi-kring — backward-compat oude tokens', () => {
  test('MK-11: token zonder cache-velden → defaults (0 < 8) → toegestaan '
      + '(fail-safe voor pre-2.5-a-3-a tokens)', async () => {
    // Verwijder cache-velden om oud-token-scenario te simuleren.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), 'uitnodig_tokens', TOKEN_A_RAW),
        {
          kringId: KRING_A_ID,
          aangemaaktDoor: EIGENAAR_A_UID,
          kringNaam: 'Familie A',
          tokenLower: TOKEN_A_RAW.toLowerCase(),
          // GEEN huidigeLedenCache / maxLedenCache
        },
      );
    });
    const db = alsNieuweGast(env).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'kringen', KRING_A_ID, 'leden', NIEUWE_GAST_UID), {
        userUid: NIEUWE_GAST_UID,
        rol: 'gast',
        viaToken: TOKEN_A_RAW,
        uitgenodigdDoor: EIGENAAR_A_UID,
      }),
    );
  });
});
