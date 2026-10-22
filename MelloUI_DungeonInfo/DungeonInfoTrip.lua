--------------------------------------------------------------------------------
-- MelloUI - Dungeon Info: the row at a dungeon's door, and the quest trip
--
-- The row at the door (the user's pick D of journal_placements, a switch that starts off: doorRow): within DOOR_NEAR
-- yards of a dungeon's door, or inside it, a row in the widget column (MelloUI.Reminders, column = true) -- its
-- emblem, its name, its bosses and how many of your items drop there; a click, or its list button, opens its page
-- in Dungeon Info, its way button picks up its quests (the trip). Checked on the zone's changes and, while it shows,
-- as you move (Route's 'where'); nothing while the switch is off.
--
-- The quest trip (the user, 2026-10-22: "Pick Up all the Quests ... the route leads him in the most time efficient
-- way possible"; their pick A of journal_loot_trip: every stop on the map): Trip.Start(inst) below.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Safe = MelloUI.Safe
local Num = Safe.Number
local J = ns.DungeonInfo

local Trip = {}
J.Trip = Trip

local EMBLEM = "Interface\\LFGFrame\\LFGIcon-"
local DOOR_NEAR = 70   -- yards from a door the row comes up

local TEXT = {
	label = "Dungeon Info: at a dungeon's door",
	bosses = "%d bosses",
	bossesMine = "%d bosses, %d of your items drop here",
	mineOnly = "%d of your items drop here",
	dungeonInfo = "Dungeon Info",
	dungeonInfoDesc = "Its bosses and what they drop, beside the map.",
	quests = "Pick Up Its Quests",
	questsDesc = "Route takes you to every quest of it you can take now, in the fastest order.",
	hint = "Click: its page in Dungeon Info",
}

--------------------------------------------------------------------------------
-- The row at a dungeon's door
--------------------------------------------------------------------------------

local D = { inst = nil, doors = nil, on = false }

-- the doors in Route's yards, worked out the first time they are asked for
local function Doors()
	local R = rawget(MelloUI, "Route")
	if D.doors or not (R and R.WorldYards) then
		return D.doors
	end
	local list = {}
	for kind = 1, 2 do
		for _, inst in ipairs(J.List(kind)) do
			local door = J.Door(inst)
			if door then
				local cont, x, y = R:WorldYards(door.cont, door.wx, door.wy)
				if cont then
					list[#list + 1] = { inst = inst, cont = cont, x = x, y = y }
				end
			end
		end
	end
	D.doors = list
	return list
end

-- the instance you are at: inside it (the game's instance), or within DOOR_NEAR yards of its door
local function Near()
	local ok, _, itype, _, _, _, _, _, mapID = pcall(GetInstanceInfo)
	if ok and (itype == "party" or itype == "raid") then
		local inst = J.ByMap(Num(mapID))
		if inst then
			return inst
		end
	end
	local R = rawget(MelloUI, "Route")
	if not (R and R.Where) then
		return nil
	end
	local cont, x, y = R:Where()
	if not cont then
		return nil
	end
	local best, bestD
	for _, d in ipairs(Doors() or {}) do
		if d.cont == cont then
			local dist = math.sqrt((d.x - x) ^ 2 + (d.y - y) ^ 2)
			if dist <= DOOR_NEAR and (not bestD or dist < bestD) then
				best, bestD = d.inst, dist
			end
		end
	end
	return best
end

local function Open()
	if D.inst then
		J.Open(D.inst.key)
	end
end

local function PickUp()
	if D.inst then
		Trip.Start(D.inst)
	end
end

local DOOR = {
	key = "dungeonInfoDoor", column = true, label = TEXT.label, priority = "ongoing", hint = TEXT.hint,
	when = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "where" },
	check = function()
		D.inst = Near()
		return D.inst ~= nil
	end,
	title = function()
		return D.inst and D.inst.name or TEXT.dungeonInfo
	end,
	text = function()
		local inst = D.inst
		if not inst then
			return ""
		end
		local n, mine = #inst.bosses, J.TrackedIn(inst)
		if mine > 0 then
			return n > 0 and TEXT.bossesMine:format(n, mine) or TEXT.mineOnly:format(mine)
		end
		return n > 0 and TEXT.bosses:format(n) or ""
	end,
	icon = function()
		return D.inst and (EMBLEM .. D.inst.emblem) or (EMBLEM .. "dungeon")
	end,
	onClick = function()
		Open()
	end,
	actions = {
		{ glyph = "list", tip = TEXT.dungeonInfo, desc = TEXT.dungeonInfoDesc, fn = Open },
		{ glyph = "way", tip = TEXT.quests, desc = TEXT.questsDesc, fn = PickUp,
		  shown = function()
			  local P = J.Panel
			  return D.inst ~= nil and P and P.Takeable and P.Takeable(D.inst) > 0 or false
		  end },
	},
}

-- the row registered while the module is on and its switch is (DungeonInfo.lua: OnEnable, OnSettingChanged)
function J.DoorRow(on)
	local Rem = rawget(MelloUI, "Reminders")
	if not (type(Rem) == "table" and Rem.Register) then
		return
	end
	local db = J.M.db
	on = on and db and db.doorRow == true or false
	if on == D.on then
		return
	end
	D.on = on
	if on then
		Rem:Register(DOOR)
	else
		Rem:Unregister(DOOR.key)
		D.inst = nil
	end
end

-- (the tests')
Trip.D = D

--------------------------------------------------------------------------------
-- The quest trip: the dungeon's quests you can take now, one stop a giver (several quests of one giver: one stop),
-- every way between them priced by Route (M:PriceFrom: from you and from each stop to all the others), put in the
-- fastest order from where you stand -- every order tried for up to HK_MAX stops (Held-Karp), the nearest first and
-- then 2-opt beyond -- with the dungeon's door the last stop; then Route leads it (M:Trip): a stop is passed once its
-- quests are in your log (QUEST_ACCEPTED), or skipped from the trip's page. Nothing of it is made before a trip.
--   Trip.Start(inst)   Trip.cur (the trip: inst, stops, secs, status "pricing" | "on" | "done" | "ended")
--   Trip.LayPage()     its page in Dungeon Info (DungeonInfoPanel's tripPage)
--------------------------------------------------------------------------------

local Perf = MelloUI.Perf:Scope("MelloUI_DungeonInfo (Trip)")
local CreateFrame = MelloUI.Safe.CreateFrame   -- (a frame inside an open window: the gamepad navigation left out)
local W = MelloUI.Widgets
local floor, max = math.floor, math.max

local HK_MAX = 10      -- stops ordered by trying every order (2^n * n^2 steps); the nearest first and 2-opt past it
local FAR = 100000     -- the price of a way Route has none for (seconds)
local SAME_GIVER = 15  -- yards apart, one giver's quests still one stop

local TT = {
	title = "Pick Up Quests",
	pricing = "Working out the fastest order...",
	stops = "%d stops, about %s",
	stopsDoor = "%d stops and the door, about %s",
	arrived = "Take the quests here: the trip goes on by itself.",
	done = "Done: every quest of it is in your log.",
	ended = "The trip has ended.",
	none = "No quest of it to take now.",
	noRoute = "The quest trip needs Route: switch it on in the configurator.",
	noPlace = "Your place is not known here: try again outside.",
	stopsHead = "Stops",
	door = "Its door",
	doorLine = "The dungeon's door, the trip's end",
	skip = "Skip This Stop", skipTip = "Route takes you on to the next stop.",
	stop = "End The Trip", stopTip = "The trip and its route end.",
	notice = "  Quest trip: %s, {dist} away",
	minutes = "%d min", seconds = "%d s",
	rowTip = "Click: the map shows it",
}
Trip.TEXT = TT

local function Route()
	local R = rawget(MelloUI, "Route")
	return (type(R) == "table" and R.Trip and R.isEnabled) and R or nil
end

local function Took(secs)
	secs = Num(secs)
	if not secs then
		return ""
	end
	if secs < 60 then
		return TT.seconds:format(max(1, floor(secs + 0.5)))
	end
	return TT.minutes:format(floor(secs / 60 + 0.5))
end

-- every quest of a stop in your log (or done)
local function Taken(s)
	for _, id in ipairs(s.quests or {}) do
		if not J.Taken(id) then
			return false
		end
	end
	return true
end

local function AllTaken(cur)
	for _, s in ipairs(cur.stops) do
		if s.hold and not Taken(s) then
			return false
		end
	end
	return true
end

-- the page laid again while it shows
local function Refresh()
	local P = J.Panel
	local S = P and P.S
	if S and S.built and S.shown and S.pager:Current() == S.tripPage then
		Trip.LayPage()
	end
end

--------------------------------------------------------------------------------
-- The order
--------------------------------------------------------------------------------

-- the stops 1..n in the fastest order from 0 (you), the door (n + 1) after the last when there is one; C(i, j) the
-- way's price
local function Order(n, C, door)
	local order = {}
	if n == 0 then
		return order
	end
	local function EndCost(j)
		return door and C(j, door) or 0
	end
	if n <= HK_MAX then
		-- every order (Held-Karp): dp[set * 32 + j] the cheapest way from you through `set` (a stop's bit 2^(j-1)),
		-- ending at j
		local two = {}
		for j = 1, n do
			two[j] = 2 ^ (j - 1)
		end
		local dp, from = {}, {}
		for j = 1, n do
			dp[two[j] * 32 + j] = C(0, j)
		end
		local full = 2 ^ n - 1
		for set = 1, full do
			for j = 1, n do
				local here = dp[set * 32 + j]
				if here then
					for k = 1, n do
						local bk = two[k]
						if floor(set / bk) % 2 == 0 then
							local key = (set + bk) * 32 + k
							local v = here + C(j, k)
							if not dp[key] or v < dp[key] then
								dp[key], from[key] = v, j
							end
						end
					end
				end
			end
		end
		local best, last
		for j = 1, n do
			local v = dp[full * 32 + j] + EndCost(j)
			if not best or v < best then
				best, last = v, j
			end
		end
		local set = full
		for i = n, 1, -1 do
			order[i] = last
			local prev = from[set * 32 + last]
			set = set - two[last]
			last = prev
		end
		return order
	end
	-- the nearest first
	local left = {}
	for j = 1, n do
		left[j] = true
	end
	local at = 0
	for i = 1, n do
		local best, pick
		for j in pairs(left) do
			local v = C(at, j)
			if not best or v < best then
				best, pick = v, j
			end
		end
		order[i], left[pick], at = pick, nil, pick
	end
	-- then 2-opt: a stretch turned round while that makes the whole way cheaper (the prices may differ each way)
	local function Total(o)
		local sum, prev = 0, 0
		for i = 1, n do
			sum, prev = sum + C(prev, o[i]), o[i]
		end
		return sum + EndCost(prev)
	end
	local best = Total(order)
	local better = true
	while better do
		better = false
		for i = 1, n - 1 do
			for k = i + 1, n do
				local o = {}
				for m = 1, n do
					o[m] = (m >= i and m <= k) and order[i + k - m] or order[m]
				end
				local v = Total(o)
				if v < best - 0.5 then
					order, best, better = o, v, true
				end
			end
		end
	end
	return order
end
Trip.Order = Order

--------------------------------------------------------------------------------
-- Starting it
--------------------------------------------------------------------------------

-- the quests you can take now, one stop a giver; the door last
local function Stops(inst)
	local F = J.F
	local stops = {}
	local mark = W.IconMarkup("quest_mark", 22)
	for _, q in ipairs(J.Quests(inst)) do
		local row = q.row
		local cont, wx, wy = Num(row[F.CONT]), Num(row[F.WX]), Num(row[F.WY])
		if q.state == "take" and cont and cont >= 0 and wx and wy and (wx ~= 0 or wy ~= 0) then
			local giver = row[F.GIVER] or "?"
			local s
			for _, o in ipairs(stops) do
				if o.label == giver and o.wcont == cont and math.abs(o.wx - wx) <= SAME_GIVER
					and math.abs(o.wy - wy) <= SAME_GIVER then
					s = o
				end
			end
			if not s then
				s = { wcont = cont, wx = wx, wy = wy, label = giver, hold = true, quests = {}, titles = {},
					notice = mark .. TT.notice:format(giver) }
				stops[#stops + 1] = s
			end
			s.quests[#s.quests + 1] = row[F.ID]
			s.titles[#s.titles + 1] = row[F.TITLE]
		end
	end
	local door = J.Door(inst)
	local doorStop
	if door and #stops > 0 then
		doorStop = { wcont = door.cont, wx = door.wx, wy = door.wy, label = inst.name, hold = false, door = true,
			notice = mark .. TT.notice:format(inst.name) }
	end
	return stops, doorStop
end

local OnTrip, Listen

-- the prices in: the order, then Route leads it
local function Priced(cur, nodes, prices, n, doorAt)
	if Trip.cur ~= cur then
		return
	end
	local R = Route()
	if not R then
		cur.status = "ended"
		Refresh()
		return
	end
	local walk = R.WALK or 7
	local function C(i, j)
		local v = prices[i] and prices[i][j]
		if v == nil then
			local a, b = nodes[i], nodes[j]
			v = a[1] == b[1] and math.sqrt((a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2) / walk * 1.3 or FAR
		end
		return v
	end
	local order = Order(n, C, doorAt)
	local list, secs, prev = {}, {}, 0
	for i, j in ipairs(order) do
		list[i], secs[i], prev = nodes[j].stop, C(prev, j), j
	end
	if doorAt then
		list[#list + 1], secs[#secs + 1] = nodes[doorAt].stop, C(prev, doorAt)
	end
	cur.stops, cur.secs = list, secs
	if not R:Trip(list) then
		cur.status = "ended"
		Refresh()
		return
	end
	cur.rt, cur.status = R:TripState(), "on"
	Listen(true)
	Trip.Check()
	Refresh()
end

-- every way between you and the stops priced (one search from you and one from each stop), then Priced
local function Price(cur)
	local R = Route()
	if not R or Trip.cur ~= cur then
		return
	end
	local pcont, px, py = R:Where()
	if not pcont then
		cur.status = "ended"
		MelloUI:Print(TT.noPlace)
		Refresh()
		return
	end
	local nodes = { [0] = { pcont, px, py } }
	local n = 0
	for _, s in ipairs(cur.quests) do
		local c, x, y = R:WorldYards(s.wcont, s.wx, s.wy)
		if c then
			n = n + 1
			nodes[n] = { c, x, y, stop = s }
		end
	end
	local doorAt
	local d = cur.door
	if d then
		local c, x, y = R:WorldYards(d.wcont, d.wx, d.wy)
		if c then
			doorAt = n + 1
			nodes[doorAt] = { c, x, y, stop = d }
		end
	end
	if n == 0 then
		cur.status = "ended"
		Refresh()
		return
	end
	local targets = {}
	for j = 1, doorAt or n do
		targets[j] = nodes[j]
	end
	local prices, waiting = {}, n + 1
	for i = 0, n do
		local from = i
		local asked = R:PriceFrom(nodes[from], targets, function(costs)
			prices[from] = costs
			waiting = waiting - 1
			if waiting == 0 then
				Priced(cur, nodes, prices, n, doorAt)
			end
		end)
		if not asked then
			-- (the roads not in after all: asked again once they are)
			R:WhenReady(function()
				Price(cur)
			end)
			return
		end
	end
end

function Trip.Start(inst)
	if not inst then
		return
	end
	local cur = Trip.cur
	local R = Route()
	if cur and cur.inst == inst and (cur.status == "pricing" or cur.status == "on") and R and R:TripState() == cur.rt then
		J.Panel.ShowTrip(inst)   -- (on its way already: its page)
		return
	end
	if not R then
		MelloUI:Print(TT.noRoute)
		return
	end
	local quests, door = Stops(inst)
	if #quests == 0 then
		MelloUI:Print(TT.none)
		return
	end
	if cur and cur.status == "on" and R:TripState() == cur.rt then
		R:TripEnd()
	end
	cur = { inst = inst, quests = quests, door = door, stops = {}, secs = {}, status = "pricing" }
	Trip.cur = cur
	if J.Panel and J.Panel.ShowTrip then
		J.Panel.ShowTrip(inst)
	end
	R:WhenReady(function()
		Price(cur)
	end)
end

--------------------------------------------------------------------------------
-- Following it: a stop passed once its quests are taken; the trip's end
--------------------------------------------------------------------------------

function Trip.Check()
	local cur, R = Trip.cur, Route()
	local rt = R and R:TripState()
	if not (cur and cur.status == "on" and rt and rt == cur.rt) then
		return
	end
	for _ = 1, #rt.stops do
		local s = rt.stops[rt.at]
		if not (s and s.hold and Taken(s)) then
			return
		end
		if not R:TripNext() then
			return
		end
		if R:TripState() ~= rt then
			return
		end
	end
end

local CheckSoon = Perf.Shared("Dungeon Info's trip checked (quests taken)", function()
	Trip.checking = false
	Trip.Check()
	Refresh()
end)

local OnEvent = Perf.Shared("OnEvent of Dungeon Info's trip", function()
	if not Trip.checking then
		Trip.checking = true
		Perf.C_Timer.After(0.2, CheckSoon)   -- (the log's index of a quest just taken: there a moment later)
	end
end, "script")

-- the bus's "route:trip": the trip's end seen, its page laid again
OnTrip = function()
	local cur = Trip.cur
	if cur and cur.status == "on" then
		local R = Route()
		if not (R and R:TripState() == cur.rt) then
			cur.status = AllTaken(cur) and "done" or "ended"
			Listen(false)
		end
	end
	Refresh()
end

Listen = function(on)
	local f = Trip.events
	if on and not f then
		f = CreateFrame("Frame")
		Perf.SetScript(f, "OnEvent", OnEvent)
		Trip.events = f
		MelloUI:On("route:trip", OnTrip, "Dungeon Info trip")
	end
	if not f then
		return
	end
	if on then
		f:RegisterEvent("QUEST_ACCEPTED")
		f:RegisterEvent("QUEST_LOG_UPDATE")
	else
		f:UnregisterAllEvents()
	end
end

--------------------------------------------------------------------------------
-- Its page: the stops in their order, the time to each, Skip This Stop and End The Trip
--------------------------------------------------------------------------------

local G = { rows = {} }

local ButtonClick = Perf.Shared("OnClick on Dungeon Info's trip buttons", function(self)
	local R = Route()
	local cur = Trip.cur
	if not (R and cur and cur.status == "on" and R:TripState() == cur.rt) then
		return
	end
	MelloUI:PlayUISound("click")
	if self == G.skip then
		R:TripNext()
	else
		R:TripEnd()
	end
end, "script")

local ButtonEnter = Perf.Shared("OnEnter on Dungeon Info's trip buttons", function(self)
	W.ShowTooltip(self, self.label:GetText(), self.tip)
end, "script")

local RowClick = Perf.Shared("OnClick on Dungeon Info's trip stops", function(self)
	local s = self.stop
	local map = MelloUI:GetModule("Map")
	if s and map and map.ShowWorld then
		MelloUI:PlayUISound("click")
		map:ShowWorld(s.wcont, s.wx, s.wy)
	end
end, "script")

local RowEnter = Perf.Shared("OnEnter on Dungeon Info's trip stops", function(self)
	if self.stop then
		W.ShowTooltip(self, self.title:GetText() or "", TT.rowTip)
	end
end, "script")

local function Button(parent, T, icon, label, tip)
	local b = W.RoundIcon(parent, T.BUTTON, T.ICONS .. icon)
	b.label = W.Text(parent, "GameFontHighlight", label, "text")
	b.label:SetPoint("TOP", b, "BOTTOM", 0, -4)
	b.label:SetJustifyH("CENTER")
	b.tip = tip
	Perf.SetScript(b, "OnClick", ButtonClick)
	Perf.SetScript(b, "OnEnter", ButtonEnter)
	Perf.SetScript(b, "OnLeave", W.TipLeave)
	return b
end

local function Build(page, T)
	G.built = true
	G.back = J.Panel.Kit.BackButton(page)
	G.title = W.Text(page, "GameFontNormalLarge", TT.title, "selectedTrim")
	G.sub = W.Text(page, "GameFontHighlight", nil, "text")
	G.sub:SetPoint("TOPLEFT", G.title, "BOTTOMLEFT", 0, -4)
	G.row = CreateFrame("Frame", nil, page)
	G.row:SetHeight(T.BUTTON_ROW)
	G.skip = Button(G.row, T, "btn_next", TT.skip, TT.skipTip)
	G.stop = Button(G.row, T, "btn_stop", TT.stop, TT.stopTip)
end

local function Row(page, i)
	local r = G.rows[i]
	if r then
		return r
	end
	r = CreateFrame("Button", nil, page)
	r:RegisterForClicks("LeftButtonUp")
	r.disc = r:CreateTexture(nil, "ARTWORK", nil, 1)
	r.disc:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
	r.disc:SetSize(22, 22)
	r.disc:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -6)
	W.Paint(r.disc, "mainWindow", "vertex")
	r.ring = r:CreateTexture(nil, "ARTWORK", nil, 2)
	r.ring:SetPoint("CENTER", r.disc, "CENTER", 0, 0)
	r.ring:SetSize(26, 26)
	W.Icon(r.ring, "ring_gold")
	r.num = W.Text(r, "GameFontHighlight", nil, "text")
	r.num:SetPoint("CENTER", r.disc, "CENTER", 0, 0)
	r.icon = r:CreateTexture(nil, "ARTWORK", nil, 3)
	r.icon:SetSize(22, 22)
	r.icon:SetPoint("CENTER", r.disc, "CENTER", 0, 0)
	r.time = W.Text(r, "GameFontHighlight", nil, "text")
	r.time:SetPoint("TOPRIGHT", r, "TOPRIGHT", -4, -9)
	r.title = W.Text(r, "GameFontHighlight", nil, "text")
	r.title:SetWordWrap(false)
	r.title:SetPoint("TOPLEFT", r, "TOPLEFT", 38, -5)
	r.title:SetPoint("RIGHT", r.time, "LEFT", -8, 0)
	r.line = W.Text(r, "GameFontHighlight", nil, "text")
	W.Paint(r.line, "text", "text", 0.75)
	r.line:SetWordWrap(false)
	r.line:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -3)
	r.line:SetPoint("RIGHT", r, "RIGHT", -4, 0)
	Perf.SetScript(r, "OnClick", RowClick)
	Perf.SetScript(r, "OnEnter", RowEnter)
	Perf.SetScript(r, "OnLeave", W.TipLeave)
	W.RowPlate(r)
	G.rows[i] = r
	return r
end

function Trip.LayPage()
	local P = J.Panel
	local S, T, K = P.S, P.Measures(), P.Kit
	local page, width, cur = S.tripPage, S.pageW, Trip.cur
	if not (page and T and cur) then
		return
	end
	if not G.built then
		Build(page, T)
	end
	G.back.text:SetText(cur.inst.name)
	local y = T.FOLD + 10
	G.title:ClearAllPoints()
	G.title:SetPoint("TOPLEFT", page, "TOPLEFT", 2, -y)
	local R = Route()
	local rt = cur.status == "on" and R and R:TripState()
	if cur.status == "on" and rt ~= cur.rt then
		rt = nil
	end
	local at = rt and rt.at or (cur.status == "done" and #cur.stops + 1 or 1)
	local sub
	if cur.status == "pricing" then
		sub = TT.pricing
	elseif cur.status == "done" then
		sub = TT.done
	elseif cur.status == "ended" then
		sub = TT.ended
	elseif rt and rt.arrived then
		sub = TT.arrived
	else
		local secs, quests, door = 0, 0, false
		for i = at, #cur.stops do
			secs = secs + (cur.secs[i] or 0)
			if cur.stops[i].door then
				door = true
			else
				quests = quests + 1
			end
		end
		sub = (door and TT.stopsDoor or TT.stops):format(quests, Took(secs))
	end
	G.sub:SetText(sub)
	y = y + (Num(G.title:GetStringHeight()) or 16) + 4 + (Num(G.sub:GetStringHeight()) or 12) + 12
	-- the buttons, while it is on
	local on = rt ~= nil
	G.row:SetShown(on)
	G.skip.label:SetShown(on)
	G.stop.label:SetShown(on)
	if on then
		G.row:ClearAllPoints()
		G.row:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
		G.row:SetSize(width, T.BUTTON_ROW)
		local step = width / 2
		G.skip:ClearAllPoints()
		G.skip:SetPoint("TOP", G.row, "TOPLEFT", step * 0.5, 0)
		G.stop:ClearAllPoints()
		G.stop:SetPoint("TOP", G.row, "TOPLEFT", step * 1.5, 0)
		y = y + T.BUTTON_ROW + 6
	end
	-- the stops
	local list = cur.status == "pricing" and cur.quests or cur.stops
	y = K.PutHeading(page, 1, y, width, TT.stopsHead, #list > 0 and #list or nil)
	for i, s in ipairs(list) do
		local r = Row(page, i)
		r.stop = s
		local passed = cur.status ~= "pricing" and i < at
		local now = rt ~= nil and i == at
		r.num:SetText(i)
		r.num:SetShown(not passed and not s.door)
		if passed then
			W.Icon(r.icon, "ql_completed")
		elseif s.door then
			r.icon:SetTexture(EMBLEM .. cur.inst.emblem)
			r.icon:SetTexCoord(0, 1, 0, 1)
		end
		r.icon:SetShown(passed or s.door == true)
		r.title:SetText(s.door and (TT.door .. ": " .. s.label) or s.label)
		W.Paint(r.title, now and "selectedTrim" or "text", "text")
		r.line:SetText(s.door and TT.doorLine or table.concat(s.titles, ", "))
		r.time:SetText(cur.status ~= "pricing" and not passed and cur.secs[i] and ("+" .. Took(cur.secs[i])) or "")
		r:SetAlpha(passed and 0.55 or 1)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
		r:SetSize(width, 40)
		r:Show()
		y = y + 40
	end
	K.HideFrom(G.rows, #list)
	K.HideFrom(S.heads[page] or {}, 1)
	K.PageHeight(page, max(y + T.PAD, 1))
end
