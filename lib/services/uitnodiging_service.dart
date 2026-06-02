import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../data/kring.dart';
import '../data/kring_membership.dart';
import '../data/uitnodiging.dart';
import 'apparaat_service.dart';

/// Service voor de V9 uitnodig-flow (2.5).
///
/// Eén herbruikbaar token per kring (WhatsApp-stijl groepslink). Token
/// wordt gegenereerd bij eerste 'Uitnodigen'-klik en blijft staan tot
/// expliciet ingetrokken (latere fase). De natuurlijke rem is de
/// kring-limiet uit het tier-model.
///
/// Schema:
/// - kringen/{kringId}.uitnodigToken / .uitnodigTokenOp — bron-of-truth
/// - uitnodig_tokens/{token} — lichte lookup-doc (kringId, aangemaaktDoor,
///   aangemaaktOp) zodat een gast met alleen het token de kring kan vinden
class UitnodigingService {
  // ─── Token-format helpers ─────────────────────────────────────────

  /// Splitst de 20-char raw token in 5 groepjes van 4 met streepjes:
  /// 'aB3c-D4eF-5gH6-iJ7k-lM8n'. Pure UI-helper — Firestore-paden
  /// gebruiken altijd de raw versie.
  static String formatTokenVoorDisplay(String raw) {
    if (raw.isEmpty) return '';
    final buf = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write('-');
      buf.write(raw[i]);
    }
    return buf.toString();
  }

  /// Strip alle non-alfanumerieke chars (streepjes, spaties, newlines,
  /// emojis-niet-aanwezig). Tolerant voor wat de gebruiker overtypt of
  /// uit een gedeelde tekst plakt.
  static String normaliseerTokenInput(String input) {
    return input.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  }

  // ─── Service-methods ──────────────────────────────────────────────

  /// Zorgt dat de gegeven kring een actief uitnodig-token heeft.
  /// Idempotent: bij bestaand geldig token returnt dat; anders genereert
  /// er één in een atomic batch (token-doc + kring-update).
  ///
  /// [kringId] de kring waarvoor uitgenodigd wordt
  /// [uid] de auth-uid van de uitnodiger (audit-trail + rule-eis)
  static Future<({String? token, UitnodigingFout? fout})> zorgVoorToken({
    required String kringId,
    required String uid,
  }) async {
    if (kringId.isEmpty || uid.isEmpty) {
      return (token: null, fout: UitnodigingFout.netwerk);
    }
    try {
      final kringRef = FirebaseFirestore.instance
          .collection('kringen').doc(kringId);
      final kringSnap = await kringRef.get();
      if (!kringSnap.exists) {
        return (token: null, fout: UitnodigingFout.kringNotFound);
      }
      final bestaand = kringSnap.data()?['uitnodigToken'] as String?;
      if (bestaand != null && bestaand.isNotEmpty) {
        // Sanity-check: lookup-doc moet ook bestaan. Bij mismatch
        // (bv. handmatig verwijderd) door naar nieuwe-token-pad.
        final lookup = await FirebaseFirestore.instance
            .collection('uitnodig_tokens').doc(bestaand).get();
        if (lookup.exists) {
          return (token: bestaand, fout: null);
        }
      }

      // Genereer nieuw token via random doc-id.
      final nieuwTokenRef = FirebaseFirestore.instance
          .collection('uitnodig_tokens').doc();
      final nieuwToken = nieuwTokenRef.id;

      final batch = FirebaseFirestore.instance.batch();
      batch.set(nieuwTokenRef, {
        'kringId': kringId,
        'aangemaaktDoor': uid,
        'aangemaaktOp': FieldValue.serverTimestamp(),
      });
      batch.update(kringRef, {
        'uitnodigToken': nieuwToken,
        'uitnodigTokenOp': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      return (token: nieuwToken, fout: null);
    } catch (e) {
      debugPrint('🔗 [UitnodigingService] zorgVoorToken faalde: $e');
      return (token: null, fout: UitnodigingFout.netwerk);
    }
  }

  /// Valideert een token-input (uit URL of overgetypte code). Returnt
  /// een Uitnodiging-object met preview-velden + ledental + maxLeden,
  /// of een foutreden.
  ///
  /// Doet zelf geen membership-write — caller roept [accepteer] aan.
  static Future<({Uitnodiging? uitnodiging, UitnodigingFout? fout})>
      valideer(String tokenInput) async {
    final token = normaliseerTokenInput(tokenInput);
    if (token.isEmpty) {
      return (uitnodiging: null, fout: UitnodigingFout.notFound);
    }
    try {
      final tokenDoc = await FirebaseFirestore.instance
          .collection('uitnodig_tokens').doc(token).get();
      if (!tokenDoc.exists) {
        return (uitnodiging: null, fout: UitnodigingFout.notFound);
      }
      final tokenData = tokenDoc.data() ?? const <String, dynamic>{};
      final kringId = tokenData['kringId'] as String? ?? '';
      final aangemaaktDoor = tokenData['aangemaaktDoor'] as String? ?? '';
      if (kringId.isEmpty) {
        return (uitnodiging: null, fout: UitnodigingFout.notFound);
      }

      final kringSnap = await FirebaseFirestore.instance
          .collection('kringen').doc(kringId).get();
      if (!kringSnap.exists) {
        return (uitnodiging: null, fout: UitnodigingFout.kringNotFound);
      }
      final kring = Kring.fromFirestore(kringSnap);

      // Uitnodiger-naam (best-effort — null bij ontbrekend doc).
      String? uitnodigerNaam;
      if (aangemaaktDoor.isNotEmpty) {
        try {
          final gebruikerSnap = await FirebaseFirestore.instance
              .collection('gebruikers').doc(aangemaaktDoor).get();
          final naam = gebruikerSnap.data()?['familieNaam'] as String?;
          if (naam != null && naam.isNotEmpty) uitnodigerNaam = naam;
        } catch (_) {}
      }

      // Tellingen + tier-limiet.
      final ledenCount = await FirebaseFirestore.instance
          .collection('kringen').doc(kringId)
          .collection('leden').count().get();
      final huidigeLeden = ledenCount.count ?? 0;
      final tier = await ApparaatService.krijgTier(kring.eigenaarUid);
      final maxLeden = ApparaatService.limietPerTier(tier);

      return (
        uitnodiging: Uitnodiging(
          token: token,
          displayToken: formatTokenVoorDisplay(token),
          kringId: kringId,
          kringNaam: kring.naam,
          kringFoto: kring.foto,
          uitnodigerNaam: uitnodigerNaam,
          huidigeLeden: huidigeLeden,
          maxLeden: maxLeden,
        ),
        fout: null,
      );
    } catch (e) {
      debugPrint('🔗 [UitnodigingService] valideer faalde: $e');
      return (uitnodiging: null, fout: UitnodigingFout.netwerk);
    }
  }

  /// Voegt [gebruikerUid] als gast-membership toe aan de kring waar
  /// [token] naar wijst. Idempotent: als de gebruiker al lid is,
  /// returnt [UitnodigingFout.alLid] zonder schade.
  ///
  /// **Race-mitigatie (Optie A, bekende beperking)**: doet vlak vóór de
  /// membership-write een nieuwe `.count()` op de leden-subcollectie om
  /// te checken dat de kring nog niet vol is. Dit dekt het normale geval
  /// (sub-seconde tussen valideer en accept) maar is niet 100% atomic
  /// — twee gasten die tegelijk de laatste plek opeisen kunnen allebei
  /// slagen. Voor latere fase: Firestore-transaction met expliciet
  /// teller-veld op kring-doc.
  static Future<({bool success, UitnodigingFout? fout})> accepteer({
    required String token,
    required String gebruikerUid,
  }) async {
    final rawToken = normaliseerTokenInput(token);
    if (rawToken.isEmpty || gebruikerUid.isEmpty) {
      return (success: false, fout: UitnodigingFout.notFound);
    }
    try {
      final tokenSnap = await FirebaseFirestore.instance
          .collection('uitnodig_tokens').doc(rawToken).get();
      if (!tokenSnap.exists) {
        return (success: false, fout: UitnodigingFout.notFound);
      }
      final tokenData = tokenSnap.data() ?? const <String, dynamic>{};
      final kringId = tokenData['kringId'] as String? ?? '';
      final aangemaaktDoor = tokenData['aangemaaktDoor'] as String?;
      if (kringId.isEmpty) {
        return (success: false, fout: UitnodigingFout.notFound);
      }

      final kringRef = FirebaseFirestore.instance
          .collection('kringen').doc(kringId);
      final kringSnap = await kringRef.get();
      if (!kringSnap.exists) {
        return (success: false, fout: UitnodigingFout.kringNotFound);
      }
      final kring = Kring.fromFirestore(kringSnap);

      // Al lid? Geen membership-write nodig, maar return alLid zodat de
      // UI iets duidelijks kan tonen.
      final lidRef = kringRef.collection('leden').doc(gebruikerUid);
      final lidSnap = await lidRef.get();
      if (lidSnap.exists) {
        return (success: false, fout: UitnodigingFout.alLid);
      }

      // Optie A race-mitigatie: recount vlak voor de write.
      final ledenCount = await kringRef.collection('leden').count().get();
      final huidigeLeden = ledenCount.count ?? 0;
      final tier = await ApparaatService.krijgTier(kring.eigenaarUid);
      final maxLeden = ApparaatService.limietPerTier(tier);
      if (huidigeLeden >= maxLeden) {
        return (success: false, fout: UitnodigingFout.kringVol);
      }

      final membership = Membership(
        userUid: gebruikerUid,
        rol: AccountRol.gast,
        gejoindOp: DateTime.now(), // direct overschreven met serverTimestamp
        uitgenodigdDoor: aangemaaktDoor,
      );

      final batch = FirebaseFirestore.instance.batch();
      batch.set(lidRef, membership.toFirestoreMap(bijCreate: true));
      await batch.commit();
      return (success: true, fout: null);
    } catch (e) {
      debugPrint('🔗 [UitnodigingService] accepteer faalde: $e');
      return (success: false, fout: UitnodigingFout.netwerk);
    }
  }
}
