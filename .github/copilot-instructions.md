## Copilot-Anleitung für dieses Repo

Ziel: KI-Agents schnell produktiv machen für diesen Roblox + Rojo Endless Runner. Nur projektspezifische, verlässliche Muster – kurz und konkret.

### Überblick
- Architektur: Server-autoritativer Runner, Client nur Input/FX.
  - Server (`src/ServerScriptService/Main.server.lua`): Heartbeat-Loop für Vortrieb, Spur-Lerp, einfache Vertikalphysik, prozeduraler Track (Spawn/Cleanup), Kollisionen, Score/HUD, Powerups.
  - Client (`src/StarterPlayer/StarterPlayerScripts/Client.client.lua`): Input (Tastatur/Swipe), Kamera-Follow, lokaler Animator, HUD-Wiring, SFX.
  - Shared (`src/ReplicatedStorage/Shared/{Constants.lua,Animations.lua}`).
- Rojo-Datenmodell: `default.project.json` (authoritativ), `rojo.toml` konsistent halten. Pro Spieler: `Workspace/Tracks/<UserId>/Seg_%04d`.

### Workflow
- Start lokal: Rojo (`rojo serve`, via Aftman 7.4.4) und in Studio mit Plugin zu `localhost:34872` verbinden; Play drücken.
- Luau Strict (`--!strict`) beibehalten. Mapping-Änderungen in `default.project.json` (und `rojo.toml`) spiegeln.

### Spielregeln & Konventionen
- Lanes: `Constants.LANES = {-5, 0, 5}`, Start Mitte (Index 2). HRP dauerhaft 180° gedreht (blickt +Z).
- Spurwechsel: `LaneRequest(dir)` mit links=+1, rechts=-1 (bewusst invertiert, nicht ändern).
- Bewegung: Server besitzt NetworkOwner; Speed beschleunigt von `PLAYER.BaseSpeed` bis `MaxSpeed`; lateral Lerp mit `LaneSwitchSpeed`.
- Jump/Roll: einfache Gravitation; Roll mit kurzem Vorwärtsschub `PLAYER.RollBoost` und niedrigerer AABB.
- Track: `SPAWN.SegmentLength`, `ViewDistance`, Cleanup mit `CleanupBehind`; Segmente heißen `Seg_%04d`.
- Kollisionen: AABB-Scan 2 Studs vor HRP; Coins/Powerups via Attribute (`Powerup.Kind = "Magnet"|"Shield"`).

### Remotes (ReplicatedStorage/Remotes)
- `LaneRequest:FireServer(dir:number)` — Spurwechsel (links=+1, rechts=-1).
- `ActionRequest:FireServer("Jump"|"Roll")` — Eingaben.
- `ActionSync:FireClient(player,{action="Jump"|"Roll"})` — Server→Client Sync für lokale Animationen.
- `UpdateHUD:FireClient(player,{distance,coins,speed,magnet?,shield?})` — getaktet ~0,15s + bei Events.
- `CoinPickup`, `PowerupPickup`, `GameOver`, `RestartRequest` — SFX/Feedback/Reset.

### Client-Muster
- Input: A/D oder Pfeile → `LaneRequest`; W/Space → Jump; S → Roll; Mobile Swipes; `ContextActionService` bindet W/S (hohe Priorität, sink) und deaktiviert Default Controls.
- Kamera: Scriptable Follow im `RenderStepped`.
- Animationen: `Animate` deaktiviert; Animator lädt IDs aus `Shared/Animations.lua`; Run-Playback skaliert mit horizontaler Speed; Slide nutzt Platzhalter bis echte ID vorhanden.
- HUD: Minimal-HUD in `StarterGui/HUD.client.lua`; Singleton via `EndlessHUD`-Attribut (Duplikate werden entfernt).

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
