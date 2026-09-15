import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// FASE D-3 (sept 2026) — trial-conversie-momenten, warme & spaarzame
/// aanpak op basis van conversie-onderzoek (Skript voor CLAUDE.md
/// "Wat NIET doen"):
///
///  1. **Tussentijdse nudge** — pas na waarde-ervaring (>= 5 momenten),
///     op een natuurlijk overgangsmoment (nét ná verzenden), altijd
///     "Niet nu"-optie, cap max 1x per 3 dagen. Framing: opgebouwde
///     waarde + zachte reminder van resterende dagen.
///  2. **Laatste dag** — in-app kaart wanneer proef nog 1 dag te gaan
///     heeft. Max 1x per proef getoond.
///  3. **Verlopen** — in-app kaart wanneer proef voorbij + geen
///     abonnement. Max 1x per proef getoond.
///
/// Alle checks fail-open op fouten: geen nudge/kaart tonen bij storing
/// is beter dan een crash of ongepast moment.
///
/// GEEN local scheduled notification in deze eerste versie — vereist
/// timezone-init + Samsung/Xiaomi battery-opt-workarounds. Actieve
/// gebruikers openen de app dagelijks; de in-app kaart dekt dat. Later
/// enhancement: FCM scheduled push via Cloud Function.
class TrialPromptService {
  static const int _proefDagen = 14;

  /// Minimum aantal verzonden momenten voordat de tussentijdse nudge
  /// überhaupt in beeld komt. Onder deze drempel: user heeft nog geen
  /// waarde ervaren — dan converteert een nudge slecht en irriteert.
  static const int _minMomentenVoorNudge = 5;

  /// Rustig-cap: minimaal aantal dagen tussen twee nudges. Zorgt dat
  /// een actieve verzender niet iedere dag een sheet krijgt.
  static const int _minDagenTussenNudges = 3;

  // SharedPreferences-sleutels — houden state per apparaat. Bij nieuw
  // account (setup-wizard) worden ze niet expliciet gewist; ze zijn
  // van nature scoped op de teller vanaf dat moment.
  static const String _kMomentenTeller = 'trial_momenten_teller_v1';
  static const String _kNudgeLastShown = 'trial_nudge_last_shown_ms_v1';
  static const String _kLaatsteDagGetoond = 'trial_laatste_dag_getoond_v1';
  static const String _kVerlopenGetoond = 'trial_verlopen_getoond_v1';

  // ─────────────────────────────────────────────────────────────
  // Momenten-teller (voor de "waarde-ervaring"-drempel + framing)
  // ─────────────────────────────────────────────────────────────

  /// Roep aan direct nadat een moment succesvol is geschreven naar
  /// Firestore. Fail-soft: bij SharedPreferences-fout wordt niets
  /// bijgewerkt en gaat het leven door.
  static Future<void> registreerMomentVerzonden() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final huidig = prefs.getInt(_kMomentenTeller) ?? 0;
      await prefs.setInt(_kMomentenTeller, huidig + 1);
    } catch (e) {
      debugPrint('🎯 TrialPromptService.registreerMomentVerzonden '
          'faalde (fail-soft): $e');
    }
  }

  static Future<int> aantalMomentenVerzonden() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_kMomentenTeller) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Fase-evaluatie (leest gebruikers/{uid}.proefStart + abonnement)
  // ─────────────────────────────────────────────────────────────

  /// Enkelvoudige Firestore-read → TrialContext of null bij fout.
  /// Fail-open: bij null returnt magNudgeTonen ook null (geen nudge).
  static Future<TrialContext?> haalContext(String uid,
      {String? kringNaamFallback}) async {
    if (uid.isEmpty) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('gebruikers').doc(uid).get();
      final data = doc.data();
      if (data == null) return null;
      final abo = data['abonnement'] as Map<String, dynamic>?;
      final actief = abo?['actief'] as bool? ?? false;
      final proefStart = (data['proefStart'] as Timestamp?)?.toDate();
      final naam = kringNaamFallback ??
          (data['familieNaam'] as String?) ??
          (data['ontvangerNaam'] as String?);
      if (actief) {
        return TrialContext(
          fase: TrialFase.betaald,
          dagenResterend: null,
          kringNaam: naam,
        );
      }
      if (proefStart == null) {
        return TrialContext(
          fase: TrialFase.onbekend,
          dagenResterend: null,
          kringNaam: naam,
        );
      }
      final verstreken = DateTime.now().difference(proefStart).inDays;
      final resterend = _proefDagen - verstreken;
      final TrialFase fase;
      if (resterend <= 0) {
        fase = TrialFase.verlopen;
      } else if (resterend == 1) {
        fase = TrialFase.laatsteDag;
      } else {
        fase = TrialFase.proef;
      }
      return TrialContext(
        fase: fase,
        dagenResterend: resterend.clamp(0, _proefDagen),
        kringNaam: naam,
      );
    } catch (e) {
      debugPrint('🎯 TrialPromptService.haalContext faalde '
          '(fail-open): $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 1) TUSSENTIJDSE NUDGE
  // ─────────────────────────────────────────────────────────────

  /// Beslist of de tussentijdse nudge nu getoond mag worden. Returnt
  /// nudge-info voor de UI, of null als een van de cheap-checks faalt
  /// (dan wordt géén Firestore-read gedaan).
  ///
  /// Volgorde (cheap → duur):
  ///  1. SharedPreferences: teller >= 5 momenten.
  ///  2. SharedPreferences: laatst getoond >= 3 dagen geleden.
  ///  3. Firestore: context.fase == proef && resterend > 1
  ///     (op laatste dag pakt de eind-reminder het over).
  static Future<TrialNudgeInfo?> magNudgeTonen(String uid) async {
    if (uid.isEmpty) return null;
    final teller = await aantalMomentenVerzonden();
    if (teller < _minMomentenVoorNudge) return null;

    try {
      final prefs = await SharedPreferences.getInstance();
      final laatsteMs = prefs.getInt(_kNudgeLastShown) ?? 0;
      if (laatsteMs > 0) {
        final laatste = DateTime.fromMillisecondsSinceEpoch(laatsteMs);
        if (DateTime.now().difference(laatste).inDays <
            _minDagenTussenNudges) {
          return null;
        }
      }
    } catch (_) {
      // Prefs-fout → sla check over, blokkeer nudge niet.
    }

    final ctx = await haalContext(uid);
    if (ctx == null) return null;
    if (ctx.fase != TrialFase.proef) return null;
    if (ctx.dagenResterend == null || ctx.dagenResterend! <= 1) {
      return null;
    }
    return TrialNudgeInfo(
      dagenResterend: ctx.dagenResterend!,
      momentenTotaal: teller,
      kringNaam: ctx.kringNaam,
    );
  }

  /// Markeer nudge als getoond zodat de 3-dagen-cap doorloopt. Roep
  /// aan zodra de sheet daadwerkelijk verschijnt (niet bij mag-check).
  static Future<void> markeerNudgeGetoond() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          _kNudgeLastShown, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('🎯 markeerNudgeGetoond faalde (fail-soft): $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 2) LAATSTE DAG + 3) VERLOPEN — max 1x per proef in-app kaart
  // ─────────────────────────────────────────────────────────────

  /// Voor de warme eind-reminders (laatste dag + verlopen). Beide
  /// mogen max 1x per proef getoond worden — verhindert dat de kaart
  /// bij elke schermwissel opnieuw pop't.
  ///
  /// De kaart zelf blijft persistent zichtbaar in InstellingenTab (zie
  /// [TrialContext]); dit vinkje regelt alleen de één-malige
  /// aandacht-trekkende presentatie (bijv. dialog of home-banner).
  static Future<bool> magEindeReminderTonen(TrialFase fase) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = fase == TrialFase.laatsteDag
          ? _kLaatsteDagGetoond
          : (fase == TrialFase.verlopen ? _kVerlopenGetoond : null);
      if (key == null) return false;
      return !(prefs.getBool(key) ?? false);
    } catch (_) {
      return false;
    }
  }

  static Future<void> markeerEindeReminderGetoond(TrialFase fase) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = fase == TrialFase.laatsteDag
          ? _kLaatsteDagGetoond
          : (fase == TrialFase.verlopen ? _kVerlopenGetoond : null);
      if (key == null) return;
      await prefs.setBool(key, true);
    } catch (e) {
      debugPrint('🎯 markeerEindeReminderGetoond faalde '
          '(fail-soft): $e');
    }
  }

  /// Reset alle vinkjes + teller. Roep aan bij expliciete logout of
  /// bij setup-wizard-completion voor een NIEUW account, zodat een
  /// verse proef ook verse reminders krijgt.
  static Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kMomentenTeller);
      await prefs.remove(_kNudgeLastShown);
      await prefs.remove(_kLaatsteDagGetoond);
      await prefs.remove(_kVerlopenGetoond);
    } catch (e) {
      debugPrint('🎯 reset faalde (fail-soft): $e');
    }
  }
}

/// Uitkomst van [TrialPromptService.haalContext].
class TrialContext {
  final TrialFase fase;
  final int? dagenResterend;
  final String? kringNaam;
  const TrialContext({
    required this.fase,
    required this.dagenResterend,
    required this.kringNaam,
  });
}

/// Payload voor de tussentijdse nudge-sheet.
class TrialNudgeInfo {
  final int dagenResterend;
  final int momentenTotaal;
  final String? kringNaam;
  const TrialNudgeInfo({
    required this.dagenResterend,
    required this.momentenTotaal,
    required this.kringNaam,
  });
}

/// Fase van de user in de proef/abonnement-lifecycle.
enum TrialFase {
  /// Firestore niet leesbaar of proefStart ontbreekt op oud account —
  /// fail-open: nooit iets tonen.
  onbekend,

  /// abonnement.actief == true → alle prompts uit.
  betaald,

  /// proefStart aanwezig, > 1 dag resterend.
  proef,

  /// proefStart aanwezig, precies 1 dag resterend — laatste-dag-kaart.
  laatsteDag,

  /// proef verlopen én geen actief abonnement — verlopen-kaart.
  verlopen,
}
