import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/device_modus_service.dart';
import '../../services/video_call_service.dart';
import '../../theme/kleuren.dart';

/// Verborgen test-scherm voor Fase VB-V1. Bereikbaar vanuit Instellingen
/// zolang [DEBUG_VIDEOBELLEN] aan staat. Bedoeld om de complete keten
/// (camera-permissie → Cloud Function → LiveKit-connect → self-view)
/// in één klik uit te oefenen, zónder dat er al een echte belflow of
/// ontvanger-kant klaar hoeft te staan.
///
/// De room-naam is per apparaat uniek (`test_{apparaatId}`) zodat twee
/// testtoestellen tegelijk niet in elkaars gesprek belanden. Wie er
/// alsnog samen wil testen zet expliciet dezelfde apparaatId over —
/// dat komt in V2 wanneer we een tweede deelnemer toevoegen.
class VideobellenTestScherm extends StatefulWidget {
  const VideobellenTestScherm({super.key});

  @override
  State<VideobellenTestScherm> createState() => _VideobellenTestSchermState();
}

enum _Fase {
  camera,
  token,
  verbinden,
  actief,
  geenPerm,
  fout,
}

class _VideobellenTestSchermState extends State<VideobellenTestScherm> {
  _Fase _fase = _Fase.camera;
  String _foutmelding = '';

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
      setState(() => _fase = _Fase.token);
      final apparaatId = await DeviceModusService.krijgApparaatId();
      final token = await VideoCallService.haalToken(
        roomName: 'test_$apparaatId',
        identity: '${apparaatId}_test',
      );
      if (!mounted) return;
      setState(() => _fase = _Fase.verbinden);
      await VideoCallService.join(token);
      if (!mounted) return;
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
      case _Fase.token:
        return _statusPaneel('Token ophalen…');
      case _Fase.verbinden:
        return _statusPaneel('Verbinden met LiveKit…');
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
        // Room is een ChangeNotifier: rebuild zodra tracks published/
        // unpublished worden zodat de self-view zonder polling verschijnt.
        return AnimatedBuilder(
          animation: room,
          builder: (context, _) {
            final pubs =
                room.localParticipant?.videoTrackPublications ?? const [];
            final track = pubs.isNotEmpty ? pubs.first.track : null;
            return Stack(children: [
              Positioned.fill(
                child: track == null
                    ? const ColoredBox(color: Colors.black)
                    : VideoTrackRenderer(track),
              ),
              // Kader met status linksboven — zodat je in de test snel
              // ziet dat het écht een live-track is en geen still.
              Positioned(
                top: 12, left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Text('TEST · self-view',
                      style: TextStyle(color: Colors.white, fontSize: 12,
                          fontWeight: FontWeight.w700)),
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
              'Zet camera aan in de app-instellingen om de videobel-'
              'functie te testen.',
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
          const Text('Verbinden mislukt',
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
