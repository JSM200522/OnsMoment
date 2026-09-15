import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';
import '../main.dart' show kRevenueCatAndroidKey, kRevenueCatIosKey;

/// FASE D-2 (sept 2026) — RevenueCat wrapper.
///
/// Encapsuleert alle `Purchases.*`-calls achter één service met:
///  - **Fail-soft op elk pad**: web-guard + platform-guard + lege-API-key
///    guard + try/catch rond elke SDK-call. Bij storing valt de app terug
///    op "geen betaalfunctionaliteit"; nooit crash of stuck-UI.
///  - **Idempotente init**: `_initGedaan`-guard voorkomt dubbele
///    `Purchases.logIn`-calls bij re-login binnen dezelfde app-sessie.
///  - **Testbaar door constructie**: alle publieke methods returnen
///    types die je zonder SDK-mock kunt inspecteren (bool / Offerings? /
///    CustomerInfo?). Foutcondities → `null`, geen throws.
///
/// Server-side tier/abonnement-schrijf gebeurt via de
/// `revenuecatWebhook` Cloud Function (D-2). De client leest tier
/// terug uit `gebruikers/{uid}.tier` — hij schrijft NIETS aan dat veld
/// (Firestore-rule blokkeert dat sinds D-1).
///
/// Entitlements: **`klein`** en **`groot`** (letterlijk, lowercase —
/// gespiegeld met `revenuecat_webhook.ts` regel 82-88).
class PurchasesService {
  /// True zodra `Purchases.configure()` in main.dart is uitgevoerd (of
  /// bewust overgeslagen door lege key / kIsWeb / onbekend platform).
  /// Wordt gezet door [markConfigureVoltooid], niet door deze service
  /// zelf, want main.dart houdt de configure in eigen hand voor
  /// timing-controle (voor runApp).
  static bool _configureVoltooid = false;
  static bool _initGedaan = false;

  /// Listener-registratie: bewaar de callback zodat we bij logout /
  /// hot-reload dezelfde reference kunnen verwijderen.
  static CustomerInfoUpdateListener? _entitlementListener;

  /// Roept main.dart aan zodra `Purchases.configure()` klaar is (of
  /// silent-skipped is). Zonder deze marker zou [beschikbaar] altijd
  /// false blijven en zouden alle service-calls no-op'en.
  static void markConfigureVoltooid() {
    _configureVoltooid = true;
  }

  /// True als de SDK op dit platform bruikbaar is (native + API-key
  /// aanwezig). Web + desktop + leeg-key → false, dan slaan alle
  /// service-calls no-op en returnen `null`/`false`.
  static bool get beschikbaar {
    if (kIsWeb) return false;
    if (!_configureVoltooid) return false;
    final key = defaultTargetPlatform == TargetPlatform.android
        ? kRevenueCatAndroidKey
        : (defaultTargetPlatform == TargetPlatform.iOS
            ? kRevenueCatIosKey
            : '');
    return key.isNotEmpty;
  }

  /// Koppelt de RevenueCat-gebruiker aan de Firebase-uid. RevenueCat
  /// stuurt die uid vervolgens mee als `app_user_id` in elk webhook-
  /// event — dat is de sleutel waar de webhook-Cloud-Function op
  /// `gebruikers/{uid}` schrijft.
  ///
  /// Roep aan zodra Firebase Auth een user levert (of bij re-login).
  /// Idempotent: dubbele calls met dezelfde uid zijn een no-op.
  static Future<void> init(String uid) async {
    if (!beschikbaar) return;
    if (uid.isEmpty) return;
    if (_initGedaan) return;
    try {
      await Purchases.logIn(uid);
      _initGedaan = true;
      debugPrint('💳 PurchasesService.init: logIn($uid) OK');
    } catch (e) {
      debugPrint('💳 PurchasesService.init faalde (fail-soft): $e');
    }
  }

  /// Reset de SDK-user (bij expliciete logout in de app). Voorkomt dat
  /// een volgende inlog met een andere Firebase-uid een verkeerde
  /// entitlement-koppeling erft.
  static Future<void> logout() async {
    if (!beschikbaar) return;
    try {
      await Purchases.logOut();
      _initGedaan = false;
      debugPrint('💳 PurchasesService.logout OK');
    } catch (e) {
      debugPrint('💳 PurchasesService.logout faalde (fail-soft): $e');
    }
  }

  /// Haalt de RevenueCat-offering op (default "current"). Returnt
  /// `null` bij onbeschikbare SDK, ontbrekende offering of netwerk-
  /// fout — caller toont dan een "Momenteel geen abonnementen
  /// beschikbaar"-fallback.
  static Future<Offering?> haalCurrentOffering() async {
    if (!beschikbaar) return null;
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current;
    } catch (e) {
      debugPrint('💳 haalCurrentOffering faalde: $e');
      return null;
    }
  }

  /// Voert een aankoop uit voor het gegeven package. Returnt
  /// `CustomerInfo` bij succes, `null` bij fout/annulering. De
  /// entitlement-update landt tegelijk op de client (via de listener
  /// in [luisterEntitlementChanges]) én server-side (via de
  /// RevenueCat-webhook naar `gebruikers/{uid}`).
  ///
  /// Play/App Store toont zelf de betaal-UI; deze method retourneert
  /// pas als user OK of Annuleer heeft getikt.
  static Future<CustomerInfo?> koop(Package pkg) async {
    if (!beschikbaar) return null;
    try {
      // purchases_flutter 9.x: purchasePackage is deprecated → gebruik
      // Purchases.purchase(PurchaseParams.package(...)). Retourneert
      // PurchaseResult met .customerInfo — dat is wat de caller wil.
      final result = await Purchases.purchase(PurchaseParams.package(pkg));
      debugPrint('💳 koop OK: ${pkg.identifier}');
      return result.customerInfo;
    } on PlatformException catch (e) {
      // Cancelled = user-annulering, geen echte fout — log op debug.
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        debugPrint('💳 koop geannuleerd door user');
      } else {
        debugPrint('💳 koop faalde: $code / $e');
      }
      return null;
    } catch (e) {
      debugPrint('💳 koop faalde (onverwacht): $e');
      return null;
    }
  }

  /// Play Store-verplicht: user moet een "Herstel aankopen"-optie
  /// hebben na re-install of accountswitch. Trigger deze vanuit
  /// Instellingen → Aankopen herstellen (2G).
  ///
  /// Returnt `CustomerInfo` bij succes zodat de caller de nieuwe
  /// entitlements kan controleren; `null` bij fout.
  static Future<CustomerInfo?> herstelAankopen() async {
    if (!beschikbaar) return null;
    try {
      final info = await Purchases.restorePurchases();
      debugPrint('💳 herstelAankopen OK — entitlements: '
          '${info.entitlements.active.keys.toList()}');
      return info;
    } catch (e) {
      debugPrint('💳 herstelAankopen faalde: $e');
      return null;
    }
  }

  /// Registreert een callback die firet bij ELKE customer-info-update
  /// (nieuwe aankoop, verlopen abonnement, restore, cross-device sync).
  /// Idempotent: eerdere listener wordt eerst verwijderd zodat we niet
  /// dubbel binnenkomen bij hot-reload.
  ///
  /// De callback zelf hoeft geen tier-schrijf te doen — die komt via
  /// de RevenueCat-webhook binnen op `gebruikers/{uid}`. Callback is
  /// puur voor UI-refresh (bijv. router die de user weer uit de
  /// paywall haalt zodra entitlement live is).
  static void luisterEntitlementChanges(
      CustomerInfoUpdateListener callback) {
    if (!beschikbaar) return;
    try {
      if (_entitlementListener != null) {
        Purchases.removeCustomerInfoUpdateListener(_entitlementListener!);
      }
      _entitlementListener = callback;
      Purchases.addCustomerInfoUpdateListener(callback);
    } catch (e) {
      debugPrint('💳 luisterEntitlementChanges faalde: $e');
    }
  }

  /// Cleanup-hook voor tests en volledig-uitloggen scenario's.
  static void stopLuisteren() {
    if (!beschikbaar) return;
    try {
      if (_entitlementListener != null) {
        Purchases.removeCustomerInfoUpdateListener(_entitlementListener!);
        _entitlementListener = null;
      }
    } catch (_) {}
  }

  /// Convenience: checkt de active entitlements op een [CustomerInfo]
  /// en mapt op onze tier-strings. Retourneert `null` als user geen
  /// actief abonnement heeft (gratis proef of verlopen).
  ///
  /// GEEN Firestore-write hier — dat doet de webhook server-side.
  static String? tierUitCustomerInfo(CustomerInfo info) {
    final actief = info.entitlements.active;
    if (actief.containsKey('groot')) return 'groot';
    if (actief.containsKey('klein')) return 'klein';
    return null;
  }
}
