--------------------------------------------------------------------------------
-- MelloUI - Group Frames: spell groups (1.2.4, from the user's retail copy:
-- docs/plans/forever-preview-update.md phase 2; the picked sketch B)
--
-- The user: "a group of spells is the thing you drag and place on the frame,
-- not each spell on its own; a group is editable -- I can switch single spells
-- in it on or off for tracking". A placed group is one indicator of the list
-- (kind "group"): its look, place, size, whose and when as every indicator's,
-- and its own: which group, the way it grows, how many show, per line, the
-- room between them, its order, its spells switched off or on (only what
-- differs from the data's start: a data refresh flows in), the spells taken
-- out, added or put in your own order, a colour of its own per spell (your
-- order: each spell its own slot).
-- The spells: WoW Forever's own data, sorted by rule (GroupSpells.lua, written
-- by Tools/group_spells_forever.py; Forever has no specs: a class's own).
-- Yours (your class's): Heals over time, Shields, Your other buffs. Everyone's
-- (any member, any class): Defensives from others, Their own defensives, Group
-- defensives, Haste and power, Speed and freedom, Group buffs, Lockouts (one
-- with no spell in the data is left out of the tray). Debuffs by their kind
-- (the game never lets a friend's debuff be picked by spell): Dispellable,
-- Boss, Crowd control. A lockout is picked by spell only where the game says
-- its spell is never secret (C_Secrets.GetSpellAuraSecrecy: AuraContainerUtil's
-- CanApplyIdentityCandidateFilters).
--   SG.DEFS / SG.DEF[key]            the groups: key, label, scope, tip
--   SG.List(ind, specKey) -> entries  a placed group's spells (its adds, its
--                                      order; without the ones taken out)
--   SG.IsOn(ind, e), SG.Trackable(ind, e)
--   SG.Filter(ind), SG.Candidates(ind) -> cand, sig, SG.SlotEntries(ind)
--   SG.Starter(class) -> list         a class's spell groups to start with
--   SG.New(group, point) -> fields    a group put on the frame
--   SG.Move(from, e, to), SG.Add(ind, typed)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local RD = ns.RD
local DATA = ns.GroupSpells
if not (DATA and RD) then
	return
end
local Plain = MelloUI.Safe.Value
local Text = MelloUI.Safe.Text

local SG = {}
ns.SpellGroups = SG
RD.SpellGroups = SG   -- (the tests')

local EMPTY = {}

-- the groups (plain names: memory plain-feature-names)
SG.DEFS = {
	{ key = "hot", label = "Heals over time", scope = "own", tip = "Your heals over time on them." },
	{ key = "shield", label = "Shields", scope = "own", tip = "Your absorbs on them." },
	{ key = "yours", label = "Your other buffs", scope = "own",
	  tip = "The rest you put on them: Thorns, Fear Ward, Abolish Poison." },
	{ key = "external", label = "Defensives from others", scope = "all",
	  tip = "Anyone's defensive cast on them: Blessing of Protection, Blessing of Sacrifice." },
	{ key = "defensive", label = "Their own defensives", scope = "all",
	  tip = "Their own cooldowns, whatever their class: Shield Wall, Evasion, Ice Block." },
	{ key = "raidcd", label = "Group defensives", scope = "all",
	  tip = "Cooldowns on the whole group or an area." },
	{ key = "power", label = "Haste and power", scope = "all",
	  tip = "Power and mana given to them: Power Infusion, Innervate, Mana Tide." },
	{ key = "movement", label = "Speed and freedom", scope = "all",
	  tip = "Speed and freedom on them: Blessing of Freedom, Aspect of the Pack." },
	{ key = "raidbuff", label = "Group buffs", scope = "all",
	  tip = "The lasting buffs the group shares: Power Word: Fortitude, Blessing of Kings, Battle Shout." },
	{ key = "lockout", label = "Lockouts", scope = "all", harmful = true,
	  tip = "What they cannot have again yet: Forbearance, Weakened Soul. The game shows only those it never hides." },
	{ key = "dispel", label = "Dispellable debuffs", scope = "debuff", tip = "A debuff on them by its kind." },
	{ key = "boss", label = "Boss debuffs", scope = "debuff", tip = "A boss's debuffs on them." },
	{ key = "cc", label = "Crowd control", scope = "debuff", tip = "Stuns, roots and fears on them." },
}
SG.DEF = {}
for _, d in ipairs(SG.DEFS) do
	SG.DEF[d.key] = d
end

-- the dispellable group's kinds, the debuff groups' own filters (RD.KINDS'
-- words: a friend's debuff by its kind, never by spell)
SG.TYPES = { "Magic", "Curse", "Disease", "Poison" }
SG.DISPEL = { { value = "mine", label = "Dispellable by you" }, { value = "group", label = "Dispellable by your group" },
	{ value = "any", label = "Any dispellable" } }
local DISPEL_OK = { mine = true, group = true, any = true }
SG.GROWS = { RIGHT = true, LEFT = true, DOWN = true, UP = true }
SG.ORDERS = { { value = "time", label = "Time left" }, { value = "applied", label = "As they came" },
	{ value = "list", label = "Your order" } }
local ORDER_OK = { time = true, applied = true, list = true }

--------------------------------------------------------------------------------
-- The data, read when first asked (nothing at login)
--------------------------------------------------------------------------------

local classes = nil
function SG.Classes()
	if not classes then
		classes = {}
		for k, v in pairs(DATA) do
			if type(v) == "table" then
				classes[#classes + 1] = k
			end
		end
		table.sort(classes)
	end
	return classes
end

local parsed = {}   -- [class] = { [group] = { entry, ... } }
local function Parse(class)
	local p = parsed[class]
	if p then
		return p
	end
	p = {}
	for group, list in pairs(DATA[class] or EMPTY) do
		local out = {}
		for i, row in ipairs(list) do
			local ids = {}
			for j = 2, #row do
				ids[#ids + 1] = row[j]
			end
			out[i] = { main = row[1], ids = ids, off = row.off and true or false, class = class }
		end
		p[group] = out
	end
	parsed[class] = p
	return p
end

-- every entry by its main spell (a typed or moved spell's IDs)
local catalogue = nil
local function Catalogue()
	if not catalogue then
		catalogue = {}
		for _, class in ipairs(SG.Classes()) do
			for _, list in pairs(Parse(class)) do
				for _, e in ipairs(list) do
					if not catalogue[e.main] then
						catalogue[e.main] = e
					end
				end
			end
		end
	end
	return catalogue
end

-- a list key's class ("DRUID:2": the druid; Forever's data has no specs)
function SG.SpecOf(specKey)
	specKey = specKey or RD:Spec()
	return specKey:match("^([^:]+)")
end

local entries = {}   -- ["group|class"] = { entry, ... }
function SG.Entries(group, class)
	local key = group .. "|" .. tostring(class)
	local out = entries[key]
	if out then
		return out
	end
	out = {}
	local def = SG.DEF[group]
	if def and def.scope == "debuff" then
		if group == "dispel" then
			for _, t in ipairs(SG.TYPES) do
				out[#out + 1] = { main = t, kind = t, ids = EMPTY, off = false }
			end
		else
			out[1] = { main = group, kind = group, ids = EMPTY, off = false, fixed = true }
		end
	elseif def and def.scope == "own" then
		for _, e in ipairs(Parse(class or "")[group] or EMPTY) do
			out[#out + 1] = e
		end
	elseif def then
		local seen = {}
		for _, c in ipairs(SG.Classes()) do
			for _, e in ipairs(Parse(c)[group] or EMPTY) do
				if not seen[e.main] then
					seen[e.main] = true
					out[#out + 1] = e
				end
			end
		end
	end
	entries[key] = out
	return out
end

-- a spell's name and picture: the game's (plain only)
function SG.Name(e)
	if e.kind then
		local d = SG.DEF[e.kind]
		return d and d.label or e.kind
	end
	if e.name then
		return e.name
	end
	return RD:SpellName(e.main) or ("Spell " .. tostring(e.main))
end

function SG.Icon(e)
	local CSpell = rawget(_G, "C_Spell")
	if e.kind or not (CSpell and type(CSpell.GetSpellTexture) == "function") then
		return nil
	end
	local ok, tex = pcall(CSpell.GetSpellTexture, e.main)
	return ok and Plain(tex) or nil
end

-- a lockout the game lets be picked on a friend: its spell never secret
local never = {}
function SG.NeverSecret(id)
	local v = never[id]
	if v == nil then
		v = false
		local S, E = rawget(_G, "C_Secrets"), rawget(_G, "Enum")
		local level = E and E.SecrecyLevel and E.SecrecyLevel.NeverSecret
		if S and type(S.GetSpellAuraSecrecy) == "function" and level ~= nil then
			local ok, got = pcall(S.GetSpellAuraSecrecy, id)
			v = ok and Plain(got) == level or false
		end
		never[id] = v
	end
	return v
end

--------------------------------------------------------------------------------
-- A placed group
--------------------------------------------------------------------------------

function SG.Label(ind)
	local d = SG.DEF[ind.group]
	return d and d.label or "?"
end

-- (the lists' changes, another spec, a typed spell's IDs: the groups' answers
-- worked out again on their next ask -- registered at load, so before the
-- frames' own listener)
local version = 0
MelloUI:On("groupframes", function(what)
	if what == "list" or what == "spec" or what == "ids" then
		version = version + 1
	end
end, "GroupFrames.spellgroups")

-- an added spell's entry (a typed one, or one moved in): the data's own IDs,
-- else every ID of its name the gathering found
local function Added(main, name)
	local e = Catalogue()[main]
	if e then
		return e
	end
	local set = RD:Ids(name, main)
	local ids = {}
	for id in pairs(set) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	return { main = main, ids = ids, name = name, off = false, added = true }
end

function SG.List(ind, specKey)
	local out = {}
	local out_ = ind.out or EMPTY
	for _, e in ipairs(SG.Entries(ind.group, SG.SpecOf(specKey))) do
		if not out_[e.main] then
			out[#out + 1] = e
		end
	end
	local adds = {}
	for main in pairs(ind.add or EMPTY) do
		adds[#adds + 1] = main
	end
	table.sort(adds)
	for _, main in ipairs(adds) do
		if not out_[main] then
			local seen = false
			for _, e in ipairs(out) do
				if e.main == main then
					seen = true
				end
			end
			if not seen then
				out[#out + 1] = Added(main, ind.add[main])
			end
		end
	end
	local ranks = ind.ranks
	if type(ranks) == "table" and #ranks > 0 then
		local at = {}
		for i, main in ipairs(ranks) do
			at[main] = i
		end
		local was = {}
		for i, e in ipairs(out) do
			was[e] = i
		end
		table.sort(out, function(a, b)
			local ra, rb = at[a.main] or (1000 + was[a]), at[b.main] or (1000 + was[b])
			return ra < rb
		end)
	end
	return out
end

function SG.IsOn(ind, e)
	local v = ind.spells and ind.spells[e.main]
	if v ~= nil then
		return v and true or false
	end
	return not e.off
end

-- a spell the game lets the group show (a lockout: never secret)
function SG.Trackable(ind, e)
	if ind.group ~= "lockout" or e.kind then
		return true
	end
	for _, id in ipairs(e.ids) do
		if SG.NeverSecret(id) then
			return true
		end
	end
	return false
end

function SG.Filter(ind)
	local g = ind.group
	if g == "dispel" then
		local k = RD.KIND[ind.what]
		return k and k.filter or "HARMFUL|RAID"
	elseif g == "boss" or g == "lockout" then
		return "HARMFUL"
	elseif g == "cc" then
		return "HARMFUL|CROWD_CONTROL"
	end
	return ind.whose == "any" and "HELPFUL" or "HELPFUL|PLAYER"
end

-- the game's sort for the order (your order: each spell its own slot)
function SG.Sort(ind)
	local M = rawget(_G, "AuraContainerSortMethod")
	if type(M) ~= "table" then
		return nil
	end
	if ind.order == "time" then
		return M.Expiration or M.Default
	elseif ind.order == "applied" then
		return M.AuraInstanceIDOnly or M.Default
	end
	return M.Default
end

local answers = setmetatable({}, { __mode = "k" })   -- [ind] = { ver, cand, sig, slots }

local function IdsOf(ind, e, set)
	local lockout = ind.group == "lockout"
	for _, id in ipairs(e.ids) do
		if not lockout or SG.NeverSecret(id) then
			set[id] = true
		end
	end
end

local function SigOf(set)
	local keys = {}
	for k in pairs(set) do
		keys[#keys + 1] = tostring(k)
	end
	table.sort(keys)
	return table.concat(keys, ",")
end

local function Answer(ind)
	local a = answers[ind]
	if a and a.ver == version and a.spec == RD:Spec() then
		return a
	end
	a = { ver = version, spec = RD:Spec(), slots = {} }
	answers[ind] = a
	local list = SG.List(ind)
	local g = ind.group
	if g == "boss" then
		a.cand, a.sig = { isBossAura = true }, "boss"
	elseif g == "cc" then
		a.cand, a.sig = nil, "cc"
	elseif g == "dispel" then
		local types = {}
		for _, e in ipairs(list) do
			if SG.IsOn(ind, e) then
				types[e.kind] = true
			end
		end
		a.cand, a.sig = { includeDispelTypes = types }, "types:" .. SigOf(types)
	else
		local set = {}
		for _, e in ipairs(list) do
			if SG.IsOn(ind, e) then
				IdsOf(ind, e, set)
				-- (your order: each spell its own slot, up to the most shown)
				if #a.slots < (ind.max or 3) and SG.Trackable(ind, e) then
					local one = {}
					IdsOf(ind, e, one)
					a.slots[#a.slots + 1] = { e = e, cand = { includeSpellIDs = one }, sig = SigOf(one) }
				end
			end
		end
		a.cand, a.sig = { includeSpellIDs = set }, "ids:" .. SigOf(set)
	end
	return a
end

function SG.Candidates(ind)
	local a = Answer(ind)
	return a.cand, a.sig
end

function SG.SlotEntries(ind)
	return Answer(ind).slots
end

-- a spell's own colour in your order (a square, a bar), else the group's
function SG.ColourOf(ind, e)
	local c = ind.colours and e and ind.colours[e.main]
	if type(c) == "table" and type(c[1]) == "number" then
		return c
	end
	return nil
end

--------------------------------------------------------------------------------
-- Fields, starters, edits
--------------------------------------------------------------------------------

local function Clamp(v, lo, hi, def)
	v = tonumber(v) or def
	return math.max(lo, math.min(hi, v))
end

-- a group's own fields, filled where missing (RD:Fill: the fields every
-- indicator has)
function SG.Fill(t)
	t.group = SG.DEF[t.group] and t.group or "hot"
	local def = SG.DEF[t.group]
	t.grow = SG.GROWS[t.grow] and t.grow or "LEFT"
	t.perLine = Clamp(t.perLine, 1, 10, 4)
	t.max = Clamp(t.max, 1, 10, 3)
	t.spacing = Clamp(t.spacing, 0, 8, 1)
	t.order = ORDER_OK[t.order] and t.order or "time"
	if def.scope ~= "debuff" and not def.harmful then
		t.colourBy = "mine"
	end
	t.what = t.group == "dispel" and (DISPEL_OK[t.what] and t.what or "mine") or nil
	for _, k in ipairs({ "spells", "out", "add", "colours" }) do
		if type(t[k]) ~= "table" then
			t[k] = {}
		end
	end
	if type(t.ranks) ~= "table" then
		t.ranks = {}
	end
	t.spell, t.name = nil, nil
	return t
end

-- a group put on the frame at `point`: growing away from its edge
function SG.New(group, point)
	local def = SG.DEF[group] or SG.DEF.hot
	local px = point and (point:find("RIGHT") and "LEFT" or "RIGHT") or "RIGHT"
	return { kind = "group", group = def.key, point = point or "TOPRIGHT", grow = px, look = "icon", size = 10,
		max = 3, perLine = 4, whose = def.scope == "own" and "mine" or "any",
		colourBy = def.scope == "debuff" and "type" or nil, colour = "WHITE_FONT_COLOR" }
end

-- a class's spell groups to start with: a healer's (heals over time or
-- shields of its own) its heals over time, shields, others' defensives, what
-- it can dispel; the rest their own defensives, others' on them, what the
-- group can dispel; every one the boss's debuffs
local function G(group, point, extra)
	local t = SG.New(group, point)
	for k, v in pairs(extra or EMPTY) do
		t[k] = v
	end
	return t
end

function SG.Starter(class)
	if not class then
		return nil
	end
	local out = {}
	local hots, shields = #SG.Entries("hot", class), #SG.Entries("shield", class)
	if hots + shields > 0 then
		if hots > 0 then
			out[#out + 1] = G("hot", "TOPRIGHT", { grow = "LEFT", max = 3, size = 10, colour = "GREEN_FONT_COLOR" })
		end
		if shields > 0 then
			out[#out + 1] = G("shield", "RIGHT", { grow = "LEFT", max = 2, size = 8, look = "square",
				colour = "NORMAL_FONT_COLOR" })
		end
		out[#out + 1] = G("external", "CENTER", { grow = "RIGHT", max = 1, size = 13 })
		out[#out + 1] = G("dispel", "BOTTOM", { grow = "UP", max = 2, size = 2, look = "bar", what = "mine" })
	else
		out[#out + 1] = G("defensive", "CENTER", { grow = "RIGHT", max = 1, size = 13 })
		out[#out + 1] = G("external", "TOPRIGHT", { grow = "LEFT", max = 2, size = 10 })
		out[#out + 1] = G("dispel", "BOTTOM", { grow = "UP", max = 2, size = 2, look = "bar", what = "group" })
	end
	out[#out + 1] = G("boss", "LEFT", { grow = "RIGHT", max = 1, size = 12 })
	return out
end

-- a spell switched on or off (only a change from its start is kept)
function SG.Switch(ind, e, on)
	ind.spells = ind.spells or {}
	if on == (not e.off) then
		ind.spells[e.main] = nil
	else
		ind.spells[e.main] = on and true or false
	end
end

-- a spell moved from one group into another (its own taken out, the other's
-- added; back home: simply not taken out there)
function SG.Move(from, e, to)
	if from == to or e.kind then
		return
	end
	from.out = from.out or {}
	from.out[e.main] = true
	if from.add then
		from.add[e.main] = nil
	end
	to.out = to.out or {}
	to.add = to.add or {}
	if to.out[e.main] then
		to.out[e.main] = nil
	else
		to.add[e.main] = SG.Name(e)
	end
end

-- a typed spell (its name or ID) added to a group; nil when the game knows
-- no spell of that name
function SG.Add(ind, typed)
	local id, name = RD:Resolve(typed)
	if not id then
		return nil
	end
	ind.add = ind.add or {}
	ind.add[id] = name or SG.Name({ main = id })
	if ind.out then
		ind.out[id] = nil
	end
	RD:Ids(ind.add[id], id)
	return id
end

-- your order: the list as it shows now, `e` put before `before` (nil: last)
function SG.Rank(ind, list, e, before)
	local ranks = {}
	for _, x in ipairs(list) do
		if x ~= e then
			if x == before then
				ranks[#ranks + 1] = e.main
			end
			ranks[#ranks + 1] = x.main
		end
	end
	if not before then
		ranks[#ranks + 1] = e.main
	end
	ind.ranks = ranks
end

-- a placed group's typed spells' ranks gathered (RD:GatherAll)
function SG.Gather(t)
	for main, name in pairs(t.add or EMPTY) do
		if type(name) == "string" and not Catalogue()[main] then
			RD:Ids(name, main)
		end
	end
end

-- a class's name and colour (the game's own)
function SG.ClassName(class)
	local names = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
	return type(names) == "table" and Text(names[class]) or class
end

function SG.ClassColour(class)
	local CC = rawget(_G, "C_ClassColor")
	if CC and type(CC.GetClassColor) == "function" then
		local ok, c = pcall(CC.GetClassColor, class)
		if ok and type(c) == "table" and c.GetRGB then
			return c:GetRGB()
		end
	end
	local t = rawget(_G, "RAID_CLASS_COLORS")
	t = type(t) == "table" and t[class]
	if t then
		return t.r, t.g, t.b
	end
	return 1, 1, 1
end
