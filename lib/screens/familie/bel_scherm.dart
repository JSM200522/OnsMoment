import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/video_call_service.dart';
import '../../theme/kleuren.dart';

/// Caller-perspectief van een gesprek. Voert de startVideoCall-flow uit,
/// join't LiveKit met het caller-token, en toont een self-view + wacht-
/// status tot de callee aan de andere kant opneemt. Ophangen ruimt alles
/// netjes op.
///
/// Detectie van "callee heeft opgenomen" gebeurt via een eigen listener
/// op de room die op [ParticipantConnectedEvent] wacht. LiveKit garandeert
/// dat lokale participants niet in dit event verschijnen; elke join
/// hierna is dus een echt remote-lid (de callee).
class BelScherm extends StatefulWidget {
  final String kringId;
  final String bellerApparaatId;
  final String doelApparaatId;
  final String doelNaam;

  const BelScherm({
    super.key,
    required this.kringId,
    required this.bellerApparaatId,
    required this.doelApparaatId,
    required this.doelNaam,
  });

  @override
  State<BelScherm> createState() => _BelSchermState();
}

enum _Fase {
  camera,
  verbinden,
  actief,
  geenPerm,
  fout,
}

class _BelSchermState extends State<BelScherm> {
  _Fase _fase = _Fase.camera;
  String _foutmelding = '';
  bool _calleeVerbonden = false;
  EventsListener<RoomEvent>? _roomListener;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final ok = await VideoCallService.vraagCameraPermissie();
      if (!mounted) return;
      if (!ok) {
        setState(() => _fase = _Fase.geenPerm);
        return;
      }
      setState(() => _fase = _Fase.verbinden);
      final resultaat = await VideoCallService.startCall(
        kringId: widget.kringId,
        bellerApparaatId: widget.bellerApparaatId,
        doelApparaatId: widget.doelApparaatId,
      );
      if (!mounted) return;
      await VideoCallService.join(resultaat.token);
      if (!mounted) return;
      final room = VideoCallService.roomNotifier.value;
      if (room != null) {
        final listener = room.createListener();
        listener.on<ParticipantConnectedEvent>((_) {
          if (!mounted) return;
          setState(() => _calleeVerbonden = true);
        });
        // Als de callee al join'de vóór dat we de listener attachten
        // (edge case: super-snelle callee), pikt remoteParticipants
        // dat op en zetten we de state gelijk.
        if (room.remoteParticipants.isNotEmpty) {
          _calleeVerbonden = true;
        }
        _roomListener = listener;
      }
      setState(() => _fase = _Fase.actief);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fase = _Fase.fout;
        _foutmelding = e.toString();
      });
    }
  }

  Future<void> _ophangen() async {
    await VideoCallService.hangup();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    unawaited(_roomListener?.dispose());
    // Ook bij back-swipe of proces-kill de LiveKit-verbinding netjes
    // verbreken — anders blijft de room op LiveKit-Cloud open tot de
    // sessie op timeout eruit valt.
    unawaited(VideoCallService.hangup());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: _bouwInhoud()),
    );
  }

  Widget _bouwInhoud() {
    switch (_fase) {
      case _Fase.camera:
        return _statusPaneel('Camera-toestemming vragen…');
      case _Fase.verbinden:
        return _statusPaneel('Bellen naar ${widget.doelNaam}…');
      case _Fase.actief:
        return _bouwActief();
      case _Fase.geenPerm:
        return _bouwGeenPerm();
      case _Fase.fout:
        return _bouwFout();
    }
  }

  Widget _statusPaneel(String tekst) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(color: kPeach),
        const SizedBox(height: 16),
        Text(tekst,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
      ]),
    );
  }

  Widget _bouwActief() {
    return ValueListenableBuilder<Room?>(
      valueListenable: VideoCallService.roomNotifier,
      builder: (context, room, _) {
        if (room == null) {
          return _statusPaneelMetKnop('Verbinding verloren');
        }
        return AnimatedBuilder(
          animation: room,
          builder: (context, _) {
            final pubs =
                room.localParticipant?.videoTrackPublications ?? const [];
            final track = pubs.isNotEmpty ? pubs.first.track : null;
            // Als AnimatedBuilder rebuild triggert door participant-events,
            // syncen we hier ook direct de calleeVerbonden-flag. Voorkomt
            // dat een track-event vóór ons ParticipantConnected-callback
            // de status stale laat.
            final callee = _calleeVerbonden
                || room.remoteParticipants.isNotEmpty;
            final status = callee
                ? 'Verbonden met ${widget.doelNaam}'
                : 'Wachten tot ${widget.doelNaam} opneemt…';
            return Stack(children: [
              Positioned.fill(
                child: track == null
                    ? const ColoredBox(color: Colors.black)
                    : VideoTrackRenderer(track),
              ),
              Positioned(
                top: 12, left: 12, right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(status,
                      style: const TextStyle(color: Colors.white,
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
              Positioned(
                bottom: 24, left: 0, right: 0,
                child: Center(child: _ophangKnop('Ophangen')),
              ),
            ]);
          },
        );
      },
    );
  }

  Widget _bouwGeenPerm() {
    return Center(
      child: Padding(padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.videocam_off_rounded,
              color: Colors.white, size: 48),
          const SizedBox(height: 16),
          const Text('Geen camera-toestemming',
              style: TextStyle(color: Colors.white, fontSize: 18,
                  fontWeight: FontWeight.w800),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text(
              'Zet camera aan in de app-instellingen om te kunnen '
              'videobellen.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kPeach, foregroundColor: kWhite,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12)),
            onPressed: () => openAppSettings(),
            child: const Text('Open instellingen',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 12),
          _ophangKnop('Sluiten'),
        ]),
      ),
    );
  }

  Widget _bouwFout() {
    return Center(
      child: Padding(padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded,
              color: kRood, size: 48),
          const SizedBox(height: 16),
          const Text('Bellen mislukt',
              style: TextStyle(color: Colors.white, fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(_foutmelding,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          _ophangKnop('Sluiten'),
        ]),
      ),
    );
  }

  Widget _ophangKnop(String label) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
          backgroundColor: kRood, foregroundColor: kWhite,
          padding: const EdgeInsets.symmetric(
              horizontal: 24, vertical: 14)),
      onPressed: _ophangen,
      icon: const Icon(Icons.call_end_rounded),
      label: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }

  Widget _statusPaneelMetKnop(String tekst) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(tekst,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        const SizedBox(height: 20),
        _ophangKnop('Sluiten'),
      ]),
    );
  }
}
