import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import '../../services/apparaat_service.dart';
import '../../services/device_modus_service.dart';
import '../../theme/kleuren.dart';
import '../../data/geluiden.dart';
import '../../data/labels.dart';
import '../../data/kring.dart';
import '../../data/kring_membership.dart';

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
  String? _bezigModus;
  String? _accountType;  // 'familie' of 'zorg', gekozen bij nieuw account

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
  void initState() {
    super.initState();
    // Knop in stap 2 (ontvanger-profiel) blijft disabled tot de naam is ingevuld.
    _ontvangerNaamCtrl.addListener(_herbouw);
  }

  void _herbouw() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ontvangerNaamCtrl.removeListener(_herbouw);
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
            if (_stap > 0 && !(_rol == 'ontvanger' && _stap == 2)) _knop(),
          ]),
        ),
      ),
    );
  }

  Widget _topBalk() {
    final toonProgress = _rol == 'familie' && !_isInloggen;
    const maxStappen = 3;
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
        if (toonProgress) ...[
          const SizedBox(width: 12),
          Expanded(child: Row(children: List.generate(maxStappen, (i) => Expanded(
            child: Container(margin: const EdgeInsets.only(right: 4),
              height: 4, decoration: BoxDecoration(
                color: i < _stap ? kPeach : kPeachLight,
                borderRadius: BorderRadius.circular(2))),
          )))),
        ],
      ]),
      if (toonProgress) ...[
        const SizedBox(height: 8),
        Text('Stap $_stap van $maxStappen',
            style: const TextStyle(fontSize: 11,
                fontWeight: FontWeight.w800, color: kPeach, letterSpacing: 0.8)),
      ],
      const SizedBox(height: 16),
    ]);
  }

  void _terug() {
    if (_stap > 0) {
      setState(() {
        _stap--;
        if (_stap == 0) _isInloggen = false;
      });
    }
  }

  Future<void> _kiesRol(String nieuweRol) async {
    if (nieuweRol == 'ontvanger') {
      final bevestigd = await _bevestigOntvanger();
      if (!bevestigd) return;
    }
    if (!mounted) return;
    setState(() {
      if (_rol != '' && _rol != nieuweRol) {
        _isInloggen = false;
        _accountType = null;
        if (nieuweRol == 'ontvanger') {
          _naamCtrl.clear();
          _ontvangerNaamCtrl.clear();
          _lievelingsdingenCtrl.clear();
          _woonplaatsCtrl.clear();
          _noodNaamCtrl.clear();
          _noodTelCtrl.clear();
          _profielFotoBytes = null;
          _gekozenGeluid = 'twinkel';
        }
      }
      _rol = nieuweRol;
      _stap = 1;
    });
  }

  Future<bool> _bevestigOntvanger() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: kCream,
        title: const Row(children: [
          Text('⚠️', style: TextStyle(fontSize: 22)),
          SizedBox(width: 10),
          Expanded(child: Text(
            'Is het kringaccount al aangemaakt?',
            style: TextStyle(fontSize: 18,
                fontWeight: FontWeight.w900, color: kBrown))),
        ]),
        content: const Text(
          'Dit apparaat wordt zo ingesteld voor je dierbare of cliënt — het '
          'ontvangt straks de berichten, foto\'s en stemberichten van '
          'de kring.\n\n'
          'Daarvoor moet eerst iemand van de kring een kringaccount '
          'hebben aangemaakt op hun eigen telefoon. Dit apparaat logt '
          'straks in met diezelfde gegevens.\n\n'
          'Is het kringaccount al aangemaakt?',
          style: TextStyle(fontSize: 14, color: kBrownLight, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nee, terug',
                style: TextStyle(color: kTextMuted,
                    fontWeight: FontWeight.w700))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kPeach,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ja, ga verder',
                style: TextStyle(color: kWhite,
                    fontWeight: FontWeight.w800))),
        ],
      ),
    );
    return result == true;
  }

  Widget _huidigeStap() {
    if (_stap == 0) return _rolKeuze();
    if (_rol == 'familie') {
      if (_stap == 1) return _accountStap();
      if (_stap == 2 && !_isInloggen) return _ontvangerProfielStap();
      if (_stap == 2 && _isInloggen) return _persoonsnaamStap();
    } else {
      // ontvanger
      if (_stap == 1) return _accountStap();
      if (_stap == 2) return _weergaveModusStap();
    }
    return const SizedBox();
  }

  // ───────────────────────────────────────────────────
  // STAP 0: WELKOM + ROL KEUZE
  // ───────────────────────────────────────────────────
  Widget _rolKeuze() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const SizedBox(height: 8),
    Center(child: Image.asset('assets/images/logo.png', height: 76)),
    const SizedBox(height: 16),
    const Text('Welkom bij\nOns Moment',
        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900,
            color: kBrown, height: 1.2)),
    const SizedBox(height: 12),
    const Text('Stuur lieve momenten',
        style: TextStyle(fontSize: 15, color: kTextMuted)),
    const SizedBox(height: 20),
    Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kPeach,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: kPeach.withOpacity(0.3),
            blurRadius: 12, offset: const Offset(0, 4))]),
      child: const Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Row(children: [
          Text('⚠️', style: TextStyle(fontSize: 18)),
          SizedBox(width: 8),
          Expanded(child: Text('LET OP',
              style: TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w900, color: kWhite,
                  letterSpacing: 1.2))),
        ]),
        SizedBox(height: 8),
        Text(
          'Maak EERST je account aan op je eigen telefoon.\n\n'
          'Stel pas DAARNA het ontvanger-apparaat in.',
          style: TextStyle(fontSize: 13,
              fontWeight: FontWeight.w700, color: kWhite, height: 1.4)),
      ])),
    const SizedBox(height: 16),
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
          '1️⃣ Maak een account aan op je eigen telefoon\n'
          '    Vul je gegevens in en kies je rol.\n\n'
          '2️⃣ Voeg een ontvanger toe\n'
          '    Vertel ons over de persoon die berichten krijgt.\n\n'
          '3️⃣ Stel het ontvanger-apparaat in\n'
          '    Een aparte tablet of telefoon bij de ontvanger toont alles wat je stuurt.\n\n'
          '4️⃣ Stuur lieve momenten\n'
          '    Foto\'s, stemberichten, video\'s en herinneringen vanaf je telefoon.',
          style: TextStyle(fontSize: 12, color: kBrownLight, height: 1.6)),
      ])),
    const SizedBox(height: 20),
    const Text('Hoe gebruik je dit apparaat?',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
            color: kBrown)),
    const SizedBox(height: 12),
    _rolKaart('👨‍👩‍👧 Familielid of zorgverlener',
      'Ik stuur foto\'s, stemberichtjes en herinneringen',
      () => _kiesRol('familie')),
    const SizedBox(height: 12),
    _rolKaart('👵 Ontvanger',
      'Dit apparaat is voor mijn dierbare of cliënt — om berichten te zien en horen',
      () => _kiesRol('ontvanger')),
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
        ? 'Vraag iemand uit de kring om de inloggegevens van het gezamenlijke account.'
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
          _isInloggen ? 'Nieuwe kring? Maak een account aan'
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
  Widget _accountTypeKnop(
      String emoji, String titel, String uitleg, String waarde) {
    final gekozen = _accountType == waarde;
    return GestureDetector(
      onTap: () => setState(() => _accountType = waarde),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: gekozen ? kPeach : kWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: gekozen ? kPeach : kPeachLight, width: 2)),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Text(titel, style: TextStyle(fontSize: 16,
                fontWeight: FontWeight.w900, color: gekozen ? kWhite : kBrown)),
            const SizedBox(height: 2),
            Text(uitleg, style: TextStyle(fontSize: 12, height: 1.3,
                color: gekozen ? kWhite.withOpacity(0.9) : kTextMuted)),
          ])),
        ]),
      ),
    );
  }

  Widget _ontvangerProfielStap() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Welkom! Wat is je rol?',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
            color: kBrown, height: 1.2)),
    const SizedBox(height: 16),
    _accountTypeKnop('🏠', 'Ik ben familielid',
        'om met mijn dierbare in contact te blijven', 'familie'),
    _accountTypeKnop('💼', 'Ik ben zorgverlener',
        'om voor mijn cliënten te zorgen', 'zorg'),
    const SizedBox(height: 24),
    Text('Vertel ons over ${jeDierbareLabel(_accountType)}',
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
            color: kBrown, height: 1.2)),
    const SizedBox(height: 8),
    const Text('Hoe meer je vertelt, hoe persoonlijker de app voelt. '
        'Alles is optioneel — je kunt altijd later aanpassen in Instellingen.',
        style: TextStyle(fontSize: 14, color: kTextMuted, height: 1.4)),
    const SizedBox(height: 24),

    _sectieKop('📸 Achtergrondfoto',
        'Kies een mooie foto van ${jeDierbareLabel(_accountType)}. Deze foto wordt de '
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
        'De naam staat op het home-scherm. Extra info helpt de kring '
        'gerichte berichten te sturen.'),
    const SizedBox(height: 12),
    _input('👵', 'Naam van ${jeDierbareLabel(_accountType)}',
        _accountType == 'zorg'
            ? 'Bijv. Mevr. de Vries, Dhr. Jansen...'
            : 'Bijv. Oma, Opa, Mam, Pap...',
        _ontvangerNaamCtrl, false),
    const SizedBox(height: 6),
    const Text('Zo verschijnt zijn/haar naam in de app en bij berichten.',
        style: TextStyle(fontSize: 12, color: kTextMuted, height: 1.4)),
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
        'het voor te beluisteren. Helpt ${jeDierbareLabel(_accountType)} het te '
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
    const SizedBox(height: 12),
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kCream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kPeachLight, width: 1.5)),
      child: const Text(
        '💡 Tip: in de app kun je later ook eigen stem of muziek '
        'toevoegen per moment via Agenda.',
        style: TextStyle(fontSize: 12, color: kTextMuted, height: 1.4)),
    ),
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
          'Klaar? Klik "App starten". Je komt in het kring-portaal waar '
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
  /// Ontvanger-naam is verplicht bij het aanmaken van een nieuwe kring.
  bool get _ontvangerNaamVerplichtMaarLeeg =>
      _rol == 'familie' && !_isInloggen && _stap == 2
      && (_ontvangerNaamCtrl.text.trim().isEmpty || _accountType == null);

  Widget _knop() {
    final geblokkeerd = _ontvangerNaamVerplichtMaarLeeg;
    return Opacity(
      opacity: geblokkeerd ? 0.5 : 1.0,
      child: GestureDetector(
        onTap: (_bezig || geblokkeerd) ? null : _volgende,
        child: Container(width: double.infinity, padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [kPeach, kRose]),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: kPeach.withOpacity(0.35),
                blurRadius: 20, offset: const Offset(0, 8))]),
          child: Center(child: _bezig
              ? Row(mainAxisSize: MainAxisSize.min, children: const [
                  SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: kWhite, strokeWidth: 3)),
                  SizedBox(width: 12),
                  Text('Even laden...',
                      style: TextStyle(fontSize: 16,
                          fontWeight: FontWeight.w800, color: kWhite)),
                ])
              : Text(_knopTekst(), style: const TextStyle(fontSize: 16,
                    fontWeight: FontWeight.w800, color: kWhite))),
        ),
      ),
    );
  }

  String _knopTekst() {
    if (_rol == 'familie' && _isInloggen && _stap == 1) return 'Inloggen';
    if (_rol == 'familie' && _isInloggen && _stap == 2) return 'Klaar 💕';
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
    } else if (_rol == 'familie' && _stap == 2 && _isInloggen) {
      await _voltooiFamilieInloggen();
    } else if (_rol == 'ontvanger' && _stap == 1) {
      await _ontvangerInloggenActie();
    }
  }

  Future<void> _familieInloggen() async {
    setState(() => _bezig = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailCtrl.text.trim(), password: _wachtwoordCtrl.text);
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final apparaatId = await DeviceModusService.krijgApparaatId();
      final doc = await FirebaseFirestore.instance
          .collection('gebruikers').doc(uid)
          .collection('apparaten').doc(apparaatId).get();
      if (doc.exists) {
        // Bekend apparaat — skip naam-vraag, direct door
        ApparaatService.updateLaatstActief(
            familieUid: uid, apparaatId: apparaatId);
        await DeviceModusService.zet(DeviceModusService.FAMILIE);
      } else {
        // Eerste keer op dit apparaat — vraag naam in stap 2.
        _naamCtrl.clear();
        if (mounted) setState(() => _stap = 2);
      }
    } catch (e) {
      _toonFout('Inloggen mislukt. Klopt e-mail en wachtwoord?');
    } finally {
      if (mounted) setState(() => _bezig = false);
    }
  }

  Future<void> _familieRegistreren() async {
    setState(() => _bezig = true);
    UserCredential? cred;
    try {
      cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailCtrl.text.trim(), password: _wachtwoordCtrl.text);
      final uid = cred.user!.uid;

      // V9: kringId los van auth-uid (klaar voor multi-kring). Dual-write
      // naast bestaande gebruikers/{uid} velden — geen breaking change.
      final kringId =
          FirebaseFirestore.instance.collection('kringen').doc().id;

      // Profielfoto uploaden (geen exception bij fail; zie #22)
      String profielFotoUrl = '';
      bool fotoUploadFaalde = false;
      if (_profielFotoBytes != null) {
        try {
          final ref = FirebaseStorage.instance.ref()
              .child('profielfotos').child('$uid.jpg');
          await ref.putData(_profielFotoBytes!,
              SettableMetadata(contentType: 'image/jpeg'));
          profielFotoUrl = await ref.getDownloadURL();
        } catch (_) {
          fotoUploadFaalde = true;
        }
      }

      // Profiel + dagelijkse momenten atomair via WriteBatch.
      // Bij fail wordt de auth-user in de catch hieronder weer verwijderd
      // zodat retry met dezelfde email mogelijk blijft.
      final batch = FirebaseFirestore.instance.batch();
      batch.set(
          FirebaseFirestore.instance.collection('gebruikers').doc(uid), {
        'email': _emailCtrl.text.trim(),
        'familieNaam': _naamCtrl.text.trim(),
        'gebruikersNaam': _naamCtrl.text.trim(),
        'ontvangerNaam': _ontvangerNaamCtrl.text.trim(),
        'ontvangerFoto': profielFotoUrl,
        'lievelingsdingen': _lievelingsdingenCtrl.text.trim(),
        'woonplaats': _woonplaatsCtrl.text.trim(),
        'noodcontactNaam': _noodNaamCtrl.text.trim(),
        'noodcontactTel': _noodTelCtrl.text.trim(),
        'herkenningsgeluid': _gekozenGeluid,
        'accountType': _accountType ?? 'familie',
        'tier': 'klein',
        'aangemaaktOp': FieldValue.serverTimestamp(),
      });

      // V9 schema: schrijf kringen/{kringId} + leden/{uid} parallel.
      // Bestaande lees-paden (familie_scherm, tablet_scherm) blijven de
      // gebruikers/{uid}-doc lezen tot 1.1d+ de queries omdraait.
      final kring = Kring(
        id: kringId,
        naam: _ontvangerNaamCtrl.text.trim(),
        foto: profielFotoUrl.isEmpty ? null : profielFotoUrl,
        lievelingsdingen: _lievelingsdingenCtrl.text.trim().isEmpty
            ? null : _lievelingsdingenCtrl.text.trim(),
        woonplaats: _woonplaatsCtrl.text.trim().isEmpty
            ? null : _woonplaatsCtrl.text.trim(),
        noodcontactNaam: _noodNaamCtrl.text.trim().isEmpty
            ? null : _noodNaamCtrl.text.trim(),
        noodcontactTel: _noodTelCtrl.text.trim().isEmpty
            ? null : _noodTelCtrl.text.trim(),
        herkenningsgeluid: _gekozenGeluid,
        eigenaarUid: uid,
        aangemaaktOp: DateTime.now(), // wordt direct overschreven met server-stamp
        laatsteUpdate: DateTime.now(),
        type: _accountType == 'zorg' ? Kring.TYPE_ZORG : Kring.TYPE_FAMILIE,
        modus: Kring.MODUS_VERGRENDELD,
      );
      final kringMap = kring.toFirestoreMap(bijUpdate: true);
      kringMap['aangemaaktOp'] = FieldValue.serverTimestamp();
      batch.set(
          FirebaseFirestore.instance.collection('kringen').doc(kringId),
          kringMap);

      final membership = Membership(
        userUid: uid,
        rol: AccountRol.eigenaar,
        gejoindOp: DateTime.now(),
        uitgenodigdDoor: null,
      );
      batch.set(
          FirebaseFirestore.instance.collection('kringen').doc(kringId)
              .collection('leden').doc(uid),
          membership.toFirestoreMap(bijCreate: true));

      for (final m in _momenten) {
        batch.set(
            FirebaseFirestore.instance.collection('dagelijkse_momenten').doc(),
            {
          'familieUid': uid,
          'kringId': kringId,
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
      await batch.commit();

      if (fotoUploadFaalde && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Account aangemaakt. Foto kon niet worden '
              'opgeslagen — pas later aan via Instellingen → '
              'Ontvanger-profiel.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ));
      }
      // Apparaat registreren in sub-collectie zodat kringleden-overzicht
      // (sub-commit C) dit apparaat kan tonen.
      final apparaatId = await DeviceModusService.krijgApparaatId();
      await ApparaatService.registreer(
        familieUid: uid,
        apparaatId: apparaatId,
        persoonsNaam: _naamCtrl.text.trim(),
        modus: 'familie',
      );
      await DeviceModusService.zet(DeviceModusService.FAMILIE);
      await DeviceModusService.zetActieveKring(kringId);
    } catch (e) {
      if (cred?.user != null) {
        try {
          await cred!.user!.delete();
        } catch (_) {}
      }
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
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final apparaatId = await DeviceModusService.krijgApparaatId();
      final doc = await FirebaseFirestore.instance
          .collection('gebruikers').doc(uid)
          .collection('apparaten').doc(apparaatId).get();
      if (doc.exists) {
        // Bekend apparaat — lees opgeslagen weergaveModus, geen keuze nodig
        final wm = (doc.data()?['weergaveModus'] as String?)
                   ?? DeviceModusService.VERGRENDELD;
        ApparaatService.updateLaatstActief(
            familieUid: uid, apparaatId: apparaatId);
        await DeviceModusService.zetWeergaveModus(wm);
        await DeviceModusService.zet(DeviceModusService.ONTVANGER);
      } else {
        // Eerste keer op dit apparaat — keuze in stap 2
        if (mounted) setState(() => _stap = 2);
      }
    } catch (e) {
      _toonFout('Inloggen mislukt. Klopt e-mail en wachtwoord?');
    } finally {
      if (mounted) setState(() => _bezig = false);
    }
  }

  // ───────────────────────────────────────────────────
  // STAP 2: PERSOONSNAAM (route B — familie inloggen)
  // ───────────────────────────────────────────────────
  Widget _persoonsnaamStap() => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Welkom in de kring 💕',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
            color: kBrown, height: 1.2)),
    const SizedBox(height: 8),
    const Text('Hoe heet jij?',
        style: TextStyle(fontSize: 14, color: kTextMuted, height: 1.4)),
    const SizedBox(height: 24),
    _input('👤', 'Jouw naam', 'Bijv. Sara', _naamCtrl, false),
  ]);

  Future<void> _voltooiFamilieInloggen() async {
    if (_naamCtrl.text.trim().isEmpty) {
      _toonFout('Vul je naam in');
      return;
    }
    setState(() => _bezig = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final naam = _naamCtrl.text.trim();
      final mag = await ApparaatService.kanNieuwePersoonToevoegen(
          familieUid: uid, nieuweNaam: naam);
      if (!mag) {
        final limiet = ApparaatService.limietPerTier(
            await ApparaatService.krijgTier(uid));
        _toonFout('Deze kring zit vol ($limiet kringleden). Vraag de '
            'beheerder om een ander kringlid te verwijderen.');
        if (mounted) setState(() => _bezig = false);
        return;
      }
      final apparaatId = await DeviceModusService.krijgApparaatId();
      await ApparaatService.registreer(
        familieUid: uid,
        apparaatId: apparaatId,
        persoonsNaam: naam,
        modus: 'familie',
      );
      await DeviceModusService.zet(DeviceModusService.FAMILIE);
    } finally {
      if (mounted) setState(() => _bezig = false);
    }
  }

  // ───────────────────────────────────────────────────
  // STAP 2: WEERGAVEMODUS (route C — ontvanger)
  // ───────────────────────────────────────────────────
  Widget _weergaveModusStap() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return FutureBuilder<DocumentSnapshot?>(
      future: uid == null
          ? Future.value(null)
          : FirebaseFirestore.instance.collection('gebruikers').doc(uid).get(),
      builder: (ctx, snap) {
        final naam = (snap.data?.data() as Map?)?['ontvangerNaam'] as String?
                     ?? 'je dierbare';
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Hoe gebruikt $naam dit apparaat?',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
                  color: kBrown, height: 1.2)),
          const SizedBox(height: 20),
          _modusKaart(
            emoji: '🔒',
            titel: 'Alleen voor Ons Moment',
            modusId: DeviceModusService.VERGRENDELD,
            uitleg: 'Voor $naam die niet meer zelf op een apparaat kan '
                'reageren.\n\n'
                'Het apparaat:\n'
                '- Toont alleen Ons Moment\n'
                '- Kan geen andere apps openen, niet bellen\n'
                '- $naam kan kijken en luisteren, maar niet terugsturen\n\n'
                'Kies dit als $naam veel zorg nodig heeft of het '
                'apparaat niet zelf gebruikt.',
            onTap: () => _voltooiOntvanger(DeviceModusService.VERGRENDELD),
          ),
          const SizedBox(height: 12),
          _modusKaart(
            emoji: '📱',
            titel: 'Ook voor andere dingen',
            modusId: DeviceModusService.MELDINGEN,
            uitleg: 'Voor $naam die nog wel zelf wil reageren.\n\n'
                '$naam kan:\n'
                '- Foto\'s, stem-berichten en muziek terugsturen\n'
                '- De agenda zien\n'
                '- Het apparaat gebruiken voor andere apps\n\n'
                'Berichten komen binnen als melding.\n\n'
                'Notities tussen familie zijn voor $naam verborgen.',
            onTap: () => _voltooiOntvanger(DeviceModusService.MELDINGEN),
          ),
        ]);
      },
    );
  }

  Widget _modusKaart({required String emoji, required String titel,
      required String uitleg, required String modusId,
      required VoidCallback onTap}) {
    final bezigDeze = _bezigModus == modusId;
    final bezigAnder = _bezigModus != null && !bezigDeze;
    return Opacity(
      opacity: bezigAnder ? 0.4 : 1.0,
      child: GestureDetector(onTap: _bezig ? null : onTap, child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: kWhite,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kPeachLight, width: 2),
          boxShadow: [BoxShadow(color: kPeach.withOpacity(0.08),
              blurRadius: 12, offset: const Offset(0, 4))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(child: Text(titel, style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: kBrown))),
            if (bezigDeze) ...[
              const SizedBox(width: 8),
              const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(
                      color: kPeach, strokeWidth: 2.5)),
              const SizedBox(width: 8),
              const Text('Even laden...',
                  style: TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w800, color: kPeach)),
            ],
          ]),
          const SizedBox(height: 8),
          Text(uitleg, style: const TextStyle(
              fontSize: 12, color: kBrownLight, height: 1.5)),
        ]),
      )),
    );
  }

  Future<void> _voltooiOntvanger(String weergaveModus) async {
    setState(() {
      _bezig = true;
      _bezigModus = weergaveModus;
    });
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final apparaatId = await DeviceModusService.krijgApparaatId();
      // Voor ontvanger-apparaat gebruiken we ontvangerNaam als persoonsnaam.
      String naam = 'Ontvanger';
      try {
        final doc = await FirebaseFirestore.instance
            .collection('gebruikers').doc(uid).get();
        naam = (doc.data()?['ontvangerNaam'] as String?) ?? 'Ontvanger';
      } catch (_) {}
      final mag = await ApparaatService.kanNieuwePersoonToevoegen(
          familieUid: uid, nieuweNaam: naam);
      if (!mag) {
        final limiet = ApparaatService.limietPerTier(
            await ApparaatService.krijgTier(uid));
        _toonFout('Deze kring zit vol ($limiet kringleden). Vraag de '
            'beheerder om een ander kringlid te verwijderen.');
        return;
      }
      await ApparaatService.registreer(
        familieUid: uid,
        apparaatId: apparaatId,
        persoonsNaam: naam,
        modus: 'ontvanger',
        weergaveModus: weergaveModus,
      );
      await DeviceModusService.zetWeergaveModus(weergaveModus);
      await DeviceModusService.zet(DeviceModusService.ONTVANGER);
    } finally {
      if (mounted) setState(() {
        _bezig = false;
        _bezigModus = null;
      });
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
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

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
