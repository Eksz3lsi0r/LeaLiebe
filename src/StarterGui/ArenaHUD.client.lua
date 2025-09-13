--!strict
-- Arena HUD: Health, Mana, Cooldowns, Combat-Feedback

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ArenaConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ArenaConstants"))

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UpdatePlayerHUD = Remotes:WaitForChild("UpdatePlayerHUD") :: RemoteEvent
local CombatSync = Remotes:WaitForChild("CombatSync") :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- HUD-Struktur
local hudFrame: Frame?
local healthBar: Frame?
local healthFill: Frame?
local healthLabel: TextLabel?
local manaBar: Frame?
local manaFill: Frame?
local manaLabel: TextLabel?
local staminaBar: Frame?
local staminaFill: Frame?
local staminaLabel: TextLabel?
local levelLabel: TextLabel?
local attackCooldownIndicator: Frame?

-- Combat-Feedback
local damageContainer: Frame?

-- Singleton-Check
local existingHUD = playerGui:FindFirstChild("ArenaHUD")
if existingHUD then
    existingHUD:Destroy()
end

local function createDamageNumber(damage: number, position: Vector3, color: Color3)
    if not damageContainer then
        return
    end

    local camera = workspace.CurrentCamera
    local screenPos, onScreen = camera:WorldToScreenPoint(position)
    if not onScreen then
        return
    end

    local damageLabel = Instance.new("TextLabel")
    damageLabel.Size = UDim2.fromOffset(100, 30)
    damageLabel.Position = UDim2.fromOffset(screenPos.X - 50, screenPos.Y - 15)
    damageLabel.BackgroundTransparency = 1
    damageLabel.Text = string.format("-%d", damage)
    damageLabel.TextColor3 = color
    damageLabel.Font = Enum.Font.GothamBold
    damageLabel.TextStrokeTransparency = 0.5
    damageLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    damageLabel.TextScaled = true
    damageLabel.Parent = damageContainer

    -- Animation: Nach oben bewegen und verblassen
    local tweenInfo =
        TweenInfo.new(ArenaConstants.HUD.DamageNumberDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = TweenService:Create(damageLabel, tweenInfo, {
        Position = UDim2.fromOffset(screenPos.X - 50, screenPos.Y - 80),
        TextTransparency = 1,
        TextStrokeTransparency = 1,
    })

    tween:Play()
    tween.Completed:Connect(function()
        damageLabel:Destroy()
    end)
end

local function createHUD()
    -- Haupt-Container
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ArenaHUD"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = playerGui

    -- Haupt-Frame (oben links)
    local newHudFrame = Instance.new("Frame")
    newHudFrame.Name = "HUDFrame"
    newHudFrame.Size = UDim2.fromOffset(300, 120)
    newHudFrame.Position = UDim2.fromOffset(20, 20)
    newHudFrame.BackgroundColor3 = Color3.new(0, 0, 0)
    newHudFrame.BackgroundTransparency = 0.3
    newHudFrame.BorderSizePixel = 0
    newHudFrame.Parent = screenGui
    hudFrame = newHudFrame

    -- Runde Ecken
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = hudFrame

    -- Health Bar
    local newHealthBar = Instance.new("Frame")
    newHealthBar.Name = "HealthBar"
    newHealthBar.Size = UDim2.new(1, -20, 0, 20)
    newHealthBar.Position = UDim2.fromOffset(10, 10)
    newHealthBar.BackgroundColor3 = Color3.new(0.2, 0.1, 0.1)
    newHealthBar.BorderSizePixel = 0
    newHealthBar.Parent = hudFrame
    healthBar = newHealthBar

    local healthCorner = Instance.new("UICorner")
    healthCorner.CornerRadius = UDim.new(0, 4)
    healthCorner.Parent = healthBar

    local newHealthFill = Instance.new("Frame")
    newHealthFill.Name = "Fill"
    newHealthFill.Size = UDim2.fromScale(1, 1)
    newHealthFill.Position = UDim2.fromOffset(0, 0)
    newHealthFill.BackgroundColor3 = ArenaConstants.HUD.HealthBarColor
    newHealthFill.BorderSizePixel = 0
    newHealthFill.Parent = healthBar
    healthFill = newHealthFill

    local healthFillCorner = Instance.new("UICorner")
    healthFillCorner.CornerRadius = UDim.new(0, 4)
    healthFillCorner.Parent = healthFill

    local newHealthLabel = Instance.new("TextLabel")
    newHealthLabel.Name = "HealthLabel"
    newHealthLabel.Size = UDim2.fromScale(1, 1)
    newHealthLabel.Position = UDim2.fromOffset(0, 0)
    newHealthLabel.BackgroundTransparency = 1
    newHealthLabel.Text = "100 / 100"
    newHealthLabel.TextColor3 = Color3.new(1, 1, 1)
    newHealthLabel.TextScaled = true
    newHealthLabel.Font = Enum.Font.GothamBold
    newHealthLabel.Parent = healthBar
    healthLabel = newHealthLabel

    -- Mana Bar
    local newManaBar = Instance.new("Frame")
    newManaBar.Name = "ManaBar"
    newManaBar.Size = UDim2.new(1, -20, 0, 20)
    newManaBar.Position = UDim2.fromOffset(10, 40)
    newManaBar.BackgroundColor3 = Color3.new(0.1, 0.1, 0.2)
    newManaBar.BorderSizePixel = 0
    newManaBar.Parent = hudFrame
    manaBar = newManaBar

    local manaCorner = Instance.new("UICorner")
    manaCorner.CornerRadius = UDim.new(0, 4)
    manaCorner.Parent = manaBar

    local newManaFill = Instance.new("Frame")
    newManaFill.Name = "Fill"
    newManaFill.Size = UDim2.fromScale(1, 1)
    newManaFill.Position = UDim2.fromOffset(0, 0)
    newManaFill.BackgroundColor3 = ArenaConstants.HUD.ManaBarColor
    newManaFill.BorderSizePixel = 0
    newManaFill.Parent = manaBar
    manaFill = newManaFill

    local manaFillCorner = Instance.new("UICorner")
    manaFillCorner.CornerRadius = UDim.new(0, 4)
    manaFillCorner.Parent = manaFill

    local newManaLabel = Instance.new("TextLabel")
    newManaLabel.Name = "ManaLabel"
    newManaLabel.Size = UDim2.fromScale(1, 1)
    newManaLabel.Position = UDim2.fromOffset(0, 0)
    newManaLabel.BackgroundTransparency = 1
    newManaLabel.Text = "50 / 50"
    newManaLabel.TextColor3 = Color3.new(1, 1, 1)
    newManaLabel.TextScaled = true
    newManaLabel.Font = Enum.Font.Gotham
    newManaLabel.Parent = manaBar
    manaLabel = newManaLabel

    -- Stamina Bar
    local newStaminaBar = Instance.new("Frame")
    newStaminaBar.Name = "StaminaBar"
    newStaminaBar.Size = UDim2.new(1, -20, 0, 20)
    newStaminaBar.Position = UDim2.fromOffset(10, 70)
    newStaminaBar.BackgroundColor3 = Color3.new(0.2, 0.2, 0.1)
    newStaminaBar.BorderSizePixel = 0
    newStaminaBar.Parent = hudFrame
    staminaBar = newStaminaBar

    local staminaCorner = Instance.new("UICorner")
    staminaCorner.CornerRadius = UDim.new(0, 4)
    staminaCorner.Parent = staminaBar

    local newStaminaFill = Instance.new("Frame")
    newStaminaFill.Name = "Fill"
    newStaminaFill.Size = UDim2.fromScale(1, 1)
    newStaminaFill.Position = UDim2.fromOffset(0, 0)
    newStaminaFill.BackgroundColor3 = ArenaConstants.HUD.StaminaBarColor
    newStaminaFill.BorderSizePixel = 0
    newStaminaFill.Parent = staminaBar
    staminaFill = newStaminaFill

    local staminaFillCorner = Instance.new("UICorner")
    staminaFillCorner.CornerRadius = UDim.new(0, 4)
    staminaFillCorner.Parent = staminaFill

    local newStaminaLabel = Instance.new("TextLabel")
    newStaminaLabel.Name = "StaminaLabel"
    newStaminaLabel.Size = UDim2.fromScale(1, 1)
    newStaminaLabel.Position = UDim2.fromOffset(0, 0)
    newStaminaLabel.BackgroundTransparency = 1
    newStaminaLabel.Text = "100 / 100"
    newStaminaLabel.TextColor3 = Color3.new(1, 1, 1)
    newStaminaLabel.TextScaled = true
    newStaminaLabel.Font = Enum.Font.Gotham
    newStaminaLabel.Parent = staminaBar
    staminaLabel = newStaminaLabel

    -- Level Label
    local newLevelLabel = Instance.new("TextLabel")
    newLevelLabel.Name = "LevelLabel"
    newLevelLabel.Size = UDim2.fromOffset(80, 20)
    newLevelLabel.Position = UDim2.new(1, -90, 0, 100)
    newLevelLabel.BackgroundTransparency = 1
    newLevelLabel.Text = "Level ★"
    newLevelLabel.TextColor3 = Color3.new(1, 1, 1)
    newLevelLabel.TextScaled = true
    newLevelLabel.Font = Enum.Font.GothamBold
    newLevelLabel.Parent = hudFrame
    levelLabel = newLevelLabel

    -- Attack Cooldown Indicator (unten rechts)
    local newAttackCooldownIndicator = Instance.new("Frame")
    newAttackCooldownIndicator.Name = "AttackCooldown"
    newAttackCooldownIndicator.Size = UDim2.fromOffset(60, 60)
    newAttackCooldownIndicator.Position = UDim2.new(1, -80, 1, -80)
    newAttackCooldownIndicator.BackgroundColor3 = Color3.new(0.3, 0.1, 0.1)
    newAttackCooldownIndicator.BorderSizePixel = 0
    newAttackCooldownIndicator.Visible = false
    newAttackCooldownIndicator.Parent = screenGui
    attackCooldownIndicator = newAttackCooldownIndicator

    local cooldownCorner = Instance.new("UICorner")
    cooldownCorner.CornerRadius = UDim.new(0, 8)
    cooldownCorner.Parent = attackCooldownIndicator

    local cooldownLabel = Instance.new("TextLabel")
    cooldownLabel.Name = "CooldownLabel"
    cooldownLabel.Size = UDim2.fromScale(1, 1)
    cooldownLabel.Position = UDim2.fromOffset(0, 0)
    cooldownLabel.BackgroundTransparency = 1
    cooldownLabel.Text = "⏱"
    cooldownLabel.TextColor3 = Color3.new(1, 1, 1)
    cooldownLabel.TextScaled = true
    cooldownLabel.Font = Enum.Font.GothamBold
    cooldownLabel.Parent = attackCooldownIndicator

    -- Damage Numbers Container
    local newDamageContainer = Instance.new("Frame")
    newDamageContainer.Name = "DamageContainer"
    newDamageContainer.Size = UDim2.fromScale(1, 1)
    newDamageContainer.Position = UDim2.fromOffset(0, 0)
    newDamageContainer.BackgroundTransparency = 1
    newDamageContainer.Parent = screenGui
    damageContainer = newDamageContainer

    return screenGui
end

-- HUD Update Handler
UpdatePlayerHUD.OnClientEvent:Connect(function(hudData)
    local health = hudData.health or 100
    local maxHealth = hudData.maxHealth or 100
    local mana = hudData.mana or 50
    local maxMana = hudData.maxMana or 50
    local stamina = hudData.stamina or 100
    local maxStamina = hudData.maxStamina or 100
    local level = hudData.level or 1
    local attackCooldown = hudData.attackCooldown or 0

    -- Health Bar
    local healthPercent = math.max(0, math.min(1, health / maxHealth))
    if healthFill then
        healthFill.Size = UDim2.fromScale(healthPercent, 1)
    end
    if healthLabel then
        healthLabel.Text = string.format("%d / %d", health, maxHealth)
    end

    -- Mana Bar
    local manaPercent = math.max(0, math.min(1, mana / maxMana))
    if manaFill then
        manaFill.Size = UDim2.fromScale(manaPercent, 1)
    end
    if manaLabel then
        manaLabel.Text = string.format("%d / %d", mana, maxMana)
    end

    -- Stamina Bar
    local staminaPercent = math.max(0, math.min(1, stamina / maxStamina))
    if staminaFill then
        staminaFill.Size = UDim2.fromScale(staminaPercent, 1)
    end
    if staminaLabel then
        staminaLabel.Text = string.format("%d / %d", stamina, maxStamina)
    end

    -- Level
    if levelLabel then
        levelLabel.Text = string.format("Level %d", level)
    end

    -- Attack Cooldown
    if attackCooldownIndicator then
        if attackCooldown > 0 then
            attackCooldownIndicator.Visible = true
            local cooldownLabel = attackCooldownIndicator:FindFirstChild("CooldownLabel") :: TextLabel?
            if cooldownLabel then
                cooldownLabel.Text = string.format("%.1f", attackCooldown)
            end
        else
            attackCooldownIndicator.Visible = false
        end
    end
end)

-- Combat Feedback Handler
CombatSync.OnClientEvent:Connect(function(combatData)
    if combatData.action == "Attack" and combatData.damage and type(combatData.damage) == "number" then
        -- Zeige Schadenszahl an
        local character = player.Character
        if character then
            local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
            if hrp then
                createDamageNumber(
                    combatData.damage :: number,
                    hrp.Position + Vector3.new(0, 3, 0),
                    Color3.fromRGB(255, 100, 100)
                )
            end
        end
    elseif combatData.action == "Block" then
        -- Block-Feedback (könnte ein kurzer Schild-Effekt sein)
        print("Blocked!")
    elseif combatData.action == "Cast" then
        -- Spell-Cast-Feedback
        print(string.format("Cast %s!", combatData.spell or "spell"))
    end
end)

-- Bei Charakter-Respawn HUD neu erstellen
player.CharacterAdded:Connect(function()
    task.wait(1) -- Kurz warten für Setup
    createHUD()
end)

-- Initial HUD erstellen
if player.Character then
    createHUD()
else
    player.CharacterAdded:Wait()
    createHUD()
end
