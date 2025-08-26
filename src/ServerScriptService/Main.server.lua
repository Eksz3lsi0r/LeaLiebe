--!strict
-- Server-side game loop & procedural generation

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants")) :: {
		PLAYER: { BaseSpeed: number, Acceleration: number, MaxSpeed: number, LaneSwitchSpeed: number, RollDuration: number, RollBoost: number },
		SPAWN: { ViewDistance: number, SegmentLength: number, OverhangChance: number, ObstacleChance: number, CoinChance: number, CleanupBehind: number, PowerupChance: number },
		LANES: { number },
		COLLISION: { CoinValue: number },
		POWERUPS: any,
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

local ActionRequest = Instance.new("RemoteEvent")
ActionRequest.Name = "ActionRequest"
ActionRequest.Parent = RemotesFolder

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
	VerticalY: number?,     -- Y-Position
	VerticalVel: number?,   -- vertikale Geschwindigkeit
	OnGround: boolean?,     -- steht auf dem Boden?
	RollingUntil: number?,  -- Roll-Endezeit
	WasOnGround: boolean?,  -- vorheriger Bodenkontakt
	-- Powerups
	MagnetUntil: number?,
	ShieldHits: number?,
}

local state: { [Player]: PlayerState } = {}

-- Animation helpers
local function getAnimator(hum: Humanoid): Animator?
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		local ok, err = pcall(function()
			animator = Instance.new("Animator")
			animator.Parent = hum
		end)
		if not ok then
			warn("[Server] Failed to create Animator:", err)
			return nil
		end
	end
	return animator :: Animator
end

local function stopJumpTracks(hum: Humanoid)
	local animator = getAnimator(hum)
	if not animator then return end
	local ok, tracks = pcall(function()
		return animator:GetPlayingAnimationTracks()
	end)
	if not ok or not tracks then return end
	for _, tr in ipairs(tracks :: {AnimationTrack}) do
		local n = (tr.Name or ""):lower()
		local an = ""
		local a = tr.Animation
		if a then an = (a.Name or ""):lower() end
		if string.find(n, "jump") or string.find(an, "jump") then
			pcall(function() tr:Stop(0.1) end)
		end
	end
end

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
		VerticalY = 3,
		VerticalVel = 0,
		OnGround = true,
		RollingUntil = 0,
		WasOnGround = true,
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
	p.CanCollide = false
	return p
end

local function createOverhang()
	-- Hängelnde Barriere, die nur im Duck/ Roll unterquert werden kann
	local p = Instance.new("Part")
	p.Size = Vector3.new(4, 2.2, 4)
	p.Anchored = true
	p.Color = Color3.fromRGB(255, 140, 0)
	p.Name = "Overhang"
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
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

local function createPowerup(kind: string)
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
	return p
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

		-- Overhang (nur durch Rollen passierbar)
		if roll < Constants.SPAWN.OverhangChance then
			local o = createOverhang()
			-- Overhang leicht niedriger, erfordert Rollen
			o.Position = Vector3.new(laneX, 3 + 1.4, z)
			o.Parent = segmentFolder
		elseif roll < Constants.SPAWN.OverhangChance + Constants.SPAWN.ObstacleChance then
			local o = createObstacle()
			o.Position = Vector3.new(laneX, 3, z)
			o.Parent = segmentFolder
		elseif roll < Constants.SPAWN.OverhangChance + Constants.SPAWN.ObstacleChance + Constants.SPAWN.CoinChance then
			local c = createCoin()
			c.Position = Vector3.new(laneX, 4, z)
			c.Parent = segmentFolder
		elseif roll < (Constants.SPAWN.OverhangChance + Constants.SPAWN.ObstacleChance + Constants.SPAWN.CoinChance + (Constants.SPAWN.PowerupChance or 0)) then
		local pick = math.random()
		local totalW = (Constants.POWERUPS.Magnet.Weight or 1) + (Constants.POWERUPS.Shield.Weight or 1)
		local magCut = (Constants.POWERUPS.Magnet.Weight or 1) / totalW
		local kind = (pick <= magCut) and "Magnet" or "Shield"
		local pu = createPowerup(kind)
		pu.Position = Vector3.new(laneX, 4, z)
		pu.Parent = segmentFolder
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
	local boxCFrame = CFrame.new(hrp.Position + Vector3.new(0, 0.5, 2))
	local boxHeight = isRolling and 2.2 or 5.6
	local parts = workspace:GetPartBoundsInBox(boxCFrame, Vector3.new(5.5, boxHeight, 5.5), overlap)
	for _, part in ipairs(parts) do
		if part.Name == "Obstacle" then
			if (s.ShieldHits or 0) > 0 then
				s.ShieldHits = (s.ShieldHits :: number) - 1
				part:Destroy()
				UpdateHUD:FireClient(player, { distance = math.floor(s.Distance), coins = s.Coins, speed = math.floor(s.Speed), shield = s.ShieldHits })
			else
				if not s.GameOver then
					s.GameOver = true
					s.Speed = 0
					print("[Server] GameOver collision detected for player", player.Name)
					GameOver:FireClient(player)
				end
			end
			break
		elseif part.Name == "Overhang" then
			-- Overhang trifft nur, wenn nicht gerollt wird
			if not isRolling then
				if (s.ShieldHits or 0) > 0 then
					s.ShieldHits = (s.ShieldHits :: number) - 1
					part:Destroy()
					UpdateHUD:FireClient(player, { distance = math.floor(s.Distance), coins = s.Coins, speed = math.floor(s.Speed), shield = s.ShieldHits })
				else
					if not s.GameOver then
						s.GameOver = true
						s.Speed = 0
						print("[Server] GameOver (Overhang) for player", player.Name)
						GameOver:FireClient(player)
					end
				end
				break
			end
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
		elseif part.Name == "Powerup" and part.Parent then
			local kind = part:GetAttribute("Kind")
			if kind == "Magnet" then
				s.MagnetUntil = os.clock() + (Constants.POWERUPS.Magnet.Duration or 8)
				PowerupPickup:FireClient(player, { kind = kind })
			elseif kind == "Shield" then
				s.ShieldHits = math.max(1, (s.ShieldHits or 0) + (Constants.POWERUPS.Shield.Hits or 1))
				PowerupPickup:FireClient(player, { kind = kind })
			end
			part:Destroy()
		end
	end

	-- Magnet: Coins anziehen
	if (s.MagnetUntil or 0) > os.clock() then
		local radius = (Constants.POWERUPS.Magnet.Radius or 16)
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
						s.Coins += Constants.COLLISION.CoinValue
						UpdateHUD:FireClient(player, { distance = math.floor(s.Distance), coins = s.Coins, speed = math.floor(s.Speed), magnet = math.max(0, (s.MagnetUntil or 0) - os.clock()) })
						CoinPickup:FireClient(player)
						p:Destroy()
					end
				end
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
            magnet = math.max(0, (s.MagnetUntil or 0) - os.clock()),
            shield = s.ShieldHits or 0,
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

-- Action handler: Jump / Roll
ActionRequest.OnServerEvent:Connect(function(player, action: string)
	local s = state[player]
	if not s or s.GameOver then return end
	local hum = s.Humanoid
	if action == "Jump" then
	if s.OnGround and (s.RollingUntil or 0) <= os.clock() then
			s.VerticalVel = 50 -- Sprungstärke
			s.OnGround = false
			-- Sprunganimation starten
			if hum then
				hum.Jump = true
				pcall(function()
					hum:ChangeState(Enum.HumanoidStateType.Jumping)
				end)
			end
		end
	elseif action == "Roll" then
		local now = os.clock()
	if s.OnGround and (s.RollingUntil or 0) <= now then
			local duration = Constants.PLAYER.RollDuration or 0.6
			s.RollingUntil = now + duration -- Roll aktiv, kein Cooldown
			-- optional: State halten
			if hum then
				pcall(function()
					hum:ChangeState(Enum.HumanoidStateType.Running)
				end)
			end
		end
	end
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
