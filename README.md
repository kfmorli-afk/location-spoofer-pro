# 🌍 Location Spoofer Pro

> Professionelle iOS-App für systemweites GPS-Location-Spoofing in Kombination mit **Local Dev VPN** und dem Apple Developer Protocol `com.apple.dt.simulatelocation`. Entwickelt für **iPhone 15** und optimiert für **Sideloadly**.

---

## ✨ Features

- 🗺️ **Apple Maps Interface:** Flüssige native MapKit-Kartenansicht mit Standard-, Satelliten- und Hybridansicht.
- 🔍 **Echtzeit-Ortssuche:** Autovervollständigung für Städte, Adressen, Points of Interest via `MKLocalSearchCompleter`.
- 📍 **Interaktive Pin-Platzierung:** Tippen oder Gedrückthalten überall auf der Welt mit präziser Koordinaten- und Adressanzeige.
- ⚡ **Local Dev VPN & Lockdown Engine:** Direkte Kommunikation mit dem internen Apple Developer Dienst `com.apple.dt.simulatelocation` über Loopback (`127.0.0.1:62078`).
- 🔐 **Pairing-Import:** Einfacher Import von `.mobiledevicepairing` / `.plist` Pairing-Zertifikaten aus der Dateien-App oder iCloud Drive.
- 🕹️ **Virtueller Joystick & Bewegung:** Geh- und Fahrmodus mit konfigurierbarer Geschwindigkeit (5 km/h bis 120 km/h) für dynamische Routen.
- ⭐ **Favoriten & Verlauf:** Schneller Zugriff auf weltweite Metropolen, Sehenswürdigkeiten und eigene gespeicherte Orte.
- 🔄 **Ein-Klick-Reset:** Sofortiges Zurücksetzen auf den echten Satelliten-GPS-Standort.
- 📊 **Live Debug-Konsole:** Echtzeit-Monitoring aller TLS-Handshakes und Datenpakete.
- ☁️ **GitHub Actions CI/CD:** Vollautomatisches Erstellen der `.ipa`-Datei in der Cloud für die Installation mit Sideloadly auf Windows.

---

## 📁 Projektstruktur

```
location spoofer pro/
├── LocationSpooferPro/
│   ├── App/
│   │   ├── LocationSpooferProApp.swift          # App Einstiegspunkt & State
│   │   ├── Info.plist                          # Berechtigungen & Konfiguration
│   │   └── LocationSpooferPro.entitlements      # Netzwerk- & Keychain-Rechte
│   ├── Models/
│   │   ├── SavedLocation.swift                 # Favoriten & Presets Model
│   │   ├── PairingRecord.swift                 # Apple Pairing Plist Parser
│   │   └── SimulationState.swift               # Status, Geschwindigkeiten & Logs
│   ├── Services/
│   │   ├── LocationManager.swift               # CoreLocation GPS Management
│   │   ├── GeocodingService.swift              # Reverse-Geocoding & Suche
│   │   ├── PairingService.swift                # TLS-Zertifikate & Speicher
│   │   ├── LockdownClient.swift                # TCP/TLS Client für lockdownd
│   │   ├── LocationSimulationClient.swift      # com.apple.dt.simulatelocation Engine
│   │   └── MovementSimulator.swift             # Joystick- und Schrittberechnung
│   ├── ViewModels/
│   │   ├── MapViewModel.swift                  # Karten- & Spoofing-Logik
│   │   ├── SearchViewModel.swift               # Autocomplete-Suchlogik
│   │   └── SettingsViewModel.swift             # Setup & Verbindungsprüfungen
│   ├── Views/
│   │   ├── MainMapView.swift                   # Hauptansicht mit nativer Apple Map
│   │   ├── Components/
│   │   │   ├── SearchBarView.swift             # Apple Maps Suchleiste
│   │   │   ├── SearchResultsView.swift         # Suchergebnis-Dropdown
│   │   │   ├── LocationControlCard.swift       # Untere Floating-Aktionskarte
│   │   │   ├── JoystickOverlayView.swift       # Virtueller Joystick
│   │   │   └── StatusIndicatorView.swift       # VPN- & Status-Pille
│   │   └── Sheets/
│   │       ├── FavoritesSheetView.swift        # Favoriten & Verlauf Sheet
│   │       ├── SettingsSheetView.swift         # Einstellungen & Pairing Import
│   │       └── LogConsoleSheetView.swift       # Live Debug-Konsole
│   └── Assets.xcassets/                        # App Icons & Akzentfarben
├── LocationSpooferPro.xcodeproj/
│   └── project.pbxproj                         # Xcode Projektdatei
├── .github/
│   └── workflows/
│       └── build-ipa.yml                       # Automatischer Cloud-IPA-Builder
├── tools/
│   └── package_ipa.py                          # Hilfsskript für Validierung & IPA-Packen
├── ANLEITUNG.md                                # Ausführliche Deutsche Anleitung
└── README.md
```

---

## 📖 Anleitung

Lies die Datei [ANLEITUNG.md](file:///c:/Users/psmar/Desktop/location%20spoofer%20pro/ANLEITUNG.md) für eine detaillierte Schritt-für-Schritt-Anleitung zur Erstellung der `.ipa`, Installation via Sideloadly und Konfiguration auf deinem iPhone 15!
