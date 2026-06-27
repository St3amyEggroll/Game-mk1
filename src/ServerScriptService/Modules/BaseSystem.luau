--[[
	BaseSystem  (Phase 3)
	---------------------
	Every team has a base, auto-built behind its spawn marker. While a base
	stands it trickles out reinforcements, so a team can't be wiped while their
	base lives. Destroy the base to stop their respawns; then finish their units.

	Bases are discovered by sight (scouts spot them from far). First discovery
	fires a flare so the whole team knows where to march.

	Win condition (in BattleSim): a team is out only when its base is destroyed
	AND it has no living units.
]]

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local UnitManager = require(script.Parent.UnitManager)
local SpawnSystem = require(script.Parent.SpawnSystem)
local NavigationSystem = require(script.Parent.NavigationSystem)
local Signals = require(script.Parent.Signals)

local BaseSystem = {}

BaseSystem.Bases = {} -- [team] = base
BaseSystem.Discovered = {} -- [team] = { [enemyTeam] = baseRef }

local lastRespawn = {}
local respawnCursor = {}
local respawnCycle = {}

local function buildCycle()
	respawnCycle = {}
	for _, group in Config.Composition do
		for _ = 1, group.Count do
			table.insert(respawnCycle, group.Type)
		end
	end
	if #respawnCycle == 0 then
		respawnCycle = { "Melee" }
	end
end

local function teamCap()
	local cap = 0
	for _, group in Config.Composition do
		cap += group.Count
	end
	return cap
end

local function healthColor(fraction)
	return Color3.fromRGB(math.floor(255 * (1 - fraction)), math.floor(200 * fraction), 40)
end

-- Build the visible keep + flag + health bar. Returns model, fillFrame.
local function createBaseModel(teamKey, teamData, groundPos)
	local model = Instance.new("Model")
	model.Name = "Base_" .. teamKey

	-- CanQuery=false so the base doesn't block the line-of-sight rays that
	-- discover it (or the units' vision in general).
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Size = Vector3.new(16, 12, 16)
	core.Anchored = true
	core.CanQuery = false
	core.Material = Enum.Material.Brick
	core.Color = teamData.Color:Lerp(Color3.new(0, 0, 0), 0.45)
	core.Position = groundPos + Vector3.new(0, 6, 0)
	core.Parent = model
	model.PrimaryPart = core

	local pole = Instance.new("Part")
	pole.Name = "Pole"
	pole.Size = Vector3.new(0.6, 16, 0.6)
	pole.Anchored = true
	pole.CanCollide = false
	pole.CanQuery = false
	pole.Color = Color3.fromRGB(60, 45, 30)
	pole.Position = groundPos + Vector3.new(0, 20, 0)
	pole.Parent = model

	local flag = Instance.new("Part")
	flag.Name = "Flag"
	flag.Size = Vector3.new(0.3, 5, 9)
	flag.Anchored = true
	flag.CanCollide = false
	flag.CanQuery = false
	flag.Material = Enum.Material.Fabric
	flag.Color = teamData.Color
	flag.Position = groundPos + Vector3.new(0, 25, 4.5)
	flag.Parent = model

	model.Parent = Workspace

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(170, 32)
	gui.StudsOffset = Vector3.new(0, 16, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = core
	gui.Parent = core

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 18)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = teamData.Color
	label.Text = Config.Base.Icon .. " " .. teamData.Name
	label.Parent = gui

	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, 0, 0, 9)
	bg.Position = UDim2.new(0, 0, 1, -9)
	bg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = healthColor(1)
	fill.BorderSizePixel = 0
	fill.Parent = bg

	return model, fill
end

function BaseSystem.Reset()
	for _, base in BaseSystem.Bases do
		if base.Model then
			base.Model:Destroy()
		end
	end
	BaseSystem.Bases = {}
	BaseSystem.Discovered = {}
	lastRespawn = {}
	respawnCursor = {}
end

function BaseSystem.SpawnBases()
	buildCycle()

	local markers, sum, n = {}, Vector3.zero, 0
	for team, data in Config.Teams do
		local marker = Workspace:FindFirstChild(data.SpawnMarker)
		if marker then
			markers[team] = marker.Position
			sum += marker.Position
			n += 1
		end
	end
	local center = n > 0 and sum / n or Vector3.zero

	for team, data in Config.Teams do
		local mp = markers[team]
		if mp then
			local dir = mp - center
			dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(0, 0, 1)
			local pos = mp + dir * Config.Base.SetbackFromSpawn
			local model, fill = createBaseModel(team, data, pos)
			BaseSystem.Bases[team] = {
				Team = team,
				Model = model,
				Position = pos, -- ground-level reference for distance/attacks/spawns
				Health = Config.Base.Health,
				MaxHealth = Config.Base.Health,
				Alive = true,
				Fill = fill,
			}
			lastRespawn[team] = 0
			respawnCursor[team] = 0
			BaseSystem.Discovered[team] = {}
		end
	end
end

function BaseSystem.IsBaseAlive(teamKey)
	local base = BaseSystem.Bases[teamKey]
	return base ~= nil and base.Alive
end

-- Nearest alive enemy base this team has discovered.
function BaseSystem.GetDiscoveredEnemyBase(teamKey, fromPos)
	local disc = BaseSystem.Discovered[teamKey]
	if not disc then
		return nil
	end
	local best, bestDist = nil, math.huge
	for _, base in disc do
		if base.Alive then
			local dist = (base.Position - fromPos).Magnitude
			if dist < bestDist then
				bestDist = dist
				best = base
			end
		end
	end
	return best
end

function BaseSystem.Damage(base, amount)
	if not base or not base.Alive then
		return
	end
	base.Health -= amount
	local frac = math.clamp(base.Health / base.MaxHealth, 0, 1)
	if base.Fill then
		base.Fill.Size = UDim2.fromScale(frac, 1)
		base.Fill.BackgroundColor3 = healthColor(frac)
	end
	if base.Health <= 0 then
		base.Alive = false
		Signals.Fire({ kind = "baseDown", team = base.Team })
		-- Collapse: grey rubble that sinks into the ground.
		if base.Model and base.Model.PrimaryPart then
			for _, part in base.Model:GetDescendants() do
				if part:IsA("BasePart") then
					part.Color = Color3.fromRGB(70, 70, 70)
					TweenService:Create(part, TweenInfo.new(1.5), { Position = part.Position - Vector3.new(0, 9, 0) }):Play()
				end
			end
		end
	end
end

function BaseSystem.Update(now)
	-- Snapshot living units per team + non-leader counts.
	local byTeam, counts = {}, {}
	for _, unit in UnitManager.Units do
		if unit.Alive then
			local list = byTeam[unit.Team]
			if not list then
				list = {}
				byTeam[unit.Team] = list
			end
			table.insert(list, unit)
			if not unit.IsLeader then
				counts[unit.Team] = (counts[unit.Team] or 0) + 1
			end
		end
	end

	-- Discover enemy bases by sight; flare on first contact.
	for team in Config.Teams do
		local allies = byTeam[team]
		if allies then
			local disc = BaseSystem.Discovered[team]
			for otherTeam in Config.Teams do
				local base = BaseSystem.Bases[otherTeam]
				if otherTeam ~= team and base and base.Alive and not disc[otherTeam] then
					for _, ally in allies do
						if (base.Position - ally.Root.Position).Magnitude <= ally.Stats.SightRange
							and NavigationSystem.HasLineOfSight(ally.Root.Position, base.Position)
						then
							disc[otherTeam] = base
							Signals.Fire({ kind = "flare", pos = base.Position, by = team, baseTeam = otherTeam })
							break
						end
					end
				end
			end
		end
	end

	-- Trickle reinforcements from living bases, up to the army cap.
	local cap = teamCap()
	for team, base in BaseSystem.Bases do
		if base.Alive and (counts[team] or 0) < cap and now - (lastRespawn[team] or 0) >= Config.Base.RespawnInterval then
			lastRespawn[team] = now
			respawnCursor[team] = (respawnCursor[team] % #respawnCycle) + 1
			local unitType = respawnCycle[respawnCursor[team]]
			local angle = respawnCursor[team] * 1.3
			-- Outside the base footprint (core is 16 wide) so they don't spawn inside it.
			local spot = base.Position + Vector3.new(math.cos(angle) * 15, 0, math.sin(angle) * 15)
			SpawnSystem.SpawnOne(team, unitType, spot)
		end
	end
end

return BaseSystem
