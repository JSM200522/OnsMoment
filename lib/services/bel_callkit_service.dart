import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'push_service.dart';

/// Wrapper rond flutter_callkit_incoming voor de Optie B ConnectionService-
/// integratie. In B2 alleen een safe warm-up-probe zonder gedragswijziging.
/// De bel-flow loopt in deze fase nog volledig via de bestaande weg
/// (Optie A: FCM data-only + flutter_local_notifications).
///
/// De plugin registreert manifest-permissies, services en receivers via
/// manifest-merging bij de Flutter-build (MANAGE_OWN_CALLS, FOREGROUND_
/// SERVICE_PHONE_CALL, CallkitConnectionService voor SELF_MANAGED-support
/// op wifi-only toestellen zonder SIM, etc.). We hoeven aan onze eigen
/// AndroidManifest.xml niets toe te voegen.
class BelCallkitService {
  /// Fire-and-forget probe die tijdens app-init de plugin één keer 'raakt'.
  /// Doel: verifiëren dat de native side bereikbaar is en geen crash geeft
  /// bij het initiële method-channel-contact. Faalt de plugin — bijv. op
  /// een toestel zonder TelecomManager, of een niet-ondersteunde firmware
  /// — dan blijft de app volledig werken via Optie A.
  ///
  /// Garanties op crash-veiligheid:
  /// - kIsWeb-guard vóór elke plugin-aanroep (plugin heeft geen web-support)
  /// - try/catch op `Object` — vangt zowel Exception als Error (incl.
  ///   MissingPluginException, PlatformException, NoSuchMethodError)
  /// - Geen rethrow, geen UI-melding, geen SharedPreferences-write
  /// - Alleen debugPrint voor diagnose
  ///
  /// Wordt aangeroepen via `unawaited(BelCallkitService.warmupProbe())`
  /// zodat de main-thread nooit wordt geblokkeerd door plugin-registratie.
  static Future<void> warmupProbe() async {
    if (kIsWeb) {
      debugPrint('☎️ BelCallkitService: web — probe overgeslagen');
      return;
    }
    try {
      // endAllCalls is een read-only cleanup: als er geen actieve calls
      // zijn (zoals bij app-init) is dit een no-op. Wél triggert het de
      // eerste method-channel-hop naar native, wat betekent dat de plugin
      // z'n init-code doorloopt (o.a. het klaarzetten van de connection
      // service). PhoneAccount-registratie zelf blijft lazy tot de eerste
      // showCallkitIncoming (B3/B4).
      await FlutterCallkitIncoming.endAllCalls();
      debugPrint('☎️ BelCallkitService: warm-up probe OK');
    } catch (e, st) {
      // Bewust breed vangnet — een fout hier mag ONMOGELIJK de app-opstart
      // beïnvloeden. Optie A blijft de bel-flow dragen.
      debugPrint('⚠️ BelCallkitService warm-up faalde (val terug op '
          'Optie A): $e\n$st');
    }
  }

  // ── B3-B5: showCallkitIncoming + event-stream ─────────────────────

  /// Alleen aangeroepen door BEL-A-paden zodat A2 zichzelf kan
  /// deactiveren als B daadwerkelijk heeft getriggerd (B6).
  static bool _laatsteShowGelukt = false;
  static bool get laatsteShowGelukt => _laatsteShowGelukt;

  static StreamSubscription<CallEvent?>? _eventSub;

  /// Toont de native call-UI (ConnectionService op Android, CallKit op
  /// iOS). Return `true` als de plugin de show succesvol heeft ontvangen
  /// — nog GEEN garantie dat het OS de UI toont (kan alsnog falen op
  /// oude firmware). Bij `false` moet de caller terugvallen op Optie A.
  ///
  /// Payload wordt als `extra` meegegeven zodat het accept/decline-event
  /// (via [luisterEvents]) de originele FCM-data terugkrijgt en de
  /// bestaande [PushService.incomingCallNotifier] + cancelVideoCall-flow
  /// kan aansturen.
  static Future<bool> showCallkit({
    required String callId,
    required String callerName,
    required Map<String, dynamic> fcmData,
  }) async {
    if (kIsWeb) return false;
    try {
      final params = CallKitParams(
        id: callId,
        nameCaller: callerName,
        appName: 'Ons Moment',
        handle: 'Videogesprek',
        type: 1, // video
        duration: 45000, // 45s ring-timeout (matcht bestaande V3-4)
        textAccept: 'Opnemen',
        textDecline: 'Weigeren',
        missedCallNotification: const NotificationParams(
          showNotification: false,
          isShowCallback: false,
        ),
        extra: <String, dynamic>{
          'fcmDataJson': jsonEncode(fcmData),
        },
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#FF9B71',
          actionColor: '#FF9B71',
          incomingCallNotificationChannelName: 'Inkomend gesprek',
          missedCallNotificationChannelName: 'Gemiste gesprekken',
          isImportant: true,
        ),
      );
      await FlutterCallkitIncoming.showCallkitIncoming(params);
      _laatsteShowGelukt = true;
      return true;
    } catch (e, st) {
      _laatsteShowGelukt = false;
      debugPrint('⚠️ BelCallkitService.showCallkit faalde '
          '(val terug op Optie A): $e\n$st');
      return false;
    }
  }

  /// Sluit de native call-UI voor deze [callId] (bij server-cancel of
  /// wanneer de gebruiker in-app hangup doet). Fail-soft.
  static Future<void> beeindigCallkit(String callId) async {
    if (kIsWeb) return;
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (_) {}
  }

  /// Sluit ALLE native call-UI's (bijv. bij app-restart of forceer-cleanup).
  static Future<void> beeindigAlles() async {
    if (kIsWeb) return;
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {}
  }

  /// Registreert de event-listener die accept/decline/timeout/end
  /// omzet naar de bestaande PushService-notifiers + cancelVideoCall-
  /// call. Idempotent: dubbel aanroepen vervangt de bestaande subscription.
  ///
  /// Wordt aangeroepen door PushService.initApp zodat de listener leeft
  /// zolang de main-isolate draait. Voor achtergrond-events (dichte app)
  /// worden accept/decline door callkit via een intent naar
  /// CallkitIncomingActivity gerouteerd — die opent de app en trigert
  /// dezelfde event-stream in de main-isolate.
  static Future<void> luisterEvents() async {
    if (kIsWeb) return;
    try {
      await _eventSub?.cancel();
      _eventSub = FlutterCallkitIncoming.onEvent.listen(_verwerkEvent);
    } catch (e, st) {
      debugPrint('⚠️ BelCallkitService.luisterEvents faalde: $e\n$st');
    }
  }

  static Future<void> _verwerkEvent(CallEvent? event) async {
    if (event == null) return;
    try {
      final data = event.body is Map ? Map<String, dynamic>.from(
          event.body as Map) : const <String, dynamic>{};
      final extra = (data['extra'] is Map)
          ? Map<String, dynamic>.from(data['extra'] as Map)
          : const <String, dynamic>{};
      final fcmDataJson = extra['fcmDataJson'];
      Map<String, dynamic>? fcmData;
      if (fcmDataJson is String && fcmDataJson.isNotEmpty) {
        try {
          fcmData = jsonDecode(fcmDataJson) as Map<String, dynamic>;
        } catch (_) {}
      }

      switch (event.event) {
        case Event.actionCallAccept:
          if (fcmData != null) {
            _publiceerAccept(fcmData);
          }
          break;
        case Event.actionCallDecline:
          if (fcmData != null) {
            await _stuurCancelNaarBeller(fcmData);
          }
          break;
        case Event.actionCallEnded:
        case Event.actionCallTimeout:
          // Ring-tijd voorbij of remote hangup — geen extra actie nodig,
          // native UI is al gesloten. Alleen loggen.
          break;
        default:
          break;
      }
    } catch (e, st) {
      debugPrint('⚠️ BelCallkitService event-verwerking faalde: $e\n$st');
    }
  }

  static void _publiceerAccept(Map<String, dynamic> fcmData) {
    // Forceer autoAnswer=true zodat de main-flow direct naar
    // GesprekScherm springt (analoog aan actionId=='accept' in de
    // Optie-A-notificatietik-flow).
    final aangepast = Map<String, dynamic>.from(fcmData);
    aangepast['autoAnswer'] = 'true';
    final call = IncomingCall.uitFcmData(aangepast);
    if (call == null) return;
    if (PushService.incomingCallNotifier.value?.callId == call.callId) {
      return;
    }
    PushService.incomingCallNotifier.value = call;
  }

  static Future<void> _stuurCancelNaarBeller(
      Map<String, dynamic> fcmData) async {
    final kringId = fcmData['kringId'];
    final callId = fcmData['callId'];
    final bellerApparaatId = fcmData['bellerApparaatId'];
    if (kringId is! String || kringId.isEmpty) return;
    if (callId is! String || callId.isEmpty) return;
    if (bellerApparaatId is! String || bellerApparaatId.isEmpty) return;
    try {
      await Firebase.initializeApp();
      final callable = FirebaseFunctions
          .instanceFor(region: 'europe-west1')
          .httpsCallable('cancelVideoCall');
      await callable.call<dynamic>(<String, dynamic>{
        'kringId': kringId,
        'callId': callId,
        'doelApparaatId': bellerApparaatId,
      });
    } catch (e) {
      debugPrint('⚠️ callkit decline cancelCall faalde: $e');
    }
  }
}
