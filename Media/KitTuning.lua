-- MelloUI kit tuning -- overrides for Media\KitLayout.lua and Modules\Kit.lua.
--
-- Written by the kit editing tools, which do NOT ship with the addon:
--   * MelloUIKitEditor   the in-game companion addon (drag, resize, recolour
--                        live frames; saves into MelloUIDB and exports here)
--   * tools\kitforge     the desktop tool (edits the source sprites, the
--                        piece geometry and this file)
--
-- The schema is documented in Core\KitTuning.lua. An empty table means the
-- kit behaves exactly as build_kit.py and the replacement library describe
-- it; the addon never writes this file itself.
--
-- Last written by kitforge on 2026-09-22 17:54.

MelloUI_KitTuning = {
	elements = {},
	globals = {},
	pieces = {},
	rules = {},
	schema = 1,
}
