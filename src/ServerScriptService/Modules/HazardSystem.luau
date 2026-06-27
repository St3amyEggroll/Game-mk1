--[[
	HazardSystem
	------------
	Lava / fire / explosive zones. Put parts in a Workspace folder named
	"Hazards". Units steer away from them while moving and take damage if they
	end up standing inside one.

	The hazard list is cached once per tick (Refresh) so per-unit steering is
	cheap.
]]

local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local HazardSystem = {}

local cache = {} -- { {pos = Vector3, radius = number}, ... }
local lastDamage = 0

function HazardSystem.Refresh()
	cache = {}
	local folder = Workspace:FindFirstChild("Hazards")
	if not folder then
		return
	end
	for _, part in folder:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(cache, {
				pos = part.Position,
				radius = math.max(part.Size.X, part.Size.Z) / 2,
			})
		end
	end
end

-- A steering push away from any nearby hazards (added into movement).
function HazardSystem.Repel(position)
	if #cache == 0 then
		return Vector3.zero
	end
	local push = Vector3.zero
	for _, hazard in cache do
		local offset = position - hazard.pos
		offset = Vector3.new(offset.X, 0, offset.Z)
		local dist = offset.Magnitude
		local danger = hazard.radius + Config.Hazards.AvoidRadius
		if dist > 0 and dist < danger then
			push += offset.Unit * (danger - dist)
		end
	end
	return push * Config.Hazards.AvoidStrength
end

-- Damage any unit caught standing inside a hazard (throttled).
function HazardSystem.ApplyDamage(units, now)
	if #cache == 0 or now - lastDamage < Config.Hazards.DamageInterval then
		return
	end
	lastDamage = now
	for _, hazard in cache do
		for _, unit in units do
			if unit.Alive and unit.Root then
				local offset = unit.Root.Position - hazard.pos
				offset = Vector3.new(offset.X, 0, offset.Z)
				if offset.Magnitude < hazard.radius then
					unit.Humanoid:TakeDamage(Config.Hazards.Damage)
				end
			end
		end
	end
end

return HazardSystem
