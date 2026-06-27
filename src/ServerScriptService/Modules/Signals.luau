--[[
	Signals
	-------
	A tiny server->client event bus. Lazily creates a RemoteEvent in
	ReplicatedStorage so the client HUD can listen for kills, score changes,
	and battle results. No need to build the RemoteEvent by hand in Studio.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signals = {}
local event

function Signals.Get()
	if not event then
		event = ReplicatedStorage:FindFirstChild("BattleSignals")
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = "BattleSignals"
			event.Parent = ReplicatedStorage
		end
	end
	return event
end

function Signals.Fire(payload)
	Signals.Get():FireAllClients(payload)
end

return Signals
