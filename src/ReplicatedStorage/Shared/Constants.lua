local Constants = {}

Constants.LANES = {
	-5, 0, 5, -- etwas schmalere Lanes für engere Subway-Surfers-Anmutung
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
	OverhangChance = 0.18, -- etwas häufiger
	ObstacleChance = 0.44,
	CoinChance = 0.28,
	PowerupChance = 0.08, -- Chance auf ein Powerup (Magnet oder Schild)
}

Constants.COLLISION = {
	ObstacleDamage = 1, -- simple hit value; can be expanded
	CoinValue = 1,
}

-- Powerup-Konfigurationen
Constants.POWERUPS = {
	Magnet = {
		Duration = 8.0, -- Sekunden
		Radius = 18.0,  -- Reichweite zum Einsammeln
		Weight = 0.6,   -- relative Gewichtung beim Spawnen
	},
	Shield = {
		Hits = 1,       -- absorbiert so viele Treffer (idR 1)
		Duration = 0,   -- 0 = nicht zeitbasiert
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
		8208591201,  -- Power Up
	},
	CrashSoundIds = {
	8595980577,  -- Error beep (kurz, neutral)
	},
}

return Constants
