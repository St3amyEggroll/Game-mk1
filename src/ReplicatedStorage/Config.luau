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

	-- Obstacle avoidance: units cast a short ray ahead and steer around walls
	-- and cover. This is what makes them ready for the obstacles you'll add.
	ObstacleLookAhead = 10, -- studs to look ahead for an obstacle
	ObstacleAvoidStrength = 8, -- how hard to veer around it
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
