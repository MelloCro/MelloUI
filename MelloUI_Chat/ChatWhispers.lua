--------------------------------------------------------------------------------
-- MelloUI - Chat View's whisper window (0.23.0; docs/plans/chat-redesign.md, stages 4 and 5)
--
-- The user, 2026-10-14: "i really like the whisper window ... the one where the senders messages are on the left
-- and mine on the right, instant message style" (W1), and the flow: "once you get a whisper you get this number
-- notification, telling you that you have a whisper, also the widget tells you that like currently, and clicking on
-- it expands the whisper window from the top of the chat upwards where you have all of your whisper chats with other
-- people". After the whisper-messenger addon's idea (looked at on its page, not copied).
--
-- One window for every whisper, while the minimal chat is on (Chat View: Minimal):
--   * the people on its left: each one's class picture in the kit's round rim, an unread count on the rim, a dot
--     while they are known to be online (a friend, a guild member, a Battle.net friend), the name in its class
--     colour, how long ago, the last line (the engine cuts it: nothing measured)
--   * the conversation in bubbles: theirs left on the raised panel by their picture, yours right on the selected
--     tab's red; the name and time over the first of a run. Laid by anchors only, the newest at the foot: a whisper
--     can be SECRET (chat messaging lockdown) -- shown as it is, its bubble at the full width (a plain one shrinks to
--     its text)
--   * the person's header: the name in its class colour, level, class and zone where the game knows them; Add
--     Friend, Invite, Ignore and Report -- the whisper popups' own four (Chat.lua M.Whisper), on a conversation table
--     with the popups' fields
--   * the answer box at the foot (Enter sends: the key press the game wants behind a whisper; Escape lets go)
-- The flow: a whisper lands in the chat like any line; the count pops onto the chat's Whispers tab (its rim lights
-- once) and the whisper widget comes as today (bus 'whisper', this file the one teller while the minimal chat is
-- on). The count, the Whispers tab or the widget's Reply (Chat's OpenWhisper) grow the window up out of the chat's
-- top edge (the one drawer: Anim:Drawer; 0.28 s; Reduce Motion: at once), the conversation that came in open, the
-- widget gone as read; the tab again or the cross fold it back down (0.18 s), Escape closes it at once.
-- Built on its first open (WINDOW-RULES 2f); the conversations are kept from the first whisper, in rings of records
-- made once and written over (no table per line).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_Chat (ChatWhispers)")
local Secret = MelloUI.Safe.IsSecret
local Text = MelloUI.Safe.Text
local Num = MelloUI.Safe.Number
local W = MelloUI.Widgets
local M = MelloUI:GetModule("Chat")
local View = M.View

local WV = { convs = {}, order = {}, current = nil, open = false, job = {}, rows = {}, bubbles = {}, offset = 0,
	listOffset = 0, shim = {}, pixel = 0 }
M.Whispers = WV
View.Whispers = WV

-- UI units
local WIN_H, TITLE_H, LIST_W, ROW_H, PORTRAIT, HEAD_H, BOX_H = 262, 24, 158, 42, 28, 40, 22
local FACE, PADX, PADY, TX, RX = 16, 8, 4, 32, 8   -- their picture; a bubble's padding; their text's left, yours' right
local GAP_RUN, GAP_IN, SHARE = 8, 3, 0.66          -- between runs, inside one; a bubble's widest share of the talk
local CAP, LAY, RUN_SECONDS = 200, 30, 120          -- lines kept per conversation; bubbles laid at most
local OPEN_TIME, CLOSE_TIME, BUTTON = 0.28, 0.18, 20
local SAVE_CONVS, SAVE_WHISPERS = 30, 100   -- kept over a logout: the newest conversations, their newest lines
-- someone whose class is not known: the chat's whisper button of MelloUI's icon set (0.25.0; the game's whisper
-- icon until then), shown whole in the face's place
local UNKNOWN = MelloUI.Widgets.IconPath("chan_whisper")
local TEXT = {
	title = "Whispers",
	none = "No whispers yet. Whisper someone (/w Name) and the conversation shows here.",
	reply = "Reply to %s ...",
	you = "You",
	level = "Level %d",
	now = "now",
}

local function P()
	return M.Whisper
end

-- the chat view's colours, inks and shadows (one look for the chat and its whisper window: ChatView.lua)
local Colour, ChatColour, Shadow = View.Colour, View.ChatColour, View.Shadow

local function Ago(at)
	local s = GetTime() - (at or 0)
	if s < 60 then
		return TEXT.now
	elseif s < 3600 then
		return math.floor(s / 60) .. "m"
	elseif s < 86400 then
		return math.floor(s / 3600) .. "h"
	end
	return math.floor(s / 86400) .. "d"
end

--------------------------------------------------------------------------------
-- The conversations: kept from the first whisper, the window or not
--------------------------------------------------------------------------------

local function Conv(key, kind, target, title)
	local c = WV.convs[key]
	if not c then
		c = { key = key, kind = kind, target = target, title = title, items = {}, count = 0, last = 0, unread = 0 }
		WV.convs[key] = c
	end
	return c
end

-- the j-th newest line of a conversation (0: the newest)
local function Nth(c, j)
	if j >= c.count then
		return nil
	end
	return c.items[((c.last - 1 - j) % CAP) + 1]
end

-- to the top of the people
local function Touch(c)
	local order = WV.order
	for i = #order, 1, -1 do
		if order[i] == c then
			table.remove(order, i)
		end
	end
	table.insert(order, 1, c)
end

function WV.Total()
	local n = 0
	for _, c in pairs(WV.convs) do
		n = n + c.unread
	end
	return n
end

-- One whisper event (the popups' events and keys: Chat.lua's WHISPER_EVENTS). Its arguments: text, the other
-- person's name, ..., at 11 its line ID, at 12 their GUID, at 13 the Battle.net account id.
local function OnEvent(_, event, text, sender, ...)
	local parts = P()
	if not parts then
		return
	end
	if event == "GUILD_ROSTER_UPDATE" then
		parts.GuildStale()
		return
	end
	local how = parts.EVENTS[event]
	if not (how and View.on) then
		return
	end
	local key, target, title, classFile, level, guid
	if how.kind == "BN_WHISPER" then
		local bnID = select(11, ...)
		if Secret(bnID) or not bnID then
			return
		end
		key, target, title = "BN:" .. tostring(bnID), bnID, sender
		classFile, level = parts.BattleNetIdentity(bnID)
	else
		-- the name keys the conversation, so a secret one cannot open one: the whisper is still in the chat
		if Secret(sender) or not sender then
			return
		end
		guid = Text((select(10, ...)))
		key, target = "W:" .. sender, sender
		title = type(Ambiguate) == "function" and Ambiguate(sender, "short") or sender
		classFile, level = parts.CharacterIdentity(sender, guid)
	end
	local c = Conv(key, how.kind, target, title)
	c.guid = guid or c.guid
	if how.incoming then
		c.reportLine = Num((select(9, ...))) or c.reportLine
	end
	-- known once is known: a later whisper without the answer keeps the earlier one
	c.classFile = (parts.Known(classFile) and classFile) or c.classFile
	c.classHex = parts.ClassHex(classFile) or c.classHex
	c.level = level or c.level
	c.last = c.last % CAP + 1
	local rec = c.items[c.last]
	if not rec then
		rec = {}
		c.items[c.last] = rec
	end
	if c.count < CAP then
		c.count = c.count + 1
	end
	rec.text, rec.mine, rec.at, rec.ts = text, not how.incoming, GetTime(), time()
	rec.time = View.Clock and View.Clock() or ""
	c.lastText, c.lastAt, c.lastMine = text, rec.at, rec.mine
	Touch(c)
	local seen = WV.open and WV.current == c
	if how.incoming and not seen then
		c.unread = c.unread + 1
	elseif not how.incoming then
		c.unread = 0   -- (answered)
	end
	-- the widget column's Whispers row hears it here (its Reply opens this window: Chat's OpenWhisper)
	MelloUI:Fire("whisper", key, c.title, c.classHex, text, how.incoming, WV.open)
	if View.WhisperCount then
		View.WhisperCount(how.incoming and not WV.open)
	end
	if WV.frame and WV.open then
		if not WV.current then
			WV.Select(c)
			return
		end
		if seen and (WV.offset > 0 or WV.pixel > 0) then
			WV.offset = math.min(WV.offset + 1, c.count - 1)   -- (scrolled back: the talk holds still)
		end
		WV.LayList()
		if seen then
			WV.Head()   -- (the line to report, a level learnt)
			WV.LayTalk()
		end
	end
end

local events   -- (made the first time the minimal chat comes on: nothing at load)

--------------------------------------------------------------------------------
-- The history (0.23.1; the user, 2026-10-15: "the chat needs its history saved aswell as the whisper window"): the
-- newest conversations (SAVE_CONVS) and their newest lines (SAVE_WHISPERS), their unread counts with them, kept over a
-- logout in the chat view's history (MelloUIChatHistory.whispers) and laid back as the minimal chat comes on. A
-- character's only: a Battle.net conversation is keyed by an id the game gives anew each login. A SECRET line is never
-- kept.
--------------------------------------------------------------------------------

function WV.Save(hist)
	local convs, order = {}, {}
	for _, c in ipairs(WV.order) do
		if #order >= SAVE_CONVS then
			break
		end
		if c.kind == "WHISPER" and type(c.key) == "string" and type(c.target) == "string" and not Secret(c.title) then
			local lines = {}
			for j = math.min(c.count, SAVE_WHISPERS) - 1, 0, -1 do
				local rec = Nth(c, j)
				if rec and not Secret(rec.text) and type(rec.text) == "string" then
					lines[#lines + 1] = { tx = rec.text, m = rec.mine or nil, ts = rec.ts, tm = rec.time }
				end
			end
			if #lines > 0 then
				order[#order + 1] = c.key
				convs[c.key] = { title = c.title, target = c.target, class = Text(c.classFile), hex = Text(c.classHex),
					level = Num(c.level), guid = Text(c.guid), unread = c.unread, lines = lines }
			end
		end
	end
	hist.whispers = { order = order, convs = convs }
end

-- the kept conversations back (once a login, as the minimal chat first comes on)
function WV.Load()
	if WV.loaded then
		return
	end
	WV.loaded = true
	local hist = rawget(_G, "MelloUIChatHistory")
	local w = type(hist) == "table" and hist.whispers
	if type(w) ~= "table" or type(w.order) ~= "table" or type(w.convs) ~= "table" then
		return
	end
	local now, clock = GetTime(), time()
	for _, key in ipairs(w.order) do
		local s = w.convs[key]
		if type(s) == "table" and type(s.lines) == "table" and type(s.target) == "string" and not WV.convs[key] then
			local c = Conv(key, "WHISPER", s.target, type(s.title) == "string" and s.title or s.target)
			c.classFile, c.classHex, c.level, c.guid = Text(s.class), Text(s.hex), Num(s.level), Text(s.guid)
			for _, l in ipairs(s.lines) do
				if type(l) == "table" and type(l.tx) == "string" then
					c.last = c.last % CAP + 1
					local rec = c.items[c.last]
					if not rec then
						rec = {}
						c.items[c.last] = rec
					end
					if c.count < CAP then
						c.count = c.count + 1
					end
					rec.text, rec.mine, rec.ts, rec.time = l.tx, l.m and true or false, Num(l.ts), l.tm
					rec.at = now - math.max(0, clock - (rec.ts or clock))
					c.lastText, c.lastAt, c.lastMine = rec.text, rec.at, rec.mine
				end
			end
			c.unread = Num(s.unread) or 0
			WV.order[#WV.order + 1] = c
		end
	end
	if View.WhisperCount then
		View.WhisperCount(false)
	end
end

-- the whispers heard while the minimal chat is on
function WV.Listen(on)
	local parts = P()
	if on and not events then
		events = CreateFrame("Frame")
	end
	if not events then
		return
	end
	if on then
		WV.Load()   -- (the conversations kept over the last logout)
	end
	if on and parts then
		for event in pairs(parts.EVENTS) do
			events:RegisterEvent(event)
		end
		events:RegisterEvent("GUILD_ROSTER_UPDATE")
		Perf.SetScript(events, "OnEvent", OnEvent)
	else
		events:UnregisterAllEvents()
	end
end

--------------------------------------------------------------------------------
-- The people
--------------------------------------------------------------------------------

local RowClick = Perf.Shared("OnClick on a whisper window person", function(row)
	if row.conv and row.conv ~= WV.current then
		MelloUI:PlayUISound("tab")
		WV.Select(row.conv)
	end
	WV.Answer()
end, "script")

local RowEnter = Perf.Shared("OnEnter on a whisper window person", function(row)
	-- ("2m" ago: laid again on every whisper and every open, and a row's own under the pointer; no timer)
	if row.conv then
		row.ago:SetText(Ago(row.conv.lastAt))
	end
	if row.conv ~= WV.current then
		row.fill:SetAlpha(0.35)
		row.fill:Show()
	end
end, "script")

local RowLeave = Perf.Shared("OnLeave on a whisper window person", function(row)
	if row.conv ~= WV.current then
		row.fill:Hide()
	end
end, "script")

local function Row(i)
	local row = WV.rows[i]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, WV.list)
	row:SetHeight(ROW_H)
	row:RegisterForClicks("LeftButtonUp")
	row.fill = W.Solid(row, "BACKGROUND", "hover", 0.6)
	row.fill:SetAllPoints(row)
	row.fill:Hide()
	row.mark = W.Solid(row, "ARTWORK", "selectedTrim")
	row.mark:SetWidth(2)
	row.mark:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.mark:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	row.mark:Hide()
	local face = W.RoundIcon(row, PORTRAIT, UNKNOWN)
	face:EnableMouse(false)   -- (the row takes the click)
	face:SetPoint("LEFT", row, "LEFT", 6, 0)
	View.KitRim(face)
	row.face = face
	local dot = row:CreateTexture(nil, "OVERLAY", nil, 6)
	dot:SetTexture(W.IconPath("map_dot"))   -- (0.25.0: the set's bead, its white tinted; a flat disc until then)
	dot:SetSize(7, 7)
	dot:SetPoint("CENTER", face, "BOTTOMRIGHT", -3, 3)
	row.dot = dot
	row.name = row:CreateFontString(nil, "OVERLAY", "MelloUIFont_GameFontNormal")
	row.name:SetPoint("TOPLEFT", face, "TOPRIGHT", 8, 1)
	row.name:SetPoint("RIGHT", row, "RIGHT", -34, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.ago = row:CreateFontString(nil, "OVERLAY", "MelloUIFont_GameFontHighlightSmall")
	row.ago:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -7)
	row.ago:SetJustifyH("RIGHT")
	row.last = row:CreateFontString(nil, "OVERLAY", "MelloUIFont_GameFontHighlightSmall")
	row.last:SetPoint("BOTTOMLEFT", face, "BOTTOMRIGHT", 8, 0)
	row.last:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	row.last:SetJustifyH("LEFT")
	row.last:SetWordWrap(false)   -- (the engine ends a long one with "...": nothing measured)
	Perf.SetScript(row, "OnClick", RowClick)
	Perf.SetScript(row, "OnEnter", RowEnter)
	Perf.SetScript(row, "OnLeave", RowLeave)
	WV.rows[i] = row
	return row
end

-- a person's class picture on a round icon's texture: the class medallion always (MelloUI.Look's one class
-- picture)
local function Picture(tex, c)
	local Look = MelloUI.Look
	local class = c and Text(c.classFile)
	if Look and Look.ClassIcon then
		Look.ClassIcon(tex, class, class and MelloUI.ClassIconPath and MelloUI:ClassIconPath(class) or UNKNOWN)
	else
		tex:SetTexture(UNKNOWN)
	end
end

-- a person's name on `fs`: in their class colour on the dark panel; on the paper in ink after their class gem (the
-- chat's own way: View.Gem)
local function NameText(c, fs)
	local name = c.title
	if Secret(name) then
		return name
	end
	if View.paper then
		Colour(fs, "text")
		local QI = MelloUI.QuestInk
		local r, g, b
		if QI and QI.ClassColour then
			r, g, b = QI.ClassColour(c.classFile)
		end
		return View.Gem(r, g, b, fs) .. tostring(name)
	end
	local hex = c.classHex
	local code = hex and ("|c" .. hex) or MelloUI:PaletteCode("selectedTrim")
	return code .. tostring(name) .. "|r"
end

function WV.LayList()
	local list = WV.list
	if not list then
		return
	end
	local okH, height = pcall(list.GetHeight, list)
	height = okH and Num(height) or 200
	local fits = math.max(1, math.floor(height / ROW_H))
	WV.listOffset = math.max(0, math.min(WV.listOffset, #WV.order - fits))
	WV.Bar(WV.listBar, #WV.order - fits, WV.listOffset, fits / math.max(1, #WV.order))
	local shown = 0
	for i = 1, #WV.order do
		local c = WV.order[i]
		local slot = i - WV.listOffset
		if slot >= 1 and slot <= fits + 1 then
			shown = shown + 1
			local row = Row(shown)
			row.conv = c
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(slot - 1) * ROW_H)
			row:SetPoint("RIGHT", list, "RIGHT", 0, 0)
			local on = c == WV.current
			row.fill:SetAlpha(0.6)
			row.fill:SetShown(on)
			row.mark:SetShown(on)
			Picture(row.face.icon, c)
			View.SetCount(row.face, c.unread)
			local _, online = P().Where(c.kind, c.target, c.guid)
			row.dot:SetShown(online ~= nil)
			W.Paint(row.dot, online and "selectedTrim" or "border", "vertex")
			pcall(row.name.SetText, row.name, NameText(c, row.name))
			Shadow(row.name)
			row.ago:SetText(Ago(c.lastAt))
			Colour(row.ago, "text")
			Shadow(row.ago)
			local last = c.lastText
			if c.lastMine and not Secret(last) and type(last) == "string" then
				last = TEXT.you .. ": " .. last
			end
			pcall(row.last.SetText, row.last, last)
			Colour(row.last, "text")
			Shadow(row.last)
			row:Show()
		end
	end
	for i = shown + 1, #WV.rows do
		WV.rows[i]:Hide()
		WV.rows[i].conv = nil
	end
end

--------------------------------------------------------------------------------
-- The talk: bubbles by anchors, the newest at the foot
--------------------------------------------------------------------------------

local function Bubble(k)
	local b = WV.bubbles[k]
	if b then
		return b
	end
	local talk = WV.talk
	b = {}
	b.ground = talk:CreateTexture(nil, "BACKGROUND", nil, 2)
	b.text = talk:CreateFontString(nil, "OVERLAY")
	b.text:SetJustifyH("LEFT")
	b.text:SetJustifyV("TOP")
	b.text:SetWordWrap(true)
	b.stamp = talk:CreateFontString(nil, "OVERLAY")
	b.face = talk:CreateTexture(nil, "ARTWORK")
	b.face:SetSize(FACE, FACE)
	local mask = talk:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(b.face)
	b.face:AddMaskTexture(mask)
	-- the row's ceiling: the talk's width, the next older bubble stands on it
	b.ceil = talk:CreateTexture(nil, "BACKGROUND")
	b.ceil:SetHeight(1)   -- (no texture: an anchor, never drawn)
	View.Font(b.text, nil, ChatFrame1)   -- (whispers come to General: its font)
	View.Font(b.stamp, 0.85, ChatFrame1)
	WV.bubbles[k] = b
	return b
end

local function HideBubble(b)
	b.ground:Hide()
	b.text:Hide()
	b.stamp:Hide()
	b.face:Hide()
end

local function SameRun(newer, older)
	return newer and older and newer.mine == older.mine and (newer.at - older.at) < RUN_SECONDS
end

function WV.LayTalk()
	local talk, c = WV.talk, WV.current
	if not talk then
		return
	end
	WV.none:SetShown(c == nil)
	Colour(WV.none, "text")
	if not c then
		for i = 1, #WV.bubbles do
			HideBubble(WV.bubbles[i])
		end
		WV.Bar(WV.talkBar, 0)
		return
	end
	local okW, width = pcall(talk.GetWidth, talk)
	width = okW and Num(width) or 280
	local widest = math.max(60, width * SHARE - 2 * PADX)
	local parts = P()
	local prev, k, j = nil, 0, WV.offset
	local newer = nil
	while k < LAY do
		local rec = Nth(c, j)
		if not rec then
			break
		end
		k = k + 1
		local b = Bubble(k)
		local text, ground = b.text, b.ground
		local mine = rec.mine
		text:SetWidth(widest)
		pcall(text.SetText, text, rec.text)
		-- a plain line's bubble shrinks to its text (a secret one keeps the full width: nothing of it is read)
		if not Secret(rec.text) then
			local okU, w = pcall(text.GetUnboundedStringWidth, text)
			w = okU and Num(w)
			if w and w + 2 < widest then
				text:SetWidth(w + 2)
			end
		end
		local r, g, bl = parts.PopupColor(c.kind, not mine)
		ChatColour(text, r, g, bl)
		Shadow(text)
		local gap = (prev == nil) and (PADY + 2) or ((newer and SameRun(newer, rec)) and GAP_IN or GAP_RUN) + PADY
		text:ClearAllPoints()
		-- (the newest bubble at the foot, pushed down by the glide: View.Glide)
		if k == 2 and WV.firstPart then
			WV.firstH = WV.firstPart + gap
		end
		if mine then
			if prev then
				text:SetPoint("BOTTOMRIGHT", prev, "TOPRIGHT", -RX, gap)
			else
				text:SetPoint("BOTTOMRIGHT", talk, "BOTTOMRIGHT", -RX, gap - WV.pixel)
				WV.firstMine, WV.firstGap = true, gap
			end
		elseif prev then
			text:SetPoint("BOTTOMLEFT", prev, "TOPLEFT", TX, gap)
		else
			text:SetPoint("BOTTOMLEFT", talk, "BOTTOMLEFT", TX, gap - WV.pixel)
			WV.firstMine, WV.firstGap = false, gap
		end
		text:Show()
		ground:ClearAllPoints()
		ground:SetPoint("TOPLEFT", text, "TOPLEFT", -PADX, PADY)
		ground:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", PADX, -PADY)
		W.Paint(ground, mine and "selectedTab" or "raisedPanel", "fill", View.paper and 0.16 or 0.92)
		ground:Show()
		-- their picture by the newest bubble of their run
		if not mine and not (newer and SameRun(newer, rec)) then
			b.face:ClearAllPoints()
			b.face:SetPoint("BOTTOMLEFT", text, "BOTTOMLEFT", -TX, -PADY)
			Picture(b.face, c)
			b.face:Show()
		else
			b.face:Hide()
		end
		-- the name and time over the first (oldest) bubble of a run
		local older = Nth(c, j + 1)
		local top = text
		local topX = mine and RX or -TX
		if not SameRun(rec, older) then
			local stamp = b.stamp
			stamp:ClearAllPoints()
			local who = mine and TEXT.you or c.title
			pcall(stamp.SetText, stamp, (Secret(who) and "" or (tostring(who) .. "  ")) .. (rec.time or ""))
			if mine then
				stamp:SetPoint("BOTTOMRIGHT", text, "TOPRIGHT", PADX, PADY + 2)
				topX = RX - PADX
			else
				stamp:SetPoint("BOTTOMLEFT", text, "TOPLEFT", -PADX, PADY + 2)
				topX = -(TX - PADX)
			end
			Colour(stamp, "text")
			Shadow(stamp)
			stamp:Show()
			top = stamp
		else
			b.stamp:Hide()
		end
		-- the ceiling on the topmost of the row, at the talk's left (theirs) or right (yours)
		local ceil = b.ceil
		ceil:ClearAllPoints()
		ceil:SetWidth(width)
		if mine then
			ceil:SetPoint("BOTTOMRIGHT", top, "TOPRIGHT", topX, top == text and PADY or 0)
		else
			ceil:SetPoint("BOTTOMLEFT", top, "TOPLEFT", topX, top == text and PADY or 0)
		end
		if k == 1 then
			-- the newest bubble's height to its ceiling (nil: secret, the glide guesses it); with the next one's gap
			local th = View.Height(text)
			local sh = top ~= text and View.Height(b.stamp) or 0
			WV.firstPart = (th and sh) and (th + (top ~= text and (PADY + 2 + sh) or PADY) + 1) or nil
			WV.firstH = WV.firstPart
		end
		prev, newer = ceil, rec
		j = j + 1
	end
	if k == 0 then
		WV.firstH = nil
	end
	-- (the top stop's: the topmost laid bubble's ceiling, and whether it is the oldest kept)
	WV.topRegion, WV.oldestLaid = prev, k > 0 and Nth(c, j) == nil
	for i = k + 1, #WV.bubbles do
		HideBubble(WV.bubbles[i])
	end
	-- past the window: the topmost laid bubble over the talk's top, or lines not laid (a secret one unread: guessed
	-- from the window's height)
	local okT, talkTop = pcall(talk.GetTop, talk)
	local okP, prevTop = pcall(prev and prev.GetTop or talk.GetTop, prev or talk)
	talkTop, prevTop = okT and Num(talkTop), okP and Num(prevTop)
	local okH, talkH = pcall(talk.GetHeight, talk)
	local inView = math.max(1, (okH and Num(talkH) or 120) / WV.scroller.estimate())
	local past = k < c.count or (talkTop and prevTop and prevTop > talkTop) or (not (talkTop and prevTop) and c.count > inView)
	local top = past and math.max(1, math.ceil(c.count - inView)) or 0
	WV.Bar(WV.talkBar, top, top - WV.offset, inView / math.max(1, c.count))
end

-- a bar of the window's (MelloUI's thin one): its range 0 .. top (none: hidden), at `value`, its thumb `share` of it
function WV.Bar(bar, top, value, share)
	if not bar then
		return
	end
	top = math.max(0, top or 0)
	local okD, dragging = pcall(bar.IsDraggingThumb, bar)
	bar.laying = true
	bar:SetMinMaxValues(0, top)
	if not (okD and dragging == true) then
		bar:SetValue(math.max(0, math.min(top, value or 0)))   -- (dragged: the thumb is the mouse's)
	end
	bar.laying = false
	if top > 0 then
		local okB, bh = pcall(bar.GetHeight, bar)
		bh = okB and Num(bh) or 100
		bar.thumb:SetHeight(math.max(12, bh * math.min(1, share or 1)))
	end
	bar:SetShown(top > 0)
end

-- the talk glides as the chat does (View.Glide: the chat's Smooth Scrolling)
WV.scroller = {
	owner = WV, target = 0, from = 0,
	count = function()
		return WV.current and WV.current.count or 0
	end,
	lay = function()
		WV.LayTalk()
	end,
	shift = function()
		local b = WV.bubbles[1]
		if not (b and b.text:IsShown()) then
			return
		end
		if WV.firstMine then
			b.text:SetPoint("BOTTOMRIGHT", WV.talk, "BOTTOMRIGHT", -RX, (WV.firstGap or 0) - WV.pixel)
		else
			b.text:SetPoint("BOTTOMLEFT", WV.talk, "BOTTOMLEFT", TX, (WV.firstGap or 0) - WV.pixel)
		end
	end,
	estimate = function()
		local ok, _, size = pcall(ChatFrame1.GetFont, ChatFrame1)
		return ((ok and Num(size)) or 14) * 1.25 + 2 * PADY + GAP_IN
	end,
	room = function()
		return View.Room(WV, WV.talk)
	end,
}

function WV.Scroll(delta)
	if not WV.current then
		return
	end
	View.Glide(WV.scroller, delta * (IsShiftKeyDown() and 5 or 1))
end

--------------------------------------------------------------------------------
-- The person's header and the answer
--------------------------------------------------------------------------------

local function LayActions()
	local acts, kind = WV.shim.actions, WV.shim.kind
	if not acts then
		return
	end
	local Kit = View.RimKit()   -- (the icon set's own buttons; the kit's rim under Oldschool's painted chat)
	local x = -8
	local parts = P()
	for i = #parts.ACTIONS, 1, -1 do
		local id = parts.ACTIONS[i]
		local b = acts[id]
		b.wanted = WV.current ~= nil and (kind ~= "BN_WHISPER" or id == "invite" or id == "report")
		b:SetKit(Kit)
		b:ClearAllPoints()
		if b.wanted then
			b:SetPoint("RIGHT", WV.head, "RIGHT", x, 0)
			x = x - (BUTTON + 6)
		end
		b:SetShown(b.wanted)
	end
end

function WV.Head()
	local c, head = WV.current, WV.head
	if not head then
		return
	end
	local shim = WV.shim
	shim.target, shim.kind, shim.guid, shim.reportLine = c and c.target, c and c.kind, c and c.guid, c and c.reportLine
	shim.titleText = c and c.title
	LayActions()
	if c then
		P().RefreshActions(shim)
	end
	if not c then
		WV.name:SetText("")
		WV.info:SetText("")
		return
	end
	pcall(WV.name.SetText, WV.name, NameText(c, WV.name))
	Shadow(WV.name)
	local zone = P().Where(c.kind, c.target, c.guid)
	local info = ""
	if c.level then
		info = TEXT.level:format(c.level)
	end
	local class = Text(c.classFile)
	local localized = class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
	if type(localized) == "string" then
		info = info ~= "" and (info .. " " .. localized) or localized
	end
	if zone then
		info = info ~= "" and (info .. "  \194\183  " .. zone) or zone
	end
	WV.info:SetText(info)
	Colour(WV.info, "text")
	Shadow(WV.info)
	local who = Secret(c.title) and "" or tostring(c.title)
	WV.hint:SetText(TEXT.reply:format(who))
	WV.boxHint:SetText(TEXT.reply:format(who))
end

-- Input Box Only While Typing (Chat's, the game's chat style): the answer box shows while you type; else a "Reply
-- to ..." line on the window stands in its place (the user, 2026-10-15: "the edit box on the whisper window remains
-- visible even when not typing, and the text inside it is almost not visible" -- its hint was inked on its dark field)
local function TypingOnly()
	return not (M.db and M.db.editBoxWhileTyping == false)
end

local function Placeholder()
	local box, c = WV.box, WV.current
	local typing = box:HasFocus() or box:GetText() ~= ""
	local only = TypingOnly()
	box:SetShown(c ~= nil and (typing or not only))
	WV.reply:SetShown(c ~= nil and only and not typing)
	WV.boxHint:SetShown(c ~= nil and not only and not typing)
end

-- the answer box out and taking the keys (a click on the reply line, on a person; the widget's Reply)
function WV.Answer()
	if not (WV.box and WV.current) then
		return
	end
	WV.box:Show()
	WV.box:SetFocus()
	Placeholder()
end

-- a conversation open in the window: read, its talk from the newest, its header, the answer box's target
function WV.Select(c)
	WV.current = c
	if c then
		c.unread = 0
	end
	WV.offset = 0
	View.Settle(WV.scroller)
	WV.Head()
	WV.LayList()
	WV.LayTalk()
	if WV.box then
		Placeholder()
	end
	if View.WhisperCount then
		View.WhisperCount(false)
	end
end

--------------------------------------------------------------------------------
-- The window, and the drawer it comes out of
--------------------------------------------------------------------------------

local function Build()
	if WV.frame then
		return
	end
	local view = View.frame
	local holder = CreateFrame("Frame", nil, UIParent)
	holder:SetAllPoints(UIParent)
	holder:SetFrameStrata(view:GetFrameStrata())
	holder:SetFrameLevel(view:GetFrameLevel() + 30)
	holder:EnableMouse(false)
	local f = CreateFrame("Frame", "MelloUIWhispers", holder)
	f:SetHeight(WIN_H)
	f:EnableMouse(true)
	W.Panel(f, { on = true, alpha = 0.94 })
	WV.holder, WV.frame = holder, f
	-- the title, the close cross, the title's hairline
	local title = f:CreateFontString(nil, "OVERLAY", "MelloUIFont_GameFontNormal")
	title:SetPoint("LEFT", f, "TOPLEFT", 10, -TITLE_H / 2)
	title:SetText(TEXT.title)
	if MelloUI.Kit and MelloUI.Kit.TitleFont then
		MelloUI.Kit:TitleFont(title, true)   -- (the title face for everyone: one look, the user's pick 9, 2026-10-15)
	end
	WV.title = title
	local close = W.CloseButton(f)
	close:SetPoint("RIGHT", f, "TOPRIGHT", -6, -TITLE_H / 2)
	Perf.SetScript(close, "OnClick", function()
		WV.Close()
	end)
	local hair = W.Solid(f, "ARTWORK", "border")
	hair:SetHeight(1)
	hair:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -TITLE_H)
	hair:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -TITLE_H)
	-- the people: clipped, the wheel scrolls them
	local list = CreateFrame("Frame", nil, f)
	list:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -(TITLE_H + 4))
	list:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", LIST_W, 4)
	list:SetClipsChildren(true)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		WV.listOffset = WV.listOffset - delta
		WV.LayList()
	end)

	WV.list = list
	-- its bar (shown while the people do not all fit): dragged, the list follows
	local listBar = W.ThinScrollBar(f, 3)
	listBar:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)
	listBar:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)
	listBar:SetFrameLevel(list:GetFrameLevel() + 10)
	listBar:Hide()
	listBar:SetScript("OnValueChanged", function(self, value)
		if self.laying then
			return
		end
		WV.listOffset = math.floor((Num(value) or 0) + 0.5)
		WV.LayList()
	end)
	WV.listBar = listBar
	local divider = W.Solid(f, "ARTWORK", "border")
	divider:SetWidth(1)
	divider:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_W + 2, -(TITLE_H + 6))
	divider:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", LIST_W + 2, 6)
	-- the person's header: the name, what is known of them, the four buttons
	local head = CreateFrame("Frame", nil, f)
	head:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_W + 3, -TITLE_H)
	head:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -TITLE_H)
	head:SetHeight(HEAD_H)
	WV.head = head
	WV.name = head:CreateFontString(nil, "OVERLAY", "MelloUIFont_GameFontNormalLarge")
	WV.name:SetPoint("TOPLEFT", head, "TOPLEFT", 10, -5)
	WV.name:SetPoint("RIGHT", head, "RIGHT", -(4 * (BUTTON + 6) + 10), 0)
	WV.name:SetJustifyH("LEFT")
	WV.name:SetWordWrap(false)
	WV.info = head:CreateFontString(nil, "OVERLAY", "MelloUIFont_GameFontHighlightSmall")
	WV.info:SetPoint("TOPLEFT", WV.name, "BOTTOMLEFT", 0, -2)
	WV.info:SetPoint("RIGHT", head, "RIGHT", -(4 * (BUTTON + 6) + 10), 0)
	WV.info:SetJustifyH("LEFT")
	WV.info:SetWordWrap(false)
	local headLine = W.Solid(f, "ARTWORK", "border")
	headLine:SetHeight(1)
	headLine:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 6, 0)
	headLine:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", -8, 0)
	WV.shim.head = head
	P().MakeActions(WV.shim, BUTTON)
	-- the talk: clipped, the wheel scrolls it by bubble, links click as in the chat
	local talk = CreateFrame("Frame", nil, f)
	talk:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 6, -4)
	talk:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, BOX_H + 12)
	talk:SetClipsChildren(true)
	talk:EnableMouseWheel(true)
	talk:SetScript("OnMouseWheel", function(_, delta)
		WV.Scroll(delta)
	end)
	View.Links(talk)
	talk:SetScript("OnSizeChanged", function()
		if WV.open then
			WV.LayTalk()
		end
	end)
	WV.talk = talk
	-- its bar (shown while the talk runs past the window; the newest at its foot): dragged, the talk follows
	local talkBar = W.ThinScrollBar(f, 3)
	talkBar:SetPoint("TOPLEFT", talk, "TOPRIGHT", 1, 0)
	talkBar:SetPoint("BOTTOMLEFT", talk, "BOTTOMRIGHT", 1, 0)
	talkBar:Hide()
	talkBar:SetScript("OnValueChanged", function(self, value)
		if self.laying or not WV.current then
			return
		end
		local _, top = self:GetMinMaxValues()
		View.Settle(WV.scroller)
		WV.offset = math.max(0, math.min(WV.current.count - 1, math.floor((Num(top) or 0) - (Num(value) or 0) + 0.5)))
		WV.LayTalk()
		View.TopStop(WV.scroller)   -- (at its top: the oldest bubble's top at the window's top)
	end)
	WV.talkBar = talkBar
	WV.none = talk:CreateFontString(nil, "OVERLAY", "MelloUIFont_GameFontHighlight")
	WV.none:SetPoint("CENTER", talk, "CENTER", 0, 0)
	WV.none:SetWidth(220)
	WV.none:SetText(TEXT.none)
	-- the answer: Enter sends (the key press the game wants behind it) and keeps the box; Enter on an empty box lets
	-- go of it, as the game's chat box does; Escape lets go
	local box = CreateFrame("EditBox", nil, f)
	box:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", LIST_W + 10, 8)
	box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
	box:SetHeight(BOX_H)
	box:SetAutoFocus(false)   -- never takes the keyboard by itself: movement keys stay the player's
	box:SetMaxLetters(255)
	box:SetFontObject(ChatFontNormal)
	box:SetTextInsets(6, 6, 0, 0)
	if W.FlatField then
		W.FlatField(box)
	end
	Perf.SetScript(box, "OnEnterPressed", function(self)
		local text = self:GetText()
		self:SetText("")
		if WV.current and text and text:find("%S") then
			P().SendWhisper(WV.shim, text)
		else
			self:ClearFocus()
		end
	end)
	Perf.SetScript(box, "OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	Perf.SetScript(box, "OnEditFocusGained", Placeholder)
	Perf.SetScript(box, "OnEditFocusLost", Placeholder)
	Perf.SetScript(box, "OnTextChanged", Placeholder)
	WV.box = box
	-- its hint inside it (the box always shown: its field's light colours, never ink)
	WV.boxHint = box:CreateFontString(nil, "ARTWORK", "MelloUIFont_GameFontDisable")
	WV.boxHint:SetPoint("LEFT", box, "LEFT", 7, 0)
	-- the reply line in its place while you do not type (on the window: in ink on the paper); a click opens the box
	local reply = CreateFrame("Button", nil, f)
	reply:SetAllPoints(box)
	reply:RegisterForClicks("LeftButtonUp")
	WV.hint = reply:CreateFontString(nil, "ARTWORK", "MelloUIFont_GameFontHighlight")
	WV.hint:SetPoint("LEFT", reply, "LEFT", 7, 0)
	WV.hint:SetPoint("RIGHT", reply, "RIGHT", -7, 0)
	WV.hint:SetJustifyH("LEFT")
	WV.hint:SetWordWrap(false)
	Perf.SetScript(reply, "OnClick", function()
		WV.Answer()
	end)
	Perf.SetScript(reply, "OnEnter", function()
		Colour(WV.hint, "text")
	end)
	Perf.SetScript(reply, "OnLeave", function()
		Colour(WV.hint, "mutedText")
	end)
	reply:Hide()
	WV.reply = reply
	-- Escape closes it (at once; the game's walk hides it): UISpecialFrames, as the own windows' shell does
	if type(UISpecialFrames) == "table" then
		tinsert(UISpecialFrames, "MelloUIWhispers")
	end
	f:SetScript("OnHide", function()
		WV.Ended()
	end)
	-- the drawer: up out of the chat's top edge
	local job = WV.job
	job.holder, job.content, job.p, job.rel, job.rp, job.x, job.y = holder, f, "BOTTOM", view, "TOP", 0, 2
	job.pad, job.lag, job.h = 6, 0.35, WIN_H
	f:Hide()
	WV.Restyle()
end

-- the window's colours and paper again (the chat's parchment, a new palette, the kit's look)
function WV.Restyle()
	local f = WV.frame
	if not f then
		return
	end
	local paper = View.paper
	if paper and not WV.sheet and MelloUI.Kit and MelloUI.Kit.ParchmentSheet then
		WV.sheet = MelloUI.Kit:ParchmentSheet(f, f, { rect = f, margin = 3 })
	end
	if WV.sheet then
		WV.sheet:SetShown(paper)
	end
	Colour(WV.title, "selectedTrim")
	Shadow(WV.title)
	Colour(WV.hint, "mutedText")
	Shadow(WV.hint)
	View.FieldColour(WV.boxHint, "mutedText")   -- (in the box's dark field)
	View.FieldColour(WV.box, "text")
	local Kit = View.RimKit()
	for _, row in ipairs(WV.rows) do
		row.face:SetKit(Kit)
	end
	if WV.open then
		WV.Head()
		WV.LayList()
		WV.LayTalk()
	end
end

-- the chat's font again on the bubbles (View.Fonts)
function WV.Fonts()
	for _, b in ipairs(WV.bubbles) do
		View.Font(b.text, nil, ChatFrame1)
		View.Font(b.stamp, 0.85, ChatFrame1)
	end
	if WV.open then
		WV.LayTalk()
	end
end

-- open (the conversation `key`, else the one open last, else the newest); `answer`: the box out to answer in (the
-- widget's Reply); false while the minimal chat is off
function WV.Open(key, answer)
	if not (View.on and View.frame) then
		return false
	end
	Build()
	local f, job = WV.frame, WV.job
	local okW, width = pcall(View.frame.GetWidth, View.frame)
	width = okW and Num(width) or 440
	f:SetWidth(width)
	job.w = width
	local c = (key and WV.convs[key]) or WV.current or WV.order[1]
	local was = WV.open
	WV.open = true
	-- the widget's rows read (its count gone with this window open: every conversation told, none came in)
	for k, conv in pairs(WV.convs) do
		MelloUI:Fire("whisper", k, conv.title, conv.classHex, nil, false, true)
	end
	WV.Restyle()
	WV.Select(c)
	if not was then
		f:Show()
		MelloUI.Anim:Drawer(job, true, OPEN_TIME)
	end
	if View.Lit then
		View.Lit()
	end
	if answer then
		WV.Answer()
	end
	return true
end

-- the tab again, the cross: folded back down into the chat
function WV.Close()
	if not (WV.frame and WV.open) then
		return
	end
	WV.open = false
	if WV.box then
		WV.box:ClearFocus()
	end
	MelloUI.Anim:Drawer(WV.job, false, CLOSE_TIME, function()
		WV.frame:Hide()
	end)
	if View.Lit then
		View.Lit()
	end
	if View.WhisperCount then
		View.WhisperCount(false)
	end
end

function WV.Toggle()
	if WV.open then
		WV.Close()
	else
		WV.Open()
	end
end

-- hidden however it went (folded, Escape, the minimal chat off): nothing left running
function WV.Ended()
	WV.open = false
	MelloUI.Anim:StopDrawer(WV.job)
	if WV.box then
		WV.box:ClearFocus()
	end
	if View.Lit then
		View.Lit()
	end
	if View.WhisperCount then
		View.WhisperCount(false)
	end
end

-- the minimal chat off: the window gone at once
function WV.Hide()
	if WV.frame and WV.frame:IsShown() then
		WV.frame:Hide()
	end
end
