import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// BEL-S4: persistente rollende log voor bel-pad-events zodat je bij
/// dichte-app-tests kunt aflezen of het achtergrond-pad daadwerkelijk
/// loopt. Zonder deze log zit alle bel-flow-diagnose in `debugPrint` en
/// is dus alleen via ADB/Android Studio zichtbaar — bij een killed-app-
/// test onbruikbaar.
///
/// Gebruik:
///   await BelLogService.log('FCM inkomend gesprek binnen');
///
/// Wat er onder de motorkap gebeurt:
///  - Rollende buffer van [_maxEvents] entries in SharedPreferences.
///  - Elke entry is `HH:mm:ss.SSS $tekst` — genoeg om orde vast te
///    stellen zonder ISO-parsing.
///  - `SharedPreferences` werkt CROSS-ISOLATE, dus zowel het
///    achtergrond-FCM-isolate als het main-isolate schrijven naar
///    dezelfde onderliggende opslag. Er is een minieme race als twee
///    calls exact tegelijk gebeuren (één kan een add van de andere
///    overschrijven) — voor een dev-log acceptabel.
///  - Fail-soft op alles. Nooit throw uit een log-aanroep. Als de write
///    faalt (opslag vol, permissie), verliezen we die entry — nooit de
///    aanroepende flow.
///
/// Niet voor productie-releases bedoeld. Bereikbaar via het
/// BelDiagnoseScherm achter `DEBUG_VIDEOBELLEN`.
class BelLogService {
  BelLogService._();

  static const String _prefKey = 'bel_events_log_v1';
  static const int _maxEvents = 40;

  /// Voeg één regel toe. Silent fail-soft — nooit throw.
  static Future<void> log(String event) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entry = '${_tijdstempel()} $event';
      final list = prefs.getStringList(_prefKey) ?? <String>[];
      list.add(entry);
      if (list.length > _maxEvents) {
        list.removeRange(0, list.length - _maxEvents);
      }
      await prefs.setStringList(_prefKey, list);
      debugPrint('📝 BEL-S4 log: $entry');
    } catch (e) {
      debugPrint('⚠️ BEL-S4 log faalde: $e');
    }
  }

  /// Leest de huidige buffer terug (oudste eerst, nieuwste laatst).
  /// Fail-soft naar leeg lijst.
  static Future<List<String>> leesAlles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_prefKey) ?? <String>[];
    } catch (_) {
      return <String>[];
    }
  }

  /// Wist de volledige buffer. Fail-soft.
  static Future<void> wisAlles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
      debugPrint('📝 BEL-S4 log gewist');
    } catch (_) {}
  }

  static String _tijdstempel() {
    final n = DateTime.now();
    return '${_p2(n.hour)}:${_p2(n.minute)}:${_p2(n.second)}'
        '.${_p3(n.millisecond)}';
  }

  static String _p2(int n) => n.toString().padLeft(2, '0');
  static String _p3(int n) => n.toString().padLeft(3, '0');
}
