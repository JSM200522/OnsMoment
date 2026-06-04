import 'dart:math' show Random;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'kring_service.dart';

/// Beheert de "modus" van dit specifieke apparaat:
/// - 'familie' = familie portaal (Sturen, Agenda, Notities, Instellingen)
/// - 'ontvanger' = ontvanger kiosk (alleen popups en home)
/// - null = nog niet ingesteld (toon keuzescherm)
///
/// Op web werkt dit via localStorage. Op mobiel via SharedPreferences.
/// Per apparaat opgeslagen — dezelfde Firebase Auth account kan op het ene
/// apparaat als familie ingelogd zijn en op het andere als ontvanger.
class DeviceModusService {
  static const String _key = 'ons_moment_device_modus';
  static const String _weergaveKey = 'ons_moment_weergave_modus';
  static const String _apparaatIdKey = 'ons_moment_apparaat_id';
  static const String _geregistreerdKey = 'ons_moment_geregistreerd';
  static const String _actieveKringKey = 'ons_moment_actieve_kring_id';
  static const String _gecachteOntvangerNaamKey =
      'ons_moment_gecachte_ontvanger_naam';
  static const String FAMILIE = 'familie';
  static const String ONTVANGER = 'ontvanger';
  static const String VERGRENDELD = 'vergrendeld';
  static const String MELDINGEN = 'meldingen';

  /// Reactief gepubliceerde modus — wordt door [get], [zet] en [wis]
  /// up-to-date gehouden zodat de UI zonder polling kan reageren.
  static final ValueNotifier<String?> notifier = ValueNotifier<String?>(null);

  /// Reactief gepubliceerde weergaveModus voor ontvanger-apparaten
  /// ('vergrendeld' of 'meldingen'). Null als niet ingesteld.
  static final ValueNotifier<String?> weergaveModusNotifier =
      ValueNotifier<String?>(null);

  /// Reactief gepubliceerde actieveKringId. Wijzigt bij zetActieveKring
  /// en wisActieveKring. Familie-scherm en NotitiesTab luisteren hierop
  /// (V9 2.2b) om listeners te herstarten bij kring-switch.
  static final ValueNotifier<String?> actieveKringNotifier =
      ValueNotifier<String?>(null);

  /// Lees huidige modus uit storage en publiceer naar [notifier]. Null als nog niet ingesteld.
  static Future<String?> get() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final waarde = prefs.getString(_key);
      final resultaat = (waarde == FAMILIE || waarde == ONTVANGER) ? waarde : null;
      notifier.value = resultaat;
      return resultaat;
    } catch (_) {
      return null;
    }
  }

  /// Zet de modus voor dit apparaat. Geeft true als geslaagd.
  static Future<bool> zet(String modus) async {
    if (modus != FAMILIE && modus != ONTVANGER) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ok = await prefs.setString(_key, modus);
      if (ok) notifier.value = modus;
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Wis de modus (bij uitloggen of bewust wisselen).
  static Future<void> wis() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
      await prefs.remove(_weergaveKey);
      await prefs.remove(_actieveKringKey);
      notifier.value = null;
      weergaveModusNotifier.value = null;
    } catch (_) {}
  }

  /// Gememoïseerd resultaat van [krijgApparaatId]. Zorgt dat ALLE aanroepers
  /// binnen één app-sessie exact hetzelfde id krijgen. Voorkomt de race waarbij
  /// gelijktijdige aanroepers elk een ander id genereren en het apparaat zich
  /// onder een ander id registreert dan het opgeslagen id — de oorzaak van
  /// onterechte force-logout én dubbele kringleden.
  static Future<String>? _apparaatIdFuture;

  /// Geeft een stabiele apparaat-id terug. Genereert er één bij eerste oproep
  /// en bewaart in SharedPreferences zodat dit apparaat persistent herkenbaar is.
  static Future<String> krijgApparaatId() =>
      _apparaatIdFuture ??= _laadOfMaakApparaatId();

  static Future<String> _laadOfMaakApparaatId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Lees eerst het opgeslagen id; alleen genereren als er echt geen is.
      final bestaand = prefs.getString(_apparaatIdKey);
      if (bestaand != null && bestaand.isNotEmpty) {
        debugPrint('📱 apparaatId geladen uit prefs: $bestaand');
        return bestaand;
      }
      final nieuw = '${DateTime.now().millisecondsSinceEpoch}_'
          '${Random().nextInt(0xFFFFFFFF).toRadixString(16)}';
      await prefs.setString(_apparaatIdKey, nieuw);
      debugPrint('📱 apparaatId nieuw aangemaakt + opgeslagen: $nieuw');
      return nieuw;
    } catch (e) {
      // Prefs niet beschikbaar: niet-persistent id, maar wél gememoïseerd
      // zodat het binnen deze sessie stabiel blijft (één keer gegenereerd).
      final fallback = 'tmp_${DateTime.now().millisecondsSinceEpoch}';
      debugPrint('⚠️ apparaatId fallback (prefs faalde: $e) → $fallback');
      return fallback;
    }
  }

  /// Lees weergaveModus uit storage en publiceer naar [weergaveModusNotifier].
  static Future<String?> krijgWeergaveModus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final waarde = prefs.getString(_weergaveKey);
      final resultaat = (waarde == VERGRENDELD || waarde == MELDINGEN) ? waarde : null;
      weergaveModusNotifier.value = resultaat;
      return resultaat;
    } catch (_) {
      return null;
    }
  }

  /// Zet weergaveModus voor dit apparaat. Faalt silent.
  static Future<void> zetWeergaveModus(String modus) async {
    if (modus != VERGRENDELD && modus != MELDINGEN) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ok = await prefs.setString(_weergaveKey, modus);
      if (ok) weergaveModusNotifier.value = modus;
    } catch (_) {}
  }

  /// Persistente markering dat dit apparaat ooit in de kring geregistreerd
  /// was. Overleeft cold-starts zodat force-logout ook na herstart werkt.
  static Future<void> markeerGeregistreerd() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_geregistreerdKey, true);
    } catch (_) {}
  }

  static Future<bool> isGeregistreerd() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_geregistreerdKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// De kring waar dit apparaat momenteel actief mee verbonden is (V9).
  /// Wordt gezet bij signup; multi-kring switching komt later. Null = geen
  /// actieve kring (bv. vlak na uitloggen of bij accounts van vóór V9).
  static Future<String?> krijgActieveKring() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_actieveKringKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> zetActieveKring(String kringId) async {
    if (kringId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_actieveKringKey, kringId);
      actieveKringNotifier.value = kringId;
    } catch (_) {}
  }

  /// Zoekt in Firestore de eerste kring waarvan deze uid eigenaar is en
  /// slaat de doc-id op als actieveKringId. Stil bij geen kring of fout.
  /// Aangeroepen direct na signIn-blokken zodat reads die op kringId
  /// filteren (V9 1.1d+) werken voor bestaande eigenaars.
  static Future<void> zetActieveKringVoorEigenaar(String uid) async {
    if (uid.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('kringen')
          .where('eigenaarUid', isEqualTo: uid)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return;
      await zetActieveKring(snap.docs.first.id);
    } catch (_) {}
  }

  /// Resolveer kringId voor services die Storage/Firestore-paden bouwen.
  /// Keten (V9 2.1c):
  /// 1. cache (SharedPreferences) — snel pad
  /// 2. live lookup op kringen.eigenaarUid==uid (eigenaar-pad)
  /// 3. eerste membership uit KringService.mijnKringen (gast-pad voor
  ///    uitgenodigde leden zonder eigen kring)
  /// 4. ultieme fallback: auth.uid (V7/V8-accounts zonder kring-doc)
  ///
  /// Null als niemand is ingelogd. Eigenaars volgen pad 1 of 2 — voor hen
  /// verandert er niets t.o.v. 1.1h-fix. Stap 3 is nieuw en maakt gasten
  /// (membership zonder eigen kring) ondersteund.
  static Future<String?> huidigeKringIdMetFallback() async {
    final cached = await krijgActieveKring();
    if (cached != null && cached.isNotEmpty) return cached;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('kringen')
          .where('eigenaarUid', isEqualTo: uid)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final kringId = snap.docs.first.id;
        await zetActieveKring(kringId);
        return kringId;
      }
    } catch (_) {}
    // Geen eigen kring gevonden — probeer membership in een andere kring
    // (gast-pad). Eerste resultaat uit mijnKringen wordt gecached.
    final kringen = await KringService.mijnKringen(uid);
    if (kringen.isNotEmpty) {
      final kringId = kringen.first.id;
      await zetActieveKring(kringId);
      return kringId;
    }
    return uid;
  }

  static Future<void> wisActieveKring() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_actieveKringKey);
      actieveKringNotifier.value = null;
    } catch (_) {}
  }

  /// V9 2.9-perf-2: cache van ontvangerNaam zodat TabletScherm (en in
  /// de toekomst FamilieScherm-alsOntvanger) de 'Hallo X'-banner
  /// direct kan tonen zonder op de gebruikers/{uid} snapshot of de
  /// actieveKringStream te wachten. Wordt geschreven door
  /// _voltooiOntvanger; bestaande Firestore-streams overschrijven 'm
  /// zodra live data binnen is. Alleen-presentatie: geen gedrags-
  /// wijziging, geen autoritatieve bron.
  static Future<void> zetGecachteOntvangerNaam(String naam) async {
    final trimmed = naam.trim();
    if (trimmed.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_gecachteOntvangerNaamKey, trimmed);
    } catch (_) {}
  }

  static Future<String?> krijgGecachteOntvangerNaam() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_gecachteOntvangerNaamKey);
    } catch (_) {
      return null;
    }
  }
}
