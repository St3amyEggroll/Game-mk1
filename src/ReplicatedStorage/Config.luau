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

-- What each team is made of. Add more entries / bump Count to grow the army.
-- Milestone 2 = melee only. We'll add a Ranged line here in Milestone 3.
Config.Composition = {
	{ Type = "Melee", Count = 5 },
}

-- How units are arranged when they spawn (a grid near the spawn marker).
Config.SpawnSpacing = 4 -- studs between units
Config.SpawnColumns = 5 -- units per row

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
