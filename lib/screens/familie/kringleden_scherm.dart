import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/apparaat_service.dart';
import '../../services/device_modus_service.dart';
import '../../theme/kleuren.dart';

/// Overzicht van alle apparaten in de kring met verwijder-functie.
/// Permissies (OPTIE C): de account-maker (oudste apparaat) mag elk ander
/// apparaat verwijderen behalve zichzelf (anti-lockout); andere apparaten
/// mogen alleen hun eigen apparaat verwijderen.
class KringledenScherm extends StatefulWidget {
  const KringledenScherm({super.key});
  @override
  State<KringledenScherm> createState() => _KringledenSchermState();
}

class _KringledenSchermState extends State<KringledenScherm> {
  String? _mijnApparaatId;

  @override
  void initState() {
    super.initState();
    DeviceModusService.krijgApparaatId().then((id) {
      if (mounted) setState(() => _mijnApparaatId = id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: kCream,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0,
        iconTheme: const IconThemeData(color: kBrown),
        title: const Text('Kringleden',
            style: TextStyle(color: kBrown, fontWeight: FontWeight.w900))),
      body: uid == null ? const SizedBox()
        : StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('gebruikers')
            .doc(uid).collection('apparaten').snapshots(),
        builder: (ctx, snap) {
          if (!snap.hasData) return const Center(
              child: CircularProgressIndicator(color: kPeach));
          final docs = snap.data!.docs.toList();
          if (docs.isEmpty) return const Center(child: Padding(
            padding: EdgeInsets.all(40),
            child: Text('Geen apparaten in de kring',
                style: TextStyle(fontSize: 14, color: kTextMuted))));
          // Sorteer op aangemaakt oplopend; docs zonder timestamp achteraan.
          docs.sort((a, b) {
            final ta = (a.data() as Map)['aangemaakt'] as Timestamp?;
            final tb = (b.data() as Map)['aangemaakt'] as Timestamp?;
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return ta.compareTo(tb);
          });
          final beheerderId = docs.first.id;
          final isViewerAccountMaker = beheerderId == _mijnApparaatId;
          return ListView(padding: const EdgeInsets.all(20),
            children: docs.map((doc) {
              final d = doc.data() as Map<String, dynamic>;
              final isBeheerder = doc.id == beheerderId;
              final isSelf = doc.id == _mijnApparaatId;
              final magVerwijderen = _magVerwijderen(
                  isViewerAccountMaker: isViewerAccountMaker,
                  isTargetBeheerder: isBeheerder,
                  isTargetSelf: isSelf);
              return _apparaatKaart(d, isBeheerder, isSelf, magVerwijderen,
                  () => _bevestigVerwijder(uid, doc.id,
                      d['persoonsNaam'] as String? ?? 'dit apparaat'));
            }).toList());
        },
      ),
    );
  }

  bool _magVerwijderen({
    required bool isViewerAccountMaker,
    required bool isTargetBeheerder,
    required bool isTargetSelf,
  }) {
    if (isTargetBeheerder) return false;       // beheerder-apparaat beschermd
    if (isViewerAccountMaker) return true;      // beheerder mag elk ander
    return isTargetSelf;                         // anders alleen eigen apparaat
  }

  Widget _apparaatKaart(Map<String, dynamic> d, bool isBeheerder,
      bool isSelf, bool magVerwijderen, VoidCallback onVerwijder) {
    final naam = d['persoonsNaam'] as String? ?? 'Onbekend';
    final label = d['apparaatLabel'] as String? ?? 'Apparaat';
    final modus = d['modus'] as String? ?? '';
    final modusTekst = modus == 'ontvanger' ? '👵 Ontvanger'
        : modus == 'familie' ? '👨‍👩‍👧 Kringlid'
        : modus;
    return Container(margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kPeachLight, width: 2)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text(naam, style: const TextStyle(fontSize: 15,
              fontWeight: FontWeight.w800, color: kBrown)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: kTextMuted)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _chip(modusTekst, kPeachPale, kBrown),
            if (isBeheerder) _chip('⭐ Beheerder', kBlue, kWhite),
            if (isSelf) _chip('📍 Dit apparaat', kGreen, kWhite),
          ]),
        ])),
        if (magVerwijderen)
          IconButton(icon: const Icon(Icons.delete_outline_rounded,
              color: kRood),
            onPressed: onVerwijder),
      ]),
    );
  }

  Widget _chip(String tekst, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: bg,
        borderRadius: BorderRadius.circular(8)),
    child: Text(tekst, style: TextStyle(fontSize: 11,
        fontWeight: FontWeight.w800, color: fg)));

  void _bevestigVerwijder(String uid, String apparaatId, String naam) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: kCream,
      title: const Text('Apparaat verwijderen?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
              color: kBrown)),
      content: Text('Apparaat van $naam verwijderen? '
          'Het apparaat wordt direct uitgelogd.',
          style: const TextStyle(fontSize: 14, color: kBrownLight,
              height: 1.4)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuleren',
                style: TextStyle(color: kTextMuted,
                    fontWeight: FontWeight.w700))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: kRood,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
          onPressed: () async {
            Navigator.pop(ctx);
            final ok = await ApparaatService.verwijderApparaat(
                familieUid: uid, apparaatId: apparaatId);
            if (!mounted) return;
            if (!ok) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Verwijderen mislukt — probeer opnieuw'),
                backgroundColor: kRood));
            }
          },
          child: const Text('Verwijderen',
              style: TextStyle(color: kWhite, fontWeight: FontWeight.w800))),
      ],
    ));
  }
}
