import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import '../../data/geluiden.dart';
import '../../services/apparaat_service.dart';
import '../../services/device_modus_service.dart';
import '../../services/kring_service.dart';
import '../../theme/kleuren.dart';
import '../../widgets/normaal_scaffold.dart';
import 'pakket_keuze_scherm.dart';

/// Scherm waarmee een ingelogde gebruiker een EXTRA kring kan aanmaken
/// vanuit Instellingen → "Nieuwe kring aanmaken" (V9 2.2a + 2.2a-fix).
///
/// Layout is 1-op-1 overgenomen van de ontvanger-profiel-stap in
/// setup_wizard (de stap "Vertel ons over je dierbare"), inclusief
/// _sectieKop, _input, foto-picker, geluid-preview en spacing — zodat
/// een tweede-keer-aanmaker exact dezelfde flow herkent als de signup.
///
/// Schrijft kring + eigenaar-membership via
/// [KringService.voegKringMetEigenaarToeAanBatch] in een atomic
/// WriteBatch, samen met 4 default dagelijkse momenten.
///
/// Na succes: snackbar + Navigator.pop(). De ACTIEVE kring blijft de
/// huidige — switchen komt in 2.2b.
class KringAanmakenScherm extends StatefulWidget {
  const KringAanmakenScherm({super.key});

  @override
  State<KringAanmakenScherm> createState() => _KringAanmakenSchermState();
}

class _KringAanmakenSchermState extends State<KringAanmakenScherm> {
  final _naamCtrl = TextEditingController();
  final _noodNaamCtrl = TextEditingController();
  final _noodTelCtrl = TextEditingController();

  Uint8List? _profielFotoBytes;
  String _gekozenGeluid = 'twinkel';
  bool _bezig = false;

  final _geluidPreviewPlayer = AudioPlayer();

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
    _noodNaamCtrl.dispose();
    _noodTelCtrl.dispose();
    _geluidPreviewPlayer.dispose();
    super.dispose();
  }

  Future<void> _kiesProfielFoto() async {
    try {
      final picker = ImagePicker();
      final foto = await picker.pickImage(source: ImageSource.gallery,
          maxWidth: 1200, imageQuality: 85);
      if (foto != null) {
        final bytes = await foto.readAsBytes();
        if (mounted) setState(() => _profielFotoBytes = bytes);
      }
    } catch (_) {}
  }

  Future<void> _speelGeluidPreview(String pad) async {
    try {
      await _geluidPreviewPlayer.stop();
      await _geluidPreviewPlayer.setAsset(pad);
      await _geluidPreviewPlayer.play();
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
      // Kring-limiet: tel eigen kringen vóór de write
      final tier = await ApparaatService.krijgTier(uid);
      final maxKringen = ApparaatService.kringLimietPerTier(tier);
      final ledenSnap = await FirebaseFirestore.instance
          .collectionGroup('leden')
          .where('userUid', isEqualTo: uid)
          .get();
      final aantalEigenKringen = ledenSnap.docs
          .where((d) => d.data()['rol'] == 'eigenaar')
          .length;
      if (aantalEigenKringen >= maxKringen) {
        if (mounted) setState(() => _bezig = false);
        _toonLimietMelding(maxKringen, tier);
        return;
      }

      final kringId = KringService.genereerKringId();

      String fotoUrl = '';
      if (_profielFotoBytes != null) {
        try {
          final ref = FirebaseStorage.instance.ref()
              .child('profielfotos').child('$kringId.jpg');
          await ref.putData(_profielFotoBytes!,
              SettableMetadata(contentType: 'image/jpeg'));
          fotoUrl = await ref.getDownloadURL();
        } catch (_) {}
      }

      // V9 2.8-a-1: lees eigen familieNaam zodat eigenaar-leden-doc
      // het weergaveNaam-veld krijgt (denormalisatie voor kringleden-
      // lijst). Tegelijk checken of proefStart ontbreekt (gast-signup
      // schrijft dat niet — pas bij eigenaar-worden is de 14-dagen
      // teller relevant). Eigen uid -> geen cross-user issue. Fail-soft.
      String eigenaarNaam = '';
      bool proefStartOntbreekt = false;
      try {
        final eigenDoc = await FirebaseFirestore.instance
            .collection('gebruikers').doc(uid).get();
        final data = eigenDoc.data();
        final n = data?['familieNaam'] as String?;
        if (n != null && n.isNotEmpty) eigenaarNaam = n;
        // Alleen zetten als veld ontbreekt — bestaande proef mag niet
        // gereset worden door aanmaak van een extra kring (Groot-tier).
        proefStartOntbreekt = data?['proefStart'] == null;
      } catch (_) {}

      final batch = FirebaseFirestore.instance.batch();
      KringService.voegKringMetEigenaarToeAanBatch(
        batch: batch,
        kringId: kringId,
        eigenaarUid: uid,
        ontvangerNaam: naam,
        foto: fotoUrl,
        noodcontactNaam: _noodNaamCtrl.text.trim(),
        noodcontactTel: _noodTelCtrl.text.trim(),
        herkenningsgeluid: _gekozenGeluid,
        eigenaarNaam: eigenaarNaam,
      );
      // Server-side teller: Firestore-rules checken kringAantal < tierLimit.
      // proefStart-backfill voor gast-die-eigenaar-wordt zodat het
      // PakketKeuzeScherm de 14-dagen teller kan tonen en de trial-lock
      // (FASE C) niet direct dichtklapt.
      final gebruikersUpdate = <String, Object>{
        'kringAantal': FieldValue.increment(1),
      };
      if (proefStartOntbreekt) {
        gebruikersUpdate['proefStart'] = FieldValue.serverTimestamp();
      }
      batch.update(
          FirebaseFirestore.instance.collection('gebruikers').doc(uid),
          gebruikersUpdate);

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

      // V9 2.2b: switch direct naar de nieuwe kring. De notifier in
      // DeviceModusService triggert _FamilieSchermState + NotitiesTab om
      // hun kringId-listeners te herstarten.
      await DeviceModusService.zetActieveKring(kringId);

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

  void _toonLimietMelding(int max, String tier) {
    final maxTekst = max == 1 ? '1 kring' : '$max kringen';
    final isPro = tier == 'groot' || tier == 'zorg';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCream,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Kring-limiet bereikt',
            style: TextStyle(color: kBrown, fontWeight: FontWeight.w900)),
        content: Text(
          'Met je huidige pakket kun je maximaal $maxTekst aanmaken.'
          '${isPro ? '' : '\n\nWil je meer kringen? Bekijk onze pakketten.'}',
          style: const TextStyle(color: kBrown, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Sluiten',
                style: TextStyle(color: kTextMuted))),
          if (!isPro)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                PakketKeuzeScherm.toon(context);
              },
              child: const Text('Pakketten bekijken →',
                  style: TextStyle(
                      color: kPeach, fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }

  void _toonFout(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: kRood));
  }

  @override
  Widget build(BuildContext context) {
    final magOpslaan = _naamCtrl.text.trim().isNotEmpty && !_bezig;
    return NormaalScaffold(
      backgroundColor: kCream,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: kBrown),
        title: const Text('Nieuwe kring aanmaken',
            style: TextStyle(color: kBrown, fontWeight: FontWeight.w900)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(children: [
          const Text('Vertel ons over je dierbare',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
                  color: kBrown, height: 1.2)),
          const SizedBox(height: 8),
          const Text('Hoe meer je vertelt, hoe persoonlijker de app voelt. '
              'Alles is optioneel — je kunt altijd later aanpassen in '
              'Instellingen.',
              style: TextStyle(fontSize: 14, color: kTextMuted, height: 1.4)),
          const SizedBox(height: 24),

          _sectieKop('📸 Achtergrondfoto',
              'Kies een mooie foto van je dierbare. Deze foto wordt de '
              'sfeervolle achtergrond op het home-scherm van het '
              'ontvanger-apparaat.'),
          const SizedBox(height: 12),
          Center(child: GestureDetector(
            onTap: _kiesProfielFoto,
            child: Container(width: 120, height: 120,
              decoration: BoxDecoration(
                color: kPeachPale, shape: BoxShape.circle,
                border: Border.all(color: kPeach, width: 3),
                image: _profielFotoBytes != null ? DecorationImage(
                  image: MemoryImage(_profielFotoBytes!),
                  fit: BoxFit.cover) : null,
                boxShadow: [BoxShadow(color: kPeach.withOpacity(0.2),
                    blurRadius: 16, offset: const Offset(0, 4))]),
              child: _profielFotoBytes == null
                ? const Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_rounded, color: kPeach, size: 32),
                    SizedBox(height: 4),
                    Text('Kies foto', style: TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w800, color: kPeach)),
                  ])) : null,
            ),
          )),
          if (_profielFotoBytes != null) Center(child: TextButton(
            onPressed: () => setState(() => _profielFotoBytes = null),
            child: const Text('Verwijderen',
                style: TextStyle(color: kTextMuted, fontSize: 12)))),
          const SizedBox(height: 24),

          _sectieKop('👤 Naam en noodcontact',
              'De naam staat op het home-scherm. Noodcontact is optioneel.'),
          const SizedBox(height: 12),
          _input('👵', 'Naam van je dierbare',
              'Bijv. Oma, Opa, Mam, Pap...',
              _naamCtrl, false),
          const SizedBox(height: 6),
          const Text('Zo verschijnt zijn/haar naam in de app en bij berichten.',
              style: TextStyle(fontSize: 12, color: kTextMuted, height: 1.4)),
          const SizedBox(height: 10),
          _input('🆘', 'Noodcontact naam (optioneel)',
              'Bijv. Dochter Sara', _noodNaamCtrl, false),
          const SizedBox(height: 10),
          _input('☎️', 'Noodcontact telefoon (optioneel)',
              '06...', _noodTelCtrl, false),
          const SizedBox(height: 24),

          _sectieKop('🔔 Herkenningsgeluid',
              'Klinkt elke keer als er iets nieuws aankomt. Tik op een geluid '
              'om het voor te beluisteren. Helpt je dierbare het te herkennen '
              'als iets liefs.'),
          const SizedBox(height: 12),
          ...kGeluiden.map((g) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () {
                setState(() => _gekozenGeluid = g['id']!);
                _speelGeluidPreview(g['asset']!);
              },
              child: Container(padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _gekozenGeluid == g['id'] ? kPeach : kWhite,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _gekozenGeluid == g['id']
                      ? kPeach : kPeachLight, width: 2)),
                child: Row(children: [
                  Text(g['emoji']!, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(g['naam']!,
                      style: TextStyle(fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _gekozenGeluid == g['id']
                              ? kWhite : kBrown))),
                  Icon(Icons.play_circle_outline_rounded,
                      color: _gekozenGeluid == g['id'] ? kWhite : kPeach,
                      size: 24),
                ]),
              ),
            ),
          )),
          const SizedBox(height: 12),

          Container(padding: const EdgeInsets.all(12),
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
      ),
    );
  }

  /// 1-op-1 overgenomen uit setup_wizard._sectieKop (L501-508).
  Widget _sectieKop(String titel, String uitleg) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titel, style: const TextStyle(fontSize: 16,
          fontWeight: FontWeight.w900, color: kBrown)),
      const SizedBox(height: 4),
      Text(uitleg, style: const TextStyle(fontSize: 12,
          color: kTextMuted, height: 1.4)),
    ]);

  /// 1-op-1 overgenomen uit setup_wizard._input (L1007-1025).
  Widget _input(String emoji, String label, String hint,
      TextEditingController ctrl, bool verborgen) =>
      Container(
        decoration: BoxDecoration(color: kWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kPeachLight, width: 2)),
        child: Row(children: [
          Padding(padding: const EdgeInsets.only(left: 16),
              child: Text(emoji, style: const TextStyle(fontSize: 20))),
          Expanded(child: TextField(controller: ctrl, obscureText: verborgen,
            style: const TextStyle(color: kBrown, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: hint, labelText: label,
              labelStyle: const TextStyle(color: kTextMuted, fontSize: 12),
              hintStyle: const TextStyle(color: kPeachLight),
              contentPadding: const EdgeInsets.fromLTRB(12, 16, 16, 16),
              border: InputBorder.none))),
        ]),
      );
}
