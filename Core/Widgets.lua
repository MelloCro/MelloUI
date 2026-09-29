--------------------------------------------------------------------------------
-- MelloUI - Widgets
--
-- One widget set for the windows MelloUI makes itself (audit item 11, the
-- configurator build of 2026-09-25): the configurator first, the installer
-- next. Lifted from the configurator's own helpers, taking get / set instead
-- of a module's settings, so any window's data can sit behind them.
--
--   W.Paint(region, key, how, alpha)   a palette colour by its KEY (below)
--   W.Repaint()
--   W.Text(parent, font, text, key)    a FontString, left and top justified
--   W.Solid(parent, layer, key, alpha) a flat texture in a palette colour
--   W.Box(parent, bg, border, alpha)   a backdrop box, its fill and 1 px edge
--   W.Edges(frame, key, layer)         four 1 px lines round a frame, by key
--   W.Panel(parent, opts)              THE content panel of the own windows
--                                      (0.15.0): a flat inner panel in a 1 px
--                                      edge, in both looks
--   W.Header(parent, y, text, opts)    a section's heading: a gold title and
--                                      a hairline (0.15.0)
--   W.ShowTooltip(owner, title, body, line, anchor)   W.TipLeave (a shared OnLeave)
--   W.Switch(parent, get, set, opts)   a flat check box (0.15.0)
--   W.Dropdown(parent, width, get, set, values, opts)   dd:SetValues(values)
--                                      a flat box and MelloUI's own list
--                                      (0.15.0: never the game's menu; a
--                                      long list capped and scrolled)
--   W.Slider(parent, width, get, set, opts)   a thin track, a round knob and
--                                      a box to type the value in (0.15.0)
--   W.NumberBox(parent, width, get, set, opts)   a number to type, in the
--                                      slider box's look (0.15.0)
--   W.Button(parent, text, width, skin, opts)   a flat plate (0.15.0), and
--     W.FlatButton(button, gold): the same look on a button made by hand
--   W.CloseButton(parent, skin)        a flat plate with a cross (0.15.0)
--   W.FlatTab(tab, skin)               a page's tab made by hand, flat (0.15.0)
--   W.FlatField(box)                   a text field or search box made by
--                                      hand, flat (0.15.0; W.FlatSearch)
--   W.IconBox(parent, size, texture, skin)
--   W.RoundIcon(parent, size, texture, opts)   a round icon button in a rim
--                                      (the kit's round rim, or the minimap's)
--   W.TrayBox(parent, opts)            a small list's box beside a window (the
--                                      kit's list box, or a plain fill and edge)
--   W.RowPlate(row, opts)              W.RowPlateOff(row), W.RowPlateChild(row, child)
--   W.Flash(row, hold)                 a row's hover look lit for a moment (a
--                                      jump's target: the configurator's search)
--   W.Tag(parent, text, snug)          ONE small gold word on a plate (a card's
--                                      "Recommended", an option's "New"), and
--     W.NewTag(parent, after, new, room), W.Badge(frame, new, inset),
--     W.ButtonTag(button, new): an option's New tag while its update runs
--     (MelloUI:IsNew); W.TagShown, W.TagAlpha
--   W.Row(parent, y, height, label, hint, desc, opts) and the typed rows
--     W.ToggleRow / SliderRow / DropdownRow / ButtonRow, W.Gate, W.ClipRow
--   W.PictureRow(parent, y, label, hint, desc, get, set, choices, kind, opts)
--                                      a look chosen by its picture (0.15.0),
--     its flyout W.PictureMenu(host, skin), one per window (a dropdown's
--     list opens in it too), W.ClosePictureMenu(host), W.CloseFlyouts()
--   W.LinkRow(parent, y, label, get, onClick, opts)   a setting kept on
--                                      another page: its value and a button
--                                      to it (0.15.0)
--   W.Card(parent, spec, skin)         a choice card (the installer's setups;
--                                      spec.palette: a palette's card)
--   W.PaletteSwatch(parent, spec)      a palette shown by its colours, and
--     W.PaletteValues(), W.PaletteName(id), W.PaletteFill(tex, id, role):
--     the one palette picker's parts
--   W.Dress(root, skin, depth)         the kit's control sweep over a root
--   W.NavRail(parent, spec)            a side list / a steps rail (and a
--                                      search's results in its place)
--   W.Pager(parent, opts)              pages that cross-fade in one scroll
--   W.RowBudget                        ONE budget of rows a frame for every
--                                      own window: Begin(ms), End(), Spent(ms)
--
-- `skin` is the window's shell (Kit:OwnWindow, Modules/KitWindow.lua), or nil
-- for the plain palette look. A builder never reaches for MelloUI.Kit itself
-- for dressing: it asks skin:Kit(fn, ...) (fn(Kit, ...) now while the kit look
-- is on, else at its first switch on), hands skin.replace / skin.skin to the
-- kit's helpers, and takes the region to replace, where a widget has none,
-- from skin:Anchor(parent, layer) -- this file makes no invisible anchor and
-- holds no numeric colour. Colours go only through W.Paint (a picture of
-- ANOTHER palette -- W.PaletteFill: a swatch's chips -- reads that palette's
-- own colours from Core's registry, as a card's picture reads its file), sounds only
-- through MelloUI:PlayUISound, motion only through MelloUI.Anim (Reduce Motion
-- honoured by every helper). Kit and Fonts load after this file (the TOC):
-- nothing of theirs is bound here, everything is looked up when a builder
-- runs (the kit in one place, KitNow: a colour painted, a choice's picture
-- drawn). Nothing is made at load but the shared handlers and weak tables.
-- 0.15.0, the cleaner look the user picked (v150 configurator rebuild): the
-- own windows' panels, buttons, sliders and section headings are flat in
-- both looks (W.Panel, W.Button, W.Slider, W.Header) on the shell's calm
-- ground; the kit's list box, red plate, slider and header plate stay the
-- game windows'. Then "all flat" (user, 2026-09-29): the check boxes, the
-- dropdowns and their list, a page's tabs, the search box and the text
-- fields, and the close button too (W.Switch, W.Dropdown, W.FlatTab,
-- W.FlatField, W.CloseButton), the kit's active look (Kit:SetActive) still
-- marking a ticked box and the selected tab in the kit's look. Unchanged:
-- the row plate, W.Card, W.TrayBox.
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Widgets")
local Shared = Perf.Shared
local C_Timer = Perf.C_Timer   -- (a flash's hold: W.Flash)
local Secret = MelloUI.Safe.IsSecret   -- (Core.lua's, one set for the addon)
local Num = MelloUI.Safe.Number

local W = {}
MelloUI.Widgets = W

local WHITE = "Interface\\Buttons\\WHITE8x8"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"   -- a round icon's, a slider's knob
local TEXTURE_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Textures\\"
local ICON_FRAME = "UI-HUD-ActionBar-IconFrame"        -- the action button bevel
local ICON_MASK = "UI-HUD-ActionBar-IconFrame-Mask"    -- its rounded corners
local GLOW_ART = "Interface\\Buttons\\UI-ActionButton-Border"
local RIM_GROW = 1.1        -- the kit rim's rect: the icon box grown about its centre
local FADE_IN, FADE_OUT = 0.10, 0.12   -- a row's hover
local GATE_ALPHA = 0.4      -- a row that sleeps until a switch is on
local FLAT_OFF = 0.5        -- a disabled flat control: its fill and edge at this

-- the typed rows' heights (the configurator's ledger)
W.ROW_HEIGHT, W.SLIDER_ROW_HEIGHT = 34, 40

local weakKeys = { __mode = "k" }
local NO_OPTS = {}   -- (a builder called without options reads this empty table)

-- The window's one flyout (a picture row's tiles, a dropdown's list): filled
-- by W.PictureMenu's block, below; the dropdowns' box opens it from here
local Flyout = {}

--------------------------------------------------------------------------------
-- Paint ("Palette-ready", user 2026-09-25): every colour an
-- own window draws is a palette KEY, looked up when it is painted (never an
-- { r, g, b } held from load: a palette switch puts a new table in
-- MelloUI.Palette) and remembered per region, so the bus's 'palette' paints
-- them all again. ONE registry for the addon: the kit's (Kit:Paint, Kit.lua),
-- looked up when a region is painted.
--   W.Paint(region, key, how, alpha)
--     how    "fill" (SetColorTexture, the default), "vertex" (SetVertexColor),
--            "text" (SetTextColor), "backdrop" (SetBackdropColor), "border"
--            (SetBackdropBorderColor); a backdrop and its border are kept
--            apart, so one frame holds both
--     alpha  the colour's alpha (1)
--   W.Repaint()   the palette topic fired: every painted region from the
--                 palette as it is now (a palette change is a NEW table, so
--                 the same table repaints nothing: the kit's contract)
-- Without the kit (a world that never loaded Kit.lua) nothing is painted.
--------------------------------------------------------------------------------

-- The kit as it is now, looked up in this one place when a colour is painted
-- or a choice's picture drawn (Kit.lua loads after this file: nothing of it
-- is bound here)
local function KitNow()
	return MelloUI.Kit
end

function W.Paint(region, key, how, alpha)
	local Kit = KitNow()
	if region and key and Kit and Kit.Paint then
		Kit:Paint(region, key, how or "fill", alpha)
	end
end

function W.Repaint()
	MelloUI:Fire("palette")
end

function W.Text(parent, font, text, key)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	if text then
		fs:SetText(text)
	end
	if key then
		W.Paint(fs, key, "text")
	end
	return fs
end

function W.Solid(parent, layer, key, alpha)
	local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
	tex:SetTexture(WHITE)
	W.Paint(tex, key, "vertex", alpha or 1)
	return tex
end

local BOX_BACKDROP = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }

function W.Box(parent, bg, border, alpha)
	local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	f:SetBackdrop(BOX_BACKDROP)
	W.Paint(f, bg, "backdrop", alpha or 1)
	W.Paint(f, border, "border", 1)
	return f
end

-- four 1 px lines round a frame, painted by key (a box's edge without a
-- backdrop: a region each, so the kit look can hide them): { top, bottom,
-- left, right }. The one copy: the own-window shell's plate uses it too.
-- `rect`: the region they lie round, when not the frame itself (a check
-- box's box, a tab's plate: regions of the frame)
local function Edges(frame, key, layer, rect)
	local out = {}
	for i = 1, 4 do
		out[i] = frame:CreateTexture(nil, layer or "BORDER")
		W.Paint(out[i], key, "fill", 1)
	end
	rect = rect or frame
	out[1]:SetPoint("TOPLEFT", rect, "TOPLEFT", 0, 0)
	out[1]:SetPoint("BOTTOMRIGHT", rect, "TOPRIGHT", 0, -1)
	out[2]:SetPoint("TOPLEFT", rect, "BOTTOMLEFT", 0, 1)
	out[2]:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", 0, 0)
	out[3]:SetPoint("TOPLEFT", rect, "TOPLEFT", 0, 0)
	out[3]:SetPoint("BOTTOMRIGHT", rect, "BOTTOMLEFT", 1, 0)
	out[4]:SetPoint("TOPLEFT", rect, "TOPRIGHT", -1, 0)
	out[4]:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", 0, 0)
	return out
end
W.Edges = Edges

--------------------------------------------------------------------------------
-- Panel (0.15.0, the cleaner look the user picked: Background A): THE
-- content panel of the own windows, in both looks -- a flat `innerPanel`
-- fill in a 1 px `border` edge (W.Box's look, as regions: no backdrop). It
-- stands where the kit's list box (L1, Professions-background-summarylist)
-- stood in them: the configurator's sections and side list, the installer's
-- body, the question dialog's text, a picture row's flyout. One surface, one
-- panel: it lies on the calm ground (Kit:OwnWindow's `calm`), never on
-- another panel. The kit's list box stays the game windows'.
--   W.Panel(parent, opts) -> panel   a Frame, sized and placed by the caller
--     opts: on (true: the look laid on `parent` itself, which is returned --
--           a section that is its own panel), alpha (the fill's, 1)
--   panel.panelFill, panel.panelEdges   (painted by key: a new palette
--                                       paints them again)
--------------------------------------------------------------------------------

-- the panel's regions on a frame: its fill under everything the frame
-- draws, its edge over the fill
local function PanelLook(frame, alpha)
	local fill = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	fill:SetAllPoints(frame)
	W.Paint(fill, "innerPanel", "fill", alpha or 1)
	return fill, Edges(frame, "border", "BORDER")
end

function W.Panel(parent, opts)
	opts = opts or NO_OPTS
	local panel = opts.on and parent or CreateFrame("Frame", nil, parent)
	local alpha = opts.alpha
	if type(alpha) ~= "number" or Secret(alpha) then
		alpha = 1
	end
	panel.panelFill, panel.panelEdges = PanelLook(panel, alpha)
	return panel
end

--------------------------------------------------------------------------------
-- Header (0.15.0, Headers 1): a section's heading in the own windows -- its
-- title in gold (`selectedTrim`, GameFontNormal) and a 1 px `border`
-- hairline from 12 px past the title to 8 px short of the row's right edge,
-- on the title's middle. No plate, no gem caps, no hover, in both looks (the
-- kit's header plate, SH3, stays the game windows'): the configurator's
-- sections and subheadings, Home's cards, the installer's steps.
--   W.Header(parent, y, text, opts) -> header   a Frame W.HEADER_HEIGHT high,
--     `y` below the parent's top, as wide as the parent less opts.inset (0)
--     at both sides; opts.x: the title's left (8)
--   header.label, header.line
--------------------------------------------------------------------------------

do
	W.HEADER_HEIGHT = 28
	local HEADER_X, HEADER_GAP, HEADER_END = 8, 12, 8   -- the title's left, the title to its line, the line's end

	function W.Header(parent, y, text, opts)
		opts = opts or NO_OPTS
		local inset = opts.inset or 0
		local h = CreateFrame("Frame", nil, parent)
		h:SetHeight(W.HEADER_HEIGHT)
		h:SetPoint("TOPLEFT", inset, -(y or 0))
		h:SetPoint("RIGHT", parent, "RIGHT", -inset, 0)
		h:EnableMouse(false)
		h.label = W.Text(h, "GameFontNormal", text, "selectedTrim")
		h.label:SetWordWrap(false)
		h.label:SetPoint("LEFT", h, "LEFT", opts.x or HEADER_X, 0)
		h.line = W.Solid(h, "ARTWORK", "border", 1)
		h.line:SetHeight(1)
		h.line:SetPoint("LEFT", h.label, "RIGHT", HEADER_GAP, 0)
		h.line:SetPoint("RIGHT", h, "RIGHT", -HEADER_END, 0)
		return h
	end
end

--------------------------------------------------------------------------------
-- W.RowBudget: ONE budget of rows a frame, whoever makes them -- the
-- configurator's pages (a click, the scroll hook, its worker) and the
-- installer's (review, 2026-09-25: each kept one of its own, and two of them
-- in one frame came to 6 ms). `at` is the frame (GetTime is the same all
-- through one), `ms` the rows it has made, `from` when the rows under way
-- began: none begin inside them.
--   W.RowBudget.Begin(ms) -> deadline | nil
--       up to `ms` of rows now, less those this frame has made: the
--       debugprofilestop time to stop at; nil when none are left or rows are
--       under way. End() counts them (call it whatever Begin returned).
--   W.RowBudget.End()
--   W.RowBudget.Spent(ms)
--       this frame's rows counted as at least `ms` (a page's first open whose
--       own parts are this frame's work: its rows start the next frame)
--------------------------------------------------------------------------------

do
	local spend = { at = false, ms = 0, from = false }
	local function ThisFrame()
		local now = GetTime()
		if spend.at ~= now then
			spend.at, spend.ms, spend.from = now, 0, false
			return true
		end
		return false
	end
	W.RowBudget = {
		Begin = function(ms)
			if not ThisFrame() and (spend.from or spend.ms >= ms) then
				return nil
			end
			local start = debugprofilestop()
			spend.from = start
			return start + ms - spend.ms
		end,
		End = function()
			if spend.from then
				spend.ms = spend.ms + debugprofilestop() - spend.from
				spend.from = false
			end
		end,
		Spent = function(ms)
			ThisFrame()
			if spend.ms < ms then
				spend.ms = ms
			end
		end,
	}
end

--------------------------------------------------------------------------------
-- Tooltips: the title in gold, the body in the text colour, both looked up
-- in the palette when shown. `line`, when given, goes between them (a hint
-- the row cut short). `anchor`: where it hangs ("ANCHOR_RIGHT" when nil; a
-- window's top bar wants "ANCHOR_BOTTOM").
--------------------------------------------------------------------------------

function W.ShowTooltip(owner, title, body, line, anchor)
	local P = MelloUI.Palette
	local gold, text = P.selectedTrim, P.text
	GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
	GameTooltip:SetText(title, gold[1], gold[2], gold[3])
	if line and line ~= "" then
		GameTooltip:AddLine(line, text[1], text[2], text[3], true)
	end
	if body and body ~= "" then
		GameTooltip:AddLine(body, text[1], text[2], text[3], true)
	end
	GameTooltip:Show()
end

-- The handlers every row and control shares (user, 2026-09-24: a page of two
-- hundred rows made a dozen functions per row): one function each, wrapped
-- once, reading what it shows from the frame it runs on
local TipLeave = Shared("OnLeave on MelloUI's rows and controls (tooltip)", function()
	GameTooltip:Hide()
end, "script")
W.TipLeave = TipLeave

local clipped = setmetatable({}, weakKeys)   -- [row] = true: its texts end at its control (W.ClipRow)

-- a row's tooltip: its label and description (`tipTitle`, `tipBody`), and a
-- hint the row cut short
local RowTipEnter = Shared("OnEnter on MelloUI's rows (tooltip)", function(self)
	local cut
	if clipped[self] then
		local hint = self.hint
		if hint and hint:IsShown() and hint.IsTruncated and hint:IsTruncated() then
			cut = hint:GetText()
		end
		local label = self.label
		if not (cut or self.tipBody or (label and label.IsTruncated and label:IsTruncated())) then
			return
		end
	end
	W.ShowTooltip(self, self.tipTitle, self.tipBody, cut)
end, "script")
-- a row's switch or button: the row's tooltip, on the row, when the option
-- has a description
local ControlTipEnter = Shared("OnEnter on MelloUI's row controls (tooltip)", function(self)
	if self.tipBody then
		W.ShowTooltip(self.tipOwner, self.tipTitle, self.tipBody)
	end
end, "script")

-- a row's control carries the row's tooltip
local function ControlTip(control, row, title, body)
	control.tipOwner, control.tipTitle, control.tipBody = row, title, body
	Perf.HookScript(control, "OnEnter", ControlTipEnter)
	Perf.HookScript(control, "OnLeave", TipLeave)
end

--------------------------------------------------------------------------------
-- The kit's dressing (run through skin:Kit: now, or at the kit look's first
-- switch on). Shared functions, handed the widget: no closure per widget.
--------------------------------------------------------------------------------

local function DressSweep(K, root, skin, depth)
	K:SweepControls(root, skin.replace, skin.skin, nil, depth)
end

-- The kit's control sweep over `root` (Kit:SweepControls: red plates, check
-- boxes, dropdowns, tabs, found by what they are): the one way a window's
-- controls the kit knows are dressed. `depth`: where the sweep starts (the
-- configurator's rows at 2, as a sweep of the page reaches them). The own
-- windows' controls are flat (0.15.0: `melloRep` false, the sweep passes
-- them by); what a root holds of the game's own is dressed.
function W.Dress(root, skin, depth)
	if skin and root then
		skin:Kit(DressSweep, root, skin, depth)
	end
end

-- (0.15.0: the own windows' buttons, sliders, check boxes, dropdowns, tabs,
-- search box and close button are flat in both looks -- the kit's red
-- plate, B1, slider, SL1, check box, dropdown plate, D1, tab, TB6, search
-- box, S1, and red cross stay the game windows')

--------------------------------------------------------------------------------
-- The active look (Kit:SetActive, 0.15.0: the one look for whatever is
-- active or selected, the game's windows and MelloUI's own) on a widget: a
-- chosen card, an icon-less side list's marker, a ticked box, the selected
-- tab. It is the kit's art, so it shows only while the widget's window wears
-- the kit. The kit is the one the shell hands over (skin:Kit) the first time
-- a look shows, kept for the switches after: never reached for. `rect`: the
-- region the ring lies round (the widget), `shape`: the kit's ("rect": a
-- card, a tab; "square": a box).
--------------------------------------------------------------------------------

local activeKit = nil
local function ActiveNow(K, frame, on, rect, shape)
	activeKit = K
	K:SetActive(frame, on, rect or frame, shape or "rect")
end

local function WidgetActive(skin, frame, on, rect, shape)
	if not skin then
		return
	end
	if skin.kit then
		skin:Kit(ActiveNow, frame, on and true or false, rect, shape)
	elseif activeKit then
		activeKit:SetActive(frame, false)
	end
end

-- the flat widgets of each shell that wear the active look, laid again at
-- its switches (a ticked box, the selected tab): each answers
-- widget:melloActive() -> on, rect, shape, and widget:melloKitLook(), when
-- it has one, lays its own look again (a selected tab's gold edge gives way
-- to the ring in the kit's look)
local activeOf = setmetatable({}, weakKeys)   -- [shell] = { [widget] = true } (weak)
local function Actives_OnKit(shell)
	local set = activeOf[shell]
	if set then
		for widget in pairs(set) do
			if widget.melloKitLook then
				widget:melloKitLook()
			end
			WidgetActive(shell, widget, widget:melloActive())
		end
	end
end

local function FollowLook(skin, widget)
	if not (skin and skin.OnKit) then
		return
	end
	local set = activeOf[skin]
	if not set then
		set = setmetatable({}, weakKeys)
		activeOf[skin] = set
	end
	set[widget] = true
	skin:OnKit(Actives_OnKit)
end

--------------------------------------------------------------------------------
-- The flat controls' one set of handlers (0.15.0): the pointer on a control
-- and its state (enabled or not, shown) paint it again through its kind's
-- own look, control.melloLook(control, whole) (`whole`: its state changed,
-- every part painted; else only what the hover changes). The colours are
-- looked up when painted (a new palette paints them again).
--------------------------------------------------------------------------------

local flatHover = setmetatable({}, weakKeys)   -- [control] = true while the pointer is on it

local FlatEnter = Shared("OnEnter on MelloUI's flat controls", function(c)
	flatHover[c] = true
	c.melloLook(c)
end, "script")

local FlatLeave = Shared("OnLeave on MelloUI's flat controls", function(c)
	flatHover[c] = nil
	c.melloLook(c)
end, "script")

local FlatState = Shared("OnEnable / OnDisable / OnShow on MelloUI's flat controls", function(c)
	c.melloLook(c, true)
end, "script")

-- `shows`: its look laid again on every show too (a button's own fonts
-- change its label's colour while it is hidden)
local function FlatHooks(c, look, shows)
	c.melloLook = look
	Perf.HookScript(c, "OnEnter", FlatEnter)
	Perf.HookScript(c, "OnLeave", FlatLeave)
	Perf.HookScript(c, "OnEnable", FlatState)
	Perf.HookScript(c, "OnDisable", FlatState)
	if shows then
		Perf.HookScript(c, "OnShow", FlatState)
	end
	look(c, true)
end

--------------------------------------------------------------------------------
-- Switch (0.15.0, flat: user, 2026-09-29 "all flat"; it was the game's
-- check box, the kit's in its look): a check button SWITCH px square with
-- none of the game's art -- a box SWITCH_BOX px in its middle, an
-- `innerPanel` fill in a 1 px `trim` edge (the panels' `border` is too faint
-- for a box with nothing in it: 1.6:1), and, ticked, a check mark SWITCH_TICK
-- px in `selectedTrim` inside it -- the installer's done mark (TICK_ART, its
-- art desaturated and painted by key), a mark a player reads as "on" (a
-- filled square reads as "partly on": review, 2026-09-29): the button's own
-- checked texture, so the game shows it with the check (disabled: its
-- disabled-checked one, in `mutedText`). Under the pointer the edge takes
-- `selectedTrim`; disabled, the box at half. With the kit's look on (its
-- `skin`) a ticked box also wears the active look round the box, its tick
-- kept, as the kit's own check boxes do. `melloRep` is false, so the kit's
-- sweep (Kit:SweepControls, Kit:SkinCheckButton) passes it by.
-- SetValue(on, silent) sets it without (silent) or with set(on); Refresh()
-- takes get() again. A refresh that changes nothing leaves the box alone (a
-- tab's refresh set every box on it again -- user, 2026-09-24).
--   W.Switch(parent, get, set, opts) -> switch   opts: skin
--   switch.melloFill, switch.melloEdges (the box), switch.melloTick
--------------------------------------------------------------------------------

local SWITCH, SWITCH_BOX, SWITCH_TICK = 26, 18, 16
local TICK_ART = "Interface\\RaidFrame\\ReadyCheck-Ready"   -- the check mark (the installer's done mark too)

-- the box as the switch is: its edge lit under the pointer, at half while
-- disabled (its tick is the game's to show)
local function SwitchLook(cb)
	local on = cb:IsEnabled() and true or false
	local alpha = on and 1 or FLAT_OFF
	W.Paint(cb.melloFill, "innerPanel", "fill", alpha)
	local edge = (on and flatHover[cb]) and "selectedTrim" or "trim"
	local edges = cb.melloEdges
	for i = 1, 4 do
		W.Paint(edges[i], edge, "fill", alpha)
	end
end

-- (widget:melloActive: a ticked box wears the active look round its box)
local function SwitchActive(cb)
	return cb:GetChecked() and true or false, cb.melloFill, "square"
end

-- a tick: the check mark in the box's middle, painted by key (gold from the
-- palette, not the art's own green; over the box: the game draws a state
-- texture in its own layer, over the box's two); laid and painted again once
-- the button holds it (a state texture handed over may be laid over the
-- whole button)
local function Tick(tick, key)
	tick:SetTexture(TICK_ART)
	tick:SetDesaturated(true)
	tick:ClearAllPoints()
	tick:SetSize(SWITCH_TICK, SWITCH_TICK)
	tick:SetPoint("CENTER", tick:GetParent(), "CENTER", 0, 0)
	W.Paint(tick, key, "vertex", 1)
end

local function SwitchSetValue(self, on, silent)
	on = on and true or false
	if silent and on == self.value and (self:GetChecked() and true or false) == on then
		return
	end
	self.value = on
	self:SetChecked(on)
	WidgetActive(self.melloSkin, self, on, self.melloFill, "square")
	if not silent and self.melloSet then
		self.melloSet(on)
	end
end

local function SwitchRefresh(self)
	if self.melloGet then
		self:SetValue(self.melloGet() and true or false, true)
	end
end

local SwitchClick = Shared("OnClick on MelloUI's switches", function(self)
	local value = self:GetChecked() and true or false
	MelloUI:PlayUISound(value and "check_on" or "check_off")
	self:SetValue(value)
end, "script")

function W.Switch(parent, get, set, opts)
	local cb = CreateFrame("CheckButton", nil, parent)
	cb:SetSize(SWITCH, SWITCH)
	cb.melloRep = false   -- (the kit's sweep passes it by: no kit check box)
	local fill = cb:CreateTexture(nil, "BACKGROUND")
	fill:SetSize(SWITCH_BOX, SWITCH_BOX)
	fill:SetPoint("CENTER", cb, "CENTER", 0, 0)
	cb.melloFill, cb.melloEdges = fill, Edges(cb, "trim", "BORDER", fill)
	-- the ticks, the game showing the one for the button's state
	local tick = cb:CreateTexture(nil, "ARTWORK")
	cb:SetCheckedTexture(tick)
	Tick(tick, "selectedTrim")
	cb.melloTick = tick
	if cb.SetDisabledCheckedTexture then
		local off = cb:CreateTexture(nil, "ARTWORK")
		cb:SetDisabledCheckedTexture(off)
		Tick(off, "mutedText")
	end
	cb.value = false
	cb.melloGet, cb.melloSet = get, set
	cb.SetValue, cb.Refresh, cb.melloActive = SwitchSetValue, SwitchRefresh, SwitchActive
	Perf.SetScript(cb, "OnClick", SwitchClick)
	FlatHooks(cb, SwitchLook)
	local skin = opts and opts.skin
	if skin then
		cb.melloSkin = skin
		FollowLook(skin, cb)
	end
	return cb
end

--------------------------------------------------------------------------------
-- Dropdown (0.15.0, flat: user, 2026-09-29 "all flat"; it was the game's
-- dropdown button and its menu): a box that names the choice and opens
-- MelloUI's own list of them under it, in the window's one flyout (a
-- picture row's too: W.PictureMenu, below). Never the game's menu: a game
-- menu opened from MelloUI code runs the Gamepad UI's frame manager in
-- MelloUI's run and blocks its bindings (the Gamepad UI freeze, v150 freeze
-- plan WP5b), so the list is MelloUI's own whatever the mode. The box is a
-- picture row's: an `innerPanel` fill in a 1 px `border` edge, the choice in
-- `text` from its left, a small caret at its right in `text`; `hover` under
-- the pointer; disabled, at half and the choice in `mutedText`. `values` is
-- a list of { value, label, tooltip }, read whenever the box names the
-- choice or the list opens (a list filled again in place, or renamed in
-- place -- the Voice Over voices once the game has them, the Kit Colours
-- under a new palette -- is picked up by a refresh).
--   W.Dropdown(parent, width, get, set, values, opts) -> box   DD_H high
--     opts: default (the text shown while the value has no entry), tooltip
--     (the box's own tooltip body; its title is `default`), skin
--   box:Refresh()          the choice named again from get() (its text set
--                          only when it changed: nothing made)
--   box:SetValues(values)  another list on the box (0.15.0: a row whose
--                          setting is another key per pick): the choice
--                          named from it; a list open on the old one closes
--   box.Text, box.melloGet / melloSet / melloValues
-- The list (the flyout's list mode): a row per entry, LIST_ROW_H high, the
-- chosen one marked in gold, a row's tooltip its entry's; a click on a row
-- sets it and closes the list. A long list (user, 2026-09-26: "the list
-- does not have a slider option and is way too big" -- the Fonts dropdown's
-- sixty faces ran off the screen) shows at most MENU_ROWS entries and never
-- more than MENU_SCREEN of the screen, the rest by the wheel or its scroll
-- bar, the chosen one in view as it opens. It closes as the flyout does:
-- Escape, a click outside, the page scrolling, the box or the window
-- hidden, W.ClosePictureMenu (a tab, a page or a pick changed). Unlike a
-- picture row's it opens in combat, as the game's menu did. Nothing is made
-- until a list opens.
--------------------------------------------------------------------------------

local DropdownTip = Shared("OnEnter on MelloUI's dropdowns (tooltip)", function(self)
	W.ShowTooltip(self, self.melloTipTitle or "", self.melloTip)
end, "script")

-- Where `value` stands in the list (nil when it has no such entry): its
-- row's place in the list too, one row per entry
local function ChoiceIndex(values, value)
	if values then
		for i = 1, #values do
			if values[i].value == value then
				return i
			end
		end
	end
	return nil
end

-- An entry's text: its label, else its value as text (a string value as it
-- is: a refresh makes no string)
local function EntryText(entry)
	local value = entry.value
	return entry.label or (type(value) == "string" and value) or tostring(value)
end

-- The text the box shows for `value` (nil when the list has no such entry:
-- the box then shows its default text)
local function ChoiceLabel(values, value)
	local i = ChoiceIndex(values, value)
	return i and EntryText(values[i]) or nil
end

local DD_H = 25                -- the box's height
local DD_TEXT_X = 8            -- the choice's left in the box
local CARET = { 7, 5, 3, 1 }   -- the caret's lines, top down: a small triangle (px)
local CARET_X = 9              -- its widest line's right end from the box's right

-- the box as it is: its fill (the hover) always; `whole`, its state
-- (enabled or not) too -- the edge, the choice's colour, the caret
local function DropdownLook(dd, whole)
	local on = dd:IsEnabled() and true or false
	local alpha = on and 1 or FLAT_OFF
	W.Paint(dd.melloFill, (on and flatHover[dd]) and "hover" or "innerPanel", "fill", alpha)
	if whole then
		local edges, caret = dd.melloEdges, dd.melloCaret
		for i = 1, 4 do
			W.Paint(edges[i], "border", "fill", alpha)
		end
		for i = 1, #caret do
			W.Paint(caret[i], "text", "fill", alpha)
		end
		W.Paint(dd.Text, on and "text" or "mutedText", "text")
	end
end

local function DropdownRefresh(self)
	local label = ChoiceLabel(self.melloValues, self.melloGet and self.melloGet()) or self.melloDefault or ""
	if label ~= self.shownLabel then
		self.shownLabel = label
		self.Text:SetText(label)
	end
end

local function DropdownSetValues(self, values)
	if values == self.melloValues then
		return
	end
	self.melloValues = values
	Flyout.BoxHidden(self)   -- (a list open on the old one closes)
	self:Refresh()
end

local DropdownClick = Shared("OnClick on MelloUI's dropdowns (its list)", function(self)
	Flyout.Toggle(self)
end, "script")

function W.Dropdown(parent, width, get, set, values, opts)
	opts = opts or NO_OPTS
	local dd = CreateFrame("Button", nil, parent)
	dd:SetSize(width, DD_H)
	dd.melloRep = false   -- (the kit's sweep passes it by: no dropdown plate)
	dd.melloList = true   -- (it opens the flyout's list: W.PictureMenu's block)
	dd.melloFill = dd:CreateTexture(nil, "BACKGROUND")
	dd.melloFill:SetAllPoints(dd)
	dd.melloEdges = Edges(dd, "border", "BORDER")
	local caret = {}
	for i, w in ipairs(CARET) do
		local line = dd:CreateTexture(nil, "ARTWORK")
		line:SetSize(w, 1)
		line:SetPoint("TOPRIGHT", dd, "RIGHT", -(CARET_X + (CARET[1] - w) / 2), 3 - i)
		caret[i] = line
	end
	dd.melloCaret = caret
	local text = W.Text(dd, "GameFontHighlight", nil, "text")
	text:SetJustifyV("MIDDLE")
	text:SetWordWrap(false)
	text:SetPoint("LEFT", dd, "LEFT", DD_TEXT_X, 0)
	text:SetPoint("RIGHT", dd, "RIGHT", -(CARET_X + CARET[1] + 6), 0)
	dd.Text = text
	dd.melloGet, dd.melloSet, dd.melloValues = get, set, values
	dd.melloDefault, dd.melloSkin = opts.default, opts.skin
	dd.Refresh, dd.SetValues = DropdownRefresh, DropdownSetValues
	Perf.SetScript(dd, "OnClick", DropdownClick)
	Perf.SetScript(dd, "OnHide", Flyout.BoxHidden)
	FlatHooks(dd, DropdownLook)
	if opts.tooltip then
		dd.melloTipTitle, dd.melloTip = opts.default, opts.tooltip
		Perf.HookScript(dd, "OnEnter", DropdownTip)
		Perf.HookScript(dd, "OnLeave", TipLeave)
	end
	dd:Refresh()
	return dd
end

--------------------------------------------------------------------------------
-- Slider (0.15.0, Sliders 1, the cleaner look the user picked; it was the
-- game's minimal slider with steppers and the kit's SL1 pieces): a thin track
-- 4 px high (`innerPanel` in a 1 px `border` edge), the part from the least
-- value to the knob in `trim`, a round knob 14 px in `selectedTrim` in a
-- 1 px `innerPanel` ring, and the value in a small box you can type in
-- (46 x 20, `innerPanel` in a `border` edge, the text colour; wider, up to
-- 96, where the format names a value in words -- "Edit Mode's", "no limit"
-- -- the track the shorter for it). No steppers, no gem ends, in both looks.
-- The wheel is not taken: the page scrolls.
-- The box never takes the keyboard by itself (an edit box made shown takes
-- the focus, and a page of them would hold the movement keys while the
-- window is open): only a click gives it the focus. Enter, Tab or leaving it
-- takes the number (a percent slider "40" or "40%"), kept in the range and
-- rounded to the step, and lets the focus go; Escape puts the value back and
-- lets it go (the window never sees that Escape); the window's hide lets it
-- go too, the value put back.
--   W.Slider(parent, width, get, set, opts) -> slider   a Frame `width` wide
--     and 20 high: the track `width - W.SLIDER_BOX` (54) from its left, the
--     box at its right (a box wider for its words: the track that much
--     shorter)
--     opts: min (0), max (1), step (0.05), percent, format (fn(v) -> text),
--     skin (kept for the callers: a flat slider has nothing to dress)
--   slider:Refresh()   get() again (the box left alone while it is typed in)
--   slider:SetRange(min, max, step[, percent, format])   another range (a
--     row whose setting is another key per pick): the value put in it
--   slider.Slider (the track's Slider frame), slider.box (the EditBox),
--   slider.melloGet / melloSet; W.Round(value, step)
-- Its handlers are shared (no closure per slider); nothing runs while it is
-- left alone.
--------------------------------------------------------------------------------

do
	local function Round(value, step)
		if not step or step <= 0 then
			return value
		end
		local n = math.floor(value / step + 0.5) * step
		local digits, s = 0, step
		while s < 1 and digits < 6 do
			s = s * 10
			digits = digits + 1
		end
		local mult = 10 ^ digits
		return math.floor(n * mult + 0.5) / mult
	end
	W.Round = Round

	local function PercentText(v)
		return string.format("%d%%", math.floor(v * 100 + 0.5))
	end
	local function PlainText(v)
		if math.abs(v - math.floor(v + 0.5)) < 0.001 then
			return tostring(math.floor(v + 0.5))
		end
		return string.format("%.2f", v)
	end

	local SLIDER_H = 20          -- the slider's frame: the box's height
	local TRACK_H = 4            -- the track, its 1 px edge included
	local KNOB = 14              -- the knob, its 1 px ring included
	local BOX_W, BOX_GAP = 46, 8 -- the value box (its least width), and the room between the track and it
	local BOX_MAX = 96           -- the widest a box grows for its texts
	local BOX_INSET = 3          -- the box's text insets, left and right
	local BOX_LETTERS = 10       -- the least a box takes typed (more when a text of its value is longer)
	local BOX_FONT = "GameFontHighlight"
	W.SLIDER_BOX = BOX_W + BOX_GAP   -- the slider's width less the track's (a box wider for its words takes more)

	-- the value as the box shows it
	local function ValueText(slider, v)
		local fmt = slider.melloFormat or (slider.melloPercent and PercentText) or PlainText
		return fmt(v)
	end

	-- the one hidden text the boxes' texts are measured on (made with the
	-- first slider, never at load)
	local measure = nil

	local function MeasuredWidth(parent, text)
		if not measure then
			measure = parent:CreateFontString(nil, "BACKGROUND", BOX_FONT)
			measure:Hide()
		end
		measure:SetText(text)
		local get = measure.GetUnboundedStringWidth or measure.GetStringWidth
		return Num(get(measure)) or 0
	end

	-- The box as wide as the widest text its value shows at the range's ends
	-- and at 0, where a format names the value in words ("Edit Mode's", "no
	-- limit", "Default"): BOX_W to BOX_MAX, the track giving the room (the
	-- slider keeps its width); it takes as many letters as its longest text.
	-- At the make and on SetRange only.
	local function FitBox(slider)
		local min, max = slider.melloMin, slider.melloMax
		local widest, letters = 0, BOX_LETTERS
		for i = 1, 3 do
			if i < 3 or (min <= 0 and max >= 0) then
				local text = tostring(ValueText(slider, (i == 1 and min) or (i == 2 and max) or 0))
				widest = math.max(widest, MeasuredWidth(slider, text))
				letters = math.max(letters, #text)
			end
		end
		local boxW = math.max(BOX_W, math.min(BOX_MAX, math.ceil(widest) + 2 * BOX_INSET + 2))
		slider.box:SetMaxLetters(letters)
		slider.box:SetWidth(boxW)
		slider.Slider:SetWidth(math.max(KNOB, slider.melloWidth - boxW - BOX_GAP))
	end

	-- the box shows `v` (the value only when it changed: a refresh of an
	-- unchanged row makes no string)
	local function ShowValue(slider, v)
		if v ~= slider.shownValue then
			slider.shownValue = v
			slider.box:SetText(ValueText(slider, v))
		end
	end

	-- the slider's value moved (a drag, a click on the track, a SetValue): kept
	-- to the step and handed to set, the box following
	local SliderChanged = Shared("OnValueChanged on MelloUI's sliders", function(track, value)
		local slider = track.melloSlider
		if not slider or slider.refreshing then
			return
		end
		value = Round(value, slider.melloStep)
		if slider.melloGet() ~= value then
			slider.melloSet(value)
		end
		ShowValue(slider, value)
	end, "script")

	local function SliderRefresh(self)
		local v = self.melloGet() or self.melloMin
		self.refreshing = true
		self.Slider:SetValue(v)
		self.refreshing = false
		if not self.box:HasFocus() then
			ShowValue(self, v)
		end
	end

	local function SliderSetRange(self, min, max, step, percent, format)
		self.melloMin, self.melloMax, self.melloStep = min or 0, max or 1, step or 0.05
		if percent ~= nil or format ~= nil then
			self.melloPercent, self.melloFormat = percent and true or false, format
		end
		self.refreshing = true
		self.Slider:SetMinMaxValues(self.melloMin, self.melloMax)
		self.Slider:SetValueStep(self.melloStep)
		self.refreshing = false
		FitBox(self)
		self.shownValue = nil   -- (the text again: another format, or the same number in a new range)
		self:Refresh()
	end

	-- The number typed in the box: its first number ("40%", "40", "1.5x"),
	-- a hundredth of it on a percent slider, kept in the range and rounded to
	-- the step; nil for none
	local function TypedValue(slider, text)
		local n = tonumber(tostring(text or ""):match("%-?%d*%.?%d+"))
		if not n then
			return nil
		end
		if slider.melloPercent then
			n = n / 100
		end
		n = Round(n, slider.melloStep)
		return math.max(slider.melloMin, math.min(slider.melloMax, n))
	end

	-- the typed number taken (none: the value put back); the box shows the
	-- value as it is after
	local function TakeTyped(box)
		local slider = box.melloSlider
		local v = TypedValue(slider, box:GetText())
		if v ~= nil then
			slider.Slider:SetValue(v)
			if slider.melloGet() ~= v then
				slider.melloSet(v)   -- (the slider was there already: no OnValueChanged)
			end
		else
			v = slider.melloGet() or slider.melloMin
		end
		slider.shownValue = nil
		ShowValue(slider, v)
	end

	-- the focus let go, the number taken (`take`) or the value put back; the
	-- focus-lost that follows takes nothing again
	local function LetGo(box, take)
		if take then
			TakeTyped(box)
		else
			local slider = box.melloSlider
			slider.shownValue = nil
			ShowValue(slider, slider.melloGet() or slider.melloMin)
		end
		if box:HasFocus() then
			box.melloLetGo = true
			box:ClearFocus()
		end
	end

	local BoxTake = Shared("OnEnterPressed / OnTabPressed on a slider's value box", function(box)
		LetGo(box, true)
	end, "script")

	local BoxEscape = Shared("OnEscapePressed on a slider's value box", function(box)
		LetGo(box, false)
	end, "script")

	local BoxFocusGained = Shared("OnEditFocusGained on a slider's value box", function(box)
		box:HighlightText()
	end, "script")

	-- a click elsewhere: the number taken (the box's own Enter, Tab or Escape
	-- already had its say)
	local BoxFocusLost = Shared("OnEditFocusLost on a slider's value box", function(box)
		if box.melloLetGo then
			box.melloLetGo = nil
			return
		end
		TakeTyped(box)
	end, "script")

	-- the window hidden (the box with it): the focus let go, the value back
	local BoxHidden = Shared("OnHide on a slider's value box", function(box)
		if box:HasFocus() then
			LetGo(box, false)
		end
	end, "script")

	-- a disc of the knob under its own round mask
	local function KnobMask(frame, disc)
		local mask = frame:CreateMaskTexture()
		mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(disc)
		disc:AddMaskTexture(mask)
	end

	-- the track: its edge and fill, the value's part in `trim`, the round knob
	-- (the thumb: the ring, the knob's disc on it, each under its round mask)
	local function SliderTrack(slider, width)
		local track = CreateFrame("Slider", nil, slider)
		track:SetOrientation("HORIZONTAL")
		track:SetSize(width - W.SLIDER_BOX, KNOB)
		track:SetPoint("LEFT", slider, "LEFT", 0, 0)
		track:EnableMouse(true)
		track:EnableMouseWheel(false)
		track.melloSlider = slider
		local edge = W.Solid(track, "BACKGROUND", "border", 1)
		edge:SetHeight(TRACK_H)
		edge:SetPoint("LEFT", track, "LEFT", 0, 0)
		edge:SetPoint("RIGHT", track, "RIGHT", 0, 0)
		local fill = W.Solid(track, "BACKGROUND", "innerPanel", 1)
		fill:SetDrawLayer("BACKGROUND", 1)
		fill:SetHeight(TRACK_H - 2)
		fill:SetPoint("LEFT", track, "LEFT", 1, 0)
		fill:SetPoint("RIGHT", track, "RIGHT", -1, 0)
		local ring = track:CreateTexture(nil, "OVERLAY", nil, 0)
		ring:SetSize(KNOB, KNOB)
		W.Paint(ring, "innerPanel", "fill", 1)
		track:SetThumbTexture(ring)
		local knob = track:CreateTexture(nil, "OVERLAY", nil, 1)
		knob:SetSize(KNOB - 2, KNOB - 2)
		knob:SetPoint("CENTER", ring, "CENTER", 0, 0)
		W.Paint(knob, "selectedTrim", "fill", 1)
		KnobMask(track, ring)
		KnobMask(track, knob)
		-- (from the least value to the knob's middle: it moves with the knob)
		local part = W.Solid(track, "ARTWORK", "trim", 1)
		part:SetHeight(TRACK_H - 2)
		part:SetPoint("LEFT", track, "LEFT", 1, 0)
		part:SetPoint("RIGHT", ring, "CENTER", 0, 0)
		track.edge, track.fill, track.part, track.knob, track.ring = edge, fill, part, knob, ring
		Perf.SetScript(track, "OnValueChanged", SliderChanged)
		return track
	end

	-- the value's box: never the keyboard's until clicked
	local function SliderBox(slider)
		local box = CreateFrame("EditBox", nil, slider)
		box:SetAutoFocus(false)
		box:SetSize(BOX_W, SLIDER_H)
		box:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
		box:SetFontObject(BOX_FONT)
		box:SetJustifyH("CENTER")
		box:SetTextInsets(BOX_INSET, BOX_INSET, 0, 0)
		box:SetMaxLetters(BOX_LETTERS)
		box:EnableMouse(true)
		box:EnableMouseWheel(false)
		W.Paint(box, "text", "text")
		local fill = box:CreateTexture(nil, "BACKGROUND")
		fill:SetAllPoints(box)
		W.Paint(fill, "innerPanel", "fill", 1)
		box.fill, box.edges = fill, Edges(box, "border", "BORDER")
		box.melloSlider = slider
		Perf.SetScript(box, "OnEnterPressed", BoxTake)
		Perf.SetScript(box, "OnTabPressed", BoxTake)
		Perf.SetScript(box, "OnEscapePressed", BoxEscape)
		Perf.SetScript(box, "OnEditFocusGained", BoxFocusGained)
		Perf.SetScript(box, "OnEditFocusLost", BoxFocusLost)
		Perf.SetScript(box, "OnHide", BoxHidden)
		return box
	end

	function W.Slider(parent, width, get, set, opts)
		opts = opts or NO_OPTS
		local min, max, step = opts.min or 0, opts.max or 1, opts.step or 0.05
		local slider = CreateFrame("Frame", nil, parent)
		slider:SetSize(width, SLIDER_H)
		slider:EnableMouseWheel(false)
		slider.melloGet, slider.melloSet = get, set
		slider.melloMin, slider.melloMax, slider.melloStep = min, max, step
		slider.melloPercent, slider.melloFormat = opts.percent and true or false, opts.format
		slider.melloWidth = width
		slider.refreshing = false
		slider.box = SliderBox(slider)
		local track = SliderTrack(slider, width)
		slider.Slider = track
		slider.refreshing = true
		track:SetMinMaxValues(min, max)
		track:SetValueStep(step)
		track:SetObeyStepOnDrag(true)
		slider.refreshing = false
		FitBox(slider)
		slider.Refresh, slider.SetRange = SliderRefresh, SliderSetRange
		slider:Refresh()
		return slider
	end
end

--------------------------------------------------------------------------------
-- Buttons (0.15.0, Buttons 1, the cleaner look the user picked; they were
-- the kit's red plate, B1): the game's panel button, flat in both looks --
-- the template's plate art hidden, a `raisedPanel` fill in a 1 px `border`
-- edge (W.Edges), the label in the text colour. Under the mouse the fill
-- takes `hover`; pressed, the label goes 1 px down (the button's own pushed
-- text offset); disabled, the fill and the edge at half and the label in
-- `mutedText`. The main action (opts.gold: Install..., Install again, the
-- installer's forward button, Restock's Buy, a question's accept) wears its
-- edge and label in `selectedTrim` (its label `text` on the hover fill). No
-- gem caps: `melloRep` is false before any sweep, so the kit's
-- (Kit:SweepControls, Kit:SkinRedButton) passes it by, whatever window it
-- is in.
--   W.Button(parent, text, width, skin, opts) -> button
--     opts: height (22), onClick (a shared handler), gold
--     (`skin` kept for the callers: a flat button has nothing to dress)
--   W.FlatButton(button, gold) -> button   the same look on a button made
--     by hand from UIPanelButtonTemplate (its creation line kept); once
--   button.melloFill, button.melloEdges (button.melloOutline: the gold edge)
-- The flat controls' one set of handlers (FlatHooks); the colours looked
-- up in the palette when painted (a new palette paints them again).
--   W.CloseButton(parent, skin) -> button   (0.15.0, flat: user, 2026-09-29
--     "all flat"; it was the game's red cross, RedButton-Exit in the kit's
--     look): a flat button CLOSE px square with a cross in `text` -- the
--     search box's own (common-search-clearbutton), the one cross of the
--     own windows. The click is the caller's (the configurator's, the
--     shell's), as it always was; `skin` kept for the callers.
--   button.melloCross
--------------------------------------------------------------------------------

do
	local PLATE_PARTS = { "Left", "Middle", "Right", "Center" }   -- the template's plate (the older and the 128 red one)
	local PLATE_TEXTURES = { "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }
	local flatGold = setmetatable({}, weakKeys)    -- [button] = true: the main action's
	local CLOSE, CROSS = 22, 12                    -- the close button, its cross
	local CROSS_ART = "common-search-clearbutton"  -- (the game's search box's cross: SearchBoxTemplate)

	-- The look as the button is (`edges`: its edge too -- it changes only
	-- with the button's state, not its hover). The label is painted every time:
	-- the button's own font changes (normal / highlight / disabled) take its
	-- colour. A gold label on the hover fill would be too faint (the
	-- palette's rule: only `text` on `hover`), so under the pointer the main
	-- action's label is `text`, its edge still gold.
	local function FlatLook(b, edges)
		local on = b:IsEnabled() and true or false
		local alpha = on and 1 or FLAT_OFF
		local gold = flatGold[b]
		local lit = on and flatHover[b]
		W.Paint(b.melloFill, lit and "hover" or "raisedPanel", "fill", alpha)
		if edges then
			local key = gold and "selectedTrim" or "border"
			for i = 1, 4 do
				W.Paint(b.melloEdges[i], key, "fill", alpha)
			end
		end
		local fs = b:GetFontString()
		if fs then
			W.Paint(fs, (not on and "mutedText") or (gold and not lit and "selectedTrim") or "text", "text")
		end
	end

	function W.FlatButton(b, gold)
		if not b or b.melloFill then
			return b
		end
		b.melloRep = false   -- (the kit's sweep passes it by: no red plate, no gem caps)
		for _, key in ipairs(PLATE_PARTS) do
			local part = rawget(b, key)
			if part then
				part:SetAlpha(0)
				part:Hide()
			end
		end
		for _, getter in ipairs(PLATE_TEXTURES) do
			local tex = b[getter] and b[getter](b)
			if tex then
				tex:SetAlpha(0)
			end
		end
		b.melloFill = b:CreateTexture(nil, "BACKGROUND", nil, 2)
		b.melloFill:SetAllPoints(b)
		b.melloEdges = Edges(b, "border", "BORDER")
		flatGold[b] = gold and true or nil
		if gold then
			b.melloOutline = b.melloEdges
		end
		if b.SetPushedTextOffset then
			b:SetPushedTextOffset(0, -1)
		end
		FlatHooks(b, FlatLook, true)
		return b
	end

	function W.Button(parent, text, width, skin, opts)
		local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		b:SetSize(width or 110, opts and opts.height or 22)
		b:SetText(text or "")
		if opts and opts.onClick then
			Perf.SetScript(b, "OnClick", opts.onClick)
		end
		return W.FlatButton(b, opts and opts.gold)
	end

	function W.CloseButton(parent, skin)
		local close = CreateFrame("Button", nil, parent)
		close:SetSize(CLOSE, CLOSE)
		W.FlatButton(close)
		local cross = close:CreateTexture(nil, "ARTWORK")
		cross:SetAtlas(CROSS_ART)
		cross:SetSize(CROSS, CROSS)
		cross:SetPoint("CENTER", close, "CENTER", 0, 0)
		W.Paint(cross, "text", "vertex")
		close.melloCross = cross
		return close
	end
end

--------------------------------------------------------------------------------
-- Tabs (0.15.0, flat: user, 2026-09-29 "all flat"; they were the kit's tab
-- art, TB6, and the game's own in the plain look): a page's tab -- the
-- game's top tab (PanelTopTabButtonTemplate), made by the caller (the
-- configurator's pages) -- its art hidden, the tab TAB_H high and a flat
-- plate on it, TAB_IN inside its sides (tabs laid 6 px over each other stand
-- 2 px apart): at rest `raisedPanel` in a 1 px `border` edge, `hover` under
-- the pointer; the selected one `selectedTab` in a `selectedTrim` edge. The
-- label is `text` in every state (gold on the selected tab's fill is under
-- 4.5:1 in Ember) and stays in the plate's middle (the game's select bobs it
-- up and down). With the kit's look on (its `skin`) the selected tab wears
-- the active look round its plate, the gold edge then giving way to the
-- resting one under the ring (as a chosen card's). `melloRep` is false, so
-- the kit's sweep (Kit:SkinPanelTab) passes it by. The tab keeps the width
-- its owner gives it: the template's own resize on a show and on a display
-- change is dropped (it undid the owner's padding: the tabs' gaps jumped).
--   W.FlatTab(tab, skin) -> tab   once per tab; then
--   tab:SetSelected(on)   the selected look; the selected tab disabled, as
--                         the game's select makes it (a click on it does
--                         nothing), its tooltip hidden
--   tab.melloFill (the plate), tab.melloEdges
--------------------------------------------------------------------------------

do
	local TAB_H, TAB_IN = 24, 4   -- the tab's height (its plate's), and the plate inside its sides
	local TAB_ART = { "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive",
		"LeftHighlight", "MiddleHighlight", "RightHighlight" }
	local tabOn = setmetatable({}, weakKeys)   -- [tab] = true: the selected one

	-- the whole look, every time (a tab has few parts): its fill by state and
	-- hover, the edge gold on the selected tab unless the ring lies on it, the
	-- label painted again (the button's own fonts change its colour)
	local function TabLook(tab)
		local on = tabOn[tab] == true
		local lit = flatHover[tab] and not on
		W.Paint(tab.melloFill, (on and "selectedTab") or (lit and "hover") or "raisedPanel", "fill", 1)
		local skin = tab.melloSkin
		local key = (on and not (skin and skin.kit)) and "selectedTrim" or "border"
		local edges = tab.melloEdges
		for i = 1, 4 do
			W.Paint(edges[i], key, "fill", 1)
		end
		local fs = tab.Text
		if fs then
			W.Paint(fs, "text", "text")
		end
	end

	-- (widget:melloActive: the selected tab wears the active look round its plate)
	local function TabActive(tab)
		return tabOn[tab] == true, tab.melloFill, "rect"
	end

	local function TabSetSelected(tab, on)
		on = on and true or false
		tabOn[tab] = on or nil
		tab:SetEnabled(not on)
		if on and GameTooltip:GetOwner() == tab then
			GameTooltip:Hide()
		end
		TabLook(tab)
		WidgetActive(tab.melloSkin, tab, on, tab.melloFill, "rect")
	end

	function W.FlatTab(tab, skin)
		if not tab or tab.melloFill then
			return tab
		end
		tab.melloRep = false   -- (the kit's sweep passes it by: no TB6)
		for _, key in ipairs(TAB_ART) do
			local art = rawget(tab, key)
			if art then
				art:SetAlpha(0)
			end
		end
		-- (the tab as tall as its plate, and its hidden open-tab art too: the
		-- height its owner lays the tab row by; a New badge on its top edge
		-- then lies on the plate's)
		tab:SetHeight(TAB_H)
		local open = rawget(tab, "MiddleActive")
		if open then
			open:SetHeight(TAB_H)
		end
		local fill = tab:CreateTexture(nil, "BACKGROUND", nil, 2)
		fill:SetPoint("TOPLEFT", tab, "TOPLEFT", TAB_IN, 0)
		fill:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -TAB_IN, 0)
		tab.melloFill, tab.melloEdges = fill, Edges(tab, "border", "BORDER", fill)
		local fs = tab.Text
		if fs then
			fs:ClearAllPoints()
			fs:SetPoint("CENTER", fill, "CENTER", 0, 0)
		end
		-- (the owner's width kept: the template sizes the tab again on a show
		-- and on a display change, to its own padding)
		Perf.SetScript(tab, "OnShow", nil)
		tab:UnregisterEvent("DISPLAY_SIZE_CHANGED")
		tab.melloSkin = skin
		tab.SetSelected, tab.melloActive, tab.melloKitLook = TabSetSelected, TabActive, TabLook
		FlatHooks(tab, TabLook)
		FollowLook(skin, tab)
		return tab
	end
end

--------------------------------------------------------------------------------
-- The search box (0.15.0, flat: user, 2026-09-29 "all flat"; it was the
-- kit's S1 in the kit's look, the game's own in the plain one): the game's
-- search box (SearchBoxTemplate), made by the caller (the configurator's
-- side list), in the slider value box's look -- its Left / Middle / Right
-- art hidden, an `innerPanel` fill in a 1 px `border` edge (`trim` while it
-- has the keyboard) over the art's own span (from SEARCH_LEFT px left of the
-- box: the magnifying glass inside it). The prompt in `mutedText` (the
-- palette's hint colour); the glass `mutedText` while the box is idle and
-- `text` in use (the game's own two shades of it, by key); the clear
-- button's cross in `text`. What is typed is the caller's to colour (the
-- configurator's is `text`). `melloRep` is false, so the kit's sweep
-- (Kit:SkinSearchBox) passes it by. A plain text field made by hand from
-- InputBoxTemplate (the Profiles page's name, Help's links: review,
-- 2026-09-29, "all flat") takes the same look: its Left / Middle / Right are
-- the same art at the same span, and it has no glass, prompt or cross.
--   W.FlatField(box) -> box   once per box (a search box or a plain field)
--   W.FlatSearch(box)         the same (the configurator's search box)
--   box.melloFill, box.melloEdges
--------------------------------------------------------------------------------

do
	local SEARCH_LEFT = 5   -- the game's art reaches this far left of the box
	local SEARCH_ART = { "Left", "Middle", "Right" }

	-- the glass in use (the keyboard in the box, or a text in it) or idle:
	-- after the game's own scripts, which tint it themselves
	local function Glass(box)
		local glass = box.searchIcon
		if glass then
			local text = box:GetText()
			W.Paint(glass, (box:HasFocus() or (text and text ~= "")) and "text" or "mutedText", "vertex")
		end
	end

	local SearchFocus = Shared("OnEditFocusGained / OnEditFocusLost on MelloUI's text fields", function(box)
		local key = box:HasFocus() and "trim" or "border"
		local edges = box.melloEdges
		for i = 1, 4 do
			W.Paint(edges[i], key, "fill", 1)
		end
		Glass(box)
	end, "script")

	local SearchText = Shared("OnTextChanged on MelloUI's search boxes (the glass)", function(box)
		Glass(box)
	end, "script")

	function W.FlatField(box)
		if not box or box.melloFill then
			return box
		end
		box.melloRep = false   -- (the kit's sweep passes it by: no S1)
		for _, key in ipairs(SEARCH_ART) do
			local art = rawget(box, key)
			if art then
				art:SetAlpha(0)
			end
		end
		local fill = box:CreateTexture(nil, "BACKGROUND", nil, 2)
		fill:SetPoint("TOPLEFT", box, "TOPLEFT", -SEARCH_LEFT, 0)
		fill:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
		W.Paint(fill, "innerPanel", "fill", 1)
		box.melloFill, box.melloEdges = fill, Edges(box, "border", "BORDER", fill)
		if box.Instructions then
			W.Paint(box.Instructions, "mutedText", "text")
		end
		local clear = box.clearButton
		if clear and clear.Icon then
			W.Paint(clear.Icon, "text", "vertex")
		end
		Perf.HookScript(box, "OnEditFocusGained", SearchFocus)
		Perf.HookScript(box, "OnEditFocusLost", SearchFocus)
		if box.searchIcon then
			Perf.HookScript(box, "OnTextChanged", SearchText)
		end
		SearchFocus(box)
		return box
	end
	W.FlatSearch = W.FlatField
end

--------------------------------------------------------------------------------
-- IconBox: a framed icon -- the client's action button bevel around a
-- rounded icon, grey at rest, gold when selected, the text colour while
-- hovered; with the kit, the rim every window's buttons wear (UI
-- Modifications' Button Border, swapped live with it, in the Kit Colours
-- look -- user, 2026-09-24) over the icon in its square opening.
--   box:SetIcon(texture)   box:SetSelected(on)   box:SetPressed(on)
--   box:SetHovered(on)     box:SetOn(on)         box:SetGlow(on)
--   box:SetKit(on)         the icon laid again for the look (a box made with
--                          a shell follows its switches)
--------------------------------------------------------------------------------

-- MelloUI's own logo art is shown whole; a game icon loses its baked border
local NO_CROP = { [TEXTURE_PATH .. "LogoIcon.tga"] = true, [TEXTURE_PATH .. "LogoFull.tga"] = true }

local function IconBox_SetIcon(self, texture)
	self.icon:SetTexture(texture)
	if texture ~= nil and not NO_CROP[texture] then
		self.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
		self.cropped = true
	elseif self.cropped then
		self.icon:SetTexCoord(0, 1, 0, 1)
		self.cropped = false
	end
end

local function IconBox_SetSelected(self, selected)
	self.selected = selected and true or false
	W.Paint(self.frame, self.selected and "selectedTrim" or "mutedText", "vertex", 1)
	if self.rim and self.rim.Update then
		self.rim:Update()
	end
end

local function IconBox_SetPressed(self, pressed)
	if self.rim and self.rim.Update then
		self.rim.pressed = pressed and true or nil
		self.rim:Update()
	end
end

local function IconBox_SetHovered(self, hovered)
	if hovered then
		W.Paint(self.frame, "text", "vertex", 1)
	else
		self:SetSelected(self.selected)
	end
	if self.rim and self.rim.Update then
		self.rim.hover = hovered and true or nil
		self.rim:Update()
	end
end

local function IconBox_SetOn(self, on)
	self.icon:SetDesaturated(not on)
	self.icon:SetAlpha(on and 1 or 0.45)
end

-- the glow's size: from the rim with the kit (centred on the box, the rim's
-- centre), so the light is symmetric around the iron (user, 2026-09-22)
local function GlowSize(self)
	local rim = self.kitLaid and self.size * RIM_GROW or self.size
	return rim * 1.45
end

-- a pulsing gold glow over the rim (the action button's proc glow, additive
-- light on top of the iron -- user, 2026-09-22), for an important module;
-- under Reduce Motion a still glow at full strength (Anim:Pulse)
local function IconBox_SetGlow(self, on)
	if on and not self.glow then
		local glow = self:CreateTexture(nil, "OVERLAY", nil, 7)
		glow:SetTexture(GLOW_ART)
		glow:SetBlendMode("ADD")
		W.Paint(glow, "selectedTrim", "vertex")
		local size = GlowSize(self)
		glow:SetSize(size, size)
		glow:SetPoint("CENTER", self, "CENTER", 0, 0)
		self.glow = glow
		self.glowAnim = MelloUI.Anim:Pulse(glow, 0.45, 1, 0.9)
	elseif self.glow then
		self.glow:SetShown(on and true or false)
		if on then
			MelloUI.Anim:Pulse(self.glow)   -- its group, played again
		else
			MelloUI.Anim:StopGroup(self.glowAnim)   -- not played again when Reduce Motion goes off
		end
	end
end

-- The icon for the look: with the kit at 0.9 of the box, centred, until the
-- rim fits it into its square opening (no rounded mask, as on the action
-- bars); without it the whole box with the bevel's rounded corners. Same
-- construction as an action button (a 45 px icon, the 46 x 45 bevel on its
-- top left corner, the corner mask at its native size centred on the icon),
-- scaled to this size.
local maskOf = setmetatable({}, weakKeys)   -- [box] = its icon's mask (no field: a box's parts keep their names)

local function IconBox_SetKit(self, on)
	on = on and true or false
	local size, icon, mask = self.size, self.icon, maskOf[self]
	icon:ClearAllPoints()
	if on then
		icon:SetPoint("CENTER", self, "CENTER")
		icon:SetSize(size * 0.9, size * 0.9)
	else
		icon:SetAllPoints()
	end
	local k = size / 45
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(ICON_MASK)
	if info and info.width and info.height then
		local ik = on and k * 0.9 or k   -- the corner mask at the icon's size
		mask:SetSize(info.width * ik, info.height * ik)
		mask:SetPoint("CENTER", icon, "CENTER")
	else
		mask:SetAllPoints(icon)
	end
	if on and self.masked then
		icon:RemoveMaskTexture(mask)
		self.masked = false
	elseif not on and not self.masked then
		icon:AddMaskTexture(mask)
		self.masked = true
	end
	self.kitLaid = on
	if self.glow then
		local s = GlowSize(self)
		self.glow:SetSize(s, s)
	end
end

-- the rim, as regions of the BOX (the icon's own frame) so it draws over the
-- icon; its rect the box grown by 10 % about its centre; its states the
-- box's: pressed, hover, and selected (checked: the kit's active look,
-- Kit:SetActive, round the rim)
local function DressIconBox(K, box, skin)
	local size = box.size
	local rimRect = CreateFrame("Frame", nil, box)
	rimRect:SetPoint("CENTER", box, "CENTER")
	rimRect:SetSize(size * RIM_GROW, size * RIM_GROW)
	rimRect:EnableMouse(false)
	local rep = skin:Replace(box.frame, { as = K:ButtonRimRule(), rect = rimRect, button = box, icon = box.icon,
		checked = box.melloChecked })
	box.rim = rep and rep.object or nil
	if rep then
		box.melloRep = rep
		K:RegisterButtonRim(box)
	end
end

-- the boxes of each shell, laid again at its switches (one shared fn per
-- shell: shell:OnKit keeps it once)
local boxesOf = setmetatable({}, weakKeys)   -- [shell] = { [box] = true } (weak)
local function Boxes_OnKit(shell, on)
	local set = boxesOf[shell]
	if set then
		for box in pairs(set) do
			box:SetKit(on)
		end
	end
end

function W.IconBox(parent, size, texture, skin)
	local box = CreateFrame("Frame", nil, parent)
	box:SetSize(size, size)
	box.size = size
	box.icon = box:CreateTexture(nil, "ARTWORK")
	local k = size / 45
	box.frame = box:CreateTexture(nil, "OVERLAY")
	box.frame:SetAtlas(ICON_FRAME)
	box.frame:SetSize(46 * k, 45 * k)
	box.frame:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
	local mask = box:CreateMaskTexture()
	mask:SetAtlas(ICON_MASK)
	maskOf[box] = mask
	box.SetIcon, box.SetSelected, box.SetPressed = IconBox_SetIcon, IconBox_SetSelected, IconBox_SetPressed
	box.SetHovered, box.SetOn, box.SetGlow, box.SetKit = IconBox_SetHovered, IconBox_SetOn, IconBox_SetGlow, IconBox_SetKit
	box.masked = false
	box:SetKit(skin and skin.kit)
	if texture ~= nil then
		box:SetIcon(texture)
	end
	box.selected = false
	if skin then
		box.melloChecked = function() return box.selected end
		skin:Kit(DressIconBox, box, skin)
		if skin.OnKit then
			local set = boxesOf[skin]
			if not set then
				set = setmetatable({}, weakKeys)
				boxesOf[skin] = set
			end
			set[box] = true
			skin:OnKit(Boxes_OnKit)
		end
	end
	box:SetSelected(false)
	return box
end

--------------------------------------------------------------------------------
-- RoundIcon (0.14.0, the Reminder widget; lifted from the Services bar's
-- round medallions, which can move onto it later): a round button, its icon
-- under a round mask inside a rim, with a round highlight. Two looks,
-- switched live with b:SetKit(Kit):
--   the kit's round rim (buttons/roundslot through Kit:Slot: every window's
--   Round Border, swapped with it, its hover and pressed art its own, Dark
--   Mode's shade), the icon fitted into its opening;
--   plain: the minimap's tracking rim round the icon (31 : 21, the Services
--   bar's medallion).
--   W.RoundIcon(parent, size, texture[, opts]) -> b   a Button, size x size
--       (the rim's outer size: the whole button), left and right clicks
--       registered, in the plain look. opts (read once): name; shade (a
--       shade area of Kit.shadeAreas: the kit rim wears the whole UI's
--       shade, a partner drawn by the button itself, so it fades and moves
--       with it, following the rim's own show and hide: none in the plain
--       look; made with the first kit look, at the shade's pace)
--   b:SetIcon(texture)   b:SetOn(on) (grey and dimmed while off)
--   b:SetKit(Kit)        the kit's look while handed the kit (MelloUI.Kit, as
--                        a shell hands it to its dressing: this file never
--                        reaches for it), the plain look for nil or false; the
--                        kit's rim is made the first time. Set the button's
--                        own scripts BEFORE the first kit look: the kit's rim
--                        hooks them, and SetScript drops hooks
--   b.icon, b.mask, b.plainRim, b.kitRim (nil until the first kit look),
--   b.size, b.kitLaid (true while the kit's rim shows)
-- It sets no script and holds no colour; nothing is made per call after.
--------------------------------------------------------------------------------

do
	local TRACKING_RIM = "Interface\\Minimap\\MiniMap-TrackingBorder"
	local HIGHLIGHT = "Interface\\Buttons\\ButtonHilight-Square"
	local PLAIN_RATIO = 31 / 21   -- the tracking rim: a 31 px ring round a 21 px opening
	local NONE = {}

	local function SetIcon(b, texture)
		b.icon:SetTexture(texture)
	end

	local function SetOn(b, on)
		b.icon:SetDesaturated(not on)
		b.icon:SetAlpha(on and 1 or 0.45)
	end

	-- the plain look: the icon centred at its opening's size, the tracking
	-- rim's art round it (the art sits in its texture's top left: 53 wide
	-- for a 21 wide opening, from 5 left of it and 4 above)
	local function PlainLay(b)
		local d = b.size / PLAIN_RATIO
		local k = d / 21
		local icon, rim = b.icon, b.plainRim
		icon:ClearAllPoints()
		icon:SetSize(d, d)
		icon:SetPoint("CENTER", b, "CENTER", 0, 0)
		rim:ClearAllPoints()
		rim:SetSize(53 * k, 53 * k)
		rim:SetPoint("TOPLEFT", icon, "TOPLEFT", -5 * k, 4 * k)
	end

	-- the kit rim's shade partner (opts.shade): the rim drawn at the
	-- button's size, so the partner's scale is that against its piece's
	-- painted width; an unknown area is reported, and the button goes without
	local function ShadeRim(b, rim, Kit)
		local ok, el = pcall(Kit.ShadeElement, Kit, b, b.shadeArea, { host = b })
		if not ok then
			geterrorhandler()(el)
			return
		end
		local pw = Kit.Size and rim.kitName and Kit:Size(rim.kitName, 1)
		pw = Secret(pw) and nil or tonumber(pw)
		el:Add(rim, { scale = (pw and pw > 0) and b.size / pw or nil })
	end

	local function SetKit(b, Kit)
		local on = (type(Kit) == "table" and Kit.Slot and Kit.SlotPlaceIcon) and true or false
		if on then
			local rim = b.kitRim
			if not rim then
				rim = Kit:Slot(b, { kind = "roundslot" })
				if Kit.RegisterTexture then
					Kit:RegisterTexture(rim)   -- Dark Mode's shade
				end
				b.kitRim = rim
				if b.shadeArea and Kit.ShadeElement then
					ShadeRim(b, rim, Kit)
				end
			end
			rim:Show()
			b.plainRim:Hide()
			rim.icon = b.icon
			Kit:SlotPlaceIcon(rim)
		else
			if b.kitRim then
				b.kitRim:Hide()
			end
			b.plainRim:Show()
			PlainLay(b)
		end
		b.kitLaid = on
	end

	function W.RoundIcon(parent, size, texture, opts)
		opts = type(opts) == "table" and opts or NONE
		local b = CreateFrame("Button", opts.name, parent)
		b:SetSize(size, size)
		b.size = size
		b.shadeArea = type(opts.shade) == "string" and opts.shade or nil
		b:EnableMouse(true)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		local icon = b:CreateTexture(nil, "ARTWORK")
		icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
		b.icon = icon
		local mask = b:CreateMaskTexture()
		mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(icon)
		icon:AddMaskTexture(mask)
		b.mask = mask
		b:SetHighlightTexture(HIGHLIGHT, "ADD")
		local hl = b.GetHighlightTexture and b:GetHighlightTexture()
		if hl then
			hl:ClearAllPoints()
			hl:SetAllPoints(icon)
			hl:AddMaskTexture(mask)
		end
		b.plainRim = b:CreateTexture(nil, "OVERLAY")
		b.plainRim:SetTexture(TRACKING_RIM)
		b.SetIcon, b.SetOn, b.SetKit = SetIcon, SetOn, SetKit
		if texture ~= nil then
			b:SetIcon(texture)
		end
		SetKit(b, false)
		return b
	end
end

--------------------------------------------------------------------------------
-- TrayBox (0.14.0: the Restock panel beside the shop, the Services trays;
-- lifted from the Services bar's menu box, which can move onto it later): the
-- box of a small list that hangs beside a window. Two looks, switched live
-- with box:SetKit(Kit) (handed the kit while its look is on, nil or false
-- for the plain look, as W.RoundIcon):
--   the kit's list box (Professions-background-summarylist: the single rail
--   round the list-box stone, the Services menu's look), the rule's inner
--   panel over the stone so text rows read on it (the eye strain rule;
--   opts.dim = false leaves the plain stone: a box of icons, no text);
--   plain: a fill in the palette's inner panel inside a 1 px trim edge (the
--   look of W.Box), the regions the kit's box fades while it shows.
--   W.TrayBox(parent[, opts]) -> box   a Frame, sized and placed by the
--       caller. opts (read once): name, strata, dim, alpha (the plain
--       fill's, 0.95)
--   box:SetKit(Kit) -> true while the kit's box shows (made the first time)
--   box.fill, box.edges   the plain look's regions
--------------------------------------------------------------------------------

do
	local NONE = {}

	local function SetKit(box, Kit)
		local rep = box.kitBox
		local on = type(Kit) == "table"
		if on and rep == nil and Kit.Replace then
			rep = Kit:Replace(box.fill, { as = "Professions-background-summarylist", rect = box, parent = box,
				level = -1, dim = box.kitDim, alsoFade = box.edges })
			box.kitBox = rep or false
		end
		if on and rep then
			rep:Enable()
			return true
		end
		if rep then
			rep:Disable()
		end
		return false
	end

	function W.TrayBox(parent, opts)
		opts = type(opts) == "table" and opts or NONE
		local box = CreateFrame("Frame", opts.name, parent)
		if type(opts.strata) == "string" then
			box:SetFrameStrata(opts.strata)
		end
		local alpha = opts.alpha
		if type(alpha) ~= "number" or Secret(alpha) then
			alpha = 0.95
		end
		box.fill = W.Solid(box, "BACKGROUND", "innerPanel", alpha)
		box.fill:SetAllPoints(box)
		box.edges = Edges(box, "trim", "BORDER")
		box.kitDim = opts.dim   -- (nil: the rule's panel; false: none)
		box.SetKit = SetKit
		return box
	end
end

--------------------------------------------------------------------------------
-- RowPlate (audit rank 10): the one hover look of a row, faded through Anim
-- (0.10 s in, 0.12 s out; at once under Reduce Motion), with one pair of
-- shared handlers for every row of every window -- no OnUpdate of the row's
-- own, nothing made per hover.
--   W.RowPlate(row, opts) -> the region that shows, and true when it is the
--   kit's plate
--   opts.look  "palette": the palette's hover fill at `strength` (0.5), with
--              a 2 px `selectedTrim` edge when `edge`; it rests at alpha 0
--              "plate": the kit's row plate (FriendsRowHighlight, CR4) through
--              opts.skin while its kit is on (else the palette look); it
--              rests hidden and fades in and out (it showed and hid at once)
--   opts.selected  fn(row) -> true while the row is the selected one: no
--              wash on it (gold on the hover colour is 2.96:1, under 4.5)
-- W.RowPlateOff(row): back to rest at once (a row just selected).
-- W.RowPlateChild(row, child): a frame on the row that takes the mouse (its
--   switch, button, dropdown, a slider's bar and steppers, a gate's cover).
--   The game gives the row its OnLeave as the pointer moves onto one; the
--   palette wash stays lit while the pointer is still over the row (as the
--   configurator's always did: it polled the row) and fades once the pointer
--   has left the row, from the row or from the child. The typed rows and
--   W.Gate hand theirs over; a window laying its own rows calls it. (The
--   kit's plate goes with the row's own enter and leave, as it did.)
--------------------------------------------------------------------------------

local plateOf = setmetatable({}, weakKeys)      -- [row] = the region that shows
local faderOf = setmetatable({}, weakKeys)      -- [row] = what the fade moves (the region, or its pieces' stand-in)
local edgeOf = setmetatable({}, weakKeys)       -- [row] = its gold edge (palette, edge = true)
local strengthOf = setmetatable({}, weakKeys)   -- [row] = the wash's alpha
local hiddenOf = setmetatable({}, weakKeys)     -- [row] = true: the plate rests hidden (the kit's)
local selectedOf = setmetatable({}, weakKeys)   -- [row] = fn(row): true while it is the selected one
local rowOfChild = setmetatable({}, weakKeys)   -- [a row's control] = the row whose wash it keeps lit
-- the row whose wash stays lit because the pointer, off the row's own
-- frame, is still over it (on one of its controls, or on a frame that is
-- not the row's -- a dropdown's menu over its edge -- from which no leave
-- comes back to the row): let go when the pointer enters another row
local held = nil

-- The kit's plate whose pieces are regions of the ROW (an `owner` strip, as
-- FriendsRowHighlight's rule makes it: Kit:Strip): the strip frame only lays
-- them out, so its alpha never reaches them (review, 2026-09-25: the plate
-- showed at full at once and vanished after the fade out). The fade moves the
-- pieces themselves, through this stand-in that Anim moves as it moves a
-- frame (alpha, shown, hidden): one per row, made with it.
local PieceFader = {}
PieceFader.__index = PieceFader
function PieceFader:GetAlpha()
	return self.alpha
end
function PieceFader:SetAlpha(a)
	self.alpha = a
	local strip = self.strip
	strip.capL:SetAlpha(a)
	strip.mid:SetAlpha(a)
	strip.capR:SetAlpha(a)
end
function PieceFader:IsShown()
	return self.strip:IsShown()
end
function PieceFader:Show()
	self.strip:Show()
end
function PieceFader:Hide()
	self.strip:Hide()
end

local function FaderOf(region)
	local mid = region.mid
	if region.capL and region.capR and mid and mid.GetParent and mid:GetParent() ~= region then
		return setmetatable({ strip = region, alpha = 1 }, PieceFader)
	end
	return region
end

-- the pointer over the row's rect (a secret answer counts as not over)
local function OverRow(row)
	local over = row:IsMouseOver()
	if Secret(over) then
		return false
	end
	return over and true or false
end

-- a wash or edge fades out; one that has not started to show (the mouse
-- passed straight over: nothing drawn yet) is at rest at once, no tween
-- running on for nothing
local function Out(region)
	local Anim = MelloUI.Anim
	if region:GetAlpha() <= 0 then
		Anim:Stop(region, "alpha")
	else
		Anim:To(region, "alpha", 0, FADE_OUT, "inQuad")
	end
end

-- a wash or edge fades in, unless it is there or on its way (the pointer back
-- on the row from one of its controls: no tween running on for nothing)
local function In(region, to)
	local Anim = MelloUI.Anim
	local going = Anim:Target(region, "alpha")
	if going == nil then
		local a = region:GetAlpha()
		if not Secret(a) and a > to - 0.01 and a < to + 0.01 then
			return
		end
	elseif going == to then
		return
	end
	Anim:To(region, "alpha", to, FADE_IN, "outQuad")
end

-- the row's hover back to rest, faded
local function PlateOut(row)
	if held == row then
		held = nil
	end
	local p = faderOf[row]
	if not p then
		return
	end
	if hiddenOf[row] then
		if not p:IsShown() then
			return
		end
		if p:GetAlpha() <= 0 then
			MelloUI.Anim:Stop(p, "alpha")
			p:Hide()
			p:SetAlpha(1)
		else
			MelloUI.Anim:FadeOut(p, FADE_OUT, "inQuad")
		end
	else
		Out(p)
		local e = edgeOf[row]
		if e then
			Out(e)
		end
	end
end

local PlateEnter = Shared("OnEnter on MelloUI's rows (hover)", function(row)
	if held then
		local was = held
		held = nil
		if was ~= row then
			PlateOut(was)
		end
	end
	local p = faderOf[row]
	local sel = selectedOf[row]
	if not p or (sel and sel(row)) then
		return
	end
	if hiddenOf[row] then
		MelloUI.Anim:FadeIn(p, FADE_IN, "outQuad")
	else
		In(p, strengthOf[row])
		local e = edgeOf[row]
		if e then
			In(e, 1)
		end
	end
end, "script")

local PlateLeave = Shared("OnLeave on MelloUI's rows (hover)", function(row)
	if not hiddenOf[row] and OverRow(row) then
		held = row      -- onto one of its controls: lit until the pointer leaves the row
		return
	end
	PlateOut(row)
end, "script")

local PlateChildLeave = Shared("OnLeave on the controls of MelloUI's rows (hover)", function(child)
	local row = rowOfChild[child]
	if not row then
		return
	end
	if OverRow(row) then
		held = row      -- back on the row, or on another of its controls
		return
	end
	PlateOut(row)
end, "script")

-- the palette's wash on a row (under its texts), resting at alpha 0, and its
-- 2 px gold edge unless `edge` is false: the plain hover look (and a
-- flash's, W.Flash)
local function Wash(row, strength, edge)
	local region = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	region:SetTexture(WHITE)
	region:SetAllPoints()
	W.Paint(region, "hover", "vertex", 1)
	region:SetAlpha(0)
	strengthOf[row] = strength or 0.5
	if edge ~= false then
		local e = row:CreateTexture(nil, "BACKGROUND", nil, 2)
		e:SetTexture(WHITE)
		e:SetWidth(2)
		e:SetPoint("TOPLEFT")
		e:SetPoint("BOTTOMLEFT")
		W.Paint(e, "selectedTrim", "vertex", 1)
		e:SetAlpha(0)
		edgeOf[row] = e
	end
	return region
end

function W.RowPlate(row, opts)
	opts = opts or {}
	local skin = opts.skin
	local region, kit
	if opts.look == "plate" and skin and skin.kit then
		-- the region to replace comes from the shell (its one invisible
		-- anchor): no anchor and no colour literal here
		local rep = skin:Replace(skin:Anchor(row, "BACKGROUND"), { as = "FriendsRowHighlight", rect = row })
		region = rep and rep.object
		if region then
			region:Hide()
			hiddenOf[row], strengthOf[row], kit = true, 1, true
		end
	end
	if not region then
		region = Wash(row, opts.strength, opts.edge)
	end
	plateOf[row] = region
	faderOf[row] = kit and FaderOf(region) or region
	selectedOf[row] = opts.selected
	row:EnableMouse(true)
	Perf.HookScript(row, "OnEnter", PlateEnter)
	Perf.HookScript(row, "OnLeave", PlateLeave)
	return region, kit
end

function W.RowPlateChild(row, child)
	if child and child.HookScript and faderOf[row] and not hiddenOf[row] and rowOfChild[child] == nil then
		rowOfChild[child] = row
		Perf.HookScript(child, "OnLeave", PlateChildLeave)
	end
end

function W.RowPlateOff(row)
	local p = faderOf[row]
	if not p then
		return
	end
	if held == row then
		held = nil
	end
	local Anim = MelloUI.Anim
	Anim:Stop(p, "alpha")
	if hiddenOf[row] then
		p:Hide()
		p:SetAlpha(1)
	else
		p:SetAlpha(0)
		local e = edgeOf[row]
		if e then
			Anim:Stop(e, "alpha")
			e:SetAlpha(0)
		end
	end
end

--------------------------------------------------------------------------------
-- Flash: a row's hover look lit for a moment, so the eye finds the row a
-- jump brought into view (the configurator's search, 0.14.0). The row's own
-- RowPlate when it has one (the kit's plate or the palette's wash); a frame
-- without one (a Your setup row, a card, the top bar's Layout group) gets
-- the palette's wash and gold edge at its first flash, lit only by flashes
-- (no hover of its own). Faded in and out through Anim, held by a one-shot
-- timer: nothing runs between flashes. Reduce Motion: on and off at once,
-- still held. A new flash puts the one before out at once; a row the
-- pointer is on keeps its hover when the flash ends.
--   W.Flash(row[, hold])   `hold` in seconds (W.FLASH_HOLD, 1.2)
--   W.Flashing()           the row a flash holds now, or nil
--------------------------------------------------------------------------------

W.FLASH_HOLD = 1.2
local flashOnly = setmetatable({}, weakKeys)   -- [frame] = true: its wash is a flash's only
local flash = { row = nil, holds = 0 }

local function FlashOver()
	flash.holds = flash.holds - 1
	if flash.holds > 0 then
		return
	end
	flash.holds = 0
	local row = flash.row
	flash.row = nil
	if row and (flashOnly[row] or not OverRow(row)) then
		PlateOut(row)
	end
end

function W.Flash(row, hold)
	if not row then
		return
	end
	local was = flash.row
	if was and was ~= row then
		W.RowPlateOff(was)
	end
	if not faderOf[row] then
		local region = Wash(row, 0.5, true)
		plateOf[row], faderOf[row], flashOnly[row] = region, region, true
	end
	flash.row = row
	local p = faderOf[row]
	if hiddenOf[row] then
		MelloUI.Anim:FadeIn(p, FADE_IN, "outQuad")
	else
		In(p, strengthOf[row])
		local e = edgeOf[row]
		if e then
			In(e, 1)
		end
	end
	flash.holds = flash.holds + 1
	C_Timer.After(tonumber(hold) or W.FLASH_HOLD, FlashOver)
end

function W.Flashing()
	return flash.row
end

--------------------------------------------------------------------------------
-- Tag: ONE small plate with a short gold word for every place that marks a
-- thing -- the installer card's "Recommended" (W.Card's spec.tag, the
-- approved look) and an option's "New" (the user's rule, 2026-09-26: every
-- new dropdown, slider, check box ... carries a New tag for its update, so
-- players find it and try it). The selected tab's colour behind the word,
-- laid on the word itself (no width to measure), both painted by key (a new
-- palette paints them again). Two regions of `parent`, made when asked.
--   local tag = W.Tag(parent, text, snug) -> the word (a FontString),
--       tag.plate (the caller places the word, the plate follows it: W.TAG_PAD
--       round it; `snug`: W.TAG_SNUG, where room is scarce -- the side list)
--   W.TagShown(tag, shown)    W.TagAlpha(tag, alpha)    (the word and its plate)
-- New tags: an option names the update it came with (`new`); its tag is made
-- and shown only while that update runs (Core's MelloUI:IsNew), so the next
-- update's configurator makes none of the old ones.
--   W.NEW    the word ("New")
--   W.NewTag(parent, after, new, room) -> tag | nil   right after the region
--       `after` (a label); `room`: the width `after` and the tag may take
--       together (a label of a fixed width is narrowed to its text, and cut
--       when the tag would not fit)
--   W.Badge(frame, new, inset) -> tag | nil   on a frame's top edge at its
--       right (a tab): half over it, well inside its sides. `new` true: shown
--       (the caller has asked MelloUI:IsNew of what the frame leads to).
--       `inset`: its plate's right side that far in from the frame's (a
--       control at the frame's right kept clear: the search box's clear
--       button); BADGE_IN when nil
--   W.ButtonTag(button, new) -> tag | nil   INSIDE a text button, at its
--       right and centred on its height (a badge would lie on its label): the
--       button made wider by the tag's room, its label centred in the width
--       it had
--------------------------------------------------------------------------------

local TAG_PAD_X, TAG_PAD_Y = 6, 3   -- the plate round the word
local TAG_SNUG_X = 4                -- a snug plate's sides (the side list)
local TAG_GAP = 6                   -- a label to its tag's plate
local BADGE_IN = 12                 -- a badge's plate inside its frame's right side
local BUTTON_TAG_IN = 8             -- a button's tag plate inside its right side (clear of its end cap)
local LABEL_SLACK = 2               -- a label narrowed to its text keeps this much more (never cut at an odd scale)
W.TAG_PAD = TAG_PAD_X
W.TAG_SNUG = TAG_SNUG_X
W.NEW = "New"

function W.Tag(parent, text, snug)
	local tag = W.Text(parent, "GameFontHighlightSmall", text, "selectedTrim")
	tag:SetWordWrap(false)
	local pad = snug and TAG_SNUG_X or TAG_PAD_X
	local plate = parent:CreateTexture(nil, "ARTWORK")
	plate:SetPoint("TOPLEFT", tag, "TOPLEFT", -pad, TAG_PAD_Y)
	plate:SetPoint("BOTTOMRIGHT", tag, "BOTTOMRIGHT", pad, -TAG_PAD_Y)
	W.Paint(plate, "selectedTab", "fill", 1)
	tag.plate, tag.padX = plate, pad
	return tag
end

function W.TagShown(tag, shown)
	if tag then
		shown = shown and true or false
		tag:SetShown(shown)
		tag.plate:SetShown(shown)
	end
end

function W.TagAlpha(tag, alpha)
	if tag then
		tag:SetAlpha(alpha)
		tag.plate:SetAlpha(alpha)
	end
end

-- a text's width as written (not cut by a width set on it)
local function TextWidth(fs)
	local get = fs.GetUnboundedStringWidth or fs.GetStringWidth
	return Num(get(fs))
end

-- the room a tag takes after a label: its plate and the gap before it
local function TagSpan(tag)
	local w = TextWidth(tag)
	return w and (w + 2 * TAG_PAD_X + TAG_GAP) or nil
end

function W.NewTag(parent, after, new, room)
	if not (new and after and MelloUI:IsNew(new)) then
		return nil
	end
	local tag = W.Tag(parent, W.NEW)
	tag:SetPoint("LEFT", after, "RIGHT", TAG_GAP + TAG_PAD_X, 0)
	if room then
		local w, span = TextWidth(after), TagSpan(tag)
		if w and span then
			-- (its text's width and a little more: a text set exactly as wide
			-- as it measures can be cut at an odd UI scale)
			after:SetWidth(math.max(1, math.min(w + LABEL_SLACK, room - span)))
		end
	end
	return tag
end

-- (`new` true: the caller asked MelloUI:IsNew of what the frame leads to)
local function Shows(new)
	return new == true or (new ~= nil and new ~= false and MelloUI:IsNew(new))
end

function W.Badge(frame, new, inset)
	if not Shows(new) then
		return nil
	end
	local tag = W.Tag(frame, W.NEW)
	-- (the word's middle on the frame's top edge)
	tag:SetPoint("RIGHT", frame, "TOPRIGHT", -((tonumber(inset) or BADGE_IN) + TAG_PAD_X), 0)
	return tag
end

function W.ButtonTag(button, new)
	if not Shows(new) then
		return nil
	end
	local tag = W.Tag(button, W.NEW)
	tag:SetPoint("RIGHT", button, "RIGHT", -(BUTTON_TAG_IN + TAG_PAD_X), 0)
	local width, word = Num(button:GetWidth()), TextWidth(tag)
	if width and word then
		-- the tag's room added at the right (its plate, and the cap's inset
		-- past it); the label stays centred in the width it had, so it never
		-- reaches under the tag
		local extra = word + 2 * TAG_PAD_X + BUTTON_TAG_IN
		button:SetWidth(width + extra)
		local fs = button.GetFontString and button:GetFontString()
		if fs then
			local _, _, _, x, y = fs:GetPoint(1)
			fs:ClearAllPoints()
			fs:SetPoint("CENTER", button, "CENTER", (Num(x) or 0) - extra / 2, Num(y) or 0)
		end
	end
	return tag
end

--------------------------------------------------------------------------------
-- Rows: a ledger row with its label on the left, an optional hint after it,
-- the description in its tooltip, a control on the right.
--   W.Row(parent, y, height, label, hint, desc, opts) -> row
--     parent  the section the row lies in, `y` below its top
--     opts.skin
--     opts.inset   the row's margin at both sides (0)
--     opts.indent  the label's extra step right (0: a sub-option's level)
--     opts.zebra   a stripe under it (`mainWindow` at 0.85)
--     opts.line    a 1 px `border` line along its bottom at 0.6 (the plain
--                  look's ledger)
--     opts.look    the hover (W.RowPlate): "plate" | "palette" | false
--     opts.gate    fn() -> live, why, line: the row sleeps while not live
--                  (W.Gate)
--     opts.note    (true) while it sleeps, the hint slot reads "Switch on
--                  "why" first." -- or `line` as it is, when the gate gives
--                  one ("Not for Pet") (the row keeps its height)
--     opts.onCover fn(row): a click on the sleeping row (the configurator's
--                  jump to the switch that wakes it)
--     opts.clip    (true, typed rows) the label and hint end 10 px left of
--                  the control, cut there, the full text in the tooltip
--     opts.new     the update the option came with: its New tag right after
--                  the label while that update runs (W.NewTag; the hint after
--                  the tag), dimmed with the row while it sleeps; a label with
--                  a tag and no hint keeps its text's width, cut only where
--                  the two would reach the control (row.newTag)
--   row:Refresh()  the row's control (get again) and its gate
-- The typed rows (a row and its control, which takes get / set; the
-- controls flat in both looks, 0.15.0: nothing of theirs for the kit's
-- sweep):
--   W.ToggleRow(parent, y, label, hint, desc, get, set, opts) -> row, switch
--   W.SliderRow(parent, y, label, hint, desc, get, set, opts) -> row, slider
--     (opts.min, max, step, percent, format, width: the whole slider, its
--     box included, at the row's right; 256 when none is given, the span
--     such a row always had)
--   W.DropdownRow(parent, y, label, hint, desc, get, set, values, opts)
--     -> row, dropdown (opts.width 200; the label is its default text)
--   W.ButtonRow(parent, y, label, hint, desc, text, onClick, opts)
--     -> row, button (opts.width 70; onClick a shared handler)
--   W.ControlOf(row)   the typed row's control
--------------------------------------------------------------------------------

local controlOf = setmetatable({}, weakKeys)   -- [row] = its control
local gateOf = setmetatable({}, weakKeys)      -- [row] = its cover (W.Gate)
local clipAt = setmetatable({}, weakKeys)      -- [row] = the region its texts end at (W.ClipRow)

function W.ControlOf(row)
	return controlOf[row]
end

local function RowRefresh(row)
	local control = controlOf[row]
	if control and control.Refresh then
		control:Refresh()
	end
	local cover = gateOf[row]
	if cover then
		cover:Refresh()
	end
end

-- the line a sleeping row says (one per switch, made once, not a new
-- string per hover or refresh)
local function GateLine(cover, why)
	local lines = cover.gateLines
	if not lines then
		lines = {}
		cover.gateLines = lines
	end
	local line = lines[why]
	if not line then
		line = "Switch on \"" .. why .. "\" first."
		lines[why] = line
	end
	return line
end

-- the line a sleeping row says: the gate's own (as it is), or the switch
-- that wakes it
local function SleepLine(cover, why, line)
	if line then
		return line
	end
	return why and GateLine(cover, why) or nil
end

-- the cover's tooltip: the row's label, and what wakes it
local CoverEnter = Shared("OnEnter on MelloUI's sleeping rows", function(self)
	local _, why, line = self.gate()
	local row = self.gateRow
	W.ShowTooltip(self, row.label and row.label:GetText() or "", SleepLine(self, why, line))
end, "script")

-- a click on a sleeping row: the caller's (opts.onCover), a left click only
local CoverClick = Shared("OnMouseUp on MelloUI's sleeping rows (to the switch that wakes it)", function(self, button)
	local fn = self.onCover
	if fn and button ~= "RightButton" then
		fn(self.gateRow)
	end
end, "script")

local function GateRefresh(cover)
	local live, why, line = cover.gate()
	local row = cover.gateRow
	row:SetAlpha(live and 1 or GATE_ALPHA)
	cover:SetShown(not live)
	local hint = cover.note and row.hint
	if hint then
		local text = cover.hintText
		if not live then
			text = SleepLine(cover, why, line) or text
		end
		hint:SetText(text or "")
		hint:SetShown(text ~= nil and text ~= "")
	end
end

-- A row that only means something while a switch is on (user, 2026-09-24:
-- "people will get overwhelmed by all the options"): `gate()` returns whether
-- it is live and, when not, the switch to turn on -- or a line of its own to
-- say instead (0.15.0: "Not for Pet", a row that has no setting on this
-- pick). Off, the row is dimmed and a cover over it takes the clicks and
-- says what wakes it.
--   opts.note (true): the hint slot reads that line while it sleeps
--   opts.onCover (0.15.0): fn(row), a click on the cover (the configurator
--   jumps to the switch, on another page or pick)
function W.Gate(row, gate, opts)
	local cover = CreateFrame("Frame", nil, row)
	cover:SetAllPoints(row)
	cover:SetFrameLevel(row:GetFrameLevel() + 30)
	cover:EnableMouse(true)
	cover.gate, cover.gateRow = gate, row
	Perf.SetScript(cover, "OnEnter", CoverEnter)
	Perf.SetScript(cover, "OnLeave", TipLeave)
	if opts and opts.onCover then
		cover.onCover = opts.onCover
		Perf.SetScript(cover, "OnMouseUp", CoverClick)
	end
	W.RowPlateChild(row, cover)
	cover:Hide()
	cover.Refresh = GateRefresh
	if not (opts and opts.note == false) then
		cover.note = true
		if not row.hint then
			row.hint = W.Text(row, "GameFontHighlightSmall", nil, "text")
			row.hint:SetPoint("LEFT", row.newTag or row.label, "RIGHT", row.newTag and (10 + TAG_PAD_X) or 10, 0)
			row.hint:SetWordWrap(false)
			local at = clipped[row] and clipAt[row]
			if at then
				row.hint:SetPoint("RIGHT", at, "LEFT", -10, 0)
			end
		end
		cover.hintText = row.hint:GetText()
	end
	gateOf[row] = cover
	return cover
end

-- A label with a New tag and no hint: its text's width, the tag right after
-- it; narrowed (cut, the whole text in the tooltip) only where the two would
-- reach 10 px short of the control. `span`: the control's left edge from the
-- row's right one (the typed rows know it); the row as wide as its parent
-- less the row's margins (a section's set width). Unknown: left as it is.
local function FitLabel(row, span)
	local label, parent = row.label, row:GetParent()
	local width = span and parent and Num(parent:GetWidth())
	local text, tag = TextWidth(label), TagSpan(row.newTag)
	if not (width and width > 0 and text and tag) then
		return
	end
	local room = width - 2 * (row.rowInset or 0) - (row.labelX or 14) - span - 10 - tag
	if text > room then
		label:SetWidth(math.max(20, room))
	end
end

-- The label and hint kept left of the control: the last of them ends 10 px
-- left of it (word wrap off: the game cuts it there), the full text in the
-- row's tooltip when cut; a label with a New tag and no hint: FitLabel.
-- `control` may be any region the texts end at (a link row's value).
function W.ClipRow(row, control, span)
	local last = row.hint or row.label
	if not (last and control) then
		return
	end
	if last == row.label and row.newTag then
		FitLabel(row, span)
	else
		last:SetPoint("RIGHT", control, "LEFT", -10, 0)
	end
	clipped[row], clipAt[row] = true, control
	if not row.tipTitle then
		row.tipTitle = row.label and row.label:GetText() or ""
		Perf.HookScript(row, "OnEnter", RowTipEnter)
		Perf.HookScript(row, "OnLeave", TipLeave)
	end
end

local PLATE_OPTS = {}   -- a row's RowPlate options (one table, filled per row)

function W.Row(parent, y, height, label, hint, desc, opts)
	opts = opts or NO_OPTS
	local inset = opts.inset or 0
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(height)
	row:SetPoint("TOPLEFT", inset, -y)
	row:SetPoint("RIGHT", parent, "RIGHT", -inset, 0)
	row:EnableMouse(true)
	if opts.zebra then
		-- CR4 (user, 2026-09-21): a faint band on every other row
		row.band = row:CreateTexture(nil, "BACKGROUND")
		row.band:SetAllPoints(row)
		W.Paint(row.band, "mainWindow", "fill", 0.85)
	end
	if opts.line then
		local line = W.Solid(row, "BORDER", "border", 0.6)
		line:SetHeight(1)
		line:SetPoint("BOTTOMLEFT")
		line:SetPoint("BOTTOMRIGHT")
	end
	local look = opts.look
	if look then
		local plate = PLATE_OPTS
		plate.look, plate.skin, plate.strength = look, opts.skin, opts.strength
		local region, kit = W.RowPlate(row, plate)
		plate.look, plate.skin, plate.strength = nil, nil, nil
		-- (the fields such rows always had: a heading's `hover` is taken away)
		if kit then
			row.hover, row.hoverPlate = region, region
		else
			row.hoverGlow = region
		end
	end
	row.label = W.Text(row, "GameFontHighlight", label, opts.labelKey or "text")
	row.labelX, row.rowInset = 14 + (opts.indent or 0), inset
	row.label:SetPoint("LEFT", row.labelX, 0)
	row.label:SetWordWrap(false)
	-- (the option's New tag: made only while its update runs)
	row.newTag = opts.new and W.NewTag(row, row.label, opts.new) or nil
	if hint and hint ~= "" then
		row.hint = W.Text(row, "GameFontHighlightSmall", hint, opts.hintKey or "text")
		row.hint:SetPoint("LEFT", row.newTag or row.label, "RIGHT", row.newTag and (10 + TAG_PAD_X) or 10, 0)
		row.hint:SetWordWrap(false)
	end
	if desc and desc ~= "" then
		row.tipTitle, row.tipBody = label, desc
		Perf.HookScript(row, "OnEnter", RowTipEnter)
		Perf.HookScript(row, "OnLeave", TipLeave)
	end
	row.Refresh = RowRefresh
	if opts.gate then
		W.Gate(row, opts.gate, opts)
	end
	return row
end

-- a typed row's control in place: known to the row, the texts cut at it
-- (0.15.0: every typed row's control is flat -- `melloRep` false -- so no
-- sweep of the kit's is asked per row). `span`: the control's left edge from
-- the row's right one (where a New tag's label may end: ClipRow)
local function Finish(row, control, opts, span)
	controlOf[row] = control
	-- the control's frames that take the mouse keep the row's wash lit (a
	-- slider's are its track and its value box)
	W.RowPlateChild(row, control)
	W.RowPlateChild(row, rawget(control, "Slider"))
	W.RowPlateChild(row, rawget(control, "box"))
	if opts.clip ~= false then
		W.ClipRow(row, control, span)
	end
	return row, control
end

function W.ToggleRow(parent, y, label, hint, desc, get, set, opts)
	opts = opts or NO_OPTS
	local row = W.Row(parent, y, W.ROW_HEIGHT, label, hint, desc, opts)
	local switch = W.Switch(row, get, set, opts)
	switch:SetPoint("RIGHT", -12, 0)
	ControlTip(switch, row, label, desc)
	return Finish(row, switch, opts, 12 + 26)
end

do
	-- `opts.width` is the whole control's, the track and its box (the track
	-- `width - W.SLIDER_BOX`), so a caller that places the slider itself (the
	-- Restock List's lines) keeps the footprint it asked for. None given: the
	-- span such a row always had -- 200 for the old slider and the 56 px its
	-- value took right of it -- the track where the old slider was, the box
	-- in that room, its right edge with the other rows' controls.
	local SLIDER_WIDTH, SLIDER_END = 256, 14

	function W.SliderRow(parent, y, label, hint, desc, get, set, opts)
		opts = opts or NO_OPTS
		local row = W.Row(parent, y, W.SLIDER_ROW_HEIGHT, label, hint, desc, opts)
		local width = opts.width or SLIDER_WIDTH
		local slider = W.Slider(row, width, get, set, opts)
		slider:SetPoint("RIGHT", -SLIDER_END, 0)
		return Finish(row, slider, opts, SLIDER_END + width)
	end
end

-- (the dropdown's own options: its default text is the row's label)
local DROPDOWN_OPTS = {}

function W.DropdownRow(parent, y, label, hint, desc, get, set, values, opts)
	opts = opts or NO_OPTS
	local row = W.Row(parent, y, W.ROW_HEIGHT, label, hint, desc, opts)
	DROPDOWN_OPTS.default, DROPDOWN_OPTS.tooltip = label, nil
	local width = opts.width or 200
	local dd = W.Dropdown(row, width, get, set, values, DROPDOWN_OPTS)
	dd:SetPoint("RIGHT", -14, 0)
	return Finish(row, dd, opts, 14 + width)
end

-- (the button flat, as every typed row's control)
function W.ButtonRow(parent, y, label, hint, desc, text, onClick, opts)
	opts = opts or NO_OPTS
	local row = W.Row(parent, y, W.ROW_HEIGHT, label, hint, desc, opts)
	local width = opts.width or 70
	local button = W.Button(row, text or "Run", width, nil)
	button:SetPoint("RIGHT", -12, 0)
	if onClick then
		Perf.SetScript(button, "OnClick", onClick)
	end
	ControlTip(button, row, label, desc)
	row.button = button
	return Finish(row, button, opts, 12 + width)
end

--------------------------------------------------------------------------------
-- PictureRow (0.15.0: Dynamic UI Modification's pictures, folded into the
-- configurator's pages): a look chosen by its picture -- a border, a
-- backdrop, a background, the minimap's shape. The row's box shows the
-- chosen one's picture (28 px) and its name; a click opens the window's
-- flyout under the box, a tile per choice with its picture (Kit:ChoicePicture,
-- looked up when drawn, as W.Paint looks up the kit), the chosen one outlined
-- in gold; a tile sets it at once (the real bars and windows change as you
-- pick) and closes the flyout.
--   W.PictureRow(parent, y, label, hint, desc, get, set, choices, kind, opts)
--     -> row, box
--     choices  { { value, label, piece | bar | prefix ... } } (the choice
--              lists the kit and the panels keep: Kit.borderKinds' values, a
--              PickerGroups section's choices)
--     kind     "rim" | "bar" | "frame" | "tile" (Kit:ChoicePicture)
--     opts     host (the window whose flyout it opens: the configurator's
--              frame), skin (its shell), width (200), and W.Row's
--   box:SetChoices(choices, kind)   another list (a row whose setting is
--                                   another key per pick)
--   box:Refresh()                   the chosen one drawn again (row:Refresh)
-- The flyout (W.PictureMenu): ONE per host window, made on its first open,
-- never at login; a child of the host (not of a scrolling page, which would
-- clip it), over the page, under the box (over it when there is no room
-- below). Its tiles come from a pool: an open makes no frame once the pool
-- holds enough. Closed by a tile, Escape (the flyout in UISpecialFrames, the
-- host's own Escape held meanwhile: shell:HoldEscape), a click outside (a
-- clear catcher over the host, shown only while the flyout is: no mouse
-- listener of its own), the box's page scrolling, the box hidden (a tab or
-- page switched away), the host hidden, W.ClosePictureMenu(host) (a pick
-- changed), and combat. It never opens in combat (the providers' own
-- changes were never meant for it: Dynamic UI refused a fight too): a click
-- then says "Not in combat." in the box's tooltip, and nothing else; a fight
-- that starts while it is open closes it (PLAYER_REGEN_DISABLED, listened to
-- only while it is open). With the host's shell it wears the UI shade of the
-- windows (Kit:ShadeElement, area "windows"), as the window it opens from.
-- The shell is the host's own (Kit:ShellOf), whatever skin a row passes (a
-- row in the plain look passes none): `skin` counts only for a host that
-- has no shell.
--   W.PictureMenu(host, skin) -> the host's flyout (made the first time)
--   W.ClosePictureMenu(host)   closes it if it is open (nothing is made)
--   W.CloseFlyouts() -> true when one was open: every open flyout closed (a
--     window that keeps its own Escape, Edit Layout's keys, closes an open
--     list with it first: one step a press, the game's Escape never reaching
--     the flyout there)
-- A dropdown's list opens in the same flyout (0.15.0, W.Dropdown: one
-- flyout of MelloUI's own for a window's choices, never the game's menu):
-- its host the window the box lies in (the nearest with a shell, else the
-- top one: HostOf), made on the box's first click; rows in place of the
-- tiles, left under the box (over it when the screen has no room below; by
-- the box's right when it would pass the screen's right edge), the same
-- closing but for combat -- a list opens in a fight and stays open in one,
-- as the game's menu did. The flyout is clamped to the screen, as the
-- game's menu was.
--------------------------------------------------------------------------------

do
	local PICTURE_W, PICTURE_H = 200, 28   -- a picture row's box, its picture the box's height
	local TILE, TILE_STEP, TILE_COLS = 52, 78, 6   -- a flyout's pictures, tile to tile, tiles to a line
	local TILE_BOX = TILE + 8                      -- a tile: its picture with room for its outline
	local TILE_NAME = 16                           -- the choice's name under a tile
	local TILE_LINE = TILE_BOX + TILE_NAME + 6     -- a line of tiles
	local MENU_PAD = 12                            -- the flyout's margin round its tiles
	local MENU_GAP = 4                             -- the box to the flyout
	local MENU_LIFT = 50                           -- the catcher over the box's level (over a sleeping row's cover: +30)
	local NOT_IN_COMBAT = "Not in combat."
	local SQUARE_SHADE = { shape = "shade/square" }   -- (the flyout's shade: a plain frame's)
	-- a dropdown's list (the flyout's list mode)
	local LIST_ROW_H = 20        -- a row: the game's menu's line
	local LIST_PAD = 4           -- the list's margin round its rows
	local LIST_MARK = 6          -- the chosen entry's mark, a square at its row's left
	local LIST_TEXT_X = 16       -- a row's text from its left, the mark before it
	local LIST_BAR = 6           -- a long list's scroll bar
	local LIST_GAP = 2           -- the box to the list
	local LIST_MAX_W = 420       -- the widest a list grows for its entries
	local MENU_ROWS = 18         -- a long list shows this many entries, and scrolls
	local MENU_MIN_ROWS = 6      -- however small the screen
	local MENU_SCREEN = 0.5      -- and it is never taller than this share of the screen
	local WHEEL_ROWS = 2         -- the rows a notch of the wheel moves
	local unnamed = 0            -- the flyouts of hosts without a name (each its own global name)

	local menuOf = setmetatable({}, weakKeys)      -- [host] = its flyout
	local openMenus = setmetatable({}, weakKeys)   -- [flyout] = true while it is open
	local scrollsHooked = setmetatable({}, weakKeys)   -- [a ScrollFrame] = true: its scrolls close a flyout opened in it
	local Menu = {}                                -- the flyout's methods

	-- the choice of a list that has `value` (nil: none)
	local function ChoiceOf(choices, value)
		local i = ChoiceIndex(choices, value)
		return i and choices[i] or nil
	end

	-- a tile's (or a box's) picture: the kit's drawing, looked up when drawn;
	-- nil: nothing shown
	local function DrawChoice(tile, kind, choice)
		local Kit = KitNow()
		if Kit and Kit.ChoicePicture then
			Kit:ChoicePicture(tile, kind, choice)
		end
	end

	-- a tile's two outlines: the chosen one's (2 px, a faint gold wash) and the
	-- hover's (1 px)
	local function Outline(tile, px, wash)
		local out = {}
		for i = 1, 4 do
			out[i] = tile:CreateTexture(nil, "OVERLAY", nil, 7)
			W.Paint(out[i], "selectedTrim", "fill", 0.95)
		end
		out[1]:SetPoint("TOPLEFT")
		out[1]:SetPoint("TOPRIGHT")
		out[1]:SetHeight(px)
		out[2]:SetPoint("BOTTOMLEFT")
		out[2]:SetPoint("BOTTOMRIGHT")
		out[2]:SetHeight(px)
		out[3]:SetPoint("TOPLEFT")
		out[3]:SetPoint("BOTTOMLEFT")
		out[3]:SetWidth(px)
		out[4]:SetPoint("TOPRIGHT")
		out[4]:SetPoint("BOTTOMRIGHT")
		out[4]:SetWidth(px)
		if wash then
			out[5] = tile:CreateTexture(nil, "OVERLAY", nil, 6)
			out[5]:SetAllPoints(tile)
			W.Paint(out[5], "selectedTrim", "fill", wash)
		end
		return out
	end

	local function OutlineShown(out, shown)
		for i = 1, #out do
			out[i]:SetShown(shown)
		end
	end

	local TileEnter = Shared("OnEnter on a picture flyout's tile", function(tile)
		OutlineShown(tile.hover, true)
		local choice = tile.choice
		if choice then
			W.ShowTooltip(tile, choice.label or tostring(choice.value), nil, nil, "ANCHOR_TOP")
		end
	end, "script")

	local TileLeave = Shared("OnLeave on a picture flyout's tile", function(tile)
		OutlineShown(tile.hover, false)
		GameTooltip:Hide()
	end, "script")

	-- a tile picked: the flyout closed, the choice set (the live UI changes),
	-- the box drawn again
	local TileClick = Shared("OnClick on a picture flyout's tile", function(tile)
		local menu = tile.menu
		local box = menu and menu.box
		local choice = tile.choice
		if not (box and choice) then
			return
		end
		MelloUI:PlayUISound("option_on")
		Menu.Close(menu)
		if box.melloSet then
			box.melloSet(choice.value)
		end
		box:Refresh()
	end, "script")

	local function NewTile(menu, i)
		local tile = CreateFrame("Button", nil, menu)
		tile:SetSize(TILE_BOX, TILE_BOX)
		tile.pic = CreateFrame("Frame", nil, tile)
		tile.pic:SetSize(TILE, TILE)
		tile.pic:SetPoint("CENTER")
		tile.layers = {}
		tile.size = TILE
		tile.none = tile.pic:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		tile.none:SetPoint("CENTER")
		tile.none:SetText("None")
		W.Paint(tile.none, "text", "text")
		tile.label = W.Text(tile, "GameFontHighlightSmall", nil, "text")
		tile.label:SetJustifyH("CENTER")
		tile.label:SetPoint("TOP", tile, "BOTTOM", 0, -1)
		tile.label:SetWidth(TILE_STEP - 4)
		tile.label:SetWordWrap(false)
		tile.mark = Outline(tile, 2, 0.12)
		tile.hover = Outline(tile, 1)
		OutlineShown(tile.hover, false)
		tile.menu = menu
		Perf.SetScript(tile, "OnEnter", TileEnter)
		Perf.SetScript(tile, "OnLeave", TileLeave)
		Perf.SetScript(tile, "OnClick", TileClick)
		menu.tiles[i] = tile
		return tile
	end

	-- the box's page scrolled away from where the flyout opened: it closes
	local PictureScrolled = Shared("SetVerticalScroll on a page with a picture row (its flyout closes)", function(scroll, offset)
		for menu in pairs(openMenus) do
			if menu.scroll == scroll then
				local at = Num(offset)
				if not (at and menu.scrollAt and math.abs(at - menu.scrollAt) < 0.5) then
					Menu.Close(menu)
				end
			end
		end
	end, "hook")

	-- the ScrollFrame the box lies in (the page's), up to the host; nil for none
	local function ScrollOf(box, host)
		local f = box:GetParent()
		for _ = 1, 20 do
			if not f or f == host then
				return nil
			end
			if f:GetObjectType() == "ScrollFrame" then
				return f
			end
			f = f:GetParent()
		end
		return nil
	end

	-- the flyout closed by what is not one of its tiles: the catcher (a click or
	-- the wheel outside it), a fight, its own hide (Escape) or its host's
	local CatcherClick = Shared("OnMouseDown / OnMouseWheel on a picture flyout's catcher", function(catcher)
		Menu.Close(catcher.menu)
	end, "script")

	local MenuEvent = Shared("OnEvent on a picture flyout (a fight starts)", function(menu)
		Menu.Close(menu)
	end, "script")

	local MenuHidden = Shared("OnHide on a picture flyout (Escape, the window hidden)", function(menu)
		Menu.Close(menu)
	end, "script")

	local ListWheel -- (the wheel over a list: below, with the list's rows)

	local HostHidden = Shared("OnHide on a window with a picture flyout", function(host)
		local menu = menuOf[host]
		if menu then
			Menu.Close(menu)
		end
	end, "script")

	-- the flyout's UI shade (with the host's shell: through skin:Kit, the kit
	-- handed over, never reached for)
	local function ShadeMenu(K, menu)
		local el = K:ShadeElement(menu, "windows", { host = menu })
		el:Add(menu, SQUARE_SHADE)
	end

	-- The flyout's shell: its host's own (a window in the plain look has one
	-- too, though a row there is given none), else the one its caller gave.
	-- Its Escape is held while the flyout is open, and the shade asked
	-- through it (now with the kit look on, else at the switch to it); taken
	-- once, when there is one.
	local function AdoptShell(menu, skin)
		if menu.skin then
			return
		end
		local K = KitNow()
		skin = (K and K.ShellOf and K:ShellOf(menu.host)) or skin
		if skin then
			menu.skin = skin
			skin:Kit(ShadeMenu, menu)
		end
	end

	function W.PictureMenu(host, skin)
		local menu = menuOf[host]
		if menu then
			AdoptShell(menu, skin)
			return menu
		end
		local own = host:GetName()
		if not own then
			unnamed = unnamed + 1
			own = unnamed == 1 and "MelloUIWindow" or ("MelloUIWindow" .. unnamed)
		end
		local name = own .. "PictureMenu"
		menu = W.Panel(CreateFrame("Frame", name, host), { on = true })
		menu:EnableMouse(true)
		menu:SetClampedToScreen(true)   -- (a window by the screen's edge: the screen holds it)
		menu:Hide()
		menu.host, menu.tiles, menu.rows = host, {}, {}
		-- (the wheel: a list's own while one is open, else the catcher's)
		Perf.SetScript(menu, "OnMouseWheel", ListWheel)
		menu:EnableMouseWheel(false)
		local catcher = CreateFrame("Frame", nil, host)
		catcher:SetAllPoints(host)
		catcher:EnableMouse(true)
		catcher:EnableMouseWheel(true)
		catcher.menu = menu
		Perf.SetScript(catcher, "OnMouseDown", CatcherClick)
		Perf.SetScript(catcher, "OnMouseWheel", CatcherClick)
		catcher:Hide()
		menu.catcher = catcher
		Perf.SetScript(menu, "OnEvent", MenuEvent)
		Perf.SetScript(menu, "OnHide", MenuHidden)
		Perf.HookScript(host, "OnHide", HostHidden)
		tinsert(UISpecialFrames, name)   -- (Escape closes it; hidden, the game passes it by)
		menuOf[host] = menu
		AdoptShell(menu, skin)
		return menu
	end

	function W.ClosePictureMenu(host)
		local menu = host and menuOf[host]
		if menu then
			Menu.Close(menu)
		end
	end

	function W.CloseFlyouts()
		local any = false
		for menu in pairs(openMenus) do
			Menu.Close(menu)   -- (its entry cleared while walked: allowed)
			any = true
		end
		return any
	end

	-- the tiles for the box's choices, the chosen one marked; the flyout sized
	-- to them
	local function LayTiles(menu, box)
		local choices, kind = box.melloChoices, box.melloKind
		local chosen = box.melloGet and box.melloGet()
		local n = #choices
		-- (a list's rows away, if one opened here before)
		for i = 1, #menu.rows do
			menu.rows[i]:Hide()
		end
		if menu.listBar then
			menu.listBar:Hide()
		end
		for i = 1, n do
			local tile = menu.tiles[i] or NewTile(menu, i)
			local choice = choices[i]
			tile.choice = choice
			tile:ClearAllPoints()
			tile:SetPoint("TOPLEFT", menu, "TOPLEFT", MENU_PAD + ((i - 1) % TILE_COLS) * TILE_STEP,
				-(MENU_PAD + math.floor((i - 1) / TILE_COLS) * TILE_LINE))
			tile.label:SetText(choice.label or tostring(choice.value))
			DrawChoice(tile, kind, choice)
			local on = choice.value == chosen
			OutlineShown(tile.mark, on)
			OutlineShown(tile.hover, false)
			W.Paint(tile.label, on and "selectedTrim" or "text", "text")
			tile:Show()
		end
		for i = n + 1, #menu.tiles do
			menu.tiles[i]:Hide()
		end
		local cols, lines = math.min(n, TILE_COLS), math.ceil(n / TILE_COLS)
		menu:SetSize(2 * MENU_PAD + (cols - 1) * TILE_STEP + TILE_BOX, 2 * MENU_PAD + lines * TILE_LINE - 6)
	end


	-- A dropdown's list: a row per entry from a pool (an open makes no frame
	-- once the pool holds enough), ListRows of them shown from the list's top
	-- entry (menu.listTop, 0 the first), the others by the wheel over the
	-- list or its scroll bar (a Slider: its thumb dragged, its track
	-- clicked), the chosen entry in the middle of the view as it opens. As
	-- wide as its box, or its widest entry (to LIST_MAX_W). The row under the
	-- pointer in `hover`, its text `text`; the chosen one's text in gold (but
	-- on the hover: `text`, the palette's rule) with a gold mark before it.

	-- the rows a list of `count` shows: every one of a short list; at most
	-- MENU_ROWS of a long one, never more than MENU_SCREEN of the screen (its
	-- height in the flyout's own units: the UI scale and the window's are in
	-- it), MENU_MIN_ROWS however small
	local function ListRows(menu, count)
		local rows = MENU_ROWS
		local screen = Num(UIParent:GetHeight())
		local ui, own = Num(UIParent:GetEffectiveScale()), Num(menu:GetEffectiveScale())
		if screen and ui and own and own > 0 then
			local fit = math.floor((screen * ui / own * MENU_SCREEN - 2 * LIST_PAD) / LIST_ROW_H)
			rows = math.max(MENU_MIN_ROWS, math.min(rows, fit))
		end
		return math.min(count, rows)
	end

	local function RowLook(row)
		local lit = row.lit and true or false
		row.fill:SetShown(lit)
		W.Paint(row.label, (row.chosen and not lit) and "selectedTrim" or "text", "text")
	end

	local ListRowEnter = Shared("OnEnter on a dropdown list's row", function(row)
		row.lit = true
		RowLook(row)
		local entry = row.entry
		if entry and entry.tooltip then
			W.ShowTooltip(row, EntryText(entry), entry.tooltip)
		end
	end, "script")

	local ListRowLeave = Shared("OnLeave on a dropdown list's row", function(row)
		row.lit = nil
		RowLook(row)
		if GameTooltip:GetOwner() == row then
			GameTooltip:Hide()
		end
	end, "script")

	-- an entry picked: the list closed, the value set, the box naming it
	local ListRowClick = Shared("OnClick on a dropdown list's row", function(row)
		local menu = row.menu
		local box = menu and menu.box
		local entry = row.entry
		if not (box and entry) then
			return
		end
		MelloUI:PlayUISound("option_on")
		Menu.Close(menu)
		if box.melloSet then
			box.melloSet(entry.value)
		end
		box:Refresh()
	end, "script")

	local function NewListRow(menu, i)
		local row = CreateFrame("Button", nil, menu)
		row:SetHeight(LIST_ROW_H)
		row.fill = row:CreateTexture(nil, "BACKGROUND")
		row.fill:SetAllPoints(row)
		W.Paint(row.fill, "hover", "fill", 1)
		row.fill:Hide()
		row.mark = row:CreateTexture(nil, "ARTWORK")
		row.mark:SetSize(LIST_MARK, LIST_MARK)
		row.mark:SetPoint("LEFT", row, "LEFT", (LIST_TEXT_X - LIST_MARK) / 2, 0)
		W.Paint(row.mark, "selectedTrim", "fill", 1)
		row.label = W.Text(row, "GameFontHighlight", nil, "text")
		row.label:SetJustifyV("MIDDLE")
		row.label:SetWordWrap(false)
		row.label:SetPoint("LEFT", row, "LEFT", LIST_TEXT_X, 0)
		row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
		row.menu = menu
		Perf.SetScript(row, "OnEnter", ListRowEnter)
		Perf.SetScript(row, "OnLeave", ListRowLeave)
		Perf.SetScript(row, "OnClick", ListRowClick)
		menu.rows[i] = row
		return row
	end

	-- the shown rows from the list's top entry
	local function FillList(menu)
		local values, chosen = menu.listValues, menu.listChosen
		local top, rows = menu.listTop, menu.rows
		for i = 1, menu.listShown do
			local row = rows[i]
			local entry = values[top + i]
			if entry then
				row.entry = entry
				row.label:SetText(EntryText(entry))
				row.chosen = entry.value == chosen
				row.mark:SetShown(row.chosen)
				RowLook(row)
				row:Show()
			else
				row.entry = nil
				row:Hide()
			end
		end
		for i = menu.listShown + 1, #rows do
			rows[i]:Hide()
		end
	end

	-- the list moved (the thumb dragged, the track clicked, the wheel): the
	-- rows from the new top (a row's tooltip goes with its entry)
	local ListBarMoved = Shared("OnValueChanged on a dropdown list's scroll bar", function(bar, value)
		local menu = bar.menu
		if menu.listLaying then
			return
		end
		value = math.floor((Num(value) or 0) + 0.5)
		if value == menu.listTop then
			return
		end
		menu.listTop = value
		FillList(menu)
		local owner = GameTooltip:GetOwner()
		if owner and owner.menu == menu then
			GameTooltip:Hide()
		end
	end, "script")

	-- a long list's scroll bar: a thin `border` track, a `trim` thumb (made
	-- with the first long list)
	local function ListBar(menu)
		local bar = menu.listBar
		if bar then
			return bar
		end
		bar = CreateFrame("Slider", nil, menu)
		bar:SetOrientation("VERTICAL")
		bar:SetWidth(LIST_BAR)
		bar:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -LIST_PAD, -LIST_PAD)
		bar:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -LIST_PAD, LIST_PAD)
		bar:EnableMouseWheel(false)
		local track = W.Solid(bar, "BACKGROUND", "border", 1)
		track:SetAllPoints(bar)
		local thumb = bar:CreateTexture(nil, "ARTWORK")
		thumb:SetWidth(LIST_BAR)
		W.Paint(thumb, "trim", "fill", 1)
		bar:SetThumbTexture(thumb)
		bar:SetValueStep(1)
		bar:SetObeyStepOnDrag(true)
		bar.menu, bar.thumb = menu, thumb
		Perf.SetScript(bar, "OnValueChanged", ListBarMoved)
		menu.listBar = bar
		return bar
	end

	ListWheel = Shared("OnMouseWheel on a dropdown list", function(menu, delta)
		local bar, count, shown = menu.listBar, menu.listCount, menu.listShown
		if not (bar and count and shown and count > shown) then
			return
		end
		local top = menu.listTop - (Num(delta) or 0) * WHEEL_ROWS
		bar:SetValue(math.max(0, math.min(count - shown, top)))   -- (its OnValueChanged moves the list)
	end, "script")

	-- the rows for the box's list, the chosen one marked and in view; the
	-- flyout sized to them (the tiles away, if pictures opened here before)
	local function LayList(menu, box)
		local values = box.melloValues
		local n = #values
		for i = 1, #menu.tiles do
			menu.tiles[i]:Hide()
		end
		local shown = ListRows(menu, n)
		local long = n > shown
		local chosen = box.melloGet and box.melloGet()
		menu.listValues, menu.listChosen, menu.listCount, menu.listShown = values, chosen, n, shown
		-- as wide as the box, or its widest entry (measured on the list's own
		-- hidden text, made with its first open)
		local measure = menu.listMeasure
		if not measure then
			measure = menu:CreateFontString(nil, "BACKGROUND", "GameFontHighlight")
			measure:Hide()
			menu.listMeasure = measure
		end
		local width = measure.GetUnboundedStringWidth or measure.GetStringWidth
		local widest = 0
		for i = 1, n do
			measure:SetText(EntryText(values[i]))
			widest = math.max(widest, Num(width(measure)) or 0)
		end
		local right = LIST_PAD + (long and (LIST_BAR + 2) or 0)
		local w = math.max(Num(box:GetWidth()) or 0, math.ceil(widest) + LIST_TEXT_X + 6 + LIST_PAD + right)
		menu:SetSize(math.min(LIST_MAX_W, w), 2 * LIST_PAD + shown * LIST_ROW_H)
		for i = 1, shown do
			local row = menu.rows[i] or NewListRow(menu, i)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", menu, "TOPLEFT", LIST_PAD, -(LIST_PAD + (i - 1) * LIST_ROW_H))
			row:SetPoint("RIGHT", menu, "RIGHT", -right, 0)
			row.lit = nil
		end
		-- the chosen one in the middle of the view (as near as the ends allow)
		local at = ChoiceIndex(values, chosen)
		local top = 0
		if long and at then
			top = math.max(0, math.min(n - shown, at - 1 - math.floor(shown / 2)))
		end
		menu.listTop = top
		local bar = long and ListBar(menu) or menu.listBar
		if bar then
			if long then
				menu.listLaying = true
				bar:SetMinMaxValues(0, n - shown)
				bar:SetValue(top)
				menu.listLaying = nil
				bar.thumb:SetHeight(math.max(16, math.floor(shown * LIST_ROW_H * shown / n)))
				bar:Show()
			else
				bar:Hide()
			end
		end
		FillList(menu)
	end

	-- a list laid from its box's left would pass the screen's right edge (a
	-- long entry in a narrow box by the screen's edge: review, 2026-09-29).
	-- In screen pixels: the UI scale and the window's own are in them
	local function PastRight(menu, box)
		local left, width, screen = Num(box:GetLeft()), Num(menu:GetWidth()), Num(UIParent:GetRight())
		if not (left and width and screen) then
			return false
		end
		local own = Num(box:GetEffectiveScale()) or 1
		local ui = Num(UIParent:GetEffectiveScale()) or 1
		return left * own + width * (Num(menu:GetEffectiveScale()) or own) > screen * ui + 0.5
	end

	-- under the box, or over it when there is no room below: the pictures
	-- right under it, inside the host; a list left under it, on the screen
	-- (a window as small as Edit Layout's bar would put every list over it),
	-- by the box's right instead when it would pass the screen's right edge
	local function PlaceMenu(menu, box, list)
		menu:ClearAllPoints()
		local below = Num(box:GetBottom())
		local floor = list and 0 or Num(menu.host:GetBottom())
		local h = Num(menu:GetHeight()) or 0
		local gap = list and LIST_GAP or MENU_GAP
		local up = below and floor and below - floor < h + gap + (list and 0 or MENU_PAD)
		if list then
			local right = PastRight(menu, box)
			if up then
				menu:SetPoint(right and "BOTTOMRIGHT" or "BOTTOMLEFT", box, right and "TOPRIGHT" or "TOPLEFT", 0, gap)
			else
				menu:SetPoint(right and "TOPRIGHT" or "TOPLEFT", box, right and "BOTTOMRIGHT" or "BOTTOMLEFT", 0, -gap)
			end
		elseif up then
			menu:SetPoint("BOTTOMRIGHT", box, "TOPRIGHT", 0, gap)
		else
			menu:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -gap)
		end
	end

	function Menu.Open(menu, box)
		local list = box.melloList
		local entries = list and box.melloValues or box.melloChoices
		if not (entries and #entries > 0) then
			return
		end
		if openMenus[menu] then
			Menu.Close(menu)
		end
		if list then
			LayList(menu, box)
		else
			LayTiles(menu, box)
		end
		PlaceMenu(menu, box, list)
		-- over the page and every row of it (a sleeping row's cover too), the
		-- catcher right under it
		local level = math.max(Num(box:GetFrameLevel()) or 0, Num(menu.host:GetFrameLevel()) or 0) + MENU_LIFT
		menu.catcher:SetFrameLevel(level)
		menu:SetFrameLevel(level + 2)
		menu.box = box
		openMenus[menu] = true
		local scroll = ScrollOf(box, menu.host)
		menu.scroll, menu.scrollAt = scroll, scroll and Num(scroll:GetVerticalScroll()) or nil
		if scroll and not scrollsHooked[scroll] then
			scrollsHooked[scroll] = true
			Perf.hooksecurefunc(scroll, "SetVerticalScroll", PictureScrolled)
		end
		-- (pictures close as a fight starts; a list stays, as the game's menu did)
		if not list then
			menu:RegisterEvent("PLAYER_REGEN_DISABLED")
		end
		menu:EnableMouseWheel(list and true or false)
		local skin = menu.skin
		if skin and skin.HoldEscape then
			skin:HoldEscape(true)
		end
		menu.catcher:Show()
		menu:Show()
		MelloUI:PlayUISound("tab")
	end

	function Menu.Close(menu)
		if not openMenus[menu] then
			return
		end
		openMenus[menu] = nil
		menu.box = nil
		menu:UnregisterEvent("PLAYER_REGEN_DISABLED")
		-- (a tile's tooltip goes with it: the pointer may still be on it)
		local owner = GameTooltip:GetOwner()
		if owner and owner.menu == menu then
			GameTooltip:Hide()
		end
		menu.catcher:Hide()
		menu:Hide()
		local skin = menu.skin
		if skin and skin.HoldEscape then
			skin:HoldEscape(false)
		end
	end

	local PictureBoxClick = Shared("OnClick on a picture row's box", function(box)
		if InCombatLockdown() then
			W.ShowTooltip(box, box.tipTitle or "", nil, NOT_IN_COMBAT)
			return
		end
		local host = box.melloHost
		if not host then
			return
		end
		local menu = W.PictureMenu(host, box.melloSkin)
		if menu.box == box then
			Menu.Close(menu)
		else
			Menu.Open(menu, box)
		end
	end, "script")

	-- the box hidden (its tab or page switched away, its window closed): its
	-- flyout with it (a picture row's box or a dropdown's)
	local PictureBoxHidden = Shared("OnHide on a picture row's box or a dropdown", function(box)
		local menu = box.melloHost and menuOf[box.melloHost]
		if menu and menu.box == box then
			Menu.Close(menu)
		end
	end, "script")
	Flyout.BoxHidden = PictureBoxHidden

	-- the window a dropdown lies in, its flyout's host: the nearest frame up
	-- its parents that has a shell (Kit:ShellOf: the configurator, the
	-- installer, the Restock List), else the top one under UIParent (Edit
	-- Layout's bar and box); nil for a box on UIParent itself
	local function HostOf(box)
		local K = KitNow()
		local f, top = box:GetParent(), nil
		for _ = 1, 30 do
			if not f or f == UIParent then
				break
			end
			if K and K.ShellOf and K:ShellOf(f) then
				return f
			end
			top = f
			f = f:GetParent()
		end
		return top
	end

	-- a dropdown's click: its list opened in its window's flyout, or closed
	-- (the same box again); the host found on the first click and kept
	function Flyout.Toggle(box)
		local host = box.melloHost or HostOf(box)
		if not host then
			return
		end
		box.melloHost = host
		local menu = W.PictureMenu(host, box.melloSkin)
		if menu.box == box then
			Menu.Close(menu)
		else
			Menu.Open(menu, box)
		end
	end

	local PictureBoxEnter = Shared("OnEnter on a picture row's box (hover)", function(box)
		W.Paint(box.fill, "hover", "fill", 1)
	end, "script")

	local PictureBoxLeave = Shared("OnLeave on a picture row's box (hover)", function(box)
		W.Paint(box.fill, "innerPanel", "fill", 1)
	end, "script")

	-- the chosen one's picture and name (drawn again only when it changed)
	local function PictureBoxRefresh(box)
		local choice = box.melloChoices and ChoiceOf(box.melloChoices, box.melloGet())
		if choice == box.shownChoice and box.melloKind == box.shownKind then
			return
		end
		box.shownChoice, box.shownKind = choice, box.melloKind
		box.name:SetText(choice and (choice.label or tostring(choice.value)) or "")
		DrawChoice(box, box.melloKind, choice)
	end

	local function PictureBoxSetChoices(box, choices, kind)
		box.melloChoices = choices
		if kind then
			box.melloKind = kind
		end
		box.shownChoice = false   -- (drawn again)
		PictureBoxHidden(box)     -- (a flyout open on the old list closes)
		box:Refresh()
	end

	function W.PictureRow(parent, y, label, hint, desc, get, set, choices, kind, opts)
		opts = opts or NO_OPTS
		local row = W.Row(parent, y, W.ROW_HEIGHT, label, hint, desc, opts)
		local width = opts.width or PICTURE_W
		local box = CreateFrame("Button", nil, row)
		box:SetSize(width, PICTURE_H)
		box:SetPoint("RIGHT", -14, 0)
		box.fill = box:CreateTexture(nil, "BACKGROUND")
		box.fill:SetAllPoints(box)
		W.Paint(box.fill, "innerPanel", "fill", 1)
		box.edges = Edges(box, "border", "BORDER")
		box.pic = CreateFrame("Frame", nil, box)
		box.pic:SetSize(PICTURE_H, PICTURE_H)
		box.pic:SetPoint("LEFT", box, "LEFT", 0, 0)
		box.layers, box.size = {}, PICTURE_H
		box.none = box.pic:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		box.none:SetPoint("CENTER")
		box.none:SetText("None")
		W.Paint(box.none, "text", "text")
		box.none:Hide()
		box.name = W.Text(box, "GameFontHighlight", nil, "text")
		box.name:SetPoint("LEFT", box.pic, "RIGHT", 8, 0)
		box.name:SetPoint("RIGHT", box, "RIGHT", -8, 0)
		box.name:SetWordWrap(false)
		box.melloGet, box.melloSet, box.melloChoices, box.melloKind = get, set, choices, kind
		box.melloHost, box.melloSkin = opts.host, opts.skin
		box.shownChoice = false
		box.Refresh, box.SetChoices = PictureBoxRefresh, PictureBoxSetChoices
		Perf.SetScript(box, "OnClick", PictureBoxClick)
		Perf.SetScript(box, "OnHide", PictureBoxHidden)
		Perf.HookScript(box, "OnEnter", PictureBoxEnter)
		Perf.HookScript(box, "OnLeave", PictureBoxLeave)
		ControlTip(box, row, label, desc)
		box:Refresh()
		return Finish(row, box, opts, 14 + width)
	end
end

--------------------------------------------------------------------------------
-- LinkRow (0.15.0): a row for a setting kept on another page -- a global one
-- on Look, the map's width on Minimap -- showing its value as text and a
-- flat button naming the page it lives on ("Look >"). The click is the
-- caller's (the configurator's jump: the page, its tab and pick, the row
-- flashed). Every option has ONE place: a link row is never a copy of it.
--   W.LinkRow(parent, y, label, get, onClick, opts) -> row
--     get()      the setting's value to show: text, or a boolean (On / Off)
--                or a number
--     onClick    a shared fn(row)
--     opts       target (the page's title: the button reads target .. " >",
--                as wide as its text, 60 to 110), desc (the row's tooltip)
--                and W.Row's (skin, inset, indent, zebra, line, look, gate,
--                note, onCover, new)
--   row:SetTarget(target, get)   another page and value (a per-pick link;
--                                nil keeps that part)
--   row:Refresh()   the value read again, and the row's gate
--   row.button, row.value
--------------------------------------------------------------------------------

do
	local LINK_W_MIN, LINK_W_MAX, LINK_PAD = 60, 110, 24   -- the link's button: its width's bounds, the room round its text
	local LINK_OPTS = {}   -- (the row's options less its gate, which comes once the value is placed)

	local function LinkText(v)
		if v == true then
			return "On"
		elseif v == false then
			return "Off"
		elseif v == nil then
			return ""
		end
		return tostring(v)
	end

	local LinkClick = Shared("OnClick on a link row's button", function(button)
		local row = button.melloLinkRow
		if row and row.linkClick then
			row.linkClick(row)
		end
	end, "script")

	local function LinkRowRefresh(row)
		local text = LinkText(row.linkGet and row.linkGet())
		if row.value:GetText() ~= text then
			row.value:SetText(text)
		end
		local cover = gateOf[row]
		if cover then
			cover:Refresh()
		end
	end

	local function LinkRowSetTarget(row, target, get)
		if target then
			local button = row.button
			button:SetText(target .. " >")
			local fs = button:GetFontString()
			local w = fs and TextWidth(fs)
			button:SetWidth(math.max(LINK_W_MIN, math.min(LINK_W_MAX, (w or 0) + LINK_PAD)))
		end
		if get then
			row.linkGet = get
		end
		row:Refresh()
	end

	function W.LinkRow(parent, y, label, get, onClick, opts)
		opts = opts or NO_OPTS
		local o = LINK_OPTS
		o.skin, o.inset, o.indent, o.zebra, o.line = opts.skin, opts.inset, opts.indent, opts.zebra, opts.line
		o.look, o.strength, o.new, o.labelKey = opts.look, opts.strength, opts.new, opts.labelKey
		local row = W.Row(parent, y, W.ROW_HEIGHT, label, nil, opts.desc, o)
		o.skin, o.inset, o.indent, o.zebra, o.line, o.look, o.strength, o.new, o.labelKey = nil, nil, nil, nil, nil, nil, nil, nil, nil
		local button = W.Button(row, "", LINK_W_MIN, nil, { onClick = LinkClick })
		button:SetPoint("RIGHT", -12, 0)
		button.melloLinkRow = row
		row.button = button
		row.value = W.Text(row, "GameFontHighlight", nil, "text")
		row.value:SetJustifyH("RIGHT")
		row.value:SetWordWrap(false)
		row.value:SetPoint("RIGHT", button, "LEFT", -10, 0)
		row.linkGet, row.linkClick = get, onClick
		row.Refresh, row.SetTarget = LinkRowRefresh, LinkRowSetTarget
		controlOf[row] = button
		W.RowPlateChild(row, button)
		ControlTip(button, row, label, opts.desc)
		-- (the gate's line, as a typed row's, before the texts are cut at the value)
		if opts.gate then
			W.Gate(row, opts.gate, opts)
		end
		W.ClipRow(row, row.value)
		row:SetTarget(opts.target, nil)
		return row
	end
end

--------------------------------------------------------------------------------
-- Card: one choice among a few, shown whole (the installer's four setups; the
-- Fresh start wizard's Kit Colours and Font Styles): a box with a title, a
-- line under it, a tag at its top right (W.Tag: "Recommended") and a picture
-- above the texts when given. ONE "selected" look for the addon, the NavRail
-- marker's: the raised panel's fill, a 2 px selectedTrim edge, the title in
-- gold. At rest the main window's tone at 0.85 (a stripe on the dark inner
-- panel, as rows have it: WINDOW-RULES 2e) inside a 1 px border edge, the
-- title in the text colour. The hover is W.RowPlate's palette wash with its
-- gold edge, none on the selected card (gold on the hover colour is under
-- 4.5:1).
--   local card = W.Card(parent, spec, skin)
--   spec: width (279), height (72), title, text, tag, picture (a texture
--         path) with pictureHeight (40), titleFont ("GameFontNormal"),
--         textFont ("GameFontHighlight"), key (the caller's value: card.key),
--         onClick (a shared fn(card): the caller's pick; the card plays the
--         "tab" sound itself), palette (a palette's id: a palette's card --
--         that palette's swatch where a picture goes, pictureHeight 12 high,
--         the palette's name for a title not given, the id for a key not
--         given, the texts 8 px in from the sides, as the swatch; the
--         installer's Look step)
--   card:SetSelected(on)   card:IsSelected()   card:SetTexts(title, text)
--   card.title, card.text, card.picture, card.tag (the plate's FontString),
--   card.swatch (a palette's card)
-- A frame of the caller's laid on a card that takes the mouse is handed to
-- W.RowPlateChild(card, frame). The approved card is the palette look in both
-- looks; with the kit on (its `skin`: a shell) the chosen card wears the
-- active look too (0.15.0, Kit:SetActive: the one look for whatever is
-- selected). Colours by key only (a new palette paints it again); nothing is
-- made per click or hover.
--------------------------------------------------------------------------------

local cardOn = setmetatable({}, weakKeys)   -- [card] = true while it is the selected one

local function CardSelected(card)
	return cardOn[card] == true
end

-- (the chosen card's active look: WidgetActive, with the flat controls')

-- the cards of each shell, their looks put back at its switches (the chosen
-- card's edge too: Card_SetSelected)
local cardsOf = setmetatable({}, weakKeys)   -- [shell] = { [card] = true } (weak)
local function Cards_OnKit(shell)
	local set = cardsOf[shell]
	if set then
		for card in pairs(set) do
			card:SetSelected(cardOn[card] == true)
		end
	end
end

-- the four edges `px` thick, inside the card's rect (a point set again
-- replaces the one of that name: nothing is cleared, nothing made)
local function CardEdges(card, px)
	local e = card.edges
	e[1]:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
	e[1]:SetPoint("BOTTOMRIGHT", card, "TOPRIGHT", 0, -px)
	e[2]:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, px)
	e[2]:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
	e[3]:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
	e[3]:SetPoint("BOTTOMRIGHT", card, "BOTTOMLEFT", px, 0)
	e[4]:SetPoint("TOPLEFT", card, "TOPRIGHT", -px, 0)
	e[4]:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
end

local function Card_SetSelected(card, on)
	on = on and true or false
	cardOn[card] = on or nil
	W.Paint(card.fill, on and "raisedPanel" or "mainWindow", "fill", on and 1 or 0.85)
	-- the gold edge gives way to the active look while that shows (its ring,
	-- added as light, lies on the edge: gold on gold burned out to a pale
	-- yellow, near white under Obsidian; review 2026-09-28): the resting
	-- 1 px edge under it
	local gold = on and not (card.melloSkin and card.melloSkin.kit)
	CardEdges(card, gold and 2 or 1)
	for i = 1, 4 do
		W.Paint(card.edges[i], gold and "selectedTrim" or "border", "fill", 1)
	end
	W.Paint(card.title, on and "selectedTrim" or "text", "text")
	if on then
		W.RowPlateOff(card)   -- (just picked: its wash goes at once)
	end
	WidgetActive(card.melloSkin, card, on)
end

local function Card_IsSelected(card)
	return cardOn[card] == true
end

local function Card_SetTexts(card, title, text)
	card.title:SetText(title or "")
	card.text:SetText(text or "")
end

local CardClick = Shared("OnClick on MelloUI's cards", function(card)
	MelloUI:PlayUISound("tab")
	if card.melloClick then
		card.melloClick(card)
	end
end, "script")

local CARD_PLATE = { look = "palette", edge = true, selected = CardSelected }

function W.Card(parent, spec, skin)
	spec = spec or NO_OPTS
	local card = CreateFrame("Button", nil, parent)
	local width = spec.width or 279
	card:SetSize(width, spec.height or 72)
	local palette = spec.palette
	card.key, card.melloClick = spec.key == nil and palette or spec.key, spec.onClick
	card.fill = card:CreateTexture(nil, "BACKGROUND", nil, 0)
	card.fill:SetAllPoints(card)
	card.edges = {}
	for i = 1, 4 do
		card.edges[i] = card:CreateTexture(nil, "BORDER")
	end
	local top, inset = -10, 12
	if palette then
		-- a palette's card: its swatch (a picture of that palette) where a
		-- picture goes, its name under it at the swatch's own 8 px sides (a
		-- small card: "Royal Azure Vibrant" needs 116 of a 136 card's 120)
		local h = spec.pictureHeight or 12
		card.swatch = W.PaletteSwatch(card, { id = palette, width = width - 16, height = h })
		card.swatch:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -8)
		top, inset = -8 - h - 4, 8
	elseif spec.picture then
		local h = spec.pictureHeight or 40
		card.picture = card:CreateTexture(nil, "ARTWORK")
		card.picture:SetTexture(spec.picture)
		card.picture:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -8)
		card.picture:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
		card.picture:SetHeight(h)
		top = -8 - h - 6
	end
	card.title = W.Text(card, spec.titleFont or "GameFontNormal", spec.title or (palette and W.PaletteName(palette)))
	card.title:SetWordWrap(false)
	card.title:SetPoint("TOPLEFT", card, "TOPLEFT", inset, top)
	if spec.tag then
		-- the tag (W.Tag, the one plate: an option's New tag is the same)
		card.tag = W.Tag(card, spec.tag)
		card.tag:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, top - 1)
		card.tagPlate = card.tag.plate
		card.title:SetPoint("RIGHT", card.tagPlate, "LEFT", -8, 0)
	else
		card.title:SetPoint("RIGHT", card, "RIGHT", -inset, 0)
	end
	card.text = W.Text(card, spec.textFont or "GameFontHighlight", spec.text, "text")
	card.text:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -5)
	card.text:SetPoint("RIGHT", card, "RIGHT", -inset, 0)
	card.text:SetWordWrap(true)
	card.SetSelected, card.IsSelected, card.SetTexts = Card_SetSelected, Card_IsSelected, Card_SetTexts
	W.RowPlate(card, CARD_PLATE)
	Perf.SetScript(card, "OnClick", CardClick)
	if skin and skin.OnKit then
		-- (the chosen card's active look follows the window's look switch)
		card.melloSkin = skin
		local set = cardsOf[skin]
		if not set then
			set = setmetatable({}, weakKeys)
			cardsOf[skin] = set
		end
		set[card] = true
		skin:OnKit(Cards_OnKit)
	end
	card:SetSelected(false)
	return card
end

--------------------------------------------------------------------------------
-- Palettes (0.14.0, user 2026-09-26: "A palette picker"): ONE set of parts
-- for every place a palette is chosen -- the configurator's Look page (its
-- Home shows it), the installer's Look step -- over Core's registry
-- (MelloUI.Palettes, MelloUI:PaletteId, MelloUI:SetPalette, which applies it).
--   W.PaletteSwatch(parent, spec) -> swatch   a frame: a strip of chips, one
--       per role of W.SWATCH_ROLES left to right, inside a 1 px `border`
--       edge (swatch.back, painted by key: it follows a switch)
--     spec: width (60), height (14), id (a palette's id: a PICTURE of that
--       palette, its own colours, which no switch repaints -- the installer's
--       cards, a list of palettes; nil: the palette in use, its chips painted
--       by key, so a switch paints them again -- the Home row)
--     swatch:SetPalette(id)   a picture shows another palette (nil or an
--       unknown id: Ember); the palette in use's swatch is left as it is
--     swatch.chips, swatch.back, swatch.id (nil: the palette in use)
--   W.PaletteValues() -> values   the palettes in their order as a
--       dropdown's values ({ value = id, label = name, tooltip = blurb }),
--       made the first time it is asked for, the same table after
--   W.PaletteName(id) -> name     (Ember's for nil or an unknown id)
--   W.PaletteFill(texture, id, role)   a texture in that palette's colour
--       for `role`: a picture, never repainted (a swatch's chips; the
--       installer's picture of a drafted look)
--   W.Card(parent, { palette = id, ... }, skin)   a palette's card (Card)
-- Nothing is made at load; a swatch makes its textures once, and showing
-- another palette makes nothing.
--------------------------------------------------------------------------------

W.SWATCH_ROLES = { "mainWindow", "selectedTab", "trim", "selectedTrim", "text" }

-- a palette's entry in Core's registry (Ember's for nil or an unknown id:
-- Core's one rule, MelloUI:KnownPalette)
local function PaletteEntry(id)
	return MelloUI.Palettes[MelloUI:KnownPalette(id)]
end

function W.PaletteName(id)
	return PaletteEntry(id).name
end

-- a texture in one role's colour of a NAMED palette (a picture of that
-- palette -- a swatch's chip, a picture of a drafted look -- which no switch
-- repaints; nil or an unknown id: Ember). Never on a region painted by key.
function W.PaletteFill(region, id, role)
	local c = PaletteEntry(id).roles[role]
	region:SetColorTexture(c[1], c[2], c[3], 1)
end

do
	local values = nil
	function W.PaletteValues()
		if not values then
			values = {}
			for i, id in ipairs(MelloUI.Palettes.order) do
				local entry = MelloUI.Palettes[id]
				values[i] = { value = id, label = entry.name, tooltip = entry.blurb }
			end
		end
		return values
	end
end

local function Swatch_SetPalette(swatch, id)
	if swatch.id == nil then
		return   -- (the palette in use: its chips are painted by key)
	end
	local entry = PaletteEntry(id)
	swatch.id = entry.id
	local chips = swatch.chips
	for i = 1, #chips do
		W.PaletteFill(chips[i], entry.id, W.SWATCH_ROLES[i])
	end
end

function W.PaletteSwatch(parent, spec)
	spec = spec or NO_OPTS
	local width, height = spec.width or 60, spec.height or 14
	local swatch = CreateFrame("Frame", nil, parent)
	swatch:SetSize(width, height)
	local roles = W.SWATCH_ROLES
	local n = #roles
	local w = (width - 2) / n
	-- the edge: the swatch's ground in `border`, the chips 1 px inside it
	-- (one texture, not four: a Look step lays seven swatches)
	swatch.back = swatch:CreateTexture(nil, "BACKGROUND")
	swatch.back:SetAllPoints(swatch)
	W.Paint(swatch.back, "border", "fill", 1)
	swatch.chips = {}
	for i = 1, n do
		local chip = swatch:CreateTexture(nil, "ARTWORK")
		chip:SetPoint("TOPLEFT", swatch, "TOPLEFT", 1 + (i - 1) * w, -1)
		chip:SetSize(w, height - 2)
		swatch.chips[i] = chip
		if spec.id == nil then
			W.Paint(chip, roles[i], "fill", 1)
		end
	end
	swatch.SetPalette = Swatch_SetPalette
	if spec.id ~= nil then
		swatch.id = false   -- (a picture: SetPalette fills it)
		swatch:SetPalette(spec.id)
	end
	return swatch
end

--------------------------------------------------------------------------------
-- NavRail: the configurator's side list AND the installer's steps rail, one
-- code.
--   local rail = W.NavRail(parent, spec)
--   spec: width, rowHeight (30), headerHeight (24), gap (1), iconSize (22;
--         0: no icons), inset (10), numbered (false: "3. Review"), scroll
--         (true: a ScrollFrame whose wheel glides at step 68; false: the box
--         as tall as its rows), box (true: the box -- W.Panel's look, the
--         palette's `innerPanel` in a `border` edge, in both looks:
--         rail.plainParts), skin, iconMaker (fn(row, size, skin) -> an icon
--         with :SetIcon and :SetOn, made once per row; nil: a plain texture),
--         onSelect (a shared fn(rail, key, entry)), clickable (nil: all;
--         fn(rail, key, entry) -> bool), doneGlyph (an atlas shown after a
--         done step's name)
--   rail:SetGroups(groups)   groups = { { key, title (nil: no header),
--                            collapsible, entries = { { key, text, icon,
--                            tip, new } } } }; rows and headers come from a pool
--                            (switching the installer's paths makes no frames).
--                            `new`: true (the caller asked MelloUI:IsNew of
--                            what the entry leads to) or an update's version:
--                            a snug New tag (W.Tag) near the row's right edge,
--                            and on its group's header while the group is
--                            folded; made with the first row or header that
--                            needs one
--   rail:Select(key, instant)   the one marker glides there (0.15 s); the
--                               same key again does nothing
--   rail:SetState(key, state)   nil | "off" (icon dimmed, name kept in the
--                               text colour) | "done" (doneGlyph) | "todo"
--   rail:Fold(groupKey, folded, instant)
--   rail:Reveal(key)   unfolds its group and scrolls the row into view AT
--                      ONCE (a help tip's target); returns the row
--   rail.rows[key], rail.selected, rail.box, rail.content, rail.scroll,
--   rail.glide, rail.marker
-- A search's results in the same list (0.14.0, the configurator's search
-- box; user, 2026-09-26: "search box in the next build"):
--   spec.head (0: none)   a strip that tall at the top of the box, over the
--                         list (rail.head: the caller's control goes there,
--                         the box's search field); the list starts under it
--   spec.resultHeight (38: the least a result row is; taller while the
--                         fonts are: its two lines' sizes and their room,
--                         read at each search, rail.resultHeight),
--                         spec.onResult (a shared fn(rail, entry): a result
--                         clicked)
--   rail:ShowResults(list, n, note)   the groups swapped for list[1..n] (the
--       caller's entries, read as they are laid: `name`, `path` (the small
--       line over it, "Page > Tab"; nil: the name alone; too wide for the
--       row, its first parts are left out -- " > " -- so its end, the part
--       that tells two results apart, stays: measured once per entry for the
--       row's room and font, kept in the entry as `pathShown`), `new` (true:
--       its snug New tag), `full`, `section` and `tip` (the tooltip: the
--       whole path)), one row
--       each from a pool of their own (made once, reused by every search;
--       new ones within the frame's one budget of rows), `note` a quiet line
--       under them (nothing found, how many more); the first one selected
--       (the marker), the list at its top. True when rows are still owed
--       (the budget spent): the caller asks rail:MoreResults() on a later
--       frame (Kit:NextFrame), again while it returns true
--   rail:HideResults(instant)   the groups back as they were (folds, the
--       marker on the selected entry, the list's own scroll)
--   rail:MoveResult(delta)   the marker to the next / previous result, kept
--       in view; rail:SelectResult(i); rail:Result() the selected result's
--       entry (nil: none); rail.resultsShown, rail.resultRows,
--       rail.resultCount, rail.resultIndex, rail.note
-- While results show, Select / SetState / Fold only record (the marker
-- stays on the result); nothing of them runs per frame.
-- Look (the approved sketch, kit or not): entries in the text colour (the
-- palette's muted text is 3.2:1, for large or bold labels only), the
-- selected one in gold on a `raisedPanel` marker with a 2 px gold edge;
-- headers in gold at full size, a folded one in the text colour unless it
-- holds the selected entry. A name is one line, cut at the row's edge, and
-- then shown whole in the row's tooltip.
--------------------------------------------------------------------------------

local Rail = {}
Rail.__index = Rail
local railOf = setmetatable({}, weakKeys)   -- [row or header] = its rail
local PLUS = "Interface\\Buttons\\UI-PlusButton-Up"
local MINUS = "Interface\\Buttons\\UI-MinusButton-Up"
local RAIL_TAG_IN = 2    -- a New tag's (snug) plate inside the row's right edge
local RAIL_TAG_GAP = 3   -- a name to its New tag's plate

local function IsSelected(row)
	local rail = railOf[row]
	return rail ~= nil and rail.selected == row.key
end

local RowClick = Shared("OnClick on a NavRail entry", function(row)
	local rail = railOf[row]
	if rail and rail.spec.onSelect then
		rail.spec.onSelect(rail, row.key, row.entry)
	end
end, "script")

local HeaderClick = Shared("OnClick on a NavRail group", function(header)
	local rail = railOf[header]
	if rail then
		rail:Fold(header.key, not rail.folded[header.key])
	end
end, "script")

-- the row's tooltip: the full name when the row cuts it (one line, word wrap
-- off), then the entry's tip; with neither, none. Hooked after RowPlate's
-- pair, so the wash and the tooltip both run on one enter.
local RailTipEnter = Shared("OnEnter on a NavRail entry (tooltip)", function(row)
	local icon = row.icon
	if icon and icon.SetHovered and icon:IsShown() then
		icon:SetHovered(true)
	end
	local e = row.entry
	local clippedName = row.text.IsTruncated and row.text:IsTruncated()
	local tip = e and e.tip
	if not (clippedName or tip) then
		return
	end
	local P = MelloUI.Palette
	local gold, text = P.selectedTrim, P.text
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if clippedName then
		GameTooltip:SetText(row.text:GetText(), gold[1], gold[2], gold[3], 1, true)
		if tip then
			GameTooltip:AddLine(tip, text[1], text[2], text[3], true)
		end
	else
		GameTooltip:SetText(tip, text[1], text[2], text[3], 1, true)
	end
	GameTooltip:Show()
end, "script")

local RailTipLeave = Shared("OnLeave on a NavRail entry (tooltip)", function(row)
	local icon = row.icon
	if icon and icon.SetHovered and icon:IsShown() then
		icon:SetHovered(false)
	end
	if GameTooltip:IsOwned(row) then
		GameTooltip:Hide()
	end
end, "script")

-- a kit rep shown or hidden (its holder when the rep has no SetShown)
local function RepShown(rep, shown)
	if not rep then
		return
	end
	if rep.SetShown then
		rep:SetShown(shown)
	elseif rep.object then
		rep.object:SetShown(shown)
	end
end

-- The marker's active look: on a list of text rows always (the installer's
-- steps), on a list of icon boxes while a search's results show (the chosen
-- entry's icon box wears it otherwise; a result row has none). Its own gold
-- edge gives way while the look shows (the look's ring over it burned out to
-- a pale yellow; review 2026-09-28)
local function MarkerLook(rail)
	local shell = rail.lookShell
	if not shell then
		return
	end
	local on = (rail.activeMarker or rail.resultsShown) and true or false
	WidgetActive(shell, rail.marker, on)
	rail.marker.edge:SetShown(not (on and shell.kit))
end

-- the rails of each shell, their glyphs and states put back at its switches
local railsOf = setmetatable({}, weakKeys)   -- [shell] = { [rail] = true } (weak)
local function Rails_OnKit(shell)
	local set = railsOf[shell]
	if set then
		for rail in pairs(set) do
			rail:Paint()
			MarkerLook(rail)
		end
	end
end

-- the kit's look of the rail's header glyphs (through skin:Kit)
local function DressHeader(K, h, skin)
	h.plusRep = skin:Replace(h.glyph, { as = "common-button-list-plus", button = h, rect = h.glyph })
	h.minusRep = skin:Replace(h.glyph, { as = "common-button-list-minus", button = h, rect = h.glyph })
	local rail = railOf[h]
	if rail then
		rail:Paint()
	end
end

local function NewRow(rail)
	local spec = rail.spec
	local row = CreateFrame("Button", nil, rail.content)
	row:SetHeight(spec.rowHeight)
	row:SetFrameLevel(rail.content:GetFrameLevel() + 1)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	W.RowPlate(row, { look = "palette", strength = 0.5, edge = false, selected = IsSelected })
	Perf.HookScript(row, "OnEnter", RailTipEnter)
	Perf.HookScript(row, "OnLeave", RailTipLeave)
	if spec.doneGlyph then
		-- (made with the row: a pooled row may carry a done step later)
		row.check = row:CreateTexture(nil, "OVERLAY")
		row.check:SetSize(14, 14)
		row.check:SetPoint("RIGHT", -6, 0)
		row.check:SetAtlas(spec.doneGlyph)
		row.check:Hide()
	end
	Perf.SetScript(row, "OnClick", RowClick)
	railOf[row] = rail
	return row
end

local function NewHeader(rail)
	local h = CreateFrame("Button", nil, rail.content)
	h:SetHeight(rail.spec.headerHeight)
	h:SetFrameLevel(rail.content:GetFrameLevel() + 1)
	h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	h.text:SetJustifyH("LEFT")
	h.text:SetWordWrap(false)
	h.text:SetPoint("LEFT", 26, 0)
	h.text:SetPoint("RIGHT", -6, 0)
	h.glyph = h:CreateTexture(nil, "ARTWORK")
	h.glyph:SetSize(14, 14)
	h.glyph:SetPoint("LEFT", 6, 0)
	Perf.SetScript(h, "OnClick", HeaderClick)
	railOf[h] = rail
	local skin = rail.spec.skin
	if skin then
		skin:Kit(DressHeader, h, skin)
	end
	return h
end

function W.NavRail(parent, spec)
	spec.rowHeight = spec.rowHeight or 30
	spec.headerHeight = spec.headerHeight or 24
	spec.gap = spec.gap or 1
	spec.inset = spec.inset or 10
	spec.iconSize = spec.iconSize or 22
	spec.head = spec.head or 0
	spec.resultHeight = spec.resultHeight or 38
	local rail = setmetatable({ spec = spec, rows = {}, headers = {}, order = {}, folded = {}, groupOf = {},
		state = {}, rowPool = {}, headerPool = {}, selected = nil, resultRows = {}, resultCount = 0,
		resultsShown = false, resultHeight = spec.resultHeight }, Rail)
	local skin = spec.skin
	local box = CreateFrame("Frame", nil, parent)
	box:SetWidth(spec.width)
	rail.box = box
	if spec.box ~= false then
		-- (W.Panel's look in both looks, 0.15.0: the kit's list box, L1, is
		-- the game windows')
		local fill, edges = PanelLook(box, 1)
		rail.plainParts = edges   -- (the four edges, then the fill)
		rail.plainParts[5] = fill
	end
	rail.width = spec.width - 2 * spec.inset   -- the rows' width
	-- (the caller's strip over the list: the configurator's search box)
	local top = spec.inset + spec.head
	if spec.head > 0 then
		rail.head = CreateFrame("Frame", nil, box)
		rail.head:SetPoint("TOPLEFT", spec.inset, -spec.inset)
		rail.head:SetPoint("TOPRIGHT", -spec.inset, -spec.inset)
		rail.head:SetHeight(spec.head)
	end
	if spec.scroll ~= false then
		local scroll = CreateFrame("ScrollFrame", nil, box)
		scroll:SetPoint("TOPLEFT", spec.inset, -top)
		scroll:SetPoint("BOTTOMRIGHT", -spec.inset, spec.inset)
		rail.content = CreateFrame("Frame", nil, scroll)
		rail.content:SetWidth(rail.width)
		scroll:SetScrollChild(rail.content)
		rail.scroll = scroll
		rail.glide = MelloUI.Anim:Glide(scroll, { step = 68 })
	else
		rail.content = CreateFrame("Frame", nil, box)
		rail.content:SetPoint("TOPLEFT", spec.inset, -top)
		rail.content:SetWidth(rail.width)
	end
	-- the one marker, at the content's level; the rows one above it, so their
	-- text draws over it
	local marker = CreateFrame("Frame", nil, rail.content)
	marker:SetFrameLevel(rail.content:GetFrameLevel())
	marker:SetHeight(spec.rowHeight)
	rail.markerHeight = spec.rowHeight
	marker.fill = marker:CreateTexture(nil, "BACKGROUND")
	marker.fill:SetAllPoints(marker)
	W.Paint(marker.fill, "raisedPanel", "fill", 1)
	marker.edge = marker:CreateTexture(nil, "BORDER")
	marker.edge:SetWidth(2)
	marker.edge:SetPoint("TOPLEFT")
	marker.edge:SetPoint("BOTTOMLEFT")
	W.Paint(marker.edge, "selectedTrim", "fill", 1)
	marker:SetPoint("TOPLEFT", rail.content, "TOPLEFT", 0, 0)
	marker:SetWidth(rail.width)
	marker:Hide()
	rail.marker = marker
	if skin and skin.OnKit then
		local set = railsOf[skin]
		if not set then
			set = setmetatable({}, weakKeys)
			railsOf[skin] = set
		end
		set[rail] = true
		skin:OnKit(Rails_OnKit)
		-- the active look on the marker, shown and gliding with it (0.15.0),
		-- where the rows carry no icon box of their own to wear it (the
		-- installer's steps; the configurator's side list lights the chosen
		-- entry's icon box instead, and its search results the marker:
		-- MarkerLook); made on the marker's first show
		rail.lookShell = skin
		rail.activeMarker = not (spec.iconSize > 0 and spec.iconMaker) or nil
		MarkerLook(rail)
	end
	return rail
end

function Rail:SetGroups(groups)
	local spec = self.spec
	-- (a search's results give the list back first: the groups are laid anew)
	if self.resultsShown then
		self:HideResults(true)
	end
	-- every row and header back to the pools, then taken again in order
	for key, row in pairs(self.rows) do
		row:Hide()
		W.RowPlateOff(row)
		self.rowPool[#self.rowPool + 1] = row
		self.rows[key] = nil
	end
	for key, h in pairs(self.headers) do
		h:Hide()
		self.headerPool[#self.headerPool + 1] = h
		self.headers[key] = nil
	end
	for i = #self.order, 1, -1 do
		self.order[i] = nil
	end
	for key in pairs(self.groupOf) do
		self.groupOf[key] = nil
	end
	local n = 0
	local right = spec.doneGlyph and -24 or -6
	for gi, g in ipairs(groups) do
		local gkey = g.key or gi
		if g.title then
			local h = table.remove(self.headerPool) or NewHeader(self)
			h.key, h.collapsible = gkey, g.collapsible
			h.text:SetText(g.title)
			h:EnableMouse(g.collapsible and true or false)
			h.glyph:SetShown(g.collapsible and true or false)
			self.headers[gkey] = h
			self.order[#self.order + 1] = h
		end
		local groupNew = false
		for _, e in ipairs(g.entries) do
			n = n + 1
			local row = table.remove(self.rowPool) or NewRow(self)
			row.key, row.entry, row.group = e.key, e, gkey
			row.text:SetText(spec.numbered and (n .. ". " .. e.text) or e.text)
			row.text:ClearAllPoints()
			local x = 8
			if spec.iconSize > 0 and e.icon then
				if not row.icon then
					-- made once per row: the window's icon maker (the
					-- configurator's IconBox with the Button Border rim) or a
					-- plain texture
					row.icon = spec.iconMaker and spec.iconMaker(row, spec.iconSize, spec.skin)
						or row:CreateTexture(nil, "ARTWORK")
					row.icon:SetSize(spec.iconSize, spec.iconSize)
					row.icon:SetPoint("LEFT", 8, 0)
					if row.icon.EnableMouse then
						row.icon:EnableMouse(false)
					end
				end
				local icon = row.icon
				if icon.SetIcon then
					icon:SetIcon(e.icon)
				else
					icon:SetTexture(e.icon)
				end
				icon:Show()
				x = 8 + spec.iconSize + 8
			elseif row.icon then
				row.icon:Hide()
			end
			row.text:SetPoint("LEFT", x, 0)
			-- a New tag at the right (snug, near the row's edge: the name
			-- keeps its room -- "UI Modifications" whole at the largest Font
			-- Style), the name cut before it only when it must be
			local tagged = Shows(e.new)
			if tagged and not row.newTag then
				row.newTag = W.Tag(row, W.NEW, true)
				row.newTag:SetPoint("RIGHT", row, "RIGHT", (spec.doneGlyph and right or -RAIL_TAG_IN) - TAG_SNUG_X, 0)
			end
			W.TagShown(row.newTag, tagged)
			if tagged then
				row.text:SetPoint("RIGHT", row.newTag.plate, "LEFT", -RAIL_TAG_GAP, 0)
				groupNew = true
			else
				row.text:SetPoint("RIGHT", right, 0)
			end
			local click = spec.clickable == nil or spec.clickable(self, e.key, e)
			row:EnableMouse(click and true or false)
			self.rows[e.key] = row
			self.groupOf[e.key] = gkey
			self.order[#self.order + 1] = row
		end
		local h = self.headers[gkey]
		if h then
			h.holdsNew = groupNew
			if groupNew and not h.newTag then
				h.newTag = W.Tag(h, W.NEW, true)
				h.newTag:SetPoint("RIGHT", h, "RIGHT", -(RAIL_TAG_IN + TAG_SNUG_X), 0)
				W.TagShown(h.newTag, false)
			end
		end
	end
	self:Layout(true)
	self:Paint()
end

-- the rows and headers from the top, the folded groups' rows hidden (coming
-- back they fade in, 0.12 s); the marker put on the selected row at once (a
-- fold is not a move). Each is held by ONE anchor, its top left, at the
-- content's width (the marker's glide moves that one anchor).
function Rail:Layout(instant)
	-- (while a search's results show, the groups stay hidden: HideResults
	-- lays them again)
	if self.resultsShown then
		return
	end
	local spec = self.spec
	local content = self.content
	local y = 0
	for _, f in ipairs(self.order) do
		local isRow = f.entry ~= nil
		if isRow and self.folded[f.group] then
			f:Hide()
		else
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
			f:SetWidth(self.width)
			if isRow and not f:IsShown() and not instant then
				MelloUI.Anim:FadeIn(f, 0.12)
			else
				f:Show()
			end
			f.y = y
			y = y + (isRow and spec.rowHeight or spec.headerHeight) + spec.gap
		end
	end
	content:SetHeight(math.max(y, 1))
	if not self.scroll then
		self.box:SetHeight(math.max(y, 1) + 2 * spec.inset + spec.head)
	end
	self:PlaceMarker(true)
end

-- the one marker on `row` (an entry's, or a search result's: its height),
-- gliding there unless `instant`; hidden when there is none on show
local function MarkRow(rail, row, height, instant)
	local marker = rail.marker
	local Anim = MelloUI.Anim
	if not (row and row:IsShown()) then
		Anim:Stop(marker)
		marker:Hide()
		return
	end
	if rail.markerHeight ~= height then
		rail.markerHeight = height
		marker:SetHeight(height)
	end
	local y = -row.y
	if instant or not marker:IsShown() then
		Anim:Stop(marker, "y")
		marker:ClearAllPoints()
		marker:SetPoint("TOPLEFT", rail.content, "TOPLEFT", 0, y)
		marker:Show()
	else
		Anim:To(marker, "y", y, 0.15, "outCubic")
	end
end

function Rail:PlaceMarker(instant)
	if self.resultsShown then
		MarkRow(self, self.resultIndex and self.resultRows[self.resultIndex], self.resultHeight, instant)
		return
	end
	MarkRow(self, self.selected and self.rows[self.selected], self.spec.rowHeight, instant)
end

-- the texts, icons, glyphs as the state is: gold on the selected entry, every
-- other one in the text colour; a module that is off shows it on its icon
-- (desaturated, 0.45); a done step its glyph; a folded group holding the
-- selected entry its header in gold
function Rail:Paint()
	local skin = self.spec.skin
	for key, row in pairs(self.rows) do
		local st = self.state[key]
		local selected = key == self.selected
		W.Paint(row.text, selected and "selectedTrim" or "text", "text")
		local icon = row.icon
		if icon then
			if icon.SetOn then
				icon:SetOn(st ~= "off")
			else
				icon:SetAlpha(st == "off" and 0.45 or 1)
			end
			if icon.SetSelected then
				icon:SetSelected(selected)
			end
		end
		if row.check then
			row.check:SetShown(st == "done")
		end
	end
	for gkey, h in pairs(self.headers) do
		local folded = self.folded[gkey] and true or false
		local holds = folded and self.selected ~= nil and self.groupOf[self.selected] == gkey
		W.Paint(h.text, (holds or not folded) and "selectedTrim" or "text", "text")
		-- a folded group holding a New entry: its tag on the header, the
		-- title cut before it (only when that changes)
		local tagShown = folded and h.holdsNew and true or false
		if h.newTag and h.tagShown ~= tagShown then
			h.tagShown = tagShown
			W.TagShown(h.newTag, tagShown)
			h.text:SetPoint("RIGHT", tagShown and h.newTag.plate or h, tagShown and "LEFT" or "RIGHT", tagShown and -RAIL_TAG_GAP or -6, 0)
		end
		h.glyph:SetTexture(folded and PLUS or MINUS)
		-- (the kit's glyphs only while its look is on: a switch off disabled them)
		local kitOpen = h.collapsible and skin and skin.kit and true or false
		RepShown(h.plusRep, kitOpen and folded)
		RepShown(h.minusRep, kitOpen and not folded)
	end
	if self.resultsShown then
		for i = 1, self.resultCount do
			local row = self.resultRows[i]
			W.Paint(row.label, i == self.resultIndex and "selectedTrim" or "text", "text")
		end
	end
end

function Rail:Select(key, instant)
	if key == self.selected then
		return
	end
	self.selected = key
	local row = key and self.rows[key]
	if row then
		W.RowPlateOff(row)
	end
	self:PlaceMarker(instant)
	self:Paint()
end

function Rail:SetState(key, state)
	if self.state[key] ~= state then
		self.state[key] = state
		self:Paint()
	end
end

function Rail:Fold(gkey, folded, instant)
	folded = folded and true or false
	if (self.folded[gkey] or false) == folded then
		return
	end
	self.folded[gkey] = folded or nil
	self:Layout(instant)
	self:Paint()
end

function Rail:Reveal(key)
	local row = self.rows[key]
	if not row then
		return nil
	end
	local gkey = self.groupOf[key]
	if self.folded[gkey] then
		self:Fold(gkey, false, true)
	end
	if self.glide and self.scroll then
		local top, height = row.y, self.scroll:GetHeight()
		local offset = self.glide.pos or 0
		if top < offset then
			self.glide:Jump(top)
		elseif top + self.spec.rowHeight > offset + height then
			self.glide:Jump(top + self.spec.rowHeight - height)
		end
	end
	return row
end

-- The search results' rows (see the NavRail header): two lines each -- the
-- small path over the name in full size, both in the text colour on the
-- list's inner panel (2e), the selected one's name in gold on the marker --
-- the palette's hover wash, a snug New tag at the right. A pool of their
-- own, each made whole the first time a search needs it: a keystroke after
-- makes no frame or region.
local RESULT_X, RESULT_PAD = 8, 5   -- the texts' inset and their room over and under
local RESULT_LINE_GAP = 6           -- between the two lines (10 and 12 high: the least height, 38)
local PATH_SEP = " > "              -- a path's parts (the caller's "Page > Tab")

-- A result row's height: the least (spec.resultHeight), or taller while its
-- two lines' fonts are (the Fonts module's sizes, up to 150 %: the path's
-- descenders never on the name's capitals), read from the pool's first row
-- (review of the search box, 2026-09-26). No table, no string: asked at each
-- search
local function ResultHeight(rail)
	local h = rail.spec.resultHeight
	local row = rail.resultRows[1]
	if row then
		local _, a = row.path:GetFont()
		local _, b = row.label:GetFont()
		a, b = Num(a), Num(b)
		if a and b then
			h = math.max(h, math.ceil(a + b + 2 * RESULT_PAD + RESULT_LINE_GAP))
		end
	end
	return h
end

-- The path as the row has room for it: whole when it fits, else its first
-- parts left out, so its end -- the tab, the parent: what tells two results
-- apart -- stays (review of the search box, 2026-09-26: "UI Modifications >
-- Combat > Y..." for three Icon Size rows). Measured once per entry for the
-- room and the font, the answer kept in the entry (`pathShown`, and what it
-- was measured for); a keystroke after measures nothing and makes no string.
local function FitPath(fs, e, room)
	local path = e.path
	local file, size = fs:GetFont()
	size = Num(size)
	if e.pathShown and e.pathRoom == room and e.pathSize == size and e.pathFont == file then
		return e.pathShown
	end
	local shown, at = path, 1
	fs:SetText(path)
	while (TextWidth(fs) or 0) > room do
		local _, stop = string.find(path, PATH_SEP, at, true)
		if not stop then
			break   -- (its last part alone and still too wide: cut at the row's edge)
		end
		at = stop + 1
		shown = path:sub(at)
		fs:SetText(shown)
	end
	e.pathShown, e.pathRoom, e.pathSize, e.pathFont = shown, room, size, file
	return shown
end

local function IsResultSelected(row)
	local rail = railOf[row]
	return rail ~= nil and rail.resultsShown and rail.resultIndex == row.index
end
-- (one options table for every result row's hover)
local RESULT_PLATE = { look = "palette", strength = 0.5, edge = false, selected = IsResultSelected }

local ResultClick = Shared("OnClick on a NavRail search result", function(row)
	local rail = railOf[row]
	if not (rail and rail.resultsShown and row.entry) then
		return
	end
	rail:SelectResult(row.index)
	if rail.spec.onResult then
		rail.spec.onResult(rail, row.entry)
	end
end, "script")

-- the result's tooltip: the whole of where it is (a path cut at the row's
-- edge too), the section it lies in, and what it does
local ResultTipEnter = Shared("OnEnter on a NavRail search result (tooltip)", function(row)
	local e = row.entry
	if e then
		W.ShowTooltip(row, e.full or e.name or "", e.tip, e.section)
	end
end, "script")

local function NewResultRow(rail, i)
	local row = CreateFrame("Button", nil, rail.content)
	row:SetHeight(rail.resultHeight)
	row.height = rail.resultHeight
	row:SetFrameLevel(rail.content:GetFrameLevel() + 1)
	row.path = W.Text(row, "GameFontHighlightSmall", nil, "text")
	row.path:SetWordWrap(false)
	row.label = W.Text(row, "GameFontHighlight", nil, "text")
	row.label:SetWordWrap(false)
	-- (its New tag made with it, shown when a result needs it: a keystroke
	-- makes no region either)
	row.newTag = W.Tag(row, W.NEW, true)
	row.newTag:SetPoint("RIGHT", row, "RIGHT", -(RAIL_TAG_IN + TAG_SNUG_X), 0)
	W.TagShown(row.newTag, false)
	W.RowPlate(row, RESULT_PLATE)
	Perf.HookScript(row, "OnEnter", ResultTipEnter)
	Perf.HookScript(row, "OnLeave", TipLeave)
	Perf.SetScript(row, "OnClick", ResultClick)
	row.index = i
	railOf[row] = rail
	rail.resultRows[i] = row
	return row
end

-- a result laid on its row at `y`: its texts (the caller's strings, the
-- path kept to its end when it is too wide: FitPath), its tag, the texts
-- ending before the tag, the row as tall as its fonts want (ResultHeight)
local function LayResult(rail, row, e, y)
	row.entry = e
	local path = e.path
	local hasPath = path ~= nil and path ~= ""
	local tagged = Shows(e.new)
	W.TagShown(row.newTag, tagged)
	local right = 6
	if tagged then
		right = RAIL_TAG_IN + (TextWidth(row.newTag) or 20) + 2 * TAG_SNUG_X + RAIL_TAG_GAP
	end
	row.path:SetText(hasPath and FitPath(row.path, e, rail.width - RESULT_X - right) or "")
	row.path:SetShown(hasPath)
	row.label:SetText(e.name or "")
	if row.height ~= rail.resultHeight then
		row.height = rail.resultHeight
		row:SetHeight(row.height)
	end
	row.path:ClearAllPoints()
	row.path:SetPoint("TOPLEFT", RESULT_X, -RESULT_PAD)
	row.path:SetPoint("TOPRIGHT", -right, -RESULT_PAD)
	row.label:ClearAllPoints()
	if hasPath then
		row.label:SetPoint("BOTTOMLEFT", RESULT_X, RESULT_PAD)
		row.label:SetPoint("BOTTOMRIGHT", -right, RESULT_PAD)
	else
		row.label:SetPoint("LEFT", RESULT_X, 0)
		row.label:SetPoint("RIGHT", -right, 0)
	end
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", rail.content, "TOPLEFT", 0, -y)
	row:SetWidth(rail.width)
	row.y = y
	row:Show()
end

local function PaintResult(rail, i)
	local row = i and rail.resultRows[i]
	if row then
		W.Paint(row.label, i == rail.resultIndex and "selectedTrim" or "text", "text")
	end
end

local function PutAway(row)
	row:Hide()
	row.entry = nil
	W.RowPlateOff(row)
end

-- New result rows keep to the frame's one budget of rows (W.RowBudget, as
-- the pages' rows): those the budget leaves are owed, made by the caller's
-- rail:MoreResults() on a later frame (the top ones first); the first
-- searches make the pool
local RESULT_BUDGET = 3   -- ms of new result rows in the frame of a keystroke

function Rail:ShowResults(list, n, note, more)
	local spec = self.spec
	if not self.resultsShown then
		-- the groups put away, their folds and the list's scroll kept for
		-- HideResults
		-- (a row still fading back in from a fold lands at its end: it comes
		-- back whole)
		local Anim = MelloUI.Anim
		for _, f in ipairs(self.order) do
			Anim:Land(f, "alpha")
			f:Hide()
		end
		self.listScroll = self.glide and self.glide.pos or 0
		self.resultsShown = true
		MarkerLook(self)
	end
	self.resultList, self.resultWanted, self.resultNote = list, n, note
	self.resultHeight = ResultHeight(self)
	local step = self.resultHeight + spec.gap
	local y, laid = 0, 0
	local deadline, begun = nil, false
	for i = 1, n do
		local row = self.resultRows[i]
		if not row then
			if not begun then
				begun = true
				deadline = W.RowBudget.Begin(RESULT_BUDGET)   -- (nil: this frame's rows are made)
			end
			if not (deadline and debugprofilestop() < deadline) then
				break
			end
			row = NewResultRow(self, i)
			if i == 1 then
				-- (the pool's first row: its fonts give the height from now on)
				self.resultHeight = ResultHeight(self)
				step = self.resultHeight + spec.gap
			end
		end
		LayResult(self, row, list[i], y)
		y = y + step
		laid = i
	end
	if begun then
		W.RowBudget.End()
	end
	for i = laid + 1, #self.resultRows do
		PutAway(self.resultRows[i])
	end
	self.resultsOwed = laid < n
	-- the quiet line under them, once they are all laid (full size:
	-- WINDOW-RULES 2e)
	local line = self.note
	if note and note ~= "" and not self.resultsOwed then
		if not line then
			line = W.Text(self.content, "GameFontHighlight", nil, "text")
			line:SetWordWrap(true)
			self.note = line
		end
		line:SetWidth(self.width - 2 * RESULT_X)
		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", self.content, "TOPLEFT", RESULT_X, -(y + 6))
		line:SetText(note)
		line:Show()
		y = y + 12 + (Num(line:GetStringHeight()) or 14)
	elseif line then
		line:Hide()
	end
	self.resultCount = laid
	if not more or not self.resultIndex then
		-- a new search: its first result selected, the list at its top
		self.resultIndex = laid > 0 and 1 or nil
	end
	self.content:SetHeight(math.max(y, 1))
	if self.glide and not more then
		self.glide:Jump(0)
	end
	self:PlaceMarker(not more)
	for i = 1, laid do
		PaintResult(self, i)
	end
	return self.resultsOwed
end

-- the rows a search still owes, laid now (within the frame's budget); true
-- while some are still owed after
function Rail:MoreResults()
	if self.resultsShown and self.resultsOwed then
		return self:ShowResults(self.resultList, self.resultWanted, self.resultNote, true)
	end
	return false
end

function Rail:HideResults(instant)
	if not self.resultsShown then
		return
	end
	self.resultsShown = false
	MarkerLook(self)
	for i = 1, #self.resultRows do
		PutAway(self.resultRows[i])
	end
	if self.note then
		self.note:Hide()
	end
	self.resultCount, self.resultIndex, self.resultsOwed, self.resultList = 0, nil, false, nil
	-- (the rows fade back in unless `instant`; the marker on the selected entry)
	self:Layout(instant)
	self:Paint()
	if self.glide then
		self.glide:Jump(self.listScroll or 0)
	end
end

function Rail:SelectResult(i)
	if not (self.resultsShown and i and i >= 1 and i <= self.resultCount) or i == self.resultIndex then
		return
	end
	local was = self.resultIndex
	self.resultIndex = i
	W.RowPlateOff(self.resultRows[i])   -- (no wash on the selected one)
	self:PlaceMarker(false)
	PaintResult(self, was)
	PaintResult(self, i)
end

function Rail:MoveResult(delta)
	if not (self.resultsShown and self.resultCount > 0) then
		return nil
	end
	local i = math.max(1, math.min(self.resultCount, (self.resultIndex or 0) + delta))
	self:SelectResult(i)
	local row = self.resultRows[i]
	if self.glide and self.scroll then
		-- (kept in view: the list glides by the least it must)
		local top, h = row.y, self.resultHeight
		local height = Num(self.scroll:GetHeight()) or 0
		local offset = self.glide.pos or 0
		if top < offset then
			self.glide:To(top)
		elseif height > 0 and top + h > offset + height then
			self.glide:To(top + h - height)
		end
	end
	return row.entry
end

function Rail:Result()
	local row = self.resultsShown and self.resultIndex and self.resultRows[self.resultIndex]
	return row and row.entry or nil
end

--------------------------------------------------------------------------------
-- Pager: one ScrollFrame whose scroll child is a CANVAS; pages are children
-- of the canvas held by one TOPLEFT point, so two can show at once in the
-- ScrollFrame's clip. A switch puts the new page at the top and cross-fades
-- to it (sliding in from the side `dir` says); a shield over the page area
-- takes the mouse until the new page is in.
--   local pager = W.Pager(parent, opts)
--   opts: step (80: the wheel), slide (12), outTime (0.10), inTime (0.15),
--         outInstant (true: the leaving page hides at once and only the new
--         one fades and slides; false: the leaving one fades out, pinned
--         where it is on screen -- the safe fallback is the default until
--         the clip test in game says otherwise), name,
--         template ("UIPanelScrollFrameTemplate": the classic scroll bar),
--         bleed (0: units the clip reaches past the pages' left and right
--         edges, the pages laid that far in: the caller anchors the scroll
--         frame that much wider. A chosen card's active look reaches its
--         halo past the card, and a card flush with the page's edge had it
--         cut off there; review 2026-09-28)
--   pager:NewPage() -> page       pager:Show(page, dir, instant)  dir -1 | 0 | 1
--   pager:SetPageHeight(page, h)  the canvas follows only the page on show
--   pager:AlphaOnly(page, on)     that page only fades, it never slides (a page
--                                 of many rows: a slide lays them all out
--                                 again every frame -- the fallback for
--                                 pages over 40 rows)
--   pager:Current()  pager:Offset()  pager:ScrollTo(offset, instant)
--   pager:Contains(region)        region is inside the current page
--   pager.scroll, pager.canvas, pager.glide, pager.shield, pager.cf (the
--   CrossFade options, one table: change its fields, never replace it)
-- The switch is instant under Reduce Motion, while the scroll frame is not
-- visible, or when asked.
--------------------------------------------------------------------------------

local Pager = {}
Pager.__index = Pager
local pagerOf = setmetatable({}, weakKeys)   -- [page] = its pager

-- (the CrossFade's end: the shield off once the page on show is in)
local function ShieldOff(page)
	local pager = pagerOf[page]
	if pager and pager.current == page then
		pager.shield:Hide()
	end
end

function W.Pager(parent, opts)
	opts = opts or {}
	local p = setmetatable({ current = nil, alphaOnly = setmetatable({}, weakKeys) }, Pager)
	local scroll = CreateFrame("ScrollFrame", opts.name, parent, opts.template)
	p.scroll = scroll
	p.canvas = CreateFrame("Frame", nil, scroll)
	p.canvas:SetSize(1, 1)
	scroll:SetScrollChild(p.canvas)
	p.glide = MelloUI.Anim:Glide(scroll, { step = opts.step or 80 })
	p.shield = CreateFrame("Frame", nil, scroll)
	p.shield:SetAllPoints(scroll)
	p.shield:SetFrameLevel(scroll:GetFrameLevel() + 50)
	p.shield:EnableMouse(true)
	p.shield:Hide()
	p.slide = opts.slide or 12
	p.bleed = opts.bleed or 0
	p.cf = { slide = 0, axis = "x", outTime = opts.outTime or 0.10, inTime = opts.inTime or 0.15,
		outInstant = opts.outInstant ~= false, onDone = ShieldOff, instant = false }
	return p
end

function Pager:NewPage()
	local page = CreateFrame("Frame", nil, self.canvas)
	page:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", self.bleed, 0)
	page:Hide()
	pagerOf[page] = self
	return page
end

function Pager:AlphaOnly(page, on)
	self.alphaOnly[page] = on and true or nil
end

local function Pin(page, canvas, y)
	local pager = pagerOf[page]
	page:ClearAllPoints()
	page:SetPoint("TOPLEFT", canvas, "TOPLEFT", pager and pager.bleed or 0, y)
end

function Pager:Show(page, dir, instant)
	local old = self.current
	if old == page then
		page:Show()
		return
	end
	local Anim = MelloUI.Anim
	instant = (instant or Anim.reduceMotion or not self.scroll:IsVisible()) and true or false
	if old then
		Anim:Land(old, "x")
		Pin(old, self.canvas, self.glide.pos or 0)   -- where it is on screen while it goes
	end
	self.current = page
	Pin(page, self.canvas, 0)
	self.canvas:SetWidth(page:GetWidth() + 2 * self.bleed)
	self.canvas:SetHeight(math.max(page:GetHeight(), 1))
	self.glide:Jump(0)
	local cf = self.cf
	cf.slide = self.alphaOnly[page] and 0 or (dir or 0) * self.slide
	cf.instant = instant
	if instant then
		self.shield:Hide()
	else
		self.shield:Show()
	end
	Anim:CrossFade(old, page, cf)
end

function Pager:Current()
	return self.current
end

function Pager:SetPageHeight(page, h)
	page:SetHeight(h)
	if page == self.current then
		self.canvas:SetHeight(math.max(h, 1))
	end
end

function Pager:Offset()
	return self.glide.pos or 0
end

function Pager:ScrollTo(offset, instant)
	if instant then
		self.glide:Jump(offset)
	else
		self.glide:To(offset)
	end
end

function Pager:Contains(region)
	local page = self.current
	local f = region
	for _ = 1, 40 do
		if not f or not page then
			return false
		end
		if f == page then
			return true
		end
		f = f.GetParent and f:GetParent() or nil
	end
	return false
end

--------------------------------------------------------------------------------
-- NumberBox (0.15.0, Edit Layout's right-click box: an element's X and Y): a
-- number to type, in the slider value box's look -- `innerPanel` in a 1 px
-- `border` edge, the text colour, centred. Like the slider's box it never
-- takes the keyboard by itself (only a click gives it the focus). Enter, Tab
-- or leaving it takes the number typed (its first number: "-320", "320 px";
-- the typographic minus too), kept in the range and rounded to the step, and
-- hands it to set when it changed; the box then shows the value as get()
-- gives it. Escape puts the value back and lets the focus go (the window
-- never sees that Escape); the box's hide does too.
--   W.NumberBox(parent, width, get, set, opts) -> box   an EditBox `width` x
--     20, sized and placed by the caller
--     opts: min, max (none: no limit), step (1), suffix (shown after the
--     number, never typed: " %"), format (fn(v) -> text, before the suffix)
--   box:Refresh()   get() again (left alone while it has the focus)
--   box.melloNext   an edit box Tab moves to after taking the number (the
--     caller's: Edit Layout's X -> Y -> Size)
--   box.melloGet / melloSet, box.fill, box.edges
-- Its handlers are shared (no closure per box); nothing runs while it is
-- left alone.
--------------------------------------------------------------------------------

do
	local BOX_H, BOX_INSET = 20, 3
	local BOX_FONT = "GameFontHighlight"
	local TYPO_MINUS = "\226\136\146"   -- (U+2212, the minus a readout shows)

	local function NumberText(box, v)
		local fmt = box.melloFormat
		local text
		if fmt then
			text = fmt(v)
		elseif math.abs(v - math.floor(v + 0.5)) < 0.001 then
			text = tostring(math.floor(v + 0.5))
		else
			text = string.format("%.2f", v)
		end
		return box.melloSuffix and (text .. box.melloSuffix) or text
	end

	-- the number typed, kept in the range and rounded to the step; nil for none
	local function Typed(box, text)
		text = tostring(text or ""):gsub(TYPO_MINUS, "-")
		local n = tonumber(text:match("%-?%d*%.?%d+"))
		if not n or n ~= n then
			return nil
		end
		n = W.Round(n, box.melloStep)
		if box.melloMin and n < box.melloMin then
			n = box.melloMin
		end
		if box.melloMax and n > box.melloMax then
			n = box.melloMax
		end
		return n
	end

	local function Show(box)
		local v = Num(box.melloGet())
		box:SetText(v and NumberText(box, v) or "")
	end

	-- the number taken (none: the value put back), the box showing the value
	-- after; `take` false: only put back
	local function LetGo(box, take)
		if take then
			local v = Typed(box, box:GetText())
			if v ~= nil and v ~= box.melloGet() then
				box.melloSet(v)
			end
		end
		Show(box)
		if box:HasFocus() then
			box.melloLetGo = true
			box:ClearFocus()
		end
	end

	local NumberEnter = Shared("OnEnterPressed on a number box", function(box)
		LetGo(box, true)
	end, "script")

	local NumberTab = Shared("OnTabPressed on a number box", function(box)
		LetGo(box, true)
		local nextBox = box.melloNext
		if nextBox and nextBox.SetFocus and nextBox:IsVisible() then
			nextBox:SetFocus()
		end
	end, "script")

	local NumberEscape = Shared("OnEscapePressed on a number box", function(box)
		LetGo(box, false)
	end, "script")

	local NumberFocusGained = Shared("OnEditFocusGained on a number box", function(box)
		box:HighlightText()
	end, "script")

	-- a click elsewhere: the number taken (Enter, Tab and Escape had their say)
	local NumberFocusLost = Shared("OnEditFocusLost on a number box", function(box)
		if box.melloLetGo then
			box.melloLetGo = nil
			return
		end
		LetGo(box, true)
	end, "script")

	local NumberHidden = Shared("OnHide on a number box", function(box)
		if box:HasFocus() then
			LetGo(box, false)
		end
	end, "script")

	local function NumberRefresh(box)
		if not box:HasFocus() then
			Show(box)
		end
	end

	function W.NumberBox(parent, width, get, set, opts)
		opts = opts or NO_OPTS
		local box = CreateFrame("EditBox", nil, parent)
		box:SetAutoFocus(false)
		box:SetSize(width or 60, BOX_H)
		box:SetFontObject(BOX_FONT)
		box:SetJustifyH("CENTER")
		box:SetTextInsets(BOX_INSET, BOX_INSET, 0, 0)
		box:EnableMouse(true)
		box:EnableMouseWheel(false)
		W.Paint(box, "text", "text")
		local fill = box:CreateTexture(nil, "BACKGROUND")
		fill:SetAllPoints(box)
		W.Paint(fill, "innerPanel", "fill", 1)
		box.fill, box.edges = fill, Edges(box, "border", "BORDER")
		box.melloGet, box.melloSet = get, set
		box.melloMin, box.melloMax = Num(opts.min), Num(opts.max)
		box.melloStep = Num(opts.step) or 1
		box.melloSuffix, box.melloFormat = opts.suffix, opts.format
		box.Refresh = NumberRefresh
		Perf.SetScript(box, "OnEnterPressed", NumberEnter)
		Perf.SetScript(box, "OnTabPressed", NumberTab)
		Perf.SetScript(box, "OnEscapePressed", NumberEscape)
		Perf.SetScript(box, "OnEditFocusGained", NumberFocusGained)
		Perf.SetScript(box, "OnEditFocusLost", NumberFocusLost)
		Perf.SetScript(box, "OnHide", NumberHidden)
		Show(box)
		return box
	end
end
