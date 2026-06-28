--[[
	CommandSystem  (the Leader's brain) — fog-aware
	-----------------------------------------------
	Builds one plan per team from what the team can SEE (VisionSystem), not from
	omniscient truth. If a team can't see any enemies it advances toward the
	nearest enemy spawn to make contact.

	Plan fields: Stance (Aggressive/Balanced/Defensive -- no retreating), Order
	(Advance/Engage/Hold), RallyPoint, HoldPoint, FlankPoint,
	FocusTarget, LeaderThreatened, AllyCenter/EnemyCenter, plus Known (the
	knowledge map) and KnownList (alive known enemies) the other systems read.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local UnitManager = require(script.Parent.UnitManager)
local VisionSystem = require(script.Parent.VisionSystem)
local BaseSystem = require(script.Parent.BaseSystem)

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

-- Believed position of a known enemy (real if visible now, else last-known).
local function knownPos(entry, enemy)
	if entry.visible then
		return enemy.Root.Position
	end
	return entry.pos
end

-- The center of the battlefield — geography, NOT enemy intel. A blind army
-- marches here to make contact instead of magically knowing where the enemy is.
local cachedMapCenter = nil
local function getMapCenter()
	if cachedMapCenter then
		return cachedMapCenter
	end
	local sum, n = Vector3.zero, 0
	for _, data in Config.Teams do
		local marker = Workspace:FindFirstChild(data.SpawnMarker)
		if marker then
			sum += marker.Position
			n += 1
		end
	end
	if n > 0 then
		cachedMapCenter = sum / n
	end
	return cachedMapCenter or Vector3.zero
end

-- Who the whole team focuses among KNOWN enemies: an enemy leader if we've
-- spotted one, else the closest/weakest/highest-priority sighting.
local function chooseFocus(knownList, knowledge, allyCenter)
	for _, e in knownList do
		if e.IsLeader then
			return e
		end
	end
	local best, bestScore = nil, math.huge
	for _, e in knownList do
		local entry = knowledge[e]
		local dist = (knownPos(entry, e) - allyCenter).Magnitude
		local score = dist + (entry.health or 0) - (e.Stats.Priority or 1) * 20
		if score < bestScore then
			bestScore = score
			best = e
		end
	end
	return best
end

function CommandSystem.Reset()
	CommandSystem.TeamStates = {}
	cachedMapCenter = nil
end

function CommandSystem.Update()
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
		state.Allies = allies
		state.Leader = nil
		for _, unit in allies do
			if unit.IsLeader then
				state.Leader = unit
				break
			end
		end

		-- Build the list of enemies we currently KNOW about.
		local knowledge = VisionSystem.GetKnown(teamKey)
		local knownList = {}
		for enemy in knowledge do
			if enemy.Alive then
				table.insert(knownList, enemy)
			end
		end
		state.Known = knowledge
		state.KnownList = knownList
		state.Enemies = knownList -- other systems treat "enemies" as "known enemies"

		-- No army, or nobody left to fight anywhere: idle.
		local anyEnemyAlive = false
		for otherTeam, list in byTeam do
			if otherTeam ~= teamKey and #list > 0 then
				anyEnemyAlive = true
				break
			end
		end
		if #allies == 0 or not anyEnemyAlive then
			state.Order = "Hold"
			state.Stance = "Balanced"
			state.FocusTarget = nil
			state.LeaderThreatened = false
			continue
		end

		local allyCenter = averagePosition(allies)

		-- The enemy base we're assaulting (nearest one we've DISCOVERED by sight).
		local assaultBase = BaseSystem.GetDiscoveredEnemyBase(teamKey, allyCenter)
		state.AssaultBase = assaultBase
		state.ExplorePoint = getMapCenter()

		-- Enemy center + strength from what we can SEE. If we see nothing and
		-- haven't found a base, we have no idea where they are -> explore the
		-- center to make contact (no peeking at enemy spawns).
		local enemyCenter, enemyHealth
		if #knownList > 0 then
			local sum = Vector3.zero
			enemyHealth = 0
			for _, e in knownList do
				sum += knownPos(knowledge[e], e)
				enemyHealth += (knowledge[e].health or 0) -- remembered strength, not live
			end
			enemyCenter = sum / #knownList
		else
			enemyCenter = (assaultBase and assaultBase.Position) or getMapCenter()
			enemyHealth = 0
		end

		-- Leader objective: defend home if a KNOWN enemy is near our own base.
		local ownBase = BaseSystem.Bases[teamKey]
		state.OwnBasePos = ownBase and ownBase.Position or allyCenter
		local objective = "Assault"
		if ownBase and ownBase.Alive then
			for _, e in knownList do
				if (knownPos(knowledge[e], e) - ownBase.Position).Magnitude <= Config.Command.DefendRadius then
					objective = "Defend"
					break
				end
			end
		end
		state.Objective = objective

		state.AllyCenter = allyCenter
		state.EnemyCenter = enemyCenter

		local toEnemy = enemyCenter - allyCenter
		toEnemy = toEnemy.Magnitude > 0 and toEnemy.Unit or Vector3.new(1, 0, 0)
		local side = Vector3.new(-toEnemy.Z, 0, toEnemy.X)

		-- Read the battle from what we know (so unseen reinforcements surprise us).
		local ratio = totalHealth(allies) / math.max(1, enemyHealth)
		-- No retreating (it caused the army to flee into a pile). A losing army
		-- turtles up (Defensive) and fights instead of running.
		local stance
		if ratio <= Config.Command.DefensiveRatio then
			stance = "Defensive"
		elseif ratio >= Config.Command.AggressiveRatio then
			stance = "Aggressive"
		else
			stance = "Balanced"
		end
		state.Stance = stance

		-- Is a KNOWN enemy close to our Leader?
		local threatened = false
		if state.Leader then
			local lp = state.Leader.Root.Position
			for _, e in knownList do
				if (knownPos(knowledge[e], e) - lp).Magnitude <= Config.Leader.ThreatRadius then
					threatened = true
					break
				end
			end
		end
		state.LeaderThreatened = threatened

		-- Defending? Rally on our own base; otherwise rally toward the enemy.
		if objective == "Defend" and ownBase then
			state.RallyPoint = ownBase.Position
		else
			state.RallyPoint = enemyCenter
		end
		state.HoldPoint = allyCenter + toEnemy * Config.Command.HoldDistance
		state.RearPoint = allyCenter - toEnemy * Config.Command.RetreatDistance
		state.FlankPoint = enemyCenter + side * Config.Command.FlankWidth

		local frontGap = (enemyCenter - allyCenter).Magnitude
		if stance == "Defensive" then
			state.Order = (frontGap > Config.Command.HoldDistance + Config.Command.EngageRange) and "Advance"
				or "Engage"
		else
			state.Order = (frontGap > Config.Command.EngageRange) and "Advance" or "Engage"
		end

		state.FocusTarget = chooseFocus(knownList, knowledge, allyCenter)
	end
end

function CommandSystem.GetState(teamKey)
	return CommandSystem.TeamStates[teamKey]
end

return CommandSystem
