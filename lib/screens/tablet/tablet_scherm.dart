import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

const Color kPeach      = Color(0xFFFF9B71);
const Color kPeachLight = Color(0xFFFFD4C2);
const Color kPeachPale  = Color(0xFFFFF0EA);
const Color kRose       = Color(0xFFFF7B9C);
const Color kCream      = Color(0xFFFFFAF7);
const Color kBrown      = Color(0xFF5C3D2E);
const Color kBrownLight = Color(0xFF8B6354);
const Color kTextMuted  = Color(0xFF9B7565);
const Color kWhite      = Color(0xFFFFFFFF);

class TabletScherm extends StatefulWidget {
  const TabletScherm({super.key});
  @override
  State<TabletScherm> createState() => _TabletSchermState();
}

class _TabletSchermState extends State<TabletScherm> {
  final _audioPlayer = AudioPlayer();
  final _geluidPlayer = AudioPlayer();
  Timer? _klokTimer;
  Timer? _checkTimer;
  Timer? _autoSluitTimer;
  DateTime _nu = DateTime.now();

  Map<String, dynamic>? _huidigPopup;
  String? _huidigPopupId;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _klokTimer = Timer.periodic(const Duration(seconds: 1),
        (_) => setState(() => _nu = DateTime.now()));
    _checkTimer = Timer.periodic(const Duration(seconds: 5),
        (_) => _checkMomenten());
    Future.delayed(const Duration(milliseconds: 500), _checkMomenten);

    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed
          && (_huidigPopup?['type'] == 'stem' || _huidigPopup?['type'] == 'lied')) {
        _sluitPopup();
      }
    });
  }

  @override
  void dispose() {
    _klokTimer?.cancel();
    _checkTimer?.cancel();
    _autoSluitTimer?.cancel();
    _audioPlayer.dispose();
    _geluidPlayer.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _checkMomenten() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _huidigPopup != null) return;
    final nu = DateTime.now();
    final voor30min = nu.subtract(const Duration(minutes: 30));
    try {
      final snap = await FirebaseFirestore.instance.collection('momenten')
          .where('naarUid', isEqualTo: uid)
          .where('gezien', isEqualTo: false).get();
      for (final doc in snap.docs) {
        final d = doc.data();
        final geplandOp = (d['geplandOp'] as Timestamp?)?.toDate();
        if (geplandOp == null) continue;
        if (geplandOp.isBefore(nu) && geplandOp.isAfter(voor30min)) {
          _toonPopup(doc.id, d);
          return;
        }
      }
    } catch (e) {
      debugPrint('Check fout: $e');
    }
  }

  Future<void> _toonPopup(String id, Map<String, dynamic> d, {String? geluidUrl}) async {
    if (_huidigPopupId == id) return;
    // Speel herkenningsgeluid eerst (indien geconfigureerd)
    if (geluidUrl != null && geluidUrl.isNotEmpty) {
      try {
        await _geluidPlayer.setUrl(geluidUrl);
        await _geluidPlayer.play();
        await Future.delayed(const Duration(milliseconds: 1500));
      } catch (_) {}
    }

    setState(() {
      _huidigPopup = d;
      _huidigPopupId = id;
    });

    if (d['type'] == 'stem' || d['type'] == 'lied') {
      final url = d['mediaUrl'] ?? '';
      if (url.isNotEmpty) {
        try {
          await _audioPlayer.setUrl(url);
          await _audioPlayer.play();
        } catch (_) {}
      }
    } else {
      _autoSluitTimer?.cancel();
      _autoSluitTimer = Timer(const Duration(seconds: 30), _sluitPopup);
    }
  }

  Future<void> _sluitPopup() async {
    await _audioPlayer.stop();
    _autoSluitTimer?.cancel();
    if (_huidigPopupId != null) {
      try {
        await FirebaseFirestore.instance.collection('momenten')
            .doc(_huidigPopupId).update({'gezien': true});
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _huidigPopup = null;
        _huidigPopupId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(backgroundColor: kCream);

    // Gebruik StreamBuilder zodat profielfoto LIVE update als familie hem wijzigt
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('gebruikers')
          .doc(uid).snapshots(),
      builder: (ctx, userSnap) {
        final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
        final profielFotoUrl = userData['profielFoto'] ?? '';
        final ontvangerNaam = userData['naam'] ?? '';

        return Scaffold(
          body: Stack(children: [
            // ════ ACHTERGROND: PROFIELFOTO VULT HELE SCHERM ════
            Positioned.fill(child: profielFotoUrl.isNotEmpty
              ? Image.network(profielFotoUrl, fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => Container(color: kCream))
              : Container(decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [kPeachPale, kCream]))),
            ),
            // ════ DONKERE OVERLAY voor leesbare tekst ════
            Positioned.fill(child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.55),
                    Colors.black.withOpacity(0.25),
                    Colors.black.withOpacity(0.55),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            )),
            // ════ INHOUD GECENTREERD ════
            SafeArea(child: _homeInhoud(ontvangerNaam)),
            // ════ POPUP OVERLAY ════
            if (_huidigPopup != null) GestureDetector(
              onTap: _sluitPopup, child: _popupOverlay()),
          ]),
        );
      },
    );
  }

  Widget _homeInhoud(String ontvangerNaam) {
    return Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ━━ KLOK ━━
            Text(_formatTijd(_nu),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 110,
                    fontWeight: FontWeight.w900, color: kWhite, height: 1,
                    shadows: [Shadow(color: Colors.black.withOpacity(0.5),
                        blurRadius: 16, offset: const Offset(0, 4))])),
            const SizedBox(height: 4),
            Text(_formatDatum(_nu),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20,
                    fontWeight: FontWeight.w700, color: kWhite,
                    shadows: [Shadow(color: Colors.black.withOpacity(0.5),
                        blurRadius: 12, offset: const Offset(0, 2))])),
            const SizedBox(height: 32),
            // ━━ BEGROETING ━━
            if (ontvangerNaam.isNotEmpty) Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: kWhite.withOpacity(0.25),
                borderRadius: BorderRadius.circular(50),
                border: Border.all(color: kWhite.withOpacity(0.5), width: 1.5)),
              child: Text('Hallo $ontvangerNaam 💕',
                  style: const TextStyle(fontSize: 24,
                      fontWeight: FontWeight.w800, color: kWhite,
                      shadows: [Shadow(color: Colors.black54,
                          blurRadius: 6, offset: Offset(0, 2))])),
            ),
            const SizedBox(height: 24),
            // ━━ VOLGENDE MOMENT KAART ━━
            _volgendeMomentKaart(),
            const SizedBox(height: 12),
            // ━━ EERDER VANDAAG ━━
            _eerderVandaag(),
          ]),
      ),
    ));
  }

  Widget _volgendeMomentKaart() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox();
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('dagelijkse_momenten')
          .where('naarUid', isEqualTo: uid)
          .where('actief', isEqualTo: true).snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox();
        final docs = snap.data!.docs.toList();
        final nu = DateTime.now();
        final huidigMin = nu.hour * 60 + nu.minute;
        Map<String, dynamic>? volgende;
        int volgendeMin = 24 * 60;
        for (final doc in docs) {
          final d = doc.data() as Map<String, dynamic>;
          final min = (d['uur'] as int) * 60 + (d['minuut'] as int);
          if (min > huidigMin && min < volgendeMin) {
            volgende = d;
            volgendeMin = min;
          }
        }
        if (volgende == null) {
          int vroegsteMin = 24 * 60;
          for (final doc in docs) {
            final d = doc.data() as Map<String, dynamic>;
            final min = (d['uur'] as int) * 60 + (d['minuut'] as int);
            if (min < vroegsteMin) {
              volgende = d;
              vroegsteMin = min;
            }
          }
        }
        if (volgende == null) return const SizedBox();
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kWhite.withOpacity(0.92),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2),
                blurRadius: 20, offset: const Offset(0, 6))]),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(volgende['emoji'] ?? '⭐',
                style: const TextStyle(fontSize: 40)),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
              const Text('Volgende moment',
                  style: TextStyle(fontSize: 11, color: kTextMuted,
                      fontWeight: FontWeight.w800, letterSpacing: 0.8)),
              const SizedBox(height: 2),
              Text(volgende['label'] ?? 'Moment',
                  style: const TextStyle(fontSize: 18,
                      fontWeight: FontWeight.w800, color: kBrown)),
            ]),
            const SizedBox(width: 14),
            Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: kPeachPale,
                  borderRadius: BorderRadius.circular(12)),
              child: Text('${(volgende['uur'] ?? 0).toString().padLeft(2, '0')}:${(volgende['minuut'] ?? 0).toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 18,
                      fontWeight: FontWeight.w800, color: kBrown))),
          ]),
        );
      },
    );
  }

  Widget _eerderVandaag() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox();
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('momenten')
          .where('naarUid', isEqualTo: uid)
          .where('gezien', isEqualTo: true).snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const SizedBox();
        final vandaag = DateTime.now();
        final beginVandaag = DateTime(vandaag.year, vandaag.month, vandaag.day);
        final docs = snap.data!.docs.where((d) {
          final t = ((d.data() as Map)['geplandOp'] as Timestamp?)?.toDate();
          return t != null && t.isAfter(beginVandaag);
        }).toList();
        if (docs.isEmpty) return const SizedBox();
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: kWhite.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20)),
            child: const Text('Eerder vandaag',
              style: TextStyle(fontSize: 11, color: kWhite,
                  fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          ),
          const SizedBox(height: 10),
          SizedBox(height: 64, child: ListView.builder(
            scrollDirection: Axis.horizontal,
            shrinkWrap: true,
            itemCount: docs.length,
            itemBuilder: (c, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              return GestureDetector(
                onTap: () => _toonPopup(docs[i].id, {...d, 'gezien': false}),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: kWhite.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15),
                        blurRadius: 8)]),
                  child: Center(child: Text(_emojiVoorType(d['type'] ?? ''),
                      style: const TextStyle(fontSize: 24))),
                ),
              );
            },
          )),
        ]);
      },
    );
  }

  Widget _popupOverlay() {
    final d = _huidigPopup!;
    final type = d['type'] ?? '';
    final vanNaam = d['vanNaam'] ?? 'Familie';
    final geplandOp = (d['geplandOp'] as Timestamp?)?.toDate();
    return Container(color: kBrown.withOpacity(0.94),
      child: SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Container(
            decoration: BoxDecoration(color: kCream,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3),
                    blurRadius: 40)]),
            child: Padding(padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_emojiVoorType(type), style: const TextStyle(fontSize: 48)),
                const SizedBox(height: 8),
                Text('$vanNaam stuurt je iets liefs 💕',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18,
                        fontWeight: FontWeight.w800, color: kBrown)),
                const SizedBox(height: 20),
                _popupInhoud(d),
                if (geplandOp != null) ...[
                  const SizedBox(height: 16),
                  Text(_formatPopupTijd(geplandOp),
                      style: const TextStyle(fontSize: 12,
                          color: kTextMuted, fontStyle: FontStyle.italic)),
                ],
                const SizedBox(height: 16),
                Text(type == 'stem' || type == 'lied'
                    ? 'Sluit automatisch wanneer klaar' : 'Tik om te sluiten',
                    style: const TextStyle(fontSize: 11, color: kTextMuted)),
              ])),
          ),
        )),
      )),
    );
  }

  Widget _popupInhoud(Map<String, dynamic> d) {
    final type = d['type'] ?? '';
    final bericht = d['bericht'] ?? '';
    final url = d['mediaUrl'] ?? '';
    switch (type) {
      case 'foto':
        return Column(mainAxisSize: MainAxisSize.min, children: [
          if (url.isNotEmpty) ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(url,
              height: 280, fit: BoxFit.cover,
              errorBuilder: (c, e, s) => Container(
                height: 280, color: kPeachPale,
                child: const Center(child: Icon(Icons.broken_image,
                    size: 80, color: kPeach))))),
          if (bericht.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(bericht, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, color: kBrown, height: 1.4)),
          ],
        ]);
      case 'stem':
      case 'lied':
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Container(padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(color: kPeachPale,
                shape: BoxShape.circle),
            child: const Icon(Icons.volume_up_rounded, color: kPeach, size: 72)),
          const SizedBox(height: 12),
          Text(type == 'stem' ? '🎙️ Stembericht' : '🎵 Liedje',
              style: const TextStyle(fontSize: 16,
                  fontWeight: FontWeight.w800, color: kBrown)),
          if (bericht.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(bericht, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16,
                    color: kBrownLight, height: 1.4)),
          ],
        ]);
      case 'tekst':
        return Text(bericht.isEmpty ? 'Een lief bericht voor jou' : bericht,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, color: kBrown,
                height: 1.5, fontWeight: FontWeight.w600));
      default:
        return const SizedBox();
    }
  }

  String _emojiVoorType(String type) {
    switch (type) {
      case 'foto': return '📷';
      case 'stem': return '🎙️';
      case 'lied': return '🎵';
      case 'tekst': return '✏️';
      default: return '💕';
    }
  }

  String _formatTijd(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _formatDatum(DateTime d) {
    const dagen = ['Maandag', 'Dinsdag', 'Woensdag', 'Donderdag',
                   'Vrijdag', 'Zaterdag', 'Zondag'];
    const maanden = ['januari', 'februari', 'maart', 'april', 'mei', 'juni',
                     'juli', 'augustus', 'september', 'oktober', 'november', 'december'];
    return '${dagen[d.weekday - 1]} ${d.day} ${maanden[d.month - 1]}';
  }

  String _formatPopupTijd(DateTime d) {
    return 'Verstuurd om ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
