-- Anime Dice: Preview & Fuse 3 Weakest
-- Standalone client-side button script.
-- Protects the 5 highest base-income units, plus all placed/Tower Team units.
-- Ignores local budget and balance checks. The server may still reject a fusion
-- for its own validation, money requirements, cooldown, or fusion rules.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

    local all = {}
    for id, unit in pairs(d.Inventory) do
        if type(unit) == "table" and UnitConfig.entries[unit.name] then
            all[#all + 1] = { id = id, name = unit.name, value = baseIncome(unit) }
        end
    end
    table.sort(all, function(a, b) return a.value > b.value end)

    -- Protect the five strongest units overall, regardless of placement.
    for i = 1, math.min(5, #all) do
        protectedIds[all[i].id] = true
    end

    local candidates = {}
    for _, unit in ipairs(all) do
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

local gui = Instance.new("ScreenGui")
gui.Name = "WeakestFuseStandalone"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "Panel"
frame.Size = UDim2.fromOffset(330, 180)
frame.Position = UDim2.new(0.5, -165, 0.72, -90)
frame.BackgroundColor3 = Color3.fromRGB(24, 27, 38)
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 30)
title.Position = UDim2.fromOffset(10, 7)
title.BackgroundTransparency = 1
title.Text = "WEAKEST 3 • FUSE"
title.TextColor3 = Color3.fromRGB(255, 213, 100)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.Parent = frame

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -20, 0, 76)
status.Position = UDim2.fromOffset(10, 40)
status.BackgroundTransparency = 1
status.Text = "Click the button to preview the 3 weakest eligible units."
status.TextColor3 = Color3.fromRGB(235, 238, 245)
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextWrapped = true
status.TextYAlignment = Enum.TextYAlignment.Top
status.Parent = frame

local button = Instance.new("TextButton")
button.Size = UDim2.new(1, -20, 0, 42)
button.Position = UDim2.new(0, 10, 1, -52)
button.BackgroundColor3 = Color3.fromRGB(190, 135, 45)
button.TextColor3 = Color3.fromRGB(255, 255, 255)
button.Font = Enum.Font.GothamBold
button.TextSize = 14
button.Text = "PREVIEW & FUSE"
button.Parent = frame
Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)

local busy = false
local resultConnection
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
