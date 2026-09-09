import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme/kleuren.dart';
import '../../widgets/normaal_scaffold.dart';

/// FDB-1: Feedback-/ideeënformulier in Instellingen.
///
/// Zichtbaar voor elke ingelogde gebruiker — eigenaar én gast. Doel:
/// Joshua kan tijdens de eerste testronde snel signalen van echte
/// families verzamelen zonder aparte kanalen.
///
/// Datamodel (platform-neutraal — Platform-principe uit CLAUDE.md):
///   feedback/{autoId}
///     uid: string           — auth.uid (audit)
///     weergaveNaam: string  — best-effort user-facing naam
///     categorie: 'idee' | 'probleem' | 'anders'
///     bericht: string       — vrije tekst
///     appVersie: string     — pubspec version+build
///     platform: 'android'|'ios'|'web'|'onbekend'
///     aangemaaktOp: server-timestamp
///
/// Firestore-rules: create-only voor ingelogde gebruikers; uid moet
/// gelijk zijn aan request.auth.uid (audit-trail). Read/update/delete
/// gaan uitsluitend via Firebase Console / Admin — anders zou een
/// gebruiker andermans feedback kunnen inzien.
class FeedbackScherm extends StatefulWidget {
  const FeedbackScherm({super.key});

  @override
  State<FeedbackScherm> createState() => _FeedbackSchermState();
}

class _FeedbackSchermState extends State<FeedbackScherm> {
  static const _appVersie = '1.0.36+41';

  final _berichtCtrl = TextEditingController();
  String _categorie = 'idee';
  bool _bezig = false;
  bool _klaar = false;

  @override
  void dispose() {
    _berichtCtrl.dispose();
    super.dispose();
  }

  String get _platform {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return 'onbekend';
    }
  }

  Future<String> _leesWeergaveNaam(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('gebruikers').doc(uid).get()
          .timeout(const Duration(seconds: 5));
      final data = snap.data();
      final naam = data?['naam'] as String?;
      if (naam != null && naam.isNotEmpty) return naam;
      final ontvangerNaam = data?['ontvangerNaam'] as String?;
      if (ontvangerNaam != null && ontvangerNaam.isNotEmpty) {
        return ontvangerNaam;
      }
    } catch (_) {}
    return FirebaseAuth.instance.currentUser?.email ?? '';
  }

  Future<void> _verstuur() async {
    final tekst = _berichtCtrl.text.trim();
    if (tekst.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Vul eerst je bericht in'),
        backgroundColor: kPeach,
      ));
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Je moet ingelogd zijn om feedback te sturen'),
        backgroundColor: kRood,
      ));
      return;
    }
    setState(() => _bezig = true);
    try {
      final weergaveNaam = await _leesWeergaveNaam(user.uid);
      await FirebaseFirestore.instance.collection('feedback').add({
        'uid': user.uid,
        'weergaveNaam': weergaveNaam,
        'categorie': _categorie,
        'bericht': tekst,
        'appVersie': _appVersie,
        'platform': _platform,
        'aangemaaktOp': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() {
        _klaar = true;
        _bezig = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _bezig = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Versturen mislukt — probeer opnieuw. ($e)'),
        backgroundColor: kRood,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return NormaalScaffold(
      backgroundColor: kCream,
      appBar: AppBar(
        title: const Text('Feedback en ideeën',
            style: TextStyle(fontWeight: FontWeight.w800, color: kBrown)),
        backgroundColor: kCream,
        elevation: 0,
        iconTheme: const IconThemeData(color: kBrown),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _klaar ? _bedankScherm() : _formulier(),
        ),
      ),
    );
  }

  Widget _bedankScherm() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.favorite, color: kPeach, size: 64),
          const SizedBox(height: 20),
          const Text('Dank je wel!',
              style: TextStyle(fontSize: 26,
                  fontWeight: FontWeight.w900, color: kBrown)),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Je bericht is verstuurd. Ik lees alles zelf — dank dat je '
              'de tijd nam om te helpen Ons Moment beter te maken.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: kBrownLight, height: 1.5),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPeach,
              foregroundColor: kWhite,
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Sluiten',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _formulier() {
    return ListView(children: [
      const Text(
        'Wat je hier stuurt komt direct bij Joshua terecht. Ik lees '
        'alles en gebruik het om Ons Moment te verbeteren.',
        style: TextStyle(fontSize: 14, color: kBrownLight, height: 1.5),
      ),
      const SizedBox(height: 16),
      const Text('Wat wil je delen?',
          style: TextStyle(fontSize: 14,
              fontWeight: FontWeight.w800, color: kBrown)),
      const SizedBox(height: 8),
      _categorieKeuze(),
      const SizedBox(height: 16),
      const Text('Je bericht',
          style: TextStyle(fontSize: 14,
              fontWeight: FontWeight.w800, color: kBrown)),
      const SizedBox(height: 8),
      TextField(
        controller: _berichtCtrl,
        maxLines: 8,
        minLines: 5,
        maxLength: 2000,
        style: const TextStyle(color: kBrown, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Vertel wat je bezighoudt — een idee, een probleem, '
              'of gewoon een berichtje.',
          hintStyle: const TextStyle(color: kTextMuted, fontSize: 14),
          filled: true,
          fillColor: kWhite,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kPeachLight),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kPeachLight),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kPeach, width: 2),
          ),
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _bezig ? null : _verstuur,
          style: ElevatedButton.styleFrom(
            backgroundColor: kPeach,
            foregroundColor: kWhite,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          child: _bezig
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(
                      color: kWhite, strokeWidth: 2.5))
              : const Text('Versturen',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      ),
    ]);
  }

  Widget _categorieKeuze() {
    return Wrap(
      spacing: 8,
      children: [
        _categorieChip('idee', '💡 Idee'),
        _categorieChip('probleem', '🐞 Probleem'),
        _categorieChip('anders', '💬 Anders'),
      ],
    );
  }

  Widget _categorieChip(String id, String label) {
    final aan = _categorie == id;
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
              color: aan ? kWhite : kBrown,
              fontWeight: FontWeight.w700, fontSize: 13)),
      selected: aan,
      selectedColor: kPeach,
      backgroundColor: kWhite,
      side: BorderSide(color: aan ? kPeach : kPeachLight),
      onSelected: (_) => setState(() => _categorie = id),
    );
  }
}
