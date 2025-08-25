--!strict
-- Server-side game loop & procedural generation

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants")) :: {
    PLAYER: { BaseSpeed: number, Acceleration: number, MaxSpeed: number, LaneSwitchSpeed: number },
    SPAWN: { ViewDistance: number, SegmentLength: number, ObstacleChance: number, CoinChance: number, CleanupBehind: number },
    LANES: { number },
    COLLISION: { CoinValue: number },
}

-- Vorwärtsdeklaration, damit Funktionen, die spawnSegment aufrufen, die lokale Variable erfassen
local spawnSegment: (player: Player, segmentIndex: number, baseZ: number) -> ()

-- Remotes
local RemotesFolder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
RemotesFolder.Name = "Remotes"
RemotesFolder.Parent = ReplicatedStorage

local LaneRequest = Instance.new("RemoteEvent")
LaneRequest.Name = "LaneRequest"
LaneRequest.Parent = RemotesFolder

local UpdateHUD = Instance.new("RemoteEvent")
UpdateHUD.Name = "UpdateHUD"
UpdateHUD.Parent = RemotesFolder

local CoinPickup = Instance.new("RemoteEvent")
CoinPickup.Name = "CoinPickup"
CoinPickup.Parent = RemotesFolder

-- Neues RemoteEvent für Game Over
local GameOver = Instance.new("RemoteEvent")
GameOver.Name = "GameOver"
GameOver.Parent = RemotesFolder

-- Neues RemoteEvent für Neustart
local RestartRequest = Instance.new("RemoteEvent")
RestartRequest.Name = "RestartRequest"
RestartRequest.Parent = RemotesFolder

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
    GameOver: boolean?,  -- Neu: Spiel beendet Flag
	_HudAccum: number?,  -- Throttle-Akkumulator für HUD-Updates
}

local state: { [Player]: PlayerState } = {}

local function createRunnerFor(player: Player)
	local character = player.Character or player.CharacterAdded:Wait()
	local hrp = character:WaitForChild("HumanoidRootPart") :: BasePart
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	-- Ensure network ownership stays server-side for authoritative movement
	hrp:SetNetworkOwner(nil)

	local folder = workspace:FindFirstChild("Tracks")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Tracks"
		folder.Parent = workspace
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
	local initialPayload = {
		distance = 0,
		coins = 0,
		speed = math.floor(Constants.PLAYER.BaseSpeed),
	}
	print("[Server] Initial UpdateHUD ->", player.Name, initialPayload.distance, initialPayload.coins, initialPayload.speed)
	UpdateHUD:FireClient(player, initialPayload)
end

local function cleanupPlayer(player: Player)
	local s = state[player]
	if s and s.Folder then s.Folder:Destroy() end
	state[player] = nil
end

-- Object Pools
local function createObstacle()
	local p = Instance.new("Part")
	p.Size = Vector3.new(4, 6, 4)
	p.Anchored = true
	p.Color = Color3.fromRGB(255, 81, 81)
	p.Name = "Obstacle"
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function createCoin()
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
	return coin
end

-- Track segment creation
spawnSegment = function(player: Player, segmentIndex: number, baseZ: number)
	local s = state[player]
	if not s or not s.Folder then return end

	local segmentFolder = Instance.new("Folder")
	segmentFolder.Name = string.format("Seg_%04d", segmentIndex)
	segmentFolder.Parent = s.Folder

	-- Lane ground lanes (visual)
	for _, laneX in ipairs(Constants.LANES) do
		local ground = Instance.new("Part")
		ground.Size = Vector3.new(6, 1, Constants.SPAWN.SegmentLength)
		ground.Anchored = true
		ground.Material = Enum.Material.SmoothPlastic
		ground.Color = Color3.fromRGB(59, 59, 59)
		ground.Position = Vector3.new(laneX, 0, baseZ + Constants.SPAWN.SegmentLength/2)
		ground.Name = "Ground"
		ground.Parent = segmentFolder
	end

	-- Spawn obstacles/coins
	for _, laneX in ipairs(Constants.LANES) do
		local roll = math.random()
		local z = baseZ + math.random(10, Constants.SPAWN.SegmentLength - 10)
		if roll < Constants.SPAWN.ObstacleChance then
			local o = createObstacle()
			o.Position = Vector3.new(laneX, 3, z)
			o.Parent = segmentFolder
		elseif roll < Constants.SPAWN.ObstacleChance + Constants.SPAWN.CoinChance then
			local c = createCoin()
			c.Position = Vector3.new(laneX, 4, z)
			c.Parent = segmentFolder
		end
	end
end

-- Movement & collisions
local function stepPlayer(player: Player, dt: number)
	local s = state[player]
	if not s or not s.HRP then return end

	-- Wenn bereits Game Over, überspringe weitere Updates
	if s.GameOver then return end

	-- Beschleunigung
	s.Speed = math.clamp(s.Speed + (Constants.PLAYER.Acceleration * dt), Constants.PLAYER.BaseSpeed, Constants.PLAYER.MaxSpeed)

	-- Bewegung
	local desiredX = Constants.LANES[s.LaneIndex]
	local currentPos = s.HRP.Position
	local nextX
	if math.abs(currentPos.X - desiredX) < 0.1 then
		nextX = desiredX
	else
		local dir = (desiredX > currentPos.X) and 1 or -1
		nextX = currentPos.X + dir * Constants.PLAYER.LaneSwitchSpeed * dt
		if (dir > 0 and nextX > desiredX) or (dir < 0 and nextX < desiredX) then
			nextX = desiredX
		end
	end
	local nextZ = currentPos.Z + s.Speed * dt
	-- Spieler dauerhaft um 180° drehen (Rücken zur Kamera, Blick nach +Z)
	s.HRP.CFrame = CFrame.new(nextX, currentPos.Y, nextZ) * CFrame.Angles(0, math.pi, 0)

	-- Zurückgelegte Strecke
	s.Distance += s.Speed * dt

	-- Segment-Management
	local nextSegZ = s.NextSegment * Constants.SPAWN.SegmentLength
	if nextZ + Constants.SPAWN.SegmentLength * 2 > nextSegZ then
		spawnSegment(player, s.NextSegment + Constants.SPAWN.ViewDistance, nextSegZ)
		s.NextSegment += 1
		-- Aufräumen
		local toKeepFrom = s.NextSegment - Constants.SPAWN.CleanupBehind
		for _, child in ipairs((s.Folder :: Folder):GetChildren()) do
			local idx = tonumber(string.match(child.Name, "Seg_(%d+)") or "0")
			if idx > 0 and idx < toKeepFrom then
				child:Destroy()
			end
		end
	end

	-- Kollisionsprüfung (AABB-Umgebung)
	local hrp = s.HRP
	local overlap = OverlapParams.new()
	-- Korrektes Filterverhalten: Spieler ausschließen
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { s.Runner }
	overlap.RespectCanCollide = false

	-- Kollisionsbox fix 2 Studs vor dem Spieler in Welt-+Z, unabhängig von seiner Rotation
	local boxCFrame = CFrame.new(hrp.Position + Vector3.new(0, 0, 2))
	local parts = workspace:GetPartBoundsInBox(boxCFrame, Vector3.new(6, 6, 6), overlap)
	for _, part in ipairs(parts) do
		if part.Name == "Obstacle" then
			if not s.GameOver then
				s.GameOver = true
				s.Speed = 0  -- Bewegung stoppen
				print("[Server] GameOver collision detected for player", player.Name)
				-- GameOver an den Client senden
				GameOver:FireClient(player)
			end
			break
		elseif part.Name == "Coin" and part.Parent then
			if not part:GetAttribute("Collected") then
				part:SetAttribute("Collected", true)
				s.Coins += Constants.COLLISION.CoinValue

				-- HUD-Feedback
				local payload = {
					distance = math.floor(s.Distance),
					coins = s.Coins,
					speed = math.floor(s.Speed),
				}
				print("[Server] Coin collected, UpdateHUD ->", player.Name, payload.distance, payload.coins, payload.speed)
				UpdateHUD:FireClient(player, payload)
				-- Sounds abspielen
				CoinPickup:FireClient(player)
				part:Destroy()
			end
		end
	end

	-- HUD-Update (deterministisch getaktet)
	s._HudAccum = (s._HudAccum or 0) + dt
	if s._HudAccum >= 0.15 then
		s._HudAccum = 0
		local payload = {
			distance = math.floor(s.Distance),
			coins = s.Coins,
			speed = math.floor(s.Speed),
		}
		-- Nur gelegentlich loggen, um Spam zu vermeiden
		if (math.floor(os.clock() * 10) % 20) == 0 then
			print("[Server] Tick UpdateHUD ->", player.Name, payload.distance, payload.coins, payload.speed)
		end
		UpdateHUD:FireClient(player, payload)
	end
end

-- Handle lane change requests from client
LaneRequest.OnServerEvent:Connect(function(player, dir: number)
	local s = state[player]
	if not s then return end
	local newIndex = math.clamp(s.LaneIndex + dir, 1, #Constants.LANES)
	s.LaneIndex = newIndex
end)

-- Restart handler: reset player on request
RestartRequest.OnServerEvent:Connect(function(player)
    -- Cleanup existing state and tracks
    cleanupPlayer(player)
    -- Recreate runner and initial segments
    createRunnerFor(player)
end)

-- Player lifecycle
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		createRunnerFor(player)
	end)
	if player.Character then
		createRunnerFor(player)
	end
end)

Players.PlayerRemoving:Connect(cleanupPlayer)

-- Main loop
RunService.Heartbeat:Connect(function(dt)
	for player, _ in pairs(state) do
		stepPlayer(player, dt)
	end
end)
