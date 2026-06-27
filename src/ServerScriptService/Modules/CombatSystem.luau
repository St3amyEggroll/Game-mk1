--[[
	CombatSystem
	------------
	One unit's "turn", now aware of the team's order:

	  • Advance — march to your slot in the formation (RallyPoint + your offset),
	    so the army moves as a coordinated block instead of a loose blob.
	  • Engage  — close on your target, face it, and swing on cooldown.

	Extra smarts layered in:
	  • Separation  — gently push off allies so units don't stack on one spot.
	  • Facing      — turn to look at whoever you're hitting.
	  • Morale      — hit harder near a living Leader, weaker with none.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local UnitManager = require(script.Parent.UnitManager)

local CombatSystem = {}

-- Sum a small push-away from any allies crowding this unit.
local function separation(unit)
	local push = Vector3.zero
	local pos = unit.Root.Position
	local radius = Config.Command.SeparationRadius
	for _, ally in UnitManager.GetAllies(unit) do
		local offset = pos - ally.Root.Position
		local dist = offset.Magnitude
		if dist > 0 and dist < radius then
			push += offset.Unit * (radius - dist)
		end
	end
	return push
end

-- Walk toward a goal, nudged apart from crowding allies.
local function moveTo(unit, goal)
	unit.Humanoid:MoveTo(goal + separation(unit))
end

-- Snap to face a point (used while attacking, when we're standing still).
local function faceToward(unit, targetPos)
	local pos = unit.Root.Position
	local look = Vector3.new(targetPos.X, pos.Y, targetPos.Z)
	if (look - pos).Magnitude > 0.1 then
		unit.Root.CFrame = CFrame.lookAt(pos, look)
	end
end

-- Damage after morale: bonus near a living Leader, penalty if leaderless.
local function attackDamage(unit, state)
	local damage = unit.Stats.AttackDamage
	local leader = state and state.Leader
	if leader and leader.Alive then
		local dist = (leader.Root.Position - unit.Root.Position).Magnitude
		if dist <= Config.Command.MoraleRange then
			damage *= Config.Command.MoraleDamageBonus
		end
	elseif Config.Leader.Enabled and not leader then
		damage *= Config.Command.LeaderlessDamagePenalty
	end
	return damage
end

function CombatSystem.Act(unit, now, state)
	-- ADVANCE: hold formation and march toward the rally point as a group.
	if state and state.Order == "Advance" and state.RallyPoint then
		moveTo(unit, state.RallyPoint + unit.FormationOffset)
		return
	end

	-- ENGAGE (or no orders): fight your target.
	local target = unit.Target
	if not target or not target.Alive then
		return
	end

	local pos = unit.Root.Position
	local targetPos = target.Root.Position
	local dist = (targetPos - pos).Magnitude
	local stats = unit.Stats

	if dist > stats.AttackRange then
		-- Out of range: close the distance.
		moveTo(unit, targetPos)
	else
		-- In range: stop, face the enemy, and swing on cooldown.
		unit.Humanoid:Move(Vector3.zero)
		faceToward(unit, targetPos)
		if now - unit.LastAttack >= stats.AttackCooldown then
			unit.LastAttack = now
			target.Humanoid:TakeDamage(attackDamage(unit, state))
		end
	end
end

return CombatSystem
