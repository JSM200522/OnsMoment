import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/setup/setup_wizard.dart';
import 'screens/familie/familie_scherm.dart';
import 'screens/tablet/tablet_scherm.dart';
import 'services/device_modus_service.dart';

const Color kPeach     = Color(0xFFFF9B71);
const Color kPeachPale = Color(0xFFFFF0EA);
const Color kCream     = Color(0xFFFFFAF7);
const Color kBrown     = Color(0xFF5C3D2E);

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
  String? _modus;
  bool _modusGeladen = false;

  @override
  void initState() {
    super.initState();
    _laadModus();
  }

  Future<void> _laadModus() async {
    final m = await DeviceModusService.get();
    if (!mounted) return;
    setState(() {
      _modus = m;
      _modusGeladen = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _LaadScherm();
        }
        if (!authSnap.hasData) return const SetupWizard();
        if (!_modusGeladen) return const _LaadScherm();
        if (_modus == null) return const SetupWizard();
        if (_modus == DeviceModusService.ONTVANGER) {
          return const TabletScherm();
        }
        return const FamilieScherm();
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
