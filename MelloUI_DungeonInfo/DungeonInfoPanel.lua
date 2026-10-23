--------------------------------------------------------------------------------
-- MelloUI - Dungeon Info: its pages in the map's column (the user's picks of 2026-10-22: the map's door button,
-- the column the quest log's -- BuildData/output/journal_sketch/journal_window.html, A "pages")
--
-- Mounted by the map (MelloUI_Map/MapQuestLog.lua, Log.Mode "dungeonInfo") into the column's own pane, as the Quest
-- List's page is: its tabs in the column's title row where the log's are (Dungeons, Raids, My Items), under them one
-- pager (the configurator's, the quest log's) with the pages -- the list (by level: for your level, later, earlier),
-- a dungeon's page (its picture and emblem; Show, Route, Pick Up Quests; its bosses in order with their best drops,
-- your starred ones marked; its quests), a boss's page (his drops, their kind and chance, a star each; the drops seen
-- in front of you the data does not list), My Items (your stars by dungeon) and the quest trip's (DungeonInfoTrip.lua).
-- A row of the list or a boss slides its page in from the right; Back slides back. The rows are pooled, made the
-- first time they are needed; nothing is laid while the page does not show.
--   P:Mount(pane, T) -> true   P:HostShow(on)   P:Unmount()   P:Show([inst[, encounterID]])   P:Lay()
--   P.S   the tests' look in
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_DungeonInfo (Panel)")
local Safe = MelloUI.Safe
local Finite = Safe.Finite
local CreateFrame = MelloUI.Safe.CreateFrame   -- (a frame inside an open window: the gamepad navigation left out)
local W = MelloUI.Widgets
local J = ns.DungeonInfo
local floor, max, min = math.floor, math.max, math.min

local P = {}
J.Panel = P

local STAR = "Interface\\AddOns\\MelloUI\\Media\\Textures\\DungeonInfoStar"
local EMBLEM = "Interface\\LFGFrame\\LFGIcon-"
local PLAIN_HEAD = 64   -- (1.2.2) a head with no picture: room for the emblem and the name
-- (1.2.2) the kinds of picture (DungeonInfoData.lua's 12th field): the painted area's rows (of the file's height)
-- and the file's shape as the game shows it, width / height. 1: a Forever loading screen (2992 x 1684, the painting
-- between its clear bands); 2: a classic loading screen (shown 4:3, the painting under its logo, above its frame);
-- 3: an LFG background (256 x 128, painted whole)
local PICTURE_KINDS = {
	[1] = { 0.158, 0.842, 2992 / 1684 },
	[2] = { 0.22, 0.78, 4 / 3 },
	[3] = { 0, 1, 2 },
}
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
-- (1.2.2) the heads' and the rows' fades: the soft shade's file (MelloUI.Shade.FILE), tinted innerPanel (W.Paint,
-- painted again with the palette), cut to its soft rising part across its flat middle: its top rows (full at
-- FADE_V, Core/Shade.lua VCAP) for a head, its left end's columns (full at FADE_CAP, Shade.lua CAP) for a row
local FADE_V, FADE_CAP, FADE_MID = 0.3125, 0.25, 0.4

-- (1.2.2) an instance's picture on `tex` at w x h: the box's shape cut from the middle of its kind's painted area,
-- never stretched; false (the texture left as it was) for one with none
local function CutPicture(tex, inst, w, h)
	local kind = PICTURE_KINDS[inst.picKind or 0]
	if not ((inst.pic or 0) > 0 and kind and w > 0 and h > 0) then
		return false
	end
	tex:SetTexture(inst.pic)
	local v0, v1, aspect = kind[1], kind[2], kind[3]
	local band, box = aspect / (v1 - v0), w / h
	if box < band then
		local u0 = (1 - box / band) / 2
		tex:SetTexCoord(u0, 1 - u0, v0, v1)
	else
		local mid, half = (v0 + v1) / 2, (v1 - v0) * band / box / 2
		tex:SetTexCoord(0, 1, mid - half, mid + half)
	end
	return true
end

-- a picture's fade, made on `parent` over its picture (the column's colour; its points and size set by the caller)
local function Fade(parent, sublevel, across)
	local fade = parent:CreateTexture(nil, "BACKGROUND", nil, sublevel)
	fade:SetTexture(MelloUI.Shade.FILE)
	if across then
		fade:SetTexCoord(FADE_CAP, 0, FADE_MID, 1 - FADE_MID)   -- full at the left, clear to the right
	else
		fade:SetTexCoord(FADE_MID, 1 - FADE_MID, FADE_V, 0)     -- full at the top, clear below
	end
	W.Paint(fade, "innerPanel", "vertex")
	fade:Hide()
	return fade
end

local TEXT = {
	dungeons = "Dungeons", raids = "Raids", mine = "My Items",
	forLevel = "For your level", later = "Later", earlier = "Earlier", other = "Others",
	allDungeons = "All dungeons", allRaids = "All raids",
	levels = "levels %d-%d", level = "level %d", dungeon = "Dungeon", raid = "Raid", raidOf = "Raid, %d players",
	bosses = "Bosses", quests = "Quests", loot = "Loot", seen = "Seen drop",
	bossOf = "Boss %d of %d", lastBoss = "Boss %d of %d, the last",
	show = "Show", showTip = "The map goes to its door.",
	route = "Route", routeTip = "Route shows the way to its door.",
	pickUp = "Pick Up Quests", pickUpN = "Pick Up Quests (%d)",
	pickUpTip = "Route takes you to every quest of it you can take now, in the fastest order from where you stand.",
	pickUpNone = "No quest of it to take now.",
	noDoor = "Its door is not known yet: it is learned the first time you walk in.",
	noLoot = "No drops known for this boss yet: what he drops is kept the first time he falls in front of you.",
	noBosses = "No bosses known for this one.",
	noQuests = "No quests for your side and class here.",
	mineEmpty = "Star an item on a boss's page to keep it here. A loot roll then marks it when it drops.",
	elsewhere = "Elsewhere",
	chance = "%d%%", chanceTenth = "%.1f%%", chanceSmall = "<0.1%",
	trash = "Trash", trashDrops = "Trash drops", trashSub = "The rare drops of the dungeon's other creatures",
	noTrash = "No rare drops known from its other creatures yet: they are counted as they fall in front of you.",
	droppedBy = "Dropped by %s", listed = "Listed by DungeonJournal", seenTip = "Seen fall in front of you or other players",
	everloot = "Players' data: Everloot (everloot.app), CC BY-SA 4.0",
	curated = "From DungeonMaster's lists (by MalkDev, GPL-3.0)",
	starOn = "On your list", starOff = "Put it on your list",
	starTip = "A loot roll marks the items on your list when one drops.",
	inLog = "In your log", done = "Done", fromLevel = "From level %d", after = "After an earlier quest",
	startsQuest = "Starts a quest",
	rowTip = "Click: its page",
	questTip = "Click: Route to its giver",
}
P.TEXT = TEXT

local S = {
	built = false, shown = false, tab = "dungeons", inst = nil, boss = nil, page = nil,
	heads = {}, drows = {}, brows = {}, irows = {}, qrows = {}, lists = {}, quests = {},
	pending = nil,
}
P.S = S
local T

--------------------------------------------------------------------------------
-- The pieces: a heading, the rows (pooled by page)
--------------------------------------------------------------------------------

local function Heading(page, i)
	local pool = S.heads[page]
	if not pool then
		pool = {}
		S.heads[page] = pool
	end
	local h = pool[i]
	if h then
		return h
	end
	h = CreateFrame("Button", nil, page)
	h:SetHeight(T.ZONE)
	h.label = W.Text(h, "GameFontNormal", nil, "selectedTrim")
	h.label:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 2, 7)
	h.label:SetWordWrap(false)
	h.count = W.Text(h, "GameFontNormal", nil, "text")
	h.count:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -2, 7)
	h.line = W.Solid(h, "ARTWORK", "selectedTrim", 0.6)
	h.line:SetHeight(1)
	h.line:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 2)
	h.line:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 2)
	h:EnableMouse(false)
	pool[i] = h
	return h
end

local function PutHeading(page, i, y, width, label, count)
	local h = Heading(page, i)
	h.label:SetText(label:upper())
	h.count:SetText(count and tostring(count) or "")
	h:ClearAllPoints()
	h:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
	h:SetWidth(width)
	h:Show()
	return y + T.ZONE
end

local function HideFrom(list, n)
	for i = n + 1, #list do
		list[i]:Hide()
	end
end

-- a star's picture: the filled cell or the outline's, in the palette's gold
local function Star(tex, on)
	tex:SetTexture(STAR)
	if on then
		tex:SetTexCoord(0, 0.5, 0, 1)
	else
		tex:SetTexCoord(0.5, 1, 0, 1)
	end
end

-- an item's square picture in its quality's colour round it (the game's own item colours)
local function ItemPicture(parent, size)
	local frame = parent:CreateTexture(nil, "ARTWORK", nil, 1)
	frame:SetTexture("Interface\\Buttons\\WHITE8X8")
	frame:SetSize(size + 2, size + 2)
	local icon = parent:CreateTexture(nil, "ARTWORK", nil, 2)
	icon:SetSize(size, size)
	icon:SetPoint("CENTER", frame, "CENTER", 0, 0)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	return frame, icon
end

local function SetItemPicture(frame, icon, item, quality)
	icon:SetTexture(J.ItemIcon(item))
	frame:SetVertexColor(J.QualityColour(quality or 1))
end

local function PageHeight(page, h)
	S.pager:SetPageHeight(page, h)
	P.SyncBar()
end

--------------------------------------------------------------------------------
-- The list: the dungeons (or raids) by level, under For your level, Later, Earlier, Others
--------------------------------------------------------------------------------

local RowClick = Perf.Shared("OnClick on Dungeon Info's list rows", function(self)
	if self.inst then
		MelloUI:PlayUISound("click")
		P:Show(self.inst)
	end
end, "script")

local RowEnter = Perf.Shared("OnEnter on Dungeon Info's list rows", function(self)
	if self.inst then
		W.ShowTooltip(self, self.inst.name, TEXT.rowTip)
	end
end, "script")

-- (1.2.2, the user's pick A of BuildData/output/journal_sketch/journal_look2.html, "Pictures") a row is its dungeon's
-- picture: the picture on the row's right ROW_PIC, the column's colour fading out over its left ROW_FADE, the name and
-- its line on the column left of it; the rows for your level in the gold hairline, the others' pictures LATER_ALPHA
local ROW_H, ROW_STEP = 46, 50
local ROW_PIC, ROW_FADE, LATER_ALPHA = 0.55, 0.82, 0.55

local function DungeonRow(i)
	local r = S.drows[i]
	if r then
		return r
	end
	r = CreateFrame("Button", nil, S.list)
	r:RegisterForClicks("LeftButtonUp")
	r.picture = r:CreateTexture(nil, "BACKGROUND", nil, -2)
	r.picture:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
	r.picture:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
	r.fade = Fade(r, -1, true)
	r.fade:SetPoint("TOPLEFT", r.picture, "TOPLEFT", 0, 0)
	r.fade:SetPoint("BOTTOMLEFT", r.picture, "BOTTOMLEFT", 0, 0)
	r.edges = W.HairEdges(r, "BORDER", r)
	r.title = W.Text(r, "GameFontHighlight", nil, "text")
	r.title:SetWordWrap(false)
	r.title:SetPoint("TOPLEFT", r, "TOPLEFT", 10, -7)
	r.line = W.Text(r, "GameFontHighlight", nil, "text")
	W.Paint(r.line, "text", "text", T.LINE_ALPHA)
	r.line:SetWordWrap(false)
	r.line:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -3)
	r.qn = W.Text(r, "GameFontHighlight", nil, "text")
	r.qn:SetPoint("TOPRIGHT", r, "TOPRIGHT", -4, -7)
	r.qmark = r:CreateTexture(nil, "ARTWORK")
	r.qmark:SetSize(14, 14)
	r.qmark:SetPoint("RIGHT", r.qn, "LEFT", -3, 0)
	W.Icon(r.qmark, "track_todo")
	r.sn = W.Text(r, "GameFontHighlight", nil, "selectedTrim")
	r.sn:SetPoint("TOPRIGHT", r.qn, "BOTTOMRIGHT", 0, -4)
	r.star = r:CreateTexture(nil, "ARTWORK")
	r.star:SetSize(14, 14)
	r.star:SetPoint("RIGHT", r.sn, "LEFT", -3, 0)
	Star(r.star, true)
	W.Paint(r.star, "selectedTrim", "vertex")
	-- (the counts on a soft dark band, over the picture)
	r.band = MelloUI.Shade:Band(r, { alpha = 0.7, feather = 10, layer = "BORDER" })
	if r.band then
		r.band:Anchor(r.qmark, r.sn, 3, 2)
	end
	r.title:SetPoint("RIGHT", r, "RIGHT", -40, 0)
	r.line:SetPoint("RIGHT", r, "RIGHT", -40, 0)
	Perf.SetScript(r, "OnClick", RowClick)
	Perf.SetScript(r, "OnEnter", RowEnter)
	Perf.SetScript(r, "OnLeave", W.TipLeave)
	W.RowPlate(r)
	S.drows[i] = r
	return r
end

local function Where(inst)
	local zone = J.Zone(inst)
	local lv
	if inst.lo > 0 and inst.hi > inst.lo then
		lv = TEXT.levels:format(inst.lo, inst.hi)
	elseif inst.lo > 0 then
		lv = TEXT.level:format(inst.lo)
	end
	if zone and lv then
		return zone .. ", " .. lv
	end
	return zone or lv or (inst.kind == 2 and TEXT.raid or TEXT.dungeon)
end
P.Where = Where

local function Takeable(inst)
	local n = 0
	for _, q in ipairs(J.Quests(inst, S.quests)) do
		if q.state == "take" then
			n = n + 1
		end
	end
	return n
end
P.Takeable = Takeable

local function FillDungeonRow(r, inst, width, near)
	r.inst = inst
	local picW = floor(width * ROW_PIC)
	r.picture:SetWidth(picW)
	r.fade:SetWidth(floor(picW * ROW_FADE))
	local pic = CutPicture(r.picture, inst, picW, ROW_H)
	r.picture:SetShown(pic)
	r.picture:SetAlpha(near and 1 or LATER_ALPHA)
	r.fade:SetShown(pic)
	for _, e in ipairs(r.edges) do
		e:SetShown(near)
	end
	r.title:SetText(inst.name)
	r.line:SetText(Where(inst))
	local q, s = Takeable(inst), J.TrackedIn(inst)
	r.qn:SetText(q > 0 and q or "")
	r.qmark:SetShown(q > 0)
	r.sn:SetText(s > 0 and s or "")
	r.star:SetShown(s > 0)
	if r.band then
		r.band:SetShown(q > 0 or s > 0)
	end
end

-- the sections of the list: by your level
local function Section(inst, level)
	if inst.lo <= 0 then
		return 4
	end
	local hi = inst.hi > 0 and inst.hi or inst.lo
	if level + 2 < inst.lo then
		return 2
	elseif level - 2 > hi then
		return 3
	end
	return 1
end

local SECTIONS = { "forLevel", "later", "earlier", "other" }

function P.LayList()
	local page, width = S.list, S.pageW
	local kind = S.tab == "raids" and 2 or 1
	local all = J.List(kind, S.lists[kind])
	S.lists[kind] = all
	local level = Finite(UnitLevel("player")) or 1
	local y, nh, nr = 0, 0, 0
	for sec = 1, 4 do
		local count = 0
		for _, inst in ipairs(all) do
			if Section(inst, level) == sec then
				count = count + 1
			end
		end
		if count > 0 then
			nh = nh + 1
			y = PutHeading(page, nh, y, width, TEXT[SECTIONS[sec]], count)
			for _, inst in ipairs(all) do
				if Section(inst, level) == sec then
					nr = nr + 1
					local r = DungeonRow(nr)
					FillDungeonRow(r, inst, width, sec == 1)
					r:ClearAllPoints()
					r:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
					r:SetSize(width, ROW_H)
					r:Show()
					y = y + ROW_STEP
				end
			end
			y = y + 8
		end
	end
	HideFrom(S.heads[page] or {}, nh)
	HideFrom(S.drows, nr)
	S.mineEmpty:Hide()
	PageHeight(page, max(y + T.PAD, 1))
end

--------------------------------------------------------------------------------
-- The items: a row each (a boss's page, My Items) -- its picture, its name in its colour, its kind, its chance, the
-- star that puts it on your list
--------------------------------------------------------------------------------

local StarClick = Perf.Shared("OnClick on Dungeon Info's stars", function(self)
	local r = self:GetParent()
	if r.item then
		local on = not J.IsTracked(r.item)
		J.SetTracked(r.item, on)
		MelloUI:PlayUISound(on and "check_on" or "check_off")
		Star(self.tex, on)
		if GameTooltip:IsOwned(self) then
			W.ShowTooltip(self, on and TEXT.starOn or TEXT.starOff, TEXT.starTip)
		end
	end
end, "script")

local StarEnter = Perf.Shared("OnEnter on Dungeon Info's stars", function(self)
	local r = self:GetParent()
	W.ShowTooltip(self, J.IsTracked(r.item) and TEXT.starOn or TEXT.starOff, TEXT.starTip)
end, "script")

local ItemEnter = Perf.Shared("OnEnter on Dungeon Info's item rows", function(self)
	if self.item then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		pcall(GameTooltip.SetItemByID, GameTooltip, self.item)
		-- (1.2.2) who drops it (the trash's), and where it is known from when not the data
		local d, c = self.d, MelloUI.Look.Palette().text
		if d and d.mobs and d.mobs ~= "" then
			GameTooltip:AddLine(TEXT.droppedBy:format(d.mobs), c[1], c[2], c[3], true)
		end
		if d and d.src == "everloot" then
			GameTooltip:AddLine(TEXT.everloot, c[1], c[2], c[3], true)
		elseif d and d.src == "curated" then
			GameTooltip:AddLine(TEXT.curated, c[1], c[2], c[3], true)
		elseif d and d.src == "listed" then
			GameTooltip:AddLine(TEXT.listed, c[1], c[2], c[3], true)
		elseif d and d.src == "seen" then
			GameTooltip:AddLine(TEXT.seenTip, c[1], c[2], c[3], true)
		end
		GameTooltip:Show()
	end
end, "script")

local ItemClick = Perf.Shared("OnClick on Dungeon Info's item rows", function(self)
	-- (Shift-click: the item linked in the chat, as anywhere in the game)
	if self.item and IsModifiedClick and IsModifiedClick("CHATLINK") then
		local ok, _, link = pcall(GetItemInfo, self.item)
		if ok and link and ChatEdit_InsertLink then
			ChatEdit_InsertLink(link)
		end
	elseif self.inst and self.mine then
		MelloUI:PlayUISound("click")
		P:Show(self.inst, self.boss and self.boss.id or nil)
	end
end, "script")

local function ItemRow(page, i)
	local pool = S.irows[page]
	if not pool then
		pool = {}
		S.irows[page] = pool
	end
	local r = pool[i]
	if r then
		return r
	end
	r = CreateFrame("Button", nil, page)
	r:RegisterForClicks("LeftButtonUp")
	r.frame, r.icon = ItemPicture(r, 24)
	r.frame:SetPoint("LEFT", r, "LEFT", 4, 0)
	r.name = W.Text(r, "GameFontHighlight", nil, nil)
	r.name:SetWordWrap(false)
	r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 38, -5)
	r.kind = W.Text(r, "GameFontHighlight", nil, "text")
	W.Paint(r.kind, "text", "text", T.LINE_ALPHA)
	r.kind:SetWordWrap(false)
	r.kind:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
	r.starB = CreateFrame("Button", nil, r)
	r.starB:SetSize(20, 20)
	r.starB:SetPoint("RIGHT", r, "RIGHT", -4, 0)
	r.starB.tex = r.starB:CreateTexture(nil, "ARTWORK")
	r.starB.tex:SetAllPoints()
	W.Paint(r.starB.tex, "selectedTrim", "vertex")
	Perf.SetScript(r.starB, "OnClick", StarClick)
	Perf.SetScript(r.starB, "OnEnter", StarEnter)
	Perf.SetScript(r.starB, "OnLeave", W.TipLeave)
	r.chance = W.Text(r, "GameFontHighlight", nil, "text")
	r.chance:SetPoint("RIGHT", r.starB, "LEFT", -8, 0)
	r.name:SetPoint("RIGHT", r.chance, "LEFT", -6, 0)
	r.kind:SetPoint("RIGHT", r.chance, "LEFT", -6, 0)
	Perf.SetScript(r, "OnEnter", ItemEnter)
	Perf.SetScript(r, "OnLeave", W.TipLeave)
	Perf.SetScript(r, "OnClick", ItemClick)
	W.RowPlate(r)
	W.RowPlateChild(r, r.starB)
	pool[i] = r
	return r
end

-- an item's row filled: d a drop of the data's, or nil (seen in front of you: item only)
local function FillItemRow(r, item, d, line)
	r.item, r.d = item, d
	-- (a quality the data does not know, 0: the game's own, a Forever item's once the server has sent it)
	local quality = d and d.quality or 2
	if quality == 0 then
		quality = J.ItemQuality(item) or 2
	end
	SetItemPicture(r.frame, r.icon, item, quality)
	r.name:SetText(J.ItemName(item, d and d.name))
	r.name:SetTextColor(J.QualityColour(quality))
	local kind = line
	if not kind then
		kind = J.ItemKind(item)
		if d and d.starts and d.starts > 0 then
			kind = TEXT.startsQuest
		elseif d and d.req and d.req > 0 then
			kind = (kind ~= "" and (kind .. ", ") or "") .. TEXT.level:format(d.req)
		end
	end
	r.kind:SetText(kind)
	-- its chance: the data's, or the counts' (1.2.2); none known: "Seen drop" when only seen, nothing when listed
	local ch = d and d.chance
	if ch then
		r.chance:SetText(ch >= 1 and TEXT.chance:format(floor(ch + 0.5)) or ch >= 0.1 and TEXT.chanceTenth:format(ch)
			or TEXT.chanceSmall)
	else
		r.chance:SetText((not d or d.src == "seen") and TEXT.seen or "")
	end
	Star(r.starB.tex, J.IsTracked(item))
end

--------------------------------------------------------------------------------
-- A dungeon's page: its head, Show / Route / Pick Up Quests, its bosses, its quests
--------------------------------------------------------------------------------

local BossClick = Perf.Shared("OnClick on Dungeon Info's boss rows", function(self)
	if self.boss and S.inst then
		MelloUI:PlayUISound("click")
		P:Show(S.inst, self.boss.id)
	end
end, "script")

local function BossRow(i)
	local r = S.brows[i]
	if r then
		return r
	end
	local page = S.instPage
	r = CreateFrame("Button", nil, page)
	r:RegisterForClicks("LeftButtonUp")
	r.disc = r:CreateTexture(nil, "ARTWORK", nil, 1)
	r.disc:SetTexture(ROUND)
	r.disc:SetSize(22, 22)
	r.disc:SetPoint("LEFT", r, "LEFT", 4, 0)
	W.Paint(r.disc, "mainWindow", "vertex")
	r.ring = r:CreateTexture(nil, "ARTWORK", nil, 2)
	r.ring:SetPoint("CENTER", r.disc, "CENTER", 0, 0)
	r.ring:SetSize(26, 26)
	W.Icon(r.ring, "ring_gold")
	r.num = W.Text(r, "GameFontHighlight", nil, "text")
	r.num:SetPoint("CENTER", r.disc, "CENTER", 0, 0)
	r.skull = r:CreateTexture(nil, "ARTWORK", nil, 3)
	r.skull:SetSize(24, 24)
	r.skull:SetPoint("CENTER", r.disc, "CENTER", 0, 0)
	W.Icon(r.skull, "kill_elite")
	r.name = W.Text(r, "GameFontHighlight", nil, "text")
	r.name:SetWordWrap(false)
	r.name:SetPoint("LEFT", r.disc, "RIGHT", 10, 0)
	r.drops = {}
	for k = 1, 3 do
		local frame, icon = ItemPicture(r, 20)
		frame:SetPoint("RIGHT", r, "RIGHT", -4 - (3 - k) * 25, 0)
		local star = r:CreateTexture(nil, "OVERLAY")
		star:SetSize(11, 11)
		star:SetPoint("CENTER", frame, "TOPRIGHT", -2, -2)
		Star(star, true)
		W.Paint(star, "selectedTrim", "vertex")
		r.drops[k] = { frame = frame, icon = icon, star = star }
	end
	r.name:SetPoint("RIGHT", r.drops[1].frame, "LEFT", -6, 0)
	Perf.SetScript(r, "OnClick", BossClick)
	W.RowPlate(r)
	S.brows[i] = r
	return r
end

local function FillBossRow(r, boss, i, n)
	r.boss = boss
	local last = i == n
	r.disc:SetShown(not last)
	r.ring:SetShown(not last)
	r.num:SetShown(not last)
	r.skull:SetShown(last)
	r.num:SetText(i)
	r.name:SetText(boss.name)
	-- (his three best drops, your starred ones first)
	local shown, drops = {}, J.Drops(boss)
	for _, d in ipairs(drops) do
		if J.IsTracked(d.item) and #shown < 3 then
			shown[#shown + 1] = d
		end
	end
	for _, d in ipairs(drops) do
		if #shown < 3 and not J.IsTracked(d.item) and (d.quality >= 2 or d.quality == 0) and (d.starts or 0) == 0 then
			shown[#shown + 1] = d
		end
	end
	for k = 1, 3 do
		local slot = r.drops[4 - k]   -- (from the right: the first drop rightmost)
		local d = shown[k]
		slot.frame:SetShown(d ~= nil)
		slot.icon:SetShown(d ~= nil)
		slot.star:SetShown(d ~= nil and J.IsTracked(d.item))
		if d then
			SetItemPicture(slot.frame, slot.icon, d.item, d.quality)
		end
	end
end

-- (1.2.2) the trash's row: a boss row (pool slot 0, never one of the bosses') with the plain kill mark, its drops'
-- best three; a click opens their page as a boss's
local function TrashRow(inst)
	local r = S.brows[0]
	if not r then
		r = BossRow(0)
		W.Icon(r.skull, "kill")
	end
	FillBossRow(r, inst.trash, 1, 1)   -- (the mark shown, no number)
	r.name:SetText(TEXT.trashDrops)
	return r
end

local QuestClick = Perf.Shared("OnClick on Dungeon Info's quest rows", function(self)
	local row = self.row
	local R = rawget(MelloUI, "Route")
	local F = J.F
	if row and R and R.SetDestinationTo and row[F.CONT] and row[F.CONT] >= 0 and (row[F.WX] ~= 0 or row[F.WY] ~= 0) then
		MelloUI:PlayUISound("click")
		R:SetDestinationTo({ cont = row[F.CONT], wx = row[F.WX], wy = row[F.WY] }, row[F.GIVER], true)
	end
end, "script")

local QuestEnter = Perf.Shared("OnEnter on Dungeon Info's quest rows", function(self)
	if self.row then
		W.ShowTooltip(self, self.title:GetText() or "", TEXT.questTip)
	end
end, "script")

local MARK = { take = "quest_mark", log = "track_todo", done = "ql_completed", later = "ql_notyet" }

local function QuestRow(page, i)
	local pool = S.qrows[page]
	if not pool then
		pool = {}
		S.qrows[page] = pool
	end
	local r = pool[i]
	if r then
		return r
	end
	r = CreateFrame("Button", nil, page)
	r:RegisterForClicks("LeftButtonUp")
	r.mark = r:CreateTexture(nil, "ARTWORK")
	r.mark:SetSize(T.MARK, T.MARK)
	r.mark:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -(T.ROW_TOP - 2))
	r.title = W.Text(r, "GameFontHighlight", nil, "text")
	r.title:SetWordWrap(false)
	r.title:SetPoint("TOPLEFT", r, "TOPLEFT", T.TITLE_X, -T.ROW_TOP)
	r.title:SetPoint("RIGHT", r, "RIGHT", -4, 0)
	r.line = W.Text(r, "GameFontHighlight", nil, "text")
	W.Paint(r.line, "text", "text", T.LINE_ALPHA)
	r.line:SetWordWrap(false)
	r.line:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -T.ROW_GAP)
	r.line:SetPoint("RIGHT", r, "RIGHT", -4, 0)
	Perf.SetScript(r, "OnClick", QuestClick)
	Perf.SetScript(r, "OnEnter", QuestEnter)
	Perf.SetScript(r, "OnLeave", W.TipLeave)
	W.RowPlate(r)
	pool[i] = r
	return r
end

local function QuestLine(q)
	local F, row = J.F, q.row
	if q.state == "log" then
		return TEXT.inLog
	elseif q.state == "done" then
		return TEXT.done
	elseif q.state == "later" then
		local level = Finite(UnitLevel("player")) or 1
		if (row[F.REQ] or 0) > level then
			return TEXT.fromLevel:format(row[F.REQ])
		end
		return TEXT.after
	end
	local data = rawget(_G, "MelloUI_QuestListData")
	local zone = data and data.zones and data.zones[row[8]]
	return zone and (row[F.GIVER] .. ", " .. zone) or row[F.GIVER] or ""
end

function P.FillQuestRow(r, q)
	local F, row = J.F, q.row
	r.row = row
	W.Icon(r.mark, MARK[q.state] or "quest_mark")
	r.title:SetText("[" .. row[F.LEVEL] .. "] " .. row[F.TITLE])
	r.line:SetText(QuestLine(q))
	local fade = (q.state == "done" or q.state == "later") and 0.6 or 1
	r.title:SetAlpha(fade)
	r.mark:SetAlpha(fade)
end

local ButtonEnter = Perf.Shared("OnEnter on Dungeon Info's page buttons", function(self)
	W.ShowTooltip(self, self.label:GetText(), self.tip)
end, "script")

local ButtonClick = Perf.Shared("OnClick on Dungeon Info's page buttons", function(self)
	local inst, B = S.inst, S.buttons
	if not inst then
		return
	end
	local door = J.Door(inst)
	if (self == B.show or self == B.route) and not door then
		MelloUI:Print(TEXT.noDoor)
		return
	end
	MelloUI:PlayUISound("click")
	if self == B.show then
		local map = MelloUI:GetModule("Map")
		if map and map.ShowWorld then
			map:ShowWorld(door.cont, door.wx, door.wy)
		end
	elseif self == B.route then
		local R = rawget(MelloUI, "Route")
		if R and R.SetDestinationTo then
			R:SetDestinationTo({ cont = door.cont, wx = door.wx, wy = door.wy }, inst.name, true)
		end
	elseif self == B.quests then
		if J.Trip and J.Trip.Start then
			J.Trip.Start(inst)
		end
	end
end, "script")

local function PageButton(row, icon, label, tip)
	local b = W.RoundIcon(row, T.BUTTON, T.ICONS .. icon)
	b.label = W.Text(row, "GameFontHighlight", label, "text")
	b.label:SetPoint("TOP", b, "BOTTOM", 0, -4)
	b.label:SetJustifyH("CENTER")
	b.tip = tip
	Perf.SetScript(b, "OnClick", ButtonClick)
	Perf.SetScript(b, "OnEnter", ButtonEnter)
	Perf.SetScript(b, "OnLeave", W.TipLeave)
	return b
end

local BackClick = Perf.Shared("OnClick on Dungeon Info's back button", function()
	MelloUI:PlayUISound("click")
	P.Back()
end, "script")

local function BackButton(page)
	local back = CreateFrame("Button", nil, page)
	back:SetSize(200, T.FOLD)
	back:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
	back.arrow = W.RoundIcon(back, T.FOLD, T.ICONS .. "btn_arrow")
	back.arrow.icon:SetRotation(math.pi / 2)
	back.arrow:SetPoint("LEFT", back, "LEFT", 0, 0)
	back.text = W.Text(back, "GameFontHighlight", "", "text")
	back.text:SetPoint("LEFT", back.arrow, "RIGHT", 8, 0)
	Perf.SetScript(back, "OnClick", BackClick)
	Perf.SetScript(back.arrow, "OnClick", BackClick)
	return back
end

-- (1.2.2) a head's fade under its name, from the picture's top: FADE of its height
local FADE = 0.62
-- (1.2.2, the user's pick A) a boss's head: his dungeon's picture, slimmer (BOSS_PICTURE of the width)
local BOSS_PICTURE = 0.26

function P.LayInst()
	local inst, page, width = S.inst, S.instPage, S.pageW
	if not inst then
		return
	end
	local H = S.head
	H.back.text:SetText(inst.kind == 2 and TEXT.allRaids or TEXT.allDungeons)
	-- the head: its picture (the client's own, the plain one for the instances it has none of), its emblem, its name
	local y = T.FOLD + 8
	local picH = floor(width * 0.42)
	-- (1.2.2, the user: "some are missing, some have their artwork streched and they are not fitting inside of the
	-- designated spot") every instance's picture is a file of the client's and its kind (DungeonInfoData.lua), cut to
	-- the box (CutPicture); none: a short plain head
	local plain = not CutPicture(H.picture, inst, width, picH)
	H.fade:SetHeight(floor(picH * FADE))
	H.fade:SetShown(not plain)
	if plain then
		picH = PLAIN_HEAD
	end
	H.picture:SetShown(not plain)
	H.plain:SetShown(plain)
	H.picture:ClearAllPoints()
	H.picture:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
	H.picture:SetSize(width, picH)
	H.emblem:SetIcon(EMBLEM .. inst.emblem)
	H.title:SetText(inst.name)
	local sub = Where(inst)
	if inst.kind == 2 and inst.players and inst.players >= 10 then
		sub = sub .. ", " .. TEXT.raidOf:format(inst.players)
	end
	H.sub:SetText(sub)
	y = y + picH + 10
	-- the buttons
	local B = S.buttons
	B.row:ClearAllPoints()
	B.row:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
	B.row:SetSize(width, T.BUTTON_ROW)
	local take = Takeable(inst)
	B.quests.label:SetText(take > 0 and TEXT.pickUpN:format(take) or TEXT.pickUp)
	B.quests.tip = take > 0 and TEXT.pickUpTip or TEXT.pickUpNone
	B.quests:SetAlpha(take > 0 and 1 or 0.5)
	local door = J.Door(inst) ~= nil
	B.show:SetAlpha(door and 1 or 0.5)
	B.route:SetAlpha(door and 1 or 0.5)
	local step = width / 3
	B.show:ClearAllPoints()
	B.show:SetPoint("TOP", B.row, "TOPLEFT", step * 0.5, 0)
	B.route:ClearAllPoints()
	B.route:SetPoint("TOP", B.row, "TOPLEFT", step * 1.5, 0)
	B.quests:ClearAllPoints()
	B.quests:SetPoint("TOP", B.row, "TOPLEFT", step * 2.5, 0)
	y = y + T.BUTTON_ROW + 6
	-- its bosses
	local n = #inst.bosses
	local nh = 1
	y = PutHeading(page, nh, y, width, TEXT.bosses, n > 0 and n or nil)
	for i, boss in ipairs(inst.bosses) do
		local r = BossRow(i)
		FillBossRow(r, boss, i, n)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
		r:SetSize(width, 32)
		r:Show()
		y = y + 32
	end
	HideFrom(S.brows, n)
	S.noBosses:SetShown(n == 0)
	if n == 0 then
		S.noBosses:ClearAllPoints()
		S.noBosses:SetPoint("TOPLEFT", page, "TOPLEFT", 2, -(y + 4))
		S.noBosses:SetWidth(width - 4)
		y = y + 30
	end
	-- (1.2.2) its trash's rare drops: one row, their page a click away
	nh = nh + 1
	local nTrash = #J.Drops(inst.trash)
	y = PutHeading(page, nh, y + 8, width, TEXT.trash, nTrash > 0 and nTrash or nil)
	local tr = TrashRow(inst)
	tr:ClearAllPoints()
	tr:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
	tr:SetSize(width, 32)
	tr:Show()
	y = y + 32
	-- its quests
	local quests = J.Quests(inst, S.quests)
	nh = nh + 1
	y = PutHeading(page, nh, y + 8, width, TEXT.quests, #quests > 0 and #quests or nil)
	for i, q in ipairs(quests) do
		local r = QuestRow(page, i)
		P.FillQuestRow(r, q)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
		r:SetSize(width, 38)
		r:Show()
		y = y + 38
	end
	HideFrom(S.qrows[page] or {}, #quests)
	S.noQuests:SetShown(#quests == 0)
	if #quests == 0 then
		S.noQuests:ClearAllPoints()
		S.noQuests:SetPoint("TOPLEFT", page, "TOPLEFT", 2, -(y + 4))
		y = y + 30
	end
	HideFrom(S.heads[page] or {}, nh)
	PageHeight(page, max(y + T.PAD, 1))
end

--------------------------------------------------------------------------------
-- A boss's page: his drops (the data's, then the ones seen in front of you)
--------------------------------------------------------------------------------


function P.LayBoss()
	local inst, boss, page, width = S.inst, S.boss, S.bossPage, S.pageW
	if not (inst and boss) then
		return
	end
	local H = S.bossHead
	H.back.text:SetText(inst.name)
	local y = T.FOLD + 10
	H.title:SetText(boss.trash and TEXT.trashDrops or boss.name)
	local n = #inst.bosses
	H.sub:SetText(boss.trash and TEXT.trashSub or (boss.index == n and TEXT.lastBoss or TEXT.bossOf):format(boss.index, n))
	-- (1.2.2) his dungeon's picture with his name inside at its top, tall enough for the name and its line; none: the
	-- name on the column as before
	H.title:SetWidth(width - 20)
	H.sub:SetWidth(width - 20)
	local textH = (Finite(H.title:GetStringHeight()) or 16) + 4 + (Finite(H.sub:GetStringHeight()) or 12)
	local picH = max(floor(width * BOSS_PICTURE), floor(textH + 22))
	local pic = CutPicture(H.picture, inst, width, picH)
	H.picture:SetShown(pic)
	H.fade:SetShown(pic)
	for _, e in ipairs(H.edges) do
		e:SetShown(pic)
	end
	H.title:ClearAllPoints()
	if pic then
		H.picture:ClearAllPoints()
		H.picture:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(T.FOLD + 8))
		H.picture:SetSize(width, picH)
		H.fade:SetHeight(floor(picH * FADE))
		H.title:SetPoint("TOPLEFT", H.picture, "TOPLEFT", 10, -10)
		y = T.FOLD + 8 + picH + 10
	else
		H.title:SetPoint("TOPLEFT", page, "TOPLEFT", 2, -y)
		y = y + textH + 2 + 12
	end
	-- (1.2.2) the data's, DungeonJournal's and the ones seen fall, in one list; a trash drop's line names who drops it
	local drops = J.Drops(boss)
	y = PutHeading(page, 1, y, width, TEXT.loot, #drops > 0 and #drops or nil)
	local i = 0
	for _, d in ipairs(drops) do
		i = i + 1
		local r = ItemRow(page, i)
		FillItemRow(r, d.item, d, boss.trash and d.mobs ~= "" and d.mobs or nil)
		r.inst, r.boss, r.mine = inst, boss, false
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
		r:SetSize(width, 34)
		r:Show()
		y = y + 34
	end
	HideFrom(S.irows[page] or {}, i)
	S.noLoot:SetText(boss.trash and TEXT.noTrash or TEXT.noLoot)
	S.noLoot:SetShown(i == 0)
	if i == 0 then
		S.noLoot:ClearAllPoints()
		S.noLoot:SetPoint("TOPLEFT", page, "TOPLEFT", 2, -(y + 4))
		S.noLoot:SetWidth(width - 4)
		y = y + 40
	end
	HideFrom(S.heads[page] or {}, 1)
	PageHeight(page, max(y + T.PAD, 1))
end

--------------------------------------------------------------------------------
-- My Items: your stars by dungeon (a heading each), the ones found nowhere last
--------------------------------------------------------------------------------

local mineIDs, mineBy, mineOrder = {}, {}, {}

function P.LayMine()
	local page, width = S.list, S.pageW
	J.Tracked(mineIDs)
	for k in pairs(mineBy) do
		mineBy[k] = nil
	end
	for i = #mineOrder, 1, -1 do
		mineOrder[i] = nil
	end
	for _, id in ipairs(mineIDs) do
		local inst, boss, d = J.WhereDrops(id)
		local key = inst or false
		if not mineBy[key] then
			mineBy[key] = {}
			mineOrder[#mineOrder + 1] = key
		end
		local list = mineBy[key]
		list[#list + 1] = { id = id, inst = inst, boss = boss, d = d }
	end
	table.sort(mineOrder, function(a, b)
		if a == false or b == false then
			return b == false and a ~= false
		end
		return a.lo < b.lo or (a.lo == b.lo and a.name < b.name)
	end)
	local y, nh, ni = 0, 0, 0
	for _, key in ipairs(mineOrder) do
		nh = nh + 1
		y = PutHeading(page, nh, y, width, key and key.name or TEXT.elsewhere, #mineBy[key])
		for _, e in ipairs(mineBy[key]) do
			ni = ni + 1
			local r = ItemRow(page, ni)
			FillItemRow(r, e.id, e.d, e.boss and e.boss.name or nil)
			r.inst, r.boss, r.mine = e.inst, e.boss, true
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
			r:SetSize(width, 34)
			r:Show()
			y = y + 34
		end
		y = y + 8
	end
	HideFrom(S.heads[page] or {}, nh)
	HideFrom(S.drows, 0)
	HideFrom(S.irows[page] or {}, ni)
	S.mineEmpty:SetShown(ni == 0)
	if ni == 0 then
		S.mineEmpty:SetWidth(width - 4)
		y = 60
	end
	PageHeight(page, max(y + T.PAD, 1))
end

--------------------------------------------------------------------------------
-- The pane: its tabs, the pager, the pages; the moves between them
--------------------------------------------------------------------------------

function P.SyncBar()
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

local function BarChanged(self, value)
	if not self.laying then
		S.pager:ScrollTo(Finite(value) or 0, true)
	end
end

local function TabText()
	local n = J.TrackedCount()
	S.tabs.mine:SetText(n > 0 and (TEXT.mine .. "  " .. n) or TEXT.mine)
	PanelTemplates_TabResize(S.tabs.mine, 8)
end

local TabClick = Perf.Shared("OnClick on Dungeon Info's tabs", function(self)
	MelloUI:PlayUISound("tab")
	P.Tab(self.key)
end, "script")

function P.Tab(key)
	S.tab = key
	for k, tab in pairs(S.tabs) do
		tab:SetSelected(k == key)
	end
	S.inst, S.boss = nil, nil
	P.LayCurrentList()
	S.pager:Show(S.list, 0, not S.shown)
	S.pager:ScrollTo(0, true)
	P.SyncBar()
end

function P.LayCurrentList()
	if S.tab == "mine" then
		P.LayMine()
	else
		P.LayList()
	end
end

function P.Back()
	local pager = S.pager
	local cur = pager:Current()
	if cur == S.bossPage and S.inst then
		S.boss = nil
		P.LayInst()
		pager:Show(S.instPage, -1)
	elseif cur == S.tripPage and S.inst then
		P.LayInst()
		pager:Show(S.instPage, -1)
	else
		S.inst, S.boss = nil, nil
		P.LayCurrentList()
		pager:Show(S.list, -1)
		pager:ScrollTo(S.listOffset or 0, true)
	end
	P.SyncBar()
end

-- (DungeonInfoTrip.lua) the quest trip's page, slid in from its dungeon's; false while Dungeon Info does not show
function P.ShowTrip(inst)
	if not (S.built and S.shown and inst) then
		return false
	end
	local pager = S.pager
	if pager:Current() == S.list then
		S.listOffset = pager:Offset()
	end
	S.inst, S.boss = inst, nil
	J.Trip.LayPage()
	pager:Show(S.tripPage, pager:Current() == S.tripPage and 0 or 1)
	pager:ScrollTo(0, true)
	P.SyncBar()
	return true
end

-- (DungeonInfoTrip.lua) the pieces its page is laid with
P.Kit = { BackButton = BackButton, PutHeading = PutHeading, HideFrom = HideFrom, PageHeight = PageHeight }
function P.Measures()
	return T
end

-- a page of Dungeon Info: the instance's (its boss's with an encounter id), the list without one
function P:Show(inst, encounterID)
	if not S.built then
		S.pending = { inst = inst, boss = encounterID }
		return
	end
	local pager = S.pager
	if not inst then
		P.Tab(S.tab == "mine" and "dungeons" or S.tab)
		return
	end
	local tab = inst.kind == 2 and "raids" or "dungeons"
	if S.tab ~= tab then
		S.tab = tab
		for k, t in pairs(S.tabs) do
			t:SetSelected(k == tab)
		end
	end
	if pager:Current() == S.list then
		S.listOffset = pager:Offset()
	end
	S.inst = inst
	local boss = encounterID and inst.trash and inst.trash.id == encounterID and inst.trash or nil
	for _, b in ipairs(inst.bosses) do
		if b.id == encounterID then
			boss = b
		end
	end
	S.boss = boss
	local instant = not S.shown
	if boss then
		P.LayBoss()
		pager:Show(S.bossPage, 1, instant)
	else
		P.LayInst()
		pager:Show(S.instPage, 1, instant)
	end
	pager:ScrollTo(0, true)
	P.SyncBar()
end

-- the page on show laid again (a change of your stars, quests, the items the game has come to know)
function P:Lay()
	if not (S.built and S.shown) then
		S.dirty = true
		return
	end
	S.dirty = false
	TabText()
	local cur = S.pager:Current()
	if cur == S.bossPage then
		P.LayBoss()
	elseif cur == S.instPage then
		P.LayInst()
	elseif cur == S.tripPage then
		if J.Trip and J.Trip.LayPage then
			J.Trip.LayPage()
		end
	else
		P.LayCurrentList()
	end
end

local LayLater = Perf.Shared("Dungeon Info laid again (next frame)", function()
	S.queued = false
	P:Lay()
end)

local function Queue()
	if not S.queued then
		S.queued = true
		Perf.C_Timer.After(0, LayLater)
	end
end

local OnEvent = Perf.Shared("OnEvent of Dungeon Info's page", function()
	Queue()
end, "script")

local function Build(pane)
	S.built = true
	S.pane = pane
	local function Tab(text, key)
		local tab = CreateFrame("Button", nil, pane, "PanelTopTabButtonTemplate")
		tab:SetText(text)
		PanelTemplates_TabResize(tab, 8)
		tab.key = key
		W.FlatTab(tab, nil)
		Perf.SetScript(tab, "OnClick", TabClick)
		return tab
	end
	S.tabs = { dungeons = Tab(TEXT.dungeons, "dungeons"), raids = Tab(TEXT.raids, "raids"), mine = Tab(TEXT.mine, "mine") }
	S.tabs.dungeons:SetPoint("TOPLEFT", pane, "TOPLEFT", T.PAD - 4, -7)
	S.tabs.raids:SetPoint("LEFT", S.tabs.dungeons, "RIGHT", 2, 0)
	S.tabs.mine:SetPoint("LEFT", S.tabs.raids, "RIGHT", 2, 0)
	local area = CreateFrame("Frame", nil, pane)
	area:SetPoint("TOPLEFT", pane, "TOPLEFT", T.PAD, -(T.HEAD + 6))
	area:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -T.PAD, T.PAD)
	local pager = W.Pager(area, { step = 80, slide = T.SLIDE, outInstant = true })
	S.pager = pager
	local scroll = pager.scroll
	scroll:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -2 * T.BAR, 0)
	S.pageW = T.W - 2 * T.PAD - 2 * T.BAR
	S.list = pager:NewPage()
	S.instPage = pager:NewPage()
	S.bossPage = pager:NewPage()
	S.tripPage = pager:NewPage()
	for _, page in ipairs({ S.list, S.instPage, S.bossPage, S.tripPage }) do
		page:SetWidth(S.pageW)
	end
	local bar = W.ThinScrollBar(area, T.BAR)
	bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", T.BAR, 0)
	bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", T.BAR, 0)
	bar:Hide()
	Perf.SetScript(bar, "OnValueChanged", BarChanged)
	S.bar = bar
	Perf.hooksecurefunc(scroll, "SetVerticalScroll", P.SyncBar)
	Perf.SetScript(scroll, "OnSizeChanged", P.SyncBar)
	S.mineEmpty = W.Text(S.list, "GameFontHighlight", TEXT.mineEmpty, "text")
	S.mineEmpty:SetPoint("TOPLEFT", S.list, "TOPLEFT", 2, -12)
	S.mineEmpty:Hide()
	-- a dungeon's head and buttons
	local page = S.instPage
	local H = {}
	H.back = BackButton(page)
	H.picture = page:CreateTexture(nil, "BACKGROUND", nil, 1)
	-- (1.2.2) the plain head of an instance with no picture: the inner panel in the picture's place
	H.plain = page:CreateTexture(nil, "BACKGROUND", nil, 0)
	H.plain:SetTexture("Interface\\Buttons\\WHITE8X8")
	H.plain:SetAllPoints(H.picture)
	W.Paint(H.plain, "innerPanel", "vertex")
	H.plain:Hide()
	H.edges = W.HairEdges(page, "BORDER", H.picture)
	-- (1.2.2, the user: the name block "not fitting inside of the designated spot"; their pick B of the two placements)
	-- the emblem and the name inside the picture at its top, over a fade (FADE) from the column's colour
	H.fade = Fade(page, 2)
	H.fade:SetPoint("TOPLEFT", H.picture, "TOPLEFT", 0, 0)
	H.fade:SetPoint("TOPRIGHT", H.picture, "TOPRIGHT", 0, 0)
	H.emblem = W.RoundIcon(page, 46, nil)
	H.emblem:EnableMouse(false)
	H.emblem:SetPoint("TOPLEFT", H.picture, "TOPLEFT", 8, -8)
	H.band = MelloUI.Shade:Band(page, { alpha = 0.75, feather = 14, layer = "ARTWORK" })
	H.title = W.Text(page, "GameFontNormalLarge", nil, "selectedTrim")
	H.title:SetPoint("BOTTOMLEFT", H.emblem, "RIGHT", 8, 2)
	H.title:SetWordWrap(false)
	H.sub = W.Text(page, "GameFontHighlight", nil, "text")
	H.sub:SetPoint("TOPLEFT", H.title, "BOTTOMLEFT", 0, -3)
	H.sub:SetWordWrap(false)
	if H.band then
		H.band:Anchor(H.title, H.sub, 4, 2)
	end
	S.head = H
	local row = CreateFrame("Frame", nil, page)
	row:SetHeight(T.BUTTON_ROW)
	local B = { row = row }
	B.show = PageButton(row, "goal_pin", TEXT.show, TEXT.showTip)
	B.route = PageButton(row, "btn_way", TEXT.route, TEXT.routeTip)
	B.quests = PageButton(row, "page_questlist", TEXT.pickUp, TEXT.pickUpTip)
	S.buttons = B
	S.noBosses = W.Text(page, "GameFontHighlight", TEXT.noBosses, "text")
	S.noQuests = W.Text(page, "GameFontHighlight", TEXT.noQuests, "text")
	-- a boss's head (1.2.2, the user's pick A: his dungeon's picture, slimmer, his name inside it at its top over the
	-- fade, as the dungeon's own head)
	local bp = S.bossPage
	local BH = {}
	BH.back = BackButton(bp)
	BH.picture = bp:CreateTexture(nil, "BACKGROUND", nil, 1)
	BH.picture:Hide()
	BH.fade = Fade(bp, 2)
	BH.fade:SetPoint("TOPLEFT", BH.picture, "TOPLEFT", 0, 0)
	BH.fade:SetPoint("TOPRIGHT", BH.picture, "TOPRIGHT", 0, 0)
	BH.edges = W.HairEdges(bp, "BORDER", BH.picture)
	BH.title = W.Text(bp, "GameFontNormalLarge", nil, "selectedTrim")
	BH.title:SetWordWrap(false)
	BH.sub = W.Text(bp, "GameFontHighlight", nil, "text")
	BH.sub:SetPoint("TOPLEFT", BH.title, "BOTTOMLEFT", 0, -4)
	BH.band = MelloUI.Shade:Band(bp, { alpha = 0.75, feather = 14, layer = "ARTWORK" })
	if BH.band then
		BH.band:Anchor(BH.title, BH.sub, 4, 2)
	end
	S.bossHead = BH
	S.noLoot = W.Text(bp, "GameFontHighlight", TEXT.noLoot, "text")
	-- laid again as the game comes to know items, or your quests change, while it shows
	local f = CreateFrame("Frame", nil, pane)
	Perf.SetScript(f, "OnEvent", OnEvent)
	S.events = f
	MelloUI:On("dungeonInfo:tracked", Queue, "Dungeon Info panel")
	for k, tab in pairs(S.tabs) do
		tab:SetSelected(k == S.tab)
	end
	TabText()
end

function P:Mount(pane, hostT)
	T = hostT
	if not S.built then
		Build(pane)
	end
	return true
end

function P:HostShow(on)
	on = on and true or false
	if on == S.shown then
		return
	end
	S.shown = on
	local f = S.events
	if f then
		if on then
			f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
			f:RegisterEvent("QUEST_LOG_UPDATE")
			f:RegisterEvent("QUEST_TURNED_IN")
		else
			f:UnregisterAllEvents()
		end
	end
	if on then
		local pending = S.pending
		S.pending = nil
		if pending then
			P:Show(pending.inst, pending.boss)
		elseif not S.pager:Current() then
			P.Tab(S.tab)
		else
			P:Lay()
		end
	end
end

function P:Unmount()
	P:HostShow(false)
end
