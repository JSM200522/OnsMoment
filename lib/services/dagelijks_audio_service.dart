import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Upload/verwijder-helpers voor de aangepaste audio per dagelijks moment.
/// Storage-pad: dagelijkse_audio/{kringId}/{momentId}.{webm|mp3}
class DagelijksAudioService {
  /// Upload bytes naar Storage en zet aangepasteAudioUrl/Type in het
  /// moment-doc. Probeert oude file met andere extensie eerst weg te halen.
  static Future<bool> upload({
    required String kringId,
    required String momentId,
    required Uint8List bytes,
    required String type,
    String collectie = 'dagelijkse_momenten',
  }) async {
    if (type != 'stem' && type != 'mp3') return false;
    try {
      final ext = type == 'stem' ? 'webm' : 'mp3';
      final mime = type == 'stem' ? 'audio/webm' : 'audio/mpeg';
      await _verwijderBestaand(kringId, momentId);
      final ref = FirebaseStorage.instance.ref()
          .child('dagelijkse_audio')
          .child(kringId).child('$momentId.$ext');
      await ref.putData(bytes, SettableMetadata(contentType: mime));
      final url = await ref.getDownloadURL();
      await FirebaseFirestore.instance.collection(collectie)
          .doc(momentId).update({
        'aangepasteAudioUrl': url,
        'aangepasteAudioType': type,
        'aangepasteAudioUploadedOp': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Verwijdert audio uit Storage en reset de doc-velden naar standaard bel.
  static Future<bool> reset({
    required String kringId,
    required String momentId,
    String collectie = 'dagelijkse_momenten',
  }) async {
    try {
      await _verwijderBestaand(kringId, momentId);
      await FirebaseFirestore.instance.collection(collectie)
          .doc(momentId).update({
        'aangepasteAudioUrl': FieldValue.delete(),
        'aangepasteAudioType': FieldValue.delete(),
        'aangepasteAudioUploadedOp': FieldValue.delete(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _verwijderBestaand(
      String kringId, String momentId) async {
    for (final ext in ['webm', 'mp3']) {
      try {
        await FirebaseStorage.instance.ref()
            .child('dagelijkse_audio')
            .child(kringId).child('$momentId.$ext').delete();
      } catch (_) {}
    }
  }
}
