--!strict
-- Arena Manager: Verwaltet Arenen, Spieler-Instanzen und Combat-Sessions

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ArenaConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ArenaConstants"))

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MoveRequest = Remotes:WaitForChild("MoveRequest") :: RemoteEvent
local CombatRequest = Remotes:WaitForChild("CombatRequest") :: RemoteEvent
local CombatSync = Remotes:WaitForChild("CombatSync") :: RemoteEvent
local UpdatePlayerHUD = Remotes:WaitForChild("UpdatePlayerHUD") :: RemoteEvent
local _EnemyDeath = Remotes:WaitForChild("EnemyDeath") :: RemoteEvent -- Für später
local _LootDrop = Remotes:WaitForChild("LootDrop") :: RemoteEvent -- Für später
local _ArenaComplete = Remotes:WaitForChild("ArenaComplete") :: RemoteEvent -- Für später

-- Typen
export type PlayerState = {
    Player: Player,
    Character: Model?,
    Humanoid: Humanoid?,
    HRP: BasePart?,

    -- Combat Stats
    Health: number,
    MaxHealth: number,
    Mana: number,
    MaxMana: number,
    Stamina: number,
    MaxStamina: number,

    -- Progression
    Level: number,
    Experience: number,
    Strength: number,
    Intelligence: number,
    Defense: number,

    -- Combat State
    LastDamageTime: number,
    AttackCooldownUntil: number,
    IsBlocking: boolean,
    StatusEffects: { string },

    -- Arena
    ArenaId: string?,
    Position: Vector3,
    TargetPosition: Vector3,
    Rotation: number,

    -- Equipment
    EquippedWeapon: string?,
    EquippedArmor: { string },

    -- Internal
    HudUpdateAccumulator: number,
}

export type ArenaState = {
    Id: string,
    Players: { PlayerState },
    Enemies: { Model },
    Center: Vector3,
    Size: Vector3,
    Active: boolean,
    CurrentWave: number,
    EnemiesRemaining: number,
    WaveStartTime: number,
}

-- Globaler State
local playerStates: { [Player]: PlayerState } = {}
local arenas: { [string]: ArenaState } = {}
local nextArenaId = 1

-- Hilfsfunktionen
local function createArenaId(): string
    local id = string.format("Arena_%03d", nextArenaId)
    nextArenaId += 1
    return id
end

local function getOrCreatePlayerState(player: Player): PlayerState
    if not playerStates[player] then
        local character = player.Character
        local humanoid = character and character:FindFirstChild("Humanoid") :: Humanoid?
        local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

        playerStates[player] = {
            Player = player,
            Character = character,
            Humanoid = humanoid,
            HRP = hrp,

            -- Base stats
            Health = ArenaConstants.PLAYER.BaseHealth,
            MaxHealth = ArenaConstants.PLAYER.BaseHealth,
            Mana = ArenaConstants.PLAYER.BaseMana,
            MaxMana = ArenaConstants.PLAYER.BaseMana,
            Stamina = ArenaConstants.PLAYER.BaseStamina,
            MaxStamina = ArenaConstants.PLAYER.BaseStamina,

            -- Starting progression
            Level = ArenaConstants.PLAYER.StartLevel,
            Experience = 0,
            Strength = 5,
            Intelligence = 5,
            Defense = 5,

            -- Combat state
            LastDamageTime = 0,
            AttackCooldownUntil = 0,
            IsBlocking = false,
            StatusEffects = {},

            -- Arena
            ArenaId = nil,
            Position = Vector3.zero,
            TargetPosition = Vector3.zero,
            Rotation = 0,

            -- Equipment
            EquippedWeapon = nil,
            EquippedArmor = {},

            -- Internal
            HudUpdateAccumulator = 0,
        }

        -- Setze Humanoid-Eigenschaften
        if humanoid then
            humanoid.MaxHealth = ArenaConstants.PLAYER.BaseHealth
            humanoid.Health = ArenaConstants.PLAYER.BaseHealth
            humanoid.WalkSpeed = ArenaConstants.PLAYER.MoveSpeed
        end

        -- Setze NetworkOwner für Server-Authority
        if hrp then
            hrp:SetNetworkOwner(nil)
        end
    end

    return playerStates[player]
end

local function createArena(): ArenaState
    local arenaId = createArenaId()
    local center = ArenaConstants.ARENA.Center

    -- Erstelle Arena-Geometrie
    local arenaFolder = Instance.new("Folder")
    arenaFolder.Name = arenaId
    arenaFolder.Parent = Workspace:FindFirstChild("Arenas") or Workspace

    -- Arena-Boden
    local floor = Instance.new("Part")
    floor.Name = "Floor"
    floor.Size = ArenaConstants.ARENA.Size
    floor.Position = center
    floor.Anchored = true
    floor.Color = Color3.fromRGB(100, 80, 60)
    floor.Material = Enum.Material.Concrete
    floor.Parent = arenaFolder

    -- Arena-Wände (unsichtbare Kollision)
    local function createWall(name: string, size: Vector3, position: Vector3)
        local wall = Instance.new("Part")
        wall.Name = name
        wall.Size = size
        wall.Position = position
        wall.Anchored = true
        wall.Transparency = 0.8
        wall.Color = Color3.fromRGB(150, 150, 150)
        wall.Material = Enum.Material.ForceField
        wall.Parent = arenaFolder
    end

    local arenaSize = ArenaConstants.ARENA.Size
    local wallThickness = 1
    local wallHeight = ArenaConstants.ARENA.WallHeight

    -- Nord, Süd, Ost, West Wände
    createWall(
        "NorthWall",
        Vector3.new(arenaSize.X, wallHeight, wallThickness),
        center + Vector3.new(0, wallHeight / 2, arenaSize.Z / 2)
    )
    createWall(
        "SouthWall",
        Vector3.new(arenaSize.X, wallHeight, wallThickness),
        center + Vector3.new(0, wallHeight / 2, -arenaSize.Z / 2)
    )
    createWall(
        "EastWall",
        Vector3.new(wallThickness, wallHeight, arenaSize.Z),
        center + Vector3.new(arenaSize.X / 2, wallHeight / 2, 0)
    )
    createWall(
        "WestWall",
        Vector3.new(wallThickness, wallHeight, arenaSize.Z),
        center + Vector3.new(-arenaSize.X / 2, wallHeight / 2, 0)
    )

    local arena: ArenaState = {
        Id = arenaId,
        Players = {},
        Enemies = {},
        Center = center,
        Size = ArenaConstants.ARENA.Size,
        Active = false,
        CurrentWave = 0,
        EnemiesRemaining = 0,
        WaveStartTime = 0,
    }

    arenas[arenaId] = arena
    return arena
end

local function spawnWave(arena: ArenaState)
    local waveConfig = ArenaConstants.WAVES
    local enemyCount = waveConfig.InitialEnemies + (arena.CurrentWave - 1) * waveConfig.EnemiesPerWave

    -- Spawne verschiedene Gegnertypen
    local enemyTypes = { "Dummy", "Warrior", "Archer" }

    for i = 1, enemyCount do
        local enemyType = enemyTypes[math.random(1, #enemyTypes)]

        -- Zufällige Spawn-Position am Rand der Arena
        local spawnAngle = (2 * math.pi * i) / enemyCount
        local spawnRadius = ArenaConstants.ARENA.EnemySpawnRadius
        local spawnPos = arena.Center
            + Vector3.new(math.cos(spawnAngle) * spawnRadius, 5, math.sin(spawnAngle) * spawnRadius)

        -- Lade EnemyAI-System
        local EnemyAI = require(script.Parent:WaitForChild("EnemyAI"))
        local enemy = EnemyAI.spawnEnemy(enemyType, spawnPos, arena.Id)

        if enemy then
            table.insert(arena.Enemies, enemy.Model)
        end
    end

    arena.EnemiesRemaining = enemyCount
    print(
        string.format(
            "[ArenaManager] Spawned wave %d with %d enemies in arena %s",
            arena.CurrentWave,
            enemyCount,
            arena.Id
        )
    )
end

local function startArena(arena: ArenaState)
    if arena.Active then
        return
    end

    arena.Active = true
    arena.CurrentWave = 1
    arena.WaveStartTime = os.clock()

    print(string.format("[ArenaManager] Starting arena %s with %d players", arena.Id, #arena.Players))

    -- Spawne erste Welle von Gegnern
    spawnWave(arena)
end

local function addPlayerToArena(player: Player, arenaId: string): boolean
    local arena = arenas[arenaId]
    if not arena or #arena.Players >= ArenaConstants.ARENA.MaxPlayersPerArena then
        return false
    end

    local playerState = getOrCreatePlayerState(player)
    playerState.ArenaId = arenaId

    -- Spawn-Position in Arena berechnen
    local spawnAngle = (2 * math.pi * #arena.Players) / ArenaConstants.ARENA.MaxPlayersPerArena
    local spawnRadius = ArenaConstants.ARENA.SpawnRadius
    local spawnPos = arena.Center
        + Vector3.new(math.cos(spawnAngle) * spawnRadius, 5, math.sin(spawnAngle) * spawnRadius)

    -- Teleportiere Spieler
    if playerState.Character and playerState.HRP then
        playerState.HRP.CFrame = CFrame.new(spawnPos)
        playerState.Position = spawnPos
        playerState.TargetPosition = spawnPos
    end

    table.insert(arena.Players, playerState)

    -- Aktualisiere Arena-Attribut für andere Systeme
    player:SetAttribute("InArena", true)
    player:SetAttribute("ArenaId", arenaId)

    print(
        string.format(
            "[ArenaManager] %s joined arena %s (%d/%d players)",
            player.Name,
            arenaId,
            #arena.Players,
            ArenaConstants.ARENA.MaxPlayersPerArena
        )
    )

    -- Starte Arena wenn genug Spieler vorhanden
    if #arena.Players >= 1 and not arena.Active then -- Mindestens 1 Spieler für Testing
        startArena(arena)
    end

    return true
end

local function removePlayerFromArena(player: Player)
    local playerState = playerStates[player]
    if not playerState or not playerState.ArenaId then
        return
    end

    local arena = arenas[playerState.ArenaId]
    if arena then
        -- Entferne aus Arena-Spielerliste
        for i, ps in ipairs(arena.Players) do
            if ps.Player == player then
                table.remove(arena.Players, i)
                break
            end
        end

        print(
            string.format(
                "[ArenaManager] %s left arena %s (%d players remaining)",
                player.Name,
                arena.Id,
                #arena.Players
            )
        )
    end

    playerState.ArenaId = nil
    player:SetAttribute("InArena", false)
    player:SetAttribute("ArenaId", nil)
end

-- Remote Event Handlers
MoveRequest.OnServerEvent:Connect(function(player: Player, direction: Vector3)
    local playerState = getOrCreatePlayerState(player)
    if not playerState.ArenaId then
        return
    end

    -- Normalisiere und skaliere Bewegungsrichtung
    local normalizedDir = direction.Unit
    local speed = ArenaConstants.PLAYER.MoveSpeed
    local newPosition = playerState.Position + normalizedDir * speed * RunService.Heartbeat:Wait()

    -- Begrenze Bewegung auf Arena
    local arena = arenas[playerState.ArenaId]
    if arena then
        local minX = arena.Center.X - arena.Size.X / 2
        local maxX = arena.Center.X + arena.Size.X / 2
        local minZ = arena.Center.Z - arena.Size.Z / 2
        local maxZ = arena.Center.Z + arena.Size.Z / 2

        newPosition = Vector3.new(
            math.clamp(newPosition.X, minX, maxX),
            arena.Center.Y + 3,
            math.clamp(newPosition.Z, minZ, maxZ)
        )
    end

    playerState.TargetPosition = newPosition
end)

CombatRequest.OnServerEvent:Connect(function(player: Player, action: string, target: Instance?, spellId: string?)
    local playerState = getOrCreatePlayerState(player)
    if not playerState.ArenaId then
        return
    end

    local now = os.clock()

    if action == "Attack" then
        -- Prüfe Cooldown
        if now < playerState.AttackCooldownUntil then
            return
        end

        -- Berechne Schaden
        local baseDamage = ArenaConstants.COMBAT.BaseAttackDamage
        local damage = baseDamage + playerState.Strength * 2

        -- Setze Cooldown
        playerState.AttackCooldownUntil = now + ArenaConstants.COMBAT.AttackCooldown

        -- Prüfe auf Gegner in Reichweite und füge Schaden zu
        local character = player.Character
        if character then
            local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
            if hrp then
                local arena = arenas[playerState.ArenaId]
                if arena then
                    -- Finde Gegner in Angriffsreichweite
                    for _, enemyModel in ipairs(arena.Enemies) do
                        if enemyModel.Parent then
                            local enemyHRP = enemyModel:FindFirstChild("HumanoidRootPart") :: BasePart?
                            if enemyHRP then
                                local distance = (enemyHRP.Position - hrp.Position).Magnitude
                                if distance <= ArenaConstants.COMBAT.AttackRange then
                                    -- Füge Schaden zu
                                    local EnemyAI = require(script.Parent:WaitForChild("EnemyAI"))
                                    EnemyAI.damageEnemy(enemyModel, damage)

                                    print(
                                        string.format(
                                            "[Combat] %s hits %s for %d damage",
                                            player.Name,
                                            enemyModel.Name,
                                            damage
                                        )
                                    )
                                    break -- Nur einen Gegner treffen
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Sende Feedback an Client
        CombatSync:FireClient(player, {
            action = "Attack",
            target = target,
            damage = damage,
            success = true,
        })

        print(string.format("[Combat] %s attacks for %d damage", player.Name, damage))
    elseif action == "Block" then
        playerState.IsBlocking = true
        CombatSync:FireClient(player, { action = "Block", success = true })
    elseif action == "Cast" and spellId then
        local spell = (ArenaConstants.MAGIC :: any)[spellId]
        if spell and playerState.Mana >= spell.ManaCost then
            playerState.Mana = math.max(0, playerState.Mana - spell.ManaCost)

            CombatSync:FireClient(player, {
                action = "Cast",
                spell = spellId,
                success = true,
            })

            print(string.format("[Combat] %s casts %s", player.Name, spellId))
        end
    end
end)

-- Haupt-Spielschleife
local lastUpdate = os.clock()
RunService.Heartbeat:Connect(function()
    local now = os.clock()
    local dt = now - lastUpdate
    lastUpdate = now

    -- Update aller Spielerzustände
    for player, state in pairs(playerStates) do
        if not player.Parent then
            -- Spieler hat das Spiel verlassen
            removePlayerFromArena(player)
            playerStates[player] = nil
            continue
        end

        -- Update Charakterreferenzen
        if not state.Character or state.Character.Parent == nil then
            state.Character = player.Character
            state.Humanoid = state.Character and state.Character:FindFirstChild("Humanoid") :: Humanoid?
            state.HRP = state.Character and state.Character:FindFirstChild("HumanoidRootPart") :: BasePart?

            if state.HRP then
                state.HRP:SetNetworkOwner(nil) -- Server-Authority
            end
        end

        -- Bewegung zur Zielposition (sanfte Interpolation)
        if state.HRP and state.ArenaId then
            local currentPos = state.HRP.Position
            local targetPos = state.TargetPosition
            local lerpFactor = math.min(1, dt * 8) -- Sanfte Bewegung

            local newPos = currentPos:Lerp(targetPos, lerpFactor)
            state.HRP.CFrame = CFrame.new(newPos)
            state.Position = newPos
        end

        -- Ressourcen-Regeneration (außerhalb Kampf)
        if now - state.LastDamageTime > ArenaConstants.PLAYER.OutOfCombatTime then
            state.Health = math.min(state.MaxHealth, state.Health + ArenaConstants.PLAYER.HealthRegenRate * dt)
            state.Mana = math.min(state.MaxMana, state.Mana + ArenaConstants.PLAYER.ManaRegenRate * dt)
            state.Stamina = math.min(state.MaxStamina, state.Stamina + ArenaConstants.PLAYER.StaminaRegenRate * dt)
        end

        -- Block-Status zurücksetzen (kurze Dauer)
        if state.IsBlocking then
            state.IsBlocking = false
        end

        -- HUD-Updates (gedrosselt)
        state.HudUpdateAccumulator += dt
        if state.HudUpdateAccumulator >= ArenaConstants.HUD.UpdateRate then
            state.HudUpdateAccumulator = 0

            UpdatePlayerHUD:FireClient(player, {
                health = math.floor(state.Health),
                maxHealth = state.MaxHealth,
                mana = math.floor(state.Mana),
                maxMana = state.MaxMana,
                stamina = math.floor(state.Stamina),
                maxStamina = state.MaxStamina,
                level = state.Level,
                experience = state.Experience,
                attackCooldown = math.max(0, state.AttackCooldownUntil - now),
            })
        end
    end
end)

-- Player-Lifecycle
Players.PlayerAdded:Connect(function(player)
    -- Initial-Setup wird bei Bedarf in getOrCreatePlayerState gemacht
    print(string.format("[ArenaManager] Player %s connected", player.Name))
end)

Players.PlayerRemoving:Connect(function(player)
    removePlayerFromArena(player)
    playerStates[player] = nil
    print(string.format("[ArenaManager] Player %s disconnected", player.Name))
end)

-- Öffentliche Funktionen für andere Scripts
local ArenaManager = {
    createArena = createArena,
    addPlayerToArena = addPlayerToArena,
    removePlayerFromArena = removePlayerFromArena,
    getPlayerState = function(player: Player)
        return playerStates[player]
    end,
    getArena = function(arenaId: string)
        return arenas[arenaId]
    end,
}

return ArenaManager
