# DST FX & Sound Reference for Reisen Mod

Quick lookup for `SpawnPrefab` FX names and `SoundEmitter:PlaySound` paths
available in vanilla DST. All entries verified from `scripts/fx.lua` or
`scripts/stategraphs/SGwilson.lua` inside `data/databundles/scripts.zip`.

---

## Release Mind Blowing — current choices

### Mode A: Mind Blowing (`accum > 0`, `castspell` animation)

| Role | Type | Value | Notes |
|---|---|---|---|
| Caster position | FX | `"attune_out_fx"` | Energy radiating outward from the caster |
| Target position | FX | `"moonpulse_fx"` | Expanding moon-pulse shockwave; visualises AoE radius |
| Per hit enemy | FX | `"sanity_lower"` | Sanity-disruption flash on each hostile that takes damage |
| Sound | Sound | `"maxwell_rework/shadow_magic/cast"` | Deep shadow-magic cast; fits the insanity cost theme |

### Mode B: Slow Field (`accum = 0`, `doshortaction` animation)

| Role | Type | Value | Notes |
|---|---|---|---|
| Target position | FX | `"slingshot_aoe_fx"` + `:SetColorType("slow")` | Official DST slow-AoE ripple; blue-purple wave |
| Sound | Sound | `"dontstarve/common/nightmareAddFuel"` | Nightmare-energy injection feel; distinct from Mode A |

---

## StateGraph action state names

Pass as the second argument to `AddStategraphActionHandler`.

| State | Animation | Duration | Notes |
|---|---|---|---|
| `"castspell"` | `staff_pre` → `staff` | ~4 s | Spawns `staffcastfx` + light; action fires at frame 53 |
| `"castspellmind"` | mind-cast variant | ~4 s | Alternative cast pose |
| `"doshortaction"` | `pickup` → `pickup_pst` | ~0.5 s | Action fires at frame 6 |
| `"dolongaction"` | long-work | ~2 s | Hammer/saw-style |
| `"domediumaction"` | medium-work | ~1 s | |
| `"dostandingaction"` | standing (no bend) | ~0.5 s | |
| `"give"` | hand-forward | short | |
| `"throw"` | throw | short | |
| `"book"` | page-flip | ~2 s | Wickerbottom book |

---

## FX prefabs (`SpawnPrefab`)

All entries are in `scripts/fx.lua` unless noted with `*` (separate prefab file).

### Explosion / Impact

| Name | Description |
|---|---|
| `"explode_small"` | Small explosion with sound |
| `"groundpound_fx"` | Ground shockwave ring |
| `"shadowstrike_slash_fx"` | Shadow slash arc |
| `"shadowstrike_slash2_fx"` | Shadow slash arc (variant 2) |
| `"moonpulse_fx"` | Moon pulse expanding wave (**Mode A target**) |
| `"moonpulse2_fx"` | Larger moon pulse |

### Smoke / Dissipation

| Name | Description |
|---|---|
| `"small_puff"` | Small white puff + death-poof sound |
| `"sand_puff"` | Dirt/sand burst |
| `"shadow_puff"` | Semi-transparent black smoke |
| `"shadow_puff_solid"` | Solid black smoke |
| `"shadow_puff_solid_large"` | Large solid black smoke |
| `"dirt_puff"` | Dirt burst |
| `"maxwell_smoke"` | Maxwell disappear smoke |
| `"die_fx"` | Brown death poof |

### Magic / Light

| Name | Description |
|---|---|
| `"statue_transition"` | Stone-to-life light effect |
| `"statue_transition_2"` | Brighter version |
| `"attune_out_fx"` | Energy radiating outward from entity (**Mode A caster**) |
| `"attune_in_fx"` | Energy converging inward |
| `"spawn_fx_small"` | Small summoning ring |
| `"spawn_fx_medium"` | Medium summoning ring |
| `"spawn_fx_large"` | Large summoning ring |
| `"spawn_fx_huge"` | Huge summoning ring |
| `"sanity_raise"` | Blue sanity-up wave (**Mode A per-target**) |
| `"sanity_lower"` | Sanity disruption flash |
| `"ghost_transform_overlay_fx"` | Ghost-transform overlay |
| `"ghostlyelixir_player_slowregen_fx"` | Purple slow-regen transform overlay on the player |
| `"ghostlyelixir_slowregen_dripfx"` | Per-entity drip effect placed at the target's feet; indicates the entity is currently slowed |

### Slow / AoE Field

| Name | Description |
|---|---|
| `"slingshot_aoe_fx"` + `:SetColorType("slow")` | Blue-purple slow-field ripple (**Mode B**) |
| `"slingshot_aoe_fx"` + `:SetColorType("ice")` | Ice AoE ripple |
| `"slingshot_aoe_fx"` + `:SetColorType("shadow")` | Shadow AoE ripple |
| `"slingshot_aoe_fx"` + `:SetColorType("horror")` | Horror (red) AoE ripple |
| `"slingshot_aoe_fx"` + `:SetColorType("lunar")` | Lunar AoE ripple |
| `"sleepbomb_burst"` | Purple sleep-bomb burst |
| `"purebrilliance_mark_hit_fx"` | Pure brilliance mark hit |

### Wortox / Soul

| Name | Description |
|---|---|
| `"wortox_soul_spawn_fx"` | Soul appearing |
| `"wortox_soul_heal_fx"` | Green soul-heal light |
| `"wortox_decoy_explode_fx"` | Decoy explosion |
| `"wortox_resist_fx"` | Resist/block effect |

### Ice / Electric

| Name | Description |
|---|---|
| `"icespike_fx_1"` – `"icespike_fx_4"` | Ice spike variants |
| `"shock_fx"` | Electric shock |

### Planar

| Name | Description |
|---|---|
| `"planar_resist_fx"` | Planar resistance |
| `"planar_hit_fx"` | Planar hit |

---

## Sounds (`SoundEmitter:PlaySound`)

### Staff / Magic cast

| Path | Description |
|---|---|
| `"dontstarve/wilson/use_gemstaff"` | Default staff cast (`castspell` state) |
| `"dontstarve/common/staffteleport"` | Yellow Lazy Explorer teleport |
| `"dontstarve/common/staff_star"` | Star sparkle |
| `"dontstarve/common/staff_dissassemble"` | Staff disassemble |
| `"maxwell_rework/shadow_magic/cast"` | Maxwell shadow-magic cast (**Mode A**) |
| `"meta4/casting/lunar"` | Lunar casting |
| `"meta4/casting/shadow"` | Shadow casting |

### Wortox / Soul

| Path | Description |
|---|---|
| `"dontstarve/characters/wortox/soul/heal"` | Soul heal |
| `"dontstarve/characters/wortox/soul/hop_out"` | Soul hop |

### Nightmare / Lunacy

| Path | Description |
|---|---|
| `"dontstarve/common/nightmareAddFuel"` | Nightmare fuel added (**Mode B**) |
| `"dontstarve/common/destroy_magic"` | Magic broken |
| `"dontstarve/cave/nightmare_fissure_open"` | Nightmare fissure opens |

### General action

| Path | Description |
|---|---|
| `"dontstarve/common/deathpoof"` | Dissipate poof |
| `"dontstarve/common/rebirth"` | Rebirth |
| `"dontstarve/common/freezecreature"` | Freeze creature |
| `"dontstarve/wilson/attack_weapon"` | Weapon swing |
| `"dontstarve/wilson/attack_whoosh"` | Attack whoosh |

### Hit / Block

| Path | Description |
|---|---|
| `"dontstarve/wilson/hit"` | Generic Wilson hit/hurt sound; used when dodge absorbs a hit (no stun interrupt) |
| `"dontstarve/wilson/hit_nightarmour"` | Night armour block sound; used when the uniform (heavy) absorbs a hit |
| `"dontstarve/wilson/hit_armour"` | Standard armour block sound; used when the casual outfit absorbs a hit |

---

## Notes

- `"castspell"` auto-spawns `staffcastfx` + `staff_castinglight` and plays
  the held item's `castsound` (falls back to `"dontstarve/wilson/use_gemstaff"`).
  Play a custom sound in the action `fn` to override the feel.
- FX prefabs from `fx.lua` auto-remove themselves when their animation ends;
  no manual cleanup needed.
- `SpawnPrefab` calls in action functions run server-side only; for client-side
  visual-only FX consider `net_event` or rely on the server spawning networked
  prefabs.
