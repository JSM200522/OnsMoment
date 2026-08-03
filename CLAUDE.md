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
- 1 augustus 2026: Android 16-compliance + structurele edge-to-edge afhandeling
  code-compleet (commits A1 t/m A3, 6 commits, alle groen op CI). Build
  1.0.10+12 klaar voor Codemagic-build en device-test. Wat er ligt:
  - A1 (fc0e4e8): targetSdkVersion 35 → 36 voor Play Store-deadline 31 aug
    2026 (verlengd tot 1 nov 2026). compileSdk blijft 35; AGP 8.6.0 +
    Gradle 8.7 schrijven targetSdk 36 in manifest zonder SDK-36-platform.
  - A2 (bd87b91 t/m dd6b1be): NormaalScaffold-wrapper geïntroduceerd
    (lib/widgets/normaal_scaffold.dart). Logica: SafeArea(top: appBar==null)
    — met AppBar handelt Scaffold+AppBar de statusbalk al af (top:false);
    zonder AppBar doet SafeArea het zelf (top:true). Altijd bottom:true voor
    de navigatiebalk. Aangesloten: setup_wizard, accept_uitnodig, gast_signup,
    kring_aanmaken, kringleden (P1-fix), bel_apparaat_kies, MomentenBeheren
    (P2), OntvangerProfiel (P3), MomentenLijst (P4). SystemUiOverlayStyle
    toegevoegd in main.dart: transparante balken, donkere iconen als standaard.
    Nul hardcoded inset-waarden in de hele app — alle insets via OS/MediaQuery.
  - A3 (94baad4): Category 2-markers op alle full-bleed schermen. Geverifieerd
    dat ophangen-knop (GesprekScherm bottom:32, BelScherm bottom:24),
    Beantwoorden-knop (InkomendGesprekScherm in SafeArea > Padding(all(24)))
    en TabletScherm-inhoud (SafeArea-laag boven Positioned.fill-foto) nooit
    achter een systeembalk vallen.
  - Openstaand: Codemagic-build + device-test checklist (zie boven).
    16KB page-alignment risico blijft open (Flutter 3.19.6, fix = SDK-upgrade).
- 2 augustus 2026: Videobel-fixes + push-melding-overhaul code-compleet.
  Build 1.0.11+13 klaar voor Codemagic. Commits (alle groen op CI):
  - FIX-1 (bd00f09 + f2ea312): LiveKit secrets expliciet valideren + .trim()
    zodat trailing whitespace/newline in Secret Manager geen "invalid API key"
    geeft. Cloud Functions gedeployed.
  - FIX-2 (d8f3853): kringLeden filtert nu op fcmToken != null + kringId ==
    actieveKring. Orphan-apparaten (geen FCM-token) verdwijnen uit de bellijst.
  - FIX-3 (c611890): eerste-bericht-timing — onmiddellijk sturen gebruikt nu
    FieldValue.serverTimestamp() i.p.v. Timestamp.now() (telefoonklok);
    _verwerkMomenten() heeft +30s tolerantie.
  - FIX-4 (4fd9a9c): kringleden zichtbaar zonder opnieuw inloggen — cache-hit
    pad synct nu actieveKringNotifier.
  - VB-V3-7 (67753f9): incomingCall-listener verplaatst van TabletScherm naar
    _OntvangerRouterState (main.dart) zodat beide ontvanger-modi (vergrendeld
    + meldingen) het inkomend-gesprek-scherm tonen.
  - VB-V3-8 (0952a50): ringback-toon op BelScherm — bel.mp3 loopt in lus
    zodra verbinding actief is. Status-tekst "Gaat over bij {naam}…".
  - Push-melding overhaul (1014d96 + ae32945 + deployed):
    Overgestapt op data-only FCM voor moment-meldingen. Achtergrond-handler
    (push_service.dart / _achtergrondMomentNotificatie) bouwt de notificatie
    zelf met: largeIcon=ons_moment_logo (drawable), BigTextStyleInformation,
    color=#FF9B71, number=badge (SharedPreferences-teller). Channels hebben
    expliciet showBadge:true. Badge wordt gewist bij cold-start + app-resumed
    (WidgetsBindingObserver in RouterScherm). Tap-payload (momentId) aangesloten
    op tapMomentIdNotifier via onDidReceiveNotificationResponse +
    getNotificationAppLaunchDetails(). Cloud Function (onNieuwMoment) stuurt
    nu type/title/body/channelId in data i.p.v. notification-block.
- 3 augustus 2026: Videobel-bugs + ringtone gefixed, belfunctie nu volledig
  dekkend. Build 1.0.12+14 klaar voor Codemagic. Commits (alle groen op CI):
  - FIX A (a9b0484): inkomend gesprek bereikt ontvanger in meldingen-modus.
    Root cause: _backgroundHandler had geen 'inkomend_gesprek'-tak — FCM
    viel stil bij achtergrondse app. Oplossing: _achtergrondGesprekNotificatie
    (Importance.max, gesprekChannelId) toegevoegd; _verwerkLokaalNotificatieTik
    parst payload — JSON → incomingCallNotifier, kale string → tapMomentIdNotifier.
    Eén luisteraar (_OntvangerRouterState) handelt gesprek af in beide modi.
  - FIX B (7f444cd): eerste-bericht-race definitief opgelost. Root cause:
    _herstartListeners (getriggerd door actieveKringNotifier tijdens
    huidigeKringIdMetFallback) startte de listener met _mijnApparaatId == null;
    initiële snapshot werd overgeslagen en door Firestore niet opnieuw gestuurd.
    Drie fixes: (1) _herstartListeners wacht op _mijnApparaatId vóór listener-
    start (familie_scherm); (2) cancel() vorige subscription vóór overwrite in
    beide schermen (familie + tablet); (3) defensieve null-guard in
    tablet_scherm._verwerkMomenten. Dekt alle scenario's: familie, ontvanger
    normaal/rustig, beide apps open, alle types.
  - FIX C (0d00d98): bel.mp3 (geping) vervangen door vogel.mp3 (vogelgezang)
    — zachter, warmer belgeluid voor doelgroep. Toegepast op bel_scherm
    (ringback beller-kant) + inkomend_gesprek_scherm (ringtone callee-kant).
  - FIX D-1 (067dec0): full-screen intent voor inkomend gesprek op lock-screen.
    _achtergrondGesprekNotificatie krijgt fullScreenIntent: true +
    category: AndroidNotificationCategory.call + visibility: public.
    USE_FULL_SCREEN_INTENT stond al in manifest (V1-audit). Degradeert
    gracefully op API 34+ als toestemming niet verleend.
  - FIX D-2 (cb9b2fa): callId de-dup — twee lagen garanderen nooit twee,
    nooit nul inkomend-gesprek-scherm. Laag 1: callId-check in
    _publiceerInkomendGesprek + _verwerkLokaalNotificatieTik (geval a/b/c).
    Laag 2: _inkomendGesprekOpen-vlag in _OntvangerRouterState (bestaand).
    Terminated-app-pad al afgedekt door lijn 273 in main.dart (check huidige
    notifier-waarde direct na listener-attach).
  - Belfunctie nu dekkend in alle situaties: rustig (vergrendeld, app altijd
    voorgrond), normaal actief (meldingen, voorgrond), normaal achtergrond
    (meldingen, app gebackgrounded), volledig gesloten (full-screen intent).
  - DEBUG_VIDEOBELLEN staat op true voor gesloten test (build 1.0.12+14).
    V4 auto-answer blijft apart later traject — bevestigd.
- 3 augustus 2026: V4 auto-answer volledig gebouwd. Build 1.0.13+15 klaar
  voor Codemagic. Commits (alle groen op CI):
  - V4-1 (kring.dart): autoAnswer bool veld toegevoegd aan Kring-model
    (fromFirestore + toFirestoreMap) — default false, backward-compat.
  - V4-2 (push_service.dart): IncomingCall krijgt autoAnswer bool veld;
    uitFcmData leest data['autoAnswer'] == 'true' (FCM strings, backward-compat).
  - V4-3 (start_call.ts + deploy): startVideoCall leest kring.autoAnswer
    uit kringSnap (al in memory, geen extra read) en stuurt het als
    'true'/'false' string in FCM-payload. Server-authoritative: beller kan
    de waarde niet manipuleren. Gedeployed naar europe-west1.
  - V4-4 (main.dart): _verwerkInkomendGesprek springt bij autoAnswer==true
    direct naar GesprekScherm, slaat InkomendGesprekScherm over. Kiosk-
    hoofdpad (app altijd open) is 100% betrouwbaar. Volledig afgesloten app
    valt terug op handmatig opnemen via FIX D (full-screen notificatie +
    InkomendGesprekScherm) — Android-privacygrens, acceptabel. Tevens
    _huidigeInkomendCallId naar finally verplaatst (altijd gereset).
  - V4-5 (bel_apparaat_kies_scherm.dart): laadt kring.autoAnswer bij
    _laad(). Als aan: _bel() toont AlertDialog 'Let op: {naam} neemt
    automatisch op.' — beller moet bevestigen vóór gesprek wordt opgezet.
    Annuleer stopt stil zonder foutmelding.
  - V4-6 (familie_scherm.dart): eigenaar-only SwitchListTile 'Automatisch
    opnemen' in instellingen, achter DEBUG_VIDEOBELLEN && _benIkEigenaar.
    Optimistic update met Firestore-fallback. _actieveKringSub leest
    autoAnswer live mee bij kring-switch.
  - Resterende V4-stap: Firestore-rule handmatig toevoegen in Console
    (zie openstaande punten).
- 4 augustus 2026: Kiosk-hardening gebouwd + geïntegreerd. Build 1.0.14+16
  klaar voor Codemagic. Dit is de eerste build waarbij alles samenkomt:
  volledige belfunctie V0-V4 (bellen, auto-answer, alle FIX A/B/C/D),
  push-meldingen met badge/largeIcon/BigText, kringleden-filter, EN
  kiosk-hardening rustige modus. Commits K-1a t/m K-3 (6667e01…2b346ce):
  - K-1a: DEBUG_KIOSK flag (debug_flags.dart, standaard true voor test)
  - K-1b: KioskService (lib/services/kiosk_service.dart) + MainActivity.kt
    method channel voor startKiosk/stopKiosk/onTaskUnpinned.
  - K-1c (FASE 1): eigenaar-uitgang + failsafe-herpin in TabletScherm.
    dispose(): wis callback → herstelSysteemUI → stopLockTask (eigenaar-
    uitgang, altijd veilig). _onTaskUnpinnedDoorGebruiker(): dubbele
    mounted+modus-check + 1s delay — eigenaar-switch nooit geblokkeerd.
  - K-2 (FASE 2): startLockTask + immersiveSticky in TabletScherm.initState
    als weergaveModus != 'meldingen' (null = backwards compat = vergrendeld).
  - K-3 (FASE 3): BootReceiver.kt + RECEIVE_BOOT_COMPLETED in manifest.
    Na reboot: leest SharedPrefs flutter.ons_moment_weergave_modus →
    fullScreenIntent-notificatie (Android 10+ verbiedt directe Activity-
    start). Samsung/Xiaomi: autostart handmatig inschakelen vereist.
  Openstaande device-testpunten voor deze build:
  - Kiosk eigenaar-uitgang (KRITIEK): eigenaar wisselt modus → lock opheft,
    geen herpin.
  - Kiosk failsafe-herpin: onbedoeld unpin-gebaar → herpin binnen ~1s.
  - Home+recents-ontsnapping: bewuste handgreep kan niet 100% dicht op
    niet-beheerde tablets — failsafe-herpin is de vangnet.
  - V4 auto-answer in vergrendelde modus: gesprek komt direct binnen zonder
    InkomendGesprekScherm.
  - Bellen bij weggeveegde app: graceful fallback naar handmatig opnemen
    (FIX D full-screen intent).
  - BOOT_COMPLETED: na herstart notificatie ontvangen, tap opent vergrendelde
    modus. Samsung/Xiaomi: autostart inschakelen vereist.
  DEBUG_VIDEOBELLEN=true en DEBUG_KIOSK=true — BEIDEN terug naar false vóór
  bredere release.

## Bekende grenzen push-meldingen (eerlijk vastgelegd)

- **Badge-getal vs. badge-stip**: Android AOSP / Pixel Launcher toont een stip
  (dot) op het app-icoon, geen getal. Samsung One UI toont het getal (via
  setNumber). Nova Launcher en soortgelijke launchers: varieert.
  Dit is een launcher-beperking, niet een app-fout.
- **Badge bij volledig afgesloten app (force-stop)**: als de gebruiker de app
  expliciet via Instellingen → Apps → Geforceerd stoppen heeft gestopt, levert
  Android geen enkele FCM-bericht (ook geen van WhatsApp, Signal, enzovoort).
  Onze badge-teller (SharedPreferences in de achtergrond-handler) loopt dan
  ook niet op. Acceptabel: dit is een bewuste gebruikershandeling en treft
  alle messaging-apps gelijk.
- **android.notification.notification_count (FCM notification-block)**: alleen
  bruikbaar als er ook een notification-block is. Met data-only FCM (onze
  aanpak voor largeIcon + BigTextStyle) is dit veld niet toepasbaar zonder
  dubbele meldingen te veroorzaken. Bovendien zou de server altijd een
  benadering (getal 1) sturen — de echte oplopende teller zit in
  SharedPreferences op de client. Niet geïmplementeerd; SharedPreferences-
  aanpak dekt alle praktische scenario's.
- **Kanaalmigratie voor showBadge**: showBadge=true is de standaardwaarde
  voor AndroidNotificationChannel — bestaande kanalen hebben het al. Bij
  toekomstige wijziging van een immutable channel-instelling: patroon is
  deleteNotificationChannel(id) gevolgd door createNotificationChannel(zelfde
  id, nieuwe instellingen). Gebruikersaanpassingen worden dan gereset.

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
- **~~V2-vereiste — kring-membership check server-side~~**: opgelost in
  VB-V2-0-A (leden-doc + eigenaar-fallback parallel-read).
- **~~V2-vereiste — identity binden~~**: opgelost in VB-V2-0-A (identity
  = `{uid}_{apparaatId}`, client-input genegeerd).
- **~~V2-vereiste — rate-limiting~~**: opgelost in VB-V2-0-B (Firestore-
  transactie op `rate_limits/{uid}`, 10/rollend 60s-venster).
- **TTL-policy rate_limits/expireAt**: aanmaken zodra de collectie voor
  het eerst wordt aangeschreven (Console laat alleen bestaande collecties
  kiezen). Doe dit zodra iemand in productie voor het eerst
  getVideoCallToken heeft geraakt en de collectie in Firestore verschijnt.
  Zonder policy blijft elke uid ~50 bytes rate-limit-doc houden — geen
  crisis, wél cleanup-schuld.
- **LiveKit secret-rotatie**: procedure vastleggen (regenerate in LiveKit
  Cloud → `firebase functions:secrets:set` → redeploy). Documenteer.
- **Play Store camera-verklaring (V9)**: bij store-release verklaren dat
  CAMERA gebruikt wordt voor familie-videobellen, dat USE_FULL_SCREEN_
  INTENT bij calling-functionaliteit hoort, en dat MODIFY_AUDIO_SETTINGS
  vereist is door WebRTC audio-routing.
- **DEBUG_VIDEOBELLEN staat TIJDELIJK op true (nu build 1.0.13+15)** voor
  de gesloten-test op eigen testtoestellen. MOET terug naar false (of,
  als V6 tegen die tijd af is, vervangen door de Firestore-config-flag)
  vóór elke bredere release. Zonder deze terugzet zou elke installer
  onmiddellijk de videobel-UI zien terwijl backend en UX nog niet
  productie-klaar zijn.
- **V4 auto-answer Firestore-rule** (enige openstaande stap): handmatig
  toevoegen in Firebase Console → Firestore → Rules. Regel: alleen
  eigenaarUid mag autoAnswer schrijven op kring-doc. Zolang deze regel
  ontbreekt kan elke ingelogde gebruiker autoAnswer zetten (client-side
  toggle is al eigenaar-only, maar server-side afdwinging ontbreekt).
  Prioriteit: doen vóór bredere release.
- **Orphan-cleanup dry-run**: 17 orphan-docs geïdentificeerd; 2 echte
  apparaten beschermd (1781110668656_c561d9e1 = telefoon "j",
  1782995516100_6fef1080 = tablet "Madeira"). Wachten op expliciete
  akkoord voor verwijdering. Adresboek-filter (FIX-2) maakt de
  bellijst al schoon zonder verwijdering.
- **Structurele device-id**: apparaat-ID gebaseerd op timestamp (niet
  stabiel bij reinstall). Structurele fix (vaste hardware-ID of
  server-side UUID) is een V5-punt — nu geblokkeerd door andere prioriteiten.
- **~~KIOSK-HARDENING rustige modus~~** — GEBOUWD in build 1.0.14+16
  (K-1a t/m K-3, commits 6667e01…2b346ce). Achter DEBUG_KIOSK=true.
  Wat er ligt: Screen Pinning via startLockTask (geen device-owner);
  eigenaar-uitgang via weergaveModus-switch (KioskService.wis→stop in
  TabletScherm.dispose); failsafe-herpin na onTaskUnpinned (dubbele
  mounted+modus-check, 1s delay); immersiveSticky; BOOT_COMPLETED via
  BootReceiver → fullScreenIntent-notificatie (Android 10+).
  **Openstaand testpunt**: home+recents-ontsnapping via het Android
  unpin-gebaar (bewuste handgreep) is op niet-beheerde tablets niet
  100% dicht; failsafe-herpin vangt dit op — MOET op echt toestel
  geverifieerd worden. Samsung/Xiaomi: autostart handmatig inschakelen
  vereist voor BOOT_COMPLETED-betrouwbaarheid.
