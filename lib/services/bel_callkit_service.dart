import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
// BEL-R1: overgestapt van hiennguyen92/flutter_callkit_incoming 2.5.0 naar
// de maintained fork 3.1.2. In tegenstelling tot wat de README suggereert
// re-exporteert de fork-barrel de entities NIET — ze worden alleen intern
// geïmporteerd. Voor `CallEvent`, `CallKitParams`, `AndroidParams`,
// `NotificationParams` moeten we `entities/entities.dart` daarom apart
// importeren, zoals ook in de 2.5-versie het geval was.
import 'package:flutter_callkit_incoming_maintained/entities/entities.dart';
import 'package:flutter_callkit_incoming_maintained/flutter_callkit_incoming_maintained.dart';
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

  /// BEL-R1: fork 3.1.0+ heeft een sealed CallEvent-refactor (PR #772).
  /// Bij accept/decline events krijgen we alleen `id` — de fcmData
  /// (met kringId, bellerApparaatId, callerName) zit dan NIET meer in
  /// de event-body. We cachen daarom `callId → fcmData` bij showCallkit
  /// zodat we in _verwerkEvent zonder round-trip naar de plugin kunnen
  /// bijkomen. Fallback (bij cold-start replay of gemiste cache-entry)
  /// blijft `activeCalls()` — daar staat `extra['fcmDataJson']` nog op.
  static final Map<String, Map<String, dynamic>> _fcmDataPerCallId = {};

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
      // BEL-R1: `textAccept`/`textDecline` staan in fork 3.1.x op
      // AndroidParams (voorheen op CallKitParams-niveau). `isFullScreen`
      // (PR #633) is nieuw en zorgt dat de callkit als volledig scherm
      // wordt getoond in plaats van als losse notificatie — cruciaal om
      // op A14+ prominent binnen te komen, ook als het OS de heads-up
      // wegdrukt vanwege ontbrekende USE_FULL_SCREEN_INTENT-toestemming.
      final params = CallKitParams(
        id: callId,
        nameCaller: callerName,
        appName: 'Ons Moment',
        handle: 'Videogesprek',
        type: 1, // video
        duration: 45000, // 45s ring-timeout (matcht bestaande V3-4)
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
          // BEL-R1: PR #633. Nieuwe fork-flag die de plugin een full-
          // screen activity laat starten. Werkt samen met (niet in
          // plaats van) isShowFullLockedScreen.
          isFullScreen: true,
          textAccept: 'Opnemen',
          textDecline: 'Weigeren',
        ),
      );
      // BEL-R1: cache fcmData vóór de plugin-call zodat het accept-event
      // (dat alleen callId meestuurt) meteen bij de originele FCM-payload
      // kan komen, ook als activeCalls() op sommige firmware een fractie
      // later pas terug is.
      _fcmDataPerCallId[callId] = fcmData;
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
        // BEL-R1: activeCalls() retourneert in fork 3.1.x een
        // List<CallKitParams>. `isAccepted` en `extra` zijn nu velden
        // op het object (voorheen kaarten met dynamische keys).
        final calls = await FlutterCallkitIncoming.activeCalls();
        final accepted = calls.where((c) => c.isAccepted).toList();
        debugPrint('☎️ BEL-P1 replay poll #$poging: '
            '${calls.length} entries, ${accepted.length} accepted');
        for (final call in accepted) {
          final fcmDataJson = call.extra?['fcmDataJson'];
          if (fcmDataJson is! String || fcmDataJson.isEmpty) {
            debugPrint('☎️ BEL-P1 replay: accepted call zonder '
                'fcmDataJson — skip');
            continue;
          }
          Map<String, dynamic>? fcmData;
          try {
            fcmData = jsonDecode(fcmDataJson) as Map<String, dynamic>;
          } catch (e) {
            debugPrint('☎️ BEL-P1 replay: fcmDataJson decode faalde: $e');
            continue;
          }
          final callId = call.id;
          debugPrint('☎️ BEL-P1 replay: geaccepteerde call gevonden na '
              'poll #$poging — publiceer (callId=$callId)');
          _publiceerAccept(fcmData);
          _fcmDataPerCallId.remove(callId);
          // Endcall zodat de callkit-state niet blijft rondzweven na
          // een succesvolle replay — voorkomt dat een volgende cold-
          // start dezelfde call opnieuw replayed.
          if (callId.isNotEmpty) {
            await _veiligBeeindig(callId);
          }
          return; // Enkel de eerste geaccepteerde call; klaar.
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
      // BEL-R1: fork 3.1.x — CallEvent is een sealed class met subtypes.
      // Accept/decline/ended/timeout leveren alleen een `id`; de originele
      // fcmData (met kringId, bellerApparaatId, callerNaam) halen we uit
      // onze in-memory cache met fallback op de plugin's activeCalls().
      switch (event) {
        case CallEventActionCallAccept(:final id):
          debugPrint('☎️ BelCallkitService event: Opnemen (callId=$id)');
          final fcmData = await _haalFcmDataOp(id);
          if (fcmData != null) {
            _publiceerAccept(fcmData);
          } else {
            debugPrint('⚠️ BelCallkitService: geen fcmData voor accepted '
                'callId=$id — publicatie overgeslagen');
          }
          _fcmDataPerCallId.remove(id);
          // BEL-B FIX3: expliciet endCall zodat de native call-UI +
          // ringing-notificatie direct verdwijnen. Zonder deze aanroep
          // blijft de melding op sommige Android-builds hangen tot de
          // 45s-timeout van CallKitParams.duration.
          if (id.isNotEmpty) {
            await _veiligBeeindig(id);
          }
        case CallEventActionCallDecline(:final id):
          debugPrint('☎️ BelCallkitService event: Weigeren (callId=$id)');
          final fcmData = await _haalFcmDataOp(id);
          if (fcmData != null) {
            await _stuurCancelNaarBeller(fcmData);
          } else {
            debugPrint('⚠️ BelCallkitService: geen fcmData voor declined '
                'callId=$id — cancelCall overgeslagen');
          }
          _fcmDataPerCallId.remove(id);
          // BEL-B FIX3: expliciet endCall — spiegel van accept-pad. Ook
          // hier is sluiten van de native UI onze verantwoordelijkheid;
          // de plugin garandeert dat niet consistent per firmware.
          if (id.isNotEmpty) {
            await _veiligBeeindig(id);
          }
        case CallEventActionCallEnded(:final id):
          // Ring-tijd voorbij of remote hangup — geen extra actie nodig,
          // native UI is al gesloten. Wel de cache-entry opruimen zodat
          // de map niet groeit.
          debugPrint('☎️ BelCallkitService event: ended (callId=$id)');
          _fcmDataPerCallId.remove(id);
        case CallEventActionCallTimeout(:final id):
          debugPrint('☎️ BelCallkitService event: timeout (callId=$id)');
          _fcmDataPerCallId.remove(id);
        default:
          // Overige events (incoming, connected, callback, toggle*) hebben
          // geen actie nodig in ons flow.
          break;
      }
    } catch (e, st) {
      debugPrint('⚠️ BelCallkitService event-verwerking faalde: $e\n$st');
    }
  }

  /// BEL-R1: haalt de originele fcmData op voor een callId. Eerst uit
  /// de in-memory cache (gevuld door [showCallkit] in dezelfde isolate);
  /// als die miss geeft — bijvoorbeeld bij cold-start-accept of tijdens
  /// een background-isolate — fallback op de plugin's [activeCalls] die
  /// `extra['fcmDataJson']` heeft doorbewaard.
  static Future<Map<String, dynamic>?> _haalFcmDataOp(String callId) async {
    if (callId.isEmpty) return null;
    final gecached = _fcmDataPerCallId[callId];
    if (gecached != null) {
      debugPrint('☎️ BEL-R1: fcmData uit in-memory cache (callId=$callId)');
      return gecached;
    }
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      for (final c in calls) {
        if (c.id != callId) continue;
        final fcmDataJson = c.extra?['fcmDataJson'];
        if (fcmDataJson is String && fcmDataJson.isNotEmpty) {
          debugPrint('☎️ BEL-R1: fcmData uit activeCalls() fallback '
              '(callId=$callId)');
          return jsonDecode(fcmDataJson) as Map<String, dynamic>;
        }
      }
    } catch (e) {
      debugPrint('⚠️ BEL-R1: activeCalls-fallback faalde voor '
          'callId=$callId: $e');
    }
    return null;
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
