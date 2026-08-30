import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// Wrapper rond flutter_callkit_incoming voor de Optie B ConnectionService-
/// integratie. In B2 alleen een safe warm-up-probe zonder gedragswijziging.
/// De bel-flow loopt in deze fase nog volledig via de bestaande weg
/// (Optie A: FCM data-only + flutter_local_notifications).
///
/// De plugin registreert manifest-permissies, services en receivers via
/// manifest-merging bij de Flutter-build (MANAGE_OWN_CALLS, FOREGROUND_
/// SERVICE_PHONE_CALL, CallkitConnectionService voor SELF_MANAGED-support
/// op wifi-only toestellen zonder SIM, etc.). We hoeven aan onze eigen
/// AndroidManifest.xml niets toe te voegen.
class BelCallkitService {
  /// Fire-and-forget probe die tijdens app-init de plugin één keer 'raakt'.
  /// Doel: verifiëren dat de native side bereikbaar is en geen crash geeft
  /// bij het initiële method-channel-contact. Faalt de plugin — bijv. op
  /// een toestel zonder TelecomManager, of een niet-ondersteunde firmware
  /// — dan blijft de app volledig werken via Optie A.
  ///
  /// Garanties op crash-veiligheid:
  /// - kIsWeb-guard vóór elke plugin-aanroep (plugin heeft geen web-support)
  /// - try/catch op `Object` — vangt zowel Exception als Error (incl.
  ///   MissingPluginException, PlatformException, NoSuchMethodError)
  /// - Geen rethrow, geen UI-melding, geen SharedPreferences-write
  /// - Alleen debugPrint voor diagnose
  ///
  /// Wordt aangeroepen via `unawaited(BelCallkitService.warmupProbe())`
  /// zodat de main-thread nooit wordt geblokkeerd door plugin-registratie.
  static Future<void> warmupProbe() async {
    if (kIsWeb) {
      debugPrint('☎️ BelCallkitService: web — probe overgeslagen');
      return;
    }
    try {
      // endAllCalls is een read-only cleanup: als er geen actieve calls
      // zijn (zoals bij app-init) is dit een no-op. Wél triggert het de
      // eerste method-channel-hop naar native, wat betekent dat de plugin
      // z'n init-code doorloopt (o.a. het klaarzetten van de connection
      // service). PhoneAccount-registratie zelf blijft lazy tot de eerste
      // showCallkitIncoming (B3/B4).
      await FlutterCallkitIncoming.endAllCalls();
      debugPrint('☎️ BelCallkitService: warm-up probe OK');
    } catch (e, st) {
      // Bewust breed vangnet — een fout hier mag ONMOGELIJK de app-opstart
      // beïnvloeden. Optie A blijft de bel-flow dragen.
      debugPrint('⚠️ BelCallkitService warm-up faalde (val terug op '
          'Optie A): $e\n$st');
    }
  }
}
