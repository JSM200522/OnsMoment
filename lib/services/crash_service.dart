import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Crashlytics-basis (Fase 3d-C4).
///
/// Ontwerpprincipes — spiegelen die van [PushService]:
/// - **Web-veilig**: elke publieke functie doet `if (kIsWeb) return;` als
///   eerste regel. Crashlytics heeft geen web-implementatie; de package
///   importeert wel maar `FirebaseCrashlytics.instance` throwt op web.
/// - **Fail-soft**: init zit in try/catch. Als Crashlytics faalt
///   (Google Play Services ontbreekt, netwerk-issue), blijft de rest van
///   de app werken.
/// - **Release-only collectie**: in debug/profile-builds staat collectie
///   uit zodat lokaal ontwikkelen crashes in de console laat i.p.v. ze
///   naar Firebase te sturen. In release-builds staat 'ie aan.
class CrashService {
  static bool _initGedaan = false;

  /// Roep aan direct na [Firebase.initializeApp] in main().
  /// Vangt zowel Flutter-framework errors (FlutterError.onError) als async
  /// errors buiten de Flutter zone (PlatformDispatcher.instance.onError).
  static Future<void> initApp() async {
    if (kIsWeb) return;
    if (_initGedaan) return;
    try {
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(kReleaseMode);
      _initGedaan = true;
    } catch (_) {
      // Rest van de app blijft draaien zonder Crashlytics.
    }
  }
}
