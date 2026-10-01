--------------------------------------------------------------------------------
-- MelloUI - Damage Meter: the Fight History (0.17.0)
--
-- MelloUI's own window in the place of the game's meter windows (the user,
-- 2026-10-01; MelloUI-BuildData/output/meter_sketch/fight_history.jpg): every
-- fight of this login (Modules/Meter.lua's records), grouped by run.
--   left    "This run" on top (its fights, time, your DPS and rank), then the
--           fights newest first under their run's name ("The Deadmines, run
--           1"): name, time and length, your DPS and rank. The foot: "This
--           session: N fights" and Clear (MelloUI:Confirm). The mouse wheel
--           scrolls it (only the rows in view are laid)
--   right   the fight's head line (name, length, won or lost, time); tabs
--           Damage / Healing / Your spells (W.FlatTab); the ledger: each
--           player's class medallion, rank and name, the share line of the
--           top, per second and the total; under Damage, your top spells
-- Its shell is Kit:OwnWindow (the own windows' look, "config"; its mover
-- "MelloUIFightHistory", right above the chat by default); the body is the
-- dark inner panel, or the meter's parchment with its painted edge while the
-- damage meter's Parchment is on (Kit:ParchmentSheet / Kit:StoneDim, area
-- "meter"), its text then in dark ink (MelloUI.QuestInk surface "meter").
-- Built on its first open (WINDOW-RULES 2f).
-- The chat button: a small rising bar chart in the chat's left button
-- column, under the channels' "#" (and the voice buttons when they show),
-- dressed as the column's own (ChatPanel's pick C: the glyph on a dark
-- disc). A child of the column, so Chat Buttons off hides it with the rest.
-- Tooltip "Fight History / Every fight of this session"; a click toggles the
-- window. Made after the login's frames while Fight History is on.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("MeterHistory")
local Shared = Perf.Shared
local CreateFrame = MelloUI.Safe.CreateFrame
local W = MelloUI.Widgets
local Kit = MelloUI.Kit
local Meter = ns.Meter
local M = Meter.M
local ipairs, pairs, type, max, min, floor = ipairs, pairs, type, math.max, math.min, math.floor

local WHITE = "Interface\\Buttons\\WHITE8x8"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local AREA = "meter"   -- (the parchment's and the ink's area: the damage meter's)

local H = {
	WIDTH = 660, HEIGHT = 430, TOP = 34, PAD = 14, FOOT = 40,
	LIST_W = 236, ROW = 34, HEAD = 22, RUN_ROW = 40,
	LEDGER_ROW = 28, LEDGER_MAX = 8, MEDAL = 20, SPELL_ROW = 17, SPELLS_SHORT = 4,
	TAB_W = 96, BUTTON = 32, DISC = 22, GLYPH = 14,
}

local TEXT = {
	title = "Fight History",
	thisRun = "This run",
	runLine = "%s, %d fights, %s",
	runLineOne = "%s, 1 fight, %s",
	session = "This session: %d fights",
	sessionOne = "This session: 1 fight",
	clear = "Clear",
	clearAsk = "Clear the Fight History of this session?",
	cancel = "Cancel",
	empty = "No fights yet. Each fight you are in shows here when it ends.",
	damage = "Damage",
	healing = "Healing",
	spells = "Your spells",
	spellsHead = "YOUR SPELLS",
	won = "fight won",
	lost = "you died",
	noSpells = "No spells of yours in this fight.",
	noHealing = "No healing in this fight.",
	perSecond = "%s/s",
	rankOf = "%s/s  #%d",
	buttonTip = "Fight History",
	buttonDesc = "Every fight of this session.",
}

local win = { frame = nil, shell = nil, entries = {}, offset = 0, sel = nil, tab = "damage", slots = {}, ledger = {},
	spellRows = {}, ink = false }
local button = nil

local function On()
	return M.isEnabled and M.db and M.db.history ~= false or false
end

local function StyleText(fs, size)
	local object = _G.GameFontHighlight
	if type(object) == "table" then
		fs:SetFontObject(object)
		if MelloUI.StyleFont then
			MelloUI:StyleFont(fs, "fontText", object, size)
		end
	end
end

local function Font(parent, size, key, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	StyleText(fs, size)
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	W.Paint(fs, key or "text", "text")
	return fs
end

local function ClassColour(class)
	local QI = MelloUI.QuestInk
	if QI and QI.ClassColour then
		return QI.ClassColour(class)
	end
	return nil
end

-- a texture in a class's colour (else the palette's key)
local function Tint(tex, class, key)
	local r, g, b = ClassColour(class)
	if r then
		Kit:Unpaint(tex, "vertex")
		tex:SetVertexColor(r, g, b)
	else
		W.Paint(tex, key or "trim", "vertex")
	end
end

-- a player's name as the window says it: "You" in gold
local function NameOf(s)
	return s.me and Meter.TEXT.you or s.n or Meter.TEXT.someone
end

--------------------------------------------------------------------------------
-- The ink on parchment (the damage meter's Parchment)
--------------------------------------------------------------------------------

local surfaceMade = false

local function InkOn()
	return win.frame ~= nil and Kit:ParchmentOn(AREA)
end

local function InkRoots()
	return win.left, win.right
end

local function Ink()
	local QI = MelloUI.QuestInk
	if not (QI and QI.Surface) then
		return
	end
	if not surfaceMade then
		surfaceMade = true
		QI.Surface(AREA, { on = InkOn, sheet = true, roots = InkRoots })
	else
		QI.RefreshSurface(AREA)
	end
end

--------------------------------------------------------------------------------
-- The left list: "This run", then each run's fights newest first
--------------------------------------------------------------------------------

-- the entries: { kind = "head", run } and { kind = "fight", fight }
local function Entries()
	local list = win.entries
	for i = #list, 1, -1 do
		list[i] = nil
	end
	local fights = Meter.Fights()
	local lastRun = false
	for i = #fights, 1, -1 do
		local f = fights[i]
		if f.run ~= lastRun then
			lastRun = f.run
			list[#list + 1] = { kind = "head", run = f.run }
		end
		list[#list + 1] = { kind = "fight", fight = f }
	end
	return list
end

local function EntryHeight(e)
	return e.kind == "head" and H.HEAD or H.ROW
end

-- your rate and rank in a fight ("41.8/s  #1"; healing for a healer's)
local function MineText(fight)
	local s, rank, of, healing = Meter.Mine(fight)
	if not s then
		return ""
	end
	local rate = healing and s.hps or s.dps
	if of <= 1 then
		return TEXT.perSecond:format(Meter.Plain(rate))
	end
	return TEXT.rankOf:format(Meter.Plain(rate), rank)
end

local Select   -- (below)

local SlotClick = Shared("OnClick on a Fight History row", function(slot)
	local e = slot.entry
	if e and e.kind == "fight" then
		MelloUI:PlayUISound("tab")
		Select({ kind = "fight", fight = e.fight })
	end
end, "script")

local function NewSlot(parent)
	local slot = CreateFrame("Button", nil, parent)
	slot:SetHeight(H.ROW)
	local sel = W.Solid(slot, "BACKGROUND", "selectedTab", 0.55)
	sel:SetAllPoints(slot)
	sel:Hide()
	slot.sel = sel
	local hover = W.Solid(slot, "BACKGROUND", "hover", 0.35)
	hover:SetAllPoints(slot)
	slot:SetHighlightTexture(hover)
	slot.name = Font(slot, 13, "text")
	slot.name:SetPoint("TOPLEFT", slot, "TOPLEFT", 8, -4)
	slot.name:SetPoint("RIGHT", slot, "RIGHT", -86, 0)
	slot.sub = Font(slot, 11, "text")
	slot.sub:SetPoint("TOPLEFT", slot.name, "BOTTOMLEFT", 0, -2)
	slot.sub:SetAlpha(0.8)
	slot.right = Font(slot, 12, "text", "RIGHT")
	slot.right:SetPoint("TOPRIGHT", slot, "TOPRIGHT", -8, -5)
	-- a run's head: small capitals in gold with a line after them
	slot.head = Font(slot, 11, "selectedTrim")
	slot.head:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", 4, 4)
	slot.line = W.Solid(slot, "ARTWORK", "border", 1)
	slot.line:SetHeight(1)
	slot.line:SetPoint("LEFT", slot.head, "RIGHT", 6, 0)
	slot.line:SetPoint("RIGHT", slot, "RIGHT", -6, 0)
	Perf.SetScript(slot, "OnClick", SlotClick)
	return slot
end

local function FillSlot(slot, e)
	slot.entry = e
	local head = e.kind == "head"
	slot:SetHeight(EntryHeight(e))
	slot:EnableMouse(not head)
	slot.head:SetShown(head)
	slot.line:SetShown(head)
	slot.name:SetShown(not head)
	slot.sub:SetShown(not head)
	slot.right:SetShown(not head)
	if head then
		slot.head:SetText(Meter.RunName(e.run):upper())
		slot.sel:Hide()
		return
	end
	local f = e.fight
	slot.name:SetText(f.name or "")
	slot.sub:SetText((f.clock or "") .. "  \194\183  " .. Meter.Clock(f.dur))
	slot.right:SetText(MineText(f))
	local sel = win.sel
	slot.sel:SetShown(sel ~= nil and sel.kind == "fight" and sel.fight == f)
end

-- the rows in view, from the scroll offset (an entry index)
local function LayList()
	local pane = win.list
	local entries = win.entries
	local height = pane:GetHeight()
	height = (type(height) == "number" and height > 0) and height or 300
	local n = #entries
	win.offset = max(0, min(win.offset, n - 1))
	local y, used = 0, 0
	for i = win.offset + 1, n do
		local e = entries[i]
		local h = EntryHeight(e)
		if y + h > height then
			break
		end
		used = used + 1
		local slot = win.slots[used]
		if not slot then
			slot = NewSlot(pane)
			win.slots[used] = slot
		end
		slot:ClearAllPoints()
		slot:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -y)
		slot:SetPoint("RIGHT", pane, "RIGHT", 0, 0)
		FillSlot(slot, e)
		slot:Show()
		y = y + h
	end
	for i = used + 1, #win.slots do
		win.slots[i]:Hide()
		win.slots[i].entry = nil
	end
	win.inView = used
	win.empty:SetShown(n == 0)
end

local ListWheel = Shared("OnMouseWheel on the Fight History list", function(_, delta)
	local n = #win.entries
	local before = win.offset
	win.offset = max(0, min(win.offset - delta * 2, n - (win.inView or 1)))
	if win.offset ~= before then
		LayList()
	end
end, "script")

-- "This run": its fights, time, and your run DPS and rank
local function RunRow()
	local row = win.runRow
	local st = Meter.Store()
	local c = Meter.RunStats(st.run)
	if not (c and c.fights > 0) then
		row:Hide()
		return
	end
	row:Show()
	local name = Meter.RunName(st.run)
	row.sub:SetText(c.fights == 1 and TEXT.runLineOne:format(name, Meter.Clock(c.dur))
		or TEXT.runLine:format(name, c.fights, Meter.Clock(c.dur)))
	-- your rank in the run by damage
	local mine, rank, of = nil, 1, 0
	for _, e in pairs(c.by) do
		of = of + 1
		if e.me then
			mine = e
		end
	end
	if mine then
		for _, e in pairs(c.by) do
			if e ~= mine and e.d > mine.d then
				rank = rank + 1
			end
		end
		local rate = c.dur > 0 and mine.d / c.dur or 0
		row.right:SetText(of > 1 and TEXT.rankOf:format(Meter.Plain(rate), rank) or TEXT.perSecond:format(Meter.Plain(rate)))
	else
		row.right:SetText("")
	end
	local sel = win.sel
	row.sel:SetShown(sel ~= nil and sel.kind == "run")
end

local RunClick = Shared("OnClick on the Fight History's This run", function()
	MelloUI:PlayUISound("tab")
	Select({ kind = "run", run = Meter.Store().run })
end, "script")

--------------------------------------------------------------------------------
-- The right side: the head line, the tabs, the ledger, your spells
--------------------------------------------------------------------------------

-- the rows a selection shows on a tab: { n, c, me, value, rate } best first
local rows = {}
local function LedgerRows(sel, tab)
	for i = #rows, 1, -1 do
		rows[i] = nil
	end
	local healing = tab == "healing"
	if sel.kind == "run" then
		local c = Meter.RunStats(sel.run)
		if c then
			for _, e in pairs(c.by) do
				local v = healing and e.h or e.d
				if v > 0 then
					rows[#rows + 1] = { n = e.n, c = e.c, me = e.me, value = v, rate = c.dur > 0 and v / c.dur or 0 }
				end
			end
		end
	else
		for _, s in ipairs(sel.fight.src) do
			local v = healing and s.h or s.d
			if v > 0 then
				rows[#rows + 1] = { n = s.n, c = s.c, me = s.me, value = v, rate = (healing and s.hps or s.dps) or 0 }
			end
		end
	end
	table.sort(rows, function(a, b) return a.value > b.value end)
	return rows
end

local function LedgerRow(i)
	local row = win.ledger[i]
	if row then
		return row
	end
	local pane = win.board
	row = CreateFrame("Frame", nil, pane)
	row:SetHeight(H.LEDGER_ROW)
	row:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -(i - 1) * H.LEDGER_ROW)
	row:SetPoint("RIGHT", pane, "RIGHT", 0, 0)
	local disc = row:CreateTexture(nil, "ARTWORK", nil, 1)
	disc:SetTexture(ROUND_MASK)
	disc:SetSize(H.MEDAL + 2, H.MEDAL + 2)
	disc:SetPoint("LEFT", row, "LEFT", 2, 0)
	W.Paint(disc, "border", "vertex")
	row.disc = disc
	local medal = row:CreateTexture(nil, "ARTWORK", nil, 2)
	medal:SetSize(H.MEDAL, H.MEDAL)
	medal:SetPoint("CENTER", disc, "CENTER")
	row.medal = medal
	row.name = Font(row, 13, "text")
	row.name:SetPoint("LEFT", disc, "RIGHT", 6, 3)
	row.name:SetPoint("RIGHT", row, "RIGHT", -130, 0)
	row.total = Font(row, 13, "text", "RIGHT")
	row.total:SetPoint("RIGHT", row, "RIGHT", -6, 3)
	row.rate = Font(row, 11, "text", "RIGHT")
	row.rate:SetPoint("RIGHT", row.total, "LEFT", -10, 0)
	row.rate:SetAlpha(0.8)
	-- the share line: the top's whole width, this one's share of it
	local track = W.Solid(row, "BORDER", "border", 0.6)
	track:SetHeight(2)
	track:SetPoint("BOTTOMLEFT", disc, "BOTTOMRIGHT", 6, 1)
	track:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	row.track = track
	local share = row:CreateTexture(nil, "ARTWORK")
	share:SetTexture(WHITE)
	share:SetHeight(2)
	share:SetPoint("LEFT", track, "LEFT", 0, 0)
	row.share = share
	win.ledger[i] = row
	return row
end

local function SpellRow(i)
	local row = win.spellRows[i]
	if row then
		return row
	end
	local pane = win.spellPane
	row = CreateFrame("Frame", nil, pane)
	row:SetHeight(H.SPELL_ROW)
	row:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -18 - (i - 1) * H.SPELL_ROW)
	row:SetPoint("RIGHT", pane, "RIGHT", 0, 0)
	row.name = Font(row, 12, "text")
	row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
	row.name:SetWidth(150)
	row.value = Font(row, 12, "text", "RIGHT")
	row.value:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	local bar = row:CreateTexture(nil, "ARTWORK")
	bar:SetTexture(WHITE)
	bar:SetHeight(3)
	bar:SetPoint("LEFT", row, "LEFT", 160, 0)
	W.Paint(bar, "trim", "vertex")
	row.bar = bar
	-- its dark outline, 1 px round it (the user's test, 2026-10-01: the bare
	-- trim line hardly showed on the parchment)
	local outline = W.Solid(row, "BORDER", "mainWindow", 0.9)
	outline:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
	outline:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
	row.outline = outline
	win.spellRows[i] = row
	return row
end

-- your spells of the shown fight (a run: none)
local function LaySpells(fight, count, top)
	local pane = win.spellPane
	local spells = fight and fight.sp or {}
	local total = 0
	for _, sp in ipairs(spells) do
		total = total + sp.a
	end
	local n = min(#spells, count)
	pane:ClearAllPoints()
	pane:SetPoint("TOPLEFT", win.board, "TOPLEFT", 0, -top)
	pane:SetPoint("RIGHT", win.board, "RIGHT", 0, 0)
	pane:SetHeight(18 + max(1, n) * H.SPELL_ROW)
	pane:SetShown(fight ~= nil)
	win.spellsEmpty:SetShown(fight ~= nil and n == 0)
	local width = (win.board:GetWidth() or 300) - 160 - 90
	local best = spells[1] and spells[1].a or 1
	for i = 1, n do
		local sp, row = spells[i], SpellRow(i)
		row.name:SetText(sp.n)
		local pct = total > 0 and floor(sp.a / total * 100 + 0.5) or 0
		row.value:SetText(Meter.Big(sp.a) .. "  " .. pct .. "%")
		row.bar:SetWidth(max(1, width * sp.a / max(best, 1)))
		row:Show()
	end
	for i = n + 1, #win.spellRows do
		win.spellRows[i]:Hide()
	end
end

local function LayLedger()
	local sel = win.sel
	for _, row in ipairs(win.ledger) do
		row:Hide()
	end
	win.spellPane:Hide()
	win.spellsEmpty:Hide()
	win.boardEmpty:Hide()
	if not sel then
		return
	end
	local fight = sel.kind == "fight" and sel.fight or nil
	if win.tab == "spells" then
		LaySpells(fight, Meter.T.SPELLS, 0)
		if not fight then
			win.spellPane:Hide()
		end
		return
	end
	local list = LedgerRows(sel, win.tab)
	local n = min(#list, H.LEDGER_MAX)
	local width = (win.board:GetWidth() or 300) - (H.MEDAL + 14) - 6
	local top = list[1] and list[1].value or 1
	for i = 1, n do
		local e, row = list[i], LedgerRow(i)
		row.name:SetText(i .. ".  " .. NameOf(e))
		if e.me then
			W.Paint(row.name, "selectedTrim", "text")
		else
			W.Paint(row.name, "text", "text")
		end
		row.total:SetText(Meter.Big(e.value))
		row.rate:SetText(TEXT.perSecond:format(Meter.Plain(e.rate)))
		row.medal:SetTexture(Meter.ClassIcon(e.c) or "Interface\\Icons\\INV_Misc_QuestionMark")
		row.share:SetWidth(max(1, width * e.value / max(top, 1)))
		Tint(row.share, e.c, e.me and "selectedTrim" or "trim")
		row:Show()
	end
	if n == 0 then
		win.boardEmpty:SetText(win.tab == "healing" and TEXT.noHealing or TEXT.empty)
		win.boardEmpty:Show()
	end
	-- under Damage, your top spells when there is room
	if win.tab == "damage" and fight then
		local used = max(n, 1) * H.LEDGER_ROW + 10
		local room = floor(((win.board:GetHeight() or 300) - used - 18) / H.SPELL_ROW)
		local count = min(H.SPELLS_SHORT, room)
		if count > 0 and fight.sp and #fight.sp > 0 then
			LaySpells(fight, count, used)
		end
	end
end

local function LayHead()
	local sel = win.sel
	if not sel then
		win.headName:SetText("")
		win.headSub:SetText("")
		return
	end
	if sel.kind == "run" then
		local c = Meter.RunStats(sel.run)
		win.headName:SetText(TEXT.thisRun)
		win.headSub:SetText(Meter.RunName(sel.run) .. "  \194\183  " .. (c and c.fights or 0) .. "  \194\183  "
			.. Meter.Clock(c and c.dur or 0))
		return
	end
	local f = sel.fight
	win.headName:SetText(f.name or "")
	win.headSub:SetText(Meter.Clock(f.dur) .. "  \194\183  " .. (f.won and TEXT.won or TEXT.lost) .. "  \194\183  "
		.. (f.clock or ""))
end

local function LayTabs()
	for key, tab in pairs(win.tabs) do
		tab:SetSelected(key == win.tab)
	end
	-- (Your spells: a fight's only)
	local sel = win.sel
	local spells = win.tabs.spells
	spells:SetEnabled(sel ~= nil and sel.kind == "fight" and win.tab ~= "spells")
end

local function LayAll()
	if not win.frame then
		return
	end
	Entries()
	-- a selection whose fight is gone (dropped by the cap, Clear): the newest
	local sel = win.sel
	if sel and sel.kind == "fight" then
		local found = false
		for _, f in ipairs(Meter.Fights()) do
			found = found or f == sel.fight
		end
		if not found then
			win.sel = nil
		end
	end
	if not win.sel then
		local last = Meter.Last()
		win.sel = last and { kind = "fight", fight = last } or nil
	end
	if win.sel and win.sel.kind == "run" and win.tab == "spells" then
		win.tab = "damage"
	end
	RunRow()
	LayList()
	LayHead()
	LayTabs()
	LayLedger()
	local n = #Meter.Fights()
	win.count:SetText(n == 1 and TEXT.sessionOne or TEXT.session:format(n))
	Ink()
end

Select = function(sel)
	win.sel = sel
	if sel and sel.kind == "run" and win.tab == "spells" then
		win.tab = "damage"
	end
	RunRow()
	for i = 1, (win.inView or 0) do
		local slot = win.slots[i]
		if slot and slot.entry then
			FillSlot(slot, slot.entry)
		end
	end
	LayHead()
	LayTabs()
	LayLedger()
	Ink()
end

local TabClick = Shared("OnClick on a Fight History tab", function(tab)
	if tab.meterKey and tab.meterKey ~= win.tab then
		MelloUI:PlayUISound("tab")
		win.tab = tab.meterKey
		LayTabs()
		LayLedger()
		Ink()
	end
end, "script")

--------------------------------------------------------------------------------
-- The window (built on its first open)
--------------------------------------------------------------------------------

local function ClearAccepted()
	MelloUI:PlayUISound("page")
	win.sel = nil
	Meter.Clear()
end
local CLEAR_ASK = { text = TEXT.clearAsk, accept = TEXT.clear, cancel = TEXT.cancel, onAccept = ClearAccepted }
local ClearClick = Shared("OnClick on the Fight History's Clear", function()
	MelloUI:Confirm(CLEAR_ASK)
end, "script")

local Shown = Shared("OnShow on the Fight History", function()
	LayAll()
end, "script")

-- right above the chat (its tabs), by default
local function Home(frame)
	frame:ClearAllPoints()
	local chat = _G.ChatFrame1
	if Meter.IsFrame(chat) then
		frame:SetPoint("BOTTOMLEFT", chat, "TOPLEFT", -8, 44)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
end

local function MyEmblem()
	local ok, _, class = pcall(_G.UnitClass, "player")
	return ok and Meter.ClassIcon(class) or nil
end

local function Build()
	local f = CreateFrame("Frame", "MelloUIFightHistory", UIParent)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetSize(H.WIDTH, H.HEIGHT)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:Hide()
	Perf.SetScript(f, "OnShow", Shown)
	win.frame = f
	win.shell = Kit:OwnWindow(f, {
		area = "config", ring = { at = "tl", texture = MyEmblem() }, plate = "rail", title = TEXT.title,
		close = true, escape = true, fit = true, sounds = true,
		mover = { key = "MelloUIFightHistory", label = TEXT.title, page = "BarsMeters", default = Home },
	})
	-- the body: the dark inner panel, or the meter's parchment
	local body = CreateFrame("Frame", nil, f)
	body:SetPoint("TOPLEFT", f, "TOPLEFT", H.PAD, -H.TOP)
	body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -H.PAD, H.PAD)
	win.body = body
	local dim = Kit.StoneDim and Kit:StoneDim(body, { rect = body, area = AREA, alpha = 0.85 })
	if not dim then
		local fill = W.Solid(body, "BACKGROUND", "innerPanel", 0.85)
		fill:SetAllPoints(body)
	end
	if Kit.ParchmentSheet then
		Kit:ParchmentSheet(body, body, { rect = body, margin = 0, area = AREA, fine = true })
	end
	-- the left side
	local left = CreateFrame("Frame", nil, body)
	left:SetPoint("TOPLEFT", body, "TOPLEFT", 8, -8)
	left:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 8, 8)
	left:SetWidth(H.LIST_W)
	win.left = left
	local runRow = NewSlot(left)
	runRow:SetHeight(H.RUN_ROW)
	runRow:SetPoint("TOPLEFT", left, "TOPLEFT", 0, 0)
	runRow:SetPoint("RIGHT", left, "RIGHT", 0, 0)
	runRow.head:Hide()
	runRow.line:Hide()
	runRow.name:SetText(TEXT.thisRun)
	W.Paint(runRow.name, "selectedTrim", "text")
	Perf.SetScript(runRow, "OnClick", RunClick)
	win.runRow = runRow
	local list = CreateFrame("Frame", nil, left)
	list:SetPoint("TOPLEFT", runRow, "BOTTOMLEFT", 0, -6)
	list:SetPoint("RIGHT", left, "RIGHT", 0, 0)
	list:SetPoint("BOTTOM", left, "BOTTOM", 0, H.FOOT)
	list:EnableMouseWheel(true)
	Perf.SetScript(list, "OnMouseWheel", ListWheel)
	win.list = list
	win.empty = Font(list, 12, "text")
	win.empty:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -8)
	win.empty:SetPoint("RIGHT", list, "RIGHT", -8, 0)
	win.empty:SetWordWrap(true)
	win.empty:SetText(TEXT.empty)
	win.count = Font(left, 11, "text")
	win.count:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 6, 12)
	win.clear = W.Button(left, TEXT.clear, 80, win.shell, { onClick = ClearClick })
	win.clear.melloNoInk = true   -- (a plate of its own, as the tabs)
	win.clear:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -4, 4)
	-- the line between the two sides
	local split = W.Solid(body, "ARTWORK", "border", 1)
	split:SetWidth(1)
	split:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
	split:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 8, 0)
	-- the right side
	local right = CreateFrame("Frame", nil, body)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 18, 0)
	right:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -8, 8)
	win.right = right
	win.headName = Font(right, 15, "selectedTrim")
	win.headName:SetPoint("TOPLEFT", right, "TOPLEFT", 2, -2)
	win.headName:SetPoint("RIGHT", right, "RIGHT", -4, 0)
	win.headSub = Font(right, 11, "text")
	win.headSub:SetPoint("TOPLEFT", win.headName, "BOTTOMLEFT", 0, -3)
	win.tabs = {}
	local prev = nil
	for _, t in ipairs({ { "damage", TEXT.damage }, { "healing", TEXT.healing }, { "spells", TEXT.spells } }) do
		local tab = CreateFrame("Button", nil, right, "PanelTopTabButtonTemplate")
		-- (on its own dark plate: its label keeps the light text, never the
		-- parchment's ink -- the user, 2026-10-01: "these tabs are hard to read")
		tab.melloNoInk = true
		tab:SetText(t[2])
		W.FlatTab(tab, win.shell)
		tab:SetWidth(H.TAB_W)
		if prev then
			tab:SetPoint("LEFT", prev, "RIGHT", 4, 0)
		else
			tab:SetPoint("TOPLEFT", win.headSub, "BOTTOMLEFT", -2, -8)
		end
		tab.meterKey = t[1]
		Perf.SetScript(tab, "OnClick", TabClick)
		win.tabs[t[1]] = tab
		prev = tab
	end
	local board = CreateFrame("Frame", nil, right)
	board:SetPoint("TOPLEFT", win.tabs.damage, "BOTTOMLEFT", 2, -8)
	board:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 0)
	win.board = board
	win.boardEmpty = Font(board, 12, "text")
	win.boardEmpty:SetPoint("TOPLEFT", board, "TOPLEFT", 6, -6)
	local spellPane = CreateFrame("Frame", nil, board)
	spellPane:Hide()
	win.spellPane = spellPane
	local spellsHead = Font(spellPane, 11, "selectedTrim")
	spellsHead:SetPoint("TOPLEFT", spellPane, "TOPLEFT", 4, 0)
	spellsHead:SetText(TEXT.spellsHead)
	win.spellsEmpty = Font(board, 12, "text")
	win.spellsEmpty:SetPoint("TOPLEFT", spellPane, "TOPLEFT", 4, -18)
	win.spellsEmpty:SetText(TEXT.noSpells)
	win.spellsEmpty:Hide()
	W.Dress(f, win.shell)
	return f
end

-- a fight shown (from the summary's click), or the window toggled
function Meter.OpenHistory(fight)
	if not On() then
		return
	end
	local f = win.frame or Build()
	if fight then
		win.sel = { kind = "fight", fight = fight }
		win.offset = 0
	end
	if f:IsShown() then
		LayAll()
	else
		f:Show()
	end
end

function Meter.ToggleHistory()
	if win.frame and win.frame:IsShown() then
		win.frame:Hide()
	else
		Meter.OpenHistory()
	end
end

--------------------------------------------------------------------------------
-- The chat button: under the "#" in the chat's left button column
--------------------------------------------------------------------------------

local ButtonClick = Shared("OnClick on the Fight History chat button", function()
	MelloUI:PlayUISound("tab")
	Meter.ToggleHistory()
end, "script")

local ButtonEnter = Shared("OnEnter on the Fight History chat button", function(self)
	W.ShowTooltip(self, TEXT.buttonTip, TEXT.buttonDesc)
end, "script")

local ButtonLeave = Shared("OnLeave on the Fight History chat button", function()
	GameTooltip:Hide()
end, "script")

-- under the channels' button, or under the voice buttons while they show
local function PlaceButton()
	if not button then
		return
	end
	local above = _G.ChatFrameChannelButton
	above = Meter.IsFrame(above) and above or nil
	for _, name in ipairs({ "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton" }) do
		local b = _G[name]
		local ok, shown = pcall(function() return Meter.IsFrame(b) and b:IsShown() end)
		if ok and shown == true then
			above = b
		end
	end
	button:ClearAllPoints()
	if above then
		button:SetPoint("TOP", above, "BOTTOM", 0, -2)
	else
		button:SetPoint("TOP", button:GetParent(), "TOP", 0, -36)
	end
end

local function MakeButton()
	local column = _G.ChatFrame1ButtonFrame
	if button or not Meter.IsFrame(column) or not On() then
		return
	end
	button = CreateFrame("Button", "MelloUIFightHistoryButton", column)
	button:SetSize(H.BUTTON, H.BUTTON)
	button:SetFrameStrata("MEDIUM")
	local disc = button:CreateTexture(nil, "ARTWORK", nil, 1)
	disc:SetTexture(ROUND_MASK)
	disc:SetSize(H.DISC, H.DISC)
	disc:SetPoint("CENTER")
	W.Paint(disc, "innerPanel", "vertex", 0.95)
	local glyph = button:CreateTexture(nil, "ARTWORK", nil, 2)
	W.Glyph(glyph, "chart")
	glyph:SetSize(H.GLYPH, H.GLYPH)
	glyph:SetPoint("CENTER")
	W.Paint(glyph, "text", "vertex")
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetTexture(ROUND_MASK)
	hover:SetSize(H.DISC, H.DISC)
	hover:SetPoint("CENTER")
	W.Paint(hover, "hover", "vertex", 0.5)
	Perf.SetScript(button, "OnClick", ButtonClick)
	Perf.SetScript(button, "OnEnter", ButtonEnter)
	Perf.SetScript(button, "OnLeave", ButtonLeave)
	-- the voice buttons come and go: the button under them follows (post-hooks)
	for _, name in ipairs({ "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton" }) do
		local b = _G[name]
		if Meter.IsFrame(b) then
			Perf.HookScript(b, "OnShow", PlaceButton)
			Perf.HookScript(b, "OnHide", PlaceButton)
		end
	end
	PlaceButton()
end

-- a fight recorded or the history cleared: the open window again
local function Changed()
	if win.frame and win.frame:IsShown() then
		LayAll()
	end
end

-- the module or its settings changed (Meter.lua's Apply)
local listening = false
function Meter.HistoryApply()
	local on = On()
	if on and not listening then
		listening = true
		MelloUI:On("meter", Changed, "Fight History")
	end
	if on then
		MelloUI:AfterLogin(MakeButton)
		if button then
			button:Show()
		end
	else
		if button then
			button:Hide()
		end
		if win.frame then
			win.frame:Hide()
		end
	end
end
