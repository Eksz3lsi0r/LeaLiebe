--!strict
-- Achievement System Fix Auto-Loader
-- Automatically fixes achievement button spam issues
-- Place this script in StarterPlayer/StarterPlayerScripts or StarterGui

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Load the Achievement Fix module
local AchievementFix = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AchievementFix"))

-- Initialize the fix system
AchievementFix.initialize()

print("[AchievementFixLoader] Achievement button spam protection activated!")
