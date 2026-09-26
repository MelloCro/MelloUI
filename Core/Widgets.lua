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
--   W.Slider(parent, width, get, set, opts)
--   W.Button(parent, text, width, skin, opts)
--   W.CloseButton(parent, skin)
--   W.IconBox(parent, size, texture, skin)
--   W.RowPlate(row, opts)              W.RowPlateOff(row), W.RowPlateChild(row, child)
--   W.Row(parent, y, height, label, hint, desc, opts) and the typed rows
--     W.ToggleRow / SliderRow / DropdownRow / ButtonRow, W.Gate, W.ClipRow
--   W.Card(parent, spec, skin)         a choice card (the installer's setups)
--   W.Dress(root, skin, depth)         the kit's control sweep over a root
--   W.NavRail(parent, spec)            a side list / a steps rail
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
-- holds no numeric colour. Colours go only through W.Paint, sounds only
-- through MelloUI:PlayUISound, motion only through MelloUI.Anim (Reduce Motion
-- honoured by every helper). Kit and Fonts load after this file (the TOC):
-- nothing of theirs is bound here, everything is looked up when a builder
-- runs. Nothing is made at load but the shared handlers and weak tables.
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Widgets")
local Shared = Perf.Shared
local Secret = MelloUI.Safe.IsSecret   -- (Core.lua's, one set for the addon)

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
-- configurator's rows at 2, as a sweep of the page reaches them).
function W.Dress(root, skin, depth)
	if skin and root then
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

-- The text the box shows for `value` (nil when the list has no such entry:
-- the box then shows its default text, and the menu is made again on every
-- refresh, as before)
local function ChoiceLabel(values, value)
	if values then
		for i = 1, #values do
			local entry = values[i]
			if entry.value == value then
				return entry.label or tostring(entry.value)
			end
		end
	end
	return nil
end

-- the menu, made by the game when the box opens or GenerateMenu is called
local function DropdownMenu(dd, root)
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
end

-- the menu is made again only when it is out of date (user, 2026-09-24: a
-- tab's refresh made every dropdown's menu again, the font lists' dozens of
-- entries each time -- 19 ms and a heap of garbage per click on the Text
-- tab): the box not naming the choice, or the list filled again since the
-- menu was made (the Voice Over voices, listed once the game has them, in
-- the same table: the box must then name the chosen voice and the menu hold
-- them all)
local function DropdownRefresh(self)
	local values = self.melloValues
	local count, last = ListMark(values)
	if count == self.menuCount and last == self.menuLast then
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
	dd.melloGet, dd.melloSet, dd.melloValues = get, set, values
	dd.Refresh = DropdownRefresh
	dd:SetupMenu(DropdownMenu)
	dd.menuCount, dd.menuLast = ListMark(values)
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
		region = row:CreateTexture(nil, "BACKGROUND", nil, 1)
		region:SetTexture(WHITE)
		region:SetAllPoints()
		W.Paint(region, "hover", "vertex", 1)
		region:SetAlpha(0)
		strengthOf[row] = opts.strength or 0.5
		if opts.edge ~= false then
			local e = row:CreateTexture(nil, "BACKGROUND", nil, 2)
			e:SetTexture(WHITE)
			e:SetWidth(2)
			e:SetPoint("TOPLEFT")
			e:SetPoint("BOTTOMLEFT")
			W.Paint(e, "selectedTrim", "vertex", 1)
			e:SetAlpha(0)
			edgeOf[row] = e
		end
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
			row.hint:SetPoint("LEFT", row.label, "RIGHT", 10, 0)
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

-- The label and hint kept left of the control: the last of them ends 10 px
-- left of it (word wrap off: the game cuts it there), the full text in the
-- row's tooltip when cut
function W.ClipRow(row, control)
	local last = row.hint or row.label
	if not (last and control) then
		return
	end
	last:SetPoint("RIGHT", control, "LEFT", -10, 0)
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
	row.label:SetPoint("LEFT", 14 + (opts.indent or 0), 0)
	row.label:SetWordWrap(false)
	if hint and hint ~= "" then
		row.hint = W.Text(row, "GameFontHighlightSmall", hint, opts.hintKey or "text")
		row.hint:SetPoint("LEFT", row.label, "RIGHT", 10, 0)
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
-- the row's controls dressed by the kit's sweep
local function Finish(row, control, opts)
	controlOf[row] = control
	-- the control's frames that take the mouse keep the row's wash lit (a
	-- slider's are its bar and its two steppers)
	W.RowPlateChild(row, control)
	W.RowPlateChild(row, control.Slider)
	W.RowPlateChild(row, control.Back)
	W.RowPlateChild(row, control.Forward)
	if opts.clip ~= false then
		W.ClipRow(row, control)
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
	return Finish(row, switch, opts)
end

function W.SliderRow(parent, y, label, hint, desc, get, set, opts)
	opts = opts or NO_OPTS
	local row = W.Row(parent, y, W.SLIDER_ROW_HEIGHT, label, hint, desc, opts)
	local slider = W.Slider(row, opts.width or 200, get, set, opts)
	slider:SetPoint("RIGHT", -70, 0)
	return Finish(row, slider, opts)
end

-- (the dropdown's own options: its default text is the row's label)
local DROPDOWN_OPTS = {}

function W.DropdownRow(parent, y, label, hint, desc, get, set, values, opts)
	opts = opts or NO_OPTS
	local row = W.Row(parent, y, W.ROW_HEIGHT, label, hint, desc, opts)
	DROPDOWN_OPTS.default, DROPDOWN_OPTS.tooltip = label, nil
	local dd = W.Dropdown(row, opts.width or 200, get, set, values, DROPDOWN_OPTS)
	dd:SetPoint("RIGHT", -14, 0)
	return Finish(row, dd, opts)
end

-- (the button is dressed with the row, by the kit's sweep)
function W.ButtonRow(parent, y, label, hint, desc, text, onClick, opts)
	opts = opts or NO_OPTS
	local row = W.Row(parent, y, W.ROW_HEIGHT, label, hint, desc, opts)
	local button = W.Button(row, text or "Run", opts.width or 70, nil)
	button:SetPoint("RIGHT", -12, 0)
	if onClick then
		Perf.SetScript(button, "OnClick", onClick)
	end
	ControlTip(button, row, label, desc)
	row.button = button
	return Finish(row, button, opts)
end

--------------------------------------------------------------------------------
-- Card: one choice among a few, shown whole (the installer's four setups; the
-- Fresh start wizard's Kit Colours and Font Styles): a box with a title, a
-- line under it, a tag plate at its top right ("Recommended") and a picture
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
--         "tab" sound itself)
--   card:SetSelected(on)   card:IsSelected()   card:SetTexts(title, text)
--   card.title, card.text, card.picture, card.tag (the plate's FontString)
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
	card:SetSize(spec.width or 279, spec.height or 72)
	card.key, card.melloClick = spec.key, spec.onClick
	card.fill = card:CreateTexture(nil, "BACKGROUND", nil, 0)
	card.fill:SetAllPoints(card)
	card.edges = {}
	for i = 1, 4 do
		card.edges[i] = card:CreateTexture(nil, "BORDER")
	end
	local top = -10
	if spec.picture then
		local h = spec.pictureHeight or 40
		card.picture = card:CreateTexture(nil, "ARTWORK")
		card.picture:SetTexture(spec.picture)
		card.picture:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -8)
		card.picture:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
		card.picture:SetHeight(h)
		top = -8 - h - 6
	end
	card.title = W.Text(card, spec.titleFont or "GameFontNormal", spec.title)
	card.title:SetWordWrap(false)
	card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 12, top)
	if spec.tag then
		-- the plate: selectedTab behind a short gold word, laid on the word
		-- itself (no width to measure)
		card.tag = W.Text(card, "GameFontHighlightSmall", spec.tag, "selectedTrim")
		card.tag:SetWordWrap(false)
		card.tag:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, top - 1)
		local plate = card:CreateTexture(nil, "ARTWORK")
		plate:SetPoint("TOPLEFT", card.tag, "TOPLEFT", -6, 3)
		plate:SetPoint("BOTTOMRIGHT", card.tag, "BOTTOMRIGHT", 6, -3)
		W.Paint(plate, "selectedTab", "fill", 1)
		card.tagPlate = plate
		card.title:SetPoint("RIGHT", plate, "LEFT", -8, 0)
	else
		card.title:SetPoint("RIGHT", card, "RIGHT", -12, 0)
	end
	card.text = W.Text(card, spec.textFont or "GameFontHighlight", spec.text, "text")
	card.text:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -5)
	card.text:SetPoint("RIGHT", card, "RIGHT", -12, 0)
	card.text:SetWordWrap(true)
	card.SetSelected, card.IsSelected, card.SetTexts = Card_SetSelected, Card_IsSelected, Card_SetTexts
	W.RowPlate(card, CARD_PLATE)
	Perf.SetScript(card, "OnClick", CardClick)
	card:SetSelected(false)
	return card
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
--                            tip } } } }; rows and headers come from a pool
--                            (switching the installer's paths makes no frames)
--   rail:Select(key, instant)   the one marker glides there (0.15 s); the
--                               same key again does nothing
--   rail:SetState(key, state)   nil | "off" (icon dimmed, name kept in the
--                               text colour) | "done" (doneGlyph) | "todo"
--   rail:Fold(groupKey, folded, instant)
--   rail:Reveal(key)   unfolds its group and scrolls the row into view AT
--                      ONCE (a help tip's target); returns the row
--   rail.rows[key], rail.selected, rail.box, rail.content, rail.scroll,
--   rail.glide, rail.marker
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
	local rail = setmetatable({ spec = spec, rows = {}, headers = {}, order = {}, folded = {}, groupOf = {},
		state = {}, rowPool = {}, headerPool = {}, selected = nil }, Rail)
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
	if spec.scroll ~= false then
		local scroll = CreateFrame("ScrollFrame", nil, box)
		scroll:SetPoint("TOPLEFT", spec.inset, -spec.inset)
		scroll:SetPoint("BOTTOMRIGHT", -spec.inset, spec.inset)
		rail.content = CreateFrame("Frame", nil, scroll)
		rail.content:SetWidth(rail.width)
		scroll:SetScrollChild(rail.content)
		rail.scroll = scroll
		rail.glide = MelloUI.Anim:Glide(scroll, { step = 68 })
	else
		rail.content = CreateFrame("Frame", nil, box)
		rail.content:SetPoint("TOPLEFT", spec.inset, -spec.inset)
		rail.content:SetWidth(rail.width)
	end
	-- the one marker, at the content's level; the rows one above it, so their
	-- text draws over it
	local marker = CreateFrame("Frame", nil, rail.content)
	marker:SetFrameLevel(rail.content:GetFrameLevel())
	marker:SetHeight(spec.rowHeight)
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
			row.text:SetPoint("RIGHT", right, 0)
			local click = spec.clickable == nil or spec.clickable(self, e.key, e)
			row:EnableMouse(click and true or false)
			self.rows[e.key] = row
			self.groupOf[e.key] = gkey
			self.order[#self.order + 1] = row
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
		self.box:SetHeight(math.max(y, 1) + 2 * spec.inset)
	end
	self:PlaceMarker(true)
end

function Rail:PlaceMarker(instant)
	local marker = self.marker
	local row = self.selected and self.rows[self.selected]
	local Anim = MelloUI.Anim
	if not (row and row:IsShown()) then
		Anim:Stop(marker)
		marker:Hide()
		return
	end
	local y = -row.y
	if instant or not marker:IsShown() then
		Anim:Stop(marker, "y")
		marker:ClearAllPoints()
		marker:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, y)
		marker:Show()
	else
		Anim:To(marker, "y", y, 0.15, "outCubic")
	end
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
		h.glyph:SetTexture(folded and PLUS or MINUS)
		-- (the kit's glyphs only while its look is on: a switch off disabled them)
		local kitOpen = h.collapsible and skin and skin.kit and true or false
		RepShown(h.plusRep, kitOpen and folded)
		RepShown(h.minusRep, kitOpen and not folded)
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
