/**
 * legitiem.test.ts — alle echte app-handelingen die MOETEN slagen.
 * Elke test weerspiegelt een daadwerkelijke query uit de Flutter-app.
 */
import {
  assertSucceeds,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  maakTestOmgeving,
  seedData,
  alsEigenaarA,
  alsLidA,
  alsEigenaarB,
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
// KRINGEN
// ──────────────────────────────────────────────
describe('kringen — lezen', () => {
  test('L1: eigenaarA leest eigen kring', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(getDoc(doc(db, 'kringen', KRING_A_ID)));
  });

  test('L2: lidA leest kringA (gewoon lid)', async () => {
    const db = alsLidA(env).firestore();
    await assertSucceeds(getDoc(doc(db, 'kringen', KRING_A_ID)));
  });
});

describe('kringen — schrijven', () => {
  test('L3: eigenaarA update kringnaam', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'kringen', KRING_A_ID), { naam: 'Nieuwe Naam' })
    );
  });

  test('L4: eigenaarA update autoAnswer (V4 videobellen-instelling)', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'kringen', KRING_A_ID), { autoAnswer: true })
    );
  });

  test('L5: eigenaarA maakt nieuwe kring aan met eigen eigenaarUid', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      addDoc(collection(db, 'kringen'), {
        eigenaarUid: EIGENAAR_A_UID,
        naam: 'Tweede Kring',
      })
    );
  });

  test('L6: eigenaarB maakt eigen kring B aan', async () => {
    const db = alsEigenaarB(env).firestore();
    await env.clearFirestore();
    await assertSucceeds(
      addDoc(collection(db, 'kringen'), {
        eigenaarUid: EIGENAAR_B_UID,
        naam: 'Familie B Nieuw',
      })
    );
  });

  test('L30: eigenaar met groot-tier (kringAantal=2) maakt derde kring aan', async () => {
    // Stel tier en teller in via admin (bypass rules)
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'gebruikers', EIGENAAR_A_UID), {
        tier: 'groot',
        kringAantal: 2,
      });
    });
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      addDoc(collection(db, 'kringen'), {
        eigenaarUid: EIGENAAR_A_UID,
        naam: 'Derde Kring',
      })
    );
  });
});

// ──────────────────────────────────────────────
// LEDEN-SUBCOLLECTIE
// ──────────────────────────────────────────────
describe('leden — lezen', () => {
  test('L7: eigenaarA leest leden-lijst van kringA', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      getDocs(collection(db, 'kringen', KRING_A_ID, 'leden'))
    );
  });

  test('L8: lidA leest eigen leden-entry', async () => {
    const db = alsLidA(env).firestore();
    await assertSucceeds(
      getDoc(doc(db, 'kringen', KRING_A_ID, 'leden', LID_A_UID))
    );
  });

  test('L9: eigenaarA collection group query — mijnKringen() patroon', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      getDocs(
        query(
          collectionGroup(db, 'leden'),
          where('userUid', '==', EIGENAAR_A_UID)
        )
      )
    );
  });

  test('L10: lidA collection group query — mijnKringen() patroon', async () => {
    const db = alsLidA(env).firestore();
    await assertSucceeds(
      getDocs(
        query(
          collectionGroup(db, 'leden'),
          where('userUid', '==', LID_A_UID)
        )
      )
    );
  });
});

describe('leden — schrijven (eigenaar)', () => {
  test('L11: eigenaarA voegt nieuw lid toe aan kringA', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'kringen', KRING_A_ID, 'leden', 'nieuwLid'), {
        userUid: 'nieuwLid',
        rol: 'lid',
        kringId: KRING_A_ID,
      })
    );
  });

  test('L12: eigenaarA verwijdert lid uit kringA', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      deleteDoc(doc(db, 'kringen', KRING_A_ID, 'leden', LID_A_UID))
    );
  });
});

// ──────────────────────────────────────────────
// MOMENTEN (verstuurde berichten)
// ──────────────────────────────────────────────
describe('momenten', () => {
  test('L13: eigenaarA leest momentA', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(getDoc(doc(db, 'momenten', 'momentA')));
  });

  test('L14: lidA leest momentA', async () => {
    const db = alsLidA(env).firestore();
    await assertSucceeds(getDoc(doc(db, 'momenten', 'momentA')));
  });

  test('L15: eigenaarA stuurt nieuw moment', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      addDoc(collection(db, 'momenten'), {
        kringId: KRING_A_ID,
        type: 'foto',
        mediaUrl: 'https://example.com/nieuw.jpg',
        verstuurdOp: new Date(),
      })
    );
  });

  test('L16: lidA stuurt ook een moment (elk lid mag sturen)', async () => {
    const db = alsLidA(env).firestore();
    await assertSucceeds(
      addDoc(collection(db, 'momenten'), {
        kringId: KRING_A_ID,
        type: 'tekst',
        tekstBericht: 'Hoi van lid A',
        verstuurdOp: new Date(),
      })
    );
  });

  test('L17: eigenaarA verwijdert momentA', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(deleteDoc(doc(db, 'momenten', 'momentA')));
  });
});

// ──────────────────────────────────────────────
// DAGELIJKSE MOMENTEN
// ──────────────────────────────────────────────
describe('dagelijkse_momenten', () => {
  test('L18: eigenaarA leest dagA', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(getDoc(doc(db, 'dagelijkse_momenten', 'dagA')));
  });

  test('L19: eigenaarA maakt nieuw dagelijks moment aan', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      addDoc(collection(db, 'dagelijkse_momenten'), {
        kringId: KRING_A_ID,
        label: 'Goedemiddag',
        emoji: '🌤️',
      })
    );
  });

  test('L20: eigenaarA update dagelijks moment', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'dagelijkse_momenten', 'dagA'), { label: 'Gewijzigd' })
    );
  });

  test('L21: eigenaarA verwijdert dagelijks moment', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(deleteDoc(doc(db, 'dagelijkse_momenten', 'dagA')));
  });
});

// ──────────────────────────────────────────────
// GEPLANDE MOMENTEN
// ──────────────────────────────────────────────
describe('gepland_momenten', () => {
  test('L22: eigenaarA leest geplandA', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(getDoc(doc(db, 'gepland_momenten', 'geplandA')));
  });

  test('L23: eigenaarA maakt gepland moment aan', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      addDoc(collection(db, 'gepland_momenten'), {
        kringId: KRING_A_ID,
        label: 'Verjaardag kleinzoon',
        emoji: '🎉',
        geplandOp: new Date(),
      })
    );
  });
});

// ──────────────────────────────────────────────
// NOTITIES
// ──────────────────────────────────────────────
describe('notities', () => {
  test('L24: eigenaarA leest notitieA', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(getDoc(doc(db, 'notities', 'notitieA')));
  });

  test('L25: eigenaarA maakt nieuwe notitie aan', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      addDoc(collection(db, 'notities'), {
        kringId: KRING_A_ID,
        tekst: 'Nieuwe herinnering',
      })
    );
  });
});

// ──────────────────────────────────────────────
// GEBRUIKERS + APPARATEN (eigen docs)
// ──────────────────────────────────────────────
describe('gebruikers', () => {
  test('L26: eigenaarA leest eigen gebruikers-doc', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(getDoc(doc(db, 'gebruikers', EIGENAAR_A_UID)));
  });

  test('L27: eigenaarA schrijft naar eigen gebruikers-doc', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'gebruikers', EIGENAAR_A_UID), { naam: 'Nieuwe Naam' })
    );
  });

  test('L28: eigenaarA leest eigen apparaat', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      getDoc(doc(db, 'gebruikers', EIGENAAR_A_UID, 'apparaten', 'app1'))
    );
  });

  test('L29: eigenaarA schrijft FCM-token op eigen apparaat', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'gebruikers', EIGENAAR_A_UID, 'apparaten', 'app2'), {
        kringId: KRING_A_ID,
        fcmToken: 'nieuw_token',
        fcmPlatform: 'android',
      })
    );
  });
});
