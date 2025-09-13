--!strict
-- Arena RPG Konstanten - Combat, Player Stats, AI, Loot

local ArenaConstants = {}

-- Arena-System
ArenaConstants.ARENA = {
    Size = Vector3.new(50, 1, 50), -- 50x50 Studs Arena
    Center = Vector3.new(700, 3, 0), -- Arena-Position
    SpawnRadius = 20, -- Spawn-Kreis-Radius für Spieler
    EnemySpawnRadius = 25, -- Spawn-Radius für Gegner (weiter außen)
    WallHeight = 8, -- Höhe der Arena-Begrenzung
    MaxPlayersPerArena = 4, -- Maximale Spieleranzahl pro Arena
}

-- Spieler-Eigenschaften
ArenaConstants.PLAYER = {
    BaseHealth = 100,
    BaseMana = 50,
    BaseStamina = 100,
    MoveSpeed = 16, -- studs/sec
    RotationSpeed = 720, -- degrees/sec

    -- Regeneration (außerhalb Kampf)
    HealthRegenRate = 5, -- HP/sec
    ManaRegenRate = 8, -- MP/sec
    StaminaRegenRate = 15, -- Stamina/sec
    OutOfCombatTime = 5, -- Sekunden ohne Schaden für Regen

    -- Leveling
    StartLevel = 1,
    MaxLevel = 10,
    BaseStatPoints = 10,
    StatPointsPerLevel = 2,
}

-- Combat-System
ArenaConstants.COMBAT = {
    -- Melee
    BaseAttackDamage = 15,
    AttackRange = 5, -- Studs
    AttackCooldown = 1.2, -- Sekunden
    ComboWindow = 2.0, -- Zeit für Kombos
    MaxComboHits = 3,
    ComboMultiplier = 1.2, -- Schaden-Multiplikator für Kombos

    -- Block/Parry
    BlockReduction = 0.5, -- 50% Schadensreduzierung
    ParryWindow = 0.3, -- Sekunden für perfektes Parieren
    ParryReflectMultiplier = 1.5, -- Reflektierter Schaden
    BlockStaminaCost = 10,

    -- Knockback & Stun
    BaseKnockback = 8, -- Studs
    StunDuration = 0.8, -- Sekunden
    KnockbackResistance = 0.1, -- je Level

    -- Status Effects
    MaxStatusEffects = 5,
    StatusTickRate = 0.5, -- Sekunden zwischen Ticks
}

-- Magie-System
ArenaConstants.MAGIC = {
    -- Spells
    Fireball = {
        ManaCost = 15,
        Damage = 25,
        Range = 30,
        Speed = 40,
        Cooldown = 2.5,
        Area = 0, -- 0 = Einzelziel
    },
    Heal = {
        ManaCost = 20,
        HealAmount = 35,
        Range = 0, -- Selbstheilung
        Cooldown = 4.0,
        Area = 8, -- Radius für Gruppenheilung
    },
    MagicShield = {
        ManaCost = 12,
        Duration = 8.0,
        DamageReduction = 0.3,
        Cooldown = 15.0,
    },
    Lightning = {
        ManaCost = 25,
        Damage = 40,
        Range = 25,
        Cooldown = 5.0,
        ChainTargets = 3,
    },
}

-- AI-Gegner
ArenaConstants.ENEMIES = {
    Dummy = {
        Health = 30,
        Damage = 8,
        MoveSpeed = 0, -- Bewegt sich nicht
        AttackRange = 0, -- Greift nicht an
        Gold = 5,
        Experience = 10,
    },
    Warrior = {
        Health = 80,
        Damage = 18,
        MoveSpeed = 12,
        AttackRange = 6,
        AttackCooldown = 1.8,
        AggroRange = 15,
        Gold = 15,
        Experience = 25,
        AI = "Aggressive", -- Aggressive, Defensive, Balanced
    },
    Archer = {
        Health = 60,
        Damage = 22,
        MoveSpeed = 10,
        AttackRange = 20,
        AttackCooldown = 2.2,
        AggroRange = 25,
        Gold = 20,
        Experience = 30,
        AI = "Ranged",
    },
    Mage = {
        Health = 50,
        Mana = 80,
        Damage = 30,
        MoveSpeed = 8,
        AttackRange = 15,
        AttackCooldown = 3.0,
        AggroRange = 20,
        Gold = 25,
        Experience = 40,
        AI = "Caster",
    },
}

-- Loot-System
ArenaConstants.LOOT = {
    -- Drop-Raten (0-1)
    WeaponDropRate = 0.15,
    ArmorDropRate = 0.12,
    ConsumableDropRate = 0.25,
    GoldDropRate = 0.8,

    -- Equipment-Typen
    WeaponTypes = { "Sword", "Axe", "Staff", "Bow" },
    ArmorTypes = { "Helmet", "Chestplate", "Boots" },
    ConsumableTypes = { "HealthPotion", "ManaPotion", "StrengthBoost" },

    -- Qualitätsstufen
    QualityLevels = {
        Common = { Color = Color3.fromRGB(200, 200, 200), StatMultiplier = 1.0 },
        Uncommon = { Color = Color3.fromRGB(30, 255, 30), StatMultiplier = 1.25 },
        Rare = { Color = Color3.fromRGB(50, 150, 255), StatMultiplier = 1.5 },
        Epic = { Color = Color3.fromRGB(200, 50, 255), StatMultiplier = 2.0 },
    },
}

-- Wave-System
ArenaConstants.WAVES = {
    InitialEnemies = 2,
    EnemiesPerWave = 1, -- Zusätzliche Gegner pro Welle
    MaxWave = 10,
    BossWave = 5, -- Alle X Wellen ein Boss
    WaveDelay = 3.0, -- Sekunden zwischen Wellen

    -- Difficulty Scaling
    HealthScaling = 1.15, -- +15% HP pro Welle
    DamageScaling = 1.1, -- +10% Damage pro Welle
    RewardScaling = 1.2, -- +20% Rewards pro Welle
}

-- HUD & UI
ArenaConstants.HUD = {
    UpdateRate = 0.15, -- Sekunden zwischen Updates
    DamageNumberDuration = 1.5, -- Floating Damage Numbers
    StatusEffectIconSize = 32,
    CooldownAnimationSpeed = 1.0,
    HealthBarColor = Color3.fromRGB(200, 50, 50),
    ManaBarColor = Color3.fromRGB(50, 100, 255),
    StaminaBarColor = Color3.fromRGB(255, 200, 50),
}

-- Audio
ArenaConstants.AUDIO = {
    AttackSoundIds = { 100936483086925 }, -- Placeholder
    BlockSoundIds = { 104298925753512 }, -- Placeholder
    SpellSoundIds = { 100936483086925 }, -- Placeholder
    DeathSoundIds = { 104298925753512 }, -- Placeholder
    LevelUpSoundIds = { 100936483086925 }, -- Placeholder
    LootDropSoundIds = { 104298925753512 }, -- Placeholder

    -- Lautstärke
    SFXVolume = 0.3,
    MusicVolume = 0.2,
}

-- Debug & Development
ArenaConstants.DEBUG = {
    ShowDamageNumbers = true,
    ShowAIStates = false,
    ShowCombatRanges = false,
    LogCombatEvents = false,
    InfiniteResources = false, -- Für Testing
    GodMode = false, -- Für Testing
}

return ArenaConstants
