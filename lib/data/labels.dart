/// Labels voor de ontvanger. Pure functies — geen state, geen imports.
/// De accountType-parameter is bewaard voor backwards-compatibility met
/// bestaande callers; sinds 1.1n-1 wordt 'ie genegeerd (app is familie-only).

/// Zelfst. naamwoord voor de ontvanger.
String dierbareLabel(String? accountType) => 'dierbare';

/// Echte naam als die er is, anders "je dierbare".
String dierbareNaamLabel(String? accountType, String? naam) {
  if (naam != null && naam.trim().isNotEmpty) return naam.trim();
  return 'je dierbare';
}

/// Bezittelijke variant: "je dierbare" (zonder naam-voorrang).
String jeDierbareLabel(String? accountType) => 'je dierbare';
