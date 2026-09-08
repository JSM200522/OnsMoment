import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// BEL-C6 (DEEL A): dunne wrapper rond de Android
/// SYSTEM_ALERT_WINDOW-permission ("Weergeven over andere apps").
///
/// Waarom we deze nodig hebben — auto-answer bij scherm AAN + app dicht:
/// Android 10+ verbiedt background-activity-start voor apps zonder
/// BAL-exemption. FullScreenIntent alleen dekt scherm-uit / vergrendeld;
/// bij scherm aan degradeert Android naar heads-up en negeert de
/// activity-start. SYSTEM_ALERT_WINDOW is een van de weinige geldige
/// BAL-exempties — met deze permission mag de fullScreenIntent-notif
/// óók bij scherm-aan de InkomendGesprekScherm-Activity starten
/// (dezelfde manier waarop WhatsApp inkomende bellen weergeeft).
///
/// We tekenen NOOIT een daadwerkelijke overlay-view. De permission
/// wordt puur gebruikt als BAL-exemption. Play Store-rechtvaardiging:
/// "video calling app; auto-answer for accessibility-configured devices".
///
/// Fail-soft: elke channel-fout retourneert `false` (permission niet
/// aanwezig) — dan valt de app terug op de standaard heads-up-notif
/// waar de gebruiker zelf moet tikken. Geen crash, geen regressie.
class OverlayPermissionService {
  OverlayPermissionService._();

  static const _channel = MethodChannel('nl.onsmoment.kiosk');

  /// True als de app SYSTEM_ALERT_WINDOW-permission heeft. Op Android < 6
  /// (API 22) bestaat de check niet — dan altijd true (permission is
  /// "gratis" op oude versies). Web: altijd false.
  static Future<bool> heeftToestemming() async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod<bool>('canDrawOverlays') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opent de Android special-access-settings-pagina voor "Weergeven
  /// over andere apps". Er bestaat geen directe prompt-dialog voor deze
  /// permission — de gebruiker moet in de systeeminstelling zelf de
  /// toggle omzetten. De aanroeper toont daarom eerst warme uitleg.
  ///
  /// No-op op web en op API < 23. Faalt silent als de intent geblokkeerd
  /// is (zeldzame OEM-restrictie); de UI-melding is de bron van
  /// waarheid voor de gebruiker.
  static Future<void> vraagToestemming() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('vraagOverlayToestemming');
    } catch (_) {}
  }
}
