-- Anime Dice: Preview & Fuse 3 Weakest
-- Standalone client-side button script.
-- Skips locked/limited units, protects the 5 strongest eligible units and all placed/Tower Team units.
-- UI supports dragging, minimizing/restoring, and closing.
-- Ignores local budget and balance checks. The server may still reject a fusion
-- for its own validation, money requirements, cooldown, or fusion rules.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
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
        level = 1,
    })
    return ok and (tonumber(value) or 0) or 0
end

local function isFlagged(value)
    return value == true or value == 1 or value == "true"
end

local function isLocked(unit)
    local attributes = type(unit.attributes) == "table" and unit.attributes or {}
    -- Check common inventory schemas for a lock flag. A missing flag is treated
    -- as unlocked; the server remains authoritative if the game uses another schema.
    return isFlagged(unit.locked) or isFlagged(unit.isLocked)
        or isFlagged(unit.Locked) or isFlagged(unit.IsLocked)
        or isFlagged(attributes.locked) or isFlagged(attributes.isLocked)
        or isFlagged(attributes.Locked) or isFlagged(attributes.IsLocked)
end

local function isLimited(unit)
    local attributes = type(unit.attributes) == "table" and unit.attributes or {}
    return isFlagged(unit.limited) or isFlagged(unit.isLimited)
        or isFlagged(unit.Limited) or isFlagged(unit.IsLimited)
        or isFlagged(attributes.limited) or isFlagged(attributes.isLimited)
        or isFlagged(attributes.Limited) or isFlagged(attributes.IsLimited)
end

local function getWeakestThree()
    local d = getData()
    assert(type(d) == "table" and type(d.Inventory) == "table",
        "Player inventory data is not ready")

    local protectedIds = {}
    for _, slot in pairs(d.Slots or {}) do
        if slot and slot.unitId then protectedIds[slot.unitId] = true end
    end
    for _, id in pairs(d.TowerTeam or {}) do
        protectedIds[id] = true
    end

    -- Locked/limited units are omitted entirely; they do not count toward the
    -- five strongest units protected from fusion.
    local eligible = {}
    for id, unit in pairs(d.Inventory) do
        if type(unit) == "table" and UnitConfig.entries[unit.name]
            and not isLocked(unit) and not isLimited(unit) then
            eligible[#eligible + 1] = { id = id, name = unit.name, value = baseIncome(unit) }
        end
    end
    table.sort(eligible, function(a, b) return a.value > b.value end)

    -- Protect the five strongest eligible (unlocked, non-limited) units.
    for i = 1, math.min(5, #eligible) do
        protectedIds[eligible[i].id] = true
    end

    local candidates = {}
    for _, unit in ipairs(eligible) do
        if not protectedIds[unit.id] then
            candidates[#candidates + 1] = unit
        end
    end
    table.sort(candidates, function(a, b) return a.value < b.value end)

    local result = {}
    for i = 1, math.min(3, #candidates) do
        result[#result + 1] = candidates[i]
    end
    return result
end

local busy = false
local resultConnection

local gui = Instance.new("ScreenGui")
gui.Name = "WeakestFuseStandalone"
gui.ResetOnSpawn = false
gui.Parent = playerGui

gui.DisplayOrder = 100

local frame = Instance.new("Frame")
frame.Name = "Panel"
frame.Size = UDim2.fromOffset(360, 205)
frame.Position = UDim2.new(0.5, -180, 0.72, -102)
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

-- A small cover hides the title bar's rounded bottom corners.
local topbarCover = Instance.new("Frame")
topbarCover.Size = UDim2.new(1, 0, 0, 10)
topbarCover.Position = UDim2.new(0, 0, 1, -10)
topbarCover.BackgroundColor3 = topbar.BackgroundColor3
topbarCover.BorderSizePixel = 0
topbarCover.Parent = topbar

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -100, 1, 0)
title.Position = UDim2.fromOffset(12, 0)
title.BackgroundTransparency = 1
title.Text = "WEAKEST 3 • FUSE"
title.TextColor3 = Color3.fromRGB(255, 213, 100)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = topbar

local function makeTopButton(name, text, xOffset, color)
    local b = Instance.new("TextButton")
    b.Name = name
    b.Size = UDim2.fromOffset(30, 26)
    b.Position = UDim2.new(1, xOffset, 0, 6)
    b.BackgroundColor3 = color
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 16
    b.Text = text
    b.AutoButtonColor = true
    b.Parent = topbar
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end

local minimizeButton = makeTopButton("MinimizeButton", "−", -70, Color3.fromRGB(75, 82, 103))
local closeButton = makeTopButton("CloseButton", "×", -36, Color3.fromRGB(150, 55, 65))

local status = Instance.new("TextLabel")
status.Name = "Status"
status.Size = UDim2.new(1, -20, 0, 100)
status.Position = UDim2.fromOffset(10, 46)
status.BackgroundTransparency = 1
status.Text = "Click the button to preview the 3 weakest eligible units."
status.TextColor3 = Color3.fromRGB(235, 238, 245)
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextWrapped = true
status.TextYAlignment = Enum.TextYAlignment.Top
status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = frame

local button = Instance.new("TextButton")
button.Name = "FuseButton"
button.Size = UDim2.new(1, -20, 0, 42)
button.Position = UDim2.new(0, 10, 1, -52)
button.BackgroundColor3 = Color3.fromRGB(190, 135, 45)
button.TextColor3 = Color3.fromRGB(255, 255, 255)
button.Font = Enum.Font.GothamBold
button.TextSize = 14
button.Text = "PREVIEW & FUSE"
button.Parent = frame
Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)

local minimized = false
local normalSize = UDim2.fromOffset(360, 205)
local minimizedSize = UDim2.fromOffset(190, 38)
local maximizeButton

local function setMinimized(value)
    minimized = value
    if minimized then
        frame.Size = minimizedSize
        status.Visible = false
        button.Visible = false
        minimizeButton.Visible = false
        if not maximizeButton or not maximizeButton.Parent then
            maximizeButton = makeTopButton("MaximizeButton", "□", -70, Color3.fromRGB(75, 82, 103))
            maximizeButton.Activated:Connect(function() setMinimized(false) end)
        else
            maximizeButton.Visible = true
        end
        title.Text = "WEAKEST 3 • FUSE"
    else
        frame.Size = normalSize
        status.Visible = true
        button.Visible = true
        minimizeButton.Visible = true
        if maximizeButton then maximizeButton.Visible = false end
    end
end

minimizeButton.Activated:Connect(function() setMinimized(true) end)
closeButton.Activated:Connect(function()
    if resultConnection then resultConnection:Disconnect() end
    gui:Destroy()
end)

-- Drag the panel by its title bar (mouse or touch); top buttons remain clickable.
local dragging = false
local dragInput
local dragStart
local startPosition
local function beginDrag(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then return end
    dragging = true
    dragStart = input.Position
    startPosition = frame.Position
    dragInput = input
end

topbar.InputBegan:Connect(beginDrag)
title.InputBegan:Connect(beginDrag)
UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(
            startPosition.X.Scale, startPosition.X.Offset + delta.X,
            startPosition.Y.Scale, startPosition.Y.Offset + delta.Y
        )
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
        dragInput = nil
    end
end)

resultConnection = resultRemote.OnClientEvent:Connect(function(unit, err, newId)
    if not busy then return end
    if unit then
        status.Text = "Fusion successful!\nResult: " .. tostring(unit.name)
        if unit.attributes and unit.attributes.mutation then
            status.Text ..= " (" .. tostring(unit.attributes.mutation) .. ")"
        end
    else
        status.Text = "Fusion rejected by server:\n" .. tostring(err or "No result received")
    end
    busy = false
    button.Text = "PREVIEW & FUSE"
    button.Active = true
    button.AutoButtonColor = true
end)

button.Activated:Connect(function()
    if busy then return end
    local ok, targets = pcall(getWeakestThree)
    if not ok then
        status.Text = "Could not read inventory:\n" .. tostring(targets)
        return
    end
    if #targets < 3 then
        status.Text = "Need 3 eligible units after protecting the top 5."
        return
    end

    local lines = {"Selected 3 weakest eligible units:"}
    for i, unit in ipairs(targets) do
        lines[#lines + 1] = string.format("%d. %s | income %s",
            i, tostring(unit.name), tostring(math.floor(unit.value)))
    end
    status.Text = table.concat(lines, "\n") .. "\nSending fusion request..."

    -- Revalidate IDs immediately before sending.
    local d = getData()
    for _, target in ipairs(targets) do
        local current = d.Inventory and d.Inventory[target.id]
        if not current or not UnitConfig.entries[current.name] then
            status.Text = "Inventory changed. Click again to refresh the preview."
            return
        end
    end

    busy = true
    button.Text = "FUSING..."
    button.Active = false
    button.AutoButtonColor = false

    -- No client-side fusion-budget or balance gate is applied here.
    -- The server remains authoritative and may still reject the request.
    local sent, sendErr = pcall(function()
        fuseRemote:FireServer(targets[1].id, targets[2].id, targets[3].id)
    end)
    if not sent then
        busy = false
        button.Text = "PREVIEW & FUSE"
        button.Active = true
        button.AutoButtonColor = true
        status.Text = "Could not send fusion request:\n" .. tostring(sendErr)
        return
    end

    task.delay(6, function()
        if busy then
            busy = false
            button.Text = "PREVIEW & FUSE"
            button.Active = true
            button.AutoButtonColor = true
            status.Text ..= "\nNo result event received yet. The server may still be processing or may have rejected it."
        end
    end)
end)
