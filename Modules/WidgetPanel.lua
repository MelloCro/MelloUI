--------------------------------------------------------------------------------
-- MelloUI - Widget Panel: the UI shade on the game's event widgets (0.14.0)
--
-- The whole UI's soft shade (Modules/KitShade.lua) on the widgets the game
-- shows for events: the scores at the top of the screen (a battleground's
-- bases and flags, a world event's counts), the capture bar under the
-- minimap and the encounter power bar. They have no kit art, so each one
-- gets the kit's synthetic shapes (user, 2026-09-26: whole-UI shade on by
-- default, outline pieces only; the event widgets are one of its areas):
--   a bar        the sheet's capsule under the bar's own outline (a capture
--                bar, a status bar, the two bars of a double bar, a power
--                bar, a tug of war), cut as a nine so its round ends keep
--                their shape at any length (never a rectangle on round art)
--   a line       the one soft band of the text rows (MelloUI.Shade:Band in
--                Shade.TEXT's look) behind each line of text (a score, a
--                timer, a label), its height pad following the line's text
--                size; on a line the game gives a set width (a text with
--                state or with a subtext) it hangs on MelloUI.Shade:Measure,
--                so it hugs the text, not the width (a wrapped line, or one
--                whose lines cannot be read, keeps the line's own span)
-- The widgets are read from the client's own UI code (studied locally, never
-- shipped): Blizzard_UIWidgets' containers keep their widgets in
-- container.widgetFrames, lay them out in container:UpdateWidgetLayout() and
-- take them from pools per template (a frame comes back for another widget
-- of its kind); a widget fades in and out with its own FadeInAnim /
-- FadeOutAnim (0.25 s) and is set up again by its Setup on every update (a
-- timer's every second).
--
-- Taint and the game's layout: the containers and most widgets are layout
-- frames that size themselves from ALL their children and regions, and the
-- one under the minimap moves the frames around it. So nothing is ever made
-- on a game frame here: no child frame, no texture. Every shade is drawn by
-- our own frames (one per container, a child of UIParent at the container's
-- strata and level, under all its widgets; one per widget under it) and only
-- ANCHORED to the widget's regions. The game's frames get hooks only
-- (hooksecurefunc on the containers' UpdateWidgetLayout and each widget's
-- Setup; HookScript on each widget's OnShow / OnHide and its two fades).
-- Nothing is anchored to an Edit Mode system: the power bar's container sits
-- in one, and only its widgets' own regions are anchor points here.
--
-- The switch: the Configurator's "Event Widgets" shade row (UI Shade on and
-- shade_widgets on: Kit:ShadeOn("widgets")), at its Shade Strength,
-- while the reskin is on (the kit's look: Kit:IsOn(LOOK) below). Switched
-- off, our frames hide at once; switched on, every widget up is dressed.
--
-- First use: loading the file makes no frame and no texture; it takes the
-- container hooks and three bus listeners ('shade', 'look:<area>' and
-- 'restart': a profile load writes the switches past the setting's Fire, so
-- the widgets' shade is set again from them on the next frame). A widget
-- is dressed the first time the game lays it out while the shade is on, and
-- once only (a pooled frame dressed again adds nothing). No idle work: no
-- ticker, no OnUpdate; the work runs when the game lays out or updates a
-- widget, reads no more than a few plain values and allocates nothing. The
-- fades copy the widget's own through the shared tween engine
-- (MelloUI.Anim: Reduce Motion shows and hides at once). The colours are
-- the palette's (the partners and the bands repaint on 'palette' in
-- Kit.lua and Core/Shade.lua).
--
-- Every read of the game's values is secret-safe (a secret text counts as
-- text and is handed on to the measure untouched, a secret size keeps the
-- fit it had, a secret shown state counts as shown). For tests and dumps:
-- Kit.shadeWidgets = { roots, dressed }.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
-- frames made in a game window: Core's maker, so the game's gamepad
-- navigation never walks an open window for each one (MelloUI.Safe.CreateFrame)
local CreateFrame = MelloUI.Safe.CreateFrame
local Perf = MelloUI.Perf:Scope("WidgetPanel")
local Shared = Perf.Shared
local hooksecurefunc = Perf.hooksecurefunc
local Kit = MelloUI.Kit
local Shade = MelloUI.Shade
local Anim = MelloUI.Anim
local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number

local AREA = "widgets"                 -- the shade area (Kit.shadeAreas)
-- the reskin's answer: the configurator's look area, as MelloUI's own
-- windows (the reskin alone: UI Modifications on, its reskin switch on)
local LOOK = "config"
local OWNER = "Event widget shade"     -- the bus owner
local RESTART_KEY = "Event widget shade after a restart"   -- (Kit:NextFrame's key)
local FADE = 0.25                      -- the widgets' own fade in and out (UIWidgetBaseTemplate)
local CAPSULE = "shade/capsule"
local ADDON = "Blizzard_UIWidgets"
-- the containers shaded: the scores at the top, the capture bars under the
-- minimap, the encounter power bar (its container is a child of an Edit
-- Mode system: only its widgets' regions are anchored to)
local CONTAINERS = { "UIWidgetTopCenterContainerFrame", "UIWidgetBelowMinimapContainerFrame",
	"UIWidgetPowerBarContainerFrame" }

-- The parts shaded per kind of widget (the client's visualization types).
-- bars: { path [, to = path], l, t, r, b } a capsule under the region at
--   `path` ("self": the widget; "Left.Text": a key of a key), or from its
--   top left to `to`'s bottom right, grown by l, t, r, b (the widget's units:
--   the frame art that stands past a status bar's ends)
-- lines: paths of font strings, a band behind each
-- fixed: the kind's Setup gives its lines a set width (the client's
--   Text:SetWidth: widgetSizeSetting, or the wider of two lines), so each
--   band hangs on a measure of its line
local KINDS = {
	IconAndText = { lines = { "Text" } },
	CaptureBar = { bars = { { "self" } } },
	StatusBar = { bars = { { "Bar", 8, 0, 8, 0 } } },
	DoubleStatusBar = { bars = { { "LeftBar", 4, 0, 4, 0 }, { "RightBar", 4, 0, 4, 0 } }, lines = { "Label" } },
	DoubleIconAndText = { lines = { "Label", "Left.Text", "Right.Text" } },
	TextWithState = { lines = { "Text" }, fixed = true },
	TextWithSubtext = { lines = { "Text", "SubText" }, fixed = true },
	UnitPowerBar = { bars = { { "Frame" } } },
	TugOfWar = { bars = { { "BarBackgroundLeft", to = "BarBackgroundRight" } } },
}
-- the numbers of those kinds on this client (its API documentation), for a
-- client with no Enum.UIWidgetVisualizationType
local TYPE_IDS = { IconAndText = 0, CaptureBar = 1, StatusBar = 2, DoubleStatusBar = 3, DoubleIconAndText = 5,
	TextWithState = 8, UnitPowerBar = 23, TextWithSubtext = 25, TugOfWar = 28 }

local WEAK = { __mode = "k" }
local KIND = {}                             -- [visualization type] = { bars, lines } with the paths split
local roots = {}                            -- [container] = { frame, level, subs = { widget records } }
local dressed = setmetatable({}, WEAK)      -- [widget frame] = its record, or false (a kind not shaded)
local byGroup = setmetatable({}, WEAK)      -- [a widget's fade] = its record
local hooked = {}                           -- [container] = true
local bandOpts = nil                        -- (Shade:Band's options, made with the first band)
-- a measure's point on its line, from the line's justify (anything else: LEFT)
local JUSTIFY = { LEFT = "LEFT", CENTER = "CENTER", RIGHT = "RIGHT" }
Kit.shadeWidgets = { roots = roots, dressed = dressed }

do
	local function Path(s)
		local path = {}
		if s ~= "self" then
			for key in s:gmatch("[^%.]+") do
				path[#path + 1] = key
			end
		end
		return path
	end
	local enum = type(Enum) == "table" and Enum.UIWidgetVisualizationType or nil
	for name, spec in pairs(KINDS) do
		local kind = { bars = {}, lines = {}, fixed = spec.fixed and true or false }
		for i, bar in ipairs(spec.bars or {}) do
			kind.bars[i] = { path = Path(bar[1]), to = bar.to and Path(bar.to) or nil,
				l = bar[2] or 0, t = bar[3] or 0, r = bar[4] or 0, b = bar[5] or 0 }
		end
		for i, line in ipairs(spec.lines or {}) do
			kind.lines[i] = Path(line)
		end
		local id = (type(enum) == "table" and Num(enum[name])) or TYPE_IDS[name]
		if id then
			KIND[id] = kind
		end
	end
end

--------------------------------------------------------------------------------
-- Reading the game's frames (secret-safe; nothing is written onto them)
--------------------------------------------------------------------------------

-- the region at a path of keys under the widget (the widget itself for none)
local function Resolve(widget, path)
	local o = widget
	for i = 1, #path do
		if type(o) ~= "table" then
			return nil
		end
		o = rawget(o, path[i])
	end
	if type(o) == "table" and type(o.GetObjectType) == "function" then
		return o
	end
	return nil
end

local function IsFontString(o)
	local ok, kind = pcall(o.GetObjectType, o)
	return ok and kind == "FontString"
end

-- shown (a refused or secret answer counts as shown)
local function Shown(region)
	local ok, v = pcall(region.IsShown, region)
	return not ok or Secret(v) or (v and true or false)
end

-- seen: its own flag and every parent's
local function Visible(region)
	local ok, v = pcall(region.IsVisible, region)
	return not ok or Secret(v) or (v and true or false)
end

-- a line's text size (nil when refused or secret: Shade:LinePadY's own pad)
local function TextSize(fs)
	local ok, _, size = pcall(fs.GetFont, fs)
	return ok and Num(size) or nil
end

-- where a measure sits on its line: the line's justify
local function Justify(fs)
	local ok, h = pcall(fs.GetJustifyH, fs)
	return ok and not Secret(h) and JUSTIFY[h] or "LEFT"
end

-- the line laid on one line (wrapped in its set width, or not readable: not)
local function OneLine(fs)
	local ok, n = pcall(fs.GetNumLines, fs)
	return ok and Num(n) == 1
end

local function Height(region)
	local ok, h = pcall(region.GetHeight, region)
	h = ok and Num(h)
	if h and h > 0 then
		return h
	end
	return nil
end

-- the widget's units in ours (1 when a scale reads secret or not at all)
local function Ratio(widget, ours)
	local okA, a = pcall(widget.GetEffectiveScale, widget)
	local okB, b = pcall(ours.GetEffectiveScale, ours)
	a, b = okA and Num(a), okB and Num(b)
	if a and b and a > 0 and b > 0 then
		return a / b
	end
	return 1
end

local function Level(frame)
	local ok, level = pcall(frame.GetFrameLevel, frame)
	level = ok and Num(level)
	return level and level > 0 and level or 0
end

-- the shade on and the reskin on
local function Active()
	return Kit:ShadeOn(AREA) and Kit:IsOn(LOOK)
end

--------------------------------------------------------------------------------
-- Our frames: one per container (at its strata and level: under all its
-- widgets, which the game lays at the container's level + 1 and up), one per
-- widget under it (shown, hidden and faded with its widget)
--------------------------------------------------------------------------------

local function Root(container)
	local root = roots[container]
	if root then
		return root
	end
	local f = CreateFrame("Frame", nil, UIParent)
	f:EnableMouse(false)
	f:SetAllPoints(UIParent)
	local ok, strata = pcall(container.GetFrameStrata, container)
	if ok and type(strata) == "string" and not Secret(strata) then
		f:SetFrameStrata(strata)
	end
	root = { frame = f, level = Level(container), subs = {} }
	f:SetFrameLevel(root.level)
	roots[container] = root
	return root
end

-- the container's level again (a container that raises itself on show: the
-- top one): our frames follow it down under its widgets
local function Relevel(root, container)
	local level = Level(container)
	if level == root.level then
		return
	end
	root.level = level
	root.frame:SetFrameLevel(level)
	local subs = root.subs
	for i = 1, #subs do
		subs[i].sub:SetFrameLevel(level)
	end
end

--------------------------------------------------------------------------------
-- A widget's parts fitted: each bar's capsule on its region grown by its
-- outsets (in our units), its shape's scale from the region's height (the
-- capsule's two corners are the rect's height), shown with its region; each
-- band shown while its line is shown and has text, anchored again when its
-- text size or what it hangs on changes. Nothing is made here once the parts
-- are in; a scale that changed refits the made capsule.
--------------------------------------------------------------------------------

local corner = nil   -- the capsule's corner (painted px), read from the sheet with the first bar

local function Anchor(part, ratio)
	local rect, region, to = part.rect, part.region, part.to
	rect:ClearAllPoints()
	rect:SetPoint("TOPLEFT", region, "TOPLEFT", -part.l * ratio, part.t * ratio)
	rect:SetPoint("BOTTOMRIGHT", to, "BOTTOMRIGHT", part.r * ratio, -part.b * ratio)
end

local function FitBar(rec, part, ratio, anchor)
	local region = part.region
	part.rect:SetShown(Shown(region) and (part.to == region or Shown(part.to)))
	if anchor then
		Anchor(part, ratio)
	end
	local h = Height(region)
	if h and corner then
		local scale = (h + part.t + part.b) * ratio / (2 * corner)
		local opts = part.opts
		if scale ~= opts.scale then
			-- (waiting in the shade's queue: made at this scale; made: refitted)
			opts.scale = scale
			local nine = Kit.shadeState.shaped[part.rect]
			if nine then
				Kit:ShadowFit(nine, scale)
			end
		end
	end
	if not part.added then
		part.added = true
		rec.el:Add(part.rect, part.opts)
	end
end

-- a line: its band shown while it is shown and has text (a secret text
-- counts), hung on its measure while the measure takes the text and the line
-- lies on one line (else on the line itself), its height pad from the text
-- size (the client's Setup can change a line's font on any update)
local function FitLine(line)
	local fs, band = line.fs, line.band
	local ok, text = pcall(fs.GetText, fs)
	local has = not ok or Secret(text) or (type(text) == "string" and text ~= "")
	if not (has and Shown(fs)) then
		band:SetShown(false)
		return
	end
	band:SetShown(true)
	local size = TextSize(fs)
	local hang = fs
	local m = line.m
	if m then
		local point = Justify(fs)
		if point ~= line.point then
			line.point = point
			m:ClearAllPoints()
			m:SetPoint(point, fs, point, 0, 0)
		end
		if size ~= line.size then
			Shade:MeasureFont(m)
		end
		if ok and Shade:MeasureText(m, text) and OneLine(fs) then
			hang = m
		end
	end
	if hang ~= line.hang or size ~= line.size then
		line.hang, line.size = hang, size
		band:Anchor(hang, Shade.TEXT.padX, Shade:LinePadY(size))
	end
end

local function Refit(rec)
	local ratio = Ratio(rec.widget, rec.sub)
	local anchor = ratio ~= rec.ratio
	rec.ratio = ratio
	local bars = rec.bars
	for i = 1, #bars do
		FitBar(rec, bars[i], ratio, anchor)
	end
	local lines = rec.lines
	for i = 1, #lines do
		FitLine(lines[i])
	end
end

--------------------------------------------------------------------------------
-- The widget's own show, hide, update and fades (shared handlers, hooked on
-- the widget once when it is dressed)
--------------------------------------------------------------------------------

local function Rest(rec, shown)
	Anim:Stop(rec.sub, "alpha")
	rec.sub:SetAlpha(1)
	rec.sub:SetShown(shown)
end

local Widget_OnShow = Shared("OnShow on an event widget: its shade", function(widget)
	local rec = dressed[widget]
	if rec then
		Rest(rec, true)
	end
end, "script")

local Widget_OnHide = Shared("OnHide on an event widget: its shade", function(widget)
	local rec = dressed[widget]
	if rec then
		Rest(rec, false)
	end
end, "script")

-- set up again (a new value, a timer's second, a pooled frame taken for
-- another widget): its parts fitted again
local Widget_OnSetup = Shared("Setup on an event widget: its shade", function(widget)
	local rec = dressed[widget]
	if rec and Active() then
		Refit(rec)
	end
end)

local FadeIn_OnPlay = Shared("OnPlay on an event widget's fade in: its shade", function(group)
	local rec = byGroup[group]
	if rec and Visible(rec.widget) then
		Anim:FadeIn(rec.sub, FADE)
	end
end, "script")

local FadeOut_OnPlay = Shared("OnPlay on an event widget's fade out: its shade", function(group)
	local rec = byGroup[group]
	if rec then
		Anim:FadeOut(rec.sub, FADE)
	end
end, "script")

-- a fade stopped midway (the game starts the other one, or sets the widget
-- back): the shade as the widget stands
local Fade_OnStop = Shared("OnStop on an event widget's fade: its shade", function(group)
	local rec = byGroup[group]
	if rec then
		Rest(rec, Visible(rec.widget))
	end
end, "script")

local function HookFade(rec, group, onPlay)
	if type(group) == "table" and type(group.HookScript) == "function" then
		byGroup[group] = rec
		Perf.HookScript(group, "OnPlay", onPlay)
		Perf.HookScript(group, "OnStop", Fade_OnStop)
	end
end

local function IsPlaying(group)
	if type(group) ~= "table" or type(group.IsPlaying) ~= "function" then
		return false
	end
	local ok, v = pcall(group.IsPlaying, group)
	return ok and not Secret(v) and v == true
end

--------------------------------------------------------------------------------
-- Dressing a widget: its frame under the container's, its element in the
-- shade's area (drawn by that frame), its capsules and bands, its hooks
--------------------------------------------------------------------------------

-- (the strength as it is now: each band is moved on its own in Sync)
local function BandOptions()
	if not bandOpts then
		local look = Shade.TEXT
		bandOpts = { colour = look.colour, feather = look.feather, layer = look.layer }
	end
	bandOpts.alpha = Kit:ShadeStrength()
	return bandOpts
end

local function Dress(widget, container)
	local kind = KIND[Num(rawget(widget, "widgetType")) or -1]
	if not kind then
		dressed[widget] = false
		return nil
	end
	if corner == nil then
		local entry = Kit:ShadowShape(CAPSULE)
		corner = entry and Num(entry.corner) or false
		if corner and corner <= 0 then
			corner = false
		end
	end
	local root = Root(container)
	local sub = CreateFrame("Frame", nil, root.frame)
	sub:EnableMouse(false)
	sub:SetAllPoints(root.frame)
	sub:SetFrameLevel(root.level)
	local rec = { widget = widget, container = container, sub = sub, bars = {}, lines = {}, ratio = nil,
		el = Kit:ShadeElement(sub, AREA, { host = sub }) }
	for _, spec in ipairs(kind.bars) do
		local region = Resolve(widget, spec.path)
		local to = spec.to and Resolve(widget, spec.to) or region
		if region and to then
			rec.bars[#rec.bars + 1] = { region = region, to = to, l = spec.l, t = spec.t, r = spec.r, b = spec.b,
				rect = CreateFrame("Frame", nil, sub), opts = { shape = CAPSULE } }
		end
	end
	-- (a line's band is anchored by its first fit; a measure, on a line with
	-- a set width, sits at the line's justify)
	for _, path in ipairs(kind.lines) do
		local fs = Resolve(widget, path)
		if fs and IsFontString(fs) then
			local band = Shade:Band(sub, BandOptions())
			if band then
				local point = Justify(fs)
				rec.lines[#rec.lines + 1] = { fs = fs, band = band, point = point, hang = nil, size = nil,
					m = kind.fixed and Shade:Measure(sub, fs, point) or nil }
			end
		end
	end
	dressed[widget] = rec
	root.subs[#root.subs + 1] = rec
	Perf.HookScript(widget, "OnShow", Widget_OnShow)
	Perf.HookScript(widget, "OnHide", Widget_OnHide)
	if type(widget.Setup) == "function" then
		hooksecurefunc(widget, "Setup", Widget_OnSetup)
	end
	local fadeIn, fadeOut = rawget(widget, "FadeInAnim"), rawget(widget, "FadeOutAnim")
	HookFade(rec, fadeIn, FadeIn_OnPlay)
	HookFade(rec, fadeOut, FadeOut_OnPlay)
	Refit(rec)
	-- as the widget stands now (a fade already under way: ours from here)
	local seen = Visible(widget)
	sub:SetShown(seen)
	if seen and IsPlaying(fadeIn) then
		Anim:FadeIn(sub, FADE)
	end
	return rec
end

--------------------------------------------------------------------------------
-- The passes: a container laid out by the game (its widgets dressed and
-- fitted), and the switch (our frames shown or hidden, every container's
-- widgets passed when it comes on, the bands at the strength)
--------------------------------------------------------------------------------

local function Pass(container)
	if not Active() then
		return
	end
	local frames = rawget(container, "widgetFrames")
	if type(frames) ~= "table" then
		return
	end
	for _, widget in pairs(frames) do
		if type(widget) == "table" then
			local rec = dressed[widget]
			if rec == nil then
				Dress(widget, container)
			elseif rec then
				Refit(rec)
			end
		end
	end
	local root = roots[container]
	if root then
		Relevel(root, container)
	end
end

local OnLayout = Shared("UpdateWidgetLayout on an event widget container: its widgets' shade", function(container)
	Pass(container)
end)

local function Sync()
	local on = Active()
	for _, root in pairs(roots) do
		root.frame:SetShown(on)
	end
	if not on then
		return
	end
	-- each band to the strength on its own (one made meanwhile has it already)
	local strength = Kit:ShadeStrength()
	for _, root in pairs(roots) do
		local subs = root.subs
		for i = 1, #subs do
			local lines = subs[i].lines
			for j = 1, #lines do
				local band = lines[j].band
				if band.alpha ~= strength then
					band:SetStrength(strength)
				end
			end
		end
	end
	for container in pairs(hooked) do
		Pass(container)
	end
end

MelloUI:On("shade", Shared("'shade' on the bus: the event widgets' shade", function(area)
	if area == AREA then
		Sync()
	end
end), OWNER)
MelloUI:On("look:" .. LOOK, Shared("'look' on the bus: the event widgets' shade", function()
	Sync()
end), OWNER)
-- a profile load (and the late settings at login) writes the switches and
-- the strength past the setting's Fire, and the shade's own pass after it
-- tells 'shade' only for an area with made partners (bands are not): set
-- again from the settings on the next frame (Sync reads them live, so a run
-- after a 'shade' changes nothing)
do
	local SyncSoon = Shared("next frame after a 'restart': the event widgets' shade", Sync)
	MelloUI:On("restart", Shared("'restart' on the bus: the event widgets' shade", function()
		Kit:NextFrame(RESTART_KEY, SyncSoon)
	end), OWNER)
end

-- the containers hooked once Blizzard_UIWidgets is in (it loads before the
-- addons: at once)
local function HookContainers()
	for _, name in ipairs(CONTAINERS) do
		local container = _G[name]
		if type(container) == "table" and type(container.UpdateWidgetLayout) == "function" and not hooked[container] then
			hooked[container] = true
			hooksecurefunc(container, "UpdateWidgetLayout", OnLayout)
		end
	end
end

local EventUtil = _G.EventUtil
if type(EventUtil) == "table" and type(EventUtil.ContinueOnAddOnLoaded) == "function" then
	EventUtil.ContinueOnAddOnLoaded(ADDON, HookContainers)
else
	HookContainers()
end
