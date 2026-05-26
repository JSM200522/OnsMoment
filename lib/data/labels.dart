/// Context-afhankelijke labels op basis van het account-type ('familie' of
/// 'zorg'). Wordt vanaf T4-T5 gebruikt om teksten passend te maken voor zowel
/// familieleden als zorgverleners. Pure functies — geen state, geen imports.

/// Zelfst. naamwoord voor de ontvanger, afhankelijk van account-type.
String dierbareLabel(String? accountType) =>
    accountType == 'zorg' ? 'cliënt' : 'dierbare';

/// Echte naam als die er is, anders "je cliënt"/"je dierbare".
String dierbareNaamLabel(String? accountType, String? naam) {
  if (naam != null && naam.trim().isNotEmpty) return naam.trim();
  return accountType == 'zorg' ? 'je cliënt' : 'je dierbare';
}

/// Bezittelijke variant: "je cliënt" / "je dierbare" (zonder naam-voorrang).
String jeDierbareLabel(String? accountType) =>
    accountType == 'zorg' ? 'je cliënt' : 'je dierbare';
