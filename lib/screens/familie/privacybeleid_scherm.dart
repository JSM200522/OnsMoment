import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/kleuren.dart';
import '../../widgets/normaal_scaffold.dart';

/// Privacybeleid-scherm — bereikbaar via Instellingen → "Privacybeleid".
///
/// **VOOR JOSHUA — hier plaats je de definitieve, juridisch gecheckte
/// tekst zodra die klaar is:**
///
/// 1. Vervang `_privacybeleidTekstConcept` hieronder door de definitieve
///    tekst (blijft String; formatting via `\n\n` voor paragrafen en
///    `#H1 ` / `##H2 ` prefix-conventies die door `_bouwParagrafen`
///    herkend worden — of vervang die helper door een Markdown-renderer).
/// 2. Zet `_privacybeleidStatus` op `'definitief'` (concept-banner
///    verdwijnt dan automatisch).
/// 3. Update `_laatstBijgewerkt` naar de datum van juridische goedkeuring.
/// 4. Zet de definitieve tekst ook op onsmoment.app/privacy — de
///    URL-versie is verplicht voor de Play Store-listing (Data safety
///    tab → Privacy policy URL). Zorg dat beide teksten identiek zijn
///    (of laat de app-versie linken naar de web-versie via de knop
///    onderaan).
///
/// De tekst hieronder is een PLAATSHOUDER om de UI-structuur te
/// bouwen en te testen. Communiceer 'm NIET als officieel beleid.

const String _privacybeleidStatus = 'concept';
const String _laatstBijgewerkt = '12 september 2026';
const String _privacybeleidWebUrl = 'https://onsmoment.app/privacy';

const String _privacybeleidTekstConcept = '''
[Deze tekst is een concept en heeft nog geen juridische controle gehad.
Vervang door de definitieve tekst voordat je de app publiek maakt.]

# Wie zijn wij

Ons Moment is een app om op afstand verbonden te blijven met een
dierbare die dementie, verstandelijke beperking of ernstige
vergeetachtigheid heeft. De app wordt gemaakt door JS Milhous
(KVK 94498695) in Nederland.

# Welke gegevens verwerken wij

Om Ons Moment te laten werken bewaren wij:
- Je e-mailadres en wachtwoord (voor het inloggen)
- De namen die je invult (jouw naam, de naam van je dierbare, andere
  kringleden)
- De foto's, video's, spraakberichten, liedjes en teksten die jij
  bewust deelt in je kring
- Notities die je met andere familieleden deelt
- Informatie over jouw apparaten (type, taal, hoe vaak je de app
  gebruikt) zodat meldingen aan het juiste toestel worden bezorgd

Wij verzamelen géén advertentie-ID, geen locatie, geen gezondheids-
gegevens buiten wat jij zelf typt in een bericht.

# Wie kan bij jouw gegevens

Alleen de leden van jouw kring kunnen jouw foto's, berichten en
gesprekken zien. Iemand die niet is uitgenodigd in jouw kring krijgt
geen toegang.

Onze servers draaien in de Europese Unie (België). Voor het versturen
van videogesprekken gebruiken wij een Europese partner (LiveKit); wij
bewaren geen video-of-audio-opnames van deze gesprekken.

# Jouw rechten

Je hebt het recht om:
- Jouw gegevens in te zien
- Jouw gegevens te corrigeren
- Jouw account en alle bijbehorende gegevens te laten verwijderen
- Bezwaar te maken tegen onze verwerking

Neem hiervoor contact op via info@onsmoment.app.

# Contact

Vragen over dit privacybeleid? Mail naar info@onsmoment.app.

Laatst bijgewerkt: $_laatstBijgewerkt
''';

class PrivacybeleidScherm extends StatelessWidget {
  const PrivacybeleidScherm({super.key});

  @override
  Widget build(BuildContext context) {
    return NormaalScaffold(
      backgroundColor: kCream,
      appBar: AppBar(
        title: const Text('Privacybeleid',
            style: TextStyle(fontWeight: FontWeight.w800, color: kBrown)),
        backgroundColor: kCream,
        elevation: 0,
        iconTheme: const IconThemeData(color: kBrown),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_privacybeleidStatus == 'concept') _conceptBanner(),
            _samenvattingsBlok(),
            ..._bouwParagrafen(_privacybeleidTekstConcept),
            const SizedBox(height: 24),
            _webVersieKnop(context),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _conceptBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kPeachPale,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kPeach, width: 1.5),
      ),
      child: Row(children: [
        const Text('⚠️', style: TextStyle(fontSize: 24)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Deze tekst is een concept en heeft nog geen '
            'juridische controle gehad. De definitieve versie volgt.',
            style: TextStyle(
                color: kBrown, fontSize: 13, height: 1.4,
                fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }

  /// Warm samenvattings-blok bovenaan — geeft de gebruiker in één
  /// oogopslag het geruststellende beeld voordat de formele tekst begint.
  /// In merkstijl (kPeachPale + kPeach-rand + kBrown-tekst).
  Widget _samenvattingsBlok() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kPeachPale,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kPeach, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Jouw privacy is veilig bij ons',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900,
                  color: kBrown, height: 1.2)),
          const SizedBox(height: 12),
          const Text(
            'Ons Moment is een besloten plek, alleen voor jouw kring. '
            'Alleen de mensen die jij uitnodigt kunnen de foto\'s, '
            'berichten en gesprekken zien.',
            style: TextStyle(fontSize: 14, color: kBrown, height: 1.5),
          ),
          const SizedBox(height: 12),
          _samenvattingRegel(
              'Al je gegevens staan veilig versleuteld, op beveiligde '
              'servers in Europa.'),
          _samenvattingRegel('Geen advertenties. Nooit.'),
          _samenvattingRegel(
              'Alleen jij beheert wie er in je kring zit.'),
          const SizedBox(height: 12),
          const Text('Kleine momenten, veilig gedeeld.',
              style: TextStyle(fontSize: 14, color: kBrown,
                  fontWeight: FontWeight.w800, height: 1.4,
                  fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _samenvattingRegel(String tekst) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(top: 3, right: 10),
          child: Icon(Icons.check_circle, color: kPeach, size: 18),
        ),
        Expanded(
          child: Text(tekst,
              style: const TextStyle(fontSize: 14, color: kBrown,
                  height: 1.45)),
        ),
      ]),
    );
  }

  /// Simpele paragraaf-renderer voor de placeholder-tekst. Herkent
  /// `# H1 ` en `## H2 ` als kopjes; alle andere regels als paragraaf.
  /// Vervang deze functie door een echte Markdown-renderer als je meer
  /// opmaak nodig hebt (bijv. `flutter_markdown`).
  List<Widget> _bouwParagrafen(String tekst) {
    final regels = tekst.split('\n');
    final widgets = <Widget>[];
    var paragraafBuffer = <String>[];

    void spoelParagraaf() {
      if (paragraafBuffer.isEmpty) return;
      final samen = paragraafBuffer.join('\n').trim();
      if (samen.isNotEmpty) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(samen,
              style: const TextStyle(fontSize: 14,
                  color: kBrownLight, height: 1.55)),
        ));
      }
      paragraafBuffer = <String>[];
    }

    for (final r in regels) {
      final t = r.trimRight();
      if (t.startsWith('# ')) {
        spoelParagraaf();
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(t.substring(2),
              style: const TextStyle(fontSize: 20,
                  fontWeight: FontWeight.w900, color: kBrown)),
        ));
      } else if (t.startsWith('## ')) {
        spoelParagraaf();
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Text(t.substring(3),
              style: const TextStyle(fontSize: 16,
                  fontWeight: FontWeight.w800, color: kBrown)),
        ));
      } else if (t.isEmpty) {
        spoelParagraaf();
      } else {
        paragraafBuffer.add(t);
      }
    }
    spoelParagraaf();
    return widgets;
  }

  Widget _webVersieKnop(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () async {
          final uri = Uri.parse(_privacybeleidWebUrl);
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Kon $_privacybeleidWebUrl niet openen'),
                backgroundColor: kRood));
            }
          }
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: kBrown,
          side: const BorderSide(color: kPeach, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        child: const Text('Bekijk op onsmoment.app',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      ),
    );
  }
}
