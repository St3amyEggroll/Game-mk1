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

function HealthBar.Attach(model, humanoid, isLeader)
	if not Config.HealthBars.Enabled then
		return
	end

	local head = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
	if not head then
		return
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Size = UDim2.fromOffset(isLeader and 70 or 48, isLeader and 9 or 6)
	gui.StudsOffset = Vector3.new(0, isLeader and 3.5 or 2.5, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = head
	gui.Parent = head

	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
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
