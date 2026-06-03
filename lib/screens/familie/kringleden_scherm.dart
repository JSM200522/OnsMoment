import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/uitnodiging.dart';
import '../../services/apparaat_service.dart';
import '../../services/device_modus_service.dart';
import '../../services/uitnodiging_service.dart';
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
        : Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: _uitnodigKnop()),
        Expanded(child: StreamBuilder<QuerySnapshot>(
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
            return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
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
        )),
      ]),
    );
  }

  // ─── Uitnodig-link/code (V9 2.5-a-2) ───────────────────────────────

  Widget _uitnodigKnop() => GestureDetector(
    onTap: _openUitnodigDialog,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [kPeach, kRose]),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: kPeach.withOpacity(0.3),
            blurRadius: 14, offset: const Offset(0, 4))]),
      child: const Row(mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('🔗 ', style: TextStyle(fontSize: 18)),
        Flexible(child: Text('Familie uitnodigen',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15,
                fontWeight: FontWeight.w900, color: kWhite))),
      ]),
    ),
  );

  Future<void> _openUitnodigDialog() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final kringId = await DeviceModusService.huidigeKringIdMetFallback();
    if (!mounted) return;
    if (kringId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Kring niet beschikbaar — log opnieuw in.'),
        backgroundColor: kRood));
      return;
    }

    showDialog(context: context, barrierDismissible: false,
        builder: (_) => const Center(
            child: CircularProgressIndicator(color: kPeach)));

    final tokenResult = await UitnodigingService.zorgVoorToken(
        kringId: kringId, uid: uid);
    if (!mounted) return;
    if (tokenResult.token == null) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Link maken mislukt — probeer opnieuw.'),
        backgroundColor: kRood));
      return;
    }
    final valideerResult =
        await UitnodigingService.valideer(tokenResult.token!);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    final uitnodiging = valideerResult.uitnodiging;
    if (uitnodiging == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Kon de uitnodiging niet ophalen.'),
        backgroundColor: kRood));
      return;
    }
    if (!mounted) return;
    showDialog(context: context,
        builder: (_) => _UitnodigLinkDialog(uitnodiging: uitnodiging));
  }

  // ─── Apparaten-lijst (bestaand) ─────────────────────────────────────

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

/// Dialog die de actieve uitnodig-link en -code toont (V9 2.5-a-2).
/// Toont preview-info (kring-naam + plekken-bezet) + kopieer-knoppen
/// voor zowel de URL als de gegroepeerde code.
class _UitnodigLinkDialog extends StatelessWidget {
  final Uitnodiging uitnodiging;
  const _UitnodigLinkDialog({required this.uitnodiging});

  String get _link =>
      'https://jsm200522.github.io/OnsMoment/?uitnodiging=${uitnodiging.token}';

  Future<void> _kopieer(BuildContext context, String tekst,
      String bevestiging) async {
    await Clipboard.setData(ClipboardData(text: tekst));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('✓ $bevestiging'),
      backgroundColor: kGreen,
      duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final plekkenChipKleur = uitnodiging.ruimte ? kGreen : kRood;
    final plekkenChipTekst = uitnodiging.ruimte
        ? 'Plek ${uitnodiging.huidigeLeden} van ${uitnodiging.maxLeden} bezet'
        : 'Kring is vol (${uitnodiging.maxLeden} kringleden)';

    return Dialog(
      backgroundColor: kCream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('🔗 Familie uitnodigen',
                style: TextStyle(fontSize: 18,
                    fontWeight: FontWeight.w900, color: kBrown)),
            const SizedBox(height: 10),
            Text(
              'Iedereen met deze link kan lid worden van '
              '"${uitnodiging.kringNaam}". Deel de link met familieleden '
              'die mee mogen sturen.',
              style: const TextStyle(fontSize: 13,
                  color: kBrownLight, height: 1.4)),
            const SizedBox(height: 14),

            // Plekken-bezet badge
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: plekkenChipKleur,
                borderRadius: BorderRadius.circular(8)),
              child: Text(plekkenChipTekst,
                  style: const TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w800, color: kWhite,
                      letterSpacing: 0.4)),
            ),
            const SizedBox(height: 18),

            // LINK
            const Text('LINK',
                style: TextStyle(fontSize: 11, color: kTextMuted,
                    fontWeight: FontWeight.w800, letterSpacing: 0.8)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: kPeachPale,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kPeachLight, width: 1.5)),
              child: SelectableText(_link,
                  style: const TextStyle(fontSize: 12,
                      color: kBrown, fontFamily: 'monospace')),
            ),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPeach,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12)),
                onPressed: () => _kopieer(context, _link, 'Link gekopieerd'),
                icon: const Icon(Icons.copy_rounded,
                    color: kWhite, size: 18),
                label: const Text('Kopieer link',
                    style: TextStyle(color: kWhite,
                        fontWeight: FontWeight.w800))),
            ),
            const SizedBox(height: 20),

            // CODE
            const Text('OF CODE',
                style: TextStyle(fontSize: 11, color: kTextMuted,
                    fontWeight: FontWeight.w800, letterSpacing: 0.8)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: kPeachPale,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kPeachLight, width: 1.5)),
              child: Center(child: SelectableText(uitnodiging.displayToken,
                  style: const TextStyle(fontSize: 16,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w800,
                      color: kBrown, letterSpacing: 1.2))),
            ),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPeach,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12)),
                onPressed: () => _kopieer(
                    context, uitnodiging.displayToken, 'Code gekopieerd'),
                icon: const Icon(Icons.copy_rounded,
                    color: kWhite, size: 18),
                label: const Text('Kopieer code',
                    style: TextStyle(color: kWhite,
                        fontWeight: FontWeight.w800))),
            ),
            const SizedBox(height: 18),

            Center(child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Sluiten',
                  style: TextStyle(color: kTextMuted,
                      fontWeight: FontWeight.w700)))),
          ]),
        ),
      ),
    );
  }
}
