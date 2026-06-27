--[[
	BattleClient  (LocalScript)
	---------------------------
	The viewer's experience:
	  • Action camera that frames the whole battle and follows it.
	  • Scoreboard (survivors per team).
	  • Kill feed (recent deaths, leader deaths called out).
	  • Result banner when a side wins.

	It listens to the server's BattleSignals RemoteEvent and reads team
	names/colors from the shared Config in ReplicatedStorage.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local signals = ReplicatedStorage:WaitForChild("BattleSignals")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ---------------------------------------------------------------- UI build ---

local screen = Instance.new("ScreenGui")
screen.Name = "BattleHUD"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.Parent = playerGui

-- Scoreboard (top center).
local scoreFrame = Instance.new("Frame")
scoreFrame.Size = UDim2.fromOffset(360, 54)
scoreFrame.Position = UDim2.new(0.5, -180, 0, 12)
scoreFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
scoreFrame.BackgroundTransparency = 0.4
scoreFrame.BorderSizePixel = 0
scoreFrame.Parent = screen
Instance.new("UICorner").Parent = scoreFrame

local function makeScoreLabel(anchorX, posX, color)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromOffset(150, 54)
	label.Position = UDim2.fromOffset(posX, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = "0"
	label.TextXAlignment = anchorX
	label.Parent = scoreFrame
	return label
end

local blueLabel = makeScoreLabel(Enum.TextXAlignment.Left, 14, Config.Teams.A.Color)
local redLabel = makeScoreLabel(Enum.TextXAlignment.Right, 196, Config.Teams.B.Color)

local vsLabel = Instance.new("TextLabel")
vsLabel.Size = UDim2.fromOffset(60, 54)
vsLabel.Position = UDim2.fromOffset(150, 0)
vsLabel.BackgroundTransparency = 1
vsLabel.Font = Enum.Font.GothamBold
vsLabel.TextScaled = true
vsLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
vsLabel.Text = "VS"
vsLabel.Parent = scoreFrame

-- Kill feed (top right, lines added/removed dynamically).
local feed = Instance.new("Frame")
feed.Size = UDim2.fromOffset(280, 300)
feed.Position = UDim2.new(1, -292, 0, 78)
feed.BackgroundTransparency = 1
feed.Parent = screen
local feedLayout = Instance.new("UIListLayout")
feedLayout.SortOrder = Enum.SortOrder.LayoutOrder
feedLayout.VerticalAlignment = Enum.VerticalAlignment.Top
feedLayout.Padding = UDim.new(0, 4)
feedLayout.Parent = feed

local feedOrder = 0
local function addFeedLine(text, color, big)
	feedOrder += 1
	local line = Instance.new("TextLabel")
	line.Size = UDim2.fromOffset(280, big and 30 or 22)
	line.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	line.BackgroundTransparency = 0.5
	line.BorderSizePixel = 0
	line.Font = big and Enum.Font.GothamBold or Enum.Font.Gotham
	line.TextScaled = true
	line.TextColor3 = color
	line.Text = text
	line.TextXAlignment = Enum.TextXAlignment.Right
	line.LayoutOrder = -feedOrder
	line.Parent = feed
	Instance.new("UICorner").Parent = line
	task.delay(5, function()
		line:Destroy()
	end)
end

-- Result banner (center).
local banner = Instance.new("TextLabel")
banner.Size = UDim2.fromOffset(560, 90)
banner.Position = UDim2.new(0.5, -280, 0.5, -45)
banner.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
banner.BackgroundTransparency = 0.35
banner.BorderSizePixel = 0
banner.Font = Enum.Font.GothamBlack
banner.TextScaled = true
banner.Visible = false
banner.Parent = screen
Instance.new("UICorner").Parent = banner

-- ------------------------------------------------------------- HUD updates ---

local function updateScore(counts)
	counts = counts or {}
	blueLabel.Text = tostring(counts.A or 0)
	redLabel.Text = tostring(counts.B or 0)
end

local function teamColor(teamKey)
	local team = Config.Teams[teamKey]
	return team and team.Color or Color3.fromRGB(220, 220, 220)
end

signals.OnClientEvent:Connect(function(payload)
	if payload.kind == "start" then
		banner.Visible = false
		updateScore(payload.counts)
	elseif payload.kind == "score" then
		updateScore(payload.counts)
	elseif payload.kind == "kill" then
		local name = Config.Teams[payload.team] and Config.Teams[payload.team].Name or "A soldier"
		if payload.leader then
			addFeedLine(("★ %s's LEADER has fallen!"):format(name), teamColor(payload.team), true)
		else
			addFeedLine(("A %s soldier fell"):format(name), teamColor(payload.team), false)
		end
	elseif payload.kind == "result" then
		if payload.winner then
			local team = Config.Teams[payload.winner]
			banner.Text = (team and team.Name or "Someone") .. " WINS"
			banner.TextColor3 = teamColor(payload.winner)
		else
			banner.Text = "DRAW"
			banner.TextColor3 = Color3.fromRGB(220, 220, 220)
		end
		banner.Visible = true
	end
end)

-- ----------------------------------------------------------- Action camera ---

local camera = Workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable

local function battleFocus()
	local unitsFolder = Workspace:FindFirstChild("Units")
	if not unitsFolder then
		return nil, 0
	end

	local sum, count, maxSpread = Vector3.zero, 0, 0
	local roots = {}
	for _, model in unitsFolder:GetChildren() do
		local root = model:FindFirstChild("HumanoidRootPart")
		if root then
			sum += root.Position
			count += 1
			table.insert(roots, root.Position)
		end
	end
	if count == 0 then
		return nil, 0
	end

	local center = sum / count
	for _, pos in roots do
		maxSpread = math.max(maxSpread, (pos - center).Magnitude)
	end
	return center, maxSpread
end

RunService.RenderStepped:Connect(function()
	local center, spread = battleFocus()
	if not center then
		return
	end

	-- Pull back and rise based on how spread out the battle is.
	local distance = math.clamp(spread * 1.6 + 40, 60, 320)
	local height = math.clamp(spread * 1.1 + 30, 40, 240)
	local goalPos = center + Vector3.new(0, height, distance)
	local goalCFrame = CFrame.lookAt(goalPos, center)

	camera.CFrame = camera.CFrame:Lerp(goalCFrame, 0.04)
end)
