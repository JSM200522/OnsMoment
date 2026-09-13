import 'package:android_intent_plus/android_intent.dart';
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

  /// P3 (13 sept 2026): per-OEM deep-link naar EXACT de autostart-
  /// pagina. Probeert eerst de merk-specifieke Intent; als die faalt
  /// (OEM heeft de Activity hernoemd op deze OS-versie, of user heeft
  /// een aangepaste ROM), fallback naar Android's app-info-pagina zodat
  /// user van daar één klik verder kan naar batterij/autostart.
  ///
  /// Merk-specifieke deep-links zijn onvermijdelijk fragile — OEM's
  /// hernoemen Activities regelmatig. Try/catch is essentieel.
  ///
  /// Retourneert de merknaam (lowercase) als je die wilt gebruiken voor
  /// een merk-specifieke instructie-tekst; 'onbekend' bij niet-Android.
  static Future<String> openOemAutostartInstellingen() async {
    if (kIsWeb) return 'onbekend';
    String merk = 'onbekend';
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      merk = info.manufacturer.toLowerCase().trim();
    } catch (_) {}

    // Kandidaat-Intents per merk. Meerdere per OEM voor OS-versie-
    // verschillen (bv. Xiaomi MIUI 12 vs 14 vs HyperOS).
    final kandidaten = _oemIntentKandidaten(merk);
    for (final intent in kandidaten) {
      try {
        await intent.launch();
        return merk;
      } catch (_) {
        // volgende kandidaat proberen
      }
    }
    // Fallback: app-info-pagina.
    try {
      await openAppSettings();
    } catch (_) {}
    return merk;
  }

  static List<AndroidIntent> _oemIntentKandidaten(String merk) {
    switch (merk) {
      case 'samsung':
        return [
          // One UI 5+ Sleeping apps direct
          const AndroidIntent(
            action: 'com.samsung.android.sm.ACTION_APP_SLEEP_LIST',
          ),
          // Device Care (algemene batterij-optimalisatie-pagina)
          const AndroidIntent(
            action: 'android.intent.action.MAIN',
            componentName: 'com.samsung.android.lool/'
                'com.samsung.android.sm.ui.battery.BatteryActivity',
          ),
        ];
      case 'xiaomi':
      case 'redmi':
      case 'poco':
        return [
          // MIUI/HyperOS autostart-manager
          const AndroidIntent(
            action: 'android.intent.action.MAIN',
            componentName: 'com.miui.securitycenter/'
                'com.miui.permcenter.autostart.AutoStartManagementActivity',
          ),
          // MIUI power-hide-mode (batterij-optimalisatie-lijst)
          const AndroidIntent(
            action: 'miui.intent.action.POWER_HIDE_MODE_APP_LIST',
          ),
        ];
      case 'huawei':
      case 'honor':
        return [
          // EMUI/MagicOS launch-manager
          const AndroidIntent(
            action: 'android.intent.action.MAIN',
            componentName: 'com.huawei.systemmanager/'
                '.startupmgr.ui.StartupNormalAppListActivity',
          ),
          const AndroidIntent(
            action: 'android.intent.action.MAIN',
            componentName: 'com.huawei.systemmanager/'
                '.optimize.process.ProtectActivity',
          ),
        ];
      case 'oppo':
      case 'realme':
        return [
          // ColorOS/RealmeUI autostart. Nieuwere en oudere paths.
          const AndroidIntent(
            action: 'android.intent.action.MAIN',
            componentName: 'com.coloros.safecenter/'
                '.startupapp.StartupAppListActivity',
          ),
          const AndroidIntent(
            action: 'android.intent.action.MAIN',
            componentName: 'com.coloros.safecenter/'
                '.permission.startup.StartupAppListActivity',
          ),
        ];
      case 'vivo':
        return [
          // FuntouchOS bg-startup-manager
          const AndroidIntent(
            action: 'android.intent.action.MAIN',
            componentName: 'com.vivo.permissionmanager/'
                '.activity.BgStartUpManagerActivity',
          ),
        ];
      default:
        return const [];
    }
  }

  /// Korte NL-instructie per merk voor onder de "Instelling openen"-
  /// knop, zodat user weet wat te doen als de deep-link naar app-info
  /// fallback'te (of naar een instelling-tab die er iets anders uitziet
  /// dan verwacht).
  static String instructiePerOem(String merk) {
    switch (merk) {
      case 'samsung':
        return "Zoek onder Batterij → Achtergrondgebruikslimiet → "
            "Slapen. Als Ons Moment in de lijst staat: haal 'm daar weg.";
      case 'xiaomi':
      case 'redmi':
      case 'poco':
        return 'Zoek "Autostart" (of "Automatisch opstarten") en zet '
            'Ons Moment aan.';
      case 'huawei':
      case 'honor':
        return 'Zoek "App-launch" (of "Handmatig beheer") en zet '
            'de schakelaar voor Ons Moment aan.';
      case 'oppo':
      case 'realme':
        return 'Zoek "Autostart" (onder Batterijgebruik) en zet '
            'Ons Moment aan.';
      case 'vivo':
        return 'Zoek "Achtergrondtoegang" (of "Autostart") en zet '
            'Ons Moment aan.';
      default:
        return 'Zoek "Autostart" of "Automatisch opstarten" in de '
            'instellingen van je apparaat en zet Ons Moment aan.';
    }
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
