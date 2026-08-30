/// Data-model voor de V9 uitnodig-flow (2.5).
///
/// Een uitnodiging bestaat uit één raw token (Firestore doc-id, 20 chars)
/// dat als doc-id in uitnodig_tokens/{token} staat en als veld
/// uitnodigToken op het bijbehorende kring-doc. Tokens zijn herbruikbaar
/// (WhatsApp-stijl groepslink) — de natuurlijke rem is de kring-limiet
/// uit het tier-model (klein: 8, groot: 20).

class Uitnodiging {
  /// Raw token (20 chars, alfanumeriek, gelijk aan doc-id van
  /// uitnodig_tokens/{...}). Gebruiken voor alle Firestore-paden.
  final String token;

  /// Display-versie met streepjes voor leesbaarheid en overtypbaarheid,
  /// bv. 'aB3c-D4eF-5gH6-iJ7k-lM8n'. Toonbaar in UI.
  final String displayToken;

  final String kringId;
  final String kringNaam;
  final String? kringFoto;

  /// Naam van wie de uitnodiging genereerde (uit gebruikers/{uid}.familieNaam).
  /// Kan null zijn als de uitnodiger-doc niet meer bestaat of de naam leeg is.
  final String? uitnodigerNaam;

  /// Huidige ledental in de kring (telling op moment van valideer).
  final int huidigeLeden;

  /// Maximum-aantal leden op basis van het tier van de eigenaar
  /// (klein: 8, groot: 20).
  final int maxLeden;

  const Uitnodiging({
    required this.token,
    required this.displayToken,
    required this.kringId,
    required this.kringNaam,
    this.kringFoto,
    this.uitnodigerNaam,
    required this.huidigeLeden,
    required this.maxLeden,
  });

  bool get ruimte => huidigeLeden < maxLeden;
  int get plekkenOver => (maxLeden - huidigeLeden).clamp(0, maxLeden);
}

/// Foutreden voor valideer- en accepteer-flows. Gemeenschappelijk zodat
/// UI één switch-statement kan gebruiken.
enum UitnodigingFout {
  /// Token-doc bestaat niet in uitnodig_tokens (verkeerd getypt of
  /// ingetrokken).
  notFound,

  /// Token wijst naar een kring-doc dat niet meer bestaat (zeldzaam:
  /// kring verwijderd terwijl token nog leeft).
  kringNotFound,

  /// Kring zit aan z'n maximum-ledental — accepteer wordt geweigerd
  /// (race-window: kan ook tijdens accept ontstaan als iemand anders
  /// net joinde; valideer zelf is meestal optimistischer).
  kringVol,

  /// Gebruiker is al lid van deze kring; opnieuw accepteren is een no-op.
  alLid,

  /// Firestore weigert de write (rule-mismatch, veld-eis niet gehaald).
  /// Zeldzaam na strip van accepteer(); toont een neutrale melding zodat
  /// de gebruiker weet dat het niet aan het netwerk lag.
  permissionGeweigerd,

  /// Echte netwerk-/serverfout (offline, timeout, unavailable).
  netwerk,
}
