import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

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
// STUUR TAB — Werkt echt nu
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
  bool _testModus = false;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Stuur een moment',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
                color: kBrown)),
        const SizedBox(height: 8),
        const Text('Kies één type media. Eén ding tegelijk werkt het best.',
            style: TextStyle(fontSize: 13, color: kTextMuted, height: 1.4)),
        const SizedBox(height: 16),
        // TEST KNOP
        GestureDetector(
          onTap: () => setState(() => _testModus = !_testModus),
          child: Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _testModus ? kBlue.withOpacity(0.15) : kPeachPale,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _testModus ? kBlue : kPeachLight,
                  width: 1.5)),
            child: Row(children: [
              Icon(_testModus ? Icons.bolt_rounded : Icons.timer_rounded,
                  color: _testModus ? kBlue : kTextMuted, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(_testModus
                  ? 'TEST-MODUS AAN — verschijnt direct bij ontvanger'
                  : 'Test-modus uit — wordt op ingesteld tijdstip verstuurd',
                  style: TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _testModus ? kBlue : kTextMuted))),
            ])),
        ),
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
            controller: _berichtCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: _type == 'tekst' ? 'Bericht' : 'Optioneel bijschrift',
              hintText: _type == 'tekst' ? 'Wat wil je zeggen?'
                  : 'Bijv. "Een leuke foto van de kleinkinderen!"',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              filled: true, fillColor: kWhite,
            ),
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
                ? const CircularProgressIndicator(color: kWhite)
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
    return GestureDetector(
      onTap: _kiesMedia,
      child: Container(padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: kPeachPale,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kPeachLight, width: 2)),
        child: Center(child: Column(children: [
          if (_mediaBytes != null && _type == 'foto') ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(_mediaBytes!, height: 120, fit: BoxFit.cover),
          ) else Icon(_type == 'foto' ? Icons.add_photo_alternate_rounded
              : _type == 'stem' ? Icons.mic_rounded
              : Icons.audiotrack_rounded, size: 40, color: kPeach),
          const SizedBox(height: 8),
          Text(_mediaNaam.isNotEmpty ? '✓ $_mediaNaam'
              : _type == 'foto' ? 'Tik om foto te kiezen'
              : _type == 'stem' ? 'Tik om stem-bericht te kiezen (MP3/M4A)'
              : 'Tik om MP3 lied te kiezen',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w700, color: kBrown)),
        ])),
      ),
    );
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
      _toonFout('Typ eerst een bericht');
      return;
    }
    if (_type != 'tekst' && _mediaBytes == null) {
      _toonFout('Kies eerst een bestand');
      return;
    }
    setState(() => _bezig = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final familieDoc = await FirebaseFirestore.instance
          .collection('gebruikers').doc(uid).get();
      final ontvangerUid = familieDoc.data()?['ontvangerUid'] ?? '';
      if (ontvangerUid.isEmpty) {
        _toonFout('Geen ontvanger gevonden. Maak setup opnieuw.');
        return;
      }
      String mediaUrl = '';
      if (_mediaBytes != null) {
        final ext = _type == 'foto' ? 'jpg' : 'mp3';
        final ref = FirebaseStorage.instance.ref()
            .child('momenten').child('${DateTime.now().millisecondsSinceEpoch}.$ext');
        await ref.putData(_mediaBytes!, SettableMetadata(
            contentType: _type == 'foto' ? 'image/jpeg' : 'audio/mpeg'));
        mediaUrl = await ref.getDownloadURL();
      }
      final geplandTijd = _testModus ? DateTime.now() : DateTime(
          _datum.year, _datum.month, _datum.day, _tijd.hour, _tijd.minute);
      await FirebaseFirestore.instance.collection('momenten').add({
        'naarUid': ontvangerUid,
        'vanUid': uid,
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
              ? '⚡ Direct verstuurd! Check ontvanger-scherm'
              : 'Moment gepland voor ${_formatDatum(_datum)} ${_formatTijd(_tijd)} 💕'),
          backgroundColor: kGreen));
        setState(() {
          _type = '';
          _berichtCtrl.clear();
          _mediaBytes = null;
          _mediaNaam = '';
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
// AGENDA TAB - dagelijkse + geplande momenten
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
          // Dagelijkse momenten
          const _SectieTitel('🔁 ELKE DAG'),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('dagelijkse_momenten')
                .where('vanUid', isEqualTo: uid)
                .where('actief', isEqualTo: true)
                .snapshots(),
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
          // Geplande eenmalige
          const _SectieTitel('📅 GEPLAND'),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('momenten')
                .where('vanUid', isEqualTo: uid)
                .where('gezien', isEqualTo: false)
                .snapshots(),
            builder: (ctx, snap) {
              if (!snap.hasData) return const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator(color: kPeach)));
              final docs = snap.data!.docs.where((d) {
                final geplandOp = (d.data() as Map)['geplandOp'];
                if (geplandOp == null) return true;
                return (geplandOp as Timestamp).toDate().isAfter(
                    DateTime.now().subtract(const Duration(minutes: 5)));
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
          // Verstuurd / gezien
          const _SectieTitel('✓ VERSTUURD'),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('momenten')
                .where('vanUid', isEqualTo: uid)
                .where('gezien', isEqualTo: true)
                .snapshots(),
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
        fontWeight: FontWeight.w800, color: kTextMuted, letterSpacing: 0.8)),
  );
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
          Text(d['label'] ?? 'Moment',
              style: const TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w800, color: kBrown)),
          Text('Elke dag', style: const TextStyle(fontSize: 11,
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
        TextField(
          controller: _ctrl, maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Bijv. "Vandaag genoot moeder erg van de muziek"',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            filled: true, fillColor: kWhite),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => _opslaan(uid),
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
              .where('vanUid', isEqualTo: uid).snapshots(),
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
    await FirebaseFirestore.instance.collection('notities').add({
      'vanUid': uid, 'tekst': _ctrl.text.trim(),
      'aangemaaktOp': FieldValue.serverTimestamp(),
    });
    _ctrl.clear();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notitie opgeslagen'),
            backgroundColor: kGreen));
  }
}

// ════════════════════════════════════════════════════════════
// INSTELLINGEN TAB - werkt nu echt
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
        _item('👵', 'Ontvanger-info',
            'Pas naam en profielfoto aan', () {
          Navigator.push(context, MaterialPageRoute(
              builder: (c) => const OntvangerInfoScherm()));
        }),
        _item('👨‍👩‍👧', 'Familieleden uitnodigen',
            'Tot 8 personen — binnenkort beschikbaar', () {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Binnenkort beschikbaar')));
        }),
        _item('💳', 'Abonnement',
            '€7,99/maand — 5 dagen gratis proef', () {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Binnenkort beschikbaar')));
        }),
        const SizedBox(height: 20),
        _sectie('OVERIG'),
        _item('❓', 'Hulp en uitleg', 'Veelgestelde vragen', () {
          showModalBottomSheet(context: context,
              backgroundColor: Colors.transparent, isScrollControlled: true,
              builder: (ctx) => _HulpDialog());
        }),
        _item('🚪', 'Uitloggen', '', () async {
          await FirebaseAuth.instance.signOut();
        }),
        const SizedBox(height: 30),
        const Center(child: Text('Ons Moment v5',
            style: TextStyle(fontSize: 11, color: kTextMuted))),
      ]),
    );
  }

  Widget _sectie(String t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(t, style: const TextStyle(fontSize: 11,
        fontWeight: FontWeight.w800, color: kTextMuted, letterSpacing: 0.8)),
  );

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
// MOMENTEN BEHEREN SCHERM
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
        title: const Text('Momenten beheren', style: TextStyle(
            color: kBrown, fontWeight: FontWeight.w900))),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kPeach,
        onPressed: () => _voegToe(context, uid),
        icon: const Icon(Icons.add_rounded, color: kWhite),
        label: const Text('Nieuw moment',
            style: TextStyle(color: kWhite, fontWeight: FontWeight.w800)),
      ),
      body: uid == null ? const SizedBox()
        : StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('dagelijkse_momenten')
            .where('vanUid', isEqualTo: uid)
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
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Colors.red),
                    onPressed: () => doc.reference.update({'actief': false}),
                  ),
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
      final familieDoc = await FirebaseFirestore.instance
          .collection('gebruikers').doc(uid).get();
      final ontvangerUid = familieDoc.data()?['ontvangerUid'] ?? '';
      await FirebaseFirestore.instance.collection('dagelijkse_momenten').add({
        'naarUid': ontvangerUid,
        'vanUid': uid,
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
              child: const Text('Annuleren', style: TextStyle(color: kTextMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kPeach),
              onPressed: () {
                if (_labelCtrl.text.trim().isEmpty) return;
                Navigator.pop(context, {
                  'emoji': _emoji, 'label': _labelCtrl.text.trim(),
                  'uur': _tijd.hour, 'minuut': _tijd.minute,
                });
              },
              child: const Text('Toevoegen', style: TextStyle(color: kWhite,
                  fontWeight: FontWeight.w800))),
          ]),
        ])));
  }
}

// ════════════════════════════════════════════════════════════
// ONTVANGER INFO SCHERM
// ════════════════════════════════════════════════════════════
class OntvangerInfoScherm extends StatefulWidget {
  const OntvangerInfoScherm({super.key});
  @override
  State<OntvangerInfoScherm> createState() => _OntvangerInfoSchermState();
}

class _OntvangerInfoSchermState extends State<OntvangerInfoScherm> {
  final _naamCtrl = TextEditingController();
  Uint8List? _fotoBytes;
  String _huidigeFotoUrl = '';
  bool _bezig = false;
  String _ontvangerUid = '';

  @override
  void initState() {
    super.initState();
    _laad();
  }

  Future<void> _laad() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('gebruikers').doc(uid).get();
    final d = doc.data() ?? {};
    setState(() {
      _naamCtrl.text = d['ontvangerNaam'] ?? '';
      _huidigeFotoUrl = d['ontvangerProfielFoto'] ?? '';
      _ontvangerUid = d['ontvangerUid'] ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0,
        iconTheme: const IconThemeData(color: kBrown),
        title: const Text('Ontvanger-info',
            style: TextStyle(color: kBrown, fontWeight: FontWeight.w900))),
      body: Padding(padding: const EdgeInsets.all(20),
        child: Column(children: [
          GestureDetector(
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
          ),
          const SizedBox(height: 8),
          const Text('Tik om profielfoto te wijzigen',
              style: TextStyle(fontSize: 11, color: kTextMuted)),
          const SizedBox(height: 24),
          Container(decoration: BoxDecoration(color: kWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kPeachLight, width: 2)),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(controller: _naamCtrl,
                decoration: const InputDecoration(
                  labelText: 'Naam ontvanger', border: InputBorder.none)))),
          const SizedBox(height: 30),
          GestureDetector(onTap: _bezig ? null : _opslaan,
            child: Container(width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [kPeach, kRose]),
                borderRadius: BorderRadius.circular(16)),
              child: Center(child: _bezig
                ? const CircularProgressIndicator(color: kWhite)
                : const Text('Opslaan',
                    style: TextStyle(fontSize: 16, color: kWhite,
                        fontWeight: FontWeight.w800))))),
        ])),
    );
  }

  Future<void> _kiesFoto() async {
    final picker = ImagePicker();
    final foto = await picker.pickImage(source: ImageSource.gallery,
        maxWidth: 800, imageQuality: 85);
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
            .child('profielfotos').child('${_ontvangerUid}.jpg');
        await ref.putData(_fotoBytes!, SettableMetadata(contentType: 'image/jpeg'));
        fotoUrl = await ref.getDownloadURL();
      }
      await FirebaseFirestore.instance.collection('gebruikers').doc(uid).update({
        'ontvangerNaam': _naamCtrl.text.trim(),
        'ontvangerProfielFoto': fotoUrl,
      });
      if (_ontvangerUid.isNotEmpty) {
        await FirebaseFirestore.instance.collection('gebruikers')
            .doc(_ontvangerUid).update({
          'naam': _naamCtrl.text.trim(),
          'profielFoto': fotoUrl,
        });
      }
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
    _FAQ('Hoe stuur ik een moment direct?',
        'Ga naar Sturen, klik op "Test-modus" knop bovenaan om hem AAN te '
        'zetten. Kies type, kies bestand, klik "Stuur NU". Het verschijnt '
        'direct bij de ontvanger.'),
    _FAQ('Hoe stuur ik een gepland moment?',
        'Zet Test-modus UIT. Kies type, bestand, datum en tijd. Klik '
        '"Plan en stuur". Het verschijnt automatisch op die datum/tijd.'),
    _FAQ('Wat zijn dagelijkse momenten?',
        'Vaste tijdstippen waarop er automatisch iets verschijnt — bv. elke '
        'ochtend om 08:30 "Goedemorgen". Beheer ze in Instellingen → '
        'Momenten beheren.'),
    _FAQ('Hoe verander ik de profielfoto van de ontvanger?',
        'Instellingen → Ontvanger-info. Tik op de cirkel om een nieuwe '
        'foto te kiezen. Klik Opslaan.'),
    _FAQ('Werkt het op telefoon en tablet?',
        'Ja, beide. De ontvanger kan een telefoon, tablet of oude smartphone '
        'gebruiken. Apparaat moet aan blijven en aangesloten op stroom.'),
    _FAQ('Hoe gebruikt de ontvanger de app?',
        'Open de app op zijn/haar apparaat, log in met de speciale ontvanger-'
        'gegevens. De app blijft altijd open en speelt momenten automatisch af.'),
    _FAQ('Wat kost Ons Moment?',
        'Eerste 5 dagen gratis. Daarna €7,99 per maand voor het hele gezin '
        '(tot 8 personen).'),
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
