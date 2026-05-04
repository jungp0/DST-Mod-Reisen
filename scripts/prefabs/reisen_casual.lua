--[[
==============================================================================
reisen_casual  —  Reisen's Casual Outfit (BODY slot)
==============================================================================

OVERVIEW
    A lightweight grass-material armor. Provides modest physical protection
    and a conditional sanity bonus when the wearer's hunger is high. No
    hunger or night-drain side effects. Can be used as fuel and is flammable.

STATS
    Condition (durability) : 300
    Absorption             : 0.75  (75%)
    Weakness               : takes extra damage from Woodie (beaver) attacks
    Fuel value             : LARGE_FUEL  (burnable as fire fuel)
    Burn time              : SMALL_BURNTIME
    Warm insulation        : 60  (warmth only, no heat protection; insulator component)

SANITY (dapperness)
    Conditional via dapperfn — checked each tick by the sanity component:
      - Hunger >= HUNGER_HIGH (75%) of max : +DAPPERNESS_MED × 0.85  (small passive gain)
      - Hunger  < HUNGER_HIGH (75%) of max : 0  (no bonus)
    No penalty is applied; purely a positive or neutral effect.

REISEN INTERACTION
    On equip and unequip fires reisen_stats_dirty so lunatic() can account
    for the vulnerability absorb-relief this armor provides (cap: 0.5).
    Does NOT set _reisen_uniform_worn; that flag is exclusive to reisen_uniform.

EVENTS LISTENED (while equipped)
    "blocked" on owner → plays standard armor-block sound

TAGS ADDED TO ITEM
    "grass"
==============================================================================
--]]

local ReisenConsts = require "reisen_consts"

local REISEN_CASUAL_BUILD = "reisen_casual"

local assets =
{
	Asset("ANIM", "anim/reisen_casual.zip"),
	Asset("ATLAS", "images/inventoryimages/reisen_casual.xml"),
	Asset("IMAGE", "images/inventoryimages/reisen_casual.tex"),
}

local REISEN_CASUAL_ABSORPTION = 0.75
local REISEN_CASUAL_CONDITION = 300
local REISEN_CASUAL_INSULATION = 60

local function casual_dapperfn(inst, owner)
	if owner.components.hunger ~= nil and owner.components.hunger.current >= ReisenConsts.HUNGER_HIGH * owner.components.hunger.max then
		return TUNING.DAPPERNESS_MED * 0.85
	end
	return 0
end

local function OnBlocked(owner)
	owner.SoundEmitter:PlaySound("dontstarve/wilson/hit_armour")
end

local function onequip(inst, owner)
	local skin_build = inst:GetSkinBuild()
	if skin_build ~= nil then
		owner:PushEvent("equipskinneditem", inst:GetSkinName())
		owner.AnimState:OverrideItemSkinSymbol("swap_body", skin_build, "swap_body", inst.GUID, REISEN_CASUAL_BUILD)
	else
		owner.AnimState:OverrideSymbol("swap_body", REISEN_CASUAL_BUILD, "swap_body")
	end

	inst:ListenForEvent("blocked", OnBlocked, owner)

	if owner.prefab == "reisen" then
		owner:PushEvent("reisen_stats_dirty")
	end
end

local function onunequip(inst, owner)
	owner.AnimState:ClearOverrideSymbol("swap_body")
	inst:RemoveEventCallback("blocked", OnBlocked, owner)

	local skin_build = inst:GetSkinBuild()
	if skin_build ~= nil then
		owner:PushEvent("unequipskinneditem", inst:GetSkinName())
	end

	if owner.prefab == "reisen" then
		owner:PushEvent("reisen_stats_dirty")
	end
end

local function fn()
	local inst = CreateEntity()

	inst.entity:AddTransform()
	inst.entity:AddAnimState()
	inst.entity:AddNetwork()

	MakeInventoryPhysics(inst)

	inst.AnimState:SetBank(REISEN_CASUAL_BUILD)
	inst.AnimState:SetBuild(REISEN_CASUAL_BUILD)
	inst.AnimState:PlayAnimation("anim")

	inst:AddTag("grass")

	inst.foleysound = "dontstarve/movement/foley/grassarmour"

	local swap_data = { bank = REISEN_CASUAL_BUILD, anim = "anim" }
	MakeInventoryFloatable(inst, "small", 0.2, 0.80, nil, nil, swap_data)

	inst.entity:SetPristine()

	if not TheWorld.ismastersim then
		return inst
	end

	inst:AddComponent("inspectable")

	inst:AddComponent("inventoryitem")
	inst.components.inventoryitem.atlasname = "images/inventoryimages/reisen_casual.xml"

	inst:AddComponent("fuel")
	inst.components.fuel.fuelvalue = TUNING.LARGE_FUEL

	MakeSmallBurnable(inst, TUNING.SMALL_BURNTIME)
	MakeSmallPropagator(inst)

	inst:AddComponent("armor")
	inst.components.armor:InitCondition(REISEN_CASUAL_CONDITION, REISEN_CASUAL_ABSORPTION)
	inst.components.armor:AddWeakness("beaver", TUNING.BEAVER_WOOD_DAMAGE)

	inst:AddComponent("insulator")
	inst.components.insulator:SetInsulation(REISEN_CASUAL_INSULATION)

	inst:AddComponent("equippable")
	inst.components.equippable.equipslot = EQUIPSLOTS.BODY
	inst.components.equippable.dapperfn = casual_dapperfn
	inst.components.equippable:SetOnEquip(onequip)
	inst.components.equippable:SetOnUnequip(onunequip)

	MakeHauntableLaunch(inst)

	return inst
end

return Prefab("reisen_casual", fn, assets)
