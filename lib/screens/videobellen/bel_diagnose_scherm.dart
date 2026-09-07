import 'dart:async';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../services/bel_log_service.dart';
import '../../services/full_screen_intent_service.dart';
import '../../services/push_service.dart';
import '../../theme/kleuren.dart';
import '../../widgets/normaal_scaffold.dart';

/// BEL-S3: dev-diagnose voor de inkomend-gesprek-melding.
///
/// Doel: op elk test-toestel in één oogopslag kunnen zien of de bel-
/// melding bij dichte app de juiste kant op kan (SDK-versie bekend,
/// FSI-toestemming aanwezig, notification-channel correct + niet door
/// user gedempt) zonder eerst een test-belletje te hoeven doen en
/// vervolgens te gokken wat er misgaat.
///
/// Geen productie-scherm — bereikbaar via de 🩺-knop in Instellingen
/// achter DEBUG_VIDEOBELLEN.
class BelDiagnoseScherm extends StatefulWidget {
  const BelDiagnoseScherm({super.key});

  @override
  State<BelDiagnoseScherm> createState() => _BelDiagnoseSchermState();
}

class _BelDiagnoseSchermState extends State<BelDiagnoseScherm> {
  bool _bezig = true;
  // Toestel
  int? _sdkVersion;
  String? _releaseNaam;
  String? _fabrikant;
  String? _model;
  // FSI
  bool? _fsiStatus; // null = onbekend
  // Channel
  bool _channelBestaat = false;
  String? _channelImportance;
  String? _channelSoundUri;
  bool? _channelVibratie;
  int? _channelBadgeAan;
  // BEL-S4: bel-events log
  List<String> _events = const <String>[];

  @override
  void initState() {
    super.initState();
    _laad();
  }

  Future<void> _laad() async {
    setState(() => _bezig = true);
    // Toestel-info
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      _sdkVersion = info.version.sdkInt;
      _releaseNaam = info.version.release;
      _fabrikant = info.manufacturer;
      _model = info.model;
    } catch (e) {
      debugPrint('⚠️ BEL-S3 diag: androidInfo faalde: $e');
    }
    // FSI
    _fsiStatus = await FullScreenIntentService.leesHuidigeStatus();
    // Channel
    await _leesChannel();
    // Events
    _events = await BelLogService.leesAlles();
    if (!mounted) return;
    setState(() => _bezig = false);
  }

  Future<void> _leesChannel() async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      final androidImpl = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final channels = await androidImpl?.getNotificationChannels() ?? [];
      final match = channels.firstWhere(
        (c) => c.id == PushService.gesprekChannelId,
        orElse: () => const AndroidNotificationChannel('', ''),
      );
      if (match.id.isEmpty) {
        _channelBestaat = false;
        return;
      }
      _channelBestaat = true;
      _channelImportance = match.importance.name;
      _channelSoundUri = match.sound?.sound;
      _channelVibratie = match.enableVibration;
      _channelBadgeAan = match.showBadge ? 1 : 0;
    } catch (e) {
      debugPrint('⚠️ BEL-S3 diag: getNotificationChannels faalde: $e');
    }
  }

  /// BEL-S4: knop-feedback voor "Prompt forceren". Als FSI al AAN staat,
  /// toon SnackBar in plaats van stil terug te keren (dat gaf de tester
  /// het idee dat de knop stuk was). Anders trigger forceerPromptVoorTest.
  Future<void> _promptForceren() async {
    final huidig = await FullScreenIntentService.leesHuidigeStatus();
    if (!mounted) return;
    if (huidig == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Toestemming staat al AAN — geen prompt nodig'),
        duration: Duration(seconds: 3),
      ));
      return;
    }
    await FullScreenIntentService.forceerPromptVoorTest(context);
    if (!mounted) return;
    await Future<void>.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    _laad();
  }

  Future<void> _wisEvents() async {
    await BelLogService.wisAlles();
    if (!mounted) return;
    setState(() => _events = const <String>[]);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Log gewist'),
      duration: Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return NormaalScaffold(
      backgroundColor: kCream,
      appBar: AppBar(
        title: const Text('Bel-melding diagnose',
            style: TextStyle(color: kBrown, fontWeight: FontWeight.w800)),
        backgroundColor: kCream,
        foregroundColor: kBrown,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Opnieuw ophalen',
            onPressed: _bezig ? null : _laad,
          ),
        ],
      ),
      body: _bezig
          ? const Center(child: CircularProgressIndicator(color: kPeach))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectie('Toestel'),
                _regel('Fabrikant', _fabrikant ?? '—'),
                _regel('Model', _model ?? '—'),
                _regel('Android-versie',
                    _releaseNaam == null ? '—' : 'Android $_releaseNaam'),
                _regel('SDK-versie',
                    _sdkVersion == null ? '—' : 'SDK $_sdkVersion'),
                _uitleg(
                  _sdkVersion == null
                      ? 'SDK-versie niet uitleesbaar.'
                      : _sdkVersion! >= 34
                          ? 'Android 14+ (SDK ≥ 34) — USE_FULL_SCREEN_INTENT '
                              'moet door gebruiker geactiveerd worden.'
                          : _sdkVersion! >= 31
                              ? 'Android 12–13 (SDK 31–33) — FSI standaard AAN. '
                                  'Als de melding tóch niet prominent verschijnt, '
                                  'ligt de oorzaak in het kanaal of in '
                                  'Android/OEM-instellingen (Doze, Sleeping apps, '
                                  'DND, geluidsprofiel).'
                              : 'Ouder dan Android 12 — FSI standaard AAN.',
                ),
                const SizedBox(height: 20),
                _sectie('Volledig-scherm-toestemming'),
                _regel(
                  'Status',
                  _fsiStatus == null
                      ? 'onbekend (plugin gaf geen bool)'
                      : (_fsiStatus! ? 'AAN' : 'UIT'),
                  waarde: _fsiStatus == null
                      ? kBrownLight
                      : (_fsiStatus! ? kGreen : kRood),
                ),
                _uitleg(_fsiStatus == false
                    ? 'Toestemming ontbreekt. Tik hieronder op '
                        '"Prompt forceren" om de warme dialog te tonen.'
                    : _fsiStatus == true
                        ? 'Toestemming staat aan — bel-meldingen mogen '
                            'volledig-scherm/full heads-up worden getoond.'
                        : 'Kon de status niet lezen; probeer opnieuw ophalen.'),
                const SizedBox(height: 8),
                _knop(
                  label: 'Prompt forceren',
                  icon: Icons.notification_important_rounded,
                  onTap: _promptForceren,
                ),
                const SizedBox(height: 20),
                _sectie('Bel-melding kanaal (${PushService.gesprekChannelId})'),
                _regel('Bestaat', _channelBestaat ? 'ja' : 'nee',
                    waarde: _channelBestaat ? kGreen : kRood),
                if (_channelBestaat) ...[
                  _regel('Importance (systeem)',
                      _channelImportance ?? '—'),
                  _regel('Geluid',
                      _channelSoundUri == null || _channelSoundUri!.isEmpty
                          ? 'STIL (of niet gezet)'
                          : _channelSoundUri!,
                      waarde: (_channelSoundUri ?? '').isEmpty ? kRood : kGreen),
                  _regel('Vibratie',
                      _channelVibratie == null
                          ? '—'
                          : (_channelVibratie! ? 'aan' : 'uit')),
                  _regel('Badge tonen',
                      _channelBadgeAan == null
                          ? '—'
                          : (_channelBadgeAan == 1 ? 'aan' : 'uit')),
                ],
                _uitleg(
                  !_channelBestaat
                      ? 'Kanaal is nog niet aangemaakt — open de app een keer '
                          'volledig zodat PushService.initApp draait.'
                      : (_channelImportance == 'low' ||
                              _channelImportance == 'min' ||
                              _channelImportance == 'none' ||
                              (_channelSoundUri ?? '').isEmpty)
                          ? 'Kanaal is door de gebruiker of het systeem '
                              'aangepast (importance verlaagd of geluid '
                              'uitgezet). Reset: Instellingen → App → '
                              'Meldingen → "Inkomend gesprek" → herstel '
                              'importance op "Urgent" en geluid.'
                          : 'Kanaal ziet er goed uit — bij dichte app zou '
                              'de melding prominent én met marimba moeten '
                              'binnenkomen. Als dat niet gebeurt: check DND, '
                              'geluidsprofiel, Doze/battery-optimalisatie.',
                ),
                const SizedBox(height: 20),
                _sectie('Laatste bel-events (nieuwste onderaan)'),
                _uitleg(
                  'Doe één test-belletje bij dichte app en tik dan de '
                  'refresh-knop rechtsboven. Als hier "FCM inkomend_gesprek '
                  'binnen" én "_toonGesprekNotificatie" verschijnen: de '
                  'code draaide — dan is de melding een presentatie-probleem. '
                  'Als er NIETS staat na een test-belletje: Android/OEM '
                  'blokkeert de achtergrond-code (Doze / Slapende apps).',
                ),
                const SizedBox(height: 8),
                if (_events.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: kWhite,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kBrownLight.withOpacity(0.3)),
                    ),
                    child: const Text(
                      '— leeg — nog geen events opgeslagen',
                      style: TextStyle(color: kTextMuted, fontSize: 12),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kWhite,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kBrownLight.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final e in _events)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: SelectableText(
                              e,
                              style: const TextStyle(
                                  color: kBrown,
                                  fontSize: 11.5,
                                  fontFamily: 'monospace'),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: _wisEvents,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Wis log'),
                    style: TextButton.styleFrom(foregroundColor: kBrownLight),
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    'Diagnose ${DateTime.now().toIso8601String().substring(11, 19)}',
                    style: const TextStyle(color: kTextMuted, fontSize: 11),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sectie(String tekst) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(tekst.toUpperCase(),
            style: const TextStyle(color: kBrown,
                fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.6)),
      );

  Widget _regel(String label, String value, {Color? waarde}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Text(label,
                  style: const TextStyle(color: kBrownLight, fontSize: 13)),
            ),
            Expanded(
              flex: 6,
              child: Text(value,
                  style: TextStyle(
                      color: waarde ?? kBrown,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                  textAlign: TextAlign.right),
            ),
          ],
        ),
      );

  Widget _uitleg(String tekst) => Padding(
        padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
        child: Text(tekst,
            style: const TextStyle(color: kTextMuted,
                fontSize: 12, height: 1.35)),
      );

  Widget _knop({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) =>
      ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        style: ElevatedButton.styleFrom(
          backgroundColor: kPeach,
          foregroundColor: kWhite,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      );
}
