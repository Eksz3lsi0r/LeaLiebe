--!strict
-- Deterministic helpers for spawn/utility logic to enable unit testing

export type SpawnChances = {
    OverhangChance: number,
    ObstacleChance: number,
    CoinChance: number,
    PowerupChance: number?,
}

-- Returns 1-based biome index for a given segmentIndex
local function getBiomeIndex(segmentIndex: number, segmentsPerBiome: number, biomesCount: number): number
    if biomesCount <= 0 then
        return 1
    end
    local per = math.max(1, math.floor(segmentsPerBiome))
    local idx = ((math.max(1, math.floor(segmentIndex)) - 1) // per) % biomesCount
    return idx + 1
end

-- Given a random roll in [0,1), decide content kind for a lane
-- Returns "Overhang"|"Obstacle"|"Coin"|"Powerup"|nil
local function pickLaneContent(roll: number, cfg: SpawnChances): string?
    local r = roll
    if r < 0 then
        r = 0
    elseif r > 1 then
        r = 1
    end
    local pOver = math.max(0, cfg.OverhangChance)
    local pObs = math.max(0, cfg.ObstacleChance)
    local pCoin = math.max(0, cfg.CoinChance)
    local pPow = math.max(0, cfg.PowerupChance or 0)
    -- Evaluate sequentially like in server code
    if r < pOver then
        return "Overhang"
    end
    if r < pOver + pObs then
        return "Obstacle"
    end
    if r < pOver + pObs + pCoin then
        return "Coin"
    end
    if r < pOver + pObs + pCoin + pPow then
        return "Powerup"
    end
    return nil
end

-- Weighted pick between Magnet and Shield; returns "Magnet" or "Shield"
local function pickPowerupKind(rand01: number, weightMagnet: number, weightShield: number): string
    local wm = math.max(0, weightMagnet)
    local ws = math.max(0, weightShield)
    local total = wm + ws
    if total <= 0 then
        -- Default to Magnet if weights are degenerate
        return "Magnet"
    end
    local cut = wm / total
    local r = math.clamp(rand01, 0, 1)
    if r <= cut then
        return "Magnet"
    else
        return "Shield"
    end
end

return {
    getBiomeIndex = getBiomeIndex,
    pickLaneContent = pickLaneContent,
    pickPowerupKind = pickPowerupKind,
}
