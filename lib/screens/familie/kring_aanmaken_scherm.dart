import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/geluiden.dart';
import '../../services/kring_service.dart';
import '../../theme/kleuren.dart';

/// Scherm waarmee een ingelogde gebruiker een EXTRA kring kan aanmaken
/// vanuit Instellingen → "Nieuwe kring aanmaken" (V9 2.2a).
///
/// Schrijft de nieuwe kring + eigenaar-membership via
/// [KringService.voegKringMetEigenaarToeAanBatch] — atomic, zelfde
/// patroon als de signup-flow. Voegt ook 4 default dagelijkse momenten
/// toe zodat de kring direct gevuld voelt.
///
/// Na succesvolle aanmaak: snackbar + Navigator.pop(). De ACTIEVE kring
/// blijft de huidige — switchen wordt pas in 2.2b geïmplementeerd.
class KringAanmakenScherm extends StatefulWidget {
  const KringAanmakenScherm({super.key});

  @override
  State<KringAanmakenScherm> createState() => _KringAanmakenSchermState();
}

class _KringAanmakenSchermState extends State<KringAanmakenScherm> {
  final _naamCtrl = TextEditingController();
  final _lievelingsdingenCtrl = TextEditingController();
  final _woonplaatsCtrl = TextEditingController();

  Uint8List? _profielFotoBytes;
  String _gekozenGeluid = 'twinkel';
  bool _bezig = false;

  @override
  void initState() {
    super.initState();
    _naamCtrl.addListener(_herbouw);
  }

  void _herbouw() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _naamCtrl.removeListener(_herbouw);
    _naamCtrl.dispose();
    _lievelingsdingenCtrl.dispose();
    _woonplaatsCtrl.dispose();
    super.dispose();
  }

  Future<void> _kiesFoto() async {
    try {
      final foto = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (foto == null) return;
      final bytes = await foto.readAsBytes();
      if (mounted) setState(() => _profielFotoBytes = bytes);
    } catch (_) {}
  }

  Future<void> _opslaan() async {
    final naam = _naamCtrl.text.trim();
    if (naam.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _toonFout('Niet ingelogd — log opnieuw in.');
      return;
    }
    setState(() => _bezig = true);
    try {
      // KringId vooraf genereren zodat we de foto eronder kunnen opslaan.
      final kringId = KringService.genereerKringId();

      String fotoUrl = '';
      if (_profielFotoBytes != null) {
        try {
          final ref = FirebaseStorage.instance.ref()
              .child('profielfotos').child('$kringId.jpg');
          await ref.putData(_profielFotoBytes!,
              SettableMetadata(contentType: 'image/jpeg'));
          fotoUrl = await ref.getDownloadURL();
        } catch (_) {
          // Foto-faal niet blokkerend — kring wordt nog steeds aangemaakt.
        }
      }

      final batch = FirebaseFirestore.instance.batch();
      KringService.voegKringMetEigenaarToeAanBatch(
        batch: batch,
        kringId: kringId,
        eigenaarUid: uid,
        ontvangerNaam: naam,
        foto: fotoUrl,
        lievelingsdingen: _lievelingsdingenCtrl.text.trim(),
        woonplaats: _woonplaatsCtrl.text.trim(),
        herkenningsgeluid: _gekozenGeluid,
      );

      // 4 default dagelijkse momenten — zelfde lijst als de signup-flow.
      const defaults = [
        {'emoji': '☀️', 'label': 'Goedemorgen', 'uur': 8,  'minuut': 30},
        {'emoji': '☕', 'label': 'Tijd voor koffie', 'uur': 10, 'minuut': 0},
        {'emoji': '🍽️', 'label': 'Lunchtijd', 'uur': 12, 'minuut': 30},
        {'emoji': '🌙', 'label': 'Welterusten', 'uur': 20, 'minuut': 0},
      ];
      for (final m in defaults) {
        batch.set(
            FirebaseFirestore.instance.collection('dagelijkse_momenten').doc(),
            {
              'kringId': kringId,
              'emoji': m['emoji'],
              'label': m['label'],
              'uur': m['uur'],
              'minuut': m['minuut'],
              'mediaType': '',
              'mediaUrl': '',
              'tekstBericht': '',
              'actief': true,
              'aangemaaktOp': FieldValue.serverTimestamp(),
            });
      }

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Nieuwe kring "$naam" aangemaakt'),
        backgroundColor: kGreen));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _bezig = false);
        _toonFout('Aanmaken mislukt — probeer opnieuw.');
      }
    }
  }

  void _toonFout(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: kRood));
  }

  @override
  Widget build(BuildContext context) {
    final magOpslaan = _naamCtrl.text.trim().isNotEmpty && !_bezig;
    return Scaffold(
      backgroundColor: kCream,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: kBrown),
        title: const Text('Nieuwe kring aanmaken',
            style: TextStyle(color: kBrown, fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(children: [
          const Text('Voor wie maak je deze kring?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                  color: kBrown)),
          const SizedBox(height: 6),
          const Text('Bijvoorbeeld voor een andere ouder, oma of opa. Je '
              'kunt later via "Wissel van kring" tussen kringen heen en weer.',
              style: TextStyle(fontSize: 13, color: kTextMuted, height: 1.4)),
          const SizedBox(height: 20),

          _kop('📸 Foto (optioneel)'),
          const SizedBox(height: 8),
          Center(child: GestureDetector(
            onTap: _kiesFoto,
            child: Container(
              width: 110, height: 110,
              decoration: BoxDecoration(
                color: kPeachPale,
                shape: BoxShape.circle,
                border: Border.all(color: kPeach, width: 3),
                image: _profielFotoBytes != null
                    ? DecorationImage(image: MemoryImage(_profielFotoBytes!),
                        fit: BoxFit.cover)
                    : null,
              ),
              child: _profielFotoBytes == null
                  ? const Center(child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_rounded,
                            color: kPeach, size: 30),
                        SizedBox(height: 4),
                        Text('Kies foto',
                            style: TextStyle(fontSize: 11,
                                fontWeight: FontWeight.w800, color: kPeach)),
                      ]))
                  : null,
            ),
          )),
          if (_profielFotoBytes != null)
            Center(child: TextButton(
              onPressed: () => setState(() => _profielFotoBytes = null),
              child: const Text('Verwijderen',
                  style: TextStyle(color: kTextMuted, fontSize: 12)))),
          const SizedBox(height: 24),

          _kop('👵 Naam van je dierbare'),
          const SizedBox(height: 8),
          _input(_naamCtrl, 'Bijv. Oma, Opa, Mam, Pap...'),
          const SizedBox(height: 20),

          _kop('💕 Lievelingsdingen (optioneel)'),
          const SizedBox(height: 8),
          _input(_lievelingsdingenCtrl, 'Bijv. tulpen, koffie, oude foto\'s'),
          const SizedBox(height: 20),

          _kop('🏠 Vroegere woonplaats (optioneel)'),
          const SizedBox(height: 8),
          _input(_woonplaatsCtrl, 'Bijv. Volendam'),
          const SizedBox(height: 20),

          _kop('🔔 Herkenningsgeluid'),
          const SizedBox(height: 6),
          const Text('Klinkt elke keer als er iets nieuws aankomt.',
              style: TextStyle(fontSize: 12, color: kTextMuted)),
          const SizedBox(height: 10),
          ...kGeluiden.map((g) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => setState(() => _gekozenGeluid = g['id']!),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _gekozenGeluid == g['id'] ? kPeach : kWhite,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _gekozenGeluid == g['id'] ? kPeach : kPeachLight,
                      width: 2)),
                child: Row(children: [
                  Text(g['emoji']!, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(g['naam']!,
                      style: TextStyle(fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _gekozenGeluid == g['id']
                              ? kWhite : kBrown))),
                  if (_gekozenGeluid == g['id'])
                    const Icon(Icons.check_rounded, color: kWhite),
                ]),
              ),
            ),
          )),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: kPeachPale,
                borderRadius: BorderRadius.circular(10)),
            child: const Text(
              '💡 Er worden 4 standaard dagelijkse momenten meegemaakt '
              '(ochtend, koffie, lunch, avond). Die kun je later aanpassen '
              'via Instellingen → Momenten beheren.',
              style: TextStyle(fontSize: 12,
                  color: kBrownLight, height: 1.4)),
          ),
          const SizedBox(height: 24),

          Opacity(
            opacity: magOpslaan ? 1.0 : 0.5,
            child: GestureDetector(
              onTap: magOpslaan ? _opslaan : null,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [kPeach, kRose]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: kPeach.withOpacity(0.35),
                      blurRadius: 20, offset: const Offset(0, 8))]),
                child: Center(child: _bezig
                    ? const Row(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(
                                color: kWhite, strokeWidth: 3)),
                        SizedBox(width: 12),
                        Text('Aanmaken...',
                            style: TextStyle(fontSize: 16,
                                fontWeight: FontWeight.w800, color: kWhite)),
                      ])
                    : const Text('🪄 Kring aanmaken',
                        style: TextStyle(fontSize: 16,
                            fontWeight: FontWeight.w900, color: kWhite))),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ]),
      )),
    );
  }

  Widget _kop(String t) => Text(t,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
          color: kBrown));

  Widget _input(TextEditingController c, String hint) => TextField(
        controller: c,
        decoration: InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: kWhite,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kPeachLight, width: 1.5)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kPeachLight, width: 1.5)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kPeach, width: 2)),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
        ),
      );
}
