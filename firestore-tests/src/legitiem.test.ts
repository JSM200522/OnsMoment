/**
 * legitiem.test.ts — alle echte app-handelingen die MOETEN slagen.
 * Elke test weerspiegelt een daadwerkelijke query uit de Flutter-app.
 */
import {
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { writeBatch, serverTimestamp } from 'firebase/firestore';
import {
  maakTestOmgeving,
  seedData,
  alsEigenaarA,
  alsLidA,
  alsEigenaarB,
  alsGast,
  alsNieuweGast,
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
  NIEUWE_GAST_UID,
  KRING_A_ID,
  KRING_B_ID,
  TOKEN_A_RAW,
  TOKEN_A_LOWER,
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

  // D-1: create-rule tolereert de default 'tier: klein' die setup_wizard
  // en gast_signup_scherm bij nieuwe accounts schrijven. Abonnement mag
  // bij create niet aanwezig zijn.
  test('L27b: nieuwe gebruiker create met default tier=klein', async () => {
    const db = alsNieuweGast(env).firestore();
    await env.clearFirestore();
    await assertSucceeds(
      setDoc(doc(db, 'gebruikers', NIEUWE_GAST_UID), {
        email: 'nieuw@test.nl',
        familieNaam: 'Nieuw',
        gebruikersNaam: 'Nieuw',
        accountType: 'familie',
        tier: 'klein',
        aangemaaktOp: new Date(),
      }),
    );
  });

  // REGRESSION-GUARD: het OUDE registratie-patroon (alles in één
  // WriteBatch) MOET onder de huidige rules falen — Firestore evalueert
  // batch-writes tegen pre-batch state, dus isEigenaar/isLid op docs die
  // in dezelfde batch worden aangemaakt geven een evaluation error.
  // Deze test verandert nooit → als hij ooit stiekem gaat slagen zijn de
  // rules per ongeluk permissief gemaakt en verdient het onderzoek.
  test('L27b-bis: OUDE single-batch signup FAALT (regression-guard, mag niet stilzwijgend slagen)', async () => {
    await env.clearFirestore();
    const db = alsNieuweGast(env).firestore();
    const nieuweKringId = 'oudeSingleBatchKring';
    const batch = writeBatch(db);
    batch.set(doc(db, 'gebruikers', NIEUWE_GAST_UID), {
      email: 'nieuw@test.nl',
      familieNaam: 'Sara',
      accountType: 'familie',
      tier: 'klein',
      kringAantal: 1,
      aangemaaktOp: serverTimestamp(),
      proefStart: serverTimestamp(),
    });
    batch.set(doc(db, 'kringen', nieuweKringId), {
      eigenaarUid: NIEUWE_GAST_UID,
      naam: 'Oma',
      herkenningsgeluid: 'twinkel',
      type: 'familie',
      modus: 'vergrendeld',
      aangemaaktOp: serverTimestamp(),
    });
    batch.set(doc(db, 'kringen', nieuweKringId, 'leden', NIEUWE_GAST_UID), {
      userUid: NIEUWE_GAST_UID,
      rol: 'eigenaar',
      gejoindOp: serverTimestamp(),
      uitgenodigdDoor: null,
      weergaveNaam: 'Sara',
    });
    batch.set(doc(collection(db, 'dagelijkse_momenten')), {
      kringId: nieuweKringId,
      emoji: '☀️',
      label: 'Goedemorgen',
      uur: 8,
      minuut: 30,
      actief: true,
      aangemaaktOp: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  // KRITIEK: reproduceert de NIEUWE setup_wizard._familieRegistreren
  // registratie-flow (3 sequentiële batches). Faalt deze test → geen
  // enkele nieuwe familie-gebruiker kan een account aanmaken. LAUNCH-BLOCKER.
  test('L27b-ter: NIEUWE signup-flow (3 sequentiële batches: gebruiker+kring → leden → dagelijkse_momenten) SLAAGT', async () => {
    await env.clearFirestore();
    const db = alsNieuweGast(env).firestore();
    const nieuweKringId = 'nieuweSequentieleKring';

    // Batch A — gebruikers (create) + kringen (create).
    const batchA = writeBatch(db);
    batchA.set(doc(db, 'gebruikers', NIEUWE_GAST_UID), {
      email: 'nieuw@test.nl',
      familieNaam: 'Sara',
      gebruikersNaam: 'Sara',
      ontvangerNaam: 'Oma',
      ontvangerFoto: '',
      noodcontactNaam: '',
      noodcontactTel: '',
      herkenningsgeluid: 'twinkel',
      accountType: 'familie',
      tier: 'klein',
      kringAantal: 1,
      aangemaaktOp: serverTimestamp(),
      proefStart: serverTimestamp(),
    });
    batchA.set(doc(db, 'kringen', nieuweKringId), {
      eigenaarUid: NIEUWE_GAST_UID,
      naam: 'Oma',
      herkenningsgeluid: 'twinkel',
      type: 'familie',
      modus: 'vergrendeld',
      aangemaaktOp: serverTimestamp(),
    });
    await assertSucceeds(batchA.commit());

    // Write B — eigenaar-membership. Kring bestaat nu.
    await assertSucceeds(
      setDoc(doc(db, 'kringen', nieuweKringId, 'leden', NIEUWE_GAST_UID), {
        userUid: NIEUWE_GAST_UID,
        rol: 'eigenaar',
        gejoindOp: serverTimestamp(),
        uitgenodigdDoor: null,
        weergaveNaam: 'Sara',
      }),
    );

    // Batch C — dagelijkse_momenten. Leden-doc bestaat nu → isLid=true.
    const batchC = writeBatch(db);
    for (let i = 0; i < 4; i++) {
      batchC.set(doc(collection(db, 'dagelijkse_momenten')), {
        kringId: nieuweKringId,
        emoji: '☀️',
        label: 'Moment ' + i,
        uur: 8 + i * 3,
        minuut: 0,
        mediaType: '',
        mediaUrl: '',
        tekstBericht: '',
        actief: true,
        aangemaaktOp: serverTimestamp(),
      });
    }
    await assertSucceeds(batchC.commit());
  });

  // D-1: legitieme updates die tier/abonnement NIET raken blijven werken.
  test('L27c: eigenaarA update meerdere velden (naam+foto) zonder tier', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'gebruikers', EIGENAAR_A_UID), {
        naam: 'Andere Naam',
        ontvangerFoto: 'https://example.com/nieuw.jpg',
      }),
    );
  });

  // D-1: kringAantal verhogen (kring aanmaken) blijft toegestaan.
  test('L27d: eigenaarA verhoogt kringAantal (kring-aanmaak-scenario)', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'gebruikers', EIGENAAR_A_UID), {
        kringAantal: 1,
      });
    });
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'gebruikers', EIGENAAR_A_UID), { kringAantal: 2 }),
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

// ──────────────────────────────────────────────
// UITNODIG_TOKENS
// ──────────────────────────────────────────────
describe('uitnodig_tokens — lezen (preview)', () => {
  test('L30: gast (niet ingelogd) leest tokenA voor preview', async () => {
    const db = alsGast(env).firestore();
    await assertSucceeds(getDoc(doc(db, 'uitnodig_tokens', TOKEN_A_RAW)));
  });

  test('L31: nieuwe gast (ingelogd) leest tokenA voor preview', async () => {
    const db = alsNieuweGast(env).firestore();
    await assertSucceeds(getDoc(doc(db, 'uitnodig_tokens', TOKEN_A_RAW)));
  });

  test('L32: case-insensitive query op tokenLower slaagt', async () => {
    const db = alsNieuweGast(env).firestore();
    await assertSucceeds(
      getDocs(
        query(
          collection(db, 'uitnodig_tokens'),
          where('tokenLower', '==', TOKEN_A_LOWER),
        ),
      ),
    );
  });
});

describe('uitnodig_tokens — schrijven (eigenaar)', () => {
  test('L33: eigenaarA maakt nieuw uitnodig-token aan voor kringA', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'uitnodig_tokens', 'NieuwToken12345678AB'), {
        kringId: KRING_A_ID,
        aangemaaktDoor: EIGENAAR_A_UID,
        kringNaam: 'Familie A',
        kringFoto: null,
        uitnodigerNaam: 'Eigenaar A',
        huidigeLedenCache: 2,
        maxLedenCache: 8,
        tokenLower: 'nieuwtoken12345678ab',
      }),
    );
  });

  test('L34: eigenaarA backfilt tokenLower op bestaand token', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'uitnodig_tokens', TOKEN_A_RAW), {
        tokenLower: TOKEN_A_LOWER,
      }),
    );
  });

  test('L35: eigenaarA verwijdert eigen uitnodig-token', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      deleteDoc(doc(db, 'uitnodig_tokens', TOKEN_A_RAW)),
    );
  });
});

// ──────────────────────────────────────────────
// GAST-ACCEPT (join via uitnodig-token)
// ──────────────────────────────────────────────
describe('leden — gast-accept via token', () => {
  test('L36: nieuwe gast joint kringA met geldig tokenA', async () => {
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

  test('L37: lidA (bestaand lid) verlaat kringA (self-delete)', async () => {
    const db = alsLidA(env).firestore();
    await assertSucceeds(
      deleteDoc(doc(db, 'kringen', KRING_A_ID, 'leden', LID_A_UID)),
    );
  });
});

// ──────────────────────────────────────────────
// CONFIG — feature-flags publiek leesbaar
// ──────────────────────────────────────────────
describe('config/features — feature-flag read', () => {
  test('L39: gast (niet ingelogd) leest config/features', async () => {
    const db = alsGast(env).firestore();
    await assertSucceeds(getDoc(doc(db, 'config', 'features')));
  });

  test('L40: eigenaarA leest config/features (voor CallkitFlagService)', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(getDoc(doc(db, 'config', 'features')));
  });
});

// ──────────────────────────────────────────────
// FEEDBACK — ingelogde gebruikers mogen feedback aanmaken
// ──────────────────────────────────────────────
describe('feedback — create door ingelogde gebruikers', () => {
  test('L41: eigenaarA stuurt feedback (idee)', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      addDoc(collection(db, 'feedback'), {
        uid: EIGENAAR_A_UID,
        weergaveNaam: 'Eigenaar A',
        categorie: 'idee',
        bericht: 'Een dagklok voor de nacht zou fijn zijn',
        appVersie: '1.0.36+41',
        platform: 'android',
      }),
    );
  });

  test('L42: lidA stuurt feedback (probleem)', async () => {
    const db = alsLidA(env).firestore();
    await assertSucceeds(
      addDoc(collection(db, 'feedback'), {
        uid: LID_A_UID,
        weergaveNaam: 'Lid A',
        categorie: 'probleem',
        bericht: 'Bel gaat soms niet over bij mijn moeder',
        appVersie: '1.0.36+41',
        platform: 'ios',
      }),
    );
  });

  test('L43: nieuwe gast (net ingelogd) stuurt feedback (anders)', async () => {
    const db = alsNieuweGast(env).firestore();
    await assertSucceeds(
      addDoc(collection(db, 'feedback'), {
        uid: NIEUWE_GAST_UID,
        weergaveNaam: 'Nieuwe Gast',
        categorie: 'anders',
        bericht: 'Bedankje',
        appVersie: '1.0.36+41',
        platform: 'web',
      }),
    );
  });
});

// ──────────────────────────────────────────────
// APPARATEN — cross-uid read (bel-lijst)
// ──────────────────────────────────────────────
describe('apparaten — cross-uid read voor bellijst', () => {
  test('L38: lidA leest eigenaarA-apparaat (zelfde kring)', async () => {
    // Bel-flow: gast (lidA) opent bel-scherm en moet ontvanger-apparaten
    // van de eigenaar kunnen lezen om te bellen.
    const db = alsLidA(env).firestore();
    await assertSucceeds(
      getDoc(doc(db, 'gebruikers', EIGENAAR_A_UID, 'apparaten', 'app1')),
    );
  });
});
