# Ons Moment — Project Context

> Dit bestand is het permanente geheugen voor elke Claude-sessie in dit project. Lees dit eerst voordat je iets doet.

## Het doel

Ons Moment is een digitale knuffel voor mensen met dementie, verstandelijke beperking of erge vergeetachtigheid — en hun familie die zich machteloos voelt op afstand.

Familie stuurt vanaf hun telefoon een foto, stem, lied of bericht. Op het apparaat van de dierbare popt dat moment automatisch op met een vertrouwd herkenningsgeluid en hun eigen foto als warme achtergrond. Zij hoeven niks te doen — het komt naar hen toe.

Kernwaarde: "Mantelzorger App helpt JOU. Ons Moment helpt je DIERBARE."

## Businessmodel

- 7,99 EUR per maand per gezinsaccount, max 8 familieleden
- 5 dagen gratis proefperiode
- Markt: Nederland eerst

## Architectuur (V7)

Een gedeeld gezinsaccount: alle familieleden + ontvanger gebruiken dezelfde Firebase Auth account. Rol per apparaat via SharedPreferences/localStorage: familie of ontvanger.

Firestore collecties: gebruikers, dagelijkse_momenten, momenten, notities. Alle koppeling via familieUid (NIET naarUid — dat was V6 bug).

## Tech stack

- Flutter 3.19.6
- Firebase (Auth, Firestore, Storage)
- Hosting via GitHub Pages (workflow in .github/workflows/build.yml)
- Belangrijke packages: firebase_core/auth/firestore/storage, image_picker, file_picker, record, just_audio, wakelock_plus, shared_preferences, flutter_localizations, intl ^0.18.1

## Firebase project

- Project ID: onsmonent
- Auth: email + wachtwoord
- Test account: oma@test.nl / oma12345

## Live URLs

- App: https://jsm200522.github.io/OnsMoment/
- Repo: https://github.com/JSM200522/OnsMoment

## Bekende issues per 15 mei 2026

- Oude V6 momenten in Firestore gebruiken nog naarUid prefix — verschijnen niet bij V7 ontvanger
- Pixabay-URLs voor preset-geluiden kunnen falen door hotlink-protectie (fallback aanwezig)
- Stem-opname op web werkt via blob URLs — moet bytes uploaden naar Storage (V8 fix)
- Firebase web-app was incorrect geconfigureerd in build.yml (Android-appId voor web-omgeving). Werkte tot ~15 mei 2026 door Google's tolerantie. Vanaf 16 mei strenger geweigerd → 400 errors op identitytoolkit.goog. Fix: echte web-config uit Firebase Console gebruikt in build.yml.

## V8 routekaart

1. Stem-opname als bytes uploaden naar Storage
2. Familieleden uitnodigen via email + deeplink
3. Persoonlijk herkenningsgeluid opnemen
4. Stripe 7,99/maand met 5 dagen proef
5. Account-status check

## V9 — App stores

- Google Play: 25 EUR eenmalig, ~1 week review
- Apple App Store: 99 EUR per jaar, ~1-2 weken review, Mac of cloud build service nodig
- Privacy policy + terms of service verplicht
- GDPR/AVG compliance

## Over Joshua

- Geen technische achtergrond
- Windows 11 + iPhone
- Nederlands, stap-voor-stap uitleg zonder jargon
- Wil senior-level engineering en productie-kwaliteit

## Werkstijl-regels

1. Denk eerst diep na voor implementatie
2. Controleer eigen output als productie-code
3. Geen aannames — verifieer eerst
4. Geen halfwerk
5. Edge cases, UX, performance, security, schaalbaarheid meedenken
6. Geen pseudo-code, geen essentiele delen weglaten

## Standaard workflow

Voor elke wijziging:
1. Lees bestaande code
2. Check afhankelijkheden (grep)
3. Beschrijf plan kort
4. Maak wijziging
5. Run flutter analyze
6. Run flutter build web
7. Pas dan committen en pushen

NOOIT blind pushen — vandaag (15 mei 2026) heeft dat 10 rode builds opgeleverd.

## Sessielog

- 15 mei 2026: V7 release, build #47 groen
- 15 mei 2026: Overstap naar Claude Code workflow
