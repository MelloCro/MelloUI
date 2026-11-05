--------------------------------------------------------------------------------
-- MelloUI - Group Frames (0.20.0; docs/plans/raid-frame-designer.md;
-- the user's picks 2026-10-09 "A A C B": the square drains from the top on its
-- own dark shade, the indicator list inside the Designer, your own frame while
-- solo AND the fake raid, a starter set per class and spec)
--
-- Your own aura indicators on the game's party and raid frames (and on your
-- frame while solo): a buff of yours or your group's picked by its spell, a
-- debuff on your group picked by its kind (the game never lets a friend's
-- debuff be picked by spell). Each one has a look -- an icon (its time a
-- sweep), a draining icon, a square that drains, a bar along an edge, or the
-- health bar's colour (the user: "recolor your Healthbar when you have
-- certain Hots") -- a place (one of nine anchors and an offset), a size, the
-- player's own colour (a colour wheel), and its time and stacks as text with
-- their own size and place. The game draws them: its secret-safe aura widget
-- (CustomAuraContainerTemplate, proven in a fight 2026-10-09) reads the auras,
-- secret or not, and fills our regions. MelloUI never reads an aura.
--
-- This file: the module, its settings and the indicator lists.
--   GroupLooks.lua        an indicator's regions and how each look lays them
--   GroupParts.lua        the frame's own parts: name, health text, icons
--   GroupIndicators.lua   the game's aura containers on the compact frames
--   RaidSolo.lua         your frame while solo
--   GroupDesignerPage.lua the Designer (the Configurator's canvas)
--
-- (Suggestion 1, point 3, 2026-11-04: one layout for every character -- the lists' key RD.SHARED, "ALL", whatever
-- you play; its start your class's own layout as you had it, else your class's starters; every character's own list
-- kept in db.sets as it was, Copy from brings it back. A single spell switched in a group is your class's tweak,
-- GroupSpellGroups.lua's classSpells.)
-- The lists: db.sets[specKey] = { indicator, ... } (specKey "PRIEST:1": the
-- class and the spec, or the talent group where the client has no specs). A
-- spec with no list of its own shows its class's starter set, kept in memory
-- only (ids "<specKey>#<n>"): nothing is written until the player changes it
-- (the login writes no setting), then the list is kept (db.sets, and
-- db.started so an emptied list stays empty). A buff is kept by its spell's
-- NAME: the client's spells of that name (every rank) are gathered by RD:Ids
-- once a session (sliced over frames, out of a fight), in memory only.
--   RD:Spec() -> key, label             the spec playing now
--   RD:List([key]) -> list              the indicators of a spec (laid with
--                                       its starter set on its first use)
--   RD:Add(entry) -> ind, RD:Remove(ind), RD:Changed([ind])   edits (the bus)
--   RD:Ids(name) -> { [id] = true }     a buff's spell IDs, as far as known
-- Bus "groupframes" (what, ...): "list" (the list or an indicator changed),
-- "spec" (another spec plays), "ids" (a name's spell IDs were gathered).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_GroupFrames (Group Frames)")
local Shared = Perf.Shared
local Text = MelloUI.Safe.Text

local RD = {}
ns.RD = RD
MelloUI.GroupFrames = RD   -- (the tests', and the Preview's part "raid")

local OWNER = "GroupFrames"

-- (1.2.4, the retail client: MelloUI.Retail, Core.lua) Group Frames' retail
-- guards -- the game's party members' buff rows, click-through aura buttons,
-- the buff tooltip put away; WoW Forever as before
function RD.Retail()
	return MelloUI.Retail
end

-- (0.20.1, the user: "i want to be able to change the background on the raid unitframes") Background: a flat colour
-- (Background Colour, as before) or one of the kit's shared backgrounds (Kit.buttonLooks.backgrounds: the tiles and the
-- gradients, the window backgrounds' own list), or none (GroupButton's Paint lays it)
function RD.BackgroundTextures()
	local out = { { value = "flat", label = "Flat colour" } }
	local Kit = MelloUI.Kit
	for _, v in ipairs(Kit and Kit.buttonLooks and Kit.buttonLooks.backgrounds or {}) do
		if v.piece or v.value == "none" then
			out[#out + 1] = { value = v.value, label = v.label }
		end
	end
	return out
end

RD.TEXT = {
	noSpell = "Group Frames: no spell named \"%s\" (type its name as the game writes it, or its spell ID).",
	added = "Group Frames: %s added.",
	gathering = "gathering its ranks...",
}

-- the looks (the user: "choose if something like renew is going as an icon,
-- or draining icon etc")
RD.LOOKS = {
	{ value = "icon", label = "Icon", tooltip = "The aura's own icon, its time as a sweep." },
	{ value = "drain", label = "Draining Icon", tooltip = "The aura's icon, emptying from the top as its time runs out." },
	{ value = "square", label = "Square", tooltip = "A square in your colour on its own dark shade, draining from the top." },
	{ value = "bar", label = "Bar", tooltip = "A thin bar along an edge of the frame, its length the time left." },
	{ value = "health", label = "Health Colour", tooltip = "The health bar takes your colour while the aura is on." },
}
RD.LOOK = {}
for _, l in ipairs(RD.LOOKS) do
	RD.LOOK[l.value] = l
end

-- a debuff by its kind: the game's filter words (AuraUtil.AuraFilters) and the
-- container's candidate filters (AuraContainerUtil.DoesAuraPassCandidateFilters)
RD.KINDS = {
	{ value = "group", label = "Dispellable by your group", filter = "HARMFUL|RAID_PLAYER_DISPELLABLE" },
	{ value = "mine", label = "Dispellable by you", filter = "HARMFUL|RAID" },
	{ value = "any", label = "Any dispellable debuff", filter = "HARMFUL|DISPELLABLE" },
	{ value = "boss", label = "Boss debuff", filter = "HARMFUL", candidates = { isBossAura = true } },
	{ value = "Magic", label = "Magic", filter = "HARMFUL", candidates = { includeDispelTypes = { Magic = true } } },
	{ value = "Curse", label = "Curse", filter = "HARMFUL", candidates = { includeDispelTypes = { Curse = true } } },
	{ value = "Disease", label = "Disease", filter = "HARMFUL", candidates = { includeDispelTypes = { Disease = true } } },
	{ value = "Poison", label = "Poison", filter = "HARMFUL", candidates = { includeDispelTypes = { Poison = true } } },
	{ value = "cc", label = "Crowd control", filter = "HARMFUL|CROWD_CONTROL" },
}
RD.KIND = {}
for _, k in ipairs(RD.KINDS) do
	RD.KIND[k.value] = k
end

RD.POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

-- the sizes a part may take (an icon, a square, a bar's thickness; text)
RD.SIZE = { min = 4, max = 30, text = 9, textMin = 6, textMax = 20 }

--------------------------------------------------------------------------------
-- Colours: an indicator's is the player's own (the colour wheel); a starter's
-- is one of the game's named colours, read when it is laid (never a literal)
--------------------------------------------------------------------------------

local function NamedColour(name)
	local c = rawget(_G, name)
	if type(c) == "table" and c.GetRGB then
		local r, g, b = c:GetRGB()
		if type(r) == "number" then
			return r, g, b
		end
	end
	return 1, 1, 1
end
RD.NamedColour = NamedColour

--------------------------------------------------------------------------------
-- The module
--------------------------------------------------------------------------------

-- the choices (Danders-level: the user, 2026-10-09 "i want the exact same
-- functionality as danders frames has"; stage 1 -- the frames, bars, colours
-- and texts)
local function V(...)
	local out = {}
	local t = { ... }
	for i = 1, #t, 2 do
		out[#out + 1] = { value = t[i], label = t[i + 1] }
	end
	return out
end
-- (one look Q7) the one Health Colour and its colours: Bar Textures' keys,
-- read with Bar Textures on or off -- the store as it is (no defaults laid on
-- each read: By Health asks it on every health update), else laid once
RD.HEALTH_KEYS = { healthColor = true, healthCustom = true, healthHigh = true, healthMid = true, healthLow = true }
function RD.Health()
	local mods = MelloUI.db and MelloUI.db.modules
	local t = type(mods) == "table" and mods.BarTextures
	if type(t) == "table" and t.healthColor ~= nil then
		return t
	end
	return MelloUI:GetModuleDB("BarTextures")
end

RD.CHOICES = {
	-- (1.2.4; the user, 2026-10-28: "either Raid or Party Frames" -- one look for the raid and a party in raid frames)
	partyStyle = V("group", "Raid Frames", "party", "Party Frames (Portraits)"),
	partyGrowth = V("DOWN", "Down", "UP", "Up", "RIGHT", "Right", "LEFT", "Left"),
	partySort = V("role", "By Role (Tanks, Healers, Damage)", "group", "Group Order", "name", "By Name"),
	raidGroupBy = V("group", "By Group", "role", "By Role", "class", "By Class", "none", "One List"),
	raidFlow = V("down", "Down, Then Across", "across", "Across, Then Down"),
	fillDirection = V("RIGHT", "Left To Right", "LEFT", "Right To Left", "UP", "Bottom To Top", "DOWN", "Top To Bottom"),
	background = V("custom", "My Colour", "class", "Class Colour"),
	missing = V("off", "Off", "custom", "My Colour", "class", "Class Colour", "health", "By Health"),
	power = V("healers", "Healers", "all", "Everyone", "off", "Off"),
	powerColour = V("type", "Power Type", "class", "Class Colour", "custom", "My Colour"),
	nameColour = V("white", "White", "class", "Class Colour", "custom", "My Colour"),
	healthText = V("none", "None", "percent", "Percent", "current", "Current", "deficit", "Missing"),
}
local C = RD.CHOICES

-- the frame's measures (the game's raid frame is 72 x 36: a little larger by
-- default, as group frames are)
RD.MEASURE = { width = 80, height = 40, widthMin = 40, widthMax = 200, heightMin = 20, heightMax = 120,
	spacingMax = 20, powerMin = 2, powerMax = 20, portraitSpacingMax = 40 }
local MS = RD.MEASURE

local M = MelloUI:RegisterModule(OWNER, {
	title = "Group Frames",
	desc = "MelloUI's own party and raid frames: their size, layout, colours, texts and your aura indicators.",
	icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing",
	flavour = "Your party and raid as you want them: colours, bars, texts, and your HoTs and shields at a glance.",
	enabledByDefault = true,
	-- (0.20.2, 2.1.0) the one-time steps (the raid spacing's copy, the range fade's new default): this machine's,
	-- never in a profile
	keep = { "raidSpacingMigrated", "rangeAlphaMigrated" },
	defaults = {
		-- the frames
		partyStyle = "group",
		showPlayer = true,
		solo = true,
		width = MS.width,
		height = MS.height,
		spacing = 2,
		raidSpacing = 2,
		portraitSpacing = 2,   -- (fr-16: the portrait party frames' room, the tight one of before fr-16)
		partyGrowth = "DOWN",
		partySort = "role",
		raidGroupBy = "group",
		raidFlow = "down",
		raidPerLine = 5,
		raidGap = 6,
		rangeAlpha = 0.4,   -- (one look C13d: 100% is no fade -- Fade When Out Of Range folded in; 2.1.0: 40%)
		-- the bars
		healthAlpha = 1,
		fillDirection = "RIGHT",
		smooth = true,
		hover = true,   -- (1.2.4: the mouseover highlight, MelloUI.FrameHover)
		backgroundTexture = "flat",
		background = "custom",
		backgroundCustom = "palette:innerPanel",
		backgroundAlpha = 0.9,
		missing = "off",
		missingCustom = "RED_FONT_COLOR",
		missingAlpha = 0.5,
		power = "healers",
		powerSolo = true,
		powerHeight = 6,
		powerColour = "type",
		powerCustom = "LIGHTBLUE_FONT_COLOR",
		-- the texts
		nameColour = "white",
		nameCustom = "WHITE_FONT_COLOR",
		nameLength = 0,
		healthText = "percent",
		statusText = true,
		-- (one look C11) the texts' own faces: MelloUI.FontFaces' values
		nameFont = "shared",
		healthFont = "shared",
		indicatorFont = "shared",
		-- the indicators (the Designer)
		indicators = true,
		fakeRaid = 10,   -- (Suggestion 1 point 2, 2.1.1: the fake raid's size, its Size buttons: 5, 10, 25 or 40)
		sets = {},
		started = {},
		-- (1.2.4: the raid's places, our party's too when it wears the raid frames; the party's own from one look C9,
		-- `partyParts`, stay in old settings unread)
		parts = {},
		nextId = 1,
	},
	options = {
		-- the frames
		{ type = "dropdown", key = "partyStyle", name = "In A Party", values = C.partyStyle,
		  desc = "In a party: the raid frames (their look is set on Raid), or the party frames with portraits. In a raid, the raid frames always show." },
		-- (1.2.4; the user, 2026-10-28: "if the Person selects that he wants to see the Raid Frames, then he should get
		-- the Look under the "Raid" category") the party in raid frames wears the raid's look: to Raid
		{ type = "button", name = "Raid Frames' Look", text = "Raid",
		  desc = "Your party wears the raid frames' look: set it on Raid.",
		  onClick = function() MelloUI:OpenConfig("raidframes") end },
		{ type = "toggle", key = "showPlayer", name = "Show Yourself In Your Party",
		  desc = "Your own frame among your party's." },
		{ type = "toggle", key = "solo", name = "Show Yourself While Solo",
		  desc = "Your own frame shows while you are not in a group. Move it in Edit Layout." },
		{ type = "slider", key = "width", name = "Frame Width", min = MS.widthMin, max = MS.widthMax, step = 1,
		  desc = "The width of each frame." },
		{ type = "slider", key = "height", name = "Frame Height", min = MS.heightMin, max = MS.heightMax, step = 1,
		  desc = "The height of each frame." },
		{ type = "slider", key = "spacing", name = "Party Spacing", min = 0, max = MS.spacingMax, step = 1,
		  desc = "The space between the party's frames." },
		-- (fr-16; the user, 2026-11-01: "the party frames are also too spread and i dont see the slider for vertical
		-- spacing") the portrait party frames' own: GroupHeaders.lua's PortraitSpacing
		{ type = "slider", key = "portraitSpacing", name = "Vertical Spacing", min = 0, max = MS.portraitSpacingMax,
		  step = 1, new = "2.1.0", desc = "The space between the party frames with portraits." },
		{ type = "dropdown", key = "partyGrowth", name = "Party Grows", values = C.partyGrowth,
		  desc = "Which way the party's frames line up." },
		{ type = "dropdown", key = "partySort", name = "Party Order", width = 240, values = C.partySort,
		  desc = "The order of the party's frames: by role, the game's order, or by name." },
		{ type = "dropdown", key = "raidGroupBy", name = "Raid Grouping", width = 240, values = C.raidGroupBy,
		  desc = "How the raid is grouped: by group, role, class, or one list." },
		{ type = "dropdown", key = "raidFlow", name = "Raid Fills", values = C.raidFlow,
		  desc = "Fill down columns, or across rows." },
		{ type = "slider", key = "raidPerLine", name = "Frames Per Column / Row", min = 1, max = 40, step = 1,
		  desc = "How many frames per column or row. 5 lines the raid up by group." },
		-- (0.20.2, the user: "a slider to modify the Distance Between the Party/Raid Frames" -- pick "Separate party / raid")
		{ type = "slider", key = "raidSpacing", name = "Raid Spacing", min = 0, max = MS.spacingMax, step = 1,
		  desc = "The space between the raid's frames." },
		{ type = "slider", key = "raidGap", name = "Gap Between Columns / Rows", min = 0, max = 40, step = 1,
		  desc = "The space between the raid's columns or rows." },
		{ type = "slider", key = "rangeAlpha", name = "Out Of Range Opacity", min = 0.1, max = 1, step = 0.05,
		  percent = true, desc = "How much a member out of your range fades. 100%: no fade." },
		-- the bars
		-- (one look Q7: the health bar's colour is the one Health Colour, Bar
		-- Textures' -- RD.Health -- its four colours with it)
		{ type = "slider", key = "healthAlpha", name = "Health Bar Opacity", min = 0.1, max = 1, step = 0.05,
		  percent = true, desc = "How solid the health bar is." },
		{ type = "dropdown", key = "fillDirection", name = "Fill Direction", values = C.fillDirection,
		  desc = "Which way the health and power bars fill." },
		{ type = "toggle", key = "smooth", name = "Smooth Bars",
		  desc = "Bars glide to new values instead of jumping." },
		{ type = "toggle", key = "hover", name = "Mouseover Highlight",
		  desc = "A glow and an outline on the frame under your mouse." },
		{ type = "dropdown", key = "backgroundTexture", name = "Background", values = RD.BackgroundTextures(),
		  desc = "What shows behind the health bar: a flat colour, a texture, or nothing." },
		{ type = "dropdown", key = "background", name = "Background Colour", values = C.background,
		  desc = "The colour behind the health bar: yours, or the member's class colour." },
		{ type = "colour", key = "backgroundCustom", name = "My Background Colour",
		  desc = "The background colour with My Colour." },
		{ type = "slider", key = "backgroundAlpha", name = "Background Opacity", min = 0, max = 1, step = 0.05,
		  percent = true, desc = "How solid the background is." },
		{ type = "dropdown", key = "missing", name = "Missing Health", values = C.missing,
		  desc = "Colours the lost part of the health bar: your colour, the class colour, or by health." },
		{ type = "colour", key = "missingCustom", name = "My Missing Health Colour",
		  desc = "The missing health's colour with My Colour." },
		{ type = "slider", key = "missingAlpha", name = "Missing Health Opacity", min = 0.1, max = 1, step = 0.05,
		  percent = true, desc = "How solid the missing health is." },
		{ type = "dropdown", key = "power", name = "Power Bar", values = C.power,
		  desc = "Who shows a power bar under their health." },
		{ type = "toggle", key = "powerSolo", name = "Your Power Bar While Solo",
		  desc = "Your own power bar while you play solo." },
		{ type = "slider", key = "powerHeight", name = "Power Bar Height", min = MS.powerMin, max = MS.powerMax, step = 1,
		  desc = "How tall the power bar is." },
		{ type = "dropdown", key = "powerColour", name = "Power Colour", values = C.powerColour,
		  desc = "The power bar's colour: the power's own, the class colour, or yours." },
		{ type = "colour", key = "powerCustom", name = "My Power Colour",
		  desc = "The power colour with My Colour." },
		-- the texts
		{ type = "dropdown", key = "nameColour", name = "Name Colour", values = C.nameColour,
		  desc = "The name's colour: white, the class colour, or yours." },
		{ type = "colour", key = "nameCustom", name = "My Name Colour",
		  desc = "The name colour with My Colour." },
		{ type = "slider", key = "nameLength", name = "Name Length", min = 0, max = 20, step = 1,
		  format = function(v) v = math.floor(v + 0.5) return v == 0 and "Whole name" or tostring(v) end,
		  desc = "The most letters of a name shown." },
		{ type = "dropdown", key = "healthText", name = "Health Text", values = C.healthText,
		  desc = "The health text: percent, current health, or missing health." },
		{ type = "toggle", key = "statusText", name = "Dead / Offline Text",
		  desc = "Dead, Ghost or Offline on a member's frame." },
		{ type = "dropdown", key = "nameFont", name = "Name Font", values = MelloUI.FontFaces,
		  desc = "The font of names on the party and raid frames. Shared: the interface font." },
		{ type = "dropdown", key = "healthFont", name = "Health Text Font", values = MelloUI.FontFaces,
		  desc = "The font of health text and status words on the party and raid frames. Shared: the interface font." },
		{ type = "dropdown", key = "indicatorFont", name = "Indicator Numbers Font", values = MelloUI.FontFaces,
		  desc = "The font of the indicators' timers and stacks. Shared: the numbers font." },
		-- the Designer
		{ type = "toggle", key = "indicators", name = "Indicators On The Frames",
		  desc = "Your aura indicators on the frames." },
		-- (one look C10: the frame and its parts are the designer stage's; 1.2.4:
		-- the canvas is the spell groups' tray and block, GroupSpellGroupsPage.lua's)
		-- (its height from the width it gets, `heightAt`: taller in the narrow column beside the stage, layout C --
		-- GroupSpellGroupsPage.lua's Page.Height; `height` the full width's)
		{ type = "canvas", key = "designer", name = "Your Indicators", height = 900,
		  heightAt = function(width)
			return ns.Page and ns.Page.Height and ns.Page.Height(width) or 900
		  end,
		  search = "indicators spell groups icons squares bars hots shields buffs debuffs defensives lockouts dispel colour wheel designer",
		  desc = "Your spell groups for this spec: drag a group onto the frame, pick its spells, then its look, place, size and colour.",
		  build = function(canvas, width)
			if ns.Page and ns.Page.Build then
				ns.Page.Build(canvas, width)
			end
		  end },
	},
})
RD.module = M

--------------------------------------------------------------------------------
-- The spec playing now: the class and the spec (or the talent group)
--------------------------------------------------------------------------------

local Plain = MelloUI.Safe.Value

-- a table copied all the way down (an indicator's text and stacks tables)
local function Copy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = type(v) == "table" and Copy(v) or v
	end
	return out
end
RD.Copy = Copy

function RD:Class()
	local ok, _, token = pcall(UnitClass, "player")
	return ok and Text(token) or "PRIEST"
end

function RD:Spec()
	local class = self:Class()
	local SI = rawget(_G, "C_SpecializationInfo")
	local n, label = nil, nil
	if type(SI) == "table" and type(SI.GetSpecialization) == "function" then
		local ok, s = pcall(SI.GetSpecialization)
		s = ok and Plain(s)
		if type(s) == "number" and s >= 1 then
			n = s
			if type(SI.GetSpecializationInfo) == "function" then
				local ok2, _, name = pcall(SI.GetSpecializationInfo, s)
				label = ok2 and Text(name) or nil
			end
		end
		if not n and type(SI.GetActiveSpecGroup) == "function" then
			local ok3, g = pcall(SI.GetActiveSpecGroup)
			g = ok3 and Plain(g)
			if type(g) == "number" and g >= 1 then
				n = g
			end
		end
	end
	n = n or 1
	return class .. ":" .. n, label or ("Talents " .. n)
end

--------------------------------------------------------------------------------
-- The lists
--------------------------------------------------------------------------------

local function DB()
	return M.db or MelloUI:GetModuleDB(OWNER)
end
-- (one look C10) the settings a frame's paint reads: a designer stage's try
-- while it paints its samples (RD.WithTry), else the module's. GroupFrames'
-- own code reads DB() itself
RD.DB = function()
	return RD.try or DB()
end

-- (one look C10) `fn(...)` run with the setting `key` read as `value` (a
-- choice under the mouse in a list: the stage's samples painted with it,
-- nothing written); one proxy kept, RD.try cleared even when fn fails
do
	local tried = { key = nil, value = nil }
	local proxy = setmetatable({}, {
		__index = function(_, k)
			if k == tried.key then
				return tried.value
			end
			return DB()[k]
		end,
		__newindex = function() end,
	})
	function RD.WithTry(key, value, fn, ...)
		if key == nil then
			return fn(...)
		end
		tried.key, tried.value = key, value
		RD.try = proxy
		local ok, err = pcall(fn, ...)
		RD.try = nil
		tried.key, tried.value = nil, nil
		if not ok then
			geterrorhandler()(err)
		end
	end
end

local function NextId()
	local db = DB()
	local n = tonumber(db.nextId) or 1
	db.nextId = n + 1
	return "i" .. n
end
RD.NewId = NextId

-- an indicator's fields, filled where missing (a starter's, an older one's)
function RD:Fill(t)
	t.id = t.id or NextId()
	-- (1.2.4: a spell group, GroupSpellGroups.lua)
	local SG = t.kind == "group" and ns.SpellGroups
	t.kind = (SG and "group") or (t.kind == "debuff" and "debuff") or "buff"
	t.look = RD.LOOK[t.look] and t.look or "icon"
	t.point = t.point or "TOPRIGHT"
	t.x, t.y = tonumber(t.x) or 0, tonumber(t.y) or 0
	t.size = tonumber(t.size) or (t.look == "bar" and 3 or 12)
	t.length = tonumber(t.length) or 1
	t.alpha = tonumber(t.alpha) or 0.55
	if type(t.r) ~= "number" then
		t.r, t.g, t.b = NamedColour(t.colour or "WHITE_FONT_COLOR")
	end
	t.colour = nil
	t.colourBy = t.colourBy == "type" and t.kind ~= "buff" and "type" or "mine"
	t.whose = t.whose == "any" and "any" or "mine"
	t.when = t.when == "combat" and "combat" or "always"
	if type(t.text) ~= "table" then
		t.text = { show = t.look == "icon" or t.look == "drain", point = "CENTER", x = 0, y = 0 }
	end
	t.text.size = tonumber(t.text.size) or RD.SIZE.text
	if type(t.count) ~= "table" then
		t.count = { show = true, point = "BOTTOMRIGHT", x = 1, y = -1 }
	end
	t.count.size = tonumber(t.count.size) or RD.SIZE.text
	if SG then
		SG.Fill(t)
	elseif t.kind == "buff" then
		-- (kept by name: every rank; the ID it came with gives the name)
		if not t.name and t.spell then
			t.name = RD:SpellName(t.spell)
		end
		t.what = nil
	else
		t.what = RD.KIND[t.what] and t.what or "group"
		t.spell, t.name = nil, nil
	end
	return t
end

-- a starter laid fresh (a copy: the class's spell groups stay as they are);
-- `id` its own (a spec's starters: "<specKey>#<n>", nothing counted in the
-- settings)
local function Laid(e, id)
	local t = {}
	for k, v in pairs(e) do
		t[k] = v
	end
	t.id = id
	return RD:Fill(t)
end

-- (2026-10-09 late: the normal party frames a choice in a party -- the
-- user: "the Designer should also be able to design our normal party frames")
-- The frame kinds: "group" (MelloUI's own) and "party" (the game's party
-- members, MelloUI-dressed: 120 x 53, the portrait on the left). A kind keeps
-- its own list per spec (places differ on a portrait frame): a party list's key
-- is "party@<specKey>".
RD.KINDS_OF_FRAME = { "group", "party" }
local PARTY_KEY = "party@"
-- (one look C9b: our party's own lists, "gparty@<specKey>"; 1.2.4, the user 2026-10-28: "we are modifying the Party
-- "Group Frames" and Raid Frames separatelly even tho they are the same" -- our party in raid frames shows the raid's
-- list, a bare spec key, again. Its old own lists stay in the settings, offered in Copy from only)
local GPARTY_KEY = "gparty@"

-- (Suggestion 1, point 3) the one layout every character shares
RD.SHARED = "ALL"
function RD:Layout()
	return RD.SHARED
end

function RD:KeyOf(key, kind)
	key = key or self:Layout()
	if kind == "party" and key:sub(1, #PARTY_KEY) ~= PARTY_KEY then
		return PARTY_KEY .. key
	end
	return key
end

function RD:KindOf(key)
	if type(key) ~= "string" then
		return "group"
	end
	if key:sub(1, #PARTY_KEY) == PARTY_KEY then
		return "party"
	end
	return key:sub(1, #GPARTY_KEY) == GPARTY_KEY and "groupParty" or "group"
end

-- a list key's spec (its kind's prefix off)
local function SpecOf(key)
	return (key:gsub("^" .. PARTY_KEY, ""):gsub("^" .. GPARTY_KEY, ""))
end

-- a starter's place on the normal party frame: icons and squares in a row
-- from the top right, leftwards; bars along the bottom under the bars; a
-- debuff's icon at the right
local function PartyPlace(t, n)
	if t.look == "bar" then
		t.point, t.x, t.y, t.length = "BOTTOMRIGHT", -5, 6, 0.6
	elseif t.look == "health" then
		return n
	elseif t.kind == "debuff" then
		t.point, t.x, t.y = "RIGHT", -4, -6
	else
		t.point, t.x, t.y = "TOPRIGHT", -4 - n * 14, -4
		return n + 1
	end
	return n
end

-- (one look C10) an indicator's default place on its list's frames: the top
-- right corner on ours, a starter's place on the normal party frame
function RD:Home(ind, listKey)
	local t = { look = ind.look, kind = ind.kind, point = "TOPRIGHT", x = 0, y = 0 }
	if self:KindOf(listKey) == "party" then
		PartyPlace(t, 0)
	end
	return t
end

function RD:Starter(class, key)
	local out = {}
	local party, n = self:KindOf(key) == "party", 0
	-- (1.2.4: the class's spell groups, GroupSpellGroups.lua)
	for i, e in ipairs(ns.SpellGroups and ns.SpellGroups.Starter(class) or {}) do
		local t = Laid(e, key and (key .. "#" .. i) or nil)
		if party then
			n = PartyPlace(t, n)
		end
		out[#out + 1] = t
	end
	return out
end

local unsaved = {}   -- [listKey] = its starter set, shown until the player changes it

function RD:List(key, kind)
	local db = DB()
	key = self:KeyOf(key, kind)
	local list = db.sets[key]
	if type(list) == "table" then
		for _, t in ipairs(list) do
			if not t.id then
				self:Fill(t)
			end
		end
		return list
	end
	if db.started[key] then
		-- (a list the player emptied, its table gone: empty again)
		list = {}
		db.sets[key] = list
		return list
	end
	list = unsaved[key]
	if not list then
		local spec = SpecOf(key)
		if spec == RD.SHARED then
			-- (Suggestion 1, point 3) the shared layout's start: your class's own as you had it (copied: that one stays
			-- as it is, a backup Copy from brings back), else your class's starters -- in memory until changed
			local own = db.sets[key:sub(1, #key - #spec) .. self:Spec()]
			if type(own) == "table" then
				list = {}
				for _, e in ipairs(own) do
					local t = {}
					for k, v in pairs(e) do
						t[k] = type(v) == "table" and Copy(v) or v
					end
					t.id = key .. "#" .. (#list + 1)
					list[#list + 1] = self:Fill(t)
				end
			else
				list = self:Starter(self:Class(), key)
			end
		else
			local class = spec:match("^([^:]+)") or self:Class()
			list = self:Starter(class, key)
		end
		unsaved[key] = list
	end
	return list
end

-- a starter set changed: kept from now on (its spec's list in the settings)
local function Keep(key, list)
	local db = DB()
	db.sets[key] = list
	db.started[key] = true
	unsaved[key] = nil
end

-- the spec whose list holds the indicator, while it is a starter set
local function UnsavedOf(ind)
	for key, list in pairs(unsaved) do
		for _, t in ipairs(list) do
			if t == ind then
				return key, list
			end
		end
	end
	return nil
end

function RD:Changed(ind, key)
	local k, list = nil, nil
	if key and unsaved[key] then
		k, list = key, unsaved[key]
	elseif ind then
		k, list = UnsavedOf(ind)
	end
	if k then
		Keep(k, list)
	end
	MelloUI:NotifySettingChanged(OWNER, "sets", DB().sets)
	MelloUI:Fire("groupframes", "list", ind)
end

function RD:Add(entry, key)
	key = key or self:Layout()
	local list = self:List(key)
	if unsaved[key] then
		Keep(key, list)
	end
	local t = self:Fill(entry)
	list[#list + 1] = t
	if t.name then
		self:Ids(t.name)
	end
	self:Changed(t)
	return t
end

function RD:Remove(ind, key)
	key = key or self:Layout()
	local list = self:List(key)
	if unsaved[key] then
		Keep(key, list)
	end
	for i = #list, 1, -1 do
		if list[i] == ind then
			table.remove(list, i)
		end
	end
	self:Changed()
end

-- every spec's list copied from another (the Designer's "Copy from")
function RD:CopyFrom(from, to)
	local src = self:List(from)
	local list = {}
	for _, e in ipairs(src) do
		local t = {}
		for k, v in pairs(e) do
			t[k] = type(v) == "table" and Copy(v) or v
		end
		t.id = nil
		list[#list + 1] = self:Fill(t)
	end
	Keep(to or self:Layout(), list)
	self:Changed()
end

-- the lists to copy from (the Designer's Copy from), as dropdown values: every
-- spec's of every kind ("Party Frames: PRIEST:1")
local LIST_LABEL = { group = "Raid Frames: ", groupParty = "Group Frames Party: ", party = "Party Frames: " }
function RD:SpecValues()
	local out, seen = {}, {}
	for _, t in ipairs({ DB().sets, unsaved }) do
		for key in pairs(t) do
			if not seen[key] then
				seen[key] = true
				local spec = SpecOf(key)
				out[#out + 1] = { value = key,
					label = LIST_LABEL[self:KindOf(key)] .. (spec == RD.SHARED and "Every character" or spec) }
			end
		end
	end
	table.sort(out, function(a, b) return a.value < b.value end)
	return out
end

--------------------------------------------------------------------------------
-- Spells: a buff's name, picture and every ID of that name (all its ranks:
-- this client's spells are ranked -- Renew is ten of them). Gathered once a
-- session, sliced over frames out of a fight, kept in memory (RD.known).
--------------------------------------------------------------------------------

-- (looked up when asked: a client's table, never one kept from load)
local function Spells()
	local t = rawget(_G, "C_Spell")
	return type(t) == "table" and t or nil
end

local function NameOf(id)
	local CSpell = Spells()
	if CSpell and type(CSpell.GetSpellName) == "function" then
		local ok, name = pcall(CSpell.GetSpellName, id)
		return ok and Text(name) or nil
	end
	local get = rawget(_G, "GetSpellInfo")
	if type(get) == "function" then
		local ok, name = pcall(get, id)
		return ok and Text(name) or nil
	end
	return nil
end

function RD:SpellName(id)
	return NameOf(tonumber(id) or 0)
end

function RD:SpellIcon(ind)
	local id = ind.spell
	if not id and ind.name then
		local ids = RD.known[ind.name]
		id = type(ids) == "table" and ids[1]
	end
	if not id then
		return nil
	end
	local CSpell = Spells()
	if CSpell and type(CSpell.GetSpellTexture) == "function" then
		local ok, tex = pcall(CSpell.GetSpellTexture, id)
		return ok and Plain(tex) or nil
	end
	return nil
end

-- a typed spell: its ID, or its name (a spell of yours by name, else any
-- spell of that name once the gathering finds one)
function RD:Resolve(typed)
	typed = (typed or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if typed == "" then
		return nil
	end
	local id = tonumber(typed)
	if id then
		local name = NameOf(id)
		return name and id, name
	end
	local CSpell = Spells()
	if CSpell and type(CSpell.GetSpellInfo) == "function" then
		local ok, info = pcall(CSpell.GetSpellInfo, typed)
		if ok and type(info) == "table" and Plain(info.spellID) then
			return info.spellID, Text(info.name) or typed
		end
	end
	return nil, typed
end

local SCAN = { top = 500000, slice = 0.004 }   -- the spell IDs looked at, and the time per frame
local scan = { wanted = {}, at = 0, on = false, found = {}, next = {} }
RD.SCAN = SCAN   -- (the tests')
RD.known = {}    -- [name] = { id, ... }: every ID of that name, gathered this session

local ScanStep
ScanStep = Shared("the Group Frames's spell gathering", function()
	if InCombatLockdown() then
		C_Timer.After(1, ScanStep)
		return
	end
	local stop = debugprofilestop() + SCAN.slice * 1000
	local wanted, found = scan.wanted, scan.found
	local id = scan.at
	while id < SCAN.top do
		id = id + 1
		local name = NameOf(id)
		if name and wanted[name] then
			local f = found[name]
			f[#f + 1] = id
		end
		if id % 200 == 0 and debugprofilestop() > stop then
			break
		end
	end
	scan.at = id
	if id < SCAN.top then
		C_Timer.After(0, ScanStep)
		return
	end
	-- done: every name asked for, its IDs kept for the session
	scan.on = false
	for name in pairs(wanted) do
		RD.known[name] = found[name]
	end
	wipe(scan.wanted)
	wipe(scan.found)
	MelloUI:Fire("groupframes", "ids")
	-- (names asked while it ran: one more gathering, all of them together)
	if next(scan.next) then
		for name in pairs(scan.next) do
			scan.wanted[name], scan.found[name] = true, {}
		end
		wipe(scan.next)
		scan.on, scan.at = true, 0
		C_Timer.After(0, ScanStep)
	end
end)

local function StartScan()
	if scan.on or not next(scan.wanted) then
		return
	end
	scan.on, scan.at = true, 0
	C_Timer.After(0, ScanStep)
end

-- a name's IDs as a set { [id] = true } for the container's includeSpellIDs;
-- unknown yet: the IDs it is known by so far (its own), the gathering asked
function RD:Ids(name, known)
	local kept = name and RD.known[name]
	local set = {}
	if type(kept) == "table" then
		for _, id in ipairs(kept) do
			set[id] = true
		end
		if known then
			set[known] = true
		end
		return set, true
	end
	if known then
		set[known] = true
	end
	if name and not scan.wanted[name] then
		if not scan.on or scan.at == 0 then
			-- (before the gathering's first step: it joins it)
			scan.wanted[name] = true
			scan.found[name] = {}
			StartScan()
		else
			-- (a name asked while a gathering runs: the next one)
			scan.next[name] = true
		end
	end
	return set, false
end

-- every buff name of the spec playing and of every kept list gathered (after
-- the login, once)
function RD:GatherAll()
	local lists = { self:List() }
	for _, list in pairs(DB().sets) do
		lists[#lists + 1] = list
	end
	for _, list in ipairs(lists) do
		for _, t in ipairs(list) do
			if t.kind == "buff" and t.name then
				self:Ids(t.name, t.spell)
			elseif t.kind == "group" and ns.SpellGroups then
				-- (a spell group's typed spells)
				ns.SpellGroups.Gather(t)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local specEvents = nil
local lastSpec = nil

local OnSpecEvent = Shared("the Group Frames' spec events", function()
	local key = RD:Spec()
	if key ~= lastSpec then
		lastSpec = key
		RD:List()   -- (the shared layout; another class's spell tweaks: the bus's "spec")
		MelloUI:Fire("groupframes", "spec", key)
	end
end, "script")

function M:OnInit(db)
	self.db = db
	-- (0.20.2: the raid's spacing of its own) a player from before keeps the one spacing party and raid shared; once
	if not db.raidSpacingMigrated then
		db.raidSpacingMigrated = true
		if type(db.spacing) == "number" then
			db.raidSpacing = db.spacing
		end
	end
	-- (2.1.0: Out Of Range Opacity 45% -> 40%) the old default, stored with the rest, becomes the new one; a player's
	-- own other value stays; once
	if not db.rangeAlphaMigrated then
		db.rangeAlphaMigrated = true
		if db.rangeAlpha == 0.45 then
			db.rangeAlpha = 0.4
		end
	end
end

-- the game's party and raid frames hidden by ours now (the Fader leaves them
-- alone then: Modules/Fader.lua; Unit Frames dresses the game's party members
-- only while they show); kind "party": its normal party frames, "raid" or nil:
-- the rest -- all of them in every style since fr-16 (In A Party: Party Frames
-- is our portrait party, GroupSolo.lua)
function RD:HidesGame(kind)
	local H = ns.Headers
	return (H and H.S and H.S.hidden) and true or false
end

-- (fr-16) the game's party and raid frames left alone -- nothing of another module's dressed, covered or hooked on
-- them (the user's errors of 2026-10-31: writes on the game's party members' regions): while Group Frames is on (its
-- switch, so a module asking before Group Frames has started hears it too) and while the game's are still hidden
-- (given back out of a fight, after the switch). The bus word groupframes "game" tells when they come back
function RD:LeavesGame(kind)
	return (MelloUI.db and MelloUI:IsModuleEnabled(OWNER)) or self:HidesGame(kind)
end

-- (fr-16) party `i`'s portrait party frame of ours while the portraits stand in for the game's party frames (the
-- damage meter's tab hangs on it: Modules/Meter.lua), else nil
function RD:PartyMember(i)
	local Solo = ns.Solo
	return (Solo and Solo.partyDriven and Solo:Member(i)) or nil
end

-- every frame that shows a member now (GroupHeaders.lua: H:Hosts), and one
-- member's: { frame, unit, health, kind = "group" | "party" }
function RD:Hosts()
	local H = ns.Headers
	return H and H:Hosts() or {}
end

function RD:HostOf(unit)
	local H = ns.Headers
	return H and H:HostOf(unit) or nil
end

function M:OnEnable(db)
	self.db = db
	if not specEvents then
		specEvents = CreateFrame("Frame")
		for _, e in ipairs({ "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TALENT_UPDATE" }) do
			pcall(specEvents.RegisterEvent, specEvents, e)
		end
		Perf.SetScript(specEvents, "OnEvent", OnSpecEvent)
	end
	lastSpec = RD:Spec()
	if ns.Page and ns.Page.Listen then
		ns.Page.Listen()
	end
	-- (0.21.3; the user, 2026-10-13: the party frames a second late after a
	-- /reload) at login, the header the group needs now in the next frame
	-- (Headers:Start's `first`); the rest after the login's settling seconds
	if MelloUI.LoggingIn and MelloUI:LoggingIn() then
		C_Timer.After(0, function()
			if M.isEnabled and ns.Headers then
				ns.Headers:Start(true)
			end
		end)
	end
	MelloUI:AfterLogin(function()
		if M.isEnabled then
			RD:List()
			RD:GatherAll()
			if ns.Headers then
				ns.Headers:Start()
			end
			if ns.Indicators then
				ns.Indicators:Start()
			end
		end
	end)
end

function M:OnDisable()
	if ns.Indicators then
		ns.Indicators:Stop()
	end
	if ns.Headers then
		ns.Headers:Stop()
	end
end

-- the settings that move or size the secure frames (out of combat only: a
-- fight's change waits for its end); every other one only repaints
RD.LAYOUT_KEYS = { width = true, height = true, spacing = true, raidSpacing = true, portraitSpacing = true,
	partyGrowth = true, partySort = true, raidGroupBy = true, raidFlow = true, raidPerLine = true, raidGap = true,
	showPlayer = true, solo = true }

function M:OnSettingChanged(key, _, db)
	self.db = db
	if key == "hover" then
		if MelloUI.FrameHover then
			MelloUI.FrameHover.Refresh()
		end
		return
	end
	if key == "parts" then
		-- (one look C9: a part's write, a reset of the page, a profile -- every
		-- frame laid again, once)
		if ns.Parts and ns.Parts.LayAll then
			ns.Parts.LayAll()
		end
		return
	end
	if key == "indicators" and ns.Indicators then
		if db.indicators then
			ns.Indicators:Start()
		else
			ns.Indicators:Stop()
		end
	elseif key == "indicatorFont" and ns.Indicators then
		-- (one look C11: the indicators' numbers laid again in their face; the
		-- made-up members' with the paint below)
		ns.Indicators:Apply()
		if ns.Headers then
			ns.Headers:Repaint()
		end
	elseif not ns.Headers then
		return
	elseif key == "partyStyle" then
		ns.Headers:Style()
		if ns.Indicators then
			ns.Indicators:Apply()
		end
	elseif RD.LAYOUT_KEYS[key] then
		ns.Headers:Layout()
	elseif key ~= "sets" then
		ns.Headers:Repaint()
	end
end
