--[[
	ControlPanel  (LocalScript)
	---------------------------
	A live panel (top-left) to drive the sim without editing Config + re-syncing:
	  • Army size presets (per team) -> restarts with the new size
	  • Restart / Pause-Resume
	  • Toggle unit collisions and vision cones
	  • Live unit count + FPS readout

	Talks to the server's ControlPanel RemoteEvent.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("ControlPanel")

local state = { paused = false, collisions = true, cones = true, army = 25 }

local gui = Instance.new("ScreenGui")
gui.Name = "ControlPanelGui"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(196, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.Position = UDim2.fromOffset(12, 86)
panel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
panel.BackgroundTransparency = 0.35
panel.BorderSizePixel = 0
panel.Parent = gui
Instance.new("UICorner").Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = panel
local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 8)
pad.PaddingBottom = UDim.new(0, 8)
pad.Parent = panel

local order = 0
local function nextOrder()
	order += 1
	return order
end

local function label(text, height)
	local l = Instance.new("TextLabel")
	l.LayoutOrder = nextOrder()
	l.Size = UDim2.fromOffset(180, height or 18)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = Color3.fromRGB(235, 235, 235)
	l.Text = text
	l.Parent = panel
	return l
end

local function button(text, callback)
	local b = Instance.new("TextButton")
	b.LayoutOrder = nextOrder()
	b.Size = UDim2.fromOffset(180, 30)
	b.BackgroundColor3 = Color3.fromRGB(55, 90, 160)
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.Parent = panel
	Instance.new("UICorner").Parent = b
	b.Activated:Connect(callback)
	return b
end

label("⚙  CONTROL", 20)

-- Army-size preset row.
local armyRow = Instance.new("Frame")
armyRow.LayoutOrder = nextOrder()
armyRow.Size = UDim2.fromOffset(180, 28)
armyRow.BackgroundTransparency = 1
armyRow.Parent = panel
local armyLayout = Instance.new("UIListLayout")
armyLayout.FillDirection = Enum.FillDirection.Horizontal
armyLayout.Padding = UDim.new(0, 3)
armyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
armyLayout.Parent = armyRow
for _, n in { 25, 50, 100, 200 } do
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(42, 28)
	b.BackgroundColor3 = Color3.fromRGB(70, 70, 82)
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = tostring(n)
	b.Parent = armyRow
	Instance.new("UICorner").Parent = b
	b.Activated:Connect(function()
		remote:FireServer("army", n)
	end)
end

local armyLabel = label("Army: 25 / team", 16)
button("⟳  Restart", function()
	remote:FireServer("restart")
end)
local pauseBtn = button("⏸  Pause", function()
	remote:FireServer("pause")
end)
local collideBtn = button("Collisions: ON", function()
	remote:FireServer("collisions", not state.collisions)
end)
local coneBtn = button("Cones: ON", function()
	remote:FireServer("cones", not state.cones)
end)
local statLabel = label("0 units", 16)

local function refresh()
	pauseBtn.Text = state.paused and "▶  Resume" or "⏸  Pause"
	collideBtn.Text = "Collisions: " .. (state.collisions and "ON" or "OFF")
	coneBtn.Text = "Cones: " .. (state.cones and "ON" or "OFF")
	armyLabel.Text = "Army: " .. tostring(state.army) .. " / team"
end

remote.OnClientEvent:Connect(function(kind, data)
	if kind == "state" and data then
		state.paused = data.paused
		state.collisions = data.collisions
		state.cones = data.cones
		state.army = data.army
		refresh()
	end
end)
refresh()

-- Live unit-count + FPS readout.
local frames, elapsed = 0, 0
RunService.RenderStepped:Connect(function(dt)
	frames += 1
	elapsed += dt
	if elapsed >= 0.5 then
		local fps = math.floor(frames / elapsed)
		frames, elapsed = 0, 0
		local units = Workspace:FindFirstChild("Units")
		local count = units and #units:GetChildren() or 0
		statLabel.Text = string.format("%d units  ·  %d fps", count, fps)
	end
end)
