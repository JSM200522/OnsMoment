import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// VER-1: bepaalt of een ingelogde familie-gebruiker verplicht zijn
/// e-mailadres moet verifiëren voordat hij de kern-app kan gebruiken.
///
/// Combineert drie inputs, in deze volgorde:
///  1. `config/features.emailVerificatieAfdwingen` (bool). Default
///     false. Alleen als true kan de gate ooit dichtklappen.
///  2. `config/features.emailVerificatieGraceTot` (Timestamp).
///     Accounts aangemaakt vóór deze datum worden ongestoord gelaten
///     (bestaande testers). Ontbreekt / niet gezet → geen grace-shelter.
///  3. `FirebaseAuth.currentUser.emailVerified` + `user.metadata.
///     creationTime`.
///
/// Fail-soft: elke Firestore-fout, ontbrekend veld of onverwachte staat
/// → `moetVerifieren: false`. We sluiten NOOIT iemand ten onrechte
/// buiten. De gate is voorziening voor mensen die tijd hebben om de
/// mail te openen; een netwerkflop of stale Firestore-cache mag geen
/// mantelzorger die zijn dierbare wil bereiken tegenhouden.
///
/// Cross-platform: alleen `firebase_auth` + `cloud_firestore` — werkt
/// identiek op Android, iOS en web zonder platform-specifieke code.
class VerificatieGateService {
  VerificatieGateService._();

  static const String _configPad = 'config';
  static const String _configDoc = 'features';
  static const String _kAfdwingen = 'emailVerificatieAfdwingen';
  static const String _kGraceTot = 'emailVerificatieGraceTot';

  /// Cache voor de config-flags. Levensduur = één app-sessie. Zo
  /// belasten we Firestore hooguit één keer per app-open. Wijzigt de
  /// Firebase-Console-flag: pas na een herstart merkt de gebruiker het
  /// — acceptabel voor een pre-productie voorziening.
  static bool? _cacheAfdwingen;
  static Timestamp? _cacheGraceTot;
  static bool _cacheGeladen = false;
  static Future<void>? _laadFuture;

  /// True als de huidige `FirebaseAuth.currentUser` gedwongen wordt zijn
  /// e-mail te verifiëren voordat hij door kan naar de kern-app. False
  /// bij:
  ///  - flag uit (default),
  ///  - config niet te lezen (fail-soft),
  ///  - user is null (dan is er niks te gaten),
  ///  - user is al verified,
  ///  - user is aangemaakt vóór graceTot.
  static Future<bool> moetVerifieren() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      if (user.emailVerified) return false;

      await _zorgConfigGeladen();
      if (_cacheAfdwingen != true) return false;

      final graceTot = _cacheGraceTot;
      if (graceTot != null) {
        final gemaakt = user.metadata.creationTime;
        if (gemaakt != null && gemaakt.isBefore(graceTot.toDate())) {
          // Bestaand testaccount van vóór de grace-datum — niet gaten.
          return false;
        }
      }
      return true;
    } catch (e) {
      debugPrint('⚠️ VerificatieGateService.moetVerifieren faalde: $e '
          '→ fail-soft niet-blokkeren');
      return false;
    }
  }

  /// Roep aan na een succesvolle `user.reload()` om onze cache te
  /// dwingen. Handig voor het "Ik heb het bevestigd"-scenario.
  static void wisCache() {
    _cacheAfdwingen = null;
    _cacheGraceTot = null;
    _cacheGeladen = false;
    _laadFuture = null;
  }

  static Future<void> _zorgConfigGeladen() async {
    if (_cacheGeladen) return;
    _laadFuture ??= _laad();
    await _laadFuture;
  }

  static Future<void> _laad() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(_configPad).doc(_configDoc).get()
          .timeout(const Duration(seconds: 5));
      final data = snap.data();
      final afdw = data?[_kAfdwingen];
      final grace = data?[_kGraceTot];
      _cacheAfdwingen = afdw is bool ? afdw : false;
      _cacheGraceTot = grace is Timestamp ? grace : null;
    } catch (e) {
      debugPrint('⚠️ VerificatieGateService config-laden faalde: $e '
          '→ afdwingen behandeld als false');
      _cacheAfdwingen = false;
      _cacheGraceTot = null;
    } finally {
      _cacheGeladen = true;
    }
  }
}
