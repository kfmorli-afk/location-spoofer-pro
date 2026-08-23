#!/usr/bin/env python3
"""
Location Spoofer Pro - Packaging & Verification Tool
=====================================================
Dieses Skript validiert die Projektstruktur, extrahiert/prueft .mobiledevicepairing
Dateien und kann ein kompiliertes .app Verzeichnis in eine signierbereite .ipa fuer Sideloadly verpacken.
"""

import os
import sys
import shutil
import zipfile
import plistlib
from pathlib import Path

# Ensure UTF-8 output on Windows consoles
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJECT_ROOT = Path(__file__).resolve().parent.parent

def check_project_structure():
    print("==================================================")
    print("Prüfe Location Spoofer Pro Projektstruktur...")
    print("==================================================")
    
    required_files = [
        "LocationSpooferPro/App/LocationSpooferProApp.swift",
        "LocationSpooferPro/App/Info.plist",
        "LocationSpooferPro/App/LocationSpooferPro.entitlements",
        "LocationSpooferPro/Models/SavedLocation.swift",
        "LocationSpooferPro/Models/PairingRecord.swift",
        "LocationSpooferPro/Models/SimulationState.swift",
        "LocationSpooferPro/Services/LocationManager.swift",
        "LocationSpooferPro/Services/GeocodingService.swift",
        "LocationSpooferPro/Services/PairingService.swift",
        "LocationSpooferPro/Services/LockdownClient.swift",
        "LocationSpooferPro/Services/LocationSimulationClient.swift",
        "LocationSpooferPro/Services/MovementSimulator.swift",
        "LocationSpooferPro/ViewModels/MapViewModel.swift",
        "LocationSpooferPro/ViewModels/SearchViewModel.swift",
        "LocationSpooferPro/ViewModels/SettingsViewModel.swift",
        "LocationSpooferPro/Views/MainMapView.swift",
        "LocationSpooferPro/Views/Components/SearchBarView.swift",
        "LocationSpooferPro/Views/Components/SearchResultsView.swift",
        "LocationSpooferPro/Views/Components/LocationControlCard.swift",
        "LocationSpooferPro/Views/Components/JoystickOverlayView.swift",
        "LocationSpooferPro/Views/Components/StatusIndicatorView.swift",
        "LocationSpooferPro/Views/Sheets/FavoritesSheetView.swift",
        "LocationSpooferPro/Views/Sheets/SettingsSheetView.swift",
        "LocationSpooferPro/Views/Sheets/LogConsoleSheetView.swift",
        "LocationSpooferPro.xcodeproj/project.pbxproj",
        ".github/workflows/build-ipa.yml",
        "ANLEITUNG.md",
        "README.md"
    ]
    
    missing = []
    for rel_path in required_files:
        full_path = PROJECT_ROOT / rel_path
        if full_path.exists():
            print(f"  [OK] Gefunden: {rel_path}")
        else:
            print(f"  [FEHLT] {rel_path}")
            missing.append(rel_path)
            
    if missing:
        print(f"\n[!] Warnung: {len(missing)} Dateien fehlen!")
        return False
    else:
        print("\n[+] Alle Projektdateien sind vollständig vorhanden und bereit!")
        return True

def inspect_pairing_file(pairing_path):
    print(f"\nAnalysiere Pairing-Datei: {pairing_path}")
    path = Path(pairing_path)
    if not path.exists():
        print(f"[!] Datei nicht gefunden: {pairing_path}")
        return False
        
    try:
        with open(path, "rb") as f:
            data = plistlib.load(f)
            
        udid = data.get("UDID") or data.get("DeviceUDID") or "Unbekannt"
        host_id = data.get("HostID", "Unbekannt")
        has_host_cert = "HostCertificate" in data
        has_host_key = "HostPrivateKey" in data
        has_device_cert = "DeviceCertificate" in data
        
        print(f"  * Device UDID:        {udid}")
        print(f"  * Host ID:            {host_id}")
        print(f"  * Host Certificate:   {'Ja' if has_host_cert else 'NEIN (ungültig)'}")
        print(f"  * Host Private Key:  {'Ja' if has_host_key else 'NEIN (ungültig)'}")
        print(f"  * Device Certificate: {'Ja' if has_device_cert else 'Nein'}")
        
        if has_host_cert and has_host_key:
            print("  [+] Status: Gültige Pairing-Datei! Kann in der App importiert werden.")
            return True
        else:
            print("  [!] Status: Unvollständig. Es fehlen Zertifikate oder Schlüssel.")
            return False
    except Exception as e:
        print(f"[!] Fehler beim Lesen der Pairing-Datei: {e}")
        return False

def package_app_to_ipa(app_dir_path, output_ipa_path=None):
    app_path = Path(app_dir_path)
    if not app_path.exists() or not app_path.is_dir():
        print(f"[!] App-Verzeichnis nicht gefunden: {app_dir_path}")
        return False
        
    if output_ipa_path is None:
        output_ipa_path = PROJECT_ROOT / "LocationSpooferPro.ipa"
    else:
        output_ipa_path = Path(output_ipa_path)
        
    print(f"Erstelle IPA-Datei: {output_ipa_path}...")
    
    build_temp = PROJECT_ROOT / "build_temp"
    payload_dir = build_temp / "Payload"
    
    if build_temp.exists():
        shutil.rmtree(build_temp)
    payload_dir.mkdir(parents=True, exist_ok=True)
    
    dest_app = payload_dir / app_path.name
    shutil.copytree(app_path, dest_app)
    
    with zipfile.ZipFile(output_ipa_path, "w", zipfile.ZIP_DEFLATED) as zip_file:
        for root, dirs, files in os.walk(payload_dir):
            for file in files:
                file_full = Path(root) / file
                rel_archive_path = file_full.relative_to(build_temp)
                zip_file.write(file_full, rel_archive_path)
                
    shutil.rmtree(build_temp)
    print(f"[+] IPA erfolgreich erstellt: {output_ipa_path} ({os.path.getsize(output_ipa_path):,} Bytes)")
    return True

if __name__ == "__main__":
    if len(sys.argv) > 1:
        cmd = sys.argv[1]
        if cmd == "check":
            check_project_structure()
        elif cmd == "inspect-pairing" and len(sys.argv) > 2:
            inspect_pairing_file(sys.argv[2])
        elif cmd == "package" and len(sys.argv) > 2:
            package_app_to_ipa(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
        else:
            print("Verwendung:")
            print("  python package_ipa.py check")
            print("  python package_ipa.py inspect-pairing <pfad/zu/pairing.plist>")
            print("  python package_ipa.py package <pfad/zu/LocationSpooferPro.app> [ausgabe.ipa]")
    else:
        check_project_structure()
