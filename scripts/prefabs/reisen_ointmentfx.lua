--[[
reisen_ointmentfx — Dark Moon Salve buff visual
==============================================================================

LAYERS
  1. Main entity (inst)  — abigail_shield "player_shield" dome (premult=0)
       Purple tint via SetMultColour; plays once on application.
  2. reisen_ointmentring — shadow_trap_debuff ground rune circle
       Spawned and tracked separately by reisen_ointment.lua apply_buff /
       reset_buff_state; loops for the full buff duration.
  3. Light               — subtle purple point-light on inst.

WHY abigail_shield.zip:
  - KTEX premult=0  →  SetMultColour works correctly.
  - "player_shield" animation is the looping dome overlay for the player.
  - "shield_buff" was used previously but "player_shield" gives a better
    single-shot flash on application.

WHY shadow_trap_debuff.zip:
  - KTEX premult=0  →  SetMultColour works correctly.
  - Bank/Build "shadow_trap_debuff".
  - "debuff_pre_small" (one-shot lead-in) → "debuff_loop_small" (loop):
    a circular shadow rune pattern at the player's feet, giving a clear
    "dark magic ward" aesthetic that complements the dome above.

KILL:
  kill_fx() removes inst.  The ring child entity is removed automatically
  by the DST entity hierarchy (children are removed with their parent).
==============================================================================
--]]

local assets =
{
    Asset("ANIM", "anim/abigail_shield.zip"),
}

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddLight()
    inst.entity:AddNetwork()

    -- Main dome: abigail shield tinted to deep purple.
    inst.AnimState:SetBank("abigail_shield")
    inst.AnimState:SetBuild("abigail_shield")
    inst.AnimState:PlayAnimation("player_shield", false)
    inst.AnimState:SetMultColour(0.35, 0.05, 0.95, 0.95)

    -- Subtle purple ambient point-light for atmosphere.
    inst.Light:SetRadius(2.0)
    inst.Light:SetIntensity(0.35)
    inst.Light:SetFalloff(0.85)
    inst.Light:SetColour(0.25, 0.0, 0.8)
    inst.Light:Enable(true)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    -- Instant removal; reisen_ointmentring is tracked and cleaned separately
    -- by reset_buff_state() in reisen_ointment.lua.
    inst.kill_fx = function(i)
        if i ~= nil and i:IsValid() then i:Remove() end
    end

    return inst
end

return Prefab("reisen_ointmentfx", fn, assets)
