import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

const Color kPeach      = Color(0xFFFF9B71);
const Color kPeachLight = Color(0xFFFFD4C2);
const Color kPeachPale  = Color(0xFFFFF0EA);
const Color kRose       = Color(0xFFFF7B9C);
const Color kCream      = Color(0xFFFFFAF7);
const Color kBrown      = Color(0xFF5C3D2E);
const Color kBrownLight = Color(0xFF8B6354);
const Color kTextMuted  = Color(0xFF9B7565);
const Color kWhite      = Color(0xFFFFFFFF);
const Color kGreen      = Color(0xFF4CAF82);

class SetupWizard extends StatefulWidget {
  const SetupWizard({super.key});
  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  int _stap = 0;
  String _rol = '';
  bool _isInloggen = false;
  bool _bezig = false;

  final _naamCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _wachtwoordCtrl = TextEditingController();
  final _ontvangerNaamCtrl = TextEditingController();

  Uint8List? _profielFotoBytes;
  String _profielFotoNaam = '';

  final List<_DagelijksMoment> _momenten = [
    _DagelijksMoment('☀️', 'Goedemorgen', const TimeOfDay(hour: 8, minute: 30)),
    _DagelijksMoment('☕', 'Tijd voor koffie', const TimeOfDay(hour: 10, minute: 0)),
    _DagelijksMoment('🍽️', 'Lunchtijd', const TimeOfDay(hour: 12, minute: 30)),
    _DagelijksMoment('🌙', 'Welterusten', const TimeOfDay(hour: 20, minute: 0)),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_stap > 0) _topBalk(),
            Expanded(child: SingleChildScrollView(child: _huidigeStap())),
            const SizedBox(height: 12),
            if (_stap > 0) _knop(),
          ]),
        ),
      ),
    );
  }

  Widget _topBalk() {
    final maxStappen = _rol == 'familie' && !_isInloggen ? 3 : 2;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        GestureDetector(
          onTap: _terug,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kPeachPale,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_back_rounded, color: kBrown, size: 20),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Row(children: List.generate(maxStappen, (i) => Expanded(
          child: Container(margin: const EdgeInsets.only(right: 4),
            height: 4, decoration: BoxDecoration(
              color: i < _stap ? kPeach : kPeachLight,
              borderRadius: BorderRadius.circular(2))),
        )))),
      ]),
      const SizedBox(height: 8),
      Text('Stap $_stap van $maxStappen',
          style: const TextStyle(fontSize: 11,
              fontWeight: FontWeight.w800, color: kPeach, letterSpacing: 0.8)),
      const SizedBox(height: 16),
    ]);
  }

  void _terug() {
    if (_stap > 0) {
      setState(() {
        _stap--;
        if (_stap == 0) {
          _rol = '';
          _isInloggen = false;
        }
      });
    }
  }

  Widget _huidigeStap() {
    if (_stap == 0) return _rolKeuze();
    if (_rol == 'familie') {
      if (_stap == 1) return _familieAccount();
      if (_stap == 2 && !_isInloggen) return _momentenInstellen();
    } else {
      if (_stap == 1) return _ontvangerInloggen();
    }
    return _klaarScherm();
  }

  Widget _rolKeuze() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const SizedBox(height: 40),
    const Text('💕', style: TextStyle(fontSize: 48)),
    const SizedBox(height: 16),
    const Text('Welkom bij\nOns Moment',
        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900,
            color: kBrown, height: 1.2)),
    const SizedBox(height: 12),
    const Text('Hoe ga je deze app gebruiken?',
        style: TextStyle(fontSize: 16, color: kTextMuted)),
    const SizedBox(height: 32),
    _rolKaart('👨‍👩‍👧 Familie of mantelzorger',
      'Ik stuur foto\'s, stemberichtjes en herinneringen naar mijn dierbare',
      () => setState(() { _rol = 'familie'; _stap = 1; })),
    const SizedBox(height: 14),
    _rolKaart('👵 Ontvanger',
      'Ik gebruik dit apparaat om berichten van familie te zien en horen',
      () => setState(() { _rol = 'ontvanger'; _stap = 1; })),
  ]);

  Widget _rolKaart(String titel, String tekst, VoidCallback onTap) =>
    GestureDetector(onTap: onTap, child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: kWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kPeachLight, width: 2),
        boxShadow: [BoxShadow(color: kPeach.withOpacity(0.1),
            blurRadius: 16, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titel, style: const TextStyle(fontSize: 16,
            fontWeight: FontWeight.w800, color: kBrown)),
        const SizedBox(height: 6),
        Text(tekst, style: const TextStyle(fontSize: 13,
            color: kBrownLight, height: 1.4)),
        const SizedBox(height: 10),
        const Row(children: [
          Text('Kies dit', style: TextStyle(fontSize: 12,
              fontWeight: FontWeight.w800, color: kPeach)),
          SizedBox(width: 4),
          Text('→', style: TextStyle(fontSize: 14, color: kPeach)),
        ]),
      ]),
    ));

  Widget _familieAccount() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(_isInloggen ? 'Welkom terug 👋' : 'Maak je account aan',
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
            color: kBrown, height: 1.2)),
    const SizedBox(height: 8),
    Text(_isInloggen ? 'Log in met je e-mail en wachtwoord'
        : 'Eerst maak je een account, daarna kies je voor wie je dit instelt',
        style: const TextStyle(fontSize: 14, color: kTextMuted)),
    const SizedBox(height: 24),
    if (!_isInloggen) ...[
      _input('👤', 'Jouw naam', 'Sara', _naamCtrl, false),
      const SizedBox(height: 10),
    ],
    _input('📧', 'E-mailadres', 'sara@email.nl', _emailCtrl, false),
    const SizedBox(height: 10),
    _input('🔒', 'Wachtwoord', 'Minimaal 6 tekens', _wachtwoordCtrl, true),
    const SizedBox(height: 16),
    GestureDetector(
      onTap: () => setState(() => _isInloggen = !_isInloggen),
      child: Center(child: Text(
        _isInloggen ? 'Nog geen account? Maak er een aan'
            : 'Al een account? Log in',
        style: const TextStyle(fontSize: 13,
            fontWeight: FontWeight.w800, color: kPeach,
            decoration: TextDecoration.underline))),
    ),
  ]);

  Widget _momentenInstellen() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Voor wie?',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
            color: kBrown, height: 1.2)),
    const SizedBox(height: 8),
    const Text('Vertel ons over je dierbare. Profielfoto en momenten zijn '
        'optioneel — je kunt altijd later aanpassen in Instellingen.',
        style: TextStyle(fontSize: 14, color: kTextMuted, height: 1.4)),
    const SizedBox(height: 20),
    // PROFIELFOTO
    Center(child: GestureDetector(
      onTap: _kiesProfielFoto,
      child: Container(
        width: 100, height: 100,
        decoration: BoxDecoration(
          color: kPeachPale,
          shape: BoxShape.circle,
          border: Border.all(color: kPeach, width: 3),
          image: _profielFotoBytes != null ? DecorationImage(
            image: MemoryImage(_profielFotoBytes!),
            fit: BoxFit.cover,
          ) : null,
        ),
        child: _profielFotoBytes == null
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center,
            children: [
            Icon(Icons.add_a_photo_rounded, color: kPeach, size: 28),
            SizedBox(height: 4),
            Text('Foto', style: TextStyle(fontSize: 10,
                fontWeight: FontWeight.w800, color: kPeach)),
          ]))
          : null,
      ),
    )),
    const SizedBox(height: 8),
    Center(child: Text(_profielFotoBytes == null
        ? 'Tik om profielfoto te kiezen (optioneel)'
        : 'Profielfoto gekozen — tik om aan te passen',
        style: const TextStyle(fontSize: 11, color: kTextMuted))),
    const SizedBox(height: 20),
    _input('👵', 'Naam ontvanger', 'Jan', _ontvangerNaamCtrl, false),
    const SizedBox(height: 20),
    const Text('DAGELIJKSE MOMENTEN',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
            color: kTextMuted, letterSpacing: 0.8)),
    const SizedBox(height: 8),
    if (_momenten.isEmpty)
      Container(padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: kPeachPale,
            borderRadius: BorderRadius.circular(14)),
        child: const Text('Nog geen momenten. Tik op + om er een toe te voegen, '
            'of sla deze stap over.',
            style: TextStyle(fontSize: 13, color: kBrownLight, height: 1.4))),
    ..._momenten.asMap().entries.map((e) => _momentRij(e.key, e.value)),
    const SizedBox(height: 8),
    GestureDetector(
      onTap: _voegMomentToe,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: kPeachPale,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kPeach, width: 1.5)),
        child: const Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add_rounded, color: kPeach, size: 18),
          SizedBox(width: 4),
          Text('Moment toevoegen', style: TextStyle(fontSize: 13,
              fontWeight: FontWeight.w800, color: kPeach)),
        ])),
      ),
    ),
    const SizedBox(height: 16),
    Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kPeachPale,
          borderRadius: BorderRadius.circular(12)),
      child: const Row(children: [
        Text('💡', style: TextStyle(fontSize: 18)),
        SizedBox(width: 10),
        Expanded(child: Text(
          'Media (foto/stem/lied) koppel je later in de Familie-app per moment. '
          'Een leeg moment is ook prima — dan verschijnt alleen de tijd-melding.',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
              color: kBrownLight, height: 1.4))),
      ])),
  ]);

  Future<void> _kiesProfielFoto() async {
    try {
      final picker = ImagePicker();
      final foto = await picker.pickImage(source: ImageSource.gallery,
          maxWidth: 800, imageQuality: 85);
      if (foto != null) {
        final bytes = await foto.readAsBytes();
        setState(() {
          _profielFotoBytes = bytes;
          _profielFotoNaam = foto.name;
        });
      }
    } catch (e) {
      _toonFout('Foto kiezen niet mogelijk: $e');
    }
  }

  Widget _momentRij(int index, _DagelijksMoment m) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(color: kWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kPeachLight, width: 2)),
    child: Row(children: [
      Text(m.emoji, style: const TextStyle(fontSize: 22)),
      const SizedBox(width: 10),
      Expanded(child: Text(m.label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
              color: kBrown))),
      GestureDetector(
        onTap: () => _kiesTijd(index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: kPeachPale,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kPeach, width: 1.5)),
          child: Text(_formatTijd(m.tijd),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                  color: kBrown)),
        ),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: () => setState(() => _momenten.removeAt(index)),
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: Icon(Icons.close_rounded, color: kTextMuted, size: 18),
        ),
      ),
    ]),
  );

  void _voegMomentToe() async {
    final result = await showDialog<_DagelijksMoment>(
      context: context,
      builder: (ctx) => _NieuwMomentDialog(),
    );
    if (result != null) setState(() => _momenten.add(result));
  }

  Future<void> _kiesTijd(int index) async {
    final gekozen = await showTimePicker(
      context: context,
      initialTime: _momenten[index].tijd,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (gekozen != null) setState(() => _momenten[index].tijd = gekozen);
  }

  String _formatTijd(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _ontvangerInloggen() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Log in op dit apparaat',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
            color: kBrown, height: 1.2)),
    const SizedBox(height: 8),
    const Text('Vraag je familielid om de inloggegevens. Zodra je inlogt, '
        'opent de app altijd in ontvanger-modus.',
        style: TextStyle(fontSize: 14, color: kTextMuted, height: 1.4)),
    const SizedBox(height: 24),
    _input('📧', 'E-mailadres ontvanger', '', _emailCtrl, false),
    const SizedBox(height: 10),
    _input('🔒', 'Wachtwoord', '', _wachtwoordCtrl, true),
  ]);

  Widget _klaarScherm() => const Column(children: [
    SizedBox(height: 60),
    Text('🎉', style: TextStyle(fontSize: 56)),
    SizedBox(height: 16),
    Text('Klaar!', style: TextStyle(fontSize: 32,
        fontWeight: FontWeight.w900, color: kBrown)),
  ]);

  Widget _knop() => GestureDetector(
    onTap: _bezig ? null : _volgende,
    child: Container(
      width: double.infinity, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [kPeach, kRose]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: kPeach.withOpacity(0.35),
            blurRadius: 20, offset: const Offset(0, 8))]),
      child: Center(child: _bezig
          ? const CircularProgressIndicator(color: kWhite)
          : Text(_knopTekst(),
              style: const TextStyle(fontSize: 16,
                  fontWeight: FontWeight.w800, color: kWhite))),
    ),
  );

  String _knopTekst() {
    if (_rol == 'familie' && _isInloggen && _stap == 1) return 'Inloggen';
    if (_rol == 'familie' && !_isInloggen && _stap == 1) return 'Volgende →';
    if (_rol == 'familie' && !_isInloggen && _stap == 2) return '✨ App starten!';
    if (_rol == 'ontvanger' && _stap == 1) return 'Inloggen';
    return 'Volgende →';
  }

  Future<void> _volgende() async {
    if (_rol == 'familie' && _stap == 1) {
      if (_isInloggen) {
        await _familieInloggen();
      } else {
        if (_naamCtrl.text.trim().isEmpty ||
            _emailCtrl.text.trim().isEmpty ||
            _wachtwoordCtrl.text.length < 6) {
          _toonFout('Vul alle velden in (wachtwoord min. 6 tekens)');
          return;
        }
        setState(() => _stap = 2);
      }
    } else if (_rol == 'familie' && _stap == 2 && !_isInloggen) {
      if (_ontvangerNaamCtrl.text.trim().isEmpty) {
        _toonFout('Vul de naam van de ontvanger in');
        return;
      }
      await _familieRegistreren();
    } else if (_rol == 'ontvanger' && _stap == 1) {
      await _ontvangerInloggenActie();
    }
  }

  Future<void> _familieInloggen() async {
    setState(() => _bezig = true);
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailCtrl.text.trim(), password: _wachtwoordCtrl.text);
      await FirebaseFirestore.instance.collection('gebruikers')
          .doc(cred.user!.uid).set({'rol': 'familie'}, SetOptions(merge: true));
    } catch (e) {
      _toonFout('Inloggen mislukt. Klopt e-mail en wachtwoord?');
    } finally {
      if (mounted) setState(() => _bezig = false);
    }
  }

  Future<void> _familieRegistreren() async {
    setState(() => _bezig = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailCtrl.text.trim(), password: _wachtwoordCtrl.text);
      final ontvangerUid = 'ontvanger_${cred.user!.uid}';

      // Profielfoto uploaden indien gekozen
      String profielFotoUrl = '';
      if (_profielFotoBytes != null) {
        try {
          final ref = FirebaseStorage.instance.ref()
              .child('profielfotos').child('${ontvangerUid}.jpg');
          await ref.putData(_profielFotoBytes!,
              SettableMetadata(contentType: 'image/jpeg'));
          profielFotoUrl = await ref.getDownloadURL();
        } catch (e) {
          // Negeer fout - profielfoto is optioneel
        }
      }

      await FirebaseFirestore.instance
          .collection('gebruikers').doc(cred.user!.uid).set({
        'naam': _naamCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'rol': 'familie',
        'ontvangerUid': ontvangerUid,
        'ontvangerNaam': _ontvangerNaamCtrl.text.trim(),
        'ontvangerProfielFoto': profielFotoUrl,
        'aangemaaktOp': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('gebruikers').doc(ontvangerUid).set({
        'naam': _ontvangerNaamCtrl.text.trim(),
        'rol': 'tablet',
        'familieUid': cred.user!.uid,
        'profielFoto': profielFotoUrl,
        'aangemeldOp': FieldValue.serverTimestamp(),
      });

      for (final m in _momenten) {
        await FirebaseFirestore.instance.collection('dagelijkse_momenten').add({
          'naarUid': ontvangerUid,
          'vanUid': cred.user!.uid,
          'emoji': m.emoji,
          'label': m.label,
          'uur': m.tijd.hour,
          'minuut': m.tijd.minute,
          'mediaType': '',
          'mediaUrl': '',
          'tekstBericht': '',
          'actief': true,
          'aangemaaktOp': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      _toonFout('Account aanmaken mislukt: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _bezig = false);
    }
  }

  Future<void> _ontvangerInloggenActie() async {
    setState(() => _bezig = true);
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailCtrl.text.trim(), password: _wachtwoordCtrl.text);
      await FirebaseFirestore.instance.collection('gebruikers')
          .doc(cred.user!.uid).set({'rol': 'tablet'}, SetOptions(merge: true));
    } catch (e) {
      _toonFout('Inloggen mislukt: vraag familie naar de juiste gegevens');
    } finally {
      if (mounted) setState(() => _bezig = false);
    }
  }

  void _toonFout(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.red));

  Widget _input(String emoji, String label, String hint,
      TextEditingController ctrl, bool verborgen) =>
      Container(
        decoration: BoxDecoration(color: kWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kPeachLight, width: 2)),
        child: Row(children: [
          Padding(padding: const EdgeInsets.only(left: 16),
              child: Text(emoji, style: const TextStyle(fontSize: 20))),
          Expanded(child: TextField(
            controller: ctrl, obscureText: verborgen,
            style: const TextStyle(color: kBrown, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: hint, labelText: label,
              labelStyle: const TextStyle(color: kTextMuted, fontSize: 12),
              hintStyle: const TextStyle(color: kPeachLight),
              contentPadding: const EdgeInsets.fromLTRB(12, 16, 16, 16),
              border: InputBorder.none),
          )),
        ]),
      );
}

class _DagelijksMoment {
  String emoji;
  String label;
  TimeOfDay tijd;
  _DagelijksMoment(this.emoji, this.label, this.tijd);
}

class _NieuwMomentDialog extends StatefulWidget {
  @override
  State<_NieuwMomentDialog> createState() => _NieuwMomentDialogState();
}

class _NieuwMomentDialogState extends State<_NieuwMomentDialog> {
  String _emoji = '⭐';
  final _labelCtrl = TextEditingController();
  TimeOfDay _tijd = const TimeOfDay(hour: 15, minute: 0);
  final _emojis = ['⭐', '☀️', '☕', '🍽️', '🌙', '💕', '🎵', '🌸', '🌳', '📚', '🐦', '🍰'];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kCream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Nieuw moment toevoegen',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                  color: kBrown)),
          const SizedBox(height: 16),
          const Text('Kies een emoji', style: TextStyle(fontSize: 12,
              color: kTextMuted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _emojis.map((e) =>
            GestureDetector(
              onTap: () => setState(() => _emoji = e),
              child: Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _emoji == e ? kPeach : kPeachPale,
                  borderRadius: BorderRadius.circular(8)),
                child: Text(e, style: const TextStyle(fontSize: 20)),
              ),
            )).toList()),
          const SizedBox(height: 16),
          TextField(
            controller: _labelCtrl,
            decoration: const InputDecoration(
              labelText: 'Naam (bijv. Wandeling)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            const Text('Tijd:', style: TextStyle(fontSize: 14,
                fontWeight: FontWeight.w700, color: kBrown)),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: _tijd,
                  builder: (c, child) => MediaQuery(
                    data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
                    child: child!));
                if (t != null) setState(() => _tijd = t);
              },
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: kPeachPale,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kPeach, width: 1.5)),
                child: Text('${_tijd.hour.toString().padLeft(2, '0')}:${_tijd.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 14,
                        fontWeight: FontWeight.w800, color: kBrown)),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuleren', style: TextStyle(color: kTextMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kPeach),
              onPressed: () {
                if (_labelCtrl.text.trim().isEmpty) return;
                Navigator.pop(context, _DagelijksMoment(_emoji,
                    _labelCtrl.text.trim(), _tijd));
              },
              child: const Text('Toevoegen', style: TextStyle(color: kWhite,
                  fontWeight: FontWeight.w800)),
            ),
          ]),
        ])),
    );
  }
}
