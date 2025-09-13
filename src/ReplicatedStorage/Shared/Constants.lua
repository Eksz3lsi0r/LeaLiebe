local Constants = {}

-- Globale Debug-Schalter (keine Runtime-Kosten im Normalfall)
Constants.DEBUG_LOGS = false

Constants.LANES = {
    -5,
    0,
    5, -- etwas schmalere Lanes für engere Subway-Surfers-Anmutung
}

Constants.PLAYER = {
    BaseSpeed = 28, -- studs/sec forward
    MaxSpeed = 60,
    LaneSwitchSpeed = 24, -- studs/sec lateral (Basiswert)
    LaneSwitchFactor = 2.0, -- Multiplikator für effektive Spurwechsel-Geschwindigkeit (z.B. 2.0 = doppelt so schnell)
    Acceleration = 0.025, -- per second
    -- Roll-Parameter: kurzer Vorwärtsschub für sichtbares "Abtauchen" unter Overhang
    RollDuration = 0.6, -- Sekunden
    RollBoost = 14, -- zusätzliche studs/sec während der RollDuration
}

Constants.SPAWN = {
    SegmentLength = 80, -- studs per segment along +Z
    ViewDistance = 8, -- number of segments to keep spawned ahead
    CleanupBehind = 3, -- number of segments to keep behind before cleanup
    -- Spawnchancen pro Lane (werden sequenziell ausgewertet)
    -- Ziel: ~0.78 Belegung pro Lane und Segment (Rest = leer für Lesbarkeit/Decision Time)
    OverhangChance = 0.12, -- etwas seltener, da schwer (Roll nötig)
    ObstacleChance = 0.36, -- generische Hindernisse
    CoinChance = 0.24, -- Coins moderat
    PowerupChance = 0.06, -- Chance auf ein Powerup (Magnet oder Schild)
    -- Deko-Wahrscheinlichkeit pro Segment (separate, optionale Spawns außerhalb der Lanes)
    DecoChance = 0.28, -- etwas reduziert, weniger Clutter an den Rändern
    -- Erweiterte Patterns (zusätzlich zu Einzelspawns), werden pro Segment probabilistisch geprüft
    Patterns = {
        CoinLine = 0.28, -- gerade Coin-Linie (6–8 Coins)
        CoinZigZag = 0.14, -- Coins wechseln die Lane (Zickzack)
        LaneBlocker = 0.10, -- zwei Lanes blockiert, eine frei
        Mover = 0.10, -- bewegliches Hindernis (Seitwärts-Oszillator in einer Lane)
    },
}

Constants.COLLISION = {
    ObstacleDamage = 1, -- simple hit value; can be expanded
    CoinValue = 1,
}

-- Scoring/Multiplikator (beeinflusst Coins pro Pickup)
Constants.SCORE = {
    StreakStep = 10, -- alle X Coins steigt der Multiplikator
    MultiplierPerStep = 0.1, -- Zuwachs pro Step
    MaxMultiplier = 3.0, -- Obergrenze
}

-- Dynamische Events (z. B. Double Coins)
Constants.EVENTS = {
    DoubleCoins = {
        Duration = 60.0, -- Sekunden
        Multiplier = 2, -- wie viele Coins pro Pickup
        StartChancePerSegment = 0.12, -- Chance je Segmentfortschritt, wenn kein Event aktiv
    },
}

-- Powerup-Konfigurationen
Constants.POWERUPS = {
    Magnet = {
        Duration = 8.0, -- Sekunden
        Radius = 18.0, -- Reichweite zum Einsammeln
        Weight = 0.6, -- relative Gewichtung beim Spawnen
    },
    Shield = {
        Hits = 1, -- absorbiert so viele Treffer (idR 1)
        Duration = 0, -- 0 = nicht zeitbasiert
        Weight = 0.4,
    },
}

-- Audio-IDs (Roblox Asset IDs). 0 = deaktiviert
Constants.AUDIO = {
    -- Kandidatenlisten: Der Client versucht die IDs nacheinander.
    CoinSoundIds = {
        3125624765, -- UI Collect/Pickup
    },
    -- Jump-Sound(s): erster abspielbarer Eintrag wird genutzt
    JumpSoundIds = {
        100936483086925,
    },
    -- Slide-Sound(s) (vormals Roll)
    SlideSoundIds = {
        104298925753512,
    },
    PowerupSoundIds = {
        8208591201, -- Power Up
    },
    CrashSoundIds = {
        8595980577, -- Error beep (kurz, neutral)
    },
    -- Zentrale Lautstärken fr den SFX-Mix (Client liest diese Werte)
    SFXVolumes = {
        Master = 1.0, -- globaler Multiplikator fr alle SFX
        Coin = 0.5,
        Jump = 0.6,
        Slide = 0.6,
        Powerup = 0.6,
        Crash = 0.8,
    },
    -- Hintergrundmusik (Loop) – Kandidatenliste (IDs mit Zugriff freigeben)
    MusicLoopIds = {
        -- 0, -- trage hier rbxassetid Zahlen ein (z. B. eigene Loops)
    },
    -- Musik-Lautstärke & Ducking
    MusicVolume = 0.45, -- Basislautstärke für den Loop
    MusicDuck = {
        FadeOut = 0.18, -- s
        FadeIn = 0.30, -- s
        GameOver = 0.35, -- Faktor der Basislautstärke bei GameOver (bleibt geduckt)
        Powerup = 0.70, -- Faktor der Basislautstärke bei Powerup-Pickup (temporär)
        PowerupHold = 1.2, -- s haltedauer, bevor wieder eingeblendet wird
    },
}

-- Animation-Feinjustage
Constants.ANIMATION = {
    RunPlayback = {
        -- Bei dieser Vorwärtsgeschwindigkeit (studs/sec) spielt der Run-Loop mit Rate 1.0
        SpeedAtRate1 = 28,
        -- Rate-Klammern für sehr langsame/schnelle Passagen
        MinRate = 0.9,
        MaxRate = 1.8,
        -- Nichtlineare Skalierung (1.0 = linear)
        Exponent = 1.0,
        -- Glättungszeitkonstante (Sekunden) für die gemessene Geschwindigkeit
        SmoothTau = 0.20,
        -- Mindestens nötige Rate-Änderung, bevor AdjustSpeed aufgerufen wird
        ChangeThreshold = 0.03,
    },
}

-- Biomes/Themes: Sequenz und sanfte Übergänge (Tag/Nacht, Stadt/Strand/Schnee)
-- Farben als RGB-Tripel; Server wandelt nach Color3 um und mischt während Transitionen.
Constants.BIOMES = {
    SegmentsPerBiome = 8, -- nach so vielen Segmenten erfolgt ein Theme-Wechsel
    TransitionDuration = 3.0, -- Sekunden für sanften Lighting-Blend
    List = {
        {
            name = "CityDay",
            groundColor = { 59, 59, 59 },
            ambient = { 130, 130, 130 },
            outdoorAmbient = { 140, 140, 140 },
            fogColor = { 200, 210, 220 },
            fogEnd = 400,
            clockTime = 14,
        },
        {
            name = "CityNight",
            groundColor = { 40, 40, 50 },
            ambient = { 40, 40, 60 },
            outdoorAmbient = { 20, 20, 30 },
            fogColor = { 40, 50, 70 },
            fogEnd = 250,
            clockTime = 20,
        },
        {
            name = "BeachDay",
            groundColor = { 200, 185, 120 }, -- sandig
            ambient = { 180, 180, 160 },
            outdoorAmbient = { 200, 200, 180 },
            fogColor = { 220, 230, 240 },
            fogEnd = 500,
            clockTime = 13,
        },
        {
            name = "BeachNight",
            groundColor = { 130, 120, 80 },
            ambient = { 60, 60, 80 },
            outdoorAmbient = { 40, 40, 60 },
            fogColor = { 50, 60, 80 },
            fogEnd = 280,
            clockTime = 21,
        },
        {
            name = "SnowDay",
            groundColor = { 240, 245, 250 },
            ambient = { 200, 200, 220 },
            outdoorAmbient = { 210, 210, 230 },
            fogColor = { 230, 235, 245 },
            fogEnd = 420,
            clockTime = 12,
        },
        {
            name = "SnowNight",
            groundColor = { 210, 215, 225 },
            ambient = { 80, 80, 110 },
            outdoorAmbient = { 60, 60, 90 },
            fogColor = { 70, 80, 100 },
            fogEnd = 260,
            clockTime = 22,
        },
    },
}

return Constants
