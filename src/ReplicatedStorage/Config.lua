--!strict

-- Gemeinsame Konfiguration für das minimale Mario-2D-Setup
local Config = {}

Config.GRAVITY = 196.2
Config.JUMP_POWER = 75
Config.MOVE_SPEED = 20

-- 2D-Rail: Z-Achse wird gesperrt, der Spieler läuft nur auf X
Config.Z_LOCK = 0 -- kann bei Spawn dynamisch überschrieben werden

-- Kamera
Config.CAMERA = {
    Height = 8,
    DistanceZ = 22, -- seitlicher Abstand (Z)
    LookAheadX = 5, -- Blick etwas voraus Richtung +X
}

-- Lobby: große, flache Insel + Standard-Spawnposition
Config.LOBBY = {
    IslandSize = Vector3.new(400, 1, 200),
    IslandY = 0,
    Spawn = Vector3.new(0, 6, 0), -- X-Achse Mitte, leicht über Boden
    Color = Color3.fromRGB(90, 200, 120),
}

return Config
