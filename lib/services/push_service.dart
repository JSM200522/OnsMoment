import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color;
// BEL-S6: cloud_functions is niet meer nodig in dit bestand — het
// background-cancel-pad doet nu een directe HTTPS-POST via het http-
// package (Firebase Auth-context leeft niet cross-isolate, dus de
// callable-Dart-plugin faalt daar met unauthenticated).
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'apparaat_service.dart';
import 'bel_callkit_service.dart';
import 'bel_log_service.dart';
import 'callkit_flag_service.dart';
import 'device_modus_service.dart';
import 'kring_service.dart';

// BEL-S6: SharedPreferences-sleutels voor het idToken-persist-pad zodat
// het achtergrond-isolate (dat GEEN eigen Firebase Auth-context krijgt)
// alsnog authenticated HTTPS-calls kan doen naar cancelVideoCall.
const String _kBelIdTokenKey = 'bel_id_token_v1';
const String _kBelIdTokenTsKey = 'bel_id_token_ts_ms_v1';

// BEL-S7: SharedPreferences-vlag om de herhaal-loop
// (_herhaalGesprekMelding) te stoppen zodra de gebruiker de melding
// bewust heeft aangetikt (body-tap → main-isolate). Zonder deze cross-
// isolate vlag draaide de loop stug door en toonde elke ~8s een NIEUWE
// melding — die de user opnieuw kon aantikken en dan bij cold-start
// direct in gesprek zou belanden (probleem 1 + probleem 2).
String _kGesprekGestoptKey(String callId) => 'bel_gesprek_gestopt_$callId';

// BEL-S7: onthoud de laatst-verwerkte callId + timestamp zodat de main-
// isolate een dubbele publish naar incomingCallNotifier binnen 60s skipt.
// Voorkomt dat een 2e melding (herhaal-loop) opnieuw naar GesprekScherm
// leidt terwijl de user het gesprek al heeft afgerond.
const String _kLaatsteCallIdKey = 'bel_laatste_call_id_v1';
const String _kLaatsteCallTsKey = 'bel_laatste_call_ts_ms_v1';
const int _kDubbelPublishMaxAgeMs = 60 * 1000;
// Token uit Firebase Auth is 1u geldig; we gebruiken 55min zodat we
// nooit een net-verlopen token als "vers" behandelen.
const int _kBelIdTokenMaxAgeMs = 55 * 60 * 1000;
// Cloud Functions-callable-URL. Callables zijn onder de motorkap gewoon
// HTTPS-endpoints; we spreken hetzelfde `{data: ...}` / `{result: ...}`
// contract zoals de cloud_functions Dart-plugin dat ook doet.
const String _kCancelVideoCallUrl =
    'https://europe-west1-onsmonent.cloudfunctions.net/cancelVideoCall';

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
  /// BEL-P2: true als de callee al bewust heeft opgenomen (callkit
  /// accept-event, notif-actionId=='accept', of cold-start replay). De
  /// main-flow springt dan DIRECT naar GesprekScherm — geen inkomend-
  /// gesprek-scherm meer (dat zou dubbel voelen) en géén auto-opnemen-
  /// waarschuwingsscherm (dat is voor onaangekondigde auto-answer, niet
  /// voor bewust getikt-opnemen). Onafhankelijk van [autoAnswer]: de
  /// server-side kring-instelling blijft leidend voor onverwachte auto-
  /// opnemen; deze vlag zegt "gebruiker heeft de intentie bewezen".
  final bool handmatigGeaccepteerd;

  const IncomingCall({
    required this.roomName,
    required this.callId,
    required this.callerName,
    required this.calleeToken,
    required this.kringId,
    required this.ontvangenOp,
    this.autoAnswer = false,
    this.handmatigGeaccepteerd = false,
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
      // BEL-P2: dezelfde string-conventie; wordt intern gezet door
      // callkit-accept-event, notif-actionId=='accept' en cold-start
      // replay via een aangepaste kopie van de fcm-data-map.
      handmatigGeaccepteerd: data['handmatigGeaccepteerd'] == 'true',
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
  // BEL-S7: channel-id versioneerd naar v2 om Samsung One UI te dwingen
  // de sound-URI opnieuw op te bouwen. Op sommige Samsung-toestellen
  // overschreef One UI onze `RawResourceAndroidNotificationSound` met
  // `content://settings/system/notification_sound` (systeem-default), en
  // een delete+recreate van HETZELFDE channel-id herstelde dat niet
  // consistent. Een verse channel-id + gekopieerde raw resource
  // ('ons_moment_gesprek_v2.wav') dwingt Samsung tot een nieuwe binding.
  // Het oude channel wordt in initApp expliciet gedelete zodat er geen
  // orphan in Instellingen achterblijft.
  static const String gesprekChannelId = 'ons_moment_gesprek_v2';
  static const String _gesprekChannelIdLegacy = 'ons_moment_gesprek';

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
    // BEL-S8: log app-open zodat je in de bel-log chronologisch kunt
    // zien wanneer de app opnieuw is opgestart. Combineer met de
    // "FCM background ENTRY"-logs om te bepalen of een test-belletje
    // (bij scherm-uit) de app wél/niet uit slaap wist te wekken.
    unawaited(BelLogService.log('PushService.initApp start (cold-start of resume)'));
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
        // BEL-S7: verwijder óók de legacy v1-channel zodat er geen orphan
        // 'ons_moment_gesprek' achterblijft in Instellingen → Meldingen
        // nadat we naar '_v2' zijn overgestapt.
        await androidImpl?.deleteNotificationChannel(_gesprekChannelIdLegacy);
        // Verwijder de v2-channel óók idempotent zodat een instellingswijziging
        // (sound, importance) altijd doorwerkt bij de volgende create-call.
        // Android channels zijn immutable ná eerste aanmaak — delete+recreate
        // is de enige manier om ze te updaten.
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
      // sound: ons_moment_gesprek_v2 → res/raw/ons_moment_gesprek_v2.wav
      // (marimba-ringtone, ~26s). BEL-S7 hernoemd van v1 om Samsung One UI
      // te dwingen de sound-URI opnieuw op te bouwen (v1-channel had URI
      // overschreven naar systeem-default). Android speelt eenmalig bij
      // verschijnen; in-app looping via just_audio in InkomendGesprekScherm.
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          gesprekChannelId,
          'Ons Moment – Inkomend gesprek',
          description: 'Inkomend videogesprek van familie',
          importance: Importance.max,
          sound: RawResourceAndroidNotificationSound('ons_moment_gesprek_v2'),
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
      FirebaseMessaging.onMessage.listen((msg) async {
        debugPrint('🔔 FCM foreground: ${msg.messageId} '
            'data=${msg.data} notification=${msg.notification?.title}');
        // Await zodat de B-of-A-beslissing sequentieel loopt: als B slaagt
        // wordt A NOOIT geraakt (geen fire-and-forget-race).
        await _publiceerInkomendGesprek(msg);
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
      final didLaunch = launchDetails?.didNotificationLaunchApp == true;
      unawaited(BelLogService.log(
          'getNotificationAppLaunchDetails.didLaunch=$didLaunch'));
      if (didLaunch) {
        final resp = launchDetails!.notificationResponse;
        final payload = resp?.payload?.trim() ?? '';
        unawaited(BelLogService.log(
            'cold-start-tap actionId=${resp?.actionId ?? "tap"} '
            'payloadLen=${payload.length}'));
        if (payload.isNotEmpty) {
          // BEL-S6 + BEL-S7: bij cold-start met een inkomend_gesprek-payload
          // forceer actionId='accept'. User heeft bij dichte app op de
          // bel-melding getikt = wilde opnemen. Zonder deze forcering zou
          // main.dart:373 het InkomendGesprekScherm openen (bevestig-scherm
          // met 'Beantwoorden'-knop) en zou de user een tweede tik nodig
          // hebben. Bij OPEN app blijft actionId=null via het separate
          // pad `onDidReceiveNotificationResponse` (regel 249) — die
          // toont wél InkomendGesprekScherm, wat daar gewenst is.
          //
          // BEL-S7 uitzondering: als de payload autoAnswer='true' bevat,
          // NIET forceer accept. Dan is dit een dierbare-scenario (kring
          // heeft server-side autoAnswer aan) en willen we juist de
          // AutoOpnemenWaarschuwingScherm-flow (2.5s "we nemen zo op…"
          // → GesprekScherm) — main.dart:341-366. handmatigGeaccepteerd
          // wint boven autoAnswer in main.dart:315; zonder deze exception
          // zou fullScreenIntent-launch bij scherm-uit direct in gesprek
          // gaan zonder waarschuwing, niet wat de kwetsbaarste doelgroep
          // verdient.
          String? effectiefActionId = resp?.actionId;
          try {
            final decoded = jsonDecode(payload);
            if (decoded is Map && decoded['type'] == 'inkomend_gesprek') {
              final autoAnswerAan = decoded['autoAnswer'] == 'true';
              if (autoAnswerAan) {
                unawaited(BelLogService.log(
                    'cold-start body-tap: autoAnswer=true → laat autoAnswer-'
                    'flow winnen (waarschuwingsscherm)'));
              } else {
                effectiefActionId = 'accept';
                unawaited(BelLogService.log(
                    'cold-start body-tap op belletje → forceer accept'));
              }
            }
          } catch (_) {}
          debugPrint('🔔 Lokale notificatie launch: payload=$payload '
              'actionId=$effectiefActionId');
          _verwerkLokaalNotificatieTik(payload, actionId: effectiefActionId);
        }
      }

      // BEL-S6: persist idToken zodat het achtergrond-isolate authenticated
      // HTTPS-calls naar cancelVideoCall kan doen bij weigeren-vanuit-dichte-
      // app. Dit isolate heeft anders geen Firebase Auth-context, waardoor
      // FirebaseFunctions.instance.httpsCallable(...) throws unauthenticated.
      // De token is ~1u geldig; we refreshen bij elke app-open (initApp).
      // Fail-soft: als er geen user is (uitgelogd) of getIdToken faalt,
      // slaan we niets op — het achtergrond-pad valt dan terug op de
      // bestaande 45s-timeout aan de beller-kant.
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final token = await user.getIdToken();
          if (token != null && token.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_kBelIdTokenKey, token);
            await prefs.setInt(_kBelIdTokenTsKey,
                DateTime.now().millisecondsSinceEpoch);
            unawaited(BelLogService.log(
                'idToken opgeslagen voor achtergrond-cancel '
                '(len=${token.length})'));
          }
        }
      } catch (e) {
        unawaited(BelLogService.log(
            'idToken persist faalde (niet blocking): $e'));
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
  /// dan wordt handmatigGeaccepteerd geforceerd op true zodat
  /// [_verwerkInkomendGesprek] DIRECT naar GesprekScherm springt (geen
  /// tussenscherm, geen waarschuwingsscherm — de gebruiker heeft immers
  /// bewust getikt). BEL-P2 vervangt de oude autoAnswer-force die de
  /// callee door het "we nemen zo op…"-scherm liet lopen na handmatig
  /// opnemen.
  static void _verwerkLokaalNotificatieTik(String payload,
      {String? actionId}) {
    if (payload.isEmpty) return;
    unawaited(BelLogService.log(
        '_verwerkLokaalNotificatieTik (actionId=${actionId ?? "tap"})'));
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      if (data['type'] == 'inkomend_gesprek') {
        var call = IncomingCall.uitFcmData(data);
        if (call != null) {
          // BEL-S7: stop de achtergrond-herhaal-loop voor DEZE callId zodra
          // de user de melding heeft aangetikt (body-tap of accept-forceer).
          // Vlag wordt gelezen in _herhaalGesprekMelding vóór elke iteratie.
          // Ook: cancel de eventueel al getoonde notification-ids 1001-1004
          // zodat de melding zichtbaar verdwijnt.
          unawaited(_zetGesprekGestopt(call.callId));
          unawaited(_wisGesprekMeldingen());
          // BEL-S7: dubbel-publish-skip. Als binnen 60s dezelfde callId
          // al is verwerkt (bijv. door een 2e melding uit de herhaal-loop
          // dat door de user opnieuw is aangetikt), skip de nieuwe publish.
          // Voorkomt "ongewild opnieuw opnemen" na een gesprek.
          if (_isDubbelBinnenVenster(call.callId)) {
            unawaited(BelLogService.log(
                'dubbel-publish geskipt (callId=${call.callId} <60s)'));
            return;
          }
          unawaited(_zetLaatsteCallId(call.callId));
          // 'Opnemen'-knop getikt → zet handmatigGeaccepteerd zodat het
          // gesprek direct opent zonder InkomendGesprekScherm en zonder
          // waarschuwingsscherm. autoAnswer blijft de server-side waarde.
          if (actionId == 'accept' && !call.handmatigGeaccepteerd) {
            call = IncomingCall(
              roomName: call.roomName,
              callId: call.callId,
              callerName: call.callerName,
              calleeToken: call.calleeToken,
              kringId: call.kringId,
              ontvangenOp: call.ontvangenOp,
              autoAnswer: call.autoAnswer,
              handmatigGeaccepteerd: true,
            );
          }
          // De-dup laag 1: sla over als dit gesprek al in de notifier staat.
          // Geval (a) terminated → enig actief pad, geen race verwacht.
          // Geval (c) grensgeval → voorkomt dubbele emit als beide paden
          // bijna tegelijk vuren voor dezelfde callId. Fallback: de
          // _inkomendGesprekOpen-vlag in _OntvangerRouterState.
          if (incomingCallNotifier.value?.callId != call.callId) {
            incomingCallNotifier.value = call;
            unawaited(BelLogService.log(
                'navigatie naar gesprek (callId=${call.callId}, '
                'handmatig=${call.handmatigGeaccepteerd})'));
          }
        }
        return;
      }
    } catch (_) {}
    tapMomentIdNotifier.value = payload;
  }

  /// BEL-S7: schrijft de "gesprek gestopt"-vlag zodat het achtergrond-
  /// isolate's herhaal-loop bij volgende iteratie afbreekt. Fail-soft.
  static Future<void> _zetGesprekGestopt(String callId) async {
    if (callId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kGesprekGestoptKey(callId), true);
    } catch (_) {}
  }

  /// BEL-S7: cancel de zichtbare bel-meldingen (1001..1004) direct bij
  /// body-tap zodat de UI niet nog een gedateerde melding toont terwijl
  /// user in GesprekScherm zit. Idempotent + fail-soft.
  static Future<void> _wisGesprekMeldingen() async {
    try {
      for (var id = 1001; id <= 1004; id++) {
        await _localNotifications.cancel(id);
      }
    } catch (_) {}
  }

  /// BEL-S7: dubbel-publish-check. Return true als deze callId <60s
  /// geleden al door _verwerkLokaalNotificatieTik is verwerkt.
  static bool _isDubbelBinnenVenster(String callId) {
    if (callId.isEmpty) return false;
    // SharedPreferences read is async — hier synchroon aannemen dat
    // de state uit dezelfde isolate al is bijgewerkt. Voor cross-isolate
    // is de flag in prefs pas ná onze eerste _zetLaatsteCallId aanwezig.
    // De check leest voluit async in de tik-flow via de eerste helper;
    // deze snelle synchrone stub gebruikt de in-memory hint.
    final laatste = _laatsteVerwerkteCallIdSync;
    if (laatste == null) return false;
    if (laatste != callId) return false;
    final ageMs = DateTime.now().millisecondsSinceEpoch
        - (_laatsteVerwerkteCallTsMsSync ?? 0);
    return ageMs < _kDubbelPublishMaxAgeMs;
  }

  static String? _laatsteVerwerkteCallIdSync;
  static int? _laatsteVerwerkteCallTsMsSync;

  static Future<void> _zetLaatsteCallId(String callId) async {
    _laatsteVerwerkteCallIdSync = callId;
    _laatsteVerwerkteCallTsMsSync = DateTime.now().millisecondsSinceEpoch;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLaatsteCallIdKey, callId);
      await prefs.setInt(_kLaatsteCallTsKey, _laatsteVerwerkteCallTsMsSync!);
    } catch (_) {}
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
  static Future<void> _publiceerInkomendGesprek(RemoteMessage msg) async {
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

    // BEL-E2: auto-answer bypasst B volledig. De native call-UI toont
    // altijd een tap-om-op-te-nemen-melding — dat botst met de bedoeling
    // van "automatisch opnemen". Bij autoAnswer=true dus direct de A-flow:
    // notifier → AutoOpnemenWaarschuwingScherm → GesprekScherm. Geen
    // callkit-melding, geen dubbele ringtone. Consistent voor foreground:
    // de app is open, de dierbare krijgt binnen 2.5s het waarschuwscherm
    // + camera-open.
    if (call.autoAnswer) {
      debugPrint('☎️ BEL-E2 fg: autoAnswer=true → skip callkit, '
          'direct notifier (callId=${call.callId})');
      incomingCallNotifier.value = call;
      return;
    }

    // BEL-B3 + BEL-E1: één gate, één pad. Als callkit-flag aan én niet
    // vergrendeld → probeer Optie B synchroon (await). Slaagt B, dan A
    // wordt NOOIT geraakt in dezelfde FCM-cyclus. Faalt B, dan (en
    // uitsluitend dan) val terug op A. In vergrendelde modus draait de
    // kiosk-flow (foreground app + InkomendGesprekScherm) — die mag niet
    // gedupliceerd worden door B.
    final modus = DeviceModusService.weergaveModusNotifier.value;
    final vergrendeld = modus == DeviceModusService.VERGRENDELD;
    final flagAan = CallkitFlagService.isEnabledSync();
    debugPrint('☎️ BEL-B3 fg-check: callId=${call.callId} '
        'modus=${modus ?? "onbekend"} vergrendeld=$vergrendeld '
        'flag=$flagAan → ${!vergrendeld && flagAan ? "PROBEER OPTIE B" : "OPTIE A"}');
    if (!vergrendeld && flagAan) {
      final getoond = await BelCallkitService.showCallkit(
        callId: call.callId,
        callerName: call.callerName,
        fcmData: Map<String, dynamic>.from(msg.data),
      );
      debugPrint('☎️ BEL-B3 fg-result: callId=${call.callId} '
          'showCallkit=${getoond ? "GELUKT (B actief, A wordt overgeslagen)" : "GEFAALD (val terug op A)"}');
      if (getoond) return; // BEL-E1: B is de gate, A blijft dicht.
      // B faalde → val terug op de bestaande foreground-pad.
      if (incomingCallNotifier.value?.callId != call.callId) {
        incomingCallNotifier.value = call;
      }
      return;
    }
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
    final type = message.data['type'];
    debugPrint('🔔 FCM background: ${message.messageId} type=$type');
    // BEL-S8: log ELKE FCM-binnenkomst (niet alleen inkomend_gesprek)
    // zodat we bij stand-by/scherm-uit-tests kunnen aflezen of FCM
    // überhaupt de achtergrond-isolate bereikt. Als tijdens een test
    // GEEN entry verschijnt in de log: OS blokkeerde achtergrond-wake
    // (Doze/App Standby/Samsung Sleeping Apps) — dan geen
    // presentatie-probleem maar OS-restrictie, oplosbaar via battery-
    // optimization-uitzondering + vergrendelde/kiosk-modus.
    await BelLogService.log(
        'FCM background ENTRY (type=$type, msgId=${message.messageId})');
    if (type == 'inkomend_gesprek') {
      await BelLogService.log('FCM inkomend_gesprek binnen '
          '(callId=${message.data["callId"] ?? "?"})');
    }
    if (type == 'nieuw_moment') {
      await _achtergrondMomentNotificatie(message.data);
    } else if (type == 'inkomend_gesprek') {
      await _achtergrondGesprekNotificatie(message.data);
    } else if (message.data['type'] == 'gesprek_geannuleerd') {
      // BEL-A2: beller heeft opgehangen — stop de herhaal-loop en veeg
      // de melding weg zodat de callee geen ghost-rinkel meer krijgt.
      final callId = message.data['callId'];
      if (callId is String && _actieveGesprekId == callId) {
        _actieveGesprekId = null;
      }
      try {
        final plugin = FlutterLocalNotificationsPlugin();
        for (var i = 0; i < 5; i++) {
          await plugin.cancel(1001 + i);
        }
      } catch (_) {}
      // BEL-B: ook de eventuele native call-UI sluiten als B actief was.
      if (callId is String && callId.isNotEmpty) {
        await BelCallkitService.beeindigCallkit(callId);
      }
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
  final callId = _achtergrondStrUit(data, 'callId', '');
  // BEL-E2: server-side autoAnswer-vlag ook in achtergrond-isolate uitlezen.
  // FCM-waarden zijn altijd strings; 'true' is de enige truthy waarde.
  final autoAnswer = data['autoAnswer'] == 'true';
  await BelLogService.log('_achtergrondGesprekNotificatie start '
      '(caller=$callerName, autoAnswer=$autoAnswer)');

  // BEL-B7: vergrendelde-modus guard — die modus draait de app altijd
  // voorgrond en gebruikt het foreground-pad; achtergrond-notificatie
  // is daar hooguit een fallback. Native call-UI (B) zou daar dubbel
  // triggeren of het kiosk-scherm verstoren. Skip B in vergrendeld.
  //
  // BEL-S5: 3s-timeout op SharedPreferences-lookup zodat een hangende
  // read (uiterst zeldzaam maar mogelijk in fresh background isolate)
  // de bel-flow niet oneindig blokkeert. Fallback: MELDINGEN-modus is
  // het pad dat we hier sowieso volgen.
  String? modus;
  try {
    modus = await DeviceModusService.krijgWeergaveModus()
        .timeout(const Duration(seconds: 3));
  } catch (e) {
    await BelLogService.log('modus-lookup timeout/fout: $e (val op MELDINGEN)');
    modus = DeviceModusService.MELDINGEN;
  }
  final vergrendeld = modus == DeviceModusService.VERGRENDELD;
  await BelLogService.log('modus=$modus vergrendeld=$vergrendeld');

  // BEL-B4 + BEL-E2: probeer native call-UI (ConnectionService) alleen als
  // flag aan én niet vergrendeld ÉN autoAnswer NIET aan staat. Auto-answer
  // + callkit botsen: callkit vereist een tap, Android verbiedt een dichte
  // app auto-launchen. In beide gevallen wint dus A: de heads-up-notif met
  // Opnemen-knop (actionId=='accept' forceert dan autoAnswer=true en de
  // main-flow springt direct naar het waarschuwingsscherm + GesprekScherm).
  var bViaCallkit = false;
  if (!vergrendeld && !autoAnswer && callId.isNotEmpty) {
    try {
      // BEL-S5: 3s-timeout op Firestore-flag-read. Fresh background-
      // isolate zonder connectiviteit zou hier oneindig kunnen blijven
      // hangen — dan bleef de melding onvertoond ("start" maar geen
      // "plugin.initialize"). Bij timeout: fallback naar false = Optie A,
      // exact het gedrag dat de tester nu ook nodig heeft.
      final flagAan = await CallkitFlagService.isEnabled()
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
      await BelLogService.log('callkit-flag=$flagAan '
          '${flagAan ? "→ probeer optie B" : "→ optie A"}');
      if (flagAan) {
        bViaCallkit = await BelCallkitService.showCallkit(
          callId: callId,
          callerName: callerName,
          fcmData: data,
        );
        await BelLogService.log(
            'showCallkit=${bViaCallkit ? "OK (B actief)" : "FAALDE (val op A)"}');
      }
    } catch (e) {
      await BelLogService.log('B-check/show faalde: $e (val op A)');
      bViaCallkit = false;
    }
  } else {
    await BelLogService.log('B skip '
        '(vergrendeld=$vergrendeld autoAnswer=$autoAnswer '
        'callIdLeeg=${callId.isEmpty})');
  }

  if (bViaCallkit) {
    // BEL-E1: één gate, één pad. B slaagt → NIETS extra tonen. Geen
    // lokale notificatie, geen A2-herhaal-loop. Native call-UI regelt
    // beltoon + Opnemen/Weigeren via event-stream in de main-isolate.
    // _actieveGesprekId is de enige state die A vasthoudt — nodig voor
    // de cancel-cleanup-hook (gesprek_geannuleerd FCM sluit óók callkit).
    _actieveGesprekId = callId;
    await BelLogService.log('B actief — A-pad skip');
    return;
  }

  await BelLogService.log('plugin.initialize start');
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_ons_moment'),
    ),
    onDidReceiveBackgroundNotificationResponse: _achtergrondNotificatieActie,
  );
  await BelLogService.log('plugin.initialize klaar');

  // BEL-A2 (Samsung-cutoff-omzeiling): Samsung One UI kapt notification-
  // sounds af op ~15s. In plaats van één show() met stille rest, tonen
  // we DEZELFDE melding elke 8s opnieuw (~4x = ~32s ring-tijd). Elke show
  // triggert een nieuwe sound-play op OS-niveau. Bij Weiger/Opnemen
  // stopt de loop via _actieveGesprekId (top-level flag, gedeeld tussen
  // isolate-invocaties zolang de VM leeft).
  //
  // Beperking: dit isolate kan door OS gedood worden op zeer agressieve
  // Samsungs; dan stopt de loop na de eerste show. Volledige rotsvaste
  // fix = native foreground service (post-launch upgrade).
  _actieveGesprekId = callId;
  await BelLogService.log(
      'Optie A pad — _toonGesprekNotificatie aanroepen (fullScreenIntent)');
  await _toonGesprekNotificatie(plugin, callerName, data, notificationId: 1001);
  unawaited(_herhaalGesprekMelding(plugin, callerName, data, callId));
}

/// Top-level vlag om herhaal-loops te stoppen bij Weiger/Opnemen.
/// Enkel gebruikt in het achtergrond-isolate.
String? _actieveGesprekId;

Future<void> _herhaalGesprekMelding(
    FlutterLocalNotificationsPlugin plugin,
    String callerName,
    Map<String, dynamic> data,
    String callId) async {
  const herhalingen = 3; // ~3x 8s na de eerste = totaal ~32s
  const interval = Duration(seconds: 8);
  for (int i = 0; i < herhalingen; i++) {
    await Future<void>.delayed(interval);
    // Stop als user Weiger/Opnemen heeft getikt (flag gewijzigd door
    // _achtergrondNotificatieActie) of als een nieuwe call is binnengekomen.
    if (_actieveGesprekId != callId) return;
    // BEL-S7: cross-isolate stop-vlag. Bij body-tap in het main-isolate
    // wordt SharedPreferences '_kGesprekGestoptKey($callId)' op true gezet;
    // in-memory `_actieveGesprekId` (dit isolate) blijft dan misleidend
    // hetzelfde. Lees de vlag vóór elke herhaal-iteratie zodat de melding
    // NIET nog een keer verschijnt terwijl user in GesprekScherm zit.
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kGesprekGestoptKey(callId)) == true) {
        await BelLogService.log(
            'herhaal-loop gestopt: gesprek_gestopt-vlag AAN '
            '(callId=$callId, iter=$i)');
        return;
      }
    } catch (_) {}
    try {
      // Nieuw ID per iteratie zodat OS de sound opnieuw afspeelt
      // (dezelfde ID + update wordt als 'in progress' beschouwd en
      // speelt de sound vaak niet opnieuw).
      final id = 1001 + i + 1;
      await _toonGesprekNotificatie(plugin, callerName, data,
          notificationId: id);
      // Ruim oude ID op zodat er visueel maar 1 melding staat.
      await plugin.cancel(id - 1);
    } catch (_) {
      return;
    }
  }
}

Future<void> _toonGesprekNotificatie(
    FlutterLocalNotificationsPlugin plugin,
    String callerName,
    Map<String, dynamic> data,
    {required int notificationId}) async {
  try {
    await plugin.show(
    notificationId,
    'Inkomend videogesprek',
    // BEL-S6: duidelijkere body die de user vertelt WAT te doen.
    // Vroeger stond hier "$callerName wil videobellen"; de tester wist
    // niet dat je op de melding-body moest tikken om op te nemen.
    '$callerName belt — tik hier om op te nemen',
    NotificationDetails(
      android: AndroidNotificationDetails(
        PushService.gesprekChannelId,
        'Ons Moment – Inkomend gesprek',
        importance: Importance.max,
        priority: Priority.high,
        icon: 'ic_stat_ons_moment',
        color: const Color(0xFFFF9B71),
        largeIcon: const DrawableResourceAndroidBitmap('ons_moment_logo'),
        ticker: 'Inkomend videogesprek',
        showWhen: false,
        autoCancel: false,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        visibility: NotificationVisibility.public,
        // BEL-S6: 'Opnemen'-actionButton VERWIJDERD. Op Android 12+ opent
        // die niet betrouwbaar de app door notification-trampoline
        // restrictions — bevestigd door de tester's log
        // "getNotificationAppLaunchDetails.didLaunch=false" bij tik op
        // Opnemen. Body-tap fires deze API wel betrouwbaar (community-
        // bewezen patroon, changelog 8.1.1+1). De cold-start-pad in
        // initApp forceert dan actionId='accept' → direct GesprekScherm.
        // Weiger-button blijft: showsUserInterface:false gebruikt het
        // background-isolate-pad (_achtergrondNotificatieActie) dat
        // niet op de trampoline-restrictie loopt.
        actions: <AndroidNotificationAction>[
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
    await BelLogService.log('melding getoond OK (id=$notificationId)');
  } catch (e, st) {
    await BelLogService.log('melding tonen FAALDE: $e');
    debugPrint('⚠️ _toonGesprekNotificatie faalde: $e\n$st');
  }
}

/// Top-level handler voor notificatie-acties die worden getikt terwijl de
/// app NIET in de voorgrond staat (vereist door flutter_local_notifications
/// zodra er een action met showsUserInterface:false bestaat).
///
/// 'Opnemen' (showsUserInterface:true) bereikt dit pad NIET — die brengt de
/// app naar de voorgrond en triggert onDidReceiveNotificationResponse in de
/// hoofd-isolate.
///
/// 'Weigeren' (showsUserInterface:false) komt hier binnen. cancelNotification
/// heeft de melding al weggehaald op OS-niveau, maar de LiveKit-room bij de
/// beller loopt door tot z'n eigen timeout — vanuit de callee gezien voelt
/// dat als "weigeren doet niks". Fix: roep cancelVideoCall aan zodat de
/// beller-app een `gesprek_geannuleerd`-FCM krijgt en direct stopt.
@pragma('vm:entry-point')
void _achtergrondNotificatieActie(NotificationResponse response) {
  // Stop de herhaal-loop van BEL-A2 (voor zowel Opnemen als Weigeren).
  // Deze flag wordt door _herhaalGesprekMelding gecheckt zodat de
  // marimba niet meer opnieuw afgaat na een user-actie.
  _actieveGesprekId = null;

  unawaited(BelLogService.log(
      '_achtergrondNotificatieActie (actionId=${response.actionId ?? "?"})'));
  if (response.actionId != 'decline') return;
  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;
  // Async werk niet awaiten — de callback moet snel terugkeren zodat het
  // OS de melding sluit. Fire-and-forget met eigen error-handling.
  unawaited(_stuurAchtergrondCancel(payload));
}

/// Roept cancelVideoCall aan vanuit het achtergrond-isolate zodat de
/// beller-app stopt met bellen wanneer de callee 'Weigeren' tikt bij
/// gesloten app.
///
/// Fail-soft: bij missende velden, netwerk-fout of auth-fout blijft de
/// call-cancel achterwege. De beller valt terug op zijn eigen 45s-timeout.
/// Nooit throwen — dit isolate heeft geen UI om een fout aan te tonen.
Future<void> _stuurAchtergrondCancel(String payload) async {
  await BelLogService.log('_stuurAchtergrondCancel start');
  try {
    final data = jsonDecode(payload);
    if (data is! Map) {
      await BelLogService.log('cancel: payload is geen Map (skip)');
      return;
    }
    final kringId = data['kringId'];
    final callId = data['callId'];
    final bellerApparaatId = data['bellerApparaatId'];
    if (kringId is! String || kringId.isEmpty) {
      await BelLogService.log('cancel: kringId ontbreekt (skip)');
      return;
    }
    if (callId is! String || callId.isEmpty) {
      await BelLogService.log('cancel: callId ontbreekt (skip)');
      return;
    }
    if (bellerApparaatId is! String || bellerApparaatId.isEmpty) {
      await BelLogService.log('cancel: bellerApparaatId ontbreekt (skip)');
      return;
    }

    // BEL-S6: haal idToken uit SharedPreferences (bewaard door initApp in
    // het main-isolate). Firebase Auth-context leeft NIET cross-isolate,
    // dus FirebaseFunctions.instance.httpsCallable(...) faalt met
    // unauthenticated in dit achtergrond-isolate. In plaats daarvan doen
    // we een directe HTTPS-POST naar de callable-URL — die accepteert
    // exact hetzelfde `{data: ...}` / `{result: ...}` contract als de
    // Dart plugin.
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kBelIdTokenKey);
    final tokenTsMs = prefs.getInt(_kBelIdTokenTsKey) ?? 0;
    final tokenLeeftijdMs =
        DateTime.now().millisecondsSinceEpoch - tokenTsMs;
    if (token == null || token.isEmpty) {
      await BelLogService.log(
          'cancel: geen opgeslagen idToken — skip (val op 45s timeout)');
      return;
    }
    if (tokenLeeftijdMs > _kBelIdTokenMaxAgeMs) {
      await BelLogService.log(
          'cancel: idToken verlopen (age=${tokenLeeftijdMs}ms) — '
          'skip (val op 45s timeout)');
      return;
    }
    await BelLogService.log(
        'cancel: idToken vers (age=${tokenLeeftijdMs}ms), HTTP-POST start');

    final response = await http.post(
      Uri.parse(_kCancelVideoCallUrl),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(<String, dynamic>{
        'data': <String, dynamic>{
          'kringId': kringId,
          'callId': callId,
          'doelApparaatId': bellerApparaatId,
        },
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      await BelLogService.log(
          'cancelVideoCall HTTP ✓ (status=200, weiger vanaf achtergrond)');
    } else {
      // Compact body-preview zodat de log leesbaar blijft.
      final preview = response.body.length > 120
          ? '${response.body.substring(0, 120)}…'
          : response.body;
      await BelLogService.log(
          'cancelVideoCall HTTP faalde: status=${response.statusCode} '
          'body=$preview');
    }
  } catch (e) {
    await BelLogService.log(
        'cancelVideoCall FAALDE (weiger vanaf achtergrond): $e');
    debugPrint('⚠️ achtergrond-weiger cancelCall faalde: $e');
  }
}
