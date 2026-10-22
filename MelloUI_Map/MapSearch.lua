--------------------------------------------------------------------------------
-- MelloUI Map - search (docs/plans/seamless-map.md, stage M4)
--
-- One box in the map's title row (the UI's own text field, W.FlatField), its
-- matches in a list under it: the places (zones, cities, continents), the
-- towns, camps and named sub-zones (MelloUI_PlaceData, from the client's
-- tables), the quests in your log, dungeons and raids, flight masters, boats and
-- zeppelins, and the quest givers of the Quest List's data (a quest by its
-- title or its giver). Up and Down move through them, Enter (or a click)
-- takes one: a place framed, a point glided to and marked, a quest of your
-- log opened on its page. Escape empties the box and lets it go.
--
-- The index is made the first time you type (nothing at login, nothing while
-- the map is closed), again when the map has opened since; a match is laid
-- from it, never made per key.
--
--   Search.Init(win)    the box and its list on the map's window (Map.lua's Build)
--   Search.Find(text)   the matches for a text (the tests' way in): a list of entries
--   Search.Take(entry)  an entry taken
--   Search.Hidden()     the map closed: the list, the mark and the index let go
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_Map (Search)")
local Safe = MelloUI.Safe
local Finite, Text = Safe.Finite, Safe.Text
local W = MelloUI.Widgets
local max, min = math.max, math.min
local pairs, ipairs, type, pcall = pairs, ipairs, type, pcall

local Search = {}
ns.Search = Search

local T = {
	W = 240, H = 20,            -- the box
	RIGHT = -44, TOP = -7,      -- its place in the title row (left of the close button)
	LIST_W = 320, ROWS = 10, ROW_H = 26, ICON = 18, PAD = 6,
	ZOOM = 6,                   -- a point found: the map at least this close
	ICONS = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Icons\\",
	MARK = "goal_cream",        -- the place found, marked
	ORDER = 45,                 -- the mark's layer: over the group, under the player
	KIND_RANK = { place = 1, area = 2, log = 3, dungeon = 4, raid = 4, flight = 5, dock = 6, quest = 7, giver = 8 },
}

local TEXT = {
	prompt = "Search the map",
	place = { zone = "Zone", city = "City", continent = "Continent" },
	area = "Place",
	log = "Your quest", dungeon = "Dungeon", raid = "Raid", flight = "Flight master", dock = "Boat or zeppelin",
	quest = "Quest", giver = "Quest giver",
	none = "Nothing on the map by that name.",
}

local S = { win = nil, index = nil, matches = {}, rows = {}, sel = 1, markSpec = nil }

--------------------------------------------------------------------------------
-- The index: one entry a thing to find, { key (lower case), name, sub, icon, kind, ... }
--------------------------------------------------------------------------------

local function Add(index, kind, name, sub, icon, fields)
	name = Text(name)
	if not name or name == "" then
		return
	end
	local e = fields or {}
	e.kind, e.name, e.sub, e.icon, e.key = kind, name, sub, icon, name:lower()
	index[#index + 1] = e
end

local function QuestList()
	local QL = rawget(MelloUI, "QuestList")
	return type(QL) == "table" and QL.F_TITLE and QL or nil
end

local function Build()
	local index = {}
	local c, Layers = S.win.canvas, ns.Layers
	-- the places
	c:EachPlace(function(p)
		local sub = TEXT.place[p.kind]
		if sub then
			Add(index, "place", p.name, sub, nil, { id = p.id })
		end
	end)
	-- the towns, camps and named sub-zones (MelloUI_PlaceData: [world map] = x, y, reach, name ...), not again a
	-- place's own name
	local point = Layers and Layers.WorldPoint
	local named = {}
	for _, e in ipairs(index) do
		named[e.key] = true
	end
	local areas = rawget(_G, "MelloUI_PlaceData")
	if type(areas) == "table" and point then
		for mapID, rows in pairs(areas) do
			for i = 1, #rows - 3, 4 do
				local name = rows[i + 3]
				if type(name) == "string" and not named[name:lower()] then
					local wx, wy = point(mapID, rows[i], rows[i + 1])
					if wx then
						Add(index, "area", name, TEXT.area, nil, { wx = wx, wy = wy })
					end
				end
			end
		end
	end
	-- your quests
	local Q = C_QuestLog
	if Q and Q.GetNumQuestLogEntries and Q.GetInfo then
		local ok, n = pcall(Q.GetNumQuestLogEntries)
		local zone = ""
		for i = 1, ok and Finite(n) or 0 do
			local okI, info = pcall(Q.GetInfo, i)
			if okI and type(info) == "table" and not Safe.Value(info.isHidden) then
				if Safe.Value(info.isHeader) then
					zone = Text(info.title) or ""
				elseif Finite(info.questID) then
					Add(index, "log", info.title, zone ~= "" and (TEXT.log .. ", " .. zone) or TEXT.log, T.ICONS .. "track_todo",
						{ questID = Finite(info.questID) })
				end
			end
		end
	end
	-- dungeons, raids, flight masters, docks: the names the layers laid
	if Layers and Layers.Searchable then
		Layers.Searchable(function(kind, name, icon, wx, wy)
			Add(index, kind, name, TEXT[kind], icon, { wx = wx, wy = wy })
		end)
	end
	-- the Quest List's quests (not done, open to you) and their givers (one entry a giver and place)
	local QL = QuestList()
	if QL and point and type(QL.allRows) == "table" then
		local givers = {}
		for _, row in ipairs(QL.allRows) do
			local id = row[QL.F_ID]
			local open = not (QL.IsCompleted and QL.IsCompleted(id)) and not (QL.Eligible and not QL.Eligible(row))
			if open then
				local wx, wy = point(row[QL.F_CONT], row[QL.F_WX], row[QL.F_WY])
				if wx then
					local giver = Text(row[QL.F_GIVER]) or ""
					Add(index, "quest", row[QL.F_TITLE], giver ~= "" and (TEXT.quest .. ": " .. giver) or TEXT.quest,
						T.ICONS .. "quest_mark", { wx = wx, wy = wy })
					local gkey = giver .. ":" .. math.floor(wx) .. ":" .. math.floor(wy)
					if giver ~= "" and not givers[gkey] then
						givers[gkey] = true
						Add(index, "giver", giver, TEXT.giver, T.ICONS .. "quest_mark", { wx = wx, wy = wy })
					end
				end
			end
		end
	end
	S.index = index
	return index
end

--------------------------------------------------------------------------------
-- Matching: a name that begins with the text first, then a word of it, then
-- anywhere; the kinds in their order; the shorter name first
--------------------------------------------------------------------------------

local function Score(e, text)
	local at = e.key:find(text, 1, true)
	if not at then
		return nil
	end
	local how = at == 1 and 0 or (e.key:sub(at - 1, at - 1):find("[%s%-%(']") and 1 or 2)
	return how * 100 + (T.KIND_RANK[e.kind] or 9) * 10 + min(9, #e.key / 8)
end

function Search.Find(text)
	local out = S.matches
	wipe(out)
	text = type(text) == "string" and text:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
	if #text < 2 then
		return out
	end
	local index = S.index or Build()
	local scored = {}
	for _, e in ipairs(index) do
		local s = Score(e, text)
		if s then
			e.score = s
			scored[#scored + 1] = e
		end
	end
	table.sort(scored, function(a, b)
		if a.score ~= b.score then
			return a.score < b.score
		end
		return a.name < b.name
	end)
	for i = 1, min(T.ROWS, #scored) do
		out[i] = scored[i]
	end
	return out
end

--------------------------------------------------------------------------------
-- Taking one
--------------------------------------------------------------------------------

local function Mark(wx, wy)
	local pins = S.win.pins
	if not S.markSpec then
		pins:Layer("search", T.ORDER)
		S.markSpec = { icon = T.ICONS .. T.MARK, size = 22, sub = 2, lift = T.MARK }
	end
	pins:Set("search", "found", wx, wy, S.markSpec)
	pins:Lay()
end

function Search.Take(e)
	local c = S.win.canvas
	if not e then
		return false
	end
	if e.kind == "place" then
		c:Fit(e.id)
		if S.win.pins.layers.search then
			S.win.pins:Clear("search")
		end
	elseif e.kind == "log" then
		local Log = ns.QuestLog
		if Log and Log.Select then
			Log.Select(e.questID)
		end
	elseif e.wx then
		c:Glide(e.wx, e.wy, max(c.z or 1, T.ZOOM))
		Mark(e.wx, e.wy)
	end
	MelloUI:PlayUISound("click")
	return true
end

--------------------------------------------------------------------------------
-- The box and its list
--------------------------------------------------------------------------------

local function Lay()
	local list, matches = S.list, S.matches
	for i = 1, T.ROWS do
		local r = S.rows[i]
		local e = matches[i]
		if e then
			r.entry = e
			if e.icon then
				MelloUI.Icons.Set(r.icon, e.icon, T.ICON)   -- (2026-10-21: the copy for its size)
				r.icon:Show()
			else
				r.icon:Hide()
			end
			r.name:SetText(e.name)
			r.sub:SetText(e.sub or "")
			r.sel:SetShown(i == S.sel)
			r:Show()
		else
			r.entry = nil
			r:Hide()
		end
	end
	local n = #matches
	local box = S.box
	local typed = box:GetText() or ""
	if n == 0 and #typed >= 2 then
		S.none:Show()
		list:SetHeight(T.ROW_H + 2 * T.PAD)
		list:Show()
	elseif n == 0 then
		list:Hide()
	else
		S.none:Hide()
		list:SetHeight(n * T.ROW_H + 2 * T.PAD)
		list:Show()
	end
end

local function Close()
	wipe(S.matches)
	S.sel = 1
	if S.list then
		S.list:Hide()
	end
end

local Changed = Perf.Shared("OnTextChanged on the map's search", function(box, user)
	if not user then
		return
	end
	S.sel = 1
	Search.Find(box:GetText())
	Lay()
end, "script")

local Arrow = Perf.Shared("OnArrowPressed on the map's search", function(_, key)
	local n = #S.matches
	if n == 0 then
		return
	end
	if key == "DOWN" then
		S.sel = S.sel % n + 1
	elseif key == "UP" then
		S.sel = (S.sel - 2) % n + 1
	end
	Lay()
end, "script")

local Enter = Perf.Shared("OnEnterPressed on the map's search", function(box)
	local e = S.matches[S.sel]
	if e then
		Search.Take(e)
		box:ClearFocus()
		Close()
	end
end, "script")

local Escape = Perf.Shared("OnEscapePressed on the map's search", function(box)
	box:SetText("")
	box:ClearFocus()
	Close()
end, "script")

local RowClick = Perf.Shared("OnClick on the map's search rows", function(row)
	if row.entry then
		Search.Take(row.entry)
		S.box:ClearFocus()
		Close()
	end
end, "script")

local RowEnter = Perf.Shared("OnEnter on the map's search rows", function(row)
	for i, r in ipairs(S.rows) do
		if r == row then
			S.sel = i
		end
	end
	Lay()
end, "script")

function Search.Init(win)
	S.win = win
	local f = win.frame
	local box = CreateFrame("EditBox", nil, f, "SearchBoxTemplate")
	box:SetSize(T.W, T.H)
	box:SetPoint("TOPRIGHT", f, "TOPRIGHT", T.RIGHT, T.TOP)
	box:SetAutoFocus(false)
	box:SetFrameLevel(f:GetFrameLevel() + 20)
	if box.Instructions then
		box.Instructions:SetText(TEXT.prompt)
	end
	W.FlatField(box)
	Perf.HookScript(box, "OnTextChanged", Changed)
	Perf.SetScript(box, "OnArrowPressed", Arrow)
	Perf.SetScript(box, "OnEnterPressed", Enter)
	Perf.SetScript(box, "OnEscapePressed", Escape)
	S.box = box
	local list = CreateFrame("Frame", nil, f)
	W.Panel(list, { on = true })
	list:SetWidth(T.LIST_W)
	list:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -4)
	list:SetFrameLevel(f:GetFrameLevel() + 600)   -- (over the canvas's pins and the quest log's column)
	list:EnableMouse(true)
	list:Hide()
	S.list = list
	S.none = W.Text(list, "GameFontHighlight", TEXT.none, "text")
	S.none:SetPoint("TOPLEFT", list, "TOPLEFT", T.PAD + 4, -T.PAD - 5)
	for i = 1, T.ROWS do
		local r = CreateFrame("Button", nil, list)
		r:SetHeight(T.ROW_H)
		r:SetPoint("TOPLEFT", list, "TOPLEFT", T.PAD, -T.PAD - (i - 1) * T.ROW_H)
		r:SetPoint("RIGHT", list, "RIGHT", -T.PAD, 0)
		r.sel = W.Solid(r, "BACKGROUND", "selectedTab", 1)
		r.sel:SetAllPoints()
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(T.ICON, T.ICON)
		r.icon:SetPoint("LEFT", r, "LEFT", 4, 0)
		r.name = W.Text(r, "GameFontHighlight", nil, "text")
		r.name:SetPoint("LEFT", r, "LEFT", T.ICON + 10, 0)
		r.name:SetWordWrap(false)
		r.sub = W.Text(r, "GameFontHighlight", nil, "text")
		r.sub:SetPoint("RIGHT", r, "RIGHT", -6, 0)
		r.sub:SetJustifyH("RIGHT")
		r.sub:SetWordWrap(false)
		r.sub:SetAlpha(0.75)
		r.name:SetPoint("RIGHT", r.sub, "LEFT", -8, 0)
		r:RegisterForClicks("LeftButtonUp")
		Perf.SetScript(r, "OnClick", RowClick)
		Perf.SetScript(r, "OnEnter", RowEnter)
		r:Hide()
		S.rows[i] = r
	end
	return box
end

-- the map closed: the list and the mark gone, the index made again next time (the log, the layers may change)
function Search.Hidden()
	if not S.win then
		return
	end
	Close()
	if S.box then
		S.box:ClearFocus()
	end
	if S.win.pins and S.win.pins.layers.search then
		S.win.pins:Clear("search")
	end
	S.index = nil
end

Search.S, Search.T = S, T
