--------------------------------------------------------------------------------
-- MelloUI - Services
--
-- Service icons under the minimap (and an optional minimap button that opens
-- the list of them) that lead you to the nearest repair, mailbox,
-- innkeeper, flight master, auction house, bank, trainer, barber or
-- transmogrifier. Vanilla service NPCs and mailboxes come from the Quest
-- List data (placed by the client), flight masters from the flight point
-- data, and anything new (Forever's barbers and transmogrifiers, NPCs the
-- database does not know) is remembered the first time you use it. "Nearest"
-- is by route cost through the Route module, so a flight master across the
-- river is not "near" when the bridge is a long way round.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Services")
local C_Timer = Perf.C_Timer

local M = MelloUI:RegisterModule("Services", {
	title = "Services",
	keep = { "learned" },   -- services recorded by hand (when Route's store is missing): never in a profile
	desc = "Service icons under the minimap that route you to the nearest repair, mailbox, innkeeper, flight master, auction house, bank, trainer, barber or transmogrifier.",
	icon = "Interface\\Icons\\Ability_Repair",
	flavour = "Repair, mailbox, innkeeper, bank... the nearest one is a click under the minimap.",
	group = "Quests and travel",
	area = { key = "services", follows = "MinimapPanel" },   -- the bar under the minimap: as the minimap
	enabledByDefault = true,
	defaults = {
		showBar = true,
		barOffset = -26,
		roundIcons = true,
		showButton = false,
		angle = 205,
	},
	options = {
		{ type = "toggle", key = "showBar", name = "Icon Bar Under The Minimap",
		  desc = "Two rows of service icons under the minimap; it moves with the minimap in Edit Mode. Click an icon to route to the nearest one by road, right-click to stop the route. A grey icon has none known on this continent yet. With the painted look, the square minimap in the Window frame or Single rail border, and \"Square minimap: merge with the Services bar\" on (Dynamic UI Modification), the icons sit inside the minimap's frame." },
		{ type = "slider", key = "barOffset", parent = "showBar", name = "Bar Distance From The Minimap", min = -80, max = 20, step = 2,
		  desc = "How far under the minimap the icons sit. Not used while they are merged into the square minimap's frame." },
		{ type = "toggle", key = "roundIcons", parent = "showBar", name = "Round Icons",
		  desc = "Show the service icons as round medallions in a round rim instead of squares." },
		{ type = "toggle", key = "showButton", name = "Minimap Button",
		  desc = "Also show a round button on the minimap's edge that opens the list of the nearest services; drag it to move it, right-click it to stop the route. /services opens the same list." },
	},
})

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua); Plain(v)
-- is v, or nil when v is secret
local IsSecret = MelloUI.Safe.IsSecret
local Plain = MelloUI.Safe.Value

local function VectorXY(pos)
	if type(pos) ~= "table" then
		return nil, nil
	end
	local x, y = Plain(pos.x), Plain(pos.y)
	if (x == nil or y == nil) and type(pos.GetXY) == "function" then
		local ok, gx, gy = pcall(pos.GetXY, pos)
		if ok then
			x, y = Plain(gx), Plain(gy)
		end
	end
	return x, y
end

local function Route()
	local R = MelloUI.Route
	if R and R.isEnabled and R.Cheapest then
		return R
	end
	return nil
end

local function Data()
	return MelloUI_QuestListData
end

local function Yards(d)
	if d >= 1000 then
		return string.format("%.1f km", d / 1000)
	end
	return string.format("%d yd", d)
end

local function PlayerMapPoint()
	local okM, mapID = pcall(C_Map.GetBestMapForUnit, "player")
	mapID = okM and Plain(mapID) or nil
	if not mapID then
		return nil
	end
	local okP, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
	local x, y
	if okP then
		x, y = VectorXY(pos)
	end
	if not (x and y) then
		return nil
	end
	return mapID, x, y
end

local function NPCName()
	for _, unit in ipairs({ "npc", "target" }) do
		local ok, name = pcall(UnitName, unit)
		if ok and type(name) == "string" and not IsSecret(name) and name ~= "" then
			return name
		end
	end
	return nil
end

-- The NPC's title line ("Warrior Trainer") from its tooltip.
local function NPCSubName()
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then
		return ""
	end
	local ok, data = pcall(C_TooltipInfo.GetUnit, "npc")
	if ok and type(data) == "table" and type(data.lines) == "table" and data.lines[2] then
		local text = Plain(data.lines[2].leftText)
		if type(text) == "string" and not text:find("^Level ") then
			return text
		end
	end
	return ""
end

--------------------------------------------------------------------------------
-- Kinds
--------------------------------------------------------------------------------

local KINDS = {
	{ key = "repair", label = "Repair", data = "repair", event = "MERCHANT_SHOW", icon = "Interface/Minimap/Tracking/Repair" },
	{ key = "mailbox", label = "Mailbox", data = "mailbox", event = "MAIL_SHOW", object = true, icon = "Interface/Minimap/Tracking/Mailbox" },
	{ key = "innkeeper", label = "Innkeeper", data = "innkeeper", icon = "Interface/Minimap/Tracking/Innkeeper" },
	{ key = "flight", label = "Flight Master", taxi = true, event = "TAXIMAP_OPENED", icon = "Interface/Minimap/Tracking/FlightMaster" },
	{ key = "auction", label = "Auction House", data = "auction", event = "AUCTION_HOUSE_SHOW", icon = "Interface/Minimap/Tracking/Auctioneer" },
	{ key = "banker", label = "Bank", data = "banker", event = "BANKFRAME_OPENED", icon = "Interface/Minimap/Tracking/Banker" },
	{ key = "classtrainer", label = "Class Trainer", data = "trainer", trainer = "class", icon = "Interface/Minimap/Tracking/Class" },
	{ key = "proftrainer", label = "Profession Trainer", data = "trainer", trainer = "profession", icon = "Interface/Minimap/Tracking/Profession" },
	{ key = "barber", label = "Barber", event = "BARBER_SHOP_OPEN", icon = "Interface/Minimap/Tracking/BarberShop" },
	{ key = "transmog", label = "Transmogrifier", event = "TRANSMOGRIFY_OPEN", icon = "Interface/Minimap/Tracking/Transmogrifier" },
}

local function PlayerSide()
	return UnitFactionGroup("player") == "Horde" and 2 or 1
end

-- Lower-cased stems of the player's professions ("leat", "blac", "mini"...),
-- into `stems` (emptied first: one table kept and filled again). The list
-- ends at the first missing profession, as it always has. Each name's stem
-- is kept (the bar's looks read them, and two new strings a look were
-- garbage).
local stemOf = {}
local function ProfessionStems(stems)
	wipe(stems)
	if GetProfessions and GetProfessionInfo then
		local ok, a, b, c, d, e, f = pcall(GetProfessions)
		if ok then
			for i = 1, 6 do
				local index = select(i, a, b, c, d, e, f)
				if not index then
					break
				end
				local okI, name = pcall(GetProfessionInfo, index)
				if okI and type(name) == "string" and not IsSecret(name) then
					local stem = stemOf[name]
					if not stem then
						stem = name:lower():sub(1, 4)
						stemOf[name] = stem
					end
					stems[#stems + 1] = stem
				end
			end
		end
	end
	return stems
end

-- A subname in lower case, kept: every pass over the candidates reads each
-- trainer's, and a fresh string per row was garbage.
local lowerOf = {}
local function Lower(s)
	s = s or ""
	local l = lowerOf[s]
	if not l then
		l = s:lower()
		lowerOf[s] = l
	end
	return l
end

-- Professions a trainer can teach, recognised from the trainer's subname
-- ("Journeyman Blacksmith", "Herbalism Trainer", "Fisherman", ...).
local PROFESSIONS = {
	{ key = "alchemy",        label = "Alchemy",        match = { "alchem" } },
	{ key = "blacksmithing",  label = "Blacksmithing",  match = { "blacksmith", "armorsmith", "weaponsmith", "armor crafter", "weapon crafter" } },
	{ key = "enchanting",     label = "Enchanting",     match = { "enchant" } },
	{ key = "engineering",    label = "Engineering",    match = { "engineer" } },
	{ key = "herbalism",      label = "Herbalism",      match = { "herbal" } },
	{ key = "leatherworking", label = "Leatherworking", match = { "leather" } },
	{ key = "mining",         label = "Mining",         match = { "mining", "miner" } },
	{ key = "skinning",       label = "Skinning",       match = { "skinn" } },
	{ key = "tailoring",      label = "Tailoring",      match = { "tailor" } },
	{ key = "cooking",        label = "Cooking",        match = { "cook", "butcher" } },
	{ key = "fishing",        label = "Fishing",        match = { "fish" } },
	{ key = "firstaid",       label = "First Aid",      match = { "first aid", "physician", "trauma surgeon" } },
	{ key = "riding",         label = "Riding",         match = { "riding", "mechanostrider pilot" } },
	{ key = "weapons",        label = "Weapon Skills",  match = { "weapon master" } },
}

local function ProfessionOf(sub)
	sub = (sub or ""):lower()
	if sub == "" then
		return nil
	end
	for _, prof in ipairs(PROFESSIONS) do
		for _, stem in ipairs(prof.match) do
			if sub:find(stem, 1, true) then
				return prof
			end
		end
	end
	return nil
end

-- Names of the professions the character knows, lower case.
local function KnownProfessions()
	local known = {}
	if GetProfessions and GetProfessionInfo then
		local ok, a, b, c, d, e, f = pcall(GetProfessions)
		if ok then
			for _, index in ipairs({ a, b, c, d, e, f }) do
				if index then
					local okI, name = pcall(GetProfessionInfo, index)
					if okI and type(name) == "string" and not IsSecret(name) then
						known[name:lower()] = true
					end
				end
			end
		end
	end
	return known
end

-- What a trainer's subname is matched against, worked out once per pass
-- over the candidates (per row it cost a professions lookup and two tables):
-- the class trainer's "<class> trainer", the player's profession stems.
local passNeedle = nil
local passStems = {}
local needleOf = {}   -- class name -> "<class> trainer", made once

local function PreparePass(kind)
	passNeedle = nil
	if kind.trainer == "class" then
		local class = UnitClass("player")
		if type(class) == "string" and not IsSecret(class) then
			passNeedle = needleOf[class]
			if not passNeedle then
				passNeedle = class:lower() .. " trainer"
				needleOf[class] = passNeedle
			end
		end
	elseif kind.trainer == "profession" then
		ProfessionStems(passStems)
	end
end

local function TrainerMatches(kind, sub)
	sub = Lower(sub)
	if kind.trainer == "class" then
		return passNeedle ~= nil and sub:find(passNeedle, 1, true) ~= nil
	end
	-- Profession trainer: one of the player's professions, else any trade one.
	if #passStems == 0 then
		return not sub:find(" trainer") or sub:find("journeyman") or sub:find("expert") or sub:find("artisan")
	end
	for _, stem in ipairs(passStems) do
		if sub:find(stem, 1, true) then
			return true
		end
	end
	return false
end

-- Recorded services, kept with the Route module's learned paths.
local function Learned()
	local R = MelloUI.Route
	local store = R and R.Pins and R:Pins()
	if store then
		store.services = store.services or {}
		return store.services
	end
	M.db.learned = M.db.learned or {}
	return M.db.learned
end

local function Wanted(kind, profession, sub)
	if profession then
		return ProfessionOf(sub) == profession
	end
	return not kind.trainer or TrainerMatches(kind, sub)
end

-- Flight points the character may use: the Route module's answer, kept per
-- node (/melloperf, 2026-09-24: while the world map lists no flight points,
-- each answer walked every zone of the world map again, one walk per node on
-- every look at the flight masters). Forgotten when a flight master's map
-- opens (the Route module learns the known points a moment later); an answer
-- older than the Route module's own two minutes is asked again, one a pass,
-- and when it has changed, every one is.
--
-- Asked again only on the way to a route (GoTo), never by a look: the bar's
-- icons, the tooltip, the menu (/melloperf, the user's recording,
-- 2026-09-24: the bar's timer was slow once, 20 ms, and made 37 KB/s of
-- garbage). The flight icon's look every 15 s asked one old answer again,
-- and the Route module answers every question after refreshing its list of
-- the world map's flight points once that is two minutes old: a C_TaxiMap
-- list for every zone of both continents, each point with its own position
-- vector, 3.6 MB and 19 ms in one tick on a model of the client that gives
-- the recording's figures. That list decides nothing for a character who
-- has opened a flight master (its own points do), and the answers only
-- change at a flight master, whose map forgets them here, so a look loses
-- nothing by keeping the ones it has. Nor does the check at a flight
-- master's window (Remember): with no look asking again, the Route module's
-- list was always old by then, and every visit paid those 19 ms in the
-- window's event for answers forgotten half a second later.
local TAXI_KEEP = 120
local taxiOk, taxiAt = {}, {}   -- node ID -> usable, and when it was asked
local taxiRechecked = false     -- this pass has asked an old one again
local taxiForgot = 0            -- how often the answers were forgotten (a look notices)

local function ForgetTaxis()
	wipe(taxiOk)
	taxiForgot = taxiForgot + 1
end

-- Every flight point of the player's side not asked yet, asked at once when
-- one is: that first question had the Route module's list made (or found it
-- fresh), so the rest cost next to nothing. Asked one by one as the looks
-- came to them, the first look on another continent (after a boat) set the
-- list off again.
local function AskAllTaxis(R)
	local data = Data()
	if type(data) ~= "table" or type(data.taxiNodes) ~= "table" then
		return
	end
	local side, now = PlayerSide(), GetTime()
	for id, n in pairs(data.taxiNodes) do
		if taxiOk[id] == nil and (n[5] == 0 or n[5] == side) then
			taxiOk[id], taxiAt[id] = R:IsTaxiUsable(id) and true or false, now
		end
	end
end

-- ask: also when not asked yet (else nil for that one); keep: an old answer
-- as it is (a look, the check at a flight master's window)
local function TaxiOk(R, id, ask, keep)
	local ok = taxiOk[id]
	if ok == nil then
		if not ask then
			return nil
		end
	elseif keep or taxiRechecked or GetTime() - taxiAt[id] < TAXI_KEEP then
		return ok
	else
		taxiRechecked = true
	end
	local usable = R:IsTaxiUsable(id) and true or false
	if ok ~= nil and usable ~= ok then
		ForgetTaxis()
	end
	taxiOk[id], taxiAt[id] = usable, GetTime()
	if usable ~= ok then
		AskAllTaxis(R)   -- the first answer, or one that changed (the rest forgotten)
	end
	return usable
end

-- One pass over the candidates of a kind: visit(entry, name, sub, cont, wx,
-- wy, mapID, x, y) for each, the database's and the flight points' by
-- continent and world position, the learned ones by map and map position,
-- until visit returns true. The entries in `skip` (optional) are passed over
-- untested. profession (optional): only trainers teaching that profession.
-- lazy (a look, not a route): a flight point not asked about yet is visited
-- with its node ID last, for visit to ask once it has a distance (and that
-- asks them all, AskAllTaxis); an old answer is kept (see TaxiOk).
-- cur, stopAt (optional; the bar's looks): a pass that may stop part way.
-- Once debugprofilestop() is past stopAt after a visit, where it got to is
-- kept on cur (the service button) and true returned; the next pass with cur
-- goes on from there, in the same order. The database's rows and the flight
-- points can stop; the remembered ones, a handful that can change in
-- between, are gone through in one go.
-- keep (optional; not lazy): an old flight answer kept as it is, as a look
-- keeps it; one not asked yet is still asked.
local function EachCandidate(kind, profession, visit, skip, lazy, cur, stopAt, keep)
	PreparePass(kind)   -- again on going on: another pass may have run since
	local phase, pos = 1, 0
	if cur and cur.scanPhase then
		phase, pos = cur.scanPhase, cur.scanPos
		cur.scanPhase = nil
	else
		taxiRechecked = false
	end
	local data = Data()
	local side = PlayerSide()
	if phase == 1 then
		if kind.data and type(data) == "table" and type(data.services) == "table" then
			local rows = data.services
			local i = pos + 1
			local row = rows[i]
			while row ~= nil do
				if row[1] == kind.data and (row[4] == 0 or row[4] == side) and not (skip and skip[row])
					and Wanted(kind, profession, row[3]) then
					if visit(row, row[2], row[3], row[5], row[6], row[7]) then
						return false
					end
					if stopAt and debugprofilestop() > stopAt then
						cur.scanPhase, cur.scanPos = 1, i
						return true
					end
				end
				i = i + 1
				row = rows[i]
			end
		end
		pos = nil
	end
	if phase <= 2 and kind.taxi and type(data) == "table" and type(data.taxiNodes) == "table" then
		local R = Route()
		local nodes = data.taxiNodes
		local id, n = next(nodes, pos)
		while id ~= nil do
			if (n[5] == 0 or n[5] == side) and not (skip and skip[n]) then
				local usable = not R or TaxiOk(R, id, not lazy, lazy or keep)
				if usable ~= false then
					if visit(n, n[1], "", n[2], n[3], n[4], nil, nil, nil, usable == nil and id or nil) then
						return false
					end
					if stopAt and debugprofilestop() > stopAt then
						cur.scanPhase, cur.scanPos = 2, id
						return true
					end
				end
			end
			id, n = next(nodes, id)
		end
	end
	for _, l in pairs(Learned()) do
		if (l.kind == kind.key or (kind.data and l.kind == kind.data and Wanted(kind, profession, l.sub))) and not (skip and skip[l])
			and visit(l, l.name, l.sub or "", nil, nil, nil, l.mapID, l.x, l.y) then
			return false
		end
	end
	return false
end

-- Candidates of a kind: { name, sub, cont/wx/wy or mapID/x/y }.
-- profession (optional): only trainers teaching that profession. keep
-- (optional): the flight answers kept however old (EachCandidate).
local function Candidates(kind, profession, keep)
	local out = {}
	EachCandidate(kind, profession, function(_, name, sub, cont, wx, wy, mapID, x, y)
		if cont ~= nil then
			out[#out + 1] = { name = name, sub = sub, cont = cont, wx = wx, wy = wy }
		else
			out[#out + 1] = { name = name, sub = sub, mapID = mapID, x = x, y = y }
		end
	end, nil, false, nil, nil, keep)
	return out
end

-- The nearest few by straight line, with their distances.
local function Nearest(kind, count, profession)
	local R = Route()
	if not R then
		return {}
	end
	local list = {}
	for _, c in ipairs(Candidates(kind, profession)) do
		local d = R:DistanceTo(c)
		if d then
			c.distance = d
			list[#list + 1] = c
		end
	end
	table.sort(list, function(a, b) return a.distance < b.distance end)
	while #list > count do
		list[#list] = nil
	end
	return list
end

-- The bar's and the menu's look at a kind (/melloperf, 2026-09-24: the
-- bar's refresh took 17 ms and made 1.7 MB of garbage every 15 s; every
-- candidate of every kind got a table and a route distance, and each
-- distance asks the client for the player's position). An icon only says
-- whether one is known on this continent, and the first candidate with a
-- distance answers that; the nearest, with its distance, is looked for when
-- a tooltip or the menu shows it. Candidates found on another continent are
-- kept per continent and passed over: their answer cannot change while the
-- player is on it.
local MAP_CONTINENT = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
local WEAK_KEYS = { __mode = "k" }
local contOf = {}         -- the player's map -> the continent map above it
local elsewhereOn = {}    -- continent -> { [entry] = true }: candidates on another one
local probe = {}          -- the candidate handed to Route:DistanceTo, filled again each time
local scanR, scanSkip, scanFirst, scanMap, scanPlayerOk = nil, nil, false, nil, nil
local bestD, bestName, bestSub = nil, nil, nil

-- The player's continent, found as the Route module finds it (the continent
-- map above the player's map; the map itself while that is not known), and
-- the player's map; nil without a map, when no candidate has a distance.
-- A map with no continent above it is kept as its own (a map info table per
-- level on every look was garbage); what is kept per continent only needs a
-- key the map fixes, and the map does.
local function PlayerContinent()
	local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
	mapID = ok and Plain(mapID) or nil
	if not mapID then
		return nil
	end
	local cont = contOf[mapID]
	if cont then
		return cont, mapID
	end
	local id = mapID
	for _ = 1, 6 do
		local okI, info = pcall(C_Map.GetMapInfo, id)
		if not okI or type(info) ~= "table" then
			break
		end
		if Plain(info.mapType) == MAP_CONTINENT then
			contOf[mapID] = id
			return id, mapID
		end
		id = Plain(info.parentMapID)
		if not id or id == 0 then
			break
		end
	end
	contOf[mapID] = mapID
	return mapID, mapID
end

local function ScanVisit(entry, name, sub, cont, wx, wy, mapID, x, y, taxi)
	probe.cont, probe.wx, probe.wy, probe.mapID, probe.x, probe.y = cont, wx, wy, mapID, x, y
	local d, elsewhere = scanR:DistanceTo(probe)
	if d then
		scanPlayerOk = true
		-- a flight point not asked about yet: asked now it is on this continent
		if taxi and not TaxiOk(scanR, taxi, true) then
			return false
		end
		if not bestD or d < bestD then
			bestD, bestName, bestSub = d, name, sub
		end
		return scanFirst
	end
	if elsewhere then
		scanPlayerOk = true
		scanSkip[entry] = true
		return false
	end
	-- no distance, not elsewhere: this one's place is not known, or the
	-- player's is not (then none has a distance, and the pass ends); a point
	-- on the player's own map tells which
	if scanPlayerOk == nil then
		probe.cont, probe.wx, probe.wy, probe.mapID, probe.x, probe.y = nil, nil, nil, scanMap, 0.5, 0.5
		scanPlayerOk = scanR:DistanceTo(probe) ~= nil
	end
	return not scanPlayerOk
end

-- Distance to the nearest candidate of a kind with its name and subname
-- (first: to the first one found, which is enough for an icon); nil when
-- none has a distance. cur, stopAt: an icon's look (first) that may stop
-- part way (EachCandidate); then nil, nil, nil, true, and the next call with
-- cur goes on, where it stopped while the player is still on that map.
local function ScanKind(kind, first, cur, stopAt)
	local R = Route()
	if not R then
		return nil
	end
	local cont, mapID = PlayerContinent()
	if not cont then
		return nil
	end
	local skip = elsewhereOn[cont]
	if not skip then
		skip = setmetatable({}, WEAK_KEYS)
		elsewhereOn[cont] = skip
	end
	local playerOk = nil
	if cur and cur.scanPhase then
		if cur.scanR == R and cur.scanMap == mapID then
			playerOk = cur.scanOk
		else
			cur.scanPhase = nil
		end
	end
	scanR, scanSkip, scanFirst, scanMap, scanPlayerOk = R, skip, first and true or false, mapID, playerOk
	bestD, bestName, bestSub = nil, nil, nil
	local stopped = EachCandidate(kind, nil, ScanVisit, scanSkip, true, cur, stopAt)
	if stopped then
		cur.scanR, cur.scanMap, cur.scanOk = R, mapID, scanPlayerOk
	end
	scanR, scanSkip = nil, nil
	if stopped then
		return nil, nil, nil, true
	end
	return bestD, bestName, bestSub
end

-- The Route module draws the tracking notice; chat when it is off.
local function Notify(text, kind)
	local R = MelloUI.Route
	if R and R.Notify then
		R:Notify(text, kind)
	else
		MelloUI:Notice(text)
	end
end

local function CleanSub(sub)
	if type(sub) ~= "string" or sub == "" or sub:upper() == "NULL" then
		return ""
	end
	return sub
end

local function GoTo(kind, profession)
	local R = Route()
	if not R then
		Notify("The Route module is off; enable it under /mello.", "fail")
		return
	end
	local what = profession and (profession.label .. " trainer") or kind.label:lower()
	local near = Nearest(kind, 6, profession)
	if #near == 0 then
		Notify("No " .. what .. " known on this continent yet.", "fail")
		return
	end
	local best, _, later = R:Cheapest(near)
	if later and R.WhenReady then
		-- the first route of the session: Route's road graph is still being
		-- built (user, 2026-09-24: built on the first route, not at login), so
		-- the nearest is chosen once it is, by route as ever, not by straight
		-- line (a flight master across the river is not near)
		R:WhenReady(function() GoTo(kind, profession) end)
		return
	end
	local c = near[best or 1]
	local icon = kind.icon and ("|T" .. kind.icon .. ":16:16|t ") or ""
	local label = icon .. (profession and profession.label or kind.label) .. ": " .. c.name
	local big = kind.icon and ("|T" .. kind.icon .. ":22:22|t  ") or ""
	R:SetDestinationTo(c, label, true, string.format("%sTracking nearest %s, closest one {dist} away", big, what))
end

-- The profession trainer button asks which profession: a menu of every
-- profession with a known trainer, the character's own ones first.
local function ProfessionMenu(owner, kind)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		GoTo(kind)
		return
	end
	local known = KnownProfessions()
	local available = {}
	for _, prof in ipairs(PROFESSIONS) do
		if #Candidates(kind, prof) > 0 then
			available[#available + 1] = prof
		end
	end
	table.sort(available, function(a, b)
		local ka, kb = known[a.label:lower()] or false, known[b.label:lower()] or false
		if ka ~= kb then
			return ka
		end
		return a.label < b.label
	end)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("Profession Trainer")
		for _, prof in ipairs(available) do
			local text = prof.label
			if known[prof.label:lower()] then
				text = text .. "  |cff40ff40(yours)|r"
			end
			root:CreateButton(text, function() GoTo(kind, prof) end)
		end
		if #available > 0 then
			root:CreateDivider()
		end
		root:CreateButton("Nearest of any", function() GoTo(kind) end)
	end)
end

--------------------------------------------------------------------------------
-- Learning
--------------------------------------------------------------------------------

local function Remember(kindKey, name, sub)
	if not name then
		return
	end
	local mapID, x, y = PlayerMapPoint()
	if not mapID then
		return
	end
	local key = kindKey .. "|" .. name .. "|" .. mapID
	local learned = Learned()
	if learned[key] then
		return
	end
	-- The database may already know this one: skip when a known candidate of
	-- the kind stands within 40 yards.
	local R = Route()
	local me = { mapID = mapID, x = x, y = y }
	if R then
		local here = R:DistanceTo(me) or 0
		for _, kind in ipairs(KINDS) do
			-- every kind of this data (the class trainer entry filters its
			-- candidates by class; a profession trainer is in the next one)
			if kind.key == kindKey or kind.data == kindKey then
				-- the flight answers as they are (TaxiOk): a flight master's
				-- map forgets them half a second later
				for _, c in ipairs(Candidates(kind, nil, true)) do
					if not c.mapID then
						local d = R:DistanceTo(c)
						if d and math.abs(d - here) < 40 then
							return
						end
					end
				end
			end
		end
	end
	learned[key] = { kind = kindKey, name = name, sub = sub or "", mapID = mapID, x = x, y = y }
	local icon = ""
	for _, kind in ipairs(KINDS) do
		if (kind.key == kindKey or kind.data == kindKey) and kind.icon then
			icon = "|T" .. kind.icon .. ":22:22|t  "
			break
		end
	end
	Notify(icon .. "Remembered " .. name .. " as a " .. kindKey, "learn")
end

local eventFrame = CreateFrame("Frame")
Perf.SetScript(eventFrame, "OnEvent", function(_, event)
	if event == "MERCHANT_SHOW" then
		local ok, can = pcall(CanMerchantRepair)
		if ok and can then
			Remember("repair", NPCName(), NPCSubName())
		end
	elseif event == "MAIL_SHOW" then
		Remember("mailbox", "Mailbox", "")
	elseif event == "GOSSIP_SHOW" then
		if C_GossipInfo and C_GossipInfo.GetOptions then
			local ok, options = pcall(C_GossipInfo.GetOptions)
			if ok and type(options) == "table" then
				for _, option in ipairs(options) do
					local text = Plain(option.name)
					if type(text) == "string" and text:lower():find("inn your home", 1, true) then
						Remember("innkeeper", NPCName(), NPCSubName())
						break
					end
				end
			end
		end
	elseif event == "TAXIMAP_OPENED" then
		Remember("flight", NPCName(), NPCSubName())
		-- the Route module learns the known flight points 0.2 s in
		C_Timer.After(0.5, ForgetTaxis)
	elseif event == "AUCTION_HOUSE_SHOW" then
		Remember("auction", NPCName(), NPCSubName())
	elseif event == "BANKFRAME_OPENED" then
		Remember("banker", NPCName(), NPCSubName())
	elseif event == "TRAINER_SHOW" then
		Remember("trainer", NPCName(), NPCSubName())
	elseif event == "BARBER_SHOP_OPEN" then
		Remember("barber", NPCName() or "Barber", NPCSubName())
	elseif event == "TRANSMOGRIFY_OPEN" then
		Remember("transmog", NPCName() or "Transmogrifier", NPCSubName())
	end
end)

local EVENTS = { "MERCHANT_SHOW", "MAIL_SHOW", "GOSSIP_SHOW", "TAXIMAP_OPENED", "AUCTION_HOUSE_SHOW", "BANKFRAME_OPENED",
	"TRAINER_SHOW", "BARBER_SHOP_OPEN", "TRANSMOGRIFY_OPEN" }

--------------------------------------------------------------------------------
-- Menu
--------------------------------------------------------------------------------

local menu = nil
local ROW_HEIGHT = 20
local MENU_WIDTH = 300

local KitOn, SetKitBox   -- the kit look (below)

local function CreateMenu()
	if menu then
		return menu
	end
	menu = CreateFrame("Frame", "MelloUIServicesMenu", UIParent, "BackdropTemplate")
	menu:SetFrameStrata("DIALOG")
	menu:SetClampedToScreen(true)
	menu:SetWidth(MENU_WIDTH)
	if menu.SetBackdrop then
		menu:SetBackdrop({
			bgFile = "Interface/Tooltips/UI-Tooltip-Background",
			edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		menu:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
		menu:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
	end
	menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	menu.title:SetPoint("TOPLEFT", 12, -10)
	menu.title:SetText("Nearest ...")
	menu.rows = {}
	for i, kind in ipairs(KINDS) do
		local row = CreateFrame("Button", nil, menu)
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 8, -30 - (i - 1) * ROW_HEIGHT)
		row:SetPoint("RIGHT", -8, 0)
		row:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")
		row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.label:SetPoint("LEFT", 6, 0)
		row.label:SetText(kind.label)
		row.where = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		row.where:SetPoint("RIGHT", -6, 0)
		row.where:SetPoint("LEFT", row.label, "RIGHT", 8, 0)
		row.where:SetJustifyH("RIGHT")
		row.where:SetWordWrap(false)
		row.kind = kind
		Perf.SetScript(row, "OnClick", function(self)
			menu:Hide()
			GoTo(self.kind)
		end)
		menu.rows[i] = row
	end
	menu.stop = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
	menu.stop:SetSize(110, 20)
	menu.stop:SetPoint("TOPLEFT", 12, -34 - #KINDS * ROW_HEIGHT)
	menu.stop:SetText("Stop route")
	Perf.SetScript(menu.stop, "OnClick", function()
		menu:Hide()
		local R = MelloUI.Route
		if R and R.Clear then
			R:Clear()
		end
		if C_Map.ClearUserWaypoint then
			pcall(C_Map.ClearUserWaypoint)
		end
	end)
	menu.hint = menu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	menu.hint:SetPoint("LEFT", menu.stop, "RIGHT", 8, 0)
	menu.hint:SetPoint("RIGHT", -12, 0)
	menu.hint:SetJustifyH("LEFT")
	menu.hint:SetText("nearest by road")
	menu:SetHeight(30 + #KINDS * ROW_HEIGHT + 34)
	menu:Hide()
	if KitOn() then
		SetKitBox(menu, true)   -- SV1: the L1 box, as the bar
	end
	-- Close when clicking elsewhere: a mouse press anywhere, listened for only
	-- while the menu is open; a client without that event looks at the mouse
	-- buttons every frame while it is open.
	local function Away(self)
		return not self:IsMouseOver(20, -20, -20, 20) and not (M.button and M.button:IsMouseOver())
	end
	local okEvent, registered = pcall(menu.RegisterEvent, menu, "GLOBAL_MOUSE_DOWN")
	if okEvent and registered ~= false then
		menu:UnregisterEvent("GLOBAL_MOUSE_DOWN")
		Perf.SetScript(menu, "OnEvent", function(self, _, button)
			if (button == "LeftButton" or button == "RightButton") and Away(self) then
				self:Hide()
			end
		end)
		Perf.HookScript(menu, "OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
		Perf.HookScript(menu, "OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
	else
		Perf.SetScript(menu, "OnUpdate", function(self)
			if Away(self) then
				local down = IsMouseButtonDown and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
				if down then
					self:Hide()
				end
			end
		end)
	end
	return menu
end

local function FillMenu()
	local R = Route()
	local hasDest = R and R.HasDestination and R:HasDestination()
	for _, row in ipairs(menu.rows) do
		local d, name = ScanKind(row.kind, false)
		if d then
			row.where:SetText(string.format("%s  |cffaaaaaa%s|r", name, Yards(d)))
			row.where:SetTextColor(1, 0.82, 0.25)
			row:Enable()
			row.label:SetTextColor(1, 1, 1)
		else
			row.where:SetText(R and "none known here" or "Route module off")
			row.where:SetTextColor(0.5, 0.5, 0.5)
			row.label:SetTextColor(0.6, 0.6, 0.6)
		end
	end
	menu.stop:SetShown(hasDest and true or false)
	menu.hint:SetShown(not hasDest)
end

local function ToggleMenu(anchor)
	CreateMenu()
	if menu:IsShown() then
		menu:Hide()
		return
	end
	FillMenu()
	menu:ClearAllPoints()
	if anchor then
		menu:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", 0, 0)
	else
		menu:SetPoint("CENTER", UIParent, "CENTER")
	end
	menu:Show()
end

--------------------------------------------------------------------------------
-- Icon bar under the minimap
--------------------------------------------------------------------------------

local bar = nil
local ICON = 26
local GAP = 5
local PER_ROW = 5

local function StopRoute()
	local R = MelloUI.Route
	if R and R.Clear then
		R:Clear()
	end
	if C_Map.ClearUserWaypoint then
		pcall(C_Map.ClearUserWaypoint)
	end
end

-- The icons: bright with one of the kind known on this continent, grey
-- without. Each kind is looked at every 15 s while the bar is visible, one
-- kind at a time on a ticker that stops while the bar is hidden; all of them
-- when it shows or is set up again, a millisecond's worth a frame (the new
-- bar's first pass whole, or an icon not looked at yet would show bright,
-- then turn grey). The nearest one with its distance is looked for when its
-- tooltip opens.
--
-- (/melloperf, the user's recording, 2026-09-24) A bright icon is not looked
-- at again while nothing its answer hangs on has changed (SameLook): where
-- the player stands on the continent does not change it, and each look
-- asked the client for the player's position again, a new position vector
-- every 1.5 s for the same answer. A grey one is looked at as ever (a place
-- the client could not map yet may be mapped now); that costs next to
-- nothing, the candidates elsewhere being passed over. A look stops after
-- its share of the tick and goes on at the next one, the icon as it was
-- meanwhile.
local CHECK_EVERY = 15
local SPREAD_MS = 1
local TICK_MS = 1
local ticker = nil

local function ShowFound(b, found)
	if found ~= b.found then
		b.found = found
		b.nearestAt = nil   -- the tooltip looks again
	end
	if not found then
		b.nearest = nil
	end
	b.icon:SetDesaturated(not found)
	b.icon:SetAlpha(found and 1 or 0.45)
end

-- What an icon's answer hangs on besides the candidates' own places: the
-- Route module, the player's map (its continent, and whether the client
-- gives a position there: none in an instance), the side, the class (class
-- trainers), the professions (profession trainers), the flight answers
-- (flight masters) and the remembered services. True while it is as it was
-- at the button's last look; keep: taken as the new look's.
local lookStems = {}

local function SameLook(b, keep)
	local kind = b.kind
	local R = Route()
	local _, mapID = PlayerContinent()
	local store = Learned()
	local count = 0
	for _ in pairs(store) do
		count = count + 1
	end
	local side = PlayerSide()
	local class = kind.trainer == "class" and Plain(UnitClass("player")) or nil
	local taxi = kind.taxi and taxiForgot or nil
	local same = b.lookR == R and b.lookMap == mapID and b.lookSide == side and b.lookClass == class
		and b.lookTaxi == taxi and b.lookStore == store and b.lookCount == count
	if kind.trainer == "profession" then
		ProfessionStems(lookStems)
		local kept = b.lookStems
		if not kept then
			kept = {}
			b.lookStems = kept
			same = false
		elseif #kept ~= #lookStems then
			same = false
		else
			for i = 1, #kept do
				if kept[i] ~= lookStems[i] then
					same = false
					break
				end
			end
		end
		if keep then
			wipe(kept)
			for i = 1, #lookStems do
				kept[i] = lookStems[i]
			end
		end
	end
	if keep then
		b.lookR, b.lookMap, b.lookSide, b.lookClass = R, mapID, side, class
		b.lookTaxi, b.lookStore, b.lookCount = taxi, store, count
	end
	return same
end

-- A look at a button's kind; true once it is done. stopAt: it may stop there
-- and go on at the next call (from the start again when what it hangs on
-- has changed meanwhile). force: looked at even when bright and unchanged.
local function CheckButton(b, stopAt, force)
	if b.scanPhase and not SameLook(b) then
		b.scanPhase = nil
	end
	if not b.scanPhase then
		if not force and b.found and b.looked and SameLook(b) then
			ShowFound(b, true)
			return true
		end
		SameLook(b, true)
		b.looked = false
	end
	local d, _, _, stopped = ScanKind(b.kind, true, b, stopAt)
	if stopped then
		return false
	end
	b.looked = true
	ShowFound(b, d ~= nil)
	return true
end

local function FindNearest(b)
	b.scanPhase = nil   -- a whole look, in place of one under way
	SameLook(b, true)
	local d, name, sub = ScanKind(b.kind, false)
	if d then
		local c = b.near or {}
		b.near = c
		c.name, c.sub, c.distance = name, sub, d
		b.nearest = c
	end
	b.looked = true
	ShowFound(b, d ~= nil)
	b.nearestAt = GetTime()
end

-- The kinds from bar.spread on, for about a millisecond (the first pass to
-- its end: the last icon has no state until then); true while some are left
-- for the next frames. A look that stops goes on in the next frame.
local function Spread(self)
	local t0 = debugprofilestop()
	local last = self.buttons[#self.buttons]
	while self.spread do
		local b = self.buttons[self.spread]
		if not b then
			self.spread = nil
		else
			local i = self.spread
			self.spread = i + 1
			if not CheckButton(b, last.found ~= nil and t0 + SPREAD_MS or nil, true) then
				self.spread = i   -- stopped part way: this one again
			end
			if last.found ~= nil and debugprofilestop() - t0 > SPREAD_MS then
				break
			end
		end
	end
	if not self.spread and self.spreading then
		self.spreading = nil
		Perf.SetScript(self, "OnUpdate", nil)
	end
	return self.spread ~= nil
end

local function RefreshBar()
	if not (bar and bar:IsShown()) then
		return
	end
	for _, b in ipairs(bar.buttons) do
		b.scanPhase = nil   -- every one looked at again, from the start
	end
	bar.spread = 1
	if Spread(bar) and not bar.spreading then
		bar.spreading = true
		Perf.SetScript(bar, "OnUpdate", Spread)
	end
end

-- One kind a tick, TICK_MS of it; a look that stops keeps its turn
local function Tick()
	if not (bar and bar:IsVisible()) then
		return
	end
	local i = bar.nextCheck or 1
	bar.nextCheck = i % #bar.buttons + 1
	if not CheckButton(bar.buttons[i], debugprofilestop() + TICK_MS) then
		bar.nextCheck = i
	end
end

local function WatchBar(on)
	if on and not ticker then
		ticker = C_Timer.NewTicker(CHECK_EVERY / #KINDS, Tick)
	elseif not on and ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local function BarTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText(self.kind.label, 1, 1, 1)
	if self.nearest then
		local c = self.nearest
		local sub = CleanSub(c.sub)
		GameTooltip:AddLine(string.format("Nearest: %s%s, %s", c.name, sub ~= "" and (" (" .. sub .. ")") or "", Yards(c.distance)), 1, 0.82, 0.25)
		if self.kind.trainer == "profession" then
			GameTooltip:AddLine("Click to pick a profession and route to its nearest trainer. Right-click stops the route.", 0.7, 0.7, 0.7, true)
		else
			GameTooltip:AddLine("Click to route there by road. Right-click stops the route.", 0.7, 0.7, 0.7, true)
		end
	elseif Route() then
		GameTooltip:AddLine("None known on this continent yet; it is remembered the first time you use one.", 0.6, 0.6, 0.6, true)
	else
		GameTooltip:AddLine("The Route module is off.", 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

local function CreateBar()
	if bar or not Minimap then
		return
	end
	local rows = math.ceil(#KINDS / PER_ROW)
	bar = CreateFrame("Frame", "MelloUIServicesBar", Minimap, "BackdropTemplate")
	bar:SetSize(PER_ROW * ICON + (PER_ROW + 1) * GAP, rows * ICON + (rows + 1) * GAP)
	if bar.SetBackdrop then
		bar:SetBackdrop({
			bgFile = "Interface/Tooltips/UI-Tooltip-Background",
			edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		bar:SetBackdropColor(0.05, 0.05, 0.06, 0.85)
		bar:SetBackdropBorderColor(0.55, 0.45, 0.25, 1)
	end
	bar.buttons = {}
	for i, kind in ipairs(KINDS) do
		local b = CreateFrame("Button", nil, bar)
		b:SetSize(ICON, ICON)
		local col, row = (i - 1) % PER_ROW, math.floor((i - 1) / PER_ROW)
		b:SetPoint("TOPLEFT", GAP + col * (ICON + GAP), -(GAP + row * (ICON + GAP)))
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetAllPoints()
		b.icon:SetTexture(kind.icon)
		b:SetHighlightTexture("Interface/Buttons/ButtonHilight-Square", "ADD")
		b.kind = kind
		Perf.SetScript(b, "OnClick", function(self, mouse)
			if mouse == "RightButton" then
				StopRoute()
			elseif self.kind.trainer == "profession" then
				ProfessionMenu(self, self.kind)
			else
				GoTo(self.kind)
			end
		end)
		Perf.SetScript(b, "OnEnter", function(self)
			if not self.nearestAt or GetTime() - self.nearestAt > 5 then
				FindNearest(self)
			end
			BarTooltip(self)
		end)
		Perf.SetScript(b, "OnLeave", function() GameTooltip:Hide() end)
		bar.buttons[i] = b
	end
	-- The known-here state is looked at now and then while the bar is visible.
	Perf.SetScript(bar, "OnShow", function()
		RefreshBar()
		WatchBar(true)
	end)
	Perf.SetScript(bar, "OnHide", function(self)
		WatchBar(false)
		if self.spreading then
			self.spread, self.spreading = nil, nil
			Perf.SetScript(self, "OnUpdate", nil)
		end
	end)
end

--------------------------------------------------------------------------------
-- The painted minimap stand (ring, zone bar, scaffold with slots) was removed
-- on 2026-09-21 with the restore-first rule: the minimap is the game's, the
-- service icons sit on the plain bar below it.
--------------------------------------------------------------------------------

local function LayerBar()
	if not (bar and Minimap) then
		return
	end
	bar:SetFrameStrata(Minimap:GetFrameStrata())
	bar:SetFrameLevel(Minimap:GetFrameLevel() + 3)
end

local function ApplyStand()
	LayerBar()
end

-- Bar layout: a grid of icons under the minimap (round medallions with a rim
-- when roundIcons is on).
local RIM_RATIO = 31 / 21   -- medallion outer diameter over icon diameter (rim art: 31 px ring, 21 px opening)
local KIT_RIM_RATIO = 130 / 79   -- the kit's round rim (buttons/roundslot: 130 px, 79 px opening)

--------------------------------------------------------------------------------
-- The kit look (user's picks SV1 SR2, 2026-09-22, kit_raw/services_catalog.png):
-- the bar and the nearest-service menu on the L1 box (single rail, list-box
-- stone), the icons in the kit's round rims. It goes with the minimap area
-- of the reskin (Kit:IsCovered("minimap")): on while the painted minimap
-- is, the game's own backdrop and tracking rims otherwise. Square icons
-- ("Round Icons" off) get the square R1 rim.
--------------------------------------------------------------------------------

KitOn = function()
	local kit = MelloUI.Kit
	return kit and kit.IsCovered and kit:IsCovered("minimap") and kit.Replace and true or false
end

-- An invisible region for Kit:Replace where the frame has none of its own.
local function KitAnchor(frame)
	local tex = frame:CreateTexture(nil, "BACKGROUND")
	tex:SetAllPoints(frame)
	tex:SetColorTexture(0, 0, 0, 0)
	return tex
end

-- The L1 box on a frame of ours (the bar, the menu), one level under it.
-- The box's rule lays the palette's inner panel over its stone (the eye
-- strain rule, user 2026-09-24: "apply the eye strain rule to all existing
-- windows"; WINDOW-RULES 2e): kept on the nearest-service menu, a list of
-- text rows; left off the bar, a grid of icons in their rims with no text on
-- the stone, which keeps the plain stone it was picked with (SV1).
local function KitBox(frame)
	if frame.kitBox ~= nil then
		return frame.kitBox
	end
	-- nil: the rule's panel; false: none (an `and false or nil` would give nil)
	local dim = nil
	if frame ~= menu then
		dim = false
	end
	local rep = MelloUI.Kit:Replace(KitAnchor(frame), { as = "Professions-background-summarylist", rect = frame, parent = frame, level = -1, dim = dim })
	frame.kitBox = rep or false
	return frame.kitBox
end

SetKitBox = function(frame, on)
	if not frame then
		return
	end
	if on then
		local rep = KitBox(frame)
		if rep then
			rep:Enable()
			if frame.SetBackdrop then
				frame:SetBackdrop(nil)
			end
			return true
		end
	elseif frame.kitBox then
		frame.kitBox:Disable()
	end
	return false
end

-- A service button's kit rim (round or square), made once each, the icon
-- fitted into the shown one's opening.
local function KitRim(b, round)
	local key = round and "kitRoundRim" or "kitSquareRim"
	if not b[key] then
		b[key] = MelloUI.Kit:Slot(b, { kind = round and "roundslot" or "slot" })
		if MelloUI.Kit.RegisterTexture then
			MelloUI.Kit:RegisterTexture(b[key])   -- Dark Mode's shade
		end
	end
	return b[key]
end

-- Merged into the square minimap's frame (MinimapPanel's Merge With
-- Services; user, 2026-09-23: the header, the minimap and the services "into
-- 1 thing", a header plate between map and services, "D"): the bar spans the
-- map's width under that plate, on the frame's stone instead of its own box.
local function Merged()
	local mp = MelloUI:GetModule("MinimapPanel")
	return KitOn() and mp and mp.isEnabled and mp.WantsServices and mp:WantsServices() and true or false
end

-- the frame's stone under the merged bar
local function BarStone(on)
	if not bar then
		return
	end
	if on and not bar.stone then
		bar.stone = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
		bar.stone:SetAllPoints(bar)
	end
	if bar.stone then
		if on then
			local mp = MelloUI:GetModule("MinimapPanel")
			local piece = mp and mp.BodyPiece and mp:BodyPiece() or "window/frame_body"
			if bar.stone.kitName ~= piece then
				MelloUI.Kit:Apply(bar.stone, piece)
			end
			MelloUI.Kit:Retile(bar.stone)
		end
		bar.stone:SetShown(on and true or false)
	end
end

local function LayoutBar()
	if not bar then
		return
	end
	local rows = math.ceil(#KINDS / PER_ROW)
	local kit = KitOn()
	-- a medallion needs room for its rim; on the kit every icon has one
	-- (round or square), and the BUTTON is the rim: the icon is fitted
	-- into its opening
	local ring = kit and KIT_RIM_RATIO or (M.db.roundIcons and RIM_RATIO or 1)
	local icon, gap = ICON, GAP
	local cell = icon * ring
	local inset = kit and 0 or (cell - icon) / 2
	local merged = Merged()
	local width = PER_ROW * cell + (PER_ROW + 1) * gap
	if merged then
		-- as wide as the map: the cells made smaller where five do not fit
		-- (user, 2026-09-23: "the buttons are not quite fitting the borders"),
		-- then spread evenly across it
		local okW, mapW = pcall(Minimap.GetWidth, Minimap)
		if okW and mapW and not IsSecret(mapW) and mapW > 0 then
			width = mapW
			local minGap = 4
			local fit = (mapW - (PER_ROW + 1) * minGap) / PER_ROW
			if cell > fit then
				local k = fit / cell
				cell, icon = fit, icon * k
				inset = kit and 0 or (cell - icon) / 2
			end
			gap = (mapW - PER_ROW * cell) / (PER_ROW + 1)
		end
	end
	bar:SetSize(width, rows * cell + (rows + 1) * gap)
	for i, b in ipairs(bar.buttons) do
		local col, row = (i - 1) % PER_ROW, math.floor((i - 1) / PER_ROW)
		b:SetSize(kit and cell or icon, kit and cell or icon)
		b:ClearAllPoints()
		b:Show()
		b:SetPoint("TOPLEFT", gap + col * (cell + gap) + inset, -(gap + row * (cell + gap) + inset))
		if b.rim then
			local k = icon / 21
			b.rim:SetSize(53 * k, 53 * k)
			b.rim:ClearAllPoints()
			b.rim:SetPoint("TOPLEFT", b, "TOPLEFT", -5 * k, 4 * k)
		end
	end
	if kit then
		for _, b in ipairs(bar.buttons) do
			for _, key in ipairs({ "kitRoundRim", "kitSquareRim" }) do
				local rim = b[key]
				if rim and rim:IsShown() and rim.icon then
					MelloUI.Kit:SlotPlaceIcon(rim)
				end
			end
		end
	end
	-- hung where the column under the minimap keeps it (MinimapPanel's
	-- column: under the map by the bar's offset, or under the divider
	-- merged; audit, 2026-09-24, rank 18)
	bar:ClearAllPoints()
	local mp = MelloUI:GetModule("MinimapPanel")
	if mp and mp.ColumnSlot then
		local rel, relPoint, x, y = mp:ColumnSlot("services")
		bar:SetPoint("TOP", rel, relPoint, x, y)
	elseif merged then
		bar:SetPoint("TOP", Minimap, "BOTTOM", 0, -(mp.DividerHeight and mp:DividerHeight() or 26))
	else
		bar:SetPoint("TOP", Minimap, "BOTTOM", 0, tonumber(M.db.barOffset) or -26)
	end
end

-- The bar laid out, shown or hidden: the column under the minimap laid again
-- (MinimapPanel lays its frame round the map and the bar first while it is
-- on). The game's objective tracker is an Edit Mode system and nothing here
-- ever moves it: an anchor set by addon code taints what Edit Mode reads
-- back on exit. (The objective tracker's panel has no layout to call: the
-- call the bar made to it did nothing; audit, 2026-09-24, rank 18.)
local function TellColumn()
	local mp = MelloUI:GetModule("MinimapPanel")
	if not mp then
		return
	end
	if mp.isEnabled and mp.Relayout then
		mp:Relayout()
	elseif mp.LayColumn then
		mp:LayColumn()
	end
end

-- Round medallion icons: the icon under a circular mask with the classic
-- minimap tracking rim around it.
local RIM_TEXTURE = "Interface\\Minimap\\MiniMap-TrackingBorder"
local function ApplyIconShape()
	if not bar then
		return
	end
	local round = M.db.roundIcons and true or false
	local kit = KitOn()
	for _, b in ipairs(bar.buttons) do
		if not b.mask then
			b.mask = b:CreateMaskTexture()
			b.mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			b.mask:SetAllPoints(b.icon)
			b.rim = b:CreateTexture(nil, "OVERLAY")
			b.rim:SetTexture(RIM_TEXTURE)
			-- the rim art sits in the top left of its texture: 53 wide for a 21 wide opening
			local k = b:GetWidth() / 21
			b.rim:SetSize(53 * k, 53 * k)
			b.rim:SetPoint("TOPLEFT", b, "TOPLEFT", -5 * k, 4 * k)
		end
		if round then
			b.icon:AddMaskTexture(b.mask)
			b.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
			b.rim:SetShown(not kit)
		else
			b.icon:RemoveMaskTexture(b.mask)
			b.icon:SetTexCoord(0, 1, 0, 1)
			b.rim:Hide()
		end
		-- the kit's rim (SR2 round; square for square icons), the icon in
		-- its opening; the game's anchors back when the kit is off
		if kit then
			local want = KitRim(b, round)
			for _, key in ipairs({ "kitRoundRim", "kitSquareRim" }) do
				if b[key] then
					b[key]:SetShown(b[key] == want)
				end
			end
			want.icon = b.icon
			MelloUI.Kit:SlotPlaceIcon(want)
		else
			for _, key in ipairs({ "kitRoundRim", "kitSquareRim" }) do
				if b[key] then
					b[key]:Hide()
				end
			end
			b.icon:ClearAllPoints()
			b.icon:SetAllPoints(b)
		end
	end
	if round then
		-- Dark Mode shades the rims with the minimap art.
		local dark = MelloUI:GetModule("DarkMode")
		if dark and dark.isEnabled and dark.Reapply then
			dark:Reapply("minimap")
		end
	end
	local merged = Merged()
	BarStone(merged)
	if bar.SetBackdrop then
		if merged then
			SetKitBox(bar, false)   -- the minimap's frame is its border, its stone the ground
			bar:SetBackdrop(nil)
		elseif not SetKitBox(bar, kit) then
			bar:SetBackdrop({
				bgFile = "Interface/Tooltips/UI-Tooltip-Background",
				edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
				tile = true, tileSize = 16, edgeSize = 12,
				insets = { left = 3, right = 3, top = 3, bottom = 3 },
			})
			bar:SetBackdropColor(0.05, 0.05, 0.06, 0.85)
			bar:SetBackdropBorderColor(0.55, 0.45, 0.25, 1)
		end
	end
	-- the nearest-service menu on the same box (SV1)
	if menu and menu.SetBackdrop and not SetKitBox(menu, kit) then
		menu:SetBackdrop({
			bgFile = "Interface/Tooltips/UI-Tooltip-Background",
			edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		menu:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
		menu:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
	end
end

local function ApplyBar()
	if M.db.showBar and M.isEnabled then
		CreateBar()
	end
	if bar then
		LayerBar()
		bar:SetShown(M.isEnabled and M.db.showBar and true or false)
		if bar:IsShown() then
			RefreshBar()
		end
		WatchBar(bar:IsVisible())
	end
	ApplyStand()
	ApplyIconShape()
	LayoutBar()
	TellColumn()
end

--------------------------------------------------------------------------------
-- Minimap button
--------------------------------------------------------------------------------

local function UpdateButtonPosition()
	local button = M.button
	if not button then
		return
	end
	local angle = math.rad(tonumber(M.db.angle) or 205)
	local radius = 80
	local x, y = math.cos(angle) * radius, math.sin(angle) * radius
	-- A square minimap wants the button on its edge, not on a circle.
	if GetMinimapShape then
		local ok, shape = pcall(GetMinimapShape)
		if ok and shape == "SQUARE" then
			local q = math.max(math.abs(math.cos(angle)), math.abs(math.sin(angle)))
			x, y = math.cos(angle) / q * radius, math.sin(angle) / q * radius
		end
	end
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- While the button is dragged (its OnUpdate is on only then): it follows the
-- cursor round the minimap.
local function FollowCursor()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	cx, cy = cx / scale, cy / scale
	M.db.angle = math.deg(math.atan2(cy - my, cx - mx))
	UpdateButtonPosition()
end

local function CreateButton()
	if M.button or not Minimap then
		return
	end
	local button = CreateFrame("Button", "MelloUIServicesButton", Minimap)
	M.button = button
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")
	local overlay = button:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(53, 53)
	overlay:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT")
	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetSize(20, 20)
	background:SetTexture("Interface/Minimap/UI-Minimap-Background")
	background:SetPoint("TOPLEFT", 7, -5)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetTexture("Interface/Icons/INV_Misc_Map_01")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetPoint("TOPLEFT", 7, -6)
	button.icon = icon
	Perf.SetScript(button, "OnClick", function(self, mouse)
		if mouse == "RightButton" then
			local R = MelloUI.Route
			if R and R.Clear then
				R:Clear()
			end
			if C_Map.ClearUserWaypoint then
				pcall(C_Map.ClearUserWaypoint)
			end
			if menu then
				menu:Hide()
			end
			return
		end
		ToggleMenu(self)
	end)
	Perf.SetScript(button, "OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Services", 1, 1, 1)
		GameTooltip:AddLine("Click: the list of the nearest services.", nil, nil, nil, true)
		GameTooltip:AddLine("Right-click: stop the route.  Drag: move the button.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	Perf.SetScript(button, "OnLeave", function() GameTooltip:Hide() end)
	Perf.SetScript(button, "OnDragStart", function(self)
		self.dragging = true
		GameTooltip:Hide()
		Perf.SetScript(self, "OnUpdate", FollowCursor)
	end)
	Perf.SetScript(button, "OnDragStop", function(self)
		self.dragging = nil
		Perf.SetScript(self, "OnUpdate", nil)
		MelloUI:NotifySettingChanged(M.name, "angle", M.db.angle)
	end)
	UpdateButtonPosition()
end

local function ApplyButton()
	if M.db.showButton and M.isEnabled then
		CreateButton()
	end
	if M.button then
		M.button:SetShown(M.isEnabled and M.db.showButton and true or false)
		UpdateButtonPosition()
	end
end

--------------------------------------------------------------------------------
-- Slash command and lifecycle
--------------------------------------------------------------------------------

SLASH_MELLOSERVICES1 = "/services"
SlashCmdList.MELLOSERVICES = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "" then
		ToggleMenu(M.button)
		return
	end
	for _, kind in ipairs(KINDS) do
		if kind.key == msg or kind.label:lower() == msg or kind.label:lower():find(msg, 1, true) == 1 then
			GoTo(kind)
			return
		end
	end
	MelloUI:Print("/services  |  /services repair | mailbox | innkeeper | flight | auction | bank | class trainer | profession trainer | barber | transmog")
end

function M:OnInit(db)
	self.db = db
end

local relayoutHooked = false
local function HookRelayout()
	if relayoutHooked then
		return
	end
	relayoutHooked = true
	-- the minimap can be resized or moved in Edit Mode: fit the stand and the bar again
	if Minimap and Minimap.HookScript then
		Perf.HookScript(Minimap, "OnSizeChanged", function() C_Timer.After(0, ApplyBar) end)
	end
	-- and when Edit Mode closes (the kit's one Edit Mode registration, the
	-- bus's 'editmode'; audit, 2026-09-24)
	MelloUI:On("editmode", function(entering)
		if not entering then
			C_Timer.After(0, ApplyBar)
		end
	end, M)
end

local coverWatched = false

function M:OnEnable(db)
	self.db = db
	ForgetTaxis()
	HookRelayout()
	ApplyButton()
	ApplyBar()
	if not coverWatched and MelloUI.Kit and MelloUI.Kit.OnCover then
		coverWatched = true
		MelloUI.Kit:OnCover(function(group)
			if group == "minimap" and M.isEnabled then
				ApplyBar()   -- the bar's look goes with the painted minimap
			end
		end)
	end
	for _, event in ipairs(EVENTS) do
		pcall(eventFrame.RegisterEvent, eventFrame, event)
	end
end

function M:OnDisable()
	eventFrame:UnregisterAllEvents()
	if M.button then
		M.button:Hide()
	end
	if bar then
		bar:Hide()
	end
	if menu then
		menu:Hide()
	end
	ApplyStand()
	TellColumn()
end

-- The minimap's frame changed (its shape, border, Merge With Services): the
-- bar laid out again, without calling back (MinimapPanel lays itself out)
function M:LayoutForMinimap()
	if bar and M.isEnabled then
		ApplyIconShape()
		LayoutBar()
	end
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	ApplyButton()
	ApplyBar()
end

MelloUI:Profile("Services", "service window events", eventFrame)
