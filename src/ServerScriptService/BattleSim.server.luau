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

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Modules = ServerScriptService:WaitForChild("Modules")
local UnitManager = require(Modules.UnitManager)
local SpawnSystem = require(Modules.SpawnSystem)
local TargetingSystem = require(Modules.TargetingSystem)
local CombatSystem = require(Modules.CombatSystem)

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
	SpawnSystem.SpawnAllTeams()

	if #UnitManager.Units == 0 then
		warn("[BattleSim] Nothing spawned. Check your rigs and spawn markers, then save again.")
		return
	end

	print(("[BattleSim] Battle start! %d soldiers on the field."):format(#UnitManager.Units))

	while true do
		local now = os.clock()

		for _, unit in UnitManager.Units do
			if unit.Alive then
				TargetingSystem.UpdateTarget(unit)
				CombatSystem.Act(unit, now)
			end
		end
		UnitManager.RemoveDead()

		local status = battleStatus()
		if status ~= "running" then
			if status == "draw" then
				print("[BattleSim] Draw — both armies wiped out.")
			else
				print(("[BattleSim] Winner: %s!"):format(Config.Teams[status].Name))
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
