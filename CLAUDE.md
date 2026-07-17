# Ons Moment — Project Context

> Dit bestand is het permanente geheugen voor elke Claude-sessie in dit project. Lees dit eerst voordat je iets doet.

## Het doel

Ons Moment is een digitale knuffel voor mensen met dementie, verstandelijke beperking of erge vergeetachtigheid — en hun familie die zich machteloos voelt op afstand.

Familie stuurt vanaf hun telefoon een foto, stem, lied of bericht. Op het apparaat van de dierbare popt dat moment automatisch op met een vertrouwd herkenningsgeluid en hun eigen foto als warme achtergrond. Zij hoeven niks te doen — het komt naar hen toe.

Kernwaarde: "Mantelzorger App helpt JOU. Ons Moment helpt je DIERBARE."

## Businessmodel

- 7,99 EUR per maand per gezinsaccount, max 8 familieleden
- 5 dagen gratis proefperiode
- Markt: Nederland eerst

## Architectuur (V7)

Een gedeeld gezinsaccount: alle familieleden + ontvanger gebruiken dezelfde Firebase Auth account. Rol per apparaat via SharedPreferences/localStorage: familie of ontvanger.

Firestore collecties: gebruikers, dagelijkse_momenten, momenten, notities. Alle koppeling via familieUid (NIET naarUid — dat was V6 bug).

## Tech stack

- Flutter 3.19.6
- Firebase (Auth, Firestore, Storage)
- Hosting via GitHub Pages (workflow in .github/workflows/build.yml)
- Belangrijke packages: firebase_core/auth/firestore/storage, image_picker, file_picker, record, just_audio, wakelock_plus, shared_preferences, flutter_localizations, intl ^0.18.1

## Firebase project

- Project ID: onsmonent
- Auth: email + wachtwoord
- Test account: oma@test.nl / oma12345

## Live URLs

- App: https://jsm200522.github.io/OnsMoment/
- Repo: https://github.com/JSM200522/OnsMoment

## Bekende issues per 15 mei 2026

- Oude V6 momenten in Firestore gebruiken nog naarUid prefix — verschijnen niet bij V7 ontvanger
- Pixabay-URLs voor preset-geluiden kunnen falen door hotlink-protectie (fallback aanwezig)
- Stem-opname op web werkt via blob URLs — moet bytes uploaden naar Storage (V8 fix)
- Firebase web-app was incorrect geconfigureerd in build.yml (Android-appId voor web-omgeving). Werkte tot ~15 mei 2026 door Google's tolerantie. Vanaf 16 mei strenger geweigerd → 400 errors op identitytoolkit.goog. Fix: echte web-config uit Firebase Console gebruikt in build.yml.

## V8 routekaart

1. Stem-opname als bytes uploaden naar Storage
2. Familieleden uitnodigen via email + deeplink
3. Persoonlijk herkenningsgeluid opnemen
4. Stripe 7,99/maand met 5 dagen proef
5. Account-status check

## V9 — App stores

- Google Play: 25 EUR eenmalig, ~1 week review
- Apple App Store: 99 EUR per jaar, ~1-2 weken review, Mac of cloud build service nodig
- Privacy policy + terms of service verplicht
- GDPR/AVG compliance

## Nog te doen bij launch / betaalsysteem

- Limieten definitief vastgesteld als PER KRING (niet totaal): Family Klein = 1 kring, max 8 personen per kring. Family Groot = max 3 kringen, max 20 personen per kring. De personen-limiet (8/20 per kring) zit al correct in de code. Nog te bouwen bij het betaalsysteem: de kring-aantal-limiet (1 vs 3), het tier-upgradepad (klein -> groot), en server-side afdwinging via Firestore rules. Controleer bij de launch ook of alle in-app teksten/FAQ "per kring" vermelden en nergens nog "totaal" staat.

## Over Joshua

- Geen technische achtergrond
- Windows 11 + iPhone
- Nederlands, stap-voor-stap uitleg zonder jargon
- Wil senior-level engineering en productie-kwaliteit

## Werkstijl-regels

1. Denk eerst diep na voor implementatie
2. Controleer eigen output als productie-code
3. Geen aannames — verifieer eerst
4. Geen halfwerk
5. Edge cases, UX, performance, security, schaalbaarheid meedenken
6. Geen pseudo-code, geen essentiele delen weglaten

## Standaard workflow

Voor elke wijziging:
1. Lees bestaande code
2. Check afhankelijkheden (grep)
3. Beschrijf plan kort
4. Maak wijziging
5. Run flutter analyze
6. Run flutter build web
7. Pas dan committen en pushen

NOOIT blind pushen — vandaag (15 mei 2026) heeft dat 10 rode builds opgeleverd.

## Sessielog

- 15 mei 2026: V7 release, build #47 groen
- 15 mei 2026: Overstap naar Claude Code workflow
- 12 juli 2026: Push-meldingen Fase 1 code-compleet (commits 1a-1d) en Fase 2
  code-compleet (commits 2a-2c). Alle 7 commits groen op CI. Wat er ligt:
  - FCM-basis: firebase_messaging ^14.7.20 + flutter_local_notifications ^17.1.2
  - PushService (lib/services/push_service.dart) met kIsWeb-guards + fail-soft
  - FCM-token per apparaat op gebruikers/{uid}/apparaten/{id} (fcmToken,
    fcmTokenBijgewerkt, fcmPlatform) — NIET op de gebruiker-doc, zodat tablet
    én familie-toestellen elk hun eigen adres hebben binnen het gedeelde account
  - Monochroom statusbar-icoon ic_stat_ons_moment (5 densities) + peach-tint
  - Zes notification channels, één per herkenningsgeluid; channelIdVoorGeluid
    als bron van waarheid voor de Cloud Function
  - Tap-op-notificatie opent het juiste moment via PushService.tapMomentIdNotifier
    → beide schermen fetchen het moment en tonen bestaande _toonPopup
  - Payload-conventie verankerd: notification.android.channel_id +
    data.momentId (Cloud Function moet die vullen)
  - Handmatige device-test (1e + 2d) verschoven naar ná Fase 3 zodat we in
    één keer de volledige automatische flow testen (Cloud Function → FCM →
    tray → tap → popup) i.p.v. twee losse handmatige rondes.
- 13 juli 2026: Push-meldingen Fase 3 code-compleet (commits 3a + 3b) EN
  gedeployed naar productie. Volledige status:
  - Firebase Functions skelet: functions/-map, TypeScript strict, Node 22,
    region europe-west1 (matcht Firestore eur3 multi-region)
  - onNieuwMoment: Firestore-trigger onDocumentCreated('momenten/{id}') met
    hybride targeting (aanApparaatIds indien niet-leeg, anders ontvangers in
    kring; altijd afzender-uitfilter), 5-min skip voor toekomstige geplande
    momenten, gespiegelde channelIdVoorGeluid-map, dead-token cleanup bij
    registration-token-not-registered / invalid-registration-token, en
    NOOIT writes naar momenten/ (recursie onmogelijk)
  - Gedeployed naar onsmonent 13 juli 2026. Function is live (v2, 256MB,
    nodejs22, europe-west1). Deploy vereiste 2 pogingen door first-time
    Eventarc-service-agent-permissies (~8 min wachten tussen pogingen).
  - Artifact Registry cleanup policy op europe-west1: images ouder dan 7 dagen
    worden automatisch verwijderd (voorkomt oplopende opslagkosten).
  - Geparkeerd tot na testresultaten: firebase-functions v6 → v7 major-upgrade
    (waarschuwing tijdens deploy; niet blocking, wachten om breaking changes
    in één keer te doen ná bevestiging dat huidige setup werkt).
  - Openstaand: 3d device-test staat open tot build 1.0.7+9 via Play Store op
    de testtoestellen (telefoon + tablet) is geïnstalleerd. Testscenario's:
    (a) FCM-token verschijnt in Firestore na eerste inlog, (b) meldingen komen
    binnen met eigen geluid per kring, (c) tik opent het juiste moment,
    (d) afzender krijgt zijn eigen bericht niet, (e) statusbar-icoon is
    zichtbaar en peach-getint. Bij problemen: Cloud Function logs via
    `firebase functions:log --only onNieuwMoment`.
  - GEEN Claude Code-werk tot testresultaten binnen zijn.
- 17 juli 2026: Videobellen V0 volledig af én gedeployed, V1 code-compleet
  op main (commits VB-V0-1 t/m VB-V1-5, alle 9 groen op CI). Wat er ligt:
  - LiveKit Cloud project `onsmoment-jsh7c0m3` (EU), API-key + secret in
    Firebase Secrets (LIVEKIT_API_KEY + LIVEKIT_API_SECRET, versie 1)
  - Cloud Function `getVideoCallToken` (europe-west1, secrets-binding via
    defineSecret) — auth-required, 10-min JWT-TTL, schrijft niets naar
    Firestore. `onNieuwMoment` volledig ongewijzigd naast deze toevoeging.
  - Flutter-service `VideoCallService` met haalToken/vraagCameraPermissie/
    join/hangup. Alle publieke methods kIsWeb-guarded; hangup is idempotent
    en synchroon-resettend; join reverten bij fout en re-throwen.
  - `VideobellenTestScherm` (verborgen achter DEBUG_VIDEOBELLEN, alleen op
    familie-modus) verbindt met `test_{apparaatId}` en toont self-view via
    AnimatedBuilder op Room (ChangeNotifier).
  - Android manifest: CAMERA + MODIFY_AUDIO_SETTINGS + USE_FULL_SCREEN_INTENT
    (RECORD_AUDIO was al aanwezig).
- 17 juli 2026 — Veiligheidsaudit V0+V1: alle 7 punten groen (bewijs
  vastgelegd; belangrijkste uitkomsten):
  1. Flag-uit-garantie: `grep VideoCallService|videobellen|livekit|
     cloud_functions|permission_handler|FirebaseFunctions lib/main.dart`
     geeft ZERO matches — de service wordt in productie nergens gebootstrapt.
     Enige productie-aanroep zit achter `if (DEBUG_VIDEOBELLEN &&
     !widget.alsOntvanger)` in familie_scherm.dart:3570.
  2. Bestaande flows onaangeraakt: `git diff 91a65d0..HEAD -- lib/main.dart
     lib/screens/tablet/tablet_scherm.dart lib/services/push_service.dart`
     = 0 regels. Enige aanpassing in familie_scherm.dart = +1 import + 15
     flag-gated regels. Momenten-flow, 22 listeners, push, popup identiek.
  3. Permissies: CAMERA is dangerous (runtime-prompt, nooit getriggerd met
     flag uit); MODIFY_AUDIO_SETTINGS is normal (geen prompt);
     USE_FULL_SCREEN_INTENT is special (Play Console-declaration nodig vóór
     V9 store-release). Geen crash-risico op minSdk 23 (permission_handler
     11 vereist minSdk 21).
  4. Cloud Function veiligheid: auth ✓; ROOM/IDENTITY WORDEN NIET SERVER-
     SIDE GEBONDEN AAN KRING-MEMBERSHIP OF UID — voor V1 met test-rooms
     acceptabel, MOET fixed voor V2 (zie openstaande punten).
  5. Deps schoon: cloud_functions 4.7.6, permission_handler 11.3.1,
     transitief 9 nieuwe packages, geen conflict met record/just_audio/
     video_player. pubspec.lock consistent.
  6. Kosten: getVideoCallToken schrijft niks (regel-audit videocall.ts) →
     recursie onmogelijk. Enige kosten: 1 invocation + JWT-CPU per call.
     Geen server-side rate-limiting → V2-punt.
  7. Openstaande punten geregistreerd in aparte sectie hieronder.

## Openstaande punten (niet vergeten)

Losse eindjes die bewust zijn uitgesteld en niet mogen wegzakken.
Update deze lijst zodra een item is opgepakt of afgerond.

Push-meldingen (Fase 3+):
- **Device-test 3d**: open tot testers 1.0.7+9 uit Play Store hebben
  geïnstalleerd — 5 scenario's beschreven in de sessielog van 13 juli.
- **firebase-functions v6 → v7**: major-upgrade waarschuwing tijdens deploy,
  wachten tot na 3d-testresultaten om breaking changes te bundelen.
- **Verstuurtijd-root-cause**: nog niet gediagnosticeerd — pakken zodra
  push-meldingen groen zijn getest.
- **Orphan-cleanup stap E**: laatste stap van de push-orphan-cleanup staat
  nog open (details in oude sessie-log — te achterhalen via git-history).

Videobellen (Fase VB):
- **Device-test V1**: handmatig op telefoon met DEBUG_VIDEOBELLEN=true —
  scenario's: (a) camera-permissie-prompt verschijnt bij eerste tap,
  (b) self-view komt binnen 3s in beeld, (c) ophangen sluit netjes en
  LiveKit-room verdwijnt (te checken in LiveKit Cloud dashboard),
  (d) back-swipe verbreekt ook (dispose-pad), (e) tweede tap na ophangen
  werkt opnieuw (geen stale state).
- **V2-vereiste — kring-membership check server-side**: getVideoCallToken
  moet vóór token-uitgifte verifiëren dat `request.auth.uid` deel is van
  de kring waar `roomName` bij hoort. Nu kan elke ingelogde user tokens
  voor elke room vragen. Blocker voor productie-belflow.
- **V2-vereiste — identity binden**: server bepaalt identity uit
  (uid, apparaatId) i.p.v. deze uit client-payload over te nemen. Anders
  kan client zich als iemand anders aanmelden in LiveKit.
- **V2-vereiste — rate-limiting**: bv. max N token-requests per uid per
  minuut, of App Check-integratie. Nu onbegrensd → potentieel misbruik.
- **LiveKit secret-rotatie**: procedure vastleggen (regenerate in LiveKit
  Cloud → `firebase functions:secrets:set` → redeploy). Documenteer.
- **Play Store camera-verklaring (V9)**: bij store-release verklaren dat
  CAMERA gebruikt wordt voor familie-videobellen, dat USE_FULL_SCREEN_
  INTENT bij calling-functionaliteit hoort, en dat MODIFY_AUDIO_SETTINGS
  vereist is door WebRTC audio-routing.
