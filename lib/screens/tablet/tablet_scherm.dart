import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../services/device_modus_service.dart';
import '../../services/kring_service.dart';
import '../../services/push_service.dart';
import '../../theme/kleuren.dart';
import '../../data/geluiden.dart';
import '../../data/debug_flags.dart';
import '../../data/kring.dart';
import '../../widgets/pulserend_hart.dart';
import '../../widgets/video_speler.dart';
import 'inkomend_gesprek_scherm.dart';
import '../videobellen/gesprek_scherm.dart';

class TabletScherm extends StatefulWidget {
  const TabletScherm({super.key});
  @override
  State<TabletScherm> createState() => _TabletSchermState();
}

class _TabletSchermState extends State<TabletScherm>
    with WidgetsBindingObserver {
  final _audioPlayer = AudioPlayer();
  final _geluidPlayer = AudioPlayer();
  Timer? _autoSluitTimer;
  StreamSubscription? _momentenListener;
  StreamSubscription<DocumentSnapshot>? _gebruikerSub;

  Map<String, dynamic>? _huidigPopup;
  String? _huidigPopupId;
  String _herkenningsgeluid = 'twinkel';

  Timer? _checkTimer;
  StreamSubscription<QuerySnapshot>? _dagelijkseSub;
  List<QueryDocumentSnapshot>? _dagelijkseDocs;
  StreamSubscription<QuerySnapshot>? _eenmaligSub;
  List<QueryDocumentSnapshot>? _eenmaligDocs;
  /// V9 2.27: lokale in-memory dedup naast Firestore's laatstGetoond/getoond.
  /// Wordt SYNCHROON gezet vóór de popup opent, zodat een re-check tussen
  /// popup-sluit en Firestore-snapshot-re-emit het moment niet nogmaals kan
  /// triggeren binnen het 10-min window. Voor dagelijks bevat de key ook de
  /// triggerKey (dag-key), zodat dagovergang zich vanzelf reset — een moment
  /// van gisteren mag vandaag opnieuw. Voor eenmalig alleen de doc.id (die
  /// maar één keer mag komen, niet per dag).
  final Set<String> _reedsGetoondLokaal = <String>{};

  /// Fase 2c: callback op [PushService.tapMomentIdNotifier]. Gecached
  /// zodat we bij dispose netjes remove-listener kunnen doen.
  VoidCallback? _tapMomentListener;
  /// V2-5: callback op [PushService.incomingCallNotifier]. Alleen
  /// geattacht als [DEBUG_VIDEOBELLEN] aan staat — met flag uit blijft
  /// deze null en wordt de belflow op deze tablet nergens bereikbaar.
  VoidCallback? _incomingCallListener;
  /// Reentrancy-guard: voorkomt dat een re-emit van de notifier tijdens
  /// een openstaand inkomend-gesprek-scherm nogmaals een scherm opent.
  bool _inkomendGesprekOpen = false;
  String? _mijnApparaatId;
  String? _kringId;
  // V9 2.4-a-2: kring-doc als primaire bron; _gebruikerSub blijft als
  // legacy-fallback zodat het popup-bel-geluid NOOIT stil kan worden.
  StreamSubscription<Kring?>? _actieveKringSub;
  String? _kringFoto;
  String? _kringOntvangerNaam;
  /// V9 2.9-perf-2: gecachte naam uit SharedPrefs voor de 'Hallo X'-
  /// banner. Alleen-fallback: zodra _kringOntvangerNaam of het
  /// gebruikers-doc een naam levert, neemt die het over.
  String? _gecachteOntvangerNaam;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
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
    DeviceModusService.huidigeKringIdMetFallback().then((id) async {
      if (!mounted) return;
      setState(() => _kringId = id);
      if (id != null) {
        // V9 2.13-a: wacht op _mijnApparaatId voordat de momenten-listener
        // attacht. Chain A (regel 58-62) laadt hetzelfde ID uit dezelfde
        // cache; is die nog niet klaar, dan halen we het hier direct op.
        // Voorkomt dat de initial snapshot van _startMomentenListener docs
        // met aanApparaatIds/aanApparaatId-targeting foutief als 'niet voor
        // mij' filtert — symptoom: 'eerste bericht komt pas bij een tweede'.
        if (_mijnApparaatId == null) {
          _debugLog('⏳ Wacht op apparaatId voor momenten-listener');
          final apparaatId = await DeviceModusService.krijgApparaatId();
          if (!mounted) return;
          if (_mijnApparaatId == null) {
            setState(() => _mijnApparaatId = apparaatId);
          }
        }

        _startMomentenListener();
        _startDagelijksListener();
        _startEenmaligListener();
        // V9 2.11-a-1: lees de gecachte ontvangerNaam met de juiste
        // kringId-tag zodat de 'Hallo X'-banner de naam van DEZE
        // kring toont, niet de laatst-gecachte naam van een andere
        // kring (was de bug uit 2.9-perf-2).
        final naam = await DeviceModusService
            .krijgGecachteOntvangerNaam(id);
        if (!mounted || naam == null || naam.isEmpty) return;
        setState(() => _gecachteOntvangerNaam = naam);
      }
    });
    _checkTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkGeplandeMomenten();
      _herscanMomenten();
    });

    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed
          && (_huidigPopup?['type'] == 'stem'
              || _huidigPopup?['type'] == 'lied'
              || _huidigPopup?['type'] == 'dagelijks')) {
        _sluitPopup();
      }
    });
    // V9 2.4-a-2: kring-doc is primaire bron voor geluid/foto/naam.
    // OVERSCHRIJFT ALLEEN bij niet-lege waarden — _gebruikerSub blijft
    // als legacy-fallback zodat _herkenningsgeluid nooit leeg wordt.
    _actieveKringSub = KringService.actieveKringStream().listen((kring) {
      if (!mounted || kring == null) return;
      setState(() {
        if (kring.herkenningsgeluid.isNotEmpty) {
          _herkenningsgeluid = kring.herkenningsgeluid;
        }
        if (kring.foto != null && kring.foto!.isNotEmpty) {
          _kringFoto = kring.foto;
        }
        if (kring.naam.isNotEmpty) {
          _kringOntvangerNaam = kring.naam;
        }
      });
    });
    _startTapMomentListener();
    _startIncomingCallListener();
  }

  /// Fase 2c: luistert op de tap-notifier van PushService. Wordt getriggerd
  /// bij een tik op een systeem-tray-notificatie (background of terminated
  /// launch). Fetcht het moment uit Firestore en toont het via de bestaande
  /// [_toonPopup]. Skip wanneer er al een popup open staat (reentrancy-guard
  /// via _huidigPopupId), en reset de notifier synchroon vóór de fetch zodat
  /// een re-emit hem niet nog eens laat afvuren. Op web blijft de notifier
  /// altijd null (PushService.initApp doet no-op via kIsWeb) — deze code
  /// draait daar dus zonder side-effect.
  void _startTapMomentListener() {
    void cb() { _verwerkTapMomentId(PushService.tapMomentIdNotifier.value); }
    PushService.tapMomentIdNotifier.addListener(cb);
    _tapMomentListener = cb;
    // Initial: als de notifier al gezet is (terminated-launch waarbij
    // initApp getInitialMessage al heeft gepubliceerd vóór dit scherm
    // bouwde), triggeren we de callback zelf — addListener doet dat niet.
    if (PushService.tapMomentIdNotifier.value != null) cb();
  }

  /// V2-5: attach de incomingCall-listener alleen als DEBUG_VIDEOBELLEN
  /// aan staat. Met flag uit blijft [PushService.incomingCallNotifier]
  /// eventueel wél op waarde staan (want PushService is niet flag-
  /// gated), maar niemand luistert dus er verandert niets aan het
  /// gedrag van de tablet.
  void _startIncomingCallListener() {
    if (!DEBUG_VIDEOBELLEN) return;
    void cb() { _verwerkInkomendGesprek(PushService.incomingCallNotifier.value); }
    PushService.incomingCallNotifier.addListener(cb);
    _incomingCallListener = cb;
    // Initial: als er al een call gepubliceerd is voordat dit scherm
    // bouwde (bv. FCM binnengekomen tijdens app-startup), triggeren we
    // de callback zelf — addListener doet dat niet.
    if (PushService.incomingCallNotifier.value != null) cb();
  }

  Future<void> _verwerkInkomendGesprek(IncomingCall? call) async {
    if (call == null) return;
    // Consumeer synchroon vóór de scherm-push zodat een re-emit tijdens
    // het scherm geen tweede scherm opent.
    PushService.incomingCallNotifier.value = null;
    if (_inkomendGesprekOpen) return;
    if (!mounted) return;
    _inkomendGesprekOpen = true;
    try {
      final navigator = Navigator.of(context);
      bool beantwoord = false;
      await navigator.push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => InkomendGesprekScherm(
          call: call,
          onBeantwoord: () {
            beantwoord = true;
            Navigator.of(navigator.context).pop();
          },
          onAfgewezen: () {
            Navigator.of(navigator.context).pop();
          },
        ),
      ));
      if (!mounted) return;
      if (beantwoord) {
        // V3-2: doorstroom naar GesprekScherm. Dat scherm doet zelf
        // VideoCallService.join(call.calleeToken) in initState en toont
        // ondertussen een dementie-vriendelijke 'Verbinden met {naam}…'-
        // status — geen leeg gat tussen tap en remote video. Fout tijdens
        // join wordt in GesprekScherm zelf afgehandeld (fout-fase +
        // sluiten-knop); tablet-side hoeft niet meer te reageren.
        await navigator.push(MaterialPageRoute<void>(
          builder: (_) => GesprekScherm(
            remoteNaam: call.callerName,
            tokenToJoin: call.calleeToken,
          ),
        ));
      }
    } finally {
      _inkomendGesprekOpen = false;
    }
  }

  Future<void> _verwerkTapMomentId(String? id) async {
    if (id == null || id.isEmpty) return;
    // Consumeer direct — synchroon vóór de async fetch — zodat een
    // re-emit tijdens de fetch niet dubbel afvuurt.
    PushService.tapMomentIdNotifier.value = null;
    if (_huidigPopupId != null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('momenten').doc(id).get();
      if (!mounted || !doc.exists) return;
      final data = doc.data();
      if (data == null) return;
      await _toonPopup(doc.id, data);
    } catch (_) {
      // Silent — fetch-fout mag app niet crashen. Bekende beperking:
      // moment in andere kring blokkeert Firestore-rules, dat komt hier
      // als exception binnen en wordt geskipt. Fase 3 pakt kring-switching.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_tapMomentListener != null) {
      PushService.tapMomentIdNotifier.removeListener(_tapMomentListener!);
      _tapMomentListener = null;
    }
    if (_incomingCallListener != null) {
      PushService.incomingCallNotifier.removeListener(_incomingCallListener!);
      _incomingCallListener = null;
    }
    _autoSluitTimer?.cancel();
    _checkTimer?.cancel();
    _momentenListener?.cancel();
    _gebruikerSub?.cancel();
    _actieveKringSub?.cancel();
    _dagelijkseSub?.cancel();
    _eenmaligSub?.cancel();
    _audioPlayer.dispose();
    _geluidPlayer.dispose();
    WakelockPlus.disable();
    super.dispose();
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

  /// V9 2.16: wacht tot _geluidPlayer klaar is met afspelen, met een harde
  /// max-wachttijd als vangnet. Gebruikt vóór het mounten van de VideoSpeler
  /// zodat het herkenningsgeluid niet afgekapt wordt door de audio-focus-
  /// claim van video_player op Android. Timeout garandeert dat de popup
  /// nooit langer dan [maxWacht] blokkeert — zelfs bij een defecte player.
  Future<void> _wachtOpBelKlaar(Duration maxWacht) async {
    // Al klaar? Direct terug — geen listener overhead.
    if (_geluidPlayer.playerState.processingState
        == ProcessingState.completed) {
      return;
    }
    final completer = Completer<void>();
    StreamSubscription<PlayerState>? sub;
    Timer? timeout;
    void afronden() {
      if (completer.isCompleted) return;
      sub?.cancel();
      timeout?.cancel();
      completer.complete();
    }
    sub = _geluidPlayer.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) afronden();
    });
    timeout = Timer(maxWacht, afronden);
    await completer.future;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _herscanMomenten();
      // V9 2.26: bij terug op de voorgrond ook geplande/dagelijkse momenten
      // opnieuw checken — zonder deze regel worden ze pas op de volgende
      // 30s-tick opgepikt en missen we een moment nét na standby.
      _checkGeplandeMomenten();
    }
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
    // Realtime listener — pakt nieuwe momenten direct op
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
        .listen((snap) {
      // V9 2.26: bij de EERSTE snapshot direct één check aftrappen zodat we
      // niet 30s hoeven te wachten op de Timer.periodic-tick. Dekt het gat
      // waarin de app precies na een dagelijks-moment opstart.
      final wasEersteSnapshot = _dagelijkseDocs == null;
      _dagelijkseDocs = snap.docs;
      if (wasEersteSnapshot) _checkGeplandeMomenten();
    });
  }

  void _startEenmaligListener() {
    final kringId = _kringId;
    if (kringId == null) return;
    _eenmaligSub = FirebaseFirestore.instance
        .collection('gepland_momenten')
        .where('kringId', isEqualTo: kringId)
        .where('actief', isEqualTo: true)
        .snapshots()
        .listen((snap) {
      // V9 2.26: eerste snapshot → direct check (mirror van dagelijks).
      final wasEersteSnapshot = _eenmaligDocs == null;
      _eenmaligDocs = snap.docs;
      if (wasEersteSnapshot) _checkGeplandeMomenten();
    });
  }

  void _verwerkMomenten(QuerySnapshot snap) {
    _debugLog('📨 Snap: ${snap.docs.length} momenten');
    if (_huidigPopupId != null) return;
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
      // Skip: eigen bericht (relevant als tablet in meldingen-modus stuurt)
      final van = d['vanApparaatId'] as String?;
      if (van != null && van == _mijnApparaatId) continue;
      final geplandOp = (d['geplandOp'] as Timestamp?)?.toDate();
      if (geplandOp == null) continue;
      // Toon als gepland tijd al voorbij is en niet ouder dan 24 uur
      if (geplandOp.isBefore(nu) && geplandOp.isAfter(voor24uur)) {
        _toonPopup(doc.id, d);
        return;
      }
    }
  }

  Future<void> _checkGeplandeMomenten() async {
    if (_huidigPopupId != null) return;
    final nu = DateTime.now();
    // V9 2.26: 10-min window als vangnet voor korte opstart-/standby-
    // vertragingen. Ruim genoeg om robuust te zijn, klein genoeg dat een
    // ochtendmoment niet 's middags nog verschijnt.
    const windowSec = 10 * 60;
    String dagKey(DateTime d) => '${d.year}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final vandaagKey = dagKey(nu);
    final gisteren = DateTime(nu.year, nu.month, nu.day)
        .subtract(const Duration(days: 1));
    final gisterenKey = dagKey(gisteren);

    if (_dagelijkseDocs != null) {
      for (final doc in _dagelijkseDocs!) {
        final d = doc.data() as Map<String, dynamic>;
        final uur = d['uur'] as int? ?? 0;
        final minuut = d['minuut'] as int? ?? 0;
        // V9 2.26: bepaal trigger als echte DateTime (vandaag of gisteren)
        // zodat een 23:59-moment ook net na middernacht wordt herkend.
        final momentVandaag =
            DateTime(nu.year, nu.month, nu.day, uur, minuut);
        final momentGisteren =
            momentVandaag.subtract(const Duration(days: 1));
        String? triggerKey;
        if (!nu.isBefore(momentVandaag)
            && nu.difference(momentVandaag).inSeconds <= windowSec) {
          triggerKey = vandaagKey;
        } else if (!nu.isBefore(momentGisteren)
            && nu.difference(momentGisteren).inSeconds <= windowSec) {
          triggerKey = gisterenKey;
        }
        if (triggerKey == null) continue;
        // V9 2.27: lokale dedup EERST — dekt het gat tussen popup-sluit en
        // Firestore-snapshot-re-emit. Overleeft niet cold restart, maar dan
        // valt laatstGetoond terug als backup.
        final lokaleKey = 'dagelijks_${doc.id}_$triggerKey';
        if (_reedsGetoondLokaal.contains(lokaleKey)) continue;
        if (d['laatstGetoond'] == triggerKey) continue;

        // V9 2.26: popup EERST (die claimt synchroon _huidigPopupId), pas
        // daarna laatstGetoond schrijven — zo verliezen we het moment niet
        // als de app precies tussen write en render crasht.
        // V9 2.27: lokale markering óók synchroon vóór de async popup-flow,
        // zodat een re-check tijdens/na de popup het moment niet opnieuw
        // pakt. Bij popupId-mismatch (andere popup claimde eerst) rollback
        // van de lokale markering — anders zou het moment stil verloren gaan.
        final popupId = 'dagelijks_${doc.id}';
        _reedsGetoondLokaal.add(lokaleKey);
        await _toonDagelijksPopup(doc.id, d);
        if (_huidigPopupId != popupId) {
          _reedsGetoondLokaal.remove(lokaleKey);
          return;
        }
        try {
          await doc.reference.update({'laatstGetoond': triggerKey});
        } catch (_) {}
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

        // V9 2.27: lokale dedup (zelfde reden als dagelijks).
        final lokaleKey = 'eenmalig_${doc.id}';
        if (_reedsGetoondLokaal.contains(lokaleKey)) continue;

        // V9 2.26: popup EERST, daarna markeren — zelfde reden als bij
        // dagelijks (crash-veilig).
        // V9 2.27: lokale markering óók synchroon vóór de async popup-flow.
        final popupId = 'eenmalig_${doc.id}';
        _reedsGetoondLokaal.add(lokaleKey);
        await _toonEenmaligPopup(doc.id, d);
        if (_huidigPopupId != popupId) {
          _reedsGetoondLokaal.remove(lokaleKey);
          return;
        }
        try {
          await doc.reference.update({'getoond': true});
        } catch (_) {}
        return;
      }
    }
  }

  Future<void> _toonDagelijksPopup(
      String id, Map<String, dynamic> d) async {
    final aangepasteAudio = d['aangepasteAudioUrl'] as String? ?? '';
    _debugLog('▶️ Dagelijks: ${d['label']} '
        '(eigenAudio=${aangepasteAudio.isNotEmpty})');
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

  Future<void> _toonPopup(String id, Map<String, dynamic> d) async {
    if (_huidigPopupId != null) return;
    // Claim slot direct (synchroon) zodat _verwerkMomenten geen tweede
    // popup start tijdens de async setup hieronder.
    _huidigPopupId = id;

    // Markeer gezien zodat na tablet-reboot niet alle ongeziene momenten
    // van afgelopen 24u opnieuw als popup verschijnen.
    try {
      await FirebaseFirestore.instance.collection('momenten')
          .doc(id).update({'gezien': true});
    } catch (_) {}

    // V9 2.16: type-lookup naar voren gehaald zodat de bel-branch kan
    // differentiëren tussen video en de rest.
    final type = d['type'];

    // Speel herkenningsgeluid.
    // - Bij VIDEO: wacht op echte completion van de bel (max 3000ms vangnet),
    //   want Android's video_player-plugin claimt audio-focus bij initialize
    //   en zou de bel anders abrupt afkappen zodra de VideoSpeler mount.
    // - Bij andere types: vaste 1200ms delay (bestaand gedrag, niet aanraken).
    // - Skip de bel bij dagelijks/eenmalig-popups met aangepaste audio —
    //   eigen audio wordt anders door de bel overstemd (bestaand gedrag).
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
        if (type == 'video') {
          await _wachtOpBelKlaar(const Duration(milliseconds: 3000));
        } else {
          await Future.delayed(const Duration(milliseconds: 1200));
        }
      }
    }

    if (!mounted) {
      _huidigPopupId = null;
      return;
    }
    setState(() {
      _huidigPopup = d;
    });

    if (type == 'stem' || type == 'lied' || type == 'dagelijks') {
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
    // 60s zodat dementie-doelgroep tijd heeft om te verwerken;
    // ook fallback als audio niet eindigt of niet aanwezig is.
    _autoSluitTimer?.cancel();
    final sluitNa = (d['type'] == 'hartje') ? 10 : 60;
    _autoSluitTimer = Timer(Duration(seconds: sluitNa), _sluitPopup);
  }

  Future<void> _sluitPopup() async {
    await _audioPlayer.stop();
    _autoSluitTimer?.cancel();
    // gezien:true is al gezet aan het begin van _toonPopup
    if (mounted) {
      setState(() {
        _huidigPopup = null;
        _huidigPopupId = null;
      });
    }
    // Toon na een korte rustpauze een eventueel gemist bericht (Bug A) EN
    // een gemist dagelijks/eenmalig moment (V9 2.26). Nodig als er meerdere
    // momenten op (bijna) hetzelfde tijdstip staan: zonder deze extra check
    // zou de 2e/3e pas op de volgende 30s-tick worden opgepikt en dan
    // mogelijk al buiten het 10-min window vallen.
    Future.delayed(const Duration(milliseconds: 500), () {
      _herscanMomenten();
      _checkGeplandeMomenten();
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(backgroundColor: kCream);

    // StreamBuilder voor gebruikersdata - live updates van profielfoto + naam
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('gebruikers')
          .doc(uid).snapshots(),
      builder: (ctx, userSnap) {
        final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
        // V9 2.4-a-2: kring-doc primaire bron; gebruikers/{uid} fallback
        // voor V7/V8-accounts zonder kring-doc.
        final profielFotoUrl = (_kringFoto != null && _kringFoto!.isNotEmpty)
            ? _kringFoto!
            : (userData['ontvangerFoto'] as String? ?? '');
        // V9 2.9-perf-2: drielagige naam-resolutie. Kring-doc > gebruikers-
        // doc > SharedPrefs-cache. Cache zorgt dat de banner direct
        // verschijnt; bestaande live-bronnen overschrijven 'm zodra binnen.
        final naamUitDoc = (userData['ontvangerNaam'] as String?) ?? '';
        final ontvangerNaam =
            (_kringOntvangerNaam != null && _kringOntvangerNaam!.isNotEmpty)
                ? _kringOntvangerNaam!
                : (naamUitDoc.isNotEmpty
                    ? naamUitDoc
                    : (_gecachteOntvangerNaam ?? ''));

        return Scaffold(
          // V9 2.26: Stack in SizedBox.expand zodat hij tight body-hoogte
          // krijgt. Zonder dit krimpt de Stack naar de intrinsieke hoogte
          // van _homeInhoud, waardoor de popup (nu Positioned.fill) niet
          // gegarandeerd het volle scherm vulde. StackFit blijft loose zodat
          // _homeInhoud zijn eigen opmaak behoudt; alleen de popup pakt nu
          // gegarandeerd de volle body-hoogte.
          body: SizedBox.expand(child: Stack(children: [
            // ━━━━ ACHTERGROND ━━━━
            Positioned.fill(child: profielFotoUrl.isNotEmpty
              ? Image.network(profielFotoUrl,
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
                        colors: [kPeachPale, kCream]))))
              : Container(decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [kPeachPale, kCream])))),

            // ━━━━ OVERLAY voor leesbare tekst ━━━━
            Positioned.fill(child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: profielFotoUrl.isNotEmpty ? [
                    Colors.black.withOpacity(0.55),
                    Colors.black.withOpacity(0.20),
                    Colors.black.withOpacity(0.65),
                  ] : [
                    Colors.transparent,
                    Colors.transparent,
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0]),
              ),
            )),

            // ━━━━ INHOUD ━━━━
            SafeArea(child: _homeInhoud(ontvangerNaam,
                hasBackground: profielFotoUrl.isNotEmpty)),

            // ━━━━ POPUP ━━━━
            if (_huidigPopup != null) Positioned.fill(
              child: GestureDetector(
                onTap: _sluitPopup, child: _popupOverlay())),
          ])),
        );
      },
    );
  }

  Widget _homeInhoud(String naam, {required bool hasBackground}) {
    final textColor = hasBackground ? kWhite : kBrown;
    final shadow = hasBackground ? [
      Shadow(color: Colors.black.withOpacity(0.6),
          blurRadius: 12, offset: const Offset(0, 3))
    ] : <Shadow>[];

    // V9 2.28: scroll-vangnet voor krappe schermen (bv. tablet in landscape
    // of klein toestel met veel systeembalk). Op ruime schermen verandert
    // er niets: minHeight = beschikbare hoogte + IntrinsicHeight + Column
    // met mainAxisAlignment.center houdt de content verticaal gecentreerd.
    // Zodra de inhoud niet meer past, wordt het geheel scrollbaar i.p.v.
    // een gele overflow-banner te tonen.
    //
    // V9 2.30 (tablet-fit):
    // - schaal-factor op basis van shortestSide zodat teksten, emoji's en
    //   iconen mee-groeien op tablets. Op mobiel (shortestSide <=400)
    //   blijft schaal 1.0 → geen verslechtering. Cap op 1.6 voorkomt
    //   onnodig grote UI op ultra-brede toestellen.
    // - maxWidth verruimd naar 800 op grote tablets zodat de content niet
    //   'verdwaald in het midden' oogt op 10-12-inch portrait.
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final schaal = (shortestSide / 400).clamp(1.0, 1.6);
    final maxWidth = shortestSide < 600 ? 640.0 : 800.0;
    return Center(child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: LayoutBuilder(builder: (ctx, cons) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: cons.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _Klok(
                        textColor: textColor,
                        shadow: shadow,
                        schaal: schaal),
                    const SizedBox(height: 36),

                    // DAGDEEL-GEVOELIGE BEGROETING
                    if (naam.isNotEmpty) _DagdeelGroet(
                        naam: naam,
                        textColor: textColor,
                        shadow: shadow,
                        hasBackground: hasBackground,
                        schaal: schaal),
                    const SizedBox(height: 28),

                    // DAGOVERZICHT: vaste + geplande momenten van vandaag.
                    // SizedBox(width: infinity) zorgt dat de tijdlijn de
                    // volle kolombreedte pakt — anders zou de Column met
                    // .center de _dagOverzicht als 'min-width' chip
                    // renderen ondanks stretch binnenin.
                    SizedBox(
                        width: double.infinity,
                        child: _dagOverzicht(
                            hasBackground: hasBackground,
                            schaal: schaal)),
                  ]),
              ),
            ),
          ),
        );
      }),
    ));
  }

  /// V9 2.29: rustig dagoverzicht voor de kiosk-modus. Toont alle vaste
  /// (dagelijkse_momenten) en geplande (gepland_momenten die op vandaag
  /// vallen) momenten van vandaag als één tijdlijn met drie visuele
  /// statussen: verleden compact/grijs met vinkje, nu/aankomend (binnen
  /// 15 min) met peach-accent, toekomst als normale peach-pale kaart.
  ///
  /// Gebruikt DEZELFDE streams als de oude _volgendeMomentKaart deed —
  /// geen extra Firestore-verkeer. Puur informatief: geen tap-acties, dus
  /// dedup/popup-flow blijft ongemoeid. Verstuurde `momenten` worden hier
  /// bewust NIET getoond — die blijven via de auto-popup binnenkomen.
  Widget _dagOverzicht({required bool hasBackground, required double schaal}) {
    final kringId = _kringId;
    if (kringId == null) return const SizedBox();
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('dagelijkse_momenten')
          .where('kringId', isEqualTo: kringId)
          .where('actief', isEqualTo: true).snapshots(),
      builder: (ctx, dagelijksSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('gepland_momenten')
              .where('kringId', isEqualTo: kringId)
              .where('actief', isEqualTo: true).snapshots(),
          builder: (ctx, eenmaligSnap) {
            // Wacht tot BEIDE streams hun eerste snapshot hebben geleverd
            // — anders zou een eenmalig moment ontbreken tijdens het laden.
            if (!dagelijksSnap.hasData || !eenmaligSnap.hasData) {
              return _placeholderKaart(schaal: schaal);
            }
            final nu = DateTime.now();
            final beginVandaag = DateTime(nu.year, nu.month, nu.day);
            final eindVandaag = beginVandaag.add(const Duration(days: 1));
            final items = <_DagMoment>[];

            // Dagelijkse: tijd = VANDAAG op uur:minuut. Niet verschuiven
            // naar morgen — verleden willen we juist tonen (grijs/vinkje).
            for (final doc in dagelijksSnap.data!.docs) {
              final d = doc.data() as Map<String, dynamic>;
              final uur = d['uur'] as int? ?? 0;
              final minuut = d['minuut'] as int? ?? 0;
              final tijd =
                  DateTime(nu.year, nu.month, nu.day, uur, minuut);
              items.add(_DagMoment(
                tijd: tijd,
                emoji: d['emoji'] as String? ?? '⭐',
                label: d['label'] as String? ?? 'Moment',
                status: _bepaalStatus(tijd, nu),
              ));
            }

            // Eenmalige: alleen als geplandOp op vandaag valt.
            for (final doc in eenmaligSnap.data!.docs) {
              final d = doc.data() as Map<String, dynamic>;
              final geplandOp = (d['geplandOp'] as Timestamp?)?.toDate();
              if (geplandOp == null) continue;
              if (geplandOp.isBefore(beginVandaag)) continue;
              if (!geplandOp.isBefore(eindVandaag)) continue;
              items.add(_DagMoment(
                tijd: geplandOp,
                emoji: d['emoji'] as String? ?? '⭐',
                label: d['label'] as String? ?? 'Moment',
                status: _bepaalStatus(geplandOp, nu),
              ));
            }

            if (items.isEmpty) return _legeDagKaart(schaal: schaal);
            items.sort((a, b) => a.tijd.compareTo(b.tijd));

            // V9 2.30: crossAxisAlignment.stretch maakt elke regel vol-
            // breedte → tijden lopen onder elkaar, nu-peach wordt een
            // brede opvallende kaart in plaats van een chip.
            // De sectie-titel blijft een pil (via Center-wrapping).
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: _sectieTitel('Vandaag',
                    hasBackground: hasBackground, schaal: schaal)),
                const SizedBox(height: 12),
                ...items.map((m) => _dagMomentRegel(m,
                    hasBackground: hasBackground, schaal: schaal)),
              ]);
          },
        );
      },
    );
  }

  /// Bepaalt de visuele status van een moment op basis van het verschil
  /// tussen `tijd` en `nu`. Marge van -1 min voorkomt flikkeren op het
  /// exacte moment; window van 15 min voor 'nu/aankomend' matcht het
  /// popup-window in _checkGeplandeMomenten (10 min) ruim genoeg zodat
  /// de gebruiker het accent al ziet vóór de popup verschijnt.
  _MomentStatus _bepaalStatus(DateTime tijd, DateTime nu) {
    final verschil = tijd.difference(nu);
    if (verschil.inMinutes < -1) return _MomentStatus.verleden;
    if (verschil.inMinutes <= 15) return _MomentStatus.nu;
    return _MomentStatus.toekomst;
  }

  String _formatUurMinuut(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  Widget _sectieTitel(String tekst,
      {required bool hasBackground, required double schaal}) {
    // V9 2.30: fontSize van 11 → 15 * schaal. Op mobiel oogt de badge nu
    // wat prominenter (was op afstand slecht leesbaar); op tablet groeit
    // hij mee zodat 'Vandaag' de kop van het dagoverzicht wordt.
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: 16 * schaal, vertical: 7 * schaal),
      decoration: BoxDecoration(
        color: hasBackground ? kWhite.withOpacity(0.2) : kPeachPale,
        borderRadius: BorderRadius.circular(20)),
      child: Text(tekst,
          style: TextStyle(fontSize: 15 * schaal,
              color: hasBackground ? kWhite : kBrown,
              fontWeight: FontWeight.w800, letterSpacing: 0.8)),
    );
  }

  Widget _placeholderKaart({required double schaal}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kWhite.withOpacity(0.94),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2),
            blurRadius: 20, offset: const Offset(0, 6))]),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 24 * schaal, height: 24 * schaal,
          child: const CircularProgressIndicator(
              color: kPeach, strokeWidth: 3)),
        const SizedBox(width: 14),
        Text('Even klaarzetten...',
            style: TextStyle(fontSize: 18 * schaal,
                fontWeight: FontWeight.w700, color: kBrown)),
      ]),
    );
  }

  Widget _legeDagKaart({required double schaal}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kWhite.withOpacity(0.94),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15),
            blurRadius: 16, offset: const Offset(0, 4))]),
      child: Text('Vandaag geen vaste momenten — geniet ervan 💕',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18 * schaal,
              fontWeight: FontWeight.w700,
              color: kBrown, height: 1.4)),
    );
  }

  /// Rendert één regel van het dagoverzicht op basis van de status.
  /// Verleden = compact/grijs/vinkje, nu = peach-accent/pijl/groter,
  /// toekomst = normale peach-pale kaart. Bewust GEEN GestureDetector —
  /// tap-acties zouden de dedup/popup-flow doorbreken.
  ///
  /// V9 2.30: alle Row's zonder MainAxisSize.min (default = max) zodat de
  /// container vol-breedte pakt en tijden onder elkaar staan. Flexible om
  /// het label opvangen bij lange teksten (ellipsis). Fontsizes schalen
  /// met [schaal] zodat regels op tablet groter zijn.
  Widget _dagMomentRegel(_DagMoment m,
      {required bool hasBackground, required double schaal}) {
    final tijd = _formatUurMinuut(m.tijd);
    switch (m.status) {
      case _MomentStatus.verleden:
        // Compact, grijs, vinkje links. Bij foto-achtergrond een subtiele
        // glazen container voor leesbaarheid — opacity 0.15 → 0.28 zodat
        // tekst leesbaar blijft op detailrijke foto's.
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: EdgeInsets.symmetric(
              horizontal: 14 * schaal, vertical: 8 * schaal),
          decoration: BoxDecoration(
            color: hasBackground
                ? kWhite.withOpacity(0.28) : Colors.transparent,
            borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(Icons.check_rounded,
                size: 18 * schaal,
                color: hasBackground ? kWhite : kTextMuted),
            SizedBox(width: 10 * schaal),
            Text(tijd,
                style: TextStyle(fontSize: 15 * schaal,
                    fontWeight: FontWeight.w600,
                    color: hasBackground ? kWhite : kTextMuted)),
            SizedBox(width: 12 * schaal),
            Text(m.emoji, style: TextStyle(fontSize: 20 * schaal)),
            SizedBox(width: 10 * schaal),
            Expanded(child: Text(m.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15 * schaal,
                    fontWeight: FontWeight.w600,
                    color: hasBackground ? kWhite : kTextMuted))),
          ]),
        );

      case _MomentStatus.nu:
        // Warm accent: kPeach achtergrond, wit tekst, pijl links, groter,
        // zachte schaduw voor 'lift'. Vol-breedte zodat het als kaart
        // valt op i.p.v. als chip.
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: EdgeInsets.symmetric(
              horizontal: 18 * schaal, vertical: 16 * schaal),
          decoration: BoxDecoration(
            color: kPeach,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(
                color: kPeach.withOpacity(0.35),
                blurRadius: 20, offset: const Offset(0, 6))]),
          child: Row(children: [
            Icon(Icons.arrow_forward_rounded,
                size: 22 * schaal, color: kWhite),
            SizedBox(width: 12 * schaal),
            Text(tijd,
                style: TextStyle(fontSize: 20 * schaal,
                    fontWeight: FontWeight.w800, color: kWhite)),
            SizedBox(width: 14 * schaal),
            Text(m.emoji, style: TextStyle(fontSize: 28 * schaal)),
            SizedBox(width: 12 * schaal),
            Expanded(child: Text(m.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 20 * schaal,
                    fontWeight: FontWeight.w800, color: kWhite))),
          ]),
        );

      case _MomentStatus.toekomst:
        // Normale peach-pale kaart, matcht de visuele taal van de oude
        // 'volgende moment'-kaart maar dan per regel en vol-breedte.
        // De lege SizedBox(22) links spiegelt de icoon-breedte van
        // verleden/nu zodat de tijden onder elkaar uitgelijnd staan.
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: EdgeInsets.symmetric(
              horizontal: 16 * schaal, vertical: 12 * schaal),
          decoration: BoxDecoration(
            color: kPeachPale,
            borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            SizedBox(width: 22 * schaal),
            Text(tijd,
                style: TextStyle(fontSize: 17 * schaal,
                    fontWeight: FontWeight.w700, color: kBrown)),
            SizedBox(width: 14 * schaal),
            Text(m.emoji, style: TextStyle(fontSize: 24 * schaal)),
            SizedBox(width: 12 * schaal),
            Expanded(child: Text(m.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17 * schaal,
                    fontWeight: FontWeight.w700, color: kBrown))),
          ]),
        );
    }
  }

  Widget _popupOverlay() {
    final d = _huidigPopup!;
    final type = d['type'] ?? '';
    // V9 2.25: popup vult nu de volledige beschikbare ruimte tussen de
    // systeembalken (SafeArea) en laat de inhoud (Expanded) de plek pakken
    // die overblijft na kop + sluit-hint. Geen vaste chrome-berekening,
    // geen BoxFit.cover-crop meer — foto/video gebruikt BoxFit.contain
    // zodat de hele foto zichtbaar is op elk toestel.
    final bool isMedia = type == 'foto' || type == 'video';
    final vanRaw = (d['vanNaam'] as String?)?.trim() ?? '';
    final vanNaam = vanRaw.isNotEmpty ? vanRaw : 'Iemand uit je kring';
    final geplandOp = (d['geplandOp'] as Timestamp?)?.toDate();
    return Container(color: kBrown.withOpacity(0.94),
      child: SafeArea(child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(builder: (ctx, cons) {
          // Kaartbreedte cap 1100 voor desktop/tablet; op mobiel = de volle
          // beschikbare breedte na de padding (16 links + 16 rechts).
          final kaartBreedte = cons.maxWidth.clamp(0.0, 1100.0);
          return Center(child: SizedBox(
            width: kaartBreedte,
            height: cons.maxHeight,
            child: Container(
              decoration: BoxDecoration(color: kCream,
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3),
                      blurRadius: 40)]),
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: 16, vertical: isMedia ? 22 : 32),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (type != 'hartje' && !isMedia) ...[
                      Text(_emojiVoorType(type),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 96)),
                      const SizedBox(height: 12),
                    ],
                    if (isMedia)
                      // Emoji inline vóór de tekst — één regel, wraps netjes
                      // (TextSpan → dezelfde tekstflow). Emoji iets groter
                      // dan de tekst (22 vs 20) voor een warm accent zonder
                      // te domineren.
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(
                              text: '${_emojiVoorType(type)}  ',
                              style: const TextStyle(fontSize: 22)),
                          TextSpan(
                              text: '$vanNaam stuurt je een bericht'),
                        ]),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: kBrown,
                            height: 1.2),
                      )
                    else
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
                    SizedBox(height: isMedia ? 12 : 20),
                    Expanded(child: _popupInhoud(d)),
                    if (geplandOp != null && type != 'dagelijks') ...[
                      const SizedBox(height: 12),
                      Text(_formatPopupTijd(geplandOp),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16,
                              color: kTextMuted,
                              fontStyle: FontStyle.italic)),
                    ],
                    const SizedBox(height: 10),
                    Text(type == 'stem' || type == 'lied'
                        ? 'Sluit automatisch wanneer klaar'
                        : (type == 'dagelijks'
                            ? 'Sluit automatisch'
                            : 'Tik om te sluiten'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 14, color: kTextMuted)),
                  ]),
              ),
            ),
          ));
        }),
      )),
    );
  }

  Widget _popupInhoud(Map<String, dynamic> d) {
    final type = d['type'] ?? '';
    final bericht = d['bericht'] ?? '';
    final url = d['mediaUrl'] ?? '';
    switch (type) {
      case 'foto':
        // V9 2.25: foto pakt de beschikbare Expanded-ruimte met
        // BoxFit.contain zodat de hele foto zichtbaar is (geen crop van
        // hoofd/randen). Optioneel bijschrift onder de foto.
        if (url.isEmpty) return const SizedBox();
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                color: kPeachPale,
                width: double.infinity,
                height: double.infinity,
                child: Image.network(url,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                  loadingBuilder: (c, child, prog) {
                    if (prog == null) return child;
                    return Container(color: kPeachPale,
                      child: const Center(
                          child: CircularProgressIndicator(color: kPeach)));
                  },
                  errorBuilder: (c, e, s) => Container(color: kPeachPale,
                    child: const Center(child: Icon(Icons.broken_image,
                        size: 96, color: kPeach))),
                ),
              ),
            )),
            if (bericht.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(bericht, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24,
                      color: kBrown, height: 1.4)),
            ],
          ]);
      case 'stem':
      case 'lied':
        return Center(child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
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
          ]),
        ));
      case 'tekst':
        return Center(child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            decoration: BoxDecoration(
                color: kPeachPale,
                borderRadius: BorderRadius.circular(24)),
            child: Text(
                bericht.isEmpty ? 'Een lief bericht voor jou' : bericht,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 40, color: kBrown,
                    height: 1.5, fontWeight: FontWeight.w600)),
          ),
        ));
      case 'dagelijks':
        // V9 2.25: emoji-grootte gebaseerd op de daadwerkelijke box
        // (Expanded-ruimte), niet op het hele scherm — schaalt vanzelf
        // mee met het kader en past op elk toestel.
        return LayoutBuilder(builder: (ctx, cons) {
          final emojiSize = (cons.biggest.shortestSide * 0.42)
              .clamp(120.0, 260.0);
          return Center(child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(d['emoji'] as String? ?? '⭐',
                  style: TextStyle(fontSize: emojiSize)),
              const SizedBox(height: 24),
              Text(d['label'] as String? ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 44,
                      fontWeight: FontWeight.w800,
                      color: kBrown, height: 1.2)),
            ]),
          ));
        });
      case 'hartje':
        // V9 2.25: hartje-grootte gebaseerd op de daadwerkelijke box.
        return LayoutBuilder(builder: (ctx, cons) {
          final hartjeSize = (cons.biggest.shortestSide * 0.85)
              .clamp(180.0, 500.0);
          return Center(child: PulserendHart(grootte: hartjeSize));
        });
      case 'video':
        // V9 2.25: VideoSpeler behoudt zijn eigen AspectRatio; Center
        // zorgt dat portret-video's netjes gecentreerd worden in het kader.
        // Zwart kader vult de letterbox-ruimte natuurlijk aan.
        return ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Container(
            color: Colors.black,
            width: double.infinity,
            height: double.infinity,
            child: Center(child: VideoSpeler(url: url)),
          ),
        );
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

  String _formatPopupTijd(DateTime d) {
    return 'Verstuurd om ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

class _Klok extends StatefulWidget {
  final Color textColor;
  final List<Shadow> shadow;
  /// V9 2.30: schaal-factor uit _homeInhoud (shortestSide-gebaseerd).
  /// Op mobiel 1.0, op tablet groter zodat de klok herkenbaar blijft.
  final double schaal;
  const _Klok({
    required this.textColor,
    required this.shadow,
    required this.schaal,
  });
  @override
  State<_Klok> createState() => _KlokState();
}

class _KlokState extends State<_Klok> {
  Timer? _timer;
  DateTime _nu = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1),
        (_) => setState(() => _nu = DateTime.now()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.schaal;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(_formatTijd(_nu),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 110 * s,
              fontWeight: FontWeight.w900, color: widget.textColor, height: 1,
              shadows: widget.shadow)),
      const SizedBox(height: 4),
      Text(_formatDatum(_nu),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20 * s,
              fontWeight: FontWeight.w700, color: widget.textColor,
              shadows: widget.shadow)),
    ]);
  }

  String _formatTijd(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _formatDatum(DateTime d) {
    const dagen = ['Maandag', 'Dinsdag', 'Woensdag', 'Donderdag',
                   'Vrijdag', 'Zaterdag', 'Zondag'];
    const maanden = ['januari', 'februari', 'maart', 'april', 'mei', 'juni',
                     'juli', 'augustus', 'september', 'oktober', 'november', 'december'];
    return '${dagen[d.weekday - 1]} ${d.day} ${maanden[d.month - 1]}';
  }
}

/// V9 2.29: één type voor items in het dagoverzicht — dagelijkse en
/// eenmalige momenten met dezelfde velden. `status` bepaalt de visuele
/// staat (verleden / nu / toekomst), berekend uit tijd vs. now via
/// _bepaalStatus in _TabletSchermState.
enum _MomentStatus { verleden, nu, toekomst }

class _DagMoment {
  final DateTime tijd;
  final String emoji;
  final String label;
  final _MomentStatus status;
  const _DagMoment({
    required this.tijd,
    required this.emoji,
    required this.label,
    required this.status,
  });
}

/// V9 2.29: dagdeel-gevoelige begroeting die zichzelf elke minuut ververst
/// zodat de tekst mee-schuift met de klok (bv. van 'Goedemorgen' naar
/// 'Goedemiddag' om 12:00). Spiegel van _Klok qua timer-patroon. De vaste
/// 💕-emoji blijft — is de handtekening van de app en minder verwarrend
/// voor de doelgroep dan een wisselende dagdeel-emoji.
class _DagdeelGroet extends StatefulWidget {
  final String naam;
  final Color textColor;
  final List<Shadow> shadow;
  final bool hasBackground;
  /// V9 2.30: schaal-factor voor tablet-leesbaarheid.
  final double schaal;
  const _DagdeelGroet({
    required this.naam,
    required this.textColor,
    required this.shadow,
    required this.hasBackground,
    required this.schaal,
  });
  @override
  State<_DagdeelGroet> createState() => _DagdeelGroetState();
}

class _DagdeelGroetState extends State<_DagdeelGroet> {
  Timer? _timer;
  DateTime _nu = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1),
        (_) => setState(() => _nu = DateTime.now()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _groet() {
    final uur = _nu.hour;
    if (uur >= 5 && uur < 12) return 'Goedemorgen';
    if (uur >= 12 && uur < 18) return 'Goedemiddag';
    if (uur >= 18 && uur < 23) return 'Goedenavond';
    return 'Fijne nacht';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.schaal;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: 28 * s, vertical: 14 * s),
      decoration: BoxDecoration(
        color: widget.hasBackground
            ? kWhite.withOpacity(0.25) : kPeachPale,
        borderRadius: BorderRadius.circular(50),
        border: widget.hasBackground
            ? Border.all(color: kWhite.withOpacity(0.5), width: 1.5)
            : null),
      child: Text('${_groet()}, ${widget.naam} 💕',
          style: TextStyle(fontSize: 26 * s,
              fontWeight: FontWeight.w800, color: widget.textColor,
              shadows: widget.shadow)),
    );
  }
}
