--!strict
-- Central animation IDs (R15). Replace with your own assets as needed.
-- 0 or nil will skip loading that animation.

local Animations = {
	-- Hinweis: In diesem Endless Runner sind Run und Walk identisch.
	-- Der echte, saubere Lauf-Loop ist die R15 Walk-Animation (507777826).
	-- Die frühere R15 "Run"-ID (507767714) enthält ein Start-Snippet und wirkt beim Loopen ruckelig.
	Run = 507777826,   -- verwende den sauberen Loop
	Walk = 507777826,  -- alias, falls irgendwo Walk referenziert wird
	Jump = 507765000,  -- R15 Jump
	Fall = 507767968,  -- R15 Fall
	-- Slide (vormals Roll): Platzhalter-Animation (Climb), bis eine eigene/zugelassene Slide-Animation genutzt werden kann.
	-- Hinweis: Eine gefundene Creator-Store-ID (z.B. 9890071351) erfordert Zugriffsfreigabe für die Experience
	-- (Studio: Output-Link "Click to share access" nutzen) oder ein eigenes, hochgeladenes Asset.
	-- Für stabile Läufe setzen wir vorerst den Platzhalter:
	Slide = 507765644,
}

return Animations
