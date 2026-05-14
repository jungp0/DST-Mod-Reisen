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

BUFF REACTION
    On owner attacked (real attacker required): spawn two nearby gestalts.
    The buff only breaks when the owner is attacked by a gestalt.
    EnableLunacy(false, "reisen_ointment") is called immediately on break.
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
local ReisenFX = require "reisen_fx"

-- 8 real-time minutes
local BUFF_DURATION = 480

local assets =
{
    Asset("ANIM",  "anim/reisen_ointment.zip"),
    Asset("ATLAS", "images/inventoryimages/reisen_ointment.xml"),
    Asset("IMAGE", "images/inventoryimages/reisen_ointment.tex"),
}

local prefabs = { "reisen_ointmentfx", "gestalt" }

-- Source key for EnableLunacy; same convention as vanilla "lunacyhat".
local BUFF_KEY = "reisen_ointment"
local OINTMENT_GESTALT_COUNT = 2
local OINTMENT_GESTALT_MAX_COUNT = 10
local OINTMENT_GESTALT_SPAWN_COOLDOWN = 0.1
local OINTMENT_GESTALT_SPAWN_DIST = 4.5
local OINTMENT_GESTALT_BEHAVIOUR_LEVEL = 3
local OINTMENT_GESTALT_LIFETIME = 20
local OINTMENT_GESTALT_MAX_TARGET_DIST = 25
local OINTMENT_GESTALT_DISTANCE_CHECK_PERIOD = 1

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
local dismiss_ointment_gestalt  -- forward declaration

local function reset_buff_state(owner)
    if owner == nil then return end

    if owner._reisen_ointment_timer ~= nil then
        owner._reisen_ointment_timer:Cancel()
        owner._reisen_ointment_timer = nil
    end

    if owner._reisen_ointment_spawn_cooldown_task ~= nil then
        owner._reisen_ointment_spawn_cooldown_task:Cancel()
        owner._reisen_ointment_spawn_cooldown_task = nil
    end

    if owner._reisen_ointment_attacked_fn ~= nil then
        owner:RemoveEventCallback("attacked", owner._reisen_ointment_attacked_fn)
        owner._reisen_ointment_attacked_fn = nil
    end

    if owner._reisen_ointment_death_fn ~= nil then
        owner:RemoveEventCallback("death", owner._reisen_ointment_death_fn)
        owner._reisen_ointment_death_fn = nil
    end

    if owner._reisen_ointment_ghost_fn ~= nil then
        owner:RemoveEventCallback("ms_becameghost", owner._reisen_ointment_ghost_fn)
        owner._reisen_ointment_ghost_fn = nil
    end

    if owner._reisen_ointment_onremove_fn ~= nil then
        owner:RemoveEventCallback("onremove", owner._reisen_ointment_onremove_fn)
        owner._reisen_ointment_onremove_fn = nil
    end

    if owner._reisen_ointment_gestalts ~= nil then
        local gestalts = owner._reisen_ointment_gestalts
        local skip = owner._reisen_ointment_cleanup_skip
        owner._reisen_ointment_gestalts = nil
        for gestalt in pairs(gestalts) do
            if gestalt ~= nil and gestalt:IsValid() then
                dismiss_ointment_gestalt(gestalt, gestalt == skip)
            end
        end
    end
    owner._reisen_ointment_cleanup_skip = nil

    if owner._reisen_ointment_fx ~= nil then
        if owner._reisen_ointment_fx:IsValid() and owner._reisen_ointment_fx.kill_fx ~= nil then
            owner._reisen_ointment_fx:kill_fx()
        end
        owner._reisen_ointment_fx = nil
    end

end

local kill_buff  -- forward declaration

local function is_gestalt_attacker(attacker)
    return attacker ~= nil
        and attacker:IsValid()
        and (attacker:HasTag("brightmare_gestalt") or attacker:HasTag("brightmare_guard"))
end

local function no_holes(pt)
    return TheWorld ~= nil
        and TheWorld.Map ~= nil
        and not TheWorld.Map:IsPointNearHole(pt)
end

local function is_valid_ointment_owner(owner)
    return owner ~= nil
        and owner:IsValid()
        and not owner:HasTag("playerghost")
        and (owner.components.health == nil or not owner.components.health:IsDead())
end

local function count_ointment_gestalts(owner)
    local count = 0
    local gestalts = owner ~= nil and owner._reisen_ointment_gestalts or nil
    if gestalts ~= nil then
        for gestalt in pairs(gestalts) do
            if gestalt ~= nil and gestalt:IsValid() and not gestalt._reisen_ointment_removing then
                count = count + 1
            else
                gestalts[gestalt] = nil
            end
        end
    end
    return count
end

dismiss_ointment_gestalt = function(gestalt, defer_remove)
    if gestalt == nil or not gestalt:IsValid() or gestalt._reisen_ointment_removing then return end
    gestalt._reisen_ointment_removing = true

    local owner = gestalt._reisen_ointment_target
    if owner ~= nil then
        if owner._reisen_ointment_gestalts ~= nil then
            owner._reisen_ointment_gestalts[gestalt] = nil
        end
        if gestalt._reisen_ointment_owner_remove_fn ~= nil then
            owner:RemoveEventCallback("onremove", gestalt._reisen_ointment_owner_remove_fn, gestalt)
        end
    end
    gestalt._reisen_ointment_owner_remove_fn = nil

    if gestalt._reisen_ointment_lifetime_task ~= nil then
        gestalt._reisen_ointment_lifetime_task:Cancel()
        gestalt._reisen_ointment_lifetime_task = nil
    end
    if gestalt._reisen_ointment_distance_task ~= nil then
        gestalt._reisen_ointment_distance_task:Cancel()
        gestalt._reisen_ointment_distance_task = nil
    end

    gestalt._reisen_ointment_bound = nil
    gestalt._reisen_ointment_target = nil
    if gestalt.SetTrackingTarget ~= nil then
        gestalt:SetTrackingTarget(nil, 0)
    end
    if gestalt.components ~= nil and gestalt.components.combat ~= nil then
        gestalt.components.combat:DropTarget()
    end

    if defer_remove then
        gestalt:DoTaskInTime(0, function(g)
            if g:IsValid() then
                g:Remove()
            end
        end)
    else
        gestalt:Remove()
    end
end

local function track_ointment_gestalt(owner, gestalt)
    owner._reisen_ointment_gestalts = owner._reisen_ointment_gestalts or {}
    owner._reisen_ointment_gestalts[gestalt] = true
    gestalt._reisen_ointment_bound = true
    gestalt._reisen_ointment_target = owner
    gestalt._reisen_ointment_owner_remove_fn = function(g)
        if owner:IsValid() and owner._reisen_ointment_gestalts ~= nil then
            owner._reisen_ointment_gestalts[g] = nil
        end
    end
    owner:ListenForEvent("onremove", gestalt._reisen_ointment_owner_remove_fn, gestalt)

    gestalt._reisen_ointment_lifetime_task = gestalt:DoTaskInTime(OINTMENT_GESTALT_LIFETIME, function(g)
        dismiss_ointment_gestalt(g)
    end)
    gestalt._reisen_ointment_distance_task = gestalt:DoPeriodicTask(OINTMENT_GESTALT_DISTANCE_CHECK_PERIOD, function(g)
        local target = g._reisen_ointment_target
        if not is_valid_ointment_owner(target)
            or not g:IsNear(target, OINTMENT_GESTALT_MAX_TARGET_DIST) then
            dismiss_ointment_gestalt(g)
        end
    end, OINTMENT_GESTALT_DISTANCE_CHECK_PERIOD)
end

local function spawn_ointment_gestalt(owner, angle)
    if not is_valid_ointment_owner(owner) then return end

    local x, y, z = owner.Transform:GetWorldPosition()
    local offset = FindWalkableOffset(
        Vector3(x, y, z),
        angle,
        OINTMENT_GESTALT_SPAWN_DIST,
        8,
        true,
        true,
        no_holes)

    local sx = offset ~= nil and x + offset.x or x + OINTMENT_GESTALT_SPAWN_DIST * math.cos(angle)
    local sz = offset ~= nil and z + offset.z or z - OINTMENT_GESTALT_SPAWN_DIST * math.sin(angle)

    local gestalt = SpawnPrefab("gestalt")
    if gestalt == nil then return end

    track_ointment_gestalt(owner, gestalt)
    gestalt.Transform:SetPosition(sx, 0, sz)
    if gestalt.SetTrackingTarget ~= nil then
        gestalt:SetTrackingTarget(owner, OINTMENT_GESTALT_BEHAVIOUR_LEVEL)
    end
    if gestalt.components ~= nil and gestalt.components.combat ~= nil then
        gestalt.components.combat:SetTarget(owner)
    end
end

local function spawn_ointment_gestalts(owner)
    if not is_valid_ointment_owner(owner) then return end

    local remaining = OINTMENT_GESTALT_MAX_COUNT - count_ointment_gestalts(owner)
    if remaining <= 0 then return end

    local base_angle = math.random() * 2 * math.pi
    for i = 1, math.min(OINTMENT_GESTALT_COUNT, remaining) do
        spawn_ointment_gestalt(owner, base_angle + (i - 1) * math.pi)
    end
end

local function try_spawn_ointment_gestalts(owner)
    if not is_valid_ointment_owner(owner) then return end
    if owner._reisen_ointment_spawn_cooldown_task ~= nil then
        return
    end

    spawn_ointment_gestalts(owner)

    owner._reisen_ointment_spawn_cooldown_task = owner:DoTaskInTime(OINTMENT_GESTALT_SPAWN_COOLDOWN, function(o)
        o._reisen_ointment_spawn_cooldown_task = nil
    end)
end

-- Full teardown: cleans state AND restores normal SANITY_MODE_INSANITY.
-- Only called on genuine buff expiry (hit / death / natural timeout).
kill_buff = function(owner)
    if owner == nil then return end
    reset_buff_state(owner)
    -- Removes "reisen_ointment" from SourceModifierList.
    -- If other lunacy sources ("lunacyarea", "lunacyhat", …) are still
    -- present the modifier stays true → mode stays LUNACY.
    -- UpdateMode_Internal only fires DoDelta(0) when the mode actually changes.
    if owner:IsValid() then
        ointment_set_lunacy(owner, false)
    end
end

local function on_owner_attacked(owner, data)
    if data == nil or data.attacker == nil or not data.attacker:IsValid() then return end
    if not is_valid_ointment_owner(owner) then return end
    if owner.sg ~= nil and owner.sg:HasStateTag("dead") then return end

    if is_gestalt_attacker(data.attacker) then
        owner._reisen_ointment_cleanup_skip = data.attacker
        kill_buff(owner)
        return
    end

    try_spawn_ointment_gestalts(owner)
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

    owner._reisen_ointment_ghost_fn = function()
        kill_buff(owner)
    end
    owner:ListenForEvent("ms_becameghost", owner._reisen_ointment_ghost_fn)

    owner._reisen_ointment_onremove_fn = function()
        kill_buff(owner)
    end
    owner:ListenForEvent("onremove", owner._reisen_ointment_onremove_fn)
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

return Prefab("reisen_ointment", fn, assets, prefabs),
    ReisenFX.MakeOintmentFxPrefab()
