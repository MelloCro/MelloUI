--------------------------------------------------------------------------------
-- MelloUI - Preview
--
-- How the interface behaves, played as a short scene (0.17.0; the user,
-- 2026-10-01: "a 'Preview while solo' and a 'Preview in Party' button ... it
-- simulates how the UI elements behave while im solo fighting mobs, the
-- widgets in and out of combat, while Preview in party simulates the Party
-- Frames, damage meter, etc", then "preview opens the preview menu and i can
-- click different stuff to check it out individually"; docs/plans/preview.md).
-- Out of combat only. It never fakes a game event and never touches a game
-- frame: it fires the bus topic 'preview' with the scene's beats, and each
-- module that takes part shows its own sample state from its own code (its
-- own samples where it has them), then puts its own state back at the stop.
--
--   local Preview = MelloUI.Preview
--   Preview:Start(mode[, part]) -> true | false[, why]   mode "solo" or
--       "party"; part: one part alone (Preview.PARTS), nil: all of them. A
--       scene playing is stopped first ("restart"). Not in a fight
--       ("combat"), not while Edit Layout shows ("editlayout"). The
--       configurator steps aside while it plays (the Fader shows everything
--       while it is open) and comes back after.
--   Preview:Stop([reason])  the scene ends now: "user" (the default),
--       "combat", "editlayout", "done", "restart"
--   Preview:On() -> the mode playing, or nil; Preview:Part() -> its part or nil
--   Preview:Plays(part) -> true while a scene plays that part (all of them,
--       or that one alone): a module asks before it shows anything
--   Preview:Fighting() -> true between the pull and the kill
--   Preview:ToggleMenu(anchor[, skin])   the Preview list under a button (the
--       configurator's top bar): the two whole scenes, then each part alone
--   Preview.BEATS  the scene: { t = seconds, beat, n } in order
--   Preview.PARTY  the made-up group (the stand-ins, the meter, the widgets)
-- Bus 'preview' (beat, mode, n):
--   "start"  the scene begins: sample rows and reminders up, the stand-ins
--   "pull"   a pretend fight starts: what reacts to combat reacts
--   "hit"    n = 1 .. T.HITS, one exchange every T.HIT_EVERY seconds
--   "kill"   the pretend fight ends: gains, the summary, the fades back
--   "stop"   n = the reason: everything put back (asked of every module,
--            whatever part played: each undoes only what it did). On
--            "combat" a module that pretended a fight leaves its combat
--            state alone: the real fight has begun (PLAYER_REGEN_DISABLED,
--            before the lockdown)
--
-- While it plays, a strip at the top of the screen: "Preview: Solo Fight",
-- the phase and Stop. Nothing at login: the strip, the list and the one
-- frame are made when first needed; the frame's OnUpdate runs only while a
-- scene plays.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Preview")
local Shared = Perf.Shared
local W = MelloUI.Widgets
local Secret = MelloUI.Safe.IsSecret
local ScreenRect = MelloUI.Safe.ScreenRect

local Preview = {}
MelloUI.Preview = Preview

local OWNER = "Preview"   -- the bus owner
local T = { PULL = 4, HIT0 = 4.6, HIT_EVERY = 0.9, HITS = 12, KILL = 16, DONE = 26 }
Preview.T = T

Preview.TEXT = {
	title = "Preview: %s",
	rest = "Resting",
	fight = "In a fight",
	after = "After the fight",
	stop = "Stop",
	stopTip = "End the preview now. Everything goes back as it was.",
	combat = "Preview stopped: you are in a fight.",
	inCombat = "The preview plays out of combat only.",
	editing = "Close Edit Layout first: the preview plays without it.",
	off = "%s is switched off.",
	alone = "One at a time",
	usage = "/mello preview solo | party | %s | stop",
}
local TEXT = Preview.TEXT

-- The list: the two whole scenes, then each part alone (its scene's mode:
-- party where it has something to show in a group). module: the module it
-- needs on (the row dimmed while it is off)
Preview.ITEMS = {
	{ key = "solo", mode = "solo", name = "Solo Fight",
		desc = "Everything while you fight alone." },
	{ key = "party", mode = "party", name = "Party Fight",
		desc = "Everything in a group, with stand-in party frames." },
	{ key = "fader", part = "fader", mode = "solo", name = "Fader", module = "Fader",
		desc = "What you set to fade: away at rest, back in a fight." },
	{ key = "reminders", part = "reminders", mode = "party", name = "Reminders", module = "Widgets",
		desc = "The round reminders by your portrait." },
	{ key = "widgets", part = "widgets", mode = "party", name = "Widget Column", module = "Widgets",
		desc = "Quest items, a healer drinking, a loot roll." },
	{ key = "partyframes", part = "party", mode = "party", name = "Party Frames",
		desc = "Stand-ins where your party frames sit, hurt and healed." },
	-- (0.19.0; the user, 2026-10-04: "how can i simulate and see how it works ingame?")
	{ key = "healer", part = "healer", mode = "party", name = "Healer Frames", module = "HealerFrames",
		desc = "Heals coming in and debuffs to remove: on the stand-in party and your own frame." },
	{ key = "meter", part = "meter", mode = "party", name = "Damage Meter", module = "Meter",
		desc = "Your numbers, the group's race bar, the summary." },
	{ key = "combattext", part = "combattext", mode = "solo", name = "Combat Text", module = "CombatText",
		desc = "The text over you, and your damage at your target." },
	{ key = "gains", part = "gains", mode = "solo", name = "Gains", module = "Gains",
		desc = "What a kill brings: experience, loot and money." },
}
local ITEMS = Preview.ITEMS
local BY_KEY = {}
for _, item in ipairs(ITEMS) do
	BY_KEY[item.key] = item
end

-- the made-up group, one list for every part that shows it (the stand-ins,
-- the meter, the widgets): the meter's own sample members (/mello meter test)
Preview.PARTY = {
	{ name = "Fellaria", class = "MAGE", dps = 52, hps = 0 },
	{ name = "Shadeleaf", class = "HUNTER", dps = 46, hps = 0 },
	{ name = "Tarnok", class = "SHAMAN", dps = 33, hps = 3 },
	{ name = "Brightwood", class = "PRIEST", dps = 9, hps = 65, healer = true },
}

-- the scene, in order
local BEATS = {}
local function Beat(t, beat, n)
	BEATS[#BEATS + 1] = { t = t, beat = beat, n = n }
end
Beat(0, "start")
Beat(T.PULL, "pull")
for i = 1, T.HITS do
	Beat(T.HIT0 + (i - 1) * T.HIT_EVERY, "hit", i)
end
Beat(T.KILL, "kill")
Beat(T.DONE, "stop", "done")
Preview.BEATS = BEATS

local PHASE = { start = "rest", pull = "fight", kill = "after" }

local S = { mode = nil, part = nil, t0 = 0, idx = 0, fighting = false, configBack = false, heard = false }
local driver, strip, menu   -- made when first needed

function Preview:On()
	return S.mode
end

function Preview:Part()
	return S.part
end

function Preview:Plays(part)
	return S.mode ~= nil and (S.part == nil or S.part == part)
end

function Preview:Fighting()
	return S.mode ~= nil and S.fighting
end

local function Phase(key)
	if strip and key then
		strip.phase:SetText(TEXT[key])
	end
end

--------------------------------------------------------------------------------
-- Party Frames' stand-ins: the game shows its party frames only in a real
-- group, and an addon may not show them -- so the made-up group is drawn as
-- replicas of the game's party member frame (MelloUI.ConfigPreview: MakeParty,
-- PaintParty; the user: "not a 1-1 replica on how they actually look ingame"),
-- dressed by the unit frame skin as the members are (UnitFramePanel:
-- DressStandIn), on your party frames' own slots and scale, in one holder
-- (MelloUIPreviewParty) the Fader fades with the party frames
-- (Modules/Fader.lua). Their health falls on the hits and is healed back by
-- the end, the healer's mana goes down. Made with the first party scene.
--   Preview:StandIn(i) -> the i-th stand-in while a scene shows it, or nil
--------------------------------------------------------------------------------

local stand = { holder = nil, frames = {}, on = false }
local HURT = { 0.25, 0.15, 0.55, 0.1 }   -- the most each member loses (Tarnok in melee)
local WORST = 8                          -- the worst after the 8th hit, healed by the last
local STAND_GAP = 10                     -- the game's gap between two members (26 with their pets shown)

-- Where the members stand: the game stacks the SHOWN member frames down from
-- the party frame's top-left (PartyFrame, a vertical layout frame: each under
-- the one before, its `spacing` apart); the hidden ones -- all of them
-- without a group -- stay on that top-left, one on the other (the user's
-- test, 2026-10-01: the four stand-ins drawn on one spot, their names on
-- each other). So: the first member's top-left (or the party frame's) at its
-- scale, then each one its height and the game's spacing lower.
local function StandOrigin(w)
	local us = UIParent:GetEffectiveScale()
	local pf = rawget(_G, "PartyFrame")
	local mf = type(pf) == "table" and pf.MemberFrame1
	local l, _, r, t = nil, nil, nil, nil
	if type(mf) == "table" then
		l, _, r, t = ScreenRect(mf)
	end
	if l and r > l then
		-- (the member frame at its own scale, Edit Mode's Size)
		return l / us, t / us, (r - l) / us / w
	end
	local okS, es = pcall(function() return pf:GetEffectiveScale() end)
	local k = (okS and type(es) == "number" and not Secret(es) and es > 0) and es / us or 1
	local pl, _, _, pt = ScreenRect(pf)
	if pl then
		return pl / us, pt / us, k
	end
	return 20, UIParent:GetHeight() * 0.72, k
end

-- the game's own gap between two members (read, never written)
local function StandGap()
	local pf = rawget(_G, "PartyFrame")
	local gap = type(pf) == "table" and pf.spacing
	if type(gap) == "number" and not Secret(gap) and gap >= 0 then
		return gap
	end
	return STAND_GAP
end

local function PlaceStand(f, i, x, y, k)
	local _, h = f:GetSize()
	y = y - (i - 1) * (h + StandGap()) * k
	f:SetScale(k)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / k, y / k)
end

-- the scene's health and mana after hit n (0: before the fight)
local function StandValues(n, healerMana)
	local CP = MelloUI.ConfigPreview
	local w = n <= 0 and 0 or (n <= WORST and n / WORST or math.max(0, (T.HITS - n) / (T.HITS - WORST)))
	for i, f in ipairs(stand.frames) do
		local s = f.sample
		s.health = math.floor(s.max * (1 - (HURT[i] or 0.2) * w) + 0.5)
		s.fraction = s.health / s.max
		if Preview.PARTY[i] and Preview.PARTY[i].healer then
			s.power = math.floor(s.powerMax * healerMana + 0.5)
		end
		CP.PaintParty(f, s)
	end
end

local function StandShow()
	local CP = MelloUI.ConfigPreview
	if not (CP and CP.MakeParty and CP.PaintParty) then
		return
	end
	if not stand.holder then
		stand.holder = CreateFrame("Frame", "MelloUIPreviewParty", UIParent)
		stand.holder:SetAllPoints(UIParent)
		stand.holder:EnableMouse(false)
	end
	local ufp = MelloUI:GetModule("UnitFramePanel")
	local x, y, k
	for i, member in ipairs(Preview.PARTY) do
		local f = stand.frames[i]
		if not f then
			f = CP.MakeParty(stand.holder)
			stand.frames[i] = f
		end
		local s = f.sample or CP.PartySample()
		s.first, s.last, s.class = member.name, nil, member.class
		s.max, s.powerMax, s.token = 7000, 6000, "MANA"
		s.health, s.power = s.max, s.powerMax
		f.sample = s
		if not x then
			x, y, k = StandOrigin(f:GetWidth())
		end
		PlaceStand(f, i, x, y, k)
		f:Show()
		-- (dressed as a member while the unit frame skin is on)
		if ufp and ufp.DressStandIn then
			ufp:DressStandIn(f)
		end
	end
	stand.on = true
	stand.holder:Show()
	StandValues(0, 0.6)   -- (the healer drinking before the pull)
	if MelloUI.Fader and MelloUI.Fader.Join then
		MelloUI.Fader:Join("party", stand.holder)
	end
end

local function StandHide()
	stand.on = false
	if stand.holder then
		stand.holder:Hide()
	end
end

function Preview:StandIn(i)
	return stand.on and stand.frames[i] or nil
end

-- the stand-ins' part of a beat (before the bus hears it: the meter hangs
-- its party numbers on them)
local function Stand(b)
	if b.beat == "start" then
		-- (the healer part shows its heals and glows on them too)
		if S.mode == "party" and (Preview:Plays("party") or Preview:Plays("healer")) then
			StandShow()
		end
	elseif not stand.on then
		return
	elseif b.beat == "pull" then
		StandValues(0, 0.95)
	elseif b.beat == "hit" then
		StandValues(b.n, 0.95 - 0.03 * b.n)
	end
end

local function FireBeat(b)
	if b.beat == "pull" then
		S.fighting = true
	elseif b.beat == "kill" then
		S.fighting = false
	end
	Phase(PHASE[b.beat])
	Stand(b)
	MelloUI:Fire("preview", b.beat, S.mode, b.n)
end

-- the beats that are due, in order (a slow frame fires several)
local Tick = Shared("OnUpdate on the preview", function()
	while S.mode do
		local b = BEATS[S.idx + 1]
		if not (b and b.t <= GetTime() - S.t0) then
			return
		end
		S.idx = S.idx + 1
		if b.beat == "stop" then
			Preview:Stop(b.n)
			return
		end
		FireBeat(b)
	end
end, "script")

local OnEvent = Shared("OnEvent on the preview", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		Preview:Stop("combat")
	end
end, "script")

local StopClick = Shared("OnClick on the preview's Stop", function()
	Preview:Stop("user")
end, "script")

local function OnEditLayout(showing)
	if showing and S.mode then
		Preview:Stop("editlayout")
	end
end

local function Make()
	if driver then
		return
	end
	driver = CreateFrame("Frame")
	Perf.SetScript(driver, "OnEvent", OnEvent)
	strip = CreateFrame("Frame", "MelloUIPreviewStrip", UIParent)
	W.Panel(strip, { on = true, alpha = 0.92 })
	strip:SetSize(380, 34)
	strip:SetPoint("TOP", UIParent, "TOP", 0, -110)
	strip:SetFrameStrata("HIGH")
	strip:EnableMouse(true)
	strip.title = W.Text(strip, "GameFontNormal", nil, "selectedTrim")
	strip.title:SetPoint("LEFT", strip, "LEFT", 12, 0)
	strip.phase = W.Text(strip, "GameFontHighlight", nil, "text")
	strip.phase:SetPoint("LEFT", strip.title, "RIGHT", 10, 0)
	strip.stop = W.Button(strip, TEXT.stop, 70, nil, { onClick = StopClick })
	strip.stop:SetPoint("RIGHT", strip, "RIGHT", -6, 0)
	strip.stop.melloTipTitle, strip.stop.melloTipBody = TEXT.stop, TEXT.stopTip
	strip:Hide()
end

-- the item a mode and a part play (the strip's name)
local function ItemOf(mode, part)
	for _, item in ipairs(ITEMS) do
		if item.part == part and (part ~= nil or item.mode == mode) then
			return item
		end
	end
	return nil
end

function Preview:Start(mode, part)
	if mode ~= "solo" and mode ~= "party" then
		return false, "mode"
	end
	if MelloUI.InCombat() then
		MelloUI:Announce(TEXT.inCombat, "info")
		return false, "combat"
	end
	if MelloUI:EditingLayout() then
		MelloUI:Announce(TEXT.editing, "info")
		return false, "editlayout"
	end
	if S.mode then
		self:Stop("restart")
	end
	Make()
	if not S.heard then
		S.heard = true
		MelloUI:On("editlayout", OnEditLayout, OWNER)
	end
	if menu then
		menu:Hide()
	end
	-- the configurator steps aside (the Fader shows everything while it is open)
	local cfg = rawget(_G, "MelloUIConfigFrame")   -- (made on its first open)
	S.configBack = (cfg and cfg:IsShown()) and true or false
	if S.configBack then
		cfg:Hide()
	end
	S.mode, S.part, S.t0, S.idx, S.fighting = mode, part, GetTime(), 0, false
	local item = ItemOf(mode, part)
	strip.title:SetText(TEXT.title:format(item and item.name or mode))
	Phase("rest")
	strip:Show()
	driver:RegisterEvent("PLAYER_REGEN_DISABLED")
	Perf.SetScript(driver, "OnUpdate", Tick)
	Tick()   -- (the start beat at once)
	return true
end

function Preview:Stop(reason)
	local mode = S.mode
	if not mode then
		return
	end
	reason = reason or "user"
	S.mode, S.part, S.fighting = nil, nil, false
	Perf.SetScript(driver, "OnUpdate", nil)
	driver:UnregisterEvent("PLAYER_REGEN_DISABLED")
	strip:Hide()
	StandHide()
	MelloUI:Fire("preview", "stop", mode, reason)
	if reason == "combat" then
		MelloUI:Announce(TEXT.combat, "info")
	end
	local back = S.configBack
	S.configBack = false
	-- (the configurator back after a scene that ended by itself or by Stop)
	if back and (reason == "done" or reason == "user") then
		MelloUI:OpenConfig()
	end
end

-- an item played (the list's click, the slash command): its module on, or it says so
local function Play(item)
	local name = item.module
	if name and not MelloUI:IsModuleEnabled(name) then
		local m = MelloUI:GetModule(name)
		MelloUI:Announce(TEXT.off:format(m and m.title or name), "info")
		return false
	end
	return Preview:Start(item.mode, item.part)
end
Preview.Play = Play

--------------------------------------------------------------------------------
-- The list (the configurator's Preview button): a small list in the widget
-- set's tray box under the button, a row per item -- its name, what it shows
-- -- a line between the two whole scenes and the parts. Made on its first
-- open; a row whose module is off is dimmed (its click says so).
--------------------------------------------------------------------------------

local ROW_H, MENU_W, PAD, GAP = 42, 320, 6, 10
local DIM = 0.45

local ItemClick = Shared("OnClick on a preview list row", function(row)
	Play(row.item)
end, "script")

local function MakeMenu(parent, skin)
	menu = W.TrayBox(parent, { name = "MelloUIPreviewMenu", strata = "DIALOG" })
	menu:EnableMouse(true)
	menu.rows = {}
	local y = -PAD
	for i, item in ipairs(ITEMS) do
		if i == 3 then
			-- (the parts, one at a time, under a line)
			local line = W.Solid(menu, "ARTWORK", "border", 1)
			line:SetHeight(1)
			line:SetPoint("TOPLEFT", menu, "TOPLEFT", PAD, y - GAP / 2)
			line:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -PAD, y - GAP / 2)
			local head = W.Text(menu, "GameFontNormal", TEXT.alone, "selectedTrim")
			head:SetPoint("TOPLEFT", menu, "TOPLEFT", PAD + 8, y - GAP)
			y = y - GAP - 20
		end
		local row = CreateFrame("Button", nil, menu)
		row:SetHeight(ROW_H)
		row:SetPoint("TOPLEFT", menu, "TOPLEFT", PAD, y)
		row:SetPoint("RIGHT", menu, "RIGHT", -PAD, 0)
		W.RowPlate(row, { look = "plate", skin = skin })
		row.name = W.Text(row, "GameFontNormal", item.name, "selectedTrim")
		row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -5)
		row.desc = W.Text(row, "GameFontHighlight", item.desc, "text")
		row.desc:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
		row.desc:SetPoint("RIGHT", row, "RIGHT", -8, 0)
		row.desc:SetWordWrap(false)
		row.item = item
		Perf.SetScript(row, "OnClick", ItemClick)
		menu.rows[i] = row
		y = y - ROW_H
	end
	menu:SetSize(MENU_W, -y + PAD)
	if skin and skin.Kit then
		skin:Kit(function(Kit)
			menu:SetKit(Kit)
		end)
	end
	menu:Hide()
end

-- the rows' state on every open (a module switched since)
local function MenuRefresh()
	for _, row in ipairs(menu.rows) do
		local name = row.item.module
		row:SetAlpha((name and not MelloUI:IsModuleEnabled(name)) and DIM or 1)
	end
end

function Preview:ToggleMenu(anchor, skin)
	if not anchor then
		return
	end
	if not menu then
		MakeMenu(anchor:GetParent() or UIParent, skin)
	end
	if menu:IsShown() then
		menu:Hide()
		return
	end
	MenuRefresh()
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
	menu:Show()
end

function Preview:MenuShown()
	return menu ~= nil and menu:IsShown()
end

-- /mello preview [solo | party | <a part> | stop]: a part's key from the list
-- (fader, reminders, widgets, partyframes, meter, combattext, gains)
function Preview.Slash(rest)
	rest = type(rest) == "string" and rest:lower():match("^%s*(%S*)") or ""
	local item = BY_KEY[rest]
	if item then
		Play(item)
	elseif rest == "stop" then
		Preview:Stop("user")
	else
		local keys = {}
		for i = 3, #ITEMS do
			keys[#keys + 1] = ITEMS[i].key
		end
		MelloUI:Print(TEXT.usage:format(table.concat(keys, " | ")))
	end
end
