--[[
	CommandSystem  (the Leader's brain)
	-----------------------------------
	Once per tick this builds ONE plan per team and a shared snapshot the other
	systems reuse — so nothing rebuilds enemy/ally lists per unit (the old lag).

	Each team's state holds:
	  • Order        "Advance" (march in formation) or "Engage" (fight)
	  • RallyPoint   where the army is heading
	  • FocusTarget  the enemy to gang up on (focus fire)
	  • Leader       the team's commander (or nil if it has fallen)
	  • Allies/Enemies, AllyCenter/EnemyCenter — cached for this tick

	This is also the seam a PLAYER will later plug into: a human just sets
	Order / RallyPoint / FocusTarget instead of this AI.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local UnitManager = require(script.Parent.UnitManager)

local CommandSystem = {}

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

-- Who the whole team focuses: enemy Leader if visible, else the closest,
-- weakest enemy near our front (finish off the easy kills first).
local function chooseFocus(enemies, allyCenter)
	for _, e in enemies do
		if e.IsLeader then
			return e
		end
	end
	local best, bestScore = nil, math.huge
	for _, e in enemies do
		local score = (e.Root.Position - allyCenter).Magnitude + e.Humanoid.Health
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

function CommandSystem.Update()
	-- Single snapshot of living units, bucketed by team, for the whole tick.
	local byTeam = {}
	for _, unit in UnitManager.Units do
		if unit.Alive then
			local list = byTeam[unit.Team]
			if not list then
				list = {}
				byTeam[unit.Team] = list
			end
			table.insert(list, unit)
		end
	end

	for teamKey in Config.Teams do
		local state = CommandSystem.TeamStates[teamKey]
		if not state then
			state = {}
			CommandSystem.TeamStates[teamKey] = state
		end

		local allies = byTeam[teamKey] or {}
		local enemies = {}
		for otherTeam, list in byTeam do
			if otherTeam ~= teamKey then
				table.move(list, 1, #list, #enemies + 1, enemies)
			end
		end

		state.Allies = allies
		state.Enemies = enemies

		state.Leader = nil
		for _, unit in allies do
			if unit.IsLeader then
				state.Leader = unit
				break
			end
		end

		if #allies == 0 or #enemies == 0 then
			state.Order = "Hold"
			state.FocusTarget = nil
			state.AllyCenter = nil
			state.EnemyCenter = nil
		else
			local allyCenter = averagePosition(allies)
			local enemyCenter = averagePosition(enemies)
			state.AllyCenter = allyCenter
			state.EnemyCenter = enemyCenter
			state.RallyPoint = enemyCenter

			local frontGap = (enemyCenter - allyCenter).Magnitude
			state.Order = (frontGap > Config.Command.EngageRange) and "Advance" or "Engage"
			state.FocusTarget = chooseFocus(enemies, allyCenter)
		end
	end
end

function CommandSystem.GetState(teamKey)
	return CommandSystem.TeamStates[teamKey]
end

return CommandSystem
