import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/apparaat_service.dart';
import '../../services/device_modus_service.dart';
import '../../theme/kleuren.dart';
import '../../widgets/normaal_scaffold.dart';
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
            .where((a) => a['apparaatId'] != mijnAppId)
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
          const Text('Start een videogesprek',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                  color: kBrown)),
          const SizedBox(height: 4),
          const Text('Kies hieronder een apparaat om te bellen.',
              style: TextStyle(fontSize: 13, color: kTextMuted, height: 1.4)),
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
                subtitle: const Text(
                    'Als het apparaat van je dierbare aanstaat en Ons Moment '
                    'openstaat, wordt een videogesprek automatisch beantwoord '
                    '— je dierbare hoeft niets te doen.',
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
