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

-- If you see this in the Output window, the client script IS synced & running.
print("[BattleClient] spectator camera active")

-- Render distance: push fog/atmosphere out so far-off units don't fade away.
local Lighting = game:GetService("Lighting")
Lighting.FogStart = 100000
Lighting.FogEnd = 1000000
for _, item in Lighting:GetChildren() do
	if item:IsA("Atmosphere") then
		item.Density = math.min(item.Density, 0.15)
		item.Haze = 0
	end
end

-- Freeze the avatar so flying the camera doesn't also walk the character
-- around the viewing platform.
local function freezeCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	end
end
if player.Character then
	freezeCharacter(player.Character)
end
player.CharacterAdded:Connect(freezeCharacter)

-- ---------------------------------------------------------------- UI build ---

local screen = Instance.new("ScreenGui")
screen.Name = "BattleHUD"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.Parent = playerGui

-- Scoreboard (top center) — one panel per team, built from Config.Teams.
local teamKeys = {}
for key in Config.Teams do
	table.insert(teamKeys, key)
end
table.sort(teamKeys)

local scoreFrame = Instance.new("Frame")
scoreFrame.AutomaticSize = Enum.AutomaticSize.X
scoreFrame.Size = UDim2.fromOffset(0, 56)
scoreFrame.Position = UDim2.new(0.5, 0, 0, 12)
scoreFrame.AnchorPoint = Vector2.new(0.5, 0)
scoreFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
scoreFrame.BackgroundTransparency = 0.4
scoreFrame.BorderSizePixel = 0
scoreFrame.Parent = screen
Instance.new("UICorner").Parent = scoreFrame
local scoreLayout = Instance.new("UIListLayout")
scoreLayout.FillDirection = Enum.FillDirection.Horizontal
scoreLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
scoreLayout.VerticalAlignment = Enum.VerticalAlignment.Center
scoreLayout.Padding = UDim.new(0, 8)
scoreLayout.Parent = scoreFrame
local scorePad = Instance.new("UIPadding")
scorePad.PaddingLeft = UDim.new(0, 14)
scorePad.PaddingRight = UDim.new(0, 14)
scorePad.Parent = scoreFrame

local teamLabels = {} -- teamKey -> TextLabel
for order, key in teamKeys do
	local team = Config.Teams[key]
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.Size = UDim2.fromOffset(150, 56)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = team.Color
	label.Text = team.Name .. "  0"
	label.Parent = scoreFrame
	teamLabels[key] = label
end

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
	for key, label in teamLabels do
		label.Text = Config.Teams[key].Name .. "  " .. tostring(counts[key] or 0)
	end
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

-- -------------------------------------------------------- Spectator camera ---
-- Free-fly: WASD to move, hold Right Mouse to look, Q/E down/up, Shift = fast.
-- Press F to toggle an auto-follow cam that frames the whole battle.

local UserInputService = game:GetService("UserInputService")

local camera = Workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable

local MOVE_SPEED = 70 -- studs/sec
local FAST_MULTIPLIER = 3.5
local LOOK_SENSITIVITY = 0.005

-- Where to point the camera on startup: the battlefield, not empty space.
-- Averages every Team*Spawn marker so it frames all armies (2 or 3 teams).
local function initialFocus()
	local sum, count = Vector3.zero, 0
	for _, child in Workspace:GetChildren() do
		if child:IsA("BasePart") and string.match(child.Name, "^Team.*Spawn$") then
			sum += child.Position
			count += 1
		end
	end
	if count > 0 then
		return sum / count
	end
	local ground = Workspace:FindFirstChild("Battlefield") or Workspace:FindFirstChild("Baseplate")
	return ground and ground.Position or Vector3.zero
end

-- Camera state, tracked as a position + yaw/pitch we rebuild each frame.
local focus = initialFocus()
local camPos = focus + Vector3.new(0, 110, 200)
local yaw, pitch
do
	local dir = focus - camPos
	dir = dir.Magnitude > 0 and dir.Unit or Vector3.new(0, 0, -1)
	pitch = math.asin(math.clamp(dir.Y, -1, 1))
	yaw = math.atan2(-dir.X, -dir.Z)
end
local held = {} -- keycode name -> true
local looking = false
local followMode = false

local function camRotation()
	return CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
end

-- Average position + spread of all units, for the follow cam.
local function battleFocus()
	local unitsFolder = Workspace:FindFirstChild("Units")
	if not unitsFolder then
		return nil, 0
	end
	local sum, count = Vector3.zero, 0
	local positions = {}
	for _, model in unitsFolder:GetChildren() do
		local root = model:FindFirstChild("HumanoidRootPart")
		if root then
			sum += root.Position
			count += 1
			table.insert(positions, root.Position)
		end
	end
	if count == 0 then
		return nil, 0
	end
	local center = sum / count
	local spread = 0
	for _, pos in positions do
		spread = math.max(spread, (pos - center).Magnitude)
	end
	return center, spread
end

-- Controls hint (bottom center).
local hint = Instance.new("TextLabel")
hint.Size = UDim2.fromOffset(640, 24)
hint.Position = UDim2.new(0.5, -320, 1, -32)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham
hint.TextSize = 15
hint.TextColor3 = Color3.fromRGB(235, 235, 235)
hint.TextStrokeTransparency = 0.5
hint.Text = "WASD fly  ·  hold Right-Mouse to look  ·  Q/E down/up  ·  Shift boost  ·  F auto-follow"
hint.Parent = screen

-- Input: keys.
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		held[input.KeyCode.Name] = true
		if input.KeyCode == Enum.KeyCode.F then
			followMode = not followMode
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		looking = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Keyboard then
		held[input.KeyCode.Name] = nil
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		looking = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end)

-- Input: mouse look while holding RMB.
UserInputService.InputChanged:Connect(function(input)
	if looking and input.UserInputType == Enum.UserInputType.MouseMovement then
		yaw -= input.Delta.X * LOOK_SENSITIVITY
		pitch = math.clamp(pitch - input.Delta.Y * LOOK_SENSITIVITY, math.rad(-89), math.rad(89))
	end
end)

-- Bind AFTER the default camera each frame and re-assert Scriptable, so the
-- built-in camera can never steal control (which would leave us in the void).
local function updateCamera(dt)
	camera.CameraType = Enum.CameraType.Scriptable

	if followMode then
		local center, spread = battleFocus()
		if center then
			local distance = math.clamp(spread * 1.6 + 40, 60, 320)
			local height = math.clamp(spread * 1.1 + 30, 40, 240)
			local goal = CFrame.lookAt(center + Vector3.new(0, height, distance), center)
			camera.CFrame = camera.CFrame:Lerp(goal, 0.05)
			camPos = camera.CFrame.Position -- so freecam resumes from here
		end
		return
	end

	-- Free-fly movement relative to where we're looking.
	local rot = camRotation()
	local move = Vector3.zero
	if held.W then move += rot.LookVector end
	if held.S then move -= rot.LookVector end
	if held.D then move += rot.RightVector end
	if held.A then move -= rot.RightVector end
	if held.E then move += Vector3.new(0, 1, 0) end
	if held.Q then move += Vector3.new(0, -1, 0) end

	if move.Magnitude > 0 then
		local fast = held.LeftShift or held.RightShift
		local speed = MOVE_SPEED * (fast and FAST_MULTIPLIER or 1)
		camPos += move.Unit * speed * dt
	end

	camera.CFrame = CFrame.new(camPos) * rot
end

RunService:BindToRenderStep("SpectatorCamera", Enum.RenderPriority.Camera.Value + 1, updateCamera)
