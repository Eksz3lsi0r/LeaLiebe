#!/bin/bash

# Roblox Luau + Rojo Quick Setup Script
# Führt alle notwendigen Schritte für die Entwicklungsumgebung aus

echo "🚀 LeaLiebe Roblox Projekt Setup"
echo "=================================="

# 1. Sourcemap generieren
echo "� Prüfe Tooling (aftman/rojo)..."
if command -v aftman >/dev/null 2>&1; then
    echo "✅ aftman gefunden"
    export PATH="$HOME/.aftman/bin:$PATH"
else
    echo "ℹ️  aftman nicht gefunden. Optional installieren: https://github.com/LPGhatguy/aftman"
fi

if command -v wally >/dev/null 2>&1; then
    echo "✅ wally gefunden"
else
    echo "ℹ️  wally nicht gefunden. Optional installieren: https://wally.run"
fi

echo "📦 Installiere Wally-Pakete (falls möglich)..."
if command -v wally >/dev/null 2>&1; then
    wally install || true
else
    echo "⚠️  wally nicht verfügbar – überspringe Paketinstallation."
fi

if ! command -v rojo >/dev/null 2>&1; then
    echo "🔄 Versuche rojo über aftman bereitzustellen..."
    if command -v aftman >/dev/null 2>&1; then
        aftman install || true
    fi
fi

if ! command -v rojo >/dev/null 2>&1; then
    echo "❌ rojo nicht im PATH. Bitte installieren (aftman) oder Binary in PATH legen."
    exit 1
fi

echo "�📋 Generiere Sourcemap für Luau Language Server..."
rojo sourcemap --output sourcemap.json

if [ $? -eq 0 ]; then
    echo "✅ Sourcemap erfolgreich generiert"
else
    echo "❌ Fehler beim Generieren der Sourcemap"
    exit 1
fi

# 2. Projekt validieren
echo "🔍 Validiere Rojo-Projektkonfiguration..."
rojo build --output /tmp/test-build.rbxl > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✅ Rojo-Projekt ist gültig"
    rm -f /tmp/test-build.rbxl
else
    echo "❌ Rojo-Projektkonfiguration hat Fehler"
    exit 1
fi

# 3. Rojo Server Status prüfen
echo "🌐 Prüfe Rojo Server Status..."
if pgrep -f "rojo serve --port 34872" > /dev/null; then
    echo "✅ Rojo Server läuft bereits auf Port 34872"
else
    echo "🔄 Starte Rojo Server..."
    nohup rojo serve --port 34872 >/tmp/rojo-serve.log 2>&1 &
    sleep 2
    echo "✅ Rojo Server gestartet auf Port 34872 (Logs: /tmp/rojo-serve.log)"
fi

echo ""
echo "🎯 Setup abgeschlossen! Nächste Schritte:"
echo "1. Öffne Roblox Studio"
echo "2. Installiere das Rojo Studio Plugin"
echo "3. Verbinde zu localhost:34872"
echo "4. Klicke 'Sync Into' um das Projekt zu laden"
echo ""
echo "💡 Nützliche Commands:"
echo "   rojo serve --port 34872    # Server starten"
echo "   rojo sourcemap --output sourcemap.json  # Sourcemap aktualisieren"
echo "   rojo build --output game.rbxl           # Standalone Build erstellen"