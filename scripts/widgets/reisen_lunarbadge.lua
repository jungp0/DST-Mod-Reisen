local Badge = require "widgets/badge"
local UIAnim = require "widgets/uianim"
local ReisenConsts = require "reisen_consts"
local ReisenPerf = require "reisen_perf"

-- Low-saturation fashionable palette with flowing RGB primaries.
-- R rises throughout; B peaks at 33 then falls; G steadily decreases.
-- Boost (gold overlay) result: jade-gold → cornflower-gold → heather-gold → coral-gold.
local TINT_NEUTRAL    = { 1.00, 1.00, 1.00, 1 }  -- white           (no net)
local TINT_CELADON    = { 0.46, 0.68, 0.64, 1 }  -- celadon jade    (accum =   0, G/B both high)
local TINT_CORNFLOWER = { 0.46, 0.56, 0.74, 1 }  -- dusty cornflower(accum =  33, B peak)
local TINT_HEATHER    = { 0.62, 0.46, 0.70, 1 }  -- muted heather   (accum =  66, R rises / B falls)
local TINT_ROSE       = { 0.82, 0.38, 0.46, 1 }  -- dusty rose      (accum = 100, R peak)

local REISEN_LUNATIC_MAX  = ReisenConsts.LUNATIC_MAX
local REISEN_ACCUM_CAP    = ReisenConsts.RELEASE_HEAL_ACCUM_CAP  -- 100

-- Piecewise linear gradient: celadon → cornflower → heather → rose
local GRADIENT_STOPS = {
    { v = 0,   c = TINT_CELADON    },
    { v = 33,  c = TINT_CORNFLOWER },
    { v = 66,  c = TINT_HEATHER    },
    { v = 100, c = TINT_ROSE       },
}

local function lerp_colour(a, b, t)
    return {
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
        1,
    }
end

local function accum_to_tint(accum)
    accum = math.max(0, math.min(REISEN_ACCUM_CAP, accum))
    local stops = GRADIENT_STOPS
    for i = 1, #stops - 1 do
        local s0, s1 = stops[i], stops[i + 1]
        if accum <= s1.v then
            local t = (accum - s0.v) / (s1.v - s0.v)
            return lerp_colour(s0.c, s1.c, t)
        end
    end
    return TINT_ROSE
end

-- Sanity threshold: below this the badge enters "lunacy" mode.
-- Technique mirrors SanityBadge: swap self.backing's "bg" symbol for "lunacy_bg",
-- the same moonlight-gradient background the vanilla sanity badge uses in lunacy mode.
local SAN_LUNATIC_THRESHOLD = 0.50

local ReisenLunarBadge = Class(Badge, function(self, owner)
    -- Use status_sanity as iconbuild to wire up Badge's OverrideSymbol slot,
    -- then immediately replace the icon with the stack-based moon phase.
    -- moon_phases.zip is declared in modmain Assets so it is guaranteed loaded.
    Badge._ctor(self, nil, owner, TINT_NEUTRAL, "status_sanity", nil, false, true)
    self.circleframe:GetAnimState():OverrideSymbol("icon", "status_sanity", "lunacy_icon")

    -- Border: status_sanity elaborate frame, clock-face ring swapped for the
    -- neutral status_meter ring so SetMultColour shows clean tinting.
    self.circleframe:GetAnimState():Hide("frame")

    self.circleframe2 = self.underNumber:AddChild(UIAnim())
    self.circleframe2:GetAnimState():SetBank("status_sanity")
    self.circleframe2:GetAnimState():SetBuild("status_sanity")
    self.circleframe2:GetAnimState():OverrideSymbol("frame_circle", "status_meter", "frame_circle")
    self.circleframe2:GetAnimState():Hide("FX")
    self.circleframe2:GetAnimState():Hide("icon")
    self.circleframe2:GetAnimState():PlayAnimation("frame")
    self.circleframe2:GetAnimState():AnimateWhilePaused(false)
    self.circleframe2:GetAnimState():SetMultColour(unpack(TINT_NEUTRAL))

    self.cur_tint         = TINT_NEUTRAL
    self.cur_accum        = -1    -- sentinel: force first apply
    self.cur_san_lunatic  = nil   -- sentinel: force first backing/ring apply
    self.cur_stack        = -1    -- sentinel: force first SetPercent
    self.cur_boosted      = nil   -- sentinel: force first colour apply on transition
    self._boost_time      = 0

    self:SetPercent(0, REISEN_LUNATIC_MAX)
    self:StartUpdating()
end)

function ReisenLunarBadge:OnUpdate(dt)
    if TheNet ~= nil and TheNet:IsServerPaused() then return end

    local owner = self.owner
    if owner == nil then return end

    ReisenPerf.Bump("hud.lunarbadge.OnUpdate")

    local stack = owner._reisen_lunatic_net ~= nil and owner._reisen_lunatic_net:value() or 0

    local san_pct = 1.0
    if owner.replica ~= nil and owner.replica.sanity ~= nil then
        san_pct = owner.replica.sanity:GetPercent()
    end

    -- Only re-issue SetPercent when stack actually changes; SetPercent updates the
    -- arc anim state and the centre num text, both of which would otherwise be
    -- recomputed every frame for no visible effect.
    if stack ~= self.cur_stack then
        self.cur_stack = stack
        self:SetPercent(stack / REISEN_LUNATIC_MAX, REISEN_LUNATIC_MAX)
    end

    -- Backing: 2-state lunacy switch (same technique as vanilla SanityBadge).
    -- san > 50%: default backing bg.
    -- san ≤ 50%: lunacy_bg symbol (moonlight gradient).
    local is_lunatic = san_pct <= SAN_LUNATIC_THRESHOLD
    if is_lunatic ~= self.cur_san_lunatic then
        self.cur_san_lunatic = is_lunatic
        if is_lunatic then
            self.backing:GetAnimState():OverrideSymbol("bg", "status_sanity", "lunacy_bg")
        else
            self.backing:GetAnimState():ClearOverrideSymbol("bg")
        end
    end

    -- Tint by accum gradient (green→teal→mauve→rose over 0-100)
    local accum = owner._reisen_kill_hp_accum_net ~= nil and owner._reisen_kill_hp_accum_net:value() or 0
    -- Recompute tint only when accum value changes (net_byte = integer, safe to compare)
    local tint_changed = false
    if accum ~= self.cur_accum then
        self.cur_accum = accum
        self.cur_tint  = accum_to_tint(accum)
        tint_changed   = true
    end
    local tint = self.cur_tint

    -- Boosted state: gold pulse blended onto the fill arc every frame.
    -- Non-boosted: only re-issue SetMultColour when the tint changes or we just
    -- exited boost mode; otherwise skip (saves a SetMultColour per frame).
    local boosted = owner._reisen_lunatic_boosted_net ~= nil and owner._reisen_lunatic_boosted_net:value() or false
    if boosted then
        self._boost_time = self._boost_time + dt
        -- sin wave 0..1, ~2.5 cycles/sec
        local pulse = (math.sin(self._boost_time * 5) + 1) * 0.5
        local r = tint[1] + (1.00 - tint[1]) * pulse * 0.55
        local g = tint[2] + (0.88 - tint[2]) * pulse * 0.55
        local b = tint[3] + (0.18 - tint[3]) * pulse * 0.55
        self.anim:GetAnimState():SetMultColour(r, g, b, 1)
        self.cur_boosted = true
    else
        self._boost_time = 0
        if tint_changed or self.cur_boosted ~= false then
            self.cur_boosted = false
            self.anim:GetAnimState():SetMultColour(unpack(tint))
        end
    end
end

return ReisenLunarBadge
