PrefabFiles = {

	"reisen",
	"reisen_none",
	"reisen_casual",
	"reisen_uniform",
	"reisen_charm",
	"reisen_ointment",
	"reisen_ointmentfx",
	"reisen_boostfx",
	"reisen_petalring",
	"reisen_critfx",

}

Assets = {

    -- Ensure moon phase animation builds are loaded before the HUD widget runs.
    -- Without these declarations the builds are loaded lazily by the game clock
    -- and may not be present when OverrideSymbol is first called on our badge.
    Asset("ANIM", "anim/moon_phases.zip"),
    Asset("ANIM", "anim/moon_phases_clock.zip"),

    Asset( "IMAGE", "images/saveslot_portraits/reisen.tex" ),
    Asset( "ATLAS", "images/saveslot_portraits/reisen.xml" ),

    Asset( "IMAGE", "images/selectscreen_portraits/reisen.tex" ),
    Asset( "ATLAS", "images/selectscreen_portraits/reisen.xml" ),
	
    Asset( "IMAGE", "images/selectscreen_portraits/reisen_silho.tex" ),
    Asset( "ATLAS", "images/selectscreen_portraits/reisen_silho.xml" ),

    Asset( "IMAGE", "bigportraits/reisen.tex" ),
    Asset( "ATLAS", "bigportraits/reisen.xml" ),
	
	Asset( "IMAGE", "images/map_icons/reisen.tex" ),
	Asset( "ATLAS", "images/map_icons/reisen.xml" ),
	
	Asset( "IMAGE", "images/avatars/avatar_reisen.tex" ),
    Asset( "ATLAS", "images/avatars/avatar_reisen.xml" ),
	
	Asset( "IMAGE", "images/avatars/avatar_ghost_reisen.tex" ),
    Asset( "ATLAS", "images/avatars/avatar_ghost_reisen.xml" ),
	
	Asset( "IMAGE", "images/avatars/self_inspect_reisen.tex" ),
    Asset( "ATLAS", "images/avatars/self_inspect_reisen.xml" ),
	
	Asset( "IMAGE", "images/names_reisen.tex" ),
    Asset( "ATLAS", "images/names_reisen.xml" ),
	
    Asset( "IMAGE", "bigportraits/reisen_none.tex" ),
    Asset( "ATLAS", "bigportraits/reisen_none.xml" ),

	Asset( "IMAGE", "images/inventoryimages/reisen_casual.tex" ),
	Asset( "ATLAS", "images/inventoryimages/reisen_casual.xml" ),

	Asset( "IMAGE", "images/inventoryimages/reisen_uniform.tex" ),
	Asset( "ATLAS", "images/inventoryimages/reisen_uniform.xml" ),

	Asset( "IMAGE", "images/inventoryimages/reisen_charm.tex" ),
	Asset( "ATLAS", "images/inventoryimages/reisen_charm.xml" ),

    Asset( "IMAGE", "images/inventoryimages/reisen_ointment.tex" ),
    Asset( "ATLAS", "images/inventoryimages/reisen_ointment.xml" ),

	-- HUD sanity dots (moon icon); PNG source at images/reisen_dot.png — run tools/ktech_reisen_dot.bat to build .tex
	Asset( "IMAGE", "images/reisen_dot.tex" ),
	Asset( "ATLAS", "images/reisen_dot.xml" ),

}

RegisterInventoryItemAtlas("images/inventoryimages/reisen_casual.xml", "reisen_casual.tex")
RegisterInventoryItemAtlas("images/inventoryimages/reisen_uniform.xml", "reisen_uniform.tex")
RegisterInventoryItemAtlas("images/inventoryimages/reisen_charm.xml", "reisen_charm.tex")
RegisterInventoryItemAtlas("images/inventoryimages/reisen_ointment.xml", "reisen_ointment.tex")

-- Register starting items for the character selection screen.
-- The screen reads from TUNING.GAMEMODE_STARTING_ITEMS; the start_inv in the
-- prefab file only controls what is actually spawned in-game.
-- Character name must be UPPERCASE; only DEFAULT / LAVAARENA / QUAGMIRE exist
-- as top-level mode keys. ENDLESS and WILDERNESS fall back to DEFAULT.
local REISEN_START_INV = {"manrabbit_tail", "carrot", "carrot", "carrot", "monsterlasagna"}
TUNING.GAMEMODE_STARTING_ITEMS = TUNING.GAMEMODE_STARTING_ITEMS or {}
for _, mode in ipairs({"DEFAULT", "LAVAARENA", "QUAGMIRE"}) do
    TUNING.GAMEMODE_STARTING_ITEMS[mode] = TUNING.GAMEMODE_STARTING_ITEMS[mode] or {}
    TUNING.GAMEMODE_STARTING_ITEMS[mode]["REISEN"] = REISEN_START_INV
end

local require = GLOBAL.require
local pcall = GLOBAL.pcall
local STRINGS = GLOBAL.STRINGS
local Ingredient = GLOBAL.Ingredient
local TECH = GLOBAL.TECH
local TheNet = GLOBAL.TheNet
local EQUIPSLOTS = GLOBAL.EQUIPSLOTS
local debug = GLOBAL.debug

local ReisenI18n = require "reisen_i18n"
local ReisenConsts = require "reisen_consts"
local ReisenPerf = require "reisen_perf"

-- Register the 3-slot fuel container for reisen_charm.
--   Slot 1 : nightmarefuel only   (+25 % maxfuel, refuel at < 75 %)
--   Slot 2 : horrorfuel only      (+50 % maxfuel, refuel at < 50 %)
--   Slot 3 : shadowheart / shadowheart_infused (passive — not fuel)
local _charm_containers = require("containers")
local _V3 = GLOBAL.Vector3
_charm_containers.params["reisen_charm"] = {
    widget = {
        slotpos = {
            _V3(-(64 + 12), 0, 0),
            _V3(0,          0, 0),
            _V3( (64 + 12), 0, 0),
        },
        animbank  = "ui_chest_3x1",
        animbuild = "ui_chest_3x1",
    },
    acceptsstacks        = true,
    usespecificslotsforitems = true,
    type                 = "chest",
    itemtestfn = function(container, item, slot)
        -- slot == nil: general validity check used by CanTakeItemInSlot / STORE action.
        -- Must return true for any item this container can ever hold; GiveItem will then
        -- call GetSpecificSlotForItem (with real slot numbers) to find the right slot.
        if slot == nil then
            return item.prefab == "nightmarefuel"
                or item.prefab == "horrorfuel"
                or item.prefab == "shadowheart"
                or item.prefab == "shadowheart_infused"
        end
        if slot == 1 then return item.prefab == "nightmarefuel"
        elseif slot == 2 then return item.prefab == "horrorfuel"
        elseif slot == 3 then return item.prefab == "shadowheart" or item.prefab == "shadowheart_infused"
        end
        return false
    end,
}

-- Client-side: overlay a faded item icon on each empty charm container slot so
-- players know what to put there. Uses the same SetBGImage2 / SetOnTileChangedFn
-- mechanism as DST's own construction-site slots.
local _CHARM_SLOT_HINTS = {
    { atlas = "images/inventoryimages2.xml", image = "nightmarefuel.tex"       },
    { atlas = "images/inventoryimages2.xml", image = "horrorfuel.tex"          },
    { atlas = "images/inventoryimages3.xml", image = "shadowheart_infused.tex" },
}
AddClassPostConstruct("widgets/containerwidget", function(self)
    local base_open = self.Open
    self.Open = function(self_w, container, doer)
        base_open(self_w, container, doer)
        if container == nil or container.prefab ~= "reisen_charm" then return end
        for i, hint in ipairs(_CHARM_SLOT_HINTS) do
            local slot = self_w.inv[i]
            if slot ~= nil then
                slot:SetBGImage2(hint.atlas, hint.image, { 1, 1, 1, 0.35 })
                local function on_tile_changed(_, tile)
                    if slot.bgimage2 == nil then return end
                    if tile ~= nil then
                        slot.bgimage2:Hide()
                    else
                        slot.bgimage2:Show()
                    end
                end
                slot:SetOnTileChangedFn(on_tile_changed)
                on_tile_changed(nil, slot.tile)
            end
        end
    end
end)

local _reisen_zh_variant = ReisenI18n.GetChineseVariant()

-- Expose console hook so a player with admin can toggle perf logging in-game:
--   ReisenPerf(true) / ReisenPerf(false) / ReisenPerf("dump")
GLOBAL.ReisenPerf = ReisenPerf.Console
-- Gate for debug-only prints (release_heal flow, stategraph handler).
-- Disabled by default; flip via ReisenPerf(true) or by editing this constant.
local function _reisen_dbg(...)
    if ReisenPerf.IsEnabled() then
        print(...)
    end
end

local function DeepCopyTable(src)
	if type(src) ~= "table" then
		return src
	end
	local dst = {}
	for k, v in pairs(src) do
		dst[k] = DeepCopyTable(v)
	end
	return dst
end


local function IdentifyShit(fn, name)
	local i = 1
	while debug.getupvalue(fn, i) and debug.getupvalue(fn, i) ~= name do
		i = i + 1
	end
	local _, value = debug.getupvalue(fn, i)
	return value, i
end

local function CollectShit(fn, ...)
	local prv, upi
	for _, var in ipairs({ ... }) do
		if type(fn) ~= "function" then
			return nil, nil, nil
		end
		prv = fn
		fn, upi = IdentifyShit(fn, var)
	end
	return fn, upi, prv
end

local function IsReisenCharacter()
	local p = GLOBAL.ThePlayer
	return p ~= nil and p.prefab == "reisen"
end

local function ReisenMooncharmEquipped()
	local p = GLOBAL.ThePlayer
	if p == nil or p.replica.inventory == nil or EQUIPSLOTS == nil then
		return false
	end
	local hat = p.replica.inventory:GetEquippedItem(EQUIPSLOTS.HEAD)
	return hat ~= nil and hat.prefab == "reisen_charm"
end

local function ReisenCharmImmunityActive()
	local p = GLOBAL.ThePlayer
	if p == nil or not ReisenMooncharmEquipped() then return false end
	local world = GLOBAL.TheWorld
	if world ~= nil and world.state.isfullmoon then
		-- Mirror server logic: full moon only breaks immunity at night.
		local is_night = world:HasTag("cave") and world.state.iscavenight or not world:HasTag("cave") and world.state.isnight
		if is_night then return false end
	end
	local hunger = p.replica and p.replica.hunger
	if hunger ~= nil then
		return hunger:GetPercent() > 0
	end
	return true
end

local function ReisenShouldSuppressGreyVision()
	-- Grey vision / distortion is suppressed whenever charm is worn, regardless
	-- of whether full immunity is active.  Even when conditions break charm
	-- immunity (full-moon night, starvation, nightmare amulet, …) the
	-- PostProcessor flicker effect should still be hidden.
	return IsReisenCharacter() or ReisenMooncharmEquipped()
end

local function ReisenShouldSuppressSanitySound()
	return IsReisenCharacter() or ReisenCharmImmunityActive()
end

local function ReisenShouldSuppressFramework()
	return ReisenCharmImmunityActive()
end

local function ReisenClearGreyVision()
	local PP = GLOBAL.PostProcessor
	if PP == nil then return end
	PP:SetColourCubeLerp(1, 0)
	PP:SetDistortionFactor(1)
	PP:SetOverlayBlend(0)
end

local VIG_VEIN_SYMBOLS = {"vigpaint"}

local function ReisenHideVigVeins(hud)
	if hud ~= nil and hud.vig ~= nil then
		local anim = hud.vig:GetAnimState()
		for _, sym in ipairs(VIG_VEIN_SYMBOLS) do
			anim:HideSymbol(sym)
		end
	end
end

local function ReisenApplySanityMute()
	local w = GLOBAL.TheWorld
	if w == nil or w.SoundEmitter == nil then
		return
	end
	if ReisenShouldSuppressSanitySound() then
		w.SoundEmitter:SetVolume("SANITY", 0)
	else
		w.SoundEmitter:SetVolume("SANITY", 1)
	end
end

local function ReisenRefreshInsanityVisual()
	local p = GLOBAL.ThePlayer
	local hud = p ~= nil and p.HUD or nil
	if hud == nil then
		return
	end
	if ReisenShouldSuppressFramework() then
		if hud.GoSane ~= nil then
			hud:GoSane()
		end
		ReisenClearGreyVision()
	else
		-- Framework is not suppressed: sync visual with actual sanity replica state.
		-- GoInsane hook handles Reisen's vein hiding, so no separate elseif needed.
		local sanity = p.replica ~= nil and p.replica.sanity or nil
		if sanity ~= nil and sanity:IsCrazy() then
			if hud.GoInsane ~= nil then
				hud:GoInsane()
			end
		end
	end
end

AddComponentPostInit("sanity", function(sanity)
	local inst = sanity.inst
	-- inst.prefab is not set yet during AddComponentPostInit (it's assigned by
	-- SpawnPrefab after the prefab fn returns), so we must check HasTag("player")
	-- here and defer the prefab check to runtime inside each listener.
	if inst == nil or not inst:HasTag("player") then
		return
	end
	local w = GLOBAL.TheWorld
	if w == nil or not w.ismastersim then
		return
	end

	inst._reisen_shadow_overwhelming = false
	local shadow_watch_task = nil
	local night_spawn_task = nil

	local function reisen_update_sane()
		if inst.components.sanity == nil or not inst._reisen_charm_worn then return end
		local world = GLOBAL.TheWorld
		local is_night = world ~= nil and (world:HasTag("cave") and world.state.iscavenight or not world:HasTag("cave") and world.state.isnight)
		local is_full_moon = is_night and world.state.isfullmoon
		local hunger_ok = inst.components.hunger ~= nil and inst.components.hunger.current > 0
		local new_sane = not (is_full_moon or inst._reisen_shadow_overwhelming or not hunger_ok)
		-- SetInducedInsanity sources (e.g. starvation via reisen_sync_starving_insanity) have
		-- higher priority than the charm's forced-sane mechanism.  If any induced-insanity source
		-- is active, cap new_sane to false so the charm cannot silently override it regardless
		-- of which handler happens to run last.
		if new_sane and inst.components.sanity.inducedinsanity then
			new_sane = false
		end
		inst.components.sanity.sane = new_sane
		-- Fire speech once per sane→insane transition (only for Reisen).
		if inst.prefab == "reisen" and not new_sane and inst._reisen_charm_sane_prev ~= false then
			local speech = STRINGS.CHARACTERS
				and STRINGS.CHARACTERS.REISEN
				and STRINGS.CHARACTERS.REISEN.ANNOUNCE_REISEN_CHARM_INSANE
			if inst.components.talker ~= nil and type(speech) == "string" and speech ~= "" then
				inst.components.talker:Say(speech)
			end
		end
		inst._reisen_charm_sane_prev = new_sane
	end

	local function start_shadow_watch()
		if shadow_watch_task ~= nil then return end
		shadow_watch_task = inst:DoPeriodicTask(5, function()
			if GLOBAL.TheWorld == nil then return end
			ReisenPerf.Bump("charm.shadow_watch.tick")
			local _t_done = ReisenPerf.Begin("charm.shadow_watch")
			local x, y, z = inst.Transform:GetWorldPosition()
			local ents = GLOBAL.TheSim:FindEntities(x, y, z, 20, {"shadowcreature"})
			local overwhelming = #ents >= ReisenConsts.CHARM_SHADOW_OVERWHELM_THRESHOLD
			if overwhelming ~= inst._reisen_shadow_overwhelming then
				inst._reisen_shadow_overwhelming = overwhelming
				reisen_update_sane()
			end
			_t_done()
		end)
	end

	local function stop_shadow_watch()
		if shadow_watch_task ~= nil then
			shadow_watch_task:Cancel()
			shadow_watch_task = nil
		end
		inst._reisen_shadow_overwhelming = false
	end

	-- Non-full-moon dualgear night: random shadow creature spawned periodically.
	-- Full-moon dualgear night: one-time bunnyman batch (count = cycles/40, min 1 max 3).
	-- Bunnyman do NOT despawn at dawn; shadow creatures do.
	local NIGHT_SPAWN_PREFABS = {"terrorbeak", "crawlinghorror"}
	local SHADOW_SPAWN_MAX_NEAR = 5
	local SHADOW_COUNT_RADIUS = 30   -- radius for pre-spawn creature count check
	local SPAWN_PLACE_RADIUS = 20    -- radius for randomising spawn position
	local _bunnyman_spawned_this_moon = false  -- prevents re-spawn if dualgear re-equipped

	local function is_dualgear_night_eligible()
		local inv = inst.components.inventory
		if inv == nil then return false end
		local head = inv:GetEquippedItem(GLOBAL.EQUIPSLOTS.HEAD)
		local body = inv:GetEquippedItem(GLOBAL.EQUIPSLOTS.BODY)
		if head == nil or body == nil
			or head.prefab ~= "reisen_charm"
			or body.prefab ~= "reisen_uniform" then
			return false
		end
		local world = GLOBAL.TheWorld
		if world == nil then return false end
		local is_night = world:HasTag("cave") and world.state.iscavenight or not world:HasTag("cave") and world.state.isnight
		if not is_night then return false end
		if inst:HasTag("playerghost")
			or (inst.components.health ~= nil and inst.components.health.dead) then
			return false
		end
		return true
	end

	-- One-time bunnyman batch for full-moon dualgear nights.
	-- count = floor(cycles / 40), clamped to [1, 3]. No day-removal callback.
	local function spawn_bunnyman_fullmoon_batch()
		if _bunnyman_spawned_this_moon then return end
		if not is_dualgear_night_eligible() then return end
		_bunnyman_spawned_this_moon = true
		local world = GLOBAL.TheWorld
		local cycles = (world ~= nil and world.state.cycles) or 0
		local count = math.max(1, math.min(3, math.floor(cycles / 40)))
		local x, y, z = inst.Transform:GetWorldPosition()
		for _ = 1, count do
			local angle = math.random() * 2 * math.pi
			local dist = 10 + math.random() * 8
			local mob = GLOBAL.SpawnPrefab("bunnyman")
			if mob ~= nil then
				mob.Transform:SetPosition(x + dist * math.cos(angle), 0, z - dist * math.sin(angle))
			end
		end
	end

	-- Periodic shadow-creature spawn for non-full-moon nights.
	local function try_spawn_one_shadow()
		if not is_dualgear_night_eligible() then return end
		ReisenPerf.Bump("dualgear.night_spawn.tick")
		local _t_done = ReisenPerf.Begin("dualgear.night_spawn")
		local x, y, z = inst.Transform:GetWorldPosition()
		local nearby = GLOBAL.TheSim:FindEntities(x, y, z, SHADOW_COUNT_RADIUS,
			nil, {"INLIMBO", "FX"}, {"shadowcreature", "nightmarecreature"})
		local count = 0
		for _, e in ipairs(nearby) do
			if e ~= nil and e:IsValid()
				and e.components ~= nil
				and e.components.health ~= nil
				and not e.components.health:IsDead() then
				count = count + 1
			end
		end
		if count >= SHADOW_SPAWN_MAX_NEAR then
			_t_done()
			return
		end
		local angle = math.random() * 2 * math.pi
		local dist = 10 + math.random() * 8
		local px = x + dist * math.cos(angle)
		local pz = z - dist * math.sin(angle)
		local prefab = NIGHT_SPAWN_PREFABS[math.random(#NIGHT_SPAWN_PREFABS)]
		local shadow = GLOBAL.SpawnPrefab(prefab)
		if shadow ~= nil then
			shadow.Transform:SetPosition(px, 0, pz)
			shadow:WatchWorldState("isday", function(s)
				if s ~= nil and s:IsValid() then s:Remove() end
			end)
			shadow:WatchWorldState("iscaveday", function(s)
				if s ~= nil and s:IsValid() then s:Remove() end
			end)
		end
		_t_done()
	end

	-- Full moon: one-time bunnyman batch; no periodic task needed.
	-- Normal night: immediate first shadow, then periodic every DUALGEAR_SHADOW_SPAWN_INTERVAL s.
	-- Guard against night_spawn_task ~= nil so we don't double-start on re-equip.
	local function start_night_spawn()
		local world = GLOBAL.TheWorld
		local is_full = world ~= nil and world.state.isfullmoon
		if is_full then
			spawn_bunnyman_fullmoon_batch()
			return
		end
		if night_spawn_task ~= nil then return end
		try_spawn_one_shadow()
		if not is_dualgear_night_eligible() then return end
		local interval = ReisenConsts.DUALGEAR_SHADOW_SPAWN_INTERVAL
		night_spawn_task = inst:DoPeriodicTask(interval, try_spawn_one_shadow, interval)
	end

	local function stop_night_spawn()
		if night_spawn_task ~= nil then
			night_spawn_task:Cancel()
			night_spawn_task = nil
		end
		-- _bunnyman_spawned_this_moon is intentionally NOT reset here so that
		-- unequipping and re-equipping dualgear on the same full-moon night cannot
		-- retrigger the batch.  Only a true dawn transition resets it.
	end

	-- Start / stop based on night transitions (surface and cave).
	inst:WatchWorldState("isnight", function()
		local world = GLOBAL.TheWorld
		if world ~= nil and world.state.isnight then
			start_night_spawn()
		else
			stop_night_spawn()
			_bunnyman_spawned_this_moon = false  -- new day: next full moon is fresh
		end
	end)

	inst:WatchWorldState("iscavenight", function()
		local world = GLOBAL.TheWorld
		if world ~= nil and world.state.iscavenight then
			start_night_spawn()
		else
			stop_night_spawn()
			_bunnyman_spawned_this_moon = false  -- new day: next full moon is fresh
		end
	end)

	inst:ListenForEvent("equip", function(player, data)
		if data == nil or data.item == nil then return end
		local prefab = data.item.prefab
		if prefab == "reisen_charm" then
			start_shadow_watch()
			-- Only start night spawn if dualgear is complete AND it's already night.
			-- Equipping during daytime must NOT create the task; WatchWorldState handles
			-- the night-start transition so the immediate first spawn fires correctly.
			if is_dualgear_night_eligible() then
				start_night_spawn()
			end
			-- Reset transition flag so the first suppression-break after equip fires speech.
			inst._reisen_charm_sane_prev = true
			reisen_update_sane()
		elseif prefab == "reisen_uniform" then
			if is_dualgear_night_eligible() then
				start_night_spawn()
			end
		end
	end)

	inst:ListenForEvent("unequip", function(player, data)
		if data == nil or data.item == nil then return end
		local prefab = data.item.prefab
		if prefab == "reisen_charm" then
			stop_shadow_watch()
			stop_night_spawn()
		elseif prefab == "reisen_uniform" then
			stop_night_spawn()
		end
	end)

	inst:WatchWorldState("isfullmoon", function()
		if inst._reisen_charm_worn then
			reisen_update_sane()
		end
	end)

	inst:ListenForEvent("sanitydelta", function()
		if inst._reisen_charm_worn then
			reisen_update_sane()
		end
	end)

	local _hunger_was_zero = false
	inst:ListenForEvent("hungerdelta", function()
		if inst.components.hunger == nil then return end
		local is_zero = inst.components.hunger.current <= 0
		if is_zero ~= _hunger_was_zero then
			_hunger_was_zero = is_zero
			reisen_update_sane()
		end
	end)

	-- On load, WatchWorldState only fires on transitions, not on the initial state.
	-- Check immediately in case the player spawns during an ongoing night.
	inst:DoTaskInTime(0, function()
		start_night_spawn()
	end)
end)

if not TheNet:IsDedicated() then
	AddClassPostConstruct("widgets/statusdisplays", function(self)
		if self.owner == nil or self.owner.prefab ~= "reisen" then
			return
		end
		local ReisenLunarBadge  = require "widgets/reisen_lunarbadge"
		local ReisenSanityDots  = require "widgets/reisen_sanitydots"

		self.reisen_lunarbadge = self:AddChild(ReisenLunarBadge(self.owner))
		self.reisen_lunarbadge:Show()

		self.reisen_sanitydots = self:AddChild(ReisenSanityDots(self.owner))
		self.reisen_sanitydots:Show()

		-- Defer positioning until all other mods' AddClassPostConstruct callbacks
		-- have run.  Combined Status (workshop-376333686) always writes
		-- GLOBAL.TUNING.COMBINED_STATUS_UNIT regardless of its config, so we
		-- use that as a reliable detection flag.
		--
		-- Default layout  : column5 = -120, same slot as Wolfgang's mightybadge.
		-- Combined Status : extra badges live at (-62, -52), below the hunger badge.
		--
		-- Dots sit to the LEFT of the lunar badge.
		-- X offset: badge_radius(~30) + dot_half(~8) + gap(~4) = 42
		-- Y: same centre as badge so the dot column aligns vertically.
		self.inst:DoTaskInTime(0, function()
			if self.reisen_lunarbadge == nil then return end
			local bx, by, bz
			if GLOBAL.TUNING.COMBINED_STATUS_UNIT ~= nil then
				bx, by, bz = -62, -52, 0
			else
				bx, by, bz = self.column5, 20, 0
			end
			self.reisen_lunarbadge:SetPosition(bx, by, bz)
			if self.reisen_sanitydots ~= nil then
				self.reisen_sanitydots:SetPosition(bx - 41, by, bz)
			end
		end)
	end)

	local PlayerHud = require("screens/playerhud")
	local old_GoInsane = PlayerHud.GoInsane
	function PlayerHud:GoInsane(...)
		-- Track whether we entered through the suppression path.
		-- suppress_active == true  →  client thinks charm immunity is on, but
		--   IsCrazy() overrides (external inducedinsanity, e.g. nightmare amulet).
		--   In this case we WANT the vig "insane" animation to show.
		-- suppress_active == false →  charm immunity is genuinely broken by game
		--   conditions (full moon night, starvation, shadow overwhelm).
		--   In this case we suppress the dark-edge vig animation for charm wearers.
		local suppress_active = ReisenShouldSuppressFramework()
		if suppress_active then
			-- Defer to the server replica: if the server says the player is
			-- crazy, don't suppress even if client-side immunity looks active.
			-- This covers cases where server overrides sane=false for reasons
			-- the client can't see (shadow overwhelming, full moon timing gap).
			local p = self.owner or GLOBAL.ThePlayer
			local sanity = p ~= nil and p.replica ~= nil and p.replica.sanity or nil
			if sanity == nil or not sanity:IsCrazy() then
				return
			end
		end
		old_GoInsane(self, ...)
		if IsReisenCharacter() or ReisenMooncharmEquipped() then
			ReisenHideVigVeins(self)
		end
		if ReisenMooncharmEquipped() then
			-- old_GoInsane may directly write PostProcessor state (colour cube,
			-- distortion, overlay) before OnSanityDelta has a chance to fire.
			ReisenClearGreyVision()
			-- When charm immunity was NOT active (game-condition crazy: full moon,
			-- starvation, shadow overwhelm), suppress the vig dark-edge animation
			-- so non-Reisen charm wearers behave the same as Reisen.
			-- When suppress_active was true (external inducedinsanity, e.g. nightmare
			-- amulet), keep the "insane" vig animation to signal the forced state.
			if not suppress_active then
				self.vig:GetAnimState():PlayAnimation("basic", true)
			end
		end
	end
end

AddPrefabPostInit("world", function(world)
	if TheNet:IsDedicated() then
		return
	end
	local listeners = world.event_listeners
		and world.event_listeners.playeractivated
		and world.event_listeners.playeractivated[world]
	if listeners ~= nil then
		for _, v in pairs(listeners) do
			if type(v) == "function" and CollectShit(v, "OnOverrideCCTable") then
				local orig, idx, listener = CollectShit(v, "OnSanityDelta")
				if orig ~= nil and listener ~= nil and idx ~= nil and type(orig) == "function" then
					local function wrapped(inst, data, ...)
						if ReisenShouldSuppressGreyVision() then
							ReisenClearGreyVision()
							return
						end
						return orig(inst, data, ...)
					end
					debug.setupvalue(listener, idx, wrapped)
				end
			end
		end
	end
	world:ListenForEvent("playeractivated", function(w, player)
		if player ~= GLOBAL.ThePlayer then
			return
		end
		-- Guard against playeractivated firing multiple times for the same entity
		-- (e.g. shard migration back to the same world within one session).
		if player._reisen_client_listeners_registered then
			return
		end
		player._reisen_client_listeners_registered = true
		player:ListenForEvent("equip", function(_, data)
			if data ~= nil and data.item ~= nil and data.item.prefab == "reisen_charm" then
				ReisenApplySanityMute()
				-- On equip (including save-load restore), suppress the insanity
				-- framework immediately without querying replica, which may not
				-- yet reflect the newly equipped item and would cause GoInsane to
				-- fire incorrectly while the replica catches up.
				-- Exception: if an external source (e.g. nightmare amulet) is
				-- holding inducedinsanity active, the server keeps sane=false and
				-- the replica will already report IsCrazy()==true by this tick.
				-- In that case skip GoSane so the frame stays visible.
				player:DoTaskInTime(0, function()
					local hud = player.HUD
					if hud == nil then return end
					local san = player.replica ~= nil and player.replica.sanity or nil
					if san ~= nil and san:IsCrazy() then return end
					if hud.GoSane ~= nil then hud:GoSane() end
					ReisenClearGreyVision()
				end)
			end
		end)
		player:ListenForEvent("unequip", function(_, data)
			if data ~= nil and data.item ~= nil and data.item.prefab == "reisen_charm" then
				ReisenApplySanityMute()
				-- On unequip the replica will already reflect the removal, so the
				-- full visual refresh is safe to run after a tick.
				player:DoTaskInTime(0, ReisenRefreshInsanityVisual)
			end
		end)
		local _client_hunger_was_zero = false
		player:ListenForEvent("hungerdelta", function()
			if not ReisenMooncharmEquipped() then return end
			local hunger = player.replica and player.replica.hunger
			if hunger == nil then return end
			local is_zero = hunger:GetPercent() <= 0
			if is_zero ~= _client_hunger_was_zero then
				_client_hunger_was_zero = is_zero
				ReisenApplySanityMute()
				ReisenRefreshInsanityVisual()
			end
		end)
		ReisenApplySanityMute()
		if IsReisenCharacter() then
			player:DoTaskInTime(0, ReisenClearGreyVision)
		end
	end)
end)

local function is_reisen_dualgear_equipped(inst)
	if inst == nil or inst.components.inventory == nil then
		return false
	end
	local body = inst.components.inventory:GetEquippedItem(EQUIPSLOTS.BODY)
	local head = inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HEAD)
	return body ~= nil and head ~= nil
		and body.prefab == "reisen_uniform"
		and head.prefab == "reisen_charm"
end

local function try_say_reisen_dualgear_hint(inst, key, cooldown)
	if inst == nil or inst.prefab ~= "reisen" then
		return
	end
	if inst.components.talker == nil then
		return
	end
	local now = GLOBAL.GetTime and GLOBAL.GetTime() or 0
	inst._reisen_dualgear_hint_cd = inst._reisen_dualgear_hint_cd or {}
	local cd_key = key or "ANNOUNCE_REISEN_DUALGEAR"
	local next_time = inst._reisen_dualgear_hint_cd[cd_key]
	if next_time ~= nil and now < next_time then
		return
	end
	inst._reisen_dualgear_hint_cd[cd_key] = now + (cooldown or 10)
	local speech = STRINGS.CHARACTERS
		and STRINGS.CHARACTERS.REISEN
		and STRINGS.CHARACTERS.REISEN[cd_key]
	if type(speech) == "string" and speech ~= "" then
		inst.components.talker:Say(speech)
	end
end

-- Dual-gear night spawns: AddComponentPostInit("sanity") above.
-- Non–full-moon: 1 shadow creature on night start, +1 every 60s (cap 5 nearby).
-- Full moon: same cadence and cap, but bunnymen instead of shadow creatures.

STRINGS.SCRAPBOOK = STRINGS.SCRAPBOOK or {}
STRINGS.SCRAPBOOK.SPECIALINFO = STRINGS.SCRAPBOOK.SPECIALINFO or {}
STRINGS.SCRAPBOOK.SPECIALINFO.REISEN_CASUAL = "Sanity restore is conditional: only active when hunger is above 75%."
STRINGS.SCRAPBOOK.SPECIALINFO.REISEN_UNIFORM = "Slightly increases movement speed; hunger depletes faster. While worn, reduces max sanity by 25%, worsening to 50% as durability drops. Successful attacks cost a small amount of sanity. At 0 sanity, movement speed increases further and you are immune to knockback. Worn with the Lunatic Vision Ribbon, negative events can trigger at night."
STRINGS.SCRAPBOOK.SPECIALINFO.REISEN_CHARM = "Nightmare Fuel refuels 25%, Horror Fuel 50%. Unequipping costs 25% max fuel. Applies a 50% sanity penalty but blocks all other sanity loss. When hit, each strike has a small chance to summon a Terrorbeak and cost fuel. All immunity effects cease when surrounded by a group of shadow creatures or when hunger reaches 0. Worn together with the Lunar Battle Uniform: each hit on a shadow or nightmare creature grants +10 flat bonus damage (stacks up to +50), lasting 30 seconds and refreshed on each hit."

STRINGS.NAMES.REISEN_CASUAL = "Moon Rabbit Casual"
STRINGS.RECIPE_DESC.REISEN_CASUAL = "Soft homewear with modest armor and warmth."
STRINGS.CHARACTERS.GENERIC.DESCRIBE.REISEN_CASUAL = "It feels extra cozy when I am full."

AddCharacterRecipe(
	"petals_evil",
	{
		Ingredient("nightmarefuel", 3),
		Ingredient("petals", 1),
	},
	TECH.NONE,
	{
		builder_tag = "reisen",
		force_hint = true,
	},
	{"MAGIC"}
)

AddCharacterRecipe(
	"reisen_casual",
	{
		Ingredient("silk", 3),
		Ingredient("manrabbit_tail", 1),
		Ingredient("armorgrass", 1),
	},
	TECH.NONE,
	{
		atlas = "images/inventoryimages/reisen_casual.xml",
		image = "reisen_casual.tex",
		builder_tag = "reisen",
		force_hint = true,
	},
	{"ARMOUR"}
)

STRINGS.NAMES.REISEN_UNIFORM = "Lunar Battle Uniform"
STRINGS.RECIPE_DESC.REISEN_UNIFORM = "Battle-ready uniform. Fast and protective, but strains mind and body."
STRINGS.CHARACTERS.GENERIC.DESCRIBE.REISEN_UNIFORM = "The uniform feels fused with me, as if it resists getting hurt."

AddCharacterRecipe(
	"reisen_uniform",
	{
		Ingredient("silk", 8),
		Ingredient("nightmarefuel", 4),
		Ingredient("beardhair", 4),
		Ingredient("manrabbit_tail", 2),
	},
	TECH.MAGIC_THREE,
	{
		atlas = "images/inventoryimages/reisen_uniform.xml",
		image = "reisen_uniform.tex",
		builder_tag = "reisen",
		force_hint = true,
	},
	{"ARMOUR", "MAGIC"}
)

STRINGS.NAMES.REISEN_CHARM = "Lunatic Vision Ribbon"
STRINGS.RECIPE_DESC.REISEN_CHARM = "Eerie ribbon that suppresses shadows. Fueled by Nightmare or Horror Fuel."
STRINGS.CHARACTERS.GENERIC.DESCRIBE.REISEN_CHARM = "I can almost see shadows breaking through the barrier at night."

STRINGS.ACTIONS = STRINGS.ACTIONS or {}
STRINGS.ACTIONS.REISEN_RELEASE_HEAL = "Release Mind Blowing"
STRINGS.ACTIONS.REISEN_MOON_PORT    = "Moon Port"
STRINGS.ACTIONS.REISEN_STATS        = "Stats"
STRINGS.REISEN_STATS_FMT            = "ATK: x%.2f\nSPD: x%.2f\nVULN: %.2f\nACCUM: %d/%d"
STRINGS.REISEN_ACCUM_FMT            = "ACCUM: %d/%d"

AddCharacterRecipe(
	"reisen_charm",
	{
		Ingredient("nightmarefuel", 8),
		Ingredient("petals_evil", 4),
		Ingredient("manrabbit_tail", 2),
		Ingredient("crow", 1),
	},
	TECH.MAGIC_TWO,
	{
		atlas = "images/inventoryimages/reisen_charm.xml",
		image = "reisen_charm.tex",
		builder_tag = "reisen",
		force_hint = true,
	},
	{"CLOTHING", "MAGIC"}
)

STRINGS.NAMES.REISEN_OINTMENT = "Dark Moon Salve"
STRINGS.RECIPE_DESC.REISEN_OINTMENT = "A shadow-attuned salve that keeps lunacy at bay."
STRINGS.CHARACTERS.GENERIC.DESCRIBE.REISEN_OINTMENT = "Smells faintly of petals and dread."

STRINGS.SCRAPBOOK = STRINGS.SCRAPBOOK or {}
STRINGS.SCRAPBOOK.SPECIALINFO = STRINGS.SCRAPBOOK.SPECIALINFO or {}
STRINGS.SCRAPBOOK.SPECIALINFO.REISEN_OINTMENT = "Restores 50 HP and costs 25 Sanity on use. Enters Enlightenment mode，taking a real hit immediately breaks the ward."

AddCharacterRecipe(
	"reisen_ointment",
	{
		Ingredient("spidergland", 4),
		Ingredient("silk", 3),
		Ingredient("petals_evil", 1),
	},
	TECH.MAGIC_TWO,
	{
		atlas = "images/inventoryimages/reisen_ointment.xml",
		image = "reisen_ointment.tex",
		builder_tag = "reisen",
		force_hint = true,
	},
	{"RESTORATION", "MAGIC"}
)

-- Stats read by the character selection screen:
-- TEMPLATES.MakeUIStatusBadge reads TUNING[upper(character.."_"..stat)]
local TUNING = GLOBAL.TUNING
TUNING.REISEN_HEALTH = 300
TUNING.REISEN_HUNGER = 200
TUNING.REISEN_SANITY = 100


STRINGS.CHARACTER_TITLES.reisen = "The Moon Rabbit"
STRINGS.CHARACTER_NAMES.reisen = "Reisen"
STRINGS.CHARACTER_DESCRIPTIONS.reisen = "Cute or Cruel, depends on Sanity\n *Lunatic: Power shifts with Sanity; at low Sanity, survival is traded for sharper combat instincts\n *Phantasm: Gain buffs from combo stacks; effects grow stronger when boosted,\n *Strong Vitality: resist cold, run faster\n *Carrot Addiction: Eating carrots restores Sanity; the more you eat, the happier you feel; you cannot sleep"
STRINGS.CHARACTER_QUOTES.reisen = "\"I'm just a little bunny, only good for my appeal.\""

if _reisen_zh_variant ~= nil and STRINGS.CHARACTERS ~= nil and STRINGS.CHARACTERS.GENERIC ~= nil then
	-- Chinese locale: use vanilla Chinese speech as baseline,
	-- then apply Reisen-specific localized overrides below.
	STRINGS.CHARACTERS.REISEN = DeepCopyTable(STRINGS.CHARACTERS.GENERIC)
else
	STRINGS.CHARACTERS.REISEN = require "speech_reisen"
end

STRINGS.NAMES.REISEN = "Reisen"

if _reisen_zh_variant ~= nil then
	local ztbl = ReisenI18n.ZH[_reisen_zh_variant]
	ReisenI18n.ApplyToStrings(STRINGS, ztbl)
	ReisenI18n.ApplySpeechDescribe(STRINGS.CHARACTERS.REISEN, ztbl)
end

-- Register item atlases for the scrapbook icon renderer
RegisterScrapbookIconAtlas("images/inventoryimages/reisen_casual.xml", "reisen_casual.tex")
RegisterScrapbookIconAtlas("images/inventoryimages/reisen_uniform.xml", "reisen_uniform.tex")
RegisterScrapbookIconAtlas("images/inventoryimages/reisen_charm.xml", "reisen_charm.tex")
RegisterScrapbookIconAtlas("images/inventoryimages/reisen_ointment.xml", "reisen_ointment.tex")

-- Inject custom items into the scrapbook.
-- Both tables are Lua module singletons; modifications here are visible to
-- the scrapbook screen when it later requires the same modules.
local scrapbook_prefabs = require("scrapbook_prefabs")
scrapbook_prefabs["reisen_casual"] = true
scrapbook_prefabs["reisen_uniform"] = true
scrapbook_prefabs["reisen_charm"] = true
scrapbook_prefabs["reisen_ointment"] = true

local scrapbookdata = require("screens/redux/scrapbookdata")
scrapbookdata["reisen_casual"] = {
	name = "reisen_casual",
	tex = "reisen_casual.tex",
	type = "item",
	subcat = "armor",
	prefab = "reisen_casual",
	armor = 300,
	absorb_percent = 0.75,
	insulator = 60,
	insulator_type = "winter",
	dapperness = 0.041667,
	fueltype = "BURNABLE",
	fuelvalue = TUNING.LARGE_FUEL,
	burnable = true,
	build = "reisen_casual",
	bank = "reisen_casual",
	anim = "anim",
	craftingprefab = "reisen",
	deps = {"silk", "manrabbit_tail", "armorgrass"},
	specialinfo = "REISEN_CASUAL",
}
scrapbookdata["reisen_uniform"] = {
	name = "reisen_uniform",
	tex = "reisen_uniform.tex",
	type = "item",
	subcat = "armor",
	prefab = "reisen_uniform",
	armor = 1105,
	absorb_percent = 0.85,
	fueledmax = TUNING.TOTAL_DAY_TIME * 8,
	fueledrate = 1,
	fueledtype1 = "USAGE",
	build = "reisen_uniform",
	bank = "reisen_uniform",
	anim = "anim",
	craftingprefab = "reisen",
	deps = {"manrabbit_tail", "papyrus", "nightmarefuel", "beardhair"},
	specialinfo = "REISEN_UNIFORM",
}
scrapbookdata["reisen_charm"] = {
	name = "reisen_charm",
	tex = "reisen_charm.tex",
	type = "item",
	subcat = "clothing",
	prefab = "reisen_charm",
	build = "reisen_hat",
	bank = "reisenhat",
	anim = "anim",
	fueledmax = TUNING.TOTAL_DAY_TIME * 2,
	fueledrate = 1,
	fueledtype1 = "NIGHTMARE",
	craftingprefab = "reisen",
	deps = {"nightmarefuel", "petals_evil", "manrabbit_tail", "crow"},
	specialinfo = "REISEN_CHARM",
}
scrapbookdata["reisen_ointment"] = {
	name = "reisen_ointment",
	tex = "reisen_ointment.tex",
	type = "item",
	subcat = "elixer",
	prefab = "reisen_ointment",
	build = "reisen_ointment",
	bank = "reisenointment",
	anim = "idle",
	health = 50,
	craftingprefab = "reisen",
	deps = {"spidergland", "silk", "petals_evil"},
	specialinfo = "REISEN_OINTMENT",
}

AddMinimapAtlas("images/map_icons/reisen.xml")

AddPlayerPostInit(function(inst)
	inst._reisen_dualgear_hint_active = false
	inst:ListenForEvent("equip", function(i, data)
		if data ~= nil and data.item ~= nil
			and (data.item.prefab == "reisen_uniform" or data.item.prefab == "reisen_charm") then
			if is_reisen_dualgear_equipped(i) then
				if not i._reisen_dualgear_hint_active then
					i._reisen_dualgear_hint_active = true
					try_say_reisen_dualgear_hint(i, "ANNOUNCE_REISEN_DUALGEAR", 10)
				end
			else
				i._reisen_dualgear_hint_active = false
			end
		end
	end)
	inst:ListenForEvent("unequip", function(i, data)
		if data ~= nil and data.item ~= nil
			and (data.item.prefab == "reisen_uniform" or data.item.prefab == "reisen_charm") then
			if not is_reisen_dualgear_equipped(i) then
				i._reisen_dualgear_hint_active = false
			end
		end
	end)
end)

-- ── Dualgear: shadow hit damage bonus (all characters) ──────────────────────
-- Hitting a shadowcreature / nightmarecreature while wearing full dualgear
-- (reisen_uniform + reisen_charm) stacks a flat damage bonus applied via
-- bonusdamagefn.  Each stack adds +10 flat damage to every hit (up to
-- +50 at 5 stacks).  Any hit on an eligible target refreshes the 30-second
-- expiry timer; the timer expiring clears all stacks at once.
--
-- Implementation note: bonusdamagefn is called server-side on every attack,
-- so reading a plain numeric field costs virtually nothing.  We wrap any
-- existing bonusdamagefn (e.g. Reisen's boosted crit) rather than replacing
-- it, keeping the two effects fully independent and additive.
local DUALGEAR_SHADOW_DMG_PER_STACK  = ReisenConsts.DUALGEAR_SHADOW_DMG_PER_STACK
local DUALGEAR_SHADOW_DMG_MAX_STACKS = ReisenConsts.DUALGEAR_SHADOW_DMG_MAX_STACKS
local DUALGEAR_SHADOW_DMG_DURATION   = ReisenConsts.DUALGEAR_SHADOW_DMG_DURATION

AddPlayerPostInit(function(inst)
	-- Capture any bonusdamagefn the prefab constructor already set (Reisen crit fn).
	-- This runs after the character's fn(), so the existing fn is already in place.
	local orig_bonus_fn = inst.components.combat ~= nil
		and inst.components.combat.bonusdamagefn or nil

	if inst.components.combat ~= nil then
		inst.components.combat.bonusdamagefn = function(attacker, target, damage, weapon)
			local bonus = 0
			local stacks = attacker._reisen_dualgear_shadow_stacks or 0
			if stacks > 0 then
				bonus = stacks * DUALGEAR_SHADOW_DMG_PER_STACK
			end
			if orig_bonus_fn ~= nil then
				bonus = bonus + orig_bonus_fn(attacker, target, damage, weapon)
			end
			return bonus
		end
	end

	inst._reisen_dualgear_shadow_stacks = 0
	inst._reisen_dualgear_shadow_task   = nil

	inst:ListenForEvent("onhitother", function(i, data)
		if not (GLOBAL.TheWorld ~= nil and GLOBAL.TheWorld.ismastersim) then return end
		if data == nil or data.target == nil or not data.target:IsValid() then return end
		if not (data.target:HasTag("shadowcreature") or data.target:HasTag("nightmarecreature")) then
			return
		end
		if not is_reisen_dualgear_equipped(i) then return end

		local new_stacks = math.min(
			(i._reisen_dualgear_shadow_stacks or 0) + 1,
			DUALGEAR_SHADOW_DMG_MAX_STACKS)
		i._reisen_dualgear_shadow_stacks = new_stacks

		-- Refresh the expiry timer on every eligible hit.
		if i._reisen_dualgear_shadow_task ~= nil then
			i._reisen_dualgear_shadow_task:Cancel()
		end
		i._reisen_dualgear_shadow_task = i:DoTaskInTime(
			DUALGEAR_SHADOW_DMG_DURATION,
			function(inst2)
				inst2._reisen_dualgear_shadow_task   = nil
				inst2._reisen_dualgear_shadow_stacks = 0
			end)
	end)
end)

-- Monster Lasagna (monsterlasagna) is detected via the eater component's
-- oneat callback in reisen.lua, so no AddPrefabPostInit hook is needed here.

-- When a player is force-killed via console (PushEvent('death')), the health
-- component's currenthealth is not reduced to 0, so health:IsDead() returns
-- false. The global SGwilson attacked handler checks health:IsDead() and
-- will try to GoToState("hit") if that returns false, triggering the death
-- state's onexit assert. Add a no-op state-specific attacked handler to the
-- death state that returns true, blocking the global handler from running.
AddStategraphPostInit("wilson", function(sg)
    local death = sg.states["death"]
    if death ~= nil and death.events["attacked"] == nil then
        death.events["attacked"] = GLOBAL.EventHandler("attacked", function(inst)
            return true
        end)
    end
end)

-- When Reisen starts a work action (chop / mine / hammer) at zero sanity,
-- push an event so reisen.lua can fire the speech hint via its cooldown system.
AddStategraphPostInit("wilson", function(sg)
    for _, state_name in ipairs({ "chop", "mine", "hammer" }) do
        local state = sg.states[state_name]
        if state ~= nil then
            local orig_onenter = state.onenter
            state.onenter = function(inst)
                if orig_onenter ~= nil then orig_onenter(inst) end
                if inst:HasTag("reisen")
                    and inst.components.sanity ~= nil
                    and inst.components.sanity.current <= 0 then
                    inst:PushEvent("reisen_zero_san_work")
                end
            end
        end
	end
end)

-- During dodge ("reisen_dodging" entity tag is active), suppress GoToState("hit") so
-- the player is not frozen by hit-stun. The original global attacked handler is still
-- called for all other branches (transform, sleeping, electrocute, knockback, etc.).
-- Only the final GoToState("hit") / stunlock path is intercepted.
AddStategraphPostInit("wilson", function(sg)
    local orig = sg.events["attacked"]
    if orig == nil then return end
    sg.events["attacked"] = GLOBAL.EventHandler("attacked", function(inst, data)
        if inst:HasTag("reisen_dodging") then
            -- Mirror the "nointerrupt / nostunlock" branch: play sounds, skip hit state.
            if inst.SoundEmitter ~= nil then
                inst.SoundEmitter:PlaySound("dontstarve/wilson/hit")
            end
            return
        end
        return orig.fn(inst, data)
    end)
end)

AddModCharacter("reisen", "FEMALE")

-- ════════════════════════════════════════════════════════════════════════
--  REISEN RELEASE MIND BLOWING ACTION
--  Right-click a target to instantly release accumulated kill HP heal.
--  Deals heal_amount × combat.damagemultiplier damage to hostile entities
--  within ReisenConsts.RELEASE_HEAL_RADIUS of the target, and applies
--  Mind Blowing fear: lerp FEAR_MIN..FEAR_MAX by accum / RELEASE_HEAL_ACCUM_CAP.
--  Constants live in reisen_consts.lua.
-- ════════════════════════════════════════════════════════════════════════

-- Read constants from the shared module (avoids duplicating magic numbers in modmain).
-- IMPORTANT: these must be declared before any function that closes over them, otherwise
-- Lua resolves them as globals (nil) at call time.
local REISEN_RELEASE_HEAL_RADIUS_MIN         = ReisenConsts.RELEASE_HEAL_RADIUS_MIN
local REISEN_RELEASE_HEAL_RADIUS_MAX         = ReisenConsts.RELEASE_HEAL_RADIUS_MAX
local REISEN_RELEASE_HEAL_RADIUS_BOOSTED     = ReisenConsts.RELEASE_HEAL_RADIUS_BOOSTED
local REISEN_RELEASE_HEAL_FEAR_DURATION        = ReisenConsts.RELEASE_HEAL_FEAR_DURATION
local REISEN_RELEASE_HEAL_SANITY_COST        = ReisenConsts.RELEASE_HEAL_SANITY_COST
local REISEN_BOOSTED_HUNGER_MULT             = ReisenConsts.BOOSTED_HUNGER_MULT
local REISEN_RELEASE_HEAL_BOOSTED_SELF_MULT  = ReisenConsts.RELEASE_HEAL_BOOSTED_SELF_MULT
local REISEN_RELEASE_SLOW_SANITY_COST   = ReisenConsts.RELEASE_SLOW_SANITY_COST
local REISEN_RELEASE_SLOW_STACK_COST    = ReisenConsts.RELEASE_SLOW_STACK_COST
local REISEN_RELEASE_SLOW_MULT          = ReisenConsts.RELEASE_SLOW_MULT
local REISEN_RELEASE_SLOW_MULT_NEAR     = ReisenConsts.RELEASE_SLOW_MULT_NEAR
local REISEN_RELEASE_SLOW_DURATION      = ReisenConsts.RELEASE_SLOW_DURATION
local REISEN_RELEASE_HEAL_ACCUM_CAP          = ReisenConsts.RELEASE_HEAL_ACCUM_CAP
local REISEN_LUNATIC_MAX                     = ReisenConsts.LUNATIC_MAX
local REISEN_BOOSTED_AUTO_COLLECT_RADIUS     = ReisenConsts.BOOSTED_AUTO_COLLECT_RADIUS
-- (Old assert: RELEASE_SLOW_STACK_COST < LUNATIC_STACK_MID no longer required for Slow Field gate.)
-- if REISEN_RELEASE_SLOW_STACK_COST >= REISEN_LUNATIC_STACK_MID then
--     error("reisen mod: RELEASE_SLOW_STACK_COST must be < LUNATIC_STACK_MID")
-- end

-- Returns true when the player is in Enlightenment (SANITY_MODE_LUNACY).
-- Server: sanity:IsLunacyMode()
-- Client: replica.sanity._isinsanitymode == false  (false = LUNACY, true = INSANITY)
local function ReisenIsEnlightened(inst)
    if TheNet:GetIsServer() or TheNet:IsDedicated() then
        return inst.components.sanity ~= nil and inst.components.sanity:IsLunacyMode()
    else
        local rep = inst.replica and inst.replica.sanity
        return rep ~= nil and rep._isinsanitymode ~= nil and rep._isinsanitymode:value() == false
    end
end

local function ReisenCanReleaseHeal(inst)
    if inst == nil or inst.prefab ~= "reisen" then
        return false
    end
    if inst:HasTag("playerghost") then
        return false
    end
    -- In Enlightenment, Moon Port replaces Mind Blowing entirely.
    if ReisenIsEnlightened(inst) then return false end
    local stack, accum
    if TheNet:GetIsServer() or TheNet:IsDedicated() then
        stack = inst._reisen_lunatic_stack or 0
        accum = inst._reisen_kill_hp_accum or 0
    else
        stack = inst._reisen_lunatic_net ~= nil and inst._reisen_lunatic_net:value() or 0
        accum = inst._reisen_kill_hp_accum_net ~= nil and inst._reisen_kill_hp_accum_net:value() or 0
    end
    -- MODE A (Mind Blowing, accum > 0): any positive stack is enough.
    -- MODE B (Slow Field, accum = 0): requires stack >= RELEASE_SLOW_STACK_COST (i.e. stack=1 is valid).
    if accum > 0 then
        return stack > 0
    end
    return stack >= REISEN_RELEASE_SLOW_STACK_COST
end

-- True if release cost can be paid: sanity, or (fallback) hunger with current > 0.
-- hunger_only: boosted Mind Blowing — must have hunger > 0 (no sanity).
local function ReisenCanAffordReleaseCost(inst, sanity_cost, hunger_only)
    if hunger_only then
        return inst.components.hunger ~= nil and inst.components.hunger.current > 0
    end
    if inst.components.sanity ~= nil and inst.components.sanity.current >= sanity_cost then
        return true
    end
    return inst.components.hunger ~= nil and inst.components.hunger.current > 0
end

-- Unified cost function.  Returns false if the cost cannot be paid (caller should abort).
--
-- Universal gate: hunger = 0 always blocks all skills.
--
-- Boosted (stack > 0 and _reisen_lunatic_boosted):
--   Requires hunger > 0.  Drains hunger × BOOSTED_HUNGER_MULT (scaled by vuln).
--   Sanity is not touched.
--
-- Normal, Enlightenment (SANITY_MODE_LUNACY):
--   Recover sanity: gain = sanity_cost × (1 − vuln).
--
-- Normal, not Enlightenment:
--   Deduct sanity; fall back to hunger drain if sanity insufficient.
--   Returns false when neither sanity nor hunger is available.
local function ReisenPayCost(inst, sanity_cost)
    -- Universal gate: hunger = 0 blocks all skills regardless of mode.
    if inst.components.hunger == nil or inst.components.hunger.current <= 0 then
        return false
    end

    local s    = inst.components.sanity
    local vuln = inst.vulnerable or 0
    local is_boosted = (inst._reisen_lunatic_stack or 0) > 0
        and inst._reisen_lunatic_boosted == true

    if is_boosted then
        if not ReisenCanAffordReleaseCost(inst, sanity_cost, true) then
            return false
        end
        if inst.components.hunger ~= nil then
            inst.components.hunger:DoDelta(sanity_cost * (-1 + vuln) * REISEN_BOOSTED_HUNGER_MULT)
        end
        return true  -- boosted: hunger only, sanity untouched
    end

    if s ~= nil and s.IsLunacyMode ~= nil and s:IsLunacyMode() then
        s:DoDelta(sanity_cost * (1 - vuln))
        return true
    end

    if not ReisenCanAffordReleaseCost(inst, sanity_cost, false) then
        return false
    end
    if s ~= nil and s.current >= sanity_cost then
        s:DoDelta(-sanity_cost)
    else
        if inst.components.hunger ~= nil then
            inst.components.hunger:DoDelta(sanity_cost * (-1 + vuln))
        end
    end
    return true
end

local REISEN_SLOW_SPEED_KEY = "reisen_mind_slow"

local function ReisenApplySlow(ent, duration, mult)
    if ent == nil or not ent:IsValid() or duration <= 0 then
        return
    end
    if ent.components.locomotor == nil then
        return
    end
    ent.components.locomotor:SetExternalSpeedMultiplier(ent, REISEN_SLOW_SPEED_KEY, mult)
    local is_refresh = ent._reisen_slow_task ~= nil
    if is_refresh then
        ent._reisen_slow_task:Cancel()
    end
    ent._reisen_slow_task = ent:DoTaskInTime(duration, function(e)
        e._reisen_slow_task = nil
        if e:IsValid() and e.components.locomotor ~= nil then
            e.components.locomotor:RemoveExternalSpeedMultiplier(e, REISEN_SLOW_SPEED_KEY)
        end
    end)
    if not is_refresh then
        local drip = GLOBAL.SpawnPrefab("ghostlyelixir_slowregen_dripfx")
        if drip ~= nil then
            local ex, ey, ez = ent.Transform:GetWorldPosition()
            drip.Transform:SetPosition(ex, ey, ez)
        end
    end
end

local function ReisenApplyFear(ent, duration, source_pos)
    if ent == nil or not ent:IsValid() or duration <= 0 then
        return
    end
    if ent.components.hauntable ~= nil and ent.components.hauntable.Panic ~= nil then
        ent.components.hauntable:Panic(duration)
    end
end

-- ══════════════════════════════════════════════════════════════════════════
-- Shared AoE helpers – called by both ReleaseHeal and MoonPort.
-- All position arguments are ground-level (y=0 unless the target is elevated).
-- ══════════════════════════════════════════════════════════════════════════

-- MODE A core: damage + fear + slow AoE around (tx,tz).
-- Returns true if any enemy was killed (for boost-state trigger).
local function ReisenDoMindBlowingAoE(doer, tx, tz, accum, is_boosted)
    local aoe_radius = is_boosted and REISEN_RELEASE_HEAL_RADIUS_BOOSTED or REISEN_RELEASE_HEAL_RADIUS_MAX
    local dmg_mult = math.max((doer.components.combat ~= nil and doer.components.combat.damagemultiplier) or 1, 0.01)
    local damage_amount = accum * dmg_mult
    local dest_pos = GLOBAL.Vector3(tx, 0, tz)

    local ents = GLOBAL.TheSim:FindEntities(tx, 0, tz, aoe_radius,
        nil, {"INLIMBO", "FX", "NOCLICK", "player", "playerghost"})
    local any_killed = false
    for _, ent in ipairs(ents) do
        if ent ~= nil and ent:IsValid() and ent ~= doer then
            local is_structure = ent:HasTag("structure") or ent:HasTag("wall")
            local follower = ent.components.follower
            local leader = follower ~= nil and follower:GetLeader() or nil
            local followed_by_player = leader ~= nil and leader:HasTag("player")
            local is_combat_entity = ent.components.combat ~= nil
                and not ent:HasTag("companion")
                and not ent:HasTag("notarget")
            if is_combat_entity and not is_structure and not followed_by_player then
                local health = ent.components.health
                if health ~= nil and not health:IsDead() then
                    ent.components.combat:GetAttacked(doer, damage_amount, nil)
                    if health:IsDead() then
                        any_killed = true
                    end
                    local hit_fx = GLOBAL.SpawnPrefab("sanity_lower")
                    if hit_fx ~= nil then
                        local ex, ey, ez = ent.Transform:GetWorldPosition()
                        hit_fx.Transform:SetPosition(ex, ey, ez)
                    end
                end
                ReisenApplyFear(ent, REISEN_RELEASE_HEAL_FEAR_DURATION, dest_pos)
                ReisenApplySlow(ent, REISEN_RELEASE_SLOW_DURATION, REISEN_RELEASE_SLOW_MULT)
            end
        end
    end

    local wave_prefab = is_boosted and "moonpulse2_fx" or "moonpulse_fx"
    local wave_fx = GLOBAL.SpawnPrefab(wave_prefab)
    if wave_fx ~= nil then
        wave_fx.Transform:SetPosition(tx, 0, tz)
    end
    return any_killed
end

-- MODE B core: distance-based slow field AoE around (tx,tz), no damage.
-- Plays the slow-field sound and FX at the target position.
local function ReisenDoSlowFieldAoE(doer, tx, tz)
    local aoe_radius = REISEN_RELEASE_HEAL_RADIUS_MAX
    local r_near = REISEN_RELEASE_HEAL_RADIUS_MIN
    local r_span = aoe_radius - r_near  -- guaranteed > 0 by constants

    -- _reisen_no_stack_aoe prevents stack gain from the 0-damage hit in reisen_on_hit_other.
    doer._reisen_no_stack_aoe = true
    local ents = GLOBAL.TheSim:FindEntities(tx, 0, tz, aoe_radius,
        nil, {"INLIMBO", "FX", "NOCLICK", "player", "playerghost"})
    for _, ent in ipairs(ents) do
        if ent ~= nil and ent:IsValid() and ent ~= doer then
            local is_structure = ent:HasTag("structure") or ent:HasTag("wall")
            local follower = ent.components.follower
            local leader = follower ~= nil and follower:GetLeader() or nil
            local followed_by_player = leader ~= nil and leader:HasTag("player")
            local is_combat_entity = ent.components.combat ~= nil
                and not ent:HasTag("companion")
                and not ent:HasTag("notarget")
            if is_combat_entity and not is_structure and not followed_by_player then
                local health = ent.components.health
                if health ~= nil and not health:IsDead() then
                    -- 0-damage hit: fires on-hit events without dealing damage.
                    ent.components.combat:GetAttacked(doer, 1, nil)
                end
                -- Distance-based slow: RADIUS_MIN → 95% slow, RADIUS_MAX → 50% slow.
                local ex, _, ez = ent.Transform:GetWorldPosition()
                local dist = math.sqrt((ex - tx)^2 + (ez - tz)^2)
                local t = math.max(0, math.min(1, (dist - r_near) / r_span))
                local slow_mult = REISEN_RELEASE_SLOW_MULT_NEAR
                    + t * (REISEN_RELEASE_SLOW_MULT - REISEN_RELEASE_SLOW_MULT_NEAR)
                ReisenApplySlow(ent, REISEN_RELEASE_SLOW_DURATION, slow_mult)
            end
        end
    end
    doer._reisen_no_stack_aoe = false

    if doer.SoundEmitter ~= nil then
        doer.SoundEmitter:PlaySound("dontstarve/common/nightmareAddFuel")
    end
    local slow_fx = GLOBAL.SpawnPrefab("slingshot_aoe_fx")
    if slow_fx ~= nil then
        slow_fx.Transform:SetPosition(tx, 0, tz)
        slow_fx:SetColorType("slow")
    end
end

-- ══════════════════════════════════════════════════════════════════════════

local function ReisenDoReleaseHeal(act)
    local doer = act.doer
    local target = act.target
    if doer == nil or doer.prefab ~= "reisen" then
        _reisen_dbg("[REISEN] ReleaseHeal: SKIP – doer nil or not reisen")
        return false
    end
    if not GLOBAL.TheWorld.ismastersim then
        _reisen_dbg("[REISEN] ReleaseHeal: client side, returning true")
        return true
    end

    local stack = doer._reisen_lunatic_stack or 0
    local accum = doer._reisen_kill_hp_accum or 0
    _reisen_dbg(string.format("[REISEN] ReleaseHeal: server entry  stack=%d accum=%d", stack, accum))
    ReisenPerf.Bump("release_heal.invoke")

    if stack <= 0 then
        _reisen_dbg("[REISEN] ReleaseHeal: ABORT – stack=0 (returning true to avoid client stall)")
        -- Return true to let the castspellmind state complete normally on both
        -- server and client.  When client net vars are stale, client may enter
        -- the action while server's authoritative stack is already 0; returning
        -- false here causes a state mismatch that freezes the character.
        return true
    end

    local tx, ty, tz
    if target ~= nil and target:IsValid() then
        tx, ty, tz = target.Transform:GetWorldPosition()
    else
        tx, ty, tz = doer.Transform:GetWorldPosition()
    end

    if accum > 0 then
        -- ── MODE A: Mind Blowing ──────────────────────────────────────────
        _reisen_dbg(string.format("[REISEN] ReleaseHeal: → MODE A  accum=%d", accum))
        local is_boosted = doer._reisen_lunatic_boosted == true
        if not ReisenPayCost(doer, REISEN_RELEASE_HEAL_SANITY_COST) then
            _reisen_dbg("[REISEN] ReleaseHeal: MODE A cost failed (returning true to avoid client stall)")
            return true
        end

        doer._reisen_kill_hp_accum = 0
        doer._reisen_kill_hp_accum_net_last_value = 0
        if doer._reisen_kill_hp_accum_net ~= nil then doer._reisen_kill_hp_accum_net:set(0) end

        local dmg_mult = math.max((doer.components.combat ~= nil and doer.components.combat.damagemultiplier) or 1, 0.01)
        local self_heal_frac = is_boosted and (REISEN_RELEASE_HEAL_BOOSTED_SELF_MULT / dmg_mult) or (1 / dmg_mult)
        if doer.components.health ~= nil then
            doer.components.health:DoDelta(accum * self_heal_frac, true)
        end

        local any_killed = ReisenDoMindBlowingAoE(doer, tx, tz, accum, is_boosted)
        if accum >= REISEN_RELEASE_HEAL_ACCUM_CAP then
            doer:PushEvent("reisen_boost_triggered")
        end

        if doer.SoundEmitter ~= nil then doer.SoundEmitter:PlaySound("maxwell_rework/shadow_magic/cast") end
        local px, py, pz = doer.Transform:GetWorldPosition()
        local self_fx = GLOBAL.SpawnPrefab("attune_out_fx")
        if self_fx ~= nil then self_fx.Transform:SetPosition(px, py, pz) end

        if doer.components.talker ~= nil then
            local speech = STRINGS.CHARACTERS and STRINGS.CHARACTERS.REISEN
                and STRINGS.CHARACTERS.REISEN.ANNOUNCE_REISEN_MIND_BLOWING
            if type(speech) == "string" and speech ~= "" then doer.components.talker:Say(speech) end
        end
    else
        -- ── MODE B: Slow Field ────────────────────────────────────────────
        _reisen_dbg(string.format("[REISEN] ReleaseHeal: → MODE B  stack=%d", stack))
        if stack < REISEN_RELEASE_SLOW_STACK_COST then
            _reisen_dbg(string.format("[REISEN] ReleaseHeal: MODE B stack insufficient (returning true to avoid client stall)"))
            return true
        end
        if not ReisenPayCost(doer, REISEN_RELEASE_SLOW_SANITY_COST) then
            _reisen_dbg("[REISEN] ReleaseHeal: MODE B cost failed (returning true to avoid client stall)")
            return true
        end

        local new_stack = stack - REISEN_RELEASE_SLOW_STACK_COST
        doer._reisen_lunatic_stack = new_stack
        if doer._reisen_lunatic_net ~= nil then doer._reisen_lunatic_net:set(new_stack) end
        if new_stack == 0 then
            doer:PushEvent("reisen_stack_zeroed")
        else
            doer:PushEvent("reisen_stats_dirty")
        end

        ReisenDoSlowFieldAoE(doer, tx, tz)

        local px, py, pz = doer.Transform:GetWorldPosition()
        local caster_fx = GLOBAL.SpawnPrefab("attune_out_fx")
        if caster_fx ~= nil then caster_fx.Transform:SetPosition(px, py, pz) end
        local shadow_puff_fx = GLOBAL.SpawnPrefab("statue_transition_2")
        if shadow_puff_fx ~= nil then shadow_puff_fx.Transform:SetPosition(tx, ty, tz) end

        if doer.components.talker ~= nil then
            local sp1 = STRINGS.CHARACTERS and STRINGS.CHARACTERS.REISEN
                and STRINGS.CHARACTERS.REISEN.ANNOUNCE_REISEN_MIND_STOPPER
            if type(sp1) == "string" and sp1 ~= "" then doer.components.talker:Say(sp1) end
            local sp2 = STRINGS.CHARACTERS and STRINGS.CHARACTERS.REISEN
                and STRINGS.CHARACTERS.REISEN.ANNOUNCE_REISEN_SLOW_NEED_SOUL
            if type(sp2) == "string" and sp2 ~= "" then
                doer:DoTaskInTime(1.5, function(d)
                    if d:IsValid() and d.components.talker ~= nil then d.components.talker:Say(sp2) end
                end)
            end
        end
    end

    _reisen_dbg("[REISEN] ReleaseHeal: DONE – returning true")
    return true
end

AddAction("REISEN_RELEASE_HEAL", STRINGS.ACTIONS.REISEN_RELEASE_HEAL or "Release Mind Blowing", ReisenDoReleaseHeal)
GLOBAL.ACTIONS.REISEN_RELEASE_HEAL.rmb = true
GLOBAL.ACTIONS.REISEN_RELEASE_HEAL.distance = ReisenConsts.RELEASE_HEAL_TARGET_DIST
GLOBAL.ACTIONS.REISEN_RELEASE_HEAL.priority = 10
GLOBAL.ACTIONS.REISEN_RELEASE_HEAL.do_not_locomote = true

local function ReisenIsValidReleaseTarget(inst)
    -- Tags are net-synced and safe to read on both client and server.
    -- AddComponentAction("SCENE","combat",...) guarantees inst has a combat component,
    -- so we only need to exclude non-combatants and friendlies.
    if inst:HasTag("player") or inst:HasTag("playerghost") then
        return false
    end
    if inst:HasTag("structure") or inst:HasTag("wall") then
        return false
    end
    -- Exclude permanent companions (Chester, Glommer, etc.) and notarget entities.
    if inst:HasTag("companion") or inst:HasTag("notarget") then
        return false
    end
    -- Any remaining entity with a combat component is a valid target
    -- (covers moose, mosslings, killer bees, bosses, etc.).
    return true
end

AddComponentAction("SCENE", "combat", function(inst, doer, actions, right)
    if right and doer ~= nil and doer.prefab == "reisen" and inst ~= doer then
        if ReisenIsValidReleaseTarget(inst) and ReisenCanReleaseHeal(doer) then
            table.insert(actions, GLOBAL.ACTIONS.REISEN_RELEASE_HEAL)
        end
    end
end)

local function ReisenReleaseHealHandler(inst, action)
    _reisen_dbg(string.format("[REISEN] ReleaseHealHandler: inst=%s sg=%s",
        tostring(inst), inst.sg ~= nil and inst.sg.currentstate ~= nil and inst.sg.currentstate.name or "nil"))
    -- Always use castspellmind for both modes (Mind Blowing and Slow Field).
    --
    -- Root-cause of the animation freeze:
    --   The handler runs independently on the server (SGwilson) and on each client
    --   (SGwilson_client).  The server reads _reisen_kill_hp_accum directly while the
    --   client reads the net variable _reisen_kill_hp_accum_net, which can be stale due
    --   to network propagation delay.  When the two sides disagree (one picks
    --   "castspellmind", the other picks "throw"), the client's castspellmind state
    --   (which has server_states = { "castspellmind" }) waits for a server-state-match
    --   that never arrives, freezing the character until its ontimeout fires.  The
    --   "busy" tag on that prediction state also blocks other actions in the meantime.
    --
    -- Fix: return the same state regardless of accum so server and client always agree.
    -- The actual MODE A (Mind Blowing) vs MODE B (Slow Field) split is decided entirely
    -- inside ReisenDoReleaseHeal on the server based on the authoritative accum value,
    -- and is unrelated to which animation state is entered.
    return "castspellmind"
end

AddStategraphActionHandler("wilson", GLOBAL.ActionHandler(GLOBAL.ACTIONS.REISEN_RELEASE_HEAL, ReisenReleaseHealHandler))
AddStategraphActionHandler("wilson_client", GLOBAL.ActionHandler(GLOBAL.ACTIONS.REISEN_RELEASE_HEAL, ReisenReleaseHealHandler))

-- ════════════════════════════════════════════════════════════════════════
--  REISEN MOON PORT ACTION
--  Right-click an empty tile (like the Lazy Explorer) to cast, then
--  teleport to the cursor position and release Mind Blowing there.
--  Available whenever accum > 0; stack may be 0.
--  stack = 0 → skip self-heal, use normal (non-boosted) mode.
--  The cast animation (castspellmind) plays before the teleport.
-- ════════════════════════════════════════════════════════════════════════

-- Returns true when the player is in Enlightenment (SANITY_MODE_LUNACY).
-- MODE A (accum > 0): teleport + damage AoE.
-- MODE B (accum = 0): teleport + Slow Field, no stack requirement in Enlightenment.
local function ReisenCanMoonPort(inst)
    if inst == nil or inst.prefab ~= "reisen" then return false end
    if inst:HasTag("playerghost") then return false end
    if not ReisenIsEnlightened(inst) then return false end
    return true
end

-- Moon Port: same logic as ReleaseHeal but targeting a ground position chosen
-- by the player, with a teleport prepended and stack restrictions removed.
local function ReisenDoMoonPort(act)
    local doer = act.doer
    if doer == nil or doer.prefab ~= "reisen" then
        _reisen_dbg("[REISEN] MoonPort: SKIP – doer nil or not reisen")
        return false
    end
    if not GLOBAL.TheWorld.ismastersim then
        _reisen_dbg("[REISEN] MoonPort: client side, returning true")
        return true
    end
    if not ReisenIsEnlightened(doer) then
        _reisen_dbg("[REISEN] MoonPort: ABORT – not in Enlightenment")
        return false
    end

    local actionpt = act:GetActionPoint()
    if actionpt == nil then
        _reisen_dbg("[REISEN] MoonPort: ABORT – act.pos nil")
        return false
    end
    local tx, tz = actionpt.x, actionpt.z
    local accum = doer._reisen_kill_hp_accum or 0
    local stack = doer._reisen_lunatic_stack or 0
    local is_boosted = stack > 0 and doer._reisen_lunatic_boosted == true
    _reisen_dbg(string.format("[REISEN] MoonPort: stack=%d accum=%d boosted=%s", stack, accum, tostring(is_boosted)))

    -- Pay cost before any irreversible action.
    local cost = accum > 0 and REISEN_RELEASE_HEAL_SANITY_COST or REISEN_RELEASE_SLOW_SANITY_COST
    if not ReisenPayCost(doer, cost) then return false end

    -- MODE A only: consume accum and self-heal (skip self-heal when stack=0).
    if accum > 0 then
        doer._reisen_kill_hp_accum = 0
        doer._reisen_kill_hp_accum_net_last_value = 0
        if doer._reisen_kill_hp_accum_net ~= nil then doer._reisen_kill_hp_accum_net:set(0) end
        if stack > 0 and doer.components.health ~= nil then
            local dmg_mult = math.max((doer.components.combat ~= nil and doer.components.combat.damagemultiplier) or 1, 0.01)
            local self_heal_frac = is_boosted and (REISEN_RELEASE_HEAL_BOOSTED_SELF_MULT / dmg_mult) or (1 / dmg_mult)
            doer.components.health:DoDelta(accum * self_heal_frac, true)
        end
    end

    -- Departure FX + teleport.
    local px, py, pz = doer.Transform:GetWorldPosition()
    if doer.SoundEmitter ~= nil then doer.SoundEmitter:PlaySound("maxwell_rework/shadow_magic/cast") end
    local cast_fx = GLOBAL.SpawnPrefab("attune_out_fx")
    if cast_fx ~= nil then cast_fx.Transform:SetPosition(px, py, pz) end

    if doer.Physics ~= nil then doer.Physics:Teleport(tx, 0, tz)
    else doer.Transform:SetPosition(tx, 0, tz) end

    -- Post-arrival invincibility: 8 frames ≈ 0.27 s.
    if doer.components.health ~= nil then doer.components.health:SetInvincible(true) end
    doer:DoTaskInTime(8 / 30, function(p)
        if p ~= nil and p:IsValid() and p.components.health ~= nil then p.components.health:SetInvincible(false) end
    end)
    local arrive_fx = GLOBAL.SpawnPrefab("statue_transition_2")
    if arrive_fx ~= nil then arrive_fx.Transform:SetPosition(tx, 0, tz) end

    -- AoE at destination.
    if accum > 0 then
        local any_killed = ReisenDoMindBlowingAoE(doer, tx, tz, accum, is_boosted)
        if accum >= REISEN_RELEASE_HEAL_ACCUM_CAP then
            doer:PushEvent("reisen_boost_triggered")
        end
        _reisen_dbg("[REISEN] MoonPort: MODE A done")
    else
        ReisenDoSlowFieldAoE(doer, tx, tz)
        _reisen_dbg("[REISEN] MoonPort: MODE B (Slow Field) done")
    end

    if doer.components.talker ~= nil then
        local speech = STRINGS.CHARACTERS and STRINGS.CHARACTERS.REISEN
            and STRINGS.CHARACTERS.REISEN.ANNOUNCE_REISEN_MOON_PORT
        if type(speech) == "string" and speech ~= "" then doer.components.talker:Say(speech) end
    end

    _reisen_dbg("[REISEN] MoonPort: DONE – returning true")
    return true
end

-- Two action definitions share the same fn; only do_not_locomote differs.
-- Using two static objects avoids mutating global action state at runtime,
-- which would be a bug when multiple Reisen players are in the same shard.
AddAction("REISEN_MOON_PORT", STRINGS.ACTIONS.REISEN_MOON_PORT or "Moon Port", ReisenDoMoonPort)
GLOBAL.ACTIONS.REISEN_MOON_PORT.rmb               = true
GLOBAL.ACTIONS.REISEN_MOON_PORT.distance          = ReisenConsts.MOON_PORT_RANGE
GLOBAL.ACTIONS.REISEN_MOON_PORT.priority          = 9
GLOBAL.ACTIONS.REISEN_MOON_PORT.encumbered_valid  = true  -- allow use while heavylifting (carrying portable structures)

AddAction("REISEN_MOON_PORT_BOOSTED", STRINGS.ACTIONS.REISEN_MOON_PORT or "Moon Port", ReisenDoMoonPort)
GLOBAL.ACTIONS.REISEN_MOON_PORT_BOOSTED.rmb               = true
GLOBAL.ACTIONS.REISEN_MOON_PORT_BOOSTED.distance          = ReisenConsts.MOON_PORT_RANGE
GLOBAL.ACTIONS.REISEN_MOON_PORT_BOOSTED.priority          = 9
GLOBAL.ACTIONS.REISEN_MOON_PORT_BOOSTED.do_not_locomote   = true
GLOBAL.ACTIONS.REISEN_MOON_PORT_BOOSTED.encumbered_valid  = true  -- allow use while heavylifting (carrying portable structures)

-- AddComponentAction("WORLD", fn) does NOT handle ground right-clicks in DST.
-- Empty-tile right-click goes through playeractionpicker:GetPointSpecialActions →
-- pointspecialactionsfn (set per-character in their prefab, e.g. wilson.lua).
-- We inject Moon Port by wrapping GetPointSpecialActions at the class level.
AddClassPostConstruct("components/playeractionpicker", function(self)
    local orig = self.GetPointSpecialActions
    self.GetPointSpecialActions = function(s, pos, useitem, right, usereticulepos)
        if right
            and s.inst ~= nil
            and s.inst.prefab == "reisen"
            and pos ~= nil
            and ReisenCanMoonPort(s.inst)
        then
            local px = pos.x or 0
            local pz = pos.z or 0
            local world = GLOBAL.TheWorld
            if world ~= nil and world.Map ~= nil
                and world.Map:IsPassableAtPoint(px, 0, pz)
            then
                local is_boosted = s.inst._reisen_lunatic_boosted_net ~= nil
                    and s.inst._reisen_lunatic_boosted_net:value() == true
                local action = is_boosted
                    and GLOBAL.ACTIONS.REISEN_MOON_PORT_BOOSTED
                    or  GLOBAL.ACTIONS.REISEN_MOON_PORT
                return s:SortActionList({ action }, pos, useitem)
            end
        end
        return orig(s, pos, useitem, right, usereticulepos)
    end
end)

local function ReisenMoonPortHandler(inst, action)
    return "castspellmind"
end

AddStategraphActionHandler("wilson", GLOBAL.ActionHandler(GLOBAL.ACTIONS.REISEN_MOON_PORT, ReisenMoonPortHandler))
AddStategraphActionHandler("wilson_client", GLOBAL.ActionHandler(GLOBAL.ACTIONS.REISEN_MOON_PORT, ReisenMoonPortHandler))
AddStategraphActionHandler("wilson", GLOBAL.ActionHandler(GLOBAL.ACTIONS.REISEN_MOON_PORT_BOOSTED, ReisenMoonPortHandler))
AddStategraphActionHandler("wilson_client", GLOBAL.ActionHandler(GLOBAL.ACTIONS.REISEN_MOON_PORT_BOOSTED, ReisenMoonPortHandler))

-- ════════════════════════════════════════════════════════════════════════
--  REISEN BOOSTED AUTO-COLLECT (PICK / HARVEST)
--  When in boosted state, performing PICK or HARVEST automatically
--  collects all pickable / harvestable objects within
--  BOOSTED_AUTO_COLLECT_RADIUS of the caster.  The scan runs server-side
--  immediately after the original action succeeds.
-- ════════════════════════════════════════════════════════════════════════

-- match_fn(ent) → bool: whether the candidate entity counts as "same type"
-- as the original action target.
local function reisen_boosted_collect_nearby(doer, skip_ent, match_fn)
    if doer == nil or doer._reisen_lunatic_boosted ~= true then return end
    if not (GLOBAL.TheWorld ~= nil and GLOBAL.TheWorld.ismastersim) then return end
    ReisenPerf.Bump("boosted_auto_collect.invoke")
    local _t_done = ReisenPerf.Begin("boosted_auto_collect")
    local x, y, z = doer.Transform:GetWorldPosition()
    local ents = GLOBAL.TheSim:FindEntities(x, y, z, REISEN_BOOSTED_AUTO_COLLECT_RADIUS)
    ReisenPerf.Bump("boosted_auto_collect.ents.count", #ents)
    for _, ent in ipairs(ents) do
        if ent ~= doer and ent ~= skip_ent and ent:IsValid() and match_fn(ent) then
            local pickable = ent.components.pickable
            local harvestable = ent.components.harvestable
            local inventoryitem = ent.components.inventoryitem
            if pickable ~= nil and pickable:CanBePicked() then
                pickable:Pick(doer)
            elseif harvestable ~= nil and harvestable:CanBeHarvested() then
                harvestable:Harvest(doer)
            elseif inventoryitem ~= nil and not inventoryitem:IsHeld()
                and doer.components.inventory ~= nil then
                doer.components.inventory:GiveItem(ent)
            end
        end
    end
    _t_done()
end

-- Wrap PICK action at module load time (before ACTIONS are cached)
local _orig_pick_fn = GLOBAL.ACTIONS.PICK.fn
GLOBAL.ACTIONS.PICK.fn = function(act)
    local result = _orig_pick_fn(act)
    if result and act.doer ~= nil and act.doer.prefab == "reisen" then
        local target_prefab = act.target ~= nil and act.target.prefab or nil
        reisen_boosted_collect_nearby(act.doer, act.target, function(ent)
            return ent.prefab == target_prefab
        end)
    end
    return result
end

-- Wrap HARVEST action at module load time
local _orig_harvest_fn = GLOBAL.ACTIONS.HARVEST.fn
GLOBAL.ACTIONS.HARVEST.fn = function(act)
    local result = _orig_harvest_fn(act)
    if result and act.doer ~= nil and act.doer.prefab == "reisen" then
        local target = act.target
        -- Farm plants (crop component or "farmplant" tag): all varieties are same type.
        local is_farmplant = target ~= nil
            and (target:HasTag("farmplant") or target.components.crop ~= nil)
        if is_farmplant then
            reisen_boosted_collect_nearby(act.doer, target, function(ent)
                return ent:HasTag("farmplant") or ent.components.crop ~= nil
            end)
        else
            local target_prefab = target ~= nil and target.prefab or nil
            reisen_boosted_collect_nearby(act.doer, target, function(ent)
                return ent.prefab == target_prefab
            end)
        end
    end
    return result
end

-- Wrap PICKUP action at module load time (ground items)
local _orig_pickup_fn = GLOBAL.ACTIONS.PICKUP.fn
GLOBAL.ACTIONS.PICKUP.fn = function(act)
    local result = _orig_pickup_fn(act)
    if result and act.doer ~= nil and act.doer.prefab == "reisen" then
        local target_prefab = act.target ~= nil and act.target.prefab or nil
        reisen_boosted_collect_nearby(act.doer, act.target, function(ent)
            return ent.prefab == target_prefab
                and ent.components.inventoryitem ~= nil
                and not ent.components.inventoryitem:IsHeld()
                and ent.components.stackable ~= nil
        end)
    end
    return result
end

-- ════════════════════════════════════════════════════════════════════════
--  REISEN STATS ACTION
--  Right-click self to display current attack mult, move speed mult, and
--  kill HP accum pool via talker:Say().
-- ════════════════════════════════════════════════════════════════════════

local function ReisenDoStats(act)
    local doer = act.doer
    if doer == nil or doer.prefab ~= "reisen" then return false end
    if not (GLOBAL.TheWorld ~= nil and GLOBAL.TheWorld.ismastersim) then return true end

    -- Attack multiplier (effective, already includes HI-thresh bonus applied by lunatic()).
    local dmg_mult = (doer.components.combat ~= nil and doer.components.combat.damagemultiplier) or 1.0

    -- Move speed multiplier: tier base × all external multipliers (lunatic, boost, dodge, etc.).
    local base_run = (doer.components.locomotor ~= nil and doer.components.locomotor.runspeed)
        or TUNING.WILSON_RUN_SPEED
    local total_run = base_run
    if doer.components.locomotor ~= nil
        and doer.components.locomotor.externalspeedmultipliers ~= nil
    then
        for _, v in pairs(doer.components.locomotor.externalspeedmultipliers) do
            total_run = total_run * v
        end
    end
    local move_mult = total_run / TUNING.WILSON_RUN_SPEED

    -- Vulnerability (negative = more damage taken; 0 = no penalty).
    local vuln = doer.vulnerable or 0

    -- Kill HP accum pool.
    local accum     = doer._reisen_kill_hp_accum or 0
    local accum_cap = ReisenConsts.RELEASE_HEAL_ACCUM_CAP

    local fmt = (STRINGS.REISEN_STATS_FMT ~= nil and STRINGS.REISEN_STATS_FMT)
        or "ATK: x%.2f\nSPD: x%.2f\nVULN: %.2f\nACCUM: %d/%d"
    local text = string.format(fmt, dmg_mult, move_mult, vuln, accum, accum_cap)

    if doer.components.talker ~= nil then
        doer.components.talker:Say(text)
    end
    return true
end

AddAction("REISEN_STATS", STRINGS.ACTIONS.REISEN_STATS or "Stats", ReisenDoStats)
GLOBAL.ACTIONS.REISEN_STATS.rmb             = true
GLOBAL.ACTIONS.REISEN_STATS.priority        = 8
GLOBAL.ACTIONS.REISEN_STATS.do_not_locomote = true
GLOBAL.ACTIONS.REISEN_STATS.instant         = true   -- bypass stategraph; no animation

-- Show the Stats action when right-clicking Reisen's own character entity.
-- Use "sanity" component (characters only) instead of "inspectable" (all entities)
-- so this callback never runs for world objects like crock_pot.
AddComponentAction("SCENE", "sanity", function(inst, doer, actions, right)
    if right and doer ~= nil and inst == doer and inst.prefab == "reisen" then
        table.insert(actions, GLOBAL.ACTIONS.REISEN_STATS)
    end
end)

