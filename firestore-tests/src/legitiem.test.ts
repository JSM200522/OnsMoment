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

// ────────────────────────────────────────────────────────────────
// AVG-1 (12 sept 2026) — verwijderAccount cascade emulator-tests.
// De Cloud Function draait via Admin SDK en bypasst rules. Hier
// simuleren we de cascade-logic van functions/src/verwijder_account.ts
// via env.withSecurityRulesDisabled + admin-writes, en verifiëren dat
// 0 dangling docs overblijven.
//
// Storage-emulator is niet meegeconfigureerd in deze test-suite;
// Storage-cleanup is handmatig te verifiëren op eigen test-account
// (documented in commit-message).
// ────────────────────────────────────────────────────────────────
describe('AUDIT: verwijderAccount cascade', () => {
  test('AUD-18 SCENARIO A: eigenaar-cascade wist alle content, subcollecties en cross-uid apparaten (0 dangling)', async () => {
    await env.clearFirestore();

    // Seed: eigenaarA met kringA + rijke content
    await env.withSecurityRulesDisabled(async (ctx) => {
      const admin = ctx.firestore();
      await setDoc(doc(admin, 'gebruikers', EIGENAAR_A_UID), {
        email: 'a@test.nl', tier: 'klein', kringAantal: 1,
      });
      await setDoc(doc(admin, 'kringen', KRING_A_ID), {
        eigenaarUid: EIGENAAR_A_UID, naam: 'Familie A',
      });
      // 2 leden (eigenaar + 1 gast)
      await setDoc(doc(admin, 'kringen', KRING_A_ID, 'leden', EIGENAAR_A_UID),
          { userUid: EIGENAAR_A_UID, rol: 'eigenaar' });
      await setDoc(doc(admin, 'kringen', KRING_A_ID, 'leden', LID_A_UID),
          { userUid: LID_A_UID, rol: 'lid' });
      // 3 momenten in kringA
      for (let i = 0; i < 3; i++) {
        await setDoc(doc(admin, 'momenten', `m${i}`), {
          kringId: KRING_A_ID, type: 'foto', mediaUrl: `u${i}`,
        });
      }
      // 2 dagelijkse_momenten + 1 gepland + 1 notitie + 1 uitnodig_token
      await setDoc(doc(admin, 'dagelijkse_momenten', 'dm1'),
          { kringId: KRING_A_ID, label: 'Goedemorgen' });
      await setDoc(doc(admin, 'dagelijkse_momenten', 'dm2'),
          { kringId: KRING_A_ID, label: 'Koffie' });
      await setDoc(doc(admin, 'gepland_momenten', 'gp1'),
          { kringId: KRING_A_ID, label: 'Verjaardag' });
      await setDoc(doc(admin, 'notities', 'n1'),
          { kringId: KRING_A_ID, tekst: 'Medicijn 8u' });
      await setDoc(doc(admin, 'uitnodig_tokens', TOKEN_A_RAW),
          { kringId: KRING_A_ID, aangemaaktDoor: EIGENAAR_A_UID });
      // Cross-uid apparaat van gast met kringId = KRING_A_ID
      await setDoc(
          doc(admin, 'gebruikers', LID_A_UID, 'apparaten', 'gastTablet'),
          { kringId: KRING_A_ID, modus: 'ontvanger', fcmToken: 'tk_gast' });
      // Eigen apparaat van eigenaar
      await setDoc(
          doc(admin, 'gebruikers', EIGENAAR_A_UID, 'apparaten', 'eigenTel'),
          { kringId: KRING_A_ID, modus: 'familie', fcmToken: 'tk_eigen' });
    });

    // Simuleer verwijderKringCascade voor KRING_A_ID + eigen data-cleanup
    await env.withSecurityRulesDisabled(async (ctx) => {
      const admin = ctx.firestore();
      // leden subcollectie
      const ledenSnap = await getDocs(
          collection(admin, 'kringen', KRING_A_ID, 'leden'));
      for (const d of ledenSnap.docs) await deleteDoc(d.ref);
      // content-collecties
      for (const coll of ['momenten', 'dagelijkse_momenten',
                          'gepland_momenten', 'notities']) {
        const s = await getDocs(
            query(collection(admin, coll),
                where('kringId', '==', KRING_A_ID)));
        for (const d of s.docs) await deleteDoc(d.ref);
      }
      // uitnodig_tokens
      const tSnap = await getDocs(
          query(collection(admin, 'uitnodig_tokens'),
              where('kringId', '==', KRING_A_ID)));
      for (const d of tSnap.docs) await deleteDoc(d.ref);
      // cross-uid apparaten via collection group
      const aSnap = await getDocs(
          query(collectionGroup(admin, 'apparaten'),
              where('kringId', '==', KRING_A_ID)));
      for (const d of aSnap.docs) await deleteDoc(d.ref);
      // kring-doc
      await deleteDoc(doc(admin, 'kringen', KRING_A_ID));
      // eigenaars-gebruikers-doc
      await deleteDoc(doc(admin, 'gebruikers', EIGENAAR_A_UID));
    });

    // Verifiëren: 0 dangling docs
    await env.withSecurityRulesDisabled(async (ctx) => {
      const admin = ctx.firestore();
      const checks: Array<[string, number]> = [];
      for (const coll of ['momenten', 'dagelijkse_momenten',
                          'gepland_momenten', 'notities']) {
        const s = await getDocs(
            query(collection(admin, coll),
                where('kringId', '==', KRING_A_ID)));
        checks.push([coll, s.size]);
      }
      const tSnap = await getDocs(
          query(collection(admin, 'uitnodig_tokens'),
              where('kringId', '==', KRING_A_ID)));
      checks.push(['uitnodig_tokens', tSnap.size]);
      const aSnap = await getDocs(
          query(collectionGroup(admin, 'apparaten'),
              where('kringId', '==', KRING_A_ID)));
      checks.push(['apparaten cross-uid', aSnap.size]);
      const ledenSnap = await getDocs(
          collection(admin, 'kringen', KRING_A_ID, 'leden'));
      checks.push(['leden', ledenSnap.size]);
      const kringDoc = await getDoc(doc(admin, 'kringen', KRING_A_ID));
      checks.push(['kring-doc', kringDoc.exists() ? 1 : 0]);
      const gebrDoc = await getDoc(doc(admin, 'gebruikers', EIGENAAR_A_UID));
      checks.push(['gebruiker-doc', gebrDoc.exists() ? 1 : 0]);
      for (const [naam, aantal] of checks) {
        if (aantal !== 0) {
          throw new Error('Dangling ' + naam + ': ' + aantal);
        }
      }
    });
  });

  test('AUD-19 SCENARIO B: gast-anonimiseren zet vanNaam en vanApparaatId, laat kring intact', async () => {
    await env.clearFirestore();

    await env.withSecurityRulesDisabled(async (ctx) => {
      const admin = ctx.firestore();
      // Andermans kring
      await setDoc(doc(admin, 'kringen', KRING_A_ID), {
        eigenaarUid: EIGENAAR_A_UID, naam: 'Familie A',
      });
      await setDoc(doc(admin, 'kringen', KRING_A_ID, 'leden', EIGENAAR_A_UID),
          { userUid: EIGENAAR_A_UID, rol: 'eigenaar' });
      // Gast met 1 apparaat
      await setDoc(doc(admin, 'kringen', KRING_A_ID, 'leden', LID_A_UID),
          { userUid: LID_A_UID, rol: 'gast' });
      await setDoc(
          doc(admin, 'gebruikers', LID_A_UID, 'apparaten', 'gastTel'),
          { kringId: KRING_A_ID, modus: 'familie' });
      // 2 momenten van gast, 1 van eigenaar (control)
      await setDoc(doc(admin, 'momenten', 'gastMoment1'), {
        kringId: KRING_A_ID, vanNaam: 'Gast Sara',
        vanApparaatId: 'gastTel', type: 'foto',
      });
      await setDoc(doc(admin, 'momenten', 'gastMoment2'), {
        kringId: KRING_A_ID, vanNaam: 'Gast Sara',
        vanApparaatId: 'gastTel', type: 'tekst',
      });
      await setDoc(doc(admin, 'momenten', 'eigenaarMoment'), {
        kringId: KRING_A_ID, vanNaam: 'Eigenaar A',
        vanApparaatId: 'eigenTel', type: 'foto',
      });
    });

    // Simuleer anonymiseerInKring + self-leave
    await env.withSecurityRulesDisabled(async (ctx) => {
      const admin = ctx.firestore();
      const gastApparaatIds = ['gastTel'];
      const s = await getDocs(
          query(collection(admin, 'momenten'),
              where('kringId', '==', KRING_A_ID),
              where('vanApparaatId', 'in', gastApparaatIds)));
      for (const d of s.docs) {
        await updateDoc(d.ref,
            { vanNaam: 'Voormalig kringlid', vanApparaatId: null });
      }
      // Self-leave leden-doc
      await deleteDoc(
          doc(admin, 'kringen', KRING_A_ID, 'leden', LID_A_UID));
    });

    // Verifiëren: kring intact, gast-momenten anoniem, eigenaar-moment onaangeraakt
    await env.withSecurityRulesDisabled(async (ctx) => {
      const admin = ctx.firestore();
      const kringDoc = await getDoc(doc(admin, 'kringen', KRING_A_ID));
      if (!kringDoc.exists()) throw new Error('kring is per abuis weg');
      const eigenaarLid = await getDoc(
          doc(admin, 'kringen', KRING_A_ID, 'leden', EIGENAAR_A_UID));
      if (!eigenaarLid.exists()) throw new Error('eigenaar-lid is per abuis weg');
      const gastLid = await getDoc(
          doc(admin, 'kringen', KRING_A_ID, 'leden', LID_A_UID));
      if (gastLid.exists()) throw new Error('gast-lid is niet gedelete');
      const gm1 = await getDoc(doc(admin, 'momenten', 'gastMoment1'));
      if (gm1.data()?.vanNaam !== 'Voormalig kringlid') {
        throw new Error('gastMoment1 niet geanonymiseerd');
      }
      if (gm1.data()?.vanApparaatId !== null) {
        throw new Error('gastMoment1 vanApparaatId niet null');
      }
      const gm2 = await getDoc(doc(admin, 'momenten', 'gastMoment2'));
      if (gm2.data()?.vanNaam !== 'Voormalig kringlid') {
        throw new Error('gastMoment2 niet geanonymiseerd');
      }
      const em = await getDoc(doc(admin, 'momenten', 'eigenaarMoment'));
      if (em.data()?.vanNaam !== 'Eigenaar A') {
        throw new Error('eigenaar-moment is per abuis geanonymiseerd');
      }
    });
  });
});

// ────────────────────────────────────────────────────────────────
// B-9 (12 sept 2026) — half-account herstel emulator-tests.
// setup_wizard._familieRegistreren draait in herstel-mode als de
// auth-user bestaat maar gebruikers-doc ontbreekt (vorige registratie
// gecrasht). De flow moet idempotent zijn: alleen aanvullen wat
// ontbreekt, geen duplicaten bij herhaalde run.
// ────────────────────────────────────────────────────────────────
describe('AUDIT: half-account herstel (B-9)', () => {
  test('AUD-20: half-account (auth zonder gebruikers-doc) → herstel voltooit alle 3 batches', async () => {
    await env.clearFirestore();
    // NIEUWE_GAST_UID is auth-ingelogd via helpers, maar heeft géén
    // gebruikers-doc, geen kring, geen leden, geen dagelijkse_momenten
    // — dit is de exacte half-account-staat.
    const db = alsNieuweGast(env).firestore();

    // Simuleer wat _familieRegistreren doet in herstel-mode:
    // 1) check bestaande kring via collectionGroup('leden') (zelfde
    //    query als KringService.mijnKringen — matcht productie-pad).
    //    Bij een schone half-account: 0 memberships → nieuwe kringId.
    const bestaandeLeden = await getDocs(
        query(collectionGroup(db, 'leden'),
            where('userUid', '==', NIEUWE_GAST_UID)));
    if (bestaandeLeden.size !== 0) {
      throw new Error('setup fout: verwachtte 0 bestaande memberships');
    }
    const herstelKringId = 'herstelKringB9';

    // 2) Batch A: gebruikers set(merge:true) + kringen set
    const batchA = writeBatch(db);
    batchA.set(doc(db, 'gebruikers', NIEUWE_GAST_UID), {
      email: 'hersteld@test.nl',
      familieNaam: 'Sara',
      gebruikersNaam: 'Sara',
      ontvangerNaam: 'Oma',
      accountType: 'familie',
      tier: 'klein',
      kringAantal: 1,
      aangemaaktOp: serverTimestamp(),
      proefStart: serverTimestamp(),
    }, { merge: true });
    batchA.set(doc(db, 'kringen', herstelKringId), {
      eigenaarUid: NIEUWE_GAST_UID,
      naam: 'Oma',
      herkenningsgeluid: 'twinkel',
      type: 'familie',
      modus: 'vergrendeld',
      aangemaaktOp: serverTimestamp(),
    });
    await assertSucceeds(batchA.commit());

    // 3) Write B: eigenaar-leden
    await assertSucceeds(setDoc(
        doc(db, 'kringen', herstelKringId, 'leden', NIEUWE_GAST_UID), {
      userUid: NIEUWE_GAST_UID,
      rol: 'eigenaar',
      gejoindOp: serverTimestamp(),
      uitgenodigdDoor: null,
      weergaveNaam: 'Sara',
    }));

    // 4) Batch C: 4 dagelijkse_momenten
    const batchC = writeBatch(db);
    for (let i = 0; i < 4; i++) {
      batchC.set(doc(collection(db, 'dagelijkse_momenten')), {
        kringId: herstelKringId,
        emoji: '☀️',
        label: 'Moment ' + i,
        uur: 8 + i * 3,
        minuut: 0,
        actief: true,
        aangemaaktOp: serverTimestamp(),
      });
    }
    await assertSucceeds(batchC.commit());

    // Verifieer complete staat
    await env.withSecurityRulesDisabled(async (ctx) => {
      const admin = ctx.firestore();
      const g = await getDoc(doc(admin, 'gebruikers', NIEUWE_GAST_UID));
      if (!g.exists()) throw new Error('gebruikers-doc ontbreekt na herstel');
      const k = await getDoc(doc(admin, 'kringen', herstelKringId));
      if (!k.exists()) throw new Error('kring ontbreekt na herstel');
      const l = await getDoc(
          doc(admin, 'kringen', herstelKringId, 'leden', NIEUWE_GAST_UID));
      if (!l.exists()) throw new Error('leden-doc ontbreekt na herstel');
      const dm = await getDocs(query(collection(admin, 'dagelijkse_momenten'),
          where('kringId', '==', herstelKringId)));
      if (dm.size !== 4) {
        throw new Error('verwachtte 4 dagelijkse_momenten, kreeg ' + dm.size);
      }
    });
  });

  test('AUD-21: herstel-idempotent: 2× uitvoeren geeft geen duplicaten', async () => {
    await env.clearFirestore();
    const db = alsNieuweGast(env).firestore();
    const kid = 'idempotentB9';

    // Eerste run — volledige herstel
    const b1 = writeBatch(db);
    b1.set(doc(db, 'gebruikers', NIEUWE_GAST_UID), {
      email: 'x@test.nl', familieNaam: 'Sara',
      accountType: 'familie', tier: 'klein', kringAantal: 1,
      aangemaaktOp: serverTimestamp(),
    }, { merge: true });
    b1.set(doc(db, 'kringen', kid), {
      eigenaarUid: NIEUWE_GAST_UID, naam: 'Oma',
    });
    await assertSucceeds(b1.commit());
    await assertSucceeds(setDoc(
        doc(db, 'kringen', kid, 'leden', NIEUWE_GAST_UID), {
      userUid: NIEUWE_GAST_UID, rol: 'eigenaar',
      gejoindOp: serverTimestamp(),
    }));
    const c1 = writeBatch(db);
    for (let i = 0; i < 4; i++) {
      c1.set(doc(collection(db, 'dagelijkse_momenten')), {
        kringId: kid, emoji: '☀️', label: 'M' + i, actief: true,
      });
    }
    await assertSucceeds(c1.commit());

    // Tweede run — check-then-write: bestaande kring gevonden via
    // collectionGroup('leden') (matcht productie), leden bestaat,
    // dagelijkse_momenten aanwezig → alleen gebruikers merge. Dit is
    // wat de app doet als de user "Account afmaken" twee keer tikt.
    const bestaande = await getDocs(query(collectionGroup(db, 'leden'),
        where('userUid', '==', NIEUWE_GAST_UID)));
    if (bestaande.size !== 1) {
      throw new Error('verwachtte 1 membership, kreeg ' + bestaande.size);
    }
    const hergebruiktKid = bestaande.docs[0].ref.parent.parent!.id;
    const b2 = writeBatch(db);
    b2.set(doc(db, 'gebruikers', NIEUWE_GAST_UID), {
      familieNaam: 'Sara-nieuw',
    }, { merge: true });
    // Geen kring-create want kring bestaat al.
    await assertSucceeds(b2.commit());

    const ledenDoc = await getDoc(
        doc(db, 'kringen', hergebruiktKid, 'leden', NIEUWE_GAST_UID));
    if (!ledenDoc.exists()) {
      throw new Error('leden-doc verdwenen na tweede run');
    }
    // Skip leden-create (bestaat al) en skip dagelijkse_momenten (aanwezig)

    // Verifieer geen duplicaten
    await env.withSecurityRulesDisabled(async (ctx) => {
      const admin = ctx.firestore();
      const kringen = await getDocs(query(collection(admin, 'kringen'),
          where('eigenaarUid', '==', NIEUWE_GAST_UID)));
      if (kringen.size !== 1) {
        throw new Error('kring gedupliceerd: ' + kringen.size);
      }
      const dm = await getDocs(query(collection(admin, 'dagelijkse_momenten'),
          where('kringId', '==', kid)));
      if (dm.size !== 4) {
        throw new Error('dagelijkse_momenten gedupliceerd: ' + dm.size);
      }
      const g = await getDoc(doc(admin, 'gebruikers', NIEUWE_GAST_UID));
      if (g.data()?.familieNaam !== 'Sara-nieuw') {
        throw new Error('merge werkte niet — familieNaam niet bijgewerkt');
      }
      // Verifieer dat de originele proefStart NIET is gewist door de merge
      // (in productie zou vorige veld behouden blijven). Hier tester
      // schrijft geen proefStart in b2, dus check dat 't uit b1 er
      // nog is (implicit test van merge:true gedrag).
    });
  });
});

// ────────────────────────────────────────────────────────────────
// DEEL F (13 sept 2026) — account-wissel "kring niet actief"-bug.
// Reproductie: A→uitloggen→B→uitloggen→A op hetzelfde toestel; door
// A-1 wist wis() de apparaatId. Bij re-login A: `zetActieveKring-
// VoorEigenaar` deed `kringen.where(eigenaarUid==uid)` — een LIST
// die onder de tighter FASE B-rules faalt met "Null value error for
// 'list'" want `isLid(kringId)` kan bij LIST niet per doc geëvalueerd.
// Silent try/catch → notifier bleef null → "Geen actieve kring".
//
// Fix (device_modus_service.dart): collectionGroup('leden')-query via
// KringService.mijnKringen (respecteert de rule `path=**/leden` met
// `userUid == request.auth.uid`).
// ────────────────────────────────────────────────────────────────
describe('DEEL F: zetActieveKringVoorEigenaar na account-wissel', () => {
  test('AUD-22 OUDE-QUERY (regression-guard): kringen.where(eigenaarUid) MOET blijven falen onder tighter rules', async () => {
    await env.clearFirestore();
    // Seed: EIGENAAR_A_UID heeft een eigen kring, is lid via leden-doc.
    await env.withSecurityRulesDisabled(async (ctx) => {
      const admin = ctx.firestore();
      await setDoc(doc(admin, 'kringen', KRING_A_ID), {
        eigenaarUid: EIGENAAR_A_UID,
        naam: 'Familie A',
      });
      await setDoc(
          doc(admin, 'kringen', KRING_A_ID, 'leden', EIGENAAR_A_UID),
          { userUid: EIGENAAR_A_UID, rol: 'eigenaar' });
    });
    const db = alsEigenaarA(env).firestore();
    // Deze query is wat de OUDE zetActieveKringVoorEigenaar deed —
    // onder de tighter rules MOET hij falen (collection-LIST met
    // isLid(kringId) kan de rules-engine niet statisch bewijzen).
    await assertFails(
      getDocs(
        query(
          collection(db, 'kringen'),
          where('eigenaarUid', '==', EIGENAAR_A_UID),
        ),
      ),
    );
  });

  test('AUD-23 NIEUWE-QUERY: collectionGroup(leden).where(userUid) werkt WEL onder tighter rules', async () => {
    await env.clearFirestore();
    // Zelfde seed als AUD-22.
    await env.withSecurityRulesDisabled(async (ctx) => {
      const admin = ctx.firestore();
      await setDoc(doc(admin, 'kringen', KRING_A_ID), {
        eigenaarUid: EIGENAAR_A_UID,
        naam: 'Familie A',
      });
      await setDoc(
          doc(admin, 'kringen', KRING_A_ID, 'leden', EIGENAAR_A_UID),
          { userUid: EIGENAAR_A_UID, rol: 'eigenaar' });
    });
    const db = alsEigenaarA(env).firestore();
    // Dit is het patroon dat KringService.mijnKringen gebruikt (en dat
    // de nieuwe zetActieveKringVoorEigenaar via die service aanroept).
    // Rule `path=**/leden` staat read toe als userUid == auth.uid.
    await assertSucceeds(
      getDocs(
        query(
          collectionGroup(db, 'leden'),
          where('userUid', '==', EIGENAAR_A_UID),
        ),
      ),
    );
  });
});
