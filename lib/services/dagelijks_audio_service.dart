import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Upload/verwijder-helpers voor de aangepaste audio per dagelijks moment.
/// Storage-pad: dagelijkse_audio/{kringId}/{momentId}.{webm|m4a|mp3}
class DagelijksAudioService {
  /// Upload bytes naar Storage en zet aangepasteAudioUrl/Type in het
  /// moment-doc. Geeft de download-URL terug, of null bij een fout.
  static Future<String?> upload({
    required String kringId,
    required String momentId,
    required Uint8List bytes,
    required String type,
    String collectie = 'dagelijkse_momenten',
  }) async {
    if (type != 'stem' && type != 'mp3') return null;
    try {
      final String ext;
      final String mime;
      if (type == 'stem') {
        ext = kIsWeb ? 'webm' : 'm4a';
        mime = kIsWeb ? 'audio/webm' : 'audio/mp4';
      } else {
        ext = 'mp3';
        mime = 'audio/mpeg';
      }
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
      return url;
    } catch (_) {
      return null;
    }
  }

  /// Verwijdert audio uit Storage en reset de doc-velden naar standaard geluid.
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
    for (final ext in ['webm', 'm4a', 'mp3']) {
      try {
        await FirebaseStorage.instance.ref()
            .child('dagelijkse_audio')
            .child(kringId).child('$momentId.$ext').delete();
      } catch (_) {}
    }
  }
}
