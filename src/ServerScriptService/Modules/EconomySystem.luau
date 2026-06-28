--[[
	EconomySystem
	-------------
	The RTS economy:
	  • Trees are scattered on the map. Workers chop them for WOOD and haul it
	    back to their base (CombatSystem.workerAct drives the worker movement;
	    this module owns the trees + wood + the base build AI).
	  • Each base has Wood + a Level. The base AI spends wood to: grow workers
	    (up to a target), pump troops (weighted by composition), and UPGRADE the
	    base (more HP + higher worker/troop caps).

	Kill an enemy's workers or raze their base to choke this whole loop.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local UnitManager = require(script.Parent.UnitManager)
local SpawnSystem = require(script.Parent.SpawnSystem)
local BaseSystem = require(script.Parent.BaseSystem)

local EconomySystem = {}

EconomySystem.Trees = {} -- list of { model, pos, wood }
local lastDecision = {}

-- ---- trees -----------------------------------------------------------------

local function mapInfo()
	local sum, n, groundY = Vector3.zero, 0, 3
	for _, child in Workspace:GetChildren() do
		if child:IsA("BasePart") and string.match(child.Name, "^Team.*Spawn$") then
			sum += child.Position
			n += 1
			groundY = child.Position.Y
		end
	end
	return (n > 0 and sum / n or Vector3.zero), groundY
end

local function farFromBases(pos)
	for _, base in BaseSystem.Bases do
		if (base.Position - pos).Magnitude < Config.Economy.Trees.MinFromBase then
			return false
		end
	end
	return true
end

local function plantTree(center, groundY)
	local angle = math.random() * math.pi * 2
	local dist = 30 + math.random() * Config.Economy.Trees.Scatter
	local pos = center + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
	pos = Vector3.new(pos.X, groundY, pos.Z)
	if not farFromBases(pos) then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = "Tree"

	local trunk = Instance.new("Part")
	trunk.Anchored = true
	trunk.CanCollide = false
	trunk.CanQuery = false
	trunk.Size = Vector3.new(1.6, 9, 1.6)
	trunk.Color = Color3.fromRGB(94, 62, 38)
	trunk.Position = pos + Vector3.new(0, 4.5, 0)
	trunk.Parent = model

	local leaves = Instance.new("Part")
	leaves.Shape = Enum.PartType.Ball
	leaves.Anchored = true
	leaves.CanCollide = false
	leaves.CanQuery = false
	leaves.Size = Vector3.new(7, 7, 7)
	leaves.Color = Color3.fromRGB(48, 120, 52)
	leaves.Material = Enum.Material.Grass
	leaves.Position = pos + Vector3.new(0, 10, 0)
	leaves.Parent = model
	model.PrimaryPart = trunk

	model.Parent = Workspace
	return { model = model, pos = pos, wood = Config.Economy.Trees.Wood, generated = true }
end

function EconomySystem.Reset()
	-- Only destroy trees WE generated; never touch the user's placed trees.
	for _, tree in EconomySystem.Trees do
		if tree.generated and tree.model then
			tree.model:Destroy()
		end
	end
	EconomySystem.Trees = {}
	lastDecision = {}
end

-- A Workspace object named "tree..." (Model or Part) becomes an endless wood
-- source -- the user's placed trees aren't depleted or destroyed.
local function considerTree(obj)
	if obj.Name:lower():sub(1, 4) ~= "tree" then
		return
	end
	local pos
	if obj:IsA("Model") then
		pos = obj:GetPivot().Position
	elseif obj:IsA("BasePart") then
		pos = obj.Position
	else
		return
	end
	table.insert(EconomySystem.Trees, { model = obj, pos = pos, wood = math.huge, infinite = true, generated = false })
end

function EconomySystem.SetupTrees()
	-- Prefer trees you've already placed in Workspace (named "tree 2", "tree 5", ...).
	for _, child in Workspace:GetChildren() do
		considerTree(child)
		if child:IsA("Folder") then
			for _, sub in child:GetChildren() do
				considerTree(sub)
			end
		end
	end
	if #EconomySystem.Trees > 0 then
		print(("[EconomySystem] using %d existing tree(s) from Workspace"):format(#EconomySystem.Trees))
		return
	end

	-- None found: scatter our own as a fallback.
	local center, groundY = mapInfo()
	local tries = 0
	while #EconomySystem.Trees < Config.Economy.Trees.Count and tries < Config.Economy.Trees.Count * 4 do
		tries += 1
		local tree = plantTree(center, groundY)
		if tree then
			table.insert(EconomySystem.Trees, tree)
		end
	end
end

-- Nearest tree that still has wood.
function EconomySystem.NearestTree(pos)
	local best, bestDist = nil, math.huge
	for _, tree in EconomySystem.Trees do
		if tree.wood > 0 then
			local dist = (tree.pos - pos).Magnitude
			if dist < bestDist then
				bestDist = dist
				best = tree
			end
		end
	end
	return best
end

-- Chop a tree; returns wood actually obtained. A depleted tree is replaced by a
-- fresh one elsewhere so the economy keeps flowing.
function EconomySystem.Mine(tree, amount)
	if tree.infinite then
		return amount -- placed trees never run out
	end
	local got = math.min(amount, tree.wood)
	tree.wood -= got
	if tree.wood <= 0 then
		if tree.model then
			tree.model:Destroy()
		end
		for i, t in EconomySystem.Trees do
			if t == tree then
				table.remove(EconomySystem.Trees, i)
				break
			end
		end
		local center, groundY = mapInfo()
		local fresh = plantTree(center, groundY)
		if fresh then
			table.insert(EconomySystem.Trees, fresh)
		end
	end
	return got
end

function EconomySystem.Deposit(teamKey, amount)
	local base = BaseSystem.Bases[teamKey]
	if base and base.Alive then
		base.Wood += amount
	end
end

-- ---- base build AI ---------------------------------------------------------

local function workerTarget(level)
	return math.min(Config.Economy.MaxWorkers, Config.Economy.Upgrade.WorkerTargetBase + level * Config.Economy.Upgrade.WorkerTargetPerLevel)
end

local function troopCap(level)
	return Config.Economy.Upgrade.TroopCapBase + level * Config.Economy.Upgrade.TroopCapPerLevel
end

local function upgradeCost(level)
	return Config.Economy.Upgrade.BaseCost * (level + 1)
end

local function ringSpot(basePos, n, radius)
	local angle = n * 1.7
	return basePos + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

-- Pick a troop type to build, weighted by the composition, that we can afford.
local function pickTroop(wood)
	local pool = {}
	for _, group in Config.Composition do
		local cost = Config.Economy.Costs[group.Type] or 15
		if wood >= cost then
			for _ = 1, group.Count do
				table.insert(pool, group.Type)
			end
		end
	end
	if #pool == 0 then
		return nil
	end
	return pool[math.random(#pool)]
end

function EconomySystem.Update(now)
	-- Count workers + troops per team.
	local workers, troops = {}, {}
	for _, unit in UnitManager.Units do
		if unit.Alive then
			if unit.Type == "Worker" then
				workers[unit.Team] = (workers[unit.Team] or 0) + 1
			elseif not unit.IsLeader then
				troops[unit.Team] = (troops[unit.Team] or 0) + 1
			end
		end
	end

	for teamKey, base in BaseSystem.Bases do
		if base.Alive and now - (lastDecision[teamKey] or 0) >= Config.Economy.DecisionInterval then
			lastDecision[teamKey] = now
			local wcount = workers[teamKey] or 0
			local tcount = troops[teamKey] or 0

			if wcount < workerTarget(base.Level) and base.Wood >= Config.Economy.WorkerCost then
				-- Grow the economy first.
				base.Wood -= Config.Economy.WorkerCost
				SpawnSystem.SpawnOne(teamKey, "Worker", ringSpot(base.Position, wcount + 1, 17))
			elseif base.Level < Config.Economy.Upgrade.MaxLevel
				and base.Wood >= upgradeCost(base.Level)
				and tcount >= troopCap(base.Level) * 0.6
			then
				-- Army's reasonably full: invest in an upgrade (more HP + caps).
				base.Wood -= upgradeCost(base.Level)
				BaseSystem.Upgrade(base)
			elseif tcount < troopCap(base.Level) then
				-- Pump troops with whatever we can afford.
				local unitType = pickTroop(base.Wood)
				if unitType then
					base.Wood -= Config.Economy.Costs[unitType] or 15
					SpawnSystem.SpawnOne(teamKey, unitType, ringSpot(base.Position, tcount + 1, 15))
				end
			end

			BaseSystem.UpdateLabel(base)
		end
	end
end

return EconomySystem
