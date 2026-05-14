import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  // Haal rol op van gebruiker ('tablet' of 'familie')
  Future<String> getUserRol(String uid) async {
    final doc = await _db.collection('gebruikers').doc(uid).get();
    return doc.data()?['rol'] ?? 'familie';
  }

  // Tablet inloggen met speciale code (geen email nodig voor Jan)
  Future<UserCredential?> tabletInloggen(String tabletCode) async {
    try {
      // Tablet gebruikt een vaste email+code combinatie
      final email = '$tabletCode@tablet.onsmoment.nl';
      return await _auth.signInWithEmailAndPassword(
          email: email, password: tabletCode);
    } catch (e) {
      return null;
    }
  }

  // Familie inloggen met email
  Future<UserCredential?> familieInloggen(String email, String wachtwoord) async {
    try {
      return await _auth.signInWithEmailAndPassword(
          email: email, password: wachtwoord);
    } catch (e) {
      return null;
    }
  }

  // Familie registreren
  Future<UserCredential?> familieRegistreren(
      String email, String wachtwoord, String naam) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
          email: email, password: wachtwoord);
      // Sla profiel op in Firestore
      await _db.collection('gebruikers').doc(cred.user!.uid).set({
        'naam': naam, 'rol': 'familie', 'email': email,
        'aangemeldOp': FieldValue.serverTimestamp(),
      });
      return cred;
    } catch (e) {
      return null;
    }
  }

  Future<void> uitloggen() => _auth.signOut();
  User? get huidigGebruiker => _auth.currentUser;
}
