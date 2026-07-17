import 'dart:async';
import 'package:flutter/foundation.dart';

/// VideoCallService — LiveKit-integratie voor de videobel-functie.
///
/// Ontwerpprincipes — spiegelen die van [PushService] en [CrashService]:
/// - **Web-veilig**: publieke functies doen `if (kIsWeb) return;` eerst.
///   LiveKit werkt technisch ook op web, maar in scope (V6) is video-
///   bellen Android-only. Web krijgt kIsWeb-guards + no-op tot we het
///   expliciet openzetten.
/// - **Fail-soft**: init in try/catch. LiveKit-fouten mogen de bestaande
///   momenten/meldingen-flow niet stukmaken.
/// - **Achter [DEBUG_VIDEOBELLEN]**: publieke functies zijn no-op zolang
///   de master-flag uit staat. Vanaf V6 vervangen we die door een
///   Firestore-config-flag.
///
/// V0 levert alleen het skelet + init-hook. Vanaf V1 komt de LiveKit-
/// connect-logica erin (join/leave, remote-participant listeners,
/// stream-notifiers).
class VideoCallService {
  static bool _initGedaan = false;

  /// Roep aan in main() na Firebase.initializeApp(). Web + flag-uit
  /// → no-op. Alle initialisatie zit in try/catch zodat een LiveKit-
  /// fout de rest van de app niet stukmaakt.
  static Future<void> initApp() async {
    if (kIsWeb) return;
    if (_initGedaan) return;
    try {
      // V1 vult hier de LiveKit engine-init in (event-listeners e.d.).
      // Vooralsnog niets te doen — het skelet is er om de aanroeper in
      // main() gestabiliseerd te houden zodat V1 alleen het lichaam
      // hoeft in te vullen zonder main() aan te raken.
      _initGedaan = true;
    } catch (_) {
      // Rest van de app blijft werken zonder videobel-feature.
    }
  }
}
