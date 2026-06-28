--[[
	ClickerService  (TEMPORARY)
	---------------------------
	A throwaway clicker on top of the sim:
	  • leaderstats: Clicks + Rebirths
	  • each click adds (2 ^ Rebirths) clicks
	  • Rebirth costs 10 clicks, resets Clicks to 0, and +1 Rebirth (so every
	    rebirth doubles clicks earned from then on)

	Delete this file (and ClickerGui.client.luau) to undo.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REBIRTH_COST = 10

local remote = ReplicatedStorage:FindFirstChild("ClickerRemote")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "ClickerRemote"
	remote.Parent = ReplicatedStorage
end

local function setupStats(player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local clicks = Instance.new("IntValue")
	clicks.Name = "Clicks"
	clicks.Parent = leaderstats

	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = leaderstats

	leaderstats.Parent = player
end

Players.PlayerAdded:Connect(setupStats)
for _, player in Players:GetPlayers() do
	setupStats(player)
end

remote.OnServerEvent:Connect(function(player, action)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		return
	end
	local clicks = stats:FindFirstChild("Clicks")
	local rebirths = stats:FindFirstChild("Rebirths")
	if not clicks or not rebirths then
		return
	end

	if action == "click" then
		clicks.Value += 2 ^ rebirths.Value
	elseif action == "rebirth" then
		if clicks.Value >= REBIRTH_COST then
			clicks.Value = 0
			rebirths.Value += 1
		end
	end
end)
