# Game-mk1 — Roblox Mass Battle Simulator

Small AI soldiers fight autonomously, last team standing wins. Synced into
Roblox Studio with [Rojo](https://rojo.space).

---

## What's in the repo

```
default.project.json          Rojo mapping (repo files -> Studio)
src/
  ReplicatedStorage/
    Config.luau               every tunable number
  ServerScriptService/
    BattleSim.server.luau     main loop (the conductor)
    Modules/
      UnitManager.luau        master table of all units
      SpawnSystem.luau        spawns the armies
      TargetingSystem.luau    picks who fights who
      CombatSystem.luau       move + attack
docs/GameDesignDocument.md    the plan
```

Rojo only manages those scripts. Anything **you** build in Studio (rigs,
battlefield, spawn parts) is left untouched.

---

## One-time setup in Studio (your part)

You build the visuals; the code does the brains. Create these by hand:

### 1. The battlefield
In **Workspace**, add a big flat `Part` named **`Battlefield`**
(e.g. size `512 x 1 x 512`), anchored, sitting at the world floor.

### 2. Spawn markers
Two small `Part`s in **Workspace**, anchored, at opposite ends of the
battlefield:
- **`TeamASpawn`** (Blue army)
- **`TeamBSpawn`** (Red army)

They can be tiny or invisible — they're just position references. Put them a
few studs above the floor.

### 3. The soldier rig
- In **ReplicatedStorage**, create a `Folder` named **`Assets`**.
- Open the **Rig Builder** plugin (Avatar tab) and insert a **Block R6** rig.
- Scale it small (your "small humanoid" — e.g. ~0.6 scale).
- Rename the model to **`MeleeUnit`** and move it into `ReplicatedStorage/Assets`.

> The rig just needs a `Humanoid` and a `HumanoidRootPart` — every R6 dummy has
> both. (You'll add a `RangedUnit` rig in Milestone 3.)

---

## Connect Rojo

1. Install the Rojo plugin in Studio + the Rojo CLI on your machine.
2. From this folder run:
   ```
   rojo serve
   ```
3. In Studio, open the **Rojo** plugin → **Connect**.

The scripts appear under `ReplicatedStorage` and `ServerScriptService`.

---

## Run it

Press **Play** in Studio. You should see:
- two armies spawn at the markers,
- they march toward each other,
- a melee clash,
- the Output window prints the winner,
- it restarts after a few seconds.

Nothing happening? Check **Output** — `SpawnSystem` warns by name if a rig or
spawn marker is missing.

---

## Tuning

Open `src/ReplicatedStorage/Config.luau`. Change army size (`Composition`),
damage, health, speed, colors — save, and Rojo pushes it live. No other file
needs touching.
