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
local SpatialGrid = require(script.Parent.SpatialGrid)

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

		-- Build this team's "eyes". Each soldier sees a forward CONE (limited
		-- field of view -- blind to the sides/rear), plus a small all-round
		-- NearRadius of awareness up close (someone right next to you). The
		-- watchtower is a stationary source that sees all around home.
		local near = Config.Vision.NearRadius
		local eyes = {}
		for _, ally in allies do
			local look = ally.Root.CFrame.LookVector
			local facing = Vector3.new(look.X, 0, look.Z)
			facing = facing.Magnitude > 0.01 and facing.Unit or Vector3.new(0, 0, 1)
			table.insert(eyes, {
				pos = ally.Root.Position,
				facing = facing,
				range = ally.Stats.SightRange,
				cosHalf = math.cos(math.rad((ally.Stats.FOV or 160) / 2)),
			})
		end
		local sources = BaseSystem.GetVisionSources(teamKey)

		-- The set of enemies this team can SEE this tick. Each eye only checks
		-- units in nearby grid cells, not the whole enemy army.
		local visibleSet = {}
		local function lookFrom(pos, range, facing, cosHalf)
			SpatialGrid.ForNear(pos, range, function(other)
				if other.Team == teamKey or visibleSet[other] or not other.Alive then
					return
				end
				local off = other.Root.Position - pos
				local dist = off.Magnitude
				if dist > range then
					return
				end
				local inView = dist <= near -- all-round awareness up close
				if not inView and facing then
					local flat = Vector3.new(off.X, 0, off.Z)
					if flat.Magnitude > 0 and facing:Dot(flat.Unit) >= cosHalf then
						inView = true -- inside the forward cone
					end
				elseif not facing then
					inView = true -- a 360 source (watchtower)
				end
				if inView and NavigationSystem.HasLineOfSight(pos, other.Root.Position) then
					visibleSet[other] = true
					other.SeenBy[teamKey] = true
				end
			end)
		end

		for _, eye in eyes do
			lookFrom(eye.pos, eye.range, eye.facing, eye.cosHalf)
		end
		for _, src in sources do
			lookFrom(src.pos, src.range, nil, nil) -- watchtower: 360
		end

		-- Refresh knowledge for seen enemies; mark the rest as not-currently-seen.
		for enemy in visibleSet do
			local entry = knowledge[enemy]
			if not entry then
				entry = {}
				knowledge[enemy] = entry
			end
			entry.pos = enemy.Root.Position
			entry.visible = true
			entry.lastSeen = now
			entry.health = enemy.Humanoid.Health -- remembered strength (no peeking after)
		end
		for enemy, entry in knowledge do
			if not visibleSet[enemy] then
				entry.visible = false
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
				SpatialGrid.ForNear(entry.pos, Config.Vision.ForgetRadius, function(other)
					if not forget and other.Team == teamKey and other.Alive
						and (other.Root.Position - entry.pos).Magnitude <= Config.Vision.ForgetRadius
					then
						forget = true
					end
				end)
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
