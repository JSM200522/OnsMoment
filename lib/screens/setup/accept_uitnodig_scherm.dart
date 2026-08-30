import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/uitnodiging.dart';
import '../../services/apparaat_service.dart';
import '../../services/device_modus_service.dart';
import '../../services/uitnodiging_service.dart';
import '../../theme/kleuren.dart';
import '../../widgets/normaal_scaffold.dart';
import '../../widgets/ow_knop.dart';
import '../../widgets/ow_invoer.dart';
import 'gast_signup_scherm.dart';

/// Accept-flow voor een uitnodig-link of -code (V9 2.5-a-3-a).
///
/// Drie zichtbare secties op basis van state:
/// 1. Token-invoer (TextField + 'Volgende'-knop) — tot uitnodiging is
///    gevalideerd.
/// 2. Preview (kring-naam + foto + uitnodiger + plekkenstand) + 2
///    keuze-knoppen 'Ik heb al een account' / 'Nieuw account'.
/// 3. Inlog-velden (email + wachtwoord) na klik op 'Ik heb al een
///    account' — eigen lokale tak, hergebruikt _familieInloggen NIET.
///
/// 2.5-a-3-a bouwt alleen de inlog-tak; signup-knop toont voorlopig
/// een 'Komt eraan'-snackbar (signup-flow is 2.5-a-3-b).
class AcceptUitnodigScherm extends StatefulWidget {
  /// Optioneel: token meegeven om de invoer-stap over te slaan
  /// (gebruikt door 2.5-a-4 deeplink-handler).
  final String? initialToken;

  const AcceptUitnodigScherm({super.key, this.initialToken});

  @override
  State<AcceptUitnodigScherm> createState() => _AcceptUitnodigSchermState();
}

class _AcceptUitnodigSchermState extends State<AcceptUitnodigScherm> {
  final _tokenCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _wachtwoordCtrl = TextEditingController();

  Uitnodiging? _uitnodiging;
  UitnodigingFout? _validatieFout;
  bool _bezigValideren = false;
  bool _toonInlogVelden = false;
  bool _bezigInloggen = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialToken != null && widget.initialToken!.isNotEmpty) {
      _tokenCtrl.text = widget.initialToken!;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _valideerToken());
    }
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _emailCtrl.dispose();
    _wachtwoordCtrl.dispose();
    super.dispose();
  }

  Future<void> _valideerToken() async {
    if (_tokenCtrl.text.trim().isEmpty) return;
    setState(() {
      _bezigValideren = true;
      _validatieFout = null;
      _uitnodiging = null;
    });
    final result = await UitnodigingService.valideer(_tokenCtrl.text);
    if (!mounted) return;
    setState(() {
      _bezigValideren = false;
      _uitnodiging = result.uitnodiging;
      _validatieFout = result.fout;
    });
  }

  Future<void> _gastInloggen() async {
    final uitnodiging = _uitnodiging;
    if (uitnodiging == null) return;
    final email = _emailCtrl.text.trim();
    final ww = _wachtwoordCtrl.text;
    if (email.isEmpty || ww.isEmpty) {
      _toonFout('Vul e-mailadres en wachtwoord in.');
      return;
    }
    setState(() => _bezigInloggen = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email, password: ww);
      final uid = FirebaseAuth.instance.currentUser!.uid;

      final acceptResult = await UitnodigingService.accepteer(
          token: uitnodiging.token, gebruikerUid: uid);

      // V9 2.5-a-3-a — Optie B (bewust): bij accept-fout NA succesvolle
      // login blijft het account ingelogd. Geen rollback. Gast kan via
      // SetupWizard opnieuw een (andere) code proberen of de uitnodiger
      // om een nieuwe code vragen.
      if (acceptResult.success) {
        await _afrondenEnNaarFamilie(uitnodiging);
        return;
      }
      if (acceptResult.fout == UitnodigingFout.alLid) {
        // Idempotent — al lid, geen melding nodig
        await _afrondenEnNaarFamilie(uitnodiging);
        return;
      }
      if (!mounted) return;
      setState(() => _bezigInloggen = false);
      _toonAcceptFout(acceptResult.fout);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _bezigInloggen = false);
        if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
          _toonFout('Wachtwoord klopt niet. Probeer opnieuw.');
        } else if (e.code == 'user-not-found') {
          _toonFout('Geen account gevonden met dit e-mailadres. '
              'Klik op "Maak een nieuw account aan".');
        } else {
          _toonFout('Inloggen mislukt: ${e.code}');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _bezigInloggen = false);
        _toonFout('Inloggen mislukt — probeer opnieuw.');
      }
    }
  }

  Future<void> _afrondenEnNaarFamilie(Uitnodiging uitnodiging) async {
    // Apparaat registreren binnen GAST's eigen gebruikers/{uid}/apparaten
    // subcollectie zodat _KringWachter werkt en de gast in 'kringleden
    // beheren' van de host-kring nog niet zichtbaar wordt — wel in z'n
    // eigen account-context.
    final apparaatId = await DeviceModusService.krijgApparaatId();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        // Fase 3c-B: kringId uit de uitnodiging meegeven zodat de Cloud
        // Function `onNieuwMoment` dit familie-apparaat als push-target
        // vindt binnen de host-kring.
        await ApparaatService.registreer(
          familieUid: uid,
          apparaatId: apparaatId,
          persoonsNaam: 'Kringlid',
          modus: 'familie',
          kringId: uitnodiging.kringId,
        );
      } catch (_) {
        // Apparaat-registratie is niet kritiek voor de accept zelf.
      }
    }
    await DeviceModusService.zet(DeviceModusService.FAMILIE);
    await DeviceModusService.zetActieveKring(uitnodiging.kringId);
    if (!mounted) return;
    // Terug naar root → RouterScherm ziet auth+modus → toont FamilieScherm
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _toonAcceptFout(UitnodigingFout? fout) {
    final tekst = switch (fout) {
      UitnodigingFout.kringVol => 'De kring zit nu vol. Vraag de '
          'uitnodiger of er ruimte vrijkomt.',
      UitnodigingFout.kringNotFound =>
          'De kring uit deze uitnodiging bestaat niet meer.',
      UitnodigingFout.notFound =>
          'De uitnodiging is niet meer geldig.',
      UitnodigingFout.permissionGeweigerd =>
          'Deze uitnodiging kon niet worden geaccepteerd. Vraag de '
          'uitnodiger om een nieuwe code.',
      _ => 'Even een netwerkprobleem. Probeer opnieuw.',
    };
    _toonFout(tekst);
  }

  void _toonFout(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: kRood,
      duration: const Duration(seconds: 5)));
  }

  @override
  Widget build(BuildContext context) {
    return NormaalScaffold(
      backgroundColor: kCream,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: kBrown),
        title: const Text('Uitnodiging',
            style: TextStyle(color: kBrown, fontWeight: FontWeight.w900)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(children: [
          if (_uitnodiging == null) ..._tokenInvoerSectie()
          else ..._previewEnKeuzeSectie(_uitnodiging!),
          if (_toonInlogVelden) ..._inlogSectie(),
        ]),
      ),
    );
  }

  // ─── 1. Token-invoer ────────────────────────────────────────────────

  List<Widget> _tokenInvoerSectie() => [
    const SizedBox(height: 8),
    const Text('Je bent uitgenodigd',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
            color: kBrown, height: 1.2)),
    const SizedBox(height: 8),
    const Text('Vul hier de uitnodig-code in die je hebt gekregen. '
        'De code bestaat uit groepjes letters en cijfers met streepjes.',
        style: TextStyle(fontSize: 14, color: kTextMuted, height: 1.4)),
    const SizedBox(height: 28),

    // Custom monospace-veld in dezelfde stijl als OWInvoer.
    const Text('UITNODIG-CODE',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
            color: kTextMuted, letterSpacing: 0.3)),
    const SizedBox(height: 5),
    Container(
      decoration: BoxDecoration(color: kWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kPeachLight, width: 2)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 52, color: kPeachPale, alignment: Alignment.center,
              child: const Text('🔑', style: TextStyle(fontSize: 20))),
            Expanded(child: TextField(
              controller: _tokenCtrl,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.none,
              // Voorkomt dat mobiele toetsenborden tekens 'verbeteren' of
              // eerste letter hoofdgevoelig maken bij overtypen van code.
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              decoration: const InputDecoration(
                hintText: 'aB3c-D4eF-5gH6-iJ7k-lM8n',
                hintStyle: TextStyle(color: kPeachLight, letterSpacing: 1.2),
                border: InputBorder.none,
                contentPadding: EdgeInsets.fromLTRB(12, 18, 12, 18),
              ),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                  color: kBrown, fontFamily: 'monospace', letterSpacing: 1.2),
            )),
          ]),
        ),
      ),
    ),
    const SizedBox(height: 16),

    if (_validatieFout != null) ..._validatieFoutBlok(_validatieFout!),

    OWKnop(
      label: 'Volgende',
      onTap: _bezigValideren ? null : _valideerToken,
      bezig: _bezigValideren,
    ),
  ];

  List<Widget> _validatieFoutBlok(UitnodigingFout fout) {
    final tekst = switch (fout) {
      UitnodigingFout.notFound =>
          'Deze code is niet gevonden. Klopt \'m precies?',
      UitnodigingFout.kringNotFound =>
          'De kring uit deze uitnodiging bestaat niet meer.',
      UitnodigingFout.netwerk =>
          'Even een netwerkprobleem. Probeer opnieuw.',
      _ => 'Onbekende fout — probeer opnieuw.',
    };
    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: kRood.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kRood, width: 1.5)),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, color: kRood, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(tekst,
              style: const TextStyle(fontSize: 13, color: kRood))),
        ]),
      ),
      const SizedBox(height: 16),
    ];
  }

  // ─── 2. Preview + keuze ─────────────────────────────────────────────

  List<Widget> _previewEnKeuzeSectie(Uitnodiging u) {
    final plekChipKleur = u.ruimte ? kGreen : kRood;
    final plekChipTekst = u.ruimte
        ? 'Plek ${u.huidigeLeden} van ${u.maxLeden} bezet'
        : 'Kring is vol (${u.maxLeden} kringleden)';

    return [
      const SizedBox(height: 8),
      // Warme kring-kaart met foto, naam, uitnodiger en plekchip.
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: kWhite,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kPeachLight, width: 2),
          boxShadow: [BoxShadow(color: kPeach.withOpacity(0.08),
              blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(children: [
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle, color: kPeachPale,
              border: Border.all(color: kPeach, width: 3),
              image: (u.kringFoto != null && u.kringFoto!.isNotEmpty)
                  ? DecorationImage(image: NetworkImage(u.kringFoto!),
                      fit: BoxFit.cover)
                  : null,
            ),
            child: (u.kringFoto == null || u.kringFoto!.isEmpty)
                ? const Center(child: Icon(Icons.person_rounded,
                    color: kPeach, size: 44))
                : null,
          ),
          const SizedBox(height: 16),
          Text(u.kringNaam.isNotEmpty ? u.kringNaam : 'Een kring',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22,
                  fontWeight: FontWeight.w900, color: kBrown)),
          const SizedBox(height: 4),
          Text(
            u.uitnodigerNaam != null && u.uitnodigerNaam!.isNotEmpty
                ? 'Uitgenodigd door ${u.uitnodigerNaam}'
                : 'Uitgenodigd door familie',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: kTextMuted)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: plekChipKleur,
                borderRadius: BorderRadius.circular(8)),
            child: Text(plekChipTekst,
                style: const TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w800, color: kWhite,
                    letterSpacing: 0.4)),
          ),
        ]),
      ),
      const SizedBox(height: 24),

      if (!u.ruimte) ..._kringVolBlok()
      else ..._keuzeKnoppen(),
    ];
  }

  List<Widget> _kringVolBlok() => [
    Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kRood.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kRood, width: 1.5)),
      child: const Text(
        'Deze kring zit vol. Vraag de uitnodiger of er ruimte '
        'vrijkomt voordat je lid kunt worden.',
        style: TextStyle(fontSize: 13, color: kRood, height: 1.4)),
    ),
    const SizedBox(height: 16),
    Center(child: TextButton(
      onPressed: () => Navigator.pop(context),
      child: const Text('Terug',
          style: TextStyle(color: kTextMuted,
              fontWeight: FontWeight.w700)))),
  ];

  List<Widget> _keuzeKnoppen() => [
    OWKnop(
      label: 'Ik heb al een account',
      onTap: () => setState(() => _toonInlogVelden = true),
    ),
    const SizedBox(height: 12),
    OWKnopSecundair(
      label: 'Maak een nieuw account aan',
      onTap: () => _naarGastSignup(),
    ),
  ];

  Future<void> _naarGastSignup() async {
    final u = _uitnodiging;
    if (u == null) return;
    final result = await Navigator.of(context).push<String?>(
      MaterialPageRoute(builder: (_) => GastSignupScherm(uitnodiging: u)),
    );
    if (!mounted) return;
    // Bij accept-fout NA succesvolle createUser (Optie B) komt de gast
    // terug met 'reset' — laat 'm meteen een andere code proberen.
    if (result == 'reset') {
      setState(() {
        _uitnodiging = null;
        _validatieFout = null;
        _toonInlogVelden = false;
        _tokenCtrl.clear();
      });
    }
  }

  /// V9 2.12-a-1: stuurt een wachtwoord-reset-mail via Firebase Auth.
  /// Gebruikt het al ingevoerde e-mailadres uit _emailCtrl. Anti-
  /// enumeratie: behalve bij invalid-email tonen we altijd dezelfde
  /// generieke succes-melding (ook bij user-not-found of netwerk).
  Future<void> _wachtwoordVergetenAanvragen() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty
        || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _toonFout('Vul eerst je e-mailadres in');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-email') {
        _toonFout('E-mailadres lijkt niet te kloppen');
        return;
      }
      // user-not-found en alle andere FirebaseAuth-fouten: door naar
      // de generieke succes-melding (anti-enumeratie).
    } catch (_) {
      // Netwerk- of onbekende fout: ook generiek.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Als dit e-mailadres bij ons bekend is, sturen we '
          'je een e-mail om je wachtwoord opnieuw in te stellen. Kijk '
          'ook in je spam-map.'),
      backgroundColor: kPeach,
      duration: Duration(seconds: 6)));
  }

  // ─── 3. Inlog-velden ────────────────────────────────────────────────

  List<Widget> _inlogSectie() => [
    const SizedBox(height: 24),
    const Text('Log in met je bestaande account',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
            color: kBrown)),
    const SizedBox(height: 16),
    OWInvoer(emoji: '📧', label: 'E-MAILADRES', hint: 'voorbeeld@email.nl',
        controller: _emailCtrl,
        toetsenbord: TextInputType.emailAddress,
        hoofdletters: TextCapitalization.none),
    const SizedBox(height: 12),
    OWInvoer(emoji: '🔒', label: 'WACHTWOORD', hint: 'Je wachtwoord',
        controller: _wachtwoordCtrl, verborgen: true),
    const SizedBox(height: 8),
    Center(child: TextButton(
      onPressed: _wachtwoordVergetenAanvragen,
      child: const Text('Wachtwoord vergeten?',
          style: TextStyle(fontSize: 13, color: kPeach,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline))),
    ),
    const SizedBox(height: 8),

    OWKnop(
      label: 'Inloggen en deelnemen',
      onTap: _bezigInloggen ? null : _gastInloggen,
      bezig: _bezigInloggen,
    ),
    const SizedBox(height: 24),
  ];
}
