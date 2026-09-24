--------------------------------------------------------------------------------
-- MelloUI - Options Kit
--
-- (user, 2026-09-24: "and the macros menu, edit mode menu, addons list, and
-- the whole options settings menu"): the game's Options window
-- (SettingsPanel, Blizzard_Settings_Shared: the category list at the left,
-- the settings page at the right, every page of it) dressed in the painted
-- kit on the game's own layout, by the rule book's fixed looks:
--   the window: the outer double rail with its gem corners (no portrait,
--   so all four corners are gems until the title plate takes the top two),
--   the page stone in place of the flat background, the title plate riding
--   the rail with the window's title on it, the close X, B1 red plates on
--   Close / Apply / Defaults, TB6 cards on the Game / AddOns tabs, S1 on the
--   search box;
--   the two areas (the game frames both with one inner-frame picture): an L1
--   box (single rail, list-box stone) round the category list and one round
--   the page, each with the palette's inner panel over its stone
--   (WINDOW-RULES 2e: no small text on brown);
--   the category list: its group headers on the category plate, a
--   category's hover / selected bar on the plate's hover / selected look,
--   its expand toggle on the kit's plus / minus, the scroll bar T2 / H1 / S1;
--   the settings page: the header's divider line, rows striped as the
--   configurator's (CR4) with the plate's hover look on the row under the
--   mouse (where the game lights its own faint hover), section headers on
--   the category plate, the key binding groups' bars on the category plate
--   with the kit's plus / minus, check boxes, SL1 sliders with their arrow
--   steppers, D1 dropdowns with arrow steppers, B1 buttons, key binding
--   buttons on the S1 field (lit while the game listens for a key), the
--   graphics quality box on the single rail with TB6 tabs, the scroll bar.
-- Other addons' own panels (the canvases under the AddOns tab) are never
-- walked into; a row of a template this file does not know stays the game's.
--
-- TAINT (the settings write cvars, key bindings and protected options): the
-- skin is purely visual. It only adds frames and textures of its own and
-- fades the game's ART regions (alpha, Kit:Fade / Kit:Unfade). It never sets
-- a script, never replaces a method, mixin or global, never writes a field
-- onto a Settings frame, control or their data (every note it keeps is in
-- the weak side tables below), never calls a Settings / SettingsPanel
-- function and never moves, sizes, shows or hides one of the game's
-- controls. It follows the game through hooksecurefunc post-hooks and
-- HookScript on the game's own objects, every hook body in pcall. The lists
-- are followed by post-hooking their ScrollBox's Update (no callback is
-- registered in the game's own callback tables) and walking the scroll
-- target's children with the plain widget API. Kit helpers that write a
-- marker onto the game's controls (Kit:SkinCheckButton, SkinRedButton,
-- SkinScrollBar, SkinSearchBox, SkinPanelTab, HookScrollBoxRows) are not
-- used here; their work is done inline with Kit:Replace and a side table.
--
-- /optionsdump [frames | reps | art]: the window's parts, the category list
-- and the current page's rows, and what the skin made of each.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("OptionsPanel", {
	title = "Options Kit",
	desc = "The game's Options window (every settings page) in the kit.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local PAL = MelloUI.Palette

-- Additions to what the game draws, as the configurator has them (user,
-- 2026-09-24: the Options window should feel like MelloUI's configurator):
-- the row stripes (CR4) and a plate under a page's section headers (the game
-- prints those as bare text). Either can be switched off here without
-- touching the rest.
local ADD_STRIPES = true
local ADD_HEADER_PLATES = true

local BOX_OUTSET = 4        -- UI px the L1 boxes reach past the list / page rects, so their rail clears the rows
local FILL_INSET = 5        -- the inner panel inside a box's rail (as the configurator's SEC_FILL_INSET)
local FILL_ALPHA = 0.8      -- WINDOW-RULES 2e: the inner panel at about 0.8 over the stone
local STRIPE_ALPHA = 0.85   -- WINDOW-RULES 2e: stripes in the main window tone at about 0.85
local HEADER_TOP = 11       -- a section header's plate: its top below the header row's top ...
local HEADER_H = 26         -- ... and its height, centred on the game's title text (7, -16 in a 45 px row)

local active = false
local built = false
local reps = {}             -- every replacement, for enable / disable
local syncs = {}            -- followers of the game's state, re-run whenever the skin comes on
local own = {}              -- our own regions shown only while dressed (the title copy)
local loose = {}            -- [game region] = true: art faded outside a replacement (a re-made toggle texture)
local chrome = {}           -- [part name] = its replacement, for the dump
local dressed = setmetatable({}, { __mode = "k" })       -- [game frame] = what we made for it (false: looked at, nothing)
local rowInfo = setmetatable({}, { __mode = "k" })       -- [list row] = { kind = , band = }
local hookedBoxes = setmetatable({}, { __mode = "k" })   -- [ScrollBox] = true
local watched = setmetatable({}, { __mode = "k" })       -- [SettingsPanel] = true
local lists = {}            -- the two ScrollBoxes and their row functions, once found

local function Secret(v)
	return issecretvalue and issecretvalue(v) or false
end

-- the given values without the nils (a table literal with a nil in it stops
-- ipairs there, and the art after it would never be faded)
local function List(...)
	local out = {}
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if v then
			out[#out + 1] = v
		end
	end
	return out
end

-- Kit:Replace, registered for enable / disable; enabled at once while the
-- skin is on. A region the library has no rule for, or a failure, is nil.
local function Replace(region, opts)
	if not (region and Kit and Kit.Replace) then
		return nil
	end
	local ok, rep = pcall(Kit.Replace, Kit, region, opts)
	if not ok or not rep then
		return nil
	end
	reps[#reps + 1] = rep
	if active then
		pcall(rep.Enable, rep)
	end
	return rep
end

-- A follower of the game's state: kept for the next time the skin comes on,
-- and run now if it is on.
local function Follow(fn)
	syncs[#syncs + 1] = fn
	if active then
		pcall(fn)
	end
end

-- A post-hook on one of the game's objects (hooksecurefunc: the game's own
-- call stays secure), doing nothing while the skin is off, its body in pcall.
local function Hook(obj, method, fn)
	if obj and type(obj[method]) == "function" then
		hooksecurefunc(obj, method, function(...)
			if active then
				pcall(fn, ...)
			end
		end)
	end
end

local function HookScript(frame, script, fn)
	if frame and frame.HookScript then
		frame:HookScript(script, function(...)
			if active then
				pcall(fn, ...)
			end
		end)
	end
end

-- An invisible region of OUR frame to hand to Kit:Replace where the game has
-- no art of its own to stand in for (the piece is placed on opts.rect).
local function Anchor(host, layer)
	local tex = host:CreateTexture(nil, layer or "BACKGROUND")
	tex:SetAllPoints(host)
	tex:SetColorTexture(0, 0, 0, 0)
	tex.kitPiece = true   -- ours: never taken for game art by the Kit's finders
	return tex
end

local function FadeLoose(region)
	if region and not loose[region] then
		loose[region] = true
		if active then
			Kit:Fade(region)
		end
	end
end

local function Shown(region)
	local ok, shown = pcall(region.IsShown, region)
	return ok and not Secret(shown) and shown and true or false
end

local function Key(region)
	return (region and Kit:ArtKey(region) or ""):lower()
end

-- the first texture of `frame` whose art is `key` (lower case)
local function FindArt(frame, key)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece and Key(region) == key then
			return region
		end
	end
	return nil
end

-- every game texture of `frame` (none of ours)
local function Textures(frame)
	local out = {}
	if frame then
		for _, region in ipairs({ frame:GetRegions() }) do
			if region:GetObjectType() == "Texture" and not region.kitPiece then
				out[#out + 1] = region
			end
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- The controls, each found by what it IS and dressed once per frame
--------------------------------------------------------------------------------

-- B1: a UIPanelButtonTemplate (Left / Middle / Right file pieces) or a
-- 128-RedButton three-slice on the red plate, as regions of the button
-- (Kit:SkinRedButton's work, without its marker on the button)
local function RedButton(button)
	if not button or dressed[button] ~= nil then
		return
	end
	dressed[button] = false
	local anchor, key
	if button.Center then
		anchor, key = button.Center, "_128-RedButton-Center"
	elseif button.Middle and button.Left and button.Right then
		anchor, key = button.Middle, "UI-Panel-Button-Up"
	end
	if not anchor then
		return
	end
	local extra = List(button.Left, button.Right)
	for _, region in ipairs({ button:GetRegions() }) do
		if region:GetObjectType() == "Texture" and region ~= anchor and region ~= button.Left and region ~= button.Right
			and not region.kitPiece and region:GetDrawLayer() == "HIGHLIGHT" then
			extra[#extra + 1] = region
		end
	end
	dressed[button] = Replace(anchor, { as = key, rect = button, button = button, alsoFade = extra }) or false
end

-- the kit's check box on a SettingsCheckboxTemplate (checkbox-minimal /
-- checkmark-minimal), its state from the button's own checked flag
local function CheckBox(cb)
	if not cb or dressed[cb] ~= nil then
		return
	end
	dressed[cb] = false
	local normal = cb.GetNormalTexture and cb:GetNormalTexture()
	if not normal then
		return
	end
	local extra = {}
	for _, getter in ipairs({ "GetPushedTexture", "GetCheckedTexture", "GetHighlightTexture", "GetDisabledTexture", "GetDisabledCheckedTexture" }) do
		if cb[getter] then
			local tex = cb[getter](cb)
			if tex and tex ~= normal then
				extra[#extra + 1] = tex
			end
		end
	end
	dressed[cb] = Replace(normal, { as = "checkbox-minimal", button = cb, rect = normal, alsoFade = extra }) or false
end

-- A piece of ours dimmed while its button is disabled: the kit's arrows and
-- slider thumb have no disabled look of their own, and the game greys its
-- own art there (the dropdown steppers' disabled atlas, the thumb's alpha).
local function Dim(rep, button)
	if not (rep and button and rep.object and rep.object.SetAlpha) then
		return
	end
	local function Sync()
		local ok, enabled = pcall(button.IsEnabled, button)
		if ok and not Secret(enabled) then
			rep.object:SetAlpha(enabled and 1 or 0.45)
		end
	end
	Hook(button, "SetEnabled", Sync)
	Hook(button, "Enable", Sync)
	Hook(button, "Disable", Sync)
	Follow(Sync)
end

-- an arrow stepper (the slider's Back / Forward with their one texture, a
-- dropdown's WowStyle2 icon button with its Background and Icon): the kit's
-- arrow at its size on the button's art
local function Stepper(button, key, dim)
	if not button or dressed[button] ~= nil then
		return
	end
	dressed[button] = false
	local art = button.Background or Kit:FirstTexture(button)
	if not art then
		return
	end
	local rep = Replace(art, { as = key, button = button, alsoFade = Kit:OtherTextures(button, art) })
	dressed[button] = rep or false
	if rep and dim then
		Dim(rep, button)
	end
end

-- SL1 on a MinimalSliderWithSteppersTemplate (the configurator's slider):
-- the track at the kit piece's own thickness, the gem thumb, the arrows
local function Slider(sw)
	if not sw or dressed[sw] ~= nil then
		return
	end
	dressed[sw] = false
	local track = sw.Slider
	if not track then
		return
	end
	if track.Middle then
		local layout = MelloUI_KitLayout and MelloUI_KitLayout.pieces and MelloUI_KitLayout.pieces["inputs/slider_mid"]
		local natural = layout and layout.box and (layout.box[4] - layout.box[2]) * Kit.scale or nil
		Replace(track.Middle, { as = "_Minimal_SliderBar_Middle", rect = track, fitHeight = natural, alsoFade = List(track.Left, track.Right) })
	end
	local thumb = track.Thumb or (track.GetThumbTexture and track:GetThumbTexture())
	if thumb then
		Dim(Replace(thumb, { as = "Minimal_SliderBar_Button", rect = thumb, button = track }), track)
	end
	-- (the game dims these two by the buttons' own alpha: nothing to add)
	Stepper(sw.Back, "Minimal_SliderBar_Button_Left")
	Stepper(sw.Forward, "Minimal_SliderBar_Button_Right")
	dressed[sw] = true
end

-- D1 on a settings dropdown (SettingsDropdownWithButtonsTemplate: a
-- WowStyle2 dropdown whose Background the game re-atlases with its state,
-- an Arrow it shows on hover) with its two arrow steppers
local function Dropdown(ctrl)
	if not ctrl or dressed[ctrl] ~= nil then
		return
	end
	dressed[ctrl] = false
	local dd = ctrl.Dropdown
	if dd and dd.Background and dd.Text then
		Replace(dd.Background, { as = "common-dropdown-textholder", rect = dd, button = dd, alsoFade = List(dd.Arrow) })
	end
	Stepper(ctrl.DecrementButton, "Minimal_SliderBar_Button_Left", true)
	Stepper(ctrl.IncrementButton, "Minimal_SliderBar_Button_Right", true)
	dressed[ctrl] = true
end

-- T2 / H1 / S1 on a MinimalScrollBar (Kit:SkinScrollBar's work, without its
-- marker on the bar)
local function ScrollBar(bar)
	if not bar or dressed[bar] ~= nil then
		return
	end
	dressed[bar] = false
	local track = bar.Track
	local thumb = track and track.Thumb
	if not (track and thumb and track.Middle and thumb.Middle) then
		return
	end
	local made = List(
		Replace(track.Middle, { as = "minimal-scrollbar-track-middle", rect = track, alsoFade = List(track.Begin, track.End) }),
		Replace(thumb.Middle, { as = "minimal-scrollbar-small-thumb-middle", rect = thumb, button = thumb, alsoFade = List(thumb.Begin, thumb.End) }))
	if bar.Back and bar.Back.Texture then
		Replace(bar.Back.Texture, { as = "minimal-scrollbar-arrow-top", button = bar.Back })
	end
	if bar.Forward and bar.Forward.Texture then
		Replace(bar.Forward.Texture, { as = "minimal-scrollbar-arrow-bottom", button = bar.Forward })
	end
	-- the thumb's height follows the content: the slab refits with it
	HookScript(thumb, "OnSizeChanged", function()
		for _, rep in ipairs(made) do
			if rep.vstrip and rep.object:IsShown() then
				rep:Refit()
			end
		end
	end)
	dressed[bar] = true
end

-- TB6 on a MinimalTabTemplate (Left / Middle / Right re-atlased by the game
-- between Options_Tab_* and Options_Tab_Active_*): the stone card with the
-- single rail, its iron lit gold while the tab is the selected one. The tab's
-- text stays where the game puts it.
local function Tab(tab)
	if not (tab and tab.Left and tab.Middle and tab.Right) or dressed[tab] ~= nil then
		return
	end
	dressed[tab] = false
	local plain = Replace(tab.Left, { as = "uiframe-tab-left", rect = tab, button = tab, alsoFade = List(tab.Middle, tab.Right) })
	local open = Replace(tab.Left, { as = "uiframe-activetab-left", rect = tab, noFade = true })
	dressed[tab] = plain or open or false
	local function Sync()
		local selected = Key(tab.Left):find("active", 1, true) ~= nil
		if plain then
			plain.object:SetShown(not selected)
		end
		if open then
			open.object:SetShown(selected)
		end
	end
	Hook(tab.Left, "SetAtlas", Sync)
	Follow(Sync)
end

-- a key binding button (UIMenuButtonStretchTemplate: nine silver file
-- pieces): the S1 field without its search glass (a key sits in it, not a
-- search), its focused look while the game listens for a key on it (the
-- game's SelectedHighlight) and under the mouse
local SILVER = { "TopLeft", "TopRight", "BottomLeft", "BottomRight", "TopMiddle", "MiddleLeft", "MiddleRight", "BottomMiddle" }
local function BindingButton(b)
	if not b or dressed[b] ~= nil then
		return
	end
	dressed[b] = false
	if not b.MiddleMiddle then
		return
	end
	local extra = {}
	for _, key in ipairs(SILVER) do
		if b[key] then
			extra[#extra + 1] = b[key]
		end
	end
	local highlight = b.GetHighlightTexture and b:GetHighlightTexture()
	if highlight then
		extra[#extra + 1] = highlight
	end
	-- (the custom binding button, voice push-to-talk, spells the key in lower case)
	local selected = b.SelectedHighlight or b.selectedHighlight
	if selected then
		extra[#extra + 1] = selected
	end
	local rep = Replace(b.MiddleMiddle, { as = "UI-ChatInputBorder-Mid2", rect = b, dropCap = "l", alsoFade = extra })
	dressed[b] = rep or false
	if not rep then
		return
	end
	local over = false
	local function Sync()
		local listening = selected and Shown(selected)
		rep:SetState((listening or over) and "focused" or "normal")
	end
	HookScript(b, "OnEnter", function() over = true; Sync() end)
	HookScript(b, "OnLeave", function() over = false; Sync() end)
	if selected then
		Hook(selected, "Show", Sync)
		Hook(selected, "Hide", Sync)
		Hook(selected, "SetShown", Sync)
	end
	Follow(Sync)
end

-- the plus / minus on a toggle the game re-textures with its state (a
-- category's expand toggle: common-button-dropdown-closed / -open set as its
-- normal texture): one kit glyph per state, the one for the current art shown
local function Toggle(t)
	if not t or dressed[t] ~= nil then
		return
	end
	dressed[t] = false
	local normal = t.GetNormalTexture and t:GetNormalTexture()
	if not normal then
		return
	end
	local plus = Replace(normal, { as = "common-button-list-plus", button = t, rect = t,
		alsoFade = List(t.GetPushedTexture and t:GetPushedTexture(), t.GetHighlightTexture and t:GetHighlightTexture()) })
	local minus = Replace(normal, { as = "common-button-list-minus", button = t, rect = t, noFade = true })
	dressed[t] = plus or minus or false
	local function Sync()
		-- a texture the game made anew with SetNormalTexture / SetPushedTexture is faded too
		local n = t:GetNormalTexture()
		if n and not Kit.faded[n] then
			FadeLoose(n)
		end
		local p = t.GetPushedTexture and t:GetPushedTexture()
		if p and not Kit.faded[p] then
			FadeLoose(p)
		end
		local key = Key(n)
		local open = key:find("open", 1, true) ~= nil or key:find("minus", 1, true) ~= nil
		if plus then
			plus.object:SetShown(not open)
		end
		if minus then
			minus.object:SetShown(open)
		end
	end
	Hook(t, "SetNormalTexture", Sync)
	Hook(t, "SetPushedTexture", Sync)
	Follow(Sync)
end

--------------------------------------------------------------------------------
-- List rows
--------------------------------------------------------------------------------

-- A frame of ours one level under a row: the row's stripe and hover plate
-- are its regions, so they lie under everything the row draws (a key binding
-- row's label is in its BACKGROUND layer) and nothing is added to the row's
-- own layer stack.
local function Underlay(row)
	local u = CreateFrame("Frame", nil, row)
	u:SetAllPoints(row)
	u:EnableMouse(false)
	u:SetFrameLevel(math.max(row:GetFrameLevel() - 1, 0))
	return u
end

-- CR4's faint band (WINDOW-RULES 2e: the main window tone on the inner
-- panel), shown on every other row by the list pass
local function Band(u, row)
	if not ADD_STRIPES then
		return nil
	end
	local band = u:CreateTexture(nil, "BACKGROUND", nil, -8)
	band:SetAllPoints(row)
	local c = PAL.mainWindow
	band:SetColorTexture(c[1], c[2], c[3], STRIPE_ALPHA)
	band.kitPiece = true
	band:Hide()
	return band
end

-- the plate's hover look on a row while the game shows its own hover
-- (`sources`: the faint textures it shows on hover, faded)
local function HoverPlate(row, u, sources)
	local rep = Replace(Anchor(u), { as = "FriendsRowHighlight", rect = row, noFade = true, alsoFade = sources })
	if not rep then
		return nil
	end
	local function Sync()
		local on = false
		for _, tex in ipairs(sources) do
			if Shown(tex) then
				on = true
			end
		end
		rep.object:SetShown(on)
	end
	for _, tex in ipairs(sources) do
		Hook(tex, "Show", Sync)
		Hook(tex, "Hide", Sync)
		Hook(tex, "SetShown", Sync)
	end
	Follow(Sync)
	return rep
end

-- the check boxes, sliders, dropdowns and buttons a settings control carries
-- (by the game templates' own keys only: a row of an addon's own template is
-- not searched)
local function DressBits(f)
	if f.Checkbox then
		CheckBox(f.Checkbox)
	end
	if f.SliderWithSteppers then
		Slider(f.SliderWithSteppers)
	end
	if f.Control and f.Control.Dropdown then
		Dropdown(f.Control)
	end
	for _, key in ipairs({ "Button", "ToggleTest", "OpenAccessButton" }) do
		local b = f[key]
		if b and b.GetObjectType and b:GetObjectType() == "Button" and b.Left and b.Middle and b.Right then
			RedButton(b)
		end
	end
end

-- a page's section header (SettingsListSectionHeaderTemplate: its title as
-- bare text): the category plate under the title
local function HeaderPlate(row)
	local u = Underlay(row)
	local rect = CreateFrame("Frame", nil, u)
	rect:EnableMouse(false)
	rect:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -HEADER_TOP)
	rect:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -HEADER_TOP)
	rect:SetHeight(HEADER_H)
	return Replace(Anchor(u), { as = "LFGBrowse-Grouping", rect = rect, noFade = true })
end

-- an expandable section's bar (the key binding groups: Options_ListExpand
-- Left / middle / Right, the Right re-atlased _Expanded when open): the
-- category plate on the bar, the kit's plus / minus on its right end
local function Expandable(row)
	local bar = row.Button
	local mid
	for _, region in ipairs({ bar:GetRegions() }) do
		if region:GetObjectType() == "Texture" and region ~= bar.Left and region ~= bar.Right and not region.kitPiece then
			mid = mid or region
		end
	end
	Replace(bar.Left, { as = "LFGBrowse-Grouping", rect = bar, alsoFade = List(mid, bar.Right) })
	local plus = Replace(bar.Right, { as = "common-button-list-plus", button = bar, noFade = true })
	local minus = Replace(bar.Right, { as = "common-button-list-minus", button = bar, noFade = true })
	local function Sync()
		local open = Key(bar.Right):find("expanded", 1, true) ~= nil
		if plus then
			plus.object:SetShown(not open)
		end
		if minus then
			minus.object:SetShown(open)
		end
	end
	Hook(bar.Right, "SetAtlas", Sync)
	Follow(Sync)
end

-- the graphics page's quality box (SettingsAdvancedQualitySectionTemplate:
-- a NineSlice round two sets of controls, the Base / Raid tabs over it)
local function Graphics(row)
	local nine = row.NineSlice
	if nine then
		local host = CreateFrame("Frame", nil, row)
		host:EnableMouse(false)
		Replace(Anchor(host), { as = "common-insideframe", parent = row, rect = nine, level = 0, body = false, noFade = true, alsoFade = Textures(nine) })
	end
	Tab(row.BaseTab)
	Tab(row.RaidTab)
	for _, set in ipairs(List(row.BaseQualityControls, row.RaidQualityControls)) do
		for _, control in ipairs(set.Controls or {}) do
			DressBits(control)
		end
	end
end

-- which game template a settings-list row is, by its template's own keys
local function RowKind(row)
	if row.BaseQualityControls or row.RaidQualityControls then
		return "graphics"
	elseif row.Button1 and row.Button2 and row.Highlight then
		return "binding"
	elseif row.Tooltip and row.Text then
		return "setting"
	elseif row.Button and row.Button.Left and row.Button.Right and row.Button.Text then
		return "section"
	elseif row.Title and row.MouseoverOverlay then
		return "search"
	elseif row.Title and row.NewFeature then
		return "header"
	end
	return nil
end

local function SettingsRow(row)
	if dressed[row] ~= nil then
		return
	end
	local kind = RowKind(row)
	dressed[row] = kind or false
	if not kind then
		return
	end
	local info = { kind = kind }
	rowInfo[row] = info
	if kind == "setting" then
		local u = Underlay(row)
		info.band = Band(u, row)
		HoverPlate(row, u, List(row.Tooltip and row.Tooltip.HoverBackground, row.Checkbox and row.Checkbox.HoverBackground))
		DressBits(row)
	elseif kind == "binding" then
		local u = Underlay(row)
		info.band = Band(u, row)
		HoverPlate(row, u, List(row.Highlight))
		BindingButton(row.Button1)
		BindingButton(row.Button2)
	elseif kind == "search" then
		HoverPlate(row, Underlay(row), List(row.MouseoverOverlay))
	elseif kind == "header" then
		if ADD_HEADER_PLATES then
			HeaderPlate(row)
		end
	elseif kind == "section" then
		Expandable(row)
	elseif kind == "graphics" then
		Graphics(row)
	end
end

-- which template a category-list row is
local function CategoryKind(row)
	if row.Toggle and row.Texture and row.Label then
		return "category"
	elseif row.Background and row.Label then
		return "group"
	end
	return nil
end

local function CategoryRow(row)
	if dressed[row] ~= nil then
		return
	end
	local kind = CategoryKind(row)
	dressed[row] = kind or false
	if kind == "group" then
		-- a group header (Options_CategoryHeader_1..3): the category plate
		Replace(row.Background, { as = "LFGBrowse-Grouping", rect = row })
	elseif kind == "category" then
		-- a category's bar (its Texture: Options_List_Hover under the mouse,
		-- Options_List_Active when selected, hidden otherwise): the plate's
		-- hover / selected look, following the game's Show / Hide and atlas
		local rep = Replace(row.Texture, { as = "questlog-quest-glow-yellow", rect = row })
		if rep then
			local function Sync()
				rep:SetState(Key(row.Texture):find("active", 1, true) and "selected" or "hover")
				rep.object:SetShown(Shown(row.Texture))
			end
			Hook(row.Texture, "SetAtlas", Sync)
			Hook(row.Texture, "Show", Sync)
			Hook(row.Texture, "Hide", Sync)
			Hook(row.Texture, "SetShown", Sync)
			Follow(Sync)
		end
		Toggle(row.Toggle)
	end
end

-- a list's pass, after each of the game's own updates: rows not seen yet are
-- dressed, the stripes follow the rows' places in the list
local function Pass(scrollBox, rowFn)
	local target = scrollBox and scrollBox.ScrollTarget
	if not target then
		return
	end
	for _, row in ipairs({ target:GetChildren() }) do
		pcall(rowFn, row)
		local info = rowInfo[row]
		if info then
			if info.kind == "binding" and row.CustomButton then
				pcall(BindingButton, row.CustomButton)
			end
			if info.band then
				local even = false
				local order = row.GetOrderIndex
				if type(order) == "function" then
					local ok, index = pcall(order, row)
					if ok and type(index) == "number" and not Secret(index) then
						even = index % 2 == 0
					end
				end
				info.band:SetShown(active and even)
			end
		end
	end
end

local function Passes()
	for _, entry in ipairs(lists) do
		pcall(Pass, entry.box, entry.rowFn)
	end
end

local function HookList(scrollBox, rowFn)
	if not scrollBox or hookedBoxes[scrollBox] then
		return
	end
	hookedBoxes[scrollBox] = true
	lists[#lists + 1] = { box = scrollBox, rowFn = rowFn }
	local function Run()
		Pass(scrollBox, rowFn)
	end
	Hook(scrollBox, "Update", Run)
	Hook(scrollBox, "ReinitializeFrames", Run)
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

-- a frame of ours `BOX_OUTSET` px round a list / page rect: the L1 box's rail
-- lies on it, clear of the rows
local function BoxRect(parent, target)
	local f = CreateFrame("Frame", nil, parent)
	f:EnableMouse(false)
	f:SetPoint("TOPLEFT", target, "TOPLEFT", -BOX_OUTSET, BOX_OUTSET)
	f:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", BOX_OUTSET, -BOX_OUTSET)
	return f
end

-- WINDOW-RULES 2e (user, 2026-09-24: "too much small text over a plain
-- brown border is just an eye strain"): the palette's inner panel over the
-- box's stone inside its rail, a region of the kit's own skin frame (above
-- its stone body, under its rails), so it comes and goes with the box
local function InnerPanel(rep)
	local skin = rep and rep.skin
	if not skin then
		return
	end
	local fill = skin:CreateTexture(nil, "BACKGROUND", nil, 1)
	fill:SetPoint("TOPLEFT", skin, "TOPLEFT", FILL_INSET, -FILL_INSET)
	fill:SetPoint("BOTTOMRIGHT", skin, "BOTTOMRIGHT", -FILL_INSET, FILL_INSET)
	local c = PAL.innerPanel
	fill:SetColorTexture(c[1], c[2], c[3], FILL_ALPHA)
	fill.kitPiece = true
end

local function BuildChrome(SP)
	-- a frame of ours over the window for the anchors the pieces are handed
	local host = CreateFrame("Frame", nil, SP)
	host:SetAllPoints(SP)
	host:EnableMouse(false)

	-- the outer border (the NineSlice, ButtonFrameTemplateNoPortrait): the
	-- double rail grown outward, all four gem corners (no portrait ring); its
	-- pieces are faded one by one, the frame itself is left alone
	local nine = SP.NineSlice
	chrome.outer = Replace(Anchor(host), { as = "NineSlicePanelTemplate", parent = SP, rect = SP, body = false, noFade = true,
		alsoFade = Textures(nine) })

	-- the flat background (FlatPanelBackgroundTemplate at frame level 0): the
	-- page stone as a region of it, inside the outer rail's bevel (one
	-- background for the window: the rail above carries no body)
	local bgArt = Textures(SP.Bg)
	if bgArt[1] then
		local first = table.remove(bgArt, 1)
		chrome.page = Replace(first, { as = "UI-Background-Rock", parent = SP.Bg, rect = SP, inset = Kit:OuterRailInset(), alsoFade = bgArt })
	end

	-- the title plate riding the outer rail. The game's title string stays
	-- where it is (faded): a copy of ours stands on the plate, following the
	-- game's SetText, so none of the game's strings is moved
	local band = CreateFrame("Frame", nil, SP)
	band:SetPoint("TOPLEFT", SP, "TOPLEFT", 0, 0)
	band:SetPoint("TOPRIGHT", SP, "TOPRIGHT", 0, 0)
	band:SetHeight(20)
	band:EnableMouse(false)
	band:SetFrameLevel(SP:GetFrameLevel() + 3)   -- the plate (one under the band) above the outer rail, the text above the plate
	local title = band:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("CENTER", band, "CENTER")
	title:SetShown(active)
	band.TitleText = title   -- the TitleBar look centres the plate's `TitleText` (our own string)
	own[#own + 1] = title
	local gameTitle = nine and nine.Text
	if gameTitle then
		local function Copy()
			local ok, text = pcall(gameTitle.GetText, gameTitle)
			if ok and not Secret(text) then
				title:SetText(text or "")
			end
		end
		Hook(gameTitle, "SetText", Copy)
		Follow(Copy)
	end
	chrome.title = Replace(Anchor(band), { as = "TitleBar", parent = band, rect = band, fitHeight = 20, level = -1, noFade = true,
		alsoFade = List(gameTitle) })

	-- the close X
	local close = SP.ClosePanelButton
	local normal = close and close.GetNormalTexture and close:GetNormalTexture()
	if normal then
		chrome.close = Replace(normal, { as = "RedButton-Exit", button = close, alsoFade = Kit:OtherTextures(close, normal) })
	end

	-- Close / Apply, the Game / AddOns tabs
	RedButton(SP.CloseButton)
	RedButton(SP.ApplyButton)
	Tab(SP.GameTab)
	Tab(SP.AddOnsTab)

	-- the search box: S1, its left end plain and the game's own magnifier
	-- left on it (the kit's glass cap would need the text moved past it)
	local search = SP.SearchBox
	if search and search.Middle then
		chrome.search = Replace(search.Middle, { as = "common-search-border-middle", rect = search, edit = search, dropCap = "l",
			alsoFade = List(search.Left, search.Right) })
	end

	-- the two areas the game frames with one picture (Options_InnerFrame): an
	-- L1 box round the category list, one round the page, each a holder at
	-- that frame's own level (under its rows), the inner panel on its stone
	local inner = FindArt(SP, "options_innerframe")
	local cats = SP.CategoryList
	if cats then
		chrome.categoryBox = Replace(inner or Anchor(host), { as = "Professions-background-summarylist", parent = cats,
			rect = BoxRect(host, cats), level = 0, noFade = not inner })
		InnerPanel(chrome.categoryBox)
		ScrollBar(cats.ScrollBar)
		HookList(cats.ScrollBox, CategoryRow)
	end
	local container = SP.Container
	if container then
		chrome.pageBox = Replace(Anchor(host), { as = "Professions-background-summarylist", parent = container,
			rect = BoxRect(host, container), level = 0, noFade = true })
		InnerPanel(chrome.pageBox)
		local list = container.SettingsList
		local header = list and list.Header
		if header then
			local divider = FindArt(header, "options_horizontaldivider")
			if divider then
				chrome.divider = Replace(divider, { as = "UI-Character-Info-ScrollLine" })
			end
			RedButton(header.DefaultsButton)
		end
		if list then
			ScrollBar(list.ScrollBar)
			HookList(list.ScrollBox, SettingsRow)
		end
	end
end

local function Build(SP)
	if built or not SP then
		return
	end
	built = true
	BuildChrome(SP)
	Passes()
end

-- The window may be made late (load on demand) and is laid out when first
-- shown: dressed then, its lists walked again once the game has filled them
local function Watch(SP)
	if not SP or watched[SP] then
		return
	end
	watched[SP] = true
	SP:HookScript("OnShow", function()
		if not active then
			return
		end
		pcall(Build, SP)
		C_Timer.After(0, function()
			if active then
				Passes()
			end
		end)
	end)
end

local function Activate()
	if active then
		return
	end
	local SP = _G.SettingsPanel
	if SP then
		Watch(SP)
		pcall(Build, SP)
	end
	active = true
	for _, rep in ipairs(reps) do
		pcall(rep.Enable, rep)
	end
	for region in pairs(loose) do
		Kit:Fade(region)
	end
	for _, obj in ipairs(own) do
		obj:Show()
	end
	for _, fn in ipairs(syncs) do
		pcall(fn)
	end
	Passes()
end

-- switched off: every piece hidden, every faded region of the game's shown
-- again at full alpha; nothing of the game's was moved, so nothing else is
-- put back
local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, rep in ipairs(reps) do
		pcall(rep.Disable, rep)
	end
	for region in pairs(loose) do
		Kit:Unfade(region)
	end
	for _, obj in ipairs(own) do
		obj:Hide()
	end
	for _, info in pairs(rowInfo) do
		if info.band then
			info.band:Hide()
		end
	end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function()
	local SP = _G.SettingsPanel
	if active and SP and not built then
		Watch(SP)
		pcall(Build, SP)
		for _, fn in ipairs(syncs) do
			pcall(fn)
		end
	end
end)

function M:OnEnable(db)
	self.db = db
	Activate()
end

function M:OnDisable()
	Deactivate()
end

--------------------------------------------------------------------------------
-- /optionsdump [frames | reps | art]: the window's parts and what the skin
-- made of them, the category list, the current page's rows (kind, label,
-- the controls in it and whether each was dressed). Opens the copy window.
--------------------------------------------------------------------------------

local function Mark(obj)
	if not obj then
		return "-"
	end
	local d = dressed[obj]
	if d == nil then
		return "not seen"
	end
	return d and "kit" or "left"
end

local function RepMark(rep)
	if not rep then
		return "none"
	end
	local ok, shown = pcall(rep.object.IsShown, rep.object)
	return (ok and shown) and "shown" or "hidden"
end

local function Text(fs)
	if not (fs and fs.GetText) then
		return nil
	end
	local ok, text = pcall(fs.GetText, fs)
	if ok and text ~= nil and not Secret(text) then
		return tostring(text)
	end
	return nil
end

local function RowLabel(row)
	return Text(row.Text) or Text(row.Label) or Text(row.Title) or (row.Button and Text(row.Button.Text)) or ""
end

local function RowParts(row)
	local parts = {}
	local function Add(label, obj)
		if obj then
			parts[#parts + 1] = label .. "=" .. Mark(obj)
		end
	end
	Add("check", row.Checkbox)
	Add("slider", row.SliderWithSteppers)
	Add("dropdown", row.Control and row.Control.Dropdown and row.Control)
	Add("button", row.Button and row.Button.Middle and row.Button)
	Add("bind1", row.Button1)
	Add("bind2", row.Button2)
	Add("custom", row.CustomButton)
	Add("baseTab", row.BaseTab)
	Add("raidTab", row.RaidTab)
	local info = rowInfo[row]
	if info and info.band then
		parts[#parts + 1] = "stripe=" .. (info.band:IsShown() and "on" or "off")
	end
	return table.concat(parts, " ")
end

local function DumpRows(scrollBox, kindFn, title)
	local target = scrollBox and scrollBox.ScrollTarget
	if not target then
		MelloUI:Print("%s: no list", title)
		return
	end
	local shownRows, hidden = 0, 0
	MelloUI:Print("%s:", title)
	for _, row in ipairs({ target:GetChildren() }) do
		if Shown(row) then
			shownRows = shownRows + 1
			local okT, top = pcall(row.GetTop, row)
			MelloUI:Print("  %-9s %-8s y=%s  %-32s %s", tostring(kindFn(row) or "unknown"), Mark(row),
				(okT and top and not Secret(top)) and string.format("%.0f", top) or "?", RowLabel(row):sub(1, 32), RowParts(row))
		else
			hidden = hidden + 1
		end
	end
	MelloUI:Print("  %d rows shown, %d pooled / hidden", shownRows, hidden)
end

SLASH_MELLOOPTIONSDUMP1 = "/optionsdump"
SlashCmdList.MELLOOPTIONSDUMP = function(msg)
	msg = (msg or ""):lower()
	MelloUI:ClearLog()
	local SP = _G.SettingsPanel
	if not SP then
		MelloUI:Print("/optionsdump: no SettingsPanel on this client yet (the Options window is made when its addon loads)")
		MelloUI:ShowLog("optionsdump")
		return
	end
	if msg == "frames" or msg == "reps" or msg == "art" then
		Kit:DumpWindow(SP, msg == "reps" and { reps = reps } or nil, msg ~= "art" and msg or nil)
		MelloUI:ShowLog("optionsdump " .. msg)
		return
	end
	local okR, _, _, w, h = pcall(SP.GetRect, SP)
	MelloUI:Print("SettingsPanel: shown %s, %s x %s, strata %s, level %d; kit %s, built %s, %d pieces, %d followers",
		tostring(SP:IsShown()), (okR and w and not Secret(w)) and string.format("%.0f", w) or "?",
		(okR and h and not Secret(h)) and string.format("%.0f", h) or "?", tostring(SP:GetFrameStrata()), SP:GetFrameLevel(),
		active and "on" or "off", tostring(built), #reps, #syncs)
	MelloUI:Print("Chrome:")
	for _, part in ipairs({ "outer", "page", "title", "close", "search", "categoryBox", "pageBox", "divider" }) do
		MelloUI:Print("  %-12s %s", part, RepMark(chrome[part]))
	end
	local list = SP.Container and SP.Container.SettingsList
	local header = list and list.Header
	MelloUI:Print("  Close %s, Apply %s, Defaults %s, Game tab %s, AddOns tab %s", Mark(SP.CloseButton), Mark(SP.ApplyButton),
		Mark(header and header.DefaultsButton), Mark(SP.GameTab), Mark(SP.AddOnsTab))
	MelloUI:Print("  scroll bars: categories %s, page %s", Mark(SP.CategoryList and SP.CategoryList.ScrollBar), Mark(list and list.ScrollBar))
	MelloUI:Print("The window's own art:")
	for _, region in ipairs({ SP:GetRegions() }) do
		if region:GetObjectType() == "Texture" then
			local okA, alpha = pcall(region.GetAlpha, region)
			MelloUI:Print("  %s alpha %s shown %s", tostring(Kit:ArtKey(region)), (okA and not Secret(alpha)) and string.format("%.2f", alpha) or "?",
				tostring(Shown(region)))
		end
	end
	DumpRows(SP.CategoryList and SP.CategoryList.ScrollBox, CategoryKind, "Category list")
	local canvas = SP.Container and SP.Container.SettingsCanvas
	MelloUI:Print("Page: %s  (list %s, addon canvas %s: canvases are never dressed)", Text(header and header.Title) or "?",
		list and (Shown(list) and "shown" or "hidden") or "-", canvas and (Shown(canvas) and "shown" or "hidden") or "-")
	DumpRows(list and list.ScrollBox, RowKind, "Page rows")
	MelloUI:ShowLog("optionsdump")
end
