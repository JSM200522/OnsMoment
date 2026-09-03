import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'screens/setup/setup_wizard.dart';
import 'screens/familie/familie_scherm.dart';
import 'screens/tablet/tablet_scherm.dart';
import 'screens/tablet/inkomend_gesprek_scherm.dart';
import 'screens/videobellen/auto_opnemen_waarschuwing_scherm.dart';
import 'screens/videobellen/gesprek_scherm.dart';
import 'services/apparaat_service.dart';
import 'services/bel_callkit_service.dart';
import 'services/callkit_flag_service.dart';
import 'services/device_modus_service.dart';
import 'services/crash_service.dart';
import 'services/push_service.dart';
import 'data/debug_flags.dart';
import 'theme/kleuren.dart';

/// App-niveau messenger zodat een toast (bv. force-logout) zichtbaar blijft
/// terwijl de widget-tree naar het login-scherm rebuildt.
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // Fase 3d-C4: Crashlytics zo vroeg mogelijk zodat crashes tijdens de
  // rest van de init óók worden gerapporteerd. Web-veilig (no-op) en
  // fail-soft — spiegelt het PushService-patroon.
  await CrashService.initApp();
  // A2: edge-to-edge + donkere iconen als standaard voor status- en
  // navigatiebalk. Content-schermen draaien op crème-achtergrond; dark
  // icons zijn daar leesbaar. Full-bleed video-schermen zijn te kort voor
  // een eigen override — acceptabel. Insets worden 100% via OS geleverd
  // (MediaQuery); nergens in de app staan hardcoded statusbar-hoogtes.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  // Fase 1 push-meldingen: FCM-basis opzetten (background-handler,
  // notification channel, foreground/tap-listeners). No-op op web dankzij
  // kIsWeb-guard in PushService. Faalt silent bij Play Services-fouten —
  // de rest van de app blijft dan werken via de bestaande Firestore-
  // listeners.
  await PushService.initApp();
  // BEL-B2: fire-and-forget callkit-plugin warm-up. Volledig async,
  // niet ge-awaited, alle fouten intern gevangen — mag onmogelijk de
  // app-opstart blokkeren of crashen.
  unawaited(BelCallkitService.warmupProbe());
  // BEL-B3-B7 flag-warmup: async lookup zodat CallkitFlagService.
  // isEnabledSync() vanaf ~1s na app-start een verse waarde heeft.
  // Fail-soft naar OFF bij Firestore-fout — Optie A blijft dan dragen.
  unawaited(CallkitFlagService.isEnabled());
  // BEL-B5: event-stream luisteraar voor Opnemen/Weigeren-taps in de
  // native call-UI. Idempotent + fail-soft.
  unawaited(BelCallkitService.luisterEvents());
  // BEL-E4: cold-start replay. Als de app door een callkit-accept vanuit
  // killed-state werd opgestart, is het actionCallAccept-event al gefired
  // vóór luisterEvents attached. Zonder deze replay komt de user in de
  // app maar zit hij niet in het gesprek. activeCalls() → geaccepteerde
  // call → notifier met autoAnswer=true → main-flow springt naar het
  // waarschuwingsscherm + GesprekScherm.
  unawaited(BelCallkitService.replayGeaccepteerdeCalls());
  runApp(const OnsMomentApp());
}

class OnsMomentApp extends StatelessWidget {
  const OnsMomentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ons Moment',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kPeach),
        scaffoldBackgroundColor: kCream,
      ),
      home: const RouterScherm(),
    );
  }
}

/// Centrale routing logica:
/// - Niet ingelogd                  -> SetupWizard
/// - Ingelogd + modus onbekend      -> SetupWizard
/// - Ingelogd + modus = familie     -> FamilieScherm
/// - Ingelogd + modus = ontvanger   -> TabletScherm
class RouterScherm extends StatefulWidget {
  const RouterScherm({super.key});
  @override
  State<RouterScherm> createState() => _RouterSchermState();
}

class _RouterSchermState extends State<RouterScherm>
    with WidgetsBindingObserver {
  bool _initieelGeladen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _laadInitieel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Wist lokale notificaties + badge zodra de app naar de voorgrond komt.
  /// Identiek aan WhatsApp-gedrag: badge daalt bij openen, ongeacht of de
  /// berichten al zijn gelezen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      PushService.lokaleMeldingenWissen();
    }
  }

  Future<void> _laadInitieel() async {
    // Wis badge + openstaande lokale notificaties bij cold start.
    PushService.lokaleMeldingenWissen();
    await DeviceModusService.get()
        .timeout(const Duration(seconds: 5), onTimeout: () => null);
    await DeviceModusService.krijgWeergaveModus();
    // Fire-and-forget: update laatstActief als gebruiker al ingelogd is.
    // Faalt silent als apparaat nog niet geregistreerd is (bestaande gebruikers).
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final apparaatId = await DeviceModusService.krijgApparaatId();
      ApparaatService.updateLaatstActief(
          familieUid: user.uid, apparaatId: apparaatId);
      // Fase 1 push-meldingen: registreer FCM-token voor dit apparaat.
      // Fire-and-forget — PushService heeft zelf try/catch en no-op op web.
      // Draait bij elke geslaagde auth-state (verse signIn én cold-start
      // ingelogd), zodat token-registratie op één centraal punt zit i.p.v.
      // vijf verspreide signIn-blokken.
      PushService.registreerHuidigApparaat(
              familieUid: user.uid, apparaatId: apparaatId)
          .catchError((_) {});
      // Eenmalige migratie: bestaande accounts zonder accountType -> 'familie'.
      FirebaseFirestore.instance.collection('gebruikers').doc(user.uid).get()
          .then((d) {
        if (d.exists && d.data()?['accountType'] == null) {
          d.reference.set({'accountType': 'familie'}, SetOptions(merge: true));
        }
      }).catchError((_) {});
    }
    if (!mounted) return;
    setState(() => _initieelGeladen = true);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _LaadScherm();
        }
        if (!_initieelGeladen) return const _LaadScherm();
        return ValueListenableBuilder<String?>(
          valueListenable: DeviceModusService.notifier,
          builder: (context, modus, _) {
            if (!authSnap.hasData || modus == null) return const SetupWizard();
            return _KringWachter(
              familieUid: authSnap.data!.uid,
              child: modus == DeviceModusService.ONTVANGER
                  ? _OntvangerRouter(familieUid: authSnap.data!.uid)
                  : const FamilieScherm(),
            );
          },
        );
      },
    );
  }
}

class _LaadScherm extends StatelessWidget {
  const _LaadScherm();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Image.asset('assets/images/logo.png', height: 100),
          const SizedBox(height: 16),
          const Text('Ons Moment',
              style: TextStyle(fontSize: 24,
                  fontWeight: FontWeight.w900, color: kBrown)),
          const SizedBox(height: 16),
          const CircularProgressIndicator(color: kPeach),
        ]),
      ),
    );
  }
}

/// Bewaakt de ontvanger-tak. Luistert naar eigen apparaat-doc in Firestore
/// zodat de account-maker de weergaveModus op afstand kan wisselen — bij
/// wijziging triggert DeviceModusService.zetWeergaveModus een rebuild via
/// de notifier.
class _OntvangerRouter extends StatefulWidget {
  final String familieUid;
  const _OntvangerRouter({required this.familieUid});
  @override
  State<_OntvangerRouter> createState() => _OntvangerRouterState();
}

class _OntvangerRouterState extends State<_OntvangerRouter> {
  StreamSubscription<DocumentSnapshot>? _sub;
  VoidCallback? _incomingCallListener;
  VoidCallback? _cancelledCallListener;
  bool _inkomendGesprekOpen = false;
  String? _huidigeInkomendCallId;

  @override
  void initState() {
    super.initState();
    // Portrait-lock voor de ontvanger-tak (rustig én normaal). Alleen native:
    // op web negeert SystemChrome de oproep sowieso, maar de kIsWeb-guard
    // maakt de intentie expliciet. Familie-kant loopt via een andere router-
    // tak en wordt hier niet geraakt. dispose() zet 'm weer vrij zodat een
    // modus-wissel naar familie de rotatie teruggeeft.
    if (!kIsWeb) {
      SystemChrome.setPreferredOrientations(
          const [DeviceOrientation.portraitUp]);
    }
    _startListener();
    _startIncomingCallListener();
    _startCancelledCallListener();
  }

  Future<void> _startListener() async {
    final apparaatId = await DeviceModusService.krijgApparaatId();
    if (!mounted) return;
    _sub = FirebaseFirestore.instance
        .collection('gebruikers').doc(widget.familieUid)
        .collection('apparaten').doc(apparaatId)
        .snapshots()
        .listen((doc) {
      final remote = doc.data()?['weergaveModus'] as String?;
      if (remote != DeviceModusService.VERGRENDELD
          && remote != DeviceModusService.MELDINGEN) return;
      if (remote == DeviceModusService.weergaveModusNotifier.value) return;
      DeviceModusService.zetWeergaveModus(remote!);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_incomingCallListener != null) {
      PushService.incomingCallNotifier.removeListener(_incomingCallListener!);
      _incomingCallListener = null;
    }
    if (_cancelledCallListener != null) {
      PushService.cancelledCallIdNotifier
          .removeListener(_cancelledCallListener!);
      _cancelledCallListener = null;
    }
    // Reset naar alle richtingen zodat de familie-kant vrij kan draaien
    // zodra iemand de modus terugzet naar familie.
    if (!kIsWeb) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    super.dispose();
  }

  void _startIncomingCallListener() {
    if (!DEBUG_VIDEOBELLEN) return;
    void cb() {
      _verwerkInkomendGesprek(PushService.incomingCallNotifier.value);
    }
    PushService.incomingCallNotifier.addListener(cb);
    _incomingCallListener = cb;
    if (PushService.incomingCallNotifier.value != null) cb();
  }

  Future<void> _verwerkInkomendGesprek(IncomingCall? call) async {
    if (call == null) return;
    // Consumeer synchroon vóór de scherm-push: voorkomt dat een re-emit
    // tijdens het scherm een tweede exemplaar opent.
    PushService.incomingCallNotifier.value = null;
    if (_inkomendGesprekOpen) return;
    if (!mounted) return;
    _inkomendGesprekOpen = true;
    _huidigeInkomendCallId = call.callId;
    try {
      final navigator = Navigator.of(context);
      // autoAnswer=true via drie paden:
      //   (1) Kiosk/rustige modus — app altijd voorgrond: FCM-foreground
      //       → _publiceerInkomendGesprek → hier → direct GesprekScherm.
      //       100% betrouwbaar, geen Android-beperkingen.
      //   (2) Normale modus, 'Opnemen'-knop in melding getikt:
      //       _verwerkLokaalNotificatieTik(actionId:'accept') zet
      //       autoAnswer=true ongeacht kring-instelling → hier → direct
      //       GesprekScherm. Werkt bij app achtergrond én gesloten.
      //   (3) Normale modus, gesloten app, scherm UIT: fullScreenIntent
      //       kan Android triggeren om de app automatisch te starten.
      //       Als getNotificationAppLaunchDetails() de payload meelevert
      //       (afhankelijk van Android-versie/OEM), vuurt dit pad.
      //       ANDROID-GRENS: bij scherm AAN toont fullScreenIntent als
      //       heads-up; app wordt niet auto-gelauncht — gebruiker tikt
      //       'Opnemen' (pad 2). Nooit een stille/verwarrende toestand:
      //       de melding blijft zichtbaar met actieknoppen tot tik of
      //       45s-timeout.
      if (call.autoAnswer) {
        // BEL-C FIX5: nooit ongewaarschuwd een camera openen bij de
        // dierbare. Toon eerst ~2.5s een dementie-vriendelijk schermpje
        // met marimba + "X belt jou — we nemen zo op…", pop dat weg
        // en dan pas GesprekScherm. Warm en menselijk ipv abrupt.
        //
        // pushReplacement in de onKlaar-callback zorgt dat het waarschuw-
        // scherm netjes uit de stack verdwijnt zodat een terug-swipe uit
        // GesprekScherm niet terugvalt naar dit tussenscherm.
        await navigator.push(MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (dialogCtx) => AutoOpnemenWaarschuwingScherm(
            callerName: call.callerName,
            onKlaar: () {
              Navigator.of(dialogCtx).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => GesprekScherm(
                    remoteNaam: call.callerName,
                    tokenToJoin: call.calleeToken,
                  ),
                ),
              );
            },
          ),
        ));
        return;
      }
      bool beantwoord = false;
      // fullscreenDialog: true zorgt dat de Android back-swipe een
      // slide-down geeft in plaats van slide-right — intuïtiever voor
      // een inkomend-gesprek-scherm. canPop: false in InkomendGesprekScherm
      // zorgt dat alleen de twee knoppen de uitweg zijn.
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
      _huidigeInkomendCallId = null;
      if (!mounted) return;
      if (beantwoord) {
        await navigator.push(MaterialPageRoute<void>(
          builder: (_) => GesprekScherm(
            remoteNaam: call.callerName,
            tokenToJoin: call.calleeToken,
          ),
        ));
      }
    } finally {
      _huidigeInkomendCallId = null;
      _inkomendGesprekOpen = false;
    }
  }

  void _startCancelledCallListener() {
    if (!DEBUG_VIDEOBELLEN) return;
    void cb() {
      final geannuleerdId = PushService.cancelledCallIdNotifier.value;
      if (geannuleerdId == null) return;
      PushService.cancelledCallIdNotifier.value = null;
      if (_huidigeInkomendCallId != geannuleerdId) return;
      if (!mounted) return;
      Navigator.of(context).maybePop();
    }
    PushService.cancelledCallIdNotifier.addListener(cb);
    _cancelledCallListener = cb;
    if (PushService.cancelledCallIdNotifier.value != null) cb();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: DeviceModusService.weergaveModusNotifier,
      builder: (context, weergave, _) {
        if (weergave == DeviceModusService.MELDINGEN) {
          return const FamilieScherm(alsOntvanger: true);
        }
        // 'vergrendeld' of null (backwards compat) → kiosk
        return const TabletScherm();
      },
    );
  }
}

/// Bewaakt het eigen apparaat-doc. Verdwijnt het doc nadat het eerder
/// bestond (verwijderd uit de kring), dan volgt een force-logout. De
/// _zagOoitBestaan-gate voorkomt dat bestaande gebruikers zonder apparaat-
/// registratie onterecht worden uitgelogd.
class _KringWachter extends StatefulWidget {
  final String familieUid;
  final Widget child;
  const _KringWachter({required this.familieUid, required this.child});
  @override
  State<_KringWachter> createState() => _KringWachterState();
}

class _KringWachterState extends State<_KringWachter> {
  StreamSubscription<DocumentSnapshot>? _sub;
  bool _geregistreerd = false;
  bool _uitgelogd = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final apparaatId = await DeviceModusService.krijgApparaatId();
    _geregistreerd = await DeviceModusService.isGeregistreerd();
    if (!mounted) return;
    _debugToast('Wachter start — geregistreerd=$_geregistreerd');
    _sub = FirebaseFirestore.instance
        .collection('gebruikers').doc(widget.familieUid)
        .collection('apparaten').doc(apparaatId)
        .snapshots()
        .listen((doc) {
      if (_uitgelogd) return;
      _debugToast('Snapshot: exists=${doc.exists} '
          'cache=${doc.metadata.isFromCache} reg=$_geregistreerd');
      if (doc.exists) {
        // Persistente markering: dit apparaat hoort bij de kring. Overleeft
        // cold-starts zodat een latere verwijdering altijd uitlogt.
        if (!_geregistreerd) {
          _geregistreerd = true;
          DeviceModusService.markeerGeregistreerd();
        }
      } else if (_geregistreerd && !doc.metadata.isFromCache) {
        // Alleen uitloggen bij een server-bevestigde verdwijning. Firestore
        // stuurt op web vaak eerst een leeg cache-snapshot vóór het server-
        // antwoord — dat is geen echte verwijdering uit de kring.
        _forceLogout();
      }
      // exists==false zonder _geregistreerd = nooit geregistreerd → niets.
    });
  }

  Future<void> _forceLogout() async {
    _uitgelogd = true;
    _debugToast('Force-logout: apparaat verwijderd');
    await _sub?.cancel();
    await DeviceModusService.wis();
    await FirebaseAuth.instance.signOut();
    scaffoldMessengerKey.currentState?.showSnackBar(const SnackBar(
      content: Text('Je apparaat is verwijderd uit de kring'),
      backgroundColor: Colors.orange,
      duration: Duration(seconds: 5),
    ));
  }

  void _debugToast(String msg) {
    if (!DEBUG_FORCE_LOGOUT) return;
    scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
      content: Text('🔐 $msg', style: const TextStyle(fontSize: 11)),
      backgroundColor: Colors.black.withOpacity(0.75),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
