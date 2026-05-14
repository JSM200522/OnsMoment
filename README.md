# 💕 Ons Moment

Verbinding voor mensen met dementie. Twee portalen: tablet (Jan, ontvangt automatisch) en familie (Sara, stuurt).

## 📁 Projectstructuur

```
onsmoment_final/
├── .github/workflows/build.yml   ← GitHub Action die de APK bouwt
├── pubspec.yaml                  ← Flutter dependencies
└── lib/
    ├── main.dart                 ← Startpunt + router
    ├── models/                   ← Data structuren
    ├── services/                 ← Firebase logic
    └── screens/
        ├── tablet/               ← Jan's portaal (kiosk modus)
        ├── familie/              ← Sara's portaal
        └── setup/                ← Eerste-keer wizard
```

## 🚀 APK bouwen (volautomatisch)

Zodra deze bestanden in GitHub staan + `google-services.json` in de root:

1. GitHub Action triggert automatisch bij elke push naar `main`
2. Bouw duurt 8-15 minuten
3. Download APK via: GitHub → Actions tab → laatste run → Artifacts → `ons-moment-apk`

## 📱 APK op tablet zetten

1. Download `app-release.apk` naar je telefoon of computer
2. Verstuur naar de tablet via email/WhatsApp/USB
3. Op de tablet: open het bestand → "Installeer onbekende app" toestaan → Installeer
4. Open Ons Moment → eerste-keer setup doorlopen

## 🔧 Belangrijk

- **Package name**: `com.onsmoment.app` (matcht met de Firebase registratie)
- **Min Android versie**: Android 6.0 (SDK 23) — vereist voor Firebase Auth
- **google-services.json**: moet in de root van de repo staan (Action kopieert hem naar android/app/)

## 🆘 Als de build faalt

Check de GitHub Actions log voor de exacte foutmelding. Veelvoorkomende issues:
- `google-services.json` ontbreekt → upload hem naar repo root
- Package name mismatch → de naam in `google-services.json` moet `com.onsmoment.app` zijn
- Dependency conflict → laat me weten welke versie faalt
