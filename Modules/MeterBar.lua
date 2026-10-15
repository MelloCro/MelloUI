--------------------------------------------------------------------------------
-- MelloUI - Damage Meter: the race bar (0.17.0)
--
-- One bar for the group in a fight (the user's drawing, 2026-10-01;
-- MelloUI-BuildData/output/meter_sketch/race_bar.jpg, "pins as class
-- medallions"): the right end is the top player (100%), their value above
-- it ("41.8 dps"); everyone else a class medallion pin under the bar at their
-- share of the top, labelled 2nd, 3rd...; you the bigger gold-ringed pin,
-- the bar filled up to you. Crowded pins keep the pin and drop the label
-- (yours always shows); the pointer on the bar lists everyone in order.
-- It fades in when a fight starts and out ~1.5 s after it ends (MelloUI.Anim;
-- Reduce Motion: at once). Healing instead of damage for a healer (Race Bar
-- Shows: Auto, by the group role) or by the setting.
-- Secret-safe by the engine: each pin is an invisible StatusBar on the
-- track's rect, the pin hung on its fill's right edge, so the game places it
-- from the secret amounts (SetMinMaxValues(0, the top's) / SetValue); the
-- values go to SetText through Meter.Format; the list's order gives the
-- ranks and classFilename / isLocalPlayer are never secret.
-- Its place: MelloUI's one mover (key "meterbar", "Race Bar"; Edit Layout
-- shows it with sample pins on its plate; its box has the Width and
-- Thickness sliders, shortcuts to the configurator's Race Bar Width /
-- Thickness). Built with the first fight, or Edit Layout's first open while
-- it is on.
-- Its look (onelook stage B, the user's pick B "Rail", 2026-10-15;
-- docs/plans/onelook-b-sketches/meter.md, meter_looks.jpg): one slim rail
-- (2 units, the palette's border) on the track's middle, your share on it in
-- your class colour (the status bars' Bar Texture, else MelloUI's Minimalist;
-- Race Bar Thickness tall); each pin a W.RoundIcon in the kit's round rim,
-- the plain class medallion inside, centred on its fill's right end (20,
-- yours 24); the labels under them; the caption in the title face over the
-- left end, the top's value over the right; the whole group on one soft text
-- band (MelloUI.Shade.TEXT), every text with that look's soft shadow (the
-- notice rule). The holder is 56 tall (76 before), still placed by its
-- bottom. The modern look is its only look: Oldschool does not dress it (the
-- user's decision 8: no cover branch for MelloUI's own HUD parts; the kit's
-- 'TooltipStatusBar' bracket is gone). The caption says "Current DPS" (or
-- HPS).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("MeterBar")
local C_Timer = Perf.C_Timer
local Shared = Perf.Shared
local Safe = MelloUI.Safe
local Num, Text, Secret = Safe.Number, Safe.Text, Safe.IsSecret
local W = MelloUI.Widgets
-- (0.17.1, docs/plans/game-look.md) the look of MelloUI's own parts: the
-- palette's (one look since onelook stage E)
local Look = MelloUI.Look
local Meter = ns.Meter
local M = Meter.M
local pcall, ipairs, min = pcall, ipairs, math.min

local WHITE = "Interface\\Buttons\\WHITE8x8"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local MOVER_KEY = "meterbar"

-- (onelook B "Rail") ABOVE: the holder's top to the rail's middle; BELOW: the
-- rail's middle to the holder's bottom (56 in all, 76 before); THICK: Race
-- Bar Thickness's default and range; RAIL: the rail line; PIN / ME_PIN: the
-- rims; GAP: the caption's line over the rims; ICON_IN: the plain
-- medallion's own bronze ring cut off inside the kit's rim; BAND_Y: the soft
-- band's fade above and below the group; HOME_Y: the holder's bottom over
-- the screen's (325: the rail's middle 26 over it lies where the old
-- 76-tall holder's track middle lay, 51 over a bottom at 300)
local B = {
	WIDTH = 260, THICK = 4, THICK_MIN = 2, THICK_MAX = 8, RAIL = 2, PIN = 20, ME_PIN = 24, GAP = 4,
	ABOVE = 30, BELOW = 26, ICON_IN = 0.09, BAND_Y = 10,
	LABEL = 10, ME_LABEL = 12, TOP = 13, CAPTION = 11,
	FADE_IN = 0.6, FADE_OUT = 1.2, OUT_DELAY = 1.5,
	LIST_ROW = 16, LIST_W = 220, LIST_MAX = 10,
	HOME_Y = 325,
}

local TEXT = {
	caption = "Current DPS",
	captionHeal = "Current HPS",
	dps = "dps",
	hps = "hps",
	label = "Race Bar",
}

local Bar = { ui = nil, shown = false, samples = false, healing = false, list = nil }
Meter.Bar = Bar

local function On()
	return M.isEnabled and M.db and M.db.bar ~= false or false
end

local function Pins()
	local n = Num(M.db and M.db.pins) or Meter.T.PINS
	return math.max(Meter.T.PINS_MIN, math.min(Meter.T.PINS_MAX, math.floor(n)))
end

-- healing for this fight: the setting, or Auto by your group role
local function Healing()
	local metric = M.db and M.db.metric or "auto"
	if metric == "hps" then
		return true
	elseif metric == "dps" then
		return false
	end
	local ok, role = pcall(_G.UnitGroupRolesAssigned, "player")
	return ok and Text(role) == "HEALER" or false
end


-- the bar's size: Race Bar Width and Thickness (its track: your share's
-- height on the rail; the holder adds the caption above and the pins under
-- it). (onelook B, 2026-10-15: Thickness, railHeight, took Height's place; a
-- saved barHeight is not read, and a thickness out of the slider's range is
-- kept inside it)
local function Size()
	local db = M.db
	local w = Num(db and db.barWidth) or B.WIDTH
	local h = Num(db and db.railHeight) or B.THICK
	h = math.max(B.THICK_MIN, math.min(B.THICK_MAX, h))
	return math.floor(w + 0.5), math.floor(h + 0.5)
end

-- the fill's texture: the status bars' Bar Texture, else MelloUI's Minimalist (W.BarFill)
local FillTexture = W.BarFill

local function Home(holder)
	holder:ClearAllPoints()
	holder:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, B.HOME_Y)
end

-- a string in its class's colour (its role's own colour without one): one
-- colour table a string, set again in place (Look.Colour)
local classColours = setmetatable({}, { __mode = "k" })
local function ClassColour(fs, class)
	local QI = MelloUI.QuestInk
	local r, g, b
	if QI and QI.ClassColour then
		r, g, b = QI.ClassColour(class)
	end
	if r then
		local c = classColours[fs] or {}
		classColours[fs] = c
		c[1], c[2], c[3] = r, g, b
		Look.Colour(fs, c)
	else
		Look.Colour(fs, nil)
	end
end

--------------------------------------------------------------------------------
-- The bar's parts
--------------------------------------------------------------------------------

-- the text look's soft shadow on one of the bar's texts (MelloUI.Shade.TEXT:
-- the palette's innerPanel at 0.85, one unit right and down; the notice
-- rule, as the centre texts): at the bar's dressing and at a new palette
-- (Bar.Look), and on a pin's label again after its class colour (Look.Colour
-- lays its font again)
local function TextShadow(fs)
	local look = MelloUI.Shade.TEXT
	fs:SetShadowOffset(look.shadowX, look.shadowY)
	Look.Shadow(fs, look.shadow)
end

-- your class's colour (your share's), or nil while it cannot be read
local function PlayerColour()
	local QI = MelloUI.QuestInk
	local ok, _, class = pcall(_G.UnitClass, "player")
	if ok and QI and QI.ClassColour and not Secret(class) then
		return QI.ClassColour(class)
	end
	return nil
end

-- (a rim's whole-UI shade partner: the unit frames' area's, as the Reminders'
-- round buttons beside the portrait)
local PIN_OPTS = { shade = "unitframes" }

local function NewPin(ui, mine)
	local holder, track = ui.holder, ui.track
	local bar = CreateFrame("StatusBar", nil, holder)
	bar:SetAllPoints(track)
	bar:SetStatusBarTexture(WHITE)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	local fill = bar:GetStatusBarTexture()
	if fill then
		fill:SetAlpha(0)
	end
	bar:EnableMouse(false)
	local pin = { bar = bar, mine = mine }
	-- the medallion: a W.RoundIcon in the kit's round rim (yours the bigger),
	-- the class's plain medallion inside it with its own bronze ring cut off,
	-- centred on the fill's right end: anchors only, so the game places it
	-- from the secret amount
	local face = W.RoundIcon(holder, mine and B.ME_PIN or B.PIN, UNKNOWN_ICON, PIN_OPTS)
	face:SetKit(MelloUI.Kit)
	-- (the pointer stays the holder's: its list. W.RoundIcon's SetKit keeps
	-- a mouse turned off through the kit rim's mouse hooks, in either order)
	face:EnableMouse(false)
	face.icon:SetTexCoord(B.ICON_IN, 1 - B.ICON_IN, B.ICON_IN, 1 - B.ICON_IN)
	face:SetPoint("CENTER", fill or bar, "RIGHT", 0, 0)
	-- over the rail and your share (the track's StatusBar); yours over the others
	face:SetFrameLevel(ui.fill:GetFrameLevel() + (mine and 2 or 1))
	pin.face, pin.icon = face, face.icon
	local label = holder:CreateFontString(nil, "OVERLAY")
	Look.Text(label, mine and "value" or "text", mine and B.ME_LABEL or B.LABEL)
	TextShadow(label)
	label:SetPoint("TOP", face, "BOTTOM", 0, -1)
	pin.label = label
	return pin
end

-- (set only when it changes: a rim's show hooks run when it comes or goes,
-- not at every lay)
local function SetPinShown(pin, on)
	pin.bar:SetShown(on)
	pin.face:SetShown(on)
	pin.icon:SetShown(on)
	pin.label:SetShown(on)
end

-- a pin's picture: its class's plain medallion (no diamonds: the kit's rim
-- is its ring), set when its class changes
local function Medallion(pin, class)
	class = Text(class)
	if pin.classSet and pin.class == class then
		return
	end
	pin.class, pin.classSet = class, true
	local path = class and MelloUI.ClassIconPath and MelloUI:ClassIconPath(class, "plain")
	pin.face:SetIcon(path or UNKNOWN_ICON)
end

local ListShow, ListHide   -- (below)

local function Build()
	if Bar.ui then
		return Bar.ui
	end
	local holder = CreateFrame("Frame", "MelloUIMeterBar", UIParent)
	holder:SetSize(B.WIDTH, B.ABOVE + B.BELOW)   -- (the settings' width: Bar.Resize, below)
	holder:SetFrameStrata("MEDIUM")
	holder:SetClampedToScreen(true)
	holder:SetAlpha(0)
	holder:Hide()
	Home(holder)
	local ui = { holder = holder, pins = {} }
	Bar.ui = ui
	-- the caption and the top value: one line, GAP over the rims (the caption
	-- in the title face over the left end, the value over the right)
	local lineY = -(B.ABOVE - B.ME_PIN / 2 - B.GAP)
	local caption = W.Text(holder, "GameFontNormal", TEXT.caption, "text")
	caption:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", 0, lineY)
	if MelloUI.Kit and MelloUI.Kit.TitleFont then
		MelloUI.Kit:TitleFont(caption, true)
	end
	ui.caption = caption
	local unit = holder:CreateFontString(nil, "OVERLAY")
	Look.Text(unit, "value", B.CAPTION)
	unit:SetPoint("BOTTOMRIGHT", holder, "TOPRIGHT", 0, lineY)
	ui.unit = unit
	local top = holder:CreateFontString(nil, "OVERLAY")
	Look.Text(top, "value", B.TOP)
	top:SetPoint("BOTTOMRIGHT", unit, "BOTTOMLEFT", -3, 0)
	ui.top = top
	-- the track: on the rail's middle line, as tall as your share (Race Bar
	-- Thickness); the rail across it, your share over the rail (Bar.Look)
	local track = CreateFrame("Frame", nil, holder)
	track:SetPoint("LEFT", holder, "TOPLEFT", 0, -B.ABOVE)
	track:SetPoint("RIGHT", holder, "TOPRIGHT", 0, -B.ABOVE)
	track:SetHeight(B.THICK)
	ui.track = track
	local rail = W.Solid(track, "BACKGROUND", "border", 1)
	rail:SetPoint("LEFT", track, "LEFT", 0, 0)
	rail:SetPoint("RIGHT", track, "RIGHT", 0, 0)
	rail:SetHeight(B.RAIL)
	ui.rail = rail
	local fill = CreateFrame("StatusBar", nil, track)
	fill:SetAllPoints(track)
	fill:SetMinMaxValues(0, 1)
	fill:SetValue(0)
	ui.fill = fill
	-- the whole group on one soft band in the text look (its middle the
	-- holder grown by the look's padX at each side, faded BAND_Y above and
	-- below: a block of lines, Shade:Band's featherY)
	local Shade = MelloUI.Shade
	local look = Shade.TEXT
	ui.band = Shade:Band(holder, { colour = look.colour, alpha = look.alpha, feather = look.feather, layer = look.layer,   -- look-ok: the one look's band (onelook B "Rail"; no game twin since stage C)
		featherY = B.BAND_Y })
	if ui.band then
		ui.band:Anchor(holder, look.padX, 0)
	end
	-- the pins: the others, then yours over them
	for i = 1, Meter.T.PINS_MAX - 1 do
		ui.pins[i] = NewPin(ui, false)
		SetPinShown(ui.pins[i], false)
	end
	ui.me = NewPin(ui, true)
	SetPinShown(ui.me, false)
	ui.me.label:SetText(Meter.TEXT.you)
	-- the pointer on it: everyone in order
	holder:EnableMouse(true)
	Perf.SetScript(holder, "OnEnter", ListShow)
	Perf.SetScript(holder, "OnLeave", ListHide)
	-- its place: the one mover (its box: Width and Thickness, the
	-- configurator's own settings)
	ui.entry = MelloUI:RegisterMover(holder, holder, { key = MOVER_KEY, default = Home, min = 0.5, max = 2, base = 1,
		label = TEXT.label, page = "BarsMeters", when = On, settings = { "Meter.barWidth", "Meter.railHeight" } })
	if not MelloUI:RestorePosition(MOVER_KEY, holder) then
		Home(holder)
	end
	Bar.Resize()
	Bar.Look()
	return ui
end

-- the size from the settings (the holder's height is the rims' and texts':
-- Thickness stays inside it)
function Bar.Resize()
	local ui = Bar.ui
	if not ui then
		return
	end
	local w, h = Size()
	ui.holder:SetSize(w, B.ABOVE + B.BELOW)
	ui.track:SetHeight(h)
end

-- the look (onelook B "Rail", 2026-10-15: MelloUI's one look for it, whatever
-- the reskin; Oldschool does not dress it): your share in the status bars'
-- Bar Texture, in your class colour (the palette's selectedTrim while your
-- class cannot be read); every text's soft shadow. Laid at the build, at a
-- new Bar Texture and at a new palette; a pin's label is laid again by its
-- class colour, so Lay shades it again there.
function Bar.Look()
	local ui = Bar.ui
	if not ui then
		return
	end
	local fill, Kit = ui.fill, MelloUI.Kit
	fill:SetStatusBarTexture(FillTexture())
	local tex = fill:GetStatusBarTexture()
	if tex then
		local r, g, b = PlayerColour()
		if r then
			if Kit and Kit.Unpaint then
				Kit:Unpaint(tex, "vertex")   -- (out of the palette's repaint: a meaning colour)
			end
			tex:SetVertexColor(r, g, b, 1)
		else
			W.Paint(tex, "selectedTrim", "vertex")
		end
	end
	TextShadow(ui.caption)
	TextShadow(ui.unit)
	TextShadow(ui.top)
	for _, pin in ipairs(ui.pins) do
		TextShadow(pin.label)
	end
	TextShadow(ui.me.label)
end

--------------------------------------------------------------------------------
-- The pins laid from a list of sources (the game's live ones, secret in a
-- fight, or Edit Layout's plain samples)
--------------------------------------------------------------------------------

-- the labels: a crowded pin drops its label, yours always shows (by the
-- pins' places when they read plainly; in a fight they read secret: then the
-- 1st's and yours only, once more than four pins show)
local rects = {}
local function Declutter(ui, shown)
	local plain = true
	for i = 1, #shown do
		local l, _, r = Safe.ScreenRect(shown[i].icon)
		if not l then
			plain = false
			break
		end
		rects[i] = rects[i] or {}
		rects[i][1], rects[i][2] = l, r
	end
	if not plain then
		for i = 1, #shown do
			local pin = shown[i]
			pin.label:SetShown(pin.mine or #shown <= 4 or i == 1)
		end
		return
	end
	-- (best first: a label further down the list gives way)
	for i = 1, #shown do
		local pin = shown[i]
		local free = true
		if not pin.mine then
			for j = 1, #shown do
				if j ~= i and (shown[j].mine or j < i) and shown[j].label:IsShown() then
					local gap = math.abs((rects[i][1] + rects[i][2]) - (rects[j][1] + rects[j][2])) / 2
					if gap < 26 then
						free = false
						break
					end
				end
			end
		end
		pin.label:SetShown(free)
	end
	-- (yours over any it hides)
	ui.me.label:SetShown(ui.me.icon:IsShown())
end

-- the Current session's sources of the bar's kind (only the list)
local function LiveSources(healing)
	local sources = Meter.Sources(healing and Meter.KIND.healing or Meter.KIND.damage)
	return sources
end

local order = {}
local function Lay(sources, healing, sample)
	local ui = Bar.ui
	if not ui then
		return
	end
	Bar.list, Bar.healing = sources, healing
	local top = sources and sources[1]
	-- (each pin shown or hidden once, at the end, as this list wants it: a pin
	-- that stays stays shown)
	for _, pin in ipairs(ui.pins) do
		pin.want = false
	end
	ui.me.want = false
	ui.unit:SetText(healing and TEXT.hps or TEXT.dps)
	ui.caption:SetText(healing and TEXT.captionHeal or TEXT.caption)
	if not top then
		ui.top:SetText(Meter.TEXT.dash)
		ui.fill:SetValue(0)
		Bar.ShowWanted(ui)
		return
	end
	local topAmount = top.totalAmount
	ui.top:SetText(Meter.Format(top.amountPerSecond) or Meter.TEXT.dash)
	-- who has a pin: the best ones and always you
	local n, mine = #sources, nil
	for i = 1, n do
		if sources[i].isLocalPlayer == true then
			mine = i
			break
		end
	end
	local pins = min(n, Pins())
	for i = #order, 1, -1 do
		order[i] = nil
	end
	for i = 1, pins do
		order[i] = i
	end
	if mine and mine > pins then
		order[pins] = mine
	end
	pcall(ui.fill.SetMinMaxValues, ui.fill, 0, topAmount)
	ui.fill:SetValue(0)
	local shown, other = {}, 0
	for _, i in ipairs(order) do
		local src = sources[i]
		local pin
		if i == mine then
			pin = ui.me
			pcall(ui.fill.SetValue, ui.fill, src.totalAmount)
		else
			other = other + 1
			pin = ui.pins[other]   -- (nil past the others' pins: you not in the list, all of them taken)
			if pin then
				pin.label:SetText(Meter.Ordinal(i))
				ClassColour(pin.label, src.classFilename)
				TextShadow(pin.label)
			end
		end
		if pin then
			pcall(pin.bar.SetMinMaxValues, pin.bar, 0, topAmount)
			pcall(pin.bar.SetValue, pin.bar, src.totalAmount)
			Medallion(pin, src.classFilename)
			pin.want = true
			shown[#shown + 1] = pin
		end
	end
	Bar.ShowWanted(ui)
	Declutter(ui, shown)
end

-- every pin shown or hidden as the last lay wanted it
function Bar.ShowWanted(ui)
	for _, pin in ipairs(ui.pins) do
		SetPinShown(pin, pin.want)
	end
	SetPinShown(ui.me, ui.me.want)
end

--------------------------------------------------------------------------------
-- The list on hover: everyone in order (names secret in a fight: SetText)
--------------------------------------------------------------------------------

local list = nil

local function BuildList()
	if list then
		return list
	end
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetFrameStrata("TOOLTIP")
	f:SetSize(B.LIST_W, 20)
	f:Hide()
	-- (onelook B: the own windows' one panel, its border edge; Look.Panel's
	-- trim edge before)
	W.Panel(f, { on = true, alpha = 0.92 })
	list = { frame = f, rows = {} }
	Bar.listFrame = f   -- (read only: the tests')
	return list
end

local function ListRow(i)
	local row = list.rows[i]
	if row then
		return row
	end
	local f = list.frame
	row = {}
	row.rank = f:CreateFontString(nil, "OVERLAY")
	Look.Text(row.rank, "text", B.CAPTION)
	row.rank:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6 - (i - 1) * B.LIST_ROW)
	row.rank:SetWidth(28)
	row.rank:SetJustifyH("LEFT")
	row.name = f:CreateFontString(nil, "OVERLAY")
	Look.Text(row.name, "text", B.CAPTION)
	row.name:SetPoint("LEFT", row.rank, "RIGHT", 2, 0)
	row.name:SetWidth(120)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.value = f:CreateFontString(nil, "OVERLAY")
	Look.Text(row.value, "text", B.CAPTION)
	row.value:SetPoint("RIGHT", f, "RIGHT", -8, 0)
	row.value:SetPoint("TOP", row.rank, "TOP", 0, 0)
	row.value:SetJustifyH("RIGHT")
	list.rows[i] = row
	return row
end

ListShow = Shared("OnEnter on the race bar", function(holder)
	local sources = Bar.list
	if not (sources and sources[1]) then
		return
	end
	BuildList()
	local n = min(#sources, B.LIST_MAX)
	for i = 1, n do
		local src, row = sources[i], ListRow(i)
		row.rank:SetText(Meter.Ordinal(i))
		if src.isLocalPlayer == true then
			row.name:SetText(Meter.TEXT.you)
			Look.Text(row.name, "value", B.CAPTION)
			Look.Colour(row.name, nil)
		else
			Look.Text(row.name, "text", B.CAPTION)
			row.name:SetText(src.name or Meter.TEXT.someone)
			ClassColour(row.name, src.classFilename)
		end
		ClassColour(row.rank, src.classFilename)
		row.value:SetText(Meter.Format(src.amountPerSecond) or Meter.TEXT.dash)
		row.rank:Show()
		row.name:Show()
		row.value:Show()
	end
	for i = n + 1, #list.rows do
		local row = list.rows[i]
		row.rank:Hide()
		row.name:Hide()
		row.value:Hide()
	end
	local f = list.frame
	f:SetHeight(12 + n * B.LIST_ROW)
	-- above the bar; under it where the screen's top leaves no room (the
	-- user's test, 2026-10-01: the race bar placed at the top of the screen,
	-- its list ran off it), and kept on the screen at its sides too
	f:ClearAllPoints()
	f:SetPoint("BOTTOM", holder, "TOP", 0, 6)
	local _, _, _, top = Safe.ScreenRect(f)
	local _, _, _, screenTop = Safe.ScreenRect(UIParent)
	if top and screenTop and top > screenTop then
		f:ClearAllPoints()
		f:SetPoint("TOP", holder, "BOTTOM", 0, -6)
	end
	MelloUI:FitOnScreen(f)
	f:Show()
end, "script")

ListHide = Shared("OnLeave on the race bar", function()
	if list then
		list.frame:Hide()
	end
end, "script")

--------------------------------------------------------------------------------
-- In a fight, fading, and Edit Layout's samples
--------------------------------------------------------------------------------

local HideIt = function(holder)
	if not (Bar.shown or Bar.samples) then
		holder:Hide()
	end
end

local function FadeTo(alpha, duration)
	local ui = Bar.ui
	if not ui then
		return
	end
	if alpha > 0 then
		ui.holder:Show()
		MelloUI.Anim:To(ui.holder, "alpha", alpha, duration)
	else
		MelloUI.Anim:To(ui.holder, "alpha", 0, duration, nil, HideIt)
	end
end

-- the live sources (Meter.lua's read, at most 4 a second)
function Bar.Live(dmg, heal)
	if not (Bar.shown and Bar.ui) or Bar.samples then
		return
	end
	local healing = Healing()
	Lay(healing and heal or dmg, healing, false)
end

local function OutNow()
	if not Bar.shown and not Bar.samples and not Bar.preview then
		FadeTo(0, B.FADE_OUT)
	end
end

function Bar.Fight(on)
	if on then
		if not On() then
			return
		end
		Build()
		Bar.shown = true
		if not Bar.samples then
			local healing = Healing()
			Lay(LiveSources(healing), healing, false)
		end
		FadeTo(1, B.FADE_IN)
	elseif Bar.shown then
		Bar.shown = false
		if Bar.samples then
			return
		end
		if MelloUI.Anim.reduceMotion then
			OutNow()
		else
			C_Timer.After(B.OUT_DELAY, OutNow)
		end
	end
end

-- Edit Layout's samples (the sketch's group: you 3rd of five)
local SAMPLE = {
	{ name = "Fellaria", classFilename = "MAGE", totalAmount = 2510, amountPerSecond = 41.8 },
	{ name = "Shadeleaf", classFilename = "HUNTER", totalAmount = 2184, amountPerSecond = 36.4 },
	{ name = Meter.TEXT.you, classFilename = "WARRIOR", totalAmount = 1580, amountPerSecond = 26.3, isLocalPlayer = true },
	{ name = "Tarnok", classFilename = "SHAMAN", totalAmount = 1150, amountPerSecond = 19.2 },
	{ name = "Brightwood", classFilename = "PRIEST", totalAmount = 390, amountPerSecond = 6.5 },
}

function Bar.Samples()
	local want = On() and MelloUI:EditingLayout() and true or false
	if want == Bar.samples then
		return
	end
	Bar.samples = want
	if want then
		local ui = Build()
		local ok, _, file = pcall(_G.UnitClass, "player")
		SAMPLE[3].classFilename = ok and Text(file) or "WARRIOR"
		Lay(SAMPLE, false, true)
		ui.holder:SetAlpha(1)
		ui.holder:Show()
	elseif Bar.shown then
		local healing = Healing()
		Lay(LiveSources(healing), healing, false)
	else
		FadeTo(0, 0)
	end
end

-- the preview's made-up group fight (0.17.0, Modules/Meter.lua's): its
-- sources laid on each hit, faded out after the kill or the stop
function Bar.Preview(on, sources)
	if on then
		if not On() then
			return
		end
		local ui = Build()
		if not Bar.preview then
			Bar.preview = true
			ui.holder:SetAlpha(0)
			FadeTo(1, B.FADE_IN)
		end
		Lay(sources, false, true)
	elseif Bar.preview then
		Bar.preview = false
		OutNow()
	end
end

-- a new palette (the texts' shadow, the fill's fallback) or Bar Texture
local looking = false
local function LookChanged()
	if Bar.ui then
		Bar.Look()
	end
end

-- the module or its settings changed
function Bar.Apply()
	if not looking then
		looking = true
		-- (onelook B: the kit bracket's 'border' and 'look:statusbars' are gone
		-- with it; the soft shadow is the palette's, as the notice's)
		MelloUI:On("palette", LookChanged, "Race bar")
		-- the status bars' Bar Texture set or switched (W.BarFill): the fill again
		W.OnBarTexture("statusbars", LookChanged, "Race bar")
	end
	if Bar.ui then
		Bar.Resize()
		Bar.Look()
	end
	if not On() then
		Bar.shown = false
		Bar.samples = false
		if Bar.ui then
			MelloUI.Anim:Stop(Bar.ui.holder, "alpha")
			Bar.ui.holder:SetAlpha(0)
			Bar.ui.holder:Hide()
		end
		return
	end
	Bar.Samples()
	if Bar.shown and Bar.ui and not Bar.samples then
		local healing = Healing()
		Lay(LiveSources(healing), healing, false)
	end
end
