--[[
	SpatialGrid
	-----------
	A uniform grid hash over unit positions, rebuilt once per tick. It turns the
	O(n^2) "check every other unit" scans (separation, targeting, vision) into
	"check only nearby cells" -- the core optimization for big battles.

	Usage:
	  SpatialGrid.Rebuild(UnitManager.Units)        -- once per tick
	  SpatialGrid.ForNear(pos, radius, function(u)  -- visit candidates near pos
	      ... your own exact distance/team checks ...
	  end)
]]

local SpatialGrid = {}

local CELL = 24 -- studs per cell
local grid = {} -- key -> { units }

local function keyOf(cx, cz)
	return cx * 100000 + cz
end

function SpatialGrid.Rebuild(units)
	table.clear(grid)
	for _, unit in units do
		if unit.Alive and unit.Root then
			local pos = unit.Root.Position
			local key = keyOf(math.floor(pos.X / CELL), math.floor(pos.Z / CELL))
			local cell = grid[key]
			if not cell then
				cell = {}
				grid[key] = cell
			end
			table.insert(cell, unit)
		end
	end
end

-- Calls fn(unit) for every unit in cells overlapping the box around `pos` of the
-- given radius. fn must still do its own exact distance / team / alive checks --
-- this only narrows the candidate set.
function SpatialGrid.ForNear(pos, radius, fn)
	local minx = math.floor((pos.X - radius) / CELL)
	local maxx = math.floor((pos.X + radius) / CELL)
	local minz = math.floor((pos.Z - radius) / CELL)
	local maxz = math.floor((pos.Z + radius) / CELL)
	for cx = minx, maxx do
		for cz = minz, maxz do
			local cell = grid[keyOf(cx, cz)]
			if cell then
				for _, unit in cell do
					fn(unit)
				end
			end
		end
	end
end

return SpatialGrid
