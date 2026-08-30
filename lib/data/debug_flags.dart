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

/// Master-flag voor de videobel-functie (Fase VB-V0..V6). Zolang deze
/// uit staat is de belknop nergens zichtbaar, doet VideoCallService
/// niets, en verandert er niets aan de bestaande momenten/meldingen-
/// flow. Zet op true in een debug-build om test-scherm en belflow te
/// ontgrendelen. Bij V6 verhuist deze naar Firestore-config zodat we
/// per kring kunnen uitrollen zonder release.
const bool DEBUG_VIDEOBELLEN = true;

/// Kiosk-hardening: vergrendelt de rustige modus via Android Screen
/// Pinning (startLockTask zonder device-owner). Alleen actief als de
/// weergaveModus 'vergrendeld' is. De eigenaar heft de lock op door de
/// modus te wisselen naar 'meldingen' via de bestaande instelling —
/// dat pad is gegarandeerd en wordt nooit door deze flag geblokkeerd.
/// Zet op false als de testresultaten negatief zijn; bij false gedraagt
/// de app zich exact als vóór deze feature.
const bool DEBUG_KIOSK = true;

/// BEL-B: harde compile-time kill-switch voor Optie B (ConnectionService/
/// TelecomManager via flutter_callkit_incoming). Zet op TRUE als de
/// callkit-code op een toestel catastrofaal faalt en de remote flag +
/// dev-override niet snel genoeg bereikbaar zijn. Bij TRUE draait de
/// app 100% op Optie A (BEL-A1..A4), ongeacht Firestore/SharedPreferences.
/// Standaard FALSE — remote/lokale flag bepaalt dan of B daadwerkelijk
/// aan gaat. Zie CallkitFlagService voor de 3-laags beslislogica.
const bool CALLKIT_HARD_UIT = false;
