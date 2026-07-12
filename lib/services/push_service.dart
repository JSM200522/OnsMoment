import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'apparaat_service.dart';

/// FCM-basis (Fase 1 push-meldingen).
///
/// Ontwerpprincipes:
/// - **Web-veilig**: elke publieke functie doet `if (kIsWeb) return;` als
///   eerste regel. De web-build compileert doordat firebase_messaging en
///   flutter_local_notifications web-compatibele stubs leveren, maar de
///   runtime-init blijft achterwege — GitHub Pages blijft dus draaien.
/// - **Fail-soft**: alle init zit in try/catch. Als FCM faalt (permissies
///   geweigerd, Google Play Services ontbreekt, netwerk), blijft de rest
///   van de app werken. De bestaande Firestore-listeners in familie_scherm
///   dragen de UX-verantwoordelijkheid; FCM is puur aanvullend voor push
///   wanneer de app niet in de voorgrond staat.
/// - **Geen dubbele popup**: foreground-messages worden alleen gelogd.
///   De listener in familie_scherm.dart triggert de popup al; hier ook
///   een lokale notification tonen zou dubbeltellen.
class PushService {
  /// Channel-ID moet exact matchen met de meta-data
  /// `com.google.firebase.messaging.default_notification_channel_id`
  /// in AndroidManifest.xml (commit 1b). FCM plaatst pure-notification
  /// messages automatisch in dit kanaal wanneer de app in background of
  /// terminated state is.
  static const String _channelId = 'ons_moment_default';
  static const String _channelName = 'Ons Moment meldingen';
  static const String _channelDescription =
      "Berichten en foto's van je familie";

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static bool _initGedaan = false;
  static StreamSubscription<String>? _tokenRefreshSub;

  /// Gecacht zodat de onTokenRefresh-listener naar hetzelfde apparaat-doc
  /// kan schrijven zonder dat de aanroeper de ids opnieuw doorgeeft.
  static String? _huidigeFamilieUid;
  static String? _huidigeApparaatId;

  /// Roep één keer aan in main() ná Firebase.initializeApp().
  /// Idempotent — een tweede aanroep is een no-op.
  static Future<void> initApp() async {
    if (kIsWeb) return;
    if (_initGedaan) return;
    _initGedaan = true;
    try {
      // Background/terminated-handler moet vóór de eerste message worden
      // geregistreerd. De handler zelf is een top-level functie (FCM-eis)
      // — zie _backgroundHandler onderaan dit bestand.
      FirebaseMessaging.onBackgroundMessage(_backgroundHandler);

      // Local-notifications init is nodig om het channel te kunnen
      // aanmaken. Op iOS geeft resolvePlatformSpecificImplementation<
      // Android...>() null — de channel-aanroep wordt dan geskipt.
      await _localNotifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (resp) {
          debugPrint('🔔 Local notification getikt: ${resp.payload}');
        },
      );
      final androidImpl = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.high,
        ),
      );

      // Foreground-handler: alleen loggen. De Firestore-listener in
      // familie_scherm.dart toont de popup — een lokale notification
      // hier zou een dubbel-tik geven.
      FirebaseMessaging.onMessage.listen((msg) {
        debugPrint('🔔 FCM foreground: ${msg.messageId} '
            'data=${msg.data} notification=${msg.notification?.title}');
      });

      // Tap in background-state.
      FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        debugPrint('🔔 FCM tap (background→foreground): ${msg.messageId} '
            'data=${msg.data}');
      });

      // Tap terwijl app volledig gesloten was.
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        debugPrint('🔔 FCM tap (terminated launch): ${initial.messageId} '
            'data=${initial.data}');
      }
    } catch (e, st) {
      debugPrint('⚠️ PushService.initApp faalde: $e\n$st');
    }
  }

  /// Roep aan zodra een familieUid + apparaatId bekend zijn (via
  /// RouterScherm._laadInitieel bij zowel bestaande sessies als verse
  /// signIn/createUser). Vraagt meldings-toestemming, haalt het FCM-token
  /// en schrijft het naar `gebruikers/{familieUid}/apparaten/{apparaatId}`.
  /// Idempotent — meermaals aanroepen is veilig.
  static Future<void> registreerHuidigApparaat({
    required String familieUid,
    required String apparaatId,
  }) async {
    if (kIsWeb) return;
    try {
      _huidigeFamilieUid = familieUid;
      _huidigeApparaatId = apparaatId;

      // Op Android 12- geeft requestPermission() altijd authorized. Op
      // 13+ toont het systeem de runtime-dialog. Op iOS de standaard-
      // prompt. Weigering blokkeert niks — getToken werkt vaak nog wel,
      // alleen system-tray-display niet. De bestaande in-app popup
      // (Firestore-listener) blijft in beide gevallen werken.
      await FirebaseMessaging.instance.requestPermission();

      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await ApparaatService.zetFcmToken(
          familieUid: familieUid,
          apparaatId: apparaatId,
          token: token,
          platform: _huidigPlatform(),
        );
      }

      // onTokenRefresh: herregistreer bij token-rotatie (app-reinstall,
      // Google-account-wissel, restore from backup). Cancel eerst een
      // eventuele vorige subscription om lekken te voorkomen bij
      // opnieuw-inloggen op hetzelfde apparaat.
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub =
          FirebaseMessaging.instance.onTokenRefresh.listen((nieuw) {
        final uid = _huidigeFamilieUid;
        final apparaat = _huidigeApparaatId;
        if (uid == null || apparaat == null) return;
        ApparaatService.zetFcmToken(
          familieUid: uid,
          apparaatId: apparaat,
          token: nieuw,
          platform: _huidigPlatform(),
        );
      });
    } catch (e) {
      debugPrint('⚠️ PushService.registreerHuidigApparaat faalde: $e');
    }
  }

  static String _huidigPlatform() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return 'onbekend';
    }
  }
}

/// Top-level FCM background handler. Draait in een aparte Dart-isolate;
/// Firebase moet dus opnieuw worden geïnitialiseerd. Voor Fase 1 alleen
/// loggen — het systeem toont pure-notification messages zelf via het
/// channel dat in de manifest is gedeclareerd.
@pragma('vm:entry-point')
Future<void> _backgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    debugPrint('🔔 FCM background: ${message.messageId} '
        'data=${message.data} notification=${message.notification?.title}');
  } catch (e) {
    debugPrint('⚠️ FCM background handler faalde: $e');
  }
}
