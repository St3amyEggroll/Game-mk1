--[[
	HealthBar
	---------
	A floating bar above each unit that tracks its health (green -> red) and
	hides on death. Built server-side so it just replicates to every client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local HealthBar = {}

local function colorForFraction(fraction)
	-- 1.0 = green, 0.0 = red.
	return Color3.fromRGB(math.floor(255 * (1 - fraction)), math.floor(200 * fraction), 40)
end

function HealthBar.Attach(model, humanoid, isLeader, icon)
	if not Config.HealthBars.Enabled then
		return
	end

	local head = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
	if not head then
		return
	end

	local barWidth = isLeader and 70 or 48
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Size = UDim2.fromOffset(barWidth, (isLeader and 9 or 6) + 22)
	gui.StudsOffset = Vector3.new(0, isLeader and 3.8 or 2.8, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = head
	gui.Parent = head

	-- Type icon above the bar.
	if icon then
		local iconLabel = Instance.new("TextLabel")
		iconLabel.Size = UDim2.new(1, 0, 0, isLeader and 22 or 18)
		iconLabel.Position = UDim2.fromOffset(0, 0)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Font = Enum.Font.GothamBold
		iconLabel.TextScaled = true
		iconLabel.Text = icon
		iconLabel.Parent = gui
	end

	local background = Instance.new("Frame")
	background.Size = UDim2.new(1, 0, 0, isLeader and 9 or 6)
	background.Position = UDim2.new(0, 0, 1, isLeader and -9 or -6)
	background.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	background.BorderSizePixel = 0
	background.Parent = gui

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = colorForFraction(1)
	fill.BorderSizePixel = 0
	fill.Parent = background

	humanoid.HealthChanged:Connect(function(health)
		local fraction = math.clamp(health / humanoid.MaxHealth, 0, 1)
		fill.Size = UDim2.fromScale(fraction, 1)
		fill.BackgroundColor3 = colorForFraction(fraction)
		if health <= 0 then
			gui.Enabled = false
		end
	end)
end

return HealthBar
