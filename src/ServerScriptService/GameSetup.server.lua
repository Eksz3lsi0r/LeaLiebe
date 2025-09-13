--!strict
-- Setzt eine einfache 2D-Welt entlang der X-Achse auf und stellt RemoteEvents bereit

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local _ArenaConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ArenaConstants"))

-- Roblox Gravity global setzen (optional; Studio Default ist bereits 196.2)
Workspace.Gravity = Config.GRAVITY

-- Remotes-Ordner absichern (Mapping erzeugt sie, aber falls live in Studio erstellt)
local remotesFolderAny = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolderAny or not remotesFolderAny:IsA("Folder") then
    local newFolder = Instance.new("Folder")
    newFolder.Name = "Remotes"
    newFolder.Parent = ReplicatedStorage
    remotesFolderAny = newFolder
end
local Remotes = remotesFolderAny :: Folder

local function ensureRemote(name: string)
    local rAny = Remotes:FindFirstChild(name)
    if rAny and rAny:IsA("RemoteEvent") then
        return rAny
    end
    local r = Instance.new("RemoteEvent")
    r.Name = name
    r.Parent = Remotes
    return r
end

local PlayerJumped = ensureRemote("PlayerJumped")
local PlayerScored = ensureRemote("PlayerScored")
local PlayerDied = ensureRemote("PlayerDied")
local StartGame = ensureRemote("StartGame")
local TeleportToLobby = ensureRemote("TeleportToLobby")
local EnterQueue = ensureRemote("EnterQueue")
local EnterArena = ensureRemote("EnterArena")

-- Einfache Queue-/Match-Parameter
local QUEUE = {
    MinPlayers = 1,
    QueueWait = 6.0, -- Sekunden bis Shop-Phase
    ShopWindow = 8.0, -- Sekunden Shop-Zeit
    ArenaDuration = 60.0, -- Sekunden bis automatische Rückkehr zur Lobby
}

-- Queue-Status
local queued: { [Player]: boolean } = {}
local queueActive = false

local function setInArena(player: Player, val: boolean)
    pcall(function()
        player:SetAttribute("InArena", val)
    end)
end

-- Basic Server-Logging/Handling
PlayerJumped.OnServerEvent:Connect(function(player)
    print(string.format("[Server] %s ist gesprungen", player.Name))
end)

-- Leaderstats anlegen
local function ensureLeaderstats(player: Player)
    local lsAny = player:FindFirstChild("leaderstats")
    if not lsAny or not lsAny:IsA("Folder") then
        local f = Instance.new("Folder")
        f.Name = "leaderstats"
        f.Parent = player
        lsAny = f
    end
    local ls = lsAny :: Folder

    local function ensureInt(name: string)
        local vAny = ls:FindFirstChild(name)
        if not vAny or not vAny:IsA("IntValue") then
            local v = Instance.new("IntValue")
            v.Name = name
            v.Value = 0
            v.Parent = ls
            return v
        end
        return vAny :: IntValue
    end

    local score = ensureInt("Score")
    local coins = ensureInt("Coins")
    return score, coins
end

Players.PlayerAdded:Connect(function(player)
    ensureLeaderstats(player)
end)

PlayerScored.OnServerEvent:Connect(function(player, amount: number)
    amount = tonumber(amount) or 0
    if amount <= 0 then
        return
    end
    local score, coins = ensureLeaderstats(player)
    score.Value += amount
    coins.Value += amount -- Einfach: Coins == Punkte; kann später getrennt werden
    print(string.format("[Server] %s +%d Punkte (Score=%d, Coins=%d)", player.Name, amount, score.Value, coins.Value))
    -- TODO: Remotes für HUD-Update senden
end)

PlayerDied.OnServerEvent:Connect(function(player)
    print(string.format("[Server] %s ist gestorben – Respawn", player.Name))
    player:LoadCharacter()
end)

-- Hilfsfunktion zum Erstellen von Blöcken
-- (Optional) Helper für spätere Level-Blöcke – aktuell nicht genutzt
-- local function _createBlock(position: Vector3, size: Vector3, color: Color3)
--     local part = Instance.new("Part")
--     part.Size = size
--     part.Anchored = true
--     part.Color = color
--     part.Material = Enum.Material.Grass
--     part.CFrame = CFrame.new(position)
--     part.TopSurface = Enum.SurfaceType.Smooth
--     part.BottomSurface = Enum.SurfaceType.Smooth
--     part.Parent = Workspace
--     return part
-- end

-- Lobby: große, flache Insel (einfacher Ankerpunkt für den Spielstart)
local function createLobbyIsland()
    -- Verhindere Duplikate beim erneuten Laden in Studio
    local existing = Workspace:FindFirstChild("LobbyIsland")
    if existing and existing:IsA("BasePart") then
        return existing
    end
    local island = Instance.new("Part")
    island.Name = "LobbyIsland"
    island.Size = Config.LOBBY.IslandSize
    island.Anchored = true
    island.Color = Config.LOBBY.Color
    island.Material = Enum.Material.Grass
    island.CFrame = CFrame.new(Vector3.new(0, Config.LOBBY.IslandY, 0))
    island.TopSurface = Enum.SurfaceType.Smooth
    island.BottomSurface = Enum.SurfaceType.Smooth
    island.Parent = Workspace
    return island
end

local _lobbyIsland = createLobbyIsland()

-- Stelle sicher, dass Arena-Container existiert
local function ensureArenasContainer(): Folder
    local existing = Workspace:FindFirstChild("Arenas")
    if not existing or not existing:IsA("Folder") then
        local arenasFolder = Instance.new("Folder")
        arenasFolder.Name = "Arenas"
        arenasFolder.Parent = Workspace
        return arenasFolder
    end
    return existing :: Folder
end

local _arenasContainer = ensureArenasContainer()

-- Level-Start Marker in der Ferne (für Teleport)
local function ensureMarker(name: string, position: Vector3, color: Color3)
    local existing = Workspace:FindFirstChild(name)
    if existing and existing:IsA("BasePart") then
        return existing :: BasePart
    end
    local p = Instance.new("Part")
    p.Name = name
    p.Size = Vector3.new(4, 4, 4)
    p.Anchored = true
    p.Color = color
    p.Material = Enum.Material.Neon
    p.CFrame = CFrame.new(position)
    p.CanCollide = false
    p.Parent = Workspace
    return p
end

local LevelStart = ensureMarker("LevelStart", Vector3.new(500, 6, Config.Z_LOCK), Color3.fromRGB(255, 200, 60))
local QueueMarker = ensureMarker("Queue", Vector3.new(260, 6, Config.Z_LOCK), Color3.fromRGB(60, 200, 255))
local ShopMarker = ensureMarker("Shop", Vector3.new(320, 6, Config.Z_LOCK), Color3.fromRGB(160, 255, 160))
local ArenaMarker = ensureMarker("Arena", Vector3.new(700, 6, Config.Z_LOCK), Color3.fromRGB(255, 100, 120))

-- Positioniere den Spawn auf die Bahn (leicht über Boden)
-- Optionales Framework-Bootstrap (Knit), falls via Wally vorhanden
local function tryStartKnitServer()
    local ok = pcall(function()
        local pkg = ReplicatedStorage:FindFirstChild("Packages")
        if not pkg then
            return
        end
        local knitAny = pkg:FindFirstChild("Knit")
        if not knitAny then
            return
        end
        local Knit = (require :: any)(knitAny)
        -- Knit erfordert üblicherweise Service-Definitionen vor Start; hier nur Start, wenn verfügbar
        task.spawn(function()
            pcall(function()
                (Knit.Start :: any)()
            end)
        end)
    end)
    if not ok then
        -- kein Knit installiert oder Fehler beim require → ignorieren
        return
    end
end
tryStartKnitServer()
-- Teleportiere Spieler beim Join (und bei Respawn) zur Lobby
local function teleportToLobby(player: Player)
    local character = player.Character or player.CharacterAdded:Wait()
    local hrpAny = character:FindFirstChild("HumanoidRootPart")
    if hrpAny and hrpAny:IsA("BasePart") then
        local hrp = hrpAny :: BasePart
        hrp.CFrame = CFrame.new(Config.LOBBY.Spawn)
    end
    setInArena(player, false)
end

local function _teleportToLevelStart(player: Player)
    local character = player.Character or player.CharacterAdded:Wait()
    local hrpAny = character:FindFirstChild("HumanoidRootPart")
    if hrpAny and hrpAny:IsA("BasePart") then
        local hrp = hrpAny :: BasePart
        local pos = LevelStart and (LevelStart :: BasePart).Position or Vector3.new(220, 6, Config.Z_LOCK)
        hrp.CFrame = CFrame.new(pos)
    end
end

local function teleportToQueue(player: Player)
    local character = player.Character or player.CharacterAdded:Wait()
    local hrpAny = character:FindFirstChild("HumanoidRootPart")
    if hrpAny and hrpAny:IsA("BasePart") then
        local hrp = hrpAny :: BasePart
        local pos = QueueMarker.Position
        hrp.CFrame = CFrame.new(pos)
    end
    setInArena(player, false)
end

local function _teleportToShop(player: Player)
    local character = player.Character or player.CharacterAdded:Wait()
    local hrpAny = character:FindFirstChild("HumanoidRootPart")
    if hrpAny and hrpAny:IsA("BasePart") then
        local hrp = hrpAny :: BasePart
        local pos = ShopMarker.Position
        hrp.CFrame = CFrame.new(pos)
    end
    setInArena(player, false)
end

local function teleportToArena(player: Player)
    local character = player.Character or player.CharacterAdded:Wait()
    local hrpAny = character:FindFirstChild("HumanoidRootPart")
    if hrpAny and hrpAny:IsA("BasePart") then
        local hrp = hrpAny :: BasePart
        local pos = ArenaMarker.Position
        hrp.CFrame = CFrame.new(pos)
    end
    setInArena(player, true)
end

-- Remote-Handler: Lobby/Level Teleports
local function countQueued(): number
    local n = 0
    for _, ok in pairs(queued) do
        if ok then
            n += 1
        end
    end
    return n
end

local function startQueueCycle()
    if queueActive then
        return
    end
    queueActive = true
    task.spawn(function()
        -- Wartefenster für weitere Spieler
        task.wait(QUEUE.QueueWait)
        -- Sammle aktuelle Queue-Spieler
        local bucket: { Player } = {}
        for p, ok in pairs(queued) do
            if ok and p.Parent ~= nil then
                table.insert(bucket, p)
            end
        end
        -- Mindestspieler prüfen
        if #bucket < QUEUE.MinPlayers then
            -- Abbrechen und Queue leeren
            queued = {}
            queueActive = false
            print("[Queue] Not enough players, resetting queue")
            return
        end
        -- Shop-Phase
        for _, p in ipairs(bucket) do
            _teleportToShop(p)
        end
        task.wait(QUEUE.ShopWindow)
        -- Arena-Phase
        for _, p in ipairs(bucket) do
            teleportToArena(p)
        end
        -- Nach Ablauf zurück zur Lobby
        task.delay(QUEUE.ArenaDuration, function()
            for _, p in ipairs(bucket) do
                if p.Parent ~= nil then
                    teleportToLobby(p)
                end
            end
        end)
        -- Queue zurücksetzen
        queued = {}
        queueActive = false
    end)
end

StartGame.OnServerEvent:Connect(function(player)
    -- Neuer Flow: Lobby -> Queue -> Shop -> Arena -> Lobby
    queued[player] = true
    teleportToQueue(player)
    print(string.format("[Queue] %s queued (%d waiting)", player.Name, countQueued()))
    startQueueCycle()
end)

TeleportToLobby.OnServerEvent:Connect(function(player)
    teleportToLobby(player)
end)

EnterQueue.OnServerEvent:Connect(function(player)
    -- Manuelles Einreihen in die Queue
    queued[player] = true
    teleportToQueue(player)
    print(string.format("[Queue] %s queued (%d waiting)", player.Name, countQueued()))
    startQueueCycle()
end)

EnterArena.OnServerEvent:Connect(function(player)
    -- Direkter Teleport zur Arena (vereinfacht bis ArenaManager als ModuleScript verfügbar ist)
    teleportToArena(player)
    print(string.format("[Arena] %s entered arena", player.Name))
end)

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        teleportToLobby(player)
    end)
    -- Falls Character bereits existiert (Play Solo in Studio)
    task.defer(function()
        if player.Character then
            teleportToLobby(player)
        end
    end)
    -- Initialer Arena-Status
    setInArena(player, false)
end)

Players.PlayerRemoving:Connect(function(player)
    queued[player] = nil
end)
