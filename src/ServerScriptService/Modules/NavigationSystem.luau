--[[
	NavigationSystem
	----------------
	Obstacle-aware movement. The key trick for performance: we only pathfind
	when an obstacle is actually in the way.

	  1. Raycast straight at the goal. Clear? Walk straight there (cheap — this
	     is every unit on an open field, costing one ray each).
	  2. Blocked? Ask PathfindingService for a route AROUND the obstacle, then
	     follow its waypoints.

	Path computes are throttled per-unit and globally capped so a whole army
	can't recompute at once and spike the server.
]]

local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local NavigationSystem = {}

-- Line-of-sight rays ignore the soldiers themselves (only obstacles matter).
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
sightParams.FilterDescendantsInstances = {}

local activeComputes = 0

-- Refresh at battle start so rays ignore the live units folder.
function NavigationSystem.Refresh()
	local unitsFolder = Workspace:FindFirstChild("Units")
	sightParams.FilterDescendantsInstances = unitsFolder and { unitsFolder } or {}
	activeComputes = 0
end

-- Is there a clear straight line from the unit to the goal?
local function pathIsClear(origin, goal)
	local up = Vector3.new(0, Config.Nav.RayHeight, 0)
	return Workspace:Raycast(origin + up, (goal - origin), sightParams) == nil
end

-- Kick off a throttled, non-blocking path recompute for this unit.
local function requestPath(unit, goal, now)
	local nav = unit.Nav
	if nav.computing then
		return
	end
	if now - (nav.lastCompute or -math.huge) < Config.Nav.RecomputeInterval then
		return
	end
	if activeComputes >= Config.Nav.MaxConcurrent then
		return
	end

	nav.computing = true
	nav.lastCompute = now
	activeComputes += 1
	local origin = unit.Root.Position

	task.spawn(function()
		local path = nav.path
		if not path then
			path = PathfindingService:CreatePath({
				AgentRadius = Config.Nav.AgentRadius,
				AgentCanJump = false,
			})
			nav.path = path
		end

		local ok = pcall(function()
			path:ComputeAsync(origin, goal)
		end)

		if ok and path.Status == Enum.PathStatus.Success then
			nav.waypoints = path:GetWaypoints()
			nav.index = 2 -- waypoint 1 is where we already are
			nav.goal = goal
		else
			nav.waypoints = nil
		end

		nav.computing = false
		activeComputes -= 1
	end)
end

-- The point this unit should walk toward this tick.
function NavigationSystem.NextPoint(unit, goal, now)
	local origin = unit.Root.Position

	-- Clear shot: go straight, forget any old path.
	if pathIsClear(origin, goal) then
		unit.Nav = nil
		return goal
	end

	-- Blocked: make sure we have a usable path to (roughly) this goal.
	local nav = unit.Nav
	if not nav then
		nav = {}
		unit.Nav = nav
	end

	local goalMoved = not nav.goal or (goal - nav.goal).Magnitude > Config.Nav.RepathDistance
	if not nav.waypoints or goalMoved then
		requestPath(unit, goal, now)
	end

	if nav.waypoints then
		local wp = nav.waypoints[nav.index]
		while wp do
			local flat = Vector3.new(wp.Position.X - origin.X, 0, wp.Position.Z - origin.Z)
			if flat.Magnitude <= Config.Nav.WaypointReach then
				nav.index += 1
				wp = nav.waypoints[nav.index]
			else
				return wp.Position
			end
		end
		-- ran out of waypoints; fall through to head straight
	end

	return goal
end

return NavigationSystem
