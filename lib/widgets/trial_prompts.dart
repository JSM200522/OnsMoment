import 'package:flutter/material.dart';
import '../screens/familie/pakket_keuze_scherm.dart';
import '../services/trial_prompt_service.dart';
import '../theme/kleuren.dart';

/// FASE D-3 — warme, spaarzame conversie-momenten. Twee widgets:
///
///  * [TussentijdseNudgeSheet.toon] — na een verzonden moment,
///    max 1x per 3 dagen, alleen na waarde-ervaring.
///  * [TrialEindeKaart] — in-app kaart bij laatste dag / verlopen,
///    persistent zichtbaar zolang de fase actueel is.
///
/// Elk element heeft altijd een "Niet nu"-uitweg — nooit blokkerend,
/// nooit agressief. Framing: opgebouwde waarde + zachte "wat je zou
/// missen"-boodschap.

// ═════════════════════════════════════════════════════════════════
// 1) TUSSENTIJDSE NUDGE — bottom-sheet direct na moment-send
// ═════════════════════════════════════════════════════════════════

class TussentijdseNudgeSheet extends StatelessWidget {
  final TrialNudgeInfo info;
  const TussentijdseNudgeSheet({super.key, required this.info});

  /// Toont de sheet + markeert 'm als getoond in prefs (verlengt de
  /// 3-dagen-cap). Alleen aanroepen ná [TrialPromptService.magNudgeTonen]
  /// een niet-null resultaat gaf.
  static Future<void> toon(BuildContext context, TrialNudgeInfo info) async {
    await TrialPromptService.markeerNudgeGetoond();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => TussentijdseNudgeSheet(info: info),
    );
  }

  @override
  Widget build(BuildContext context) {
    final naam = (info.kringNaam ?? '').trim().isEmpty
        ? 'je dierbare'
        : info.kringNaam!.trim();
    final dagenTekst = info.dagenResterend == 1
        ? '1 gratis dag'
        : '${info.dagenResterend} gratis dagen';
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: kCream,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
          decoration: BoxDecoration(color: kPeachLight,
              borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        const Text('💛', style: TextStyle(fontSize: 36)),
        const SizedBox(height: 8),
        Text('Al ${info.momentenTotaal} momenten gedeeld',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20,
                fontWeight: FontWeight.w900, color: kBrown)),
        const SizedBox(height: 10),
        Text(
          'Wat een schat aan warme berichtjes stuur je naar $naam. '
          'Wil je verbonden blijven? Je hebt nog $dagenTekst.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14,
              color: kBrown, height: 1.45)),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, child: GestureDetector(
          onTap: () {
            Navigator.of(context).pop();
            PakketKeuzeScherm.toon(context);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(color: kPeach,
                borderRadius: BorderRadius.circular(14)),
            child: const Center(child: Text('Bekijk pakketten',
                style: TextStyle(fontSize: 15,
                    fontWeight: FontWeight.w900, color: kWhite))),
          ),
        )),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Niet nu',
              style: TextStyle(fontSize: 14,
                  color: kTextMuted, fontWeight: FontWeight.w700))),
        const SizedBox(height: 4),
        const Text(
          'Geen verplichtingen. Doe je niets, dan stopt het vanzelf.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: kTextMuted)),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// 2) LAATSTE DAG / VERLOPEN — persistente in-app kaart
// ═════════════════════════════════════════════════════════════════

/// Warme kaart voor de eind-fases (laatste dag + verlopen). Toont
/// zichzelf zolang de fase actueel is; caller (FamilieScherm) beslist
/// waar hij komt te staan.
///
/// De caller haalt zelf de [TrialContext] op via
/// [TrialPromptService.haalContext] en filtert op fase — deze widget
/// rendert alleen als de fase past.
class TrialEindeKaart extends StatelessWidget {
  final TrialContext context;

  /// Aantal momenten dat de user tijdens deze proef heeft verzonden
  /// (uit [TrialPromptService.aantalMomentenVerzonden]). Wordt in de
  /// tekst gebruikt om de opgebouwde waarde te tonen.
  final int momentenTotaal;

  const TrialEindeKaart({
    super.key,
    required this.context,
    required this.momentenTotaal,
  });

  bool get magTonen =>
      context.fase == TrialFase.laatsteDag ||
      context.fase == TrialFase.verlopen;

  @override
  Widget build(BuildContext buildContext) {
    if (!magTonen) return const SizedBox.shrink();
    final naam = (context.kringNaam ?? '').trim().isEmpty
        ? 'je dierbare'
        : context.kringNaam!.trim();
    final isVerlopen = context.fase == TrialFase.verlopen;
    final titel = isVerlopen
        ? 'Je gratis periode is voorbij'
        : 'Morgen eindigt je gratis periode';
    final emoji = isVerlopen ? '⏰' : '⏳';
    final randKleur = isVerlopen ? kRood : kPeach;
    final momentenZin = momentenTotaal > 0
        ? 'Je deelde al $momentenTotaal ${momentenTotaal == 1 ? "moment" : "momenten"} met $naam.'
        : '';
    final hoofdTekst = isVerlopen
        ? [
            'Je gratis periode van 14 dagen is voorbij.',
            if (momentenZin.isNotEmpty) momentenZin,
            'Kies een pakket om $naam elke dag een klein moment '
                'te blijven sturen.',
          ].join(' ')
        : [
            'Morgen eindigt je gratis periode.',
            if (momentenZin.isNotEmpty) momentenZin,
            'Wil je $naam elke dag een klein moment blijven sturen? '
                'Kies een pakket om door te gaan.',
          ].join(' ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: kWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: randKleur, width: 2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(child: Text(titel,
                style: const TextStyle(fontSize: 15,
                    fontWeight: FontWeight.w900, color: kBrown))),
          ]),
          const SizedBox(height: 8),
          Text(hoofdTekst,
              style: const TextStyle(fontSize: 13,
                  color: kBrown, height: 1.5)),
          const SizedBox(height: 10),
          const Text(
            'Doe je niets, dan stopt het vanzelf — je betaalt niets.',
            style: TextStyle(fontSize: 11,
                color: kTextMuted, height: 1.4,
                fontStyle: FontStyle.italic)),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: GestureDetector(
            onTap: () => PakketKeuzeScherm.toon(buildContext),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: kPeach,
                  borderRadius: BorderRadius.circular(12)),
              child: const Center(child: Text('Bekijk pakketten',
                  style: TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w900, color: kWhite))),
            ),
          )),
        ]),
    );
  }
}
