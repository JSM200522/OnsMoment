# Ons Moment — Project Context

> Dit bestand is het permanente geheugen voor elke Claude-sessie in dit project. Lees dit eerst voordat je iets doet.

## Het doel

Ons Moment is een digitale knuffel voor mensen met dementie, verstandelijke beperking of erge vergeetachtigheid — en hun familie die zich machteloos voelt op afstand.

Familie stuurt vanaf hun telefoon een foto, stem, lied of bericht. Op het apparaat van de dierbare popt dat moment automatisch op met een vertrouwd herkenningsgeluid en hun eigen foto als warme achtergrond. Zij hoeven niks te doen — het komt naar hen toe.

Kernwaarde: "Mantelzorger App helpt JOU. Ons Moment helpt je DIERBARE."

## Naam, domein en internationale strategie

- **Naam**: "Ons Moment" blijft. Bewust Nederlands, warm, past bij de NL-doelgroep.
  Niet neutraliseren voor internationale ambitie — dat zou de kracht voor de
  NL-markt verzwakken.
- **Domein**: onsmoment.app (neutrale extensie, modern, prima voor NL-launch).
- **Internationale ambitie**: indien later relevant → een APARTE app/merknaam
  lanceren, vertaald, met eigen domein en Play Store-listing. De technische
  basis (Flutter/Firebase/belfunctie/dagklok/logica) is taal-onafhankelijk en
  grotendeels herbruikbaar; alleen de schil (naam, teksten, branding) verandert.
  NU volledig focussen op een sterke Nederlandse launch. Internationale versie =
  apart toekomstproject, te beslissen met echte data (meten, niet gokken).

## Platform-principe (vast uitgangspunt)

Ons Moment MOET op elk apparaat werken en cross-platform naadloos
samenwerken: iPhone-familie ↔ Android-familie ↔ Android-tablet bij de
dierbare (en later iPad). Sturen, ontvangen, bellen, auto-answer,
kringen, uitnodigen: alles gaat tussen al die toestellen door elkaar
heen. Regels bij elke wijziging:

1. **Data en logica blijven platform-neutraal.** Firestore, Storage,
   Auth, LiveKit-signalering, kringen, momenten, gesprek-payloads: geen
   Android-aannames in het datamodel of in de service-lagen. FCM-data
   is generiek key/value; de server (Cloud Functions) leest platform
   uit `apparaten/{id}.fcmPlatform` en kiest APNs vs Android-priority.
2. **Android-native werk zit in een aparte Android-laag** (KioskService,
   FullScreenIntentService, OverlayPermissionService, MainActivity,
   OnsMomentFcmService, BootReceiver). Elke publieke Dart-methode is
   `kIsWeb`-guarded of `defaultTargetPlatform`-gate zodat iOS er
   NAAST komt zonder herbouw en zonder dat Android↔iOS bellen breekt.
3. **Geen merk-specifieke trucs** (Samsung/Xiaomi) behalve waar Android
   dat vereist, altijd met nette fallback. Minimaal Android 12–14+
   ondersteund.
4. **Elke PR / wijziging benoemt expliciet**: (a) werkt dit op alle
   Android-toestellen? (b) raakt dit iOS/cross-platform? (c) blijft
   de data-laag platform-neutraal?

Wat NOG staat te gebeuren voor iOS (apart traject in FASE G): PushKit +
CallKit voor betrouwbaar bellen, VoIP-push met apns-priority 10, iOS
Safari audio-checklist. De hele datalaag en Firestore-rules zijn hier
al klaar voor.

## Businessmodel

- Familie Klein €4,99/maand (1 kring, max 8 leden), Familie Groot €7,99/maand (max 3 kringen, max 20 leden/kring)
- Jaar: €35,99 resp. €57,99 (~40% korting)
- 14 dagen gratis proefperiode
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
4. Stripe betaalsysteem (Klein/Groot, 14 dagen gratis proef)
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

## Vaste werkafspraak: commit ⇒ direct push (harde regel)

Na ELKE commit meteen `git push origin main`. In de samenvatting die
naar Joshua gaat MOET staan: de `git log origin/main -1` hash + de
`version:`-regel uit `pubspec.yaml` op origin/main. Nooit "gecommit"
melden zonder die push-bevestiging.

Waarom: op 9 sept 2026 zaten 7 commits (incl. drie versie-bumps
41/42/43/44) alleen lokaal. Codemagic bouwde daardoor van origin/main =
1.0.35+40, en Google Play weigerde met "versiecode 40 al gebruikt". Al
het werk was op zich klaar, maar onbereikbaar voor de build-server. Het
harde signaal (git log origin/main + pubspec op origin/main in de
samenvatting) sluit dit gat af.

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
- 4 augustus 2026: Belfixes + MainActivity K-fix code-compleet. Build 1.0.15+17
  klaar voor Codemagic-build en device-test. flutter analyze: geen issues.
  Alle commits groen op CI en gepusht naar main. Wat er ligt:
  - Fix K (7a571be): MainActivity.kt compileerfout opgelost. onTaskUnpinned()
    bestond niet — vervangen door onWindowFocusChanged(hasFocus: Boolean) +
    ActivityManager.getLockTaskModeState() (API 23+, ≥ minSdk). kioskActief-
    boolean voorkomt false positive bij eigenaar-initiated stopLockTask().
  - P2+P4+P3 (a9f03d2, gebundeld): marimba-ringtone — mixkit-marimba-
    ringtone-1359.wav gekopieerd naar assets/sounds/marimba.wav (in-app loop
    via just_audio) én android/app/src/main/res/raw/ons_moment_gesprek.wav
    (notification sound). Gesprek-channel verwijderd (immutable) + opnieuw
    aangemaakt met RawResourceAndroidNotificationSound('ons_moment_gesprek')
    + audioAttributesUsage: notificationRingtone → STREAM_RING (beltoonvolume).
    Samsung-caveat: notification sounds afgekapt op ~15s (OS-grens). P3
    gebundeld: Opnemen (showsUserInterface:true, cancelNotification:true) en
    Weigeren (showsUserInterface:false, cancelNotification:true) action buttons
    in _achtergrondGesprekNotificatie. actionId=='accept' in
    _verwerkLokaalNotificatieTik zet autoAnswer=true → direct GesprekScherm.
    _achtergrondNotificatieActie als top-level @pragma('vm:entry-point').
    getNotificationAppLaunchDetails() leest actionId bij terminated-start.
    Vogel.mp3 vervangen door marimba.wav in BelScherm + InkomendGesprekScherm.
    Versie-bump 1.0.15+17 in dezelfde commit.
  - P1 (039d721): drie auto-answer-paden gedocumenteerd in main.dart als
    inline comments. Android-grens expliciet benoemd: scherm AAN + gesloten
    app = heads-up notificatie, geen auto-launch — gebruiker tikt Opnemen
    (pad 2, actionId='accept'). Geen functie-wijziging.
  Openstaande testpunten voor 1.0.15+17:
  - Marimba luid bij gesloten app (beltoonvolume = STREAM_RING)
  - Opnemen/Weigeren knoppen zichtbaar in melding bij gesloten app
  - Opnemen → direct GesprekScherm (zonder InkomendGesprekScherm)
  - Weigeren → melding verdwijnt, geen actie
  - Kiosk eigenaar-uitgang (KRITIEK): modus wisselen → lock opheft
  - Kiosk failsafe-herpin: onbedoeld unpin → herpin binnen ~1s
  - BOOT_COMPLETED na reboot (Samsung: autostart inschakelen)
  DEBUG_VIDEOBELLEN=true en DEBUG_KIOSK=true — BEIDEN terug naar false vóór
  bredere release.
- 4 augustus 2026: Veiligheidsaudit 10-punten afgerond + geautomatiseerd
  security-traject gepland. Start NA belfunctie-test. Kritieke bevindingen:
  - Firestore rules: allow read, write: if request.auth != null op alle
    collecties → BLOCKER. Elke ingelogde gebruiker kan alle families' data
    lezen via Firestore REST API. Aanpak: isKringEigenaar(kringId) helper
    met get(/kringen/$(kringId)).eigenaarUid == request.auth.uid. Geen
    Flutter-code-aanpassingen nodig (alle queries filteren al op kringId;
    geen familieUid-veld in content-documenten — koppeling alleen via kringId).
  - Storage rules: staat onbekend (niet in repo). Controleer Console → Storage
    → Rules vóór activatie.
  - Cloud Functions: groen. Auth ✓, kring-membership ✓, rate-limiting ✓,
    apparaat-verify ✓, secrets in Secret Manager ✓. Geen actie vereist.
  Zie sectie "Security hardening" in Openstaande punten voor het complete plan.
- 8 augustus 2026: Security FASE 1 code-compleet + 58/58 tests groen.
  Drie Flutter-fixes ook gebouwd (commits op main, CI groen):
  - Stale-snapshot bug in _AudioInstelDialog: opname meteen zichtbaar na upload
    zonder dialog te sluiten. DagelijksAudioService.upload() geeft URL terug;
    dialog werkt eigen state bij. Openers fetchen fresh DocumentSnapshot.
  - G1: aankomstgeluid direct kiesbaar bij nieuw moment. Draft-mode in
    _AudioInstelDialog (optionele doc + onDraftSave). Bytes gehouden in parent
    state; mee-uploaden na add() met ref.id. Identiek patroon als foto.
  - Testbreekende bug: _toonDagelijksPopup/_toonEenmaligPopup bouwden altijd
    type:'dagelijks' ongeacht mediaType. _maakSyntheticDoc() helper toegevoegd
    (spiegel van tablet_scherm.dart). Backwards-compat: geen mediaType → oud gedrag.
  Security FASE 1: firestore-tests/ met 29 legitieme + 29 aanvals-testgevallen.
  Java 21 (OpenJDK) geïnstalleerd op Joshua's machine. Rules NIET geactiveerd
  op live DB — wacht op toesteltest FASE A + bevestiging van eigen toegang.
  Zie "ALS IK THUIS BEN — WEG NAAR LAUNCH" checklist voor het volledige pad.
- 27 augustus 2026: Grote toesteltest (FASE A) deels uitgevoerd. Kernflow
  (momenten sturen/ontvangen, meldingen, bellen bij app open) werkt. Vier
  bevindingen onderzocht; beslissingen:
  - PUNT 2 OPGELOST — meldingsgeluid bij gesloten app (Pixel): bleek
    telefooninstelling (meldingsvolume/geluidsprofiel op de Pixel stond laag).
    Geen app-bug. FIX A (kanaal delete+recreate voor moment-kanalen) NIET gebouwd
    — niet nodig. ✓
  - PUNT 1 OPEN — videobel-knop ontbreekt op homescherm kleine telefoon:
    diagnose = lay-outprobleem. Knop staat in StuurTab (familie_scherm.dart:1395)
    achter `if (DEBUG_VIDEOBELLEN && !widget.alsOntvanger)` — logica klopt.
    Content vóór de knop is ~540dp (titel + 3 rijen tegels + spacers + padding);
    op kleine telefoons waar de body-hoogte < ~540dp valt de knop net onder de
    vouw. SingleChildScrollView maakt scrollen mogelijk maar toont geen indicator.
    Apparaat was in familie-modus (bevestigd: InstellingenTab toonde eigenaar-items).
    De "bel-optie in Instellingen" was de auto-answer-toggle in BelApparaatKies-
    Scherm (app-titel "Videobellen"), bereikbaar via de knop die via scrollen
    gevonden was. Fix-richting: knop omhoog plaatsen of scroll-indicator toevoegen
    — beslissing en uitvoering nog open.
  - PUNT 3+4 OPEN — Samsung bel bij gesloten app (geen ringtone + Weiger-knop
    doet niks): advies gegeven (zie Openstaande punten — Videobellen). Beslissing
    over aanpak nog open. Nog niet bouwen.

## Bel-architectuur (definitief, sept 2026)

Na het BEL-A t/m BEL-S traject en de C1..C6-consolidatie is dit de
DEFINITIEVE opzet. Wat hier staat werkt op alle geteste toestellen; wat
in de "NIET meer proberen"-lijst staat is bewezen niet-productie-waardig.

**Twee schermen, één architectuur:**
1. **Vergrendelde modus (rustig)** — Ons Moment staat 100% voorgrond via
   Screen Pinning (K-1..K-3). FCM foreground-pad → `incomingCallNotifier` →
   `_OntvangerRouterState._verwerkInkomendGesprek` →
     - `autoAnswer=true` → `AutoOpnemenWaarschuwingScherm` (2.5s) →
       `GesprekScherm`. Geen tik nodig.
     - `autoAnswer=false` → `InkomendGesprekScherm` (rinkelend, 35s
       timeout, twee grote knoppen). Handmatig opnemen → `GesprekScherm`.
   Deze modus is 100% betrouwbaar — geen Android-restricties in de weg.
2. **Meldingen-modus (normaal)** — het toestel werkt als gewone tablet.
   `_backgroundHandler` → `_achtergrondGesprekNotificatie` toont
   heads-up-notif via channel `ons_moment_gesprek_v2` (max importance,
   category.call, fullScreenIntent, marimba-ringtone via STREAM_RING).
     - Scherm UIT / lockscreen: fullScreenIntent auto-launcht MainActivity
       → InkomendGesprekScherm. Werkt op Pixel + Samsung.
     - Scherm AAN, app gesloten: heads-up-notif verschijnt. Body-tap →
       InkomendGesprekScherm. `handmatigGeaccepteerd=true` slaat de
       tussenschermen over en gaat direct naar `GesprekScherm`.
     - Auto-answer bij scherm AAN + app gesloten: door Android BAL-
       restrictie werkt fullScreenIntent-auto-launch dan niet. **Zonder
       SYSTEM_ALERT_WINDOW-toestemming** valt hij terug op de heads-up-
       notif; gebruiker moet dan alsnog tikken. Zie DEEL A voor de
       overlay-oplossing.

**Ringtone-timing:**
- InkomendGesprekScherm rinkelt via `just_audio` (marimba.wav in-app,
  looped, STREAM_RING) tot 35s → auto-afwijzen + gemist-melding.
- Achtergrond-notif speelt marimba éénmalig (~15s Samsung-limiet);
  `_herhaalGesprekMelding` toont ~3× dezelfde melding met nieuwe ID
  zodat OS opnieuw play triggert. Cross-isolate stop-vlag in
  SharedPreferences per callId zodra user tikt.

**Gemist gesprek (BEL-C3):**
- 35s zonder actie → `PushService.toonGemisteOproep(bellerNaam)` toont
  rustige melding via channel `ons_moment_gemist_v1` (importance.default,
  category.missedCall, geen ringtone). Vaste notification-ID 1010 zodat
  een tweede gemist gesprek de eerste vervangt.

**Weiger vanuit dichte app:**
- InkomendGesprekScherm's `Niet nu` roept `VideoCallService.cancelCall`
  vanuit main-isolate — daar leeft echte Firebase Auth. Beller-app
  ontvangt `gesprek_geannuleerd`-FCM en stopt met rinkelen.
- Achtergrond-isolate weiger-pad gebruikt gepersisteerd idToken
  (`_kBelIdTokenKey`) + directe HTTPS-POST naar cancelVideoCall-callable.

**Optie B (callkit) is dood.** `CALLKIT_HARD_UIT=true` sinds C1. Code
blijft in de repo voor archief-doeleinden maar wordt NOOIT geraakt in
productie.

## NIET meer proberen (bewezen niet-oplossingen)

- **Forceer-accept bij cold-start launch**: BEL-S6/S7 zetten bij
  `getNotificationAppLaunchDetails().didLaunch=true` `handmatigGeaccepteerd=true`.
  Bij scherm-UIT stand-by kon het BE gewoon een fullScreenIntent-auto-
  launch zijn (geen tik). Gevolg: dierbare kreeg ineens gespreksgeluid
  zonder toestemming. Fix in S9: nooit forceren, laat autoAnswer/tik
  het scherm bepalen.
- **Action buttons (`Opnemen`/`Weigeren`) op de heads-up-notif**:
  Android 12+ notification-trampoline-restricties + Samsung battery-opt
  maken `showsUserInterface:false` onbetrouwbaar. Bevestigd door
  meerdere testrondes: `cancelNotification` werkt half, action-handler
  wordt niet altijd getriggerd. Nu doen we alles via body-tap +
  InkomendGesprekScherm (waar knoppen 100% betrouwbaar zijn).
- **Callkit / ConnectionService / TelecomManager** (Optie B): PhoneAccount-
  registratie flakey op Samsung, dubbele ringtone met just_audio, en
  auto-answer botst met de vereiste "tap om op te nemen". Weken werk
  voor onduidelijk voordeel. `CALLKIT_HARD_UIT=true`.
- **Meer dan één FSI-prompt-plek**: eerder stond de prompt zowel in
  `FullScreenIntentService.controleerEnPromptAlsNodig` (aangeroepen
  vanuit main.dart) én in `FamilieScherm._checkBelPromptsMeldingenModus`.
  Dubbele dialogs bij modus-switch. Nu één plek (FamilieScherm), met
  7-dagen dismiss-cache.

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

Onboarding herinrichting (OB-traject):
- **OB-3 keuze-scherm testen met eerste testfamilies** (commit 7cc2b14): het
  nieuwe 3-kaart keuze-scherm (Familielid / Ontvanger / Uitnodigingscode) is
  een bewuste UX-keuze. Checken bij de eerste echte gebruikers: begrijpen ze
  onmiddellijk welke kaart voor hen bedoeld is? Struikelen ze over 'Ontvanger'
  als term, of is dat duidelijk? Feedback kan leiden tot aanpassing van
  kaart-tekst of volgorde.
- **OB-4**: compacte profielstap (alleen naam + foto + geluid; dagelijkse
  momenten eruit naar InstellingenTab) — nog te bouwen.
- **OB-5**: lievelingsdingen, woonplaats, noodcontact, dagelijkse momenten
  verplaatsen naar InstellingenTab — nog te bouwen.
- **OB-6**: gast-route stylen (accept_uitnodig_scherm + gast_signup_scherm)
  — nog te bouwen.

Geplande momenten (grote UX-verbetering, apart traject — NIET nu bouwen):
- **GEPLANDE MOMENTEN VERBETEREN**: Nu kan 'momenten beheren' alleen titel +
  geluid (eigen stem/liedje). Doel: momenten beheren wordt de complete, heldere
  plek voor ALLE planning — herhalend én eenmalig — met volledige media (tekst,
  foto, video, stem, liedje) én herinneringen, niet alleen titel+geluid.
  Twee kanten moeten grondig ontworpen worden:
  1. PLAN-KANT (familie): de layout/flow van het plannen zelf — duidelijk kiezen
     tussen herhalend vs. eenmalig, welk type, welke media, welk tijdstip. Nu
     verwarrend en beperkt; moet helder en compleet.
  2. ONTVANGER-KANT: hoe een gepland moment fijn, mooi en duidelijk binnenkomt/
     verschijnt bij de kwetsbare ontvanger (rustige én normale modus) — passend
     bij de warme dagtijdlijn (dagklok stap 3+4).
  Voorbeeld-use-case: 'elke dag een foto van de kleinkinderen laten verschijnen'.
  Dit is onze onderscheidende troef t.o.v. concurrenten (RecallCue e.a. scheiden
  kale agenda van losse foto's; wij plannen álles warm samen).
  Grote klus — raakt datastructuur (dagelijkse_momenten/gepland_momenten/momenten)
  + media-upload in de plan-flow. Eerst een grondig ontwerp-onderzoek
  (plan-kant + ontvanger-kant) vóór er gebouwd wordt.

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
- **TTL-policy actieveGesprekken/expireAt** (BEL-R3, build 1.0.23+26):
  vangnet voor de bezet-slot-cleanup. Client + server ruimen bij normaal
  eind (hangup, cancel, decline) het slot expliciet op, maar bij een
  app-crash of netwerkverlies moet de TTL het overnemen (max 5 min). De
  collectie bestaat pas ná het eerste OPGENOMEN gesprek met de nieuwe
  build — daarvoor is er geen doc en biedt Console geen keuzelijst.
  Volgorde:
  1. Toestel-test met build 1.0.23+26 → bel opnemen → collectie
     `actieveGesprekken` verschijnt in Firestore Console.
  2. Google Cloud Console → Firestore → TTL → collection group
     `actieveGesprekken`, timestamp field `expireAt`, offset `0 seconds`.
  3. Vóór publieke launch (FASE D) afronden.
  Zonder policy blijven verweesde slots ~5 min bestaan (door de
  expireAt-datum die de reserveerBezetSlot-helper zet) — de check zelf
  respecteert die expireAt en behandelt verlopen slots al als "vrij",
  dus geen bel-blokkade. De TTL-policy zorgt alleen dat Firestore de
  verlopen docs OOK fysiek opruimt (bespaart storage-kosten).
- **LiveKit secret-rotatie**: procedure vastleggen (regenerate in LiveKit
  Cloud → `firebase functions:secrets:set` → redeploy). Documenteer.
- **Play Store camera-verklaring (V9)**: bij store-release verklaren dat
  CAMERA gebruikt wordt voor familie-videobellen, dat USE_FULL_SCREEN_
  INTENT bij calling-functionaliteit hoort, en dat MODIFY_AUDIO_SETTINGS
  vereist is door WebRTC audio-routing.
- **DEBUG_VIDEOBELLEN staat TIJDELIJK op true (nu build 1.0.15+17)** voor
  de gesloten-test op eigen testtoestellen. MOET terug naar false (of,
  als V6 tegen die tijd af is, vervangen door de Firestore-config-flag)
  vóór elke bredere release. Zonder deze terugzet zou elke installer
  onmiddellijk de videobel-UI zien terwijl backend en UX nog niet
  productie-klaar zijn.
- **PUNT 1 — Videobel-knop onder de vouw op kleine telefoon**: knop staat
  in StuurTab onderaan, 4e rij na foto/video/stem/lied/tekst/hartje. Content
  vóór de knop = ~540dp; op kleine telefoons (kleine body-hoogte of grote
  lettergrootte/weergavegrootte in Toegankelijkheid) valt de knop net buiten
  beeld. Scrollen onthult hem, maar SingleChildScrollView toont geen indicator.
  Twee fix-richtingen: (A) knop omhoog in de StuurTab-volgorde (boven de
  type-selectie), of (B) eigen "Bellen"-knop in de bottom navigation bar.
  Beslissing + uitvoering: gepland, datum open.
- **PUNT 3 — Samsung: geen beltoon bij gesloten app (meldingen-modus)**:
  Oorzaak: bij gesloten app speelt het ons_moment_gesprek-kanaal de marimba
  eenmalig (~15s, Samsung-limiet). De loopende just_audio-ringtone (in
  InkomendGesprekScherm) start pas als de notificatie wordt aangetikt en de
  app opent. Bij vergrendeld/kiosk-modus werkt bellen 100% betrouwbaar
  (app altijd voorgrond, FCM-foreground pad). Aanpak-advies:
  Optie A (nu): accepteer beperking voor meldingen-modus; vergrendeld=primary.
  Optie B (later): ConnectionService / CallKit voor echte telecom-integratie
  (WhatsApp-niveau, weken werk, pas bij iOS-traject). Beslissing open.
- **PUNT 4 — Weiger-knop op notificatie doet niks bij gesloten app**:
  Oorzaak: `cancelNotification: true` werkt niet betrouwbaar bij terminated
  app + Samsung battery optimization. De background isolate's `initialize()`
  registreert `onDidReceiveBackgroundNotificationResponse` NIET (zie
  push_service.dart:636-640), waardoor de handler bij gesloten app mogelijk
  niet actief is. Gerichte fix: voeg `onDidReceiveBackgroundNotificationResponse:
  _achtergrondNotificatieActie` toe aan de `initialize()` call in
  `_achtergrondGesprekNotificatie()`. Minimalistische code-aanpassing (1 veld).
  Beslissing + uitvoering: gepland, datum open.
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

Security hardening (geprioriteerd traject — start NA belfunctie-test 1.0.15+17):
- **KRITIEK BLOCKER — Firestore rules aanscherpen** (vóór open test/launch):
  Huidige rules: allow read, write: if request.auth != null → elke ingelogde
  gebruiker kan alle families' data lezen/schrijven via Firestore REST API.
  Correcte aanpak: isKringEigenaar(kringId)-helper met get()-call op
  kringen/{kringId}.eigenaarUid == request.auth.uid. Geldt voor momenten,
  dagelijkse_momenten, gepland_momenten, notities. Kringen: eigenaarUid-check
  direct. Gebruikers/{uid}: uid-check direct. Leden subcollectie: lidUid-check.
  GEEN Flutter-code-aanpassingen nodig — alle queries filteren al op kringId;
  er is geen familieUid-veld in content-documenten (koppeling uitsluitend via
  kringId, bevestigd in code-audit).
- **KRITIEK BLOCKER — Storage rules controleren** (vóór open test/launch):
  Huidige staat onbekend — niet in repo, beheerd in Console. Open Console →
  Storage → Rules en controleer. Indien permissief: aanscherpen vóór activatie
  Firestore-rules. Structuur bepaalt de regels (zie sessielog 4 aug audit).
- **~~GATE — Geautomatiseerde testset~~** — KLAAR (8 aug 2026): firestore-tests/
  gebouwd met @firebase/rules-unit-testing + Jest + Firebase Emulator (Java 21).
  58/58 tests groen: 29 legitieme app-handelingen slagen, 29 aanvalspogingen
  geblokkeerd. Commando herhalen:
  $env:PATH = "C:\Program Files\Microsoft\jdk-21.0.12.8-hotspot\bin;" + $env:PATH;
  firebase emulators:exec --only firestore "cd firestore-tests && npm test"
- **Veilige uitrolstrategie** (activeren PAS als Joshua terug is van vakantie
  en eigen app-toegang heeft bevestigd):
  1. ~~firestore-tests/ bouwen + java-check + npm install~~ — KLAAR
  2. ~~firestore.rules lokaal schrijven~~ — KLAAR
  3. ~~firebase emulators:exec → alle tests groen~~ — KLAAR (58/58)
  4. Storage-rules verifiëren in Console — OPENSTAAND
  5. Rules activeren in Console (na toesteltest FASE A)
  6. 30 min monitor Cloud Function logs na activatie
  7. Rollback indien nodig (< 1 min via Console History)
- **BELANGRIJK — E-mailverificatie server-side** (vóór launch, NIET nu):
  ZeptoMail-koppeling is klaar (15 aug 2026) — mails komen van eigen domein.
  Afdwingen van verificatie (request.auth.token.email_verified == true in
  Firestore rules) is een aparte stap die pas mag na: (1) betaalsysteem, (2)
  trial-lock. Reden: nep-accounts zoals oma@test.nl worden anders buitengesloten
  en testers lopen vast. Aanpak: bestaande accounts eerst verifiëren, dan rule
  activeren. Voorkomt subscription-bypass bij betaallancering.
- **BELANGRIJK — AVG/Privacy** (vóór launch):
  Privacy Policy schrijven + in-app tonen (AVG art. 13, wettelijk verplicht).
  Right to erasure implementeren (AVG art. 17, verwijderAccount()-flow).
  Data retention policy. Bijzondere persoonsgegevens (dementie/zorgcontext)
  vereisen expliciete toestemming (AVG art. 9).
- **BELANGRIJK — Git + API-key restricties** (na rules-fix):
  .gitignore uitbreiden: lib/firebase_options.dart + google-services.json.
  Web API key restricties in Google Cloud Console (HTTP-referer:
  jsm200522.github.io). Sleutelrotatie NIET nodig — Firebase API keys zijn
  semi-publiek bedoeld; bescherming zit in rules, niet in geheimhouding.
- **Cloud Functions**: groen bevonden in audit (auth ✓, membership ✓,
  rate-limiting ✓, apparaat-verify ✓, secrets in Secret Manager ✓). Geen actie.

## ALS IK THUIS BEN — WEG NAAR LAUNCH

Geordende checklist van eerste toesteltest tot store-launch.
Doorloop de fasen op volgorde. Niets overslaan.

### FASE A — Grote toesteltest (eerste actie thuis, build 1.0.18+20)

Op beide toestellen (Pixel = schoon Android, Samsung/tablet = One UI),
beide modi (rustig + normaal). Noteer per punt OK / FOUT / NVTB.

**Geplande momenten — alle 5 types:**
- [ ] Foto: komt op juiste tijd aan, toont de foto mooi?
- [ ] Video: speelt af, geen freeze?
- [ ] Tekst: leesbaar, juiste lettergrootte voor doelgroep?
- [ ] Stem: hoorbaar zonder extra tap? (kon niet op web testen)
- [ ] Liedje: speelt volledig af?
- [ ] Dagelijks herhalend moment: komt het de volgende dag opnieuw?

**Aankomstgeluid:**
- [ ] Standaard herkenningsgeluid hoorbaar bij binnenkomen moment?
- [ ] Eigen stem als herkenningsgeluid hoorbaar? (kon niet op web)

**Bellen — alle situaties:**
- [ ] Rustige modus (vergrendeld, app altijd voorgrond): gesprek binnenkomt?
- [ ] Normale modus actief (meldingen, app voorgrond): gesprek binnenkomt?
- [ ] Normale modus achtergrond (app gebackgrounded): melding + ringtone?
- [ ] App volledig weggeveegd: full-screen intent + marimba luid?
- [ ] Auto-answer in dock (rustige modus): gesprek opent direct zonder tik?
- [ ] Marimba groot + luid (beltoonvolume, niet meldingsvolume)?
- [ ] CallStyle-melding zichtbaar met Opnemen + Weigeren knoppen?
- [ ] Opnemen-knop → direct GesprekScherm (geen InkomendGesprekScherm)?
- [ ] Weigeren-knop → melding verdwijnt, geen actie?
- [ ] USE_FULL_SCREEN_INTENT toestemming gevraagd (API 34+)?

**Weekstrip + eerste bericht + normale meldingen:**
- [ ] Weekstrip correct weergegeven?
- [ ] Eerste bericht na inloggen direct zichtbaar?
- [x] Push-melding met largeIcon + badge bij nieuw moment?
      Pixel: OK na aanpassen meldingsvolume (telefooninstelling, geen app-bug). ✓

**Randgevallen:**
- [ ] Tablet-scherm uit → komt gepland moment alsnog aan als scherm aan gaat?
- [ ] Tablet herstart → verschijnen geplande momenten weer? (BOOT_COMPLETED)
- [ ] Home+recents-ontsnapping → failsafe-herpin binnen ~1s?
- [ ] Kiosk eigenaar-uitgang: modus wisselen → lock opheft, geen herpin?

**Cross-Android:**
- [ ] Alles werkt op Pixel (schoon Android) én Samsung (One UI)?
      Let op: Samsung knipt notificatiegeluiden af na ~15s (OS-grens, acceptabel).
      One UI badge toont getal; Pixel toont stip — beide correct.

Fix wat nodig is vóór verder gaan naar Fase B.

### FASE B — Security activeren (na geslaagde toesteltest)

- [ ] Open live app → bevestig: eigen kring zichtbaar, momenten werken, bellen OK
- [ ] Controleer Storage rules in Firebase Console → Storage → Rules
      (staat onbekend; aanscherpen als permissief)
- [ ] Plak `firestore-tests/firestore.rules` in Console → Firestore →
      Rules → Publiceren (tests zijn 62/62 groen incl. kring-limiet)
- [ ] 30 min monitoren: Cloud Function logs (`firebase functions:log`)
- [ ] Bij problemen: Console → Rules → History → Revert (< 1 min)

### FASE C — Van test naar echt

- [ ] E-mailverificatie AFDWINGEN (ZeptoMail werkt al sinds 15 aug 2026):
      VER-1 (9 sept 2026) is code-compleet: `verificatie_gate_service.dart`
      + `verificatie_afdwingen_scherm.dart` + RouterScherm-inplug. Draait
      achter TWEE Firestore-config-flags in `config/features`:
        - `emailVerificatieAfdwingen: bool` (default false → gate uit)
        - `emailVerificatieGraceTot: Timestamp` (accounts van vóór deze
          datum ongestoord — bescherming voor bestaande testers)
      Gate zit ALLEEN op familie-tak in RouterScherm; ontvanger/tablet-
      modus wordt nooit geblokkeerd (dierbare mag niet gestraft worden).
      Fail-soft in de service: elke Firestore-fout of missende config →
      niet blokkeren. Zolang de flag false is verandert er NIETS aan het
      huidige gedrag; de bestaande banner in InstellingenTab blijft
      informatief zichtbaar.
      **Volgorde dwingend** vóór activeren van de flag:
        1. Betaalsysteem werkend (D-2 t/m D-6).
        2. Trial-lock werkend (D-5).
        3. Nep-testaccounts (oma@test.nl e.a.) opruimen of grace-datum
           ná hun creationTime zetten.
        4. `emailVerificatieGraceTot` in Firebase Console zetten op een
           tijdstip ná alle huidige testers.
        5. `emailVerificatieAfdwingen: true` flippen in Firebase Console.
      Server-side sluitstuk (`request.auth.token.email_verified == true`
      in de rules) is optioneel later — client-side gate is voor nu
      voldoende.
- [ ] Trial-expiry-lock (NIET bouwen vóór betaalsysteem werkt):
      Na 14 gratis dagen zonder actief abonnement de eigenaar mild locken —
      toegang beperkt tot PakketKeuzeScherm, maar dierbare blijft ontvangen
      wat er al staat. Volgorde dwingend: (1) betaalsysteem werkend + getest,
      (2) lock inbouwen, (3) betaling heft lock op. Lock vóór betalen =
      testers buitengesloten zonder uitweg. PakketKeuzeScherm (disabled
      betaalknop) en proefStart-veld liggen al klaar in de code.
- [ ] Firebase Auth mail-templates: NL + "Ons Moment" branding controleren

### FASE D — Betaalsysteem + finale flags

- [ ] Google Play Billing inbouwen + testen (vereist toestel + Play Store):
      14 dagen proef, pakketten Klein/Groot, jaar 40% korting.
      Kring-aantal-limiet (1 vs 3) server-side afdwingen in Firestore rules.
      Daarna PakketKeuzeScherm-betaalknop activeren.
- [ ] Privacy Policy schrijven + in-app tonen (AVG art. 13, wettelijk verplicht)
- [ ] Right to erasure implementeren (AVG art. 17, verwijderAccount()-flow)
- [ ] In-app teksten/FAQ controleren: staat overal "per kring", nergens "totaal"?
- [ ] DEBUG_VIDEOBELLEN → false in lib/data/debug_flags.dart
- [ ] DEBUG_KIOSK → false in lib/data/debug_flags.dart
- [ ] V4 autoAnswer Firestore-rule handmatig toevoegen in Console:
      alleen eigenaarUid mag autoAnswer schrijven op kring-doc
- [ ] Web API-key beperken tot jsm200522.github.io (Google Cloud Console →
      API & Services → Credentials → HTTP-referer). Na rules-activatie doen.
- [ ] TTL-policy aanmaken op rate_limits-collectie zodra de eerste echte
      videobel in productie is geweest (collectie verschijnt dan in Console).
- [ ] Budget-alert verhogen van €5 naar €20–50 bij eerste echte gebruikers.

### FASE E — Website publiceren (Lovable-tokens terug ~8 sept)

- [ ] Publiceren naar Netlify: verbeterde mobiele weergave, prijs-presentatie,
      schema-markup (Organization + SoftwareApplication), llms.txt,
      URL-correctie (alles naar onsmoment.app, geen subpaden).
- [ ] Na publiceren checken: sitemap.xml, robots.txt, llms.txt correct op
      onsmoment.app; Rich Results Test groen voor schema-data.
- [ ] NOOIT DNS naar Lovable wijzen (185.158.133.1 / _lovable CNAME) —
      domein blijft bij Netlify. Lovable alleen als editor gebruiken.

### FASE F — Google Play live

- [ ] Versie bumpen (nieuwe release-build, DEBUG-flags op false)
- [ ] Codemagic release-build (.aab) maken + ondertekenen
- [ ] Play Console listing afmaken:
      - Screenshots: telefoon min. 2 + 7-inch + 10-inch tablet
      - Store-omschrijving NL (kort + lang)
      - App-icoon 512×512
      - Feature graphic 1024×500
- [ ] Camera/USE_FULL_SCREEN_INTENT/MODIFY_AUDIO_SETTINGS verklaren in
      Play Console (Data safety + permissions)
- [ ] .aab uploaden als closed test (vereist: min. 12 testers, 14 dagen)
- [ ] Na 14 dagen closed test zonder blockers: productie aanvragen

### FASE G — iOS (apart traject, ná Android live)

Groot apart traject — niet nu plannen. Fundering staat al klaar
(data-model platform-neutraal, apns-blok priority 5 al aanwezig in FCM).
Wat er straks specifiek bij komt kijken voor iOS:
- Apple Developer-account (99 EUR/jaar) + Mac of Codemagic macOS runner
- PushKit + CallKit voor betrouwbaar bellen op iOS (apns-prioriteit 10 +
  VoIP-push), flutter_local_notifications iOS-pad
- iOS Safari audio-checklist (autoplay-restricties anders dan Android)
- App Store Connect listing + TestFlight closed beta (verplicht vóór productie)
- App Store review 1-2 weken

## Post-launch ideeën (bij groei, niet nu)

- **Publiek ideeën-bord**: nu hebben we een simpel privé-feedbackformulier
  (Firestore `feedback`-collectie, create-only, alleen Joshua ziet het via
  Console) — dat past bij de testfase + doelgroep. Als het gebruikersaantal
  groeit naar honderden+: overweeg een publiek ideeën-bord waar gebruikers
  ideeën posten, anderen erop stemmen (duimpje), en het populairst bovenaan
  komt. Niet zelf bouwen — koppel een kant-en-klare tool (Canny, Featurebase
  of Upvoty) via een link in de app. Reden om te wachten: bij weinig
  gebruikers is een bord leeg/stil, en publiek delen past minder bij deze
  gevoelige doelgroep. Simpel privé-vak blijft voorlopig het juiste.
