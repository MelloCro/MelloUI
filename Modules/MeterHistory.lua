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
--           player's class face, rank and name, the share of the top on a
--           rail, per second and the total; under Damage, your top spells
-- Its shell is Kit:OwnWindow (the own windows' look, "config"; its mover
-- "MelloUIFightHistory", right above the chat by default); the body is the
-- own windows' panel (W.Panel), with the meter's parchment and its painted
-- edge on it while the damage meter's Parchment is on (Kit:ParchmentSheet,
-- area "meter"), its text then in dark ink (MelloUI.QuestInk surface
-- "meter"; the modern look's title too, on the paper there) and the panel's
-- edge hidden under the paper's own. Built on its first open (WINDOW-RULES
-- 2f).
-- The look (onelook stage B, the user's picks, 2026-10-15): the shell's C,
-- "the brand column" (docs/plans/onelook-b-sketches/shell.md,
-- shell_small.jpg): no title bar; a brand row heads the list column (your
-- class's face in the kit's round rim, "Fight History" in the title face,
-- a hairline under them: shell:Brand), the fight's name and the close on
-- that row's line, the window dragged by its top band (0-56: the brand row
-- and the fight's head, no controls); the painted look (Oldschool) keeps its
-- corner ring and rail plate and lays the body as before (shell:Inset). The
-- meter's B, "the rail" (onelook-b-sketches/meter.md, meter_looks.jpg), as
-- the race bar: each ledger row's face a W.RoundIcon in the kit's rim, the
-- share 3 tall in the class colour on a hairline rail, your spells the same
-- in trim, "Your spells" a W.Header. These are its only look: the game's
-- meter bars and round class icons are reached no more (stage E deletes
-- them), and Oldschool does not dress the rows.
-- The chat button: a small rising bar chart in the chat's left button
-- column, under the channels' "#" (and the voice buttons when they show),
-- dressed as the column's own (ChatPanel's pick C: the glyph on a dark
-- disc). A child of the column, so Chat Buttons off hides it with the rest.
-- Tooltip "Fight History / Every fight of this session"; a click toggles the
-- window. Made after the login's frames while Fight History is on.
-- Its texts, the rows' marks and the chat button are painted through
-- MelloUI.Look (docs/plans/game-look.md, wave 2): the palette's, one look
-- whatever the reskin (onelook stages C and E).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("MeterHistory")
local Shared = Perf.Shared
local CreateFrame = MelloUI.Safe.CreateFrame
local W = MelloUI.Widgets
local Kit = MelloUI.Kit
local Look = MelloUI.Look
local Meter = ns.Meter
local M = Meter.M
local Num, Text = MelloUI.Safe.Number, MelloUI.Safe.Text
local ipairs, pairs, type, max, min, floor = ipairs, pairs, type, math.max, math.min, math.floor

local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local AREA = "meter"   -- (the parchment's and the ink's area: the damage meter's)

-- TOP, PAD: the painted look's body (under its corner ring and rail plate);
-- IN: the two columns inside the body; GRAB, CLOSE_X / CLOSE_Y: the modern
-- look's drag band (from the top) and the close's right edge and middle
-- (from the top right: on the brand row's line, over the ledger's numbers);
-- BRAND_MID: the brand row's middle line under the column's top (the shell's
-- row rim, Kit:OwnWindow), where the fight's name sits too. The ledger (the
-- meter's pick B, "Rail"): FACE the class's face in the kit's rim at FACE_X,
-- FACE_IN its own bronze ring cut off; the texts TEXT_UP over the row's
-- middle, GAP from the face and the row's end; the rail RAIL_DOWN under the
-- middle, 1 tall, the share SHARE tall on it; the spells' rail SPELL_W long
-- at SPELL_X (in both looks: no width read from the inset)
local H = {
	WIDTH = 660, HEIGHT = 430, TOP = 34, PAD = 14, FOOT = 40, IN = 8,
	LIST_W = 236, ROW = 34, HEAD = 22, RUN_ROW = 40,
	LEDGER_ROW = 28, LEDGER_MAX = 8, SPELL_ROW = 17, SPELLS_SHORT = 4,
	FACE = 24, FACE_X = 2, FACE_IN = 0.09, TEXT_UP = 4, GAP = 6, RAIL_DOWN = 7.5, SHARE = 3, SPELL_X = 160, SPELL_W = 110,
	TAB_W = 96, BUTTON = 32, ART = 26,
	GRAB = 56, CLOSE_X = 20, CLOSE_Y = 33, BRAND_MID = 17,
}
-- (the ledger's faces: the kit rim's whole-UI shade partner, the windows' area)
local FACE_OPTS = { shade = "windows" }

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
	spellsHead = "Your spells",
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

-- a string in its role (MelloUI.Look: "text", "gold", "note"): MelloUI's
-- font and the palette painted
local function Font(parent, size, role, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	Look.Text(fs, role or "text", size)
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	return fs
end

local function ClassColour(class)
	local QI = MelloUI.QuestInk
	if QI and QI.ClassColour then
		return QI.ClassColour(class)
	end
	return nil
end

-- a share in its player's class colour, out of the palette's repaint (else
-- the palette's gold)
local function ShareColour(tex, class)
	local r, g, b = ClassColour(class)
	if r then
		Kit:Unpaint(tex, "vertex")
		tex:SetVertexColor(r, g, b)
	else
		W.Paint(tex, "selectedTrim", "vertex")
	end
end

-- a class's face: its plain medallion (no diamonds; the kit's rim takes the
-- place of its own bronze ring, cut off with FACE_IN), else the question mark
local function FaceOf(class)
	local path = class and MelloUI.ClassIconPath and MelloUI:ClassIconPath(class, "plain")
	return path or UNKNOWN_ICON
end

-- a face's picture cut to the medallion inside its own ring (its round button's crop: MelloUI.Icons draws it)
local function CutFace(b)
	b:SetCrop(H.FACE_IN)
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

-- what the paper changes past the ink's walk (the surface's onRefresh: the
-- parchment switched, a lay; and Lay, a look switched): the body's edge
-- hidden under the paper's own torn edge (both looks); the shell's title, on
-- the paper in the modern look (the brand row heads the list column), in
-- dark ink as the rest (the painted look's title on its plate: plain)
local function Sheet(on)
	local body, sh = win.body, win.shell
	if not (body and sh) then
		return
	end
	local edges = body.panelEdges
	for i = 1, #edges do
		edges[i]:SetShown(not on)
	end
	local QI, title = MelloUI.QuestInk, sh.title
	if not (QI and QI.InkText and title) then
		return
	end
	if on and not sh.kit then
		QI.onSheet[title] = true
		QI.InkText(title)
	else
		QI.PlainText(title)
	end
end

local function Ink()
	local QI = MelloUI.QuestInk
	if not (QI and QI.Surface) then
		return
	end
	if not surfaceMade then
		surfaceMade = true
		QI.Surface(AREA, { on = InkOn, sheet = true, roots = InkRoots, onRefresh = Sheet })
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
	local sel = slot:CreateTexture(nil, "BACKGROUND")
	Look.Mark(sel, "selected", "selectedTab", 0.55)
	sel:SetAllPoints(slot)
	sel:Hide()
	slot.sel = sel
	local hover = slot:CreateTexture(nil, "BACKGROUND")
	Look.Mark(hover, "hover", "hover", 0.35)
	hover:SetAllPoints(slot)
	slot:SetHighlightTexture(hover)
	slot.name = Font(slot, 13, "text")
	slot.name:SetPoint("TOPLEFT", slot, "TOPLEFT", 8, -4)
	slot.name:SetPoint("RIGHT", slot, "RIGHT", -86, 0)
	slot.sub = Font(slot, 11, "note")
	slot.sub:SetPoint("TOPLEFT", slot.name, "BOTTOMLEFT", 0, -2)
	slot.sub:SetAlpha(0.8)
	slot.right = Font(slot, 12, "text", "RIGHT")
	slot.right:SetPoint("TOPRIGHT", slot, "TOPRIGHT", -8, -5)
	-- a run's head: small capitals in gold with a line after them
	slot.head = Font(slot, 11, "gold")
	slot.head:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", 4, 4)
	slot.line = Look.Solid(slot, "ARTWORK", "border", 1)
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
	-- the class's face in the kit's round rim (no lit state: yours is told by
	-- its gold "You"); its picture set by LayLedger when the class changes
	local face = W.RoundIcon(row, H.FACE, UNKNOWN_ICON, FACE_OPTS)
	face:SetKit(Kit)
	-- (click-through: W.RoundIcon's SetKit keeps a mouse turned off through
	-- the kit rim's mouse hooks, in either order)
	face:EnableMouse(false)
	CutFace(face)
	face:SetPoint("LEFT", row, "LEFT", H.FACE_X, 0)
	row.face = face
	-- the texts on one line over the row's middle
	row.name = Font(row, 13, "text")
	row.name:SetPoint("LEFT", face, "RIGHT", H.GAP, H.TEXT_UP)
	row.name:SetPoint("RIGHT", row, "RIGHT", -130, H.TEXT_UP)
	row.total = Font(row, 13, "text", "RIGHT")
	row.total:SetPoint("RIGHT", row, "RIGHT", -H.GAP, H.TEXT_UP)
	row.rate = Font(row, 11, "note", "RIGHT")
	row.rate:SetPoint("RIGHT", row.total, "LEFT", -10, 0)
	row.rate:SetAlpha(0.8)
	-- the rail under them: a hairline the top's whole width, this one's share
	-- of it on it (the status bars' Bar Texture, its class's colour)
	local track = W.Solid(row, "BACKGROUND", "border", 1)
	track:SetHeight(1)
	track:SetPoint("LEFT", face, "RIGHT", H.GAP, -H.RAIL_DOWN)
	track:SetPoint("RIGHT", row, "RIGHT", -H.GAP, -H.RAIL_DOWN)
	row.track = track
	local share = row:CreateTexture(nil, "ARTWORK")
	share:SetTexture(W.BarFill())
	share:SetHeight(H.SHARE)
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
	row.value:SetPoint("RIGHT", row, "RIGHT", -H.GAP, 0)
	-- the ledger's rail (the user's pick B: its dark outline of 2026-10-01
	-- went): the hairline as long as the best spell's, this one's share of it
	-- on it in trim
	local rail = W.Solid(row, "BACKGROUND", "border", 1)
	rail:SetHeight(1)
	rail:SetPoint("LEFT", row, "LEFT", H.SPELL_X, 0)
	row.rail = rail
	local bar = row:CreateTexture(nil, "ARTWORK")
	bar:SetTexture(W.BarFill())
	bar:SetHeight(H.SHARE)
	bar:SetPoint("LEFT", rail, "LEFT", 0, 0)
	W.Paint(bar, "trim", "vertex")
	row.bar = bar
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
	local width = H.SPELL_W
	local best = spells[1] and spells[1].a or 1
	for i = 1, n do
		local sp, row = spells[i], SpellRow(i)
		row.name:SetText(sp.n)
		local pct = total > 0 and floor(sp.a / total * 100 + 0.5) or 0
		row.value:SetText(Meter.Big(sp.a) .. "  " .. pct .. "%")
		local share = min(1, sp.a / max(best, 1))
		row.rail:SetWidth(width)
		row.bar:SetWidth(max(1, width * share))
		row.bar:SetTexCoord(0, share, 0, 1)   -- (the fill cut as a status bar's, not squeezed)
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
	-- (the rail: from the face's right GAP on to GAP short of the row's end)
	local width = max(1, (win.board:GetWidth() or 300) - (H.FACE_X + H.FACE + H.GAP) - H.GAP)
	local top = list[1] and list[1].value or 1
	for i = 1, n do
		local e, row = list[i], LedgerRow(i)
		row.name:SetText(i .. ".  " .. NameOf(e))
		Look.Tint(row.name, e.me and "gold" or nil)   -- (you in gold)
		row.total:SetText(Meter.Big(e.value))
		row.rate:SetText(TEXT.perSecond:format(Meter.Plain(e.rate)))
		-- (the picture set only when the row's class changes)
		local class = e.c or false
		if row.class ~= class then
			row.class = class
			row.face:SetIcon(FaceOf(e.c))
		end
		local share = min(1, e.value / max(top, 1))
		row.share:SetWidth(max(1, width * share))
		row.share:SetTexCoord(0, share, 0, 1)   -- (the fill cut as a status bar's, not squeezed)
		ShareColour(row.share, e.c)
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

-- your class (nil while it cannot be read)
local function MyClass()
	local ok, _, class = pcall(_G.UnitClass, "player")
	return ok and Text(class) or nil
end

-- the brand row's rim (the modern look's, made the first time it shows)
-- wears your class's face as the ledger's faces do: the plain medallion, its
-- own bronze ring cut off (the painted look's corner ring keeps the whole
-- medallion); without one, the shell's emblem stays (tried again at the
-- next lay: your class not read yet)
local function BrandFace(sh)
	local rim = sh.rim
	if not rim or win.brandFace == rim then
		return
	end
	local class = MyClass()
	local path = class and MelloUI.ClassIconPath and MelloUI:ClassIconPath(class, "plain")
	if path then
		win.brandFace = rim
		rim:SetIcon(path)
		CutFace(rim)
	end
end

-- the window's parts where the look puts them, at the build and at every
-- switch (shell:OnKit): the body on the shell's inset (the painted look's
-- own numbers under its corner ring and rail plate, the modern look's round
-- its brand column), the list under the brand row (the room shell:Brand
-- gave), the fight's name on the brand row's line, clear of the close; the
-- paper's parts (Sheet); then, while it shows, what is counted from the
-- inset's sizes laid again (the list's rows in view, the ledger's shares and
-- its room for your spells)
local function Lay(sh)
	local body, right, name = win.body, win.right, win.headName
	local edge, top = sh:Inset(H.PAD, -H.TOP)
	body:ClearAllPoints()
	body:SetPoint("TOPLEFT", win.frame, "TOPLEFT", edge, top)
	body:SetPoint("BOTTOMRIGHT", win.frame, "BOTTOMRIGHT", -edge, edge)
	local modern = not sh.kit
	local runRow = win.runRow
	runRow:ClearAllPoints()
	runRow:SetPoint("TOPLEFT", win.left, "TOPLEFT", 0, modern and -win.room or 0)
	runRow:SetPoint("RIGHT", win.left, "RIGHT", 0, 0)
	name:ClearAllPoints()
	if modern then
		-- (the close's right edge CLOSE_X in from the window's, the right
		-- column's IN in from the body's)
		local close = sh.close and Num(sh.close:GetWidth()) or 0
		local clear = max(4, H.CLOSE_X + close + H.GAP - (edge + H.IN))
		name:SetPoint("LEFT", right, "TOPLEFT", 2, -H.BRAND_MID)
		name:SetPoint("RIGHT", right, "TOPRIGHT", -clear, -H.BRAND_MID)
		BrandFace(sh)
	else
		name:SetPoint("TOPLEFT", right, "TOPLEFT", 2, -2)
		name:SetPoint("RIGHT", right, "RIGHT", -4, 0)
	end
	Sheet(InkOn())
	if win.frame:IsShown() then
		LayAll()
	end
end

-- the status bars' Bar Texture set or switched (W.BarFill): the shares and
-- the spells' bars take it
local function BarTexture()
	local fill = W.BarFill()
	for _, row in ipairs(win.ledger) do
		row.share:SetTexture(fill)
	end
	for _, row in ipairs(win.spellRows) do
		row.bar:SetTexture(fill)
	end
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
	local class = MyClass()
	win.shell = Kit:OwnWindow(f, {
		area = "config", ring = { at = "tl", texture = class and Meter.ClassIcon(class) or nil }, plate = "rail",
		title = TEXT.title, close = true, escape = true, fit = true, sounds = true,
		mover = { key = "MelloUIFightHistory", label = TEXT.title, page = "BarsMeters", default = Home },
		-- (the modern look: the brand row at the list column's head, the drag
		-- band the top GRAB, the close on the brand row's line)
		brand = { shape = "row", grab = -H.GRAB, close = { -H.CLOSE_X, -H.CLOSE_Y } },
	})
	-- the body: the own windows' panel, the meter's parchment on it while
	-- that is on (laid by Lay)
	local body = W.Panel(f)
	win.body = body
	if Kit.ParchmentSheet then
		Kit:ParchmentSheet(body, body, { rect = body, margin = 0, area = AREA, fine = true })
	end
	-- the left side: the list column, the brand row at its head (the modern
	-- look's; its room under the column's top)
	local left = CreateFrame("Frame", nil, body)
	left:SetPoint("TOPLEFT", body, "TOPLEFT", H.IN, -H.IN)
	left:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", H.IN, H.IN)
	left:SetWidth(H.LIST_W)
	win.left = left
	win.room = win.shell:Brand(left)
	local runRow = NewSlot(left)
	runRow:SetHeight(H.RUN_ROW)
	runRow.head:Hide()
	runRow.line:Hide()
	runRow.name:SetText(TEXT.thisRun)
	Look.Tint(runRow.name, "gold")
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
	win.count = Font(left, 11, "note")
	win.count:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 6, 12)
	win.clear = W.Button(left, TEXT.clear, 80, win.shell, { onClick = ClearClick })
	if MelloUI.QuestInk then
		MelloUI.QuestInk.noInk[win.clear] = true   -- (a plate of its own, as the tabs)
	end
	win.clear:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -4, 4)
	-- the line between the two sides
	local split = Look.Solid(body, "ARTWORK", "border", 1)
	split:SetWidth(1)
	split:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
	split:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 8, 0)
	-- the right side
	local right = CreateFrame("Frame", nil, body)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 18, 0)
	right:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -H.IN, H.IN)
	win.right = right
	win.headName = Font(right, 15, "gold")   -- (laid by Lay)
	win.headSub = Font(right, 11, "note")
	win.headSub:SetPoint("TOPLEFT", win.headName, "BOTTOMLEFT", 0, -3)
	win.tabs = {}
	local prev = nil
	for _, t in ipairs({ { "damage", TEXT.damage }, { "healing", TEXT.healing }, { "spells", TEXT.spells } }) do
		local tab = CreateFrame("Button", nil, right, "PanelTopTabButtonTemplate")
		-- (on its own dark plate: its label keeps the light text, never the
		-- parchment's ink -- the user, 2026-10-01: "these tabs are hard to read")
		if MelloUI.QuestInk then
			MelloUI.QuestInk.noInk[tab] = true
		end
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
	-- (the own windows' section heading: its title's middle 7 under the
	-- pane's top, where the old heading sat, so the rows keep their place)
	win.spellsHead = W.Header(spellPane, -7, TEXT.spellsHead, { x = 4 })
	win.spellsEmpty = Font(board, 12, "text")
	win.spellsEmpty:SetPoint("TOPLEFT", spellPane, "TOPLEFT", 4, -18)
	win.spellsEmpty:SetText(TEXT.noSpells)
	win.spellsEmpty:Hide()
	Lay(win.shell)
	win.shell:OnKit(Lay)
	W.OnBarTexture("statusbars", BarTexture, "Fight History bars")
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
	-- (0.25.0) the meter's button of MelloUI's icon set, its own disc and ring, the round gold light over it (a
	-- palette disc with the chart glyph until then)
	local art = button:CreateTexture(nil, "ARTWORK", nil, 1)
	art:SetSize(H.ART, H.ART)
	art:SetPoint("CENTER")
	W.Icon(art, "btn_meter")
	W.HoverLight(button, "round", art)
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
