# Ons Moment 💕

**Twee portalen, één verbinding**

## Portaal 1 — Tablet (Jan)
- Scherm altijd aan, kiosk modus
- Automatisch afspelen op geplande tijd
- Kan NIETS aanpassen
- Grote klok, foto's, agenda, video's

## Portaal 2 — Familie (Sara)
- Stemberichtje opnemen
- Foto/video uploaden
- Tijdstip + herhaling instellen
- Ziet of Jan het heeft afgespeeld ✓

## Technisch
- Firebase Auth (twee rollen: tablet / familie)
- Firestore (momenten opslaan + status bijhouden)
- Firebase Storage (audio, foto, video)
- just_audio (automatisch afspelen)
- wakelock_plus (scherm altijd aan)

## Firebase structuur
```
gebruikers/{uid}
  naam, rol, tabletUid, email

momenten/{id}
  vanUid, vanNaam, naarUid
  type: audio|foto|video|muziek
  mediaUrl, bericht
  geplandOp (timestamp)
  herhalen (bool)
  afgespeeld (bool)
  afgespeeldOp (timestamp)
```
