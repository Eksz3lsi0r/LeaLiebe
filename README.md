# Projekt-ToDo: LeaPopel Subway-Surfers-Style Endless Runner

Diese Datei ist die zentrale ToDo-/Roadmap-Liste. Hake Punkte ab, ergänze kurze Status-Notizen (mit Datum), und verweise bei Bedarf auf relevante Dateien.

Hinweis zu Steuerung/Konventionen
- Spurwechsel: `LaneRequest(dir)` mit links=+1, rechts=-1 (bewusst invertiert auf dem Client).
- HUD-Updates via `UpdateHUD` sind getaktet (~0,15s) und bündeln Felder.
- Server ist autoritativ; HRP `SetNetworkOwner(nil)` beibehalten.

## Setup & Tooling
- [x] Rojo Mappings gepflegt (`default.project.json`, `rojo.toml`)
  - Stand: Struktur vorhanden; Tracks unter `Workspace/Tracks/<UserId>` mit `Seg_%04d`.
- [x] VS Code Task für Rojo Serve (Auto-Start bei Ordner-Öffnen)
  - Stand: `tasks.json` startet Rojo automatisch.
- [x] Toolchain gepinnt in `aftman.toml`
  - Rojo, `luau-lsp`, `stylua`, `selene` — bereits eingerichtet; keine weiteren Install-Schritte nötig.

## Core Gameplay
- [x] 3 Spuren X={-5,0,5}, Start Mitte
  - Stand: `Shared/Constants.lua` (LANES).
- [x] Server-autoritative Vorwärtsbewegung mit Beschleunigung/MaxSpeed
  - Stand: `Main.server.lua` (Heartbeat, Acceleration, MaxSpeed).
- [x] Spurwechsel per Lerp mit `LaneSwitchSpeed`
- [x] Sprung & Rollen (RollDuration, RollBoost) inkl. niedrigerer AABB beim Rollen
  - Stand: Kollisionsbox dynamisch (Höhe 2.2 bei Roll).
  - 26.08.2025: Input-Gating serverseitig: Jump/Slide nur aus Run; doppeltes Triggern verhindert; Jump cancel → sofortige Roll (S in der Luft startet Roll sofort); aus aktiver Roll triggert W/Space direkt Jump.
- [x] Kamera Follow (hinter dem Spieler)
  - Stand: `Client.client.lua` (RenderStepped).

## Procedural Track & Objekte
- [x] Segment-Spawn, ViewDistance, CleanupBehind
- [x] Hindernisse: Obstacle, Overhang (nur mit Roll passierbar)
- [x] Coins
- [x] Powerups: Magnet (Radius/Duration), Shield (ShieldHits)
- [x] Weitere Hindernisvarianten und Deko-Bausteine
  - 26.08.2025: Obstacle-Varianten (tall/low/wide) visuell ergänzt, Kollision weiter unter "Obstacle"; einfache Deko (Post/Crate/Fence) außerhalb der Lanes mit `SPAWN.DecoChance`.

## Kollisionen & Powerups
- [x] Overlap-Box 2 Studs vor dem HRP, `RespectCanCollide=false`, Player excluded
- [x] Magnet zieht Coins an (Radius, sanftes Step-Movement)
- [x] Shield reduziert bei Treffer `ShieldHits` und zerstört Hindernis
- [x] Balancing von Chancen/Weights in `Constants.lua`
  - 26.08.2025: Spawn-Chancen neu justiert: Overhang 0.12, Obstacle 0.36, Coin 0.24, Powerup 0.06; DecoChance 0.28. Ziel: weniger Clutter, klarere Entscheidungen, stabilere Difficulty-Rampe.

## HUD & UI
- [x] HUD (Distance/Coins/Speed; Magnet/Shield optional)
  - Stand: `StarterGui/HUD.client.lua` + Client-Singleton-Logik.
- [x] GameOver-Overlay mit Restart-Flow
- [x] Buttons Hauptmenü/Shop mit echter Logik hinterlegen
  - 26.08.2025: Menü-/Shop-Buttons hinzugefügt (Restart via Remote, Shop-Kauf Shield1 für 5 Coins). Remotes: `ShopPurchaseRequest`, `ShopResult`.
- [x] HUD-Design/Styling verbessern (Fonts, Farben, Padding, Autoscale)
  - 26.08.2025: Theming + Autoscaling für Labels/Buttons/Panels/Toast; UI-Rundungen/Stroke; keine per-Frame Allokationen.
- [x] Accessibility: Farbkontrast prüfen, ScreenShake-/Effekte-Toggle
  - 26.08.2025: High-Contrast-Theme-Toggle + Effekte/SFX Toggle (Client), Zustände als PlayerGui-Attribute; HUD restylt bei Umschaltung.
- [ ] HUD-Design/Styling verbessern

## Input
- [x] Keyboard: A/D, Pfeile links/rechts (invertierte Richtung)
- [x] Jump auf W/Space, Slide (vormals Roll) auf S via `ContextActionService` (hohe Priorität, sink)
- [x] Mobile: einfache Swipe-Gesten
- [x] Gamepad-Unterstützung
  - 26.08.2025: A=Jump, B=Roll, DPad links/rechts und linker Stick (mit Hysterese) für Spurwechsel; via `ContextActionService` mit hoher Priorität gebunden. Server‑Authority/Remotes respektiert.

## Audio & Effekte
- [x] Coin-SFX Asset-IDs setzen
  - 26.08.2025: Mehrere Kandidaten in `Constants.AUDIO.CoinSoundIds`; Client probiert der Reihe nach.
- [x] Powerup SFX/VFX (SFX)
  - 26.08.2025: Kandidaten in `Constants.AUDIO.PowerupSoundIds`; Client spielt beim Pickup.
- [x] Crash/GameOver SFX
  - 26.08.2025: Kandidaten in `Constants.AUDIO.CrashSoundIds`; Client spielt beim GameOver.
- [x] Jump/Slide SFX
  - 26.08.2025: Jump `100936483086925` und Slide `104298925753512` in `Constants.AUDIO` verdrahtet; Abspiel bei Input auf Client.

## Assets & Animationen
- [x] Default `Animate` deaktiviert; eigener `Animator`
- [x] Eigene Asset-IDs in `Shared/Animations.lua` gepflegt (Slide ersetzt)
  - 26.08.2025: Slide-ID auf eigenes Asset `128234664490731` aktualisiert; Fallback-Logik verbleibt im Client (bei fehlendem Zugriff wird Slide ausgelassen).
- [x] Echte Slide-Animation einbinden
  - 26.08.2025: Eigene Slide-Animation eingetragen (`128234664490731`); Zugriff ggf. in Studio über "Click to share access" freigeben.
  - 26.08.2025: State-Transitions (Run→Jump→Roll) geglättet: kurzer Delay vor Fall-Start, Landed/Running reset; Client/Server bleiben autoritativ synchron (ActionSync).
  - 26.08.2025: Run-PlaybackRate skaliert jetzt sauber mit Vorwärtsgeschwindigkeit (Z), konfigurierbar in `Constants.ANIMATION.RunPlayback` (SpeedAtRate1, Min/MaxRate, Exponent, Glättung).

## Networking & Struktur
- [x] Remotes: `LaneRequest`, `ActionRequest`, `UpdateHUD`, `CoinPickup`, `PowerupPickup`, `GameOver`, `RestartRequest`
  - 26.08.2025: Shop-Remotes ergänzt: `ShopPurchaseRequest`, `ShopResult`.
- [x] Pro-Spieler-Track unter `Workspace/Tracks/<UserId>` + `Seg_%04d`
- [x] Optionale Persistenz (Highscore/Coins)
  - 26.08.2025: DataStore-Persistenz minimal-invasiv: Load auf Join, Apply Coins ins HUD nach Runner-Erstellung, Save bei Shop-Kauf, GameOver, PlayerRemoving und Server-Shutdown. Key: `EndlessRunner_v1:u_<UserId>`; Felder `{coins,best}`. Safe `pcall`, Cache im Speicher.

## Testing & Polish
- [x] Performance-Check (Studio/Client), Jitter minimieren
  - 26.08.2025: Per-Frame-Allocations reduziert (OverlapParams/Filter-Reuse serverseitig, RenderStepped-Loop konsolidiert), Debug-Logs hinter Flag `Constants.DEBUG_LOGS` gelegt, Client-HUD-Print entfernt. HUD-Throttle bleibt bei ~0,15 s. Erwartung: weniger GC-Spikes, stabilere FPS.
- [x] Edge Cases: Respawn/Wiederbeitritt/Mehrspieler
  - 26.08.2025: Respawn/CharacterAdded bereinigt jetzt alte Tracks und verhindert Doppel-Init; Kollisionsabfragen filtern strikt pro Spieler-Track (Include) → keine Cross-Pickups; Magnet-Dauer stapelt bei Mehrfach-Pickup; Restart bleibt idempotent.
- [ ] Code Cleanup, Kommentare, Typen schärfen
  - 26.08.2025: Luau-Typen für HUD-Payload/Animations ergänzt, Kommentare zu Server-Authority/Lane-Konvention/Kollisionsfilter; kleine Refactors ohne Verhaltensänderung.
  - [x] Code Cleanup, Kommentare, Typen schärfen

## How to Run (Kurz)
1) VS Code öffnet Projekt → Rojo startet automatisch (Tasks).
2) In Roblox Studio mit Rojo verbinden (localhost:34872) und Play drücken.
3) Steuern: A/D oder Pfeile (Spur), W/Space (Jump), S (Roll), Mobile Swipe; Gamepad: A (Jump), B (Roll), DPad L/R oder linker Stick L/R (Spur).

## AAA Quality Bar & KPIs
Zielwerte und Leitplanken für ein „AAA“-Gefühl (Subway‑Surfers‑ähnlich):
- Performance: 60 FPS Ziel; RenderStepped ohne Allokationen im Client (`src/StarterPlayer/StarterPlayerScripts/Client.client.lua`), Instanzen cachen. Microprofiler/ScriptProfiler regelmäßig prüfen.
- Netzwerk: Server bleibt autoritativ; `HumanoidRootPart:SetNetworkOwner(nil)` ist gesetzt (`src/ServerScriptService/Main.server.lua`). HUD-Updates sind auf ~0,15 s getaktet; Payload klein halten (Ganzzahlen, verbleibende Powerup‑Dauer in s).
- Eingabelatenz: <80 ms bis sichtbares Feedback. Client spielt SFX/Animation lokal über `Shared/Animations.lua` und `Constants.AUDIO`, Server bestätigt via `ActionSync`.
- Physik/Determinismus: Vortrieb/Spur-Lerp im Server-Heartbeat; keine Client‑Positionsschreibungen.
- Speicher: Striktes Cleanup hinter dem Spieler; perspektivisch Segment‑Pooling evaluieren (<350 MB auf Mobile).

## Production-Features (Roadmap)
- Inhalte
  - [ ] Weitere Hindernisvarianten (beweglich, mehrstufige Overhangs), Deko‑Prefabs; Weights in `src/ReplicatedStorage/Shared/Constants.lua` pflegen.
  - [x] Biomes/Themes (Tag/Nacht, Stadt/Strand/Schnee) mit sanften Übergängen.
    - 26.08.2025: Einfaches Biome-System (City/Beach/Snow × Day/Night), per `BIOMES` in Constants konfigurierbar; Ground-Farben pro Segment und Lighting-Blend bei Wechsel.
  - [ ] Dynamische Events (z. B. Double Coins 60 s).
  - [x] Dynamische Events (z. B. Double Coins 60 s).
    - 26.08.2025: Einfaches Double‑Coins‑Event serverseitig: Start mit Segment‑Chance, Dauer/Multiplikator in `Constants.EVENTS`. HUD zeigt Restzeit, Toast bei Start. Coins & Magnet‑Pull respektieren Multiplikator. HUD‑Throttle eingehalten.
- Powerups & VFX
  - [x] Sichtbares Magnet-/Shield‑VFX am Charakter; Restlaufzeit im HUD (`src/StarterGui/HUD.client.lua`).
    - 26.08.2025: Clientseitige VFX: dezenter Magnet‑ParticleEmitter am HRP für Magnet‑Dauer; ForceField‑Glanz für aktive Schild‑Hits; Zustände aus `UpdateHUD` (throttled). Minimal‑invasiv, performance‑arm.
    - 26.08.2025: HUD zeigt Restlaufzeiten: Magnet in Sekunden; Schild unterstützt optional zeitbasierte Dauer (ShieldTime) neben Hit‑Zähler. VFX folgen ShieldTime/Hit‑State.
  - [ ] Balancing von Dauer/Radius/Weights in `src/ReplicatedStorage/Shared/Constants.lua`.
- Animationen
  - [x] Echte Slide‑Animation in `src/ReplicatedStorage/Shared/Animations.lua` eintragen; State‑Transitions (Run→Jump→Roll) glätten.
  - [x] Run‑PlaybackRate skaliert mit Speed (Feinjustage per `Constants.ANIMATION`).
- Audio
  - [x] Musikloop + Ducking bei GameOver/Powerup; Finalisierung von `Constants.AUDIO` (Lautstärke normalisieren).
    - 26.08.2025: Client-seitiger Musik-Controller implementiert (Loop + Ducking). Gesteuert über `Constants.AUDIO.{MusicLoopIds,MusicVolume,MusicDuck}`. Hinweis: Trage eigene Musik-Asset-IDs in `MusicLoopIds` ein (Zugriff in Studio freigeben), sonst bleibt Musik aus; Ducking reagiert auf `GameOver` und `PowerupPickup` Remotes und respektiert `EffectsEnabled`.
  - [x] Lautstärken normalisiert (SFX-Mix über `Constants.AUDIO.SFXVolumes`)
    - 26.08.2025: Zentrale SFX-Lautstärken (`Master`, `Coin`, `Jump`, `Slide`, `Powerup`, `Crash`) eingeführt und im Client verdrahtet; harte Werte entfernt. Anpassung ohne Spielverhaltensänderung.
- UI/UX
  - [ ] HUD‑Feinschliff; Buttons Hauptmenü/Shop mit echter Logik.
  - [ ] Accessibility: Farbkontrast, ScreenShake‑Toggle.

## Testing & QA
- Automatisiert
  - [ ] Luau‑LSP/Format/Lint via Aftman (CI optional): `luau-lsp`, `stylua`, `selene`.
  - [x] CI (optional): Format (StyLua) & Lint (Selene) automatisiert.
    - 26.08.2025: GitHub Actions Workflow `.github/workflows/format-lint.yml` hinzugefügt: StyLua `--check`, Selene `src/`, und Rojo Sourcemap. Versionen gepinnt (StyLua 0.20.1, Selene 0.27.1, Rojo 7.4.4).
  - [x] Unit‑Tests für Utility-/Spawn‑Logik (TestEZ) – ggf. kleine Abstraktionen aus dem Server extrahieren.
    - 26.08.2025: `SpawnUtils` extrahiert (Biome-Index, Lane-Content, Powerup-Pick). TestEZ-Specs in `tests/`; Bootstrap `src/ServerScriptService/TestBootstrap.server.lua` (läuft nur in Studio bei `workspace:SetAttribute("RunTests", true)`).
- Manuell
  - [ ] Performance‑Matrix (Low‑End Mobile, Mid PC): FPS, GC‑Spikes, Remote‑Rate (UpdateHUD ~6–7 Hz).
  - [ ] Edge Cases: Respawn, Wiederbeitritt, Mehrspieler, Powerup‑Überlappungen.
- Telemetrie (dev)
  - [ ] Metriken: Distanz‑Lebenszeit, Death‑Reasons (Obstacle/Overhang), Coins/min; Debug‑Ausgabe abschaltbar.
  
Hinweis: DataStore in Studio testen
Tests in Studio ausführen (optional)
- In der Command Bar: `workspace:SetAttribute("RunTests", true)` setzen und Play starten. Ein `TestEZ`-ModuleScript muss im Spiel vorhanden sein (z. B. unter `ReplicatedStorage/TestEZ`).
- In Roblox Studio unter „Game Settings → Security“ API-Zugriff aktivieren.
- Während Play prüfen: Coins aufsammeln, sterben (GameOver), Spiel verlassen → Coins/Best sollten bei erneutem Join geladen werden.

## LiveOps & Monetarisierung (optional)
- [ ] Soft‑Currency/Coins persistieren (DataStore); Highscore pro User.
- [ ] Daily Missions/Quests; Login‑Streaks.
- [ ] Skins/Boards (nur Kosmetik; kein Pay2Win).

## Entwicklerhinweise (Querverweise)
- Serverkern: `src/ServerScriptService/Main.server.lua`
  - Remotes: LaneRequest, ActionRequest, ActionSync, UpdateHUD, CoinPickup, PowerupPickup, GameOver, RestartRequest
- Clientkern: `src/StarterPlayer/StarterPlayerScripts/Client.client.lua`
- Shared Konfig/Anims: `src/ReplicatedStorage/Shared/Constants.lua`, `src/ReplicatedStorage/Shared/Animations.lua`
- Rojo Mapping: `default.project.json`, `rojo.toml`

