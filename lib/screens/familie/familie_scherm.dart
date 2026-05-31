import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import '../../services/apparaat_service.dart';
import '../../services/device_modus_service.dart';
import '../../services/dagelijks_audio_service.dart';
import '../../theme/kleuren.dart';
import '../../data/geluiden.dart';
import '../../data/debug_flags.dart';
import '../../widgets/pulserend_hart.dart';
import '../../widgets/video_speler.dart';
import '../../data/labels.dart';
import 'kringleden_scherm.dart';

class FamilieScherm extends StatefulWidget {
  final bool alsOntvanger;
  const FamilieScherm({super.key, this.alsOntvanger = false});
  @override
  State<FamilieScherm> createState() => _FamilieSchermState();
}

class _FamilieSchermState extends State<FamilieScherm>
    with WidgetsBindingObserver {
  int _tab = 0;

  final _audioPlayer = AudioPlayer();
  final _geluidPlayer = AudioPlayer();
  StreamSubscription<QuerySnapshot>? _momentenListener;
  StreamSubscription<DocumentSnapshot>? _gebruikerSub;
  Map<String, dynamic>? _huidigPopup;
  String? _huidigPopupId;
  String _herkenningsgeluid = 'twinkel';
  String? _mijnApparaatId;
  String? _kringId;
  String? _accountType;  // 'familie'/'zorg', geladen voor T4-T5 (labels)
  Timer? _autoSluitTimer;

  // Dagelijkse + eenmalige momenten-flow — alleen actief in
  // ontvanger-meldings-modus.
  Timer? _checkTimer;
  StreamSubscription<QuerySnapshot>? _dagelijkseSub;
  List<QueryDocumentSnapshot>? _dagelijkseDocs;
  StreamSubscription<QuerySnapshot>? _eenmaligSub;
  List<QueryDocumentSnapshot>? _eenmaligDocs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Listeners pas starten ná apparaatId-load zodat _verwerkMomenten nooit
    // triggert met _mijnApparaatId == null (voorkomt off-by-one delay).
    DeviceModusService.krijgApparaatId().then((id) {
      if (!mounted) return;
      setState(() => _mijnApparaatId = id);
      _startGebruikerListener();
    });
    // V9 1.1f/1.1g/1.1h: alle kringId-gefilterde listeners pas starten ná
    // resolve, anders null-filter en hoort de ontvanger geen popups/
    // herkenningsgeluiden meer.
    DeviceModusService.huidigeKringIdMetFallback().then((id) {
      if (!mounted) return;
      setState(() => _kringId = id);
      if (id != null) {
        _startMomentenListener();
        if (widget.alsOntvanger) {
          _startDagelijksListener();
          _startEenmaligListener();
        }
      }
    });
    if (widget.alsOntvanger) {
      _checkTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _checkGeplandeMomenten();
        _herscanMomenten();
      });
    }
    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed
          && (_huidigPopup?['type'] == 'stem'
              || _huidigPopup?['type'] == 'lied'
              || _huidigPopup?['type'] == 'dagelijks')) {
        _sluitPopup();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSluitTimer?.cancel();
    _checkTimer?.cancel();
    _momentenListener?.cancel();
    _gebruikerSub?.cancel();
    _dagelijkseSub?.cancel();
    _eenmaligSub?.cancel();
    _audioPlayer.dispose();
    _geluidPlayer.dispose();
    super.dispose();
  }

  void _debugLog(String msg) {
    if (!DEBUG_AUDIO || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 11)),
      backgroundColor: Colors.black.withOpacity(0.75),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.only(top: 60, left: 16, right: 16, bottom: 0),
    ));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _herscanMomenten();
  }

  /// Her-scant openstaande (ongeziene) momenten via een verse query en voert
  /// ze door _verwerkMomenten. Vangt berichten op die binnenkwamen terwijl een
  /// popup open was (Bug A) of de app op de achtergrond stond (Bug B).
  Future<void> _herscanMomenten() async {
    if (_huidigPopupId != null) return;
    final kringId = _kringId;
    if (kringId == null) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('momenten')
          .where('kringId', isEqualTo: kringId)
          .where('gezien', isEqualTo: false)
          .get();
      if (mounted) _verwerkMomenten(snap);
    } catch (_) {}
  }

  void _startMomentenListener() {
    final kringId = _kringId;
    if (kringId == null) return;
    _momentenListener = FirebaseFirestore.instance.collection('momenten')
        .where('kringId', isEqualTo: kringId)
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
      final nieuwType = data?['accountType'] as String? ?? 'familie';
      if (mounted && _accountType != nieuwType) {
        setState(() => _accountType = nieuwType);
      }
    });
  }

  void _startDagelijksListener() {
    final kringId = _kringId;
    if (kringId == null) return;
    _dagelijkseSub = FirebaseFirestore.instance
        .collection('dagelijkse_momenten')
        .where('kringId', isEqualTo: kringId)
        .where('actief', isEqualTo: true)
        .snapshots()
        .listen((snap) => _dagelijkseDocs = snap.docs);
  }

  void _startEenmaligListener() {
    final kringId = _kringId;
    if (kringId == null) return;
    _eenmaligSub = FirebaseFirestore.instance
        .collection('gepland_momenten')
        .where('kringId', isEqualTo: kringId)
        .where('actief', isEqualTo: true)
        .snapshots()
        .listen((snap) => _eenmaligDocs = snap.docs);
  }

  Future<void> _checkGeplandeMomenten() async {
    if (_huidigPopupId != null) return;
    final nu = DateTime.now();
    final huidigMin = nu.hour * 60 + nu.minute;
    final vandaagKey = '${nu.year}-'
        '${nu.month.toString().padLeft(2, '0')}-'
        '${nu.day.toString().padLeft(2, '0')}';
    if (_dagelijkseDocs != null) {
      for (final doc in _dagelijkseDocs!) {
        final d = doc.data() as Map<String, dynamic>;
        final momentMin = (d['uur'] as int? ?? 0) * 60
                        + (d['minuut'] as int? ?? 0);
        if (momentMin > huidigMin) continue;
        if (huidigMin - momentMin > 1) continue;
        if (d['laatstGetoond'] == vandaagKey) continue;
        try {
          await doc.reference.update({'laatstGetoond': vandaagKey});
        } catch (_) {}
        _toonDagelijksPopup(doc.id, d);
        return;
      }
    }
    // Eenmalig geplande momenten: trigger als geplandOp <= nu < +24u en
    // nog niet getoond. Robuust: vangt gemiste momenten op (apparaat sliep).
    if (_eenmaligDocs != null) {
      for (final doc in _eenmaligDocs!) {
        final d = doc.data() as Map<String, dynamic>;
        if (d['getoond'] == true) continue;
        final geplandOp = (d['geplandOp'] as Timestamp?)?.toDate();
        if (geplandOp == null) continue;
        final verschil = nu.difference(geplandOp);
        if (verschil.isNegative) continue;       // nog in toekomst
        if (verschil.inHours >= 24) continue;     // te laat, sla over
        try {
          await doc.reference.update({'getoond': true});
        } catch (_) {}
        _toonEenmaligPopup(doc.id, d);
        return;
      }
    }
  }

  Future<void> _toonDagelijksPopup(
      String id, Map<String, dynamic> d) async {
    final aangepasteAudio = d['aangepasteAudioUrl'] as String? ?? '';
    final synthetic = <String, dynamic>{
      'type': 'dagelijks',
      'emoji': d['emoji'],
      'label': d['label'],
      'mediaUrl': aangepasteAudio,
      'geplandOp': Timestamp.now(),
      'heeftAangepasteAudio': aangepasteAudio.isNotEmpty,
    };
    await _toonPopup('dagelijks_$id', synthetic);
  }

  Future<void> _toonEenmaligPopup(
      String id, Map<String, dynamic> d) async {
    // Hergebruik 'dagelijks' popup-rendering + audio-flow: emoji + label,
    // standaard bel of eigen audio. Identiek aan dagelijks moment.
    final aangepasteAudio = d['aangepasteAudioUrl'] as String? ?? '';
    final synthetic = <String, dynamic>{
      'type': 'dagelijks',
      'emoji': d['emoji'],
      'label': d['label'],
      'mediaUrl': aangepasteAudio,
      'geplandOp': Timestamp.now(),
      'heeftAangepasteAudio': aangepasteAudio.isNotEmpty,
    };
    await _toonPopup('eenmalig_$id', synthetic);
  }

  void _verwerkMomenten(QuerySnapshot snap) {
    _debugLog('📨 Snap (meldings): ${snap.docs.length}');
    if (_huidigPopupId != null) return;
    if (_mijnApparaatId == null) return;
    final nu = DateTime.now();
    final voor24uur = nu.subtract(const Duration(hours: 24));
    for (final doc in snap.docs) {
      final d = doc.data() as Map<String, dynamic>;
      // Niet voor mij bedoeld. Nieuwe sends gebruiken aanApparaatIds (lijst);
      // oude docs het enkele aanApparaatId. Beide ondersteund.
      final aanLijst = (d['aanApparaatIds'] as List?)?.cast<String>();
      final aan = d['aanApparaatId'] as String?;
      if (aanLijst != null && aanLijst.isNotEmpty) {
        if (!aanLijst.contains(_mijnApparaatId)) continue;
      } else if (aan != null && aan != _mijnApparaatId) {
        continue;
      }
      // Eigen bericht skip
      final van = d['vanApparaatId'] as String?;
      if (van != null && van == _mijnApparaatId) continue;
      // In gewone familie-modus: alleen popups van ontvanger-apparaten
      // (familie→familie geeft geen popup)
      if (!widget.alsOntvanger) {
        final vanModus = d['vanApparaatModus'] as String?;
        if (vanModus != 'ontvanger') continue;
      }
      final geplandOp = (d['geplandOp'] as Timestamp?)?.toDate();
      if (geplandOp == null) continue;
      if (geplandOp.isBefore(nu) && geplandOp.isAfter(voor24uur)) {
        _toonPopup(doc.id, d);
        return;
      }
    }
  }

  Future<void> _toonPopup(String id, Map<String, dynamic> d) async {
    if (_huidigPopupId != null) return;
    _huidigPopupId = id;

    try {
      await FirebaseFirestore.instance.collection('momenten')
          .doc(id).update({'gezien': true});
    } catch (_) {}

    final skipBel = d['heeftAangepasteAudio'] == true;
    final geluidAsset = kGeluidAssets[_herkenningsgeluid];
    if (!skipBel && geluidAsset != null) {
      bool geluidGespeeld = false;
      try {
        _debugLog('🔔 Bel laden: $_herkenningsgeluid');
        await _geluidPlayer.setAsset(geluidAsset);
        await _geluidPlayer.play();
        geluidGespeeld = true;
      } catch (e) {
        _debugLog('❌ Bel-fout: $e');
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

    if (d['type'] == 'stem' || d['type'] == 'lied' || d['type'] == 'dagelijks') {
      final url = d['mediaUrl'] ?? '';
      if (url.isNotEmpty) {
        try {
          _debugLog('🔊 Audio laden');
          await _audioPlayer.setUrl(url);
          await _audioPlayer.play();
        } catch (e) {
          _debugLog('❌ Audio-fout: $e');
        }
      }
    }
    _autoSluitTimer?.cancel();
    final sluitNa = (d['type'] == 'hartje') ? 10 : 60;
    _autoSluitTimer = Timer(Duration(seconds: sluitNa), _sluitPopup);
  }

  Future<void> _sluitPopup() async {
    await _audioPlayer.stop();
    _autoSluitTimer?.cancel();
    if (mounted) {
      setState(() {
        _huidigPopup = null;
        _huidigPopupId = null;
      });
    }
    // Toon na een korte rustpauze een eventueel gemist bericht (Bug A).
    Future.delayed(const Duration(milliseconds: 500), _herscanMomenten);
  }

  Widget _popupOverlay() {
    final d = _huidigPopup!;
    final type = d['type'] ?? '';
    final vanRaw = (d['vanNaam'] as String?)?.trim() ?? '';
    final vanNaam = vanRaw.isNotEmpty ? vanRaw : 'Iemand uit je kring';
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
                if (type != 'hartje') ...[
                  Text(_emojiVoorType(type),
                      style: const TextStyle(fontSize: 48)),
                  const SizedBox(height: 8),
                ],
                Text(type == 'dagelijks'
                    ? 'Het is tijd voor:'
                    : type == 'hartje'
                        ? '$vanNaam denkt aan je 💕'
                        : '$vanNaam stuurt je een bericht',
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
                Text(type == 'stem' || type == 'lied' || type == 'dagelijks'
                    ? 'Sluit automatisch wanneer klaar'
                    : 'Tik om te sluiten',
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
                  child: const Center(
                      child: CircularProgressIndicator(color: kPeach)));
              },
              errorBuilder: (c, e, s) => Container(
                height: 280, color: kPeachPale,
                child: const Center(child: Icon(Icons.broken_image,
                    size: 80, color: kPeach))))),
          if (bericht.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(bericht, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18,
                    color: kBrown, height: 1.4)),
          ],
        ]);
      case 'stem':
      case 'lied':
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Container(padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(color: kPeachPale,
                shape: BoxShape.circle),
            child: const Icon(Icons.volume_up_rounded,
                color: kPeach, size: 72)),
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
      case 'dagelijks':
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Text(d['emoji'] as String? ?? '⭐',
              style: const TextStyle(fontSize: 96)),
          const SizedBox(height: 16),
          Text(d['label'] as String? ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28,
                  fontWeight: FontWeight.w800, color: kBrown)),
        ]);
      case 'hartje':
        return const Center(child: PulserendHart(grootte: 130));
      case 'video':
        return VideoSpeler(url: url);
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
      case 'dagelijks': return '⏰';
      case 'video': return '🎥';
      default: return '💕';
    }
  }

  String _formatPopupTijd(DateTime d) =>
      'Verstuurd om ${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (!widget.alsOntvanger) return _buildScaffold(achtergrondFotoUrl: '');
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return _buildScaffold(achtergrondFotoUrl: '');
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('gebruikers').doc(uid).snapshots(),
      builder: (ctx, snap) {
        final url = (snap.data?.data() as Map<String, dynamic>?)
            ?['ontvangerFoto'] as String? ?? '';
        return _buildScaffold(achtergrondFotoUrl: url);
      },
    );
  }

  Widget _buildScaffold({required String achtergrondFotoUrl}) {
    final toonAchtergrond = widget.alsOntvanger
        && achtergrondFotoUrl.isNotEmpty;
    return Scaffold(
      backgroundColor: toonAchtergrond ? Colors.transparent : kCream,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        title: const Text('Ons Moment 💕',
            style: TextStyle(color: kBrown,
                fontWeight: FontWeight.w900, fontSize: 20)),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: kTextMuted),
            tooltip: 'Hulp',
            onPressed: () => showModalBottomSheet(context: context,
                backgroundColor: Colors.transparent, isScrollControlled: true,
                builder: (ctx) => const _HulpDialog()),
          ),
        ],
      ),
      body: Stack(children: [
        if (toonAchtergrond) ...[
          Positioned.fill(child: Image.network(achtergrondFotoUrl,
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
                  colors: [kPeachPale, kCream]))))),
          Positioned.fill(child: Container(
              color: kCream.withOpacity(0.68))),
        ],
        _huidigeTab(),
        if (_huidigPopup != null) Positioned.fill(
          child: GestureDetector(
            onTap: _sluitPopup,
            child: _popupOverlay(),
          ),
        ),
      ]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: kWhite,
            boxShadow: [BoxShadow(color: kBrown.withOpacity(0.08),
                blurRadius: 16)]),
        child: SafeArea(child: Row(children: [
          _navItem(0, Icons.send_rounded, 'Sturen'),
          _navItem(1, Icons.calendar_today_rounded, 'Agenda'),
          if (!widget.alsOntvanger)
            _navItem(2, Icons.note_alt_rounded, 'Notities'),
          _navItem(widget.alsOntvanger ? 2 : 3,
              Icons.settings_rounded, 'Instellingen'),
        ])),
      ),
    );
  }

  Widget _huidigeTab() {
    if (widget.alsOntvanger) {
      switch (_tab) {
        case 0: return StuurTab(alsOntvanger: widget.alsOntvanger);
        case 1: return const AgendaTab();
        case 2: return InstellingenTab(alsOntvanger: widget.alsOntvanger);
        default: return const SizedBox();
      }
    }
    switch (_tab) {
      case 0: return StuurTab(alsOntvanger: widget.alsOntvanger);
      case 1: return const AgendaTab();
      case 2: return const NotitiesTab();
      case 3: return const InstellingenTab();
      default: return const SizedBox();
    }
  }

  Widget _navItem(int index, IconData icon, String label) {
    final sel = _tab == index;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _tab = index),
      child: Container(padding: const EdgeInsets.symmetric(vertical: 12),
        color: Colors.transparent,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: sel ? kPeach : kTextMuted, size: 22),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10,
              fontWeight: FontWeight.w800,
              color: sel ? kPeach : kTextMuted)),
        ])),
    ));
  }
}

// ════════════════════════════════════════════════════════════
// STUUR TAB
// ════════════════════════════════════════════════════════════
class StuurTab extends StatefulWidget {
  final bool alsOntvanger;
  const StuurTab({super.key, this.alsOntvanger = false});
  @override
  State<StuurTab> createState() => _StuurTabState();
}

class _StuurTabState extends State<StuurTab> {
  String _type = '';
  final _berichtCtrl = TextEditingController();
  TimeOfDay _tijd = TimeOfDay.now();
  DateTime _datum = DateTime.now();
  Uint8List? _mediaBytes;
  String _mediaNaam = '';
  bool _bezig = false;
  bool _testModus = false;  // Default UIT in productie (zie DEBUG_TESTMODUS)

  final _recorder = AudioRecorder();
  final _previewPlayer = AudioPlayer();
  bool _isOpnemen = false;
  bool _hebOpname = false;
  String? _opnamePad;
  int _opnameSeconden = 0;
  Timer? _opnameTimer;

  String? _gekozenPersoonsNaam;  // null = iedereen in kring
  String? _mijnApparaatId;
  String? _ontvangerNaam;
  Future<List<Map<String, dynamic>>>? _kringFuture;
  double? _uploadProgress;  // null = geen media-upload bezig
  bool _uploadIndeterminate = false;  // web-fallback als progress 0->100 springt

  @override
  void initState() {
    super.initState();
    DeviceModusService.krijgApparaatId().then((id) {
      if (mounted) setState(() => _mijnApparaatId = id);
    });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _kringFuture = ApparaatService.kringLeden(uid);
      FirebaseFirestore.instance.collection('gebruikers').doc(uid).get()
          .then((doc) {
        if (!mounted) return;
        setState(() {
          _ontvangerNaam =
              (doc.data()?['ontvangerNaam'] as String?) ?? 'ontvanger';
        });
      });
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
    _previewPlayer.dispose();
    _opnameTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Stuur een moment',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
                color: kBrown)),
        const SizedBox(height: 8),
        const Text('Kies één type media. Eén ding tegelijk werkt het beste.',
            style: TextStyle(fontSize: 13, color: kTextMuted, height: 1.4)),
        // TEST MODUS — alleen zichtbaar in debug (zie DEBUG_TESTMODUS)
        if (DEBUG_TESTMODUS) ...[
        const SizedBox(height: 16),
        Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _testModus ? kBlue : kPeachPale,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _testModus ? kBlue : kPeachLight,
                width: 1.5)),
          child: Row(children: [
            Icon(_testModus ? Icons.bolt_rounded : Icons.timer_rounded,
                color: _testModus ? kWhite : kTextMuted, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Text(_testModus ? 'TEST-MODUS AAN' : 'Test-modus uit',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900,
                      color: _testModus ? kWhite : kBrown)),
              Text(_testModus
                  ? 'Verschijnt direct bij ontvanger (binnen 5 sec)'
                  : 'Tik om aan te zetten — handig om snel te testen',
                  style: TextStyle(fontSize: 11,
                      color: _testModus ? kWhite.withOpacity(0.9) : kTextMuted)),
            ])),
            Switch(value: _testModus,
                onChanged: (v) => setState(() => _testModus = v),
                activeColor: kWhite, activeTrackColor: kBlue.withOpacity(0.5)),
          ])),
        ],

        const SizedBox(height: 16),
        if (widget.alsOntvanger) ...[
          _adresKeuze(),
          const SizedBox(height: 16),
        ],
        // 3x2 grid: Foto/Video, Stem/Lied, Tekst/Hartje.
        Row(children: [
          _typeKnop('📷', 'Foto', 'foto'),
          const SizedBox(width: 10),
          _typeKnop('🎥', 'Video', 'video'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _typeKnop('🎙️', 'Stem', 'stem'),
          const SizedBox(width: 10),
          _typeKnop('🎵', 'Lied', 'lied'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _typeKnop('✏️', 'Tekst', 'tekst'),
          const SizedBox(width: 10),
          _actieTegel(
              icoon: const PulserendHart(grootte: 28),
              label: 'Hartje',
              onTap: _stuurHartje),
        ]),

        if (_type.isNotEmpty) ...[
          const SizedBox(height: 20),
          _inhoudInvoer(),
          const SizedBox(height: 16),
          TextField(
            controller: _berichtCtrl, maxLines: 2,
            decoration: InputDecoration(
              labelText: _type == 'tekst' ? 'Bericht' : 'Optioneel bijschrift',
              hintText: _type == 'tekst' ? 'Wat wil je zeggen?'
                  : 'Bijv. "Een leuke foto van de kleinkinderen!"',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              filled: true, fillColor: kWhite),
          ),
          if (!_testModus) ...[
            const SizedBox(height: 16),
            const Text('WANNEER STUREN?',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                    color: kTextMuted, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _tijdDatumKnop('📅', _formatDatum(_datum), () async {
                final d = await showDatePicker(context: context,
                  initialDate: _datum, firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) setState(() => _datum = d);
              })),
              const SizedBox(width: 10),
              Expanded(child: _tijdDatumKnop('🕐', _formatTijd(_tijd), () async {
                final t = await showTimePicker(context: context, initialTime: _tijd,
                  builder: (c, child) => MediaQuery(
                    data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
                    child: child!));
                if (t != null) setState(() => _tijd = t);
              })),
            ]),
          ],
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _bezig ? null : _verstuur,
            child: Container(width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [kPeach, kRose]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: kPeach.withOpacity(0.35),
                    blurRadius: 20, offset: const Offset(0, 8))]),
              child: Center(child: !_bezig
                ? Text(
                    _testModus
                        ? (widget.alsOntvanger
                            ? (_gekozenPersoonsNaam == null
                                ? '⚡ Stuur NU naar de kring'
                                : '⚡ Stuur NU naar $_gekozenPersoonsNaam')
                            : '⚡ Stuur NU naar ${_ontvangerNaam ?? "ontvanger"}')
                        : 'Plan en stuur 💕',
                    style: const TextStyle(fontSize: 16,
                        fontWeight: FontWeight.w800, color: kWhite))
                : _uploadProgress == null
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(
                            color: kWhite, strokeWidth: 3))
                    : Column(mainAxisSize: MainAxisSize.min, children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                              value: _uploadIndeterminate
                                  ? null : _uploadProgress,
                              minHeight: 6,
                              backgroundColor: kWhite.withOpacity(0.3),
                              valueColor: const
                                  AlwaysStoppedAnimation<Color>(kWhite))),
                        const SizedBox(height: 6),
                        Text(_uploadIndeterminate
                            ? 'Uploaden…'
                            : 'Upload bezig: '
                                '${((_uploadProgress ?? 0) * 100).round()}%',
                            style: const TextStyle(fontSize: 13,
                                fontWeight: FontWeight.w800, color: kWhite)),
                      ])),
            ),
          ),
        ],
      ])),
    );
  }

  Widget _inhoudInvoer() {
    if (_type == 'tekst') {
      return Container(padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: kPeachPale,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kPeachLight, width: 2)),
        child: const Center(child: Text('✏️ Typ je bericht hieronder',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                color: kBrown))));
    }
    if (_type == 'stem') return _stemOpname();
    if (_type == 'video') return _videoPreviewKaart();
    return _bestandKiezen();
  }

  Widget _stemOpname() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: kPeachPale,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kPeachLight, width: 2)),
    child: Column(children: [
      GestureDetector(
        onTap: _isOpnemen ? _stopOpname : _startOpname,
        child: Container(width: 80, height: 80,
          decoration: BoxDecoration(
            color: _isOpnemen ? kRood : kRose,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(
              color: (_isOpnemen ? kRood : kRose).withOpacity(0.4),
              blurRadius: _isOpnemen ? 30 : 12,
              spreadRadius: _isOpnemen ? 6 : 0)]),
          child: Icon(_isOpnemen ? Icons.stop_rounded : Icons.mic_rounded,
              color: kWhite, size: 40),
        ),
      ),
      const SizedBox(height: 12),
      Text(_isOpnemen
          ? '🔴 Opname loopt: ${_opnameSeconden}s — tik om te stoppen'
          : _hebOpname
            ? '✓ Opname klaar (${_opnameSeconden}s)'
            : 'Tik op de microfoon om in te spreken',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
              color: _isOpnemen ? kRood : kBrown)),
      if (_hebOpname && !_isOpnemen) ...[
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _speelPreview,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(color: kPeach,
                borderRadius: BorderRadius.circular(20)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.play_arrow_rounded, color: kWhite, size: 20),
              SizedBox(width: 6),
              Text('Voorbeeld beluisteren',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                      color: kWhite)),
            ]),
          ),
        ),
      ],
    ]),
  );

  Future<void> _startOpname() async {
    try {
      if (await _recorder.hasPermission()) {
        await _recorder.start(const RecordConfig(encoder: AudioEncoder.opus),
            path: '');
        setState(() {
          _isOpnemen = true;
          _opnameSeconden = 0;
          _hebOpname = false;
          _mediaBytes = null;
        });
        _opnameTimer?.cancel();
        _opnameTimer = Timer.periodic(const Duration(seconds: 1),
            (_) => setState(() => _opnameSeconden++));
      } else {
        _toonFout('Geen toegang tot microfoon. Sta toe in browser-instellingen.');
      }
    } catch (e) {
      _toonFout('Opname starten mislukt: $e');
    }
  }

  Future<void> _stopOpname() async {
    try {
      final pad = await _recorder.stop();
      _opnameTimer?.cancel();
      if (pad != null) {
        try { await _previewPlayer.setUrl(pad); } catch (_) {}
        _opnamePad = pad;
        setState(() {
          _isOpnemen = false;
          _hebOpname = true;
        });
      }
    } catch (e) {
      _toonFout('Opname stoppen mislukt: $e');
    }
  }

  Future<void> _speelPreview() async {
    if (_opnamePad == null) return;
    try {
      await _previewPlayer.seek(Duration.zero);
      await _previewPlayer.play();
    } catch (e) {
      _toonFout('Afspelen mislukt: $e');
    }
  }

  Widget _bestandKiezen() => GestureDetector(
    onTap: _kiesMedia,
    child: Container(padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: kPeachPale,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kPeachLight, width: 2)),
      child: Center(child: Column(children: [
        if (_mediaBytes != null && _type == 'foto') ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(_mediaBytes!, height: 120, fit: BoxFit.cover))
        else Icon(_type == 'foto' ? Icons.add_photo_alternate_rounded
            : Icons.audiotrack_rounded, size: 40, color: kPeach),
        const SizedBox(height: 8),
        Text(_mediaNaam.isNotEmpty ? '✓ $_mediaNaam'
            : _type == 'foto' ? 'Tik om foto te kiezen'
            : 'Tik om MP3 lied te kiezen',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14,
                fontWeight: FontWeight.w700, color: kBrown)),
        if (_type == 'lied' && _mediaBytes != null) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _speelLiedPreview,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: kPeach,
                  borderRadius: BorderRadius.circular(20)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.play_arrow_rounded, color: kWhite, size: 20),
                SizedBox(width: 6),
                Text('Voorbeeld beluisteren',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                        color: kWhite)),
              ]),
            ),
          ),
        ],
      ])),
    ),
  );

  Future<void> _speelLiedPreview() async {
    if (_mediaBytes == null) return;
    try {
      await _previewPlayer.stop();
      await _previewPlayer.setAudioSource(
          _BytesAudioSource(_mediaBytes!, 'audio/mpeg'));
      await _previewPlayer.play();
    } catch (e) {
      _toonFout('Afspelen mislukt: $e');
    }
  }

  Future<void> _kiesMedia() async {
    try {
      if (_type == 'foto') {
        final picker = ImagePicker();
        final foto = await picker.pickImage(source: ImageSource.gallery,
            maxWidth: 1600, imageQuality: 85);
        if (foto != null) {
          final bytes = await foto.readAsBytes();
          setState(() {
            _mediaBytes = bytes;
            _mediaNaam = foto.name;
          });
        }
      } else {
        final result = await FilePicker.platform.pickFiles(
            type: FileType.audio, withData: true);
        if (result != null && result.files.first.bytes != null) {
          setState(() {
            _mediaBytes = result.files.first.bytes;
            _mediaNaam = result.files.first.name;
          });
        }
      }
    } catch (e) {
      _toonFout('Bestand kiezen niet mogelijk: $e');
    }
  }

  Future<void> _kiesVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['mp4'], withData: true);
      if (result == null) return;
      final f = result.files.first;
      Uint8List? bytes = f.bytes;
      if (bytes == null && f.xFile != null) {
        try {
          bytes = await f.xFile!.readAsBytes();
        } catch (e) {
          debugPrint('xFile.readAsBytes faalde: $e');
        }
      }
      if (bytes == null) {
        _toonFout('Kon video niet laden. Probeer een ander bestand.');
        return;
      }
      if (bytes.lengthInBytes > 50 * 1024 * 1024) {
        _toonFout('Deze video is te groot. '
            'Kies een video van maximaal 50MB.');
        return;
      }
      setState(() {
        _mediaBytes = bytes;
        _mediaNaam = f.name;
        _type = 'video';
      });
    } catch (e) {
      _toonFout('Video kiezen niet mogelijk: $e');
    }
  }

  Widget _videoPreviewKaart() => GestureDetector(
    onTap: _kiesVideo,
    child: Container(padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: kPeachPale,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kPeachLight, width: 2)),
      child: Center(child: Column(children: [
        const Icon(Icons.movie_rounded, size: 40, color: kPeach),
        const SizedBox(height: 8),
        Text(_mediaBytes != null
            ? '🎥 Video klaar om te versturen'
            : 'Tik om een video te kiezen',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14,
                fontWeight: FontWeight.w700, color: kBrown)),
        const SizedBox(height: 4),
        Text(_mediaBytes != null
            ? '$_mediaNaam — ${_formatBytes(_mediaBytes!.lengthInBytes)}'
            : 'Alleen .mp4, max 50MB',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: kTextMuted)),
      ])),
    ),
  );

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)}MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
    return '$bytes B';
  }

  Future<void> _stuurHartje() async {
    toonZwevendeHartjes(context);
    try {
      final kringId = await DeviceModusService.huidigeKringIdMetFallback();
      if (kringId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Kring niet beschikbaar — log opnieuw in'),
            backgroundColor: Colors.red));
        }
        return;
      }
      final leden = await (_kringFuture
          ?? Future.value(<Map<String, dynamic>>[]));
      final mijnNaam = (leden.firstWhere(
              (l) => l['apparaatId'] == _mijnApparaatId,
              orElse: () => <String, dynamic>{})['persoonsNaam'] as String? ?? '')
          .trim();
      final vanNaam = mijnNaam.isNotEmpty ? mijnNaam : 'Iemand uit je kring';

      List<String>? aanApparaatIds;
      if (_gekozenPersoonsNaam != null) {
        aanApparaatIds = leden
            .where((l) => (l['persoonsNaam'] as String? ?? '').toLowerCase()
                == _gekozenPersoonsNaam!.toLowerCase())
            .map((l) => l['apparaatId'] as String)
            .toList();
      }

      await FirebaseFirestore.instance.collection('momenten').add({
        'kringId': kringId,
        'vanNaam': vanNaam,
        'vanApparaatId': _mijnApparaatId,
        'vanApparaatModus': DeviceModusService.notifier.value ?? 'familie',
        'aanApparaatId': null,
        'aanApparaatIds': aanApparaatIds,
        'aanPersoonsNaam': _gekozenPersoonsNaam,
        'type': 'hartje',
        'emoji': '💕',
        'mediaUrl': '',
        'bericht': '',
        'geplandOp': Timestamp.now(),
        'verstuurdOp': FieldValue.serverTimestamp(),
        'gezien': false,
        'testModus': _testModus,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Je hartje is verstuurd 💕'),
          backgroundColor: kGreen));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Versturen mislukt — probeer opnieuw'),
          backgroundColor: kRood));
      }
    }
  }

  Future<void> _verstuur() async {
    if (_type == 'tekst' && _berichtCtrl.text.trim().isEmpty) {
      _toonFout('Typ eerst een bericht'); return;
    }
    if (_type == 'stem' && !_hebOpname) {
      _toonFout('Neem eerst een stembericht op'); return;
    }
    if ((_type == 'foto' || _type == 'lied' || _type == 'video')
        && _mediaBytes == null) {
      _toonFout('Kies eerst een bestand'); return;
    }
    setState(() => _bezig = true);
    try {
      final kringId = await DeviceModusService.huidigeKringIdMetFallback();
      if (kringId == null) {
        if (mounted) {
          setState(() => _bezig = false);
          _toonFout('Kring niet beschikbaar — log opnieuw in');
        }
        return;
      }

      // Afzender = de echte persoon op DIT apparaat (persoonsNaam uit de
      // kringlijst), niet de account-brede familieNaam.
      final leden = await (_kringFuture
          ?? Future.value(<Map<String, dynamic>>[]));
      final mijnNaam = (leden.firstWhere(
              (l) => l['apparaatId'] == _mijnApparaatId,
              orElse: () => <String, dynamic>{})['persoonsNaam'] as String? ?? '')
          .trim();
      final vanNaam = mijnNaam.isNotEmpty ? mijnNaam : 'Iemand uit je kring';

      String mediaUrl = '';
      if (_type == 'stem' && _opnamePad != null) {
        final response = await http.get(Uri.parse(_opnamePad!));
        if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
          throw Exception('Opname kon niet worden gelezen');
        }
        final ref = FirebaseStorage.instance.ref()
            .child('momenten')
            .child('${DateTime.now().millisecondsSinceEpoch}.webm');
        await ref.putData(response.bodyBytes,
            SettableMetadata(contentType: 'audio/webm'));
        mediaUrl = await ref.getDownloadURL();
      } else if (_type == 'video' && _mediaBytes != null) {
        final ref = FirebaseStorage.instance.ref()
            .child('momenten')
            .child('${DateTime.now().millisecondsSinceEpoch}.mp4');
        mediaUrl = await _uploadMetProgress(ref, _mediaBytes!, 'video/mp4');
      } else if (_mediaBytes != null) {
        final ext = _type == 'foto' ? 'jpg' : 'mp3';
        final ref = FirebaseStorage.instance.ref()
            .child('momenten')
            .child('${DateTime.now().millisecondsSinceEpoch}.$ext');
        await ref.putData(_mediaBytes!, SettableMetadata(
            contentType: _type == 'foto' ? 'image/jpeg' : 'audio/mpeg'));
        mediaUrl = await ref.getDownloadURL();
      }

      final geplandTijd = _testModus ? DateTime.now() : DateTime(
          _datum.year, _datum.month, _datum.day, _tijd.hour, _tijd.minute);

      // Persoon → alle apparaatIds van die persoon (case-insensitief).
      // null = iedereen in de kring.
      List<String>? aanApparaatIds;
      if (_gekozenPersoonsNaam != null) {
        aanApparaatIds = leden
            .where((l) => (l['persoonsNaam'] as String? ?? '').toLowerCase()
                == _gekozenPersoonsNaam!.toLowerCase())
            .map((l) => l['apparaatId'] as String)
            .toList();
      }

      await FirebaseFirestore.instance.collection('momenten').add({
        'kringId': kringId,
        'vanNaam': vanNaam,
        'vanApparaatId': _mijnApparaatId,
        'vanApparaatModus':
            DeviceModusService.notifier.value ?? 'familie',
        'aanApparaatId': null,                  // legacy-veld; nieuwe sends via lijst
        'aanApparaatIds': aanApparaatIds,        // null = iedereen in kring
        'aanPersoonsNaam': _gekozenPersoonsNaam, // voor historie/weergave
        'type': _type,
        'mediaUrl': mediaUrl,
        'bericht': _berichtCtrl.text.trim(),
        'geplandOp': Timestamp.fromDate(geplandTijd),
        'verstuurdOp': FieldValue.serverTimestamp(),
        'gezien': false,
        'testModus': _testModus,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_testModus
              ? '⚡ Direct verstuurd! Verschijnt nu bij ontvanger'
              : 'Moment gepland voor ${_formatDatum(_datum)} ${_formatTijd(_tijd)} 💕'),
          backgroundColor: kGreen));
        setState(() {
          _type = '';
          _berichtCtrl.clear();
          _mediaBytes = null;
          _mediaNaam = '';
          _hebOpname = false;
          _opnamePad = null;
          _opnameSeconden = 0;
        });
      }
    } catch (e) {
      _toonFout('Versturen mislukt: $e');
    } finally {
      if (mounted) {
        setState(() {
          _bezig = false;
          _uploadProgress = null;
          _uploadIndeterminate = false;
        });
      }
    }
  }

  /// Upload met live voortgang. Op web kan progress in één stap van 0 naar 100
  /// springen; dan tonen we een indeterminate balk (altijd zichtbare beweging).
  Future<String> _uploadMetProgress(
      Reference ref, Uint8List bytes, String contentType) async {
    setState(() {
      _uploadProgress = 0;
      _uploadIndeterminate = true;
    });
    final taak = ref.putData(bytes, SettableMetadata(contentType: contentType));
    final sub = taak.snapshotEvents.listen((snap) {
      if (snap.totalBytes > 0) {
        final p = snap.bytesTransferred / snap.totalBytes;
        if (mounted && p > 0 && p < 1) {
          setState(() {
            _uploadProgress = p;
            _uploadIndeterminate = false;
          });
        }
      }
    });
    try {
      await taak;
    } finally {
      await sub.cancel();
    }
    return ref.getDownloadURL();
  }

  void _toonFout(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.red));

  Widget _adresKeuze() => FutureBuilder<List<Map<String, dynamic>>>(
    future: _kringFuture,
    builder: (ctx, snap) {
      if (_mijnApparaatId == null || !snap.hasData) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(color: kWhite,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kPeachLight, width: 2)),
          child: Row(children: const [
            Text('👥', style: TextStyle(fontSize: 20)),
            SizedBox(width: 10),
            SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(
                    color: kPeach, strokeWidth: 2.5)),
            SizedBox(width: 10),
            Text('Even laden...',
                style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w700, color: kTextMuted)),
          ]),
        );
      }
      // In alsOntvanger-modus: sluit álle ontvanger-apparaten uit, niet
      // alleen het eigen apparaat (meerdere ontvanger-sessies kunnen
      // dezelfde modus delen met andere apparaatIds).
      final leden = snap.data!.where((l) {
        if (l['apparaatId'] == _mijnApparaatId) return false;
        if (widget.alsOntvanger && l['modus'] == 'ontvanger') return false;
        return true;
      }).toList();
      // Groepeer op persoonsNaam (case-insensitief) — meerdere apparaten van
      // dezelfde persoon geven één entry.
      final gezien = <String>{};
      final personen = <Map<String, dynamic>>[];
      for (final l in leden) {
        final naam = (l['persoonsNaam'] as String? ?? '').trim();
        if (naam.isEmpty) continue;
        final key = naam.toLowerCase();
        if (gezien.contains(key)) continue;
        gezien.add(key);
        personen.add(l);
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(color: kWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kPeachLight, width: 2)),
        child: Row(children: [
          const Text('👥', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(child: DropdownButton<String?>(
            value: _gekozenPersoonsNaam,
            isExpanded: true,
            underline: const SizedBox(),
            hint: const Text('Naar wie?',
                style: TextStyle(color: kTextMuted)),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Iedereen in de kring',
                    style: TextStyle(color: kBrown,
                        fontWeight: FontWeight.w700)),
              ),
              ...personen.map((l) {
                final naam = l['persoonsNaam'] as String;
                final isOntv = l['modus'] == 'ontvanger';
                final label = isOntv ? '$naam (ontvanger)' : naam;
                return DropdownMenuItem<String?>(
                  value: naam,
                  child: Text(label, style: const TextStyle(
                      color: kBrown, fontWeight: FontWeight.w700)),
                );
              }),
            ],
            onChanged: (val) => setState(() {
              _gekozenPersoonsNaam = val;
            }),
          )),
        ]),
      );
    },
  );

  Widget _typeKnop(String emoji, String label, String waarde) =>
    Expanded(child: GestureDetector(
      onTap: () => setState(() {
        _type = _type == waarde ? '' : waarde;
        _mediaBytes = null;
        _mediaNaam = '';
        _hebOpname = false;
        _opnamePad = null;
      }),
      child: Container(padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: _type == waarde ? kPeach : kWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kPeachLight, width: 2)),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 13,
              fontWeight: FontWeight.w800,
              color: _type == waarde ? kWhite : kBrown)),
        ]),
      ),
    ));

  /// Actie-tegel met dezelfde styling als _typeKnop, maar met een vrije onTap
  /// en een widget als icoon (voor de Video-placeholder en het pulserende
  /// Hartje). Nooit "geselecteerd" — dus altijd witte achtergrond.
  Widget _actieTegel({required Widget icoon, required String label,
      required VoidCallback onTap}) =>
    Expanded(child: GestureDetector(
      onTap: onTap,
      child: Container(padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: kWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kPeachLight, width: 2)),
        child: Column(children: [
          icoon,
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 13,
              fontWeight: FontWeight.w800, color: kBrown)),
        ]),
      ),
    ));

  Widget _tijdDatumKnop(String emoji, String tekst, VoidCallback onTap) =>
    GestureDetector(onTap: onTap, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: kWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kPeachLight, width: 2)),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Text(tekst, style: const TextStyle(fontSize: 13,
            fontWeight: FontWeight.w800, color: kBrown)),
      ]),
    ));

  String _formatDatum(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}';
  String _formatTijd(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

// ════════════════════════════════════════════════════════════
// AGENDA TAB
// ════════════════════════════════════════════════════════════
class AgendaTab extends StatelessWidget {
  const AgendaTab({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Center(child: Text('Niet ingelogd'));
    return Padding(padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Agenda',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
                color: kBrown)),
        const SizedBox(height: 4),
        const Text('Alle vaste en geplande momenten',
            style: TextStyle(fontSize: 13, color: kTextMuted)),
        const SizedBox(height: 16),
        Expanded(child: ListView(children: [
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kPeachPale,
              borderRadius: BorderRadius.circular(10)),
            child: const Text(
              '💡 Tijd aanpassen kan via Instellingen > Momenten beheren',
              style: TextStyle(fontSize: 12, color: kTextMuted)),
          ),
          const _SectieTitel('🔁 ELKE DAG'),
          FutureBuilder<String?>(
            future: DeviceModusService.huidigeKringIdMetFallback(),
            builder: (ctx, kringSnap) {
              final kringId = kringSnap.data;
              if (kringId == null) return const SizedBox();
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('dagelijkse_momenten')
                    .where('kringId', isEqualTo: kringId)
                    .where('actief', isEqualTo: true).snapshots(),
                builder: (ctx, snap) {
                  if (!snap.hasData) return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                        child: CircularProgressIndicator(color: kPeach)));
                  final docs = snap.data!.docs.toList();
                  if (docs.isEmpty) {
                    return _leeg('Nog geen dagelijkse momenten');
                  }
                  docs.sort((a, b) {
                    final ua = (a.data() as Map)['uur'] ?? 0;
                    final ub = (b.data() as Map)['uur'] ?? 0;
                    if (ua != ub) return (ua as int).compareTo(ub as int);
                    return ((a.data() as Map)['minuut'] as int)
                        .compareTo((b.data() as Map)['minuut'] as int);
                  });
                  return Column(children: docs.map((d) =>
                    _DagelijksItem(doc: d)).toList());
                },
              );
            },
          ),
          const SizedBox(height: 20),
          const _SectieTitel('📅 GEPLAND'),
          FutureBuilder<String?>(
            future: DeviceModusService.huidigeKringIdMetFallback(),
            builder: (ctx, kringSnap) {
              final kringId = kringSnap.data;
              if (kringId == null) return const SizedBox();
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('gepland_momenten')
                    .where('kringId', isEqualTo: kringId)
                    .where('actief', isEqualTo: true).snapshots(),
                builder: (ctx, eenmaligSnap) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('momenten')
                        .where('kringId', isEqualTo: kringId)
                        .where('gezien', isEqualTo: false).snapshots(),
                    builder: (ctx, momentenSnap) {
                      if (!eenmaligSnap.hasData || !momentenSnap.hasData) {
                        return const SizedBox();
                      }
                      final nu = DateTime.now();
                      final items = <MapEntry<DateTime, Widget>>[];
                      for (final doc in eenmaligSnap.data!.docs) {
                        final g = ((doc.data() as Map)['geplandOp']
                            as Timestamp?)?.toDate();
                        if (g == null || !g.isAfter(nu)) continue;
                        items.add(MapEntry(g, _EenmaligItem(doc: doc)));
                      }
                      for (final doc in momentenSnap.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        if (data['testModus'] == true) continue;
                        final g = (data['geplandOp'] as Timestamp?)?.toDate();
                        if (g == null || !g.isAfter(nu)) continue;
                        items.add(MapEntry(g, _GeplandItem(doc: doc)));
                      }
                      if (items.isEmpty) {
                        return _leeg('Geen geplande momenten');
                      }
                      items.sort((a, b) => a.key.compareTo(b.key));
                      return Column(
                          children: items.map((e) => e.value).toList());
                    },
                  );
                },
              );
            },
          ),
          const SizedBox(height: 20),
          const _SectieTitel('✓ VERSTUURD'),
          FutureBuilder<String?>(
            future: DeviceModusService.huidigeKringIdMetFallback(),
            builder: (ctx, kringSnap) {
              final kringId = kringSnap.data;
              if (kringId == null) return const SizedBox();
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('momenten')
                    .where('kringId', isEqualTo: kringId)
                    .where('gezien', isEqualTo: true).snapshots(),
                builder: (ctx, snap) {
                  if (!snap.hasData) return const SizedBox();
                  final docs = snap.data!.docs.toList();
                  if (docs.isEmpty) {
                    return _leeg('Nog geen verstuurde momenten');
                  }
                  return Column(children: docs.take(5).map((d) =>
                    _GeplandItem(doc: d, isHistorie: true)).toList());
                },
              );
            },
          ),
        ])),
      ]),
    );
  }

  Widget _leeg(String tekst) => Padding(padding: const EdgeInsets.all(20),
    child: Center(child: Text(tekst,
        style: const TextStyle(fontSize: 12, color: kTextMuted))));
}

class _SectieTitel extends StatelessWidget {
  final String tekst;
  const _SectieTitel(this.tekst);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(tekst, style: const TextStyle(fontSize: 11,
        fontWeight: FontWeight.w800, color: kTextMuted, letterSpacing: 0.8)));
}

class _DagelijksItem extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  const _DagelijksItem({required this.doc});
  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final audioType = d['aangepasteAudioType'] as String? ?? '';
    final audioLabel = audioType == 'stem' ? '🎤 Eigen stem'
        : audioType == 'mp3' ? '🎵 Eigen MP3'
        : '🔔 Standaard bel';
    return Container(margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kPeachLight, width: 1.5)),
      child: Row(children: [
        Text(d['emoji'] ?? '⭐', style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text(d['label'] ?? 'Moment', style: const TextStyle(fontSize: 14,
              fontWeight: FontWeight.w800, color: kBrown)),
          Text('Elke dag • $audioLabel',
              style: const TextStyle(fontSize: 11, color: kTextMuted)),
        ])),
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: kPeachPale,
              borderRadius: BorderRadius.circular(8)),
          child: Text('${(d['uur'] ?? 0).toString().padLeft(2, '0')}:${(d['minuut'] ?? 0).toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w800, color: kBrown))),
      ]),
    );
  }
}

class _EenmaligItem extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  const _EenmaligItem({required this.doc});

  String _formatDatumTijd(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-'
      '${d.month.toString().padLeft(2, '0')} • '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final geplandOp = (d['geplandOp'] as Timestamp?)?.toDate();
    final audioType = d['aangepasteAudioType'] as String? ?? '';
    final audioLabel = audioType == 'stem' ? '🎤 Eigen stem'
        : audioType == 'mp3' ? '🎵 Eigen MP3'
        : '🔔 Standaard bel';
    return Container(margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kPeachLight, width: 1.5)),
      child: Row(children: [
        Text(d['emoji'] ?? '⭐', style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text(d['label'] ?? 'Moment', style: const TextStyle(fontSize: 14,
              fontWeight: FontWeight.w800, color: kBrown)),
          Text(geplandOp != null
              ? '${_formatDatumTijd(geplandOp)} • $audioLabel'
              : audioLabel,
              style: const TextStyle(fontSize: 11, color: kTextMuted)),
        ])),
        IconButton(icon: const Icon(Icons.delete_outline_rounded,
            color: Colors.red),
          onPressed: () async {
            final kringId =
                await DeviceModusService.huidigeKringIdMetFallback();
            if (kringId != null) {
              await DagelijksAudioService.reset(
                  kringId: kringId, momentId: doc.id,
                  collectie: 'gepland_momenten');
            }
            await doc.reference.update({'actief': false});
          }),
      ]),
    );
  }
}

class _AudioInstelDialog extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  const _AudioInstelDialog({required this.doc});
  @override
  State<_AudioInstelDialog> createState() => _AudioInstelDialogState();
}

class _AudioInstelDialogState extends State<_AudioInstelDialog> {
  final _recorder = AudioRecorder();
  final _previewPlayer = AudioPlayer();
  Timer? _opnameTimer;

  bool _isOpnemen = false;
  int _opnameSeconden = 0;
  String? _opnamePad;
  Uint8List? _opnameBytes;

  Uint8List? _mp3Bytes;
  String _mp3Naam = '';

  bool _bezig = false;
  String? _huidigeUrl;
  String? _huidigType;
  Uint8List? _huidigeBytes;

  @override
  void initState() {
    super.initState();
    final d = widget.doc.data() as Map<String, dynamic>;
    _huidigeUrl = d['aangepasteAudioUrl'] as String?;
    _huidigType = d['aangepasteAudioType'] as String?;
    _preloadHuidige();
  }

  Future<void> _preloadHuidige() async {
    if ((_huidigeUrl ?? '').isEmpty) return;
    try {
      final resp = await http.get(Uri.parse(_huidigeUrl!));
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty && mounted) {
        _huidigeBytes = resp.bodyBytes;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _opnameTimer?.cancel();
    _recorder.dispose();
    _previewPlayer.dispose();
    super.dispose();
  }

  Future<void> _startOpname() async {
    try {
      if (!await _recorder.hasPermission()) {
        _toonFout('Geen toegang tot microfoon. '
            'Sta toe in browser-instellingen.');
        return;
      }
      await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.opus), path: '');
      setState(() {
        _isOpnemen = true;
        _opnameSeconden = 0;
        _opnamePad = null;
        _opnameBytes = null;
      });
      _opnameTimer?.cancel();
      _opnameTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _opnameSeconden++);
        if (_opnameSeconden >= 30) _stopOpname();
      });
    } catch (e) {
      _toonFout('Opname starten mislukt: $e');
    }
  }

  Future<void> _stopOpname() async {
    try {
      final pad = await _recorder.stop();
      _opnameTimer?.cancel();
      if (pad == null) {
        setState(() => _isOpnemen = false);
        return;
      }
      final response = await http.get(Uri.parse(pad));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        _toonFout('Opname kon niet worden gelezen');
        setState(() => _isOpnemen = false);
        return;
      }
      try {
        await _previewPlayer.setUrl(pad);
      } catch (_) {}
      setState(() {
        _isOpnemen = false;
        _opnamePad = pad;
        _opnameBytes = response.bodyBytes;
      });
    } catch (e) {
      _toonFout('Opname stoppen mislukt: $e');
    }
  }

  Future<void> _kiesMp3() async {
    try {
      final result = await FilePicker.platform.pickFiles(
          type: FileType.audio, withData: true);
      if (result == null) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        _toonFout('Bestand kon niet worden gelezen');
        return;
      }
      if (bytes.length > 5 * 1024 * 1024) {
        _toonFout('MP3 te groot (max 5MB)');
        return;
      }
      setState(() {
        _mp3Bytes = bytes;
        _mp3Naam = file.name;
      });
    } catch (e) {
      _toonFout('MP3 kiezen mislukt: $e');
    }
  }

  Future<void> _speelOpnamePreview() async {
    if (_opnamePad == null) return;
    try {
      await _previewPlayer.seek(Duration.zero);
      await _previewPlayer.play();
    } catch (e) {
      _toonFout('Afspelen mislukt: $e');
    }
  }

  Future<void> _speelHuidigePreview() async {
    if ((_huidigeUrl ?? '').isEmpty) return;
    try {
      // Speel uit lokale bytes (bij dialog-open gepreload) — vermijdt
      // iOS Safari CORS/range-issues én gesture-verlies door netwerk-fetch
      // vóór play(). Dat liet de knop op iPhone stil falen.
      if (_huidigeBytes == null) {
        final resp = await http.get(Uri.parse(_huidigeUrl!));
        if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
          _toonFout('Audio kon niet worden geladen (${resp.statusCode})');
          return;
        }
        _huidigeBytes = resp.bodyBytes;
      }
      final mime = _huidigType == 'mp3' ? 'audio/mpeg' : 'audio/webm';
      await _previewPlayer.setAudioSource(
          _BytesAudioSource(_huidigeBytes!, mime));
      await _previewPlayer.play();
    } catch (e) {
      // V8.6: native iOS heeft geen CORS-restricties — daar werkt dit wel.
      _toonFout('Audio kan niet worden afgespeeld op deze iPhone-browser. '
          'In de Ons Moment app werkt dit straks wel.');
    }
  }

  Future<void> _opslaanOpname() async {
    if (_opnameBytes == null) return;
    final kringId = await DeviceModusService.huidigeKringIdMetFallback();
    if (kringId == null) return;
    setState(() => _bezig = true);
    final ok = await DagelijksAudioService.upload(
      kringId: kringId,
      momentId: widget.doc.id,
      bytes: _opnameBytes!,
      type: 'stem',
      collectie: widget.doc.reference.parent.id,
    );
    if (!mounted) return;
    setState(() => _bezig = false);
    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✓ Stem-opname opgeslagen'),
        backgroundColor: kGreen));
    } else {
      _toonFout('Opslaan mislukt — probeer opnieuw');
    }
  }

  Future<void> _opslaanMp3() async {
    if (_mp3Bytes == null) return;
    final kringId = await DeviceModusService.huidigeKringIdMetFallback();
    if (kringId == null) return;
    setState(() => _bezig = true);
    final ok = await DagelijksAudioService.upload(
      kringId: kringId,
      momentId: widget.doc.id,
      bytes: _mp3Bytes!,
      type: 'mp3',
      collectie: widget.doc.reference.parent.id,
    );
    if (!mounted) return;
    setState(() => _bezig = false);
    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✓ MP3 opgeslagen'), backgroundColor: kGreen));
    } else {
      _toonFout('Opslaan mislukt — probeer opnieuw');
    }
  }

  Future<void> _zetTerugNaarBel() async {
    final kringId = await DeviceModusService.huidigeKringIdMetFallback();
    if (kringId == null) return;
    setState(() => _bezig = true);
    final ok = await DagelijksAudioService.reset(
        kringId: kringId, momentId: widget.doc.id,
        collectie: widget.doc.reference.parent.id);
    if (!mounted) return;
    setState(() => _bezig = false);
    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✓ Terug naar standaard bel'),
        backgroundColor: kGreen));
    } else {
      _toonFout('Verwijderen mislukt — probeer opnieuw');
    }
  }

  void _toonFout(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.red));

  @override
  Widget build(BuildContext context) {
    final d = widget.doc.data() as Map<String, dynamic>;
    final label = d['label'] ?? 'Moment';
    final heeftHuidig = (_huidigeUrl ?? '').isNotEmpty;
    final huidigLabel = _huidigType == 'stem' ? '🎤 Eigen stem'
        : _huidigType == 'mp3' ? '🎵 Eigen MP3'
        : '🔔 Standaard bel';

    return Dialog(backgroundColor: kCream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Eigen stem of liedje voor "$label"',
                style: const TextStyle(fontSize: 18,
                    fontWeight: FontWeight.w900, color: kBrown)),
            const SizedBox(height: 4),
            Text('Op dit moment: $huidigLabel',
                style: const TextStyle(fontSize: 12, color: kTextMuted)),
            if (heeftHuidig) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _speelHuidigePreview,
                child: Container(padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: kPeachPale,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kPeach, width: 1.5)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.play_arrow_rounded, color: kPeach, size: 18),
                    SizedBox(width: 4),
                    Text('Beluister huidige',
                        style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w800, color: kPeach)),
                  ]))),
            ],
            const SizedBox(height: 20),

            // STEM OPNAME
            const Text('🎤 Neem zelf op',
                style: TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w800, color: kBrown)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _bezig ? null
                  : (_isOpnemen ? _stopOpname : _startOpname),
              child: Container(width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _isOpnemen ? kRood : kPeach,
                  borderRadius: BorderRadius.circular(12)),
                child: Center(child: Text(
                  _isOpnemen
                      ? '🔴 Stoppen (${_opnameSeconden}s / 30s)'
                      : (_opnameBytes != null
                          ? '✓ Opname klaar (${_opnameSeconden}s) — tik om opnieuw'
                          : 'Start opname (max 30 sec)'),
                  style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w800, color: kWhite))),
              ),
            ),
            if (_opnameBytes != null && !_isOpnemen) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: _speelOpnamePreview,
                  child: Container(padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(color: kWhite,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kPeach, width: 1.5)),
                    child: const Center(child: Row(mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow_rounded, color: kPeach, size: 18),
                        SizedBox(width: 4),
                        Text('Voorbeeld', style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w800, color: kPeach)),
                      ]))),
                )),
                const SizedBox(width: 8),
                Expanded(child: GestureDetector(
                  onTap: _bezig ? null : _opslaanOpname,
                  child: Container(padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                        color: _bezig ? kPeachLight : kGreen,
                        borderRadius: BorderRadius.circular(10)),
                    child: const Center(child: Text('Opslaan',
                        style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w800, color: kWhite)))),
                )),
              ]),
            ],
            const SizedBox(height: 20),

            // MP3 UPLOAD
            const Text('🎵 Upload MP3',
                style: TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w800, color: kBrown)),
            const SizedBox(height: 4),
            const Text('Houd MP3 onder ~30 seconden — max 5MB',
                style: TextStyle(fontSize: 11, color: kTextMuted)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _bezig ? null : _kiesMp3,
              child: Container(width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(color: kPeachPale,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kPeach, width: 1.5)),
                child: Center(child: Text(
                  _mp3Naam.isNotEmpty
                      ? '✓ $_mp3Naam — tik om ander te kiezen'
                      : 'Kies MP3-bestand',
                  style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w800, color: kBrown))),
              ),
            ),
            if (_mp3Bytes != null) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _bezig ? null : _opslaanMp3,
                child: Container(width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                      color: _bezig ? kPeachLight : kGreen,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Center(child: Text('Opslaan MP3',
                      style: TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w800, color: kWhite)))),
              ),
            ],
            const SizedBox(height: 20),

            // TERUG NAAR STANDAARD
            if (heeftHuidig)
              GestureDetector(
                onTap: _bezig ? null : _zetTerugNaarBel,
                child: Container(width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(color: kWhite,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kPeachLight, width: 1.5)),
                  child: const Center(child: Text(
                      '🔔 Terug naar standaard bel',
                      style: TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w800, color: kBrown)))),
              ),
            const SizedBox(height: 12),
            Center(child: TextButton(
              onPressed: _bezig ? null : () => Navigator.pop(context),
              child: const Text('Sluiten',
                  style: TextStyle(color: kTextMuted,
                      fontWeight: FontWeight.w700)))),
          ]),
        ),
      ),
    );
  }
}

class _GeplandItem extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final bool isHistorie;
  const _GeplandItem({required this.doc, this.isHistorie = false});
  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final t = (d['geplandOp'] as Timestamp?)?.toDate() ?? DateTime.now();
    return Container(margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: isHistorie ? kPeachPale : kWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kPeachLight, width: 1.5)),
      child: Row(children: [
        Text(_emojiVoorType(d['type'] ?? ''),
            style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text(_labelVoorType(d['type'] ?? ''),
              style: const TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w800, color: kBrown)),
          if ((d['bericht'] ?? '').toString().isNotEmpty)
            Text(d['bericht'], maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: kTextMuted)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${t.day.toString().padLeft(2, '0')}-${t.month.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 11, color: kTextMuted)),
          Text('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w800, color: kBrown)),
        ]),
      ]),
    );
  }
  String _emojiVoorType(String type) {
    switch (type) {
      case 'foto': return '📷';
      case 'stem': return '🎙️';
      case 'lied': return '🎵';
      case 'tekst': return '✏️';
      case 'hartje': return '💕';
      case 'video': return '🎥';
      default: return '⭐';
    }
  }
  String _labelVoorType(String type) {
    switch (type) {
      case 'foto': return 'Foto bericht';
      case 'stem': return 'Stem bericht';
      case 'lied': return 'Liedje';
      case 'tekst': return 'Tekst bericht';
      case 'hartje': return 'Hartje';
      case 'video': return 'Video';
      default: return 'Bericht';
    }
  }
}

// ════════════════════════════════════════════════════════════
// NOTITIES TAB
// ════════════════════════════════════════════════════════════
class NotitiesTab extends StatefulWidget {
  const NotitiesTab({super.key});
  @override
  State<NotitiesTab> createState() => _NotitiesTabState();
}

class _NotitiesTabState extends State<NotitiesTab> {
  final _ctrl = TextEditingController();
  String? _ontvangerNaam;
  String? _accountType;
  String? _kringId;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirebaseFirestore.instance.collection('gebruikers').doc(uid).get()
          .then((doc) {
        if (!mounted) return;
        setState(() {
          _accountType = doc.data()?['accountType'] as String?;
          _ontvangerNaam = doc.data()?['ontvangerNaam'] as String?;
        });
      });
    }
    DeviceModusService.huidigeKringIdMetFallback().then((id) {
      if (!mounted) return;
      setState(() => _kringId = id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final kringId = _kringId;
    return Padding(padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Notities',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
                color: kBrown)),
        const SizedBox(height: 8),
        Text('Deel observaties met ${_accountType == 'zorg' ? 'je collega\'s' : 'andere kringleden en mantelzorgers'}',
            style: const TextStyle(fontSize: 13, color: kTextMuted)),
        const SizedBox(height: 16),
        TextField(controller: _ctrl, maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Bijv. "Vandaag genoot moeder erg van de muziek"',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            filled: true, fillColor: kWhite)),
        const SizedBox(height: 10),
        GestureDetector(onTap: _opslaan,
          child: Container(padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kPeach, kRose]),
              borderRadius: BorderRadius.circular(12)),
            child: const Center(child: Text('Notitie opslaan',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                    color: kWhite))),
          ),
        ),
        const SizedBox(height: 24),
        const Text('EERDERE NOTITIES',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                color: kTextMuted, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        Expanded(child: kringId == null ? const SizedBox()
          : StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('notities')
              .where('kringId', isEqualTo: kringId).snapshots(),
          builder: (ctx, snap) {
            if (!snap.hasData) return const Center(
                child: CircularProgressIndicator(color: kPeach));
            final docs = snap.data!.docs.toList()
              ..sort((a, b) {
                final ta = (a.data() as Map)['aangemaaktOp'] as Timestamp?;
                final tb = (b.data() as Map)['aangemaaktOp'] as Timestamp?;
                if (ta == null && tb == null) return 0;
                if (ta == null) return 1;
                if (tb == null) return -1;
                return tb.compareTo(ta);
              });
            if (docs.isEmpty) return const Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('📝', style: TextStyle(fontSize: 48)),
              SizedBox(height: 8),
              Text('Nog geen notities', style: TextStyle(
                  fontSize: 14, color: kTextMuted)),
            ]));
            return ListView.builder(itemCount: docs.length,
              itemBuilder: (c, i) {
                final d = docs[i].data() as Map<String, dynamic>;
                final vanNaam = d['vanNaam'] as String? ?? 'Kringlid';
                final ts = d['aangemaaktOp'] as Timestamp?;
                final header = ts != null
                    ? '$vanNaam · ${_kortDatumTijdNl(ts.toDate())}'
                    : vanNaam;
                return Container(margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: kWhite,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kPeachLight, width: 1.5)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(header, style: const TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w600, color: kTextMuted)),
                      const SizedBox(height: 6),
                      Text(d['tekst'] ?? '',
                          style: const TextStyle(fontSize: 13,
                              color: kBrown, height: 1.4)),
                    ]));
              });
          },
        )),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kPeachPale,
            borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Text('🔒', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Notities zijn alleen zichtbaar voor '
              '${_accountType == 'zorg' ? 'collega\'s' : 'familieleden en mantelzorgers'}. '
              '${dierbareNaamLabel(_accountType, _ontvangerNaam)} ziet deze niet.',
              style: const TextStyle(fontSize: 11,
                  color: kBrownLight, height: 1.4))),
          ]),
        ),
      ]),
    );
  }

  Future<void> _opslaan() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final kringId = await DeviceModusService.huidigeKringIdMetFallback();
    if (uid == null || kringId == null || _ctrl.text.trim().isEmpty) return;
    final familieDoc = await FirebaseFirestore.instance
        .collection('gebruikers').doc(uid).get();
    final familieNaam = familieDoc.data()?['familieNaam'] ?? 'Kringlid';
    await FirebaseFirestore.instance.collection('notities').add({
      'kringId': kringId,
      'vanNaam': familieNaam,
      'tekst': _ctrl.text.trim(),
      'aangemaaktOp': FieldValue.serverTimestamp(),
    });
    _ctrl.clear();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notitie opgeslagen'),
            backgroundColor: kGreen));
  }

  String _kortDatumTijdNl(DateTime d) {
    const m = ['jan', 'feb', 'mrt', 'apr', 'mei', 'jun',
               'jul', 'aug', 'sep', 'okt', 'nov', 'dec'];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${m[d.month - 1]}, $hh:$mm';
  }
}

// ════════════════════════════════════════════════════════════
// INSTELLINGEN TAB
// ════════════════════════════════════════════════════════════
class InstellingenTab extends StatefulWidget {
  final bool alsOntvanger;
  const InstellingenTab({super.key, this.alsOntvanger = false});
  @override
  State<InstellingenTab> createState() => _InstellingenTabState();
}

class _InstellingenTabState extends State<InstellingenTab> {
  String? _ontvangerNaam;
  String? _accountType;
  bool _isAccountMaker = false;
  String? _huidigeOntvangerModus;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance.collection('gebruikers').doc(uid).get()
        .then((doc) {
      if (!mounted) return;
      setState(() {
        _accountType = doc.data()?['accountType'] as String?;
        _ontvangerNaam = doc.data()?['ontvangerNaam'] as String?;
      });
    });
    if (!widget.alsOntvanger) {
      DeviceModusService.krijgApparaatId().then((apparaatId) async {
        final ok = await ApparaatService.isAccountMaker(
            familieUid: uid, apparaatId: apparaatId);
        if (!mounted) return;
        setState(() => _isAccountMaker = ok);
        if (ok) {
          final huidig = await ApparaatService
              .krijgWeergaveModusVoorOntvangers(uid);
          if (mounted) setState(() => _huidigeOntvangerModus = huidig);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final naam = dierbareNaamLabel(_accountType, _ontvangerNaam);
    return Padding(padding: const EdgeInsets.all(20),
      child: ListView(children: [
        const Text('Instellingen',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
                color: kBrown)),
        const SizedBox(height: 20),
        _sectie('DAGELIJKSE MOMENTEN'),
        _item('📅', 'Momenten beheren',
            'Voeg toe, pas aan of verwijder vaste momenten', () {
          Navigator.push(context, MaterialPageRoute(
              builder: (c) => const MomentenBeherenScherm()));
        }),
        const SizedBox(height: 20),
        _sectie('ACCOUNT'),
        _item('👵', 'Ontvanger-profiel',
            'Naam, foto, lievelingsdingen en herkenningsgeluid', () {
          Navigator.push(context, MaterialPageRoute(
              builder: (c) => const OntvangerInfoScherm()));
        }),
        _item('📥', 'Ontvangen berichten van $naam',
            'Alle berichten die ${jeDierbareLabel(_accountType)} heeft gestuurd', () {
          Navigator.push(context, MaterialPageRoute(
              builder: (c) => const OntvangenBerichtenScherm()));
        }),
        if (!widget.alsOntvanger)
          _item('👥', 'Kringleden beheren',
              'Bekijk en verwijder apparaten in de kring', () {
            Navigator.push(context, MaterialPageRoute(
                builder: (c) => const KringledenScherm()));
          }),
        if (_isAccountMaker && !widget.alsOntvanger)
          _item('🔄', 'Wijzig modus van $naam',
              'Vergrendeld of meldings — op afstand',
              () => _toonModusDialog(context, naam)),
        if (_isAccountMaker && !widget.alsOntvanger)
          _item('✉️', 'Email of wachtwoord wijzigen',
              _accountType == 'zorg'
                  ? 'Voor jou en je collega\'s'
                  : 'Voor jou en je kringleden',
              () => showDialog(context: context,
                  builder: (ctx) => const _AccountWijzigDialog())),
        const SizedBox(height: 20),
        _sectie('OVERIG'),
        _item('❓', 'Hulp en uitleg', 'Veelgestelde vragen', () {
          showModalBottomSheet(context: context,
              backgroundColor: Colors.transparent, isScrollControlled: true,
              builder: (ctx) => const _HulpDialog());
        }),
        _item('🚪', 'Uitloggen', 'Logt uit en wist apparaat-instellingen', () async {
          await DeviceModusService.wis();
          await FirebaseAuth.instance.signOut();
        }),
        const SizedBox(height: 30),
        Center(child: Opacity(opacity: 0.85,
            child: Image.asset('assets/images/logo.png', height: 48))),
        const SizedBox(height: 8),
        const Center(child: Text('Ons Moment v7',
            style: TextStyle(fontSize: 11, color: kTextMuted))),
      ]),
    );
  }

  void _toonModusDialog(BuildContext context, String naam) {
    String? gekozen = _huidigeOntvangerModus;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: kCream,
        title: Text('Hoe gebruikt $naam dit apparaat?',
            style: const TextStyle(fontSize: 17,
                fontWeight: FontWeight.w900, color: kBrown)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _modusOptie(
              emoji: '🔒', titel: 'Alleen voor Ons Moment',
              uitleg: 'Kiosk — alleen popups, geen andere apps',
              modusId: DeviceModusService.VERGRENDELD,
              gekozen: gekozen, huidig: _huidigeOntvangerModus,
              onTap: () => setLocal(() =>
                  gekozen = DeviceModusService.VERGRENDELD)),
          const SizedBox(height: 10),
          _modusOptie(
              emoji: '📱', titel: 'Ook voor andere dingen',
              uitleg: 'Berichten komen als melding binnen',
              modusId: DeviceModusService.MELDINGEN,
              gekozen: gekozen, huidig: _huidigeOntvangerModus,
              onTap: () => setLocal(() =>
                  gekozen = DeviceModusService.MELDINGEN)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuleren',
                  style: TextStyle(color: kTextMuted,
                      fontWeight: FontWeight.w700))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kPeach,
              disabledBackgroundColor: kPeachLight,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
            onPressed: (gekozen == null
                    || gekozen == _huidigeOntvangerModus)
                ? null
                : () => _commitModusWijziging(ctx, gekozen!, naam),
            child: const Text('Wijzig', style: TextStyle(
                color: kWhite, fontWeight: FontWeight.w800))),
        ],
      ),
    ));
  }

  Widget _modusOptie({required String emoji, required String titel,
      required String uitleg, required String modusId,
      required String? gekozen, required String? huidig,
      required VoidCallback onTap}) {
    final isGekozen = gekozen == modusId;
    final isHuidig = huidig == modusId;
    return GestureDetector(onTap: onTap, child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: isGekozen ? kPeachPale : kWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isGekozen ? kPeach : kPeachLight, width: 2)),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Row(children: [
            Flexible(child: Text(titel, style: const TextStyle(fontSize: 13,
                fontWeight: FontWeight.w800, color: kBrown))),
            if (isHuidig) ...[
              const SizedBox(width: 6),
              const Text('(huidig)', style: TextStyle(fontSize: 10,
                  fontWeight: FontWeight.w800, color: kPeach)),
            ],
          ]),
          Text(uitleg, style: const TextStyle(fontSize: 11,
              color: kTextMuted, height: 1.3)),
        ])),
      ]),
    ));
  }

  Future<void> _commitModusWijziging(BuildContext ctx, String nieuweModus,
      String naam) async {
    Navigator.pop(ctx);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ok = await ApparaatService.zetWeergaveModusVoorOntvangers(
        familieUid: uid, nieuweModus: nieuweModus);
    if (!mounted) return;
    if (ok) setState(() => _huidigeOntvangerModus = nieuweModus);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? '✓ Modus van $naam gewijzigd. '
              'Het apparaat van $naam herlaadt automatisch.'
          : 'Wijzigen mislukt — probeer opnieuw'),
      backgroundColor: ok ? Colors.green : Colors.red,
      duration: const Duration(seconds: 4),
    ));
  }

  Widget _sectie(String t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(t, style: const TextStyle(fontSize: 11,
        fontWeight: FontWeight.w800, color: kTextMuted, letterSpacing: 0.8)));

  Widget _item(String emoji, String titel, String tekst, VoidCallback onTap) =>
    GestureDetector(onTap: onTap, child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kPeachLight, width: 1.5)),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text(titel, style: const TextStyle(fontSize: 14,
              fontWeight: FontWeight.w800, color: kBrown)),
          if (tekst.isNotEmpty) Text(tekst, style: const TextStyle(
              fontSize: 11, color: kTextMuted)),
        ])),
        const Icon(Icons.chevron_right_rounded, color: kTextMuted),
      ]),
    ));
}

// ════════════════════════════════════════════════════════════
// MOMENTEN BEHEREN
// ════════════════════════════════════════════════════════════
class MomentenBeherenScherm extends StatelessWidget {
  const MomentenBeherenScherm({super.key});
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: kCream,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0,
        iconTheme: const IconThemeData(color: kBrown),
        title: const Text('Momenten beheren',
            style: TextStyle(color: kBrown, fontWeight: FontWeight.w900))),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end, children: [
        FloatingActionButton.extended(
          heroTag: 'fab_eenmalig',
          backgroundColor: kRose,
          onPressed: () => _opnenEenmaligDialog(context, uid),
          icon: const Icon(Icons.event_rounded, color: kWhite),
          label: const Text('Eenmalig gepland',
              style: TextStyle(color: kWhite, fontWeight: FontWeight.w800))),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'fab_dagelijks',
          backgroundColor: kPeach,
          onPressed: () => _opnenDialog(context, uid),
          icon: const Icon(Icons.repeat_rounded, color: kWhite),
          label: const Text('Dagelijks moment',
              style: TextStyle(color: kWhite, fontWeight: FontWeight.w800))),
      ]),
      body: uid == null ? const SizedBox()
        : FutureBuilder<String?>(
        future: DeviceModusService.huidigeKringIdMetFallback(),
        builder: (ctx, kringSnap) {
          final kringId = kringSnap.data;
          if (kringId == null) return const SizedBox();
          return ListView(padding: const EdgeInsets.all(20), children: [
            const _SectieTitel('🔁 DAGELIJKSE MOMENTEN'),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('dagelijkse_momenten')
                  .where('kringId', isEqualTo: kringId)
                  .where('actief', isEqualTo: true).snapshots(),
              builder: (ctx, snap) {
                if (!snap.hasData) return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator(
                      color: kPeach)));
                final docs = snap.data!.docs.toList();
                if (docs.isEmpty) {
                  return _beheerLeeg('Nog geen dagelijkse momenten');
                }
                docs.sort((a, b) {
                  final ua = (a.data() as Map)['uur'] ?? 0;
                  final ub = (b.data() as Map)['uur'] ?? 0;
                  if (ua != ub) return (ua as int).compareTo(ub as int);
                  return ((a.data() as Map)['minuut'] as int)
                      .compareTo((b.data() as Map)['minuut'] as int);
                });
                return Column(children: docs.map((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final audioType =
                      d['aangepasteAudioType'] as String? ?? '';
                  final audioLabel = audioType == 'stem' ? '🎤 Eigen stem'
                      : audioType == 'mp3' ? '🎵 Eigen MP3'
                      : '🔔 Standaard bel';
                  return GestureDetector(
                    onTap: () => _opnenDialog(context, uid, bestaand: doc),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: kWhite,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: kPeachLight, width: 2)),
                      child: Row(children: [
                        Text(d['emoji'] ?? '⭐',
                            style: const TextStyle(fontSize: 28)),
                        const SizedBox(width: 14),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d['label'] ?? 'Moment',
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: kBrown)),
                            Text('${(d['uur'] ?? 0).toString().padLeft(2, '0')}:${(d['minuut'] ?? 0).toString().padLeft(2, '0')} elke dag • $audioLabel',
                                style: const TextStyle(
                                    fontSize: 12, color: kTextMuted)),
                          ])),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.red),
                          onPressed: () async {
                            final kringId = await DeviceModusService
                                .huidigeKringIdMetFallback();
                            if (kringId != null) {
                              await DagelijksAudioService.reset(
                                  kringId: kringId, momentId: doc.id);
                            }
                            await doc.reference.update({'actief': false});
                          }),
                      ]),
                    ),
                  );
                }).toList());
              },
            ),
            const SizedBox(height: 24),
            const _SectieTitel('📅 EENMALIGE MOMENTEN'),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('gepland_momenten')
                  .where('kringId', isEqualTo: kringId)
                  .where('actief', isEqualTo: true).snapshots(),
              builder: (ctx, snap) {
                if (!snap.hasData) return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator(
                      color: kPeach)));
                // Verberg eenmalige momenten meer dan 24u na hun tijd —
                // beheer-lijst blijft schoon voor mantelzorger. Popup-pad
                // (actief+getoond) is ongewijzigd; alleen UI-filter.
                final grens =
                    DateTime.now().subtract(const Duration(hours: 24));
                final docs = snap.data!.docs.where((d) {
                  final t = ((d.data() as Map)['geplandOp'] as Timestamp?)
                      ?.toDate();
                  return t != null && t.isAfter(grens);
                }).toList()..sort((a, b) {
                  final ta = (a.data() as Map)['geplandOp'] as Timestamp?;
                  final tb = (b.data() as Map)['geplandOp'] as Timestamp?;
                  if (ta == null || tb == null) return 0;
                  return ta.compareTo(tb);
                });
                if (docs.isEmpty) {
                  return _beheerLeeg('Nog geen eenmalige momenten');
                }
                return Column(children: docs.map((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final geplandOp =
                      (d['geplandOp'] as Timestamp?)?.toDate();
                  final tijdLabel = geplandOp != null
                      ? '${geplandOp.day.toString().padLeft(2, '0')}-'
                        '${geplandOp.month.toString().padLeft(2, '0')} • '
                        '${geplandOp.hour.toString().padLeft(2, '0')}:'
                        '${geplandOp.minute.toString().padLeft(2, '0')}'
                      : 'Geen tijdstip';
                  final audioType =
                      d['aangepasteAudioType'] as String? ?? '';
                  final audioLabel = audioType == 'stem' ? '🎤 Eigen stem'
                      : audioType == 'mp3' ? '🎵 Eigen MP3'
                      : '🔔 Standaard bel';
                  return GestureDetector(
                    onTap: () =>
                        _opnenEenmaligDialog(context, uid, bestaand: doc),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: kWhite,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: kPeachLight, width: 2)),
                      child: Row(children: [
                        Text(d['emoji'] ?? '⭐',
                            style: const TextStyle(fontSize: 28)),
                        const SizedBox(width: 14),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d['label'] ?? 'Moment',
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: kBrown)),
                            Text('$tijdLabel • $audioLabel',
                                style: const TextStyle(
                                    fontSize: 12, color: kTextMuted)),
                          ])),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.red),
                          onPressed: () async {
                            final kringId = await DeviceModusService
                                .huidigeKringIdMetFallback();
                            if (kringId != null) {
                              await DagelijksAudioService.reset(
                                  kringId: kringId, momentId: doc.id,
                                  collectie: 'gepland_momenten');
                            }
                            await doc.reference
                                .update({'actief': false});
                          }),
                      ]),
                    ),
                  );
                }).toList());
              },
            ),
          ]);
        },
      ),
    );
  }

  Widget _beheerLeeg(String tekst) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
    child: Text(tekst,
        style: const TextStyle(fontSize: 12, color: kTextMuted)));

  Future<void> _opnenDialog(BuildContext context, String? uid,
      {QueryDocumentSnapshot? bestaand}) async {
    if (uid == null) return;
    final initial = bestaand?.data() as Map<String, dynamic>?;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _NieuwMomentDialog(
          initial: initial, bestaand: bestaand));
    if (result == null) return;
    if (bestaand != null) {
      await bestaand.reference.update({
        'emoji': result['emoji'],
        'label': result['label'],
        'uur': result['uur'],
        'minuut': result['minuut'],
      });
    } else {
      final kringId = await DeviceModusService.huidigeKringIdMetFallback();
      if (kringId == null) return;
      await FirebaseFirestore.instance.collection('dagelijkse_momenten').add({
        'kringId': kringId,
        'emoji': result['emoji'],
        'label': result['label'],
        'uur': result['uur'],
        'minuut': result['minuut'],
        'mediaType': '', 'mediaUrl': '', 'tekstBericht': '',
        'actief': true,
        'aangemaaktOp': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _opnenEenmaligDialog(BuildContext context, String? uid,
      {QueryDocumentSnapshot? bestaand}) async {
    if (uid == null) return;
    final initial = bestaand?.data() as Map<String, dynamic>?;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _EenmaligMomentDialog(
          initial: initial, bestaand: bestaand));
    if (result == null) return;
    if (bestaand != null) {
      // Update alleen de bewerkbare velden — kringId/actief/getoond/aangemaakt
      // blijven bewust ongemoeid zodat de popup-trigger en historie kloppen.
      await bestaand.reference.update({
        'emoji': result['emoji'],
        'label': result['label'],
        'uur': result['uur'],
        'minuut': result['minuut'],
        'geplandOp': Timestamp.fromDate(result['geplandOp'] as DateTime),
      });
    } else {
      final kringId = await DeviceModusService.huidigeKringIdMetFallback();
      if (kringId == null) return;
      await FirebaseFirestore.instance.collection('gepland_momenten').add({
        'kringId': kringId,
        'emoji': result['emoji'],
        'label': result['label'],
        'uur': result['uur'],
        'minuut': result['minuut'],
        'geplandOp': Timestamp.fromDate(result['geplandOp'] as DateTime),
        'actief': true,
        'getoond': false,
        'aangemaakt': FieldValue.serverTimestamp(),
      });
    }
  }
}

class _NieuwMomentDialog extends StatefulWidget {
  final Map<String, dynamic>? initial;
  final QueryDocumentSnapshot? bestaand;
  const _NieuwMomentDialog({this.initial, this.bestaand});
  @override
  State<_NieuwMomentDialog> createState() => _NieuwMomentDialogState();
}

class _NieuwMomentDialogState extends State<_NieuwMomentDialog> {
  late String _emoji;
  late final TextEditingController _labelCtrl;
  late TimeOfDay _tijd;
  final _emojis = ['⭐', '☀️', '☕', '🍽️', '🌙', '💕', '🎵', '🌸', '🌳', '📚', '🐦', '🍰'];

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _emoji = init?['emoji'] as String? ?? '⭐';
    _labelCtrl = TextEditingController(text: init?['label'] as String? ?? '');
    _tijd = TimeOfDay(
        hour: init?['uur'] as int? ?? 15,
        minute: init?['minuut'] as int? ?? 0);
  }

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
          Text(widget.initial == null ? 'Nieuw moment' : 'Moment aanpassen',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
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
          const SizedBox(height: 16),
          if (widget.bestaand != null)
            GestureDetector(
              onTap: () => showDialog(context: context,
                  builder: (ctx) =>
                      _AudioInstelDialog(doc: widget.bestaand!)),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: kPeachPale,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kPeach, width: 1.5)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('🎤 ', style: TextStyle(fontSize: 18)),
                  Flexible(child: Text(
                      'Eigen stem of liedje toevoegen',
                      style: TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w800, color: kBrown))),
                ]),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: kPeachPale,
                  borderRadius: BorderRadius.circular(8)),
              child: const Text(
                '💡 Je kunt je eigen stem of een liedje toevoegen '
                'nadat je dit moment hebt opgeslagen.',
                style: TextStyle(fontSize: 12,
                    color: kBrownLight, height: 1.4)),
            ),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Annuleren',
                  style: TextStyle(color: kTextMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kPeach),
              onPressed: () {
                if (_labelCtrl.text.trim().isEmpty) return;
                Navigator.pop(context, {
                  'emoji': _emoji, 'label': _labelCtrl.text.trim(),
                  'uur': _tijd.hour, 'minuut': _tijd.minute,
                });
              },
              child: const Text('Toevoegen',
                  style: TextStyle(color: kWhite, fontWeight: FontWeight.w800))),
          ]),
        ])));
  }
}

class _EenmaligMomentDialog extends StatefulWidget {
  final Map<String, dynamic>? initial;
  final QueryDocumentSnapshot? bestaand;
  const _EenmaligMomentDialog({this.initial, this.bestaand});
  @override
  State<_EenmaligMomentDialog> createState() => _EenmaligMomentDialogState();
}

class _EenmaligMomentDialogState extends State<_EenmaligMomentDialog> {
  late String _emoji;
  late final TextEditingController _labelCtrl;
  late DateTime _datum;
  late TimeOfDay _tijd;
  final _emojis = ['⭐', '☀️', '☕', '🍽️', '🌙', '💕', '🎵', '🌸', '🌳', '📚', '🐦', '🍰'];

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    final geplandOp = (i?['geplandOp'] as Timestamp?)?.toDate();
    _emoji = (i?['emoji'] as String?) ?? '⭐';
    _labelCtrl = TextEditingController(text: (i?['label'] as String?) ?? '');
    _datum = geplandOp ?? DateTime.now().add(const Duration(days: 1));
    _tijd = geplandOp != null
        ? TimeOfDay(hour: geplandOp.hour, minute: geplandOp.minute)
        : const TimeOfDay(hour: 12, minute: 0);
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  String _formatDatum(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.year}';

  void _toonFout(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.red));

  @override
  Widget build(BuildContext context) {
    return Dialog(backgroundColor: kCream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Eenmalig gepland moment',
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
              decoration: const InputDecoration(labelText: 'Naam (bijv. Verjaardag)',
                border: OutlineInputBorder())),
            const SizedBox(height: 16),
            Row(children: [
              const Text('Datum:', style: TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w700, color: kBrown)),
              const SizedBox(width: 12),
              GestureDetector(onTap: () async {
                final d = await showDatePicker(context: context,
                  initialDate: _datum,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) setState(() => _datum = d);
              }, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: kPeachPale,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kPeach, width: 1.5)),
                child: Text(_formatDatum(_datum),
                  style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w800, color: kBrown)))),
            ]),
            const SizedBox(height: 12),
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
                child: Text('${_tijd.hour.toString().padLeft(2, '0')}:'
                    '${_tijd.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w800, color: kBrown)))),
            ]),
            const SizedBox(height: 16),
            if (widget.bestaand != null)
              GestureDetector(
                onTap: () => showDialog(context: context,
                    builder: (ctx) =>
                        _AudioInstelDialog(doc: widget.bestaand!)),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: kPeachPale,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kPeach, width: 1.5)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('🎤 ', style: TextStyle(fontSize: 18)),
                    Flexible(child: Text(
                        'Eigen stem of liedje toevoegen',
                        style: TextStyle(fontSize: 13,
                            fontWeight: FontWeight.w800, color: kBrown))),
                  ]),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: kPeachPale,
                    borderRadius: BorderRadius.circular(8)),
                child: const Text(
                  '💡 Je kunt je eigen stem of een liedje toevoegen '
                  'nadat je dit moment hebt opgeslagen.',
                  style: TextStyle(fontSize: 12,
                      color: kBrownLight, height: 1.4)),
              ),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('Annuleren',
                    style: TextStyle(color: kTextMuted))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: kPeach),
                onPressed: () {
                  if (_labelCtrl.text.trim().isEmpty) {
                    _toonFout('Vul een naam in'); return;
                  }
                  final gepland = DateTime(_datum.year, _datum.month,
                      _datum.day, _tijd.hour, _tijd.minute);
                  if (!gepland.isAfter(DateTime.now())) {
                    _toonFout('Kies een tijdstip in de toekomst'); return;
                  }
                  Navigator.pop(context, {
                    'emoji': _emoji,
                    'label': _labelCtrl.text.trim(),
                    'uur': _tijd.hour,
                    'minuut': _tijd.minute,
                    'geplandOp': gepland,
                  });
                },
                child: const Text('Plannen',
                    style: TextStyle(color: kWhite, fontWeight: FontWeight.w800))),
            ]),
          ]))));
  }
}

class _AccountWijzigDialog extends StatefulWidget {
  const _AccountWijzigDialog();
  @override
  State<_AccountWijzigDialog> createState() => _AccountWijzigDialogState();
}

class _AccountWijzigDialogState extends State<_AccountWijzigDialog> {
  final _emailNieuwCtrl = TextEditingController();
  final _emailWwCtrl = TextEditingController();
  final _wwHuidigCtrl = TextEditingController();
  final _wwNieuwCtrl = TextEditingController();
  final _wwBevestigCtrl = TextEditingController();
  bool _bezigEmail = false;
  bool _bezigWw = false;

  @override
  void dispose() {
    _emailNieuwCtrl.dispose();
    _emailWwCtrl.dispose();
    _wwHuidigCtrl.dispose();
    _wwNieuwCtrl.dispose();
    _wwBevestigCtrl.dispose();
    super.dispose();
  }

  void _toonFout(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.red));

  void _toonSucces(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: kGreen,
          duration: const Duration(seconds: 6)));

  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Huidig wachtwoord klopt niet';
      case 'weak-password':
        return 'Nieuw wachtwoord moet minimaal 6 tekens zijn';
      case 'email-already-in-use':
        return 'Dit email-adres is al in gebruik';
      case 'invalid-email':
        return 'Email-adres is niet geldig';
      case 'requires-recent-login':
        return 'Even opnieuw inloggen, dan kun je het wijzigen';
      default:
        return 'Wijzigen mislukt — probeer opnieuw';
    }
  }

  Future<void> _wijzigEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final nieuw = _emailNieuwCtrl.text.trim();
    final ww = _emailWwCtrl.text;
    if (nieuw.isEmpty || ww.isEmpty) {
      _toonFout('Vul alle velden in'); return;
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(nieuw)) {
      _toonFout('Email-adres is niet geldig'); return;
    }
    setState(() => _bezigEmail = true);
    try {
      final cred = EmailAuthProvider.credential(
          email: user.email!, password: ww);
      await user.reauthenticateWithCredential(cred);
      // verifyBeforeUpdateEmail stuurt een verificatielink naar het nieuwe
      // adres; de e-mail wijzigt pas ná het klikken. Werkt ook met Email
      // Enumeration Protection (anders dan het deprecated updateEmail).
      await user.verifyBeforeUpdateEmail(nieuw);
      if (!mounted) return;
      _toonSucces('✓ Verificatie-link is gestuurd naar $nieuw. Klik op de '
          'link om te bevestigen. Daarna moeten alle kringleden inloggen '
          'met het nieuwe email.');
      _emailNieuwCtrl.clear();
      _emailWwCtrl.clear();
    } on FirebaseAuthException catch (e) {
      _toonFout(_friendlyError(e));
    } catch (_) {
      _toonFout('Wijzigen mislukt — probeer opnieuw');
    } finally {
      if (mounted) setState(() => _bezigEmail = false);
    }
  }

  Future<void> _wijzigWachtwoord() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final huidig = _wwHuidigCtrl.text;
    final nieuw = _wwNieuwCtrl.text;
    final bevestig = _wwBevestigCtrl.text;
    if (huidig.isEmpty || nieuw.isEmpty) {
      _toonFout('Vul alle velden in'); return;
    }
    if (nieuw.length < 6) {
      _toonFout('Nieuw wachtwoord moet minimaal 6 tekens zijn'); return;
    }
    if (nieuw != bevestig) {
      _toonFout('Nieuwe wachtwoorden komen niet overeen'); return;
    }
    setState(() => _bezigWw = true);
    try {
      final cred = EmailAuthProvider.credential(
          email: user.email!, password: huidig);
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(nieuw);
      if (!mounted) return;
      _toonSucces('✓ Wachtwoord gewijzigd. Vertel je kringleden!');
      _wwHuidigCtrl.clear();
      _wwNieuwCtrl.clear();
      _wwBevestigCtrl.clear();
    } on FirebaseAuthException catch (e) {
      _toonFout(_friendlyError(e));
    } catch (_) {
      _toonFout('Wijzigen mislukt — probeer opnieuw');
    } finally {
      if (mounted) setState(() => _bezigWw = false);
    }
  }

  Widget _veld(String label, TextEditingController ctrl, {bool obscure = false}) =>
      Padding(padding: const EdgeInsets.only(bottom: 10),
        child: TextField(controller: ctrl, obscureText: obscure,
          style: const TextStyle(color: kBrown, fontWeight: FontWeight.w700),
          decoration: InputDecoration(labelText: label,
            labelStyle: const TextStyle(color: kTextMuted, fontSize: 13),
            border: const OutlineInputBorder())));

  Widget _actieKnop(String label, bool bezig, VoidCallback onTap) =>
      SizedBox(width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kPeach,
            disabledBackgroundColor: kPeachLight,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
          onPressed: bezig ? null : onTap,
          child: bezig
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(color: kWhite, strokeWidth: 2.5))
              : Text(label, style: const TextStyle(
                  color: kWhite, fontWeight: FontWeight.w800))));

  Widget _sectieKop(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: const TextStyle(fontSize: 15,
        fontWeight: FontWeight.w900, color: kBrown)));

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return Dialog(backgroundColor: kCream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Account gegevens wijzigen',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                    color: kBrown)),
            const SizedBox(height: 16),
            Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(12)),
              child: Text('⚠️ Let op: na wijziging moeten alle kringleden '
                  'opnieuw inloggen met de nieuwe gegevens. Vertel ze de '
                  'nieuwe gegevens!',
                  style: TextStyle(fontSize: 12,
                      color: Colors.orange.shade900, height: 1.4))),
            const SizedBox(height: 20),

            _sectieKop('E-mail wijzigen'),
            Container(width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: kPeachPale,
                  borderRadius: BorderRadius.circular(10)),
              child: Text('Huidig: $email',
                  style: const TextStyle(fontSize: 12, color: kTextMuted))),
            _veld('Nieuw e-mailadres', _emailNieuwCtrl),
            _veld('Huidig wachtwoord', _emailWwCtrl, obscure: true),
            _actieKnop('Wijzig e-mail', _bezigEmail, _wijzigEmail),
            const SizedBox(height: 8),
            const Text('Je krijgt een email op het NIEUWE adres. Open die '
                'en klik op de link om de wijziging te bevestigen.',
                style: TextStyle(fontSize: 11, color: kTextMuted, height: 1.4)),
            const SizedBox(height: 24),

            _sectieKop('Wachtwoord wijzigen'),
            _veld('Huidig wachtwoord', _wwHuidigCtrl, obscure: true),
            _veld('Nieuw wachtwoord', _wwNieuwCtrl, obscure: true),
            _veld('Bevestig nieuw wachtwoord', _wwBevestigCtrl, obscure: true),
            _actieKnop('Wijzig wachtwoord', _bezigWw, _wijzigWachtwoord),
            const SizedBox(height: 16),

            Center(child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Sluiten',
                  style: TextStyle(color: kTextMuted,
                      fontWeight: FontWeight.w700)))),
          ]))));
  }
}

// ════════════════════════════════════════════════════════════
// ONTVANGER INFO
// ════════════════════════════════════════════════════════════
class OntvangerInfoScherm extends StatefulWidget {
  const OntvangerInfoScherm({super.key});
  @override
  State<OntvangerInfoScherm> createState() => _OntvangerInfoSchermState();
}

class _OntvangerInfoSchermState extends State<OntvangerInfoScherm> {
  final _naamCtrl = TextEditingController();
  final _lievelingsdingenCtrl = TextEditingController();
  final _woonplaatsCtrl = TextEditingController();
  final _noodNaamCtrl = TextEditingController();
  final _noodTelCtrl = TextEditingController();
  Uint8List? _fotoBytes;
  String _huidigeFotoUrl = '';
  String _gekozenGeluid = 'twinkel';
  final _geluidPreviewPlayer = AudioPlayer();
  bool _bezig = false;

  @override
  void initState() { super.initState(); _laad(); }

  @override
  void dispose() {
    _geluidPreviewPlayer.dispose();
    super.dispose();
  }

  Future<void> _laad() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('gebruikers').doc(uid).get();
    if (!mounted) return;
    final d = doc.data() ?? {};
    setState(() {
      _naamCtrl.text = d['ontvangerNaam'] ?? '';
      _lievelingsdingenCtrl.text = d['lievelingsdingen'] ?? '';
      _woonplaatsCtrl.text = d['woonplaats'] ?? '';
      _noodNaamCtrl.text = d['noodcontactNaam'] ?? '';
      _noodTelCtrl.text = d['noodcontactTel'] ?? '';
      _huidigeFotoUrl = d['ontvangerFoto'] ?? '';
      _gekozenGeluid = d['herkenningsgeluid'] ?? 'twinkel';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0,
        iconTheme: const IconThemeData(color: kBrown),
        title: const Text('Ontvanger-profiel',
            style: TextStyle(color: kBrown, fontWeight: FontWeight.w900))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(child: GestureDetector(
          onTap: _kiesFoto,
          child: Container(width: 120, height: 120,
            decoration: BoxDecoration(
              color: kPeachPale, shape: BoxShape.circle,
              border: Border.all(color: kPeach, width: 3),
              image: _fotoBytes != null ? DecorationImage(
                image: MemoryImage(_fotoBytes!), fit: BoxFit.cover)
                : _huidigeFotoUrl.isNotEmpty ? DecorationImage(
                  image: NetworkImage(_huidigeFotoUrl), fit: BoxFit.cover)
                : null),
            child: (_fotoBytes == null && _huidigeFotoUrl.isEmpty)
              ? const Center(child: Icon(Icons.add_a_photo_rounded,
                  color: kPeach, size: 36)) : null,
          ),
        )),
        const SizedBox(height: 8),
        const Center(child: Text('Tik om foto te wijzigen',
            style: TextStyle(fontSize: 11, color: kTextMuted))),
        const SizedBox(height: 24),
        _veld('👤', 'Naam', _naamCtrl),
        const SizedBox(height: 10),
        _veld('💕', 'Lievelingsdingen', _lievelingsdingenCtrl),
        const SizedBox(height: 10),
        _veld('🏠', 'Vroegere woonplaats', _woonplaatsCtrl),
        const SizedBox(height: 10),
        _veld('🆘', 'Noodcontact naam', _noodNaamCtrl),
        const SizedBox(height: 10),
        _veld('☎️', 'Noodcontact telefoon', _noodTelCtrl),
        const SizedBox(height: 24),
        const Text('HERKENNINGSGELUID',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                color: kTextMuted, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        ...kGeluiden.map((g) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () {
              setState(() => _gekozenGeluid = g['id']!);
              _speelPreview(g['asset']!);
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
        const SizedBox(height: 30),
        GestureDetector(onTap: _bezig ? null : _opslaan,
          child: Container(width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kPeach, kRose]),
              borderRadius: BorderRadius.circular(16)),
            child: Center(child: _bezig
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(color: kWhite, strokeWidth: 3))
              : const Text('Opslaan',
                  style: TextStyle(fontSize: 16, color: kWhite,
                      fontWeight: FontWeight.w800))))),
      ]),
    );
  }

  Widget _veld(String emoji, String label, TextEditingController ctrl) =>
    Container(decoration: BoxDecoration(color: kWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kPeachLight, width: 2)),
      child: Row(children: [
        Padding(padding: const EdgeInsets.only(left: 16),
            child: Text(emoji, style: const TextStyle(fontSize: 20))),
        Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(controller: ctrl,
            decoration: InputDecoration(labelText: label,
              labelStyle: const TextStyle(color: kTextMuted, fontSize: 12),
              border: InputBorder.none)))),
      ]),
    );

  Future<void> _speelPreview(String pad) async {
    try {
      await _geluidPreviewPlayer.stop();
      await _geluidPreviewPlayer.setAsset(pad);
      await _geluidPreviewPlayer.play();
    } catch (_) {}
  }

  Future<void> _kiesFoto() async {
    final picker = ImagePicker();
    final foto = await picker.pickImage(source: ImageSource.gallery,
        maxWidth: 1200, imageQuality: 85);
    if (foto != null) {
      final bytes = await foto.readAsBytes();
      setState(() => _fotoBytes = bytes);
    }
  }

  Future<void> _opslaan() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _bezig = true);
    try {
      String fotoUrl = _huidigeFotoUrl;
      if (_fotoBytes != null) {
        final ref = FirebaseStorage.instance.ref()
            .child('profielfotos').child('$uid.jpg');
        await ref.putData(_fotoBytes!, SettableMetadata(contentType: 'image/jpeg'));
        fotoUrl = await ref.getDownloadURL();
      }
      await FirebaseFirestore.instance.collection('gebruikers').doc(uid).update({
        'ontvangerNaam': _naamCtrl.text.trim(),
        'ontvangerFoto': fotoUrl,
        'lievelingsdingen': _lievelingsdingenCtrl.text.trim(),
        'woonplaats': _woonplaatsCtrl.text.trim(),
        'noodcontactNaam': _noodNaamCtrl.text.trim(),
        'noodcontactTel': _noodTelCtrl.text.trim(),
        'herkenningsgeluid': _gekozenGeluid,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Opgeslagen ✓'), backgroundColor: kGreen));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Fout: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _bezig = false);
    }
  }
}

// ════════════════════════════════════════════════════════════
// HULP DIALOG
// ════════════════════════════════════════════════════════════
class _HulpDialog extends StatelessWidget {
  const _HulpDialog();

  static const List<_FAQ> _faqs = [
    // ── Algemeen ──
    _FAQ('Algemeen', "Wat is Ons Moment precies?",
        "Ons Moment is een app waarmee je foto's, stem-berichten en "
        "herinneringen kunt sturen naar het apparaat van je dierbare. Je kunt "
        "kiezen hoe de app bij je dierbare verschijnt: als een rustig scherm "
        "dat alleen jouw berichten toont, of als een gewone app met meldingen."),
    _FAQ('Algemeen', "Hoe werkt het voor mijn dierbare?",
        "Je dierbare ontvangt jouw berichten op het apparaat dat bij hem of "
        "haar staat. Bij elk nieuw bericht klinkt een herkenningsgeluid en "
        "verschijnt het bericht in beeld. Je dierbare hoeft zelf niets in te "
        "stellen of in te loggen — het apparaat blijft altijd klaar om "
        "berichten te ontvangen."),
    _FAQ('Algemeen',
        "Wat is het verschil tussen vergrendelde modus en meldingen-modus?",
        "In de vergrendelde modus toont het apparaat alleen Ons Moment. Andere "
        "apps zijn niet bereikbaar en je dierbare kan niet per ongeluk iets "
        "veranderen. Deze modus past goed bij iemand die meer zorg nodig heeft. "
        "In de meldingen-modus werkt het apparaat als gewoon: je dierbare kan "
        "andere apps gebruiken, en Ons Moment laat berichten zien als pop-up. "
        "Deze modus past bij iemand die nog zelf met het apparaat omgaat."),
    // ── Voor families ──
    _FAQ('Voor families', "Hoe voeg ik iemand toe aan de kring?",
        "Open Instellingen en kies 'Kringleden beheren'. Je ziet daar wie er al "
        "in de kring zit. Om een familielid of vriend toe te voegen, deel je "
        "het e-mailadres en wachtwoord van de kring met diegene. Wil je een "
        "zorgverlener uitnodigen? Stuur dan een uitnodigingslink via "
        "'Zorgverlener uitnodigen'. Een kring telt maximaal acht of twintig "
        "personen, afhankelijk van je abonnement."),
    _FAQ('Voor families', "Hoe stuur ik een bericht?",
        "Open het tabblad 'Sturen'. Kies wat je wilt versturen: een foto, een "
        "stem-bericht, een liedje of een tekst. Vul in voor wie het bedoeld is "
        "en wanneer het moet aankomen. Druk op versturen en het bericht "
        "verschijnt op het ingestelde moment bij je dierbare."),
    _FAQ('Voor families', "Hoe maak ik een dagelijkse herinnering?",
        "Ga naar het tabblad 'Agenda' en kies 'Nieuwe herinnering'. Stel een "
        "tijd in en kies wat er moet verschijnen — bijvoorbeeld 'Tijd voor "
        "koffie' met een foto of geluid. De herinnering komt voortaan elke dag "
        "op die tijd in beeld bij je dierbare."),
    _FAQ('Voor families', "Hoe voeg ik mijn eigen stem toe aan een moment?",
        "Bij het maken of bewerken van een herinnering kun je je eigen stem "
        "opnemen via de microfoon-knop. Spreek de boodschap in en sla op. Je "
        "dierbare hoort dan jouw stem in plaats van een standaard geluid."),
    _FAQ('Voor families', "Kan ik een bericht in de toekomst plannen?",
        "Ja. Bij het versturen van een bericht kies je 'Wanneer sturen?' en "
        "stel je een datum en tijd in. Het bericht wordt opgeslagen en "
        "verschijnt vanzelf op het gekozen moment bij je dierbare. Dit werkt "
        "voor losse momenten en voor terugkerende herinneringen."),
    _FAQ('Voor families', "Hoe wijzig ik mijn wachtwoord?",
        "Open Instellingen en kies 'Wachtwoord wijzigen'. Vul je huidige "
        "wachtwoord in en kies een nieuw wachtwoord. Vergeet niet om het nieuwe "
        "wachtwoord ook door te geven aan de andere kringleden — zij gebruiken "
        "hetzelfde wachtwoord om in te loggen."),
    _FAQ('Voor families', "Kan ik iemand uit de kring verwijderen?",
        "Ja. Ga naar Instellingen → Kringleden beheren en tik op de persoon die "
        "je wilt verwijderen. De accountmaker kan iedereen verwijderen; andere "
        "kringleden kunnen alleen zichzelf verwijderen. Het apparaat van de "
        "verwijderde persoon logt automatisch uit."),
    _FAQ('Voor families', "Wat gebeurt er als ik het apparaat weghaal?",
        "Als het apparaat van je dierbare uit staat of geen internet heeft, "
        "blijven verstuurde berichten klaarstaan. Zodra het apparaat weer "
        "aangaat en verbinding heeft, verschijnen de berichten alsnog. Er gaat "
        "niets verloren."),
    // ── Voor zorgverleners ──
    _FAQ('Voor zorgverleners', "Kan ik Ons Moment gebruiken als zorgverlener?",
        "Ja. Met een zorg-abonnement beheer je meerdere cliënten vanuit één "
        "account. Je switcht eenvoudig tussen cliënten via het menu. Je betaalt "
        "op basis van het aantal cliënten dat je beheert."),
    _FAQ('Voor zorgverleners',
        "Hoe begin ik als zorgverlener bij een nieuwe cliënt?",
        "Er zijn twee manieren. De makkelijkste: vraag de familie van je cliënt "
        "om je uit te nodigen via een link. Familie heeft dan al een apparaat "
        "ingericht bij de cliënt en jij wordt automatisch toegevoegd aan hun "
        "overzicht. Heeft je cliënt geen familie die meedoet? Dan installeer je "
        "zelf de Ons Moment-app op een apparaat bij je cliënt, configureer je "
        "dat in de gewenste modus, en stuur je een toestemmingslink naar een "
        "wettelijk vertegenwoordiger."),
    _FAQ('Voor zorgverleners', "Hoe werkt het als familie mij uitnodigt?",
        "Een familielid kan je een uitnodigingslink sturen. Als je daarop "
        "klikt, wordt hun dierbare als cliënt aan je overzicht toegevoegd. "
        "Omdat familie je zelf uitnodigt, geldt dat als toestemming — een "
        "aparte toestemmingslink is dan niet nodig."),
    _FAQ('Voor zorgverleners', "Wat als mijn cliënt geen familie heeft?",
        "Dan maak je de cliënt zelf aan via 'Nieuwe cliënt'. De app vraagt om "
        "toestemming van een wettelijk vertegenwoordiger: je kunt zelf "
        "bevestigen dat je die hebt, of een toestemmingslink versturen. Diegene "
        "klikt op de link, bevestigt dat ze akkoord zijn en de cliënt wordt "
        "actief in je overzicht."),
    _FAQ('Voor zorgverleners',
        "Wat als familie mij wel uitnodigt, maar later weer verwijdert?",
        "Familie kan op elk moment iemand uit hun kring verwijderen, inclusief "
        "de uitgenodigde zorgverlener. Als dat gebeurt verlies je toegang tot "
        "die cliënt. De cliënt verdwijnt uit jouw overzicht en je betaalt vanaf "
        "de volgende periode niet meer voor die plek in je abonnement."),
    // ── Abonnement ──
    _FAQ('Abonnement', "Wat kost Ons Moment?",
        "Voor families is er een Klein-abonnement (tot 8 personen) en een "
        "Groot-abonnement (tot 20 personen). Voor zorgverleners zijn er "
        "abonnementen vanaf 1 cliënt tot onbeperkt. Je kunt kiezen voor "
        "maandelijks betalen of voor een jaarabonnement met korting. Alle "
        "abonnementen starten met een gratis proefperiode van 5 dagen zonder "
        "dat je betaalgegevens hoeft op te geven."),
    _FAQ('Abonnement', "Wie telt mee in mijn abonnement?",
        "Bij een familie-abonnement tellen alle mensen mee die berichten kunnen "
        "sturen — familieleden, vrienden en een eventueel uitgenodigde "
        "zorgverlener. Je dierbare zelf telt niet mee. Bij een zorg-abonnement "
        "telt het aantal cliënten dat je beheert; familieleden van die cliënten "
        "hebben hun eigen familie-abonnement en tellen niet mee in jouw "
        "zorg-abonnement."),
  ];

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85, minChildSize: 0.5, maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(color: kCream,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          Padding(padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: kPeachLight,
                  borderRadius: BorderRadius.circular(2)))),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: [
              Text('💕', style: TextStyle(fontSize: 24)),
              SizedBox(width: 8),
              Text('Hulp & uitleg', style: TextStyle(fontSize: 22,
                  fontWeight: FontWeight.w900, color: kBrown)),
            ])),
          const SizedBox(height: 16),
          Expanded(child: ListView.builder(controller: scrollCtrl,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _faqs.length,
            itemBuilder: (c, i) {
              final faq = _faqs[i];
              final toonKop = i == 0 || _faqs[i - 1].categorie != faq.categorie;
              return Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (toonKop) Padding(
                    padding: EdgeInsets.only(
                        top: i == 0 ? 0 : 18, bottom: 8, left: 4),
                    child: Text(faq.categorie,
                        style: const TextStyle(fontSize: 13,
                            fontWeight: FontWeight.w900, color: kPeach,
                            letterSpacing: 0.8))),
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(color: kWhite,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kPeachLight, width: 1.5)),
                    child: Theme(
                      data: ThemeData(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        title: Text(faq.vraag, style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800,
                            color: kBrown)),
                        iconColor: kPeach, collapsedIconColor: kTextMuted,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Text(faq.antwoord, style: const TextStyle(
                                fontSize: 13, color: kBrownLight,
                                height: 1.5))),
                        ]))),
                ]);
            })),
        ]),
      ),
    );
  }
}

class _FAQ {
  final String categorie, vraag, antwoord;
  const _FAQ(this.categorie, this.vraag, this.antwoord);
}

class _BytesAudioSource extends StreamAudioSource {
  final Uint8List _bytes;
  final String _contentType;
  _BytesAudioSource(this._bytes, this._contentType);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_bytes.sublist(start, end)),
      contentType: _contentType,
    );
  }
}

// ════════════════════════════════════════════════════════════
// ONTVANGEN BERICHTEN SCHERM
// ════════════════════════════════════════════════════════════
class OntvangenBerichtenScherm extends StatefulWidget {
  const OntvangenBerichtenScherm({super.key});
  @override
  State<OntvangenBerichtenScherm> createState() =>
      _OntvangenBerichtenSchermState();
}

class _OntvangenBerichtenSchermState extends State<OntvangenBerichtenScherm> {
  String _ontvangerNaam = 'je dierbare';
  List<String>? _ontvangerApparaatIds;
  String? _kringId;

  @override
  void initState() {
    super.initState();
    _laad();
  }

  Future<void> _laad() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final kringId = await DeviceModusService.huidigeKringIdMetFallback();
      final naamDoc = await FirebaseFirestore.instance
          .collection('gebruikers').doc(uid).get();
      final leden = await ApparaatService.kringLeden(uid);
      if (!mounted) return;
      setState(() {
        _kringId = kringId;
        _ontvangerNaam = dierbareNaamLabel(
            naamDoc.data()?['accountType'] as String?,
            naamDoc.data()?['ontvangerNaam'] as String?);
        _ontvangerApparaatIds = leden
            .where((l) => l['modus'] == 'ontvanger')
            .map((l) => l['apparaatId'] as String)
            .toList();
      });
    } catch (_) {
      if (mounted) setState(() => _ontvangerApparaatIds = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: kCream,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        iconTheme: const IconThemeData(color: kBrown),
        title: Text('Ontvangen van $_ontvangerNaam',
            style: const TextStyle(color: kBrown,
                fontWeight: FontWeight.w900)),
      ),
      body: uid == null
          ? const SizedBox()
          : (_kringId == null || _ontvangerApparaatIds == null
              ? const Center(child: CircularProgressIndicator(color: kPeach))
              : (_ontvangerApparaatIds!.isEmpty
                  ? _leeg('Er is nog geen ontvanger-apparaat in deze kring')
                  : StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('momenten')
                          .where('kringId', isEqualTo: _kringId)
                          .where('vanApparaatId',
                              whereIn: _ontvangerApparaatIds!.take(10).toList())
                          .snapshots(),
                      builder: (ctx, snap) {
                        if (!snap.hasData) {
                          return const Center(
                              child: CircularProgressIndicator(color: kPeach));
                        }
                        final docs = snap.data!.docs.toList()
                          ..sort((a, b) {
                            final ta = (a.data() as Map)['verstuurdOp']
                                as Timestamp?;
                            final tb = (b.data() as Map)['verstuurdOp']
                                as Timestamp?;
                            if (ta == null || tb == null) return 0;
                            return tb.compareTo(ta);
                          });
                        if (docs.isEmpty) {
                          return _leeg('Nog geen berichten van $_ontvangerNaam');
                        }
                        return ListView(
                          padding: const EdgeInsets.all(20),
                          children: docs.map((doc) => _bouwItem(
                              context, doc.id, doc.data() as Map<String, dynamic>))
                              .toList(),
                        );
                      },
                    ))),
    );
  }

  Widget _leeg(String tekst) => Center(
    child: Padding(padding: const EdgeInsets.all(40),
      child: Text(tekst, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: kTextMuted))),
  );

  Widget _bouwItem(BuildContext context, String id, Map<String, dynamic> d) {
    final type = d['type'] as String? ?? '';
    final tekst = (d['bericht'] as String? ?? '').trim();
    final verstuurd = (d['verstuurdOp'] as Timestamp?)?.toDate();
    final gezien = d['gezien'] == true;
    return GestureDetector(
      onTap: () => _toonDetail(context, d),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kPeachLight, width: 2)),
        child: Row(children: [
          Text(_emoji(type), style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_label(type), style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: kBrown)),
              if (tekst.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(tekst,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: kTextMuted)),
              ),
              if (verstuurd != null) Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_formatTijd(verstuurd),
                    style: const TextStyle(fontSize: 10, color: kTextMuted)),
              ),
          ])),
          if (!gezien) Container(
            width: 10, height: 10,
            decoration: const BoxDecoration(
                color: kPeach, shape: BoxShape.circle)),
        ]),
      ),
    );
  }

  void _toonDetail(BuildContext context, Map<String, dynamic> d) {
    showDialog(context: context, builder: (ctx) => Dialog(
      backgroundColor: kCream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(padding: const EdgeInsets.all(20),
        child: _detailInhoud(d)),
    ));
  }

  Widget _detailInhoud(Map<String, dynamic> d) {
    final type = d['type'] as String? ?? '';
    final bericht = (d['bericht'] as String? ?? '').trim();
    final url = d['mediaUrl'] as String? ?? '';
    if (type == 'foto') {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        if (url.isNotEmpty) ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(url, fit: BoxFit.cover)),
        if (bericht.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(bericht, style: const TextStyle(fontSize: 14, color: kBrown)),
        ],
      ]);
    }
    if (type == 'tekst') {
      return Text(bericht.isEmpty ? 'Een lief bericht' : bericht,
          style: const TextStyle(fontSize: 18, color: kBrown));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(_emoji(type), style: const TextStyle(fontSize: 48)),
      const SizedBox(height: 12),
      Text(_label(type), style: const TextStyle(fontSize: 16,
          fontWeight: FontWeight.w800, color: kBrown)),
      if (bericht.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(bericht, style: const TextStyle(fontSize: 14, color: kBrown)),
      ],
    ]);
  }

  String _emoji(String type) {
    switch (type) {
      case 'foto': return '📷';
      case 'stem': return '🎙️';
      case 'lied': return '🎵';
      case 'tekst': return '✏️';
      case 'video': return '🎥';
      default: return '💕';
    }
  }

  String _label(String type) {
    switch (type) {
      case 'foto': return 'Foto';
      case 'stem': return 'Stem-bericht';
      case 'lied': return 'Liedje';
      case 'tekst': return 'Tekst';
      case 'hartje': return 'Hartje';
      case 'video': return 'Video';
      default: return 'Bericht';
    }
  }

  String _formatTijd(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}-'
      '${t.month.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}
