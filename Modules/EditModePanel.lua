--------------------------------------------------------------------------------
-- MelloUI - Edit Mode Kit
--
-- (user, 2026-09-24: "and the macros menu, edit mode menu, addons list, and
-- the whole options settings menu"): Edit Mode's settings window and the
-- layout dialogs in the painted kit (Modules/Kit.lua), on the game's own
-- layout:
--   the HUD Edit Mode window (EditModeManagerFrame): the window shell as any
--   kit window -- the outer double rail grown outward with its stone, the
--   title plate riding the rail with the title on it, the close button --
--   the layout dropdown on the D1 plate, the check boxes the kit's, the grid
--   spacing slider SL1, the options list's border the single rail with the
--   palette's inner panel inside it (WINDOW-RULES 2e: no small text on the
--   brown stone), its Frames / Combat / Misc headings on the header plate,
--   its scroll bar the kit's, the "Expand / Collapse options" line the
--   divider strip, Revert All Changes / Save on the red plates;
--   the settings dialog of a selected HUD element (EditModeSystemSettingsDialog)
--   the same shell, its setting rows on the inner panel inside a single
--   rail, its pooled sliders, dropdowns and check boxes, its Revert Changes /
--   Reset To Default Position / extra buttons and their divider;
--   the small layout dialogs (new / rename / delete layout, import, unsaved
--   changes) the dialog look of Modules/DialogPanel.lua: the single rail with
--   its stone, red plate buttons, the kit check box, the name box on the edit
--   plate, the import box's border the single rail.
-- The "i" help button (a picture button) stays the game's; it sits over the
-- rail's top-left corner where a portrait ring would be (the title plate's
-- caps take the top corners, so no gem is under it).
--
-- EDIT MODE IS THE MOST TAINT-SENSITIVE UI IN THE GAME (the manager moves the
-- protected action bars, saves layouts and runs in secure code paths): an
-- addon that writes into it leaves tainted state behind, and the player then
-- gets "Interface action failed because of an AddOn" when saving a layout or
-- entering combat. So this module is PURELY VISUAL and follows these rules:
--   * Nothing of Edit Mode's is moved, sized, scaled, shown, hidden,
--     re-parented or re-scripted, no method or global is replaced, and no
--     field is ever written onto its frames, controls or mixins: all state
--     lives in weak tables here, keyed by the game's frame.
--   * Its functions are never called (only getters: GetText, GetWidth, ...).
--   * Hooks are post-hooks only (HookScript, hooksecurefunc), their bodies in
--     pcall, and they leave the game's code path as it was.
--   * The game's ART is faded with alpha (SetAlpha 0, held by a secure
--     post-hook on SetAlpha), its title string too (re-drawn on the plate);
--     nothing else of the game's is changed.
--   * The manager and the settings dialog are ResizeLayoutFrames: their
--     Layout() takes EVERY shown child frame and region into their size, and
--     skipping one needs a field on it (`ignoreInLayout`) that their secure
--     layout would then read -- tainted. So nothing is ever made on those two
--     frames, nor on any other layout frame of Edit Mode (the options list,
--     its containers, the setting rows, the check button rows): the window
--     shells are frames of our own under UIParent, laid on the window's rect
--     (SetAllPoints to it: our frame is anchored, theirs is untouched), and a
--     control's kit piece is made on the control itself (the CheckButton, the
--     dropdown, the slider, the button), which is not a layout frame and
--     whose size nothing reads from its children.
--   * Kit:Replace is used only on paths that keep to this: its parent is
--     always the control itself or a frame that is no layout frame (checked
--     per call below), and no rule that re-anchors or re-sizes a game control
--     is used (no StatusBar brackets, no icon fitting, no text insets). Its
--     helpers that mark the control (Kit:SkinRedButton, SkinCheckButton,
--     SkinScrollBar write `melloRep` onto it) are re-done here without the mark.
-- Switching the module off hides every piece and gives the faded art back its
-- alpha: the window looks exactly as the game draws it. The hooks stay (post-
-- hooks cannot be removed) but do nothing while the module is off. Each
-- window is dressed the first time it shows, never at login (Activate).
--
-- /editmodedump [manager | dialog | layout | import | unsaved | all]: what a
-- window is made of (regions, children), what the kit made of it, and any
-- error a hook caught; opens the copy window.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("EditModePanel")
local hooksecurefunc = Perf.hooksecurefunc
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("EditModePanel", {
	title = "Edit Mode Kit",
	desc = "Edit Mode's settings window and the layout dialogs in the kit.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local active = false
local reps = {}                                           -- every replacement, for enable / disable
local skinned = setmetatable({}, { __mode = "k" })        -- [game control] = what it became (a rep, a list, or false: looked at, nothing to do)
local kinds = setmetatable({}, { __mode = "k" })          -- [game control] = "check" | "button" | ... (for the dump)
local shells = setmetatable({}, { __mode = "k" })         -- [manager / settings dialog] = its shell (our root, rail, title plate, dividers) or false
local smalls = setmetatable({}, { __mode = "k" })         -- [layout dialog] = { nine } or false
local fadedArt = setmetatable({}, { __mode = "k" })       -- [window] = { [the game's region we faded] = true }
local faded = setmetatable({}, { __mode = "k" })          -- [game region] = true while we hold it at alpha 0
local alphaHooked = setmetatable({}, { __mode = "k" })    -- [game region] = true once its SetAlpha is post-hooked
local hooked = setmetatable({}, { __mode = "k" })         -- [game frame] = true once its show / hide are followed
local sections = {}                                       -- the manager's heading plates: { strip, frame }
local missing = {}                                        -- rule keys Kit:Replace had no piece for
local errors = {}                                         -- the first errors the guarded code caught, for the dump
local MAX_ERRORS = 10

-- the title plate's height: a standard window's title bar (PortraitFrameTemplate's
-- TitleContainer, 20 px) times the TitleBar rule's heightScale, so the plate is
-- the one every other kit window carries
local TITLE_BAR_H = 20
-- a heading's plate: its painted box this share of the heading row's height
-- (the row is 32 px for a 16 px GameFontNormalLarge line)
local SECTION_FIT = 0.75
-- the inner panel under text (WINDOW-RULES 2e, user 2026-09-24: "too much small
-- text over a plain brown border is just an eye strain"): the palette's inner
-- panel at the configurator's alpha (Core/Config.lua SEC_FILL_ALPHA), inside
-- its rail by the share of the rail's thickness the AddOn list uses
local PANEL_ALPHA = 0.8
local PANEL_IN_RAIL = 0.6
-- the settings dialog's rows panel: the rows' rect grown by this much (the
-- dialog keeps 20 px round its content -- its widthPadding 40 -- and 12 px
-- between the title, the rows and the buttons), so its rail clears the rows'
-- labels and still stands off the dialog's edge and the buttons
local ROWS_PAD_X, ROWS_PAD_Y = 14, 8
-- the level our window shell takes when the window sits too low in its strata
-- to have room under it: one strata lower, high in it (under the window whatever
-- the levels, above that strata's usual content)
local FALLBACK_LEVEL = 9000
local STRATA_BELOW = {
	TOOLTIP = "FULLSCREEN_DIALOG", FULLSCREEN_DIALOG = "FULLSCREEN", FULLSCREEN = "DIALOG",
	DIALOG = "HIGH", HIGH = "MEDIUM", MEDIUM = "LOW", LOW = "BACKGROUND",
}
-- the small dialogs of Edit Mode (EditModeDialogs.xml); the import-link one is
-- commented out in this client's XML and dressed only if a client has it
local SMALL_DIALOGS = { "EditModeLayoutDialog", "EditModeImportLayoutDialog", "EditModeUnsavedChangesDialog", "EditModeImportLayoutLinkDialog" }

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe and MelloUI.Safe.IsSecret or issecretvalue

local function Note(err)
	if #errors < MAX_ERRORS then
		errors[#errors + 1] = tostring(err)
	end
end

-- a hook body: whatever goes wrong in it stays in it (noted for the dump), so
-- no error of ours ever reaches the game's code that fired the hook
local function Guard(fn)
	return function(...)
		local ok, err = pcall(fn, ...)
		if not ok then
			Note(err)
		end
	end
end

-- a number read from a game frame, or nil when it is unreadable or secret
local function Read(obj, method)
	if not (obj and obj[method]) then
		return nil
	end
	local ok, v = pcall(obj[method], obj)
	if not ok or Secret(v) or type(v) ~= "number" then
		return nil
	end
	return v
end

local function Replace(region, opts)
	if not (region and Kit and Kit.Replace) then
		return nil
	end
	local ok, rep, key = pcall(Kit.Replace, Kit, region, opts)
	if not ok then
		Note(rep)
		return nil
	end
	if not rep then
		if key then
			missing[tostring(key)] = true
		end
		return nil
	end
	reps[#reps + 1] = rep
	if active then
		local okE, err = pcall(rep.Enable, rep)
		if not okE then
			Note(err)
		end
	end
	return rep
end

-- A window's own art (its border pieces, its title string, a divider line)
-- held at alpha 0 while the kit is on. Kept here rather than in Kit:Fade,
-- which marks the region with a field: nothing is written onto Edit Mode's
-- regions; the SetAlpha post-hook puts 0 back should anything raise it.
local function FadeRegion(obj)
	if not obj or faded[obj] then
		return
	end
	faded[obj] = true
	obj:SetAlpha(0)
	if not alphaHooked[obj] then
		alphaHooked[obj] = true
		hooksecurefunc(obj, "SetAlpha", Guard(function(o, a)
			if faded[o] and a ~= 0 then
				o:SetAlpha(0)
			end
		end))
	end
end

local function UnfadeRegion(obj)
	if obj and faded[obj] then
		faded[obj] = nil
		obj:SetAlpha(1)
	end
end

local function FadeArt(window, list)
	local set = fadedArt[window] or {}
	fadedArt[window] = set
	for _, obj in ipairs(list) do
		if obj then
			FadeRegion(obj)
			set[obj] = true
		end
	end
end

local function UnfadeArt(window)
	for obj in pairs(fadedArt[window] or {}) do
		UnfadeRegion(obj)
	end
	fadedArt[window] = nil
end

-- every texture of a frame (its regions only): a dialog's border pieces
local function Textures(frame)
	local list = {}
	if not (frame and frame.GetRegions) then
		return list
	end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.GetObjectType and region:GetObjectType() == "Texture" and not region.kitPiece then
			list[#list + 1] = region
		end
	end
	return list
end

-- the palette's inner panel as a region of one of OUR frames (a kit rail's
-- frame, whose rails are in BORDER above it), inside the rail
local TOP_PAD_X, TOP_PAD_Y = 12, 30   -- the top controls' panel, in from the window's left and top edges (under the title plate)

local function InnerPanel(owner, inset)
	local pal = MelloUI.Palette and MelloUI.Palette.innerPanel or { 0.07, 0.06, 0.05 }
	local fill = owner:CreateTexture(nil, "BACKGROUND", nil, 2)
	fill.kitPiece = true
	fill:SetPoint("TOPLEFT", owner, "TOPLEFT", inset, -inset)
	fill:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", -inset, inset)
	fill:SetColorTexture(pal[1], pal[2], pal[3], PANEL_ALPHA)
	return fill
end

--------------------------------------------------------------------------------
-- Controls. Each is dressed once (skinned[] remembers it, the pools hand the
-- same frames out again) with the kit piece made ON the control: the game's
-- own art on it faded, ours following its states through post-hooks.
--------------------------------------------------------------------------------

-- A check box (the classic UI-CheckBox file art of EditModeCheckButtonTemplate
-- and EditModeSettingCheckboxTemplate; file textures read back as ids, so
-- keyed by hand): the kit's check box off / on / hover on its normal
-- texture's rect, a texture of the CheckButton (Kit:Replace's `state` kind:
-- parent = the button). Every other look of the button is faded with it.
local function SkinCheck(cb)
	if skinned[cb] ~= nil or not (cb.GetNormalTexture and cb:GetNormalTexture()) then
		return
	end
	local w = Read(cb, "GetWidth")
	if w and w > 40 then
		skinned[cb] = false   -- a wide check button is a row, not a box
		return
	end
	local normal = cb:GetNormalTexture()
	local fade = {}
	for _, getter in ipairs({ "GetPushedTexture", "GetCheckedTexture", "GetHighlightTexture", "GetDisabledTexture", "GetDisabledCheckedTexture" }) do
		local tex = cb[getter] and cb[getter](cb)
		if tex and tex ~= normal then
			fade[#fade + 1] = tex
		end
	end
	skinned[cb] = Replace(normal, { as = "UI-CheckBox-Up", button = cb, rect = normal, alsoFade = fade }) or false
	kinds[cb] = "check"
end

-- A text button (UIPanelButtonTemplate: Left / Middle / Right file pieces, or
-- a 128-RedButton three-slice): the red plate (B1), as Kit:SkinRedButton does
-- it but without the marker that helper writes onto the button. The plate's
-- textures are regions of the button (the rule's `owner`), its states from
-- the button's scripts and SetEnabled.
local function SkinButton(b)
	if skinned[b] ~= nil then
		return
	end
	local anchor, key
	if b.Center then
		anchor, key = b.Center, "_128-RedButton-Center"
	elseif b.Middle then
		anchor, key = b.Middle, "UI-Panel-Button-Up"
	end
	if not anchor then
		skinned[b] = false
		return
	end
	local extra = { b.Left, b.Right }
	for _, region in ipairs({ b:GetRegions() }) do
		if region:GetObjectType() == "Texture" and region ~= anchor and region ~= b.Left and region ~= b.Right
			and not region.kitPiece and region:GetDrawLayer() == "HIGHLIGHT" then
			extra[#extra + 1] = region
		end
	end
	skinned[b] = Replace(anchor, { as = key, rect = b, button = b, alsoFade = extra }) or false
	kinds[b] = "button"
end

-- A text dropdown (WowStyle1DropdownTemplate): the dropdown plate (D1) as the
-- dropdown's regions, its painted cap in place of the game's arrow.
local function SkinDropdown(dd)
	if skinned[dd] ~= nil then
		return
	end
	skinned[dd] = Replace(dd.Background, { as = "common-dropdown-textholder", rect = dd, button = dd, alsoFade = { dd.Arrow } }) or false
	kinds[dd] = "dropdown"
end

-- A MinimalSliderWithSteppersTemplate (the grid spacing, a setting's slider):
-- SL1 as the configurator has it (Core/Config.lua CreateSlider) -- the kit
-- track at the piece's own thickness as the Slider's regions, the gem thumb on
-- the thumb's rect, the kit arrows on the steppers. The steppers' arrow is a
-- plain texture of theirs in this client (no NormalTexture): taken as found.
local function SkinSlider(s)
	if skinned[s] ~= nil then
		return
	end
	local list = {}
	local track = s.Slider
	if track and track.Middle then
		local mid = Kit:Piece("inputs/slider_mid")
		local natural = mid and mid.box and (mid.box[4] - mid.box[2]) * Kit.scale or nil
		list[#list + 1] = Replace(track.Middle, { as = "_Minimal_SliderBar_Middle", rect = track, fitHeight = natural, alsoFade = { track.Left, track.Right } })
	end
	if track and track.Thumb then
		list[#list + 1] = Replace(track.Thumb, { as = "Minimal_SliderBar_Button", rect = track.Thumb, button = track })
	end
	for _, entry in ipairs({ { s.Back, "Minimal_SliderBar_Button_Left" }, { s.Forward, "Minimal_SliderBar_Button_Right" } }) do
		local b, key = entry[1], entry[2]
		local tex = b and ((b.GetNormalTexture and b:GetNormalTexture()) or Kit:FirstTexture(b))
		if tex then
			list[#list + 1] = Replace(tex, { as = key, button = b, alsoFade = Kit:OtherTextures(b, tex) })
		end
	end
	skinned[s] = list
	kinds[s] = "slider"
end

-- A MinimalScrollBar (the options list's): Kit:SkinScrollBar's pieces, made
-- here so no marker is written onto the bar -- the trough on the track, the
-- gem-slab thumb, the kit arrows; the thumb refitted as its height follows
-- the content.
local function SkinScrollBar(bar)
	if skinned[bar] ~= nil then
		return
	end
	local track, thumb = bar.Track, bar.Track and bar.Track.Thumb
	if not (track and thumb and track.Middle and thumb.Middle) then
		skinned[bar] = false
		return
	end
	local list = {}
	list[#list + 1] = Replace(track.Middle, { as = "minimal-scrollbar-track-middle", rect = track, alsoFade = { track.Begin, track.End } })
	list[#list + 1] = Replace(thumb.Middle, { as = "minimal-scrollbar-small-thumb-middle", rect = thumb, button = thumb, alsoFade = { thumb.Begin, thumb.End } })
	if bar.Back and bar.Back.Texture then
		list[#list + 1] = Replace(bar.Back.Texture, { as = "minimal-scrollbar-arrow-top", button = bar.Back })
	end
	if bar.Forward and bar.Forward.Texture then
		list[#list + 1] = Replace(bar.Forward.Texture, { as = "minimal-scrollbar-arrow-bottom", button = bar.Forward })
	end
	Perf.HookScript(thumb, "OnSizeChanged", Guard(function()
		for _, rep in ipairs(list) do
			if rep.vstrip and rep.object:IsShown() then
				rep:Refit()
			end
		end
	end))
	skinned[bar] = list
	kinds[bar] = "scrollbar"
end

-- A one-line edit box (InputBoxTemplate: the layout name): the edit plate
-- (S1) with its LEFT cap dropped -- that cap carries the search glass, and
-- this is a name box (the chat box's rule) -- on the art's own span (the
-- game's Left / Right pieces sit 5 px outside the box), a helper frame of the
-- box giving that span. The box's text insets stay the game's.
local function SkinEditBox(box)
	if skinned[box] ~= nil then
		return
	end
	local rect = CreateFrame("Frame", nil, box)
	rect:EnableMouse(false)
	rect:SetPoint("TOPLEFT", box.Left, "TOPLEFT")
	rect:SetPoint("BOTTOMRIGHT", box.Right, "BOTTOMRIGHT")
	skinned[box] = Replace(box.Middle, { as = "common-search-border-middle", rect = rect, edit = box, dropCap = "l", alsoFade = { box.Left, box.Right } }) or false
	kinds[box] = "editbox"
end

-- Every control under `root`, found by what it IS (as Kit:SweepControls, but
-- without its markers): scroll bars, sliders, check buttons, edit boxes,
-- dropdowns, text buttons. `skip` = frames never walked into.
local function Sweep(root, skip, depth)
	depth = depth or 0
	if not (root and root.GetChildren) or depth > 8 or (skip and skip[root]) then
		return
	end
	for _, child in ipairs({ root:GetChildren() }) do
		if not (skip and skip[child]) and not child.melloSkin then
			local kind = child.GetObjectType and child:GetObjectType()
			local leaf = false
			if child.Track and child.Track.Thumb and child.Back and child.Forward then
				SkinScrollBar(child)
				leaf = true
			elseif child.Slider and child.Back and child.Forward and child.Slider.Thumb then
				SkinSlider(child)
				leaf = true
			elseif kind == "CheckButton" then
				SkinCheck(child)
			elseif kind == "EditBox" and child.Left and child.Middle and child.Right then
				SkinEditBox(child)
			elseif child.Background and child.Arrow and child.Text then
				SkinDropdown(child)
			elseif kind == "Button" and (child.Center or (child.Left and child.Middle and child.Right))
				and child.GetFontString and child:GetFontString() then
				SkinButton(child)
			end
			if not leaf then
				Sweep(child, skip, depth + 1)
			end
		end
	end
end

-- A close button (UIPanelCloseButton): the kit's close states on its normal
-- texture's rect, the button's other art faded (Kit:SkinWindowShell's way).
local function SkinClose(close)
	if not close or skinned[close] ~= nil then
		return
	end
	local normal = close.GetNormalTexture and close:GetNormalTexture()
	if not normal then
		skinned[close] = false
		return
	end
	skinned[close] = Replace(normal, { as = "RedButton-Exit", button = close, alsoFade = Kit:OtherTextures(close, normal) }) or false
	kinds[close] = "close"
end

--------------------------------------------------------------------------------
-- The window shell of the manager and the settings dialog: frames of OUR OWN
-- under UIParent, on the window's rect, one step under the window (a lower
-- level in its strata, or the strata below when it sits too low): the outer
-- double rail grown outward with its stone body (the window's translucent
-- black is faded), the title plate riding the rail with the window's title on
-- it (the game's own title string faded: it cannot be moved), the divider
-- lines drawn as regions of the rail's frame, above its stone, and (the
-- settings dialog) the rows' panel.
--------------------------------------------------------------------------------

local function Place(shell)
	local w = shell.window
	local strata = "DIALOG"
	local okS, s = pcall(w.GetFrameStrata, w)
	if okS and type(s) == "string" then
		strata = s
	end
	local level = Read(w, "GetFrameLevel") or 0
	local base
	if level >= 2 then
		base = level - 2
	else
		strata = STRATA_BELOW[strata] or strata
		base = FALLBACK_LEVEL
	end
	for _, f in ipairs({ shell.root, shell.holder, shell.nine }) do
		f:SetFrameStrata(strata)
		f:SetFrameLevel(base)
	end
	-- the plate over the rail's top corners and the rows' panel over the
	-- stone: one level up, still under the window
	for _, f in ipairs({ shell.title, shell.rows, shell.rowsNine, shell.top, shell.topNine }) do
		if f then
			f:SetFrameStrata(strata)
			f:SetFrameLevel(base + 1)
		end
	end
	shell.strata, shell.level = strata, base
end

-- the plate on the outer rail as the TitleBar rule lays it (Kit:TitleOnRail:
-- its caps' gems on the rail's top corners, the whole rail's width), the
-- title centred on its painted box
local function FitTitle(shell)
	local strip, root = shell.title, shell.root
	local rule = Kit.Replacements.TitleBar or {}
	strip:FitBox(TITLE_BAR_H * (rule.heightScale or 1))
	local lift, reach = Kit:TitleOnRail(strip)
	local out = Kit:OuterRailOutset() + reach
	strip:ClearAllPoints()
	strip:SetPoint("LEFT", root, "TOPLEFT", -out, lift)
	strip:SetPoint("RIGHT", root, "TOPRIGHT", out, lift)
	strip:SetHeight(strip.height)
	local w = Read(shell.window, "GetWidth")
	if w and w > 0 then
		strip:FitCaps(w + 2 * out)
	end
	local mid = Kit:Piece(Kit:StripPieceName(strip.base, "mid", strip.state))
	local dy = 0
	if mid and mid.box then
		dy = (mid.h / 2 - (mid.box[2] + mid.box[4]) / 2) * (strip.scale or Kit.scale)
	end
	shell.text:ClearAllPoints()
	shell.text:SetPoint("CENTER", strip, "CENTER", 0, dy)
end

-- the window's title, re-drawn on the plate in the game's own font and colour
-- (the settings dialog's changes with the selected element)
local function SyncTitle(shell)
	local game = shell.gameTitle
	if not game then
		return
	end
	local ok, text = pcall(game.GetText, game)
	if ok and not Secret(text) then
		shell.text:SetText(text or "")
	end
end

-- a divider line (the OnlineDivider file art, keyed by hand): the kit's
-- divider strip on the line's rect, shown while the game shows the line
local function FitDivider(d)
	local h, w = Read(d.region, "GetHeight"), Read(d.region, "GetWidth")
	if not (h and w and h > 0 and w > 0) then
		return
	end
	local yoff = d.strip:FitBox(h)
	d.strip:ClearAllPoints()
	d.strip:SetPoint("LEFT", d.region, "LEFT", 0, yoff)
	d.strip:SetPoint("RIGHT", d.region, "RIGHT", 0, yoff)
	d.strip:SetHeight(d.strip.height)
	d.strip:FitCaps(w)
end

local function IsShownNow(obj)
	local ok, shown = pcall(obj.IsShown, obj)
	return ok and not Secret(shown) and shown and true or false
end

-- the dividers and the rows' panel follow what the game shows (the settings
-- dialog hides its rows when an element has no settings, its divider when it
-- has no extra buttons)
local function SyncParts(shell)
	for _, d in ipairs(shell.dividers) do
		local shown = active and IsShownNow(d.region)
		d.strip:SetShown(shown)
		if shown then
			FitDivider(d)
		end
	end
	if shell.rows then
		shell.rows:SetShown(active and IsShownNow(shell.rowsOf))
	end
end

local function AddDivider(shell, region)
	if not region or skinned[region] ~= nil then
		return
	end
	local strip = Kit:Strip(shell.nine, "window/divider", { scale = Kit.scale, owner = shell.nine, layer = "ARTWORK", sublevel = 2 })
	strip:EnableMouse(false)
	strip:Hide()
	shell.dividers[#shell.dividers + 1] = { strip = strip, region = region }
	skinned[region] = strip
	kinds[region] = "divider"
end

-- the settings dialog's rows (its Settings frame) on the inner panel inside a
-- single rail (L1's rail, edges only), a frame of ours on the rows' rect
local function AddRowsPanel(shell, rowsOf)
	if shell.rows or not rowsOf then
		return
	end
	local rows = CreateFrame("Frame", nil, shell.root)
	rows:EnableMouse(false)
	rows:SetPoint("TOPLEFT", rowsOf, "TOPLEFT", -ROWS_PAD_X, ROWS_PAD_Y)
	rows:SetPoint("BOTTOMRIGHT", rowsOf, "BOTTOMRIGHT", ROWS_PAD_X, -ROWS_PAD_Y)
	rows:Hide()
	local nine = Kit:NineSlice(rows, { prefix = "window/single", scale = Kit.scale * (Kit.frameScale or 1.6), gems = false, body = false })
	InnerPanel(nine, (nine.thickness or 6) * PANEL_IN_RAIL)
	shell.rows, shell.rowsNine, shell.rowsOf = rows, nine, rowsOf
	kinds[rowsOf] = "rows panel"
end

local function BuildShell(window)
	if shells[window] ~= nil then
		return shells[window]
	end
	shells[window] = false
	if not (Kit.NineSlice and Kit.Strip and Kit.TitleOnRail) then
		return false
	end
	local shell = { window = window, dividers = {}, gameTitle = window.Title }
	local root = CreateFrame("Frame", nil, UIParent)
	root:EnableMouse(false)
	root:SetAllPoints(window)
	root:Hide()
	shell.root = root
	-- the outer rail as the NineSlicePanelTemplate rule builds it (Kit:Replace's
	-- `frame` kind with `outset`), made here so it lives on our frame (the rule
	-- would also register the window with the window mover, which must never
	-- move Edit Mode's windows)
	local rule = Kit.Replacements.NineSlicePanelTemplate or {}
	local fscale = Kit.scale * (rule.scale or Kit.frameScale)
	local o = (rule.outset or 0) * fscale
	local holder = CreateFrame("Frame", nil, root)
	holder:EnableMouse(false)
	holder:SetPoint("TOPLEFT", root, "TOPLEFT", -o, o)
	holder:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", o, -o)
	shell.holder = holder
	local nine = Kit:NineSlice(holder, { scale = fscale, gems = false, body = true, bodyScale = rule.bodyScale and Kit.scale * rule.bodyScale,
		prefix = rule.prefix or "window/frame", corners = rule.corners })
	-- the plate's caps carry the top corners' gems (RegisterShell's way)
	if nine.SetTopGems then
		nine:SetTopGems(false)
	end
	shell.nine = nine
	-- the title plate and the title on it
	local tr = Kit.Replacements.TitleBar or {}
	local strip = Kit:Strip(root, tr.base or "tabs/top", { state = tr.state or "open", scale = Kit.scale })
	strip:EnableMouse(false)
	shell.title = strip
	local text = strip:CreateFontString(nil, "OVERLAY")
	local game = shell.gameTitle
	local fo = game and game.GetFontObject and game:GetFontObject()
	text:SetFontObject(fo or "GameFontHighlightLarge")
	if game and game.GetTextColor then
		local ok, r, g, b = pcall(game.GetTextColor, game)
		if ok and r and not Secret(r) then
			text:SetTextColor(r, g, b)
		end
	end
	text:SetWordWrap(false)
	Kit:TitleFont(text, true)
	shell.text = text
	-- the window's size follows its layout (the settings dialog per element)
	Perf.SetScript(root, "OnSizeChanged", Guard(function()
		if active then
			FitTitle(shell)
			SyncParts(shell)
		end
	end))
	-- the window's alpha (a fade-in) and scale, followed while it is open; and
	-- a window that went away without its OnHide reaching us takes the shell
	Perf.SetScript(root, "OnUpdate", function(self)
		if not IsShownNow(window) then
			self:Hide()
			return
		end
		local a = Read(window, "GetAlpha")
		if a and math.abs(a - self:GetAlpha()) > 0.001 then
			self:SetAlpha(a)
		end
		local s = Read(window, "GetScale")
		if s and s > 0 and math.abs(s - self:GetScale()) > 0.0001 then
			self:SetScale(s)
		end
	end)
	shells[window] = shell
	return shell
end

-- the game's own art of a shelled window: its border (the Dialog nine-slice
-- and its translucent black), its title string (re-drawn on the plate) and
-- the divider lines the kit re-draws
local function ShellArt(shell)
	local list = Textures(shell.window.Border)
	if shell.gameTitle then
		list[#list + 1] = shell.gameTitle
	end
	for _, d in ipairs(shell.dividers) do
		list[#list + 1] = d.region
	end
	return list
end

local function ShowShell(shell)
	if not (shell and active) then
		return
	end
	Place(shell)
	local s = Read(shell.window, "GetScale")
	if s and s > 0 then
		shell.root:SetScale(s)
	end
	shell.root:SetAlpha(Read(shell.window, "GetAlpha") or 1)
	SyncTitle(shell)
	shell.root:Show()
	FitTitle(shell)
	SyncParts(shell)
	FadeArt(shell.window, ShellArt(shell))
end

--------------------------------------------------------------------------------
-- The manager (EditModeManagerFrame)
--------------------------------------------------------------------------------

-- a heading of the advanced options (Frames / Combat / Misc: a 225 x 32 frame
-- with its Title string LEFT + 5, no art): the header plate under it (an
-- addition the user asked for, 2026-09-24). The plate is a child of the
-- heading frame, which is no layout frame, so it scrolls and clips with the
-- list. The text cannot be moved, and the list clips at the heading's left
-- edge, so the plate starts there with its left cap left out (the mid runs to
-- the edge) and spans the list's two columns, closing with its right cap.
local function AddSection(frame)
	if not frame or skinned[frame] ~= nil then
		return
	end
	local strip = Kit:Strip(frame, "lists/header", { scale = Kit.scale })
	strip:EnableMouse(false)
	strip:SetFrameLevel(math.max((Read(frame, "GetFrameLevel") or 1) - 1, 0))
	strip.dropCap = "l"
	strip:Hide()
	sections[#sections + 1] = { strip = strip, frame = frame }
	skinned[frame] = strip
	kinds[frame] = "heading"
end

local function FitSection(entry)
	local strip, frame = entry.strip, entry.frame
	local h, w = Read(frame, "GetHeight"), Read(frame, "GetWidth")
	if not (h and w and h > 0 and w > 0) then
		return
	end
	local yoff = strip:FitBox(h * SECTION_FIT)
	-- the grid lays the check boxes two to a row, each the heading's width
	local width = w * 2
	strip:ClearAllPoints()
	strip:SetPoint("LEFT", frame, "LEFT", 0, yoff)
	strip:SetSize(width, strip.height)
	strip:FitCaps(width)
end

local function SyncSections()
	for _, entry in ipairs(sections) do
		entry.strip:SetShown(active)
		if active then
			FitSection(entry)
		end
	end
end

local managerSkip = setmetatable({}, { __mode = "k" })

local function DressManager(manager)
	if skinned[manager] ~= nil then
		return
	end
	skinned[manager] = true
	local shell = BuildShell(manager)
	-- frames never walked into: the full-screen grid and snapping lines
	if manager.Grid then
		managerSkip[manager.Grid] = true
	end
	if manager.MagnetismPreviewLinesContainer then
		managerSkip[manager.MagnetismPreviewLinesContainer] = true
	end
	SkinClose(manager.CloseButton)
	local account = manager.AccountSettings
	local container = account and account.SettingsContainer
	if container and container.BorderArt then
		-- the options list's border (an OptionsFrame nine-slice): the single
		-- rail, edges only, a child of the border frame itself (a NineSlice,
		-- no layout frame), which shows and hides with the list; inside it the
		-- palette's inner panel under the check boxes (WINDOW-RULES 2e), a
		-- region of the rail's own frame under its rails
		local art = container.BorderArt
		local pieces = Textures(art)
		if #pieces > 0 then
			local rep = Replace(pieces[1], { as = "common-insideframe", parent = art, rect = art, body = false,
				alsoFade = { select(2, unpack(pieces)) } })
			skinned[art] = rep or false
			kinds[art] = "list border + panel"
			if rep and rep.skin and rep.skin.CreateTexture then
				InnerPanel(rep.skin, (rep.skin.thickness or 6) * PANEL_IN_RAIL)
			end
		end
	end
	-- the controls above the list (the Layout dropdown, Show Grid, Snap to
	-- Elements, Advanced Options): the same inner panel inside a single rail,
	-- a frame of OUR shell from under the title down to the list (user,
	-- 2026-09-24: WINDOW-RULES 2e, no small text on the plain stone) --
	-- anchored to the game's frames, nothing of theirs moved
	if shell and not shell.top and container then
		local top = CreateFrame("Frame", nil, shell.root)
		top:EnableMouse(false)
		top:SetPoint("TOPLEFT", manager, "TOPLEFT", TOP_PAD_X, -TOP_PAD_Y)
		top:SetPoint("BOTTOMRIGHT", container, "TOPRIGHT", 0, 4)
		local nine = Kit:NineSlice(top, { prefix = "window/single", scale = Kit.scale * (Kit.frameScale or 1.6), gems = false, body = false })
		InnerPanel(nine, (nine.thickness or 6) * PANEL_IN_RAIL)
		shell.top, shell.topNine = top, nine
		kinds[top] = "top controls panel"
	end
	local adv = container and container.ScrollChild and container.ScrollChild.AdvancedOptionsContainer
	if adv then
		for _, key in ipairs({ "FramesTitle", "CombatTitle", "MiscTitle" }) do
			local f = adv[key]
			if f and f.Title and not f.Button then
				AddSection(f)
			end
		end
	end
	if shell and account and account.Expander and account.Expander.Divider then
		AddDivider(shell, account.Expander.Divider)
	end
	-- the check boxes of the options list (all made at load; the game moves
	-- them between its containers, and our pieces, being theirs, go along)
	if account and account.settingsCheckButtons then
		for _, row in pairs(account.settingsCheckButtons) do
			if type(row) == "table" and row.Button then
				SkinCheck(row.Button)
			end
		end
	end
	Sweep(manager, managerSkip)
end

--------------------------------------------------------------------------------
-- The settings dialog (EditModeSystemSettingsDialog)
--------------------------------------------------------------------------------

local function DressDialog(dialog)
	if skinned[dialog] == nil then
		skinned[dialog] = true
		local shell = BuildShell(dialog)
		SkinClose(dialog.CloseButton)
		if shell then
			AddRowsPanel(shell, dialog.Settings)
			if dialog.Buttons and dialog.Buttons.Divider then
				AddDivider(shell, dialog.Buttons.Divider)
			end
		end
	end
	-- the pooled setting rows and extra buttons: new ones may have come
	Sweep(dialog.Settings)
	Sweep(dialog.Buttons)
end

--------------------------------------------------------------------------------
-- The small layout dialogs: DialogPanel's dialog look -- the single rail with
-- its stone one level under the dialog (a child of the dialog: these are no
-- layout frames, so it simply shows and hides with it), the game's box faded,
-- the buttons on red plates, the check box, the name box, the import box's
-- border.
--------------------------------------------------------------------------------

local function DressSmall(dialog)
	if smalls[dialog] ~= nil then
		return smalls[dialog]
	end
	smalls[dialog] = false
	if not Kit.NineSlice then
		return false
	end
	local ok, nine = pcall(Kit.NineSlice, Kit, dialog, { prefix = "window/single", scale = Kit.scale * (Kit.frameScale or 1.6),
		gems = false, body = true, level = -1 })
	if not (ok and nine) then
		Note(nine)
		return false
	end
	nine:SetShown(active)
	local skin = { nine = nine }
	smalls[dialog] = skin
	-- the import box (InputScrollFrameTemplate: eight Common-Input-Border file
	-- pieces round a dark middle): the single rail on the pieces' span, edges
	-- only, a child of the box (a ScrollFrame, no layout frame); the game's
	-- dark middle stays under the pasted text (its own inner panel)
	local box = dialog.ImportBox
	if box and box.TopLeftTex and box.BottomRightTex and skinned[box] == nil then
		local rect = CreateFrame("Frame", nil, box)
		rect:EnableMouse(false)
		rect:SetPoint("TOPLEFT", box.TopLeftTex, "TOPLEFT")
		rect:SetPoint("BOTTOMRIGHT", box.BottomRightTex, "BOTTOMRIGHT")
		local fade = {}
		for _, key in ipairs({ "TopRightTex", "TopTex", "BottomLeftTex", "BottomRightTex", "BottomTex", "LeftTex", "RightTex" }) do
			if box[key] then
				fade[#fade + 1] = box[key]
			end
		end
		skinned[box] = Replace(box.TopLeftTex, { as = "common-insideframe", parent = box, rect = rect, body = false, alsoFade = fade }) or false
		kinds[box] = "importbox"
	end
	Sweep(dialog)
	return skin
end

local function ShowSmall(dialog)
	local skin = active and DressSmall(dialog)
	if skin then
		skin.nine:Show()
		FadeArt(dialog, Textures(dialog.Border))
	end
end

--------------------------------------------------------------------------------
-- Following the windows: post-hooks on their show / hide (and the settings
-- dialog's own refresh), each body guarded.
--------------------------------------------------------------------------------

local function Manager()
	return _G.EditModeManagerFrame
end

local function Dialog()
	return _G.EditModeSystemSettingsDialog
end

local function OnManagerShow(manager)
	if not active then
		return
	end
	DressManager(manager)
	ShowShell(shells[manager])
	SyncSections()
end

local function OnDialogShow(dialog)
	if not active then
		return
	end
	DressDialog(dialog)
	ShowShell(shells[dialog])
end

local function OnShellHide(window)
	local shell = shells[window]
	if shell then
		shell.root:Hide()
	end
end

-- the element's settings are re-laid (new pooled rows, the extra buttons,
-- the title) by UpdateDialog, while the dialog is open too
local function OnDialogUpdate(dialog)
	if not active then
		return
	end
	-- (a dialog never shown yet is left for its first show: dressed there)
	if skinned[dialog] == nil and not IsShownNow(dialog) then
		return
	end
	DressDialog(dialog)
	local shell = shells[dialog]
	if shell then
		SyncTitle(shell)
		if shell.root:IsShown() then
			FitTitle(shell)
			SyncParts(shell)
			FadeArt(dialog, ShellArt(shell))
		end
	end
end

local function Hook()
	local manager = Manager()
	if manager and not hooked[manager] then
		hooked[manager] = true
		Perf.HookScript(manager, "OnShow", Guard(OnManagerShow))
		Perf.HookScript(manager, "OnHide", Guard(OnShellHide))
	end
	local dialog = Dialog()
	if dialog and not hooked[dialog] then
		hooked[dialog] = true
		Perf.HookScript(dialog, "OnShow", Guard(OnDialogShow))
		Perf.HookScript(dialog, "OnHide", Guard(OnShellHide))
		if type(dialog.UpdateDialog) == "function" then
			hooksecurefunc(dialog, "UpdateDialog", Guard(OnDialogUpdate))
		end
	end
	for _, name in ipairs(SMALL_DIALOGS) do
		local d = _G[name]
		if d and d.HookScript and not hooked[d] then
			hooked[d] = true
			Perf.HookScript(d, "OnShow", Guard(ShowSmall))
		end
	end
end

local function Activate()
	if active or not Kit then
		return
	end
	active = true
	Hook()
	-- (user, 2026-09-24: "dress rarely used windows on first open") Edit Mode is
	-- loaded with the interface and most sessions never open it: the manager
	-- and the settings dialog are dressed the first time each shows (their
	-- OnShow: OnManagerShow / OnDialogShow, before the first frame is drawn),
	-- not here -- only one that is open right now is dressed at once. What
	-- was dressed before is switched back on below as it always was.
	local manager, dialog = Manager(), Dialog()
	if manager and IsShownNow(manager) then
		DressManager(manager)
	end
	if dialog and IsShownNow(dialog) then
		DressDialog(dialog)
	end
	for _, rep in ipairs(reps) do
		local ok, err = pcall(rep.Enable, rep)
		if not ok then
			Note(err)
		end
	end
	if manager and IsShownNow(manager) then
		ShowShell(shells[manager])
	end
	if dialog and IsShownNow(dialog) then
		ShowShell(shells[dialog])
	end
	SyncSections()
	for _, name in ipairs(SMALL_DIALOGS) do
		local d = _G[name]
		if d and d.IsShown and IsShownNow(d) then
			ShowSmall(d)
		end
	end
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	for window, shell in pairs(shells) do
		if shell then
			shell.root:Hide()
		end
		UnfadeArt(window)
	end
	for dialog, skin in pairs(smalls) do
		if skin then
			skin.nine:Hide()
		end
		UnfadeArt(dialog)
	end
	SyncSections()
	for _, rep in ipairs(reps) do
		local ok, err = pcall(rep.Disable, rep)
		if not ok then
			Note(err)
		end
	end
end

-- Edit Mode is loaded with the interface on this client; a client that loads
-- it later has its frames hooked when it arrives
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
Perf.SetScript(loader, "OnEvent", function(_, _, name)
	if name == "Blizzard_EditMode" and active then
		local ok, err = pcall(Hook)
		if not ok then
			Note(err)
		end
	end
end)

function M:OnEnable(db)
	self.db = db
	local ok, err = pcall(Activate)
	if not ok then
		Note(err)
	end
end

function M:OnDisable()
	local ok, err = pcall(Deactivate)
	if not ok then
		Note(err)
	end
end

--------------------------------------------------------------------------------
-- /editmodedump [manager | dialog | layout | import | unsaved | all]: a
-- window's regions and children (the manager and the settings dialog by
-- default), what the kit made of it, missing mappings and caught errors;
-- opens the copy window. Only getters are called on the game's frames.
--------------------------------------------------------------------------------

local function Name(obj)
	local ok, name = pcall(function()
		return obj.GetName and obj:GetName() or (obj.GetDebugName and obj:GetDebugName())
	end)
	if not ok or Secret(name) then
		return "[secret name]"
	end
	return tostring(name)
end

local function Num(v)
	if v == nil then
		return "?"
	end
	return string.format("%.1f", v)
end

local function DumpRegions(frame, window, indent)
	for _, region in ipairs({ frame:GetRegions() }) do
		local kind = region:GetObjectType()
		local layer = region.GetDrawLayer and region:GetDrawLayer() or "?"
		local what = ""
		if kind == "Texture" then
			what = tostring(Kit:ArtKey(region) or "?")
		elseif kind == "FontString" then
			local ok, t = pcall(region.GetText, region)
			what = "text: " .. ((ok and not Secret(t)) and tostring(t):sub(1, 40) or "?")
		end
		MelloUI:Print("%sregion %s %s %s alpha %s shown %s%s", indent, kind, tostring(layer), what, Num(Read(region, "GetAlpha")),
			tostring(IsShownNow(region)), (fadedArt[window] and fadedArt[window][region]) and " [faded by the kit]" or "")
	end
end

local function DumpChildren(frame, indent, depth)
	for _, child in ipairs({ frame:GetChildren() }) do
		if not child.melloSkin then
			MelloUI:Print("%schild %s %s level %s shown %s%s", indent, tostring(child:GetObjectType()), Name(child),
				tostring(Read(child, "GetFrameLevel") or "?"), tostring(IsShownNow(child)),
				kinds[child] and (" -> kit " .. kinds[child] .. (skinned[child] and "" or " (no piece)")) or "")
			if depth > 0 then
				DumpChildren(child, indent .. "  ", depth - 1)
			end
		end
	end
end

local function DumpWindow(label, frame, depth)
	if not frame then
		MelloUI:Print("%s: not on this client", label)
		return
	end
	local okS, strata = pcall(frame.GetFrameStrata, frame)
	MelloUI:Print("%s: shown %s, size %s x %s, strata %s, level %s, scale %s, alpha %s", label, tostring(IsShownNow(frame)),
		Num(Read(frame, "GetWidth")), Num(Read(frame, "GetHeight")), okS and tostring(strata) or "?",
		tostring(Read(frame, "GetFrameLevel") or "?"), Num(Read(frame, "GetScale")), Num(Read(frame, "GetAlpha")))
	local shell = shells[frame]
	if shell then
		MelloUI:Print("  kit shell: shown %s, strata %s, level %s (title plate and rows panel %s), title %q, dividers %d, rows panel %s",
			tostring(shell.root:IsShown()), tostring(shell.strata), tostring(shell.level), tostring(shell.level and shell.level + 1),
			tostring(shell.text:GetText()), #shell.dividers, shell.rows and tostring(shell.rows:IsShown()) or "none")
	elseif smalls[frame] then
		MelloUI:Print("  kit dialog rail: shown %s, level %s", tostring(smalls[frame].nine:IsShown()), tostring(smalls[frame].nine:GetFrameLevel()))
	else
		MelloUI:Print("  kit: not dressed yet (dressed on first show)")
	end
	local count = 0
	for _ in pairs(fadedArt[frame] or {}) do
		count = count + 1
	end
	MelloUI:Print("  game art faded: %d", count)
	DumpRegions(frame, frame, "  ")
	if frame.Border then
		MelloUI:Print("  Border:")
		DumpRegions(frame.Border, frame, "    ")
	end
	DumpChildren(frame, "  ", depth)
end

SLASH_MELLOEDITMODEDUMP1 = "/editmodedump"
SlashCmdList.MELLOEDITMODEDUMP = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	MelloUI:ClearLog()
	MelloUI:Print("Edit Mode kit: module %s, dressed %s, replacements %d, heading plates %d", M.isEnabled and "on" or "off",
		active and "on" or "off", #reps, #sections)
	local counts = {}
	for _, kind in pairs(kinds) do
		counts[kind] = (counts[kind] or 0) + 1
	end
	local parts = {}
	for kind, n in pairs(counts) do
		parts[#parts + 1] = kind .. " " .. n
	end
	table.sort(parts)
	MelloUI:Print("kit pieces by control: %s", #parts > 0 and table.concat(parts, ", ") or "none yet")
	local keys = {}
	for key in pairs(missing) do
		keys[#keys + 1] = key
	end
	if #keys > 0 then
		table.sort(keys)
		MelloUI:Print("no kit piece mapped for: %s", table.concat(keys, ", "))
	end
	for i, err in ipairs(errors) do
		MelloUI:Print("caught error %d: %s", i, err)
	end
	local all = msg == "all"
	if msg == "" or msg == "manager" or all then
		DumpWindow("EditModeManagerFrame", Manager(), 3)
	end
	if msg == "" or msg == "dialog" or all then
		DumpWindow("EditModeSystemSettingsDialog", Dialog(), 3)
	end
	if msg == "layout" or all then
		DumpWindow("EditModeLayoutDialog", _G.EditModeLayoutDialog, 1)
	end
	if msg == "import" or all then
		DumpWindow("EditModeImportLayoutDialog", _G.EditModeImportLayoutDialog, 1)
	end
	if msg == "unsaved" or all then
		DumpWindow("EditModeUnsavedChangesDialog", _G.EditModeUnsavedChangesDialog, 1)
	end
	MelloUI:ShowLog("editmodedump")
end
