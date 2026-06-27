--[[
	TargetingSystem
	---------------
	Each unit scores every enemy and picks the best. The score blends:

	  • Priority   — high-value enemies (leader, and later healers/artillery).
	  • Self threat   — an enemy currently attacking ME.
	  • Leader threat — an enemy currently attacking MY leader (defend him!).
	  • Focus      — the Leader's called focus target.
	  • Distance   — closer is better.
	  • Hysteresis — a bonus for keeping the current target (no thrashing).

	NOTE: still an O(n) scan per unit. Fine to ~20v20; Milestone 4 swaps in a
	spatial grid so units only score nearby foes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local UnitManager = require(script.Parent.UnitManager)

local TargetingSystem = {}

local function priorityOf(enemy)
	if enemy.IsLeader then
		return Config.Targeting.LeaderPriority
	end
	return enemy.Stats.Priority or 1
end

-- True if `attacker` recently hit `victim`.
local function recentlyHit(victim, attacker, now)
	return victim
		and victim.AttackedBy == attacker
		and (now - (victim.AttackedAt or 0)) < Config.Targeting.ThreatMemory
end

function TargetingSystem.UpdateTarget(unit, state, now)
	local enemies = (state and state.Enemies) or UnitManager.GetEnemies(unit)
	if #enemies == 0 then
		unit.Target = nil
		return
	end

	local W = Config.Targeting
	local pos = unit.Root.Position
	local leader = state and state.Leader
	local focus = state and state.FocusTarget

	local function scoreOf(enemy)
		local dist = (enemy.Root.Position - pos).Magnitude
		local score = -dist * W.DistanceWeight
		score += priorityOf(enemy) * W.PriorityWeight
		if recentlyHit(unit, enemy, now) then
			score += W.SelfThreatWeight
		end
		if leader and recentlyHit(leader, enemy, now) then
			score += W.LeaderThreatWeight
		end
		if focus == enemy and dist <= Config.Command.FocusRange then
			score += W.FocusWeight
		end
		return score
	end

	-- Start from the current target (with a stickiness bonus), then see if any
	-- enemy beats it.
	local best, bestScore = nil, -math.huge
	if unit.Target and unit.Target.Alive then
		best = unit.Target
		bestScore = scoreOf(unit.Target) + W.Hysteresis
	end

	for _, enemy in enemies do
		local score = scoreOf(enemy)
		if score > bestScore then
			bestScore = score
			best = enemy
		end
	end

	unit.Target = best
end

return TargetingSystem
