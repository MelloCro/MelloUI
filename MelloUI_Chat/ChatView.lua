--------------------------------------------------------------------------------
-- MelloUI - Chat View (0.23.0; docs/plans/chat-redesign.md, stages 2 and 3)
--
-- The user, 2026-10-14: "a minimalistic version where its less visual clutter, minimalistic, functional but also
-- true to the artstyle" -- picked: frame A (a rail of round tabs with their names, the lines on the dark inner panel,
-- one row of twelve round buttons under them) and the lines laid out as 3 (the name, its channel's short tag and the
-- time on one line, the message under it; a run from one person under one name).
--
-- MelloUI's own view of the chat, the game's chat windows alive but out of sight under it (Chat View: Minimal):
--   * the lines are the game's own: the Chat module's post-hook on each window's AddMessage hands every line here as
--     the game adds it -- through every filter, other addons' prints too -- with the chat event and its whole
--     argument pack when it came from one (the game's handler calls AddMessage(msg, r, g, b, id, accessID, typeID,
--     event, eventArgs), ChatFrameOverrides.lua): the sender, the channel and the GUID for the header
--   * each tab on the rail is one of the game's chat windows (GetChatWindowInfo, read only) and shows the lines that
--     window got; nothing of the game's dock or tabs is driven from here (that tainted the chat pipeline before:
--     the whisper popup's note), the rail switches this view only
--   * the rows are laid out by anchors alone, each under the one before, the newest at the foot, clipped by the
--     lines' holder and scrolled by message: a line can be SECRET (chat messaging lockdown) and then nothing of its
--     size can be read (the spike of 2026-10-14) -- the game lays the rows out, this file reads no size of a line
--   * the game's windows at alpha 0 without the mouse (the chat fade touches only tabs and textures; ChatPanel's
--     no-fade and the Fader's chat fade stand aside: MelloUI.ChatView.hiding); the line you type in shown on its own
--     over the lines' foot; the row's S P R I G Y W E open it on that chat type the game's way
--     (ChatFrameUtil.OpenChat: the edit box runs secure commands before it reads the chat type -- a /use typed after
--     still casts, checked in game 2026-10-14)
-- Nothing is made while the view is off; the rows and their records are made once and used again (no table per line).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_Chat (ChatView)")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
local Secret, Plain = MelloUI.Safe.IsSecret, MelloUI.Safe.Value
local W = MelloUI.Widgets
local M = MelloUI:GetModule("Chat")

local View = { on = false, hiding = false, tab = nil, offset = 0, bufs = {}, unread = {}, rows = {}, tabs = {},
	order = {}, pending = false }
M.View = View
MelloUI.ChatView = View   -- (ChatPanel's no-fade and the Fader's chat fade ask it)

-- UI units
local RAIL_W, ROW_H, ICON, LETTER, PAD = 112, 34, 24, 24, 6
local GAP_RUN, GAP_LINE, GAP_PLAIN, INDENT, RUN_SECONDS = 6, 1, 2, 10, 120
local CAP, LAY = 300, 40          -- lines kept per tab; rows laid at most (the holder clips what does not fit)
local SEED = 60                   -- the game's own lines a tab starts with when the view comes on

-- the chat types whose lines get a header (the rest -- the game's own notices, loot, addons' prints -- are lines alone)
local HEADED = { SAY = true, YELL = true, EMOTE = true, PARTY = true, PARTY_LEADER = true, RAID = true,
	RAID_LEADER = true, RAID_WARNING = true, INSTANCE_CHAT = true, INSTANCE_CHAT_LEADER = true, GUILD = true,
	OFFICER = true, WHISPER = true, WHISPER_INFORM = true, BN_WHISPER = true, BN_WHISPER_INFORM = true, CHANNEL = true,
	MONSTER_SAY = true, MONSTER_YELL = true, MONSTER_WHISPER = true }
local TYPE_NAME = { SAY = "Say", YELL = "Yell", EMOTE = "Emote", PARTY = "Party", PARTY_LEADER = "Party",
	RAID = "Raid", RAID_LEADER = "Raid", RAID_WARNING = "Raid Warning", INSTANCE_CHAT = "Instance",
	INSTANCE_CHAT_LEADER = "Instance", GUILD = "Guild", OFFICER = "Officer", WHISPER = "Whisper",
	WHISPER_INFORM = "Whisper", BN_WHISPER = "Whisper", BN_WHISPER_INFORM = "Whisper", MONSTER_SAY = "Says",
	MONSTER_YELL = "Yells", MONSTER_WHISPER = "Whispers" }
-- who you speak to: the row's letters (the chat menu's picks), the game's slash command for each, its chat colour
local PICKS = { { "S", "/s ", "SAY", "Say" }, { "P", "/p ", "PARTY", "Party" }, { "R", "/ra ", "RAID", "Raid" },
	{ "I", "/i ", "INSTANCE_CHAT", "Instance" }, { "G", "/g ", "GUILD", "Guild" }, { "Y", "/y ", "YELL", "Yell" },
	{ "W", "/w ", "WHISPER", "Whisper someone" }, { "E", "/e ", "EMOTE", "Emote" } }

-- every chat window the game has, the whisper windows it opens on the fly too (CHAT_FRAMES), with its id
local function Windows(fn)
	local names = rawget(_G, "CHAT_FRAMES")
	if type(names) == "table" and #names > 0 then
		for _, name in ipairs(names) do
			local f = type(name) == "string" and _G[name]
			if f and f.GetID then
				fn(f, f:GetID())
			end
		end
		return
	end
	for i = 1, tonumber(rawget(_G, "NUM_CHAT_WINDOWS")) or 10 do
		local f = _G["ChatFrame" .. i]
		if f then
			fn(f, i)
		end
	end
end

-- a window's name, shown and docked (the game's own reading, which knows its whisper windows)
local function WindowInfo(id)
	local get = rawget(_G, "FCF_GetChatWindowInfo") or _G.GetChatWindowInfo
	local ok, name, _, _, _, _, _, shown, _, docked = pcall(get, id)
	if not ok then
		return nil
	end
	return Plain(name), Plain(shown), Plain(docked)
end

-- the time a line came in, as the header shows it (made once a minute)
local clockAt, clockText = -1, ""
local function Clock()
	local m = math.floor(time() / 60)
	if m ~= clockAt then
		clockAt, clockText = m, date("%H:%M")
	end
	return clockText
end

--------------------------------------------------------------------------------
-- The lines: one ring of records per tab, made once and written over
--------------------------------------------------------------------------------

local function Buffer(frame)
	local buf = View.bufs[frame]
	if not buf then
		buf = { items = {}, count = 0, last = 0 }
		View.bufs[frame] = buf
	end
	return buf
end

-- the j-th newest record (0: the newest), or nil
local function Nth(buf, j)
	if j >= buf.count then
		return nil
	end
	return buf.items[((buf.last - 1 - j) % CAP) + 1]
end

local function ClassColour(guid)
	guid = Plain(guid)
	if type(guid) ~= "string" or guid == "" or type(GetPlayerInfoByGUID) ~= "function" then
		return nil
	end
	local ok, _, class = pcall(GetPlayerInfoByGUID, guid)
	class = ok and Plain(class)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then
		return c.r, c.g, c.b
	end
	return nil
end

-- the channel's short tag and its name ("[T] Trade"), from the Chat module's tags
local function Tag(chatType, args)
	local channel = chatType == "CHANNEL" and Plain(args[9]) or nil
	local short, hex = nil, nil
	if M.ShortTag then
		short, hex = M.ShortTag(chatType, channel)
	end
	local name = TYPE_NAME[chatType]
	if chatType == "CHANNEL" then
		name = type(channel) == "string" and channel:gsub("%s*%-.*$", "") or nil
	end
	if not (short or name) then
		return nil
	end
	local text = (short and ("[" .. short .. "]") or "") .. ((short and name) and " " or "") .. (name or "")
	return hex and ("|cff" .. hex .. text .. "|r") or text
end

-- the message as the game's own line shows it: {star} and the like as their icons (its MessageFormatter's step)
local function Expand(msg, chatType, args)
	if Secret(msg) or type(msg) ~= "string" then
		return msg
	end
	local util, info = ChatFrameUtil, C_ChatInfo
	if not (util and util.GetChatCategory and util.CanChatGroupPerformExpressionExpansion and info
		and info.ReplaceIconAndGroupExpressions) then
		return msg
	end
	local okG, group = pcall(util.GetChatCategory, chatType)
	local okC, can = pcall(util.CanChatGroupPerformExpressionExpansion, okG and group or chatType)
	local ok, out = pcall(info.ReplaceIconAndGroupExpressions, msg, Plain(args[17]), not (okC and Plain(can)))
	return (ok and not Secret(out) and type(out) == "string") and out or msg
end

-- a line as the game added it (the Chat module's AddMessage post-hook)
function View.Line(frame, text, r, g, b, _, _, _, event, args)
	if not View.on then
		return
	end
	local buf = View.bufs[frame]
	if not buf then
		return   -- (a window not on the rail)
	end
	buf.last = buf.last % CAP + 1
	local rec = buf.items[buf.last]
	if not rec then
		rec = {}
		buf.items[buf.last] = rec
	end
	if buf.count < CAP then
		buf.count = buf.count + 1
	end
	r, g, b = Plain(r), Plain(g), Plain(b)
	rec.r, rec.g, rec.b = r or 1, g or 1, b or 1
	rec.body, rec.headed, rec.key, rec.name, rec.tag = text, false, nil, nil, nil
	rec.at, rec.time = GetTime(), Clock()
	if type(event) == "string" and type(args) == "table" then
		local chatType = event:sub(10)   -- CHAT_MSG_<type>
		if HEADED[chatType] then
			local sender = args[2]
			rec.headed, rec.body = true, Expand(args[1], chatType, args)
			local name = Plain(sender)
			if type(name) == "string" then
				if chatType ~= "BN_WHISPER" and chatType ~= "BN_WHISPER_INFORM" and type(Ambiguate) == "function" then
					name = Ambiguate(name, "short")
				end
				rec.key = chatType .. ":" .. tostring(Plain(args[8]) or "") .. ":" .. name
				local shown = (chatType == "WHISPER_INFORM" or chatType == "BN_WHISPER_INFORM") and ("To " .. name) or name
				local lineID = Plain(args[11])
				if chatType:sub(1, 3) ~= "BN_" and chatType:sub(1, 8) ~= "MONSTER_" and type(sender) == "string" then
					shown = "|Hplayer:" .. sender .. ":" .. tostring(lineID or 0) .. ":" .. chatType .. "|h" .. shown .. "|h"
				end
				rec.name = shown
			else
				rec.name = sender   -- (secret: shown as it is, in the line's colour, never in a run)
			end
			local cr, cg, cb = ClassColour(args[12])
			rec.nr, rec.ng, rec.nb = cr or rec.r, cg or rec.g, cb or rec.b
			rec.tag = Tag(chatType, args)
		end
	end
	if View.seeding then
		return
	end
	if frame ~= View.tab then
		View.unread[frame] = (View.unread[frame] or 0) + 1
		View.Counts()
		return
	end
	if View.offset > 0 then
		View.offset = math.min(View.offset + 1, buf.count - 1)   -- (scrolled back: the view holds still)
	end
	View.Soon()
end

-- the game's own lines a tab starts with (as lines alone: their events are gone)
local function Seed(frame)
	local ok, n = pcall(frame.GetNumMessages, frame)
	n = ok and Plain(n)
	if type(n) ~= "number" then
		return
	end
	View.seeding = true
	for j = math.max(1, n - SEED + 1), n do
		local okM, text, r, g, b = pcall(frame.GetMessageInfo, frame, j)
		if okM then
			View.Line(frame, text, r, g, b)   -- (a secret line shown as it is)
		end
	end
	View.seeding = false
end

--------------------------------------------------------------------------------
-- The rows: laid by anchors, newest at the foot
--------------------------------------------------------------------------------

local function Font(fs, scale)
	local ok, face, size, flags = pcall(ChatFrame1.GetFont, ChatFrame1)
	if ok and Plain(face) and Plain(size) then
		fs:SetFont(face, size * (scale or 1), flags or "")
	end
end

local function Row(k)
	local row = View.rows[k]
	if not row then
		local area = View.area
		row = {}
		row.body = area:CreateFontString(nil, "OVERLAY")
		row.name = area:CreateFontString(nil, "OVERLAY")
		row.tag = area:CreateFontString(nil, "OVERLAY")
		row.time = area:CreateFontString(nil, "OVERLAY")
		for _, fs in ipairs({ row.body, row.name, row.tag, row.time }) do
			fs:SetJustifyH("LEFT")
			fs:SetJustifyV("TOP")
		end
		row.body:SetWordWrap(true)
		row.time:SetJustifyH("RIGHT")
		View.rows[k] = row
		View.RowFonts(row)
	end
	return row
end

function View.RowFonts(row)
	Font(row.body)
	Font(row.name)
	Font(row.tag, 0.85)
	Font(row.time, 0.85)
	W.Paint(row.time, "text", "text")
end

local function HideRow(row)
	row.body:Hide()
	row.name:Hide()
	row.tag:Hide()
	row.time:Hide()
end

local function SameRun(newer, older)
	return newer and older and newer.headed and older.headed and newer.key ~= nil and newer.key == older.key
		and (newer.at - older.at) < RUN_SECONDS
end

function View.Lay()
	View.pending = false
	local buf = View.tab and View.bufs[View.tab]
	local area = View.area
	if not (buf and area) then
		return
	end
	local okW, width = pcall(area.GetWidth, area)
	width = okW and Plain(width) or 300
	local prev, prevX, gap = nil, 0, 0
	local k = 0
	local j = View.offset
	while k < LAY do
		local rec = Nth(buf, j)
		if not rec then
			break
		end
		k = k + 1
		local row = Row(k)
		local x = rec.headed and INDENT or 0
		local body = row.body
		body:ClearAllPoints()
		if prev then
			body:SetPoint("BOTTOMLEFT", prev, "TOPLEFT", x - prevX, gap)
		else
			body:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", x, 2)
		end
		body:SetWidth(math.max(40, width - x - 4))
		pcall(body.SetText, body, rec.body)
		body:SetTextColor(rec.r, rec.g, rec.b)
		body:Show()
		local older = Nth(buf, j + 1)
		if rec.headed and not SameRun(rec, older) then
			-- the run's first line: its header over it
			local name, tag, time = row.name, row.tag, row.time
			name:ClearAllPoints()
			name:SetPoint("BOTTOMLEFT", body, "TOPLEFT", -x, GAP_LINE)
			pcall(name.SetText, name, rec.name)
			name:SetTextColor(rec.nr or rec.r, rec.ng or rec.g, rec.nb or rec.b)
			name:Show()
			tag:ClearAllPoints()
			tag:SetPoint("BOTTOMLEFT", name, "BOTTOMRIGHT", 6, 1)
			tag:SetText(rec.tag or "")
			tag:SetShown(rec.tag ~= nil)
			time:ClearAllPoints()
			time:SetPoint("BOTTOMRIGHT", body, "TOPRIGHT", 0, GAP_LINE + 1)
			time:SetText(rec.time or "")
			time:Show()
			prev, prevX, gap = name, 0, GAP_RUN
		else
			row.name:Hide()
			row.tag:Hide()
			row.time:Hide()
			prev, prevX = body, x
			if SameRun(rec, older) then
				gap = GAP_LINE
			elseif not rec.headed and older and not older.headed then
				gap = GAP_PLAIN   -- (the game's notices, loot, prints: one under the other)
			else
				gap = GAP_RUN
			end
		end
		j = j + 1
	end
	for i = k + 1, #View.rows do
		HideRow(View.rows[i])
	end
end

-- laid again on the next frame (a burst of lines once)
function View.Soon()
	if View.pending then
		return
	end
	View.pending = true
	C_Timer.After(0, View.Lay)
end

function View.Scroll(delta)
	local buf = View.tab and View.bufs[View.tab]
	if not buf then
		return
	end
	local step = IsShiftKeyDown() and 10 or 3
	View.offset = math.max(0, math.min(View.offset + delta * step, math.max(0, buf.count - 1)))
	View.Lay()
end

--------------------------------------------------------------------------------
-- The rail: the game's chat windows by name, the open one lit
--------------------------------------------------------------------------------

local function GlyphFor(name)
	name = type(name) == "string" and name:lower() or ""
	if name:find("combat") then
		return "sword"
	elseif name:find("loot") then
		return "bag"
	elseif name:find("guild") then
		return "flag"
	elseif name:find("whisper") then
		return "reply"
	elseif name:find("trade") then
		return "channels"
	end
	return "chat"
end

local function KitRim(b)
	local Kit = MelloUI.Kit
	if Kit and Kit.IsCovered and Kit:IsCovered("chat") then
		b:SetKit(Kit)
	end
end

-- a count on a button's rim (a dark disc, the number in gold)
local function Count(b)
	if not b.countText then
		local disc = b:CreateTexture(nil, "OVERLAY", nil, 5)
		disc:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
		disc:SetSize(13, 13)
		disc:SetPoint("CENTER", b, "TOPRIGHT", -3, -3)
		W.Paint(disc, "innerPanel", "vertex", 0.95)
		local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetPoint("CENTER", disc, "CENTER", 0, 0)
		W.Paint(fs, "selectedTrim", "text")
		b.countDisc, b.countText = disc, fs
	end
	return b.countDisc, b.countText
end

local function SetCount(b, n)
	local disc, fs = Count(b)
	local show = n and n > 0
	disc:SetShown(show)
	fs:SetShown(show)
	if show then
		fs:SetText(n > 99 and "99" or n)
	end
end

local TabClick = Perf.Shared("OnClick on a chat view tab", function(b)
	if b.chatFrame ~= View.tab then
		MelloUI:PlayUISound("tab")
	end
	View.Select(b.chatFrame)
end, "script")

local TabEnter = Perf.Shared("OnEnter on a chat view tab", function(b)
	W.ShowTooltip(b, b.tabName or "", "Show this chat window's lines.")
end, "script")

function View.Rail()
	local frame = View.frame
	wipe(View.order)
	Windows(function(f, i)
		local name, shown, docked = WindowInfo(i)
		if type(name) == "string" and name ~= "" and (i == 1 or shown or docked) then
			View.order[#View.order + 1] = f
			local t = View.tabs[f]
			if not t then
				local b = W.GlyphButton(frame, ICON, GlyphFor(name))
				b.chatFrame = f
				Perf.SetScript(b, "OnClick", TabClick)
				Perf.SetScript(b, "OnEnter", TabEnter)
				Perf.SetScript(b, "OnLeave", W.TipLeave)
				KitRim(b)
				local label = W.Text(frame, "GameFontHighlight", name, "text")
				label:SetPoint("LEFT", b, "RIGHT", 6, 0)
				t = { button = b, label = label }
				View.tabs[f] = t
				if not View.bufs[f] then
					Buffer(f)
					Seed(f)
				end
			end
			t.button.tabName = name
			t.label:SetText(name)
		end
	end)
	for f, t in pairs(View.tabs) do
		local shown = false
		for idx, o in ipairs(View.order) do
			if o == f then
				shown = true
				t.button:ClearAllPoints()
				t.button:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -(8 + (idx - 1) * (ICON + 8)))
			end
		end
		t.button:SetShown(shown)
		t.label:SetShown(shown)
	end
	if not (View.tab and View.tabs[View.tab]) then
		View.tab = View.order[1]
	end
	View.Lit()
	View.Counts()
end

function View.Lit()
	for f, t in pairs(View.tabs) do
		local on = f == View.tab
		W.Paint(t.label, on and "selectedTrim" or "text", "text")
		W.Paint(t.button.icon, on and "selectedTrim" or "text", "vertex")
		if on then
			View.mark:ClearAllPoints()
			View.mark:SetPoint("TOP", t.button, "TOP", 0, 0)
			View.mark:SetPoint("BOTTOM", t.button, "BOTTOM", 0, 0)
			View.mark:SetPoint("LEFT", View.divider, "LEFT", -1, 0)
		end
	end
end

function View.Counts()
	for f, t in pairs(View.tabs) do
		SetCount(t.button, f ~= View.tab and View.unread[f] or 0)
	end
end

function View.Select(frame)
	if not View.tabs[frame] then
		return
	end
	View.tab, View.offset = frame, 0
	View.unread[frame] = 0
	View.Lit()
	View.Counts()
	View.Lay()
end

--------------------------------------------------------------------------------
-- The row of buttons: who you speak to, then Channels, Friends, the fight history, the settings
--------------------------------------------------------------------------------

local function Open(slash)
	local open = ChatFrameUtil and ChatFrameUtil.OpenChat
	if type(open) == "function" then
		open(slash, ChatFrame1)
	end
end

local PickClick = Perf.Shared("OnClick on a chat view pick", function(b)
	Open(b.slash)
end, "script")

local ButtonEnter = Perf.Shared("OnEnter on a chat view button", function(b)
	W.ShowTooltip(b, b.tipTitle or "", b.tipText)
end, "script")

local ACTIONS = {
	{ "channels", "Channels", "The chat channels you are in.", function()
		local toggle = rawget(_G, "ToggleChannelFrame")
		if type(toggle) == "function" then
			toggle()
		end
	end },
	{ "friends", "Friends", "Your friends list.", function()
		local toggle = rawget(_G, "ToggleFriendsFrame")
		if type(toggle) == "function" then
			toggle()
		end
	end },
	{ "chart", "Fight History", "The damage meter's fights.", function()
		local meter = MelloUI:GetModule("Meter")
		if meter and type(meter.ToggleHistory) == "function" then
			meter.ToggleHistory()
		end
	end },
	{ "cog", "Chat Settings", "MelloUI's chat settings.", function()
		MelloUI:OpenConfig("chatpanel")
	end },
}

local ActionClick = Perf.Shared("OnClick on a chat view button", function(b)
	pcall(b.action)   -- (the windows it opens play their own sounds)
end, "script")

local function ButtonRow(frame)
	View.buttons = {}
	local n = #PICKS + #ACTIONS
	for i = 1, n do
		local pick, act = PICKS[i], ACTIONS[i - #PICKS]
		local b = W.GlyphButton(frame, LETTER, act and act[1] or nil)
		if pick then
			local letter = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			letter:SetPoint("CENTER", b, "CENTER", 0, 0)
			local info = ChatTypeInfo and ChatTypeInfo[pick[3]]
			if info and Plain(info.r) then
				letter:SetTextColor(info.r, info.g, info.b)
			end
			letter:SetText(pick[1])
			b.slash, b.tipTitle, b.tipText = pick[2], pick[4], "Speak in " .. pick[4]:lower() .. " (" .. pick[2] .. ")."
			Perf.SetScript(b, "OnClick", PickClick)
		else
			b.action, b.tipTitle, b.tipText = act[4], act[2], act[3]
			Perf.SetScript(b, "OnClick", ActionClick)
		end
		Perf.SetScript(b, "OnEnter", ButtonEnter)
		Perf.SetScript(b, "OnLeave", W.TipLeave)
		KitRim(b)
		View.buttons[i] = b
	end
end

local function PlaceButtons()
	local frame = View.frame
	local okW, width = pcall(frame.GetWidth, frame)
	width = okW and Plain(width) or 400
	local n = #View.buttons
	local step = (width - 20) / n
	for i, b in ipairs(View.buttons) do
		b:ClearAllPoints()
		b:SetPoint("CENTER", frame, "BOTTOMLEFT", 10 + step * (i - 0.5), ROW_H / 2)
	end
end

--------------------------------------------------------------------------------
-- The frame, and the game's chat out of sight under it
--------------------------------------------------------------------------------

local function Build()
	if View.frame then
		return
	end
	local frame = CreateFrame("Frame", "MelloUIChatView", UIParent)
	frame:SetFrameStrata(ChatFrame1:GetFrameStrata())
	frame:SetFrameLevel(ChatFrame1:GetFrameLevel() + 5)
	frame:SetPoint("TOPLEFT", ChatFrame1, "TOPLEFT", -PAD, PAD + 2)
	frame:SetPoint("BOTTOMRIGHT", ChatFrame1, "BOTTOMRIGHT", PAD, -(ROW_H + PAD))
	W.Panel(frame, { on = true, alpha = 0.82 })
	View.frame = frame
	-- the rail's divider, the open tab's mark on it
	local divider = W.Solid(frame, "ARTWORK", "border")
	divider:SetWidth(1)
	divider:SetPoint("TOPLEFT", frame, "TOPLEFT", RAIL_W, -8)
	divider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", RAIL_W, ROW_H + 4)
	View.divider = divider
	local mark = W.Solid(frame, "OVERLAY", "selectedTrim")
	mark:SetWidth(3)
	View.mark = mark
	-- the row's hairline
	local hair = W.Solid(frame, "ARTWORK", "border")
	hair:SetHeight(1)
	hair:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, ROW_H)
	hair:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, ROW_H)
	-- the lines' holder: clips, takes the wheel and the links
	local area = CreateFrame("Frame", nil, frame)
	area:SetPoint("TOPLEFT", frame, "TOPLEFT", RAIL_W + 10, -8)
	area:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, ROW_H + 6)
	area:SetClipsChildren(true)
	area:EnableMouseWheel(true)
	area:SetScript("OnMouseWheel", function(_, delta)
		View.Scroll(delta)
	end)
	pcall(area.SetHyperlinksEnabled, area, true)
	area:SetScript("OnHyperlinkClick", function(_, link, text, button)
		if not Secret(link) and type(SetItemRef) == "function" then
			pcall(SetItemRef, link, text, button, ChatFrame1)
		end
	end)
	area:SetScript("OnSizeChanged", function()
		View.Soon()
		PlaceButtons()
	end)
	View.area = area
	ButtonRow(frame)
	PlaceButtons()
	-- the combat log adds its lines through its own window, which the Chat module's hook leaves out
	local log = rawget(_G, "COMBATLOG")
	if log and log.AddMessage then
		hooksecurefunc(log, "AddMessage", function(f, text, r, g, b)
			if View.on then
				View.Line(f, text, r, g, b)
			end
		end)
	end
	-- a new palette: the rows' and buttons' colours again (the rest is painted by key)
	MelloUI:On("palette", function()
		if View.on then
			View.Lit()
		end
	end, "Chat view")
end

local saved = {}   -- [edit box] = { level, points }: how the view found it

-- the line you type in: over the lines' foot, above the view; put back as it was when the view goes
local function PlaceEditBoxes(on)
	Windows(function(f)
		local box = f.editBox
		if not box then
			return
		end
		pcall(box.SetIgnoreParentAlpha, box, on)
		local was = saved[box]
		if on then
			if not was then
				was = { level = box:GetFrameLevel(), points = {} }
				for p = 1, box:GetNumPoints() do
					was.points[p] = { box:GetPoint(p) }
				end
				saved[box] = was
			end
			box:SetFrameLevel(View.frame:GetFrameLevel() + 20)
			box:ClearAllPoints()
			box:SetPoint("BOTTOMLEFT", View.area, "BOTTOMLEFT", -4, -4)
			box:SetPoint("BOTTOMRIGHT", View.area, "BOTTOMRIGHT", 4, -4)
		elseif was then
			box:SetFrameLevel(was.level)
			box:ClearAllPoints()
			for _, pt in ipairs(was.points) do
				box:SetPoint(unpack(pt))
			end
			saved[box] = nil
		end
	end)
	if not on and M.SetEditBoxOnTop then
		M.SetEditBoxOnTop(M.db and M.db.editBoxTop)   -- (the Chat module's own place again)
	end
end

local COLUMN = { "ChatFrameMenuButton", "ChatFrameChannelButton", "QuickJoinToastButton", "MelloUIFightHistoryButton",
	"ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton" }

-- the Fader's chat fade on the view while the game's windows are out of sight under it (Fader.lua ChatFrames)
local function Regather()
	local Fader = MelloUI.Fader
	if Fader and Fader.Regather then
		Fader:Regather("chat")
	end
end

local held = {}   -- [game frame] = { alpha, mouse, wheel }: how the view found it, given back as it was

-- a game frame out of sight: alpha 0, no mouse (its own state noted the first time)
local function Hold(f, wheel)
	if not (f and f.SetAlpha) then
		return
	end
	if not held[f] then
		local okA, a = pcall(f.GetAlpha, f)
		local okM, m = pcall(f.IsMouseEnabled, f)
		local h = { alpha = okA and Plain(a) or 1, mouse = okM and Plain(m) }
		if wheel then
			local okW, w = pcall(f.IsMouseWheelEnabled, f)
			h.wheel = okW and Plain(w)
		end
		held[f] = h
	end
	f:SetAlpha(0)
	f:EnableMouse(false)
	if wheel then
		pcall(f.EnableMouseWheel, f, false)
	end
end

local function Let(f)
	local h = f and held[f]
	if not h then
		return
	end
	held[f] = nil
	f:SetAlpha(h.alpha)
	if h.mouse ~= nil then
		f:EnableMouse(h.mouse)
	end
	if h.wheel ~= nil then
		pcall(f.EnableMouseWheel, f, h.wheel)
	end
end

local function HideGame(on)
	if on then
		View.hiding = true   -- (first: the Fader lets the game's windows go, ChatPanel's no-fade stands aside)
		Regather()
	end
	local Do = on and Hold or Let
	Windows(function(f, i)
		Do(f, true)
		Do(rawget(_G, "ChatFrame" .. i .. "Tab"))
	end)
	Do(rawget(_G, "GeneralDockManager"))
	for _, name in ipairs(COLUMN) do
		Do(rawget(_G, name))
	end
	if not on then
		View.hiding = false   -- (last: the game's windows back as they were before the Fader takes them again)
		Regather()
	end
end

function View.Wanted()
	return M.isEnabled and M.db ~= nil and M.db.view == "minimal"
end

-- on, off, or laid again (the Chat module's Apply, a setting, a whisper window opened)
function View.Apply()
	local want = View.Wanted()
	if want then
		Build()
		local was = View.on
		View.on = true
		View.frame:Show()
		View.Rail()
		HideGame(true)
		PlaceEditBoxes(true)
		if not was then
			View.offset = 0
		end
		View.Lay()
	elseif View.on then
		View.on = false
		HideGame(false)
		PlaceEditBoxes(false)
		View.frame:Hide()
	end
end
