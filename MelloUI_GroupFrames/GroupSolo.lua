--------------------------------------------------------------------------------
-- MelloUI - Group Frames: the portrait party -- you and your party as normal party frames of ours
--
-- (the user, 2026-10-09: "when choosing in a party "party frames" if im not in a raid group, the party frames should
-- look like normal party frames even when im solo"; 2026-10-31, fr-16: "i dont want, under any circumstance, when
-- using our custom Party and Raid Frames, for the default blizzard Party/Raid Frames to appear at all")
--
-- While In A Party is Party Frames, every frame of the party is ours: the game's party member frame as the replica
-- ConfigPreview's 'unitframe' kind builds it as its party sample (CP.Build, painted with CP.Values / CP.Paint; the
-- game's template's keys and geometry, PartyFrameTemplates.xml), built on a secure unit button of ours -- a click
-- targets, a right click opens the unit's menu -- dressed as a member (Unit Frames' M:DressStandIn, with the painted
-- skin's dressing while it is on), its bars MelloUI's own StatusBars in the look the settings give the members (Bar
-- Textures), filled with the unit's health and power as the game hands them (a secret value goes to the bar as it
-- is, never read), its portrait (or Class Icons' medallion), its name, and the members' aura row (the game's aura
-- container: up to four debuffs, as the members show them). Two kinds:
--   you        "player" (Show Yourself While Solo / In Your Party), shown by its own state driver
--   members    party1 .. party4, each shown by the game's unit watch (the unit there: in a fight too), all of them in
--              one holder shown by a state driver while you are in a party and not in a raid; each with the game's
--              own member parts (its PVP badge, its offline plug, its status glow, the ready check, the "not here"
--              eye, its portrait's low-health beat) and its pet's frame under it (partypet1 .. 4, while the game
--              shows party pets)
-- They stand in the party container (Edit Layout's "Party Frames", GroupHeaders.lua), stacked from its corner (its
-- top right while Flip Horizontally mirrors the portraits), you on top, one slot each at the game's own room (10, 26
-- with party pets), at Edit Mode's party size times PORTRAIT_BASE. The slots never move in a fight: the game keeps
-- party1 .. partyN in a row, so a roster change only shows or hides a slot (the unit watch). Nothing is laid in a
-- fight; what a setting changes in one waits for its end. They are hosts as the game's members were: the indicators
-- (kind "party"), the Designer's party parts, Healer Frames' heals and debuff glow, and Heal Flight and Frame Effects
-- (Headers:Hosts / HostOf: kind "party", its portrait and ring), the damage meter's tab (Modules/Meter.lua).
-- Made the first time they are wanted, never before; their events only while wanted.
--   Solo:Update()             wanted or not: made, placed and driven, or put away (out of a fight)
--   Solo:Repaint()            their look again (a setting of the looks)
--   Solo:Shown() -> frame     your frame while it shows, else nil
--   Solo:Each(fn)             fn(frame, unit) for every frame made (you first), shown or not
--   Solo:Member(i) -> frame   party i's frame (nil until made)
--   Solo:Of(unit) -> frame    the frame of `unit` while it shows, else nil
--   Solo.Above() -> bool      your place kept at the top of your party (the settings alone: GroupHeaders.lua SelfRoom)
--   Solo.Scale() -> number    the frames' scale in the party container
--   Solo.PartyOn() -> bool    the members wanted (Party Frames the choice, the module on)
--   Solo.frame                your frame (nil until made)
--   Solo.aside                true while the Preview's made-up raid shows (GroupHeaders.lua's Aside): you away
--   Solo.Range(f)             a member's fade out of range again (GroupHeaders: a fight's start or end)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_GroupFrames (solo)")
local Shared = Perf.Shared
local Text = MelloUI.Safe.Text
local Num = MelloUI.Safe.Number
local IsSecret = MelloUI.Safe.IsSecret
-- (the game's unit watch: a secure frame shown while its unit is there -- SecureStateDriver.lua)
local function Watch(f)
	local fn = rawget(_G, "RegisterUnitWatch")
	if fn then
		fn(f)
	end
end
local function Unwatch(f)
	local fn = rawget(_G, "UnregisterUnitWatch")
	if fn then
		fn(f)
	end
end
local RD = ns.RD
local Looks = ns.Looks
local Button = ns.Button

local Solo = { frame = nil, driven = false, rule = nil, listening = false, aside = false, members = {},
	holder = nil, partyDriven = false }
ns.Solo = Solo

local UNIT = "player"
local MEMBERS = 4
-- (1.2.4, the user's retail test, 2026-10-27: party portraits "set on EditMode to 100%, and on the Edit Layout 100%
-- and they are miniature" -- their pick, bigger by default) the portraits at Edit Mode's own party size times Edit
-- Layout's (the party container's scale) times this: about the player frame's height at 100% and 100%
Solo.PORTRAIT_BASE = 1.4
-- when you show: solo (Show Yourself While Solo), in a party (Show Yourself In Your Party), or both; never in a raid
-- (Group Frames' raid frames show there)
local RULES = { solo = "[group] hide; show", party = "[group:raid] hide; [group] show; hide",
	both = "[group:raid] hide; show" }
-- the members' holder: in a party, never in a raid (the game's ShouldShowPartyFrames)
local PARTY_RULE = "[group:raid] hide; [group] show; hide"
-- the members' aura row (PartyAuraFrameTemplate: 15 x 15, 2 apart, its
-- border the debuff overlay's; MAX_PARTY_DEBUFFS four; the row at 48,-43)
local AURA = { size = 15, gap = 2, max = 4, x = 48, y = -43 }
-- the game's leader and guide icons (PartyMemberOverlay's)
local GROUP_ICONS = { LeaderIcon = "UI-HUD-UnitFrame-Player-Group-LeaderIcon",
	GuideIcon = "UI-HUD-UnitFrame-Player-Group-GuideIcon" }
-- (fr-16) the game's own member parts (PartyFrameTemplates.xml, PartyMemberFrame.lua): the status glow, the PVP
-- badge, the offline plug, the "not here" eye and its kinds, the ready check, the pet's frame
local PART = {
	status = "UI-HUD-UnitFrame-Party-PortraitOn-Status",
	plug = "Interface\\CharacterFrame\\Disconnect-Icon",   -- (the game's offline plug)
	ring = "Interface\\Common\\RingBorder",                -- (the game's "not here" ring)
	phase = "Interface\\TargetingFrame\\UI-PhasingIcon",   -- (the game's phased eye)
	phaseCoords = { 0.15625, 0.84375, 0.15625, 0.84375 },
	other = "groupfinder-eye-single",
	summon = { "Raid-Icon-SummonPending", "Raid-Icon-SummonAccepted", "Raid-Icon-SummonDeclined" },
	pvp = { ffa = "ui-hud-unitframe-player-pvp-ffaicon", Horde = "ui-hud-unitframe-player-pvp-hordeicon",
		Alliance = "ui-hud-unitframe-player-pvp-allianceicon" },
	away = 0.6,   -- (the game's alpha for a member phased or in another group)
	pet = { w = 64, h = 23, x = 23, y = -43, art = "ui-hud-unitframe-party-portraiton",
		health = "ui-hud-unitframe-party-portraiton-bar-health" },
}
-- (the game's portrait tints, PartyMemberFrameMixin:PartyMemberHealthCheck: dead, a ghost, above none and at a fifth
-- of the health or under, else none; its low-health beat there, UpdateMemberHealth: the portrait's alpha from 127/255
-- to 1 and back, straight, half a second each way)
local TINT = { dead = { 0.35, 0.35, 0.35 }, ghost = { 0.2, 0.2, 0.75 }, low = { 1, 0, 0 }, none = { 1, 1, 1 },
	at = 0.2, beat = { from = 127 / 255, to = 1, half = 0.5 } }
-- the modules whose settings change its look
local LOOKS = { BarTextures = true, UnitFrames = true, ClassIcons = true, UnitFramePanel = true, HealerFrames = true }

local function Later(fn, key)
	local K = MelloUI.Kit
	if InCombatLockdown() and K and K.WhenOutOfCombat then
		K:WhenOutOfCombat(fn, key)
	elseif not InCombatLockdown() then
		fn()
	end
end

local function Call(obj, method, ...)
	local fn = obj and obj[method]
	if type(fn) ~= "function" then
		return false
	end
	return (pcall(fn, obj, ...))
end

-- a call's first answer, plain (nil: refused or secret)
local function Ask(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, v = pcall(fn, ...)
	if ok and not IsSecret(v) then
		return v
	end
	return nil
end

local function Enum2(group, name)
	local E = rawget(_G, "Enum")
	local t = type(E) == "table" and E[group]
	return type(t) == "table" and t[name] or nil
end

-- the members wanted: the module on, Party Frames the choice in a party
function Solo.PartyOn()
	local H = ns.Headers
	return (H and H.S and H.S.on and RD.DB().partyStyle == "party") and true or false
end

-- you wanted: the members' choice, and you shown solo or in your party
local function Wanted()
	local db = RD.DB()
	return (Solo.PartyOn() and (db.solo or db.showPlayer)) and true or false
end

local function Rule()
	local db = RD.DB()
	return RULES[db.solo and (db.showPlayer and "both" or "solo") or "party"]
end

-- (fr-15) your place over the members kept: by the settings alone, never by the group's state, so the members
-- already stand one place lower when you join a party in a fight (nothing may move then)
function Solo.Above()
	return (Wanted() and RD.DB().showPlayer and not Solo.aside) and true or false
end

--------------------------------------------------------------------------------
-- The aura row: the game's aura container, its frames dressed as the members'
--------------------------------------------------------------------------------

local function DressAura(b)
	MelloUI.Units.DressAura(b)
	-- (retail: a click goes through to the frame -- click casting -- the hover still its tooltip)
	Looks.ClickThrough(b)
end

-- an aura row dressed as the members' (the game's aura container: up to four,
-- 2 apart), `filter`'s auras of `unit`, sorted by `sort` (nil: the game's own
-- order), placed by the SetPoint arguments `...` (before its group: the game
-- holds a container with aura groups to its own layout)
function Solo.AuraRow(parent, filter, unit, sort, ...)
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
	if not ok or type(c) ~= "table" or type(c.AddAuraGroup) ~= "function" then
		return nil
	end
	c:SetPoint(...)
	c:SetSize(AURA.size, AURA.size)
	local opts = { maxFrameCount = AURA.max, initializeFrame = DressAura, sortMethod = sort,
		layout = { elementSpacing = AURA.gap, elementWidth = AURA.size, elementHeight = AURA.size } }
	if not Call(c, "AddAuraGroup", "auras", filter, opts) then
		return nil
	end
	Call(c, "SetUnit", unit)
	return c
end

-- a frame's aura row at the members' place (its parent `f`, its unit's; a pet's at its own place, `x`, `y`)
local function MakeAuras(f, unit, x, y)
	-- (the members show their buffs instead where the game says so)
	local buffs = rawget(_G, "PARTY_FRAME_SHOW_BUFFS") and true or false
	local sort = rawget(_G, "AuraContainerSortMethod")
	return Solo.AuraRow(f, buffs and "HELPFUL" or "HARMFUL", unit,
		(not buffs and type(sort) == "table") and sort.UnitFrameDebuff or nil, "TOPLEFT", f, "TOPLEFT", x or AURA.x,
		y or AURA.y)
end

-- (retail, never shipped: the user, 2026-10-24, "this mouseover container that shows the buffs instead of just
-- showing them under it, which makes it a problem to click cast heal") a row of a frame's buffs under it, right after
-- its debuff row -- in it, so the Designer's Buffs & Debuffs part moves, sizes and hides both: our frames' debuff row
-- is a game aura container -- nothing may be anchored to it -- so their buffs are a second group in it, flowing after
-- the debuffs on their line (the container lays its groups in turn, groupSpacing apart). Made out of a fight
local ownBuffs = setmetatable({}, { __mode = "k" })   -- [our frame] = its debuff container, the buffs in it
local function OwnBuffs(f, unit)
	local c = rawget(f, "AuraFrameContainer")
	if ownBuffs[f] or InCombatLockdown() or not (type(c) == "table" and type(c.AddAuraGroup) == "function") then
		return ownBuffs[f]
	end
	local opts = { maxFrameCount = AURA.max, initializeFrame = DressAura, layout = { elementSpacing = AURA.gap,
		elementWidth = AURA.size, elementHeight = AURA.size, groupSpacing = AURA.gap } }
	if not Call(c, "AddAuraGroup", "buffs", "HELPFUL", opts) then
		return nil
	end
	Call(c, "SetUnit", unit or UNIT)
	ownBuffs[f] = c
	return c
end

function Solo.BuffRow(f, unit)
	if not RD.Retail() or type(f) ~= "table" then
		return nil
	end
	return OwnBuffs(f, unit)
end
Solo.ownBuffs = ownBuffs   -- (the tests', the party dump's)

--------------------------------------------------------------------------------
-- Painting
--------------------------------------------------------------------------------

local function Module(name)
	local m = MelloUI:GetModule(name)
	return (m and m.isEnabled and m.db) and m or nil
end

-- the health bar's colour as Bar Textures gives the members' (nil: the one
-- the look put on stays -- the art's own, or its green)
local function Colour(f)
	local bt = Module("BarTextures")
	if not (bt and bt.LiveHealthColor) then
		return
	end
	local hb = f.HealthBarContainer.HealthBar
	local ok, r, g, b = pcall(bt.LiveHealthColor, hb)
	if ok and r ~= nil then
		pcall(hb.SetStatusBarColor, hb, r, g, b)
	end
end

local function ByHealth()
	local bt = Module("BarTextures")
	return bt and bt.db.healthColor == "health" or false
end

-- connected (the player always; a member as the game says -- a refused or secret answer counts as connected)
local function Connected(unit)
	if unit == UNIT then
		return true
	end
	return Ask(UnitIsConnected, unit) ~= false
end

-- (fr-16) the portrait's tint as the game gives it (PartyMemberHealthCheck): grey while dead, blue as a ghost, red
-- above none and at a fifth of the health or under, else none; and its low-health beat in that fifth
-- (UpdateMemberHealth). Read through colour curves of the client's at the unit's own share (UnitHealthPercent: the
-- secret share never read here): the portrait's at alpha 0 in that fifth, its twin's at 1 there and 0 elsewhere -- the
-- twin the same picture over it, beating (Beat) -- so the twin stands in for the portrait while the share is low.
-- Nothing compared, nothing run while the share stays
local tint = { curves = nil, made = false }
local function TintCurves()
	if tint.made then
		return tint.curves
	end
	tint.made = true
	local CU = rawget(_G, "C_CurveUtil")
	if type(CU) ~= "table" or type(CU.CreateColorCurve) ~= "function" or not rawget(_G, "CreateColor") then
		return nil
	end
	-- (a curve whose alpha is `low` in that fifth, the other way elsewhere)
	local function Make(low)
		local made = CU.CreateColorCurve()
		local E = rawget(_G, "Enum")
		if E and E.LuaCurveType then
			made:SetType(E.LuaCurveType.Step)
		end
		local red, none = TINT.low, TINT.none
		made:AddPoint(0, CreateColor(none[1], none[2], none[3], 1 - low))
		made:AddPoint(1e-6, CreateColor(red[1], red[2], red[3], low))
		made:AddPoint(TINT.at + 1e-6, CreateColor(none[1], none[2], none[3], 1 - low))
		return made
	end
	local ok, portrait, twin = pcall(function()
		return Make(0), Make(1)
	end)
	tint.curves = ok and { portrait = portrait, twin = twin } or nil
	return tint.curves
end

-- the portrait and its twin in one colour, each at its alpha (secret ones handed on as they are)
local function TintBoth(f, r, g, b, a, twinAlpha)
	pcall(f.Portrait.SetVertexColor, f.Portrait, r, g, b, a)
	local twin = f.PortraitTwin
	if twin then
		pcall(twin.SetVertexColor, twin, r, g, b, twinAlpha)
	end
end

local function Tint(f)
	local unit = f.unit
	if unit == UNIT then
		return
	end
	local c = Ask(UnitIsDead, unit) == true and TINT.dead or (Ask(UnitIsGhost, unit) == true and TINT.ghost) or nil
	-- (dead or a ghost: its bar at none -- MelloUI.Units.Value; offline: the game's bar at its most -- UpdateOnlineStatus:
	-- neither red nor beating)
	if c or not Connected(unit) then
		c = c or TINT.none
		TintBoth(f, c[1], c[2], c[3], 1, 0)
		return
	end
	local curves = TintCurves()
	local okP, col, okT, twin = false, nil, false, nil
	if curves and rawget(_G, "UnitHealthPercent") then
		okP, col = pcall(UnitHealthPercent, unit, false, curves.portrait)
		okT, twin = pcall(UnitHealthPercent, unit, false, curves.twin)
	end
	if okP and okT and type(col) == "table" and col.GetRGBA and type(twin) == "table" and twin.GetRGBA then
		local r, g, b, a = col:GetRGBA()
		local _, _, _, twinAlpha = twin:GetRGBA()
		TintBoth(f, r, g, b, a, twinAlpha)
		return
	end
	-- (a client without the curves: the plain share, when the game hands one)
	local cur, max = Ask(UnitHealth, unit), Ask(UnitHealthMax, unit)
	local share = (cur and max and max > 0) and cur / max or 1
	local low = share > 0 and share <= TINT.at
	c = low and TINT.low or TINT.none
	TintBoth(f, c[1], c[2], c[3], low and 0 or 1, low and 1 or 0)
end

-- (fr-16) the portrait's twin (Tint): the portrait's picture -- Class Icons' medallion through the same icon copies,
-- else the game's portrait of the unit -- its layer (a sublevel over it), its masks (a skin's ring adds one) and its grey
local function HasMask(tex, mask)
	for i = 1, tex:GetNumMaskTextures() do
		if tex:GetMaskTexture(i) == mask then
			return true
		end
	end
	return false
end
local function TwinMasks(twin, portrait)
	for i = twin:GetNumMaskTextures(), 1, -1 do
		local m = twin:GetMaskTexture(i)
		if m and not HasMask(portrait, m) then
			twin:RemoveMaskTexture(m)
		end
	end
	for i = 1, portrait:GetNumMaskTextures() do
		local m = portrait:GetMaskTexture(i)
		if m and not HasMask(twin, m) then
			twin:AddMaskTexture(m)
		end
	end
end
local function Twin(f, medallion)
	local twin, portrait = f.PortraitTwin, f.Portrait
	if not twin then
		return
	end
	local okL, layer, sub = pcall(portrait.GetDrawLayer, portrait)
	if okL and type(layer) == "string" then
		twin:SetDrawLayer(layer, math.min((Num(sub) or 0) + 1, 7))
	end
	local okC, _, class = pcall(UnitClass, f.unit)
	class = medallion and okC and Text(class) or nil
	local path = class and MelloUI:ClassIconPath(class, "portrait") or nil
	if path then
		MelloUI.Icons.Set(twin, path)
	else
		MelloUI.Icons.Release(twin)
		twin:SetTexCoord(0, 1, 0, 1)
		twin:SetTexture(nil)
		pcall(SetPortraitTexture, twin, f.unit)
	end
	pcall(TwinMasks, twin, portrait)
	Call(twin, "SetDesaturated", not Connected(f.unit))
end

-- the twin's beat while its member shows (MelloUI.Anim's pulse, the engine's animation: still under Reduce Motion)
local function Beat(f, on)
	local twin, A = f.PortraitTwin, MelloUI.Anim
	if not (twin and A and A.Pulse) then
		return
	end
	if on and f.beat then
		A:Pulse(twin)   -- (its group again, as it was made)
	elseif on then
		local B = TINT.beat
		f.beat = A:Pulse(twin, B.from, B.to, B.half, B.to)
	elseif f.beat then
		A:StopGroup(f.beat)
	end
end

-- (fr-16) a member's bars' values as text, as the game's (TextStatusBar, the party's bars: its Status Text setting --
-- the statusText CVar -- keeps them shown, else while the bar is under the mouse; statusTextDisplay: the value and its
-- most, the share, both -- the share on the left, the value on the right). The client's string helpers take the
-- secret values as they are (BreakUpLargeNumbers, SetFormattedText); the share is the client's own (UnitHealthPercent
-- / UnitPowerPercent) rounded up as the game's through a step curve; "Dead" at none, as the game's
local Texts = function(f)
	-- (fr-17: the one copy, MelloUI.Units.Texts -- Modules/UnitFramesOwn.lua -- shared with the player frame of ours)
	MelloUI.Units.Texts(f)
end

-- the bars' values, as the game hands them (a member offline: its bar full and grey, as the game's; gone: none, the one
-- rule of every bar of a unit, MelloUI.Units.Value)
local function Health(f)
	local unit = f.unit
	local hb = f.HealthBarContainer.HealthBar
	local max = UnitHealthMax(unit)
	pcall(hb.SetMinMaxValues, hb, 0, max)
	local on = Connected(unit)
	local value = max
	if on then
		value = MelloUI.Units.Value(unit, UnitHealth(unit))
	end
	pcall(hb.SetValue, hb, value)
	Call(hb, "SetStatusBarDesaturated", not on)
	if ByHealth() then
		Colour(f)
	end
	Tint(f)
	Texts(f)
end

local function Power(f)
	local unit = f.unit
	local mb = f.ManaBar
	pcall(mb.SetMinMaxValues, mb, 0, UnitPowerMax(unit))
	pcall(mb.SetValue, mb, MelloUI.Units.Value(unit, UnitPower(unit)))
	Texts(f)
end

-- the portrait (the game's), or Class Icons' medallion while its portraits
-- are on (the look put that on); grey while offline, as the game's
local function Portrait(f)
	local ci = Module("ClassIcons")
	local medallion = ci and ci.db.portraits and true or false
	if not medallion then
		f.Portrait:SetTexCoord(0, 1, 0, 1)
		-- (fr-16: a member's as the game's -- never the replica's sample picture under it while the unit has none)
		if f.unit ~= UNIT then
			f.Portrait:SetTexture(nil)
		end
		pcall(SetPortraitTexture, f.Portrait, f.unit)
	end
	Call(f.Portrait, "SetDesaturated", not Connected(f.unit))
	Twin(f, medallion)
	Tint(f)
end

-- (fr-16) the member's offline plug, as the game's (UpdateOnlineStatus)
local function Online(f)
	local plug = f.PartyMemberOverlay.Disconnect
	if plug then
		plug:SetShown(not Connected(f.unit))
	end
end

-- (fr-16) the member's PVP badge, as the game's (UpdatePvPStatus): free for all, else its faction's while flagged
local function PvP(f)
	local icon = f.PartyMemberOverlay.PVPIcon
	if not icon then
		return
	end
	local unit = f.unit
	local atlas
	if Ask(rawget(_G, "UnitIsPVPFreeForAll"), unit) == true then
		atlas = PART.pvp.ffa
	else
		local faction = Ask(UnitFactionGroup, unit)
		if (faction == "Horde" or faction == "Alliance") and Ask(rawget(_G, "UnitIsPVP"), unit) == true then
			atlas = PART.pvp[faction]
		end
	end
	if atlas then
		Call(icon, "SetAtlas", atlas, true)
	end
	icon:SetShown(atlas ~= nil)
end

-- (fr-16) the member's "not here" eye, as the game's (UpdateNotPresentIcon): in another group, a summons on its way,
-- phased -- the frame at the game's 0.6 then, the eye at full (it stands beside the frame, not in it)
-- (2.1.0; the user, 2026-11-03: "...update the behaviour to match in Default, Modern and Oldschool theme") a member
-- out of your range faded as the raid buttons are (GroupButton's rule and Out Of Range Opacity, whole and at once); one
-- away (another group, another phase: NotPresent) faded the same; you never. Its pet's frame, a child of its frame,
-- fades with it.
local function Range(f)
	local alpha = Button.RangeOpacity()
	if f.unit == UNIT then
		f:SetAlpha(1)
	elseif alpha >= 1 then
		f:SetAlpha(f.away and PART.away or 1)   -- (no fade asked: the game's own for one away)
	else
		Button.RangeAlpha(f, f.unit, alpha, f.away)
	end
end
Solo.Range = Range

local function NotPresent(f)
	local eye = f.NotPresentIcon
	if not eye then
		return
	end
	local unit = f.unit
	local atlas, file, ring, tip, away = nil, nil, false, nil, false
	if Ask(rawget(_G, "UnitInOtherParty"), unit) == true then
		atlas, ring, tip, away = PART.other, true, rawget(_G, "PARTY_IN_PUBLIC_GROUP_MESSAGE"), true
	else
		local IS = rawget(_G, "C_IncomingSummon")
		local status = type(IS) == "table" and Ask(IS.HasIncomingSummon, unit) == true
			and Ask(IS.IncomingSummonStatus, unit) or nil
		local S = Enum2("SummonStatus", "Pending") and rawget(_G, "Enum").SummonStatus
		if status and S then
			local key = (status == S.Pending and 1) or (status == S.Accepted and 2) or (status == S.Declined and 3) or nil
			local tips = { "INCOMING_SUMMON_TOOLTIP_SUMMON_PENDING", "INCOMING_SUMMON_TOOLTIP_SUMMON_ACCEPTED",
				"INCOMING_SUMMON_TOOLTIP_SUMMON_DECLINED" }
			if key then
				atlas, tip = PART.summon[key], rawget(_G, tips[key])
			end
		elseif Connected(unit) then
			local reason = Ask(rawget(_G, "UnitPhaseReason"), unit)
			if reason then
				file, away = PART.phase, true
				local PU = rawget(_G, "PartyUtil")
				tip = PU and PU.GetPhasedReasonString and Ask(PU.GetPhasedReasonString, reason, unit) or nil
			end
		end
	end
	f.away = away
	Range(f)
	if not (atlas or file) then
		eye:Hide()
		return
	end
	if atlas then
		Call(eye.texture, "SetAtlas", atlas, true)
		eye.texture:SetTexCoord(0, 1, 0, 1)
	else
		eye.texture:SetTexture(file)
		local c = PART.phaseCoords
		eye.texture:SetTexCoord(c[1], c[2], c[3], c[4])
	end
	eye.Border:SetShown(ring)
	eye.tip = tip
	eye:SetShown(f:IsShown())
end

-- (fr-16) the member's ready check, as the game's (UpdateReadyCheck, READY_CHECK_FINISHED): the game's own icon frame
-- and helpers (ReadyCheck.lua) on our frame
local function Ready(f, finished)
	local rc = f.ReadyCheck
	if not rc then
		return
	end
	local unit = f.unit
	if finished then
		if Ask(UnitExists, unit) == true then
			pcall(rawget(_G, "ReadyCheck_Finish"), rc, rawget(_G, "DEFAULT_READY_CHECK_STAY_TIME") or 6)
		end
		return
	end
	local status = Ask(GetReadyCheckStatus, unit)
	if status and Ask(UnitName, unit) and Connected(unit) then
		if status == "ready" then
			pcall(rawget(_G, "ReadyCheck_Confirm"), rc, 1)
		elseif status == "notready" then
			pcall(rawget(_G, "ReadyCheck_Confirm"), rc, 0)
		else
			pcall(rawget(_G, "ReadyCheck_Start"), rc)
		end
	else
		rc:Hide()
	end
end

local Threat   -- (below: a member's combat flash)

-- (fr-16) a member's mana bar in the game's party art for its power, as the game's member wears it
-- (UnitFrameManaBar_UpdateType: "UI-HUD-UnitFrame-" .. its frame type, "Party", .. "-PortraitOn-Bar-" .. the power's
-- element) where the replica's painter put the player frame's art of that power; a picked Bar Texture left alone
local PLAYER_POWER, PARTY_POWER = "^UI%-HUD%-UnitFrame%-Player%-PortraitOn%-Bar%-(.+)$", "UI-HUD-UnitFrame-Party-PortraitOn-Bar-"
local function PartyPower(f)
	local fill = f.ManaBar:GetStatusBarTexture()
	local ok, atlas = pcall(fill.GetAtlas, fill)
	atlas = ok and Text(atlas) or nil
	local element = atlas and atlas:match(PLAYER_POWER)
	local CT = rawget(_G, "C_Texture")
	if element and CT and CT.GetAtlasInfo and CT.GetAtlasInfo(PARTY_POWER .. element) then
		f.ManaBar:SetStatusBarTexture(PARTY_POWER .. element)
	end
end

-- (fr-16) a member's status glow, as the game's (PartyMemberAuraMixin:UpdateAurasInternal: shown while the member has
-- a debuff the game lists, in that debuff's colour -- AuraUtil.SetAuraBorderColor): the unit's first debuff through the
-- game's own filter (AuraUtil's RefreshDebuffs: the ones I can dispel while its showDispelDebuffs setting is on and I
-- can help the unit, else any), its colour by Healer Frames' curve of the game's colours (that module off too), read
-- on the unit's own UNIT_AURA. A debuff or a colour the client keeps from us shows none; nothing compared
local function StatusFilter(unit)
	local CV = rawget(_G, "C_CVar")
	local get = (type(CV) == "table" and CV.GetCVarBool) or rawget(_G, "GetCVarBool")
	if Ask(get, "showDispelDebuffs") ~= true then
		return "HARMFUL"
	end
	-- (an answer kept secret counts as one I can help: a member is)
	local ok, help = pcall(UnitCanAssist, "player", unit)
	return (ok and (IsSecret(help) or help)) and "HARMFUL|RAID" or "HARMFUL"
end
local function Status(f)
	local status = f.PartyMemberOverlay.Status
	if not status then
		return
	end
	local found, r, g, b = false, nil, nil, nil
	-- (2.1.17: none on a dead member or a ghost, MelloUI.Units.Gone -- the user, 2026-11-07)
	local hf = f.unit ~= UNIT and not MelloUI.Units.Gone(f.unit) and MelloUI:GetModule("HealerFrames")
	if hf and hf.DebuffColour then
		local ok
		ok, found, r, g, b = pcall(hf.DebuffColour, hf, f.unit, StatusFilter(f.unit))
		found = ok and found == true
	end
	if found then
		pcall(status.SetVertexColor, status, r, g, b)
	end
	status:SetShown(found)
end

-- the look the settings give the members' (the replica's painter, with the
-- unit's plain facts: name, class, power type), then its values
local function Look(f)
	local CP = MelloUI.ConfigPreview
	local s = CP and CP.Values and CP.Paint and CP.Values("unitframe", "party")
	if not s then
		return
	end
	local unit = f.unit
	local okN, name = pcall(UnitName, unit)
	local okC, _, class = pcall(UnitClass, unit)
	local okP, _, token = pcall(UnitPowerType, unit)
	s.first, s.last = okN and Text(name) or "", nil
	s.class = okC and Text(class) or nil
	s.token = okP and Text(token) or "MANA"
	s.display = nil
	s.health, s.max, s.power, s.powerMax = 1, 1, 1, 1
	pcall(CP.Paint, "unitframe", f, "party", s)
	if okN and not Text(name) then
		pcall(f.Name.SetText, f.Name, name)   -- (a secret name as it is)
	end
	Portrait(f)
	Colour(f)
	Health(f)
	Power(f)
	Solo.Group(f)
	if unit ~= UNIT then
		PartyPower(f)
		Online(f)
		PvP(f)
		NotPresent(f)
		Ready(f)
		Threat(f)
		Status(f)
	end
end

-- in a party: the role and the leader's crown (the guide's in a group from the dungeon finder), as the game's members
-- show theirs (PartyMemberFrame.lua UpdateAssignedRoles / UpdateLeader; the role in the members' sharp picture,
-- Button.RoleAtlas); solo: none. Shown or hidden here, faded by the Designer's parts (their alpha)
function Solo.Group(f)
	local ov = f.PartyMemberOverlay
	local unit = f.unit
	local okG, grouped = pcall(IsInGroup)
	grouped = okG and grouped == true
	local okR, role = pcall(UnitGroupRolesAssigned, unit)
	local atlas = grouped and okR and Button.RoleAtlas(Text(role)) or nil
	if atlas then
		Call(ov.RoleIcon, "SetAtlas", atlas)
	end
	ov.RoleIcon:SetShown(atlas ~= nil)
	local okL, lead = pcall(UnitIsGroupLeader, unit)
	lead = grouped and okL and not IsSecret(lead) and lead == true
	local okF, guide = pcall(HasLFGRestrictions)
	guide = okF and not IsSecret(guide) and guide == true
	ov.LeaderIcon:SetShown(lead and not guide)
	ov.GuideIcon:SetShown(lead and guide)
end

local function Paint(f)
	if f and f:IsShown() then
		Look(f)
	end
end

--------------------------------------------------------------------------------
-- (fr-16) A member's combat flash, as the game's (UnitFrame_UpdateThreatIndicator: shown in its threat's colour --
-- GetThreatStatusColor -- while the unit has threat), read from the unit itself on its threat event: a threat the game
-- keeps secret shows none (it cannot be told from none; nothing of the game's frames is read or hooked -- the user's
-- errors of 2026-10-31 23:49, the game's members' regions missing a method after hooks of ours on them). Seen only
-- while Unit Frames is off, as the game's own (Hide Combat Flash; its threat halo follows ours, MelloUI.FrameHalo,
-- through the frame's threatIndicator)
--------------------------------------------------------------------------------

-- our flash seen as the game's would be (Unit Frames hides the game's)
local function FlashSeen(f)
	local uf = MelloUI:GetModule("UnitFrames")
	f.Flash:SetAlpha((uf and uf.isEnabled) and 0 or 1)
end

Threat = function(f)
	if f.unit == UNIT then
		return
	end
	local status = Ask(rawget(_G, "UnitThreatSituation"), f.unit)
	-- (2.1.17: none on a dead member or a ghost -- the game's leaves its flash as it stood; the user, 2026-11-07, hid it)
	local on = type(status) == "number" and status > 0 and not MelloUI.Units.Gone(f.unit)
	if on then
		local get = rawget(_G, "GetThreatStatusColor")
		local ok, r, g, b = false, nil, nil, nil
		if get then
			ok, r, g, b = pcall(get, status)
		end
		if ok and r then
			pcall(f.Flash.SetVertexColor, f.Flash, r, g, b)
		end
	end
	f.Flash:SetShown(on)
	FlashSeen(f)
	local halo = rawget(MelloUI, "FrameHalo")
	if halo and halo.Update then
		pcall(halo.Update, f)
	end
end

-- (2.1.16) gone or back, on whatever told us first: both bars and the portrait's tint at once; (2.1.17) no glow round a
-- gone member (the user, 2026-11-07): its combat flash (the threat halo follows it), its status glow, Healer Frames' glow
local function Life(f)
	if MelloUI.Units.GoneChanged(f) then
		Health(f)
		Power(f)
		if f.unit ~= UNIT then
			Threat(f)
			Status(f)
		end
		local hf = MelloUI:GetModule("HealerFrames")
		if hf and hf.Update then
			pcall(hf.Update, hf, f)
		end
	end
end

--------------------------------------------------------------------------------
-- A member's pet (PartyMemberPetFrameTemplate: 64 x 23 at the member's 23,-43; its portrait 18 at 3,-3 in its
-- circle, the party frame's art at half its size at 0,-1, its health bar 71 x 10 at half at 43,-18, its aura row at
-- 24,-16), shown by the game's unit watch while the game shows party pets (the showPartyPets setting), faded while
-- its owner is offline (the game hides it then; a secure frame of ours may not be hidden in a fight)
--------------------------------------------------------------------------------

local function PetsShown()
	local get = type(C_CVar) == "table" and C_CVar.GetCVarBool
	return get and Ask(get, "showPartyPets") == true or false
end

local function PetLook(p)
	local unit = p.unit
	pcall(SetPortraitTexture, p.Portrait, unit)
	local hb = p.HealthBar
	pcall(hb.SetMinMaxValues, hb, 0, UnitHealthMax(unit))
	pcall(hb.SetValue, hb, MelloUI.Units.Value(unit, UnitHealth(unit)))
	p:SetAlpha(Connected(p.owner.unit) and 1 or 0)
end

local OnPetShow = Shared("a party pet's frame shown", function(self)
	PetLook(self)
end, "script")

local function MakePet(member, i)
	local P = PART.pet
	local p = CreateFrame("Button", "MelloUIGroupPartyPet" .. i, member, "SecureUnitButtonTemplate")
	p:Hide()
	p:SetSize(P.w, P.h)
	p:SetPoint("TOPLEFT", member, "TOPLEFT", P.x, P.y)
	p.unit = "partypet" .. i
	p.owner = member
	p:SetAttribute("unit", p.unit)
	p:SetAttribute("*type1", "target")
	p:SetAttribute("*type2", "togglemenu")
	p:RegisterForClicks("AnyUp")
	p.Portrait = p:CreateTexture(nil, "BACKGROUND")
	p.Portrait:SetSize(18, 18)
	p.Portrait:SetPoint("TOPLEFT", p, "TOPLEFT", 3, -3)
	local circle = p:CreateMaskTexture()
	circle:SetAtlas("CircleMask")
	circle:SetAllPoints(p.Portrait)
	p.Portrait:AddMaskTexture(circle)
	p.PortraitMask = circle
	p.Texture = p:CreateTexture(nil, "ARTWORK")
	Call(p.Texture, "SetAtlas", P.art, true)
	p.Texture:SetScale(0.5)
	p.Texture:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -1)
	local hb = CreateFrame("StatusBar", nil, p)
	hb:SetScale(0.5)
	hb:SetSize(71, 10)
	hb:SetPoint("TOPLEFT", p, "TOPLEFT", 43, -18)
	hb:SetMinMaxValues(0, 1)
	Call(hb, "SetStatusBarTexture", P.health)
	p.HealthBar = hb
	p.AuraFrameContainer = MakeAuras(p, p.unit, 24, -16)
	Perf.HookScript(p, "OnShow", OnPetShow)
	return p
end

-- a member's pet driven by the game's unit watch while party pets show, else put away (out of a fight)
local function DrivePet(p, on)
	on = on and PetsShown() or false
	if p.driven == on then
		return
	end
	p.driven = on
	if on then
		Watch(p)
	else
		Unwatch(p)
		p:Hide()
	end
	if p.AuraFrameContainer then
		Call(p.AuraFrameContainer, "SetAuraGroupEnabled", "auras", on)
	end
end

--------------------------------------------------------------------------------
-- Their places: stacked from the party container's corner, you on top
--------------------------------------------------------------------------------

-- the frames' scale in the container: Edit Mode's own party size (the game's party frame's, which nothing of ours
-- writes) times PORTRAIT_BASE
function Solo.Scale()
	local pf = rawget(_G, "PartyFrame")
	local s = type(pf) == "table" and Ask(pf.GetScale, pf) or nil
	s = Num(s)
	return ((s and s > 0) and s or 1) * Solo.PORTRAIT_BASE
end

-- one slot: a frame's height (the game's member's 53) and the room under it (GroupHeaders.lua's PortraitSpacing:
-- Vertical Spacing, its pet's room in it)
local function Step(f)
	local H = ns.Headers
	local okH, h = pcall(f.GetHeight, f)
	return (okH and Num(h) or 53) + (H and H.PortraitSpacing and H.PortraitSpacing() or 2)
end

local function Corner()
	local H = ns.Headers
	return (H and H.Corner and H.Corner("party")) or "TOPLEFT"
end

-- a frame in slot `slot` (0: the top) of the container, at the frames' scale
local function PlaceIn(f, parent, slot)
	f:SetScale(Solo.Scale())
	f:ClearAllPoints()
	local corner = Corner()
	f:SetPoint(corner, parent, corner, 0, -slot * Step(f))
end

local function PlaceAll()
	local H = ns.Headers
	local c = H and H.containers and H.containers.party
	if not c then
		return
	end
	if Solo.frame and Solo.driven then
		PlaceIn(Solo.frame, c, 0)
	end
	local first = Solo.Above() and 1 or 0
	for i, m in ipairs(Solo.members) do
		PlaceIn(m, Solo.holder, first + i - 1)
	end
end

--------------------------------------------------------------------------------
-- Made once, their events while wanted
--------------------------------------------------------------------------------

-- a unit event's paint ([event] = fn(frame, unit-of-the-event))
local UNIT_EVENTS = {
	UNIT_HEALTH = Health, UNIT_MAXHEALTH = Health, UNIT_POWER_UPDATE = Power, UNIT_MAXPOWER = Power,
	UNIT_DISPLAYPOWER = Look, UNIT_NAME_UPDATE = Look, UNIT_PORTRAIT_UPDATE = Portrait,
	UNIT_CONNECTION = function(f)
		Health(f)
		Portrait(f)
		Online(f)
		NotPresent(f)
		local pet = f.PetFrame
		if pet and pet:IsShown() then
			PetLook(pet)
		end
	end,
	UNIT_THREAT_SITUATION_UPDATE = function(f)
		Threat(f)
	end,
	UNIT_FACTION = PvP, UNIT_PHASE = NotPresent, UNIT_FLAGS = NotPresent, UNIT_OTHER_PARTY_CHANGED = NotPresent,
	UNIT_IN_RANGE_UPDATE = Range,
	UNIT_CTR_OPTIONS = NotPresent,
}
-- a member's own unit events beyond those (its status glow: its auras)
local OWN_EVENTS = { UNIT_AURA = Status }
local PET_EVENTS = { UNIT_HEALTH = true, UNIT_MAXHEALTH = true, UNIT_PORTRAIT_UPDATE = true, UNIT_NAME_UPDATE = true }
-- (a place to read again: the world entered, the UI's scale, Edit Mode's layout -- its party size)
local PLACE_EVENTS = { UI_SCALE_CHANGED = true, PLAYER_ENTERING_WORLD = true, EDIT_MODE_LAYOUTS_UPDATED = true }
-- (the role, the leader, a member's whole look -- partyN may be another player after a roster change -- the ready
-- check, a summons, a member's state)
local GROUP_EVENTS = { GROUP_ROSTER_UPDATE = true, PLAYER_ROLES_ASSIGNED = true, PARTY_LEADER_CHANGED = true }
local MEMBER_EVENTS = { READY_CHECK = true, READY_CHECK_CONFIRM = true, READY_CHECK_FINISHED = true,
	INCOMING_SUMMON_CHANGED = true, PARTY_MEMBER_ENABLE = true, PARTY_MEMBER_DISABLE = true, CVAR_UPDATE = true }
-- (2.1.16) a death anywhere near, yours, your release and return: who is gone read again (UNIT_DIED's payload not read)
local LIFE_EVENTS = { UNIT_DIED = true, PLAYER_DEAD = true, PLAYER_ALIVE = true, PLAYER_UNGHOST = true }

local function PlaceNow()
	if Solo.driven or Solo.partyDriven then
		PlaceAll()
	end
end

-- every member shown: fn(frame)
local function EachMember(fn, ...)
	for _, m in ipairs(Solo.members) do
		if m:IsShown() then
			fn(m, ...)
		end
	end
end

local function PetsLater()
	Later(function()
		for _, m in ipairs(Solo.members) do
			DrivePet(m.PetFrame, Solo.partyDriven)
		end
	end, "Group Frames: the party pets")
end

local events = nil
local OnEvent = Shared("the portrait party's events", function(_, event, arg1)
	local f = Solo.frame
	if PLACE_EVENTS[event] then
		Later(PlaceNow, "Group Frames: the portrait party's place")
		Paint(f)
		EachMember(Look)
		return
	end
	if event == "PORTRAITS_UPDATED" then
		if f and f:IsShown() then
			Portrait(f)
		end
		EachMember(Portrait)
	elseif GROUP_EVENTS[event] then
		if f and f:IsShown() then
			Solo.Group(f)
		end
		EachMember(event == "GROUP_ROSTER_UPDATE" and Look or Solo.Group)
	elseif event == "READY_CHECK_FINISHED" then
		EachMember(Ready, true)
	elseif event == "READY_CHECK" or event == "READY_CHECK_CONFIRM" then
		EachMember(Ready)
	elseif event == "CVAR_UPDATE" then
		if arg1 == "showPartyPets" then
			PetsLater()
		elseif arg1 == "statusText" or arg1 == "statusTextDisplay" then
			MelloUI.Units.TextsChanged()   -- (fr-17: the shared texts' settings read again)
			EachMember(Texts)
		elseif arg1 == "showDispelDebuffs" then
			EachMember(Status)
		end
	elseif MEMBER_EVENTS[event] then
		EachMember(NotPresent)
		EachMember(Life)
	elseif LIFE_EVENTS[event] then
		if f and f:IsShown() then
			Life(f)
		end
		EachMember(Life)
	end
end, "script")

-- your unit events (one listener for you: your unit's events only)
local OnYours = Shared("your portrait party frame's events", function(_, event)
	local f = Solo.frame
	local paint = f and f:IsShown() and UNIT_EVENTS[event]
	if paint then
		Life(f)
		paint(f, UNIT)
	end
end, "script")

-- a member's own unit events: its unit's and its pet's
local OnMember = Shared("a portrait party member's events", function(self, event, unit)
	if not self:IsShown() then
		return
	end
	if unit == self.unit then
		Life(self)   -- (any event of its unit may be the first to say)
		local paint = UNIT_EVENTS[event] or OWN_EVENTS[event]
		if paint then
			paint(self, unit)
		end
	elseif unit and self.PetFrame and unit == self.PetFrame.unit and PET_EVENTS[event] then
		if self.PetFrame:IsShown() then
			PetLook(self.PetFrame)
		end
	end
	if event == "UNIT_PET" then
		local p = self.PetFrame
		if p and p:IsShown() then
			PetLook(p)
		end
	end
end, "script")

local yours = nil
local function Listen(on)
	on = on and true or false
	if on == Solo.listening then
		return
	end
	Solo.listening = on
	if on then
		if not events then
			events = CreateFrame("Frame")
			Perf.SetScript(events, "OnEvent", OnEvent)
			yours = CreateFrame("Frame")
			Perf.SetScript(yours, "OnEvent", OnYours)
		end
		for e in pairs(UNIT_EVENTS) do
			pcall(yours.RegisterUnitEvent, yours, e, UNIT)
		end
		pcall(events.RegisterEvent, events, "PORTRAITS_UPDATED")
		for _, set in ipairs({ PLACE_EVENTS, GROUP_EVENTS, MEMBER_EVENTS, LIFE_EVENTS }) do
			for e in pairs(set) do
				pcall(events.RegisterEvent, events, e)
			end
		end
	elseif events then
		events:UnregisterAllEvents()
		yours:UnregisterAllEvents()
	end
end

-- a member's events while the members are wanted
local function ListenMember(m, on)
	if on == (m.listening or false) then
		return
	end
	m.listening = on
	if on then
		local pet = m.PetFrame and m.PetFrame.unit
		for e in pairs(UNIT_EVENTS) do
			pcall(m.RegisterUnitEvent, m, e, m.unit, pet)
		end
		for e in pairs(OWN_EVENTS) do
			pcall(m.RegisterUnitEvent, m, e, m.unit)
		end
		pcall(m.RegisterUnitEvent, m, "UNIT_PET", m.unit)
	else
		m:UnregisterAllEvents()
	end
end

-- the look's settings (one listener each, made once)
local hooked = false
local function Hook()
	if hooked then
		return
	end
	hooked = true
	MelloUI:On("setting", function(module)
		if LOOKS[module] then
			Solo:Repaint()
		end
	end, "GroupFrames.solo")
	MelloUI:On("module", function(module)
		if LOOKS[module] then
			Solo:Repaint()
		end
	end, "GroupFrames.solo")
	-- (Edit Mode's party size -- the game's party frame's own, read by Solo.Scale -- read again when Edit Mode closes
	-- and its layouts are applied: GroupHeaders.lua's editmode listener, EDIT_MODE_LAYOUTS_UPDATED; nothing hooked on
	-- the game's frame)
end

-- the skin's dressing, Healer Frames' heals and glow, the indicators, the
-- parts (each idempotent: asked again when the look comes on later)
local function Dress(f)
	local ufp = MelloUI:GetModule("UnitFrames")
	if ufp and ufp.DressStandIn then
		pcall(ufp.DressStandIn, ufp, f)
	end
	local hf = MelloUI:GetModule("HealerFrames")
	if hf and hf.Heals then
		local hb = f.HealthBarContainer.HealthBar
		pcall(hf.Heals, hf, hb, function()
			return f.unit
		end)
		pcall(hf.Glow, hf, f, "party")
	end
	if ns.Parts then
		ns.Parts:Lay(f, "party", true)
	end
end

-- (fr-16) the game's own member parts on a member of ours (PartyFrameTemplates.xml): the status glow, the PVP badge,
-- the offline plug (its overlay's), the ready check over the portrait, the "not here" eye beside the frame
local function MemberParts(f)
	local ov = f.PartyMemberOverlay
	local status = ov:CreateTexture(nil, "ARTWORK")
	Call(status, "SetAtlas", PART.status, true)
	status:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -2)
	status:Hide()
	ov.Status = status
	-- (the portrait's twin for the game's low-health beat: Twin, Tint, Beat -- unseen till the share is low)
	local twin = f:CreateTexture(nil, "BACKGROUND")
	twin:SetAllPoints(f.Portrait)
	twin:SetVertexColor(1, 1, 1, 0)
	f.PortraitTwin = twin
	local pvp = ov:CreateTexture(nil, "OVERLAY")
	pvp:SetScale(0.6)
	pvp:SetPoint("CENTER", f, "TOPLEFT", 24, -68)
	pvp:Hide()
	ov.PVPIcon = pvp
	local plug = ov:CreateTexture(nil, "OVERLAY")
	plug:SetTexture(PART.plug)
	plug:SetSize(64, 64)
	plug:SetPoint("LEFT", f, "LEFT", -7, -1)
	plug:Hide()
	ov.Disconnect = plug
	-- the bars' texts (the game's TextStatusBarText: centre, left, right; the mana bar's 2 and 4 in: Texts) -- on the
	-- bars themselves: the game's health bar shares its container's level, ours is a frame over it
	local function Strings(bar, cx, lx)
		local t = {}
		for key, at in pairs({ center = { "CENTER", cx }, left = { "LEFT", lx }, right = { "RIGHT", 0 } }) do
			local fs = bar:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
			fs:SetPoint(at[1], bar, at[1], at[2], 0)
			fs:Hide()
			t[key] = fs
		end
		return t
	end
	f.texts = { health = Strings(f.HealthBarContainer.HealthBar, 0, 0), mana = Strings(f.ManaBar, 2, 4) }
	-- (its combat flash the threat indicator the threat halo follows, as the game's frames' -- UnitFrame_Initialize)
	f.threatIndicator = f.Flash
	f.Flash.unit = f.unit
	local okR, rc = pcall(CreateFrame, "Frame", nil, f, "ReadyCheckStatusTemplate")
	if okR and type(rc) == "table" then
		rc:Hide()
		rc:SetPoint("CENTER", f.Portrait, "CENTER", 0, -2)
		rc:SetFrameLevel(f:GetFrameLevel() + 2)
		f.ReadyCheck = rc
	end
	-- (the eye at full while the frame is at 0.6: beside it, in the frame's own holder, hidden with it)
	local eye = CreateFrame("Frame", nil, f:GetParent())
	eye:Hide()
	eye:SetSize(25, 25)
	eye:SetPoint("LEFT", f, "RIGHT", 2, -2)
	eye.texture = eye:CreateTexture(nil, "ARTWORK")
	eye.texture:SetAllPoints(eye)
	eye.Border = eye:CreateTexture(nil, "OVERLAY")
	eye.Border:SetTexture(PART.ring)
	eye.Border:SetAllPoints(eye)
	Perf.HookScript(eye, "OnEnter", Shared("a party member's not-here eye: its tip", function(self)
		if self.tip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.tip, nil, nil, nil, nil, true)
			GameTooltip:Show()
		end
	end, "script"))
	Perf.HookScript(eye, "OnLeave", Shared("a party member's not-here eye: its tip away", function()
		GameTooltip:Hide()
	end, "script"))
	eye:EnableMouse(true)
	f.NotPresentIcon = eye
end

-- (fr-16) the game's mouseover box of a member's buffs and debuffs (PartyMemberBuffTooltip, PartyMemberFrameMixin:
-- OnEnter: at the member's 47,-25): one per member of ours, made with the members -- the shared one, MelloUI.Units.
-- AuraBox (Modules/UnitFramesOwn.lua), the pet frame's too
local BOX = { x = 47, y = -25 }
local function MakeBox(m)
	return MelloUI.Units.AuraBox(m, BOX.x, BOX.y, DressAura)
end

-- the member's box on its hover (the game's HIDE_PARTY_MEMBER_BUFF_TOOLTIP: none)
local function BoxOn(m)
	if not rawget(_G, "HIDE_PARTY_MEMBER_BUFF_TOOLTIP") then
		MelloUI.Units.AuraBoxOn(m.buffBox)
	end
end

-- (fr-16) a member under the mouse: the bar under it shows its text (Texts), as the game's bars do on their hover --
-- read on each frame while a member is under the mouse only (our bars take no mouse: the clicks are the member's)
local hover = { frame = nil, member = nil }
local OnHoverUpdate = Shared("a portrait party member under the mouse: its bars' texts", function(self)
	local m = hover.member
	if not m then
		self:Hide()
		return
	end
	local at = (m.HealthBarContainer:IsMouseOver() and "health") or (m.ManaBar:IsMouseOver() and "mana") or nil
	if at ~= m.hovered then
		m.hovered = at
		Texts(m)
	end
end, "script")

-- (fr-16) a member's tooltip, as the game's (UnitFrame_OnEnter: the unit's tooltip at the default place)
local OnMemberEnter = Shared("a portrait party member's tooltip", function(self)
	if rawget(_G, "GameTooltip_SetDefaultAnchor") then
		GameTooltip_SetDefaultAnchor(GameTooltip, self)
	else
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	end
	if pcall(GameTooltip.SetUnit, GameTooltip, self.unit) then
		GameTooltip:Show()
	end
	if not hover.frame then
		hover.frame = CreateFrame("Frame")
		hover.frame:Hide()
		Perf.SetScript(hover.frame, "OnUpdate", OnHoverUpdate)
	end
	hover.member = self
	hover.frame:Show()
	BoxOn(self)
end, "script")
local OnMemberLeave = Shared("a portrait party member's tooltip away", function(self)
	GameTooltip:Hide()
	if hover.member == self then
		hover.member = nil
		if hover.frame then
			hover.frame:Hide()
		end
	end
	if self.hovered then
		self.hovered = nil
		Texts(self)
	end
	MelloUI.Units.AuraBoxOff(self.buffBox)
end, "script")

local OnShown = Shared("a portrait party frame shown", function(self)
	Look(self)
	if self.NotPresentIcon then
		NotPresent(self)
	end
	Beat(self, true)
end, "script")
local OnHidden = Shared("a portrait party member hidden: its eye too, its portrait's beat", function(self)
	if self.NotPresentIcon then
		self.NotPresentIcon:Hide()
	end
	Beat(self, false)
end, "script")

-- one frame of ours: the replica on a secure unit button for `unit`, named `name`, in `parent`
local function MakeFrame(unit, name, parent)
	local CP = MelloUI.ConfigPreview
	if not (CP and CP.Kind and CP.Kind("unitframe") and CP.Build and parent) then
		return nil
	end
	local f = CreateFrame("Button", name, parent, "SecureUnitButtonTemplate")
	f:Hide()
	f:SetAttribute("unit", unit)
	f:SetAttribute("*type1", "target")
	f:SetAttribute("*type2", "togglemenu")
	f:SetAttribute("toggleForVehicle", false)
	f:RegisterForClicks("AnyUp")
	local okB, made = pcall(CP.Build, "unitframe", parent, "party", f)
	if not (okB and made) then
		return nil
	end
	f.unit = unit
	-- (its health bar keeps its art's colour, as the game's own: Bar Textures
	-- leaves such a bar white under its green)
	f.HealthBarContainer.HealthBar.lockColor = true
	-- the overlay's role, leader and guide icons (none solo; the Designer's
	-- Role Icon and Leader Icon parts lay them)
	local ov = f.PartyMemberOverlay
	local role = ov:CreateTexture(nil, "OVERLAY")
	role:SetSize(12, 12)
	role:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
	role:Hide()
	ov.RoleIcon = role
	for key, atlas in pairs(GROUP_ICONS) do
		local icon = ov:CreateTexture(nil, "OVERLAY")
		Call(icon, "SetAtlas", atlas, true)
		icon:SetPoint("BOTTOM", f, "TOP", -10, -6)
		icon:Hide()
		ov[key] = icon
	end
	f.AuraFrameContainer = MakeAuras(f, unit)
	Perf.HookScript(f, "OnShow", OnShown)
	if MelloUI.FrameHover then
		MelloUI.FrameHover.Attach(f)   -- (1.2.4: the mouseover highlight)
	end
	return f
end

-- after its parts: dressed, a host of the indicators
local function Finish(f)
	-- (retail: its buffs after its debuffs, as the members' -- Solo.BuffRow)
	Solo.BuffRow(f, f.unit)
	Dress(f)
	if ns.Indicators then
		ns.Indicators:Host(f, f.unit, Looks.Fill(f.HealthBarContainer.HealthBar), "party")
	end
end

local function Make()
	local H = ns.Headers
	local f = MakeFrame(UNIT, "MelloUIGroupSoloParty", H and H.containers and H.containers.party)
	if not f then
		return nil
	end
	Solo.frame = f
	Finish(f)
	return f
end

-- the members, once: their holder in the container (a state driver shows it in a party), each with its parts and pet
local function MakeMembers()
	local H = ns.Headers
	local c = H and H.containers and H.containers.party
	if not c then
		return false
	end
	local holder = CreateFrame("Frame", "MelloUIGroupPartyMembers", c)
	holder:SetAllPoints(c)
	holder:Hide()
	Solo.holder = holder
	for i = 1, MEMBERS do
		local m = MakeFrame("party" .. i, "MelloUIGroupPartyMember" .. i, holder)
		if not m then
			return false
		end
		m.index = i
		-- (the game's member's name in its template's font, GameFontNormalSmall: its level and the Designer's name
		-- part read it as they read the game's)
		local font = rawget(_G, "GameFontNormalSmall")
		if font then
			m.Name:SetFontObject(font)
		end
		MemberParts(m)
		m.PetFrame = MakePet(m, i)
		m.buffBox = MakeBox(m)
		Perf.SetScript(m, "OnEvent", OnMember)
		Perf.HookScript(m, "OnHide", OnHidden)
		Perf.HookScript(m, "OnEnter", OnMemberEnter)
		Perf.HookScript(m, "OnLeave", OnMemberLeave)
		Solo.members[i] = m
		Finish(m)
	end
	return true
end

local function Drive(f, on)
	local rule = on and Rule() or nil
	if on == Solo.driven and rule == Solo.rule then
		return
	end
	local was = Solo.driven
	Solo.driven, Solo.rule = on, rule
	if on then
		RegisterStateDriver(f, "visibility", rule)
	else
		UnregisterStateDriver(f, "visibility")
		f:Hide()
	end
	if on == was then
		return   -- (only its rule changed)
	end
	if f.AuraFrameContainer then
		Call(f.AuraFrameContainer, "SetAuraGroupEnabled", "auras", on)
	end
	if ownBuffs[f] then
		Call(f.AuraFrameContainer, "SetAuraGroupEnabled", "buffs", on)
	end
end

-- the members and their holder driven (the unit watch, the party's state driver) or put away
local function DriveMembers(on)
	if on == Solo.partyDriven then
		return
	end
	Solo.partyDriven = on
	local holder = Solo.holder
	if on then
		RegisterStateDriver(holder, "visibility", PARTY_RULE)
	else
		UnregisterStateDriver(holder, "visibility")
		holder:Hide()
	end
	for _, m in ipairs(Solo.members) do
		if on then
			Watch(m)
		else
			Unwatch(m)
			m:Hide()
		end
		ListenMember(m, on)
		DrivePet(m.PetFrame, on)
		if m.AuraFrameContainer then
			Call(m.AuraFrameContainer, "SetAuraGroupEnabled", "auras", on)
		end
		if ownBuffs[m] then
			Call(m.AuraFrameContainer, "SetAuraGroupEnabled", "buffs", on)
		end
	end
end

local function UpdateNow()
	local party = Solo.PartyOn()
	local want = Wanted()
	if (want or party) and not hooked then
		Hook()
	end
	local f = Solo.frame
	if want and not f then
		f = Make()
	end
	if party and not Solo.holder then
		MakeMembers()
	end
	-- (you away while the Preview's made-up raid shows: GroupHeaders.lua's Aside)
	local on = (want and not Solo.aside) and true or false
	if f then
		Drive(f, on)
	end
	if Solo.holder then
		DriveMembers(party)
	end
	PlaceAll()
	Listen(on or party)
	if on then
		Paint(f)
	end
	EachMember(Look)
end

function Solo:Update()
	Later(UpdateNow, "Group Frames: the portrait party")
end

local function RepaintNow()
	local f = Solo.frame
	if f and Solo.driven then
		Dress(f)
		Paint(f)
	end
	if Solo.partyDriven then
		for _, m in ipairs(Solo.members) do
			Dress(m)
		end
		EachMember(Look)
	end
end

function Solo:Repaint()
	if (self.frame and self.driven) or self.partyDriven then
		Later(RepaintNow, "Group Frames: the portrait party's look")
	end
end

function Solo:Shown()
	local f = self.frame
	return (f and self.driven and f:IsVisible()) and f or nil
end

function Solo:Each(fn)
	if self.frame then
		fn(self.frame, UNIT)
	end
	for _, m in ipairs(self.members) do
		fn(m, m.unit)
	end
end

function Solo:Member(i)
	return self.members[i]
end

function Solo:Of(unit)
	unit = Text(unit)
	if not unit then
		return nil
	end
	local f = self:Shown()
	if f and unit == UNIT then
		return f
	end
	if not self.partyDriven then
		return nil
	end
	for _, m in ipairs(self.members) do
		if m.unit == unit and m:IsVisible() then
			return m
		end
	end
	return nil
end
