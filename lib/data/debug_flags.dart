/// Tijdelijke diagnose-vlag. Zet op false zodra audio-bug op iOS Safari
/// is gediagnosticeerd — dan verdwijnen alle debug-toasts weer.
const bool DEBUG_AUDIO = false;

/// Tijdelijke diagnose-vlag voor de force-logout flow. Zet op false zodra
/// bevestigd is dat verwijderde apparaten correct uitloggen.
const bool DEBUG_FORCE_LOGOUT = false;

/// Toont de test-modus schakelaar in het stuur-scherm. Default uit voor
/// productie; zet op true om snel te testen (momenten verschijnen direct
/// bij de ontvanger i.p.v. op de geplande tijd).
const bool DEBUG_TESTMODUS = false;

/// **PRODUCTIE-FLAG** — master-flag voor de videobel-functie.
/// Blijft TRUE in productie: gate op de belknop in StuurTab, de FSI-
/// toestemmingsdialog op de tablet, en de inkomend-gesprek-listeners
/// in main.dart. Zonder deze flag doet VideoCallService niets en
/// verdwijnen alle bel-features — voor de dementie-doelgroep is dat
/// een launch-blocker.
///
/// Historie: voorheen DEBUG_VIDEOBELLEN met de instructie 'zet op
/// false vóór productie' — die valkuil (bel-functie zou dan
/// verdwijnen) is gefixt door hernoemen naar VIDEOBELLEN_INGESCHAKELD.
/// Bij V6+ Firestore-config-flag kan dit per kring uitrollen.
const bool VIDEOBELLEN_INGESCHAKELD = true;

/// **DEPRECATED** — deze flag was voorheen master-gate + dev-gate
/// gecombineerd. Nu vervangen door [VIDEOBELLEN_INGESCHAKELD]
/// (permanent true in productie) voor de master-gate. Deze flag is
/// nog beschikbaar voor eventuele extra dev-logs — verandert nergens
/// meer het productie-gedrag.
const bool DEBUG_VIDEOBELLEN = false;

/// **PRODUCTIE-FLAG** — kiosk-hardening voor de rustige modus.
/// Vergrendelt via Android Screen Pinning (startLockTask zonder
/// device-owner). Alleen actief als weergaveModus 'vergrendeld' is.
/// De eigenaar heft de lock op door de modus te wisselen naar
/// 'meldingen' via de bestaande instelling — dat pad is gegarandeerd
/// en wordt nooit door deze flag geblokkeerd.
///
/// **BLIJFT TRUE IN PRODUCTIE** — zonder deze flag doet KioskService
/// niets en gedraagt de rustige modus zich als een gewone tablet
/// (geen screen-pinning, geen herpin, geen kiosk-exit-detection).
/// Voor dementie-doelgroep is dat een launch-blocker.
///
/// Historie: voorheen was dit DEBUG_KIOSK met de instructie 'zet op
/// false vóór productie' — die valkuil is gefixt door hernoemen naar
/// KIOSK_INGESCHAKELD.
const bool KIOSK_INGESCHAKELD = true;

/// **DEPRECATED** — deze flag was voorheen de kill-switch voor de
/// kiosk-feature. De valkuil was: de FASE D-checklist zei 'zet op
/// false vóór productie', en dan werkte de rustige modus opeens niet
/// meer omdat KioskService.start() nergens werd aangeroepen.
///
/// Nu vervangen door [KIOSK_INGESCHAKELD] (permanent true in
/// productie). Deze DEBUG_KIOSK-constante is alleen nog beschikbaar
/// voor eventuele extra debug-logs — verandert nergens meer het
/// productie-gedrag.
const bool DEBUG_KIOSK = false;

/// BEL-B: harde compile-time kill-switch voor Optie B (ConnectionService/
/// TelecomManager via flutter_callkit_incoming). Bij TRUE draait de app
/// 100% op Optie A (BEL-A1..A4), ongeacht Firestore/SharedPreferences.
///
/// STAAT NU HARD OP TRUE. De belfunctie draait volledig op Optie A: heads-
/// up-notif bij scherm-uit/lock, InkomendGesprekScherm bij app-open,
/// AutoOpnemenWaarschuwingScherm → GesprekScherm bij autoAnswer. Callkit
/// (Optie B) heeft in testen op Samsung + Pixel nooit een merkbaar voor-
/// deel gegeven en veroorzaakte extra failure modes (dubbele ringtone,
/// PhoneAccount-registratie-issues, action-button-onbetrouwbaarheid).
/// De code blijft in de repo om V6+-onderzoek te bewaren, maar wordt in
/// productie NOOIT aangeraakt.
const bool CALLKIT_HARD_UIT = true;

/// BEL-DEV: dev-only bel-UI verbergen in productie-builds. Zet op TRUE
/// om diagnose-scherm, callkit-toggle, "prompt forceren", persistente
/// bel-log en test-modus te tonen. Standaard FALSE zodat een release
/// build de gebruiker nooit met deze knoppen belast.
///
/// Onafhankelijk van [DEBUG_VIDEOBELLEN] — die master-flag ontgrendelt
/// de belfunctie zelf (voor gesloten testtoestellen). DEBUG_BEL_DEV
/// ontgrendelt daarbovenop het testrommel-oppervlak. Beide moeten uit
/// vóór publieke release.
const bool DEBUG_BEL_DEV = false;
