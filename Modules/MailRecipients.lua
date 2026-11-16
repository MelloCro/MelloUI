--------------------------------------------------------------------------------
-- MelloUI - Mail Recipients (2.1.56; a player's wish: "a list of our alts at the mailbox, so you only click which one
-- and the name is filled in", and "the same with Battle.net friends, a tab of its own: I can't remember my friends'
-- characters")
--
-- A small button at the right of the mailbox's To field (Send Mail) opens a menu:
--   Your Characters      your other characters of your faction, each in its class colour with its level; a click puts
--                        the name in the To field (Name-Realm when it lives on another realm) and moves on to Subject
--   Battle.net Friends   a friend a row (their BattleTag's name, "online" while they play), their characters under it
--                        as a submenu; every character the game has shown of them while they played, so the ones you
--                        cannot remember are there while they are offline too
-- What it keeps, account-wide in its own settings (`keep`: never in a profile or a share string, as Services' learned
-- services), only on this computer:
--   alts       ["Name-Realm"] = { name, realm, class (the class's token), level, faction, seen } -- this character as
--              it logs in and levels; the Quest List's record of your characters (MelloUIQuestRecord) read once for the
--              ones not seen yet (their faction unknown until they log in)
--   bnetChars  [BattleTag] = { ["Name-Realm"] = { name, realm, class, level, faction, seen } } -- read from the game's
--              friend list while a friend plays this game, a moment after it changes (its events come in bursts)
-- Nothing of the game's is replaced: the button is MelloUI's own frame on the Send Mail page, the menu the game's
-- (MenuUtil), the click the To field's own SetText. Not with the Gamepad UI (the game's menu opened from MelloUI's
-- code blocks its bindings: Services.lua's note), and nothing at all while the module is off.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("MailRecipients")
local Safe = MelloUI.Safe
local Text, Num, Secret = Safe.Text, Safe.Number, Safe.IsSecret

-- (every text a window draws: Tools/languages/strings.py reads this table)
local TEXT = {
	button = "Recipients",
	tip = "Pick one of your characters or a Battle.net friend's character to send this letter to.",
	alts = "Your Characters",
	friends = "Battle.net Friends",
	noAlts = "None yet: each of your characters is noted as it logs in.",
	noFriends = "None yet: a friend's characters are noted while they play.",
	online = "online",
}

local M = MelloUI:RegisterModule("MailRecipients", {
	title = "Mail Recipients",
	new = "2.1.56",
	desc = "A button beside the mailbox's To field lists your characters and your Battle.net friends' characters: click one and its name is filled in.",
	icon = "Interface\\Icons\\INV_Letter_15",
	flavour = "Who was that again? One click and the letter has its name.",
	enabledByDefault = true,
	keep = { "alts", "bnetChars" },   -- your characters and your friends': never in a profile or a share string
	defaults = {
		bnet = true,
	},
	options = {
		{ type = "toggle", key = "bnet", name = "Battle.net Friends' Characters", new = "2.1.56",
		  desc = "The menu lists your Battle.net friends too, each with the characters the game has shown of them while they played. Off: your own characters only, and none of theirs noted." },
	},
})
MelloUI.MailRecipients = M

local R = {
	SIZE = 18,       -- the button
	GAP = 4,         -- from the To field's right edge
	SETTLE = 2,      -- seconds: the friend list read once its events have stopped coming
	SEED_SEEN = 0,   -- a character from the Quest List's record: never seen here
}

local function Tr(text)
	local W = MelloUI.Widgets
	return W and W.Tr and W.Tr(text) or text
end

local function Call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c = pcall(fn, ...)
	if ok then
		return a, b, c
	end
	return nil
end

--------------------------------------------------------------------------------
-- What it keeps
--------------------------------------------------------------------------------

local function Store(key)
	local db = M.db
	if type(db) ~= "table" then
		return {}
	end
	if type(db[key]) ~= "table" then
		db[key] = {}
	end
	return db[key]
end

-- this character: its key, name, realm and faction ("Alliance" / "Horde"); nil while they cannot be read
local function Me()
	local name, realm = Text(Call(UnitName, "player")), Text(Call(GetRealmName))
	if not name or name == "" or not realm or realm == "" then
		return nil
	end
	return name .. "-" .. realm, name, realm, Text(Call(UnitFactionGroup, "player"))
end

-- the class token of a class's shown name (a friend's game account names the class in the client's language)
local function ClassToken(shown)
	if type(shown) ~= "string" or shown == "" then
		return nil
	end
	for _, list in ipairs({ rawget(_G, "LOCALIZED_CLASS_NAMES_MALE"), rawget(_G, "LOCALIZED_CLASS_NAMES_FEMALE") }) do
		if type(list) == "table" then
			for token, text in pairs(list) do
				if text == shown then
					return token
				end
			end
		end
	end
	return nil
end

-- this character as it logs in and levels; the Quest List's record read once for the characters not seen yet
local function WriteMe()
	local key, name, realm, faction = Me()
	if not key then
		return
	end
	local alts = Store("alts")
	local _, class = Call(UnitClass, "player")
	alts[key] = { name = name, realm = realm, class = Text(class), level = Num(Call(UnitLevel, "player")),
		faction = faction, seen = time() }
	local record = rawget(_G, "MelloUIQuestRecord")
	local chars = type(record) == "table" and record.chars
	for k, c in pairs(type(chars) == "table" and chars or {}) do
		if alts[k] == nil and type(c) == "table" and type(c.name) == "string" and type(c.realm) == "string" then
			alts[k] = { name = c.name, realm = c.realm, class = c.class, level = c.level, seen = R.SEED_SEEN }
		end
	end
end

-- the friend list: each friend's characters of this game they play now, noted
local function ReadFriends()
	if not (M.isEnabled and M.db and M.db.bnet) then
		return
	end
	local BN = rawget(_G, "C_BattleNet")
	local count = Num(Call(rawget(_G, "BNGetNumFriends")))
	if type(BN) ~= "table" or not count then
		return
	end
	local wow, project = rawget(_G, "BNET_CLIENT_WOW"), rawget(_G, "WOW_PROJECT_ID")
	local known = Store("bnetChars")
	for i = 1, count do
		local info = Call(BN.GetFriendAccountInfo, i)
		local tag = type(info) == "table" and Text(info.battleTag) or nil
		local games = tag and Num(Call(BN.GetFriendNumGameAccounts, i)) or 0
		for j = 1, games do
			local g = Call(BN.GetFriendGameAccountInfo, i, j)
			if type(g) == "table" and Text(g.clientProgram) == wow
				and (not project or Num(g.wowProjectID) == project) then
				local name, realm = Text(g.characterName), Text(g.realmName)
				if name and name ~= "" and realm and realm ~= "" then
					local chars = known[tag] or {}
					known[tag] = chars
					chars[name .. "-" .. realm] = { name = name, realm = realm, class = ClassToken(Text(g.className)),
						level = Num(g.characterLevel), faction = Text(g.factionName), seen = time() }
				end
			end
		end
	end
end

local waiting = false
local function ReadFriendsSoon()
	if waiting then
		return
	end
	waiting = true
	C_Timer.After(R.SETTLE, function()
		waiting = false
		ReadFriends()
	end)
end

--------------------------------------------------------------------------------
-- The menu
--------------------------------------------------------------------------------

-- a character's line: its name in its class colour, its level after it dimmed
local function Line(c)
	local hex = c.class and MelloUI.Colours and MelloUI.Colours.ClassHex and MelloUI.Colours.ClassHex(c.class)
	local name = hex and ("|c" .. hex .. c.name .. "|r") or c.name
	return c.level and (name .. "  |cff9d9d9d" .. c.level .. "|r") or name
end

-- the characters of a list you can write to: your faction (or not known yet), you yourself left out; highest level first
local function Writable(list, me, faction)
	local out = {}
	for key, c in pairs(type(list) == "table" and list or {}) do
		if key ~= me and type(c) == "table" and type(c.name) == "string"
			and (c.faction == nil or faction == nil or c.faction == faction) then
			out[#out + 1] = c
		end
	end
	table.sort(out, function(a, b)
		if (a.level or 0) ~= (b.level or 0) then
			return (a.level or 0) > (b.level or 0)
		end
		return a.name < b.name
	end)
	return out
end

-- the To field gets the name (with its realm when it lives on another one), the cursor moves on to Subject
local function Put(c)
	local to, subject = rawget(_G, "SendMailNameEditBox"), rawget(_G, "SendMailSubjectEditBox")
	if not to then
		return
	end
	local _, _, realm = Me()
	local name = c.name
	if realm and c.realm ~= realm then
		name = name .. "-" .. c.realm:gsub("%s", "")
	end
	to:SetText(name)
	if subject then
		subject:SetFocus()
	end
	MelloUI:PlayUISound("click")
end

-- a friend's BattleTag ("Name#1234") as the menu shows it, with "online" while they play this game
local function FriendNames()
	local online = {}
	local BN = rawget(_G, "C_BattleNet")
	local count = Num(Call(rawget(_G, "BNGetNumFriends"))) or 0
	for i = 1, type(BN) == "table" and count or 0 do
		local info = Call(BN.GetFriendAccountInfo, i)
		local tag = type(info) == "table" and Text(info.battleTag) or nil
		if tag then
			local game = info.gameAccountInfo
			local playing = type(game) == "table" and not Secret(game.isOnline) and game.isOnline
				and Text(game.clientProgram) == rawget(_G, "BNET_CLIENT_WOW")
			online[tag] = playing and true or false
		end
	end
	return online
end

local function Menu(owner)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		return
	end
	WriteMe()
	ReadFriends()
	local me, _, _, faction = Me()
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(Tr(TEXT.alts))
		local alts = Writable(Store("alts"), me, faction)
		for _, c in ipairs(alts) do
			root:CreateButton(Line(c), function() Put(c) end)
		end
		if #alts == 0 then
			root:CreateTitle("|cff9d9d9d" .. Tr(TEXT.noAlts) .. "|r")
		end
		if not M.db.bnet then
			return
		end
		root:CreateDivider()
		root:CreateTitle(Tr(TEXT.friends))
		local known, shown = Store("bnetChars"), 0
		local friends = FriendNames()
		local tags = {}
		for tag in pairs(friends) do
			tags[#tags + 1] = tag
		end
		table.sort(tags, function(a, b) return a:lower() < b:lower() end)
		for _, tag in ipairs(tags) do
			local chars = Writable(known[tag], nil, faction)
			if #chars > 0 then
				local label = tag:match("^[^#]+") or tag
				if friends[tag] then
					label = label .. "  |cff40ff40" .. Tr(TEXT.online) .. "|r"
				end
				local sub = root:CreateButton(label)
				for _, c in ipairs(chars) do
					sub:CreateButton(Line(c), function() Put(c) end)
				end
				shown = shown + 1
			end
		end
		if shown == 0 then
			root:CreateTitle("|cff9d9d9d" .. Tr(TEXT.noFriends) .. "|r")
		end
	end)
end

--------------------------------------------------------------------------------
-- The button on the Send Mail page
--------------------------------------------------------------------------------

local button

local Click = Perf.Shared("OnClick on the mailbox's recipients button", function(self)
	MelloUI:PlayUISound("click")
	Menu(self)
end, "script")

local Enter = Perf.Shared("OnEnter on the mailbox's recipients button", function(self)
	MelloUI.Widgets.ShowTooltip(self, TEXT.button, TEXT.tip)
end, "script")

local function Button()
	if button then
		return button
	end
	local to, page = rawget(_G, "SendMailNameEditBox"), rawget(_G, "SendMailFrame")
	if not (to and page) then
		return nil
	end
	local W = MelloUI.Widgets
	button = Safe.CreateFrame("Button", nil, page)
	button:SetSize(R.SIZE, R.SIZE)
	button:SetPoint("LEFT", to, "RIGHT", R.GAP, 0)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	W.Icon(button.icon, "chat_friends", R.SIZE)
	button.glow = button:CreateTexture(nil, "HIGHLIGHT")
	button.glow:SetAllPoints()
	W.Icon(button.glow, "chat_friends", R.SIZE)
	button.glow:SetBlendMode("ADD")
	button.glow:SetAlpha(0.35)
	button:RegisterForClicks("LeftButtonUp")
	Perf.SetScript(button, "OnClick", Click)
	Perf.SetScript(button, "OnEnter", Enter)
	Perf.SetScript(button, "OnLeave", W.TipLeave)
	return button
end

local function Show()
	local b = (M.isEnabled and not Safe.GamepadUI()) and Button() or button
	if b then
		b:SetShown(M.isEnabled and not Safe.GamepadUI())
	end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
local EVENTS = { "MAIL_SHOW", "PLAYER_LEVEL_UP", "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE",
	"BN_FRIEND_LIST_SIZE_CHANGED" }

Perf.SetScript(events, "OnEvent", function(_, event)
	if event == "MAIL_SHOW" then
		Show()
	elseif event == "PLAYER_LEVEL_UP" then
		C_Timer.After(1, WriteMe)   -- (UnitLevel reads the new level a moment later)
	else
		ReadFriendsSoon()
	end
end)

function M:OnEnable(db)
	self.db = db
	for _, e in ipairs(EVENTS) do
		pcall(events.RegisterEvent, events, e)
	end
	WriteMe()
	ReadFriendsSoon()
	Show()
end

function M:OnDisable()
	events:UnregisterAllEvents()
	Show()
end

function M:OnSettingChanged(_, _, db)
	self.db = db
	ReadFriendsSoon()
end

-- for the test harness
M.TEXT, M.R = TEXT, R
M.Writable, M.Put, M.ClassToken = Writable, Put, ClassToken
