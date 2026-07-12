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
  /// Bron van waarheid voor de mapping herkenningsgeluid → notification-
  /// channel-id. Elke kring heeft een herkenningsgeluid uit deze 6 IDs
  /// (zie [kGeluidAssets] in lib/data/geluiden.dart, autoritatieve bron
  /// in kringen/{kringId}.herkenningsgeluid). De Cloud Function (Fase 3)
  /// leest de kring, kiest via deze map het juiste channel-id en zet
  /// dat als `notification.android.channel_id` in de FCM-payload; het
  /// systeem speelt dan het bijbehorende geluid via het channel.
  ///
  /// Channels zijn Android-immutable na registratie — wisselen van
  /// herkenningsgeluid door de familie betekent alleen dat volgende
  /// meldingen op een ander channel binnenkomen. Alle 6 channels worden
  /// bij eerste app-open aangemaakt zodat live wisselen direct werkt.
  static const Map<String, String> channelIdVoorGeluid = {
    'twinkel':  'ons_moment_twinkel',
    'bel':      'ons_moment_bel',
    'vogel':    'ons_moment_vogel',
    'piano':    'ons_moment_piano',
    'kerkklok': 'ons_moment_kerkklok',
    'hart':     'ons_moment_hart',
  };

  /// User-visible namen voor de 6 channels in Android Instellingen →
  /// App-meldingen. Gemapt op geluid-ID (niet channel-ID) zodat het
  /// eenvoudig blijft synchroon met [kGeluiden] in geluiden.dart.
  static const Map<String, String> _channelNaamVoorGeluid = {
    'twinkel':  'Ons Moment – Twinkel',
    'bel':      'Ons Moment – Zachte bel',
    'vogel':    'Ons Moment – Vogel',
    'piano':    'Ons Moment – Piano',
    'kerkklok': 'Ons Moment – Kerkklok',
    'hart':     'Ons Moment – Liefdes-melodie',
  };

  /// Channel-ID uit Fase 1 dat bij commit 2b vervangen wordt door de 6
  /// per-geluid channels. Wordt bij initApp geprobeerd te deleten zodat
  /// het channel niet als weeskind achterblijft in Android-instellingen
  /// bij bestaande installs.
  static const String _oudDefaultChannelId = 'ons_moment_default';

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static bool _initGedaan = false;
  static StreamSubscription<String>? _tokenRefreshSub;

  /// Gecacht zodat de onTokenRefresh-listener naar hetzelfde apparaat-doc
  /// kan schrijven zonder dat de aanroeper de ids opnieuw doorgeeft.
  static String? _huidigeFamilieUid;
  static String? _huidigeApparaatId;

  /// Fase 2c: pusht het moment-id uit een aangetikte notificatie door naar
  /// de UI-schermen (familie_scherm en tablet_scherm). Beide luisteren
  /// erop en tonen bij een niet-null waarde de popup voor dat moment via
  /// hun eigen bestaande `_toonPopup`. Payload-conventie: de Cloud Function
  /// (Fase 3) zet `data: {'momentId': '<firestore-doc-id>'}` in de
  /// FCM-payload; tikken op de tray-notificatie triggert dan `onMessage
  /// OpenedApp` of `getInitialMessage`, en die zetten deze notifier.
  ///
  /// De consumer (het scherm) is verantwoordelijk voor het resetten naar
  /// null zodra hij de tik heeft afgehandeld, zodat een re-emit hem niet
  /// opnieuw laat afvuren. Op web blijft de waarde altijd null (initApp
  /// doet no-op via kIsWeb-guard).
  static final ValueNotifier<String?> tapMomentIdNotifier =
      ValueNotifier<String?>(null);

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

      // Cleanup: verwijder het Fase-1 channel zodat het niet als weeskind
      // in Android-instellingen achterblijft. Silent fail als niet aanwezig
      // (nieuwe installs of al eerder verwijderd).
      try {
        await androidImpl?.deleteNotificationChannel(_oudDefaultChannelId);
      } catch (_) {}

      // Zes channels registreren, één per herkenningsgeluid. Elk channel
      // is immutable na aanmaak, dus we doen dit één keer bij eerste
      // app-open. Wisselt de familie het herkenningsgeluid, dan komen
      // volgende meldingen automatisch op een ander bestaand channel.
      for (final entry in channelIdVoorGeluid.entries) {
        final geluidId = entry.key;
        final channelId = entry.value;
        final channelNaam = _channelNaamVoorGeluid[geluidId]
            ?? 'Ons Moment';
        await androidImpl?.createNotificationChannel(
          AndroidNotificationChannel(
            channelId,
            channelNaam,
            description: 'Nieuwe berichten van je familie',
            importance: Importance.high,
            sound: RawResourceAndroidNotificationSound(channelId),
          ),
        );
      }

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
        _publiceerTapMomentId(msg);
      });

      // Tap terwijl app volledig gesloten was. De schermen luisteren op
      // tapMomentIdNotifier en pikken de waarde op zodra ze bouwen —
      // main() await't initApp() vóór runApp(), dus de notifier is gezet
      // vóór het eerste build.
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        debugPrint('🔔 FCM tap (terminated launch): ${initial.messageId} '
            'data=${initial.data}');
        _publiceerTapMomentId(initial);
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

  /// Leest `data.momentId` uit een FCM-payload en publiceert die op
  /// [tapMomentIdNotifier]. Bij ontbreken of leeg → notifier wordt niet
  /// gezet (fail-safe: app opent gewoon zonder popup). Trimmed zodat
  /// whitespace-only waarden ook worden genegeerd.
  static void _publiceerTapMomentId(RemoteMessage msg) {
    final raw = msg.data['momentId'];
    if (raw is! String) return;
    final id = raw.trim();
    if (id.isEmpty) return;
    tapMomentIdNotifier.value = id;
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
