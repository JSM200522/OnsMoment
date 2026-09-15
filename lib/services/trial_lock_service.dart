import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// FASE D-2F (sept 2026) — trial-expiry-lock logica, ready-to-wire.
///
/// **Deze service wordt bewust NIET nu aan de router gekoppeld.** Per
/// CLAUDE.md FASE D volgorde:
///   1. Betaalsysteem werkend + getest (2A..2E + sandbox).
///   2. PAS DAN deze service aansluiten op de router (FamilieScherm-
///      gate op de familie-tak).
///   3. Betaling heft de lock op.
///
/// Lock activeren VÓÓR een werkende betaal-flow = testers buitensluiten
/// zonder uitweg. Zie CLAUDE.md "Trial-expiry-lock — NIET bouwen vóór
/// betaalsysteem werkt".
///
/// De code hier bevat alleen de leesbare beslissings-logica; de UI-
/// gate + navigatie komen bij aansluiten (FASE C in de weg-naar-launch).
class TrialLockService {
  /// Duur van de gratis proef in dagen. Matcht [PakketKeuzeScherm]
  /// (private constante daar met dezelfde waarde).
  static const int proefDagen = 14;

  /// Leest `gebruikers/{uid}` en beslist of de user gelocked is.
  /// Zie [TrialLockUitkomst] onderaan voor het return-type.
  ///
  /// Fail-open op elke fout (Firestore down, doc bestaat niet, veld
  /// ontbreekt): een net-ingelogde user mag NOOIT per abuis buiten
  /// gesloten worden. Beter een gemiste lock dan een boze testfamilie.
  ///
  /// Regel:
  /// - `abonnement.actief == true` → NIET gelocked (betaald of trial).
  /// - `proefStart` ontbreekt → NIET gelocked (fail-open, bv. legacy
  ///   accounts van vóór het proefStart-veld).
  /// - Proefdagen resterend > 0 → NIET gelocked.
  /// - Anders → GELOCKED.
  static Future<TrialLockUitkomst> evaluate(String uid) async {
    if (uid.isEmpty) {
      return const TrialLockUitkomst(
        gelocked: false,
        dagenResterend: null,
        abonnementActief: false,
        redenLog: 'geen uid',
      );
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('gebruikers').doc(uid).get();
      final data = doc.data();
      if (data == null) {
        return const TrialLockUitkomst(
          gelocked: false,
          dagenResterend: null,
          abonnementActief: false,
          redenLog: 'gebruikers-doc bestaat niet — fail-open',
        );
      }
      final abo = data['abonnement'] as Map<String, dynamic>?;
      final actief = abo?['actief'] as bool? ?? false;
      if (actief) {
        return const TrialLockUitkomst(
          gelocked: false,
          dagenResterend: null,
          abonnementActief: true,
          redenLog: 'abonnement.actief=true',
        );
      }
      final proefStart = (data['proefStart'] as Timestamp?)?.toDate();
      if (proefStart == null) {
        return const TrialLockUitkomst(
          gelocked: false,
          dagenResterend: null,
          abonnementActief: false,
          redenLog: 'proefStart ontbreekt — fail-open',
        );
      }
      final verstreken = DateTime.now().difference(proefStart).inDays;
      final resterend = (proefDagen - verstreken).clamp(0, proefDagen);
      final gelocked = resterend <= 0;
      return TrialLockUitkomst(
        gelocked: gelocked,
        dagenResterend: resterend,
        abonnementActief: false,
        redenLog: gelocked
            ? 'proef verlopen ($verstreken dagen verstreken)'
            : '$resterend dagen resterend',
      );
    } catch (e) {
      debugPrint('🔒 TrialLockService.evaluate faalde (fail-open): $e');
      return TrialLockUitkomst(
        gelocked: false,
        dagenResterend: null,
        abonnementActief: false,
        redenLog: 'fout: $e',
      );
    }
  }
}

/// Uitkomst van [TrialLockService.evaluate].
class TrialLockUitkomst {
  final bool gelocked;
  final int? dagenResterend;
  final bool abonnementActief;
  final String redenLog;
  const TrialLockUitkomst({
    required this.gelocked,
    required this.dagenResterend,
    required this.abonnementActief,
    required this.redenLog,
  });
}
