--!strict
-- Klassenauswahl-UI für Arena RPG

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ClassSystem = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ClassSystem"))
type ClassData = {
    Name: string,
    Description: string,
    Icon: string,
    Color: Color3,
    [string]: any,
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local EnterQueue = Remotes:WaitForChild("EnterQueue") :: RemoteEvent
local QueueStatus = Remotes:WaitForChild("QueueStatus") :: RemoteEvent

-- UI-Variablen
local gui: ScreenGui
local mainFrame: Frame
local classButtons: { [string]: TextButton } = {}
local selectedClass: string = "MeleeDPS"
local queueButton: TextButton
local statusLabel: TextLabel

-- Funktionsdefinitionen
local function selectClass(className: string)
    selectedClass = className

    -- Update Button-Styles
    for name, button in pairs(classButtons) do
        local selectionBorder = button:FindFirstChild("SelectionBorder") :: Frame?
        if selectionBorder then
            selectionBorder.Visible = (name == selectedClass)
        end
    end

    -- Update Queue-Button Text
    if queueButton then
        queueButton.Text = string.format("🎯 Als %s beitreten", (ClassSystem.CLASSES :: any)[selectedClass].Name)
    end

    print(string.format("[ClassSelection] Selected class: %s", selectedClass))
end

local function onQueueButtonClick()
    local level = player:GetAttribute("Level") or 1
    EnterQueue:FireServer(selectedClass, level)

    -- Update UI
    queueButton.Text = "⏳ In Queue..."
    queueButton.BackgroundColor3 = Color3.fromRGB(150, 150, 50)
    statusLabel.Text = "Suche nach Match..."
end

local function createClassButtons(parent: Frame)
    for className, classData in pairs(ClassSystem.CLASSES :: any) do
        local button = Instance.new("TextButton")
        button.Name = (className :: string) .. "Button"
        button.BackgroundColor3 = classData.Color
        button.BorderSizePixel = 0
        button.Text = ""
        button.Parent = parent

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 12)
        corner.Parent = button

        -- Icon
        local icon = Instance.new("TextLabel")
        icon.Name = "Icon"
        icon.Size = UDim2.fromScale(1, 0.3)
        icon.Position = UDim2.fromScale(0, 0.05)
        icon.BackgroundTransparency = 1
        icon.Text = classData.Icon
        icon.TextColor3 = Color3.fromRGB(255, 255, 255)
        icon.TextScaled = true
        icon.Font = Enum.Font.GothamBold
        icon.Parent = button

        -- Name
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "ClassName"
        nameLabel.Size = UDim2.fromScale(0.9, 0.15)
        nameLabel.Position = UDim2.fromScale(0.05, 0.38)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = classData.Name
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameLabel.TextScaled = true
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.Parent = button

        -- Beschreibung
        local description = Instance.new("TextLabel")
        description.Name = "Description"
        description.Size = UDim2.fromScale(0.9, 0.4)
        description.Position = UDim2.fromScale(0.05, 0.55)
        description.BackgroundTransparency = 1
        description.Text = classData.Description
        description.TextColor3 = Color3.fromRGB(240, 240, 240)
        description.TextScaled = true
        description.TextWrapped = true
        description.Font = Enum.Font.Gotham
        description.Parent = button

        -- Selection Border (initially hidden)
        local selectionBorder = Instance.new("Frame")
        selectionBorder.Name = "SelectionBorder"
        selectionBorder.Size = UDim2.fromScale(1, 1)
        selectionBorder.Position = UDim2.fromScale(0, 0)
        selectionBorder.BackgroundTransparency = 1
        selectionBorder.BorderSizePixel = 4
        selectionBorder.BorderColor3 = Color3.fromRGB(255, 255, 100)
        selectionBorder.Visible = false
        selectionBorder.Parent = button

        local selectionCorner = Instance.new("UICorner")
        selectionCorner.CornerRadius = UDim.new(0, 12)
        selectionCorner.Parent = selectionBorder

        -- Click-Event
        button.MouseButton1Click:Connect(function()
            selectClass(className :: string)
        end)

        -- Hover-Effekte
        button.MouseEnter:Connect(function()
            local tween = TweenService:Create(
                button,
                TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { Size = UDim2.fromScale(1.05, 1.05) }
            )
            tween:Play()
        end)

        button.MouseLeave:Connect(function()
            local tween = TweenService:Create(
                button,
                TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { Size = UDim2.fromScale(1, 1) }
            )
            tween:Play()
        end)

        classButtons[className :: string] = button
    end

    -- Initial-Auswahl
    selectClass(selectedClass)
end

-- UI-Setup
local function createUI()
    -- Haupt-GUI
    gui = Instance.new("ScreenGui")
    gui.Name = "ClassSelectionUI"
    gui.ResetOnSpawn = false
    gui.Parent = playerGui

    -- Haupt-Panel
    mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.fromScale(0.8, 0.7)
    mainFrame.Position = UDim2.fromScale(0.1, 0.15)
    mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 15)
    corner.Parent = mainFrame

    -- Titel
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.fromScale(1, 0.12)
    title.Position = UDim2.fromScale(0, 0)
    title.BackgroundTransparency = 1
    title.Text = "🏟️ Wähle deine Klasse"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.Parent = mainFrame

    -- Klassen-Container
    local classContainer = Instance.new("Frame")
    classContainer.Name = "ClassContainer"
    classContainer.Size = UDim2.fromScale(0.95, 0.65)
    classContainer.Position = UDim2.fromScale(0.025, 0.15)
    classContainer.BackgroundTransparency = 1
    classContainer.Parent = mainFrame

    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.CellSize = UDim2.fromScale(0.3, 0.45)
    gridLayout.CellPadding = UDim2.fromScale(0.05, 0.05)
    gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    gridLayout.VerticalAlignment = Enum.VerticalAlignment.Top
    gridLayout.Parent = classContainer

    -- Erstelle Klassen-Buttons

    createClassButtons(classContainer)

    -- Queue-Button
    queueButton = Instance.new("TextButton")
    queueButton.Name = "QueueButton"
    queueButton.Size = UDim2.fromScale(0.4, 0.08)
    queueButton.Position = UDim2.fromScale(0.1, 0.85)
    queueButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
    queueButton.Text = "🎯 Queue beitreten"
    queueButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    queueButton.TextScaled = true
    queueButton.Font = Enum.Font.GothamBold
    queueButton.Parent = mainFrame

    local queueCorner = Instance.new("UICorner")
    queueCorner.CornerRadius = UDim.new(0, 8)
    queueCorner.Parent = queueButton

    -- Status-Label
    statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "StatusLabel"
    statusLabel.Size = UDim2.fromScale(0.45, 0.08)
    statusLabel.Position = UDim2.fromScale(0.52, 0.85)
    statusLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    statusLabel.Text = "Bereit zum Spielen"
    statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    statusLabel.TextScaled = true
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.Parent = mainFrame

    local statusCorner = Instance.new("UICorner")
    statusCorner.CornerRadius = UDim.new(0, 8)
    statusCorner.Parent = statusLabel

    -- Event-Verbindungen
    queueButton.MouseButton1Click:Connect(onQueueButtonClick)
end

-- Queue-Status Updates
QueueStatus.OnClientEvent:Connect(function(status: { inQueue: boolean, position: number, estimatedWait: number })
    if status.inQueue then
        statusLabel.Text = string.format("Position: %d | ~%ds", status.position, math.floor(status.estimatedWait))
    else
        statusLabel.Text = "Bereit zum Spielen"
        queueButton.Text = string.format("🎯 Als %s beitreten", (ClassSystem.CLASSES :: any)[selectedClass].Name)
        queueButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
    end
end)

-- UI verstecken wenn in Arena
game:GetService("RunService").Heartbeat:Connect(function()
    local inArena = player:GetAttribute("InArena") or false
    if gui then
        gui.Enabled = not inArena
    end
end)

-- Initialize UI
createUI()

print("[ClassSelection] Class selection UI loaded")
