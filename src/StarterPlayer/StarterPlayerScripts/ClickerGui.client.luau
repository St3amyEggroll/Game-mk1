--[[
	ClickerGui  (TEMPORARY)
	-----------------------
	A big CLICK button + a REBIRTH button, plus a live counter. Talks to
	ClickerService over the ClickerRemote. Delete this file to undo.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("ClickerRemote")

local gui = Instance.new("ScreenGui")
gui.Name = "ClickerGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- Live counter.
local info = Instance.new("TextLabel")
info.Size = UDim2.fromOffset(360, 44)
info.Position = UDim2.new(0.5, -180, 0.5, -190)
info.BackgroundTransparency = 1
info.Font = Enum.Font.GothamBold
info.TextScaled = true
info.TextColor3 = Color3.new(1, 1, 1)
info.TextStrokeTransparency = 0.4
info.Text = "Clicks: 0"
info.Parent = gui

-- CLICK button.
local clickBtn = Instance.new("TextButton")
clickBtn.Size = UDim2.fromOffset(240, 240)
clickBtn.Position = UDim2.new(0.5, -120, 0.5, -120)
clickBtn.BackgroundColor3 = Color3.fromRGB(60, 140, 255)
clickBtn.Font = Enum.Font.GothamBlack
clickBtn.TextScaled = true
clickBtn.TextColor3 = Color3.new(1, 1, 1)
clickBtn.Text = "CLICK"
clickBtn.AutoButtonColor = true
clickBtn.Parent = gui
local clickCorner = Instance.new("UICorner")
clickCorner.CornerRadius = UDim.new(0, 24)
clickCorner.Parent = clickBtn

clickBtn.Activated:Connect(function()
	remote:FireServer("click")
end)

-- REBIRTH button.
local rebirthBtn = Instance.new("TextButton")
rebirthBtn.Size = UDim2.fromOffset(240, 56)
rebirthBtn.Position = UDim2.new(0.5, -120, 0.5, 140)
rebirthBtn.BackgroundColor3 = Color3.fromRGB(200, 120, 40)
rebirthBtn.Font = Enum.Font.GothamBold
rebirthBtn.TextScaled = true
rebirthBtn.TextColor3 = Color3.new(1, 1, 1)
rebirthBtn.Text = "REBIRTH (10 → 2×)"
rebirthBtn.Parent = gui
local rebirthCorner = Instance.new("UICorner")
rebirthCorner.CornerRadius = UDim.new(0, 12)
rebirthCorner.Parent = rebirthBtn

rebirthBtn.Activated:Connect(function()
	remote:FireServer("rebirth")
end)

-- Live updates from leaderstats.
local stats = player:WaitForChild("leaderstats")
local clicks = stats:WaitForChild("Clicks")
local rebirths = stats:WaitForChild("Rebirths")

local function refresh()
	local mult = math.floor(2 ^ rebirths.Value)
	info.Text = string.format("Clicks: %d   |   Rebirths: %d  (%dx)", clicks.Value, rebirths.Value, mult)
end

clicks.Changed:Connect(refresh)
rebirths.Changed:Connect(refresh)
refresh()
