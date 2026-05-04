--[[
==============================================================================
reisen_ointment  —  Dark Moon Salve (consumable)
==============================================================================

OVERVIEW
    Single-use consumable crafted by Reisen. Applies healing and a
    shadow-attuned buff that prevents going insane for a fixed duration.

USE EFFECTS (immediate)
    HP      : +50
    Sanity  : -25  (shadow attunement cost)

BUFF  ("dark petal ward")
    Duration  : 12 real-time minutes (720 s)
    Effect    : switches owner to SANITY_MODE_LUNACY (Enlightenment mode) via
                sanity:EnableLunacy(true, "reisen_ointment").
                In LUNACY mode, IsInsane() always returns false, so shadow
                creatures never attack regardless of sanity value.
                Sanity still drains normally; the HUD shows the real value
                (unlike SetInducedLunacy, EnableLunacy does NOT set inducedlunacy,
                so _replica_setcurrent displays sanity.current correctly).
                — Overrides reisen_charm's force-sane=false: in LUNACY mode
                  sane=false means "enlightened", not "insane"; IsInsane()
                  stays false so GoInsane never fires.
                — Same API pattern as vanilla lunacyhat ("lunacyhat" source key).
    Visual    : forcefieldfx (ruinshat-style shield sphere) parented to owner
    Sound     : forcefieldfx loop "dontstarve/wilson/forcefield_LP"
    Use sound : "dontstarve/wilson/eat"

BUFF BREAK
    On owner attacked (real attacker required): the forcefieldfx plays its
    "hit" animation, then is closed via kill_fx() after 0.5 s.
    EnableLunacy(false, "reisen_ointment") is called immediately on hit.
    The buff also breaks on owner death.

RECIPE (Reisen only, Shadow Manipulator)
    8x spidergland  +  4x silk  +  2x petals_evil
    Tab: RESTORATION + MAGIC

TECH: MAGIC_TWO (Shadow Manipulator)

ANIM
    Bank : reisenointment   (bandage-compatible atlas)
    Build: reisen_ointment
    Anim : idle
==============================================================================
--]]

local OINTMENT_BANK  = "reisenointment"
local OINTMENT_BUILD = "reisen_ointment"

-- 4 real-time minutes
local BUFF_DURATION = 480

local assets =
{
    Asset("ANIM",  "anim/reisen_ointment.zip"),
    Asset("ATLAS", "images/inventoryimages/reisen_ointment.xml"),
    Asset("IMAGE", "images/inventoryimages/reisen_ointment.tex"),
}

local prefabs = { "reisen_ointmentfx" }

-- Source key for EnableLunacy; same convention as vanilla "lunacyhat".
local BUFF_KEY = "reisen_ointment"

--------------------------------------------------------------------------
-- Enlightenment mode toggle via EnableLunacy
--
-- sanity:EnableLunacy(true, BUFF_KEY) switches mode to SANITY_MODE_LUNACY.
-- In that mode IsInsane() is always false regardless of sanity.current,
-- so shadow creatures never become aggressive and goinsane never fires.
-- The HUD shows the actual current sanity value because inducedlunacy is
-- NOT set — avoiding the display bug that SetInducedLunacy would cause.
-- EnableLunacy uses SourceModifierList internally; removing BUFF_KEY only
-- removes this buff's entry; other lunacy sources are unaffected.
--------------------------------------------------------------------------

local function ointment_set_lunacy(owner, val)
    local s = owner.components.sanity
    if s ~= nil and s.EnableLunacy ~= nil then
        s:EnableLunacy(val, BUFF_KEY)
    end
end

--------------------------------------------------------------------------
-- Buff lifecycle
--------------------------------------------------------------------------

-- Cancels the active timer, event listeners, and FX without touching the
-- lunacy mode.  Called by both apply_buff (refresh) and kill_buff (end).
local function reset_buff_state(owner)
    if owner == nil or not owner:IsValid() then return end

    if owner._reisen_ointment_timer ~= nil then
        owner._reisen_ointment_timer:Cancel()
        owner._reisen_ointment_timer = nil
    end

    if owner._reisen_ointment_attacked_fn ~= nil then
        owner:RemoveEventCallback("attacked", owner._reisen_ointment_attacked_fn)
        owner._reisen_ointment_attacked_fn = nil
    end

    if owner._reisen_ointment_death_fn ~= nil then
        owner:RemoveEventCallback("death", owner._reisen_ointment_death_fn)
        owner._reisen_ointment_death_fn = nil
    end

    if owner._reisen_ointment_fx ~= nil then
        if owner._reisen_ointment_fx:IsValid() and owner._reisen_ointment_fx.kill_fx ~= nil then
            owner._reisen_ointment_fx:kill_fx()
        end
        owner._reisen_ointment_fx = nil
    end

end

local kill_buff  -- forward declaration

-- Full teardown: cleans state AND restores normal SANITY_MODE_INSANITY.
-- Only called on genuine buff expiry (hit / death / natural timeout).
kill_buff = function(owner)
    reset_buff_state(owner)
    -- Removes "reisen_ointment" from SourceModifierList.
    -- If other lunacy sources ("lunacyarea", "lunacyhat", …) are still
    -- present the modifier stays true → mode stays LUNACY.
    -- UpdateMode_Internal only fires DoDelta(0) when the mode actually changes.
    ointment_set_lunacy(owner, false)
end

local function on_owner_attacked(owner, data)
    if data == nil or data.attacker == nil or not data.attacker:IsValid() then return end
    if owner.sg ~= nil and owner.sg:HasStateTag("dead") then return end

    -- kill_buff handles the fx via kill_fx(), which plays buff_pst close
    -- animation synced to clients via the _iskilling net_bool.
    kill_buff(owner)
end

local function apply_buff(owner)
    -- Reset state without touching lunacy mode.
    -- If the buff is already active ("reisen_ointment" source already in the
    -- SourceModifierList), EnableLunacy(true) below is a pure no-op (same key,
    -- same value → RecalculateModifier is skipped).  This avoids the
    -- LUNACY→INSANITY→LUNACY flicker that would happen if kill_buff were used.
    reset_buff_state(owner)

    -- Enter SANITY_MODE_LUNACY: IsInsane() always false, HUD shows real value.
    -- No-op when mode is already LUNACY from any source (moon island, hat, etc.)
    -- because UpdateMode_Internal guards with self.mode ~= mode.
    ointment_set_lunacy(owner, true)

    -- Purple shield dome.
    local fx = SpawnPrefab("reisen_ointmentfx")
    if fx ~= nil then
        fx.entity:SetParent(owner.entity)
        fx.Transform:SetPosition(0, 0.2, 0)
        owner._reisen_ointment_fx = fx
    end

    -- Expiry timer
    owner._reisen_ointment_timer = owner:DoTaskInTime(BUFF_DURATION, function()
        kill_buff(owner)
    end)

    -- Break on hit
    owner._reisen_ointment_attacked_fn = function(o, data)
        on_owner_attacked(o, data)
    end
    owner:ListenForEvent("attacked", owner._reisen_ointment_attacked_fn)

    -- Break on death (clean up; immunity restored even if the player ghosts)
    owner._reisen_ointment_death_fn = function()
        kill_buff(owner)
    end
    owner:ListenForEvent("death", owner._reisen_ointment_death_fn)
end

--------------------------------------------------------------------------
-- Healer callback  —  called after HP delta is applied
-- Signature: fn(item, target, doer)
--------------------------------------------------------------------------

local function on_healed(inst, target, doer)
    -- Sanity cost to the target (shadow attunement price)
    if target.components.sanity ~= nil then
        target.components.sanity:DoDelta(-25, false, inst.prefab)
    end

    -- Switch to Enlightenment mode and start the buff
    apply_buff(target)
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

    inst.AnimState:SetBank(OINTMENT_BANK)
    inst.AnimState:SetBuild(OINTMENT_BUILD)
    inst.AnimState:PlayAnimation("idle")

    MakeInventoryFloatable(inst, "small", 0.05, 0.95)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("stackable")
    inst.components.stackable.maxsize = 10

    inst:AddComponent("inspectable")

    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem.atlasname = "images/inventoryimages/reisen_ointment.xml"

    inst:AddComponent("healer")
    inst.components.healer:SetHealthAmount(50)
    inst.components.healer:SetOnHealFn(on_healed)

    MakeHauntableLaunch(inst)

    return inst
end

return Prefab("reisen_ointment", fn, assets, prefabs)
