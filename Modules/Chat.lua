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
		nameStyle = "full",
		nameShade = true,
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
		{ type = "toggle", key = "hideBrackets", parent = "shortChannels", name = "Hide Brackets",
		  desc = "Also remove the square brackets around the short channel tags." },
		{ type = "toggle", key = "classColors", name = "Class Coloured Names",
		  desc = "Colour player names by class in every chat type (sets the chatClassColorOverride CVar)." },
		{ type = "dropdown", key = "nameStyle", name = "Names In Chat", values = {
			{ value = "full", label = "Full name (Professor Skillybones)" },
			{ value = "initial", label = "Initial and surname (P. Skillybones)" },
			{ value = "firstinitial", label = "Name and initial (Professor S.)" },
			{ value = "first", label = "First name (Professor)" },
			{ value = "last", label = "Surname (Skillybones)" },
		  }, desc = "How a player's name is written in the chat windows and the whisper windows. A name without a surname stays as it is; the name is still a link to the player." },
		{ type = "toggle", key = "nameShade", name = "Shade Behind Names",
		  desc = "On the parchment sheet, a soft dark band behind a line's channel tag and the player's name, so their bright class and channel colours read without an outline. The rest of the line is in dark ink." },
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

--------------------------------------------------------------------------------
-- Names In Chat (user, 2026-09-24: "Professor Skillybones goes either P.
-- Skillybones or Professor S."): the name a player link shows, shortened;
-- the link itself (who it is) is left as it is. Characters here have a
-- first name and a surname; a name of one word stays whole.
--------------------------------------------------------------------------------

-- the first letter of a word (a UTF-8 character, not a byte)
local function Initial(word)
	return word:match("^[%z\1-\127\194-\244][\128-\191]*") or word:sub(1, 1)
end

local function ShortPerson(name, style)
	if type(name) ~= "string" or style == nil or style == "full" then
		return name
	end
	local core, realm = name:match("^(.-)(%-[^%s]+)$")
	core, realm = core or name, realm or ""
	local first, last = core:match("^(%S+)%s+(.+)$")
	if not first then
		return name
	end
	if style == "initial" then
		return Initial(first) .. ". " .. last .. realm
	elseif style == "firstinitial" then
		return first .. " " .. Initial(last) .. "." .. realm
	elseif style == "first" then
		return first .. realm
	elseif style == "last" then
		return last .. realm
	end
	return name
end

local function NameStyle()
	local style = Active("nameStyle")
	return type(style) == "string" and style ~= "full" and style or nil
end

-- the shown name in each player link of a line: "[|cffc79c6eName|r]",
-- "[Name]", "Name", with a hex or a named colour
local function ShortNames(text, style)
	return (text:gsub("(|Hplayer:[^|]*|h)(.-)(|h)", function(open, shown, close)
		local pre, core, post = shown:match("^(%[?|c%x%x%x%x%x%x%x%x)(.-)(|r%]?)$")
		if not pre then
			pre, core, post = shown:match("^(%[?|cn[%w_]+:)(.-)(|r%]?)$")
		end
		if not pre then
			pre, core, post = shown:match("^(%[?)(.-)(%]?)$")
		end
		if not core or core == "" then
			return nil
		end
		return open .. pre .. ShortPerson(core, style) .. post .. close
	end))
end

local function OnLineAdded(chatFrame, text)
	local short, style = Active("shortChannels"), NameStyle()
	if transformFailed or not (short or style) then
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
	local function Rewritten(t)
		if short then
			t = Shorten(t)
		end
		if style then
			t = ShortNames(t, style)
		end
		return t
	end
	local function Rewrite(e, ...)
		if type(e) == "table" then
			e.message = Rewritten(e.message)
			return e, ...
		end
		return Rewritten(e), ...
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

-- The chat's inks (user, 2026-09-24: "match the Chat color when we have a
-- Parchment behind it"): one designed dark ink per kind of chat, each at
-- 5 : 1 or better on the vellum and apart from the others by its hue --
-- say in the text ink, guild green, party blue, raid amber, whispers plum,
-- Battle.net teal, channels rosewood, yells red, the system ochre. A line's
-- kind is read back from its colour (ChatTypeInfo, the player's own colour
-- choices included); a colour of no known kind gets QuestInk's ink of it.
local CHAT_INKS = {
	say      = { 0.227, 0.165, 0.110 },   -- #3A2A1C
	emote    = { 0.403, 0.201, 0.053 },   -- #67330D
	yell     = { 0.505, 0.091, 0.054 },   -- #81170E
	party    = { 0.116, 0.238, 0.524 },   -- #1E3D86
	raid     = { 0.391, 0.210, 0.014 },   -- #643504
	warning  = { 0.485, 0.125, 0.000 },   -- #7C2000
	instance = { 0.349, 0.232, 0.043 },   -- #593B0B
	guild    = { 0.088, 0.295, 0.075 },   -- #164B13
	officer  = { 0.197, 0.281, 0.064 },   -- #324810
	whisper  = { 0.448, 0.108, 0.389 },   -- #721B63
	bnet     = { 0.036, 0.284, 0.304 },   -- #09484D
	channel  = { 0.416, 0.180, 0.165 },   -- #6A2E2A
	system   = { 0.306, 0.251, 0.023 },   -- #4E4006
	loot     = { 0.093, 0.294, 0.093 },   -- #184B18
	money    = { 0.320, 0.245, 0.018 },   -- #523F05
	skill    = { 0.164, 0.226, 0.539 },   -- #2A3A89
	npc      = { 0.305, 0.250, 0.084 },   -- #4E4015
}
-- the chat types, in the order they win when two share a colour
local CHAT_INK_TYPES = {
	{ "SAY", "say" }, { "YELL", "yell" }, { "EMOTE", "emote" }, { "TEXT_EMOTE", "emote" },
	{ "PARTY", "party" }, { "PARTY_LEADER", "party" }, { "RAID", "raid" }, { "RAID_LEADER", "raid" },
	{ "RAID_WARNING", "warning" }, { "INSTANCE_CHAT", "instance" }, { "INSTANCE_CHAT_LEADER", "instance" },
	{ "GUILD", "guild" }, { "OFFICER", "officer" }, { "WHISPER", "whisper" }, { "WHISPER_INFORM", "whisper" },
	{ "BN_WHISPER", "bnet" }, { "BN_WHISPER_INFORM", "bnet" }, { "BN_INLINE_TOAST_ALERT", "bnet" },
	{ "SYSTEM", "system" }, { "LOOT", "loot" }, { "CURRENCY", "loot" }, { "MONEY", "money" },
	{ "SKILL", "skill" }, { "ACHIEVEMENT", "money" }, { "GUILD_ACHIEVEMENT", "money" },
	{ "MONSTER_SAY", "npc" }, { "MONSTER_PARTY", "npc" }, { "MONSTER_WHISPER", "npc" },
	{ "MONSTER_YELL", "yell" }, { "MONSTER_EMOTE", "emote" }, { "RAID_BOSS_EMOTE", "warning" }, { "RAID_BOSS_WHISPER", "warning" },
	{ "CHANNEL", "channel" },
}
for i = 1, 20 do
	CHAT_INK_TYPES[#CHAT_INK_TYPES + 1] = { "CHANNEL" .. i, "channel" }
end

local inkByColour = nil   -- "r,g,b" -> ink, from ChatTypeInfo; rebuilt when the chat's colours change

local function ColourKey(r, g, b)
	return string.format("%.2f,%.2f,%.2f", r, g, b)
end

local function ChatInk(r, g, b)
	if not inkByColour then
		inkByColour = {}
		for _, entry in ipairs(CHAT_INK_TYPES) do
			local info = ChatTypeInfo and ChatTypeInfo[entry[1]]
			if info and type(info.r) == "number" and not Secret(info.r) then
				local key = ColourKey(info.r, info.g, info.b)
				inkByColour[key] = inkByColour[key] or CHAT_INKS[entry[2]]
			end
		end
	end
	local ink = inkByColour[ColourKey(r, g, b)]
	if ink then
		return ink[1], ink[2], ink[3]
	end
	return MelloUI.QuestInk.InkOf(r, g, b)
end

do
	local watch = CreateFrame("Frame")
	watch:RegisterEvent("UPDATE_CHAT_COLOR")
	watch:SetScript("OnEvent", function()
		inkByColour = nil
	end)
end

local function Number(v)
	return type(v) == "number" and not Secret(v)
end

local function ChatInked()
	local Kit = MelloUI.Kit
	return (MelloUI.QuestInk ~= nil and Kit and Kit.IsCovered and Kit:IsCovered("chat")
		and Kit.ParchmentOn and Kit:ParchmentOn("chat")) and true or false
end

-- Where the sender's part of a line ends (its channel tag and the player's
-- name, or a coloured sender such as MelloUI's own prefix): the end of the
-- first player link, else the colon after a coloured start; 0 for none
local function SenderEnd(text)
	local _, stop = text:find("|HB?N?player:[^|]*|h.-|h")
	if stop then
		return stop
	end
	local colon = text:find(": ", 1, true)
	if colon and text:sub(1, colon):find("|c", 1, true) then
		return colon - 1
	end
	return 0
end

-- The colour codes of a text in ink, its links left in their colours (the
-- item's quality, a player's class: user, 2026-09-24, "we are going to keep
-- Class Colored Names and links"): each link with the code before it put
-- aside, the rest inked, the links put back
local function InkKeepLinks(text)
	local kept = {}
	local function Keep(link)
		kept[#kept + 1] = link
		return "\1" .. #kept .. "\2"
	end
	text = text:gsub("|c[^|]*|H.-|h.-|h", Keep)
	text = text:gsub("|H.-|h.-|h", Keep)
	text = MelloUI.QuestInk.InkCodes(text)
	return (text:gsub("\1(%d+)\2", function(i) return kept[tonumber(i)] end))
end

local function Hex(r, g, b)
	return string.format("ff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- A line on the paper (user, 2026-09-24): the sender's part -- channel tag
-- and player name -- keeps its bright colours and lies on a soft dark band
-- (ShadeLines below), its plain parts (brackets, the colon) held in the
-- line's own colour so they read on the band too; the rest is dark ink,
-- links kept.
--
-- The ink is written INTO the text as colour codes (/chatink, 2026-09-24:
-- this client's chat hands TransformMessages a copy of each line and keeps
-- only its text; a new colour or a mark on the copy was lost, so no line
-- ever took its ink): the body opens in the chat kind's ink and every |r in
-- it (after a link, a name) opens it again.
local function InkLine(text, r, g, b)
	local cut = SenderEnd(text)
	local head, body = text:sub(1, cut), text:sub(cut + 1)
	local readable = Number(r) and Number(g) and Number(b)
	if cut > 0 and readable then
		local hex = Hex(r, g, b)
		head = "|c" .. hex .. head:gsub("|r", "|r|c" .. hex) .. "|r"
	end
	body = InkKeepLinks(body)
	if readable then
		local ink = Hex(ChatInk(r, g, b))
		body = "|c" .. ink .. body:gsub("|r", "|r|c" .. ink) .. "|r"
	end
	return head .. body
end

-- The ink goes on the lines as they are DRAWN (/chatink, 2026-09-24: this
-- client's chat history cannot be rewritten for it -- TransformMessages
-- hands out copies and reaches only a few lines -- so no line ever took its
-- ink). After every redraw of a chat window (its RefreshDisplay, which sets
-- each visible line from the history) each visible line's text is written
-- again as InkLine has it and its colour set to the chat kind's ink; a
-- protected (secret) line cannot be read, so only its colour takes the
-- ink. The history is never touched: off, the next redraw -- or the put-back
-- below, at once -- shows the game's own text. What was changed on a line is
-- kept beside it (a weak side table), never on the game's font string.
local lineState = setmetatable({}, { __mode = "k" })   -- [font string] = { inked, plain, rgb, ink }
local inkFrames = setmetatable({}, { __mode = "k" })   -- [message frame] = true: its lines take the ink

local function SameColour(r, g, b, c)
	return c ~= nil and math.abs(r - c[1]) < 0.002 and math.abs(g - c[2]) < 0.002 and math.abs(b - c[3]) < 0.002
end

local function InkDrawnLine(line, on)
	local okT, text = pcall(line.GetText, line)
	if not okT or text == nil then
		return
	end
	local state = lineState[line]
	local secret = Secret(text)
	local okC, r, g, b = pcall(line.GetTextColor, line)
	local rgbReadable = okC and Number(r) and Number(g) and Number(b)
	if on then
		-- still our ink from the last pass (no redraw since): left as it is
		if state and (secret or text == state.inked) and (not rgbReadable or SameColour(r, g, b, state.ink)) then
			return
		end
		state = { rgb = rgbReadable and { r, g, b } or nil }
		if not secret and type(text) == "string" then
			state.plain = text
			state.inked = InkLine(text, r, g, b)
			line:SetText(state.inked)
		end
		if rgbReadable then
			local ir, ig, ib = ChatInk(r, g, b)
			state.ink = { ir, ig, ib }
			line:SetTextColor(ir, ig, ib)
		end
		lineState[line] = state
	elseif state then
		-- put back what is still ours (a redraw since has done it already)
		if state.inked and not secret and text == state.inked then
			line:SetText(state.plain)
		end
		if state.rgb and rgbReadable and SameColour(r, g, b, state.ink) then
			line:SetTextColor(state.rgb[1], state.rgb[2], state.rgb[3])
		end
		lineState[line] = nil
	end
end

-- The drawn lines in the face and size the Fonts module wants for this
-- window (user, 2026-09-24: "the Chat font still refuses to change to the
-- Font Style"): the Font Style's chat face on the stone, its parchment face
-- on the paper, without an outline while in ink. Set on each line after
-- every redraw, so whatever sets the lines' font behind it (the game, the
-- chat's shared font object) is undone at the next one.
local function FitLineFonts(frame)
	local lines = frame and frame.visibleLines
	local fonts = MelloUI:GetModule("Fonts")
	if not (inkFrames[frame] and type(lines) == "table" and fonts and fonts.isEnabled and fonts.ChatWindowFont) then
		return
	end
	local inked = ChatInked()
	local okW, path, size = pcall(fonts.ChatWindowFont, fonts, frame, inked)
	if not (okW and path and size) then
		return
	end
	local okF, _, _, frameFlags = pcall(frame.GetFont, frame)
	local flags = inked and "" or (okF and frameFlags) or ""
	for _, line in ipairs(lines) do
		local okL, lpath, lsize, lflags = pcall(line.GetFont, line)
		if okL and (lpath ~= path or math.abs((lsize or 0) - size) > 0.05 or (lflags or "") ~= flags) then
			pcall(line.SetFont, line, path, size, flags)
		end
	end
end

local function InkVisible(frame)
	local lines = frame and frame.visibleLines
	if not (inkFrames[frame] and type(lines) == "table") then
		return
	end
	local on = ChatInked()
	for _, line in ipairs(lines) do
		pcall(InkDrawnLine, line, on)
	end
end

--------------------------------------------------------------------------------
-- The shade behind names (user, 2026-09-24: "the best way to be able to read
-- it without having to use Outlines would be to place a soft darkening
-- behind the Channel Name and the Players Name"): on the paper, a small soft
-- band under each BRIGHT piece of a line's first row -- the channel tag,
-- the player's name, a coloured sender (MelloUI's prefix, a whisper
-- window's time and name), a link -- and nothing under the ink (user,
-- 2026-09-24: one band from the line's start covered an NPC's speech,
-- dark on dark). Each band is three pieces of one feathered texture (its
-- ends kept at their shape, its middle stretched), measured on the line's
-- own font, placed by the width of the text before it. The pieces are found
-- in the text the game wrote (the ink only adds colour codes, which have no
-- width); a protected line's text cannot be read, so it has none. Needs
-- the message frame's visible lines (this client's Lua message frame:
-- visibleLines, RefreshDisplay); without them nothing is drawn.
--------------------------------------------------------------------------------

local SHADE_FILE = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Chat\\name_shade"
local SHADE_ALPHA = 0.55
local SHADE_COLOUR = { 0.180, 0.122, 0.078 }   -- the palette's raised panel, #2E1F14: a warm dark on the paper
local SHADE_PAD = 3                             -- UI px the band reaches past its text on each side
local shades = setmetatable({}, { __mode = "k" })       -- [message frame] = { [line * 10 + piece] = band }
local shadeWanted = setmetatable({}, { __mode = "k" })  -- [message frame] = function() -> on?
local measure = nil

local function MeasureWidth(line, text)
	if not measure then
		local host = CreateFrame("Frame", nil, UIParent)
		host:Hide()
		measure = host:CreateFontString(nil, "ARTWORK")
	end
	local ok, path, size, flags = pcall(line.GetFont, line)
	if not (ok and path and size) then
		return nil
	end
	if text == "" then
		return 0, size
	end
	measure:SetFont(path, size, flags or "")
	measure:SetText(text)
	local okW, w = pcall(measure.GetUnboundedStringWidth, measure)
	if not okW or Secret(w) then
		return nil
	end
	return w, size
end

-- The bright pieces of a line: { first, last } character spans in `text`,
-- in order. The channel tag (its link, or a coloured tag at the start such
-- as a whisper's), the player's name (its link), else a coloured sender
-- before the first colon; then every other link.
local function BrightPieces(text)
	local pieces = {}
	local taken = {}
	local function Add(a, b)
		if a and b and b >= a then
			pieces[#pieces + 1] = { a, b }
			for k = a, b do
				taken[k] = true
			end
		end
	end
	local ca, cb = text:find("|Hchannel:[^|]*|h.-|h")
	if ca and ca <= 12 then
		Add(ca, cb)
	else
		Add(text:find("^%[?|c%x%x%x%x%x%x%x%x[^|]-|r%]?"))
	end
	local pa, pb = text:find("|HB?N?player:[^|]*|h.-|h")
	if pa then
		Add(pa, pb)
	else
		local cut = SenderEnd(text)
		if cut > 0 then
			local from = (#pieces > 0 and pieces[#pieces][2] + 1) or 1
			Add(from, cut)
		end
	end
	local at = 1
	while true do
		local la, lb, kind = text:find("|H(%a+):[^|]*|h.-|h", at)
		if not la then
			break
		end
		if kind ~= "channel" and kind ~= "player" and kind ~= "BNplayer" and not taken[la] then
			-- the link's colour code just before it belongs to it
			local code = text:sub(1, la - 1):match("()|c[^|]*$")
			Add(code or la, lb)
		end
		at = lb + 1
	end
	table.sort(pieces, function(x, y) return x[1] < y[1] end)
	-- pieces that touch are one band (MelloUI's two-coloured name)
	local merged = {}
	for _, piece in ipairs(pieces) do
		local last = merged[#merged]
		if last and piece[1] <= last[2] + 1 then
			last[2] = math.max(last[2], piece[2])
		else
			merged[#merged + 1] = { piece[1], piece[2] }
		end
	end
	return merged
end

-- the layer under a line's text, on the frame that draws it
local UNDER = { OVERLAY = "ARTWORK", ARTWORK = "BORDER", BORDER = "BACKGROUND", BACKGROUND = "BACKGROUND" }

local function Band(frame, line, key)
	shades[frame] = shades[frame] or {}
	local band = shades[frame][key]
	if band then
		return band
	end
	local owner = line:GetParent() or frame
	local layer = UNDER[(line:GetDrawLayer())] or "BACKGROUND"
	band = {}
	for j, part in ipairs({ { 0, 0.25 }, { 0.25, 0.75 }, { 0.75, 1 } }) do
		local t = owner:CreateTexture(nil, layer, nil, layer == "BACKGROUND" and -8 or 7)
		t:SetTexture(SHADE_FILE)
		t:SetTexCoord(part[1], part[2], 0, 1)
		t:SetVertexColor(SHADE_COLOUR[1], SHADE_COLOUR[2], SHADE_COLOUR[3], 1)
		t:Hide()
		band[j] = t
	end
	shades[frame][key] = band
	return band
end

local function HideBand(band)
	for _, t in ipairs(band) do
		t:Hide()
	end
end

local function PlaceBand(band, line, x0, x1, size, alpha)
	local h = size * 1.2
	local cap = math.min(h * 0.45, (x1 - x0) / 2)
	local y = (h - size) / 2 + 1
	band[1]:ClearAllPoints()
	band[1]:SetPoint("TOPLEFT", line, "TOPLEFT", x0, y)
	band[1]:SetSize(cap, h)
	band[2]:ClearAllPoints()
	band[2]:SetPoint("TOPLEFT", line, "TOPLEFT", x0 + cap, y)
	band[2]:SetSize(math.max(0.1, (x1 - x0) - 2 * cap), h)
	band[3]:ClearAllPoints()
	band[3]:SetPoint("TOPLEFT", line, "TOPLEFT", x1 - cap, y)
	band[3]:SetSize(cap, h)
	for _, t in ipairs(band) do
		t:SetAlpha(alpha)
		t:Show()
	end
end

local function ShadeLines(frame)
	local lines = frame and frame.visibleLines
	local want = shadeWanted[frame]
	local on = type(lines) == "table" and want and want() and Active("nameShade") ~= false
	local used = {}
	if on then
		for i, line in ipairs(lines) do
			local shown = line.IsShown and line:IsShown()
			local justify = line.GetJustifyH and line:GetJustifyH()
			-- a chat window's line: the text the game wrote, kept when it was
			-- inked; a whisper window's: the line as it is
			local text
			if inkFrames[frame] then
				local state = lineState[line]
				text = state and state.plain
			else
				local okT, t = pcall(line.GetText, line)
				text = okT and t or nil
			end
			if shown and type(text) == "string" and not Secret(text) and (justify == nil or justify == "LEFT") then
				local okW, rowWidth = pcall(line.GetWidth, line)
				rowWidth = (okW and not Secret(rowWidth) and rowWidth) or 0
				local alpha = SHADE_ALPHA * (line.GetAlpha and line:GetAlpha() or 1)
				for k, piece in ipairs(BrightPieces(text)) do
					if k > 9 then
						break
					end
					local before, size = MeasureWidth(line, text:sub(1, piece[1] - 1))
					local width = before and MeasureWidth(line, text:sub(piece[1], piece[2]))
					-- the first row only: a piece past its end may have wrapped
					if before and width and width > 0 and size and (rowWidth <= 0 or before + width <= rowWidth - 4) then
						local key = i * 10 + k
						PlaceBand(Band(frame, line, key), line, before - SHADE_PAD, before + width + SHADE_PAD, size, alpha)
						used[key] = true
					end
				end
			end
		end
	end
	for key, band in pairs(shades[frame] or {}) do
		if not used[key] then
			HideBand(band)
		end
	end
end

-- A message frame's lines get their shade while `wanted()` (the chat on its
-- paper, a whisper window on its own), after every redraw of its lines
local function WatchShade(frame, wanted)
	if not frame or shadeWanted[frame] then
		return
	end
	shadeWanted[frame] = wanted
	local function AfterRedraw(f)
		pcall(FitLineFonts, f)
		InkVisible(f)
		ShadeLines(f)
	end
	for _, method in ipairs({ "RefreshDisplay", "RefreshLayout" }) do
		if type(frame[method]) == "function" then
			hooksecurefunc(frame, method, AfterRedraw)
		end
	end
	AfterRedraw(frame)
end

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
	-- the parchment's own chat face and size (Fonts) first when the sheet
	-- comes, so the ink's font (no outline) is the last word; after the
	-- outline is back when it goes
	local fonts = MelloUI:GetModule("Fonts")
	local refresh = fonts and fonts.isEnabled and fonts.RefreshChatWindows
	if on and refresh then
		pcall(fonts.RefreshChatWindows, fonts)
	end
	for _, name in ipairs(ChatFrameNames()) do
		local frame = _G[name]
		if frame and frame ~= _G.COMBATLOG then
			pcall(InkFrameFont, frame, on)
			-- the drawn lines in their font, inked or put back at once
			pcall(FitLineFonts, frame)
			pcall(InkVisible, frame)
			pcall(ShadeLines, frame)
		end
	end
	if not on and refresh then
		pcall(fonts.RefreshChatWindows, fonts)
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
			-- the ink and the bands go on its lines as they are drawn
			inkFrames[frame] = true
			WatchShade(frame, ChatInked)
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
	-- the face and size of the chat on the stone or on the paper, whichever
	-- this window lies on (the chat window's own may be the other)
	local fonts = MelloUI:GetModule("Fonts")
	if fonts and fonts.isEnabled and fonts.ChatWindowFont then
		local fpath, fsize = fonts:ChatWindowFont(src, f.inked)
		if fpath and fsize then
			path, size = fpath, fsize
		end
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
	WatchShade(f.msgs, function() return f.inked end)
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

-- One conversation line, in ink on parchment, else in its colours: the
-- main chat's rules (user, 2026-09-24: "the Whisper Popup Window follows the
-- same rules as the main chat") -- the time and the name bright on their
-- soft band, the words in the whisper's ink, links kept
WriteWhisperLine = function(f, e)
	local ink = WhisperInked() and f.kitDressed
	local r, g, b = e.r, e.g, e.b
	local line = ("|cff8a8a8a%s|r %s: %s"):format(e.stamp, e.who, e.text)
	if ink then
		if not Secret(e.text) then
			line = InkLine(line, r, g, b)
		end
		r, g, b = ChatInk(r, g, b)
	end
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
	local who = how.incoming and ShortPerson(f.titleText, NameStyle()) or (YOU or "You")
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
	elseif key == "nameShade" then
		for frame in pairs(shadeWanted) do
			pcall(ShadeLines, frame)
		end
	elseif key == "whisperPopup" then
		SetWhisperPopup(value)
	end
end

--------------------------------------------------------------------------------
-- /chatink [n]: how the ink took on chat window n (1 by default): its lines,
-- the inked, the protected (secret) ones, the colours left bright in inked
-- lines, and the game's chat filter hooks this client offers (for the names
-- of protected lines)
--------------------------------------------------------------------------------
SLASH_MELLOCHATINK1 = "/chatink"
SlashCmdList.MELLOCHATINK = function(msg)
	local n = tonumber(msg) or 1
	local frame = _G["ChatFrame" .. n]
	if not frame then
		MelloUI:Print("/chatink: no chat window %d.", n)
		return
	end
	MelloUI:ClearLog()
	local lines = frame.visibleLines
	local shown, inked, secret, bright = 0, 0, 0, {}
	for _, line in ipairs(type(lines) == "table" and lines or {}) do
		if line:IsShown() then
			shown = shown + 1
			local okT, text = pcall(line.GetText, line)
			local state = lineState[line]
			if okT and Secret(text) then
				secret = secret + 1
			end
			if state then
				inked = inked + 1
			end
			if okT and type(text) == "string" and not Secret(text) and state and #bright < 6 then
				-- the body only, its links left out: names and links stay bright by design
				local body = text:sub(SenderEnd(text) + 1):gsub("|c[^|]*|H.-|h.-|h", ""):gsub("|H.-|h.-|h", "")
				for code in body:gmatch("|c(%x%x%x%x%x%x%x%x)") do
					local r, g, b = tonumber(code:sub(3, 4), 16) / 255, tonumber(code:sub(5, 6), 16) / 255, tonumber(code:sub(7, 8), 16) / 255
					if 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.45 then
						bright[#bright + 1] = code .. " in: " .. text:sub(1, 90):gsub("|", "||")
						break
					end
				end
			end
		end
	end
	MelloUI:Print("ChatFrame%d: %d lines drawn, %d inked, %d protected. Parchment ink %s.", n, shown, inked, secret, ChatInked() and "on" or "off")
	local Kit, QI = MelloUI.Kit, MelloUI.QuestInk
	local um = MelloUI:GetModule("UIModifications")
	local surface = QI and QI.surfaces and QI.surfaces.chat
	MelloUI:Print("  ink engine %s, chat reskin covered %s, parchment_chat %s, surface %s (active %s), ink on its lines %s, outline flags %q",
		tostring(QI ~= nil), tostring(Kit and Kit.IsCovered and Kit:IsCovered("chat")),
		tostring(um and um.db and um.db.parchment_chat), surface and "registered" or "missing",
		tostring(surface and surface.active), tostring(inkFrames[frame] or false), tostring(select(3, frame:GetFont())))
	local banded = 0
	for _, band in pairs(shades[frame] or {}) do
		if band[1]:IsShown() then
			banded = banded + 1
		end
	end
	MelloUI:Print("  name shade: visible lines %s, RefreshDisplay %s, bands shown %d",
		type(lines) == "table" and tostring(#lines) or "none", tostring(type(frame.RefreshDisplay) == "function"), banded)
	for _, line in ipairs(bright) do
		MelloUI:Print("  still bright: %s", line)
	end
	-- the first drawn lines as they are now, codes shown
	local listed = 0
	for _, line in ipairs(type(lines) == "table" and lines or {}) do
		local okT, text = pcall(line.GetText, line)
		if listed < 4 and line:IsShown() and okT and type(text) == "string" and not Secret(text) then
			listed = listed + 1
			MelloUI:Print("  line: %s", (text:sub(1, 160):gsub("|", "||")))
		end
	end
	local util = _G.ChatFrameUtil
	local hooks = {}
	if type(util) == "table" then
		for k, v in pairs(util) do
			if type(v) == "function" and (k:find("Filter") or k:find("Sender")) then
				hooks[#hooks + 1] = k
			end
		end
	end
	table.sort(hooks)
	MelloUI:Print("Chat hooks: %s", #hooks > 0 and table.concat(hooks, ", ") or "none found in ChatFrameUtil")
	-- the fonts: what the Fonts module wants, and what each link of the
	-- chain -- the window, its font object, a drawn line, the chat's shared
	-- font object -- has now (the chat not following the Font Style)
	local function FontOf(obj)
		if not (obj and obj.GetFont) then
			return "none"
		end
		local ok, path, size, flags = pcall(obj.GetFont, obj)
		if not ok or not path then
			return "unreadable"
		end
		return string.format("%s %s %q", tostring(path):match("[^\\/]+$") or tostring(path), tostring(size and math.floor(size * 10 + 0.5) / 10), tostring(flags))
	end
	local function ObjName(obj)
		return obj and ((obj.GetName and obj:GetName()) or tostring(obj)) or "none"
	end
	local fonts = MelloUI:GetModule("Fonts")
	local fdb = fonts and fonts.db
	MelloUI:Print("Fonts: module %s, style %s", tostring(fonts and fonts.isEnabled), tostring(fdb and fdb.style))
	MelloUI:Print("  chat %s | chat text %s | chat on parchment %s",
		tostring(fdb and fdb.fontChat):match("[^\\/]+$") or "?", tostring(fdb and fdb.fontChatText):match("[^\\/]+$") or "?",
		tostring(fdb and fdb.fontChatParchment):match("[^\\/]+$") or "?")
	if fonts and fonts.ChatWindowFont then
		local okW, path, size = pcall(fonts.ChatWindowFont, fonts, frame, ChatInked())
		MelloUI:Print("  wanted on this window: %s %s", okW and tostring(path):match("[^\\/]+$") or "?", okW and tostring(size) or "?")
	end
	local fobj = frame.GetFontObject and frame:GetFontObject()
	MelloUI:Print("  window: %s | its font object %s: %s", FontOf(frame), ObjName(fobj), FontOf(fobj))
	local first = type(lines) == "table" and lines[1]
	local lobj = first and first.GetFontObject and first:GetFontObject()
	MelloUI:Print("  drawn line: %s | its font object %s: %s", FontOf(first), ObjName(lobj), FontOf(lobj))
	MelloUI:Print("  ChatFontNormal: %s", FontOf(_G.ChatFontNormal))
	-- into the copy window, selected: Ctrl+C copies it (an addon cannot
	-- reach the system clipboard itself)
	MelloUI:ShowLog("chatink")
end
