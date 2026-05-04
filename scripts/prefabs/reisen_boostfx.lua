--[[
reisen_boostfx — Reisen boosted-state persistent shadow aura
==============================================================================

Uses merm_shadow_fx.zip (premult=0).
Animations: buff_pre (one-shot lead-in) → buff_idle (loop) → buff_pst (close).

No Light component: the aura is a visual-only shadow effect.

LIFECYCLE:
  Spawned by reisen_spawn_boost_fx() when Reisen enters the boosted state.
  Parented to the player entity so it follows movement automatically.
  Killed by reisen_exit_boost_state() via kill_fx() which plays buff_pst
  before removing (close animation synced to clients via _iskilling net_bool).
==============================================================================
--]]

local assets =
{
    Asset("ANIM", "anim/merm_shadow_fx.zip"),
}

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    inst.AnimState:SetBank("merm_shadow_fx")
    inst.AnimState:SetBuild("merm_shadow_fx")
    inst.AnimState:PlayAnimation("buff_pre")
    inst.AnimState:PushAnimation("buff_idle", true)

    -- Net flag toggled server-side when kill_fx() is called.
    -- Clients watch "killdirty" to play buff_pst then self-remove.
    inst._iskilling = net_bool(inst.GUID, "reisen_boostfx._iskilling", "killdirty")
    inst._iskilling:set(false)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        inst:ListenForEvent("killdirty", function()
            if inst._iskilling:value() and inst:IsValid() then
                inst.AnimState:PlayAnimation("buff_pst")
                inst:DoTaskInTime(0.5, function(i)
                    if i ~= nil and i:IsValid() then i:Remove() end
                end)
            end
        end)
        return inst
    end

    inst.kill_fx = function(i)
        if i == nil or not i:IsValid() then return end
        i._iskilling:set(true)
        i.AnimState:PlayAnimation("buff_pst")
        i:DoTaskInTime(0.5, function(fx)
            if fx ~= nil and fx:IsValid() then fx:Remove() end
        end)
    end

    return inst
end

return Prefab("reisen_boostfx", fn, assets)
