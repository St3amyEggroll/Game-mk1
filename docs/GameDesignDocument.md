# Game-mk1 — Design Document

A living doc. Updated as the project grows.

## Vision

A modern-military **mass battle simulator** in Roblox. Lots of small AI humanoid
soldiers — mixed **melee + ranged** — fight autonomously until one side is wiped
out. **Last team standing wins.** Built to scale toward **100v100+**, with player
"commander" control added later.

Build philosophy: get the AI battle looking good *on its own first*. Once the
fighting is fun to watch, adding player control on top is the easy part.

## Pillars

1. **Autonomous AI** — soldiers find targets, fight, and die with no player input.
2. **Scale** — the architecture must reach hundreds of units without lag.
3. **Readable battles** — you can look at the field and understand what's happening.

## Core loop (current)

Spawn two armies → they march at each other → melee clash → last team standing
wins → auto-restart.

## Architecture (the important part)

Everything is **data-oriented**: one central loop in `BattleSim` walks a single
table of unit rows (`UnitManager.Units`). There is **no per-soldier Script**.
This is the decision that makes 100v100 possible later.

- **Config** — every tunable number.
- **UnitManager** — the master table of units; register / query / prune.
- **SpawnSystem** — clone rigs, build Leader + formation, register them.
- **CommandSystem** — the Leader's brain: sets each team's Order / RallyPoint /
  FocusTarget once per tick. This is the seam a player Leader plugs into later.
- **TargetingSystem** — pick who to fight (focus target, then nearest).
- **CombatSystem** — formation advance, close + face + attack, separation, morale.
- **BattleSim** — the conductor: spawn, tick everyone, check win, restart.

### How a unit thinks each tick
1. `CommandSystem` (Leader) sets the team plan: Advance vs Engage, where to
   rally, who to focus.
2. `TargetingSystem` picks the unit's target (focus-fire when in range).
3. `CombatSystem` either marches to its formation slot (Advance) or closes,
   faces, and attacks its target (Engage) — hitting harder near a live Leader.

Two optimization habits are baked in from day one:
- units "think" 10×/sec (`SimTick`), not every frame;
- one loop over a table, not many scripts.

## Milestones

| # | Goal | Status |
|---|------|--------|
| 1 | Spawn + march | ✅ done |
| 2 | Melee combat + last-team-standing | ✅ done |
| 2.5 | Leader + smarter AI (orders, formation, focus fire, morale) | ✅ done |
| 2.7 | Pathfinding, flanking + guard squads, HUD, death FX | ✅ done |
| 3 | Ranged units (projectiles / line-of-sight) | ⬜ next |
| 4 | Optimize to 100v100 (lightweight units, spatial targeting) | ⬜ |
| 5 | More polish (sound, kill streaks, win-screen stats) | ⬜ |
| 6 | Player commander takes over the Leader role | ⬜ |

### Roles & tactics (2.7 / 2.8)
- **Leader** hangs back and directs; pulls back further & self-defends when
  threatened.
- **Guards** screen the Leader, or form a defensive **ring** around him when
  he's threatened — the counter to focus-fire assassination.
- **Flankers** hold the line while advancing, then peel off **once engaged**
  and drive at the enemy's rear/leader.
- **Main** line advances (rally, or a defensive hold line), then engages.
- **Stance** (read the battle): Aggressive / Balanced / Defensive / Retreat,
  chosen each tick from the health ratio.
- **Threat assessment**: units prefer enemies attacking them or their leader,
  plus high-value targets (leader, later healers/artillery).
- **Hazards**: parts in a Workspace `Hazards` folder repel units and deal
  damage to anyone caught inside.
- **Collisions**: units physically collide (toggle `Config.UnitsCollide`).

### Unit roster (Phase 1)
- **Melee** — line infantry.
- **Spearman** — line infantry, **anti-cavalry** (2.5× vs Cavalry).
- **Archer** — shoots from range, kites away when crowded, needs line of sight.
- **Cavalry** — fast hit-and-run charger, rides a (cosmetic) horse.
- **Scout** — fast, fragile, longest sight (used by fog-of-war in Phase 2).
- **Stamina** (no UI): sprinting/charging/fleeing drains it; exhausted units
  slow down, so runners get caught.

### Big-feature roadmap
- **Phase 1 — units & bodies** ✅ (archers, spearmen, scouts, stamina, cavalry+horse)
- **Phase 2 — fog of war** ✅: see-only-what-you-see, shared team vision,
  last-known-position memory, vision blocked by walls, ambush bonus, scouts'
  long sight, spectator fog toggle (V). VisionSystem feeds CommandSystem +
  TargetingSystem; if a team sees nothing it advances on the nearest enemy spawn.
- **Phase 3 — bases & respawn** ✅: each team has a base that trickles out
  reinforcements while it stands; bases are discovered by sight (flare on first
  contact); units assault the discovered enemy base when no enemies are in view;
  a team is out only when its base is destroyed AND its units are dead.
  Unit icons above heads (read the battle from above).
- **Phase 4 — structures & strategy**: barracks/watchtower/walls/gates/depot,
  explicit leader objectives (rush/turtle/raid), dedicated scout-dispatch.

### Deferred AI
- Commit reserves (a held-back squad sent to a breaking flank).
- Automatic chokepoint funneling / high-ground seeking.
- Feints (fake a frontal push while flanking).
- **NavigationSystem** only pathfinds when an obstacle is actually in the
  line of sight to the goal (open field = one cheap ray per unit).
- **Client HUD**: action camera, survivor scoreboard, kill feed, win banner.
- **Death FX**: dust puff, ragdoll, fade.

## Known shortcuts to revisit

- **Targeting is O(n²)** — fine to ~20v20, replaced by a spatial grid in M4.
- **Movement uses `Humanoid:MoveTo`** — heavy at scale; M4 moves to lightweight
  CFrame units.
- **No pathfinding** — fine on a flat field; needed once obstacles exist.
