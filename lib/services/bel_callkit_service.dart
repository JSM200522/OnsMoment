import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'device_modus_service.dart';
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
      // BEL-Q3: de plugin heeft z'n eigen POST_NOTIFICATIONS-runtime-
      // prompt op Android 13+. firebase_messaging.requestPermission()
      // vraagt hetzelfde recht, maar de plugin kan een bekeken/geweigerd-
      // status apart bijhouden voor z'n eigen incoming-call-channel. Deze
      // extra call is idempotent (Android toont de prompt maar 1×) en
      // fail-soft — geen effect op oudere Android of als toestemming al
      // gegeven is.
      try {
        await FlutterCallkitIncoming.requestNotificationPermission(
            <String, dynamic>{});
        debugPrint('☎️ BEL-Q3: requestNotificationPermission verzonden');
      } catch (e) {
        debugPrint('⚠️ BEL-Q3: requestNotificationPermission faalde '
            '(niet blocking): $e');
      }
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
          // BEL-Q4: was true met eigen custom-layout notif — die is op
          // Android 12+ minder betrouwbaar dan de standaard CallStyle.
          // Op false gebruikt de plugin de native heads-up + full-screen
          // call-UI die door Android zelf gerenderd wordt. Visueel
          // prominenter en beter compatible met OS-versies (One UI,
          // ColorOS, MIUI hebben eigen custom-layouts die soms falen).
          isCustomNotification: false,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#FF9B71',
          actionColor: '#FF9B71',
          incomingCallNotificationChannelName: 'Inkomend gesprek',
          missedCallNotificationChannelName: 'Gemiste gesprekken',
          isImportant: true,
          // BEL-Q1: expliciet aanvragen dat de call-UI over het lock-
          // screen mag verschijnen. Zonder deze vlag toont de plugin op
          // Android 14+ de melding hooguit in de meldingenlade. In
          // combinatie met USE_FULL_SCREEN_INTENT (manifest) en de
          // special-permission-prompt (BEL-Q2) geeft dit de gewenste
          // prominente heads-up + lock-screen call-UI.
          isShowFullLockedScreen: true,
        ),
      );
      debugPrint('☎️ BelCallkitService.showCallkit → plugin-invoke '
          'callId=$callId caller="$callerName"');
      await FlutterCallkitIncoming.showCallkitIncoming(params);
      _laatsteShowGelukt = true;
      debugPrint('✅ BelCallkitService.showCallkit OK — native call-UI '
          'getriggerd (callId=$callId). PhoneAccount/ConnectionService '
          'binding wordt door plugin lazy afgehandeld; falen daar komt '
          'via een separate onEvent-error.');
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

  /// BEL-E4: cold-start replay voor dichte-app-accepts.
  ///
  /// Probleem: als de app KILLED was en de user tikt Opnemen in de
  /// callkit-heads-up, dan opent Android de Flutter-activity → main()
  /// draait → luisterEvents() wordt geregistreerd. Maar het
  /// actionCallAccept-event was al gefired VÓÓR de listener attached
  /// (onEvent is een broadcast-stream, niet buffered), en de plugin's
  /// TransparentActivity roept sendBroadcast(ACCEPT) fire-and-forget aan
  /// direct voordat hij de MainActivity start — dus de eerste
  /// activeCalls()-lookup uit Flutter kan RACEN met de native
  /// BroadcastReceiver die isAccepted=true naar SharedPrefs schrijft.
  ///
  /// BEL-P1: fix is retry-poll — probeer ~10× met 400ms delay (~4s max)
  /// totdat een isAccepted=true call verschijnt, of tot de user zelf
  /// tijdens die tijd al iets doet. Uitgebreide logging zodat we in
  /// production kunnen zien: replay aangeroepen? poll #N: X entries,
  /// Y accepted? call gevonden? publiceren?
  ///
  /// Idempotent + fail-soft: onbekende structuur → skip. Meerdere calls →
  /// alleen de eerste geaccepteerde wordt gerepubliceerd. Op iOS geeft
  /// activeCalls een CallKit-lijst; op Android alleen de laatste call
  /// (voldoende voor ons single-gesprek-model).
  static Future<void> replayGeaccepteerdeCalls() async {
    if (kIsWeb) return;
    debugPrint('☎️ BEL-P1 replay: aangeroepen — start poll (max ~4s)');
    const maxPogingen = 10;
    const pogingDelay = Duration(milliseconds: 400);
    for (var poging = 1; poging <= maxPogingen; poging++) {
      try {
        final ruw = await FlutterCallkitIncoming.activeCalls();
        if (ruw is! List) {
          debugPrint('☎️ BEL-P1 replay poll #$poging: '
              'result geen List ($ruw) — skip poging');
        } else {
          final accepted = ruw
              .whereType<Map>()
              .where((e) => e['isAccepted'] == true)
              .toList();
          debugPrint('☎️ BEL-P1 replay poll #$poging: '
              '${ruw.length} entries, ${accepted.length} accepted');
          for (final entry in accepted) {
            final extra = entry['extra'];
            if (extra is! Map) {
              debugPrint('☎️ BEL-P1 replay: accepted call zonder extra — skip');
              continue;
            }
            final fcmDataJson = extra['fcmDataJson'];
            if (fcmDataJson is! String || fcmDataJson.isEmpty) {
              debugPrint('☎️ BEL-P1 replay: extra zonder fcmDataJson — skip');
              continue;
            }
            Map<String, dynamic>? fcmData;
            try {
              fcmData = jsonDecode(fcmDataJson) as Map<String, dynamic>;
            } catch (e) {
              debugPrint('☎️ BEL-P1 replay: fcmDataJson decode faalde: $e');
              continue;
            }
            final callId = fcmData['callId'];
            debugPrint('☎️ BEL-P1 replay: geaccepteerde call gevonden na '
                'poll #$poging — publiceer (callId=$callId)');
            _publiceerAccept(fcmData);
            // Endcall zodat de callkit-state niet blijft rondzweven na
            // een succesvolle replay — voorkomt dat een volgende cold-
            // start dezelfde call opnieuw replayed.
            if (callId is String && callId.isNotEmpty) {
              await _veiligBeeindig(callId);
            }
            return; // Enkel de eerste geaccepteerde call; klaar.
          }
        }
      } catch (e, st) {
        debugPrint('⚠️ BEL-P1 replay poll #$poging fout '
            '(volgende poging): $e\n$st');
      }
      if (poging < maxPogingen) {
        await Future<void>.delayed(pogingDelay);
      }
    }
    debugPrint('☎️ BEL-P1 replay: geen geaccepteerde call na $maxPogingen '
        'pogingen — replay klaar (geen actie)');
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

      // callId zit zowel in de CallKitParams.id (data['id']) als in de
      // originele fcmData['callId']. Eerste is autoritair — dat is wat we
      // aan de plugin hebben doorgegeven bij showCallkit.
      final callId = () {
        final vanuitPlugin = data['id'];
        if (vanuitPlugin is String && vanuitPlugin.isNotEmpty) {
          return vanuitPlugin;
        }
        final vanuitFcm = fcmData?['callId'];
        return (vanuitFcm is String && vanuitFcm.isNotEmpty) ? vanuitFcm : '';
      }();

      switch (event.event) {
        case Event.actionCallAccept:
          debugPrint('☎️ BelCallkitService event: Opnemen (callId=$callId)');
          if (fcmData != null) {
            _publiceerAccept(fcmData);
          }
          // BEL-B FIX3: expliciet endCall zodat de native call-UI +
          // ringing-notificatie direct verdwijnen. Zonder deze aanroep
          // blijft de melding op sommige Android-builds hangen tot de
          // 45s-timeout van CallKitParams.duration.
          if (callId.isNotEmpty) {
            await _veiligBeeindig(callId);
          }
          break;
        case Event.actionCallDecline:
          debugPrint('☎️ BelCallkitService event: Weigeren (callId=$callId)');
          if (fcmData != null) {
            await _stuurCancelNaarBeller(fcmData);
          }
          // BEL-B FIX3: expliciet endCall — spiegel van accept-pad. Ook
          // hier is sluiten van de native UI onze verantwoordelijkheid;
          // de plugin garandeert dat niet consistent per firmware.
          if (callId.isNotEmpty) {
            await _veiligBeeindig(callId);
          }
          break;
        case Event.actionCallEnded:
        case Event.actionCallTimeout:
          // Ring-tijd voorbij of remote hangup — geen extra actie nodig,
          // native UI is al gesloten. Alleen loggen.
          debugPrint('☎️ BelCallkitService event: ended/timeout '
              '(callId=$callId)');
          break;
        default:
          break;
      }
    } catch (e, st) {
      debugPrint('⚠️ BelCallkitService event-verwerking faalde: $e\n$st');
    }
  }

  /// Interne wrapper rond [beeindigCallkit] met alleen extra logging zodat
  /// we in de traces zien of het endCall-pad daadwerkelijk liep na accept/
  /// decline. Fail-soft — plugin-fouten mogen de bel-flow niet raken.
  static Future<void> _veiligBeeindig(String callId) async {
    try {
      await FlutterCallkitIncoming.endCall(callId);
      debugPrint('☎️ BelCallkitService: endCall verzonden (callId=$callId)');
    } catch (e) {
      debugPrint('⚠️ BelCallkitService.endCall faalde (callId=$callId): $e');
    }
  }

  /// BEL-R2: publiek toegangspunt voor de MainActivity.kt launch-intent-
  /// route. [CallkitLaunchService] roept dit aan met de rauwe fcmDataJson
  /// die uit het accept-intent is gelezen. We decoderen hier en delegeren
  /// naar dezelfde [_publiceerAccept]-flow die ook door de callkit-onEvent
  /// en de activeCalls()-replay wordt gebruikt — één definitieve route
  /// naar [PushService.incomingCallNotifier] met handmatigGeaccepteerd.
  ///
  /// Fail-soft: ongeldige JSON of missing keys → log + skip, geen crash.
  /// Idempotent per callId dankzij de bestaande de-dup in
  /// [_publiceerAccept].
  static void publiceerAcceptVanFcmDataJson(String fcmDataJson) {
    if (fcmDataJson.isEmpty) {
      debugPrint('☎️ BEL-R2: publiceerAcceptVanFcmDataJson: lege string');
      return;
    }
    Map<String, dynamic> fcmData;
    try {
      fcmData = jsonDecode(fcmDataJson) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('⚠️ BEL-R2: fcmDataJson decode faalde: $e');
      return;
    }
    final callId = fcmData['callId'];
    debugPrint('☎️ BEL-R2: publiceer accept vanuit intent '
        '(callId=$callId, keys=${fcmData.keys.join(",")})');
    _publiceerAccept(fcmData);
  }

  static void _publiceerAccept(Map<String, dynamic> fcmData) {
    // BEL-P2: zet handmatigGeaccepteerd i.p.v. autoAnswer. Callkit-accept
    // is een bewuste tik door de callee — het waarschuwingsscherm ("we
    // nemen zo op…") hoort daar niet bij. Main-flow springt direct naar
    // GesprekScherm. autoAnswer blijft de server-side kring-waarde.
    final aangepast = Map<String, dynamic>.from(fcmData);
    aangepast['handmatigGeaccepteerd'] = 'true';
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
      // BEL-R3: eigen apparaatId is de ontvanger die weigert; meesturen
      // zodat server het bezet-slot opruimt en een volgende beller niet
      // 5 min hoeft te wachten op TTL. Fail-soft: als apparaatId
      // opvragen faalt sturen we alleen de bestaande payload — cancel
      // werkt dan nog steeds, alleen valt slot-cleanup terug op TTL.
      String? eigenApparaatId;
      try {
        eigenApparaatId = await DeviceModusService.krijgApparaatId();
      } catch (e) {
        debugPrint('⚠️ BEL-R3: eigen apparaatId ophalen faalde: $e');
      }
      final payload = <String, dynamic>{
        'kringId': kringId,
        'callId': callId,
        'doelApparaatId': bellerApparaatId,
      };
      if (eigenApparaatId != null && eigenApparaatId.isNotEmpty) {
        payload['ontvangerApparaatId'] = eigenApparaatId;
      }
      final callable = FirebaseFunctions
          .instanceFor(region: 'europe-west1')
          .httpsCallable('cancelVideoCall');
      await callable.call<dynamic>(payload);
    } catch (e) {
      debugPrint('⚠️ callkit decline cancelCall faalde: $e');
    }
  }
}
