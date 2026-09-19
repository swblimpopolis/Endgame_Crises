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

Assumptions the design rests on. Record answers here once tested — the protocol
is in the artifact under Phase −1.

| Test | Question | Result |
|---|---|---|
| A | Does `<if [X] is constructed by anybody>` see a **trigger-granted** building? | **YES** |
| B | Do Barbarians evaluate `GlobalUniques` `<upon turn start>` triggers? | **YES** |
| C | Can Barbarians **own a city**? | _untested — needed before Phase 5_ |

Tested against Unciv 4.21.18.

**A is confirmed.** All four steps behaved as predicted — baseline gold fired, the
Beacon was granted, the `is constructed by anybody` gold fired afterwards, and the
trailing `is not constructed` control correctly did *not* fire. The hidden-building
flag is therefore a valid substitute for the mod-writable state Unciv doesn't have,
and the one-shot trigger, the stage-marker escalation chain and the Survival
victory all rest on solid ground. No Policy fallback needed.

**Confirmed while testing B:** global `<upon turn start>` triggers fire for every
major civ **and for city-states**. So crisis waves will spawn at city-state cities
too — which is the indiscriminate behaviour the design wants, but it means
city-states contribute to the total spawn count. Budget wave sizes accordingly.

**B is confirmed yes.** A barbarian-owned marker appeared once barbarians had at
least one unit on the map to place it beside. (The first run was a false negative:
`Free [unit] appears` resolves a placement target in order — a city, else a tile
from context, else next to the civ's first existing unit, else it aborts. With no
barbarian units and no barbarian cities there was nowhere to put one.)

### What B=yes changes

**Anything triggerable placed in `GlobalUniques.json` also fires for the
Barbarians.** Three consequences, in order of severity:

1. **The crisis trigger must exclude them.** If barbarians can roll
   `Triggers a [The Awakening] event`, they will eventually fire it — the event
   auto-resolves for AI civs, so its choice runs, `Triggers the following global
   alert` announces the crisis to everyone, and then
   `Gain a free [Crisis Beacon] [in capital]` silently aborts because barbarians
   have no capital. Result: the world is told the crisis began, the flag is never
   set, and no waves ever spawn. Guard every crisis trigger with
   `<when number of [Cities] is more than [0]>` — barbarians own zero cities;
   city-states own at least one, so they still take part.
2. **`Free [unit] appears` uniques arm the crisis.** The Phase 5 emergency
   mobilization (`[2] free [Rifleman] units appear`) would hand free Riflemen to
   the barbarians. Move it onto a Policy or Building, or apply the same
   cities-greater-than-zero guard.
3. **Waves are safe.** `[N] [unit]s rebel` requires a city and aborts without one,
   so wave sizes do not double. No rebalancing needed.

### C — can Barbarians own a city?

**Why it matters.** Two load-bearing mechanisms assume barbarians own zero cities:

- `<when number of [Cities] is more than [0]>` is what stops them firing the
  crisis trigger (see B, consequence 1). A barbarian holding one city makes that
  guard fail open.
- `[N] [unit]s rebel` aborts for a civ with no city. A barbarian holding a city
  makes the wave uniques start working *for the crisis*, spawning a second wave
  at the captured city every tick.

**Why it's now live rather than theoretical.** `Destroys [cityFilter] cities
instead of capturing` — the unique on Crisis Knight — is documented as:

> The unit will destroy [cityFilter] cities instead of capturing them, also allows
> non-melee units to destroy cities. Capital cities (including city states) are
> immune to this effect.

So capitals are *not* razed, and the fallback is ordinary capture. Whether the
engine then lets the Barbarians hold it, razes it anyway, or hands it elsewhere is
unconfirmed — static analysis found the raid/pillage branch in `Battle` but the
capture path for barbarians was not fully traced.

**How to test.** Extension mod, small map. Give yourself a throwaway unit with
`Destroys [All] cities instead of capturing` and high strength, let a barbarian
melee unit take one of your non-capital cities, then a capital. After each,
check the Barbarians in the nations overview for a city count. Faster variant:
one city, deliberately undefended, and watch what the notification says —
"destroyed" vs "captured" answers it immediately.

**If C is yes**, the guard has to change from a cities count to something
barbarians can never satisfy, and the wave uniques need their own exclusion.
Candidates to check at that point: `<for [civFilter] Civilizations>` (the filter
has no barbarian value, so it may not help), or gating on a marker Building that
only a real civ can hold.

### Delivery is not guaranteed, and not uniform

Observed: on a `<every [10] turns>` spawn, **most** civs and city-states received
their unit on the same game turn, but some received it only on a later tick. So
global triggers are not a reliable "every civ, every time" broadcast.

Two candidate explanations, neither yet confirmed:

- **Placement failure, retried on the next tick.** `Free [unit] appears` has to
  find somewhere to put the unit; if the capital and its surroundings are full
  (one military unit per tile), the trigger fails silently that turn and succeeds
  10 turns later when there is room. This is the more likely cause and it is
  testable — spawn `<every [2] turns>` into a deliberately crowded city and see
  whether the misses correlate with congestion.
- **Observation lag.** AI civs resolve their turns after the human's, so a spawn
  on the AI's turn N is only visible to the human on turn N+1. This would explain
  a uniform one-turn offset but not why *some* civs lagged and others didn't.

**What this means for the mod either way:** do not assume a wave unique delivers to
every civ on every tick. Crisis waves use `[N] [unit]s rebel`, which places at the
city centre and so is less fragile than `Free [unit] appears`, but a besieged or
unit-packed city can still swallow a spawn. Budget waves on the assumption that
some fraction will silently not arrive, and prefer more frequent small waves over
rare large ones so a single failure matters less.

## Validating this mod

`mod-ci` on an extension mod validates it in isolation, so every base-ruleset name
(`Rifleman`, `Nuclear Fission`) is reported as "does not fit parameter type". Those
are false alarms. For a real answer, merge into a full base ruleset first — see the
recipe in `../CLAUDE.md`. That merge is the only check that catches bad unique
*text*; the JSON schema extension won't, because its Uniques schema is just
`type: string`.
