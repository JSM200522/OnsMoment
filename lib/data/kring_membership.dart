/// Data-model voor de V9 auth-refactor. Nog niet geïntegreerd — wordt
/// in commit 1.1c pas door setup_wizard gebruikt. Beschrijft één
/// lidmaatschap in de kringen/{kringId}/leden/{userUid} subcollectie.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'kring.dart';

/// Membership van één persoon in één kring. Doc-pad:
/// kringen/{kringId}/leden/{userUid}
///
/// [userUid] wordt naast de doc-id ook als veld opgeslagen, zodat
/// collectionGroup('leden').where('userUid', isEqualTo: ...) mogelijk is
/// — nodig voor de "mijn kringen"-query in commit 1.1d.
class Membership {
  final String userUid;
  final AccountRol rol;
  final DateTime gejoindOp;
  final String? uitgenodigdDoor;

  /// V9 2.8-a-1: gedenormaliseerde weergavenaam, gevuld vanuit
  /// `gebruikers/{userUid}.familieNaam` op moment van membership-creatie.
  /// Voorkomt dat de kringleden-lijst per lid een cross-user
  /// gebruikers-doc-read moet doen. Null bij oudere memberships en bij
  /// accounts zonder familieNaam — UI valt dan terug op "Kringlid".
  final String? weergaveNaam;

  Membership({
    required this.userUid,
    required this.rol,
    required this.gejoindOp,
    this.uitgenodigdDoor,
    this.weergaveNaam,
  });

  /// Leest een membership-doc uit Firestore. Onbekende rol-strings
  /// vallen terug naar [AccountRol.gast] — veiligheid > backwards-compat
  /// bij corrupted data.
  factory Membership.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? const {};
    final rolStr = data['rol'] as String? ?? 'gast';
    AccountRol parsedRol;
    try {
      parsedRol = AccountRol.values.byName(rolStr);
    } catch (_) {
      parsedRol = AccountRol.gast;
    }
    return Membership(
      userUid: data['userUid'] as String? ?? doc.id,
      rol: parsedRol,
      gejoindOp: (data['gejoindOp'] as Timestamp?)?.toDate()
          ?? DateTime.fromMillisecondsSinceEpoch(0),
      uitgenodigdDoor: data['uitgenodigdDoor'] as String?,
      weergaveNaam: data['weergaveNaam'] as String?,
    );
  }

  /// Geeft een Map die je in Firestore kunt schrijven. [bijCreate]=true
  /// gebruikt FieldValue.serverTimestamp() voor gejoindOp — voorkomt
  /// clock-skew bij joinen via een uitnodigingslink. Na creatie wordt
  /// gejoindOp nooit meer aangeraakt; vandaar bijCreate i.p.v. bijUpdate.
  ///
  /// weergaveNaam wordt alleen geschreven als niet-null, zodat bestaande
  /// memberships die met merge==true worden bijgewerkt niet onbedoeld
  /// een leeg veld krijgen.
  Map<String, dynamic> toFirestoreMap({bool bijCreate = false}) {
    final map = <String, dynamic>{
      'userUid': userUid,
      'rol': rol.name,
      'gejoindOp': bijCreate
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(gejoindOp),
      'uitgenodigdDoor': uitgenodigdDoor,
    };
    if (weergaveNaam != null) map['weergaveNaam'] = weergaveNaam;
    return map;
  }
}
