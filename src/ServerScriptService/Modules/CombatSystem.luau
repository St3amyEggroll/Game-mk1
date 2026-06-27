--[[
	CombatSystem
	------------
	One unit's "turn", driven by its role + the team's stance/order:

	  • Leader  — directs from the back; pulls back further when threatened;
	              self-defends only.
	  • Guard   — screens the Leader, or forms a defensive RING when the Leader
	              is threatened; intercepts anything near him.
	  • Flank   — stays with the line while advancing, then peels off ONCE
	              engaged and drives at the enemy's rear / leader.
	  • Main    — advances (to the rally or a defensive hold line), then engages.

	On a Retreat order everyone falls back to the rear regroup point.

	Movement routes around obstacles (NavigationSystem), steers apart from
	allies (separation) and away from hazards. Attacks record who hit whom so
	the TargetingSystem can do threat assessment.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local NavigationSystem = require(script.Parent.NavigationSystem)
local HazardSystem = require(script.Parent.HazardSystem)

local CombatSystem = {}

function CombatSystem.RefreshObstacleFilter()
	NavigationSystem.Refresh()
end

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

-- Route around obstacles, then steer apart from allies and away from hazards.
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
		-- Record the threat so the victim can prioritize us back.
		target.AttackedBy = unit
		target.AttackedAt = now
	end
end

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

-- Close on a target and attack it.
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

-- Leader: direct from the back; pull back further when threatened; self-defend.
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

	local nearest, dist = nearestEnemy(state, unit.Root.Position)
	if nearest and dist <= unit.Stats.AttackRange then
		swingAt(unit, nearest, now, state)
	end
end

-- Guard: screen the Leader, or ring up around him when he's threatened.
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
		-- Evenly spaced ring around the Leader.
		local count = math.max(1, Config.Leader.GuardSquadSize)
		local angle = (unit.GuardIndex / count) * math.pi * 2
		local spot = leaderPos + Vector3.new(math.cos(angle), 0, math.sin(angle)) * Config.Leader.GuardRingRadius
		moveTo(unit, spot, allies, now)
	else
		-- Screen the front (between Leader and enemy).
		local toEnemy = (state.EnemyCenter or leaderPos) - leaderPos
		toEnemy = toEnemy.Magnitude > 0.01 and toEnemy.Unit or Vector3.new(0, 0, 1)
		moveTo(unit, leaderPos + toEnemy * Config.Leader.GuardScreenDistance + unit.FormationOffset, allies, now)
	end
end

-- Flank: hold with the line while advancing; once engaged, drive at the
-- enemy's rear / leader to pour through the gap.
local function flankAct(unit, now, state, allies)
	if state.Order == "Engage" then
		if unit.Target and unit.Target.Alive then
			local dist = (unit.Target.Root.Position - unit.Root.Position).Magnitude
			if dist <= unit.Stats.AttackRange then
				swingAt(unit, unit.Target, now, state)
				return
			end
		end
		-- Push toward the enemy leader if known, else the flank point.
		local drive = (state.FocusTarget and state.FocusTarget.Alive and state.FocusTarget.Root.Position)
			or state.FlankPoint
			or unit.Root.Position
		moveTo(unit, drive, allies, now)
	else
		-- Advancing: stay in formation with the main line.
		local rally = state.RallyPoint or state.AllyCenter or unit.Root.Position
		moveTo(unit, rally + unit.FormationOffset, allies, now)
	end
end

function CombatSystem.Act(unit, now, state)
	local allies = (state and state.Allies) or {}

	if unit.IsLeader then
		leaderAct(unit, now, state, allies)
		return
	end

	-- Retreat overrides roles: everyone falls back, fighting only in reach.
	if state and state.Order == "Retreat" then
		if unit.Role == "Guard" then
			guardAct(unit, now, state, allies)
		else
			moveTo(unit, (state.RearPoint or state.AllyCenter) + unit.FormationOffset, allies, now)
			local nearest, dist = nearestEnemy(state, unit.Root.Position)
			if nearest and dist <= unit.Stats.AttackRange then
				swingAt(unit, nearest, now, state)
			end
		end
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

	-- Main line. Advance to the rally (or a defensive hold line), then engage.
	if state and state.Order == "Advance" then
		local rally = (state.Stance == "Defensive" and state.HoldPoint) or state.RallyPoint
		if rally then
			moveTo(unit, rally + unit.FormationOffset, allies, now)
			return
		end
	end

	fightTarget(unit, unit.Target, now, state, allies)
end

return CombatSystem
