-- Shared constants for the lunatic stack system and hunger thresholds.
-- Used by scripts/prefabs/reisen.lua, reisen_casual.lua, and scripts/widgets/reisen_lunarbadge.lua.
return {
	-- ── Lunatic stack thresholds ─────────────────────────────────────────
	LUNATIC_MAX       = 10,   -- maximum stack value
	LUNATIC_STACK_LOW = 1,    -- low threshold: base effects kick in above this
	LUNATIC_STACK_MID = 4,    -- mid threshold: san conversion + vuln relief kick in above this
	LUNATIC_STACK_HI  = 7,    -- hi  threshold: damage mult + hunger drain scale above this

	-- ── Hunger thresholds (normalised, 0–1 of max hunger) ────────────────
	-- Compare: inst.components.hunger.current < HUNGER_LOW * inst.components.hunger.max
	HUNGER_HIGH = 0.75,  -- "well-fed": enables zero-san HP regen, casual outfit sanity bonus
	HUNGER_MID  = 0.40,  -- mid-hunger marker (reserved for future use)
	HUNGER_LOW  = 0.15,  -- low hunger: triggers vulnerability penalty and blocks molting

	-- ── Dualgear night spawn ─────────────────────────────────────────────
	DUALGEAR_SHADOW_SPAWN_INTERVAL = 90,  -- seconds between shadow spawns at night

	-- ── Dualgear: shadow hit damage bonus (all characters) ───────────────
	-- Hitting a shadowcreature / nightmarecreature while wearing full dualgear
	-- grants +DUALGEAR_SHADOW_DMG_PER_STACK flat bonus damage per stack, up to
	-- DUALGEAR_SHADOW_DMG_MAX_STACKS stacks.  Each hit refreshes the timer;
	-- expiry clears all stacks at once.
	DUALGEAR_SHADOW_DMG_PER_STACK  = 10,  -- +10 flat bonus damage per stack
	DUALGEAR_SHADOW_DMG_MAX_STACKS = 5,   -- cap: 5 stacks = +50 flat max
	DUALGEAR_SHADOW_DMG_DURATION   = 30,  -- seconds until stacks expire

	-- ── Moon charm: shadow overwhelm (server sanity.sane gate in modmain) ─
	-- When nearby shadowcreature count is >= this value, charm immunity stops.
	CHARM_SHADOW_OVERWHELM_THRESHOLD = 3,

	-- Boosted state: extra hunger rate (reisen.lua) and boosted Mind Blowing
	-- hunger-only cost in modmain use the same multiplier.
	BOOSTED_HUNGER_MULT = 1.33,

	-- ── Release Mind Blowing (right-click heal release) ──────────────────
	-- Two modes: Mind Blowing (accum > 0) and Slow Field (accum = 0).

	-- Mind Blowing uses fixed RADIUS_MAX; Slow Field uses fixed RADIUS_MIN.
	RELEASE_HEAL_RADIUS_MIN   = 2,     -- Slow Field AoE radius
	RELEASE_HEAL_RADIUS_MAX   = 4,     -- Mind Blowing AoE radius

	-- Mind Blowing (accum > 0): fixed fear duration.
	RELEASE_HEAL_FEAR_DURATION = 10.0,
	-- Self-heal fraction is now dynamic: 1 / damagemultiplier (higher damage → less self-heal).
	-- RELEASE_HEAL_SELF_FRACTION removed; the fraction is computed at cast time in modmain.lua.
	RELEASE_HEAL_SANITY_COST  = 5,    -- sanity cost for Mind Blowing

	-- Mind Blowing boosted mode (lunatic boosted active):
	--   only drains hunger (no sanity), smaller self-heal, separate radius.
	RELEASE_HEAL_RADIUS_BOOSTED    = 6,   -- AoE radius in boosted mode
	-- Mind Blowing cast (modmain): accum × BOOSTED_SELF_MULT / damagemultiplier.
	-- Kill-pool payout on stack zero (reisen.lua reisen_apply_kill_hp_accum): accum × BOOSTED_SELF_MULT only.
	RELEASE_HEAL_BOOSTED_SELF_MULT = 0.5,
	-- (boosted hunger cost uses BOOSTED_HUNGER_MULT above)

	-- Slow Field (accum = 0): distance-based slow, no damage, costs stack.
	RELEASE_SLOW_SANITY_COST  = 2.5,     -- sanity cost for Slow Field
	RELEASE_SLOW_STACK_COST   = 1,     -- lunatic stacks consumed per Slow Field cast
	RELEASE_SLOW_MULT         = 0.5,   -- speed multiplier at outer radius (50% speed = 50% slow)
	RELEASE_SLOW_MULT_NEAR    = 0.25,  -- speed multiplier at inner radius (5% speed = 95% slow)
	RELEASE_SLOW_DURATION     = 20.0,   -- slow duration in seconds

	-- Fallback cost: if sanity < cost, drain hunger instead.
	-- hunger_cost = sanity_cost × (-1 + vuln), vuln is usually ≤ 0.
	-- e.g. vuln=0 → -10 hunger; vuln=-1 → -20 hunger.

	RELEASE_HEAL_ACCUM_CAP    = 100,   -- max kill-accumulation HP pool
	RELEASE_HEAL_TARGET_DIST  = 18,    -- max targeting distance for right-click release

	-- ── Kill accumulation ─────────────────────────────────────────────────
	-- Each kill adds min(stack+1, LUNATIC_MAX) × KILL_HP_PER_KILL to the pool.
	-- Pool is capped at RELEASE_HEAL_ACCUM_CAP.
	KILL_HP_PER_KILL          = 1,     -- HP accumulated per lunatic stack per kill (normal mode)
	KILL_HP_PER_KILL_BOOSTED  = 2,     -- HP accumulated per lunatic stack per kill (boosted mode)

	-- ── Boosted state: auto-collect on pick/harvest ───────────────────────
	-- When boosted, performing PICK or HARVEST auto-collects all pickable /
	-- harvestable objects within this radius of the caster.
	BOOSTED_AUTO_COLLECT_RADIUS = 8,

	-- ── Moon Port ─────────────────────────────────────────────────────────
	-- Right-click empty tile to teleport and release Mind Blowing at destination.
	MOON_PORT_RANGE = 12,   -- max targeting distance (ground cursor range)

	-- ── PvP behaviour (only meaningful when TheNet:GetPVPEnabled() is true) ─
	-- Layered gate for player-vs-player effects.  All four conditions must
	-- pass before a hostile-player branch fires:
	--   1) TheNet:GetPVPEnabled()             -- world setting (server authoritative)
	--   2) PVP_ENABLE_<feature>               -- mod-level switches (this section)
	--   3) doer.components.combat:CanTarget   -- vanilla team/state filter
	--   4) target is "player" and not "playerghost"
	-- Damage uses combat.pvp_damagemod (vanilla TUNING.PVP_DAMAGE_MOD = 0.5),
	-- so balance follows whatever the engine ships.
	PVP_ENABLE_DAMAGE              = true,    -- Mind Blowing / Moon Port can damage hostile players
	PVP_ENABLE_SLOW                = true,    -- Mind Blowing / Mind Stopper can slow hostile players
	PVP_ENABLE_FEAR                = false,   -- locked off: players have no hauntable; never panic players
	-- Slow strength relaxation for player targets only:
	--   applied = 1 - (1 - mult) * (1 - PVP_SLOW_RELAX)
	-- 0.0 = full strength on players (same as creatures)
	-- 0.5 = half-strength slow (recommended)
	-- 1.0 = no slow on players
	PVP_SLOW_RELAX                 = 0.5,

	-- ── Friend heal (Mind Blowing / Moon Port MODE A) ────────────────────
	-- Each friendly player inside the AoE (excluding the caster, who already
	-- self-heals once outside the loop) receives:
	--   accum * self_heal_frac * RELEASE_HEAL_FRIEND_HEAL_MULT
	-- Independent of TheNet:GetPVPEnabled(): in PvP, only allies (those that
	-- combat:CanTarget cannot target) are healed; hostile players take damage.
	RELEASE_HEAL_FRIEND_HEAL_MULT  = 0.5,
}
