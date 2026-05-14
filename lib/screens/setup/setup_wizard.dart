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

class SetupWizard extends StatefulWidget {
  const SetupWizard({super.key});
  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  int _stap = 0;
  bool _bezig = false;

  // Familie-gegevens
  final _naamCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _wachtwoordCtrl = TextEditingController();

  // Jan's gegevens
  final _janNaamCtrl = TextEditingController(text: 'Jan');
  final _tabletCodeCtrl = TextEditingController();

  final _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Voortgangsbalk
            Row(children: List.generate(4, (i) => Expanded(
              child: Container(margin: const EdgeInsets.only(right: 4),
                height: 4, decoration: BoxDecoration(
                  color: i <= _stap ? kPeach : kPeachLight,
                  borderRadius: BorderRadius.circular(2))),
            ))),
            const SizedBox(height: 8),
            Text('Stap ${_stap + 1} van 4',
                style: const TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w800, color: kPeach,
                    letterSpacing: 0.8)),
            const SizedBox(height: 16),

            Expanded(child: SingleChildScrollView(child: _stappen[_stap])),

            // Knop
            GestureDetector(
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
                    : Text(_stap == 3 ? '✨ App starten!' : 'Volgende →',
                        style: const TextStyle(fontSize: 16,
                            fontWeight: FontWeight.w800, color: kWhite))),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  List<Widget> get _stappen => [_stap1(), _stap2(), _stap3(), _stap4()];

  Future<void> _volgende() async {
    if (_stap < 3) {
      setState(() => _stap++);
    } else {
      await _afronden();
    }
  }

  Future<void> _afronden() async {
    setState(() => _bezig = true);
    try {
      // 1. Familie account aanmaken
      final cred = await _authService.familieRegistreren(
          _emailCtrl.text.trim(),
          _wachtwoordCtrl.text.trim(),
          _naamCtrl.text.trim());
      if (cred == null) {
        _toonFout('Account aanmaken mislukt. Probeer opnieuw.');
        return;
      }
      // 2. Tablet account aanmaken met code
      final tabletCode = _tabletCodeCtrl.text.trim();
      final tabletEmail = '$tabletCode@tablet.onsmoment.nl';
      try {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: tabletEmail, password: tabletCode);
        final tabletUid = FirebaseAuth.instance.currentUser!.uid;
        // Sla tablet profiel op
        await FirebaseFirestore.instance
            .collection('gebruikers').doc(tabletUid).set({
          'naam': _janNaamCtrl.text.trim(),
          'rol': 'tablet', 'tabletCode': tabletCode,
          'aangemeldOp': FieldValue.serverTimestamp(),
        });
        // Koppel familie aan tablet
        await FirebaseFirestore.instance
            .collection('gebruikers').doc(cred.user!.uid).update({
          'tabletUid': tabletUid,
        });
      } catch (e) {
        // Tablet bestaat al, koppel gewoon
      }
    } catch (e) {
      _toonFout('Er ging iets mis: $e');
    } finally {
      if (mounted) setState(() => _bezig = false);
    }
  }

  void _toonFout(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.red));

  // STAP 1 — Jouw gegevens (familie)
  Widget _stap1() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Welkom bij\nOns Moment 💕', style: TextStyle(
        fontSize: 28, fontWeight: FontWeight.w900, color: kBrown, height: 1.2)),
    const SizedBox(height: 8),
    Text('Maak jouw familieaccount aan',
        style: TextStyle(fontSize: 15, color: kTextMuted)),
    const SizedBox(height: 24),
    _input('👤', 'Jouw naam', 'Sara', _naamCtrl, false),
    const SizedBox(height: 10),
    _input('📧', 'E-mailadres', 'sara@email.nl', _emailCtrl, false),
    const SizedBox(height: 10),
    _input('🔒', 'Wachtwoord', 'Minimaal 6 tekens', _wachtwoordCtrl, true),
  ]);

  // STAP 2 — Jan's naam
  Widget _stap2() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Voor wie stel je\nOns Moment in?', style: TextStyle(
        fontSize: 28, fontWeight: FontWeight.w900, color: kBrown, height: 1.2)),
    const SizedBox(height: 24),
    _input('👴', 'Naam van de ontvanger', 'Jan', _janNaamCtrl, false),
    const SizedBox(height: 16),
    Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kPeachPale,
          borderRadius: BorderRadius.circular(12)),
      child: const Row(children: [
        Text('💡', style: TextStyle(fontSize: 18)),
        SizedBox(width: 10),
        Expanded(child: Text(
          'Dit is de naam die op de tablet verschijnt. Gebruik de voornaam.',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
              color: kBrownLight, height: 1.4))),
      ])),
  ]);

  // STAP 3 — Tablet code instellen
  Widget _stap3() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Maak een code voor\nde tablet', style: TextStyle(
        fontSize: 28, fontWeight: FontWeight.w900, color: kBrown, height: 1.2)),
    const SizedBox(height: 8),
    Text('Deze code gebruik je éénmalig om de tablet in te stellen',
        style: TextStyle(fontSize: 14, color: kTextMuted)),
    const SizedBox(height: 24),
    _input('🔑', 'Tabletcode (bijv. jan2024)', 'jan2024', _tabletCodeCtrl, false),
    const SizedBox(height: 16),
    Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kPeachPale,
          borderRadius: BorderRadius.circular(12)),
      child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('📱 Hoe stel je de tablet in?',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: kBrown)),
        SizedBox(height: 8),
        Text('1. Download Ons Moment op de Android tablet',
            style: TextStyle(fontSize: 12, color: kBrownLight, height: 1.5)),
        Text('2. Open de app en kies "Tablet instellen"',
            style: TextStyle(fontSize: 12, color: kBrownLight, height: 1.5)),
        Text('3. Voer de code in die je hier instelt',
            style: TextStyle(fontSize: 12, color: kBrownLight, height: 1.5)),
        Text('4. Klaar! De tablet staat vast voor Jan',
            style: TextStyle(fontSize: 12, color: kBrownLight, height: 1.5)),
      ])),
  ]);

  // STAP 4 — Overzicht
  Widget _stap4() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Alles klaar! 🎉', style: TextStyle(
        fontSize: 28, fontWeight: FontWeight.w900, color: kBrown)),
    const SizedBox(height: 24),
    _bevestigRij('👤', 'Jouw naam', _naamCtrl.text),
    const SizedBox(height: 10),
    _bevestigRij('📧', 'E-mail', _emailCtrl.text),
    const SizedBox(height: 10),
    _bevestigRij('👴', 'Ontvanger', _janNaamCtrl.text),
    const SizedBox(height: 10),
    _bevestigRij('🔑', 'Tabletcode', _tabletCodeCtrl.text),
    const SizedBox(height: 24),
    Center(child: Text('💕 ${_janNaamCtrl.text} gaat dit geweldig vinden',
        style: const TextStyle(fontSize: 16, color: kPeach,
            fontWeight: FontWeight.w700))),
  ]);

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
              labelStyle: TextStyle(color: kTextMuted, fontSize: 12),
              hintStyle: TextStyle(color: kPeachLight),
              contentPadding: const EdgeInsets.fromLTRB(12, 16, 16, 16),
              border: InputBorder.none),
          )),
        ]),
      );

  Widget _bevestigRij(String emoji, String label, String waarde) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: kWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kPeachLight, width: 2)),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: const TextStyle(fontSize: 10,
                fontWeight: FontWeight.w800, color: kTextMuted, letterSpacing: 0.5)),
            Text(waarde, style: const TextStyle(fontSize: 14,
                fontWeight: FontWeight.w700, color: kBrown)),
          ])),
          Container(width: 24, height: 24,
              decoration: const BoxDecoration(color: kGreen, shape: BoxShape.circle),
              child: const Center(child: Text('✓',
                  style: TextStyle(fontSize: 12, color: kWhite,
                      fontWeight: FontWeight.w800)))),
        ]),
      );
}
