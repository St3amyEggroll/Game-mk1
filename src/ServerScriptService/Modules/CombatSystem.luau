--[[
	CombatSystem
	------------
	One unit's "turn", driven by its role and the team's order:

	  • Leader  — hangs back and directs; fights only in self-defense.
	  • Guard   — screens the Leader; intercepts enemies that get close to it.
	  • Flank   — swings wide to the FlankPoint, then hits the enemy's side.
	  • Main    — advances in formation, then engages head-on.

	Movement goes through NavigationSystem (routes around obstacles) and is
	nudged apart by separation. Morale boosts damage near a living Leader.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local NavigationSystem = require(script.Parent.NavigationSystem)

local CombatSystem = {}

function CombatSystem.RefreshObstacleFilter()
	NavigationSystem.Refresh()
end

-- Push away from any allies crowding this unit (uses the tick's cached list).
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

-- Walk toward a goal: route around obstacles, then nudge apart from allies.
local function moveTo(unit, goal, allies, now)
	local point = NavigationSystem.NextPoint(unit, goal, now)
	unit.Humanoid:MoveTo(point + separation(unit, allies))
end

-- Snap to face a point (used while standing and swinging).
local function faceToward(unit, targetPos)
	local pos = unit.Root.Position
	local look = Vector3.new(targetPos.X, pos.Y, targetPos.Z)
	if (look - pos).Magnitude > 0.1 then
		unit.Root.CFrame = CFrame.lookAt(pos, look)
	end
end

-- Damage after morale.
local function attackDamage(unit, state)
	local damage = unit.Stats.AttackDamage
	local leader = state and state.Leader
	if leader and leader.Alive then
		if (leader.Root.Position - unit.Root.Position).Magnitude <= Config.Command.MoraleRange then
			damage *= Config.Command.MoraleDamageBonus
		end
	elseif Config.Leader.Enabled and not leader then
		damage *= Config.Command.LeaderlessDamagePenalty
	end
	return damage
end

local function swingAt(unit, target, now, state)
	faceToward(unit, target.Root.Position)
	unit.Humanoid:Move(Vector3.zero)
	if now - unit.LastAttack >= unit.Stats.AttackCooldown then
		unit.LastAttack = now
		target.Humanoid:TakeDamage(attackDamage(unit, state))
	end
end

-- Nearest living enemy to a position, from the tick's cached enemy list.
local function nearestEnemy(state, position)
	local nearest, nearestDist = nil, math.huge
	for _, enemy in (state and state.Enemies) or {} do
		local dist = (enemy.Root.Position - position).Magnitude
		if dist < nearestDist then
			nearestDist = dist
			nearest = enemy
		end
	end
	return nearest, nearestDist
end

-- Close on a target and attack it (shared by Main/Flank engage and intercepts).
local function fightTarget(unit, target, now, state, allies)
	if not target or not target.Alive then
		return
	end
	local dist = (target.Root.Position - unit.Root.Position).Magnitude
	if dist > unit.Stats.AttackRange then
		moveTo(unit, target.Root.Position, allies, now)
	else
		swingAt(unit, target, now, state)
	end
end

-- Leader: stay behind the army; swing only if an enemy is right on top of you.
local function leaderAct(unit, now, state, allies)
	if state and state.AllyCenter and state.EnemyCenter then
		local back = state.AllyCenter - state.EnemyCenter
		back = back.Magnitude > 0.01 and back.Unit or Vector3.new(0, 0, 1)
		moveTo(unit, state.AllyCenter + back * Config.Leader.Standoff, allies, now)
	end

	local nearest, dist = nearestEnemy(state, unit.Root.Position)
	if nearest and dist <= unit.Stats.AttackRange then
		swingAt(unit, nearest, now, state)
	end
end

-- Guard: hold a screen in front of the Leader; intercept nearby threats.
local function guardAct(unit, now, state, allies)
	local leader = state and state.Leader
	if not leader or not leader.Alive then
		-- No one left to guard — fight like a normal soldier.
		fightTarget(unit, unit.Target, now, state, allies)
		return
	end

	local leaderPos = leader.Root.Position
	local threat, threatDist = nearestEnemy(state, leaderPos)

	if threat and threatDist <= Config.Leader.GuardEngageRange then
		-- Enemy near the Leader: intercept it.
		fightTarget(unit, threat, now, state, allies)
	else
		-- Otherwise screen the Leader between it and the enemy.
		local toEnemy = (state.EnemyCenter or leaderPos) - leaderPos
		toEnemy = toEnemy.Magnitude > 0.01 and toEnemy.Unit or Vector3.new(0, 0, 1)
		moveTo(unit, leaderPos + toEnemy * Config.Leader.GuardScreenDistance + unit.FormationOffset, allies, now)
	end
end

function CombatSystem.Act(unit, now, state)
	local allies = (state and state.Allies) or {}

	if unit.IsLeader then
		leaderAct(unit, now, state, allies)
		return
	end

	if unit.Role == "Guard" then
		guardAct(unit, now, state, allies)
		return
	end

	-- ADVANCE: march to formation. Flankers head wide to the flank point.
	if state and state.Order == "Advance" then
		local rally = (unit.Role == "Flank" and state.FlankPoint) or state.RallyPoint
		if rally then
			moveTo(unit, rally + unit.FormationOffset, allies, now)
			return
		end
	end

	-- ENGAGE: fight your target.
	fightTarget(unit, unit.Target, now, state, allies)
end

return CombatSystem
