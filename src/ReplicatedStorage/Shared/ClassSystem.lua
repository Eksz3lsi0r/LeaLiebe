--!strict
-- Klassen-System für Arena RPG - 5 verschiedene Spielerklassen

local ClassSystem = {}

export type ClassData = {
    Name: string,
    Description: string,
    Icon: string,
    Color: Color3,
    BaseHealth: number,
    BaseMana: number,
    BaseStamina: number,
    HealthPerLevel: number,
    ManaPerLevel: number,
    StaminaPerLevel: number,
    StrengthGrowth: number,
    IntelligenceGrowth: number,
    DefenseGrowth: number,
    Spells: {string},
    HealingBonus: number?,
    ManaRegenBonus: number?,
    AttackDamageBonus: number?,
    AttackSpeedBonus: number?,
    CriticalChance: number?,
    RangedDamageBonus: number?,
    RangeBonus: number?,
    AccuracyBonus: number?,
    MagicDamageBonus: number?,
    ManaCostReduction: number?,
    SpellCriticalChance: number?,
    DamageReduction: number?,
    ThreatMultiplier: number?,
    BlockChance: number?,
    HealthRegenBonus: number?,
}

-- Klassen-Definitionen
ClassSystem.CLASSES = {
    Healer = {
        Name = "Healer",
        Description = "Unterstützt das Team mit Heilzaubern und Schutz",
        Icon = "🔮",
        Color = Color3.fromRGB(100, 255, 100), -- Grün

        -- Basis-Stats
        BaseHealth = 80,
        BaseMana = 100,
        BaseStamina = 80,

        -- Stat-Multiplikatoren pro Level
        HealthPerLevel = 8,
        ManaPerLevel = 15,
        StaminaPerLevel = 6,

        -- Attribut-Schwerpunkte
        StrengthGrowth = 1,
        IntelligenceGrowth = 3, -- Haupt-Attribut
        DefenseGrowth = 2,

        -- Verfügbare Zaubersprüche
        Spells = { "Heal", "MagicShield", "GroupHeal", "Purify", "Resurrection" },

        -- Klassen-spezifische Boni
        HealingBonus = 1.5, -- 50% mehr Heilung
        ManaRegenBonus = 1.3, -- 30% schnellere Mana-Regeneration
    },

    MeleeDPS = {
        Name = "Melee DPS",
        Description = "Nahkampf-Schadensspezialist mit hoher Mobilität",
        Icon = "⚔️",
        Color = Color3.fromRGB(255, 100, 100), -- Rot

        BaseHealth = 120,
        BaseMana = 40,
        BaseStamina = 120,

        HealthPerLevel = 12,
        ManaPerLevel = 4,
        StaminaPerLevel = 12,

        StrengthGrowth = 3, -- Haupt-Attribut
        IntelligenceGrowth = 1,
        DefenseGrowth = 2,

        Spells = { "Charge", "WhirlwindAttack", "BerserkerRage", "ExecuteStrike", "Dodge" },

        AttackDamageBonus = 1.4, -- 40% mehr Nahkampfschaden
        AttackSpeedBonus = 1.2, -- 20% schnellere Angriffe
        CriticalChance = 0.15 -- 15% Kritische Trefferchance
    },

    RangeDPS = {
        Name = "Range DPS",
        Description = "Fernkampf-Spezialist mit Pfeil und Bogen",
        Icon = "🏹",
        Color = Color3.fromRGB(100, 255, 255), -- Cyan

        BaseHealth = 100,
        BaseMana = 60,
        BaseStamina = 100,

        HealthPerLevel = 10,
        ManaPerLevel = 6,
        StaminaPerLevel = 10,

        StrengthGrowth = 2,
        IntelligenceGrowth = 2,
        DefenseGrowth = 2, -- Ausgewogen

        Spells = { "PowerShot", "ArrowRain", "PiercingArrow", "ExplosiveArrow", "EagleEye" },

        RangedDamageBonus = 1.5, -- 50% mehr Fernkampfschaden
        RangeBonus = 1.3, -- 30% größere Reichweite
        AccuracyBonus = 1.2, -- Bessere Treffergenauigkeit
    },

    MagicDPS = {
        Name = "Magic DPS",
        Description = "Mächtiger Zauberer mit verheerenden Zaubersprüchen",
        Icon = "🔥",
        Color = Color3.fromRGB(255, 100, 255), -- Magenta

        BaseHealth = 70,
        BaseMana = 120,
        BaseStamina = 70,

        HealthPerLevel = 7,
        ManaPerLevel = 18,
        StaminaPerLevel = 6,

        StrengthGrowth = 1,
        IntelligenceGrowth = 3, -- Haupt-Attribut
        DefenseGrowth = 1,

        Spells = { "Fireball", "Lightning", "Meteor", "Blizzard", "ArcaneBlast" },

        MagicDamageBonus = 1.6, -- 60% mehr Zauber-Schaden
        ManaCostReduction = 0.8, -- 20% weniger Mana-Kosten
        SpellCriticalChance = 0.2 -- 20% Kritische Zauber
    },

    Tank = {
        Name = "Tank",
        Description = "Robuster Verteidiger der das Team schützt",
        Icon = "🛡️",
        Color = Color3.fromRGB(150, 150, 255), -- Blau

        BaseHealth = 150,
        BaseMana = 50,
        BaseStamina = 120,

        HealthPerLevel = 18,
        ManaPerLevel = 5,
        StaminaPerLevel = 12,

        StrengthGrowth = 2,
        IntelligenceGrowth = 1,
        DefenseGrowth = 3, -- Haupt-Attribut

        Spells = { "Taunt", "DefensiveStance", "ShieldWall", "Provoke", "Fortify" },

        DamageReduction = 0.7, -- 30% Schadensreduzierung
        ThreatMultiplier = 2.0, -- Zieht Aufmerksamkeit der Gegner
        BlockChance = 0.25, -- 25% Block-Chance
        HealthRegenBonus = 1.4 -- 40% schnellere Heilung
    },
}

-- Hilfsfunktionen
function ClassSystem.getClassData(className: string)
    return ClassSystem.CLASSES[className]
end

function ClassSystem.getAllClasses()
    local classes = {}
    for className, _ in pairs(ClassSystem.CLASSES) do
        table.insert(classes, className)
    end
    return classes
end

export type ClassStats = {
    Health: number,
    Mana: number,
    Stamina: number,
    Strength: number,
    Intelligence: number,
    Defense: number,
}

function ClassSystem.calculateStats(className: string, level: number): ClassStats?
    local classData = ClassSystem.getClassData(className)
    if not classData then
        return nil
    end

    return {
        Health = (classData.BaseHealth :: number) + ((classData.HealthPerLevel :: number) * (level - 1)),
        Mana = (classData.BaseMana :: number) + ((classData.ManaPerLevel :: number) * (level - 1)),
        Stamina = (classData.BaseStamina :: number) + ((classData.StaminaPerLevel :: number) * (level - 1)),
        Strength = (classData.StrengthGrowth :: number) * level,
        Intelligence = (classData.IntelligenceGrowth :: number) * level,
        Defense = (classData.DefenseGrowth :: number) * level,
    }
end

function ClassSystem.getAvailableSpells(className: string)
    local classData = ClassSystem.getClassData(className)
    return classData and classData.Spells or {}
end

return ClassSystem
