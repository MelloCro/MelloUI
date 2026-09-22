--------------------------------------------------------------------------------
-- MelloUI - Edit Mode layout
--
-- The painted reskin is drawn for one arrangement of the HUD: the user's
-- own Edit Mode layout (action bars, side bars, reputation bar, unit and
-- party frames, the two end caps). It ships as the game's share string in
-- Media/EditModeLayout.lua and is put into Edit Mode as an account layout
-- named after it, and made active, when the reskin is switched on (user,
-- 2026-09-22: "if people enable the reskin ... it needs to load my current
-- UI layout"). UI Modifications calls Apply; /mello layout does it by hand.
--
-- Only the C_EditMode API is used, never the manager frame's own methods
-- (Edit Mode code run from addon code taints and errors on secrets): the
-- layouts table is read, the new layout inserted where the game's import
-- dialog would put it (after the last account layout, else after the
-- presets), saved back, and the game told a layout was added. The manager
-- then applies it on its own EDIT_MODE_LAYOUTS_UPDATED. Not in combat.
--
-- C_EditMode.GetLayouts() returns the SAVED layouts only, while its
-- activeLayout and every index the API takes count the presets (Modern,
-- Classic...) first, the way the manager keeps them (a copy of the presets
-- with the saved ones appended, EditModeManager.lua UpdateLayoutInfo). The
-- list is built the same way here (user, 2026-09-22: "no active layout").
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI

local function Data()
	local data = MelloUI_EditModeLayout
	if type(data) ~= "table" or type(data.layout) ~= "string" or data.layout == "" then
		return nil
	end
	return data
end

local function Api()
	return C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts and C_EditMode.ConvertStringToLayoutInfo and true or false
end

local function LayoutType(name)
	return Enum and Enum.EditModeLayoutType and Enum.EditModeLayoutType[name]
end

-- The presets the game puts in front of the saved layouts (a copy).
local function Presets()
	local list = {}
	local manager = EditModePresetLayoutManager
	local source = type(manager) == "table" and type(manager.presetLayoutInfo) == "table" and manager.presetLayoutInfo or {}
	for i, layout in ipairs(source) do
		list[i] = layout
	end
	return list
end

-- The full list the API indexes: presets, then the saved layouts.
local function FullList()
	local ok, info = pcall(C_EditMode.GetLayouts)
	if not (ok and type(info) == "table" and type(info.layouts) == "table") then
		return nil
	end
	local full = Presets()
	local presets = #full
	for _, layout in ipairs(info.layouts) do
		full[#full + 1] = layout
	end
	return full, info, presets
end

-- The active layout as the game's share string, for baking.
function MelloUI:ExportEditModeLayout()
	if not (Api() and C_EditMode.ConvertLayoutInfoToString) then
		return nil, "this client has no Edit Mode layout API"
	end
	local full, info = FullList()
	if not full then
		return nil, "the layouts could not be read"
	end
	local active = full[info.activeLayout]
	if not active then
		return nil, string.format("no active layout (active index %s of %d)", tostring(info.activeLayout), #full)
	end
	local okS, text = pcall(C_EditMode.ConvertLayoutInfoToString, active)
	if not (okS and type(text) == "string") then
		return nil, "the layout could not be converted"
	end
	return text, active.layoutName
end

local pending = false
local waiter = CreateFrame("Frame")
waiter:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	if pending then
		pending = false
		MelloUI:ApplyEditModeLayout()
	end
end)

-- The baked layout into Edit Mode, made active. Returns true, or false and
-- why. `quiet` skips the chat line.
function MelloUI:ApplyEditModeLayout(quiet)
	local data = Data()
	if not data then
		return false, "no layout is baked (Media/EditModeLayout.lua is empty)"
	end
	if not Api() then
		return false, "this client has no Edit Mode layout API"
	end
	if InCombatLockdown() then
		pending = true
		waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
		return false, "in combat; the layout is applied when it ends"
	end
	local full, info, presets = FullList()
	if not full then
		return false, "the layouts could not be read"
	end
	local okC, new = pcall(C_EditMode.ConvertStringToLayoutInfo, data.layout)
	if not (okC and type(new) == "table") then
		return false, "the baked layout string is not readable by this client (re-export it with /mello layout export)"
	end
	local account, preset = LayoutType("Account"), LayoutType("Preset")
	new.layoutType = account or new.layoutType
	new.layoutName = data.name
	local index, replaced
	for i, layout in ipairs(full) do
		if layout.layoutName == data.name and layout.layoutType ~= preset then
			index, replaced = i, true
			full[i] = new
			break
		end
	end
	if not index then
		local last = 0
		for i, layout in ipairs(full) do
			if layout.layoutType == account then
				last = i
			end
		end
		if last == 0 then
			last = presets
		end
		index = last + 1
		table.insert(full, index, new)
	end
	-- saved the way the manager saves: the full list, presets in front
	info.layouts = full
	local okS, err = pcall(C_EditMode.SaveLayouts, info)
	if not okS then
		return false, "the layouts could not be saved: " .. tostring(err)
	end
	if replaced then
		if info.activeLayout ~= index and C_EditMode.SetActiveLayout then
			pcall(C_EditMode.SetActiveLayout, index)
		end
	elseif C_EditMode.OnLayoutAdded then
		pcall(C_EditMode.OnLayoutAdded, index, true, true)
	elseif C_EditMode.SetActiveLayout then
		pcall(C_EditMode.SetActiveLayout, index)
	end
	if not quiet then
		MelloUI:Print("Edit Mode layout '%s' %s and made active.", data.name, replaced and "updated" or "added")
	end
	return true
end

function MelloUI:EditModeLayoutStatus()
	local data = Data()
	if not Api() then
		return "no Edit Mode layout API on this client"
	end
	local full, info, presets = FullList()
	local active = full and full[info.activeLayout]
	local names = {}
	for i, layout in ipairs(full or {}) do
		names[#names + 1] = string.format("%d:%s%s", i, tostring(layout.layoutName), i == info.activeLayout and "*" or "")
	end
	return string.format("baked layout %s (%d chars); Edit Mode: %d presets + %d saved, active %s: %s", data and "'" .. data.name .. "'" or "none",
		data and #data.layout or 0, presets or 0, full and (#full - (presets or 0)) or 0, active and tostring(active.layoutName) or "?", table.concat(names, " "))
end
