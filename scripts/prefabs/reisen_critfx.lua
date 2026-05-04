--[[
reisen_critfx — Boosted crit-ramp visual indicator
==============================================================================

Shows shadow fire around Reisen while she is in boosted max-stack zone.
Visual intensity scales with actual crit probability:

  Phase 0 (t < RAMP_DELAY = 5 s):
    Barely visible — anim1 at low alpha/scale.
    Crit chance is 0; the faint flame signals "ramp is about to start".

  The effect is always nearly transparent (alpha 0.05 → 0.22) so the
  character is never occluded.  Scale (0.40 → 1.30) is the primary
  intensity cue.

  Phase 1 (progress 0 → 0.35):
    anim1 loop; alpha ~0.05–0.11, scale 0.40–0.56

  Phase 2 (progress 0.35 → 0.70):
    anim2 loop; alpha ~0.11–0.17, scale 0.56–0.72

  Phase 3 (progress 0.70 → 1.0):
    anim3 loop; alpha ~0.17–0.22, scale 0.72–0.85
    Max crit chance reached at progress = 1.0.

Progress is computed linearly from t_eff (= elapsed time since entering max zone
minus RAMP_DELAY).  The actual crit formula uses power-law easing on top of
this same window; the linear visual is simpler to read.

shadow_fire_fx.zip (premult=0):
  - Bank/Build "shadow_fire_fx"
  - anim1 / anim2 / anim3 — three ~1-second shadow-fire loops
  - Deep crimson tint distinguishes this from the purple ointment/petal FX.

No Light component.

Spawned / killed by reisen_update_lunatic_state() when entering / exiting
the boosted max-zone.  crit_start_time, crit_ramp_delay, and crit_ramp_time
must be set on the entity after spawn.  The entity runs its own periodic
update task to keep the visual in sync.
==============================================================================
--]]

local assets =
{
    Asset("ANIM", "anim/shadow_fire_fx.zip"),
}

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    inst.AnimState:SetBank("shadow_fire_fx")
    inst.AnimState:SetBuild("shadow_fire_fx")
    inst.AnimState:PlayAnimation("anim1", true)
    -- Deep crimson, nearly transparent throughout — character must never be blocked.
    inst.AnimState:SetMultColour(0.9, 0.05, 0.0, 0.0)
    inst.Transform:SetScale(0.2, 0.2, 0.2)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    -- Set by caller immediately after spawn.
    inst.crit_start_time = nil
    inst.crit_ramp_delay = 5.0
    inst.crit_ramp_time  = 30.0
    -- Track current anim stage to avoid unnecessary PlayAnimation calls.
    inst._crit_stage     = 0

    local function update(i)
        if i == nil or not i:IsValid() or i.crit_start_time == nil then return end

        local t_total = GetTime() - i.crit_start_time
        local t_eff   = math.max(0, t_total - i.crit_ramp_delay)
        local t_span  = i.crit_ramp_time - i.crit_ramp_delay
        -- Linear progress 0 → 1 over [RAMP_DELAY, crit_ramp_time].
        local progress = math.min(1.0, t_eff / t_span)

        -- Keep nearly transparent throughout so the character is never occluded.
        -- Scale is the primary intensity indicator; alpha just barely shows the shape.
        local alpha = 0.10 + progress * 0.15   -- 0.05 → 0.22
        local scale = 0.15 + progress * 0.20   -- 0.40 → 0.85
        i.AnimState:SetMultColour(0.9, 0.05, 0.0, alpha)
        i.Transform:SetScale(scale, scale, scale)

        -- Advance animation stage as crit ramps up.
        local stage = progress < 0.35 and 1 or progress < 0.70 and 2 or 3
        if i._crit_stage ~= stage then
            i._crit_stage = stage
            local anim = stage == 1 and "anim1" or stage == 2 and "anim2" or "anim3"
            i.AnimState:PlayAnimation(anim, true)
        end
    end

    inst.crit_update_task = inst:DoPeriodicTask(1.0, update)

    inst.kill_fx = function(i)
        if i == nil or not i:IsValid() then return end
        if i.crit_update_task ~= nil then
            i.crit_update_task:Cancel()
            i.crit_update_task = nil
        end
        i:Remove()
    end

    return inst
end

return Prefab("reisen_critfx", fn, assets)
