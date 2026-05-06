--[[
==============================================================================
reisen_charm  —  Reisen's Shadow Choker (HEAD slot)
==============================================================================

OVERVIEW
    A fueled hat that suppresses all negative sanity effects while worn,
    at the cost of increased hunger during night and a continuous sanity
    penalty. Runs on Nightmare Fuel; spawns a nightmarebeaks from the shadows
    when the wearer is hit (eligible attacks).

STATS
    Fuel type   : NIGHTMARE
    Max fuel    : TOTAL_DAY_TIME × 2  (two full in-game days)
    Drain rate  : 1 unit/s while equipped (starts immediately on equip)
    Fuel inputs : Nightmare Fuel → +25%  max fuel per piece
                  Horror Fuel   → +50%  max fuel per piece
    On unequip  : -25% max fuel (equip-to-model excluded)
    On depletion: item is removed (destroyed).

SANITY PENALTY
    Continuous drain multiplier: -50%  (AddSanityPenalty / RemoveSanityPenalty).

IMMUNITY  (suppressed when owner hunger == 0)
    While hunger > 0:
      neg_aura_mult          = 0   (ignore all negative aura sources)
      dapperness             = 0
      dapperness_mult        = 0
      SetNegativeAuraImmunity(true)
      SetLightDrainImmune(true)
      night_drain_mult       = 0

    When hunger drops to 0 the immunity is removed until hunger recovers.
    Tracked via "hungerdelta" listener → charm_sync_immunity().


SNAPSHOT / RESTORE  (non-reisen owners only)
    On equip, the owner's current neg_aura_mult and dapperness_mult are stored
    in owner._reisen_charm_snap.
    s.dapperness is intentionally NOT snapshotted or zeroed: other equipped
    items continue to add/subtract their dapperness normally while the charm
    is worn. The charm suppresses dapperness effects via dapperness_mult = 0
    instead of overwriting the accumulated base value. This prevents a bug
    where unequipping a dapperness item while the charm is active would cause
    its contribution to be "lost" and then wrongly restored from the stale
    snapshot on charm removal.
    On unequip, charm_remove_immunity() restores only neg_aura_mult and
    dapperness_mult, then clears the snapshot.

TERRORBEAK SPAWN
    When the owner is attacked (valid combat attacker):
      - 20% probability of triggering per eligible hit.
      - On roll success: always apply trigger fuel cost (independent of creature
        count or whether spawn actually happens).
      - Count shadowcreature / nightmarecreature within 30 m. Cap = 5.
      - If count > 5: cull farthest extras down to 5; no spawn.
      - If count >= 5: no spawn.
      - If count < 5: check 0.5 s cooldown; if ok, spawn nightmarebeaks 15 m away
        and fire "reisen_charm_shadow_spawned".
      - Nightmarebeaks auto-removes after 1/3 of a day, or 10 s after charm unequip
        (whichever comes first).

REISEN INTERACTION
    _reisen_charm_worn flag read by lunatic():
      - Sets neg_aura_mult = 0, night_drain_mult = 0, dapperness = 0,
        dapperness_mult = 0, NegativeAuraImmunity, LightDrainImmune
        (only when hunger > 0)

    On UNEQUIP, clear_charm_sanity() explicitly calls
      SetNegativeAuraImmunity(false), SetLightDrainImmune(false),
      dapperness_mult = 1  before firing reisen_stats_dirty, so lunatic()
      recalculates from a clean state.

EQUIP TO MODEL (mannequin / display)
    Calls clear_charm_sanity() and stops fuel consumption; the item does not
    grant effects when displayed on a model.

TAGS ADDED TO ITEM
    "hat", "reisen_charm", "shadowlevel"
==============================================================================
--]]

local CHARM_BANK = "reisenhat"
local CHARM_BUILD = "reisen_hat"
local CHARM_WORLD_SCALE = 1.25

local function refresh_charm_world_scale(inst)
	if inst.AnimState == nil or inst.components.inventoryitem == nil then
		return
	end
	if inst.components.inventoryitem:IsHeld() then
		inst.AnimState:SetScale(1, 1)
	else
		inst.AnimState:SetScale(CHARM_WORLD_SCALE, CHARM_WORLD_SCALE)
	end
end

local assets =
{
	Asset("ANIM", "anim/reisen_charm.zip"),
	Asset("ATLAS", "images/inventoryimages/reisen_charm.xml"),
	Asset("IMAGE", "images/inventoryimages/reisen_charm.tex"),
	Asset("ANIM", "anim/ui_chest_3x1.zip"),
}

local prefabs = { "nightmarebeaks" }

local CHARM_SWAP_DATA = { bank = CHARM_BANK, anim = "anim" }

local function clear_hat_swap_visual(owner)
	if owner ~= nil and owner:IsValid() and owner.AnimState ~= nil then
		owner.AnimState:ClearOverrideSymbol("swap_hat")
	end
end

local CHARM_MAX_FUEL           = TUNING.TOTAL_DAY_TIME * 2
local CHARM_FUEL_RATE          = 1
local CHARM_SANITY_PENALTY     = 0.50
-- On eligible hit: 10% roll; on success, fuel cost and spawn logic below.
local CHARM_TERRORBEAK_SPAWN_CHANCE    = 0.10
local CHARM_TERRORBEAK_DURABILITY_LOSS = 0.10
-- Min seconds between actual terrorbeak spawns (gates spawn only; not roll/fuel/cull).
local CHARM_TERRORBEAK_SPAWN_COOLDOWN  = 1.5
-- Max shadow + nightmare creatures near owner before blocking spawn; over-cap are culled.
local CHARM_SHADOW_CREATURE_CAP        = 5
local CHARM_SHADOW_COUNT_RADIUS        = 30
local CHARM_SHADOW_COUNT_CANT_TAGS     = { "INLIMBO", "FX" }
local CHARM_SHADOW_COUNT_ONEOF_TAGS    = { "shadowcreature", "nightmarecreature" }
-- Each real unequip (not equip-to-model) costs 25% of max fuel.
local CHARM_UNEQUIP_DURABILITY_LOSS = 0.125
-- How often (seconds) the equipped charm checks whether to pull fuel from its container.
local CHARM_FUEL_CHECK_PERIOD = 5
-- Consume a nightmare fuel piece when currentfuel/maxfuel falls below this ratio.
local CHARM_REFUEL_THRESHOLD_NIGHTMARE = 0.75
-- Consume a horror fuel piece when currentfuel/maxfuel falls below this ratio.
local CHARM_REFUEL_THRESHOLD_HORROR   = 0.50

--------------------------------------------------------------------------
-- Immunity toggle helpers
-- Non-reisen: directly manipulate sanity fields with _reisen_charm_immune_active guard.
-- Reisen: push reisen_stats_dirty; lunatic() handles the actual field values.
--------------------------------------------------------------------------

-- Applies or removes night_drain_mult = 0 for non-reisen owners wearing the charm.
-- Original value is cached in _reisen_night_drain_original and restored on removal.
local function recompute_night_drain(owner)
	if owner.prefab == "reisen" then return end
	local s = owner.components.sanity
	if s == nil then return end
	if owner._reisen_charm_immune_active then
		if owner._reisen_night_drain_original == nil then
			owner._reisen_night_drain_original = s.night_drain_mult
		end
		s.night_drain_mult = 0
	else
		if owner._reisen_night_drain_original ~= nil then
			s.night_drain_mult = owner._reisen_night_drain_original
			owner._reisen_night_drain_original = nil
		end
	end
end

local function charm_apply_immunity(inst, owner)
	if owner.prefab == "reisen" then
		owner:PushEvent("reisen_stats_dirty")
		return
	end
	if owner._reisen_charm_immune_active then return end
	owner._reisen_charm_immune_active = true
	local s = owner.components.sanity
	if s == nil then return end
	s:SetNegativeAuraImmunity(true)
	s:SetLightDrainImmune(true)
	s.neg_aura_mult = 0
	-- Do NOT zero s.dapperness directly: other equipped items continue to
	-- add/subtract their dapperness via the normal equippable system while
	-- the charm is worn. Zeroing the field would corrupt that accumulated
	-- value and cause stale dapperness when those items are later unequipped.
	-- Suppressing via dapperness_mult = 0 is safe: the base value stays
	-- intact and the multiplier is restored cleanly on unequip.
	s.dapperness_mult = 0
	recompute_night_drain(owner)
end

local function charm_remove_immunity(inst, owner)
	if owner.prefab == "reisen" then
		owner:PushEvent("reisen_stats_dirty")
		return
	end
	if not owner._reisen_charm_immune_active then return end
	owner._reisen_charm_immune_active = false
	local s = owner.components.sanity
	if s == nil then return end
	s:SetNegativeAuraImmunity(false)
	s:SetLightDrainImmune(false)
	local snap = owner._reisen_charm_snap
	if snap ~= nil then
		s.neg_aura_mult = snap.neg_aura_mult
		-- s.dapperness is intentionally not restored here: it was never
		-- zeroed by charm_apply_immunity, so it reflects the true current
		-- accumulated value from all equipped items.
		s.dapperness_mult = snap.dapperness_mult
	end
	recompute_night_drain(owner)
end

-- Apply or remove immunity based on current hunger state.
local function charm_sync_immunity(inst, owner)
	if not owner._reisen_charm_worn then return end
	if owner.components.hunger ~= nil and owner.components.hunger.current <= 0 then
		charm_remove_immunity(inst, owner)
	else
		charm_apply_immunity(inst, owner)
	end
end


--------------------------------------------------------------------------
-- Talker helper
--------------------------------------------------------------------------

-- Make the charm's owner speak a line from their speech file (key in CHARACTERS.REISEN).
local function charm_say(inst, key)
	local owner = inst._charm_owner
		or (inst.components.inventoryitem and inst.components.inventoryitem.owner)
	if owner == nil or not owner:IsValid() then return end
	local t = owner.components.talker
	if t == nil then return end
	local speech = STRINGS.CHARACTERS
		and STRINGS.CHARACTERS.REISEN
		and STRINGS.CHARACTERS.REISEN[key]
	if type(speech) == "string" and speech ~= "" then
		t:Say(speech)
	end
end

--------------------------------------------------------------------------
-- Container helpers
--------------------------------------------------------------------------

-- Slots 1-2 are fuel (nightmare / horror); slot 3 is the passive shadowheart socket.
local CHARM_FUEL_SLOTS = 2

-- Return the item in slot 3, or nil.
local function charm_get_shadowheart(inst)
	if inst.components.container == nil then return nil end
	local item = inst.components.container:GetItemInSlot(3)
	if item ~= nil and (item.prefab == "shadowheart" or item.prefab == "shadowheart_infused") then
		return item
	end
	return nil
end

-- Find the first occupied fuel slot (1 or 2); return (slot_index, item) or (nil, nil).
local function charm_find_fuel_slot(inst)
	local c = inst.components.container
	if c == nil then return nil, nil end
	for i = 1, CHARM_FUEL_SLOTS do
		local item = c:GetItemInSlot(i)
		if item ~= nil and (item.prefab == "nightmarefuel" or item.prefab == "horrorfuel") then
			return i, item
		end
	end
	return nil, nil
end

-- Consume exactly one piece from the first occupied fuel slot in the container.
-- Returns the fuel amount added (> 0), or 0 if the container is empty / invalid.
local function charm_consume_one_from_container(inst)
	if inst.components.fueled == nil then return 0 end
	local slot, item = charm_find_fuel_slot(inst)
	if slot == nil then return 0 end
	local fmult = (item.prefab == "horrorfuel" and 0.50) or 0.25
	local added = inst.components.fueled.maxfuel * fmult
	local st = item.components.stackable
	if st ~= nil and st:StackSize() > 1 then
		st:SetStackSize(st:StackSize() - 1)
	else
		inst.components.container:RemoveItemBySlot(slot)
		item:Remove()
	end
	return added
end

--------------------------------------------------------------------------
-- Attacked: roll, fuel on success, cull if overcap, spawn (with cd gate).
-- No sanity==0 requirement (trigger at any sanity).
--------------------------------------------------------------------------

local function charm_collect_shadow_creatures(x, y, z)
	local raw = TheSim:FindEntities(
		x, y, z,
		CHARM_SHADOW_COUNT_RADIUS,
		nil,
		CHARM_SHADOW_COUNT_CANT_TAGS,
		CHARM_SHADOW_COUNT_ONEOF_TAGS
	)
	local ents = {}
	for _, e in ipairs(raw) do
		if e ~= nil and e:IsValid()
			and e.components.health ~= nil
			and not e.components.health:IsDead()
		then
			table.insert(ents, e)
		end
	end
	return ents
end

-- Periodic tick (runs only while equipped): consume one fuel piece when the charge
-- ratio drops below the threshold for the fuel type in the first occupied slot.
--   nightmarefuel: adds 25 % → refuel at < 75 %
--   horrorfuel:    adds 50 % → refuel at < 50 %
local function charm_auto_refuel_tick(inst)
	if inst.components.fueled == nil or inst.components.container == nil then return end
	local f = inst.components.fueled
	local _, item = charm_find_fuel_slot(inst)
	if item == nil then return end
	local threshold =
		(item.prefab == "nightmarefuel" and CHARM_REFUEL_THRESHOLD_NIGHTMARE) or
		(item.prefab == "horrorfuel"    and CHARM_REFUEL_THRESHOLD_HORROR)    or
		nil
	if threshold == nil then return end
	while f.currentfuel / f.maxfuel < threshold do
		local added = charm_consume_one_from_container(inst)
		if added <= 0 then break end
		f:DoDelta(added)
	end
end

-- Unified handler for all non-time-triggered fuel costs.
-- Deducts ratio * maxfuel, then immediately runs the refuel check so the
-- container compensates for the loss where possible.
local function charm_spend_fuel(inst, ratio)
	local f = inst.components.fueled
	if f == nil then return end
	f:DoDelta(-(f.maxfuel * ratio))
	charm_auto_refuel_tick(inst)
end

local function charm_apply_terrorbeak_fuel_cost(inst)
	if inst:IsValid() then
		charm_spend_fuel(inst, CHARM_TERRORBEAK_DURABILITY_LOSS)
	end
end

local function charm_on_attacked(inst, owner, data)
	if not owner:IsValid() then return end
	if owner.sg ~= nil and owner.sg:HasStateTag("dead") then return end
	-- Require a real combat attacker; sanity-system damage fires "attacked" with no attacker.
	if data == nil or data.attacker == nil or not data.attacker:IsValid() then return end
	-- shadowheart_infused in slot 3 suppresses terrorbeak spawning entirely.
	-- Plain shadowheart does NOT grant this protection.
	local sh = charm_get_shadowheart(inst)
	if sh ~= nil and sh.prefab == "shadowheart_infused" then return end
	if math.random() > CHARM_TERRORBEAK_SPAWN_CHANCE then return end

	charm_apply_terrorbeak_fuel_cost(inst)

	local x, y, z = owner.Transform:GetWorldPosition()
	local ents = charm_collect_shadow_creatures(x, y, z)

	if #ents > CHARM_SHADOW_CREATURE_CAP then
		table.sort(ents, function(a, b)
			return owner:GetDistanceSqToInst(a) > owner:GetDistanceSqToInst(b)
		end)
		for i = 1, #ents - CHARM_SHADOW_CREATURE_CAP do
			local e = ents[i]
			if e ~= nil and e:IsValid() then
				e:Remove()
			end
		end
		return
	end

	if #ents >= CHARM_SHADOW_CREATURE_CAP then
		return
	end

	local t = GetTime()
	if t - (inst._charm_tb_spawn_cd or 0) < CHARM_TERRORBEAK_SPAWN_COOLDOWN then
		return
	end

	local angle = math.random() * 2 * math.pi
	local tb = SpawnPrefab("nightmarebeaks")
	if tb ~= nil then
		tb.Transform:SetPosition(x + 15 * math.cos(angle), 0, z - 15 * math.sin(angle))
		tb:DoTaskInTime(TUNING.TOTAL_DAY_TIME / 4, function(s)
			if s ~= nil and s:IsValid() then s:Remove() end
		end)
		if inst._charm_spawned_tbs == nil then
			inst._charm_spawned_tbs = {}
		end
		table.insert(inst._charm_spawned_tbs, tb)
		if owner ~= nil and owner:IsValid() then
			owner:PushEvent("reisen_charm_shadow_spawned")
		end
	end
	inst._charm_tb_spawn_cd = t
end

--------------------------------------------------------------------------
-- Fuel multiplier
--------------------------------------------------------------------------

local function charm_fuel_mult(inst, fuel_obj)
	local maxf = inst.components.fueled.maxfuel
	local fv = fuel_obj.components.fuel.fuelvalue
	if fuel_obj.prefab == "nightmarefuel" then
		return (0.25 * maxf) / fv
	elseif fuel_obj.prefab == "horrorfuel" then
		return (0.50 * maxf) / fv
	end
	return 1
end

local function charm_cancel_refuel_task(inst)
	if inst._charm_refuel_task ~= nil then
		inst._charm_refuel_task:Cancel()
		inst._charm_refuel_task = nil
	end
end

--------------------------------------------------------------------------
-- Equip / unequip logic
--------------------------------------------------------------------------

local function apply_charm_sanity(inst, owner)
	local s = owner.components.sanity
	if s == nil then return end
	owner._reisen_charm_worn = true
	owner._reisen_charm_immune_active = false
	s:AddSanityPenalty(inst, CHARM_SANITY_PENALTY)

	if owner.prefab ~= "reisen" then
		if owner._reisen_charm_snap == nil then
			owner._reisen_charm_snap = {
				neg_aura_mult   = s.neg_aura_mult,
				dapperness_mult = s.dapperness_mult,
				-- s.dapperness is NOT snapshotted: charm_apply_immunity never
				-- zeroes it, so it keeps tracking other equipped items correctly
				-- and requires no restore on unequip.
			}
		end
		inst._charm_hunger_fn = function(o)
			charm_sync_immunity(inst, o)
		end
		inst:ListenForEvent("hungerdelta", inst._charm_hunger_fn, owner)
	end

	inst._charm_attacked_fn = function(o, data)
		charm_on_attacked(inst, o, data)
	end
	inst:ListenForEvent("attacked", inst._charm_attacked_fn, owner)

	inst._charm_owner = owner
	charm_sync_immunity(inst, owner)
end

local function clear_charm_sanity(inst, owner)
	if not (owner ~= nil and owner._reisen_charm_worn) then return end

	inst._charm_owner = nil

	if inst._charm_attacked_fn ~= nil then
		inst:RemoveEventCallback("attacked", inst._charm_attacked_fn, owner)
		inst._charm_attacked_fn = nil
	end

	if owner.prefab ~= "reisen" then
		if inst._charm_hunger_fn ~= nil then
			inst:RemoveEventCallback("hungerdelta", inst._charm_hunger_fn, owner)
			inst._charm_hunger_fn = nil
		end
		charm_remove_immunity(inst, owner)
		owner._reisen_charm_snap = nil
	end

	owner._reisen_charm_worn = false
	owner._reisen_charm_immune_active = nil
	inst._charm_tb_spawn_cd = nil

	local s = owner.components.sanity
	if s ~= nil then
		s:RemoveSanityPenalty(inst)
	end

	if owner.prefab == "reisen" then
		local s = owner.components.sanity
		if s ~= nil then
			s:SetNegativeAuraImmunity(false)
			s:SetLightDrainImmune(false)
			s.dapperness_mult = 1
		end
		owner:PushEvent("reisen_stats_dirty")
	end
end

local function opentop_onequip(inst, owner)
	if inst.components.fueled ~= nil then
		inst.components.fueled:StartConsuming()
	end
	inst._charm_refuel_task = inst:DoPeriodicTask(CHARM_FUEL_CHECK_PERIOD, charm_auto_refuel_tick)
	charm_auto_refuel_tick(inst)  -- immediate check on equip
	apply_charm_sanity(inst, owner)
	-- Worn art is inventory/world only; do not draw a hat swap on the character.
	clear_hat_swap_visual(owner)
	inst:DoTaskInTime(0, function()
		clear_hat_swap_visual(owner)
	end)
	inst:DoTaskInTime(1 / 30, function()
		clear_hat_swap_visual(owner)
	end)
end

local function charm_schedule_spawned_tb_removal(inst)
	local tbs = inst._charm_spawned_tbs
	if tbs == nil then return end
	inst._charm_spawned_tbs = nil
	for _, tb in ipairs(tbs) do
		if tb ~= nil and tb:IsValid() then
			tb:DoTaskInTime(2.5, function(s)
				if s ~= nil and s:IsValid() then s:Remove() end
			end)
		end
	end
end

local function opentop_onunequip(inst, owner)
	charm_cancel_refuel_task(inst)
	charm_schedule_spawned_tb_removal(inst)
	clear_charm_sanity(inst, owner)
	if inst.components.fueled ~= nil then
		-- Shadowheart in slot 3 protects against the unequip durability penalty.
		-- charm_spend_fuel applies the cost then refuels from the container as needed.
		if charm_get_shadowheart(inst) == nil then
			charm_spend_fuel(inst, CHARM_UNEQUIP_DURABILITY_LOSS)
		end
		inst.components.fueled:StopConsuming()
	end
end

local function onequiptomodel(inst, owner, from_ground)
	charm_cancel_refuel_task(inst)
	charm_schedule_spawned_tb_removal(inst)
	clear_charm_sanity(inst, owner)
	if inst.components.fueled ~= nil then
		inst.components.fueled:StopConsuming()
	end
end

local function charm_drop_contents(inst)
	if inst.components.container == nil then return end
	local pos = inst:GetPosition()
	inst.components.container:DropEverything(pos)
end

local function onfueldepleted(inst)
	local added = charm_consume_one_from_container(inst)
	if added > 0 then
		inst.components.fueled:DoDelta(added)
	else
		charm_say(inst, "ANNOUNCE_REISEN_CHARM_FUEL_EMPTY")
		charm_drop_contents(inst)
		inst:Remove()
	end
end

--------------------------------------------------------------------------
-- Prefab construction
--------------------------------------------------------------------------

local function fn()
	local inst = CreateEntity()

	inst.entity:AddTransform()
	inst.entity:AddAnimState()
	inst.entity:AddSoundEmitter()
	inst.entity:AddNetwork()

	MakeInventoryPhysics(inst)

	inst.AnimState:SetBank(CHARM_BANK)
	inst.AnimState:SetBuild(CHARM_BUILD)
	inst.AnimState:PlayAnimation("anim")
	inst.scrapbook_anim = "anim"

	inst:AddTag("hat")
	inst:AddTag("reisen_charm")
	inst:AddTag("shadowlevel")

	MakeInventoryFloatable(inst)
	inst.components.floater:SetBankSwapOnFloat(false, nil, CHARM_SWAP_DATA)
	inst.components.floater:SetSize("med")
	inst.components.floater:SetScale(0.68)

	inst.entity:SetPristine()

	if not TheWorld.ismastersim then
		return inst
	end

	inst:AddComponent("inspectable")

	inst:AddComponent("inventoryitem")
	inst.components.inventoryitem.atlasname = "images/inventoryimages/reisen_charm.xml"
	inst.components.inventoryitem:SetOnDroppedFn(refresh_charm_world_scale)
	inst.components.inventoryitem:SetOnPutInInventoryFn(function(i)
		refresh_charm_world_scale(i)
	end)

	inst:AddComponent("equippable")
	inst.components.equippable.equipslot = EQUIPSLOTS.HEAD
	inst.components.equippable.dapperness = 0
	inst.components.equippable.is_magic_dapperness = false
	inst.components.equippable:SetOnEquip(opentop_onequip)
	inst.components.equippable:SetOnUnequip(opentop_onunequip)
	inst.components.equippable:SetOnEquipToModel(onequiptomodel)

	inst:AddComponent("fueled")
	inst.components.fueled:InitializeFuelLevel(CHARM_MAX_FUEL)
	inst.components.fueled.maxfuel = CHARM_MAX_FUEL
	inst.components.fueled.rate = CHARM_FUEL_RATE
	inst.components.fueled.fueltype = FUELTYPE.NIGHTMARE
	inst.components.fueled.accepting = false  -- fuel via container slot only
	inst.components.fueled:SetDepletedFn(onfueldepleted)
	inst.components.fueled:SetMultiplierFn(charm_fuel_mult)

	inst:AddComponent("container")
	inst.components.container:WidgetSetup("reisen_charm")
	inst.components.container.acceptsstacks = true
	inst:ListenForEvent("itemget", function(i, data)
		if data == nil or data.slot ~= 3 or data.item == nil then return end
		if data.item.prefab == "shadowheart_infused" then
			charm_say(i, "ANNOUNCE_REISEN_CHARM_SHADOWHEART_INF")
		elseif data.item.prefab == "shadowheart" then
			charm_say(i, "ANNOUNCE_REISEN_CHARM_SHADOWHEART")
		end
	end)

	inst:AddComponent("shadowlevel")
	inst.components.shadowlevel:SetDefaultLevel(TUNING.AMULET_SHADOW_LEVEL)

	MakeHauntableLaunch(inst)

	inst:DoTaskInTime(0, refresh_charm_world_scale)

	return inst
end

return Prefab("reisen_charm", fn, assets, prefabs)
