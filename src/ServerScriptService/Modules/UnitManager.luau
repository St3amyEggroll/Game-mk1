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
local EffectsSystem = require(script.Parent.EffectsSystem)
local Signals = require(script.Parent.Signals)

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
		IsLeader = false, -- set by SpawnSystem for the team's commander
		Role = "Main", -- "Main" | "Flank" | "Guard", set by SpawnSystem
		GuardIndex = 0, -- this guard's slot in the defensive ring
		FormationOffset = Vector3.zero, -- this unit's slot in the marching block
		Nav = nil, -- pathfinding state, managed by NavigationSystem
		AttackedBy = nil, -- last enemy that hit us (for threat assessment)
		AttackedAt = 0, -- when that hit landed
		CavalryPhase = "Charge", -- "Charge" | "Peel", for hit-and-run cavalry
		PeelUntil = 0, -- timestamp until which cavalry rides away
		PeelPoint = nil, -- where cavalry retreats to before re-charging
	}

	-- When the Humanoid dies: flag the row, play death FX, tell the HUD, and
	-- leave a self-cleaning corpse. The main loop prunes flagged rows next tick.
	humanoid.Died:Connect(function()
		if not unit.Alive then
			return
		end
		unit.Alive = false
		EffectsSystem.PlayDeath(unit)
		Signals.Fire({ kind = "kill", team = unit.Team, leader = unit.IsLeader })
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
	return UnitManager.GetEnemyUnits(unit.Team)
end

-- All living units NOT on the given team.
function UnitManager.GetEnemyUnits(teamKey)
	local enemies = {}
	for _, other in UnitManager.Units do
		if other.Alive and other.Team ~= teamKey then
			table.insert(enemies, other)
		end
	end
	return enemies
end

-- All living units ON the given team.
function UnitManager.GetTeamUnits(teamKey)
	local team = {}
	for _, other in UnitManager.Units do
		if other.Alive and other.Team == teamKey then
			table.insert(team, other)
		end
	end
	return team
end

-- Living teammates of a unit (excluding itself).
function UnitManager.GetAllies(unit)
	local allies = {}
	for _, other in UnitManager.Units do
		if other ~= unit and other.Alive and other.Team == unit.Team then
			table.insert(allies, other)
		end
	end
	return allies
end

-- The living Leader of a team, or nil if it has fallen.
function UnitManager.GetLeader(teamKey)
	for _, other in UnitManager.Units do
		if other.Alive and other.Team == teamKey and other.IsLeader then
			return other
		end
	end
	return nil
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
