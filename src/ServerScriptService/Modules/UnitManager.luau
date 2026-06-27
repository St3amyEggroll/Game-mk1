--[[
	UnitManager
	-----------
	The heart of the data-oriented design. Instead of giving every soldier its
	own Script, we keep ONE table (UnitManager.Units) where each soldier is a
	plain Lua row holding its model + state. The main loop walks this table.

	This is what lets us scale to 100v100 later: 200 table rows is cheap;
	200 running Scripts is not.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local UnitManager = {}

-- The master list. Each entry is a "unit" table (see Register below).
UnitManager.Units = {}

local nextId = 0

-- Turn a freshly spawned model into a tracked unit.
function UnitManager.Register(model, teamKey, unitType)
	nextId += 1

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")

	local unit = {
		Id = nextId,
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Team = teamKey, -- "A" or "B"
		Type = unitType, -- "Melee" or "Ranged"
		Stats = Config.UnitTypes[unitType],
		Target = nil, -- another unit table, chosen by TargetingSystem
		LastAttack = 0, -- timestamp of last hit (for cooldown)
		Alive = true,
	}

	-- When the Humanoid dies, flag the row and turn the model into a corpse
	-- that cleans itself up. The main loop prunes flagged rows next tick.
	humanoid.Died:Connect(function()
		unit.Alive = false
		task.delay(Config.CorpseLifetime, function()
			if model and model.Parent then
				model:Destroy()
			end
		end)
	end)

	table.insert(UnitManager.Units, unit)
	return unit
end

-- All living enemies of the given unit.
function UnitManager.GetEnemies(unit)
	local enemies = {}
	for _, other in UnitManager.Units do
		if other.Alive and other.Team ~= unit.Team then
			table.insert(enemies, other)
		end
	end
	return enemies
end

-- A set of team keys that still have at least one living soldier.
function UnitManager.TeamsAlive()
	local teams = {}
	for _, unit in UnitManager.Units do
		if unit.Alive then
			teams[unit.Team] = true
		end
	end
	return teams
end

-- Drop dead rows from the list (their models become self-cleaning corpses).
function UnitManager.RemoveDead()
	for i = #UnitManager.Units, 1, -1 do
		if not UnitManager.Units[i].Alive then
			table.remove(UnitManager.Units, i)
		end
	end
end

-- Wipe everything before a fresh battle.
function UnitManager.Clear()
	for _, unit in UnitManager.Units do
		if unit.Model and unit.Model.Parent then
			unit.Model:Destroy()
		end
	end
	UnitManager.Units = {}
	nextId = 0
end

return UnitManager
