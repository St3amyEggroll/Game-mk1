--[[
	TargetingSystem
	---------------
	Picks who each unit fights, now coordinated by the team's Leader:

	  1. If the Leader named a focus target and it's within FocusRange, gang up
	     on it (focus fire — drops enemies fast and looks tactical).
	  2. Otherwise keep your current target until it dies.
	  3. Otherwise grab the nearest living enemy.

	NOTE: still an O(n^2) nearest scan. Fine to ~20v20; Milestone 4 swaps in a
	spatial grid so units only check nearby foes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local UnitManager = require(script.Parent.UnitManager)

local TargetingSystem = {}

function TargetingSystem.UpdateTarget(unit, state)
	-- 1. Follow the Leader's focus-fire call if the target is close enough.
	local focus = state and state.FocusTarget
	if focus and focus.Alive then
		local dist = (focus.Root.Position - unit.Root.Position).Magnitude
		if dist <= Config.Command.FocusRange then
			unit.Target = focus
			return
		end
	end

	-- 2. Stick with a still-valid target.
	if unit.Target and unit.Target.Alive then
		return
	end

	-- 3. Fall back to the nearest enemy.
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
