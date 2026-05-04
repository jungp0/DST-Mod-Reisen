--[[
reisen_sanitydots — Sanity-stage 3-dot indicator widget
==============================================================================

Three moon-dot icons to the LEFT of the lunar badge, arranged vertically.
Texture: hand-drawn DST-style moon circle (warm cream fill, ink outline,
hatch shading, crater details). Base pixel ≈ (1.0, 0.976, 0.925) warm cream.
SetTint multiplies onto this base — B-channel tints are boosted by /0.925
to compensate for the warm base so the final blue reads correctly.

Layout: DARK at TOP (dot 1), LIGHT fills from BOTTOM as san rises.
Each dot has its own tint — top dots are always slightly lighter, bottom dots
slightly darker, for both the dark and light palettes.

  san = 0       ●₁ ●₂ ●₃   fixed dark-crimson  (edge state, no animation)
  san ≤ 25      ●₁ ●₂ ●₃   all dark
  san ≤ 50      ●₁ ●₂ ○₃   2 dark, 1 light (bottom)
  san ≤ 75      ●₁ ○₂ ○₃   1 dark, 2 light
  san < 100     ○₁ ○₂ ○₃   all light
  san = 100     ○₁ ○₂ ○₃   fixed warm-gold     (edge state, no animation)

Tint only reapplied on state change — no per-frame math in steady states.
==============================================================================
--]]

local Widget = require "widgets/widget"
local Image  = require "widgets/image"

-- ── Layout ───────────────────────────────────────────────────────────────────
local DOT_ATLAS   = "images/reisen_dot.xml"
local DOT_TEX     = "reisen_dot.tex"
local DOT_SIZE    = 13
local DOT_SPACING = 16
local DOT_COUNT   = 3

-- ── Per-dot tint tables ───────────────────────────────────────────────────────
-- Index 1 = top dot, 3 = bottom dot.
-- Base pixel ≈ (1.0, 0.976, 0.925) warm cream; B tints boosted by ÷0.925.

-- Normal dark: slate-navy family, top lighter → bottom deeper.
local DARK = {
    { 0.56, 0.61, 0.84, 1 },  -- dot 1 top:    light slate-blue
    { 0.42, 0.47, 0.69, 1 },  -- dot 2 middle: mid slate-navy
    { 0.28, 0.33, 0.54, 1 },  -- dot 3 bottom: deep navy-indigo
}

-- Normal light: warm parchment, top bright → bottom muted.
local LIGHT = {
    { 1.00, 0.98, 0.94, 1 },  -- dot 1 top:    bright warm white
    { 0.90, 0.88, 0.84, 1 },  -- dot 2 middle: soft parchment
    { 0.78, 0.76, 0.72, 1 },  -- dot 3 bottom: muted warm gray
}

-- Edge state — san = 0: muted dusty-rose / wine, same desaturation level as
-- DARK.  Derived from the former ACC_DARK (0.60,0.30,0.38) with per-dot grad.
local EDGE_DARK = {
    { 0.64, 0.32, 0.38, 1 },  -- dot 1 top:    dusty rose
    { 0.54, 0.26, 0.32, 1 },  -- dot 2 middle: mid wine-rose
    { 0.44, 0.20, 0.26, 1 },  -- dot 3 bottom: deep muted wine
}

-- Edge state — san = 100: dusty amber-gold, same muted quality as LIGHT.
-- Derived from the former ACC_LIGHT (0.90,0.80,0.50) with per-dot grad.
local EDGE_LIGHT = {
    { 0.92, 0.80, 0.46, 1 },  -- dot 1 top:    soft bright gold
    { 0.84, 0.72, 0.38, 1 },  -- dot 2 middle: mid amber
    { 0.74, 0.63, 0.32, 1 },  -- dot 3 bottom: deep warm amber
}

-- Boundary softening: the dark dot immediately above a light dot blends
-- 25 % toward a neutral bridge to ease the blue→warm hue jump.
local BOUNDARY_BLEND = 0.25
local BRIDGE = { 0.62, 0.60, 0.60, 1 }

-- ── Sanity → display state ────────────────────────────────────────────────────
-- Returns (lights, edge)
--   lights : number of dots (from BOTTOM) in light state (0-3)
--   edge   : "dark_edge" | "light_edge" | nil
local T1, T2, T3 = 0.25, 0.50, 0.75

local function pct_to_display(pct)
    if pct <= 0        then return 0, "dark_edge"
    elseif pct <= T1   then return 0, nil
    elseif pct <= T2   then return 1, nil
    elseif pct <= T3   then return 2, nil
    elseif pct < 1.0   then return 3, nil
    else                    return 3, "light_edge"
    end
end

-- ── Widget ───────────────────────────────────────────────────────────────────

local ReisenSanityDots = Class(Widget, function(self, owner)
    Widget._ctor(self, "ReisenSanityDots")
    self.owner = owner

    self.dots = {}
    local half = DOT_SPACING * (DOT_COUNT - 1) * 0.5
    for i = 1, DOT_COUNT do
        local dot = self:AddChild(Image(DOT_ATLAS, DOT_TEX))
        dot:SetSize(DOT_SIZE, DOT_SIZE)
        dot:SetPosition(0, half - (i - 1) * DOT_SPACING, 0)
        local c = DARK[i]
        dot:SetTint(c[1], c[2], c[3], c[4])
        self.dots[i] = dot
    end

    self._cur_lights = -1
    self._cur_edge   = "unset"

    self:StartUpdating()
end)

function ReisenSanityDots:OnUpdate(dt)
    if TheNet ~= nil and TheNet:IsServerPaused() then return end
    local owner = self.owner
    if owner == nil then return end

    local pct = 1.0
    if owner.replica ~= nil and owner.replica.sanity ~= nil then
        pct = owner.replica.sanity:GetPercent()
    end

    local lights, edge = pct_to_display(pct)

    -- Only repaint when the display state actually changes.
    if lights == self._cur_lights and edge == self._cur_edge then return end
    self._cur_lights = lights
    self._cur_edge   = edge

    local boundary_dark = (lights > 0 and lights < DOT_COUNT)
        and (DOT_COUNT - lights) or nil

    for i = 1, DOT_COUNT do
        local c
        if edge == "dark_edge" then
            c = EDGE_DARK[i]
        elseif edge == "light_edge" then
            c = EDGE_LIGHT[i]
        else
            local is_light = i > (DOT_COUNT - lights)
            local base = is_light and LIGHT[i] or DARK[i]
            if i == boundary_dark then
                c = {
                    base[1] + (BRIDGE[1] - base[1]) * BOUNDARY_BLEND,
                    base[2] + (BRIDGE[2] - base[2]) * BOUNDARY_BLEND,
                    base[3] + (BRIDGE[3] - base[3]) * BOUNDARY_BLEND,
                    1,
                }
            else
                c = base
            end
        end
        self.dots[i]:SetTint(c[1], c[2], c[3], c[4])
    end
end

return ReisenSanityDots
