## Copilot-Anleitung für dieses Repo

**PROJEKT-PIVOT: Von Endless Runner zu Mini Arena RPG (13.09.2025)**

Ziel: KI-Agents schnell produktiv machen für dieses Roblox + Rojo Arena RPG. Nur projektspezifische, verlässliche Muster – kurz und konkret.

### Überblick (NEU: Arena RPG)
- Architektur: Server-autoritatives Combat-System, Client nur Input/VFX.
  - Server (`src/ServerScriptService/GameSetup.server.lua` + neue Combat-Scripts): Arena-Management, Combat-Loop, Health/Mana-System, AI-Gegner, Loot-Drops, Matchmaking.
  - Client (`src/StarterPlayer/StarterPlayerScripts/PlayerController.client.lua`): Combat Input (Attack/Block/Cast/Move), Kamera-Steuerung, Animation-Controller, Combat-VFX.
  - Shared (`src/ReplicatedStorage/Shared/{Constants.lua,Animations.lua}`): Combat-Stats, Spell-Configs, Damage-Formeln.
- Rojo-Datenmodell: `default.project.json` (authoritativ). Arena-Struktur: `Workspace/Arenas/<ArenaId>/`, Spieler-Instanzen unter `Workspace/Players/<UserId>/`.

### Workflow
- Start lokal: VS Code Task „Rojo: Serve“ starten und in Studio mit Plugin zu `localhost:34872` verbinden; Play.
- Luau Strict (`--!strict`) beibehalten. Mapping-Änderungen in `default.project.json` (und `rojo.toml`) spiegeln.
- Sourcemap für Luau-LSP aktuell halten: Task „Rojo: Sourcemap“ ausführen (schreibt `sourcemap.json`).

### Quality Bar & KPIs (kurz)
- 60 FPS anstreben (keine Allokationen in RenderStepped, Instanzen cachen).
- Server ist Quelle der Wahrheit (keine Client-Positionsschreibungen, HRP NetworkOwner=nil).
- Remotes: Input bündeln; HUD-Updates auf ~0,15 s throttlen (kleine Payload).
- Eingabefeedback <80 ms: SFX/Anim lokal am Client, Server sync via ActionSync.
- Speicher: Track-Cleanup konsequent; Pooling evaluieren (Mobile <350 MB).

### Spielregeln & Konventionen (NEU: Arena RPG)
- Arena: Feste runde/rechteckige Arena, ~50x50 Studs. Spawn-Points für Spieler und Gegner definiert.
- Bewegung: Server besitzt NetworkOwner; freie 3D-Bewegung statt Lane-System. Standardgeschwindigkeit `PLAYER.MoveSpeed`.
- Combat: Melee (Schwert/Axt), Ranged (Bogen/Zauber), Block/Parry-System. Attack/Block über `CombatRequest`.
- Health/Mana: Server autoritativ; Client zeigt Bars. Health-Regeneration außerhalb Kampf.
- Gegner-AI: Finite State Machine (Idle/Chase/Attack/Retreat), A*-Pathfinding für Navigation.
- Loot: Drops nach Gegnertod, Equipment-Slots (Weapon/Armor/Accessory), Stats-Modifikation.

### Remotes (ReplicatedStorage/Remotes) - NEU: Combat-System
- `MoveRequest:FireServer(direction:Vector3)` — Bewegungsrichtung.
- `CombatRequest:FireServer(action:"Attack"|"Block"|"Cast", target?:Instance, spellId?:string)` — Combat-Aktionen.
- `CombatSync:FireClient(player,{action,target,damage?,effect?})` — Server→Client Combat-Feedback.
- `UpdatePlayerHUD:FireClient(player,{health,mana,stamina,cooldowns})` — getaktet ~0,15s.
- `EnemyDeath`, `LootDrop`, `ArenaComplete`, `MatchmakingQueue` — Events und Status-Updates.
- Shop: `EquipmentPurchase:FireServer(itemId:string)` → `EquipmentResult:FireClient(player,{success,item?,gold})`.

### Client-Muster
- Input: A/D oder Pfeile → `LaneRequest`; W/Space → Jump; S → Roll; Mobile Swipes; `ContextActionService` bindet W/S (hohe Priorität, sink) und deaktiviert Default Controls.
- Kamera: Scriptable Follow im `RenderStepped`.
- Animationen: `Animate` deaktiviert; Animator lädt IDs aus `Shared/Animations.lua`; Run-Playback skaliert mit horizontaler Speed; Slide nutzt Platzhalter bis echte ID vorhanden.
- HUD: Minimal-HUD in `StarterGui/HUD.client.lua`; Singleton via `EndlessHUD`-Attribut (Duplikate werden entfernt).
 - Audio/Musik: SFX-IDs und Lautstärken zentral in `Shared/Constants.lua` (`AUDIO`). Musik-Loop + Ducking optional.
 - Accessibility: Attribute am `PlayerGui` (z. B. `HighContrast`, `EffectsEnabled`, `ScreenShake`) steuern UI/FX.

### Powerups & Audio
- Magnet zieht Coins im Radius (`POWERUPS.Magnet.{Duration,Radius}`); Shield nutzt `ShieldHits` (impact-verbrauchend).
- Audio zentral in `Constants.AUDIO` (Listen: Coin/Jump/Slide/Powerup/Crash). Client spielt SFX bei Coin/Powerup/GameOver und bei `ActionSync` (Jump/Slide). IDs als `rbxassetid://<number>`.

### Änderungen umsetzen
- Zahlen/Wahrscheinlichkeiten in `Constants.lua` pflegen (statt Magic Numbers); HUD-Update-Throttle (0,15s) respektieren.
- Neue Gameplay-Parts: `Anchored=true`, korrekte `CanCollide/CanQuery/CanTouch`, sinnvolle Namen/Attribute für Overlap-Scans.
- Segmente/Tracks-Namen strikt beibehalten; Mappings in `default.project.json`/`rojo.toml` aktualisieren.

### Schlüsseldaten
- Kern: `Main.server.lua`, `Client.client.lua`, `HUD.client.lua`, `Shared/{Constants.lua,Animations.lua}`, Rojo-Mapping.
- Roadmap: `README.md` ist ToDo/Status-Quelle. Ablauf für Agents: (1) oberstes offenes, risikoarmes Item wählen, (2) minimal umsetzen, (3) `README.md` abhaken + Datum/Notiz, (4) Mapping synchron halten.

Diese Datei nur bei Konventionsänderungen aktualisieren; laufende Fortschritte gehören in `README.md`.
