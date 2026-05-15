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

const Map<String, String> kGeluidAssets = {
  'twinkel':  'assets/sounds/twinkel.mp3',
  'bel':      'assets/sounds/bel.mp3',
  'vogel':    'assets/sounds/vogel.mp3',
  'piano':    'assets/sounds/piano.mp3',
  'kerkklok': 'assets/sounds/kerkklok.mp3',
  'hart':     'assets/sounds/hart.mp3',
};

class TabletScherm extends StatefulWidget {
  const TabletScherm({super.key});
  @override
  State<TabletScherm> createState() => _TabletSchermState();
}

class _TabletSchermState extends State<TabletScherm> {
  final _audioPlayer = AudioPlayer();
  final _geluidPlayer = AudioPlayer();
  Timer? _autoSluitTimer;
  StreamSubscription? _momentenListener;
  StreamSubscription<DocumentSnapshot>? _gebruikerSub;

  Map<String, dynamic>? _huidigPopup;
  String? _huidigPopupId;
  String _herkenningsgeluid = 'twinkel';

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _startMomentenListener();
    _startGebruikerListener();

    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed
          && (_huidigPopup?['type'] == 'stem' || _huidigPopup?['type'] == 'lied')) {
        _sluitPopup();
      }
    });
  }

  @override
  void dispose() {
    _autoSluitTimer?.cancel();
    _momentenListener?.cancel();
    _gebruikerSub?.cancel();
    _audioPlayer.dispose();
    _geluidPlayer.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  void _startMomentenListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // Realtime listener — pakt nieuwe momenten direct op
    _momentenListener = FirebaseFirestore.instance.collection('momenten')
        .where('familieUid', isEqualTo: uid)
        .where('gezien', isEqualTo: false)
        .snapshots()
        .listen(_verwerkMomenten);
  }

  void _startGebruikerListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _gebruikerSub = FirebaseFirestore.instance
        .collection('gebruikers').doc(uid).snapshots()
        .listen((doc) {
      final data = doc.data() as Map<String, dynamic>?;
      final nieuwGeluid = data?['herkenningsgeluid'] as String? ?? 'twinkel';
      if (mounted && _herkenningsgeluid != nieuwGeluid) {
        setState(() => _herkenningsgeluid = nieuwGeluid);
      }
    });
  }

  void _verwerkMomenten(QuerySnapshot snap) {
    if (_huidigPopupId != null) return;
    final nu = DateTime.now();
    final voor24uur = nu.subtract(const Duration(hours: 24));
    for (final doc in snap.docs) {
      final d = doc.data() as Map<String, dynamic>;
      final geplandOp = (d['geplandOp'] as Timestamp?)?.toDate();
      if (geplandOp == null) continue;
      // Toon als gepland tijd al voorbij is en niet ouder dan 24 uur
      if (geplandOp.isBefore(nu) && geplandOp.isAfter(voor24uur)) {
        _toonPopup(doc.id, d);
        return;
      }
    }
  }

  Future<void> _toonPopup(String id, Map<String, dynamic> d) async {
    if (_huidigPopupId != null) return;
    // Claim slot direct (synchroon) zodat _verwerkMomenten geen tweede
    // popup start tijdens de async setup hieronder.
    _huidigPopupId = id;

    // Markeer gezien zodat na tablet-reboot niet alle ongeziene momenten
    // van afgelopen 24u opnieuw als popup verschijnen.
    try {
      await FirebaseFirestore.instance.collection('momenten')
          .doc(id).update({'gezien': true});
    } catch (_) {}

    // Speel herkenningsgeluid - wacht alleen 1200ms als afspelen daadwerkelijk lukte
    final geluidAsset = kGeluidAssets[_herkenningsgeluid];
    if (geluidAsset != null) {
      bool geluidGespeeld = false;
      try {
        await _geluidPlayer.setAsset(geluidAsset);
        await _geluidPlayer.play();
        geluidGespeeld = true;
      } catch (_) {
        // Geluid niet beschikbaar - geen probleem, popup gaat door
      }
      if (geluidGespeeld) {
        await Future.delayed(const Duration(milliseconds: 1200));
      }
    }

    if (!mounted) {
      _huidigPopupId = null;
      return;
    }
    setState(() {
      _huidigPopup = d;
    });

    if (d['type'] == 'stem' || d['type'] == 'lied') {
      final url = d['mediaUrl'] ?? '';
      if (url.isNotEmpty) {
        try {
          await _audioPlayer.setUrl(url);
          await _audioPlayer.play();
        } catch (_) {}
      }
      // Fallback: ook na 60 sec sluiten als audio niet eindigt
      _autoSluitTimer?.cancel();
      _autoSluitTimer = Timer(const Duration(seconds: 60), _sluitPopup);
    } else {
      // Foto/tekst: 60s zodat dementie-doelgroep tijd heeft om te verwerken
      _autoSluitTimer?.cancel();
      _autoSluitTimer = Timer(const Duration(seconds: 60), _sluitPopup);
    }
  }

  Future<void> _sluitPopup() async {
    await _audioPlayer.stop();
    _autoSluitTimer?.cancel();
    // gezien:true is al gezet aan het begin van _toonPopup
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

    // StreamBuilder voor gebruikersdata - live updates van profielfoto + naam
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('gebruikers')
          .doc(uid).snapshots(),
      builder: (ctx, userSnap) {
        final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
        final profielFotoUrl = userData['ontvangerFoto'] ?? '';
        final ontvangerNaam = userData['ontvangerNaam'] ?? '';

        return Scaffold(
          body: Stack(children: [
            // ━━━━ ACHTERGROND ━━━━
            Positioned.fill(child: profielFotoUrl.isNotEmpty
              ? Image.network(profielFotoUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (c, child, prog) {
                    if (prog == null) return child;
                    return Container(decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [kPeachPale, kCream])));
                  },
                  errorBuilder: (c, e, s) => Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [kPeachPale, kCream]))))
              : Container(decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [kPeachPale, kCream])))),

            // ━━━━ OVERLAY voor leesbare tekst ━━━━
            Positioned.fill(child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: profielFotoUrl.isNotEmpty ? [
                    Colors.black.withOpacity(0.55),
                    Colors.black.withOpacity(0.20),
                    Colors.black.withOpacity(0.65),
                  ] : [
                    Colors.transparent,
                    Colors.transparent,
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0]),
              ),
            )),

            // ━━━━ INHOUD ━━━━
            SafeArea(child: _homeInhoud(ontvangerNaam,
                hasBackground: profielFotoUrl.isNotEmpty)),

            // ━━━━ POPUP ━━━━
            if (_huidigPopup != null) GestureDetector(
              onTap: _sluitPopup, child: _popupOverlay()),
          ]),
        );
      },
    );
  }

  Widget _homeInhoud(String naam, {required bool hasBackground}) {
    final textColor = hasBackground ? kWhite : kBrown;
    final shadow = hasBackground ? [
      Shadow(color: Colors.black.withOpacity(0.6),
          blurRadius: 12, offset: const Offset(0, 3))
    ] : <Shadow>[];

    return Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Klok(textColor: textColor, shadow: shadow),
            const SizedBox(height: 36),

            // BEGROETING
            if (naam.isNotEmpty) Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                color: hasBackground
                    ? kWhite.withOpacity(0.25) : kPeachPale,
                borderRadius: BorderRadius.circular(50),
                border: hasBackground
                    ? Border.all(color: kWhite.withOpacity(0.5), width: 1.5)
                    : null),
              child: Text('Hallo $naam 💕',
                  style: TextStyle(fontSize: 26,
                      fontWeight: FontWeight.w800, color: textColor,
                      shadows: shadow)),
            ),
            const SizedBox(height: 28),

            // VOLGENDE MOMENT KAART
            _volgendeMomentKaart(),
            const SizedBox(height: 16),

            // EERDER VANDAAG
            _eerderVandaag(hasBackground: hasBackground),
          ]),
      ),
    ));
  }

  Widget _volgendeMomentKaart() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox();
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('dagelijkse_momenten')
          .where('familieUid', isEqualTo: uid)
          .where('actief', isEqualTo: true).snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox();
        final docs = snap.data!.docs.toList();
        final nu = DateTime.now();
        final huidigMin = nu.hour * 60 + nu.minute;
        Map<String, dynamic>? volgende;
        int volgendeMin = 24 * 60;
        bool isMorgen = false;
        for (final doc in docs) {
          final d = doc.data() as Map<String, dynamic>;
          final min = (d['uur'] as int) * 60 + (d['minuut'] as int);
          if (min > huidigMin && min < volgendeMin) {
            volgende = d;
            volgendeMin = min;
          }
        }
        if (volgende == null) {
          // Geen vandaag, pak vroegste van morgen
          isMorgen = true;
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
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: kWhite.withOpacity(0.94),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2),
                blurRadius: 20, offset: const Offset(0, 6))]),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(volgende['emoji'] ?? '⭐',
                style: const TextStyle(fontSize: 44)),
            const SizedBox(width: 16),
            Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
              Text(isMorgen ? 'Morgen' : 'Vandaag',
                  style: const TextStyle(fontSize: 11, color: kTextMuted,
                      fontWeight: FontWeight.w800, letterSpacing: 0.8)),
              const SizedBox(height: 2),
              Text(volgende['label'] ?? 'Moment',
                  style: const TextStyle(fontSize: 20,
                      fontWeight: FontWeight.w800, color: kBrown)),
            ]),
            const SizedBox(width: 16),
            Container(padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: kPeachPale,
                  borderRadius: BorderRadius.circular(12)),
              child: Text('${(volgende['uur'] ?? 0).toString().padLeft(2, '0')}:${(volgende['minuut'] ?? 0).toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 20,
                      fontWeight: FontWeight.w800, color: kBrown))),
          ]),
        );
      },
    );
  }

  Widget _eerderVandaag({required bool hasBackground}) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox();
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('momenten')
          .where('familieUid', isEqualTo: uid)
          .where('gezien', isEqualTo: true).snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const SizedBox();
        final vandaag = DateTime.now();
        final beginVandaag = DateTime(vandaag.year, vandaag.month, vandaag.day);
        final docs = snap.data!.docs.where((d) {
          final t = ((d.data() as Map)['geplandOp'] as Timestamp?)?.toDate();
          return t != null && t.isAfter(beginVandaag);
        }).take(20).toList();
        if (docs.isEmpty) return const SizedBox();
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: hasBackground
                  ? kWhite.withOpacity(0.2) : kPeachPale,
              borderRadius: BorderRadius.circular(20)),
            child: Text('Eerder vandaag',
              style: TextStyle(fontSize: 11,
                  color: hasBackground ? kWhite : kBrown,
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
                onTap: () => _toonPopup(docs[i].id, d),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: kWhite.withOpacity(0.9),
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
          child: SingleChildScrollView(child: Container(
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
          ))),
        )),
      ),
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
              loadingBuilder: (c, child, prog) {
                if (prog == null) return child;
                return Container(height: 280, color: kPeachPale,
                  child: const Center(child: CircularProgressIndicator(color: kPeach)));
              },
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

  String _formatPopupTijd(DateTime d) {
    return 'Verstuurd om ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

class _Klok extends StatefulWidget {
  final Color textColor;
  final List<Shadow> shadow;
  const _Klok({required this.textColor, required this.shadow});
  @override
  State<_Klok> createState() => _KlokState();
}

class _KlokState extends State<_Klok> {
  Timer? _timer;
  DateTime _nu = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1),
        (_) => setState(() => _nu = DateTime.now()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(_formatTijd(_nu),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 110,
              fontWeight: FontWeight.w900, color: widget.textColor, height: 1,
              shadows: widget.shadow)),
      const SizedBox(height: 4),
      Text(_formatDatum(_nu),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20,
              fontWeight: FontWeight.w700, color: widget.textColor,
              shadows: widget.shadow)),
    ]);
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
