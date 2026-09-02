import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

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
/// V0 levert het skelet + method-signatures. V1 vult de LiveKit-connect-
/// logica in (join/leave, remote-participant listeners, camera-permission
/// runtime-request).
class VideoCallService {
  /// LiveKit Cloud URL — publiek, mag in code (project onsmoment-jsh7c0m3,
  /// EU-region). Secrets (API key + secret) blijven server-side in de
  /// Cloud Function via `defineSecret` (zie functions/src/videocall.ts).
  static const String livekitUrl =
      'wss://onsmoment-jsh7c0m3.livekit.cloud';

  static bool _initGedaan = false;
  static Room? _room;
  /// Gescheiden van [_room] zodat we hem in [hangup] netjes kunnen
  /// disposen los van de room-lifecycle. LiveKit garbage-collect de
  /// listener niet vanzelf zodra de room weg is.
  static EventsListener<RoomEvent>? _listener;

  /// Actieve LiveKit-room, of null als er geen gesprek loopt. UI-schermen
  /// luisteren hierop om de juiste view te tonen (idle vs actief-gesprek).
  static final ValueNotifier<Room?> roomNotifier =
      ValueNotifier<Room?>(null);

  /// Modus voor [haalToken]. Server valideert dat de bijbehorende
  /// velden aanwezig zijn (kringId voor gesprek, apparaatId altijd).
  static const String modusTest = 'test';
  static const String modusGesprek = 'gesprek';

  /// Vraagt bij de Cloud Function [getVideoCallToken] (europe-west1) een
  /// korte JWT op waarmee de client kan verbinden met de door de server
  /// bepaalde LiveKit-room. Sinds V2-0 bepaalt de server zowel [roomName]
  /// als [identity] — de client kan zich niet meer als iemand anders
  /// identificeren en kan geen tokens voor willekeurige rooms opvragen.
  ///
  /// Payload:
  /// - [modus]: [modusTest] of [modusGesprek].
  /// - [apparaatId]: altijd verplicht; server bindt hem aan de auth-uid
  ///   voor de identity en verifieert dat het apparaat-doc bestaat.
  /// - [kringId]: alleen verplicht bij [modusGesprek]; server checkt
  ///   membership (leden-doc of eigenaar-fallback).
  ///
  /// Returnt een record met token/roomName/identity. Throwt bij netwerk-
  /// fout, HttpsError of onverwacht antwoord; caller (V1 test-scherm,
  /// V3+ belflow) beslist over UI-feedback.
  static Future<({String token, String roomName, String identity})>
      haalToken({
    required String modus,
    required String apparaatId,
    String? kringId,
  }) async {
    final payload = <String, dynamic>{
      'modus': modus,
      'apparaatId': apparaatId,
    };
    if (kringId != null && kringId.isNotEmpty) {
      payload['kringId'] = kringId;
    }
    final callable = FirebaseFunctions
        .instanceFor(region: 'europe-west1')
        .httpsCallable('getVideoCallToken');
    final result = await callable.call<dynamic>(payload);
    final data = result.data;
    if (data is! Map) {
      throw StateError('Cloud Function gaf onverwacht antwoord');
    }
    final token = data['token'];
    final roomName = data['roomName'];
    final identity = data['identity'];
    if (token is! String || token.isEmpty
        || roomName is! String || roomName.isEmpty
        || identity is! String || identity.isEmpty) {
      throw StateError('Cloud Function gaf incompleet antwoord');
    }
    return (token: token, roomName: roomName, identity: identity);
  }

  /// V2: initieert een gesprek via de [startVideoCall] Cloud Function.
  /// Server bepaalt roomName + callId; caller-token komt in de response,
  /// callee-token gaat via high-priority data-FCM naar het doel-
  /// apparaat (zie functions/src/start_call.ts).
  ///
  /// Payload:
  /// - [kringId]: de kring waarin het gesprek plaatsvindt.
  /// - [bellerApparaatId]: eigen apparaatId van de beller (server bindt
  ///   hem aan de auth-uid voor de identity).
  /// - [doelApparaatId]: apparaatId van de callee. Server verifieert
  ///   dat dat apparaat in dezelfde kring zit en een fcmToken heeft.
  ///
  /// Returnt een record met caller-token/roomName/callId. Throwt bij
  /// netwerkfout, HttpsError of onverwacht antwoord; caller beslist over
  /// UI-feedback. Verwachte HttpsError-codes:
  /// - permission-denied  → beller is geen lid / doel niet in kring
  /// - not-found           → kring of doel-apparaat bestaat niet
  /// - failed-precondition → doel heeft geen fcmToken
  /// - resource-exhausted  → rate-limit (max 10/min per uid)
  /// - unavailable         → FCM naar doel is mislukt
  static Future<({String token, String roomName, String callId})>
      startCall({
    required String kringId,
    required String bellerApparaatId,
    required String doelApparaatId,
  }) async {
    final callable = FirebaseFunctions
        .instanceFor(region: 'europe-west1')
        .httpsCallable('startVideoCall');
    final result = await callable.call<dynamic>(<String, dynamic>{
      'kringId': kringId,
      'bellerApparaatId': bellerApparaatId,
      'doelApparaatId': doelApparaatId,
    });
    final data = result.data;
    if (data is! Map) {
      throw StateError('startVideoCall gaf onverwacht antwoord');
    }
    final token = data['token'];
    final roomName = data['roomName'];
    final callId = data['callId'];
    if (token is! String || token.isEmpty
        || roomName is! String || roomName.isEmpty
        || callId is! String || callId.isEmpty) {
      throw StateError('startVideoCall gaf incompleet antwoord');
    }
    return (token: token, roomName: roomName, callId: callId);
  }

  /// V3: annuleert een lopend uitgaand gesprek vóórdat de callee heeft
  /// opgenomen. Roept de [cancelVideoCall] Cloud Function aan die een
  /// data-FCM naar het doel-apparaat pusht met `type:
  /// 'gesprek_geannuleerd'`; de tablet sluit het inkomend-scherm alleen
  /// als de callId matcht met de openstaande call.
  ///
  /// Returnt of de FCM daadwerkelijk verzonden is. Bij false is er geen
  /// probleem — de tablet valt terug op de 45s-timeout. Alleen security-
  /// laag fouten worden ge-throwt (unauth, rate-limit, membership).
  ///
  /// Bewust fire-and-forget-vriendelijk: caller kan het resultaat
  /// negeren en direct doorgaan met hangup(), want een falende cancel
  /// mag de ophangen-UI niet blokkeren.
  static Future<bool> cancelCall({
    required String kringId,
    required String callId,
    required String doelApparaatId,
  }) async {
    final callable = FirebaseFunctions
        .instanceFor(region: 'europe-west1')
        .httpsCallable('cancelVideoCall');
    final result = await callable.call<dynamic>(<String, dynamic>{
      'kringId': kringId,
      'callId': callId,
      'doelApparaatId': doelApparaatId,
    });
    final data = result.data;
    if (data is! Map) return false;
    return data['verzonden'] == true;
  }

  /// Runtime camera-permissie. Native: vraagt via [permission_handler] en
  /// returnt of de gebruiker het permitteerde. Web: no-op → true, want
  /// de browser vraagt zelf om toestemming zodra LiveKit getUserMedia
  /// aanroept (permission_handler is op web te beperkt om hier zinvol
  /// te zijn). Als de gebruiker 'permanent geweigerd' heeft gekozen
  /// laat deze method dat aan de caller — die kan dan
  /// [openAppSettings] tonen als UX-vervolg.
  static Future<bool> vraagCameraPermissie() async {
    if (kIsWeb) return true;
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  /// Roep aan in main() na Firebase.initializeApp(). Web + flag-uit
  /// → no-op. Alle initialisatie zit in try/catch zodat een LiveKit-
  /// fout de rest van de app niet stukmaakt.
  static Future<void> initApp() async {
    if (kIsWeb) return;
    if (_initGedaan) return;
    try {
      // V1: eventueel globale Room-listeners of camera-permission-warmup.
      _initGedaan = true;
    } catch (_) {
      // Rest van de app blijft werken zonder videobel-feature.
    }
  }

  /// Verbindt met [livekitUrl] via [token], joint de room en publiceert
  /// camera + microfoon. Vult [roomNotifier] met de actieve room zodat UI
  /// naar het gesprek-scherm kan switchen. No-op op web.
  ///
  /// Werkwijze:
  /// - Eerst [hangup] aanroepen zodat een oude sessie netjes opruimt als
  ///   join per ongeluk dubbel wordt aangeroepen (voorkomt orphan-rooms).
  /// - Verse [Room] per sessie — LiveKit-listeners en publications leven
  ///   op room-niveau; hergebruik zou stale state kunnen introduceren.
  /// - [RoomDisconnectedEvent] triggert bij server-drop of netwerkverlies.
  ///   Daar resetten we alleen state; hangup zelf disposet de listener,
  ///   dus we voorkomen dubbele dispose.
  /// - Faalt connect of publish, dan reverten we alle state en re-throwen
  ///   zodat het aanroepend scherm foutmelding kan tonen.
  static Future<void> join(String token) async {
    if (kIsWeb) return;
    await hangup();
    // RoomOptions horen sinds livekit_client 2.x in de constructor, niet
    // in connect() (die parameter is daar deprecated).
    final room = Room(
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
      ),
    );
    final listener = room.createListener();
    listener.on<RoomDisconnectedEvent>((_) {
      _room = null;
      roomNotifier.value = null;
    });
    // BEL-D FIX4: als de tegenpartij ophangt, disconnect de LOKALE room
    // ook zodat GesprekScherm bij BEIDE kanten sluit. Zonder deze listener
    // bleef de andere kant in GesprekScherm hangen met een "Wachten tot
    // X verschijnt…"-overlay tot de gebruiker zelf ophing.
    //
    // Waarom veilig bij netwerk-haperingen: LiveKit's client houdt eerst
    // een re-connect-window aan (10-15s standaard) voordat een participant
    // als 'disconnected' wordt gemarkeerd. Korte glitches vuren dit event
    // NIET; alleen echt weggevallen deelnemers. Daarnaast controleren we
    // remoteParticipants.isEmpty vóór we hangen — als er nog anderen in
    // de room zitten (multi-party in latere fase) blijven we hangen.
    listener.on<ParticipantDisconnectedEvent>((event) {
      final actieveRoom = _room;
      if (actieveRoom == null) return;
      if (actieveRoom.remoteParticipants.isEmpty) {
        debugPrint('📞 VideoCallService: laatste remote-participant weg — '
            'sluit lokale room (identity=${event.participant.identity})');
        // Fire-and-forget hangup: idempotent en synchroon-resettend, dus
        // een tweede tap of dispose kan hier bovenop zonder schade.
        unawaited(hangup());
      }
    });
    try {
      await room.connect(livekitUrl, token);
      await room.localParticipant?.setCameraEnabled(true);
      await room.localParticipant?.setMicrophoneEnabled(true);
      _room = room;
      _listener = listener;
      roomNotifier.value = room;
    } catch (_) {
      await listener.dispose();
      try {
        await room.disconnect();
      } catch (_) {
        // Al mislukt; niets extra's te doen.
      }
      rethrow;
    }
  }

  /// Verbreekt het gesprek en ruimt de room + listener op. Safe om te
  /// callen als er geen gesprek loopt. Wordt door V3 aangeroepen vanaf
  /// de ophangen-knop op het gesprek-scherm.
  ///
  /// State wordt SYNCHROON gereset vóór we disconnect awaiten, zodat
  /// een ophang-knop voelt-als-direct-reagerend en een tweede tap niet
  /// dezelfde room nogmaals disconnect.
  static Future<void> hangup() async {
    if (kIsWeb) return;
    final room = _room;
    final listener = _listener;
    _room = null;
    _listener = null;
    roomNotifier.value = null;
    await listener?.dispose();
    if (room == null) return;
    try {
      await room.disconnect();
    } catch (_) {
      // Al disconnected of netwerk-uit — negeer.
    }
  }
}
