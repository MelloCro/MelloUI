--------------------------------------------------------------------------------
-- MelloUI - Swing Timers (0.17.1; 1.2.0: the swing badge)
--
-- Your swing timer for everyone, without the Personal Display: the swing badge (MelloUI.SwingBadge,
-- Core/SwingBadge.lua). (0.17.1 to 1.1: a shot bar and a melee bar in MelloUI's look -- the user, 2026-10-01: "I would
-- love to see better swing timers", docs/plans/swing-timers.md; the Round rim of one look C. Animations round 3, the
-- user 2026-10-22, "yes to all" to BuildData/output/animation_previews/more_anims.html, docs/plans/animations-3.md
-- item 1: the Swing Timers wear the badge, the bars retired.)
--   The badge on your target's nameplate -- your weapon in the gold ring, the next swing's sweep over it, the wind-up
--   and the strike, a crit gold, a dodge or parry bounced back with the game's word, Auto Shot's aim (red, four
--   chevrons; moving holds them), a wand's motes and bolt, red-tinted out of range -- or, with no plate for your
--   target, at its own place: one Edit Layout mover, "Swing Timer" (the melee bar's key, so a place kept from the bars
--   stays), just above the player's cast bar by default.
--   Its host only while the Personal Display does not show the badge itself (its Swing Badge: that one stands under
--   the display, and is in charge -- SwingBadge's hosts, the display's first).
--   Shots, Melee Swings, Off Hand: which swings the badge shows (a wand's shots are the melee's, as on the bars).
-- The game's swing timers are switched off while this is on (its own CVar, showSwingTimer, held by MelloUI:HoldCVar;
-- the player's value comes back when this is off), out of combat only -- and held off: switched on again in the game's
-- settings, it is off again at once (CVAR_UPDATE; in a fight at its end), as the damage meter holds the game's meter.
-- Never a Hide or SetPoint on the game's Edit Mode frames.
-- Nothing at login while off; while on, the badge and its place are made with the first swing (or Edit Layout's
-- first open).
--
-- /mello swing log (plan section 2): the shot's timing as this client gives
-- it. For LOG_TIME seconds it prints, with the seconds since the log began:
--   PLAYER_SWING (duration, type) and the time since the last of its type;
--   START_AUTOREPEAT_SPELL / STOP_AUTOREPEAT_SPELL;
--   your UNIT_SPELLCAST_START / STOP / SUCCEEDED / FAILED / INTERRUPTED with
--   the spell (Auto Shot 75, Shoot 5019);
--   PLAYER_STARTED_MOVING / PLAYER_STOPPED_MOVING;
--   PLAYER_SWING_RANGE_UPDATE and UNIT_ATTACK_SPEED;
-- and on its first line your weapons' speeds, the ranged slot's weapon and
-- the game's own swing timer setting (showSwingTimer). Made on the first
-- log, never at login.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("SwingTimers")
local Shared = Perf.Shared
local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number
local Text = MelloUI.Safe.Text
local SB = MelloUI.SwingBadge

local M = MelloUI:RegisterModule("SwingTimers", {
	title = "Swing Timers",
	desc = "Your swing timer as a badge on your target's nameplate, or above your cast bar while its plate is not there: your weapon in a gold ring with the next swing's sweep over it, a wind-up and a strike, a crit flashing gold, a dodge or parry bounced back; Auto Shot's aim and a wand's bolt. The game's own swing timers are switched off while this is on, and come back as you had them when it is off. While the Personal Display shows its Swing Badge, that one shows your swings.",
	icon = "Interface\\Icons\\Ability_Marksmanship",
	flavour = "Every swing and shot at a glance.",
	role = "replaces",
	slash = "swing",
	enabledByDefault = false,
	-- (not on the installer's Features step: its two columns are full; it is
	-- switched on in the settings window)
	installer = false,
	-- the player's own game setting, given back when off: never in a profile
	keep = { "savedSwing" },
	-- (1.2.0: the bars' Seconds, Width, Height and Show went with them -- an old save's dropped at each enable, Retired;
	-- the one look's `look` before them)
	defaults = { shot = true, melee = true, offhand = true },
	options = {
		{ type = "toggle", key = "shot", name = "Shots",
		  desc = "Your Auto Shot with a bow, gun, crossbow or thrown weapon on the badge: the reload, then the aim in red with four chevrons closing in while you stand still (moving holds the shot back), the shot a recoil." },
		{ type = "toggle", key = "melee", name = "Melee Swings",
		  desc = "Your main hand's swings on the badge: the next swing's sweep, the wind-up and the strike. A wand's shots show here too." },
		{ type = "toggle", key = "offhand", name = "Off Hand",
		  desc = "Your off-hand weapon's swings on a smaller badge beside the main one, while you carry one." },
	},
})

-- the place's size (the two badges side by side, PAIR apart) and its default: centred CAST_GAP above the player's
-- cast bar, else above the screen's bottom middle; the game's CVar; the mover
local B = { PAIR = 3, CAST_GAP = 30, BOTTOM = 250 }
local CVAR = "showSwingTimer"
local MOVER = "swingmelee"
local TEXT = { mover = "Swing Timer" }
local RETIRED = { "look", "width", "height", "show", "text" }

-- state: the badge's place (its frame and mover entry), the CVar's write waiting for the fight's end
local S = { holder = nil, entry = nil, cvarDue = false }

local function On()
	return M.isEnabled and true or false
end

-- the bars' settings dropped (1.2.0), as the one look's `look` before them: at each start, as a profile may bring one
local function Retired(db)
	if type(db) == "table" then
		for _, key in ipairs(RETIRED) do
			db[key] = nil
		end
	end
end

-- (0.21.0, the user 2026-10-12: "the swing timer needs to hide if im using the new ones") the Personal Display shows
-- the badge itself while its Swing Badge is on (the badge's host in charge): this place stands down meanwhile
local function RailsOn()
	local pd = MelloUI:GetModule("PersonalDisplay")
	return pd ~= nil and pd.isEnabled == true and type(pd.db) == "table" and pd.db.swing ~= false
end
M.RailsOn = RailsOn

--------------------------------------------------------------------------------
-- The badge's place: the host
--------------------------------------------------------------------------------

local function Home(holder)
	holder:ClearAllPoints()
	local cast = _G.PlayerCastingBarFrame
	if type(cast) == "table" and cast.GetObjectType then
		holder:SetPoint("BOTTOM", cast, "TOP", 0, B.CAST_GAP)
	else
		holder:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, B.BOTTOM)
	end
	return true
end

-- the place (made with its first need: a swing with no plate, Edit Layout's open), its mover
local function Holder()
	local h = S.holder
	if h then
		return h
	end
	local d = SB.T.badge
	h = CreateFrame("Frame", "MelloUISwingBadge", UIParent)
	h:SetFrameStrata("MEDIUM")
	h:SetClampedToScreen(true)
	h:EnableMouse(false)
	h:SetSize(d + B.PAIR + d * SB.T.badgeOff, d)
	S.holder = h
	S.entry = MelloUI:RegisterMover(h, h, { key = MOVER, default = Home, min = 0.5, max = 2, base = 1,
		label = TEXT.mover, page = "SwingTimers", when = On, placeholder = true })
	if not MelloUI:RestorePosition(MOVER, h) then
		Home(h)
	end
	return h
end

local Host = { key = "swingtimers" }

-- the two at the place, the off hand's right of the main one
function Host.Here(big, small)
	local h = Holder()
	local level = h:GetFrameLevel() + 2
	SB.Attach(big, h, level, 1)
	SB.Attach(small, h, level, 1)
	big:ClearAllPoints()
	big:SetPoint("LEFT", h, "LEFT", 0, 0)
	small:ClearAllPoints()
	small:SetPoint("LEFT", big, "RIGHT", B.PAIR, 0)
end

-- which swings show: Shots, Melee Swings (a wand's shots too), Off Hand
function Host.Wants(hand)
	local db = M.db
	if not db then
		return true
	end
	if hand == "off" then
		return db.offhand ~= false
	end
	if hand == "ranged" and not SB.Ranged.wand then
		return db.shot ~= false
	end
	return db.melee ~= false
end

--------------------------------------------------------------------------------
-- The game's own timers
--------------------------------------------------------------------------------

-- the game's own swing timers off while this is on (out of combat), the player's setting back when off
local function Switches()
	if MelloUI.InCombat() then
		S.cvarDue = true
		return
	end
	S.cvarDue = false
	MelloUI:HoldCVar(M.db, CVAR, "savedSwing", On(), "0")
end

local OnEvent = Shared("OnEvent of the swing timers", function(_, event, a1)
	if event == "CVAR_UPDATE" then
		-- the game's own swing timers switched on again (its settings) while
		-- this stands in for them (the user, 2026-10-02: players had both):
		-- off again (out of combat; in a fight at its end, Switches), the
		-- player's newest choice kept for when this is switched off
		if a1 == CVAR and On() then
			local now = MelloUI:CVarText(CVAR)
			if now ~= nil and now ~= "0" then
				if M.db then
					M.db.savedSwing = now
				end
				Switches()
			end
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if S.cvarDue then
			Switches()
		end
		if not On() then
			S.frame:UnregisterAllEvents()   -- (switched off in the fight: the game's timers were waiting for its end)
		end
	end
end)

local function Events(on)
	if not S.frame then
		if not on then
			return
		end
		S.frame = CreateFrame("Frame")
		Perf.SetScript(S.frame, "OnEvent", OnEvent)
	end
	if on then
		S.frame:RegisterEvent("CVAR_UPDATE")
		S.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	else
		S.frame:UnregisterAllEvents()
	end
end

--------------------------------------------------------------------------------
-- The module
--------------------------------------------------------------------------------

-- Edit Layout's plate: the place made when it opens (its mover with it), never at login
local function MoverSource()
	if On() then
		Holder()
	end
end

function M:OnInit(db)
	self.db = db
	Retired(db)
	MelloUI:AddMoverSource(MoverSource)
end

-- (the saved variables arriving after the login: the table they hold)
function M:OnAddonLoaded(db)
	self.db = db
	Retired(db)
end

function M:OnEnable(db)
	self.db = db or self.db
	Retired(self.db)
	Events(true)
	Switches()
	SB:Use(Host)
end

function M:OnDisable()
	SB:Drop(Host)
	-- the game's own timers back (in a fight: at its end, from the one listener left for it)
	if MelloUI.InCombat() then
		Events(false)
		if S.frame then
			S.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		end
		S.cvarDue = true
	else
		Events(false)
		Switches()
	end
end

-- (Shots, Melee Swings, Off Hand: read at each swing, Host.Wants)
function M:OnSettingChanged(_, _, db)
	self.db = db or self.db
end

-- for the tests and /mello swing: the state and the host
M.S = S
M.Host = Host

--------------------------------------------------------------------------------
-- /mello swing log
--------------------------------------------------------------------------------

local LOG_TIME = 20
local TYPES = { [0] = "MainHand", [1] = "OffHand", [2] = "Ranged" }
local LOG_EVENTS = { "PLAYER_SWING", "PLAYER_SWING_RANGE_UPDATE", "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL",
	"PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
local LOG_UNIT_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_ATTACK_SPEED" }
local log = { frame = nil, t0 = 0, untilAt = 0, last = {}, on = false }

local function Ask(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
	if ok then
		return a, b, c, d, e, f, g, h
	end
	return nil
end

-- a number for the log: two decimals, "secret" or "-"
local function N(v)
	if Secret(v) then
		return "secret"
	end
	v = Num(v)
	return v and string.format("%.2f", v) or "-"
end

local function Say(text, ...)
	MelloUI:Print("swing %6.2f  " .. text, GetTime() - log.t0, ...)
end

local function SpellName(id)
	if Secret(id) then
		return "secret"
	end
	local api = _G.C_Spell
	local name = api and Text((Ask(api.GetSpellName, id)))
	return string.format("%s %s", tostring(id), name or "?")
end

local function LogStop()
	if not log.on then
		return
	end
	log.on = false
	log.frame:UnregisterAllEvents()
	Say("log over")
end

local OnLogEvent = Shared("OnEvent on the swing log", function(_, event, a1, a2, a3)
	if not log.on then
		return
	end
	if GetTime() > log.untilAt then
		LogStop()
		return
	end
	if event == "PLAYER_SWING" then
		local kind = not Secret(a2) and TYPES[a2] or tostring(a2)
		local since = ""
		local last = log.last[kind]
		if last then
			since = string.format("  (%.2f since the last %s)", GetTime() - last, kind)
		end
		log.last[kind] = GetTime()
		Say("PLAYER_SWING %s duration %s%s", kind, N(a1), since)
	elseif event == "PLAYER_SWING_RANGE_UPDATE" then
		Say("PLAYER_SWING_RANGE_UPDATE %s in range %s checks %s", not Secret(a1) and TYPES[a1] or "?", tostring(a2),
			tostring(a3))
	elseif event == "UNIT_ATTACK_SPEED" then
		local main, off = Ask(_G.UnitAttackSpeed, "player")
		Say("UNIT_ATTACK_SPEED main %s off %s", N(main), N(off))
	elseif event:find("^UNIT_SPELLCAST_") then
		-- (unit, castGUID, spellID)
		Say("%s %s", event, SpellName(a3))
	else
		Say("%s", event)
	end
end)

-- /mello swing log
function M.Log()
	if not log.frame then
		log.frame = CreateFrame("Frame")
		Perf.SetScript(log.frame, "OnEvent", OnLogEvent)
	end
	log.t0, log.untilAt, log.on = GetTime(), GetTime() + LOG_TIME, true
	for k in pairs(log.last) do
		log.last[k] = nil
	end
	for _, e in ipairs(LOG_EVENTS) do
		pcall(log.frame.RegisterEvent, log.frame, e)
	end
	for _, e in ipairs(LOG_UNIT_EVENTS) do
		pcall(log.frame.RegisterUnitEvent, log.frame, e, "player")
	end
	-- the ranged range check on, as the game's own timer asks for it
	local st = _G.C_SwingTimer
	if st and st.EnableRangeCheck then
		pcall(st.EnableRangeCheck, 2, true)
	end
	local main, off = Ask(_G.UnitAttackSpeed, "player")
	local ranged = Ask(_G.UnitRangedDamage, "player")
	local item = Ask(_G.GetInventoryItemID, "player", 18)
	local kind = ""
	if item and not Secret(item) and _G.C_Item and _G.C_Item.GetItemInfoInstant then
		local _, _, _, _, _, classID, subclassID = Ask(_G.C_Item.GetItemInfoInstant, item)
		kind = string.format(" (item class %s, subclass %s)", tostring(classID), tostring(subclassID))
	end
	local cvar = MelloUI:CVarText(CVAR)
	MelloUI:Print("Swing log for %d seconds: fire a few shots standing still, then a few while stepping (a melee or wand "
		.. "fight works too). Copy it from /mellolog.", LOG_TIME)
	Say("speeds: main %s off %s ranged %s; ranged slot %s%s; showSwingTimer %s", N(main), N(off), N(ranged),
		tostring(item), kind, tostring(cvar))
	C_Timer.After(LOG_TIME + 0.1, LogStop)
end

M.SlashWords = { log = M.Log }
