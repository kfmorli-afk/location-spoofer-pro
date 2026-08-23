# 🗺️ Location Spoofer Pro - Vollständige Installations- & Bedienungsanleitung

Herzlichen Glückwunsch! Du hast nun den kompletten Quellcode und das Build-System für **Location Spoofer Pro**. Diese App ermöglicht es dir, auf deinem **iPhone 15** ohne PC-Dauerverbindung den GPS-Standort systemweit (für **Snapchat**, **Apple "Wo ist?" (Find My)**, **Tinder**, **Maps**, **WhatsApp**, etc.) zu fälschen – direkt in Kombination mit **Local Dev VPN**.

---

## 📋 Übersicht der Komponenten

1. **Location Spoofer Pro (iOS App):**
   * Apple Maps Kartenoberfläche
   * Suchleiste für Adressen und Orte mit automatischer Vervollständigung
   * Fadenkreuz / Pin-Auswahl auf der ganzen Welt
   * **"Standort fälschen"** & **"Zurücksetzen" (Reset)** Buttons
   * Integrierter virtueller **Joystick** mit Geschwindigkeitsstufen (Gehen 5 km/h, Joggen, Fahrrad, Auto)
   * Favoriten & Verlauf

2. **Local Dev VPN (oder SideStore VPN):**
   * Stellt einen lokalen Loopback-Tunnel auf dem iPhone bereit (`127.0.0.1:62078`), damit die App mit dem Apple Developer Daemon `lockdownd` und `com.apple.dt.simulatelocation` kommunizieren kann.

3. **Pairing-Zertifikat (`.mobiledevicepairing` / `.plist`):**
   * Das kryptografische Vertrauenszertifikat deines iPhones, mit dem sich die App beim iOS-System als autorisierter Entwickler ausweist.

---

## 🚀 Schritt 1: Die `.ipa`-Datei erstellen

Da du auf einem Windows-PC arbeitest, kannst du die `.ipa` am einfachsten und schnellsten über den integrierten **GitHub Actions Cloud-Builder** kompilieren lassen (völlig kostenlos und ohne Mac):

### Methode A: Automatisch via GitHub Actions (Empfohlen für Windows)
1. Erstelle ein kostenloses Repository auf [GitHub.com](https://github.com).
2. Lade diesen Ordner (`location spoofer pro`) in dein Repository hoch.
3. Klicke im GitHub-Repository oben auf den Reiter **Actions**.
4. Wähle den Workflow **"Build Location Spoofer Pro IPA"** aus und klicke auf **"Run workflow"**.
5. Nach ca. 2–3 Minuten ist der Build fertig. Klicke auf den Durchlauf und lade unter **Artifacts** die Datei `LocationSpooferPro-IPA.zip` herunter.
6. Entpacke das Zip – darin befindet sich deine fertige `LocationSpooferPro.ipa`!

### Methode B: Direkt mit Xcode (falls du einen Mac hast)
1. Öffne `LocationSpooferPro.xcodeproj` in Xcode.
2. Wähle dein Team / Apple ID aus.
3. Wähle *Product > Archive* oder erstelle das `.app` Bundle und packe es mit `python tools/package_ipa.py package <pfad>` zur `.ipa`.

---

## 📲 Schritt 2: Installation auf dem iPhone 15 mit Sideloadly

1. Lade **Sideloadly** auf deinem Windows-PC herunter und starte es.
2. Schließe dein iPhone 15 per USB-Kabel an deinen PC an und tippe auf dem iPhone auf **"Diesem Computer vertrauen"**.
3. Ziehe die Datei `LocationSpooferPro.ipa` per Drag & Drop in das Sideloadly-Fenster.
4. Gib deine Apple-ID ein (wird nur zum Signieren der App verwendet).
5. Klicke auf **Start**. Nach ca. 30 Sekunden ist die App auf deinem iPhone 15 installiert!

---

## ⚙️ Schritt 3: Entwicklermodus auf dem iPhone 15 aktivieren

Auf iOS 16, 17 und neuer verlangt Apple für sideloaded Entwickler-Apps den Entwicklermodus:
1. Öffne auf deinem iPhone die **Einstellungen**.
2. Gehe zu **Datenschutz & Sicherheit**.
3. Scrolle ganz nach unten und tippe auf **Entwicklermodus**.
4. Aktiviere den Schalter und starte dein iPhone neu.
5. Nach dem Neustart fragt iOS nach einer Bestätigung: Tippe auf **Aktivieren** und gib deinen Sperrcode ein.
6. Gehe in **Einstellungen > Allgemein > VPN und Geräteverwaltung**, tippe auf deine Apple-ID und wähle **"Vertrauen"**.

---

## 🔑 Schritt 4: Die Pairing-Datei (`.mobiledevicepairing`) einbinden

Damit die App ohne angeschlossenen PC den Entwicklerdienst ansteuern kann, benötigt sie deine Pairing-Datei:

1. **Woher bekommst du die Pairing-Datei?**
   * **Über Sideloadly:** Sideloadly speichert beim Anschließen des iPhones automatisch die Pairing-Datei auf deinem PC unter:
     `%APPDATA%\sideloadly\pairing\` oder `%USERPROFILE%\AppData\Roaming\sideloadly\`
   * **Über iTunes / Apple Devices:** Unter Windows befindet sich die Datei unter:
     `C:\ProgramData\Apple\Lockdown\<Deine-UDID>.plist`
   * **Über Jitterbugpair / AltServer:** Führe `jitterbugpair.exe` aus, um direkt eine `<UDID>.mobiledevicepairing` auf dem Desktop zu erzeugen.
2. **Auf das iPhone übertragen:**
   * Sende dir diese `.plist` oder `.mobiledevicepairing` Datei per AirDrop, iCloud Drive, Mail oder Telegram an dein iPhone.
   * Speichere sie in der **Dateien-App** (z.B. in *iCloud Drive* oder *Auf meinem iPhone*).
3. **In Location Spoofer Pro laden:**
   * Öffne **Location Spoofer Pro**.
   * Tippe unten auf **"VPN & Setup"** (Zahnrad).
   * Tippe auf **"Pairing-Datei importieren"** und wähle deine Datei aus.
   * Du siehst sofort ein grünes Häkchen und deine Geräte-UDID.

---

## 🌐 Schritt 5: Local Dev VPN aktivieren & Standort fälschen

1. Installiere die App **LocalDevVPN** (oder die integrierte VPN-Funktion von SideStore) aus dem App Store / Sideload.
2. Öffne **LocalDevVPN** und schalte den **VPN-Schalter auf AN**.
3. Öffne **Location Spoofer Pro**:
   * Oben siehst du den Status-Indikator: **"Verbunden & Bereit"** (grün/blau).
   * **Ort suchen:** Gib oben in der Suchleiste eine beliebige Stadt, Adresse oder Sehenswürdigkeit ein (z.B. *Times Square, New York* oder *Eiffelturm Paris*) und tippe auf das Ergebnis.
   * **Oder Manuell tippen:** Tippe einfach irgendwo auf die Weltkarte, um das Fadenkreuz/Pin zu platzieren.
   * **Standort fälschen:** Tippe unten auf den großen blauen Button **"Standort Fälschen"**.
   * Der Button leuchtet grün auf: **"Standort Aktiv"**.
4. **Ergebnis prüfen:**
   * Öffne jetzt **Snapchat**, **Apple "Wo ist?"**, **Google Maps** oder **Instagram**.
   * Dein Standort ist nun überall auf der Welt genau an dem Ort, den du ausgewählt hast!

---

## 🕹️ Bonus: Virtueller Joystick & Geh-Modus

1. Tippe in der unteren Karte auf **"Joystick"**.
2. Es erscheint ein schwebendes Steuerkreuz und eine Geschwindigkeitsleiste:
   * **5 km/h:** Normales Gehen
   * **12 km/h:** Joggen
   * **25 km/h:** Fahrrad fahren
   * **60 km/h:** Autofahren
3. Halte den virtuellen Joystick in eine Richtung gedrückt – dein gefälschter Standort bewegt sich flüssig in Echtzeit über die Straßen!

---

## 🔄 Standort zurücksetzen

Wenn du wieder deinen echten GPS-Standort haben möchtest:
1. Öffne **Location Spoofer Pro**.
2. Tippe unten auf den Button **"Reset"**.
3. Der gefälschte Standort wird sofort freigegeben und dein iPhone nutzt wieder das echte GPS-Signal.

---

## 🛠️ Fehlerbehebung (Troubleshooting)

* **Status zeigt "Lockdownd nicht erreichbar":**
  * Vergewissere dich, dass **LocalDevVPN** im Hintergrund eingeschaltet ist.
  * Prüfe in den Einstellungen der App, ob der Port auf `62078` und die Host-IP auf `127.0.0.1` steht.
* **Standort ändert sich in Snapchat nicht sofort:**
  * Schließe Snapchat einmal komplett aus dem Multitasking (App-Switcher nach oben wischen) und öffne es erneut.
* **Live-Logs ansehen:**
  * Tippe in den Einstellungen auf **"Live Debug-Konsole öffnen"**, um jedes gesendete Datenpaket und eventuelle Fehler live im Klartext zu sehen.
