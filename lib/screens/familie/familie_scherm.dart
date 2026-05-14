import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/moment.dart';
import '../../services/moment_service.dart';
import '../../services/media_service.dart';
import '../../services/auth_service.dart';

const Color kPeach      = Color(0xFFFF9B71);
const Color kPeachLight = Color(0xFFFFD4C2);
const Color kPeachPale  = Color(0xFFFFF0EA);
const Color kRose       = Color(0xFFFF7B9C);
const Color kCream      = Color(0xFFFFFAF7);
const Color kBrown      = Color(0xFF5C3D2E);
const Color kTextMuted  = Color(0xFF9B7565);
const Color kWhite      = Color(0xFFFFFFFF);
const Color kGreen      = Color(0xFF4CAF82);

// ════════════════════════════════════════════════════════════
// FAMILIE SCHERM — Sara's portaal
// ─ Stuurt berichten naar Jan
// ─ Ziet status (afgespeeld of niet)
// ─ Plant tijdstip en herhaling
// ════════════════════════════════════════════════════════════
class FamilieScherm extends StatefulWidget {
  const FamilieScherm({super.key});
  @override
  State<FamilieScherm> createState() => _FamilieSchermState();
}

class _FamilieSchermState extends State<FamilieScherm> {
  final _momentService = MomentService();
  final _mediaService = MediaService();
  final _authService = AuthService();
  int _tab = 0; // 0=Sturen, 1=Overzicht

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
            icon: const Icon(Icons.logout, color: kTextMuted),
            onPressed: () async {
              await _authService.uitloggen();
            },
          ),
        ],
      ),
      body: _tab == 0 ? const _StuurTab() : const _OverzichtTab(),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: kWhite,
            boxShadow: [BoxShadow(color: kBrown.withOpacity(0.08),
                blurRadius: 16)]),
        child: Row(children: [
          _navItem(0, Icons.send_rounded, 'Sturen'),
          _navItem(1, Icons.history_rounded, 'Overzicht'),
        ]),
      ),
    );
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
            Icon(icon, color: sel ? kPeach : kTextMuted),
            Text(label, style: TextStyle(fontSize: 11,
                fontWeight: FontWeight.w800,
                color: sel ? kPeach : kTextMuted)),
          ]),
        ),
      ),
    );
  }
}

// ─── STUREN TAB ─────────────────────────────────────────────
class _StuurTab extends StatefulWidget {
  const _StuurTab();
  @override
  State<_StuurTab> createState() => _StuurTabState();
}

class _StuurTabState extends State<_StuurTab> {
  final _momentService = MomentService();
  final _mediaService = MediaService();

  int _type = 0; // 0=audio, 1=foto, 2=video, 3=muziek
  TimeOfDay _tijdstip = const TimeOfDay(hour: 9, minute: 0);
  bool _herhalen = false;
  bool _neemtOp = false;
  bool _bezig = false;
  File? _gekozenBestand;
  String? _opnamePad;
  final _berichtCtrl = TextEditingController();

  final _typen = [
    {'icon': '🎙️', 'naam': 'Stemberichtje', 'sub': 'Neem je stem op'},
    {'icon': '📸', 'naam': 'Foto',           'sub': 'Kies een foto'},
    {'icon': '🎬', 'naam': 'Filmpje',        'sub': 'Max 1 minuut'},
    {'icon': '🎵', 'naam': 'Muziek',         'sub': 'Favoriet liedje'},
  ];

  // Tabletgebruiker ophalen (Jan)
  Future<Map<String, dynamic>?> _getTabletProfiel() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final doc = await FirebaseFirestore.instance
        .collection('gebruikers').doc(uid).get();
    final tabletUid = doc.data()?['tabletUid'];
    if (tabletUid == null) return null;
    final tablet = await FirebaseFirestore.instance
        .collection('gebruikers').doc(tabletUid).get();
    return {'uid': tabletUid, ...?tablet.data()};
  }

  Future<void> _kiesBestand() async {
    if (_type == 1) {
      final f = await _mediaService.kiesFoto();
      setState(() => _gekozenBestand = f);
    } else if (_type == 2) {
      final f = await _mediaService.kiesVideo();
      setState(() => _gekozenBestand = f);
    }
  }

  Future<void> _startStopOpname() async {
    if (!_neemtOp) {
      await _mediaService.startOpname();
      setState(() => _neemtOp = true);
    } else {
      final pad = await _mediaService.stopOpname();
      setState(() { _neemtOp = false; _opnamePad = pad; });
    }
  }

  Future<void> _verstuur() async {
    setState(() => _bezig = true);
    try {
      final profiel = await _getTabletProfiel();
      if (profiel == null) {
        _toonFout('Geen tablet gekoppeld. Vraag de beheerder.');
        return;
      }
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final naam = (await FirebaseFirestore.instance
          .collection('gebruikers').doc(uid).get())
          .data()?['naam'] ?? 'Familie';

      String mediaUrl = '';
      final typeString = ['audio','foto','video','muziek'][_type];

      // Upload media
      if (_type == 0 && _opnamePad != null) {
        mediaUrl = await _mediaService.uploadMedia(
            File(_opnamePad!), 'audio', uid);
      } else if ((_type == 1 || _type == 2) && _gekozenBestand != null) {
        mediaUrl = await _mediaService.uploadMedia(
            _gekozenBestand!, typeString, uid);
      }

      if (mediaUrl.isEmpty && _type != 3) {
        _toonFout('Kies eerst een bestand of neem iets op.');
        return;
      }

      // Bepaal exact tijdstip vandaag of morgen
      final nu = DateTime.now();
      var gepland = DateTime(nu.year, nu.month, nu.day,
          _tijdstip.hour, _tijdstip.minute);
      if (gepland.isBefore(nu)) {
        gepland = gepland.add(const Duration(days: 1));
      }

      final moment = Moment(
        id: '', vanUid: uid, vanNaam: naam,
        naarUid: profiel['uid'], type: typeString,
        mediaUrl: mediaUrl,
        bericht: _berichtCtrl.text.isNotEmpty ? _berichtCtrl.text : null,
        geplandOp: gepland, herhalen: _herhalen,
      );

      await _momentService.momentPlannen(moment);

      if (mounted) {
        _toonSucces('Verstuurd! ${profiel['naam']} hoort het om '
            '${_tijdstip.format(context)} 💕');
        _berichtCtrl.clear();
        setState(() { _gekozenBestand = null; _opnamePad = null; });
      }
    } finally {
      if (mounted) setState(() => _bezig = false);
    }
  }

  void _toonFout(String bericht) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(bericht), backgroundColor: Colors.red));
  }

  void _toonSucces(String bericht) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(bericht), backgroundColor: kGreen,
      duration: const Duration(seconds: 4)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _getTabletProfiel(),
      builder: (context, snap) {
        final ontvangerNaam = snap.data?['naam'] ?? 'Jan';
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── ONTVANGER ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [kPeach, kRose],
                    begin: Alignment.centerLeft, end: Alignment.centerRight),
                borderRadius: BorderRadius.circular(20)),
              child: Row(children: [
                const Text('👴', style: TextStyle(fontSize: 32)),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ontvangerNaam, style: const TextStyle(fontSize: 18,
                      fontWeight: FontWeight.w800, color: kWhite)),
                  const Text('Tablet staat klaar',
                      style: TextStyle(fontSize: 12, color: kWhite,
                          fontWeight: FontWeight.w600)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: kWhite.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(50)),
                  child: const Text('● Online',
                      style: TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w800, color: kWhite))),
              ]),
            ),

            const SizedBox(height: 20),
            _sectionLabel('Wat stuur je?'),
            const SizedBox(height: 10),

            // ── TYPE KEUZE ──
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, crossAxisSpacing: 10,
                  mainAxisSpacing: 10, childAspectRatio: 1.6),
              itemCount: _typen.length,
              itemBuilder: (_, i) {
                final sel = _type == i;
                return GestureDetector(
                  onTap: () {
                    setState(() { _type = i; _gekozenBestand = null; _opnamePad = null; });
                    if (i == 1 || i == 2) _kiesBestand();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: sel ? kPeachPale : kWhite,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: sel ? kPeach : Colors.transparent, width: 2),
                      boxShadow: [BoxShadow(color: kBrown.withOpacity(0.07),
                          blurRadius: 10)]),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_typen[i]['icon']!,
                            style: const TextStyle(fontSize: 24)),
                        const SizedBox(height: 4),
                        Text(_typen[i]['naam']!, style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800,
                            color: kBrown)),
                        Text(_typen[i]['sub']!, style: TextStyle(
                            fontSize: 10, color: kTextMuted)),
                      ]),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // ── ACTIE GEDEELTE ──
            if (_type == 0) _opnameWidget(),
            if (_type == 1 && _gekozenBestand != null) _fotoPreview(),
            if (_type == 2 && _gekozenBestand != null) _videoPreview(),

            // ── TEKSTBERICHT ──
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(color: kWhite,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kPeachLight, width: 2)),
              child: TextField(
                controller: _berichtCtrl,
                maxLines: 2,
                style: const TextStyle(color: kBrown, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'Schrijf een berichtje (optioneel)...',
                  hintStyle: TextStyle(color: kTextMuted),
                  contentPadding: const EdgeInsets.all(16),
                  border: InputBorder.none),
              ),
            ),

            const SizedBox(height: 16),
            _sectionLabel('Wanneer verschijnt het?'),
            const SizedBox(height: 10),

            // ── TIJDSTIP & HERHALING ──
            Container(
              decoration: BoxDecoration(color: kWhite,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: kBrown.withOpacity(0.07),
                      blurRadius: 10)]),
              child: Column(children: [
                // Tijdstip kiezen
                GestureDetector(
                  onTap: () async {
                    final t = await showTimePicker(
                        context: context, initialTime: _tijdstip);
                    if (t != null) setState(() => _tijdstip = t);
                  },
                  child: _rij('⏰', 'Tijdstip',
                      _tijdstip.format(context), true),
                ),
                const Divider(height: 1, color: kPeachPale),
                // Herhaling toggle
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(children: [
                    const Text('🔁', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('Elke dag herhalen',
                        style: TextStyle(fontSize: 14,
                            fontWeight: FontWeight.w700, color: kBrown))),
                    Switch(
                      value: _herhalen,
                      onChanged: (v) => setState(() => _herhalen = v),
                      activeColor: kPeach,
                    ),
                  ]),
                ),
              ]),
            ),

            const SizedBox(height: 20),

            // ── VERSTUUR KNOP ──
            GestureDetector(
              onTap: _bezig ? null : _verstuur,
              child: Container(
                width: double.infinity, padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _bezig
                        ? [kPeachLight, kPeachLight]
                        : [kPeach, kRose]),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: _bezig ? [] : [BoxShadow(
                      color: kPeach.withOpacity(0.45),
                      blurRadius: 24, offset: const Offset(0, 8))]),
                child: Center(child: _bezig
                    ? const CircularProgressIndicator(color: kWhite)
                    : Text(
                        '${_typen[_type]['icon']} Versturen naar $ontvangerNaam',
                        style: const TextStyle(fontSize: 16,
                            fontWeight: FontWeight.w800, color: kWhite))),
              ),
            ),
            const SizedBox(height: 32),
          ]),
        );
      },
    );
  }

  Widget _opnameWidget() => GestureDetector(
    onTapDown: (_) => _startStopOpname(),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity, padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _neemtOp ? kRose.withOpacity(0.15) : kPeachPale,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: _neemtOp ? kRose : kPeachLight, width: 2)),
      child: Column(children: [
        Text(_neemtOp ? '⏹' : '🎙️',
            style: const TextStyle(fontSize: 40)),
        const SizedBox(height: 8),
        Text(_neemtOp ? 'Tik om te stoppen' : 'Tik om op te nemen',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                color: _neemtOp ? kRose : kBrown)),
        if (_opnamePad != null && !_neemtOp)
          const Text('✓ Opname klaar!',
              style: TextStyle(fontSize: 12, color: kGreen,
                  fontWeight: FontWeight.w800)),
      ]),
    ),
  );

  Widget _fotoPreview() => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: Image.file(_gekozenBestand!,
        height: 150, width: double.infinity, fit: BoxFit.cover),
  );

  Widget _videoPreview() => Container(
    height: 80, decoration: BoxDecoration(color: kPeachPale,
        borderRadius: BorderRadius.circular(16)),
    child: const Center(child: Text('🎬 Video geselecteerd',
        style: TextStyle(fontWeight: FontWeight.w700, color: kBrown))),
  );

  Widget _sectionLabel(String t) => Text(t.toUpperCase(),
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
          color: kTextMuted, letterSpacing: 0.8));

  Widget _rij(String icon, String label, String waarde, bool klikbaar) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14,
              fontWeight: FontWeight.w700, color: kBrown))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(color: kPeachPale,
                borderRadius: BorderRadius.circular(50)),
            child: Text(waarde, style: const TextStyle(fontSize: 13,
                fontWeight: FontWeight.w800, color: kPeach))),
          if (klikbaar) const SizedBox(width: 4),
          if (klikbaar) const Icon(Icons.chevron_right, color: kTextMuted),
        ]),
      );
}

// ─── OVERZICHT TAB ──────────────────────────────────────────
class _OverzichtTab extends StatelessWidget {
  const _OverzichtTab();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<List<Moment>>(
      stream: MomentService().momentenVanFamilie(uid),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(
            child: CircularProgressIndicator(color: kPeach));
        final momenten = snap.data!;
        if (momenten.isEmpty) return Center(child: Column(
          mainAxisSize: MainAxisSize.min, children: [
          const Text('💌', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text('Nog geen momenten verstuurd',
              style: TextStyle(fontSize: 16, color: kTextMuted,
                  fontWeight: FontWeight.w700)),
        ]));
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: momenten.length,
          itemBuilder: (_, i) {
            final m = momenten[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kWhite, borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: kBrown.withOpacity(0.07),
                    blurRadius: 10)]),
              child: Row(children: [
                Text(m.typeIcon, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.typeLabel, style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800, color: kBrown)),
                  Text(
                    '${m.geplandOp.day}/${m.geplandOp.month} om '
                    '${m.geplandOp.hour.toString().padLeft(2,'0')}:'
                    '${m.geplandOp.minute.toString().padLeft(2,'0')}',
                    style: TextStyle(fontSize: 12, color: kTextMuted)),
                  if (m.herhalen)
                    Text('🔁 Herhaalt dagelijks',
                        style: TextStyle(fontSize: 11, color: kPeach,
                            fontWeight: FontWeight.w700)),
                ])),
                // Status: afgespeeld of niet
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: m.afgespeeld
                        ? kGreen.withOpacity(0.15)
                        : kPeachPale,
                    borderRadius: BorderRadius.circular(50)),
                  child: Text(
                    m.afgespeeld ? '✓ Gezien' : '⏳ Gepland',
                    style: TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: m.afgespeeld ? kGreen : kPeach))),
              ]),
            );
          },
        );
      },
    );
  }
}
