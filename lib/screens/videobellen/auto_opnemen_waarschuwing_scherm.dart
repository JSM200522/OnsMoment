import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../theme/kleuren.dart';

/// BEL-C FIX 5: dementie-vriendelijk tussenscherm dat 2.5s speelt
/// vóór een auto-answer-gesprek automatisch opent.
///
/// Doel: nooit onaangekondigd een open camera bij een kwetsbare
/// dierbare. Ze horen eerst een warme marimba-toon en zien in grote
/// letters wie er zo verschijnt, zodat het menselijk voelt in plaats
/// van technisch — je oma denkt "o, mijn dochter" ipv "wat is dit?".
///
/// Gebruik: push dit scherm; het pop't zichzelf na [wachtduur] via de
/// [onKlaar]-callback. Caller doet daarna de push naar GesprekScherm.
///
/// Fail-soft geluid: als just_audio faalt (hot-reload, asset-load-race)
/// blijft het scherm gewoon draaien en pop't na de timer. De visuele
/// aankondiging is de bron van waarheid.
class AutoOpnemenWaarschuwingScherm extends StatefulWidget {
  final String callerName;
  final VoidCallback onKlaar;
  final Duration wachtduur;

  const AutoOpnemenWaarschuwingScherm({
    super.key,
    required this.callerName,
    required this.onKlaar,
    this.wachtduur = const Duration(milliseconds: 2500),
  });

  @override
  State<AutoOpnemenWaarschuwingScherm> createState() =>
      _AutoOpnemenWaarschuwingSchermState();
}

class _AutoOpnemenWaarschuwingSchermState
    extends State<AutoOpnemenWaarschuwingScherm> {
  final AudioPlayer _speler = AudioPlayer();
  Timer? _timer;
  bool _klaarGemeld = false;

  @override
  void initState() {
    super.initState();
    unawaited(_startGeluid());
    _timer = Timer(widget.wachtduur, _meldKlaar);
  }

  Future<void> _startGeluid() async {
    try {
      await _speler.setAsset('assets/sounds/marimba.wav');
      // Eén keer afspelen — de wachtduur is korter dan de sample dus
      // een loop is overbodig en zou halverwege afgekapt worden.
      await _speler.play();
    } catch (_) {
      // Nice-to-have; scherm blijft werken zonder geluid.
    }
  }

  void _meldKlaar() {
    if (_klaarGemeld) return;
    _klaarGemeld = true;
    widget.onKlaar();
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_speler.stop());
    unawaited(_speler.dispose());
    super.dispose();
  }

  String get _initiaal {
    final naam = widget.callerName.trim();
    if (naam.isEmpty) return '?';
    return naam.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    // Back-swipe blokkeren — de gebruiker mag hier niet uitvallen; het
    // scherm sluit vanzelf zodra de timer klaar is en het gesprek opent.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: kCream,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 200, height: 200,
                    decoration: const BoxDecoration(
                      color: kPeach,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(_initiaal,
                          style: const TextStyle(
                              fontSize: 100,
                              color: kWhite,
                              fontWeight: FontWeight.w900)),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(widget.callerName,
                      style: const TextStyle(
                          fontSize: 44,
                          color: kBrown,
                          fontWeight: FontWeight.w900),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  const Text('belt jou — we nemen zo op…',
                      style: TextStyle(
                          fontSize: 22,
                          color: kBrownLight,
                          fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
