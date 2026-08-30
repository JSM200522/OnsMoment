import {
  initializeTestEnvironment,
  RulesTestEnvironment,
  RulesTestContext,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'fs';
import { join } from 'path';
import {
  collection,
  doc,
  setDoc,
  getDoc,
  getDocs,
  addDoc,
  updateDoc,
  deleteDoc,
  collectionGroup,
  query,
  where,
  DocumentData,
} from 'firebase/firestore';

// Firestore-instantie per context
export { collection, doc, setDoc, getDoc, getDocs, addDoc, updateDoc, deleteDoc, collectionGroup, query, where };
export type { DocumentData, RulesTestContext };

// ──────────────────────────────────────────────
// Test-actor-IDs (stabiele strings voor seed + auth)
// ──────────────────────────────────────────────
export const EIGENAAR_A_UID = 'eigenaarA';
export const LID_A_UID = 'lidA';
export const EIGENAAR_B_UID = 'eigenaarB';
export const ONBEKEND_UID = 'onbekend'; // ingelogd maar geen lid van enige kring
export const NIEUWE_GAST_UID = 'nieuweGast'; // ingelogd, wil joinen via token

export const KRING_A_ID = 'kringA';
export const KRING_B_ID = 'kringB';

// Uitnodig-tokens (20-char alfanumeriek zoals Firestore auto-id)
export const TOKEN_A_RAW = 'aB3cD4eF5gH6iJ7kLm8N';         // geldig, kringA
export const TOKEN_B_RAW = 'zY1xW2vU3tS4rQ5pOn6M';         // geldig, kringB
export const TOKEN_A_LOWER = TOKEN_A_RAW.toLowerCase();

// ──────────────────────────────────────────────
// Testomgeving opstarten
// ──────────────────────────────────────────────
export async function maakTestOmgeving(): Promise<RulesTestEnvironment> {
  return initializeTestEnvironment({
    projectId: 'onsmonent',
    firestore: {
      rules: readFileSync(join(__dirname, '..', 'firestore.rules'), 'utf8'),
      host: 'localhost',
      port: 8080,
    },
  });
}

// ──────────────────────────────────────────────
// Seed: schrijft alle startdata als admin (rules bypass)
// ──────────────────────────────────────────────
export async function seedData(env: RulesTestEnvironment): Promise<void> {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    // Kring A — eigenaarA + lidA
    await setDoc(doc(db, 'kringen', KRING_A_ID), {
      eigenaarUid: EIGENAAR_A_UID,
      naam: 'Familie A',
    });
    await setDoc(doc(db, 'kringen', KRING_A_ID, 'leden', EIGENAAR_A_UID), {
      userUid: EIGENAAR_A_UID,
      rol: 'eigenaar',
      kringId: KRING_A_ID,
    });
    await setDoc(doc(db, 'kringen', KRING_A_ID, 'leden', LID_A_UID), {
      userUid: LID_A_UID,
      rol: 'lid',
      kringId: KRING_A_ID,
    });

    // Kring B — eigenaarB alleen
    await setDoc(doc(db, 'kringen', KRING_B_ID), {
      eigenaarUid: EIGENAAR_B_UID,
      naam: 'Familie B',
    });
    await setDoc(doc(db, 'kringen', KRING_B_ID, 'leden', EIGENAAR_B_UID), {
      userUid: EIGENAAR_B_UID,
      rol: 'eigenaar',
      kringId: KRING_B_ID,
    });

    // Gebruiker A + apparaat
    await setDoc(doc(db, 'gebruikers', EIGENAAR_A_UID), {
      naam: 'Eigenaar A',
      email: 'eigenaarA@test.nl',
    });
    await setDoc(doc(db, 'gebruikers', EIGENAAR_A_UID, 'apparaten', 'app1'), {
      kringId: KRING_A_ID,
      naam: 'Tablet Woonkamer',
      fcmToken: 'token_a1',
    });

    // Content-docs voor kring A
    await setDoc(doc(db, 'momenten', 'momentA'), {
      kringId: KRING_A_ID,
      type: 'foto',
      mediaUrl: 'https://example.com/foto.jpg',
      verstuurdOp: new Date(),
    });
    await setDoc(doc(db, 'dagelijkse_momenten', 'dagA'), {
      kringId: KRING_A_ID,
      label: 'Goedemorgen',
      emoji: '☀️',
    });
    await setDoc(doc(db, 'gepland_momenten', 'geplandA'), {
      kringId: KRING_A_ID,
      label: 'Verjaardag',
      emoji: '🎂',
      geplandOp: new Date(),
    });
    await setDoc(doc(db, 'notities', 'notitieA'), {
      kringId: KRING_A_ID,
      tekst: 'Medicijnen om 8 uur',
    });

    // Content-docs voor kring B
    await setDoc(doc(db, 'momenten', 'momentB'), {
      kringId: KRING_B_ID,
      type: 'tekst',
      tekstBericht: 'Hallo van Familie B',
    });
    await setDoc(doc(db, 'dagelijkse_momenten', 'dagB'), {
      kringId: KRING_B_ID,
      label: 'Goedenavond',
      emoji: '🌙',
    });

    // Uitnodig-tokens — één voor elke kring, met tokenLower voor
    // case-insensitieve fallback. Token A is de "actieve" test-code.
    await setDoc(doc(db, 'uitnodig_tokens', TOKEN_A_RAW), {
      kringId: KRING_A_ID,
      aangemaaktDoor: EIGENAAR_A_UID,
      kringNaam: 'Familie A',
      kringFoto: null,
      uitnodigerNaam: 'Eigenaar A',
      huidigeLedenCache: 2,
      maxLedenCache: 8,
      tokenLower: TOKEN_A_LOWER,
    });
    await setDoc(doc(db, 'uitnodig_tokens', TOKEN_B_RAW), {
      kringId: KRING_B_ID,
      aangemaaktDoor: EIGENAAR_B_UID,
      kringNaam: 'Familie B',
      kringFoto: null,
      uitnodigerNaam: 'Eigenaar B',
      huidigeLedenCache: 1,
      maxLedenCache: 8,
      tokenLower: TOKEN_B_RAW.toLowerCase(),
    });

    // Feature-flags doc — remote CallkitFlagService leest hier vanaf.
    await setDoc(doc(db, 'config', 'features'), {
      callkitEnabled: false,
    });

    // Apparaat voor eigenaarB (voor cross-uid bel-lees-test)
    await setDoc(doc(db, 'gebruikers', EIGENAAR_B_UID), {
      naam: 'Eigenaar B',
      email: 'eigenaarB@test.nl',
    });
    await setDoc(doc(db, 'gebruikers', EIGENAAR_B_UID, 'apparaten', 'appB1'), {
      kringId: KRING_B_ID,
      naam: 'Tablet Familie B',
      fcmToken: 'token_b1',
    });
  });
}

// ──────────────────────────────────────────────
// Auth-contexten (helpers voor leesbaarheid in tests)
// ──────────────────────────────────────────────
export function alsEigenaarA(env: RulesTestEnvironment) {
  return env.authenticatedContext(EIGENAAR_A_UID);
}

export function alsLidA(env: RulesTestEnvironment) {
  return env.authenticatedContext(LID_A_UID);
}

export function alsEigenaarB(env: RulesTestEnvironment) {
  return env.authenticatedContext(EIGENAAR_B_UID);
}

export function alsOnbekend(env: RulesTestEnvironment) {
  return env.authenticatedContext(ONBEKEND_UID);
}

export function alsGast(env: RulesTestEnvironment) {
  return env.unauthenticatedContext();
}

export function alsNieuweGast(env: RulesTestEnvironment) {
  return env.authenticatedContext(NIEUWE_GAST_UID);
}
