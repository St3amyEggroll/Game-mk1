--[[
	StaminaSystem
	-------------
	No UI — purely a movement effect. Behaviors set unit.WantsSprint when they
	want to move fast (cavalry charging, soldiers fleeing). This drains stamina;
	walking regenerates it. When it bottoms out the unit is Exhausted and crawls
	until it recovers, so a fleeing soldier eventually gets run down.

	Call Update(unit, dt) once per tick per unit. It sets Humanoid.WalkSpeed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local StaminaSystem = {}

function StaminaSystem.Update(unit, dt)
	local cfg = Config.Stamina
	local wantsSprint = unit.WantsSprint
	unit.WantsSprint = false -- consumed; behaviors re-set it next tick

	local canSprint = wantsSprint and unit.Stamina > 0 and not unit.Exhausted

	if canSprint then
		unit.Stamina = math.max(0, unit.Stamina - cfg.Drain * dt)
		if unit.Stamina <= 0 then
			unit.Exhausted = true
		end
		unit.Humanoid.WalkSpeed = unit.BaseSpeed * cfg.SprintMult
	else
		unit.Stamina = math.min(cfg.Max, unit.Stamina + cfg.Regen * dt)
		if unit.Exhausted and unit.Stamina >= cfg.RecoverThreshold then
			unit.Exhausted = false
		end
		unit.Humanoid.WalkSpeed = unit.Exhausted and (unit.BaseSpeed * cfg.ExhaustedMult) or unit.BaseSpeed
	end
end

return StaminaSystem
