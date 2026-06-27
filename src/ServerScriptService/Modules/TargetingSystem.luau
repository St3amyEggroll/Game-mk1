--[[
	TargetingSystem  (fog-aware)
	----------------------------
	A unit only considers enemies its TEAM currently knows about (KnownList).
	It scores them and picks the best:

	  • Priority   — high-value enemies (leader, archers).
	  • Self/Leader threat — enemies attacking you or your leader.
	  • Focus      — the Leader's called focus target.
	  • Distance   — closer (by last-known position) is better.
	  • Hysteresis — bonus for keeping the current target (no thrashing).

	Distances use the BELIEVED position: the real spot if we can see it now, or
	the last-known spot if we've lost sight.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local TargetingSystem = {}

local function priorityOf(enemy)
	if enemy.IsLeader then
		return Config.Targeting.LeaderPriority
	end
	return enemy.Stats.Priority or 1
end

local function recentlyHit(victim, attacker, now)
	return victim
		and victim.AttackedBy == attacker
		and (now - (victim.AttackedAt or 0)) < Config.Targeting.ThreatMemory
end

local function believedPos(known, enemy)
	local entry = known and known[enemy]
	if not entry then
		return enemy.Root.Position
	end
	return entry.visible and enemy.Root.Position or entry.pos
end

function TargetingSystem.UpdateTarget(unit, state, now)
	local knownList = state and state.KnownList
	if not knownList or #knownList == 0 then
		unit.Target = nil -- we don't know about anyone to fight
		return
	end

	local known = state.Known
	local W = Config.Targeting
	local pos = unit.Root.Position
	local leader = state.Leader
	local focus = state.FocusTarget

	local function scoreOf(enemy)
		local dist = (believedPos(known, enemy) - pos).Magnitude
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

	local best, bestScore = nil, -math.huge
	-- Keep the current target only if it's still known.
	if unit.Target and unit.Target.Alive and known and known[unit.Target] then
		best = unit.Target
		bestScore = scoreOf(unit.Target) + W.Hysteresis
	end

	for _, enemy in knownList do
		local score = scoreOf(enemy)
		if score > bestScore then
			bestScore = score
			best = enemy
		end
	end

	unit.Target = best
end

return TargetingSystem
