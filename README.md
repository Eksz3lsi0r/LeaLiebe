# Lea Liebe Arena RPG

Ein modernes Arena-RPG entwickelt mit Roblox Studio und Rojo für Live-Synchronisation.

## 🎮 Spielkonzept

**Mini Arena RPG** - Spieler kämpfen in abgeschlossenen Arenen gegen KI-Gegner, sammeln Loot und verbessern ihre Ausrüstung.

### Kernfeatures
- **Server-autoritatives Combat-System** mit Melee/Ranged/Magic
- **Klassen-System** (Warrior, Mage, Archer) mit einzigartigen Fähigkeiten  
- **Arena-basierte Matches** mit Matchmaking-System
- **Loot & Equipment** mit Stats-Modifikation
- **KI-Gegner** mit FSM-basierter Navigation

## 🚀 Entwicklung

### Voraussetzungen
- [Roblox Studio](https://www.roblox.com/create) (neueste Version)
- [VS Code](https://code.visualstudio.com/) mit empfohlenen Extensions
- [Aftman](https://github.com/LPGhatguy/aftman) für Tool-Management

### Setup
1. Repository klonen:
   ```bash
   git clone https://github.com/Eksz3lsi0r/LeaLiebe.git
   cd LeaLiebe
   ```

2. Tools installieren:
   ```bash
   aftman install
   ```

3. Dependencies laden:
   ```bash
   wally install
   ```

4. Development-Server starten:
   ```bash
   # In VS Code: Strg+Shift+P → "Tasks: Run Task" → "Rojo: Serve"
   # Oder manuell:
   rojo serve --port 34872
   ```

5. In Roblox Studio:
   - Rojo Plugin installieren
   - "Connect" zu `localhost:34872`
   - Play testen

### Workflow
- **Live-Sync**: Code-Änderungen werden automatisch in Studio übertragen
- **Luau Strict**: Typ-sichere Entwicklung mit `--!strict`
- **Auto-Format**: StyLua formatiert Code beim Speichern
- **Lint**: Selene prüft auf häufige Lua-Fehler

### Projekt-Struktur
```
src/
├── ReplicatedStorage/          # Geteilte Ressourcen
│   ├── Config.lua             # Basis-Konfiguration
│   └── Shared/                # Gemeinsame Module
│       ├── Constants.lua      # Spiel-Konstanten
│       ├── ArenaConstants.lua # Arena-spezifische Werte
│       ├── ClassSystem.lua    # Klassen-Definitionen
│       └── Animations.lua     # Animation-IDs
├── ServerScriptService/        # Server-Logic
│   ├── Main.server.lua        # Haupt-Server-Script
│   ├── GameSetup.server.lua   # Spiel-Initialisierung
│   ├── ArenaManager.server.lua # Arena-Management
│   ├── EnemyAI.lua           # KI-Verhalten
│   └── MatchmakingSystem.server.lua # Matchmaking
└── StarterPlayer/StarterPlayerScripts/ # Client-Logic
    └── Client.client.lua      # Haupt-Client-Script
```

### Combat-System
Das Spiel nutzt ein **server-autoritatives Combat-System**:

**Input (Client → Server):**
- `MoveRequest(direction: Vector3)` - Bewegung
- `CombatRequest(action, target?, spellId?)` - Kampf-Aktionen

**Feedback (Server → Client):**
- `CombatSync` - Kampf-Ereignisse mit VFX
- `UpdatePlayerHUD` - Health/Mana/Stamina Updates (~150ms)

### Remotes (ReplicatedStorage/Remotes)
Alle Remote-Events sind in `default.project.json` definiert:
- Combat: `CombatRequest`, `CombatSync`
- Movement: `MoveRequest`
- UI: `UpdatePlayerHUD`, `QueueStatus`
- Events: `EnemyDeath`, `LootDrop`, `ArenaComplete`
- Shop: `EquipmentPurchase`, `EquipmentResult`

## 🔧 Konfiguration

### Performance-Ziele
- **60 FPS** - Keine Allokationen in RenderStepped
- **<80ms Input-Latenz** - Sofortige SFX/Animation, Server-Sync async
- **<350MB Speicher** (Mobile) - Instanz-Pooling bei Bedarf

### Code-Standards
- **Luau Strict Mode** für Typ-Sicherheit
- **Modulare Architektur** - Services/Controllers getrennt
- **Constants-driven** - Keine Magic Numbers
- **Server Authority** - Client nur Input/VFX

## 📋 Roadmap

### ✅ Completed
- [x] Basis Rojo-Setup mit Live-Sync
- [x] Projekt-Struktur und Tooling
- [x] Grundlegende Combat-Remote-Events

### 🚧 In Progress  
- [ ] Arena-Management System
- [ ] Basis Combat-Logic (Server)
- [ ] Spieler Input-Handler (Client)
- [ ] Health/Mana/Stamina System

### 📅 Planned
- [ ] KI-Gegner mit FSM
- [ ] Loot-System & Equipment
- [ ] Klassen-System (Warrior/Mage/Archer)
- [ ] Matchmaking & Queue-System
- [ ] Arena-Editor für Level-Design
- [ ] Shop-System mit Gold-Wirtschaft

## 🛠 Commands

```bash
# Development
rojo serve --port 34872        # Live-Sync zu Studio
rojo build --output build.rbxl # Standalone .rbxl erstellen  
rojo sourcemap -o sourcemap.json # LSP-Sourcemap aktualisieren

# Code Quality
stylua src/ test/              # Code formatieren
selene src/                    # Linting
```

## 📚 Weitere Infos

- **Copilot Instructions**: `.github/copilot-instructions.md`
- **Tasks**: VS Code Tasks für Build/Serve/Lint
- **Extensions**: Empfohlene VS Code Extensions in `.vscode/extensions.json`

## 📄 Lizenz

Dieses Projekt ist für Lern- und Demonstrationszwecke. Alle Roblox-Assets unterliegen den Roblox-Nutzungsbedingungen.