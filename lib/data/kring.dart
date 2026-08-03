/// Data-model voor de V9 auth-refactor. Nog niet geïntegreerd — wordt
/// in commit 1.1c pas door setup_wizard gebruikt. Dit bestand zet alleen
/// het schema vast zodat fromFirestore/toFirestoreMap klaarstaan.

import 'package:cloud_firestore/cloud_firestore.dart';

/// Rol van een persoon binnen een kring.
/// - eigenaar: kan ontvanger-info en leden bewerken
/// - gast:     kan momenten sturen, geen beheer
enum AccountRol { eigenaar, gast }

/// Data-model van één kring (V9 schema). De doc-id wordt apart in [id]
/// bewaard en hoort niet thuis in toFirestoreMap — Firestore beheert dat.
class Kring {
  // Type-constants voor 'type'-veld (vermijdt typo's bij callers)
  static const String TYPE_FAMILIE = 'familie';
  static const String TYPE_ZORG = 'zorg';

  // Modus-constants voor 'modus'-veld
  static const String MODUS_VERGRENDELD = 'vergrendeld';
  static const String MODUS_MELDINGEN = 'meldingen';

  final String id;
  final String naam;
  final String? foto;
  final String? lievelingsdingen;
  final String? woonplaats;
  final String? noodcontactNaam;
  final String? noodcontactTel;
  final String herkenningsgeluid;
  final String eigenaarUid;
  final DateTime aangemaaktOp;
  final DateTime laatsteUpdate;
  final String type;
  final String modus;
  /// V4: automatisch opnemen bij inkomend videogesprek. Default false.
  /// Alleen de kring-eigenaar mag dit zetten (Firestore-regel + UI-gate).
  final bool autoAnswer;

  Kring({
    required this.id,
    required this.naam,
    this.foto,
    this.lievelingsdingen,
    this.woonplaats,
    this.noodcontactNaam,
    this.noodcontactTel,
    this.herkenningsgeluid = 'twinkel',
    required this.eigenaarUid,
    required this.aangemaaktOp,
    required this.laatsteUpdate,
    this.type = TYPE_FAMILIE,
    this.modus = MODUS_VERGRENDELD,
    this.autoAnswer = false,
  });

  /// Leest een kring-doc uit Firestore. Robuust tegen ontbrekende velden
  /// (oude/gemigreerde docs krijgen defaults i.p.v. een crash).
  factory Kring.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? const {};
    return Kring(
      id: doc.id,
      naam: data['naam'] as String? ?? '',
      foto: data['foto'] as String?,
      lievelingsdingen: data['lievelingsdingen'] as String?,
      woonplaats: data['woonplaats'] as String?,
      noodcontactNaam: data['noodcontactNaam'] as String?,
      noodcontactTel: data['noodcontactTel'] as String?,
      herkenningsgeluid: data['herkenningsgeluid'] as String? ?? 'twinkel',
      eigenaarUid: data['eigenaarUid'] as String? ?? '',
      aangemaaktOp: (data['aangemaaktOp'] as Timestamp?)?.toDate()
          ?? DateTime.fromMillisecondsSinceEpoch(0),
      laatsteUpdate: (data['laatsteUpdate'] as Timestamp?)?.toDate()
          ?? DateTime.fromMillisecondsSinceEpoch(0),
      type: data['type'] as String? ?? TYPE_FAMILIE,
      modus: data['modus'] as String? ?? MODUS_VERGRENDELD,
      autoAnswer: data['autoAnswer'] as bool? ?? false,
    );
  }

  /// Geeft een Map die je in Firestore kunt schrijven. [bijUpdate]=true
  /// vervangt laatsteUpdate door FieldValue.serverTimestamp() — zo
  /// vermijd je clock-skew bij elke wijziging. aangemaaktOp blijft
  /// client-DateTime; de caller mag bij eerste write zelf serverTimestamp
  /// gebruiken (override na deze map).
  Map<String, dynamic> toFirestoreMap({bool bijUpdate = false}) {
    return {
      'naam': naam,
      'foto': foto,
      'lievelingsdingen': lievelingsdingen,
      'woonplaats': woonplaats,
      'noodcontactNaam': noodcontactNaam,
      'noodcontactTel': noodcontactTel,
      'herkenningsgeluid': herkenningsgeluid,
      'eigenaarUid': eigenaarUid,
      'aangemaaktOp': Timestamp.fromDate(aangemaaktOp),
      'laatsteUpdate': bijUpdate
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(laatsteUpdate),
      'type': type,
      'modus': modus,
      'autoAnswer': autoAnswer,
    };
  }
}
