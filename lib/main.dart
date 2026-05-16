import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/setup/setup_wizard.dart';
import 'screens/familie/familie_scherm.dart';
import 'screens/tablet/tablet_scherm.dart';
import 'services/apparaat_service.dart';
import 'services/device_modus_service.dart';
import 'theme/kleuren.dart';

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
            if (modus == DeviceModusService.ONTVANGER) {
              return const TabletScherm();
            }
            return const FamilieScherm();
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
