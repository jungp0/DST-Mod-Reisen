local ReisenFX = {}

function ReisenFX.MakeCharmLightFxPrefab()
	local CHARM_LIGHT_COLOUR = { 150 / 255, 146 / 255, 182 / 255 }
	local REISEN_DIM_FACTOR   = 0.2

	local function is_owner_reisen(inst)
		local parent = inst.entity:GetParent()
		return parent ~= nil and parent.prefab == "reisen"
	end

	local function set_stage(inst, stage, stage_idx)
		if inst.Light == nil then return end
		stage_idx = stage_idx or 0
		if inst._stage_idx == stage_idx then return end
		inst._stage_idx = stage_idx
		if stage == nil then
			inst.Light:Enable(false)
			return
		end
		local intensity = is_owner_reisen(inst)
			and (stage.intensity * REISEN_DIM_FACTOR)
			or stage.intensity
		inst.Light:SetRadius(stage.radius)
		inst.Light:SetIntensity(intensity)
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
end

function ReisenFX.MakeOintmentFxPrefab()
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

		inst.AnimState:SetBank("abigail_shield")
		inst.AnimState:SetBuild("abigail_shield")
		inst.AnimState:PlayAnimation("player_shield", false)
		inst.AnimState:SetMultColour(0.35, 0.05, 0.95, 0.95)

		inst.Light:SetRadius(2.0)
		inst.Light:SetIntensity(0.35)
		inst.Light:SetFalloff(0.85)
		inst.Light:SetColour(0.25, 0.0, 0.8)
		inst.Light:Enable(true)

		inst.entity:SetPristine()

		if not TheWorld.ismastersim then
			return inst
		end

		inst.kill_fx = function(i)
			if i ~= nil and i:IsValid() then i:Remove() end
		end

		return inst
	end

	return Prefab("reisen_ointmentfx", fn, assets)
end

function ReisenFX.MakePetalRingPrefab()
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
end

function ReisenFX.MakeBoostFxPrefab()
	local assets =
	{
		Asset("ANIM", "anim/merm_shadow_fx.zip"),
	}

	local BASE_SCALE = 1.0
	local RING_TINTS = {
		{ 0.06, 0.03, 0.18,  1.8,   0.00, 0.00, 0.10 },
		{ 0.58, 0.16, 0.52,  1.6,   0.48, 0.12, 0.40 },
		{ 0.90, 0.68, 0.15,  1.5,   0.80, 0.62, 0.08 },
	}
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

		inst._iskilling     = net_bool(inst.GUID, "reisen_boostfx._iskilling", "killdirty")
		inst._iskilling:set(false)
		inst._crit_progress = net_byte(inst.GUID, "reisen_boostfx._crit_progress", "crit_dirty")
		inst._layer_count   = net_byte(inst.GUID, "reisen_boostfx._layer_count", "layer_dirty")
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
					if client_rings[3] ~= nil then
						if client_rings[3]:IsValid() then client_rings[3]:Remove() end
						client_rings[3] = nil
					end
					for idx = 1, target_count do
						if client_rings[idx] == nil then
							client_rings[idx] = make_ring(idx)
						end
					end
					for idx = target_count + 1, 2 do
						if client_rings[idx] ~= nil then
							if client_rings[idx]:IsValid() then client_rings[idx]:Remove() end
							client_rings[idx] = nil
						end
					end
				end
			end

			inst:ListenForEvent("layer_dirty", function()
				if not inst:IsValid() or inst._iskilling:value() then return end
				sync_client_rings(inst._layer_count:value())
			end)

			inst:ListenForEvent("reisen_boostfx.retrigger_dirty", function()
				if not inst:IsValid() or inst._iskilling:value() then return end
				inst.AnimState:PlayAnimation("buff_pre")
				inst.AnimState:PushAnimation("buff_idle", true)
			end)

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

		inst._last_crit_progress = 0
		inst._crit_update_task   = nil
		inst._crit_start_time    = nil
		inst._crit_ramp_delay    = 5.0
		inst._crit_ramp_time     = 30.0
		inst._progress_bonus     = 0
		inst._milestone_layers   = 0
		inst._crit_max_fired     = false

		local function broadcast_layers(i)
			if i._milestone_layers ~= i._layer_count:value() then
				i._layer_count:set(i._milestone_layers)
			end
		end

		local function compute_progress(i)
			local t_eff = math.max(0, GetTime() - i._crit_start_time - i._crit_ramp_delay)
			local t_span = i._crit_ramp_time - i._crit_ramp_delay
			return math.min(1.0, t_eff / t_span + i._progress_bonus)
		end

		local function sync_progress(i, progress)
			if progress > 0 and i._milestone_layers < 1 then
				i._milestone_layers = 1
				broadcast_layers(i)
			end
			if progress >= 0.5 and i._milestone_layers < 2 then
				i._milestone_layers = 2
				broadcast_layers(i)
			end
			if progress >= 1.0 and not i._crit_max_fired then
				i._crit_max_fired = true
				if i._milestone_layers < 3 then
					i._milestone_layers = 3
					broadcast_layers(i)
				end
				local parent = i.entity:GetParent()
				if parent ~= nil then
					if parent.SoundEmitter ~= nil then
						parent.SoundEmitter:PlaySound("dontstarve/common/nightmareAddFuel")
					end
					i._crit_burst:push()
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
			i._layer_count:set(0)
		end

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
		end

		return inst
	end

	return Prefab("reisen_boostfx", fn, assets)
end

return ReisenFX
