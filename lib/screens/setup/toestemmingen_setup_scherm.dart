import 'dart:async';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../data/bel_uitleg_teksten.dart';
import '../../services/apparaat_service.dart';
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
  bool? _perAppBattOk;
  bool? _spaarstandUit;
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

  /// CHECKLIST-MODUS (14 sept 2026): rustige modus (vergrendeld) draait
  /// de app permanent op de voorgrond via Screen Pinning. Daardoor:
  ///   - Volledig scherm bij gesprek → niet nodig, de app IS al
  ///     zichtbaar wanneer een gesprek binnenkomt.
  ///   - Overlay (auto-answer via BAL-exemption) → niet nodig, app is
  ///     al voorgrond → FCM-foreground pad publiceert direct naar
  ///     incomingCallNotifier zonder background-activity-start.
  ///   - Meldingen (POST_NOTIFICATIONS) → niet nodig, moment-popups
  ///     komen direct via Firestore-listener in-app; er is geen
  ///     tray-melding om te tonen.
  /// Wat WEL nodig blijft in rustige modus:
  ///   - Batterij-optimalisatie uit — Android kan de app zelfs op de
  ///     voorgrond in Doze zetten na langere inactiviteit; dan mist
  ///     de dierbare een moment. Zonder deze uitzondering wordt de
  ///     Firestore-listener geknepen.
  ///   - Autostart (Samsung/Xiaomi/etc) — na reboot of stroomuitval
  ///     moet Ons Moment terugkomen op de voorgrond zonder dat de
  ///     eigenaar erbij hoeft. Op Pixel/stock Android niet relevant
  ///     (blokkerende OEM-check gate).
  bool get _isRustig =>
      widget.weergaveModus == DeviceModusService.VERGRENDELD;

  bool get _fsiStapNodig => !_isRustig;
  bool get _notifStapNodig => !_isRustig;
  bool get _overlayStapNodig => widget.autoAnswerActief && !_isRustig;

  Future<void> _ververs() async {
    final mijnTicket = ++_verversTicket;
    if (kIsWeb) {
      if (mijnTicket != _verversTicket) return;
      setState(() {
        _fsiOk = true;
        _battOk = true;
        _perAppBattOk = true;
        _spaarstandUit = true;
        _overlayOk = true;
        _notifOk = true;
        _autostartOk = true;
        _oemHeeftAutostart = false;
      });
      return;
    }
    // CHECKLIST-MODUS: stappen die in rustige modus niet nodig zijn,
    // slaan we ook over in de fysieke check — hun bool wordt true zodat
    // _allesOk/_resterend/belGereed hen niet als 'ontbrekend' tellen.
    // De UI verbergt de betreffende kaartjes; de warme uitleg bovenaan
    // vertelt de eigenaar waarom er maar 2 stappen zijn.
    final fsi = _fsiStapNodig
        ? await KioskService.kanFullScreenIntent()
        : true;
    final batt = await KioskService.isBatteryOptimizationUit();
    // P3 (14 sept 2026): losse sub-checks zodat we in de UI kunnen
    // uitleggen WELKE van de twee (per-app whitelist of spaarstand)
    // nog aan-staat. isBatteryOptimizationUit() is de samengestelde
    // check (beide moeten uit); de losse checks vertellen ons welke
    // reparatie-instructie te tonen.
    final perAppBatt = await KioskService.isPerAppBatteryOptimizationUit();
    final spaarstand = await KioskService.isSpaarstandUit();
    final overlay = _overlayStapNodig
        ? await OverlayPermissionService.heeftToestemming()
        : true;
    final notif = _notifStapNodig
        ? await StroomuitvalService.notificatieToegestaan()
        : true;
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
      _perAppBattOk = perAppBatt;
      _spaarstandUit = spaarstand;
      _overlayOk = overlay;
      _notifOk = notif;
      _oemHeeftAutostart = oemNodig;
      _autostartOk = autostart;
    });
    // DEEL B (13 sept 2026): sync bel-gereedheid naar apparaat-doc zodat
    // de familie-kant just-in-time kan waarschuwen als een ontvanger
    // niet gereed is. Fire-and-forget — een Firestore-hik hier mag de
    // UI niet blokkeren. Voorwaarde-set is IDENTIEK aan _allesOk (elke
    // stap die visueel groen moet zijn), zodat "checklist compleet in
    // UI" één-op-één matcht met "belGereed=true op server".
    await _syncBelGereedNaarFirestore(
      fsi: fsi, batt: batt, overlay: overlay,
      notif: notif, oemNodig: oemNodig, autostart: autostart,
    );
  }

  Future<void> _syncBelGereedNaarFirestore({
    required bool fsi,
    required bool batt,
    required bool overlay,
    required bool notif,
    required bool oemNodig,
    required bool autostart,
  }) async {
    if (kIsWeb) return;
    // CHECKLIST-MODUS: 'gereed' bevat alleen de checks die in de
    // huidige modus WEL van toepassing zijn. In rustige modus is dat
    // alleen batterij + autostart. Zonder deze gates zou de eigenaar-
    // kant een 'niet bel-klaar'-melding zien voor stappen die op de
    // ontvanger-tablet niet nodig zijn (bijv. Volledig scherm in de
    // vergrendelde modus). fsi/overlay/notif zijn in _ververs al op
    // 'true' gezet voor niet-relevante stappen, dus deze berekening is
    // idempotent bij later toe- of afvoegen van gates.
    final gereed = (_fsiStapNodig ? fsi : true) && batt &&
        (_overlayStapNodig ? overlay : true) &&
        (_notifStapNodig ? notif : true) &&
        (!oemNodig || autostart);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      final apparaatId = await DeviceModusService.krijgApparaatId();
      if (apparaatId.isEmpty) return;
      await ApparaatService.zetBelGereed(
        familieUid: uid,
        apparaatId: apparaatId,
        gereed: gereed,
      );
    } catch (_) {}
  }

  /// CHECKLIST-MODUS: stap-nodig-gates verbergen niet-relevante stappen
  /// uit de telling. Rustige modus telt alleen batterij + autostart.
  bool get _allesOk =>
      (_fsiStapNodig ? (_fsiOk ?? false) : true) &&
      (_battOk ?? false) &&
      (_overlayStapNodig ? (_overlayOk ?? false) : true) &&
      (_notifStapNodig ? (_notifOk ?? false) : true) &&
      (_autostartOk ?? true);

  int get _resterend {
    int r = 0;
    if (_fsiStapNodig && _fsiOk == false) r++;
    if (_battOk == false) r++;
    if (_overlayStapNodig && _overlayOk == false) r++;
    if (_notifStapNodig && _notifOk == false) r++;
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
              // CHECKLIST-MODUS (14 sept 2026): rustige modus toont maar
              // 2 stappen omdat de andere in kiosk-mode niet nodig zijn.
              // Uitleg-kaart bovenaan zodat de eigenaar niet denkt dat er
              // stappen ontbreken.
              if (_isRustig) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kPeachPale,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kPeach, width: 1.2),
                  ),
                  child: const Row(children: [
                    Text('🔒', style: TextStyle(fontSize: 22)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Omdat het apparaat vast op Ons Moment staat, '
                        'zijn maar twee instellingen nodig.',
                        style: TextStyle(fontSize: 13, color: kBrown,
                            height: 1.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              Expanded(child: ListView(children: [
                if (_fsiStapNodig) ...[
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
                    fallbackInstructie:
                        'Werkt de knop niet? Ga naar Instellingen → Apps → '
                        'Ons Moment → Meldingen → "Volledig scherm bij '
                        'melding" en zet aan.',
                  ),
                  const SizedBox(height: 12),
                ],
                // P3 (14 sept 2026): batterij-stap toont nu welke van de
                // twee onderliggende instellingen aan-staat (whitelist of
                // spaarstand). _battOk is de samenvatting; als NIET ok
                // gebruiken we de sub-status om de juiste tekst + knop
                // te tonen. Bij spaarstand aan: knop opent Instellingen
                // → Batterij (algemeen), want er is geen direct-intent
                // om spaarstand uit te schakelen (Android-limitatie).
                _stapKaart(
                  emoji: '🔋',
                  titel: _battOk == false && _spaarstandUit == false
                      ? 'Spaarstand uitzetten'
                      : 'Batterij-optimalisatie uit',
                  uitleg: _battOk == false && _spaarstandUit == false
                      ? 'De Spaarstand van je apparaat staat AAN. In deze '
                        'stand mag Ons Moment niet vrij op de achtergrond '
                        'werken — je dierbare mist berichten en gesprekken '
                        'terwijl de app "in slaap" wordt gezet. Zet de '
                        'Spaarstand uit in de instellingen van je apparaat '
                        '(meestal onder Batterij).'
                      : 'Je apparaat kan de app stiller zetten als hij denkt '
                        'dat de app "in slaap" is — dan mist je dierbare '
                        'berichten en gesprekken. Zet dit uit voor Ons '
                        'Moment.',
                  status: _battOk,
                  knopTekst: _battOk == false && _spaarstandUit == false
                      ? 'Open Batterij-instellingen'
                      : 'Zet uit',
                  onTap: () async {
                    // Twee gescheiden acties op basis van welke van
                    // de twee sub-checks NIET ok is. Als beide niet-ok
                    // zijn, doen we eerst de per-app-exempt (die opent
                    // een dialog); user pakt spaarstand daarna zelf op.
                    if (_perAppBattOk == false) {
                      await KioskService.vraagBatteryOptimizationUit();
                    } else {
                      // Alleen spaarstand aan: open de algemene batterij-
                      // instellingen. Er is geen publieke Android-intent
                      // om spaarstand direct uit te zetten — de gebruiker
                      // ziet daar zelf de schakelaar.
                      await StroomuitvalService.openBatterijInstellingen();
                    }
                  },
                  fallbackInstructie: _battOk == false
                      && _spaarstandUit == false
                      ? 'Werkt de knop niet? Ga naar Instellingen → '
                        'Batterij → Spaarstand en zet uit.'
                      : 'Werkt de knop niet? Ga naar Instellingen → '
                        'Apps → Ons Moment → Batterij → kies '
                        '"Onbeperkt".',
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
                    fallbackInstructie:
                        'Werkt de knop niet? Ga naar Instellingen → '
                        'Apps → Speciale toegang → "Weergeven over '
                        'andere apps" → zoek Ons Moment en zet aan.',
                  ),
                ],
                // C-1-vervolg: POST_NOTIFICATIONS (Android 13+). Zonder
                // dit komt geen enkele melding aan — niet voor
                // gesprekken, niet voor momenten. CHECKLIST-MODUS:
                // niet nodig in rustige modus; moment-popups komen
                // dan via de Firestore-listener in-app.
                if (_notifStapNodig) ...[
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
                      // Q3 (14 sept 2026): vraagNotificatieToestemming detecteert
                      // permanent-denied en opent dan meteen de meldingsinstellingen
                      // via de KioskService method-channel. Zonder die detectie
                      // deed .request() niks op een 'don't ask again'-toestel.
                      await StroomuitvalService.vraagNotificatieToestemming();
                    },
                    fallbackInstructie:
                        'Werkt de knop niet? Ga naar Instellingen → '
                        'Apps → Ons Moment → Meldingen en zet aan.',
                  ),
                ],
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
    // Q1-Q3 (14 sept 2026): warme fallback-instructie die getoond wordt
    // ONDER de 'openen'-knop. User kan zo altijd zelf naar de juiste
    // plek navigeren als een merk-specifieke Activity is hernoemd of
    // exported=false is gezet. Alleen zichtbaar als de stap NIET-ok is.
    String? fallbackInstructie,
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
          if (fallbackInstructie != null) ...[
            const SizedBox(height: 10),
            Text(fallbackInstructie,
                style: const TextStyle(fontSize: 12, color: kBrown,
                    height: 1.5, fontStyle: FontStyle.italic)),
          ],
        ],
      ]),
    );
  }
}
