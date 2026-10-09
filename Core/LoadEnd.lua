--------------------------------------------------------------------------------
-- MelloUI - the end of its files (0.19.9, docs/plans/split-addons.md)
--
-- MelloUI.toc's last file, nothing else: the game reads MelloUI's saved
-- settings (the SavedVariables) right after the last file and before
-- ADDON_LOADED, so their time is counted here, under their own name in
-- /melloperf load, not under the last file's (it read 38 ms / 9.5 MB as
-- "WidgetPanel" in the 2026-10-06 reports).
--------------------------------------------------------------------------------

local _, ns = ...
ns.MelloUI.Perf:Scope("the saved settings (read by the game after the last file)")
