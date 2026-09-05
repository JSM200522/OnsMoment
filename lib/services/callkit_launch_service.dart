import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'bel_callkit_service.dart';
import 'callkit_flag_service.dart';

/// BEL-R2: leest de callkit-accept-actie uit het launch-intent van
/// MainActivity.kt en routeert de originele FCM-payload naar
/// [BelCallkitService.publiceerAcceptVanFcmDataJson]. Dat pad zet
/// vervolgens `PushService.incomingCallNotifier` met
/// `handmatigGeaccepteerd=true`, waarna de bestaande main-flow
/// direct naar `GesprekScherm` navigeert.
///
/// Waarom dit bestaat — zie ook MainActivity.kt (`BEL-R2`):
/// `flutter_callkit_incoming` 2.5.x heeft een bekend gat waarbij het
/// `actionCallAccept`-event bij cold-start uit killed state verloren
/// gaat (state bewaard in memory, niet cross-process). De launch-
/// intent-route is de bewezen community-fix: MainActivity leest het
/// intent dat de plugin naar de app stuurt bij accept, en levert de
/// call-data alsnog aan Dart. E4-`replayGeaccepteerdeCalls` blijft
/// als tweede vangnet.
///
/// Voorwaarden:
///  - Alleen actief als [CallkitFlagService.isEnabled] true is (net als
///    de rest van Optie B). Flag UIT → deze service doet niets.
///  - Alleen Android (native channel). Web/iOS: no-op via kIsWeb-guard.
///  - Idempotent: één `getLaunchAcceptData` per app-start; de callback
///    voor warm-start-accepts blijft leven tot process-death.
class CallkitLaunchService {
  CallkitLaunchService._();

  static const MethodChannel _channel =
      MethodChannel('nl.onsmoment.callkit_launch');

  static bool _geinitialiseerd = false;

  /// Aan te roepen vroeg in `main()`, na
  /// `WidgetsFlutterBinding.ensureInitialized()`.
  ///
  /// Doet twee dingen:
  ///  1. Registreert een MethodCallHandler zodat warm-start-accepts
  ///     (onNewIntent in MainActivity) direct naar Dart komen via
  ///     `onAcceptFromIntent`.
  ///  2. Polt eenmalig `getLaunchAcceptData` om het cold-start-pad
  ///     af te vangen (accept-tap opende de app vanuit killed state).
  ///
  /// Fail-soft op elke fout: log en verder — geen crash, geen impact
  /// op de rest van de app-init.
  static Future<void> initApp() async {
    if (kIsWeb) {
      debugPrint('☎️ BEL-R2 CallkitLaunchService: web — skip');
      return;
    }
    if (_geinitialiseerd) {
      debugPrint('☎️ BEL-R2 CallkitLaunchService: al geïnitialiseerd, skip');
      return;
    }
    _geinitialiseerd = true;
    // Callback voor warm-start-accepts (app draaide al, gebruiker tikt
    // 'Opnemen' — MainActivity.onNewIntent invoket dit).
    _channel.setMethodCallHandler((call) async {
      debugPrint('☎️ BEL-R2 CallkitLaunchService: channel-call '
          '${call.method} args=${call.arguments?.runtimeType}');
      if (call.method == 'onAcceptFromIntent') {
        final arg = call.arguments;
        if (arg is! String || arg.isEmpty) {
          debugPrint('⚠️ BEL-R2: onAcceptFromIntent zonder String-arg');
          return null;
        }
        await _verwerkAcceptData(arg, bron: 'onNewIntent-callback');
      }
      return null;
    });
    // Cold-start-pad: één keer vragen of er een gebufferde accept staat.
    // MainActivity heeft die in onCreate al geparseerd; getLaunchAcceptData
    // consumeert (en clear'd) de pending-buffer aan native kant.
    try {
      final flagAan = await CallkitFlagService.isEnabled();
      if (!flagAan) {
        debugPrint('☎️ BEL-R2 CallkitLaunchService: callkit-flag uit — '
            'skip cold-start poll');
        return;
      }
      final data = await _channel.invokeMethod<String?>('getLaunchAcceptData');
      if (data == null || data.isEmpty) {
        debugPrint('☎️ BEL-R2 CallkitLaunchService: geen pending accept '
            'op cold-start (getLaunchAcceptData=null/leeg)');
        return;
      }
      debugPrint('☎️ BEL-R2 CallkitLaunchService: cold-start pending '
          'accept gevonden (len=${data.length})');
      await _verwerkAcceptData(data, bron: 'cold-start-poll');
    } catch (e, st) {
      debugPrint('⚠️ BEL-R2 CallkitLaunchService.initApp faalde '
          '(niet blocking): $e\n$st');
    }
  }

  /// Enige uitgangspunt naar de bel-flow. Beide bronnen (cold-start-poll
  /// + onNewIntent-callback) delegeren hier zodat de logging consistent is
  /// en we op één plek de flag-check kunnen versterken bij eventuele
  /// warm-start (de flag kan tijdens app-runtime van waarde wisselen).
  static Future<void> _verwerkAcceptData(String fcmDataJson,
      {required String bron}) async {
    debugPrint('☎️ BEL-R2 CallkitLaunchService._verwerkAcceptData '
        '(bron=$bron) — start join-pad');
    // Bij warm-start opnieuw flag-check zodat het uitzetten van Optie B
    // tijdens de sessie ook effectief is voor deze route.
    final flagAan = await CallkitFlagService.isEnabled();
    if (!flagAan) {
      debugPrint('☎️ BEL-R2 CallkitLaunchService: flag uit tijdens verwerk '
          '(bron=$bron) — accept genegeerd');
      return;
    }
    BelCallkitService.publiceerAcceptVanFcmDataJson(fcmDataJson);
    debugPrint('☎️ BEL-R2 CallkitLaunchService: gepubliceerd naar '
        'incomingCallNotifier (bron=$bron) — main-flow neemt het over');
  }
}
