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
- [ ] Aftman Toolchain-Hinweise in Doku aufnehmen

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
- [ ] Weitere Hindernisvarianten und Deko-Bausteine

## Kollisionen & Powerups
- [x] Overlap-Box 2 Studs vor dem HRP, `RespectCanCollide=false`, Player excluded
- [x] Magnet zieht Coins an (Radius, sanftes Step-Movement)
- [x] Shield reduziert bei Treffer `ShieldHits` und zerstört Hindernis
- [ ] Balancing von Chancen/Weights in `Constants.lua`

## HUD & UI
- [x] HUD (Distance/Coins/Speed; Magnet/Shield optional)
  - Stand: `StarterGui/HUD.client.lua` + Client-Singleton-Logik.
- [x] GameOver-Overlay mit Restart-Flow
- [ ] Buttons Hauptmenü/Shop mit echter Logik hinterlegen
- [ ] HUD-Design/Styling verbessern

## Input
- [x] Keyboard: A/D, Pfeile links/rechts (invertierte Richtung)
- [x] Jump auf W/Space, Slide (vormals Roll) auf S via `ContextActionService` (hohe Priorität, sink)
- [x] Mobile: einfache Swipe-Gesten
- [ ] Gamepad-Unterstützung

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
- [ ] Eigene Asset-IDs in `Shared/Animations.lua` pflegen (Slide ist Platzhalter)
- [ ] Echte Slide-Animation einbinden

## Networking & Struktur
- [x] Remotes: `LaneRequest`, `ActionRequest`, `UpdateHUD`, `CoinPickup`, `PowerupPickup`, `GameOver`, `RestartRequest`
- [x] Pro-Spieler-Track unter `Workspace/Tracks/<UserId>` + `Seg_%04d`
- [ ] Optionale Persistenz (Highscore/Coins)

## Testing & Polish
- [ ] Performance-Check (Studio/Client), Jitter minimieren
- [ ] Edge Cases: Respawn/Wiederbeitritt/Mehrspieler
- [ ] Code Cleanup, Kommentare, Typen schärfen

## How to Run (Kurz)
1) VS Code öffnet Projekt → Rojo startet automatisch (Tasks).
2) In Roblox Studio mit Rojo verbinden (localhost:34872) und Play drücken.
3) Steuern: A/D oder Pfeile (Spur), W/Space (Jump), S (Roll), Mobile Swipe.

