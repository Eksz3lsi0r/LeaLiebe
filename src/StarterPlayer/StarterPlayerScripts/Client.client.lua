--!strict
-- Client input + minor visual FX + HUD hooking

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local LaneRequest = Remotes:WaitForChild("LaneRequest") :: RemoteEvent
local UpdateHUD = Remotes:WaitForChild("UpdateHUD") :: RemoteEvent
local CoinPickup = Remotes:FindFirstChild("CoinPickup") :: RemoteEvent?
local PowerupPickup = Remotes:FindFirstChild("PowerupPickup") :: RemoteEvent?
local RestartRequest = Remotes:WaitForChild("RestartRequest") :: RemoteEvent
local ActionRequest = Remotes:WaitForChild("ActionRequest") :: RemoteEvent
local ActionSync = Remotes:FindFirstChild("ActionSync") :: RemoteEvent?

-- Shared roll window across closures so server-driven Roll (ActionSync) can inform animator checks
local rollingUntilShared = 0.0

-- Simple SFX helper available to all scopes
local function playSfx(ids: {number}?, name: string, volume: number)
    if not ids or #ids == 0 then return end
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
                task.delay(2, function() if s and s.Parent then s:Destroy() end end)
                break
            else
                if s then s:Destroy() end
            end
        end
    end
end

local Animations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Animations")) :: {
    Run: number?, Jump: number?, Fall: number?, Slide: number?, Walk: number?
}
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants")) :: any

-- Lane-Infos und clientseitige Visualisierung des Spurwechsels
local LANES: {number} = (Constants and Constants.LANES) or {-5, 0, 5}
local targetLaneIndex: number = 2 -- Start in der Mitte
-- Eff. seitliche Visualgeschwindigkeit: entspricht Server (LaneSwitchSpeed * LaneSwitchFactor)
local laneSwitchSpeed: number = (((Constants and Constants.PLAYER and Constants.PLAYER.LaneSwitchSpeed) or 24)
    * ((Constants and Constants.PLAYER and (Constants.PLAYER.LaneSwitchFactor or 1)) or 1))
-- Prädizierte X-Position, der die Kamera lateral folgt (Z/Y von HRP)
local predictedX: number? = nil

-- Input: A/D or Left/Right to switch lanes
local function onInputBegan(input: InputObject, gpe: boolean)
	if gpe then return end
    -- A/D und Pfeile klassisch belegen
    if input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then
        LaneRequest:FireServer(1)  -- links
        targetLaneIndex = math.clamp(targetLaneIndex + 1, 1, #LANES)
    elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
        LaneRequest:FireServer(-1)   -- rechts
        targetLaneIndex = math.clamp(targetLaneIndex - 1, 1, #LANES)
    elseif input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.Space then
        ActionRequest:FireServer("Jump")
    elseif input.KeyCode == Enum.KeyCode.Down then
        -- Clientseitiges Gating: Während aktiver Roll kein erneutes Triggern/SFX
        if os.clock() < rollingUntilShared then return end
        ActionRequest:FireServer("Roll")
	end
end
UserInputService.InputBegan:Connect(onInputBegan)

-- Bind W/S exclusively to Jump/Roll and sink default movement
do
    local function handleJumpAction(actionName: string, inputState: Enum.UserInputState, input: InputObject)
        -- Always sink to block default forward movement
        if inputState == Enum.UserInputState.Begin then
            ActionRequest:FireServer("Jump")
        end
        return Enum.ContextActionResult.Sink
    end

    local function handleRollAction(actionName: string, inputState: Enum.UserInputState, input: InputObject)
        -- Always sink to block default backward movement (which slows player)
        if inputState == Enum.UserInputState.Begin then
            -- Clientseitiges Gating: Wenn bereits Slide aktiv, tue nichts (kein SFX)
            if os.clock() < rollingUntilShared then
                return Enum.ContextActionResult.Sink
            end
            ActionRequest:FireServer("Roll")
        end
        return Enum.ContextActionResult.Sink
    end

    -- High priority to beat default control scripts
    pcall(function()
        ContextActionService:BindActionAtPriority("Endless_JumpOnW", handleJumpAction, false, 2000, Enum.KeyCode.W)
        ContextActionService:BindActionAtPriority("Endless_RollOnS", handleRollAction, false, 2000, Enum.KeyCode.S)
    end)
end

-- Basic camera: follow behind
local function setupCamera()
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local char = player.Character or player.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart

    -- Initiale Zielspur anhand aktueller X-Position bestimmen
    local function nearestLaneIndex(x: number): number
        local bestIdx, bestDist = 1, math.huge
        for i, laneX in ipairs(LANES) do
            local d = math.abs(x - laneX)
            if d < bestDist then bestIdx, bestDist = i, d end
        end
        return bestIdx
    end
    targetLaneIndex = nearestLaneIndex(hrp.Position.X)
    predictedX = hrp.Position.X

    local last = os.clock()
    RunService.RenderStepped:Connect(function()
        local now = os.clock()
        local dt = math.clamp(now - last, 0, 1/15)
        last = now

        -- Seitliche Prädiktion Richtung Zielspur
        local desiredX = LANES[targetLaneIndex]
        local currentX = predictedX or hrp.Position.X
        if math.abs(currentX - desiredX) < 0.05 then
            currentX = desiredX
        else
            local dir = (desiredX > currentX) and 1 or -1
            currentX = currentX + dir * laneSwitchSpeed * dt
            if (dir > 0 and currentX > desiredX) or (dir < 0 and currentX < desiredX) then
                currentX = desiredX
            end
        end
        -- sanfte Korrektur zur Serverposition, falls merkliche Abweichung entsteht
        local serverX = hrp.Position.X
        if math.abs(serverX - currentX) > 1.2 then
            currentX = currentX + (serverX - currentX) * 0.25
        end
        predictedX = currentX

        local pos = Vector3.new(currentX, hrp.Position.Y, hrp.Position.Z)
        local camPos = pos + Vector3.new(0, 10, -18)
        workspace.CurrentCamera.CFrame = CFrame.new(camPos, pos + Vector3.new(0, 4, 12))
    end)
end

task.spawn(setupCamera)

-- Simple swipe gestures for mobile
do
    local touchStart: Vector2? = nil
    local touchTime: number = 0
    UserInputService.TouchStarted:Connect(function(input, gpe)
        if gpe then return end
        touchStart = input.Position
        touchTime = os.clock()
    end)
    UserInputService.TouchEnded:Connect(function(input, gpe)
        if gpe then return end
        if not touchStart then return end
        local delta = input.Position - touchStart
        local dt = os.clock() - touchTime
        touchStart = nil
        -- einfacher Schwellenwert
        local minDist = 40
        if dt < 0.6 then
            if math.abs(delta.X) > math.abs(delta.Y) and math.abs(delta.X) > minDist then
                local dir = (delta.X > 0) and 1 or -1
                LaneRequest:FireServer(dir)
                targetLaneIndex = math.clamp(targetLaneIndex + dir, 1, #LANES)
            elseif math.abs(delta.Y) > minDist then
                if delta.Y < 0 then
                    ActionRequest:FireServer("Jump")
                else
                    -- Clientseitiges Gating: Wenn Slide läuft, ignoriere Swipe-Down
                    if os.clock() < rollingUntilShared then return end
                    ActionRequest:FireServer("Roll")
                end
            end
        end
    end)
end

-- Simple local animation controller
local function setupAnimator()
    local char = player.Character or player.CharacterAdded:Wait()
    local hum = char:WaitForChild("Humanoid") :: Humanoid
    -- Disable Roblox default movement controls (WASD) so W/S don't affect speed
    task.spawn(function()
        local ps = player:WaitForChild("PlayerScripts")
        local ok, PlayerModule = pcall(function()
            return require(ps:WaitForChild("PlayerModule"))
        end)
        if ok and PlayerModule then
            local controlsOk, controls = pcall(function()
                return PlayerModule:GetControls()
            end)
            if controlsOk and controls and controls.Disable then
                controls:Disable()
            end
        end
    end)
    -- Disable default Animate to avoid conflicts
    local animateScript = char:FindFirstChild("Animate")
    if animateScript and animateScript:IsA("LocalScript") then
        animateScript.Disabled = true
    end
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = hum
    end

    local tracks: { [string]: AnimationTrack } = {}
    local lastRunPlayback: number = 1.0
    local runGraceUntil = 0.0   -- Grace nach Landung/Running, bevor wir Jump/Fall hart stoppen
    local jumpGraceUntil = 0.0  -- Grace direkt nach Jump-Start, damit Jump nicht sofort am Boden abgebrochen wird
    local rollingUntil = 0.0    -- während dieser Zeit darf Run/Fall Roll nicht übersteuern
    local function load(name: string, id: number?, opts: { loop: boolean?, priority: Enum.AnimationPriority? }?)
        if not id or id == 0 then return end
        local anim = Instance.new("Animation")
        anim.AnimationId = string.format("rbxassetid://%d", id)
        anim.Name = name
        local ok, track = pcall(function()
            return animator:LoadAnimation(anim)
        end)
        if not ok or not track then
            warn(string.format("[Client] Konnte Animation '%s' (ID %s) nicht laden", name, tostring(id)))
            return
        end
        track.Name = name
        if opts and opts.priority then
            track.Priority = opts.priority
        else
            track.Priority = Enum.AnimationPriority.Movement
        end
        if opts and opts.loop ~= nil then
            track.Looped = opts.loop
        end
        -- Reset current when this track fully stops (important for non-looping like Jump/Roll)
        pcall(function()
            track.Stopped:Connect(function()
                if current == name then
                    current = nil
                end
            end)
        end)
        tracks[name] = track
    end
    load("Run", Animations.Run, {loop = true, priority = Enum.AnimationPriority.Movement})
    load("Jump", Animations.Jump, {loop = false, priority = Enum.AnimationPriority.Action})
    load("Fall", Animations.Fall, {loop = true, priority = Enum.AnimationPriority.Movement})
    load("Slide", Animations.Slide, {loop = false, priority = Enum.AnimationPriority.Action})

    local current: string? = nil
    local function play(name: string, fade: number, force: boolean?)
        local t = tracks[name]
        if current == name and not force then
            -- If same track requested: only (re)play if it ended
            if t and not t.IsPlaying then
                t:Play(fade)
            end
            return
        end
        -- stop previous
        if current and tracks[current] then
            tracks[current]:Stop(fade)
        end
        current = name
        if t then
            if force and t.IsPlaying then
                t:Stop(0)
            end
            t:Play(fade)
        end
    end

    -- react to state changes
    hum.StateChanged:Connect(function(_, new)
    -- Wenn wir sliden, ignorieren wir Zustandswechsel, die Run/Fall triggern würden
        if os.clock() < math.max(rollingUntil, rollingUntilShared) then
            return
        end
    if new == Enum.HumanoidStateType.Jumping then
            jumpGraceUntil = os.clock() + 0.3
            play("Jump", 0.05, true)
        elseif new == Enum.HumanoidStateType.Freefall then
            play("Fall", 0.05, true)
        elseif new == Enum.HumanoidStateType.Landed then
            -- Ensure fall/jump stop immediately on landing
            if tracks["Fall"] then tracks["Fall"]:Stop(0.05) end
            if tracks["Jump"] then tracks["Jump"]:Stop(0.05) end
            runGraceUntil = os.clock() + 0.3
            play("Run", 0.05, true)
    elseif new == Enum.HumanoidStateType.Running or new == Enum.HumanoidStateType.RunningNoPhysics then
            runGraceUntil = os.clock() + 0.3
            play("Run", 0.05, true)
        elseif new == Enum.HumanoidStateType.Seated then
            -- keep run stopped when seated
            if tracks["Run"] then tracks["Run"]:Stop(0.1) end
        end
    end)

    -- drive run animation by horizontal speed and adjust playback speed (with smoothing)
    local lastPos: Vector3? = nil
    local smoothedSpeed = 0.0
    RunService.RenderStepped:Connect(function(dt)
        if not char.Parent then return end
        local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not hrp then return end
        local pos = hrp.Position
        local speed = 0
    if lastPos then
            local delta = pos - lastPos
            speed = Vector3.new(delta.X, 0, delta.Z).Magnitude / math.max(dt, 1/240)
        end
        lastPos = pos

        -- Exponential smoothing to avoid jitter from replication timing
        local alpha = math.clamp(dt * 5, 0, 1) -- ~200ms time constant
        smoothedSpeed = smoothedSpeed + (speed - smoothedSpeed) * alpha

    if hum.FloorMaterial ~= Enum.Material.Air then
            -- Während Slide keine Run/Fall-Umschaltung auslösen; kein Auto-Replay,
            -- damit Slide/Jump sich nicht gegenseitig dauerhaft sperren
            if os.clock() < math.max(rollingUntil, rollingUntilShared) then
                return
            end
            local now = os.clock()
            local jumpPlaying = tracks["Jump"] and tracks["Jump"].IsPlaying or false
            local fallPlaying = tracks["Fall"] and tracks["Fall"].IsPlaying or false

            if jumpPlaying or fallPlaying then
                -- Direkt nach Jump nicht abbrechen; nach Landung kurze Grace gewähren
                local stillInJumpGrace = jumpPlaying and (now < jumpGraceUntil)
                local beyondLandingGrace = now > runGraceUntil
                if not stillInJumpGrace and beyondLandingGrace then
                    if tracks["Fall"] and tracks["Fall"].IsPlaying then tracks["Fall"]:Stop(0.05) end
                    if tracks["Jump"] and tracks["Jump"].IsPlaying then tracks["Jump"]:Stop(0.05) end
                    play("Run", 0.06, true)
                end
            else
                -- Grounded und keine luftbezogenen Tracks -> Run sicherstellen
                play("Run", 0.06)
            end

            -- Update run playback speed smoothly (baseline ~28 studs/s -> 1.0)
            local runTrack = tracks["Run"]
            if runTrack and runTrack.IsPlaying then
                local target = math.clamp(smoothedSpeed / 28, 0.8, 1.8)
                if math.abs((lastRunPlayback or 1) - target) > 0.05 then
                    runTrack:AdjustSpeed(target)
                    lastRunPlayback = target
                end
            end
        else
            -- Airborne: ensure Fall plays when not actively in Jump
            if os.clock() < math.max(rollingUntil, rollingUntilShared) then
                -- In der Luft sollte Slide normal nicht aktiv sein; falls doch, brechen wir nicht um
                return
            end
            local jumpPlaying = tracks["Jump"] and tracks["Jump"].IsPlaying or false
            local fallPlaying = tracks["Fall"] and tracks["Fall"].IsPlaying or false
            if not jumpPlaying and not fallPlaying then
                play("Fall", 0.05, true)
            end
        end
    end)

    -- Optional: naive Slide visual (if no Slide anim). Slightly tilt/offset for 0.5s when S pressed
    local hrp = (player.Character or player.CharacterAdded:Wait()):WaitForChild("HumanoidRootPart") :: BasePart
    UserInputService.InputBegan:Connect(function(input, gpe)
        -- Für W/S lokale Animationen auch dann erlauben, wenn das Event via CAS gesunken wurde
        if gpe and not (input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.S) then return end
        local grounded = hum.FloorMaterial ~= Enum.Material.Air
        if input.KeyCode == Enum.KeyCode.S then
            -- Während aktiver Slide keine erneute Auslösung / kein SFX
            if os.clock() < math.max(rollingUntil, rollingUntilShared) then
                return
            end
            -- Slide nur am Boden starten
            if grounded then
                local duration = (Constants.PLAYER and Constants.PLAYER.RollDuration) or 0.6
                rollingUntil = os.clock() + duration
                rollingUntilShared = rollingUntil
                -- Wechsel auf Slide: evtl. laufenden Jump abbrechen und Grace zurücksetzen
                jumpGraceUntil = 0
                if tracks["Jump"] and tracks["Jump"].IsPlaying then
                    tracks["Jump"]:Stop(0.05)
                end
                if tracks["Fall"] and tracks["Fall"].IsPlaying then
                    tracks["Fall"]:Stop(0.05)
                end
                if tracks["Slide"] then
                    play("Slide", 0.05, true)
                end
            else
                -- In der Luft: Der Server bricht Jump sofort ab und startet Roll; spiegle das lokal direkt
                local duration = (Constants.PLAYER and Constants.PLAYER.RollDuration) or 0.6
                rollingUntil = os.clock() + duration
                rollingUntilShared = rollingUntil
                -- Stoppe Jump/Fall sofort und spiele Slide
                jumpGraceUntil = 0
                if tracks["Jump"] and tracks["Jump"].IsPlaying then tracks["Jump"]:Stop(0.05) end
                if tracks["Fall"] and tracks["Fall"].IsPlaying then tracks["Fall"]:Stop(0.05) end
                if tracks["Slide"] then play("Slide", 0.05, true) end
            end
        elseif input.KeyCode == Enum.KeyCode.W then
            -- Jump sofort lokal triggern (Responsiveness), nur am Boden und nicht während Roll
            if grounded and os.clock() >= math.max(rollingUntil, rollingUntilShared) then
                -- Wechsel auf Jump: Slide sofort freigeben und evtl. Track stoppen
                rollingUntil = 0
                rollingUntilShared = 0
                if tracks["Slide"] and tracks["Slide"].IsPlaying then
                    tracks["Slide"]:Stop(0.05)
                end
                jumpGraceUntil = os.clock() + 0.3
                play("Jump", 0.05, true)
            elseif os.clock() < math.max(rollingUntil, rollingUntilShared) then
                -- Während Slide ersetzt W sofort Slide durch Jump (spiegele Serverlogik)
                rollingUntil = 0
                rollingUntilShared = 0
                if tracks["Slide"] and tracks["Slide"].IsPlaying then tracks["Slide"]:Stop(0.05) end
                jumpGraceUntil = os.clock() + 0.3
                play("Jump", 0.05, true)
            end
        end
    end)
    RunService.RenderStepped:Connect(function()
        -- Wenn Slide abgelaufen ist und wir am Boden sind, zurück zu Run, falls nicht schon aktiv
        if os.clock() >= math.max(rollingUntil, rollingUntilShared) then
            if hum.FloorMaterial ~= Enum.Material.Air then
                -- Sicherstellen, dass evtl. hängen gebliebener Slide-Track gestoppt ist
                if tracks["Slide"] and tracks["Slide"].IsPlaying then
                    tracks["Slide"]:Stop(0.05)
                end
                local runTrack = tracks["Run"]
                if runTrack and not runTrack.IsPlaying then
                    play("Run", 0.06)
                end
            end
        end
    end)

    -- Serverseitige ActionSync-Events direkt im Animator-Context spiegeln (damit wir Zugriff auf Tracks/Play haben)
    if ActionSync then
        ActionSync.OnClientEvent:Connect(function(info)
            local action = info and info.action
            if not action then return end
            if action == "Roll" then
                local duration = (Constants.PLAYER and Constants.PLAYER.RollDuration) or 0.6
                rollingUntil = os.clock() + duration
                rollingUntilShared = rollingUntil
                -- Stoppe Jump/Fall und spiele Slide
                jumpGraceUntil = 0
                if tracks["Jump"] and tracks["Jump"].IsPlaying then tracks["Jump"]:Stop(0.05) end
                if tracks["Fall"] and tracks["Fall"].IsPlaying then tracks["Fall"]:Stop(0.05) end
                if tracks["Slide"] then play("Slide", 0.05, true) end
                playSfx((Constants.AUDIO and Constants.AUDIO.SlideSoundIds) or {}, "SlideSFX", 0.6)
            elseif action == "Jump" then
                rollingUntil = 0
                rollingUntilShared = 0
                if tracks["Slide"] and tracks["Slide"].IsPlaying then tracks["Slide"]:Stop(0.05) end
                jumpGraceUntil = os.clock() + 0.3
                play("Jump", 0.05, true)
                playSfx((Constants.AUDIO and Constants.AUDIO.JumpSoundIds) or {}, "JumpSFX", 0.6)
            end
        end)
    end
end

task.spawn(setupAnimator)

-- HUD updates
local cachedHUD: ScreenGui? = nil
local cachedDist: TextLabel? = nil
local cachedCoins: TextLabel? = nil
local cachedSpeed: TextLabel? = nil
local cachedMagnet: TextLabel? = nil
local cachedShield: TextLabel? = nil

-- Ensure only one HUD exists at any time (singleton)
local function enforceSingleHUD()
    local sg = player:WaitForChild("PlayerGui")
    local function isHUD(inst: Instance): boolean
        return inst:IsA("ScreenGui") and inst.Name == "HUD"
    end

    -- Prefer adopting an existing HUD if ours isn't resolved yet
    local ours = cachedHUD or (function()
        local h = sg:FindFirstChild("HUD")
        if h and h:IsA("ScreenGui") then
            cachedHUD = h
            h:SetAttribute("EndlessHUD", true)
            return h
        end
        return nil
    end)()

    -- Remove duplicates immediately
    if ours then
        for _, child in ipairs(sg:GetChildren()) do
            if isHUD(child) and child ~= ours then
                child:Destroy()
            end
        end
    end

    -- Future duplicates: destroy anything that isn't our managed HUD
    sg.ChildAdded:Connect(function(child)
        if isHUD(child) then
            local current = cachedHUD or child
            if current ~= child and child.Parent == sg then
                task.defer(function()
                    if child.Parent == sg then child:Destroy() end
                end)
            else
                -- If we had none, adopt this one
                cachedHUD = child
                child:SetAttribute("EndlessHUD", true)
            end
        end
    end)
end

-- Create a minimal HUD if none exists (fallback)
local function ensureHUD(): ScreenGui
    local sg = player:WaitForChild("PlayerGui")
    local existing = sg:FindFirstChild("HUD")
    if existing and existing:IsA("ScreenGui") then
        cachedHUD = existing
        return existing
    end

    local hud = Instance.new("ScreenGui")
    hud.Name = "HUD"
    hud.ResetOnSpawn = false
    hud:SetAttribute("EndlessHUD", true)
    hud.Parent = sg

    local function makeLabel(name: string, pos: UDim2): TextLabel
        local lbl = Instance.new("TextLabel")
        lbl.Name = name
        lbl.BackgroundTransparency = 0.35
        lbl.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        lbl.BorderSizePixel = 0
        lbl.TextColor3 = Color3.new(1, 1, 1)
        lbl.Font = Enum.Font.GothamBold
        lbl.TextScaled = true
        lbl.Size = UDim2.new(0, 160, 0, 40)
        lbl.Position = pos
        lbl.Parent = hud
        return lbl
    end

    makeLabel("Distance", UDim2.new(0, 20, 0, 20)).Text = "0m"
    makeLabel("Coins", UDim2.new(0, 20, 0, 70)).Text = "0"
    makeLabel("Speed", UDim2.new(0, 20, 0, 120)).Text = "0"
    makeLabel("Magnet", UDim2.new(0, 20, 0, 170)).Text = ""
    makeLabel("Shield", UDim2.new(0, 20, 0, 220)).Text = ""

    cachedHUD = hud
    cachedDist = hud:FindFirstChild("Distance") :: TextLabel?
    cachedCoins = hud:FindFirstChild("Coins") :: TextLabel?
    cachedSpeed = hud:FindFirstChild("Speed") :: TextLabel?
    cachedMagnet = hud:FindFirstChild("Magnet") :: TextLabel?
    cachedShield = hud:FindFirstChild("Shield") :: TextLabel?
    return hud
end

-- Activate singleton enforcement once
enforceSingleHUD()

local function resolveHUD(): ScreenGui?
    if cachedHUD and cachedHUD.Parent then return cachedHUD end
    local sg = player:WaitForChild("PlayerGui")
    local hud = sg:FindFirstChild("HUD")
    if not hud then
        for _, child in ipairs(sg:GetChildren()) do
            if child:IsA("ScreenGui") and child:GetAttribute("EndlessHUD") then
                hud = child
                break
            end
        end
    end
    if hud and hud:IsA("ScreenGui") then
        cachedHUD = hud
    end
    return cachedHUD
end

local function resolveLabels()
    local hud = resolveHUD()
    if not hud then return end
    if not (cachedDist and cachedDist.Parent == hud) then
        cachedDist = hud:FindFirstChild("Distance") :: TextLabel?
    end
    if not (cachedCoins and cachedCoins.Parent == hud) then
        cachedCoins = hud:FindFirstChild("Coins") :: TextLabel?
    end
    if not (cachedSpeed and cachedSpeed.Parent == hud) then
        cachedSpeed = hud:FindFirstChild("Speed") :: TextLabel?
    end
    if not (cachedMagnet and cachedMagnet.Parent == hud) then
        cachedMagnet = hud:FindFirstChild("Magnet") :: TextLabel?
    end
    if not (cachedShield and cachedShield.Parent == hud) then
        cachedShield = hud:FindFirstChild("Shield") :: TextLabel?
    end
end

UpdateHUD.OnClientEvent:Connect(function(payload)
    print("[Client] UpdateHUD received", payload and payload.distance, payload and payload.coins, payload and payload.speed)
    resolveLabels()
    local hud = resolveHUD()
    if not hud then
        -- Try to build a fallback HUD on the fly
        hud = ensureHUD()
        resolveLabels()
    end
    if not hud then
        warn("[Client] HUD ScreenGui not available")
        return
    end
    if cachedDist and cachedDist:IsA("TextLabel") then cachedDist.Text = string.format("%dm", payload.distance or 0) end
    if cachedCoins and cachedCoins:IsA("TextLabel") then cachedCoins.Text = string.format("%d", payload.coins or 0) end
    if cachedSpeed and cachedSpeed:IsA("TextLabel") then cachedSpeed.Text = string.format("%d", payload.speed or 0) end
    if cachedMagnet and cachedMagnet:IsA("TextLabel") then
        local secs = math.max(0, (payload.magnet or 0))
        cachedMagnet.Text = secs > 0 and string.format("Magnet: %.0fs", secs) or ""
    end
    if cachedShield and cachedShield:IsA("TextLabel") then
        local hits = payload.shield or 0
        cachedShield.Text = hits > 0 and string.format("Schild: %d", hits) or ""
    end
end)

-- Coin pickup SFX (local)
do
    local function buildAssetUri(idNumber: number?): string
        if not idNumber or idNumber == 0 then return "" end
        return string.format("rbxassetid://%d", idNumber)
    end
    local function playFirst(ids: {number}?, name: string, volume: number)
        if not ids or #ids == 0 then return end
        -- Erzeuge pro Name einen flüchtigen Sound (kein Reuse, um ID-Wechsel zu respektieren)
        for _, id in ipairs(ids) do
            if typeof(id) == "number" and id > 0 then
                local s = Instance.new("Sound")
                s.Name = name
                s.SoundId = buildAssetUri(id)
                s.Volume = volume
                s.Parent = SoundService
                local ok = pcall(function()
                    SoundService:PlayLocalSound(s)
                end)
                if ok then
                    task.delay(2, function() if s and s.Parent then s:Destroy() end end)
                    return
                else
                    if s then s:Destroy() end
                end
            end
        end
    end
    local function playCoinSound()
        local ids = (Constants.AUDIO and Constants.AUDIO.CoinSoundIds) or {}
        playFirst(ids, "CoinPickupSFX", 0.5)
    end
    if CoinPickup then
        CoinPickup.OnClientEvent:Connect(playCoinSound)
    end
end

-- GameOver overlay listener
local GameOver = Remotes:WaitForChild("GameOver") :: RemoteEvent
GameOver.OnClientEvent:Connect(function()
    -- Crash/GameOver SFX
    task.spawn(function()
        local ids = (Constants.AUDIO and Constants.AUDIO.CrashSoundIds) or {}
        local played = false
        local function tryPlayList(list: {number}?, name: string, volume: number)
            if played then return end
            if not list or #list == 0 then return end
            for _, id in ipairs(list) do
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
                        played = true
                        task.delay(2, function() if s and s.Parent then s:Destroy() end end)
                        return
                    else
                        if s then s:Destroy() end
                    end
                end
            end
        end
        -- 1) Crash-Kandidaten
        tryPlayList(ids, "CrashSFX", 0.8)
        -- 2) Fallback: Powerup-Kandidaten
        if not played then tryPlayList((Constants.AUDIO and Constants.AUDIO.PowerupSoundIds) or {}, "CrashFallbackPowerup", 0.7) end
        -- 3) Fallback: Coin-Kandidaten
        if not played then tryPlayList((Constants.AUDIO and Constants.AUDIO.CoinSoundIds) or {}, "CrashFallbackCoin", 0.6) end
    end)
    local playerGui = player:WaitForChild("PlayerGui")
    if playerGui:FindFirstChild("GameOverOverlay") then return end

    local overlay = Instance.new("ScreenGui")
    overlay.Name = "GameOverOverlay"
    overlay.ResetOnSpawn = false

    local frame = Instance.new("Frame")
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    frame.Size = UDim2.new(0, 300, 0, 200)
    frame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    frame.Parent = overlay

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 50)
    title.BackgroundTransparency = 1
    title.Text = "Game Over"
    title.Font = Enum.Font.GothamBold
    title.TextScaled = true
    title.TextColor3 = Color3.new(1, 1, 1)
    title.Parent = frame

    local restart = Instance.new("TextButton")
    restart.Size = UDim2.new(0.8, 0, 0, 40)
    restart.Position = UDim2.new(0.1, 0, 0.5, -50)
    restart.Text = "Neustarten"
    restart.Font = Enum.Font.Gotham
    restart.TextScaled = true
    restart.Parent = frame

    local menu = Instance.new("TextButton")
    menu.Size = UDim2.new(0.8, 0, 0, 40)
    menu.Position = UDim2.new(0.1, 0, 0.5, 0)
    menu.Text = "Hauptmenü"
    menu.Font = Enum.Font.Gotham
    menu.TextScaled = true
    menu.Parent = frame

    local shop = Instance.new("TextButton")
    shop.Size = UDim2.new(0.8, 0, 0, 40)
    shop.Position = UDim2.new(0.1, 0, 0.5, 50)
    shop.Text = "Shop"
    shop.Font = Enum.Font.Gotham
    shop.TextScaled = true
    shop.Parent = frame

    overlay.Parent = playerGui

    restart.MouseButton1Click:Connect(function()
        -- Send restart request to server to reset the game
        RestartRequest:FireServer()
        -- Remove overlay
        overlay:Destroy()
    end)
    menu.MouseButton1Click:Connect(function()
        -- Logik für Hauptmenü
    end)
    shop.MouseButton1Click:Connect(function()
        -- Logik für Shop
    end)
end)

-- Powerup Pickup Feedback (optional placeholder)
if PowerupPickup then
    PowerupPickup.OnClientEvent:Connect(function(info)
        -- SFX für Powerup
        local ids = (Constants.AUDIO and Constants.AUDIO.PowerupSoundIds) or {}
        local function playFirst(ids: {number}?, name: string, volume: number)
            if not ids or #ids == 0 then return end
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
                        task.delay(2, function() if s and s.Parent then s:Destroy() end end)
                        return
                    else
                        if s then s:Destroy() end
                    end
                end
            end
        end
        playFirst(ids, "PowerupSFX", 0.6)
    end)
end
