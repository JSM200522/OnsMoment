import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import '../theme/kleuren.dart';
// BEL-S1: CallkitFlagService niet meer nodig — de USE_FULL_SCREEN_INTENT-
// check moet ongeacht Optie A/B draaien omdat Optie A's lokale-notificatie
// óók fullScreenIntent gebruikt.

/// BEL-Q2: check + warme prompt voor de Android 14+ USE_FULL_SCREEN_INTENT
/// special-permission. Zonder deze toestemming toont het OS de callkit-
/// notificatie hooguit in de meldingenlade i.p.v. als prominente heads-up
/// / lock-screen call-UI. Beide symptomen van build 1.0.21+23 (melding
/// niet prominent + opnemen-bij-dichte-app werkt niet) verdwijnen zodra
/// deze permission verleend is.
///
/// Wordt alleen relevant bij MELDINGEN-modus (ontvanger die gebeld wordt).
/// VERGRENDELDE modus draait de app altijd voorgrond met eigen inkomend-
/// gesprek-scherm; daar is de special-permission niet vereist.
///
/// Idempotent per app-start: [_promptGetoondDezeSessie] voorkomt dat de
/// gebruiker meerdere keren de dialog krijgt in dezelfde sessie. Bij een
/// volgende cold-start wordt opnieuw gecheckt.
class FullScreenIntentService {
  FullScreenIntentService._();

  static bool _promptGetoondDezeSessie = false;

  /// BEL-S3: publieke wrapper zodat een dev-diagnose-scherm een prompt
  /// kan forceren zonder de "1× per sessie"-guard te respecteren.
  /// Reset de flag én roept de standaard-check aan; als toestemming
  /// AL is gegeven toont hij (correct) niks — vandaar dat het
  /// diagnose-scherm ook `leesHuidigeStatus` aparte weergeeft.
  static Future<void> forceerPromptVoorTest(BuildContext context) async {
    _promptGetoondDezeSessie = false;
    await controleerEnPromptAlsNodig(context);
  }

  /// Check of de app de FULL_SCREEN_INTENT-special-permission heeft; als
  /// niet, toon een vriendelijke uitleg-dialog met knop om Android's
  /// instellingenpagina te openen.
  ///
  /// Fail-soft: elke fout (plugin-mismatch, oudere Android, geen context)
  /// → geen prompt, geen crash. Op API 33- geeft de plugin gewoonlijk
  /// `true` terug omdat de special-permission daar niet bestaat.
  ///
  /// Aanroepen vanuit de ontvanger-router zodra de weergaveModus op
  /// MELDINGEN staat en de callkit-flag aan is. Web is een no-op.
  static Future<void> controleerEnPromptAlsNodig(BuildContext context) async {
    if (kIsWeb) return;
    if (_promptGetoondDezeSessie) return;
    try {
      // BEL-S1: callkit-flag-gate WEG. USE_FULL_SCREEN_INTENT (Android 14+)
      // is óók vereist voor Optie A: de lokale-notificatie-flow zet
      // `fullScreenIntent: true` op de heads-up-melding bij dichte app
      // (push_service.dart:915). Zonder de special-permission degradeert
      // Android die notificatie naar een gewone melding tussen de andere
      // meldingen — geen belgeluid, niet prominent. De prompt moet dus
      // triggeren ongeacht Optie A/B.
      final resultaat = await FlutterCallkitIncoming.canUseFullScreenIntent();
      // BEL-S3: fail-CLOSED. Voorheen behandelden we "alles behalve
      // expliciet false" als toegestaan — dat verborg problemen waarbij
      // de plugin een niet-bool teruggaf (null, exception via return) en
      // de prompt stil oversloeg. Nu tellen we alleen `resultaat == true`
      // (letterlijk true) als "toestemming aanwezig". Alles anders (null,
      // false, string, error) → toon de prompt zodat de gebruiker of
      // toestemming kan geven, of via de dev-diagnose kan zien dat er
      // iets misgaat.
      final magGebruiken = resultaat == true;
      debugPrint('☎️ BEL-Q2: canUseFullScreenIntent=$resultaat '
          '(type=${resultaat.runtimeType} → magGebruiken=$magGebruiken)');
      if (magGebruiken) return;
      if (!context.mounted) return;
      _promptGetoondDezeSessie = true;
      await _toonPrompt(context);
    } catch (e, st) {
      debugPrint('⚠️ BEL-Q2: check faalde (skip prompt): $e\n$st');
    }
  }

  /// BEL-S3: reset de "1× per sessie"-guard zodat de dev-diagnose-knop
  /// ("Prompt forceren") de prompt opnieuw kan tonen zonder app-restart.
  /// Bewust NIET automatisch aangeroepen — het is puur een dev-utility.
  static void resetGuardVoorTest() {
    _promptGetoondDezeSessie = false;
  }

  /// BEL-S3: leest de huidige FSI-status van de plugin zodat het
  /// diagnose-scherm ("AAN/UIT") kan tonen zonder de prompt te triggeren.
  /// Wraps de raw plugin-call zodat callers een schone `bool?` krijgen
  /// (null = kon niet bepalen; true/false = actuele status).
  static Future<bool?> leesHuidigeStatus() async {
    if (kIsWeb) return null;
    try {
      final r = await FlutterCallkitIncoming.canUseFullScreenIntent();
      if (r is bool) return r;
      return null;
    } catch (e) {
      debugPrint('⚠️ BEL-S3: leesHuidigeStatus faalde: $e');
      return null;
    }
  }
}

  /// Toont de dementie-vriendelijke uitleg-dialog. Twee knoppen:
  ///   - 'Toestemming geven'  → opent Android-instellingenpagina
  ///   - 'Later'              → sluit dialog zonder actie
  /// Tekst bewust warm en zonder jargon; de doelgroep is familie
  /// (Nederlands, niet-technisch).
  static Future<void> _toonPrompt(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: kCream,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Eén kleine instelling nog',
            style: TextStyle(color: kBrown,
                fontSize: 22, fontWeight: FontWeight.w900)),
        content: const Text(
          'Om videogesprekken goed te laten verschijnen, mag Ons Moment '
          '"over je scherm tonen". Zo komt een bel meteen groot in beeld — '
          'ook als de telefoon vergrendeld is.\n\n'
          'Zonder deze instelling komt de bel als gewone melding en zie je '
          'hem gemakkelijk over het hoofd.',
          style: TextStyle(color: kBrown, fontSize: 16, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            style: TextButton.styleFrom(foregroundColor: kBrownLight),
            child: const Text('Later',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              try {
                await FlutterCallkitIncoming.requestFullIntentPermission();
                debugPrint('☎️ BEL-Q2: requestFullIntentPermission verzonden');
              } catch (e) {
                debugPrint('⚠️ BEL-Q2: request faalde: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kPeach,
              foregroundColor: kWhite,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Toestemming geven',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
