import 'dart:typed_data';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/apparaat_service.dart';
import '../../services/device_modus_service.dart';
import '../../services/dagelijks_audio_service.dart';
import '../../theme/kleuren.dart';
import '../../data/geluiden.dart';
import '../../data/debug_flags.dart';
import '../../widgets/pulserend_hart.dart';
import '../../widgets/video_speler.dart';
import '../../data/labels.dart';
import 'kringleden_scherm.dart';
import 'kring_aanmaken_scherm.dart';
import '../../data/kring.dart';
import '../../data/kring_membership.dart';
import '../../services/kring_service.dart';

class FamilieScherm extends StatefulWidget {
  final bool alsOntvanger;
  const FamilieScherm({super.key, this.alsOntvanger = false});
  @override
  State<FamilieScherm> createState() => _FamilieSchermState();
}

class _FamilieSchermState extends State<FamilieScherm>
    with WidgetsBindingObserver {
  int _tab = 0;

  final _audioPlayer = AudioPlayer();
  final _geluidPlayer = AudioPlayer();
  StreamSubscription<QuerySnapshot>? _momentenListener;
  StreamSubscription<DocumentSnapshot>? _gebruikerSub;
  // V9 2.4-a-3: kring-doc als primaire bron voor geluid + foto;
  // _gebruikerSub blijft als legacy-fallback.
  StreamSubscription<Kring?>? _actieveKringSub;
  String? _kringFoto;
  String? _kringNaam;  // V9 2.13-b: live kring-naam voor 'Je dierbare'-swap in popup
  Map<String, dynamic>? _huidigPopup;
  String? _huidigPopupId;
  String _herkenningsgeluid = 'twinkel';
  String? _mijnApparaatId;
  String? _kringId;
  Timer? _autoSluitTimer;

  // Dagelijkse + eenmalige momenten-flow — alleen actief in
  // ontvanger-meldings-modus.
  Timer? _checkTimer;
  StreamSubscription<QuerySnapshot>? _dagelijkseSub;
  List<QueryDocumentSnapshot>? _dagelijkseDocs;
  StreamSubscription<QuerySnapshot>? _eenmaligSub;
  List<QueryDocumentSnapshot>? _eenmaligDocs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Listeners pas starten ná apparaatId-load zodat _verwerkMomenten nooit
    // triggert met _mijnApparaatId == null (voorkomt off-by-one delay).
    DeviceModusService.krijgApparaatId().then((id) {
      if (!mounted) return;
      setState(() => _mijnApparaatId = id);
      _startGebruikerListener();
    });
    // V9 1.1f/1.1g/1.1h: alle kringId-gefilterde listeners pas starten ná
    // resolve, anders null-filter en hoort de ontvanger geen popups/
    // herkenningsgeluiden meer.
    DeviceModusService.huidigeKringIdMetFallback().then((id) {
      if (!mounted) return;
      setState(() => _kringId = id);
      if (id != null) {
        _startMomentenListener();
        if (widget.alsOntvanger) {
          _startDagelijksListener();
          _startEenmaligListener();
        }
      }
    });
    if (widget.alsOntvanger) {
      _checkTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _checkGeplandeMomenten();
        _herscanMomenten();
      });
    }
    // V9 2.2b: luister op kring-switch zodat alle kringId-afhankelijke
    // listeners automatisch herstarten met de nieuwe kring.
    DeviceModusService.actieveKringNotifier
        .addListener(_opActieveKringWijziging);
    // V9 2.4-a-3: lees naam/foto/geluid uit het ACTIEVE kring-doc
    // (overschrijft de waarden uit _gebruikerSub bij elke kring-emit).
    _actieveKringSub = KringService.actieveKringStream().listen((kring) {
      if (!mounted || kring == null) return;
      setState(() {
        if (kring.foto != null && kring.foto!.isNotEmpty) {
          _kringFoto = kring.foto;
        }
        if (kring.herkenningsgeluid.isNotEmpty) {
          _herkenningsgeluid = kring.herkenningsgeluid;
        }
        if (kring.naam.isNotEmpty) {
          _kringNaam = kring.naam;
        }
      });
    });
    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed
          && (_huidigPopup?['type'] == 'stem'
              || _huidigPopup?['type'] == 'lied'
              || _huidigPopup?['type'] == 'dagelijks')) {
        _sluitPopup();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DeviceModusService.actieveKringNotifier
        .removeListener(_opActieveKringWijziging);
    _autoSluitTimer?.cancel();
    _checkTimer?.cancel();
    _momentenListener?.cancel();
    _gebruikerSub?.cancel();
    _actieveKringSub?.cancel();
    _dagelijkseSub?.cancel();
    _eenmaligSub?.cancel();
    _audioPlayer.dispose();
    _geluidPlayer.dispose();
    super.dispose();
  }

  /// V9 2.2b: callback voor actieveKringNotifier. Triggert herstart van
  /// kringId-afhankelijke listeners zodra een andere kring actief wordt.
  void _opActieveKringWijziging() {
    final nieuwe = DeviceModusService.actieveKringNotifier.value;
    if (nieuwe != null) _herstartListeners(nieuwe);
  }

  /// V9 2.2b: cancelt en herstart alle kringId-afhankelijke listeners.
  /// No-op als de meegegeven kringId gelijk is aan de huidige (voorkomt
  /// onnodige reload bij normale inlog-flow waar de notifier ook fired).
  Future<void> _herstartListeners(String nieuweKringId) async {
    if (nieuweKringId == _kringId) return;
    await _momentenListener?.cancel(); _momentenListener = null;
    await _dagelijkseSub?.cancel();    _dagelijkseSub    = null;
    await _eenmaligSub?.cancel();      _eenmaligSub      = null;
    if (!mounted) return;
    setState(() {
      _kringId = nieuweKringId;
      _dagelijkseDocs = null;
      _eenmaligDocs   = null;
      _huidigPopup    = null;
      _huidigPopupId  = null;
    });
    _startMomentenListener();
    if (widget.alsOntvanger) {
      _startDagelijksListener();
      _startEenmaligListener();
    }
  }

  void _debugLog(String msg) {
    if (!DEBUG_AUDIO || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 11)),
      backgroundColor: Colors.black.withOpacity(0.75),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.only(top: 60, left: 16, right: 16, bottom: 0),
    ));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _herscanMomenten();
  }

  /// Her-scant openstaande (ongeziene) momenten via een verse query en voert
  /// ze door _verwerkMomenten. Vangt berichten op die binnenkwamen terwijl een
  /// popup open was (Bug A) of de app op de achtergrond stond (Bug B).
  Future<void> _herscanMomenten() async {
    if (_huidigPopupId != null) return;
    final kringId = _kringId;
    if (kringId == null) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('momenten')
          .where('kringId', isEqualTo: kringId)
          .where('gezien', isEqualTo: false)
          .get();
      if (mounted) _verwerkMomenten(snap);
    } catch (_) {}
  }

  void _startMomentenListener() {
    final kringId = _kringId;
    if (kringId == null) return;
    _momentenListener = FirebaseFirestore.instance.collection('momenten')
        .where('kringId', isEqualTo: kringId)
        .where('gezien', isEqualTo: false)
        .snapshots()
        .listen(_verwerkMomenten);
  }

  void _startGebruikerListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _gebruikerSub = FirebaseFirestore.instance
        .collection('gebruikers').doc(uid).snapshots()
        .listen((doc) {
      final data = doc.data() as Map<String, dynamic>?;
      final nieuwGeluid = data?['herkenningsgeluid'] as String? ?? 'twinkel';
      if (mounted && _herkenningsgeluid != nieuwGeluid) {
        setState(() => _herkenningsgeluid = nieuwGeluid);
      }
    });
  }

  void _startDagelijksListener() {
    final kringId = _kringId;
    if (kringId == null) return;
    _dagelijkseSub = FirebaseFirestore.instance
        .collection('dagelijkse_momenten')
        .where('kringId', isEqualTo: kringId)
        .where('actief', isEqualTo: true)
        .snapshots()
        .listen((snap) => _dagelijkseDocs = snap.docs);
  }

  void _startEenmaligListener() {
    final kringId = _kringId;
    if (kringId == null) return;
    _eenmaligSub = FirebaseFirestore.instance
        .collection('gepland_momenten')
        .where('kringId', isEqualTo: kringId)
        .where('actief', isEqualTo: true)
        .snapshots()
        .listen((snap) => _eenmaligDocs = snap.docs);
  }

  Future<void> _checkGeplandeMomenten() async {
    if (_huidigPopupId != null) return;
    final nu = DateTime.now();
    final huidigMin = nu.hour * 60 + nu.minute;
    final vandaagKey = '${nu.year}-'
        '${nu.month.toString().padLeft(2, '0')}-'
        '${nu.day.toString().padLeft(2, '0')}';
    if (_dagelijkseDocs != null) {
      for (final doc in _dagelijkseDocs!) {
        final d = doc.data() as Map<String, dynamic>;
        final momentMin = (d['uur'] as int? ?? 0) * 60
                        + (d['minuut'] as int? ?? 0);
        if (momentMin > huidigMin) continue;
        if (huidigMin - momentMin > 1) continue;
        if (d['laatstGetoond'] == vandaagKey) continue;
        try {
          await doc.reference.update({'laatstGetoond': vandaagKey});
        } catch (_) {}
        _toonDagelijksPopup(doc.id, d);
        return;
      }
    }
    // Eenmalig geplande momenten: trigger als geplandOp <= nu < +24u en
    // nog niet getoond. Robuust: vangt gemiste momenten op (apparaat sliep).
    if (_eenmaligDocs != null) {
      for (final doc in _eenmaligDocs!) {
        final d = doc.data() as Map<String, dynamic>;
        if (d['getoond'] == true) continue;
        final geplandOp = (d['geplandOp'] as Timestamp?)?.toDate();
        if (geplandOp == null) continue;
        final verschil = nu.difference(geplandOp);
        if (verschil.isNegative) continue;       // nog in toekomst
        if (verschil.inHours >= 24) continue;     // te laat, sla over
        try {
          await doc.reference.update({'getoond': true});
        } catch (_) {}
        _toonEenmaligPopup(doc.id, d);
        return;
      }
    }
  }

  Future<void> _toonDagelijksPopup(
      String id, Map<String, dynamic> d) async {
    final aangepasteAudio = d['aangepasteAudioUrl'] as String? ?? '';
    final synthetic = <String, dynamic>{
      'type': 'dagelijks',
      'emoji': d['emoji'],
      'label': d['label'],
      'mediaUrl': aangepasteAudio,
      'geplandOp': Timestamp.now(),
      'heeftAangepasteAudio': aangepasteAudio.isNotEmpty,
    };
    await _toonPopup('dagelijks_$id', synthetic);
  }

  Future<void> _toonEenmaligPopup(
      String id, Map<String, dynamic> d) async {
    // Hergebruik 'dagelijks' popup-rendering + audio-flow: emoji + label,
    // standaard geluid of eigen audio. Identiek aan dagelijks moment.
    final aangepasteAudio = d['aangepasteAudioUrl'] as String? ?? '';
    final synthetic = <String, dynamic>{
      'type': 'dagelijks',
      'emoji': d['emoji'],
      'label': d['label'],
      'mediaUrl': aangepasteAudio,
      'geplandOp': Timestamp.now(),
      'heeftAangepasteAudio': aangepasteAudio.isNotEmpty,
    };
    await _toonPopup('eenmalig_$id', synthetic);
  }

  void _verwerkMomenten(QuerySnapshot snap) {
    _debugLog('📨 Snap (meldings): ${snap.docs.length}');
    if (_huidigPopupId != null) return;
    if (_mijnApparaatId == null) return;
    final nu = DateTime.now();
    final voor24uur = nu.subtract(const Duration(hours: 24));
    for (final doc in snap.docs) {
      final d = doc.data() as Map<String, dynamic>;
      // V9 2.10-a-1: 4-pad targeting-filter.
      // 1. aanUserUids -> nieuwe lid-target (V9 membership-based,
      //    werkt over alle apparaten van het lid).
      // 2. aanApparaatIds -> ontvanger-target (V9 'voor je dierbare')
      //    of oude lid-target (pre-2.10 backwards-compat).
      // 3. aanApparaatId -> heel oude single-id docs.
      // 4. allemaal null/leeg -> iedereen in de kring.
      // De send-kant schrijft nog GEEN aanUserUids tot 2.10-a-2;
      // pad 1 is voorbereiding zonder gedragswijziging.
      final aanUserUidsLijst =
          (d['aanUserUids'] as List?)?.cast<String>();
      final aanApparaatIdsLijst =
          (d['aanApparaatIds'] as List?)?.cast<String>();
      final aanLegacy = d['aanApparaatId'] as String?;
      bool voorMij;
      if (aanUserUidsLijst != null && aanUserUidsLijst.isNotEmpty) {
        final mijnUid = FirebaseAuth.instance.currentUser?.uid;
        voorMij = mijnUid != null
            && aanUserUidsLijst.contains(mijnUid);
      } else if (aanApparaatIdsLijst != null
          && aanApparaatIdsLijst.isNotEmpty) {
        voorMij = aanApparaatIdsLijst.contains(_mijnApparaatId);
      } else if (aanLegacy != null) {
        voorMij = aanLegacy == _mijnApparaatId;
      } else {
        voorMij = true;
      }
      if (!voorMij) continue;
      // Eigen bericht skip
      final van = d['vanApparaatId'] as String?;
      if (van != null && van == _mijnApparaatId) continue;
      // In gewone familie-modus: alleen popups van ontvanger-apparaten
      // (familie→familie geeft geen popup)
      if (!widget.alsOntvanger) {
        final vanModus = d['vanApparaatModus'] as String?;
        if (vanModus != 'ontvanger') continue;
      }
      final geplandOp = (d['geplandOp'] as Timestamp?)?.toDate();
      if (geplandOp == null) continue;
      if (geplandOp.isBefore(nu) && geplandOp.isAfter(voor24uur)) {
        _toonPopup(doc.id, d);
        return;
      }
    }
  }

  Future<void> _toonPopup(String id, Map<String, dynamic> d) async {
    if (_huidigPopupId != null) return;
    _huidigPopupId = id;

    try {
      await FirebaseFirestore.instance.collection('momenten')
          .doc(id).update({'gezien': true});
    } catch (_) {}

    final skipBel = d['heeftAangepasteAudio'] == true;
    final geluidAsset = kGeluidAssets[_herkenningsgeluid];
    if (!skipBel && geluidAsset != null) {
      bool geluidGespeeld = false;
      try {
        _debugLog('🔔 Bel laden: $_herkenningsgeluid');
        await _geluidPlayer.setAsset(geluidAsset);
        await _geluidPlayer.play();
        geluidGespeeld = true;
      } catch (e) {
        _debugLog('❌ Bel-fout: $e');
      }
      if (geluidGespeeld) {
        await Future.delayed(const Duration(milliseconds: 1200));
      }
    }

    if (!mounted) {
      _huidigPopupId = null;
      return;
    }
    setState(() {
      _huidigPopup = d;
    });

    if (d['type'] == 'stem' || d['type'] == 'lied' || d['type'] == 'dagelijks') {
      final url = d['mediaUrl'] ?? '';
      if (url.isNotEmpty) {
        try {
          _debugLog('🔊 Audio laden');
          await _audioPlayer.setUrl(url);
          await _audioPlayer.play();
        } catch (e) {
          _debugLog('❌ Audio-fout: $e');
        }
      }
    }
    _autoSluitTimer?.cancel();
    final sluitNa = (d['type'] == 'hartje') ? 10 : 60;
    _autoSluitTimer = Timer(Duration(seconds: sluitNa), _sluitPopup);
  }

  Future<void> _sluitPopup() async {
    await _audioPlayer.stop();
    _autoSluitTimer?.cancel();
    if (mounted) {
      setState(() {
        _huidigPopup = null;
        _huidigPopupId = null;
      });
    }
    // Toon na een korte rustpauze een eventueel gemist bericht (Bug A).
    Future.delayed(const Duration(milliseconds: 500), _herscanMomenten);
  }

  Widget _popupOverlay() {
    final d = _huidigPopup!;
    final type = d['type'] ?? '';
    final vanRaw = (d['vanNaam'] as String?)?.trim() ?? '';
    // V9 2.13-b: als de send-kant 'Je dierbare' als fallback wegschreef
    // (bijv. kring-naam nog niet geladen op moment van versturen), swap
    // hier met de live kring-naam. Faalt netjes terug op 'Je dierbare' als
    // _kringNaam nog niet geladen is of ook leeg blijft. Andere waardes
    // (echte namen, 'Iemand uit je kring') blijven ongemoeid.
    final vanFromKring = (_kringNaam ?? '').trim();
    final String vanNaam;
    if (vanRaw.isEmpty) {
      vanNaam = 'Iemand uit je kring';
    } else if (vanRaw.toLowerCase() == 'je dierbare' && vanFromKring.isNotEmpty) {
      vanNaam = vanFromKring;
    } else {
      vanNaam = vanRaw;
    }
    final geplandOp = (d['geplandOp'] as Timestamp?)?.toDate();
    // V9 2.20: mirror van tablet_scherm _popupOverlay-upgrade (V9 2.14-a).
    // Popup schaalt mee met schermgrootte (85% breedte, cap 1100 voor
    // desktop) i.p.v. de vaste 600 px. Op tablet ± 75-85% zichtbaar,
    // op telefoon comfortabel binnen de rand met de bestaande 20 px marge.
    final schermBreedte = MediaQuery.of(context).size.width;
    final kaartBreedte = (schermBreedte * 0.85).clamp(320.0, 1100.0);
    return Container(color: kBrown.withOpacity(0.94),
      child: SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: kaartBreedte),
          child: SingleChildScrollView(child: Container(
            decoration: BoxDecoration(color: kCream,
                borderRadius: BorderRadius.circular(40),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3),
                    blurRadius: 40)]),
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 40),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (type != 'hartje') ...[
                  Text(_emojiVoorType(type),
                      style: const TextStyle(fontSize: 96)),
                  const SizedBox(height: 12),
                ],
                Text(type == 'dagelijks'
                    ? 'Het is tijd voor:'
                    : type == 'hartje'
                        ? '$vanNaam denkt aan je 💕'
                        : '$vanNaam stuurt je een bericht',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: kBrown,
                        height: 1.2)),
                const SizedBox(height: 28),
                _popupInhoud(d),
                if (geplandOp != null) ...[
                  const SizedBox(height: 20),
                  Text(_formatPopupTijd(geplandOp),
                      style: const TextStyle(fontSize: 16,
                          color: kTextMuted, fontStyle: FontStyle.italic)),
                ],
                const SizedBox(height: 24),
                Text(type == 'stem' || type == 'lied' || type == 'dagelijks'
                    ? 'Sluit automatisch wanneer klaar'
                    : 'Tik om te sluiten',
                    style: const TextStyle(fontSize: 14, color: kTextMuted)),
              ])),
          ))),
        )),
      ),
    );
  }

  Widget _popupInhoud(Map<String, dynamic> d) {
    final type = d['type'] ?? '';
    final bericht = d['bericht'] ?? '';
    final url = d['mediaUrl'] ?? '';
    switch (type) {
      case 'foto':
        final fotoHoogte =
            (MediaQuery.of(context).size.height * 0.75).clamp(320.0, 900.0);
        return Column(mainAxisSize: MainAxisSize.min, children: [
          if (url.isNotEmpty) ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.network(url,
              height: fotoHoogte, fit: BoxFit.cover,
              loadingBuilder: (c, child, prog) {
                if (prog == null) return child;
                return Container(height: fotoHoogte, color: kPeachPale,
                  child: const Center(
                      child: CircularProgressIndicator(color: kPeach)));
              },
              errorBuilder: (c, e, s) => Container(
                height: fotoHoogte, color: kPeachPale,
                child: const Center(child: Icon(Icons.broken_image,
                    size: 120, color: kPeach))))),
          if (bericht.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(bericht, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24,
                    color: kBrown, height: 1.4)),
          ],
        ]);
      case 'stem':
      case 'lied':
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Container(padding: const EdgeInsets.all(36),
            decoration: BoxDecoration(
                color: kPeachPale,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                    color: kPeach.withOpacity(0.25),
                    blurRadius: 32, spreadRadius: 4)]),
            child: const Icon(Icons.volume_up_rounded,
                color: kPeach, size: 140)),
          const SizedBox(height: 20),
          Text(type == 'stem' ? '🎙️ Stembericht' : '🎵 Liedje',
              style: const TextStyle(fontSize: 26,
                  fontWeight: FontWeight.w800, color: kBrown)),
          if (bericht.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(bericht, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22,
                    color: kBrownLight, height: 1.4)),
          ],
        ]);
      case 'tekst':
        // V9 2.20: horizontale wrapper compenseert de reductie van de
        // kaart-padding (24 → 12) zodat de tekst-kaart visueel dezelfde
        // breedte houdt als vóór de foto/video-vergroting.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            decoration: BoxDecoration(
                color: kPeachPale,
                borderRadius: BorderRadius.circular(24)),
            child: Text(bericht.isEmpty ? 'Een lief bericht voor jou' : bericht,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 40, color: kBrown,
                    height: 1.5, fontWeight: FontWeight.w600)),
          ),
        );
      case 'dagelijks':
        final dagelijksEmojiSize =
            (MediaQuery.of(context).size.shortestSide * 0.28)
                .clamp(140.0, 220.0);
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Text(d['emoji'] as String? ?? '⭐',
              style: TextStyle(fontSize: dagelijksEmojiSize)),
          const SizedBox(height: 24),
          Text(d['label'] as String? ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 44,
                  fontWeight: FontWeight.w800, color: kBrown, height: 1.2)),
        ]);
      case 'hartje':
        final hartjeSize =
            (MediaQuery.of(context).size.shortestSide * 0.55)
                .clamp(220.0, 380.0);
        return Center(child: PulserendHart(grootte: hartjeSize));
      case 'video':
        return VideoSpeler(url: url);
      default:
        return const SizedBox();
    }
  }

  String _emojiVoorType(String type) {
    switch (type) {
      case 'foto': return '📷';
      case 'stem': return '🎙️';
      case 'lied': return '🎵';
      case 'tekst': return '✏️';
      case 'dagelijks': return '⏰';
      case 'video': return '🎥';
      default: return '💕';
    }
  }

  String _formatPopupTijd(DateTime d) =>
      'Verstuurd om ${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (!widget.alsOntvanger) return _buildScaffold(achtergrondFotoUrl: '');
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return _buildScaffold(achtergrondFotoUrl: '');
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('gebruikers').doc(uid).snapshots(),
      builder: (ctx, snap) {
        final gebruikersFoto = (snap.data?.data() as Map<String, dynamic>?)
            ?['ontvangerFoto'] as String? ?? '';
        // V9 2.4-a-3: kring-foto heeft voorrang; gebruikers/{uid} als
        // fallback (V7/V8-accounts zonder kring-doc).
        final url = (_kringFoto != null && _kringFoto!.isNotEmpty)
            ? _kringFoto!
            : gebruikersFoto;
        return _buildScaffold(achtergrondFotoUrl: url);
      },
    );
  }

  Widget _buildScaffold({required String achtergrondFotoUrl}) {
    final toonAchtergrond = widget.alsOntvanger
        && achtergrondFotoUrl.isNotEmpty;
    return Scaffold(
      backgroundColor: toonAchtergrond ? Colors.transparent : kCream,
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
                builder: (ctx) => const _HulpDialog()),
          ),
        ],
      ),
      body: Stack(children: [
        if (toonAchtergrond) ...[
          Positioned.fill(child: Image.network(achtergrondFotoUrl,
            fit: BoxFit.cover,
            loadingBuilder: (c, child, prog) {
              if (prog == null) return child;
              return Container(decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [kPeachPale, kCream])));
            },
            errorBuilder: (c, e, s) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [kPeachPale, kCream]))))),
          Positioned.fill(child: Container(
              color: kCream.withOpacity(0.68))),
        ],
        _huidigeTab(),
        if (_huidigPopup != null) Positioned.fill(
          child: GestureDetector(
            onTap: _sluitPopup,
            child: _popupOverlay(),
          ),
        ),
      ]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: kWhite,
            boxShadow: [BoxShadow(color: kBrown.withOpacity(0.08),
                blurRadius: 16)]),
        child: SafeArea(child: Row(children: [
          _navItem(0, Icons.send_rounded, 'Sturen'),
          _navItem(1, Icons.calendar_today_rounded, 'Agenda'),
          if (!widget.alsOntvanger)
            _navItem(2, Icons.note_alt_rounded, 'Notities'),
          _navItem(widget.alsOntvanger ? 2 : 3,
              Icons.settings_rounded, 'Instellingen'),
        ])),
      ),
    );
  }

  Widget _huidigeTab() {
    if (widget.alsOntvanger) {
      switch (_tab) {
        case 0: return StuurTab(alsOntvanger: widget.alsOntvanger);
        case 1: return AgendaTab(alsOntvanger: widget.alsOntvanger);
        case 2: return InstellingenTab(alsOntvanger: widget.alsOntvanger);
        default: return const SizedBox();
      }
    }
    switch (_tab) {
      case 0: return StuurTab(alsOntvanger: widget.alsOntvanger);
      case 1: return AgendaTab(alsOntvanger: widget.alsOntvanger);
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
// STUUR TAB
// ════════════════════════════════════════════════════════════
class StuurTab extends StatefulWidget {
  final bool alsOntvanger;
  const StuurTab({super.key, this.alsOntvanger = false});
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
  bool _testModus = false;  // Default UIT in productie (zie DEBUG_TESTMODUS)

  final _recorder = AudioRecorder();
  final _previewPlayer = AudioPlayer();
  bool _isOpnemen = false;
  bool _hebOpname = false;
  String? _opnamePad;
  int _opnameSeconden = 0;
  Timer? _opnameTimer;

  String? _gekozenPersoonsNaam;  // legacy display + aanPersoonsNaam-historie
  String? _mijnApparaatId;
  String? _ontvangerNaam;       // legacy: uit gebruikers/{uid}
  String? _kringNaam;            // V9 2.4-a-3: uit actieve kring-doc
  /// V9 2.11-a-3: eigen weergaveNaam uit het membership van de actieve
  /// kring (kringen/{kringId}/leden/{auth.uid}.weergaveNaam, sinds
  /// 2.8-a-1). Gebruikt als vanNaam bij send wanneer dit een familielid
  /// is (widget.alsOntvanger == false). Vervangt de oude lookup via
  /// kringLeden(uid) die account-breed was en lekt bij multi-kring.
  String? _mijnWeergaveNaam;
  StreamSubscription<Kring?>? _actieveKringSub;
  /// V9 2.10-a-2: live leden-stream van de ACTIEVE kring.
  /// Vervangt de oude _kringFuture (account-brede kringLeden(uid))
  /// zodat gasten met eigen account zichtbaar zijn en geen oude
  /// apparaat-namen meer lekken.
  List<Membership> _leden = const [];
  StreamSubscription<QuerySnapshot>? _ledenSub;
  String? _actieveKringIdVoorLeden;
  /// V9 2.10-a-2: targeting-keuze. _gekozenUserUid = lid-target via
  /// aanUserUids; _dierbareTarget = 'voor je dierbare' via aanApparaatIds
  /// (ontvanger-apparaten). Allebei null/false = iedereen in de kring.
  /// _gekozenPersoonsNaam blijft als display/historie-veld.
  String? _gekozenUserUid;
  bool _dierbareTarget = false;
  double? _uploadProgress;  // null = geen media-upload bezig
  bool _uploadIndeterminate = false;  // web-fallback als progress 0->100 springt

  /// V9 2.4-a-3: kring-doc primair, gebruikers/{uid} als fallback,
  /// 'je dierbare' als ultieme default. Nooit lege naam.
  String get _toonNaam {
    if ((_kringNaam ?? '').isNotEmpty) return _kringNaam!;
    if ((_ontvangerNaam ?? '').isNotEmpty) return _ontvangerNaam!;
    return 'je dierbare';
  }

  @override
  void initState() {
    super.initState();
    DeviceModusService.krijgApparaatId().then((id) {
      if (mounted) setState(() => _mijnApparaatId = id);
    });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      // V9 2.10-a-2: account-brede kringLeden(uid)-init is verwijderd;
      // de leden komen nu uit de actieve kring (zie _startLedenStream
      // hieronder en _opActieveKringWissel voor switch-handling).
      FirebaseFirestore.instance.collection('gebruikers').doc(uid).get()
          .then((doc) {
        if (!mounted) return;
        setState(() {
          _ontvangerNaam =
              (doc.data()?['ontvangerNaam'] as String?) ?? 'ontvanger';
        });
      });
    }
    _actieveKringSub = KringService.actieveKringStream().listen((kring) {
      if (!mounted) return;
      setState(() {
        _kringNaam = (kring != null && kring.naam.isNotEmpty)
            ? kring.naam : null;
      });
    });
    // V9 2.11-a-3 + 2.10-a-2: eerste load van eigen weergaveNaam en
    // de leden-stream van de actieve kring. Notifier-listener vangt
    // kring-switch op voor beide.
    DeviceModusService.huidigeKringIdMetFallback().then((id) {
      _laadMijnWeergaveNaam(id);
      _startLedenStream(id);
    });
    DeviceModusService.actieveKringNotifier
        .addListener(_opActieveKringWissel);
  }

  void _opActieveKringWissel() {
    final nw = DeviceModusService.actieveKringNotifier.value;
    if (nw == null || nw.isEmpty) return;
    _laadMijnWeergaveNaam(nw);
    _startLedenStream(nw);
  }

  /// V9 2.10-a-2: subscribe op kringen/{kringId}/leden zodat de
  /// persoon-kiezer altijd de echte leden van de ACTIEVE kring toont
  /// (gasten met eigen account zichtbaar). Detecteert een gekozen
  /// lid dat tijdens opstellen uit de kring verdwijnt en reset +
  /// snackbar in dat geval.
  void _startLedenStream(String? kringId) {
    if (kringId == _actieveKringIdVoorLeden) return;
    _ledenSub?.cancel();
    _actieveKringIdVoorLeden = kringId;
    if (kringId == null || kringId.isEmpty) {
      if (mounted) setState(() => _leden = const []);
      return;
    }
    _ledenSub = FirebaseFirestore.instance
        .collection('kringen').doc(kringId)
        .collection('leden').snapshots()
        .listen((snap) {
      if (!mounted) return;
      final leden = snap.docs.map(Membership.fromFirestore).toList();
      leden.sort((a, b) {
        if (a.rol == AccountRol.eigenaar
            && b.rol != AccountRol.eigenaar) return -1;
        if (b.rol == AccountRol.eigenaar
            && a.rol != AccountRol.eigenaar) return 1;
        return a.gejoindOp.compareTo(b.gejoindOp);
      });
      // Detecteer gekozen lid dat verdwenen is.
      bool moetReset = false;
      if (_gekozenUserUid != null
          && !leden.any((m) => m.userUid == _gekozenUserUid)) {
        moetReset = true;
      }
      setState(() {
        _leden = leden;
        if (moetReset) {
          _gekozenUserUid = null;
          _gekozenPersoonsNaam = null;
        }
      });
      if (moetReset && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('De gekozen persoon is uit de kring gegaan.'),
          backgroundColor: kRood));
      }
    });
  }

  /// V9 2.10-a-2: uid van de eigenaar uit de huidige leden-lijst.
  /// Gebruikt om ontvanger-apparaten te vinden (die staan onder de
  /// eigenaar's apparaten-subcollectie).
  String? _eigenaarUid() {
    for (final m in _leden) {
      if (m.rol == AccountRol.eigenaar) return m.userUid;
    }
    return null;
  }

  /// V9 2.10-a-2: ontvanger-apparaat-IDs van de actieve kring voor
  /// het 'Voor je dierbare'-target (Variant 2). Single-field where
  /// op kringId (auto-indexed) + clientside filter op modus=='ontvanger'.
  Future<List<String>> _ontvangerApparaatIds(String kringId) async {
    final eigenaar = _eigenaarUid();
    if (eigenaar == null) return const [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('gebruikers').doc(eigenaar)
          .collection('apparaten')
          .where('kringId', isEqualTo: kringId)
          .get();
      return snap.docs
          .where((d) =>
              ((d.data())['modus'] as String?) == 'ontvanger')
          .map((d) => d.id)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _laadMijnWeergaveNaam(String? kringId) async {
    if (kringId == null || kringId.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final ledenDoc = await FirebaseFirestore.instance
          .collection('kringen').doc(kringId)
          .collection('leden').doc(uid).get();
      final naam = ledenDoc.data()?['weergaveNaam'] as String?;
      if (!mounted) return;
      setState(() {
        _mijnWeergaveNaam =
            (naam != null && naam.isNotEmpty) ? naam : null;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _actieveKringSub?.cancel();
    _ledenSub?.cancel();
    DeviceModusService.actieveKringNotifier
        .removeListener(_opActieveKringWissel);
    _recorder.dispose();
    _previewPlayer.dispose();
    _opnameTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Stuur een moment',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
                color: kBrown)),
        const SizedBox(height: 8),
        const Text('Kies één type media. Eén ding tegelijk werkt het beste.',
            style: TextStyle(fontSize: 13, color: kTextMuted, height: 1.4)),
        // TEST MODUS — alleen zichtbaar in debug (zie DEBUG_TESTMODUS)
        if (DEBUG_TESTMODUS) ...[
        const SizedBox(height: 16),
        Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _testModus ? kBlue : kPeachPale,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _testModus ? kBlue : kPeachLight,
                width: 1.5)),
          child: Row(children: [
            Icon(_testModus ? Icons.bolt_rounded : Icons.timer_rounded,
                color: _testModus ? kWhite : kTextMuted, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Text(_testModus ? 'TEST-MODUS AAN' : 'Test-modus uit',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900,
                      color: _testModus ? kWhite : kBrown)),
              Text(_testModus
                  ? 'Verschijnt direct bij ontvanger (binnen 5 sec)'
                  : 'Tik om aan te zetten — handig om snel te testen',
                  style: TextStyle(fontSize: 11,
                      color: _testModus ? kWhite.withOpacity(0.9) : kTextMuted)),
            ])),
            Switch(value: _testModus,
                onChanged: (v) => setState(() => _testModus = v),
                activeColor: kWhite, activeTrackColor: kBlue.withOpacity(0.5)),
          ])),
        ],

        const SizedBox(height: 16),
        if (widget.alsOntvanger) ...[
          _adresKeuze(),
          const SizedBox(height: 16),
        ],
        // 3x2 grid: Foto/Video, Stem/Lied, Tekst/Hartje.
        Row(children: [
          _typeKnop('📷', 'Foto', 'foto'),
          const SizedBox(width: 10),
          _typeKnop('🎥', 'Video', 'video'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _typeKnop('🎙️', 'Stem', 'stem'),
          const SizedBox(width: 10),
          _typeKnop('🎵', 'Lied', 'lied'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _typeKnop('✏️', 'Tekst', 'tekst'),
          const SizedBox(width: 10),
          _actieTegel(
              icoon: const PulserendHart(grootte: 28),
              label: 'Hartje',
              onTap: _stuurHartje),
        ]),

        if (_type.isNotEmpty) ...[
          const SizedBox(height: 20),
          _inhoudInvoer(),
          const SizedBox(height: 16),
          TextField(
            controller: _berichtCtrl, maxLines: 2,
            decoration: InputDecoration(
              labelText: _type == 'tekst' ? 'Bericht' : 'Optioneel bijschrift',
              hintText: _type == 'tekst' ? 'Wat wil je zeggen?'
                  : 'Bijv. "Een leuke foto van de kleinkinderen!"',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              filled: true, fillColor: kWhite),
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
              child: Center(child: !_bezig
                ? Text(
                    _testModus
                        ? (widget.alsOntvanger
                            ? (_gekozenPersoonsNaam == null
                                ? '⚡ Stuur NU naar de kring'
                                : '⚡ Stuur NU naar $_gekozenPersoonsNaam')
                            : '⚡ Stuur NU naar $_toonNaam')
                        : 'Plan en stuur 💕',
                    style: const TextStyle(fontSize: 16,
                        fontWeight: FontWeight.w800, color: kWhite))
                : _uploadProgress == null
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(
                            color: kWhite, strokeWidth: 3))
                    : Column(mainAxisSize: MainAxisSize.min, children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                              value: _uploadIndeterminate
                                  ? null : _uploadProgress,
                              minHeight: 6,
                              backgroundColor: kWhite.withOpacity(0.3),
                              valueColor: const
                                  AlwaysStoppedAnimation<Color>(kWhite))),
                        const SizedBox(height: 6),
                        Text(_uploadIndeterminate
                            ? 'Uploaden…'
                            : 'Upload bezig: '
                                '${((_uploadProgress ?? 0) * 100).round()}%',
                            style: const TextStyle(fontSize: 13,
                                fontWeight: FontWeight.w800, color: kWhite)),
                      ])),
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
    if (_type == 'stem') return _stemOpname();
    if (_type == 'video') return _videoPreviewKaart();
    return _bestandKiezen();
  }

  Widget _stemOpname() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: kPeachPale,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kPeachLight, width: 2)),
    child: Column(children: [
      GestureDetector(
        onTap: _isOpnemen ? _stopOpname : _startOpname,
        child: Container(width: 80, height: 80,
          decoration: BoxDecoration(
            color: _isOpnemen ? kRood : kRose,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(
              color: (_isOpnemen ? kRood : kRose).withOpacity(0.4),
              blurRadius: _isOpnemen ? 30 : 12,
              spreadRadius: _isOpnemen ? 6 : 0)]),
          child: Icon(_isOpnemen ? Icons.stop_rounded : Icons.mic_rounded,
              color: kWhite, size: 40),
        ),
      ),
      const SizedBox(height: 12),
      Text(_isOpnemen
          ? '🔴 Opname loopt: ${_opnameSeconden}s — tik om te stoppen'
          : _hebOpname
            ? '✓ Opname klaar (${_opnameSeconden}s)'
            : 'Tik op de microfoon om in te spreken',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
              color: _isOpnemen ? kRood : kBrown)),
      if (_hebOpname && !_isOpnemen) ...[
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _speelPreview,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(color: kPeach,
                borderRadius: BorderRadius.circular(20)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.play_arrow_rounded, color: kWhite, size: 20),
              SizedBox(width: 6),
              Text('Voorbeeld beluisteren',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                      color: kWhite)),
            ]),
          ),
        ),
      ],
    ]),
  );

  Future<void> _startOpname() async {
    try {
      if (!await _recorder.hasPermission()) {
        _toonFout('Geen toegang tot microfoon. Sta toe in de app-instellingen.');
        return;
      }

      String pad = '';
      if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        pad = '${dir.path}/opname_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }

      const encoder = kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc;
      await _recorder.start(const RecordConfig(encoder: encoder), path: pad);

      if (!mounted) return;
      setState(() {
        _isOpnemen = true;
        _opnameSeconden = 0;
        _hebOpname = false;
        _mediaBytes = null;
      });
      _opnameTimer?.cancel();
      _opnameTimer = Timer.periodic(const Duration(seconds: 1),
          (_) => setState(() => _opnameSeconden++));
    } catch (e) {
      _toonFout('Opname starten mislukt: $e');
    }
  }

  Future<void> _stopOpname() async {
    _opnameTimer?.cancel();
    String? pad;
    try {
      pad = await _recorder.stop();
    } catch (e) {
      _toonFout('Opname stoppen mislukt: $e');
    }
    if (!mounted) return;
    if (pad != null) {
      _opnamePad = pad;
      try {
        if (kIsWeb) {
          await _previewPlayer.setUrl(pad);
        } else {
          await _previewPlayer.setFilePath(pad);
        }
      } catch (_) {}
      setState(() {
        _isOpnemen = false;
        _hebOpname = true;
      });
    } else {
      setState(() => _isOpnemen = false);
    }
  }

  Future<void> _speelPreview() async {
    if (_opnamePad == null) return;
    try {
      await _previewPlayer.seek(Duration.zero);
      await _previewPlayer.play();
    } catch (e) {
      _toonFout('Afspelen mislukt: $e');
    }
  }

  Widget _bestandKiezen() => GestureDetector(
    onTap: _kiesMedia,
    child: Container(padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: kPeachPale,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kPeachLight, width: 2)),
      child: Center(child: Column(children: [
        if (_mediaBytes != null && _type == 'foto') ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(_mediaBytes!, height: 120, fit: BoxFit.cover))
        else Icon(_type == 'foto' ? Icons.add_photo_alternate_rounded
            : Icons.audiotrack_rounded, size: 40, color: kPeach),
        const SizedBox(height: 8),
        Text(_mediaNaam.isNotEmpty ? '✓ $_mediaNaam'
            : _type == 'foto' ? 'Tik om foto te kiezen'
            : 'Tik om MP3 lied te kiezen',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14,
                fontWeight: FontWeight.w700, color: kBrown)),
        if (_type == 'lied' && _mediaBytes != null) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _speelLiedPreview,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: kPeach,
                  borderRadius: BorderRadius.circular(20)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.play_arrow_rounded, color: kWhite, size: 20),
                SizedBox(width: 6),
                Text('Voorbeeld beluisteren',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                        color: kWhite)),
              ]),
            ),
          ),
        ],
      ])),
    ),
  );

  Future<void> _speelLiedPreview() async {
    if (_mediaBytes == null) return;
    try {
      await _previewPlayer.stop();
      await _previewPlayer.setAudioSource(
          _BytesAudioSource(_mediaBytes!, 'audio/mpeg'));
      await _previewPlayer.play();
    } catch (e) {
      _toonFout('Afspelen mislukt: $e');
    }
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

  Future<void> _kiesVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['mp4'], withData: true);
      if (result == null) return;
      final f = result.files.first;
      Uint8List? bytes = f.bytes;
      if (bytes == null && f.xFile != null) {
        try {
          bytes = await f.xFile!.readAsBytes();
        } catch (e) {
          debugPrint('xFile.readAsBytes faalde: $e');
        }
      }
      if (bytes == null) {
        _toonFout('Kon video niet laden. Probeer een ander bestand.');
        return;
      }
      if (bytes.lengthInBytes > 50 * 1024 * 1024) {
        _toonFout('Deze video is te groot. '
            'Kies een video van maximaal 50MB.');
        return;
      }
      setState(() {
        _mediaBytes = bytes;
        _mediaNaam = f.name;
        _type = 'video';
      });
    } catch (e) {
      _toonFout('Video kiezen niet mogelijk: $e');
    }
  }

  Widget _videoPreviewKaart() => GestureDetector(
    onTap: _kiesVideo,
    child: Container(padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: kPeachPale,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kPeachLight, width: 2)),
      child: Center(child: Column(children: [
        const Icon(Icons.movie_rounded, size: 40, color: kPeach),
        const SizedBox(height: 8),
        Text(_mediaBytes != null
            ? '🎥 Video klaar om te versturen'
            : 'Tik om een video te kiezen',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14,
                fontWeight: FontWeight.w700, color: kBrown)),
        const SizedBox(height: 4),
        Text(_mediaBytes != null
            ? '$_mediaNaam — ${_formatBytes(_mediaBytes!.lengthInBytes)}'
            : 'Alleen .mp4, max 50MB',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: kTextMuted)),
      ])),
    ),
  );

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)}MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
    return '$bytes B';
  }

  Future<void> _stuurHartje() async {
    toonZwevendeHartjes(context);
    try {
      final kringId = await DeviceModusService.huidigeKringIdMetFallback();
      if (kringId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Kring niet beschikbaar — log opnieuw in'),
            backgroundColor: Colors.red));
        }
        return;
      }
      // V9 2.11-a-3: vanNaam uit kring-context i.p.v. account-brede
      // apparaten-lookup. Tablet (alsOntvanger) stuurt namens de
      // dierbare (kring-naam); familielid stuurt namens zichzelf
      // (weergaveNaam uit eigen membership).
      // V9 2.13-b: legacy _ontvangerNaam als extra fallback vóór de
      // 'Je dierbare'-generieke tekst — voorkomt dat 'Je dierbare' in
      // Firestore terechtkomt wanneer een kring-naam is uitgezet of nog
      // niet is geladen, maar er wel een oud gebruikers-doc met naam is.
      final String vanNaam;
      if (widget.alsOntvanger) {
        if ((_kringNaam ?? '').isNotEmpty) {
          vanNaam = _kringNaam!;
        } else if ((_ontvangerNaam ?? '').isNotEmpty) {
          vanNaam = _ontvangerNaam!;
        } else {
          vanNaam = 'Je dierbare';
        }
      } else {
        vanNaam = (_mijnWeergaveNaam ?? '').isNotEmpty
            ? _mijnWeergaveNaam!
            : 'Iemand uit je kring';
      }

      // V9 2.10-a-2: drie target-modes — iedereen / lid (userUid) /
      // dierbare (ontvanger-apparaten van deze kring).
      List<String>? aanApparaatIds;
      List<String>? aanUserUids;
      if (_dierbareTarget) {
        aanApparaatIds = await _ontvangerApparaatIds(kringId);
        if (aanApparaatIds.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Nog geen apparaat ingesteld voor je dierbare.'),
              backgroundColor: kRood));
          }
          return;
        }
      } else if (_gekozenUserUid != null) {
        aanUserUids = [_gekozenUserUid!];
      }

      await FirebaseFirestore.instance.collection('momenten').add({
        'kringId': kringId,
        'vanNaam': vanNaam,
        'vanApparaatId': _mijnApparaatId,
        'vanApparaatModus': DeviceModusService.notifier.value ?? 'familie',
        'aanApparaatId': null,
        'aanApparaatIds': aanApparaatIds,
        'aanUserUids': aanUserUids,
        'aanPersoonsNaam': _gekozenPersoonsNaam,
        'type': 'hartje',
        'emoji': '💕',
        'mediaUrl': '',
        'bericht': '',
        'geplandOp': Timestamp.now(),
        'verstuurdOp': FieldValue.serverTimestamp(),
        'gezien': false,
        'testModus': _testModus,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Je hartje is verstuurd 💕'),
          backgroundColor: kGreen));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Versturen mislukt — probeer opnieuw'),
          backgroundColor: kRood));
      }
    }
  }

  Future<void> _verstuur() async {
    if (_type == 'tekst' && _berichtCtrl.text.trim().isEmpty) {
      _toonFout('Typ eerst een bericht'); return;
    }
    if (_type == 'stem' && !_hebOpname) {
      _toonFout('Neem eerst een stembericht op'); return;
    }
    if ((_type == 'foto' || _type == 'lied' || _type == 'video')
        && _mediaBytes == null) {
      _toonFout('Kies eerst een bestand'); return;
    }
    setState(() => _bezig = true);
    try {
      final kringId = await DeviceModusService.huidigeKringIdMetFallback();
      if (kringId == null) {
        if (mounted) {
          setState(() => _bezig = false);
          _toonFout('Kring niet beschikbaar — log opnieuw in');
        }
        return;
      }

      // V9 2.11-a-3: vanNaam uit kring-context (tablet = dierbare,
      // familielid = eigen weergaveNaam).
      // V9 2.13-b: legacy _ontvangerNaam als extra fallback vóór de
      // 'Je dierbare'-generieke tekst — zelfde patroon als direct-versturen.
      final String vanNaam;
      if (widget.alsOntvanger) {
        if ((_kringNaam ?? '').isNotEmpty) {
          vanNaam = _kringNaam!;
        } else if ((_ontvangerNaam ?? '').isNotEmpty) {
          vanNaam = _ontvangerNaam!;
        } else {
          vanNaam = 'Je dierbare';
        }
      } else {
        vanNaam = (_mijnWeergaveNaam ?? '').isNotEmpty
            ? _mijnWeergaveNaam!
            : 'Iemand uit je kring';
      }

      String mediaUrl = '';
      if (_type == 'stem' && _opnamePad != null) {
        Uint8List bytes;
        if (kIsWeb) {
          final response = await http.get(Uri.parse(_opnamePad!));
          if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
            throw Exception('Opname kon niet worden gelezen');
          }
          bytes = response.bodyBytes;
        } else {
          final file = File(_opnamePad!);
          if (!await file.exists()) {
            throw Exception('Opname-bestand niet gevonden');
          }
          bytes = await file.readAsBytes();
          if (bytes.isEmpty) {
            throw Exception('Opname-bestand is leeg');
          }
        }
        const ext = kIsWeb ? 'webm' : 'm4a';
        const contentType = kIsWeb ? 'audio/webm' : 'audio/mp4';
        final ref = FirebaseStorage.instance.ref()
            .child('momenten')
            .child('${DateTime.now().millisecondsSinceEpoch}.$ext');
        await ref.putData(bytes, SettableMetadata(contentType: contentType));
        mediaUrl = await ref.getDownloadURL();
      } else if (_type == 'video' && _mediaBytes != null) {
        final ref = FirebaseStorage.instance.ref()
            .child('momenten')
            .child('${DateTime.now().millisecondsSinceEpoch}.mp4');
        mediaUrl = await _uploadMetProgress(ref, _mediaBytes!, 'video/mp4');
      } else if (_mediaBytes != null) {
        final ext = _type == 'foto' ? 'jpg' : 'mp3';
        final ref = FirebaseStorage.instance.ref()
            .child('momenten')
            .child('${DateTime.now().millisecondsSinceEpoch}.$ext');
        await ref.putData(_mediaBytes!, SettableMetadata(
            contentType: _type == 'foto' ? 'image/jpeg' : 'audio/mpeg'));
        mediaUrl = await ref.getDownloadURL();
      }

      final geplandTijd = _testModus ? DateTime.now() : DateTime(
          _datum.year, _datum.month, _datum.day, _tijd.hour, _tijd.minute);

      // V9 2.10-a-2: drie target-modes — iedereen / lid (userUid) /
      // dierbare (ontvanger-apparaten van deze kring).
      List<String>? aanApparaatIds;
      List<String>? aanUserUids;
      if (_dierbareTarget) {
        aanApparaatIds = await _ontvangerApparaatIds(kringId);
        if (aanApparaatIds.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Nog geen apparaat ingesteld voor je dierbare.'),
              backgroundColor: kRood));
            setState(() => _bezig = false);
          }
          return;
        }
      } else if (_gekozenUserUid != null) {
        aanUserUids = [_gekozenUserUid!];
      }

      await FirebaseFirestore.instance.collection('momenten').add({
        'kringId': kringId,
        'vanNaam': vanNaam,
        'vanApparaatId': _mijnApparaatId,
        'vanApparaatModus':
            DeviceModusService.notifier.value ?? 'familie',
        'aanApparaatId': null,                  // legacy-veld; nieuwe sends via lijst
        'aanApparaatIds': aanApparaatIds,        // null of ontvanger-target
        'aanUserUids': aanUserUids,              // null of [lid.userUid]
        'aanPersoonsNaam': _gekozenPersoonsNaam, // voor historie/weergave
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
              ? '⚡ Direct verstuurd! Verschijnt nu bij ontvanger'
              : 'Moment gepland voor ${_formatDatum(_datum)} ${_formatTijd(_tijd)} 💕'),
          backgroundColor: kGreen));
        setState(() {
          _type = '';
          _berichtCtrl.clear();
          _mediaBytes = null;
          _mediaNaam = '';
          _hebOpname = false;
          _opnamePad = null;
          _opnameSeconden = 0;
        });
      }
    } catch (e) {
      _toonFout('Versturen mislukt: $e');
    } finally {
      if (mounted) {
        setState(() {
          _bezig = false;
          _uploadProgress = null;
          _uploadIndeterminate = false;
        });
      }
    }
  }

  /// Upload met live voortgang. Op web kan progress in één stap van 0 naar 100
  /// springen; dan tonen we een indeterminate balk (altijd zichtbare beweging).
  Future<String> _uploadMetProgress(
      Reference ref, Uint8List bytes, String contentType) async {
    setState(() {
      _uploadProgress = 0;
      _uploadIndeterminate = true;
    });
    final taak = ref.putData(bytes, SettableMetadata(contentType: contentType));
    final sub = taak.snapshotEvents.listen((snap) {
      if (snap.totalBytes > 0) {
        final p = snap.bytesTransferred / snap.totalBytes;
        if (mounted && p > 0 && p < 1) {
          setState(() {
            _uploadProgress = p;
            _uploadIndeterminate = false;
          });
        }
      }
    });
    try {
      await taak;
    } finally {
      await sub.cancel();
    }
    return ref.getDownloadURL();
  }

  void _toonFout(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.red));

  /// V9 2.10-a-2: membership-based persoon-kiezer.
  /// - Items: 'Iedereen in de kring' (null) + 'Voor je dierbare'
  ///   (sentinel '__dierbare__') + leden uit _leden (value = userUid).
  /// - Self-uitsluiting op auth.uid. Geen account-brede apparaat-bron
  ///   meer; oude apparaat-namen + cross-kring lekken zijn weg.
  /// - Naam uit Membership.weergaveNaam met fallback 'Kringlid'.
  static const String _dierbareSentinel = '__dierbare__';

  Widget _adresKeuze() {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    // V9 2.10-a-2-fix3: self-uitsluiting alleen aan de FAMILIE-kant.
    // Aan de ontvanger-kant draait de tablet met het eigenaar-account
    // (auth.uid == eigenaar.uid). Self-uitsluiten zou dan onterecht
    // de eigenaar (= een familielid dat juist bereikbaar moet zijn)
    // uit de kiezer weglaten. Het bestaande van==_mijnApparaatId-
    // filter aan ontvankant voorkomt self-echo.
    final andereLeden = _leden
        .where((m) => widget.alsOntvanger || m.userUid != authUid)
        .toList();
    // V9 2.10-a-2-fix2: 'Voor je dierbare'-entry heeft geen betekenis
    // aan de ontvanger-kant — de dierbare zit dáár al; sturen 'naar
    // de dierbare' zou self-target zijn. Alleen tonen aan de
    // familie-kant.
    final toonDierbare = !widget.alsOntvanger;
    String? huidigeWaarde;
    if (_dierbareTarget && toonDierbare) {
      huidigeWaarde = _dierbareSentinel;
    } else {
      // Defensief: als _dierbareTarget per ongeluk actief zou zijn
      // aan de ontvanger-kant, val terug op de userUid (of null).
      // Voorkomt dat de Dropdown een waarde toont die niet in z'n
      // items-lijst staat.
      huidigeWaarde = _gekozenUserUid;
    }
    final dierbareLabel = (_kringNaam ?? '').isNotEmpty
        ? 'Voor je dierbare (${_kringNaam!})'
        : 'Voor je dierbare';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(color: kWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kPeachLight, width: 2)),
      child: Row(children: [
        const Text('👥', style: TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(child: DropdownButton<String?>(
          value: huidigeWaarde,
          isExpanded: true,
          underline: const SizedBox(),
          hint: const Text('Naar wie?',
              style: TextStyle(color: kTextMuted)),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Iedereen in de kring',
                  style: TextStyle(color: kBrown,
                      fontWeight: FontWeight.w700)),
            ),
            if (toonDierbare) DropdownMenuItem<String?>(
              value: _dierbareSentinel,
              child: Text(dierbareLabel,
                  style: const TextStyle(color: kBrown,
                      fontWeight: FontWeight.w700)),
            ),
            ...andereLeden.map((m) {
              final naam = (m.weergaveNaam ?? '').trim();
              final label = naam.isEmpty ? 'Kringlid' : naam;
              return DropdownMenuItem<String?>(
                value: m.userUid,
                child: Text(label, style: const TextStyle(
                    color: kBrown, fontWeight: FontWeight.w700)),
              );
            }),
          ],
          onChanged: (val) => setState(() {
            if (val == null) {
              _gekozenUserUid = null;
              _dierbareTarget = false;
              _gekozenPersoonsNaam = null;
            } else if (val == _dierbareSentinel) {
              _gekozenUserUid = null;
              _dierbareTarget = true;
              _gekozenPersoonsNaam = (_kringNaam ?? '').isNotEmpty
                  ? _kringNaam
                  : 'Je dierbare';
            } else {
              _gekozenUserUid = val;
              _dierbareTarget = false;
              final lid = _leden.firstWhere(
                  (m) => m.userUid == val,
                  orElse: () => Membership(
                      userUid: val, rol: AccountRol.gast,
                      gejoindOp: DateTime.now()));
              final naam = (lid.weergaveNaam ?? '').trim();
              _gekozenPersoonsNaam = naam.isEmpty ? 'Kringlid' : naam;
            }
          }),
        )),
      ]),
    );
  }

  Widget _typeKnop(String emoji, String label, String waarde) =>
    Expanded(child: GestureDetector(
      onTap: () => setState(() {
        _type = _type == waarde ? '' : waarde;
        _mediaBytes = null;
        _mediaNaam = '';
        _hebOpname = false;
        _opnamePad = null;
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

  /// Actie-tegel met dezelfde styling als _typeKnop, maar met een vrije onTap
  /// en een widget als icoon (voor de Video-placeholder en het pulserende
  /// Hartje). Nooit "geselecteerd" — dus altijd witte achtergrond.
  Widget _actieTegel({required Widget icoon, required String label,
      required VoidCallback onTap}) =>
    Expanded(child: GestureDetector(
      onTap: onTap,
      child: Container(padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: kWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kPeachLight, width: 2)),
        child: Column(children: [
          icoon,
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 13,
              fontWeight: FontWeight.w800, color: kBrown)),
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
// AGENDA TAB
// ════════════════════════════════════════════════════════════
class AgendaTab extends StatelessWidget {
  /// V9 2.17: perspectief-vlag. Default false = familie-kant (bestaand
  /// gedrag). true = ontvanger-kant, waar het uitleg-tekstje over 'via
  /// Instellingen → Momenten beheren' wordt verborgen — de ontvanger
  /// heeft dat menu-item namelijk niet.
  final bool alsOntvanger;
  const AgendaTab({super.key, this.alsOntvanger = false});

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
          if (!alsOntvanger) Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kPeachPale,
              borderRadius: BorderRadius.circular(10)),
            child: const Text(
              '💡 Tijd, datum en het geluidje van een moment pas je aan '
              'via Instellingen → Momenten beheren. Daar kun je ook je '
              'eigen stem of een liedje toevoegen.',
              style: TextStyle(fontSize: 12, color: kTextMuted)),
          ),
          const _SectieTitel('🔁 ELKE DAG'),
          FutureBuilder<String?>(
            future: DeviceModusService.huidigeKringIdMetFallback(),
            builder: (ctx, kringSnap) {
              final kringId = kringSnap.data;
              if (kringId == null) return const SizedBox();
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('dagelijkse_momenten')
                    .where('kringId', isEqualTo: kringId)
                    .where('actief', isEqualTo: true).snapshots(),
                builder: (ctx, snap) {
                  if (!snap.hasData) return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                        child: CircularProgressIndicator(color: kPeach)));
                  final docs = snap.data!.docs.toList();
                  if (docs.isEmpty) {
                    return _leeg('Nog geen dagelijkse momenten');
                  }
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
              );
            },
          ),
          const SizedBox(height: 20),
          const _SectieTitel('📅 GEPLAND'),
          FutureBuilder<String?>(
            future: DeviceModusService.huidigeKringIdMetFallback(),
            builder: (ctx, kringSnap) {
              final kringId = kringSnap.data;
              if (kringId == null) return const SizedBox();
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('gepland_momenten')
                    .where('kringId', isEqualTo: kringId)
                    .where('actief', isEqualTo: true).snapshots(),
                builder: (ctx, eenmaligSnap) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('momenten')
                        .where('kringId', isEqualTo: kringId)
                        .where('gezien', isEqualTo: false).snapshots(),
                    builder: (ctx, momentenSnap) {
                      if (!eenmaligSnap.hasData || !momentenSnap.hasData) {
                        return const SizedBox();
                      }
                      final nu = DateTime.now();
                      final items = <MapEntry<DateTime, Widget>>[];
                      for (final doc in eenmaligSnap.data!.docs) {
                        final g = ((doc.data() as Map)['geplandOp']
                            as Timestamp?)?.toDate();
                        if (g == null || !g.isAfter(nu)) continue;
                        items.add(MapEntry(g, _EenmaligItem(doc: doc)));
                      }
                      for (final doc in momentenSnap.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        if (data['testModus'] == true) continue;
                        final g = (data['geplandOp'] as Timestamp?)?.toDate();
                        if (g == null || !g.isAfter(nu)) continue;
                        items.add(MapEntry(g, _GeplandItem(doc: doc)));
                      }
                      if (items.isEmpty) {
                        return _leeg('Geen geplande momenten');
                      }
                      items.sort((a, b) => a.key.compareTo(b.key));
                      return Column(
                          children: items.map((e) => e.value).toList());
                    },
                  );
                },
              );
            },
          ),
          const SizedBox(height: 20),
          const _SectieTitel('✓ VERSTUURD'),
          FutureBuilder<String?>(
            future: DeviceModusService.huidigeKringIdMetFallback(),
            builder: (ctx, kringSnap) {
              final kringId = kringSnap.data;
              if (kringId == null) return const SizedBox();
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('momenten')
                    .where('kringId', isEqualTo: kringId)
                    .where('gezien', isEqualTo: true).snapshots(),
                builder: (ctx, snap) {
                  if (!snap.hasData) return const SizedBox();
                  final docs = snap.data!.docs.toList();
                  if (docs.isEmpty) {
                    return _leeg('Nog geen verstuurde momenten');
                  }
                  return Column(children: docs.take(5).map((d) =>
                    _GeplandItem(doc: d, isHistorie: true)).toList());
                },
              );
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
        fontWeight: FontWeight.w800, color: kTextMuted, letterSpacing: 0.8)));
}

class _DagelijksItem extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  const _DagelijksItem({required this.doc});
  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final audioType = d['aangepasteAudioType'] as String? ?? '';
    final audioLabel = audioType == 'stem' ? '🎤 Eigen stem'
        : audioType == 'mp3' ? '🎵 Eigen MP3'
        : '🔔 Standaard geluid';
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
          Text(d['label'] ?? 'Moment', style: const TextStyle(fontSize: 14,
              fontWeight: FontWeight.w800, color: kBrown)),
          Text('Elke dag • $audioLabel',
              style: const TextStyle(fontSize: 11, color: kTextMuted)),
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

class _EenmaligItem extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  const _EenmaligItem({required this.doc});

  String _formatDatumTijd(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-'
      '${d.month.toString().padLeft(2, '0')} • '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final geplandOp = (d['geplandOp'] as Timestamp?)?.toDate();
    final audioType = d['aangepasteAudioType'] as String? ?? '';
    final audioLabel = audioType == 'stem' ? '🎤 Eigen stem'
        : audioType == 'mp3' ? '🎵 Eigen MP3'
        : '🔔 Standaard geluid';
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
          Text(d['label'] ?? 'Moment', style: const TextStyle(fontSize: 14,
              fontWeight: FontWeight.w800, color: kBrown)),
          Text(geplandOp != null
              ? '${_formatDatumTijd(geplandOp)} • $audioLabel'
              : audioLabel,
              style: const TextStyle(fontSize: 11, color: kTextMuted)),
        ])),
        IconButton(icon: const Icon(Icons.delete_outline_rounded,
            color: Colors.red),
          onPressed: () async {
            final kringId =
                await DeviceModusService.huidigeKringIdMetFallback();
            if (kringId != null) {
              await DagelijksAudioService.reset(
                  kringId: kringId, momentId: doc.id,
                  collectie: 'gepland_momenten');
            }
            await doc.reference.update({'actief': false});
          }),
      ]),
    );
  }
}

class _AudioInstelDialog extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  const _AudioInstelDialog({required this.doc});
  @override
  State<_AudioInstelDialog> createState() => _AudioInstelDialogState();
}

class _AudioInstelDialogState extends State<_AudioInstelDialog> {
  final _recorder = AudioRecorder();
  final _previewPlayer = AudioPlayer();
  Timer? _opnameTimer;

  bool _isOpnemen = false;
  int _opnameSeconden = 0;
  String? _opnamePad;
  Uint8List? _opnameBytes;

  Uint8List? _mp3Bytes;
  String _mp3Naam = '';

  bool _bezig = false;
  String? _huidigeUrl;
  String? _huidigType;
  Uint8List? _huidigeBytes;

  /// V9 2.19: guard tegen dubbel-klikken op de preview-knoppen. Wordt in
  /// de play-methoden gezet naar true bij binnenkomst en via try/finally
  /// altijd weer teruggezet naar false — kan dus nooit blijven hangen.
  bool _laadt = false;

  @override
  void initState() {
    super.initState();
    final d = widget.doc.data() as Map<String, dynamic>;
    _huidigeUrl = d['aangepasteAudioUrl'] as String?;
    _huidigType = d['aangepasteAudioType'] as String?;
    _preloadHuidige();
  }

  Future<void> _preloadHuidige() async {
    if ((_huidigeUrl ?? '').isEmpty) return;
    try {
      final resp = await http.get(Uri.parse(_huidigeUrl!));
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty && mounted) {
        _huidigeBytes = resp.bodyBytes;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _opnameTimer?.cancel();
    _recorder.dispose();
    _previewPlayer.dispose();
    super.dispose();
  }

  Future<void> _startOpname() async {
    try {
      if (!await _recorder.hasPermission()) {
        _toonFout('Geen toegang tot microfoon. '
            'Sta toe in de app-instellingen.');
        return;
      }

      String pad = '';
      if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        pad = '${dir.path}/dagelijks_opname_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }

      const encoder = kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc;
      await _recorder.start(const RecordConfig(encoder: encoder), path: pad);

      if (!mounted) return;
      setState(() {
        _isOpnemen = true;
        _opnameSeconden = 0;
        _opnamePad = null;
        _opnameBytes = null;
      });
      _opnameTimer?.cancel();
      _opnameTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _opnameSeconden++);
        if (_opnameSeconden >= 30) _stopOpname();
      });
    } catch (e) {
      _toonFout('Opname starten mislukt: $e');
    }
  }

  Future<void> _stopOpname() async {
    _opnameTimer?.cancel();
    String? pad;
    try {
      pad = await _recorder.stop();
    } catch (e) {
      _toonFout('Opname stoppen mislukt: $e');
    }
    if (!mounted) return;
    if (pad == null) {
      setState(() => _isOpnemen = false);
      return;
    }

    Uint8List? bytes;
    try {
      if (kIsWeb) {
        final response = await http.get(Uri.parse(pad));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          bytes = response.bodyBytes;
        }
      } else {
        final file = File(pad);
        if (await file.exists()) {
          final raw = await file.readAsBytes();
          if (raw.isNotEmpty) bytes = raw;
        }
      }
    } catch (_) {}

    if (!mounted) return;
    if (bytes == null) {
      _toonFout('Opname kon niet worden gelezen');
      setState(() => _isOpnemen = false);
      return;
    }

    try {
      if (kIsWeb) {
        await _previewPlayer.setUrl(pad);
      } else {
        await _previewPlayer.setFilePath(pad);
      }
    } catch (_) {}

    setState(() {
      _isOpnemen = false;
      _opnamePad = pad;
      _opnameBytes = bytes;
    });
  }

  Future<void> _kiesMp3() async {
    try {
      final result = await FilePicker.platform.pickFiles(
          type: FileType.audio, withData: true);
      if (result == null) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        _toonFout('Bestand kon niet worden gelezen');
        return;
      }
      if (bytes.length > 5 * 1024 * 1024) {
        _toonFout('MP3 te groot (max 5MB)');
        return;
      }
      setState(() {
        _mp3Bytes = bytes;
        _mp3Naam = file.name;
      });
    } catch (e) {
      _toonFout('MP3 kiezen mislukt: $e');
    }
  }

  /// V9 2.18: robuuste mime-bepaling voor huidige aangepasteAudio.
  /// Alleen op web gebruikt (native leidt formaat af uit de HTTP Content-
  /// Type-header). Uri.decodeFull zorgt dat URL-encoded paden ook goed
  /// worden gecheckt; fallback audio/mp4 sluit aan bij recente uploads
  /// (aacLc via V8-fix van juli 2026).
  String _bepaalMime(String url, String? type) {
    if (type == 'mp3') return 'audio/mpeg';
    final decoded = Uri.decodeFull(url).toLowerCase();
    if (decoded.contains('.m4a')) return 'audio/mp4';
    if (decoded.contains('.webm')) return 'audio/webm';
    return 'audio/mp4';
  }

  Future<void> _speelOpnamePreview() async {
    if (_laadt) return;
    _laadt = true;
    try {
      // V9 2.19: eerst stoppen — anders botst de nieuwe setUrl/setFilePath
      // met een eventuele pre-warm uit _stopOpname of een vorige preview-
      // klik → AbortError op web, subtiele glitches op native.
      await _previewPlayer.stop();
      if (kIsWeb) {
        if (_opnameBytes == null) {
          _toonFout('Geen opname beschikbaar om af te spelen');
          return;
        }
        // Web: data-URI i.p.v. blob-URL uit _stopOpname zodat afspelen
        // ook op iOS Safari betrouwbaar werkt. Web-opnames zijn opus in
        // webm-container (zie _startOpname bij kIsWeb).
        final dataUri = Uri.dataFromBytes(
            _opnameBytes!, mimeType: 'audio/webm').toString();
        await _previewPlayer.setUrl(dataUri);
      } else {
        if (_opnamePad == null) {
          _toonFout('Geen opname beschikbaar om af te spelen');
          return;
        }
        // Native: opnames zijn aacLc in m4a-container. setFilePath opnieuw
        // aanroepen zodat de player altijd een geldig source heeft, ook
        // als de pre-warm in _stopOpname ooit faalde.
        await _previewPlayer.setFilePath(_opnamePad!);
      }
      await _previewPlayer.seek(Duration.zero);
      await _previewPlayer.play();
    } catch (e) {
      _toonFout('Afspelen mislukt: $e');
    } finally {
      _laadt = false;
    }
  }

  Future<void> _speelHuidigePreview() async {
    if (_laadt) return;
    if ((_huidigeUrl ?? '').isEmpty) return;
    _laadt = true;
    try {
      // V9 2.19: eerst stoppen — voorkomt AbortError op web wanneer de
      // player nog een vorige source aan het laden was (bijv. pre-warm
      // uit _stopOpname of een vorige preview-klik). Op native is dit
      // een safe no-op op idle-state.
      await _previewPlayer.stop();
      if (kIsWeb) {
        // WEB-pad: bytes preloaden (behoudt CORS-workaround uit V8.6) en
        // omzetten naar data-URI zodat afspelen ook op iOS Safari werkt.
        // Vervangt het oude _BytesAudioSource-pad dat browsers niet
        // ondersteunen (HTMLAudioElement accepteert geen byte-streams).
        if (_huidigeBytes == null) {
          final resp = await http.get(Uri.parse(_huidigeUrl!));
          if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
            _toonFout('Audio kon niet worden geladen (${resp.statusCode})');
            return;
          }
          _huidigeBytes = resp.bodyBytes;
        }
        final mime = _bepaalMime(_huidigeUrl ?? '', _huidigType);
        final dataUri = Uri.dataFromBytes(
            _huidigeBytes!, mimeType: mime).toString();
        await _previewPlayer.setUrl(dataUri);
      } else {
        // NATIVE-pad: setUrl direct met de Firebase Storage-URL. Just_audio
        // streamt via ExoPlayer/AVFoundation en gebruikt de HTTP Content-
        // Type-header van Storage (die we bij upload correct hebben gezet
        // in DagelijksAudioService — audio/mp4 voor m4a, audio/mpeg voor
        // mp3, audio/webm voor web-uploads). Geen mime-guess-work uit
        // URL-strings meer, geen bytes-omweg — de HTTP-header is
        // autoritatief. Zelfde flow als tablet_scherm._toonPopup gebruikt
        // voor stem/lied-berichten (bewezen betrouwbaar op native).
        await _previewPlayer.setUrl(_huidigeUrl!);
      }
      await _previewPlayer.play();
    } catch (e) {
      _toonFout('Audio kan niet worden afgespeeld: $e');
    } finally {
      _laadt = false;
    }
  }

  Future<void> _opslaanOpname() async {
    if (_opnameBytes == null) return;
    final kringId = await DeviceModusService.huidigeKringIdMetFallback();
    if (kringId == null) return;
    setState(() => _bezig = true);
    final ok = await DagelijksAudioService.upload(
      kringId: kringId,
      momentId: widget.doc.id,
      bytes: _opnameBytes!,
      type: 'stem',
      collectie: widget.doc.reference.parent.id,
    );
    if (!mounted) return;
    setState(() => _bezig = false);
    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✓ Stem-opname opgeslagen'),
        backgroundColor: kGreen));
    } else {
      _toonFout('Opslaan mislukt — probeer opnieuw');
    }
  }

  Future<void> _opslaanMp3() async {
    if (_mp3Bytes == null) return;
    final kringId = await DeviceModusService.huidigeKringIdMetFallback();
    if (kringId == null) return;
    setState(() => _bezig = true);
    final ok = await DagelijksAudioService.upload(
      kringId: kringId,
      momentId: widget.doc.id,
      bytes: _mp3Bytes!,
      type: 'mp3',
      collectie: widget.doc.reference.parent.id,
    );
    if (!mounted) return;
    setState(() => _bezig = false);
    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✓ MP3 opgeslagen'), backgroundColor: kGreen));
    } else {
      _toonFout('Opslaan mislukt — probeer opnieuw');
    }
  }

  Future<void> _zetTerugNaarBel() async {
    final kringId = await DeviceModusService.huidigeKringIdMetFallback();
    if (kringId == null) return;
    setState(() => _bezig = true);
    final ok = await DagelijksAudioService.reset(
        kringId: kringId, momentId: widget.doc.id,
        collectie: widget.doc.reference.parent.id);
    if (!mounted) return;
    setState(() => _bezig = false);
    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✓ Terug naar standaard geluid'),
        backgroundColor: kGreen));
    } else {
      _toonFout('Verwijderen mislukt — probeer opnieuw');
    }
  }

  void _toonFout(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.red));

  @override
  Widget build(BuildContext context) {
    final d = widget.doc.data() as Map<String, dynamic>;
    final label = d['label'] ?? 'Moment';
    final heeftHuidig = (_huidigeUrl ?? '').isNotEmpty;
    final huidigLabel = _huidigType == 'stem' ? '🎤 Eigen stem'
        : _huidigType == 'mp3' ? '🎵 Eigen MP3'
        : '🔔 Standaard geluid';

    return Dialog(backgroundColor: kCream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Eigen stem of liedje voor "$label"',
                style: const TextStyle(fontSize: 18,
                    fontWeight: FontWeight.w900, color: kBrown)),
            const SizedBox(height: 4),
            Text('Op dit moment: $huidigLabel',
                style: const TextStyle(fontSize: 12, color: kTextMuted)),
            if (heeftHuidig) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _speelHuidigePreview,
                child: Container(padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: kPeachPale,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kPeach, width: 1.5)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.play_arrow_rounded, color: kPeach, size: 18),
                    SizedBox(width: 4),
                    Text('Beluister huidige',
                        style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w800, color: kPeach)),
                  ]))),
            ],
            const SizedBox(height: 20),

            // STEM OPNAME
            const Text('🎤 Neem zelf op',
                style: TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w800, color: kBrown)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _bezig ? null
                  : (_isOpnemen ? _stopOpname : _startOpname),
              child: Container(width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _isOpnemen ? kRood : kPeach,
                  borderRadius: BorderRadius.circular(12)),
                child: Center(child: Text(
                  _isOpnemen
                      ? '🔴 Stoppen (${_opnameSeconden}s / 30s)'
                      : (_opnameBytes != null
                          ? '✓ Opname klaar (${_opnameSeconden}s) — tik om opnieuw'
                          : 'Start opname (max 30 sec)'),
                  style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w800, color: kWhite))),
              ),
            ),
            if (_opnameBytes != null && !_isOpnemen) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: _speelOpnamePreview,
                  child: Container(padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(color: kWhite,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kPeach, width: 1.5)),
                    child: const Center(child: Row(mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow_rounded, color: kPeach, size: 18),
                        SizedBox(width: 4),
                        Text('Voorbeeld', style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w800, color: kPeach)),
                      ]))),
                )),
                const SizedBox(width: 8),
                Expanded(child: GestureDetector(
                  onTap: _bezig ? null : _opslaanOpname,
                  child: Container(padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                        color: _bezig ? kPeachLight : kGreen,
                        borderRadius: BorderRadius.circular(10)),
                    child: const Center(child: Text('Opslaan',
                        style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w800, color: kWhite)))),
                )),
              ]),
            ],
            const SizedBox(height: 20),

            // MP3 UPLOAD
            const Text('🎵 Upload MP3',
                style: TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w800, color: kBrown)),
            const SizedBox(height: 4),
            const Text('Houd MP3 onder ~30 seconden — max 5MB',
                style: TextStyle(fontSize: 11, color: kTextMuted)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _bezig ? null : _kiesMp3,
              child: Container(width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(color: kPeachPale,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kPeach, width: 1.5)),
                child: Center(child: Text(
                  _mp3Naam.isNotEmpty
                      ? '✓ $_mp3Naam — tik om ander te kiezen'
                      : 'Kies MP3-bestand',
                  style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w800, color: kBrown))),
              ),
            ),
            if (_mp3Bytes != null) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _bezig ? null : _opslaanMp3,
                child: Container(width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                      color: _bezig ? kPeachLight : kGreen,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Center(child: Text('Opslaan MP3',
                      style: TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w800, color: kWhite)))),
              ),
            ],
            const SizedBox(height: 20),

            // TERUG NAAR STANDAARD
            if (heeftHuidig)
              GestureDetector(
                onTap: _bezig ? null : _zetTerugNaarBel,
                child: Container(width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(color: kWhite,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kPeachLight, width: 1.5)),
                  child: const Center(child: Text(
                      '🔔 Terug naar standaard geluid',
                      style: TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w800, color: kBrown)))),
              ),
            const SizedBox(height: 12),
            Center(child: TextButton(
              onPressed: _bezig ? null : () => Navigator.pop(context),
              child: const Text('Sluiten',
                  style: TextStyle(color: kTextMuted,
                      fontWeight: FontWeight.w700)))),
          ]),
        ),
      ),
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
      case 'hartje': return '💕';
      case 'video': return '🎥';
      default: return '⭐';
    }
  }
  String _labelVoorType(String type) {
    switch (type) {
      case 'foto': return 'Foto bericht';
      case 'stem': return 'Stem bericht';
      case 'lied': return 'Liedje';
      case 'tekst': return 'Tekst bericht';
      case 'hartje': return 'Hartje';
      case 'video': return 'Video';
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
  String? _ontvangerNaam;       // legacy: uit gebruikers/{uid}
  String? _kringNaam;            // V9 2.4-a-3: uit actieve kring-doc
  String? _kringId;
  StreamSubscription<Kring?>? _actieveKringSub;

  /// V9 2.4-a-3: kring-doc primair, gebruikers/{uid} als fallback,
  /// 'je dierbare' als ultieme default.
  String get _toonNaam {
    if ((_kringNaam ?? '').isNotEmpty) return _kringNaam!;
    if ((_ontvangerNaam ?? '').isNotEmpty) return _ontvangerNaam!;
    return 'je dierbare';
  }

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirebaseFirestore.instance.collection('gebruikers').doc(uid).get()
          .then((doc) {
        if (!mounted) return;
        setState(() {
          _ontvangerNaam = doc.data()?['ontvangerNaam'] as String?;
        });
      });
    }
    DeviceModusService.huidigeKringIdMetFallback().then((id) {
      if (!mounted) return;
      setState(() => _kringId = id);
    });
    // V9 2.2b: kring-switch updatet _kringId zodat de StreamBuilder
    // van notities automatisch herlaadt op de nieuwe kring.
    DeviceModusService.actieveKringNotifier.addListener(_opKringWijziging);
    // V9 2.4-a-3: actieve-kring-doc voor naam (overschrijft fallback).
    _actieveKringSub = KringService.actieveKringStream().listen((kring) {
      if (!mounted) return;
      setState(() {
        _kringNaam = (kring != null && kring.naam.isNotEmpty)
            ? kring.naam : null;
      });
    });
  }

  @override
  void dispose() {
    DeviceModusService.actieveKringNotifier
        .removeListener(_opKringWijziging);
    _actieveKringSub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _opKringWijziging() {
    final nieuwe = DeviceModusService.actieveKringNotifier.value;
    if (nieuwe == null || nieuwe == _kringId) return;
    if (mounted) setState(() => _kringId = nieuwe);
  }

  @override
  Widget build(BuildContext context) {
    final kringId = _kringId;
    return Padding(padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Notities',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
                color: kBrown)),
        const SizedBox(height: 8),
        const Text('Deel observaties met andere kringleden en mantelzorgers',
            style: TextStyle(fontSize: 13, color: kTextMuted)),
        const SizedBox(height: 16),
        TextField(controller: _ctrl, maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Bijv. "Vandaag genoot moeder erg van de muziek"',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            filled: true, fillColor: kWhite)),
        const SizedBox(height: 10),
        GestureDetector(onTap: _opslaan,
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
        Expanded(child: kringId == null ? const SizedBox()
          : StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('notities')
              .where('kringId', isEqualTo: kringId).snapshots(),
          builder: (ctx, snap) {
            if (!snap.hasData) return const Center(
                child: CircularProgressIndicator(color: kPeach));
            final docs = snap.data!.docs.toList()
              ..sort((a, b) {
                final ta = (a.data() as Map)['aangemaaktOp'] as Timestamp?;
                final tb = (b.data() as Map)['aangemaaktOp'] as Timestamp?;
                if (ta == null && tb == null) return 0;
                if (ta == null) return 1;
                if (tb == null) return -1;
                return tb.compareTo(ta);
              });
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
                final vanNaam = d['vanNaam'] as String? ?? 'Kringlid';
                final ts = d['aangemaaktOp'] as Timestamp?;
                final header = ts != null
                    ? '$vanNaam · ${_kortDatumTijdNl(ts.toDate())}'
                    : vanNaam;
                return Container(margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: kWhite,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kPeachLight, width: 1.5)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(header, style: const TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w600, color: kTextMuted)),
                      const SizedBox(height: 6),
                      Text(d['tekst'] ?? '',
                          style: const TextStyle(fontSize: 13,
                              color: kBrown, height: 1.4)),
                    ]));
              });
          },
        )),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kPeachPale,
            borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Text('🔒', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Notities zijn alleen zichtbaar voor familieleden en '
              'mantelzorgers. $_toonNaam ziet deze niet.',
              style: const TextStyle(fontSize: 11,
                  color: kBrownLight, height: 1.4))),
          ]),
        ),
      ]),
    );
  }

  Future<void> _opslaan() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final kringId = await DeviceModusService.huidigeKringIdMetFallback();
    if (uid == null || kringId == null || _ctrl.text.trim().isEmpty) return;
    final familieDoc = await FirebaseFirestore.instance
        .collection('gebruikers').doc(uid).get();
    final familieNaam = familieDoc.data()?['familieNaam'] ?? 'Kringlid';
    await FirebaseFirestore.instance.collection('notities').add({
      'kringId': kringId,
      'vanNaam': familieNaam,
      'tekst': _ctrl.text.trim(),
      'aangemaaktOp': FieldValue.serverTimestamp(),
    });
    _ctrl.clear();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notitie opgeslagen'),
            backgroundColor: kGreen));
  }

  String _kortDatumTijdNl(DateTime d) {
    const m = ['jan', 'feb', 'mrt', 'apr', 'mei', 'jun',
               'jul', 'aug', 'sep', 'okt', 'nov', 'dec'];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${m[d.month - 1]}, $hh:$mm';
  }
}

// ════════════════════════════════════════════════════════════
// INSTELLINGEN TAB
// ════════════════════════════════════════════════════════════
class InstellingenTab extends StatefulWidget {
  final bool alsOntvanger;
  const InstellingenTab({super.key, this.alsOntvanger = false});
  @override
  State<InstellingenTab> createState() => _InstellingenTabState();
}

class _InstellingenTabState extends State<InstellingenTab> {
  String? _ontvangerNaam;       // legacy: uit gebruikers/{uid}
  String? _kringNaam;            // V9 2.4-a-3: uit actieve kring-doc
  bool _isAccountMaker = false;
  bool _benIkEigenaar = false;   // V9 eigenaar-check: kring.eigenaarUid == authUid
  String? _huidigeOntvangerModus;
  // V9 2.3a: kring-switcher state
  List<Kring>? _kringen;
  String? _huidigeKringId;
  StreamSubscription<Kring?>? _actieveKringSub;
  // V9 2.12-a-2: e-mailverificatie-status (zacht — alleen tonen).
  bool _emailVerified = false;
  bool _bezigVerstuur = false;
  bool _bezigVerifieer = false;

  /// V9 2.4-a-3: kring-doc primair, gebruikers/{uid} fallback,
  /// 'je dierbare' als ultieme default.
  String get _toonNaam {
    if ((_kringNaam ?? '').isNotEmpty) return _kringNaam!;
    if ((_ontvangerNaam ?? '').isNotEmpty) return _ontvangerNaam!;
    return 'je dierbare';
  }

  @override
  void initState() {
    super.initState();
    // V9 2.12-a-2: synchroon emailVerified-status uitlezen voor de
    // banner; bij elke handmatige verversing herzet _controleerVerificatie.
    _emailVerified =
        FirebaseAuth.instance.currentUser?.emailVerified ?? false;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance.collection('gebruikers').doc(uid).get()
        .then((doc) {
      if (!mounted) return;
      setState(() {
        _ontvangerNaam = doc.data()?['ontvangerNaam'] as String?;
      });
    });
    if (!widget.alsOntvanger) {
      DeviceModusService.krijgApparaatId().then((apparaatId) async {
        final ok = await ApparaatService.isAccountMaker(
            familieUid: uid, apparaatId: apparaatId);
        if (!mounted) return;
        setState(() => _isAccountMaker = ok);
        if (ok) {
          // V9 multi-kring fix: kringId is verplicht in de service. We
          // pakken hier de notifier-waarde (synchroon, geen race met
          // _laadKringen). Bij ontbrekende kring → service geeft null
          // → _huidigeOntvangerModus blijft null (geen "(huidig)"-label).
          final kringId = DeviceModusService.actieveKringNotifier.value ?? '';
          final huidig = await ApparaatService
              .krijgWeergaveModusVoorOntvangers(uid, kringId);
          if (mounted) setState(() => _huidigeOntvangerModus = huidig);
        }
      });
      _laadKringen();
      DeviceModusService.actieveKringNotifier.addListener(_opKringSwitch);
    }
    // V9 2.4-a-3: naam uit actieve kring-doc (wisselt mee bij switch).
    // V9 eigenaar-gating: óók eigenaarschap evalueren en — bij eigenaar —
    // de huidige ontvanger-weergaveModus herladen, zodat de "(huidig)"-
    // label in de modus-dialog meeschuift bij kring-switch. Geen extra
    // Firestore-read voor eigenaarschap: kring.eigenaarUid zit al in
    // het gestreamde object.
    _actieveKringSub = KringService.actieveKringStream().listen((kring) async {
      if (!mounted) return;
      final mijnUid = FirebaseAuth.instance.currentUser?.uid;
      final eigenaar = kring != null
          && mijnUid != null
          && mijnUid.isNotEmpty
          && kring.eigenaarUid == mijnUid;
      setState(() {
        _kringNaam = (kring != null && kring.naam.isNotEmpty)
            ? kring.naam : null;
        _benIkEigenaar = eigenaar;
        if (!eigenaar) _huidigeOntvangerModus = null;
      });
      if (eigenaar) {
        // V9 multi-kring fix: kring en mijnUid zijn hier gepromoot naar
        // non-null door de eigenaar-check hierboven.
        final huidig = await ApparaatService
            .krijgWeergaveModusVoorOntvangers(mijnUid, kring.id);
        if (mounted) setState(() => _huidigeOntvangerModus = huidig);
      }
    });
  }

  @override
  void dispose() {
    DeviceModusService.actieveKringNotifier.removeListener(_opKringSwitch);
    _actieveKringSub?.cancel();
    super.dispose();
  }

  void _opKringSwitch() {
    // Notifier triggert bij elke zetActieveKring — herlaad de lijst
    // (nieuw aangemaakte kring verschijnt, huidige markering schuift).
    _laadKringen();
  }

  Future<void> _laadKringen() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final kringen = await KringService.mijnKringen(uid);
    final huidig = await DeviceModusService.krijgActieveKring();
    if (!mounted) return;
    setState(() {
      _kringen = kringen;
      _huidigeKringId = huidig;
    });
  }

  Future<void> _switchNaarKring(String kringId) async {
    if (kringId == _huidigeKringId) return;
    await DeviceModusService.zetActieveKring(kringId);
    // _opKringSwitch wordt vanzelf getriggerd via notifier; bovendien
    // herstart _FamilieSchermState._herstartListeners (2.2b) de
    // kringId-afhankelijke streams.
  }

  /// V9 2.12-a-2: stuurt een verificatie-mail naar het huidige account.
  /// Faalt silent bij netwerk/quota — toon snackbar met uitkomst.
  Future<void> _verstuurVerificatieMail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _bezigVerstuur = true);
    try {
      await user.sendEmailVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Mail verstuurd. Kijk in je inbox (en spam).'),
        backgroundColor: kPeach));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Versturen mislukt — probeer opnieuw.'),
        backgroundColor: kRood));
    } finally {
      if (mounted) setState(() => _bezigVerstuur = false);
    }
  }

  /// V9 2.12-a-2: vraagt Firebase om de huidige user-status opnieuw
  /// op te halen (reload) en update de emailVerified-banner.
  Future<void> _controleerVerificatie() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _bezigVerifieer = true);
    try {
      await user.reload();
      final geverifieerd =
          FirebaseAuth.instance.currentUser?.emailVerified ?? false;
      if (!mounted) return;
      setState(() => _emailVerified = geverifieerd);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(geverifieerd
            ? 'Gelukt — je e-mailadres is bevestigd ✓'
            : 'Nog niet bevestigd — klik eerst op de link in de e-mail.'),
        backgroundColor: geverifieerd ? kGreen : kPeach));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Controle mislukt — probeer opnieuw.'),
        backgroundColor: kRood));
    } finally {
      if (mounted) setState(() => _bezigVerifieer = false);
    }
  }

  /// V9 2.12-a-2-fix: alleen de niet-bevestigd-kaart. De bevestigd-
  /// variant is weggehaald — bij _emailVerified == true verbergt de
  /// build deze sectie helemaal. Een constante 'bevestigd'-banner zou
  /// alleen ruis zijn voor gebruikers die het al hebben afgehandeld.
  Widget _emailStatusSectie(String email) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kPeach, width: 2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('⚠', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Je e-mailadres is nog niet bevestigd',
                    style: TextStyle(fontSize: 14,
                        fontWeight: FontWeight.w800, color: kBrown)),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(email, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12,
                          color: kTextMuted)),
                ],
              ])),
          ]),
          const SizedBox(height: 10),
          const Text(
              'Kijk in je inbox (en spam) voor onze e-mail. Daarna kun '
              'je hieronder bevestigen dat je geklikt hebt.',
              style: TextStyle(fontSize: 12,
                  color: kBrownLight, height: 1.4)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: kPeachPale,
                foregroundColor: kBrown,
                padding: const EdgeInsets.symmetric(vertical: 12)),
              onPressed: _bezigVerstuur ? null : _verstuurVerificatieMail,
              child: _bezigVerstuur
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          color: kPeach, strokeWidth: 2.5))
                  : const Text('Verstuur opnieuw',
                      style: TextStyle(fontWeight: FontWeight.w800)),
            )),
            const SizedBox(width: 8),
            Expanded(child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: kPeach,
                foregroundColor: kWhite,
                padding: const EdgeInsets.symmetric(vertical: 12)),
              onPressed: _bezigVerifieer ? null : _controleerVerificatie,
              child: _bezigVerifieer
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          color: kWhite, strokeWidth: 2.5))
                  : const Text("Ik heb 't bevestigd",
                      style: TextStyle(fontWeight: FontWeight.w800)),
            )),
          ]),
        ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final naam = _toonNaam;
    return Padding(padding: const EdgeInsets.all(20),
      child: ListView(children: [
        const Text('Instellingen',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
                color: kBrown)),
        if (!widget.alsOntvanger) ...[
          const SizedBox(height: 20),
          _sectie('DAGELIJKSE MOMENTEN'),
          _item('📅', 'Momenten beheren',
              'Voeg toe, pas aan of verwijder vaste momenten', () {
            Navigator.push(context, MaterialPageRoute(
                builder: (c) => const MomentenBeherenScherm()));
          }),
        ],
        if (!widget.alsOntvanger) ...[
          const SizedBox(height: 20),
          _sectie('KRINGEN'),
          if (_kringen != null && _kringen!.isNotEmpty) ...[
            ..._kringen!.map(_kringTegel),
            const SizedBox(height: 4),
          ],
          _item('🪄', 'Nieuwe kring aanmaken',
              'Voor een tweede dierbare bijvoorbeeld', () {
            Navigator.push(context, MaterialPageRoute(
                builder: (c) => const KringAanmakenScherm()));
          }),
        ],
        const SizedBox(height: 20),
        _sectie('ACCOUNT'),
        if (!widget.alsOntvanger && !_emailVerified)
          _emailStatusSectie(
              FirebaseAuth.instance.currentUser?.email ?? ''),
        _item('👵', 'Ontvanger-profiel',
            'Naam, foto, lievelingsdingen en herkenningsgeluid', () {
          Navigator.push(context, MaterialPageRoute(
              builder: (c) => const OntvangerInfoScherm()));
        }),
        _item('📥',
            widget.alsOntvanger
                ? 'Ontvangen berichten'
                : 'Ontvangen berichten van $naam',
            widget.alsOntvanger
                ? 'Alle berichten die je hebt ontvangen'
                : 'Alle berichten die $naam heeft gestuurd', () {
          Navigator.push(context, MaterialPageRoute(
              builder: (c) => OntvangenBerichtenScherm(
                  alsOntvanger: widget.alsOntvanger)));
        }),
        if (!widget.alsOntvanger)
          _item('👥', 'Kringleden beheren',
              'Bekijk en verwijder apparaten in de kring', () {
            Navigator.push(context, MaterialPageRoute(
                builder: (c) => const KringledenScherm()));
          }),
        if (_benIkEigenaar && !widget.alsOntvanger)
          _item('🔄', 'Wijzig modus van $naam',
              'Vergrendeld of meldings — op afstand',
              () => _toonModusDialog(context, naam)),
        if (_benIkEigenaar && !widget.alsOntvanger)
          _item('✉️', 'Email of wachtwoord wijzigen',
              'Voor jou en je kringleden',
              () => showDialog(context: context,
                  builder: (ctx) => const _AccountWijzigDialog())),
        const SizedBox(height: 20),
        _sectie('OVERIG'),
        _item('❓', 'Hulp en uitleg', 'Veelgestelde vragen', () {
          showModalBottomSheet(context: context,
              backgroundColor: Colors.transparent, isScrollControlled: true,
              builder: (ctx) => const _HulpDialog());
        }),
        _item('🚪', 'Uitloggen', 'Logt uit en wist apparaat-instellingen', () async {
          await DeviceModusService.wis();
          await FirebaseAuth.instance.signOut();
        }),
        const SizedBox(height: 30),
        Center(child: Opacity(opacity: 0.85,
            child: Image.asset('assets/images/logo.png', height: 48))),
        const SizedBox(height: 8),
        const Center(child: Text('Ons Moment v7',
            style: TextStyle(fontSize: 11, color: kTextMuted))),
      ]),
    );
  }

  void _toonModusDialog(BuildContext context, String naam) {
    String? gekozen = _huidigeOntvangerModus;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: kCream,
        title: Text('Hoe gebruikt $naam dit apparaat?',
            style: const TextStyle(fontSize: 17,
                fontWeight: FontWeight.w900, color: kBrown)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _modusOptie(
              emoji: '🔒', titel: 'Alleen voor Ons Moment',
              uitleg: 'Kiosk — alleen popups, geen andere apps',
              modusId: DeviceModusService.VERGRENDELD,
              gekozen: gekozen, huidig: _huidigeOntvangerModus,
              onTap: () => setLocal(() =>
                  gekozen = DeviceModusService.VERGRENDELD)),
          const SizedBox(height: 10),
          _modusOptie(
              emoji: '📱', titel: 'Ook voor andere dingen',
              uitleg: 'Berichten komen als melding binnen',
              modusId: DeviceModusService.MELDINGEN,
              gekozen: gekozen, huidig: _huidigeOntvangerModus,
              onTap: () => setLocal(() =>
                  gekozen = DeviceModusService.MELDINGEN)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuleren',
                  style: TextStyle(color: kTextMuted,
                      fontWeight: FontWeight.w700))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kPeach,
              disabledBackgroundColor: kPeachLight,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
            onPressed: (gekozen == null
                    || gekozen == _huidigeOntvangerModus)
                ? null
                : () => _commitModusWijziging(ctx, gekozen!, naam),
            child: const Text('Wijzig', style: TextStyle(
                color: kWhite, fontWeight: FontWeight.w800))),
        ],
      ),
    ));
  }

  Widget _modusOptie({required String emoji, required String titel,
      required String uitleg, required String modusId,
      required String? gekozen, required String? huidig,
      required VoidCallback onTap}) {
    final isGekozen = gekozen == modusId;
    final isHuidig = huidig == modusId;
    return GestureDetector(onTap: onTap, child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: isGekozen ? kPeachPale : kWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isGekozen ? kPeach : kPeachLight, width: 2)),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Row(children: [
            Flexible(child: Text(titel, style: const TextStyle(fontSize: 13,
                fontWeight: FontWeight.w800, color: kBrown))),
            if (isHuidig) ...[
              const SizedBox(width: 6),
              const Text('(huidig)', style: TextStyle(fontSize: 10,
                  fontWeight: FontWeight.w800, color: kPeach)),
            ],
          ]),
          Text(uitleg, style: const TextStyle(fontSize: 11,
              color: kTextMuted, height: 1.3)),
        ])),
      ]),
    ));
  }

  Future<void> _commitModusWijziging(BuildContext ctx, String nieuweModus,
      String naam) async {
    Navigator.pop(ctx);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // V9 multi-kring fix: kringId is verplicht in de service. Zonder
    // actieve kring is er geen tablet om te schakelen — toon een nette
    // melding en stop voordat we Firestore raken.
    final kringId = DeviceModusService.actieveKringNotifier.value;
    if (kringId == null || kringId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Geen actieve kring gekozen — open eerst een kring.'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 4),
      ));
      return;
    }
    final ok = await ApparaatService.zetWeergaveModusVoorOntvangers(
        familieUid: uid, kringId: kringId, nieuweModus: nieuweModus);
    if (!mounted) return;
    if (ok) setState(() => _huidigeOntvangerModus = nieuweModus);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? '✓ Modus van $naam gewijzigd. '
              'Het apparaat van $naam herlaadt automatisch.'
          : 'Wijzigen mislukt — geen tablet gevonden in deze kring. '
              'Mogelijk moet de tablet opnieuw gekoppeld worden.'),
      backgroundColor: ok ? Colors.green : Colors.red,
      duration: const Duration(seconds: 4),
    ));
  }

  Widget _sectie(String t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(t, style: const TextStyle(fontSize: 11,
        fontWeight: FontWeight.w800, color: kTextMuted, letterSpacing: 0.8)));

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

  /// V9 2.3a: tegel voor één kring in de switcher-lijst. Huidige kring
  /// krijgt peach-pale achtergrond + vinkje + subtekst "(huidige kring)";
  /// andere kringen zijn tikbaar om naar te switchen.
  Widget _kringTegel(Kring k) {
    final isHuidig = k.id == _huidigeKringId;
    final foto = k.foto;
    return GestureDetector(
      onTap: isHuidig ? null : () => _switchNaarKring(k.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isHuidig ? kPeachPale : kWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isHuidig ? kPeach : kPeachLight,
              width: isHuidig ? 2 : 1.5)),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kPeachPale,
              border: Border.all(color: kPeachLight, width: 1.5),
              image: (foto != null && foto.isNotEmpty)
                  ? DecorationImage(image: NetworkImage(foto),
                      fit: BoxFit.cover)
                  : null,
            ),
            child: (foto == null || foto.isEmpty)
                ? const Center(child: Icon(Icons.person_rounded,
                    color: kPeach, size: 22))
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(k.naam.isEmpty ? 'Naamloze kring' : k.naam,
                  style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w800, color: kBrown)),
              if (isHuidig)
                const Padding(padding: EdgeInsets.only(top: 2),
                  child: Text('(huidige kring)',
                      style: TextStyle(fontSize: 11, color: kTextMuted))),
            ])),
          if (isHuidig)
            const Icon(Icons.check_circle_rounded, color: kPeach, size: 22),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// MOMENTEN BEHEREN
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
        title: const Text('Momenten beheren',
            style: TextStyle(color: kBrown, fontWeight: FontWeight.w900))),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end, children: [
        FloatingActionButton.extended(
          heroTag: 'fab_eenmalig',
          backgroundColor: kRose,
          onPressed: () => _opnenEenmaligDialog(context, uid),
          icon: const Icon(Icons.event_rounded, color: kWhite),
          label: const Text('Eenmalig gepland',
              style: TextStyle(color: kWhite, fontWeight: FontWeight.w800))),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'fab_dagelijks',
          backgroundColor: kPeach,
          onPressed: () => _opnenDialog(context, uid),
          icon: const Icon(Icons.repeat_rounded, color: kWhite),
          label: const Text('Dagelijks moment',
              style: TextStyle(color: kWhite, fontWeight: FontWeight.w800))),
      ]),
      body: uid == null ? const SizedBox()
        : FutureBuilder<String?>(
        future: DeviceModusService.huidigeKringIdMetFallback(),
        builder: (ctx, kringSnap) {
          final kringId = kringSnap.data;
          if (kringId == null) return const SizedBox();
          return ListView(padding: const EdgeInsets.all(20), children: [
            const _SectieTitel('🔁 DAGELIJKSE MOMENTEN'),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('dagelijkse_momenten')
                  .where('kringId', isEqualTo: kringId)
                  .where('actief', isEqualTo: true).snapshots(),
              builder: (ctx, snap) {
                if (!snap.hasData) return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator(
                      color: kPeach)));
                final docs = snap.data!.docs.toList();
                if (docs.isEmpty) {
                  return _beheerLeeg('Nog geen dagelijkse momenten');
                }
                docs.sort((a, b) {
                  final ua = (a.data() as Map)['uur'] ?? 0;
                  final ub = (b.data() as Map)['uur'] ?? 0;
                  if (ua != ub) return (ua as int).compareTo(ub as int);
                  return ((a.data() as Map)['minuut'] as int)
                      .compareTo((b.data() as Map)['minuut'] as int);
                });
                return Column(children: docs.map((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final audioType =
                      d['aangepasteAudioType'] as String? ?? '';
                  final audioLabel = audioType == 'stem' ? '🎤 Eigen stem'
                      : audioType == 'mp3' ? '🎵 Eigen MP3'
                      : '🔔 Standaard geluid';
                  return GestureDetector(
                    onTap: () => _opnenDialog(context, uid, bestaand: doc),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: kWhite,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: kPeachLight, width: 2)),
                      child: Row(children: [
                        Text(d['emoji'] ?? '⭐',
                            style: const TextStyle(fontSize: 28)),
                        const SizedBox(width: 14),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d['label'] ?? 'Moment',
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: kBrown)),
                            Text('${(d['uur'] ?? 0).toString().padLeft(2, '0')}:${(d['minuut'] ?? 0).toString().padLeft(2, '0')} elke dag • $audioLabel',
                                style: const TextStyle(
                                    fontSize: 12, color: kTextMuted)),
                          ])),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.red),
                          onPressed: () async {
                            final kringId = await DeviceModusService
                                .huidigeKringIdMetFallback();
                            if (kringId != null) {
                              await DagelijksAudioService.reset(
                                  kringId: kringId, momentId: doc.id);
                            }
                            await doc.reference.update({'actief': false});
                          }),
                      ]),
                    ),
                  );
                }).toList());
              },
            ),
            const SizedBox(height: 24),
            const _SectieTitel('📅 EENMALIGE MOMENTEN'),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('gepland_momenten')
                  .where('kringId', isEqualTo: kringId)
                  .where('actief', isEqualTo: true).snapshots(),
              builder: (ctx, snap) {
                if (!snap.hasData) return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator(
                      color: kPeach)));
                // Verberg eenmalige momenten meer dan 24u na hun tijd —
                // beheer-lijst blijft schoon voor mantelzorger. Popup-pad
                // (actief+getoond) is ongewijzigd; alleen UI-filter.
                final grens =
                    DateTime.now().subtract(const Duration(hours: 24));
                final docs = snap.data!.docs.where((d) {
                  final t = ((d.data() as Map)['geplandOp'] as Timestamp?)
                      ?.toDate();
                  return t != null && t.isAfter(grens);
                }).toList()..sort((a, b) {
                  final ta = (a.data() as Map)['geplandOp'] as Timestamp?;
                  final tb = (b.data() as Map)['geplandOp'] as Timestamp?;
                  if (ta == null || tb == null) return 0;
                  return ta.compareTo(tb);
                });
                if (docs.isEmpty) {
                  return _beheerLeeg('Nog geen eenmalige momenten');
                }
                return Column(children: docs.map((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final geplandOp =
                      (d['geplandOp'] as Timestamp?)?.toDate();
                  final tijdLabel = geplandOp != null
                      ? '${geplandOp.day.toString().padLeft(2, '0')}-'
                        '${geplandOp.month.toString().padLeft(2, '0')} • '
                        '${geplandOp.hour.toString().padLeft(2, '0')}:'
                        '${geplandOp.minute.toString().padLeft(2, '0')}'
                      : 'Geen tijdstip';
                  final audioType =
                      d['aangepasteAudioType'] as String? ?? '';
                  final audioLabel = audioType == 'stem' ? '🎤 Eigen stem'
                      : audioType == 'mp3' ? '🎵 Eigen MP3'
                      : '🔔 Standaard geluid';
                  return GestureDetector(
                    onTap: () =>
                        _opnenEenmaligDialog(context, uid, bestaand: doc),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: kWhite,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: kPeachLight, width: 2)),
                      child: Row(children: [
                        Text(d['emoji'] ?? '⭐',
                            style: const TextStyle(fontSize: 28)),
                        const SizedBox(width: 14),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d['label'] ?? 'Moment',
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: kBrown)),
                            Text('$tijdLabel • $audioLabel',
                                style: const TextStyle(
                                    fontSize: 12, color: kTextMuted)),
                          ])),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.red),
                          onPressed: () async {
                            final kringId = await DeviceModusService
                                .huidigeKringIdMetFallback();
                            if (kringId != null) {
                              await DagelijksAudioService.reset(
                                  kringId: kringId, momentId: doc.id,
                                  collectie: 'gepland_momenten');
                            }
                            await doc.reference
                                .update({'actief': false});
                          }),
                      ]),
                    ),
                  );
                }).toList());
              },
            ),
          ]);
        },
      ),
    );
  }

  Widget _beheerLeeg(String tekst) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
    child: Text(tekst,
        style: const TextStyle(fontSize: 12, color: kTextMuted)));

  Future<void> _opnenDialog(BuildContext context, String? uid,
      {QueryDocumentSnapshot? bestaand}) async {
    if (uid == null) return;
    final initial = bestaand?.data() as Map<String, dynamic>?;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _NieuwMomentDialog(
          initial: initial, bestaand: bestaand));
    if (result == null) return;
    if (bestaand != null) {
      await bestaand.reference.update({
        'emoji': result['emoji'],
        'label': result['label'],
        'uur': result['uur'],
        'minuut': result['minuut'],
      });
    } else {
      final kringId = await DeviceModusService.huidigeKringIdMetFallback();
      if (kringId == null) return;
      await FirebaseFirestore.instance.collection('dagelijkse_momenten').add({
        'kringId': kringId,
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

  Future<void> _opnenEenmaligDialog(BuildContext context, String? uid,
      {QueryDocumentSnapshot? bestaand}) async {
    if (uid == null) return;
    final initial = bestaand?.data() as Map<String, dynamic>?;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _EenmaligMomentDialog(
          initial: initial, bestaand: bestaand));
    if (result == null) return;
    if (bestaand != null) {
      // Update alleen de bewerkbare velden — kringId/actief/getoond/aangemaakt
      // blijven bewust ongemoeid zodat de popup-trigger en historie kloppen.
      await bestaand.reference.update({
        'emoji': result['emoji'],
        'label': result['label'],
        'uur': result['uur'],
        'minuut': result['minuut'],
        'geplandOp': Timestamp.fromDate(result['geplandOp'] as DateTime),
      });
    } else {
      final kringId = await DeviceModusService.huidigeKringIdMetFallback();
      if (kringId == null) return;
      await FirebaseFirestore.instance.collection('gepland_momenten').add({
        'kringId': kringId,
        'emoji': result['emoji'],
        'label': result['label'],
        'uur': result['uur'],
        'minuut': result['minuut'],
        'geplandOp': Timestamp.fromDate(result['geplandOp'] as DateTime),
        'actief': true,
        'getoond': false,
        'aangemaakt': FieldValue.serverTimestamp(),
      });
    }
  }
}

class _NieuwMomentDialog extends StatefulWidget {
  final Map<String, dynamic>? initial;
  final QueryDocumentSnapshot? bestaand;
  const _NieuwMomentDialog({this.initial, this.bestaand});
  @override
  State<_NieuwMomentDialog> createState() => _NieuwMomentDialogState();
}

class _NieuwMomentDialogState extends State<_NieuwMomentDialog> {
  late String _emoji;
  late final TextEditingController _labelCtrl;
  late TimeOfDay _tijd;
  final _emojis = ['⭐', '☀️', '☕', '🍽️', '🌙', '💕', '🎵', '🌸', '🌳', '📚', '🐦', '🍰'];

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _emoji = init?['emoji'] as String? ?? '⭐';
    _labelCtrl = TextEditingController(text: init?['label'] as String? ?? '');
    _tijd = TimeOfDay(
        hour: init?['uur'] as int? ?? 15,
        minute: init?['minuut'] as int? ?? 0);
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(backgroundColor: kCream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.initial == null ? 'Nieuw moment' : 'Moment aanpassen',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
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
          const SizedBox(height: 16),
          if (widget.bestaand != null)
            GestureDetector(
              onTap: () => showDialog(context: context,
                  builder: (ctx) =>
                      _AudioInstelDialog(doc: widget.bestaand!)),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: kPeachPale,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kPeach, width: 1.5)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('🎤 ', style: TextStyle(fontSize: 18)),
                  Flexible(child: Text(
                      'Eigen stem of liedje toevoegen',
                      style: TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w800, color: kBrown))),
                ]),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: kPeachPale,
                  borderRadius: BorderRadius.circular(8)),
              child: const Text(
                '💡 Je kunt je eigen stem of een liedje toevoegen '
                'nadat je dit moment hebt opgeslagen.',
                style: TextStyle(fontSize: 12,
                    color: kBrownLight, height: 1.4)),
            ),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Annuleren',
                  style: TextStyle(color: kTextMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kPeach),
              onPressed: () {
                if (_labelCtrl.text.trim().isEmpty) return;
                Navigator.pop(context, {
                  'emoji': _emoji, 'label': _labelCtrl.text.trim(),
                  'uur': _tijd.hour, 'minuut': _tijd.minute,
                });
              },
              child: const Text('Toevoegen',
                  style: TextStyle(color: kWhite, fontWeight: FontWeight.w800))),
          ]),
        ])));
  }
}

class _EenmaligMomentDialog extends StatefulWidget {
  final Map<String, dynamic>? initial;
  final QueryDocumentSnapshot? bestaand;
  const _EenmaligMomentDialog({this.initial, this.bestaand});
  @override
  State<_EenmaligMomentDialog> createState() => _EenmaligMomentDialogState();
}

class _EenmaligMomentDialogState extends State<_EenmaligMomentDialog> {
  late String _emoji;
  late final TextEditingController _labelCtrl;
  late DateTime _datum;
  late TimeOfDay _tijd;
  final _emojis = ['⭐', '☀️', '☕', '🍽️', '🌙', '💕', '🎵', '🌸', '🌳', '📚', '🐦', '🍰'];

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    final geplandOp = (i?['geplandOp'] as Timestamp?)?.toDate();
    _emoji = (i?['emoji'] as String?) ?? '⭐';
    _labelCtrl = TextEditingController(text: (i?['label'] as String?) ?? '');
    _datum = geplandOp ?? DateTime.now().add(const Duration(days: 1));
    _tijd = geplandOp != null
        ? TimeOfDay(hour: geplandOp.hour, minute: geplandOp.minute)
        : const TimeOfDay(hour: 12, minute: 0);
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  String _formatDatum(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.year}';

  void _toonFout(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.red));

  @override
  Widget build(BuildContext context) {
    return Dialog(backgroundColor: kCream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Eenmalig gepland moment',
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
              decoration: const InputDecoration(labelText: 'Naam (bijv. Verjaardag)',
                border: OutlineInputBorder())),
            const SizedBox(height: 16),
            Row(children: [
              const Text('Datum:', style: TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w700, color: kBrown)),
              const SizedBox(width: 12),
              GestureDetector(onTap: () async {
                final d = await showDatePicker(context: context,
                  initialDate: _datum,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) setState(() => _datum = d);
              }, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: kPeachPale,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kPeach, width: 1.5)),
                child: Text(_formatDatum(_datum),
                  style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w800, color: kBrown)))),
            ]),
            const SizedBox(height: 12),
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
                child: Text('${_tijd.hour.toString().padLeft(2, '0')}:'
                    '${_tijd.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w800, color: kBrown)))),
            ]),
            const SizedBox(height: 16),
            if (widget.bestaand != null)
              GestureDetector(
                onTap: () => showDialog(context: context,
                    builder: (ctx) =>
                        _AudioInstelDialog(doc: widget.bestaand!)),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: kPeachPale,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kPeach, width: 1.5)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('🎤 ', style: TextStyle(fontSize: 18)),
                    Flexible(child: Text(
                        'Eigen stem of liedje toevoegen',
                        style: TextStyle(fontSize: 13,
                            fontWeight: FontWeight.w800, color: kBrown))),
                  ]),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: kPeachPale,
                    borderRadius: BorderRadius.circular(8)),
                child: const Text(
                  '💡 Je kunt je eigen stem of een liedje toevoegen '
                  'nadat je dit moment hebt opgeslagen.',
                  style: TextStyle(fontSize: 12,
                      color: kBrownLight, height: 1.4)),
              ),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('Annuleren',
                    style: TextStyle(color: kTextMuted))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: kPeach),
                onPressed: () {
                  if (_labelCtrl.text.trim().isEmpty) {
                    _toonFout('Vul een naam in'); return;
                  }
                  final gepland = DateTime(_datum.year, _datum.month,
                      _datum.day, _tijd.hour, _tijd.minute);
                  if (!gepland.isAfter(DateTime.now())) {
                    _toonFout('Kies een tijdstip in de toekomst'); return;
                  }
                  Navigator.pop(context, {
                    'emoji': _emoji,
                    'label': _labelCtrl.text.trim(),
                    'uur': _tijd.hour,
                    'minuut': _tijd.minute,
                    'geplandOp': gepland,
                  });
                },
                child: const Text('Plannen',
                    style: TextStyle(color: kWhite, fontWeight: FontWeight.w800))),
            ]),
          ]))));
  }
}

class _AccountWijzigDialog extends StatefulWidget {
  const _AccountWijzigDialog();
  @override
  State<_AccountWijzigDialog> createState() => _AccountWijzigDialogState();
}

class _AccountWijzigDialogState extends State<_AccountWijzigDialog> {
  final _emailNieuwCtrl = TextEditingController();
  final _emailWwCtrl = TextEditingController();
  final _wwHuidigCtrl = TextEditingController();
  final _wwNieuwCtrl = TextEditingController();
  final _wwBevestigCtrl = TextEditingController();
  bool _bezigEmail = false;
  bool _bezigWw = false;

  @override
  void dispose() {
    _emailNieuwCtrl.dispose();
    _emailWwCtrl.dispose();
    _wwHuidigCtrl.dispose();
    _wwNieuwCtrl.dispose();
    _wwBevestigCtrl.dispose();
    super.dispose();
  }

  void _toonFout(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.red));

  void _toonSucces(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: kGreen,
          duration: const Duration(seconds: 6)));

  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Huidig wachtwoord klopt niet';
      case 'weak-password':
        return 'Nieuw wachtwoord moet minimaal 6 tekens zijn';
      case 'email-already-in-use':
        return 'Dit email-adres is al in gebruik';
      case 'invalid-email':
        return 'Email-adres is niet geldig';
      case 'requires-recent-login':
        return 'Even opnieuw inloggen, dan kun je het wijzigen';
      default:
        return 'Wijzigen mislukt — probeer opnieuw';
    }
  }

  Future<void> _wijzigEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final nieuw = _emailNieuwCtrl.text.trim();
    final ww = _emailWwCtrl.text;
    if (nieuw.isEmpty || ww.isEmpty) {
      _toonFout('Vul alle velden in'); return;
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(nieuw)) {
      _toonFout('Email-adres is niet geldig'); return;
    }
    setState(() => _bezigEmail = true);
    try {
      final cred = EmailAuthProvider.credential(
          email: user.email!, password: ww);
      await user.reauthenticateWithCredential(cred);
      // verifyBeforeUpdateEmail stuurt een verificatielink naar het nieuwe
      // adres; de e-mail wijzigt pas ná het klikken. Werkt ook met Email
      // Enumeration Protection (anders dan het deprecated updateEmail).
      await user.verifyBeforeUpdateEmail(nieuw);
      if (!mounted) return;
      _toonSucces('✓ Verificatie-link is gestuurd naar $nieuw. Open je '
          'inbox en klik op de link om te bevestigen. Daarna log jij in '
          'met je nieuwe e-mailadres.');
      _emailNieuwCtrl.clear();
      _emailWwCtrl.clear();
    } on FirebaseAuthException catch (e) {
      _toonFout(_friendlyError(e));
    } catch (_) {
      _toonFout('Wijzigen mislukt — probeer opnieuw');
    } finally {
      if (mounted) setState(() => _bezigEmail = false);
    }
  }

  Future<void> _wijzigWachtwoord() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final huidig = _wwHuidigCtrl.text;
    final nieuw = _wwNieuwCtrl.text;
    final bevestig = _wwBevestigCtrl.text;
    if (huidig.isEmpty || nieuw.isEmpty) {
      _toonFout('Vul alle velden in'); return;
    }
    if (nieuw.length < 6) {
      _toonFout('Nieuw wachtwoord moet minimaal 6 tekens zijn'); return;
    }
    if (nieuw != bevestig) {
      _toonFout('Nieuwe wachtwoorden komen niet overeen'); return;
    }
    setState(() => _bezigWw = true);
    try {
      final cred = EmailAuthProvider.credential(
          email: user.email!, password: huidig);
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(nieuw);
      if (!mounted) return;
      _toonSucces('✓ Wachtwoord gewijzigd. Je blijft nu ingelogd; de '
          'volgende keer heb je je nieuwe wachtwoord nodig.');
      _wwHuidigCtrl.clear();
      _wwNieuwCtrl.clear();
      _wwBevestigCtrl.clear();
    } on FirebaseAuthException catch (e) {
      _toonFout(_friendlyError(e));
    } catch (_) {
      _toonFout('Wijzigen mislukt — probeer opnieuw');
    } finally {
      if (mounted) setState(() => _bezigWw = false);
    }
  }

  Widget _veld(String label, TextEditingController ctrl, {bool obscure = false}) =>
      Padding(padding: const EdgeInsets.only(bottom: 10),
        child: TextField(controller: ctrl, obscureText: obscure,
          style: const TextStyle(color: kBrown, fontWeight: FontWeight.w700),
          decoration: InputDecoration(labelText: label,
            labelStyle: const TextStyle(color: kTextMuted, fontSize: 13),
            border: const OutlineInputBorder())));

  Widget _actieKnop(String label, bool bezig, VoidCallback onTap) =>
      SizedBox(width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kPeach,
            disabledBackgroundColor: kPeachLight,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
          onPressed: bezig ? null : onTap,
          child: bezig
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(color: kWhite, strokeWidth: 2.5))
              : Text(label, style: const TextStyle(
                  color: kWhite, fontWeight: FontWeight.w800))));

  Widget _sectieKop(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: const TextStyle(fontSize: 15,
        fontWeight: FontWeight.w900, color: kBrown)));

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return Dialog(backgroundColor: kCream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Account gegevens wijzigen',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                    color: kBrown)),
            const SizedBox(height: 16),
            Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12)),
              child: Text('💡 Dit wijzigt alleen jouw inloggegevens. Andere '
                  'kringleden hebben hun eigen account en merken er niets van.',
                  style: TextStyle(fontSize: 12,
                      color: Colors.blue.shade900, height: 1.4))),
            const SizedBox(height: 20),

            _sectieKop('E-mail wijzigen'),
            Container(width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: kPeachPale,
                  borderRadius: BorderRadius.circular(10)),
              child: Text('Huidig: $email',
                  style: const TextStyle(fontSize: 12, color: kTextMuted))),
            _veld('Nieuw e-mailadres', _emailNieuwCtrl),
            _veld('Huidig wachtwoord', _emailWwCtrl, obscure: true),
            _actieKnop('Wijzig e-mail', _bezigEmail, _wijzigEmail),
            const SizedBox(height: 8),
            const Text('Je krijgt een email op het NIEUWE adres. Open die '
                'en klik op de link om de wijziging te bevestigen.',
                style: TextStyle(fontSize: 11, color: kTextMuted, height: 1.4)),
            const SizedBox(height: 24),

            _sectieKop('Wachtwoord wijzigen'),
            _veld('Huidig wachtwoord', _wwHuidigCtrl, obscure: true),
            _veld('Nieuw wachtwoord', _wwNieuwCtrl, obscure: true),
            _veld('Bevestig nieuw wachtwoord', _wwBevestigCtrl, obscure: true),
            _actieKnop('Wijzig wachtwoord', _bezigWw, _wijzigWachtwoord),
            const SizedBox(height: 16),

            Center(child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Sluiten',
                  style: TextStyle(color: kTextMuted,
                      fontWeight: FontWeight.w700)))),
          ]))));
  }
}

// ════════════════════════════════════════════════════════════
// ONTVANGER INFO
// ════════════════════════════════════════════════════════════
class OntvangerInfoScherm extends StatefulWidget {
  const OntvangerInfoScherm({super.key});
  @override
  State<OntvangerInfoScherm> createState() => _OntvangerInfoSchermState();
}

class _OntvangerInfoSchermState extends State<OntvangerInfoScherm> {
  final _naamCtrl = TextEditingController();
  final _lievelingsdingenCtrl = TextEditingController();
  final _woonplaatsCtrl = TextEditingController();
  final _noodNaamCtrl = TextEditingController();
  final _noodTelCtrl = TextEditingController();
  Uint8List? _fotoBytes;
  String _huidigeFotoUrl = '';
  String _gekozenGeluid = 'twinkel';
  final _geluidPreviewPlayer = AudioPlayer();
  bool _bezig = false;
  // V9 2.4-a-4: kringId frozen op moment van _laad zodat een notifier-
  // switch mid-edit niet per ongeluk een andere kring overschrijft.
  String? _kringIdVoorOpslaan;
  bool _kringDocBestaat = false;

  @override
  void initState() { super.initState(); _laad(); }

  @override
  void dispose() {
    _geluidPreviewPlayer.dispose();
    super.dispose();
  }

  /// Helper: kies kring-veld als niet-leeg, anders gebruikersdoc-veld,
  /// anders fallback.
  ///
  /// V9 2.4-a-5 fix: bij _kringDocBestaat == true wordt STRIKT uit het
  /// kring-veld gelezen — geen fallback naar gebruikers/{uid}. Reden:
  /// gebruikers/{uid} is een gedeelde bron en de dual-write overschrijft
  /// 'm bij elke save in een willekeurige kring. Een null/lege waarde
  /// in het kring-doc voor een optioneel veld is bewust leeg, niet
  /// "kijk maar in gebruikers/{uid}". Lekkage tussen kringen voorkomen.
  ///
  /// Bij _kringDocBestaat == false (V7/V8 zonder kring-doc) blijft de
  /// bestaande fallback-keten exact intact.
  String _kies(Map<String, dynamic> kring, String kringVeld,
      Map<String, dynamic> gebruiker, String gebruikersVeld,
      {String fallback = ''}) {
    if (_kringDocBestaat) {
      final k = kring[kringVeld];
      if (k is String && k.isNotEmpty) return k;
      return fallback;
    }
    final k = kring[kringVeld];
    if (k is String && k.isNotEmpty) return k;
    final g = gebruiker[gebruikersVeld];
    if (g is String && g.isNotEmpty) return g;
    return fallback;
  }

  Future<void> _laad() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final kringId = await DeviceModusService.huidigeKringIdMetFallback();

    final futures = <Future<DocumentSnapshot>>[
      FirebaseFirestore.instance.collection('gebruikers').doc(uid).get(),
    ];
    if (kringId != null && kringId.isNotEmpty) {
      futures.add(FirebaseFirestore.instance
          .collection('kringen').doc(kringId).get());
    }
    final docs = await Future.wait(futures);
    if (!mounted) return;

    final gebruikersDoc = docs[0];
    final kringDoc = docs.length > 1 ? docs[1] : null;
    final g = (gebruikersDoc.data() as Map<String, dynamic>?) ?? {};
    final kringExists = kringDoc?.exists == true;
    final k = kringExists
        ? ((kringDoc!.data() as Map<String, dynamic>?) ?? {})
        : <String, dynamic>{};

    setState(() {
      _kringIdVoorOpslaan = kringId;
      _kringDocBestaat = kringExists;
      _naamCtrl.text = _kies(k, 'naam', g, 'ontvangerNaam');
      _lievelingsdingenCtrl.text =
          _kies(k, 'lievelingsdingen', g, 'lievelingsdingen');
      _woonplaatsCtrl.text = _kies(k, 'woonplaats', g, 'woonplaats');
      _noodNaamCtrl.text =
          _kies(k, 'noodcontactNaam', g, 'noodcontactNaam');
      _noodTelCtrl.text = _kies(k, 'noodcontactTel', g, 'noodcontactTel');
      _huidigeFotoUrl = _kies(k, 'foto', g, 'ontvangerFoto');
      _gekozenGeluid =
          _kies(k, 'herkenningsgeluid', g, 'herkenningsgeluid',
              fallback: 'twinkel');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0,
        iconTheme: const IconThemeData(color: kBrown),
        title: const Text('Ontvanger-profiel',
            style: TextStyle(color: kBrown, fontWeight: FontWeight.w900))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(child: GestureDetector(
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
        )),
        const SizedBox(height: 8),
        const Center(child: Text('Tik om foto te wijzigen',
            style: TextStyle(fontSize: 11, color: kTextMuted))),
        const SizedBox(height: 24),
        _veld('👤', 'Naam', _naamCtrl),
        const SizedBox(height: 10),
        _veld('💕', 'Lievelingsdingen', _lievelingsdingenCtrl),
        const SizedBox(height: 10),
        _veld('🏠', 'Vroegere woonplaats', _woonplaatsCtrl),
        const SizedBox(height: 10),
        _veld('🆘', 'Noodcontact naam', _noodNaamCtrl),
        const SizedBox(height: 10),
        _veld('☎️', 'Noodcontact telefoon', _noodTelCtrl),
        const SizedBox(height: 24),
        const Text('HERKENNINGSGELUID',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                color: kTextMuted, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        ...kGeluiden.map((g) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () {
              setState(() => _gekozenGeluid = g['id']!);
              _speelPreview(g['asset']!);
            },
            child: Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _gekozenGeluid == g['id'] ? kPeach : kWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _gekozenGeluid == g['id']
                    ? kPeach : kPeachLight, width: 2)),
              child: Row(children: [
                Text(g['emoji']!, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(child: Text(g['naam']!, style: TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _gekozenGeluid == g['id'] ? kWhite : kBrown))),
                Icon(Icons.play_circle_outline_rounded,
                    color: _gekozenGeluid == g['id'] ? kWhite : kPeach, size: 24),
              ]),
            ),
          ),
        )),
        const SizedBox(height: 30),
        GestureDetector(onTap: _bezig ? null : _opslaan,
          child: Container(width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kPeach, kRose]),
              borderRadius: BorderRadius.circular(16)),
            child: Center(child: _bezig
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(color: kWhite, strokeWidth: 3))
              : const Text('Opslaan',
                  style: TextStyle(fontSize: 16, color: kWhite,
                      fontWeight: FontWeight.w800))))),
      ]),
    );
  }

  Widget _veld(String emoji, String label, TextEditingController ctrl) =>
    Container(decoration: BoxDecoration(color: kWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kPeachLight, width: 2)),
      child: Row(children: [
        Padding(padding: const EdgeInsets.only(left: 16),
            child: Text(emoji, style: const TextStyle(fontSize: 20))),
        Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(controller: ctrl,
            decoration: InputDecoration(labelText: label,
              labelStyle: const TextStyle(color: kTextMuted, fontSize: 12),
              border: InputBorder.none)))),
      ]),
    );

  Future<void> _speelPreview(String pad) async {
    try {
      await _geluidPreviewPlayer.stop();
      await _geluidPreviewPlayer.setAsset(pad);
      await _geluidPreviewPlayer.play();
    } catch (_) {}
  }

  Future<void> _kiesFoto() async {
    final picker = ImagePicker();
    final foto = await picker.pickImage(source: ImageSource.gallery,
        maxWidth: 1200, imageQuality: 85);
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
      // V9 2.4-a-4: foto-pad per kring (apart bestand per kring-doc).
      // V7/V8-fallback gebruikt nog steeds {uid}.jpg — oude gedrag intact.
      final fotoNaam = (_kringDocBestaat && _kringIdVoorOpslaan != null)
          ? _kringIdVoorOpslaan!
          : uid;
      String fotoUrl = _huidigeFotoUrl;
      if (_fotoBytes != null) {
        final ref = FirebaseStorage.instance.ref()
            .child('profielfotos').child('$fotoNaam.jpg');
        await ref.putData(_fotoBytes!,
            SettableMetadata(contentType: 'image/jpeg'));
        fotoUrl = await ref.getDownloadURL();
      }

      final batch = FirebaseFirestore.instance.batch();

      // Legacy: blijf naar gebruikers/{uid} schrijven voor backwards-compat
      // met oude leespaden die we mogelijk missen.
      batch.update(
        FirebaseFirestore.instance.collection('gebruikers').doc(uid), {
          'ontvangerNaam': _naamCtrl.text.trim(),
          'ontvangerFoto': fotoUrl,
          'lievelingsdingen': _lievelingsdingenCtrl.text.trim(),
          'woonplaats': _woonplaatsCtrl.text.trim(),
          'noodcontactNaam': _noodNaamCtrl.text.trim(),
          'noodcontactTel': _noodTelCtrl.text.trim(),
          'herkenningsgeluid': _gekozenGeluid,
        });

      // V9: schrijf primair naar het ACTIEVE kring-doc. Gebruikt
      // _kringIdVoorOpslaan (frozen bij _laad) zodat een tussentijdse
      // notifier-switch niet de verkeerde kring overschrijft.
      if (_kringDocBestaat && _kringIdVoorOpslaan != null) {
        batch.update(
          FirebaseFirestore.instance.collection('kringen')
              .doc(_kringIdVoorOpslaan!), {
            'naam': _naamCtrl.text.trim(),
            'foto': fotoUrl,
            'lievelingsdingen': _lievelingsdingenCtrl.text.trim(),
            'woonplaats': _woonplaatsCtrl.text.trim(),
            'noodcontactNaam': _noodNaamCtrl.text.trim(),
            'noodcontactTel': _noodTelCtrl.text.trim(),
            'herkenningsgeluid': _gekozenGeluid,
            'laatsteUpdate': FieldValue.serverTimestamp(),
          });
      }

      await batch.commit();

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
  const _HulpDialog();

  static const List<_FAQ> _faqs = [
    // ── Algemeen ──
    _FAQ('Algemeen', "Wat is Ons Moment precies?",
        "Ons Moment is een app waarmee je foto's, stem-berichten en "
        "herinneringen kunt sturen naar het apparaat van je dierbare. Je kunt "
        "kiezen hoe de app bij je dierbare verschijnt: als een rustig scherm "
        "dat alleen jouw berichten toont, of als een gewone app met meldingen."),
    _FAQ('Algemeen', "Hoe werkt het voor mijn dierbare?",
        "Je dierbare ontvangt jouw berichten op het apparaat dat bij hem of "
        "haar staat. Bij elk nieuw bericht klinkt een herkenningsgeluid en "
        "verschijnt het bericht in beeld. Je dierbare hoeft zelf niets in te "
        "stellen of in te loggen — het apparaat blijft altijd klaar om "
        "berichten te ontvangen."),
    _FAQ('Algemeen',
        "Wat is het verschil tussen vergrendelde modus en meldingen-modus?",
        "In de vergrendelde modus toont het apparaat alleen Ons Moment. Andere "
        "apps zijn niet bereikbaar en je dierbare kan niet per ongeluk iets "
        "veranderen. Deze modus past goed bij iemand die meer zorg nodig heeft. "
        "In de meldingen-modus werkt het apparaat als gewoon: je dierbare kan "
        "andere apps gebruiken, en Ons Moment laat berichten zien als pop-up. "
        "Deze modus past bij iemand die nog zelf met het apparaat omgaat."),
    _FAQ('Algemeen', "Wat is een kring?",
        "Een kring is de groep mensen rondom één dierbare. In de kring zitten "
        "de familieleden, vrienden en mantelzorgers die berichten kunnen "
        "sturen, plus de dierbare zelf die ze ontvangt. Voor elke dierbare "
        "maak je één kring. Zorg je voor meer dan één persoon? Dan kun je "
        "meerdere kringen hebben (afhankelijk van je abonnement)."),
    _FAQ('Algemeen', "Wat is het verschil tussen een eigenaar en een gast?",
        "De eigenaar is degene die de kring heeft aangemaakt en het "
        "abonnement beheert. De eigenaar kan kringleden toevoegen of "
        "verwijderen en de gegevens van de dierbare aanpassen. Een gast is "
        "iemand die is uitgenodigd met een code. Een gast kan berichten "
        "sturen en zichzelf uit de kring halen, maar beheert de kring niet. "
        "Zo houdt één persoon het overzicht, terwijl iedereen kan meedoen."),
    _FAQ('Algemeen', "Wat ziet mijn dierbare op het scherm?",
        "Je dierbare ziet een rustig, overzichtelijk scherm met de tijd, "
        "een vriendelijke begroeting en de berichten die jullie sturen. "
        "Komt er een nieuw bericht of een herinnering binnen, dan "
        "verschijnt die vanzelf in beeld met een herkenningsgeluid. Er "
        "staan geen ingewikkelde knoppen of menu's — alleen wat jullie "
        "sturen."),
    // ── Voor families ──
    _FAQ('Voor families', "Hoe voeg ik iemand toe aan de kring?",
        "Open Instellingen en kies 'Kringleden beheren'. Tik op 'Familie "
        "uitnodigen' — je krijgt dan een uitnodig-code. Deel die code met "
        "een familielid, vriend of mantelzorger. Diegene opent de app, "
        "tikt op 'Heb je een uitnodig-code?' en maakt een eigen account "
        "aan (of logt in met een bestaand account) om mee te doen. Een "
        "kring telt maximaal acht of twintig kringleden, afhankelijk van "
        "je abonnement."),
    _FAQ('Voor families', "Hoe stuur ik een bericht?",
        "Open het tabblad 'Sturen'. Kies wat je wilt versturen: een foto, een "
        "stem-bericht, een liedje of een tekst. Vul in voor wie het bedoeld is "
        "en wanneer het moet aankomen. Druk op versturen en het bericht "
        "verschijnt op het ingestelde moment bij je dierbare."),
    _FAQ('Voor families', "Hoe maak ik een dagelijkse herinnering?",
        "Ga naar 'Instellingen' en kies 'Momenten beheren'. Stel een "
        "tijd in en kies wat er moet verschijnen — bijvoorbeeld 'Tijd voor "
        "koffie' met een foto of geluid. De herinnering komt voortaan elke dag "
        "op die tijd in beeld bij je dierbare."),
    _FAQ('Voor families', "Hoe voeg ik mijn eigen stem toe aan een moment?",
        "Bij het maken of bewerken van een herinnering kun je je eigen stem "
        "opnemen via de microfoon-knop. Spreek de boodschap in en sla op. Je "
        "dierbare hoort dan jouw stem in plaats van een standaard geluid."),
    _FAQ('Voor families', "Kan ik een bericht in de toekomst plannen?",
        "Ja. Bij het versturen van een bericht kies je 'Wanneer sturen?' en "
        "stel je een datum en tijd in. Het bericht wordt opgeslagen en "
        "verschijnt vanzelf op het gekozen moment bij je dierbare. Dit werkt "
        "voor losse momenten en voor terugkerende herinneringen."),
    _FAQ('Voor families', "Hoe wijzig ik mijn wachtwoord?",
        "Open Instellingen en kies 'Wachtwoord wijzigen'. Vul je huidige "
        "wachtwoord in en kies een nieuw wachtwoord. Iedereen in de kring "
        "heeft een eigen wachtwoord, dus dit verandert alleen dat van "
        "jou. Heb je het apparaat van je dierbare met jouw account "
        "ingesteld? Dan moet je dat apparaat na een wachtwoordwijziging "
        "opnieuw inloggen."),
    _FAQ('Voor families', "Kan ik iemand uit de kring verwijderen?",
        "Ja. Ga naar Instellingen → Kringleden beheren en tik op de "
        "persoon die je wilt verwijderen. De eigenaar van de kring kan "
        "iedereen verwijderen; andere kringleden kunnen alleen zichzelf "
        "verwijderen. Het apparaat van de verwijderde persoon verliest "
        "de toegang tot deze kring."),
    _FAQ('Voor families', "Wat gebeurt er als ik het apparaat weghaal?",
        "Als het apparaat van je dierbare uit staat of geen internet heeft, "
        "blijven verstuurde berichten klaarstaan. Zodra het apparaat weer "
        "aangaat en verbinding heeft, verschijnen de berichten alsnog. Er gaat "
        "niets verloren."),
    _FAQ('Voor families', "Hoe koppel ik het apparaat van mijn dierbare?",
        "Pak de tablet of telefoon die bij je dierbare komt te staan. Open "
        "daarop Ons Moment en kies 'Apparaat van mijn dierbare instellen'. "
        "Log in met jouw eigen account en kies de juiste kring. Daarna kies "
        "je hoe het scherm eruitziet: een rustig scherm dat alleen Ons "
        "Moment toont, of een gewoon scherm met meldingen. Het apparaat "
        "blijft daarna vanzelf klaarstaan — je dierbare hoeft niets te doen."),
    _FAQ('Voor families', "Heeft het apparaat van mijn dierbare internet nodig?",
        "Ja. Het apparaat heeft wifi of internet nodig om jullie berichten "
        "en herinneringen te ontvangen. Staat het apparaat even zonder "
        "verbinding, dan komen de berichten alsnog binnen zodra er weer "
        "internet is. Er gaat niets verloren."),
    _FAQ('Voor families', "Hoe stuur ik een bericht naar één bepaald persoon?",
        "Bij het versturen kies je bij 'Naar wie?' een specifiek kringlid "
        "in plaats van 'Iedereen in de kring'. Het bericht komt dan alleen "
        "bij die persoon aan. Zo kun je bijvoorbeeld iets persoonlijks "
        "naar je dierbare sturen, of een berichtje naar één familielid."),
    _FAQ('Voor families', "Hoe verlaat ik een kring waar ik gast ben?",
        "Ga naar Instellingen, kies Kringleden beheren en kies bij jezelf "
        "'Uit kring gaan'. Je hebt daarna geen toegang meer tot die kring. "
        "De eigenaar en de andere kringleden blijven gewoon doorgaan."),
    // ── Abonnement ──
    _FAQ('Abonnement', "Wat kost Ons Moment?",
        "Twee abonnementen:\n"
        "- Familie Klein — 1 kring, max 8 kringleden per kring. "
        "€4,99 p/m of €35,99 per jaar.\n"
        "- Familie Groot — max 3 kringen, max 20 kringleden per kring. "
        "€7,99 p/m of €57,99 per jaar.\n"
        "Met een jaarabonnement bespaar je zo'n 40%. Je begint altijd "
        "met 5 dagen gratis — geen betaalgegevens nodig."),
    _FAQ('Abonnement', "Wie telt mee in mijn abonnement?",
        "Iedereen in een kring die berichten kan sturen telt mee voor die "
        "kring — familieleden, vrienden en mantelzorgers. Je dierbare zelf "
        "telt niet mee. Heb je meerdere kringen (Familie Groot), dan heeft "
        "elke kring zijn eigen telling."),
    _FAQ('Abonnement', "Wat gebeurt er na de 5 gratis dagen?",
        "Je begint altijd met 5 dagen gratis, zonder dat je betaalgegevens "
        "hoeft op te geven. Wil je daarna doorgaan, dan kies je een "
        "abonnement. Doe je niets, dan stopt het vanzelf — je wordt nooit "
        "zomaar iets in rekening gebracht."),
    // ── Veiligheid en privacy ──
    _FAQ('Veiligheid en privacy', "Wie kan mijn foto's en berichten zien?",
        "Alleen de mensen in jouw kring en het gekoppelde apparaat van je "
        "dierbare. Ons Moment is een besloten, veilige omgeving — er zijn "
        "geen advertenties, geen vreemden en geen openbare profielen. Wat "
        "je deelt, blijft binnen de kring."),
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
            itemBuilder: (c, i) {
              final faq = _faqs[i];
              final toonKop = i == 0 || _faqs[i - 1].categorie != faq.categorie;
              return Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (toonKop) Padding(
                    padding: EdgeInsets.only(
                        top: i == 0 ? 0 : 18, bottom: 8, left: 4),
                    child: Text(faq.categorie,
                        style: const TextStyle(fontSize: 13,
                            fontWeight: FontWeight.w900, color: kPeach,
                            letterSpacing: 0.8))),
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(color: kWhite,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kPeachLight, width: 1.5)),
                    child: Theme(
                      data: ThemeData(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        title: Text(faq.vraag, style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800,
                            color: kBrown)),
                        iconColor: kPeach, collapsedIconColor: kTextMuted,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Text(faq.antwoord, style: const TextStyle(
                                fontSize: 13, color: kBrownLight,
                                height: 1.5))),
                        ]))),
                ]);
            })),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            decoration: const BoxDecoration(color: kCream,
                border: Border(top: BorderSide(color: kPeachLight, width: 1))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text('Staat je vraag er niet bij?',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: kBrownLight))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: kPeach,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(ctx);
                    // CONTACT-ADRES — later vervangen door zakelijk adres
                    final uri = Uri(scheme: 'mailto',
                        path: 'joshuapanna@gmail.com',
                        query: 'subject=Vraag of feedback over Ons Moment');
                    try {
                      final ok = await launchUrl(uri);
                      if (!ok) {
                        messenger.showSnackBar(const SnackBar(
                            content: Text('Kon mail-app niet openen')));
                      }
                    } catch (_) {
                      messenger.showSnackBar(const SnackBar(
                          content: Text('Kon mail-app niet openen')));
                    }
                  },
                  child: const Text('Stuur ons een mail',
                    style: TextStyle(color: kWhite, fontWeight: FontWeight.w800))),
              ])),
        ]),
      ),
    );
  }
}

class _FAQ {
  final String categorie, vraag, antwoord;
  const _FAQ(this.categorie, this.vraag, this.antwoord);
}

class _BytesAudioSource extends StreamAudioSource {
  final Uint8List _bytes;
  final String _contentType;
  _BytesAudioSource(this._bytes, this._contentType);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_bytes.sublist(start, end)),
      contentType: _contentType,
    );
  }
}

// ════════════════════════════════════════════════════════════
// ONTVANGEN BERICHTEN SCHERM
// ════════════════════════════════════════════════════════════
class OntvangenBerichtenScherm extends StatefulWidget {
  /// V9 2.15: perspectief waarmee dit scherm werd geopend. Default false
  /// (= familie-kant) behoudt bestaand gedrag voor callers zonder param.
  final bool alsOntvanger;
  const OntvangenBerichtenScherm({super.key, this.alsOntvanger = false});
  @override
  State<OntvangenBerichtenScherm> createState() =>
      _OntvangenBerichtenSchermState();
}

class _OntvangenBerichtenSchermState extends State<OntvangenBerichtenScherm> {
  /// V9 2.11-a-2: enige naam-bron is het kring-doc (kringen/{kringId}.naam).
  /// Geen account-brede gebruikers/{uid}.ontvangerNaam-fallback meer want
  /// dat veld lekt bij multi-kring eigenaars naar de verkeerde kring.
  String? _kringNaam;
  List<String>? _ontvangerApparaatIds;
  /// V9 2.15: familie-apparaten in de kring (modus != 'ontvanger').
  /// Nodig voor de ontvanger-perspectief-query.
  List<String>? _familieApparaatIds;
  String? _kringId;
  /// V9 2.15: eigen apparaat-id voor client-side targeting-filter.
  String? _mijnApparaatId;
  StreamSubscription<Kring?>? _actieveKringSub;

  /// V9 2.11-a-2: kring-doc OF 'je dierbare'. Geen account-brede fallback.
  String get _toonNaam {
    if ((_kringNaam ?? '').isNotEmpty) return _kringNaam!;
    return 'je dierbare';
  }

  @override
  void initState() {
    super.initState();
    _laad();
    _actieveKringSub = KringService.actieveKringStream().listen((kring) {
      if (!mounted) return;
      setState(() {
        _kringNaam = (kring != null && kring.naam.isNotEmpty)
            ? kring.naam : null;
      });
    });
  }

  @override
  void dispose() {
    _actieveKringSub?.cancel();
    super.dispose();
  }

  Future<void> _laad() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final kringId = await DeviceModusService.huidigeKringIdMetFallback();
      if (kringId == null) {
        if (mounted) setState(() => _ontvangerApparaatIds = []);
        return;
      }
      // V9 2.11-a-2: kring-doc + apparaten parallel zodat _kringNaam
      // al gevuld is bij de eerste render — voorkomt de korte
      // 'Ontvangen van je dierbare' -> 'Ontvangen van Opa' flash.
      // V9 2.15: apparaat-id meeladen voor client-side targeting-filter
      // op ontvanger-kant.
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('kringen').doc(kringId).get(),
        ApparaatService.kringLeden(uid),
        DeviceModusService.krijgApparaatId(),
      ]);
      final kringDoc = results[0] as DocumentSnapshot;
      final leden = results[1] as List<Map<String, dynamic>>;
      final apparaatId = results[2] as String?;
      final kringData = kringDoc.data();
      final kringNaam = (kringData is Map)
          ? kringData['naam'] as String?
          : null;
      if (!mounted) return;
      setState(() {
        _kringId = kringId;
        _mijnApparaatId = apparaatId;
        if (kringNaam != null && kringNaam.isNotEmpty) {
          _kringNaam = kringNaam;
        }
        _ontvangerApparaatIds = leden
            .where((l) => l['modus'] == 'ontvanger')
            .map((l) => l['apparaatId'] as String)
            .toList();
        _familieApparaatIds = leden
            .where((l) => l['modus'] != 'ontvanger')
            .map((l) => l['apparaatId'] as String)
            .toList();
      });
    } catch (_) {
      if (mounted) setState(() => _ontvangerApparaatIds = []);
    }
  }

  /// V9 2.15: identiek targeting-patroon aan tablet_scherm.dart regel 232-243.
  /// Bepaalt of een moment voor de ontvanger (dit apparaat) bedoeld was.
  /// Voorkomt dat berichten die specifiek voor een ander familielid waren
  /// (aanUserUids/aanApparaatIds) in de ontvanger-lijst verschijnen.
  bool _isVoorOntvanger(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final aanUserUids = (d['aanUserUids'] as List?)?.cast<String>();
    final aanApparaatIds = (d['aanApparaatIds'] as List?)?.cast<String>();
    final aanLegacy = d['aanApparaatId'] as String?;
    if (aanUserUids != null && aanUserUids.isNotEmpty) {
      final mijnUid = FirebaseAuth.instance.currentUser?.uid;
      return mijnUid != null && aanUserUids.contains(mijnUid);
    }
    if (aanApparaatIds != null && aanApparaatIds.isNotEmpty) {
      return aanApparaatIds.contains(_mijnApparaatId);
    }
    if (aanLegacy != null) {
      return aanLegacy == _mijnApparaatId;
    }
    return true;  // geen targeting = voor iedereen in de kring
  }

  /// V9 2.15: veilige afzender-naam voor lijst-items op ontvanger-kant.
  String _afzenderNaam(Map<String, dynamic> d) {
    final raw = (d['vanNaam'] as String?)?.trim() ?? '';
    return raw.isNotEmpty ? raw : 'Iemand uit je kring';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    // V9 2.15: perspectief-afhankelijke bron-lijst en teksten.
    // Familie-kant: berichten van de ontvanger-apparaten (huidige gedrag).
    // Ontvanger-kant: berichten van de familie-apparaten (bugfix).
    final relevanteApparaatIds = widget.alsOntvanger
        ? _familieApparaatIds
        : _ontvangerApparaatIds;
    final titelTekst = widget.alsOntvanger
        ? 'Ontvangen berichten'
        : 'Ontvangen van $_toonNaam';
    final leegApparaatTekst = widget.alsOntvanger
        ? 'Er zijn nog geen familie-apparaten in deze kring'
        : 'Er is nog geen ontvanger-apparaat in deze kring';
    final leegLijstTekst = widget.alsOntvanger
        ? 'Nog geen berichten van je familie'
        : 'Nog geen berichten van $_toonNaam';
    return Scaffold(
      backgroundColor: kCream,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        iconTheme: const IconThemeData(color: kBrown),
        title: Text(titelTekst,
            style: const TextStyle(color: kBrown,
                fontWeight: FontWeight.w900)),
      ),
      body: uid == null
          ? const SizedBox()
          : (_kringId == null || relevanteApparaatIds == null
              ? const Center(child: CircularProgressIndicator(color: kPeach))
              : (relevanteApparaatIds.isEmpty
                  ? _leeg(leegApparaatTekst)
                  : StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('momenten')
                          .where('kringId', isEqualTo: _kringId)
                          .where('vanApparaatId',
                              whereIn: relevanteApparaatIds.take(10).toList())
                          .snapshots(),
                      builder: (ctx, snap) {
                        if (!snap.hasData) {
                          return const Center(
                              child: CircularProgressIndicator(color: kPeach));
                        }
                        // V9 2.15: op ontvanger-kant client-side targeting-
                        // filter zodat berichten die specifiek voor een
                        // familielid bedoeld waren niet in de lijst verschijnen.
                        // Familie-kant filtert niks (identiek aan huidige gedrag).
                        final alleDocs = snap.data!.docs;
                        final gefiltered = widget.alsOntvanger
                            ? alleDocs.where(_isVoorOntvanger).toList()
                            : alleDocs.toList();
                        gefiltered.sort((a, b) {
                          final ta = (a.data() as Map)['verstuurdOp']
                              as Timestamp?;
                          final tb = (b.data() as Map)['verstuurdOp']
                              as Timestamp?;
                          if (ta == null || tb == null) return 0;
                          return tb.compareTo(ta);
                        });
                        if (gefiltered.isEmpty) return _leeg(leegLijstTekst);
                        return ListView(
                          padding: const EdgeInsets.all(20),
                          children: gefiltered.map((doc) => _bouwItem(
                              context, doc.id, doc.data() as Map<String, dynamic>))
                              .toList(),
                        );
                      },
                    ))),
    );
  }

  Widget _leeg(String tekst) => Center(
    child: Padding(padding: const EdgeInsets.all(40),
      child: Text(tekst, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: kTextMuted))),
  );

  Widget _bouwItem(BuildContext context, String id, Map<String, dynamic> d) {
    final type = d['type'] as String? ?? '';
    final tekst = (d['bericht'] as String? ?? '').trim();
    final verstuurd = (d['verstuurdOp'] as Timestamp?)?.toDate();
    final gezien = d['gezien'] == true;
    return GestureDetector(
      onTap: () => _toonDetail(context, d),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kPeachLight, width: 2)),
        child: Row(children: [
          Text(_emoji(type), style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.alsOntvanger) ...[
                // V9 2.15: op ontvanger-kant per item wie het stuurde. Veilige
                // terugval bij ontbrekende naam matcht popup-fallback.
                Text(_afzenderNaam(d),
                    style: const TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w700, color: kBrown)),
                const SizedBox(height: 2),
              ],
              Text(_label(type), style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: kBrown)),
              if (tekst.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(tekst,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: kTextMuted)),
              ),
              if (verstuurd != null) Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_formatTijd(verstuurd),
                    style: const TextStyle(fontSize: 10, color: kTextMuted)),
              ),
          ])),
          if (!gezien) Container(
            width: 10, height: 10,
            decoration: const BoxDecoration(
                color: kPeach, shape: BoxShape.circle)),
        ]),
      ),
    );
  }

  void _toonDetail(BuildContext context, Map<String, dynamic> d) {
    showDialog(context: context, builder: (ctx) => Dialog(
      backgroundColor: kCream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(padding: const EdgeInsets.all(20),
        child: _detailInhoud(d)),
    ));
  }

  Widget _detailInhoud(Map<String, dynamic> d) {
    final type = d['type'] as String? ?? '';
    final bericht = (d['bericht'] as String? ?? '').trim();
    final url = d['mediaUrl'] as String? ?? '';
    if (type == 'foto') {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        if (url.isNotEmpty) ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(url, fit: BoxFit.cover)),
        if (bericht.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(bericht, style: const TextStyle(fontSize: 14, color: kBrown)),
        ],
      ]);
    }
    if (type == 'tekst') {
      return Text(bericht.isEmpty ? 'Een lief bericht' : bericht,
          style: const TextStyle(fontSize: 18, color: kBrown));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(_emoji(type), style: const TextStyle(fontSize: 48)),
      const SizedBox(height: 12),
      Text(_label(type), style: const TextStyle(fontSize: 16,
          fontWeight: FontWeight.w800, color: kBrown)),
      if (bericht.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(bericht, style: const TextStyle(fontSize: 14, color: kBrown)),
      ],
    ]);
  }

  String _emoji(String type) {
    switch (type) {
      case 'foto': return '📷';
      case 'stem': return '🎙️';
      case 'lied': return '🎵';
      case 'tekst': return '✏️';
      case 'video': return '🎥';
      default: return '💕';
    }
  }

  String _label(String type) {
    switch (type) {
      case 'foto': return 'Foto';
      case 'stem': return 'Stem-bericht';
      case 'lied': return 'Liedje';
      case 'tekst': return 'Tekst';
      case 'hartje': return 'Hartje';
      case 'video': return 'Video';
      default: return 'Bericht';
    }
  }

  String _formatTijd(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}-'
      '${t.month.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}
