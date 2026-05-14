import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

class MediaService {
  final _storage = FirebaseStorage.instance;
  final _picker = ImagePicker();
  final _recorder = AudioRecorder();

  // ─── AUDIO OPNEMEN ──────────────────────────────────────────
  Future<void> startOpname() async {
    if (await _recorder.hasPermission()) {
      final dir = await getTemporaryDirectory();
      final pad = '${dir.path}/opname_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(), path: pad);
    }
  }

  Future<String?> stopOpname() async {
    return await _recorder.stop();
  }

  // ─── FOTO KIEZEN ────────────────────────────────────────────
  Future<File?> kiesFoto() async {
    final result = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80);
    return result != null ? File(result.path) : null;
  }

  // ─── VIDEO KIEZEN ───────────────────────────────────────────
  Future<File?> kiesVideo() async {
    final result = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 1));
    return result != null ? File(result.path) : null;
  }

  // ─── UPLOAD NAAR FIREBASE STORAGE ───────────────────────────
  Future<String> uploadMedia(File bestand, String type, String uid) async {
    final pad = 'momenten/$uid/$type/${DateTime.now().millisecondsSinceEpoch}';
    final ref = _storage.ref().child(pad);
    await ref.putFile(bestand);
    return await ref.getDownloadURL();
  }
}
