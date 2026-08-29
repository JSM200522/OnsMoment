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
  /// uit een gedeelde tekst plakt. Casing blijft onaangeraakt — de
  /// directe doc-lookup is case-sensitive; case-insensitive fallback
  /// gebeurt via [_zoekTokenDocRefCaseInsensitief].
  static String normaliseerTokenInput(String input) {
    return input.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  }

  /// Zoekt het token-doc via een case-insensitive query op het
  /// [tokenLower]-veld. Fallback voor gasten die de code met verkeerde
  /// hoofdletters overtypen. Geeft null als niets gevonden of query faalt.
  ///
  /// Werkt alleen op tokens die het [tokenLower]-veld hebben — bij oude
  /// tokens backfilt [zorgVoorToken] het veld zodra de eigenaar
  /// 'Uitnodig' opnieuw opent.
  static Future<DocumentSnapshot?> _zoekTokenDocCaseInsensitief(
      String genormaliseerdToken) async {
    if (genormaliseerdToken.isEmpty) return null;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('uitnodig_tokens')
          .where('tokenLower', isEqualTo: genormaliseerdToken.toLowerCase())
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return snap.docs.first;
    } catch (e) {
      debugPrint('🔗 [UitnodigingService] case-insensitive lookup faalde: $e');
      return null;
    }
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
        final lookupRef = FirebaseFirestore.instance
            .collection('uitnodig_tokens').doc(bestaand);
        final lookup = await lookupRef.get();
        if (lookup.exists) {
          // Backfill: bestaande tokens (van vóór de case-insensitive
          // fallback) missen tokenLower. Voeg toe zodat de gast
          // case-insensitive kan valideren. Fail-soft — geen blokkade
          // op de uitnodig-flow als de update faalt.
          final data = lookup.data() ?? const <String, dynamic>{};
          if (data['tokenLower'] == null) {
            try {
              await lookupRef.update({'tokenLower': bestaand.toLowerCase()});
            } catch (_) {}
          }
          return (token: bestaand, fout: null);
        }
      }

      // V9 2.5-a-3-a-fix: bouw preview-velden voor het nieuwe token-doc
      // zodat valideer() ZONDER auth kan werken (preview vóór inlog).
      // Echte limiet-check gebeurt in accepteer() onder strikte rules.
      final kring = Kring.fromFirestore(kringSnap);

      String? uitnodigerNaam;
      try {
        final gebruikerSnap = await FirebaseFirestore.instance
            .collection('gebruikers').doc(uid).get();
        final naam = gebruikerSnap.data()?['familieNaam'] as String?;
        if (naam != null && naam.isNotEmpty) uitnodigerNaam = naam;
      } catch (_) {}

      int huidigeLeden = 0;
      int maxLeden = 8;
      try {
        final ledenCount = await kringRef.collection('leden').count().get();
        huidigeLeden = ledenCount.count ?? 0;
        final tier = await ApparaatService.krijgTier(kring.eigenaarUid);
        maxLeden = ApparaatService.limietPerTier(tier);
      } catch (_) {}

      // Genereer nieuw token via random doc-id.
      final nieuwTokenRef = FirebaseFirestore.instance
          .collection('uitnodig_tokens').doc();
      final nieuwToken = nieuwTokenRef.id;

      final batch = FirebaseFirestore.instance.batch();
      batch.set(nieuwTokenRef, {
        'kringId': kringId,
        'aangemaaktDoor': uid,
        'aangemaaktOp': FieldValue.serverTimestamp(),
        // V9 2.5-a-3-a-fix: preview-velden voor publieke valideer()
        // (read-rule op uitnodig_tokens staat sinds deze fix op publiek).
        'kringNaam': kring.naam,
        'kringFoto': kring.foto,
        'uitnodigerNaam': uitnodigerNaam,
        'huidigeLedenCache': huidigeLeden,
        'maxLedenCache': maxLeden,
        // Case-insensitive lookup-helper: gasten kunnen de code met een
        // andere casing overtypen; valideer/accepteer valt terug op een
        // query op dit veld als directe doc-lookup faalt.
        'tokenLower': nieuwToken.toLowerCase(),
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
  /// V9 2.5-a-3-a-fix: alle preview-info komt UIT HET TOKEN-DOC ZELF
  /// (gecached door zorgVoorToken bij creatie). Eén doc-read, werkt
  /// zonder auth — preview vóór inlog mogelijk. Echte limiet-check
  /// gebeurt in accepteer() onder strikte rules.
  ///
  /// Oude tokens zonder preview-velden (van vóór 2.5-a-3-a-fix) geven
  /// leeg-preview terug. Geen migratie-code — bij eerste hergebruik
  /// van Uitnodig-link-knop wordt het token-doc niet aangeraakt
  /// (immutable update-rule), dus leeg-preview blijft voor oude tokens.
  ///
  /// Doet zelf geen membership-write — caller roept [accepteer] aan.
  static Future<({Uitnodiging? uitnodiging, UitnodigingFout? fout})>
      valideer(String tokenInput) async {
    final token = normaliseerTokenInput(tokenInput);
    if (token.isEmpty) {
      return (uitnodiging: null, fout: UitnodigingFout.notFound);
    }
    try {
      DocumentSnapshot? tokenDoc = await FirebaseFirestore.instance
          .collection('uitnodig_tokens').doc(token).get();
      if (!tokenDoc.exists) {
        // Case-insensitive fallback: gast heeft de code met andere
        // hoofdletters overgetypt. Werkt op tokens met tokenLower-veld.
        tokenDoc = await _zoekTokenDocCaseInsensitief(token);
        if (tokenDoc == null || !tokenDoc.exists) {
          return (uitnodiging: null, fout: UitnodigingFout.notFound);
        }
      }
      final canonicalToken = tokenDoc.id;
      final data = (tokenDoc.data() as Map<String, dynamic>?) ??
          const <String, dynamic>{};
      final kringId = data['kringId'] as String? ?? '';
      if (kringId.isEmpty) {
        return (uitnodiging: null, fout: UitnodigingFout.notFound);
      }
      return (
        uitnodiging: Uitnodiging(
          token: canonicalToken,
          displayToken: formatTokenVoorDisplay(canonicalToken),
          kringId: kringId,
          kringNaam: data['kringNaam'] as String? ?? '',
          kringFoto: data['kringFoto'] as String?,
          uitnodigerNaam: data['uitnodigerNaam'] as String?,
          huidigeLeden: data['huidigeLedenCache'] as int? ?? 0,
          maxLeden: data['maxLedenCache'] as int? ?? 8,
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
      DocumentSnapshot? tokenSnap = await FirebaseFirestore.instance
          .collection('uitnodig_tokens').doc(rawToken).get();
      if (!tokenSnap.exists) {
        // Case-insensitive fallback (gelijk aan valideer): gast typte
        // de code met verkeerde hoofdletters.
        tokenSnap = await _zoekTokenDocCaseInsensitief(rawToken);
        if (tokenSnap == null || !tokenSnap.exists) {
          return (success: false, fout: UitnodigingFout.notFound);
        }
      }
      final tokenData = (tokenSnap.data() as Map<String, dynamic>?) ??
          const <String, dynamic>{};
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

      // V9 2.8-a-1: lees eigen familieNaam (eigen uid -> geen cross-user)
      // om als weergaveNaam in de leden-doc te denormaliseren. Voorkomt
      // dat de kringleden-lijst per lid een cross-user read moet doen.
      String? weergaveNaam;
      try {
        final eigenDoc = await FirebaseFirestore.instance
            .collection('gebruikers').doc(gebruikerUid).get();
        final naam = eigenDoc.data()?['familieNaam'] as String?;
        if (naam != null && naam.isNotEmpty) weergaveNaam = naam;
      } catch (_) {}

      final membership = Membership(
        userUid: gebruikerUid,
        rol: AccountRol.gast,
        gejoindOp: DateTime.now(), // direct overschreven met serverTimestamp
        uitgenodigdDoor: aangemaaktDoor,
        weergaveNaam: weergaveNaam,
        // Canonieke token-id (uit tokenSnap.id) i.p.v. rawToken zodat de
        // Firestore-rule case-insensitief joinen accepteert.
        viaToken: tokenSnap.id,
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
