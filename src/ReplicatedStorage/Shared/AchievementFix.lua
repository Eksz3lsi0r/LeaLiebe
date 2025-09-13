--!strict
-- Achievement System Bug Fix
-- Fixes the issue where players can repeatedly click "Collect" buttons for already claimed achievements

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- This module provides utility functions to fix common achievement UI bugs
-- It prevents button spam, ensures proper state synchronization, and avoids re-entrancy issues

local AchievementFix = {}

-- Track claim attempts to prevent spam
local claimAttempts: { [string]: { timestamp: number, count: number } } = {}
local CLAIM_COOLDOWN = 3.0 -- seconds between claim attempts
local MAX_ATTEMPTS = 1 -- max attempts before long cooldown
local LONG_COOLDOWN = 30.0 -- seconds for excessive clicking

-- Track button states to prevent re-entrancy
local buttonStates: {
    [TextButton]: {
        locked: boolean,
        originalEnabled: boolean,
        originalText: string,
        achievementId: string?,
    },
} =
    {}

--[[
	Prevents button spam by implementing cooldowns and attempt tracking
	Returns true if the action should be allowed, false otherwise
]]
function AchievementFix.canClaimAchievement(achievementId: string): boolean
    if not achievementId then
        return false
    end

    local now = tick()
    local attempt = claimAttempts[achievementId]

    if not attempt then
        -- First attempt
        claimAttempts[achievementId] = { timestamp = now, count = 1 }
        return true
    end

    local timeDelta = now - attempt.timestamp

    -- Reset counter if enough time has passed
    if timeDelta >= CLAIM_COOLDOWN then
        attempt.timestamp = now
        attempt.count = 1
        return true
    end

    -- Check if too many attempts
    if attempt.count >= MAX_ATTEMPTS then
        -- Apply long cooldown for spam
        if timeDelta < LONG_COOLDOWN then
            warn("[AchievementFix] Achievement claim spam detected for " .. achievementId .. ". Please wait.")
            return false
        else
            -- Reset after long cooldown
            attempt.timestamp = now
            attempt.count = 1
            return true
        end
    end

    -- Still within cooldown
    return false
end

--[[
	Safely locks a button to prevent re-entrancy and visual feedback issues
]]
function AchievementFix.lockButton(button: TextButton, achievementId: string?, lockText: string?)
    if buttonStates[button] and buttonStates[button].locked then
        return -- Already locked
    end

    -- Store original state
    buttonStates[button] = {
        locked = true,
        originalEnabled = button.Active ~= false, -- Handle both Active and Interactable
        originalText = button.Text,
        achievementId = achievementId,
    }

    -- Lock the button
    button.Active = false
    button.AutoButtonColor = false
    button.Text = lockText or "Processing..."

    -- Visual feedback that it's disabled
    local originalColor = button.BackgroundColor3
    button.BackgroundColor3 = Color3.fromRGB(
        math.floor(originalColor.R * 255 * 0.5),
        math.floor(originalColor.G * 255 * 0.5),
        math.floor(originalColor.B * 255 * 0.5)
    )
end

--[[
	Unlocks a button and restores its original state
]]
function AchievementFix.unlockButton(button: TextButton)
    local state = buttonStates[button]
    if not state then
        return -- Not managed by us
    end

    -- Restore original state
    button.Active = state.originalEnabled
    button.AutoButtonColor = true
    button.Text = state.originalText

    -- Remove darker color by restoring original or using a default
    button.BackgroundColor3 = Color3.fromRGB(35, 35, 35) -- Default button color

    -- Clear state
    buttonStates[button] = nil
end

--[[
	Marks an achievement as claimed to prevent further attempts
]]
function AchievementFix.markAchievementClaimed(achievementId: string)
    if not achievementId then
        return
    end

    -- Set to maximum attempts to prevent future claims
    claimAttempts[achievementId] = {
        timestamp = tick(),
        count = MAX_ATTEMPTS + 1,
    }
end

--[[
	Checks if an achievement is already in claimed state
]]
function AchievementFix.isAchievementClaimed(achievementId: string): boolean
    if not achievementId then
        return false
    end

    local attempt = claimAttempts[achievementId]
    if not attempt then
        return false
    end

    return attempt.count > MAX_ATTEMPTS
end

--[[
	Safely handles achievement claim attempts with proper error handling
	Use this wrapper around your existing claim logic
]]
function AchievementFix.handleClaimAttempt(button: TextButton, achievementId: string, claimFunction: () -> ())
    -- Validate inputs
    if not button or not achievementId or not claimFunction then
        warn("[AchievementFix] Invalid parameters for claim attempt")
        return
    end

    -- Check if already locked
    if buttonStates[button] and buttonStates[button].locked then
        return
    end

    -- Check if can claim
    if not AchievementFix.canClaimAchievement(achievementId) then
        return
    end

    -- Lock button immediately
    AchievementFix.lockButton(button, achievementId, "Claiming...")

    -- Execute claim with error handling
    local success = pcall(claimFunction)

    if not success then
        warn("[AchievementFix] Claim failed for " .. achievementId)
        -- Unlock on error after short delay
        task.wait(1.0)
        AchievementFix.unlockButton(button)
    end

    -- Note: Button should be unlocked by the response handler, not here
    -- This prevents race conditions with server responses
end

--[[
	Auto-patches existing achievement buttons to be more robust
	Call this after your Achievement UI is created
]]
function AchievementFix.patchAchievementButtons(containerGui: ScreenGui?)
    if not containerGui then
        -- Try to find achievement UI automatically
        for _, gui in ipairs(playerGui:GetChildren()) do
            if
                gui:IsA("ScreenGui")
                and (
                    string.find(string.lower(gui.Name), "achievement")
                    or string.find(string.lower(gui.Name), "reward")
                    or gui:FindFirstChild("AchievementFrame", true)
                )
            then
                containerGui = gui
                break
            end
        end
    end

    if not containerGui then
        return
    end

    -- Find all buttons that might be achievement claim buttons
    local function patchButton(button: TextButton)
        local buttonText = string.lower(button.Text)
        if
            string.find(buttonText, "collect")
            or string.find(buttonText, "claim")
            or string.find(buttonText, "sammeln")
            or string.find(buttonText, "einsammeln")
        then
            -- Try to find achievement ID from button name or parent
            local achievementId = button.Name
            if button.Parent and button.Parent.Name ~= button.Name then
                achievementId = button.Parent.Name .. "_" .. button.Name
            end

            -- Note: We can't safely wrap existing connections in Luau without exploits
            -- Instead, we add our protection as an additional layer
            button.MouseButton1Click:Connect(function()
                if not AchievementFix.canClaimAchievement(achievementId) then
                    return -- Silently block spam attempts
                end
                AchievementFix.lockButton(button, achievementId, "Processing...")

                -- Auto-unlock after timeout to prevent permanent locks
                task.delay(10.0, function()
                    if buttonStates[button] and buttonStates[button].locked then
                        AchievementFix.unlockButton(button)
                    end
                end)
            end)

            print("[AchievementFix] Patched button: " .. button.Name)
        end
    end

    -- Patch existing buttons
    for _, descendant in ipairs(containerGui:GetDescendants()) do
        if descendant:IsA("TextButton") then
            patchButton(descendant)
        end
    end

    -- Patch future buttons
    containerGui.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("TextButton") then
            task.wait() -- Let it fully initialize
            patchButton(descendant)
        end
    end)
end

--[[
	Initializes the Achievement Fix system
	Call this once when your game starts
]]
function AchievementFix.initialize()
    print("[AchievementFix] Achievement Bug Fix System initialized")

    -- Auto-patch when Achievement UIs are added
    playerGui.ChildAdded:Connect(function(child)
        if child:IsA("ScreenGui") then
            task.wait(1.0) -- Let UI fully load
            AchievementFix.patchAchievementButtons(child)
        end
    end)

    -- Patch existing UIs
    task.spawn(function()
        task.wait(2.0) -- Wait for initial UI load
        AchievementFix.patchAchievementButtons()
    end)

    -- Clean up disconnected buttons periodically
    task.spawn(function()
        while true do
            task.wait(60.0) -- Clean every minute

            for button, _ in pairs(buttonStates) do
                if not button.Parent then
                    buttonStates[button] = nil
                end
            end
        end
    end)

    -- Handle core Roblox re-entrancy errors
    game:GetService("ScriptContext").Error:Connect(function(message)
        if string.find(message, "re-entrancy") and string.find(message, "BindableEvent") then
            warn("[AchievementFix] Detected re-entrancy error, clearing button states")

            -- Clear all locked buttons to prevent permanent lock
            for button, _ in pairs(buttonStates) do
                if button.Parent then
                    AchievementFix.unlockButton(button)
                end
            end
        end
    end)
end

return AchievementFix
