--[[
	CommandSystem  (the Leader's brain)
	-----------------------------------
	Each team has a Leader. Instead of every soldier deciding everything alone,
	the Leader sets ONE plan per team each tick and the soldiers follow it:

	  • Order       "Advance" = march in formation, "Engage" = fight
	  • RallyPoint  where the team is heading (the enemy's center of mass)
	  • FocusTarget the enemy to gang up on (focus fire)

	TargetingSystem and CombatSystem read this team state to act as a group.
	This is also the seam where a PLAYER will later take over the Leader: a
	human just sets Order / RallyPoint / FocusTarget instead of this AI.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local UnitManager = require(script.Parent.UnitManager)

local CommandSystem = {}

-- [teamKey] = { Order, RallyPoint, FocusTarget, Leader }
CommandSystem.TeamStates = {}

local function averagePosition(units)
	if #units == 0 then
		return nil
	end
	local sum = Vector3.zero
	for _, u in units do
		sum += u.Root.Position
	end
	return sum / #units
end

-- Pick who the whole team should focus: the enemy Leader if we can see one,
-- otherwise the closest, weakest enemy near our front line.
local function chooseFocus(enemies, allyCenter)
	for _, e in enemies do
		if e.IsLeader then
			return e
		end
	end

	local best, bestScore = nil, math.huge
	for _, e in enemies do
		local dist = (e.Root.Position - allyCenter).Magnitude
		-- lower = better: close AND low-health enemies get finished first
		local score = dist + e.Humanoid.Health
		if score < bestScore then
			bestScore = score
			best = e
		end
	end
	return best
end

function CommandSystem.Reset()
	CommandSystem.TeamStates = {}
end

-- Recompute every team's plan. Called once per tick before units act.
function CommandSystem.Update()
	for teamKey in Config.Teams do
		local state = CommandSystem.TeamStates[teamKey]
		if not state then
			state = {}
			CommandSystem.TeamStates[teamKey] = state
		end

		local allies = UnitManager.GetTeamUnits(teamKey)
		local enemies = UnitManager.GetEnemyUnits(teamKey)
		state.Leader = UnitManager.GetLeader(teamKey)

		if #allies == 0 or #enemies == 0 then
			state.Order = "Hold"
			state.FocusTarget = nil
			continue
		end

		local allyCenter = averagePosition(allies)
		local enemyCenter = averagePosition(enemies)

		-- March toward the enemy mass; that's the rally point.
		state.RallyPoint = enemyCenter

		-- Hold formation and advance until the lines are close, then commit.
		local frontGap = (enemyCenter - allyCenter).Magnitude
		state.Order = (frontGap > Config.Command.EngageRange) and "Advance" or "Engage"

		state.FocusTarget = chooseFocus(enemies, allyCenter)
	end
end

function CommandSystem.GetState(teamKey)
	return CommandSystem.TeamStates[teamKey]
end

return CommandSystem
