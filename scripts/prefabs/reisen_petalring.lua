--[[
reisen_petalring — Evil Petal buff ground shadow rune
==============================================================================

Shown while the petal buff (_reisen_petal_buff) is active after Reisen
eats petals_evil / petals_evil_dried / hermitcrabtea_petals_evil.
Disappears (via kill_fx) when the buff is cancelled — either by a direct
attack hit or when the extended decay timer naturally fires.

shadow_trap_debuff.zip (premult=0):
  - Bank/Build "shadow_trap_debuff"
  - "debuff_pre_small"  : one-shot lead-in rune-circle appearance
  - "debuff_loop_small" : looping shadow rune that persists during the buff

Spawned by reisen_evil_petals_stack_gain() in reisen.lua.
Parented to the owner entity so it follows movement automatically.
Removed via kill_fx() when the petal buff ends.
==============================================================================
--]]

local assets =
{
    Asset("ANIM", "anim/shadow_trap_debuff.zip"),
}

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    inst.AnimState:SetBank("shadow_trap_debuff")
    inst.AnimState:SetBuild("shadow_trap_debuff")
    inst.AnimState:PlayAnimation("debuff_pre_small")
    inst.AnimState:PushAnimation("debuff_loop_small", true)
    -- Dark purple tint; premult=0 makes SetMultColour fully effective.
    inst.AnimState:SetMultColour(0.3, 0.0, 0.85, 0.9)
    inst.Transform:SetScale(0.65, 0.65, 0.65)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.kill_fx = function(i)
        if i ~= nil and i:IsValid() then i:Remove() end
    end

    return inst
end

return Prefab("reisen_petalring", fn, assets)
