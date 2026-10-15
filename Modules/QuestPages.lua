--------------------------------------------------------------------------------
-- MelloUI - Quest Pages
--
-- The quest log's and the Quest List's modern touches (0.24.0, the chat's
-- look: the user's picks 2A / 2B of BuildData/output/column_questlist_sketch,
-- 2026-10-15), core since onelook D8 and on for every player (the user,
-- 2026-10-15: the game's own background with MelloUI's headings, gems and
-- rims on it, no parchment under them):
--   * a section header (the log's and the Quests panel's) as the chat's
--     heading: its plate, its lit copy and its name faded, MelloUI's own name
--     over the game's in the title face (small caps; the header button puts
--     its own name back in its own font on hover: hard rule 1, cover, never
--     overwrite), the palette's gold, a hairline under it
--   * a quest title's difficulty as one gem just left of it (QI.RowGem)
--   * a Quests panel row's icon in the kit's round rim on a dark disc
-- The ink (dark text on the parchment) is the painted page's: QP.SetPaper,
-- which the painted quest log skin (QuestLogPanel, Oldschool's) calls with
-- its page, is the one writer of QI.onParchment.
-- Not a module: no switch, no setting, no option (a library, as QuestInk).
--
-- The game's quest log is dressed from its own update (QuestLogQuests_Update
-- rebuilds the list from pools under QuestScrollFrame.Contents): the rows in
-- the list's view at once, the rows out of it a few ms a frame after or as
-- the list scrolls (Rows out of view, below). The Quests panel (MelloUI's
-- own page) calls QP.Header and QP.Row as it lays a button.
--
-- Hard rule 1 (checked against the client's source, ui_src): the game never
-- calls SetAlpha on a header's plate, its highlight or its name
-- (QuestMapFrame.lua's one SetAlpha is its bottom shadow; the header pool's
-- reset is Hide and ClearAllPoints). It does recolour the log's name:
-- ListHeaderVisualMixin:CheckHighlightTitle, SetTextColor(r, g, b) from the
-- header's OnLoad, OnEnter and OnLeave (a quest log update only sets its
-- text), and a text colour sets the string's alpha back to 1 on this client,
-- a write Kit:Fade's hooks (SetAlpha, SetVertexColor) never see. The name is
-- faded again from its SetTextColor (GameName_OnSetTextColor): on a hover,
-- never per frame or per update, counted (MelloUI.Perf.WriteBack).
-- The Gamepad UI (0.15.0's freeze fix: the game's navigation walks every frame
-- in the open world map): while it is on and no painted page is, the game's
-- quest log gets no MelloUI frame (no gem frames on its rows; the headings are
-- regions) and none of its rows waits, so nothing of MelloUI's runs in the
-- log's scroll.
--
--   QP.Header(button, rect)  a header, the log's or the panel's (`rect`: where
--                            its plate lies): the chat's heading; its parts
--   QP.Row(button)           a Quests panel row: no heading, its icon in the rim
--   QP.SetPaper(on)          the painted page on / off: the log and the
--                            Quests panel inked / plain again
--   QP.Dresser(fn)           fn(row, kind) after each log row's own dressing
--                            ("title", "header", "objective"): the painted skin's
--   QP.kept                  read only: headingOf, rimOf, dressedOf, waitingKind
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
-- frames made in a game window: Core's maker, so the game's gamepad
-- navigation never walks an open window for each one (MelloUI.Safe.CreateFrame)
local CreateFrame = MelloUI.Safe.CreateFrame
local Perf = MelloUI.Perf:Scope("QuestPages")
local hooksecurefunc = Perf.hooksecurefunc
local Shared = Perf.Shared
-- a write back onto a game region, counted for /melloperf
local WriteBack = MelloUI.Perf.WriteBack or function() end
local Kit = MelloUI.Kit
-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number
local GamepadUI = MelloUI.Safe.GamepadUI

local QP = {}
MelloUI.QuestPages = QP

-- the Gamepad UI on and no painted page: no frame in the world map, no row waiting (above)
local function Lean()
	local QI = MelloUI.QuestInk
	return GamepadUI() and not (QI and QI.onParchment)
end
local lean = false   -- Lean(), read once per pass over the list
local titleSize = 12 -- the log's title font's size (QI.RowFonts), read once per pass: off the page the gem's size

-- the pass's reads (DressList, DressWaiting)
local function NewPass()
	lean = Lean()
	local QI = MelloUI.QuestInk
	titleSize = QI and QI.RowFonts(nil, nil) or 12
end

--------------------------------------------------------------------------------
-- The heading
--------------------------------------------------------------------------------

local headingOf = setmetatable({}, { __mode = "k" })   -- [header button] = { src, cover, hair, rect, off }

local function HeadingLook(button)
	local h = headingOf[button]
	if not h then
		return
	end
	-- (the Quests panel's done / total bar along the foot is the line there; a
	-- pooled panel button laid as a row shows no heading: QP.Row)
	local bar = button.progress
	local on = not h.off
	h.hair:SetShown(on and not (bar and bar:IsShown()))
	h.cover:SetShown(on)
	if not on then
		return
	end
	local text = h.src:GetText()
	h.cover:SetText((not Secret(text) and type(text) == "string") and text or "")
	local QI = MelloUI.QuestInk
	local paper = QI and QI.onParchment
	if paper then
		QI.Ink(h.cover, "title")
	else
		if QI then
			QI.Plain(h.cover)
		end
		MelloUI.Widgets.Paint(h.cover, "selectedTrim", "text")
	end
	-- the Quests panel's done / total on the paper in the faded ink (its
	-- palette colour off it: the panel's own, set as it lays the header)
	local count = button.count
	if count and QI then
		if paper then
			QI.Ink(count, "faded")
		else
			QI.Plain(count)
		end
	end
end

-- the cover's shadow: the game's string's own (its font object's), read
-- secret-safe; the palette's dark inner panel one unit right and down when
-- it cannot be read
local function CopyShadow(cover, src)
	local okC, r, g, b, a = pcall(src.GetShadowColor, src)
	local okO, x, y = pcall(src.GetShadowOffset, src)
	r, g, b, a = okC and Num(r), okC and Num(g), okC and Num(b), okC and Num(a)
	x, y = okO and Num(x), okO and Num(y)
	if r and g and b and x and y then
		cover:SetShadowColor(r, g, b, a or 1)
		cover:SetShadowOffset(x, y)
		return
	end
	local c = MelloUI.Palette.innerPanel
	cover:SetShadowColor(c[1], c[2], c[3], 1)
	cover:SetShadowOffset(1, -1)
end

-- the log's name recoloured by the game (its hover: hard rule 1, above):
-- faded again while it is faded. One handler for every header
local GameName_OnSetTextColor = Shared("QuestPages: the log's name recoloured", function(fs)
	if Kit.faded[fs] then
		WriteBack("QuestPages: the log's faded name's alpha put back to 0")
		fs:SetAlpha(0)
	end
end)

local function Heading(button, rect)
	local h = headingOf[button]
	if h then
		return h
	end
	-- the name: the panel's own label, the log's ButtonText
	local src = button.label or button.ButtonText or (button.GetFontString and button:GetFontString())
	local W = MelloUI.Widgets
	if not (src and W and W.Solid) then
		return nil
	end
	h = { src = src, rect = rect or button }
	-- the hairline first: a world whose widgets are stand-ins makes none, and no heading then (nothing made per call)
	local hair = W.Solid(button, "ARTWORK", "border")
	if not hair then
		return nil
	end
	hair:SetHeight(1)
	hair:SetPoint("BOTTOMLEFT", h.rect, "BOTTOMLEFT", 0, 1)
	hair:SetPoint("BOTTOMRIGHT", h.rect, "BOTTOMRIGHT", 0, 1)
	h.hair = hair
	local cover = button:CreateFontString(nil, "OVERLAY")
	local ok, path, size, flags = pcall(src.GetFont, src)
	if ok and path and size and not (Secret(path) or Secret(size)) then
		cover:SetFont(path, size, flags or "")
	else
		cover:SetFontObject(GameFontNormal)
	end
	CopyShadow(cover, src)
	cover:SetJustifyH("LEFT")
	cover:SetWordWrap(false)
	cover:SetPoint("LEFT", src, "LEFT", 0, 0)
	cover:SetPoint("RIGHT", src, "RIGHT", 0, 0)
	Kit:TitleFont(cover, true)
	local QI = MelloUI.QuestInk
	if QI and QI.WatchColour then
		QI.WatchColour(cover)   -- (a palette switch's gold inked over at once on the paper)
	end
	h.cover = cover
	headingOf[button] = h
	-- (the log's name comes with the header's SetText, QuestLogQuests_
	-- SetupStandardHeaderButton's caller; the panel's as it lays the header.
	-- The log's name's colour comes with its hover: faded again, above)
	if not button.label and button.SetText then
		hooksecurefunc(button, "SetText", HeadingLook)
		if src.SetTextColor then
			hooksecurefunc(src, "SetTextColor", GameName_OnSetTextColor)
		end
	end
	return h
end

--------------------------------------------------------------------------------
-- The rim (0.24.0, the user's pick 2B): a Quests panel row's icon (the !, the
-- ?, a tick, what a quest begins from) in the kit's round rim on a dark disc,
-- as the Quest Tracker's marks and the chat's tabs: the rim (Kit:Slot, every
-- window's Round Border) on a small frame where the panel lays its icon
-- (QI.ROW's icon column, on the title's line), the icon in its opening, the
-- disc under it. The log's own rows keep the game's map buttons.
--------------------------------------------------------------------------------

local rimOf = setmetatable({}, { __mode = "k" })   -- [Quests panel row] = { holder, rim, disc }
local RIM = 20   -- the rim: the log's map button's size (POIButtonTemplate)
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"   -- (a round white: W.GlyphButton's disc)

local function RowRim(button, isRow)
	local r = rimOf[button]
	local icon = button.check
	if not (isRow and icon and icon:IsShown()) then
		if r then
			r.holder:Hide()
			r.disc:Hide()
		end
		return
	end
	if not r then
		local holder = CreateFrame("Frame", nil, button)
		holder:SetSize(RIM, RIM)
		holder:EnableMouse(false)
		local disc = button:CreateTexture(nil, "BORDER", nil, 6)
		disc:SetTexture(DISC)
		MelloUI.Widgets.Paint(disc, "innerPanel", "vertex", 0.95)
		r = { holder = holder, disc = disc, rim = Kit:Slot(holder, { kind = "roundslot", icon = icon }) }
		rimOf[button] = r
	end
	local ROW = MelloUI.QuestInk and MelloUI.QuestInk.ROW
	local ok, _, ts = pcall(button.title.GetFont, button.title)
	ts = ok and Num(ts) or 12
	r.holder:ClearAllPoints()
	r.holder:SetPoint("CENTER", button, "TOPLEFT", ROW and ROW.iconX or 16, -((ROW and ROW.top or 8) + ts / 2))
	r.holder:Show()
	Kit:SlotPlaceIcon(r.rim)
	r.disc:ClearAllPoints()
	r.disc:SetAllPoints(icon)
	r.disc:Show()
end

-- A section header, the log's (QuestLogHeaderTemplate = ListHeaderVisualTemplate)
-- or the Quests panel's (`rect`: its plate's place, as far right of its rows
-- as the log's): the chat's heading over it; its plate, the plate's additive
-- highlight and the game's name faded (nothing stands in: the heading is the
-- look). A pooled panel button laid as a header drops its rim. The name's
-- owner colours it no more once it is faded (the panel: its label): a text
-- colour with an alpha sets the string's alpha on this client, which no hook
-- of Kit:Fade sees. Returns the heading (nil: none made, the name stays).
function QP.Header(button, rect)
	local normal = button.GetNormalTexture and button:GetNormalTexture()
	if not normal then
		return nil
	end
	Kit:Fade(normal)
	local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
	if highlight then
		Kit:Fade(highlight)
	end
	local h = Heading(button, rect)
	if h then
		h.off = nil
		Kit:Fade(h.src)
		HeadingLook(button)
	end
	RowRim(button, false)
	return h
end

-- A Quests panel row (the pool's buttons serve as headers and rows): a
-- heading it carried as a header hidden, its icon in the round rim
function QP.Row(button)
	local h = headingOf[button]
	if h then
		h.off = true
		HeadingLook(button)
	end
	RowRim(button, true)
end

--------------------------------------------------------------------------------
-- The ink and the gem. On the painted page (QI.onParchment) the quest titles
-- and objectives are dark ink (QuestInk; user, 2026-09-23); the game colours
-- them on each update and the colour it gave an objective (grey once done) is
-- watched, so inking again never mistakes our own ink for it. Off the page
-- the game's colours. The log's rows are the one quest row the Quests panel
-- lays too (QuestInk's Quest rows): on the page the same fonts on the title
-- and the line under it (QI.RowFonts). The difficulty (0.24.0, the user's
-- pick 2A): one gem before the title, as the Quests panel's and the Quest
-- Tracker's (QI.RowGem), in the slot the game keeps left of its title for its
-- own task icon (QuestLogTitleTemplate's TaskIcon).
--------------------------------------------------------------------------------

local function QuestLevel(questID)
	local log = C_QuestLog
	if not (questID and log and log.GetLogIndexForQuestID and log.GetInfo) then
		return nil
	end
	local ok, index = pcall(log.GetLogIndexForQuestID, questID)
	index = ok and Num(index)
	if not index then
		return nil
	end
	local okI, info = pcall(log.GetInfo, index)
	if not okI or Secret(info) or type(info) ~= "table" then
		return nil
	end
	return Num(info.difficultyLevel) or Num(info.level)
end

-- an objective's ink from the game's colour: grey once done (a secret colour: the text's ink)
local function ObjectiveRole(r)
	r = Num(r)
	return (r and r < 0.8) and "faded" or "text"
end

local function InkTitle(QI, title)
	local fs = title.Text
	if not fs then
		return
	end
	local paper = QI.onParchment
	-- (the client's relative difficulty first; the level's colour only when it says nothing)
	local qid = Num(title.questID)
	local tier = nil
	if not lean then
		tier = QI.TierForQuest(qid, nil) or QI.Tier(QuestLevel(qid))
	end
	-- (on the page the title takes the shared row's font; off it the game's stays)
	local ts = paper and QI.RowFonts(fs, nil) or titleSize
	if paper then
		QI.WatchColour(fs)
		QI.Ink(fs, tier == 1 and "faded" or "title")
	else
		-- (the game's colour written back once, as the ink goes)
		local was = QI.inkOn[fs]
		QI.Plain(fs)
		if was then
			fs:SetTextColor(QI.GameColour(fs))
		end
	end
	QI.RowGem(title, fs, ts, tier)
end

-- (an objective's bullet is a string of its own, the Dash, in ObjectiveFont's
-- light grey, which the game never colours: inked as the line after it, as
-- the Quests panel's bullet is, its own grey back off the page)
local function InkObjective(QI, objective)
	local fs, dash = objective.Text, objective.Dash
	if not fs then
		return
	end
	if QI.onParchment then
		QI.WatchColour(fs, ObjectiveRole)
		local role = ObjectiveRole(QI.GameColour(fs))
		QI.RowFonts(nil, fs)
		QI.Ink(fs, role)
		if dash then
			QI.RowFonts(nil, dash)
			QI.Ink(dash, role)
		end
	elseif QI.inkOn[fs] then
		QI.Plain(fs)
		fs:SetTextColor(QI.GameColour(fs))
		QI.Plain(dash, true)
	end
end

--------------------------------------------------------------------------------
-- Rows out of view (/melloperf, user 2026-09-24: the first map open dressed
-- the whole quest log in one QuestLogQuests_Update -- 8.8 ms). A row is
-- dressed in the update only when it lies in the list's view (the scroll
-- frame's rect) or was dressed before (since the last SetPaper); the rows
-- below or above it wait, and are dressed a few ms per frame after, or at
-- once as the list scrolls, changes size or shows, before they can be seen.
-- One scheduler for the core's dressing and the painted skin's (QP.Dresser).
--------------------------------------------------------------------------------

local ROW_BUDGET = 2   -- ms of waiting rows per frame
local waiting = {}     -- the rows waiting, in the list's order (a row no longer waiting is passed over)
local waitingKind = setmetatable({}, { __mode = "k" })   -- [row] = "title" | "header" | "objective" while it waits
local waitAt = 1
local rowsFrame = nil  -- the waiting rows' OnUpdate: made when a row first waits (nothing at login)
local rowsTicking = false
local dressers = {}    -- QP.Dresser's
local gen = 1          -- the dressing's generation: a SetPaper dresses every row again
local dressedOf = setmetatable({}, { __mode = "k" })   -- [row] = the generation it was last dressed in
local hooked = false

-- The list's view: its top and bottom; false while it cannot be seen (every
-- new row waits); nil when its rect cannot be read (every row counts as seen)
local function ListView(sf)
	if not sf:IsVisible() then
		return false
	end
	local okT, top = pcall(sf.GetTop, sf)
	local okB, bottom = pcall(sf.GetBottom, sf)
	top, bottom = okT and Num(top), okB and Num(bottom)
	if top and bottom then
		return top, bottom
	end
	return nil
end

local function InView(row, top, bottom)
	if top == false then
		return false
	elseif top == nil then
		return true
	end
	local okT, t = pcall(row.GetTop, row)
	local okB, b = pcall(row.GetBottom, row)
	t, b = okT and Num(t), okB and Num(b)
	if not (t and b) then
		return true
	end
	return b < top and t > bottom
end

-- a row's whole dressing, as the list's update gives it
local function DressRow(row, kind)
	local QI = MelloUI.QuestInk
	if kind == "title" then
		InkTitle(QI, row)
	elseif kind == "header" then
		QP.Header(row)
	else
		InkObjective(QI, row)
	end
	for i = 1, #dressers do
		dressers[i](row, kind)
	end
	dressedOf[row] = gen
end

local DressWaiting   -- below

local function RowsTick()
	DressWaiting(ROW_BUDGET)
end

-- the list scrolled, sized or shown: the waiting rows it shows now, at once
local function DressShown()
	if waiting[waitAt] then
		DressWaiting(nil, true)
	end
end

local function Wait(row, kind)
	if waitingKind[row] then
		return
	end
	waitingKind[row] = kind
	waiting[#waiting + 1] = row
	if rowsTicking then
		return
	end
	rowsTicking = true
	if not rowsFrame then
		rowsFrame = CreateFrame("Frame")
		-- (the list's scroll, size and show hooked with it: never while no row
		-- ever waited -- the Gamepad UI's, above)
		local sf = QuestScrollFrame
		if sf and sf.HookScript then
			Perf.HookScript(sf, "OnVerticalScroll", DressShown)
			Perf.HookScript(sf, "OnSizeChanged", DressShown)
			Perf.HookScript(sf, "OnShow", DressShown)
		end
	end
	Perf.SetScript(rowsFrame, "OnUpdate", RowsTick)
end

-- The waiting rows dressed: those in the list's view now (`inView`), or
-- (`budget`, in ms) in order until that much time has gone, or all of them.
-- A row the list no longer shows (released to its pool) is passed over:
-- the update that shows it again decides for it.
DressWaiting = function(budget, inView)
	NewPass()
	local top, bottom
	if inView then
		top, bottom = ListView(QuestScrollFrame)
	end
	local t0 = budget and debugprofilestop()
	local i = inView and 1 or waitAt
	while i <= #waiting do
		local row = waiting[i]
		local kind = waitingKind[row]
		if not inView then
			waitAt = i + 1
		end
		if kind and (not inView or InView(row, top, bottom)) then
			waitingKind[row] = nil
			if row:IsShown() then
				DressRow(row, kind)
			end
		end
		i = i + 1
		if budget and debugprofilestop() - t0 >= budget then
			break
		end
	end
	if waitAt > #waiting then
		for n = #waiting, 1, -1 do
			waiting[n] = nil
		end
		waitAt = 1
		rowsTicking = false
		Perf.SetScript(rowsFrame, "OnUpdate", nil)
	end
end

-- one pool's rows: dressed now (in view, or dressed before), or waiting
local function DressPool(pool, kind, top, bottom)
	if not pool then
		return
	end
	for row in pool:EnumerateActive() do
		if dressedOf[row] ~= gen and not InView(row, top, bottom) then
			Wait(row, kind)
		else
			waitingKind[row] = nil
			DressRow(row, kind)
		end
	end
end

-- The game's list after its update (QuestLogQuests_Update) and as its page
-- shows: every row the list shows (lean: all of them at once)
local function DressList()
	local sf = QuestScrollFrame
	if not (sf and sf.titleFramePool and MelloUI.QuestInk) then
		return
	end
	NewPass()
	local top, bottom = nil, nil
	if not lean then
		top, bottom = ListView(sf)
	end
	DressPool(sf.headerFramePool, "header", top, bottom)
	DressPool(sf.titleFramePool, "title", top, bottom)
	DressPool(sf.objectiveFramePool, "objective", top, bottom)
end

-- fn(row, kind) after each log row's own dressing, once per fn (the painted
-- skin's hover plates, tick boxes and +/- glyphs: on the same rows, at the
-- same time)
function QP.Dresser(fn)
	for i = 1, #dressers do
		if dressers[i] == fn then
			return
		end
	end
	dressers[#dressers + 1] = fn
end

-- The painted page on or off (QuestLogPanel's Activate / Deactivate): the ink
-- follows over the log (every row dressed again: the ones in view at once, the
-- rest as at the first open), the headings and the Quests panel (laid again)
function QP.SetPaper(on)
	local QI = MelloUI.QuestInk
	if not QI then
		return
	end
	QI.onParchment = on and true or false
	gen = gen + 1
	DressList()
	for button in pairs(headingOf) do
		HeadingLook(button)
	end
	local ql = MelloUI.QuestList
	if ql and ql.Panel and ql.Panel.frame and ql.Panel.Update then
		pcall(ql.Panel.Update, ql.Panel)
	end
end

--------------------------------------------------------------------------------
-- The hooks: the log's update and its page's show (the world map and the
-- quest log load with the UI, before any addon: Blizzard_WorldMap is not
-- load-on-demand; a world without them waits for the login)
--------------------------------------------------------------------------------
local function Hook()
	if hooked or not (WorldMapFrame and QuestMapFrame) then
		return
	end
	hooked = true
	Perf.HookScript(QuestMapFrame, "OnShow", DressList)
	if type(QuestLogQuests_Update) == "function" then
		hooksecurefunc("QuestLogQuests_Update", DressList)
	end
end

if WorldMapFrame and QuestMapFrame then
	Hook()
else
	local waitFrame = CreateFrame("Frame")
	waitFrame:RegisterEvent("PLAYER_LOGIN")
	Perf.SetScript(waitFrame, "OnEvent", function(self)
		self:UnregisterAllEvents()
		Hook()
	end)
end

-- What this file keeps beside the game's frames (hard rule 1: weak-keyed
-- tables, never keys on the frames), for the dumps and the tests: read only
QP.kept = { headingOf = headingOf, rimOf = rimOf, dressedOf = dressedOf, waitingKind = waitingKind }
