import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Beheert apparaat-detectie en registratie in de sub-collectie
/// `gebruikers/{familieUid}/apparaten/{apparaatId}`.
class ApparaatService {
  /// Geeft een leesbaar label voor het huidige apparaat (bv. 'iPhone',
  /// 'Android-telefoon', 'MacBook'). Faalt zachtjes naar 'Apparaat'.
  static Future<String> detecteerLabel() async {
    if (!kIsWeb) return 'Apparaat';
    try {
      final info = await DeviceInfoPlugin().webBrowserInfo;
      final ua = info.userAgent ?? '';
      if (ua.contains('iPhone')) return 'iPhone';
      if (ua.contains('iPad')) return 'iPad';
      if (ua.contains('Android') && ua.contains('Mobile')) return 'Android-telefoon';
      if (ua.contains('Android')) return 'Android-tablet';
      if (ua.contains('Macintosh') || ua.contains('Mac OS')) return 'MacBook';
      if (ua.contains('Windows')) return 'Windows PC';
      if (ua.contains('Linux')) return 'Linux PC';
      return 'Onbekend apparaat';
    } catch (_) {
      return 'Apparaat';
    }
  }

  /// Schrijft of bijwerkt een apparaat-doc met set+merge.
  /// Faalt silent bij Firestore-errors (bv. ontbrekende rules).
  static Future<void> registreer({
    required String familieUid,
    required String apparaatId,
    required String persoonsNaam,
    required String modus,
    String? weergaveModus,
  }) async {
    try {
      final label = await detecteerLabel();
      final data = <String, dynamic>{
        'persoonsNaam': persoonsNaam,
        'apparaatLabel': label,
        'modus': modus,
        'aangemaakt': FieldValue.serverTimestamp(),
        'laatstActief': FieldValue.serverTimestamp(),
      };
      if (weergaveModus != null) data['weergaveModus'] = weergaveModus;
      await FirebaseFirestore.instance
          .collection('gebruikers').doc(familieUid)
          .collection('apparaten').doc(apparaatId)
          .set(data, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Lichtgewicht heartbeat-update. Faalt silent als doc niet bestaat
  /// (bestaande gebruikers zonder registratie).
  static Future<void> updateLaatstActief({
    required String familieUid,
    required String apparaatId,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('gebruikers').doc(familieUid)
          .collection('apparaten').doc(apparaatId)
          .update({'laatstActief': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  /// Geeft alle apparaten in deze kring terug voor adres-keuze in stuur-UI.
  /// Lege lijst bij fout (bv. permission-denied of nog geen apparaten).
  static Future<List<Map<String, dynamic>>> kringLeden(String familieUid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('gebruikers').doc(familieUid)
          .collection('apparaten').get();
      return snap.docs.map((doc) {
        final d = doc.data();
        return <String, dynamic>{
          'apparaatId': doc.id,
          'persoonsNaam': d['persoonsNaam'] as String? ?? '',
          'apparaatLabel': d['apparaatLabel'] as String? ?? '',
          'modus': d['modus'] as String? ?? '',
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// True als dit apparaatId het oudste apparaat is in de subcollectie —
  /// dat is het apparaat dat de account heeft aangemaakt. Faalt naar false.
  static Future<bool> isAccountMaker({
    required String familieUid,
    required String apparaatId,
  }) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('gebruikers').doc(familieUid)
          .collection('apparaten')
          .orderBy('aangemaakt').limit(1).get();
      if (snap.docs.isEmpty) return false;
      return snap.docs.first.id == apparaatId;
    } catch (_) {
      return false;
    }
  }

  /// Geeft de huidige weergaveModus van het eerste ontvanger-apparaat in
  /// deze kring. Gebruikt voor visuele indicatie in de modus-dialog.
  static Future<String?> krijgWeergaveModusVoorOntvangers(
      String familieUid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('gebruikers').doc(familieUid)
          .collection('apparaten')
          .where('modus', isEqualTo: 'ontvanger').limit(1).get();
      if (snap.docs.isEmpty) return null;
      return snap.docs.first.data()['weergaveModus'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Batch-update weergaveModus voor alle ontvanger-apparaten in een kring.
  /// Triggert remote modus-wissel via Firestore listener op ontvanger-kant.
  static Future<bool> zetWeergaveModusVoorOntvangers({
    required String familieUid,
    required String nieuweModus,
  }) async {
    if (nieuweModus != 'vergrendeld' && nieuweModus != 'meldingen') {
      return false;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('gebruikers').doc(familieUid)
          .collection('apparaten')
          .where('modus', isEqualTo: 'ontvanger').get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'weergaveModus': nieuweModus});
      }
      await batch.commit();
      return true;
    } catch (_) {
      return false;
    }
  }
}
