--[[
	CombatSystem  (modern military -- guns)
	---------------------------------------
	Almost everyone carries a gun, so combat is RANGED: units hold at their
	weapon range and shoot (tracers), back off if an enemy gets inside MinRange,
	and only close the distance when out of range. This keeps them in spaced
	firing lines instead of piling into a melee scrum.

	Still fog-aware (act on believed positions, only shoot what you can see, get
	an ambush bonus from outside the enemy's vision) and grid-accelerated.

	Roles: Leader (directs from the back, fires in self-defense), Guard (screens
	the leader), Flank (peels wide once engaged), Scout (recons then fights),
	Main (advance + engage), Worker (non-combat).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local NavigationSystem = require(script.Parent.NavigationSystem)
local HazardSystem = require(script.Parent.HazardSystem)
local EffectsSystem = require(script.Parent.EffectsSystem)
local BaseSystem = require(script.Parent.BaseSystem)
local AnimationSystem = require(script.Parent.AnimationSystem)
local SpatialGrid = require(script.Parent.SpatialGrid)
local EconomySystem = require(script.Parent.EconomySystem)

local CombatSystem = {}

local function horizontalDist(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

function CombatSystem.RefreshObstacleFilter()
	NavigationSystem.Refresh()
end

local function teamColor(unit)
	local team = Config.Teams[unit.Team]
	return team and team.Color
end

-- ---- fog-of-war helpers ----------------------------------------------------

local function isVisible(state, target)
	local entry = state and state.Known and state.Known[target]
	return entry ~= nil and entry.visible
end

local function believedPos(state, target)
	if isVisible(state, target) then
		return target.Root.Position
	end
	local entry = state and state.Known and state.Known[target]
	return (entry and entry.pos) or target.Root.Position
end

-- ---- movement --------------------------------------------------------------

-- Push apart from nearby ALLIES (grid-queried) so they hold a spaced line.
local function separation(unit)
	local push = Vector3.zero
	local pos = unit.Root.Position
	local radius = Config.Command.SeparationRadius
	SpatialGrid.ForNear(pos, radius, function(other)
		if other ~= unit and other.Alive and other.Team == unit.Team then
			local offset = pos - other.Root.Position
			local dist = offset.Magnitude
			if dist > 0 and dist < radius then
				push += offset.Unit * (radius - dist)
			end
		end
	end)
	return push
end

local function moveTo(unit, goal, now)
	local point = NavigationSystem.NextPoint(unit, goal, now)
	unit.Humanoid:MoveTo(point + separation(unit) + HazardSystem.Repel(unit.Root.Position))
end

local function faceToward(unit, targetPos)
	local pos = unit.Root.Position
	local look = Vector3.new(targetPos.X, pos.Y, targetPos.Z)
	if (look - pos).Magnitude > 0.1 then
		unit.Root.CFrame = CFrame.lookAt(pos, look)
	end
end

-- ---- firing ----------------------------------------------------------------

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

-- Fire if the cooldown is ready. Returns true if a shot went off.
local function fireAt(unit, target, now, state)
	if now - unit.LastAttack < unit.Stats.AttackCooldown then
		return false
	end
	unit.LastAttack = now
	target.Humanoid:TakeDamage(attackDamage(unit, state, target))
	target.AttackedBy = unit
	target.AttackedAt = now
	AnimationSystem.PlayAttack(unit)
	EffectsSystem.Tracer(
		unit.Root.Position + Vector3.new(0, 1.5, 0),
		target.Root.Position + Vector3.new(0, 1.5, 0),
		teamColor(unit)
	)
	return true
end

-- Engage a target with a gun: shoot at range, back off if too close, close in
-- if out of range, and move to the last-known spot if we've lost sight.
local function engage(unit, target, now, state)
	if not target or not target.Alive then
		return false
	end
	if not isVisible(state, target) then
		moveTo(unit, believedPos(state, target), now)
		return true
	end

	local stats = unit.Stats
	local myPos = unit.Root.Position
	local targetPos = target.Root.Position
	local dist = (targetPos - myPos).Magnitude
	local minRange = stats.MinRange or 0

	if dist < minRange then
		-- Too close: back away while keeping it in our sights.
		faceToward(unit, targetPos)
		local away = myPos - targetPos
		away = Vector3.new(away.X, 0, away.Z)
		away = away.Magnitude > 0.01 and away.Unit or Vector3.new(0, 0, 1)
		moveTo(unit, myPos + away * 16, now)
	elseif dist <= stats.AttackRange and NavigationSystem.HasLineOfSight(myPos, targetPos) then
		unit.Humanoid:Move(Vector3.zero)
		faceToward(unit, targetPos)
		fireAt(unit, target, now, state)
	else
		moveTo(unit, targetPos, now)
	end
	return true
end

-- Nearest KNOWN enemy near a position (state.Known holds only enemies).
local function nearestEnemy(state, position, radius)
	local known = state and state.Known
	if not known then
		return nil, math.huge
	end
	local nearest, nearestDist = nil, math.huge
	SpatialGrid.ForNear(position, radius or 70, function(other)
		if other.Alive and known[other] then
			local dist = (believedPos(state, other) - position).Magnitude
			if dist < nearestDist then
				nearestDist = dist
				nearest = other
			end
		end
	end)
	return nearest, nearestDist
end

-- No enemy in view: advance on the discovered enemy base and shoot it down.
local function assault(unit, state, now)
	local base = state and state.AssaultBase
	if not base or not base.Alive then
		if state and state.EnemyCenter then
			moveTo(unit, state.EnemyCenter, now)
		end
		return
	end
	local pos = unit.Root.Position
	local flat = Vector3.new(base.Position.X - pos.X, 0, base.Position.Z - pos.Z)
	if flat.Magnitude <= unit.Stats.AttackRange then
		unit.Humanoid:Move(Vector3.zero)
		faceToward(unit, base.Position)
		if now - unit.LastAttack >= unit.Stats.AttackCooldown then
			unit.LastAttack = now
			BaseSystem.Damage(base, unit.Stats.AttackDamage)
			AnimationSystem.PlayAttack(unit)
			EffectsSystem.Tracer(pos + Vector3.new(0, 1.5, 0), base.Position + Vector3.new(0, 2, 0), teamColor(unit))
		end
	else
		moveTo(unit, base.Position, now)
	end
end

-- ---- per-role behavior -----------------------------------------------------

local function leaderAct(unit, now, state)
	if state and state.AllyCenter and state.EnemyCenter then
		local back = state.AllyCenter - state.EnemyCenter
		back = back.Magnitude > 0.01 and back.Unit or Vector3.new(0, 0, 1)
		local danger = state.LeaderThreatened or state.Stance == "Defensive"
		local standoff = danger and Config.Leader.RetreatStandoff or Config.Leader.Standoff
		moveTo(unit, state.AllyCenter + back * standoff, now)
	end
	-- Fire on the nearest visible enemy in range.
	if unit.Target and isVisible(state, unit.Target) then
		local dist = (unit.Target.Root.Position - unit.Root.Position).Magnitude
		if dist <= unit.Stats.AttackRange and NavigationSystem.HasLineOfSight(unit.Root.Position, unit.Target.Root.Position) then
			faceToward(unit, unit.Target.Root.Position)
			fireAt(unit, unit.Target, now, state)
		end
	end
end

local function guardAct(unit, now, state)
	local leader = state and state.Leader
	if not leader or not leader.Alive then
		if unit.Target then
			engage(unit, unit.Target, now, state)
		else
			assault(unit, state, now)
		end
		return
	end

	local leaderPos = leader.Root.Position
	local threat, threatDist = nearestEnemy(state, leaderPos, Config.Leader.GuardEngageRange)
	if threat and threatDist <= Config.Leader.GuardEngageRange then
		engage(unit, threat, now, state)
		return
	end

	local ringUp = state.LeaderThreatened or state.Stance == "Defensive"
	if ringUp then
		local count = math.max(1, Config.Leader.GuardSquadSize)
		local angle = (unit.GuardIndex / count) * math.pi * 2
		moveTo(unit, leaderPos + Vector3.new(math.cos(angle), 0, math.sin(angle)) * Config.Leader.GuardRingRadius, now)
	else
		local toEnemy = (state.EnemyCenter or leaderPos) - leaderPos
		toEnemy = toEnemy.Magnitude > 0.01 and toEnemy.Unit or Vector3.new(0, 0, 1)
		moveTo(unit, leaderPos + toEnemy * Config.Leader.GuardScreenDistance + unit.FormationOffset, now)
	end
end

local function flankAct(unit, now, state)
	if unit.Target then
		engage(unit, unit.Target, now, state)
		return
	end
	if state.Order == "Engage" then
		if state.FocusTarget and state.FocusTarget.Alive then
			moveTo(unit, believedPos(state, state.FocusTarget), now)
		elseif state.FlankPoint then
			moveTo(unit, state.FlankPoint, now)
		else
			assault(unit, state, now)
		end
	else
		moveTo(unit, (state.RallyPoint or state.AllyCenter or unit.Root.Position) + unit.FormationOffset, now)
	end
end

local function scoutAct(unit, now, state)
	local hasIntel = (state and state.KnownList and #state.KnownList > 0)
		or (state and state.AssaultBase and state.AssaultBase.Alive)
	if not hasIntel then
		-- Roam the map to find the enemy (the leader's eyes).
		local center = (state and state.ExplorePoint) or unit.Root.Position
		if not unit.ExploreTarget or (unit.ExploreTarget - unit.Root.Position).Magnitude < 15 then
			local angle = math.random() * math.pi * 2
			local distance = 40 + math.random() * Config.Command.ScoutRoamRadius
			unit.ExploreTarget = center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		end
		unit.WantsSprint = true
		moveTo(unit, unit.ExploreTarget, now)
		return
	end
	if unit.Target then
		engage(unit, unit.Target, now, state)
	else
		assault(unit, state, now)
	end
end

-- Worker: chop the nearest tree, haul wood back to base, repeat. Non-combat.
local function workerAct(unit, now, state)
	local basePos = (state and state.OwnBasePos) or unit.Root.Position
	unit.Carry = unit.Carry or 0

	-- Full load -> return to base and deposit.
	if unit.Carry >= Config.Economy.CarryCapacity then
		if horizontalDist(unit.Root.Position, basePos) <= Config.Economy.DepositRange then
			EconomySystem.Deposit(unit.Team, unit.Carry)
			unit.Carry = 0
			unit.TargetTree = nil
		else
			moveTo(unit, basePos, now)
		end
		return
	end

	-- Find a tree with wood.
	if not unit.TargetTree or unit.TargetTree.wood <= 0 then
		unit.TargetTree = EconomySystem.NearestTree(unit.Root.Position)
	end
	local tree = unit.TargetTree
	if not tree then
		-- Nothing to chop: wait near base.
		if horizontalDist(unit.Root.Position, basePos) > 20 then
			moveTo(unit, basePos, now)
		end
		return
	end

	if horizontalDist(unit.Root.Position, tree.pos) <= 6 then
		unit.Humanoid:Move(Vector3.zero)
		faceToward(unit, tree.pos)
		if now - (unit.LastMine or 0) >= Config.Economy.MineInterval then
			unit.LastMine = now
			unit.Carry += EconomySystem.Mine(tree, Config.Economy.MinePerTick)
			AnimationSystem.PlayAttack(unit) -- chopping swing
			if tree.wood <= 0 then
				unit.TargetTree = nil
			end
		end
	else
		moveTo(unit, tree.pos, now)
	end
end

-- ---- dispatch --------------------------------------------------------------

function CombatSystem.Act(unit, now, state)
	if unit.IsLeader then
		leaderAct(unit, now, state)
		return
	end
	if unit.Role == "Worker" then
		workerAct(unit, now, state)
		return
	end
	if unit.Role == "Scout" then
		scoutAct(unit, now, state)
		return
	end
	if unit.Role == "Guard" then
		guardAct(unit, now, state)
		return
	end
	if unit.Role == "Flank" then
		flankAct(unit, now, state)
		return
	end

	-- Main line. Shoot if we have a target; otherwise advance, or assault the base.
	if unit.Target then
		engage(unit, unit.Target, now, state)
	elseif state and state.Order == "Advance" then
		local rally = (state.Stance == "Defensive" and state.HoldPoint) or state.RallyPoint or state.AllyCenter
		moveTo(unit, (rally or unit.Root.Position) + unit.FormationOffset, now)
	else
		assault(unit, state, now)
	end
end

return CombatSystem
