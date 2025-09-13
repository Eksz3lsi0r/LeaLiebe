--!strict
-- Win/Loss-Validation und Match-Management

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local _Players = game:GetService("Players")

local _ArenaConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ArenaConstants"))

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local _ArenaComplete = Remotes:WaitForChild("ArenaComplete") :: RemoteEvent
local MatchResult: RemoteEvent = Remotes:FindFirstChild("MatchResult") :: RemoteEvent? or Instance.new("RemoteEvent")
if not Remotes:FindFirstChild("MatchResult") then
    MatchResult.Name = "MatchResult"
    MatchResult.Parent = Remotes
end
local TeleportToLobby = Remotes:WaitForChild("TeleportToLobby") :: RemoteEvent

-- Typen
export type MatchState = {
    MatchId: string,
    ArenaId: string,
    Players: { Player },
    StartTime: number,
    Duration: number,
    WaveNumber: number,
    EnemiesKilled: number,
    TotalEnemies: number,
    Status: "InProgress" | "Victory" | "Defeat" | "Timeout",
    EndTime: number?,
}

-- Globaler State
local activeMatches: { [string]: MatchState } = {}

-- Match-Parameter
local MATCH_CONFIG = {
    MaxDuration = 300, -- 5 Minuten
    VictoryConditions = {
        SurviveAllWaves = true,
        KillAllEnemies = true,
        DefendObjective = false, -- Für später
    },
    DefeatConditions = {
        AllPlayersDead = true,
        TimeExpired = false, -- Optional
        ObjectiveDestroyed = false, -- Für später
    },
    WavesToWin = 3, -- Anzahl Wellen bis Sieg
    ReturnToLobbyDelay = 10.0, -- Sekunden nach Match-Ende
}

-- Match-Creation
local function createMatch(matchId: string, arenaId: string, players: { Player }): MatchState
    local match: MatchState = {
        MatchId = matchId,
        ArenaId = arenaId,
        Players = players,
        StartTime = os.clock(),
        Duration = 0,
        WaveNumber = 1,
        EnemiesKilled = 0,
        TotalEnemies = 0,
        Status = "InProgress",
        EndTime = nil,
    }

    activeMatches[matchId] = match

    print(string.format("[MatchValidation] Started match %s with %d players", matchId, #players))
    return match
end

-- Victory/Defeat Checking
local function checkVictoryConditions(match: MatchState): boolean
    -- Alle Wellen besiegt
    if MATCH_CONFIG.VictoryConditions.SurviveAllWaves and match.WaveNumber > MATCH_CONFIG.WavesToWin then
        return true
    end

    -- Alle Gegner getötet (current wave)
    if
        MATCH_CONFIG.VictoryConditions.KillAllEnemies
        and match.EnemiesKilled >= match.TotalEnemies
        and match.TotalEnemies > 0
    then
        return true
    end

    return false
end

local function checkDefeatConditions(match: MatchState): boolean
    -- Alle Spieler tot
    if MATCH_CONFIG.DefeatConditions.AllPlayersDead then
        local alivePlayers = 0
        for _, player in ipairs(match.Players) do
            if player.Parent then -- Spieler noch verbunden
                local character = player.Character
                local humanoid = character and character:FindFirstChild("Humanoid") :: Humanoid?
                if humanoid and humanoid.Health > 0 then
                    alivePlayers += 1
                end
            end
        end

        if alivePlayers == 0 then
            return true
        end
    end

    -- Zeit abgelaufen
    if MATCH_CONFIG.DefeatConditions.TimeExpired and match.Duration >= MATCH_CONFIG.MaxDuration then
        return true
    end

    return false
end

local function endMatch(match: MatchState, result: "Victory" | "Defeat" | "Timeout")
    match.Status = result
    match.EndTime = os.clock()

    local rewards = _calculateRewards(match, result)

    -- Benachrichtige alle Spieler
    for _, player in ipairs(match.Players) do
        if player.Parent then
            MatchResult:FireClient(player, {
                result = result,
                matchId = match.MatchId,
                duration = match.Duration,
                wavesCompleted = match.WaveNumber - 1,
                enemiesKilled = match.EnemiesKilled,
                rewards = rewards[player] or {},
            })
        end
    end

    -- Schedule teleport back to lobby
    task.wait(MATCH_CONFIG.ReturnToLobbyDelay)
    _teleportPlayersToLobby(match.Players)

    print(string.format("[MatchValidation] Match %s ended with result: %s", match.MatchId, result))
end

function _calculateRewards(match: MatchState, result: "Victory" | "Defeat" | "Timeout"): { [Player]: any }
    local rewards: { [Player]: any } = {}

    for _, player in ipairs(match.Players) do
        local baseGold = 50
        local baseExp = 100

        -- Victory-Bonus
        if result == "Victory" then
            baseGold *= 1.5
            baseExp *= 1.5
        end

        -- Wave-Bonus
        baseGold += (match.WaveNumber - 1) * 25
        baseExp += (match.WaveNumber - 1) * 50

        -- Kill-Bonus
        baseGold += match.EnemiesKilled * 5
        baseExp += match.EnemiesKilled * 10

        rewards[player] = {
            gold = math.floor(baseGold),
            experience = math.floor(baseExp),
            items = {}, -- Für später: Loot-System
        }
    end

    return rewards
end

function _teleportPlayersToLobby(players: { Player })
    for _, player in ipairs(players) do
        if player.Parent then
            -- Entferne Arena-Attribute
            player:SetAttribute("InArena", false)
            player:SetAttribute("ArenaId", nil)
            player:SetAttribute("MatchId", nil)

            -- Teleportiere zur Lobby
            TeleportToLobby:FireServer()
        end
    end
end

-- Match Monitoring Loop
RunService.Heartbeat:Connect(function()
    local now = os.clock()

    for matchId, match in pairs(activeMatches) do
        if match.Status == "InProgress" then
            match.Duration = now - match.StartTime

            -- Prüfe Sieg-/Niederlagen-Bedingungen
            if checkVictoryConditions(match) then
                endMatch(match, "Victory")
            elseif checkDefeatConditions(match) then
                endMatch(match, "Defeat")
            elseif match.Duration >= MATCH_CONFIG.MaxDuration then
                endMatch(match, "Timeout")
            end
        elseif match.EndTime and (now - match.EndTime) > MATCH_CONFIG.ReturnToLobbyDelay + 30 then
            -- Cleanup nach 30 Sekunden Extra-Zeit
            activeMatches[matchId] = nil
        end
    end
end)

-- External Events (für Integration mit anderen Systemen)
local function onEnemyKilled(arenaId: string)
    for _, match in pairs(activeMatches) do
        if match.ArenaId == arenaId and match.Status == "InProgress" then
            match.EnemiesKilled += 1
            break
        end
    end
end

local function onWaveCompleted(arenaId: string, waveNumber: number, totalEnemies: number)
    for _, match in pairs(activeMatches) do
        if match.ArenaId == arenaId and match.Status == "InProgress" then
            match.WaveNumber = waveNumber + 1
            match.TotalEnemies = totalEnemies
            match.EnemiesKilled = 0 -- Reset für neue Welle
            break
        end
    end
end

-- Public API
local MatchValidation = {
    createMatch = createMatch,
    endMatch = endMatch,
    onEnemyKilled = onEnemyKilled,
    onWaveCompleted = onWaveCompleted,
    getMatch = function(matchId: string)
        return activeMatches[matchId]
    end,
    getActiveMatches = function()
        return activeMatches
    end,
}

return MatchValidation
