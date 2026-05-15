import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Beheert de "modus" van dit specifieke apparaat:
/// - 'familie' = familie portaal (Sturen, Agenda, Notities, Instellingen)
/// - 'ontvanger' = ontvanger kiosk (alleen popups en home)
/// - null = nog niet ingesteld (toon keuzescherm)
///
/// Op web werkt dit via localStorage. Op mobiel via SharedPreferences.
/// Per apparaat opgeslagen — dezelfde Firebase Auth account kan op het ene
/// apparaat als familie ingelogd zijn en op het andere als ontvanger.
class DeviceModusService {
  static const String _key = 'ons_moment_device_modus';
  static const String FAMILIE = 'familie';
  static const String ONTVANGER = 'ontvanger';

  /// Reactief gepubliceerde modus — wordt door [get], [zet] en [wis]
  /// up-to-date gehouden zodat de UI zonder polling kan reageren.
  static final ValueNotifier<String?> notifier = ValueNotifier<String?>(null);

  /// Lees huidige modus uit storage en publiceer naar [notifier]. Null als nog niet ingesteld.
  static Future<String?> get() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final waarde = prefs.getString(_key);
      final resultaat = (waarde == FAMILIE || waarde == ONTVANGER) ? waarde : null;
      notifier.value = resultaat;
      return resultaat;
    } catch (_) {
      return null;
    }
  }

  /// Zet de modus voor dit apparaat. Geeft true als geslaagd.
  static Future<bool> zet(String modus) async {
    if (modus != FAMILIE && modus != ONTVANGER) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ok = await prefs.setString(_key, modus);
      if (ok) notifier.value = modus;
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Wis de modus (bij uitloggen of bewust wisselen).
  static Future<void> wis() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
      notifier.value = null;
    } catch (_) {}
  }
}
