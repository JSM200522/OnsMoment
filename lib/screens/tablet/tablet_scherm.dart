import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/moment.dart';
import '../../services/moment_service.dart';

// ─── KLEUREN ─────────────────────────────────────────────────
const Color kPeach      = Color(0xFFFF9B71);
const Color kPeachLight = Color(0xFFFFD4C2);
const Color kPeachPale  = Color(0xFFFFF0EA);
const Color kRose       = Color(0xFFFF7B9C);
const Color kBrown      = Color(0xFF5C3D2E);
const Color kTextMuted  = Color(0xFF9B7565);
const Color kWhite      = Color(0xFFFFFFFF);

// ════════════════════════════════════════════════════════════
// TABLET SCHERM — Jan's portaal
// ─ Kiosk modus: kan NIETS aanpassen
// ─ Automatisch afspelen op geplande tijd
// ─ Altijd aan, geen uitlogknop, geen instellingen
// ════════════════════════════════════════════════════════════
class TabletScherm extends StatefulWidget {
  const TabletScherm({super.key});
  @override
  State<TabletScherm> createState() => _TabletSchermState();
}

class _TabletSchermState extends State<TabletScherm>
    with TickerProviderStateMixin {
  final _momentService = MomentService();
  final _audioPlayer = AudioPlayer();
  late Timer _klokTimer;
  late Timer _checkTimer;

  int _tab = 0;
  Moment? _huidigMoment;     // het moment dat NU getoond wordt
  bool _speeltAf = false;
  bool _toonPopup = false;

  late AnimationController _popupCtrl;
  late Animation<double> _popupAnim;

  String get _tabletUid =>
      FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    // Scherm altijd aan in kiosk modus
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable(); // scherm nooit dimmen

    // Klok elke 30 seconden updaten
    _klokTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => setState(() {}));

    // Elke 60 seconden checken op nieuwe momenten
    _checkTimer = Timer.periodic(
        const Duration(seconds: 60), (_) => _checkNieuweMomenten());

    // Direct checken bij opstarten
    _checkNieuweMomenten();

    _popupCtrl = AnimationController(
        duration: const Duration(milliseconds: 800), vsync: this);
    _popupAnim = CurvedAnimation(
        parent: _popupCtrl, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _klokTimer.cancel();
    _checkTimer.cancel();
    _audioPlayer.dispose();
    _popupCtrl.dispose();
    super.dispose();
  }

  // ─── CHECK NIEUWE MOMENTEN ──────────────────────────────────
  Future<void> _checkNieuweMomenten() async {
    final momenten = await _momentService
        .momentenVoorTablet(_tabletUid)
        .first;
    if (momenten.isNotEmpty && mounted) {
      final moment = momenten.first;
      setState(() {
        _huidigMoment = moment;
        _toonPopup = true;
        _tab = 0; // ga naar Vandaag tab
      });
      _popupCtrl.forward(from: 0);
      // Automatisch afspelen!
      if (moment.type == 'audio' || moment.type == 'muziek') {
        await Future.delayed(const Duration(milliseconds: 500));
        _speelAudio(moment);
      }
    }
  }

  // ─── AUDIO AFSPELEN ─────────────────────────────────────────
  Future<void> _speelAudio(Moment moment) async {
    try {
      await _audioPlayer.setUrl(moment.mediaUrl);
      await _audioPlayer.play();
      setState(() => _speeltAf = true);
      _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          setState(() => _speeltAf = false);
          _markeerAfgespeeld(moment);
        }
      });
    } catch (e) {
      debugPrint('Audio fout: $e');
    }
  }

  Future<void> _markeerAfgespeeld(Moment moment) async {
    await _momentService.markeerAfgespeeld(moment.id);
    // Als herhaling aan: plan voor morgen zelfde tijdstip
    if (moment.herhalen) {
      final morgen = moment.geplandOp.add(const Duration(days: 1));
      final nieuw = Moment(
        id: '', vanUid: moment.vanUid, vanNaam: moment.vanNaam,
        naarUid: moment.naarUid, type: moment.type,
        mediaUrl: moment.mediaUrl, bericht: moment.bericht,
        geplandOp: morgen, herhalen: true,
      );
      await _momentService.momentPlannen(nieuw);
    }
  }

  // ─── TIJDWEERGAVE ───────────────────────────────────────────
  String get _tijd {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2,'0')}:${n.minute.toString().padLeft(2,'0')}';
  }

  String get _datum {
    final n = DateTime.now();
    const dagen = ['Maandag','Dinsdag','Woensdag','Donderdag',
                   'Vrijdag','Zaterdag','Zondag'];
    const maanden = ['januari','februari','maart','april','mei','juni',
                     'juli','augustus','september','oktober','november','december'];
    return '${dagen[n.weekday-1]} ${n.day} ${maanden[n.month-1]}';
  }

  @override
  Widget build(BuildContext context) {
    // Blokkeer ALLE system gestures — Jan kan niet teruggaan of swipen
    return PopScope(
      canPop: false, // terug-knop werkt niet
      child: Scaffold(
        backgroundColor: kPeachPale,
        body: SafeArea(
          child: Column(children: [
            // ── KLOK ──
            _klokWidget(),
            // ── INHOUD ──
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _tab == 0 ? _vandaagTab()
                     : _tab == 1 ? _fotosTab()
                     : _tab == 2 ? _agendaTab()
                     : _videosTab(),
              ),
            ),
            // ── NAVIGATIE ──
            _bottomNav(),
          ]),
        ),
      ),
    );
  }

  // ─── KLOK WIDGET ────────────────────────────────────────────
  Widget _klokWidget() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
    child: Column(children: [
      Text(_tijd, style: const TextStyle(fontSize: 80,
          fontWeight: FontWeight.w900, color: kBrown,
          height: 1.0, letterSpacing: -3)),
      const SizedBox(height: 4),
      Text(_datum, style: const TextStyle(fontSize: 20,
          fontWeight: FontWeight.w700, color: kTextMuted)),
    ]),
  );

  // ─── VANDAAG TAB ────────────────────────────────────────────
  Widget _vandaagTab() {
    if (!_toonPopup || _huidigMoment == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Center(child: Column(children: [
          const Text('💕', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text('Nog geen momenten vandaag',
              style: TextStyle(fontSize: 18, color: kTextMuted,
                  fontWeight: FontWeight.w700)),
        ])),
      );
    }
    return ScaleTransition(
      scale: _popupAnim,
      child: _momentKaart(_huidigMoment!),
    );
  }

  // ─── MOMENT KAART ───────────────────────────────────────────
  Widget _momentKaart(Moment moment) => Container(
    decoration: BoxDecoration(
      color: kWhite, borderRadius: BorderRadius.circular(24),
      boxShadow: [BoxShadow(color: kBrown.withOpacity(0.12),
          blurRadius: 32, offset: const Offset(0, 8))],
    ),
    clipBehavior: Clip.hardEdge,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Foto/media gedeelte
      Container(
        height: 200, width: double.infinity,
        decoration: BoxDecoration(gradient: LinearGradient(
            colors: [kPeachLight, kRose.withOpacity(0.5)],
            begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: Stack(children: [
          // Toon foto als het type foto is, anders emoji
          if (moment.type == 'foto' && moment.mediaUrl.isNotEmpty)
            Positioned.fill(child: Image.network(
                moment.mediaUrl, fit: BoxFit.cover))
          else
            Center(child: Text(moment.typeIcon,
                style: const TextStyle(fontSize: 72))),
          Positioned(top: 12, right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: kWhite.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(50)),
              child: Text('${moment.typeIcon} ${moment.typeLabel}',
                  style: TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w800, color: kRose)))),
        ]),
      ),
      // Tekst + audiobalk
      Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${moment.vanNaam} 💕', style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w800, color: kPeach)),
          if (moment.bericht != null) ...[
            const SizedBox(height: 8),
            Text(moment.bericht!, style: const TextStyle(fontSize: 18,
                fontWeight: FontWeight.w700, color: kBrown, height: 1.4)),
          ],
          if (moment.type == 'audio' || moment.type == 'muziek') ...[
            const SizedBox(height: 16),
            _audioBalk(moment),
          ],
        ]),
      ),
    ]),
  );

  // ─── AUDIO BALK ─────────────────────────────────────────────
  Widget _audioBalk(Moment moment) => GestureDetector(
    onTap: () {
      if (_speeltAf) {
        _audioPlayer.pause();
        setState(() => _speeltAf = false);
      } else {
        _speelAudio(moment);
      }
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: kPeachPale,
          borderRadius: BorderRadius.circular(50)),
      child: Row(children: [
        // Grote play knop
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [kPeach, kRose]),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: kPeach.withOpacity(0.45),
                blurRadius: 16, offset: const Offset(0, 4))]),
          child: Icon(_speeltAf ? Icons.pause : Icons.play_arrow,
              color: kWhite, size: 32)),
        const SizedBox(width: 12),
        // Geluidsgolven animatie
        Expanded(child: Row(
          children: List.generate(18, (i) => Expanded(
            child: AnimatedContainer(
              duration: Duration(milliseconds: 100 + i * 30),
              margin: const EdgeInsets.symmetric(horizontal: 1),
              height: _speeltAf ? (5 + (i % 5) * 8).toDouble()
                                : (i < 9 ? 16.0 : 8.0),
              decoration: BoxDecoration(
                color: i < 9 ? kPeach : kPeachLight,
                borderRadius: BorderRadius.circular(2)),
            ),
          )),
        )),
        const SizedBox(width: 8),
        Text(_speeltAf ? '▶ speelt af' : 'tik om te luisteren',
            style: TextStyle(fontSize: 11,
                fontWeight: FontWeight.w800, color: kTextMuted)),
      ]),
    ),
  );

  // ─── FOTO'S TAB ─────────────────────────────────────────────
  Widget _fotosTab() => StreamBuilder<List<Moment>>(
    stream: _momentService.momentenVoorTablet(_tabletUid),
    builder: (context, snap) {
      final fotos = (snap.data ?? [])
          .where((m) => m.type == 'foto').toList();
      if (fotos.isEmpty) return _leegTab('📷', "Nog geen foto's");
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12),
        itemCount: fotos.length,
        itemBuilder: (_, i) => ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.network(fotos[i].mediaUrl, fit: BoxFit.cover),
        ),
      );
    },
  );

  // ─── AGENDA TAB ─────────────────────────────────────────────
  Widget _agendaTab() => StreamBuilder<List<Moment>>(
    stream: _momentService.momentenVoorTablet(_tabletUid),
    builder: (context, snap) {
      final vandaag = DateTime.now();
      final komende = (snap.data ?? []).where((m) =>
          m.geplandOp.isAfter(vandaag) &&
          m.geplandOp.isBefore(vandaag.add(const Duration(days: 7)))
      ).toList()..sort((a,b) => a.geplandOp.compareTo(b.geplandOp));

      if (komende.isEmpty) return _leegTab('📅', 'Geen geplande momenten');
      return Column(children: komende.map((m) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: kWhite,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: kBrown.withOpacity(0.08),
                blurRadius: 12)]),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: kPeachPale,
                borderRadius: BorderRadius.circular(50)),
            child: Text(
              '${m.geplandOp.hour.toString().padLeft(2,'0')}:${m.geplandOp.minute.toString().padLeft(2,'0')}',
              style: const TextStyle(fontWeight: FontWeight.w800,
                  color: kPeach, fontSize: 16))),
          const SizedBox(width: 12),
          Text(m.typeIcon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(child: Text('${m.vanNaam} stuurt een ${m.typeLabel.toLowerCase()}',
              style: const TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w700, color: kBrown))),
        ]),
      )).toList());
    },
  );

  // ─── VIDEO'S TAB ────────────────────────────────────────────
  Widget _videosTab() => StreamBuilder<List<Moment>>(
    stream: _momentService.momentenVoorTablet(_tabletUid),
    builder: (context, snap) {
      final videos = (snap.data ?? [])
          .where((m) => m.type == 'video').toList();
      if (videos.isEmpty) return _leegTab('🎬', "Nog geen video's");
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: videos.length,
        itemBuilder: (_, i) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 160,
          decoration: BoxDecoration(
            color: kBrown.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16)),
          child: Center(child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              const Text('🎬', style: TextStyle(fontSize: 40)),
              Text(videos[i].vanNaam,
                  style: const TextStyle(fontWeight: FontWeight.w700,
                      color: kBrown)),
            ])),
        ),
      );
    },
  );

  Widget _leegTab(String emoji, String tekst) => Padding(
    padding: const EdgeInsets.only(top: 60),
    child: Center(child: Column(children: [
      Text(emoji, style: const TextStyle(fontSize: 64)),
      const SizedBox(height: 16),
      Text(tekst, style: TextStyle(fontSize: 18, color: kTextMuted,
          fontWeight: FontWeight.w700)),
    ])),
  );

  // ─── BOTTOM NAVIGATIE ───────────────────────────────────────
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
      decoration: BoxDecoration(color: kWhite,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: kBrown.withOpacity(0.08),
              blurRadius: 16)]),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: tabs.asMap().entries.map((e) {
          final sel = _tab == e.key;
          return GestureDetector(
            onTap: () => setState(() => _tab = e.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                  color: sel ? kPeachPale : Colors.transparent,
                  borderRadius: BorderRadius.circular(16)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(e.value['icon'] as IconData,
                    color: sel ? kPeach : kTextMuted, size: 24),
                const SizedBox(height: 4),
                Text(e.value['label'] as String,
                    style: TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: sel ? kPeach : kTextMuted)),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}
