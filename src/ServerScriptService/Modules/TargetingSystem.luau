--[[
	TargetingSystem
	---------------
	Decides who each unit should fight. Rule for now: stick with your current
	target until it dies, then pick the nearest living enemy. Simple and it
	produces convincing "the lines crash into each other" behavior.

	NOTE: nearest-enemy is an O(n^2) scan across the whole army each tick.
	Fine at 5v5 or 20v20. When we push to 100v100 in Milestone 4 we'll swap
	this for a spatial grid so units only check nearby foes.
]]

local UnitManager = require(script.Parent.UnitManager)

local TargetingSystem = {}

function TargetingSystem.UpdateTarget(unit)
	-- Keep a valid target.
	if unit.Target and unit.Target.Alive then
		return
	end

	unit.Target = nil
	local nearestDist = math.huge
	local pos = unit.Root.Position

	for _, enemy in UnitManager.GetEnemies(unit) do
		local dist = (enemy.Root.Position - pos).Magnitude
		if dist < nearestDist then
			nearestDist = dist
			unit.Target = enemy
		end
	end
end

return TargetingSystem
