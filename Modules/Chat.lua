--------------------------------------------------------------------------------
-- MelloUI - Chat
--
--   * hide the chat window background and border art
--   * hide the input box border art
--   * short, saturated channel tags:  G  Guild,  P  Party,  R  Raid,
--     RW  Raid Warning,  W  Whisper,  G  General,  T  Trade, ...
--   * class coloured player names in every chat type
--
-- Channel tags for guild / party / raid / whisper come from the CHAT_*_GET
-- format strings Blizzard uses to build every line, so they can be replaced
-- outright. Numbered channels (General, Trade, ...) are named through
-- ChatFrameUtil.ResolvePrefixedChannelName, which is wrapped. Message text
-- itself is never touched, so secret chat payloads are safe.
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
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
	},
})

local function Active(key)
	return M.isEnabled and M.db and M.db[key]
end

local function NumWindows()
	return NUM_CHAT_WINDOWS or 10
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
	for i = 1, NumWindows() do
		local name = "ChatFrame" .. i
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
	for i = 1, NumWindows() do
		local editBox = _G["ChatFrame" .. i .. "EditBox"]
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

-- Blizzard fades tabs between a "mouse over" and a "no mouse" alpha; setting
-- the latter to zero hides them until the chat is hovered. Alerting tabs keep
-- their own constants so whisper flashes stay visible.
local TAB_ALPHA_OVERRIDES = {
	CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA = 0,
	CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA = 0,
	CHAT_FRAME_TAB_NORMAL_MOUSEOVER_ALPHA = 1,
}

local tabAlphaOriginals = {}

local function SetTabsOnMouseover(enabled)
	for name, override in pairs(TAB_ALPHA_OVERRIDES) do
		if tabAlphaOriginals[name] == nil and type(_G[name]) == "number" then
			tabAlphaOriginals[name] = _G[name]
		end
		if enabled then
			_G[name] = override
		elseif tabAlphaOriginals[name] ~= nil then
			_G[name] = tabAlphaOriginals[name]
		end
	end
	if type(FCFTab_UpdateAlpha) == "function" then
		for i = 1, NumWindows() do
			local frame = _G["ChatFrame" .. i]
			if frame then
				pcall(FCFTab_UpdateAlpha, frame)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Edit box position
--------------------------------------------------------------------------------

local TAB_ROW_HEIGHT = 24

local function SetEditBoxOnTop(top)
	for i = 1, NumWindows() do
		local frame = _G["ChatFrame" .. i]
		local editBox = frame and (frame.editBox or _G["ChatFrame" .. i .. "EditBox"])
		if frame and editBox then
			local rightAnchor = frame.ScrollBar or frame
			editBox:ClearAllPoints()
			if top then
				editBox:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -5, TAB_ROW_HEIGHT)
			else
				editBox:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -5, -2)
			end
			editBox:SetPoint("RIGHT", rightAnchor, "RIGHT", 8, 0)
		end
	end
end

--------------------------------------------------------------------------------
-- Tab background
--------------------------------------------------------------------------------

local TAB_TEXTURES = { "Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight", "HighlightLeft", "HighlightMiddle", "HighlightRight" }

local function SetTabArtShown(shown)
	for i = 1, NumWindows() do
		local tab = _G["ChatFrame" .. i .. "Tab"]
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
	for i = 1, NumWindows() do
		list[#list + 1] = _G["ChatFrame" .. i .. "ButtonFrame"]
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

local originalFormats = {}
local originalResolve = nil
local resolveInstalled = false

local function BuildTag(entry)
	local text = entry[2] and ("|cff" .. entry[2] .. entry[1] .. "|r") or entry[1]
	return "[" .. text .. "]"
end

local function ApplyShortTypes()
	for chatType, entry in pairs(SHORT_TYPES) do
		local key = "CHAT_" .. chatType .. "_GET"
		local current = _G[key]
		if type(current) == "string" then
			if originalFormats[key] == nil then
				originalFormats[key] = current
			end
			local link = "|Hchannel:" .. chatType .. "|h" .. BuildTag(entry) .. "|h"
			if chatType == "WHISPER" or chatType == "BN_WHISPER" or chatType == "WHISPER_INFORM" or chatType == "BN_WHISPER_INFORM" then
				-- Whispers carry no channel link in Blizzard's format; keep it that way.
				_G[key] = BuildTag(entry) .. " %s: "
			else
				_G[key] = link .. " %s: "
			end
		end
	end
end

local function RestoreShortTypes()
	for key, value in pairs(originalFormats) do
		_G[key] = value
	end
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

local function InstallResolve()
	if resolveInstalled or not ChatFrameUtil or type(ChatFrameUtil.ResolvePrefixedChannelName) ~= "function" then
		return
	end
	resolveInstalled = true
	originalResolve = ChatFrameUtil.ResolvePrefixedChannelName
	ChatFrameUtil.ResolvePrefixedChannelName = function(communityChannelArg)
		local original = originalResolve(communityChannelArg)
		if not Active("shortChannels") then
			return original
		end
		local ok, short = pcall(ShortChannelName, communityChannelArg)
		if ok and type(short) == "string" and short ~= "" then
			return short
		end
		return original
	end
end

--------------------------------------------------------------------------------
-- Bracket removal (rewrites the line after it was added)
--------------------------------------------------------------------------------

local transformFailed = false

local function NeedsBracketStrip(text)
	return type(text) == "string" and text:find("|h[", 1, true) ~= nil
end

local function StripBrackets(text, ...)
	-- "|Hchannel:GUILD|h[G]|h" -> "|Hchannel:GUILD|hG|h", plus bracketed whisper tags.
	text = text:gsub("(|Hchannel:[^|]-|h)%[(.-)%]|h", "%1%2|h")
	text = text:gsub("^%[(|cff%x%x%x%x%x%x[%a>]+|r)%] ", "%1 ")
	text = text:gsub("^(%[?[%d:%s%p]-%]?%s?)%[(|cff%x%x%x%x%x%x[%a>]+|r)%] ", "%1%2 ")
	return text, ...
end

local function OnMessageAdded(chatFrame, text)
	if transformFailed or not Active("shortChannels") or not Active("hideBrackets") then
		return
	end
	if type(chatFrame.TransformMessages) ~= "function" or not NeedsBracketStrip(text) then
		return
	end
	local ok = pcall(chatFrame.TransformMessages, chatFrame, NeedsBracketStrip, StripBrackets)
	if not ok then
		transformFailed = true
	end
end

local observersInstalled = false

local function InstallObservers()
	if observersInstalled then
		return
	end
	observersInstalled = true
	for i = 1, NumWindows() do
		local frame = _G["ChatFrame" .. i]
		if frame and frame.addMessageObserver == nil then
			frame.addMessageObserver = OnMessageAdded
		end
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
-- Module lifecycle
--------------------------------------------------------------------------------

local function ApplyAll()
	local db = M.db
	SetBackgroundShown(not db.hideBackground)
	SetEditBoxArtShown(not db.hideEditBox)
	SetTabArtShown(not db.hideTabs)
	SetTabsOnMouseover(db.tabsOnMouseover)
	SetEditBoxOnTop(db.editBoxTop)
	SetButtonsHidden(db.hideButtons)
	if db.shortChannels then
		ApplyShortTypes()
		InstallResolve()
		InstallObservers()
	else
		RestoreShortTypes()
	end
	ApplyClassColors(db.classColors)
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
	RestoreShortTypes()
	ApplyClassColors(false)
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "hideBackground" then
		SetBackgroundShown(not value)
	elseif key == "hideEditBox" then
		SetEditBoxArtShown(not value)
	elseif key == "hideTabs" then
		SetTabArtShown(not value)
	elseif key == "tabsOnMouseover" then
		SetTabsOnMouseover(value)
	elseif key == "hideButtons" then
		SetButtonsHidden(value)
	elseif key == "editBoxTop" then
		SetEditBoxOnTop(value)
	elseif key == "shortChannels" then
		if value then
			ApplyShortTypes()
			InstallResolve()
			InstallObservers()
		else
			RestoreShortTypes()
		end
	elseif key == "classColors" then
		ApplyClassColors(value)
	end
end
