# Changelog

Alle wichtigen Änderungen an diesem Projekt werden in dieser Datei dokumentiert.

Das Format basiert auf [Keep a Changelog](https://keepachangelog.com/de/1.0.0/),
und dieses Projekt folgt [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Projektweite Konfigurationsdateien aktualisiert
- GitHub Actions Workflow für CI/CD
- Vollständige Entwickler-Dokumentation
- CONTRIBUTING.md für Beitragsleitlinien

### Changed
- `rojo.toml` synchronisiert mit `default.project.json`
- `wally.toml` auf v0.3.0 mit aktuelleren Dependencies
- `.gitignore` erweitert für bessere Abdeckung

## [0.2.0] - 2025-09-13

### Added
- Arena RPG Basis-Architektur
- Server-autoritatives Combat-System Design
- Remote Events für Combat/Movement/Matchmaking
- Klassen-System Grundlage (Warrior/Mage/Archer)
- Arena-Management Server-Side Logic

### Changed  
- Projekt-Pivot von Endless Runner zu Arena RPG
- Rojo-Struktur für Arena-basierte Gameplay
- Combat-System von Client- zu Server-autoritativ

### Technical
- Luau Strict Mode für alle Dateien
- ModuleScript-basierte Architektur
- Shared Constants für Konfiguration

## [0.1.0] - 2025-09-01

### Added
- Initiales Rojo-Projekt Setup
- VS Code Integration mit Luau LSP
- StyLua Auto-Formatierung
- Selene Linting-Konfiguration
- Aftman Tool-Management
- Wally Package-Manager Setup

### Technical
- `default.project.json` Rojo-Konfiguration
- Development-Workflow mit Live-Sync
- Basis Folder-Struktur für Roblox-Projekt