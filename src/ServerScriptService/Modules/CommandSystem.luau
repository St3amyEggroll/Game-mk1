--[[
	CommandSystem  (the Leader's brain)
	-----------------------------------
	Once per tick this reads the battle and builds ONE plan per team that the
	soldiers follow. The plan now includes a STANCE based on who's winning:

	  • Aggressive  — winning: push hard, rally on the enemy.
	  • Balanced    — even: standard advance + engage.
	  • Defensive   — losing: hold a line, turtle up, Leader pulls back, guards
	                  ring up around the Leader.
	  • Retreat     — losing badly / Leader dead: fall back to a rear point and
	                  regroup.

	Other fields: RallyPoint (forward), RearPoint (regroup behind), FlankPoint
	(enemy's side), FocusTarget (high-value enemy), LeaderThreatened, plus the
	cached Allies/Enemies lists so nothing rebuilds per-unit.

	This is the seam a PLAYER plugs into later: set Stance/Order/Focus by hand.
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

local function totalHealth(units)
	local total = 0
	for _, u in units do
		total += u.Humanoid.Health
	end
	return total
end

-- Who the whole team focuses: enemy Leader if visible, else the closest,
-- weakest, highest-priority enemy near our front.
local function chooseFocus(enemies, allyCenter)
	for _, e in enemies do
		if e.IsLeader then
			return e
		end
	end
	local best, bestScore = nil, math.huge
	for _, e in enemies do
		local dist = (e.Root.Position - allyCenter).Magnitude
		local score = dist + e.Humanoid.Health - (e.Stats.Priority or 1) * 20
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
			state.Stance = "Balanced"
			state.FocusTarget = nil
			state.AllyCenter = nil
			state.EnemyCenter = nil
			state.LeaderThreatened = false
			continue
		end

		local allyCenter = averagePosition(allies)
		local enemyCenter = averagePosition(enemies)
		state.AllyCenter = allyCenter
		state.EnemyCenter = enemyCenter

		local toEnemy = enemyCenter - allyCenter
		toEnemy = toEnemy.Magnitude > 0 and toEnemy.Unit or Vector3.new(1, 0, 0)
		local side = Vector3.new(-toEnemy.Z, 0, toEnemy.X)

		-- Read the battle: our health vs theirs sets the stance.
		local ratio = totalHealth(allies) / math.max(1, totalHealth(enemies))
		local leaderAlive = state.Leader ~= nil
		local stance
		if ratio <= Config.Command.RetreatRatio or (not leaderAlive and ratio < 1) then
			stance = "Retreat"
		elseif ratio <= Config.Command.DefensiveRatio then
			stance = "Defensive"
		elseif ratio >= Config.Command.AggressiveRatio then
			stance = "Aggressive"
		else
			stance = "Balanced"
		end
		state.Stance = stance

		-- Is the Leader under direct threat?
		local threatened = false
		if state.Leader then
			local lp = state.Leader.Root.Position
			for _, e in enemies do
				if (e.Root.Position - lp).Magnitude <= Config.Leader.ThreatRadius then
					threatened = true
					break
				end
			end
		end
		state.LeaderThreatened = threatened

		-- Key positions.
		state.RallyPoint = enemyCenter
		state.HoldPoint = allyCenter + toEnemy * Config.Command.HoldDistance
		state.RearPoint = allyCenter - toEnemy * Config.Command.RetreatDistance
		state.FlankPoint = enemyCenter + side * Config.Command.FlankWidth

		-- Order from stance + spacing.
		local frontGap = (enemyCenter - allyCenter).Magnitude
		if stance == "Retreat" then
			state.Order = "Retreat"
		elseif stance == "Defensive" then
			-- Hold the line; only "Engage" once they reach our hold point.
			state.Order = (frontGap > Config.Command.HoldDistance + Config.Command.EngageRange) and "Advance"
				or "Engage"
		else
			state.Order = (frontGap > Config.Command.EngageRange) and "Advance" or "Engage"
		end

		state.FocusTarget = chooseFocus(enemies, allyCenter)
	end
end

function CommandSystem.GetState(teamKey)
	return CommandSystem.TeamStates[teamKey]
end

return CommandSystem
