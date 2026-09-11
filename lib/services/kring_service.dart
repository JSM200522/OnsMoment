import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../data/kring.dart';
import '../data/kring_membership.dart';
import 'device_modus_service.dart';

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

  /// Bouwt de Firestore-map voor een nieuwe kring — zonder te schrijven.
  /// Caller committet zelf via `set(kringRef, map)` of `batch.set(...)`.
  ///
  /// Waarom apart van [bouwEigenaarMembershipMap]: Firestore-rules
  /// evalueren batch-writes tegen de PRE-batch state. De leden-create-
  /// rule (`isEigenaar`) leest `kringen/{K}` — die moet dus AL bestaan
  /// vóórdat de leden-write wordt beoordeeld. Setup_wizard schrijft
  /// daarom eerst de kring (batch A) en pas dan de eigenaar-membership.
  static Map<String, dynamic> bouwKringMap({
    required String kringId,
    required String eigenaarUid,
    required String ontvangerNaam,
    String? foto,
    String? noodcontactNaam,
    String? noodcontactTel,
    String herkenningsgeluid = 'twinkel',
  }) {
    final kring = Kring(
      id: kringId,
      naam: ontvangerNaam,
      foto: (foto == null || foto.isEmpty) ? null : foto,
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
    return kringMap;
  }

  /// Bouwt de Firestore-map voor een eigenaar-membership — zonder te
  /// schrijven. Caller committet zelf; zie [bouwKringMap] voor de reden
  /// waarom kring en leden apart geschreven moeten worden.
  static Map<String, dynamic> bouwEigenaarMembershipMap({
    required String eigenaarUid,
    String eigenaarNaam = '',
  }) {
    final membership = Membership(
      userUid: eigenaarUid,
      rol: AccountRol.eigenaar,
      gejoindOp: DateTime.now(),
      uitgenodigdDoor: null,
      weergaveNaam: eigenaarNaam.isEmpty ? null : eigenaarNaam,
    );
    return membership.toFirestoreMap(bijCreate: true);
  }

  /// V9 2.8-a-1: verwijdert een membership-doc uit een kring. Wordt
  /// in 2.8-a-2 vanuit de UI aangeroepen (eigenaar verwijdert lid OF
  /// gast self-leave). Doet GEEN force-logout — die zit op apparaat-
  /// niveau via _KringWachter en is hier niet van toepassing.
  ///
  /// Permissies worden door Firestore-rules afgedwongen (handmatig in
  /// Console te zetten vóór 2.8-a-2): alleen request.auth.uid == lidId
  /// (self-leave) of de eigenaar van de kring mag deleten.
  static Future<bool> verwijderLid({
    required String kringId,
    required String userUid,
  }) async {
    if (kringId.isEmpty || userUid.isEmpty) return false;
    try {
      await FirebaseFirestore.instance
          .collection('kringen').doc(kringId)
          .collection('leden').doc(userUid)
          .delete();
      return true;
    } catch (e) {
      debugPrint('🌀 [KringService] verwijderLid faalde: $e');
      return false;
    }
  }

  /// Levert een live stream van de actieve kring (V9 2.4-a-1).
  ///
  /// Vuurt opnieuw bij:
  /// - elke wijziging van DeviceModusService.actieveKringNotifier
  ///   (kring-switch via switcher of nieuwe-kring-aanmaak)
  /// - elke wijziging van het kring-doc zelf in Firestore (bv. naam-edit
  ///   via OntvangerInfoScherm)
  ///
  /// Emit Kring? — null als geen kring actief, kring-doc niet bestaat
  /// (V7/V8 uid-fallback) of fromFirestore-parse faalt. Listeners
  /// kunnen daarop een fallback-strategie toepassen (gebruikers/{uid}).
  ///
  /// Stream cancelt z'n interne Firestore-listener automatisch bij elke
  /// notifier-wijziging en bij listener-cancel — geen leaks.
  static Stream<Kring?> actieveKringStream() {
    late StreamController<Kring?> controller;
    StreamSubscription<DocumentSnapshot>? docSub;

    Future<void> abonneer(String? kringId) async {
      await docSub?.cancel();
      docSub = null;
      if (controller.isClosed) return;
      if (kringId == null || kringId.isEmpty) {
        controller.add(null);
        return;
      }
      docSub = FirebaseFirestore.instance
          .collection('kringen').doc(kringId)
          .snapshots()
          .listen((doc) {
        if (controller.isClosed) return;
        if (!doc.exists) {
          controller.add(null);
          return;
        }
        try {
          controller.add(Kring.fromFirestore(doc));
        } catch (e) {
          debugPrint('🌀 [KringService] Kring.fromFirestore faalde: $e');
          controller.add(null);
        }
      }, onError: (Object e) {
        if (!controller.isClosed) controller.add(null);
      });
    }

    void onNotifier() =>
        abonneer(DeviceModusService.actieveKringNotifier.value);

    controller = StreamController<Kring?>(
      onListen: () {
        DeviceModusService.actieveKringNotifier.addListener(onNotifier);
        abonneer(DeviceModusService.actieveKringNotifier.value);
      },
      onCancel: () async {
        DeviceModusService.actieveKringNotifier.removeListener(onNotifier);
        await docSub?.cancel();
        docSub = null;
      },
    );

    return controller.stream;
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

  /// Lichtgewicht variant van [mijnKringen] die alleen de kringIds
  /// teruggeeft — zonder de N extra kring-doc-reads. Gebruikt door
  /// [PushService.registreerHuidigApparaat] om het `kringId`-veld
  /// atomair mee te schrijven bij de fcmToken-update. Zelfde
  /// collectionGroup-query, zelfde rules/index-vereisten.
  static Future<List<String>> mijnKringIds(String uid) async {
    if (uid.isEmpty) return const [];
    try {
      final ledenSnap = await FirebaseFirestore.instance
          .collectionGroup('leden')
          .where('userUid', isEqualTo: uid)
          .get();
      return ledenSnap.docs
          .map((d) => d.reference.parent.parent?.id)
          .whereType<String>()
          .toList();
    } catch (e) {
      debugPrint('🌀 [KringService] mijnKringIds($uid) faalde: $e');
      return const [];
    }
  }
}
