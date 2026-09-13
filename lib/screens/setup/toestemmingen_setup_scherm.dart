import 'dart:async';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../data/bel_uitleg_teksten.dart';
import '../../services/device_modus_service.dart';
import '../../services/kiosk_service.dart';
import '../../services/overlay_permission_service.dart';
import '../../services/stroomuitval_service.dart';
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
  /// BEL-D3: [DeviceModusService.VERGRENDELD] of [MELDINGEN]. In
  /// VERGRENDELDE modus staat het apparaat vast op Ons Moment; de
  /// overlay-toestemming is dan overbodig — die stap wordt overgeslagen.
  final String weergaveModus;
  final VoidCallback onKlaar;

  const ToestemmingenSetupScherm({
    super.key,
    required this.autoAnswerActief,
    required this.weergaveModus,
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
  bool? _notifOk;
  bool? _autostartOk;
  bool _oemHeeftAutostart = false;
  bool _bezig = false;
  // P2 (13 sept 2026): race-guard voor _ververs. Als lifecycle-resumed
  // snel na elkaar tweemaal fired (bekend Android-gedrag na systeem-
  // instellingen), lopen twee _ververs-calls parallel; de tweede kan de
  // eerste setState overschrijven met verouderde waarden. Ticket-check
  // zorgt dat alleen de meest-recente ververs de state mag updaten.
  int _verversTicket = 0;

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

  /// BEL-D3: overlay-stap alleen relevant bij MELDINGEN-modus met
  /// autoAnswer aan. Bij VERGRENDELDE modus staat het apparaat vast op
  /// Ons Moment en werkt automatisch opnemen altijd — geen extra
  /// toestemming nodig, en dus geen kaartje tonen.
  bool get _overlayStapNodig =>
      widget.autoAnswerActief &&
      widget.weergaveModus != DeviceModusService.VERGRENDELD;

  Future<void> _ververs() async {
    final mijnTicket = ++_verversTicket;
    if (kIsWeb) {
      if (mijnTicket != _verversTicket) return;
      setState(() {
        _fsiOk = true;
        _battOk = true;
        _overlayOk = true;
        _notifOk = true;
        _autostartOk = true;
        _oemHeeftAutostart = false;
      });
      return;
    }
    final fsi = await KioskService.kanFullScreenIntent();
    final batt = await KioskService.isBatteryOptimizationUit();
    final overlay = _overlayStapNodig
        ? await OverlayPermissionService.heeftToestemming()
        : true;
    final notif = await StroomuitvalService.notificatieToegestaan();
    final oemNodig = await StroomuitvalService.isBlokkerendeOem();
    final autostart = oemNodig
        ? await StroomuitvalService.autostartAttested()
        : true;
    // P2: race-guard. Als er intussen een nieuwere _ververs is gestart
    // (bijv. door een tweede resumed-event), verwerpen we deze.
    if (mijnTicket != _verversTicket || !mounted) return;
    setState(() {
      _fsiOk = fsi;
      _battOk = batt;
      _overlayOk = overlay;
      _notifOk = notif;
      _oemHeeftAutostart = oemNodig;
      _autostartOk = autostart;
    });
  }

  bool get _allesOk =>
      (_fsiOk ?? false) &&
      (_battOk ?? false) &&
      (_overlayOk ?? true) &&
      (_notifOk ?? false) &&
      (_autostartOk ?? true);

  int get _resterend {
    int r = 0;
    if (_fsiOk == false) r++;
    if (_battOk == false) r++;
    if (_overlayStapNodig && _overlayOk == false) r++;
    if (_notifOk == false) r++;
    if (_oemHeeftAutostart && _autostartOk == false) r++;
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
                      'als het scherm uit is.',
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
                      'Je apparaat kan de app stiller zetten als hij denkt '
                      'dat de app "in slaap" is — dan mist je dierbare '
                      'berichten en gesprekken. Zet dit uit voor Ons '
                      'Moment.',
                  status: _battOk,
                  knopTekst: 'Zet uit',
                  onTap: () async {
                    await KioskService.vraagBatteryOptimizationUit();
                  },
                ),
                if (_overlayStapNodig) ...[
                  const SizedBox(height: 12),
                  _stapKaart(
                    emoji: '☎️',
                    titel: 'Automatisch opnemen mogelijk maken',
                    // BEL-D3: twee korte zinnen (waarvoor + zonder), uit
                    // BelUitlegTeksten zodat de tekst hier gelijk is aan
                    // de dialog en de FAQ.
                    uitleg:
                        '${BelUitlegTeksten.overlayWaarvoor}\n\n'
                        '${BelUitlegTeksten.overlayZonder}',
                    status: _overlayOk,
                    knopTekst: 'Instelling openen',
                    onTap: () async {
                      await OverlayPermissionService.vraagToestemming();
                    },
                  ),
                ],
                // C-1-vervolg: POST_NOTIFICATIONS (Android 13+). Zonder
                // dit komt geen enkele melding aan — niet voor
                // gesprekken, niet voor momenten.
                const SizedBox(height: 12),
                _stapKaart(
                  emoji: '🔔',
                  titel: 'Meldingen aan',
                  uitleg:
                      'Zet meldingen aan, zodat berichten en gesprekken '
                      'altijd bij je dierbare aankomen. Zonder dit '
                      'blijft het scherm stil, ook als er een moment of '
                      'oproep binnenkomt.',
                  status: _notifOk,
                  knopTekst: 'Zet aan',
                  onTap: () async {
                    await StroomuitvalService.vraagNotificatieToestemming();
                  },
                ),
                // C-1-vervolg: OEM-autostart (alleen Samsung/Xiaomi/
                // Huawei/Oppo/Vivo/Realme). Op Pixel/stock Android
                // wordt deze stap OVERGESLAGEN — geen verwarrende
                // vinkje voor een instelling die daar niet bestaat.
                if (_oemHeeftAutostart) ...[
                  const SizedBox(height: 12),
                  _autostartKaart(),
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

  /// C-1-vervolg: OEM-autostart-kaart met TWEE knoppen. Android geeft
  /// geen publieke API om autostart-status te lezen; we vragen de
  /// eigenaar zelf te bevestigen dat 'ie het heeft aangezet. Bij
  /// tik op "Ik heb het aangezet" slaan we dat op in prefs (user-
  /// attested) en verdwijnt de stap.
  Widget _autostartKaart() {
    final ok = _autostartOk == true;
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
          const Text('🔄', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          const Expanded(child: Text('Automatisch opstarten',
              style: TextStyle(fontSize: 15,
                  fontWeight: FontWeight.w800, color: kBrown))),
          // P2 (13 sept 2026): user-attested badge visueel duidelijk
          // anders dan systeem-geverifieerd. Systeem-checks tonen een
          // strak groen check-icoon; hier een pill-badge "Door jou
          // bevestigd" met kPeach — user weet dat Android dit niet zelf
          // kan verifieren en dat hij zelf heeft aangevinkt.
          if (ok)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: kPeachPale,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kPeach, width: 1),
              ),
              child: const Text('Door jou bevestigd',
                  style: TextStyle(fontSize: 10,
                      color: kBrown, fontWeight: FontWeight.w700)),
            )
          else
            const Icon(Icons.radio_button_unchecked,
                color: kPeachLight, size: 24),
        ]),
        const SizedBox(height: 8),
        const Text(
          "Zet 'automatisch opstarten' aan. Zo komt Ons Moment vanzelf "
          'terug als de tablet opnieuw opstart — bijvoorbeeld na een '
          'stroomstoring. Zonder dit zou het scherm van je dierbare '
          'leeg blijven tot je er zelf bij bent.',
          style: TextStyle(fontSize: 13, color: kBrownLight, height: 1.5),
        ),
        if (!ok) ...[
          const SizedBox(height: 10),
          // P3 (13 sept 2026): merk-specifieke instructie. Bepaald door
          // Codemagic-build op basis van device_info_plus.manufacturer;
          // gerenderd via een FutureBuilder omdat het async is.
          FutureBuilder<String>(
            future: StroomuitvalService.isBlokkerendeOem().then((_) async {
              // Herbepaal merk (zelfde call die openOemAutostartInstellingen
              // straks doet) zodat de instructie 1-op-1 matcht.
              try {
                final info = await DeviceInfoPlugin().androidInfo;
                return info.manufacturer.toLowerCase().trim();
              } catch (_) {
                return 'onbekend';
              }
            }),
            builder: (ctx, snap) {
              final merk = snap.data ?? 'onbekend';
              return Text(
                StroomuitvalService.instructiePerOem(merk),
                style: const TextStyle(fontSize: 12, color: kBrown,
                    height: 1.5, fontStyle: FontStyle.italic),
              );
            },
          ),
          const SizedBox(height: 12),
          Row(children: [
            OutlinedButton(
              onPressed: _bezig ? null : () async {
                setState(() => _bezig = true);
                try {
                  await StroomuitvalService.openOemAutostartInstellingen();
                } finally {
                  if (mounted) setState(() => _bezig = false);
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: kBrown,
                side: const BorderSide(color: kPeach, width: 1.5),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Instelling openen',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: _bezig ? null : () async {
                await StroomuitvalService.markeerAutostartGedaan();
                if (mounted) await _ververs();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kPeach,
                foregroundColor: kWhite,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Ik heb het aangezet',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800)),
            ),
          ]),
        ],
      ]),
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
