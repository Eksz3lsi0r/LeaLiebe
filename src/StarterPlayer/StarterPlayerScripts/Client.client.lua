--!strict
-- Client input + minor visual FX + HUD hooking

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local LaneRequest = Remotes:WaitForChild("LaneRequest") :: RemoteEvent
local UpdateHUD = Remotes:WaitForChild("UpdateHUD") :: RemoteEvent
local CoinPickup = Remotes:FindFirstChild("CoinPickup") :: RemoteEvent?
local PowerupPickup = Remotes:FindFirstChild("PowerupPickup") :: RemoteEvent?
local RestartRequest = Remotes:WaitForChild("RestartRequest") :: RemoteEvent
local ActionRequest = Remotes:WaitForChild("ActionRequest") :: RemoteEvent
local ActionSync = Remotes:FindFirstChild("ActionSync") :: RemoteEvent?
local EventAnnounce = Remotes:FindFirstChild("EventAnnounce") :: RemoteEvent?

-- Shared roll window across closures so server-driven Roll (ActionSync) can inform animator checks
local rollingUntilShared = 0.0

-- Simple SFX helper available to all scopes
local function playSfx(ids: { number }?, name: string, volume: number)
    -- Accessibility: allow disabling effects/sounds via PlayerGui attribute
    local okGui, pg = pcall(function()
        return player:WaitForChild("PlayerGui")
    end)
    if okGui and pg and pg:GetAttribute("EffectsEnabled") == false then
        return
    end
    if not ids or #ids == 0 then
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

type AnimTable = { Run: number?, Jump: number?, Fall: number?, Slide: number?, Walk: number? }
local Animations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Animations")) :: AnimTable
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants")) :: any
-- Music ducking hooks (assigned by music controller below)
local music_onGameOverRef: (() -> ())? = nil
local music_onPowerupRef: (() -> ())? = nil

-- Background music controller (loop + ducking)
do
    local musicSound: Sound? = nil
    local lastDuckUntil = 0.0
    local baseVolume = ((Constants.AUDIO and Constants.AUDIO.MusicVolume) or 0.45)
    local function buildAssetUri(idNumber: number?): string
        if not idNumber or idNumber == 0 then
            return ""
        end
        return string.format("rbxassetid://%d", idNumber)
    end
    local function ensureMusic(): Sound?
        if musicSound and musicSound.Parent then
            return musicSound
        end
        -- Respect EffectsEnabled toggle: if disabled, do not create music
        local okGui, pg = pcall(function()
            return player:WaitForChild("PlayerGui")
        end)
        if okGui and pg and pg:GetAttribute("EffectsEnabled") == false then
            return nil
        end
        local ids = (Constants.AUDIO and Constants.AUDIO.MusicLoopIds) or {}
        for _, id in ipairs(ids) do
            if typeof(id) == "number" and id > 0 then
                local s = Instance.new("Sound")
                s.Name = "BG_Music"
                s.SoundId = buildAssetUri(id)
                s.Looped = true
                s.Volume = baseVolume
                s.RollOffMaxDistance = 100000 -- ensure no attenuation
                s.Parent = SoundService
                local ok = pcall(function()
                    SoundService:PlayLocalSound(s)
                end)
                if ok then
                    musicSound = s
                    return musicSound
                else
                    s:Destroy()
                end
            end
        end
        return nil
    end

    local function tweenVolume(target: number, duration: number)
        local s = musicSound
        if not s or not s.Parent then
            return
        end
        -- simple manual tween to avoid services; small and allocation-light
        local startV = s.Volume
        local t0 = os.clock()
        if duration <= 0 then
            s.Volume = target
            return
        end
        task.spawn(function()
            while s and s.Parent do
                local t = (os.clock() - t0) / duration
                if t >= 1 then
                    s.Volume = target
                    break
                end
                local v = startV + (target - startV) * t
                s.Volume = v
                RunService.Heartbeat:Wait()
            end
        end)
    end

    local function duckTemp(factor: number, fadeOut: number, fadeIn: number, hold: number)
        local s = ensureMusic()
        if not s then
            return
        end
        local minVol = baseVolume * math.clamp(factor, 0, 1)
        tweenVolume(minVol, fadeOut)
        lastDuckUntil = os.clock() + (hold or 0)
        task.delay((hold or 0), function()
            -- only fade in if no newer duck extended the timer
            if os.clock() >= lastDuckUntil then
                tweenVolume(baseVolume, fadeIn)
            end
        end)
    end

    -- Start music once HUD exists or shortly after script init
    task.defer(function()
        ensureMusic()
    end)

    -- Hooks
    local function onGameOver()
        local cfg = (Constants.AUDIO and Constants.AUDIO.MusicDuck) or {}
        duckTemp(cfg.GameOver or 0.35, cfg.FadeOut or 0.18, cfg.FadeIn or 0.30, 9999) -- remain ducked
    end
    local function onPowerup()
        local cfg = (Constants.AUDIO and Constants.AUDIO.MusicDuck) or {}
        duckTemp(cfg.Powerup or 0.70, cfg.FadeOut or 0.18, cfg.FadeIn or 0.30, cfg.PowerupHold or 1.2)
    end
    -- Assign to outer references
    music_onGameOverRef = onGameOver
    music_onPowerupRef = onPowerup
end

-- Lane-Infos und clientseitige Visualisierung des Spurwechsels
-- Wichtige Konvention: links=+1, rechts=-1 (Server erwartet diese Richtung)
local LANES: { number } = (Constants and Constants.LANES) or { -5, 0, 5 }
local targetLaneIndex: number = 2 -- Start in der Mitte
-- Eff. seitliche Visualgeschwindigkeit: entspricht Server (LaneSwitchSpeed * LaneSwitchFactor)
local laneSwitchSpeed: number = (
    ((Constants and Constants.PLAYER and Constants.PLAYER.LaneSwitchSpeed) or 24)
    * ((Constants and Constants.PLAYER and (Constants.PLAYER.LaneSwitchFactor or 1)) or 1)
)
-- Prädizierte X-Position, der die Kamera lateral folgt (Z/Y von HRP)
local predictedX: number? = nil

-- VFX (clientseitig) für Powerups
local magnetEmitter: ParticleEmitter? = nil
local shieldField: ForceField? = nil

local function ensureVFX()
    local char = player.Character or player.CharacterAdded:Wait()
    local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not hrp then
        return
    end
    if not magnetEmitter then
        -- Erzeuge einen dezenten blauen Partikelring für Magnet
        local att = hrp:FindFirstChild("VFX_Magnet") :: Attachment?
        if not att then
            local newAtt = Instance.new("Attachment")
            newAtt.Name = "VFX_Magnet"
            newAtt.Parent = hrp
            att = newAtt
        end
        local pe = Instance.new("ParticleEmitter")
        pe.Name = "MagnetPE"
        pe.Parent = att
        pe.Enabled = false
        pe.Rate = 10
        pe.Lifetime = NumberRange.new(0.4, 0.8)
        pe.Speed = NumberRange.new(0, 0)
        pe.Rotation = NumberRange.new(0, 360)
        pe.RotSpeed = NumberRange.new(40, 80)
        pe.SpreadAngle = Vector2.new(360, 360)
        pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.0) })
        pe.Color = ColorSequence.new(Color3.fromRGB(80, 180, 255))
        pe.LightInfluence = 0
        pe.LockedToPart = false
        magnetEmitter = pe
    end
    if not shieldField then
        -- Klassischer ForceField-Glanz für Schild
        local ff = Instance.new("ForceField")
        ff.Visible = false
        ff.Parent = char
        shieldField = ff
    end
end

-- Bei Respawn VFX-Referenzen zurücksetzen (werden lazy neu erstellt)
player.CharacterAdded:Connect(function()
    magnetEmitter = nil
    shieldField = nil
end)

-- Input: A/D or Left/Right to switch lanes
local function onInputBegan(input: InputObject, gpe: boolean)
    if gpe then
        return
    end
    -- A/D und Pfeile klassisch belegen
    if input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then
        LaneRequest:FireServer(1) -- links
        targetLaneIndex = math.clamp(targetLaneIndex + 1, 1, #LANES)
    elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
        LaneRequest:FireServer(-1) -- rechts
        targetLaneIndex = math.clamp(targetLaneIndex - 1, 1, #LANES)
    elseif input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.Space then
        ActionRequest:FireServer("Jump")
    elseif input.KeyCode == Enum.KeyCode.Down then
        -- Clientseitiges Gating: Während aktiver Roll kein erneutes Triggern/SFX
        if os.clock() < rollingUntilShared then
            return
        end
        ActionRequest:FireServer("Roll")
    end
end
UserInputService.InputBegan:Connect(onInputBegan)

-- Bind W/S exclusively to Jump/Roll and sink default movement
do
    local function handleJumpAction(_actionName: string, inputState: Enum.UserInputState, _input: InputObject)
        -- Always sink to block default forward movement
        if inputState == Enum.UserInputState.Begin then
            ActionRequest:FireServer("Jump")
        end
        return Enum.ContextActionResult.Sink
    end

    local function handleRollAction(_actionName: string, inputState: Enum.UserInputState, _input: InputObject)
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

        -- Gamepad-Unterstützung: A=Jump, B=Roll, DPad/Thumbstick links/rechts = Lane
        -- Hinweis: Spurwechsel-Konvention: links=+1, rechts=-1 (bewusst invertiert)
        local function handleLaneLeftGP(_name: string, state: Enum.UserInputState, _input: InputObject)
            if state == Enum.UserInputState.Begin then
                LaneRequest:FireServer(1) -- links
                targetLaneIndex = math.clamp(targetLaneIndex + 1, 1, #LANES)
            end
            return Enum.ContextActionResult.Sink
        end
        local function handleLaneRightGP(_name: string, state: Enum.UserInputState, _input: InputObject)
            if state == Enum.UserInputState.Begin then
                LaneRequest:FireServer(-1) -- rechts
                targetLaneIndex = math.clamp(targetLaneIndex - 1, 1, #LANES)
            end
            return Enum.ContextActionResult.Sink
        end
        ContextActionService:BindActionAtPriority(
            "Endless_Jump_GP",
            handleJumpAction,
            false,
            2000,
            Enum.KeyCode.ButtonA
        )
        ContextActionService:BindActionAtPriority(
            "Endless_Roll_GP",
            handleRollAction,
            false,
            2000,
            Enum.KeyCode.ButtonB
        )
        ContextActionService:BindActionAtPriority(
            "Endless_LaneLeft_GP",
            handleLaneLeftGP,
            false,
            2000,
            Enum.KeyCode.DPadLeft
        )
        ContextActionService:BindActionAtPriority(
            "Endless_LaneRight_GP",
            handleLaneRightGP,
            false,
            2000,
            Enum.KeyCode.DPadRight
        )

        -- Analoges Lane-Switching über linken Stick (Thumbstick1) mit Hysterese (Edge-Trigger)
        local lastStickSign = 0 -- -1 = rechts, +1 = links, 0 = neutral
        local threshold = 0.45
        local function handleLaneStickGP(_name: string, state: Enum.UserInputState, input: InputObject)
            -- Wir reagieren auf Begin/Change; analoger Wert in input.Position.X
            if state ~= Enum.UserInputState.Begin and state ~= Enum.UserInputState.Change then
                return Enum.ContextActionResult.Sink
            end
            local pos = input and input.Position or Vector3.new()
            local x = pos.X
            local sign = 0
            if x <= -threshold then
                sign = -1 -- rechts (gemäß Konvention)
            elseif x >= threshold then
                sign = 1 -- links
            end
            if sign == 0 then
                -- Zurück zur Neutralzone -> nächsten Edge erlauben
                if lastStickSign ~= 0 then
                    lastStickSign = 0
                end
                return Enum.ContextActionResult.Sink
            end
            if sign ~= lastStickSign then
                -- Edge-Trigger: einmaliger Spurwechsel pro Auslenkung
                if sign == 1 then
                    LaneRequest:FireServer(1) -- links
                    targetLaneIndex = math.clamp(targetLaneIndex + 1, 1, #LANES)
                else -- sign == -1
                    LaneRequest:FireServer(-1) -- rechts
                    targetLaneIndex = math.clamp(targetLaneIndex - 1, 1, #LANES)
                end
                lastStickSign = sign
            end
            return Enum.ContextActionResult.Sink
        end
        ContextActionService:BindActionAtPriority(
            "Endless_LaneStick_GP",
            handleLaneStickGP,
            false,
            2000,
            Enum.KeyCode.Thumbstick1
        )
    end)
end

-- Basic camera: follow behind
-- Lightweight camera shake (attribute gated)
local shakeAmp = 0.0 -- current amplitude in studs
local shakeFreq = 12.0 -- Hz
local shakeDecay = 4.5 -- per second exponential
local shakeSeed = math.random() * 1000

local function triggerShake(amp: number)
    -- respect PlayerGui ScreenShake attribute
    local pgOk, pg = pcall(function()
        return player:WaitForChild("PlayerGui")
    end)
    if not pgOk or not pg then
        return
    end
    if pg:GetAttribute("ScreenShake") == false then
        return
    end
    -- Note: we currently just bump amplitude; decay handled in RenderStepped
    shakeAmp = math.max(shakeAmp, amp)
end

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
            if d < bestDist then
                bestIdx, bestDist = i, d
            end
        end
        return bestIdx
    end
    targetLaneIndex = nearestLaneIndex(hrp.Position.X)
    predictedX = hrp.Position.X

    local last = os.clock()
    local tAccum = 0.0
    RunService.RenderStepped:Connect(function()
        local now = os.clock()
        local dt = math.clamp(now - last, 0, 1 / 15)
        last = now
        tAccum += dt

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

        -- Apply subtle camera shake if active
        if shakeAmp > 1e-3 then
            -- exponential decay
            shakeAmp *= math.exp(-shakeDecay * dt)
            -- two-axis oscillation with slight phase offset
            local sx = math.sin((tAccum + shakeSeed) * 2 * math.pi * shakeFreq)
            local sy = math.cos((tAccum * 0.93 + shakeSeed * 1.1) * 2 * math.pi * (shakeFreq * 0.85))
            local offset = Vector3.new(sx, sy, 0) * shakeAmp
            camPos += offset
        end

        workspace.CurrentCamera.CFrame = CFrame.new(camPos, pos + Vector3.new(0, 4, 12))
    end)
end

task.spawn(setupCamera)

-- Expose simple shake triggers for key events (optional use)
local function shakeCrash()
    triggerShake(0.7)
end
-- selene: allow(unused_variable)
local function _shakeHardLand()
    triggerShake(0.25)
end

-- Simple swipe gestures for mobile
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
                    if os.clock() < rollingUntilShared then
                        return
                    end
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
        local success = pcall(function()
            -- Disable default StarterPlayerScripts controls by setting PlatformStand
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid.PlatformStand = true
                task.wait(0.1)
                humanoid.PlatformStand = false
            end
        end)
        if not success then
            warn("[Client] Could not disable default movement controls")
        end
    end)
    -- Disable default Animate to avoid conflicts
    local animateScript = char:FindFirstChild("Animate")
    if animateScript and animateScript:IsA("LocalScript") then
        animateScript.Disabled = true
    end
    -- Safety check: ensure we have valid humanoid before proceeding
    if not hum then
        warn("[Client] Failed to setup animator - missing humanoid")
        return
    end
    
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then
        local success, newAnimator = pcall(function()
            local anim = Instance.new("Animator")
            anim.Parent = hum
            return anim
        end)
        if success and newAnimator then
            animator = newAnimator
        else
            warn("[Client] Failed to create animator")
            return
        end
    end
    
    -- Final safety check: ensure we have valid animator
    if not animator then
        warn("[Client] Failed to setup animator - could not create animator")
        return
    end

    local tracks: { [string]: AnimationTrack } = {}
    local current: string? = nil
    local lastRunPlayback: number = 1.0
    local runGraceUntil = 0.0 -- Grace nach Landung/Running, bevor wir Jump/Fall hart stoppen
    local jumpGraceUntil = 0.0 -- Grace direkt nach Jump-Start, damit Jump nicht sofort am Boden abgebrochen wird
    local rollingUntil = 0.0 -- während dieser Zeit darf Run/Fall Roll nicht übersteuern
    local airborneAt = 0.0 -- Zeitpunkt des Übergangs in die Luft (Freefall), um Fall verzögert zu starten
    local function load(name: string, id: number?, opts: { loop: boolean?, priority: Enum.AnimationPriority? }?)
        if not id or id == 0 then
            return
        end
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
    load("Run", Animations.Run, { loop = true, priority = Enum.AnimationPriority.Movement })
    load("Jump", Animations.Jump, { loop = false, priority = Enum.AnimationPriority.Action })
    load("Fall", Animations.Fall, { loop = true, priority = Enum.AnimationPriority.Movement })
    load("Slide", Animations.Slide, { loop = false, priority = Enum.AnimationPriority.Action })

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
            -- Starte Fall nicht sofort, sondern merke Zeitpunkt für sanften Delay
            airborneAt = os.clock()
        elseif new == Enum.HumanoidStateType.Landed then
            -- Ensure fall/jump stop immediately on landing
            if tracks["Fall"] then
                tracks["Fall"]:Stop(0.05)
            end
            if tracks["Jump"] then
                tracks["Jump"]:Stop(0.05)
            end
            runGraceUntil = os.clock() + 0.3
            airborneAt = 0
            play("Run", 0.05, true)
        elseif new == Enum.HumanoidStateType.Running or new == Enum.HumanoidStateType.RunningNoPhysics then
            runGraceUntil = os.clock() + 0.3
            airborneAt = 0
            play("Run", 0.05, true)
        elseif new == Enum.HumanoidStateType.Seated then
            -- keep run stopped when seated
            if tracks["Run"] then
                tracks["Run"]:Stop(0.1)
            end
        end
    end)

    -- drive run animation by forward (Z-axis) speed and adjust playback speed (configurable, smoothed)
    local lastPos: Vector3? = nil
    local smoothedSpeed = 0.0
    RunService.RenderStepped:Connect(function(dt)
        if not char.Parent then
            return
        end
        local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not hrp then
            return
        end
        local pos = hrp.Position
        local speed = 0
        if lastPos then
            local delta = pos - lastPos
            -- Nur Vorwärtsgeschwindigkeit (Z), kein seitliches Lerp (X) einbeziehen
            speed = math.abs(delta.Z) / math.max(dt, 1 / 240)
        end
        lastPos = pos

        -- Exponential smoothing to avoid jitter from replication timing
        local tau = (Constants.ANIMATION and Constants.ANIMATION.RunPlayback.SmoothTau) or 0.2
        local alpha = math.clamp(dt / math.max(tau, 1e-3), 0, 1)
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
                    if tracks["Fall"] and tracks["Fall"].IsPlaying then
                        tracks["Fall"]:Stop(0.05)
                    end
                    if tracks["Jump"] and tracks["Jump"].IsPlaying then
                        tracks["Jump"]:Stop(0.05)
                    end
                    play("Run", 0.06, true)
                end
            else
                -- Grounded und keine luftbezogenen Tracks -> Run sicherstellen
                play("Run", 0.06)
            end

            -- Update run playback speed smoothly per Constants.ANIMATION.RunPlayback
            local runTrack = tracks["Run"]
            if runTrack and runTrack.IsPlaying then
                local cfg = (Constants.ANIMATION and Constants.ANIMATION.RunPlayback) or {}
                local speedAt1 = cfg.SpeedAtRate1 or 28
                local exp = cfg.Exponent or 1.0
                local minR = cfg.MinRate or 0.9
                local maxR = cfg.MaxRate or 1.8
                local thr = cfg.ChangeThreshold or 0.03
                local ratio = smoothedSpeed / math.max(speedAt1, 0.001)
                local target = math.pow(math.clamp(ratio, 0.01, 10), exp)
                target = math.clamp(target, minR, maxR)
                if math.abs((lastRunPlayback or 1) - target) > thr then
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
            local now = os.clock()
            -- Starte Fall erst nach kurzem Luft-Zeitpuffer, um Mikroflicker zu vermeiden
            if not jumpPlaying and not fallPlaying then
                if airborneAt > 0 and (now - airborneAt) >= 0.08 then
                    play("Fall", 0.05, true)
                end
            end
        end
    end)

    -- Optional: naive Slide visual (if no Slide anim). Slightly tilt/offset for 0.5s when S pressed
    UserInputService.InputBegan:Connect(function(input, gpe)
        -- Für W/S lokale Animationen auch dann erlauben, wenn das Event via CAS gesunken wurde
        if gpe and not (input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.S) then
            return
        end
        local grounded = hum.FloorMaterial ~= Enum.Material.Air
        if input.KeyCode == Enum.KeyCode.S then
            -- Während aktiver Slide keine erneute Auslösung / kein SFX
            if os.clock() < math.max(rollingUntil, rollingUntilShared) then
                return
            end
            -- Slide starten: Boden/Luft identisch behandeln (Server spiegelt dies)
            local duration = (Constants.PLAYER and Constants.PLAYER.RollDuration) or 0.6
            rollingUntil = os.clock() + duration
            rollingUntilShared = rollingUntil
            -- Stoppe Jump/Fall und spiele Slide
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
        elseif input.KeyCode == Enum.KeyCode.W then
            -- Jump sofort lokal triggern (Responsiveness): am Boden ODER während aktiver Slide
            local slidingNow = os.clock() < math.max(rollingUntil, rollingUntilShared)
            if grounded or slidingNow then
                -- Wechsel auf Jump: Slide sofort freigeben und evtl. Track stoppen
                rollingUntil = 0
                rollingUntilShared = 0
                if tracks["Slide"] and tracks["Slide"].IsPlaying then
                    tracks["Slide"]:Stop(0.05)
                end
                jumpGraceUntil = os.clock() + 0.3
                play("Jump", 0.05, true)
            end
        end
    end)
    -- Slide-Ende-Check wird im bestehenden RenderStepped (Playback/State) mit erledigt

    -- Serverseitige ActionSync-Events direkt im Animator-Context spiegeln (damit wir Zugriff auf Tracks/Play haben)
    if ActionSync then
        ActionSync.OnClientEvent:Connect(function(info)
            local action = info and info.action
            if not action then
                return
            end
            if action == "Roll" then
                local duration = (Constants.PLAYER and Constants.PLAYER.RollDuration) or 0.6
                rollingUntil = os.clock() + duration
                rollingUntilShared = rollingUntil
                -- Stoppe Jump/Fall und spiele Slide
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
                local vcfg = (Constants.AUDIO and Constants.AUDIO.SFXVolumes) or {}
                local vMaster = (vcfg.Master or 1.0)
                playSfx(
                    (Constants.AUDIO and Constants.AUDIO.SlideSoundIds) or {},
                    "SlideSFX",
                    (vcfg.Slide or 0.6) * vMaster
                )
            elseif action == "Jump" then
                rollingUntil = 0
                rollingUntilShared = 0
                if tracks["Slide"] and tracks["Slide"].IsPlaying then
                    tracks["Slide"]:Stop(0.05)
                end
                jumpGraceUntil = os.clock() + 0.3
                play("Jump", 0.05, true)
                local vcfg = (Constants.AUDIO and Constants.AUDIO.SFXVolumes) or {}
                local vMaster = (vcfg.Master or 1.0)
                playSfx(
                    (Constants.AUDIO and Constants.AUDIO.JumpSoundIds) or {},
                    "JumpSFX",
                    (vcfg.Jump or 0.6) * vMaster
                )
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
local cachedEvent: TextLabel? = nil
local cachedMult: TextLabel? = nil

-- Create a minimal HUD if none exists (fallback)
local function _ensureHUD(): ScreenGui
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
        lbl.Size = UDim2.fromOffset(160, 40)
        lbl.Position = pos
        lbl.Parent = hud
        return lbl
    end

    makeLabel("Distance", UDim2.fromOffset(20, 20)).Text = "0m"
    makeLabel("Coins", UDim2.fromOffset(20, 70)).Text = "0"
    makeLabel("Speed", UDim2.fromOffset(20, 120)).Text = "0"
    makeLabel("Magnet", UDim2.fromOffset(20, 170)).Text = ""
    makeLabel("Shield", UDim2.fromOffset(20, 220)).Text = ""
    makeLabel("Event", UDim2.fromOffset(20, 270)).Text = ""
    makeLabel("Multiplier", UDim2.fromOffset(20, 320)).Text = "x✦"

    cachedHUD = hud
    cachedDist = hud:FindFirstChild("Distance") :: TextLabel?
    cachedCoins = hud:FindFirstChild("Coins") :: TextLabel?
    cachedSpeed = hud:FindFirstChild("Speed") :: TextLabel?
    cachedMagnet = hud:FindFirstChild("Magnet") :: TextLabel?
    cachedShield = hud:FindFirstChild("Shield") :: TextLabel?
    cachedEvent = hud:FindFirstChild("Event") :: TextLabel?
    cachedMult = hud:FindFirstChild("Multiplier") :: TextLabel?
    return hud
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
        lbl.Size = UDim2.fromOffset(160, 40)
        lbl.Position = pos
        lbl.Parent = hud
        return lbl
    end

    makeLabel("Distance", UDim2.fromOffset(20, 20)).Text = "0m"
    makeLabel("Coins", UDim2.fromOffset(20, 70)).Text = "0"
    makeLabel("Speed", UDim2.fromOffset(20, 120)).Text = "0"
    makeLabel("Magnet", UDim2.fromOffset(20, 170)).Text = ""
    makeLabel("Shield", UDim2.fromOffset(20, 220)).Text = ""
    makeLabel("Event", UDim2.fromOffset(20, 270)).Text = ""
    makeLabel("Multiplier", UDim2.fromOffset(20, 320)).Text = "x✦"

    cachedHUD = hud
    cachedDist = hud:FindFirstChild("Distance") :: TextLabel?
    cachedCoins = hud:FindFirstChild("Coins") :: TextLabel?
    cachedSpeed = hud:FindFirstChild("Speed") :: TextLabel?
    cachedMagnet = hud:FindFirstChild("Magnet") :: TextLabel?
    cachedShield = hud:FindFirstChild("Shield") :: TextLabel?
    cachedEvent = hud:FindFirstChild("Event") :: TextLabel?
    cachedMult = hud:FindFirstChild("Multiplier") :: TextLabel?
    return hud
end

-- Activate singleton enforcement once
local function enforceSingleHUD()
    local sg = player:WaitForChild("PlayerGui")
    local hudCount = 0
    local lastHUD: ScreenGui? = nil
    for _, child in ipairs(sg:GetChildren()) do
        if child:IsA("ScreenGui") and child:GetAttribute("EndlessHUD") then
            hudCount += 1
            lastHUD = child
        end
    end
    -- Remove duplicates, keep the last one
    if hudCount > 1 then
        for _, child in ipairs(sg:GetChildren()) do
            if child:IsA("ScreenGui") and child:GetAttribute("EndlessHUD") and child ~= lastHUD then
                child:Destroy()
            end
        end
    end
end
enforceSingleHUD()

local function resolveHUD(): ScreenGui?
    if cachedHUD and cachedHUD.Parent then
        return cachedHUD
    end
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
        return hud
    end
    return nil
end

local function resolveLabels()
    local hud = resolveHUD()
    if not hud then
        return
    end
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
    if not (cachedEvent and cachedEvent.Parent == hud) then
        cachedEvent = hud:FindFirstChild("Event") :: TextLabel?
    end
    if not (cachedMult and cachedMult.Parent == hud) then
        cachedMult = hud:FindFirstChild("Multiplier") :: TextLabel?
    end
end

UpdateHUD.OnClientEvent:Connect(function(payload)
    if Constants.DEBUG_LOGS then
        print(
            "[Client] UpdateHUD received",
            payload and payload.distance,
            payload and payload.coins,
            payload and payload.speed
        )
    end
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
    if cachedDist and cachedDist:IsA("TextLabel") then
        cachedDist.Text = string.format("%dm", payload.distance or 0)
    end
    if cachedCoins and cachedCoins:IsA("TextLabel") then
        cachedCoins.Text = string.format("%d", payload.coins or 0)
    end
    if cachedSpeed and cachedSpeed:IsA("TextLabel") then
        cachedSpeed.Text = string.format("%d", payload.speed or 0)
    end
    if cachedMagnet and cachedMagnet:IsA("TextLabel") then
        local secs = math.max(0, (payload.magnet or 0))
        cachedMagnet.Text = secs > 0 and string.format("Magnet: %.0fs", secs) or ""
    end
    if cachedShield and cachedShield:IsA("TextLabel") then
        local hits = payload.shield or 0
        local secs = math.max(0, (payload.shieldTime or 0))
        if secs > 0 then
            cachedShield.Text = string.format("Schild: %.0fs", secs)
        else
            cachedShield.Text = hits > 0 and string.format("Schild: %d", hits) or ""
        end
    end
    if cachedEvent and cachedEvent:IsA("TextLabel") then
        local secs = math.max(0, (payload.doubleCoins or 0))
        cachedEvent.Text = secs > 0 and string.format("Double Coins: %.0fs", secs) or ""
    end
    if cachedMult and cachedMult:IsA("TextLabel") then
        local m = tonumber(payload.multiplier or 1) or 1
        cachedMult.Text = string.format("x%.1f", m)
    end

    -- VFX-Toggling (clientseitig, basierend auf servergetakteten HUD-States)
    ensureVFX()
    if payload.magnet ~= nil then
        local magnetSecs = math.max(0, (payload.magnet or 0))
        if magnetEmitter then
            magnetEmitter.Enabled = magnetSecs > 0
        end
    end
    local shieldHits = payload.shield or 0
    local shieldSecs = math.max(0, (payload.shieldTime or 0))
    if shieldField then
        shieldField.Visible = (shieldHits > 0) or (shieldSecs > 0)
    end
end)

-- Coin pickup SFX (local)
do
    local function buildAssetUri(idNumber: number?): string
        if not idNumber or idNumber == 0 then
            return ""
        end
        return string.format("rbxassetid://%d", idNumber)
    end
    local function playFirst(ids: { number }?, name: string, volume: number)
        if not ids or #ids == 0 then
            return
        end
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
                    task.delay(2, function()
                        if s and s.Parent then
                            s:Destroy()
                        end
                    end)
                    return
                else
                    if s then
                        s:Destroy()
                    end
                end
            end
        end
    end
    local function playCoinSound()
        local ids = (Constants.AUDIO and Constants.AUDIO.CoinSoundIds) or {}
        local vcfg = (Constants.AUDIO and Constants.AUDIO.SFXVolumes) or {}
        local vMaster = (vcfg.Master or 1.0)
        playFirst(ids, "CoinPickupSFX", (vcfg.Coin or 0.5) * vMaster)
    end
    if CoinPickup then
        CoinPickup.OnClientEvent:Connect(playCoinSound)
    end
end

-- GameOver overlay listener
local GameOver = Remotes:WaitForChild("GameOver") :: RemoteEvent
GameOver.OnClientEvent:Connect(function()
    if music_onGameOverRef then
        music_onGameOverRef()
    end
    -- Trigger a brief camera shake on crash (if enabled)
    pcall(function()
        shakeCrash()
    end)
    -- Crash/GameOver SFX
    task.spawn(function()
        local ids = (Constants.AUDIO and Constants.AUDIO.CrashSoundIds) or {}
        local played = false
        local function tryPlayList(list: { number }?, name: string, volume: number)
            if played then
                return
            end
            if not list or #list == 0 then
                return
            end
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
                        task.delay(2, function()
                            if s and s.Parent then
                                s:Destroy()
                            end
                        end)
                        return
                    else
                        if s then
                            s:Destroy()
                        end
                    end
                end
            end
        end
        -- 1) Crash-Kandidaten
        local vcfg = (Constants.AUDIO and Constants.AUDIO.SFXVolumes) or {}
        local vMaster = (vcfg.Master or 1.0)
        tryPlayList(ids, "CrashSFX", (vcfg.Crash or 0.8) * vMaster)
        -- 2) Fallback: Powerup-Kandidaten
        if not played then
            tryPlayList(
                (Constants.AUDIO and Constants.AUDIO.PowerupSoundIds) or {},
                "CrashFallbackPowerup",
                (vcfg.Powerup or 0.6) * vMaster
            )
        end
        -- 3) Fallback: Coin-Kandidaten
        if not played then
            tryPlayList(
                (Constants.AUDIO and Constants.AUDIO.CoinSoundIds) or {},
                "CrashFallbackCoin",
                (vcfg.Coin or 0.5) * vMaster
            )
        end
    end)
    local playerGui = player:WaitForChild("PlayerGui")
    if playerGui:FindFirstChild("GameOverOverlay") then
        return
    end

    local overlay = Instance.new("ScreenGui")
    overlay.Name = "GameOverOverlay"
    overlay.ResetOnSpawn = false

    local frame = Instance.new("Frame")
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.fromScale(0.5, 0.5)
    frame.Size = UDim2.fromOffset(300, 200)
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
    menu.Position = UDim2.fromScale(0.1, 0.5)
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
        -- Öffne HUD-Hauptmenü und schließe Overlay
        local pg = player:WaitForChild("PlayerGui")
        local hud = pg:FindFirstChild("HUD") or pg:FindFirstChildWhichIsA("ScreenGui")
        if hud and hud:IsA("ScreenGui") then
            local menuP = hud:FindFirstChild("MenuPanel")
            local shopP = hud:FindFirstChild("ShopPanel")
            if shopP and shopP:IsA("Frame") then
                shopP.Visible = false
            end
            if menuP and menuP:IsA("Frame") then
                menuP.Visible = true
            end
        end
        overlay:Destroy()
    end)
    shop.MouseButton1Click:Connect(function()
        -- Öffne HUD-Shop und schließe Overlay
        local pg = player:WaitForChild("PlayerGui")
        local hud = pg:FindFirstChild("HUD") or pg:FindFirstChildWhichIsA("ScreenGui")
        if hud and hud:IsA("ScreenGui") then
            local menuP = hud:FindFirstChild("MenuPanel")
            local shopP = hud:FindFirstChild("ShopPanel")
            if menuP and menuP:IsA("Frame") then
                menuP.Visible = false
            end
            if shopP and shopP:IsA("Frame") then
                shopP.Visible = true
            end
        end
        overlay:Destroy()
    end)
end)

-- Powerup Pickup Feedback (optional placeholder)
if PowerupPickup then
    PowerupPickup.OnClientEvent:Connect(function(_info)
        -- SFX für Powerup using the global playSfx helper
        local powerupIds = (Constants.AUDIO and Constants.AUDIO.PowerupSoundIds) or {}
        local vcfg = (Constants.AUDIO and Constants.AUDIO.SFXVolumes) or {}
        local vMaster = (vcfg.Master or 1.0)
        playSfx(powerupIds, "PowerupSFX", (vcfg.Powerup or 0.6) * vMaster)
        if music_onPowerupRef then
            music_onPowerupRef()
        end
    end)
end

-- Event announcements toast
if EventAnnounce then
    EventAnnounce.OnClientEvent:Connect(function(info)
        local kind = info and info.kind
        if kind == "DoubleCoins" then
            -- Reuse simple SFX helper and screen message via HUD ensure
            local hud = ensureHUD()
            if not hud then
                warn("[Client] Could not create HUD for event announcement")
                return
            end
            -- lightweight toast using a temporary TextLabel at top center
            local toast = hud:FindFirstChild("EventToast") :: TextLabel?
            if not toast then
                local newToast = Instance.new("TextLabel")
                newToast.Name = "EventToast"
                newToast.BackgroundTransparency = 0.2
                newToast.BackgroundColor3 = Color3.fromRGB(35, 80, 35)
                newToast.TextColor3 = Color3.new(1, 1, 1)
                newToast.Font = Enum.Font.GothamBold
                newToast.TextScaled = true
                newToast.Size = UDim2.fromOffset(280, 36)
                newToast.AnchorPoint = Vector2.new(0.5, 0)
                newToast.Position = UDim2.fromScale(0.5, 0.05)
                newToast.Visible = false
                newToast.Parent = hud
                toast = newToast
            end
            if toast then
                toast.Text = "Event: Double Coins!"
                toast.Visible = true
                task.delay(2.0, function()
                    if toast and toast.Parent then
                        toast.Visible = false
                    end
                end)
            end
        end
    end)
end
