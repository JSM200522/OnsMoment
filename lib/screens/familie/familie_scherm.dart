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
import '../../theme/kleuren.dart';
import '../../data/geluiden.dart';

class FamilieScherm extends StatefulWidget {
  final bool alsOntvanger;
  const FamilieScherm({super.key, this.alsOntvanger = false});
  @override
  State<FamilieScherm> createState() => _FamilieSchermState();
}

class _FamilieSchermState extends State<FamilieScherm> {
  int _tab = 0;

  final _audioPlayer = AudioPlayer();
  final _geluidPlayer = AudioPlayer();
  StreamSubscription<QuerySnapshot>? _momentenListener;
  StreamSubscription<DocumentSnapshot>? _gebruikerSub;
  Map<String, dynamic>? _huidigPopup;
  String? _huidigPopupId;
  String _herkenningsgeluid = 'twinkel';
  String? _mijnApparaatId;
  Timer? _autoSluitTimer;

  @override
  void initState() {
    super.initState();
    // Listeners pas starten ná apparaatId-load zodat _verwerkMomenten nooit
    // triggert met _mijnApparaatId == null (voorkomt off-by-one delay).
    DeviceModusService.krijgApparaatId().then((id) {
      if (!mounted) return;
      setState(() => _mijnApparaatId = id);
      _startMomentenListener();
      _startGebruikerListener();
    });
    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed
          && (_huidigPopup?['type'] == 'stem'
              || _huidigPopup?['type'] == 'lied')) {
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
    super.dispose();
  }

  void _startMomentenListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
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
    if (_mijnApparaatId == null) return;
    final nu = DateTime.now();
    final voor24uur = nu.subtract(const Duration(hours: 24));
    for (final doc in snap.docs) {
      final d = doc.data() as Map<String, dynamic>;
      // Niet voor mij bedoeld (specifiek aan ander apparaat)
      final aan = d['aanApparaatId'] as String?;
      if (aan != null && aan != _mijnApparaatId) continue;
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

    final geluidAsset = kGeluidAssets[_herkenningsgeluid];
    if (geluidAsset != null) {
      bool geluidGespeeld = false;
      try {
        await _geluidPlayer.setAsset(geluidAsset);
        await _geluidPlayer.play();
        geluidGespeeld = true;
      } catch (_) {}
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
    }
    _autoSluitTimer?.cancel();
    _autoSluitTimer = Timer(const Duration(seconds: 60), _sluitPopup);
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
  }

  Widget _popupOverlay() {
    final d = _huidigPopup!;
    final type = d['type'] ?? '';
    final vanNaam = d['vanNaam'] ?? 'Een naaste';
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
              color: kCream.withOpacity(0.88))),
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
  bool _testModus = true;  // Default AAN voor makkelijk testen

  final _recorder = AudioRecorder();
  final _previewPlayer = AudioPlayer();
  bool _isOpnemen = false;
  bool _hebOpname = false;
  String? _opnamePad;
  int _opnameSeconden = 0;
  Timer? _opnameTimer;

  String? _gekozenApparaatId;  // null = iedereen in kring
  String? _gekozenPersoonsNaam;
  String? _mijnApparaatId;
  String? _ontvangerNaam;
  Future<List<Map<String, dynamic>>>? _kringFuture;

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
        const SizedBox(height: 16),
        // TEST MODUS
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

        const SizedBox(height: 16),
        if (widget.alsOntvanger) ...[
          _adresKeuze(),
          const SizedBox(height: 16),
        ],
        Row(children: [
          _typeKnop('📷', 'Foto', 'foto'),
          const SizedBox(width: 10),
          _typeKnop('🎙️', 'Stem', 'stem'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _typeKnop('🎵', 'Lied', 'lied'),
          const SizedBox(width: 10),
          _typeKnop('✏️', 'Tekst', 'tekst'),
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
              child: Center(child: _bezig
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(color: kWhite, strokeWidth: 3))
                : Text(
                    _testModus
                        ? (widget.alsOntvanger
                            ? (_gekozenApparaatId == null
                                ? '⚡ Stuur NU naar de kring'
                                : '⚡ Stuur NU naar ${_gekozenPersoonsNaam ?? "deze persoon"}')
                            : '⚡ Stuur NU naar ${_ontvangerNaam ?? "ontvanger"}')
                        : 'Plan en stuur 💕',
                    style: const TextStyle(fontSize: 16,
                        fontWeight: FontWeight.w800, color: kWhite))),
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

  Future<void> _verstuur() async {
    if (_type == 'tekst' && _berichtCtrl.text.trim().isEmpty) {
      _toonFout('Typ eerst een bericht'); return;
    }
    if (_type == 'stem' && !_hebOpname) {
      _toonFout('Neem eerst een stembericht op'); return;
    }
    if ((_type == 'foto' || _type == 'lied') && _mediaBytes == null) {
      _toonFout('Kies eerst een bestand'); return;
    }
    setState(() => _bezig = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final familieDoc = await FirebaseFirestore.instance
          .collection('gebruikers').doc(user.uid).get();
      final familieData = familieDoc.data() ?? {};
      final familieNaam = familieData['familieNaam'] ?? 'Een naaste';

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

      await FirebaseFirestore.instance.collection('momenten').add({
        'familieUid': user.uid,
        'vanNaam': familieNaam,
        'vanApparaatId': _mijnApparaatId,
        'vanApparaatModus':
            DeviceModusService.notifier.value ?? 'familie',
        'aanApparaatId': _gekozenApparaatId,  // null = iedereen in kring
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
      if (mounted) setState(() => _bezig = false);
    }
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
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(color: kWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kPeachLight, width: 2)),
        child: Row(children: [
          const Text('👥', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(child: DropdownButton<String?>(
            value: _gekozenApparaatId,
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
              ...leden.map((l) {
                final isOntv = l['modus'] == 'ontvanger';
                final label = isOntv
                    ? '${l['persoonsNaam']} (ontvanger)'
                    : l['persoonsNaam'] as String;
                return DropdownMenuItem<String?>(
                  value: l['apparaatId'] as String,
                  child: Text(label, style: const TextStyle(
                      color: kBrown, fontWeight: FontWeight.w700)),
                );
              }),
            ],
            onChanged: (val) => setState(() {
              _gekozenApparaatId = val;
              if (val == null) {
                _gekozenPersoonsNaam = null;
              } else {
                final geko = leden.firstWhere(
                    (l) => l['apparaatId'] == val,
                    orElse: () => <String, dynamic>{});
                _gekozenPersoonsNaam = geko['persoonsNaam'] as String?;
              }
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
          const _SectieTitel('🔁 ELKE DAG'),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('dagelijkse_momenten')
                .where('familieUid', isEqualTo: uid)
                .where('actief', isEqualTo: true).snapshots(),
            builder: (ctx, snap) {
              if (!snap.hasData) return const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator(color: kPeach)));
              final docs = snap.data!.docs.toList();
              if (docs.isEmpty) return _leeg('Nog geen dagelijkse momenten');
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
          ),
          const SizedBox(height: 20),
          const _SectieTitel('📅 GEPLAND'),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('momenten')
                .where('familieUid', isEqualTo: uid)
                .where('gezien', isEqualTo: false).snapshots(),
            builder: (ctx, snap) {
              if (!snap.hasData) return const SizedBox();
              final nu = DateTime.now();
              final docs = snap.data!.docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                if (data['testModus'] == true) return false;
                final geplandOp = (data['geplandOp'] as Timestamp?)?.toDate();
                return geplandOp != null && geplandOp.isAfter(nu);
              }).toList();
              if (docs.isEmpty) return _leeg('Geen geplande momenten');
              docs.sort((a, b) {
                final ta = (a.data() as Map)['geplandOp'] as Timestamp?;
                final tb = (b.data() as Map)['geplandOp'] as Timestamp?;
                if (ta == null || tb == null) return 0;
                return ta.compareTo(tb);
              });
              return Column(children: docs.map((d) =>
                _GeplandItem(doc: d)).toList());
            },
          ),
          const SizedBox(height: 20),
          const _SectieTitel('✓ VERSTUURD'),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('momenten')
                .where('familieUid', isEqualTo: uid)
                .where('gezien', isEqualTo: true).snapshots(),
            builder: (ctx, snap) {
              if (!snap.hasData) return const SizedBox();
              final docs = snap.data!.docs.toList();
              if (docs.isEmpty) return _leeg('Nog geen verstuurde momenten');
              return Column(children: docs.take(5).map((d) =>
                _GeplandItem(doc: d, isHistorie: true)).toList());
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
          const Text('Elke dag', style: TextStyle(fontSize: 11,
              color: kTextMuted)),
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
      default: return '⭐';
    }
  }
  String _labelVoorType(String type) {
    switch (type) {
      case 'foto': return 'Foto bericht';
      case 'stem': return 'Stem bericht';
      case 'lied': return 'Liedje';
      case 'tekst': return 'Tekst bericht';
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

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirebaseFirestore.instance.collection('gebruikers').doc(uid).get()
          .then((doc) {
        if (!mounted) return;
        setState(() {
          _ontvangerNaam =
              (doc.data()?['ontvangerNaam'] as String?) ?? 'je dierbare';
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Padding(padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Notities',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
                color: kBrown)),
        const SizedBox(height: 8),
        const Text('Deel observaties met andere kringleden en mantelzorgers',
            style: TextStyle(fontSize: 13, color: kTextMuted)),
        const SizedBox(height: 16),
        TextField(controller: _ctrl, maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Bijv. "Vandaag genoot moeder erg van de muziek"',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            filled: true, fillColor: kWhite)),
        const SizedBox(height: 10),
        GestureDetector(onTap: () => _opslaan(uid),
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
        Expanded(child: uid == null ? const SizedBox()
          : StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('notities')
              .where('familieUid', isEqualTo: uid).snapshots(),
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
                return Container(margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: kWhite,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kPeachLight, width: 1.5)),
                  child: Text(d['tekst'] ?? '',
                      style: const TextStyle(fontSize: 13,
                          color: kBrown, height: 1.4)));
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
              'Notities zijn alleen zichtbaar voor familieleden en '
              'mantelzorgers. ${_ontvangerNaam ?? "je dierbare"} ziet deze niet.',
              style: const TextStyle(fontSize: 11,
                  color: kBrownLight, height: 1.4))),
          ]),
        ),
      ]),
    );
  }

  Future<void> _opslaan(String? uid) async {
    if (uid == null || _ctrl.text.trim().isEmpty) return;
    final familieDoc = await FirebaseFirestore.instance
        .collection('gebruikers').doc(uid).get();
    final familieNaam = familieDoc.data()?['familieNaam'] ?? 'Kringlid';
    await FirebaseFirestore.instance.collection('notities').add({
      'familieUid': uid,
      'vanNaam': familieNaam,
      'tekst': _ctrl.text.trim(),
      'aangemaaktOp': FieldValue.serverTimestamp(),
    });
    _ctrl.clear();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notitie opgeslagen'),
            backgroundColor: kGreen));
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
        _ontvangerNaam =
            (doc.data()?['ontvangerNaam'] as String?) ?? 'je dierbare';
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
    final naam = _ontvangerNaam ?? 'je dierbare';
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
            'Alle berichten die je dierbare heeft gestuurd', () {
          Navigator.push(context, MaterialPageRoute(
              builder: (c) => const OntvangenBerichtenScherm()));
        }),
        if (_isAccountMaker && !widget.alsOntvanger)
          _item('🔄', 'Wijzig modus van $naam',
              'Vergrendeld of meldings — op afstand',
              () => _toonModusDialog(context, naam)),
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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kPeach,
        onPressed: () => _opnenDialog(context, uid),
        icon: const Icon(Icons.add_rounded, color: kWhite),
        label: const Text('Nieuw moment',
            style: TextStyle(color: kWhite, fontWeight: FontWeight.w800))),
      body: uid == null ? const SizedBox()
        : StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('dagelijkse_momenten')
            .where('familieUid', isEqualTo: uid)
            .where('actief', isEqualTo: true).snapshots(),
        builder: (ctx, snap) {
          if (!snap.hasData) return const Center(
              child: CircularProgressIndicator(color: kPeach));
          final docs = snap.data!.docs.toList();
          if (docs.isEmpty) return const Center(child: Padding(
            padding: EdgeInsets.all(40),
            child: Column(mainAxisAlignment: MainAxisAlignment.center,
              children: [
              Text('📅', style: TextStyle(fontSize: 56)),
              SizedBox(height: 12),
              Text('Geen dagelijkse momenten', style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: kBrown)),
              SizedBox(height: 6),
              Text('Tik op "Nieuw moment" om er een toe te voegen',
                  style: TextStyle(fontSize: 13, color: kTextMuted)),
            ])));
          docs.sort((a, b) {
            final ua = (a.data() as Map)['uur'] ?? 0;
            final ub = (b.data() as Map)['uur'] ?? 0;
            if (ua != ub) return (ua as int).compareTo(ub as int);
            return ((a.data() as Map)['minuut'] as int)
                .compareTo((b.data() as Map)['minuut'] as int);
          });
          return ListView(padding: const EdgeInsets.all(20),
            children: docs.map((doc) {
              final d = doc.data() as Map<String, dynamic>;
              return GestureDetector(
                onTap: () => _opnenDialog(context, uid, bestaand: doc),
                child: Container(margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: kWhite,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: kPeachLight, width: 2)),
                  child: Row(children: [
                    Text(d['emoji'] ?? '⭐',
                        style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Text(d['label'] ?? 'Moment', style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800,
                          color: kBrown)),
                      Text('${(d['uur'] ?? 0).toString().padLeft(2, '0')}:${(d['minuut'] ?? 0).toString().padLeft(2, '0')} elke dag',
                          style: const TextStyle(fontSize: 12, color: kTextMuted)),
                    ])),
                    IconButton(icon: const Icon(Icons.delete_outline_rounded,
                        color: Colors.red),
                      onPressed: () => doc.reference.update({'actief': false})),
                  ]),
                ),
              );
            }).toList());
        },
      ),
    );
  }

  Future<void> _opnenDialog(BuildContext context, String? uid,
      {QueryDocumentSnapshot? bestaand}) async {
    if (uid == null) return;
    final initial = bestaand?.data() as Map<String, dynamic>?;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _NieuwMomentDialog(initial: initial));
    if (result == null) return;
    if (bestaand != null) {
      await bestaand.reference.update({
        'emoji': result['emoji'],
        'label': result['label'],
        'uur': result['uur'],
        'minuut': result['minuut'],
      });
    } else {
      await FirebaseFirestore.instance.collection('dagelijkse_momenten').add({
        'familieUid': uid,
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
}

class _NieuwMomentDialog extends StatefulWidget {
  final Map<String, dynamic>? initial;
  const _NieuwMomentDialog({this.initial});
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
    _FAQ('Hoe stuur ik direct iets naar de ontvanger?',
        'Ga naar Sturen, zorg dat Test-modus AAN staat (blauwe banner). Kies '
        'type, voeg media toe, klik "Stuur NU". Het verschijnt binnen enkele '
        'seconden op het ontvanger-apparaat.'),
    _FAQ('Wat is het verschil tussen Kring- en Ontvanger-modus?',
        'Beide gebruiken hetzelfde account. Kring-modus = je kunt sturen, '
        'plannen en beheren. Ontvanger-modus = kiosk-weergave met klok, '
        'achtergrondfoto en automatische popups.'),
    _FAQ('Hoe stel ik een ander apparaat in als ontvanger?',
        'Open de app op het andere apparaat. Kies "Ontvanger". Log in met '
        'jullie gezamenlijke gegevens. Dat apparaat blijft dan altijd in '
        'kiosk-modus.'),
    _FAQ('Kunnen meerdere kringleden hetzelfde account gebruiken?',
        'Ja! Tot 8 personen kunnen tegelijk inloggen op hun eigen telefoon, '
        'allemaal met dezelfde inloggegevens. Iedereen ziet en stuurt vanuit '
        'het gezamenlijke profiel.'),
    _FAQ('Hoe neem ik een stem-bericht op?',
        'Kies "🎙️ Stem". Tik op de microfoon-knop. Spreek je bericht in. '
        'Tik nogmaals om te stoppen. Beluister voorbeeld. Klik Stuur.'),
    _FAQ('Wat zijn dagelijkse momenten?',
        'Vaste tijden waarop er automatisch iets verschijnt. Beheer ze in '
        'Instellingen → Momenten beheren.'),
    _FAQ('Wat kost Ons Moment?',
        'Eerste 5 dagen gratis. Daarna €7,99 per maand voor de hele kring.'),
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
            itemBuilder: (c, i) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: kWhite,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kPeachLight, width: 1.5)),
              child: Theme(data: ThemeData(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  title: Text(_faqs[i].vraag, style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800, color: kBrown)),
                  iconColor: kPeach, collapsedIconColor: kTextMuted,
                  children: [
                    Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text(_faqs[i].antwoord, style: const TextStyle(
                          fontSize: 13, color: kBrownLight, height: 1.5))),
                  ]))))),
        ]),
      ),
    );
  }
}

class _FAQ {
  final String vraag, antwoord;
  const _FAQ(this.vraag, this.antwoord);
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

  @override
  void initState() {
    super.initState();
    _laad();
  }

  Future<void> _laad() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final naamDoc = await FirebaseFirestore.instance
          .collection('gebruikers').doc(uid).get();
      final leden = await ApparaatService.kringLeden(uid);
      if (!mounted) return;
      setState(() {
        _ontvangerNaam = (naamDoc.data()?['ontvangerNaam'] as String?)
                         ?? 'je dierbare';
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
          : (_ontvangerApparaatIds == null
              ? const Center(child: CircularProgressIndicator(color: kPeach))
              : (_ontvangerApparaatIds!.isEmpty
                  ? _leeg('Er is nog geen ontvanger-apparaat in deze kring')
                  : StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('momenten')
                          .where('familieUid', isEqualTo: uid)
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
      default: return '💕';
    }
  }

  String _label(String type) {
    switch (type) {
      case 'foto': return 'Foto';
      case 'stem': return 'Stem-bericht';
      case 'lied': return 'Liedje';
      case 'tekst': return 'Tekst';
      default: return 'Bericht';
    }
  }

  String _formatTijd(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}-'
      '${t.month.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}
