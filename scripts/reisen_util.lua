--[[
reisen_util — shared helpers for the Reisen mod.

Single source of truth for "what sanity value should this code use".  Read it
via `require "reisen_util"` from prefab / modmain / widget code.

Convention:
  Any code path that gates BEHAVIOUR or VISUAL state on the wearer's sanity
  must use M.GetEffectiveSanity (server side) so it matches what the player
  sees on the HUD.  Cost deductions still go through Sanity:DoDelta on the
  raw component, but the AFFORDABILITY check that gates them must use the
  effective value -- otherwise nightmare-amulet'd players "spend" hidden
  sanity they cannot see.

  Client widgets that read replica.sanity:GetPercent() do NOT call this:
  the replica already returns the displayed percentage.
==============================================================================
--]]

local M = {}

-- Returns the effective sanity value for `inst`, accounting for:
--   1. inducedinsanity (Nightmare Amulet, starvation)        → 0
--   2. SANITY_MODE_LUNACY (Alter Guardian Hat, etc.)          → enlightenment value
--   3. Otherwise                                              → sanity.current
-- Server-only (reads the authoritative sanity component).  On clients without
-- a real sanity component this returns 0.
function M.GetEffectiveSanity(inst)
	local s = inst ~= nil and inst.components and inst.components.sanity or nil
	if s == nil then return 0 end
	if s.inducedinsanity then return 0 end
	if s:IsLunacyMode() then return s:GetPercent() * s.max end
	return s.current
end

return M
