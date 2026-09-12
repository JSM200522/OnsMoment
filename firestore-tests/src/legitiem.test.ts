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

// ──────────────────────────────────────────────
// AUDIT-BLOK — 14 kritieke acties (sept 2026)
// ──────────────────────────────────────────────
describe('AUDIT: bel-lijst kringLeden query', () => {
  // ApparaatService.kringLeden doet .collection('apparaten').get() zonder
  // where-clause. In Firestore rules moet ELKE doc individueel slagen —
  // een enkel doc zonder kringId of met een 'vreemde' kringId doet de
  // hele query kelderen. Deze test bewijst of dat gebeurt of niet.
  test('AUD-1: lidA doet volledige get() op eigenaarA/apparaten (bellijst) — LAUNCH-BLOCKER', async () => {
    // ApparaatService.kringLeden regel 121-123 doet exact deze query.
    // De read-rule (regel 59) filtert per-doc op resource.data.kringId,
    // maar bij een LIST-operatie kan Firestore rules dat niet statisch
    // bewijzen → weigert de hele lijst.
    const db = alsLidA(env).firestore();
    await assertFails(
      getDocs(collection(db, 'gebruikers', EIGENAAR_A_UID, 'apparaten')),
    );
  });

  test('AUD-1b: lidA doet get() MET where(kringId==kringA) → SLAAGT wel', async () => {
    // Bewijs dat de fix een where-clause is: rule kan dan filter-match
    // met resource.data.kringId statisch afleiden. ApparaatService.kringLeden
    // moet dus zo aangepast worden.
    const db = alsLidA(env).firestore();
    await assertSucceeds(
      getDocs(
        query(
          collection(db, 'gebruikers', EIGENAAR_A_UID, 'apparaten'),
          where('kringId', '==', KRING_A_ID),
        ),
      ),
    );
  });

  test('AUD-1c: _ontvangerApparaatIds patroon (where(kringId)==) werkt voor lidA', async () => {
    // familie_scherm.dart:1561-1565 gebruikt exact dit patroon om ontvanger-
    // apparaten van de kring-eigenaar op te halen als lidA een moment
    // "voor je dierbare" stuurt.
    const db = alsLidA(env).firestore();
    await assertSucceeds(
      getDocs(
        query(
          collection(db, 'gebruikers', EIGENAAR_A_UID, 'apparaten'),
          where('kringId', '==', KRING_A_ID),
        ),
      ),
    );
  });

  test('AUD-2: bellijst faalt als eigenaarA een apparaat zonder kringId heeft', async () => {
    // Seed een orphan-apparaat (geen kringId) onder eigenaarA. LidA leest
    // dan de collectie — rule-eval faalt op de orphan want kringId=''.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), 'gebruikers', EIGENAAR_A_UID, 'apparaten', 'orphan'),
        { naam: 'Orphan apparaat', fcmToken: 'x' },
      );
    });
    const db = alsLidA(env).firestore();
    await assertFails(
      getDocs(collection(db, 'gebruikers', EIGENAAR_A_UID, 'apparaten')),
    );
  });

  test('AUD-3: bellijst faalt bij apparaat met kringId van andere kring', async () => {
    // Seed een apparaat onder eigenaarA met kringId=kringB. LidA is lid
    // van kringA maar niet van kringB → rule leest kringB-leden/lidA →
    // false → hele query faalt.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), 'gebruikers', EIGENAAR_A_UID, 'apparaten', 'appVreemd'),
        { kringId: KRING_B_ID, naam: 'Andere kring', fcmToken: 'y' },
      );
    });
    const db = alsLidA(env).firestore();
    await assertFails(
      getDocs(collection(db, 'gebruikers', EIGENAAR_A_UID, 'apparaten')),
    );
  });

  test('AUD-3b: eigenaarA leest eigen apparaten-collectie inclusief orphan (baseline)', async () => {
    // Eigen uid → altijd toegestaan ongeacht kringId-veld. Bewijst dat
    // AUD-2/AUD-3 falen echt aan de rule liggen, niet aan seed.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), 'gebruikers', EIGENAAR_A_UID, 'apparaten', 'orphan'),
        { naam: 'Orphan apparaat' },
      );
    });
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      getDocs(collection(db, 'gebruikers', EIGENAAR_A_UID, 'apparaten')),
    );
  });
});

describe('AUDIT: UitnodigingService.zorgVoorToken batch', () => {
  // Batch: uitnodig_tokens/{token}.set + kringen/{K}.update. Beide
  // reads (isEigenaar) leunen op bestaande kringen/{K} — geen intra-
  // batch dependency. Zou moeten slagen.
  test('AUD-4: eigenaarA batch uitnodig_tokens.create + kringen.update (nieuwe token-flow)', async () => {
    const db = alsEigenaarA(env).firestore();
    const nieuwToken = 'nieuwTokenBatch12345';
    const batch = writeBatch(db);
    batch.set(doc(db, 'uitnodig_tokens', nieuwToken), {
      kringId: KRING_A_ID,
      aangemaaktDoor: EIGENAAR_A_UID,
      kringNaam: 'Familie A',
      kringFoto: null,
      uitnodigerNaam: 'Eigenaar A',
      huidigeLedenCache: 2,
      maxLedenCache: 8,
      tokenLower: nieuwToken.toLowerCase(),
    });
    batch.update(doc(db, 'kringen', KRING_A_ID), {
      uitnodigToken: nieuwToken,
      uitnodigTokenOp: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
  });
});

describe('AUDIT: OntvangerInfoScherm._opslaan batch', () => {
  // Batch: gebruikers/{uid}.update + kringen/{K}.update. Rule reads
  // beide op bestaande docs → geen intra-batch dep. Zou moeten slagen.
  test('AUD-5: eigenaarA batch gebruikers.update + kringen.update (ontvanger-profiel)', async () => {
    const db = alsEigenaarA(env).firestore();
    const batch = writeBatch(db);
    batch.update(doc(db, 'gebruikers', EIGENAAR_A_UID), {
      ontvangerNaam: 'Oma Nieuw',
      ontvangerFoto: 'https://x.example/foto.jpg',
      noodcontactNaam: 'Anna',
      noodcontactTel: '0611111111',
      herkenningsgeluid: 'twinkel',
    });
    batch.update(doc(db, 'kringen', KRING_A_ID), {
      naam: 'Oma Nieuw',
      foto: 'https://x.example/foto.jpg',
      noodcontactNaam: 'Anna',
      noodcontactTel: '0611111111',
      herkenningsgeluid: 'twinkel',
      laatsteUpdate: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
  });
});

describe('AUDIT: kring_aanmaken_scherm 3-stappen extra-kring', () => {
  // Extra kring aanmaken: gebruikersA heeft al kringA (kringAantal=1);
  // wil kringC aanmaken met kringAantal→2. Doel-tier 'groot' (limiet 3).
  test('AUD-6: extra kring aanmaken via 3-stappen (kring-count 1→2 op tier=groot)', async () => {
    // Seed: gebruikersA op tier=groot met kringAantal=1
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'gebruikers', EIGENAAR_A_UID), {
        tier: 'groot',
        kringAantal: 1,
        familieNaam: 'Sara',
      });
    });
    const db = alsEigenaarA(env).firestore();
    const nieuweKringId = 'kringC_extra';

    // Batch A: kringen.create + gebruikers.update({kringAantal: 2})
    const batchA = writeBatch(db);
    batchA.set(doc(db, 'kringen', nieuweKringId), {
      eigenaarUid: EIGENAAR_A_UID,
      naam: 'Opa',
      herkenningsgeluid: 'twinkel',
      aangemaaktOp: serverTimestamp(),
    });
    batchA.update(doc(db, 'gebruikers', EIGENAAR_A_UID), {
      kringAantal: 2,
    });
    await assertSucceeds(batchA.commit());

    // Write B: eigenaar-membership
    await assertSucceeds(
      setDoc(doc(db, 'kringen', nieuweKringId, 'leden', EIGENAAR_A_UID), {
        userUid: EIGENAAR_A_UID,
        rol: 'eigenaar',
        gejoindOp: serverTimestamp(),
        weergaveNaam: 'Sara',
      }),
    );

    // Batch C: dagelijkse_momenten defaults
    const batchC = writeBatch(db);
    batchC.set(doc(collection(db, 'dagelijkse_momenten')), {
      kringId: nieuweKringId,
      emoji: '☀️',
      label: 'Goedemorgen',
      uur: 8,
      minuut: 30,
      mediaType: '',
      mediaUrl: '',
      tekstBericht: '',
      actief: true,
      aangemaaktOp: serverTimestamp(),
    });
    await assertSucceeds(batchC.commit());
  });
});

describe('AUDIT: content-writes zonder kringId', () => {
  // Kritieke rule-eis: momenten/dagelijkse/gepland/notities create MOET
  // kringId bevatten. Anders faalt de isLid-read met evaluation error.
  test('AUD-7: moment create ZONDER kringId faalt', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertFails(
      addDoc(collection(db, 'momenten'), {
        type: 'tekst',
        bericht: 'Zonder kringId',
        verstuurdOp: serverTimestamp(),
      }),
    );
  });

  test('AUD-8: notitie create ZONDER kringId faalt', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertFails(
      addDoc(collection(db, 'notities'), {
        tekst: 'Zonder kringId',
        vanNaam: 'Sara',
        aangemaaktOp: serverTimestamp(),
      }),
    );
  });
});

describe('AUDIT: gast-signup end-to-end (bestaand-account pad)', () => {
  // AcceptUitnodigScherm._gastInloggen (regel 96) roept
  // UitnodigingService.accepteer aan, dat een leden-doc create met
  // viaToken doet. Deze test bewijst dat de exacte veldenset uit
  // Membership.toFirestoreMap slaagt.
  test('AUD-9: nieuwe gast leden-doc create met exacte Membership-velden slaagt', async () => {
    const db = alsNieuweGast(env).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'kringen', KRING_A_ID, 'leden', NIEUWE_GAST_UID), {
        userUid: NIEUWE_GAST_UID,
        rol: 'gast',
        gejoindOp: serverTimestamp(),
        uitgenodigdDoor: EIGENAAR_A_UID,
        weergaveNaam: 'Nieuwe Gast',
        viaToken: TOKEN_A_RAW,
      }),
    );
  });

  test('AUD-10: gast-signup gebruikers-create met exacte GastSignupScherm-velden slaagt', async () => {
    // Uit gast_signup_scherm.dart:113 — 6 velden, tier=klein, geen abonnement.
    await env.clearFirestore();
    const db = alsNieuweGast(env).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'gebruikers', NIEUWE_GAST_UID), {
        email: 'gast@test.nl',
        familieNaam: 'Nieuwe Gast',
        gebruikersNaam: 'Nieuwe Gast',
        accountType: 'familie',
        tier: 'klein',
        aangemaaktOp: serverTimestamp(),
      }),
    );
  });
});

describe('AUDIT: apparaat weergaveModus batch', () => {
  // ApparaatService.zetWeergaveModusVoorOntvangers doet batch.update op
  // eigen uid's apparaten. Rule: write if request.auth.uid == uid → OK.
  test('AUD-11: eigenaarA batch update weergaveModus op eigen apparaten', async () => {
    // Seed ontvanger-apparaat onder eigenaarA
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), 'gebruikers', EIGENAAR_A_UID, 'apparaten', 'tablet'),
        {
          kringId: KRING_A_ID,
          modus: 'ontvanger',
          weergaveModus: 'vergrendeld',
          fcmToken: 'tk',
        },
      );
    });
    const db = alsEigenaarA(env).firestore();
    const batch = writeBatch(db);
    batch.update(
      doc(db, 'gebruikers', EIGENAAR_A_UID, 'apparaten', 'tablet'),
      { weergaveModus: 'meldingen' },
    );
    await assertSucceeds(batch.commit());
  });
});

describe('AUDIT: apparaat re-registratie na re-login', () => {
  // AUTH-1 (12 sept 2026): na uitloggen + opnieuw inloggen op de
  // ontvanger-tablet moet PushService.registreerHuidigApparaat een verse
  // fcmToken naar het bestaande apparaat-doc kunnen schrijven (set+merge).
  // Anders blijft de stale token staan → startVideoCall.send() faalt
  // met 'unavailable / Kon doel-apparaat niet bereiken'.
  test('AUD-17: eigenaarA (die als ontvanger op tablet ingelogd is) schrijft verse fcmToken via set+merge', async () => {
    // Seed: bestaand apparaat-doc met OUDE fcmToken (zoals dat vóór
    // uitloggen bestond).
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), 'gebruikers', EIGENAAR_A_UID, 'apparaten', 'tablet'),
        {
          kringId: KRING_A_ID,
          modus: 'ontvanger',
          weergaveModus: 'vergrendeld',
          fcmToken: 'oude_stale_token',
          fcmPlatform: 'android',
        },
      );
    });
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'gebruikers', EIGENAAR_A_UID, 'apparaten', 'tablet'),
        {
          fcmToken: 'nieuwe_verse_token_na_relogin',
          fcmTokenBijgewerkt: serverTimestamp(),
          fcmPlatform: 'android',
          kringId: KRING_A_ID,
        },
        { merge: true },
      ),
    );
  });
});

describe('AUDIT: kring-doc autoAnswer + eenmalige update-velden', () => {
  test('AUD-12: eigenaarA schrijft autoAnswer=true op eigen kring', async () => {
    // BelApparaatKiesScherm._zetAutoAnswer regel 92
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'kringen', KRING_A_ID), { autoAnswer: true }),
    );
  });

  test('AUD-13: lidA (niet-eigenaar) mag GEEN autoAnswer zetten', async () => {
    const db = alsLidA(env).firestore();
    await assertFails(
      updateDoc(doc(db, 'kringen', KRING_A_ID), { autoAnswer: true }),
    );
  });
});

describe('AUDIT: familie-scherm moment-update velden (gezien / laatstGetoond / getoond)', () => {
  test('AUD-14: eigenaarA update gezien=true op moment (popup dismiss)', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'momenten', 'momentA'), { gezien: true }),
    );
  });

  test('AUD-15: eigenaarA update laatstGetoond op dagelijks moment', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'dagelijkse_momenten', 'dagA'), {
        laatstGetoond: '2026-09-11_08:30',
      }),
    );
  });

  test('AUD-16: eigenaarA update getoond=true op gepland moment', async () => {
    const db = alsEigenaarA(env).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'gepland_momenten', 'geplandA'), { getoond: true }),
    );
  });
});
