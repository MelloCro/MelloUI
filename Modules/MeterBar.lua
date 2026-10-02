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
-- shows it with sample pins on its plate; its box has the Width and Height
-- sliders, shortcuts to the configurator's Race Bar Width / Height). Built
-- with the first fight, or Edit Layout's first open while it is on.
-- Its look (user, 2026-10-01: "does not quite match the theme, the bar is
-- flat with no borders"): with the kit on (the status bars' look,
-- Kit:IsOn("statusbars")) the kit's bar bracket round it -- the P1 piece the
-- tooltip's health bar wears (Kit.Replacements "TooltipStatusBar"), following
-- the Bar Border choice -- and its trough; without the kit the palette's dark
-- ground and a trim edge. The fill in the Bar Texture of the status bars
-- (else MelloUI's Minimalist), in the palette's trim. The caption says
-- "Current DPS" (or HPS).
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
-- painted one with the reskin, the game's own without
local Look = MelloUI.Look
local Meter = ns.Meter
local M = Meter.M
local pcall, ipairs, min = pcall, ipairs, math.min

local WHITE = "Interface\\Buttons\\WHITE8x8"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MOVER_KEY = "meterbar"

local B = {
	WIDTH = 260, TRACK = 10, PIN = 16, ME_PIN = 20, RIM = 2, BELOW = 46, ABOVE = 20,
	LABEL = 10, ME_LABEL = 12, TOP = 13, CAPTION = 11,
	FADE_IN = 0.6, FADE_OUT = 1.2, OUT_DELAY = 1.5,
	LIST_ROW = 16, LIST_W = 220, LIST_MAX = 10,
	HOME_Y = 300,
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


-- the bar's size: Race Bar Width and Height (its track; the holder adds the
-- caption above and the pins under it)
local function Size()
	local db = M.db
	local w = Num(db and db.barWidth) or B.WIDTH
	local h = Num(db and db.barHeight) or B.TRACK
	return math.floor(w + 0.5), math.floor(h + 0.5)
end

-- the fill's texture: the status bars' Bar Texture, else MelloUI's Minimalist (W.BarFill)
local FillTexture = W.BarFill

local function Home(holder)
	holder:ClearAllPoints()
	holder:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, B.HOME_Y)
end

-- a string in its class's colour (its role's own colour without one): one
-- colour table a string, set again in place (Look.Colour keeps it over a
-- look switch)
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
	local size = mine and B.ME_PIN or B.PIN
	local pin = { bar = bar, mine = mine }
	-- (a gold rim round yours: a disc a little bigger behind it)
	if mine then
		local rim = holder:CreateTexture(nil, "ARTWORK", nil, 1)
		rim:SetTexture(ROUND_MASK)
		rim:SetSize(size + 2 * B.RIM, size + 2 * B.RIM)
		rim:SetPoint("TOP", fill or bar, "BOTTOMRIGHT", 0, -1)
		Look.Paint(rim, "selectedTrim", "vertex")
		Look.Hide(rim)
		pin.rim = rim
	end
	local icon = holder:CreateTexture(nil, "ARTWORK", nil, 2)
	icon:SetSize(size, size)
	icon:SetPoint("TOP", fill or bar, "BOTTOMRIGHT", 0, -1 - (mine and B.RIM or 0))
	pin.icon = icon
	-- (the game's look: the game's round class icon in the minimap's ring, as
	-- its round buttons; the ring's art sits in its file's top left, 53 of
	-- 64 round a 21 wide opening)
	local ring = holder:CreateTexture(nil, "ARTWORK", nil, 3)
	local _, ringFile = Look.Art("ring")
	ring:SetTexture(ringFile)
	local k = size / 21
	ring:SetSize(53 * k, 53 * k)
	ring:SetPoint("TOPLEFT", icon, "TOPLEFT", -5 * k, 4 * k)
	Look.Only(ring, "game")
	pin.ring = ring
	local label = holder:CreateFontString(nil, "OVERLAY")
	Look.Text(label, mine and "value" or "text", mine and B.ME_LABEL or B.LABEL)
	label:SetShadowOffset(1, -1)
	label:SetPoint("TOP", icon, "BOTTOM", 0, -1)
	pin.label = label
	return pin
end

local function SetPinShown(pin, on)
	pin.bar:SetShown(on)
	pin.icon:SetShown(on)
	pin.label:SetShown(on)
	Look.Show(pin.ring, on)
	if pin.rim then
		Look.Show(pin.rim, on)
	end
end

local ListShow, ListHide, LookBar   -- (below)

local function Build()
	if Bar.ui then
		return Bar.ui
	end
	local holder = CreateFrame("Frame", "MelloUIMeterBar", UIParent)
	holder:SetSize(B.WIDTH, B.ABOVE + B.TRACK + B.BELOW)   -- (the settings' size: Bar.Resize, below)
	holder:SetFrameStrata("MEDIUM")
	holder:SetClampedToScreen(true)
	holder:SetAlpha(0)
	holder:Hide()
	Home(holder)
	local ui = { holder = holder, pins = {} }
	Bar.ui = ui
	-- the caption and the top value above the track
	local caption = holder:CreateFontString(nil, "OVERLAY")
	Look.Text(caption, "title", B.CAPTION, { alpha = 0.8 })
	caption:SetShadowOffset(1, -1)
	caption:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", 0, -16)
	caption:SetText(TEXT.caption)
	ui.caption = caption
	local unit = holder:CreateFontString(nil, "OVERLAY")
	Look.Text(unit, "value", B.CAPTION)
	unit:SetShadowOffset(1, -1)
	unit:SetPoint("BOTTOMRIGHT", holder, "TOPRIGHT", 0, -16)
	ui.unit = unit
	local top = holder:CreateFontString(nil, "OVERLAY")
	Look.Text(top, "value", B.TOP)
	top:SetShadowOffset(1, -1)
	top:SetPoint("BOTTOMRIGHT", unit, "BOTTOMLEFT", -3, 0)
	ui.top = top
	-- the track: your fill in the kit's bar bracket painted, in the game's
	-- meter bar in its look (LookBar, below)
	local track = CreateFrame("Frame", nil, holder)
	track:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -B.ABOVE)
	track:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -B.ABOVE)
	ui.track = track
	local fill = CreateFrame("StatusBar", nil, track)
	fill:SetAllPoints(track)
	fill:SetMinMaxValues(0, 1)
	fill:SetValue(0)
	ui.fill = fill
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
	-- its place: the one mover (its box: Width and Height, the
	-- configurator's own settings)
	ui.entry = MelloUI:RegisterMover(holder, holder, { key = MOVER_KEY, default = Home, min = 0.5, max = 2, base = 1,
		label = TEXT.label, page = "BarsMeters", when = On, settings = { "Meter.barWidth", "Meter.barHeight" } })
	if not MelloUI:RestorePosition(MOVER_KEY, holder) then
		Home(holder)
	end
	Bar.Resize()
	Look.Watch(ui, LookBar)   -- (now, and at every switch of MelloUI's own look)
	return ui
end

-- the size from the settings
function Bar.Resize()
	local ui = Bar.ui
	if not ui then
		return
	end
	local w, h = Size()
	ui.holder:SetSize(w, B.ABOVE + h + B.BELOW)
	ui.track:SetHeight(h)
	if ui.rep and ui.rep.Refit then
		pcall(ui.rep.Refit, ui.rep)
	end
end

-- the look (0.17.1, MelloUI's own look: the reskin): painted, the kit's
-- bar bracket round your fill in your Bar Texture and the palette's trim;
-- the game's, its damage meter's bar -- the dark ground, its shadowed edge
-- 2 px round, the cooldown manager's fill (as its meter entries) in your
-- class's colour. The one place the race bar names both looks (Look.Watch)
LookBar = function(ui, painted)
	local fill, Kit = ui.fill, MelloUI.Kit
	local tex = fill:GetStatusBarTexture()
	if painted then
		fill:SetStatusBarTexture(FillTexture())
		tex = fill:GetStatusBarTexture()
		if tex then
			W.Paint(tex, "trim", "vertex")
		end
		if ui.rep == nil and Kit and Kit.Replace then
			local layer, sublevel, troughLayer, troughSub = Kit:BracketLayers(fill)
			local ok, r = pcall(Kit.Replace, Kit, fill, { as = "TooltipStatusBar", parent = fill, rect = fill, noFade = true,
				layer = layer, sublevel = sublevel, troughLayer = troughLayer, troughSub = troughSub })
			ui.rep = ok and r or false
		end
		if ui.rep then
			ui.rep:Enable()
			pcall(ui.rep.Refit, ui.rep)
		end
		Look.GameBar(fill, nil, false)
		return
	end
	if ui.rep then
		ui.rep:Disable()
	end
	if tex and Kit and Kit.Unpaint then
		Kit:Unpaint(tex, "vertex")
	end
	Look.GameBar(fill, nil, true)   -- (the game's fill, its ground and edge)
	ui.back, ui.edge = Look.GameBarParts(fill)
	tex = fill:GetStatusBarTexture()
	if tex then
		local QI = MelloUI.QuestInk
		local okC, _, class = pcall(_G.UnitClass, "player")
		local r, g, b
		if okC and QI and QI.ClassColour and not Secret(class) then
			r, g, b = QI.ClassColour(class)
		end
		tex:SetVertexColor(r or 1, g or 0.82, b or 0, 1)
	end
end

-- the look again: a Bar Texture or Bar Border changed (the painted look's)
function Bar.Look()
	local ui = Bar.ui
	if ui then
		LookBar(ui, Look:On())
	end
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
	for _, pin in ipairs(ui.pins) do
		SetPinShown(pin, false)
	end
	SetPinShown(ui.me, false)
	ui.unit:SetText(healing and TEXT.hps or TEXT.dps)
	ui.caption:SetText(healing and TEXT.captionHeal or TEXT.caption)
	if not top then
		ui.top:SetText(Meter.TEXT.dash)
		ui.fill:SetValue(0)
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
			pin = ui.pins[other]
			pin.label:SetText(Meter.Ordinal(i))
			ClassColour(pin.label, src.classFilename)
		end
		if pin then
			pcall(pin.bar.SetMinMaxValues, pin.bar, 0, topAmount)
			pcall(pin.bar.SetValue, pin.bar, src.totalAmount)
			-- (the class's medallion painted, the game's round class icon in its look)
			Look.ClassIcon(pin.icon, src.classFilename, Meter.ClassIcon(src.classFilename))
			SetPinShown(pin, true)
			shown[#shown + 1] = pin
		end
	end
	Declutter(ui, shown)

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
	-- (the flat panel painted, the game's tooltip frame in its look)
	Look.Panel(f, { alpha = 0.92 })
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

-- the status bars' look switched (the kit on or off)
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
		MelloUI:On("border", LookChanged, "Race bar")
		MelloUI:On("look:statusbars", LookChanged, "Race bar")   -- (the Bar Texture follows the status bars' look)
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
