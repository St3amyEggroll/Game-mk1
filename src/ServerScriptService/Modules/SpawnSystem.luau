--[[
	SpawnSystem
	-----------
	Clones rig templates from ReplicatedStorage/Assets and lines each army up
	in a grid near its spawn marker. Registers every spawned unit with the
	UnitManager so the brain loop can drive it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local UnitManager = require(script.Parent.UnitManager)

local SpawnSystem = {}

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

-- Paint every part of a unit its team color so the two sides read clearly.
local function colorModel(model, color)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "Head" then
			part.Color = color
		end
	end
end

-- Spawn one team's full composition at its marker.
local function spawnTeam(teamKey, teamData, assets, unitsFolder)
	local marker = Workspace:FindFirstChild(teamData.SpawnMarker)
	if not marker then
		warn(("[SpawnSystem] No spawn marker named '%s' in Workspace."):format(teamData.SpawnMarker))
		return
	end

	-- Face the units toward the middle of the map (toward world origin-ish).
	local facing = CFrame.lookAt(marker.Position, Vector3.new(0, marker.Position.Y, 0))

	local index = 0
	for _, group in Config.Composition do
		local stats = Config.UnitTypes[group.Type]
		local template = assets:FindFirstChild(stats.RigName)
		if not template then
			warn(("[SpawnSystem] No rig named '%s' in ReplicatedStorage/Assets."):format(stats.RigName))
			continue
		end

		for _ = 1, group.Count do
			-- Grid offset: spread out so they don't spawn inside each other.
			local col = index % Config.SpawnColumns
			local row = math.floor(index / Config.SpawnColumns)
			local localOffset = Vector3.new(
				(col - (Config.SpawnColumns - 1) / 2) * Config.SpawnSpacing,
				3,
				row * Config.SpawnSpacing
			)

			local model = template:Clone()
			model:PivotTo(facing * CFrame.new(localOffset))
			colorModel(model, teamData.Color)
			model.Parent = unitsFolder

			local humanoid = model:FindFirstChildOfClass("Humanoid")
			humanoid.MaxHealth = stats.MaxHealth
			humanoid.Health = stats.MaxHealth
			humanoid.WalkSpeed = stats.WalkSpeed

			UnitManager.Register(model, teamKey, group.Type)
			index += 1
		end
	end
end

-- Spawn both armies.
function SpawnSystem.SpawnAllTeams()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		warn("[SpawnSystem] No 'Assets' folder in ReplicatedStorage. Build your rigs there.")
		return
	end

	local unitsFolder = getUnitsFolder()
	for teamKey, teamData in Config.Teams do
		spawnTeam(teamKey, teamData, assets, unitsFolder)
	end
end

return SpawnSystem
