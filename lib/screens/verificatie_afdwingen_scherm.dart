import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/verificatie_gate_service.dart';
import '../theme/kleuren.dart';
import '../widgets/normaal_scaffold.dart';

/// VER-1: warm, kalm scherm dat verschijnt als de flags aan staan én
/// de familie-gebruiker zijn e-mailadres nog niet heeft geverifieerd.
///
/// Bewust géén blokkade voor de ONTVANGER-modus — dit scherm zit
/// alleen op het familie-pad in RouterScherm. De dierbare-tablet en
/// bel-flows blijven volledig werken; de dierbare mag niet gestraft
/// worden voor een mailtje dat de mantelzorger nog moet openen.
///
/// UX:
///  - Grote emoji + warme titel "Je bent er bijna"
///  - Uitleg + het e-mailadres in kwestie
///  - Knop "Verstuur mail opnieuw" (met korte rate-limit-tekst)
///  - Knop "Ik heb het bevestigd" → user.reload() + service-cache wist
///  - Discreet "Uitloggen"-linkje voor het geval iemand vast zit
///
/// Bij succes (na "Ik heb het bevestigd" en `emailVerified==true`)
/// roept het scherm `onGeverifieerd()` aan zodat RouterScherm rebuilt.
class VerificatieAfdwingenScherm extends StatefulWidget {
  final VoidCallback onGeverifieerd;
  const VerificatieAfdwingenScherm({
    super.key,
    required this.onGeverifieerd,
  });

  @override
  State<VerificatieAfdwingenScherm> createState() =>
      _VerificatieAfdwingenSchermState();
}

class _VerificatieAfdwingenSchermState
    extends State<VerificatieAfdwingenScherm> {
  bool _bezigVersturen = false;
  bool _bezigControleren = false;
  String? _melding;
  bool _meldingIsFout = false;

  String get _email =>
      FirebaseAuth.instance.currentUser?.email ?? '';

  Future<void> _versturenOpnieuw() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() {
      _bezigVersturen = true;
      _melding = null;
    });
    try {
      await user.sendEmailVerification();
      if (!mounted) return;
      setState(() {
        _melding = 'Mail verstuurd. Kijk in je inbox — en ook even in '
            'je spam-map als je hem niet ziet.';
        _meldingIsFout = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _melding =
            'Versturen lukte niet. Probeer het over een paar minuten '
            'opnieuw — Firebase beperkt het aantal mails per uur.';
        _meldingIsFout = true;
      });
    } finally {
      if (mounted) setState(() => _bezigVersturen = false);
    }
  }

  Future<void> _controleren() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() {
      _bezigControleren = true;
      _melding = null;
    });
    try {
      await user.reload();
      VerificatieGateService.wisCache();
      final geverifieerd =
          FirebaseAuth.instance.currentUser?.emailVerified ?? false;
      if (!mounted) return;
      if (geverifieerd) {
        widget.onGeverifieerd();
        return;
      }
      setState(() {
        _melding =
            'We zien nog geen bevestiging. Klik eerst op de link in '
            'de mail — die kan een minuutje op zich laten wachten.';
        _meldingIsFout = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _melding = 'Controleren lukte niet. Probeer het zo opnieuw.';
        _meldingIsFout = true;
      });
    } finally {
      if (mounted) setState(() => _bezigControleren = false);
    }
  }

  Future<void> _uitloggen() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return NormaalScaffold(
      backgroundColor: kCream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('💌', style: TextStyle(fontSize: 56)),
                  const SizedBox(height: 16),
                  const Text('Je bent er bijna',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 26,
                          fontWeight: FontWeight.w900, color: kBrown)),
                  const SizedBox(height: 12),
                  Text(
                    'We hebben een mail gestuurd naar\n$_email.\n\n'
                    'Klik op de link in die mail zodat we zeker weten '
                    'dat dit adres van jou is. Daarna kun je gewoon '
                    'verder.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15,
                        color: kBrownLight, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  if (_melding != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _meldingIsFout ? kRood.withOpacity(0.08)
                            : kPeach.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _meldingIsFout ? kRood : kPeach,
                            width: 1.5),
                      ),
                      child: Text(_melding!,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13,
                              color: _meldingIsFout ? kRood : kBrown,
                              height: 1.4)),
                    ),
                    const SizedBox(height: 16),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _bezigControleren ? null : _controleren,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPeach,
                        foregroundColor: kWhite,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _bezigControleren
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  color: kWhite, strokeWidth: 2.5))
                          : const Text('Ik heb het bevestigd',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _bezigVersturen ? null : _versturenOpnieuw,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kBrown,
                        side: const BorderSide(color: kPeachLight, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _bezigVersturen
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  color: kPeach, strokeWidth: 2.5))
                          : const Text('Verstuur mail opnieuw',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Google en Firebase beperken hoe vaak we deze mail '
                    'mogen sturen — wacht even als je meerdere keren tikt.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11,
                        color: kTextMuted, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: _uitloggen,
                    style: TextButton.styleFrom(foregroundColor: kTextMuted),
                    child: const Text('Uitloggen',
                        style: TextStyle(fontSize: 13,
                            decoration: TextDecoration.underline)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
