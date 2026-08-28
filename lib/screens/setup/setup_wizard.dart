import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import '../../services/apparaat_service.dart';
import '../../services/device_modus_service.dart';
import '../../services/kring_service.dart';
import '../../theme/kleuren.dart';
import '../../data/geluiden.dart';
import '../../data/kring.dart';
import '../../widgets/normaal_scaffold.dart';
import 'accept_uitnodig_scherm.dart';
import '../../widgets/ow_knop.dart';
import '../../widgets/ow_invoer.dart';

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
  bool _toonCarousel = false;
  final _carouselCtrl = PageController();
  int _carouselPagina = 0;

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

  /// V9 2.6-a-2: kringen waaruit de eigenaar mag kiezen bij ontvanger-
  /// setup van een NIEUW apparaat. null = nog niet bezig met keuze (toon
  /// account-velden of weergavemodus-stap). Niet-null = toon
  /// _ontvangerKringKeuzeStap(). Alleen relevant bij _rol=='ontvanger'.
  List<Kring>? _ontvangerKringen;

  /// V9 2.9-perf: id van de kring-kaart die op dit moment wordt
  /// verwerkt in _kiesOntvangerKring. Niet-null = toon spinner op die
  /// kaart en blokkeer taps op andere kaarten. Analoog aan _bezigModus
  /// in _modusKaart.
  String? _bezigKringId;

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
    _carouselCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_toonCarousel) {
      return NormaalScaffold(
        backgroundColor: kCream,
        body: _carousel(),
      );
    }
    return NormaalScaffold(
      backgroundColor: kCream,
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_stap > 0) _topBalk(),
          Expanded(child: SingleChildScrollView(child: _huidigeStap())),
          const SizedBox(height: 12),
          if (_stap > 0
              && !(_rol == 'ontvanger' && _stap == 2)
              && !(_rol == 'ontvanger' && _ontvangerKringen != null))
            _knop(),
        ]),
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
    // V9 2.6-a-2: bij kring-keuze breekt 'terug' de keuze af. Loggen uit
    // zodat ander account ingevuld kan worden — anders zit de eigenaar
    // vast in z'n eigen sessie zonder kring-keuze gemaakt te hebben.
    if (_rol == 'ontvanger' && _ontvangerKringen != null) {
      FirebaseAuth.instance.signOut();
      setState(() {
        _ontvangerKringen = null;
      });
      return;
    }
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
      if (nieuweRol == 'familie') {
        _toonCarousel = true;
      } else {
        _stap = 1;
      }
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
            'Is de kring al aangemaakt?',
            style: TextStyle(fontSize: 18,
                fontWeight: FontWeight.w900, color: kBrown))),
        ]),
        content: const Text(
          'Dit apparaat wordt ingesteld voor je dierbare — het toont '
          'straks de berichten, foto\'s en stemberichten van de '
          'kring.\n\n'
          'Daarvoor moet de eigenaar van de kring (degene die de '
          'kring heeft aangemaakt) eerst een account hebben op de '
          'eigen telefoon. Dit apparaat logt in met dat account.\n\n'
          'Is de kring al aangemaakt?',
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
      if (_stap == 1 && _ontvangerKringen != null) {
        return _ontvangerKringKeuzeStap();
      }
      if (_stap == 1) return _accountStap();
      if (_stap == 2) return _weergaveModusStap();
    }
    return const SizedBox();
  }

  // ───────────────────────────────────────────────────
  // CAROUSEL: WELKOMST-SCHERMEN (tonen vóór de wizard)
  // ───────────────────────────────────────────────────
  Widget _carousel() {
    return SafeArea(
      child: Stack(children: [
        PageView(
          controller: _carouselCtrl,
          onPageChanged: (i) => setState(() => _carouselPagina = i),
          children: [
            _carouselSlide(
              emoji: '📸',
              blobKleuren: const [Color(0xFFFFE8D6), Color(0xFFFFD4B8)],
              kop: 'Je wilt er zijn.\nOok als je er niet bent.',
              subtitel: 'Misschien woon je te ver weg. Misschien lukt bellen '
                  'niet meer zo goed, of vliegen de dagen voorbij. Maar je '
                  'denkt aan je dierbare. Ons Moment brengt je dichtbij, met '
                  'een foto, je stem of een liedje dat vanzelf bij je dierbare '
                  'aankomt.',
            ),
            _carouselSlide(
              emoji: '💕',
              blobKleuren: const [Color(0xFFFFD6E0), Color(0xFFFFB8CA)],
              kop: 'Zonder dat je dierbare\niets hoeft te doen.',
              subtitel: 'Bij een telefoontje of appje moet je dierbare zelf '
                  'opnemen, zoeken, of weten hoe het werkt. Bij Ons Moment '
                  'niet. Kan je dierbare nog zelf kijken en terugsturen? Dan '
                  'doet die mee, zo veel als die wil. Lukt dat niet meer? Dan '
                  'zet je het apparaat in de rustige modus, helemaal vergrendeld '
                  'op Ons Moment. Alles verschijnt dan vanzelf op het scherm, '
                  'zonder knoppen of gedoe.',
            ),
            _carouselSlide(
              emoji: '🌸',
              blobKleuren: const [Color(0xFFD4EDD4), Color(0xFFB8D8B8)],
              kop: 'Een klein moment.\nElke dag opnieuw.',
              subtitel: 'Nodig de mensen om je dierbare heen uit in een kring. '
                  'Samen vul je de dagen met berichtjes, foto\'s en '
                  'herinneringen. Met de dagelijkse agenda plan je vaste '
                  'momenten, zoals een goedemorgen of een liedje voor het '
                  'slapen. En wil je je dierbare zien? Met een videogesprek '
                  'kijk je elkaar in de ogen. Je kunt zelfs instellen dat de '
                  'oproep vanzelf beantwoord wordt.',
              isLaatste: true,
            ),
          ],
        ),
        if (_carouselPagina < 2)
          Positioned(
            top: 8,
            right: 16,
            child: TextButton(
              onPressed: () => setState(() { _toonCarousel = false; _stap = 1; }),
              child: const Text('Overslaan',
                  style: TextStyle(
                      color: kTextMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) => GestureDetector(
              onTap: () => _carouselCtrl.animateToPage(i,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: _carouselPagina == i ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _carouselPagina == i ? kPeach : kPeachLight,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            )),
          ),
        ),
      ]),
    );
  }

  Widget _carouselSlide({
    required String emoji,
    required List<Color> blobKleuren,
    required String kop,
    required String subtitel,
    bool isLaatste = false,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 80),
      child: Column(
        children: [
          Container(
            height: 220,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: blobKleuren,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 72)),
            ),
          ),
          const SizedBox(height: 32),
          Text(kop,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: kBrown,
                  height: 1.2)),
          const SizedBox(height: 12),
          Text(subtitel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15, color: kTextMuted, height: 1.5)),
          if (isLaatste) ...[
            const SizedBox(height: 32),
            OWKnop(
              label: 'Aan de slag',
              onTap: () => setState(() { _toonCarousel = false; _stap = 1; }),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () => setState(() { _toonCarousel = false; _stap = 1; _isInloggen = true; }),
              child: const Text('Al een account? Log in',
                  style: TextStyle(
                      fontSize: 14,
                      color: kPeach,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline)),
            ),
          ],
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────
  // STAP 0: ROL KEUZE (3 kaarten)
  // ───────────────────────────────────────────────────
  Widget _rolKeuze() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const SizedBox(height: 8),
    Center(child: Image.asset('assets/images/logo.png', height: 76)),
    const SizedBox(height: 28),
    const Text('Hoe gebruik jij\nOns Moment?',
        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900,
            color: kBrown, height: 1.2)),
    const SizedBox(height: 8),
    const Text('Kies hoe jij de app gebruikt.',
        style: TextStyle(fontSize: 15, color: kTextMuted, height: 1.4)),
    const SizedBox(height: 28),
    _keuzeKaart(
      emoji: '👨‍👩‍👧',
      titel: 'Familielid',
      uitleg: 'Jij bent de eigenaar: je maakt de kring aan, stelt alles in en nodigt anderen uit.',
      onTap: () => _kiesRol('familie'),
    ),
    const SizedBox(height: 14),
    _keuzeKaart(
      emoji: '💛',
      titel: 'Ontvanger',
      uitleg: 'Als eigenaar stel je dit in op het apparaat van je dierbare. Je dierbare hoeft zelf niets te doen.',
      onTap: () => _kiesRol('ontvanger'),
    ),
    const SizedBox(height: 14),
    _keuzeKaart(
      emoji: '🔑',
      titel: 'Uitnodigingscode',
      uitleg: 'Voor iedereen die door de eigenaar is uitgenodigd om mee te doen.',
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => const AcceptUitnodigScherm())),
    ),
  ]);

  Widget _keuzeKaart({
    required String emoji,
    required String titel,
    required String uitleg,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kPeachLight, width: 2),
        boxShadow: [BoxShadow(color: kPeach.withOpacity(0.08),
            blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
              color: kPeachPale, borderRadius: BorderRadius.circular(14)),
          child: Center(child: Text(emoji,
              style: const TextStyle(fontSize: 26))),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text(titel, style: const TextStyle(fontSize: 16,
              fontWeight: FontWeight.w900, color: kBrown)),
          const SizedBox(height: 4),
          Text(uitleg, style: const TextStyle(fontSize: 13,
              color: kBrownLight, height: 1.4)),
        ])),
        const SizedBox(width: 8),
        const Icon(Icons.arrow_forward_ios_rounded, color: kPeach, size: 16),
      ]),
    ),
  );

  // ───────────────────────────────────────────────────
  // STAP 1: ACCOUNT (registreren of inloggen)
  // ───────────────────────────────────────────────────
  Widget _accountStap() {
    final titel = _rol == 'ontvanger' ? 'Log in op dit apparaat'
        : (_isInloggen ? 'Welkom terug 👋' : 'Maak je account aan');
    final uitleg = _rol == 'ontvanger'
        ? 'Log in met het account van de eigenaar van de kring '
            '(degene die de kring heeft aangemaakt).'
        : (_isInloggen ? 'Log in met je e-mail en wachtwoord'
            : 'Daarna richt je samen met ons alles in voor je dierbare.');

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titel, style: const TextStyle(fontSize: 28,
          fontWeight: FontWeight.w900, color: kBrown, height: 1.2)),
      const SizedBox(height: 8),
      Text(uitleg, style: const TextStyle(fontSize: 14,
          color: kTextMuted, height: 1.4)),
      const SizedBox(height: 24),
      if (_rol == 'familie' && !_isInloggen) ...[
        OWInvoer(emoji: '👤', label: 'JOUW NAAM', hint: 'Bijv. Sara',
            controller: _naamCtrl),
        const SizedBox(height: 12),
      ],
      OWInvoer(emoji: '📧', label: 'E-MAILADRES', hint: 'voorbeeld@email.nl',
          controller: _emailCtrl, toetsenbord: TextInputType.emailAddress,
          hoofdletters: TextCapitalization.none),
      const SizedBox(height: 12),
      OWInvoer(emoji: '🔒', label: 'WACHTWOORD', hint: 'Minimaal 6 tekens',
          controller: _wachtwoordCtrl, verborgen: true),
      // V9 2.12-a-1: 'Wachtwoord vergeten?'-link alleen op inlog-paden
      // (familie+inloggen of ontvanger). Bij registreren niet — daar is
      // er nog geen account om te resetten.
      if (_rol == 'ontvanger' || (_rol == 'familie' && _isInloggen)) ...[
        const SizedBox(height: 8),
        Center(child: TextButton(
          onPressed: _wachtwoordVergetenAanvragen,
          child: const Text('Wachtwoord vergeten?',
              style: TextStyle(fontSize: 13, color: kPeach,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline))),
        ),
      ],
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
      // Netwerk- of onbekende fout: ook generiek. Gebruiker kan
      // opnieuw proberen of contact opnemen.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Als dit e-mailadres bij ons bekend is, sturen we '
          'je een e-mail om je wachtwoord opnieuw in te stellen. Kijk '
          'ook in je spam-map.'),
      backgroundColor: kPeach,
      duration: Duration(seconds: 6)));
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
        'De naam staat op het home-scherm. Extra info helpt de kring '
        'gerichte berichten te sturen.'),
    const SizedBox(height: 12),
    _input('👵', 'Naam van je dierbare',
        'Bijv. Oma, Opa, Mam, Pap...',
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
        'het voor te beluisteren. Helpt je dierbare het te herkennen als '
        'iets liefs.'),
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
        'toevoegen per moment via Instellingen → Momenten beheren.',
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
      && _ontvangerNaamCtrl.text.trim().isEmpty;

  Widget _knop() {
    final geblokkeerd = _ontvangerNaamVerplichtMaarLeeg;
    return OWKnop(
      label: _knopTekst(),
      onTap: geblokkeerd ? null : _volgende,
      bezig: _bezig,
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
      await DeviceModusService.zetActieveKringVoorEigenaar(uid);
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

      // V9 2.12-a-2: stuur verificatie-mail fire-and-forget. Zachte
      // variant: het account werkt direct, ongeacht of de mail wordt
      // bevestigd. Faalt silent bij netwerk/quota — geen blokkering.
      cred.user?.sendEmailVerification().catchError((Object _) {});

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
        'accountType': 'familie',
        'tier': 'klein',
        'kringAantal': 1,
        'aangemaaktOp': FieldValue.serverTimestamp(),
        'proefStart': FieldValue.serverTimestamp(),
      });

      // V9 schema: kring + eigenaar-membership atomair in batch.
      // KringId wordt teruggegeven zodat dagelijkse_momenten hieronder
      // hetzelfde id meekrijgen. eigenaarNaam (V9 2.8-a-1) belandt als
      // weergaveNaam in de eigenaar-leden-doc voor de kringleden-lijst.
      final kringId = KringService.voegKringMetEigenaarToeAanBatch(
        batch: batch,
        eigenaarUid: uid,
        ontvangerNaam: _ontvangerNaamCtrl.text.trim(),
        foto: profielFotoUrl,
        lievelingsdingen: _lievelingsdingenCtrl.text.trim(),
        woonplaats: _woonplaatsCtrl.text.trim(),
        noodcontactNaam: _noodNaamCtrl.text.trim(),
        noodcontactTel: _noodTelCtrl.text.trim(),
        herkenningsgeluid: _gekozenGeluid,
        eigenaarNaam: _naamCtrl.text.trim(),
      );

      for (final m in _momenten) {
        batch.set(
            FirebaseFirestore.instance.collection('dagelijkse_momenten').doc(),
            {
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
      // (sub-commit C) dit apparaat kan tonen. Fase 3c-B: kringId meegeven
      // zodat de Cloud Function `onNieuwMoment` dit familie-apparaat als
      // push-target vindt binnen de kring.
      final apparaatId = await DeviceModusService.krijgApparaatId();
      await ApparaatService.registreer(
        familieUid: uid,
        apparaatId: apparaatId,
        persoonsNaam: _naamCtrl.text.trim(),
        modus: 'familie',
        kringId: kringId,
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
      // V9 2.9-perf: start apparaat-doc.get en mijnKringen parallel.
      // Beide hangen alleen af van uid + apparaatId; geen onderlinge
      // dependency. Bekend-tak gebruikt alleen doc en negeert
      // mijneKringenFuture (.ignore). Nieuw-tak awaitet beide.
      final docFuture = FirebaseFirestore.instance
          .collection('gebruikers').doc(uid)
          .collection('apparaten').doc(apparaatId).get();
      final mijneKringenFuture = KringService.mijnKringen(uid);
      final doc = await docFuture;
      if (doc.exists) {
        // V9 2.9-perf: parallelle mijneKringenFuture is in deze tak
        // niet meer nodig — fail-soft ignoren zodat een eventuele
        // fout geen unhandled-exception wordt.
        mijneKringenFuture.ignore();
        // V9 2.6-a-1: bekend apparaat — als kringId in doc staat (gezet
        // door _voltooiOntvanger op een vorige setup), gebruik die.
        // Anders fallback naar .limit(1)-eigenaarskring (legacy
        // gedrag, geen regressie).
        final kringIdInDoc = doc.data()?['kringId'] as String?;
        if (kringIdInDoc != null && kringIdInDoc.isNotEmpty) {
          await DeviceModusService.zetActieveKring(kringIdInDoc);
        } else {
          await DeviceModusService.zetActieveKringVoorEigenaar(uid);
        }
        // Bekend apparaat — lees opgeslagen weergaveModus, geen keuze nodig
        final wm = (doc.data()?['weergaveModus'] as String?)
                   ?? DeviceModusService.VERGRENDELD;
        ApparaatService.updateLaatstActief(
            familieUid: uid, apparaatId: apparaatId);
        await DeviceModusService.zetWeergaveModus(wm);
        await DeviceModusService.zet(DeviceModusService.ONTVANGER);
      } else {
        // V9 2.6-a-2: nieuw apparaat — bepaal welke kring (welke
        // dierbare) dit apparaat moet tonen. Alleen eigen kringen
        // (eigenaarUid == uid): een gast-account kan geen ontvanger-
        // tablet aan een andermans kring koppelen. V9 2.9-perf:
        // gebruikt de mijneKringenFuture die parallel met doc.get is
        // gestart, dus geen extra round-trip-wachttijd.
        final alleKringen = await mijneKringenFuture;
        final eigenKringen =
            alleKringen.where((k) => k.eigenaarUid == uid).toList();
        if (eigenKringen.isEmpty) {
          // 0 kringen: typisch een gast die zich vergiste in de rol.
          // Vriendelijke melding + uitloggen zodat de gebruiker niet
          // ingelogd-zonder-modus vastloopt in RouterScherm.
          _toonFout('Dit account heeft nog geen eigen kring. Maak '
              'eerst een kring aan vanaf je eigen telefoon, en stel '
              'daarna dit apparaat in.');
          await FirebaseAuth.instance.signOut();
          if (mounted) setState(() => _ontvangerKringen = null);
        } else if (eigenKringen.length == 1) {
          // 1 kring: automatisch, geen extra scherm. Identiek aan
          // bestaand gedrag voor de meeste gebruikers.
          await DeviceModusService
              .zetActieveKring(eigenKringen.first.id);
          if (mounted) setState(() => _stap = 2);
        } else {
          // 2+ kringen: laat de eigenaar kiezen vóór welke dierbare
          // dit apparaat is. _kiesOntvangerKring zet de keuze en
          // schuift door naar de weergavemodus-stap.
          if (mounted) {
            setState(() => _ontvangerKringen = eigenKringen);
          }
        }
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
    OWInvoer(emoji: '👤', label: 'JOUW NAAM', hint: 'Bijv. Sara',
        controller: _naamCtrl),
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
      // Fase 3c-B: kringId komt uit de actieve-kring-notifier — bij een
      // familie-login op een bestaande kring is die typisch al gezet
      // door de vorige sessie. Als 'ie null is (verse install of eerst
      // uitgelogd geweest), schrijft registreer() het veld gewoon niet
      // en pikt PushService.registreerHuidigApparaat de backfill op via
      // collectionGroup('leden') zodra de fcmToken binnenkomt.
      final apparaatId = await DeviceModusService.krijgApparaatId();
      await ApparaatService.registreer(
        familieUid: uid,
        apparaatId: apparaatId,
        persoonsNaam: naam,
        modus: 'familie',
        kringId: DeviceModusService.actieveKringNotifier.value,
      );
      await DeviceModusService.zet(DeviceModusService.FAMILIE);
    } finally {
      if (mounted) setState(() => _bezig = false);
    }
  }

  // ───────────────────────────────────────────────────
  // STAP 1b: KRING-KEUZE (route C — ontvanger, 2+ eigen kringen, V9 2.6-a-2)
  // ───────────────────────────────────────────────────
  Widget _ontvangerKringKeuzeStap() {
    final kringen = _ontvangerKringen ?? const <Kring>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Voor welke dierbare is dit apparaat?',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
              color: kBrown, height: 1.2)),
      const SizedBox(height: 8),
      const Text('Je hebt meer dan één kring. Kies hieronder wie deze '
          'tablet of telefoon gaat zien.',
          style: TextStyle(fontSize: 14, color: kTextMuted, height: 1.4)),
      const SizedBox(height: 20),
      ...kringen.map((k) {
        // V9 2.9-perf: dim niet-geklikte kaarten + spinner op de
        // geklikte kaart zodra _bezigKringId gezet is.
        final bezigDeze = _bezigKringId == k.id;
        final bezigAndere = _bezigKringId != null && !bezigDeze;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Opacity(opacity: bezigAndere ? 0.4 : 1.0,
            child: GestureDetector(
              onTap: (_bezig || _bezigKringId != null)
                  ? null : () => _kiesOntvangerKring(k),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: kWhite,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: kPeachLight, width: 2),
                    boxShadow: [BoxShadow(color: kPeach.withOpacity(0.08),
                        blurRadius: 12, offset: const Offset(0, 4))]),
                child: Row(children: [
                  Container(width: 56, height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kPeachPale,
                      border: Border.all(color: kPeach, width: 2),
                      image: (k.foto != null && k.foto!.isNotEmpty)
                          ? DecorationImage(image: NetworkImage(k.foto!),
                              fit: BoxFit.cover) : null),
                    child: (k.foto == null || k.foto!.isEmpty)
                        ? const Center(child: Icon(Icons.person_rounded,
                            color: kPeach, size: 28))
                        : null),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(k.naam.isNotEmpty ? k.naam : 'Onbenoemde kring',
                          style: const TextStyle(fontSize: 16,
                              fontWeight: FontWeight.w800, color: kBrown)),
                      if (k.lievelingsdingen != null
                          && k.lievelingsdingen!.isNotEmpty)
                        Padding(padding: const EdgeInsets.only(top: 2),
                          child: Text(k.lievelingsdingen!,
                              style: const TextStyle(fontSize: 12,
                                  color: kTextMuted, height: 1.3),
                              maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ])),
                  if (bezigDeze)
                    const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            color: kPeach, strokeWidth: 2.5))
                  else
                    const Icon(Icons.arrow_forward_ios_rounded,
                        color: kPeach, size: 16),
                ]),
              ),
            ),
          ),
        );
      }),
    ]);
  }

  Future<void> _kiesOntvangerKring(Kring kring) async {
    // V9 2.9-perf: directe visuele feedback (spinner op aangeklikte
    // kaart, andere kaarten dimmen) zodat de tik niet "onresponsief"
    // voelt. zetActieveKring is SharedPrefs en is in zichzelf snel,
    // maar zonder feedback denken gebruikers dat hun tik niet
    // geregistreerd is.
    setState(() => _bezigKringId = kring.id);
    await DeviceModusService.zetActieveKring(kring.id);
    if (!mounted) return;
    setState(() {
      _ontvangerKringen = null;
      _stap = 2;
      _bezigKringId = null;
    });
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
      // V9 2.6-a-1: actieve kring uit SharedPreferences (gezet door
      // _ontvangerInloggenActie via zetActieveKringVoorEigenaar of door
      // de multi-kring keuze in 2.6-a-2) meegeven zodat het apparaat-doc
      // 'm vastlegt.
      final kringId = await DeviceModusService.krijgActieveKring();
      // V9 2.11-a-1: lees naam EN foto uit het kring-doc i.p.v. uit
      // gebruikers/{uid}.ontvangerNaam / ontvangerFoto. Die laatste
      // velden zijn account-breed en lekken bij multi-kring eigenaars
      // de naam/foto van kring A in kring B. kringen/{kringId}.naam
      // is per kring uniek (geschreven door
      // KringService.voegKringMetEigenaarToeAanBatch).
      String naam = 'Ontvanger';
      if (kringId != null && kringId.isNotEmpty) {
        try {
          final kringDoc = await FirebaseFirestore.instance
              .collection('kringen').doc(kringId).get();
          final data = kringDoc.data();
          final kringNaam = data?['naam'] as String?;
          if (kringNaam != null && kringNaam.isNotEmpty) {
            naam = kringNaam;
          }
          // Schrijf naam-cache + precache foto fire-and-forget zodat
          // TabletScherm de banner instant kan tonen. kringId-tagged
          // cache voorkomt cross-kring naam-lek.
          if (naam.isNotEmpty && naam != 'Ontvanger') {
            DeviceModusService.zetGecachteOntvangerNaam(kringId, naam);
          }
          final fotoUrl = data?['foto'] as String?;
          if (fotoUrl != null && fotoUrl.isNotEmpty && mounted) {
            precacheImage(NetworkImage(fotoUrl), context)
                .catchError((Object _) {});
          }
        } catch (_) {}
      }
      // V9 2.7: GEEN kanNieuwePersoonToevoegen-check hier — een
      // ontvanger-tablet koppelen voegt geen kringlid toe, dus de
      // tier-limiet hoort niet van toepassing. De dierbare is geen
      // membership-houder (FAQ-belofte).
      await ApparaatService.registreer(
        familieUid: uid,
        apparaatId: apparaatId,
        persoonsNaam: naam,
        modus: 'ontvanger',
        weergaveModus: weergaveModus,
        kringId: kringId,
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
