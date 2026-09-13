import 'dart:async';
import 'package:audio_session/audio_session.dart';
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
  Timer? _hardFallbackTimer;
  bool _klaarGemeld = false;

  @override
  void initState() {
    super.initState();
    unawaited(_startGeluid());
    _timer = Timer(widget.wachtduur, _meldKlaar);
    // P5 (14 sept 2026): hard-fallback zodat dit scherm NOOIT blijft
    // hangen als iets misgaat met de reguliere timer (bijv. een
    // async-race die _meldKlaar preempt of een navigator-hik). Elke
    // 10s harder proberen — user's toesteltest 13 sept had een klacht
    // dat het scherm 'niet weg te klikken' bleef. Met deze fallback +
    // canPop: true + de sluit-knop rechtsonder is dat structureel dicht.
    _hardFallbackTimer = Timer(const Duration(seconds: 10), _meldKlaar);
  }

  Future<void> _startGeluid() async {
    try {
      // FINAL-CHECK (14 sept 2026): expliciete AudioSession.configure +
      // setActive VÓÓR setAsset. Zelfde reden als BelScherm P4-fix: in
      // just_audio 0.9.46 wordt setAndroidAudioAttributes zonder actieve
      // AudioSession genegeerd → marimba stil gerouteerd door LiveKit's
      // aankomende MODE_IN_COMMUNICATION. Dit scherm speelt de marimba
      // ~2.5s vóór GesprekScherm-open — precies het venster waarin de
      // stille-routing zou plaatsvinden. Bug zat verborgen; nu preemptief
      // gefixt om te matchen met BelScherm's ringback-flow.
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        androidAudioAttributes: AndroidAudioAttributes(
          usage: AndroidAudioUsage.notificationRingtone,
          contentType: AndroidAudioContentType.sonification,
        ),
        androidAudioFocusGainType:
            AndroidAudioFocusGainType.gainTransientMayDuck,
      ));
      await session.setActive(true);
      await _speler.setAndroidAudioAttributes(
        const AndroidAudioAttributes(
          usage: AndroidAudioUsage.notificationRingtone,
          contentType: AndroidAudioContentType.sonification,
        ),
      );
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
    _hardFallbackTimer?.cancel();
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
    // P5 (14 sept 2026): back-swipe is nu WEL toegestaan (canPop: true)
    // als noodrem — bij een defecte timer of onverwachte navigator-state
    // moet de user er altijd uit kunnen. Er zit óók een expliciete
    // sluit-knop rechtsonder én een hard-fallback-timer in initState.
    // Ook de vorige "belt jou — we nemen zo op…" was correct, maar
    // "opent nu je gesprek…" is nog concreter voor de doelgroep.
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: kCream,
        body: SafeArea(
          child: Stack(children: [
            Center(
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
                    const Text('opent nu je gesprek…',
                        style: TextStyle(
                            fontSize: 22,
                            color: kBrownLight,
                            fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
            // P5: sluit-knop rechtsboven als noodrem. Klein maar
            // bereikbaar; de gebruiker die vaststrand kan altijd uit
            // deze schil. Kwetsbare dierbare ziet hem waarschijnlijk
            // niet — die kijkt naar de grote naam in het midden.
            Positioned(
              top: 12, right: 12,
              child: IconButton(
                icon: const Icon(Icons.close, color: kBrownLight, size: 28),
                tooltip: 'Sluiten',
                onPressed: _meldKlaar,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
