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

  Membership({
    required this.userUid,
    required this.rol,
    required this.gejoindOp,
    this.uitgenodigdDoor,
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
    );
  }

  /// Geeft een Map die je in Firestore kunt schrijven. [bijCreate]=true
  /// gebruikt FieldValue.serverTimestamp() voor gejoindOp — voorkomt
  /// clock-skew bij joinen via een uitnodigingslink. Na creatie wordt
  /// gejoindOp nooit meer aangeraakt; vandaar bijCreate i.p.v. bijUpdate.
  Map<String, dynamic> toFirestoreMap({bool bijCreate = false}) {
    return {
      'userUid': userUid,
      'rol': rol.name,
      'gejoindOp': bijCreate
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(gejoindOp),
      'uitgenodigdDoor': uitgenodigdDoor,
    };
  }
}
