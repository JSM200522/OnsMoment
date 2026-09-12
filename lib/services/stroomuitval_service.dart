import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// C-1-vervolg (12 sept 2026) — "stroomuitval-proof" checks + best-
/// effort deep-links voor de setup-checklist.
///
/// - POST_NOTIFICATIONS (Android 13+): status + prompt via
///   permission_handler.
/// - OEM-detectie: manufacturer via device_info_plus. Alleen op
///   blokkerende OEM's (Samsung, Xiaomi/Redmi, Huawei/Honor, Oppo,
///   Vivo, Realme) is autostart nodig — Pixel/stock Android hoeft niet.
/// - User-attested vinkje voor autostart in SharedPreferences (want
///   Android biedt geen publieke API om te lezen of autostart aan
///   staat). De eigenaar tikt zelf "Ik heb het aangezet" nadat hij de
///   OEM-instelling heeft geopend.
class StroomuitvalService {
  static const _kAutostartAttestedKey =
      'stroomuitval_autostart_attested_v1';

  /// Merken waar autostart handmatig aangezet moet worden. Pixel en
  /// stock Android hebben deze restrictie niet. iOS/iPad krijgt in
  /// FASE G een eigen scherm — deze service is Android-only via de
  /// kIsWeb-guard.
  static const _blokkerendeOems = <String>{
    'samsung', 'xiaomi', 'redmi', 'huawei', 'honor',
    'oppo', 'vivo', 'realme',
  };

  static Future<bool> notificatieToegestaan() async {
    if (kIsWeb) return true;
    try {
      final status = await Permission.notification.status;
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> vraagNotificatieToestemming() async {
    if (kIsWeb) return true;
    try {
      final status = await Permission.notification.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// True als het toestel van een merk is dat autostart-management heeft
  /// (Samsung/Xiaomi/etc). Op Pixel/stock Android en iOS: false → stap
  /// wordt in de UI overgeslagen. Fail-safe naar false zodat we bij
  /// twijfel geen verwarrende stap tonen.
  static Future<bool> isBlokkerendeOem() async {
    if (kIsWeb) return false;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final merk = info.manufacturer.toLowerCase().trim();
      return _blokkerendeOems.contains(merk);
    } catch (_) {
      return false;
    }
  }

  /// Best-effort: open OEM-instellingen. Op onbetrouwbare/nieuwe MIUI-
  /// versies faalt de specifieke intent — dan valt permission_handler
  /// terug op de app-info-page. Beide zijn 'in de buurt' van de juiste
  /// setting; user krijgt in de UI extra tekst-instructie.
  static Future<void> openOemAutostartInstellingen() async {
    if (kIsWeb) return;
    try {
      // openAppSettings gaat naar Android's app-info-scherm — vandaar
      // klikt de gebruiker één keer door naar batterij/autostart. Meer
      // gerichte deep-links (bijv. com.miui.permcenter.autostart.
      // AutoStartManagementActivity) zijn OEM+versie-specifiek en breken
      // regelmatig; we gebruiken de gegarandeerde fallback zodat we niet
      // in "unknown-intent"-fouten belanden.
      await openAppSettings();
    } catch (_) {}
  }

  static Future<bool> autostartAttested() async {
    if (kIsWeb) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kAutostartAttestedKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markeerAutostartGedaan() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAutostartAttestedKey, true);
    } catch (_) {}
  }

  /// Voor de "reset checklist"-optie in Instellingen: gooi het
  /// user-attested vinkje weg zodat de stap opnieuw verschijnt.
  static Future<void> wisAutostartAttestatie() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kAutostartAttestedKey);
    } catch (_) {}
  }
}
