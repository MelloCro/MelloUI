--------------------------------------------------------------------------------
-- MelloUI - the configurator's Addons page (2.1.44; the user, 2026-11-11: "focus on other addon integration from
-- now on", "a compatibility tab with all compatible addons and a link for them"; the sketch
-- BuildData/output/addons_page_sketch, "Looks good"). Its three tabs' content, from MelloUI.Integrations (the one
-- list: Core/Integrations.lua); the page, its header and tabs are the configurator's (Core/Config.lua's
-- CONFIG.BuildAddonsPage). Made on its first open, like every page; laid again (its live parts) at each show.
--   Installed      a card per installed addon: its name, version and state (Working, Partly, Off), Use with MelloUI
--                  (the one setting here), what MelloUI does with it, its settings in MelloUI (buttons that open
--                  them where they live), what MelloUI changed in it once (each with Switch back on)
--   Compatibility  every addon MelloUI works with, by group: what MelloUI does, its link (the configurator opens no
--                  web page: a box to copy it from), Installed on the ones loaded; the request channel's link
--   Who does what  the jobs two addons could both do, and which one does each now (I.Jobs)
--   AP.Installed(sec, width, skin, ctx) / AP.Compatibility(sec, width, skin) / AP.Jobs(sec, width, skin) -> height
--     ctx: Jump(id) (a setting's place), OpenMapLayers()
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local W = MelloUI.Widgets
local Perf = MelloUI.Perf:Scope("AddonsPage")
local I = MelloUI.Integrations

local AP = {}
MelloUI.AddonsPage = AP

local T = {
	PAD = 14,         -- a card's inside, left and right
	HEAD_H = 44,      -- a card's head row
	ICON = 24,
	GAP = 14,         -- between cards
	LINE = 4,         -- after a line of text
	BUTTON_H = 22,
	ROW_H = 34,       -- a changed setting's row, a job's, a compatible addon's
	LINK_W = 290,     -- the Compatibility tab's link column
	NAME_W = 184,     -- its addon column
	NEW = "2.1.44",
}
AP.T = T
local ICONS = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Icons\\"
local ICON_OF = { Questie = "quest_mark", RestedXP = "track_todo", Zygor = "track_todo", Polestar = "track_todo",
	TomTom = "arrow_player", RareScanner = "kill_rare", GatherMate2 = "pin_collect", HandyNotes = "page_map",
	NodeSight = "page_minimap", Lueur = "page_minimap", Clique = "page_frames" }

local TEXT = {
	use = "Use with MelloUI",
	does = "What MelloUI does with it",
	settings = "Its settings in MelloUI",
	changed = "Changed in %s",
	wasOff = "switched off once",
	wasOn = "switched on again",
	back = "Switch back on",
	working = "Working", partly = "Partly", off = "Off",
	partlyLine = "MelloUI could not read %s: that part is off until a MelloUI update catches up. The rest works.",
	offLine = "Switched off: MelloUI leaves it alone (after a /reload).",
	noSwitch = "Nothing to switch: MelloUI only keeps out of its way.",
	none = "None of the addons MelloUI works with is installed. The Compatibility tab lists them, with their links.",
	more = "More addons MelloUI works with, with their links: the Compatibility tab.",
	compat = "Addons MelloUI works with",
	colAddon = "Addon", colDoes = "What MelloUI does with it", colLink = "Link (click it, then Ctrl+C)",
	installed = "Installed",
	missing = "Missing one?",
	ask = "Ask for it in the addon requests channel on MelloUI's Discord:",
	jobs = "Who does what",
	colJob = "Job", colBy = "Done by",
}
AP.TEXT = TEXT
AP.DISCORD = "https://discord.com/channels/1552056753833648140/1570155693305110558"

local function Tr(s)
	return MelloUI.Lang.T(s)
end

local function Height(fs, least)
	local h = fs:GetStringHeight()
	h = type(h) == "number" and h or 0
	return math.max(least or 12, math.floor(h + 0.5))
end

-- a 1 px line across a panel, at y from its top
local function Rule(parent, y)
	local t = W.Solid(parent, "ARTWORK", "border", 0.7)
	t:SetHeight(1)
	t:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -y)
	t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -y)
	return t
end

-- a heading with the gold line (W.Header), at y; -> y under it
local function Heading(parent, y, text)
	W.Header(parent, y, text, { inset = 4 })
	return y + W.HEADER_HEIGHT + 2
end

--------------------------------------------------------------------------------
-- The state pill: a dot and a word in the state's meaning colour, in a rim of it
--------------------------------------------------------------------------------

local STATE = { working = "addonWorking", partly = "addonPartly" }

local function Tint(shape, c)
	local Painter = MelloUI.Painter
	for _, t in ipairs(shape.discs) do
		Painter.Unpaint(t)
		t:SetVertexColor(c[1], c[2], c[3], 1)
	end
	for _, t in ipairs(shape.rects) do
		Painter.Unpaint(t)
		t:SetColorTexture(c[1], c[2], c[3], 1)
	end
end

local function Pill(parent)
	local p = CreateFrame("Frame", nil, parent)
	p:SetSize(70, 18)
	p.plate = W.RoundPlate(p, { shape = "pill", fill = "innerPanel", edge = "border" })
	p.dot = p:CreateTexture(nil, "ARTWORK")
	p.dot:SetSize(5, 5)
	p.dot:SetPoint("LEFT", p, "LEFT", 7, 0)
	p.dot:SetTexture("Interface\\Buttons\\WHITE8X8")
	p.text = W.Text(p, "GameFontHighlightSmall")
	p.text:SetPoint("LEFT", p.dot, "RIGHT", 4, 0)
	return p
end

-- a state's look: its meaning colour (working, partly), else the palette's muted (off: painted by key, so a new
-- palette paints it again)
local function PillShow(p, state)
	local key = STATE[state]
	local c = key and MelloUI.Meaning[key]
	p.text:SetText(Tr(TEXT[state] or TEXT.off))
	local Painter = MelloUI.Painter
	if c then
		Painter.Unpaint(p.text)
		Painter.Unpaint(p.dot)
		p.text:SetTextColor(c[1], c[2], c[3], 1)
		p.dot:SetVertexColor(c[1], c[2], c[3], 1)
		Tint(p.plate.edgeShape, c)
	else
		W.Paint(p.text, "text", "text")   -- (muted text is never small text: the dot says it)
		W.Paint(p.dot, "mutedText", "vertex")
		p.plate:Paint("innerPanel", "border")
	end
	p:SetWidth(math.floor((p.text:GetStringWidth() or 30) + 0.5) + 22)
end

--------------------------------------------------------------------------------
-- The link box: the address to copy (the configurator opens no web page); the short form shown, the whole one
-- selected while it has the focus
--------------------------------------------------------------------------------

local function Short(url)
	return (url:gsub("^https?://", ""):gsub("^www%.", ""))
end

local LinkFocus = Perf.Shared("OnEditFocusGained on the Addons page's links", function(box)
	box:SetText(box.melloUrl)
	box:HighlightText()
end, "script")
local LinkLost = Perf.Shared("OnEditFocusLost on the Addons page's links", function(box)
	box:HighlightText(0, 0)
	box:SetText(Short(box.melloUrl))
	box:SetCursorPosition(0)
end, "script")
local LinkTyped = Perf.Shared("OnTextChanged on the Addons page's links", function(box, typed)
	if typed then   -- (read only: the address again, selected)
		box:SetText(box.melloUrl)
		box:HighlightText()
	end
end, "script")
local LinkDone = Perf.Shared("OnEscapePressed on the Addons page's links", function(box)
	box:ClearFocus()
end, "script")

local function LinkBox(parent, url, width)
	local frame = W.Box(parent, "innerPanel", "border")
	frame:SetSize(width, T.BUTTON_H)
	local box = CreateFrame("EditBox", nil, frame)
	box:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, 0)
	box:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 0)
	box:SetAutoFocus(false)
	box:SetFontObject(W.FontObject("GameFontHighlight"))
	box.melloUrl = url
	box:SetText(Short(url))
	box:SetCursorPosition(0)
	Perf.SetScript(box, "OnEditFocusGained", LinkFocus)
	Perf.SetScript(box, "OnEditFocusLost", LinkLost)
	Perf.SetScript(box, "OnTextChanged", LinkTyped)
	Perf.SetScript(box, "OnEscapePressed", LinkDone)
	Perf.SetScript(box, "OnEnterPressed", LinkDone)
	frame.box = box
	return frame
end
AP.LinkBox = LinkBox

--------------------------------------------------------------------------------
-- Installed: a card each
--------------------------------------------------------------------------------

local JumpClick = Perf.Shared("OnClick on the Addons page's settings buttons", function(b)
	local ctx = b.melloCtx
	if not ctx then
		return
	end
	if b.melloMap then
		ctx.OpenMapLayers()
	else
		ctx.Jump(b.melloId)
	end
end, "script")

local UndoClick = Perf.Shared("OnClick on the Addons page's Switch back on", function(b)
	MelloUI:PlayUISound("click")
	local fix = b.melloFix
	if fix and fix.Undo then
		pcall(fix.Undo)
	end
	if b.melloCard and b.melloCard.Refresh then
		b.melloCard.Refresh()
	end
end, "script")

-- the bullets: a trim square and the line, wrapped; -> y under them
local function Lines(card, y, lines, width)
	for _, line in ipairs(lines) do
		local dot = W.Solid(card, "ARTWORK", "trim", 1)
		dot:SetSize(4, 4)
		dot:SetPoint("TOPLEFT", card, "TOPLEFT", T.PAD + 6, -(y + 6))
		local fs = W.Text(card, "GameFontHighlight", Tr(line), "text")
		fs:SetWordWrap(true)
		fs:SetWidth(width - T.PAD * 2 - 24)
		fs:SetPoint("TOPLEFT", card, "TOPLEFT", T.PAD + 18, -y)
		y = y + Height(fs) + T.LINE
	end
	return y
end

local function Card(parent, e, width, skin, ctx)
	local card = W.Panel(parent)
	card:SetWidth(width)
	-- the head: icon, name, version, state; the switch on the right
	local icon = card:CreateTexture(nil, "ARTWORK")
	icon:SetSize(T.ICON, T.ICON)
	icon:SetPoint("TOPLEFT", card, "TOPLEFT", T.PAD, -10)
	MelloUI.Icons.Set(icon, ICONS .. (ICON_OF[e.key] or "svc_addons"), T.ICON)
	local name = W.Text(card, "GameFontHighlightLarge", Tr(e.name), "text")
	name:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	local version = W.Text(card, "GameFontHighlight", I.Version(e) or "", "text")
	version:SetAlpha(0.75)
	version:SetPoint("BOTTOMLEFT", name, "BOTTOMRIGHT", 6, 1)
	local pill = Pill(card)
	pill:SetPoint("LEFT", version, "RIGHT", 10, 0)
	card.pill = pill
	local y = T.HEAD_H
	if e.switch ~= false then
		card.new = "2.1.44"   -- (Use with MelloUI, below: new in this update)
		local sw = W.Switch(card, function()
			return I.Use(e.key)
		end, function(on)
			I.SetUse(e.key, on)
			if card.Refresh then
				card.Refresh()
			end
		end)
		sw:SetPoint("TOPRIGHT", card, "TOPRIGHT", -T.PAD, -9)
		card.switch = sw
		local label = W.Text(card, "GameFontHighlight", Tr(TEXT.use), "text")
		label:SetPoint("RIGHT", sw, "LEFT", -8, 0)
	end
	Rule(card, y - 2)
	-- the state's own line (Partly, Off, or nothing to switch)
	local note = W.Text(card, "GameFontHighlight", "", "text")
	note:SetWordWrap(true)
	note:SetWidth(width - T.PAD * 2)
	note:SetPoint("TOPLEFT", card, "TOPLEFT", T.PAD + 4, -(y + 6))
	card.note = note
	local noteY = y
	y = y + 6
	card.afterNote = y
	-- the rest under the note: laid again when the note's height changes (Refresh)
	local body = CreateFrame("Frame", nil, card)
	body:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -y)
	body:SetWidth(width)
	local by = 4
	by = Heading(body, by, TEXT.does)
	by = Lines(body, by, e.does, width)
	if #e.links > 0 then
		by = Heading(body, by + 4, TEXT.settings)
		local x = T.PAD + 4
		for _, link in ipairs(e.links) do
			local b = W.Button(body, Tr(link[1]), 60, skin, { onClick = JumpClick })
			W.FitButton(b)
			b:SetWidth(math.max(60, (b:GetFontString():GetStringWidth() or 40) + 22))
			local bw = b:GetWidth()
			if x + bw > width - T.PAD then
				x, by = T.PAD + 4, by + T.BUTTON_H + 6
			end
			b:SetPoint("TOPLEFT", body, "TOPLEFT", x, -by)
			b.melloCtx, b.melloId, b.melloMap = ctx, link.id, link.map
			x = x + bw + 8
		end
		by = by + T.BUTTON_H + 8
	end
	-- what MelloUI changed in it once
	local fixes = I.Changed(e)
	card.fixRows = {}
	if #fixes > 0 then
		by = Heading(body, by + 2, MelloUI.Lang.F(TEXT.changed, Tr(e.name)))
		for _, fix in ipairs(fixes) do
			local label = W.Text(body, "GameFontHighlight", Tr(fix.label), "text")
			label:SetPoint("TOPLEFT", body, "TOPLEFT", T.PAD + 4, -(by + 8))
			local state = W.Text(body, "GameFontHighlight", "", "text")
			state:SetAlpha(0.75)
			state:SetPoint("LEFT", label, "RIGHT", 10, 0)
			local b = W.Button(body, Tr(TEXT.back), 110, skin, { onClick = UndoClick })
			b:SetPoint("TOPRIGHT", body, "TOPRIGHT", -T.PAD, -(by + 4))
			b.melloFix, b.melloCard = fix, card
			Rule(body, by + T.ROW_H - 2)
			card.fixRows[#card.fixRows + 1] = { label = fix.label, state = state, button = b }
			by = by + T.ROW_H
		end
	end
	body:SetHeight(by + 6)
	card.body = body
	-- the live parts: the state and its line, the switch, the fixes' states (each show of the page)
	function card.Refresh()
		local state, why = I.Status(e)
		PillShow(pill, state)
		local line
		if e.switch == false then
			line = Tr(TEXT.noSwitch)
		elseif state == "partly" then
			line = MelloUI.Lang.F(TEXT.partlyLine, why or "")
		elseif state == "off" then
			line = Tr(TEXT.offLine)
		end
		note:SetText(line or "")
		local c = state == "partly" and MelloUI.Meaning.addonPartly or nil
		if c then
			MelloUI.Painter.Unpaint(note)
			note:SetTextColor(c[1], c[2], c[3], 1)
		else
			W.Paint(note, "text", "text")
		end
		local nh = line and (Height(note) + 8) or 0
		body:ClearAllPoints()
		body:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -(card.afterNote + nh))
		if card.switch then
			card.switch:Refresh()
		end
		local now = {}
		for _, fix in ipairs(I.Changed(e)) do
			now[fix.label] = fix
		end
		for _, row in ipairs(card.fixRows) do
			local fix = now[row.label]
			row.state:SetText(Tr((fix and fix.off) and TEXT.wasOff or TEXT.wasOn))
			row.button.melloFix = fix
			row.button:SetShown(fix ~= nil and fix.off and true or false)
		end
		card:SetHeight(card.afterNote + nh + body:GetHeight())
		return card:GetHeight()
	end
	card.noteY = noteY
	return card
end

function AP.Installed(sec, width, skin, ctx)
	local cards = {}
	for _, e in ipairs(I.LIST) do
		if I.Installed(e) then
			cards[#cards + 1] = Card(sec, e, width, skin, ctx)
		end
	end
	local tail = W.Text(sec, "GameFontHighlight", Tr(#cards > 0 and TEXT.more or TEXT.none), "text")
	tail:SetAlpha(0.75)
	tail:SetWordWrap(true)
	tail:SetWidth(width - 8)
	local function Lay()
		local y = 0
		for _, card in ipairs(cards) do
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, -y)
			y = y + card.Refresh() + T.GAP
		end
		tail:ClearAllPoints()
		tail:SetPoint("TOPLEFT", sec, "TOPLEFT", 4, -y)
		return y + Height(tail) + 4
	end
	sec.addonCards = cards
	sec.refreshers[#sec.refreshers + 1] = function()
		sec.y = Lay()
		sec:Finish()
	end
	return Lay()
end

--------------------------------------------------------------------------------
-- Compatibility: every addon, by group, with its link
--------------------------------------------------------------------------------

function AP.Compatibility(sec, width, skin)
	local box = W.Panel(sec)
	box:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, 0)
	box:SetWidth(width)
	local y = Heading(box, 8, TEXT.compat)
	local doesX, linkX = T.PAD + T.NAME_W, width - T.PAD - T.LINK_W
	for _, col in ipairs({ { TEXT.colAddon, T.PAD + 4 }, { TEXT.colDoes, doesX }, { TEXT.colLink, linkX } }) do
		local fs = W.Text(box, "GameFontHighlight", Tr(col[1]), "text")
		fs:SetAlpha(0.75)
		fs:SetPoint("TOPLEFT", box, "TOPLEFT", col[2], -y)
	end
	y = y + 22
	local marks = {}
	for _, g in ipairs(I.GROUPS) do
		Rule(box, y)
		local head = W.Text(box, "GameFontNormal", Tr(g.name), "selectedTrim")
		head:SetPoint("TOPLEFT", box, "TOPLEFT", T.PAD + 4, -(y + 8))
		y = y + 30
		for _, e in ipairs(I.LIST) do
			if e.group == g.key then
				Rule(box, y - 2)
				local name = W.Text(box, "GameFontHighlight", Tr(e.name), "text")
				name:SetPoint("TOPLEFT", box, "TOPLEFT", T.PAD + 4, -(y + 9))
				local pill = Pill(box)
				pill:SetPoint("LEFT", name, "RIGHT", 8, 0)
				marks[#marks + 1] = { e = e, pill = pill }
				local does = W.Text(box, "GameFontHighlight", Tr(e.short), "text")
				does:SetWordWrap(true)
				does:SetWidth(linkX - doesX - 14)
				local h = math.max(T.ROW_H, Height(does) + 16)
				does:SetPoint("TOPLEFT", box, "TOPLEFT", doesX, -(y + (h - Height(does)) / 2))
				local link = LinkBox(box, e.url, T.LINK_W)
				link:SetPoint("TOPLEFT", box, "TOPLEFT", linkX, -(y + (h - T.BUTTON_H) / 2))
				y = y + h
			end
		end
	end
	box:SetHeight(y + 8)
	-- the request box
	local ask = W.Panel(sec)
	ask:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -T.GAP)
	ask:SetWidth(width)
	local ay = Heading(ask, 8, TEXT.missing)
	local line = W.Text(ask, "GameFontHighlight", Tr(TEXT.ask), "text")
	line:SetPoint("TOPLEFT", ask, "TOPLEFT", T.PAD + 4, -ay)
	ay = ay + 20
	local link = LinkBox(ask, AP.DISCORD, width - T.PAD * 2 - 8)
	link:SetPoint("TOPLEFT", ask, "TOPLEFT", T.PAD + 4, -ay)
	ask:SetHeight(ay + T.BUTTON_H + 12)
	-- (the installed ones marked, again at each show: an addon loaded on demand since)
	local function Marks()
		for _, m in ipairs(marks) do
			local on = I.Installed(m.e) ~= nil
			m.pill:SetShown(on)
			if on then
				PillShow(m.pill, "working")
				m.pill.text:SetText(Tr(TEXT.installed))
				m.pill:SetWidth(math.floor((m.pill.text:GetStringWidth() or 40) + 0.5) + 22)
			end
		end
	end
	Marks()
	sec.refreshers[#sec.refreshers + 1] = Marks
	sec.compatBox = box
	return y + 8 + T.GAP + ask:GetHeight()
end

--------------------------------------------------------------------------------
-- Who does what (I.Jobs, read at each show)
--------------------------------------------------------------------------------

function AP.Jobs(sec, width, skin)
	local box = W.Panel(sec)
	box:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, 0)
	box:SetWidth(width)
	local top = Heading(box, 8, TEXT.jobs)
	local byX = T.PAD + math.floor(width * 0.42)
	for _, col in ipairs({ { TEXT.colJob, T.PAD + 4 }, { TEXT.colBy, byX } }) do
		local fs = W.Text(box, "GameFontHighlight", Tr(col[1]), "text")
		fs:SetAlpha(0.75)
		fs:SetPoint("TOPLEFT", box, "TOPLEFT", col[2], -top)
	end
	top = top + 22
	local rows = {}
	local function Lay()
		local list = I.Jobs()
		local y = top
		for i, j in ipairs(list) do
			local r = rows[i]
			if not r then
				r = { rule = Rule(box, 0),
					job = W.Text(box, "GameFontHighlight", nil, "text"),
					by = W.Text(box, "GameFontHighlight", nil, "selectedTrim"),
					note = W.Text(box, "GameFontHighlight", nil, "text") }
				r.note:SetAlpha(0.8)
				r.note:SetWordWrap(true)
				r.note:SetWidth(width - byX - T.PAD)
				rows[i] = r
			end
			r.rule:ClearAllPoints()
			r.rule:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -(y - 4))
			r.rule:SetPoint("TOPRIGHT", box, "TOPRIGHT", -10, -(y - 4))
			r.job:SetText(Tr(j[1]))
			r.job:SetPoint("TOPLEFT", box, "TOPLEFT", T.PAD + 4, -(y + 4))
			r.by:SetText(Tr(j[2]))
			r.by:SetPoint("TOPLEFT", box, "TOPLEFT", byX, -(y + 4))
			r.note:SetText(j[3] and Tr(j[3]) or "")
			r.note:SetPoint("TOPLEFT", box, "TOPLEFT", byX, -(y + 21))
			for _, part in pairs(r) do
				part:Show()
			end
			y = y + (j[3] and (Height(r.note) + 28) or T.ROW_H)
		end
		for i = #list + 1, #rows do
			for _, part in pairs(rows[i]) do
				part:Hide()
			end
		end
		box:SetHeight(y + 4)
		return y + 4
	end
	sec.refreshers[#sec.refreshers + 1] = function()
		sec.y = Lay()
		sec:Finish()
	end
	return Lay()
end
