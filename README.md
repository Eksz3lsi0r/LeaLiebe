# LeaPopel Endless Runner (Roblox + Rojo)

A minimal endless runner game scaffold for Roblox, set up to sync with Rojo.

Features
- Auto-forward runner with 3 lanes (left, center, right)
- Lane switching via A/D or Left/Right arrow keys
- Procedural track segments with obstacles and coins
- Simple HUD for distance and coins
- Server-authoritative movement and collisions

## Requirements
- Roblox Studio
- Rojo (CLI)
- Optional: Rojo Studio plugin (for one-click sync inside Studio)

## Install Rojo (macOS)
You can use either Homebrew or Aftman. Pick one.

- Homebrew (simple):
  - brew install rojo-rbx/rojo/rojo

- Aftman (toolchain manager):
  - brew install aftman/tap/aftman
  - aftman init
  - aftman add rojo-rbx/rojo (or use the included aftman.toml)
  - aftman install

## Project Structure
- `default.project.json` — Rojo project file
- `src/` — Roblox data model mapped by Rojo
  - `ReplicatedStorage/` — shared config and remotes
  - `ServerScriptService/` — server code
  - `StarterPlayer/StarterPlayerScripts/` — client-side input and HUD
  - `StarterGui/` — HUD bootstrap
  - `Workspace/` — world items (Tracks folder, SpawnLocation)

## How to Run
1) Open Roblox Studio and create a new empty place (e.g., Baseplate). Save it anywhere.
2) In a terminal, start Rojo in this folder:
   - rojo serve
3) In Roblox Studio, connect to Rojo:
   - Using the Rojo plugin: click “Sync” to connect to localhost (default port 34872)
   - Or from the Studio command bar, use the plugin UI; the CLI `serve` is already running
4) Press Play in Studio. Your character will auto-run; use A/D or Left/Right to change lanes.

## Notes
- This scaffold assumes single-player or casual multiplayer; each player gets their own procedural track under `Workspace/Tracks/<UserId>`.
- Tweak `src/ReplicatedStorage/Shared/Constants.lua` to adjust difficulty, speed, spawn rates, etc.
- If movement looks jittery, ensure the server owns network authority of the runner (the code sets it); Studio perf can vary.

## Troubleshooting
- If Rojo doesn’t connect, confirm the CLI is running and the port (default 34872) is open. The plugin should point to `http://localhost:34872`.
- If assets don’t appear, check the Output window for errors and verify the Rojo tree matches (`default.project.json`).
