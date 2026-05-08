--[[
reisen_boostfx — Reisen boosted-state persistent shadow aura with crit ramp
==============================================================================

Uses merm_shadow_fx.zip (premult=0).
Animations: buff_pre (one-shot lead-in) → buff_idle (loop) → buff_pst (close).

LAYER SYSTEM (3 total visible layers):
  inst (main aura): always present, fixed natural color/scale, unaffected by progress.
  ring 1 (innermost): deep purple-black (follow texture hue). Spawns when crit starts.
  ring 2 (middle):    deep wine red. Spawns at progress 50%.
  ring 3:             dark gold. At 100%, replaces rings 1+2; fires
                      together with the gold burst net_event.

  Server tracks _milestone_layers (0–3) broadcast via _layer_count net_byte.
  Client creates/removes local ring entities on layer_dirty.

LIFECYCLE:
  reisen_spawn_boost_fx() spawns this when entering boost.
  Server calls start_crit_ramp / stop_crit_ramp as lunatic zone changes.
  Server calls retrigger() when boost is re-triggered while already boosted.
  reisen_exit_boost_state() calls kill_fx() to dismiss.
==============================================================================
--]]

local assets =
{
    Asset("ANIM", "anim/merm_shadow_fx.zip"),
}

local BASE_SCALE = 1.0

-- 3 inner rings driven purely by time milestones.
local MAX_INNER_RINGS = 3

-- Per ring: mult_r, mult_g, mult_b, mult_a, add_r, add_g, add_b
-- Stronger contrast between layers for clear visual progression.
local RING_TINTS = {
    { 0.06, 0.03, 0.18,  1.8,   0.00, 0.00, 0.10 },  -- ring 1: near-black purple (darkest)
    { 0.58, 0.16, 0.52,  1.6,   0.48, 0.12, 0.40 },  -- ring 2: pink-magenta / 紫红色
    { 0.90, 0.68, 0.15,  1.5,   0.80, 0.62, 0.08 },  -- ring 3: bright gold (lightest)
}

-- Scale progression: 0.42 (inner) → 0.68 (middle) → 1.0 (main aura)
-- Ring 3 (dark gold) replaces rings 1+2 at max, sits at 0.58 inside the main aura
local RING_SCALES = { 0.42, 0.68, 0.58 }

local function get_ring_def(n)
    local t = RING_TINTS[n] or RING_TINTS[#RING_TINTS]
    return {
        scale  = RING_SCALES[n] or 0.42,
        mult_r = t[1], mult_g = t[2], mult_b = t[3], mult_a = t[4],
        add_r  = t[5], add_g  = t[6], add_b  = t[7],
    }
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    inst.AnimState:SetBank("merm_shadow_fx")
    inst.AnimState:SetBuild("merm_shadow_fx")
    inst.AnimState:PlayAnimation("buff_pre")
    inst.AnimState:PushAnimation("buff_idle", true)
    inst.Transform:SetScale(BASE_SCALE, BASE_SCALE, BASE_SCALE)

    -- Net vars: kill signal, crit progress, total layer count, retrigger, crit-max gold burst
    inst._iskilling     = net_bool(inst.GUID, "reisen_boostfx._iskilling",   "killdirty")
    inst._iskilling:set(false)
    inst._crit_progress = net_byte(inst.GUID, "reisen_boostfx._crit_progress", "crit_dirty")
    inst._layer_count   = net_byte(inst.GUID, "reisen_boostfx._layer_count",   "layer_dirty")
    inst._retrigger     = net_event(inst.GUID, "reisen_boostfx.retrigger_dirty")
    inst._crit_burst    = net_event(inst.GUID, "reisen_boostfx.crit_burst_dirty")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        local client_rings = {}

        local function make_ring(idx)
            local def = get_ring_def(idx)
            local ring = CreateEntity()
            ring.entity:AddTransform()
            ring.entity:AddAnimState()
            ring.AnimState:SetBank("merm_shadow_fx")
            ring.AnimState:SetBuild("merm_shadow_fx")
            ring.AnimState:PlayAnimation("buff_idle", true)
            ring.AnimState:SetMultColour(def.mult_r, def.mult_g, def.mult_b, def.mult_a)
            ring.AnimState:SetAddColour(def.add_r, def.add_g, def.add_b, 0)
            ring.Transform:SetScale(def.scale, def.scale, def.scale)
            ring.entity:SetParent(inst.entity)
            ring.Transform:SetPosition(0, 0, 0)
            ring:AddTag("FX")
            ring:AddTag("NOCLICK")
            return ring
        end

        local function sync_client_rings(target_count)
            if target_count >= 3 then
                -- At max crit: replace rings 1+2 with the single outer gold ring (ring 3)
                for idx = 1, 2 do
                    if client_rings[idx] ~= nil then
                        if client_rings[idx]:IsValid() then client_rings[idx]:Remove() end
                        client_rings[idx] = nil
                    end
                end
                if client_rings[3] == nil then
                    client_rings[3] = make_ring(3)
                end
            else
                -- Below max: show only rings 1 and 2 as earned; ensure ring 3 is absent
                if client_rings[3] ~= nil then
                    if client_rings[3]:IsValid() then client_rings[3]:Remove() end
                    client_rings[3] = nil
                end
                for idx = 1, target_count do
                    if client_rings[idx] == nil then
                        client_rings[idx] = make_ring(idx)
                    end
                end
                -- Remove rings beyond target (e.g. after stop_crit_ramp resets)
                for idx = target_count + 1, 2 do
                    if client_rings[idx] ~= nil then
                        if client_rings[idx]:IsValid() then client_rings[idx]:Remove() end
                        client_rings[idx] = nil
                    end
                end
            end
        end

        -- Main aura color/scale is fixed; crit_dirty only needed for server-side milestone logic.
        -- No client visual update on progress change.

        inst:ListenForEvent("layer_dirty", function()
            if not inst:IsValid() or inst._iskilling:value() then return end
            sync_client_rings(inst._layer_count:value())
        end)

        -- Retrigger: replay entry animation (same visual as initial boost entry)
        inst:ListenForEvent("reisen_boostfx.retrigger_dirty", function()
            if not inst:IsValid() or inst._iskilling:value() then return end
            inst.AnimState:PlayAnimation("buff_pre")
            inst.AnimState:PushAnimation("buff_idle", true)
        end)

        -- Crit-max gold burst: client-local one-shot FX
        inst:ListenForEvent("reisen_boostfx.crit_burst_dirty", function()
            if not inst:IsValid() then return end
            local parent = inst.entity:GetParent()
            local px, py, pz
            if parent ~= nil then
                px, py, pz = parent.Transform:GetWorldPosition()
            else
                px, py, pz = inst.Transform:GetWorldPosition()
            end
            local burst = CreateEntity()
            burst.entity:AddTransform()
            burst.entity:AddAnimState()
            burst.AnimState:SetBank("merm_shadow_fx")
            burst.AnimState:SetBuild("merm_shadow_fx")
            burst.AnimState:PlayAnimation("buff_pre")
            -- SetAddColour adds color on top of texture, making it glow gold
            burst.AnimState:SetMultColour(1, 1, 1, 1)
            burst.AnimState:SetAddColour(1.0, 0.75, 0.1, 0)
            burst.Transform:SetScale(2.0, 2.0, 2.0)
            burst.Transform:SetPosition(px, py, pz)
            burst:AddTag("FX")
            burst:AddTag("NOCLICK")
            burst:ListenForEvent("animover", function(b)
                if b ~= nil and b:IsValid() then b:Remove() end
            end)
        end)

        inst:ListenForEvent("killdirty", function()
            if inst._iskilling:value() and inst:IsValid() then
                sync_client_rings(0)
                inst.AnimState:PlayAnimation("buff_pst")
                inst:DoTaskInTime(0.5, function(i)
                    if i ~= nil and i:IsValid() then i:Remove() end
                end)
            end
        end)
        return inst
    end

    -- ── Server state ────────────────────────────────────────────────────────

    inst._last_crit_progress = 0
    inst._crit_update_task   = nil
    inst._crit_start_time    = nil
    inst._crit_ramp_delay    = 5.0
    inst._crit_ramp_time     = 30.0
    inst._progress_bonus     = 0   -- colour/scale ramp offset from retriggers
    inst._milestone_layers   = 0   -- layers driven solely by time milestones (0, 1, or 2)
    inst._crit_max_fired     = false  -- ensures crit-max FX fires only once per ramp

    local function broadcast_layers(i)
        if i._milestone_layers ~= i._layer_count:value() then
            i._layer_count:set(i._milestone_layers)
        end
    end

    local function compute_progress(i)
        local t_eff  = math.max(0, GetTime() - i._crit_start_time - i._crit_ramp_delay)
        local t_span = i._crit_ramp_time - i._crit_ramp_delay
        return math.min(1.0, t_eff / t_span + i._progress_bonus)
    end

    -- Fire time-based milestone layers from progress.
    -- _crit_progress netvar is intentionally not :set() here -- clients do not
    -- listen for crit_dirty (see comment in client section), so broadcasting it
    -- every tick was pure idle bandwidth (~25-30 dirties per ramp). The netvar
    -- declaration is kept for backward-compat of the entity's netvar layout.
    local function sync_progress(i, progress)
        -- Milestone 1: innermost ring appears when crit starts (progress > 0)
        if progress > 0 and i._milestone_layers < 1 then
            i._milestone_layers = 1
            broadcast_layers(i)
        end

        -- Milestone 2: middle ring appears at 50%
        if progress >= 0.5 and i._milestone_layers < 2 then
            i._milestone_layers = 2
            broadcast_layers(i)
        end

        -- Milestone 3: outer gold ring fires with crit_burst at 100%
        -- (layer broadcast happens inside the crit_max block below)

        -- Crit max FX: outer gold ring + sound + burst + talker (fires once at 100%)
        if progress >= 1.0 and not i._crit_max_fired then
            i._crit_max_fired = true
            -- Outer gold ring (ring 3) appears together with burst
            if i._milestone_layers < 3 then
                i._milestone_layers = 3
                broadcast_layers(i)
            end
            local parent = i.entity:GetParent()
            if parent ~= nil then
                if parent.SoundEmitter ~= nil then
                    parent.SoundEmitter:PlaySound("dontstarve/common/nightmareAddFuel")
                end
                -- Notify clients to spawn the gold burst locally
                i._crit_burst:push()
                -- Talker speech with delay (server-side talker component)
                local _parent = parent
                local _say = (STRINGS.CHARACTERS
                    and STRINGS.CHARACTERS.REISEN
                    and STRINGS.CHARACTERS.REISEN.ANNOUNCE_REISEN_CRIT_MAX)
                    or STRINGS.REISEN_CRIT_MAX_SAY
                    or "Blade unsheathed!"
                i:DoTaskInTime(0.5, function()
                    if _parent ~= nil and _parent:IsValid()
                            and _parent.components.talker ~= nil then
                        _parent.components.talker:Say(_say, 2.5)
                    end
                end)
            end
            if i._crit_update_task ~= nil then
                i._crit_update_task:Cancel()
                i._crit_update_task = nil
            end
        end
    end

    local function crit_update_tick(i)
        if i == nil or not i:IsValid() or i._crit_start_time == nil then return end
        sync_progress(i, compute_progress(i))
    end

    -- Called by reisen.lua when entering the high-stack lunatic zone
    inst.start_crit_ramp = function(i, ramp_delay, ramp_time)
        if i == nil or not i:IsValid() then return end
        i._crit_start_time  = GetTime()
        i._crit_ramp_delay  = ramp_delay or 5.0
        i._crit_ramp_time   = ramp_time or 30.0
        i._progress_bonus   = 0
        i._milestone_layers = 0
        i._crit_max_fired   = false
        if i._crit_update_task ~= nil then
            i._crit_update_task:Cancel()
        end
        i._crit_update_task = i:DoPeriodicTask(1.0, crit_update_tick)
        crit_update_tick(i)
    end

    -- Called by reisen.lua when leaving the high-stack zone (still boosted)
    inst.stop_crit_ramp = function(i)
        if i == nil or not i:IsValid() then return end
        if i._crit_update_task ~= nil then
            i._crit_update_task:Cancel()
            i._crit_update_task = nil
        end
        i._crit_start_time    = nil
        i._last_crit_progress = 0
        i._progress_bonus     = 0
        i._milestone_layers   = 0
        i._crit_max_fired     = false
        i._layer_count:set(0)    -- layer_dirty → client removes all rings
    end

    -- Called by reisen.lua when boost is re-triggered while already boosted.
    -- Plays entry animation on client and advances progress_bonus for colour/scale ramp.
    -- Does NOT add extra rings; layers are driven solely by milestones.
    inst.retrigger = function(i)
        if i == nil or not i:IsValid() then return end
        i._retrigger:push()
        i._progress_bonus = math.min(1.0, (i._progress_bonus or 0) + 0.5)
        if i._crit_start_time ~= nil then
            sync_progress(i, compute_progress(i))
        else
            sync_progress(i, math.min(1.0, i._progress_bonus))
        end
    end

    inst.kill_fx = function(i)
        if i == nil or not i:IsValid() then return end
        if i._crit_update_task ~= nil then
            i._crit_update_task:Cancel()
            i._crit_update_task = nil
        end
        i._layer_count:set(0)
        i._iskilling:set(true)
        -- Client handles buff_pst + Remove() via killdirty
    end

    return inst
end

return Prefab("reisen_boostfx", fn, assets)
