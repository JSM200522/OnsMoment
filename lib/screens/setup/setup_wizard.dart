import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import '../../services/device_modus_service.dart';

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

final List<Map<String, String>> kGeluiden = [
  {'id': 'twinkel',  'emoji': '✨', 'naam': 'Twinkel',
   'asset': 'assets/sounds/twinkel.mp3'},
  {'id': 'bel',      'emoji': '🔔', 'naam': 'Zachte bel',
   'asset': 'assets/sounds/bel.mp3'},
  {'id': 'vogel',    'emoji': '🐦', 'naam': 'Vogel',
   'asset': 'assets/sounds/vogel.mp3'},
  {'id': 'piano',    'emoji': '🎹', 'naam': 'Piano',
   'asset': 'assets/sounds/piano.mp3'},
  {'id': 'kerkklok', 'emoji': '⛪', 'naam': 'Kerkklok',
   'asset': 'assets/sounds/kerkklok.mp3'},
  {'id': 'hart',     'emoji': '💕', 'naam': 'Liefdes-melodie',
   'asset': 'assets/sounds/hart.mp3'},
];

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
  final _lievelingsdingenCtrl = TextEditingController();
  final _woonplaatsCtrl = TextEditingController();
  final _noodNaamCtrl = TextEditingController();
  final _noodTelCtrl = TextEditingController();

  Uint8List? _profielFotoBytes;
  String _gekozenGeluid = 'twinkel';
  final _geluidPreviewPlayer = AudioPlayer();

  final List<_DagelijksMoment> _momenten = [
    _DagelijksMoment('☀️', 'Goedemorgen', const TimeOfDay(hour: 8, minute: 30)),
    _DagelijksMoment('☕', 'Tijd voor koffie', const TimeOfDay(hour: 10, minute: 0)),
    _DagelijksMoment('🍽️', 'Lunchtijd', const TimeOfDay(hour: 12, minute: 30)),
    _DagelijksMoment('🌙', 'Welterusten', const TimeOfDay(hour: 20, minute: 0)),
  ];

  @override
  void dispose() {
    _geluidPreviewPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
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
            decoration: BoxDecoration(color: kPeachPale,
                borderRadius: BorderRadius.circular(10)),
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
        if (_stap == 0) { _rol = ''; _isInloggen = false; }
      });
    }
  }

  Widget _huidigeStap() {
    if (_stap == 0) return _rolKeuze();
    if (_rol == 'familie') {
      if (_stap == 1) return _accountStap();
      if (_stap == 2 && !_isInloggen) return _ontvangerProfielStap();
    } else {
      // ontvanger
      if (_stap == 1) return _accountStap();
    }
    return const SizedBox();
  }

  // ───────────────────────────────────────────────────
  // STAP 0: WELKOM + ROL KEUZE
  // ───────────────────────────────────────────────────
  Widget _rolKeuze() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const SizedBox(height: 32),
    const Text('💕', style: TextStyle(fontSize: 48)),
    const SizedBox(height: 16),
    const Text('Welkom bij\nOns Moment',
        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900,
            color: kBrown, height: 1.2)),
    const SizedBox(height: 12),
    const Text('Stuur lieve momenten naar je dierbare',
        style: TextStyle(fontSize: 15, color: kTextMuted)),
    const SizedBox(height: 24),
    Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kPeachPale,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kPeachLight, width: 1.5)),
      child: const Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Row(children: [
          Text('💡', style: TextStyle(fontSize: 16)),
          SizedBox(width: 8),
          Text('Hoe werkt het?', style: TextStyle(fontSize: 13,
              fontWeight: FontWeight.w800, color: kBrown)),
        ]),
        SizedBox(height: 6),
        Text(
          '• Eén account voor het hele gezin (tot 8 personen)\n'
          '• De ontvanger logt in met dezelfde gegevens op zijn/haar apparaat\n'
          '• Iedereen ziet en stuurt vanuit hetzelfde gezamenlijke profiel',
          style: TextStyle(fontSize: 12, color: kBrownLight, height: 1.6)),
      ])),
    const SizedBox(height: 20),
    const Text('Hoe gebruik je dit apparaat?',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
            color: kBrown)),
    const SizedBox(height: 12),
    _rolKaart('👨‍👩‍👧 Familie of mantelzorger',
      'Ik stuur foto\'s, stemberichtjes en herinneringen naar mijn dierbare',
      () => setState(() { _rol = 'familie'; _stap = 1; })),
    const SizedBox(height: 12),
    _rolKaart('👵 Ontvanger',
      'Dit apparaat is voor mijn dierbare — om berichten te zien en horen',
      () => setState(() { _rol = 'ontvanger'; _stap = 1; })),
  ]);

  Widget _rolKaart(String titel, String tekst, VoidCallback onTap) =>
    GestureDetector(onTap: onTap, child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: kWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kPeachLight, width: 2),
        boxShadow: [BoxShadow(color: kPeach.withOpacity(0.08),
            blurRadius: 12, offset: const Offset(0, 4))]),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text(titel, style: const TextStyle(fontSize: 15,
              fontWeight: FontWeight.w800, color: kBrown)),
          const SizedBox(height: 4),
          Text(tekst, style: const TextStyle(fontSize: 12,
              color: kBrownLight, height: 1.4)),
        ])),
        const Icon(Icons.arrow_forward_ios_rounded,
            color: kPeach, size: 16),
      ]),
    ));

  // ───────────────────────────────────────────────────
  // STAP 1: ACCOUNT (registreren of inloggen)
  // ───────────────────────────────────────────────────
  Widget _accountStap() {
    final titel = _rol == 'ontvanger' ? 'Log in op dit apparaat'
        : (_isInloggen ? 'Welkom terug 👋' : 'Maak je account aan');
    final uitleg = _rol == 'ontvanger'
        ? 'Vraag je familielid om de inloggegevens van het gezamenlijke account.'
        : (_isInloggen ? 'Log in met je e-mail en wachtwoord'
            : 'Eerst je gezamenlijke account. Daarna stel je samen met ons in voor wie je dit doet.');

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titel, style: const TextStyle(fontSize: 28,
          fontWeight: FontWeight.w900, color: kBrown, height: 1.2)),
      const SizedBox(height: 8),
      Text(uitleg, style: const TextStyle(fontSize: 14,
          color: kTextMuted, height: 1.4)),
      const SizedBox(height: 24),
      if (_rol == 'familie' && !_isInloggen) ...[
        _input('👤', 'Jouw naam', 'Bijv. Sara', _naamCtrl, false),
        const SizedBox(height: 10),
      ],
      _input('📧', 'E-mailadres', 'voorbeeld@email.nl', _emailCtrl, false),
      const SizedBox(height: 10),
      _input('🔒', 'Wachtwoord', 'Minimaal 6 tekens', _wachtwoordCtrl, true),
      const SizedBox(height: 16),
      if (_rol == 'familie') GestureDetector(
        onTap: () => setState(() => _isInloggen = !_isInloggen),
        child: Center(child: Text(
          _isInloggen ? 'Nieuw gezin? Maak een account aan'
              : 'Al een account? Log in',
          style: const TextStyle(fontSize: 13,
              fontWeight: FontWeight.w800, color: kPeach,
              decoration: TextDecoration.underline))),
      ),
    ]);
  }

  // ───────────────────────────────────────────────────
  // STAP 2: ONTVANGER PROFIEL (alleen voor familie bij registratie)
  // ───────────────────────────────────────────────────
  Widget _ontvangerProfielStap() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Vertel ons over je dierbare',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
            color: kBrown, height: 1.2)),
    const SizedBox(height: 8),
    const Text('Hoe meer je vertelt, hoe persoonlijker de app voelt. '
        'Alles is optioneel — je kunt altijd later aanpassen in Instellingen.',
        style: TextStyle(fontSize: 14, color: kTextMuted, height: 1.4)),
    const SizedBox(height: 24),

    _sectieKop('📸 Achtergrondfoto',
        'Kies een mooie foto van je dierbare. Deze foto wordt de '
        'sfeervolle achtergrond op het home-scherm van het ontvanger-apparaat.'),
    const SizedBox(height: 12),
    Center(child: GestureDetector(
      onTap: _kiesProfielFoto,
      child: Container(width: 120, height: 120,
        decoration: BoxDecoration(
          color: kPeachPale, shape: BoxShape.circle,
          border: Border.all(color: kPeach, width: 3),
          image: _profielFotoBytes != null ? DecorationImage(
            image: MemoryImage(_profielFotoBytes!), fit: BoxFit.cover) : null,
          boxShadow: [BoxShadow(color: kPeach.withOpacity(0.2),
              blurRadius: 16, offset: const Offset(0, 4))]),
        child: _profielFotoBytes == null
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center,
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

    _sectieKop('👤 Naam en informatie',
        'De naam staat op het home-scherm. Extra info helpt familie '
        'gerichte berichten te sturen.'),
    const SizedBox(height: 12),
    _input('👵', 'Naam ontvanger', 'Bijv. Jan, Opa, Moeder', _ontvangerNaamCtrl, false),
    const SizedBox(height: 10),
    _input('💕', 'Lievelingsdingen (optioneel)',
        'Bijv. tulpen, koffie, oude foto\'s', _lievelingsdingenCtrl, false),
    const SizedBox(height: 10),
    _input('🏠', 'Vroegere woonplaats (optioneel)',
        'Bijv. Volendam', _woonplaatsCtrl, false),
    const SizedBox(height: 10),
    _input('🆘', 'Noodcontact naam (optioneel)',
        'Bijv. Dochter Sara', _noodNaamCtrl, false),
    const SizedBox(height: 10),
    _input('☎️', 'Noodcontact telefoon (optioneel)',
        '06...', _noodTelCtrl, false),
    const SizedBox(height: 24),

    _sectieKop('🔔 Herkenningsgeluid',
        'Klinkt elke keer als er iets nieuws aankomt. Tik op een geluid om '
        'het voor te beluisteren. Helpt ontvangers met dementie het te '
        'herkennen als iets liefs.'),
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
            Expanded(child: Text(g['naam']!, style: TextStyle(fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _gekozenGeluid == g['id'] ? kWhite : kBrown))),
            Icon(Icons.play_circle_outline_rounded,
                color: _gekozenGeluid == g['id'] ? kWhite : kPeach, size: 24),
          ]),
        ),
      ),
    )),
    const SizedBox(height: 24),

    _sectieKop('📅 Dagelijkse momenten',
        'Vaste tijden waarop er automatisch een melding verschijnt. '
        'Later in de app kun je bij elk moment een foto, stemberichtje, '
        'lied, tekst of agenda-melding koppelen.'),
    const SizedBox(height: 12),
    if (_momenten.isEmpty)
      Container(padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: kPeachPale,
            borderRadius: BorderRadius.circular(14)),
        child: const Text('Nog geen momenten. Sla deze stap over of voeg een '
            'moment toe.',
            style: TextStyle(fontSize: 13, color: kBrownLight))),
    ..._momenten.asMap().entries.map((e) => _momentRij(e.key, e.value)),
    const SizedBox(height: 8),
    GestureDetector(
      onTap: _voegMomentToe,
      child: Container(padding: const EdgeInsets.symmetric(vertical: 12),
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
    const SizedBox(height: 24),
    Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kPeachPale,
          borderRadius: BorderRadius.circular(12)),
      child: const Row(children: [
        Text('🎉', style: TextStyle(fontSize: 18)),
        SizedBox(width: 10),
        Expanded(child: Text(
          'Klaar? Klik "App starten". Je komt in het familie-portaal waar '
          'je foto\'s, stem en muziek kunt sturen.',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
              color: kBrownLight, height: 1.4))),
      ])),
  ]);

  Widget _sectieKop(String titel, String uitleg) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titel, style: const TextStyle(fontSize: 16,
          fontWeight: FontWeight.w900, color: kBrown)),
      const SizedBox(height: 4),
      Text(uitleg, style: const TextStyle(fontSize: 12,
          color: kTextMuted, height: 1.4)),
    ]);

  Future<void> _speelGeluidPreview(String pad) async {
    try {
      await _geluidPreviewPlayer.stop();
      await _geluidPreviewPlayer.setAsset(pad);
      await _geluidPreviewPlayer.play();
    } catch (_) {}
  }

  Future<void> _kiesProfielFoto() async {
    try {
      final picker = ImagePicker();
      final foto = await picker.pickImage(source: ImageSource.gallery,
          maxWidth: 1200, imageQuality: 85);
      if (foto != null) {
        final bytes = await foto.readAsBytes();
        setState(() => _profielFotoBytes = bytes);
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
        child: Container(padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 8),
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
        child: const Padding(padding: EdgeInsets.all(4),
          child: Icon(Icons.close_rounded, color: kTextMuted, size: 18)),
      ),
    ]),
  );

  void _voegMomentToe() async {
    final result = await showDialog<_DagelijksMoment>(
      context: context, builder: (ctx) => _NieuwMomentDialog());
    if (result != null) setState(() => _momenten.add(result));
  }

  Future<void> _kiesTijd(int index) async {
    final gekozen = await showTimePicker(context: context,
      initialTime: _momenten[index].tijd,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!));
    if (gekozen != null) setState(() => _momenten[index].tijd = gekozen);
  }

  String _formatTijd(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  // ───────────────────────────────────────────────────
  // KNOP & ACTIES
  // ───────────────────────────────────────────────────
  Widget _knop() => GestureDetector(
    onTap: _bezig ? null : _volgende,
    child: Container(width: double.infinity, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [kPeach, kRose]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: kPeach.withOpacity(0.35),
            blurRadius: 20, offset: const Offset(0, 8))]),
      child: Center(child: _bezig
          ? const SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(color: kWhite, strokeWidth: 3))
          : Text(_knopTekst(), style: const TextStyle(fontSize: 16,
                fontWeight: FontWeight.w800, color: kWhite))),
    ),
  );

  String _knopTekst() {
    if (_rol == 'familie' && _isInloggen && _stap == 1) return 'Inloggen';
    if (_rol == 'familie' && !_isInloggen && _stap == 1) return 'Volgende →';
    if (_rol == 'familie' && !_isInloggen && _stap == 2) return '✨ App starten!';
    if (_rol == 'ontvanger' && _stap == 1) return 'Inloggen op dit apparaat';
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
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
            .hasMatch(_emailCtrl.text.trim())) {
          _toonFout('Ongeldig e-mailadres');
          return;
        }
        setState(() => _stap = 2);
      }
    } else if (_rol == 'familie' && _stap == 2 && !_isInloggen) {
      if (_ontvangerNaamCtrl.text.trim().isEmpty) {
        _toonFout('Vul minstens de naam van de ontvanger in');
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
      await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailCtrl.text.trim(), password: _wachtwoordCtrl.text);
      await DeviceModusService.zet(DeviceModusService.FAMILIE);
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
      final uid = cred.user!.uid;

      // Profielfoto uploaden
      String profielFotoUrl = '';
      if (_profielFotoBytes != null) {
        try {
          final ref = FirebaseStorage.instance.ref()
              .child('profielfotos').child('$uid.jpg');
          await ref.putData(_profielFotoBytes!,
              SettableMetadata(contentType: 'image/jpeg'));
          profielFotoUrl = await ref.getDownloadURL();
        } catch (_) {}
      }

      // Familie/gezin document (EEN account, alle data hangt eraan)
      await FirebaseFirestore.instance.collection('gebruikers').doc(uid).set({
        'email': _emailCtrl.text.trim(),
        'familieNaam': _naamCtrl.text.trim(),
        'ontvangerNaam': _ontvangerNaamCtrl.text.trim(),
        'ontvangerFoto': profielFotoUrl,
        'lievelingsdingen': _lievelingsdingenCtrl.text.trim(),
        'woonplaats': _woonplaatsCtrl.text.trim(),
        'noodcontactNaam': _noodNaamCtrl.text.trim(),
        'noodcontactTel': _noodTelCtrl.text.trim(),
        'herkenningsgeluid': _gekozenGeluid,
        'aangemaaktOp': FieldValue.serverTimestamp(),
      });

      // Dagelijkse momenten
      for (final m in _momenten) {
        await FirebaseFirestore.instance.collection('dagelijkse_momenten').add({
          'familieUid': uid,
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

      await DeviceModusService.zet(DeviceModusService.FAMILIE);
    } catch (e) {
      _toonFout('Account aanmaken mislukt: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _bezig = false);
    }
  }

  Future<void> _ontvangerInloggenActie() async {
    setState(() => _bezig = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailCtrl.text.trim(), password: _wachtwoordCtrl.text);
      await DeviceModusService.zet(DeviceModusService.ONTVANGER);
    } catch (e) {
      _toonFout('Inloggen mislukt. Klopt e-mail en wachtwoord?');
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

class _DagelijksMoment {
  String emoji; String label; TimeOfDay tijd;
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
    return Dialog(backgroundColor: kCream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Nieuw moment',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                  color: kBrown)),
          const SizedBox(height: 16),
          const Text('Emoji', style: TextStyle(fontSize: 12,
              color: kTextMuted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _emojis.map((e) =>
            GestureDetector(onTap: () => setState(() => _emoji = e),
              child: Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _emoji == e ? kPeach : kPeachPale,
                  borderRadius: BorderRadius.circular(8)),
                child: Text(e, style: const TextStyle(fontSize: 20))))).toList()),
          const SizedBox(height: 16),
          TextField(controller: _labelCtrl,
            decoration: const InputDecoration(labelText: 'Naam',
              border: OutlineInputBorder())),
          const SizedBox(height: 16),
          Row(children: [
            const Text('Tijd:', style: TextStyle(fontSize: 14,
                fontWeight: FontWeight.w700, color: kBrown)),
            const SizedBox(width: 12),
            GestureDetector(onTap: () async {
              final t = await showTimePicker(context: context,
                initialTime: _tijd, builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
                  child: child!));
              if (t != null) setState(() => _tijd = t);
            }, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: kPeachPale,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kPeach, width: 1.5)),
              child: Text('${_tijd.hour.toString().padLeft(2, '0')}:${_tijd.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w800, color: kBrown)))),
          ]),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Annuleren',
                  style: TextStyle(color: kTextMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kPeach),
              onPressed: () {
                if (_labelCtrl.text.trim().isEmpty) return;
                Navigator.pop(context, _DagelijksMoment(_emoji,
                    _labelCtrl.text.trim(), _tijd));
              },
              child: const Text('Toevoegen', style: TextStyle(color: kWhite,
                  fontWeight: FontWeight.w800))),
          ]),
        ])));
  }
}
