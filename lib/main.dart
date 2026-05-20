import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'screens/setup/setup_wizard.dart';
import 'screens/familie/familie_scherm.dart';
import 'screens/tablet/tablet_scherm.dart';
import 'services/apparaat_service.dart';
import 'services/device_modus_service.dart';
import 'theme/kleuren.dart';

/// App-niveau messenger zodat een toast (bv. force-logout) zichtbaar blijft
/// terwijl de widget-tree naar het login-scherm rebuildt.
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
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

class _RouterSchermState extends State<RouterScherm> {
  bool _initieelGeladen = false;

  @override
  void initState() {
    super.initState();
    _laadInitieel();
  }

  Future<void> _laadInitieel() async {
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
    return const Scaffold(
      backgroundColor: kCream,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('💕', style: TextStyle(fontSize: 48)),
          SizedBox(height: 16),
          Text('Ons Moment',
              style: TextStyle(fontSize: 24,
                  fontWeight: FontWeight.w900, color: kBrown)),
          SizedBox(height: 16),
          CircularProgressIndicator(color: kPeach),
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

  @override
  void initState() {
    super.initState();
    _startListener();
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
    super.dispose();
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
  bool _zagOoitBestaan = false;
  bool _uitgelogd = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final apparaatId = await DeviceModusService.krijgApparaatId();
    if (!mounted) return;
    _sub = FirebaseFirestore.instance
        .collection('gebruikers').doc(widget.familieUid)
        .collection('apparaten').doc(apparaatId)
        .snapshots()
        .listen((doc) {
      if (_uitgelogd) return;
      if (doc.exists) {
        _zagOoitBestaan = true;
      } else if (_zagOoitBestaan) {
        _forceLogout();
      }
      // exists==false zonder _zagOoitBestaan = nooit geregistreerd → niets.
    });
  }

  Future<void> _forceLogout() async {
    _uitgelogd = true;
    await _sub?.cancel();
    await DeviceModusService.wis();
    await FirebaseAuth.instance.signOut();
    scaffoldMessengerKey.currentState?.showSnackBar(const SnackBar(
      content: Text('Je apparaat is verwijderd uit de kring'),
      backgroundColor: Colors.orange,
      duration: Duration(seconds: 5),
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
