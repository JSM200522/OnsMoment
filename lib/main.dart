import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/tablet/tablet_scherm.dart';
import 'screens/familie/familie_scherm.dart';
import 'screens/setup/setup_wizard.dart';
import 'services/auth_service.dart';

// ─── KLEUREN ─────────────────────────────────────────────────
const Color kPeach      = Color(0xFFFF9B71);
const Color kPeachLight = Color(0xFFFFD4C2);
const Color kPeachPale  = Color(0xFFFFF0EA);
const Color kRose       = Color(0xFFFF7B9C);
const Color kCream      = Color(0xFFFFFAF7);
const Color kBrown      = Color(0xFF5C3D2E);
const Color kBrownLight = Color(0xFF8B6354);
const Color kTextMuted  = Color(0xFF9B7565);
const Color kWhite      = Color(0xFFFFFFFF);
const Color kGreen      = Color(0xFF4CAF82);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const OnsMonentApp());
}

class OnsMonentApp extends StatelessWidget {
  const OnsMonentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ons Moment',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Nunito',
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kPeach),
        scaffoldBackgroundColor: kPeachPale,
      ),
      home: const RouterScherm(),
    );
  }
}

// ─── ROUTER ──────────────────────────────────────────────────
// Bepaalt automatisch welk portaal de gebruiker ziet:
// Niet ingelogd → Setup
// Rol = 'tablet' → TabletScherm (kiosk, Jan)
// Rol = 'familie' → FamilieScherm (Sara)
class RouterScherm extends StatelessWidget {
  const RouterScherm({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LaadScherm();
        }
        if (!snapshot.hasData) {
          return const SetupWizard();
        }
        return FutureBuilder<String>(
          future: AuthService().getUserRol(snapshot.data!.uid),
          builder: (context, rolSnapshot) {
            if (!rolSnapshot.hasData) return const _LaadScherm();
            if (rolSnapshot.data == 'tablet') {
              // Kiosk modus — Jan kan NIETS aanpassen
              SystemChrome.setEnabledSystemUIMode(
                  SystemUiMode.immersiveSticky);
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
      backgroundColor: kPeachPale,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('💕', style: TextStyle(fontSize: 48)),
          SizedBox(height: 16),
          Text('Ons Moment',
              style: TextStyle(fontSize: 24,
                  fontWeight: FontWeight.w900, color: kBrown)),
        ]),
      ),
    );
  }
}
