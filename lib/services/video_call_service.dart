import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

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

  /// Actieve LiveKit-room, of null als er geen gesprek loopt. UI-schermen
  /// luisteren hierop om de juiste view te tonen (idle vs actief-gesprek).
  static final ValueNotifier<Room?> roomNotifier =
      ValueNotifier<Room?>(null);

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

  /// V1: verbindt met [livekitUrl] via [token], joint de room en publiceert
  /// camera + microfoon. Vult [roomNotifier] met de actieve room zodat UI
  /// naar het gesprek-scherm kan switchen. No-op op web.
  static Future<void> join(String token) async {
    if (kIsWeb) return;
    // V1 implementeert dit:
    //   final room = Room();
    //   await room.connect(livekitUrl, token,
    //       roomOptions: const RoomOptions(adaptiveStream: true,
    //           dynacast: true));
    //   await room.localParticipant?.setCameraEnabled(true);
    //   await room.localParticipant?.setMicrophoneEnabled(true);
    //   _room = room;
    //   roomNotifier.value = room;
  }

  /// Verbreekt het gesprek en ruimt de room op. Safe om te callen als
  /// er geen gesprek loopt. Wordt door V3 aangeroepen vanaf de ophangen-
  /// knop op het gesprek-scherm.
  static Future<void> hangup() async {
    if (kIsWeb) return;
    try {
      await _room?.disconnect();
    } catch (_) {
      // Disconnect kan falen als de verbinding al weg is; log niet nodig.
    }
    _room = null;
    roomNotifier.value = null;
  }
}
