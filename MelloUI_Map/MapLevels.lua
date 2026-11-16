--------------------------------------------------------------------------------
-- MelloUI Map - the level labels (2.1.55; docs/plans/map-level-labels.md; the user, 2026-11-16: "people are
-- freequently requesting that we show Zone/Mobs levels on the map, also fishing spots level ranges", then the picks
-- of the map level labels sketch: "A, E, H, off", the zone ranges "From Questie", the switches in a group of their
-- own after Travel)
--
-- Three layers, each a switch on the map's layers page (Map.lua's SWITCHES, the group Levels), all off until switched:
--   Zone levels      (A) a line under each zone's name, its level range in the game's difficulty colour for you
--                    (MapLayers' names ask Levels.Line)
--   Creature levels  (E) at a zone's zoom, a pill a group of creatures: their levels on it, the pill in the difficulty
--                    colour; the creature's name and levels on hover
--   Fishing levels   (H) at a zone's zoom, a badge on each of the zone's waters (MapWaters.lua, from the terrain's
--                    liquids): the skill the water needs, from where fish bite to where none get away, coloured by your
--                    fishing skill (red: nothing bites yet, yellow: some get away, green: none get away)
-- The minimap wears what the map wears: the pills and the badges round you on Route's minimap layer, by the same
-- switches.
--
-- The game has no zone levels to give (on Forever C_Map.GetMapLevels answers 0-0 for every zone) and no fishing
-- skills: the zones' ranges and the creatures come from Questie's data (LibQuestieDB, read in place through its
-- public API as Core/QuestSource.lua reads it; none of it ships with MelloUI), the fishing skills from MelloUI's own
-- table (FISH: the zones' known fishing levels). Without Questie the two Questie layers stand dimmed on the page.
--
-- The Questie pass: one look at every creature, a few ms a frame (the 1000 ms budget, rule 7), only once one of the
-- two layers is on and the map or the minimap wants it -- never at login:
--   a creature that offers no service (npcFlags 0: no vendor, trainer, quest giver, guard ...), not friendly to your
--   side alone, no critter (T.CRITTER_LEVEL), with levels and spawns; its spawns per zone grouped (a spawn within T.GROUP of a group's middle joins
--   it); once the zones' ranges are known (below) a zone's groups that fit it are merged by place into its pills
--   (Pills: whatever the creature, within T.MERGE), a pill of T.GROUP_MIN spawns or more, an elite's or a rare's of
--   one, its creatures listed on hover;
--   a zone's range: its normal creatures' levels, weighted by their spawns, from the T.P_LOW to the T.P_HIGH share,
--   critters and guards (more than T.CRITTER levels under or over the zone's middle) left out.
--
--   Levels.Line(uiMapID) -> text, r, g, b      the line under a zone's name (nil: none)
--   Levels.Init(canvas, pins) / Open() / Close() / Tick()   the map's (Map.lua)
--   Levels.Changed(key)                         a layer's switch turned (Map.lua's SetLayer)
--   Levels.Mini(enabled)                        the minimap's wanted or not (the Map module on)
--   Levels.KEYS                                 the layers' keys: zonelevels, creatures, fishing
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_Map (Levels)")
local Safe = MelloUI.Safe
local Finite, Plain = Safe.Finite, Safe.Value
local pairs, ipairs, pcall, type, rawget = pairs, ipairs, pcall, type, rawget
local floor, abs, max, min = math.floor, math.abs, math.max, math.min

local Levels = {}
ns.Levels = Levels

local T = {
	ZONES = "zonelevels", CREATURES = "creatures", FISHING = "fishing",   -- the layers' keys (Map.lua's SWITCHES)
	STEP_MS = 3,          -- the Questie pass: at most this many ms a frame
	GROUP = 5,            -- a spawn within this far of a group's middle joins it (percent of the zone's map)
	-- (2026-11-16, seen in the real client with Questie's data: a pill on every small group of every creature covered
	-- Durotar, guards at 30 and 60 among them) the groups of a zone merged by place, whatever the creature, and only
	-- what fits the zone shown:
	MERGE = 6,            -- groups within this far of a pill's middle join it (percent of the zone's map) ...
	SPAN_MERGE = 3,       -- ... while the pill's levels then span no more than this (a tight range stays tight)
	GROUP_MIN = 5,        -- spawns a pill needs (an elite's or a rare's: one)
	SPAN_MAX = 5,         -- a creature whose levels span more than this (a scaling one, a test entry) is no pill ...
	SPAN_ZONE = 10,       -- ... nor in its zone's range past this span
	FIT = 5,              -- a creature more than this many levels outside its zone's range (a guard) is no pill
	NAMES_MAX = 5,        -- creatures a pill's tooltip lists
	CRITTER_LEVEL = 1,    -- (seen in the real client: hares and adders merged into a zone's pills, "1-11") a creature
	                      -- no higher than this is a critter: no pill, not in its zone's range
	P_LOW = 0.1,          -- a zone's range: its creatures' levels from this share ...
	P_HIGH = 0.9,         -- ... to this one
	CRITTER = 15,         -- levels under a zone's middle: a critter, out of its range (over it: a guard)
	ZONE_FROM = 2.5,      -- the pills and the badges from a zone's zoom on (the other addons' pins', MapAddonPins)
	BUILD_PER_FRAME = 2,  -- zones laid a frame
	KEEP = 12,            -- zones kept laid; the farthest seen last let go past it
	PILL_H = 17,          -- a pill's height (px)
	PILL_PAD = 6,         -- its text's room each side
	BADGE_H = 19,         -- a fishing badge's height
	HOOK = 14,            -- the hook in it
	HOOK_ART = "Interface\\Icons\\Trade_Fishing",   -- the game's fishing picture (its mips keep it smooth small)
	EDGE = 1,             -- the dark edge round a pill (px)
	MINI_SCALE = 0.8,     -- the minimap's pills and badges at this share of the map's
	OWNER = "Map level labels",   -- on Route's minimap layer
	DASH = "\226\128\147",        -- the range's dash
	-- under the quest marks (20), over the flight masters (14); the badges laid before the pills (a pill that would cover
	-- a badge or another pill is not shown at that zoom: MapPins' cull, the most spawns first)
	ORDER = { creatures = 18, fishing = 19 },
}
Levels.T = T
Levels.KEYS = { T.ZONES, T.CREATURES, T.FISHING }

-- The zones' fishing skills (MelloUI's own table; the game keeps them on its server): [uiMapID] = the skill fish start
-- biting from (classic's zone values: below 1 is any skill); none get away from it + T.SURE. Forever's own zones
-- (Mount Hyjal, Riverglades, Shen'dralas, Zephras Isle) none until known
T.SURE = 95
local FISH = {
	-- Kalimdor
	[1411] = -70, [1412] = -70, [1413] = -20, [1438] = -70, [1439] = -20, [1440] = 55, [1441] = 130, [1442] = 55,
	[1443] = 130, [1444] = 205, [1445] = 130, [1446] = 205, [1447] = 205, [1448] = 205, [1449] = 205, [1450] = 205,
	[1451] = 330, [1452] = 330, [1454] = -20, [1456] = -20, [1457] = -20,
	-- the Eastern Kingdoms
	[1416] = 130, [1417] = 130, [1420] = -70, [1421] = -20, [1422] = 205, [1423] = 330, [1424] = 55, [1425] = 205,
	[1426] = -70, [1428] = 330, [1429] = -70, [1430] = 330, [1431] = 55, [1432] = -20, [1433] = 55, [1434] = 130,
	[1435] = 130, [1436] = -20, [1437] = 55, [1453] = -20, [1455] = -20, [1458] = -20,
}
Levels.FISH = FISH

local TEXT = {
	level = "Level %s",
	elite = "Elite",
	rare = "Rare",
	rareElite = "Rare Elite",
	boss = "Boss",
	fishing = "Fishing %s",
	fishNone = "You have not learned fishing.",
	fishBite = "Fish bite from %d, none get away from %d. Your skill: %d.",
	more = "and %d more",
}
Levels.TEXT = TEXT

-- the switch of a layer, as the map keeps it (Map.lua hands it over: Levels.on)
local function On(key)
	return Levels.on and Levels.on(key) and true or false
end

local function QuestieLib()
	local QS = rawget(MelloUI, "QuestSource")
	return QS and QS.Lib and QS.Lib() or nil
end

--------------------------------------------------------------------------------
-- Colours: the game's own (its quest difficulty colours: the same rule its own map uses for a zone's levels)
--------------------------------------------------------------------------------

local function Difficulty(level)
	if not (level and GetQuestDifficultyColor) then
		return 1, 1, 1
	end
	local ok, c = pcall(GetQuestDifficultyColor, level)
	if ok and type(c) == "table" and Finite(c.r) then
		return c.r, c.g, c.b
	end
	return 1, 1, 1
end

local function Named(name, fallbackLevel)
	local q = rawget(_G, "QuestDifficultyColors")
	local c = type(q) == "table" and q[name]
	if type(c) == "table" and Finite(c.r) then
		return c.r, c.g, c.b
	end
	return Difficulty(fallbackLevel)
end

local function PlayerLevel()
	return Finite(UnitLevel("player")) or 1
end

-- a zone's range in the game's map's colour (AreaLabelDataProvider): under its lowest by its lowest, over its highest
-- by its highest - 2 (a zone wholly below you is not yellow), else the "difficult" yellow
local function ZoneColour(lo, hi)
	local p = PlayerLevel()
	if p < lo then
		return Difficulty(lo)
	elseif p > hi then
		return Difficulty(hi - 2)
	end
	return Named("difficult", p)
end

local function Range(lo, hi)
	return lo == hi and tostring(hi) or (lo .. T.DASH .. hi)
end

--------------------------------------------------------------------------------
-- Your fishing skill (Forever's C_SkillInfo by the skill line's ID: the same in every language)
--------------------------------------------------------------------------------

local FISHING_LINE = 356
local fishSkill = nil   -- read once; again at SKILL_LINES_CHANGED

local function FishSkill()
	if fishSkill ~= nil then
		return fishSkill or nil
	end
	local get = C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID
	local rank
	if get then
		local ok, info = pcall(get, FISHING_LINE)
		if ok and type(info) == "table" then
			rank = Finite(info.rank)
		end
	end
	fishSkill = rank or false
	return rank
end

local function FishColour(lo, hi)
	local s = FishSkill() or 0
	if s < lo then
		return Named("impossible", PlayerLevel() + 10)
	elseif s < hi then
		return Named("difficult", PlayerLevel())
	end
	return Named("standard", PlayerLevel() - 3)
end

local function FishRange(id)
	local z = FISH[id]
	if not z then
		return nil
	end
	return max(1, z), z + T.SURE
end

--------------------------------------------------------------------------------
-- The Questie pass
--------------------------------------------------------------------------------

local S = {
	state = "idle",      -- "idle", "building", "ready"
	zone = {},           -- [uiMapID] = { lo, hi }
	groups = {},         -- [uiMapID] = { { name, lo, hi, rank, x, y, n } ... } (x, y: 0..1 of the zone's map)
	hist = nil,          -- (during the pass) [uiMapID] = { [level] = weight }
	ids = nil, i = 0,
	runner = nil,
	-- the map's
	canvas = nil, pins = nil, shown = false, cut = nil, built = {}, builtCount = 0, gen = 0,
}
Levels.S = S

local KEYS = { "name", "minLevel", "maxLevel", "spawns", "friendlyToFaction", "rank", "npcFlags" }
-- names of the data's helpers no player sees (spawn markers, triggers)
local HIDDEN = { "Trigger", "Bunny", "DND", "DNT", "Invisible", "Dummy", "Credit" }

local function Hidden(name)
	for _, w in ipairs(HIDDEN) do
		if name:find(w, 1, true) then
			return true
		end
	end
	return false
end

local mySide = nil
local function MySide()
	if not mySide then
		local f = Plain(UnitFactionGroup("player"))
		mySide = f == "Horde" and "H" or (f == "Alliance" and "A" or "")
	end
	return mySide
end

-- one creature: its groups per zone, its weight in each zone's levels
local function Take(id, L, maps)
	local ok, v = pcall(L.Npc.GetAll, id, KEYS)
	if not ok or type(v) ~= "table" then
		return
	end
	local name, lo, hi, spawns, friendly, rank, flags = v[1], v[2], v[3], v[4], v[5], v[6], v[7]
	if type(name) ~= "string" or type(spawns) ~= "table" or type(lo) ~= "number" or type(hi) ~= "number"
		or lo < 1 or hi < lo or hi <= T.CRITTER_LEVEL or (flags and flags ~= 0) or friendly == MySide()
		or Hidden(name) then
		return
	end
	rank = type(rank) == "number" and rank or 0
	local R2 = T.GROUP * T.GROUP
	for zone, pts in pairs(spawns) do
		local id2 = type(zone) == "number" and maps[zone]
		if id2 and type(pts) == "table" then
			local found = {}
			local n = 0
			for _, p in ipairs(pts) do
				local x, y = type(p) == "table" and p[1], type(p) == "table" and p[2]
				if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
					n = n + 1
					local joined = false
					for _, g in ipairs(found) do
						local dx, dy = x - g.sx / g.n, y - g.sy / g.n
						if dx * dx + dy * dy <= R2 then
							g.sx, g.sy, g.n = g.sx + x, g.sy + y, g.n + 1
							joined = true
							break
						end
					end
					if not joined then
						found[#found + 1] = { sx = x, sy = y, n = 1 }
					end
				end
			end
			if n > 0 then
				local list = S.groups[id2]
				if not list then
					list = {}
					S.groups[id2] = list
				end
				for _, g in ipairs(found) do
					list[#list + 1] = { name, lo, hi, rank, g.sx / g.n / 100, g.sy / g.n / 100, g.n }
				end
				-- (the zone's levels: a normal creature's spawns spread over its levels)
				-- (seen in the real client: Questie's neutral animals -- swine, farm stock -- pulled the Barrens' range down
				-- to 3; the creatures friendly to neither side make the range)
				if rank == 0 and hi - lo <= T.SPAN_ZONE and friendly == nil then
					local h = S.hist[id2]
					if not h then
						h = {}
						S.hist[id2] = h
					end
					local w = n / (hi - lo + 1)
					for l = lo, min(hi, lo + 20) do
						h[l] = (h[l] or 0) + w
					end
				end
			end
		end
	end
end

-- a zone's range from its levels' weights: the middle first, critters under it left out, then the shares
local function RangeOf(h)
	local levels, total = {}, 0
	for l, w in pairs(h) do
		levels[#levels + 1] = l
		total = total + w
	end
	if total <= 0 then
		return nil
	end
	table.sort(levels)
	local function At(share, from, to, sum)
		local run, last = 0, nil
		for _, l in ipairs(levels) do
			if l >= from and l <= to then
				run, last = run + h[l], l
				if run >= share * sum then
					return l
				end
			end
		end
		return last
	end
	local mid = At(0.5, 0, math.huge, total)
	-- (critters far under the middle out, and guards far over it)
	local lo0, hi0 = mid - T.CRITTER, mid + T.CRITTER
	local kept = 0
	for _, l in ipairs(levels) do
		if l >= lo0 and l <= hi0 then
			kept = kept + h[l]
		end
	end
	return At(T.P_LOW, lo0, hi0, kept), At(T.P_HIGH, lo0, hi0, kept)
end

local Ready   -- (below: the map and the minimap laid again)

-- a zone's groups as its pills: those that fit the zone (a creature's span at most SPAN_MAX, its levels within FIT of
-- the zone's range), merged by place (the biggest first; a group within MERGE of a pill's middle joins it while the
-- pill's levels then span at most SPAN_MERGE), a pill kept
-- with GROUP_MIN spawns or an elite or rare in it. A pill: { names = { { name, lo, hi, rank, n } ... } (the most spawns
-- first), lo, hi, x, y, n, rank (its highest) }
local function Pills(id, list)
	local z = S.zone[id]
	local fit = {}
	for _, g in ipairs(list) do
		local lo, hi = g[2], g[3]
		if hi - lo <= T.SPAN_MAX and (not z or (lo >= z[1] - T.FIT and hi <= z[2] + T.FIT)) then
			fit[#fit + 1] = g
		end
	end
	table.sort(fit, function(a, b)
		if a[7] ~= b[7] then
			return a[7] > b[7]
		end
		return a[1] < b[1]
	end)
	local pills, R2 = {}, (T.MERGE / 100) ^ 2
	for _, g in ipairs(fit) do
		local into
		for _, p in ipairs(pills) do
			local dx, dy = g[5] - p.x, g[6] - p.y
			if dx * dx + dy * dy <= R2 and max(p.hi, g[3]) - min(p.lo, g[2]) <= T.SPAN_MERGE then
				into = p
				break
			end
		end
		if into then
			local n = into.n + g[7]
			into.x, into.y = (into.x * into.n + g[5] * g[7]) / n, (into.y * into.n + g[6] * g[7]) / n
			into.n, into.lo, into.hi, into.rank = n, min(into.lo, g[2]), max(into.hi, g[3]), max(into.rank, g[4])
			local named
			for _, e in ipairs(into.names) do
				if e[1] == g[1] then
					e[2], e[3], e[5] = min(e[2], g[2]), max(e[3], g[3]), e[5] + g[7]
					named = true
					break
				end
			end
			if not named then
				into.names[#into.names + 1] = { g[1], g[2], g[3], g[4], g[7] }
			end
		else
			pills[#pills + 1] = { names = { { g[1], g[2], g[3], g[4], g[7] } }, lo = g[2], hi = g[3], x = g[5], y = g[6],
				n = g[7], rank = g[4] }
		end
	end
	local out = {}
	for _, p in ipairs(pills) do
		if p.n >= T.GROUP_MIN or p.rank > 0 then
			table.sort(p.names, function(a, b)
				if a[5] ~= b[5] then
					return a[5] > b[5]
				end
				return a[1] < b[1]
			end)
			out[#out + 1] = p
		end
	end
	return out
end

local function Finish()
	for id, h in pairs(S.hist) do
		local lo, hi = RangeOf(h)
		if lo and hi then
			S.zone[id] = { lo, hi }
		end
	end
	for id, list in pairs(S.groups) do
		S.groups[id] = Pills(id, list)
	end
	S.hist, S.ids = nil, nil
	S.state = "ready"
	if S.runner then
		S.runner:SetScript("OnUpdate", nil)
	end
	Ready()
end

local Step = Perf.Shared("MelloUI Map's level labels: the Questie pass", function()
	local L = QuestieLib()
	local maps = rawget(_G, "MelloUI_AreaMaps")
	if not (L and type(maps) == "table" and S.ids) then
		S.state = "idle"
		S.runner:SetScript("OnUpdate", nil)
		return
	end
	local t0 = debugprofilestop()
	local ids = S.ids
	local i = S.i
	while i < #ids do
		i = i + 1
		Take(ids[i], L, maps)
		if (i % 32) == 0 and debugprofilestop() - t0 >= T.STEP_MS then
			break
		end
	end
	S.i = i
	if i >= #ids then
		Finish()
	end
end, "update")

-- the pass started once wanted (a Questie layer on, and the map open or the minimap's layer drawing)
local function Want()
	if S.state ~= "idle" or not (On(T.ZONES) or On(T.CREATURES)) then
		return
	end
	local L = QuestieLib()
	if not (L and L.Npc and L.Npc.GetAllIds and L.Npc.GetAll) then
		return
	end
	local ok, ids = pcall(L.Npc.GetAllIds)
	if not ok or type(ids) ~= "table" then
		return
	end
	S.ids, S.i, S.hist = ids, 0, {}
	wipe(S.zone)
	wipe(S.groups)
	S.state = "building"
	S.runner = S.runner or CreateFrame("Frame")
	S.runner:SetScript("OnUpdate", Step)
end
Levels.Want = Want

function Levels.Ready()
	return S.state == "ready"
end

--------------------------------------------------------------------------------
-- (A) the line under a zone's name (MapLayers' names)
--------------------------------------------------------------------------------

function Levels.Line(id)
	if not On(T.ZONES) then
		return nil
	end
	if S.state ~= "ready" then
		Want()
		return nil
	end
	local z = S.zone[id]
	if not z then
		return nil
	end
	local r, g, b = ZoneColour(z[1], z[2])
	return Range(z[1], z[2]), r, g, b
end

--------------------------------------------------------------------------------
-- (E, H) the pills and the badges at a zone's zoom
--------------------------------------------------------------------------------

local measure = nil
local widths = {}
-- a text's width in the pills' font (measured once a text)
local function TextW(text)
	local w = widths[text]
	if w then
		return w
	end
	if not measure then
		measure = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		measure:Hide()
	end
	measure:SetText(text)
	w = Finite(measure:GetStringWidth())
	if not (w and w > 0) then
		return 7 * #text   -- (the face not read yet: a guess, measured again next time)
	end
	widths[text] = w
	return w
end

local function RankWord(rank)
	return rank == 1 and TEXT.elite or rank == 2 and TEXT.rareElite or rank == 3 and TEXT.boss
		or rank == 4 and TEXT.rare or nil
end

-- (a pin's: its spec's data; the minimap's mark hands its own)
local function PillTip(pin)
	local g = pin.spec and pin.spec.data or pin.data
	local W = MelloUI.Widgets
	local lines = {}
	for i, e in ipairs(g.names) do
		if i > T.NAMES_MAX then
			lines[#lines + 1] = W.Tr(TEXT.more):format(#g.names - T.NAMES_MAX)
			break
		end
		local line = e[1] .. "  " .. W.Tr(TEXT.level):format(Range(e[2], e[3]))
		local word = RankWord(e[4])
		if word then
			line = line .. "  " .. W.Tr(word)
		end
		lines[#lines + 1] = line
	end
	return W.Tr(TEXT.level):format(Range(g.lo, g.hi)), table.concat(lines, "\n")
end

local function BadgeTip(pin)
	local d = pin.spec and pin.spec.data or pin.data
	local W = MelloUI.Widgets
	local s = FishSkill()
	local body = s and W.Tr(TEXT.fishBite):format(d[1], d[2], s) or W.Tr(TEXT.fishNone)
	return W.Tr(TEXT.fishing):format(Range(d[1], d[2])), body
end

local function PillSpec(g)
	local mid = floor((g.lo + g.hi) / 2 + 0.5)
	local r, gg, b = Difficulty(mid)
	local text = Range(g.lo, g.hi)
	return {
		icon = "pad_pill_disc", size = T.PILL_H, wide = floor(TextW(text) + 2 * T.PILL_PAD + 0.5), rgb = { r, gg, b },
		disc = "innerPanel", discIcon = "pad_pill_disc", edge = T.EDGE,
		number = text, numberKey = "innerPanel", tip = PillTip, data = g, weight = g.n,
	}
end

local function BadgeSpec(id, lo, hi)
	local r, g, b = FishColour(lo, hi)
	local text = Range(lo, hi)
	-- (the sketch's H: a dark pill with an edge in the skill's colour -- the pill drawn in it, a dark one over it a
	-- pixel in)
	return {
		icon = "pad_pill_disc", size = T.BADGE_H, wide = floor(TextW(text) + T.HOOK + 3 * T.PILL_PAD / 2 + 0.5),
		rgb = { r, g, b }, core = "innerPanel", coreIcon = "pad_pill_disc", rim = T.EDGE,
		lead = T.HOOK_ART, leadSize = T.HOOK, leadX = 3,
		number = text, numberRGB = { r, g, b }, tip = BadgeTip, data = { lo, hi, id },
	}
end

local function DropZone(id)
	local z = S.built[id]
	if not z then
		return
	end
	for _, key in ipairs(z.creatures) do
		S.pins:Remove(T.CREATURES, key)
	end
	for _, key in ipairs(z.fishing) do
		S.pins:Remove(T.FISHING, key)
	end
	S.built[id] = nil
	S.builtCount = S.builtCount - 1
end

local function DropZones()
	for id in pairs(S.built) do
		DropZone(id)
	end
	S.cut = nil
end
Levels.Stale = DropZones

local function BuildZone(id)
	local z = { creatures = {}, fishing = {}, gen = S.gen }
	if On(T.CREATURES) and S.state == "ready" then
		for i, g in ipairs(S.groups[id] or {}) do
			local key = "lv:" .. id .. ":" .. i
			S.pins:SetAt(T.CREATURES, key, id, g.x, g.y, PillSpec(g))
			z.creatures[#z.creatures + 1] = key
		end
	end
	local waters = ns.MapWaters and ns.MapWaters[id]
	local lo, hi = FishRange(id)
	if On(T.FISHING) and waters and lo then
		for i = 1, #waters, 3 do
			local key = "fish:" .. id .. ":" .. i
			S.pins:SetAt(T.FISHING, key, id, waters[i], waters[i + 1], BadgeSpec(id, lo, hi))
			z.fishing[#z.fishing + 1] = key
		end
	end
	S.built[id] = z
	S.builtCount = S.builtCount + 1
end

-- the zones in view at a zone's zoom laid (a few a frame), the farthest seen last let go past KEEP
local function Zones()
	local c = S.canvas
	S.cut = c.cuts
	if c.z < T.ZONE_FROM or not (On(T.CREATURES) or On(T.FISHING)) then
		return
	end
	if On(T.CREATURES) and S.state ~= "ready" then
		Want()
	end
	local box = c.box
	S.gen = S.gen + 1
	local gen, built, pending = S.gen, 0, false
	for _, p in ipairs(c.places or {}) do
		if (p.kind == "zone" or p.kind == "city") and p.left < box[3] and p.left + p.w > box[1]
			and p.top < box[4] and p.top + p.h > box[2] then
			local z = S.built[p.id]
			if z then
				z.gen = gen
			elseif built < T.BUILD_PER_FRAME then
				BuildZone(p.id)
				S.built[p.id].gen = gen
				built = built + 1
			else
				pending = true
			end
		end
	end
	while S.builtCount > T.KEEP do
		local oldest, at
		for id, z in pairs(S.built) do
			if z.gen < gen and (not at or z.gen < at) then
				oldest, at = id, z.gen
			end
		end
		if not oldest then
			break
		end
		DropZone(oldest)
	end
	if pending then
		S.cut = nil
	end
	if built > 0 then
		S.pins:Lay()
	end
end

function Levels.Init(canvas, pins)
	S.canvas, S.pins = canvas, pins
	pins:Layer(T.CREATURES, T.ORDER.creatures, { minZ = T.ZONE_FROM, cull = true })
	pins:Layer(T.FISHING, T.ORDER.fishing, { minZ = T.ZONE_FROM, cull = true })
end

function Levels.Open()
	S.shown = true
	S.cut = nil
	fishSkill = nil   -- (your skill read again at each open: a skill gained while the map was closed shows)
	if On(T.ZONES) or On(T.CREATURES) then
		Want()
	end
end

function Levels.Close()
	S.shown = false
	if S.pins then
		DropZones()
	end
end

function Levels.Tick()
	if S.shown and S.canvas and S.cut ~= S.canvas.cuts then
		Zones()
	end
end

-- a layer's switch turned (Map.lua's SetLayer): the zones laid again of what is on now, the names and the minimap too
function Levels.Changed(key)
	if key ~= T.ZONES and key ~= T.CREATURES and key ~= T.FISHING then
		return
	end
	fishSkill = nil
	if S.pins then
		DropZones()
	end
	if On(T.ZONES) or On(T.CREATURES) then
		Want()
	end
	Levels.Mini(Levels.miniEnabled)
	if Levels.relabel then
		Levels.relabel()
	end
end

-- the pass done: the names' lines, the pills and the minimap's again
Ready = function()
	if S.pins then
		DropZones()
	end
	if Levels.relabel and S.shown then
		Levels.relabel()
	end
	Levels.MiniStale()
end

--------------------------------------------------------------------------------
-- The minimap: the same pills and badges round you, on Route's minimap layer
--------------------------------------------------------------------------------

local mini = { marks = {}, n = 0, list = nil, want = false, events = nil, mapID = nil }
Levels.mini = mini

local function MiniLeave(f)
	if GameTooltip:GetOwner() == f then
		GameTooltip:Hide()
	end
end

local function MiniEnter(f)
	local title, body
	if f.kind == "pill" then
		title, body = PillTip({ data = f.data })
	else
		title, body = BadgeTip({ data = f.data })
	end
	local P = MelloUI.Look and MelloUI.Look.TipPalette and MelloUI.Look.TipPalette() or MelloUI.Palette
	local t, m = P.text, P.mutedText
	GameTooltip:SetOwner(f, "ANCHOR_CURSOR")
	GameTooltip:SetText(title or "", t[1], t[2], t[3])
	if body then
		GameTooltip:AddLine(body, m[1], m[2], m[3], true)
	end
	GameTooltip:Show()
end

-- a mark (made the first time it is needed): its pill, its edge, its text, its hook; the mouse's motion only
local function MiniMark(i, frame)
	local f = mini.marks[i]
	if not f then
		local W = MelloUI.Widgets
		f = CreateFrame("Frame", nil, frame)
		f:SetFrameLevel(frame:GetFrameLevel() + 1)
		f.edge = f:CreateTexture(nil, "ARTWORK", nil, 0)
		f.edge:SetPoint("TOPLEFT", f, "TOPLEFT", -T.EDGE, T.EDGE)
		f.edge:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", T.EDGE, -T.EDGE)
		W.Paint(f.edge, "innerPanel", "vertex")
		f.pill = f:CreateTexture(nil, "ARTWORK", nil, 1)
		f.pill:SetAllPoints(f)
		f.hook = f:CreateTexture(nil, "ARTWORK", nil, 2)
		f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		if f.SetMouseClickEnabled then
			f:EnableMouse(true)
			f:SetMouseClickEnabled(false)
			f:SetScript("OnEnter", MiniEnter)
			f:SetScript("OnLeave", MiniLeave)
			f:SetScript("OnHide", MiniLeave)
		end
		mini.marks[i] = f
	end
	return f
end

-- your zone's pills and badges in Route's yards (once a zone; again at a switch, a level, a skill or the pass's end)
local EMPTY = {}
local function MiniList()
	local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
	id = ok and Finite(id) or nil
	if mini.list and mini.mapID == id then
		return mini.list
	end
	local Route = MelloUI.Route
	local list = {}
	mini.list, mini.mapID = list, id
	if not (id and Route and Route.ToYards) then
		return EMPTY
	end
	if On(T.CREATURES) then
		if S.state ~= "ready" then
			Want()
		else
			for _, g in ipairs(S.groups[id] or EMPTY) do
				local okY, cont, x, y = pcall(Route.ToYards, id, g.x, g.y)
				if okY and cont and x and y then
					list[#list + 1] = { cont = cont, x = x, y = y, kind = "pill", data = g }
				end
			end
		end
	end
	local waters = ns.MapWaters and ns.MapWaters[id]
	local lo, hi = FishRange(id)
	if On(T.FISHING) and waters and lo then
		for i = 1, #waters, 3 do
			local okY, cont, x, y = pcall(Route.ToYards, id, waters[i], waters[i + 1])
			if okY and cont and x and y then
				list[#list + 1] = { cont = cont, x = x, y = y, kind = "badge", data = { lo, hi, id } }
			end
		end
	end
	return list
end

local function MiniLook(f, p)
	local W = MelloUI.Widgets
	local k = T.MINI_SCALE
	local text, h, w
	if p.kind == "pill" then
		local g = p.data
		text = Range(g.lo, g.hi)
		h = floor(T.PILL_H * k + 0.5)
		w = floor((TextW(text) * 0.85 + 2 * T.PILL_PAD) * k + 0.5)
		local r, gg, b = Difficulty(floor((g.lo + g.hi) / 2 + 0.5))
		MelloUI.Icons.Set(f.pill, "pad_pill_disc", w)
		local P = rawget(MelloUI, "Painter")
		if P and P.Unpaint then
			P.Unpaint(f.pill, "vertex")
		end
		f.pill:SetVertexColor(r, gg, b)
		W.Paint(f.edge, "innerPanel", "vertex")
		W.Paint(f.text, "innerPanel", "text")
		f.text:ClearAllPoints()
		f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
		f.hook:Hide()
	else
		local d = p.data
		text = Range(d[1], d[2])
		h = floor(T.BADGE_H * k + 0.5)
		local hs = floor(T.HOOK * k + 0.5)
		w = floor((TextW(text) * 0.85 + T.HOOK + 3 * T.PILL_PAD / 2) * k + 0.5)
		MelloUI.Icons.Set(f.pill, "pad_pill_disc", w)
		W.Paint(f.pill, "innerPanel", "vertex")
		local r, g, b = FishColour(d[1], d[2])
		local P = rawget(MelloUI, "Painter")
		if P and P.Unpaint then
			P.Unpaint(f.text, "text")
			P.Unpaint(f.edge, "vertex")
		end
		f.text:SetTextColor(r, g, b)
		f.edge:SetVertexColor(r, g, b)   -- (the sketch's H: the edge in the skill's colour)
		f.hook:ClearAllPoints()
		f.hook:SetPoint("LEFT", f, "LEFT", 2, 0)
		f.hook:SetSize(hs, hs)
		MelloUI.Icons.Set(f.hook, T.HOOK_ART, hs)
		f.hook:Show()
		f.text:ClearAllPoints()
		f.text:SetPoint("CENTER", f, "CENTER", floor(hs / 2 + 0.5), 0)
	end
	MelloUI.Icons.Set(f.edge, "pad_pill_disc", w + 2 * T.EDGE)
	f.text:SetText(text)
	f:SetSize(w, h)
	f.size = h   -- (Route's MarkPlace keeps a mark's size by this: the oblong size is ours)
	f.kind, f.data = p.kind, p.data
	f.w = w
end

-- Route's minimap layer's tick (cont nil: hidden)
function Levels.MiniDraw(cont, round, R, RX, RY)
	local Route = MelloUI.Route
	local frame = Route.MinimapFrame()
	local n = 0
	if cont and frame then
		local Offset = Route.MinimapOffset
		for _, p in ipairs(MiniList()) do
			if p.cont == cont then
				local gx, gy = Offset(p.x, p.y)
				local m = T.PILL_H
				local on
				if round then
					on = gx * gx + gy * gy <= (R - m) * (R - m)
				else
					on = abs(gx) <= RX - m and abs(gy) <= RY - m
				end
				if on then
					n = n + 1
					local f = MiniMark(n, frame)
					if f.at ~= p then
						f.at = p
						MiniLook(f, p)
					end
					Route.MarkPlace(f, f.size, frame, "CENTER", gx, gy)
				end
			end
		end
	end
	for i = n + 1, mini.n do
		mini.marks[i]:Hide()
	end
	mini.n = n
end

function Levels.MiniStale()
	mini.list = nil
	for _, f in ipairs(mini.marks) do
		f.at = nil
	end
end

local MiniEvent = Perf.Shared("MelloUI Map's level labels' minimap events", function(_, event)
	if event == "SKILL_LINES_CHANGED" then
		fishSkill = nil
	end
	Levels.MiniStale()
	if S.pins and (event == "PLAYER_LEVEL_UP" or event == "SKILL_LINES_CHANGED") then
		DropZones()   -- (the colours are by your level and your skill)
		if Levels.relabel and S.shown then
			Levels.relabel()
		end
	end
end, "event")

local EVENTS = { "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED" }

-- (Map.lua: its OnEnable and OnDisable, and a switch turned) the minimap's wanted: the map on, a pill or badge layer on,
-- Route's minimap layer there
function Levels.Mini(enabled)
	Levels.miniEnabled = enabled
	local R = MelloUI.Route
	local can = type(R) == "table" and type(R.WantMinimap) == "function" and type(R.ToYards) == "function"
	local on = enabled and can and (On(T.CREATURES) or On(T.FISHING)) and true or false
	mini.want, mini.list = on, nil
	if on and not mini.events then
		mini.events = CreateFrame("Frame")
		Perf.SetScript(mini.events, "OnEvent", MiniEvent)
	end
	if mini.events then
		for _, event in ipairs(EVENTS) do
			if on then
				mini.events:RegisterEvent(event)
			else
				mini.events:UnregisterEvent(event)
			end
		end
	end
	if can then
		R.WantMinimap(T.OWNER, on and Levels.MiniDraw or nil)
	end
end

return Levels
