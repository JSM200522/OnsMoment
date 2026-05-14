import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ============================================================
// ONS MOMENT — VOLLEDIGE APP IN ÉÉN BESTAND
// Scherm 1: TabletScherm (voor Jan)
// Scherm 2: FamilieApp (voor Sara/dochter)
// Scherm 3: SetupWizard (eerste installatie)
// ============================================================

// ─── KLEUREN ───────────────────────────────────────────────
const Color kPeach      = Color(0xFFFF9B71);
const Color kPeachLight = Color(0xFFFFD4C2);
const Color kPeachPale  = Color(0xFFFFF0EA);
const Color kRose       = Color(0xFFFF7B9C);
const Color kCream      = Color(0xFFFFFAF7);
const Color kBrown      = Color(0xFF5C3D2E);
const Color kBrownLight = Color(0xFF8B6354);
const Color kTextMuted  = Color(0xFF9B7565);
const Color kWhite      = Color(0xFFFFFFFF);

// ─── MAIN ──────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const OnsMonentApp());
}

class OnsMonentApp extends StatelessWidget {
  const OnsMonentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ons Moment',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Nunito',
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kPeach),
        scaffoldBackgroundColor: kPeachPale,
      ),
      initialRoute: '/setup',
      routes: {
        '/setup':   (ctx) => const SetupWizard(),
        '/tablet':  (ctx) => const TabletScherm(),
        '/familie': (ctx) => const FamilieApp(),
      },
    );
  }
}

// ============================================================
// SCHERM 1 — TABLET SCHERM (voor Jan, persoon met dementie)
// Grote klok, popup met stemberichtje, foto's, agenda
// ============================================================

class TabletScherm extends StatefulWidget {
  const TabletScherm({super.key});
  @override
  State<TabletScherm> createState() => _TabletSchermState();
}

class _TabletSchermState extends State<TabletScherm>
    with TickerProviderStateMixin {
  int _tab = 0;
  bool _speeltAf = false;
  late Timer _klokTimer;
  late AnimationController _popupCtrl;
  late Animation<double> _popupAnim;

  final _moment = {
    'van': 'Sara & de kinderen',
    'bericht': 'Goedemorgen papa! We denken aan je 💕',
    'emoji': '🌸',
    'duur': '0:12',
  };

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _klokTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => setState(() {}));
    _popupCtrl = AnimationController(
        duration: const Duration(milliseconds: 700), vsync: this);
    _popupAnim =
        CurvedAnimation(parent: _popupCtrl, curve: Curves.elasticOut);
    _popupCtrl.forward();
  }

  @override
  void dispose() {
    _klokTimer.cancel();
    _popupCtrl.dispose();
    super.dispose();
  }

  String get _tijd {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  String get _datum {
    final n = DateTime.now();
    const dagen = [
      'Maandag', 'Dinsdag', 'Woensdag', 'Donderdag',
      'Vrijdag', 'Zaterdag', 'Zondag'
    ];
    const maanden = [
      'januari', 'februari', 'maart', 'april', 'mei', 'juni',
      'juli', 'augustus', 'september', 'oktober', 'november', 'december'
    ];
    return '${dagen[n.weekday - 1]} ${n.day} ${maanden[n.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPeachPale,
      body: SafeArea(
        child: Column(children: [
          // ── KLOK BOVENAAN ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
            child: Column(children: [
              Text(
                _tijd,
                style: const TextStyle(
                  fontSize: 80,
                  fontWeight: FontWeight.w900,
                  color: kBrown,
                  height: 1.0,
                  letterSpacing: -3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _datum,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: kTextMuted,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // ── TABINHOUD ──
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _tab == 0
                  ? _vandaag()
                  : _tab == 1
                      ? _fotos()
                      : _tab == 2
                          ? _agenda()
                          : _videos(),
            ),
          ),

          // ── BOTTOM NAV ──
          _bottomNav(),
        ]),
      ),
    );
  }

  // ── VANDAAG TAB ──
  Widget _vandaag() => ScaleTransition(
        scale: _popupAnim,
        child: Container(
          decoration: BoxDecoration(
            color: kWhite,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: kBrown.withOpacity(0.12),
                blurRadius: 32,
                offset: const Offset(0, 8),
              )
            ],
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Foto gedeelte
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kPeachLight, kRose.withOpacity(0.5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(children: [
                  Center(
                    child: Text(_moment['emoji']!,
                        style: const TextStyle(fontSize: 72)),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: kWhite.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Text(
                        '📸 Nieuw moment',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: kRose,
                        ),
                      ),
                    ),
                  ),
                ]),
              ),

              // Tekst + audiobalk
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_moment['van']} 💕',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: kPeach,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _moment['bericht']!,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: kBrown,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Audiobalk
                    GestureDetector(
                      onTap: () => setState(() => _speeltAf = !_speeltAf),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: kPeachPale,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Row(children: [
                          // Play knop
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                  colors: [kPeach, kRose]),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: kPeach.withOpacity(0.45),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                )
                              ],
                            ),
                            child: Icon(
                              _speeltAf ? Icons.pause : Icons.play_arrow,
                              color: kWhite,
                              size: 30,
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Geluidsgolven
                          Expanded(
                            child: Row(
                              children: List.generate(
                                16,
                                (i) => Expanded(
                                  child: AnimatedContainer(
                                    duration: Duration(
                                        milliseconds: 150 + i * 40),
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 1),
                                    height: _speeltAf
                                        ? (6 + (i % 4) * 7).toDouble()
                                        : (i < 8 ? 14.0 : 7.0),
                                    decoration: BoxDecoration(
                                      color: i < 8 ? kPeach : kPeachLight,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _moment['duur']!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: kTextMuted,
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  // ── FOTO'S TAB ──
  Widget _fotos() {
    final items = ['🌸', '👨‍👩‍👧', '🏖️', '🎂', '🌿', '❤️'];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [kPeachLight, kRose.withOpacity(0.4)]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
            child: Text(items[i], style: const TextStyle(fontSize: 48))),
      ),
    );
  }

  // ── AGENDA TAB ──
  Widget _agenda() {
    final items = [
      {'t': '10:00', 'v': 'Sara komt op bezoek 💕'},
      {'t': '14:00', 'v': 'Medicijnen innemen 💊'},
      {'t': '16:00', 'v': 'Wandeling in de tuin 🌿'},
    ];
    return Column(
      children: items
          .map((a) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kWhite,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: kBrown.withOpacity(0.08), blurRadius: 12)
                  ],
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: kPeachPale,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text(a['t']!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: kPeach,
                          fontSize: 16,
                        )),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(a['v']!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: kBrown,
                        )),
                  ),
                ]),
              ))
          .toList(),
    );
  }

  // ── VIDEO'S TAB ──
  Widget _videos() => Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 60),
          child: Column(children: [
            const Text('🎬', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text("Nog geen video's",
                style: TextStyle(fontSize: 18, color: kTextMuted)),
          ]),
        ),
      );

  // ── BOTTOM NAVIGATIE ──
  Widget _bottomNav() {
    final tabs = [
      {'icon': Icons.home_rounded, 'label': 'Vandaag'},
      {'icon': Icons.photo_rounded, 'label': "Foto's"},
      {'icon': Icons.calendar_today_rounded, 'label': 'Agenda'},
      {'icon': Icons.videocam_rounded, 'label': "Video's"},
    ];
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: kBrown.withOpacity(0.08), blurRadius: 16)
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: tabs.asMap().entries.map((e) {
          final sel = _tab == e.key;
          return GestureDetector(
            onTap: () => setState(() => _tab = e.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? kPeachPale : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(e.value['icon'] as IconData,
                    color: sel ? kPeach : kTextMuted, size: 24),
                const SizedBox(height: 4),
                Text(
                  e.value['label'] as String,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: sel ? kPeach : kTextMuted,
                  ),
                ),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ============================================================
// SCHERM 2 — FAMILIE APP (voor Sara/dochter)
// Stemberichtje, foto, video, muziek versturen naar Jan
// ============================================================

class FamilieApp extends StatefulWidget {
  const FamilieApp({super.key});
  @override
  State<FamilieApp> createState() => _FamilieAppState();
}

class _FamilieAppState extends State<FamilieApp> {
  int _type = 0;
  bool _ingedrukt = false;

  final _typen = [
    {'icon': '🎙️', 'naam': 'Stemberichtje', 'sub': 'Jouw stem'},
    {'icon': '📸', 'naam': 'Foto',           'sub': 'Met bericht'},
    {'icon': '🎬', 'naam': 'Filmpje',        'sub': 'Max 1 min'},
    {'icon': '🎵', 'naam': 'Muziek',         'sub': 'Favoriet liedje'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: kBrown),
          onPressed: () => Navigator.of(context).pushReplacementNamed('/tablet'),
        ),
        title: const Text(
          'Stuur een moment',
          style: TextStyle(
            color: kBrown,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [kPeach, kRose]),
              shape: BoxShape.circle,
            ),
            child: const Center(
                child: Text('😊', style: TextStyle(fontSize: 20))),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── ONTVANGER KAART ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [kPeach, kRose],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(children: [
              const Text('👴', style: TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Papa — Jan',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: kWhite,
                        )),
                    Text('Tablet aan · thuis',
                        style: TextStyle(
                          fontSize: 12,
                          color: kWhite,
                          fontWeight: FontWeight.w600,
                        )),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: kWhite.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: const Text('● Online',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: kWhite,
                    )),
              ),
            ]),
          ),

          const SizedBox(height: 20),
          _label('Wat stuur je?'),
          const SizedBox(height: 10),

          // ── TYPE GRID ──
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.6,
            ),
            itemCount: _typen.length,
            itemBuilder: (_, i) {
              final sel = _type == i;
              return GestureDetector(
                onTap: () => setState(() => _type = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: sel ? kPeachPale : kWhite,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: sel ? kPeach : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: kBrown.withOpacity(0.07), blurRadius: 10)
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_typen[i]['icon']!,
                          style: const TextStyle(fontSize: 24)),
                      const SizedBox(height: 4),
                      Text(_typen[i]['naam']!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: kBrown,
                          )),
                      Text(_typen[i]['sub']!,
                          style: TextStyle(
                            fontSize: 10,
                            color: kTextMuted,
                          )),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 20),
          _label('Wanneer verschijnt het?'),
          const SizedBox(height: 10),

          // ── WANNEER BLOK ──
          Container(
            decoration: BoxDecoration(
              color: kWhite,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: kBrown.withOpacity(0.07), blurRadius: 10)
              ],
            ),
            child: Column(children: [
              _wanneerRij('⏰', 'Tijdstip', '09:00'),
              const Divider(height: 1, color: kPeachPale),
              _wanneerRij('🔁', 'Herhaling', 'Elke dag'),
            ]),
          ),

          const SizedBox(height: 20),

          // ── VERSTUUR KNOP ──
          GestureDetector(
            onTapDown: (_) => setState(() => _ingedrukt = true),
            onTapUp: (_) => setState(() => _ingedrukt = false),
            onTapCancel: () => setState(() => _ingedrukt = false),
            child: AnimatedScale(
              scale: _ingedrukt ? 0.97 : 1.0,
              duration: const Duration(milliseconds: 100),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [kPeach, kRose]),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: kPeach.withOpacity(0.45),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: Center(
                  child: Text(
                    '${_typen[_type]['icon']} Opnemen & versturen',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: kWhite,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }

  Widget _label(String t) => Text(
        t.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: kTextMuted,
          letterSpacing: 0.8,
        ),
      );

  Widget _wanneerRij(String icon, String label, String waarde) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kBrown,
                  ))),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: kPeachPale,
              borderRadius: BorderRadius.circular(50),
            ),
            child: Text(waarde,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: kPeach,
                )),
          ),
        ]),
      );
}

// ============================================================
// SCHERM 3 — SETUP WIZARD (5 stappen, eerste installatie)
// ============================================================

class SetupWizard extends StatefulWidget {
  const SetupWizard({super.key});
  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  int _stap = 0;
  final int _totaal = 5;
  final List<String> _familie = ['Sara (jij)', 'Tom'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── VOORTGANGSBALK ──
            Row(
              children: List.generate(
                _totaal,
                (i) => Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(right: 4),
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= _stap ? kPeach : kPeachLight,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Stap ${_stap + 1} van $_totaal',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: kPeach,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 16),

            // ── STAPINHOUD ──
            Expanded(
              child: SingleChildScrollView(child: _inhoud()),
            ),

            // ── VOLGENDE KNOP ──
            GestureDetector(
              onTap: () {
                if (_stap < _totaal - 1) {
                  setState(() => _stap++);
                } else {
                  Navigator.of(context).pushReplacementNamed('/familie');
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [kPeach, kRose]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: kPeach.withOpacity(0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: Center(
                  child: Text(
                    _stap == _totaal - 1 ? '✨ App openen!' : 'Volgende →',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: kWhite,
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _inhoud() {
    switch (_stap) {
      case 0: return _stap1();
      case 1: return _stap2();
      case 2: return _stap3();
      case 3: return _stap4();
      default: return _stap5();
    }
  }

  // STAP 1 — Naam & woonsituatie
  Widget _stap1() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Hoe heet degene voor\nwie je dit instelt?',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700,
              color: kBrown, height: 1.2)),
      const SizedBox(height: 24),
      _veld('👤', 'Voornaam', 'Jan', true),
      const SizedBox(height: 10),
      _veld('🎂', 'Geboortedatum', '12 maart 1942', true),
      const SizedBox(height: 10),
      _veld('🏠', 'Woonsituatie', 'Thuis / verpleeghuis...', false),
    ],
  );

  // STAP 2 — Foto & wektijd
  Widget _stap2() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Upload een foto van Jan',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700,
              color: kBrown, height: 1.2)),
      const SizedBox(height: 24),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: kPeachPale,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kPeachLight, width: 2),
        ),
        child: const Column(children: [
          Text('📷', style: TextStyle(fontSize: 40)),
          SizedBox(height: 8),
          Text('Foto uploaden',
              style: TextStyle(fontSize: 15,
                  fontWeight: FontWeight.w800, color: kBrown)),
          Text('Zijn favoriete foto — hij ziet dit elke dag',
              style: TextStyle(fontSize: 12, color: kTextMuted)),
        ]),
      ),
      const SizedBox(height: 16),
      _veld('🌅', 'Hoe laat staat Jan op?', '08:00', true),
      const SizedBox(height: 10),
      _veld('🎵', 'Favoriet liedje (optioneel)', 'Bijv. André Hazes...', false),
    ],
  );

  // STAP 3 — Familie uitnodigen
  Widget _stap3() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Wie mogen berichten\nsturen naar Jan?',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700,
              color: kBrown, height: 1.2)),
      const SizedBox(height: 24),
      Wrap(
        spacing: 8, runSpacing: 8,
        children: [
          ..._familie.map((n) => _chip(n, true)),
          _chip('+ Uitnodigen', false),
        ],
      ),
      const SizedBox(height: 20),
      _veld('📧', 'Uitnodigen via', 'WhatsApp of e-mail', true),
    ],
  );

  // STAP 4 — Apparaat instellen
  Widget _stap4() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Op welk apparaat komt\nde app voor Jan?',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700,
              color: kBrown, height: 1.2)),
      const SizedBox(height: 24),
      _veld('📱', 'Apparaat', 'Android tablet (aanbevolen)', true),
      const SizedBox(height: 10),
      _veld('🔊', 'Geluid', 'Altijd aan', true),
      const SizedBox(height: 10),
      _veld('🌙', 'Scherm dimmen na', '21:00', false),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kPeachPale,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(children: [
          Text('💡', style: TextStyle(fontSize: 18)),
          SizedBox(width: 10),
          Expanded(child: Text(
            'Tip: leg de tablet in de lader op tafel. Zo mist Jan nooit een moment.',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: kBrownLight, height: 1.4),
          )),
        ]),
      ),
    ],
  );

  // STAP 5 — Klaar!
  Widget _stap5() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Ons Moment is klaar! 🎉',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700,
              color: kBrown)),
      const SizedBox(height: 24),
      _veld('👤', 'Naam', 'Jan · geb. 12 maart 1942', true),
      const SizedBox(height: 10),
      _veld('👨‍👩‍👧', 'Familie uitgenodigd',
          '${_familie.join(', ')} — ${_familie.length} personen', true),
      const SizedBox(height: 10),
      _veld('📱', 'Apparaat', 'Android tablet · geluid altijd aan', true),
      const SizedBox(height: 10),
      _veld('⏰', 'Eerste moment', 'Morgenochtend 08:00', true),
      const SizedBox(height: 24),
      const Center(
        child: Text('💕 Jan gaat dit geweldig vinden',
            style: TextStyle(fontSize: 16, color: kPeach,
                fontWeight: FontWeight.w700)),
      ),
    ],
  );

  Widget _veld(String emoji, String label, String waarde, bool gevuld) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kPeachLight, width: 2),
          boxShadow: [
            BoxShadow(color: kBrown.withOpacity(0.06), blurRadius: 10)
          ],
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: kTextMuted,
                      letterSpacing: 0.5,
                    )),
                Text(waarde,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: gevuld ? kBrown : kPeachLight,
                    )),
              ],
            ),
          ),
          if (gevuld)
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                  color: kPeach, shape: BoxShape.circle),
              child: const Center(
                child: Text('✓',
                    style: TextStyle(
                      fontSize: 12,
                      color: kWhite,
                      fontWeight: FontWeight.w800,
                    )),
              ),
            ),
        ]),
      );

  Widget _chip(String naam, bool actief) => GestureDetector(
        onTap: () {
          if (!actief) setState(() => _familie.add('Nieuw familielid'));
        },
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: actief ? kPeachPale : kWhite,
            borderRadius: BorderRadius.circular(50),
            border: Border.all(
                color: actief ? kPeach : kPeachLight, width: 2),
          ),
          child: Text(naam,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: actief ? kPeach : kTextMuted,
              )),
        ),
      );
}
