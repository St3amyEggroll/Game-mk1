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
| 3 | Ranged units (projectiles / line-of-sight) | ⬜ next |
| 4 | Optimize to 100v100 (lightweight units, spatial targeting) | ⬜ |
| 5 | Polish (health bars, death FX, stats UI) | ⬜ |
| 6 | Player commander takes over the Leader role | ⬜ |

## Known shortcuts to revisit

- **Targeting is O(n²)** — fine to ~20v20, replaced by a spatial grid in M4.
- **Movement uses `Humanoid:MoveTo`** — heavy at scale; M4 moves to lightweight
  CFrame units.
- **No pathfinding** — fine on a flat field; needed once obstacles exist.
