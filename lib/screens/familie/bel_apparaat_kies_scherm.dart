import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/bel_uitleg_teksten.dart';
import '../../services/apparaat_service.dart';
import '../../services/device_modus_service.dart';
import '../../theme/kleuren.dart';
import '../../widgets/normaal_scaffold.dart';
import '../videobellen/bel_uitleg_dialog.dart';
import 'bel_scherm.dart';

/// Kies een apparaat om te bellen, met (voor de eigenaar) de
/// auto-answer-instelling op dezelfde plek.
///
/// Het eigen apparaat wordt uit de lijst gefilterd — kan-niet-met-jezelf-
/// bellen wordt óók server-side afgedwongen (startVideoCall gooit
/// invalid-argument), maar cliënt-side filteren voorkomt de dead-tap.
class BelApparaatKiesScherm extends StatefulWidget {
  const BelApparaatKiesScherm({super.key});

  @override
  State<BelApparaatKiesScherm> createState() => _BelApparaatKiesSchermState();
}

class _BelApparaatKiesSchermState extends State<BelApparaatKiesScherm> {
  bool _bezig = true;
  String? _fout;
  List<Map<String, dynamic>> _apparaten = const [];
  String? _mijnApparaatId;
  String? _kringId;
  bool _autoAnswer = false;
  bool _benIkEigenaar = false;

  @override
  void initState() {
    super.initState();
    _laad();
  }

  Future<void> _laad() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() { _bezig = false; _fout = 'Niet ingelogd'; });
        return;
      }
      final mijnAppId = await DeviceModusService.krijgApparaatId();
      final kringId = await DeviceModusService.huidigeKringIdMetFallback();
      if (kringId == null || kringId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _bezig = false;
          _fout = 'Geen actieve kring — kies eerst een kring';
        });
        return;
      }
      // Kring-doc eerst: eigenaarUid is nodig voor kringLeden zodat een
      // gast met eigen account de apparaten van de eigenaar ziet, niet
      // zijn eigen (lege) collectie. In de huidige shared-account situatie
      // is uid == eigenaarUid — geen enkel verschil in gedrag.
      final kringSnap = await FirebaseFirestore.instance
          .collection('kringen').doc(kringId).get();
      final data = kringSnap.data();
      final eigenaarUid = (data?['eigenaarUid'] as String? ?? '').trim();
      final effectiefUid = eigenaarUid.isNotEmpty ? eigenaarUid : uid;
      final leden = await ApparaatService.kringLeden(effectiefUid, kringId);
      if (!mounted) return;
      final autoAnswer = data?['autoAnswer'] == true;
      setState(() {
        _bezig = false;
        _mijnApparaatId = mijnAppId;
        _kringId = kringId;
        _autoAnswer = autoAnswer;
        _benIkEigenaar = eigenaarUid.isNotEmpty && eigenaarUid == uid;
        _apparaten = leden
            .where((a) =>
                a['apparaatId'] != mijnAppId &&
                (a['modus'] as String?) == 'ontvanger')
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _bezig = false; _fout = e.toString(); });
    }
  }

  Future<void> _zetAutoAnswer(bool waarde) async {
    final kringId = _kringId;
    if (kringId == null || kringId.isEmpty) return;
    setState(() => _autoAnswer = waarde);
    try {
      await FirebaseFirestore.instance
          .collection('kringen').doc(kringId)
          .update({'autoAnswer': waarde});
      // BEL-D3: bij AANZETTEN korte warme hint. We kunnen client-side
      // niet zien welke modus het ontvanger-apparaat heeft, dus we
      // tonen 'm áltijd bij aan-zetten. Rustige modus? Dan negeert de
      // gebruiker 'm terecht. Normale modus? Dan weet-'ie de weg.
      if (waarde && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(BelUitlegTeksten.autoAnswerAangezetHint,
              style: TextStyle(height: 1.4)),
          backgroundColor: kPeach,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Uitleg',
            textColor: kWhite,
            onPressed: () => BelUitlegDialog.forceerTonen(context),
          ),
        ));
      }
    } catch (_) {
      if (mounted) setState(() => _autoAnswer = !waarde);
    }
  }

  Future<void> _bel(Map<String, dynamic> apparaat) async {
    final kringId = _kringId;
    final bellerApparaatId = _mijnApparaatId;
    if (kringId == null || bellerApparaatId == null) return;
    final doelApparaatId = apparaat['apparaatId'] as String;
    final doelNaam = (apparaat['persoonsNaam'] as String? ?? '').trim();
    final label = (apparaat['apparaatLabel'] as String? ?? '').trim();
    final weergaveNaam = doelNaam.isNotEmpty
        ? doelNaam
        : (label.isNotEmpty ? label : 'Onbekend apparaat');

    // DEEL B (13 sept 2026): just-in-time warm dialog als het ontvanger-
    // apparaat niet als bel-gereed geregistreerd staat. Bron: sync die
    // in toestemmingen_setup_scherm bij elke resume plaatsvindt.
    //
    // Fail-open: null (oude installs die het setup-scherm nog nooit
    // hebben doorlopen sinds DEEL B) → geen dialog. We waarschuwen
    // ALLEEN bij expliciete `false`. Nadeel: eigenaar kan een echt-niet-
    // gereed toestel missen. Voordeel: geen false-positives waardoor de
    // hint irritatie wordt. Volgende keer dat het setup-scherm op de
    // ontvanger wordt geopend, komt de status correct binnen.
    //
    // Niet blokkerend: user kan altijd "Bel toch" — soms is de checklist
    // niet-gereed door een instelling die de gebruiker bewust wil laten
    // staan (bijv. bewust batterij-opt aan om ander onderzoek).
    final belGereed = apparaat['belGereed'];
    if (belGereed == false && mounted) {
      // BEL-CHK (15 sept 2026): modus-aware instructie. In rustige modus
      // is de tablet vastgezet op Ons Moment (kiosk), dus 'Instellingen →
      // Bellen → Instellingen voor dit apparaat' is NIET fysiek te
      // openen op de tablet zelf. Eigenaar moet eerst de rustige modus
      // tijdelijk uitzetten via 'Wijzig modus van $naam' hier in
      // Instellingen, dan de checklist openen, dan modus weer aan.
      final doelWeergaveModus = apparaat['weergaveModus'] as String?;
      final isRustig = doelWeergaveModus == DeviceModusService.VERGRENDELD;
      final instructieTekst = isRustig
          ? 'Zo zet je het aan:\n'
              '1. Open hier: Instellingen → "Wijzig modus van '
              '$weergaveNaam" en zet tijdelijk op Gewone modus.\n'
              '2. Pak het apparaat van $weergaveNaam. Open '
              'Ons Moment → Instellingen → Bellen → '
              '"Instellingen voor dit apparaat" en tik de '
              'ontbrekende stappen aan.\n'
              '3. Zet de modus daarna weer op Rustige modus.'
          : 'Zo zet je het aan:\n'
              'Pak het apparaat van $weergaveNaam, open '
              'Ons Moment → Instellingen → Bellen → '
              '"Instellingen voor dit apparaat", en tik de '
              'ontbrekende stappen aan.';
      final belToch = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          backgroundColor: kCream,
          title: Text('$weergaveNaam is nog niet helemaal klaar voor bellen',
              style: const TextStyle(fontSize: 17,
                  fontWeight: FontWeight.w900, color: kBrown)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Op het apparaat van $weergaveNaam staat nog een '
                    'instelling uit die nodig is voor bellen. Je kunt nu '
                    'toch bellen — het kan alleen zijn dat het gesprek '
                    'niet aankomt.',
                    style: const TextStyle(fontSize: 14,
                        color: kBrownLight, height: 1.5)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kPeachPale,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kPeachLight),
                  ),
                  child: Text(instructieTekst,
                      style: const TextStyle(fontSize: 13,
                          color: kBrown, height: 1.55)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuleren',
                    style: TextStyle(color: kTextMuted,
                        fontWeight: FontWeight.w700))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: kPeach,
                  foregroundColor: kWhite,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Bel toch',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
      if (belToch != true) return;
    }

    // V4: als automatisch opnemen aan staat, eerst bevestigen bij de beller.
    if (_autoAnswer && mounted) {
      final bevestigd = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Let op'),
          content: Text(
            '$weergaveNaam neemt automatisch op. '
            'Zorg dat je klaar bent om te worden gezien en gehoord.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuleer'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: kGreen, foregroundColor: kWhite),
              child: const Text('Bel toch'),
            ),
          ],
        ),
      );
      if (bevestigd != true) return;
    }

    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BelScherm(
        kringId: kringId,
        bellerApparaatId: bellerApparaatId,
        doelApparaatId: doelApparaatId,
        doelNaam: weergaveNaam,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return NormaalScaffold(
      backgroundColor: kCream,
      appBar: AppBar(
        title: const Text('Videobellen',
            style: TextStyle(color: kBrown, fontWeight: FontWeight.w800)),
        backgroundColor: kCream,
        foregroundColor: kBrown,
        elevation: 0,
      ),
      body: _bouwInhoud(),
    );
  }

  Widget _bouwInhoud() {
    if (_bezig) {
      return const Center(child: CircularProgressIndicator(color: kPeach));
    }
    if (_fout != null) {
      return Center(
        child: Padding(padding: const EdgeInsets.all(24),
          child: Text(_fout!,
              style: const TextStyle(color: kRood, fontSize: 14),
              textAlign: TextAlign.center)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _koptekst(),
        if (_apparaten.isEmpty)
          const Expanded(
            child: Center(
              child: Padding(padding: EdgeInsets.all(24),
                child: Text(
                    'Geen andere apparaten in deze kring om te bellen.',
                    style: TextStyle(color: kBrownLight, fontSize: 14),
                    textAlign: TextAlign.center)),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _apparaten.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final a = _apparaten[i];
                final naam = (a['persoonsNaam'] as String? ?? '').trim();
                final label = (a['apparaatLabel'] as String? ?? '').trim();
                final modus = (a['modus'] as String? ?? '').trim();
                final weergave = naam.isNotEmpty ? naam : 'Onbekend';
                final subtitel = [
                  if (label.isNotEmpty) label,
                  if (modus.isNotEmpty) modus,
                ].join(' · ');
                return Card(
                  color: kWhite,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: kPeachLight)),
                  child: ListTile(
                    title: Text(weergave,
                        style: const TextStyle(color: kBrown,
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    subtitle: subtitel.isNotEmpty
                        ? Text(subtitel,
                            style: const TextStyle(
                                color: kTextMuted, fontSize: 12))
                        : null,
                    trailing: ElevatedButton.icon(
                      onPressed: () => _bel(a),
                      icon: const Icon(Icons.videocam_rounded, size: 20),
                      label: Text('Bel $weergave',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kGreen,
                        foregroundColor: kWhite,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _koptekst() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Expanded(child: Text('Start een videogesprek',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                    color: kBrown))),
            // BEL-D3: klein linkje naar dezelfde warme uitleg-dialog
            // (BelUitlegTeksten). Altijd bereikbaar vanaf dit scherm.
            BelUitlegLink(),
          ]),
          const SizedBox(height: 4),
          const Text('Kies hieronder het apparaat van je dierbare.',
              style: TextStyle(fontSize: 13, color: kTextMuted, height: 1.4)),
          const SizedBox(height: 4),
          const Text(BelUitlegTeksten.wieBelJe,
              style: TextStyle(fontSize: 12, color: kTextMuted, height: 1.5)),
          if (_benIkEigenaar) ...[
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: kWhite,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kPeachLight),
              ),
              child: SwitchListTile(
                title: const Text('Gesprekken automatisch beantwoorden',
                    style: TextStyle(color: kBrown,
                        fontWeight: FontWeight.w700, fontSize: 15)),
                // BEL-D3: één zin uit BelUitlegTeksten. Wijzig 'm daar.
                subtitle: const Text(
                    BelUitlegTeksten.autoAnswerToggleUitleg,
                    style: TextStyle(color: kTextMuted, fontSize: 12,
                        height: 1.4)),
                value: _autoAnswer,
                activeColor: kGreen,
                onChanged: _zetAutoAnswer,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 6),
              ),
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
