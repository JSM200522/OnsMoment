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
import '../../main.dart';
import '../../services/device_modus_service.dart';

const Color kPeach      = Color(0xFFFF9B71);
const Color kPeachLight = Color(0xFFFFD4C2);
const Color kPeachPale  = Color(0xFFFFF0EA);
const Color kRose       = Color(0xFFFF7B9C);
const Color kCream      = Color(0xFFFFFAF7);
const Color kBrown      = Color(0xFF5C3D2E);
const Color kBrownLight = Color(0xFF8B6354);
const Color kTextMuted  = Color(0xFF9B7565);
const Color kWhite      = Color(0xFFFFFFFF);
const Color kGreen      = Color(0xFF4CAF82);
const Color kBlue       = Color(0xFF4A90E2);
const Color kRood       = Color(0xFFE74C3C);

const List<Map<String, String>> kGeluiden = [
  {'id': 'twinkel', 'emoji': '✨', 'naam': 'Twinkel',
   'url': 'https://cdn.pixabay.com/audio/2022/03/24/audio_8e8e3e6f17.mp3'},
  {'id': 'bel', 'emoji': '🔔', 'naam': 'Zachte bel',
   'url': 'https://cdn.pixabay.com/audio/2022/03/15/audio_e9e98c7c8b.mp3'},
  {'id': 'vogel', 'emoji': '🐦', 'naam': 'Vogel',
   'url': 'https://cdn.pixabay.com/audio/2022/03/10/audio_cd2c1ec3fc.mp3'},
  {'id': 'piano', 'emoji': '🎹', 'naam': 'Piano',
   'url': 'https://cdn.pixabay.com/audio/2022/03/15/audio_8c0f1f4a4f.mp3'},
  {'id': 'kerkklok', 'emoji': '⛪', 'naam': 'Kerkklok',
   'url': 'https://cdn.pixabay.com/audio/2021/08/04/audio_bb630cc098.mp3'},
  {'id': 'hart', 'emoji': '💕', 'naam': 'Liefdes-melodie',
   'url': 'https://cdn.pixabay.com/audio/2022/01/18/audio_d0c6ff1eab.mp3'},
];

class FamilieScherm extends StatefulWidget {
  const FamilieScherm({super.key});
  @override
  State<FamilieScherm> createState() => _FamilieSchermState();
}

class _FamilieSchermState extends State<FamilieScherm> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
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
                builder: (ctx) => _HulpDialog()),
          ),
        ],
      ),
      body: _huidigeTab(),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: kWhite,
            boxShadow: [BoxShadow(color: kBrown.withOpacity(0.08),
                blurRadius: 16)]),
        child: SafeArea(child: Row(children: [
          _navItem(0, Icons.send_rounded, 'Sturen'),
          _navItem(1, Icons.calendar_today_rounded, 'Agenda'),
          _navItem(2, Icons.note_alt_rounded, 'Notities'),
          _navItem(3, Icons.settings_rounded, 'Instellingen'),
        ])),
      ),
    );
  }

  Widget _huidigeTab() {
    switch (_tab) {
      case 0: return const StuurTab();
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
  const StuurTab({super.key});
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
                : Text(_testModus ? '⚡ Stuur NU naar ontvanger'
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
        await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
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
      ])),
    ),
  );

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
      final familieNaam = familieData['familieNaam'] ?? 'Familie';

      String mediaUrl = '';
      if (_type == 'stem' && _opnamePad != null) {
        // Web blob URL - voor MVP direct gebruiken
        mediaUrl = _opnamePad!;
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
              final docs = snap.data!.docs.toList();
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

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Padding(padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Notities',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
                color: kBrown)),
        const SizedBox(height: 8),
        const Text('Deel observaties met andere familie en mantelzorgers',
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
            final docs = snap.data!.docs;
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
      ]),
    );
  }

  Future<void> _opslaan(String? uid) async {
    if (uid == null || _ctrl.text.trim().isEmpty) return;
    final familieDoc = await FirebaseFirestore.instance
        .collection('gebruikers').doc(uid).get();
    final familieNaam = familieDoc.data()?['familieNaam'] ?? 'Familielid';
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
class InstellingenTab extends StatelessWidget {
  const InstellingenTab({super.key});
  @override
  Widget build(BuildContext context) {
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
        _item('🔄', 'Wissel naar Ontvanger-modus',
            'Verander dit apparaat naar ontvanger-weergave', () =>
            _bevestigModusWissel(context)),
        const SizedBox(height: 20),
        _sectie('OVERIG'),
        _item('❓', 'Hulp en uitleg', 'Veelgestelde vragen', () {
          showModalBottomSheet(context: context,
              backgroundColor: Colors.transparent, isScrollControlled: true,
              builder: (ctx) => _HulpDialog());
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

  void _bevestigModusWissel(BuildContext context) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Naar Ontvanger-modus?'),
      content: const Text(
          'Dit apparaat wordt dan een kiosk-weergave voor de ontvanger. '
          'Je kunt later terugschakelen door uit te loggen en opnieuw de '
          'familie-modus te kiezen.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuleren')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kPeach),
          onPressed: () async {
            await DeviceModusService.zet(DeviceModusService.ONTVANGER);
            if (!context.mounted) return;
            Navigator.pop(ctx);
            // Forceer volledige app rebuild → router routeert nu naar TabletScherm
            OnsMomentApp.herstart(context);
          },
          child: const Text('Wissel', style: TextStyle(color: kWhite))),
      ],
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
        onPressed: () => _voegToe(context, uid),
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
              return Container(margin: const EdgeInsets.only(bottom: 10),
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
              );
            }).toList());
        },
      ),
    );
  }

  Future<void> _voegToe(BuildContext context, String? uid) async {
    if (uid == null) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context, builder: (ctx) => _NieuwMomentDialog());
    if (result != null) {
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
  @override
  State<_NieuwMomentDialog> createState() => _NieuwMomentDialogState();
}

class _NieuwMomentDialogState extends State<_NieuwMomentDialog> {
  String _emoji = '⭐';
  final _labelCtrl = TextEditingController();
  TimeOfDay _tijd = const TimeOfDay(hour: 15, minute: 0);
  final _emojis = ['⭐', '☀️', '☕', '🍽️', '🌙', '💕', '🎵', '🌸', '🌳', '📚', '🐦', '🍰'];

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
              _speelPreview(g['url']!);
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

  Future<void> _speelPreview(String url) async {
    try {
      await _geluidPreviewPlayer.stop();
      await _geluidPreviewPlayer.setUrl(url);
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
  final List<_FAQ> _faqs = [
    _FAQ('Hoe stuur ik direct iets naar de ontvanger?',
        'Ga naar Sturen, zorg dat Test-modus AAN staat (blauwe banner). Kies '
        'type, voeg media toe, klik "Stuur NU". Het verschijnt binnen enkele '
        'seconden op het ontvanger-apparaat.'),
    _FAQ('Wat is het verschil tussen Familie- en Ontvanger-modus?',
        'Beide gebruiken hetzelfde account. Familie-modus = je kunt sturen, '
        'plannen en beheren. Ontvanger-modus = kiosk-weergave met klok, '
        'achtergrondfoto en automatische popups.'),
    _FAQ('Hoe stel ik een ander apparaat in als ontvanger?',
        'Open de app op het andere apparaat. Kies "Ontvanger". Log in met '
        'jullie gezamenlijke gegevens. Dat apparaat blijft dan altijd in '
        'kiosk-modus.'),
    _FAQ('Kunnen meerdere familieleden hetzelfde account gebruiken?',
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
        'Eerste 5 dagen gratis. Daarna €7,99 per maand voor het hele gezin.'),
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
  _FAQ(this.vraag, this.antwoord);
}
