--!strict
-- Constructs a simple HUD at runtime (to avoid manual UI work)

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Try to adopt an existing HUD (e.g., after respawn) to avoid duplicates
local gui: ScreenGui? = nil
do
	local existing = playerGui:FindFirstChild("HUD")
	if existing and existing:IsA("ScreenGui") then
		gui = existing
	else
		for _, child in ipairs(playerGui:GetChildren()) do
			if child:IsA("ScreenGui") and child:GetAttribute("EndlessHUD") then
				gui = child
				break
			end
		end
	end
end

if gui then
	gui.Name = "HUD"
	gui:SetAttribute("EndlessHUD", true)
else
	gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false
	gui:SetAttribute("EndlessHUD", true)
	gui.Parent = playerGui
	print("[HUD] ScreenGui created and parented to PlayerGui")
end

-- Label factory
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
	lbl.Parent = gui
	return lbl
end

-- Create labels if missing and set initial text
local distanceLbl = (gui :: ScreenGui):FindFirstChild("Distance") :: TextLabel?
if not distanceLbl then distanceLbl = makeLabel("Distance", UDim2.new(0, 20, 0, 20)) end
distanceLbl.Text = "0m"

local coinsLbl = (gui :: ScreenGui):FindFirstChild("Coins") :: TextLabel?
if not coinsLbl then coinsLbl = makeLabel("Coins", UDim2.new(0, 20, 0, 70)) end
coinsLbl.Text = "0"

local speedLbl = (gui :: ScreenGui):FindFirstChild("Speed") :: TextLabel?
if not speedLbl then speedLbl = makeLabel("Speed", UDim2.new(0, 20, 0, 120)) end
speedLbl.Text = "0"

-- optionale Powerup-Anzeigen
local magnetLbl = (gui :: ScreenGui):FindFirstChild("Magnet") :: TextLabel?
if not magnetLbl then magnetLbl = makeLabel("Magnet", UDim2.new(0, 20, 0, 170)) end
magnetLbl.Text = ""

local shieldLbl = (gui :: ScreenGui):FindFirstChild("Shield") :: TextLabel?
if not shieldLbl then shieldLbl = makeLabel("Shield", UDim2.new(0, 20, 0, 220)) end
shieldLbl.Text = ""

print("[HUD] Labels initialized: Distance/Coins/Speed")
