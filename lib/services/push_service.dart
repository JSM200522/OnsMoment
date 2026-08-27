import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'apparaat_service.dart';
import 'device_modus_service.dart';
import 'kring_service.dart';

/// Immutable payload voor een inkomend videogesprek. Wordt gepubliceerd
/// op [PushService.incomingCallNotifier] zodra een high-priority data-
/// FCM met `type: 'inkomend_gesprek'` binnenkomt. tablet_scherm (V2-5)
/// leest hem en opent [InkomendGesprekScherm] (V2-4).
///
/// Alle velden worden server-side geleverd door startVideoCall (V2-2):
/// - [roomName]/[callId]: uniek per gesprek, gesprek_{kringId}_{ms}_{r6}
/// - [callerName]: leesbare naam van de beller, klaar voor het scherm
/// - [calleeToken]: LiveKit-JWT (10 min) — callee kan direct join'en,
///   geen tweede getVideoCallToken-call nodig
/// - [kringId]: voor logging en debug
@immutable
class IncomingCall {
  final String roomName;
  final String callId;
  final String callerName;
  final String calleeToken;
  final String kringId;
  final DateTime ontvangenOp;
  /// V4: true als de kring-eigenaar "Automatisch opnemen" heeft aangezet.
  /// Gezaghebbend: ingevuld door de Cloud Function op bel-moment vanuit
  /// het kring-doc — niet client-side op te stellen door de beller.
  /// Default false bij ontbrekend veld (backward-compat met pre-V4 FCM).
  final bool autoAnswer;

  const IncomingCall({
    required this.roomName,
    required this.callId,
    required this.callerName,
    required this.calleeToken,
    required this.kringId,
    required this.ontvangenOp,
    this.autoAnswer = false,
  });

  /// Bouwt uit een FCM-data-map. Returnt null als één van de vereiste
  /// velden ontbreekt of leeg is — dan wordt er niks op de notifier
  /// gezet en logt PushService een waarschuwing.
  static IncomingCall? uitFcmData(Map<String, dynamic> data) {
    final roomName = data['roomName'];
    final callId = data['callId'];
    final callerName = data['callerName'];
    final calleeToken = data['calleeToken'];
    final kringId = data['kringId'];
    if (roomName is! String || roomName.isEmpty
        || callId is! String || callId.isEmpty
        || callerName is! String || callerName.isEmpty
        || calleeToken is! String || calleeToken.isEmpty
        || kringId is! String || kringId.isEmpty) {
      return null;
    }
    return IncomingCall(
      roomName: roomName,
      callId: callId,
      callerName: callerName,
      calleeToken: calleeToken,
      kringId: kringId,
      ontvangenOp: DateTime.now(),
      // FCM-waarden zijn altijd strings; 'true' is de enige truthy waarde.
      // Ontbrekend veld → false (backward-compat).
      autoAnswer: data['autoAnswer'] == 'true',
    );
  }
}

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

  /// V2-3 / FIX-D: eigen channel voor inkomend videogesprek. Aparte channel
  /// (buiten de zes moment-channels) zodat de gebruiker in Android →
  /// App-meldingen het gesprek-geluid en de importance apart kan zetten
  /// zonder de moment-meldingen te beïnvloeden.
  ///
  /// Gebruikt door [_achtergrondGesprekNotificatie] als channel-id voor de
  /// hoge-prioriteit lokale notificatie (fullScreenIntent, category.call).
  /// startVideoCall stuurt data-only FCM → dit channel wordt via de lokale
  /// notificatie bereikt, niet direct via de FCM-payload.
  static const String gesprekChannelId = 'ons_moment_gesprek';

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static bool _initGedaan = false;
  static StreamSubscription<String>? _tokenRefreshSub;

  /// SharedPreferences-sleutel voor de oplopende badge-teller. Wordt
  /// verhoogd door de achtergrond-handler (aparte isolate, via
  /// SharedPreferences) en gereset naar 0 bij [lokaleMeldingenWissen].
  static const String _kBadgeCount = 'badge_count';

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

  /// FIX-D: publiceert een inkomend videogesprek. Drie paden:
  /// (a) terminated-app: [_achtergrondGesprekNotificatie] toont full-screen-
  ///     intent; gebruiker tikt → [_verwerkLokaalNotificatieTik] zet deze
  ///     notifier; [_OntvangerRouterState._startIncomingCallListener]
  ///     controleert huidige waarde direct na listener-attach (line 273).
  /// (b) foreground-app: [_publiceerInkomendGesprek] zet direct vanuit
  ///     onMessage.listen() — geen lokale notificatie nodig.
  /// (c) background-app (meldingen): [_achtergrondGesprekNotificatie] toont
  ///     notificatie; tik → [_verwerkLokaalNotificatieTik]; listener vuurt.
  ///
  /// De-duplication: callId-check in [_publiceerInkomendGesprek] en
  /// [_verwerkLokaalNotificatieTik] voorkomt dat twee paden dezelfde call
  /// dubbel publiceren. Fallback: _inkomendGesprekOpen-vlag in
  /// [_OntvangerRouterState] garandeert dat nooit twee schermen worden
  /// gepusht ook als de notifier twee keer met dezelfde call wordt gezet.
  ///
  /// Consumer-verantwoordelijkheid: reset naar null na afhandeling.
  static final ValueNotifier<IncomingCall?> incomingCallNotifier =
      ValueNotifier<IncomingCall?>(null);

  /// V3-5: publiceert de callId van een geannuleerd uitgaand gesprek.
  /// Beller heeft opgehangen vóór callee opnam → server pusht data-FCM
  /// `type: 'gesprek_geannuleerd'`. tablet_scherm luistert en sluit het
  /// openstaande inkomend-scherm alleen als de callId matcht met de
  /// huidig-getoonde call (voorkomt dat een stale/oude cancel-FCM het
  /// verkeerde scherm sluit).
  ///
  /// Consumer-verantwoordelijkheid als bij [tapMomentIdNotifier] en
  /// [incomingCallNotifier]: reset naar null na afhandeling.
  static final ValueNotifier<String?> cancelledCallIdNotifier =
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
          final payload = resp.payload?.trim() ?? '';
          debugPrint('🔔 Lokale notificatie getikt: payload=$payload '
              'actionId=${resp.actionId}');
          _verwerkLokaalNotificatieTik(payload, actionId: resp.actionId);
        },
        // Vereist door flutter_local_notifications zodra er een action met
        // showsUserInterface:false bestaat ('Weigeren'). Draait in een aparte
        // isolate; voor onze 'Weigeren'-actie is geen verdere afhandeling
        // nodig — cancelNotification:true ruimt de notificatie al op.
        onDidReceiveBackgroundNotificationResponse: _achtergrondNotificatieActie,
      );
      final androidImpl = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      // Cleanup: verwijder verouderde/immutable channels zodat ze niet als
      // weeskind achterblijven en zodat we sound/audioAttributes kunnen
      // updaten (Android channels zijn immutable na eerste aanmaak).
      // Silent fail als niet aanwezig (nieuwe installs of al eerder verwijderd).
      try {
        await androidImpl?.deleteNotificationChannel(_oudDefaultChannelId);
        // P2: ons_moment_gesprek werd eerder aangemaakt zonder sound en zonder
        // audioAttributesUsage → stille melding op meldingsvolume. Verwijder
        // zodat we hieronder opnieuw aanmaken met ringtone + STREAM_RING.
        await androidImpl?.deleteNotificationChannel(gesprekChannelId);
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
            showBadge: true,
          ),
        );
      }

      // P2: gesprek-channel als echte oproep — ringtone + beltoonvolume.
      //
      // audioAttributesUsage: notificationRingtone → Android stuurt het
      // geluid naar STREAM_RING (beltoonvolume). Op Pixel en Samsung One UI
      // volgt dit de fysieke beltoon-volumeknop, identiek aan een telefoon-
      // oproep. Samsung-caveat: One UI kapt notification sounds af op ~15s
      // ongeacht bestandslengte — binnen Android-OS-grens, niet omzeilbaar.
      //
      // importance: max + category call (gezet op de notificatie zelf) geven
      // op Android 13+ het recht om door DND heen te breken als calling app.
      //
      // sound: ons_moment_gesprek → res/raw/ons_moment_gesprek.wav
      // (marimba-ringtone, ~26s). Android speelt het eenmalig bij verschijnen;
      // in-app looping via just_audio in InkomendGesprekScherm.
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          gesprekChannelId,
          'Ons Moment – Inkomend gesprek',
          description: 'Inkomend videogesprek van familie',
          importance: Importance.max,
          sound: RawResourceAndroidNotificationSound('ons_moment_gesprek'),
          audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
          enableVibration: true,
          playSound: true,
        ),
      );

      // Foreground-handler: alleen loggen voor de moment-flow (de
      // Firestore-listener in familie_scherm.dart toont daar de popup —
      // een lokale notification hier zou een dubbel-tik geven). Voor
      // een inkomend-gesprek-payload publiceren we wél direct op
      // [incomingCallNotifier] zodat tablet_scherm het scherm kan
      // openen — daar is Firestore geen bron van waarheid want de
      // callee-token zit in de FCM-data.
      FirebaseMessaging.onMessage.listen((msg) {
        debugPrint('🔔 FCM foreground: ${msg.messageId} '
            'data=${msg.data} notification=${msg.notification?.title}');
        _publiceerInkomendGesprek(msg);
        _publiceerGeannuleerdGesprek(msg);
      });

      // Tap in background-state.
      FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        debugPrint('🔔 FCM tap (background→foreground): ${msg.messageId} '
            'data=${msg.data}');
        _publiceerTapMomentId(msg);
      });

      // Tap terwijl app volledig gesloten was (via FCM-notificatie).
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        debugPrint('🔔 FCM tap (terminated launch): ${initial.messageId} '
            'data=${initial.data}');
        _publiceerTapMomentId(initial);
      }

      // Tap (of fullScreenIntent auto-launch) terwijl app volledig gesloten
      // was. Payload bevat het gesprek-JSON of een momentId.
      // actionId: 'accept' als de gebruiker de 'Opnemen'-knop tikte →
      // direct naar GesprekScherm zonder InkomendGesprekScherm.
      final launchDetails =
          await _localNotifications.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        final resp = launchDetails!.notificationResponse;
        final payload = resp?.payload?.trim() ?? '';
        if (payload.isNotEmpty) {
          debugPrint('🔔 Lokale notificatie launch: payload=$payload '
              'actionId=${resp?.actionId}');
          _verwerkLokaalNotificatieTik(payload, actionId: resp?.actionId);
        }
      }
    } catch (e, st) {
      debugPrint('⚠️ PushService.initApp faalde: $e\n$st');
    }
  }

  /// Verwijdert alle zichtbare lokale notificaties en reset de badge-teller
  /// naar 0. Aanroepen wanneer de gebruiker de app opent (resumed-state) —
  /// identiek aan WhatsApp-gedrag: de telbadge daalt zodra de app wordt
  /// geopend, ongeacht of de berichten al zijn gelezen.
  ///
  /// No-op op web (kIsWeb-guard). Fail-soft — een fout hier is niet blokkerend.
  static Future<void> lokaleMeldingenWissen() async {
    if (kIsWeb) return;
    try {
      await _localNotifications.cancelAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kBadgeCount, 0);
    } catch (_) {}
  }

  /// Verwerkt de payload van een aangetikte lokale notificatie.
  /// Gespreks-notificaties bevatten een JSON-payload met alle IncomingCall-
  /// velden (type/roomName/callId/callerName/calleeToken/kringId).
  /// Moment-notificaties bevatten een kale momentId-string.
  /// Onbekende of lege payloads worden genegeerd (fail-safe).
  ///
  /// [actionId]: 'accept' als de gebruiker de 'Opnemen'-actieknop tikte —
  /// dan wordt autoAnswer geforceerd op true zodat [_verwerkInkomendGesprek]
  /// altijd direct naar GesprekScherm springt, ook als de kring autoAnswer
  /// normaal uit heeft staan. De gebruiker heeft immers bewust getikt.
  static void _verwerkLokaalNotificatieTik(String payload,
      {String? actionId}) {
    if (payload.isEmpty) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      if (data['type'] == 'inkomend_gesprek') {
        var call = IncomingCall.uitFcmData(data);
        if (call != null) {
          // 'Opnemen'-knop getikt → forceer autoAnswer zodat het gesprek
          // direct opent zonder InkomendGesprekScherm tussendoor.
          if (actionId == 'accept' && !call.autoAnswer) {
            call = IncomingCall(
              roomName: call.roomName,
              callId: call.callId,
              callerName: call.callerName,
              calleeToken: call.calleeToken,
              kringId: call.kringId,
              ontvangenOp: call.ontvangenOp,
              autoAnswer: true,
            );
          }
          // De-dup laag 1: sla over als dit gesprek al in de notifier staat.
          // Geval (a) terminated → enig actief pad, geen race verwacht.
          // Geval (c) grensgeval → voorkomt dubbele emit als beide paden
          // bijna tegelijk vuren voor dezelfde callId. Fallback: de
          // _inkomendGesprekOpen-vlag in _OntvangerRouterState.
          if (incomingCallNotifier.value?.callId != call.callId) {
            incomingCallNotifier.value = call;
          }
        }
        return;
      }
    } catch (_) {}
    tapMomentIdNotifier.value = payload;
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

      // Fase 3c-B: bepaal kringId zodat we die in dezelfde set+merge
      // als het fcmToken kunnen meeschrijven — vangt bestaande familie-
      // apparaat-docs op die 'm bij initiële registratie niet meekregen
      // (setup_wizard/accept_uitnodig/gast_signup skipten het veld).
      final kringId = await _bepaalKringIdVoorApparaat(familieUid);

      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await ApparaatService.zetFcmToken(
          familieUid: familieUid,
          apparaatId: apparaatId,
          token: token,
          platform: _huidigPlatform(),
          kringId: kringId,
        );
      }

      // onTokenRefresh: herregistreer bij token-rotatie (app-reinstall,
      // Google-account-wissel, restore from backup). Cancel eerst een
      // eventuele vorige subscription om lekken te voorkomen bij
      // opnieuw-inloggen op hetzelfde apparaat.
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub =
          FirebaseMessaging.instance.onTokenRefresh.listen((nieuw) async {
        final uid = _huidigeFamilieUid;
        final apparaat = _huidigeApparaatId;
        if (uid == null || apparaat == null) return;
        // Zelfde backfill-lookup bij elke token-refresh — de kring-
        // membership van deze gebruiker kan tussen refresh en refresh
        // gewijzigd zijn (nieuwe kring, verlaten kring).
        final refreshKringId = await _bepaalKringIdVoorApparaat(uid);
        ApparaatService.zetFcmToken(
          familieUid: uid,
          apparaatId: apparaat,
          token: nieuw,
          platform: _huidigPlatform(),
          kringId: refreshKringId,
        );
      });
    } catch (e) {
      debugPrint('⚠️ PushService.registreerHuidigApparaat faalde: $e');
    }
  }

  /// Fase 3c-B: bepaalt welk kringId in het apparaat-doc moet komen.
  ///
  /// Regels:
  /// - 0 kringen → null (user zit in geen kring; niks schrijven).
  /// - 1 kring   → gebruik die.
  /// - >1 kring  → tiebreak op [DeviceModusService.actieveKringNotifier].
  ///   Als die gezet is én in de lijst voorkomt → gebruik 'm. Anders
  ///   warning + null (liever géén kringId dan de verkeerde — de
  ///   Cloud Function skipt dit apparaat dan gewoon totdat de volgende
  ///   refresh een geldige actieve kring vindt).
  ///
  /// Fail-soft: elke fout in de collectionGroup-query wordt door
  /// [KringService.mijnKringIds] al opgevangen als lege lijst.
  static Future<String?> _bepaalKringIdVoorApparaat(String familieUid) async {
    final ids = await KringService.mijnKringIds(familieUid);
    if (ids.isEmpty) return null;
    if (ids.length == 1) return ids.first;
    final actief = DeviceModusService.actieveKringNotifier.value;
    if (actief != null && ids.contains(actief)) return actief;
    debugPrint('⚠️ PushService: gebruiker zit in ${ids.length} kringen, '
        'maar actieveKring is niet gezet of niet in de lijst — '
        'kringId overgeslagen voor apparaat-doc');
    return null;
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

  /// V2-3: publiceert een inkomend gesprek als de FCM-data een geldig
  /// `type: 'inkomend_gesprek'`-payload bevat. Onbekende types (bv.
  /// moment-payloads die géén 'type'-veld hebben) worden overgeslagen —
  /// die worden door de andere handlers of de Firestore-listener in
  /// familie_scherm afgehandeld.
  ///
  /// Als het type wél matcht maar velden missen: waarschuwing loggen en
  /// notifier ongemoeid laten. Beter dan een half-scherm met lege naam.
  static void _publiceerInkomendGesprek(RemoteMessage msg) {
    if (msg.data['type'] != 'inkomend_gesprek') return;
    final call = IncomingCall.uitFcmData(msg.data);
    if (call == null) {
      debugPrint('⚠️ inkomend-gesprek FCM incompleet: ${msg.data}');
      return;
    }
    // De-dup laag 1: sla over als dit gesprek al in de notifier staat.
    // Geval (b) foreground → enig actief pad, geen race verwacht.
    // Geval (c) grensgeval → voorkomt dubbele emit als ook
    // _verwerkLokaalNotificatieTik al vuurde voor dezelfde callId.
    // Fallback: _inkomendGesprekOpen-vlag in _OntvangerRouterState.
    if (incomingCallNotifier.value?.callId == call.callId) return;
    incomingCallNotifier.value = call;
  }

  /// V3-5: publiceert de callId van een geannuleerd gesprek als de FCM-
  /// data een geldig `type: 'gesprek_geannuleerd'`-payload bevat.
  /// Missende callId → waarschuwing + notifier ongemoeid; tablet valt
  /// dan terug op de 45s-timeout.
  static void _publiceerGeannuleerdGesprek(RemoteMessage msg) {
    if (msg.data['type'] != 'gesprek_geannuleerd') return;
    final callId = msg.data['callId'];
    if (callId is! String || callId.isEmpty) {
      debugPrint('⚠️ gesprek_geannuleerd FCM zonder callId: ${msg.data}');
      return;
    }
    cancelledCallIdNotifier.value = callId;
  }
}

/// Top-level FCM background handler. Draait in een aparte Dart-isolate;
/// Firebase + flutter_local_notifications moeten opnieuw worden geïni-
/// tialiseerd. FCM-momenten zijn data-only (geen notification-block) zodat
/// deze handler volledige controle heeft over de notificatie-weergave:
/// largeIcon, BigTextStyle, accentkleur en badge-teller.
@pragma('vm:entry-point')
Future<void> _backgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    debugPrint('🔔 FCM background: ${message.messageId} '
        'type=${message.data["type"]}');
    if (message.data['type'] == 'nieuw_moment') {
      await _achtergrondMomentNotificatie(message.data);
    } else if (message.data['type'] == 'inkomend_gesprek') {
      await _achtergrondGesprekNotificatie(message.data);
    }
  } catch (e) {
    debugPrint('⚠️ FCM background handler faalde: $e');
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Top-level helpers — zichtbaar vanuit de achtergrond-isolate.
// Geen toegang tot PushService-static-state uit de hoofd-isolate; elke
// isolate heeft zijn eigen exemplaar. Kanalen zijn wél persistent (OS-
// niveau) en hoeven hier niet opnieuw aangemaakt te worden.
// ────────────────────────────────────────────────────────────────────────────

String _achtergrondStrUit(
    Map<String, dynamic> data, String key, String fallback) {
  final v = data[key];
  return (v is String && v.isNotEmpty) ? v : fallback;
}

/// Verhoogt de badge-teller in SharedPreferences en retourneert de nieuwe
/// waarde. Bij elke fout (rechten, read-only mode) valt terug op 1.
Future<int> _achtergrondVerhoogBadge() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getInt(PushService._kBadgeCount) ?? 0) + 1;
    await prefs.setInt(PushService._kBadgeCount, next);
    return next;
  } catch (_) {
    return 1;
  }
}

/// Maakt een volledig gestijlde lokale notificatie voor een binnenkomend
/// moment. Wordt aangeroepen vanuit [_backgroundHandler] in de achtergrond-
/// isolate.
///
/// Bewijs per eis:
/// - accentkleur  → color: const Color(0xFFFF9B71) (#FF9B71 peach/oranje)
/// - largeIcon    → DrawableResourceAndroidBitmap('ons_moment_logo')
///                  (android/app/src/main/res/drawable/ons_moment_logo.png)
/// - BigTextStyle → BigTextStyleInformation(body, contentTitle: titel)
/// - badge        → number: badge (oplopend via SharedPreferences)
/// - channelId    → uit FCM-data, bepaalt herkenningsgeluid (cloud-functie
///                  schrijft 'ons_moment_twinkel' / 'ons_moment_bel' etc.)
/// - payload      → momentId, zodat tik de juiste popup opent
Future<void> _achtergrondMomentNotificatie(
    Map<String, dynamic> data) async {
  final titel     = _achtergrondStrUit(data, 'title',     'Ons Moment');
  final body      = _achtergrondStrUit(data, 'body',      'Een nieuw bericht van je familie');
  final channelId = _achtergrondStrUit(data, 'channelId', 'ons_moment_twinkel');
  final momentId  = _achtergrondStrUit(data, 'momentId',  '');

  final badge = await _achtergrondVerhoogBadge();

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_ons_moment'),
    ),
  );

  // Uniek notificatie-ID per moment zodat elk nieuw bericht als
  // losse kaart in het meldingenscherm staat (geen overwrite).
  final notifId = momentId.isNotEmpty
      ? momentId.hashCode.abs() % 2000000000
      : DateTime.now().millisecondsSinceEpoch % 2000000000;

  await plugin.show(
    notifId,
    titel,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelId,
        importance: Importance.high,
        priority: Priority.high,
        // Kleuren logo rechts in de melding (via Android largeIcon-slot).
        largeIcon: const DrawableResourceAndroidBitmap('ons_moment_logo'),
        // Volledig zichtbare tekst bij uitklappen (BigTextStyle).
        styleInformation: BigTextStyleInformation(body,
            contentTitle: titel),
        // Peach-accentkleur op het monochrome icoon in de notificatiebalk.
        color: const Color(0xFFFF9B71),
        icon: 'ic_stat_ons_moment',
        ticker: 'Nieuw bericht van je familie',
        // Badge-teller op het app-icoon. Oplopend per bericht.
        // Pixel Launcher: toont een stip (dot). Samsung One UI: toont het
        // getal. Nova Launcher en andere custom launchers: varieert.
        number: badge,
        showWhen: true,
      ),
    ),
    payload: momentId,
  );
}

/// Toont een hoge-prioriteit lokale notificatie voor een inkomend videogesprek
/// wanneer de app op de achtergrond of volledig gesloten is (FIX-D / P3).
///
/// Payload = jsonEncode(data) zodat [PushService._verwerkLokaalNotificatieTik]
/// de IncomingCall kan reconstrueren bij tik of action-knop.
///
/// Action buttons (P3):
/// - 'Opnemen' (showsUserInterface:true): brengt app naar voorgrond,
///   triggert onDidReceiveNotificationResponse met actionId:'accept' →
///   _verwerkLokaalNotificatieTik zet autoAnswer=true → direct GesprekScherm.
/// - 'Weigeren' (showsUserInterface:false): dismisst de notificatie stil,
///   app blijft dicht. Beller ziet de 45s-timeout.
///
/// fullScreenIntent wekt het scherm op lock-screen (USE_FULL_SCREEN_INTENT
/// in manifest). Op API 34+ degradeert het naar heads-up als toestemming
/// niet verleend — nooit een stille/onzichtbare toestand.
/// NotificationVisibility.public: melding zichtbaar zonder ontgrendelen.
///
/// ANDROID-GRENS: notification sound speelt éénmalig (~26s marimba).
/// In-app looping via just_audio in InkomendGesprekScherm. Looping via
/// notificatie-channel is niet mogelijk zonder native foreground service.
Future<void> _achtergrondGesprekNotificatie(
    Map<String, dynamic> data) async {
  final callerName = _achtergrondStrUit(data, 'callerName', 'Familie');

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_ons_moment'),
    ),
    onDidReceiveBackgroundNotificationResponse: _achtergrondNotificatieActie,
  );

  await plugin.show(
    1001,
    'Inkomend videogesprek',
    '$callerName wil videobellen',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        PushService.gesprekChannelId,
        'Ons Moment – Inkomend gesprek',
        importance: Importance.max,
        priority: Priority.high,
        icon: 'ic_stat_ons_moment',
        color: Color(0xFFFF9B71),
        largeIcon: DrawableResourceAndroidBitmap('ons_moment_logo'),
        ticker: 'Inkomend videogesprek',
        showWhen: false,
        autoCancel: false,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        visibility: NotificationVisibility.public,
        actions: [
          AndroidNotificationAction(
            'accept',
            'Opnemen',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            'decline',
            'Weigeren',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ],
      ),
    ),
    payload: jsonEncode(data),
  );
}

/// Top-level handler voor notificatie-acties die worden getikt terwijl de
/// app NIET in de voorgrond staat (vereist door flutter_local_notifications
/// zodra er een action met showsUserInterface:false bestaat).
///
/// Voor 'Weigeren' is geen actie nodig: cancelNotification:true heeft de
/// notificatie al verwijderd. 'Opnemen' (showsUserInterface:true) bereikt
/// dit pad nooit — die brengt de app naar de voorgrond en triggert
/// onDidReceiveNotificationResponse in de hoofd-isolate.
@pragma('vm:entry-point')
void _achtergrondNotificatieActie(NotificationResponse response) {
  // Geen verdere afhandeling — 'Weigeren' is via cancelNotification:true
  // al afgehandeld op OS-niveau.
}
