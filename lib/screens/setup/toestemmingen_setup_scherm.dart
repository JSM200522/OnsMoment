import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../services/kiosk_service.dart';
import '../../services/overlay_permission_service.dart';
import '../../theme/kleuren.dart';
import '../../widgets/normaal_scaffold.dart';

/// BEL-D2: Toestemmingen-stap voor de ontvanger-setup.
///
/// Wordt getoond direct nadat de eigenaar de weergavemodus voor het
/// ontvanger-apparaat heeft gekozen. Doel: alle Android-toestemmingen die
/// voor betrouwbaar bellen nodig zijn worden HIER één keer duidelijk
/// verzameld, in plaats van pas op te duiken (~30s later) op het
/// ontvanger-scherm — wat verwarring geeft bij de dierbare.
///
/// Twee soorten stappen:
///  - **Kritiek voor bellen**: volledig scherm bij inkomend gesprek
///    (Android 14+, USE_FULL_SCREEN_INTENT) en batterij-optimalisatie
///    uitzetten. Zonder deze twee mist de dierbare oproepen.
///  - **Kritiek voor auto-answer**: SYSTEM_ALERT_WINDOW ("Weergeven
///    over andere apps"). Enige weg om een gesprek automatisch te
///    openen bij scherm-AAN + app-dicht (BAL-exemption). Alleen tonen
///    als [autoAnswerActief] true is — als auto-answer uitstaat, heeft
///    deze toestemming geen praktisch nut.
///
/// Cross-platform (Platform-principe uit CLAUDE.md): dit scherm doet
/// alleen Android-native aanroepen via KioskService en OverlayPermission-
/// Service, die zelf kIsWeb-guarded zijn. iOS krijgt in FASE G een
/// eigen scherm met CallKit/PushKit-stappen — de scaffold en tekst-
/// structuur zijn dan herbruikbaar, alleen de checks veranderen.
class ToestemmingenSetupScherm extends StatefulWidget {
  final bool autoAnswerActief;
  final VoidCallback onKlaar;

  const ToestemmingenSetupScherm({
    super.key,
    required this.autoAnswerActief,
    required this.onKlaar,
  });

  @override
  State<ToestemmingenSetupScherm> createState() =>
      _ToestemmingenSetupSchermState();
}

class _ToestemmingenSetupSchermState extends State<ToestemmingenSetupScherm>
    with WidgetsBindingObserver {
  bool? _fsiOk;
  bool? _battOk;
  bool? _overlayOk;
  bool _bezig = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ververs();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Bij terugkeer naar de app (na een systeem-instelling) opnieuw checken
  /// zodat de vinkjes automatisch omslaan. Werkt via WidgetsBindingObserver.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _ververs();
  }

  Future<void> _ververs() async {
    if (kIsWeb) {
      setState(() {
        _fsiOk = true;
        _battOk = true;
        _overlayOk = true;
      });
      return;
    }
    final fsi = await KioskService.kanFullScreenIntent();
    final batt = await KioskService.isBatteryOptimizationUit();
    final overlay = widget.autoAnswerActief
        ? await OverlayPermissionService.heeftToestemming()
        : true;
    if (!mounted) return;
    setState(() {
      _fsiOk = fsi;
      _battOk = batt;
      _overlayOk = overlay;
    });
  }

  bool get _allesOk =>
      (_fsiOk ?? false) && (_battOk ?? false) && (_overlayOk ?? true);

  int get _resterend {
    int r = 0;
    if (_fsiOk == false) r++;
    if (_battOk == false) r++;
    if (widget.autoAnswerActief && _overlayOk == false) r++;
    return r;
  }

  @override
  Widget build(BuildContext context) {
    return NormaalScaffold(
      backgroundColor: kCream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const Text('Nog even instellen zodat bellen goed werkt',
                  style: TextStyle(fontSize: 22,
                      fontWeight: FontWeight.w900, color: kBrown, height: 1.2)),
              const SizedBox(height: 8),
              Text(_resterend == 0
                      ? 'Alles is goed ingesteld — je kunt door.'
                      : 'Zet nog $_resterend puntje${_resterend == 1 ? "" : "s"} '
                          'aan zodat gesprekken en berichten altijd '
                          'aankomen bij je dierbare.',
                  style: const TextStyle(
                      fontSize: 14, color: kBrownLight, height: 1.4)),
              const SizedBox(height: 16),
              Expanded(child: ListView(children: [
                _stapKaart(
                  emoji: '📢',
                  titel: 'Volledig scherm bij een gesprek',
                  uitleg:
                      'Zodat een videogesprek groot in beeld komt — ook '
                      'als het scherm uit staat of vergrendeld is.',
                  status: _fsiOk,
                  knopTekst: 'Instelling openen',
                  onTap: () async {
                    await KioskService.vraagFullScreenIntent();
                  },
                ),
                const SizedBox(height: 12),
                _stapKaart(
                  emoji: '🔋',
                  titel: 'Batterij-optimalisatie uit',
                  uitleg:
                      'Android kan de app stiller zetten als hij denkt dat '
                      'de app "in slaap" is — dan mist je dierbare '
                      'berichten en gesprekken. Zet dit uit voor Ons '
                      'Moment.',
                  status: _battOk,
                  knopTekst: 'Zet uit',
                  onTap: () async {
                    await KioskService.vraagBatteryOptimizationUit();
                  },
                ),
                if (widget.autoAnswerActief) ...[
                  const SizedBox(height: 12),
                  _stapKaart(
                    emoji: '☎️',
                    titel: 'Automatisch opnemen mogelijk maken',
                    uitleg:
                        'Je hebt "automatisch opnemen" aangezet. Geef Ons '
                        'Moment nog één toestemming — "Weergeven over '
                        'andere apps" — zodat een gesprek écht vanzelf '
                        'opent, ook als de tablet net iets anders op het '
                        'scherm heeft.',
                    status: _overlayOk,
                    knopTekst: 'Instelling openen',
                    onTap: () async {
                      await OverlayPermissionService.vraagToestemming();
                    },
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kWhite,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kPeachLight),
                  ),
                  child: const Text(
                    'Kun je het nu niet? Later kun je dit altijd nog aanzetten '
                    'via Instellingen → "Zo werkt bellen".',
                    style: TextStyle(
                        fontSize: 12, color: kBrownLight, height: 1.5),
                  ),
                ),
              ])),
              const SizedBox(height: 12),
              Row(children: [
                TextButton(
                  onPressed: _bezig ? null : widget.onKlaar,
                  style: TextButton.styleFrom(foregroundColor: kBrownLight),
                  child: const Text('Later',
                      style: TextStyle(fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _bezig ? null : widget.onKlaar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _allesOk ? kGreen : kPeach,
                    foregroundColor: kWhite,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(_allesOk ? '✓ Klaar' : 'Verder',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stapKaart({
    required String emoji,
    required String titel,
    required String uitleg,
    required bool? status,
    required String knopTekst,
    required Future<void> Function() onTap,
  }) {
    final ok = status == true;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: ok ? kGreen : kPeachLight, width: ok ? 2 : 1.5),
        boxShadow: [BoxShadow(color: kPeach.withOpacity(0.05),
            blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(child: Text(titel, style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w800, color: kBrown))),
          if (ok)
            const Icon(Icons.check_circle, color: kGreen, size: 24)
          else
            const Icon(Icons.radio_button_unchecked,
                color: kPeachLight, size: 24),
        ]),
        const SizedBox(height: 8),
        Text(uitleg, style: const TextStyle(
            fontSize: 13, color: kBrownLight, height: 1.5)),
        if (!ok) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton(
              onPressed: _bezig ? null : () async {
                setState(() => _bezig = true);
                try {
                  await onTap();
                } finally {
                  if (mounted) setState(() => _bezig = false);
                }
                // Ververs kort na de intent-open — de gebruiker komt terug
                // via lifecycle-resumed, dat triggert al _ververs. Extra
                // check hier is een gordel: sommige OEM's fire de resume-
                // callback niet betrouwbaar op recent OS-versies.
                Timer(const Duration(seconds: 2), () {
                  if (mounted) _ververs();
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kPeach,
                foregroundColor: kWhite,
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(knopTekst,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ]),
    );
  }
}
