--!strict
-- Constructs a simple HUD at runtime (to avoid manual UI work)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
-- HUD-Client hält eine Singleton-Instanz am Leben (Attribut EndlessHUD) und zerstört Duplikate bei Respawn
local playerGui = player:WaitForChild("PlayerGui")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RestartRequest = Remotes:WaitForChild("RestartRequest") :: RemoteEvent
local ShopPurchaseRequest = Remotes:FindFirstChild("ShopPurchaseRequest") :: RemoteEvent?
local ShopResult = Remotes:FindFirstChild("ShopResult") :: RemoteEvent?
local EventAnnounce = Remotes:FindFirstChild("EventAnnounce") :: RemoteEvent?

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

-- Theme & autoscale helpers
local Theme = {
    Bg = Color3.fromRGB(20, 20, 20),
    Bg2 = Color3.fromRGB(30, 30, 30),
    Acc = Color3.fromRGB(60, 120, 255),
    Acc2 = Color3.fromRGB(60, 80, 60),
    Text = Color3.new(1, 1, 1),
}

local function applyTheme(highContrast: boolean)
    if highContrast then
        Theme.Bg = Color3.fromRGB(15, 15, 15)
        Theme.Bg2 = Color3.fromRGB(25, 25, 25)
        Theme.Acc = Color3.fromRGB(40, 90, 200) -- dunkler für besseren Kontrast
        Theme.Acc2 = Color3.fromRGB(50, 90, 50)
        Theme.Text = Color3.new(1, 1, 1)
    else
        Theme.Bg = Color3.fromRGB(20, 20, 20)
        Theme.Bg2 = Color3.fromRGB(30, 30, 30)
        Theme.Acc = Color3.fromRGB(60, 120, 255)
        Theme.Acc2 = Color3.fromRGB(60, 80, 60)
        Theme.Text = Color3.new(1, 1, 1)
    end
end

local function viewportScale(): number
    local cam = workspace.CurrentCamera
    local h = cam and cam.ViewportSize.Y or 720
    local base = 720
    local s = h / base
    if s < 0.85 then
        s = 0.85
    elseif s > 1.25 then
        s = 1.25
    end
    return s
end

local function ensureUICorner(inst: Instance, radius: number)
    local corner = (inst :: Instance):FindFirstChildOfClass("UICorner")
    if not corner then
        corner = Instance.new("UICorner")
        corner.Parent = inst
    end
    corner.CornerRadius = UDim.new(0, radius)
end

local function ensureUIStroke(inst: Instance, thickness: number, color: Color3)
    local stroke = (inst :: Instance):FindFirstChildOfClass("UIStroke")
    if not stroke then
        stroke = Instance.new("UIStroke")
        stroke.Parent = inst
    end
    stroke.Thickness = thickness
    stroke.Color = color
    stroke.Transparency = 0.25
end

local function styleLabel(lbl: TextLabel, size: Vector2, pos: Vector2, sf: number)
    lbl.BackgroundTransparency = 0.25
    lbl.BackgroundColor3 = Theme.Bg
    lbl.BorderSizePixel = 0
    lbl.TextColor3 = Theme.Text
    lbl.Font = Enum.Font.GothamBold
    lbl.TextScaled = true
    lbl.Size = UDim2.fromOffset(math.floor(size.X * sf + 0.5), math.floor(size.Y * sf + 0.5))
    lbl.Position = UDim2.fromOffset(math.floor(pos.X * sf + 0.5), math.floor(pos.Y * sf + 0.5))
    lbl.TextStrokeTransparency = 0.6
    ensureUICorner(lbl, math.floor(6 * sf + 0.5))
    ensureUIStroke(lbl, math.max(1, math.floor(1 * sf + 0.5)), Color3.fromRGB(0, 0, 0))
end

local function styleButton(btn: TextButton, size: Vector2, pos: Vector2, sf: number, color: Color3)
    btn.BackgroundColor3 = color
    btn.TextColor3 = Theme.Text
    btn.Font = Enum.Font.GothamBold
    btn.TextScaled = true
    btn.Size = UDim2.fromOffset(math.floor(size.X * sf + 0.5), math.floor(size.Y * sf + 0.5))
    btn.Position = UDim2.fromOffset(math.floor(pos.X * sf + 0.5), math.floor(pos.Y * sf + 0.5))
    ensureUICorner(btn, math.floor(6 * sf + 0.5))
    ensureUIStroke(btn, math.max(1, math.floor(1 * sf + 0.5)), Color3.fromRGB(0, 0, 0))
end

local function stylePanel(frame: Frame, size: Vector2, sf: number, bg: Color3)
    frame.BackgroundTransparency = 0.15
    frame.BackgroundColor3 = bg
    frame.BorderSizePixel = 0
    frame.Size = UDim2.fromOffset(math.floor(size.X * sf + 0.5), math.floor(size.Y * sf + 0.5))
    ensureUICorner(frame, math.floor(10 * sf + 0.5))
    ensureUIStroke(frame, math.max(1, math.floor(1 * sf + 0.5)), Color3.fromRGB(0, 0, 0))
end

-- forward declaration to allow references before definition (Selene-friendly)
-- restylePanels defined below after toast creation

-- Label factory
local function makeLabel(name: string, pos: UDim2): TextLabel
    local lbl = Instance.new("TextLabel")
    lbl.Name = name
    -- Details werden später durch styleLabel gesetzt
    lbl.BackgroundTransparency = 0.25
    lbl.BackgroundColor3 = Theme.Bg
    lbl.BorderSizePixel = 0
    lbl.TextColor3 = Theme.Text
    lbl.Font = Enum.Font.GothamBold
    lbl.TextScaled = true
    lbl.Size = UDim2.fromOffset(160, 40)
    lbl.Position = pos
    lbl.Parent = gui
    return lbl
end

-- Create labels if missing and set initial text
local distanceLbl = (gui :: ScreenGui):FindFirstChild("Distance") :: TextLabel?
if not distanceLbl then
    distanceLbl = makeLabel("Distance", UDim2.fromOffset(20, 20))
end
distanceLbl.Text = "0m"

local coinsLbl = (gui :: ScreenGui):FindFirstChild("Coins") :: TextLabel?
if not coinsLbl then
    coinsLbl = makeLabel("Coins", UDim2.fromOffset(20, 70))
end
coinsLbl.Text = "0"

local speedLbl = (gui :: ScreenGui):FindFirstChild("Speed") :: TextLabel?
if not speedLbl then
    speedLbl = makeLabel("Speed", UDim2.fromOffset(20, 120))
end
speedLbl.Text = "0"

-- optionale Powerup-Anzeigen
local magnetLbl = (gui :: ScreenGui):FindFirstChild("Magnet") :: TextLabel?
if not magnetLbl then
    magnetLbl = makeLabel("Magnet", UDim2.fromOffset(20, 170))
end
magnetLbl.Text = ""

local shieldLbl = (gui :: ScreenGui):FindFirstChild("Shield") :: TextLabel?
if not shieldLbl then
    shieldLbl = makeLabel("Shield", UDim2.fromOffset(20, 220))
end
shieldLbl.Text = ""

local eventLbl = (gui :: ScreenGui):FindFirstChild("Event") :: TextLabel?
if not eventLbl then
    eventLbl = makeLabel("Event", UDim2.fromOffset(20, 270))
end
eventLbl.Text = ""

print("[HUD] Labels initialized: Distance/Coins/Speed")

-- Initial styling & autoscale application
local function restyle()
    local sf = viewportScale()
    styleLabel(distanceLbl :: TextLabel, Vector2.new(170, 40), Vector2.new(20, 20), sf)
    styleLabel(coinsLbl :: TextLabel, Vector2.new(170, 40), Vector2.new(20, 70), sf)
    styleLabel(speedLbl :: TextLabel, Vector2.new(170, 40), Vector2.new(20, 120), sf)
    styleLabel(magnetLbl :: TextLabel, Vector2.new(170, 40), Vector2.new(20, 170), sf)
    styleLabel(shieldLbl :: TextLabel, Vector2.new(170, 40), Vector2.new(20, 220), sf)
    styleLabel(eventLbl :: TextLabel, Vector2.new(220, 40), Vector2.new(20, 270), sf)
end
restyle()

-- Simple top-right button bar (Menu, Shop)
local topBar = (gui :: ScreenGui):FindFirstChild("TopBar") :: Frame?
if not topBar then
    topBar = Instance.new("Frame")
    topBar.Name = "TopBar"
    topBar.BackgroundTransparency = 1
    topBar.Size = UDim2.fromOffset(240, 44)
    topBar.AnchorPoint = Vector2.new(1, 0)
    topBar.Position = UDim2.fromScale(1, 0)
    topBar.Parent = gui
end

local function makeButton(name: string, text: string, xOffset: number): TextButton
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Text = text
    btn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 18
    btn.AutoButtonColor = true
    btn.Size = UDim2.fromOffset(110, 36)
    btn.Position = UDim2.fromOffset(xOffset, 4)
    btn.Parent = topBar :: Frame
    return btn
end

local menuBtn = (topBar :: Frame):FindFirstChild("MenuButton") :: TextButton?
if not menuBtn then
    menuBtn = makeButton("MenuButton", "Menü", 120)
end

local shopBtn = (topBar :: Frame):FindFirstChild("ShopButton") :: TextButton?
if not shopBtn then
    shopBtn = makeButton("ShopButton", "Shop", 4)
end

-- Menu panel
local menuPanel = (gui :: ScreenGui):FindFirstChild("MenuPanel") :: Frame?
if not menuPanel then
    menuPanel = Instance.new("Frame")
    menuPanel.Name = "MenuPanel"
    menuPanel.BackgroundTransparency = 0.15
    menuPanel.BackgroundColor3 = Theme.Bg
    menuPanel.BorderSizePixel = 0
    menuPanel.AnchorPoint = Vector2.new(0.5, 0.5)
    menuPanel.Position = UDim2.fromScale(0.5, 0.5)
    menuPanel.Size = UDim2.fromOffset(320, 200)
    menuPanel.Visible = false
    menuPanel.Parent = gui

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.BackgroundTransparency = 1
    title.Text = "Hauptmenü"
    title.Font = Enum.Font.GothamBold
    title.TextScaled = true
    title.TextColor3 = Color3.new(1, 1, 1)
    title.Size = UDim2.fromOffset(300, 40)
    title.Position = UDim2.fromOffset(10, 10)
    title.Parent = menuPanel

    local restartBtn = Instance.new("TextButton")
    restartBtn.Name = "Restart"
    restartBtn.Text = "Restart"
    restartBtn.Font = Enum.Font.GothamBold
    restartBtn.TextScaled = true
    restartBtn.TextColor3 = Color3.new(1, 1, 1)
    restartBtn.BackgroundColor3 = Theme.Bg2
    restartBtn.Size = UDim2.fromOffset(300, 44)
    restartBtn.Position = UDim2.fromOffset(10, 70)
    restartBtn.Parent = menuPanel

    restartBtn.MouseButton1Click:Connect(function()
        RestartRequest:FireServer()
        menuPanel.Visible = false
    end)

    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "Close"
    closeBtn.Text = "Schließen"
    closeBtn.Font = Enum.Font.Gotham
    closeBtn.TextScaled = true
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.BackgroundColor3 = Theme.Bg2
    closeBtn.Size = UDim2.fromOffset(300, 36)
    closeBtn.Position = UDim2.fromOffset(10, 130)
    closeBtn.Parent = menuPanel
    closeBtn.MouseButton1Click:Connect(function()
        menuPanel.Visible = false
    end)

    -- Accessibility: Toggle Panel
    local accBtn = Instance.new("TextButton")
    accBtn.Name = "Accessibility"
    accBtn.Text = "Barrierefreiheit"
    accBtn.Font = Enum.Font.Gotham
    accBtn.TextScaled = true
    accBtn.TextColor3 = Theme.Text
    accBtn.BackgroundColor3 = Theme.Bg2
    accBtn.Size = UDim2.fromOffset(300, 36)
    accBtn.Position = UDim2.fromOffset(10, 170)
    accBtn.Parent = menuPanel

    accBtn.MouseButton1Click:Connect(function()
        local acc = gui:FindFirstChild("AccessibilityPanel") :: Frame?
        if acc then
            acc.Visible = not acc.Visible
        end
    end)
end

menuBtn.MouseButton1Click:Connect(function()
    menuPanel.Visible = not menuPanel.Visible
end)

-- Shop panel
local shopPanel = (gui :: ScreenGui):FindFirstChild("ShopPanel") :: Frame?
if not shopPanel then
    shopPanel = Instance.new("Frame")
    shopPanel.Name = "ShopPanel"
    shopPanel.BackgroundTransparency = 0.15
    shopPanel.BackgroundColor3 = Theme.Bg
    shopPanel.BorderSizePixel = 0
    shopPanel.AnchorPoint = Vector2.new(0.5, 0.5)
    shopPanel.Position = UDim2.fromScale(0.5, 0.5)
    shopPanel.Size = UDim2.fromOffset(340, 230)
    shopPanel.Visible = false
    shopPanel.Parent = gui

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.BackgroundTransparency = 1
    title.Text = "Shop"
    title.Font = Enum.Font.GothamBold
    title.TextScaled = true
    title.TextColor3 = Color3.fromRGB(220, 255, 220)
    title.Size = UDim2.fromOffset(320, 40)
    title.Position = UDim2.fromOffset(10, 10)
    title.Parent = shopPanel

    local item1 = Instance.new("TextLabel")
    item1.Name = "ItemShield"
    item1.BackgroundTransparency = 0.25
    item1.BackgroundColor3 = Theme.Bg2
    item1.Text = "+1 Schild (5 Coins)"
    item1.Font = Enum.Font.Gotham
    item1.TextScaled = true
    item1.TextColor3 = Color3.fromRGB(220, 255, 220)
    item1.Size = UDim2.fromOffset(210, 44)
    item1.Position = UDim2.fromOffset(10, 70)
    item1.Parent = shopPanel

    local buy1 = Instance.new("TextButton")
    buy1.Name = "BuyShield"
    buy1.Text = "Kaufen"
    buy1.Font = Enum.Font.GothamBold
    buy1.TextScaled = true
    buy1.TextColor3 = Color3.new(1, 1, 1)
    buy1.BackgroundColor3 = Theme.Acc2
    buy1.Size = UDim2.fromOffset(100, 44)
    buy1.Position = UDim2.fromOffset(230, 70)
    buy1.Parent = shopPanel

    buy1.MouseButton1Click:Connect(function()
        if ShopPurchaseRequest then
            ShopPurchaseRequest:FireServer({ item = "Shield1" })
        end
    end)

    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "Close"
    closeBtn.Text = "Schließen"
    closeBtn.Font = Enum.Font.Gotham
    closeBtn.TextScaled = true
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.BackgroundColor3 = Theme.Bg2
    closeBtn.Size = UDim2.fromOffset(320, 36)
    closeBtn.Position = UDim2.fromOffset(10, 130)
    closeBtn.Parent = shopPanel
    closeBtn.MouseButton1Click:Connect(function()
        shopPanel.Visible = false
    end)
end

shopBtn.MouseButton1Click:Connect(function()
    shopPanel.Visible = not shopPanel.Visible
end)

-- Lightweight toast for shop results
local toast = (gui :: ScreenGui):FindFirstChild("Toast") :: TextLabel?
if not toast then
    toast = Instance.new("TextLabel")
    toast.Name = "Toast"
    toast.BackgroundTransparency = 0.2
    toast.BackgroundColor3 = Theme.Bg
    toast.TextColor3 = Theme.Text
    toast.Font = Enum.Font.GothamBold
    toast.TextScaled = true
    toast.Size = UDim2.fromOffset(340, 40)
    toast.AnchorPoint = Vector2.new(0.5, 1)
    toast.Position = UDim2.fromScale(0.5, 1)
    toast.Visible = false
    toast.Parent = gui
end

local function showToast(msg: string)
    toast.Text = msg
    toast.Visible = true
    task.delay(1.5, function()
        if toast then
            toast.Visible = false
        end
    end)
end

-- Apply rounded corners and strokes to panels and toast; style buttons using autoscale
local function restylePanels()
    local sf = viewportScale()
    stylePanel(menuPanel :: Frame, Vector2.new(320, 200), sf, Theme.Bg)
    stylePanel(shopPanel :: Frame, Vector2.new(340, 230), sf, Theme.Bg)
    ensureUICorner(toast :: TextLabel, math.floor(8 * sf + 0.5))
    ensureUIStroke(toast :: TextLabel, math.max(1, math.floor(1 * sf + 0.5)), Color3.fromRGB(0, 0, 0))
    -- Buttons positions/sizes remain as originally set; just ensure consistent styling
    styleButton(menuBtn :: TextButton, Vector2.new(110, 36), Vector2.new(120, 4), sf, Theme.Bg2)
    styleButton(shopBtn :: TextButton, Vector2.new(110, 36), Vector2.new(4, 4), sf, Theme.Acc)
end

restylePanels()

-- Accessibility Panel (hidden by default)
local accPanel = (gui :: ScreenGui):FindFirstChild("AccessibilityPanel") :: Frame?
if not accPanel then
    accPanel = Instance.new("Frame")
    accPanel.Name = "AccessibilityPanel"
    accPanel.BackgroundTransparency = 0.15
    accPanel.BackgroundColor3 = Theme.Bg
    accPanel.BorderSizePixel = 0
    accPanel.AnchorPoint = Vector2.new(1, 1)
    accPanel.Position = UDim2.fromScale(1, 1)
    accPanel.Size = UDim2.fromOffset(260, 120)
    accPanel.Visible = false
    accPanel.Parent = gui

    ensureUICorner(accPanel, 8)
    ensureUIStroke(accPanel, 1, Color3.fromRGB(0, 0, 0))

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.BackgroundTransparency = 1
    title.Text = "Barrierefreiheit"
    title.Font = Enum.Font.GothamBold
    title.TextScaled = true
    title.TextColor3 = Theme.Text
    title.Size = UDim2.fromOffset(240, 24)
    title.Position = UDim2.fromOffset(10, 6)
    title.Parent = accPanel

    local highContrast = Instance.new("TextButton")
    highContrast.Name = "HighContrast"
    highContrast.Text = "Hoher Kontrast: AUS"
    highContrast.Font = Enum.Font.Gotham
    highContrast.TextScaled = true
    highContrast.TextColor3 = Theme.Text
    highContrast.BackgroundColor3 = Theme.Bg2
    highContrast.Size = UDim2.fromOffset(240, 36)
    highContrast.Position = UDim2.fromOffset(10, 40)
    highContrast.Parent = accPanel

    local effects = Instance.new("TextButton")
    effects.Name = "Effects"
    effects.Text = "Effekte: AN"
    effects.Font = Enum.Font.Gotham
    effects.TextScaled = true
    effects.TextColor3 = Theme.Text
    effects.BackgroundColor3 = Theme.Bg2
    effects.Size = UDim2.fromOffset(240, 36)
    effects.Position = UDim2.fromOffset(10, 80)
    effects.Parent = accPanel

    -- Initialize attributes on PlayerGui (acts as simple client-side store)
    if playerGui:GetAttribute("HighContrast") == nil then
        playerGui:SetAttribute("HighContrast", false)
    end
    if playerGui:GetAttribute("EffectsEnabled") == nil then
        playerGui:SetAttribute("EffectsEnabled", true)
    end

    local function syncButtons()
        local hc = playerGui:GetAttribute("HighContrast") == true
        local fx = playerGui:GetAttribute("EffectsEnabled") ~= false
        highContrast.Text = hc and "Hoher Kontrast: AN" or "Hoher Kontrast: AUS"
        effects.Text = fx and "Effekte: AN" or "Effekte: AUS"
        applyTheme(hc)
        -- restyle full HUD on theme change
        restyle()
        restylePanels()
        -- toast colors follow theme
        if toast then
            toast.BackgroundColor3 = Theme.Bg
            toast.TextColor3 = Theme.Text
        end
    end

    highContrast.MouseButton1Click:Connect(function()
        playerGui:SetAttribute("HighContrast", not (playerGui:GetAttribute("HighContrast") == true))
        syncButtons()
    end)
    effects.MouseButton1Click:Connect(function()
        playerGui:SetAttribute("EffectsEnabled", not (playerGui:GetAttribute("EffectsEnabled") ~= false))
        syncButtons()
    end)

    syncButtons()
end

-- restylePanels defined earlier (see after toast creation)

-- Recompute on viewport changes (lightweight)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    local cam = workspace.CurrentCamera
    if not cam then
        return
    end
    cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        restyle()
        restylePanels()
    end)
end)

if ShopResult then
    ShopResult.OnClientEvent:Connect(function(result)
        if not result then
            return
        end
        local ok = (result.ok == true)
        local msg = ok and "Gekauft!" or (result.reason or "Fehlgeschlagen")
        showToast(msg)
    end)
end

-- Optional: show brief toast when an event starts
if EventAnnounce then
    EventAnnounce.OnClientEvent:Connect(function(info)
        if not info then
            return
        end
        if info.kind == "DoubleCoins" then
            local eventToast = (gui :: ScreenGui):FindFirstChild("EventToast") :: TextLabel?
            if not eventToast then
                eventToast = Instance.new("TextLabel")
                eventToast.Name = "EventToast"
                eventToast.BackgroundTransparency = 0.2
                eventToast.BackgroundColor3 = Color3.fromRGB(35, 80, 35)
                eventToast.TextColor3 = Theme.Text
                eventToast.Font = Enum.Font.GothamBold
                eventToast.TextScaled = true
                eventToast.Size = UDim2.fromOffset(320, 40)
                eventToast.AnchorPoint = Vector2.new(0.5, 0)
                eventToast.Position = UDim2.fromScale(0.5, 0.05)
                eventToast.Visible = false
                eventToast.Parent = gui
            end
            eventToast.Text = "Event: Double Coins!"
            eventToast.Visible = true
            task.delay(2.0, function()
                if eventToast and eventToast.Parent then
                    eventToast.Visible = false
                end
            end)
        end
    end)
end
