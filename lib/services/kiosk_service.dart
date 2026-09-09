import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Dunne wrapper rond het Android-kiosk method channel.
///
/// Alle methoden zijn no-ops op web (kIsWeb-guard) en falen silent op
/// Android zodat een niet-beschikbare Activity nooit een crash veroorzaakt.
///
/// Levenscyclus (voor elke TabletScherm-instantie):
///   initState → KioskService.init(_callback)
///   dispose   → KioskService.wis()   ← altijd eerst, dan stop()
///               KioskService.stop()
///
/// De callback wordt door onTaskUnpinned() aangroepen als Android meldt
/// dat de gebruiker het pin-gebaar heeft gebruikt. TabletScherm beslist
/// dan of herpin nodig is (modus-check + mounted-check).
class KioskService {
  static const _channel = MethodChannel('nl.onsmoment.kiosk');
  static void Function()? _onTaskUnpinnedCallback;

  /// Registreer de onTaskUnpinned-callback en activeer de channel-handler.
  /// Aanroepen vanuit TabletScherm.initState (enkel als DEBUG_KIOSK && !kIsWeb).
  static void init(void Function() onTaskUnpinned) {
    _onTaskUnpinnedCallback = onTaskUnpinned;
    _channel.setMethodCallHandler(_verwerkNatiefBericht);
  }

  /// Wis de callback VÓÓR stop() zodat een onTaskUnpinned-event dat na
  /// stopLockTask() arriveert geen herpin triggert op een al-disposed widget.
  static void wis() {
    _onTaskUnpinnedCallback = null;
  }

  static Future<dynamic> _verwerkNatiefBericht(MethodCall call) async {
    if (call.method == 'onTaskUnpinned') {
      _onTaskUnpinnedCallback?.call();
    }
  }

  /// Android startLockTask() — activeert Screen Pinning zonder device-owner.
  static Future<void> start() async {
    if (kIsWeb) return;
    try { await _channel.invokeMethod<void>('startKiosk'); } catch (_) {}
  }

  /// Android stopLockTask() — heft Screen Pinning op.
  static Future<void> stop() async {
    if (kIsWeb) return;
    try { await _channel.invokeMethod<void>('stopKiosk'); } catch (_) {}
  }

  /// Verberg navigatiebalk + statusbalk (immersiveSticky). Swipe-vanuit-
  /// rand toont ze kort, waarna ze vanzelf verdwijnen.
  static void verbergSysteemUI() {
    if (kIsWeb) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  /// Herstel edge-to-edge (de app-brede standaard uit main.dart).
  static void herstelSysteemUI() {
    if (kIsWeb) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  /// Android 14+ (API 34): true als de app USE_FULL_SCREEN_INTENT heeft.
  /// Op oudere versies is de toestemming automatisch — altijd true.
  static Future<bool> kanFullScreenIntent() async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod<bool>('checkFullScreenIntent') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Opent de Android-instelling waarmee de gebruiker USE_FULL_SCREEN_INTENT
  /// kan verlenen. No-op op API < 34 (toestemming al automatisch verleend).
  static Future<void> vraagFullScreenIntent() async {
    if (kIsWeb) return;
    try { await _channel.invokeMethod<void>('requestFullScreenIntent'); } catch (_) {}
  }

  /// BEL-A4: true als de app is uitgezonderd van battery-optimalisatie.
  /// Op Android < 6 (Marshmallow) bestaat de feature niet → altijd true.
  static Future<bool> isBatteryOptimizationUit() async {
    if (kIsWeb) return true;
    try {
      return await _channel.invokeMethod<bool>('isBatteryOptimizationUit')
          ?? true;
    } catch (_) {
      return true;
    }
  }

  /// BEL-A4: toont het Android-systeemdialoog waarmee de gebruiker deze
  /// app kan uitzonderen van battery-optimalisatie. No-op op web en op
  /// API < 23. Samsung heeft een tweede laag ("Sleeping apps") die
  /// alleen handmatig via Instellingen kan — de aanroeper toont
  /// daarvoor een aparte uitleg.
  static Future<void> vraagBatteryOptimizationUit() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('vraagBatteryOptimizationUit');
    } catch (_) {}
  }

  /// BEL-D1: leest een pending auto-answer payload uit MainActivity als
  /// de Activity zojuist door OnsMomentFcmReceiver is gestart voor een
  /// auto-answer scenario (scherm AAN + app dicht + SYSTEM_ALERT_WINDOW).
  ///
  /// Returnt null als er geen pending is (normale launch, of receiver
  /// heeft niet gefired). Bij een geldige match: map met `payload` (JSON-
  /// string van de FCM-data) en `callId`.
  ///
  /// Éénmalig: na deze read wist MainActivity zijn eigen state — een
  /// tweede call retourneert null. Voorkomt dat een resume-cycle een
  /// oud auto-answer scherm opnieuw triggert.
  static Future<Map<String, String>?> haalPendingAutoAnswer() async {
    if (kIsWeb) return null;
    try {
      final r = await _channel.invokeMethod<dynamic>('haalPendingAutoAnswer');
      if (r == null) return null;
      if (r is Map) {
        final payload = r['payload'];
        final callId = r['callId'];
        if (payload is String && payload.isNotEmpty) {
          return {
            'payload': payload,
            'callId': callId is String ? callId : '',
          };
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
