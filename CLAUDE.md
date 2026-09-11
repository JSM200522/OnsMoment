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

**WACHT OP (per 10 sept 2026)**: Verkopersaccount Google Play aangemaakt op
zakelijk profiel JS Milhous (KVK 94498695). WACHT op Google's testbedrag op
Revolut (IBAN eindigt op 2199), rond 9–13 sept. Zodra binnen: bedrag invullen
op payments.google.com → geverifieerd → **D-0 vervolg**: 4 abonnementen
aanmaken (familie_klein €4,99/€35,99 + familie_groot €7,99/€57,99), **GEEN
Play-free-trial** (14 dagen proef doen we via eigen `proefStart`-veld),
license-testers registreren, service-account voor Play Developer API
aanmaken → koppelen aan RevenueCat (~24u propagatie) → RTDN (Real-Time
Developer Notifications) instellen. **Daarna D-2 t/m D-6**: RevenueCat SDK
in Flutter inbouwen, PakketKeuzeScherm-knop activeren, entitlement-listener,
webhook naar Cloud Function, server-side tier/abonnement update, restore
flow. RevenueCat-project "Ons Moment" bestaat al. **D-1 (Firestore rules
server-only tier/abonnement) is klaar** (commit bb5948a, 8 sept 2026).

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

### FASE G — iOS (voorbereiding)

**Status (11 sept 2026)**: onderzoeksfase, met **correctie op eerdere
conclusie** over auto-answer (zie punt 2). Android-launch gaat voor;
iOS-werk pas ná FASE F. Hieronder de complete iOS-gereedheidscheck +
gefaseerd plan voor later. **PUUR PLAN — geen code aanraken tot Android
in productie staat.**

---

**1. FUNDERING — is de data/logica-laag iOS-klaar?**

Kort antwoord: **ja voor 90%, één gat om later te dichten.**

Iets specifieks aan iOS blokkeert de fundering nergens:
- **Firestore/Storage/Auth/kringen/momenten/notities**: geen Android-
  aannames. Alle koppeling via `kringId` + `familieUid`, geen platform-
  velden in content-documenten. iPhone-familie ↔ Android-familie ↔
  Android-tablet werkt straks kruislings uit dezelfde kring. ✓
- **LiveKit** (`livekit_client ^2.2.4`): WebRTC voor iOS én Android,
  identieke room-signalering. Cloud Function `getVideoCallToken` is
  platform-neutraal. ✓
- **FCM data-only push**: server-code (`functions/src/index.ts`,
  `start_call.ts`, `cancel_call.ts`) heeft al `apns`-blokken met
  `apns-push-type: 'background'` + `apns-priority: '5'` +
  `contentAvailable: true`. Kant-en-klaar voor iOS-momenten-push. ✓
- **`fcmPlatform`-veld** op `gebruikers/{uid}/apparaten/{id}`:
  `apparaat_service.dart:102` schrijft al 'android'|'ios'|'web' via
  `PushService._huidigPlatform()` (push_service.dart:786). De server
  leest dit veld nog niet, maar het staat klaar voor per-platform
  routing (bijv. VoIP-push alleen naar iOS). ✓
- **`kIsWeb`-guards**: 97 keer verspreid over 17 files; `defaultTargetPlatform`
  wordt op 4 plekken juist gebruikt. Alle Android-native calls (KioskService,
  OverlayPermissionService) zijn kIsWeb-guarded én ge-try/catched — op iOS
  wordt de MethodChannel `nl.onsmoment.kiosk` niet gevonden en de code
  valt fail-soft terug. ✓ Geen `Platform.isAndroid`-branches gevonden die
  iOS zouden uitsluiten.

**Het ene gat**: `lib/firebase_options.dart` heeft alleen `web` +
`android` blokken; iOS valt via `default:` terug op `web` — dan raakt
Firebase op iPhone in de war. Op te lossen zodra Firebase Console een
iOS-app krijgt (kan NU al zonder Mac).

**Android-native laag** (blijft parallel bestaan naast iOS-native): 535
regels Kotlin (`MainActivity.kt` 255, `OnsMomentFcmReceiver.kt` 206,
`BootReceiver.kt` 74) + `AndroidManifest.xml` (135 regels). Alles achter
één MethodChannel + fail-soft aan Dart-kant, dus iOS krijgt gewoon
`return false`/`return null` op elke call. Native iOS-equivalent moet
in Swift geschreven worden (zie punt 2 + punt 6).

---

**2. BELLEN op iOS — twee bewezen auto-answer-routes**

> **Correctie op 10 sept-conclusie**: eerder stond hier dat "auto-answer
> op iOS niet kan omdat Apple het verbiedt". Dat was te somber en
> feitelijk onjuist. Uit web-onderzoek 11 sept 2026 blijkt: er zijn
> **twee productie-waardige routes** waarmee Ons Moment op iOS/iPad
> automatisch een gesprek opneemt. Elk met eigen sweet-spot en één
> eerlijke beperking (video op vergrendeld scherm).

**Route A — CallKit + iOS-systeeminstelling "Oproepen automatisch beantwoorden"**

Apple heeft een **ingebouwde systeemfunctie** in Toegankelijkheid:
`Instellingen → Toegankelijkheid → Aanraken → Audioroutering oproep →
Oproepen automatisch beantwoorden` (met instelbare vertraging, 3-60s).
Deze functie beantwoordt automatisch:
- normale telefoongesprekken
- FaceTime (audio + video)
- **alle third-party VoIP-apps die Apple's CallKit gebruiken** —
  bevestigd voor WhatsApp, Skype, Viber, en soortgelijken

Bron: Apple Support "Route and automatically answer calls on iPhone"
en AbilityNet iOS 15/16/17/26-gidsen. Werkt óók op iPad. Onze app
hoeft NIETS bijzonders te doen — een normale CallKit-integratie via
PushKit VoIP-push activeert automatisch dit accessibility-gedrag als
de gebruiker het aan heeft staan.

**Gedrag per scherm-toestand (grondig geverifieerd)**:

| iPad-toestand | Gedrag bij Auto-Answer aan + CallKit-call met hasVideo=true |
|---|---|
| Ontgrendeld, app open | Auto-beantwoord → `CXAnswerCallAction` fired → app foreground → LiveKit-join → **volledig video + audio** ✓ |
| Ontgrendeld, app dicht (background/killed) | Auto-beantwoord → iOS launcht app → `CXAnswerCallAction` fired → LiveKit-join → **volledig video + audio** ✓ |
| Vergrendeld (scherm uit) | Auto-beantwoord → iOS probeert Face ID / Touch ID / passcode-authenticatie. **Slaagt authenticatie**: app foreground → volledig video + audio ✓. **Faalt authenticatie**: gesprek is beantwoord in CallKit-systeem-UI, maar app opent niet en video start niet — **alleen audio tot iemand ontgrendelt** |

Dit lock-screen-gedrag is een **Apple-systeem-grens**, niet iets dat wij
kunnen omzeilen. Bevestigd door Apple DTS Engineer Kevin Elliott in
developer forum thread 798090: "Video call op lockscreen — systeem
probeert unlock, bij succes launcht app; bij mislukking blijft de call
in de lock-screen UI." Zelfde beperking geldt voor WhatsApp — Apple
Community-thread 254532378 bevestigt: "WhatsApp videocall answer with
no video" op locked screen tot handmatig unlock.

**Bekende iOS 16.2+ bug**: zelfs na succesvolle unlock opent de app
soms niet betrouwbaar bij CallKit answer-op-lockscreen. Fix: in
`provider(_:perform:CXAnswerCallAction)` polling doen op
`UIApplication.shared.isProtectedDataAvailable` én
`applicationState == .active` vóór `action.fulfill()` (JFER's pattern,
Apple forum thread 712817). Werk: ~30 regels Swift, 30s-timeout.

**Route B — Guided Access + FCM data-only + LiveKit direct (Rustige modus)**

Voor de kwetsbaarste dierbaren (dementie, geen scherm-oppak-vaardigheid):
iPad in **Begeleide Toegang** (Guided Access,
`Instellingen → Toegankelijkheid → Begeleide toegang`, activeren met
3× home-knop / 3× top-knop). Dit locket iPad op Ons Moment als enige
zichtbare app; verzorger heeft een passcode om af te sluiten. Vergelijk
met onze Android "Rustige modus" (Screen Pinning + BootReceiver).

Werking: app staat 100% voorgrond. FCM data-only push komt binnen →
`_backgroundHandler` runt foreground-pad → `incomingCallNotifier` →
`AutoOpnemenWaarschuwingScherm` (2,5s) → `GesprekScherm` → LiveKit-join
met camera + microfoon. **Volledig automatisch, ook op vergrendeld
scherm**, want in Guided Access blijft de app zichtbaar en het scherm
staat effectief aan. **Geen CallKit gebruikt** in deze modus.

Belangrijk: **CallKit + Guided Access werkt NIET goed** (bevestigd
door Apple developer forum thread 70084 — Guided Access blokkeert de
CallKit-UI). Onze Route B omzeilt dit juist door in kiosk-modus
CallKit uit te schakelen en direct via FCM foreground te reageren. De
app moet detecteren dat het in Guided Access loopt (via
`UIAccessibility.isGuidedAccessEnabled`) en dan bij CallKit-registratie
achterwege laten of hasVideo=false forceren.

Bevestigd Apple-conform: een **voorgrond-app mag camera/microfoon
starten** zonder user-tap; dat is dagelijkse practice voor video-
conferencing apps. `NSCameraUsageDescription` +
`NSMicrophoneUsageDescription` in Info.plist regelen de eerste-run-
prompt; daarna heeft de app permanent toegang tot beide.

**Route B risico's om in device-test te bevestigen** (niet blokkerend
voor het plan):
- Er zijn losse rapporten dat sommige AVAudioSession-configuraties
  onder Guided Access minder stabiel zijn. Concreet WebRTC-bewijs
  vonden we niet; foreground-video-conferencing werkt normaal.
- BootReceiver-equivalent bestaat niet op iOS: als iPad reboot,
  moet verzorger handmatig Guided Access opnieuw activeren.

**Vergelijking met Route A**: Route B is de 100%-route voor kwetsbaar-
ste dierbaren op iPad. Route A werkt goed op iPhone én iPad voor
familie-leden die zelf hun toestel dagelijks ontgrendelen (of het
ontgrendeld laten op een vaste plek zoals aanrecht/nachtkastje).

**Het volledige iOS-bel-equivalent van onze Android-stack**:

| Android-mechanisme | iOS-equivalent | Werk |
|---|---|---|
| FCM data-only + `apns-push-type: background` | Identiek (huidige code werkt) — Route B | ✓ klaar |
| VoIP-push (Route A voor Auto-Answer via CallKit) | PushKit `apns-push-type: voip` + `apns-priority: 10` + `apns-topic: bundleid.voip` | node-apn in Cloud Function |
| `flutter_local_notifications` + `fullScreenIntent` | CallKit UI, automatisch bij VoIP-push | flutter_callkit_incoming al in deps |
| `USE_FULL_SCREEN_INTENT` toestemming | niet nodig — CallKit-recht komt met VoIP-entitlement | Xcode: Signing & Capabilities → Background Modes → VoIP |
| `SYSTEM_ALERT_WINDOW` + `startActivity` (BEL-D1) | niet nodig — CallKit start app zelf bij fulfill | — |
| `showWhenLocked` + wake-screen | CallKit doet dit zelf (systeem-niveau) | — |
| Screen Pinning + auto-herpin (rustige modus) | Guided Access (handmatig door verzorger geactiveerd) | UX-docs + isGuidedAccessEnabled-detectie |
| BootReceiver (auto-herstart) | **bestaat niet op iOS** — verzorger opent handmatig na reboot | doelgroep-tekst aanpassen |
| Auto-answer bij scherm-AAN + app dicht | **Route A**: iOS Auto-Answer-instelling doet dit. **Route B**: Guided Access houdt app permanent voorgrond | iOS-specifieke instructies in setup + FAQ |
| Marimba-ringtone via just_audio (STREAM_RING) | Route A: CallKit `ringtoneSound` via CXProviderConfiguration. Route B: bestaande just_audio-loop werkt gewoon | ~30 min in CXProvider config |
| Gemist-gesprek notif channel | CallKit registreert gemist gesprek automatisch in system call history | — |

**Netto**: bellen op iOS is met beide routes **kwalitatief goed** en
matcht Android in de belangrijkste scenario's:
- **Ontgrendeld iPad / iPhone**: Route A auto-answer werkt volledig
  (video + audio) — gelijkwaardig aan Android normale modus.
- **iPad in Guided Access**: Route B werkt volledig — gelijkwaardig
  aan Android rustige modus (kiosk).
- **Vergrendeld iPad ZONDER Guided Access + Route A**: alleen audio
  tot unlock — eerlijke beperking, gedeeld met WhatsApp/Skype/Viber
  (Apple-systeem-grens). Voor dementie-doelgroep advies: iPad
  ontgrendeld laten op vaste plek, óf Guided Access gebruiken.

**Werk-inschatting bellen iOS** (aangepast): ~5-7 werkdagen fysieke
build (LiveKit werkt out-of-the-box, `flutter_callkit_incoming` is
gebouwd voor CallKit, PushKit-token-plumbing + hasVideo=true bij
outbound calls + JFER's lockscreen-polling zijn de puzzels).

---

**3. PUSH/APNs — wat moet er geregeld worden**

- **Apple Developer Program** ($99/jaar) — Joshua zakelijk profiel JS
  Milhous. Aanvragen via developer.apple.com; DUNS-nummer nodig voor
  organization-account (KVK 94498695 heeft er waarschijnlijk al één).
  Wachttijd: 1-2 dagen tot een week.
- **APNs Authentication Key (.p8)** — moderne aanpak, aanbevolen boven
  Apple Push Certificates (die verlopen jaarlijks; .p8 niet). Genereren
  in Apple Developer → Keys → +. Uploaden in Firebase Console →
  onsmonent-project → Cloud Messaging → Apple app configuration →
  APNs Authentication Key. Daarna stuurt FCM automatisch de juiste
  APNs-berichten namens Ons Moment.
- **`apns`-blokken in Cloud Functions**: **al goed voorbereid.** Voor
  moment-push (`onNieuwMoment` regel 217-225) en gesprek-push
  (`start_call.ts` regel 264-272) staat `apns-push-type: 'background'` +
  `apns-priority: '5'` + `contentAvailable: true`. Dat is exact wat
  Apple vraagt voor data-only wake-op.
- **VoIP-push voor bellen** — hierin schiet de huidige setup nog
  tekort. FCM ondersteunt géén VoIP-push (`apns-push-type: 'voip'`);
  daarvoor moet:
  1. Een aparte plugin worden toegevoegd (kandidaten: `flutter_voip_pushkit`
     of native Swift AppDelegate) die de PushKit VoIP-token opvraagt en
     via MethodChannel doorgeeft aan Dart;
  2. Deze `voipToken` opgeslagen worden op `apparaten/{id}` als tweede
     token-veld naast `fcmToken`;
  3. Cloud Function `startVideoCall` een tweede code-pad krijgen: naar
     Android → huidige FCM-flow; naar iOS → directe APNs-call via
     `admin.messaging()`... maar VoIP-push kan **niet** via
     `admin.messaging()`. Moet via een direct HTTP/2-request naar
     `api.push.apple.com` met de .p8-key ondertekend als JWT. Grote
     puzzel — er is een `node-apn` library die dit doet.
- **PushKit-restricties Apple ≥ 2019**: VoIP-push MOET binnen ~5s een
  CallKit-UI tonen anders killt Apple de app en trekt uiteindelijk het
  VoIP-recht in. Onze flow moet: PushKit ontvangt → onmiddellijk
  CXProvider `reportNewIncomingCall(with:update:)` → daarna LiveKit
  joinen. Volgorde is strikt.
- **Sandbox vs. Production APNs**: TestFlight-builds gebruiken sandbox
  APNs, App Store-builds production. Aparte pijp; Firebase Console kiest
  automatisch op basis van build-type.

---

**4. PLUGINS — iOS-compatibiliteit**

Alle 22 direct-declared deps in `pubspec.yaml` ondersteunen iOS:

| Plugin | iOS-support | Opmerking |
|---|---|---|
| firebase_core/auth/firestore/storage/messaging/crashlytics | ✓ | Podfile-integratie via FlutterFire |
| flutter_local_notifications ^17.1.2 | ✓ | DarwinInitializationSettings + UNUserNotificationCenter |
| just_audio ^0.9.36 | ✓ | AVAudioPlayer onder de motorkap |
| audio_session ^0.1.21 | ✓ | Configureert AVAudioSession — belangrijk voor call-audio |
| record ^5.1.0 | ✓ | iOS 12+ |
| image_picker ^1.0.7 | ✓ | UIImagePickerController |
| file_picker ^8.0.0+1 | ✓ | UIDocumentPicker |
| path_provider ^2.1.2 | ✓ | |
| wakelock_plus ^1.2.1 | ✓ | `UIApplication.idleTimerDisabled` — géén programma-lock zoals Android kiosk |
| shared_preferences ^2.2.2 | ✓ | NSUserDefaults |
| intl ^0.18.1 | ✓ | pure Dart |
| http ^1.2.0 | ✓ | pure Dart |
| device_info_plus ^10.1.0 | ✓ | iOS device-model, systemVersion |
| video_player 2.9.2 | ✓ | AVPlayer |
| url_launcher ^6.2.5 | ✓ | |
| livekit_client ^2.2.4 | ✓ | WebRTC iOS-framework — grote Pod (~30MB), verwacht langere first-build |
| cloud_functions ^4.6.9 | ✓ | |
| permission_handler ^11.3.1 | ✓ | Info.plist-usage-strings vereist |
| flutter_callkit_incoming ^2.5.0 | ✓ | **CallKit is de hoofd-use-case op iOS** — al in deps sinds Optie B-traject, blijft dus gewoon staan voor iOS |

`dependency_overrides: record_android: 1.2.0` is Android-only en wordt
door iOS-build genegeerd (mag blijven staan).

**Enige plugin-kanttekeningen op iOS**:
- `wakelock_plus`: op iPad kiosk-scenario is dit slechts "scherm uit
  voorkomen", niet "app geforceerd voorgrond". Guided Access moet dat
  doen.
- `flutter_callkit_incoming` op iOS heeft z'n eigen PushKit-integratie —
  we hoeven mogelijk geen apart `flutter_voip_pushkit` toe te voegen.
  Bij VB-fase van iOS uitzoeken.

**Netto**: geen plugin blokkeert iOS. Wel Podfile + `pod install` op
macOS bij eerste build — verwacht 15-30 min compileren voor livekit +
firebase pods bij cold cache.

---

**5. OVERIG iOS**

- **Info.plist keys** (verplicht bij Apple review, anders crash op eerste
  gebruik):
  - `NSCameraUsageDescription` — "Ons Moment gebruikt uw camera voor
    videogesprekken met familie."
  - `NSMicrophoneUsageDescription` — "Ons Moment gebruikt uw microfoon
    voor spraakberichten en videogesprekken."
  - `NSPhotoLibraryUsageDescription` — "Ons Moment gebruikt uw foto's
    om herinneringen te delen met familie."
  - `NSPhotoLibraryAddUsageDescription` (optioneel, alleen als opslaan)
  - `NSUserNotificationsUsageDescription` — impliciet via
    UNUserNotificationCenter.requestAuthorization
  - `UIBackgroundModes`: `voip`, `audio`, `remote-notification`,
    `fetch`
- **App Store Connect listing**:
  - Screenshots iPhone 6.7" (min. 3) + iPhone 6.5" (fallback) + iPad
    Pro 12.9" (min. 3 als iPad supported)
  - App-icoon 1024×1024 (rond of vierkant — Apple kiest)
  - Store-omschrijving NL + EN (Engels ook verplicht voor EU-listings)
  - Privacy Policy URL (staat al op onsmoment.app)
  - Privacy nutrition label — invullen welke data verzameld wordt
    (Firebase Auth email; Firestore user content; geen advertentie-ID)
- **App Store Review**:
  - Duur: **1-2 weken initieel**, meestal 3-5 dagen bij follow-ups
  - Strenger dan Google: reviewer test met echte account. Toegang tot
    demo-account nodig (bijv. oma@test.nl reactiveren voor review).
  - Auto-answer + kiosk-features vragen om uitleg in review-notities:
    dementiezorg-context, gebruikersgroep. Apple accepteert "Assistive
    Technology" claims als het gerechtvaardigd is.
  - Rejection-risico: als de reviewer denkt dat auto-answer een privacy-
    schending is → wees eerlijk in de app-description dat auto-answer
    alleen na expliciete opt-in door de familie-eigenaar werkt.
- **In-App Purchases via Apple = verplicht** voor digitale abonnementen.
  RevenueCat SDK ondersteunt zowel Google Play Billing als Apple StoreKit
  via één API — **dit is precies waarom we RevenueCat kozen.** ✓
  In App Store Connect moeten 4 abonnementen aangemaakt worden,
  spiegelend aan Google Play (familie_klein €4,99/€35,99 +
  familie_groot €7,99/€57,99). RevenueCat koppelt de product-IDs
  automatisch.
- **Apple's commissie**: 15% (Small Business Program tot $1M/jaar) of
  30%. Aanmelden voor Small Business Program bij App Store Connect
  zodra developer-account actief.
- **Sandbox testers**: aparte Apple Sandbox-accounts (via App Store
  Connect → Users → Sandbox Testers) voor test-abonnementen.
  RevenueCat detecteert sandbox automatisch.
- **iOS Safari audio-checklist** (huidige webbuild op onsmoment.app):
  autoplay-restricties zijn strenger dan Chrome. Al deels afgevangen
  in bestaande code (audio_session + AudioAttributes). Web-build
  bevriezen op huidige status; PWA-installatie niet nodig als native
  iOS-app er komt.

---

**6. CROSS-PLATFORM MATRIX (beller × ontvanger × modus)**

LiveKit is platform-blind — de bellerkant is irrelevant voor het
opneem-gedrag. Wat telt is de ontvanger-configuratie:

| Ontvanger-toestel | Modus | Beller: Android | Beller: iPhone | Auto-opnemen? |
|---|---|---|---|---|
| Android-tablet | Rustige (kiosk) | ✓ | ✓ | Volautomatisch, altijd |
| Android-tablet | Meldingen (normaal) | ✓ | ✓ | Volautomatisch met toestemmingen (FSI + battery-opt) |
| Android-telefoon | Meldingen | ✓ | ✓ | Idem |
| iPad | Guided Access (Route B) | ✓ | ✓ | Volautomatisch, altijd — 100%-route voor kwetsbare dierbare |
| iPad | Normaal + "Oproepen automatisch beantwoorden" AAN (Route A) | ✓ | ✓ | Ontgrendeld: volledig video ✓. Vergrendeld: **alleen audio tot Face ID / passcode** |
| iPad | Normaal + Auto-Answer UIT | ✓ | ✓ | 1-tik opnemen op CallKit-UI (systeem-niveau, ook lock-screen) |
| iPhone | Normaal + Auto-Answer AAN | ✓ | ✓ | Zelfde gedrag als iPad-Route-A |
| iPhone | Normaal + Auto-Answer UIT | ✓ | ✓ | 1-tik opnemen op CallKit-UI |

**Kern-takeaway**: iPhone-familie ↔ Android-tablet-dierbare (huidige
usecase) werkt **exact zoals nu op Android** zodra de iPhone-app er is
— de tablet-kant is Android en die is al af. Andersom (Android-familie
belt iPad-dierbare) werkt volledig via Route B (Guided Access) of
Route A met de accessibility-instelling aan.

---

**7. GEBRUIKERSINSTRUCTIES (voor FAQ / website / in-app setup)**

Platform-afhankelijk tonen — niet het andere platform noemen. Kort,
warm, geen jargon.

**Voor Android-tablet als ontvanger**:
> "Automatisch opnemen werkt op deze tablet zonder extra instellingen.
> Zet Ons Moment tijdens de eerste keer even helemaal open, geef
> toestemming voor camera, microfoon en meldingen, en klaar. Kiest u
> voor Rustige modus, dan blijft Ons Moment altijd zichtbaar en neemt
> automatisch op wanneer familie belt. Kiest u voor Normale modus,
> dan werkt automatisch opnemen ook — zorg alleen dat u bij de eerste
> bel de twee instellingen op het scherm bevestigt."

**Voor iPad als ontvanger — Rustige modus (aanbevolen voor kwetsbare
dierbare)**:
> "Uw iPad staat straks vast op Ons Moment, zodat uw dierbare niks
> per ongeluk kan afsluiten. Zo zet u dat aan:
>
>  1. Open Instellingen → Toegankelijkheid → Begeleide toegang. Zet
>     'Begeleide toegang' aan en kies een viercijferige code (schrijf
>     die op voor uzelf).
>  2. Open Ons Moment.
>  3. Druk drie keer snel op de bovenknop (of thuisknop op oudere
>     iPads). Kies 'Begeleide toegang starten'.
>
> Klaar. Vanaf nu blijft Ons Moment altijd op het scherm, en wanneer
> familie belt neemt de iPad automatisch op. Wilt u de iPad tijdelijk
> voor iets anders gebruiken? Druk weer drie keer op de bovenknop en
> vul uw code in."

**Voor iPad/iPhone als ontvanger — Normale modus**:
> "Om videogesprekken automatisch op te nemen, hoeft u in Ons Moment
> zelf niets in te stellen. Zet in uw iPad-instellingen één schakelaar
> aan:
>
>  1. Open Instellingen → Toegankelijkheid → Aanraken → Audioroutering
>     oproep.
>  2. Tik op 'Oproepen automatisch beantwoorden'.
>  3. Zet de schakelaar aan en kies een tijd (3 tot 5 seconden werkt
>     fijn — genoeg om u naar de camera te draaien).
>
> Klaar. Vanaf nu neemt uw iPad videogesprekken vanzelf op, ook van
> Ons Moment. Ligt de iPad met scherm-uit? Dan hoort u eerst de andere
> persoon; het beeld start zodra u de iPad opneemt en met uw gezicht
> ontgrendelt. Wilt u dat beeld ook zonder de iPad op te nemen
> automatisch start? Gebruik dan Begeleide toegang (in de app onder
> 'Rustige modus')."

Deze teksten later verwerken in `SetupWizard` (iOS-branche via
`defaultTargetPlatform`) en in de FAQ op onsmoment.app.

**⚠️ EXPLICIETE TAAK BIJ iOS-BOUW — NIET VERGETEN**

> **BEL-UITLEG PER PLATFORM IN DE APP**: de drie gebruikersteksten uit
> FASE G punt 7 (Android-tablet / iPad-Rustige modus via Begeleide
> toegang / iPad-Gewone modus via 'Oproepen automatisch beantwoorden')
> moeten dan in de app zelf komen:
>
> 1. In de **Ontvanger-setup** (toestemmingen-stap)
> 2. In de **FAQ 'Videobellen'**
> 3. In het **'Zo werkt bellen'-uitlegscherm**
>
> Platform-afhankelijk tonen (een iPad ziet alleen de iPad-uitleg,
> Android alleen de Android-uitleg; het andere platform niet noemen).
> De eerlijke grens (vergrendelde iPad in Gewone modus → eerst geluid,
> video na ontgrendelen) kort en warm vermelden.
>
> **Kernadvies overal**: Rustige modus is het betrouwbaarst voor wie
> zelf niet kan opnemen, op beide platforms.

---

**8. INSCHATTING — hoeveel werk, wat zijn de risico's, wat nu voorbereiden**

**Werk-inschatting (kalender)**:
- Code-werk (met macOS build-toegang): **2-3 weken fulltime**
  - Fundering iOS-klaar (flutter create --platforms=ios, iOS-blok in
    firebase_options.dart, GoogleService-Info.plist, Info.plist,
    Podfile-tuning): 1 dag
  - APNs .p8-key + Firebase Console koppeling: 0.5 dag
  - Codemagic macOS-runner + provisioning profiles: 1-2 dagen (nieuw
    terrein voor Joshua)
  - Videobellen basis iOS Route A (LiveKit + CallKit + PushKit +
    hasVideo=true bij outbound + JFER's lockscreen-polling in
    CXAnswerCallAction-handler): 3-4 dagen
  - VoIP-push server-kant (voipToken opslag + Cloud Function iOS-VoIP-
    pad met node-apn + JWT-signing met .p8): 2-3 dagen
  - Route B implementatie (isGuidedAccessEnabled-detectie + FCM
    foreground-pad + skip CallKit in kiosk-modus): 1 dag
  - Auto-answer UX-verwerking (`AutoOpnemenWaarschuwingScherm` blijft
    identiek voor Route B; nieuwe iOS-branche in `BelApparaatKies` die
    lockscreen-video-nuance uitlegt): 0.5 dag
  - Gebruikersinstructies verwerken in SetupWizard iOS-branche: 0.5 dag
  - IAP via RevenueCat op iOS (identieke SDK, alleen product-IDs
    koppelen): 1 dag
  - Info.plist + usage-descriptions + entitlements
    (Background Modes: voip + audio + remote-notification + fetch): 0.5 dag
  - App Store Connect listing + screenshots (iPhone + iPad): 2 dagen
  - TestFlight closed beta setup: 0.5 dag
  - Buffer + review-iteraties: 2-3 dagen
- **Store-tijd (wachten)**: 14 dagen TestFlight closed beta minimum +
  1-2 weken App Store review = **~1 maand kalender**
- **Totaal iOS-launch: ~1.5-2 kalendermaanden vanaf start iOS-fase**,
  ná Android live

**Grootste risico's** (aangepast na 11 sept-onderzoek):
1. **Video op vergrendeld iPad (Route A)** — bij CallKit-auto-answer
   op vergrendeld scherm probeert iOS eerst Face ID / passcode. Slaagt
   dit niet, dan wordt het gesprek beantwoord maar blijft in de
   lock-screen CallKit-UI: **alleen audio tot handmatig ontgrendelen**.
   Zelfde beperking als WhatsApp/Skype/Viber (Apple-systeem-grens, niet
   omzeilbaar). Impact: voor kwetsbaarste dierbaren moeten we **Route
   B (Guided Access) actief aanbevelen**. Route B werkt 100% ook bij
   scherm-uit-lijkend-vergrendeld want de iPad blijft in feite aan.
2. **iOS 16.2+ CallKit lockscreen bug** — na successful unlock opent
   de app soms niet betrouwbaar. Fix: JFER's polling-pattern in
   CXAnswerCallAction (poll `isProtectedDataAvailable` +
   `applicationState == .active` vóór `action.fulfill()`). Overzichte-
   lijke code, maar ~30 regels Swift op meerdere iOS-versies testen.
3. **CallKit + Guided Access conflict** — bevestigd: werken niet
   samen. Onze Route B omzeilt dit door in Guided Access CallKit niet
   te gebruiken. Vergt runtime-detectie via
   `UIAccessibility.isGuidedAccessEnabled` + notification observer op
   `UIAccessibility.guidedAccessStatusDidChangeNotification` om switch-
   momenten op te vangen.
4. **App Store Review-strengheid** — kans op rejection bij CallKit +
   auto-answer-uitleg. Vereist zorgvuldige review-notities in de
   dementie-doelgroep-context. Precedent: apps zoals GrandPad worden
   goedgekeurd → wij ook goedkeurbaar. Betekent WEL: geen "auto-answer
   zonder gebruikersintentie" claimen; framen als "wij ondersteunen
   iOS' ingebouwde Auto-Answer-instelling + Guided Access".
5. **PushKit VoIP-token beheer** — subtiel: bij re-installatie
   verandert token; iOS heeft `pushRegistry(_:didInvalidatePushTokenFor:)`
   voor invalidatie. Server moet dead-token cleanup krijgen (analoog
   aan huidige FCM-cleanup in `onNieuwMoment` regel 260-274).
6. **Cloud Function VoIP-pad complexiteit** — directe APNs-call via
   node-apn + JWT-signing met .p8 (FCM ondersteunt geen VoIP-push).
   Nieuw terrein. Kans op debug-uren.
7. **Codemagic macOS-kosten** — iOS-builds zijn ~2-3× duurder in
   build-minuten dan Android. Codemagic gratis tier heeft 500 min/maand
   macOS; bij release-builds komt dit snel op.
8. **Boot-restart bestaat niet op iOS** — als iPad reboot na
   stroomuitval, moet verzorger handmatig Ons Moment terug openen én
   Guided Access opnieuw activeren. Reële UX-degradatie t.o.v.
   Android's BootReceiver + herpin. In gebruikersinstructies benoemen
   ("na een stroomuitval opent u even Ons Moment en drie-keer-drukken").
9. **DUNS-nummer** — bij aanvraag Apple Developer Program als
   organization is DUNS verplicht. Voor JS Milhous (KVK 94498695)
   waarschijnlijk al toegekend door D&B; check via lookup.dnb.com.
   Individual-account kan ook (KVK niet verplicht) maar dan staat
   "Joshua Milhous" i.p.v. "JS Milhous" in de store — minder pro.
10. **Guided Access + WebRTC audio device-test-punt** — geen concrete
    rapporten van problemen, maar losse ervaringen suggereren dat
    AVAudioSession-configuraties in Guided Access soms minder stabiel
    zijn. Moet in fysieke device-test bevestigd worden vóór we Route B
    als 100%-oplossing adverteren.

**Wat NU al veilig voor te bereiden (zonder Mac/iPhone)**:
- [ ] **Firebase Console → iOS-app registreren** onder project onsmonent.
      Bundle-ID `nl.onsmoment.app` (matcht domein). Downloadt
      `GoogleService-Info.plist` en levert de iOS-firebase-waarden
      (apiKey, appId, iosBundleId, iosClientId). Later toe te voegen
      als `iOS`-blok in `lib/firebase_options.dart`.
- [ ] **DUNS-nummer voor JS Milhous checken** via lookup.dnb.com. Zo
      nee: gratis aanvragen bij D&B (2-4 weken doorloop).
- [ ] **Apple Developer Program aanvragen** ($99/jaar) — kan online,
      geen Mac nodig. Betalingsprofiel identiek aan Google Play
      (Revolut IBAN 2199).
- [ ] **APNs .p8-key genereren** zodra Apple Developer actief. Upload
      naar Firebase Console → Cloud Messaging → APNs Auth Key. Kan
      zonder Mac.
- [ ] **App Store Connect: 4 iOS-abonnementen aanmaken** zodra Apple
      Developer actief (familie_klein_maand/jaar + familie_groot_maand/
      jaar, prijzen identiek aan Google Play). Koppelen aan bestaand
      RevenueCat-project "Ons Moment" zodra Google Play iOS-koppeling
      ook actief is.
- [ ] **Info.plist usage-descriptions in NL alvast draften** in een
      apart tekstdocument (Camera/Microfoon/Foto's).
- [ ] **onsmoment.app-tekst voorbereiden**: iOS-sectie in FAQ met
      twee routes (Route B Guided Access voor kwetsbare dierbare op
      iPad = 100% automatisch; Route A "Oproepen automatisch
      beantwoorden" in iOS-toegankelijkheid voor familie op iPhone/
      iPad). Eerlijk over lockscreen-video-nuance in Route A.
      Gebruikersinstructies zoals opgesteld in FASE G punt 7 direct
      als basis-copy gebruiken.
- [ ] **DEBUG_VIDEOBELLEN-audit vóór iOS-start**: bevestig dat alle
      productie-flows achter deze flag met flag=false NIET breken op
      Android. Zo ja: iOS mag straks parallel starten met flag=false.

**Wat vereist Mac/iPhone (LATER, niet nu voor te bereiden)**:
- `flutter create --platforms=ios .` in repo-root (genereert `ios/`
  map met Xcode-project)
- Podfile-tuning + `pod install` op macOS
- Xcode-signing + provisioning profiles + certificates
- Codemagic macOS-runner configureren
- Fysieke iPhone/iPad-tests voor VoIP-push (simulator ondersteunt geen
  echte APNs voor VoIP)
- TestFlight-uploads + closed beta
- Guided Access-workflow live testen op iPad

**Beslispunt vóór start iOS-fase (D-day + 1 maand)**: wil Joshua een
Mac Mini kopen (~€700 nieuw / ~€400 refurbished) of Codemagic macOS-
runner huren? Voor closed test volstaat Codemagic; voor iteratieve
debugging is een eigen Mac gemakkelijker. Aanbeveling: **Codemagic-only
starten**, Mac Mini pas als iOS ≥ 100 gebruikers heeft.

## Opruimen ná launch (inventarisatie, nog niet doen)

> Snapshot 10 sept 2026. **PUUR TER INFO** — niets van deze lijst nu aanraken.
> Bevestigd: geen enkele wijziging aan werkende code gemaakt bij het opstellen.
> Gebruiken pas ná closed test + productielaunch, in kleine PR's met device-test.

**Categorie A — dode code / ongebruikte imports (ooit veilig weg)**

| # | Wat + waar | Achter flag? | Elders gebruikt? | Toelichting |
|---|---|---|---|---|
| A1 | Unused import `'../../data/labels.dart'` — `lib/screens/familie/familie_scherm.dart:31` | nee | analyzer: geen | 1-regel weg |
| A2 | Ongebruikt veld `_isAccountMaker` — `familie_scherm.dart:3728` (wordt gezet op :3769 maar nergens gelezen) | nee | analyzer: geen | veld + setState-regel weg; `_benIkEigenaar` dekt eigenaar-checks |
| A3 | Ongebruikte optionele params `initial`/`bestaand` op `_NieuwMomentDialog` — `familie_scherm.dart:4665` | nee | analyzer: nooit meegegeven | dialog wordt alleen zonder args opgeroepen; params + init-lezers versimpelen |
| A4 | Ongebruikte optionele params `initial`/`bestaand` op `_EenmaligMomentDialog` — `familie_scherm.dart:4804` | nee | analyzer: nooit meegegeven | idem A3 |
| A5 | `test/widget_test.dart` — Flutter counter-boilerplate; verwijst naar niet-bestaande `MyApp` + unused import van `main.dart` | nee | build: geen | complete file kan weg óf vervangen door echte test |

**Categorie B — test-hulpmiddel achter flag (laten staan, veilig zolang flag uit)**

| # | Wat + waar | Achter flag? | Elders gebruikt? | Toelichting |
|---|---|---|---|---|
| B1 | `DEBUG_AUDIO` toast-diagnose — `debug_flags.dart:3` (=false). Gate op `familie_scherm.dart:271` + `tablet_scherm.dart:302` | ✓ (=false) | 2 aanroepen | veilig te houden; ooit weg als iOS-audio bewezen stabiel |
| B2 | `DEBUG_FORCE_LOGOUT` — `debug_flags.dart:7` (=false). Gate op `main.dart:648` | ✓ (=false) | 1 aanroep | veilig te houden; ooit weg als force-logout-flow stabiel |
| B3 | `DEBUG_TESTMODUS` + heel test-modus-blok — `debug_flags.dart:12` (=false). UI-panel `familie_scherm.dart:1626-1654` (Switch), veld `_testModus` :1133 | ✓ UI gate (=false) | veld wél gelezen door `!_testModus`-branches (1696, 2403, 2414) + `'testModus'`-veld in payload (2216, 2409, 2742) + `functions/src/index.ts:56` (skip-check) | UI-blok is dood zolang flag uit; veld/payload MAG NIET WEG — server + planning-logica leest het. Later kan het UI-blok versimpeld naar één regel of het hele mechanisme geschrapt worden |
| B4 | `DEBUG_BEL_DEV` — `debug_flags.dart:54` (=false). Ontgrendelt Bel-diagnose menu-item (familie_scherm.dart:4051) + callkit dev long-press-toggle (:4069) | ✓ (=false) | 2 gates | veilig te houden achter flag; hangt aan C1/C2/C3 opruiming |
| B5 | `DEBUG_KIOSK` — `debug_flags.dart:29` (=true) → **moet naar false vóór bredere release** (staat al in FASE D-checklist). Gate op `tablet_scherm.dart:71, 269` | ✓ (=true) | 2 gates | flag flippen; code zelf blijft (feature) |
| B6 | `DEBUG_VIDEOBELLEN` — `debug_flags.dart:20` (=true) → **moet naar false vóór bredere release** (of vervangen door Firestore-config in V6, staat in FASE D). Gates in main.dart, familie_scherm.dart, tablet_scherm.dart, video_call_service.dart | ✓ (=true) | 5+ gates | flag flippen; code blijft (feature) |
| B7 | `CALLKIT_HARD_UIT` — `debug_flags.dart:43` (=true, permanent). "Kill-switch Optie B", bewust bewaard voor archief | ✓ (=true) | leest logica in push_service, callkit_flag_service | LATEN — bewuste keuze in CLAUDE.md architectuur-sectie |

**Categorie C — bewaren tot na closed test (dan pas beoordelen)**

| # | Wat + waar | Achter flag? | Elders gebruikt? | Toelichting |
|---|---|---|---|---|
| C1 | `BelLogService` — `lib/services/bel_log_service.dart` (80 regels, SharedPreferences rollende log) | nee (log is altijd aan) | ~50 aanroepen: main.dart (7), push_service.dart (22), video_call_service.dart (5), bel_scherm.dart (4), gesprek_scherm.dart (4), bel_diagnose_scherm.dart (2) | wachten op groene device-testen; daarna alle `BelLogService.log(...)`-aanroepen + service weghalen, of achter `DEBUG_BEL_DEV` gaten |
| C2 | `BelDiagnoseScherm` — `lib/screens/videobellen/bel_diagnose_scherm.dart` (403 regels) | ✓ (`DEBUG_VIDEOBELLEN && DEBUG_BEL_DEV`) | 1 nav-push (familie_scherm.dart:4054) | complete bestand + import + menu-item weg zodra bel-flow productie-groen |
| C3 | `_toonCallkitDevToggle` dialog + long-press op logo — `familie_scherm.dart:4069-4143` | ✓ (`DEBUG_BEL_DEV`) | intern (long-press) | dialog + GestureDetector weg; logo blijft |
| C4 | `FullScreenIntentService.forceerPromptVoorTest` (regel 34) + `resetGuardVoorTest` (regel 84) | nee (methods niet gegated, maar alleen aangeroepen vanuit BelDiagnoseScherm) | 1 call (bel_diagnose_scherm.dart:121) | verwijderen samen met C2; `controleerEnPromptAlsNodig` blijft |
| C5 | `CallkitFlagService` — `lib/services/callkit_flag_service.dart` (140+ regels, Firestore-flag + SharedPreferences override) | ↔ `CALLKIT_HARD_UIT=true` neutraliseert effect | main.dart (warmup), push_service.dart (2× read), familie_scherm.dart (dev-toggle-dialog) | code + import weg zodra callkit-archief officieel geschrapt (samen met C6/C7) |
| C6 | `BelCallkitService` — `lib/services/bel_callkit_service.dart` (~350 regels, callkit-plumbing) | ↔ `CALLKIT_HARD_UIT=true` | main.dart (warmup+events+replay), push_service.dart (show+beeindig), video_call_service.dart (beeindigAlles) | leven aan Optie B; bewust bewaard voor archief (CLAUDE.md-sectie "NIET meer proberen"). Pas weghalen als iOS-traject callkit definitief niet inruilt |
| C7 | Dep `flutter_callkit_incoming` in pubspec.yaml | ↔ CALLKIT_HARD_UIT | wordt geïmporteerd door C6 + FullScreenIntentService (voor `canUseFullScreenIntent` — WEL nodig) | pas weg als FSI-check via andere plugin/kanaal komt |
| C8 | `Battery-optimalisatie`-tegel in `BelDiagnoseScherm:207-237` (dubbelt met `toestemmingen_setup_scherm.dart:161-170` = productie-versie) | ✓ via C2 | productie-versie in setup blijft | verdwijnt automatisch met C2 |
| C9 | 78 losse `debugPrint(...)`-calls in `lib/**/*.dart`: bel_callkit_service (26), push_service (18), uitnodiging_service (7), full_screen_intent_service (5), kring_service (4), bel_log_service (4), device_modus_service (3), callkit_flag_service (3), verificatie_gate_service (2), bel_diagnose_scherm (2), familie_scherm (2), widgets/video_speler (1), video_call_service (1) | nee | log alleen zichtbaar via ADB/logcat | in release-build zijn `debugPrint`-calls al goedkoop (kDebugMode-gate intern). Optioneel later filteren; NIET nu, geeft géén productie-issue |

**Overzicht per categorie**: A = 5 items · B = 7 items · C = 9 items.

**Bekende non-items** (bewust GEEN opruim-punt):
- Geen `TODO`/`FIXME`/`XXX`-markers in `lib/` (grep leeg — nette repo).
- Geen losse `print(...)` calls buiten `debugPrint`.
- `_testModus`-veld + `testModus`-payload-veld: functioneel gebruikt door
  server + planning-logica (functions/src/index.ts:56). NIET weghalen bij
  DEBUG_TESTMODUS-cleanup — alleen de UI-switch.

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
