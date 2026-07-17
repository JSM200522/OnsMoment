import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../services/push_service.dart';
import '../../theme/kleuren.dart';

/// Inkomend videogesprek — full-screen scherm voor de tablet.
///
/// Dementie-vriendelijk ontwerp:
/// - Alleen twee acties: één grote GROENE 'Beantwoorden'-knop, één
///   kleinere RUSTIGE 'Niet nu'. Geen andere afleidingen — geen
///   snoozes, geen zijmenu's.
/// - Bellernaam is de grootste tekst op het scherm zodat de dierbare
///   direct herkent wie er belt.
/// - Cirkel met initiaal in peach (huisstijl) als foto-placeholder.
///   Foto uit de kring komt in een latere iteratie zodra we een
///   goedkope manier hebben om die uit Firestore te lezen zonder
///   het scherm-open te vertragen.
/// - Ringtone loopt continu met [bel.mp3] tot beantwoorden/niet-nu.
///   Fail-soft: als just_audio faalt (bv. tijdens hot-reload) blijft
///   het scherm gewoon werken zonder geluid.
///
/// Verantwoordelijkheden zijn strikt gescheiden:
/// - Dit scherm regelt UI + ringtone.
/// - [onBeantwoord] / [onAfgewezen] callbacks bepalen de vervolg-actie
///   (V2: net-verbonden-status, V3: echte LiveKit-connect via
///   [IncomingCall.calleeToken]). tablet_scherm (V2-5) implementeert ze.
class InkomendGesprekScherm extends StatefulWidget {
  final IncomingCall call;
  final VoidCallback onBeantwoord;
  final VoidCallback onAfgewezen;

  const InkomendGesprekScherm({
    super.key,
    required this.call,
    required this.onBeantwoord,
    required this.onAfgewezen,
  });

  @override
  State<InkomendGesprekScherm> createState() => _InkomendGesprekSchermState();
}

class _InkomendGesprekSchermState extends State<InkomendGesprekScherm> {
  final AudioPlayer _ringtone = AudioPlayer();
  bool _gehandeld = false;
  /// V3-4: auto-afwijzen als niemand binnen 45 seconden opneemt. Zelfde
  /// effect als de 'Niet nu'-knop indrukken — scherm sluit, ringtone
  /// stopt. Cancel in dispose en bij handmatig beantwoord/afwijs zodat
  /// hij niet nog een keer vuurt na sluiting.
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    unawaited(_startRingtone());
    _timeout = Timer(const Duration(seconds: 45), _afwijzen);
  }

  Future<void> _startRingtone() async {
    try {
      await _ringtone.setAsset('assets/sounds/bel.mp3');
      await _ringtone.setLoopMode(LoopMode.one);
      await _ringtone.play();
    } catch (_) {
      // Geluid is een 'nice-to-have' voor V2. Scherm blijft werken
      // zonder — de visuele bel-UI is de bron van waarheid.
    }
  }

  Future<void> _stopRingtone() async {
    try {
      await _ringtone.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    _timeout?.cancel();
    // Fire-and-forget: dispose mag niet async worden.
    unawaited(_ringtone.dispose());
    super.dispose();
  }

  void _beantwoord() {
    // Dubbel-tap-guard — voorkomt dat een enthousiaste dubbeltik
    // twee keer de vervolg-flow triggert.
    if (_gehandeld) return;
    _gehandeld = true;
    _timeout?.cancel();
    unawaited(_stopRingtone());
    widget.onBeantwoord();
  }

  void _afwijzen() {
    if (_gehandeld) return;
    _gehandeld = true;
    _timeout?.cancel();
    unawaited(_stopRingtone());
    widget.onAfgewezen();
  }

  String get _initiaal {
    final naam = widget.call.callerName.trim();
    if (naam.isEmpty) return '?';
    return naam.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back-swipe/-knop mag het gesprek NIET stiekem laten wegvallen —
      // de dierbare moet een expliciete keuze maken. canPop:false
      // blokkeert; de twee knoppen zijn de enige uitweg.
      canPop: false,
      child: Scaffold(
        backgroundColor: kCream,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(children: [
                  const Text('Inkomend gesprek',
                      style: TextStyle(fontSize: 24, color: kBrownLight,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 32),
                  Container(
                    width: 200, height: 200,
                    decoration: const BoxDecoration(
                      color: kPeach,
                      shape: BoxShape.circle,
                    ),
                    child: Center(child: Text(_initiaal,
                        style: const TextStyle(fontSize: 100, color: kWhite,
                            fontWeight: FontWeight.w900))),
                  ),
                  const SizedBox(height: 32),
                  Text(widget.call.callerName,
                      style: const TextStyle(fontSize: 56, color: kBrown,
                          fontWeight: FontWeight.w900),
                      textAlign: TextAlign.center),
                ]),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  SizedBox(
                    width: double.infinity, height: 100,
                    child: ElevatedButton.icon(
                      onPressed: _beantwoord,
                      icon: const Icon(Icons.videocam_rounded, size: 40),
                      label: const Text('Beantwoorden',
                          style: TextStyle(fontSize: 32,
                              fontWeight: FontWeight.w900)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kGreen,
                        foregroundColor: kWhite,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity, height: 60,
                    child: TextButton(
                      onPressed: _afwijzen,
                      child: const Text('Niet nu',
                          style: TextStyle(fontSize: 20, color: kBrownLight,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
