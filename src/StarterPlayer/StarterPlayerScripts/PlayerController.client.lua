--!strict
-- Arena RPG Steuerung: Combat, Bewegung, Magie

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local _ContextActionService = game:GetService("ContextActionService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local _ArenaConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ArenaConstants"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Arena Remotes
local MoveRequest = Remotes:WaitForChild("MoveRequest") :: RemoteEvent
local CombatRequest = Remotes:WaitForChild("CombatRequest") :: RemoteEvent
local _CombatSync = Remotes:WaitForChild("CombatSync") :: RemoteEvent

-- Legacy Remotes (für Kompatibilität)
local PlayerJumped = Remotes:FindFirstChild("PlayerJumped") :: RemoteEvent?
local PlayerScored = Remotes:FindFirstChild("PlayerScored") :: RemoteEvent?
local PlayerDied = Remotes:FindFirstChild("PlayerDied") :: RemoteEvent?

local localPlayer = Players.LocalPlayer

local function setupCharacter(character: Model)
    local humanoid = character:WaitForChild("Humanoid") :: Humanoid
    local hrp = character:WaitForChild("HumanoidRootPart") :: BasePart

    humanoid.WalkSpeed = Config.MOVE_SPEED
    humanoid.JumpPower = Config.JUMP_POWER

    -- Z sperren, Ausrichtung entlang X erhalten
    task.defer(function()
        if hrp then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
    end)

    -- Kamera scriptable, seitlich versetzt
    local camera = workspace.CurrentCamera
    camera.CameraType = Enum.CameraType.Scriptable

    -- Seitliche Kamera-Führung und Z-Lock pro Frame
    local connA = RunService.RenderStepped:Connect(function()
        if not hrp or not character.Parent then
            return
        end
        -- Z-Achse hart auf Config.Z_LOCK fixieren
        local pos = hrp.Position
        if math.abs(pos.Z - Config.Z_LOCK) > 0.01 then
            hrp.CFrame =
                CFrame.new(Vector3.new(pos.X, pos.Y, Config.Z_LOCK), Vector3.new(pos.X + 1, pos.Y, Config.Z_LOCK))
            hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, hrp.AssemblyLinearVelocity.Y, 0)
        end

        local lookAt = hrp.Position + Vector3.new(Config.CAMERA.LookAheadX, 0, 0)
        local camPos = Vector3.new(
            hrp.Position.X - 5,
            hrp.Position.Y + Config.CAMERA.Height,
            hrp.Position.Z + Config.CAMERA.DistanceZ
        )
        camera.CFrame = CFrame.new(camPos, lookAt)
    end)

    -- Arena-Input: WASD für Bewegung, Maus für Combat
    local _movement = Vector3.zero
    local keysPressed = {
        W = false,
        A = false,
        S = false,
        D = false,
    }

    local function updateMovement()
        local moveVector = Vector3.zero
        if keysPressed.W then
            moveVector = moveVector + Vector3.new(0, 0, -1)
        end
        if keysPressed.S then
            moveVector = moveVector + Vector3.new(0, 0, 1)
        end
        if keysPressed.A then
            moveVector = moveVector + Vector3.new(-1, 0, 0)
        end
        if keysPressed.D then
            moveVector = moveVector + Vector3.new(1, 0, 0)
        end

        _movement = moveVector

        -- Sende Bewegung an Server (nur wenn in Arena)
        local isInArena = localPlayer:GetAttribute("InArena")
        if isInArena and moveVector.Magnitude > 0 then
            MoveRequest:FireServer(moveVector.Unit)
        end
    end

    local connB = UserInputService.InputBegan:Connect(function(input, gp)
        if gp then
            return
        end

        local isInArena = localPlayer:GetAttribute("InArena")

        -- Bewegungssteuerung
        if input.KeyCode == Enum.KeyCode.W then
            keysPressed.W = true
            updateMovement()
        elseif input.KeyCode == Enum.KeyCode.A then
            keysPressed.A = true
            updateMovement()
        elseif input.KeyCode == Enum.KeyCode.S then
            keysPressed.S = true
            updateMovement()
        elseif input.KeyCode == Enum.KeyCode.D then
            keysPressed.D = true
            updateMovement()
        -- Combat-Steuerung (nur in Arena)
        elseif isInArena and input.KeyCode == Enum.KeyCode.Space then
            -- Angriff
            CombatRequest:FireServer("Attack")
        elseif isInArena and (input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift) then
            -- Block
            CombatRequest:FireServer("Block")
        elseif isInArena and input.KeyCode == Enum.KeyCode.Q then
            -- Zauber 1 (Fireball)
            CombatRequest:FireServer("Cast", nil, "Fireball")
        elseif isInArena and input.KeyCode == Enum.KeyCode.E then
            -- Zauber 2 (Heal)
            CombatRequest:FireServer("Cast", nil, "Heal")
        -- Legacy Jump für Nicht-Arena-Bereiche
        elseif not isInArena and (input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Up) then
            if PlayerJumped then
                PlayerJumped:FireServer()
            end
        elseif not isInArena and input.KeyCode == Enum.KeyCode.S then
            humanoid.WalkSpeed = math.max(8, math.floor(Config.MOVE_SPEED / 2))
        end
    end)

    local connC = UserInputService.InputEnded:Connect(function(input, _gp)
        local isInArena = localPlayer:GetAttribute("InArena")

        -- Bewegungssteuerung Ende
        if input.KeyCode == Enum.KeyCode.W then
            keysPressed.W = false
            updateMovement()
        elseif input.KeyCode == Enum.KeyCode.A then
            keysPressed.A = false
            updateMovement()
        elseif input.KeyCode == Enum.KeyCode.S then
            keysPressed.S = false
            updateMovement()
            -- Legacy: Geschwindigkeit zurücksetzen wenn nicht in Arena
            if not isInArena then
                humanoid.WalkSpeed = Config.MOVE_SPEED
            end
        elseif input.KeyCode == Enum.KeyCode.D then
            keysPressed.D = false
            updateMovement()
        end
    end)

    -- Clean-up bei Charakterwechsel
    character.Destroying:Connect(function()
        connA:Disconnect()
        connB:Disconnect()
        connC:Disconnect()
    end)
end

-- Initial + Respawns
if localPlayer.Character then
    setupCharacter(localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(setupCharacter)

-- Beispiel-Helfer, kann später über Trigger/TouchEvents aufgerufen werden
-- Hinweis: Punktezählung/Death sollten über reale Trigger/Touch-Events im Level geschehen,
-- der Client meldet nur Events über Remotes an den Server.
local Mario2D = {}

function Mario2D.Score(amount: number)
    if PlayerScored then
        PlayerScored:FireServer(amount)
    end
end

function Mario2D.Die()
    if PlayerDied then
        PlayerDied:FireServer()
    end
end

return Mario2D
