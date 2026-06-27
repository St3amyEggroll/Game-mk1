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

-- Spectator sim: don't spawn player avatars into the battlefield (they'd get
-- shoved around and confuse pathfinding). The client runs a scripted camera.
Players.CharacterAutoLoads = false

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Modules = ServerScriptService:WaitForChild("Modules")
local UnitManager = require(Modules.UnitManager)
local SpawnSystem = require(Modules.SpawnSystem)
local CommandSystem = require(Modules.CommandSystem)
local TargetingSystem = require(Modules.TargetingSystem)
local CombatSystem = require(Modules.CombatSystem)
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

		-- Leaders set each team's plan first, then soldiers act on it.
		CommandSystem.Update()

		for _, unit in UnitManager.Units do
			if unit.Alive then
				local state = CommandSystem.GetState(unit.Team)
				TargetingSystem.UpdateTarget(unit, state)
				CombatSystem.Act(unit, now, state)
			end
		end
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
