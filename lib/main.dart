import 'dart:async';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'screens/setup/setup_wizard.dart';
import 'screens/familie/familie_scherm.dart';
import 'screens/tablet/tablet_scherm.dart';
import 'screens/tablet/inkomend_gesprek_scherm.dart';
import 'screens/verificatie_afdwingen_scherm.dart';
import 'screens/videobellen/auto_opnemen_waarschuwing_scherm.dart';
import 'screens/videobellen/gesprek_scherm.dart';
import 'dart:convert';
import 'services/apparaat_service.dart';
import 'services/bel_callkit_service.dart';
import 'services/bel_log_service.dart';
import 'services/callkit_flag_service.dart';
import 'services/device_modus_service.dart';
import 'services/crash_service.dart';
import 'services/kiosk_service.dart';
import 'services/push_service.dart';
import 'services/verificatie_gate_service.dart';
import 'services/purchases_service.dart';
import 'services/video_call_service.dart';
import 'data/debug_flags.dart';
import 'theme/kleuren.dart';

/// FASE D-1: RevenueCat public app-specific API-keys.
///
/// Joshua haalt deze uit RevenueCat → Project settings → API keys →
/// "Public app-specific" (per platform één). VERVANG de lege strings
/// hieronder door de echte waarden zodra beschikbaar. Zolang de
/// betreffende platform-key leeg is, wordt Purchases.configure
/// overgeslagen (fail-soft) en blijft de app volledig werken.
///
/// Public keys zijn bedoeld om in de client te staan — géén secret.
/// RevenueCat's server-side webhook-secret (bij de webhook Cloud
/// Function) is wél geheim en hoort NIET in deze file.
const String kRevenueCatAndroidKey = 'goog_DJUPMPuJUItUVeMBCvLTDLAfUhB';
const String kRevenueCatIosKey = '';

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
  // FASE D-1 (12 sept 2026): RevenueCat init TERUG na Flutter-upgrade.
  // purchases_flutter 9.x brengt Billing Library 8 mee + de
  // com.android.vending.BILLING-permissie in de merged manifest,
  // waardoor Play Console het aanmaken van abonnementen weer toestaat.
  // Fail-soft: bij lege key of Purchases-fout blijft de app volledig
  // functioneel; alleen de RevenueCat-SDK is dan slapend.
  unawaited(_initRevenueCat());
  runApp(const OnsMomentApp());
}

/// FASE D-1 SDK-init voor RevenueCat. Fail-soft op elk pad:
///  - web:               skip (SDK werkt niet in de browser).
///  - lege API-key:      skip met een leesbare debug-melding.
///  - Purchases-fout:    vangen, loggen, doorlopen.
///
/// Op elk platform wordt de bijbehorende public key gebruikt zodat de
/// iOS-branche (FASE G) hier straks vanzelf mee opstart zonder verdere
/// wijziging. Onbekende platforms (bv. desktop) worden overgeslagen.
Future<void> _initRevenueCat() async {
  if (kIsWeb) return;
  final String key;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      key = kRevenueCatAndroidKey;
      break;
    case TargetPlatform.iOS:
      key = kRevenueCatIosKey;
      break;
    default:
      return;
  }
  if (key.isEmpty) {
    debugPrint('💳 RevenueCat: geen API-key ingesteld voor '
        '$defaultTargetPlatform — configure overgeslagen (fail-soft)');
    return;
  }
  try {
    await Purchases.configure(PurchasesConfiguration(key));
    // D-2: PurchasesService.beschikbaar returnt nu true; alle wrapper-
    // calls (init, koop, restore, listener) worden vanaf hier live.
    PurchasesService.markConfigureVoltooid();
    debugPrint('💳 RevenueCat: SDK geïnitialiseerd voor '
        '$defaultTargetPlatform');
    // D-2D-FIX (sept 2026): cold-start timing-race repareren.
    // _initRevenueCat is `unawaited` in main() zodat runApp niet
    // wacht op de SDK. Op cold-start met een al-ingelogde user firet
    // _RouterSchermState._bijAuthWissel echter mogelijk VÓÓR configure
    // klaar is → PurchasesService.init doet dan no-op (beschikbaar
    // was nog false) én zet _laatstGeregistreerdeUid, wat volgende
    // auth-ticks met dezelfde uid blokkeert. Netto: Purchases.logIn
    // firet vrijwel nooit bij cold-start en users komen niet in het
    // RevenueCat-dashboard → aankopen koppelen niet aan de juiste
    // Firebase-uid. Fix: als er hier al een user is, roep init
    // expliciet aan. Idempotent via PurchasesService._initGedaan-
    // guard; fail-soft via de try/catch in init zelf.
    final huidigeUser = FirebaseAuth.instance.currentUser;
    if (huidigeUser != null && huidigeUser.uid.isNotEmpty) {
      unawaited(PurchasesService.init(huidigeUser.uid));
      debugPrint('💳 cold-start logIn-retry voor ${huidigeUser.uid}');
    }
  } catch (e, st) {
    debugPrint('⚠️ RevenueCat init faalde (fail-soft, app blijft '
        'werken): $e\n$st');
  }
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

  /// AUTH-1 (12 sept 2026): re-registreer PushService bij elke sign-in
  /// (cold-start én re-login binnen dezelfde app-sessie). Zonder deze
  /// listener behoudt het apparaat-doc de fcmToken van de vorige sessie —
  /// bij een uitlog+opnieuw-inloggen op de ontvanger-tablet was dat een
  /// stille bel-blocker: startVideoCall vond een geldig doel-apparaat
  /// maar FCM.send() faalde op de stale token → 'unavailable / Kon
  /// doel-apparaat niet bereiken'. _laadInitieel doet dit ook maar
  /// alleen bij cold-start (initState draait één keer).
  StreamSubscription<User?>? _authSub;
  String? _laatstGeregistreerdeUid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _laadInitieel();
    _authSub =
        FirebaseAuth.instance.authStateChanges().listen(_bijAuthWissel);
    // D-2D: entitlement-listener attach. Firet zodra RevenueCat een
    // customer-info-update ontvangt (nieuwe aankoop, restore, verlopen).
    // No-op zolang PurchasesService.beschikbaar false is (lege API-key
    // of web) — dan wordt de listener bewust niet geregistreerd.
    PurchasesService.luisterEntitlementChanges(_opEntitlementUpdate);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    PurchasesService.stopLuisteren();
    super.dispose();
  }

  /// D-2D callback: RevenueCat heeft een nieuwe customer-info gestuurd
  /// (aankoop, restore, verlopen, cross-device sync). Server-side heeft
  /// de `revenuecatWebhook` Cloud Function al `gebruikers/{uid}.tier`
  /// bijgewerkt; deze callback forceert alleen een client-refresh zodat
  /// UI-schermen die niet actief op gebruikers/{uid} streamen (bijv.
  /// PakketKeuzeScherm) direct de nieuwe status zien.
  ///
  /// Fail-soft: elke fout wordt gelogd; nooit crash. De client heeft
  /// geen schrijf-verantwoordelijkheid — de webhook is de bron van
  /// waarheid voor tier/abonnement.
  void _opEntitlementUpdate(CustomerInfo info) {
    final tier = PurchasesService.tierUitCustomerInfo(info);
    debugPrint('💳 entitlement-update ontvangen: tier=$tier '
        '(actief: ${info.entitlements.active.keys.toList()})');
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    // Force-refresh van het gebruikers-doc zodat een cached read direct
    // de nieuwe tier oppikt. Niet strikt nodig als de UI al streamt,
    // maar dekt ook de "PakketKeuzeScherm net geopend"-flow.
    FirebaseFirestore.instance
        .collection('gebruikers').doc(uid)
        .get(const GetOptions(source: Source.server))
        .catchError((Object e) {
      debugPrint('💳 refresh gebruikers-doc na entitlement-update '
          'faalde (fail-soft): $e');
      // Return-type dwang — we mogen niet null returnen, dus geef
      // een lege snapshot terug. Caller gebruikt hem niet.
      return FirebaseFirestore.instance.collection('gebruikers')
          .doc(uid).get();
    });
  }

  /// Idempotent: negeer als het dezelfde uid is als de vorige registratie
  /// (voorkomt dubbele call bij cold-start waar _laadInitieel het al deed).
  /// Bij een NIEUWE uid (re-login, account-switch) → verse fcmToken +
  /// laatstActief + kringId-backfill via PushService.registreerHuidigApparaat.
  ///
  /// A-8 (12 sept 2026): eerst actieve kring wissen + zetten voor de
  /// nieuwe uid. Zonder deze stap bevatte `actieveKringNotifier` nog de
  /// kringId van gebruiker A tijdens de push-registratie van gebruiker B
  /// → `_bepaalKringIdVoorApparaat` faalde de contains-check → schreef
  /// `kringId: null` op B's apparaat-doc → `onNieuwMoment` skipt het
  /// apparaat → eerste push naar B werkt niet.
  Future<void> _bijAuthWissel(User? user) async {
    if (user == null) {
      _laatstGeregistreerdeUid = null;
      // B-1 (12 sept 2026): idToken uit prefs wissen bij signOut zodat
      // het achtergrond-isolate niet meer met een 1u geldige bearer-
      // token kan pingen namens de uitgelogde gebruiker. Fail-soft.
      unawaited(PushService.wisAchtergrondIdToken());
      // D-2D: RevenueCat-user ook resetten — voorkomt dat een volgende
      // inlog met een andere uid de entitlements van de vorige user
      // erft. No-op als SDK niet configured.
      unawaited(PurchasesService.logout());
      return;
    }
    if (user.uid == _laatstGeregistreerdeUid) return;
    _laatstGeregistreerdeUid = user.uid;
    try {
      // A-8: eerst kring-context resetten en de eigenaars-kring van de
      // NIEUWE uid pakken vóór PushService leest via
      // _bepaalKringIdVoorApparaat. Bij een gast (geen eigen kring)
      // valt zetActieveKringVoorEigenaar stil terug en pakt
      // PushService de kringId via collectionGroup mijnKringIds — met
      // een mogelijk index-race (B-7, apart traject).
      await DeviceModusService.wisActieveKring();
      await DeviceModusService.zetActieveKringVoorEigenaar(user.uid);
      final apparaatId = await DeviceModusService.krijgApparaatId();
      unawaited(ApparaatService.updateLaatstActief(
          familieUid: user.uid, apparaatId: apparaatId));
      unawaited(PushService.registreerHuidigApparaat(
          familieUid: user.uid, apparaatId: apparaatId));
      // D-2D: RevenueCat aan Firebase-uid koppelen. Dit is de sleutel
      // waar de webhook Cloud Function op gebruikers/{uid} schrijft
      // (via event.app_user_id in de RevenueCat-payload). No-op als
      // SDK niet configured.
      unawaited(PurchasesService.init(user.uid));
    } catch (e) {
      unawaited(BelLogService.log(
          'AUTH-1 push re-register faalde bij auth-wissel: $e'));
    }
  }

  /// Wist lokale notificaties + badge zodra de app naar de voorgrond komt.
  /// Identiek aan WhatsApp-gedrag: badge daalt bij openen, ongeacht of de
  /// berichten al zijn gelezen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      PushService.lokaleMeldingenWissen();
      // BEL-D1: warm-launch pad. Als OnsMomentFcmReceiver de activity
      // start terwijl de app al in het geheugen zit, komt de payload
      // via onNewIntent binnen. Bij resume ook checken zodat een
      // auto-answer bij warm-start dezelfde flow neemt als cold-start.
      unawaited(_verwerkPendingAutoAnswer());
    }
  }

  /// BEL-D1: leest de pending auto-answer payload van MainActivity
  /// (gecached door OnsMomentFcmReceiver via startActivity) en publiceert
  /// hem op [PushService.incomingCallNotifier]. `_OntvangerRouter` en
  /// `FamilieScherm` (voor alsOntvanger-modus) luisteren daarop en
  /// starten de bestaande auto-answer-flow: 2.5s waarschuwingsscherm →
  /// GesprekScherm.
  ///
  /// Fail-soft: elke fout wordt gelogd maar mag de router-init niet
  /// blokkeren. Web + niet-Android: KioskService.haalPendingAutoAnswer
  /// returnt null → deze method is dan een no-op.
  Future<void> _verwerkPendingAutoAnswer() async {
    try {
      final pending = await KioskService.haalPendingAutoAnswer();
      if (pending == null) return;
      final payload = pending['payload'] ?? '';
      if (payload.isEmpty) return;
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return;
      final asMap = Map<String, dynamic>.from(decoded);
      final call = IncomingCall.uitFcmData(asMap);
      if (call == null) {
        unawaited(BelLogService.log(
            'pending auto-answer payload incompleet: $asMap'));
        return;
      }
      unawaited(BelLogService.log(
          'pending auto-answer opgehaald (callId=${call.callId}) — '
          'publiceer naar incomingCallNotifier'));
      // Server-side autoAnswer-vlag ligt al in de payload; geen forceer
      // hier — _verwerkInkomendGesprek springt op basis daarvan naar het
      // waarschuwingsscherm.
      PushService.incomingCallNotifier.value = call;
    } catch (e, st) {
      unawaited(BelLogService.log(
          'pending auto-answer lookup faalde: $e\n$st'));
    }
  }

  Future<void> _laadInitieel() async {
    // Wis badge + openstaande lokale notificaties bij cold start.
    PushService.lokaleMeldingenWissen();
    // BEL-D1: check op pending auto-answer payload uit OnsMomentFcmReceiver
    // (BAL-exempted startActivity bij scherm-AAN + app dicht). Als er een
    // pending payload is → publiceer op incomingCallNotifier zodat
    // _OntvangerRouter/_FamilieScherm de auto-answer-waarschuwing +
    // GesprekScherm-flow starten. Fire-and-forget: fout mag de rest van
    // de router-init niet blokkeren. No-op op web + niet-Android.
    unawaited(_verwerkPendingAutoAnswer());
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
            // VER-1: e-mailverificatie-gate ALLEEN op de familie-tak.
            // Ontvanger/tablet-modus wordt NOOIT geblokkeerd — de
            // dierbare mag niet gestraft worden voor een mailtje dat
            // de mantelzorger nog moet openen. Met flag UIT retourneert
            // de service altijd false → geen gedragswijziging.
            final familieKind = modus == DeviceModusService.ONTVANGER
                ? _OntvangerRouter(familieUid: authSnap.data!.uid)
                : const _FamilieMetVerificatieGate();
            return _KringWachter(
              familieUid: authSnap.data!.uid,
              child: familieKind,
            );
          },
        );
      },
    );
  }
}

/// VER-1: dunne wrapper die op cold-start én na login checkt of de
/// familie-gebruiker verplicht zijn e-mailadres moet verifiëren.
/// Met de flag `emailVerificatieAfdwingen=false` (default in
/// config/features) retourneert de service altijd `false` → deze
/// wrapper toont onmiddellijk `FamilieScherm` en er verandert
/// helemaal niets aan het bestaande gedrag.
///
/// Bij een async fout of tijdens laden fallen we terug op
/// `FamilieScherm` (fail-soft) — nooit iemand ten onrechte
/// buitensluiten.
class _FamilieMetVerificatieGate extends StatefulWidget {
  const _FamilieMetVerificatieGate();

  @override
  State<_FamilieMetVerificatieGate> createState() =>
      _FamilieMetVerificatieGateState();
}

class _FamilieMetVerificatieGateState
    extends State<_FamilieMetVerificatieGate> {
  bool _bezigCheck = true;
  bool _gate = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final gate = await VerificatieGateService.moetVerifieren();
    if (!mounted) return;
    setState(() {
      _gate = gate;
      _bezigCheck = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_bezigCheck) return const _LaadScherm();
    if (!_gate) return const FamilieScherm();
    return VerificatieAfdwingenScherm(
      onGeverifieerd: () {
        if (!mounted) return;
        setState(() {
          _gate = false;
        });
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
    if (!VIDEOBELLEN_INGESCHAKELD) return;
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
      // BEL-P2: handmatig geaccepteerd (callkit-accept, notif-'Opnemen',
      // cold-start replay) → DIRECT GesprekScherm. Geen tussenscherm en
      // geen waarschuwingsscherm — de callee heeft al bewust getikt en
      // heeft die tussenstap niet nodig. Auto-answer-scherm is voor
      // onaangekondigde server-side auto-open (de kwetsbare dierbare die
      // niet actief tikt).
      if (call.handmatigGeaccepteerd) {
        await navigator.push(MaterialPageRoute<void>(
          builder: (_) => GesprekScherm(
            remoteNaam: call.callerName,
            tokenToJoin: call.calleeToken,
          ),
        ));
        return;
      }
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
            // BEL-S9: cancelVideoCall vanuit main-isolate (echte auth
            // aanwezig) zodat de beller-app een gesprek_geannuleerd-FCM
            // krijgt en direct stopt met rinkelen — anders wachtte hij
            // op zijn 45s-timeout. Fire-and-forget: fout mag de sluit-
            // UX niet blokkeren. Bewust hier i.p.v. in InkomendGesprek-
            // Scherm zodat de weiger-flow ook geldt voor het pad
            // "melding-body-tap → dit scherm → Niet nu".
            final bellerId = call.bellerApparaatId;
            if (bellerId != null && bellerId.isNotEmpty) {
              unawaited(BelLogService.log(
                  'onAfgewezen: cancelCall naar beller '
                  '(callId=${call.callId})'));
              unawaited(
                VideoCallService.cancelCall(
                  kringId: call.kringId,
                  callId: call.callId,
                  doelApparaatId: bellerId,
                ).then((ok) {
                  unawaited(BelLogService.log(
                      'onAfgewezen cancelCall result=$ok'));
                }).catchError((Object e) {
                  unawaited(BelLogService.log(
                      'onAfgewezen cancelCall FAALDE: $e'));
                }),
              );
            } else {
              unawaited(BelLogService.log(
                  'onAfgewezen: geen bellerApparaatId in call — '
                  'skip cancel (beller valt op 45s-timeout)'));
            }
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
    if (!VIDEOBELLEN_INGESCHAKELD) return;
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
          // BEL-C2: FSI-prompt liep vroeger óók vanaf deze router; dat
          // verdubbelde met _checkBelPromptsMeldingenModus in
          // FamilieScherm (dat de warme dialog + 7-dagen-dismiss al doet).
          // Eén plek is genoeg — familie_scherm is de plek waar de
          // ontvanger-modus zichtbaar is, dus daar horen de toestemmingen.
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
