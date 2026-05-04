--[[
==============================================================================
reisen_uniform  —  Reisen's Night Armor (BODY slot)
==============================================================================

OVERVIEW
    A shadow-material armor worn by Reisen. Provides physical protection and
    a move-speed bonus, but introduces sanity penalties that scale with wear
    and combat activity.

STATS
    Condition (durability) : 1105
    Absorption             : 0.85  (85%)
    Time durability        : 10 game days (worn time only); not repairable.
                             Armor condition and fueled time share one percentage:
                             combat damage lowers both; time drain lowers both.
    Walk-speed multiplier  : +15% normally; escalates to +30% when san = 0
                             Applied via locomotor:SetExternalSpeedMultiplier for
                             immediate network-synced effect.

SANITY PENALTY  (owner.sanity:AddSanityPenalty / RemoveSanityPenalty)
    Applied as a continuous drain multiplier, not a flat delta.
    - At 100% durability : -25% penalty
    - At   0% durability : -50% penalty  (scales linearly with damage taken)
    - Each time the owner is attacked the penalty is recalculated one tick
      later so armor durability loss is already reflected.
    - Each time the owner lands a hit: -2.5 sanity instantly (-5 if HEAD is
      reisen_charm).

SANITY = 0  BONUS
    While the owner's sanity is 0:
      - "heavyarmor" tag is applied to the ITEM (same mechanism as vanilla marble suit).
        SGwilson.lua checks inventory:EquipHasTag("heavyarmor") to convert the
        airborne "knockback" state into the grounded "knockbacklanded" state.
      - Walk-speed multiplier rises from 1.15 to 1.3.
    Both effects are removed as soon as sanity rises above 0 or the armor is
    unequipped.

HUNGER RATE
    Non-reisen wearers:  hungerrate × 1.2 while equipped.
    Reisen: handled inside lunatic() via _reisen_uniform_worn flag.

REISEN INTERACTION
    Sets owner._reisen_uniform_worn = true/false so lunatic() can apply:
      - hunger multiplier × 1.2
    Triggers reisen_stats_dirty on equip and unequip so lunatic() reruns.

EVENTS LISTENED (while equipped)
    "blocked"  on owner  → plays night-armor block sound
    "armordamaged" on item → match fueled time % to armor % after each hit
    "attacked" on owner  → recalculate sanity penalty after durability drop
    "onhitother" on owner → sanity hit on landed attack (-2.5, or -5 with charm)
    "sanitydelta" on owner → toggle knockback_immune tag at san = 0

TAGS ADDED TO ITEM
    "sanity", "shadow_item", "shadowlevel"
==============================================================================
--]]

local REISEN_UNIFORM_BUILD = "reisen_uniform"

local assets =
{
	Asset("ANIM", "anim/reisen_uniform.zip"),
	Asset("ATLAS", "images/inventoryimages/reisen_uniform.xml"),
	Asset("IMAGE", "images/inventoryimages/reisen_uniform.tex"),
}

local REISEN_UNIFORM_ABSORPTION = 0.85
local REISEN_UNIFORM_CONDITION = 1105
-- Time-based durability: 15 game days when worn; not repairable.
local REISEN_UNIFORM_PERISHTIME = TUNING.TOTAL_DAY_TIME * 8
-- Speed: same mechanism as vanilla walking cane (prefabs/cane.lua: equippable.walkspeedmult).
-- Cane uses TUNING.CANE_SPEED_MULT (1.25); this armor gives +15% move speed.
-- At san = 0 the multiplier escalates to 1.3.
local REISEN_UNIFORM_WALKSPEED_MULT        = 1.10
local REISEN_UNIFORM_WALKSPEED_MULT_INSANE = 1.20
local HUNGER_MULT = 1.2
local UNIFORM_SANITY_PENALTY       = 0.25  -- base penalty (full durability)
local UNIFORM_SANITY_PENALTY_EXTRA = 0.25  -- max additional penalty (0 durability)
-- Sanity lost each time the owner lands a hit (onhitother). Heavier if charm is worn.
local UNIFORM_ATTACK_SANITY_DELTA         = -2.5
local UNIFORM_ATTACK_SANITY_DELTA_CHARM   = -5
local REISEN_CHARM_PREFAB                 = "reisen_charm"

local function uniform_attack_sanity_delta(owner)
	local inv = owner ~= nil and owner.components.inventory or nil
	if inv == nil then return UNIFORM_ATTACK_SANITY_DELTA end
	local hat = inv:GetEquippedItem(EQUIPSLOTS.HEAD)
	if hat ~= nil and hat.prefab == REISEN_CHARM_PREFAB then
		return UNIFORM_ATTACK_SANITY_DELTA_CHARM
	end
	return UNIFORM_ATTACK_SANITY_DELTA
end

-- Penalty scales linearly with durability loss:
--   100% durability -> total -25%  (extra = 0)
--     0% durability -> total -50%  (extra = 0.25)
local function uniform_update_sanity_penalty(inst, owner)
	if owner == nil or not owner:IsValid() then return end
	if owner.components.sanity == nil then return end
	local percent = 1
	if inst.components.armor ~= nil and inst.components.armor.maxcondition > 0 then
		percent = math.max(0, inst.components.armor.condition / inst.components.armor.maxcondition)
	end
	local total = UNIFORM_SANITY_PENALTY + UNIFORM_SANITY_PENALTY_EXTRA * (1 - percent)
	owner.components.sanity:AddSanityPenalty(inst, total)
end

-- Adds or removes the "heavyarmor" tag on the ITEM (inst) based on owner's current sanity.
-- SGwilson.lua checks inventory:EquipHasTag("heavyarmor") to decide between the
-- "knockback" (launch/airborne) and "knockbacklanded" (pushed back on ground) states.
-- The marble suit works by having "heavyarmor" permanently on the item; we apply it
-- conditionally only when sanity == 0.
-- The flag _reisen_uniform_knockback_immune tracks whether WE added the tag.
local function uniform_update_knockback_immune(inst, owner)
	if owner.components.sanity == nil then return end
	if owner.components.sanity.current <= 0 then
		if not owner._reisen_uniform_knockback_immune then
			inst:AddTag("heavyarmor")
			owner._reisen_uniform_knockback_immune = true
		end
	else
		if owner._reisen_uniform_knockback_immune then
			inst:RemoveTag("heavyarmor")
			owner._reisen_uniform_knockback_immune = false
		end
	end
end

-- Switches walk speed between normal and insane tiers based on san = 0.
-- Uses SetExternalSpeedMultiplier so the change is network-synced immediately
-- (externalspeedmultiplier is a classified net var) rather than waiting for
-- the next StartWalking() call that equippable.walkspeedmult would require.
local UNIFORM_SPEED_KEY = "reisen_uniform"
local function uniform_update_walkspeed(inst, owner)
	if owner.components.locomotor == nil then return end
	local mult = (owner.components.sanity ~= nil and owner.components.sanity.current <= 0)
		and REISEN_UNIFORM_WALKSPEED_MULT_INSANE
		or  REISEN_UNIFORM_WALKSPEED_MULT
	owner.components.locomotor:SetExternalSpeedMultiplier(inst, UNIFORM_SPEED_KEY, mult)
end

local function OnBlocked(owner)
	owner.SoundEmitter:PlaySound("dontstarve/wilson/hit_nightarmour")
end

local clear_uniform_stats

local function uniform_destroy(inst)
	if inst._reisen_uniform_destroying then
		return
	end
	inst._reisen_uniform_destroying = true
	if inst.components.equippable ~= nil and inst.components.equippable:IsEquipped() then
		local owner = inst.components.inventoryitem ~= nil and inst.components.inventoryitem.owner or nil
		if owner ~= nil then
			clear_uniform_stats(inst, owner)
		end
	end
	inst:Remove()
end

-- Keep armor % and fueled % identical: UI uses armor for percent; time used to drift alone.
local function uniform_sync_fueled_from_armor(inst)
	if inst._reisen_uniform_destroying or inst._reisen_uniform_syncing then
		return
	end
	local armor = inst.components.armor
	local fueled = inst.components.fueled
	if armor == nil or fueled == nil or armor.maxcondition <= 0 or fueled.maxfuel <= 0 then
		return
	end
	inst._reisen_uniform_syncing = true
	fueled:SetPercent(armor:GetPercent())
	inst._reisen_uniform_syncing = false
end

local function uniform_sync_armor_from_fueled(inst)
	if inst._reisen_uniform_destroying or inst._reisen_uniform_syncing then
		return
	end
	local armor = inst.components.armor
	local fueled = inst.components.fueled
	if armor == nil or fueled == nil or armor.maxcondition <= 0 or fueled.maxfuel <= 0 then
		return
	end
	inst._reisen_uniform_syncing = true
	armor:SetPercent(fueled:GetPercent())
	inst._reisen_uniform_syncing = false
end

local function uniform_after_time_drain(inst)
	if inst._reisen_uniform_destroying or not inst:IsValid() then
		return
	end
	uniform_sync_armor_from_fueled(inst)
	local owner = inst.components.inventoryitem ~= nil and inst.components.inventoryitem.owner or nil
	if owner ~= nil and owner:IsValid() and owner._reisen_uniform_worn then
		uniform_update_sanity_penalty(inst, owner)
	end
end

local function apply_uniform_stats(inst, owner)
	uniform_update_sanity_penalty(inst, owner)
	owner._reisen_uniform_worn = true
	if owner.prefab ~= "reisen" and owner.components.hunger ~= nil and not owner._reisen_uniform_hunger_applied then
		owner.components.hunger.hungerrate = owner.components.hunger.hungerrate * HUNGER_MULT
		owner._reisen_uniform_hunger_applied = true
	end
	if owner.prefab == "reisen" then
		owner:PushEvent("reisen_stats_dirty")
	end

	-- Recalculate sanity penalty one tick after being attacked so durability
	-- loss from the hit is already reflected.
	if inst._reisen_uniform_attacked_fn == nil then
		inst._reisen_uniform_attacked_fn = function()
			inst:DoTaskInTime(0, function(i)
				if owner ~= nil and owner:IsValid() and owner._reisen_uniform_worn then
					uniform_update_sanity_penalty(i, owner)
				end
			end)
		end
	end
	inst:ListenForEvent("attacked", inst._reisen_uniform_attacked_fn, owner)

	-- Deduct sanity each time the owner lands a hit.
	-- DST pushes "onhitother" to the attacker (combat.lua: attacker:PushEvent("onhitother", ...)).
	if inst._reisen_uniform_onhit_fn == nil then
		inst._reisen_uniform_onhit_fn = function()
			if owner:IsValid() and owner.components.sanity ~= nil then
				local d = uniform_attack_sanity_delta(owner)
				owner.components.sanity:DoDelta(d, false, "reisen_uniform_attack")
			end
		end
	end
	inst:ListenForEvent("onhitother", inst._reisen_uniform_onhit_fn, owner)

	-- Track sanity changes to toggle knockback immunity and walk-speed tier at san = 0.
	if inst._reisen_uniform_sanitydelta_fn == nil then
		inst._reisen_uniform_sanitydelta_fn = function()
			if owner:IsValid() then
				uniform_update_knockback_immune(inst, owner)
				uniform_update_walkspeed(inst, owner)
			end
		end
	end
	inst:ListenForEvent("sanitydelta", inst._reisen_uniform_sanitydelta_fn, owner)

	-- Apply immediately in case sanity is already 0 on equip.
	uniform_update_knockback_immune(inst, owner)
	uniform_update_walkspeed(inst, owner)
end

clear_uniform_stats = function(inst, owner)
	if inst._reisen_uniform_attacked_fn ~= nil then
		inst:RemoveEventCallback("attacked", inst._reisen_uniform_attacked_fn, owner)
		inst._reisen_uniform_attacked_fn = nil
	end
	if inst._reisen_uniform_onhit_fn ~= nil then
		inst:RemoveEventCallback("onhitother", inst._reisen_uniform_onhit_fn, owner)
		inst._reisen_uniform_onhit_fn = nil
	end
	if inst._reisen_uniform_sanitydelta_fn ~= nil then
		inst:RemoveEventCallback("sanitydelta", inst._reisen_uniform_sanitydelta_fn, owner)
		inst._reisen_uniform_sanitydelta_fn = nil
	end
	-- Remove knockback immunity we may have applied (tag lives on inst, not owner).
	if owner._reisen_uniform_knockback_immune then
		inst:RemoveTag("heavyarmor")
		owner._reisen_uniform_knockback_immune = false
	end
	-- Remove the walk-speed bonus applied via SetExternalSpeedMultiplier.
	if owner.components.locomotor ~= nil then
		owner.components.locomotor:RemoveExternalSpeedMultiplier(inst, UNIFORM_SPEED_KEY)
	end
	if owner.components.sanity ~= nil then
		owner.components.sanity:RemoveSanityPenalty(inst)
	end
	owner._reisen_uniform_worn = false
	if owner.prefab ~= "reisen" and owner.components.hunger ~= nil and owner._reisen_uniform_hunger_applied then
		owner.components.hunger.hungerrate = owner.components.hunger.hungerrate / HUNGER_MULT
		owner._reisen_uniform_hunger_applied = nil
	end
	if owner.prefab == "reisen" then
		owner:PushEvent("reisen_stats_dirty")
	end
end

local function onequip(inst, owner)
	local skin_build = inst:GetSkinBuild()
	if skin_build ~= nil then
		owner:PushEvent("equipskinneditem", inst:GetSkinName())
		owner.AnimState:OverrideItemSkinSymbol("swap_body", skin_build, "swap_body", inst.GUID, REISEN_UNIFORM_BUILD)
	else
		owner.AnimState:OverrideSymbol("swap_body", REISEN_UNIFORM_BUILD, "swap_body")
	end

	inst:ListenForEvent("blocked", OnBlocked, owner)
	uniform_sync_fueled_from_armor(inst)
	apply_uniform_stats(inst, owner)
	if inst.components.fueled ~= nil then
		inst.components.fueled:StartConsuming()
	end
end

local function onunequip(inst, owner)
	owner.AnimState:ClearOverrideSymbol("swap_body")
	inst:RemoveEventCallback("blocked", OnBlocked, owner)

	local skin_build = inst:GetSkinBuild()
	if skin_build ~= nil then
		owner:PushEvent("unequipskinneditem", inst:GetSkinName())
	end

	clear_uniform_stats(inst, owner)
	if inst.components.fueled ~= nil then
		inst.components.fueled:StopConsuming()
	end
end

local function fn()
	local inst = CreateEntity()

	inst.entity:AddTransform()
	inst.entity:AddAnimState()
	inst.entity:AddNetwork()

	MakeInventoryPhysics(inst)

	inst.AnimState:SetBank(REISEN_UNIFORM_BUILD)
	inst.AnimState:SetBuild(REISEN_UNIFORM_BUILD)
	inst.AnimState:PlayAnimation("anim")

	inst:AddTag("sanity")
	inst:AddTag("shadow_item")
	inst:AddTag("shadowlevel")

	inst.foleysound = "dontstarve/movement/foley/nightarmour"

	local swap_data = { bank = REISEN_UNIFORM_BUILD, anim = "anim" }
	MakeInventoryFloatable(inst, "small", 0.2, 0.80, nil, nil, swap_data)

	inst.entity:SetPristine()

	if not TheWorld.ismastersim then
		return inst
	end

	inst:AddComponent("inspectable")

	inst:AddComponent("inventoryitem")
	inst.components.inventoryitem.atlasname = "images/inventoryimages/reisen_uniform.xml"

	inst:AddComponent("armor")
	inst.components.armor:InitCondition(REISEN_UNIFORM_CONDITION, REISEN_UNIFORM_ABSORPTION)
	inst.components.armor:SetKeepOnFinished(true)
	inst.components.armor:SetOnFinished(uniform_destroy)

	inst:AddComponent("fueled")
	inst.components.fueled.fueltype = FUELTYPE.USAGE
	inst.components.fueled.no_sewing = true
	inst.components.fueled:InitializeFuelLevel(REISEN_UNIFORM_PERISHTIME)
	inst.components.fueled:SetDepletedFn(uniform_destroy)
	inst.components.fueled:SetUpdateFn(uniform_after_time_drain)

	inst:ListenForEvent("armordamaged", function()
		if inst._reisen_uniform_destroying then
			return
		end
		uniform_sync_fueled_from_armor(inst)
	end)

	inst.OnLoadPostPass = function(i, _newents, _savedata)
		if i.components.armor ~= nil and i.components.fueled ~= nil then
			uniform_sync_fueled_from_armor(i)
		end
	end

	inst:AddComponent("equippable")
	inst.components.equippable.equipslot = EQUIPSLOTS.BODY
	-- Speed bonus is applied dynamically via locomotor:SetExternalSpeedMultiplier
	-- in apply_uniform_stats / uniform_update_walkspeed, so walkspeedmult is not
	-- set here.
	inst.components.equippable:SetOnEquip(onequip)
	inst.components.equippable:SetOnUnequip(onunequip)

	inst:AddComponent("shadowlevel")
	inst.components.shadowlevel:SetDefaultLevel(TUNING.ARMOR_SANITY_SHADOW_LEVEL)

	MakeHauntableLaunch(inst)

	return inst
end

return Prefab("reisen_uniform", fn, assets)
