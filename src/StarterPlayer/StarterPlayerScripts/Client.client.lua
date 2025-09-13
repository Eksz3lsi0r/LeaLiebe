--!strict
-- Arena RPG Client - Input, Combat, VFX, HUD

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- Import Config for Z-Lock and camera settings
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Arena RPG Remotes
local MoveRequest = Remotes:WaitForChild("MoveRequest") :: RemoteEvent
local CombatRequest = Remotes:WaitForChild("CombatRequest") :: RemoteEvent
local CombatSync = Remotes:WaitForChild("CombatSync") :: RemoteEvent
local UpdatePlayerHUD = Remotes:WaitForChild("UpdatePlayerHUD") :: RemoteEvent
local _EnemyDeath = Remotes:FindFirstChild("EnemyDeath") :: RemoteEvent?
local _LootDrop = Remotes:FindFirstChild("LootDrop") :: RemoteEvent?
local _ArenaComplete = Remotes:FindFirstChild("ArenaComplete") :: RemoteEvent?
local _EquipmentPurchase = Remotes:FindFirstChild("EquipmentPurchase") :: RemoteEvent?
local _EquipmentResult = Remotes:FindFirstChild("EquipmentResult") :: RemoteEvent?

local Animations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Animations"))
local ArenaConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ArenaConstants"))

-- Character references (updated on respawn)
local currentCharacter: Model? = nil
local currentHrp: BasePart? = nil
local currentHumanoid: Humanoid? = nil

-- Movement state
local movementDirection = Vector3.new(0, 0, 0)
local _isMoving = false
local _lastMoveTime = 0

-- Combat state
local isAttacking = false
local isBlocking = false
local combatCooldowns: { [string]: number } = {}

-- System connections (for cleanup)
local cameraConnection: RBXScriptConnection? = nil
local animationConnection: RBXScriptConnection? = nil
local movementConnection: RBXScriptConnection? = nil

-- SFX helper
local function playSfx(ids: { number }?, name: string, volume: number)
    local okGui, pg = pcall(function()
        return player:WaitForChild("PlayerGui")
    end)
    if okGui and pg and pg:GetAttribute("EffectsEnabled") == false then
        return
    end
    if not ids or typeof(ids) ~= "table" or #ids == 0 then
        return
    end
    for _, id in ipairs(ids) do
        if typeof(id) == "number" and id > 0 then
            local s = Instance.new("Sound")
            s.Name = name
            s.SoundId = string.format("rbxassetid://%d", id)
            s.Volume = volume
            s.Parent = SoundService
            local ok = pcall(function()
                SoundService:PlayLocalSound(s)
            end)
            if ok then
                task.delay(2, function()
                    if s and s.Parent then
                        s:Destroy()
                    end
                end)
                break
            else
                if s then
                    s:Destroy()
                end
            end
        end
    end
end

-- Movement input handling
local function updateMovement()
    local direction = Vector3.new(0, 0, 0)

    -- WASD movement
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then
        direction = direction + Vector3.new(0, 0, 1)
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then
        direction = direction + Vector3.new(0, 0, -1)
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then
        direction = direction + Vector3.new(-1, 0, 0)
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then
        direction = direction + Vector3.new(1, 0, 0)
    end

    -- Normalize diagonal movement
    if direction.Magnitude > 0 then
        direction = direction.Unit
    end

    -- Send movement if changed
    if direction ~= movementDirection then
        movementDirection = direction
        _isMoving = direction.Magnitude > 0
        _lastMoveTime = os.clock()
        MoveRequest:FireServer(direction)
    end
end

-- Combat input handling
local function onInputBegan(input: InputObject, gpe: boolean)
    if gpe then
        return
    end

    local now = os.clock()

    -- Combat inputs
    if input.KeyCode == Enum.KeyCode.Space then
        -- Jump/dodge
        if now > (combatCooldowns["Jump"] or 0) then
            CombatRequest:FireServer("Jump")
            combatCooldowns["Jump"] = now + 1.0
        end
    elseif input.KeyCode == Enum.KeyCode.F then
        -- Attack
        if not isAttacking and now > (combatCooldowns["Attack"] or 0) then
            isAttacking = true
            CombatRequest:FireServer("Attack")
            combatCooldowns["Attack"] = now + 0.8
        end
    elseif input.KeyCode == Enum.KeyCode.G then
        -- Block start
        if not isBlocking then
            isBlocking = true
            CombatRequest:FireServer("Block")
        end
    elseif input.KeyCode == Enum.KeyCode.Q then
        -- Cast spell 1
        if now > (combatCooldowns["Spell1"] or 0) then
            CombatRequest:FireServer("Cast", nil, "spell1")
            combatCooldowns["Spell1"] = now + 3.0
        end
    elseif input.KeyCode == Enum.KeyCode.E then
        -- Cast spell 2
        if now > (combatCooldowns["Spell2"] or 0) then
            CombatRequest:FireServer("Cast", nil, "spell2")
            combatCooldowns["Spell2"] = now + 5.0
        end
    end
end

local function onInputEnded(input: InputObject, gpe: boolean)
    if gpe then
        return
    end

    if input.KeyCode == Enum.KeyCode.G then
        -- Block end
        if isBlocking then
            isBlocking = false
            CombatRequest:FireServer("Block", nil, "end")
        end
    elseif input.KeyCode == Enum.KeyCode.F then
        -- Attack end
        isAttacking = false
    end
end

UserInputService.InputBegan:Connect(onInputBegan)
UserInputService.InputEnded:Connect(onInputEnded)

-- Bind movement controls
do
    local function handleMovement(_actionName: string, inputState: Enum.UserInputState, _input: InputObject)
        if inputState == Enum.UserInputState.Begin or inputState == Enum.UserInputState.End then
            updateMovement()
        end
        return Enum.ContextActionResult.Sink
    end

    pcall(function()
        ContextActionService:BindActionAtPriority(
            "Arena_Movement",
            handleMovement,
            false,
            2000,
            Enum.KeyCode.W,
            Enum.KeyCode.A,
            Enum.KeyCode.S,
            Enum.KeyCode.D
        )
    end)
end

-- Character reference updates
local function updateCharacterReferences()
    currentCharacter = player.Character
    if currentCharacter then
        currentHrp = currentCharacter:WaitForChild("HumanoidRootPart", 5) :: BasePart?
        currentHumanoid = currentCharacter:WaitForChild("Humanoid", 5) :: Humanoid?
    else
        currentHrp = nil
        currentHumanoid = nil
    end
end

-- Cleanup connections
local function cleanupConnections()
    if cameraConnection then
        cameraConnection:Disconnect()
        cameraConnection = nil
    end
    if animationConnection then
        animationConnection:Disconnect()
        animationConnection = nil
    end
    if movementConnection then
        movementConnection:Disconnect()
        movementConnection = nil
    end
end

-- Camera system for arena with Z-Lock from PlayerController
local function setupCamera()
    -- Cleanup previous connection
    if cameraConnection then
        cameraConnection:Disconnect()
    end

    if not currentHrp then
        return
    end

    local cam = workspace.CurrentCamera
    cam.CameraType = Enum.CameraType.Scriptable

    cameraConnection = RunService.RenderStepped:Connect(function()
        if not currentCharacter or not currentCharacter.Parent or not currentHrp or not currentHrp.Parent then
            return
        end

        local hrp = currentHrp :: BasePart

        -- Z-Lock system from PlayerController: Fix Z position to Config.Z_LOCK
        local pos = hrp.Position
        if math.abs(pos.Z - Config.Z_LOCK) > 0.01 then
            hrp.CFrame =
                CFrame.new(Vector3.new(pos.X, pos.Y, Config.Z_LOCK), Vector3.new(pos.X + 1, pos.Y, Config.Z_LOCK))
            hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, hrp.AssemblyLinearVelocity.Y, 0)
        end

        -- Camera positioning from PlayerController: Seitliche Kamera-Führung
        local lookAt = hrp.Position + Vector3.new(Config.CAMERA.LookAheadX, 0, 0)
        local camPos = Vector3.new(
            hrp.Position.X - 5,
            hrp.Position.Y + Config.CAMERA.Height,
            hrp.Position.Z + Config.CAMERA.DistanceZ
        )
        cam.CFrame = CFrame.new(camPos, lookAt)
    end)
end

-- Animation controller for combat
local function setupAnimator()
    -- Cleanup previous connection
    if animationConnection then
        animationConnection:Disconnect()
    end

    if not currentCharacter or not currentHumanoid then
        return
    end

    local humanoid = currentHumanoid :: Humanoid

    -- Disable default animate script
    local animateScript = currentCharacter:FindFirstChild("Animate")
    if animateScript and animateScript:IsA("LocalScript") then
        animateScript.Disabled = true
    end

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    local tracks: { [string]: AnimationTrack } = {}
    local current: string? = nil

    local function loadAnimation(
        name: string,
        id: number?,
        opts: { loop: boolean?, priority: Enum.AnimationPriority? }?
    )
        if not id or id == 0 or not animator then
            return
        end
        local anim = Instance.new("Animation")
        anim.AnimationId = string.format("rbxassetid://%d", id)
        anim.Name = name

        local ok, track = pcall(function()
            return (animator :: Animator):LoadAnimation(anim)
        end)
        if not ok or not track then
            warn(string.format("[Client] Could not load animation '%s' (ID %s)", name, tostring(id)))
            return
        end

        track.Name = name
        track.Priority = (opts and opts.priority) or Enum.AnimationPriority.Movement
        track.Looped = (opts and opts.loop) or false

        track.Stopped:Connect(function()
            if current == name then
                current = nil
            end
        end)

        tracks[name] = track
    end

    -- Load combat animations
    loadAnimation("Idle", Animations.Idle, { loop = true })
    loadAnimation("Walk", Animations.Walk, { loop = true })
    loadAnimation("Run", Animations.Run, { loop = true })
    loadAnimation("Attack1", Animations.Attack1, { priority = Enum.AnimationPriority.Action })
    loadAnimation("Attack2", Animations.Attack2, { priority = Enum.AnimationPriority.Action })
    loadAnimation("Block", Animations.Block, { loop = true, priority = Enum.AnimationPriority.Action })
    loadAnimation("Cast", Animations.Cast, { priority = Enum.AnimationPriority.Action })
    loadAnimation("Jump", Animations.Jump)
    loadAnimation("Hit", Animations.Hit, { priority = Enum.AnimationPriority.Action4 })

    local function playAnimation(name: string, fadeTime: number?, force: boolean?)
        local track = tracks[name]
        if not track then
            return
        end

        if current == name and not force then
            if track.IsPlaying then
                return
            end
        end

        -- Stop current animation
        if current and tracks[current] then
            tracks[current]:Stop(fadeTime or 0.1)
        end

        current = name
        track:Play(fadeTime or 0.1)
    end

    -- Movement animation handling
    local lastSpeed = 0
    animationConnection = RunService.Heartbeat:Connect(function()
        if
            not currentCharacter
            or not currentCharacter.Parent
            or not currentHrp
            or not currentHrp.Parent
            or not currentHumanoid
        then
            return
        end

        local hrp = currentHrp :: BasePart
        local hum = currentHumanoid :: Humanoid

        local velocity = hrp.AssemblyLinearVelocity
        local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

        -- Smooth speed changes
        lastSpeed = lastSpeed + (horizontalSpeed - lastSpeed) * 0.3

        -- Don't override combat animations
        if isAttacking or isBlocking then
            return
        end

        -- Play appropriate movement animation
        if hum.FloorMaterial == Enum.Material.Air then
            -- In air - keep current or play idle
            if not current or current == "Walk" or current == "Run" then
                playAnimation("Idle")
            end
        elseif lastSpeed > 8 then
            playAnimation("Run")
            local runTrack = tracks["Run"]
            if runTrack then
                runTrack:AdjustSpeed(math.clamp(lastSpeed / 16, 0.5, 2.0))
            end
        elseif lastSpeed > 1 then
            playAnimation("Walk")
            local walkTrack = tracks["Walk"]
            if walkTrack then
                walkTrack:AdjustSpeed(math.clamp(lastSpeed / 8, 0.5, 2.0))
            end
        else
            playAnimation("Idle")
        end
    end)

    -- Combat animation handling via CombatSync
    CombatSync.OnClientEvent:Connect(function(info)
        local action = info and info.action
        if not action then
            return
        end

        if action == "Attack" then
            local attackAnim = math.random(1, 2) == 1 and "Attack1" or "Attack2"
            playAnimation(attackAnim, 0.05, true)

            -- Play attack sound using ArenaConstants
            local attackVolume = 0.6
            if ArenaConstants.AUDIO.SFXVolumes and ArenaConstants.AUDIO.SFXVolumes.Attack then
                attackVolume = ArenaConstants.AUDIO.SFXVolumes.Attack
            end
            playSfx(ArenaConstants.AUDIO.AttackSoundIds or {}, "AttackSFX", attackVolume)
        elseif action == "Block" then
            playAnimation("Block", 0.05, true)
        elseif action == "Cast" then
            playAnimation("Cast", 0.05, true)

            -- Play cast sound using ArenaConstants
            local castVolume = 0.5
            if ArenaConstants.AUDIO.SFXVolumes and ArenaConstants.AUDIO.SFXVolumes.Cast then
                castVolume = ArenaConstants.AUDIO.SFXVolumes.Cast
            end
            playSfx(ArenaConstants.AUDIO.CastSoundIds or {}, "CastSFX", castVolume)
        elseif action == "Hit" then
            playAnimation("Hit", 0.05, true)

            -- Play hit sound using ArenaConstants
            local hitVolume = 0.7
            if ArenaConstants.AUDIO.SFXVolumes and ArenaConstants.AUDIO.SFXVolumes.Hit then
                hitVolume = ArenaConstants.AUDIO.SFXVolumes.Hit
            end
            playSfx(ArenaConstants.AUDIO.HitSoundIds or {}, "HitSFX", hitVolume)
        elseif action == "Jump" then
            playAnimation("Jump", 0.05, true)
        end
    end)
end

-- Character spawn/respawn handling
local function onCharacterAdded(_character: Model)
    -- Cleanup previous connections
    cleanupConnections()

    -- Wait a moment for character to fully load
    task.wait(0.1)

    -- Update character references
    updateCharacterReferences()

    -- Setup systems
    if currentHrp and currentHumanoid then
        setupCamera()
        setupAnimator()
    end
end

-- Initial setup and character change handling
if player.Character then
    onCharacterAdded(player.Character)
end

player.CharacterAdded:Connect(onCharacterAdded)

-- Arena RPG HUD
local cachedHUD: ScreenGui? = nil
local cachedHealth: Frame? = nil
local cachedMana: Frame? = nil
local cachedStamina: Frame? = nil
local cachedGold: TextLabel? = nil

local function ensureArenaHUD(): ScreenGui
    local sg = player:WaitForChild("PlayerGui")
    local existing = sg:FindFirstChild("ArenaHUD")
    if existing and existing:IsA("ScreenGui") then
        cachedHUD = existing
        return existing
    end

    local hud = Instance.new("ScreenGui")
    hud.Name = "ArenaHUD"
    hud.ResetOnSpawn = false
    hud:SetAttribute("ArenaHUD", true)
    hud.Parent = sg

    -- Health bar
    local healthBG = Instance.new("Frame")
    healthBG.Name = "HealthBG"
    healthBG.Size = UDim2.fromOffset(200, 20)
    healthBG.Position = UDim2.fromOffset(20, 20)
    healthBG.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    healthBG.BorderSizePixel = 0
    healthBG.Parent = hud

    local healthBar = Instance.new("Frame")
    healthBar.Name = "HealthBar"
    healthBar.Size = UDim2.fromScale(1, 1)
    healthBar.Position = UDim2.fromScale(0, 0)
    healthBar.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    healthBar.BorderSizePixel = 0
    healthBar.Parent = healthBG

    local healthLabel = Instance.new("TextLabel")
    healthLabel.Size = UDim2.fromScale(1, 1)
    healthLabel.BackgroundTransparency = 1
    healthLabel.Text = "Health: 100/100"
    healthLabel.TextColor3 = Color3.new(1, 1, 1)
    healthLabel.Font = Enum.Font.GothamBold
    healthLabel.TextScaled = true
    healthLabel.Parent = healthBG

    -- Mana bar
    local manaBG = Instance.new("Frame")
    manaBG.Name = "ManaBG"
    manaBG.Size = UDim2.fromOffset(200, 20)
    manaBG.Position = UDim2.fromOffset(20, 50)
    manaBG.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    manaBG.BorderSizePixel = 0
    manaBG.Parent = hud

    local manaBar = Instance.new("Frame")
    manaBar.Name = "ManaBar"
    manaBar.Size = UDim2.fromScale(1, 1)
    manaBar.BackgroundColor3 = Color3.fromRGB(50, 50, 200)
    manaBar.BorderSizePixel = 0
    manaBar.Parent = manaBG

    local manaLabel = Instance.new("TextLabel")
    manaLabel.Size = UDim2.fromScale(1, 1)
    manaLabel.BackgroundTransparency = 1
    manaLabel.Text = "Mana: 100/100"
    manaLabel.TextColor3 = Color3.new(1, 1, 1)
    manaLabel.Font = Enum.Font.GothamBold
    manaLabel.TextScaled = true
    manaLabel.Parent = manaBG

    -- Stamina bar
    local staminaBG = Instance.new("Frame")
    staminaBG.Name = "StaminaBG"
    staminaBG.Size = UDim2.fromOffset(200, 20)
    staminaBG.Position = UDim2.fromOffset(20, 80)
    staminaBG.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    staminaBG.BorderSizePixel = 0
    staminaBG.Parent = hud

    local staminaBar = Instance.new("Frame")
    staminaBar.Name = "StaminaBar"
    staminaBar.Size = UDim2.fromScale(1, 1)
    staminaBar.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
    staminaBar.BorderSizePixel = 0
    staminaBar.Parent = staminaBG

    local staminaLabel = Instance.new("TextLabel")
    staminaLabel.Size = UDim2.fromScale(1, 1)
    staminaLabel.BackgroundTransparency = 1
    staminaLabel.Text = "Stamina: 100/100"
    staminaLabel.TextColor3 = Color3.new(1, 1, 1)
    staminaLabel.Font = Enum.Font.GothamBold
    staminaLabel.TextScaled = true
    staminaLabel.Parent = staminaBG

    -- Gold display
    local goldLabel = Instance.new("TextLabel")
    goldLabel.Name = "GoldLabel"
    goldLabel.Size = UDim2.fromOffset(150, 30)
    goldLabel.Position = UDim2.fromOffset(20, 120)
    goldLabel.BackgroundColor3 = Color3.fromRGB(60, 50, 20)
    goldLabel.BorderSizePixel = 0
    goldLabel.Text = "Gold: 0"
    goldLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    goldLabel.Font = Enum.Font.GothamBold
    goldLabel.TextScaled = true
    goldLabel.Parent = hud

    cachedHUD = hud
    cachedHealth = healthBG
    cachedMana = manaBG
    cachedStamina = staminaBG
    cachedGold = goldLabel

    return hud
end

-- Update HUD with player stats
UpdatePlayerHUD.OnClientEvent:Connect(function(payload: any)
    ensureArenaHUD()

    if not cachedHUD or not cachedHUD.Parent then
        return
    end

    -- Update health
    if cachedHealth and payload.health and payload.maxHealth then
        local healthBar = cachedHealth:FindFirstChild("HealthBar") :: Frame?
        local healthLabel = cachedHealth:FindFirstChild("TextLabel") :: TextLabel?

        local health = tonumber(payload.health) or 0
        local maxHealth = tonumber(payload.maxHealth) or 1

        if healthBar then
            local percent = health / math.max(maxHealth, 1)
            healthBar.Size = UDim2.fromScale(percent, 1)
        end

        if healthLabel then
            healthLabel.Text = string.format("Health: %d/%d", health, maxHealth)
        end
    end

    -- Update mana
    if cachedMana and payload.mana and payload.maxMana then
        local manaBar = cachedMana:FindFirstChild("ManaBar") :: Frame?
        local manaLabel = cachedMana:FindFirstChild("TextLabel") :: TextLabel?

        local mana = tonumber(payload.mana) or 0
        local maxMana = tonumber(payload.maxMana) or 1

        if manaBar then
            local percent = mana / math.max(maxMana, 1)
            manaBar.Size = UDim2.fromScale(percent, 1)
        end

        if manaLabel then
            manaLabel.Text = string.format("Mana: %d/%d", mana, maxMana)
        end
    end

    -- Update stamina
    if cachedStamina and payload.stamina and payload.maxStamina then
        local staminaBar = cachedStamina:FindFirstChild("StaminaBar") :: Frame?
        local staminaLabel = cachedStamina:FindFirstChild("TextLabel") :: TextLabel?

        local stamina = tonumber(payload.stamina) or 0
        local maxStamina = tonumber(payload.maxStamina) or 1

        if staminaBar then
            local percent = stamina / math.max(maxStamina, 1)
            staminaBar.Size = UDim2.fromScale(percent, 1)
        end

        if staminaLabel then
            staminaLabel.Text = string.format("Stamina: %d/%d", stamina, maxStamina)
        end
    end

    -- Update gold
    if cachedGold and payload.gold then
        local gold = tonumber(payload.gold) or 0
        cachedGold.Text = string.format("Gold: %d", gold)
    end
end)

-- Mobile touch controls for arena
do
    local touchStart: Vector2? = nil
    local touchTime: number = 0

    UserInputService.TouchStarted:Connect(function(input, gpe)
        if gpe then
            return
        end
        touchStart = Vector2.new(input.Position.X, input.Position.Y)
        touchTime = os.clock()
    end)

    UserInputService.TouchEnded:Connect(function(input, gpe)
        if gpe then
            return
        end
        if not touchStart then
            return
        end

        local delta = Vector2.new(input.Position.X, input.Position.Y) - touchStart
        local dt = os.clock() - touchTime
        touchStart = nil

        local minDist = 50
        if dt < 0.5 and delta.Magnitude < minDist then
            -- Tap = Attack
            if not isAttacking then
                CombatRequest:FireServer("Attack")
            end
        elseif dt > 0.5 then
            -- Hold = Block
            if isBlocking then
                isBlocking = false
                CombatRequest:FireServer("Block", nil, "end")
            end
        end
    end)

    UserInputService.TouchLongPress:Connect(function(_touchPositions, state, gpe)
        if gpe then
            return
        end
        if state == Enum.UserInputState.Begin then
            -- Start blocking
            if not isBlocking then
                isBlocking = true
                CombatRequest:FireServer("Block")
            end
        end
    end)
end

-- Update movement continuously (only setup connection once)
movementConnection = RunService.Heartbeat:Connect(function()
    updateMovement()
end)

print("[Client] Arena RPG client initialized")
