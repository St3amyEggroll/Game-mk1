--[[
	CombatSystem
	------------
	One unit's "turn": walk toward your target, and once you're in range, stop
	and attack on a cooldown. Milestone 2 is melee only, but this same shape
	handles ranged later — only AttackRange and what happens on-hit change.
]]

local CombatSystem = {}

-- `now` is a shared timestamp (os.clock) passed in by the main loop so every
-- unit measures its cooldown against the same clock.
function CombatSystem.Act(unit, now)
	local target = unit.Target
	if not target or not target.Alive then
		return
	end

	local pos = unit.Root.Position
	local targetPos = target.Root.Position
	local dist = (targetPos - pos).Magnitude
	local stats = unit.Stats

	if dist > stats.AttackRange then
		-- Out of range: march straight at the target. Flat battlefield, so no
		-- pathfinding needed yet — that comes when we add obstacles.
		unit.Humanoid:MoveTo(targetPos)
	else
		-- In range: stop moving and swing on cooldown.
		unit.Humanoid:MoveTo(pos)
		if now - unit.LastAttack >= stats.AttackCooldown then
			unit.LastAttack = now
			target.Humanoid:TakeDamage(stats.AttackDamage)
		end
	end
end

return CombatSystem
