import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/uitnodiging.dart';
import '../../data/kring.dart';
import '../../data/kring_membership.dart';
import '../../services/apparaat_service.dart';
import '../../services/device_modus_service.dart';
import '../../services/kring_service.dart';
import '../../services/uitnodiging_service.dart';
import '../../theme/kleuren.dart';
import '../../widgets/normaal_scaffold.dart';
import '../../main.dart' show scaffoldMessengerKey;

/// Kringleden-overzicht per ACTIEVE kring (V9 2.8-a-2).
///
/// Bron-of-truth: kringen/{actieveKringId}/leden. Toont één kaart per
/// membership met de gedenormaliseerde weergaveNaam (uit 2.8-a-1).
/// Onderaan een aparte sectie "Apparaat van je dierbare" voor de
/// eigenaar — toont ontvanger-apparaten in deze kring.
class KringledenScherm extends StatefulWidget {
  const KringledenScherm({super.key});
  @override
  State<KringledenScherm> createState() => _KringledenSchermState();
}

class _KringledenSchermState extends State<KringledenScherm> {
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return NormaalScaffold(
      backgroundColor: kCream,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0,
        iconTheme: const IconThemeData(color: kBrown),
        title: const Text('Kringleden',
            style: TextStyle(color: kBrown, fontWeight: FontWeight.w900))),
      body: uid == null ? const SizedBox()
        : Column(children: [
          // Tip-balkje + uitnodig-knop (ongewijzigd t.o.v. eerdere versie).
          Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kPeachPale,
                    borderRadius: BorderRadius.circular(12)),
                  child: const Text(
                    '💡 Deel de code met een familielid. Zij openen de '
                    'app, tikken op "Heb je een uitnodig-code?" en doen '
                    'meteen mee.',
                    style: TextStyle(fontSize: 12,
                        color: kBrownLight, height: 1.4)),
                ),
                const SizedBox(height: 12),
                _uitnodigKnop(),
              ])),
          Expanded(child: ValueListenableBuilder<String?>(
            valueListenable: DeviceModusService.actieveKringNotifier,
            builder: (ctx, kringId, _) => _ledenLijst(kringId, uid),
          )),
        ]),
    );
  }

  // ─── Leden-lijst + ontvanger-sectie ─────────────────────────────────

  Widget _ledenLijst(String? kringId, String authUid) {
    if (kringId == null || kringId.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(40),
        child: Text('Geen actieve kring — log opnieuw in.',
            style: TextStyle(fontSize: 14, color: kTextMuted))));
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('kringen').doc(kringId)
          .collection('leden').snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(
            child: CircularProgressIndicator(color: kPeach));
        final ledenDocs = snap.data!.docs;
        if (ledenDocs.isEmpty) {
          return const Center(child: Padding(padding: EdgeInsets.all(40),
            child: Text('Geen kringleden gevonden.',
                style: TextStyle(fontSize: 14, color: kTextMuted))));
        }
        final leden = ledenDocs.map(Membership.fromFirestore).toList();
        // Sorteer: eigenaar eerst, dan gasten op gejoindOp oplopend.
        leden.sort((a, b) {
          if (a.rol == AccountRol.eigenaar && b.rol != AccountRol.eigenaar) {
            return -1;
          }
          if (b.rol == AccountRol.eigenaar && a.rol != AccountRol.eigenaar) {
            return 1;
          }
          return a.gejoindOp.compareTo(b.gejoindOp);
        });
        final mijnLid = leden.cast<Membership?>().firstWhere(
            (m) => m?.userUid == authUid, orElse: () => null);
        final benIkEigenaar = mijnLid?.rol == AccountRol.eigenaar;
        // Voor de ontvanger-sectie hebben we de eigenaar-uid nodig.
        // Tonen we alleen als IK eigenaar ben, dus eigenaarUid == authUid.
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            ...leden.map((lid) => _ledenKaart(
                lid, kringId, authUid, benIkEigenaar)),
            if (benIkEigenaar) ..._ontvangerSectie(authUid, kringId),
          ]);
      },
    );
  }

  Widget _ledenKaart(Membership lid, String kringId, String authUid,
      bool benIkEigenaar) {
    final isZelf = lid.userUid == authUid;
    final naam = (lid.weergaveNaam ?? '').trim();
    final toonNaam = naam.isEmpty ? 'Kringlid' : naam;
    final initiaal = naam.isEmpty ? '?' : naam[0].toUpperCase();
    final isEigenaar = lid.rol == AccountRol.eigenaar;
    final magSelfLeave = isZelf && !isEigenaar;
    final magEigenaarVerwijderen =
        benIkEigenaar && !isZelf && !isEigenaar;
    return Container(margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kPeachLight, width: 2)),
      child: Row(children: [
        Container(width: 44, height: 44,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: kPeach),
          child: Center(child: Text(initiaal,
              style: const TextStyle(fontSize: 18,
                  fontWeight: FontWeight.w900, color: kWhite))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(toonNaam, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15,
                    fontWeight: FontWeight.w800, color: kBrown)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _chip(isEigenaar ? 'Eigenaar' : 'Gast',
                  kPeachPale, kBrown),
              if (isZelf) _chip('Dit ben jij', kGreen, kWhite),
            ]),
          ])),
        if (magSelfLeave)
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: kRood),
            icon: const Icon(Icons.exit_to_app_rounded, size: 18),
            label: const Text('Uit kring',
                style: TextStyle(fontWeight: FontWeight.w800)),
            onPressed: () => _bevestigSelfLeave(kringId, lid.userUid))
        else if (magEigenaarVerwijderen)
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: kRood),
            onPressed: () => _bevestigLidVerwijderen(
                kringId, lid.userUid, toonNaam)),
      ]),
    );
  }

  List<Widget> _ontvangerSectie(String eigenaarUid, String kringId) => [
    const SizedBox(height: 24),
    const Padding(padding: EdgeInsets.only(left: 4, bottom: 6),
      child: Text('APPARAAT VAN JE DIERBARE',
          style: TextStyle(fontSize: 11, color: kPeach,
              fontWeight: FontWeight.w900, letterSpacing: 0.8))),
    StreamBuilder<QuerySnapshot>(
      // Single-field where (auto-indexed). Modus filteren we
      // clientside om een composite index te vermijden.
      stream: FirebaseFirestore.instance
          .collection('gebruikers').doc(eigenaarUid)
          .collection('apparaten')
          .where('kringId', isEqualTo: kringId)
          .snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Padding(padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(
                    color: kPeach, strokeWidth: 2.5))));
        }
        final docs = snap.data!.docs.where((d) {
          final m = (d.data() as Map<String, dynamic>?)?['modus'] as String?;
          return m == 'ontvanger';
        }).toList();
        if (docs.isEmpty) {
          return Container(padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: kPeachPale,
                borderRadius: BorderRadius.circular(12)),
            child: const Text(
              'Nog geen apparaat ingesteld voor je dierbare. Pak de '
              'tablet of telefoon van je dierbare, kies "Ontvanger" '
              'en log in met dit account.',
              style: TextStyle(fontSize: 12,
                  color: kBrownLight, height: 1.4)));
        }
        return Column(children: docs.map((doc) {
          final d = doc.data() as Map<String, dynamic>;
          return _ontvangerKaart(d, eigenaarUid, doc.id);
        }).toList());
      }),
  ];

  Widget _ontvangerKaart(Map<String, dynamic> d, String eigenaarUid,
      String apparaatId) {
    final naam = d['persoonsNaam'] as String? ?? 'Onbekend';
    final label = d['apparaatLabel'] as String? ?? 'Apparaat';
    return Container(margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kPeachLight, width: 2)),
      child: Row(children: [
        Container(width: 44, height: 44,
          decoration: BoxDecoration(shape: BoxShape.circle,
              color: kPeachPale,
              border: Border.all(color: kPeach, width: 2)),
          child: const Center(child: Text('👵',
              style: TextStyle(fontSize: 22)))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(naam, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15,
                    fontWeight: FontWeight.w800, color: kBrown)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11,
                color: kTextMuted)),
          ])),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded, color: kRood),
          onPressed: () => _bevestigOntvangerVerwijderen(
              eigenaarUid, apparaatId, naam)),
      ]),
    );
  }

  Widget _chip(String tekst, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: bg,
        borderRadius: BorderRadius.circular(8)),
    child: Text(tekst, style: TextStyle(fontSize: 11,
        fontWeight: FontWeight.w800, color: fg)));

  // ─── Bevestig-dialogs + acties ──────────────────────────────────────

  void _bevestigSelfLeave(String kringId, String userUid) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: kCream,
      title: const Text('Uit de kring gaan?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
              color: kBrown)),
      content: const Text(
          'Je verliest dan toegang tot deze kring. Je account blijft '
          'bestaan; je kunt later met een nieuwe uitnodig-code weer '
          'lid worden.',
          style: TextStyle(fontSize: 14, color: kBrownLight, height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuleren',
                style: TextStyle(color: kTextMuted,
                    fontWeight: FontWeight.w700))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kRood,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
          onPressed: () async {
            Navigator.pop(ctx);
            final ok = await KringService.verwijderLid(
                kringId: kringId, userUid: userUid);
            if (!mounted) return;
            if (!ok) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Uit de kring gaan mislukt — probeer opnieuw.'),
                backgroundColor: kRood));
              return;
            }
            // Cached actieve kring wissen + uitloggen zodat de gast op
            // een schone state landt (RouterScherm -> SetupWizard).
            // App-niveau snackbar overleeft de pop.
            await DeviceModusService.wisActieveKring();
            await FirebaseAuth.instance.signOut();
            scaffoldMessengerKey.currentState?.showSnackBar(const SnackBar(
              content: Text('Je bent uit de kring gegaan.'),
              backgroundColor: kPeach,
              duration: Duration(seconds: 4)));
          },
          child: const Text('Ja, uit de kring',
              style: TextStyle(color: kWhite, fontWeight: FontWeight.w800))),
      ],
    ));
  }

  void _bevestigLidVerwijderen(String kringId, String userUid, String naam) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: kCream,
      title: const Text('Lid verwijderen?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
              color: kBrown)),
      content: Text('Weet je zeker dat je $naam wilt verwijderen uit de '
          'kring? Diegene verliest direct toegang.',
          style: const TextStyle(fontSize: 14, color: kBrownLight,
              height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuleren',
                style: TextStyle(color: kTextMuted,
                    fontWeight: FontWeight.w700))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kRood,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
          onPressed: () async {
            Navigator.pop(ctx);
            final ok = await KringService.verwijderLid(
                kringId: kringId, userUid: userUid);
            if (!mounted) return;
            if (!ok) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Verwijderen mislukt — probeer opnieuw.'),
                backgroundColor: kRood));
            }
            // Succes: stream-update doet de UI; geen verdere actie nodig.
          },
          child: const Text('Verwijderen',
              style: TextStyle(color: kWhite, fontWeight: FontWeight.w800))),
      ],
    ));
  }

  void _bevestigOntvangerVerwijderen(String eigenaarUid, String apparaatId,
      String naam) {
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
          style: ElevatedButton.styleFrom(backgroundColor: kRood,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
          onPressed: () async {
            Navigator.pop(ctx);
            final ok = await ApparaatService.verwijderApparaat(
                familieUid: eigenaarUid, apparaatId: apparaatId);
            if (!mounted) return;
            if (!ok) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Verwijderen mislukt — probeer opnieuw.'),
                backgroundColor: kRood));
            }
          },
          child: const Text('Verwijderen',
              style: TextStyle(color: kWhite, fontWeight: FontWeight.w800))),
      ],
    ));
  }

  // ─── Uitnodig-knop + dialog (ongewijzigd t.o.v. eerdere versie) ─────

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
}

/// Dialog die de actieve uitnodig-link en -code toont (V9 2.5-a-2).
/// Toont preview-info (kring-naam + plekken-bezet) + kopieer-knoppen
/// voor zowel de URL als de gegroepeerde code.
class _UitnodigLinkDialog extends StatelessWidget {
  final Uitnodiging uitnodiging;
  const _UitnodigLinkDialog({required this.uitnodiging});

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

            // CODE
            const Text('CODE',
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
