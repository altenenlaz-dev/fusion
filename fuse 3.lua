-- Anime Dice: Weakest 3 Auto-Fuse
-- Features: skips locked/limited units, protects top 5 eligible units and placed units,
-- draggable UI, minimize/maximize, close, auto-fuse every 10 seconds, latest/best result,
-- and optional Anti-AFK toggle.
-- NOTE: This is an untested client-side script. Game module/remote schemas may differ.
-- The game server remains authoritative and can reject fusion requests.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local old = playerGui:FindFirstChild("WeakestFuseStandalone")
if old then old:Destroy() end

local Network = ReplicatedStorage:WaitForChild("Network")
local Framework = ReplicatedStorage:WaitForChild("Framework")

local function getPath(root, path)
    local node = root
    for part in string.gmatch(path, "[^%.]+") do
        node = node and node:FindFirstChild(part)
    end
    return node
end

local fuseRemote = getPath(Network, "FusingService.RE.Fuse")
local resultRemote = getPath(Network, "FusingService.RE.Result")
assert(fuseRemote, "FusingService.RE.Fuse was not found")
assert(resultRemote, "FusingService.RE.Result was not found")

local DataController = require(Framework.Features.Data.DataController)
local UnitConfig = require(Framework.Features.Inventory.Kinds.Unit.UnitConfig)

local function getData()
    return DataController.___X
end

local function baseIncome(unit)
    local def = unit and UnitConfig.entries[unit.name]
    if not def or type(def.income) ~= "function" then return 0 end
    local a = unit.attributes or {}
    local ok, value = pcall(def.income, {
        mutation = a.mutation,
        grade = a.grade,
        trait = a.trait,
        level = tonumber(a.level) or 1,
    })
    return ok and (tonumber(value) or 0) or 0
end

local function isFlagged(value)
    return value == true or value == 1 or value == "true"
end

local function isLocked(unit)
    local a = type(unit.attributes) == "table" and unit.attributes or {}
    return isFlagged(unit.locked) or isFlagged(unit.isLocked)
        or isFlagged(unit.Locked) or isFlagged(unit.IsLocked)
        or isFlagged(a.locked) or isFlagged(a.isLocked)
        or isFlagged(a.Locked) or isFlagged(a.IsLocked)
end

local function isLimited(unit)
    local a = type(unit.attributes) == "table" and unit.attributes or {}
    return isFlagged(unit.limited) or isFlagged(unit.isLimited)
        or isFlagged(unit.Limited) or isFlagged(unit.IsLimited)
        or isFlagged(a.limited) or isFlagged(a.isLimited)
        or isFlagged(a.Limited) or isFlagged(a.IsLimited)
end

local function getWeakestThree()
    local d = getData()
    assert(type(d) == "table" and type(d.Inventory) == "table", "Player inventory data is not ready")

    local protectedIds = {}
    for _, slot in pairs(d.Slots or {}) do
        if slot and slot.unitId then protectedIds[slot.unitId] = true end
    end
    for _, id in pairs(d.TowerTeam or {}) do protectedIds[id] = true end

    local eligible = {}
    for id, unit in pairs(d.Inventory) do
        if type(unit) == "table" and UnitConfig.entries[unit.name]
            and not isLocked(unit) and not isLimited(unit) then
            eligible[#eligible + 1] = { id = id, name = unit.name, value = baseIncome(unit) }
        end
    end
    table.sort(eligible, function(a, b) return a.value > b.value end)

    -- Protect the five strongest eligible units.
    for i = 1, math.min(5, #eligible) do
        protectedIds[eligible[i].id] = true
    end

    local candidates = {}
    for _, unit in ipairs(eligible) do
        if not protectedIds[unit.id] then candidates[#candidates + 1] = unit end
    end
    table.sort(candidates, function(a, b) return a.value < b.value end)

    local result = {}
    for i = 1, math.min(3, #candidates) do result[#result + 1] = candidates[i] end
    return result
end

local busy = false
local autoEnabled = false
local antiAfkEnabled = false
local bestValue = -math.huge
local bestText = "Best fused result: —"
local latestText = "Most recent fused result: —"
local resultConnection
local idledConnection
local inputChangedConnection
local inputEndedConnection

local gui = Instance.new("ScreenGui")
gui.Name = "WeakestFuseStandalone"
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "Panel"
frame.Size = UDim2.fromOffset(390, 330)
frame.Position = UDim2.new(0.5, -195, 0.62, -165)
frame.BackgroundColor3 = Color3.fromRGB(24, 27, 38)
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local topbar = Instance.new("Frame")
topbar.Name = "TitleBar"
topbar.Size = UDim2.new(1, 0, 0, 38)
topbar.BackgroundColor3 = Color3.fromRGB(35, 39, 54)
topbar.BorderSizePixel = 0
topbar.Active = true
topbar.Parent = frame
Instance.new("UICorner", topbar).CornerRadius = UDim.new(0, 10)
local topbarCover = Instance.new("Frame")
topbarCover.Size = UDim2.new(1, 0, 0, 10)
topbarCover.Position = UDim2.new(0, 0, 1, -10)
topbarCover.BackgroundColor3 = topbar.BackgroundColor3
topbarCover.BorderSizePixel = 0
topbarCover.Parent = topbar

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -110, 1, 0)
title.Position = UDim2.fromOffset(12, 0)
title.BackgroundTransparency = 1
title.Text = "WEAKEST 3 • AUTO FUSE"
title.TextColor3 = Color3.fromRGB(255, 213, 100)
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = topbar

local function makeTopButton(name, text, xOffset, color)
    local b = Instance.new("TextButton")
    b.Name = name
    b.Size = UDim2.fromOffset(28, 26)
    b.Position = UDim2.new(1, xOffset, 0, 6)
    b.BackgroundColor3 = color
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 16
    b.Text = text
    b.Parent = topbar
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end

local minimizeButton = makeTopButton("MinimizeButton", "−", -64, Color3.fromRGB(75, 82, 103))
local closeButton = makeTopButton("CloseButton", "×", -32, Color3.fromRGB(150, 55, 65))
local maximizeButton

local function makeLabel(name, text, y, height, color)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.Size = UDim2.new(1, -20, 0, height)
    label.Position = UDim2.fromOffset(10, y)
    label.BackgroundColor3 = Color3.fromRGB(32, 36, 49)
    label.BackgroundTransparency = 0.08
    label.BorderSizePixel = 0
    label.Text = text
    label.TextColor3 = color or Color3.fromRGB(235, 238, 245)
    label.Font = Enum.Font.Gotham
    label.TextSize = 11
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Parent = frame
    Instance.new("UICorner", label).CornerRadius = UDim.new(0, 7)
    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 8)
    padding.PaddingRight = UDim.new(0, 8)
    padding.Parent = label
    return label
end

local status = makeLabel("Status", "Ready. Manual fuse or turn Auto ON to run every 10 seconds.", 45, 48)
local latestDisplay = makeLabel("LatestResult", latestText, 99, 42, Color3.fromRGB(155, 225, 255))
local bestDisplay = makeLabel("BestResult", bestText, 147, 42, Color3.fromRGB(255, 213, 100))

local function makeActionButton(name, text, x, y, width, color)
    local b = Instance.new("TextButton")
    b.Name = name
    b.Size = UDim2.fromOffset(width, 36)
    b.Position = UDim2.fromOffset(x, y)
    b.BackgroundColor3 = color
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.Text = text
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    return b
end

local fuseButton = makeActionButton("FuseButton", "PREVIEW & FUSE", 10, 198, 180, Color3.fromRGB(190, 135, 45))
local autoButton = makeActionButton("AutoButton", "AUTO: OFF", 200, 198, 180, Color3.fromRGB(65, 105, 80))
local antiAfkButton = makeActionButton("AntiAfkButton", "ANTI-AFK: OFF", 10, 242, 180, Color3.fromRGB(75, 82, 103))
local clearInfoButton = makeActionButton("RefreshButton", "REFRESH STATUS", 200, 242, 180, Color3.fromRGB(75, 82, 103))

local minimized = false
local normalSize = UDim2.fromOffset(390, 330)
local minimizedSize = UDim2.fromOffset(205, 38)
local function setMinimized(value)
    minimized = value
    if minimized then
        frame.Size = minimizedSize
        for _, child in ipairs(frame:GetChildren()) do
            if child ~= topbar and child ~= topbarCover and child ~= title then child.Visible = false end
        end
        minimizeButton.Visible = false
        if not maximizeButton or not maximizeButton.Parent then
            maximizeButton = makeTopButton("MaximizeButton", "□", -64, Color3.fromRGB(75, 82, 103))
            maximizeButton.Activated:Connect(function() setMinimized(false) end)
        else
            maximizeButton.Visible = true
        end
        title.Text = "WEAKEST 3 • FUSE"
    else
        frame.Size = normalSize
        for _, child in ipairs(frame:GetChildren()) do child.Visible = true end
        minimizeButton.Visible = true
        if maximizeButton then maximizeButton.Visible = false end
        title.Text = "WEAKEST 3 • AUTO FUSE"
    end
end

local function refreshToggleLabels()
    autoButton.Text = autoEnabled and "AUTO: ON (10s)" or "AUTO: OFF"
    autoButton.BackgroundColor3 = autoEnabled and Color3.fromRGB(45, 145, 85) or Color3.fromRGB(65, 105, 80)
    antiAfkButton.Text = antiAfkEnabled and "ANTI-AFK: ON" or "ANTI-AFK: OFF"
    antiAfkButton.BackgroundColor3 = antiAfkEnabled and Color3.fromRGB(45, 145, 85) or Color3.fromRGB(75, 82, 103)
end

local function updateLatest(unit)
    local name = tostring(unit.name or "Unknown unit")
    local value = baseIncome(unit)
    local mutation = unit.attributes and unit.attributes.mutation
    latestText = string.format("Most recent fused result: %s | income %s%s", name, tostring(math.floor(value)), mutation and (" | " .. tostring(mutation)) or "")
    latestDisplay.Text = latestText
    if value > bestValue then
        bestValue = value
        bestText = string.format("Best fused result: %s | income %s%s", name, tostring(math.floor(value)), mutation and (" | " .. tostring(mutation)) or "")
        bestDisplay.Text = bestText
    end
end

local function setBusy(value)
    busy = value
    fuseButton.Text = value and "FUSING..." or "PREVIEW & FUSE"
    fuseButton.Active = not value
    fuseButton.AutoButtonColor = not value
end

local function attemptFusion(source)
    if busy or not gui.Parent then return end
    local ok, targets = pcall(getWeakestThree)
    if not ok then
        status.Text = "Could not read inventory: " .. tostring(targets)
        return
    end
    if #targets < 3 then
        status.Text = "Not enough eligible units. Need 3 unlocked, non-limited units after protecting the top 5 and placed units."
        return
    end

    local lines = {source .. ": selected 3 weakest eligible units:"}
    for i, unit in ipairs(targets) do
        lines[#lines + 1] = string.format("%d. %s | income %s", i, tostring(unit.name), tostring(math.floor(unit.value)))
    end
    status.Text = table.concat(lines, "\n") .. "\nSending fusion request..."

    local d = getData()
    for _, target in ipairs(targets) do
        local current = d and d.Inventory and d.Inventory[target.id]
        if not current or not UnitConfig.entries[current.name] or isLocked(current) or isLimited(current) then
            status.Text = "Inventory changed or a target became locked. Skipping this attempt."
            return
        end
    end

    setBusy(true)
    local sent, sendErr = pcall(function()
        fuseRemote:FireServer(targets[1].id, targets[2].id, targets[3].id)
    end)
    if not sent then
        setBusy(false)
        status.Text = "Could not send fusion request: " .. tostring(sendErr)
        return
    end

    task.delay(6, function()
        if busy and gui.Parent then
            setBusy(false)
            status.Text ..= "\nNo result event received yet; the server may still be processing or may have rejected it."
        end
    end)
end

resultConnection = resultRemote.OnClientEvent:Connect(function(unit, err, newId)
    if not busy then return end
    if type(unit) == "table" and unit.name then
        updateLatest(unit)
        status.Text = "Fusion successful: " .. tostring(unit.name)
    else
        status.Text = "Fusion rejected by server: " .. tostring(err or "No result received")
    end
    setBusy(false)
end)

fuseButton.Activated:Connect(function() attemptFusion("Manual fuse") end)
autoButton.Activated:Connect(function()
    autoEnabled = not autoEnabled
    refreshToggleLabels()
    if autoEnabled then
        status.Text = "Auto-fuse enabled. Attempting now, then every 10 seconds."
        task.spawn(function()
            while autoEnabled and gui.Parent do
                attemptFusion("Auto-fuse")
                for _ = 1, 100 do
                    if not autoEnabled or not gui.Parent then break end
                    task.wait(0.1)
                end
            end
        end)
    else
        status.Text = "Auto-fuse disabled."
    end
end)

antiAfkButton.Activated:Connect(function()
    antiAfkEnabled = not antiAfkEnabled
    if antiAfkEnabled then
        if not idledConnection then
            idledConnection = player.Idled:Connect(function()
                if antiAfkEnabled and gui.Parent then
                    pcall(function()
                        VirtualUser:CaptureController()
                        VirtualUser:ClickButton2(Vector2.new(0, 0))
                    end)
                end
            end)
        end
        status.Text = "Anti-AFK enabled. It responds to the player's idle event when supported."
    else
        status.Text = "Anti-AFK disabled."
    end
    refreshToggleLabels()
end)

clearInfoButton.Activated:Connect(function()
    status.Text = string.format("Status: %s | Auto: %s | Anti-AFK: %s", busy and "Fusing" or "Ready", autoEnabled and "ON" or "OFF", antiAfkEnabled and "ON" or "OFF")
end)

minimizeButton.Activated:Connect(function() setMinimized(true) end)
closeButton.Activated:Connect(function()
    autoEnabled = false
    antiAfkEnabled = false
    if resultConnection then resultConnection:Disconnect() end
    if idledConnection then idledConnection:Disconnect() end
    if inputChangedConnection then inputChangedConnection:Disconnect() end
    if inputEndedConnection then inputEndedConnection:Disconnect() end
    gui:Destroy()
end)

-- Drag by title bar; mouse and touch supported.
local dragging = false
local dragInput
local dragStart
local startPosition
local function beginDrag(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
    dragging = true
    dragStart = input.Position
    startPosition = frame.Position
    dragInput = input
end

topbar.InputBegan:Connect(beginDrag)
title.InputBegan:Connect(beginDrag)
inputChangedConnection = UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
    end
end)
inputEndedConnection = UserInputService.InputEnded:Connect(function(input)
    if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
        dragInput = nil
    end
end)

refreshToggleLabels()
