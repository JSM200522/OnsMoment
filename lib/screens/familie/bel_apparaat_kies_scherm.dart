import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/apparaat_service.dart';
import '../../services/device_modus_service.dart';
import '../../theme/kleuren.dart';
import '../../widgets/normaal_scaffold.dart';
import 'bel_scherm.dart';

/// Verborgen debug-scherm (achter DEBUG_VIDEOBELLEN) — laat een familielid
/// een apparaat in de kring kiezen om te bellen. Toont per apparaat de
/// persoonsNaam + apparaatLabel en een 'Bel'-knop die [BelScherm] opent.
///
/// Het eigen apparaat wordt uit de lijst gefilterd — kan-niet-met-jezelf-
/// bellen wordt óók server-side afgedwongen (startVideoCall gooit
/// invalid-argument), maar cliënt-side filteren voorkomt de dead-tap.
///
/// Bereikbaarheid van elk apparaat (fcmToken aanwezig) wordt hier NIET
/// gefilterd; startVideoCall gooit failed-precondition als het doel-
/// apparaat geen actieve push-token heeft en [BelScherm] toont dan een
/// nette foutmelding. Latere iteratie kan die filter toevoegen aan
/// ApparaatService.kringLeden voor gray-out-UX.
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
      final ledenFuture = ApparaatService.kringLeden(uid, kringId);
      final kringSnap = await FirebaseFirestore.instance
          .collection('kringen').doc(kringId).get();
      final leden = await ledenFuture;
      if (!mounted) return;
      final autoAnswer = kringSnap.data()?['autoAnswer'] == true;
      setState(() {
        _bezig = false;
        _mijnApparaatId = mijnAppId;
        _kringId = kringId;
        _autoAnswer = autoAnswer;
        _apparaten = leden
            .where((a) => a['apparaatId'] != mijnAppId)
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _bezig = false; _fout = e.toString(); });
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
    // Zo weet de beller dat de ontvanger meteen zichtbaar en hoorbaar is.
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
        title: const Text('Bel apparaat (debug)',
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
    if (_apparaten.isEmpty) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(24),
          child: Text('Geen andere apparaten in deze kring om te bellen.',
              style: TextStyle(color: kBrownLight, fontSize: 14),
              textAlign: TextAlign.center)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
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
                    style: const TextStyle(color: kTextMuted, fontSize: 12))
                : null,
            trailing: ElevatedButton.icon(
              onPressed: () => _bel(a),
              icon: const Icon(Icons.videocam_rounded, size: 20),
              label: Text('Bel $weergave',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
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
    );
  }
}
