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
	C = {
		Name = "Green Army",
		Color = Color3.fromRGB(80, 200, 90),
		SpawnMarker = "TeamCSpawn",
	},
}

-- Stat block for each kind of soldier. MODERN MILITARY: nearly everyone carries
-- a gun (Ranged = true), so they fight from a distance in firing lines instead
-- of piling into melee. RigName falls back to MeleeUnit if you haven't built a
-- distinct rig. WalkSpeed is the BASE speed; SightRange + FOV drive fog of war.
Config.UnitTypes = {
	Rifleman = {
		RigName = "RiflemanUnit",
		MaxHealth = 100,
		WalkSpeed = 14,
		AttackRange = 52, -- standard rifle reach
		MinRange = 8, -- back off if enemies get inside this
		AttackDamage = 11,
		AttackCooldown = 0.55, -- rapid fire
		Priority = 1,
		SightRange = 60,
		Ranged = true,
	},
	Gunner = {
		RigName = "GunnerUnit",
		MaxHealth = 95,
		WalkSpeed = 10, -- heavy, slow
		AttackRange = 82, -- long-range support (MG / marksman)
		MinRange = 16,
		AttackDamage = 16,
		AttackCooldown = 0.7,
		Priority = 1.5, -- dangerous: worth focusing down
		SightRange = 88,
		FOV = 140,
		Ranged = true,
	},
	Assault = {
		RigName = "AssaultUnit",
		MaxHealth = 115,
		WalkSpeed = 18, -- fast, pushes the line
		AttackRange = 26, -- short-range (SMG / shotgun)
		MinRange = 0,
		AttackDamage = 15,
		AttackCooldown = 0.32, -- very rapid
		Priority = 1,
		SightRange = 50,
		Ranged = true,
	},
	Scout = {
		RigName = "ScoutUnit",
		MaxHealth = 60,
		WalkSpeed = 22, -- fast recon
		AttackRange = 36,
		MinRange = 0,
		AttackDamage = 8,
		AttackCooldown = 0.6,
		Priority = 1,
		SightRange = 120, -- the longest eyes on the field
		FOV = 240, -- wide-eyed observer (others default to 160)
		Ranged = true,
	},
	Worker = {
		RigName = "WorkerUnit",
		MaxHealth = 50,
		WalkSpeed = 14,
		AttackRange = 0, -- non-combat
		AttackDamage = 0,
		AttackCooldown = 1,
		Priority = 1.4, -- juicy raid target: killing workers cripples the economy
		SightRange = 35,
		FOV = 130, -- heads-down, narrow awareness
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
	FocusWeight = 12, -- the leader's called focus target (low, so they don't all swarm one)
	Hysteresis = 20, -- bonus for keeping current target (stops thrashing)
	ThreatMemory = 3, -- seconds an attacker is remembered as a threat
	AcquireRange = 80, -- only acquire NEW targets within this (grid-limited, for perf)
}

-- What each team is made of (NOT counting the Leader, who is added on top).
-- Add more entries / bump Count to grow the army.
Config.Composition = {
	{ Type = "Rifleman", Count = 14 },
	{ Type = "Gunner", Count = 4 },
	{ Type = "Assault", Count = 4 },
	{ Type = "Scout", Count = 3 },
}

-- Economy: workers chop trees for WOOD; bases spend wood to grow workers, pump
-- troops, and upgrade. The base AI decides what to build based on its wood.
Config.Economy = {
	StartingWorkers = 2, -- each base starts with this many workers
	StartingWood = 50,
	MaxWorkers = 10,
	CarryCapacity = 14, -- wood a worker hauls per trip
	MinePerTick = 5, -- wood chopped per mine tick
	MineInterval = 0.4, -- seconds between mine ticks
	DepositRange = 14, -- how close to base to drop off wood
	DecisionInterval = 0.8, -- how often the base AI makes a build decision

	-- Cost in wood to produce each thing.
	WorkerCost = 18,
	Costs = {
		Rifleman = 15,
		Gunner = 30,
		Assault = 20,
		Scout = 14,
	},

	Trees = {
		Count = 36, -- trees scattered on the map
		Wood = 160, -- wood per tree before it's used up
		Scatter = 230, -- radius around map center to scatter them
		MinFromBase = 38, -- keep them clear of the bases
	},

	Upgrade = {
		BaseCost = 70, -- wood; actual cost = BaseCost * (level + 1)
		MaxLevel = 5,
		HealthPerLevel = 350, -- each upgrade adds this much base HP (and heals)
		WorkerTargetBase = 4, -- worker goal at level 0 ...
		WorkerTargetPerLevel = 2, -- ... +this per upgrade (capped at MaxWorkers)
		TroopCapBase = 18, -- army cap at level 0 ...
		TroopCapPerLevel = 10, -- ... +this per upgrade
	},
}

-- Stamina (no UI). Sprinting/charging/fleeing drains it; walking regenerates.
-- When it hits zero a unit is Exhausted and slows right down until it recovers
-- -- so soldiers who run away eventually get caught (especially by cavalry).
Config.Stamina = {
	Max = 100,
	Drain = 32, -- per second while sprinting
	Regen = 14, -- per second while not sprinting
	SprintMult = 1.6, -- sprint speed = BaseSpeed * this
	ExhaustedMult = 0.55, -- exhausted speed = BaseSpeed * this
	RecoverThreshold = 45, -- must regen to here before sprinting again
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
	-- within this range; otherwise it fights whoever's nearest. Kept fairly
	-- short so the army spreads across the front instead of swarming one target.
	FocusRange = 35,
	-- Shape of the marching formation.
	FormationSpacing = 5, -- studs between soldiers
	FormationColumns = 6, -- soldiers per row

	-- Morale: soldiers fighting near a living Leader hit harder. If the Leader
	-- dies, the whole army loses its edge.
	MoraleRange = 35,
	MoraleDamageBonus = 1.3, -- +30% damage near the leader
	LeaderlessDamagePenalty = 0.75, -- -25% damage with no leader alive

	-- How hard units avoid piling on top of each other. Set above melee reach so
	-- they hold a spaced line in combat instead of stacking into a pile.
	SeparationRadius = 7,

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

	-- Home defense (leader objective): if a KNOWN enemy gets within this of our
	-- own base, the army turns around and rushes home to defend it.
	DefendRadius = 70,

	-- How far from the battlefield center scouts roam to search for the enemy
	-- (and their bases) when the team has no intel.
	ScoutRoamRadius = 170,
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

-- Icon shown above each unit so you can read the battle from above.
Config.Icons = {
	Rifleman = "🔫",
	Gunner = "🎯",
	Assault = "💥",
	Scout = "🔭",
	Worker = "⛏️",
	Leader = "⭐",
}

-- Workers: non-combat units that hang around the base and FLEE from enemies.
-- More living workers = faster reinforcements, so raiding an enemy's workers
-- slows their whole army's regen. They're a high-value target for that reason.
Config.Workers = {
	CountPerTeam = 4,
	RespawnBoost = 0.13, -- each living worker shortens the reinforcement timer
	FleeRange = 42, -- run from a known enemy within this range
	WanderRadius = 24, -- how far from base they mill about while working
}

-- Bases: each team has one. It respawns reinforcements while it stands; destroy
-- it and that team can't replace losses. Auto-built behind each spawn marker.
Config.Base = {
	Health = 900,
	RespawnInterval = 1.6, -- seconds between reinforcements from a living base
	SetbackFromSpawn = 22, -- studs the base sits behind the spawn marker
	Icon = "🏰",

	-- Watchtower (Phase 4): each base has one that gives the team standing vision
	-- around home, so it can't be sneak-attacked at its base without spotting it.
	WatchtowerRange = 90,
}

-- Fog of war (Prison-Architect style). Units only know what they (or a teammate)
-- can see; sightings are shared and remembered as "last-known" positions after
-- sight is lost. Vision is a forward CONE (per-type FOV, default 160 degrees) up
-- to SightRange, blocked by walls -- so units are blind to their sides/rear and
-- can be flanked or ambushed from outside the cone.
Config.Vision = {
	Interval = 0.2, -- seconds between vision recomputations (throttled = cheap)
	Memory = 8, -- seconds a lost enemy is remembered before being forgotten
	ForgetRadius = 12, -- reach a last-known spot and see nothing -> forget it
	AmbushBonus = 1.6, -- damage multiplier when you strike someone who can't see you
	NearRadius = 14, -- all-round awareness this close (you notice someone adjacent)
	ShowCones = true, -- attach a visible vision cone to each unit (shown with V)
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
