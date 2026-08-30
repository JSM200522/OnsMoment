import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/debug_flags.dart';

/// 3-laags feature-flag voor Optie B (ConnectionService/CallKit).
///
/// Beslislogica (in volgorde):
///   1. `CALLKIT_HARD_UIT` (compile-time in debug_flags.dart) → true = FALSE
///      Bedoeld als noodrem in de source; vereist wel een build.
///   2. Lokale SharedPreferences-override (dev-toggle in Instellingen) →
///      als niet-null, wint van remote. Handig voor testers zonder
///      Firebase-Console-toegang; per-toestel effectief bij volgende
///      isEnabled()-lookup (in de praktijk: bij volgende bel).
///   3. Remote Firestore-flag `config/features.callkitEnabled` →
///      standaard false; aan/uit via Firebase Console zonder build.
///      Result wordt gecached in memory tot [_cache] wordt geïnvalideerd.
///
/// **Fail-soft**: elke fout (netwerk, plugin, permission-denied) →
/// return false. Optie A blijft dan de bel-flow dragen. Geen throw naar
/// caller, geen crash.
///
/// **kIsWeb**: op web altijd false (plugin heeft geen web-support).
class CallkitFlagService {
  CallkitFlagService._();

  static const String _prefsKey = 'callkit_lokale_override';
  static const String _remoteDocPad = 'config';
  static const String _remoteDocId = 'features';
  static const String _remoteVeld = 'callkitEnabled';

  /// In-memory cache. `null` = nog niet geladen; bool = laatst effectieve
  /// waarde. Wordt geset door de eerste isEnabled()-call na app-init.
  static bool? _cache;

  /// Reset de in-memory cache — volgende isEnabled() haalt opnieuw op.
  /// Aanroepen na dev-toggle of remote-wijziging als de tester direct
  /// een verse waarde wil zonder app-restart.
  static void invalideerCache() {
    _cache = null;
  }

  /// Hoofd-check. Nooit throwt, altijd bool. Gebruikt caching zodat
  /// een bel-flow geen extra Firestore-read triggert.
  static Future<bool> isEnabled() async {
    if (_cache != null) return _cache!;
    final val = await _bepaalWaarde();
    _cache = val;
    return val;
  }

  /// Synchrone read van de gecachede waarde. Retourneert `false` als
  /// er nog geen cache is — gebruikt in hot-paths waar await onmogelijk
  /// is (bijv. tijdens sync guard-checks). De async isEnabled() wordt
  /// idealiter vroeg in de app-init gedaan zodat de cache er staat.
  static bool isEnabledSync() => _cache ?? false;

  static Future<bool> _bepaalWaarde() async {
    // Laag 1 — compile-time kill-switch (highest priority)
    if (CALLKIT_HARD_UIT) return false;
    if (kIsWeb) return false;

    // Laag 2 — lokale dev-override
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_prefsKey)) {
        return prefs.getBool(_prefsKey) ?? false;
      }
    } catch (_) {
      // SharedPreferences init faalt zelden; fail-soft door naar remote.
    }

    // Laag 3 — remote Firestore-flag
    try {
      final snap = await FirebaseFirestore.instance
          .collection(_remoteDocPad)
          .doc(_remoteDocId)
          .get();
      if (!snap.exists) return false;
      final data = snap.data();
      if (data == null) return false;
      final waarde = data[_remoteVeld];
      return waarde is bool ? waarde : false;
    } catch (e) {
      debugPrint('☎️ CallkitFlagService: remote-flag lezen faalde '
          '(fail-soft naar OFF): $e');
      return false;
    }
  }

  // ── Lokale dev-override API (voor verborgen toggle in Instellingen) ──

  /// Leest de lokale override. `null` = geen override, remote bepaalt.
  static Future<bool?> leesLokaleOverride() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(_prefsKey)) return null;
      return prefs.getBool(_prefsKey);
    } catch (_) {
      return null;
    }
  }

  /// Zet de lokale override (true/false) en invalideer de cache zodat
  /// de volgende isEnabled() de nieuwe waarde teruggeeft.
  static Future<void> zetLokaleOverride(bool waarde) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, waarde);
      invalideerCache();
    } catch (_) {}
  }

  /// Wist de lokale override. Volgende isEnabled() valt terug op remote.
  static Future<void> wisLokaleOverride() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
      invalideerCache();
    } catch (_) {}
  }
}
