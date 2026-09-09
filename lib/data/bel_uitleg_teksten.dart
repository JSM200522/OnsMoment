/// BEL-D3: éne bron van waarheid voor de uitleg over bellen aan de
/// eigenaarskant. Alle plekken (eerste-keer-dialog, "Hoe werkt bellen?"-
/// linkjes, FAQ-samenvatting, auto-answer-toggle-uitleg, overlay-stap in
/// de setup) lezen HIERUIT. Wijzig de tekst hier — het overige past
/// zichzelf automatisch aan.
///
/// Toon: kort, warm, gender-neutraal ("je dierbare"), zonder platform-
/// jargon (geen Android/iOS/Samsung). Kernboodschap die overal
/// terugkomt: in de RUSTIGE MODUS werkt bellen en automatisch opnemen
/// ALTIJD; in de GEWONE MODUS is één toestemming nodig voor automatisch
/// opnemen. Belangrijk: je belt altijd je dierbare — familieleden
/// onderling bellen kan niet.
class BelUitlegTeksten {
  BelUitlegTeksten._();

  /// Titel voor de dialog én voor de FAQ-samenvatting.
  static const String titel = 'Zo werkt bellen';

  /// De vier kernregels — de complete uitleg. Bewust ~5 korte regels,
  /// geen lappen tekst.
  static const List<String> punten = [
    'Gewoon bellen: je dierbare ziet een rinkelend scherm en neemt zelf op.',
    'Automatisch opnemen: het gesprek opent vanzelf na een korte '
        'waarschuwing — voor wie zelf niet kan opnemen. Zet je aan per kring.',
    'Rustige modus: het apparaat staat vast op Ons Moment. Bellen en '
        'automatisch opnemen werken hier altijd, zonder extra instellingen.',
    'Gewone modus + automatisch opnemen: hiervoor is één toestemming '
        'nodig op het apparaat van je dierbare ("weergeven over andere '
        'apps"). Die regel je tijdens het instellen.',
  ];

  /// Korte zin onder de auto-answer-schakelaar (BelApparaatKiesScherm).
  static const String autoAnswerToggleUitleg =
      'Werkt altijd in de rustige modus. In de gewone modus is één '
      'toestemming op het apparaat van je dierbare nodig — regel je bij '
      'het instellen.';

  /// Hint als de eigenaar auto-answer aanzet: mocht je dierbare op
  /// de gewone modus staan, dan is een toestemming nodig. We tonen dit
  /// altijd (we kunnen niet zien welke modus het andere apparaat heeft).
  static const String autoAnswerAangezetHint =
      'Aan het instellen? Kijk op het apparaat van je dierbare bij '
      'Instellingen → "Zo werkt bellen" of doe de toestemmingen-stap '
      'opnieuw.';

  /// Overlay-stap in de toestemmingen-setup: waarvoor + wat zonder gebeurt.
  static const String overlayWaarvoor =
      'Zodat een gesprek vanzelf kan openen, ook als je dierbare net iets '
      'anders op het scherm heeft.';
  static const String overlayZonder =
      'Zonder deze toestemming tikt je dierbare zelf op de melding.';

  /// Eén-zin waarheid over wie je kunt bellen. Gebruikt in het bel-
  /// apparaat-kies-scherm en in de FAQ zodat de belangrijke beperking
  /// (geen familieleden onderling) overal identiek geformuleerd is.
  static const String wieBelJe =
      'Je belt altijd je dierbare. Familieleden onderling bellen kan niet '
      '— Ons Moment is bedoeld voor contact met je dierbare.';

  /// Compact FAQ-antwoord dat exact dezelfde vier punten weergeeft, zodat
  /// een gebruiker die de FAQ inloopt dezelfde boodschap ziet als bij de
  /// eerste-keer-dialog. `const` zodat _FAQ 'm in een const-context kan
  /// gebruiken — daarom voluit opgeschreven i.p.v. via .join() te
  /// berekenen (methoden mogen niet in const-expressies).
  static const String faqSamenvatting =
      '• Gewoon bellen: je dierbare ziet een rinkelend scherm en neemt '
      'zelf op.\n\n'
      '• Automatisch opnemen: het gesprek opent vanzelf na een korte '
      'waarschuwing — voor wie zelf niet kan opnemen. Zet je aan per '
      'kring.\n\n'
      '• Rustige modus: het apparaat staat vast op Ons Moment. Bellen '
      'en automatisch opnemen werken hier altijd, zonder extra '
      'instellingen.\n\n'
      '• Gewone modus + automatisch opnemen: hiervoor is één '
      'toestemming nodig op het apparaat van je dierbare ("weergeven '
      'over andere apps"). Die regel je tijdens het instellen.';
}
