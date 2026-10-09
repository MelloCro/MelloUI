--------------------------------------------------------------------------------
-- MelloUI - Frame Effects (0.20.0; docs/plans/frame-effects.md)
--
-- The user, 2026-10-09: "lets take 1 class, for example the warrior, Last
-- Stand, Shield Wall, Aoe Taunt ... for their unitframe to reflect that", a
-- roar after a champion's scream, then every class's: six kinds from the
-- client's own spell data (FrameEffectsSpells.lua, Tools/heal_flight_spells.py)
-- -- a roar, a taunt, damage taken down, more health, an immunity, a dodge or
-- parry -- their looks picked in the Effect Tester (the roar's square fiery
-- ripples for 2 s, Shield Wall's steel, Last Stand's heartbeat ...). "Both":
-- when you use one your own frame plays it, when someone of your group uses
-- one theirs does, for as long as the spell lasts. A feature of its own
-- ("Its own feature, rename to Frame Effects") on the engine Heal Flight
-- shares: MelloUI.FrameFX (Core/FrameFX.lua).
-- Each comes from its caster's UNIT_SPELLCAST_SUCCEEDED (every one of them is
-- cast on its caster): its spell ID plain (a secret one plays nothing; the
-- probe, /melloheal, notes your group's casts to tell). A cast is told for
-- every unit token that shows its caster (raid3, party1, target ...): only
-- the group's own count, once a frame.
-- Nothing at login: the event is listened to while the module is on, the
-- effects made on the first. Reduce Motion: nothing.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_FrameEffects (Frame Effects)")
local Safe = MelloUI.Safe
local Text, Num = Safe.Text, Safe.Number
local Anim = MelloUI.Anim
local FX = MelloUI.FrameFX

local NEW = "0.20.0"
local KINDS = ns.EffectKinds or {}
local LASTS = ns.EffectLasts or {}
local EXAMPLES = ns.EffectExamples or {}
local SAME = 0.2          -- s: the same frame told again within this is the same cast (raid3 and party1)
local SHOW_GAP = 3.2      -- s between Every Effect's
local SHOW_LAST = 2.8     -- s each lasts there (a lasting one shortened)

local TEXT = {
	off = "Frame Effects is off.",
	reduceMotion = "Frame Effects: Reduce Motion is on, so nothing plays.",
	noFrame = "Frame Effects: no party or raid frame of yours is shown.",
	example = "%s (%s's %s)",
	kinds = { W = "Roar", U = "Taunt", F = "Damage taken down", L = "More health", I = "Immunity", E = "Dodge / parry" },
}

local M   -- (the module, registered below)
local P = {
	played = setmetatable({}, { __mode = "k" }),   -- [frame] = when it last played (the same cast told twice)
	show = 0,                                       -- Every Effect's step
}

-- a kind's effect on the unit's frame, as long as the spell lasts (once a frame)
local function Play(unit, kind, spell)
	local frame = FX.FrameOf(unit)
	if not frame then
		return
	end
	local now = GetTime()
	local last = P.played[frame]
	if last and now - last < SAME then
		return
	end
	P.played[frame] = now
	FX.Show(unit, kind, nil, false, spell and LASTS[spell])
end

-- a member's own unit token (a cast is also told as target, focus, a nameplate)
local function GroupUnit(unit)
	return unit:match("^party%d+$") or unit:match("^raid%d+$")
end

local function OnCast(unit, spellID)
	local id = Num(spellID)
	local kind = id and KINDS[id]
	unit = Text(unit)
	if not (kind and unit) or Anim.reduceMotion then
		return
	end
	local you = FX.Canon("player")
	if unit == "player" or unit == you then
		if M.db.mine then
			Play(you, kind, id)
		end
	elseif GroupUnit(unit) and M.db.group then
		Play(unit, kind, id)
	end
end

local OnEvent = Perf.Shared("Frame Effects' casts", function(_, _, unit, _, spellID)
	OnCast(unit, spellID)
end, "script")

local events

local function Listen(on)
	if on and not events then
		events = CreateFrame("Frame")
		events:SetScript("OnEvent", OnEvent)
	end
	if not events then
		return
	end
	events:UnregisterAllEvents()
	if on then
		events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	end
end

--------------------------------------------------------------------------------
-- Every Effect: each kind on your own frame, one after another
--------------------------------------------------------------------------------

-- (one chain at a time: a step due before the newest one's time is an older
-- chain's, started again since -- it ends there)
local function ShowNext()
	if GetTime() < (P.due or 0) - 0.05 then
		return
	end
	P.show = P.show + 1
	local e = EXAMPLES[P.show]
	if not (e and M.isEnabled) then
		return
	end
	local kind, class, name, spell = e[1], e[2], e[3], e[4]
	MelloUI:Announce(TEXT.example:format(TEXT.kinds[kind] or kind, class, name), "info")
	FX.Show(FX.Canon("player"), kind, nil, false, math.min(LASTS[spell] or SHOW_LAST, SHOW_LAST))
	P.due = GetTime() + SHOW_GAP
	C_Timer.After(SHOW_GAP, ShowNext)
end

local function PreviewAll()
	if not (M and M.isEnabled) then
		MelloUI:Announce(TEXT.off, "info")
		return
	end
	if Anim.reduceMotion then
		MelloUI:Announce(TEXT.reduceMotion, "info")
		return
	end
	FX.Members()
	if not FX.FrameOf(FX.Canon("player")) then
		MelloUI:Announce(TEXT.noFrame, "info")
		return
	end
	P.show, P.due = 0, 0
	ShowNext()
end

-- Every Effect stopped, whatever plays on the frames cleared (/mellofx stop)
local function StopPreview()
	P.show, P.due = #EXAMPLES, 0
	FX.ClearAll()
end

--------------------------------------------------------------------------------
-- The module
--------------------------------------------------------------------------------

M = MelloUI:RegisterModule("FrameEffects", {
	title = "Frame Effects",
	desc = "Your group's frames show their big moments: a roar's square ripples, a taunt, Shield Wall's steel, Last Stand's heartbeat, an immunity's barrier, an evasion's afterimages -- on your own frame when you use one, on a group mate's when they do.",
	icon = "Interface\\Icons\\Ability_Warrior_ShieldWall",
	flavour = "Shield Wall, Last Stand, a roar: your group's frames show their big moments.",
	role = "adds",
	enabledByDefault = true,
	installer = false,
	new = NEW,
	defaults = {
		mine = true,
		group = true,
	},
	options = {
		{ type = "button", name = "Every Effect", text = "Play", new = NEW,
		  hint = "each kind on your own frame",
		  desc = "Plays each kind on your own frame, one after another, its name and an example on the screen: a roar (Challenging Shout), a taunt, damage taken down (Shield Wall), more health (Last Stand), an immunity, a dodge or parry (Evasion).",
		  onClick = function() PreviewAll() end },
		{ type = "toggle", key = "mine", name = "Your Own", new = NEW,
		  desc = "When you use one (Challenging Shout, Shield Wall, Last Stand, Divine Shield, Evasion ...), your own frame in your party or raid frames plays its effect for as long as it lasts (a roar: 2 seconds)." },
		{ type = "toggle", key = "group", name = "Your Group's", new = NEW,
		  desc = "When someone of your party or raid uses one, their frame plays its effect: you see at a glance who just used Shield Wall or Divine Shield, and whose roar just pulled." },
	},
})

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	Listen(true)
end

function M:OnDisable()
	Listen(false)
end

function M:OnSettingChanged(key, value, db)
	self.db = db
end

M.PreviewAll = PreviewAll
M.StopPreview = StopPreview
M.OnCast = OnCast   -- (the tests')
