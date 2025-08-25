--!strict
-- Client input + minor visual FX + HUD hooking

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local LaneRequest = Remotes:WaitForChild("LaneRequest") :: RemoteEvent
local UpdateHUD = Remotes:WaitForChild("UpdateHUD") :: RemoteEvent
local CoinPickup = Remotes:FindFirstChild("CoinPickup") :: RemoteEvent?
local RestartRequest = Remotes:WaitForChild("RestartRequest") :: RemoteEvent

-- Input: A/D or Left/Right to switch lanes
local function onInputBegan(input: InputObject, gpe: boolean)
	if gpe then return end
	-- Swap A/D directions; keep arrow keys intuitive
	if input.KeyCode == Enum.KeyCode.A then
		LaneRequest:FireServer(1)   -- A -> rechts
	elseif input.KeyCode == Enum.KeyCode.D then
		LaneRequest:FireServer(-1)  -- D -> links
	elseif input.KeyCode == Enum.KeyCode.Left then
		LaneRequest:FireServer(-1)  -- Pfeil links bleibt links
	elseif input.KeyCode == Enum.KeyCode.Right then
		LaneRequest:FireServer(1)   -- Pfeil rechts bleibt rechts
	end
end
UserInputService.InputBegan:Connect(onInputBegan)

-- Basic camera: follow behind
local function setupCamera()
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local char = player.Character or player.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart

	game:GetService("RunService").RenderStepped:Connect(function()
		local pos = hrp.Position
		local camPos = pos + Vector3.new(0, 10, -18)
		workspace.CurrentCamera.CFrame = CFrame.new(camPos, pos + Vector3.new(0, 4, 12))
	end)
end

task.spawn(setupCamera)

-- HUD updates
local cachedHUD: ScreenGui? = nil
local cachedDist: TextLabel? = nil
local cachedCoins: TextLabel? = nil
local cachedSpeed: TextLabel? = nil

-- Ensure only one HUD exists at any time (singleton)
local function enforceSingleHUD()
    local sg = player:WaitForChild("PlayerGui")
    local function isHUD(inst: Instance): boolean
        return inst:IsA("ScreenGui") and inst.Name == "HUD"
    end

    -- Prefer adopting an existing HUD if ours isn't resolved yet
    local ours = cachedHUD or (function()
        local h = sg:FindFirstChild("HUD")
        if h and h:IsA("ScreenGui") then
            cachedHUD = h
            h:SetAttribute("EndlessHUD", true)
            return h
        end
        return nil
    end)()

    -- Remove duplicates immediately
    if ours then
        for _, child in ipairs(sg:GetChildren()) do
            if isHUD(child) and child ~= ours then
                child:Destroy()
            end
        end
    end

    -- Future duplicates: destroy anything that isn't our managed HUD
    sg.ChildAdded:Connect(function(child)
        if isHUD(child) then
            local current = cachedHUD or child
            if current ~= child and child.Parent == sg then
                task.defer(function()
                    if child.Parent == sg then child:Destroy() end
                end)
            else
                -- If we had none, adopt this one
                cachedHUD = child
                child:SetAttribute("EndlessHUD", true)
            end
        end
    end)
end

-- Create a minimal HUD if none exists (fallback)
local function ensureHUD(): ScreenGui
    local sg = player:WaitForChild("PlayerGui")
    local existing = sg:FindFirstChild("HUD")
    if existing and existing:IsA("ScreenGui") then
        cachedHUD = existing
        return existing
    end

    local hud = Instance.new("ScreenGui")
    hud.Name = "HUD"
    hud.ResetOnSpawn = false
    hud:SetAttribute("EndlessHUD", true)
    hud.Parent = sg

    local function makeLabel(name: string, pos: UDim2): TextLabel
        local lbl = Instance.new("TextLabel")
        lbl.Name = name
        lbl.BackgroundTransparency = 0.35
        lbl.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        lbl.BorderSizePixel = 0
        lbl.TextColor3 = Color3.new(1, 1, 1)
        lbl.Font = Enum.Font.GothamBold
        lbl.TextScaled = true
        lbl.Size = UDim2.new(0, 160, 0, 40)
        lbl.Position = pos
        lbl.Parent = hud
        return lbl
    end

    makeLabel("Distance", UDim2.new(0, 20, 0, 20)).Text = "0m"
    makeLabel("Coins", UDim2.new(0, 20, 0, 70)).Text = "0"
    makeLabel("Speed", UDim2.new(0, 20, 0, 120)).Text = "0"

    cachedHUD = hud
    cachedDist = hud:FindFirstChild("Distance") :: TextLabel?
    cachedCoins = hud:FindFirstChild("Coins") :: TextLabel?
    cachedSpeed = hud:FindFirstChild("Speed") :: TextLabel?
    return hud
end

-- Activate singleton enforcement once
enforceSingleHUD()

local function resolveHUD(): ScreenGui?
    if cachedHUD and cachedHUD.Parent then return cachedHUD end
    local sg = player:WaitForChild("PlayerGui")
    local hud = sg:FindFirstChild("HUD")
    if not hud then
        for _, child in ipairs(sg:GetChildren()) do
            if child:IsA("ScreenGui") and child:GetAttribute("EndlessHUD") then
                hud = child
                break
            end
        end
    end
    if hud and hud:IsA("ScreenGui") then
        cachedHUD = hud
    end
    return cachedHUD
end

local function resolveLabels()
    local hud = resolveHUD()
    if not hud then return end
    if not (cachedDist and cachedDist.Parent == hud) then
        cachedDist = hud:FindFirstChild("Distance") :: TextLabel?
    end
    if not (cachedCoins and cachedCoins.Parent == hud) then
        cachedCoins = hud:FindFirstChild("Coins") :: TextLabel?
    end
    if not (cachedSpeed and cachedSpeed.Parent == hud) then
        cachedSpeed = hud:FindFirstChild("Speed") :: TextLabel?
    end
end

UpdateHUD.OnClientEvent:Connect(function(payload)
    print("[Client] UpdateHUD received", payload and payload.distance, payload and payload.coins, payload and payload.speed)
    resolveLabels()
    local hud = resolveHUD()
    if not hud then
        -- Try to build a fallback HUD on the fly
        hud = ensureHUD()
        resolveLabels()
    end
    if not hud then
        warn("[Client] HUD ScreenGui not available")
        return
    end
    if cachedDist and cachedDist:IsA("TextLabel") then cachedDist.Text = string.format("%dm", payload.distance or 0) end
    if cachedCoins and cachedCoins:IsA("TextLabel") then cachedCoins.Text = string.format("%d", payload.coins or 0) end
    if cachedSpeed and cachedSpeed:IsA("TextLabel") then cachedSpeed.Text = string.format("%d", payload.speed or 0) end
end)

-- Coin pickup SFX (local)
do
	local cachedSound: Sound? = nil
	local SOUND_ID = "rbxassetid://0" -- TODO: replace with a valid asset id
	local function playCoinSound()
		if not cachedSound then
			cachedSound = Instance.new("Sound")
			cachedSound.Name = "CoinPickupSFX"
			cachedSound.SoundId = SOUND_ID
			cachedSound.Volume = 0.5
			cachedSound.PlaybackSpeed = 1
			cachedSound.Parent = SoundService
		end
		SoundService:PlayLocalSound(cachedSound)
	end
	if CoinPickup then
		CoinPickup.OnClientEvent:Connect(playCoinSound)
	end
end

-- GameOver overlay listener
local GameOver = Remotes:WaitForChild("GameOver") :: RemoteEvent
GameOver.OnClientEvent:Connect(function()
    local playerGui = player:WaitForChild("PlayerGui")
    if playerGui:FindFirstChild("GameOverOverlay") then return end

    local overlay = Instance.new("ScreenGui")
    overlay.Name = "GameOverOverlay"
    overlay.ResetOnSpawn = false

    local frame = Instance.new("Frame")
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    frame.Size = UDim2.new(0, 300, 0, 200)
    frame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    frame.Parent = overlay

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 50)
    title.BackgroundTransparency = 1
    title.Text = "Game Over"
    title.Font = Enum.Font.GothamBold
    title.TextScaled = true
    title.TextColor3 = Color3.new(1, 1, 1)
    title.Parent = frame

    local restart = Instance.new("TextButton")
    restart.Size = UDim2.new(0.8, 0, 0, 40)
    restart.Position = UDim2.new(0.1, 0, 0.5, -50)
    restart.Text = "Neustarten"
    restart.Font = Enum.Font.Gotham
    restart.TextScaled = true
    restart.Parent = frame

    local menu = Instance.new("TextButton")
    menu.Size = UDim2.new(0.8, 0, 0, 40)
    menu.Position = UDim2.new(0.1, 0, 0.5, 0)
    menu.Text = "Hauptmenü"
    menu.Font = Enum.Font.Gotham
    menu.TextScaled = true
    menu.Parent = frame

    local shop = Instance.new("TextButton")
    shop.Size = UDim2.new(0.8, 0, 0, 40)
    shop.Position = UDim2.new(0.1, 0, 0.5, 50)
    shop.Text = "Shop"
    shop.Font = Enum.Font.Gotham
    shop.TextScaled = true
    shop.Parent = frame

    overlay.Parent = playerGui

    restart.MouseButton1Click:Connect(function()
        -- Send restart request to server to reset the game
        RestartRequest:FireServer()
        -- Remove overlay
        overlay:Destroy()
    end)
    menu.MouseButton1Click:Connect(function()
        -- Logik für Hauptmenü
    end)
    shop.MouseButton1Click:Connect(function()
        -- Logik für Shop
    end)
end)
