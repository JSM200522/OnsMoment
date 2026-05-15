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
  Timer? _klokTimer;
  Timer? _checkTimer;
  DateTime _nu = DateTime.now();

  String _ontvangerNaam = '';
  String _profielFotoUrl = '';

  Map<String, dynamic>? _huidigPopup;
  String? _huidigPopupId;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _laadInfo();
    _klokTimer = Timer.periodic(const Duration(seconds: 1),
        (_) => setState(() => _nu = DateTime.now()));
    _checkTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkMomenten());
    _checkMomenten();
  }

  @override
  void dispose() {
    _klokTimer?.cancel();
    _checkTimer?.cancel();
    _audioPlayer.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _laadInfo() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('gebruikers').doc(uid).get();
    final d = doc.data() ?? {};
    setState(() {
      _ontvangerNaam = d['naam'] ?? '';
      _profielFotoUrl = d['profielFoto'] ?? '';
    });
  }

  Future<void> _checkMomenten() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // Kijk naar gewone momenten die nu of recent verschenen zijn
    final nu = DateTime.now();
    final voor5min = nu.subtract(const Duration(minutes: 5));
    final snap = await FirebaseFirestore.instance
        .collection('momenten')
        .where('naarUid', isEqualTo: uid)
        .where('gezien', isEqualTo: false)
        .get();
    for (final doc in snap.docs) {
      final d = doc.data();
      final geplandOp = (d['geplandOp'] as Timestamp?)?.toDate();
      if (geplandOp == null) continue;
      if (geplandOp.isBefore(nu) && geplandOp.isAfter(voor5min)) {
        _toonPopup(doc.id, d);
        return;
      }
    }
  }

  void _toonPopup(String id, Map<String, dynamic> d) {
    if (_huidigPopupId == id) return;
    setState(() {
      _huidigPopup = d;
      _huidigPopupId = id;
    });
    if (d['type'] == 'stem' || d['type'] == 'lied') {
      final url = d['mediaUrl'] ?? '';
      if (url.isNotEmpty) {
        _audioPlayer.setUrl(url).then((_) => _audioPlayer.play());
      }
    }
  }

  Future<void> _sluitPopup() async {
    await _audioPlayer.stop();
    if (_huidigPopupId != null) {
      await FirebaseFirestore.instance.collection('momenten')
          .doc(_huidigPopupId).update({'gezien': true});
    }
    setState(() {
      _huidigPopup = null;
      _huidigPopupId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      body: Stack(children: [
        _homeScherm(),
        if (_huidigPopup != null) _popupOverlay(),
      ]),
    );
  }

  Widget _homeScherm() {
    return SafeArea(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Spacer(),
        // KLOK GROOT
        Text(_formatTijd(_nu),
            style: const TextStyle(fontSize: 96,
                fontWeight: FontWeight.w900, color: kBrown, height: 1)),
        const SizedBox(height: 8),
        Text(_formatDatum(_nu),
            style: const TextStyle(fontSize: 18,
                fontWeight: FontWeight.w700, color: kBrownLight)),
        const SizedBox(height: 40),
        // PROFIELFOTO
        Container(width: 200, height: 200,
          decoration: BoxDecoration(
            color: kPeachPale, shape: BoxShape.circle,
            border: Border.all(color: kPeach, width: 4),
            image: _profielFotoUrl.isNotEmpty ? DecorationImage(
              image: NetworkImage(_profielFotoUrl), fit: BoxFit.cover) : null,
            boxShadow: [BoxShadow(color: kPeach.withOpacity(0.25),
                blurRadius: 30, spreadRadius: 4)]),
          child: _profielFotoUrl.isEmpty
            ? const Center(child: Text('💕', style: TextStyle(fontSize: 80))) : null,
        ),
        const SizedBox(height: 24),
        if (_ontvangerNaam.isNotEmpty) Text('Hallo $_ontvangerNaam',
            style: const TextStyle(fontSize: 28,
                fontWeight: FontWeight.w900, color: kBrown)),
        const SizedBox(height: 12),
        const Text('Familie stuurt zo iets leuks',
            style: TextStyle(fontSize: 14, color: kTextMuted)),
        const Spacer(),
      ]),
    ));
  }

  Widget _popupOverlay() {
    final d = _huidigPopup!;
    final type = d['type'] ?? '';
    return Positioned.fill(child: Container(
      color: kBrown.withOpacity(0.85),
      child: SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 500),
            decoration: BoxDecoration(color: kCream,
                borderRadius: BorderRadius.circular(28)),
            child: Padding(padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_emojiVoorType(type), style: const TextStyle(fontSize: 56)),
                const SizedBox(height: 12),
                const Text('Een lief moment voor jou 💕',
                    style: TextStyle(fontSize: 16,
                        fontWeight: FontWeight.w800, color: kBrown)),
                const SizedBox(height: 20),
                _popupInhoud(d),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: _sluitPopup,
                  child: Container(width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [kPeach, kRose]),
                      borderRadius: BorderRadius.circular(16)),
                    child: const Center(child: Text('Bedankt 💕',
                        style: TextStyle(fontSize: 18, color: kWhite,
                            fontWeight: FontWeight.w800)))),
                ),
              ])),
          ),
        ]),
      )),
    ));
  }

  Widget _popupInhoud(Map<String, dynamic> d) {
    final type = d['type'] ?? '';
    final bericht = d['bericht'] ?? '';
    final url = d['mediaUrl'] ?? '';
    switch (type) {
      case 'foto':
        return Column(children: [
          if (url.isNotEmpty) ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(url, height: 240, fit: BoxFit.cover)),
          if (bericht.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(bericht, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: kBrown, height: 1.4)),
          ],
        ]);
      case 'stem':
      case 'lied':
        return Column(children: [
          const Icon(Icons.volume_up_rounded, color: kPeach, size: 64),
          const SizedBox(height: 8),
          Text(type == 'stem' ? '🎙️ Spelt af...' : '🎵 Speelt af...',
              style: const TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w700, color: kBrown)),
          if (bericht.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(bericht, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14,
                    color: kTextMuted, height: 1.4)),
          ],
        ]);
      case 'tekst':
        return Text(bericht.isEmpty ? 'Een lief bericht voor jou' : bericht,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, color: kBrown, height: 1.5));
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
}
