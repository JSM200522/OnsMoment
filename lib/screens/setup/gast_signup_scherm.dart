import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/uitnodiging.dart';
import '../../services/apparaat_service.dart';
import '../../services/device_modus_service.dart';
import '../../services/uitnodiging_service.dart';
import '../../theme/kleuren.dart';
import '../../widgets/normaal_scaffold.dart';
import '../../widgets/ow_knop.dart';
import '../../widgets/ow_invoer.dart';

/// Signup-pad voor uitgenodigde gast zonder bestaand account (V9 2.5-a-3-b).
///
/// Compact: voornaam + email + wachtwoord. Geen ontvanger-info, foto of
/// dagelijkse momenten — die horen bij EIGENAAR-flow. Gast krijgt een
/// minimaal gebruikers-doc, membership rol=gast in host-kring, en landt
/// op FamilieScherm van de host-kring.
///
/// Optie B (bewust): zodra createUser is gelukt blijft het account staan,
/// ongeacht wat erna faalt. Bij accept-fout (kringVol/kringNotFound/
/// notFound) navigeren we terug naar AcceptUitnodigScherm met result
/// 'reset' zodat de code-invoer opnieuw verschijnt.
class GastSignupScherm extends StatefulWidget {
  final Uitnodiging uitnodiging;
  const GastSignupScherm({super.key, required this.uitnodiging});

  @override
  State<GastSignupScherm> createState() => _GastSignupSchermState();
}

class _GastSignupSchermState extends State<GastSignupScherm> {
  final _naamCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _wachtwoordCtrl = TextEditingController();
  bool _bezig = false;

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _naamCtrl.dispose();
    _emailCtrl.dispose();
    _wachtwoordCtrl.dispose();
    super.dispose();
  }

  void _toonFout(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: kRood,
      duration: const Duration(seconds: 5)));
  }

  Future<void> _aanmelden() async {
    final naam = _naamCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final ww = _wachtwoordCtrl.text;
    if (naam.isEmpty) {
      _toonFout('Vul je voornaam in.');
      return;
    }
    if (!_emailRegex.hasMatch(email)) {
      _toonFout('E-mailadres lijkt niet te kloppen.');
      return;
    }
    if (ww.length < 6) {
      _toonFout('Wachtwoord moet minstens 6 tekens zijn.');
      return;
    }
    setState(() => _bezig = true);

    // ─── 1. createUser ─────────────────────────────────────────────
    UserCredential cred;
    try {
      cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email, password: ww);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _bezig = false);
      switch (e.code) {
        case 'email-already-in-use':
          _toonFout('Er bestaat al een account met dit e-mailadres. '
              'Ga terug en kies "Ik heb al een account".');
          break;
        case 'weak-password':
          _toonFout('Wachtwoord moet minstens 6 tekens zijn.');
          break;
        case 'invalid-email':
          _toonFout('E-mailadres lijkt niet te kloppen.');
          break;
        default:
          _toonFout('Aanmaken mislukt: ${e.code}');
      }
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _bezig = false);
      _toonFout('Even een netwerkprobleem. Probeer opnieuw.');
      return;
    }

    final uid = cred.user!.uid;

    // V9 2.12-a-2: verificatie-mail fire-and-forget. Account werkt
    // direct ongeacht status; faalt silent bij netwerk-fout.
    cred.user?.sendEmailVerification().catchError((Object _) {});

    // ─── 2. Minimaal gebruikers-doc (6 velden, géén ontvanger-velden).
    // Optie B: bij fail geen account-delete, gast kan opnieuw inloggen.
    try {
      await FirebaseFirestore.instance.collection('gebruikers').doc(uid).set({
        'email': email,
        'familieNaam': naam,
        'gebruikersNaam': naam,
        'accountType': 'familie',
        'tier': 'klein',
        'aangemaaktOp': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _bezig = false);
      _toonFout('Account aangemaakt maar profiel kon niet worden '
          'opgeslagen. Sluit de app en log opnieuw in.');
      return;
    }

    // ─── 3. Accepteer: membership-write + race-mitigatie + alLid-check.
    final accept = await UitnodigingService.accepteer(
        token: widget.uitnodiging.token, gebruikerUid: uid);

    if (!accept.success && accept.fout != UitnodigingFout.alLid) {
      if (!mounted) return;
      setState(() => _bezig = false);
      switch (accept.fout) {
        case UitnodigingFout.kringVol:
          _toonFout('De kring zit nu vol. Vraag de uitnodiger of er '
              'ruimte vrijkomt, en kom dan via dezelfde code terug.');
          Navigator.of(context).pop('reset');
          break;
        case UitnodigingFout.kringNotFound:
          _toonFout('De kring uit deze uitnodiging bestaat niet meer.');
          Navigator.of(context).pop('reset');
          break;
        case UitnodigingFout.notFound:
          _toonFout('De uitnodiging is niet meer geldig.');
          Navigator.of(context).pop('reset');
          break;
        case UitnodigingFout.permissionGeweigerd:
          _toonFout('Deze uitnodiging kon niet worden geaccepteerd. '
              'Vraag de uitnodiger om een nieuwe code.');
          Navigator.of(context).pop('reset');
          break;
        default:
          _toonFout('Even een netwerkprobleem. Probeer opnieuw.');
      }
      return;
    }

    // ─── 4. Apparaat-registratie — niet kritiek, fail silent.
    // Fase 3c-B: kringId uit de uitnodiging meegeven zodat de Cloud
    // Function `onNieuwMoment` dit familie-apparaat als push-target
    // vindt binnen de host-kring.
    try {
      final apparaatId = await DeviceModusService.krijgApparaatId();
      await ApparaatService.registreer(
        familieUid: uid,
        apparaatId: apparaatId,
        persoonsNaam: naam,
        modus: 'familie',
        kringId: widget.uitnodiging.kringId,
      );
    } catch (_) {}

    // ─── 5. Lokale modus + actieve kring → host-kring uit uitnodiging.
    await DeviceModusService.zet(DeviceModusService.FAMILIE);
    await DeviceModusService.zetActieveKring(widget.uitnodiging.kringId);

    if (!mounted) return;
    // RouterScherm pakt auth+modus+kring op en toont FamilieScherm.
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.uitnodiging;
    return NormaalScaffold(
      backgroundColor: kCream,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: kBrown),
        title: const Text('Nieuw account',
            style: TextStyle(color: kBrown, fontWeight: FontWeight.w900)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(children: [
          const SizedBox(height: 4),
          // Warme kring-kaart met foto, naam en uitnodiger.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kWhite,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kPeachLight, width: 2),
              boxShadow: [BoxShadow(color: kPeach.withOpacity(0.08),
                  blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Row(children: [
              Container(width: 52, height: 52,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    color: kPeachPale,
                    border: Border.all(color: kPeach, width: 2),
                    image: (u.kringFoto != null && u.kringFoto!.isNotEmpty)
                        ? DecorationImage(image: NetworkImage(u.kringFoto!),
                            fit: BoxFit.cover) : null),
                child: (u.kringFoto == null || u.kringFoto!.isEmpty)
                    ? const Icon(Icons.person_rounded,
                        color: kPeach, size: 26)
                    : null),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Lid worden van '
                      '${u.kringNaam.isNotEmpty ? u.kringNaam : 'de kring'}',
                      style: const TextStyle(fontSize: 14,
                          fontWeight: FontWeight.w900, color: kBrown)),
                  if (u.uitnodigerNaam != null && u.uitnodigerNaam!.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 4),
                      child: Text('Uitgenodigd door ${u.uitnodigerNaam}',
                          style: const TextStyle(fontSize: 12,
                              color: kTextMuted))),
                ])),
            ]),
          ),
          const SizedBox(height: 24),

          const Text('Maak je account aan',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
                  color: kBrown, height: 1.2)),
          const SizedBox(height: 8),
          const Text('Daarna word je meteen lid van de kring.',
              style: TextStyle(fontSize: 14, color: kTextMuted, height: 1.4)),
          const SizedBox(height: 24),

          OWInvoer(emoji: '👤', label: 'JOUW VOORNAAM', hint: 'Bijv. Sara',
              controller: _naamCtrl),
          const SizedBox(height: 12),
          OWInvoer(emoji: '📧', label: 'E-MAILADRES', hint: 'voorbeeld@email.nl',
              controller: _emailCtrl,
              toetsenbord: TextInputType.emailAddress,
              hoofdletters: TextCapitalization.none),
          const SizedBox(height: 12),
          OWInvoer(emoji: '🔒', label: 'WACHTWOORD', hint: 'Minimaal 6 tekens',
              controller: _wachtwoordCtrl, verborgen: true),
          const SizedBox(height: 20),

          OWKnop(
            label: 'Aanmelden en deelnemen',
            onTap: _bezig ? null : _aanmelden,
            bezig: _bezig,
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: kCream,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kPeachLight, width: 1.5)),
            child: const Text(
              '💡 Je gegevens worden alleen gebruikt om je toegang te geven '
              'tot deze kring. De ontvanger-info (foto, herkenningsgeluid) '
              'is al ingesteld door de uitnodiger.',
              style: TextStyle(fontSize: 12, color: kTextMuted, height: 1.5)),
          ),
        ]),
      ),
    );
  }
}
