--[[
	BattleSim  (main entry point)
	-----------------------------
	The one Script that runs the whole simulation. It:
	  1. spawns both armies
	  2. every tick, lets each living unit pick a target and act
	  3. ends the battle when one team is wiped out
	  4. waits, then restarts so you can watch again

	All the heavy logic lives in the Modules. This file is just the conductor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local PhysicsService = game:GetService("PhysicsService")

-- ---------------------------------------------------------------------------
-- Spectator setup. We spawn the viewer on a platform OVERLOOKING the battle so
-- they always see the action (never fall into the void). This is server-only,
-- so it works even if the client freecam script hasn't synced. The freecam,
-- when present, just takes over the camera for flying.
-- ---------------------------------------------------------------------------

-- Players don't collide with battle units (and units don't path into them).
pcall(function() PhysicsService:RegisterCollisionGroup("BattleUnits") end)
pcall(function() PhysicsService:RegisterCollisionGroup("Spectator") end)
pcall(function() PhysicsService:CollisionGroupSetCollidable("Spectator", "BattleUnits", false) end)

-- A raised point overlooking the whole battle (averages every Team*Spawn marker).
local function viewpoint()
	local markers = {}
	for _, child in Workspace:GetChildren() do
		if child:IsA("BasePart") and string.match(child.Name, "^Team.*Spawn$") then
			table.insert(markers, child.Position)
		end
	end

	local center
	if #markers > 0 then
		local sum = Vector3.zero
		for _, pos in markers do
			sum += pos
		end
		center = sum / #markers
	else
		local ground = Workspace:FindFirstChild("Battlefield") or Workspace:FindFirstChild("Baseplate")
		center = ground and ground.Position or Vector3.zero
	end

	local spread = 60
	for _, pos in markers do
		spread = math.max(spread, (pos - center).Magnitude)
	end
	return center + Vector3.new(0, spread * 0.9 + 25, spread * 1.4 + 70), center
end

-- Make/repair a SpawnLocation on that viewing platform.
local function ensureSpawnPad()
	local standPos, center = viewpoint()
	local pad = Workspace:FindFirstChild("SpectatorPad")
	if not pad then
		pad = Instance.new("SpawnLocation")
		pad.Name = "SpectatorPad"
		pad.Size = Vector3.new(24, 1, 24)
		pad.Anchored = true
		pad.Neutral = true
		pad.Duration = 0 -- no forcefield
		pad.Color = Color3.fromRGB(55, 58, 68)
		pad.Parent = Workspace
	end
	pad.CFrame = CFrame.lookAt(standPos, Vector3.new(center.X, standPos.Y, center.Z))
end

-- Keep the viewer from interfering with the simulation.
local function onCharacter(character)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Spectator"
			part.CanQuery = false -- pathfinding rays ignore the player
		end
	end
	character.DescendantAdded:Connect(function(part)
		if part:IsA("BasePart") then
			part.CollisionGroup = "Spectator"
			part.CanQuery = false
		end
	end)
end

local function onPlayer(plr)
	plr.CharacterAdded:Connect(onCharacter)
	if plr.Character then
		onCharacter(plr.Character)
	end
end

ensureSpawnPad()
Players.CharacterAutoLoads = true
for _, plr in Players:GetPlayers() do
	onPlayer(plr)
end
Players.PlayerAdded:Connect(onPlayer)

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Modules = ServerScriptService:WaitForChild("Modules")
local UnitManager = require(Modules.UnitManager)
local SpawnSystem = require(Modules.SpawnSystem)
local VisionSystem = require(Modules.VisionSystem)
local BaseSystem = require(Modules.BaseSystem)
local EconomySystem = require(Modules.EconomySystem)
local CommandSystem = require(Modules.CommandSystem)
local TargetingSystem = require(Modules.TargetingSystem)
local CombatSystem = require(Modules.CombatSystem)
local HazardSystem = require(Modules.HazardSystem)
local StaminaSystem = require(Modules.StaminaSystem)
local AnimationSystem = require(Modules.AnimationSystem)
local SpatialGrid = require(Modules.SpatialGrid)
local Signals = require(Modules.Signals)

-- ----------------------------------------------------- Live control panel ---
local controlRemote = ReplicatedStorage:FindFirstChild("ControlPanel")
if not controlRemote then
	controlRemote = Instance.new("RemoteEvent")
	controlRemote.Name = "ControlPanel"
	controlRemote.Parent = ReplicatedStorage
end

local control = { paused = false, restart = false }

-- Snapshot the starting composition so army-size scaling stays proportional.
local baseComposition, baseTotal = {}, 0
for _, group in Config.Composition do
	table.insert(baseComposition, { Type = group.Type, Count = group.Count })
	baseTotal += group.Count
end

local function currentArmyTotal()
	local total = 0
	for _, group in Config.Composition do
		total += group.Count
	end
	return total
end

local function applyArmyTotal(total)
	total = math.clamp(math.floor(tonumber(total) or baseTotal), 4, 400)
	local scale = total / math.max(1, baseTotal)
	local scaled = {}
	for _, group in baseComposition do
		table.insert(scaled, { Type = group.Type, Count = math.max(0, math.round(group.Count * scale)) })
	end
	Config.Composition = scaled
end

local function broadcastState()
	controlRemote:FireAllClients("state", {
		paused = control.paused,
		collisions = Config.UnitsCollide,
		cones = Config.Vision.ShowCones,
		army = currentArmyTotal(),
	})
end

controlRemote.OnServerEvent:Connect(function(_player, action, value)
	if action == "pause" then
		control.paused = not control.paused
	elseif action == "restart" then
		control.restart = true
	elseif action == "army" then
		applyArmyTotal(value)
		control.restart = true
	elseif action == "collisions" then
		Config.UnitsCollide = value and true or false
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable("BattleUnits", "BattleUnits", Config.UnitsCollide)
		end)
	elseif action == "cones" then
		Config.Vision.ShowCones = value and true or false
	end
	broadcastState()
end)

Players.PlayerAdded:Connect(function()
	task.wait(1)
	broadcastState()
end)

-- Survivor count per team, for the HUD scoreboard.
local function teamCounts()
	local counts = {}
	for _, unit in UnitManager.Units do
		if unit.Alive then
			counts[unit.Team] = (counts[unit.Team] or 0) + 1
		end
	end
	return counts
end

local function countsChanged(a, b)
	for teamKey in Config.Teams do
		if (a[teamKey] or 0) ~= (b[teamKey] or 0) then
			return true
		end
	end
	return false
end

-- Returns: "running", a winning team key, or "draw". A team is still in play
-- while it has living units OR a standing base (which keeps respawning).
local function battleStatus()
	local counts = teamCounts()
	local count, lastTeam = 0, nil
	for teamKey in Config.Teams do
		if (counts[teamKey] or 0) > 0 or BaseSystem.IsBaseAlive(teamKey) then
			count += 1
			lastTeam = teamKey
		end
	end

	if count > 1 then
		return "running"
	elseif count == 1 then
		return lastTeam
	else
		return "draw"
	end
end

local function runOneBattle()
	UnitManager.Clear()
	VisionSystem.Reset()
	CommandSystem.Reset()
	BaseSystem.Reset()
	EconomySystem.Reset()
	SpawnSystem.SpawnAllTeams()
	BaseSystem.SpawnBases()
	EconomySystem.SetupTrees()
	CombatSystem.RefreshObstacleFilter()

	if #UnitManager.Units == 0 then
		warn("[BattleSim] Nothing spawned. Check your rigs and spawn markers, then save again.")
		return
	end

	print(("[BattleSim] Battle start! %d soldiers on the field."):format(#UnitManager.Units))

	local lastCounts = teamCounts()
	Signals.Fire({ kind = "start", counts = lastCounts })

	while true do
		if control.restart then
			break
		end
		if control.paused then
			task.wait(0.1)
			continue
		end

		local now = os.clock()

		-- Rebuild the spatial grid first; vision/targeting/separation query it.
		SpatialGrid.Rebuild(UnitManager.Units)

		-- Refresh hazards + vision, update bases (discovery/respawn), then plan + act.
		HazardSystem.Refresh()
		VisionSystem.Update(now)
		BaseSystem.Update(now)
		EconomySystem.Update(now)
		CommandSystem.Update()

		for _, unit in UnitManager.Units do
			if unit.Alive then
				local state = CommandSystem.GetState(unit.Team)
				TargetingSystem.UpdateTarget(unit, state, now)
				CombatSystem.Act(unit, now, state)
				StaminaSystem.Update(unit, Config.SimTick)
				AnimationSystem.Update(unit)
			end
		end

		HazardSystem.ApplyDamage(UnitManager.Units, now)
		UnitManager.RemoveDead()

		-- Push the scoreboard to the HUD only when a count actually changes.
		local counts = teamCounts()
		if countsChanged(counts, lastCounts) then
			lastCounts = counts
			Signals.Fire({ kind = "score", counts = counts })
		end

		local status = battleStatus()
		if status ~= "running" then
			if status == "draw" then
				print("[BattleSim] Draw — both armies wiped out.")
				Signals.Fire({ kind = "result", winner = false })
			else
				print(("[BattleSim] Winner: %s!"):format(Config.Teams[status].Name))
				Signals.Fire({ kind = "result", winner = status })
			end
			break
		end

		task.wait(Config.SimTick)
	end
end

-- Loop forever so the sim auto-restarts and you can keep watching. A manual
-- restart (from the control panel) skips the wait.
while true do
	runOneBattle()
	local manual = control.restart
	control.restart = false
	if not manual then
		print(("[BattleSim] Restarting in %d seconds..."):format(Config.RestartDelay))
		task.wait(Config.RestartDelay)
	end
end
