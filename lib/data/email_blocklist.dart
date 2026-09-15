/// E-mail-domein blocklist voor signup-flows.
///
/// Aanleiding (14 sept 2026): ZeptoMail meldde 16 hard bounces uit 16
/// verstuurde verificatie-mails (100% bounce-ratio) → account-suspensie-
/// waarschuwing. Root cause: test-accounts met adressen op niet-
/// bestaande domeinen (test.nl, example.com etc.) waarnaar Firebase Auth
/// verificatie-mails stuurde. Elke bounce beschadigt de afzender-
/// reputatie van noreply@onsmoment.app en de aflevering van ECHTE
/// verificatie-mails bij Gmail/Outlook straks.
///
/// Aanpak: signup-flows weren registraties met een handjevol duidelijk-
/// nep domeinen. Firebase Auth zelf valideert alleen email-syntax
/// (`local@domain`), doet géén MX-lookup of bestaans-check.
///
/// Bewuste keuzes:
/// - Kort lijstje. Community-repo's zoals disposable-email-domains
///   hebben ~4000 domeinen — overkill voor onze doelgroep. Onze doel-
///   groep is Nederlandse familie voor dementie-zorg; die gebruikt
///   Gmail/Outlook/eigen provider. Test-domeinen zijn de risico's.
/// - Client-side check: matcht wat de user in de setup-wizard invult.
///   Server-side kan dit later via een Cloud Function beforeCreate-
///   blocking-trigger (Firebase Auth 5.x) worden verstevigd — dan
///   is de check ook bestand tegen een uitbuiter die de client omzeilt.
///   Zolang de app niet publiek in Play staat is client-side voldoende.
/// - Case-insensitief. Whitespace-strip. Alleen exacte-domein-match
///   (@test.nl blokkeert, my-test.nl niet).
const Set<String> geblokkeerdeEmailDomeinen = {
  'test.nl',
  'test.com',
  'test.local',
  'test.test',
  'example.com',
  'example.org',
  'example.net',
  'invalid',
  'localhost',
  // Klassieke wegwerp-services waar we geen echte gebruikers verwachten
  // en die reputatie-issues kunnen geven bij mail-providers:
  'mailinator.com',
  'tempmail.com',
  'guerrillamail.com',
  '10minutemail.com',
};

/// True als [email] een van de geblokkeerde test-/wegwerp-domeinen heeft.
/// Verwacht een reeds-getrimd + syntax-gevalideerd e-mailadres (zoals
/// bijvoorbeeld `_emailCtrl.text.trim()`). Bij ontbrekend '@' → false
/// (dan is er sowieso een andere validatie-fout).
bool isGeblokkeerdEmailDomein(String email) {
  final idx = email.lastIndexOf('@');
  if (idx < 0 || idx >= email.length - 1) return false;
  final domein = email.substring(idx + 1).toLowerCase().trim();
  return geblokkeerdeEmailDomeinen.contains(domein);
}
