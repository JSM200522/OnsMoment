import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../data/debug_flags.dart';
import '../../services/purchases_service.dart';
import '../../theme/kleuren.dart';

/// Conventie voor package-identifiers in de RevenueCat "current"-offering.
/// Joshua zet deze bij het aanmaken van packages in RevenueCat exact
/// zo — kleine-letters, onderstrepen. Zonder deze conventie kan
/// [_PakketKeuzeSchermState._koopTier] de juiste Package niet vinden en
/// valt de koop-knop stil terug op "Momenteel niet beschikbaar".
///
/// Mapping tier×periode → identifier:
///   klein + maand  → 'klein_maand'
///   klein + jaar   → 'klein_jaar'
///   groot + maand  → 'groot_maand'
///   groot + jaar   → 'groot_jaar'
String _pakketId(String tier, {required bool jaar}) =>
    '${tier}_${jaar ? 'jaar' : 'maand'}';

/// Toont proefperiode-teller, maand/jaar-toggle en twee pakketten met
/// warme per-persoon-framing. Alleen aanroepen vanuit eigenaar-context.
class PakketKeuzeScherm extends StatefulWidget {
  const PakketKeuzeScherm({super.key});

  static Future<void> toon(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => const PakketKeuzeScherm(),
      );

  @override
  State<PakketKeuzeScherm> createState() => _PakketKeuzeSchermState();
}

class _PakketKeuzeSchermState extends State<PakketKeuzeScherm> {
  static const int _proefDagen = 14;
  bool _jaarModus = false;
  int? _dagenResterend; // null = proefStart onbekend (bestaand account)
  bool _geladen = false;

  // D-2E paywall live-mode state. Alleen relevant als
  // DEBUG_PAYWALL_LIVE=true; anders blijven deze velden ongebruikt en
  // toont _betaalKnop het originele placeholder.
  Offering? _offering;
  bool _offeringGeladen = false;
  bool _bezigKopen = false;

  @override
  void initState() {
    super.initState();
    _laadProefStart();
    if (DEBUG_PAYWALL_LIVE) _laadOffering();
  }

  /// D-2E: haalt de RevenueCat "current"-offering op zodra het scherm
  /// opent. No-op als SDK niet configured (lege API-key) — dan blijft
  /// _offering null en toont [_betaalKnopLive] "Momenteel niet
  /// beschikbaar".
  Future<void> _laadOffering() async {
    final offering = await PurchasesService.haalCurrentOffering();
    if (!mounted) return;
    setState(() {
      _offering = offering;
      _offeringGeladen = true;
    });
  }

  /// D-2E: zoekt de Package voor het gegeven tier + de huidige toggle
  /// en start de koop-flow. Play/App Store toont zelf de betaal-UI.
  /// Bij succes sluit de sheet en de webhook doet de tier-schrijf.
  Future<void> _koopTier(String tier) async {
    if (_bezigKopen) return;
    final offering = _offering;
    if (offering == null) return;
    final gewenstId = _pakketId(tier, jaar: _jaarModus);
    Package? gekozen;
    for (final p in offering.availablePackages) {
      if (p.identifier == gewenstId) {
        gekozen = p;
        break;
      }
    }
    if (gekozen == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Pakket "$gewenstId" is nog niet beschikbaar. '
            'Probeer het straks opnieuw.'),
        backgroundColor: kRood));
      return;
    }
    setState(() => _bezigKopen = true);
    final result = await PurchasesService.koop(gekozen);
    if (!mounted) return;
    setState(() => _bezigKopen = false);
    if (result != null) {
      final actief = PurchasesService.tierUitCustomerInfo(result);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(actief != null
            ? 'Gelukt — je bent nu op pakket "${actief.toUpperCase()}".'
            : 'Aankoop verwerkt. Het kan even duren voor je nieuwe '
                'status zichtbaar is.'),
        backgroundColor: kGreen));
      Navigator.of(context).maybePop();
    }
    // result == null bij annulering of fout — service heeft al
    // debugPrint gedaan; geen aparte user-melding nodig (Play toont
    // eigen fout-UI).
  }

  Future<void> _laadProefStart() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _geladen = true);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('gebruikers')
          .doc(uid)
          .get();
      final proefStart =
          (doc.data()?['proefStart'] as Timestamp?)?.toDate();
      if (mounted) {
        if (proefStart != null) {
          final verstreken =
              DateTime.now().difference(proefStart).inDays;
          _dagenResterend =
              (_proefDagen - verstreken).clamp(0, _proefDagen);
        }
        _geladen = true;
        setState(() {});
      }
    } catch (_) {
      if (mounted) setState(() => _geladen = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: kCream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          _dragHandle(),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                _header(),
                const SizedBox(height: 20),
                _geladen ? _proefBanner() : _laadindicator(),
                const SizedBox(height: 24),
                _toggle(),
                const SizedBox(height: 20),
                _pakketKaart(
                  label: 'FAMILIE KLEIN',
                  maandPrijs: '€4,99',
                  jaarPrijs: '€35,99',
                  jaarBesparing: 'Was €59,88/jaar — bespaar €23,89',
                  ondertitel:
                      'Perfect voor één warme kring rondom vader, '
                      'moeder of opa en oma.',
                  perPersoonMaand:
                      'De rest van de familie nodig je gratis uit. '
                      'Met 8 deelnemers: €0,62 per persoon per maand.',
                  perPersoonJaar:
                      'De rest van de familie nodig je gratis uit. '
                      'Met 8 deelnemers: €4,50 per persoon per jaar.',
                  kenmerken: const [
                    '1 kring',
                    'Max 8 kringleden',
                    '5 berichttypen',
                  ],
                  isUitgelicht: false,
                ),
                const SizedBox(height: 12),
                _pakketKaart(
                  label: 'FAMILIE GROOT',
                  maandPrijs: '€7,99',
                  jaarPrijs: '€57,99',
                  jaarBesparing: 'Was €95,88/jaar — bespaar €37,89',
                  ondertitel:
                      'Ideaal als je meerdere kringen wilt, '
                      'bijvoorbeeld voor zowel je ouders als schoonouders.',
                  perPersoonMaand:
                      'De rest nodig je gratis uit, dus met 60 deelnemers '
                      'komt het praktisch neer op €0,13 per persoon per maand.',
                  perPersoonJaar:
                      'De rest nodig je gratis uit, dus met 60 deelnemers: '
                      '€0,97 per persoon per jaar.',
                  kenmerken: const [
                    'Max 3 kringen',
                    'Max 20 kringleden per kring',
                    '5 berichttypen',
                  ],
                  isUitgelicht: true,
                ),
                const SizedBox(height: 28),
                _betaalKnop(),
                const SizedBox(height: 12),
                const Center(
                  child: Text(
                    'Geen verplichtingen. Doe je niets, dan stopt het vanzelf.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, color: kTextMuted, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _dragHandle() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
              color: kPeachLight,
              borderRadius: BorderRadius.circular(2)),
        ),
      );

  Widget _header() => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('💛 Jouw abonnement',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: kBrown)),
          SizedBox(height: 4),
          Text(
            'Eén eigenaar betaalt — de rest doet gratis mee.',
            style: TextStyle(
                fontSize: 14, color: kTextMuted, height: 1.4),
          ),
        ],
      );

  Widget _laadindicator() => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: CircularProgressIndicator(
              color: kPeach, strokeWidth: 3),
        ),
      );

  Widget _proefBanner() {
    if (_dagenResterend == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kPeachPale,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kPeachLight, width: 1.5),
        ),
        child: const Row(children: [
          Text('💛', style: TextStyle(fontSize: 20)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Kies een pakket om Ons Moment te blijven gebruiken.',
              style: TextStyle(
                  fontSize: 14,
                  color: kBrown,
                  height: 1.4,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      );
    }

    final resterend = _dagenResterend!;
    final voortgang = resterend / _proefDagen;
    final urgentie = resterend <= 3;
    final kleur = urgentie ? kRood : kGreen;

    final String bannerTekst;
    if (resterend <= 0) {
      bannerTekst = 'Je gratis proefperiode is afgelopen.';
    } else if (resterend == 1) {
      bannerTekst = 'Je hebt nog 1 van je 14 gratis dagen.';
    } else {
      bannerTekst = 'Je hebt nog $resterend van je 14 gratis dagen.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kPeachPale,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: urgentie ? kRood.withOpacity(0.3) : kPeachLight,
            width: 1.5),
      ),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(resterend <= 0 ? '⏰' : '⏳',
              style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(bannerTekst,
                style: const TextStyle(
                    fontSize: 14,
                    color: kBrown,
                    fontWeight: FontWeight.w800,
                    height: 1.3)),
          ),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: voortgang.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: kPeachLight,
            valueColor: AlwaysStoppedAnimation<Color>(kleur),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          resterend <= 0
              ? 'Proefperiode voorbij'
              : '$resterend ${resterend == 1 ? 'dag' : 'dagen'} resterend',
          style: const TextStyle(fontSize: 11, color: kTextMuted),
        ),
      ]),
    );
  }

  Widget _toggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: kPeachLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Expanded(
          child: _toggleOptie('Per maand',
              isActief: !_jaarModus,
              onTap: () => setState(() => _jaarModus = false)),
        ),
        Expanded(
          child: _toggleOptie('Per jaar',
              isActief: _jaarModus,
              badge: '−40%',
              onTap: () => setState(() => _jaarModus = true)),
        ),
      ]),
    );
  }

  Widget _toggleOptie(String tekst,
      {required bool isActief,
      String? badge,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActief ? kWhite : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: isActief
              ? [
                  BoxShadow(
                      color: kPeach.withOpacity(0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2))
                ]
              : [],
        ),
        child: Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(tekst,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isActief ? kBrown : kTextMuted)),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: kGreen,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(badge,
                    style: const TextStyle(
                        fontSize: 10,
                        color: kWhite,
                        fontWeight: FontWeight.w900)),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _pakketKaart({
    required String label,
    required String maandPrijs,
    required String jaarPrijs,
    required String jaarBesparing,
    required String ondertitel,
    required String perPersoonMaand,
    required String perPersoonJaar,
    required List<String> kenmerken,
    required bool isUitgelicht,
  }) {
    final prijs = _jaarModus ? jaarPrijs : maandPrijs;
    final periode = _jaarModus ? 'per jaar' : 'per maand';
    final perPersoon = _jaarModus ? perPersoonJaar : perPersoonMaand;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isUitgelicht ? kPeach : kPeachLight,
          width: isUitgelicht ? 2.5 : 1.5,
        ),
        boxShadow: isUitgelicht
            ? [
                BoxShadow(
                    color: kPeach.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 6))
              ]
            : [],
      ),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: kTextMuted,
                    letterSpacing: 0.8)),
          ),
          if (isUitgelicht)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: kPeach,
                  borderRadius: BorderRadius.circular(8)),
              child: const Text('Meest gekozen',
                  style: TextStyle(
                      fontSize: 10,
                      color: kWhite,
                      fontWeight: FontWeight.w900)),
            ),
        ]),
        const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(prijs,
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: kBrown)),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(periode,
                style: const TextStyle(
                    fontSize: 13, color: kTextMuted)),
          ),
        ]),
        if (_jaarModus) ...[
          const SizedBox(height: 2),
          Text(jaarBesparing,
              style: const TextStyle(
                  fontSize: 11,
                  color: kGreen,
                  fontWeight: FontWeight.w700)),
        ],
        const SizedBox(height: 10),
        Text(ondertitel,
            style: const TextStyle(
                fontSize: 14, color: kBrown, height: 1.5)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: kPeachPale,
              borderRadius: BorderRadius.circular(10)),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            const Text('👥 Alleen jij als eigenaar betaalt.',
                style: TextStyle(
                    fontSize: 13,
                    color: kBrown,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(perPersoon,
                style: const TextStyle(
                    fontSize: 13,
                    color: kBrownLight,
                    height: 1.4)),
          ]),
        ),
        const SizedBox(height: 12),
        ...kenmerken.map((k) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded,
                    color: kGreen, size: 16),
                const SizedBox(width: 8),
                Text(k,
                    style: const TextStyle(
                        fontSize: 13, color: kBrownLight)),
              ]),
            )),
      ]),
    );
  }

  Widget _betaalKnop() =>
      DEBUG_PAYWALL_LIVE ? _betaalKnopLive() : _betaalKnopPlaceholder();

  /// Origineel placeholder — actief zolang DEBUG_PAYWALL_LIVE=false.
  /// De betaal-flow is nog niet klaar voor productie (wacht op Play
  /// Console-abonnementen + sandbox-test), dus knop blijft disabled.
  Widget _betaalKnopPlaceholder() => Opacity(
        opacity: 0.5,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
              color: kBrownLight,
              borderRadius: BorderRadius.circular(16)),
          child: const Center(
            child: Text('Betaaloptie volgt binnenkort',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: kWhite)),
          ),
        ),
      );

  /// D-2E live-modus. Toont twee knoppen (Klein / Groot), elk gekoppeld
  /// aan het pakket dat matcht met de huidige jaar/maand-toggle. Bij
  /// tap → Purchases.purchase → Play/App Store dialog.
  Widget _betaalKnopLive() {
    if (!_offeringGeladen) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child:
            CircularProgressIndicator(color: kPeach, strokeWidth: 3)),
      );
    }
    if (_offering == null || _offering!.availablePackages.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kPeachPale,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kPeachLight, width: 1.5)),
        child: const Center(child: Text(
          'Momenteel geen abonnementen beschikbaar. Probeer het later '
          'opnieuw of neem contact op via info@onsmoment.app.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: kBrown, height: 1.4))),
      );
    }
    return Row(children: [
      Expanded(child: _tierKoopKnop('klein', 'Kies Klein')),
      const SizedBox(width: 10),
      Expanded(child: _tierKoopKnop('groot', 'Kies Groot',
          uitgelicht: true)),
    ]);
  }

  Widget _tierKoopKnop(String tier, String label,
      {bool uitgelicht = false}) {
    return GestureDetector(
      onTap: _bezigKopen ? null : () => _koopTier(tier),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: uitgelicht ? kPeach : kWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kPeach,
              width: uitgelicht ? 2 : 1.5),
        ),
        child: Center(child: _bezigKopen
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: kWhite))
            : Text(label,
                style: TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: uitgelicht ? kWhite : kPeach))),
      ),
    );
  }
}
