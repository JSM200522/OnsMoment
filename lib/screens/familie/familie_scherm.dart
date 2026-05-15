import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';

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

// ════════════════════════════════════════════════════════════
// FAMILIE SCHERM V4 — Sara's portaal
// Tabs: Sturen | Agenda | Notities | Instellingen
// ════════════════════════════════════════════════════════════
class FamilieScherm extends StatefulWidget {
  const FamilieScherm({super.key});
  @override
  State<FamilieScherm> createState() => _FamilieSchermState();
}

class _FamilieSchermState extends State<FamilieScherm> {
  final _authService = AuthService();
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
            onPressed: () => _toonHulp(context),
          ),
        ],
      ),
      body: _huidigeTab(),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: kWhite,
            boxShadow: [BoxShadow(color: kBrown.withOpacity(0.08),
                blurRadius: 16)]),
        child: SafeArea(
          child: Row(children: [
            _navItem(0, Icons.send_rounded, 'Sturen'),
            _navItem(1, Icons.calendar_today_rounded, 'Agenda'),
            _navItem(2, Icons.note_alt_rounded, 'Notities'),
            _navItem(3, Icons.settings_rounded, 'Instellingen'),
          ]),
        ),
      ),
    );
  }

  Widget _huidigeTab() {
    switch (_tab) {
      case 0: return const _StuurTab();
      case 1: return const _AgendaTab();
      case 2: return const _NotitiesTab();
      case 3: return _InstellingenTab(authService: _authService);
      default: return const SizedBox();
    }
  }

  Widget _navItem(int index, IconData icon, String label) {
    final sel = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          color: Colors.transparent,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: sel ? kPeach : kTextMuted, size: 22),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 10,
                fontWeight: FontWeight.w800,
                color: sel ? kPeach : kTextMuted)),
          ]),
        ),
      ),
    );
  }

  void _toonHulp(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _HulpDialog(),
    );
  }
}

// ════════════════════════════════════════════════════════════
// TAB 1: STUREN — moment versturen
// ════════════════════════════════════════════════════════════
class _StuurTab extends StatefulWidget {
  const _StuurTab();
  @override
  State<_StuurTab> createState() => _StuurTabState();
}

class _StuurTabState extends State<_StuurTab> {
  String _type = '';
  final _berichtCtrl = TextEditingController();
  TimeOfDay _tijd = TimeOfDay.now();
  DateTime _datum = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Stuur een moment',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
                color: kBrown)),
        const SizedBox(height: 8),
        const Text('Kies één type media. Eén ding tegelijk werkt het best.',
            style: TextStyle(fontSize: 13, color: kTextMuted, height: 1.4)),
        const SizedBox(height: 20),
        // 4 grote knoppen
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
          const SizedBox(height: 24),
          if (_type == 'tekst') TextField(
            controller: _berichtCtrl,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Bericht',
              hintText: 'Wat wil je zeggen?',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              filled: true, fillColor: kWhite,
            ),
          ),
          if (_type == 'foto' || _type == 'lied') Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: kPeachPale,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kPeachLight, width: 2)),
            child: Center(child: Column(children: [
              Icon(_type == 'foto' ? Icons.add_photo_alternate_rounded
                  : Icons.audiotrack_rounded, size: 40, color: kPeach),
              const SizedBox(height: 8),
              Text(_type == 'foto' ? 'Tik om foto te kiezen'
                  : 'Tik om lied te kiezen',
                  style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w700, color: kBrown)),
            ])),
          ),
          if (_type == 'stem') Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: kPeachPale,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kPeachLight, width: 2)),
            child: Column(children: [
              Container(width: 72, height: 72,
                decoration: const BoxDecoration(color: kRose, shape: BoxShape.circle),
                child: const Icon(Icons.mic_rounded, color: kWhite, size: 36),
              ),
              const SizedBox(height: 12),
              const Text('Houd ingedrukt om op te nemen',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                      color: kBrown)),
            ]),
          ),
          const SizedBox(height: 20),
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
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _verstuur,
            child: Container(
              width: double.infinity, padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [kPeach, kRose]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: kPeach.withOpacity(0.35),
                    blurRadius: 20, offset: const Offset(0, 8))]),
              child: const Center(child: Text('Plan en stuur 💕',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                      color: kWhite))),
            ),
          ),
        ],
      ])),
    );
  }

  Widget _typeKnop(String emoji, String label, String waarde) =>
    Expanded(child: GestureDetector(
      onTap: () => setState(() => _type = _type == waarde ? '' : waarde),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: _type == waarde ? kPeach : kWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kPeachLight, width: 2),
        ),
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

  void _verstuur() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Moment gepland! 💕'), backgroundColor: kGreen));
    setState(() {
      _type = '';
      _berichtCtrl.clear();
    });
  }
}

// ════════════════════════════════════════════════════════════
// TAB 2: AGENDA — overzicht alle geplande momenten
// ════════════════════════════════════════════════════════════
class _AgendaTab extends StatelessWidget {
  const _AgendaTab();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Center(child: Text('Niet ingelogd'));

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Agenda',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
                color: kBrown)),
        const SizedBox(height: 8),
        const Text('Alle geplande momenten voor je dierbare',
            style: TextStyle(fontSize: 13, color: kTextMuted)),
        const SizedBox(height: 20),
        Expanded(child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('dagelijkse_momenten')
              .where('vanUid', isEqualTo: uid)
              .where('actief', isEqualTo: true)
              .snapshots(),
          builder: (ctx, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator(color: kPeach));
            }
            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return _legeStatus('📅', 'Nog geen momenten gepland',
                  'Ga naar Sturen of Instellingen om momenten toe te voegen');
            }
            // Sorteer op tijd
            docs.sort((a, b) {
              final ua = (a.data() as Map)['uur'] ?? 0;
              final ub = (b.data() as Map)['uur'] ?? 0;
              if (ua != ub) return (ua as int).compareTo(ub as int);
              final ma = (a.data() as Map)['minuut'] ?? 0;
              final mb = (b.data() as Map)['minuut'] ?? 0;
              return (ma as int).compareTo(mb as int);
            });
            return ListView.builder(itemCount: docs.length,
              itemBuilder: (c, i) {
                final d = docs[i].data() as Map<String, dynamic>;
                return _agendaItem(d);
              },
            );
          },
        )),
      ]),
    );
  }

  Widget _agendaItem(Map<String, dynamic> d) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: kWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kPeachLight, width: 2)),
    child: Row(children: [
      Text(d['emoji'] ?? '⭐', style: const TextStyle(fontSize: 28)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Text(d['label'] ?? 'Moment',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                color: kBrown)),
        const SizedBox(height: 2),
        Text('Elke dag · ${d['mediaType'] ?? 'geen media'}',
            style: const TextStyle(fontSize: 12, color: kTextMuted)),
      ])),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: kPeachPale,
            borderRadius: BorderRadius.circular(10)),
        child: Text(
            '${(d['uur'] ?? 0).toString().padLeft(2, '0')}:${(d['minuut'] ?? 0).toString().padLeft(2, '0')}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                color: kBrown)),
      ),
    ]),
  );
}

Widget _legeStatus(String emoji, String titel, String tekst) =>
  Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Text(emoji, style: const TextStyle(fontSize: 48)),
    const SizedBox(height: 12),
    Text(titel, style: const TextStyle(fontSize: 16,
        fontWeight: FontWeight.w800, color: kBrown)),
    const SizedBox(height: 6),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Text(tekst, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: kTextMuted, height: 1.4))),
  ]));

// ════════════════════════════════════════════════════════════
// TAB 3: NOTITIES — gedeeld met familie/mantelzorg
// ════════════════════════════════════════════════════════════
class _NotitiesTab extends StatefulWidget {
  const _NotitiesTab();
  @override
  State<_NotitiesTab> createState() => _NotitiesTabState();
}

class _NotitiesTabState extends State<_NotitiesTab> {
  final _ctrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Notities',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
                color: kBrown)),
        const SizedBox(height: 8),
        const Text('Deel observaties met andere familie en mantelzorgers',
            style: TextStyle(fontSize: 13, color: kTextMuted)),
        const SizedBox(height: 16),
        // Nieuwe notitie maken
        TextField(
          controller: _ctrl,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Bijv. "Vandaag genoot moeder erg van de muziek"',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            filled: true, fillColor: kWhite,
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => _opslaan(uid),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
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
        Expanded(child: uid == null ? const SizedBox() : StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('notities')
              .where('vanUid', isEqualTo: uid)
              .snapshots(),
          builder: (ctx, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator(color: kPeach));
            }
            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return _legeStatus('📝', 'Nog geen notities',
                  'Begin met een eerste observatie of herinnering');
            }
            return ListView.builder(itemCount: docs.length,
              itemBuilder: (c, i) {
                final d = docs[i].data() as Map<String, dynamic>;
                return _notitieItem(d);
              },
            );
          },
        )),
      ]),
    );
  }

  Future<void> _opslaan(String? uid) async {
    if (uid == null || _ctrl.text.trim().isEmpty) return;
    await FirebaseFirestore.instance.collection('notities').add({
      'vanUid': uid,
      'tekst': _ctrl.text.trim(),
      'aangemaaktOp': FieldValue.serverTimestamp(),
    });
    _ctrl.clear();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notitie opgeslagen'),
          backgroundColor: kGreen));
  }

  Widget _notitieItem(Map<String, dynamic> d) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: kWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kPeachLight, width: 1.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(d['tekst'] ?? '',
          style: const TextStyle(fontSize: 13, color: kBrown, height: 1.4)),
    ]),
  );
}

// ════════════════════════════════════════════════════════════
// TAB 4: INSTELLINGEN
// ════════════════════════════════════════════════════════════
class _InstellingenTab extends StatelessWidget {
  final AuthService authService;
  const _InstellingenTab({required this.authService});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: ListView(children: [
        const Text('Instellingen',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
                color: kBrown)),
        const SizedBox(height: 20),
        _sectie('DAGELIJKSE MOMENTEN'),
        _item('📅', 'Momenten beheren',
            'Voeg toe, pas aan of verwijder vaste momenten', () {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Binnenkort beschikbaar — werkt al in setup')));
        }),
        const SizedBox(height: 20),
        _sectie('ACCOUNT'),
        _item('👤', 'Ontvanger-info', 'Pas naam en gegevens aan', () {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Binnenkort beschikbaar')));
        }),
        _item('👨‍👩‍👧 ', 'Familieleden uitnodigen',
            'Tot 8 personen toevoegen die berichten kunnen sturen', () {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Binnenkort beschikbaar')));
        }),
        _item('💳', 'Abonnement', '€7,99/maand — 5 dagen proef', () {
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
        _item('📜', 'Privacy & voorwaarden', '', () {}),
        _item('🚪', 'Uitloggen', '', () async {
          await authService.uitloggen();
        }),
        const SizedBox(height: 30),
        const Center(child: Text('Ons Moment v4',
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
// HULP DIALOG — eenvoudige FAQ
// ════════════════════════════════════════════════════════════
class _HulpDialog extends StatelessWidget {
  final List<_FAQ> _faqs = [
    _FAQ('Hoe stuur ik een moment?',
        'Ga naar de tab "Sturen", kies één type (foto/stem/lied/tekst), '
        'stel een tijd in en klik Plan en stuur.'),
    _FAQ('Wat is een dagelijks moment?',
        'Een vast tijdstip waarop er automatisch iets verschijnt bij de ontvanger. '
        'Bijvoorbeeld elke ochtend om 08:30 "Goedemorgen". Je kunt er optioneel '
        'media aan koppelen.'),
    _FAQ('Hoe nodig ik familie uit?',
        'Ga naar Instellingen → Familieleden uitnodigen. Tot 8 personen kunnen '
        'meedoen op één abonnement.'),
    _FAQ('Wat is het verschil tussen mij en de ontvanger?',
        'Jij (familie) stuurt berichten. De ontvanger (bv. opa/oma) ontvangt ze '
        'automatisch op zijn/haar apparaat. De ontvanger hoeft niks te doen.'),
    _FAQ('Hoe gebruikt de ontvanger de app?',
        'Open de app op het apparaat van de ontvanger en log in met de '
        'speciale ontvanger-gegevens. De app blijft dan altijd open en speelt '
        'momenten automatisch af.'),
    _FAQ('Kan ik momenten later aanpassen?',
        'Ja! Ga naar Instellingen → Momenten beheren. Alle momenten zijn '
        'volledig aanpasbaar.'),
    _FAQ('Werkt dit op telefoon of tablet?',
        'Allebei. De ontvanger kan een telefoon, tablet of een oude smartphone '
        'gebruiken. Het apparaat moet altijd aanstaan en ingeplugd.'),
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
            itemBuilder: (c, i) => _faqItem(_faqs[i]),
          )),
        ]),
      ),
    );
  }

  Widget _faqItem(_FAQ faq) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(color: kWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kPeachLight, width: 1.5)),
    child: Theme(data: ThemeData(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(faq.vraag, style: const TextStyle(fontSize: 14,
            fontWeight: FontWeight.w800, color: kBrown)),
        iconColor: kPeach, collapsedIconColor: kTextMuted,
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(faq.antwoord,
                style: const TextStyle(fontSize: 13, color: kBrownLight,
                    height: 1.5))),
        ],
      ),
    ),
  );
}

class _FAQ {
  final String vraag, antwoord;
  _FAQ(this.vraag, this.antwoord);
}
