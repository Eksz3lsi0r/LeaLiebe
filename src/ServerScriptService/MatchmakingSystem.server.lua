--!strict
-- Matchmaking-System für Arena RPG

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local _ArenaConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ArenaConstants"))

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local QueueJoin = Remotes:WaitForChild("EnterQueue") :: RemoteEvent
local QueueLeave = Remotes:WaitForChild("LeaveQueue") :: RemoteEvent
local MatchFound = Remotes:WaitForChild("MatchFound") :: RemoteEvent
local QueueStatus = Remotes:WaitForChild("QueueStatus") :: RemoteEvent

-- Typen
export type QueuedPlayer = {
    Player: Player,
    Class: string,
    Level: number,
    QueueTime: number,
    Preferences: {
        Region: string?,
        GameMode: string?,
    },
}

export type Match = {
    Id: string,
    Players: { QueuedPlayer },
    Status: "Forming" | "Ready" | "InProgress" | "Completed",
    StartTime: number,
    ArenaId: string?,
}

-- Globaler State
local queue: { QueuedPlayer } = {}
local activeMatches: { [string]: Match } = {}
local nextMatchId = 1

-- Matchmaking-Parameter
local MATCHMAKING = {
    MinPlayersPerMatch = 1, -- Für Testing, normalerweise 2-4
    MaxPlayersPerMatch = 4,
    MaxQueueTime = 30.0, -- Sekunden
    MatchTimeout = 300.0, -- 5 Minuten Spielzeit

    -- Level-Balancing (Optional für später)
    MaxLevelDifference = 3,
}

-- Hilfsfunktionen
local function createMatchId(): string
    local id = string.format("Match_%04d", nextMatchId)
    nextMatchId += 1
    return id
end

local function addPlayerToQueue(player: Player, className: string, level: number?)
    -- Entferne Spieler falls bereits in Queue
    removePlayerFromQueue(player)

    local queuedPlayer: QueuedPlayer = {
        Player = player,
        Class = className,
        Level = level or 1,
        QueueTime = os.clock(),
        Preferences = {},
    }

    table.insert(queue, queuedPlayer)

    -- Status-Update senden
    QueueStatus:FireClient(player, {
        inQueue = true,
        position = #queue,
        estimatedWait = math.max(5, MATCHMAKING.MaxQueueTime - (os.clock() - queuedPlayer.QueueTime)),
    })

    print(string.format("[Matchmaking] %s joined queue as %s (Position: %d)", player.Name, className, #queue))
end

function removePlayerFromQueue(player: Player)
    for i = #queue, 1, -1 do
        if queue[i].Player == player then
            table.remove(queue, i)

            QueueStatus:FireClient(player, {
                inQueue = false,
                position = 0,
                estimatedWait = 0,
            })

            print(string.format("[Matchmaking] %s left queue", player.Name))
            break
        end
    end
end

local function findMatch(): { QueuedPlayer }?
    local _now = os.clock()
    local candidates: { QueuedPlayer } = {}

    -- Sammle Kandidaten (nur verbundene Spieler)
    for _, queuedPlayer: QueuedPlayer in ipairs(queue) do
        if queuedPlayer.Player.Parent then -- Spieler ist noch verbunden
            -- Optional: Level-Balancing prüfen
            -- if #candidates > 0 then
            --     local levelDiff = math.abs(queuedPlayer.Level - candidates[1].Level)
            --     if levelDiff > MATCHMAKING.MaxLevelDifference then
            --         continue
            --     end
            -- end
            table.insert(candidates :: { any }, queuedPlayer :: any)
        end
    end

    -- Nicht genug Spieler
    if #candidates < MATCHMAKING.MinPlayersPerMatch then
        return nil
    end

    -- Sortiere nach Wartezeit (längste zuerst)
    table.sort(candidates, function(a: QueuedPlayer, b: QueuedPlayer): boolean
        return a.QueueTime < b.QueueTime
    end)

    -- Erstelle Match mit den ersten Spielern
    local matchPlayers: { QueuedPlayer } = {}
    local maxPlayers = math.min(#candidates, MATCHMAKING.MaxPlayersPerMatch)

    for i = 1, maxPlayers do
        table.insert(matchPlayers, candidates[i])
    end

    return matchPlayers
end

local function createMatch(players: { QueuedPlayer }): Match
    local matchId = createMatchId()
    local match: Match = {
        Id = matchId,
        Players = players,
        Status = "Forming",
        StartTime = os.clock(),
        ArenaId = nil,
    }

    activeMatches[matchId] = match

    -- Entferne Spieler aus Queue
    for _, queuedPlayer in ipairs(players) do
        removePlayerFromQueue(queuedPlayer.Player)
    end

    -- Benachrichtige alle Spieler
    for _, queuedPlayer in ipairs(players) do
        MatchFound:FireClient(queuedPlayer.Player, {
            matchId = matchId,
            playerCount = #players,
            estimatedStartTime = 5.0, -- 5 Sekunden Vorbereitung
        })
    end

    print(string.format("[Matchmaking] Created match %s with %d players", matchId, #players))
    return match
end

local function startMatch(match: Match)
    -- TODO: ArenaManager als ModuleScript umstrukturieren
    -- Temporär: Direkte Arena-Erstellung
    match.ArenaId = string.format("Arena_%03d", math.random(100, 999))
    match.Status = "InProgress"

    -- Teleportiere alle Spieler zur Arena (vereinfacht)
    for _, queuedPlayer in ipairs(match.Players) do
        -- Setze Spielerklasse und Match-Info
        queuedPlayer.Player:SetAttribute("Class", queuedPlayer.Class)
        queuedPlayer.Player:SetAttribute("MatchId", match.Id)
        queuedPlayer.Player:SetAttribute("InArena", true)
        queuedPlayer.Player:SetAttribute("ArenaId", match.ArenaId)

        -- Teleportation zur Arena (vereinfacht)
        if queuedPlayer.Player.Character then
            local hrp = queuedPlayer.Player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
            if hrp then
                hrp.CFrame = CFrame.new(700, 10, 0) -- Arena-Position
            end
        end
    end

    print(string.format("[Matchmaking] Started match %s in arena %s", match.Id, match.ArenaId or "unknown"))
end

-- Event-Handler
QueueJoin.OnServerEvent:Connect(function(player: Player, className: string, level: number?)
    if not className or className == "" then
        className = "MeleeDPS" -- Default-Klasse
    end

    addPlayerToQueue(player, className, level)
end)

QueueLeave.OnServerEvent:Connect(function(player: Player)
    removePlayerFromQueue(player)
end)

-- Matchmaking-Loop
local lastMatchmakingCheck = 0
RunService.Heartbeat:Connect(function()
    local now = os.clock()

    -- Matchmaking alle 2 Sekunden prüfen
    if now - lastMatchmakingCheck >= 2.0 then
        lastMatchmakingCheck = now

        -- Versuche Match zu erstellen
        local matchPlayers = findMatch()
        if matchPlayers then
            local match = createMatch(matchPlayers)

            -- Starte Match nach kurzer Verzögerung
            task.wait(5.0) -- 5 Sekunden Vorbereitung
            startMatch(match)
        end

        -- Update Queue-Positionen
        for i, queuedPlayer in ipairs(queue) do
            if queuedPlayer.Player.Parent then
                QueueStatus:FireClient(queuedPlayer.Player, {
                    inQueue = true,
                    position = i,
                    estimatedWait = math.max(5, MATCHMAKING.MaxQueueTime - (now - queuedPlayer.QueueTime)),
                })
            end
        end
    end

    -- Cleanup abgeschlossene Matches
    for matchId, match in pairs(activeMatches) do
        if match.Status == "Completed" or (now - match.StartTime) > MATCHMAKING.MatchTimeout then
            activeMatches[matchId] = nil
            print(string.format("[Matchmaking] Cleaned up match %s", matchId))
        end
    end
end)

-- Player Lifecycle
Players.PlayerRemoving:Connect(function(player)
    removePlayerFromQueue(player)

    -- Entferne aus aktiven Matches
    for _matchId, match in pairs(activeMatches) do
        for i = #match.Players, 1, -1 do
            if match.Players[i].Player == player then
                table.remove(match.Players, i)
                break
            end
        end

        -- Match beenden wenn zu wenige Spieler
        if #match.Players == 0 then
            match.Status = "Completed"
        end
    end
end)

-- Öffentliche API
local MatchmakingSystem = {
    addPlayerToQueue = addPlayerToQueue,
    removePlayerFromQueue = removePlayerFromQueue,
    getQueueStatus = function(player: Player)
        for i, queuedPlayer in ipairs(queue) do
            if queuedPlayer.Player == player then
                return {
                    inQueue = true,
                    position = i,
                    estimatedWait = math.max(5, MATCHMAKING.MaxQueueTime - (os.clock() - queuedPlayer.QueueTime)),
                }
            end
        end
        return { inQueue = false, position = 0, estimatedWait = 0 }
    end,
    getActiveMatches = function()
        return activeMatches
    end,
}

return MatchmakingSystem
