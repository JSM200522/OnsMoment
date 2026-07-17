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
const bool DEBUG_VIDEOBELLEN = false;
