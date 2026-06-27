--[[
	CombatSystem
	------------
	One unit's "turn", driven by the team's order:

	  • Leaders  hang back behind the army and direct; they only fight in
	    self-defense if an enemy reaches them.
	  • Soldiers Advance to their formation slot, then Engage: close on the
	    target, face it, and swing on cooldown.

	Movement is steered by two cheap forces so it reads as smart, not a blob:
	  • Separation     — push off crowding allies (no more shoving piles).
	  • ObstacleAvoid  — raycast ahead and veer around walls/cover. This is what
	    makes the army ready for the obstacles you're adding.

	Plus morale: hit harder near a living Leader, weaker if the Leader is dead.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local CombatSystem = {}

-- Raycasts for obstacle avoidance ignore the soldiers themselves.
local avoidParams = RaycastParams.new()
avoidParams.FilterType = Enum.RaycastFilterType.Exclude
avoidParams.FilterDescendantsInstances = {}

-- Call at the start of each battle so avoidance ignores live units.
function CombatSystem.RefreshObstacleFilter()
	local unitsFolder = Workspace:FindFirstChild("Units")
	avoidParams.FilterDescendantsInstances = unitsFolder and { unitsFolder } or {}
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

-- Look ahead; if something's in the way, steer toward the clearer side.
local function obstacleAvoid(unit, desiredDir)
	if desiredDir.Magnitude < 0.01 then
		return Vector3.zero
	end
	local dir = desiredDir.Unit
	local origin = unit.Root.Position
	local look = Config.Command.ObstacleLookAhead

	if not Workspace:Raycast(origin, dir * look, avoidParams) then
		return Vector3.zero -- clear path
	end

	-- Blocked ahead: test left/right and veer to whichever is open.
	local left = Vector3.new(-dir.Z, 0, dir.X)
	local leftBlocked = Workspace:Raycast(origin, left * look, avoidParams)
	local rightBlocked = Workspace:Raycast(origin, -left * look, avoidParams)

	local steer
	if leftBlocked and rightBlocked then
		steer = -dir -- boxed in; back off
	elseif leftBlocked then
		steer = -left
	else
		steer = left
	end
	return steer * Config.Command.ObstacleAvoidStrength
end

-- Walk toward a goal, nudged by separation + obstacle avoidance.
local function moveTo(unit, goal, allies)
	local desired = goal - unit.Root.Position
	local steer = separation(unit, allies) + obstacleAvoid(unit, desired)
	unit.Humanoid:MoveTo(goal + steer)
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

-- Leader: stay behind the army, only swing if an enemy is right on top of you.
local function leaderAct(unit, now, state, allies)
	if state and state.AllyCenter and state.EnemyCenter then
		local back = state.AllyCenter - state.EnemyCenter
		back = back.Magnitude > 0.01 and back.Unit or Vector3.new(0, 0, 1)
		moveTo(unit, state.AllyCenter + back * Config.Leader.Standoff, allies)
	end

	-- Self-defense: nearest enemy within reach only.
	local nearest, nearestDist = nil, math.huge
	for _, enemy in (state and state.Enemies) or {} do
		local dist = (enemy.Root.Position - unit.Root.Position).Magnitude
		if dist < nearestDist then
			nearestDist = dist
			nearest = enemy
		end
	end
	if nearest and nearestDist <= unit.Stats.AttackRange then
		swingAt(unit, nearest, now, state)
	end
end

function CombatSystem.Act(unit, now, state)
	local allies = (state and state.Allies) or {}

	if unit.IsLeader then
		leaderAct(unit, now, state, allies)
		return
	end

	-- ADVANCE: march to your formation slot as a group.
	if state and state.Order == "Advance" and state.RallyPoint then
		moveTo(unit, state.RallyPoint + unit.FormationOffset, allies)
		return
	end

	-- ENGAGE: fight your target.
	local target = unit.Target
	if not target or not target.Alive then
		return
	end

	local dist = (target.Root.Position - unit.Root.Position).Magnitude
	if dist > unit.Stats.AttackRange then
		moveTo(unit, target.Root.Position, allies)
	else
		swingAt(unit, target, now, state)
	end
end

return CombatSystem
