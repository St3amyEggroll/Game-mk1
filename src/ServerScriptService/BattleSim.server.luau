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
local CommandSystem = require(Modules.CommandSystem)
local TargetingSystem = require(Modules.TargetingSystem)
local CombatSystem = require(Modules.CombatSystem)
local HazardSystem = require(Modules.HazardSystem)
local Signals = require(Modules.Signals)

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

-- Returns: "running", or a winning team key, or "draw".
local function battleStatus()
	local teamsAlive = UnitManager.TeamsAlive()
	local count, lastTeam = 0, nil
	for teamKey in teamsAlive do
		count += 1
		lastTeam = teamKey
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
	CommandSystem.Reset()
	SpawnSystem.SpawnAllTeams()
	CombatSystem.RefreshObstacleFilter()

	if #UnitManager.Units == 0 then
		warn("[BattleSim] Nothing spawned. Check your rigs and spawn markers, then save again.")
		return
	end

	print(("[BattleSim] Battle start! %d soldiers on the field."):format(#UnitManager.Units))

	local lastCounts = teamCounts()
	Signals.Fire({ kind = "start", counts = lastCounts })

	while true do
		local now = os.clock()

		-- Refresh hazard zones, then leaders set each team's plan, then soldiers act.
		HazardSystem.Refresh()
		CommandSystem.Update()

		for _, unit in UnitManager.Units do
			if unit.Alive then
				local state = CommandSystem.GetState(unit.Team)
				TargetingSystem.UpdateTarget(unit, state, now)
				CombatSystem.Act(unit, now, state)
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

-- Loop forever so the sim auto-restarts and you can keep watching.
while true do
	runOneBattle()
	print(("[BattleSim] Restarting in %d seconds..."):format(Config.RestartDelay))
	task.wait(Config.RestartDelay)
end
