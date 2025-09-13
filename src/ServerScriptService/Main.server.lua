--!strict
-- Server-side game loop & procedural generation

local DataStoreService = game:GetService("DataStoreService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Konfiguration (Shared): hält Gameplay-Parameter; keine direkten Mutationen aus dem Servercode
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants")) :: {
    PLAYER: {
        BaseSpeed: number,
        Acceleration: number,
        MaxSpeed: number,
        LaneSwitchSpeed: number,
        RollDuration: number,
        RollBoost: number,
    },
    SPAWN: {
        ViewDistance: number,
        SegmentLength: number,
        OverhangChance: number,
        ObstacleChance: number,
        CoinChance: number,
        CleanupBehind: number,
        PowerupChance: number,
        DecoChance: number?,
    },
    LANES: { number },
    COLLISION: { CoinValue: number },
    POWERUPS: any,
    EVENTS: any?,
    BIOMES: {
        SegmentsPerBiome: number,
        TransitionDuration: number,
        List: {
            {
                name: string,
                groundColor: { number },
                ambient: { number },
                outdoorAmbient: { number },
                fogColor: { number },
                fogEnd: number,
                clockTime: number,
            }
        },
    },
    DEBUG_LOGS: boolean?,
    SCORE: { StreakStep: number?, MultiplierPerStep: number?, MaxMultiplier: number? }?,
}

-- Testbare Hilfsfunktionen
local SpawnUtils = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SpawnUtils"))

-- HUD-Payload-Shape: getaktete Updates an den Client (siehe HUD-Throttle ~0,15 s)
type HUDPayload = {
    distance: number,
    coins: number,
    speed: number,
    magnet: number?,
    shield: number?,
    shieldTime: number?,
    doubleCoins: number?,
    multiplier: number?,
}

-- Vorwärtsdeklaration, damit Funktionen, die spawnSegment aufrufen, die lokale Variable erfassen
local spawnSegment: (player: Player, segmentIndex: number, baseZ: number) -> ()

-- Remotes
local RemotesFolderAny = ReplicatedStorage:FindFirstChild("Remotes")
local RemotesFolder: Folder
if not RemotesFolderAny or not RemotesFolderAny:IsA("Folder") then
    local f = Instance.new("Folder")
    f.Name = "Remotes"
    f.Parent = ReplicatedStorage
    RemotesFolder = f
else
    RemotesFolder = RemotesFolderAny
end

local LaneRequest = Instance.new("RemoteEvent")
LaneRequest.Name = "LaneRequest"
LaneRequest.Parent = RemotesFolder

local UpdateHUD = Instance.new("RemoteEvent")
UpdateHUD.Name = "UpdateHUD"
UpdateHUD.Parent = RemotesFolder

local CoinPickup = Instance.new("RemoteEvent")
CoinPickup.Name = "CoinPickup"
CoinPickup.Parent = RemotesFolder

local ActionRequest = Instance.new("RemoteEvent")
ActionRequest.Name = "ActionRequest"
ActionRequest.Parent = RemotesFolder

-- Server->Client Synchronisation für gestartete Aktionen (Jump/Roll)
local ActionSync = Instance.new("RemoteEvent")
ActionSync.Name = "ActionSync"
ActionSync.Parent = RemotesFolder

-- Neues RemoteEvent für Game Over
local GameOver = Instance.new("RemoteEvent")
GameOver.Name = "GameOver"
GameOver.Parent = RemotesFolder

-- Neues RemoteEvent für Neustart
local RestartRequest = Instance.new("RemoteEvent")
RestartRequest.Name = "RestartRequest"
RestartRequest.Parent = RemotesFolder

-- Powerup Feedback
local PowerupPickup = Instance.new("RemoteEvent")
PowerupPickup.Name = "PowerupPickup"
PowerupPickup.Parent = RemotesFolder

-- Event-Announcements (z. B. Double Coins Start)
local EventAnnounce = Instance.new("RemoteEvent")
EventAnnounce.Name = "EventAnnounce"
EventAnnounce.Parent = RemotesFolder

-- Shop Remotes
local ShopPurchaseRequest = Instance.new("RemoteEvent")
ShopPurchaseRequest.Name = "ShopPurchaseRequest"
ShopPurchaseRequest.Parent = RemotesFolder

local ShopResult = Instance.new("RemoteEvent")
ShopResult.Name = "ShopResult"
ShopResult.Parent = RemotesFolder

-- Per-player state (Typ erweitern)
export type PlayerState = {
    Runner: Model?,
    Humanoid: Humanoid?,
    HRP: BasePart?,
    LaneIndex: number,
    Speed: number,
    Distance: number,
    Coins: number,
    NextSegment: number,
    Folder: Folder?,
    GameOver: boolean?, -- Neu: Spiel beendet Flag
    _HudAccum: number?, -- Throttle-Akkumulator für HUD-Updates
    VerticalY: number?, -- Y-Position
    VerticalVel: number?, -- vertikale Geschwindigkeit
    OnGround: boolean?, -- steht auf dem Boden?
    RollingUntil: number?, -- Roll-Endezeit
    WasOnGround: boolean?, -- vorheriger Bodenkontakt
    -- Powerups
    MagnetUntil: number?,
    ShieldHits: number?,
    ShieldUntil: number?,
    -- Dynamic Events
    DoubleCoinsUntil: number?,
    -- Input-Gating
    QueueRollOnLand: boolean?, -- wenn Roll in der Luft gedrückt wurde, auf Landung vormerken
    -- Biome/Theme pro Spieler
    BiomeIndex: number?,
    BiomeActiveSince: number?,
    -- Reusable query params to avoid per-frame allocations
    OverlapParams: OverlapParams?,
    OverlapFilter: { Instance }?,
    -- Scoring
    CoinStreak: number?,
    Multiplier: number?,
    -- Bewegliche Hindernisse im eigenen Track (leichtgewichtige Liste)
    Movers: { { part: BasePart, baseX: number, amp: number, freq: number, phase: number } }?,
}

local state: { [Player]: PlayerState } = {}

-- Persistence (optional): Coins + Best Distance
type SaveBlob = { coins: number, best: number }
local store = nil :: GlobalDataStore?
local saveCache: { [number]: SaveBlob } = {}

-- Save throttling to avoid filling the DataStore request queue
type SaveMeta = { lastSave: number, inFlight: boolean, pending: boolean, scheduleToken: number? }
local saveMeta: { [number]: SaveMeta } = {}
local MIN_SAVE_INTERVAL = 20.0 -- seconds between non-urgent saves per user

local function getSaveMeta(uid: number): SaveMeta
    local meta = saveMeta[uid]
    if not meta then
        meta = { lastSave = 0, inFlight = false, pending = false, scheduleToken = nil } :: SaveMeta
        saveMeta[uid] = meta
    end
    return meta
end

local function ensureStore(): GlobalDataStore?
    if store ~= nil then
        return store
    end
    local ok, ds = pcall(function()
        return DataStoreService:GetDataStore("EndlessRunner_v1")
    end)
    if ok then
        store = ds :: GlobalDataStore
        return store
    else
        warn("[Server] DataStore unavailable (Studio API disabled or error)")
        store = nil
        return nil
    end
end

local function loadPlayerData(player: Player): SaveBlob
    local key = string.format("u_%d", player.UserId)
    local blob: SaveBlob = { coins = 0, best = 0 }
    local ds = ensureStore()
    if not ds then
        saveCache[player.UserId] = blob
        return blob
    end
    local ok, data = pcall(function()
        return ds:GetAsync(key)
    end)
    if ok and typeof(data) == "table" then
        local coins = tonumber((data :: any).coins) or 0
        local best = tonumber((data :: any).best) or 0
        blob = { coins = math.max(0, coins), best = math.max(0, best) }
    end
    saveCache[player.UserId] = blob
    return blob
end

local function savePlayerData(player: Player, reason: string?)
    local s = state[player]
    local uid = player.UserId
    local cached: SaveBlob = (saveCache[uid] :: SaveBlob?) or ({ coins = 0, best = 0 } :: SaveBlob)
    local currentBest = cached.best or 0
    local dist = 0
    if s then
        dist = math.floor(s.Distance)
        cached.coins = math.max(0, s.Coins)
        if dist > currentBest then
            currentBest = dist
        end
    end
    cached.best = currentBest
    saveCache[uid] = cached

    local ds = ensureStore()
    if not ds then
        return
    end
    local key = string.format("u_%d", uid)
    local ok = pcall(function()
        ds:SetAsync(key, { coins = cached.coins, best = cached.best })
    end)
    if not ok then
        warn("[Server] Save failed for", player.Name, reason or "")
    end
end

-- Schedule/Throttle wrapper around savePlayerData
local function requestSave(player: Player, reason: string?, urgent: boolean?)
    local uid = player.UserId
    local meta = getSaveMeta(uid)
    if urgent then
        -- Bypass throttle for critical saves
        if meta.inFlight then
            meta.pending = true
            return
        end
        meta.inFlight = true
        savePlayerData(player, reason or "Urgent")
        meta.inFlight = false
        meta.lastSave = os.clock()
        if meta.pending then
            meta.pending = false
            -- Run one more non-urgent save shortly after if something queued during flight
            task.delay(0.25, function()
                requestSave(player, "PostUrgent", false)
            end)
        end
        return
    end

    -- Non-urgent: respect per-user interval and coalesce
    if meta.inFlight then
        meta.pending = true
        return
    end
    local now = os.clock()
    local delta = now - meta.lastSave
    if delta >= MIN_SAVE_INTERVAL then
        meta.inFlight = true
        savePlayerData(player, reason or "ThrottledImmediate")
        meta.inFlight = false
        meta.lastSave = os.clock()
        if meta.pending then
            meta.pending = false
            -- schedule one follow-up after the minimum interval window
            local token = (meta.scheduleToken or 0) + 1
            meta.scheduleToken = token
            task.delay(MIN_SAVE_INTERVAL + 0.25, function()
                if meta.scheduleToken ~= token then
                    return
                end
                meta.scheduleToken = nil
                requestSave(player, "FollowUp", false)
            end)
        end
    else
        -- Too soon: schedule a single save once interval has elapsed
        local token = (meta.scheduleToken or 0) + 1
        meta.scheduleToken = token
        local waitFor = (MIN_SAVE_INTERVAL - delta) + 0.25
        task.delay(waitFor, function()
            if meta.scheduleToken ~= token then
                return
            end
            meta.scheduleToken = nil
            requestSave(player, reason or "Scheduled", false)
        end)
    end
end

local function applyLoadedData(player: Player)
    local blob = saveCache[player.UserId]
    if not blob then
        return
    end
    local s = state[player]
    if not s then
        return
    end
    s.Coins = math.max(0, blob.coins)
    UpdateHUD:FireClient(player, {
        distance = math.floor(s.Distance),
        coins = s.Coins,
        speed = math.floor(s.Speed),
    })
end

-- Animation helpers
local function getAnimator(hum: Humanoid): Animator?
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then
        local ok = pcall(function()
            local a = Instance.new("Animator")
            a.Parent = hum
            animator = a
        end)
        if not ok or not animator then
            warn("[Server] Failed to create Animator")
            return nil
        end
    end
    return animator :: Animator
end

local function stopJumpTracks(hum: Humanoid)
    local animator = getAnimator(hum)
    if not animator then
        return
    end
    local ok, tracks = pcall(function()
        return animator:GetPlayingAnimationTracks()
    end)
    if not ok or not tracks then
        return
    end
    for _, tr in ipairs(tracks :: { AnimationTrack }) do
        local n = (tr.Name or ""):lower()
        local an = ""
        local a = tr.Animation
        if a then
            an = (a.Name or ""):lower()
        end
        if string.find(n, "jump") or string.find(an, "jump") then
            pcall(function()
                tr:Stop(0.1)
            end)
        end
    end
end

-- Erzeugt pro Spieler den Runner und initiale Segmente.
-- Wichtig: Server behält Network Ownership (autoritative Bewegung); HRP wird auf 180° gedreht (Blick +Z).
local function createRunnerFor(player: Player)
    local character = player.Character or player.CharacterAdded:Wait()
    local hrp = character:WaitForChild("HumanoidRootPart") :: BasePart
    local humanoid = character:WaitForChild("Humanoid") :: Humanoid

    -- Ensure network ownership stays server-side for authoritative movement
    hrp:SetNetworkOwner(nil)

    local folderAny = workspace:FindFirstChild("Tracks")
    local folder: Folder
    if not folderAny or not folderAny:IsA("Folder") then
        local f = Instance.new("Folder")
        f.Name = "Tracks"
        f.Parent = workspace
        folder = f
    else
        folder = folderAny
    end

    local playerFolder = Instance.new("Folder")
    playerFolder.Name = tostring(player.UserId)
    playerFolder.Parent = folder

    -- Initialize state
    state[player] = {
        Runner = character,
        Humanoid = humanoid,
        HRP = hrp,
        LaneIndex = 2, -- center lane
        Speed = Constants.PLAYER.BaseSpeed,
        Distance = 0,
        Coins = 0,
        NextSegment = 1,
        Folder = playerFolder,
        _HudAccum = 0,
        VerticalY = 3,
        VerticalVel = 0,
        OnGround = true,
        RollingUntil = 0,
        WasOnGround = true,
        QueueRollOnLand = false,
        BiomeIndex = 1,
        BiomeActiveSince = os.clock(),
        DoubleCoinsUntil = 0,
        ShieldUntil = 0,
        OverlapParams = nil,
        OverlapFilter = nil,
        CoinStreak = 0,
        Multiplier = 1.0,
        Movers = {},
    }

    -- Place runner at start position (180° gedreht, Rücken zur Kamera)
    local startX = Constants.LANES[state[player].LaneIndex]
    hrp.CFrame = CFrame.new(startX, 3, 0) * CFrame.Angles(0, math.pi, 0)

    -- Prepare initial segments
    for i = 1, Constants.SPAWN.ViewDistance do
        local segZ = (i - 1) * Constants.SPAWN.SegmentLength
        spawnSegment(player, i, segZ)
    end

    -- Initiales HUD-Update, damit der Client sofort Werte sieht
    local initialPayload: HUDPayload = {
        distance = 0,
        coins = 0,
        speed = math.floor(Constants.PLAYER.BaseSpeed),
    }
    if Constants.DEBUG_LOGS then
        print(
            "[Server] Initial UpdateHUD ->",
            player.Name,
            initialPayload.distance,
            initialPayload.coins,
            initialPayload.speed
        )
    end
    UpdateHUD:FireClient(player, initialPayload)
end

-- Helper: sichere Score-Config mit Defaults
local function getScoreCfg()
    local scAny = Constants.SCORE :: any
    local step = 10
    local mulPer = 0.1
    local maxMul = 3.0
    if typeof(scAny) == "table" then
        step = tonumber(scAny.StreakStep) or step
        mulPer = tonumber(scAny.MultiplierPerStep) or mulPer
        maxMul = tonumber(scAny.MaxMultiplier) or maxMul
    end
    return { StreakStep = step, MultiplierPerStep = mulPer, MaxMultiplier = maxMul }
end

local function cleanupPlayer(player: Player)
    local s = state[player]
    if s and s.Folder then
        s.Folder:Destroy()
    end
    state[player] = nil
end

-- Object Pools
local function createObstacle(): BasePart
    local p = Instance.new("Part")
    p.Size = Vector3.new(4, 6, 4)
    p.Anchored = true
    p.Color = Color3.fromRGB(255, 81, 81)
    p.Name = "Obstacle"
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.CanCollide = false
    return p :: BasePart
end

local function createObstacleTall(): BasePart
    local p = Instance.new("Part")
    p.Size = Vector3.new(4, 9, 4)
    p.Anchored = true
    p.Color = Color3.fromRGB(220, 60, 60)
    p.Name = "Obstacle"
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.CanCollide = false
    return p :: BasePart
end

local function createObstacleLow(): BasePart
    local p = Instance.new("Part")
    p.Size = Vector3.new(4, 3, 4)
    p.Anchored = true
    p.Color = Color3.fromRGB(255, 100, 100)
    p.Name = "Obstacle"
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.CanCollide = false
    return p :: BasePart
end

local function createObstacleWide(): BasePart
    local p = Instance.new("Part")
    p.Size = Vector3.new(5.5, 5, 5.5) -- etwas breiter/tiefer innerhalb der Lane
    p.Anchored = true
    p.Color = Color3.fromRGB(200, 60, 60)
    p.Name = "Obstacle"
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.CanCollide = false
    return p :: BasePart
end

local function createOverhang(): BasePart
    -- Hängelnde Barriere, die nur im Duck/ Roll unterquert werden kann
    local p = Instance.new("Part")
    p.Size = Vector3.new(4, 2.2, 4)
    p.Anchored = true
    p.Color = Color3.fromRGB(255, 140, 0)
    p.Name = "Overhang"
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.CanCollide = false
    return p :: BasePart
end

local function createCoin(): BasePart
    local coin = Instance.new("Part")
    coin.Shape = Enum.PartType.Ball
    coin.Size = Vector3.new(2, 2, 2)
    coin.Material = Enum.Material.Neon
    coin.Color = Color3.fromRGB(255, 221, 84)
    coin.Name = "Coin"
    coin.Anchored = true
    -- Coins should not block the player; we detect them via OverlapParams
    coin.CanCollide = false
    coin.CanQuery = true
    coin.CanTouch = false
    return coin :: BasePart
end

local function createPowerup(kind: string): BasePart
    local p = Instance.new("Part")
    p.Shape = Enum.PartType.Ball
    p.Size = Vector3.new(2.5, 2.5, 2.5)
    p.Material = Enum.Material.Neon
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = true
    p.CanTouch = false
    p.Name = "Powerup"
    p:SetAttribute("Kind", kind)
    if kind == "Magnet" then
        p.Color = Color3.fromRGB(80, 180, 255)
    else
        p.Color = Color3.fromRGB(120, 255, 120)
    end
    return p :: BasePart
end

-- Sehr einfache Deko-Bausteine (rein visuell, keine Kollision/Abfrage)
local function createDeco(kind: string): BasePart
    local p = Instance.new("Part")
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false
    p.CanTouch = false
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.Name = "Deco"
    if kind == "Post" then
        p.Size = Vector3.new(1, 8, 1)
        p.Color = Color3.fromRGB(90, 90, 90)
        p.Material = Enum.Material.Metal
    elseif kind == "Crate" then
        p.Size = Vector3.new(3, 3, 3)
        p.Color = Color3.fromRGB(120, 90, 60)
        p.Material = Enum.Material.Wood
    else -- Fence segment
        p.Size = Vector3.new(6, 2, 0.5)
        p.Color = Color3.fromRGB(80, 80, 80)
        p.Material = Enum.Material.Metal
    end
    return p :: BasePart
end

-- Bewegliches Hindernis (seitliche Oszillation innerhalb einer Lane)
local function createMovingObstacle(baseX: number, y: number, z: number): BasePart
    local p = Instance.new("Part")
    p.Size = Vector3.new(4, 5, 4)
    p.Anchored = true
    p.Color = Color3.fromRGB(210, 70, 70)
    p.Name = "Obstacle"
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.CanCollide = false
    p.Position = Vector3.new(baseX, y, z)
    return p :: BasePart
end

-- Biome Utils
local function toColor3(rgb: { number }): Color3
    return Color3.fromRGB(
        math.clamp(rgb[1] or 255, 0, 255),
        math.clamp(rgb[2] or 255, 0, 255),
        math.clamp(rgb[3] or 255, 0, 255)
    )
end

local function applyLightingTheme(target: {
    name: string,
    groundColor: { number },
    ambient: { number },
    outdoorAmbient: { number },
    fogColor: { number },
    fogEnd: number,
    clockTime: number,
})
    Lighting.Ambient = toColor3(target.ambient)
    Lighting.OutdoorAmbient = toColor3(target.outdoorAmbient)
    Lighting.FogColor = toColor3(target.fogColor)
    Lighting.FogEnd = target.fogEnd
    Lighting.ClockTime = target.clockTime
end

local function blendLighting(fromTheme: any, toTheme: any, duration: number)
    local start = os.clock()
    local fromAmb = toColor3(fromTheme.ambient)
    local toAmb = toColor3(toTheme.ambient)
    local fromOut = toColor3(fromTheme.outdoorAmbient)
    local toOut = toColor3(toTheme.outdoorAmbient)
    local fromFog = toColor3(fromTheme.fogColor)
    local toFog = toColor3(toTheme.fogColor)
    local fromEnd: number = fromTheme.fogEnd
    local toEnd: number = toTheme.fogEnd
    local fromClock: number = fromTheme.clockTime
    local toClock: number = toTheme.clockTime
    while os.clock() - start < duration do
        local t = (os.clock() - start) / duration
        Lighting.Ambient = fromAmb:Lerp(toAmb, t)
        Lighting.OutdoorAmbient = fromOut:Lerp(toOut, t)
        Lighting.FogColor = fromFog:Lerp(toFog, t)
        Lighting.FogEnd = fromEnd + (toEnd - fromEnd) * t
        Lighting.ClockTime = fromClock + (toClock - fromClock) * t
        task.wait(0.05)
    end
    applyLightingTheme(toTheme)
end

-- Track segment creation
spawnSegment = function(player: Player, segmentIndex: number, baseZ: number)
    local s = state[player]
    if not s or not s.Folder then
        return
    end

    local segmentFolder = Instance.new("Folder")
    segmentFolder.Name = string.format("Seg_%04d", segmentIndex)
    segmentFolder.Parent = s.Folder

    -- Biome bestimmen (per Spieler, rotiert über SegmentsPerBiome)
    local biomes = (Constants.BIOMES and Constants.BIOMES.List) or {}
    local biomeIdx = SpawnUtils.getBiomeIndex(segmentIndex, Constants.BIOMES.SegmentsPerBiome, #biomes)
    local biome = biomes[biomeIdx]

    -- Lane ground lanes (visual) mit biomebezogener Farbe
    for _, laneX in ipairs(Constants.LANES) do
        local ground = Instance.new("Part")
        ground.Size = Vector3.new(6, 1, Constants.SPAWN.SegmentLength)
        ground.Anchored = true
        ground.Material = Enum.Material.SmoothPlastic
        if biome and typeof(biome) == "table" and biome.groundColor then
            ground.Color = toColor3(biome.groundColor)
        else
            ground.Color = Color3.fromRGB(59, 59, 59)
        end
        ground.Position = Vector3.new(laneX, 0, baseZ + Constants.SPAWN.SegmentLength / 2)
        ground.Name = "Ground"
        ground.Parent = segmentFolder
    end

    -- Pattern-Auswahl (max. ein Pattern pro Segment)
    local function pickPattern(): string?
        local patterns = (Constants.SPAWN and (Constants.SPAWN :: any).Patterns) or nil
        if not patterns then
            return nil
        end
        local entries = {
            { name = "CoinLine", p = tonumber(patterns.CoinLine) or 0 },
            { name = "CoinZigZag", p = tonumber(patterns.CoinZigZag) or 0 },
            { name = "LaneBlocker", p = tonumber(patterns.LaneBlocker) or 0 },
            { name = "Mover", p = tonumber(patterns.Mover) or 0 },
        }
        local sum = 0
        for _, e in ipairs(entries) do
            sum += math.max(0, e.p)
        end
        if sum <= 0 then
            return nil
        end
        local r = math.random()
        local acc = 0
        for _, e in ipairs(entries) do
            acc += (math.max(0, e.p) / sum)
            if r < acc then
                return e.name
            end
        end
        return nil
    end

    local pattern = pickPattern()
    local usedLanes: { [number]: boolean } = {}
    if pattern == "CoinLine" then
        local laneX = Constants.LANES[math.random(1, #Constants.LANES)]
        local count = math.random(6, 8)
        local startZ = baseZ + 10
        local stepZ = (Constants.SPAWN.SegmentLength - 20) / count
        for i = 0, count - 1 do
            local c = createCoin()
            c.Position = Vector3.new(laneX, 4, startZ + i * stepZ)
            c.Parent = segmentFolder
        end
        usedLanes[laneX] = true
    elseif pattern == "CoinZigZag" then
        local order = { 1, 2, 3 }
        if #Constants.LANES == 3 and math.random() < 0.5 then
            order = { 3, 2, 1 }
        end
        local count = 9
        local startZ = baseZ + 10
        local stepZ = (Constants.SPAWN.SegmentLength - 20) / count
        for i = 0, count - 1 do
            local laneIndex = order[(i % #order) + 1]
            local laneX = Constants.LANES[laneIndex]
            local c = createCoin()
            c.Position = Vector3.new(laneX, 4, startZ + i * stepZ)
            c.Parent = segmentFolder
        end
    elseif pattern == "LaneBlocker" then
        local freeIndex = math.random(1, #Constants.LANES)
        local z = baseZ + math.random(18, Constants.SPAWN.SegmentLength - 18)
        for i, laneX in ipairs(Constants.LANES) do
            if i ~= freeIndex then
                local r2 = math.random()
                local o: BasePart
                if r2 < 0.33 then
                    o = createObstacleTall()
                elseif r2 < 0.66 then
                    o = createObstacleWide()
                else
                    o = createObstacle()
                end
                local halfY = o.Size.Y / 2
                o.Position = Vector3.new(laneX, 3 + halfY - 0.5, z)
                o.Parent = segmentFolder
            end
        end
    elseif pattern == "Mover" then
        local laneX = Constants.LANES[math.random(1, #Constants.LANES)]
        local z = baseZ + math.random(18, Constants.SPAWN.SegmentLength - 18)
        local o = createMovingObstacle(laneX, 3 + 2.5 - 0.5, z)
        o.Parent = segmentFolder
        -- Parametrisierung für Bewegung (kleine seitliche Oszillation innerhalb Lane)
        local amp = 1.5
        local freq = math.random(25, 60) / 100 -- 0.25 .. 0.60 Hz
        local phase = math.random() * math.pi * 2
        if s and s.Movers then
            table.insert(s.Movers, { part = o, baseX = laneX, amp = amp, freq = freq, phase = phase })
        end
    end

    if not pattern then
        -- Spawn obstacles/coins/powerups pro Lane (deterministisch via SpawnUtils)
        for _, laneX in ipairs(Constants.LANES) do
            local roll = math.random()
            local z = baseZ + math.random(10, Constants.SPAWN.SegmentLength - 10)

            local kindOpt = SpawnUtils.pickLaneContent(roll, {
                OverhangChance = Constants.SPAWN.OverhangChance,
                ObstacleChance = Constants.SPAWN.ObstacleChance,
                CoinChance = Constants.SPAWN.CoinChance,
                PowerupChance = Constants.SPAWN.PowerupChance,
            })

            if kindOpt == "Overhang" then
                local o = createOverhang()
                o.Position = Vector3.new(laneX, 3 + 1.4, z)
                o.Parent = segmentFolder
            elseif kindOpt == "Obstacle" then
                -- Variante wählen (visuell, Kollision bleibt "Obstacle")
                local r2 = math.random()
                local o: BasePart
                if r2 < 0.25 then
                    o = createObstacleTall()
                elseif r2 < 0.5 then
                    o = createObstacleLow()
                elseif r2 < 0.75 then
                    o = createObstacleWide()
                else
                    o = createObstacle()
                end
                local halfY = o.Size.Y / 2
                o.Position = Vector3.new(laneX, 3 + halfY - 0.5, z)
                o.Parent = segmentFolder
            elseif kindOpt == "Coin" then
                local c = createCoin()
                c.Position = Vector3.new(laneX, 4, z)
                c.Parent = segmentFolder
            elseif kindOpt == "Powerup" then
                local pick = math.random()
                local kind = SpawnUtils.pickPowerupKind(
                    pick,
                    (tonumber(Constants.POWERUPS.Magnet.Weight) or 1),
                    (tonumber(Constants.POWERUPS.Shield.Weight) or 1)
                )
                local pu = createPowerup(kind)
                pu.Position = Vector3.new(laneX, 4, z)
                pu.Parent = segmentFolder
            end
        end
    end

    -- Deko-Spawns am Rand (außerhalb der Lanes), unabhängig von Lane-Inhalten
    local decoChance = (Constants.SPAWN.DecoChance or 0.35)
    if math.random() < decoChance then
        -- Links & rechts je ein Deko-Objekt mit leichter Varianz
        local leftX = (Constants.LANES[1] or -5) - 6
        local rightX = (Constants.LANES[#Constants.LANES] or 5) + 6
        local zA = baseZ + math.random(6, math.max(7, Constants.SPAWN.SegmentLength - 20))
        local zB = baseZ + math.random(6, math.max(7, Constants.SPAWN.SegmentLength - 20))
        local kinds = { "Post", "Crate", "Fence" }
        local function pickKind(): string
            local i = math.random(1, #kinds)
            return kinds[i]
        end
        local d1 = createDeco(pickKind())
        d1.Position = Vector3.new(leftX, (d1.Size.Y / 2), zA)
        d1.Parent = segmentFolder
        local d2 = createDeco(pickKind())
        d2.Position = Vector3.new(rightX, (d2.Size.Y / 2), zB)
        d2.Parent = segmentFolder
    end
end

-- Movement & collisions
local function stepPlayer(player: Player, dt: number)
    local s = state[player]
    if not s or not s.HRP then
        return
    end

    -- Wenn bereits Game Over, überspringe weitere Updates
    if s.GameOver then
        return
    end

    -- Beschleunigung
    s.Speed = math.clamp(
        s.Speed + (Constants.PLAYER.Acceleration * dt),
        Constants.PLAYER.BaseSpeed,
        Constants.PLAYER.MaxSpeed
    )

    -- Bewegung
    local desiredX = Constants.LANES[s.LaneIndex]
    local currentPos = s.HRP.Position
    local nextX
    if math.abs(currentPos.X - desiredX) < 0.1 then
        nextX = desiredX
    else
        local dir = (desiredX > currentPos.X) and 1 or -1
        local laneFactor = (Constants.PLAYER and (Constants.PLAYER :: any).LaneSwitchFactor) or 1
        nextX = currentPos.X + dir * Constants.PLAYER.LaneSwitchSpeed * laneFactor * dt
        if (dir > 0 and nextX > desiredX) or (dir < 0 and nextX < desiredX) then
            nextX = desiredX
        end
    end
    -- Roll-Boost: während des Rollens gibt es einen kurzen Vorwärtsschub
    local isRolling = (s.RollingUntil or 0) > os.clock()
    local rollBonus = isRolling and (Constants.PLAYER.RollBoost or 0) or 0
    local nextZ = currentPos.Z + (s.Speed + rollBonus) * dt
    -- Einfache Vertikalphysik
    local gravity = workspace.Gravity
    s.VerticalVel = (s.VerticalVel or 0) - gravity * dt
    s.VerticalY = (s.VerticalY or 3) + (s.VerticalVel or 0) * dt
    local groundY = 3
    if (s.VerticalY :: number) <= groundY then
        s.VerticalY = groundY
        s.VerticalVel = 0
        -- Übergang Bodenkontakt
        local was = s.OnGround
        s.OnGround = true
        if was == false then
            -- Gerade gelandet: Sprunganimation beenden
            local hum = s.Humanoid
            if hum then
                hum.Jump = false
                stopJumpTracks(hum)
                pcall(function()
                    hum:ChangeState(Enum.HumanoidStateType.Landed)
                end)
                pcall(function()
                    hum:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
                end)
            end
            -- Wenn während des Sprungs Roll gewünscht wurde, jetzt starten
            if s.QueueRollOnLand then
                s.QueueRollOnLand = false
                local duration = (Constants.PLAYER.RollDuration or 0.6)
                s.RollingUntil = os.clock() + duration
                if hum then
                    pcall(function()
                        hum:ChangeState(Enum.HumanoidStateType.Running)
                    end)
                end
                -- Client über Roll-Start informieren
                ActionSync:FireClient(player, { action = "Roll" })
            end
        end
    else
        s.OnGround = false
        -- In der Luft: sichere State setzen, damit Animate aus Jump übergeht
        local hum = s.Humanoid
        if hum then
            pcall(function()
                hum:ChangeState(Enum.HumanoidStateType.Freefall)
            end)
        end
    end

    -- Speichere vorherigen Zustand für nächste Iteration
    s.WasOnGround = s.OnGround

    -- Spieler dauerhaft um 180° drehen (Rücken zur Kamera, Blick nach +Z)
    s.HRP.CFrame = CFrame.new(nextX, s.VerticalY or currentPos.Y, nextZ) * CFrame.Angles(0, math.pi, 0)

    -- Zurückgelegte Strecke
    s.Distance += s.Speed * dt

    -- Segment-Management
    local nextSegZ = s.NextSegment * Constants.SPAWN.SegmentLength
    if nextZ + Constants.SPAWN.SegmentLength * 2 > nextSegZ then
        local prevIndex = (
            (s.NextSegment - 1) // math.max(1, (Constants.BIOMES and Constants.BIOMES.SegmentsPerBiome) or 8)
        )
        spawnSegment(player, s.NextSegment + Constants.SPAWN.ViewDistance, nextSegZ)
        s.NextSegment += 1
        -- Dynamische Events: Double Coins mit Segment-Trigger starten, wenn inaktiv
        do
            local cfg = (Constants.EVENTS and Constants.EVENTS.DoubleCoins) or nil
            if cfg then
                local active = (s.DoubleCoinsUntil or 0) > os.clock()
                if not active then
                    local ch = cfg.StartChancePerSegment or 0.0
                    if math.random() < ch then
                        s.DoubleCoinsUntil = os.clock() + (cfg.Duration or 60)
                        EventAnnounce:FireClient(player, { kind = "DoubleCoins", duration = cfg.Duration or 60 })
                    end
                end
            end
        end
        -- Biome-Wechsel prüfen und Lighting sanft blenden (serverseitig global)
        local biomes = (Constants.BIOMES and Constants.BIOMES.List) or {}
        if #biomes > 0 then
            local newIndex = ((s.NextSegment - 1) // math.max(1, Constants.BIOMES.SegmentsPerBiome))
            if newIndex ~= prevIndex then
                local toIdx = ((newIndex % #biomes) + 1)
                local fromIdx = ((prevIndex % #biomes) + 1)
                local fromTheme = biomes[fromIdx]
                local toTheme = biomes[toIdx]
                task.spawn(function()
                    blendLighting(fromTheme, toTheme, (Constants.BIOMES.TransitionDuration or 3.0))
                end)
            end
        end
        -- Aufräumen
        local toKeepFrom = s.NextSegment - Constants.SPAWN.CleanupBehind
        for _, child in ipairs((s.Folder :: Folder):GetChildren()) do
            local idx = tonumber(string.match(child.Name, "Seg_(%d+)") or "0") or 0
            if idx > 0 and idx < toKeepFrom then
                child:Destroy()
            end
        end
    end

    -- Kollisionsprüfung (AABB-Umgebung)
    local hrp = s.HRP
    -- Reuse OverlapParams per player to reduce allocations
    -- Multiplayer-Guard: Include NUR den Track-Ordner dieses Spielers → verhindert Cross-Pickups/Kollisionen
    local overlap: OverlapParams = s.OverlapParams or OverlapParams.new()
    overlap.FilterType = Enum.RaycastFilterType.Include
    overlap.RespectCanCollide = false
    s.OverlapParams = overlap
    -- Refresh dynamic filter list
    local filter: { Instance } = s.OverlapFilter or ({} :: { Instance })
    s.OverlapFilter = filter
    local trackFolder = s.Folder
    if not trackFolder then
        return
    end
    filter[1] = trackFolder
    overlap.FilterDescendantsInstances = filter

    -- Kollisionsbox fix 2 Studs vor dem Spieler in Welt-+Z, unabhängig von seiner Rotation
    local boxCFrame = CFrame.new(hrp.Position + Vector3.new(0, 0.5, 2))
    local boxHeight = isRolling and 2.2 or 5.6
    local parts = workspace:GetPartBoundsInBox(boxCFrame, Vector3.new(5.5, boxHeight, 5.5), overlap)
    for _, part in ipairs(parts) do
        if part.Name == "Obstacle" then
            if (s.ShieldHits or 0) > 0 then
                s.ShieldHits = (s.ShieldHits :: number) - 1
                part:Destroy()
                UpdateHUD:FireClient(player, {
                    distance = math.floor(s.Distance),
                    coins = s.Coins,
                    speed = math.floor(s.Speed),
                    shield = s.ShieldHits,
                    shieldTime = math.max(0, (s.ShieldUntil or 0) - os.clock()),
                    multiplier = s.Multiplier or 1,
                })
            else
                if not s.GameOver then
                    -- Multiplier/Streak zurücksetzen
                    s.CoinStreak = 0
                    s.Multiplier = 1.0
                    s.GameOver = true
                    s.Speed = 0
                    print("[Server] GameOver collision detected for player", player.Name)
                    GameOver:FireClient(player)
                    -- Persist best distance and coins on GameOver (throttled)
                    requestSave(player, "GameOver", false)
                end
            end
            break
        elseif part.Name == "Overhang" then
            -- Overhang trifft nur, wenn nicht gerollt wird
            if not isRolling then
                if (s.ShieldHits or 0) > 0 then
                    s.ShieldHits = (s.ShieldHits :: number) - 1
                    part:Destroy()
                    UpdateHUD:FireClient(player, {
                        distance = math.floor(s.Distance),
                        coins = s.Coins,
                        speed = math.floor(s.Speed),
                        shield = s.ShieldHits,
                        shieldTime = math.max(0, (s.ShieldUntil or 0) - os.clock()),
                        multiplier = s.Multiplier or 1,
                    })
                else
                    if not s.GameOver then
                        s.CoinStreak = 0
                        s.Multiplier = 1.0
                        s.GameOver = true
                        s.Speed = 0
                        print("[Server] GameOver (Overhang) for player", player.Name)
                        GameOver:FireClient(player)
                        -- Persist best distance and coins on GameOver (throttled)
                        requestSave(player, "GameOver", false)
                    end
                end
                break
            end
        elseif part.Name == "Coin" and part.Parent then
            if not part:GetAttribute("Collected") then
                part:SetAttribute("Collected", true)
                local base = Constants.COLLISION.CoinValue
                local mult = 1
                if (s.DoubleCoinsUntil or 0) > os.clock() then
                    local cfg = (Constants.EVENTS and Constants.EVENTS.DoubleCoins) or nil
                    mult = (cfg and (cfg.Multiplier or 2)) or 2
                end
                -- Scoring: Multiplikator anhand CoinStreak
                local sc = getScoreCfg()
                s.CoinStreak = (s.CoinStreak or 0) + 1
                local step = math.max(1, math.floor(sc.StreakStep))
                local incPer = sc.MultiplierPerStep
                local maxMul = sc.MaxMultiplier
                local steps = math.floor((s.CoinStreak or 0) / step)
                local currMul = 1.0 + steps * incPer
                if currMul > maxMul then
                    currMul = maxMul
                end
                s.Multiplier = currMul
                local gained = math.floor(base * mult * currMul)
                s.Coins += gained

                -- HUD-Feedback (sofort, zusätzlich zur Taktung)
                local payload: HUDPayload = {
                    distance = math.floor(s.Distance),
                    coins = s.Coins,
                    speed = math.floor(s.Speed),
                    multiplier = s.Multiplier,
                }
                if Constants.DEBUG_LOGS then
                    print(
                        "[Server] Coin collected, UpdateHUD ->",
                        player.Name,
                        payload.distance,
                        payload.coins,
                        payload.speed
                    )
                end
                UpdateHUD:FireClient(player, payload)
                -- Sounds abspielen
                CoinPickup:FireClient(player)
                part:Destroy()
            end
        elseif part.Name == "Powerup" and part.Parent then
            local kind = part:GetAttribute("Kind")
            if kind == "Magnet" then
                -- Stack Magnet duration on overlapping pickups instead of overwriting
                local now = os.clock()
                s.MagnetUntil = math.max(s.MagnetUntil or 0, now) + (Constants.POWERUPS.Magnet.Duration or 8)
                PowerupPickup:FireClient(player, { kind = kind })
            elseif kind == "Shield" then
                s.ShieldHits = math.max(1, (s.ShieldHits or 0) + (Constants.POWERUPS.Shield.Hits or 1))
                local dur = (Constants.POWERUPS.Shield.Duration or 0)
                if dur > 0 then
                    local now = os.clock()
                    s.ShieldUntil = math.max(s.ShieldUntil or 0, now) + dur
                end
                PowerupPickup:FireClient(player, { kind = kind })
            end
            part:Destroy()
        end
    end

    -- Magnet: Coins anziehen
    if (s.MagnetUntil or 0) > os.clock() then
        local radius = tonumber(Constants.POWERUPS.Magnet.Radius) or 16
        local near = workspace:GetPartBoundsInRadius(hrp.Position, radius, overlap)
        for _, p in ipairs(near) do
            if p.Name == "Coin" and p.Parent and not p:GetAttribute("Collected") then
                local dir = (hrp.Position - p.Position)
                local dist = dir.Magnitude
                if dist > 0 then
                    local step = dir.Unit * math.min(dist, 60 * dt)
                    p.CFrame = p.CFrame + step
                    if dist < 3 then
                        p:SetAttribute("Collected", true)
                        local base = Constants.COLLISION.CoinValue
                        local mult = 1
                        if (s.DoubleCoinsUntil or 0) > os.clock() then
                            local cfg = (Constants.EVENTS and Constants.EVENTS.DoubleCoins) or nil
                            mult = (cfg and (cfg.Multiplier or 2)) or 2
                        end
                        -- Scoring über Magnet-Pickups ebenfalls berücksichtigen
                        local sc = getScoreCfg()
                        s.CoinStreak = (s.CoinStreak or 0) + 1
                        local stepS = math.max(1, math.floor(sc.StreakStep))
                        local incPer = sc.MultiplierPerStep
                        local maxMul = sc.MaxMultiplier
                        local steps = math.floor((s.CoinStreak or 0) / stepS)
                        local currMul = 1.0 + steps * incPer
                        if currMul > maxMul then
                            currMul = maxMul
                        end
                        s.Multiplier = currMul
                        local gained = math.floor(base * mult * currMul)
                        s.Coins += gained
                        local payload2: HUDPayload = {
                            distance = math.floor(s.Distance),
                            coins = s.Coins,
                            speed = math.floor(s.Speed),
                            magnet = math.max(0, (s.MagnetUntil or 0) - os.clock()),
                            shield = s.ShieldHits or 0,
                            shieldTime = math.max(0, (s.ShieldUntil or 0) - os.clock()),
                            multiplier = s.Multiplier,
                        }
                        UpdateHUD:FireClient(player, payload2)
                        CoinPickup:FireClient(player)
                        p:Destroy()
                    end
                end
            end
        end
    end

    -- Bewegliche Hindernisse aktualisieren (kleiner seitlicher Sinus in X)
    do
        local movers = s.Movers
        if movers and #movers > 0 then
            local t = os.clock()
            local i = 1
            while i <= #movers do
                local m = movers[i]
                local part = m.part
                if not part or part.Parent == nil then
                    table.remove(movers, i)
                else
                    local x = m.baseX + math.sin((t + m.phase) * (2 * math.pi) * m.freq) * m.amp
                    local pos = part.Position
                    part.CFrame = CFrame.new(Vector3.new(x, pos.Y, pos.Z))
                    i += 1
                end
            end
        end
    end

    -- HUD-Update (deterministisch getaktet)
    s._HudAccum = (s._HudAccum or 0) + dt
    if (s._HudAccum or 0) >= 0.15 then -- HUD-Throttle: ~6-7 Hz
        s._HudAccum = 0
        local payload: HUDPayload = {
            distance = math.floor(s.Distance),
            coins = s.Coins,
            speed = math.floor(s.Speed),
            magnet = math.max(0, (s.MagnetUntil or 0) - os.clock()),
            shield = s.ShieldHits or 0,
            shieldTime = math.max(0, (s.ShieldUntil or 0) - os.clock()),
            doubleCoins = math.max(0, (s.DoubleCoinsUntil or 0) - os.clock()),
            multiplier = s.Multiplier or 1,
        }
        -- Nur gelegentlich loggen, um Spam zu vermeiden
        if Constants.DEBUG_LOGS and (math.floor(os.clock() * 2) % 6) == 0 then
            print("[Server] Tick UpdateHUD ->", player.Name, payload.distance, payload.coins, payload.speed)
        end
        UpdateHUD:FireClient(player, payload)
    end
end

-- Handle lane change requests from client
-- Spurwechsel: Konvention links=+1, rechts=-1 (nicht ändern)
LaneRequest.OnServerEvent:Connect(function(player, dir: number)
    local s = state[player]
    if not s then
        return
    end
    local newIndex = math.clamp(s.LaneIndex + dir, 1, #Constants.LANES)
    s.LaneIndex = newIndex
end)

-- Restart handler: reset player on request
-- Neustart auf Wunsch des Clients (idempotent): Cleanup + Neuaufbau
RestartRequest.OnServerEvent:Connect(function(player)
    -- Cleanup existing state and tracks
    cleanupPlayer(player)
    -- Recreate runner and initial segments
    createRunnerFor(player)
end)

-- Action handler: Jump / Roll
ActionRequest.OnServerEvent:Connect(function(player, action: string)
    local s = state[player]
    if not s or s.GameOver then
        return
    end
    local hum = s.Humanoid
    local now = os.clock()
    local isRolling = (s.RollingUntil or 0) > now
    local onGround = (s.OnGround == true)
    local isJumping = not onGround

    if action == "Jump" then
        -- Verhindere erneutes Jump während eines laufenden Jumps
        if isJumping then
            return
        end
        -- Erlaube Jump aus Run/Walk oder aus aktivem Roll
        if onGround or isRolling then
            -- Beende ggf. Roll und starte Jump sofort
            s.RollingUntil = 0
            s.VerticalVel = 50 -- Sprungstärke
            s.OnGround = false
            if hum then
                hum.Jump = true
                pcall(function()
                    hum:ChangeState(Enum.HumanoidStateType.Jumping)
                end)
            end
            -- Client über Jump-Start informieren
            ActionSync:FireClient(player, { action = "Jump" })
        end
    elseif action == "Roll" then
        -- Verhindere erneutes Roll während laufendem Roll
        if isRolling then
            return
        end
        local duration = Constants.PLAYER.RollDuration or 0.6
        if onGround then
            -- Erlaubt: aus Run/Walk sofort rollen
            s.RollingUntil = now + duration
            if hum then
                pcall(function()
                    hum:ChangeState(Enum.HumanoidStateType.Running)
                end)
            end
            ActionSync:FireClient(player, { action = "Roll" })
        else
            -- In der Luft (Jump): Jump cancel → sofortige Roll
            -- Setze den Spieler direkt auf den Boden und starte die Roll sofort
            s.VerticalY = 3
            s.VerticalVel = 0
            s.OnGround = true
            local hrp = s.HRP
            if hrp then
                local p = hrp.Position
                hrp.CFrame = CFrame.new(p.X, 3, p.Z) * CFrame.Angles(0, math.pi, 0)
            end
            s.RollingUntil = now + duration
            s.QueueRollOnLand = false
            if hum then
                hum.Jump = false
                stopJumpTracks(hum)
                pcall(function()
                    hum:ChangeState(Enum.HumanoidStateType.Running)
                end)
            end
            ActionSync:FireClient(player, { action = "Roll" })
        end
    end
end)

-- Shop logic: minimal purchase flow (server-authoritativ)
ShopPurchaseRequest.OnServerEvent:Connect(function(player, payload)
    local s = state[player]
    if not s then
        return
    end
    local item = payload and payload.item
    if item == "Shield" then
        local cost = 5
        if (s.Coins or 0) >= cost then
            s.Coins -= cost
            s.ShieldHits = math.max(1, (s.ShieldHits or 0) + 1)
            -- HUD-Update nach Kauf
            UpdateHUD:FireClient(player, {
                distance = math.floor(s.Distance),
                coins = s.Coins,
                speed = math.floor(s.Speed),
                shield = s.ShieldHits,
            })
            ShopResult:FireClient(player, { ok = true })
            -- Persist coins after purchase (throttled)
            requestSave(player, "ShopPurchase", false)
        else
            ShopResult:FireClient(player, { ok = false, reason = "Zu wenig Coins" })
        end
    else
        ShopResult:FireClient(player, { ok = false, reason = "Unbekannter Artikel" })
    end
end)

-- Player lifecycle
-- Track last processed character per player to avoid double init when CharacterAdded fires rapidly
local lastCharacterProcessed: { [Player]: Model? } = {}

local function isInArena(player: Player): boolean
    local ok, val = pcall(function()
        return player:GetAttribute("InArena")
    end)
    return ok and (val == true)
end

local function ensureRunnerIfArena(player: Player)
    if isInArena(player) then
        if not state[player] then
            -- Ensure clean previous (defensive)
            cleanupPlayer(player)
            createRunnerFor(player)
            task.defer(function()
                applyLoadedData(player)
            end)
        end
    else
        if state[player] then
            cleanupPlayer(player)
        end
    end
end

Players.PlayerAdded:Connect(function(player)
    task.spawn(function()
        loadPlayerData(player)
    end)
    -- Periodic autosave loop per player (lightweight, throttled internally)
    task.spawn(function()
        while player.Parent ~= nil do
            task.wait(60)
            requestSave(player, "Autosave", false)
        end
    end)
    -- Respond to arena attribute changes
    player:GetAttributeChangedSignal("InArena"):Connect(function()
        ensureRunnerIfArena(player)
    end)
    -- On character spawns, re-evaluate arena state
    player.CharacterAdded:Connect(function(character)
        if lastCharacterProcessed[player] == character then
            return
        end
        lastCharacterProcessed[player] = character
        ensureRunnerIfArena(player)
    end)
    -- Initial check if character already exists
    if player.Character then
        ensureRunnerIfArena(player)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    -- Urgent save on player leave
    requestSave(player, "PlayerRemoving", true)
    cleanupPlayer(player)
    saveMeta[player.UserId] = nil
    saveCache[player.UserId] = nil
end)

-- Main loop
RunService.Heartbeat:Connect(function(dt)
    for player, _ in pairs(state) do
        stepPlayer(player, dt)
    end
end)

-- Save all players on server shutdown (BindToClose)
game:BindToClose(function()
    -- Attempt to save each player's data once (urgent), slightly staggered
    local i = 0
    for player, _ in pairs(state) do
        local delayS = (i % 5) * 0.2
        task.delay(delayS, function()
            requestSave(player, "Shutdown", true)
        end)
        i += 1
    end
end)
