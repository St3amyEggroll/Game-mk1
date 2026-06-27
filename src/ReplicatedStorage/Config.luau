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
		Priority = 1, -- how juicy a target this is (healers/artillery > grunts)
	},
	Ranged = {
		RigName = "RangedUnit",
		MaxHealth = 70,
		WalkSpeed = 14,
		AttackRange = 60,
		AttackDamage = 10,
		AttackCooldown = 1.5,
		Priority = 1.5, -- squishy and dangerous, worth focusing
	},
}

-- How units pick a target (threat assessment + priorities). Higher weight =
-- matters more. They prefer: high-value enemies, whoever is attacking them or
-- their leader, and the leader's focus call -- balanced against distance.
Config.Targeting = {
	DistanceWeight = 1.0, -- farther = less appealing
	PriorityWeight = 25, -- UnitType.Priority (leader uses LeaderPriority)
	LeaderPriority = 4, -- the enemy leader is a top target
	SelfThreatWeight = 40, -- an enemy currently attacking ME
	LeaderThreatWeight = 55, -- an enemy currently attacking MY leader
	FocusWeight = 30, -- the leader's called focus target
	Hysteresis = 20, -- bonus for keeping current target (stops thrashing)
	ThreatMemory = 3, -- seconds an attacker is remembered as a threat
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

	-- Self-protection: when enemies get within ThreatRadius of the Leader, it
	-- pulls back further and its guards close into a defensive RING around it.
	ThreatRadius = 40, -- enemy within this of the Leader = "threatened"
	RetreatStandoff = 45, -- how far back the Leader pulls when threatened
	GuardRingRadius = 7, -- radius of the guard ring around a threatened Leader
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

	-- Flanking: a squad peels off ONLY once the front lines are engaged, then
	-- drives at the enemy's rear / leader (pour through the gap).
	FlankSquadSize = 4, -- soldiers per team assigned to flank
	FlankWidth = 55, -- how far out to the side they swing before closing in

	-- "Read the battle": stance from strength ratio (own health vs enemy).
	AggressiveRatio = 1.35, -- winning by this much -> push hard
	DefensiveRatio = 0.7, -- losing past this -> turtle up
	RetreatRatio = 0.4, -- losing badly (or leader dead + losing) -> fall back
	HoldDistance = 25, -- defensive: hold a line this far in front of own center
	RetreatDistance = 70, -- how far back the rear/regroup point sits
}

-- Units physically collide with each other. Turn off for big battles if the
-- shoving gets expensive (separation steering still keeps them spaced).
Config.UnitsCollide = true

-- Hazards: put parts in a Workspace folder named "Hazards" (lava, fire,
-- explosive zones). Units steer around them and take damage if caught inside.
Config.Hazards = {
	AvoidRadius = 9, -- how far out units start steering away
	AvoidStrength = 1.5, -- how hard they veer off
	Damage = 12, -- damage per tick while standing in a hazard
	DamageInterval = 0.4, -- seconds between hazard damage ticks
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
