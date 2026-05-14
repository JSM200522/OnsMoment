import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/moment.dart';

class MomentService {
  final _db = FirebaseFirestore.instance;

  // Stream van momenten voor de tablet van Jan
  // Alleen momenten die NU afgespeeld moeten worden
  Stream<List<Moment>> momentenVoorTablet(String tabletUid) {
    return _db
        .collection('momenten')
        .where('naarUid', isEqualTo: tabletUid)
        .where('afgespeeld', isEqualTo: false)
        .orderBy('geplandOp')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Moment.fromFirestore(d.data(), d.id))
            .where((m) => m.geplandOp.isBefore(DateTime.now()) ||
                m.geplandOp.difference(DateTime.now()).inSeconds < 60)
            .toList());
  }

  // Stream van ALLE momenten voor familie-overzicht
  Stream<List<Moment>> momentenVanFamilie(String familieUid) {
    return _db
        .collection('momenten')
        .where('vanUid', isEqualTo: familieUid)
        .orderBy('geplandOp', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Moment.fromFirestore(d.data(), d.id))
            .toList());
  }

  // Nieuw moment plannen (door familie)
  Future<String> momentPlannen(Moment moment) async {
    final ref = await _db.collection('momenten').add(moment.toFirestore());
    return ref.id;
  }

  // Markeer als afgespeeld (door tablet)
  Future<void> markeerAfgespeeld(String momentId) async {
    await _db.collection('momenten').doc(momentId).update({
      'afgespeeld': true,
      'afgespeeldOp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // Verwijder moment
  Future<void> verwijderMoment(String momentId) async {
    await _db.collection('momenten').doc(momentId).delete();
  }
}
