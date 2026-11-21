--------------------------------------------------------------------------------
-- MelloUI - Mail Recipients (2.1.59, pull request #41 by Glockta-code; a player's wish: "a list of our alts at the
-- mailbox, so you only click which one and the name is filled in", and "the same with Battle.net friends, a tab of
-- its own: I can't remember my friends' characters")
--
-- (2.1.62, pull request #49 by Glockta-code: a panel of its own in place of the button's menu -- the German player:
-- "can't we take an approach that fits MelloUI and build it in to the right of the mail window?" The user's pick of
-- 2026-11-20, C: the button stays, a click on it opens the panel and a second one closes it, and it is open again the
-- next time where it was left open. Closed at first: nothing new on the screen until it is asked for.)
-- A small button at the right of the mailbox's To field (Send Mail) opens a list beside the Send Mail page:
--   Your Characters      your other characters, each in its class colour with its level where that is known; a click
--                        puts the full name in the To field and moves on to Subject. Every other character of the
--                        account is there at once: the game's own name list is asked for them (FromGame), so an alt
--                        need not have logged in with MelloUI first (the user: "i dont see my Alts on the list")
--   Battle.net Friends   a friend a row (their BattleTag's name, "online" while they play), their characters under it
--                        when it is unfolded (a click on its row); every character the game has shown of them while they played, so the ones you
--                        cannot remember are there while they are offline too. One on ANOTHER realm shows its
--                        realm, and the To field gets the game's own address for it (R.Address, below): a bare
--                        name there would go to whoever bears that name on your realm. (2.1.62) Another realm is
--                        another server: WoW Forever names its layers as realms ("CAMWOW EU5 Realm 5 PvE" and
--                        "CAMWOW EU4 Realm 1 PvE": one EU server), and the layer is left out of the comparison
--                        (R.ServerKey)
-- What it keeps, account-wide in its own settings (`keep`: never in a profile or a share string, as Services' learned
-- services), only on this computer:
--   alts       ["Name-Realm"] = { name (the full name, first name and surname), realm, class (the class's token),
--              level, faction, seen } -- this character as it logs in and levels
--   bnetChars  [BattleTag] = { ["Name-Realm"] = { name, realm, class, level, faction, seen } } -- read from the game's
--              friend list while a friend plays this game, a moment after it changes (its events come in bursts)
-- Nothing of the game's is replaced: the button and the panel are MelloUI's own frames on the Send Mail page (the
-- panel W.TrayBox, the Restock panel's box), the click the To field's own SetText. Not with the Gamepad UI (as the
-- button before: MelloUI's buttons inside the game's windows are held back there), and nothing at all while the
-- module is off.
-- On by default (the user, 2026-11-17: "that should be enabled by default"); its switch is Quality of Life > Mail.
-- All it puts on the screen by itself is that one button, on the Send Mail page.
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
	online = "online",
}

local M = MelloUI:RegisterModule("MailRecipients", {
	title = "Mail Recipients",
	desc = "A button beside the mailbox's To field lists your characters and your Battle.net friends' characters: click one and its name is filled in.",
	icon = "Interface\\Icons\\INV_Letter_15",
	flavour = "Who was that again? One click and the letter has its name.",
	enabledByDefault = true,   -- (the user, 2026-11-17: "that should be enabled by default")
	slash = "mail",   -- /mello mail names
	keep ={ "alts", "bnetChars" },   -- your characters and your friends': never in a profile or a share string
	defaults = {
		bnet = true,
		open = false,   -- (2.1.62) the panel beside Send Mail, as the button left it
		subject = true,   -- the subject from the first attachment
	},
	options = {
		{ type = "toggle", key = "bnet", name = "Battle.net Friends' Characters",
		  desc = "The list shows your Battle.net friends too, each with the characters the game has shown of them while they played. Off: your own characters only, and none of theirs noted." },
		{ type = "toggle", key = "subject", name = "Subject from the First Item",
		  desc = "An empty subject takes the name of the first item you attach, with its count for a stack. What you type yourself stays." },
	},
})
MelloUI.MailRecipients = M

local R = {
	SETTLE = 2,      -- seconds: the friend list read once its events have stopped coming
	MAX = 100,       -- the most characters asked of the game's own name list (FromGame)
	onList = {},     -- [BattleTag] = true: on the friend list at the last read (reused)
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
	local server = realm:gsub("%s+[Rr]ealm%s+%d+", "")
	server = server:gsub("%s+(%a%a)%d+", " %1")   -- (the region kept: "EU5" -> "EU", an American one stays apart)
	return RealmKey(server)
end

local function Me()
	local short, realm = Text(Call(UnitName, "player")), Text(Call(GetRealmName))
	if not short or short == "" or not realm or realm == "" then
		return nil
	end
	local full = Text(MelloUI.UnitNameAs and Call(MelloUI.UnitNameAs, MelloUI, "player", "both"))
	return short .. "-" .. realm, (full and full ~= "") and full or short, realm, Text(Call(UnitFactionGroup, "player"))
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

-- this character as it logs in and levels (the Quest List's record of your characters is not read: it keeps
-- UnitName's name, which may be the first name alone, and a letter to it would not arrive)
local function WriteMe()
	local key, name, realm, faction = Me()
	if not key then
		return
	end
	local alts = Store("alts")
	local _, class = Call(UnitClass, "player")
	local rec = alts[key]
	if type(rec) ~= "table" then
		rec = {}
		alts[key] = rec
	end
	rec.name, rec.full, rec.realm, rec.class = name, true, realm, Text(class)
	rec.level, rec.faction, rec.seen = Num(Call(UnitLevel, "player")), faction, time()
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

--------------------------------------------------------------------------------
-- The menu
--------------------------------------------------------------------------------

-- a character's line: its name in its class colour, its level after it dimmed (a friend's on another realm of this
-- server is written to as well: the user, "same faction, I can still send", the game's own name list offering it)
local function OtherRealm(c)
	-- (2.1.62: another SERVER, R.ServerKey -- another layer of yours is no other realm; the address keeps the realm whole)
	local mine, theirs = R.ServerKey(Text(Call(GetRealmName))), R.ServerKey(c.realm)
	return (mine and theirs and mine ~= theirs) and RealmKey(c.realm) or nil
end

local function Line(c)
	local hex = c.class and MelloUI.Colours and MelloUI.Colours.ClassHex and MelloUI.Colours.ClassHex(c.class)
	local name = hex and ("|c" .. hex .. c.name .. "|r") or c.name
	local line = c.level and (name .. "  |cff9d9d9d" .. c.level .. "|r") or name
	-- (another realm: named, so it is seen before the letter goes)
	return OtherRealm(c) and (line .. "  |cff9d9d9d" .. c.realm .. "|r") or line
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

-- Your Characters as the menu lists them: the noted ones you can write to (Writable: their class and level known), and
-- every other character the game names that is not noted -- by its name as the game gives it (the very text the To
-- field would complete to; with a realm after it, another realm's address as it stands), in its class colour and with
-- its level where the Quest List has met it. A noted character the menu leaves out (the other faction's) stays out.
local function Alts(me, myName, faction)
	local noted = Store("alts")
	local realm = Text(Call(GetRealmName))
	local here = R.ServerKey(realm)   -- (2.1.62: the server, not the layer)
	-- (2.1.62) you yourself left out by name too: your record of another layer bears another key than `me`
	local out = {}
	for _, c in ipairs(Writable(noted, me, faction, true)) do
		if not (c.name == myName and R.ServerKey(c.realm) == here) then
			out[#out + 1] = c
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
	for _, r in ipairs(FromGame() or {}) do
		local name = type(r) == "table" and Text(r.name) or nil
		if name and name ~= "" and not known[name] then
			known[name] = true
			local met = Met(name, realm)
			out[#out + 1] = { name = name, class = met and Text(met.class) or nil, level = met and Num(met.level) or nil }
		end
	end
	table.sort(out, ByLevel)
	return out
end

-- the To field gets the character's address (R.Address), the cursor moves on to Subject
local function Put(c)
	local to, subject = rawget(_G, "SendMailNameEditBox"), rawget(_G, "SendMailSubjectEditBox")
	if not to then
		return
	end
	to:SetText(R.Address(c))
	-- (the field is narrow and a full name long: shown from its start, "Dritprufa Mell", not its end, "fa Melltest")
	if to.SetCursorPosition then
		to:SetCursorPosition(0)
	end
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

--------------------------------------------------------------------------------
-- The panel beside Send Mail (2.1.62; the German player: "I'm not happy with the icon at Send Mail -- can't we take an
-- approach that fits MelloUI and build it in to the right of the mail window?"; open and closed by the button, the
-- user's pick). A list box
-- of MelloUI's own (W.TrayBox, the Restock panel's box beside the shop: the kit's list box while the reskin's look is
-- on, the palette's plain box else) hung on the mail window's right while the Send Mail page shows -- a child of that
-- page, so it comes and goes with it. Your characters, then your Battle.net friends, each friend a row that unfolds
-- their characters under it (this session); a click on a character fills the To field (Put). More rows than room:
-- the mouse wheel scrolls them. Made the first time the page shows
--------------------------------------------------------------------------------

R.PANEL_W, R.PAD, R.HEAD, R.ROW_H = 210, 10, 34, 18
R.AREA = "config"   -- the box's look: the reskin's, as MelloUI's own windows (Kit.Areas), as the Restock panel's
R.open = {}          -- [BattleTag] = true: that friend's characters unfolded (this session)
R.first = 1          -- the first entry shown (the wheel's)
R.list = {}          -- the entries in order: { kind = "title" | "char" | "friend" | "none", text, c, tag }
R.rows = {}          -- the panel's rows (reused)
R.MORE = { kind = "none", text = "..." }   -- (the rows' hint: more above or below, the wheel's)

local panel

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

local function Add(kind, text, c, tag)
	local list = R.list
	local e = list[#list + 1] or {}
	list[#list + 1] = e
	e.kind, e.text, e.c, e.tag = kind, text, c, tag
end

-- the entries, read again (your characters and your friends' as noted now)
function R.Entries()
	for i = #R.list, 1, -1 do
		R.list[i] = nil
	end
	local me, myName, _, faction = Me()
	Add("title", Tr(TEXT.alts))
	local alts = Alts(me, myName, faction)
	for _, c in ipairs(alts) do
		Add("char", Line(c), c)
	end
	if #alts == 0 then
		Add("none", Tr(TEXT.noAlts))
	end
	if not (M.db and M.db.bnet) then
		return
	end
	Add("title", Tr(TEXT.friends))
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
			local open = R.open[tag]
			local label = (open and "\226\128\147 " or "+ ") .. (tag:match("^[^#]+") or tag)
			if friends[tag] then
				label = label .. "  |cff40ff40" .. Tr(TEXT.online) .. "|r"
			end
			Add("friend", label, nil, tag)
			if open then
				for _, c in ipairs(chars) do
					Add("char", "    " .. Line(c), c)
				end
			end
			shown = shown + 1
		end
	end
	if shown == 0 then
		Add("none", Tr(TEXT.noFriends))
	end
end

-- a click: a character's address into the To field; a friend's row folds or unfolds their characters
local RowClick = Perf.Shared("OnClick on a mail recipients row", function(row)
	local e = row.entry
	if not e then
		return
	elseif e.kind == "char" and e.c then
		Put(e.c)
	elseif e.kind == "friend" and e.tag then
		R.open[e.tag] = not R.open[e.tag] or nil
		MelloUI:PlayUISound("click")
		R.Entries()
		R.Fill()
	end
end, "script")

local Wheel = Perf.Shared("OnMouseWheel on the mail recipients panel", function(_, delta)
	R.first = R.first - (delta > 0 and 1 or -1) * 3
	R.Fill()
end, "script")

local function NewRow(f, i)
	local W = MelloUI.Widgets
	local row = CreateFrame("Button", nil, f)
	row:SetHeight(R.ROW_H)
	row:SetPoint("TOPLEFT", f, "TOPLEFT", R.PAD, -(R.HEAD + (i - 1) * R.ROW_H))
	row:SetPoint("RIGHT", f, "RIGHT", -R.PAD, 0)
	row.text = Style(W.Text(row, "GameFontHighlight", nil, "text"), "fontText", _G.GameFontHighlight)
	row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
	row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	W.RowPlate(row)
	row:RegisterForClicks("LeftButtonUp")
	Perf.SetScript(row, "OnClick", RowClick)
	R.rows[i] = row
	return row
end

-- the rows from the entries, as many as the box holds from the wheel's first
function R.Fill()
	local f = panel
	if not f then
		return
	end
	local room = math.max(1, math.floor((f:GetHeight() - R.HEAD - R.PAD) / R.ROW_H))
	local n = #R.list
	R.first = math.max(1, math.min(R.first, math.max(1, n - room + 1)))
	local W = MelloUI.Widgets
	-- (2.1.62; the German player's screenshot: four friends under the box's foot, nothing to say so) a dim "..." in the
	-- first row while some are scrolled away above, in the last while some wait below; the wheel brings them
	local up, down = R.first > 1, R.first + room - 1 < n
	for i = 1, room do
		local row = R.rows[i] or NewRow(f, i)
		local e = R.list[R.first + i - 1]
		if (i == 1 and up) or (i == room and down) then
			e = R.MORE
		end
		row.entry = e
		if e then
			row.text:SetText(e.kind == "none" and ("|cff9d9d9d" .. e.text .. "|r") or e.text)
			if e.kind == "title" then
				W.Paint(row.text, "selectedTrim", "text")
			else
				W.Paint(row.text, "text", "text")
			end
			row:EnableMouse(e.kind == "char" or e.kind == "friend")
			row:Show()
		else
			row.entry = nil
			row:Hide()
		end
	end
	for i = room + 1, #R.rows do
		R.rows[i]:Hide()
	end
end

-- the Send Mail page shown again (back from the inbox): the list read again; the box resized: its rows laid again
local PageShown = Perf.Shared("OnShow on the Send Mail page (mail recipients)", function()
	if M.isEnabled and panel and panel:IsShown() then
		WriteMe()
		ReadFriends()
		R.Entries()
		R.Fill()
	end
end, "script")

local Sized = Perf.Shared("OnSizeChanged on the mail recipients panel", function()
	R.Fill()
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
	f:SetWidth(R.PANEL_W)
	f:SetPoint("TOPLEFT", mail, "TOPRIGHT", 12, 0)
	f:SetPoint("BOTTOMLEFT", mail, "BOTTOMRIGHT", 12, 0)
	f:EnableMouse(true)
	f:EnableMouseWheel(true)
	Perf.SetScript(f, "OnMouseWheel", Wheel)
	Perf.SetScript(f, "OnSizeChanged", Sized)
	Perf.HookScript(page, "OnShow", PageShown)
	PanelLook(f)
	MelloUI:On("look:" .. R.AREA, function()
		PanelLook(f)
	end, "Mail recipients panel")
	f.title = Style(W.Text(f, "GameFontNormal", Tr(TEXT.button), "selectedTrim"), "fontTitle", _G.GameFontNormal, 15)
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", R.PAD + 4, -12)
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
		R.Entries()
		R.Fill()
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
	"BN_FRIEND_LIST_SIZE_CHANGED", "MAIL_SEND_INFO_UPDATE" }

Perf.SetScript(events, "OnEvent", function(_, event)
	if event == "MAIL_SEND_INFO_UPDATE" then
		R.Subject()
	elseif event == "MAIL_SHOW" then
		R.auto = nil
		Show()
	elseif event == "PLAYER_LEVEL_UP" then
		Perf.C_Timer.After(1, WriteMe)   -- (UnitLevel reads the new level a moment later)
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

function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "bnet" and not value and type(db) == "table" then
		db.bnetChars = nil   -- (switched off: nothing of your friends is kept)
		return
	end
	ReadFriendsSoon()
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
M.WriteMe, M.ReadFriends, M.Line, M.Alts = WriteMe, ReadFriends, Line, Alts
