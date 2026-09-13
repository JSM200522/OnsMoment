import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../services/bel_log_service.dart';
import '../../services/device_modus_service.dart';
import '../../services/push_service.dart';
import '../../theme/kleuren.dart';

/// AVG-1 (12 sept 2026) — recht op verwijdering (AVG art. 17).
///
/// Twee-staps-dialog: (1) uitleg + lijst van kringen die verdwijnen +
/// ontvanger-tablet-waarschuwing, (2) type "VERWIJDER" om te bevestigen.
/// Roept dan `verwijderAccount` Cloud Function aan (Admin SDK cascade)
/// en signOut. Bij succes → auth-listener in _RouterSchermState leidt
/// automatisch naar SetupWizard.
Future<void> startVerwijderAccountFlow(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  // Vooraf-check: welke kringen wordt eigenaar van (voor waarschuwing).
  List<String> eigenKringNamen = [];
  try {
    final snap = await FirebaseFirestore.instance.collection('kringen')
        .where('eigenaarUid', isEqualTo: user.uid).get();
    eigenKringNamen = snap.docs
        .map((d) => (d.data()['naam'] as String? ?? '').trim())
        .where((n) => n.isNotEmpty)
        .toList();
  } catch (_) {
    // Fail-soft: als lijst niet opgehaald kan worden, tonen we
    // generieke waarschuwing zonder namen.
  }

  if (!context.mounted) return;

  final akkoordStap1 = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _Stap1Dialog(eigenKringNamen: eigenKringNamen),
  );
  if (akkoordStap1 != true || !context.mounted) return;

  final akkoordStap2 = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _Stap2Dialog(),
  );
  if (akkoordStap2 != true || !context.mounted) return;

  // Progress-dialog + Cloud Function-call
  await _voerVerwijderingUit(context);
}

class _Stap1Dialog extends StatelessWidget {
  final List<String> eigenKringNamen;
  const _Stap1Dialog({required this.eigenKringNamen});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: kCream,
      title: const Text('Account verwijderen',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
              color: kBrown)),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Dit wist ALLES van jouw account:',
              style: TextStyle(fontSize: 14, color: kBrown,
                  fontWeight: FontWeight.w700, height: 1.4),
            ),
            const SizedBox(height: 12),
            const Text(
              '• Je persoonlijke gegevens (naam, e-mail, foto)\n'
              '• De momenten en berichten die je hebt gestuurd\n'
              '• Je lidmaatschap in alle kringen waar je in zit',
              style: TextStyle(fontSize: 13, color: kBrownLight, height: 1.6),
            ),
            if (eigenKringNamen.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'De volgende kring(en) worden helemaal verwijderd:',
                style: TextStyle(fontSize: 13, color: kBrown,
                    fontWeight: FontWeight.w700, height: 1.4),
              ),
              const SizedBox(height: 6),
              Text(
                eigenKringNamen.map((n) => '• $n').join('\n'),
                style: const TextStyle(fontSize: 13, color: kBrownLight,
                    height: 1.6),
              ),
              const SizedBox(height: 6),
              const Text(
                'Alle andere leden verliezen direct hun toegang. '
                'Het apparaat van je dierbare stopt onmiddellijk met '
                'Ons Moment en komt terug op het instel-scherm.',
                style: TextStyle(fontSize: 13, color: kBrown,
                    fontWeight: FontWeight.w600, height: 1.5),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: kPeachPale,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kPeach, width: 1.2),
              ),
              child: const Row(children: [
                Text('⚠️', style: TextStyle(fontSize: 20)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Dit kan NIET ongedaan worden gemaakt.',
                    style: TextStyle(fontSize: 13, color: kBrown,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuleren',
              style: TextStyle(color: kTextMuted,
                  fontWeight: FontWeight.w700)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: kRood,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Ja, verwijder alles',
              style: TextStyle(color: kWhite,
                  fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

class _Stap2Dialog extends StatefulWidget {
  const _Stap2Dialog();
  @override
  State<_Stap2Dialog> createState() => _Stap2DialogState();
}

class _Stap2DialogState extends State<_Stap2Dialog> {
  final _bevestigCtrl = TextEditingController();
  bool _isKlaar = false;

  @override
  void dispose() {
    _bevestigCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: kCream,
      title: const Text('Weet je het echt zeker?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
              color: kBrown)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Type het woord "VERWIJDER" hieronder om te bevestigen.',
            style: TextStyle(fontSize: 14, color: kBrownLight, height: 1.5),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _bevestigCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: kBrown, fontSize: 15,
                fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: 'VERWIJDER',
              hintStyle: const TextStyle(color: kTextMuted),
              filled: true,
              fillColor: kWhite,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kPeachLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kPeachLight),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kRood, width: 2),
              ),
            ),
            onChanged: (v) => setState(
                () => _isKlaar = v.trim().toUpperCase() == 'VERWIJDER'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuleren',
              style: TextStyle(color: kTextMuted,
                  fontWeight: FontWeight.w700)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: kRood,
            disabledBackgroundColor: kPeachLight,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _isKlaar
              ? () => Navigator.pop(context, true)
              : null,
          child: const Text('Verwijderen (definitief)',
              style: TextStyle(color: kWhite,
                  fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

Future<void> _voerVerwijderingUit(BuildContext context) async {
  // Non-dismissible progress-dialog.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: kCream,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(height: 6),
          CircularProgressIndicator(color: kPeach),
          SizedBox(height: 18),
          Text('Bezig met verwijderen…\n'
              'Dit kan tot 90 seconden duren bij een grote familie.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: kBrown,
                  fontWeight: FontWeight.w700, height: 1.4)),
        ],
      ),
    ),
  );

  String? foutmelding;
  bool clientTimeout = false;
  try {
    // AVG-1-P1 (13 sept 2026): expliciete lege payload i.p.v.
    // `.call<dynamic>()` zonder argument. In cloud_functions 5.x
    // behandelt de callable een missing argument mogelijk anders dan
    // v4; expliciet `{}` is de veilige signature en matcht wat
    // RevenueCat/Firebase-docs adviseren voor callables zonder input.
    //
    // P6 (14 sept 2026): expliciete 90s client-side timeout via
    // HttpsCallableOptions. Server-side is de function 540s
    // getimeouted en werkt door bij een grote familie ook al gaf de
    // client op. De client-timeout dient om de UI-blokkade te breken:
    // toesteltest 13 sept had een user die 5-10 min in een
    // laadscherm zat. Nu: max 90s wachten, daarna nette afhandeling
    // (sign-out + waarschuwing dat het op de server doorloopt).
    final callable = FirebaseFunctions
        .instanceFor(region: 'europe-west1')
        .httpsCallable(
          'verwijderAccount',
          options: HttpsCallableOptions(
            timeout: const Duration(seconds: 90),
          ),
        );
    final result = await callable.call<Map<String, dynamic>>({});
    unawaited(BelLogService.log(
        'verwijderAccount success — data: ${result.data}'));
    // Server heeft auth.deleteUser al gedaan; forceer signOut voor de
    // zekerheid + wis alle lokale prefs + achtergrond-idToken.
    await DeviceModusService.wis();
    await PushService.wisAchtergrondIdToken();
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      // Al uitgelogd door auth.deleteUser — negeer.
    }
    // Firestore-cache leegmaken zodat oude data niet blijft hangen.
    try {
      await FirebaseFirestore.instance.terminate();
      await FirebaseFirestore.instance.clearPersistence();
    } catch (_) {}
  } on FirebaseFunctionsException catch (e, st) {
    // AVG-1-P1: log de VOLLEDIGE fout zodat we bij een volgende
    // toesteltest de echte oorzaak zien in BelLogService.
    unawaited(BelLogService.log(
        'verwijderAccount FirebaseFunctionsException — '
        'code=${e.code} message=${e.message} details=${e.details}\n$st'));
    debugPrint('verwijderAccount FF-EXC: ${e.code} — ${e.message}');
    // P6 (14 sept 2026): deadline-exceeded is de client-timeout hit —
    // server loopt zelf door tot 540s. Sign-out lokaal + warme
    // 'loopt door'-boodschap; bij volgende inlog zie je vanzelf of
    // je account weg is (SetupWizard) of nog bestaat (herprobeer-optie).
    if (e.code.toLowerCase().contains('deadline-exceeded')) {
      clientTimeout = true;
      try {
        await DeviceModusService.wis();
        await PushService.wisAchtergrondIdToken();
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
    } else {
      foutmelding = _warmeFout(e);
    }
  } catch (e, st) {
    // Generic catch — vaak parent-exception (FirebaseException,
    // PlatformException) die niet als FirebaseFunctionsException wordt
    // gevangen. Log runtime-type + toString zodat we die volgende keer
    // exact zien.
    unawaited(BelLogService.log(
        'verwijderAccount OTHER EXCEPTION — '
        'type=${e.runtimeType} toString=$e\n$st'));
    debugPrint('verwijderAccount other exc: ${e.runtimeType} — $e');
    foutmelding = 'Verwijderen mislukte — probeer het over enkele '
        'minuten opnieuw. (${e.runtimeType})';
  }

  if (!context.mounted) return;
  // Sluit progress-dialog.
  Navigator.of(context, rootNavigator: true).pop();

  if (foutmelding != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(foutmelding),
      backgroundColor: kRood,
      duration: const Duration(seconds: 6),
    ));
    return;
  }

  if (clientTimeout) {
    // P6 (14 sept 2026): warme uitleg dat de server doorwerkt, ook
    // al is de UI-timer voorbij. Auth-listener stuurt de user na de
    // signOut hierboven al naar SetupWizard.
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Verwijderen duurt langer dan verwacht — het loopt '
          'op de achtergrond door. Log over een minuut opnieuw in om te '
          'zien of alles weg is.'),
      backgroundColor: kPeach,
      duration: Duration(seconds: 8),
    ));
    return;
  }

  // Succes-snackbar; het auth-listener-pad in _RouterSchermState leidt
  // ondertussen automatisch naar SetupWizard.
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
    content: Text('Je account en alle gegevens zijn verwijderd.'),
    backgroundColor: kPeach,
    duration: Duration(seconds: 6),
  ));
}

String _warmeFout(FirebaseFunctionsException e) {
  final code = e.code.toLowerCase();
  if (code.contains('unauthenticated')) {
    return 'Je bent niet meer ingelogd. Log opnieuw in en probeer het.';
  }
  if (code.contains('deadline-exceeded') || code.contains('unavailable')) {
    return 'De server reageert traag. Probeer het over een paar '
        'minuten opnieuw — als er wel wat is gebeurd zie je dat vanzelf.';
  }
  return 'Verwijderen mislukte — probeer het over enkele minuten '
      'opnieuw. Neem contact op via info@onsmoment.app als het blijft '
      'mislukken.';
}
