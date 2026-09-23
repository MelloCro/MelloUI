--------------------------------------------------------------------------------
-- MelloUI - Chat
--
--   * hide the chat window background and border art
--   * hide the input box border art
--   * short, saturated channel tags:  G  Guild,  P  Party,  R  Raid,
--     RW  Raid Warning,  W  Whisper,  G  General,  T  Trade, ...
--   * class coloured player names in every chat type
--
-- The short tags are written AFTER the game has added a line: a secure
-- post-hook on each chat window's AddMessage rewrites that one line with the
-- window's TransformMessages (user, 2026-09-23, from the addon study: the
-- game's chat code runs untouched). Nothing of the game's is replaced or
-- written: its CHAT_*_GET formats, ChatFrameUtil.ResolvePrefixedChannelName
-- and the windows' addMessageObserver were, and the game's chat handler then
-- ran on MelloUI's values, tainted, where a secret message can only be
-- handled untainted. A secret line is left exactly as the game wrote it.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI

local M = MelloUI:RegisterModule("Chat", {
	title = "Chat",
	desc = "Clean chat: hidden background and input art, short coloured channel tags, class coloured names.",
	defaults = {
		hideBackground = true,
		hideEditBox = true,
		hideTabs = false,
		tabsOnMouseover = true,
		hideButtons = true,
		editBoxTop = true,
		shortChannels = true,
		hideBrackets = true,
		classColors = true,
		whisperPopup = false,
	},
	options = {
		{ type = "header", name = "Appearance" },
		{ type = "toggle", key = "hideBackground", name = "Hide Window Background",
		  desc = "Hide the background and border art of all chat windows." },
		{ type = "toggle", key = "hideEditBox", name = "Hide Input Box Art",
		  desc = "Hide the border and background art of the chat input box." },
		{ type = "toggle", key = "hideTabs", name = "Hide Tab Background",
		  desc = "Hide the background art behind the chat tabs. The tab text stays." },
		{ type = "toggle", key = "tabsOnMouseover", name = "Tabs Only On Mouseover",
		  desc = "Chat tab names are invisible until the mouse is over the chat. Tabs flashing with new whispers stay visible." },
		{ type = "toggle", key = "editBoxTop", name = "Input Box On Top",
		  desc = "Move the chat input box above the chat window and its tabs instead of below it." },
		{ type = "toggle", key = "hideButtons", name = "Hide Chat Buttons",
		  desc = "Hide the buttons next to the chat: chat menu, channel and voice buttons, social button and the minimize button column." },
		{ type = "header", name = "Channels" },
		{ type = "toggle", key = "shortChannels", name = "Short Channel Tags",
		  desc = "Replace [Guild], [Party], [1. General] and so on with short, saturated coloured tags." },
		{ type = "toggle", key = "hideBrackets", name = "Hide Brackets",
		  desc = "Also remove the square brackets around the short channel tags." },
		{ type = "toggle", key = "classColors", name = "Class Coloured Names",
		  desc = "Colour player names by class in every chat type (sets the chatClassColorOverride CVar)." },
		{ type = "header", name = "Whispers" },
		{ type = "toggle", key = "whisperPopup", name = "Whisper Popup Window",
		  desc = "A whisper opens a small window of its own, one per person, with the conversation and a box to answer in, instead of a new chat tab. Whispers still show in the main chat. Switching it off puts the game's own whisper setting back." },
	},
})

local function Active(key)
	return M.isEnabled and M.db and M.db[key]
end

-- The kit's chat skin covers the chat art (user rule, 2026-09-21): the three
-- art-hiding toggles act only while it is off; the layout toggles (tabs on
-- mouseover, input box on top, hidden buttons) and the channel options always.
local function ArtCovered()
	local Kit = MelloUI.Kit
	return Kit and Kit:IsCovered("chat")
end

local function HideArt(key)
	return M.db[key] and not ArtCovered()
end

local function NumWindows()
	return NUM_CHAT_WINDOWS or 10
end

-- Every chat window the game has, including the whisper windows it opens on
-- the fly (ChatFrame11, 12, ... listed in CHAT_FRAMES). Looping only
-- 1..NUM_CHAT_WINDOWS missed those, so a whisper tab came up without this
-- module's changes or the chat reskin (user, 2026-09-23). Read only: the game's
-- list is never written.
local function ChatFrameNames()
	local names = {}
	if type(CHAT_FRAMES) == "table" then
		for _, name in pairs(CHAT_FRAMES) do
			if type(name) == "string" then
				names[#names + 1] = name
			end
		end
	end
	if #names == 0 then
		for i = 1, NumWindows() do
			names[#names + 1] = "ChatFrame" .. i
		end
	end
	return names
end

local function Textures()
	return CHAT_FRAME_TEXTURES or {
		"Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
		"LeftTexture", "RightTexture", "BottomTexture", "TopTexture",
		"ButtonFrameBackground", "ButtonFrameTopLeftTexture", "ButtonFrameBottomLeftTexture",
		"ButtonFrameTopRightTexture", "ButtonFrameBottomRightTexture", "ButtonFrameLeftTexture",
		"ButtonFrameRightTexture", "ButtonFrameBottomTexture", "ButtonFrameTopTexture",
	}
end

--------------------------------------------------------------------------------
-- Window background
--------------------------------------------------------------------------------

local function SetBackgroundShown(shown)
	for _, name in ipairs(ChatFrameNames()) do
		for _, key in ipairs(Textures()) do
			local tex = _G[name .. key]
			if tex and tex.SetShown then
				tex:SetShown(shown)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Edit box art
--------------------------------------------------------------------------------

-- Blizzard toggles the focus textures with SetShown, so alpha is used for them.
local function SetEditBoxArtShown(shown)
	for _, name in ipairs(ChatFrameNames()) do
		local editBox = _G[name .. "EditBox"]
		if editBox then
			local editName = editBox:GetName()
			for _, suffix in ipairs({ "Left", "Mid", "Right" }) do
				local tex = _G[editName .. suffix]
				if tex then
					tex:SetShown(shown)
				end
			end
			for _, key in ipairs({ "focusLeft", "focusMid", "focusRight" }) do
				local tex = editBox[key]
				if tex then
					tex:SetAlpha(shown and 1 or 0)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Tabs only on mouseover
--------------------------------------------------------------------------------

-- The game fades each tab between a "mouse over" and a "no mouse" alpha. This
-- used to REWRITE the game's CHAT_FRAME_TAB_*_ALPHA globals and call
-- FCFTab_UpdateAlpha itself, which left the chat's fade code running tainted
-- ("Execution tainted by MelloUI while reading global
-- CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA", Logs/taint.log, 2026-09-23; the
-- game even keeps tab alphas off the tab so that taint cannot reach its shared
-- fade list). Now nothing of the game's is written: a post-hook on each tab's
-- SetAlpha corrects the alpha the game has just set, from the game's own state
-- -- hidden while the chat is not hovered, full on hover for the tabs the game
-- dims, a flashing (alerting) tab left exactly as the game draws it.
local tabsOnMouseover = false
local hookedTabs = setmetatable({}, { __mode = "k" })

local function Secret(v)
	return issecretvalue and issecretvalue(v) or false
end

local function TabAlphaWanted(tab, alpha)
	local okI, id = pcall(tab.GetID, tab)
	local frame = okI and id and not Secret(id) and _G["ChatFrame" .. id]
	if not frame then
		return alpha
	end
	if ChatFrameUtil and ChatFrameUtil.IsTabAlerting then
		local okA, alerting = pcall(ChatFrameUtil.IsTabAlerting, tab)
		if okA and not Secret(alerting) and alerting then
			return alpha
		end
	end
	if not frame.hasBeenFaded then
		return 0   -- the chat is not hovered
	end
	-- hovered: the unselected tabs the game dims to its "normal mouse over"
	-- alpha come up to full, in proportion so the fade-in stays a fade
	local normal = CHAT_FRAME_TAB_NORMAL_MOUSEOVER_ALPHA
	local selected = CHAT_FRAME_TAB_SELECTED_MOUSEOVER_ALPHA
	if type(alpha) == "number" and type(normal) == "number" and normal > 0 and normal < (selected or 1) then
		local okS, isSelected = pcall(function()
			return not frame.isDocked or frame == FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
		end)
		if okS and not isSelected then
			return math.min(1, alpha / normal)
		end
	end
	return alpha
end

-- While the kit dresses the chat, its "no fade" holds every tab at full alpha
-- (ChatPanel's NoFade, the user's pick 2026-09-21) and this steps aside, as the
-- art toggles do: two hooks setting one tab's alpha would fight, and which won
-- would depend on the order they were made in.
local function OnTabAlpha(tab, alpha)
	if not tabsOnMouseover or tab.melloAlphaGuard or Secret(alpha) or ArtCovered() then
		return
	end
	local want = TabAlphaWanted(tab, alpha)
	if want ~= alpha then
		tab.melloAlphaGuard = true
		tab:SetAlpha(want)
		tab.melloAlphaGuard = nil
	end
end

-- the game's own alpha for a tab now, for switching the option off
local function GameTabAlpha(tab)
	local okI, id = pcall(tab.GetID, tab)
	local frame = okI and id and not Secret(id) and _G["ChatFrame" .. id]
	if not (frame and ChatFrameUtil and ChatFrameUtil.GetTabAlphas) then
		return 1
	end
	local ok, over, noMouse = pcall(ChatFrameUtil.GetTabAlphas, tab)
	if not ok or Secret(over) or Secret(noMouse) then
		return 1
	end
	if frame.hasBeenFaded then
		return over or 1
	end
	return noMouse or 1
end

local function SetTabsOnMouseover(enabled)
	tabsOnMouseover = enabled and true or false
	for _, name in ipairs(ChatFrameNames()) do
		local tab = _G[name .. "Tab"]
		if tab and tab.SetAlpha then
			if not hookedTabs[tab] then
				hookedTabs[tab] = true
				hooksecurefunc(tab, "SetAlpha", OnTabAlpha)
			end
			local okA, current = pcall(tab.GetAlpha, tab)
			if okA and not Secret(current) and not ArtCovered() then
				tab.melloAlphaGuard = true
				tab:SetAlpha(tabsOnMouseover and TabAlphaWanted(tab, current) or GameTabAlpha(tab))
				tab.melloAlphaGuard = nil
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Edit box position
--------------------------------------------------------------------------------

local TAB_ROW_HEIGHT = 24

local editBoxSaved = {}   -- [editBox] = the game's anchors, taken before the first move

local function SetEditBoxOnTop(top)
	for _, name in ipairs(ChatFrameNames()) do
		local frame = _G[name]
		local editBox = frame and (frame.editBox or _G[name .. "EditBox"])
		if frame and editBox then
			if top then
				if not editBoxSaved[editBox] then
					local points = {}
					for p = 1, editBox:GetNumPoints() do
						points[p] = { editBox:GetPoint(p) }
					end
					editBoxSaved[editBox] = points
				end
				editBox:ClearAllPoints()
				editBox:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -5, TAB_ROW_HEIGHT)
				editBox:SetPoint("RIGHT", frame.ScrollBar or frame, "RIGHT", 8, 0)
			elseif editBoxSaved[editBox] then
				-- the game's own anchors back, only when they were changed
				-- (guessed offsets replaced them before, audit 2026-09-22)
				editBox:ClearAllPoints()
				for _, pt in ipairs(editBoxSaved[editBox]) do
					editBox:SetPoint(unpack(pt))
				end
				editBoxSaved[editBox] = nil
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Tab background
--------------------------------------------------------------------------------

local TAB_TEXTURES = { "Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight", "HighlightLeft", "HighlightMiddle", "HighlightRight" }

local function SetTabArtShown(shown)
	for _, name in ipairs(ChatFrameNames()) do
		local tab = _G[name .. "Tab"]
		if tab then
			for _, key in ipairs(TAB_TEXTURES) do
				local tex = tab[key]
				if tex then
					tex:SetAlpha(shown and 1 or 0)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Chat buttons
--------------------------------------------------------------------------------

local hiddenParent = MelloUIHiddenFrame or CreateFrame("Frame", nil, UIParent)
hiddenParent:Hide()

local CHAT_BUTTONS = {
	"ChatFrameMenuButton", "ChatFrameChannelButton",
	"ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
	"QuickJoinToastButton",
}

local buttonParents = setmetatable({}, { __mode = "k" })

local function CollectChatButtons()
	local list = {}
	for _, name in ipairs(CHAT_BUTTONS) do
		list[#list + 1] = _G[name]
	end
	for _, name in ipairs(ChatFrameNames()) do
		list[#list + 1] = _G[name .. "ButtonFrame"]
	end
	return list
end

local function SetButtonsHidden(hidden)
	local list = CollectChatButtons()
	-- Record original parents before anything is moved.
	for _, frame in ipairs(list) do
		if frame and frame.GetParent and buttonParents[frame] == nil then
			buttonParents[frame] = frame:GetParent() or UIParent
		end
	end
	for _, frame in ipairs(list) do
		if frame and frame.SetParent then
			if hidden then
				if frame:GetParent() ~= hiddenParent then
					frame:SetParent(hiddenParent)
				end
			elseif frame:GetParent() == hiddenParent then
				frame:SetParent(buttonParents[frame] or UIParent)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Short channel tags
--------------------------------------------------------------------------------

-- chat type -> { tag, hex colour }
local SHORT_TYPES = {
	SAY                  = { "S",   "ffffff" },
	YELL                 = { "Y",   "ff4040" },
	GUILD                = { "G",   "00ff00" },
	OFFICER              = { "O",   "40c040" },
	PARTY                = { "P",   "4da6ff" },
	PARTY_LEADER         = { "PL",  "4da6ff" },
	PARTY_GUIDE          = { "PG",  "4da6ff" },
	RAID                 = { "R",   "ff7d00" },
	RAID_LEADER          = { "RL",  "ff7d00" },
	RAID_WARNING         = { "RW",  "ff2a00" },
	INSTANCE_CHAT        = { "I",   "ff9a00" },
	INSTANCE_CHAT_LEADER = { "IL",  "ff9a00" },
	BATTLEGROUND         = { "BG",  "ff9a00" },
	BATTLEGROUND_LEADER  = { "BGL", "ff9a00" },
	WHISPER              = { "W",   "ff40ff" },
	WHISPER_INFORM       = { "W>",  "ff40ff" },
	BN_WHISPER           = { "W",   "00b0ff" },
	BN_WHISPER_INFORM    = { "W>",  "00b0ff" },
}

-- Numbered channels, keyed by lower-case name without spaces or zone suffix.
local SHORT_CHANNELS = {
	general          = { "G",   "ffcc00" },
	trade            = { "T",   "ff9955" },
	localdefense     = { "LD",  "80c0ff" },
	worlddefense     = { "WD",  "60a0ff" },
	lookingforgroup  = { "LFG", "c080ff" },
	guildrecruitment = { "GR",  "40ff90" },
	services         = { "SV",  "b0b0b0" },
	world            = { "W",   "ffe066" },
}

local function BuildTag(entry)
	local text = entry[2] and ("|cff" .. entry[2] .. entry[1] .. "|r") or entry[1]
	return "[" .. text .. "]"
end

local WHISPERS = { WHISPER = true, BN_WHISPER = true, WHISPER_INFORM = true, BN_WHISPER_INFORM = true }

-- The game's own line starts, as patterns: each chat type's format (read,
-- never written) with its sender, a player link, captured; and the short
-- start that replaces it. Built once.
local typePatterns = nil

local function TypePatterns()
	if typePatterns then
		return typePatterns
	end
	typePatterns = {}
	for chatType, entry in pairs(SHORT_TYPES) do
		local format = _G["CHAT_" .. chatType .. "_GET"]
		if type(format) == "string" and format:find("%s", 1, true) then
			local escaped = format:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
			local pattern = escaped:gsub("%%%%s", "(|H.-|h.-|h)", 1)
			-- whispers carry no channel link in the game's format; kept so
			local short = WHISPERS[chatType] and (BuildTag(entry) .. " %1: ")
				or ("|Hchannel:" .. chatType .. "|h" .. BuildTag(entry) .. "|h %1: ")
			typePatterns[#typePatterns + 1] = { pattern, short }
		end
	end
	-- the longest first: "Party Leader" before "Party"
	table.sort(typePatterns, function(a, b) return #a[1] > #b[1] end)
	return typePatterns
end

local function ShortChannelName(communityChannelArg)
	local _, name = communityChannelArg:match("(%d+. )(.*)")
	name = name or communityChannelArg
	if ChatFrameUtil and ChatFrameUtil.ResolveChannelName then
		name = ChatFrameUtil.ResolveChannelName(name)
	end
	local base = name:gsub("%s%-%s.*", "")
	local key = base:lower():gsub("%s+", "")
	local entry = SHORT_CHANNELS[key]
	if entry then
		return "|cff" .. entry[2] .. entry[1] .. "|r"
	end
	return base:sub(1, 1):upper()
end

local function ShortChannel(open, name, close)
	local ok, short = pcall(ShortChannelName, name)
	if ok and type(short) == "string" and short ~= "" then
		return open .. "[" .. short .. "]" .. close
	end
	return open .. "[" .. name .. "]" .. close
end

--------------------------------------------------------------------------------
-- Bracket removal
--------------------------------------------------------------------------------

local function StripBrackets(text)
	-- "|Hchannel:GUILD|h[G]|h" -> "|Hchannel:GUILD|hG|h", plus bracketed whisper tags.
	text = text:gsub("(|Hchannel:[^|]-|h)%[(.-)%]|h", "%1%2|h")
	text = text:gsub("^%[(|cff%x%x%x%x%x%x[%a>]+|r)%] ", "%1 ")
	text = text:gsub("^(%[?[%d:%s%p]-%]?%s?)%[(|cff%x%x%x%x%x%x[%a>]+|r)%] ", "%1%2 ")
	return text
end

-- One line, shortened: the chat type's start (guild, party, say, whisper ...),
-- then a numbered channel's name, then the brackets
local function Shorten(text)
	for _, tp in ipairs(TypePatterns()) do
		local new, n = text:gsub(tp[1], tp[2], 1)
		if n > 0 then
			text = new
			break
		end
	end
	text = text:gsub("(|Hchannel:[Cc][Hh][Aa][Nn][Nn][Ee][Ll]:%d+|h)%[(.-)%](|h)", ShortChannel, 1)
	if Active("hideBrackets") then
		text = StripBrackets(text)
	end
	return text
end

--------------------------------------------------------------------------------
-- The rewrite: after the game added a line
--------------------------------------------------------------------------------

local transformFailed = false

-- A history entry is the line's table on this client's chat frames, its text
-- in `message` (a plain string is taken too)
local function LineText(e)
	if type(e) == "table" then
		return e.message
	end
	return e
end

local function OnLineAdded(chatFrame, text)
	if transformFailed or not Active("shortChannels") then
		return
	end
	if text == nil or Secret(text) or type(text) ~= "string" or type(chatFrame.TransformMessages) ~= "function" then
		return
	end
	-- only this line (the newest with this exact text): the rest of the
	-- history was shortened when it came in
	local function IsIt(e)
		local t = LineText(e)
		return t ~= nil and not Secret(t) and t == text
	end
	local function Rewrite(e, ...)
		if type(e) == "table" then
			e.message = Shorten(e.message)
			return e, ...
		end
		return Shorten(e), ...
	end
	local ok = pcall(chatFrame.TransformMessages, chatFrame, IsIt, Rewrite)
	if not ok then
		transformFailed = true
	end
end

--------------------------------------------------------------------------------
-- Ink on parchment (QuestInk's rule, user 2026-09-23): with the chat's
-- parchment sheet on, each line's colour and the colour codes in it (names,
-- links, channel tags) are dark ink, a colour that means something as a dark
-- shade of it; the line's own look is kept on it and put back when the sheet
-- goes. The combat log is left as it is: it adds lines too fast to go over
-- its history for each one.
--------------------------------------------------------------------------------

local function ChatInked()
	local Kit = MelloUI.Kit
	return (MelloUI.QuestInk ~= nil and Kit and Kit.IsCovered and Kit:IsCovered("chat")
		and Kit.ParchmentOn and Kit:ParchmentOn("chat")) and true or false
end

local function InkEntry(e)
	local QI = MelloUI.QuestInk
	if type(e) ~= "table" or e.melloPlain or type(e.message) ~= "string" or Secret(e.message) then
		return e
	end
	e.melloPlain = { e.message, e.r, e.g, e.b }
	e.message = QI.InkCodes(e.message)
	if type(e.r) == "number" and type(e.g) == "number" and type(e.b) == "number" then
		e.r, e.g, e.b = QI.InkOf(e.r, e.g, e.b)
	end
	return e
end

local function PlainEntry(e)
	local p = type(e) == "table" and e.melloPlain
	if p then
		e.message, e.r, e.g, e.b = p[1], p[2], p[3], p[4]
		e.melloPlain = nil
	end
	return e
end

local function NotInked(e)
	return type(e) == "table" and not e.melloPlain and type(e.message) == "string" and not Secret(e.message)
end

local function Inked(e)
	return type(e) == "table" and e.melloPlain ~= nil
end

local function OnLineInk(chatFrame)
	if not ChatInked() or type(chatFrame.TransformMessages) ~= "function" then
		return
	end
	pcall(chatFrame.TransformMessages, chatFrame, NotInked, function(e, ...) return InkEntry(e), ... end)
end

-- every chat window's history inked or put back (the sheet switched)
-- A message frame's font without its outline and shadow while its lines are
-- ink (a black outline round dark ink smudges it -- user, 2026-09-23, the
-- whisper window); put back as it was after
local function InkFrameFont(frame, on)
	if not (frame and frame.GetFont) then
		return
	end
	if on then
		if not frame.melloInkFont then
			local ok, path, size, flags = pcall(frame.GetFont, frame)
			if not (ok and path and size) then
				return
			end
			local sr, sg, sb, sa = frame:GetShadowColor()
			frame.melloInkFont = { flags = flags or "", shadow = { sr, sg, sb, sa } }
		end
		local ok, path, size = pcall(frame.GetFont, frame)
		if ok and path and size then
			pcall(frame.SetFont, frame, path, size, "")
		end
		frame:SetShadowColor(0, 0, 0, 0)
	elseif frame.melloInkFont then
		local saved = frame.melloInkFont
		local ok, path, size = pcall(frame.GetFont, frame)
		if ok and path and size then
			pcall(frame.SetFont, frame, path, size, saved.flags)
		end
		local sh = saved.shadow
		if sh and sh[1] then
			frame:SetShadowColor(sh[1], sh[2], sh[3], sh[4] or 1)
		end
		frame.melloInkFont = nil
	end
end

local function InkAllChat(on)
	for _, name in ipairs(ChatFrameNames()) do
		local frame = _G[name]
		if frame and frame ~= _G.COMBATLOG and type(frame.TransformMessages) == "function" then
			InkFrameFont(frame, on)
			if on then
				pcall(frame.TransformMessages, frame, NotInked, function(e, ...) return InkEntry(e), ... end)
			else
				pcall(frame.TransformMessages, frame, Inked, function(e, ...) return PlainEntry(e), ... end)
			end
		end
	end
end

-- The post-hook on every chat window but the combat log (its lines are never
-- shortened, and it adds the most). hooksecurefunc: the game's AddMessage
-- runs first and untainted; the hook cannot be taken off again, it only acts
-- while Short Channel Tags is on.
local hookedWindows = {}

local function HookLines()
	for _, name in ipairs(ChatFrameNames()) do
		local frame = _G[name]
		if frame and not hookedWindows[frame] and frame ~= _G.COMBATLOG and frame.AddMessage then
			hookedWindows[frame] = true
			hooksecurefunc(frame, "AddMessage", OnLineAdded)
			-- after the shortening: the ink goes on the finished line
			hooksecurefunc(frame, "AddMessage", OnLineInk)
		end
	end
	local QI = MelloUI.QuestInk
	if QI and not QI.surfaces.chat then
		QI.Surface("chat", { noWalk = true, on = ChatInked, onRefresh = InkAllChat })
	end
end

--------------------------------------------------------------------------------
-- Class colours
--------------------------------------------------------------------------------

local CLASS_CVAR = "chatClassColorOverride"

local function ApplyClassColors(enable)
	if not C_CVar or not C_CVar.SetCVar then
		return
	end
	if enable then
		if M.db.savedClassColorCVar == nil then
			local current = C_CVar.GetCVar(CLASS_CVAR)
			-- "0" is the value this module writes; fall back to Blizzard's per-type default.
			M.db.savedClassColorCVar = (current and current ~= "0") and current or "-1"
		end
		C_CVar.SetCVar(CLASS_CVAR, "0") -- 0 = force class colours on for every chat type
	else
		if M.db.savedClassColorCVar ~= nil then
			C_CVar.SetCVar(CLASS_CVAR, M.db.savedClassColorCVar)
			M.db.savedClassColorCVar = nil
		end
	end
end

--------------------------------------------------------------------------------
-- Whisper popup (user, 2026-09-23)
--
-- A whisper opens a small window of its own instead of a new chat tab: one
-- window per person, with the conversation and a box to answer in.
--
-- It is MelloUI's OWN window, fed by the whisper events. Undocking the game's
-- whisper window instead would mean calling its docking code from here, which
-- taints the chat pipeline -- the same fault the damage meter's timer had --
-- and whisper text can be SECRET on this client, which tainted chat code then
-- fails on. The game is set to show whispers in the main chat instead of
-- opening a tab (the whisperMode CVar, an engine setting: setting it taints
-- nothing), so nothing is lost from the chat, and it is put back when the
-- option goes off.
--
-- Secret text is shown as it is (a message frame takes it) and never joined
-- with anything; plain text gets the time and who said it.
--------------------------------------------------------------------------------

local WHISPER_EVENTS = {
	CHAT_MSG_WHISPER           = { kind = "WHISPER",    incoming = true },
	CHAT_MSG_WHISPER_INFORM    = { kind = "WHISPER",    incoming = false },
	CHAT_MSG_BN_WHISPER        = { kind = "BN_WHISPER", incoming = true },
	CHAT_MSG_BN_WHISPER_INFORM = { kind = "BN_WHISPER", incoming = false },
}
local POPUP_W, POPUP_H = 340, 210
local HEADER_H = 24   -- the header band's opaque part
local popups = {}        -- [conversation key] = window
local WriteWhisperLine -- below (a conversation line, in ink or its colours)
local popupFontHooked = false

-- A whisper window's conversation and answer box in ink or their colours
-- again (the whisper parchment switched): the lines written anew from their
-- parts
-- The whisper window in the chat's font (user, 2026-09-23: "the Font
-- Decisions should take over the Whisper Window"): the main chat window's
-- face, size and outline as the Fonts module and the chat's size menu set
-- them, for the conversation and the answer box; on parchment the
-- conversation without its outline and shadow (the answer box keeps them:
-- it lies on its dark plate, not the paper)
local function PopupFont(f)
	local src = _G.ChatFrame1 or ChatFontNormal
	if not (f and f.msgs and src and src.GetFont) then
		return
	end
	local ok, path, size, flags = pcall(src.GetFont, src)
	if not (ok and path and size) then
		return
	end
	-- the chat's own outline, not the ink's (the chat on parchment has none)
	flags = (src.melloInkFont and src.melloInkFont.flags) or flags or ""
	if not f.msgs.melloShadow then
		local sr, sg, sb, sa = f.msgs:GetShadowColor()
		f.msgs.melloShadow = { sr, sg, sb, sa }
	end
	pcall(f.msgs.SetFont, f.msgs, path, size, f.inked and "" or flags)
	if f.inked then
		f.msgs:SetShadowColor(0, 0, 0, 0)
	else
		local sh = f.msgs.melloShadow
		f.msgs:SetShadowColor(sh[1] or 0, sh[2] or 0, sh[3] or 0, sh[4] or 1)
	end
	if f.box and f.box.SetFont then
		pcall(f.box.SetFont, f.box, path, size, flags)
	end
end

local function InkPopup(f)
	local QI = MelloUI.QuestInk
	if not (QI and f) then
		return
	end
	local ink = (f.kitDressed and QI.surfaces.whisper and QI.surfaces.whisper.active) and true or false
	local changed = (f.inked or false) ~= ink
	f.inked = ink
	PopupFont(f)
	if f.msgs and f.lineLog and changed then
		f.msgs:Clear()
		for _, e in ipairs(f.lineLog) do
			WriteWhisperLine(f, e)
		end
	end
	-- the chat's font changed (the Fonts module, the chat's size menu): every
	-- whisper window follows
	if not popupFontHooked and _G.ChatFrame1 and _G.ChatFrame1.SetFont then
		popupFontHooked = true
		hooksecurefunc(_G.ChatFrame1, "SetFont", function()
			for _, w in pairs(popups) do
				PopupFont(w)
			end
		end)
	end
end
local popupCount = 0
local popupOn = false
local whisperEvents = CreateFrame("Frame")

-- the whisper windows on their parchment sheet (the kit dressing them and
-- the Whisper Popup parchment on)
local function WhisperInked()
	local Kit = MelloUI.Kit
	return (MelloUI.QuestInk ~= nil and Kit and Kit.IsCovered and Kit:IsCovered("chat")
		and Kit.ParchmentOn and Kit:ParchmentOn("whisper")) and true or false
end

-- One conversation line, in ink on parchment, else in its colours
WriteWhisperLine = function(f, e)
	local QI = MelloUI.QuestInk
	local ink = WhisperInked() and f.kitDressed
	local stampHex, who, r, g, b = "ff8a8a8a", e.who, e.r, e.g, e.b
	if ink then
		local sr, sg, sb = QI.InkOf(0.54, 0.54, 0.54)
		stampHex = string.format("ff%02x%02x%02x", math.floor(sr * 255 + 0.5), math.floor(sg * 255 + 0.5), math.floor(sb * 255 + 0.5))
		who = QI.InkCodes(who)
		r, g, b = QI.InkOf(r, g, b)
	end
	local line = ("|c%s%s|r %s: %s"):format(stampHex, e.stamp, who, e.text)
	if not pcall(f.msgs.AddMessage, f.msgs, line, r, g, b) then
		f.msgs:AddMessage(e.text, r, g, b)
	end
end

-- the whisper windows follow their parchment (Kit:SetParchment("whisper"),
-- the chat reskin switched: ChatPanel)
if MelloUI.QuestInk then
	MelloUI.QuestInk.Surface("whisper", { noWalk = true, on = WhisperInked, onRefresh = function()
		for _, f in pairs(popups) do
			InkPopup(f)
		end
	end })
end

local function PopupColor(kind, incoming)
	local info = ChatTypeInfo and ChatTypeInfo[incoming and kind or (kind .. "_INFORM")]
	if info and type(info.r) == "number" then
		return info.r, info.g, info.b
	end
	return 1, 0.5, 1
end

-- where the next window opens: where the user last put one, each further one
-- stepped down and right so they do not stack exactly
local function PlacePopup(f)
	local pos = M.db and M.db.whisperPopupPos
	local step = ((popupCount - 1) % 6) * 24
	f:ClearAllPoints()
	if pos then
		f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", pos.x + step, pos.y - step)
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 260 + step, 80 - step)
	end
end

local function SavePopupPosition(f)
	if not M.db then
		return
	end
	local okL, left = pcall(f.GetLeft, f)
	local okB, bottom = pcall(f.GetBottom, f)
	if okL and okB and left and bottom and not Secret(left) and not Secret(bottom) then
		M.db.whisperPopupPos = { x = math.floor(left + 0.5), y = math.floor(bottom + 0.5) }
	end
end

-- the chat reskin's look when the kit dresses the chat (the single rail with
-- its stone, a parchment sheet with the painted edge on the stone), a plain
-- dark box with a thin edge otherwise. True when the kit dressed it, so the
-- header can match.
local function DressPopup(f)
	local Kit = MelloUI.Kit
	if Kit and Kit.NineSlice and Kit.IsCovered and Kit:IsCovered("chat") then
		-- no corner gems: the chat windows have none, and on a window this
		-- small the four of them bunched up in the middle of the stone (user
		-- screenshot, 2026-09-23)
		local ok, skin = pcall(Kit.NineSlice, Kit, f, { prefix = Kit.framePrefix, gems = false,
			scale = (Kit.scale or 1) * (Kit.frameScale or 1) })
		if ok then
			-- the parchment laid on the stone, inside the rails, its edge
			-- painted (user, 2026-09-23: "same on the whisper window")
			if skin and Kit.ParchmentSheet then
				Kit:ParchmentSheet(skin, f, { tight = true, area = "whisper" })
			end
			return true
		end
	end
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(f)
	bg:SetColorTexture(0.04, 0.04, 0.05, 0.92)
	local edges = { { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
		{ "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }
	for _, e in ipairs(edges) do
		local t = f:CreateTexture(nil, "BORDER")
		t:SetColorTexture(0.45, 0.4, 0.3, 1)
		t:SetPoint(e[1], f, e[1])
		t:SetPoint(e[2], f, e[2])
		if e[3] then
			t:SetWidth(e[3])
		end
		if e[4] then
			t:SetHeight(e[4])
		end
	end
end

-- An answer. Called from the box's OnEnterPressed, so it is the key press the
-- game wants behind a chat message.
local function SendWhisper(f, text)
	if f.kind == "BN_WHISPER" then
		if C_BattleNet and C_BattleNet.SendWhisper then
			C_BattleNet.SendWhisper(f.target, text)
		end
	elseif C_ChatInfo and C_ChatInfo.SendChatMessage then
		C_ChatInfo.SendChatMessage(text, "WHISPER", nil, f.target)
	end
end

local function CreatePopup(key, kind, target, title)
	popupCount = popupCount + 1
	local f = CreateFrame("Frame", "MelloUIWhisperPopup" .. popupCount, UIParent)
	f:SetSize(POPUP_W, POPUP_H)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f.kind, f.target, f.key = kind, target, key
	local dressed = DressPopup(f)
	f.kitDressed = dressed and true or false

	-- THE HEADER (user, 2026-09-23: the strip the window is dragged by is a
	-- header and should look like one; pick B of
	-- kit_raw/whisper_header_catalog.png): the kit's list header band across
	-- the top, as on the damage meter, with the name in its class colour and
	-- the level after it. Without the kit, a darker band with an edge under it.
	local head = CreateFrame("Frame", nil, f)
	head:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6)
	head:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -6)
	head:SetHeight(HEADER_H)
	head:EnableMouse(true)
	head:RegisterForDrag("LeftButton")
	head:SetScript("OnDragStart", function()
		f:StartMoving()
	end)
	head:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		SavePopupPosition(f)
	end)
	local Kit = MelloUI.Kit
	local nameInset = 8
	local plate
	if dressed and Kit and Kit.Strip then
		local ok, strip = pcall(Kit.Strip, Kit, head, "lists/header", { scale = (Kit.scale or 1) * (Kit.frameScale or 1) })
		if ok and strip then
			plate = strip
			local yoff = plate:FitBox(HEADER_H) or 0
			plate:ClearAllPoints()
			plate:SetPoint("LEFT", head, "LEFT", 0, yoff)
			plate:SetPoint("RIGHT", head, "RIGHT", 0, yoff)
			plate:SetHeight(plate.height)
			-- the text starts past the cap's gem (a quarter of the cap, as the
			-- damage meter's header keeps its controls off the gems)
			nameInset = (plate.wl or 0) * 0.3 + 4
		end
	end
	if not plate then
		local band = head:CreateTexture(nil, "BACKGROUND")
		band:SetAllPoints(head)
		band:SetColorTexture(0.1, 0.09, 0.08, 1)
		local line = head:CreateTexture(nil, "BORDER")
		line:SetColorTexture(0.45, 0.4, 0.3, 1)
		line:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT")
		line:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT")
		line:SetHeight(1)
	end
	-- on the plate when there is one: a child frame draws over its parent's
	-- regions, so a name on `head` would sit under the band
	local name = (plate or head):CreateFontString(nil, "OVERLAY", "GameFontNormal")
	name:SetPoint("LEFT", head, "LEFT", nameInset, 0)
	name:SetPoint("RIGHT", head, "RIGHT", -nameInset, 0)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	if dressed and Kit and Kit.TitleFont then
		pcall(Kit.TitleFont, Kit, name, true)
	end
	f.header = name
	f.titleText = title   -- a character name or a Battle.net name; both display as they are

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function()
		-- a short fade out (Core/Anim.lua), a plain hide without it
		if MelloUI.Anim then
			MelloUI.Anim:FadeOut(f, 0.12)
		else
			f:Hide()
		end
	end)

	-- the conversation: scrolls with the wheel, links click through
	local msgs = CreateFrame("ScrollingMessageFrame", nil, f)
	msgs:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -(HEADER_H + 14))
	msgs:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 40)
	msgs:SetFontObject(ChatFontNormal)
	msgs:SetJustifyH("LEFT")
	msgs:SetFading(false)
	msgs:SetMaxLines(250)
	msgs:SetHyperlinksEnabled(true)
	msgs:SetScript("OnHyperlinkClick", function(self, link, text, button)
		SetItemRef(link, text, button, self)
	end)
	msgs:EnableMouseWheel(true)
	msgs:SetScript("OnMouseWheel", function(self, delta)
		if delta > 0 then
			self:ScrollUp()
		else
			self:ScrollDown()
		end
	end)
	f.msgs = msgs

	-- the answer: Enter sends, Escape lets go of the keyboard
	local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	box:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 12)
	box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
	box:SetHeight(22)
	box:SetAutoFocus(false)   -- never takes the keyboard by itself: movement keys stay the player's
	box:SetMaxLetters(255)
	box:SetFontObject(ChatFontNormal)
	-- Enter sends and keeps the box for the next line; Enter on an empty box
	-- (or only spaces) lets go of it, as the game's chat box does (user,
	-- 2026-09-23: "if i decide not to answer and press enter ... it should
	-- automatically stop the editbox")
	box:SetScript("OnEnterPressed", function(self)
		local text = self:GetText()
		self:SetText("")
		if text and text:find("%S") then
			SendWhisper(f, text)
		else
			self:ClearFocus()
		end
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	f.box = box
	InkPopup(f)

	PlacePopup(f)
	popups[key] = f
	return f
end

-- WHO IS WHISPERING (user, 2026-09-23: "the name Should be Class Colored and
-- the Level of the person should be shown"). The class comes with every
-- whisper: its GUID answers GetPlayerInfoByGUID. The level does NOT, so it is
-- shown only when the game already knows it -- someone in the group, targeted
-- or nearby (UnitTokenFromGUID), a friend, a guild member, a Battle.net friend
-- playing WoW -- and otherwise left out (the user's choice over a /who lookup,
-- which would replace the game's Who list). Every read is secret-safe.
local function Plain(v)
	return v ~= nil and not Secret(v)
end

local function ClassHex(classFile)
	if not Plain(classFile) then
		return nil
	end
	local color = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(classFile)
		or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
	if color and color.GenerateHexColor then
		return color:GenerateHexColor()
	end
	return color and color.colorStr or nil
end

local function ClassFileFromLocalized(localized)
	if not Plain(localized) then
		return nil
	end
	for _, map in ipairs({ LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE }) do
		if type(map) == "table" then
			for file, name in pairs(map) do
				if name == localized then
					return file
				end
			end
		end
	end
	return nil
end

local function PlainLevel(level)
	return (Plain(level) and type(level) == "number" and level > 0) and level or nil
end

-- a character: class from the GUID, level from what the game already knows
local function CharacterIdentity(name, guid)
	local classFile, level
	if Plain(guid) and GetPlayerInfoByGUID then
		local ok, _, file = pcall(GetPlayerInfoByGUID, guid)
		if ok and Plain(file) then
			classFile = file
		end
	end
	if Plain(guid) and UnitTokenFromGUID then
		local ok, unit = pcall(UnitTokenFromGUID, guid)
		if ok and Plain(unit) and unit then
			local okL, lvl = pcall(UnitLevel, unit)
			level = okL and PlainLevel(lvl) or nil
		end
	end
	if not level and C_FriendList and C_FriendList.GetFriendInfo then
		local ok, info = pcall(C_FriendList.GetFriendInfo, name)
		if ok and info then
			level = PlainLevel(info.level)
		end
	end
	if not level and IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
		local okN, total = pcall(GetNumGuildMembers)
		if okN and Plain(total) and type(total) == "number" then
			for i = 1, total do
				-- name, rank, rankIndex, level, ... and the GUID 17th
				local ok, gName, _, _, gLevel, _, _, _, _, _, _, gClassFile, _, _, _, _, _, gGuid = pcall(GetGuildRosterInfo, i)
				if ok and ((Plain(gGuid) and Plain(guid) and gGuid == guid) or (Plain(gName) and gName == name)) then
					level = PlainLevel(gLevel)
					classFile = classFile or (Plain(gClassFile) and gClassFile or nil)
					break
				end
			end
		end
	end
	return classFile, level
end

-- a Battle.net friend: class and level of the character they are playing, if WoW
local function BattleNetIdentity(bnID)
	if not (C_BattleNet and C_BattleNet.GetAccountInfoByID) then
		return nil, nil
	end
	local ok, info = pcall(C_BattleNet.GetAccountInfoByID, bnID)
	local game = ok and info and info.gameAccountInfo
	if not game then
		return nil, nil
	end
	return ClassFileFromLocalized(game.className), PlainLevel(game.characterLevel)
end

-- the header: the name in its class colour (the game's gold when the class is
-- not known), the level after it in gold when it is
local function UpdateHeader(f)
	local name = f.titleText
	if not Plain(name) then
		f.header:SetText(name)
		return
	end
	local text = "|c" .. (f.classHex or "ffffd100") .. tostring(name) .. "|r"
	if f.level then
		text = text .. "  |cffffd100" .. f.level .. "|r"
	end
	f.header:SetText(text)
end

-- One whisper event. Its arguments: text, the other person's name, ..., at 12
-- their GUID and at 13 the Battle.net account id (the 10th and 11th of the rest).
local function OnWhisper(_, event, text, sender, ...)
	local how = WHISPER_EVENTS[event]
	if not (how and popupOn) then
		return
	end
	local key, target, title, classFile, level
	if how.kind == "BN_WHISPER" then
		local bnID = select(11, ...)
		if not bnID or Secret(bnID) then
			return
		end
		key, target, title = "BN:" .. tostring(bnID), bnID, sender
		classFile, level = BattleNetIdentity(bnID)
	else
		-- the name keys the window, so a secret one cannot open one; the
		-- whisper is still in the main chat
		if not sender or Secret(sender) then
			return
		end
		key, target = "W:" .. sender, sender
		title = Ambiguate and Ambiguate(sender, "short") or sender
		classFile, level = CharacterIdentity(sender, (select(10, ...)))
	end
	local f = popups[key] or CreatePopup(key, how.kind, target, title)
	-- known once is known: a later whisper without the answer keeps the earlier one
	f.classHex = ClassHex(classFile) or f.classHex
	f.level = level or f.level
	UpdateHeader(f)
	local r, g, b = PopupColor(how.kind, how.incoming)
	local who = how.incoming and f.titleText or (YOU or "You")
	if how.incoming and f.classHex then
		who = "|c" .. f.classHex .. who .. "|r"
	end
	-- A SECRET text gets the same line as any other: this client lets a
	-- secret be joined into text, the line staying secret and still shown
	-- (/mello secrets, 2026-09-23; user: "go ahead with the whisper popup").
	-- Nothing here compares it. Should the frame ever refuse the joined line,
	-- the text alone, as before.
	-- the parts kept, so the conversation can be written again in ink or in
	-- its colours when the parchment is switched (QuestInk's rule)
	local entry = { stamp = date("%H:%M"), who = who, text = text, r = r, g = g, b = b }
	f.lineLog = f.lineLog or {}
	table.insert(f.lineLog, entry)
	if #f.lineLog > 250 then
		table.remove(f.lineLog, 1)
	end
	WriteWhisperLine(f, entry)
	-- it rises into its place as it fades in (Core/Anim.lua); one fading out
	-- when the whisper came is simply brought back, without the rise
	local Anim = MelloUI.Anim
	if not f:IsShown() then
		if Anim then
			Anim:Pop(f, 0.22, 10)
		else
			f:Show()
		end
	elseif Anim and Anim:IsRunning(f, "alpha") then
		Anim:FadeIn(f, 0.15)
	end
	f:Raise()
end

-- the game's whisper setting: whispers in the main chat while the popups are
-- on, the user's own setting back when they go off
local WHISPER_CVAR = "whisperMode"

local function SetWhisperMode(on)
	local db = M.db
	if not (db and C_CVar and C_CVar.GetCVar) then
		return
	end
	if on then
		if db.savedWhisperMode == nil then
			local ok, current = pcall(C_CVar.GetCVar, WHISPER_CVAR)
			db.savedWhisperMode = (ok and current and not Secret(current)) and current or "popout"
		end
		pcall(C_CVar.SetCVar, WHISPER_CVAR, "inline")
	elseif db.savedWhisperMode ~= nil then
		pcall(C_CVar.SetCVar, WHISPER_CVAR, db.savedWhisperMode)
		db.savedWhisperMode = nil
	end
end

local function SetWhisperPopup(on)
	popupOn = on and true or false
	if popupOn then
		for event in pairs(WHISPER_EVENTS) do
			whisperEvents:RegisterEvent(event)
		end
		whisperEvents:SetScript("OnEvent", OnWhisper)
	else
		whisperEvents:UnregisterAllEvents()
		for _, f in pairs(popups) do
			f:Hide()
		end
	end
	SetWhisperMode(popupOn)
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

local function ApplyArt()
	SetBackgroundShown(not HideArt("hideBackground"))
	SetEditBoxArtShown(not HideArt("hideEditBox"))
	SetTabArtShown(not HideArt("hideTabs"))
end

local coverWatched = false

-- The parts of this module that live on each chat window, applied to every
-- window there is -- again whenever the game opens a whisper window, which it
-- does on the fly (a post-hook: the game's function runs untouched first).
local function ApplyWindows()
	local db = M.db
	ApplyArt()
	SetTabsOnMouseover(db.tabsOnMouseover)
	SetEditBoxOnTop(db.editBoxTop)
	SetButtonsHidden(db.hideButtons)
end

local watchingWhisperWindows = false

local function WatchWhisperWindows()
	if watchingWhisperWindows or type(FCF_OpenTemporaryWindow) ~= "function" then
		return
	end
	watchingWhisperWindows = true
	hooksecurefunc("FCF_OpenTemporaryWindow", function()
		if M.isEnabled and M.db then
			ApplyWindows()
			HookLines()
		end
	end)
end

local function ApplyAll()
	local db = M.db
	if not coverWatched and MelloUI.Kit then
		coverWatched = true
		MelloUI.Kit:OnCover(function(group)
			if group == "chat" and M.isEnabled then
				ApplyArt()
				SetTabsOnMouseover(M.db.tabsOnMouseover)
			end
		end)
	end
	ApplyArt()
	SetTabsOnMouseover(db.tabsOnMouseover)
	SetEditBoxOnTop(db.editBoxTop)
	SetButtonsHidden(db.hideButtons)
	HookLines()
	ApplyClassColors(db.classColors)
	SetWhisperPopup(db.whisperPopup)
	WatchWhisperWindows()
end

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	ApplyAll()
end

function M:OnDisable()
	SetBackgroundShown(true)
	SetEditBoxArtShown(true)
	SetTabArtShown(true)
	SetTabsOnMouseover(false)
	SetEditBoxOnTop(false)
	SetButtonsHidden(false)
	ApplyClassColors(false)
	SetWhisperPopup(false)
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "hideBackground" or key == "hideEditBox" or key == "hideTabs" then
		ApplyArt()
	elseif key == "tabsOnMouseover" then
		SetTabsOnMouseover(value)
	elseif key == "hideButtons" then
		SetButtonsHidden(value)
	elseif key == "editBoxTop" then
		SetEditBoxOnTop(value)
	elseif key == "shortChannels" then
		HookLines()
	elseif key == "classColors" then
		ApplyClassColors(value)
	elseif key == "whisperPopup" then
		SetWhisperPopup(value)
	end
end
