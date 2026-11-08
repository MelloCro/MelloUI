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
--   Preview:Start(scene[, part]) -> true | false[, why]   scene "solo",
--       "party" or "raid" (1.2.4, the user: "We need 3 Options in the Preview
--       drop down, Solo Fight, Party Fight and Raid Fight and the Party/Raid
--       Frames only showing in those circumstances"); part: one part alone (a
--       module's own button: the fake raid, the fake party), nil: the whole
--       scene. A scene playing is stopped first ("restart"). Not in a fight
--       ("combat"), not while Edit Layout shows ("editlayout"). The
--       configurator steps aside while it plays (the Fader shows everything
--       while it is open) and comes back after.
--   Preview:Stop([reason])  the scene ends now: "user" (the default),
--       "combat", "editlayout", "done", "restart"
--   Preview:On() -> the bus's mode playing ("solo", or "party" for the party
--       and the raid scenes: a group's meter, widgets and reminders), or nil
--   Preview:Scene() -> the scene playing, or nil; Preview:Part() -> its part or nil
--   Preview:Plays(part) -> true while a scene plays that part: a module asks
--       before it shows anything. A whole scene plays every part but the
--       group frames: the party ("party": the game's normal party frames'
--       stand-ins, or "groupparty": the party in raid frames, whichever look
--       your party wears) in the Party Fight only, the raid ("raid") in the
--       Raid Fight only. A part alone: that one only
--   Preview:Fighting() -> true between the pull and the kill
--   Preview:ToggleMenu(anchor[, skin])   the Preview list under a button (the
--       configurator's top bar): the three scenes
--   Preview.PARTY  the made-up group (the stand-ins, the meter, the widgets)
--   Preview.PartyHost  set by the addon that holds your party frames
--       (MelloUI_GroupFrames), asked at a party scene's start: Look() ->
--       "groupparty" or "party" (the look your party wears), Top() -> your own
--       frame the stand-ins stand under while it shows (or nil), Gap() -> the
--       room between two members (or nil: the game's). Without it: the game's
--       normal party frames where the game shows them
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
	usage = "/mello preview solo | party | raid | stop",
}
local TEXT = Preview.TEXT

-- The list: the three scenes (1.2.4: the parts alone are gone from it). mode:
-- the bus's (the raid's a group's too: the meter's race, the widgets' healer,
-- the group reminders); module: the module it needs on (the row dimmed while
-- it is off: the Raid Fight's raid frames are Group Frames')
Preview.ITEMS = {
	{ key = "solo", mode = "solo", name = "Solo Fight",
		desc = "Everything while you fight alone." },
	{ key = "party", mode = "party", name = "Party Fight",
		desc = "Everything in a group, with stand-in party frames." },
	{ key = "raid", mode = "party", name = "Raid Fight", module = "GroupFrames",
		desc = "Everything in a raid, with stand-in raid frames." },
}
local ITEMS = Preview.ITEMS
local BY_KEY = {}
for _, item in ipairs(ITEMS) do
	BY_KEY[item.key] = item
end
-- the group frames a whole scene shows, each in its own scene only (Plays)
local FRAMES_OF = { party = "party", groupparty = "party", raid = "raid" }

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

local PHASE = { start = "rest", pull = "fight", kill = "after" }

local S = { mode = nil, scene = nil, part = nil, t0 = 0, idx = 0, fighting = false, configBack = false, heard = false }
local driver, strip, menu   -- made when first needed

function Preview:On()
	return S.mode
end

function Preview:Scene()
	return S.mode and S.scene
end

function Preview:Part()
	return S.part
end

-- the look your party wears (the host's: Group Frames' raid frames, "groupparty"), else the game's normal party
-- frames ("party")
local function PartyLook()
	local host = Preview.PartyHost
	local ok, look = false, nil
	if host and host.Look then
		ok, look = pcall(host.Look)
	end
	return (ok and look == "groupparty") and "groupparty" or "party"
end

function Preview:Plays(part)
	if S.mode == nil then
		return false
	end
	if S.part ~= nil then
		return S.part == part
	end
	local scene = FRAMES_OF[part]
	if scene == nil then
		return true
	end
	return scene == S.scene and (part == "raid" or part == PartyLook())
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
-- replicas of the game's party member frame (MelloUI.ConfigPreview's
-- 'unitframe' kind, its party sample: CP.Build, CP.Values, CP.Update; the
-- user: "not a 1-1 replica on how they actually look ingame"), dressed as
-- the members are at every scene's start (CP.Dress: Unit Frames'
-- M:DressStandIn, their level and name band, the painted skin's dressing
-- while it is on; a look changed between two scenes followed), on your party
-- frames' own slots and scale, in one holder
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
-- scale, then each one its height and the game's spacing lower -- under your
-- own frame while it shows in the first member's place (the host's Top: Group
-- Frames' you as a party frame, the members stacked under it as in a party).

-- the host's answer (Preview.PartyHost), nil without one
local function Host(key)
	local host = Preview.PartyHost
	local fn = host and host[key]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, v = pcall(fn)
	return ok and v or nil
end

-- the gap between two members: the host's (the party's spacing it holds), else the game's own (read, never written)
local function StandGap()
	local gap = Host("Gap")
	if type(gap) == "number" and gap >= 0 then
		return gap
	end
	local pf = rawget(_G, "PartyFrame")
	gap = type(pf) == "table" and pf.spacing
	if type(gap) == "number" and not Secret(gap) and gap >= 0 then
		return gap
	end
	return STAND_GAP
end

local function StandOrigin(w)
	local us = UIParent:GetEffectiveScale()
	-- (your own frame in the first member's place: the members under it, at its side and scale -- the same replica)
	local top = Host("Top")
	if type(top) == "table" then
		local tl, tb, tr = ScreenRect(top)
		if tl and tr > tl then
			local k = (tr - tl) / us / w
			return tl / us, tb / us - StandGap() * k, k
		end
	end
	-- (fr-16: the host's own first member's place -- Group Frames' portrait party; the game's party frame faded elsewhere)
	local host = Preview.PartyHost
	local origin = host and host.Origin
	if type(origin) == "function" then
		local okO, ol, ot, ok = pcall(origin)
		if okO and type(ol) == "number" and type(ot) == "number" and type(ok) == "number" and ok > 0 then
			return ol, ot, ok
		end
	end
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
		CP.Update("unitframe", f, "party", s)   -- (values only: no dress)
	end
end

local function StandShow()
	local CP = MelloUI.ConfigPreview
	if not (CP and CP.Kind and CP.Kind("unitframe") and CP.Build and CP.Values and CP.Dress and CP.Update) then
		return
	end
	if not stand.holder then
		stand.holder = CreateFrame("Frame", "MelloUIPreviewParty", UIParent)
		stand.holder:SetAllPoints(UIParent)
		stand.holder:EnableMouse(false)
	end
	local x, y, k
	for i, member in ipairs(Preview.PARTY) do
		local f = stand.frames[i]
		if not f then
			f = CP.Build("unitframe", stand.holder, "party")
			if not f then
				return
			end
			stand.frames[i] = f
		end
		local s = f.sample or CP.Values("unitframe", "party", i)
		s.first, s.last, s.class = member.name, nil, member.class
		s.max, s.powerMax, s.token = 7000, 6000, "MANA"
		s.health, s.power = s.max, s.powerMax
		f.sample = s
		if not x then
			x, y, k = StandOrigin(f:GetWidth())
		end
		PlaceStand(f, i, x, y, k)
		f:Show()
		-- (dressed as a member at every scene's start: its level and band; the
		-- painted skin's too while on)
		CP.Dress("unitframe", f, "party")
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
		-- (the Party Fight while your party wears the normal party frames, or that part alone: Healer Frames' heals
		-- and glows go on them)
		if S.mode == "party" and Preview:Plays("party") then
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

function Preview:Start(scene, part)
	local item = BY_KEY[scene]
	if not item then
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
	S.mode, S.scene, S.part, S.t0, S.idx, S.fighting = item.mode, scene, part, GetTime(), 0, false
	strip.title:SetText(TEXT.title:format(item.name))
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
	S.mode, S.scene, S.part, S.fighting = nil, nil, nil, false
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
		-- (a feature of its own addon not loaded: named by Core's MelloUI.Features)
		local m, f = MelloUI:GetModule(name), MelloUI.Features and MelloUI.Features[name]
		MelloUI:Announce(TEXT.off:format((m and m.title) or (f and f.title) or name), "info")
		return false
	end
	return Preview:Start(item.key)
end
Preview.Play = Play

--------------------------------------------------------------------------------
-- One animation once (2.1.20, the Animations page; the user, 2026-11-08: "People are confused on where to find and
-- turn off animations they dont want", then the sketch's pick 3A: a Play beside each row). The row's module plays
-- its own sample from its own code -- `fn` (a module's `Plays[word]`, Core/Config.lua's CONFIG.PlayOf) returns true
-- when it played, else it said why (MelloUI:Announce), and how long it lasts; a third true: it plays on the
-- configurator itself (Windows Fade In), which then stays. Meanwhile the configurator steps aside: faded out, not
-- hidden (its page kept, and the Fader goes on showing every element while it is open), a click anywhere on it
-- bringing it back at once; then it fades back in.
--   Preview:Once(fn) -> true when it played
--------------------------------------------------------------------------------

local ONCE = { OUT = 0.15, BACK = 0.2, LAST = 1.6, MAX = 6 }
TEXT.reduced = "Reduce Motion is on (Animations > General): the animations do not play."
TEXT.failed = "That animation could not play: %s"

local function OnceBack()
	ONCE.due = nil
	local cfg, catcher = rawget(_G, "MelloUIConfigFrame"), ONCE.catcher
	if catcher then
		catcher:Hide()
	end
	if cfg then
		MelloUI.Anim:To(cfg, "alpha", 1, ONCE.BACK, "outQuad")
	end
end

-- (one timer at a time: a due before the newest one's is an older play's, played again since)
local function OnceDue()
	if ONCE.due and GetTime() >= ONCE.due - 0.05 then
		OnceBack()
	end
end

local CatcherClick = Shared("OnClick on the configurator while an animation plays", function()
	OnceBack()
end, "script")

local function Aside(cfg, seconds)
	local catcher = ONCE.catcher
	if not catcher then
		catcher = CreateFrame("Button", nil, cfg)
		catcher:SetAllPoints(cfg)
		catcher:SetFrameStrata("FULLSCREEN_DIALOG")
		catcher:RegisterForClicks("AnyUp")
		Perf.SetScript(catcher, "OnClick", CatcherClick)
		ONCE.catcher = catcher
	end
	catcher:Show()
	MelloUI.Anim:To(cfg, "alpha", 0, ONCE.OUT, "inQuad")
	ONCE.due = GetTime() + seconds
	C_Timer.After(seconds, OnceDue)
end

function Preview:Once(fn)
	if type(fn) ~= "function" then
		return false
	end
	if MelloUI.InCombat() then
		MelloUI:Announce(TEXT.inCombat, "info")
		return false
	end
	if MelloUI:EditingLayout() then
		MelloUI:Announce(TEXT.editing, "info")
		return false
	end
	if MelloUI.Anim.reduceMotion then
		MelloUI:Announce(TEXT.reduced, "info")
		return false
	end
	if S.mode then
		self:Stop("restart")
	end
	local ok, played, seconds, stay = pcall(fn)
	if not ok then
		MelloUI:Announce(TEXT.failed:format(tostring(played)), "info")
		return false
	end
	if not played then
		return false
	end
	local cfg = rawget(_G, "MelloUIConfigFrame")
	if not stay and cfg and cfg:IsShown() then
		seconds = type(seconds) == "number" and seconds > 0 and math.min(seconds, ONCE.MAX) or ONCE.LAST
		Aside(cfg, seconds)
	end
	return true
end

--------------------------------------------------------------------------------
-- The list (the configurator's Preview button): a small list in the widget
-- set's tray box under the button, a row per scene -- its name, what it
-- shows. Made on its first open; a row whose module is off is dimmed (its
-- click says so).
--------------------------------------------------------------------------------

local ROW_H, MENU_W, PAD = 42, 320, 6
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

-- the list open now (the configurator's Preview button shows no tooltip over it)
function Preview:MenuShown()
	return menu ~= nil and menu:IsShown()
end

-- the list closed if it is open (true then): the configurator's Escape, one step (Config.lua CONFIG.EscapeStep)
function Preview:CloseMenu()
	if menu and menu:IsShown() then
		menu:Hide()
		return true
	end
	return false
end

-- /mello preview [solo | party | raid | stop]
function Preview.Slash(rest)
	rest = type(rest) == "string" and rest:lower():match("^%s*(%S*)") or ""
	local item = BY_KEY[rest]
	if item then
		Play(item)
	elseif rest == "stop" then
		Preview:Stop("user")
	else
		MelloUI:Print(TEXT.usage)
	end
end
