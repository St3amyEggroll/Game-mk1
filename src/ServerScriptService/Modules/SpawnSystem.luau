--[[
	SpawnSystem
	-----------
	Builds each army: one Leader plus its soldiers, arranged in a formation
	near the team's spawn marker. Each unit is given a FormationOffset (its slot
	in the marching block) and registered with the UnitManager.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local PhysicsService = game:GetService("PhysicsService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local UnitManager = require(script.Parent.UnitManager)
local HealthBar = require(script.Parent.HealthBar)

local SpawnSystem = {}

-- Soldiers share a collision group that DOESN'T collide with itself. This stops
-- hundreds of units from shoving each other around — a big perf + look win.
-- They still collide with the ground and any obstacles you place.
local UNITS_GROUP = "BattleUnits"
local collisionReady = false
local function ensureCollisionGroup()
	if collisionReady then
		return
	end
	pcall(function()
		PhysicsService:RegisterCollisionGroup(UNITS_GROUP)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(UNITS_GROUP, UNITS_GROUP, Config.UnitsCollide)
	end)
	collisionReady = true
end

-- Workspace/Units holds all live soldiers at runtime. Created if missing.
local function getUnitsFolder()
	local folder = Workspace:FindFirstChild("Units")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Units"
		folder.Parent = Workspace
	end
	return folder
end

-- Paint every part its team color and put it in the no-self-collide group.
local function dressModel(model, color)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = UNITS_GROUP
			if part.Name ~= "Head" then
				part.Color = color
			end
		end
	end
end

-- A glow so you can spot the Leader on the field.
local function addGlow(model, color)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.FillTransparency = 0.5
	highlight.OutlineColor = color
	highlight.Parent = model
end

-- The slot offset (centered grid) for the Nth unit in the army.
local function formationOffset(slotIndex)
	local cols = Config.Command.FormationColumns
	local spacing = Config.Command.FormationSpacing
	local col = slotIndex % cols
	local row = math.floor(slotIndex / cols)
	return Vector3.new((col - (cols - 1) / 2) * spacing, 0, row * spacing)
end

-- Expand the composition (plus a Leader) into a flat list of soldiers to spawn,
-- and assign roles: some Guards screen the Leader, some Flankers swing wide,
-- the rest are Main line.
local function buildRoster()
	local roster = {}
	if Config.Leader.Enabled then
		table.insert(roster, { Type = "Melee", IsLeader = true, Role = "Leader" })
	end

	local soldiers = {}
	for _, group in Config.Composition do
		for _ = 1, group.Count do
			table.insert(soldiers, { Type = group.Type, IsLeader = false, Role = "Main" })
		end
	end

	-- Guard/Flank roles are assigned among the LINE soldiers only. Cavalry get
	-- their own role (hit-and-run), they don't guard or hold formation.
	local guards = Config.Leader.Enabled and Config.Leader.GuardSquadSize or 0
	local flankers = Config.Command.FlankSquadSize
	local lineCount = 0
	for _, soldier in soldiers do
		if soldier.Type == "Cavalry" then
			soldier.Role = "Cavalry"
		else
			lineCount += 1
			if lineCount <= guards then
				soldier.Role = "Guard"
				soldier.GuardIndex = lineCount - 1 -- 0-based slot in the guard ring
			elseif lineCount <= guards + flankers then
				soldier.Role = "Flank"
			end
		end
		table.insert(roster, soldier)
	end
	return roster
end

-- Spawn one team's Leader + soldiers.
local function spawnTeam(teamKey, teamData, assets, unitsFolder)
	local marker = Workspace:FindFirstChild(teamData.SpawnMarker)
	if not marker then
		warn(("[SpawnSystem] No spawn marker named '%s' in Workspace."):format(teamData.SpawnMarker))
		return
	end

	-- Face the army toward the middle of the map.
	local facing = CFrame.lookAt(marker.Position, Vector3.new(0, marker.Position.Y, 0))

	local roster = buildRoster()
	for slotIndex, slot in roster do
		local stats = Config.UnitTypes[slot.Type]
		-- Use the type's rig; fall back to MeleeUnit so a missing rig (e.g. you
		-- haven't built CavalryUnit yet) doesn't silently shrink the army.
		local template = assets:FindFirstChild(stats.RigName) or assets:FindFirstChild("MeleeUnit")
		if not template then
			warn(("[SpawnSystem] No rig '%s' (and no MeleeUnit fallback) in ReplicatedStorage/Assets."):format(stats.RigName))
			continue
		end

		-- Leader sits at the army's center (it'll retreat behind on its own).
		local offset = slot.IsLeader and Vector3.zero or formationOffset(slotIndex - 1)

		local model = template:Clone()
		-- Lift slightly so they don't spawn clipped into the floor.
		model:PivotTo(facing * CFrame.new(offset + Vector3.new(0, 3, 0)))
		dressModel(model, teamData.Color)

		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local maxHealth = stats.MaxHealth
		if slot.IsLeader then
			maxHealth = math.floor(stats.MaxHealth * Config.Leader.HealthMultiplier)
			model:ScaleTo(Config.Leader.Scale)
			addGlow(model, Config.Leader.GlowColor)
		end
		humanoid.MaxHealth = maxHealth
		humanoid.Health = maxHealth
		humanoid.WalkSpeed = stats.WalkSpeed

		model.Parent = unitsFolder
		HealthBar.Attach(model, humanoid, slot.IsLeader)

		local unit = UnitManager.Register(model, teamKey, slot.Type)
		unit.IsLeader = slot.IsLeader
		unit.Role = slot.Role
		unit.GuardIndex = slot.GuardIndex or 0
		unit.FormationOffset = offset
	end
end

-- Spawn both armies.
function SpawnSystem.SpawnAllTeams()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		warn("[SpawnSystem] No 'Assets' folder in ReplicatedStorage. Build your rigs there.")
		return
	end

	ensureCollisionGroup()
	local unitsFolder = getUnitsFolder()
	for teamKey, teamData in Config.Teams do
		spawnTeam(teamKey, teamData, assets, unitsFolder)
	end
end

return SpawnSystem
