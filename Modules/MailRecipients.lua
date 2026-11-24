--------------------------------------------------------------------------------
-- MelloUI - Mail Recipients (2.1.59, pull request #41 by Glockta-code; a player's wish: "a list of our alts at the
-- mailbox, so you only click which one and the name is filled in", and "the same with Battle.net friends, a tab of
-- its own: I can't remember my friends' characters")
--
-- (2.1.62, pull request #49 by Glockta-code: a panel of its own in place of the button's menu -- the German player:
-- "can't we take an approach that fits MelloUI and build it in to the right of the mail window?" The user's pick of
-- 2026-11-20, C: the button stays, a click on it opens the panel and a second one closes it, and it is open again the
-- next time where it was left open. Closed at first: nothing new on the screen until it is asked for.)
--
-- (2.1.84; the user, 2026-11-24: "its currently a bit buggy and we cant remove alts that we dont have anymore and the
-- class colours are not accurate so i want to expand on that and make it also look better", then "to be able to create
-- groups, for example i want to know which characters have which professions"; the picks "A and profession icons on
-- every row" of BuildData/output/mail_recipients_sketch) The panel is one list:
--   your groups          headings of your own with the names you put under them; Pinned is the first one. Any name
--                        goes in (a friend's character, a stranger you wrote to), a name in as many as you like
--   Recent               the last names a letter of yours went to, strangers too
--   Your Characters      your other characters: the game's own name list is asked for them (FromGame), so an alt need
--                        not have logged in with MelloUI first. A noted character the game no longer names (deleted,
--                        renamed) moves to Hidden by itself
--   Battle.net Friends   a friend a row (their BattleTag's name, a dot while they play), their characters under it
--                        when it is unfolded; every character the game has shown of them while they played. One on
--                        ANOTHER realm shows its realm, and the To field gets the game's own address for it
--                        (R.Address). Another realm is another server: WoW Forever names its layers as realms
--                        ("CAMWOW EU5 Realm 5 PvE" and "CAMWOW EU4 Realm 1 PvE": one EU server), and the layer is
--                        left out of the comparison (R.ServerKey)
--   Hidden               at the panel's foot: the names taken off the list (the bin under the pointer) and the
--                        characters that are gone, each with its way back
-- A row: the class's picture, the name in its class colour, the two main professions of a character of yours, its
-- level. A class MelloUI does not know is a "?" and a dimmer name -- never the plain white that reads as a Priest; it
-- is learned as that character logs in, from the guild's roster, or picked with a click on the "?".
-- The Professions view turns the list round: a heading a profession, your characters under it by their skill.
-- What is typed in To narrows the list, and looks through the game's own names for a letter (guild, friends) and the
-- professions as well.
--
-- What it keeps, account-wide in its own settings (`keep`: never in a profile or a share string, as Services' learned
-- services), only on this computer:
--   alts       ["Full Name-Realm"] = { name (the full name, first name and surname), realm, class (the class's token),
--              level, faction, seen, profs = { { name, icon, rank, cap, main } ... }, kept } -- this character as it
--              logs in, levels and stands at a mailbox
--   bnetChars  [BattleTag] = { ["Name-Server"] = { name, realm, class, level, faction, seen } } -- read from the game's
--              friend list while a friend plays this game, a moment after it changes (its events come in bursts)
--   groups     { { name, stock, fold, members = { { name, realm } ... } } ... } in your order
--   sentTo     { { name (the address as it was sent), at } ... } newest first: Recent
--   hidden     [id] = { name, realm, class, level }: taken off the list by hand
--   people     [id] = { class }: a class picked by hand
--   folds      which headings are folded, which friends unfolded;  view  "list" or "prof"
-- Nothing of the game's is replaced: the button and the panel are MelloUI's own frames on the Send Mail page (the
-- panel W.TrayBox, the Restock panel's box), the click the To field's own SetText; the To field and SendMail are
-- listened to with post-hooks. Not with the Gamepad UI (MelloUI's buttons inside the game's windows are held back
-- there), and nothing at all while the module is off.
-- On by default (the user, 2026-11-17: "that should be enabled by default"); its switch is Quality of Life >
-- Automation > Mail. All it puts on the screen by itself is that one button, on the Send Mail page.
-- A list of its own, not the Quest List's record of your characters: that one keeps the first name alone, and the
-- Quest List is a feature addon that may not be loaded.
-- With Battle.net Friends' Characters switched off, what was noted of friends is forgotten; a friend taken off your
-- friend list is forgotten at the next read of the list.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("MailRecipients")
local Safe = MelloUI.Safe
local Text, Num, Secret = Safe.Text, Safe.Number, Safe.IsSecret

-- (every text a window draws: Tools/languages/strings.py reads this table)
local TEXT = {
	button = "Recipients",   -- (the button's tooltip and the panel's title)
	tip = "Pick one of your characters or a Battle.net friend's character to send this letter to.",
	alts = "Your Characters",
	friends = "Battle.net Friends",
	noAlts = "No other characters.",
	noFriends = "None yet: a friend's characters are noted while they play.",
	online = "%d online",
	-- (2.1.84)
	list = "List",
	professions = "Professions",
	pinned = "Pinned",
	recent = "Recent",
	hidden = "Hidden (%d)",
	unknown = "Not known yet (%d)",
	noProfs = "None noted yet: a character's professions are noted as it logs in.",
	found = "%d names with \"%s\"",
	foundProf = "%d characters with %s",
	noneFound = "No name with \"%s\".",
	guild = "guild",
	friend = "friend",
	groupsOf = "%s's groups",
	classOf = "%s's class",
	newGroup = "New group...",
	rename = "Rename",
	moveUp = "Move up",
	moveDown = "Move down",
	deleteGroup = "Delete group",
	deleteAsk = "Delete the group %s? Its names stay in the list.",
	delete = "Delete",
	cancel = "Cancel",
	tipGroups = "Groups",
	tipGroupsLine = "Put this name in one of your groups, or make a new one.",
	tipHide = "Take off the list",
	tipHideLine = "It moves to Hidden at the list's foot.",
	tipOut = "Take out of this group",
	tipForget = "Take off Recent",
	tipBack = "Back on the list",
	tipGroup = "This group",
	tipGroupLine = "Rename it, move it or delete it.",
	tipAsk = "Class not known yet",
	tipAskLine = "It is learned as this character logs in. Click to pick it yourself.",
	tipClassLevel = "%s, level %d.",
	tipLevel = "Level %d.",
	tipNoClass = "Class not known yet.",
	tipToday = "Seen today.",
	tipYesterday = "Seen yesterday.",
	tipDays = "Seen %d days ago.",
	tipOf = "A character of %s.",
	tipGone = "The game no longer names this character.",
	tipClick = "Click: the letter goes to this character.",
	you = "you",
	tipYou = "The character you are on.",
	tipSkillOf = "Skill %d of %d.",
	tipSkill = "Skill %d.",
}

local M = MelloUI:RegisterModule("MailRecipients", {
	title = "Mail Recipients",
	desc = "A button beside the mailbox's To field lists your characters and your Battle.net friends' characters: click one and its name is filled in.",
	icon = "Interface\\Icons\\INV_Letter_15",
	flavour = "Who was that again? One click and the letter has its name.",
	enabledByDefault = true,   -- (the user, 2026-11-17: "that should be enabled by default")
	slash = "mail",   -- /mello mail names
	-- your characters, your friends' and what you made of the list: never in a profile or a share string
	keep = { "alts", "bnetChars", "groups", "sentTo", "hidden", "people", "folds", "view" },
	defaults = {
		bnet = true,
		open = false,   -- (2.1.62) the panel beside Send Mail, as the button left it
		subject = true,   -- the subject from the first attachment
		recent = true,   -- (2.1.84) the last names a letter went to
		found = true,   -- (2.1.84) the game's own names for a letter, while a name is typed
	},
	options = {
		{ type = "toggle", key = "bnet", name = "Battle.net Friends' Characters",
		  desc = "The list shows your Battle.net friends too, each with the characters the game has shown of them while they played. Off: your own characters only, and none of theirs noted." },
		{ type = "toggle", key = "recent", name = "Recent Names", new = "2.1.84",
		  desc = "The last names you sent a letter to stand in the list, strangers too. Off: none shown and none kept." },
		{ type = "toggle", key = "found", name = "Guild And Friends While Typing", new = "2.1.84",
		  desc = "What you type in To also looks through your guild and your friends list, as the game's own name list does. Off: only the names of the list itself." },
		{ type = "toggle", key = "subject", name = "Subject from the First Item",
		  desc = "An empty subject takes the name of the first item you attach, with its count for a stack. What you type yourself stays." },
	},
})
MelloUI.MailRecipients = M

local R = {
	SETTLE = 2,          -- seconds: the friend list read once its events have stopped coming
	MAX = 100,           -- the most characters asked of the game's own name list (FromGame)
	RECENT = 5,          -- the most names kept under Recent
	FOUND = 12,          -- the most names asked of the game's own list for a typed text
	GUILD_MAX = 1000,    -- the most guild members read for their class
	PROF_FIND = 3,       -- letters typed before a profession's name is looked for
	onList = {},         -- [BattleTag] = true: on the friend list at the last read (reused)
	scratch = {},        -- this character's professions as just read (reused)
	online = {},         -- [BattleTag] = true while that friend plays this game (reused)
	playing = {},        -- [BattleTag] = the character they play now (reused)
	guildClass = {},     -- [a guild member's name, lower case] = its class's token (read as the panel opens)
	guildLevel = {},     -- ... = its level
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

-- a kept table emptied, or a new one
local function Fresh(t)
	if type(t) == "table" then
		wipe(t)
		return t
	end
	return {}
end

local function Trim(text)
	if type(text) ~= "string" then
		return ""
	end
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
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

-- this character: its key, name, realm and faction ("Alliance" / "Horde"); nil while they cannot be read. The name
-- is the FULL one (the user: names on this client have a first name and a surname, "Hopfen Hilda", and a letter
-- needs the whole name): the game's display name with its surname (MelloUI:UnitNameAs "both"), UnitName's when not.
-- The key stays UnitName's, as the Quest List's record keys a character
-- a realm as the game names it in an address: its spaces left out ("CAMWOW EU5 Realm 7 PvE" -> "CAMWOWEU5Realm7PvE",
-- as a Battle.net friend's realmName reads)
local function RealmKey(realm)
	return type(realm) == "string" and (realm:gsub("%s", "")) or nil
end

-- (2.1.62) a realm without its layer: WoW Forever names each layer of its server a realm of its own -- the German
-- player's /mello mail names had a friend's character on "CAMWOW EU5 Realm 7 PvE", their screenshot a day later the same
-- character on "CAMWOW EU5 Realm 5 PvE"; and "CAMWOW EU4 Realm 1 PvE" is one more (the player: "my Battle.net friends
-- and I play on one and the same EU mega server; the layers are shown nowhere", a letter to "Name Surname-CAMWOW..."
-- refused, to "Name Surname" sent). So the layer and the shard's number, "Realm <n>" and the "<n>" of "EU<n>", are
-- left out: "CAMWOW EU PvE". The region stays: the player could write to a stranger of the EU server by the name
-- alone, to one of the American realm not.
-- Characters of one server get a letter by their bare name; the realm shown and put in the address only for a realm
-- that differs past those
function R.ServerKey(realm)
	if type(realm) ~= "string" then
		return nil
	end
	-- (with spaces as GetRealmName gives it, or without, as GetNormalizedRealmName and a friend's realmName do:
	-- "CAMWOWEU5Realm7PvE" -> "CAMWOWEUPvE" as well)
	local server = realm:gsub("[Rr]ealm%s*%d+", "")
	server = server:gsub("(%u%u)%d+", "%1")   -- (the region kept: "EU5" -> "EU", an American one stays apart)
	-- (2.1.66, the follow-up to pull request #60) a realm that is only "Realm 9": the shortening would leave nothing, and
	-- every such realm would be one server -- its whole name kept (f124/mailrecipients M11)
	if not server:find("%w") then
		server = realm
	end
	return RealmKey(server)
end

-- your realm as the game names it. WoW Forever at times names none at all (the German player's /mello mail names,
-- 2026-11-21: "realm " empty, their characters noted on "CAMWOW EU5 Realm 7 PvE" -- and the empty name read as another
-- server: every character of theirs with its realm, they themselves on the list, the game's names twice). Then the
-- normalized name, else the one last read this session, else the realm this character was last noted on
function R.Realm()
	local realm = Text(Call(GetRealmName))
	if not realm or realm == "" then
		realm = Text(Call(rawget(_G, "GetNormalizedRealmName")))
	end
	if realm and realm ~= "" then
		R.lastRealm = realm
		return realm
	end
	if R.lastRealm then
		return R.lastRealm
	end
	local short = Text(Call(UnitName, "player"))
	local full = Text(MelloUI.UnitNameAs and Call(MelloUI.UnitNameAs, MelloUI, "player", "both"))
	local alts = type(M.db) == "table" and type(M.db.alts) == "table" and M.db.alts or {}
	-- (2.1.84) this character's own notes: the ones that bear its full name, or stand under its first name's key of
	-- before; then -- a character with no note of its own, and the game naming no realm in its sessions -- the realm the
	-- account's characters were last noted on: your characters play one server
	local best, seen, any, anySeen
	for key, c in pairs(alts) do
		if type(c) == "table" and type(c.realm) == "string" and c.realm ~= "" then
			local own = (full and c.name == full)
				or (short and type(key) == "string" and key:sub(1, #short + 1) == short .. "-")
			if own and (c.seen or 0) >= (seen or 0) then
				best, seen = c.realm, c.seen or 0
			end
			if (c.seen or 0) >= (anySeen or 0) then
				any, anySeen = c.realm, c.seen or 0
			end
		end
	end
	return best or any
end

-- (2.1.84) no realm to be had at all (the game names none and nothing was ever noted): the character is noted without
-- one, under its name alone ("Full Name-"), and counts as one of your server; its note moves under its realm once one
-- is read.
-- (2.1.84; the user in their game, 2026-11-24: their two characters showed no professions of each other -- both bear
-- one first name, as "Arden Vale" and "Arden Holt" would, and UnitName gives the first name alone) The key is the FULL name's:
-- under UnitName's, one note served both characters and each login wrote the other's away. A first name is not one
-- character's on this client (a friend's three characters share one too)
local function Me()
	local short, realm = Text(Call(UnitName, "player")), R.Realm()
	if not short or short == "" then
		return nil
	end
	if realm == "" then
		realm = nil
	end
	local full = Text(MelloUI.UnitNameAs and Call(MelloUI.UnitNameAs, MelloUI, "player", "both"))
	full = (full and full ~= "") and full or short
	return full .. "-" .. (realm or ""), full, realm, Text(Call(UnitFactionGroup, "player"))
end

-- a character on another SERVER than yours (2.1.62: R.ServerKey -- another layer of yours is no other realm): its realm
-- as an address names it, else nil
local function OtherRealm(c)
	local mine, theirs = R.ServerKey(R.Realm()), R.ServerKey(c.realm)
	return (mine and theirs and mine ~= theirs) and RealmKey(c.realm) or nil
end

-- (2.1.84) a character as the lists this module keeps name it (groups, hidden, people): its name, with its server after
-- it where that is another one than yours. One of your server is its bare name -- as the game's own list names it
function R.Id(c)
	if type(c) ~= "table" or type(c.name) ~= "string" then
		return nil
	end
	return OtherRealm(c) and (c.name .. "-" .. R.ServerKey(c.realm)) or c.name
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

-- (2.1.84) this character's professions as the game lists them, into `into` (kept and filled again): each { name, icon,
-- rank, cap, main } -- `main` for the first two the game names, a character's two professions; the others (fishing,
-- cooking, first aid) after them. -> how many it read (0 before the game has them)
local function ReadProfessions(into)
	local get, info = rawget(_G, "GetProfessions"), rawget(_G, "GetProfessionInfo")
	if type(get) ~= "function" or type(info) ~= "function" then
		return 0
	end
	local ok, a, b, c, d, e, f = pcall(get)
	if not ok then
		return 0
	end
	local n = 0
	for i = 1, 6 do
		local index = select(i, a, b, c, d, e, f)
		if index ~= nil and not Secret(index) then
			local okI, name, icon, rank, cap = pcall(info, index)
			name = okI and Text(name) or nil
			if name and name ~= "" then
				n = n + 1
				local p = into[n]
				if type(p) ~= "table" then
					p = {}
					into[n] = p
				end
				p.name, p.icon, p.rank, p.cap, p.main = name, Num(icon) or Text(icon), Num(rank), Num(cap), i <= 2 or nil
			end
		end
	end
	return n
end

-- this character as it logs in, levels and stands at a mailbox (the Quest List's record of your characters is not
-- read: it keeps UnitName's name, which may be the first name alone, and a letter to it would not arrive)
local function WriteMe()
	local key, name, realm, faction = Me()
	if not key then
		return
	end
	local alts = Store("alts")
	local _, class = Call(UnitClass, "player")
	local rec = alts[key]
	-- (2.1.84) this character's notes under other keys -- its first name's of before, another layer's, one made
	-- without a realm: the one last seen is its note now, under its own key, the others go. Only a note that bears its
	-- full name is its own: one under its first name's key may be the other character's of that first name
	local here = R.ServerKey(realm)
	for k, c in pairs(alts) do
		if k ~= key and type(c) == "table" and c.name == name and (c.realm == nil or R.ServerKey(c.realm) == here) then
			if type(rec) ~= "table" or (c.seen or 0) > (rec.seen or 0) then
				rec = c
			end
			alts[k] = nil
		end
	end
	if type(rec) ~= "table" then
		rec = {}
	end
	alts[key] = rec
	rec.name, rec.full, rec.realm, rec.class = name, true, realm, Text(class)
	rec.level, rec.faction, rec.seen = Num(Call(UnitLevel, "player")), faction, time()
	-- (2.1.84) its professions, where the game has them by now (none read: what was noted stays)
	local n = ReadProfessions(R.scratch)
	if n > 0 then
		local profs = type(rec.profs) == "table" and rec.profs or {}
		rec.profs = profs
		for i = 1, n do
			local p, s = profs[i], R.scratch[i]
			if type(p) ~= "table" then
				p = {}
				profs[i] = p
			end
			p.name, p.icon, p.rank, p.cap, p.main = s.name, s.icon, s.rank, s.cap, s.main
		end
		for i = #profs, n + 1, -1 do
			profs[i] = nil
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
	local whole = Call(rawget(_G, "BNConnected")) == true   -- (the list read whole: only then is anyone forgotten)
	wipe(R.onList)
	for i = 1, count do
		local info = Call(BN.GetFriendAccountInfo, i)
		local tag = type(info) == "table" and Text(info.battleTag) or nil
		if tag then
			R.onList[tag] = true
		else
			whole = false
		end
		local games = tag and Num(Call(BN.GetFriendNumGameAccounts, i)) or 0
		for j = 1, games do
			local g = Call(BN.GetFriendGameAccountInfo, i, j)
			if type(g) == "table" and Text(g.clientProgram) == wow
				and (not project or Num(g.wowProjectID) == project) then
				-- (/mello mail names on this client: characterName is the full name, "Asmegor Baskerville";
				-- realmName without spaces, realmDisplayName with them; classFilename the class's token)
				local name = Text(g.characterName)
				local realm = Text(g.realmDisplayName) or Text(g.realmName)
				if name and name ~= "" and realm and realm ~= "" then
					local chars = known[tag]
					if type(chars) ~= "table" then
						chars = {}
						known[tag] = chars
					end
					local key = name .. "-" .. R.ServerKey(realm)   -- (2.1.62: one record whatever layer they play on)
					local rec = chars[key]
					if type(rec) ~= "table" then
						rec = {}
						chars[key] = rec
					end
					rec.name, rec.realm = name, realm
					rec.class = Text(g.classFilename) or ClassToken(Text(g.className))
					rec.level, rec.faction, rec.seen = Num(g.characterLevel), Text(g.factionName), time()
				end
			end
		end
	end
	-- a friend taken off the friend list: what was noted of them forgotten (only after a whole read of a list that
	-- is there: a Battle.net disconnect reads as no friends)
	if whole and count > 0 then
		for tag in pairs(known) do
			if not R.onList[tag] then
				known[tag] = nil
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
	Perf.C_Timer.After(R.SETTLE, function()
		waiting = false
		ReadFriends()
	end)
end

-- (2.1.84) a friend's character noted twice: until 2.1.62 its key bore its layer ("Name-CAMWOWEU5Realm7PvE"), since
-- then its server -- and the old note stayed beside the new one (the user's own settings: six of a friend's three
-- characters). Each under its server's key once, the note last seen kept. Once a session, as the panel first opens
function R.Merge()
	if R.merged then
		return
	end
	R.merged = true
	if type(M.db) ~= "table" or type(M.db.bnetChars) ~= "table" then
		return
	end
	local moves = {}
	for _, chars in pairs(M.db.bnetChars) do
		if type(chars) == "table" then
			wipe(moves)
			for key, c in pairs(chars) do
				if type(c) == "table" and type(c.name) == "string" and key ~= c.name .. "-" .. (R.ServerKey(c.realm) or "") then
					moves[#moves + 1] = key
				end
			end
			for _, key in ipairs(moves) do
				local c = chars[key]
				local want = c.name .. "-" .. (R.ServerKey(c.realm) or "")
				local had = chars[want]
				if type(had) ~= "table" or (c.seen or 0) > (had.seen or 0) then
					chars[want] = c
				end
				chars[key] = nil
			end
		end
	end
end

-- (2.1.84) your guild's members, for a class the game's name list does not give: [name, lower case] = the class's
-- token and the level, as the roster has them now (nothing asked of the server). Read as the panel opens
function R.ReadGuild()
	wipe(R.guildClass)
	wipe(R.guildLevel)
	local get = rawget(_G, "GetGuildRosterInfo")
	local inGuild = Call(rawget(_G, "IsInGuild"))
	if type(get) ~= "function" or Secret(inGuild) or not inGuild then
		return
	end
	local here = R.ServerKey(R.Realm())
	for i = 1, math.min(Num(Call(rawget(_G, "GetNumGuildMembers"))) or 0, R.GUILD_MAX) do
		local ok, name, _, _, level, _, _, _, _, _, _, class = pcall(get, i)
		name, class = ok and Text(name) or nil, ok and Text(class) or nil
		if name and name ~= "" and class then
			-- (your server's own realm after the name: the bare name, as the lists here bear it)
			local bare, suffix = name:match("^(.-)%-([^%-%s]+)$")
			if bare and R.ServerKey(suffix) == here then
				name = bare
			end
			name = name:lower()
			R.guildClass[name], R.guildLevel[name] = class, Num(level)
		end
	end
end

--------------------------------------------------------------------------------
-- The names of the list
--------------------------------------------------------------------------------

-- (2.1.84) a character's class: as noted, else the one picked by hand, else the guild roster's
function R.Class(c)
	if type(c.class) == "string" then
		return c.class
	end
	local id = R.Id(c)
	local p = id and Store("people")[id]
	if type(p) == "table" and type(p.class) == "string" then
		return p.class
	end
	return R.guildClass[c.name:lower()]
end

function R.Level(c)
	return Num(c.level) or R.guildLevel[c.name:lower()]
end

-- The address a letter needs. On your realm: the name. On another realm a bare name would go to whoever bears that
-- name on YOUR realm, so: the game's own address for the character where the game knows one (C_AutoComplete, the
-- name list the To field itself completes from: the very text the game would fill in), else the name with its realm
-- after it, the realm's spaces left out (the game's form). Not seen in a real client with a friend on another realm:
-- should this client refuse the form, the letter is refused and nothing is lost.
function R.Address(c)
	local theirs = OtherRealm(c)
	if not theirs then
		return c.name
	end
	local AC, lists = rawget(_G, "C_AutoComplete"), rawget(_G, "AUTOCOMPLETE_LIST")
	local mail = type(lists) == "table" and lists.MAIL
	if type(AC) == "table" and type(mail) == "table" then
		local results = Call(AC.GetAutoCompleteResults, c.name, 8, #c.name, true, mail.include, mail.exclude)
		for _, r in ipairs(type(results) == "table" and results or {}) do
			local full = type(r) == "table" and Text(r.name) or nil
			if full and (full == c.name or full:sub(1, #c.name + 1) == c.name .. "-") then
				return full
			end
		end
	end
	return c.name .. "-" .. theirs
end

-- the characters of a list you can write to: your faction (or not known yet), you yourself left out, and only the ones
-- noted with their full name (`full`: an early build of this module took the Quest List's record, first names alone
-- -- "Sovari" where the letter needs "Sovari Mara" -- and those wait till that character logs in); highest level first
local function ByLevel(a, b)
	if (a.level or 0) ~= (b.level or 0) then
		return (a.level or 0) > (b.level or 0)
	end
	return a.name < b.name
end

local function ByName(a, b)
	return a.name < b.name
end

local function ByTag(a, b)
	return a:lower() < b:lower()
end

local function Writable(list, me, faction, needFull)
	local out, one = {}, {}
	for key, c in pairs(type(list) == "table" and list or {}) do
		if key ~= me and type(c) == "table" and type(c.name) == "string" and (c.full or not needFull)
			and (c.faction == nil or faction == nil or c.faction == faction) then
			-- (2.1.62) a character noted on two layers of its server (before R.ServerKey, or this character's own
			-- record by its layer): once, as last seen
			local id = c.name .. "-" .. (R.ServerKey(c.realm) or "")
			local had = one[id]
			if not had or (c.seen or 0) > (had.seen or 0) then
				one[id] = c
			end
		end
	end
	for _, c in pairs(one) do
		out[#out + 1] = c
	end
	table.sort(out, ByLevel)
	return out
end

-- The account's other characters as the game itself names them: the To field's own name list (C_AutoComplete), asked
-- for account characters alone and with no text typed. Seen in the test client (2026-11-17): it hands out every other
-- character of the account by its full name ("Neuer Hund"), this one left out; the game's own windows never ask it
-- with an empty text. So an alt is in the menu before it has ever logged in with MelloUI. nil where this client has
-- no such list.
local function FromGame()
	local AC, E = rawget(_G, "C_AutoComplete"), rawget(_G, "Enum")
	local flags = type(E) == "table" and E.AutoCompleteEntryFlag
	local account = type(flags) == "table" and Num(flags.AccountCharacter)
	if type(AC) ~= "table" or not account then
		return nil
	end
	local results = Call(AC.GetAutoCompleteResults, "", R.MAX, 0, true, account, 0)
	return type(results) == "table" and results or nil
end

-- what the Quest List has kept of a character of this realm (its record keys the first name, with the class and the
-- level as it last logged out), for one the game names and this module has not noted yet; nil without that addon
local function Met(name, realm)
	local record = rawget(_G, "MelloUIQuestRecord")
	local chars = type(record) == "table" and record.chars
	local first = type(chars) == "table" and realm and name:match("^(%S+)")
	local c = first and chars[first .. "-" .. realm]
	return type(c) == "table" and c or nil
end

-- (2.1.84) a name as the game's list gives it, without the realm of your own server after it ("Name-CAMWOWEU5Realm5PvE"
-- on another layer of yours: the bare name, the address a letter to it takes)
local function Bare(name, here)
	local bare, suffix = name:match("^(.-)%-([^%-%s]+)$")
	if bare and here and R.ServerKey(suffix) == here then
		return bare
	end
	return name
end

-- Your Characters: the noted ones you can write to (Writable: their class and level known), and every other character
-- the game names that is not noted -- by its name as the game gives it (the very text the To field would complete to;
-- with a realm after it, another realm's address as it stands), with its class and level where the Quest List has met
-- it. A noted character the list leaves out (the other faction's) stays out.
-- (2.1.84) -> a second list, the characters that are gone: noted on your server, and the game's own list -- which
-- names others -- names them no more (deleted, renamed). `kept` on a note (its Back in Hidden) holds it in the first
-- list
local function Alts(me, myName, faction)
	local noted = Store("alts")
	local realm = R.Realm()
	local here = R.ServerKey(realm)   -- (2.1.62: the server, not the layer)
	local game = FromGame()
	-- (the game's list counts only while it names somebody: an empty answer may be no answer, and would send every
	-- noted character to Hidden)
	local listed
	for _, r in ipairs(game or {}) do
		local name = type(r) == "table" and Text(r.name) or nil
		if name and name ~= "" then
			listed = listed or {}
			listed[Bare(name, here)] = true
		end
	end
	-- (2.1.62) you yourself left out by name too: your record of another layer bears another key than `me`
	local out, gone = {}, {}
	for _, c in ipairs(Writable(noted, me, faction, true)) do
		if not (c.name == myName and R.ServerKey(c.realm) == here) then
			if listed and not listed[c.name] and not c.kept and R.ServerKey(c.realm) == here then
				gone[#gone + 1] = c
			else
				out[#out + 1] = c
			end
		end
	end
	local known = {}
	if myName then
		known[myName] = true
	end
	for _, c in pairs(noted) do
		if type(c) == "table" and type(c.name) == "string" then
			local theirs = R.ServerKey(c.realm)
			known[c.name .. "-" .. (theirs or "")] = true
			if theirs == nil or theirs == here then
				known[c.name] = true
			end
		end
	end
	for _, r in ipairs(game or {}) do
		local name = type(r) == "table" and Text(r.name) or nil
		name = name and Bare(name, here)
		if name and name ~= "" and not known[name] then
			known[name] = true
			-- (2.1.84) the Quest List keys a first name, and two characters may share one: its class only for a first
			-- name no other character of the list bears
			local met = Met(name, realm)
			out[#out + 1] = { name = name, class = met and Text(met.class) or nil, level = met and Num(met.level) or nil, met = met }
		end
	end
	-- (a first name borne twice in the list, or by the character you are on: the Quest List's class is neither's for sure)
	local firsts = {}
	local mine = myName and myName:match("^(%S+)")
	if mine then
		firsts[mine] = 1
	end
	for _, list in ipairs({ out, gone }) do
		for _, c in ipairs(list) do
			local first = c.name:match("^(%S+)")
			if first then
				firsts[first] = (firsts[first] or 0) + 1
			end
		end
	end
	for _, c in ipairs(out) do
		if c.met then
			if (firsts[c.name:match("^(%S+)") or ""] or 0) > 1 then
				c.class, c.level = nil, nil
			end
			c.met = nil
		end
	end
	table.sort(out, ByLevel)
	table.sort(gone, ByLevel)
	return out, gone
end

-- the To field gets the character's address (R.Address), the cursor moves on to Subject
local function Put(c)
	local to, subject = rawget(_G, "SendMailNameEditBox"), rawget(_G, "SendMailSubjectEditBox")
	if not to then
		return
	end
	local address = R.Address(c)
	R.put = address   -- (2.1.84: the list's own text in To is no search)
	to:SetText(address)
	-- (the field is narrow and a full name long: shown from its start, "Dritprufa Mell", not its end, "fa Melltest")
	if to.SetCursorPosition then
		to:SetCursorPosition(0)
	end
	if subject then
		subject:SetFocus()
	end
	MelloUI:PlayUISound("click")
end

-- your Battle.net friends by BattleTag ("Name#1234"): R.online[tag] true while they play this game, R.playing[tag]
-- the character they play
local function FriendNames()
	local online, playing = Fresh(R.online), Fresh(R.playing)
	local BN = rawget(_G, "C_BattleNet")
	local count = Num(Call(rawget(_G, "BNGetNumFriends"))) or 0
	for i = 1, type(BN) == "table" and count or 0 do
		local info = Call(BN.GetFriendAccountInfo, i)
		local tag = type(info) == "table" and Text(info.battleTag) or nil
		if tag then
			local game = info.gameAccountInfo
			local on = type(game) == "table" and not Secret(game.isOnline) and game.isOnline
				and Text(game.clientProgram) == rawget(_G, "BNET_CLIENT_WOW")
			online[tag] = on and true or false
			playing[tag] = on and Text(game.characterName) or nil
		end
	end
	return online, playing
end

-- (2.1.84) your groups, in your order. The first one is made for you: Pinned (`stock`: its name MelloUI's own word, in
-- your language, until you rename it)
function R.Groups()
	local db = M.db
	if type(db) ~= "table" then
		return {}
	end
	if type(db.groups) ~= "table" then
		db.groups = { { name = TEXT.pinned, stock = true, members = {} } }
	end
	for _, g in ipairs(db.groups) do
		if type(g.members) ~= "table" then
			g.members = {}
		end
	end
	return db.groups
end

function R.GroupName(g)
	return g.stock and Tr(g.name) or g.name
end

-- where a character stands in a group (nil: not in it)
function R.InGroup(g, id)
	for i, m in ipairs(g.members) do
		if R.Id(m) == id then
			return i
		end
	end
	return nil
end

-- in or out of a group
function R.GroupToggle(gi, c)
	local g, id = R.Groups()[gi], R.Id(c)
	if not (g and id) then
		return
	end
	local at = R.InGroup(g, id)
	if at then
		table.remove(g.members, at)
	else
		g.members[#g.members + 1] = { name = c.name, realm = c.realm }
	end
end

function R.GroupNew(name, c)
	name = Trim(name)
	if name == "" then
		return nil
	end
	local groups = R.Groups()
	groups[#groups + 1] = { name = name, members = {} }
	if c then
		R.GroupToggle(#groups, c)
	end
	return #groups
end

function R.GroupRename(gi, name)
	local g = R.Groups()[gi]
	name = Trim(name)
	if g and name ~= "" then
		g.name, g.stock = name, nil
	end
end

function R.GroupMove(gi, by)
	local groups = R.Groups()
	local to = gi + by
	if groups[gi] and groups[to] then
		groups[gi], groups[to] = groups[to], groups[gi]
	end
end

function R.GroupDelete(gi)
	local groups = R.Groups()
	if groups[gi] then
		table.remove(groups, gi)
	end
end

-- a name off the list by hand (Hidden holds it, with what was known of it), and back
function R.Hide(c)
	local id = R.Id(c)
	if id then
		Store("hidden")[id] = { name = c.name, realm = c.realm, class = R.Class(c), level = R.Level(c) }
	end
end

-- a class picked by hand
function R.SetClass(c, class)
	local id = R.Id(c)
	if not id then
		return
	end
	local people = Store("people")
	if type(people[id]) ~= "table" then
		people[id] = {}
	end
	people[id].class = class
	local hidden = Store("hidden")[id]
	if type(hidden) == "table" then
		hidden.class = class
	end
end

-- a letter went out: its name first under Recent
function R.AddRecent(name)
	name = Trim(name)
	if name == "" or not (type(M.db) == "table" and M.db.recent ~= false) then
		return
	end
	local list = Store("sentTo")
	local low = name:lower()
	for i = #list, 1, -1 do
		local r = list[i]
		if type(r) ~= "table" or type(r.name) ~= "string" or r.name:lower() == low then
			table.remove(list, i)
		end
	end
	table.insert(list, 1, { name = name, at = time() })
	for i = #list, R.RECENT + 1, -1 do
		list[i] = nil
	end
end

-- Everything the list is made of, read once a refresh: R.mine (your characters in view), R.gone (the ones the game
-- names no more), R.friends ({ tag, name, online, now, chars } each, a friend with a character to write to), and
-- R.byId: a kept name's record of now (a group's member, a recent name)
function R.Gather()
	local me, myName, _, faction = Me()
	local hidden = Store("hidden")
	local mine, gone = Alts(me, myName, faction)
	R.byId = Fresh(R.byId)
	R.mine = Fresh(R.mine)
	R.gone = gone
	-- (2.1.84) the character you are on: its own note, for the Professions view (no letter goes to yourself)
	local own = me and type(M.db) == "table" and type(M.db.alts) == "table" and M.db.alts[me] or nil
	R.own = type(own) == "table" and type(own.name) == "string" and own or nil
	for _, c in ipairs(mine) do
		local id = R.Id(c)
		if id then
			R.byId[id] = c
		end
		if not (id and hidden[id]) then
			R.mine[#R.mine + 1] = c
		end
	end
	R.friends = Fresh(R.friends)
	if not (M.db and M.db.bnet) then
		return
	end
	local known = Store("bnetChars")
	local online, playing = FriendNames()
	local tags = {}
	for tag in pairs(online) do
		tags[#tags + 1] = tag
	end
	table.sort(tags, ByTag)
	for _, tag in ipairs(tags) do
		local chars = {}
		for _, c in ipairs(Writable(known[tag], nil, faction)) do
			local id = R.Id(c)
			if id and not R.byId[id] then
				R.byId[id] = c
			end
			if not (id and hidden[id]) then
				-- (the one they play now first)
				if playing[tag] and c.name == playing[tag] then
					table.insert(chars, 1, c)
				else
					chars[#chars + 1] = c
				end
			end
		end
		if #chars > 0 then
			R.friends[#R.friends + 1] = { tag = tag, name = tag:match("^[^#]+") or tag, online = online[tag], now = playing[tag],
				chars = chars }
		end
	end
end

--------------------------------------------------------------------------------
-- The list's entries (2.1.84)
-- R.list: what the rows show, in order; R.foot: the foot's rows (Hidden; in the Professions view: Not known yet).
-- An entry: kind "head" (a heading: `key` its fold's, `fold` "open" / "closed", `group` a group of yours), "char"
-- (`c` the character, `sect` where it stands: "group", "recent", "alts", "friend", "found", "prof", "hidden",
-- "unknown"), "friend" (`friend`: R.friends' entry) or "none" (a line of words). Kept and filled again (`n` counts)
--------------------------------------------------------------------------------

R.list, R.foot = { n = 0 }, { n = 0 }

local function Add(list, kind, text, c)
	local n = list.n + 1
	list.n = n
	local e = list[n]
	if not e then
		e = {}
		list[n] = e
	end
	e.kind, e.text, e.c = kind, text, c
	e.key, e.fold, e.right, e.sect, e.group, e.indent, e.tag = nil, nil, nil, nil, nil, nil, nil
	e.skill, e.icon, e.dot, e.gone, e.friend = nil, nil, nil, nil, nil
	return e
end

-- a heading with its fold: -> true while it is open
local function Head(list, text, key, right, folds)
	local e = Add(list, "head", text:upper())
	local folded = folds and folds[key] == true
	e.key, e.right, e.fold = key, right, folded and "closed" or "open"
	return not folded, e
end

-- the list as it stands: your groups, Recent, Your Characters, Battle.net Friends
function R.ListView(L)
	local folds = Store("folds")
	local grouped = Fresh(R.grouped)
	R.grouped = grouped
	for gi, g in ipairs(R.Groups()) do
		local e = Add(L, "head", R.GroupName(g):upper())
		e.group, e.right, e.fold = gi, tostring(#g.members), g.fold and "closed" or "open"
		for _, m in ipairs(g.members) do
			local id = R.Id(m)
			if id then
				grouped[id] = true
				if not g.fold then
					local row = Add(L, "char", nil, R.byId[id] or m)
					row.sect, row.group = "group", gi
				end
			end
		end
	end
	local recent = M.db.recent ~= false and Store("sentTo") or nil
	if recent and #recent > 0 then
		if Head(L, Tr(TEXT.recent), "recent", tostring(#recent), folds) then
			for _, r in ipairs(recent) do
				if type(r) == "table" and type(r.name) == "string" then
					Add(L, "char", nil, R.byId[r.name] or r).sect = "recent"
				end
			end
		end
	end
	-- (a character that stands in one of your groups is not named a second time)
	local n = 0
	for _, c in ipairs(R.mine) do
		if not grouped[R.Id(c)] then
			n = n + 1
		end
	end
	local open = Head(L, Tr(TEXT.alts), "alts", n > 0 and tostring(n) or nil, folds)
	if open then
		for _, c in ipairs(R.mine) do
			if not grouped[R.Id(c)] then
				Add(L, "char", nil, c).sect = "alts"
			end
		end
		if n == 0 and #R.mine == 0 then
			Add(L, "none", Tr(TEXT.noAlts))
		end
	end
	if not M.db.bnet then
		return
	end
	local on = 0
	for _, fr in ipairs(R.friends) do
		if fr.online then
			on = on + 1
		end
	end
	if Head(L, Tr(TEXT.friends), "friends", on > 0 and Tr(TEXT.online):format(on) or nil, folds) then
		for _, fr in ipairs(R.friends) do
			local open2 = folds["f:" .. fr.tag] == true
			local e = Add(L, "friend", fr.name)
			e.friend, e.fold, e.dot, e.right = fr, open2 and "open" or "closed", fr.online, tostring(#fr.chars)
			if open2 then
				for _, c in ipairs(fr.chars) do
					local row = Add(L, "char", nil, c)
					row.sect, row.indent, row.friend, row.dot = "friend", R.INDENT, fr, fr.now ~= nil and c.name == fr.now
				end
			end
		end
		if #R.friends == 0 then
			Add(L, "none", Tr(TEXT.noFriends))
		end
	end
end

-- the foot of the list's view: the names taken off it and the characters that are gone
function R.HiddenFoot(F)
	local names = Fresh(R.hiddenNames)
	R.hiddenNames = names
	for _, rec in pairs(Store("hidden")) do
		if type(rec) == "table" and type(rec.name) == "string" then
			names[#names + 1] = rec
		end
	end
	table.sort(names, ByName)
	for _, rec in ipairs(names) do
		Add(F, "char", nil, rec).sect = "hidden"
	end
	for _, c in ipairs(R.gone) do
		local e = Add(F, "char", nil, c)
		e.sect, e.gone = "hidden", true
	end
	R.footKey, R.footText = "hidden", TEXT.hidden
end

-- who has which profession: a heading a profession (the two a character has; fishing, cooking and first aid are its
-- tooltip's), your characters under it, the best skill first. (2.1.84; the user, 2026-11-24, of the built view: "neither
-- does my main even tho i have Skinning and Enchanting on it") The character you are on stands in it too, said to be
-- you: the view is who has what, and a player with one other character saw an empty page
function R.ProfView(L, F)
	local folds = Store("folds")
	local by, names = Fresh(R.profBy), Fresh(R.profNames)
	R.profBy, R.profNames = by, names
	for _, p in ipairs(R.own and type(R.own.profs) == "table" and R.own.profs or {}) do
		if p.main and type(p.name) == "string" then
			by[p.name] = { { c = R.own, p = p, own = true } }
			names[#names + 1] = p.name
		end
	end
	for _, c in ipairs(R.mine) do
		local any = false
		for _, p in ipairs(type(c.profs) == "table" and c.profs or {}) do
			if p.main and type(p.name) == "string" then
				any = true
				local list = by[p.name]
				if not list then
					list = {}
					by[p.name] = list
					names[#names + 1] = p.name
				end
				list[#list + 1] = { c = c, p = p }
			end
		end
		if not any and type(c.profs) ~= "table" then
			Add(F, "char", nil, c).sect = "unknown"
		end
	end
	table.sort(names)
	for _, name in ipairs(names) do
		local list = by[name]
		table.sort(list, R.BySkill)
		local open, e = Head(L, name, "p:" .. name, tostring(#list), folds)
		e.icon = list[1].p.icon
		if open then
			for _, it in ipairs(list) do
				local row = Add(L, "char", nil, it.c)
				row.sect, row.skill = it.own and "self" or "prof", it.p.rank
				row.tag = it.own and Tr(TEXT.you) or nil
			end
		end
	end
	if #names == 0 then
		Add(L, "none", Tr(TEXT.noProfs))
	end
	R.footKey, R.footText = "unknown", TEXT.unknown
end

function R.BySkill(a, b)
	if (a.p.rank or 0) ~= (b.p.rank or 0) then
		return (a.p.rank or 0) > (b.p.rank or 0)
	end
	return a.c.name < b.c.name
end

-- a name with the typed letters, once
local function Take(found, seen, q, c, tag, friend)
	local low = type(c.name) == "string" and c.name:lower() or nil
	if low and not seen[low] and low:find(q, 1, true) then
		seen[low] = true
		found[#found + 1] = c
		found[c] = tag or false
		if friend then
			R.foundFriend[c] = friend
		end
	end
end

-- What is typed in To: every name of the list with those letters -- your groups', the recent ones, your characters,
-- your friends' (each with whose it is) -- then the game's own names for a letter (its guild members and friends: the
-- To field's own list, so each is the very text a letter takes), and the characters with a profession of that name
function R.FoundView(L, text)
	local q = text:lower()
	local found, seen = Fresh(R.foundList), Fresh(R.foundSeen)
	R.foundList, R.foundSeen, R.foundFriend = found, seen, Fresh(R.foundFriend)
	for _, g in ipairs(R.Groups()) do
		for _, m in ipairs(g.members) do
			Take(found, seen, q, R.byId[R.Id(m) or ""] or m)
		end
	end
	if M.db.recent ~= false then
		for _, r in ipairs(Store("sentTo")) do
			if type(r) == "table" then
				Take(found, seen, q, R.byId[r.name] or r)
			end
		end
	end
	for _, c in ipairs(R.mine) do
		Take(found, seen, q, c)
	end
	for _, fr in ipairs(R.friends) do
		for _, c in ipairs(fr.chars) do
			Take(found, seen, q, c, fr.name, fr)
		end
	end
	local AC, lists = rawget(_G, "C_AutoComplete"), rawget(_G, "AUTOCOMPLETE_LIST")
	local mail = type(lists) == "table" and lists.MAIL
	if M.db.found ~= false and type(AC) == "table" and type(mail) == "table" then
		local P = type(rawget(_G, "Enum")) == "table" and Enum.AutoCompletePriority
		local here = R.ServerKey(R.Realm())
		local pool = R.foundPool or {}
		R.foundPool = pool
		local results = Call(AC.GetAutoCompleteResults, text, R.FOUND, #text, true, mail.include, mail.exclude)
		for i, r in ipairs(type(results) == "table" and results or {}) do
			local name = type(r) == "table" and Text(r.name) or nil
			name = name and Bare(name, here)
			if name and name ~= "" then
				local c = pool[i]
				if not c then
					c = {}
					pool[i] = c
				end
				c.name = name
				local priority = Num(r.priority)
				local tag = type(P) == "table" and priority and ((priority == P.Guild and TEXT.guild)
					or (priority == P.Friend and TEXT.friend)) or nil
				Take(found, seen, q, R.byId[name] or c, tag and Tr(tag) or nil)
			end
		end
	end
	if #found > 0 then
		Add(L, "head", Tr(TEXT.found):format(#found, text):upper())
		for _, c in ipairs(found) do
			local e = Add(L, "char", nil, c)
			e.sect, e.tag, e.friend = "found", found[c] or nil, R.foundFriend[c]
		end
	end
	local any = #found > 0
	if #q >= R.PROF_FIND then
		local by, names = Fresh(R.profBy), Fresh(R.profNames)
		R.profBy, R.profNames = by, names
		for _, c in ipairs(R.mine) do
			for _, p in ipairs(type(c.profs) == "table" and c.profs or {}) do
				if type(p.name) == "string" and p.name:lower():sub(1, #q) == q then
					local list = by[p.name]
					if not list then
						list = {}
						by[p.name] = list
						names[#names + 1] = p.name
					end
					list[#list + 1] = { c = c, p = p }
				end
			end
		end
		table.sort(names)
		for _, name in ipairs(names) do
			local list = by[name]
			table.sort(list, R.BySkill)
			local e = Add(L, "head", Tr(TEXT.foundProf):format(#list, name):upper())
			e.icon = list[1].p.icon
			for _, it in ipairs(list) do
				local row = Add(L, "char", nil, it.c)
				row.sect, row.skill = "prof", it.p.rank
			end
			any = true
		end
	end
	if not any then
		Add(L, "none", Tr(TEXT.noneFound):format(text))
	end
end

-- the entries of now: the typed letters' names, else the view's
function R.Entries()
	local L, F = R.list, R.foot
	L.n, F.n = 0, 0
	R.footKey, R.footText = nil, nil
	if type(M.db) ~= "table" then
		return
	end
	if R.query then
		R.FoundView(L, R.query)
	elseif M.db.view == "prof" then
		R.ProfView(L, F)
	else
		R.ListView(L)
		R.HiddenFoot(F)
	end
end

--------------------------------------------------------------------------------
-- The panel beside Send Mail (2.1.62; the German player: "I'm not happy with the icon at Send Mail -- can't we take an
-- approach that fits MelloUI and build it in to the right of the mail window?"; open and closed by the button, the
-- user's pick). A list box of MelloUI's own (W.TrayBox, the Restock panel's box beside the shop: the kit's list box
-- while the reskin's look is on, the palette's plain box else) hung on the mail window's right while the Send Mail
-- page shows -- a child of that page, so it comes and goes with it. (2.1.84) Its two views (W.Chips), its rows from the
-- entries (the wheel and a thin bar scroll them), the foot's rows at its foot. Made the first time the page shows
--------------------------------------------------------------------------------

R.PANEL_W, R.PAD, R.TOP, R.ROW_H = 236, 10, 62, 22
R.CHIPS_Y, R.CHIPS_H = 36, 20
R.DISC, R.PROF, R.CTL, R.FOLD, R.DOT = 18, 15, 16, 13, 7   -- a row's class picture, profession, control, fold, dot
-- the two controls of a row under the pointer, from the row's right edge: 2, the bin, 4, the Groups button, 3. A row
-- with profession icons keeps that room at its right (its level stands in it), so the buttons never cover the icons
R.CTL_EDGE, R.CTL_GAP = 2, 4
R.CTL_ROOM = R.CTL_EDGE + 2 * R.CTL + R.CTL_GAP + 3
R.INDENT = 16        -- a friend's characters under their row
R.BAR = 6            -- the room the scroll bar takes at the rows' right
R.FOOT_MAX = 4       -- the most of the foot's names in view (the wheel brings the others)
R.FOOT_Y = 8         -- the foot above the panel's lower edge
R.DIM, R.FAINT = 0.7, 0.65   -- a row's number at its right; the word after a name
R.NO_CLASS = 0.72    -- a name whose class is not known
R.AREA = "config"    -- the box's look: the reskin's, as MelloUI's own windows (Kit.Areas), as the Restock panel's
R.first, R.footFirst = 1, 1   -- the first entry shown (the wheel's), the foot's
R.rows, R.footRows = {}, {}   -- the panel's rows (reused)
R.FOOT = { kind = "foot" }    -- the foot's own heading

local panel
local fly   -- the one small box of the panel: a name's groups, a class to pick, a group's own menu

local function Style(fs, role, object, size)
	if MelloUI.StyleFont then
		MelloUI:StyleFont(fs, role, object, size)
	end
	return fs
end

-- the box in the look of the moment (the Restock panel's way: its shade with it, the windows' area, once)
local function PanelLook(f)
	local Kit = MelloUI.Kit
	local on = Kit and Kit.IsOn and Kit:IsOn(R.AREA) and true or false
	if f:SetKit(on and Kit or false) and not f.shaded then
		f.shaded = true
		local rep = f.kitBox
		if rep and rep.skin and Kit.ShadeElement then
			local ok, el = pcall(Kit.ShadeElement, Kit, f, "windows", { host = rep.skin })
			if ok and type(el) == "table" and type(el.Add) == "function" then
				el:Add(rep)
			end
		end
	end
end

-- the list read again and laid; `gather`: what it is made of read again first
function R.Refresh(gather)
	if gather then
		R.Gather()
	end
	R.Entries()
	R.Fill()
end

local function First(name)
	return type(name) == "string" and name:match("^(%S+)") or ""
end

-- a class's name: the game's own, else MelloUI's word for it (Colours' list), else its token
function R.ClassName(class)
	local names = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
	local shown = type(names) == "table" and Text(names[class]) or nil
	if shown then
		return shown
	end
	for _, c in ipairs(MelloUI.Colours and MelloUI.Colours.CLASSES or {}) do
		if c.key == class then
			return Tr(c.label)
		end
	end
	return class
end

-- what a row's tooltip says of its character
function R.TipText(e)
	local c = e.c
	local parts = Fresh(R.tip)
	R.tip = parts
	local class, level = R.Class(c), R.Level(c)
	local shown = class and R.ClassName(class) or nil
	local line
	if shown and level then
		line = Tr(TEXT.tipClassLevel):format(shown, level)
	elseif shown then
		line = shown .. "."
	elseif level then
		line = Tr(TEXT.tipLevel):format(level)
	else
		line = Tr(TEXT.tipNoClass)
	end
	if type(c.seen) == "number" then
		local days = math.floor((time() - c.seen) / 86400)
		line = line .. " " .. (days <= 0 and Tr(TEXT.tipToday) or days == 1 and Tr(TEXT.tipYesterday) or Tr(TEXT.tipDays):format(days))
	end
	parts[#parts + 1] = line
	if e.friend then
		parts[#parts + 1] = Tr(TEXT.tipOf):format(e.friend.name)
	end
	if OtherRealm(c) and type(c.realm) == "string" then
		parts[#parts + 1] = c.realm
	end
	-- its professions: the two it has, then the others
	for pass = 1, 2 do
		local words
		for _, p in ipairs(type(c.profs) == "table" and c.profs or {}) do
			if (p.main and true or false) == (pass == 1) and type(p.name) == "string" then
				words = (words and (words .. "   ") or "") .. p.name .. (p.rank and (" " .. p.rank) or "")
			end
		end
		if words then
			parts[#parts + 1] = words
		end
	end
	if e.gone then
		parts[#parts + 1] = Tr(TEXT.tipGone)
	elseif e.sect == "self" then
		parts[#parts + 1] = Tr(TEXT.tipYou)
	elseif e.sect ~= "hidden" then
		parts[#parts + 1] = Tr(TEXT.tipClick)
	end
	return table.concat(parts, "\n")
end

-- a row at rest: its controls away, what its right side says shown
function R.Rest(row)
	if row.group then
		row.group:Hide()
	end
	if row.bin then
		row.bin:Hide()
	end
	if row.cog then
		row.cog:Hide()
	end
	row.right:SetShown(row.hasRight == true)
	if row.p1 then
		row.p1:SetShown((row.nProf or 0) >= 1)
	end
	if row.p2 then
		row.p2:SetShown((row.nProf or 0) >= 2)
	end
end

-- the handlers of a row's controls (one of each for every row)
local CtlLeave = Perf.Shared("OnLeave on a mail recipients row's control", function(b)
	GameTooltip:Hide()
	local row = b.row
	if row and not row:IsMouseOver() then
		R.Rest(row)
	end
end, "script")

local CtlEnter = Perf.Shared("OnEnter on a mail recipients row's control", function(b)
	local e = b.row and b.row.entry
	local title, line
	if b.what == "group" then
		title, line = TEXT.tipGroups, TEXT.tipGroupsLine
	elseif b.what == "bin" then
		local sect = e and e.sect
		if sect == "group" then
			title = TEXT.tipOut
		elseif sect == "recent" then
			title = TEXT.tipForget
		else
			title, line = TEXT.tipHide, TEXT.tipHideLine
		end
	elseif b.what == "back" then
		title = TEXT.tipBack
	elseif b.what == "cog" then
		title, line = TEXT.tipGroup, TEXT.tipGroupLine
	elseif b.what == "ask" then
		title, line = TEXT.tipAsk, TEXT.tipAskLine
	end
	if title then
		MelloUI.Widgets.ShowTooltip(b, title, line)
	end
end, "script")

local BinClick = Perf.Shared("OnClick on a mail recipients row's bin", function(b)
	local e = b.row and b.row.entry
	if not (e and e.c) then
		return
	end
	if e.sect == "group" and e.group then
		R.GroupToggle(e.group, e.c)
	elseif e.sect == "recent" then
		local list = Store("sentTo")
		for i = #list, 1, -1 do
			if type(list[i]) ~= "table" or list[i].name == e.c.name or R.byId[list[i].name] == e.c then
				table.remove(list, i)
			end
		end
	else
		R.Hide(e.c)
	end
	GameTooltip:Hide()
	MelloUI:PlayUISound("click")
	R.FlyClose()
	R.Refresh(true)
end, "script")

local BackClick = Perf.Shared("OnClick on a hidden mail recipient's Back", function(b)
	local e = b.row and b.row.entry
	if not (e and e.c) then
		return
	end
	if e.gone then
		e.c.kept = true   -- (the note stays in the list though the game names it no more)
	else
		local id = R.Id(e.c)
		if id then
			Store("hidden")[id] = nil
		end
	end
	GameTooltip:Hide()
	MelloUI:PlayUISound("click")
	R.Refresh(true)
end, "script")

local GroupClick = Perf.Shared("OnClick on a mail recipients row's Groups", function(b)
	R.FlyOpen("groups", b.row)
end, "script")

local CogClick = Perf.Shared("OnClick on a mail recipients group's cog", function(b)
	R.FlyOpen("group", b.row)
end, "script")

local AskClick = Perf.Shared("OnClick on a mail recipient's unknown class", function(b)
	R.FlyOpen("class", b.row)
end, "script")

-- a row's control (the Groups button, the bin, Back, a group's cog): made the first time that row shows it
local function Ctl(row, what, glyph, click)
	local b = row[what]
	if not b then
		local W = MelloUI.Widgets
		b = W.GlyphButton(row, R.CTL, glyph)
		b.row, b.what = row, what
		b:RegisterForClicks("LeftButtonUp")
		Perf.SetScript(b, "OnClick", click)
		Perf.HookScript(b, "OnEnter", CtlEnter)
		Perf.HookScript(b, "OnLeave", CtlLeave)
		W.RowPlateChild(row, b)
		row[what] = b
	end
	return b
end

-- the rows that wear the Groups button and the bin under the pointer
function R.Controls(e)
	local sect = e.sect
	return e.kind == "char"
		and (sect == "group" or sect == "recent" or sect == "alts" or sect == "friend" or sect == "found")
end

-- the row under the pointer: its controls in place of the number at its right.
-- (2.1.84; the user in their game, 2026-11-24: "i cant mouseover the icons if im not sure what the professions are,
-- because the mouseover options cover it") The profession icons stay: the controls stand in the room at the row's
-- right that R.Lay keeps for them (R.CTL_ROOM), where the level was
function R.Over(row)
	local e = row.entry
	if not e then
		return
	end
	if R.Controls(e) then
		local bin = e.sect ~= "found" and Ctl(row, "bin", "bin", BinClick) or nil
		local group = Ctl(row, "group", "layers", GroupClick)
		group:ClearAllPoints()
		if bin then
			bin:ClearAllPoints()
			bin:SetPoint("RIGHT", row, "RIGHT", -R.CTL_EDGE, 0)
			bin:Show()
			group:SetPoint("RIGHT", bin, "LEFT", -R.CTL_GAP, 0)
		else
			group:SetPoint("RIGHT", row, "RIGHT", -R.CTL_EDGE, 0)
		end
		group:Show()
	elseif e.kind == "head" and e.group then
		local cog = Ctl(row, "cog", "cog", CogClick)
		cog:ClearAllPoints()
		cog:SetPoint("RIGHT", row, "RIGHT", -R.CTL_EDGE, 0)
		cog:Show()
	else
		return
	end
	row.right:Hide()
end

local RowEnter = Perf.Shared("OnEnter on a mail recipients row", function(row)
	local e = row.entry
	if not e then
		return
	end
	R.Over(row)
	if e.kind == "char" and e.c then
		MelloUI.Widgets.ShowTooltip(row, e.c.name, R.TipText(e))
	end
end, "script")

local RowLeave = Perf.Shared("OnLeave on a mail recipients row", function(row)
	GameTooltip:Hide()
	if not row:IsMouseOver() then   -- (not onto one of its own controls)
		R.Rest(row)
	end
end, "script")

-- a click: a character's address into the To field; a heading folds; a friend's row folds or unfolds their characters
local RowClick = Perf.Shared("OnClick on a mail recipients row", function(row)
	local e = row.entry
	if not e then
		return
	end
	if e.kind == "char" then
		if e.c and e.sect ~= "hidden" and e.sect ~= "self" then
			R.FlyClose()
			Put(e.c)
		end
		return
	end
	local folds = Store("folds")
	if e.kind == "foot" then
		if R.footKey then
			folds[R.footKey .. ":open"] = not folds[R.footKey .. ":open"] or nil
		end
	elseif e.kind == "friend" and e.friend then
		local key = "f:" .. e.friend.tag
		folds[key] = not folds[key] or nil
	elseif e.kind == "head" and e.group then
		local g = R.Groups()[e.group]
		if g then
			g.fold = not g.fold or nil
		end
	elseif e.kind == "head" and e.key then
		folds[e.key] = not folds[e.key] or nil
	else
		return
	end
	MelloUI:PlayUISound("click")
	R.FlyClose()
	R.Refresh()
end, "script")

local Wheel = Perf.Shared("OnMouseWheel on the mail recipients panel", function(_, delta)
	local step = (delta > 0 and -1 or 1) * 2
	local foot = R.footRows[1]
	if foot and foot:IsShown() and R.footShown and R.footShown > 1 then
		for i = 1, R.footShown do
			if R.footRows[i]:IsMouseOver() then
				R.footFirst = R.footFirst + step
				R.Fill()
				return
			end
		end
	end
	R.first = R.first + step
	R.Fill()
end, "script")

local function NewRow(f, pool, i)
	local W = MelloUI.Widgets
	local row = CreateFrame("Button", nil, f)
	row:SetHeight(R.ROW_H)
	row.text = Style(W.Text(row, "GameFontHighlight", nil, "text"), "fontText", _G.GameFontHighlight)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row.head = Style(W.Text(row, "GameFontNormalSmall", nil, "selectedTrim"), "fontText", _G.GameFontNormalSmall)
	row.head:SetJustifyH("LEFT")
	row.head:SetWordWrap(false)
	row.tag = Style(W.Text(row, "GameFontHighlightSmall", nil, "text"), "fontText", _G.GameFontHighlightSmall)
	row.tag:SetWordWrap(false)
	row.tag:SetAlpha(R.FAINT)
	row.right = Style(W.Text(row, "GameFontHighlightSmall", nil, "text"), "fontText", _G.GameFontHighlightSmall)
	row.right:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.right:SetJustifyH("RIGHT")
	row.right:SetAlpha(R.DIM)
	row:RegisterForClicks("LeftButtonUp")
	-- (its own scripts first: the plate's hover is hooked after them)
	Perf.SetScript(row, "OnClick", RowClick)
	Perf.SetScript(row, "OnEnter", RowEnter)
	Perf.SetScript(row, "OnLeave", RowLeave)
	W.RowPlate(row)
	pool[i] = row
	return row
end

-- a row's parts, each made the first time a row shows one
local Make = {}

function Make.fold(row)
	local h = CreateFrame("Frame", nil, row)
	h:SetSize(R.FOLD, R.FOLD)
	h.tex = h:CreateTexture(nil, "ARTWORK")
	h.tex:SetAllPoints()
	return h
end

function Make.disc(row)   -- (a class's picture)
	local b = MelloUI.Widgets.RoundIcon(row, R.DISC)
	b:EnableMouse(false)
	return b
end

function Make.prof(row)   -- (a profession's icon on its heading)
	local b = MelloUI.Widgets.RoundIcon(row, R.PROF)
	b:EnableMouse(false)
	return b
end

-- a profession's icon on a character's row (2.1.84; the user, 2026-11-24: they could not tell an icon's profession):
-- under the pointer it names its profession and the skill; a click on it is the row's click
function R.ProfTip(b)
	local p = b.prof
	if type(p) ~= "table" or type(p.name) ~= "string" then
		return nil
	end
	local line
	if p.rank and p.cap then
		line = Tr(TEXT.tipSkillOf):format(p.rank, p.cap)
	elseif p.rank then
		line = Tr(TEXT.tipSkill):format(p.rank)
	end
	return p.name, line
end

R.ProfEnter = Perf.Shared("OnEnter on a mail recipient's profession", function(b)
	if b.row then
		R.Over(b.row)   -- (the pointer may come onto the icon first: the row's controls with it)
	end
	local title, line = R.ProfTip(b)
	if title then
		MelloUI.Widgets.ShowTooltip(b, title, line)
	end
end, "script")

R.ProfClick = Perf.Shared("OnClick on a mail recipient's profession", function(b)
	if b.row then
		RowClick(b.row)
	end
end, "script")

function Make.own(row)
	local W = MelloUI.Widgets
	local b = W.RoundIcon(row, R.PROF)
	b.row, b.what = row, "prof"
	b:RegisterForClicks("LeftButtonUp")
	Perf.SetScript(b, "OnClick", R.ProfClick)
	Perf.HookScript(b, "OnEnter", R.ProfEnter)
	Perf.HookScript(b, "OnLeave", CtlLeave)
	W.RowPlateChild(row, b)
	return b
end

-- the "?" of a class that is not known: a disc of the icon set in the palette's colours; a click picks the class
function Make.ask(row)
	local W = MelloUI.Widgets
	local b = CreateFrame("Button", nil, row)
	b:SetSize(R.DISC, R.DISC)
	b.disc = b:CreateTexture(nil, "ARTWORK")
	b.disc:SetAllPoints()
	MelloUI.Icons.Set(b.disc, "badge_disc", R.DISC, 0, 1, 0, 1)
	W.Paint(b.disc, "raisedPanel", "vertex", 1)
	b.ring = b:CreateTexture(nil, "OVERLAY")
	b.ring:SetAllPoints()
	MelloUI.Icons.Set(b.ring, "pad_circle", 2 * R.DISC, 0.25, 0.75, 0.25, 0.75)
	W.Paint(b.ring, "trim", "vertex", 1)
	b.mark = W.Text(b, "GameFontHighlightSmall", "?", "text")
	b.mark:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.row, b.what = row, "ask"
	b:RegisterForClicks("LeftButtonUp")
	Perf.SetScript(b, "OnClick", AskClick)
	Perf.SetScript(b, "OnEnter", CtlEnter)
	Perf.SetScript(b, "OnLeave", CtlLeave)
	W.RowPlateChild(row, b)
	return b
end

function Make.dot(row)   -- (playing now: the game's own green)
	local t = row:CreateTexture(nil, "OVERLAY")
	t:SetSize(R.DOT, R.DOT)
	MelloUI.Icons.Set(t, "badge_disc", R.DOT, 0, 1, 0, 1)
	local green = rawget(_G, "GREEN_FONT_COLOR")
	if type(green) == "table" and green.GetRGB then
		t:SetVertexColor(green:GetRGB())
	end
	return t
end

local function Part(row, key, make)
	local p = row[key]
	if not p then
		p = make(row)
		row[key] = p
	end
	return p
end

local function Away(row, key)
	if row[key] then
		row[key]:Hide()
	end
end

-- a picture on a round icon: the icon set's and the game's by path, a profession's as the game gave it (a file's number)
local function SetIcon(b, icon)
	if not pcall(b.SetIcon, b, icon) and b.icon then
		b.icon:SetTexture(icon)
	end
end

-- an entry on a row
function R.Lay(row, e)
	local W = MelloUI.Widgets
	row.entry = e
	local kind = e.kind
	local char = kind == "char"
	local x = 4 + (e.indent or 0)
	-- a heading's fold, a friend's
	if e.fold or kind == "foot" then
		local h = Part(row, "fold", Make.fold)
		local open = e.fold == "open" or (kind == "foot" and R.footOpen)
		h:ClearAllPoints()
		h:SetPoint("LEFT", row, "LEFT", (kind == "head") and 3 or 5, 0)
		W.Caret(h.tex, R.FOLD, open and "down" or "right")
		h:Show()
		x = (kind == "head") and 20 or 26
	else
		Away(row, "fold")
	end
	-- a profession's icon on its heading
	if kind == "head" and e.icon then
		local icon = Part(row, "icon", Make.prof)
		SetIcon(icon, e.icon)
		icon:ClearAllPoints()
		icon:SetPoint("LEFT", row, "LEFT", x, 0)
		icon:Show()
		x = x + R.PROF + 5
	else
		Away(row, "icon")
	end
	-- a character's class: its picture, or the "?" of one not known
	local class = char and R.Class(e.c) or nil
	local path = class and MelloUI.ClassIconPath and MelloUI:ClassIconPath(class, "portrait", R.DISC) or nil
	if path then
		local disc = Part(row, "disc", Make.disc)
		SetIcon(disc, path)
		disc:ClearAllPoints()
		disc:SetPoint("LEFT", row, "LEFT", x - 1, 0)
		disc:Show()
	else
		Away(row, "disc")
	end
	if char and not class then
		local ask = Part(row, "ask", Make.ask)
		ask:ClearAllPoints()
		ask:SetPoint("LEFT", row, "LEFT", x - 1, 0)
		ask:Show()
	else
		Away(row, "ask")
	end
	if char then
		x = x + R.DISC + 5
	end
	-- what stands at the row's right: a character's level or skill, a heading's or a friend's count; a hidden one's Back
	local right = e.right
	if char then
		local n = e.skill or R.Level(e.c)
		right = n and tostring(n) or nil
	end
	local back = char and e.sect == "hidden"
	if back then
		right = nil
		local b = Ctl(row, "back", "reset", BackClick)
		b:ClearAllPoints()
		b:SetPoint("RIGHT", row, "RIGHT", -2, 0)
		b:Show()
	else
		Away(row, "back")
	end
	row.hasRight = right ~= nil
	row.right:SetText(right or "")
	local used = back and (R.CTL + 6) or 4   -- (the room the right side takes, from the row's right edge)
	if right then
		local wide = Num(Call(row.right.GetStringWidth, row.right)) or 0
		used = used + math.max(wide, char and 16 or 0) + 4
	end
	-- a character of yours: its two professions (not where its skill in one stands there already)
	local nProf = 0
	if char and not e.skill and not back and type(e.c.profs) == "table" then
		for _, p in ipairs(e.c.profs) do
			if p.main and p.icon and nProf < 2 then
				nProf = nProf + 1
			end
		end
		-- (2.1.84) a row that wears controls under the pointer keeps their room at its right, the icons left of it:
		-- the buttons take the level's place there and the icons stay to be looked at
		if nProf > 0 and R.Controls(e) then
			used = math.max(used, R.CTL_ROOM)
		end
		-- (laid from the right: the second, then the first)
		local at = nProf
		for i = #e.c.profs, 1, -1 do
			local p = e.c.profs[i]
			if p.main and p.icon and at >= 1 and i <= 2 then
				local icon = Part(row, "p" .. at, Make.own)
				icon.prof = p
				SetIcon(icon, p.icon)
				icon:ClearAllPoints()
				icon:SetPoint("RIGHT", row, "RIGHT", -(used + (nProf - at) * (R.PROF + 3)), 0)
				at = at - 1
			end
		end
		used = used + nProf * (R.PROF + 3) + 2
	end
	row.nProf = nProf
	-- the words: a heading's, a line's, a name in its class's colour
	local fs, other = row.text, row.head
	if kind == "head" or kind == "foot" then
		fs, other = row.head, row.text
		local key = kind == "foot" and "text" or "selectedTrim"
		if row.headKey ~= key then
			row.headKey = key
			W.Paint(fs, key, "text")
		end
	end
	other:Hide()
	local words = e.text
	if kind == "foot" then
		words = Tr(R.footText or ""):format(R.foot.n)
	elseif char then
		local hex = class and MelloUI.Colours and MelloUI.Colours.ClassHex and MelloUI.Colours.ClassHex(class)
		words = hex and ("|c" .. hex .. e.c.name .. "|r") or e.c.name
	end
	fs:SetText(words or "")
	fs:SetAlpha((kind == "none" and R.DIM) or (kind == "foot" and 0.8) or (char and not class and R.NO_CLASS) or 1)
	fs:ClearAllPoints()
	fs:SetPoint("LEFT", row, "LEFT", x, 0)
	-- (cut at the right side's room, the word and the dot after the name with it)
	local room = math.max(20, R.PANEL_W - 2 * R.PAD - R.BAR - x - used)
	local tag = char and (e.tag or (OtherRealm(e.c) and e.c.realm)) or nil
	local dot = e.dot and true or false
	local after = (dot and (R.DOT + 5) or 0)
	local tagWide = 0
	if tag then
		row.tag:SetText(tag)
		tagWide = math.min(Num(Call(row.tag.GetStringWidth, row.tag)) or 0, math.floor(room * 0.4))
		after = after + tagWide + 6
	end
	local wide = Num(Call(fs.GetUnboundedStringWidth, fs)) or Num(Call(fs.GetStringWidth, fs)) or room
	fs:SetWidth(math.max(10, math.min(wide + 1, room - after)))
	fs:Show()
	local last = fs
	if dot then
		local d = Part(row, "dot", Make.dot)
		d:ClearAllPoints()
		d:SetPoint("LEFT", last, "RIGHT", 5, 0)
		d:Show()
		last = d
	else
		Away(row, "dot")
	end
	if tag then
		row.tag:ClearAllPoints()
		row.tag:SetPoint("LEFT", last, "RIGHT", 6, 0)
		row.tag:SetWidth(math.max(10, tagWide + 1))
		row.tag:Show()
	else
		row.tag:Hide()
	end
	row:EnableMouse(kind ~= "none" and not (kind == "head" and not e.fold))
	R.Rest(row)
end

-- the rows from the entries, as many as the box holds from the wheel's first; the foot's at its foot
function R.Fill()
	local f = panel
	if not f then
		return
	end
	local L, F = R.list, R.foot
	local folds = Store("folds")
	R.footOpen = R.footKey ~= nil and folds[R.footKey .. ":open"] == true
	local footNames = (F.n > 0 and R.footOpen) and math.min(F.n, R.FOOT_MAX) or 0
	local footShown = F.n > 0 and (1 + footNames) or 0
	R.footShown = footShown
	local height = Num(f:GetHeight()) or 0
	local room = math.max(1, math.floor((height - R.TOP - R.FOOT_Y - footShown * R.ROW_H - (footShown > 0 and 2 or 0)) / R.ROW_H))
	local n = L.n
	R.first = math.max(1, math.min(R.first, math.max(1, n - room + 1)))
	for i = 1, room do
		local row = R.rows[i]
		if not row then
			row = NewRow(f, R.rows, i)
			row:SetPoint("TOPLEFT", f, "TOPLEFT", R.PAD, -(R.TOP + (i - 1) * R.ROW_H))
			row:SetPoint("RIGHT", f, "RIGHT", -(R.PAD + R.BAR), 0)
		end
		local at = R.first + i - 1
		local e = at <= n and L[at] or nil
		if e then
			R.Lay(row, e)
			row:Show()
		else
			row.entry = nil
			row:Hide()
		end
	end
	for i = room + 1, #R.rows do
		R.rows[i].entry = nil
		R.rows[i]:Hide()
	end
	-- the bar, while some rows wait above or below
	local bar = f.bar
	if bar then
		local more = n > room
		bar:SetShown(more)
		if more then
			R.filling = true
			bar:ClearAllPoints()
			bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -(R.TOP + 2))
			bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -5, R.FOOT_Y + footShown * R.ROW_H + 2)
			bar:SetMinMaxValues(0, n - room)
			bar:SetValue(R.first - 1)
			if bar.thumb then
				bar.thumb:SetHeight(math.max(16, room * R.ROW_H * room / n))
			end
			R.filling = false
		end
	end
	-- the foot: its heading, then its names while it is unfolded
	R.footFirst = math.max(1, math.min(R.footFirst, math.max(1, F.n - footNames + 1)))
	for i = 1, footShown do
		local row = R.footRows[i] or NewRow(f, R.footRows, i)
		row:ClearAllPoints()
		row:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", R.PAD, R.FOOT_Y + (footShown - i) * R.ROW_H)
		row:SetPoint("RIGHT", f, "RIGHT", -(R.PAD + R.BAR), 0)
		R.Lay(row, i == 1 and R.FOOT or F[R.footFirst + i - 2])
		row:Show()
	end
	for i = footShown + 1, #R.footRows do
		R.footRows[i].entry = nil
		R.footRows[i]:Hide()
	end
	-- the row under the pointer keeps its controls through a fill
	if not (fly and fly:IsShown() and fly:IsMouseOver()) then
		R.OverAgain(R.rows)
		R.OverAgain(R.footRows)
	end
end

function R.OverAgain(pool)
	for _, row in ipairs(pool) do
		if row:IsShown() and row:IsMouseOver() then
			R.Over(row)
		end
	end
end

--------------------------------------------------------------------------------
-- The small box of the panel (2.1.84): a name's groups (ticks, and New group... with its name typed there), a class to
-- pick for a character whose class is not known, a group's own menu. One box, made at its first use, laid for what it
-- is asked; a click anywhere else closes it (GLOBAL_MOUSE_DOWN, heard only while it is open)
--------------------------------------------------------------------------------

R.FLY_W, R.FLY_ROW, R.FLY_TOP, R.FLY_DISC = 170, 20, 26, 26

local FlyRowClick = Perf.Shared("OnClick on a row of the mail recipients' small box", function(row)
	local act = row.act
	if not act then
		return
	end
	MelloUI:PlayUISound("click")
	act(row.arg)
end, "script")

local FlyDiscClick = Perf.Shared("OnClick on a class of the mail recipients' class pick", function(b)
	if R.flyC and b.class then
		R.SetClass(R.flyC, b.class)
	end
	MelloUI:PlayUISound("click")
	R.FlyClose()
	R.Refresh(true)
end, "script")

local FlyDiscEnter = Perf.Shared("OnEnter on a class of the mail recipients' class pick", function(b)
	MelloUI.Widgets.ShowTooltip(b, R.ClassName(b.class))
end, "script")

-- the name typed in the box: a new group with the character in it, or the group's new name
local FlyNamed = Perf.Shared("OnEnterPressed on the mail recipients' group name", function(box)
	local name = Trim(Text(Call(box.GetText, box)) or "")
	local renamed = R.flyNaming == "rename"
	if name ~= "" then
		if renamed then
			R.GroupRename(R.flyGroup, name)
		else
			R.GroupNew(name, R.flyC)
		end
	end
	R.flyNaming = nil
	box:ClearFocus()
	if renamed then
		R.FlyClose()
		R.Refresh()
	else
		R.Refresh()
		R.FlyLay()
	end
end, "script")

local FlyNameEscape = Perf.Shared("OnEscapePressed on the mail recipients' group name", function(box)
	box:ClearFocus()
	R.flyNaming = nil
	if R.flyMode == "groups" then
		R.FlyLay()
	else
		R.FlyClose()
	end
end, "script")

local function FlyMake()
	local W = MelloUI.Widgets
	local f = W.TrayBox(panel, { name = "MelloUIMailRecipientsMenu" })
	if Safe.PadIgnore then
		Safe.PadIgnore(f)
	end
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	PanelLook(f)
	f.title = Style(W.Text(f, "GameFontNormalSmall", nil, "selectedTrim"), "fontText", _G.GameFontNormalSmall)
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
	f.title:SetPoint("RIGHT", f, "RIGHT", -8, 0)
	f.title:SetJustifyH("LEFT")
	f.title:SetWordWrap(false)
	f.rows, f.discs = {}, {}
	f.edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	f.edit:SetHeight(20)
	f.edit:SetAutoFocus(false)
	f.edit:SetMaxLetters(24)
	W.Paint(f.edit, "text", "text")
	W.FlatField(f.edit)
	Perf.SetScript(f.edit, "OnEnterPressed", FlyNamed)
	Perf.SetScript(f.edit, "OnEscapePressed", FlyNameEscape)
	f.edit:Hide()
	f:Hide()
	fly = f
	return f
end

-- a line of the box: its words, a mark before them (a tick, the plus), what a click does
local function FlyRow(f, i, y, text, icon, act, arg)
	local W = MelloUI.Widgets
	local row = f.rows[i]
	if not row then
		row = CreateFrame("Button", nil, f)
		row:SetHeight(R.FLY_ROW)
		row.mark = row:CreateTexture(nil, "ARTWORK")
		row.mark:SetSize(14, 14)
		row.mark:SetPoint("LEFT", row, "LEFT", 4, 0)
		row.text = Style(W.Text(row, "GameFontHighlight", nil, "text"), "fontText", _G.GameFontHighlight)
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(false)
		row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
		row:RegisterForClicks("LeftButtonUp")
		Perf.SetScript(row, "OnClick", FlyRowClick)
		W.RowPlate(row)
		f.rows[i] = row
	end
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -y)
	row:SetPoint("RIGHT", f, "RIGHT", -6, 0)
	row.act, row.arg = act, arg
	row.text:SetText(text)
	row.text:ClearAllPoints()
	row.text:SetPoint("LEFT", row, "LEFT", icon and 24 or 6, 0)
	row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.text:SetAlpha(act and 1 or R.DIM)
	row.mark:SetShown(icon ~= nil)
	if icon then
		W.Icon(row.mark, icon, 14)
	end
	row:EnableMouse(act ~= nil)
	row:Show()
	return row
end

-- what the box's lines do
local Fly = {}

function Fly.toggle(gi)
	R.GroupToggle(gi, R.flyC)
	R.Refresh()
	R.FlyLay()
end

function Fly.name(how)
	R.flyNaming = how
	R.FlyLay()
end

function Fly.move(by)
	R.GroupMove(R.flyGroup, by)
	R.FlyClose()
	R.Refresh()
end

function Fly.deleted()
	R.GroupDelete(R.askDelete)
	R.askDelete = nil
	R.Refresh()
end

function Fly.delete()
	local gi = R.flyGroup
	local g = R.Groups()[gi]
	R.FlyClose()
	if not g then
		return
	end
	if #g.members == 0 then
		R.GroupDelete(gi)
		R.Refresh()
		return
	end
	R.askDelete = gi
	MelloUI:Confirm({ text = Tr(TEXT.deleteAsk):format(R.GroupName(g)), accept = TEXT.delete, cancel = TEXT.cancel,
		onAccept = Fly.deleted })
end

-- the box laid for what it was opened for
function R.FlyLay()
	local f = fly
	if not f then
		return
	end
	local W = MelloUI.Widgets
	local mode = R.flyMode
	local y, n, wide = R.FLY_TOP, 0, R.FLY_W
	local edit = false
	for _, d in ipairs(f.discs) do
		d:Hide()
	end
	if mode == "groups" then
		f.title:SetText(Tr(TEXT.groupsOf):format(First(R.flyC.name)))
		local id = R.Id(R.flyC)
		for gi, g in ipairs(R.Groups()) do
			n = n + 1
			FlyRow(f, n, y, R.GroupName(g), R.InGroup(g, id) and "ctl_check_on" or "ctl_check_off", Fly.toggle, gi)
			y = y + R.FLY_ROW
		end
		if R.flyNaming then
			edit = true
		else
			n = n + 1
			FlyRow(f, n, y, Tr(TEXT.newGroup), "btn_expand", Fly.name, "new")
			y = y + R.FLY_ROW
		end
	elseif mode == "group" then
		local groups = R.Groups()
		local g = groups[R.flyGroup]
		f.title:SetText(g and R.GroupName(g) or "")
		wide = 150
		if R.flyNaming then
			edit = true
		else
			FlyRow(f, 1, y, Tr(TEXT.rename), nil, Fly.name, "rename")
			FlyRow(f, 2, y + R.FLY_ROW, Tr(TEXT.moveUp), nil, R.flyGroup > 1 and Fly.move or nil, -1)
			FlyRow(f, 3, y + 2 * R.FLY_ROW, Tr(TEXT.moveDown), nil, R.flyGroup < #groups and Fly.move or nil, 1)
			FlyRow(f, 4, y + 3 * R.FLY_ROW, Tr(TEXT.deleteGroup), nil, Fly.delete)
			n, y = 4, y + 4 * R.FLY_ROW
		end
	elseif mode == "class" then
		f.title:SetText(Tr(TEXT.classOf):format(First(R.flyC.name)))
		local classes = MelloUI.Colours and MelloUI.Colours.CLASSES or {}
		local step = R.FLY_DISC + 4
		wide = 3 * step + 12
		local shown = 0
		for _, class in ipairs(classes) do
			local path = MelloUI.ClassIconPath and MelloUI:ClassIconPath(class.key, "portrait", R.FLY_DISC)
			if path then
				shown = shown + 1
				local d = f.discs[shown]
				if not d then
					d = W.RoundIcon(f, R.FLY_DISC)
					d:RegisterForClicks("LeftButtonUp")
					Perf.SetScript(d, "OnClick", FlyDiscClick)
					Perf.HookScript(d, "OnEnter", FlyDiscEnter)
					Perf.HookScript(d, "OnLeave", W.TipLeave)
					f.discs[shown] = d
				end
				d.class = class.key
				SetIcon(d, path)
				d:ClearAllPoints()
				d:SetPoint("TOPLEFT", f, "TOPLEFT", 8 + ((shown - 1) % 3) * step, -(y + math.floor((shown - 1) / 3) * step))
				d:Show()
			end
		end
		y = y + math.ceil(shown / 3) * step
	end
	for i = n + 1, #f.rows do
		f.rows[i]:Hide()
	end
	f.edit:SetShown(edit)
	if edit then
		f.edit:ClearAllPoints()
		f.edit:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -(y + 2))
		f.edit:SetPoint("RIGHT", f, "RIGHT", -10, 0)
		local g = R.flyNaming == "rename" and R.Groups()[R.flyGroup]
		f.edit:SetText(g and R.GroupName(g) or "")
		f.edit:SetFocus()
		if g and f.edit.HighlightText then
			f.edit:HighlightText()
		end
		y = y + R.FLY_ROW + 6
	end
	f:SetSize(wide, y + 8)
	-- (under its row; over it where the panel's foot is too near)
	local owner = R.flyOwner
	f:ClearAllPoints()
	local bottom, base = owner and Num(Call(owner.GetBottom, owner)), Num(Call(panel.GetBottom, panel))
	if bottom and base and bottom - (y + 8) < base then
		f:SetPoint("BOTTOMRIGHT", owner, "TOPRIGHT", 0, 2)
	else
		f:SetPoint("TOPRIGHT", owner or panel, "BOTTOMRIGHT", 0, -2)
	end
end

function R.FlyClose()
	if fly and fly:IsShown() then
		fly:Hide()
	end
	if R.flyMode then
		R.flyMode, R.flyNaming, R.flyC, R.flyGroup, R.flyOwner = nil, nil, nil, nil, nil
		R.Heard("GLOBAL_MOUSE_DOWN", false)
	end
end

-- opened at a row for its character's groups ("groups"), its class ("class") or its group's menu ("group"); a second
-- click on what opened it closes it
function R.FlyOpen(mode, row)
	local e = row and row.entry
	if not (e and panel) then
		return
	end
	if R.flyMode == mode and R.flyOwner == row then
		R.FlyClose()
		return
	end
	if (mode == "group" and not e.group) or (mode ~= "group" and not e.c) then
		return
	end
	local f = fly or FlyMake()
	R.flyMode, R.flyNaming, R.flyC, R.flyGroup, R.flyOwner = mode, nil, e.c, e.group, row
	GameTooltip:Hide()
	MelloUI:PlayUISound("click")
	R.FlyLay()
	f:Show()
	R.Heard("GLOBAL_MOUSE_DOWN", true)
end

-- the Send Mail page shown again (back from the inbox): the list read again; the box resized: its rows laid again
local PageShown = Perf.Shared("OnShow on the Send Mail page (mail recipients)", function()
	if M.isEnabled and panel and panel:IsShown() then
		WriteMe()
		ReadFriends()
		R.ReadGuild()
		R.Refresh(true)
	end
end, "script")

local Sized = Perf.Shared("OnSizeChanged on the mail recipients panel", function()
	R.Fill()
end, "script")

local PanelHidden = Perf.Shared("OnHide on the mail recipients panel", function()
	R.FlyClose()
end, "script")

local Scrolled = Perf.Shared("OnValueChanged on the mail recipients' scroll bar", function(_, value)
	value = Num(value)
	if R.filling or not value then
		return
	end
	local first = math.floor(value + 0.5) + 1
	if first ~= R.first then
		R.first = first
		R.Fill()
	end
end, "script")

local ViewPicked = Perf.Shared("a view picked on the mail recipients panel", function(_, key)
	if type(M.db) == "table" then
		M.db.view = key
	end
	R.first, R.footFirst = 1, 1
	R.FlyClose()
	R.Refresh()
end, "script")

-- (2.1.84) what is typed in To narrows the list (the list's own text there, R.put, is no search)
local Typed = Perf.Shared("OnTextChanged on the mailbox's To field (mail recipients)", function(box)
	if not (M.isEnabled and panel and panel:IsShown()) then
		return
	end
	local text = Trim(Text(Call(box.GetText, box)) or "")
	local q = (text ~= "" and text ~= R.put) and text or nil
	if q ~= R.query then
		R.query = q
		R.first = 1
		R.FlyClose()
		R.Refresh()
	end
end, "script")

local function Panel()
	if panel then
		return panel
	end
	local page, mail = rawget(_G, "SendMailFrame"), rawget(_G, "MailFrame")
	if not (page and mail) then
		return nil
	end
	local W = MelloUI.Widgets
	local f = W.TrayBox(page, { name = "MelloUIMailRecipients" })
	-- (2.1.81) inside the game's mail window: the panel and its rows kept out of the game's pad navigation (Core.lua,
	-- Safe.PadIgnore; in the Gamepad UI the button that opens it does not show, Apply)
	if Safe.PadIgnore then
		Safe.PadIgnore(f)
	end
	f:SetWidth(R.PANEL_W)
	f:SetPoint("TOPLEFT", mail, "TOPRIGHT", 12, 0)
	f:SetPoint("BOTTOMLEFT", mail, "BOTTOMRIGHT", 12, 0)
	f:EnableMouse(true)
	f:EnableMouseWheel(true)
	Perf.SetScript(f, "OnMouseWheel", Wheel)
	Perf.SetScript(f, "OnSizeChanged", Sized)
	Perf.HookScript(f, "OnHide", PanelHidden)
	Perf.HookScript(page, "OnShow", PageShown)
	local to = rawget(_G, "SendMailNameEditBox")
	if to and to.HookScript then
		Perf.HookScript(to, "OnTextChanged", Typed)
	end
	PanelLook(f)
	MelloUI:On("look:" .. R.AREA, function()
		PanelLook(f)
		if fly then
			PanelLook(fly)
		end
		R.Fill()
	end, "Mail recipients panel")
	-- (a class's picture is the look's own: the unit frames' area decides which)
	MelloUI:On("look:unitframes", function()
		R.Fill()
	end, "Mail recipients panel (class pictures)")
	f.title = Style(W.Text(f, "GameFontNormal", Tr(TEXT.button), "selectedTrim"), "fontTitle", _G.GameFontNormal, 15)
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", R.PAD + 4, -12)
	f.chips = W.Chips(f, { width = R.PANEL_W - 2 * R.PAD - 4, height = R.CHIPS_H, gap = 4, row = true, onPick = ViewPicked })
	f.chips:SetPoint("TOPLEFT", f, "TOPLEFT", R.PAD + 2, -R.CHIPS_Y)
	f.chips:SetItems({ { key = "list", label = Tr(TEXT.list) }, { key = "prof", label = Tr(TEXT.professions) } })
	f.chips:Select(type(M.db) == "table" and M.db.view == "prof" and "prof" or "list")
	f.bar = W.ThinScrollBar(f, 4)
	Perf.SetScript(f.bar, "OnValueChanged", Scrolled)
	f.bar:Hide()
	panel = f
	return f
end

--------------------------------------------------------------------------------
-- The button on the Send Mail page (2.1.59; since 2.1.62 its click opens and closes the panel)
--------------------------------------------------------------------------------

R.SIZE, R.GAP = 18, 4

local button
local Show

local Click = Perf.Shared("OnClick on the mailbox's recipients button", function()
	MelloUI:PlayUISound("click")
	if type(M.db) == "table" then
		M.db.open = not M.db.open
	end
	Show()
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
	if Safe.PadIgnore then
		Safe.PadIgnore(button)   -- (2.1.81: never the game's pad navigation's)
	end
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

-- the button with the Send Mail page while the module is on (not with the Gamepad UI); the panel while the button
-- left it open, its list read again. The panel is made the first time it is opened
function Show()
	local on = M.isEnabled and not Safe.GamepadUI()
	local b = (on and Button()) or button
	if b then
		b:SetShown(on and true or false)
	end
	local open = on and type(M.db) == "table" and M.db.open == true
	local f = (open and Panel()) or panel
	if not f then
		return
	end
	f:SetShown(open and true or false)
	if open then
		WriteMe()
		ReadFriends()
		R.Merge()
		R.ReadGuild()
		-- (the To field as it stands: a name typed before the panel opened narrows it too)
		local to = rawget(_G, "SendMailNameEditBox")
		local text = to and Trim(Text(Call(to.GetText, to)) or "") or ""
		R.query = (text ~= "" and text ~= R.put) and text or nil
		R.Refresh(true)
	end
end

--------------------------------------------------------------------------------
-- The subject from the first attachment (the German player: "when I drag an item into the mail to send it, it would
-- be nice if the subject were taken from the first item" -- as the game's own Send Mail did once)
--------------------------------------------------------------------------------

-- the first attachment's name, with its count where it is a stack ("Tin Ore (20)"); "" with nothing attached
function R.FirstItem()
	local get = rawget(_G, "GetSendMailItem")
	if type(get) ~= "function" then
		return ""
	end
	for i = 1, Num(rawget(_G, "ATTACHMENTS_MAX_SEND")) or 12 do
		local ok, name, _, _, count = pcall(get, i)
		name = ok and Text(name) or nil
		if name and name ~= "" then
			count = Num(count) or 1
			return count > 1 and (name .. " (" .. count .. ")") or name
		end
	end
	return ""
end

-- the subject is written only while it is empty or still the one written here: what you typed stays; taking the item
-- out again empties a subject that was the item's
function R.Subject()
	if not (M.isEnabled and type(M.db) == "table" and M.db.subject ~= false) then
		return
	end
	local box = rawget(_G, "SendMailSubjectEditBox")
	if not (box and box.GetText and box.SetText) then
		return
	end
	local now = Text(Call(box.GetText, box)) or ""
	if now ~= "" and now ~= R.auto then
		R.auto = nil
		return
	end
	local want = R.FirstItem()
	if want ~= now then
		Call(box.SetText, box, want)
	end
	R.auto = want ~= "" and want or nil
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
local EVENTS = { "MAIL_SHOW", "PLAYER_LEVEL_UP", "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE",
	"BN_FRIEND_LIST_SIZE_CHANGED", "MAIL_SEND_INFO_UPDATE", "MAIL_SEND_SUCCESS", "MAIL_FAILED" }

-- an event heard only for a while (a click anywhere, while the small box is open)
function R.Heard(event, on)
	if on then
		pcall(events.RegisterEvent, events, event)
	else
		pcall(events.UnregisterEvent, events, event)
	end
end

-- (2.1.84) a letter on its way: the name it goes to, kept till the game says it went (SendMail, a post-hook)
local function Sent(recipient)
	R.sent = (M.isEnabled and type(M.db) == "table" and M.db.recent ~= false) and Text(recipient) or nil
end

Perf.SetScript(events, "OnEvent", function(_, event)
	if event == "MAIL_SEND_INFO_UPDATE" then
		R.Subject()
	elseif event == "MAIL_SHOW" then
		R.auto, R.query = nil, nil   -- (R.put stays: a name the list put there, still in To, is no search)
		WriteMe()   -- (2.1.84: its professions as they stand, whenever it is at a mailbox)
		Show()
	elseif event == "PLAYER_LEVEL_UP" then
		Perf.C_Timer.After(1, WriteMe)   -- (UnitLevel reads the new level a moment later)
	elseif event == "MAIL_SEND_SUCCESS" then
		if R.sent then
			R.AddRecent(R.sent)
			R.sent = nil
			if panel and panel:IsShown() then
				R.Refresh(true)
			end
		end
	elseif event == "MAIL_FAILED" then
		R.sent = nil
	elseif event == "GLOBAL_MOUSE_DOWN" then
		-- (a click outside the small box and off what opened it)
		if fly and fly:IsShown() and not fly:IsMouseOver() and not (R.flyOwner and R.flyOwner:IsMouseOver()) then
			R.FlyClose()
		end
	else
		ReadFriendsSoon()
	end
end)

function M:OnEnable(db)
	self.db = db
	for _, e in ipairs(EVENTS) do
		pcall(events.RegisterEvent, events, e)
	end
	if not R.hooked and type(rawget(_G, "SendMail")) == "function" then
		R.hooked = true
		Perf.hooksecurefunc("SendMail", Sent)
	end
	WriteMe()
	ReadFriendsSoon()
	Show()
end

function M:OnDisable()
	events:UnregisterAllEvents()
	R.FlyClose()
	Show()
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "bnet" and not value and type(db) == "table" then
		db.bnetChars = nil   -- (switched off: nothing of your friends is kept)
	elseif key == "recent" and not value and type(db) == "table" then
		db.sentTo = nil   -- (switched off: none kept)
		R.sent = nil
	elseif key == "bnet" then
		ReadFriendsSoon()
	end
	if panel and panel:IsShown() then
		R.Refresh(true)
	end
end

-- /mello mail names: the names this client gives -- yours (UnitName and the full display name) and, for each
-- Battle.net friend playing this game now, every name field of their game account -- to see which one a letter needs
M.SlashWords = {
	names = function()
		local say = function(...) MelloUI:Print(...) end
		say("Mail Recipients: UnitName " .. tostring(Text(Call(UnitName, "player")))
			.. ", full name " .. tostring(Text(MelloUI.UnitNameAs and Call(MelloUI.UnitNameAs, MelloUI, "player", "both")))
			.. ", realm " .. tostring(Text(Call(GetRealmName))))
		local BN = rawget(_G, "C_BattleNet")
		local count = Num(Call(rawget(_G, "BNGetNumFriends"))) or 0
		for i = 1, type(BN) == "table" and count or 0 do
			local info = Call(BN.GetFriendAccountInfo, i)
			local tag = type(info) == "table" and Text(info.battleTag) or "?"
			for j = 1, Num(Call(BN.GetFriendNumGameAccounts, i)) or 0 do
				local g = Call(BN.GetFriendGameAccountInfo, i, j)
				if type(g) == "table" and Text(g.clientProgram) == rawget(_G, "BNET_CLIENT_WOW") then
					local parts = {}
					for k, v in pairs(g) do
						if type(k) == "string" and k:lower():find("name") then
							parts[#parts + 1] = k .. "=" .. tostring(Text(v))
						end
					end
					table.sort(parts)
					say("  " .. tag .. ": " .. table.concat(parts, ", "))
				end
			end
		end
	end,
}

-- for the test harness
M.TEXT, M.R = TEXT, R
M.Writable, M.Put, M.ClassToken = Writable, Put, ClassToken
M.WriteMe, M.ReadFriends, M.Alts = WriteMe, ReadFriends, Alts
