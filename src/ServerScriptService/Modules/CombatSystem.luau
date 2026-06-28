--[[
	CombatSystem  (fog-aware)
	-------------------------
	One unit's "turn", driven by its role + the team's stance/order, and now by
	what the team can SEE:

	  • Units move toward a target's BELIEVED position (real if visible, else the
	    last-known spot — so they investigate where an enemy was last seen).
	  • Units only STRIKE a target they can actually see and reach.
	  • Striking an enemy whose team can't see you lands an AMBUSH bonus.

	Roles: Leader (directs/self-defends), Guard (screens/rings the leader),
	Flank (peels once engaged), Archer (kites + shoots with LOS), Cavalry
	(charge/peel hit-and-run), Main/Scout (advance then engage).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local NavigationSystem = require(script.Parent.NavigationSystem)
local HazardSystem = require(script.Parent.HazardSystem)
local EffectsSystem = require(script.Parent.EffectsSystem)
local BaseSystem = require(script.Parent.BaseSystem)
local AnimationSystem = require(script.Parent.AnimationSystem)

local CombatSystem = {}

function CombatSystem.RefreshObstacleFilter()
	NavigationSystem.Refresh()
end

-- ---- fog-of-war helpers ----------------------------------------------------

local function isVisible(state, target)
	local entry = state and state.Known and state.Known[target]
	return entry ~= nil and entry.visible
end

-- Where this unit BELIEVES the target is: real spot if seen, else last-known.
local function believedPos(state, target)
	if isVisible(state, target) then
		return target.Root.Position
	end
	local entry = state and state.Known and state.Known[target]
	return (entry and entry.pos) or target.Root.Position
end

-- Can we actually hit it? Must be visible and within reach.
local function canStrike(unit, target, state)
	return isVisible(state, target)
		and (target.Root.Position - unit.Root.Position).Magnitude <= unit.Stats.AttackRange
end

-- ---- movement --------------------------------------------------------------

local function separation(unit, allies)
	local push = Vector3.zero
	local pos = unit.Root.Position
	local radius = Config.Command.SeparationRadius
	for _, ally in allies do
		if ally ~= unit then
			local offset = pos - ally.Root.Position
			local dist = offset.Magnitude
			if dist > 0 and dist < radius then
				push += offset.Unit * (radius - dist)
			end
		end
	end
	return push
end

local function moveTo(unit, goal, allies, now)
	local point = NavigationSystem.NextPoint(unit, goal, now)
	local steer = separation(unit, allies) + HazardSystem.Repel(unit.Root.Position)
	unit.Humanoid:MoveTo(point + steer)
end

local function faceToward(unit, targetPos)
	local pos = unit.Root.Position
	local look = Vector3.new(targetPos.X, pos.Y, targetPos.Z)
	if (look - pos).Magnitude > 0.1 then
		unit.Root.CFrame = CFrame.lookAt(pos, look)
	end
end

-- ---- attacks ---------------------------------------------------------------

local function attackDamage(unit, state, target)
	local damage = unit.Stats.AttackDamage
	local leader = state and state.Leader
	if leader and leader.Alive then
		if (leader.Root.Position - unit.Root.Position).Magnitude <= Config.Command.MoraleRange then
			damage *= Config.Command.MoraleDamageBonus
		end
	elseif Config.Leader.Enabled and not leader then
		damage *= Config.Command.LeaderlessDamagePenalty
	end
	-- Counter bonus (spearmen vs cavalry).
	local bonus = unit.Stats.BonusVs
	if bonus and target and bonus[target.Type] then
		damage *= bonus[target.Type]
	end
	-- Ambush: the target's team can't see us.
	if target and unit.SeenBy and not unit.SeenBy[target.Team] then
		damage *= Config.Vision.AmbushBonus
	end
	return damage
end

-- Land a hit if the cooldown is ready. Returns true if it fired.
local function dealHit(unit, target, now, state)
	if now - unit.LastAttack < unit.Stats.AttackCooldown then
		return false
	end
	unit.LastAttack = now
	target.Humanoid:TakeDamage(attackDamage(unit, state, target))
	target.AttackedBy = unit
	target.AttackedAt = now
	AnimationSystem.PlayAttack(unit)
	return true
end

local function swingAt(unit, target, now, state)
	faceToward(unit, target.Root.Position)
	unit.Humanoid:Move(Vector3.zero)
	dealHit(unit, target, now, state)
end

-- Nearest KNOWN enemy to a position (by believed location).
local function nearestEnemy(state, position)
	local nearest, nearestDist = nil, math.huge
	for _, enemy in (state and state.KnownList) or {} do
		local dist = (believedPos(state, enemy) - position).Magnitude
		if dist < nearestDist then
			nearestDist = dist
			nearest = enemy
		end
	end
	return nearest, nearestDist
end

-- Strike if we can see & reach the target, otherwise move to its believed spot.
local function fightTarget(unit, target, now, state, allies)
	if not target or not target.Alive then
		return
	end
	if canStrike(unit, target, state) then
		swingAt(unit, target, now, state)
	else
		moveTo(unit, believedPos(state, target), allies, now)
	end
end

-- No enemy unit to fight: march on the discovered enemy base and tear it down.
local function assault(unit, state, allies, now)
	local base = state and state.AssaultBase
	if not base or not base.Alive then
		if state and state.EnemyCenter then
			moveTo(unit, state.EnemyCenter, allies, now)
		end
		return
	end
	local pos = unit.Root.Position
	local flat = Vector3.new(base.Position.X - pos.X, 0, base.Position.Z - pos.Z)
	if flat.Magnitude <= unit.Stats.AttackRange + 9 then
		unit.Humanoid:Move(Vector3.zero)
		faceToward(unit, base.Position)
		if now - unit.LastAttack >= unit.Stats.AttackCooldown then
			unit.LastAttack = now
			BaseSystem.Damage(base, unit.Stats.AttackDamage)
			AnimationSystem.PlayAttack(unit)
		end
	else
		moveTo(unit, base.Position, allies, now)
	end
end

-- Worker: non-combat. Mill around the base; bolt home if a known enemy is near.
local function workerAct(unit, now, state, allies)
	local basePos = (state and state.OwnBasePos) or unit.Root.Position
	local nearest, dist = nearestEnemy(state, unit.Root.Position)
	if nearest and dist < Config.Workers.FleeRange then
		unit.WantsSprint = true
		moveTo(unit, basePos, allies, now) -- run home
		return
	end
	if not unit.WorkTarget or (unit.WorkTarget - unit.Root.Position).Magnitude < 6 then
		local angle = math.random() * math.pi * 2
		local r = math.random() * Config.Workers.WanderRadius
		unit.WorkTarget = basePos + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
	end
	moveTo(unit, unit.WorkTarget, allies, now)
end

-- ---- per-role behavior -----------------------------------------------------

local function leaderAct(unit, now, state, allies)
	if state and state.AllyCenter and state.EnemyCenter then
		local back = state.AllyCenter - state.EnemyCenter
		back = back.Magnitude > 0.01 and back.Unit or Vector3.new(0, 0, 1)
		local danger = state.LeaderThreatened or state.Stance == "Defensive" or state.Stance == "Retreat"
		local standoff = danger and Config.Leader.RetreatStandoff or Config.Leader.Standoff
		local goal = state.Stance == "Retreat" and state.RearPoint
			or (state.AllyCenter + back * standoff)
		moveTo(unit, goal, allies, now)
	end

	local nearest = nearestEnemy(state, unit.Root.Position)
	if nearest and canStrike(unit, nearest, state) then
		swingAt(unit, nearest, now, state)
	end
end

local function guardAct(unit, now, state, allies)
	local leader = state and state.Leader
	if not leader or not leader.Alive then
		fightTarget(unit, unit.Target, now, state, allies)
		return
	end

	local leaderPos = leader.Root.Position
	local threat, threatDist = nearestEnemy(state, leaderPos)
	if threat and threatDist <= Config.Leader.GuardEngageRange then
		fightTarget(unit, threat, now, state, allies)
		return
	end

	local ringUp = state.LeaderThreatened or state.Stance == "Defensive" or state.Stance == "Retreat"
	if ringUp then
		local count = math.max(1, Config.Leader.GuardSquadSize)
		local angle = (unit.GuardIndex / count) * math.pi * 2
		local spot = leaderPos + Vector3.new(math.cos(angle), 0, math.sin(angle)) * Config.Leader.GuardRingRadius
		moveTo(unit, spot, allies, now)
	else
		local toEnemy = (state.EnemyCenter or leaderPos) - leaderPos
		toEnemy = toEnemy.Magnitude > 0.01 and toEnemy.Unit or Vector3.new(0, 0, 1)
		moveTo(unit, leaderPos + toEnemy * Config.Leader.GuardScreenDistance + unit.FormationOffset, allies, now)
	end
end

local function flankAct(unit, now, state, allies)
	if state.Order == "Engage" then
		if unit.Target and canStrike(unit, unit.Target, state) then
			swingAt(unit, unit.Target, now, state)
			return
		end
		if state.FocusTarget and state.FocusTarget.Alive then
			moveTo(unit, believedPos(state, state.FocusTarget), allies, now)
		else
			assault(unit, state, allies, now)
		end
	else
		local rally = state.RallyPoint or state.AllyCenter or unit.Root.Position
		moveTo(unit, rally + unit.FormationOffset, allies, now)
	end
end

-- Scout: when the team has no intel, range ahead (fanned out) to find the enemy
-- -- the leader's eyes. Once something is known, fight/assist like the line.
local function scoutAct(unit, now, state, allies)
	local hasIntel = (state and state.KnownList and #state.KnownList > 0)
		or (state and state.AssaultBase and state.AssaultBase.Alive)
	if not hasIntel then
		-- Sweep the map: roam to random points until we find something. Pick a
		-- new spot once we reach the current one.
		local center = (state and state.ExplorePoint) or unit.Root.Position
		if not unit.ExploreTarget or (unit.ExploreTarget - unit.Root.Position).Magnitude < 15 then
			local angle = math.random() * math.pi * 2
			local dist = 40 + math.random() * Config.Command.ScoutRoamRadius
			unit.ExploreTarget = center + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		end
		unit.WantsSprint = true
		moveTo(unit, unit.ExploreTarget, allies, now)
		return
	end
	if unit.Target then
		fightTarget(unit, unit.Target, now, state, allies)
	else
		assault(unit, state, allies, now)
	end
end

-- Archer: shoot visible targets from afar; kite away if they get too close.
local function rangedAct(unit, now, state, allies)
	if state and state.Order == "Advance" then
		local rally = (state.Stance == "Defensive" and state.HoldPoint) or state.RallyPoint or state.AllyCenter
		moveTo(unit, (rally or unit.Root.Position) + unit.FormationOffset, allies, now)
		return
	end

	local target = unit.Target
	if not target or not target.Alive then
		assault(unit, state, allies, now) -- no one to shoot: help take the base
		return
	end

	local myPos = unit.Root.Position

	-- Can't see it: move to where we think it is.
	if not isVisible(state, target) then
		moveTo(unit, believedPos(state, target), allies, now)
		return
	end

	local targetPos = target.Root.Position
	local dist = (targetPos - myPos).Magnitude
	local minRange = unit.Stats.MinRange or 0

	if dist < minRange then
		unit.WantsSprint = true -- kite away (costs stamina)
		local away = myPos - targetPos
		away = Vector3.new(away.X, 0, away.Z)
		away = away.Magnitude > 0.01 and away.Unit or Vector3.new(0, 0, 1)
		moveTo(unit, myPos + away * 20, allies, now)
	elseif dist <= unit.Stats.AttackRange and NavigationSystem.HasLineOfSight(myPos, targetPos) then
		unit.Humanoid:Move(Vector3.zero)
		faceToward(unit, targetPos)
		if dealHit(unit, target, now, state) then
			local color = Config.Teams[unit.Team] and Config.Teams[unit.Team].Color
			EffectsSystem.Tracer(myPos + Vector3.new(0, 1.5, 0), targetPos + Vector3.new(0, 1.5, 0), color)
		end
	else
		moveTo(unit, targetPos, allies, now)
	end
end

-- Cavalry: ride with the army, then charge -> strike -> peel away -> re-charge.
local function cavalryAct(unit, now, state, allies)
	if state and (state.Order == "Advance" or state.Order == "Retreat") then
		local goal = state.Order == "Retreat" and (state.RearPoint or state.AllyCenter)
			or (state.RallyPoint or state.AllyCenter)
		moveTo(unit, (goal or unit.Root.Position) + unit.FormationOffset, allies, now)
		return
	end

	if unit.CavalryPhase == "Peel" then
		if now < (unit.PeelUntil or 0) and unit.PeelPoint then
			moveTo(unit, unit.PeelPoint, allies, now)
			return
		end
		unit.CavalryPhase = "Charge"
		unit.LastAttack = 0
	end

	unit.WantsSprint = true -- full gallop
	local target = unit.Target
	if not target or not target.Alive then
		assault(unit, state, allies, now) -- no one to charge: ride at the base
		return
	end

	if canStrike(unit, target, state) then
		swingAt(unit, target, now, state) -- impact
		unit.CavalryPhase = "Peel"
		unit.PeelUntil = now + Config.Cavalry.PeelTime
		local away = unit.Root.Position - target.Root.Position
		away = Vector3.new(away.X, 0, away.Z)
		away = away.Magnitude > 0.01 and away.Unit or Vector3.new(0, 0, 1)
		unit.PeelPoint = unit.Root.Position + away * Config.Cavalry.PeelDistance
	else
		moveTo(unit, believedPos(state, target), allies, now)
	end
end

-- ---- dispatch --------------------------------------------------------------

function CombatSystem.Act(unit, now, state)
	local allies = (state and state.Allies) or {}

	if unit.IsLeader then
		leaderAct(unit, now, state, allies)
		return
	end

	if unit.Role == "Cavalry" then
		cavalryAct(unit, now, state, allies)
		return
	end

	if unit.Role == "Worker" then
		workerAct(unit, now, state, allies)
		return
	end

	if state and state.Order == "Retreat" then
		if unit.Role == "Guard" then
			guardAct(unit, now, state, allies)
		else
			unit.WantsSprint = true -- run for it (and tire out)
			moveTo(unit, (state.RearPoint or state.AllyCenter) + unit.FormationOffset, allies, now)
			local nearest = nearestEnemy(state, unit.Root.Position)
			if nearest and canStrike(unit, nearest, state) then
				swingAt(unit, nearest, now, state)
			end
		end
		return
	end

	if unit.Role == "Archer" then
		rangedAct(unit, now, state, allies)
		return
	end

	if unit.Role == "Guard" then
		guardAct(unit, now, state, allies)
		return
	end

	if unit.Role == "Flank" then
		flankAct(unit, now, state, allies)
		return
	end

	if unit.Role == "Scout" then
		scoutAct(unit, now, state, allies)
		return
	end

	-- Main. Advance to the rally (or a defensive hold line), then engage.
	if state and state.Order == "Advance" then
		local rally = (state.Stance == "Defensive" and state.HoldPoint) or state.RallyPoint
		if rally then
			moveTo(unit, rally + unit.FormationOffset, allies, now)
			return
		end
	end

	if unit.Target then
		fightTarget(unit, unit.Target, now, state, allies)
	else
		assault(unit, state, allies, now)
	end
end

return CombatSystem
