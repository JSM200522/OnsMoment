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
}
