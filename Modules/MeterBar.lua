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
-- Shows: Auto, by the group role) or by the setting; (2.1.61, #26) or the
-- group's threat on your target (Race Bar Shows: Threat, in a group; its
-- section below the pins' lay).
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
local PET_ICON = "Interface\\Icons\\Ability_Hunter_BeastTaming"   -- (2.1.61: your pet's threat pin; the pet widget's icon)

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
	THREAT_TICK = 0.3, THREAT_TEST = 2,   -- (2.1.61, #26) threat read this often in a fight; the test's steps
	LIST_ROW = 16, LIST_W = 220, LIST_MAX = 10,
	HOME_Y = 325,
}

local TEXT = {
	caption = "Current DPS",
	captionHeal = "Current HPS",
	dps = "dps",
	hps = "hps",
	label = "Race Bar",
	captionThreat = "Threat",   -- (2.1.61, #26: Race Bar Shows' Threat)
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

-- (2.1.61, the German player: "how do we show both -- or leave it to the player what to show, damage, healing and
-- threat?", their picks: stacked, Auto kept, damage alone as before by default) the rows this fight shows, top
-- down: "dps", "hps", "threat".
--   Race Bar Shows: Your Pick (raceShows "pick", the default) -- the ticked ones of Damage (raceDps, on), Healing
--     (raceHps) and Threat (raceThreat); Auto -- healing as a healer, damage otherwise, and threat under it in a
--     group for a tank or a damage dealer. Threat only in a group or with your pet out (Threat.Grouped: solo, with no
--     pet, it tells nothing new); none left, damage
-- (2.1.61; the German player: "when I am out with my Voidwalker and it tanks, I would like to see my threat too") your
-- pet out: threat tells something solo too
local function HasPet()
	local ok, out = pcall(_G.UnitExists, "pet")
	return ok and not Secret(out) and out == true
end

local kinds = {}
-- (`grouped`: as in a group, for Edit Layout's samples)
local function Kinds(grouped)
	for i = #kinds, 1, -1 do
		kinds[i] = nil
	end
	local db = M.db or {}
	local T = rawget(MelloUI, "Threat")
	grouped = grouped or (T ~= nil and T.Grouped()) or HasPet()   -- (a pet out: threat solo too)
	if db.raceShows == "auto" then
		local ok, role = pcall(_G.UnitGroupRolesAssigned, "player")
		local healer = ok and Text(role) == "HEALER"
		kinds[1] = healer and "hps" or "dps"
		if grouped and not healer then
			kinds[2] = "threat"
		end
	else
		if db.raceDps ~= false then
			kinds[#kinds + 1] = "dps"
		end
		if db.raceHps == true then
			kinds[#kinds + 1] = "hps"
		end
		if db.raceThreat == true and grouped then
			kinds[#kinds + 1] = "threat"
		end
	end
	if #kinds == 0 then
		kinds[1] = "dps"
	end
	return kinds
end

-- (2.1.61) the one Race Bar Shows of before (metric: "auto", "dps", "hps"), read once into the new ones: a chosen
-- Healing stays ticked. "auto" was every player's saved default, so it reads as damage alone, the new default
function Bar.Migrate()
	local db = M.db
	if not db or db.raceMigrated then
		return
	end
	db.raceMigrated = true
	if db.metric == "hps" then
		db.raceDps, db.raceHps = false, true
	end
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
	face:SetKit(false)   -- (0.25.0: MelloUI's own gold ring of its icon set, the meter MelloUI's part; the kit's rim until then)
	-- (the pointer stays the holder's: its list. W.RoundIcon's SetKit keeps
	-- a mouse turned off through the kit rim's mouse hooks, in either order)
	face:EnableMouse(false)
	face:SetCrop(B.ICON_IN)   -- (its medallion cut inside its own ring; drawn from its copy for its size)
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
local function Medallion(pin, class, icon)
	class = Text(class)
	local key = icon or class   -- (2.1.61: a picture of its own, a pet's)
	if pin.classSet and pin.class == key then
		return
	end
	pin.class, pin.classSet = key, true
	local path = icon or (class and MelloUI.ClassIconPath and MelloUI:ClassIconPath(class, "plain"))
	pin.face:SetIcon(path or UNKNOWN_ICON)
end

local ListShow, ListHide   -- (below)

-- (2.1.61) one row of the bar: its caption and values over its rail, its share, its pins under it -- each row the
-- whole bar of before, on a frame of its own in the holder (Bar.Arrange stacks them); the pointer on a row lists
-- that row's sources
local function NewRow(ui, k)
	local holder = CreateFrame("Frame", nil, ui.holder)
	holder:SetHeight(B.ABOVE + B.BELOW)
	local row = { holder = holder, pins = {}, k = k }
	holder.row = row
	-- the caption and the top value: one line, GAP over the rims (the caption
	-- in the title face over the left end, the value over the right)
	local lineY = -(B.ABOVE - B.ME_PIN / 2 - B.GAP)
	local caption = W.Text(holder, "GameFontNormal", TEXT.caption, "text")
	caption:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", 0, lineY)
	if MelloUI.Kit and MelloUI.Kit.TitleFont then
		MelloUI.Kit:TitleFont(caption, true)
	end
	row.caption = caption
	local unit = holder:CreateFontString(nil, "OVERLAY")
	Look.Text(unit, "value", B.CAPTION)
	unit:SetPoint("BOTTOMRIGHT", holder, "TOPRIGHT", 0, lineY)
	row.unit = unit
	local top = holder:CreateFontString(nil, "OVERLAY")
	Look.Text(top, "value", B.TOP)
	top:SetPoint("BOTTOMRIGHT", unit, "BOTTOMLEFT", -3, 0)
	row.top = top
	-- the track: on the rail's middle line, as tall as your share (Race Bar
	-- Thickness); the rail across it, your share over the rail (Bar.Look)
	local track = CreateFrame("Frame", nil, holder)
	track:SetPoint("LEFT", holder, "TOPLEFT", 0, -B.ABOVE)
	track:SetPoint("RIGHT", holder, "TOPRIGHT", 0, -B.ABOVE)
	track:SetHeight(B.THICK)
	row.track = track
	local rail = W.Solid(track, "BACKGROUND", "border", 1)
	rail:SetPoint("LEFT", track, "LEFT", 0, 0)
	rail:SetPoint("RIGHT", track, "RIGHT", 0, 0)
	rail:SetHeight(B.RAIL)
	row.rail = rail
	local fill = CreateFrame("StatusBar", nil, track)
	fill:SetAllPoints(track)
	fill:SetMinMaxValues(0, 1)
	fill:SetValue(0)
	row.fill = fill
	-- the pins: the others, then yours over them
	for i = 1, Meter.T.PINS_MAX - 1 do
		row.pins[i] = NewPin(row, false)
		SetPinShown(row.pins[i], false)
	end
	row.me = NewPin(row, true)
	SetPinShown(row.me, false)
	row.me.label:SetText(W.Tr(Meter.TEXT.you))
	-- the pointer on it: everyone in order
	holder:EnableMouse(true)
	Perf.SetScript(holder, "OnEnter", ListShow)
	Perf.SetScript(holder, "OnLeave", ListHide)
	holder:Hide()
	ui.rows[k] = row
	return row
end

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
	local ui = { holder = holder, rows = {}, shownRows = 1 }
	Bar.ui = ui
	-- the whole group on one soft band in the text look (its middle the
	-- holder grown by the look's padX at each side, faded BAND_Y above and
	-- below: a block of lines, Shade:Band's featherY) -- (2.1.61) every row on it
	local Shade = MelloUI.Shade
	local look = Shade.TEXT
	ui.band = Shade:Band(holder, { colour = look.colour, alpha = look.alpha, feather = look.feather, layer = look.layer,   -- look-ok: the one look's band (onelook B "Rail"; no game twin since stage C)
		featherY = B.BAND_Y })
	if ui.band then
		ui.band:Anchor(holder, look.padX, 0)
	end
	NewRow(ui, 1)
	-- its place: the one mover (Width and Thickness are the configurator's,
	-- its box's "Design >")
	ui.entry = MelloUI:RegisterMover(holder, holder, { key = MOVER_KEY, default = Home, min = 0.5, max = 2, base = 1,
		label = TEXT.label, page = "BarsMeters", when = On, category = "combat" })
	if not MelloUI:RestorePosition(MOVER_KEY, holder) then
		Home(holder)
	end
	Bar.Arrange(1)
	Bar.Look()
	return ui
end

-- (2.1.61) `n` rows shown, stacked top down in the holder, the holder as tall as they are (placed by its bottom: more
-- rows grow it upward); the others hidden. Each row made the first time it is needed
function Bar.Arrange(n)
	local ui = Bar.ui
	if not ui then
		return
	end
	n = math.max(1, math.min(3, n or 1))
	ui.shownRows = n
	for k = 1, n do
		if not ui.rows[k] then
			Bar.LookRow(NewRow(ui, k))   -- (a row made now: its look as the others')
		end
	end
	Bar.Resize()
	for k, row in ipairs(ui.rows) do
		row.holder:SetShown(k <= n)
	end
end

-- the size from the settings (the holder's height is the rims' and texts':
-- Thickness stays inside it)
function Bar.Resize()
	local ui = Bar.ui
	if not ui then
		return
	end
	local w, h = Size()
	local rowH = B.ABOVE + B.BELOW
	ui.holder:SetSize(w, rowH * (ui.shownRows or 1))   -- (2.1.61: as tall as its rows)
	for k, row in ipairs(ui.rows) do
		row.holder:ClearAllPoints()
		row.holder:SetPoint("TOPLEFT", ui.holder, "TOPLEFT", 0, -(k - 1) * rowH)
		row.holder:SetPoint("TOPRIGHT", ui.holder, "TOPRIGHT", 0, -(k - 1) * rowH)
		row.track:SetHeight(h)
	end
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
	for _, row in ipairs(ui.rows) do
		Bar.LookRow(row)
	end
end

-- (2.1.61) one row's look (your share, its texts' shadow); a threat row's share in your class colour until its next lay
function Bar.LookRow(ui)
	ui.threatPainted = false
	local fill, Kit = ui.fill, MelloUI.Kit
	fill:SetStatusBarTexture(FillTexture())
	MelloUI.Widgets.SoftEnds(fill)   -- (every bar's ends soft: the user, 2026-10-16)
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
local function Lay(ui, sources, healing, sample)
	if not ui then
		return
	end
	-- (2.1.61: `ui` one row of the bar; its own list for its pointer)
	ui.list, ui.healing, ui.threat = sources, healing, false
	if ui.threatPainted then
		Bar.LookRow(ui)   -- (your share in your class colour again after Threat's colours)
	end
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
local LIST_ALPHA = 0.92   -- (the box's ground in the own windows' panel; the game's chat box's under Default)

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
	W.Panel(f, { on = true, alpha = LIST_ALPHA })   -- (its box laid again at every show: Bar.ListLook)
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
	local bar = holder.row   -- (2.1.61: the bar's row under the pointer, its own list)
	local sources = bar and bar.list
	if not (sources and sources[1]) then
		return
	end
	BuildList()
	local n = min(#sources, B.LIST_MAX)
	for i = 1, n do
		local src, row = sources[i], ListRow(i)
		-- (2.1.61: threat's list in order only while its numbers read plain)
		row.rank:SetText((bar.threat and not bar.threatPlain) and "" or Meter.Ordinal(i))
		if src.isLocalPlayer == true then
			row.name:SetText(W.Tr(Meter.TEXT.you))
			Look.Text(row.name, "value", B.CAPTION)
			Look.Colour(row.name, nil)
		else
			Look.Text(row.name, "text", B.CAPTION)
			row.name:SetText(src.name or Meter.TEXT.someone)
			ClassColour(row.name, src.classFilename)
		end
		ClassColour(row.rank, src.classFilename)
		row.value:SetText(src.valueText or Meter.Format(src.amountPerSecond) or Meter.TEXT.dash)
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
	Bar.ListLook()
	f:Show()
end, "script")

-- (lk-12; the user's pick 6A of default_windows_sketch, 2026-10-29: "The damage meter's bars take the chat's
-- see-through box") the list's box as the skin has it, at every show: under the Default skin the game's see-through
-- chat box (its ground at the game's chat window's alpha, MelloUI.Skin.ChatAlpha; no edge lines), the own windows'
-- panel else
function Bar.ListLook()
	local f = list and list.frame
	if not (f and f.panelFill) then
		return
	end
	local Skin = rawget(MelloUI, "Skin")
	local game = type(Skin) == "table" and Skin.ChatAlpha and Skin.IsDefault()
	local alpha = game and Skin.ChatAlpha() or nil
	W.Paint(f.panelFill, "innerPanel", "fill", alpha or LIST_ALPHA)
	for _, edge in ipairs(f.panelEdges or {}) do
		edge:SetShown(not alpha)
	end
end

ListHide = Shared("OnLeave on the race bar", function()
	if list then
		list.frame:Hide()
	end
end, "script")

--------------------------------------------------------------------------------
-- Threat (2.1.61, #26; a German player's wish: "in a dungeon I'd like to see at a glance who is how close to
-- pulling, as I can with damage"): Race Bar Shows' third choice. While you are in a group, the bar is your target's
-- threat list: its right end the pull point (100: it comes for you; the tank stands there), each member a pin at their
-- share of the pull (Core/Threat.lua's Threat.Read, the game's scaledPercentage, plain or SECRET -- the pins placed by
-- the engine from it as the damage pins are), you the bigger pin, your share on the rail in the threat colours the
-- nameplates and the Threat widget use (gold, close, aggro; Threat.State). Ranks and "73%" only while the numbers read
-- plain (in instances); secret (the open world), the pins alone. Solo the bar shows damage, as Threat.Grouped says
-- threat tells nothing new there. Read every THREAT_TICK while it shows in a fight (the target may change, a heal adds
-- threat with no damage). /mello meter threat: a made-up group in three steps, you drawing near the pull
--------------------------------------------------------------------------------

-- your group's units (a raid's own list holds you)
local units = {}
local function GroupUnits()
	for i = #units, 1, -1 do
		units[i] = nil
	end
	local okR, raid = pcall(_G.IsInRaid)
	local okN, n = pcall(_G.GetNumGroupMembers)
	n = okN and Num(n) or 0
	if okR and raid == true then
		for i = 1, math.min(n, 40) do
			units[#units + 1] = "raid" .. i
		end
	else
		units[1] = "player"
		for i = 1, math.min(math.max(n - 1, 0), 4) do
			units[#units + 1] = "party" .. i
		end
	end
	if HasPet() then
		units[#units + 1] = "pet"   -- (2.1.61: your own pet, a Voidwalker tanking for you)
	end
	return units
end

-- a unit is you (a raid's list holds you under its own token; UnitIsUnit read only when plain)
local function IsYou(unit)
	if unit == "player" then
		return true
	end
	local ok, same = pcall(_G.UnitIsUnit, unit, "player")
	return ok and not Secret(same) and same == true
end

local threatList, threatPool = {}, {}
local function ByThreat(a, b)
	return a.plain > b.plain
end

-- the group's threat on your target: its sources (one table a member, reused), and whether every number read plain
local function ThreatSources()
	for i = #threatList, 1, -1 do
		threatList[i] = nil
	end
	local T = rawget(MelloUI, "Threat")
	local okE, exists = pcall(_G.UnitExists, "target")
	local okA, foe = pcall(_G.UnitCanAttack, "player", "target")
	if not (T and okE and okA and not Secret(exists) and not Secret(foe) and exists == true and foe == true) then
		return threatList, true
	end
	local plain = true
	for _, unit in ipairs(GroupUnits()) do
		local status, fraction, tanking, value = T.Read(unit, "target")
		if value ~= nil then
			local src = threatPool[#threatList + 1] or {}
			threatPool[#threatList + 1] = src
			local okC, _, class = pcall(_G.UnitClass, unit)
			src.classFilename = okC and not Secret(class) and class or nil
			src.isLocalPlayer = IsYou(unit)
			src.icon = unit == "pet" and PET_ICON or nil
			local okN, name = pcall(_G.UnitName, unit)
			src.name = okN and name or nil
			src.value, src.status, src.fraction, src.tanking = value, status, fraction, tanking
			src.plain = not Secret(value) and Num(value) or nil
			src.valueText = src.plain and ("%.0f%%"):format(src.plain) or nil
			src.amountPerSecond = nil
			if src.plain == nil then
				plain = false
			end
			threatList[#threatList + 1] = src
		end
	end
	if plain then
		table.sort(threatList, ByThreat)
	end
	return threatList, plain
end

-- the threat list laid on a row's pins (the live one, or the test's and Edit Layout's plain made-up one)
function Bar.LayThreat(ui, sources, plain)
	if not ui then
		return
	end
	ui.list, ui.healing, ui.threat, ui.threatPlain = sources, false, true, plain
	for _, pin in ipairs(ui.pins) do
		pin.want = false
	end
	ui.me.want = false
	ui.caption:SetText(W.Tr(TEXT.captionThreat))
	ui.unit:SetText("")
	pcall(ui.fill.SetMinMaxValues, ui.fill, 0, 100)
	ui.fill:SetValue(0)
	ui.top:SetText(Meter.TEXT.dash)
	local shown, other, room = {}, 0, math.min(#ui.pins, Pins() - 1)
	local mine = nil
	for i, src in ipairs(sources) do
		local pin
		if src.isLocalPlayer then
			pin, mine = ui.me, src
			pcall(ui.fill.SetValue, ui.fill, src.value)
			ui.top:SetText(src.valueText or Meter.TEXT.dash)
		elseif other < room then
			other = other + 1
			pin = ui.pins[other]
			pin.label:SetText(plain and Meter.Ordinal(i) or "")
			ClassColour(pin.label, src.classFilename)
			TextShadow(pin.label)
		end
		if pin then
			pcall(pin.bar.SetMinMaxValues, pin.bar, 0, 100)
			pcall(pin.bar.SetValue, pin.bar, src.value)
			Medallion(pin, src.classFilename, src.icon)
			pin.want = true
			shown[#shown + 1] = pin
		end
	end
	-- your share in the threat colours (your class colour while your state cannot be read)
	local T = rawget(MelloUI, "Threat")
	local state = mine and T and T.State(mine.status, mine.fraction, T.IsTank()) or nil
	local tex = ui.fill:GetStatusBarTexture()
	if state and tex then
		local Kit = MelloUI.Kit
		if Kit and Kit.Unpaint then
			Kit:Unpaint(tex, "vertex")
		end
		tex:SetVertexColor(T.Colour(state))
		ui.threatPainted = true
	elseif ui.threatPainted then
		Bar.LookRow(ui)
	end
	Bar.ShowWanted(ui)
	Declutter(ui, shown)
end

-- (2.1.61) the rows this fight shows (Kinds), each laid: damage and healing from Meter's live lists (or the ones
-- handed over), threat from the group's (not with `noThreat`: Bar.ThreatTick lays those on its own beat). True when
-- one of them is threat
local function LayRows(dmg, heal, noThreat)
	local ui = Bar.ui
	if not ui then
		return false
	end
	local want = Kinds()
	Bar.Arrange(#want)
	local threat = false
	for k, kind in ipairs(want) do
		local row = ui.rows[k]
		row.kind = kind
		if kind == "threat" then
			threat = true
			if not noThreat then
				Bar.LayThreat(row, ThreatSources())
			end
		elseif kind == "hps" then
			Lay(row, heal or LiveSources(true), true, false)
		else
			Lay(row, dmg or LiveSources(false), false, false)
		end
	end
	return threat
end

-- every THREAT_TICK while a threat row shows in a fight (one loop at a time)
function Bar.ThreatTick()
	local ui, any = Bar.ui, false
	if Bar.shown and ui and not Bar.samples and not Bar.preview then
		for k = 1, ui.shownRows do
			local row = ui.rows[k]
			if row and row.kind == "threat" then
				any = true
				Bar.LayThreat(row, ThreatSources())
			end
		end
	end
	if any then
		C_Timer.After(B.THREAT_TICK, Bar.ThreatTick)
	else
		Bar.ticking = false
	end
end

local function ThreatStart()
	if not Bar.ticking then
		Bar.ticking = true
		Bar.ThreatTick()
	end
end

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

-- the live sources (Meter.lua's read, at most 4 a second): damage and healing rows laid, a threat row's read kept
-- going (its own beat)
function Bar.Live(dmg, heal)
	if not (Bar.shown and Bar.ui) or Bar.samples or Bar.preview then
		return
	end
	if LayRows(dmg, heal, true) then
		ThreatStart()
	end
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
		if not Bar.samples and not Bar.preview then
			if LayRows() then
				ThreatStart()
			end
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

-- (2.1.61) a made-up group's threat on a made-up foe, plain: the tank at the pull, you drawing near it step by step
-- (/mello meter threat; Edit Layout's sample a threat row's step 2)
Bar.THREAT_SAMPLE = {
	{ classFilename = "WARRIOR", name = "Tarnok", tanking = true, status = 3 },
	{ classFilename = "MAGE", name = "Fellaria", status = 0 },
	{ classFilename = nil, name = Meter.TEXT.you, isLocalPlayer = true },
	{ classFilename = "HUNTER", name = "Shadeleaf", status = 0 },
	{ classFilename = "PRIEST", name = "Brightwood", status = 0 },
}
Bar.THREAT_STEPS = {
	{ 100, 64, 55, 41, 22 },   -- (the tank's, the mage's, yours, the hunter's, the priest's)
	{ 100, 78, 86, 52, 30 },
	{ 100, 81, 100, 60, 34 },
}

local function ThreatSample(n)
	local step = Bar.THREAT_STEPS[n]
	local ok, _, file = pcall(_G.UnitClass, "player")
	Bar.THREAT_SAMPLE[3].classFilename = ok and Text(file) or "WARRIOR"
	local made = {}
	for i, src in ipairs(Bar.THREAT_SAMPLE) do
		src.value, src.plain = step[i], step[i]
		src.fraction, src.valueText = step[i] / 100, ("%.0f%%"):format(step[i])
		if src.isLocalPlayer then
			src.status = step[i] >= 100 and 3 or (step[i] >= 80 and 1 or 0)
		end
		made[#made + 1] = src
	end
	table.sort(made, ByThreat)
	return made
end

-- (2.1.61) every row the setting would show in a group, laid with samples
local function LaySamples()
	local ui = Bar.ui
	local want = Kinds(true)
	Bar.Arrange(#want)
	local ok, _, file = pcall(_G.UnitClass, "player")
	SAMPLE[3].classFilename = ok and Text(file) or "WARRIOR"
	for k, kind in ipairs(want) do
		local row = ui.rows[k]
		row.kind = kind
		if kind == "threat" then
			Bar.LayThreat(row, ThreatSample(2), true)
		else
			Lay(row, SAMPLE, kind == "hps", true)
		end
	end
end

function Bar.Samples()
	local want = On() and MelloUI:EditingLayout() and true or false
	if want == Bar.samples then
		return
	end
	Bar.samples = want
	if want then
		local ui = Build()
		LaySamples()
		ui.holder:SetAlpha(1)
		ui.holder:Show()
	elseif Bar.shown then
		if LayRows() then
			ThreatStart()
		end
	else
		FadeTo(0, 0)
	end
end

-- the preview's made-up group fight (0.17.0, Modules/Meter.lua's): its
-- sources laid on each hit (one damage row), faded out after the kill or the stop
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
		Bar.Arrange(1)
		ui.rows[1].kind = "dps"
		Lay(ui.rows[1], sources, false, true)
	elseif Bar.preview then
		Bar.preview = false
		OutNow()
	end
end

-- /mello meter threat: one threat row with the made-up group in three steps (safe, close, pulling), then faded out
-- as the preview
function Bar.ThreatTest()
	if not On() or Bar.testStep then   -- (one run at a time)
		return
	end
	local ui = Build()
	if not Bar.preview then
		Bar.preview = true
		ui.holder:SetAlpha(0)
		FadeTo(1, B.FADE_IN)
	end
	Bar.Arrange(1)
	ui.rows[1].kind = "threat"
	Bar.testStep = 0
	Bar.ThreatTestStep()
end

function Bar.ThreatTestStep()
	Bar.testStep = (Bar.testStep or 0) + 1
	if not (Bar.THREAT_STEPS[Bar.testStep] and Bar.preview and Bar.ui) then
		Bar.testStep = nil
		Bar.Preview(false)
		return
	end
	Bar.LayThreat(Bar.ui.rows[1], ThreatSample(Bar.testStep), true)
	C_Timer.After(B.THREAT_TEST, Bar.ThreatTestStep)
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
	Bar.Migrate()   -- (2.1.61: the one Race Bar Shows of before into the ticks)
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
	if Bar.samples and Bar.ui then
		LaySamples()   -- (2.1.61: a tick changed while Edit Layout shows the samples)
		return
	end
	Bar.Samples()
	if Bar.shown and Bar.ui and not Bar.samples and not Bar.preview then
		if LayRows() then
			ThreatStart()
		end
	end
end
