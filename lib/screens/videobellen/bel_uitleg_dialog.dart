import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/bel_uitleg_teksten.dart';
import '../../theme/kleuren.dart';

/// BEL-D3: warme dialog "Zo werkt bellen" die eigenaars zien:
///  - éénmalig bij de eerste tap op de bel-knop (via
///    [BelUitlegDialog.toonEersteKeer])
///  - altijd bij tik op de kleine "Hoe werkt bellen?"-linkjes (via
///    [BelUitlegDialog.forceerTonen])
///
/// Content komt uit [BelUitlegTeksten] — één bron van waarheid voor deze
/// dialog, de auto-answer-toggle-uitleg, de overlay-setup-stap en de
/// FAQ-samenvatting. Aanpassen aan één plek werkt overal door.
class BelUitlegDialog extends StatelessWidget {
  const BelUitlegDialog({super.key});

  /// SharedPreferences-sleutel. Blijft bewust op v1 tenzij we de content
  /// zo drastisch wijzigen dat bestaande gebruikers 'm opnieuw moeten
  /// zien; dan bumpen naar v2 en oude sleutel als opgeruimd beschouwen.
  static const String _kEersteKeerGezien = 'bel_uitleg_gezien_v1';

  /// Toont de dialog ALS de gebruiker deze nog niet eerder heeft gezien
  /// en zet vervolgens de "gezien"-vlag zodat een volgende belknop-tap
  /// direct doorgaat. Bij een prefs-fout fail-open: geen dialog, direct
  /// doorgaan (de belknop mag nooit blokkeren door UI-fluff).
  static Future<void> toonEersteKeer(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kEersteKeerGezien) == true) return;
      if (!context.mounted) return;
      await forceerTonen(context);
      await prefs.setBool(_kEersteKeerGezien, true);
    } catch (_) {
      // Fail-open — dialog is verrijkend maar niet-blokkerend.
    }
  }

  /// Toont de dialog ongeacht de "gezien"-vlag. Gebruikt door de
  /// "Hoe werkt bellen?"-linkjes.
  static Future<void> forceerTonen(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const BelUitlegDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kCream,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
      title: const Row(children: [
        Text('📞', style: TextStyle(fontSize: 22)),
        SizedBox(width: 10),
        Expanded(child: Text(BelUitlegTeksten.titel,
            style: TextStyle(fontSize: 20,
                fontWeight: FontWeight.w900, color: kBrown))),
      ]),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final punt in BelUitlegTeksten.punten) ...[
              _puntRegel(punt),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPeach,
              foregroundColor: kWhite,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Begrepen',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }

  Widget _puntRegel(String tekst) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('•', style: TextStyle(
            fontSize: 15, color: kPeach, fontWeight: FontWeight.w900)),
        const SizedBox(width: 8),
        Expanded(child: Text(tekst,
            style: const TextStyle(
                fontSize: 14, color: kBrown, height: 1.5))),
      ],
    );
  }
}

/// Kleine tekst-link "Hoe werkt bellen?" — bewust een `TextButton` met
/// onderlijning, klein en zonder achtergrond, zodat hij nergens de
/// primaire bel-knop overschaduwt.
class BelUitlegLink extends StatelessWidget {
  const BelUitlegLink({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => BelUitlegDialog.forceerTonen(context),
      icon: const Icon(Icons.help_outline_rounded, size: 16, color: kTextMuted),
      label: const Text('Hoe werkt bellen?',
          style: TextStyle(
              fontSize: 13,
              color: kTextMuted,
              decoration: TextDecoration.underline,
              fontWeight: FontWeight.w600)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
