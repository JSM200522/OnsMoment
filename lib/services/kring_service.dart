import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../data/kring.dart';
import '../data/kring_membership.dart';

/// Service voor kring-aanmaken en kring-beheer (V9 fase 2).
///
/// Encapsuleert het samenstellen van kring-doc + eigenaar-membership-doc
/// zodat zowel de signup-flow (setup_wizard) als de "Nieuwe kring
/// aanmaken"-flow (volgt in 2.2) dezelfde, atomic-gewaarborgde schrijf
/// kunnen gebruiken.
class KringService {
  /// Genereert een nieuwe random kringId via een Firestore doc-id.
  /// Side-effect-vrij — caller bepaalt of/wanneer er geschreven wordt.
  static String genereerKringId() =>
      FirebaseFirestore.instance.collection('kringen').doc().id;

  /// Voegt een nieuwe kring + eigenaar-membership toe aan een meegegeven
  /// WriteBatch. Atomic met alle andere writes in dezelfde batch — caller
  /// committet zelf.
  ///
  /// Pure refactor van wat eerder inline in setup_wizard._familieRegistreren
  /// gebeurde. Geen gedrag-wijziging: zelfde velden, zelfde collecties,
  /// zelfde aangemaaktOp = serverTimestamp.
  ///
  /// Returns: de gegenereerde (of meegegeven) kringId zodat andere writes
  /// in dezelfde batch hem kunnen hergebruiken (bv. dagelijkse_momenten).
  static String voegKringMetEigenaarToeAanBatch({
    required WriteBatch batch,
    required String eigenaarUid,
    required String ontvangerNaam,
    String? foto,
    String? lievelingsdingen,
    String? woonplaats,
    String? noodcontactNaam,
    String? noodcontactTel,
    String herkenningsgeluid = 'twinkel',
    String? kringId,
  }) {
    final id = kringId ?? genereerKringId();
    final kringRef = FirebaseFirestore.instance.collection('kringen').doc(id);

    final kring = Kring(
      id: id,
      naam: ontvangerNaam,
      foto: (foto == null || foto.isEmpty) ? null : foto,
      lievelingsdingen: (lievelingsdingen == null || lievelingsdingen.isEmpty)
          ? null
          : lievelingsdingen,
      woonplaats: (woonplaats == null || woonplaats.isEmpty)
          ? null
          : woonplaats,
      noodcontactNaam: (noodcontactNaam == null || noodcontactNaam.isEmpty)
          ? null
          : noodcontactNaam,
      noodcontactTel: (noodcontactTel == null || noodcontactTel.isEmpty)
          ? null
          : noodcontactTel,
      herkenningsgeluid: herkenningsgeluid,
      eigenaarUid: eigenaarUid,
      aangemaaktOp: DateTime.now(), // direct overschreven met serverTimestamp
      laatsteUpdate: DateTime.now(),
      type: Kring.TYPE_FAMILIE,
      modus: Kring.MODUS_VERGRENDELD,
    );
    final kringMap = kring.toFirestoreMap(bijUpdate: true);
    kringMap['aangemaaktOp'] = FieldValue.serverTimestamp();
    batch.set(kringRef, kringMap);

    final membership = Membership(
      userUid: eigenaarUid,
      rol: AccountRol.eigenaar,
      gejoindOp: DateTime.now(),
      uitgenodigdDoor: null,
    );
    batch.set(
        kringRef.collection('leden').doc(eigenaarUid),
        membership.toFirestoreMap(bijCreate: true));

    return id;
  }

  /// Geeft alle kringen terug waar deze uid lid van is (eigenaar of gast).
  /// Gebaseerd op de membership-subcollectie via een collectionGroup-query.
  ///
  /// Vereist:
  /// - Single-field collection-group exemption op `leden.userUid` ASC
  /// - Firestore rule `match /{path=**}/leden/{lidId}` read voor auth
  ///
  /// Faalt safely op een lege lijst bij fouten (rights/index/network).
  static Future<List<Kring>> mijnKringen(String uid) async {
    if (uid.isEmpty) return [];
    try {
      final ledenSnap = await FirebaseFirestore.instance
          .collectionGroup('leden')
          .where('userUid', isEqualTo: uid)
          .get();
      final kringRefs = ledenSnap.docs
          .map((d) => d.reference.parent.parent)
          .whereType<DocumentReference>()
          .toList();
      if (kringRefs.isEmpty) return [];
      final kringDocs = await Future.wait(kringRefs.map((r) => r.get()));
      return kringDocs
          .where((d) => d.exists)
          .map(Kring.fromFirestore)
          .toList();
    } catch (e) {
      debugPrint('🌀 [KringService] mijnKringen($uid) faalde: $e');
      return [];
    }
  }
}
