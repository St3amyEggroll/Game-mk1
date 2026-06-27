--[[
	Config
	-------
	Every tunable number in the simulation lives here. Want bigger armies,
	more damage, faster soldiers? Change it here, save, and Rojo pushes it
	straight into Studio. No other file should hard-code these values.
]]

local Config = {}

-- The two armies. SpawnMarker must match the name of a Part you place in
-- Workspace (your homework). Color is applied to every unit on that team.
Config.Teams = {
	A = {
		Name = "Blue Army",
		Color = Color3.fromRGB(70, 130, 255),
		SpawnMarker = "TeamASpawn",
	},
	B = {
		Name = "Red Army",
		Color = Color3.fromRGB(255, 80, 70),
		SpawnMarker = "TeamBSpawn",
	},
}

-- Stat block for each kind of soldier. RigName must match a Model you put
-- inside ReplicatedStorage/Assets. Ranged is defined now but not used until
-- Milestone 3 — you only need to build the MeleeUnit rig for now.
Config.UnitTypes = {
	Melee = {
		RigName = "MeleeUnit",
		MaxHealth = 100,
		WalkSpeed = 16,
		AttackRange = 6, -- studs; has to get right up close
		AttackDamage = 18,
		AttackCooldown = 1.0, -- seconds between swings
	},
	Ranged = {
		RigName = "RangedUnit",
		MaxHealth = 70,
		WalkSpeed = 14,
		AttackRange = 60,
		AttackDamage = 10,
		AttackCooldown = 1.5,
	},
}

-- What each team is made of (NOT counting the Leader, who is added on top).
-- Add more entries / bump Count to grow the army.
Config.Composition = {
	{ Type = "Melee", Count = 12 },
}

-- The Leader directs the team from the back. Beefy, scaled-up, glowing.
-- For now the Leader is AI-controlled; later a player can take its place.
Config.Leader = {
	Enabled = true,
	HealthMultiplier = 3, -- leader has 3x a normal soldier's health
	Scale = 1.5, -- visually bigger so you can spot it
	GlowColor = Color3.fromRGB(255, 230, 120), -- highlight tint
	Standoff = 20, -- studs the Leader hangs back behind its army's center

	-- Bodyguards screen the Leader. THIS is the "protect the leader" strategy:
	-- assassins (focus fire targets the enemy leader) must punch through guards.
	GuardSquadSize = 3, -- soldiers assigned to guard their Leader
	GuardScreenDistance = 9, -- how far in front of the Leader they hold
	GuardEngageRange = 28, -- guards attack any enemy this close to the Leader
}

-- Army-level behavior the Leader coordinates.
Config.Command = {
	-- Teams hold formation and Advance until enemies get this close, then Engage.
	EngageRange = 45,
	-- During Engage, a unit will gang up on the Leader's focus target if it's
	-- within this range; otherwise it fights whoever's nearest.
	FocusRange = 55,
	-- Shape of the marching formation.
	FormationSpacing = 5, -- studs between soldiers
	FormationColumns = 6, -- soldiers per row

	-- Morale: soldiers fighting near a living Leader hit harder. If the Leader
	-- dies, the whole army loses its edge.
	MoraleRange = 35,
	MoraleDamageBonus = 1.3, -- +30% damage near the leader
	LeaderlessDamagePenalty = 0.75, -- -25% damage with no leader alive

	-- How hard units avoid piling on top of each other while moving.
	SeparationRadius = 4,

	-- Flanking: a squad peels off and swings wide to hit the enemy from the
	-- side instead of charging straight in.
	FlankSquadSize = 4, -- soldiers per team assigned to flank
	FlankWidth = 55, -- how far out to the side they swing before closing in
}

-- Pathfinding. Units only compute a path when an obstacle is actually between
-- them and their goal (open field = no pathfinding cost). Paths are throttled
-- and capped so hundreds of units can't all recompute at once.
Config.Nav = {
	AgentRadius = 2, -- how wide a gap a unit needs to fit through
	RepathDistance = 12, -- recompute if the goal moved more than this
	RecomputeInterval = 0.7, -- min seconds between a unit's path recomputes
	WaypointReach = 4, -- how close before advancing to the next waypoint
	MaxConcurrent = 8, -- max path computations happening at once
	RayHeight = 2, -- height of the line-of-sight check
}

-- Death visuals.
Config.Death = {
	Ragdoll = true, -- limbs go limp and flop on death
	PuffColor = Color3.fromRGB(130, 120, 100), -- dust puff color
	PuffAmount = 18, -- particles per death
}

-- Floating health bars above each unit.
Config.HealthBars = {
	Enabled = true,
}

-- The AI "brain" updates this often (seconds). 0.1 = 10 times a second.
-- This is NOT every frame on purpose — it's the first and most important
-- optimization habit. We can run hundreds of units because each one only
-- thinks 10x/sec instead of 60x/sec.
Config.SimTick = 0.1

-- Seconds to wait after a battle ends before auto-restarting.
Config.RestartDelay = 5

-- How long a corpse lingers before it's cleaned up (seconds).
Config.CorpseLifetime = 3

return Config
