/**
 * aanval.test.ts — alle aanvallen die MOETEN falen.
 * Buitenstaander/ongeauthentiseerd/verkeerde-kring-pogingen.
 */
import {
  assertFails,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  maakTestOmgeving,
  seedData,
  alsEigenaarA,
  alsLidA,
  alsEigenaarB,
  alsOnbekend,
  alsGast,
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  addDoc,
  collection,
  getDocs,
  collectionGroup,
  query,
  where,
  EIGENAAR_A_UID,
  LID_A_UID,
  EIGENAAR_B_UID,
  KRING_A_ID,
  KRING_B_ID,
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
// NIET INGELOGD (gast)
// ──────────────────────────────────────────────
describe('niet ingelogd', () => {
  test('A1: gast leest kringA', async () => {
    const db = alsGast(env).firestore();
    await assertFails(getDoc(doc(db, 'kringen', KRING_A_ID)));
  });

  test('A2: gast leest momentA', async () => {
    const db = alsGast(env).firestore();
    await assertFails(getDoc(doc(db, 'momenten', 'momentA')));
  });

  test('A3: gast leest dagA', async () => {
    const db = alsGast(env).firestore();
    await assertFails(getDoc(doc(db, 'dagelijkse_momenten', 'dagA')));
  });

  test('A4: gast leest notitieA', async () => {
    const db = alsGast(env).firestore();
    await assertFails(getDoc(doc(db, 'notities', 'notitieA')));
  });

  test('A5: gast schrijft naar momenten', async () => {
    const db = alsGast(env).firestore();
    await assertFails(
      addDoc(collection(db, 'momenten'), {
        kringId: KRING_A_ID,
        type: 'tekst',
      })
    );
  });
});

// ──────────────────────────────────────────────
// INGELOGD MAAR GEEN LID VAN ENIGE KRING
// ──────────────────────────────────────────────
describe('ingelogd maar geen kring-lid', () => {
  test('A6: onbekende gebruiker leest kringA', async () => {
    const db = alsOnbekend(env).firestore();
    await assertFails(getDoc(doc(db, 'kringen', KRING_A_ID)));
  });

  test('A7: onbekende gebruiker leest momentA', async () => {
    const db = alsOnbekend(env).firestore();
    await assertFails(getDoc(doc(db, 'momenten', 'momentA')));
  });

  test('A8: onbekende gebruiker schrijft naar dagelijkse_momenten', async () => {
    const db = alsOnbekend(env).firestore();
    await assertFails(
      addDoc(collection(db, 'dagelijkse_momenten'), {
        kringId: KRING_A_ID,
        label: 'Aanval',
      })
    );
  });
});

// ──────────────────────────────────────────────
// CROSS-FAMILY: eigenaarB probeert data van kringA te lezen
// ──────────────────────────────────────────────
describe('cross-family lezen (eigenaarB → kringA)', () => {
  test('A9: eigenaarB leest kringA', async () => {
    const db = alsEigenaarB(env).firestore();
    await assertFails(getDoc(doc(db, 'kringen', KRING_A_ID)));
  });

  test('A10: eigenaarB leest leden van kringA', async () => {
    const db = alsEigenaarB(env).firestore();
    await assertFails(
      getDocs(collection(db, 'kringen', KRING_A_ID, 'leden'))
    );
  });

  test('A11: eigenaarB leest momentA (kring-A content)', async () => {
    const db = alsEigenaarB(env).firestore();
    await assertFails(getDoc(doc(db, 'momenten', 'momentA')));
  });

  test('A12: eigenaarB leest dagA', async () => {
    const db = alsEigenaarB(env).firestore();
    await assertFails(getDoc(doc(db, 'dagelijkse_momenten', 'dagA')));
  });

  test('A13: eigenaarB leest geplandA', async () => {
    const db = alsEigenaarB(env).firestore();
    await assertFails(getDoc(doc(db, 'gepland_momenten', 'geplandA')));
  });

  test('A14: eigenaarB leest notitieA', async () => {
    const db = alsEigenaarB(env).firestore();
    await assertFails(getDoc(doc(db, 'notities', 'notitieA')));
  });
});

// ──────────────────────────────────────────────
// CROSS-FAMILY SCHRIJVEN
// ──────────────────────────────────────────────
describe('cross-family schrijven (aanvallen op kringA data)', () => {
  test('A15: eigenaarB schrijft moment met kringId=kringA (data-injectie)', async () => {
    const db = alsEigenaarB(env).firestore();
    await assertFails(
      addDoc(collection(db, 'momenten'), {
        kringId: KRING_A_ID,
        type: 'tekst',
        tekstBericht: 'Aanval vanuit Familie B',
      })
    );
  });

  test('A16: eigenaarB update kringA', async () => {
    const db = alsEigenaarB(env).firestore();
    await assertFails(
      updateDoc(doc(db, 'kringen', KRING_A_ID), { naam: 'Gekaapt' })
    );
  });

  test('A17: eigenaarB verwijdert momentA', async () => {
    const db = alsEigenaarB(env).firestore();
    await assertFails(deleteDoc(doc(db, 'momenten', 'momentA')));
  });

  test('A18: eigenaarB voegt lid toe aan kringA', async () => {
    const db = alsEigenaarB(env).firestore();
    await assertFails(
      setDoc(doc(db, 'kringen', KRING_A_ID, 'leden', 'infiltrant'), {
        userUid: 'infiltrant',
        rol: 'lid',
        kringId: KRING_A_ID,
      })
    );
  });

  test('A19: eigenaarA injecteert dagelijks moment in kringB', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertFails(
      addDoc(collection(db, 'dagelijkse_momenten'), {
        kringId: KRING_B_ID,
        label: 'Aanval in B',
      })
    );
  });
});

// ──────────────────────────────────────────────
// LID-ESCALATIE: lidA probeert eigenaar-acties
// ──────────────────────────────────────────────
describe('lid-escalatie (lidA probeert eigenaar-acties in kringA)', () => {
  test('A20: lidA update kringA instellingen', async () => {
    const db = alsLidA(env).firestore();
    await assertFails(
      updateDoc(doc(db, 'kringen', KRING_A_ID), { naam: 'Door lid gewijzigd' })
    );
  });

  test('A21: lidA zet autoAnswer aan (eigenaar-only instelling)', async () => {
    const db = alsLidA(env).firestore();
    await assertFails(
      updateDoc(doc(db, 'kringen', KRING_A_ID), { autoAnswer: true })
    );
  });

  test('A22: lidA verwijdert kringA', async () => {
    const db = alsLidA(env).firestore();
    await assertFails(deleteDoc(doc(db, 'kringen', KRING_A_ID)));
  });

  test('A23: lidA voegt nieuw lid toe aan kringA', async () => {
    const db = alsLidA(env).firestore();
    await assertFails(
      setDoc(doc(db, 'kringen', KRING_A_ID, 'leden', 'nieuwLid'), {
        userUid: 'nieuwLid',
        rol: 'lid',
        kringId: KRING_A_ID,
      })
    );
  });

  test('A24: lidA verwijdert eigenaarA uit leden', async () => {
    const db = alsLidA(env).firestore();
    await assertFails(
      deleteDoc(doc(db, 'kringen', KRING_A_ID, 'leden', EIGENAAR_A_UID))
    );
  });
});

// ──────────────────────────────────────────────
// GEBRUIKERS-DOC: andermans doc lezen/schrijven
// ──────────────────────────────────────────────
describe('gebruikers — andermans doc', () => {
  test('A25: eigenaarB leest gebruikers-doc van eigenaarA', async () => {
    const db = alsEigenaarB(env).firestore();
    await assertFails(getDoc(doc(db, 'gebruikers', EIGENAAR_A_UID)));
  });

  test('A26: eigenaarB schrijft naar gebruikers-doc van eigenaarA', async () => {
    const db = alsEigenaarB(env).firestore();
    await assertFails(
      updateDoc(doc(db, 'gebruikers', EIGENAAR_A_UID), { naam: 'Gekaapt' })
    );
  });

  test('A27: eigenaarB leest apparaten van eigenaarA', async () => {
    const db = alsEigenaarB(env).firestore();
    await assertFails(
      getDoc(doc(db, 'gebruikers', EIGENAAR_A_UID, 'apparaten', 'app1'))
    );
  });

  test('A28: eigenaarB schrijft FCM-token op apparaat van eigenaarA', async () => {
    const db = alsEigenaarB(env).firestore();
    await assertFails(
      setDoc(doc(db, 'gebruikers', EIGENAAR_A_UID, 'apparaten', 'spy'), {
        fcmToken: 'spy_token',
      })
    );
  });
});

// ──────────────────────────────────────────────
// UID-SPOOFING: kring aanmaken met andermans eigenaarUid
// ──────────────────────────────────────────────
describe('uid-spoofing', () => {
  test('A29: eigenaarA maakt kring aan met eigenaarUid van eigenaarB', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertFails(
      addDoc(collection(db, 'kringen'), {
        eigenaarUid: EIGENAAR_B_UID,
        naam: 'Nep-kring als B',
      })
    );
  });
});

// ──────────────────────────────────────────────
// KRING-AANTALLIMIET: tierKringLimietOk() enforcement
// ──────────────────────────────────────────────
describe('kring-aantallimiet (tier-enforcement)', () => {
  test('A30: klein-tier eigenaar (kringAantal=1) probeert tweede kring aan te maken', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'gebruikers', EIGENAAR_A_UID), {
        tier: 'klein',
        kringAantal: 1,
      });
    });
    const db = alsEigenaarA(env).firestore();
    await assertFails(
      addDoc(collection(db, 'kringen'), {
        eigenaarUid: EIGENAAR_A_UID,
        naam: 'Verboden Tweede Kring',
      })
    );
  });

  test('A31: groot-tier eigenaar (kringAantal=3) probeert vierde kring aan te maken', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'gebruikers', EIGENAAR_A_UID), {
        tier: 'groot',
        kringAantal: 3,
      });
    });
    const db = alsEigenaarA(env).firestore();
    await assertFails(
      addDoc(collection(db, 'kringen'), {
        eigenaarUid: EIGENAAR_A_UID,
        naam: 'Verboden Vierde Kring',
      })
    );
  });

  test('A32: eigenaar probeert kringAantal te verlagen (teller-manipulatie via REST)', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'gebruikers', EIGENAAR_A_UID), {
        kringAantal: 2,
      });
    });
    const db = alsEigenaarA(env).firestore();
    await assertFails(
      updateDoc(doc(db, 'gebruikers', EIGENAAR_A_UID), {
        kringAantal: 0,
      })
    );
  });
});
