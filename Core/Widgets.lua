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
--   W.ShowTooltip(owner, title, body, line, anchor)   W.TipLeave (a shared OnLeave)
--   W.Switch(parent, get, set, opts)
--   W.Dropdown(parent, width, get, set, values, opts)
--   W.DropdownMenu(dd, get, set, values)   the one menu of MelloUI's dropdowns,
--                                      on a box made elsewhere (a long list
--                                      capped and scrolled)
--   W.Slider(parent, width, get, set, opts)
--   W.Button(parent, text, width, skin, opts)
--   W.CloseButton(parent, skin)
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
-- runs. Nothing is made at load but the shared handlers and weak tables.
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Widgets")
local Shared = Perf.Shared
local C_Timer = Perf.C_Timer   -- (a flash's hold: W.Flash)
local Secret = MelloUI.Safe.IsSecret   -- (Core.lua's, one set for the addon)
local Num = MelloUI.Safe.Number
local Finite = MelloUI.Safe.Finite

local W = {}
MelloUI.Widgets = W

local WHITE = "Interface\\Buttons\\WHITE8x8"
local TEXTURE_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Textures\\"
local ICON_FRAME = "UI-HUD-ActionBar-IconFrame"        -- the action button bevel
local ICON_MASK = "UI-HUD-ActionBar-IconFrame-Mask"    -- its rounded corners
local GLOW_ART = "Interface\\Buttons\\UI-ActionButton-Border"
local RIM_GROW = 1.1        -- the kit rim's rect: the icon box grown about its centre
local FADE_IN, FADE_OUT = 0.10, 0.12   -- a row's hover
local GATE_ALPHA = 0.4      -- a row that sleeps until a switch is on

-- the typed rows' heights (the configurator's ledger)
W.ROW_HEIGHT, W.SLIDER_ROW_HEIGHT = 34, 40

local weakKeys = { __mode = "k" }

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

function W.Paint(region, key, how, alpha)
	local Kit = MelloUI.Kit
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
local function Edges(frame, key, layer)
	local out = {}
	for i = 1, 4 do
		out[i] = frame:CreateTexture(nil, layer or "BORDER")
		W.Paint(out[i], key, "fill", 1)
	end
	out[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	out[1]:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, -1)
	out[2]:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 1)
	out[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	out[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	out[3]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 1, 0)
	out[4]:SetPoint("TOPLEFT", frame, "TOPRIGHT", -1, 0)
	out[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	return out
end
W.Edges = Edges

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
-- configurator's rows at 2, as a sweep of the page reaches them). The skin
-- is remembered for the root: a dropdown under it dresses its long list's
-- menu with the same look (MenuSkin, below).
local dressedBy = setmetatable({}, weakKeys)   -- [root] = the skin W.Dress dressed it with

function W.Dress(root, skin, depth)
	if skin and root then
		dressedBy[root] = skin
		skin:Kit(DressSweep, root, skin, depth)
	end
end

local function DressSwitch(K, cb, skin)
	K:SkinCheckButton(cb, skin.replace, "UI-CheckBox-Up")
end

local function DressButton(K, button, skin)
	K:SkinRedButton(button, skin.replace)
end

local function DressClose(K, close, skin)
	local normal = close.GetNormalTexture and close:GetNormalTexture()
	if normal then
		skin:Replace(normal, { as = "RedButton-Exit", button = close, alsoFade = K:OtherTextures(close, normal) })
	end
end

local function DressStepper(K, skin, button, key)
	local normal = button and button.GetNormalTexture and button:GetNormalTexture()
	if normal then
		skin:Replace(normal, { as = key, button = button, alsoFade = K:OtherTextures(button, normal) })
	end
end

-- SL1: the kit's slider track, thumb and steppers
local function DressSlider(K, slider, skin)
	local track = slider.Slider
	if not track then
		return
	end
	if track.Middle then
		-- the track at the kit piece's own thickness (fitted to the slider
		-- frame it came out as two fat stripes -- user, 2026-09-21)
		local layout = MelloUI_KitLayout and MelloUI_KitLayout.pieces and MelloUI_KitLayout.pieces["inputs/slider_mid"]
		local natural = layout and layout.box and (layout.box[4] - layout.box[2]) * K.scale or nil
		skin:Replace(track.Middle, { as = "_Minimal_SliderBar_Middle", rect = track, fitHeight = natural, alsoFade = { track.Left, track.Right } })
	end
	if track.Thumb then
		skin:Replace(track.Thumb, { as = "Minimal_SliderBar_Button", rect = track.Thumb, button = track })
	end
	DressStepper(K, skin, slider.Back, "Minimal_SliderBar_Button_Left")
	DressStepper(K, skin, slider.Forward, "Minimal_SliderBar_Button_Right")
end

--------------------------------------------------------------------------------
-- Switch: the game's check box, 26 px. SetValue(on, silent) sets it without
-- (silent) or with set(on); Refresh() takes get() again. A refresh that
-- changes nothing leaves the box alone (the kit's check box redraws on every
-- SetChecked; a tab's refresh set every box on it again -- user, 2026-09-24).
--   opts: skin
--------------------------------------------------------------------------------

local function SwitchSetValue(self, on, silent)
	on = on and true or false
	if silent and on == self.value and (self:GetChecked() and true or false) == on then
		return
	end
	self.value = on
	self:SetChecked(on)
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
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(26, 26)
	if cb.Text then
		cb.Text:Hide()
	end
	cb.value = false
	cb.melloGet, cb.melloSet = get, set
	cb.SetValue, cb.Refresh = SwitchSetValue, SwitchRefresh
	Perf.SetScript(cb, "OnClick", SwitchClick)
	local skin = opts and opts.skin
	if skin then
		skin:Kit(DressSwitch, cb, skin)
	end
	return cb
end

--------------------------------------------------------------------------------
-- Dropdown: the Settings panel look -- the text holder alone, gold text in
-- the middle, the text colour under the mouse. `values` is a list of
-- { value, label, tooltip }, read whenever the menu is made (a list filled
-- again in place is picked up).
--   opts: default (the text shown while the value has no entry), tooltip
--   (the box's own tooltip body; its title is `default`)
-- The kit dresses it through its control sweep (W.Dress of its row: the
-- typed row does it).
--   W.DropdownMenu(dd, get, set, values) -> dd
--     the menu W.Dropdown gives its box, on a DropdownButton made elsewhere
--     (Dynamic UI's boxes, in the game's own look): a radio per entry, made
--     again only when out of date (dd:Refresh(); dd:Refresh(true) at once,
--     a list whose names changed in place), a long list capped and scrolled
-- A long list (user, 2026-09-26: "the list does not have a slider option
-- and is way too big" -- the Fonts dropdown's sixty faces ran off the
-- screen) takes the game's own scroll mode (Blizzard_Menu: the root's
-- SetScrollMode(extent); past `extent` px of entries the menu shows that
-- much in its scroll box, with the game's MinimalScrollBar and mouse wheel):
-- at most MENU_ROWS entries and never taller than MENU_SCREEN of the screen
-- (the top-level parent's height in its own units: the menu takes that
-- parent's scale, so the UI scale is in both). A short list is left as it
-- was. The chosen entry is scrolled into view as the menu opens (the box's
-- OnMenuOpened, hooked on its first long list). The scroll bar wears THE
-- scroll bar's look (Kit:SkinScrollBar) while the box's window is in the
-- kit's look (the skin W.Dress remembered): the game pools its menu frames
-- and lends them to every menu, its own too, so the pieces are made once
-- per menu frame, on while our menu shows and off when it is released
-- (the root's menu-acquired and -released callbacks). Nothing is made
-- until a long list opens.
--------------------------------------------------------------------------------

local DropdownGold = Shared("OnButtonStateChanged / OnLeave on MelloUI's dropdowns", function(self)
	W.Paint(self.Text, "selectedTrim", "text")
end, "hook")
local DropdownLit = Shared("OnEnter on MelloUI's dropdowns", function(self)
	W.Paint(self.Text, "text", "text")
end, "script")
local DropdownTip = Shared("OnEnter on MelloUI's dropdowns (tooltip)", function(self)
	W.ShowTooltip(self, self.melloTipTitle or "", self.melloTip)
end, "script")

-- A dropdown's list as it stands: its length and its last entry (a list
-- filled again makes new entries, so either differs)
local function ListMark(values)
	local count = values and #values or 0
	return count, count > 0 and values[count] or nil
end

-- Where `value` stands in the list (nil when it has no such entry): its
-- radio's place in the menu too, one radio per entry
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

-- The text the box shows for `value` (nil when the list has no such entry:
-- the box then shows its default text, and the menu is made again on every
-- refresh, as before)
local function ChoiceLabel(values, value)
	local i = ChoiceIndex(values, value)
	if i then
		local entry = values[i]
		return entry.label or tostring(entry.value)
	end
	return nil
end

-- A long list's menu (the section's head). The game's menu, as the Forever
-- client's Blizzard_Menu lays it: a radio is a line 20 high (MenuVariants.
-- CreateRadio: its text set 20 high whatever the font, the tick centred on
-- it), and the menu adds its inset over and under the entries
-- (MenuStyle1Mixin:GetInset: 8 and 15).
local MENU_ROW_H = 20      -- a radio's line in the game's menu
local MENU_INSET = 23      -- the menu's inset over and under its entries
local MENU_ROWS = 18       -- a long list shows this many entries, and scrolls
local MENU_MIN_ROWS = 6    -- however small the screen
local MENU_SCREEN = 0.5    -- and the menu is never taller than this share of the screen

-- The scroll box's height for a list of `count` entries, nil for a list
-- short enough to show whole. The menu takes the top-level parent's scale
-- (Blizzard_Menu's AcquireMenu), so that parent's height in its own units
-- is the screen in the menu's.
local function MenuExtent(count)
	if count <= MENU_MIN_ROWS then
		return nil
	end
	local rows = MENU_ROWS
	local TopParent = _G.GetAppropriateTopLevelParent
	local top = TopParent and TopParent() or UIParent
	local height = top and Finite(top:GetHeight())
	if height then
		local fit = math.floor((height * MENU_SCREEN - MENU_INSET) / MENU_ROW_H)
		if fit < rows then
			rows = math.max(fit, MENU_MIN_ROWS)
		end
	end
	if count <= rows then
		return nil
	end
	return rows * MENU_ROW_H
end

-- The skin of the window a box is in: the one W.Dress dressed a root above
-- it with (nil: the plain look, or a box the kit never dresses)
local function MenuSkin(frame)
	for _ = 1, 12 do
		if not frame then
			return nil
		end
		local skin = dressedBy[frame]
		if skin then
			return skin
		end
		frame = frame.GetParent and frame:GetParent()
	end
	return nil
end

-- The menu frame's scroll bar in the kit's look: its pieces made once per
-- scroll bar (the game keeps its menu frames and lends them again), shown
-- while one of our long lists is open on it
local menuBars = setmetatable({}, weakKeys)    -- [the menu's ScrollBar] = its kit pieces (false: none to make)
local menuBarOn = setmetatable({}, weakKeys)   -- [ScrollBar] = true while they show
local menuKit = nil                             -- the kit, as skin:Kit hands it (MenuReplace's)

local function MenuReplace(region, opts)
	return menuKit:Replace(region, opts)
end

local function DressMenuBar(K, bar)
	local reps = menuBars[bar]
	if reps == nil then
		menuKit = K
		reps = K:SkinScrollBar(bar, MenuReplace) or false
		menuBars[bar] = reps
	end
	if reps and not menuBarOn[bar] then
		menuBarOn[bar] = true
		for i = 1, #reps do
			reps[i]:Enable()
		end
	end
end

-- the game's scroll bar again (for the next menu, whoever's it is)
local function MenuBarOff(bar)
	if menuBarOn[bar] then
		menuBarOn[bar] = nil
		local reps = menuBars[bar]
		for i = 1, #reps do
			reps[i]:Disable()
		end
	end
end

-- the root's callbacks: `menu` is the menu frame (its ScrollBox and
-- ScrollBar made once, with it), `menu:GetOwnerRegion()` the box
local MenuAcquired = Shared("a long list's menu acquired (its scroll bar's look)", function(menu)
	local bar = menu and menu.ScrollBar
	if not bar then
		return
	end
	local owner = menu.GetOwnerRegion and menu:GetOwnerRegion()
	local skin = owner and MenuSkin(owner)
	if skin and skin.kit then
		skin:Kit(DressMenuBar, bar)
	else
		MenuBarOff(bar)
	end
end)
local MenuReleased = Shared("a long list's menu released (the game's scroll bar back)", function(menu)
	local bar = menu and menu.ScrollBar
	if bar then
		MenuBarOff(bar)
	end
end)

-- the menu open and laid out: the chosen entry in view (the game opens a
-- scroll box at its top)
local DropdownOpened = Shared("OnMenuOpened on MelloUI's dropdowns (a long list's choice in view)", function(self, menu)
	local box = menu and menu.ScrollBox
	if not (box and box.ScrollToElementDataIndex and box:IsShown()) then
		return
	end
	local index = ChoiceIndex(self.melloValues, self.melloGet and self.melloGet())
	if index then
		local C = ScrollBoxConstants
		box:ScrollToElementDataIndex(index, C and C.AlignCenter, 0, true)
	end
end, "hook")

local scrollHooked = setmetatable({}, weakKeys)   -- [dd] = true: its OnMenuOpened brings the choice into view

-- a menu of `count` entries: the scroll mode when the list is long (the
-- root is made new each time the game makes the menu, so its callbacks go
-- with it)
local function LongMenu(dd, root, count)
	local extent = MenuExtent(count)
	if not (extent and root.SetScrollMode) then
		return
	end
	root:SetScrollMode(extent)
	if root.AddMenuAcquiredCallback and root.AddMenuReleasedCallback then
		root:AddMenuAcquiredCallback(MenuAcquired)
		root:AddMenuReleasedCallback(MenuReleased)
	end
	if not scrollHooked[dd] and dd.OnMenuOpened then
		scrollHooked[dd] = true
		Perf.hooksecurefunc(dd, "OnMenuOpened", DropdownOpened)
	end
end

-- the menu, made by the game when the box opens or GenerateMenu is called
local function DropdownEntries(dd, root)
	local values, get, set = dd.melloValues, dd.melloGet, dd.melloSet
	if not values then
		return
	end
	for _, entry in ipairs(values) do
		local value = entry.value
		local radio = root:CreateRadio(entry.label or tostring(value),
			function() return get() == value end,
			function() set(value) end,
			value)
		if entry.tooltip and radio and radio.SetTooltip then
			pcall(radio.SetTooltip, radio, function(tooltip)
				GameTooltip_SetTitle(tooltip, entry.label or tostring(value))
				GameTooltip_AddNormalLine(tooltip, entry.tooltip)
			end)
		end
	end
	LongMenu(dd, root, #values)
end

-- the menu is made again only when it is out of date (user, 2026-09-24: a
-- tab's refresh made every dropdown's menu again, the font lists' dozens of
-- entries each time -- 19 ms and a heap of garbage per click on the Text
-- tab): the box not naming the choice, or the list filled again since the
-- menu was made (the Voice Over voices, listed once the game has them, in
-- the same table: the box must then name the chosen voice and the menu hold
-- them all). `force`: made again at once (a list whose entries were renamed
-- in place: Dynamic UI's Kit Colours under a new palette)
local function DropdownRefresh(self, force)
	local values = self.melloValues
	local count, last = ListMark(values)
	if not force and count == self.menuCount and last == self.menuLast then
		local label = ChoiceLabel(values, self.melloGet())
		local text = self.Text
		if label and text and text:GetText() == label then
			return
		end
	end
	self.menuCount, self.menuLast = count, last
	if self.GenerateMenu then
		pcall(self.GenerateMenu, self)
	end
end

-- the one menu of MelloUI's dropdowns, on a box made by W.Dropdown or its
-- caller (the section's head)
function W.DropdownMenu(dd, get, set, values)
	dd.melloGet, dd.melloSet, dd.melloValues = get, set, values
	dd.Refresh = DropdownRefresh
	dd:SetupMenu(DropdownEntries)
	dd.menuCount, dd.menuLast = ListMark(values)
	return dd
end

function W.Dropdown(parent, width, get, set, values, opts)
	local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dd:SetWidth(width)
	dd:SetHeight(25)
	if dd.Arrow then
		dd.Arrow:Hide()
	end
	if dd.Text then
		dd.Text:ClearAllPoints()
		dd.Text:SetPoint("LEFT", 10, -1)
		dd.Text:SetPoint("RIGHT", -10, -1)
		dd.Text:SetJustifyH("CENTER")
		DropdownGold(dd)
		if dd.OnButtonStateChanged then
			Perf.hooksecurefunc(dd, "OnButtonStateChanged", DropdownGold)
		end
		Perf.HookScript(dd, "OnEnter", DropdownLit)
		Perf.HookScript(dd, "OnLeave", DropdownGold)
	end
	if dd.SetDefaultText and opts and opts.default then
		dd:SetDefaultText(opts.default)
	end
	W.DropdownMenu(dd, get, set, values)
	if opts and opts.tooltip then
		dd.melloTipTitle, dd.melloTip = opts.default, opts.tooltip
		Perf.HookScript(dd, "OnEnter", DropdownTip)
		Perf.HookScript(dd, "OnLeave", TipLeave)
	end
	return dd
end

--------------------------------------------------------------------------------
-- Slider: the game's minimal slider with steppers and the value on its
-- right; the kit's SL1 pieces with a skin.
--   opts: min (0), max (1), step (0.05), percent, format (fn(v) -> text),
--   skin
--------------------------------------------------------------------------------

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

-- (the slider's own callback: its owner, the slider, comes first)
local function SliderChanged(slider, value)
	if slider.refreshing then
		return
	end
	value = Round(value, slider.melloStep)
	if slider.melloGet() ~= value then
		slider.melloSet(value)
	end
end

local function SliderRefresh(self)
	self.refreshing = true
	self:SetValue(self.melloGet() or self.melloMin)
	self.refreshing = false
end

function W.Slider(parent, width, get, set, opts)
	opts = opts or {}
	local min, max, step = opts.min or 0, opts.max or 1, opts.step or 0.05
	local steps = math.max(1, math.floor((max - min) / step + 0.5))
	local slider = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
	slider:SetWidth(width)
	slider.melloGet, slider.melloSet, slider.melloMin, slider.melloStep = get, set, min, step
	slider:Init(get() or min, min, max, steps,
		{ [MinimalSliderWithSteppersMixin.Label.Right] = opts.format or (opts.percent and PercentText) or PlainText })
	if slider.Slider and slider.Slider.SetObeyStepOnDrag then
		slider.Slider:SetObeyStepOnDrag(true)
	end
	if slider.RightText then
		W.Paint(slider.RightText, "text", "text")
	end
	slider.refreshing = false
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, SliderChanged, slider)
	slider.Refresh = SliderRefresh
	local skin = opts.skin
	if skin then
		skin:Kit(DressSlider, slider, skin)
	end
	return slider
end

--------------------------------------------------------------------------------
-- Buttons: the game's panel button (the kit's red plate, B1, with a skin);
-- the close button (RedButton-Exit).
--   opts: height (22), onClick (a shared handler), gold (the Install look: a
--   `selectedTrim` label and a 1 px `selectedTrim` outline, by key)
--------------------------------------------------------------------------------

-- the gold label kept through the button's own font changes (normal /
-- highlight / disabled)
local GoldLabel = Shared("OnEnter / OnLeave / OnEnable / OnDisable on MelloUI's gold buttons", function(self)
	local fs = self.GetFontString and self:GetFontString()
	if fs then
		W.Paint(fs, "selectedTrim", "text")
	end
end, "script")

function W.Button(parent, text, width, skin, opts)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 110, opts and opts.height or 22)
	b:SetText(text or "")
	if opts and opts.onClick then
		Perf.SetScript(b, "OnClick", opts.onClick)
	end
	if skin then
		skin:Kit(DressButton, b, skin)
	end
	if opts and opts.gold then
		b.melloOutline = Edges(b, "selectedTrim", "OVERLAY")
		GoldLabel(b)
		Perf.HookScript(b, "OnEnter", GoldLabel)
		Perf.HookScript(b, "OnLeave", GoldLabel)
		Perf.HookScript(b, "OnEnable", GoldLabel)
		Perf.HookScript(b, "OnDisable", GoldLabel)
	end
	return b
end

function W.CloseButton(parent, skin)
	local close = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
	if skin then
		skin:Kit(DressClose, close, skin)
	end
	return close
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
-- box's: gold (checked) when selected, pressed, hover
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
	local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
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
--     opts.gate    fn() -> live, why: the row sleeps while not live (W.Gate)
--     opts.note    (true) while it sleeps, the hint slot reads "Switch on
--                  "why" first." (the row keeps its height)
--     opts.clip    (true, typed rows) the label and hint end 10 px left of
--                  the control, cut there, the full text in the tooltip
--     opts.new     the update the option came with: its New tag right after
--                  the label while that update runs (W.NewTag; the hint after
--                  the tag), dimmed with the row while it sleeps; a label with
--                  a tag and no hint keeps its text's width, cut only where
--                  the two would reach the control (row.newTag)
--   row:Refresh()  the row's control (get again) and its gate
-- The typed rows (a row and its control, which takes get / set; the row's
-- controls dressed by the kit's sweep with a skin):
--   W.ToggleRow(parent, y, label, hint, desc, get, set, opts) -> row, switch
--   W.SliderRow(parent, y, label, hint, desc, get, set, opts) -> row, slider
--     (opts.min, max, step, percent, format, width 200)
--   W.DropdownRow(parent, y, label, hint, desc, get, set, values, opts)
--     -> row, dropdown (opts.width 200; the label is its default text)
--   W.ButtonRow(parent, y, label, hint, desc, text, onClick, opts)
--     -> row, button (opts.width 70; onClick a shared handler)
--   W.ControlOf(row)   the typed row's control
--------------------------------------------------------------------------------

local controlOf = setmetatable({}, weakKeys)   -- [row] = its control
local gateOf = setmetatable({}, weakKeys)      -- [row] = its cover (W.Gate)

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

-- the cover's tooltip: the row's label, and the switch that wakes it
local CoverEnter = Shared("OnEnter on MelloUI's sleeping rows", function(self)
	local _, why = self.gate()
	local row = self.gateRow
	W.ShowTooltip(self, row.label and row.label:GetText() or "", why and GateLine(self, why) or nil)
end, "script")

local function GateRefresh(cover)
	local live, why = cover.gate()
	local row = cover.gateRow
	row:SetAlpha(live and 1 or GATE_ALPHA)
	cover:SetShown(not live)
	local hint = cover.note and row.hint
	if hint then
		local text = (not live and why) and GateLine(cover, why) or cover.hintText
		hint:SetText(text or "")
		hint:SetShown(text ~= nil and text ~= "")
	end
end

-- A row that only means something while a switch is on (user, 2026-09-24:
-- "people will get overwhelmed by all the options"): `gate()` returns whether
-- it is live and, when not, the switch to turn on. Off, the row is dimmed and
-- a cover over it takes the clicks and says which switch wakes it.
--   opts.note (true): the hint slot reads that line while it sleeps
function W.Gate(row, gate, opts)
	local cover = CreateFrame("Frame", nil, row)
	cover:SetAllPoints(row)
	cover:SetFrameLevel(row:GetFrameLevel() + 30)
	cover:EnableMouse(true)
	cover.gate, cover.gateRow = gate, row
	Perf.SetScript(cover, "OnEnter", CoverEnter)
	Perf.SetScript(cover, "OnLeave", TipLeave)
	W.RowPlateChild(row, cover)
	cover:Hide()
	cover.Refresh = GateRefresh
	if not (opts and opts.note == false) then
		cover.note = true
		if not row.hint then
			row.hint = W.Text(row, "GameFontHighlightSmall", nil, "text")
			row.hint:SetPoint("LEFT", row.newTag or row.label, "RIGHT", row.newTag and (10 + TAG_PAD_X) or 10, 0)
			row.hint:SetWordWrap(false)
			local control = controlOf[row]
			if clipped[row] and control then
				row.hint:SetPoint("RIGHT", control, "LEFT", -10, 0)
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
-- row's tooltip when cut; a label with a New tag and no hint: FitLabel
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
	clipped[row] = true
	if not row.tipTitle then
		row.tipTitle = row.label and row.label:GetText() or ""
		Perf.HookScript(row, "OnEnter", RowTipEnter)
		Perf.HookScript(row, "OnLeave", TipLeave)
	end
end

local PLATE_OPTS = {}   -- a row's RowPlate options (one table, filled per row)
local NO_OPTS = {}

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

-- a typed row's control in place: known to the row, the texts cut at it,
-- the row's controls dressed by the kit's sweep. `span`: the control's left
-- edge from the row's right one (where a New tag's label may end: ClipRow)
local function Finish(row, control, opts, span)
	controlOf[row] = control
	-- the control's frames that take the mouse keep the row's wash lit (a
	-- slider's are its bar and its two steppers)
	W.RowPlateChild(row, control)
	W.RowPlateChild(row, control.Slider)
	W.RowPlateChild(row, control.Back)
	W.RowPlateChild(row, control.Forward)
	if opts.clip ~= false then
		W.ClipRow(row, control, span)
	end
	W.Dress(row, opts.skin, 2)
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

function W.SliderRow(parent, y, label, hint, desc, get, set, opts)
	opts = opts or NO_OPTS
	local row = W.Row(parent, y, W.SLIDER_ROW_HEIGHT, label, hint, desc, opts)
	local width = opts.width or 200
	local slider = W.Slider(row, width, get, set, opts)
	slider:SetPoint("RIGHT", -70, 0)
	return Finish(row, slider, opts, 70 + width)
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

-- (the button is dressed with the row, by the kit's sweep)
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
-- W.RowPlateChild(card, frame). `skin` keeps the widget set's signature: the
-- approved card is the palette look in both looks, so the kit dresses none of
-- it. Colours by key only (a new palette paints it again); nothing is made
-- per click or hover.
--------------------------------------------------------------------------------

local cardOn = setmetatable({}, weakKeys)   -- [card] = true while it is the selected one

local function CardSelected(card)
	return cardOn[card] == true
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
	CardEdges(card, on and 2 or 1)
	for i = 1, 4 do
		W.Paint(card.edges[i], on and "selectedTrim" or "border", "fill", 1)
	end
	W.Paint(card.title, on and "selectedTrim" or "text", "text")
	if on then
		W.RowPlateOff(card)   -- (just picked: its wash goes at once)
	end
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
	card:SetSelected(false)
	return card
end

--------------------------------------------------------------------------------
-- Palettes (0.14.0, user 2026-09-26: "A palette picker"): ONE set of parts
-- for every place a palette is chosen -- the configurator's Home row, the
-- installer's Look step, Dynamic UI's row -- over Core's registry
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
--         as tall as its rows), box (true: the box -- the kit's L1 with a
--         skin whose kit is on, else a palette `innerPanel` box with a
--         `border` edge), skin, iconMaker (fn(row, size, skin) -> an icon
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

-- the rails of each shell, their glyphs and states put back at its switches
local railsOf = setmetatable({}, weakKeys)   -- [shell] = { [rail] = true } (weak)
local function Rails_OnKit(shell)
	local set = railsOf[shell]
	if set then
		for rail in pairs(set) do
			rail:Paint()
		end
	end
end

-- the kit's look of the rail's parts (through skin:Kit)
local function DressRailBox(K, rail, skin)
	skin:Replace(skin:Anchor(rail.box, "BACKGROUND"), { as = "Professions-background-summarylist", rect = rail.box,
		parent = rail.box, level = -1 })
end

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
		local fill = box:CreateTexture(nil, "BACKGROUND")
		fill:SetAllPoints(box)
		W.Paint(fill, "innerPanel", "fill", 1)
		rail.plainParts = Edges(box, "border", "BORDER")
		rail.plainParts[5] = fill
		if skin then
			for i = 1, #rail.plainParts do
				skin:Plain(rail.plainParts[i])
			end
			skin:Kit(DressRailBox, rail, skin)
		end
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
--         template ("UIPanelScrollFrameTemplate": the classic scroll bar)
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
	p.cf = { slide = 0, axis = "x", outTime = opts.outTime or 0.10, inTime = opts.inTime or 0.15,
		outInstant = opts.outInstant ~= false, onDone = ShieldOff, instant = false }
	return p
end

function Pager:NewPage()
	local page = CreateFrame("Frame", nil, self.canvas)
	page:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", 0, 0)
	page:Hide()
	pagerOf[page] = self
	return page
end

function Pager:AlphaOnly(page, on)
	self.alphaOnly[page] = on and true or nil
end

local function Pin(page, canvas, y)
	page:ClearAllPoints()
	page:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, y)
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
	self.canvas:SetWidth(page:GetWidth())
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
