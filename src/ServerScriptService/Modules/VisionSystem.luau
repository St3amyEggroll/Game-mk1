--[[
	VisionSystem  (fog of war)
	--------------------------
	Each team only KNOWS about enemies it (or a teammate) can currently see.
	Sightings are shared team-wide and remembered as "last-known" positions
	after sight is lost, until the team searches that spot or forgets it.

	Per team we keep:  knowledge[enemyUnit] = { pos, visible, lastSeen }

	Vision rules:
	  • within the looker's SightRange (Scouts farthest, Archers medium), AND
	  • a clear line of sight (walls/obstacles block it; other units don't).

	Also marks each unit's SeenBy (which enemy teams see it) for ambush bonuses,
	and writes a "Spotted" attribute on the model for the spectator fog view.

	Throttled to Config.Vision.Interval so all those rays stay cheap.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local UnitManager = require(script.Parent.UnitManager)
local NavigationSystem = require(script.Parent.NavigationSystem)
local BaseSystem = require(script.Parent.BaseSystem)

local VisionSystem = {}

VisionSystem.TeamKnowledge = {} -- [teamKey] = { [enemyUnit] = {pos, visible, lastSeen} }
local lastUpdate = -math.huge

function VisionSystem.Reset()
	VisionSystem.TeamKnowledge = {}
	lastUpdate = -math.huge
end

function VisionSystem.GetKnown(teamKey)
	return VisionSystem.TeamKnowledge[teamKey] or {}
end

local function setSpotted(unit, spotted)
	if unit.SpottedState ~= spotted then
		unit.SpottedState = spotted
		if unit.Model then
			unit.Model:SetAttribute("Spotted", spotted)
		end
	end
end

function VisionSystem.Update(now)
	if now - lastUpdate < Config.Vision.Interval then
		return
	end
	lastUpdate = now

	-- Snapshot living units by team; reset each unit's SeenBy set.
	local byTeam = {}
	for _, unit in UnitManager.Units do
		if unit.Alive then
			local list = byTeam[unit.Team]
			if not list then
				list = {}
				byTeam[unit.Team] = list
			end
			table.insert(list, unit)
			table.clear(unit.SeenBy)
		end
	end

	for teamKey in Config.Teams do
		local allies = byTeam[teamKey]
		if not allies then
			continue
		end

		local knowledge = VisionSystem.TeamKnowledge[teamKey]
		if not knowledge then
			knowledge = {}
			VisionSystem.TeamKnowledge[teamKey] = knowledge
		end

		-- Stationary eyes (the team's watchtower) see around home too.
		local sources = BaseSystem.GetVisionSources(teamKey)

		-- Which enemies can anyone (or anything) on this team see right now?
		for otherTeam, list in byTeam do
			if otherTeam ~= teamKey then
				for _, enemy in list do
					local enemyPos = enemy.Root.Position
					local visible = false
					for _, ally in allies do
						if (enemyPos - ally.Root.Position).Magnitude <= ally.Stats.SightRange
							and NavigationSystem.HasLineOfSight(ally.Root.Position, enemyPos)
						then
							visible = true
							break
						end
					end
					if not visible then
						for _, src in sources do
							if (enemyPos - src.pos).Magnitude <= src.range
								and NavigationSystem.HasLineOfSight(src.pos, enemyPos)
							then
								visible = true
								break
							end
						end
					end

					if visible then
						local entry = knowledge[enemy]
						if not entry then
							entry = {}
							knowledge[enemy] = entry
						end
						entry.pos = enemyPos
						entry.visible = true
						entry.lastSeen = now
						enemy.SeenBy[teamKey] = true
					else
						local entry = knowledge[enemy]
						if entry then
							entry.visible = false
						end
					end
				end
			end
		end

		-- Forget the dead, the long-unseen, and anything we've searched for.
		for enemy, entry in knowledge do
			local forget = false
			if not enemy.Alive then
				forget = true
			elseif now - entry.lastSeen > Config.Vision.Memory then
				forget = true
			elseif not entry.visible then
				for _, ally in allies do
					if (ally.Root.Position - entry.pos).Magnitude <= Config.Vision.ForgetRadius then
						forget = true
						break
					end
				end
			end
			if forget then
				knowledge[enemy] = nil
			end
		end
	end

	-- "Spotted" = seen by at least one enemy team (drives the spectator fog view).
	for _, unit in UnitManager.Units do
		if unit.Alive then
			setSpotted(unit, next(unit.SeenBy) ~= nil)
		end
	end
end

return VisionSystem
