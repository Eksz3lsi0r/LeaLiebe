# Contributing to Lea Liebe Arena RPG

Danke für dein Interesse, zu diesem Projekt beizutragen! 

## 🚀 Development Setup

### Voraussetzungen
- [Roblox Studio](https://www.roblox.com/create) (neueste Version)
- [VS Code](https://code.visualstudio.com/) mit Luau LSP Extension
- [Aftman](https://github.com/LPGhatguy/aftman) für Tool-Management

### Installation
```bash
# Repository klonen
git clone https://github.com/Eksz3lsi0r/LeaLiebe.git
cd LeaLiebe

# Tools installieren
aftman install

# Dependencies laden  
wally install

# Development-Server starten
rojo serve --port 34872
```

## 📋 Code Standards

### Luau Guidelines
- **Strict Mode**: Alle Lua-Dateien beginnen mit `--!strict`
- **Typisierung**: Explizite Typen für Public APIs
- **Naming**: PascalCase für Module/Classes, camelCase für Variablen
- **Struktur**: Ein Export pro Datei, logische Gruppierung

### Beispiel:
```lua
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)

type PlayerStats = {
    health: number,
    mana: number,
    level: number
}

local CombatSystem = {}

function CombatSystem.dealDamage(target: Model, damage: number): boolean
    -- Implementation here
    return true
end

return CombatSystem
```

### Architektur-Prinzipien
1. **Server Authority**: Alle Gameplay-Logic läuft server-side
2. **Client Prediction**: Nur visuelle Effekte sofort am Client
3. **Event-Driven**: RemoteEvents für Client-Server Kommunikation
4. **Modular**: Shared-Module für gemeinsame Logic

## 🛠 Workflow

### Feature Development
1. **Branch erstellen**: `git checkout -b feature/arena-system`
2. **Code schreiben**: Folge den Standards oben
3. **Testen**: In Studio über Live-Sync testen
4. **Format/Lint**: `stylua src/` und `selene src/`
5. **Commit**: Beschreibende Commit-Messages
6. **Pull Request**: Mit Beschreibung der Änderungen

### Testing
- **Manuell**: Studio Play-Testing für Gameplay
- **Linting**: `selene src/` für Code-Qualität  
- **Format**: `stylua src/` vor commits
- **Build-Test**: `rojo build --output test.rbxl`

### Commit-Convention
```
type(scope): kurze Beschreibung

Längere Erklärung bei Bedarf...

- feat: neue Feature
- fix: Bug-Fix
- refactor: Code-Umstrukturierung
- docs: Dokumentation
- style: Formatierung
- test: Tests hinzufügen
```

## 🎯 Contribution Areas

### High Priority
- [ ] Combat-System (Server-Logic)
- [ ] KI-Gegner Verhalten
- [ ] Arena-Management
- [ ] Player Stats & Progression

### Medium Priority  
- [ ] UI/UX Verbesserungen
- [ ] Sound-System Integration
- [ ] Performance-Optimierung
- [ ] Mobile-Support

### Nice to Have
- [ ] Arena-Editor
- [ ] Replay-System  
- [ ] Achievement-System
- [ ] Social Features

## 🚫 Was NICHT gewünscht ist

- **Client-authoritative** Gameplay-Logic
- **Hardcoded Values** statt Constants
- **Magic Numbers** ohne Erklärung
- **Massive Functions** - lieber kleine, fokussierte Funktionen
- **Direct Studio .rbxl** Files - nur über Rojo-Sync

## 📁 Datei-Organisation

```
src/
├── ReplicatedStorage/
│   ├── Config.lua              # Globale Konfiguration
│   └── Shared/                 # Geteilte Module
│       ├── Constants.lua       # Spiel-Konstanten (EDIT HERE!)
│       ├── ArenaConstants.lua  # Arena-spezifische Werte
│       └── ClassSystem.lua     # Klassen-Definitionen
├── ServerScriptService/        # Server-Logic
│   ├── Main.server.lua        # Entry Point
│   ├── ArenaManager.server.lua # Arena-Management
│   └── EnemyAI.lua           # KI-Verhalten
└── StarterPlayer/StarterPlayerScripts/
    └── Client.client.lua      # Client-Entry Point
```

## 🔧 Remote Events

Definiert in `default.project.json` → `ReplicatedStorage/Remotes/`:

**Input (Client → Server):**
- `MoveRequest(direction: Vector3)`
- `CombatRequest(action: string, target: Instance?, spellId: string?)`

**Output (Server → Client):**
- `CombatSync(action, target, damage?, effect?)`
- `UpdatePlayerHUD(health, mana, stamina, cooldowns)`

## ❓ Fragen?

- **Issues**: GitHub Issues für Bug-Reports/Feature-Requests
- **Diskussionen**: GitHub Discussions für allgemeine Fragen
- **Code-Review**: Pull Request Comments

## 📄 Lizenz

Durch das Beitragen stimmst du zu, dass deine Beiträge unter der gleichen Lizenz stehen wie das Projekt.