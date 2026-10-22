--------------------------------------------------------------------------------
-- MelloUI Map - the quest log (docs/plans/seamless-map.md; the user, 2026-10-20:
-- "build the quest log into the map's side panel (the quests in your log, their
-- details, track, abandon, share), then point L at it", and of the sketch's
-- pick, BuildData/output/map_questlog_sketch A: "A, but make sure that when
-- somebody clicks on it, it has a smooth animation like the rest of the UI")
--
-- A column on the map's right, over the canvas's edge: the quests in your log
-- under their zones, a quest's page in the same column. It comes out of the
-- map's right edge as a drawer (Anim:Drawer, the whisper window's) and goes
-- back in; the list and a quest's page are two pages of one W.Pager (the
-- configurator's pages: the new one fades and slides in, a quest's from the
-- right, the list back from the left); the list and the page scroll with the
-- one smooth scroll. Reduce Motion lands each at once.
--
-- The quests' actions are the Quest Tracker's own (MelloUI.QuestActs: follow,
-- share, abandon with MelloUI's question, watch); the rows' gem, fonts and
-- marks the Quest List's and the tracker's. The game's quest log is only read
-- (and its selection set for the moment the game's own share and abandon need
-- it, as the tracker does): no Blizzard frame touched.
--
-- Built the first time the map opens; nothing runs while the map is closed
-- (the log's events are listened to only while it shows, a change laid once on
-- the next frame).
--
--   Log.Init(win)          the column on the map's window (Map.lua's Build)
--   Log.Shown() / Log.Hidden()   the window's show and hide
--   Log.Tick()             the window's beat: a change of the log laid once
--   Log.Size()             the canvas's size changed: the column's height
--   Log.SetOut(out, instant)     out of the edge (true) or folded back in
--   Log.IsOut()
--   Log.Select(questID)    a quest's page (from the list, the tracker, L)
--   Log.Back()             back to the list
--   Log.ShowQuest(questID) the map glides to where the quest is done (its
--                          open objectives, its turn-in once it is done), marks
--                          laid there
--   Log.Tab(key)           (M4) the column's tab: "quests" (the log) or "list" (the Quest
--                          List's own page, mounted here: QL.Panel:Mount; its Current
--                          zone the zone under the map's view, QL.ViewMap), slid in
--                          as the configurator's tabs (Anim:CrossFade)
--   Log.ViewChanged()      the map's view moved: the Quest List again when its zone did
--   Log.Unmount()          the map off: the Quest List's page back to the game's column
--   Log.Filter(click)      (after M4) the map's layers button beside the opener (beside the column while it
--                          is out): the set's gear; click(button) opens the layers' menu (Map.lua)
--   S.showID               the quest whose places Show laid (the objectives layer leaves it to them)
--   Log.State()            the tests' and the dump's look in
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_Map (QuestLog)")
local Safe = MelloUI.Safe
local Plain, Finite, Text, Secret = Safe.Value, Safe.Finite, Safe.Text, Safe.IsSecret
local W, Anim = MelloUI.Widgets, MelloUI.Anim
local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
local pcall, type, ipairs, wipe = pcall, type, ipairs, wipe

local Log = {}
ns.QuestLog = Log

local T = {
	W = 340,                    -- the column's width (the sketch's 330 and its edge)
	OPEN = 0.28, CLOSE = 0.18,  -- the drawer out and back in (the whisper window's)
	LAG = 0.35,                 -- the share of its width the column trails behind the edge
	HEAD = 36,                  -- the column's title row
	PAD = 10,                   -- room inside the column
	BAR = 3,                    -- the thin scroll bar, and its gap
	SLIDE = 12,                 -- the page switch's slide (the configurator's)
	FILTER_GAP = 6,             -- (after M4) the layers button's gap to the opener and to the column
	MARK = 18,                  -- a quest's mark (track_todo / track_handin)
	CHECK = 16,                 -- its tracked box
	TITLE_X = 35,               -- a quest's title and lines from the row's left (the mark, the gem, their gaps)
	ROW_TOP = 7, ROW_GAP = 3, ROW_BOTTOM = 8,
	ZONE = 28,                  -- a zone's heading
	FOLD = 22,                  -- the fold button, the back button
	OPENER = 30,                -- the map's button that brings the column out
	BUTTON = 34,                -- the page's round buttons
	BUTTON_ROW = 54,            -- with their labels
	REWARD = 28,                -- a reward's row (its icon 24)
	BAR_H = 3,                  -- an objective's progress bar
	LINE_ALPHA = 0.85,          -- a quest's objective line, a step under its title
	PLACES = 40,                -- Show: the marks laid at most
	MIN_BOX = 12,               -- Show: the least world units fitted (one spot: not the closest zoom)
	MARK_SIZE = 16,
	ORDER = 25,                 -- Show's marks: over the givers (20), under Route (30)
	KIND_ICON = { "kill", "pin_collect", "pin_collect", "obj_explore" },   -- QO's kinds: creature, object, item, area
	ICONS = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Icons\\",
}
Log.T = T

local TEXT = {
	title = "Quests",
	tabList = "Quest List",
	filter = "Map layers",
	filterTip = "Choose what the map shows.",
	empty = "Your quest log is empty.",
	back = "All quests",
	level = "Level %d",
	sep = "  \194\183  ",
	objectives = "Objectives",
	story = "The story",
	rewards = "Rewards",
	choose = "Choose one:",
	xp = "%d XP",
	handIn = "Ready to hand in",
	handInTo = "Ready to hand in: %s",
	show = "Show", route = "Route", routing = "Routing", share = "Share", tracked = "Tracked", track = "Track",
	abandon = "Abandon",
	read = "Read", stop = "Stop",
	readTip = "Read the quest aloud: its description in the quest giver's voice, then the recorded objectives when the voice pack has them (Voice Over). Again: stop.",
	showTip = "The map goes to where this quest is done (its turn-in once it is ready).",
	routeTip = "Follow this quest: Route shows the way to it. Click again to let it go.",
	shareTip = "Share this quest with your group.",
	shareOff = "Only a quest that can be shared, while you are in a group.",
	trackTip = "Show this quest in the Quest Tracker, or take it off.",
	abandonTip = "Abandon this quest (you are asked first).",
	fold = "Hide the quest log",
	opener = "Quest log",
	openerTip = "Your quests beside the map (L).",
	rowTip = "Click: its page   Shift-click: link it in the chat",
	trackBox = "Tracked in the Quest Tracker: click to take it off, or to show it there",
	collapse = "Click: fold or unfold this zone",
}

-- the state: one table (the file's locals stay few)
local S = {
	built = false, out = false, shown = false, dirty = false,
	entries = {}, n = 0, quests = 0,
	heads = {}, rows = {}, objs = {}, rewards = {},
	collapsed = {},   -- [zone name] = true while folded (this session)
	selected = nil,   -- the quest whose page shows (or showed last: its row marked)
	listOffset = 0,   -- the list's scroll while a page shows (back to it)
	places = {}, moneyParts = {},
}

local function Acts()
	local A = rawget(MelloUI, "QuestActs")
	return type(A) == "table" and A or nil
end

-- fn(...) guarded: its first result, or nil when fn is missing, raised or answered a secret
local function Ask(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, v = pcall(fn, ...)
	if ok and not Secret(v) then
		return v
	end
	return nil
end

-- (the user, 2026-10-20: "the VoiceOver Read Button is missing from the Quest Log") Voice Over's quest reading, when
-- it offers it (MelloUI_VoiceOver: ReadCan, Reading, ReadToggle -- its own button's on the game's quest log)
local function VoiceOver()
	local ok, vo = pcall(MelloUI.GetModule, MelloUI, "VoiceOver")
	return ok and type(vo) == "table" and type(vo.ReadToggle) == "function" and vo or nil
end

local function Watched(id)
	local A = Acts()
	return A and A.Watched and A.Watched(id) or false
end

-- the thin bar follows the pager's scroll, its range worked out from the page's height (the scroll frame's own range
-- follows the child's size a frame later); dragged, the scroll follows it
local function SyncBar()
	local bar, pager = S.bar, S.pager
	if not bar then
		return
	end
	local view = Finite(pager.scroll:GetHeight()) or 1
	local range = max(0, (Finite(pager.canvas:GetHeight()) or 0) - view)
	if range <= 0.5 then
		bar:Hide()
		return
	end
	bar.laying = true
	bar:SetMinMaxValues(0, range)
	bar:SetValue(min(range, Finite(pager.scroll:GetVerticalScroll()) or 0))
	bar.laying = false
	bar.thumb:SetHeight(max(16, (Finite(bar:GetHeight()) or view) * view / (view + range)))
	bar:Show()
end

-- a page's height: the pager's canvas follows it (the page on show), the bar too
local function PageHeight(page, h)
	S.pager:SetPageHeight(page, h)
	SyncBar()
end

--------------------------------------------------------------------------------
-- The log read: zone headings and their quests, in the game's order (a hidden
-- quest left out); the entries' tables reused
--------------------------------------------------------------------------------

local function Entry()
	S.n = S.n + 1
	local e = S.entries[S.n]
	if not e then
		e = {}
		S.entries[S.n] = e
	end
	return e
end

local function Read()
	S.n, S.quests = 0, 0
	local Q = C_QuestLog
	if not (Q and Q.GetNumQuestLogEntries and Q.GetInfo) then
		return
	end
	local count = Finite(Ask(Q.GetNumQuestLogEntries)) or 0
	local head
	for i = 1, count do
		local info = Ask(Q.GetInfo, i)
		if type(info) == "table" and not Plain(info.isHidden) then
			if Plain(info.isHeader) then
				head = Entry()
				head.header, head.title, head.count, head.id = true, Text(info.title) or "", 0, nil
			else
				local id = Finite(info.questID)
				if id and id > 0 then
					local e = Entry()
					e.header, e.id, e.index = false, id, i
					e.title, e.level = Text(info.title) or "", Finite(info.level)
					e.zone = head and head.title or ""
					e.complete = Ask(Q.IsComplete, id) == true
					S.quests = S.quests + 1
					if head then
						head.count = head.count + 1
					end
				end
			end
		end
	end
end

local function EntryOf(id)
	for i = 1, S.n do
		local e = S.entries[i]
		if not e.header and e.id == id then
			return e
		end
	end
	return nil
end

-- a quest's log text: its story and its objectives' summary (the game's own words)
local function LogText(index)
	local fn = rawget(_G, "GetQuestLogQuestText")
	if type(fn) ~= "function" or not index then
		return nil, nil
	end
	local ok, story, summary = pcall(fn, index)
	if not ok then
		return nil, nil
	end
	return Text(story), Text(summary)
end

-- who takes it back, and where (the Quest List's data, when it is loaded)
local function TurnIn(id)
	local fn = rawget(MelloUI, "QuestTurnIn")
	if type(fn) ~= "function" then
		return nil
	end
	local ok, name, _, cont, wx, wy, zone = pcall(fn, MelloUI, id)
	if not ok then
		return nil
	end
	return Text(name), Finite(cont), Finite(wx), Finite(wy), Text(zone)
end

-- a quest's line under its title: what is still to do, or where it goes back
local lineParts = {}
local function QuestLine(e)
	if e.complete then
		local name, _, _, _, zone = TurnIn(e.id)
		if name then
			return TEXT.handInTo:format(zone and (name .. ", " .. zone) or name)
		end
		return TEXT.handIn
	end
	wipe(lineParts)
	local lines = MelloUI.QuestObjectives.Lines(e.id)
	for _, o in ipairs(lines) do
		if not o[2] then
			lineParts[#lineParts + 1] = o[6]
		end
	end
	if #lineParts > 0 then
		return table.concat(lineParts, "\n")
	end
	local _, summary = LogText(e.index)
	return summary or ""
end

--------------------------------------------------------------------------------
-- The list: a zone's heading (its name, its count, fold) and the quests' rows
-- (the mark, the difficulty gem, "[level] title", the tracked box, the line)
--------------------------------------------------------------------------------

local HeadClick = Perf.Shared("OnClick on the map's quest log headings", function(self)
	local zone = self.zone
	if zone then
		S.collapsed[zone] = not S.collapsed[zone] or nil
		MelloUI:PlayUISound("click")
		Log.Lay()
	end
end, "script")

local HeadEnter = Perf.Shared("OnEnter on the map's quest log headings", function(self)
	W.ShowTooltip(self, self.zone or "", TEXT.collapse)
end, "script")

local function Head(i)
	local h = S.heads[i]
	if h then
		return h
	end
	h = CreateFrame("Button", nil, S.list)
	h:SetHeight(T.ZONE)
	h.label = W.Text(h, "GameFontNormal", nil, "selectedTrim")
	h.label:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 2, 7)
	h.label:SetWordWrap(false)
	h.count = W.Text(h, "GameFontNormal", nil, "text")
	h.count:SetPoint("LEFT", h.label, "RIGHT", 6, 0)
	h.toggle = h:CreateTexture(nil, "ARTWORK")
	h.toggle:SetSize(14, 14)
	h.toggle:SetPoint("RIGHT", h, "RIGHT", -4, 0)
	h.toggle:SetPoint("BOTTOM", h.label, "BOTTOM", 0, -1)
	h.line = W.Solid(h, "ARTWORK", "selectedTrim", 0.6)
	h.line:SetHeight(1)
	h.line:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 2)
	h.line:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 2)
	h:RegisterForClicks("LeftButtonUp")
	Perf.SetScript(h, "OnClick", HeadClick)
	Perf.SetScript(h, "OnEnter", HeadEnter)
	Perf.SetScript(h, "OnLeave", W.TipLeave)
	S.heads[i] = h
	return h
end

local RowClick = Perf.Shared("OnClick on the map's quest log rows", function(self, button)
	local id = self.id
	if not id then
		return
	end
	local A = Acts()
	if button == "LeftButton" and A and A.Link and A.Link(id) then
		return
	end
	if button == "LeftButton" then
		MelloUI:PlayUISound("click")
		Log.Select(id)
	end
end, "script")

local RowEnter = Perf.Shared("OnEnter on the map's quest log rows", function(self)
	if self.title:IsTruncated() then
		W.ShowTooltip(self, self.title:GetText(), TEXT.rowTip)
	end
end, "script")

local CheckClick = Perf.Shared("OnClick on the map's quest log tracked boxes", function(self)
	local row = self:GetParent()
	local A = Acts()
	if row.id and A and A.Watch then
		A.Watch(row.id, not Watched(row.id))
		MelloUI:PlayUISound("toggle")
		S.dirty = true
	end
end, "script")

local CheckEnter = Perf.Shared("OnEnter on the map's quest log tracked boxes", function(self)
	W.ShowTooltip(self, TEXT.tracked, TEXT.trackBox)
end, "script")

local function Row(i)
	local r = S.rows[i]
	if r then
		return r
	end
	r = CreateFrame("Button", nil, S.list)
	r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	-- the open quest's row: the selected tab's fill, a gold edge at its left (under the hover's wash)
	r.sel = W.Solid(r, "BACKGROUND", "selectedTab", 1)
	r.sel:SetAllPoints()
	r.selEdge = W.Solid(r, "BORDER", "selectedTrim", 1)
	r.selEdge:SetWidth(2)
	r.selEdge:SetPoint("TOPLEFT")
	r.selEdge:SetPoint("BOTTOMLEFT")
	r.mark = r:CreateTexture(nil, "ARTWORK")
	r.mark:SetSize(T.MARK, T.MARK)
	r.mark:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -(T.ROW_TOP - 2))
	r.title = W.Text(r, "GameFontHighlight", nil, "text")
	r.title:SetWordWrap(false)
	r.line = W.Text(r, "GameFontHighlight", nil, "text")
	r.line:SetWordWrap(true)
	local QI = MelloUI.QuestInk
	r.titleSize, r.lineSize = 12, 12
	if QI and QI.RowFonts then
		r.titleSize, r.lineSize = QI.RowFonts(r.title, r.line)
	end
	W.Paint(r.line, "text", "text", T.LINE_ALPHA)
	r.title:SetPoint("TOPLEFT", r, "TOPLEFT", T.TITLE_X, -T.ROW_TOP)
	r.check = CreateFrame("Button", nil, r)
	r.check:SetSize(T.CHECK, T.CHECK)
	r.check:SetPoint("TOPRIGHT", r, "TOPRIGHT", -4, -(T.ROW_TOP - 1))
	r.check.tex = r.check:CreateTexture(nil, "ARTWORK")
	r.check.tex:SetAllPoints()
	r.title:SetPoint("RIGHT", r.check, "LEFT", -6, 0)
	r.line:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -T.ROW_GAP)
	Perf.SetScript(r, "OnClick", RowClick)
	Perf.SetScript(r, "OnEnter", RowEnter)
	Perf.SetScript(r, "OnLeave", W.TipLeave)
	Perf.SetScript(r.check, "OnClick", CheckClick)
	Perf.SetScript(r.check, "OnEnter", CheckEnter)
	Perf.SetScript(r.check, "OnLeave", W.TipLeave)
	W.RowPlate(r)
	W.RowPlateChild(r, r.check)
	S.rows[i] = r
	return r
end

-- a quest's row filled; returns its height
local function FillRow(r, e, width)
	r.id = e.id
	W.Icon(r.mark, e.complete and "track_handin" or "track_todo")
	r.title:SetText(e.level and ("[" .. e.level .. "] " .. e.title) or e.title)
	local QI = MelloUI.QuestInk
	if QI and QI.RowGem and QI.TierForQuest then
		QI.RowGem(r, r.title, r.titleSize, QI.TierForQuest(e.id, e.level))
	end
	W.Icon(r.check.tex, Watched(e.id) and "ctl_check_on" or "ctl_check_off")
	r.line:SetWidth(max(1, width - T.TITLE_X - 4))
	r.line:SetText(QuestLine(e))
	local on = e.id == S.selected
	r.sel:SetShown(on)
	r.selEdge:SetShown(on)
	local th = Finite(r.title:GetStringHeight()) or r.titleSize
	local lh = Finite(r.line:GetStringHeight()) or r.lineSize
	return floor(T.ROW_TOP + th + T.ROW_GAP + lh + T.ROW_BOTTOM + 0.5)
end

function Log.Lay()
	if not S.built then
		return
	end
	local page, width = S.list, S.pageW
	local y, nh, nr = 0, 0, 0
	local hidden = false
	for i = 1, S.n do
		local e = S.entries[i]
		if e.header then
			nh = nh + 1
			local h = Head(nh)
			h.zone = e.title
			h.label:SetText(e.title:upper())
			h.count:SetText(e.count)
			hidden = S.collapsed[e.title] and true or false
			W.Icon(h.toggle, hidden and "btn_expand" or "btn_collapse")
			h:ClearAllPoints()
			h:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
			h:SetWidth(width)
			h:Show()
			y = y + T.ZONE
		elseif not hidden then
			nr = nr + 1
			local r = Row(nr)
			local height = FillRow(r, e, width)
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
			r:SetSize(width, height)
			r:Show()
			y = y + height
		end
	end
	for i = nh + 1, #S.heads do
		S.heads[i]:Hide()
	end
	for i = nr + 1, #S.rows do
		S.rows[i]:Hide()
		S.rows[i].id = nil
	end
	S.empty:SetShown(S.quests == 0)
	if S.quests == 0 then
		y = 40
	end
	local tab = S.tabs.quests
	tab:SetText(S.quests > 0 and (TEXT.title .. "  " .. S.quests) or TEXT.title)
	PanelTemplates_TabResize(tab, 8)
	PageHeight(page, max(y + T.PAD, 1))
end

--------------------------------------------------------------------------------
-- A quest's page: its title, level and zone; its objectives (a bar each that
-- counts); its story; its rewards; the five buttons (Show, Route, Share,
-- Tracked, Abandon)
--------------------------------------------------------------------------------

local function Obj(i)
	local o = S.objs[i]
	if o then
		return o
	end
	o = CreateFrame("Frame", nil, S.page)
	o.box = o:CreateTexture(nil, "ARTWORK")
	o.box:SetSize(14, 14)
	o.box:SetPoint("TOPLEFT", o, "TOPLEFT", 2, -1)
	o.text = W.Text(o, "GameFontHighlight", nil, "text")
	o.text:SetPoint("TOPLEFT", o, "TOPLEFT", 22, 0)
	o.track = W.Solid(o, "ARTWORK", "border", 1)
	o.track:SetHeight(T.BAR_H)
	o.track:SetPoint("TOPLEFT", o.text, "BOTTOMLEFT", 0, -4)
	o.track:SetPoint("RIGHT", o, "RIGHT", 0, 0)
	o.fill = W.Solid(o, "OVERLAY", "selectedTrim", 1)
	o.fill:SetHeight(T.BAR_H)
	o.fill:SetPoint("TOPLEFT", o.track, "TOPLEFT")
	S.objs[i] = o
	return o
end

local RewardEnter = Perf.Shared("OnEnter on the map's quest log rewards", function(self)
	if not (self.kind and self.index and S.selected) then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if not pcall(GameTooltip.SetQuestLogItem, GameTooltip, self.kind, self.index, S.selected) then
		GameTooltip:SetText(self.name:GetText() or "")
	end
	GameTooltip:Show()
end, "script")

local function Reward(i)
	local b = S.rewards[i]
	if b then
		return b
	end
	b = CreateFrame("Button", nil, S.page)
	b:SetHeight(T.REWARD)
	b.edge = W.Solid(b, "BACKGROUND", "border", 1)
	b.edge:SetSize(T.REWARD - 2, T.REWARD - 2)
	b.edge:SetPoint("LEFT", b, "LEFT", 0, 0)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", b.edge, "TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", b.edge, "BOTTOMRIGHT", -1, 1)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.count:SetPoint("BOTTOMRIGHT", b.edge, "BOTTOMRIGHT", -1, 1)
	b.name = W.Text(b, "GameFontHighlight", nil, "text")
	b.name:SetPoint("LEFT", b.edge, "RIGHT", 8, 0)
	b.name:SetPoint("RIGHT", b, "RIGHT", 0, 0)
	b.name:SetJustifyV("MIDDLE")
	b.name:SetWordWrap(false)
	Perf.SetScript(b, "OnEnter", RewardEnter)
	Perf.SetScript(b, "OnLeave", W.TipLeave)
	S.rewards[i] = b
	return b
end

-- the rewards of one kind ("reward": every one; "choice": one of them) from row `n` on, at `y`; returns n, y
local function Rewards(id, kind, n, y)
	local count = Finite(Ask(kind == "choice" and rawget(_G, "GetNumQuestLogChoices") or rawget(_G, "GetNumQuestLogRewards"), id)) or 0
	local info = kind == "choice" and rawget(_G, "GetQuestLogChoiceInfo") or rawget(_G, "GetQuestLogRewardInfo")
	if count <= 0 or type(info) ~= "function" then
		return n, y
	end
	if kind == "choice" and count > 1 then
		S.choose:ClearAllPoints()
		S.choose:SetPoint("TOPLEFT", S.page, "TOPLEFT", 0, -y)
		S.choose:Show()
		y = y + (Finite(S.choose:GetStringHeight()) or 12) + 6
	end
	for i = 1, count do
		local ok, name, texture, amount = pcall(info, i, id)
		name = ok and Text(name) or nil
		if name then
			n = n + 1
			local b = Reward(n)
			b.kind, b.index = kind, i
			b.icon:SetTexture(Plain(texture) or 134400)
			amount = Finite(amount)
			b.count:SetText(amount and amount > 1 and amount or "")
			b.name:SetText(name)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", S.page, "TOPLEFT", 0, -y)
			b:SetWidth(S.pageW)
			b:Show()
			y = y + T.REWARD + 4
		end
	end
	return n, y
end

-- a section's heading (the own windows' W.Header) at y; returns the y under it
local function Heading(h, y)
	h:ClearAllPoints()
	h:SetPoint("TOPLEFT", S.page, "TOPLEFT", -8, -y)
	h:SetPoint("RIGHT", S.page, "RIGHT", 8, 0)
	h:Show()
	return y + W.HEADER_HEIGHT + 2
end

local function Place(region, y, gap)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", S.page, "TOPLEFT", 0, -y)
	region:SetWidth(S.pageW)
	region:Show()
	return y + (Finite(region:GetStringHeight()) or 12) + (gap or 8)
end

-- the buttons as the quest is now: Route lit while followed, Share while it can be shared, the tracked box, Abandon
-- the page's buttons evenly across the page: the five, and Read while Voice Over offers it
local BUTTON_ORDER = { "show", "route", "share", "track", "abandon", "read" }
local function LayButtons()
	local B = S.buttons
	local n = 0
	for _, key in ipairs(BUTTON_ORDER) do
		if B[key]:IsShown() then
			n = n + 1
		end
	end
	local slot, i = S.pageW / max(n, 1), 0
	for _, key in ipairs(BUTTON_ORDER) do
		local b = B[key]
		if b:IsShown() then
			i = i + 1
			b:ClearAllPoints()
			b:SetPoint("TOP", B.row, "TOPLEFT", slot * (i - 0.5), 0)
		end
	end
end

-- Read's label as Voice Over reads (Stop while it reads)
local function ReadLabel()
	local VO, b = VoiceOver(), S.buttons.read
	local reading = VO and VO.Reading() and true or false
	if reading ~= b.reading then
		b.reading = reading
		b.label:SetText(reading and TEXT.stop or TEXT.read)
	end
end

local function Buttons(id)
	local A, B = Acts(), S.buttons
	local VO = VoiceOver()
	local canRead = VO and VO.ReadCan() and true or false
	if B.read:IsShown() ~= canRead then
		B.read:SetShown(canRead)
		LayButtons()
	end
	if canRead then
		ReadLabel()
	end
	local followed = A and A.Followed and A.Followed() == id
	B.route.label:SetText(followed and TEXT.routing or TEXT.route)
	B.route:SetOn(A ~= nil)
	B.route.lit:SetShown(followed and true or false)
	B.share:SetOn(A and A.Shareable and A.Shareable(id) or false)
	local watched = Watched(id)
	B.track:SetIcon(T.ICONS .. (watched and "ctl_check_on" or "ctl_check_off"))
	B.track.label:SetText(watched and TEXT.tracked or TEXT.track)
	B.abandon:SetOn(A and A.CanAbandon and A.CanAbandon(id) or false)
end

local function FillPage(id)
	local e = EntryOf(id)
	if not e then
		return false
	end
	local P = S.pageParts
	local y = P.top
	P.title:SetText(e.title)
	y = Place(P.title, y, 4)
	local QI = MelloUI.QuestInk
	local info = e.level and TEXT.level:format(e.level) or ""
	if e.zone ~= "" then
		info = info ~= "" and (info .. TEXT.sep .. e.zone) or e.zone
	end
	local who = TurnIn(id)
	if who then
		info = info .. TEXT.sep .. who
	end
	local tier = QI and QI.TierForQuest and QI.TierForQuest(id, e.level)
	local c = tier and QI.TIER_COLOUR and QI.TIER_COLOUR[tier]
	local gem = c and QI.GemCode and QI.GemCode(c[1], c[2], c[3], 12)
	P.info:SetText((gem or "") .. info)
	y = Place(P.info, y, 12)
	-- the objectives: the game's lines (a box ticked when done, a bar while it counts), else its summary
	y = Heading(P.objHead, y)
	local lines = MelloUI.QuestObjectives.Lines(id)
	local n = 0
	for _, line in ipairs(lines) do
		n = n + 1
		local o = Obj(n)
		W.Icon(o.box, line[2] and "ctl_check_on" or "ctl_check_off")
		o.text:SetWidth(S.pageW - 22)
		o.text:SetText(line[6])
		local have, need = line[7], line[8]
		local counts = need and need > 1 and have
		o.track:SetShown(counts and true or false)
		o.fill:SetShown(counts and true or false)
		local th = Finite(o.text:GetStringHeight()) or 12
		local h = th + 4
		if counts then
			o.fill:SetWidth(max(1, (S.pageW - 22) * min(1, max(0, have / need))))
			h = h + T.BAR_H + 6
		end
		o:ClearAllPoints()
		o:SetPoint("TOPLEFT", S.page, "TOPLEFT", 0, -y)
		o:SetSize(S.pageW, h)
		o:Show()
		y = y + h + 4
	end
	for i = n + 1, #S.objs do
		S.objs[i]:Hide()
	end
	local story, summary = LogText(e.index)
	if n == 0 and summary then
		P.summary:SetText(summary)
		y = Place(P.summary, y, 8)
	else
		P.summary:Hide()
	end
	y = y + 6
	-- the story
	if story and story ~= "" then
		y = Heading(P.storyHead, y)
		P.story:SetText(story)
		y = Place(P.story, y, 14)
	else
		P.storyHead:Hide()
		P.story:Hide()
	end
	-- the rewards: every one, then the ones to choose from; the money and the experience
	S.choose:Hide()
	local top = y
	y = Heading(P.rewardHead, y)
	local r = 0
	r, y = Rewards(id, "reward", r, y)
	r, y = Rewards(id, "choice", r, y)
	for i = r + 1, #S.rewards do
		S.rewards[i]:Hide()
	end
	local money = Finite(Ask(rawget(_G, "GetQuestLogRewardMoney"), id)) or 0
	local xp = Finite(Ask(rawget(_G, "GetQuestLogRewardXP"), id)) or 0
	local parts = wipe(S.moneyParts)
	-- (the coins as the client writes them: C_CurrencyInfo's, else the old global)
	local coins = money > 0 and Text(Ask(C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString
		or rawget(_G, "GetCoinTextureString"), money))
	if coins then
		parts[#parts + 1] = coins
	end
	if xp > 0 then
		parts[#parts + 1] = TEXT.xp:format(xp)
	end
	if #parts > 0 then
		P.money:SetText(table.concat(parts, TEXT.sep))
		y = Place(P.money, y, 10)
	else
		P.money:Hide()
	end
	if r == 0 and #parts == 0 then
		P.rewardHead:Hide()
		y = top
	end
	-- the buttons
	y = y + 6
	local B = S.buttons
	B.row:ClearAllPoints()
	B.row:SetPoint("TOPLEFT", S.page, "TOPLEFT", 0, -y)
	B.row:SetWidth(S.pageW)
	Buttons(id)
	y = y + T.BUTTON_ROW + T.PAD
	PageHeight(S.page, y)
	return true
end

--------------------------------------------------------------------------------
-- Show: the map goes to where the quest is done, marks laid there
--------------------------------------------------------------------------------

local function ShowTip(pin)
	return pin.spec.title, pin.data
end

local function ShowMark(icon, title)
	local spec = S.markSpecs[icon]
	if not spec then
		-- (the objectives' marks wear the set's glow or shade; the turn-in's mark has none baked)
		spec = { icon = T.ICONS .. icon, size = T.MARK_SIZE, tip = ShowTip, sub = 1,
			lift = icon ~= "track_handin" and icon or nil }
		S.markSpecs[icon] = spec
	end
	spec.title = title
	return spec
end

-- the quest's places in world units (flat x, y pairs in S.places) and the marks laid there; how many
-- (the objectives layer leaves the quest shown here to these marks; laid again when that changes)
local function Showing(id)
	if S.showID ~= id then
		S.showID = id
		local O = ns.Objectives
		if O then
			O.Soon()
		end
	end
end

local function Places(id, title)
	local out, n = S.places, 0
	wipe(out)
	local pins, Layers = S.pins, ns.Layers
	pins:Clear("questlog")
	Showing(nil)
	local point = Layers and Layers.WorldPoint
	if not point then
		return 0
	end
	local e = EntryOf(id)
	if e and e.complete then
		local who, cont, wx, wy = TurnIn(id)
		local x, y
		if cont and wx and wy then
			x, y = point(cont, wx, wy)
		end
		if x and y then
			out[1], out[2], n = x, y, 1
			local pin = pins:Set("questlog", "turnin", x, y, ShowMark("track_handin", title))
			if pin then
				pin.data = who
			end
		end
		return n
	end
	local QO = MelloUI.QuestObjectives
	local O = ns.Objectives
	if O then
		O.Data()   -- (the Companion's data, asked for once: Show worked only after Route or the Quest List asked)
	end
	local data = QO.Of(id)
	if type(data) ~= "table" then
		return 0
	end
	Showing(id)
	local lines = QO.Lines(id)
	local itemLine = QO.ItemLine and QO.ItemLine(data, lines)
	-- the open objectives' places: every one, or every n-th past T.PLACES
	local total = 0
	for _, entry in ipairs(data) do
		local line = QO.Match(entry, lines, itemLine)
		if not (line and line[2]) then
			total = total + floor((#entry - 4) / 2)
		end
	end
	local step = max(1, ceil(total / T.PLACES))
	local k = 0
	for i, entry in ipairs(data) do
		local line = QO.Match(entry, lines, itemLine)
		if not (line and line[2]) then
			local icon = T.KIND_ICON[entry[1]] or "obj_explore"
			for j = 5, #entry - 1, 2 do
				k = k + 1
				if k % step == 0 or step == 1 then
					local x, y = point(entry[4], entry[j], entry[j + 1])
					if x and y then
						out[2 * n + 1], out[2 * n + 2] = x, y
						n = n + 1
						local pin = pins:Set("questlog", i * 10000 + j, x, y, ShowMark(icon, title))
						if pin then
							pin.data = line and line[6] or entry[2]
						end
					end
				end
			end
		end
	end
	return n
end

function Log.ShowQuest(id)
	local c = S.canvas
	local e = EntryOf(id)
	if not (c and c.places and e) then
		return false
	end
	local n = Places(id, e.title)
	if n > 0 then
		local p = S.places
		local x0, y0, x1, y1 = p[1], p[2], p[1], p[2]
		for i = 2, n do
			local x, y = p[2 * i - 1], p[2 * i]
			x0, x1 = min(x0, x), max(x1, x)
			y0, y1 = min(y0, y), max(y1, y)
		end
		local mx, my = max(0, (T.MIN_BOX - (x1 - x0)) / 2), max(0, (T.MIN_BOX - (y1 - y0)) / 2)
		S.pins:Lay()
		c:Glide(c:FitBox(x0 - mx, y0 - my, x1 + mx, y1 + my))
		return true
	end
	-- no place known: its zone (the log's heading over it)
	local found
	c:EachPlace(function(p)
		if not found and p.name == e.zone then
			found = p
		end
	end)
	if found then
		c:Glide(c:FitOf(found))
		return true
	end
	return false
end

--------------------------------------------------------------------------------
-- The page's buttons
--------------------------------------------------------------------------------

local ButtonEnter = Perf.Shared("OnEnter on the map's quest page buttons", function(self)
	local body = self.tip
	if self == S.buttons.share and self.icon:IsDesaturated() then
		body = TEXT.shareOff
	end
	W.ShowTooltip(self, self.label:GetText(), body)
end, "script")

local ButtonClick = Perf.Shared("OnClick on the map's quest page buttons", function(self)
	local id, A = S.selected, Acts()
	if not id then
		return
	end
	local B = S.buttons
	if self == B.show then
		Log.ShowQuest(id)
	elseif self == B.read then
		local VO = VoiceOver()
		if VO then
			VO.ReadToggle(id)   -- (its own sound and line)
			ReadLabel()
		end
		return
	elseif not A then
		return
	elseif self == B.route then
		A.Follow(id)
	elseif self == B.share then
		if A.Shareable(id) then
			A.Share(id)
		end
	elseif self == B.track then
		A.Watch(id, not Watched(id))
	elseif self == B.abandon then
		A.Abandon(id)
		return
	end
	MelloUI:PlayUISound("click")
	S.dirty = true
end, "script")

local function PageButton(row, icon, label, tip)
	local b = W.RoundIcon(row, T.BUTTON, T.ICONS .. icon)   -- (laid by LayButtons)
	b.label = W.Text(row, "GameFontHighlight", label, "text")
	b.label:SetPoint("TOP", b, "BOTTOM", 0, -4)
	b.label:SetJustifyH("CENTER")
	b.tip = tip
	Perf.SetScript(b, "OnClick", ButtonClick)
	Perf.SetScript(b, "OnEnter", ButtonEnter)
	Perf.SetScript(b, "OnLeave", W.TipLeave)
	return b
end

--------------------------------------------------------------------------------
-- The column: the drawer, its title row, the pager with the list and the page
--------------------------------------------------------------------------------

local function Swallow() end

local Tabs   -- (M4, below: the tabs shown as the Quest List is there)
local FilterPlace   -- (after M4, below: the layers button's place)

local TabClick = Perf.Shared("OnClick on the map's quest log tabs", function(self)
	if self.key ~= S.tab then
		MelloUI:PlayUISound("tab")
		Log.Tab(self.key)
	end
end, "script")

local FoldClick = Perf.Shared("OnClick on the map's quest log fold", function()
	MelloUI:PlayUISound("click")
	Log.SetOut(false)
end, "script")

local OpenerClick = Perf.Shared("OnClick on the map's quest log opener", function()
	MelloUI:PlayUISound("click")
	Log.SetOut(true)
end, "script")

local BackClick = Perf.Shared("OnClick on the map's quest page back", function()
	MelloUI:PlayUISound("click")
	Log.Back()
end, "script")

local TipEnter = Perf.Shared("OnEnter on the map's quest log buttons", function(self)
	W.ShowTooltip(self, self.tipTitle, self.tipBody)
end, "script")

local function BarChanged(self, value)
	if not self.laying then
		S.pager:ScrollTo(Finite(value) or 0, true)
	end
end

local function Events(f, on)
	local fn = on and f.RegisterEvent or f.UnregisterEvent
	fn(f, "QUEST_LOG_UPDATE")
	fn(f, "QUEST_WATCH_LIST_CHANGED")
	fn(f, "SUPER_TRACKING_CHANGED")
	fn(f, "GROUP_ROSTER_UPDATE")
end

local function Column_OnEvent()
	S.dirty = true
end

function Log.Init(win)
	local canvas, frame = win.canvas, win.frame
	S.canvas, S.pins, S.module = canvas, win.pins, win.module
	S.markSpecs = {}
	win.pins:Layer("questlog", T.ORDER)
	local cf = canvas.frame
	-- the drawer: the holder clips the column while it moves (Anim:Drawer); over the canvas and its pins
	local holder = CreateFrame("Frame", nil, frame)
	holder:SetFrameLevel(canvas.root:GetFrameLevel() + 500)
	holder:EnableMouse(false)
	local col = CreateFrame("Frame", nil, holder)
	W.Panel(col, { on = true })
	col:SetSize(T.W, 1)
	col:EnableMouse(true)
	col:EnableMouseWheel(true)
	Perf.SetScript(col, "OnMouseWheel", Swallow)
	col:Hide()
	S.holder, S.col = holder, col
	S.job = { holder = holder, content = col, p = "RIGHT", rel = cf, rp = "RIGHT", x = 0, y = 0, w = T.W, h = 1,
		lag = T.LAG, pad = 0 }
	Anim:DrawerRest(S.job)
	-- the title row: Quests and the count; the fold button
	-- (M4) the tabs: Quests (the log's count on it), the Quest List while it is there (the UI's own tabs, W.FlatTab)
	local function Tab(text, key)
		local tab = CreateFrame("Button", nil, col, "PanelTopTabButtonTemplate")
		tab:SetText(text)
		PanelTemplates_TabResize(tab, 8)
		tab.key = key
		W.FlatTab(tab, (win.shell and win.shell.kit) and win.shell or nil)   -- (as the configurator's: the ring with the kit)
		Perf.SetScript(tab, "OnClick", TabClick)
		return tab
	end
	S.tabs = { quests = Tab(TEXT.title, "quests"), list = Tab(TEXT.tabList, "list") }
	S.tabs.quests:SetPoint("TOPLEFT", col, "TOPLEFT", T.PAD - 4, -7)
	S.tabs.list:SetPoint("LEFT", S.tabs.quests, "RIGHT", 2, 0)
	-- the two panes under the title row: the log's pages, the Quest List's page
	S.paneQ = CreateFrame("Frame", nil, col)
	S.paneL = CreateFrame("Frame", nil, col)
	for _, pane in ipairs({ S.paneQ, S.paneL }) do
		pane:SetPoint("TOPLEFT", col, "TOPLEFT", T.PAD, -(T.HEAD + 6))
		pane:SetSize(T.W - 2 * T.PAD, 1)
	end
	S.paneL:Hide()
	local fold = W.RoundIcon(col, T.FOLD, T.ICONS .. "btn_arrow")
	fold.icon:SetRotation(-math.pi / 2)
	fold:SetPoint("TOPRIGHT", col, "TOPRIGHT", -T.PAD, -8)
	fold.tipTitle = TEXT.fold
	Perf.SetScript(fold, "OnClick", FoldClick)
	Perf.SetScript(fold, "OnEnter", TipEnter)
	Perf.SetScript(fold, "OnLeave", W.TipLeave)
	local rule = W.Solid(col, "ARTWORK", W.HAIR_KEY, W.HAIR_ALPHA)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", col, "TOPLEFT", T.PAD, -T.HEAD)
	rule:SetPoint("TOPRIGHT", col, "TOPRIGHT", -T.PAD, -T.HEAD)
	-- the pages: the list and a quest's, in one pager (the configurator's switch)
	local pager = W.Pager(S.paneQ, { step = 80, slide = T.SLIDE, outInstant = true })
	S.pager = pager
	local scroll = pager.scroll
	scroll:SetPoint("TOPLEFT", S.paneQ, "TOPLEFT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", S.paneQ, "BOTTOMRIGHT", -2 * T.BAR, 0)
	S.pageW = T.W - 2 * T.PAD - 2 * T.BAR
	S.list = pager:NewPage()
	S.list:SetWidth(S.pageW)
	S.page = pager:NewPage()
	S.page:SetWidth(S.pageW)
	S.empty = W.Text(S.list, "GameFontHighlight", TEXT.empty, "text")
	S.empty:SetPoint("TOPLEFT", S.list, "TOPLEFT", 2, -12)
	local bar = W.ThinScrollBar(S.paneQ, T.BAR)
	bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", T.BAR, 0)
	bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", T.BAR, 0)
	bar:Hide()
	Perf.SetScript(bar, "OnValueChanged", BarChanged)
	S.bar = bar
	Perf.hooksecurefunc(scroll, "SetVerticalScroll", SyncBar)
	Perf.SetScript(scroll, "OnSizeChanged", SyncBar)
	-- the page's parts (its rows pooled: Obj, Reward)
	local page = S.page
	local back = CreateFrame("Button", nil, page)
	back:SetSize(160, T.FOLD)
	back:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
	back.arrow = W.RoundIcon(back, T.FOLD, T.ICONS .. "btn_arrow")
	back.arrow.icon:SetRotation(math.pi / 2)
	back.arrow:SetPoint("LEFT", back, "LEFT", 0, 0)
	back.text = W.Text(back, "GameFontHighlight", TEXT.back, "text")
	back.text:SetPoint("LEFT", back.arrow, "RIGHT", 8, 0)
	Perf.SetScript(back, "OnClick", BackClick)
	Perf.SetScript(back.arrow, "OnClick", BackClick)
	local P = {}
	P.title = W.Text(page, "GameFontNormalLarge", nil, "selectedTrim")
	P.info = W.Text(page, "GameFontHighlight", nil, "text")
	P.objHead = W.Header(page, 0, TEXT.objectives)
	P.summary = W.Text(page, "GameFontHighlight", nil, "text")
	P.storyHead = W.Header(page, 0, TEXT.story)
	P.story = W.Text(page, "GameFontHighlight", nil, "text")
	P.story:SetSpacing(2)
	P.rewardHead = W.Header(page, 0, TEXT.rewards)
	P.money = W.Text(page, "GameFontHighlight", nil, "text")
	S.pageParts = P
	S.choose = W.Text(page, "GameFontHighlight", TEXT.choose, "text")
	S.choose:Hide()
	local row = CreateFrame("Frame", nil, page)
	row:SetHeight(T.BUTTON_ROW)
	local B = { row = row }
	B.show = PageButton(row, "goal_pin", TEXT.show, TEXT.showTip)
	B.route = PageButton(row, "btn_way", TEXT.route, TEXT.routeTip)
	B.share = PageButton(row, "btn_invite", TEXT.share, TEXT.shareTip)
	B.track = PageButton(row, "ctl_check_on", TEXT.tracked, TEXT.trackTip)
	B.abandon = PageButton(row, "btn_discard", TEXT.abandon, TEXT.abandonTip)
	-- (Voice Over's Read, while it offers it: Buttons)
	B.read = PageButton(row, "voice_page", TEXT.read, TEXT.readTip)
	B.read:Hide()
	-- (Route followed: the selected trim's ring round its button)
	B.route.lit = B.route:CreateTexture(nil, "OVERLAY", nil, 2)
	B.route.lit:SetTexture(T.ICONS .. "hover_glow")
	B.route.lit:SetPoint("CENTER")
	B.route.lit:SetSize(T.BUTTON + 10, T.BUTTON + 10)
	B.route.lit:SetBlendMode("ADD")
	B.route.lit:Hide()
	S.buttons = B
	LayButtons()
	-- the title and the parts under the back button
	S.backButton = back
	P.top = T.FOLD + 10
	-- the map's own button that brings the column out (shown while it is folded)
	local opener = W.RoundIcon(frame, T.OPENER, T.ICONS .. "btn_list")
	opener:SetFrameLevel(holder:GetFrameLevel() + 2)
	opener:SetPoint("TOPRIGHT", cf, "TOPRIGHT", -10, -10)
	opener.tipTitle, opener.tipBody = TEXT.opener, TEXT.openerTip
	Perf.SetScript(opener, "OnClick", OpenerClick)
	Perf.SetScript(opener, "OnEnter", TipEnter)
	Perf.SetScript(opener, "OnLeave", W.TipLeave)
	S.opener = opener
	Perf.SetScript(col, "OnEvent", Column_OnEvent)
	S.built = true
	Log.Size()
	pager:Show(S.list, 0, true)
	local db = S.module and S.module.db
	S.tab = "quests"
	S.tabs.quests:SetSelected(true)
	S.tabs.list:SetSelected(false)
	Tabs()
	Log.SetOut(db and db.log == true, true)
	if db and db.logTab == "list" then
		Log.Tab("list", true)
	end
end

function Log.Size()
	if not S.built then
		return
	end
	local h = Finite(S.canvas.frame:GetHeight())
	if h and h > 1 then
		S.job.h = h
		S.col:SetHeight(h)
		local ph = max(1, h - T.HEAD - 6 - T.PAD)
		S.paneQ:SetHeight(ph)
		S.paneL:SetHeight(ph)
	end
end

--------------------------------------------------------------------------------
-- (M4) The tabs: the log and the Quest List (the user, 2026-10-20: "Yes, as a
-- tab"), its page the Quest List's own (QuestListPanel.lua), laid here
--------------------------------------------------------------------------------

local TAB_FADE = { slide = 0, axis = "x", outTime = 0.10, inTime = 0.15, outInstant = true, instant = false }

-- the Quest List's page, when the Quest List is there and on
local function QuestListPanel()
	local QL = rawget(MelloUI, "QuestList")
	local P = type(QL) == "table" and QL.Panel
	return (P and P.Mount and QL.M and QL.M.isEnabled) and QL or nil
end

-- the map under the view (the Quest List's Current zone: Canvas:ViewMap, the zone in the middle, or the continent
-- zoomed out, where the Quest List then takes the player's zone as on the game's map); over the sea the player's
function Log.ViewMap()
	local id = S.canvas and S.canvas:ViewMap()
	if id then
		return id
	end
	local ok, pid = pcall(C_Map.GetBestMapForUnit, "player")
	return ok and Finite(pid) or nil
end

-- the Quest List's page shown here or not: with its tab, the column out and the map shown
local function ListShown()
	local QL = QuestListPanel()
	if QL and S.mounted then
		QL.Panel:HostShow(S.tab == "list" and S.out and S.shown)
	end
end

function Log.Tab(key, instant)
	if not S.built then
		return
	end
	local QL = QuestListPanel()
	if key == "list" and not QL then
		key = "quests"
	end
	local old = S.tab == "list" and S.paneL or S.paneQ
	local new = key == "list" and S.paneL or S.paneQ
	S.tab = key
	S.tabs.quests:SetSelected(key == "quests")
	S.tabs.list:SetSelected(key == "list")
	local db = S.module and S.module.db
	if db then
		db.logTab = key
	end
	if key == "list" and not S.mounted then
		S.mounted = QL.Panel:Mount(S.paneL)
		QL.ViewMap = Log.ViewMap
	end
	TAB_FADE.slide = key == "list" and T.SLIDE or -T.SLIDE
	TAB_FADE.instant = (instant or not S.col:IsVisible()) and true or false
	Anim:CrossFade(old ~= new and old or nil, new, TAB_FADE)
	ListShown()
end

-- the tabs shown as the Quest List is there (its tab only then)
function Tabs()
	local here = QuestListPanel() ~= nil
	S.tabs.list:SetShown(here)
	if not here and S.tab == "list" then
		Log.Tab("quests", true)
	end
end

function Log.ViewChanged()
	if S.tab ~= "list" or not (S.mounted and S.out and S.shown) then
		return
	end
	local id = Log.ViewMap()
	if id ~= S.viewID then
		S.viewID = id
		local QL = QuestListPanel()
		if QL then
			QL.Panel:Update(true)   -- (quiet: a zone with the same quests is not laid again)
		end
	end
end

local FilterEnter = Perf.Shared("OnEnter on the map's layers button", function(self)
	W.ShowTooltip(self, TEXT.filter, TEXT.filterTip)
end, "script")

function Log.Filter(click)
	if not S.built or S.filter then
		return S.filter
	end
	local b = W.RoundIcon(S.opener:GetParent(), T.OPENER, T.ICONS .. "chat_settings")
	b:SetFrameLevel(S.opener:GetFrameLevel())
	Perf.SetScript(b, "OnClick", click)
	Perf.SetScript(b, "OnEnter", FilterEnter)
	Perf.SetScript(b, "OnLeave", W.TipLeave)
	S.filter = b
	FilterPlace()
	return b
end

function Log.Unmount()
	local QL = rawget(MelloUI, "QuestList")
	if S.mounted and type(QL) == "table" and QL.Panel and QL.Panel.Unmount then
		QL.Panel:Unmount()
	end
	if type(QL) == "table" and QL.ViewMap == Log.ViewMap then
		QL.ViewMap = nil
	end
	S.mounted = false
end

function Log.IsOut()
	return S.out
end

-- the map's opener: gone while the column is out, back (faded in) once it has folded away
local function Opener(on, fade)
	local b = S.opener
	Anim:Stop(b, "alpha")
	if not on then
		b:Hide()
	elseif fade then
		Anim:FadeIn(b, 0.15)
	else
		b:SetAlpha(1)
		b:Show()
	end
end

-- (after M4) the layers button: beside the opener while the column is folded, beside the column while it is out
-- (anchored to the column: it moves with the drawer)
function FilterPlace()
	local b = S.filter
	if b then
		b:ClearAllPoints()
		if S.out then
			b:SetPoint("TOPRIGHT", S.col, "TOPLEFT", -T.FILTER_GAP, -10)
		else
			b:SetPoint("TOPRIGHT", S.opener, "TOPLEFT", -T.FILTER_GAP, 0)
		end
	end
end

local function FoldDone()
	S.col:Hide()
	Opener(true, true)
	FilterPlace()   -- (beside the opener now the column is gone)
end

function Log.SetOut(out, instant)
	if not S.built then
		return
	end
	out = out and true or false
	local db = S.module and S.module.db
	if db then
		db.log = out
	end
	S.canvas.cover = out and T.W or 0
	if out == S.out and not instant then
		return
	end
	S.out = out
	instant = instant or not S.col:GetParent():IsVisible()
	-- (out: beside the column, riding its slide in; folded at once: beside the opener; a fold under way rides the
	-- column out, then FoldDone puts it beside the opener)
	if out or instant then
		FilterPlace()
	end
	if out then
		Read()
		Log.Lay()
		Opener(false)
		S.col:Show()
		if instant then
			Anim:StopDrawer(S.job)
			Anim:DrawerRest(S.job)
		else
			Anim:Drawer(S.job, true, T.OPEN)
		end
		if S.shown then
			Events(S.col, true)
		end
		ListShown()
	else
		Events(S.col, false)
		ListShown()
		if instant then
			Anim:StopDrawer(S.job)
			Anim:DrawerRest(S.job)
			S.col:Hide()
			Opener(true)
		else
			Anim:Drawer(S.job, false, T.CLOSE, FoldDone)
		end
	end
end

local function MarkSelected()
	for _, r in ipairs(S.rows) do
		local on = r.id ~= nil and r.id == S.selected
		r.sel:SetShown(on)
		r.selEdge:SetShown(on)
	end
end

function Log.Select(id)
	if not S.built then
		return false
	end
	if not S.out then
		Log.SetOut(true)
	end
	if not EntryOf(id) then
		Read()
		Log.Lay()
	end
	local pager = S.pager
	if pager:Current() == S.list then
		S.listOffset = pager:Offset()
	end
	S.selected = id
	if not FillPage(id) then
		S.selected = nil
		return false
	end
	MarkSelected()
	pager:Show(S.page, 1)
	SyncBar()
	return true
end

function Log.Back()
	if not S.built then
		return
	end
	local pager = S.pager
	if pager:Current() ~= S.list then
		Log.Lay()
		pager:Show(S.list, -1)
		pager:ScrollTo(S.listOffset or 0, true)
		SyncBar()
	end
end

-- a change of the log laid once (the window's beat): the list again, the page again (back to the list when its
-- quest has left the log)
local function Refresh()
	S.dirty = false
	Read()
	Log.Lay()
	if S.pager:Current() == S.page and S.selected then
		if EntryOf(S.selected) then
			FillPage(S.selected)
		else
			S.selected = nil
			Log.Back()
		end
	end
end

function Log.Tick()
	if S.dirty and S.out then
		Refresh()
	end
	local read = S.buttons and S.buttons.read
	if read and read:IsVisible() then
		ReadLabel()   -- (Read again once the reading ends by itself)
	end
end

function Log.Shown()
	S.shown = true
	if not S.built then
		return
	end
	Log.Size()
	Tabs()
	if S.out then
		Events(S.col, true)
		Refresh()
	end
	ListShown()
end

function Log.Hidden()
	S.shown = false
	if not S.built then
		return
	end
	Events(S.col, false)
	S.pins:Clear("questlog")
	Showing(nil)
	ListShown()
	Anim:StopDrawer(S.job)
	if not S.out then
		S.col:Hide()
		Opener(true)
	end
end

function Log.State()
	local pager = S.pager
	return {
		built = S.built, out = S.out, quests = S.quests, entries = S.n, selected = S.selected,
		page = pager and (pager:Current() == S.page and "quest" or pager:Current() == S.list and "list") or nil,
		cover = S.canvas and S.canvas.cover or 0, moving = S.job and S.job.moving or false,
	}
end

Log.S = S
