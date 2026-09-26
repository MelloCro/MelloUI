--------------------------------------------------------------------------------
-- MelloUI - Reminders
--
-- (user, 2026-09-26: the reminders come and go, "without having them stay on
-- screen the whole time, except when you are in a safe zone, then the Restock
-- should be shown the whole time until the player either restocks or leaves
-- the safe area")
--
-- The page of the one reminder widget (Core/Reminders.lua, MelloUI.Reminders:
-- the round button beside the player ring, its count, glow, hover and place;
-- the settings it reads are this module's: remind_<key>, place, glow, hold)
-- and three of its four users. Restock is the fourth (Modules/Restock.lua):
-- while it has no page of its own, its rows are on this page under its
-- switch (M:OnInit): remind_restock, as every reminder's is remind_<key>.
--   New Mail     mail waiting (HasNewMail: at login and when mail comes).
--                Gone once a mailbox is opened; back only for mail that came
--                after (all of it read before, or a new latest sender).
--   Repair Gear  the worn gear's lowest durability at or under Remind At
--                (30%); broken gear makes it urgent (the most urgent of all).
--   Trainer      Class spells: the character's next level with new spells,
--                kept per character (trainer_<GUID>, a keep key: never in a
--                profile). At each class trainer visit it is the lowest level
--                among the trainer's spells not available yet, else the next
--                of the shipped trainer levels above the character's own
--                (MelloUI_QuestListData.trainerLevels: no class has new
--                spells at level 2); a character never seen before starts at
--                that next level, so nothing is claimed about spells it may
--                have learned already. Profession ranks: a profession whose
--                next rank a trainer can teach now (Journeyman from 50 skill
--                and level 10, Expert 125 and 20, Artisan 200 and 35; the
--                secondary skills Journeyman only, their higher ranks come
--                from books and quests).
-- A click routes to the nearest place that helps (Services:GoTo: a mailbox,
-- a repairer, the class trainer, the profession's trainer); M:GoTo(key) is
-- the same route for anyone else (the Services bar's Errands group). Each
-- spec names that place as the widget's `kind` (the trainer's changes in
-- place with what is due), so the widget measures the reach itself: in
-- reach (40 yd, at a raise, when the player stops or travels while it is
-- up) the glow brightens and a click targets the NPC (the widget's secure
-- button; a mailbox is only routed to). A text is also the reminder's
-- status line while it is not wanted (the Errands tray reads Rem:Text):
-- "No new mail", "Repair Gear: 87%", "Next new spells at level 14".
--
-- The widget's contract (MelloUI.Reminders:Register): key, label, icon,
-- text, urgency (higher first: broken gear 100, Repair 40, Mail 20, Trainer
-- 10), check(key, why) -> active (no reach: the widget's, by `kind`), kind
-- (+ profession), onClick, and no persistent (these three come and go:
-- only Restock stays up in a rest area; their Not now lasts until their
-- next moment, dismiss "moment"). When a reminder shows, for how long and
-- where is the widget's; so are its moments (login, rest, zone) and its
-- login delay. Nothing is read in the login frames: the state is read at
-- the widget's login moment (a check at "login", "rest" or "zone" reads it
-- again), and the passive events are left alone until that first check.
--
-- Secret-safe: every game value is tested for a secret first, and a secret
-- one leaves the state as it was. The three users keep their state on ONE
-- event frame of this module (which event came matters: a mailbox opened, a
-- class trainer's list read), made with the first OnEnable; only a
-- switched-on user's events are registered. Per event a few reads and no
-- garbage: a text is made again only when what it says changed, and the
-- widget is asked to look again (Refresh) only when a reminder's state or an
-- active one's text changed.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("ReminderUsers")   -- (Core/Reminders.lua is "Reminders")

local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number
local Text = MelloUI.Safe.Text

local floor, select, pcall, type, format = math.floor, select, pcall, type, string.format

local PLACES = {
	{ value = "left", label = "Left of the portrait" },
	{ value = "above", label = "Above the portrait" },
	{ value = "right", label = "Right of the portrait" },
}
local GLOWS = {
	{ value = "pulse", label = "Pulse, then steady" },
	{ value = "still", label = "Steady" },
	{ value = "off", label = "Off" },
}

local function Seconds(value)
	return format("%d s", value)
end

local M = MelloUI:RegisterModule("Reminders", {
	title = "Reminders",
	desc = "A small round button beside your portrait reminds you of errands: supplies running low, new mail, gear to repair, a trainer with something new. Click it to route to the nearest place.",
	icon = "Interface\\Icons\\INV_Letter_15",
	flavour = "Supplies, mail, repairs and training: a gentle nudge beside your portrait, never a nag.",
	group = "Quests and travel", navOrder = 5,
	role = "feature",
	keep = { "^trainer_", "^notnow_" },   -- each character's next trainer level (TrainerKey) and the widget's Not now until the next rest area (Core/Reminders.lua: notnow_<GUID>_<key>): never in a profile
	enabledByDefault = true,
	defaults = {
		remind_restock = true,   -- (its row only while Restock has no switch of its own: M:OnInit)
		remind_mail = true,
		remind_repair = true,
		repairAt = 0.3,
		remind_trainer = true,
		trainerClass = true,
		trainerProfession = true,
		place = "left",
		glow = "pulse",
		hold = 8,
	},
	options = {
		{ type = "header", name = "Reminders" },
		-- (Restock's rows go here while it has no page of its own: M:OnInit)
		{ type = "toggle", key = "remind_mail", name = "New Mail",
		  desc = "Remind you when mail is waiting for you. It goes once you open a mailbox, and comes back only for mail that arrives after." },
		{ type = "toggle", key = "remind_repair", name = "Repair Gear",
		  desc = "Remind you when your gear is wearing out. Broken gear goes to the top of the list." },
		{ type = "slider", key = "repairAt", parent = "remind_repair", name = "Remind At", min = 0.1, max = 0.6, step = 0.05, percent = true,
		  desc = "Remind you once your most worn piece of gear is down to this much durability." },
		{ type = "toggle", key = "remind_trainer", name = "Trainer",
		  desc = "Remind you when a trainer has something new for you." },
		{ type = "toggle", key = "trainerClass", parent = "remind_trainer", name = "Class Spells",
		  desc = "When you reach a level with new spells at your class trainer. Each visit to your class trainer tells MelloUI when the next ones come; before your first visit it goes by the levels trainers teach at." },
		{ type = "toggle", key = "trainerProfession", parent = "remind_trainer", name = "Profession Ranks",
		  desc = "When one of your professions can learn its next rank at a trainer: Journeyman, Expert or Artisan." },
		{ type = "header", name = "Widget" },
		{ type = "dropdown", key = "place", name = "Place", values = PLACES,
		  desc = "Where the reminder button sits beside your portrait. With the player frame hidden it keeps a place of its own, which you can move while the windows are unlocked." },
		{ type = "dropdown", key = "glow", name = "Glow", values = GLOWS,
		  desc = "The soft glow around the button: a gentle pulse for a few seconds, then steady; always steady; or none. It brightens when you are close to where the reminder sends you." },
		{ type = "slider", key = "hold", name = "Show For", min = 4, max = 20, step = 1, format = Seconds,
		  desc = "How long a new reminder stays before it tucks itself away. It stays while your pointer is on it." },
	},
})

--------------------------------------------------------------------------------
-- Reads (secret-safe: a secret or missing answer is nil, and the caller keeps
-- what it had). The game's functions are looked up when called: a client
-- without one simply has that part missing.
--------------------------------------------------------------------------------

-- f(...)'s first two results, or nil when f is not a function or raised
local function Ask(f, ...)
	if type(f) ~= "function" then
		return nil
	end
	local ok, a, b = pcall(f, ...)
	if not ok then
		return nil
	end
	return a, b
end

local function PlayerLevel()
	return Num((Ask(UnitLevel, "player")))
end

-- the highest level a character can reach (60 on this client)
local function MaxLevel()
	local max = Num((Ask(_G.GetMaxPlayerLevel)))
	if max and max > 1 then
		return max
	end
	return 60
end

-- the class file token ("WARRIOR"), and the class name as the game shows it
local function PlayerClass()
	local name, token = Ask(UnitClass, "player")
	return Text(token), Text(name)
end

--------------------------------------------------------------------------------
-- The users' state. check() and text() read it; the events, the widget's
-- moments and a switch-on after login fill it. `active` / `told`: what the
-- widget was last asked to look at; `looked`: read once (the widget's first
-- check of it reads it: nothing is read before, and its passive events are
-- left alone until then).
--------------------------------------------------------------------------------

local mail = { key = "mail", setting = "remind_mail", active = false, looked = false, waiting = false, seen = false,
	open = false, sender = nil, text = "No new mail", textFrom = false, textKind = 0 }
local gear = { key = "repair", setting = "remind_repair", active = false, looked = false, lowest = 1, broken = false,
	pct = -1, text = "Repair Gear" }
local trainer = { key = "trainer", setting = "remind_trainer", active = false, looked = false, class = false, from = 0,
	prof = nil, rank = nil, profKey = nil, text = "New spells at your class trainer", textClass = nil, textProf = nil,
	textRank = nil }

local state = {
	registered = false, -- the three specs handed to the widget (while the module is on)
	frame = nil,        -- the event frame (the first OnEnable)
}

local function On(key)
	return M.isEnabled and M.db ~= nil and M.db[key] == true
end

--------------------------------------------------------------------------------
-- New Mail
--------------------------------------------------------------------------------

-- the latest of the senders the game names (nil: none, or secret)
local function LatestSender()
	return Text((Ask(_G.GetLatestThreeSenders)))
end

-- HasNewMail into mail.waiting (a secret answer leaves it)
local function ReadMail()
	local v = Ask(_G.HasNewMail)
	if Secret(v) then
		return
	end
	mail.waiting = v and true or false
end

-- its line: the reminder's while wanted; the Errands tray's status line
-- while not (mail left unread after a visit, or none)
local function MailText()
	local from = mail.sender or false
	local kind = mail.waiting and (mail.seen and 2 or 1) or 3
	if mail.textFrom ~= from or mail.textKind ~= kind then
		mail.textFrom, mail.textKind = from, kind
		if kind == 1 then
			mail.text = from and ("New mail from " .. from) or "New mail"
		elseif kind == 2 then
			mail.text = "Mail waiting at the mailbox"
		else
			mail.text = "No new mail"
		end
	end
	return mail.text
end

-- (event) mail came, or the game looked again: seen mail stays seen unless
-- the box had been read empty or another sender is the latest now
local function MailPending()
	local was = mail.waiting
	ReadMail()
	local latest = LatestSender()
	if mail.waiting and mail.seen and not mail.open and (not was or (latest ~= nil and latest ~= mail.sender)) then
		mail.seen = false
	end
	if mail.waiting then
		mail.sender = latest
	end
end

local function MailShow()
	mail.open, mail.seen = true, true
	mail.sender = LatestSender() or mail.sender
end

local function MailClosed()
	mail.open = false
	ReadMail()
	mail.sender = LatestSender() or mail.sender
end

local function MailActive()
	return On("remind_mail") and mail.waiting and not mail.seen or false
end

--------------------------------------------------------------------------------
-- Repair Gear
--------------------------------------------------------------------------------

local LAST_SLOT = 19   -- the worn gear's slots (1 head .. 19 tabard)

-- the worn gear's lowest durability (0..1) and whether a piece is broken; a
-- slot with no durability or a secret one is left out
local function ReadGear()
	local lowest, broken = 1, false
	local get = _G.GetInventoryItemDurability
	if type(get) ~= "function" then
		gear.lowest, gear.broken = lowest, broken
		return
	end
	for slot = 1, LAST_SLOT do
		local ok, cur, max = pcall(get, slot)
		cur, max = Num(cur), Num(max)
		if ok and cur and max and max > 0 then
			local r = cur / max
			if r < lowest then
				lowest = r
			end
			if cur <= 0 then
				broken = true
			end
		end
	end
	gear.lowest, gear.broken = lowest, broken
end

local function RepairAt()
	local at = M.db and Num(M.db.repairAt)
	if not at or at <= 0 or at >= 1 then
		return 0.3
	end
	return at
end

local function GearText()
	local pct = gear.broken and -2 or floor(gear.lowest * 100 + 0.5)
	if gear.pct ~= pct then
		gear.pct = pct
		gear.text = gear.broken and "Repair Gear: broken gear" or format("Repair Gear: %d%%", pct)
	end
	return gear.text
end

local function GearActive()
	return On("remind_repair") and (gear.broken or gear.lowest <= RepairAt()) or false
end

--------------------------------------------------------------------------------
-- Trainer
--------------------------------------------------------------------------------

-- the setting that keeps this character's next trainer level
local function TrainerKey()
	local guid = Text((Ask(UnitGUID, "player")))
	if not guid then
		return nil
	end
	local key = trainer.keyOf
	if not key or trainer.keyGuid ~= guid then
		key = "trainer_" .. guid:gsub("[^%w]", "")
		trainer.keyOf, trainer.keyGuid = key, guid
	end
	return key
end

-- the next level above `level` at which a class trainer has new spells: the
-- shipped levels of the class, else every even level from 4 (the data: no
-- class has new spells at level 2); nil past the last
local function NextLevel(level)
	local data = rawget(_G, "MelloUI_QuestListData")
	local levels = type(data) == "table" and type(data.trainerLevels) == "table" and data.trainerLevels[PlayerClass() or ""]
	if type(levels) == "table" and #levels > 0 then
		for i = 1, #levels do
			local at = levels[i]
			if type(at) == "number" and at > level then
				return at
			end
		end
		return nil
	end
	local at = level + 1
	if at % 2 == 1 then
		at = at + 1
	end
	if at < 4 then
		at = 4
	end
	return at <= MaxLevel() and at or nil
end

-- the level this character's class trainer has new spells from (0: none
-- known); a character seen for the first time starts at the next level
local function ClassFrom(level)
	local key = TrainerKey()
	if not key or not M.db then
		return 0
	end
	local at = Num(M.db[key])
	if not at then
		at = NextLevel(level) or 0
		M.db[key] = at
	end
	return at
end

-- the lowest level among the open trainer's spells not available yet, above
-- `level` (nil: none listed, or the list hides them)
local function LowestLocked(level)
	local count = Num((Ask(_G.GetNumTrainerServices)))
	local info, req = _G.GetTrainerServiceInfo, _G.GetTrainerServiceLevelReq
	if not count or type(info) ~= "function" or type(req) ~= "function" then
		return nil
	end
	local low = nil
	for i = 1, count do
		local ok, _, _, category = pcall(info, i)
		if ok and not Secret(category) and category == "unavailable" then
			local okR, at = pcall(req, i)
			at = okR and Num(at) or nil
			if at and at > level and (not low or at < low) then
				low = at
			end
		end
	end
	return low
end

-- what the open trainer teaches: "class" (the player's own class trainer),
-- "profession", or nil (a pet trainer, a weapon master, not known)
local function TrainerKind()
	local trade = Ask(_G.IsTradeskillTrainer)
	if not Secret(trade) and trade then
		return "profession"
	end
	local token, class = PlayerClass()
	-- the trainer's line under its name: "Warrior Trainer"
	local sub = nil
	local tips = C_TooltipInfo
	if type(tips) == "table" and type(tips.GetUnit) == "function" then
		local data = Ask(tips.GetUnit, "npc")
		if Secret(data) then
			data = nil
		end
		local line = type(data) == "table" and type(data.lines) == "table" and data.lines[2]
		sub = type(line) == "table" and Text(line.leftText) or nil
	end
	if sub and sub ~= "" then
		sub = sub:lower()
		if class and sub:find(class:lower(), 1, true) and not sub:find("pet", 1, true) then
			return "class"
		end
		return nil
	end
	-- no line to read: a class trainer is of the player's own class
	local _, npcToken = Ask(UnitClass, "npc")
	npcToken = Text(npcToken)
	if token and npcToken == token then
		return "class"
	end
	return nil
end

-- the profession ranks a trainer teaches: at a rank's cap, the skill it can
-- be learned from, the level it needs, its name
local RANKS = {
	[75] = { 50, 10, "Journeyman" },
	[150] = { 125, 20, "Expert" },
	[225] = { 200, 35, "Artisan" },
}

-- the first profession whose next rank a trainer can teach now: its name and
-- the rank's (nil: none), from GetProfessions' answer (ok, ...: pcall's).
-- The game lists the two main professions first;
-- the others (archaeology, fishing, cooking, first aid) take Journeyman only
local function ProfessionDue(level, ok, ...)
	local get = _G.GetProfessionInfo
	if not ok or type(get) ~= "function" then
		return nil
	end
	for i = 1, select("#", ...) do
		local index = select(i, ...)
		if not Secret(index) and index ~= nil then
			local okI, name, _, rank, cap = pcall(get, index)
			name, rank, cap = Text(name), Num(rank), Num(cap)
			local r = okI and cap and RANKS[cap]
			if r and name and rank and rank >= r[1] and level >= r[2] and (i <= 2 or cap == 75) then
				return name, r[3]
			end
		end
	end
	return nil
end

-- the profession's key as the Services bar knows it ("First Aid" ->
-- "firstaid"), kept per name
local profKeys = {}
local function ProfessionKey(name)
	local key = profKeys[name]
	if not key then
		key = name:lower():gsub("%s", "")
		profKeys[name] = key
	end
	return key
end

-- the whole trainer look, into `trainer`
local function ReadTrainer()
	local level = PlayerLevel()
	if not level then
		return
	end
	trainer.class, trainer.from = false, 0
	if M.db and M.db.trainerClass == true then
		local from = ClassFrom(level)
		trainer.from = from
		if from > 0 and level >= from then
			trainer.class = true
		end
	end
	trainer.prof, trainer.rank, trainer.profKey = nil, nil, nil
	if M.db and M.db.trainerProfession == true and type(_G.GetProfessions) == "function" then
		local name, rank = ProfessionDue(level, pcall(_G.GetProfessions))
		if name then
			trainer.prof, trainer.rank, trainer.profKey = name, rank, ProfessionKey(name)
		end
	end
end

-- (event) a trainer's window opened: the class trainer says when its next
-- spells come
local function TrainerShown()
	if TrainerKind() ~= "class" then
		return
	end
	local level, key = PlayerLevel(), TrainerKey()
	if level and key and M.db then
		M.db[key] = LowestLocked(level) or NextLevel(level) or 0
	end
end

-- its line: the reminder's while wanted; the Errands tray's status line
-- while not (when the next spells come)
local function TrainerText()
	local class, prof, rank, from = trainer.class, trainer.prof, trainer.rank, trainer.from
	if trainer.textClass ~= class or trainer.textProf ~= prof or trainer.textRank ~= rank or trainer.textFrom ~= from then
		trainer.textClass, trainer.textProf, trainer.textRank, trainer.textFrom = class, prof, rank, from
		if class and prof then
			trainer.text = format("New spells, and %s %s", rank, prof)
		elseif prof then
			trainer.text = format("%s %s at a trainer", rank, prof)
		elseif class then
			trainer.text = "New spells at your class trainer"
		elseif from > 0 then
			trainer.text = format("Next new spells at level %d", from)
		else
			trainer.text = "Nothing new at your trainers"
		end
	end
	return trainer.text
end

local function TrainerActive()
	return On("remind_trainer") and (trainer.class or trainer.prof ~= nil) or false
end

--------------------------------------------------------------------------------
-- The widget: the specs, and asking it to look again
--------------------------------------------------------------------------------

local ICON = {
	mail = "Interface\\Minimap\\Tracking\\Mailbox",
	repair = "Interface\\Minimap\\Tracking\\Repair",
	class = "Interface\\Minimap\\Tracking\\Class",
	profession = "Interface\\Minimap\\Tracking\\Profession",
}
local URGENT, REPAIR, MAIL, TRAINER = 100, 40, 20, 10

-- where a key's click goes: the Services kind, and the profession for a
-- profession trainer (only a rank due: its trainer; else the class trainer)
local function Where(key)
	if key == "mail" then
		return "mailbox"
	elseif key == "repair" then
		return "repair"
	elseif key == "trainer" then
		if trainer.prof and not trainer.class then
			return "proftrainer", trainer.profKey
		end
		return "classtrainer"
	end
	return nil
end

-- the specs, one table each (filled below): the widget keeps them, reads
-- the fields that change (icon, urgency, text) through their functions, and
-- the trainer's kind / profession as they stand when it measures the reach
local SPECS = {}

-- the trainer's place as the widget measures it, after each look at it
local function Aim()
	local spec = SPECS.trainer
	if spec then
		spec.kind, spec.profession = Where("trainer")
	end
end

local function Services()
	local services = MelloUI:GetModule("Services")
	if services and type(services.GoTo) == "function" then
		return services
	end
	return nil
end

-- Services:GoTo's options for a profession trainer, one table per
-- profession (it may keep one until Route's roads are built: never reused
-- for another)
local GOTO_OPTS = {}

-- the same route for a reminder's key ("mail", "repair", "trainer"): the
-- widget's click, and anyone else's (the Services bar's Errands group).
-- true when routed (or once Route's roads are built); false when Services
-- could not (it says why itself) or the key is not one of these
function M:GoTo(key)
	local kind, profession = Where(key)
	local services = kind and Services()
	if not services then
		return false
	end
	local opts = nil
	if profession then
		opts = GOTO_OPTS[profession]
		if not opts then
			opts = { profession = profession }
			GOTO_OPTS[profession] = opts
		end
	end
	return services:GoTo(kind, opts) == true
end

local USERS = { mail = mail, repair = gear, trainer = trainer }
local ACTIVE = { mail = MailActive, repair = GearActive, trainer = TrainerActive }
local TEXT = { mail = MailText, repair = GearText, trainer = TrainerText }
local ORDER = { "mail", "repair", "trainer" }

-- the widget's check: wanted now (the reach is the widget's own, by the
-- spec's kind: no second answer). Its first check reads the state (the
-- login moment's); at each of its moments (login, a rest area, a zone) it is
-- read again: a change with no event of its own is found there
local MOMENT = { login = true, rest = true, zone = true }

-- a user's state read from the game now
local function Look(key)
	if key == "mail" then
		MailPending()
	elseif key == "repair" then
		ReadGear()
	else
		ReadTrainer()
	end
	USERS[key].looked = true
end

local function Check(key, why)
	local user = USERS[key]
	if not user then
		return false
	end
	if MOMENT[why] or not user.looked then
		Look(key)
	end
	if key == "trainer" then
		Aim()
	end
	local active = ACTIVE[key]()
	-- (what the widget knows now: Changed asks again only after a change)
	user.active, user.told = active, TEXT[key]()
	return active
end

-- its line (the spec's text): asked before the widget's first check (the
-- Errands tray opened in the first seconds), the state is read then
local function Line(key)
	if not USERS[key].looked then
		Look(key)
	end
	return TEXT[key]()
end

local function Click(key)
	return M:GoTo(key)
end

local function Urgency(key)
	if key == "repair" then
		return gear.broken and URGENT or REPAIR
	end
	return key == "mail" and MAIL or TRAINER
end

local function Icon(key)
	if key == "trainer" then
		return (trainer.prof and not trainer.class) and ICON.profession or ICON.class
	end
	return ICON[key]
end

local LABEL = { mail = "New Mail", repair = "Repair Gear", trainer = "Trainer" }
for _, key in ipairs(ORDER) do
	local kind, profession = Where(key)
	SPECS[key] = { key = key, label = LABEL[key], icon = Icon, text = Line, urgency = Urgency, check = Check,
		kind = kind, profession = profession, onClick = Click, dismiss = "moment" }
end
M.SPECS = SPECS   -- (read only: the tests, a dump)

local function Widget()
	local rem = MelloUI.Reminders
	if type(rem) == "table" and type(rem.Register) == "function" then
		return rem
	end
	return nil
end

-- the specs to the widget while the module is on (it keeps a reminder's
-- Not now over a new registration), taken back while it is off
local function Register(on)
	local rem = Widget()
	if not rem or state.registered == on then
		return
	end
	state.registered = on
	for _, key in ipairs(ORDER) do
		if on then
			rem:Register(SPECS[key])
		elseif type(rem.Unregister) == "function" then
			rem:Unregister(key)
		end
	end
end

-- a user's state after a change: the widget asked to look again only when
-- what check() says changed, or what an active one's text() says (one not
-- read yet has nothing to tell: its first check reads it)
local function Changed(key)
	local user = USERS[key]
	if not user.looked then
		return
	end
	if key == "trainer" then
		Aim()
	end
	local active = ACTIVE[key]()
	local text = TEXT[key]()
	local was, wasText = user.active, user.told
	user.active, user.told = active, text
	if was == active and (not active or wasText == text) then
		return
	end
	local rem = Widget()
	if state.registered and rem and type(rem.Refresh) == "function" then
		rem:Refresh(key)
	end
end

-- (a switch-on after the widget's first checks: the users read before are
-- read again, their events were not heard while off)
local function LookAll()
	for _, key in ipairs(ORDER) do
		if USERS[key].looked then
			Look(key)
		end
		Changed(key)
	end
end

--------------------------------------------------------------------------------
-- Events: a switched-on user's only, while the module is on
--------------------------------------------------------------------------------

local EVENTS = {
	mail = { "UPDATE_PENDING_MAIL", "MAIL_SHOW", "MAIL_CLOSED" },
	repair = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED" },
	trainer = { "PLAYER_LEVEL_UP", "TRAINER_SHOW", "TRAINER_CLOSED", "SKILL_LINES_CHANGED" },
}

-- (a passive event of a user not read yet is left alone: its first check
-- reads it; the login frames' events cost nothing)
local function OnEvent(_, event, arg1)
	if event == "UPDATE_INVENTORY_DURABILITY" or event == "PLAYER_EQUIPMENT_CHANGED" then
		if gear.looked then
			ReadGear()
			Changed("repair")
		end
	elseif event == "UPDATE_PENDING_MAIL" then
		if mail.looked then
			MailPending()
			Changed("mail")
		end
	elseif event == "MAIL_SHOW" then
		MailShow()
		Changed("mail")
	elseif event == "MAIL_CLOSED" then
		MailClosed()
		Changed("mail")
	elseif event == "TRAINER_SHOW" then
		TrainerShown()
		if trainer.looked then
			ReadTrainer()
			Changed("trainer")
		end
	elseif trainer.looked and (event == "PLAYER_LEVEL_UP" or event == "TRAINER_CLOSED" or event == "SKILL_LINES_CHANGED") then
		ReadTrainer()
		-- (the level the event names: UnitLevel can still say the old one)
		local level = event == "PLAYER_LEVEL_UP" and Num(arg1)
		if level and not trainer.class and M.db and M.db.trainerClass == true then
			local from = ClassFrom(level)
			trainer.from = from
			if from > 0 and level >= from then
				trainer.class = true
			end
		end
		Changed("trainer")
	end
end

-- the events of the users switched on (an event this client does not have
-- is refused, not an error)
local function Listen()
	local f = state.frame
	if not f then
		return
	end
	f:UnregisterAllEvents()
	if not (M.isEnabled and M.db) then
		return
	end
	for _, key in ipairs(ORDER) do
		if M.db[USERS[key].setting] == true then
			for _, event in ipairs(EVENTS[key]) do
				pcall(f.RegisterEvent, f, event)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

-- Restock's rows that belong to its reminder (live only while its switch is
-- on); its shop list and its list window live with the reminder off too
local REMINDER_ROWS = { below = true, stayResting = true }

function M:OnInit(db)
	self.db = db
	-- Restock's rows (Modules/Restock.lua registers after this file), while
	-- it is a module with no page of its own: laid out first, every one of
	-- them. With a switch of its own for its reminder (`remind`), all as it
	-- declares them (the reminder's rows hang on it). Without one, the
	-- widget's remind_restock is its switch ("Restock"), with the reminder's
	-- rows under it and the others after them.
	local restock = MelloUI:GetModule("Restock")
	if self.restockRows or not restock or restock.group or type(restock.options) ~= "table"
		or #restock.options == 0 then
		return
	end
	local own = false
	for _, opt in ipairs(restock.options) do
		own = own or (opt.type == "toggle" and opt.key == "remind")
	end
	local rows
	if own then
		rows = { { type = "include", module = "Restock" } }
	else
		local gated, free = {}, {}
		for _, opt in ipairs(restock.options) do
			if opt.type ~= "header" and opt.type ~= "include" then
				local into = REMINDER_ROWS[opt.key] and gated or free
				into[#into + 1] = opt
			end
		end
		rows = { { type = "toggle", key = "remind_restock", name = "Restock",
			desc = "Remind you when something on your restock list runs low: drink, food, ammunition or reagents. Click it to go to the nearest shop that sells it." } }
		if #gated > 0 then
			rows[#rows + 1] = { type = "include", module = "Restock", area = "remind_restock", keys = gated }
		end
		if #free > 0 then
			rows[#rows + 1] = { type = "include", module = "Restock", keys = free }
		end
	end
	self.restockRows = rows
	local options = self.options
	for i = #rows, 1, -1 do
		table.insert(options, 2, rows[i])   -- (under the "Reminders" header)
	end
end

-- On: the event frame (the first time), the switched-on users' events and
-- the three handed to the widget (which checks nothing before its login
-- moment, 8 s into the world, and builds nothing before a reminder comes
-- up). Nothing is read here at login: the widget's first check of each
-- reads it; switched on again later, what was read before is read again.
function M:OnEnable(db)
	self.db = db
	if not state.frame then
		state.frame = CreateFrame("Frame")
		Perf.SetScript(state.frame, "OnEvent", OnEvent)
	end
	Listen()
	for _, key in ipairs(ORDER) do
		USERS[key].active, USERS[key].told = false, nil
	end
	LookAll()
	Register(true)
end

-- Off: the events gone and the three taken back from the widget. A restart
-- (a profile load, the settings adopted late: OnDisable then OnEnable) keeps
-- them registered, so a reminder's Not now and its place in the widget stay.
function M:OnDisable()
	Listen()
	if not MelloUI.restartingModules then
		Register(false)
	end
	for _, key in ipairs(ORDER) do
		USERS[key].active, USERS[key].told = false, nil
	end
end

-- (the widget reads remind_<key>, place, glow and hold itself, on 'setting')
function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "remind_mail" or key == "remind_repair" or key == "remind_trainer" then
		Listen()
		-- (its events were not heard while it was off: looked at again)
		if value then
			Look(key:sub(8))
		end
		Changed(key:sub(8))
	elseif key == "repairAt" then
		Changed("repair")
	elseif key == "trainerClass" or key == "trainerProfession" then
		ReadTrainer()
		Changed("trainer")
	end
end
