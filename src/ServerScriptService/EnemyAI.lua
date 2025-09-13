--!strict
-- Enemy AI System: Spawning, AI-Verhalten, Combat für NPCs

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ArenaConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ArenaConstants"))

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local EnemyDeath = Remotes:WaitForChild("EnemyDeath") :: RemoteEvent
local LootDrop = Remotes:WaitForChild("LootDrop") :: RemoteEvent

-- AI State Machine Typen
export type EnemyAI = "Aggressive" | "Defensive" | "Balanced" | "Ranged" | "Caster"

export type EnemyState = {
    Model: Model,
    Humanoid: Humanoid,
    HRP: BasePart,

    -- Stats
    EnemyType: string,
    Health: number,
    MaxHealth: number,
    Damage: number,
    MoveSpeed: number,
    AttackRange: number,
    AttackCooldown: number,
    AggroRange: number,

    -- AI State
    AIType: EnemyAI,
    CurrentState: "Idle" | "Chase" | "Attack" | "Retreat" | "Dead",
    Target: Player?,
    LastAttackTime: number,
    LastStateChange: number,

    -- Arena
    ArenaId: string,
    SpawnPosition: Vector3,

    -- Rewards
    Gold: number,
    Experience: number,
}

-- Globaler State
local activeEnemies: { [Model]: EnemyState } = {}

-- Hilfsfunktionen für AI
local function findNearestPlayer(enemyPos: Vector3, arenaId: string, maxRange: number): Player?
    local nearestPlayer: Player?
    local nearestDistance = maxRange

    for _, player in ipairs(Players:GetPlayers()) do
        if player:GetAttribute("ArenaId") == arenaId then
            local character = player.Character
            if character then
                local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
                if hrp then
                    local distance = (hrp.Position - enemyPos).Magnitude
                    if distance < nearestDistance then
                        nearestPlayer = player
                        nearestDistance = distance
                    end
                end
            end
        end
    end

    return nearestPlayer
end

local function moveTowards(enemy: EnemyState, targetPosition: Vector3)
    local direction = (targetPosition - enemy.HRP.Position)
    direction = Vector3.new(direction.X, 0, direction.Z).Unit -- Nur horizontal bewegen

    -- Setze Bewegung
    local bodyVelocity = enemy.HRP:FindFirstChild("BodyVelocity") :: BodyVelocity?
    if not bodyVelocity then
        bodyVelocity = Instance.new("BodyVelocity")
        bodyVelocity.MaxForce = Vector3.new(4000, 0, 4000)
        bodyVelocity.Parent = enemy.HRP
    end

    if bodyVelocity then
        bodyVelocity.Velocity = direction * enemy.MoveSpeed
    end

    -- Rotiere zur Zielrichtung
    if direction.Magnitude > 0 then
        enemy.HRP.CFrame = CFrame.lookAt(enemy.HRP.Position, enemy.HRP.Position + direction)
    end
end

local function stopMovement(enemy: EnemyState)
    local bodyVelocity = enemy.HRP:FindFirstChild("BodyVelocity") :: BodyVelocity?
    if bodyVelocity then
        bodyVelocity.Velocity = Vector3.zero
    end
end

local function canAttackTarget(enemy: EnemyState, target: Player): boolean
    if not target.Character then
        return false
    end
    local targetHRP = target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not targetHRP then
        return false
    end

    local distance = (targetHRP.Position - enemy.HRP.Position).Magnitude
    return distance <= enemy.AttackRange
end

local function attackTarget(enemy: EnemyState, target: Player)
    local now = os.clock()
    if now - enemy.LastAttackTime < enemy.AttackCooldown then
        return
    end

    enemy.LastAttackTime = now

    -- Sende Attack-Event (für Damage-Berechnung an anderen System)
    EnemyDeath:FireAllClients(target, {
        action = "EnemyAttack",
        enemy = enemy.Model,
        damage = enemy.Damage,
        attacker = enemy.EnemyType,
    })

    print(string.format("[EnemyAI] %s attacks %s for %d damage", enemy.EnemyType, target.Name, enemy.Damage))
end

-- AI State Machine
local function updateEnemyAI(enemy: EnemyState, _dt: number)
    local now = os.clock()

    -- Prüfe auf Tod
    if enemy.Health <= 0 and enemy.CurrentState ~= "Dead" then
        enemy.CurrentState = "Dead"
        enemy.LastStateChange = now
        stopMovement(enemy)

        -- Loot-Drop
        LootDrop:FireAllClients({
            position = enemy.HRP.Position,
            gold = enemy.Gold,
            experience = enemy.Experience,
            enemyType = enemy.EnemyType,
        })

        -- Entferne Gegner nach kurzer Zeit
        task.delay(2, function()
            if enemy.Model.Parent then
                enemy.Model:Destroy()
                activeEnemies[enemy.Model] = nil
            end
        end)
        return
    end

    -- Finde nächstes Ziel
    local nearestPlayer = findNearestPlayer(enemy.HRP.Position, enemy.ArenaId, enemy.AggroRange)

    -- State Machine basierend auf AI-Typ
    if enemy.AIType == "Aggressive" then
        if nearestPlayer and enemy.CurrentState ~= "Dead" then
            enemy.Target = nearestPlayer

            if canAttackTarget(enemy, nearestPlayer) then
                if enemy.CurrentState ~= "Attack" then
                    enemy.CurrentState = "Attack"
                    enemy.LastStateChange = now
                    stopMovement(enemy)
                end
                attackTarget(enemy, nearestPlayer)
            else
                if enemy.CurrentState ~= "Chase" then
                    enemy.CurrentState = "Chase"
                    enemy.LastStateChange = now
                end
                local targetHRP = nearestPlayer.Character
                    and nearestPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
                if targetHRP then
                    moveTowards(enemy, targetHRP.Position)
                end
            end
        else
            if enemy.CurrentState ~= "Idle" then
                enemy.CurrentState = "Idle"
                enemy.LastStateChange = now
                stopMovement(enemy)
            end
            enemy.Target = nil
        end
    elseif enemy.AIType == "Ranged" then
        if nearestPlayer and enemy.CurrentState ~= "Dead" then
            enemy.Target = nearestPlayer
            local targetHRP = nearestPlayer.Character
                and nearestPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?

            if targetHRP then
                local distance = (targetHRP.Position - enemy.HRP.Position).Magnitude

                if distance <= enemy.AttackRange and distance > enemy.AttackRange * 0.5 then
                    -- Optimale Range: Angreifen
                    if enemy.CurrentState ~= "Attack" then
                        enemy.CurrentState = "Attack"
                        enemy.LastStateChange = now
                        stopMovement(enemy)
                    end
                    attackTarget(enemy, nearestPlayer)
                elseif distance < enemy.AttackRange * 0.5 then
                    -- Zu nah: Rückzug
                    if enemy.CurrentState ~= "Retreat" then
                        enemy.CurrentState = "Retreat"
                        enemy.LastStateChange = now
                    end
                    local retreatDirection = (enemy.HRP.Position - targetHRP.Position).Unit
                    local retreatTarget = enemy.HRP.Position + retreatDirection * 10
                    moveTowards(enemy, retreatTarget)
                else
                    -- Zu weit: Verfolgen
                    if enemy.CurrentState ~= "Chase" then
                        enemy.CurrentState = "Chase"
                        enemy.LastStateChange = now
                    end
                    moveTowards(enemy, targetHRP.Position)
                end
            end
        else
            if enemy.CurrentState ~= "Idle" then
                enemy.CurrentState = "Idle"
                enemy.LastStateChange = now
                stopMovement(enemy)
            end
            enemy.Target = nil
        end
    elseif enemy.AIType == "Defensive" then
        -- Defensive AI: Angriff nur wenn angegriffen
        if nearestPlayer and enemy.CurrentState ~= "Dead" then
            local targetHRP = nearestPlayer.Character
                and nearestPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
            if targetHRP then
                local distance = (targetHRP.Position - enemy.HRP.Position).Magnitude

                -- Nur angreifen wenn Spieler sehr nah ist
                if distance <= enemy.AttackRange * 0.7 then
                    enemy.Target = nearestPlayer
                    if enemy.CurrentState ~= "Attack" then
                        enemy.CurrentState = "Attack"
                        enemy.LastStateChange = now
                        stopMovement(enemy)
                    end
                    attackTarget(enemy, nearestPlayer)
                else
                    if enemy.CurrentState ~= "Idle" then
                        enemy.CurrentState = "Idle"
                        enemy.LastStateChange = now
                        stopMovement(enemy)
                    end
                end
            end
        else
            if enemy.CurrentState ~= "Idle" then
                enemy.CurrentState = "Idle"
                enemy.LastStateChange = now
                stopMovement(enemy)
            end
            enemy.Target = nil
        end
    end
end

-- Gegner-Erstellung
local function createEnemyModel(enemyType: string, position: Vector3, arenaId: string): Model?
    local enemyConfig = ArenaConstants.ENEMIES[enemyType]
    if not enemyConfig then
        warn(string.format("Unknown enemy type: %s", enemyType))
        return nil
    end

    -- Erstelle Model
    local model = Instance.new("Model")
    model.Name = enemyType .. "_AI"

    -- HumanoidRootPart
    local hrp = Instance.new("Part")
    hrp.Name = "HumanoidRootPart"
    hrp.Size = Vector3.new(2, 5, 1)
    hrp.Position = position
    hrp.Anchored = false
    hrp.CanCollide = true
    hrp.BrickColor = BrickColor.new("Bright red")
    hrp.Material = Enum.Material.Plastic
    hrp.Parent = model

    -- Humanoid
    local humanoid = Instance.new("Humanoid")
    humanoid.MaxHealth = enemyConfig.Health
    humanoid.Health = enemyConfig.Health
    humanoid.WalkSpeed = enemyConfig.MoveSpeed
    humanoid.JumpPower = 0 -- Keine Sprünge
    humanoid.Parent = model

    -- BodyPosition für bessere Bewegung
    local bodyPos = Instance.new("BodyPosition")
    bodyPos.MaxForce = Vector3.new(4000, 4000, 4000)
    bodyPos.Position = position
    bodyPos.Parent = hrp

    -- Visuelle Kennzeichnung
    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 100, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.Parent = hrp

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, 0, 0.6, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = enemyType
    nameLabel.TextColor3 = Color3.new(1, 1, 1)
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Parent = billboard

    local healthBar = Instance.new("Frame")
    healthBar.Size = UDim2.new(0.8, 0, 0.2, 0)
    healthBar.Position = UDim2.new(0.1, 0, 0.7, 0)
    healthBar.BackgroundColor3 = Color3.new(0.8, 0.2, 0.2)
    healthBar.BorderSizePixel = 0
    healthBar.Parent = billboard

    local healthFill = Instance.new("Frame")
    healthFill.Name = "HealthFill"
    healthFill.Size = UDim2.new(1, 0, 1, 0)
    healthFill.Position = UDim2.new(0, 0, 0, 0)
    healthFill.BackgroundColor3 = Color3.new(0.2, 0.8, 0.2)
    healthFill.BorderSizePixel = 0
    healthFill.Parent = healthBar

    -- Füge zur Arena hinzu
    local arenasFolder = Workspace:FindFirstChild("Arenas")
    local arenaFolder = arenasFolder and arenasFolder:FindFirstChild(arenaId)
    if arenaFolder then
        model.Parent = arenaFolder
    else
        model.Parent = Workspace
    end

    return model
end

local function spawnEnemy(enemyType: string, position: Vector3, arenaId: string): EnemyState?
    local enemyConfig = ArenaConstants.ENEMIES[enemyType]
    if not enemyConfig then
        return nil
    end

    local model = createEnemyModel(enemyType, position, arenaId)
    if not model then
        return nil
    end

    local humanoid = model:FindFirstChild("Humanoid") :: Humanoid?
    local hrp = model:FindFirstChild("HumanoidRootPart") :: BasePart?

    if not humanoid or not hrp then
        model:Destroy()
        return nil
    end

    local enemyState: EnemyState = {
        Model = model,
        Humanoid = humanoid,
        HRP = hrp,

        EnemyType = enemyType,
        Health = enemyConfig.Health,
        MaxHealth = enemyConfig.Health,
        Damage = enemyConfig.Damage,
        MoveSpeed = enemyConfig.MoveSpeed,
        AttackRange = enemyConfig.AttackRange,
        AttackCooldown = enemyConfig.AttackCooldown,
        AggroRange = enemyConfig.AggroRange,

        AIType = enemyConfig.AI :: EnemyAI,
        CurrentState = "Idle",
        Target = nil,
        LastAttackTime = 0,
        LastStateChange = os.clock(),

        ArenaId = arenaId,
        SpawnPosition = position,

        Gold = enemyConfig.Gold,
        Experience = enemyConfig.Experience,
    }

    activeEnemies[model] = enemyState

    -- Humanoid Death Handler
    humanoid.Died:Connect(function()
        if activeEnemies[model] then
            activeEnemies[model].Health = 0
        end
    end)

    print(string.format("[EnemyAI] Spawned %s in arena %s", enemyType, arenaId))
    return enemyState
end

-- Haupt-AI-Loop
RunService.Heartbeat:Connect(function()
    local dt = RunService.Heartbeat:Wait()

    -- Update alle aktiven Gegner
    for model, enemy in pairs(activeEnemies) do
        if not model.Parent then
            -- Gegner wurde entfernt
            activeEnemies[model] = nil
            continue
        end

        -- Health-Bar Update
        local billboard = enemy.HRP:FindFirstChild("BillboardGui")
        if billboard then
            local healthBar = billboard:FindFirstChild("Frame")
            if healthBar then
                local healthFill = healthBar:FindFirstChild("HealthFill") :: Frame?
                if healthFill then
                    local healthPercent = math.max(0, enemy.Health / enemy.MaxHealth)
                    healthFill.Size = UDim2.new(healthPercent, 0, 1, 0)
                end
            end
        end

        -- AI-Update
        updateEnemyAI(enemy, dt)
    end
end)

-- Öffentliche API
local EnemyAI = {
    spawnEnemy = spawnEnemy,
    getActiveEnemies = function()
        return activeEnemies
    end,
    damageEnemy = function(enemyModel: Model, damage: number)
        local enemy = activeEnemies[enemyModel]
        if enemy then
            enemy.Health = math.max(0, enemy.Health - damage)
            enemy.LastStateChange = os.clock() -- Trigger AI reaction
        end
    end,
}

return EnemyAI
