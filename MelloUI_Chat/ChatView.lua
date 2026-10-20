--------------------------------------------------------------------------------
-- MelloUI - Chat View (0.23.0; docs/plans/chat-redesign.md, stages 2, 3, 5 and 6)
--
-- The user, 2026-10-14: "a minimalistic version where its less visual clutter, minimalistic, functional but also
-- true to the artstyle" -- picked: frame A (a rail of round tabs with their names, the lines on the dark inner panel,
-- one row of twelve round buttons under them) and the lines laid out as 3 (the name, its channel's short tag and the
-- time on one line, the message under it; a run from one person under one name); "parchment as an option".
--
-- MelloUI's own view of the chat, the game's chat windows alive but out of sight under it (Chat View: Minimal):
--   * the lines are the game's own: the Chat module's post-hook on each window's AddMessage hands every line here as
--     the game adds it -- through every filter, other addons' prints too -- with the chat event and its whole
--     argument pack when it came from one (the game's handler calls AddMessage(msg, r, g, b, id, accessID, typeID,
--     event, eventArgs), ChatFrameOverrides.lua): the sender, the channel and the GUID for the header. The combat
--     log's window adds its lines through its own AddMessage (Blizzard_CombatLog), hooked here
--   * each tab on the rail is one of the game's chat windows (FCF_GetChatWindowInfo, read only) and shows the lines
--     that window got; nothing of the game's dock or tabs is driven from here (that tainted the chat pipeline before:
--     the whisper popup's note), the rail switches this view only. The last tab is Whispers: the whisper window
--     (ChatWhispers.lua), its count popping on the rim as a whisper comes in, the rim lit once. A right click on a tab
--     is the game's own on that window's tab (its menu: rename, a new window, close, lock, font size, settings),
--     through a secure stand-in, so the game's code runs it untainted; windows made, renamed, closed or docked come
--     and go on the rail
--   * the rows are laid out by anchors alone, each under the one before, the newest at the foot, clipped by the
--     lines' holder and scrolled by message: a line can be SECRET (chat messaging lockdown) and then nothing of its
--     size can be read (the spike of 2026-10-14) -- the game lays the rows out, this file reads no size of a line
--   * the game's windows held at alpha 0 without the mouse, each given back as it was (the chat fade touches only
--     tabs and textures; ChatPanel's no-fade and the Fader's chat fade stand aside: MelloUI.ChatView.hiding); the
--     line you type in shown on its own over the lines' foot, the lines rising over it while it shows; the row's
--     S P R I G Y W E open it on that chat type the game's way (ChatFrameUtil.OpenChat: the edit box runs secure
--     commands before it reads the chat type -- a /use typed after still casts, checked in game 2026-10-14)
--   * the chat's Parchment (its own switch, UI Modifications' parchment_chat: Kit.ownParchments, the reskin on or off;
--     the one look, 2026-10-15) lays the kit's parchment sheet under the view and the whisper window, every colour in
--     the chat's inks (Chat.lua ChatInk for a line's kind, QuestInk for names, links and tags), the chat's parchment
--     face without outline or shadow on the paper; the Background's None (your pick) leaves the panel clear;
--     Background Opacity is the panel's
-- Nothing is made while the view is off; the rows and their records are made once and used again (no table per line).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_Chat (ChatView)")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
local Secret = MelloUI.Safe.IsSecret
local Plain = MelloUI.Safe.Value
local Num = MelloUI.Safe.Number
local W = MelloUI.Widgets
local M = MelloUI:GetModule("Chat")

local View = { on = false, hiding = false, tab = nil, offset = 0, bufs = {}, unread = {}, rows = {}, tabs = {},
	order = {}, pending = false, railOffset = 0, paper = false, pixel = 0 }
M.View = View
MelloUI.ChatView = View   -- (ChatPanel's no-fade and the Fader's chat fade ask it)

-- UI units
local RAIL_W, ROW_H, ICON, LETTER, PAD = 112, 34, 24, 24, 6
local GAP_RUN, GAP_LINE, GAP_PLAIN, INDENT, RUN_SECONDS = 6, 1, 2, 10, 120
local CAP, LAY = 300, 40          -- lines kept per tab; rows laid at most (the holder clips what does not fit)
local SEED = 60                   -- the game's own lines a tab starts with when the view comes on
local SAVE_LINES = 150            -- lines kept over a logout per tab (MelloUIChatHistory)
local BOX_LIFT = 28               -- the line you type in, when its height cannot be read
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"   -- (the widgets' round mask)

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
local TEXT = {
	tabTip = "Show this chat window's lines.\nRight-click: the window's menu (rename it, make a new window -- on "
		.. "General --, close it, its font size, its settings: which chat and channels it shows).\nDrag it up or down "
		.. "to move it on the rail.",
	channelTip = "Your channel's lines (/%d before a line speaks in it).\nRight-click: speak in it, or leave it.\n"
		.. "Drag it up or down to move it on the rail.",
	speakIn = "Speak In %s",
	leave = "Leave %s",
	leaveAsk = "Leave the channel %s? Its lines stop coming until you /join it again.",
	whispers = "Whispers",
	whispersTip = "Your whisper conversations, in one window that opens above the chat. Click again to fold it away."
		.. "\nDrag it up or down to move it on the rail.",
}
-- the links that show a tooltip under the pointer (the game's own SetHyperlink kinds)
local TIP_LINKS = { item = true, spell = true, enchant = true, quest = true, achievement = true, currency = true,
	talent = true }

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
function View.Clock()
	local m = math.floor(time() / 60)
	if m ~= clockAt then
		clockAt, clockText = m, date("%H:%M")
	end
	return clockText
end

--------------------------------------------------------------------------------
-- Colours: the palette's, or the chat's inks on the paper (the whisper window's too)
--------------------------------------------------------------------------------

local function Pal(key)
	local pal = (MelloUI.Look and MelloUI.Look.Palette and MelloUI.Look.Palette()) or MelloUI.Palette
	local c = pal[key] or pal.text
	return c[1], c[2], c[3]
end

-- a palette key on a string in a field of its own (an input box: dark whatever lies round it), never inked
function View.FieldColour(fs, key)
	fs:SetTextColor(Pal(key))
end

-- a palette key on a string (set here, not through the kit's paint: its colour turns to ink on the paper)
function View.Colour(fs, key)
	local r, g, b = Pal(key)
	View.InkColour(fs, r, g, b)
end

-- any colour on a string, its sheet ink on the paper (a name in its class colour)
function View.InkColour(fs, r, g, b)
	if View.paper and MelloUI.QuestInk then
		r, g, b = MelloUI.QuestInk.InkOf(r, g, b, true)
	end
	fs:SetTextColor(r, g, b)
end

-- a line's chat colour, its chat ink on the paper (the chat's own: a whisper's ink is the whisper's)
function View.ChatColour(fs, r, g, b)
	if View.paper and M.ChatInk then
		r, g, b = M.ChatInk(r, g, b)
	end
	fs:SetTextColor(r, g, b)
end

-- the colour codes in a text, inked on the paper; a secret text as it is
function View.Codes(text)
	if View.paper and MelloUI.QuestInk and not Secret(text) and type(text) == "string" then
		return MelloUI.QuestInk.InkCodes(text, true)
	end
	return text
end

-- (on the paper) a name's class gem: QuestInk's one inline gem in the class's true colour, before the name in ink --
-- the chat's own way on its parchment (Chat.lua: names on the paper; the user, 2026-10-15: "the names are missing the
-- Squares that represent their Class by color on the parchment"); "" off the paper or with the class not known
function View.Gem(r, g, b, fs)
	local QI = MelloUI.QuestInk
	if not (View.paper and r and QI and QI.GemCode) then
		return ""
	end
	local ok, _, size = pcall(fs.GetFont, fs)
	return QI.GemCode(r, g, b, ok and Num(size) or nil) or ""
end

-- a soft shadow on the dark panel, none on the paper
function View.Shadow(fs)
	if View.paper then
		fs:SetShadowOffset(0, 0)
	else
		fs:SetShadowOffset(1, -1)
		fs:SetShadowColor(0, 0, 0, 0.9)
	end
end

-- the chat's font (the open tab's window's -- each window has its size in the game's tab menu -- or `from`'s: its
-- face, size and flags), at a share of its size. On the paper the chat's parchment face and size (the Fonts module's
-- Chat On Parchment, as the painted chat's windows wear it there) without an outline (the parchment ink rule): the
-- same with the reskin on or off -- without the painted cover the game's windows are not on paper (one look)
function View.Font(fs, scale, from)
	local src = from or (type(View.tab) == "table" and View.tab) or ChatFrame1   -- (a channel's tab: General's)
	local ok, face, size, flags = pcall(src.GetFont, src)
	if not (ok and Plain(face) and Num(size)) then
		return
	end
	flags = Plain(flags) or ""
	if View.paper then
		flags = ""
		local fonts = MelloUI:GetModule("Fonts")
		if fonts and fonts.isEnabled and fonts.ChatWindowFont then
			local okP, pface, psize = pcall(fonts.ChatWindowFont, fonts, src, true)
			if okP and Plain(pface) and Num(psize) then
				face, size = pface, psize
			end
		end
	end
	fs:SetFont(face, size * (scale or 1), flags)
end

-- (one look: nothing of the view follows the chat cover -- the painted kit, Oldschool's -- any more: the rims and
-- the title face are everyone's, the paper is the chat's Parchment alone, Chat.lua's M.ChatInked)

-- the round rims' kit (one look, the user's pick 9, 2026-10-15): the kit's roundslot rim for everyone, as the Quest
-- Tracker's marks and the Quest List's markers wear it, whatever the chat cover (until then only while it covered)
-- (0.25.0) the kit's rim only while Oldschool dresses the chat; else MelloUI's own buttons of its icon set (the
-- kit's roundslot rim for everyone until then)
function View.RimKit()
	return MelloUI.Widgets.KitFor("chat")
end

function View.KitRim(b)
	b:SetKit(View.RimKit())
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
	rec.cr, rec.cg, rec.cb = nil, nil, nil
	rec.at, rec.time, rec.ts = GetTime(), View.Clock(), time()
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
			rec.cr, rec.cg, rec.cb = cr, cg, cb   -- (the gem's on the paper: nil, no gem)
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
	if View.offset > 0 or View.pixel > 0 then
		View.offset = math.min(View.offset + 1, buf.count - 1)   -- (scrolled back: the view holds still)
	end
	View.Soon()
end

--------------------------------------------------------------------------------
-- The history (0.23.1; the user, 2026-10-15: "the chat needs its history saved aswell as the whisper window"): each
-- tab's newest lines (SAVE_LINES; the combat log's none) kept over a logout or a /reload, per character
-- (MelloUIChatHistory, MelloUI.toc's), written at PLAYER_LOGOUT -- only while the view was on this session, else the
-- kept history stays as it was -- and laid back into a tab's ring as the tab is made, before the game's own lines of
-- this session. A SECRET line is never kept. A line's age comes back with it (its clock, `ts`: runs are not joined
-- across the gap).
--------------------------------------------------------------------------------

local function History()
	local hist = rawget(_G, "MelloUIChatHistory")
	if type(hist) ~= "table" then
		hist = {}
		_G.MelloUIChatHistory = hist
	end
	return hist
end
View.History = History   -- (the whisper window's)

-- the kept lines of `saveKey` laid into the ring of `bufKey` (oldest first)
local function Restore(bufKey, saveKey)
	local hist = rawget(_G, "MelloUIChatHistory")
	local list = type(hist) == "table" and type(hist.tabs) == "table" and hist.tabs[saveKey]
	if type(list) ~= "table" then
		return
	end
	local buf = Buffer(bufKey)
	local now, clock = GetTime(), time()
	for _, s in ipairs(list) do
		if type(s) == "table" and type(s.tx) == "string" then
			buf.last = buf.last % CAP + 1
			local rec = buf.items[buf.last]
			if not rec then
				rec = {}
				buf.items[buf.last] = rec
			end
			if buf.count < CAP then
				buf.count = buf.count + 1
			end
			rec.body, rec.r, rec.g, rec.b = s.tx, Num(s.r) or 1, Num(s.g) or 1, Num(s.b) or 1
			rec.headed, rec.key, rec.name, rec.tag, rec.time = s.h and true or false, s.k, s.n, s.tg, s.tm
			rec.ts = Num(s.ts)
			rec.at = now - math.max(0, clock - (rec.ts or clock))
			rec.nr, rec.ng, rec.nb = Num(s.nr), Num(s.ng), Num(s.nb)
			rec.cr, rec.cg, rec.cb = Num(s.cr), Num(s.cg), Num(s.cb)
		end
	end
end

-- a line as kept (nil: a secret one, or none)
local function Kept(rec)
	if not rec or Secret(rec.body) or Secret(rec.name) or type(rec.body) ~= "string" then
		return nil
	end
	return { tx = rec.body, r = rec.r, g = rec.g, b = rec.b, h = rec.headed or nil, k = rec.key, n = rec.name,
		tg = rec.tag, tm = rec.time, ts = rec.ts, nr = rec.nr, ng = rec.ng, nb = rec.nb, cr = rec.cr, cg = rec.cg,
		cb = rec.cb }
end

-- every tab's newest lines (and the whisper window's conversations) into the history: at logout
function View.SaveHistory()
	if not View.frame then
		return   -- (the view never on this session: the kept history as it was)
	end
	local hist = History()
	local tabs = {}
	local log = rawget(_G, "COMBATLOG")
	for bufKey, t in pairs(View.tabs) do
		local buf = View.bufs[bufKey]
		if buf and t.key and bufKey ~= log then
			local list = {}
			for j = math.min(buf.count, SAVE_LINES) - 1, 0, -1 do
				local kept = Kept(Nth(buf, j))
				if kept then
					list[#list + 1] = kept
				end
			end
			tabs[t.key] = list
		end
	end
	hist.tabs = tabs
	local WV = View.Whispers
	if WV and WV.Save then
		WV.Save(hist)
	end
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

local function RowFonts(row)
	View.Font(row.body)
	View.Font(row.name)
	View.Font(row.tag, 0.85)
	View.Font(row.time, 0.85)
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
		RowFonts(row)
	end
	return row
end

-- the chat's font again on every row (and the whisper window's bubbles): its size changed, or the view came on
function View.Fonts()
	for _, row in ipairs(View.rows) do
		RowFonts(row)
	end
	-- the rail's names (the Chat Size slider's) and the tabs' spacing with them
	for _, t in pairs(View.tabs) do
		View.Font(t.label, 1, ChatFrame1)
	end
	if View.whisperTab then
		View.Font(View.whisperTab.label, 1, ChatFrame1)
	end
	if View.PlaceRail then
		View.PlaceRail()
	end
	local WV = View.Whispers
	if WV and WV.Fonts then
		WV.Fonts()
	end
end

local function HideRow(row)
	row.body:Hide()
	row.name:Hide()
	row.tag:Hide()
	row.time:Hide()
end

-- a string's height, nil when it cannot be read (secret)
local function Height(fs)
	local ok, h = pcall(fs.GetStringHeight, fs)
	return ok and Num(h) or nil
end
View.Height = Height   -- (the whisper window's bubbles)

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
	width = okW and Num(width) or 300
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
			body:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", x, 2 - View.pixel)   -- (the glide's push: View.Glide)
			View.firstX = x
		end
		body:SetWidth(math.max(40, width - x - 4))
		pcall(body.SetText, body, View.Codes(rec.body))
		View.ChatColour(body, rec.r, rec.g, rec.b)
		View.Shadow(body)
		body:Show()
		local older = Nth(buf, j + 1)
		if rec.headed and not SameRun(rec, older) then
			-- the run's first line: its header over it
			local name, tag, time = row.name, row.tag, row.time
			name:ClearAllPoints()
			name:SetPoint("BOTTOMLEFT", body, "TOPLEFT", -x, GAP_LINE)
			local text = rec.name
			if View.paper and rec.cr and not Secret(text) and type(text) == "string" then
				text = View.Gem(rec.cr, rec.cg, rec.cb, name) .. text
			end
			pcall(name.SetText, name, text)
			if View.paper then
				View.Colour(name, "text")   -- (the names' ink, as the chat's on its paper; the class in the gem)
			else
				View.InkColour(name, rec.nr or rec.r, rec.ng or rec.g, rec.nb or rec.b)
			end
			View.Shadow(name)
			name:Show()
			tag:ClearAllPoints()
			tag:SetPoint("BOTTOMLEFT", name, "BOTTOMRIGHT", 6, 1)
			tag:SetText(View.Codes(rec.tag) or "")
			View.Colour(tag, "text")
			View.Shadow(tag)
			tag:SetShown(rec.tag ~= nil)
			time:ClearAllPoints()
			time:SetPoint("BOTTOMRIGHT", body, "TOPRIGHT", 0, GAP_LINE + 1)
			time:SetText(rec.time or "")
			View.Colour(time, "text")
			View.Shadow(time)
			time:Show()
			prev, prevX, gap = name, 0, GAP_RUN
			if k == 1 then
				View.firstTop = Height(name)
				View.firstTop = View.firstTop and (View.firstTop + GAP_LINE)
			end
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
			if k == 1 then
				View.firstTop = 0
			end
		end
		if k == 1 then
			-- the newest laid row's height with its gap (nil: secret, the glide guesses it)
			local bh = Height(body)
			View.firstH = (bh and View.firstTop) and (bh + View.firstTop + gap) or nil
		end
		j = j + 1
	end
	if k == 0 then
		View.firstH = nil
	end
	-- (the top stop's: the topmost laid line, and whether it is the oldest kept)
	View.topRegion, View.oldestLaid = prev, k > 0 and Nth(buf, j) == nil
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

--------------------------------------------------------------------------------
-- Smooth scrolling (the chat's Smooth Scrolling; the user, 2026-10-15: "dont forget smooth scrolling on the chat and
-- whisper window"). A list laid by anchors from its foot -- the view's lines, the whisper window's bubbles -- glides
-- by pixels: its newest laid line pushed down past the foot, the next older line taken on (its offset one more) once
-- that line has gone by its own height (read while it is plain; a SECRET line's guessed from the font: the list then
-- settles a little at that line). Off (Smooth Scrolling off, Reduce Motion): line by line, as before.
--   scroller = { owner, count(), lay(), shift(), estimate(), room() }; owner.offset (lines from the newest),
--   owner.pixel (how far down), owner.firstH (its lay's newest line's height with its gap, nil when unknown),
--   owner.topRegion / owner.oldestLaid (its lay's topmost region; true when that is the oldest line kept)
--   View.Glide(scroller, lines)   lines older (+) or newer (-)
--   View.TopStop(scroller)        the top stop (below), after a jump (a bar dragged)
-- The top stop: scrolled to the oldest line, it stops with that line's top at the list's top -- no empty room over
-- it (the user, 2026-10-15: "make sure that we also have a scroll bar here on the whisper window, to not miss chats":
-- dragged to its top, the window showed the oldest line alone at its foot). Read only while the tops are plain.
--------------------------------------------------------------------------------

local GLIDE_TIME = 0.2

-- the newest laid line gone by: the next older one takes its place; back below it: the newer one again
local function Rebase(s)
	local o = s.owner
	for _ = 1, 60 do
		if o.pixel <= 0 then
			break
		end
		if o.offset >= s.count() - 1 then
			o.pixel, s.target, s.from = 0, 0, 0   -- (the oldest at the foot: no further)
			break
		end
		local h = o.firstH or s.estimate()
		if o.pixel < h then
			break
		end
		o.offset = o.offset + 1
		o.pixel, s.target, s.from = o.pixel - h, s.target - h, s.from - h
		s.lay()
	end
	for _ = 1, 60 do
		if o.pixel >= 0 or o.offset <= 0 then
			break
		end
		o.offset = o.offset - 1
		s.lay()
		local h = o.firstH or s.estimate()
		o.pixel, s.target, s.from = o.pixel + h, s.target + h, s.from + h
	end
	if o.offset <= 0 and o.pixel < 0 then
		o.pixel, s.target, s.from = 0, math.max(0, s.target), math.max(0, s.from)
	end
end

-- the empty room over a list's oldest line (px), while its oldest line is laid and the tops can be read; nil else
function View.Room(o, holder)
	if not (o.oldestLaid and o.topRegion) then
		return nil
	end
	local okH, ht = pcall(holder.GetTop, holder)
	local okR, rt = pcall(o.topRegion.GetTop, o.topRegion)
	ht, rt = okH and Num(ht), okR and Num(rt)
	if not (ht and rt) then
		return nil
	end
	return ht - rt
end

-- room over the oldest line: the list pulled up -- its push taken back, else a newer line taken on at the foot --
-- until the oldest line's top is at the list's top (pushed down by what then runs over), or all of it fits
local function TopStop(s)
	local o = s.owner
	for _ = 1, 60 do
		local room = s.room()
		if not room or room <= 0.5 then
			return
		end
		if o.pixel > 0 then
			local cut = math.min(o.pixel, room)
			o.pixel = o.pixel - cut
			s.target, s.from = math.min(s.target, o.pixel), math.min(s.from, o.pixel)
			s.shift()
		elseif o.offset > 0 then
			o.offset = o.offset - 1
			s.lay()
			local after = s.room()
			if after and after < 0 then
				o.pixel = -after
				s.target, s.from = o.pixel, o.pixel
				s.shift()
				return
			end
		else
			return   -- (all of it fits: the newest at the foot)
		end
	end
end
View.TopStop = TopStop

local GlideStep = function(s, u)
	local q = 1 - u
	s.owner.pixel = s.from + (s.target - s.from) * (1 - q * q * q)
	Rebase(s)
	s.shift()
	TopStop(s)
end

function View.Glide(s, lines)
	local o = s.owner
	local Anim = MelloUI.Anim
	if not (M.db and M.db.smoothScroll ~= false) or Anim.reduceMotion then
		Anim:Stop(s, "drive")
		o.pixel, s.target, s.from = 0, 0, 0
		o.offset = math.max(0, math.min(o.offset + lines, math.max(0, s.count() - 1)))
		s.lay()
		TopStop(s)
		return
	end
	s.from = o.pixel
	s.target = (Anim:IsRunning(s, "drive") and s.target or o.pixel) + lines * s.estimate()
	if o.offset <= 0 and s.target < 0 then
		s.target = 0
	end
	Anim:Drive(s, GlideStep, GLIDE_TIME, "linear")
end

-- a glide under way ended, the list at its newest line (a tab switched, the view laid anew)
function View.Settle(s)
	MelloUI.Anim:Stop(s, "drive")
	s.owner.pixel, s.target, s.from = 0, 0, 0
end

-- the view's lines: a line's height guessed from the open tab's font
View.scroller = {
	owner = View, target = 0, from = 0,
	count = function()
		local buf = View.tab and View.bufs[View.tab]
		return buf and buf.count or 0
	end,
	lay = function()
		View.Lay()
	end,
	shift = function()
		local row = View.rows[1]
		if row and row.body:IsShown() then
			row.body:SetPoint("BOTTOMLEFT", View.area, "BOTTOMLEFT", View.firstX or 0, 2 - View.pixel)
		end
	end,
	estimate = function()
		local src = (type(View.tab) == "table" and View.tab) or ChatFrame1
		local ok, _, size = pcall(src.GetFont, src)
		return ((ok and Num(size)) or 14) * 1.25 + GAP_LINE
	end,
	room = function()
		return View.Room(View, View.area)
	end,
}

function View.Scroll(delta)
	if not (View.tab and View.bufs[View.tab]) then
		return
	end
	View.Glide(View.scroller, delta * (IsShiftKeyDown() and 10 or 3))
end

--------------------------------------------------------------------------------
-- Links: a click is the game's (SetItemRef), an item or a spell shows its tooltip under the pointer. (0.25.0) A map
-- pin's link (anyone's shared pin: the game's own worldmap link) opens on MelloUI's map while it is on -- your pin
-- set there, Route on its way -- never the game's map; a modified click stays the game's (Shift: into the chat line)
--------------------------------------------------------------------------------

local LinkClick = Perf.Shared("OnHyperlinkClick on the chat view", function(_, link, text, button)
	if Secret(link) or type(link) ~= "string" then
		return
	end
	if button == "LeftButton" and link:sub(1, 9) == "worldmap:" and not (IsShiftKeyDown() or IsControlKeyDown()) then
		local map = MelloUI:GetModule("Map")
		if map and map.isEnabled and map.OpenPinLink then
			local ok, opened = pcall(map.OpenPinLink, map, link)
			if ok and opened then
				return
			end
		end
	end
	if type(SetItemRef) == "function" then
		pcall(SetItemRef, link, text, button, ChatFrame1)
	end
end, "script")

local LinkEnter = Perf.Shared("OnHyperlinkEnter on the chat view", function(owner, link)
	if Secret(link) or type(link) ~= "string" then
		return
	end
	local kind = link:match("^(%a+):")
	if not (kind and TIP_LINKS[kind]) then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
	if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
		GameTooltip:Show()
	else
		GameTooltip:Hide()
	end
end, "script")

local LinkLeave = Perf.Shared("OnHyperlinkLeave on the chat view", function(owner)
	if GameTooltip:IsOwned(owner) then
		GameTooltip:Hide()
	end
end, "script")

function View.Links(frame)
	pcall(frame.SetHyperlinksEnabled, frame, true)
	Perf.SetScript(frame, "OnHyperlinkClick", LinkClick)
	Perf.SetScript(frame, "OnHyperlinkEnter", LinkEnter)
	Perf.SetScript(frame, "OnHyperlinkLeave", LinkLeave)
end

--------------------------------------------------------------------------------
-- The rail: the game's chat windows by name, the channels you made (/join), Whispers -- in the order you drag them
-- to (kept per character: Chat's viewOrder; a new one comes in just above Whispers), scrolled by the wheel or by its
-- bar when they do not all fit (MelloUI's thin bar, W.ThinScrollBar), the names in the chat's font (the Chat Size
-- slider's) and each tab as tall as that font needs; the open one lit (the user, 2026-10-15: "i want new channels to
-- appear here, click draging could rearange them, and it the list gets too big, you get a scroll bar ... and the
-- channel names also need their font to scale with the slider")
--------------------------------------------------------------------------------

local WHISPERS_KEY = "whispers"

-- (0.25.0, the user's chat sheets: MelloUI's icon set) a window's tab by its name: the chat's buttons of the set
-- (W.GlyphButton shows them whole; in Oldschool's look their glyphs, W.GLYPH_OF)
local function GlyphFor(name)
	name = type(name) == "string" and name:lower() or ""
	if name:find("combat") then
		return "chat_combat"
	elseif name:find("loot") then
		return "chat_loot"
	elseif name:find("guild") then
		return "chan_guild"
	elseif name:find("whisper") then
		return "chat_whispers"
	elseif name:find("trade") then
		return "chat_channels"
	end
	return "chat_general"
end

-- a count on a button's rim (a dark disc, the number in gold), on a frame of its own so it can pop in
local function Count(b)
	if not b.countText then
		local holder = CreateFrame("Frame", nil, b)
		holder:SetSize(13, 13)
		holder:SetPoint("CENTER", b, "TOPRIGHT", -3, -3)
		holder:SetFrameLevel(b:GetFrameLevel() + 6)
		local disc = holder:CreateTexture(nil, "OVERLAY", nil, 5)
		disc:SetTexture(ROUND_MASK)
		disc:SetAllPoints(holder)
		W.Paint(disc, "innerPanel", "vertex", 0.95)
		local fs = holder:CreateFontString(nil, "OVERLAY", "MelloUIFont_GameFontNormalSmall")
		fs:SetPoint("CENTER", holder, "CENTER", 0, 0)
		W.Paint(fs, "selectedTrim", "text")
		b.countFrame, b.countDisc, b.countText = holder, disc, fs
	end
	return b.countFrame, b.countText
end

function View.SetCount(b, n)
	local holder, fs = Count(b)
	local show = n and n > 0
	holder:SetShown(show)
	fs:SetShown(show)
	if show then
		fs:SetText(n > 99 and "99" or n)
	end
	return show
end

-- a tab's name in the chat's font (General's: the Chat Size slider's, the game's size of its window)
local function LabelFont(label)
	View.Font(label, 1, ChatFrame1)
end

local function Label(parent)
	local label = parent:CreateFontString(nil, "OVERLAY", "MelloUIFont_GameFontHighlight")
	label:SetJustifyH("LEFT")
	label:SetWordWrap(false)
	LabelFont(label)
	return label
end

-- one tab's height on the rail: its round button's, or its name's line when the chat's font is bigger
local function Step()
	local ok, _, size = pcall(ChatFrame1.GetFont, ChatFrame1)
	size = ok and Num(size) or 14
	return math.max(ICON + 8, math.floor(size + 14))
end

local function InFight()
	return InCombatLockdown() and true or false
end

-- fn now, or once the fight is over (true: it waits)
local function WhenCalm(fn, key)
	if InFight() then
		MelloUI.Kit:WhenOutOfCombat(fn, key)
		return true
	end
	return false
end

local drag = { t = nil, slot = nil }
local justDragged = false   -- (a drag's release is no click)

local TabClick = Perf.Shared("OnClick on a chat view tab", function(f, button)
	local t = f.entry
	if justDragged or not t then
		return
	end
	if button == "RightButton" then
		if t.kind == "channel" and View.ChannelMenu then
			View.ChannelMenu(t)   -- (a window's: the game's menu, its stand-in; below)
		end
		return
	end
	if t.bufKey ~= View.tab then
		MelloUI:PlayUISound("tab")
	end
	View.Select(t.bufKey)
end, "script")

local TabEnter = Perf.Shared("OnEnter on a chat view tab", function(f)
	local t = f.entry
	if not t then
		return
	end
	if t.gameTab and not InFight() and View.PlaceStands then
		View.PlaceStands()   -- (no stand-in over it: the chat moved since)
	end
	local b = t.button
	b:LockHighlight()   -- (its round light: the strip takes the mouse)
	W.ShowTooltip(f, b.tabName or "", b.tabTip or TEXT.tabTip)
end, "script")

local TabLeave = Perf.Shared("OnLeave on a chat view tab", function(f)
	local t = f.entry
	if t then
		t.button:UnlockHighlight()
	end
	W.TipLeave(f)
end, "script")

local WhispersClick = Perf.Shared("OnClick on the chat view's Whispers tab", function(_, button)
	local WV = View.Whispers
	if WV and not justDragged and button ~= "RightButton" then
		MelloUI:PlayUISound("tab")
		WV.Toggle()
	end
end, "script")

--------------------------------------------------------------------------------
-- Dragging a tab: it follows the pointer up and down the rail, a gold line where it will land; let go, the rail is
-- in the new order, kept. Not in a fight (the windows' stand-ins cannot follow it there).
--------------------------------------------------------------------------------

-- the gap the pointer is at (0: before the first tab, #order: after the last) and its depth below the rail's top
local function DropSlot(rail, step)
	local okC, _, cy = pcall(GetCursorPosition)
	local okS, s = pcall(rail.GetEffectiveScale, rail)
	local okT, top = pcall(rail.GetTop, rail)
	cy, s, top = okC and Num(cy), okS and Num(s), okT and Num(top)
	if not (cy and s and top and s > 0) then
		return nil
	end
	local y = top - cy / s
	local slot = math.floor((y - 4) / step + 0.5) + View.railOffset
	return math.max(0, math.min(#View.order, slot)), y
end

local DragMove = Perf.Shared("OnUpdate on the chat view's rail while a tab is dragged", function(rail)
	local t = drag.t
	if not t then
		rail:SetScript("OnUpdate", nil)
		return
	end
	local step = Step()
	local slot, y = DropSlot(rail, step)
	if not slot then
		return
	end
	drag.slot = slot
	t.button:ClearAllPoints()
	t.button:SetPoint("TOPLEFT", rail, "TOPLEFT", 6, -(y - ICON / 2))
	local line = View.dropLine
	line:ClearAllPoints()
	line:SetPoint("TOPLEFT", rail, "TOPLEFT", 4, -(4 + (slot - View.railOffset) * step) + 1)
	line:SetPoint("RIGHT", rail, "RIGHT", -8, 0)
	line:Show()
end, "script")

local function ClearDragged()
	justDragged = false
end

function View.DragStart(t)
	if InFight() or not (t and View.rail) or drag.t then
		return
	end
	drag.t, drag.slot = t, nil
	justDragged = true
	t.button:SetAlpha(0.75)
	Perf.SetScript(View.rail, "OnUpdate", DragMove)
end

function View.DragStop()
	local t, slot = drag.t, drag.slot
	if not t then
		return
	end
	drag.t, drag.slot = nil, nil
	View.rail:SetScript("OnUpdate", nil)
	View.dropLine:Hide()
	t.button:SetAlpha(1)
	local order = View.order
	local from
	for i, o in ipairs(order) do
		if o == t then
			from = i
		end
	end
	if slot and from then
		table.remove(order, from)
		if slot >= from then
			slot = slot - 1
		end
		table.insert(order, slot + 1, t)
		local keys = {}
		for i, o in ipairs(order) do
			keys[i] = o.key
		end
		if M.db then
			M.db.viewOrder = keys   -- (kept per character: Chat's keep list)
		end
		MelloUI:PlayUISound("tab")
	end
	View.PlaceRail()
	C_Timer.After(0, ClearDragged)
end

local TabDragStart = Perf.Shared("OnDragStart on a chat view tab", function(f)
	View.DragStart(f.entry)
end, "script")

local TabDragStop = Perf.Shared("OnDragStop on a chat view tab", function()
	View.DragStop()
end, "script")

-- a tab of the rail: its round button, its name, and one strip over both that takes the mouse -- a click, a right
-- click, a drag on the name as on the button (the user, 2026-10-15: "these text should also be clickable like the
-- icons"); a window's stand-in lies over that strip
local function NewTab(glyph, kind, bufKey)
	local rail = View.rail
	local b = W.GlyphButton(rail, ICON, glyph)
	b:EnableMouse(false)   -- (the strip takes the mouse; its light lit from there)
	local hit = CreateFrame("Button", nil, rail)
	hit:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
	hit:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", -2, -2)
	hit:SetWidth(RAIL_W - 18)   -- (to the rail's right, short of its bar)
	hit:SetFrameLevel(b:GetFrameLevel() + 3)
	hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	hit:RegisterForDrag("LeftButton")
	local t = { button = b, label = Label(rail), hit = hit, kind = kind, bufKey = bufKey }
	b.entry, hit.entry = t, t
	Perf.SetScript(hit, "OnClick", kind == "whispers" and WhispersClick or TabClick)
	Perf.SetScript(hit, "OnEnter", TabEnter)
	Perf.SetScript(hit, "OnLeave", TabLeave)
	Perf.SetScript(hit, "OnDragStart", TabDragStart)
	Perf.SetScript(hit, "OnDragStop", TabDragStop)
	View.KitRim(b)
	if bufKey then
		View.tabs[bufKey] = t
	end
	return t
end
View.NewTab = NewTab   -- (Build's Whispers tab)

--------------------------------------------------------------------------------
-- (the row's Channels and Friends the same way: their stand-ins' left click the game's own button's)
-- A right click on a tab: the game's own menu for that window (Rename, Create New Window on General, Close, Lock,
-- Font Size, Settings -- which chat and channels it shows --, Edit Mode on General), exactly as on the game's tab.
-- Opened from MelloUI's code it would run tainted, and so would what it changes: the chat's windows, which a SECRET
-- line then fails on (the whisper popup's note). So a secure stand-in lies over each tab: a SecureActionButtonTemplate
-- button whose right click is the game's own press of that window's tab (its "click" action: SecureTemplates.lua,
-- the game's code, the player's click behind it), its left click ours (PostClick), its hover the tab's, its drag the
-- tab's. The stand-ins sit on UIParent, laid at the tabs' places out of combat only (a secure frame cannot move in a
-- fight; laid on our frames, they would make those restricted in combat too); in a fight the rail does not scroll or
-- reorder, and a change of the windows waits for its end. Laid as the reminders' overlay is
-- (Reminders.OverlayPlace: by measure on UIParent, never anchored to ours).
--------------------------------------------------------------------------------

local stand = {}   -- [our tab button] = its stand-in

local StandPost = Perf.Shared("PostClick on a chat view tab's stand-in", function(p, button, down)
	if down or justDragged then
		return   -- (both phases come: the secure action's own on the game's setting; ours on the release)
	end
	local b = p.owner
	local t = b and b.entry
	if p.which == "2" and button == "LeftButton" and t and t.bufKey then
		if t.bufKey ~= View.tab then
			MelloUI:PlayUISound("tab")
		end
		View.Select(t.bufKey)
	end
end, "script")

local StandEnter = Perf.Shared("OnEnter on a chat view tab's stand-in", function(p)
	local b = p.owner
	if not b then
		return
	end
	if not InFight() then
		View.PlaceStands()   -- (the chat moved since: laid again before a click)
	end
	b:LockHighlight()
	if p.which == "2" then
		W.ShowTooltip(b, b.tabName or "", b.tabTip or TEXT.tabTip)
	else
		W.ShowTooltip(b, b.tipTitle or "", b.tipText)
	end
end, "script")

local StandLeave = Perf.Shared("OnLeave on a chat view tab's stand-in", function(p)
	local b = p.owner
	if b then
		b:UnlockHighlight()
		W.TipLeave(b)
	end
end, "script")

local StandDragStart = Perf.Shared("OnDragStart on a chat view tab's stand-in", function(p)
	local b = p.owner
	if p.which == "2" and b then
		View.DragStart(b.entry)
	end
end, "script")

-- a button's stand-in, made out of combat (nil in a fight: made after it): `which` "2", a tab's (its right click
-- the game's tab's), "1" a row button's (its click the game's own button's: Channels, Friends)
local function Stand(b, target, which)
	local p = stand[b]
	if p or InFight() or not target then
		return p
	end
	p = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
	p:SetFrameStrata(View.frame:GetFrameStrata())
	p:SetFrameLevel(View.frame:GetFrameLevel() + 40)
	-- (both phases, as every secure button of ours: with the game's "act on key down" on, a button registered for the
	-- release alone never runs its secure action -- the user, 2026-10-15: "i still cant right click on the channel")
	p:RegisterForClicks("AnyUp", "AnyDown")
	p:SetAttribute("type" .. which, "click")
	p:SetAttribute("clickbutton" .. which, target)
	p.owner, p.which = b, which
	Perf.SetScript(p, "PostClick", StandPost)
	Perf.SetScript(p, "OnEnter", StandEnter)
	Perf.SetScript(p, "OnLeave", StandLeave)
	if which == "2" then
		p:RegisterForDrag("LeftButton")
		Perf.SetScript(p, "OnDragStart", StandDragStart)
		Perf.SetScript(p, "OnDragStop", TabDragStop)
	end
	stand[b] = p
	return p
end

-- every tab's stand-in at its tab's place while the tab shows, hidden else (out of combat; after a fight)
function View.PlaceStands()
	if WhenCalm(View.PlaceStands, "Chat view: the tabs' right click") then
		return
	end
	for _, t in pairs(View.tabs) do
		Stand(t.button, t.gameTab, "2")
	end
	for _, b in ipairs(View.buttons or {}) do
		Stand(b, b.gameButton, "1")
	end
	local place = MelloUI.Reminders and MelloUI.Reminders.OverlayPlace
	for b, p in pairs(stand) do
		local over = (b.entry and b.entry.hit) or b   -- (a tab's strip: its name too)
		local shown = View.on and over:IsVisible() and place ~= nil and place(p, over) and true or false
		p:SetShown(shown)
	end
end

--------------------------------------------------------------------------------
-- Laying the rail out
--------------------------------------------------------------------------------

local placed = {}   -- [tab] = true while laid this pass (reused)

-- the rail's tabs placed from its scroll (the wheel over the rail, its bar): those out of it hidden
function View.PlaceRail()
	local rail = View.rail
	if not rail then
		return
	end
	local step = Step()
	local okH, height = pcall(rail.GetHeight, rail)
	height = okH and Num(height) or 120
	local n = #View.order
	local fits = math.max(1, math.floor((height - 4) / step))
	View.railOffset = math.max(0, math.min(View.railOffset, n - fits))
	wipe(placed)
	for idx, t in ipairs(View.order) do
		placed[t] = true
		local slot = idx - 1 - View.railOffset
		local shown = slot >= 0 and slot < fits
		if t ~= drag.t then   -- (the one dragged follows the pointer)
			t.button:ClearAllPoints()
			t.button:SetPoint("TOPLEFT", rail, "TOPLEFT", 6, -(4 + slot * step + (step - ICON) / 2))
		end
		t.label:ClearAllPoints()
		t.label:SetPoint("LEFT", t.button, "RIGHT", 6, 0)
		t.label:SetPoint("RIGHT", rail, "RIGHT", -8, 0)
		t.button:SetShown(shown or t == drag.t)
		t.label:SetShown(shown or t == drag.t)
		t.hit:SetShown(shown or t == drag.t)
	end
	for _, t in pairs(View.tabs) do
		if not placed[t] then
			t.button:Hide()
			t.label:Hide()
			t.hit:Hide()
		end
	end
	-- the bar: shown while they do not all fit, its thumb the share in view
	local bar, long = View.bar, n > fits
	if bar then
		View.railLaying = true
		bar:SetMinMaxValues(0, math.max(0, n - fits))
		bar:SetValue(View.railOffset)
		View.railLaying = false
		if long then
			local okB, bh = pcall(bar.GetHeight, bar)
			bh = okB and Num(bh) or height
			bar.thumb:SetHeight(math.max(12, bh * fits / n))
		end
		bar:SetShown(long)
	end
	View.Lit()
	View.PlaceStands()
end

-- the wheel over the rail, its bar: not in a fight (the stand-ins cannot follow)
function View.ScrollRail(delta)
	if InFight() then
		return
	end
	View.railOffset = View.railOffset - delta
	View.PlaceRail()
end

-- the channels you made (the Channels window's custom ones: GetChannelDisplayInfo's category), fn(name, number)
local function CustomChannels(fn)
	local count, info = rawget(_G, "GetNumDisplayChannels"), rawget(_G, "GetChannelDisplayInfo")
	if type(count) ~= "function" or type(info) ~= "function" then
		return
	end
	local okN, n = pcall(count)
	n = okN and Num(n) or 0
	for i = 1, n do
		local ok, name, header, _, number, _, _, category = pcall(info, i)
		name, number = ok and Plain(name), ok and Num(number)
		if ok and not Plain(header) and Plain(category) == "CHANNEL_CATEGORY_CUSTOM" and type(name) == "string"
			and name ~= "" and number then
			fn(name, number)
		end
	end
end

-- the rail in the kept order: the known ones by it, a new one just above Whispers
local function Sort(order)
	local saved = M.db and M.db.viewOrder
	if type(saved) ~= "table" then
		return
	end
	local rank = {}
	for i, key in ipairs(saved) do
		rank[key] = i
	end
	local newAt = (rank[WHISPERS_KEY] or (#saved + 1)) - 0.5
	for i, t in ipairs(order) do
		t.rank = rank[t.key] or (newAt + i / 1000)
	end
	table.sort(order, function(a, b)
		return a.rank < b.rank
	end)
end

function View.Rail()
	if #View.order > 0 and WhenCalm(View.Rail, "Chat view: the rail") then
		return   -- (laid again after the fight: the stand-ins with it)
	end
	local order = View.order
	wipe(order)
	local maxWindows = tonumber(rawget(_G, "NUM_CHAT_WINDOWS")) or 10
	Windows(function(f, i)
		local name, shown, docked = WindowInfo(i)
		if type(name) == "string" and name ~= "" and (i == 1 or shown or docked) then
			local key = i <= maxWindows and ("w:" .. i) or ("t:" .. name)
			local t = View.tabs[f]
			if not t then
				t = NewTab(GlyphFor(name), "window", f)
				t.gameTab = rawget(_G, "ChatFrame" .. i .. "Tab")
				-- its font changed (its size in the game's tab menu, MelloUI's Chat Size, a Font Style): the rows
				hooksecurefunc(f, "SetFont", View.FontChanged)
				if not View.bufs[f] then
					Buffer(f)
					if f ~= rawget(_G, "COMBATLOG") then
						Restore(f, key)   -- (the history kept over the last logout first)
					end
					Seed(f)
				end
			end
			t.key = key
			t.button.tabName, t.button.tabTip = name, TEXT.tabTip
			t.label:SetText(name)
			order[#order + 1] = t
		end
	end)
	CustomChannels(function(name, number)
		local key = "c:" .. name:lower()
		local t = View.tabs[key]
		if not t then
			t = NewTab("chat_channels", "channel", key)
			Buffer(key)
			Restore(key, key)
		end
		t.key, t.channel, t.number = key, name, number
		t.button.tabName, t.button.tabTip = name, TEXT.channelTip:format(number)
		t.label:SetText(name)
		order[#order + 1] = t
	end)
	order[#order + 1] = View.whisperTab
	Sort(order)
	-- the open tab still there? (its window closed, its channel left, or none open yet: the first)
	local still = false
	for _, t in ipairs(order) do
		still = still or (t.bufKey ~= nil and t.bufKey == View.tab)
	end
	if not still then
		View.offset = 0
		View.Settle(View.scroller)
		View.tab = nil
		for _, t in ipairs(order) do
			if not View.tab and t.bufKey then
				View.tab = t.bufKey
			end
		end
	end
	View.PlaceRail()
	View.Counts()
end

local railPending = false
local function RailNow()
	railPending = false
	if View.on then
		View.Rail()
	end
end

-- the rail again on the next frame (a channel joined or left: a burst of events once)
function View.RailSoon()
	if not railPending then
		railPending = true
		C_Timer.After(0, RailNow)
	end
end

local function Lit(t, on)
	View.Colour(t.label, on and "selectedTrim" or "text")
	View.Shadow(t.label)
	W.Paint(t.button.icon, on and "selectedTrim" or "text", "vertex")
	if on and t.button:IsShown() then
		View.mark:ClearAllPoints()
		View.mark:SetPoint("TOP", t.button, "TOP", 0, 0)
		View.mark:SetPoint("BOTTOM", t.button, "BOTTOM", 0, 0)
		View.mark:SetPoint("LEFT", View.divider, "LEFT", -1, 0)
		return true
	end
	return false
end

function View.Lit()
	if not View.frame then
		return
	end
	local WV = View.Whispers
	local marked = false
	for _, t in ipairs(View.order) do
		local on
		if t.kind == "whispers" then
			on = WV ~= nil and WV.open
		else
			on = t.bufKey == View.tab
		end
		marked = Lit(t, on) or marked
	end
	View.mark:SetShown(marked)
end

function View.Counts()
	for key, t in pairs(View.tabs) do
		View.SetCount(t.button, key ~= View.tab and View.unread[key] or 0)
	end
end

-- the Whispers tab's count: every unread whisper while the window is closed; `pop` a new one -- the count pops in
-- and the rim lights once (Reduce Motion: shown at once, no light)
function View.WhisperCount(pop)
	local t = View.whisperTab
	local WV = View.Whispers
	if not (t and WV) then
		return
	end
	local shown = View.SetCount(t.button, (not WV.open) and WV.Total() or 0)
	if not (pop and shown) then
		return
	end
	local Anim = MelloUI.Anim
	if Anim.reduceMotion then
		return
	end
	Anim:Pop(t.button.countFrame, 0.25, 6)
	local glow = t.glow
	glow:SetAlpha(0.9)
	glow:Show()
	Anim:To(glow, "alpha", 0, 0.7, "outQuad")
end

-- a tab open: a window's lines, a channel's
function View.Select(key)
	if not View.tabs[key] then
		return
	end
	View.tab, View.offset = key, 0
	View.Settle(View.scroller)
	View.unread[key] = 0
	View.Lit()
	View.Counts()
	View.Fonts()   -- (each window its own size)
	View.Lay()
end

function View.FontChanged()
	if View.on then
		View.Fonts()
		View.Soon()
	end
end

--------------------------------------------------------------------------------
-- A channel you made: its lines on its own tab, from the game's channel event (all of them come there, whichever
-- window shows them); the rail again as you join or leave one
--------------------------------------------------------------------------------

local chanEvents
local args = {}   -- one event's arguments (reused: no table per line)

local OnChannel = Perf.Shared("OnEvent of the chat view's channels", function(_, event, ...)
	if event ~= "CHAT_MSG_CHANNEL" then
		View.RailSoon()   -- (joined, left, a channel list changed)
		return
	end
	local base = Plain((select(9, ...)))
	if type(base) ~= "string" or not View.on then
		return   -- (a secret name keys nothing: the line is still in its window)
	end
	local key = "c:" .. base:lower()
	if not View.tabs[key] then
		return
	end
	args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], args[10], args[11], args[12],
		args[13], args[14], args[15], args[16], args[17] = ...
	-- its colour the game's: the channel's own (CHANNEL<n>), else every channel's
	local index = Num(args[8])
	local info = ChatTypeInfo and ((index and ChatTypeInfo["CHANNEL" .. index]) or ChatTypeInfo.CHANNEL)
	local r, g, b
	if info and Num(info.r) then
		r, g, b = info.r, info.g, info.b
	end
	View.Line(key, nil, r, g, b, nil, nil, nil, event, args)
end, "script")

function View.ListenChannels(on)
	if on and not chanEvents then
		chanEvents = CreateFrame("Frame")
		Perf.SetScript(chanEvents, "OnEvent", OnChannel)
	end
	if not chanEvents then
		return
	end
	if on then
		chanEvents:RegisterEvent("CHAT_MSG_CHANNEL")
		chanEvents:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
		chanEvents:RegisterEvent("CHANNEL_UI_UPDATE")
	else
		chanEvents:UnregisterAllEvents()
	end
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

-- a channel's tab, right-clicked: speak in it, leave it (asked first: MelloUI:Confirm). MelloUI's own menu: nothing
-- of the game's chat is driven from it (the game's /join and /leave do the rest)
function View.ChannelMenu(t)
	if not (MenuUtil and MenuUtil.CreateContextMenu and t.channel and t.number) then
		return
	end
	MenuUtil.CreateContextMenu(t.button, function(_, root)
		root:CreateTitle(t.channel)
		root:CreateButton(TEXT.speakIn:format(t.channel), function()
			Open("/" .. t.number .. " ")
		end)
		root:CreateButton(TEXT.leave:format(t.channel), function()
			MelloUI:Confirm({
				text = TEXT.leaveAsk:format(t.channel),
				accept = TEXT.leave:format(t.channel),
				onAccept = function()
					local leave = rawget(_G, "LeaveChannelByName")
					if type(leave) == "function" then
						pcall(leave, t.channel)
					end
				end,
			})
		end)
	end)
end

local PickClick = Perf.Shared("OnClick on a chat view pick", function(b)
	Open(b.slash)
end, "script")

local ButtonEnter = Perf.Shared("OnEnter on a chat view button", function(b)
	W.ShowTooltip(b, b.tipTitle or "", b.tipText)
end, "script")

local ACTIONS = {
	{ "channels", "Channels", "The chat channels you are in, the ones you made with /join too: join, leave, invite.",
		game = "ChatFrameChannelButton", function()
		local toggle = rawget(_G, "ToggleChannelFrame")
		if type(toggle) == "function" then
			toggle()
		end
	end },
	{ "friends", "Friends", "Your friends list.", game = "QuickJoinToastButton", function()
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

-- (0.25.0, the user's chat sheets) the row's buttons of MelloUI's icon set: a channel's letter button, and the
-- actions' (the letter drawn on a disc, and the widget glyphs, until then; still so in Oldschool's look)
local ROW_ART = { S = "chan_say", P = "chan_party", R = "chan_raid", I = "chan_instance", G = "chan_guild",
	Y = "chan_yell", W = "chan_whisper", E = "chan_emote", channels = "chat_channels", friends = "chat_friends",
	chart = "chat_history", cog = "chat_settings" }

local function ButtonRow(frame)
	View.buttons = {}
	local n = #PICKS + #ACTIONS
	for i = 1, n do
		local pick, act = PICKS[i], ACTIONS[i - #PICKS]
		local b = W.GlyphButton(frame, LETTER, act and act[1] or nil)
		if pick then
			local letter = b:CreateFontString(nil, "OVERLAY", "MelloUIFont_GameFontNormal")
			letter:SetPoint("CENTER", b, "CENTER", 0, 0)
			local info = ChatTypeInfo and ChatTypeInfo[pick[3]]
			if info and Num(info.r) then
				letter:SetTextColor(info.r, info.g, info.b)
			end
			letter:SetText(pick[1])
			b.label = letter
			b.slash, b.tipTitle, b.tipText = pick[2], pick[4], "Speak in " .. pick[4]:lower() .. " (" .. pick[2] .. ")."
			Perf.SetScript(b, "OnClick", PickClick)
		else
			b.action, b.tipTitle, b.tipText = act[4], act[2], act[3]
			-- (the game's own button, pressed through a stand-in when the game has it: PlaceStands)
			b.gameButton = act.game and rawget(_G, act.game) or nil
			Perf.SetScript(b, "OnClick", ActionClick)
		end
		Perf.SetScript(b, "OnEnter", ButtonEnter)
		Perf.SetScript(b, "OnLeave", W.TipLeave)
		b:SetGlyph(ROW_ART[pick and pick[1] or act[1]])
		View.KitRim(b)
		View.buttons[i] = b
	end
end

local function PlaceButtons()
	local frame = View.frame
	local okW, width = pcall(frame.GetWidth, frame)
	width = okW and Num(width) or 400
	local n = #View.buttons
	local step = (width - 20) / n
	for i, b in ipairs(View.buttons) do
		b:ClearAllPoints()
		b:SetPoint("CENTER", frame, "BOTTOMLEFT", 10 + step * (i - 0.5), ROW_H / 2)
	end
end

-- every round button's rim: View.RimKit's (the icon set's own, the kit's only under Oldschool's painted chat)
function View.Rims()
	local Kit = View.RimKit()
	for _, t in pairs(View.tabs) do
		t.button:SetKit(Kit)
	end
	if View.whisperTab then
		View.whisperTab.button:SetKit(Kit)
	end
	for _, b in ipairs(View.buttons or {}) do
		b:SetKit(Kit)
	end
end

--------------------------------------------------------------------------------
-- The frame, and the game's chat out of sight under it
--------------------------------------------------------------------------------

-- the line you type in: its height while it shows, the lines rising over it
function View.Fit()
	local area, frame = View.area, View.frame
	if not area then
		return
	end
	local lift = 0
	if View.on then
		Windows(function(f)
			local box = f.editBox
			if box and box:IsShown() then
				local okH, h = pcall(box.GetHeight, box)
				lift = math.max(lift, (okH and Num(h)) or BOX_LIFT)
			end
		end)
	end
	area:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, ROW_H + 6 + lift)
end

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
	-- its empty parts take the click: nothing reaches the game's hidden chat under it (the user, 2026-10-15: a click
	-- on the rail "randomly selects somebody from chat for me to whisper him" -- a hidden line's player link)
	frame:EnableMouse(true)
	View.frame = frame
	-- the rail: clipped, the wheel scrolls its tabs; its divider, the open tab's mark on it
	local rail = CreateFrame("Frame", nil, frame)
	rail:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
	rail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", RAIL_W - 2, ROW_H + 4)
	rail:SetClipsChildren(true)
	rail:EnableMouseWheel(true)
	rail:SetScript("OnMouseWheel", function(_, delta)
		View.ScrollRail(delta)   -- (not in a fight: the tabs' stand-ins cannot move there)
	end)
	rail:SetScript("OnSizeChanged", function()
		View.PlaceRail()
	end)
	View.rail = rail
	local divider = W.Solid(frame, "ARTWORK", "border")
	divider:SetWidth(1)
	divider:SetPoint("TOPLEFT", frame, "TOPLEFT", RAIL_W, -8)
	divider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", RAIL_W, ROW_H + 4)
	View.divider = divider
	local mark = W.Solid(frame, "OVERLAY", "selectedTrim")
	mark:SetWidth(3)
	View.mark = mark
	-- the rail's bar (shown while its tabs do not all fit) and the line a dragged tab lands on
	local bar = W.ThinScrollBar(frame, 3)
	bar:SetPoint("TOPLEFT", frame, "TOPLEFT", RAIL_W - 5, -8)
	bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", RAIL_W - 5, ROW_H + 4)
	bar:Hide()
	bar:SetScript("OnValueChanged", function(self, value)
		if View.railLaying then
			return
		end
		if InCombatLockdown() then
			View.railLaying = true
			self:SetValue(View.railOffset)   -- (held in a fight: the tabs' stand-ins cannot move)
			View.railLaying = false
			return
		end
		View.railOffset = math.floor((Num(value) or 0) + 0.5)
		View.PlaceRail()
	end)
	View.bar = bar
	local drop = W.Solid(rail, "OVERLAY", "selectedTrim")
	drop:SetHeight(2)
	drop:Hide()
	View.dropLine = drop
	-- the Whispers tab: the whisper window (ChatWhispers.lua), its count and its one light
	local wt = View.NewTab("chat_whispers", "whispers", nil)
	local wb = wt.button
	wt.key = WHISPERS_KEY
	wb.tabName, wb.tabTip = TEXT.whispers, TEXT.whispersTip
	local glow = wb:CreateTexture(nil, "OVERLAY", nil, 7)
	glow:SetTexture(ROUND_MASK)
	glow:SetBlendMode("ADD")
	glow:SetSize(ICON * 1.7, ICON * 1.7)
	glow:SetPoint("CENTER", wb, "CENTER", 0, 0)
	W.Paint(glow, "selectedTrim", "vertex")
	glow:SetAlpha(0)
	wt.label:SetText(TEXT.whispers)
	wt.glow = glow
	View.whisperTab = wt
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
	View.Links(area)
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
	-- a window made, renamed, closed or docked (the game's tab menu: the stand-ins' right click): the rail again
	-- (after a fight: the stand-ins)
	local function WindowsChanged()
		if View.on and not WhenCalm(View.Apply, "Chat view: the windows") then
			View.Apply()
		end
	end
	for _, fn in ipairs({ "FCF_OpenNewWindow", "FCF_Close", "FCF_PopInWindow", "FCF_SetWindowName", "FCF_DockFrame",
		"FCF_UnDockFrame" }) do
		if type(rawget(_G, fn)) == "function" then
			hooksecurefunc(fn, WindowsChanged)
		end
	end
	-- the history written as the game logs out or reloads (the view on this session)
	local logout = CreateFrame("Frame")
	logout:RegisterEvent("PLAYER_LOGOUT")
	Perf.SetScript(logout, "OnEvent", function()
		local began = debugprofilestop()
		pcall(View.SaveHistory)
		if MelloUI.Perf and MelloUI.Perf.LogoutStep then
			MelloUI.Perf.LogoutStep("Chat view: the history kept", debugprofilestop() - began)
		end
	end)
	-- a new palette, the chat's parchment switched, the kit put on or taken off the chat: the look again
	local function Restyle()
		if View.on then
			View.Style()
			View.Soon()
		end
	end
	MelloUI:On("palette", Restyle, "Chat view")
	MelloUI:On("parchment", function(which)
		if which == "chat" then
			Restyle()
		end
	end, "Chat view parchment")
	local Kit = MelloUI.Kit
	if Kit and Kit.OnCover then
		Kit:OnCover(function(group)
			if group == "chat" then
				Restyle()
			end
		end)
	end
end

-- the panel's ground, from the chat's Background (None: clear) and Background Opacity
local function PanelAlpha()
	local db = M.db
	if M.Background and M.Background(db) == "none" then
		return 0
	end
	if db and db.windowAlphaOn and Num(db.windowAlpha) then
		return db.windowAlpha
	end
	return 0.82
end

-- the look: the paper or the dark panel, the rims, every colour
function View.Style()
	local frame = View.frame
	if not frame then
		return
	end
	-- (the chat's Parchment, the reskin on or off: Chat.lua's M.ChatInked)
	local paper = M.ChatInked and M.ChatInked() or false
	local turned = (View.paper and true or false) ~= paper
	View.paper = paper
	local Kit = MelloUI.Kit
	if paper and not View.sheet and Kit and Kit.ParchmentSheet then
		View.sheet = Kit:ParchmentSheet(frame, frame, { rect = frame, margin = 3 })
	end
	if View.sheet then
		View.sheet:SetShown(paper)
	end
	if frame.panelFill then
		W.Paint(frame.panelFill, "innerPanel", "fill", PanelAlpha())
	end
	-- the paper switched: the fonts again (its face, no outline; View.Font) -- the painted chat's windows tell it by
	-- their own font's change, the view on its own paper by nobody else
	if turned then
		View.Fonts()
	end
	View.Rims()
	View.Lit()
	local WV = View.Whispers
	if WV and WV.Restyle then
		WV.Restyle()
	end
end

local saved = {}   -- [edit box] = { level, points }: how the view found it
local boxHooked = {}

local FitBox = Perf.Shared("OnShow / OnHide of a chat edit box (the chat view)", function()
	if View.on then
		View.Fit()
	end
end, "script")

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
			box:SetPoint("BOTTOMLEFT", View.frame, "BOTTOMLEFT", RAIL_W + 4, ROW_H + 2)
			box:SetPoint("BOTTOMRIGHT", View.frame, "BOTTOMRIGHT", -4, ROW_H + 2)
			if not boxHooked[box] then
				boxHooked[box] = true
				Perf.HookScript(box, "OnShow", FitBox)
				Perf.HookScript(box, "OnHide", FitBox)
			end
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
		local h = { alpha = okA and Num(a) or 1, mouse = okM and Plain(m) }
		if wheel then
			local okW, w = pcall(f.IsMouseWheelEnabled, f)
			h.wheel = okW and Plain(w)
			local okL, l = pcall(f.GetHyperlinksEnabled, f)
			h.links = okL and Plain(l)
		end
		held[f] = h
	end
	f:SetAlpha(0)
	f:EnableMouse(false)
	if wheel then
		pcall(f.EnableMouseWheel, f, false)
		if held[f].links ~= nil then
			pcall(f.SetHyperlinksEnabled, f, false)   -- (its lines' links answer clicks without the mouse otherwise)
		end
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
	if h.links ~= nil then
		pcall(f.SetHyperlinksEnabled, f, h.links)
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
	local WV = View.Whispers
	if View.Wanted() then
		Build()
		local was = View.on
		View.on = true
		View.frame:Show()
		View.Rail()
		HideGame(true)
		PlaceEditBoxes(true)
		View.Fit()
		View.Fonts()
		View.Style()
		if not was then
			View.offset = 0
			View.Settle(View.scroller)
			if WV then
				WV.Listen(true)
			end
			View.ListenChannels(true)
			if M.WhisperModeAgain then
				M.WhisperModeAgain()   -- (whispers kept in the main chat, as for the popups)
			end
		end
		View.WhisperCount(false)
		View.Lay()
	elseif View.on then
		View.on = false
		if WV then
			WV.Hide()
			WV.Listen(false)
		end
		View.ListenChannels(false)
		if M.WhisperModeAgain then
			M.WhisperModeAgain()
		end
		HideGame(false)
		PlaceEditBoxes(false)
		View.frame:Hide()
		View.PlaceStands()   -- (hidden with the view; after a fight)
	end
end
