--!strict
-- Central animation IDs (R15). Replace with your own assets as needed.
-- 0 or nil will skip loading that animation.

local Animations = {
    -- Basic Movement Animations (Legacy Endless Runner)
    -- Hinweis: In diesem Endless Runner sind Run und Walk identisch.
    -- Der echte, saubere Lauf-Loop ist die R15 Walk-Animation (507777826).
    -- Die frühere R15 "Run"-ID (507767714) enthält ein Start-Snippet und wirkt beim Loopen ruckelig.
    Run = 507777826, -- verwende den sauberen Loop
    Walk = 507777826, -- alias, falls irgendwo Walk referenziert wird
    Jump = 507765000, -- R15 Jump
    Fall = 507767968, -- R15 Fall
    -- Slide (vormals Roll): Eigene, bereitgestellte Slide-Animation (selfmade).
    -- Hinweis: Stelle sicher, dass die Experience Zugriff auf das Asset hat (Studio-Output: "Click to share access").
    -- Fallback-Mechanik bleibt bestehen: Wenn das Asset nicht geladen werden kann, wird Slide clientseitig ausgelassen.
    Slide = 128234664490731,

    -- Arena RPG Combat Animations (defaults to R15 animations as placeholders)
    Idle = 507766388, -- R15 Idle
    Attack1 = 507765644, -- R15 Attack 1
    Attack2 = 507765644, -- R15 Attack 2 (duplicate for now)
    Block = 507770677, -- R15 Block/Shield
    Cast = 507770239, -- R15 Cast/Spell
    Hit = 507767968, -- R15 Hit/Damage (reuse Fall)
}

return Animations
