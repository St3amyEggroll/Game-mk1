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
local AnimationSystem = require(script.Parent.AnimationSystem)

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

-- A simple cosmetic horse welded under a cavalry rider. Massless + no-collide
-- so it doesn't affect physics or pathfinding at all.
local function attachHorse(model)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local brown = Color3.fromRGB(110, 70, 40)
	local dark = Color3.fromRGB(70, 45, 28)

	local function piece(size, offset, color)
		local part = Instance.new("Part")
		part.Size = size
		part.Color = color
		part.Material = Enum.Material.SmoothPlastic
		part.Massless = true
		part.CanCollide = false
		part.CanQuery = false
		part.CollisionGroup = UNITS_GROUP
		part.CFrame = hrp.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hrp
		weld.Part1 = part
		part.Parent = model
		weld.Parent = part
	end

	piece(Vector3.new(1.6, 1.4, 4), CFrame.new(0, -1.4, -0.3), brown) -- body
	piece(Vector3.new(1, 1.7, 1), CFrame.new(0, -0.4, -2.2), brown) -- neck
	piece(Vector3.new(0.9, 0.9, 1.6), CFrame.new(0, 0.1, -2.9), brown) -- head
	for _, x in { -0.6, 0.6 } do
		for _, z in { -1.4, 1.4 } do
			piece(Vector3.new(0.4, 2, 0.4), CFrame.new(x, -2.6, z), dark) -- legs
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

-- A flat outline of the unit's field-of-view on the ground, welded so it turns
-- with the unit. Created invisible (Transparency = 1); the client reveals it in
-- fog view (V). Forward for an R6 root is its LookVector (the -Z axis).
local function attachVisionCone(model, stats, color)
	if not Config.Vision.ShowCones then
		return
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local fov = math.rad(stats.FOV or 160)
	local range = stats.SightRange or 40
	local groundY = -2.6 -- drop the outline down near the floor

	local cone = Instance.new("Model")
	cone.Name = "VisionCone"

	local function pointAt(angle)
		return Vector3.new(-math.sin(angle) * range, groundY, -math.cos(angle) * range)
	end

	local function segment(a, b)
		local mid = (a + b) / 2
		local len = math.max(0.1, (b - a).Magnitude)
		local part = Instance.new("Part")
		part.Size = Vector3.new(0.25, 0.06, len)
		part.CanCollide = false
		part.CanQuery = false
		part.Massless = true
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = color
		part.Transparency = 1 -- hidden until the client reveals it in fog view
		part.CollisionGroup = UNITS_GROUP
		part.CFrame = hrp.CFrame * CFrame.lookAt(mid, b)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hrp
		weld.Part1 = part
		part.Parent = cone
		weld.Parent = part
	end

	local apex = Vector3.new(0, groundY, 0)
	local segments = 6
	local prev = pointAt(-fov / 2)
	segment(apex, prev) -- left edge
	for i = 1, segments do
		local angle = -fov / 2 + fov * (i / segments)
		local cur = pointAt(angle)
		segment(prev, cur) -- arc
		prev = cur
	end
	segment(apex, prev) -- right edge

	cone.Parent = model
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
		local t = soldier.Type
		if t == "Cavalry" then
			soldier.Role = "Cavalry"
		elseif t == "Archer" then
			soldier.Role = "Archer"
		elseif t == "Scout" then
			soldier.Role = "Scout"
		else
			-- Melee / Spearman = line infantry, eligible for guard/flank.
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

local function roleForType(unitType)
	if unitType == "Cavalry" then
		return "Cavalry"
	elseif unitType == "Archer" then
		return "Archer"
	elseif unitType == "Scout" then
		return "Scout"
	elseif unitType == "Worker" then
		return "Worker"
	end
	return "Main"
end

local function iconFor(slot)
	if slot.IsLeader then
		return Config.Icons.Leader
	end
	return Config.Icons[slot.Type]
end

-- Build a single soldier from a slot at a given pivot. Shared by initial spawn
-- and base reinforcements.
local function buildUnit(teamKey, teamData, slot, pivot, offset, assets, unitsFolder)
	local stats = Config.UnitTypes[slot.Type]
	-- Use the type's rig; fall back to MeleeUnit if it isn't built yet.
	local template = assets:FindFirstChild(stats.RigName) or assets:FindFirstChild("MeleeUnit")
	if not template then
		warn(("[SpawnSystem] No rig '%s' (and no MeleeUnit fallback) in ReplicatedStorage/Assets."):format(stats.RigName))
		return nil
	end

	local model = template:Clone()
	model:PivotTo(pivot)
	dressModel(model, teamData.Color)
	if slot.Type == "Cavalry" then
		attachHorse(model)
	end

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

	model:SetAttribute("Spotted", false) -- so fog view can ghost never-seen units
	model.Parent = unitsFolder
	HealthBar.Attach(model, humanoid, slot.IsLeader, iconFor(slot))
	attachVisionCone(model, stats, teamData.Color)

	local unit = UnitManager.Register(model, teamKey, slot.Type)
	unit.IsLeader = slot.IsLeader
	unit.Role = slot.Role
	unit.GuardIndex = slot.GuardIndex or 0
	unit.FormationOffset = offset or Vector3.zero
	AnimationSystem.Setup(unit)
	return unit
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

	for slotIndex, slot in buildRoster() do
		local offset = slot.IsLeader and Vector3.zero or formationOffset(slotIndex - 1)
		local pivot = facing * CFrame.new(offset + Vector3.new(0, 3, 0))
		buildUnit(teamKey, teamData, slot, pivot, offset, assets, unitsFolder)
	end
end

-- Spawn a single reinforcement of a type at a position (used by bases).
function SpawnSystem.SpawnOne(teamKey, unitType, position)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end
	ensureCollisionGroup()
	local slot = { Type = unitType, IsLeader = false, Role = roleForType(unitType) }
	local pivot = CFrame.new(position + Vector3.new(0, 3, 0))
	return buildUnit(teamKey, Config.Teams[teamKey], slot, pivot, Vector3.zero, assets, getUnitsFolder())
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
