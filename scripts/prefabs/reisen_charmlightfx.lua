--[[
reisen_charmlightfx — soft purple aura while a Shadow Atrium is socketed
==============================================================================

A minimal light-only entity, parented to the wearer of reisen_charm while a
shadowheart or shadowheart_infused sits in slot 3 of the charm's container.
Radius / intensity / falloff follow reisen_charm.lua (GetEffectiveSanity / sanity.max):


Light colour is a muted cool lilac (all channels present, low chroma): comfortable
on any wearer alone, and blends toward soft periwinkle when stacked with
reisen_ointmentfx’s stronger violet point light.

The entity has no
animation and no Network channel beyond the mandatory Transform/Network pair.

reisen_charm.lua creates this on equip / shadowheart insertion and removes it
on unequip / shadowheart removal / charm depletion.
==============================================================================
--]]

local CHARM_LIGHT_COLOUR = { 150 / 255, 146 / 255, 182 / 255 }
-- Cached on inst: integer index of the last applied stage (0 = off, 1/2/3 = stages).
-- Short-circuits redundant SetRadius/SetIntensity/SetFalloff/Enable calls when
-- sanitydelta fires within the same stage band (mirrors lunatic()'s tier cache).
local function set_stage(inst, stage, stage_idx)
    if inst.Light == nil then return end
    stage_idx = stage_idx or 0
    if inst._stage_idx == stage_idx then return end
    inst._stage_idx = stage_idx
    if stage == nil then
        inst.Light:Enable(false)
        return
    end
    inst.Light:SetRadius(stage.radius)
    inst.Light:SetIntensity(stage.intensity)
    inst.Light:SetFalloff(stage.falloff)
    inst.Light:Enable(true)
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddLight()
    inst.entity:AddNetwork()

    inst.Light:SetColour(CHARM_LIGHT_COLOUR[1], CHARM_LIGHT_COLOUR[2], CHARM_LIGHT_COLOUR[3])
    inst.Light:SetRadius(0)
    inst.Light:SetIntensity(0)
    inst.Light:SetFalloff(1)
    inst.Light:Enable(false)
    inst._stage_idx = 0

    inst:AddTag("FX")
    inst:AddTag("NOCLICK")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.persists = false
    inst.set_stage = set_stage

    return inst
end

return Prefab("reisen_charmlightfx", fn)
