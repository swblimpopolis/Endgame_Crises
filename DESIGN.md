# Endgame Crises — design

The build order, the exact unique strings and the spike-test protocol live in the
Unciv Modding Reference, under **Build a mod → Endgame Crises**:

<https://claude.ai/artifact/CqBbHGttdaGPS1BFv5fR5s>

That page is the working surface — uniques there are click-to-copy and render with
the same highlighting as the rest of the reference, and searching it covers both
the plan and the underlying unique definitions. This file holds only what belongs
in version control: the findings that shaped the design, and the answers to the
tests.

## What the mod is

An **extension mod** on `Civ V - Gods & Kings`. Late in the game a hostile faction
wakes up, attacks every civ indiscriminately, escalates in waves, and can only be
outlived. Modelled on the Stellaris endgame crisis.

Decisions made up front: one crisis end to end, original Unciv-flavored theme,
random trigger inside a window, escalating waves, forced cooperation, strength
controlled by the player via game difficulty, and resolution through a new
**Survival** victory condition.

## Engine constraints

Verified against `UniqueType.class` and the decompiled logic in Unciv 4.21.18.
These are why the design looks the way it does, and each one killed an obvious
alternative:

1. **You cannot create a civilization mid-game.** Civs are built once, by
   `GameStarter`. No unique, event or trigger anywhere makes a new one. The crisis
   can never be a real nation with its own cities, AI, diplomacy or score.

2. **The crisis must *be* the Barbarians.** Permanent war is hardcoded in
   `DiplomacyFunctions.isAtWarWith`, which short-circuits on `isBarbarian()` — and
   `isBarbarian` is literal name equality against `"Barbarians"`. Exactly one
   barbarian civ exists and a second cannot be added. The upside is that being
   Barbarians grants permanent war, immunity to peace deals and exclusion from the
   diplomacy screen for free.

3. **`[N] [unit]s rebel` is the only spawner.** It is the one unique that gives
   units to a hostile civ. In `GlobalUniques.json` it fires for every civ, which is
   exactly the "attacks all empires indiscriminately" behaviour.

Consequences worth not rediscovering:

- Barbarians bypass `NextTurnAutomation`, so `Personalities.json` and AI aggression
  tuning do not reach them. The crisis can be strong and numerous, never smart.
- Unit max HP is fixed at 100 — not a field, not a unique.
- `barbarianBonus` is a bonus *to the player* fighting barbarians and is already 0
  at Deity, so there is no headroom there.
- There is no "survive N turns" victory milestone. Only nine milestone types exist.
- `cityFilter` for the capital is `in capital`, not `in your capital`.

## Spike results

Two assumptions carry the design. Record the answers here once tested — the
protocol for both is in the artifact under Phase −1.

| Test | Question | Result |
|---|---|---|
| A | Does `<if [X] is constructed by anybody>` see a **trigger-granted** building? | _untested_ |
| B | Do Barbarians evaluate `GlobalUniques` `<upon turn start>` triggers? | _untested_ |

Tested against Unciv version: _____

**If A is false**, the flag mechanism has to change: fall back to a marker Policy
(`Adopt [policy/belief]` + `<after adopting [policy/belief]>`), which is per-civ
rather than global, so the crisis would begin independently for each civ. Phases
3–7 shift with it.

**If B is true**, every global `<upon turn start>` trigger fires an extra time with
barbarians as the beneficiary — halve all wave sizes.

## Validating this mod

`mod-ci` on an extension mod validates it in isolation, so every base-ruleset name
(`Rifleman`, `Nuclear Fission`) is reported as "does not fit parameter type". Those
are false alarms. For a real answer, merge into a full base ruleset first — see the
recipe in `../CLAUDE.md`. That merge is the only check that catches bad unique
*text*; the JSON schema extension won't, because its Uniques schema is just
`type: string`.
