## Copilot instructions for this repo

Purpose: Help AI agents contribute effectively to this Roblox + Rojo endless runner. Keep guidance concrete and specific to this codebase.

### Big picture
- Architecture: Server-authoritative runner with lightweight client input/FX.
  - Server loop: `src/ServerScriptService/Main.server.lua` (Heartbeat) handles forward motion, lane position, vertical physics, procedural track spawn/cleanup, collisions, score/HUD, and powerups.
  - Client: `src/StarterPlayer/StarterPlayerScripts/Client.client.lua` handles input (keyboard, mobile swipes), camera follow, local animations, HUD wiring, and SFX.
  - Shared config/assets: `src/ReplicatedStorage/Shared/{Constants.lua,Animations.lua}`.
- Data model via Rojo: see `default.project.json` (authoritative) and `rojo.toml` (kept aligned). Tracks are per-player under `Workspace/Tracks/<UserId>/Seg_XXXX`.

### Developer workflow
- Run locally: start Rojo, then connect Roblox Studio and press Play.
  - CLI: `rojo serve` (port 34872). Aftman pins: `aftman.toml` uses `rojo@7.4.4`.
  - In Studio: connect the Rojo plugin to `localhost:34872` and sync.
- Editing rules:
  - Keep mappings in `default.project.json` in sync with folder structure. Mirror changes in `rojo.toml` if used.
  - Use Luau strict mode (`--!strict`) as in existing files.

### Game mechanics and conventions
- Lanes: 3 lanes at X positions from `Constants.LANES = {-5, 0, 5}`; start in middle (index 2). Player HRP is rotated 180° (faces +Z back-to-camera).
- Movement: Server owns network authority (`HRP:SetNetworkOwner(nil)`), accelerates from `PLAYER.BaseSpeed` toward `MaxSpeed`. Lane changes lerp at `LaneSwitchSpeed`.
- Jump/Roll: Server vertical physics with simple gravity; roll grants short forward boost and a lower collision AABB. Use `Constants.PLAYER.{RollDuration, RollBoost}`.
- Procedural track: Spawns ground strips and lane content per segment length (`SPAWN.SegmentLength`), keeps `ViewDistance` ahead, cleans up `CleanupBehind`.
- Obstacles: `Obstacle` (solid block), `Overhang` (requires roll). Coins and powerups (`Powerup` with attribute `Kind = "Magnet"|"Shield"`). Collected parts get `Collected = true` then destroyed.
- Powerups: Magnet pulls nearby coins for `POWERUPS.Magnet.Duration` within `Radius`; Shield adds `ShieldHits` that consume on impact.

### Remote events and payloads
- ReplicatedStorage/Remotes is created on server startup. Names are stable; reuse these when extending:
  - `LaneRequest:FireServer(dir:number)` — lane change; note convention: left=+1, right=-1 (preserve this sign to match existing logic).
  - `ActionRequest:FireServer("Jump"|"Roll")` — input actions.
  - `UpdateHUD:FireClient(player, { distance, coins, speed, magnet?, shield? })` — throttled ~every 0.15s; also sent on coin pickup and state changes.
  - `CoinPickup:FireClient(player)` — play local SFX.
  - `PowerupPickup:FireClient(player, { kind })` — simple feedback hook.
  - `GameOver:FireClient(player)` + `RestartRequest:FireServer()` — game over UI and reset flow.

### Client patterns
- Input: A/D or Left/Right arrow keys call `LaneRequest` with inverted sign (intentional). W/Space triggers Jump, S triggers Roll via `ContextActionService` with high priority and sunk to block default controls. Basic swipe gestures for mobile are included.
- Camera: Scriptable follow from behind in `RenderStepped`.
- Animations: Default `Animate` is disabled. Local Animator loads IDs from `Shared/Animations.lua`; playback speed scales with horizontal speed. Replace asset IDs there (Roll uses a placeholder until you supply a real one).
- HUD: A minimal HUD is constructed in `StarterGui/HUD.client.lua` and reinforced in the client script. Singleton enforcement uses the `EndlessHUD` attribute and removes duplicates.
- Audio: Coin SFX is opt-in; set a valid `SoundId` string in `Client.client.lua` (currently empty) to enable.
  - Prefer central IDs in `Shared/Constants.lua` under `AUDIO`; avoid `rbxasset://` built-ins (Studio may fail). Use `rbxassetid://<number>`.

### When you change or add features
- Extend or add remotes under `ReplicatedStorage/Remotes` with clear names; keep server as the source of truth for movement/collisions.
- Respect the HUD throttle; bundle fields in one `UpdateHUD` payload rather than sending many events.
- Keep track folders and segment naming (`Seg_%04d`) consistent so cleanup logic works.
- Update `Constants.lua` instead of scattering magic numbers; prefer weights and chances under `SPAWN`/`POWERUPS`.
- Ensure any new parts spawned for gameplay set `Anchored=true`, correct `CanCollide/CanQuery/CanTouch` flags, and tags/attributes used by collision scans (`GetPartBoundsInBox/Radius`).

### Key files
- `src/ServerScriptService/Main.server.lua` — core loop, spawning, collisions, remotes, game over.
- `src/StarterPlayer/StarterPlayerScripts/Client.client.lua` — input, camera, animations, HUD wiring.
- `src/StarterGui/HUD.client.lua` — HUD bootstrap/singleton.
- `src/ReplicatedStorage/Shared/Constants.lua` — tune speed/spawn/powerups.
- `src/ReplicatedStorage/Shared/Animations.lua` — replace animation asset IDs.
- `default.project.json` / `rojo.toml` — Rojo mapping.

### Agent workflow on this repo
- Treat `README.md` as the canonical ToDo/roadmap. On each session:
  1) Read the ToDo sections and pick the topmost unchecked, low-risk item.
  2) Implement the change with minimal edits; prefer updating `Constants.lua` over scattering values.
  3) Update `README.md` by checking the item and adding a brief status note with date.
  4) If you add/remap files/folders, keep `default.project.json` (and `rojo.toml` if used) in sync.
  5) Respect HUD update throttling and remote naming conventions.
- Keep this file updated only when conventions change; log progress in `README.md`, not here.
