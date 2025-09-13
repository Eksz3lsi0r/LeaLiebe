--!strict
-- Einfache Lobby-UI mit Start/Respawn sowie Teleport-Buttons

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local StartGame = Remotes:WaitForChild("StartGame") :: RemoteEvent
local TeleportToLobby = Remotes:WaitForChild("TeleportToLobby") :: RemoteEvent
local EnterQueue = Remotes:WaitForChild("EnterQueue") :: RemoteEvent
local EnterArena = Remotes:WaitForChild("EnterArena") :: RemoteEvent

-- GUI erstellen (wenn nicht vorhanden)
local guiAny = playerGui:FindFirstChild("LobbyUI")
if not guiAny or not guiAny:IsA("ScreenGui") then
    local newGui = Instance.new("ScreenGui")
    newGui.Name = "LobbyUI"
    newGui.ResetOnSpawn = false
    newGui.Parent = playerGui
    guiAny = newGui
end
local gui = guiAny :: ScreenGui

-- Panel mittig
local panelAny = gui:FindFirstChild("Panel")
if not panelAny or not panelAny:IsA("Frame") then
    local newPanel = Instance.new("Frame")
    newPanel.Name = "Panel"
    newPanel.BackgroundTransparency = 0.2
    newPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    newPanel.BorderSizePixel = 0
    newPanel.AnchorPoint = Vector2.new(0.5, 0.5)
    newPanel.Position = UDim2.fromScale(0.5, 0.5)
    newPanel.Size = UDim2.fromOffset(360, 200)
    newPanel.Parent = gui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = newPanel
    panelAny = newPanel
end
local panel = panelAny :: Frame

local titleAny = panel:FindFirstChild("Title")
if not titleAny or not titleAny:IsA("TextLabel") then
    local t = Instance.new("TextLabel")
    t.Name = "Title"
    t.BackgroundTransparency = 1
    t.Text = "Lobby"
    t.TextColor3 = Color3.new(1, 1, 1)
    t.Font = Enum.Font.GothamBold
    t.TextScaled = true
    t.Size = UDim2.fromOffset(320, 40)
    t.Position = UDim2.fromOffset(20, 12)
    t.Parent = panel
    titleAny = t
end
local _title = titleAny :: TextLabel

local function makeButton(name: string, text: string, y: number, color: Color3): TextButton
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Text = text
    btn.Font = Enum.Font.GothamBold
    btn.TextScaled = true
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.BackgroundColor3 = color
    btn.Size = UDim2.fromOffset(320, 46)
    btn.Position = UDim2.fromOffset(20, y)
    btn.Parent = panel
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = btn
    return btn
end

local startBtnAny = panel:FindFirstChild("StartBtn")
local startBtn: TextButton
if startBtnAny and startBtnAny:IsA("TextButton") then
    startBtn = startBtnAny
else
    startBtn = makeButton("StartBtn", "Spiel starten", 70, Color3.fromRGB(60, 120, 255))
end

local respawnBtnAny = panel:FindFirstChild("RespawnBtn")
local respawnBtn: TextButton
if respawnBtnAny and respawnBtnAny:IsA("TextButton") then
    respawnBtn = respawnBtnAny
else
    respawnBtn = makeButton("RespawnBtn", "Respawn", 122, Color3.fromRGB(80, 180, 120))
end

local lobbyBtnAny = panel:FindFirstChild("LobbyBtn")
local lobbyBtn: TextButton
if lobbyBtnAny and lobbyBtnAny:IsA("TextButton") then
    lobbyBtn = lobbyBtnAny
else
    lobbyBtn = makeButton("LobbyBtn", "Zur Lobby", 174, Color3.fromRGB(100, 100, 100))
end

startBtn.MouseButton1Click:Connect(function()
    StartGame:FireServer()
end)

respawnBtn.MouseButton1Click:Connect(function()
    local character = player.Character
    if character then
        local hum = character:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.Health = 0
        else
            player:LoadCharacter()
        end
    else
        player:LoadCharacter()
    end
end)

lobbyBtn.MouseButton1Click:Connect(function()
    TeleportToLobby:FireServer()
end)

-- Optionale Direktbuttons (Queue/Arena) für manuelle Tests
local queueBtnAny = panel:FindFirstChild("QueueBtn")
local queueBtn: TextButton
if queueBtnAny and queueBtnAny:IsA("TextButton") then
    queueBtn = queueBtnAny
else
    queueBtn = makeButton("QueueBtn", "Zur Queue", 226, Color3.fromRGB(60, 200, 255))
end
queueBtn.MouseButton1Click:Connect(function()
    EnterQueue:FireServer()
end)

local arenaBtnAny = panel:FindFirstChild("ArenaBtn")
local arenaBtn: TextButton
if arenaBtnAny and arenaBtnAny:IsA("TextButton") then
    arenaBtn = arenaBtnAny
else
    arenaBtn = makeButton("ArenaBtn", "Zur Arena", 278, Color3.fromRGB(255, 100, 120))
end
arenaBtn.MouseButton1Click:Connect(function()
    EnterArena:FireServer()
end)
