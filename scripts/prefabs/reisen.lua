--[[
============================================================
  Reisen Udongein Inaba  —  Character Script
============================================================
  All tuneable parameters are in the CONFIGURATION block
  immediately below the module header. Each feature section
  contains its own description and constants, so you can
  find, read, and modify any mechanic in one place.

  Starting items: manrabbit_tail ×1, carrot ×3, monsterlasagna ×1
  External item mechanics: see reisen_charm.lua, reisen_uniform.lua
============================================================
]]

local MakePlayerCharacter = require "prefabs/player_common"
local ReisenConsts = require "reisen_consts"
local ReisenPerf = require "reisen_perf"
local ReisenUtil = require "reisen_util"

local assets = { Asset("SCRIPT", "scripts/prefabs/player_common.lua") }
local prefabs = { "manrabbit_tail", "reisen_boostfx", "reisen_petalring", "ghostlyelixir_player_slowregen_fx" }
local start_inv = { "manrabbit_tail", "carrot", "carrot", "carrot", "monsterlasagna" }

-- ════════════════════════════════════════════════════════════════════════
--  CONFIGURATION
--  All tuneable parameters live here, grouped by feature.
-- ════════════════════════════════════════════════════════════════════════

-- ── Base Stats ──────────────────────────────────────────────────────────
--  HP / Hunger / Sanity pool sizes and baseline rates.
local REISEN_MAX_HEALTH       = 300
local REISEN_MAX_HUNGER       = 200
local REISEN_MAX_SANITY       = 100
local REISEN_BASE_HUNGER_MULT = 0.85          -- × WILSON_HUNGER_RATE at idle
local REISEN_INSULATION_MULT  = 1.5           -- × TUNING.INSULATION_PER_BEARD_BIT

-- ── Carrot Streak Sanity ────────────────────────────────────────────────
--  Eating a carrot: clears lunatic stack, then grants a tiered sanity bonus.
--  Streak persists for one full in-game day (cycles difference <= 1).
--  If the streak expires, tier decreases by 1 instead of resetting to 0.
--    Tier 1 → +25  |  Tier 2 → +50  |  Tier 3 → +100
local CARROT_SANITY_MAX_TIER    = 3
local CARROT_SANITY_BY_TIER     = { [1] = 25, [2] = 50, [3] = 100 }

-- ── Lunatic Stack: Gain & Decay ─────────────────────────────────────────
--  Stack range: 0 – REISEN_LUNATIC_MAX.
--  Gain:  +1 per successful attack hit (onhitother).
--  Decay: −1 per interval; interval depends on zone and boosted mode.
--
--  Zone        | Stack range | Normal delay | Boosted delay
--  ────────────┼─────────────┼──────────────┼──────────────
--  base        | ≤ 1         | 1.5 s        | 1.0 s
--  hi          | 2 – 7       | 2.5 s        | 2.0 s
--  max         | 8 – 10      | 3.0 s        | 2.5 s
local REISEN_LUNATIC_MAX             = ReisenConsts.LUNATIC_MAX
local REISEN_LUNATIC_DECAY_TIME      = 2.0    -- normal, zone base (stack ≤ 1)
local REISEN_LUNATIC_DECAY_TIME_HI   = 2.5    -- normal, zone hi  (stack 2–8)
local REISEN_LUNATIC_DECAY_TIME_MAX  = 3.0    -- normal, zone max (stack 9–11)
local REISEN_LUNATIC_DECAY_BOOST     = 1.5    -- boosted, zone base
local REISEN_LUNATIC_DECAY_BOOST_HI  = 2.0    -- boosted, zone hi
local REISEN_LUNATIC_DECAY_BOOST_MAX = 2.5    -- boosted, zone max

-- ── Lunatic Stack: Tier Effects ─────────────────────────────────────────
--  Effects are cumulative as stack grows.

--  stack > 0 (non-boost) ── passive move speed bonus (flat, any stack level).
local REISEN_LUNATIC_MOVE_SPEED_MULT = 1.30

--  Boost mode: second locomotor key; multiplies with REISEN_LUNATIC_MOVE_SPEED_MULT when stack>0.
local REISEN_BOOST_MOVE_MULT_START = 1.05
local REISEN_BOOST_MOVE_MULT_MIN = 1.00
local REISEN_BOOST_MOVE_MULT_MAX = 1.05
local REISEN_BOOST_MOVE_MULT_STEP = 0.01

--  stack > REISEN_LUNATIC_STACK_LOW_THRESH ── burst speed when hit (dodge reaction)
--  weapon combat: efficientuser ACTIONS.ATTACK mult while LOW < stack (no HI cap; see Weapon:OnAttack)
local REISEN_LUNATIC_STACK_LOW_THRESH    = ReisenConsts.LUNATIC_STACK_LOW
local REISEN_DODGE_SPEED_MULT     = 1.50       -- multiplier during the burst
local REISEN_DODGE_SPEED_DURATION = 0.50       -- burst duration in seconds
local REISEN_DODGE_COOLDOWN       = 4 * REISEN_DODGE_SPEED_DURATION  -- min gap between dodge triggers
local REISEN_LUNATIC_WEAPON_DURABILITY_MULT = 0.5

--  stack > REISEN_LUNATIC_STACK_MID_THRESH ──
--    • incoming HP damage × SAN_CONVERSION_FRAC also drained as sanity loss
--    • vulnerability absorb penalty partially offset (capped at 0)
local REISEN_LUNATIC_STACK_MID_THRESH        = ReisenConsts.LUNATIC_STACK_MID
local REISEN_LUNATIC_SAN_CONVERSION_FRAC     = 0.75
local REISEN_LUNATIC_VULN_RELIEF_CAP_NORMAL  = 0.75   -- normal mode absorb relief cap
local REISEN_LUNATIC_VULN_RELIEF_CAP_BOOSTED = 0.5    -- boosted mode absorb relief cap

--  stack > REISEN_LUNATIC_STACK_HI_THRESH ──
--    • attack damagemultiplier scaled up
--    • hunger drain scaled up
local REISEN_LUNATIC_STACK_HI_THRESH  = ReisenConsts.LUNATIC_STACK_HI
local REISEN_LUNATIC_DAMAGE_MULT_HI   = 1.5
local REISEN_LUNATIC_HUNGER_MULT_HI   = 1.2

--  stack ≥ 1, on kill ── HP accumulation (active):
--    Each kill adds  min(stack+1, MAX) × REISEN_KILL_HP_PER_KILL  to a pending heal pool.
--    (+1 compensates for DST firing "killed" before "onhitother" increments the stack.)
--    Pool is capped at REISEN_KILL_HP_ACCUM_CAP (= ReisenConsts.RELEASE_HEAL_ACCUM_CAP).
--    Released manually via right-click Release Mind Blowing, OR automatically when
--    the lunatic stack decays to 0 in boosted mode / carrot reset after boost.
local REISEN_KILL_HP_PER_KILL         = ReisenConsts.KILL_HP_PER_KILL         -- HP accumulated per kill per (effective) lunatic stack (normal)
local REISEN_KILL_HP_PER_KILL_BOOSTED = ReisenConsts.KILL_HP_PER_KILL_BOOSTED -- HP accumulated per kill per (effective) lunatic stack (boosted)
local REISEN_KILL_HP_ACCUM_CAP = ReisenConsts.RELEASE_HEAL_ACCUM_CAP   -- hard ceiling on the pending heal pool

--  stack ≥ 1, on kill ── dapperness buff (REMOVED / reserved for future use):
--    While kill_buff_stacks > 0 (set on each kill, cleared when stack reaches 0),
--    add a flat sanity regen bonus in boosted mode:
--      inst.components.sanity.dapperness += REISEN_LUNATIC_KILL_SAN_COEFF × TUNING.DAPPERNESS_MED
--    To re-enable:
--      1. Uncomment the constant below.
--      2. Restore  inst._reisen_kill_buff_stacks  initialisation in onbecameghost and master_postinit.
--      3. Restore  i._reisen_kill_buff_stacks = 1  (gated on _reisen_lunatic_boosted) in the "killed" listener.
--      4. Restore  inst._reisen_kill_buff_stacks = 0  in reisen_apply_kill_hp_accum.
--      5. Restore the kill buff dapperness block in lunatic() before sync_reisen_vuln_absorb_modifier:
--           if (inst._reisen_kill_buff_stacks or 0) > 0
--               and inst._reisen_lunatic_boosted
--               and inst.components.sanity ~= nil then
--               inst.components.sanity.dapperness = inst.components.sanity.dapperness
--                   + REISEN_LUNATIC_KILL_SAN_COEFF * TUNING.DAPPERNESS_MED
--           end
-- local REISEN_LUNATIC_KILL_SAN_COEFF = 0.85

-- ── Evil Petals: food prefab lookup table & buff constants ───────────────────
--  Eating these foods grants +1 lunatic_stack and a petal buff:
--    • Petal buff: extends the current stack's decay timer by REISEN_PETAL_BUFF_TIME.
--    • During boosted state the bonus is 1/3 of normal.
--    • Being attacked while the buff is active cancels it and immediately drops 1 stack.
local REISEN_PETAL_BUFF_TIME        = 30.0    -- seconds added to decay delay (normal)
local REISEN_PETAL_BUFF_TIME_BOOST  = 10.0     -- seconds added to decay delay (boosted, 1/3)

local REISEN_EVIL_PETALS_FOODS = {
	petals_evil                    = true,
	petals_evil_dried              = true,
	hermitcrabtea_petals_evil      = true,
}

-- ── Boosted State (monster meat dishes / monster meat) ───────────────────────
--  Triggers (any): fills lunatic stack to max, boosted decay, same effects.
--    • FOODTYPE.MEAT + ("monstermeat" or "monster" tag) + healthvalue ≤ -20 AND sanityvalue ≤ -20
--      (covers monsterlasagna, monstertartare, crockpot outputs that inherit "monster")
--    Note: some dishes only expose "monster" on the cooked prefab; others use "monstermeat".
--    • full moon: matches pigman werebeast watching TheWorld.state.isfullmoon
--    • 4× MEAT foods with negative health on eat (TriggerLimit 4)
--  Boosted mode ends immediately when hunger reaches 0.
--    • extra hunger drain × ReisenConsts.BOOSTED_HUNGER_MULT on top of all tier bonuses
--    • healing received × (1 + REISEN_BOOSTED_HEAL_BONUS), i.e. effectively ×1.5
--    • in max zone (stack > HI_THRESH, i.e. 9–11): crit chance ramps from 0 up to
--      REISEN_BOOSTED_CRIT_MAX_CHANCE over REISEN_BOOSTED_CRIT_MAX_TIME seconds,
--      with a flat-zero delay of REISEN_BOOSTED_CRIT_RAMP_DELAY seconds first.
--      Curve: t_eff = clamp(t − DELAY, 0, MAX_TIME − DELAY)
--             chance = MAX_CHANCE × (t_eff / (MAX_TIME − DELAY)) ^ RAMP_POWER
--      Timer resets whenever the stack leaves max zone (or boosted ends).
--      Crit doubles post-armor damage (bonusdamagefn).
local REISEN_BOOSTED_HUNGER_MULT      = ReisenConsts.BOOSTED_HUNGER_MULT
local REISEN_BOOSTED_HEAL_BONUS       = 0.5    -- extra fraction added per heal event
local REISEN_BOOSTED_CRIT_MAX_CHANCE  = 0.25   -- crit probability ceiling (at t = MAX_TIME)
local REISEN_BOOSTED_CRIT_MAX_TIME    = 30.0   -- seconds to reach max chance
local REISEN_BOOSTED_CRIT_RAMP_DELAY  = 5.0    -- flat-zero window before ramp starts
local REISEN_BOOSTED_CRIT_RAMP_POWER  = 1.5    -- ease-in exponent (>1 = slow start, fast end)
-- Same as pigman werebeast SetTriggerLimit(4) + OnEat (MEAT, GetHealth < 0).
local REISEN_BOOSTED_MONSTER_MEAT_TRIGGER_LIMIT = 4
-- Forced sleep duration (seconds) when the 4th negative-health MEAT triggers boosted.
local REISEN_MEAT_SLEEP_DURATION = 3.0

-- ── Sanity Tiers ────────────────────────────────────────────────────────
--  lunatic() matches the first tier where sanity > san_min.
--  A special "zero" tier fires when sanity == 0 exactly.
--
--  Field glossary:
--    san_min      sanity threshold (exclusive lower bound)
--    dmg          combat.damagemultiplier
--    vuln         inst.vulnerable  (feeds into absorb modifier)
--    walk / run   locomotor speed multipliers × WILSON base
--    neg_aura     sanity.neg_aura_mult
--    night_drain  sanity.night_drain_mult
--    hunger       hungerrate multiplier × WILSON_HUNGER_RATE
--    dapper       sanity.dapperness = dapper × TUNING.DAPPERNESS_MED
--    light        nil = off; {r, fo, it} = radius / falloff / intensity
--
--  HP regen is NOT stored in the tier table; it is handled by a DoPeriodicTask
--  (see REISEN_HIGH_SAN_REGEN_HP_PER_S / REISEN_ZERO_SAN_REGEN_HP_PER_S below).
local REISEN_SANITY_TIERS = {
    -- san > 99  ── Peak clarity: fast, tank-lite, gentle regen
    { san_min=99, dmg=0.75, vuln= 0.00, walk=1.75, run=1.75, neg_aura=1.5, night_drain=0.5,  hunger=0.85, dapper= 0.15, light=nil },
    -- san 75–99 ── High clarity: normal damage
    { san_min=75, dmg=1.00, vuln=-0.25, walk=1.60, run=1.60, neg_aura=1.5, night_drain=1.0,  hunger=0.85, dapper=-0.85, light=nil },
    -- san 50–75 ── Mid: slight vulnerability
    { san_min=50, dmg=1.25, vuln=-0.50, walk=1.50, run=1.50, neg_aura=1.5, night_drain=1.5,  hunger=1.00, dapper=-0.85, light=nil },
    -- san 25–50 ── Low: light appears, stronger vuln
    { san_min=25, dmg=1.50, vuln=-0.75, walk=1.40, run=1.40, neg_aura=2.0, night_drain=1.5,  hunger=1.15, dapper=-0.85, light={r=2.5, fo=0.8, it=0.4} },
    -- san 0–25  ── Critical: heavy drain, red eyes
    { san_min=0,  dmg=1.75, vuln=-1.00, walk=1.35, run=1.35, neg_aura=2.0, night_drain=2.0,  hunger=1.30, dapper=-0.85, light={r=5, fo=0.6, it=0.5} },
}
-- san == 0 exact ── Lunatic floor: maximum penalty; bonus regen when well-fed.
local REISEN_SANITY_TIER_ZERO = {
    dmg=2.00, vuln=-1.25, walk=1.30, run=1.30, neg_aura=3.0, night_drain=3.0,
    hunger=1.50, dapper=-2.00,
    light = { r=8, fo=0.4, it=0.6 },
    -- When hunger > hunger_high_thresh × max: extra hunger drain.
    -- HP regen at this tier is handled by DoPeriodicTask (REISEN_ZERO_SAN_REGEN_HP_PER_S)(160hp at 1.33x1.5 hunger rate).
    hunger_high_thresh      = ReisenConsts.HUNGER_HIGH,
    hunger_high_extra_mult  = 1.33,
}

-- ── Health Regen (DoPeriodicTask, fixed rate) ────────────────────────────
--  Regen is applied on a periodic timer (not inside lunatic()) to guarantee
--  a stable HP/s regardless of how often lunatic() is called.
--    san > 99                                       → REISEN_HIGH_SAN_REGEN_HP_PER_S  HP/s
--    san == 0, well-fed, stack >= LUNATIC_STACK_LOW → REISEN_ZERO_SAN_REGEN_HP_PER_S  HP/s
--  "Well-fed" = hunger > REISEN_SANITY_TIER_ZERO.hunger_high_thresh × max
--  Extra hunger drain (hunger_high_extra_mult) also requires stack > 0.
--  Both regen paths skip the DoDelta call entirely when health is already full,
--  preventing spurious healthdelta events with data.amount == 0.
local REISEN_HIGH_SAN_REGEN_HP_PER_S = 0.5
local REISEN_ZERO_SAN_REGEN_HP_PER_S = 2.0
local REISEN_HEALTH_REGEN_PERIOD     = 1.0   -- seconds per regen tick
-- Shared light colour across all tiers that enable the light.
local REISEN_LIGHT_R, REISEN_LIGHT_G, REISEN_LIGHT_B = 255/255, 180/255, 20/255

-- ── Full Moon Luck ──────────────────────────────────────────────────────
local REISEN_FULLMOON_LUCK       = 10   -- luck bonus granted while isfullmoon

-- ── Zero-San Work Penalties ──────────────────────────────────────────────
--  san == 0: each hit contributes 0.75× work progress (CHOP/MINE/HAMMER/DIG).
--            tool durability consumed per hit is also 0.75× normal.
local REISEN_ZERO_SAN_WORK_MULT      = 0.75
local REISEN_ZERO_SAN_DURABILITY_MULT = 0.75

-- ── High-San Action Speed ────────────────────────────────────────────────
--  san > 99: PICK / HARVEST use "quagmire_fasthands" tag  → domediumaction
--            BUILD          uses "fastbuilder"       tag  → domediumaction

-- ── High-San Rowing Bonuses ──────────────────────────────────────────────
--  san > 99: rowing force (acceleration) multiplied by REISEN_HIGH_SAN_ROW_FORCE_MULT.
--            extra max velocity (absolute, added to oar.max_velocity) set to
--            REISEN_HIGH_SAN_ROW_EXTRA_MAX_VELOCITY.
--  Reference: TUNING.OARS.BASIC.MAX_VELOCITY = 2 → +1.0 ≈ +50% for basic oar.
--             TUNING.MIGHTY_ROWER_MULT = 1.33 (Wolfgang mighty reference).
local REISEN_HIGH_SAN_ROW_FORCE_MULT        = 1.33   -- ×1.33 rowing acceleration
local REISEN_HIGH_SAN_ROW_EXTRA_MAX_VELOCITY = 1.0   -- +1.0 max velocity (≈+50% basic oar)

-- ── Dualgear: shadow creature hit bonus ─────────────────────────────────
--  When both reisen_uniform (body) and reisen_charm (head) are equipped,
--  hitting a shadowcreature or nightmarecreature grants this many extra
--  lunatic stacks on top of the normal +1 (total = 1 + BONUS).
local REISEN_DUALGEAR_SHADOW_HIT_BONUS = 1

-- ── Internal key constants — do not tune ────────────────────────────────
local REISEN_CASUAL_PREFAB       = "reisen_casual"
local REISEN_UNIFORM_PREFAB      = "reisen_uniform"
local REISEN_CHARM_PREFAB        = "reisen_charm"
local REISEN_LUNATIC_SPEED_KEY   = "reisen_lunatic"
local REISEN_BOOST_SPEED_KEY     = "reisen_boost_move"
local REISEN_DODGE_SPEED_KEY     = "reisen_dodge"
-- local REISEN_PANIC_ATTACKER_SPEED_KEY = "reisen_panic_attacker"
local REISEN_VULN_ABSORB_SOURCE  = "reisen_vuln"
local REISEN_LUNATIC_VULN_SOURCE = "reisen_lunatic_vuln"
local REISEN_LUNATIC_WEAPON_DUR_SOURCE = "reisen_lunatic_weapon_dur"
local REISEN_FULLMOON_LUCK_KEY   = "reisen_fullmoon_luck"

-- ════════════════════════════════════════════════════════════════════════
--  END CONFIGURATION
-- ════════════════════════════════════════════════════════════════════════

local lunatic  -- forward declaration; defined below, referenced by onbecamehuman/onload

-- Effective sanity = the value the wearer perceives on the HUD.
-- Canonical implementation lives in scripts/reisen_util.lua; this is just
-- a local alias so existing call sites stay unchanged.
local get_effective_sanity = ReisenUtil.GetEffectiveSanity

-- ── Carrot helpers ──────────────────────────────────────────────────────

local function is_carrot_food(food)
	return food ~= nil
		and food.components ~= nil
		and food.components.edible ~= nil
		and (food.prefab == "carrot" or food.prefab == "carrot_cooked")
end

local function carrot_streak_days_expired(inst)
	if inst._reisen_carrot_cycle == nil then
		return 0
	end
	local diff = TheWorld.state.cycles - inst._reisen_carrot_cycle
	return math.max(0, diff - 1)      -- delay 1 day to avoid immediate streak reset
end

-- ── Molt / tail helpers ─────────────────────────────────────────────────

local function reisen_molt_required_days_per_tail()
	if not TheWorld:HasTag("cave") then
		return 2
	end
	return 2
end

-- ── Speech helpers ──────────────────────────────────────────────────────

local function reisen_say_hidden_hint(inst, key, cooldown)
	if inst == nil or inst.prefab ~= "reisen" or inst.components.talker == nil then
		return
	end
	local now = GetTime()
	inst._reisen_hidden_hint_cd = inst._reisen_hidden_hint_cd or {}
	local next_time = inst._reisen_hidden_hint_cd[key]
	if next_time ~= nil and now < next_time then
		return
	end
	inst._reisen_hidden_hint_cd[key] = now + (cooldown or 20)

	local speech = STRINGS.CHARACTERS
		and STRINGS.CHARACTERS.REISEN
		and STRINGS.CHARACTERS.REISEN[key]
	if type(speech) ~= "string" or speech == "" then
		return
	end
	inst.components.talker:Say(speech)
end

local function reisen_get_molt_season_key()
	if TheWorld == nil or TheWorld.state == nil then
		return "unknown"
	end
	local s = TheWorld.state.season
	if type(s) == "string" and s ~= "" then
		return s
	end
	if TheWorld.state.isspring then return "spring" end
	if TheWorld.state.issummer then return "summer" end
	if TheWorld.state.isautumn then return "autumn" end
	if TheWorld.state.iswinter then return "winter" end
	return tostring(TheWorld.state.cycles or 0)
end

local function reisen_say_molt_hint_once_per_season(inst, key)
	local season_key = reisen_get_molt_season_key()
	if inst._reisen_molt_hint_season ~= season_key then
		inst._reisen_molt_hint_season = season_key
		inst._reisen_molt_hint_spoken = false
	end
	if inst._reisen_molt_hint_spoken then
		return
	end
	inst._reisen_molt_hint_spoken = true
	reisen_say_hidden_hint(inst, key, 0)
end

-- ── Vulnerability / absorb ──────────────────────────────────────────────

local function compute_reisen_vulnerable_raw(inst)
	local v = inst.vulnerable or 0
	-- Hunger-based dynamic vulnerability removed.
	-- Starvation (hunger <= 0) now applies SetInducedInsanity (purpleamulet effect)
	-- via reisen_sync_starving_insanity instead of stacking absorb penalties here.
	--[[
	if inst.components.hunger ~= nil then
		local h = inst.components.hunger.current
		local hmax = inst.components.hunger.max
		if h < ReisenConsts.HUNGER_MID * hmax then
			v = v - 0.25
		end
		if h < ReisenConsts.HUNGER_LOW * hmax then
			v = v - 0.50
		end
		if h <= 0 then
			v = v - 0.75
		end
	end
	--]]
	return v
end

local function reisen_update_vuln_hint_sanity(inst)
	if inst == nil or inst.prefab ~= "reisen" then return end
	local vuln_raw = inst.vulnerable or 0
	local vuln_active = vuln_raw < 0
	if vuln_active == inst._reisen_vuln_hint_active then return end
	inst._reisen_vuln_hint_active = vuln_active
	if vuln_active then
		reisen_say_hidden_hint(inst, "ANNOUNCE_REISEN_VULNERABLE", 20)
	end
end

local function reisen_update_vuln_hint_hunger(inst)
	if inst == nil or inst.prefab ~= "reisen" then return end
	local hunger = inst.components.hunger
	local hunger_zero = hunger ~= nil and hunger.current <= 0
	if hunger_zero == inst._reisen_hunger_zero_hint_active then return end
	inst._reisen_hunger_zero_hint_active = hunger_zero
	if hunger_zero then
		reisen_say_hidden_hint(inst, "ANNOUNCE_REISEN_STARVING", 20)
	end
end

-- ── Sanity stage speech hints ───────────────────────────────────────────

-- Returns 1–5 (1 = san=0, 5 = san>75).
-- Stage boundaries mirror the thresholds in reisen_sanitydots.lua.
local function reisen_get_sanity_stage(inst)
	if inst == nil or inst.components.sanity == nil then
		return 5
	end
	local s = get_effective_sanity(inst)
	if s > 75 then
		return 5
	elseif s > 50 then
		return 4
	elseif s > 25 then
		return 3
	elseif s > 0 then
		return 2
	end
	return 1
end

local function reisen_sync_sanity_stage_net(inst, stage)
	if inst._reisen_sanity_stage_net ~= nil then
		inst._reisen_sanity_stage_net:set(stage)
	end
end

local function reisen_update_sanity_stage_hint(inst)
	if inst == nil or inst.prefab ~= "reisen" then
		return
	end
	local stage = reisen_get_sanity_stage(inst)
	if not inst._reisen_stage_hint_initialized then
		inst._reisen_stage_hint_initialized = true
		inst._reisen_last_sanity_stage = stage
		reisen_sync_sanity_stage_net(inst, stage)
		return
	end
	local prev_stage = inst._reisen_last_sanity_stage
	if prev_stage == stage then
		return
	end
	inst._reisen_last_sanity_stage = stage
	reisen_sync_sanity_stage_net(inst, stage)
	if stage == 1 and prev_stage ~= 1 then
		reisen_say_hidden_hint(inst, "ANNOUNCE_REISEN_STAGE_1", 8)
	end
end

local function compute_reisen_vulnerable_hunger_penalty(inst)
	return compute_reisen_vulnerable_raw(inst)
end

-- When hunger reaches 0 apply induced insanity (equivalent to wearing purpleamulet):
-- the game treats the player as insane regardless of their actual sanity value,
-- causing shadow creatures to spawn.  Cleared as soon as hunger rises above 0
-- or the player becomes a ghost.
local function reisen_sync_starving_insanity(inst)
	if inst == nil then return end
	local sanity = inst.components.sanity
	if sanity == nil then return end
	local hunger = inst.components.hunger
	local starving = not inst:HasTag("playerghost")
		and hunger ~= nil
		and hunger.current <= 0
	if inst._reisen_starving_cache == starving then return end
	inst._reisen_starving_cache = starving
	sanity:SetInducedInsanity("reisen_starving", starving or nil)
end

local function sync_reisen_vuln_absorb_modifier(inst)
	if inst.prefab ~= "reisen" or inst.components.health == nil or inst.components.health.externalabsorbmodifiers == nil then
		return
	end
	local v_raw = compute_reisen_vulnerable_raw(inst)
	local _ls   = inst._reisen_lunatic_stack or 0
	local _boost = inst._reisen_lunatic_boosted == true

	-- v_raw now changes only when inst.vulnerable changes (sanity tier transition).
	-- Hunger thresholds no longer affect v_raw; starvation is handled separately
	-- via SetInducedInsanity.  Skip C++ SetModifier / RemoveModifier when unchanged.
	if inst._reisen_vuln_cache_vraw   == v_raw
	and inst._reisen_vuln_cache_ls    == _ls
	and inst._reisen_vuln_cache_boost == _boost then
		return
	end
	inst._reisen_vuln_cache_vraw  = v_raw
	inst._reisen_vuln_cache_ls    = _ls
	inst._reisen_vuln_cache_boost = _boost

	local ext = inst.components.health.externalabsorbmodifiers
	if v_raw == 0 then
		ext:RemoveModifier(REISEN_VULN_ABSORB_SOURCE, "main")
	else
		ext:SetModifier(REISEN_VULN_ABSORB_SOURCE, v_raw, "main")
	end

	-- stack > MID_THRESH: offset the vuln penalty up to a cap (total still ≤ 0).
	local budget = math.max(0, -v_raw)
	if _ls > REISEN_LUNATIC_STACK_MID_THRESH then
		local relief_cap = _boost and REISEN_LUNATIC_VULN_RELIEF_CAP_BOOSTED or REISEN_LUNATIC_VULN_RELIEF_CAP_NORMAL
		local lunatic_relief = math.min(relief_cap, budget)
		if lunatic_relief > 0 then
			ext:SetModifier(REISEN_LUNATIC_VULN_SOURCE, lunatic_relief, "lunatic")
		else
			ext:RemoveModifier(REISEN_LUNATIC_VULN_SOURCE, "lunatic")
		end
	else
		ext:RemoveModifier(REISEN_LUNATIC_VULN_SOURCE, "lunatic")
	end
end

-- Sync kill-accum pool to clients (HUD badge).
local function reisen_sync_kill_hp_accum_net(inst)
	if not (TheWorld ~= nil and TheWorld.ismastersim) then return end
	if inst._reisen_kill_hp_accum_net ~= nil then
		local v = inst._reisen_kill_hp_accum or 0
		if v > 255 then v = 255 end
		if inst._reisen_kill_hp_accum_net_last_value ~= v then
			inst._reisen_kill_hp_accum_net:set(v)
			inst._reisen_kill_hp_accum_net_last_value = v
			ReisenPerf.Bump("reisen.kill_hp_accum_net.set")
		end
	end
end

-- ── Ghost / human transitions ───────────────────────────────────────────

local function onbecamehuman(inst)
	inst.components.locomotor:SetExternalSpeedMultiplier(inst, "reisen_speed_mod", 1)
	inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, "reisen_ghost_speed")
	reisen_sync_starving_insanity(inst)
	lunatic(inst)
end

local function onbecameghost(inst)
	inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, "reisen_speed_mod")
	inst.components.locomotor:SetExternalSpeedMultiplier(inst, "reisen_ghost_speed", 1.5)
	if inst._reisen_dodge_task ~= nil then
		inst._reisen_dodge_task:Cancel()
		inst._reisen_dodge_task = nil
	end
	inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, REISEN_DODGE_SPEED_KEY)
	inst:RemoveTag("reisen_dodging")
	if inst._reisen_lunatic_decay_task ~= nil then
		inst._reisen_lunatic_decay_task:Cancel()
		inst._reisen_lunatic_decay_task = nil
	end
	inst._reisen_lunatic_stack = 0
	inst._reisen_lunatic_boosted = false
	inst._reisen_boosted_meat_trigger_count = 0
	inst._reisen_boost_move_mult = nil
	if inst._reisen_lunatic_net ~= nil then
		inst._reisen_lunatic_net:set(0)
	end
	inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, REISEN_LUNATIC_SPEED_KEY)
	inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, REISEN_BOOST_SPEED_KEY)
	if inst.components.health ~= nil and inst.components.health.externalabsorbmodifiers ~= nil then
		local ext = inst.components.health.externalabsorbmodifiers
		ext:RemoveModifier(REISEN_VULN_ABSORB_SOURCE, "main")
		ext:RemoveModifier(REISEN_LUNATIC_VULN_SOURCE, "lunatic")
	end
	inst._reisen_uniform_worn = false
	inst._reisen_uniform_saved_night_drain = nil
	inst._reisen_uniform_hunger_applied = nil
	inst._reisen_charm_worn = false
	inst._reisen_charm_snap = nil
	inst._reisen_kill_hp_accum = 0
	reisen_sync_kill_hp_accum_net(inst)
	inst._reisen_crit_enter_time = nil
	reisen_sync_starving_insanity(inst)
	-- Clear lunatic() caches so respawn properly reinitializes light and other tier effects.
	inst._reisen_cached_tier_idx   = nil
	inst._reisen_cached_light_on   = nil
	inst._reisen_cached_zero_san   = nil
	inst._reisen_cached_weapon_dur = nil
	inst._reisen_cached_high_san   = nil
	if inst.Light ~= nil then
		inst.Light:Enable(false)
	end
end

local function onsave(inst, data)
	data.molt_qualified_days = inst._reisen_molt_qualified_days or 0
	data.molt_last_cycle     = inst._reisen_molt_last_cycle
end

local function onload(inst, data)
	if data ~= nil then
		inst._reisen_molt_qualified_days = data.molt_qualified_days or 0
		inst._reisen_molt_last_cycle     = data.molt_last_cycle
	end

	inst:ListenForEvent("ms_respawnedfromghost", onbecamehuman)
	inst:ListenForEvent("ms_becameghost", onbecameghost)

	if inst:HasTag("playerghost") then
		onbecameghost(inst)
	else
		onbecamehuman(inst)
	end

	inst:DoTaskInTime(0, function(i)
		lunatic(i)
		reisen_sync_kill_hp_accum_net(i)
	end)
end

-- ── lunatic() — sanity tier application ────────────────────────────────
--  Called on sanity/hunger/day-phase changes. Finds the current tier from
--  REISEN_SANITY_TIERS and applies all stats; then overlays uniform/charm
--  modifiers and lunatic stack bonuses.

lunatic = function(inst)
	ReisenPerf.Bump("reisen.lunatic.calls")
	local _t_done = ReisenPerf.Begin("reisen.lunatic")
	local san = get_effective_sanity(inst)

	-- Find matching sanity tier (first entry where san > san_min).
	local tier = nil
	local tier_idx = 0
	for i, t in ipairs(REISEN_SANITY_TIERS) do
		if san > t.san_min then
			tier = t
			tier_idx = i
			break
		end
	end
	if tier == nil then
		tier = REISEN_SANITY_TIER_ZERO
		tier_idx = -1
	end

	-- Apply tier base stats (always needed as they may be modified by stack/boost below).
	inst.components.combat.damagemultiplier = tier.dmg
	inst.vulnerable                         = tier.vuln
	inst.components.locomotor.walkspeed     = tier.walk   * TUNING.WILSON_WALK_SPEED
	inst.components.locomotor.runspeed      = tier.run    * TUNING.WILSON_RUN_SPEED
	inst.components.sanity.neg_aura_mult    = tier.neg_aura
	inst.components.sanity.night_drain_mult = tier.night_drain
	inst.components.hunger.hungerrate       = tier.hunger * TUNING.WILSON_HUNGER_RATE
	inst.components.sanity.dapperness       = tier.dapper * TUNING.DAPPERNESS_MED

	-- Apply tier light (only when tier changes or light state changes).
	local want_light_on = tier.light ~= nil
		and (TheWorld:HasTag("cave") or TheWorld.state.phase == "night")
	if tier_idx ~= inst._reisen_cached_tier_idx then
		inst._reisen_cached_tier_idx = tier_idx
		if tier.light ~= nil then
			inst.entity:AddLight()
			inst.Light:SetRadius(tier.light.r)
			inst.Light:SetFalloff(tier.light.fo)
			inst.Light:SetIntensity(tier.light.it)
			inst.Light:SetColour(REISEN_LIGHT_R, REISEN_LIGHT_G, REISEN_LIGHT_B)
		end
	end
	if want_light_on ~= inst._reisen_cached_light_on then
		inst._reisen_cached_light_on = want_light_on
		if inst.Light ~= nil then
			inst.Light:Enable(want_light_on)
		end
	end

	local _ls = inst._reisen_lunatic_stack or 0

	-- Zero-san bonus: extra hunger drain when well-fed AND lunatic stack > 0.
	if tier == REISEN_SANITY_TIER_ZERO and _ls > 0 then
		if inst.components.hunger.current > tier.hunger_high_thresh * inst.components.hunger.max then
			inst.components.hunger.hungerrate = inst.components.hunger.hungerrate * tier.hunger_high_extra_mult
		end
	end

	-- Charm: overrides all sanity effects when active (suppressed if hunger == 0).
	if inst._reisen_charm_worn then
		local hunger_suppressed = inst.components.hunger ~= nil and inst.components.hunger.current <= 0
		if not hunger_suppressed then
			inst.components.sanity.neg_aura_mult = 0
			inst.components.sanity.night_drain_mult = 0
			inst.components.sanity.dapperness = 0
			inst.components.sanity.dapperness_mult = 0
			inst.components.sanity:SetNegativeAuraImmunity(true)
			inst.components.sanity:SetLightDrainImmune(true)
		else
			inst.components.sanity:SetNegativeAuraImmunity(false)
			inst.components.sanity:SetLightDrainImmune(false)
			inst.components.sanity.dapperness_mult = 1
		end
	else
		inst.components.sanity:SetNegativeAuraImmunity(false)
		inst.components.sanity:SetLightDrainImmune(false)
		inst.components.sanity.dapperness_mult = 1
	end

	-- Lunatic stack bonuses (applied last, stack onto the tier values above).
	if _ls > REISEN_LUNATIC_STACK_HI_THRESH then
		if inst.components.combat ~= nil then
			inst.components.combat.damagemultiplier = inst.components.combat.damagemultiplier * REISEN_LUNATIC_DAMAGE_MULT_HI
		end
		if inst.components.hunger ~= nil then
			inst.components.hunger.hungerrate = inst.components.hunger.hungerrate * REISEN_LUNATIC_HUNGER_MULT_HI
		end
	end
	if inst._reisen_lunatic_boosted and inst.components.hunger ~= nil then
		inst.components.hunger.hungerrate = inst.components.hunger.hungerrate * REISEN_BOOSTED_HUNGER_MULT
	end

	-- Zero-san: reduced work progress and tool durability (cached).
	local is_zero_san = (tier == REISEN_SANITY_TIER_ZERO)
	if is_zero_san ~= inst._reisen_cached_zero_san then
		inst._reisen_cached_zero_san = is_zero_san
		if is_zero_san then
			inst.components.workmultiplier:AddMultiplier(ACTIONS.CHOP,   REISEN_ZERO_SAN_WORK_MULT,      inst)
			inst.components.workmultiplier:AddMultiplier(ACTIONS.MINE,   REISEN_ZERO_SAN_WORK_MULT,      inst)
			inst.components.workmultiplier:AddMultiplier(ACTIONS.HAMMER, REISEN_ZERO_SAN_WORK_MULT,      inst)
			inst.components.efficientuser:AddMultiplier(ACTIONS.CHOP,   REISEN_ZERO_SAN_DURABILITY_MULT, inst)
			inst.components.efficientuser:AddMultiplier(ACTIONS.MINE,   REISEN_ZERO_SAN_DURABILITY_MULT, inst)
			inst.components.efficientuser:AddMultiplier(ACTIONS.HAMMER, REISEN_ZERO_SAN_DURABILITY_MULT, inst)
		else
			inst.components.workmultiplier:RemoveMultiplier(ACTIONS.CHOP,   inst)
			inst.components.workmultiplier:RemoveMultiplier(ACTIONS.MINE,   inst)
			inst.components.workmultiplier:RemoveMultiplier(ACTIONS.HAMMER, inst)
			inst.components.efficientuser:RemoveMultiplier(ACTIONS.CHOP,   inst)
			inst.components.efficientuser:RemoveMultiplier(ACTIONS.MINE,   inst)
			inst.components.efficientuser:RemoveMultiplier(ACTIONS.HAMMER, inst)
		end
	end

	-- Lunatic weapon durability (cached).
	local want_weapon_dur = _ls > REISEN_LUNATIC_STACK_LOW_THRESH
	if want_weapon_dur ~= inst._reisen_cached_weapon_dur then
		inst._reisen_cached_weapon_dur = want_weapon_dur
		if want_weapon_dur then
			inst.components.efficientuser:AddMultiplier(
				ACTIONS.ATTACK, REISEN_LUNATIC_WEAPON_DURABILITY_MULT, REISEN_LUNATIC_WEAPON_DUR_SOURCE)
		else
			inst.components.efficientuser:RemoveMultiplier(ACTIONS.ATTACK, REISEN_LUNATIC_WEAPON_DUR_SOURCE)
		end
	end

	-- High-san: fast PICK/HARVEST/BUILD and rowing bonuses (cached).
	local is_high_san = san > 99
	if is_high_san ~= inst._reisen_cached_high_san then
		inst._reisen_cached_high_san = is_high_san
		if is_high_san then
			inst:AddTag("quagmire_fasthands")
			inst:AddTag("fastbuilder")
			inst.components.expertsailor:SetRowForceMultiplier(REISEN_HIGH_SAN_ROW_FORCE_MULT)
			inst.components.expertsailor:SetRowExtraMaxVelocity(REISEN_HIGH_SAN_ROW_EXTRA_MAX_VELOCITY)
		else
			inst:RemoveTag("quagmire_fasthands")
			inst:RemoveTag("fastbuilder")
			inst.components.expertsailor:SetRowForceMultiplier(nil)
			inst.components.expertsailor:SetRowExtraMaxVelocity(nil)
		end
	end

	sync_reisen_vuln_absorb_modifier(inst)
	reisen_update_sanity_stage_hint(inst)
	_t_done()
end

-- ── Deferred lunatic() ───────────────────────────────────────────────────
--  Coalesces multiple lunatic() triggers (sanitydelta, hungerdelta, etc.)
--  and throttles to at most one call per LUNATIC_DEFERRED_INTERVAL seconds.
--
--  Why a named callback instead of an inline closure:
--  hungerdelta fires every server tick (30 Hz). An inline "function(i)…end"
--  would allocate a new closure object on every call, creating ~30 short-lived
--  Lua objects per second.  Those accumulate until GC runs, causing the
--  intermittent brief stutters seen in non-combat idle state.
--  A named local function is allocated once at module load; DoTaskInTime
--  receives the same function pointer every call with zero extra allocation.
local LUNATIC_DEFERRED_INTERVAL = 0.25  -- max 4 lunatic() calls/s from continuous events

local function _lunatic_deferred_cb(i)
	i._reisen_lunatic_pending = false
	i._reisen_lunatic_last_deferred = GetTime()
	if i:IsValid() and not i:HasTag("playerghost") then
		lunatic(i)
	end
end

local function lunatic_deferred(inst)
	if inst._reisen_lunatic_pending then return end
	local now = GetTime()
	local delay = math.max(0, (inst._reisen_lunatic_last_deferred or 0) + LUNATIC_DEFERRED_INTERVAL - now)
	inst._reisen_lunatic_pending = true
	inst:DoTaskInTime(delay, _lunatic_deferred_cb)
end

-- ── Lunatic stack: decay timing ─────────────────────────────────────────

local function reisen_decay_delay(inst, stack)
	local base
	if inst._reisen_lunatic_boosted then
		if stack > REISEN_LUNATIC_STACK_HI_THRESH then base = REISEN_LUNATIC_DECAY_BOOST_MAX
		elseif stack > 1                           then base = REISEN_LUNATIC_DECAY_BOOST_HI
		else                                            base = REISEN_LUNATIC_DECAY_BOOST end
	else
		if stack > REISEN_LUNATIC_STACK_HI_THRESH then base = REISEN_LUNATIC_DECAY_TIME_MAX
		elseif stack > 1                           then base = REISEN_LUNATIC_DECAY_TIME_HI
		else                                            base = REISEN_LUNATIC_DECAY_TIME end
	end
	if inst._reisen_petal_buff then
		base = base + (inst._reisen_lunatic_boosted and REISEN_PETAL_BUFF_TIME_BOOST or REISEN_PETAL_BUFF_TIME)
	end
	return base
end

local reisen_lunatic_decay  -- forward declaration; assigned below after reisen_update_lunatic_state

-- ── Vulnerability / hunger chain on attack ──────────────────────────────

local function reisen_vuln_hunger_on_attacked(inst, data)
	if data == nil or data.attacker == nil or not data.attacker:IsValid() then
		return
	end
	local vulnerable = compute_reisen_vulnerable_hunger_penalty(inst)
	inst.components.hunger:DoDelta(inst.components.hunger.max * 0.02 * vulnerable, false, "reisen_vuln")
	if vulnerable < 0 then
		reisen_say_hidden_hint(inst, "ANNOUNCE_REISEN_VULN_CHAIN", 12)
	end
end

-- ── Lunatic stack: hit reaction (dodge burst) ────────────────────────────

--[[
local function reisen_lunatic_panic_on_attacked(inst, data)
	if not (TheWorld ~= nil and TheWorld.ismastersim) then return end
	if inst:HasTag("playerghost") then return end
	local _ls = inst._reisen_lunatic_stack or 0
	if _ls <= REISEN_LUNATIC_STACK_LOW_THRESH then return end
	if math.random() >= REISEN_LUNATIC_PANIC_ON_HIT_CHANCE then return end
	if data == nil or data.attacker == nil or not data.attacker:IsValid() then return end
	local attacker = data.attacker
	if attacker == inst then return end
	if attacker.components.health ~= nil and attacker.components.health:IsDead() then return end

	if attacker.components.hauntable ~= nil then
		attacker.components.hauntable:Panic(REISEN_LUNATIC_PANIC_ON_HIT_DURATION)
		return
	end
	if attacker.components.sanity ~= nil then
		attacker.components.sanity:DoDelta(REISEN_LUNATIC_PANIC_PLAYER_SANITY_DELTA)
	end
	if attacker.components.locomotor ~= nil then
		attacker.components.locomotor:SetExternalSpeedMultiplier(
			attacker, REISEN_PANIC_ATTACKER_SPEED_KEY, REISEN_LUNATIC_PANIC_PLAYER_SPEED_MULT)
		if attacker._reisen_panic_hit_slow_task ~= nil then
			attacker._reisen_panic_hit_slow_task:Cancel()
		end
		attacker._reisen_panic_hit_slow_task = attacker:DoTaskInTime(REISEN_LUNATIC_PANIC_ON_HIT_DURATION, function(a)
			a._reisen_panic_hit_slow_task = nil
			if a:IsValid() and a.components.locomotor ~= nil then
				a.components.locomotor:RemoveExternalSpeedMultiplier(a, REISEN_PANIC_ATTACKER_SPEED_KEY)
			end
		end)
	end
end
]]

local function reisen_on_attacked(inst, data)
	ReisenPerf.Bump("event.attacked")
	reisen_vuln_hunger_on_attacked(inst, data)
	-- reisen_lunatic_panic_on_attacked(inst, data)
	-- Petal buff cancellation: clear the bonus and fire decay immediately (-1 stack).
	if inst._reisen_petal_buff then
		inst._reisen_petal_buff = false
		if inst._reisen_petal_fx ~= nil then
			if inst._reisen_petal_fx:IsValid() and inst._reisen_petal_fx.kill_fx ~= nil then
				inst._reisen_petal_fx:kill_fx()
			end
			inst._reisen_petal_fx = nil
		end
		if inst._reisen_lunatic_decay_task ~= nil then
			inst._reisen_lunatic_decay_task:Cancel()
			inst._reisen_lunatic_decay_task = nil
		end
		inst._reisen_lunatic_decay_task = inst:DoTaskInTime(0, reisen_lunatic_decay)
	end

	-- Dodge burst on hit.
	if inst.components.locomotor == nil then return end
	if (inst._reisen_lunatic_stack or 0) <= REISEN_LUNATIC_STACK_LOW_THRESH then return end
	if GetTime() < (inst._reisen_dodge_cd_end or 0) then
		inst._reisen_dodge_cd_end = GetTime() + REISEN_DODGE_COOLDOWN
		return
	end
	inst._reisen_dodge_cd_end = GetTime() + REISEN_DODGE_COOLDOWN
	inst.components.locomotor:SetExternalSpeedMultiplier(inst, REISEN_DODGE_SPEED_KEY, REISEN_DODGE_SPEED_MULT)
	-- "reisen_dodging" entity tag: read by the SGwilson AddStategraphPostInit hook in modmain
	-- to suppress GoToState("hit") during the dodge window.
	inst:AddTag("reisen_dodging")
	if inst._reisen_dodge_task ~= nil then
		inst._reisen_dodge_task:Cancel()
	end
	inst._reisen_dodge_task = inst:DoTaskInTime(REISEN_DODGE_SPEED_DURATION, function(i)
		inst._reisen_dodge_task = nil
		if i:IsValid() then
			if i.components.locomotor ~= nil then
				i.components.locomotor:RemoveExternalSpeedMultiplier(i, REISEN_DODGE_SPEED_KEY)
			end
			i:RemoveTag("reisen_dodging")
		end
	end)
end

-- ── Kill HP accumulation ────────────────────────────────────────────────
-- Applies the pending kill-accumulated HP heal and resets the accumulator.
-- Called when lunatic stack reaches 0 (natural decay or carrot reset).
-- Both call sites clear _reisen_lunatic_boosted before calling this, so the
-- boosted heal bonus in reisen_on_healthdelta will not apply to this heal.
local function reisen_apply_kill_hp_accum(inst)
	local accum = inst._reisen_kill_hp_accum or 0
	inst._reisen_kill_hp_accum = 0
	reisen_sync_kill_hp_accum_net(inst)
	if accum > 0 then
		local damage_mult = (inst.components.combat ~= nil
			and inst.components.combat.damagemultiplier) or 1
		damage_mult = math.max(damage_mult, 0.01)
		local heal = accum * ReisenConsts.RELEASE_HEAL_BOOSTED_SELF_MULT
		if inst.components.health ~= nil then
			inst.components.health:DoDelta(heal, true)
		end
		if inst.components.talker ~= nil then
			inst.components.talker:Say("+" .. tostring(math.floor(heal)) .. " HP", 2.5)
		end
	end
end

-- ── Boost state exit: unified path for stack-zero settlement ────────────
-- Called whenever boost stack reaches 0, regardless of cause (natural decay,
-- carrot eat, etc.).  Clears boost flags and settles accumulated HP if the
-- player was boosted.
local function reisen_exit_boost_state(inst, was_boosted)
	inst._reisen_lunatic_boosted = false
	inst._reisen_boosted_meat_trigger_count = 0
	inst._reisen_petal_buff = false
	if inst._reisen_petal_fx ~= nil then
		if inst._reisen_petal_fx:IsValid() and inst._reisen_petal_fx.kill_fx ~= nil then
			inst._reisen_petal_fx:kill_fx()
		end
		inst._reisen_petal_fx = nil
	end
	inst._reisen_boost_move_mult = nil
	-- boostfx handles crit visual; kill_fx removes the whole effect
	if inst._reisen_boost_aura_fx ~= nil then
		if inst._reisen_boost_aura_fx:IsValid() and inst._reisen_boost_aura_fx.kill_fx ~= nil then
			inst._reisen_boost_aura_fx:kill_fx()
		end
		inst._reisen_boost_aura_fx = nil
	end
	if was_boosted then
		reisen_apply_kill_hp_accum(inst)
	end
end

-- ── Lunatic stack: state update & decay ────────────────────────────────

local function reisen_update_lunatic_state(inst)
	ReisenPerf.Bump("reisen.update_lunatic_state.calls")
	local stack = inst._reisen_lunatic_stack or 0
	local boosted = inst._reisen_lunatic_boosted == true

	if inst._reisen_lunatic_net ~= nil
		and (inst._reisen_lunatic_net_last_value ~= stack) then
		inst._reisen_lunatic_net:set(stack)
		inst._reisen_lunatic_net_last_value = stack
		ReisenPerf.Bump("reisen.lunatic_net.set")
	end
	if inst._reisen_lunatic_boosted_net ~= nil
		and (inst._reisen_lunatic_boosted_net_last_value ~= boosted) then
		inst._reisen_lunatic_boosted_net:set(boosted)
		inst._reisen_lunatic_boosted_net_last_value = boosted
		ReisenPerf.Bump("reisen.lunatic_boosted_net.set")
	end

	if inst.components.locomotor ~= nil then
		if stack > 0 then
			inst.components.locomotor:SetExternalSpeedMultiplier(inst, REISEN_LUNATIC_SPEED_KEY, REISEN_LUNATIC_MOVE_SPEED_MULT)
		else
			inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, REISEN_LUNATIC_SPEED_KEY)
		end
		if inst._reisen_lunatic_boosted and stack > 0 then
			local bm = inst._reisen_boost_move_mult or REISEN_BOOST_MOVE_MULT_START
			inst.components.locomotor:SetExternalSpeedMultiplier(inst, REISEN_BOOST_SPEED_KEY, bm)
		else
			inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, REISEN_BOOST_SPEED_KEY)
		end
	end

	if TheWorld ~= nil and TheWorld.ismastersim then
		-- Track max zone entry/exit for the crit ramp timer.
		-- Crit visual is integrated into boostfx via start_crit_ramp/stop_crit_ramp.
		local in_max_zone = inst._reisen_lunatic_boosted == true
			and (inst._reisen_lunatic_stack or 0) > REISEN_LUNATIC_STACK_HI_THRESH
		if in_max_zone and inst._reisen_crit_enter_time == nil then
			inst._reisen_crit_enter_time = GetTime()
			-- Start crit ramp on boostfx
			if inst._reisen_boost_aura_fx ~= nil
				and inst._reisen_boost_aura_fx:IsValid()
				and inst._reisen_boost_aura_fx.start_crit_ramp ~= nil then
				inst._reisen_boost_aura_fx:start_crit_ramp(
					REISEN_BOOSTED_CRIT_RAMP_DELAY,
					REISEN_BOOSTED_CRIT_MAX_TIME)
			end
		elseif not in_max_zone and inst._reisen_crit_enter_time ~= nil then
			inst._reisen_crit_enter_time = nil
			-- Stop crit ramp on boostfx
			if inst._reisen_boost_aura_fx ~= nil
				and inst._reisen_boost_aura_fx:IsValid()
				and inst._reisen_boost_aura_fx.stop_crit_ramp ~= nil then
				inst._reisen_boost_aura_fx:stop_crit_ramp()
			end
		end
		lunatic(inst)
	end
end

-- ── reisen_zero_lunatic_stack ───────────────────────────────────────────
--  Unified exit helper: captures boost flag, cancels any pending decay task,
--  zeroes the stack, then runs the full exit + state-update sequence.
--  Used by decay, carrot-eating, starvation, and Mode-B Slow Field release.
local function reisen_zero_lunatic_stack(inst)
	local was_boosted = inst._reisen_lunatic_boosted
	if inst._reisen_lunatic_decay_task ~= nil then
		inst._reisen_lunatic_decay_task:Cancel()
		inst._reisen_lunatic_decay_task = nil
	end
	inst._reisen_lunatic_stack = 0
	reisen_exit_boost_state(inst, was_boosted)
	reisen_update_lunatic_state(inst)
end

reisen_lunatic_decay = function(inst)
	inst._reisen_lunatic_decay_task = nil
	local stack = inst._reisen_lunatic_stack or 0
	if stack > 0 then
		-- Full moon + boost: stack does not decay (reschedule until moon ends).
		if TheWorld ~= nil and TheWorld.state.isfullmoon and inst._reisen_lunatic_boosted then
			local delay = reisen_decay_delay(inst, stack)
			inst._reisen_lunatic_decay_task = inst:DoTaskInTime(delay, reisen_lunatic_decay)
			return
		end
		inst._reisen_lunatic_stack = stack - 1
		if inst._reisen_lunatic_stack == 0 then
			reisen_zero_lunatic_stack(inst)
		else
			if inst._reisen_lunatic_boosted then
				inst._reisen_boost_move_mult = math.max(
					REISEN_BOOST_MOVE_MULT_MIN,
					(inst._reisen_boost_move_mult or REISEN_BOOST_MOVE_MULT_START) - REISEN_BOOST_MOVE_MULT_STEP
				)
			end
			reisen_update_lunatic_state(inst)
			local delay = reisen_decay_delay(inst, inst._reisen_lunatic_stack)
			inst._reisen_lunatic_decay_task = inst:DoTaskInTime(delay, reisen_lunatic_decay)
		end
	end
end

-- Throttle interval for onhitother stack gain (prevents high-frequency RPC abuse).
local REISEN_HIT_THROTTLE_INTERVAL = 0.1  -- seconds between stack gains

local function reisen_on_hit_other(inst, data)
	ReisenPerf.Bump("event.onhitother")
	if not TheWorld.ismastersim then return end
	-- MODE B (Slow Field) AoE hits must not grant stack; MODE A hits do grant
	-- stack via the normal onhitother path so the decay task is properly reset.
	if inst._reisen_no_stack_aoe then return end
	-- PvP: hitting another player must not feed the lunatic stack pool.
	-- This both prevents PvP snowballing (one cast → free stacks → more casts)
	-- and is robust against future code paths that may damage players directly.
	if data ~= nil and data.target ~= nil
		and (data.target:HasTag("player") or data.target:HasTag("playerghost")) then
		return
	end
	if inst.components.hunger ~= nil and inst.components.hunger.current <= 0 then return end

	-- Throttle: ignore hits that arrive faster than REISEN_HIT_THROTTLE_INTERVAL.
	-- This prevents high-frequency RPC spam (e.g. from ActionQueue or high-latency
	-- clients) from overwhelming the server with stack updates.
	local now = GetTime()
	if inst._reisen_last_hit_time ~= nil
		and now - inst._reisen_last_hit_time < REISEN_HIT_THROTTLE_INTERVAL then
		return
	end
	inst._reisen_last_hit_time = now

	local prev_stack = inst._reisen_lunatic_stack or 0
	local gain = 1
	-- Dualgear bonus: hitting shadowcreature / nightmarecreature grants +1 extra stack.
	if REISEN_DUALGEAR_SHADOW_HIT_BONUS > 0
		and data ~= nil and data.target ~= nil and data.target:IsValid()
		and (data.target:HasTag("shadowcreature") or data.target:HasTag("nightmarecreature"))
		and inst.components.inventory ~= nil then
		local body = inst.components.inventory:GetEquippedItem(EQUIPSLOTS.BODY)
		local head = inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HEAD)
		if body ~= nil and head ~= nil
			and body.prefab == REISEN_UNIFORM_PREFAB
			and head.prefab == REISEN_CHARM_PREFAB then
			gain = gain + REISEN_DUALGEAR_SHADOW_HIT_BONUS
		end
	end
	inst._reisen_lunatic_stack = math.min(prev_stack + gain, REISEN_LUNATIC_MAX)
	if inst._reisen_lunatic_boosted and inst._reisen_lunatic_stack > prev_stack then
		inst._reisen_boost_move_mult = math.min(
			REISEN_BOOST_MOVE_MULT_MAX,
			(inst._reisen_boost_move_mult or REISEN_BOOST_MOVE_MULT_START) + REISEN_BOOST_MOVE_MULT_STEP
		)
	end

	if inst._reisen_lunatic_decay_task ~= nil then
		inst._reisen_lunatic_decay_task:Cancel()
		inst._reisen_lunatic_decay_task = nil
	end
	inst._reisen_lunatic_decay_task = inst:DoTaskInTime(
		reisen_decay_delay(inst, inst._reisen_lunatic_stack), reisen_lunatic_decay)

	reisen_update_lunatic_state(inst)
end

-- ── Evil Petals: +1 lunatic stack on eat ─────────────────────────────────────
--  Eating petals_evil / petals_evil_dried / hermitcrabtea_petals_evil grants +1
--  lunatic_stack (same path as a successful attack hit), respecting the max cap.
local function reisen_evil_petals_stack_gain(inst)
	if not (TheWorld ~= nil and TheWorld.ismastersim) then return end
	if inst.components.hunger ~= nil and inst.components.hunger.current <= 0 then return end
	local prev_stack = inst._reisen_lunatic_stack or 0
	inst._reisen_lunatic_stack = math.min(prev_stack + 1, REISEN_LUNATIC_MAX)
	if inst._reisen_lunatic_boosted and inst._reisen_lunatic_stack > prev_stack then
		inst._reisen_boost_move_mult = math.min(
			REISEN_BOOST_MOVE_MULT_MAX,
			(inst._reisen_boost_move_mult or REISEN_BOOST_MOVE_MULT_START) + REISEN_BOOST_MOVE_MULT_STEP
		)
	end
	inst._reisen_petal_buff = true   -- set before reisen_decay_delay so bonus is included
	if inst._reisen_lunatic_decay_task ~= nil then
		inst._reisen_lunatic_decay_task:Cancel()
		inst._reisen_lunatic_decay_task = nil
	end
	inst._reisen_lunatic_decay_task = inst:DoTaskInTime(
		reisen_decay_delay(inst, inst._reisen_lunatic_stack), reisen_lunatic_decay)
	reisen_update_lunatic_state(inst)
	-- Kill any leftover petal ring from a previous eat (re-eat refreshes it).
	if inst._reisen_petal_fx ~= nil then
		if inst._reisen_petal_fx:IsValid() and inst._reisen_petal_fx.kill_fx ~= nil then
			inst._reisen_petal_fx:kill_fx()
		end
		inst._reisen_petal_fx = nil
	end
	-- One-shot eat feedback burst at the player's world position.
	local px, py, pz = inst.Transform:GetWorldPosition()
	local burst = SpawnPrefab("ghostlyelixir_player_slowregen_fx")
	if burst ~= nil then
		burst.Transform:SetPosition(px, py, pz)
	end
	-- Spawn persistent ground rune; parented so it follows the player.
	local pfx = SpawnPrefab("reisen_petalring")
	if pfx ~= nil then
		pfx.entity:SetParent(inst.entity)
		pfx.Transform:SetPosition(0, 0.05, 0)
		inst._reisen_petal_fx = pfx
	end
	-- Eating evil petals adds 10 to the kill-HP accumulation pool.
	local prev_accum = inst._reisen_kill_hp_accum or 0
	inst._reisen_kill_hp_accum = math.min(prev_accum + 10, REISEN_KILL_HP_ACCUM_CAP)
	reisen_sync_kill_hp_accum_net(inst)
	-- Show accum progress above head.
	if inst.components.talker ~= nil then
		local fmt = STRINGS.REISEN_ACCUM_FMT or "ACCUM: %d/%d"
		inst.components.talker:Say(string.format(fmt, inst._reisen_kill_hp_accum, REISEN_KILL_HP_ACCUM_CAP))
	end
end

-- ── Thermo tail (manrabbit_tail) ────────────────────────────────────────

local function reisen_play_shave_sound(inst)
	if inst.SoundEmitter == nil then
		return
	end
	inst.SoundEmitter:PlaySound("dontstarve/wilson/shave_LP", "reisen_molt_shave")
	inst:DoTaskInTime(0.65, function(i)
		if i:IsValid() and i.SoundEmitter ~= nil then
			i.SoundEmitter:KillSound("reisen_molt_shave")
		end
	end)
end

local function reisen_spawn_manrabbit_tail(inst, play_shave_sound)
	if not TheWorld.ismastersim then
		return
	end
	local tail = SpawnPrefab("manrabbit_tail")
	if tail == nil then
		return
	end
	local given = inst.components.inventory ~= nil and inst.components.inventory:GiveItem(tail)
	if given then
		if play_shave_sound then
			reisen_play_shave_sound(inst)
		end
		return
	end
	if tail:IsValid() then
		local x, y, z = inst.Transform:GetWorldPosition()
		tail.Transform:SetPosition(x, y, z)
	end
	if play_shave_sound then
		reisen_play_shave_sound(inst)
	end
end

local function reisen_thermo_tail_on_healthdelta(inst, data)
	if data.cause ~= "cold" and data.cause ~= "hot" then
		return
	end
	if data.overtime ~= true or data.newpercent >= data.oldpercent then
		return
	end
	local cycle = TheWorld.state.cycles
	if inst._reisen_thermo_tail_cycle ~= nil and cycle < inst._reisen_thermo_tail_cycle then
		return
	end
	inst._reisen_thermo_tail_cycle = cycle + reisen_molt_required_days_per_tail()
	reisen_spawn_manrabbit_tail(inst, false)
	reisen_say_molt_hint_once_per_season(inst, "ANNOUNCE_REISEN_MOLT_THERMO")
end

-- ── Seasonal molt (tail growth) ─────────────────────────────────────────

local function reisen_is_molting_season()
	local s = TheWorld.state.season
	if s == "spring" or s == "autumn" then
		return true
	end
	return TheWorld.state.isspring or TheWorld.state.isautumn
end

local function reisen_molt_note_low_sanity(inst)
	if not TheWorld.ismastersim then return end
	if inst._reisen_molt_san_dipped then return end
	if get_effective_sanity(inst) <= 0 then
		inst._reisen_molt_san_dipped = true
	end
end

local function reisen_molt_note_low_hunger(inst)
	if not TheWorld.ismastersim then return end
	if inst._reisen_molt_hunger_dipped then return end
	local hunger = inst.components.hunger
	if hunger ~= nil and hunger.current < ReisenConsts.HUNGER_LOW * hunger.max then
		inst._reisen_molt_hunger_dipped = true
	end
end

local function reisen_molt_on_world_cycles(inst)
	if not TheWorld.ismastersim then
		return
	end

	-- Guard against duplicate/retroactive fires when migrating between surface and cave worlds.
	local current_cycle = TheWorld.state.cycles
	if inst._reisen_molt_last_cycle ~= nil and current_cycle <= inst._reisen_molt_last_cycle then
		return
	end
	inst._reisen_molt_last_cycle = current_cycle

	local san_dipped    = inst._reisen_molt_san_dipped
	local hunger_dipped = inst._reisen_molt_hunger_dipped
	inst._reisen_molt_san_dipped    = false
	inst._reisen_molt_hunger_dipped = false

	if not reisen_is_molting_season() then
		-- Progress is preserved across seasons; only accumulation is paused.
		return
	end

	local san_fail    = san_dipped
		or get_effective_sanity(inst) <= 0
	local hunger_fail = hunger_dipped
		or (inst.components.hunger ~= nil and inst.components.hunger.current < ReisenConsts.HUNGER_LOW * inst.components.hunger.max)

	-- Each failing condition reduces the day's gain by 0.5; both failing → 0.
	local gain = 1 - (san_fail and 0.5 or 0) - (hunger_fail and 0.5 or 0)
	if gain <= 0 then
		return
	end

	inst._reisen_molt_qualified_days = (inst._reisen_molt_qualified_days or 0) + gain
	reisen_say_molt_hint_once_per_season(inst, "ANNOUNCE_REISEN_MOLT_PROGRESS")
	local need = reisen_molt_required_days_per_tail()
	while inst._reisen_molt_qualified_days >= need do
		inst._reisen_molt_qualified_days = inst._reisen_molt_qualified_days - need
		reisen_spawn_manrabbit_tail(inst, true)
		reisen_say_molt_hint_once_per_season(inst, "ANNOUNCE_REISEN_MOLT_READY")
		need = reisen_molt_required_days_per_tail()
	end
end

-- ── Lunatic stack > MID: sanity conversion on damage ────────────────────

local function reisen_lunatic_san_conversion(inst, data)
	if (inst._reisen_lunatic_stack or 0) <= REISEN_LUNATIC_STACK_MID_THRESH then return end
	if data.newpercent >= data.oldpercent then return end
	if data.overtime then return end

	local dmg = -(data.amount or 0)
	if dmg <= 0 then return end

	if inst.components.sanity ~= nil then
		inst.components.sanity:DoDelta(-dmg * REISEN_LUNATIC_SAN_CONVERSION_FRAC)
	end
end

-- ── Health delta handler ─────────────────────────────────────────────────

local function reisen_on_healthdelta(inst, data)
	reisen_thermo_tail_on_healthdelta(inst, data)
	reisen_lunatic_san_conversion(inst, data)
	-- Boosted: healing received × (1 + REISEN_BOOSTED_HEAL_BONUS).
	-- Guard flag prevents the secondary DoDelta from re-triggering this handler.
	-- Also skip when already at full health to avoid generating a +0 healthdelta event.
	if inst._reisen_lunatic_boosted
		and not inst._reisen_boosted_heal_guard
		and data.amount ~= nil and data.amount > 0
		and inst.components.health ~= nil
		and inst.components.health.currenthealth < inst.components.health.maxhealth then
		inst._reisen_boosted_heal_guard = true
		inst.components.health:DoDelta(data.amount * REISEN_BOOSTED_HEAL_BONUS, true)
		inst._reisen_boosted_heal_guard = false
	end
end

-- ── Meat-trigger knockout ────────────────────────────────────────────────
-- Pushes the "knockedout" event so SGwilson enters the "knockout" state,
-- which plays dozy→sleep_loop for normal characters and
-- insomniac_dozy→insomniac_sleep_loop for insomniac ones (Reisen has the tag).
-- "cometo" is pushed after REISEN_MEAT_SLEEP_DURATION to wake her back up.
-- No grogginess component is required; the 30s SGwilson ontimeout is harmless
-- because our cometo fires first.
local function reisen_apply_meat_knockdown(inst)
	if inst:HasTag("playerghost") then return end
	if inst.components.health ~= nil and inst.components.health:IsDead() then return end
	inst:PushEvent("knockedout")
	inst:DoTaskInTime(REISEN_MEAT_SLEEP_DURATION, function(i)
		if i:IsValid() and i.sg ~= nil then
			i:PushEvent("cometo")
		end
	end)
end

-- ── Booster application ──────────────────────────────────────────────────

local function reisen_spawn_boost_fx(inst)
	-- If already have valid boost aura: retrigger handles animation + layer + progress
	if inst._reisen_boost_aura_fx ~= nil and inst._reisen_boost_aura_fx:IsValid() then
		if inst._reisen_boost_aura_fx.retrigger ~= nil then
			inst._reisen_boost_aura_fx:retrigger()
		end
		if inst.SoundEmitter ~= nil then
			inst.SoundEmitter:PlaySound("dontstarve/common/nightmareAddFuel")
		end
		return
	end
	-- Cleanup any invalid leftover
	inst._reisen_boost_aura_fx = nil
	-- Spawn fresh boost FX
	local fx = SpawnPrefab("reisen_boostfx")
	if fx ~= nil then
		fx.entity:SetParent(inst.entity)
		fx.Transform:SetPosition(0, 0, 0)
		inst._reisen_boost_aura_fx = fx
	end
	if inst.SoundEmitter ~= nil then
		inst.SoundEmitter:PlaySound("dontstarve/common/nightmareAddFuel")
	end
end

local function reisen_on_booster_applied(inst)
	if not (TheWorld ~= nil and TheWorld.ismastersim) then return end
	inst._reisen_boosted_meat_trigger_count = 0
	inst._reisen_lunatic_stack = REISEN_LUNATIC_MAX
	inst._reisen_lunatic_boosted = true
	inst._reisen_boost_move_mult = REISEN_BOOST_MOVE_MULT_START
	if inst._reisen_lunatic_decay_task ~= nil then
		inst._reisen_lunatic_decay_task:Cancel()
		inst._reisen_lunatic_decay_task = nil
	end
	inst._reisen_lunatic_decay_task = inst:DoTaskInTime(
		reisen_decay_delay(inst, REISEN_LUNATIC_MAX), reisen_lunatic_decay)
	-- Spawn fx BEFORE update so start_crit_ramp finds a valid _reisen_boost_aura_fx.
	reisen_spawn_boost_fx(inst)
	reisen_update_lunatic_state(inst)
end

-- ── Eat handler ──────────────────────────────────────────────────────────

-- Threshold for the "heavy monster dish" direct-boost path.
local REISEN_BOOSTER_FOOD_HEALTH_THRESH = -20
local REISEN_BOOSTER_FOOD_SANITY_THRESH = -20

local function is_heavy_monster_food(food)
	if food == nil or food.components == nil or food.components.edible == nil then
		return false
	end
	local ed = food.components.edible
	return ed.foodtype == FOODTYPE.MEAT
		and (food:HasTag("monstermeat") or food:HasTag("monster"))
		and ed.healthvalue <= REISEN_BOOSTER_FOOD_HEALTH_THRESH
		and ed.sanityvalue <= REISEN_BOOSTER_FOOD_SANITY_THRESH
end

local function oneat(inst, food)
	-- Evil petals: +1 lunatic stack per eat.
	if food ~= nil and REISEN_EVIL_PETALS_FOODS[food.prefab] then
		reisen_evil_petals_stack_gain(inst)
		return
	end

	-- Monster meat dishes (MEAT type + monster/monstermeat tag + heavy HP/sanity penalty)
	-- directly trigger boosted state, bypassing the counter.
	if TheWorld ~= nil and TheWorld.ismastersim
		and is_heavy_monster_food(food) then
		reisen_on_booster_applied(inst)
		return
	end

	-- Lighter MEAT foods with negative HP still increment the counter → boost at 4.
	if TheWorld ~= nil and TheWorld.ismastersim
		and food ~= nil and food.components ~= nil and food.components.edible ~= nil
		and not (inst._reisen_lunatic_boosted)
		and food.components.edible.foodtype == FOODTYPE.MEAT
		and food.components.edible:GetHealth(inst) < 0 then
		inst._reisen_boosted_meat_trigger_count = (inst._reisen_boosted_meat_trigger_count or 0) + 1
		if inst._reisen_boosted_meat_trigger_count >= REISEN_BOOSTED_MONSTER_MEAT_TRIGGER_LIMIT then
			-- Set boosted flag immediately to prevent race conditions during deferred task.
			inst._reisen_lunatic_boosted = true
			-- Defer knockdown and full boost application to next frame to avoid
			-- stategraph conflict with the eating action.
			inst:DoTaskInTime(0, function(i)
				if not i:IsValid() or i:HasTag("playerghost") then return end
				if i.components.health ~= nil and i.components.health:IsDead() then return end
				reisen_apply_meat_knockdown(i)
				reisen_on_booster_applied(i)
			end)
		end
		return
	end

	if not is_carrot_food(food) then
		return
	end

	reisen_zero_lunatic_stack(inst)

	local expired = carrot_streak_days_expired(inst)
	if expired > 0 then
		inst._reisen_carrot_streak = math.max(0, (inst._reisen_carrot_streak or 0) - expired)
	end
	inst._reisen_carrot_streak = math.min((inst._reisen_carrot_streak or 0) + 1, CARROT_SANITY_MAX_TIER)
	inst._reisen_carrot_cycle = TheWorld.state.cycles

	-- Eating a carrot while boosted restores 100 sanity; streak still accumulates.
	if inst._reisen_lunatic_boosted and inst.components.sanity ~= nil then
		inst.components.sanity:DoDelta(100)
		return
	end

	local tier = inst._reisen_carrot_streak
	inst.components.sanity:DoDelta(CARROT_SANITY_BY_TIER[tier])
end

-- ── common_postinit ──────────────────────────────────────────────────────

local common_postinit = function(inst)
	inst.MiniMapEntity:SetIcon("reisen.tex")
	inst:AddTag("reisen")

	-- Network variables for lunatic HUD (must exist on both server and client).
	inst._reisen_lunatic_net = net_byte(inst.GUID, "reisen_lunatic_stack", "reisen_lunatic_dirty")
	inst._reisen_lunatic_boosted_net = net_bool(inst.GUID, "reisen_lunatic_boosted", "reisen_lunatic_boosted_dirty")
	inst._reisen_kill_hp_accum_net = net_byte(inst.GUID, "reisen_kill_hp_accum", "reisen_kill_hp_accum_dirty")

	-- Sanity stage net variable (1-5, see reisen_get_sanity_stage).
	-- Server writes; reserved for future HUD / widget use.
	inst._reisen_sanity_stage_net = net_byte(inst.GUID, "reisen_sanity_stage", "reisen_sanity_stage_dirty")

	-- Stats needed by the character selection screen (runs common_postinit only).
	if inst.components.health ~= nil then
		inst.components.health:SetMaxHealth(REISEN_MAX_HEALTH)
	end
	if inst.components.hunger ~= nil then
		inst.components.hunger:SetMax(REISEN_MAX_HUNGER)
	end
	if inst.components.sanity ~= nil then
		inst.components.sanity:SetMax(REISEN_MAX_SANITY)
	end
	inst.stats = { health = REISEN_MAX_HEALTH, hunger = REISEN_MAX_HUNGER, sanity = REISEN_MAX_SANITY }
end

-- ── master_postinit ──────────────────────────────────────────────────────

local master_postinit = function(inst)
	inst.soundsname = "willow"

	-- Instance state variables.
	inst.vulnerable                       = 0.0
	inst._reisen_molt_qualified_days      = 0
	inst._reisen_molt_last_cycle          = nil
	inst._reisen_molt_san_dipped          = false
	inst._reisen_molt_hunger_dipped       = false
	inst._reisen_thermo_tail_cycle        = nil
	inst._reisen_hidden_hint_cd           = {}
	inst._reisen_vuln_hint_active         = false
	inst._reisen_hunger_mid_hint_active   = false
	inst._reisen_hunger_vuln_hint_active  = false
	inst._reisen_stage_hint_initialized   = false
	inst._reisen_last_sanity_stage        = nil
	inst._reisen_molt_hint_season         = nil
	inst._reisen_molt_hint_spoken         = false
	inst._reisen_dodge_task               = nil
	inst._reisen_dodge_cd_end             = nil
	inst._reisen_lunatic_stack            = 0
	inst._reisen_lunatic_boosted          = false
	inst._reisen_boosted_meat_trigger_count = 0
	inst._reisen_boost_aura_fx            = nil
	inst._reisen_boost_move_mult          = nil
	inst._reisen_petal_fx                 = nil
	inst._reisen_lunatic_decay_task       = nil
	inst._reisen_boosted_heal_guard       = false
	inst._reisen_kill_hp_accum            = 0
	inst._reisen_crit_enter_time          = nil
	inst._reisen_last_hit_time            = nil    -- throttle for onhitother
	inst._reisen_no_stack_aoe             = false  -- MODE B: suppress stack gain during Slow Field AoE
	inst._reisen_lunatic_pending          = false  -- deferred lunatic() coalescing
	inst._reisen_lunatic_last_deferred    = nil    -- timestamp of last deferred lunatic() call
	inst._reisen_vuln_cache_vraw          = nil    -- cached inputs for sync_reisen_vuln_absorb_modifier
	inst._reisen_vuln_cache_ls            = nil
	inst._reisen_vuln_cache_boost         = nil
	inst._reisen_cached_tier_idx          = nil    -- cached tier index for lunatic() light optimization
	inst._reisen_cached_light_on          = nil    -- cached light enabled state
	inst._reisen_cached_zero_san          = nil    -- cached zero-san work multiplier state
	inst._reisen_cached_weapon_dur        = nil    -- cached weapon durability multiplier state
	inst._reisen_cached_high_san          = nil    -- cached high-san tag/sailor state
	reisen_sync_kill_hp_accum_net(inst)

	inst.components.health:SetMaxHealth(REISEN_MAX_HEALTH)
	inst.components.hunger:SetMax(REISEN_MAX_HUNGER)
	inst.components.sanity:SetMax(REISEN_MAX_SANITY)

	inst.OnSave    = onsave
	inst.OnLoad    = onload
	inst.OnNewSpawn = onload

	inst.components.temperature.inherentinsulation = TUNING.INSULATION_PER_BEARD_BIT * REISEN_INSULATION_MULT
	inst.components.hunger.hungerrate = REISEN_BASE_HUNGER_MULT * TUNING.WILSON_HUNGER_RATE
	inst:AddTag("insomniac")
	inst.components.eater:SetOnEatFn(oneat)

	-- Work speed and tool-durability multipliers (used by lunatic()).
	-- Guard against the base-game player_common.lua having already registered
	-- workmultiplier (or efficientuser/expertsailor) to avoid a "component
	-- already exists" warning on every load.
	if inst.components.workmultiplier == nil then
		inst:AddComponent("workmultiplier")
	end
	if inst.components.efficientuser == nil then
		inst:AddComponent("efficientuser")
	end
	-- Rowing bonuses (used by lunatic(); oar.lua reads these at row time).
	if inst.components.expertsailor == nil then
		inst:AddComponent("expertsailor")
	end

	-- Boosted crit: chance ramps from 0 → REISEN_BOOSTED_CRIT_MAX_CHANCE over
	-- REISEN_BOOSTED_CRIT_MAX_TIME seconds while in boosted max zone.
	-- Curve: MAX_CHANCE × (elapsed / MAX_TIME)^RAMP_POWER  (ease-in, slow start fast end).
	-- Timer is tracked via _reisen_crit_enter_time; resets on leaving max zone.
	inst.components.combat.bonusdamagefn = function(attacker, target, damage, weapon)
		if attacker._reisen_lunatic_boosted
			and (attacker._reisen_lunatic_stack or 0) > REISEN_LUNATIC_STACK_HI_THRESH
			and attacker._reisen_crit_enter_time ~= nil then
			local t     = math.min(GetTime() - attacker._reisen_crit_enter_time, REISEN_BOOSTED_CRIT_MAX_TIME)
			local t_eff = math.max(0, t - REISEN_BOOSTED_CRIT_RAMP_DELAY)
			local chance = REISEN_BOOSTED_CRIT_MAX_CHANCE
				* (t_eff / (REISEN_BOOSTED_CRIT_MAX_TIME - REISEN_BOOSTED_CRIT_RAMP_DELAY))
				^ REISEN_BOOSTED_CRIT_RAMP_POWER
			if math.random() < chance then
				return damage
			end
		end
		return 0
	end

	-- Health regen: fixed-rate periodic task (guaranteed HP/s, immune to lunatic() call frequency).
	inst:DoPeriodicTask(REISEN_HEALTH_REGEN_PERIOD, function(i)
		if i:HasTag("playerghost") then return end
		if i.components.sanity == nil or i.components.health == nil then return end
		-- Skip entirely when already at full health to avoid firing a healthdelta event
		-- with data.amount == 0, which external mods see as spurious "+0 health" ticks.
		if i.components.health.currenthealth >= i.components.health.maxhealth then return end
		local san = get_effective_sanity(i)
		if san > 99 then
			i.components.health:DoDelta(REISEN_HIGH_SAN_REGEN_HP_PER_S * REISEN_HEALTH_REGEN_PERIOD, true)
		elseif san <= 0 and i.components.hunger ~= nil
				and (i._reisen_lunatic_stack or 0) >= REISEN_LUNATIC_STACK_LOW_THRESH then
			local hunger = i.components.hunger
			if hunger.current > REISEN_SANITY_TIER_ZERO.hunger_high_thresh * hunger.max then
				i.components.health:DoDelta(REISEN_ZERO_SAN_REGEN_HP_PER_S * REISEN_HEALTH_REGEN_PERIOD, true)
			end
		end
	end)

	inst:ListenForEvent("reisen_stats_dirty", function(i)
		lunatic(i)
	end)
	inst:ListenForEvent("sanitydelta", function(i)
		ReisenPerf.Bump("event.sanitydelta")
		local _t = ReisenPerf.BeginWarn("event.sanitydelta", 2)
		reisen_molt_note_low_sanity(i)
		lunatic_deferred(i)
		reisen_update_vuln_hint_sanity(i)
		_t()
	end)
	inst:ListenForEvent("healthdelta", function(i, data)
		ReisenPerf.Bump("event.healthdelta")
		reisen_on_healthdelta(i, data)
	end)
	inst:ListenForEvent("hungerdelta", function(i)
		ReisenPerf.Bump("event.hungerdelta")
		local _t = ReisenPerf.BeginWarn("event.hungerdelta", 2)
		reisen_molt_note_low_hunger(i)
		local hunger = i.components.hunger
		local starving = not i:HasTag("playerghost") and hunger ~= nil and hunger.current <= 0
		if i._reisen_starving_cache ~= starving then
			i._reisen_starving_cache = starving
			ReisenPerf.Bump("event.hungerdelta.insanity_change")
			local sanity = i.components.sanity
			if sanity ~= nil then
				sanity:SetInducedInsanity("reisen_starving", starving or nil)
			end
		end
		lunatic_deferred(i)
		reisen_update_vuln_hint_hunger(i)
		if starving and (i._reisen_lunatic_stack or 0) > 0 then
			reisen_zero_lunatic_stack(i)
		end
		_t()
	end)
	inst:ListenForEvent("attacked", reisen_on_attacked)
	inst:ListenForEvent("onhitother", reisen_on_hit_other)
	-- On kill (DST fires "killed" on the attacker, data.victim is the target):
	-- Accumulate HP using effective_stack = min(_ls + 1, MAX).
	-- DST fires "killed" before "onhitother", so _ls has not yet been incremented
	-- by the killing blow.  Adding 1 here compensates so the kill reward reflects
	-- the stack level the player perceives (shown on the badge after the blow).
	-- Result is capped at REISEN_KILL_HP_ACCUM_CAP.
	inst:ListenForEvent("killed", function(i, data)
		if not TheWorld.ismastersim then return end
		-- Exclude structures, walls, and non-creature entities.
		local victim = data and data.victim
		if victim == nil then return end
		if victim:HasTag("structure") or victim:HasTag("wall") or victim:HasTag("veggie") then return end
		-- PvP kills do NOT grant accum: prevents snowballing in PvP servers
		-- (downed teammate → free accum → cast Mind Blowing → repeat).
		if victim:HasTag("player") or victim:HasTag("playerghost") then return end
		local _ls = i._reisen_lunatic_stack or 0
		if _ls <= 0 then return end
		local prev_accum = i._reisen_kill_hp_accum or 0
		local effective_ls = math.min(_ls + 1, REISEN_LUNATIC_MAX)
		local hp_per_kill = i._reisen_lunatic_boosted and REISEN_KILL_HP_PER_KILL_BOOSTED or REISEN_KILL_HP_PER_KILL
		local boss_mult = victim:HasTag("epic") and 10 or 1
		local gain = effective_ls * hp_per_kill * boss_mult
		local new_accum = math.min(prev_accum + gain, REISEN_KILL_HP_ACCUM_CAP)
		i._reisen_kill_hp_accum = new_accum
		reisen_sync_kill_hp_accum_net(i)
		if (new_accum >= REISEN_KILL_HP_ACCUM_CAP or new_accum > prev_accum) and not i._reisen_accum_fx_pending then
			-- Accum increased or already at cap: coalesce multi-kill FX into a single spawn next frame.
			i._reisen_accum_fx_pending = true
			i:DoTaskInTime(0, function(inst2)
				inst2._reisen_accum_fx_pending = false
				if not inst2:IsValid() then return end
				local px, py, pz = inst2.Transform:GetWorldPosition()
				local fx = SpawnPrefab("attune_in_fx")
				if fx ~= nil then
					fx.Transform:SetPosition(px, py, pz)
				end
				-- Show current accum / cap above head (coalesced, reflects final value after burst).
				local cur_accum = inst2._reisen_kill_hp_accum or 0
				local at_cap = cur_accum >= REISEN_KILL_HP_ACCUM_CAP
				-- When at cap, gate the label (and the follow-up hint) behind a shared 10 s cooldown.
				local label_allowed = true
				if at_cap then
					local cd_key = "ACCUM_LABEL_CAP"
					local now = GetTime()
					inst2._reisen_hidden_hint_cd = inst2._reisen_hidden_hint_cd or {}
					if (inst2._reisen_hidden_hint_cd[cd_key] or 0) > now then
						label_allowed = false
					else
						inst2._reisen_hidden_hint_cd[cd_key] = now + 10
					end
				end
				if label_allowed and cur_accum > 0 and inst2.components.talker ~= nil then
					local fmt = STRINGS.REISEN_ACCUM_FMT or "ACCUM: %d/%d"
					inst2.components.talker:Say(string.format(fmt, cur_accum, REISEN_KILL_HP_ACCUM_CAP), 2.5)
				end
				-- When at cap and label was shown: show ACCUM_FULL hint after the label fades (2.5 s delay).
				if at_cap and label_allowed then
					inst2:DoTaskInTime(2.5, function(i2)
						if i2:IsValid() then
							reisen_say_hidden_hint(i2, "ANNOUNCE_REISEN_ACCUM_FULL", 10)
						end
					end)
				end
			end)
		end
	end)
	reisen_update_lunatic_state(inst)
	-- Mind Blowing / Moon Port MODE A: modmain fires when kill pool is at cap (`RELEASE_HEAL_ACCUM_CAP`).
	inst:ListenForEvent("reisen_boost_triggered", function(i)
		reisen_on_booster_applied(i)
	end)
	inst:ListenForEvent("reisen_charm_shadow_spawned", function(i)
		reisen_say_hidden_hint(i, "ANNOUNCE_REISEN_CHARM_SHADOW", 25)
	end)
	inst:ListenForEvent("reisen_zero_san_work", function(i)
		reisen_say_hidden_hint(i, "ANNOUNCE_REISEN_ZERO_SAN_WORK", 15)
	end)
	-- Mode B (Slow Field) released stack to zero: run the unified exit flow.
	inst:ListenForEvent("reisen_stack_zeroed", function(i)
		if not TheWorld.ismastersim then return end
		reisen_zero_lunatic_stack(i)
	end)

	inst:WatchWorldState("cycles",      function(i) reisen_molt_on_world_cycles(i) end)

	local FULLMOON_LUNACY_KEY = "reisen_fullmoon"

	local function reisen_set_fullmoon_enlightenment(i, enable)
		local s = i.components.sanity
		if s ~= nil and s.EnableLunacy ~= nil then
			s:EnableLunacy(enable, FULLMOON_LUNACY_KEY)
		end
	end

	-- Full moon: master_postinit is server-only, no extra ismastersim guard needed.
	-- TheWorld.state.isfullmoon check prevents the end-of-full-moon callback from triggering.
	inst:WatchWorldState("isfullmoon", function(i)
		if TheWorld.state.isfullmoon then
			reisen_on_booster_applied(i)
			reisen_set_fullmoon_enlightenment(i, true)
			if i.components.luckuser ~= nil then
				i.components.luckuser:SetLuckSource(REISEN_FULLMOON_LUCK, REISEN_FULLMOON_LUCK_KEY)
			end
		else
			reisen_set_fullmoon_enlightenment(i, false)
			if i.components.luckuser ~= nil then
				i.components.luckuser:RemoveLuckSource(REISEN_FULLMOON_LUCK_KEY)
			end
		end
	end)
	-- Apply immediately if spawned during a full moon.
	if TheWorld.state.isfullmoon then
		reisen_set_fullmoon_enlightenment(inst, true)
		if inst.components.luckuser ~= nil then
			inst.components.luckuser:SetLuckSource(REISEN_FULLMOON_LUCK, REISEN_FULLMOON_LUCK_KEY)
		end
	end
	-- Reset the negative-MEAT eat counter at the start of each day, matching pigman
	-- werebeast ResetTriggers on transform (one "charge" period ≈ one day).
	inst:WatchWorldState("isday", function(i)
		if TheWorld.state.isday then
			i._reisen_boosted_meat_trigger_count = 0
		end
		lunatic_deferred(i)
	end)
	inst:WatchWorldState("isdusk",      function(i) lunatic_deferred(i) end)
	inst:WatchWorldState("isnight",     function(i) lunatic_deferred(i) end)
	inst:WatchWorldState("iscaveday",   function(i) lunatic_deferred(i) end)
	inst:WatchWorldState("iscavedusk",  function(i) lunatic_deferred(i) end)
	inst:WatchWorldState("iscavenight", function(i) lunatic_deferred(i) end)

	lunatic(inst)
	reisen_sync_starving_insanity(inst)
	reisen_update_vuln_hint_sanity(inst)
	reisen_update_vuln_hint_hunger(inst)
	return inst
end

return MakePlayerCharacter("reisen", prefabs, assets, common_postinit, master_postinit, start_inv)
