import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';

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

/// Setup wizard - eerste keer dat de app geopend wordt
/// Vraagt: wie ben je (familie of ontvanger) en logt in / registreert
class SetupWizard extends StatefulWidget {
  const SetupWizard({super.key});
  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  // 0 = rol-keuze, 1 = familie register/login, 2 = ontvanger login
  int _stap = 0;
  String _rol = ''; // 'familie' of 'ontvanger'
  bool _isInloggen = false; // false = registreren, true = inloggen
  bool _bezig = false;

  // Familie velden
  final _naamCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _wachtwoordCtrl = TextEditingController();

  // Voor wie stel je het in (alleen bij registratie)
  final _ontvangerNaamCtrl = TextEditingController();

  // Dagelijkse pop-ups - intake met EFFECT
  final List<_DagelijkseTijd> _dagelijkseTijden = [
    _DagelijkseTijd('☀️ Goedemorgen', const TimeOfDay(hour: 8, minute: 30)),
    _DagelijkseTijd('☕ Tijd voor koffie', const TimeOfDay(hour: 10, minute: 0)),
    _DagelijkseTijd('🍽️ Lunchtijd', const TimeOfDay(hour: 12, minute: 30)),
    _DagelijkseTijd('🌙 Welterusten', const TimeOfDay(hour: 20, minute: 0)),
  ];

  final _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_stap > 0) _voortgang(),
            Expanded(child: SingleChildScrollView(child: _huidigeStap())),
            const SizedBox(height: 16),
            if (_stap > 0) _knop(),
          ]),
        ),
      ),
    );
  }

  Widget _voortgang() {
    final maxStappen = _rol == 'familie' && !_isInloggen ? 3 : 2;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: List.generate(maxStappen, (i) => Expanded(
        child: Container(margin: const EdgeInsets.only(right: 4),
          height: 4, decoration: BoxDecoration(
            color: i < _stap ? kPeach : kPeachLight,
            borderRadius: BorderRadius.circular(2))),
      ))),
      const SizedBox(height: 8),
      Text('Stap $_stap van $maxStappen',
          style: const TextStyle(fontSize: 11,
              fontWeight: FontWeight.w800, color: kPeach, letterSpacing: 0.8)),
      const SizedBox(height: 16),
    ]);
  }

  Widget _huidigeStap() {
    if (_stap == 0) return _rolKeuze();
    if (_rol == 'familie') {
      if (_stap == 1) return _familieAccount();
      if (_stap == 2) return _isInloggen ? const SizedBox() : _voorWieEnTijden();
    } else {
      if (_stap == 1) return _ontvangerInloggen();
    }
    return _klaarScherm();
  }

  // ─── STAP 0: ROL KEUZE ──────────────────────────────────────
  Widget _rolKeuze() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const SizedBox(height: 40),
    const Text('💕', style: TextStyle(fontSize: 48)),
    const SizedBox(height: 16),
    const Text('Welkom bij\nOns Moment',
        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900,
            color: kBrown, height: 1.2)),
    const SizedBox(height: 12),
    Text('Hoe ga je deze app gebruiken?',
        style: TextStyle(fontSize: 16, color: kTextMuted)),
    const SizedBox(height: 32),
    _rolKaart(
      '👨‍👩‍👧 Familie of mantelzorger',
      'Ik stuur foto\'s, stemberichtjes en herinneringen naar mijn dierbare',
      () { setState(() { _rol = 'familie'; _stap = 1; }); },
    ),
    const SizedBox(height: 14),
    _rolKaart(
      '👵 Ontvanger',
      'Ik gebruik dit apparaat om berichten van familie te zien en horen',
      () { setState(() { _rol = 'ontvanger'; _stap = 1; }); },
    ),
  ]);

  Widget _rolKaart(String titel, String tekst, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: kWhite,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kPeachLight, width: 2),
          boxShadow: [BoxShadow(color: kPeach.withOpacity(0.1),
              blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titel, style: const TextStyle(fontSize: 16,
              fontWeight: FontWeight.w800, color: kBrown)),
          const SizedBox(height: 6),
          Text(tekst, style: TextStyle(fontSize: 13,
              color: kBrownLight, height: 1.4)),
          const SizedBox(height: 10),
          Row(children: const [
            Text('Kies dit', style: TextStyle(fontSize: 12,
                fontWeight: FontWeight.w800, color: kPeach)),
            SizedBox(width: 4),
            Text('→', style: TextStyle(fontSize: 14, color: kPeach)),
          ]),
        ]),
      ),
    );

  // ─── STAP 1 (familie): account aanmaken of inloggen ────────
  Widget _familieAccount() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(_isInloggen ? 'Welkom terug 👋' : 'Maak je account aan',
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
            color: kBrown, height: 1.2)),
    const SizedBox(height: 8),
    Text(_isInloggen
        ? 'Log in met je e-mail en wachtwoord'
        : 'Eerst maak je een account, daarna kies je voor wie je dit instelt',
        style: TextStyle(fontSize: 14, color: kTextMuted)),
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
        _isInloggen
            ? 'Nog geen account? Maak er een aan'
            : 'Al een account? Log in',
        style: const TextStyle(fontSize: 13,
            fontWeight: FontWeight.w800, color: kPeach,
            decoration: TextDecoration.underline))),
    ),
  ]);

  // ─── STAP 2 (familie register): voor wie + dagelijkse momenten ───
  Widget _voorWieEnTijden() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Voor wie en wanneer?',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
            color: kBrown, height: 1.2)),
    const SizedBox(height: 8),
    Text('Op deze tijden krijgt je dierbare automatisch een vrolijk moment',
        style: TextStyle(fontSize: 14, color: kTextMuted, height: 1.4)),
    const SizedBox(height: 24),
    _input('👵', 'Naam ontvanger', 'Jan', _ontvangerNaamCtrl, false),
    const SizedBox(height: 24),
    const Text('VASTE DAGELIJKSE MOMENTEN',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
            color: kTextMuted, letterSpacing: 0.8)),
    const SizedBox(height: 8),
    ..._dagelijkseTijden.asMap().entries.map((e) =>
      _tijdRij(e.key, e.value)),
    const SizedBox(height: 12),
    Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kPeachPale,
          borderRadius: BorderRadius.circular(12)),
      child: const Row(children: [
        Text('💡', style: TextStyle(fontSize: 18)),
        SizedBox(width: 10),
        Expanded(child: Text(
          'Deze momenten verschijnen elke dag automatisch. Je kunt ze later '
          'aanpassen of extra eenmalige momenten toevoegen.',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
              color: kBrownLight, height: 1.4))),
      ])),
  ]);

  Widget _tijdRij(int index, _DagelijkseTijd t) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(color: kWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kPeachLight, width: 2)),
    child: Row(children: [
      Expanded(child: Text(t.label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
              color: kBrown))),
      GestureDetector(
        onTap: () => _kiesTijd(index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: kPeachPale,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kPeach, width: 1.5)),
          child: Text(_formatTijd(t.tijd),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                  color: kBrown)),
        ),
      ),
    ]),
  );

  Future<void> _kiesTijd(int index) async {
    final gekozen = await showTimePicker(
      context: context,
      initialTime: _dagelijkseTijden[index].tijd,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (gekozen != null) {
      setState(() => _dagelijkseTijden[index].tijd = gekozen);
    }
  }

  String _formatTijd(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  // ─── ONTVANGER: simpel inloggen op bestaand account ─────────
  Widget _ontvangerInloggen() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Log in op dit apparaat',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
            color: kBrown, height: 1.2)),
    const SizedBox(height: 8),
    Text('Vraag je familielid om de inloggegevens van het ontvanger-account. '
        'Zodra je inlogt, opent de app zichzelf elke keer in ontvanger-modus.',
        style: TextStyle(fontSize: 14, color: kTextMuted, height: 1.4)),
    const SizedBox(height: 24),
    _input('📧', 'E-mailadres ontvanger', 'jan@email.nl', _emailCtrl, false),
    const SizedBox(height: 10),
    _input('🔒', 'Wachtwoord', '', _wachtwoordCtrl, true),
    const SizedBox(height: 16),
    Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kPeachPale,
          borderRadius: BorderRadius.circular(12)),
      child: const Row(children: [
        Text('💡', style: TextStyle(fontSize: 18)),
        SizedBox(width: 10),
        Expanded(child: Text(
          'Een familielid heeft deze gegevens aangemaakt bij de setup. '
          'Vraag hen om de e-mail en wachtwoord.',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
              color: kBrownLight, height: 1.4))),
      ])),
  ]);

  // ─── KLAAR ──────────────────────────────────────────────────
  Widget _klaarScherm() => const Column(children: [
    SizedBox(height: 60),
    Text('🎉', style: TextStyle(fontSize: 56)),
    SizedBox(height: 16),
    Text('Klaar!', style: TextStyle(fontSize: 32,
        fontWeight: FontWeight.w900, color: kBrown)),
  ]);

  // ─── KNOP ───────────────────────────────────────────────────
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

  // ─── ACTIE BIJ KNOP ─────────────────────────────────────────
  Future<void> _volgende() async {
    // Validatie + acties per stap
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
      final cred = await _authService.familieInloggen(
          _emailCtrl.text.trim(), _wachtwoordCtrl.text);
      if (cred == null) {
        _toonFout('Inloggen mislukt. Klopt e-mail en wachtwoord?');
      }
      // Router pakt rest op
    } finally {
      if (mounted) setState(() => _bezig = false);
    }
  }

  Future<void> _familieRegistreren() async {
    setState(() => _bezig = true);
    try {
      // 1. Familie account
      final cred = await _authService.familieRegistreren(
          _emailCtrl.text.trim(),
          _wachtwoordCtrl.text,
          _naamCtrl.text.trim());
      if (cred == null) {
        _toonFout('Account aanmaken mislukt. E-mail al in gebruik?');
        return;
      }
      // 2. Ontvanger profiel + dagelijkse momenten
      final ontvangerUid = 'ontvanger_${cred.user!.uid}';
      await FirebaseFirestore.instance
          .collection('gebruikers').doc(ontvangerUid).set({
        'naam': _ontvangerNaamCtrl.text.trim(),
        'rol': 'tablet',
        'familieUid': cred.user!.uid,
        'aangemeldOp': FieldValue.serverTimestamp(),
      });
      // 3. Dagelijkse vaste momenten opslaan
      for (final t in _dagelijkseTijden) {
        await FirebaseFirestore.instance
            .collection('dagelijkse_momenten').add({
          'naarUid': ontvangerUid,
          'vanUid': cred.user!.uid,
          'label': t.label,
          'uur': t.tijd.hour,
          'minuut': t.tijd.minute,
          'actief': true,
          'aangemaaktOp': FieldValue.serverTimestamp(),
        });
      }
      // 4. Koppel familie aan ontvanger
      await FirebaseFirestore.instance
          .collection('gebruikers').doc(cred.user!.uid).update({
        'ontvangerUid': ontvangerUid,
        'ontvangerNaam': _ontvangerNaamCtrl.text.trim(),
      });
    } catch (e) {
      _toonFout('Er ging iets mis: $e');
    } finally {
      if (mounted) setState(() => _bezig = false);
    }
  }

  Future<void> _ontvangerInloggenActie() async {
    setState(() => _bezig = true);
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailCtrl.text.trim(), password: _wachtwoordCtrl.text);
      // Zet rol op tablet zodat router naar tablet-scherm gaat
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
            controller: ctrl,
            obscureText: verborgen,
            style: const TextStyle(color: kBrown, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: hint,
              labelText: label,
              labelStyle: const TextStyle(color: kTextMuted, fontSize: 12),
              hintStyle: const TextStyle(color: kPeachLight),
              contentPadding: const EdgeInsets.fromLTRB(12, 16, 16, 16),
              border: InputBorder.none),
          )),
        ]),
      );
}

class _DagelijkseTijd {
  final String label;
  TimeOfDay tijd;
  _DagelijkseTijd(this.label, this.tijd);
}
