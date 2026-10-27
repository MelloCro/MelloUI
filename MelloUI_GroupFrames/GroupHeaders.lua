--------------------------------------------------------------------------------
-- MelloUI - Group Frames: the headers (stage 1 of MelloUI's own group frames,
-- docs/plans/raid-frame-designer.md "Stage 1 design")
--
-- Two of the game's secure group headers (SecureGroupHeaderTemplate; their
-- unit buttons SecureUnitButtonTemplate -- a click targets, a right click
-- opens the unit's menu):
--   party   you (Show Yourself In Your Party) and your party; you alone while
--           solo (Show Yourself While Solo: the header's own SOLO) -- while In
--           A Party is Group Frames; under Party Frames the game's own in a
--           party, and you alone as a normal party frame (GroupSolo.lua)
--   raid    the raid, one list: by group, role or class, so many per column
--           (or row), the columns (rows) side by side
-- Each in a container on MelloUI's mover (Edit Layout: "Party Frames", "Raid
-- Frames"), where the game's own stand by default. Every button is made out
-- of a fight when the headers are made (the header's startingIndex walked back
-- over all its buttons once), then dressed in Lua (GroupButton.lua): nothing
-- is made in a fight. A header shows by the game's state driver ("[group:raid]
-- hide; show" / "[group:raid] show; hide"), in a fight too. Their layout and
-- the buttons' size are set out of a fight only: a change in a fight waits for
-- its end. A button's unit is the header's (its "unit" attribute, followed by
-- an attribute hook); the units' events reach the buttons that show them.
-- The game's party and raid frames: faded to nothing and click-through, out
-- of a fight; given back when the module goes off. Nothing of theirs is laid
-- out or rebuilt. Under In A Party: Party Frames the game's normal party
-- frames show instead of our party, at the party container's place (Edit
-- Layout's "Party Frames": the party moves there only, whichever frames show
-- it).
--   Headers:Start([first]) / Stop()   on and off; `first`: only the header the
--                              group needs now (the login's first step)
--   Headers:Layout()           the layout settings again (a fight: later)
--   Headers:Repaint()          every button painted again (bus groupframes "paint": the made-up ones too)
--   Headers:Blizzard()         the game's frames hidden or given back
--   Headers:Buttons() -> list  every button made
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_GroupFrames (headers)")
local Shared = Perf.Shared
local hooksecurefunc = Perf.hooksecurefunc
local Text = MelloUI.Safe.Text
local Num = MelloUI.Safe.Number
local ScreenRect = MelloUI.Safe.ScreenRect
local RD = ns.RD
local Button = ns.Button
local Looks = ns.Looks

local H = {}
ns.Headers = H

local TEXT = { party = "Party Frames", raid = "Raid Frames",
	partyNote = "The game's normal party frames stand here too (In A Party: Party Frames): move them here, not in Edit Mode." }
local COUNT = { party = 5, raid = 40 }
local ROLE_ORDER = "TANK,HEALER,DAMAGER,NONE"
local CLASS_ORDER = "WARRIOR,DEATHKNIGHT,PALADIN,MONK,PRIEST,SHAMAN,DRUID,ROGUE,MAGE,WARLOCK,HUNTER,DEMONHUNTER,EVOKER"
local GROUPS = "1,2,3,4,5,6,7,8"

-- (a button made by the header in a fight -- never, all are made before --
-- sized and made clickable in the restricted environment by this snippet)
local INIT = [[
	local header = self:GetParent()
	self:SetWidth(header:GetAttribute("mello-width") or 80)
	self:SetHeight(header:GetAttribute("mello-height") or 40)
	self:SetAttribute("*type1", "target")
	self:SetAttribute("*type2", "togglemenu")
	self:SetAttribute("toggleForVehicle", false)
]]

local S = { made = false, on = false, pending = false, hidden = false }
local containers, headers = {}, {}
local buttons = {}            -- every button made, in order
local byUnit = {}             -- [unit] = { [button] = true }
local mouseOff = setmetatable({}, { __mode = "k" })   -- [game frame] = true: its mouse turned off by us

local function DB()
	return RD.DB()
end

local function Later(fn, key)
	local K = MelloUI.Kit
	if InCombatLockdown() and K and K.WhenOutOfCombat then
		K:WhenOutOfCombat(fn, key)
	elseif not InCombatLockdown() then
		fn()
	end
end

function H:Buttons()
	return buttons
end

--------------------------------------------------------------------------------
-- A button's unit
--------------------------------------------------------------------------------

local function SetUnit(b, unit)
	unit = Text(unit)
	if b.unit == unit then
		return
	end
	if b.unit and byUnit[b.unit] then
		byUnit[b.unit][b] = nil
	end
	b.unit = unit
	if unit then
		byUnit[unit] = byUnit[unit] or {}
		byUnit[unit][b] = true
		Button.Refresh(b)
	end
	if ns.Indicators then
		ns.Indicators:SetUnit(b, unit)
	end
	-- (Healer Frames' heals and debuff glow on it: its unit now)
	local hf = MelloUI:GetModule("HealerFrames")
	if hf and hf.Update then
		pcall(hf.Update, hf, b, b.healthBar)
	end
end

local OnAttribute = Shared("OnAttributeChanged on a group frame", function(b, name, value)
	if name == "unit" then
		SetUnit(b, value)
	end
end, "script")

-- `kind`: its header's ("party": our Group Frames party, laid by its own
-- parts layout -- one look C9 -- "raid": the raid's)
local function Dress(b, kind)
	if b.melloDressed then
		return
	end
	b.melloDressed = true
	b.partsLayout = kind == "party" and "groupParty" or nil
	b:RegisterForClicks("AnyUp")
	Button.Build(b)
	Perf.HookScript(b, "OnAttributeChanged", OnAttribute)
	buttons[#buttons + 1] = b
	-- (1.2.4: the mouseover highlight, MelloUI.FrameHover)
	if MelloUI.FrameHover then
		MelloUI.FrameHover.Attach(b)
	end
	-- the kit's raid dressing (its rail and stone) while the painted skin is on
	local rfp = MelloUI:GetModule("RaidFramePanel")
	if rfp and rfp.DressStandIn then
		pcall(rfp.DressStandIn, rfp, b)
		-- (its border known now: the bars inside it, Kit:RaidFrameInset)
		Button.Lay(b)
	end
	-- Healer Frames' incoming heals and shields after the health, and its debuff
	-- glow round the frame (one system: as on every frame of the game's)
	local hf = MelloUI:GetModule("HealerFrames")
	if hf and hf.Heals then
		pcall(hf.Heals, hf, b.healthBar, function()
			return b.unit
		end)
		pcall(hf.Glow, hf, b)
	end
	if ns.Indicators then
		-- (one look C9b: our party's buttons show the party's own list)
		ns.Indicators:Host(b, nil, Looks.Fill(b.healthBar), b.partsLayout == "groupParty" and "groupParty" or nil)
	end
	SetUnit(b, b:GetAttribute("unit"))
end

--------------------------------------------------------------------------------
-- The containers, their places
--------------------------------------------------------------------------------

-- a region's effective scale (nil: none to read plainly)
local function Scale(region)
	if type(region) ~= "table" or type(region.GetEffectiveScale) ~= "function" then
		return nil
	end
	local ok, s = pcall(region.GetEffectiveScale, region)
	s = ok and Num(s) or nil
	return (s and s > 0) and s or nil
end

-- (retail's fix of 2026-10-25, 1.2.4 here: the user, "we have also fixed the checkbox to show your own party
-- unitframe while in a party") a normal party member's reach past its own rect while Group Frames holds them
-- (StackMembers): under it, its pet's room while the game shows party pets (the showPartyPets CVar: the game's own 26
-- between members then, 10 without -- PartyFrame.lua)
local GAME_MEMBER = { w = 120, h = 53, n = 4, spacing = 10, pet = 16 }
local function PetRoom()
	local get = type(C_CVar) == "table" and C_CVar.GetCVarBool
	local ok, on = false, nil
	if type(get) == "function" then
		ok, on = pcall(get, "showPartyPets")
	end
	return (ok and on == true) and GAME_MEMBER.pet or 0
end

-- the game's normal party frames' footprint in the party container's units:
-- four members (PartyMemberFrameTemplate, 120 x 53) at the party frame's
-- scale with their pets' room, Party Spacing between (StackMembers) -- and
-- you on top with Show Yourself In Your Party (GroupSolo.lua)
local function GameFootprint(sp)
	local pf, c = rawget(_G, "PartyFrame"), containers.party
	local ratio = 1
	local ps, cs = Scale(pf), Scale(c)
	if ps and cs then
		ratio = ps / cs
	end
	local n = GAME_MEMBER.n
	local h = n * (GAME_MEMBER.h + PetRoom()) + (n - 1) * sp
	if DB().showPlayer then
		h = h + GAME_MEMBER.h + sp
	end
	return GAME_MEMBER.w * ratio, h * ratio
end

-- the room between two frames: the party's, or the raid's own (0.20.2)
local function Spacing(kind)
	local db = DB()
	return (kind == "raid" and (db.raidSpacing or db.spacing) or db.spacing) or 0
end
H.Spacing = Spacing

local function Footprint(kind)
	local db = DB()
	local w, h, sp = db.width, db.height, Spacing(kind)
	if kind == "party" and db.partyStyle == "party" then
		-- (the game's normal party frames show at its place: the plate their size)
		return GameFootprint(sp)
	end
	if kind == "party" then
		if db.partyGrowth == "RIGHT" or db.partyGrowth == "LEFT" then
			return 5 * w + 4 * sp, h
		end
		return w, 5 * h + 4 * sp
	end
	local per = math.max(1, db.raidPerLine or 5)
	local lines = math.ceil(COUNT.raid / per)
	if db.raidFlow == "across" then
		return per * w + (per - 1) * sp, lines * h + (lines - 1) * (db.raidGap or 0)
	end
	return lines * w + (lines - 1) * (db.raidGap or 0), per * h + (per - 1) * sp
end

-- where the game's own frames stand (a place to start from)
local function Home(kind)
	return function(c)
		c:ClearAllPoints()
		local us = UIParent:GetEffectiveScale()
		local names = kind == "party" and { "CompactPartyFrame", "PartyFrame" } or { "CompactRaidFrameContainer" }
		for _, name in ipairs(names) do
			local f = rawget(_G, name)
			local l, _, _, t = ScreenRect(f)
			if l and t then
				c:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l / us, t / us)
				return true
			end
		end
		c:SetPoint("TOPLEFT", UIParent, "LEFT", 20, kind == "party" and 220 or 0)
		return true
	end
end
H.Home = Home

local function MakeContainer(kind)
	local c = CreateFrame("Frame", kind == "party" and "MelloUIGroupParty" or "MelloUIGroupRaid", UIParent)
	c:SetSize(Footprint(kind))
	c:SetFrameStrata("LOW")
	local key = kind == "party" and "GroupFramesParty" or "GroupFramesRaid"
	-- (0.20.2 - 0.24: the box held the party's spacing, the raid's and its groups' gap; one look C4: they are the
	-- configurator's, its "Design >" link)
	MelloUI:RegisterMover(c, c, { key = key, default = Home(kind), label = TEXT[kind], page = RD.module.name,
		placeholder = true, when = function()
			return RD.module.isEnabled and true or false
		end, note = kind == "party" and function()
			return DB().partyStyle == "party" and TEXT.partyNote or nil
		end or nil })
	if not MelloUI:RestorePosition(key, c) then
		Home(kind)(c)
	end
	containers[kind] = c
	-- (0.21.3) made after the Fader faded the group's frames (at login: the
	-- party's box a frame after the module comes on, the raid's after the
	-- login): its fade at once
	local F = MelloUI.Fader
	if F and F.Refade then
		F:Refade(kind)
	end
	return c
end

--------------------------------------------------------------------------------
-- The headers' attributes
--------------------------------------------------------------------------------

local function Set(h, name, value)
	if h:GetAttribute(name) ~= value then
		h:SetAttribute(name, value)
	end
end

local function Sorting(h, kind)
	local db = DB()
	local by, order, method, filter = nil, nil, "INDEX", nil
	if kind == "party" then
		if db.partySort == "role" then
			by, order = "ASSIGNEDROLE", ROLE_ORDER
		elseif db.partySort == "name" then
			method = "NAME"
		end
	else
		filter = GROUPS
		if db.raidGroupBy == "group" then
			by, order = "GROUP", GROUPS
		elseif db.raidGroupBy == "role" then
			by, order = "ASSIGNEDROLE", ROLE_ORDER
		elseif db.raidGroupBy == "class" then
			by, order = "CLASS", CLASS_ORDER
		end
	end
	Set(h, "groupFilter", filter)
	Set(h, "groupBy", by)
	Set(h, "groupingOrder", order)
	Set(h, "sortMethod", method)
end

local ANCHOR = { DOWN = "TOPLEFT", UP = "BOTTOMLEFT", RIGHT = "TOPLEFT", LEFT = "TOPRIGHT" }

local function Attributes(kind)
	local h, c = headers[kind], containers[kind]
	local db = DB()
	local sp = Spacing(kind)
	Set(h, "mello-width", db.width)
	Set(h, "mello-height", db.height)
	if kind == "party" then
		local g = db.partyGrowth or "DOWN"
		Set(h, "showParty", true)
		Set(h, "showRaid", false)
		Set(h, "showPlayer", db.showPlayer and true or false)
		Set(h, "showSolo", db.solo and true or false)
		local point = (g == "DOWN" and "TOP") or (g == "UP" and "BOTTOM") or (g == "RIGHT" and "LEFT") or "RIGHT"
		Set(h, "point", point)
		Set(h, "xOffset", (g == "RIGHT" and sp) or (g == "LEFT" and -sp) or 0)
		Set(h, "yOffset", (g == "DOWN" and -sp) or (g == "UP" and sp) or 0)
		Set(h, "unitsPerColumn", 5)
		Set(h, "maxColumns", 1)
		h:ClearAllPoints()
		local a = ANCHOR[g] or "TOPLEFT"
		h:SetPoint(a, c, a, 0, 0)
	else
		local per = math.max(1, db.raidPerLine or 5)
		Set(h, "showRaid", true)
		Set(h, "showParty", false)
		Set(h, "showPlayer", true)
		Set(h, "showSolo", false)
		if db.raidFlow == "across" then
			Set(h, "point", "LEFT")
			Set(h, "xOffset", sp)
			Set(h, "yOffset", 0)
			Set(h, "columnAnchorPoint", "TOP")
		else
			Set(h, "point", "TOP")
			Set(h, "xOffset", 0)
			Set(h, "yOffset", -sp)
			Set(h, "columnAnchorPoint", "LEFT")
		end
		Set(h, "columnSpacing", db.raidGap or 0)
		Set(h, "unitsPerColumn", per)
		Set(h, "maxColumns", math.ceil(COUNT.raid / per))
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
	end
	Sorting(h, kind)
	c:SetSize(Footprint(kind))
end

-- every button's size and dressing as the settings say
local function SizeButtons()
	local db = DB()
	for _, b in ipairs(buttons) do
		b:SetSize(db.width, db.height)
		Button.Lay(b)
	end
end

local function MakeHeader(kind)
	local c = containers[kind] or MakeContainer(kind)
	local name = kind == "party" and "MelloUIGroupPartyHeader" or "MelloUIGroupRaidHeader"
	local h = CreateFrame("Frame", name, c, "SecureGroupHeaderTemplate")
	h:SetAttribute("template", "SecureUnitButtonTemplate")
	h:SetAttribute("initialConfigFunction", INIT)
	headers[kind] = h
	Attributes(kind)
	-- every button made now (out of a fight): the header walks back over all of
	-- them once, then shows from the first again
	local n = COUNT[kind]
	h:SetAttribute("startingIndex", -(n - 1))
	h:Show()
	h:SetAttribute("startingIndex", 1)
	-- (every button it made: a unit already shown -- you, solo -- makes it one
	-- more than asked, as the game's header counts)
	local i = 1
	while true do
		local b = h[i] or h:GetAttribute("child" .. i)
		if not b then
			break
		end
		Dress(b, kind)
		i = i + 1
	end
	return h
end

-- (In A Party: Group Frames -- ours in a party and solo -- or Party Frames: the
-- game's normal party frames in a party, and solo the normal party frame of
-- ours, GroupSolo.lua: this header never)
local function PartyRule()
	return DB().partyStyle == "party" and "hide" or "[group:raid] hide; show"
end

local function SoloUpdate()
	if ns.Solo then
		ns.Solo:Update()
	end
end

local function Drive(on)
	for kind, h in pairs(headers) do
		if on then
			RegisterStateDriver(h, "visibility", kind == "party" and PartyRule() or "[group:raid] show; hide")
		else
			UnregisterStateDriver(h, "visibility")
			h:Hide()
		end
	end
	for _, c in pairs(containers) do
		c:SetShown(on)
	end
end

--------------------------------------------------------------------------------
-- The game's own frames: faded and click-through, or given back
--------------------------------------------------------------------------------

-- the game's party members (its normal party frames: PartyFrame's pool)
local function PartyMembers(fn)
	local pf = rawget(_G, "PartyFrame")
	if type(pf) == "table" and pf.PartyMemberFramePool then
		for f in pf.PartyMemberFramePool:EnumerateActive() do
			fn(f)
		end
	end
end

local function GameMembers(fn)
	for i = 1, 5 do
		fn(rawget(_G, "CompactPartyFrameMember" .. i))
	end
	for i = 1, 40 do
		fn(rawget(_G, "CompactRaidFrame" .. i))
	end
	for g = 1, 8 do
		for i = 1, 5 do
			fn(rawget(_G, "CompactRaidGroup" .. g .. "Member" .. i))
		end
	end
end

local GAME_HOLDERS = { "CompactPartyFrame", "CompactRaidFrameContainer", "CompactRaidFrameManager", "PartyFrame" }

local function MouseOff(f)
	if type(f) == "table" and f.EnableMouse and f.IsMouseEnabled then
		local ok, on = pcall(f.IsMouseEnabled, f)
		if ok and on then
			pcall(f.EnableMouse, f, false)
			mouseOff[f] = true
		end
	end
end

local function MouseBack(f)
	if mouseOff[f] then
		pcall(f.EnableMouse, f, true)
		mouseOff[f] = nil
	end
end

-- A few parts of the game's frames ignore their parent's alpha (the game's templates: CompactUnitFrame.xml's target
-- highlight -- the yellow RaidFrame-TargetFrame box -- and its ready check icon; the normal party frame's
-- NotPresentIcon). With the holders at alpha 0 they still showed where the game's hidden frame stands: the users'
-- "random square" (2026-10-14), a yellow box whenever that frame's unit was the target. While ours stand in they
-- follow their parent's alpha; the template's own setting comes back with the frames. (The game never sets it at
-- run time: nothing it writes is undone, no write a frame.)
local loose = setmetatable({}, { __mode = "k" })   -- [game region] = true: made to follow its parent's alpha by us
local LOOSE_KEYS = { "selectionHighlight", "readyCheckIcon", "NotPresentIcon" }

local function Tie(region)
	if type(region) == "table" and region.SetIgnoreParentAlpha and not loose[region] then
		local ok, ignoring = pcall(region.IsIgnoringParentAlpha, region)
		if ok and ignoring == true then
			pcall(region.SetIgnoreParentAlpha, region, false)
			loose[region] = true
		end
	end
end

local function TieLoose(f)
	if type(f) ~= "table" then
		return
	end
	for _, key in ipairs(LOOSE_KEYS) do
		local r = f[key]
		Tie(r)
		if type(r) == "table" then
			Tie(r.Icon)   -- (the ready check icon's picture ignores its frame's alpha too)
		end
	end
end

local function UntieLoose()
	for r in pairs(loose) do
		pcall(r.SetIgnoreParentAlpha, r, true)
		loose[r] = nil
	end
end

-- the game's own frames give way to ours (the user, 2026-10-09: "i want these
-- frames to be the main ones"): always its raid frames, its raid-style party
-- frames and its raid manager; its normal party frames too, unless they are
-- the player's choice for a party (In A Party: Party Frames)
local function GameParty()
	return DB().partyStyle == "party"
end

local function HideGame()
	S.hidden = true
	local party = GameParty()
	for _, name in ipairs(GAME_HOLDERS) do
		local f = rawget(_G, name)
		if type(f) == "table" and f.SetAlpha then
			pcall(f.SetAlpha, f, (name == "PartyFrame" and party) and 1 or 0)
		end
	end
	MouseOff(rawget(_G, "CompactRaidFrameManager"))
	GameMembers(MouseOff)
	PartyMembers(party and MouseBack or MouseOff)
	-- (the parts that ignore their parent's alpha: tied to it on every frame that is hidden, the normal party frames
	-- only while they are not the choice; again on each roster change, the game's new frames with them)
	UntieLoose()
	GameMembers(TieLoose)
	if not party then
		PartyMembers(TieLoose)
	end
end

local TinyRoles   -- (below: the game's tiny role icons back)

local function ShowGame()
	S.hidden = false
	TinyRoles()
	for _, name in ipairs(GAME_HOLDERS) do
		local f = rawget(_G, name)
		if type(f) == "table" and f.SetAlpha then
			pcall(f.SetAlpha, f, 1)
		end
	end
	for f in pairs(mouseOff) do
		pcall(f.EnableMouse, f, true)
		mouseOff[f] = nil
	end
	UntieLoose()
end

--------------------------------------------------------------------------------
-- The normal party frames' place: Edit Layout's (the user, 2026-10-09: "why
-- are we moving the raid frames with the Edit Layout MelloUI option, and the
-- normal Party Frames with Edit mode, both of them need to be only moveable
-- with Edit Layout")
-- While they are the choice for a party, the game's party frame stands at the
-- party container's top left -- Edit Layout's "Party Frames" plate, one place
-- for the party whichever frames show it (the solo frame of ours there too,
-- GroupSolo.lua) -- and the container takes their size, so the plate is what
-- shows. Laid with the plain methods Edit Mode keeps aside (ClearAllPointsBase
-- / SetPointBase: hard rule 2, nothing of Edit Mode's runs), at the
-- container's place on the screen (hung from UIParent, never from a frame of
-- ours: Edit Mode reads its anchor back); laid again after the container
-- moves, after Edit Mode lays it (its layout applied, a drag in Edit Mode put
-- back), when Edit Mode closes and on a UI scale change -- out of a fight.
-- Given back (the module off, Group Frames chosen): the place it had when
-- first taken.
--------------------------------------------------------------------------------
local held = { on = false, placing = false, home = nil, hooked = false }
local PlaceParty   -- (below: held or given back, as the choice is now)

local function Base(frame, method)
	local fn = frame[method .. "Base"] or frame[method]
	return type(fn) == "function" and fn or nil
end

local function LayGame(pf, ...)
	local clear, set = Base(pf, "ClearAllPoints"), Base(pf, "SetPoint")
	if not (clear and set) then
		return false
	end
	held.placing = true
	local ok = pcall(clear, pf) and pcall(set, pf, ...)
	held.placing = false
	return ok
end

local function PlaceLater()
	Later(PlaceParty, "Group Frames: the normal party frames' place")
end

-- (1.2.4, the user's retail test, 2026-10-27: party portraits "set on EditMode to 100%, and on the Edit Layout 100%
-- and they are miniature" -- their pick, bigger by default) the game's party frames held at Edit Mode's own size
-- times Edit Layout's (the party container's scale) times PORTRAIT_BASE: about the player frame's height at 100% and
-- 100%; Edit Mode's size read from its own writes (held.gameScale, the post-hooks below), put back when let go. Out
-- of a fight only (the frame's geometry is the game's protected party's)
held.PORTRAIT_BASE = 1.4
local function ScaleGame(pf, c)
	local set = Base(pf, "SetScale")
	if not set or InCombatLockdown() then
		return
	end
	if held.gameScale == nil then
		local ok, s = pcall(pf.GetScale, pf)
		held.gameScale = ok and Num(s) or 1
	end
	local cs, ps = Scale(c), Scale(pf:GetParent())
	local rel = (cs and ps and ps > 0) and cs / ps or 1
	held.scaling = true
	pcall(set, pf, held.gameScale * rel * held.PORTRAIT_BASE)
	held.scaling = false
end
-- Edit Mode sized the party frame (its Frame Size): that size kept as the game's, the frame held again
local function OnGameScaled(_, scale)
	if held.on and not held.scaling then
		held.gameScale = Num(scale) or held.gameScale
		PlaceLater()
	end
end

-- (Edit Mode laid it, or the container moved: laid again, out of a fight)
local function OnGameLaid()
	if held.on and not held.placing then
		PlaceLater()
	end
end

-- the game's members stacked as its own Layout stacks them (VerticalLayoutFrame: shown ones by layoutIndex, TOPLEFT
-- at its padding, down from its top), each with its pet's room under it (`rooms`) and `spacing` between -- under you
-- with Show Yourself In Your Party (GroupSolo.lua: your frame of ours in the first member's place). Held: Party
-- Spacing, laid after the game's every Layout (the post-hook in HoldGameParty: the roster, pets, Edit Mode -- events,
-- never per frame); given back: the game's own spacing, as its next Layout lays them. Only a member whose point
-- differs is laid; out of a fight (the callers' Later). Nothing of the game's is called or written
local function StackMembers(pf, spacing, rooms)
	local list = {}
	PartyMembers(function(m)
		local ok, shown = pcall(m.IsShown, m)
		if ok and shown == true and Num(rawget(m, "layoutIndex")) then
			list[#list + 1] = m
		end
	end)
	table.sort(list, function(a, b)
		return rawget(a, "layoutIndex") < rawget(b, "layoutIndex")
	end)
	local left = Num(rawget(pf, "leftPadding")) or 0
	local y = Num(rawget(pf, "topPadding")) or 0
	local down = rooms and PetRoom() or 0
	if rooms and ns.Solo and ns.Solo.InParty() then
		local me = ns.Solo.frame
		local okH, h = false, nil
		if me then
			okH, h = pcall(me.GetHeight, me)
		end
		y = y + (okH and Num(h) or GAME_MEMBER.h) + spacing
	end
	for _, m in ipairs(list) do
		local okN, n = pcall(m.GetNumPoints, m)
		local okP, p, rel, rp, x, oy = pcall(m.GetPoint, m, 1)
		x, oy = okP and Num(x), okP and Num(oy)
		if not (okN and n == 1 and p == "TOPLEFT" and rel == pf and rp == "TOPLEFT" and x and oy
			and math.abs(x - left) < 0.01 and math.abs(oy + y) < 0.01) then
			pcall(m.ClearAllPoints, m)
			pcall(m.SetPoint, m, "TOPLEFT", pf, "TOPLEFT", left, -y)
		end
		local okH, h = pcall(m.GetHeight, m)
		y = y + (okH and Num(h) or GAME_MEMBER.h) + down + spacing
	end
end

local function HoldGameParty()
	local pf, c = rawget(_G, "PartyFrame"), containers.party
	if not (type(pf) == "table" and c and type(pf.GetPoint) == "function") then
		return
	end
	if not held.home then
		local ok, p, rel, rp, x, y = pcall(pf.GetPoint, pf, 1)
		if ok and Text(p) and Text(rp) and Num(x) and Num(y) then
			held.home = { Text(p), type(rel) == "table" and rel or UIParent, Text(rp), Num(x), Num(y) }
		end
	end
	local l, _, _, t = ScreenRect(c)
	local s = Scale(pf)
	if not (l and t and s) then
		return
	end
	held.on = true
	LayGame(pf, "TOPLEFT", UIParent, "BOTTOMLEFT", l / s, t / s)
	StackMembers(pf, Spacing("party"), true)
	if not held.hooked then
		held.hooked = true
		hooksecurefunc(pf, "SetPoint", OnGameLaid)
		hooksecurefunc(c, "SetPoint", OnGameLaid)
		hooksecurefunc(pf, "SetScale", OnGameScaled)
		if type(pf.SetScaleBase) == "function" then
			hooksecurefunc(pf, "SetScaleBase", OnGameScaled)
		end
		-- (the game stacked its members again -- a roster change, a pet, Edit Mode: Party Spacing again)
		if type(pf.Layout) == "function" then
			hooksecurefunc(pf, "Layout", OnGameLaid)
		end
	end
end

local function FreeGameParty()
	if not held.on then
		return
	end
	held.on = false
	local pf, h = rawget(_G, "PartyFrame"), held.home
	if type(pf) == "table" and h then
		LayGame(pf, h[1], h[2], h[3], h[4], h[5])
		StackMembers(pf, Num(rawget(pf, "spacing")) or GAME_MEMBER.spacing, false)
	end
	-- (the game's own size back)
	local set = type(pf) == "table" and Base(pf, "SetScale")
	if set and held.gameScale and not InCombatLockdown() then
		held.scaling = true
		pcall(set, pf, held.gameScale)
		held.scaling = false
		held.gameScale = nil
	end
end

PlaceParty = function()
	local c = containers.party
	local holding = S.on and S.made and GameParty()
	local pf = rawget(_G, "PartyFrame")
	if holding and c and type(pf) == "table" then
		ScaleGame(pf, c)   -- (first: the plate's size follows the frames' -- GameFootprint)
	end
	if c then
		c:SetSize(Footprint("party"))
	end
	if holding then
		HoldGameParty()
	else
		FreeGameParty()
	end
end

function H:Blizzard()
	Later(function()
		if S.on then
			HideGame()
		elseif S.hidden then
			ShowGame()
		end
	end, "Group Frames: the game's frames")
end

-- the game's party members' role icon sharp (the user, 2026-10-09: "the role
-- icons on the unitframes are too low resolution"; pick B): the round badge
-- Group Frames show (Button.RoleAtlas) put on the game's own icon right after
-- the game sets its tiny one -- a post-hook on the member's role update, which
-- the game runs on its group events, never per frame -- and the tiny one back
-- when the frames give the game's back
local TINY_ROLE = { ["roleicon-tiny-tank"] = "TANK", ["roleicon-tiny-healer"] = "HEALER",
	["roleicon-tiny-dps"] = "DAMAGER" }
local SHARP_TINY = {}   -- [sharp atlas] = the game's tiny one (filled as met)
local roleHooked = setmetatable({}, { __mode = "k" })

local function RoleIconOf(m)
	local ov = rawget(m, "PartyMemberOverlay")
	local icon = type(ov) == "table" and rawget(ov, "RoleIcon") or nil
	return type(icon) == "table" and icon.SetAtlas and icon or nil
end

local function AtlasOf(icon)
	local ok, atlas = pcall(icon.GetAtlas, icon)
	return ok and Text(atlas) or nil
end

local function SharpRole(m)
	if not (S.on and GameParty()) then
		return
	end
	local icon = RoleIconOf(m)
	local tiny = icon and AtlasOf(icon)
	local role = tiny and TINY_ROLE[tiny:lower()]
	local sharp = role and Button.RoleAtlas(role)
	if sharp and sharp ~= tiny then
		SHARP_TINY[sharp] = tiny
		pcall(icon.SetAtlas, icon, sharp)
	end
end

local function HookRole(m)
	if roleHooked[m] or type(m.UpdateAssignedRoles) ~= "function" then
		return
	end
	roleHooked[m] = true
	hooksecurefunc(m, "UpdateAssignedRoles", SharpRole)
end

TinyRoles = function()
	PartyMembers(function(m)
		local icon = RoleIconOf(m)
		local atlas = icon and AtlasOf(icon)
		local tiny = atlas and SHARP_TINY[atlas]
		if tiny then
			pcall(icon.SetAtlas, icon, tiny)
		end
	end)
end

--------------------------------------------------------------------------------
-- (retail, never shipped: the user, 2026-10-24, on the Portraits look -- "this
-- mouseover container that shows the buffs instead of just showing them under
-- it, which makes it a problem to click cast heal", and Out Of Range Opacity
-- doing nothing there) while the game's normal party members are the choice:
-- their buffs in a row under them (GroupSolo.lua's Solo.BuffRow) and the
-- game's mouseover box of them put away as it shows (PartyMemberBuffTooltip:
-- over the frames, it took the clicks); out of range faded as our own frames
-- are (Button.RangeAlpha), never over the game's own fade (a member phased or
-- in another group: its NotPresentIcon). WoW Forever as before.
--------------------------------------------------------------------------------
local ranged = setmetatable({}, { __mode = "k" })   -- [member] = faded by us
local notPresentHooked = setmetatable({}, { __mode = "k" })

local function RetailParty()
	return RD.Retail() and S.on and GameParty()
end

local function MemberRange(f)
	if not RetailParty() then
		return
	end
	local unit = Text(rawget(f, "unit"))
	local np = rawget(f, "NotPresentIcon")
	if not unit or (type(np) == "table" and np.IsShown and np:IsShown()) then
		return
	end
	local alpha = DB().rangeAlpha or 0.45
	if alpha >= 1 then
		if ranged[f] then
			ranged[f] = nil
			f:SetAlpha(1)
		end
		return
	end
	ranged[f] = true
	Button.RangeAlpha(f, unit, alpha)
end

-- every member back to the game's own (the choice changed, the module off)
local function MembersBack()
	for f in pairs(ranged) do
		ranged[f] = nil
		pcall(f.SetAlpha, f, 1)
	end
	if ns.Solo and ns.Solo.BuffRowsOn then
		ns.Solo.BuffRowsOn(false)
	end
end

local function RetailMember(f, unit)
	if not RetailParty() then
		return
	end
	if ns.Solo and ns.Solo.BuffRow and ns.Solo.BuffRow(f, unit) then
		ns.Solo.BuffRowsOn(true)
	end
	if not notPresentHooked[f] and type(f.UpdateNotPresentIcon) == "function" then
		notPresentHooked[f] = true
		-- (the game sets the member's alpha there: ours again after it -- its events, never per frame)
		hooksecurefunc(f, "UpdateNotPresentIcon", MemberRange)
	end
	MemberRange(f)
end

local tipHooked = false
local function HookBuffTip()
	local tip = rawget(_G, "PartyMemberBuffTooltip")
	if tipHooked or not RD.Retail() or type(tip) ~= "table" or type(tip.HookScript) ~= "function" then
		return
	end
	tipHooked = true
	Perf.HookScript(tip, "OnShow", Shared("the game's party buff box put away", function(self)
		if RetailParty() then
			self:Hide()
		end
	end, "script"))
end

-- the game's normal party members as hosts of the indicators (while they are
-- the choice for a party): the unit theirs, the health tint over their bar
local function PartyHosts()
	if not (ns.Indicators and GameParty()) then
		return
	end
	PartyMembers(function(f)
		local hc = rawget(f, "HealthBarContainer")
		local hb = type(hc) == "table" and rawget(hc, "HealthBar") or nil
		ns.Indicators:Host(f, Text(rawget(f, "unit")), Looks.Fill(hb), "party")
		-- (and their parts as the Designer moved them, their role icon sharp)
		if ns.Parts then
			ns.Parts:HookMember(f)
			ns.Parts:Lay(f, "party")
		end
		HookRole(f)
		SharpRole(f)
		RetailMember(f, Text(rawget(f, "unit")))
	end)
end

-- each of the game's party members now, and the solo party frame of ours
-- (fn(frame, own): the Designer's party parts)
function H:EachPartyMember(fn)
	PartyMembers(fn)
	local solo = ns.Solo and ns.Solo.frame
	if solo then
		fn(solo, true)
	end
end

-- In A Party changed: the party header's rule, the game's frames, the hosts
function H:Style()
	Later(function()
		if S.on and S.made then
			Drive(true)
			HideGame()
			PartyHosts()
		end
		-- (retail: Group Frames the choice now -- the members' own alpha and no buff rows)
		if not (S.on and GameParty()) then
			MembersBack()
		end
		PlaceParty()
		SoloUpdate()
	end, "Group Frames: In A Party")
end

-- a normal party frame's health bar, portrait and the painted ring over it
-- while the unit frame skin dresses it (Unit Frames' M:RingOf -- as Healer
-- Frames' glow), else nil
local function PartyParts(f)
	local hc = rawget(f, "HealthBarContainer")
	local portrait = rawget(f, "Portrait")
	local panel = MelloUI:GetModule("UnitFrames")
	local okR, ring = false, nil
	if portrait and panel and panel.RingOf then
		okR, ring = pcall(panel.RingOf, panel, portrait)
	end
	return type(hc) == "table" and rawget(hc, "HealthBar") or nil, portrait, okR and ring or nil
end

local function PartyEntry(f, unit)
	local health, portrait, ring = PartyParts(f)
	return { frame = f, unit = unit, health = health, kind = "party", portrait = portrait, ring = ring }
end

-- every frame that shows a member now, for every feature that marks one (Heal
-- Flight, Frame Effects): { frame, unit, health, kind } -- ours shown with a
-- unit, and the normal party frames while they are the choice for a party:
-- the game's members, and you alone as one of ours (GroupSolo.lua) -- theirs
-- also `portrait`, the portrait texture, and `ring`, the painted ring over it
-- while the unit frame skin dresses it, else nil.
-- A fresh list each call: read it, never keep it
function H:Hosts()
	local out = {}
	for _, b in ipairs(buttons) do
		if b.unit and b:IsVisible() then
			out[#out + 1] = { frame = b, unit = b.unit, health = b.healthBar, kind = "group" }
		end
	end
	if GameParty() then
		PartyMembers(function(f)
			local unit = Text(rawget(f, "unit"))
			if unit and f:IsVisible() then
				out[#out + 1] = PartyEntry(f, unit)
			end
		end)
		local solo = ns.Solo and ns.Solo:Shown()
		if solo then
			out[#out + 1] = PartyEntry(solo, solo.unit)
		end
	end
	return out
end

-- one member's frame (the effects ask it on every cast and tick: Frame Effects'
-- FX.FrameOf): looked up, nothing made -- ONE entry table reused for every
-- answer, so read it at once and never keep it (rule 7: nothing per event)
local found = {}
local function Found(frame, unit, kind, health, portrait, ring)
	found.frame, found.unit, found.health, found.kind = frame, unit, health, kind
	found.portrait, found.ring = portrait, ring
	return found
end

function H:HostOf(unit)
	unit = Text(unit)
	if not unit then
		return nil
	end
	local set = byUnit[unit]
	if set then
		for b in pairs(set) do
			if b:IsVisible() then
				return Found(b, unit, "group", b.healthBar, nil, nil)
			end
		end
	end
	if not GameParty() then
		return nil
	end
	-- (you alone: the solo party frame of ours)
	local solo = ns.Solo and ns.Solo:Shown()
	if solo and solo.unit == unit then
		return Found(solo, unit, "party", PartyParts(solo))
	end
	local pf = rawget(_G, "PartyFrame")
	if not (type(pf) == "table" and pf.PartyMemberFramePool) then
		return nil
	end
	for f in pf.PartyMemberFramePool:EnumerateActive() do
		if Text(rawget(f, "unit")) == unit and f:IsVisible() then
			return Found(f, unit, "party", PartyParts(f))
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local UNIT_PAINT = {
	UNIT_HEALTH = "Health", UNIT_MAXHEALTH = "Health", UNIT_CONNECTION = "Refresh", UNIT_FLAGS = "Health",
	UNIT_POWER_UPDATE = "Power", UNIT_MAXPOWER = "Power", UNIT_DISPLAYPOWER = "Power",
	UNIT_NAME_UPDATE = "Name", UNIT_IN_RANGE_UPDATE = "Range", UNIT_PHASE = "Range",
}

local function Each(fn, ...)
	for _, b in ipairs(buttons) do
		if b.unit then
			fn(b, ...)
		end
	end
end

local events = nil
local OnEvent = Shared("the group frames' events", function(_, event, unit, ...)
	if not S.on then
		return
	end
	local paint = UNIT_PAINT[event]
	if paint then
		local set = unit and byUnit[Text(unit) or ""]
		if set then
			for b in pairs(set) do
				Button[paint](b)
			end
		end
		-- (retail: the game's normal party member of that unit faded as ours)
		if paint == "Range" and RD.Retail() and GameParty() then
			local u = Text(unit)
			PartyMembers(function(f)
				if u and Text(rawget(f, "unit")) == u then
					MemberRange(f)
				end
			end)
		end
		return
	end
	if event == "PLAYER_REGEN_ENABLED" then
		if S.pending then
			H:Layout()
		end
		H:Blizzard()
		-- (retail: a member's buff row asked for in the fight, made now)
		if RetailParty() then
			PartyHosts()
		end
	elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "PLAYER_ENTERING_WORLD" then
		Each(Button.Refresh)
		if S.hidden then
			H:Blizzard()
		end
		PartyHosts()
	elseif event == "RAID_TARGET_UPDATE" then
		Each(Button.Mark)
	elseif event == "READY_CHECK" or event == "READY_CHECK_CONFIRM" then
		Each(Button.Ready)
	elseif event == "READY_CHECK_FINISHED" then
		-- (the marks stay a few seconds, as the game's)
		C_Timer.After(6, function()
			Each(Button.Ready, false)
		end)
	end
end, "script")

local EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_FLAGS", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER",
	"UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_IN_RANGE_UPDATE", "UNIT_PHASE", "PLAYER_REGEN_ENABLED",
	"GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_ENTERING_WORLD", "RAID_TARGET_UPDATE", "READY_CHECK",
	"READY_CHECK_CONFIRM", "READY_CHECK_FINISHED" }

local function Listen()
	if events then
		return
	end
	events = CreateFrame("Frame")
	for _, e in ipairs(EVENTS) do
		pcall(events.RegisterEvent, events, e)
	end
	Perf.SetScript(events, "OnEvent", OnEvent)
	-- (retail: the game's mouseover box of the party's buffs put away while its members are the choice)
	HookBuffTip()
	-- the game's members made later (a raid formed): click-through too while hidden
	if type(rawget(_G, "DefaultCompactUnitFrameSetup")) == "function" then
		hooksecurefunc("DefaultCompactUnitFrameSetup", function(frame)
			if S.hidden then
				Later(function()
					if S.hidden then
						MouseOff(frame)
					end
				end)
			end
		end)
	end
	-- Edit Mode closed (its own place laid on the party frame meanwhile), the
	-- UI's scale changed: the normal party frames at the container again
	MelloUI:On("editmode", function(entering)
		if not entering and held.on then
			PlaceLater()
		end
	end, "GroupFrames.party")
	MelloUI:On("scale", function()
		if held.on then
			PlaceLater()
		end
	end, "GroupFrames.party")
	-- the bar look (Bar Textures) changed: the fills again
	MelloUI.Widgets.OnBarTexture("raidframes", function()
		H:Repaint()
	end, "GroupFrames.bars")
	-- (one look Q7) the one Health Colour or one of its colours changed (Bar
	-- Textures' keys): the bars again
	MelloUI:On("setting", function(module, key)
		if module == "BarTextures" and RD.HEALTH_KEYS[key] then
			H:Repaint()
		end
	end, "GroupFrames.health")
	-- the raid frames' border changed (Raid Frame Border, its placement): the
	-- bars inside it again (Kit:RaidFrameInset; the kit lays borders out of a fight)
	MelloUI:On("raidborder", function()
		for _, b in ipairs(buttons) do
			Button.Lay(b)
		end
	end, "GroupFrames.border")
	-- (1.2.4) the skin switched (MelloUI.Skin): the cells in its look (the Default skin's: the game's raid frame)
	MelloUI:On("skin", function()
		H:Repaint()
	end, "GroupFrames.skin")
end

--------------------------------------------------------------------------------
-- On, off, layout, repaint
--------------------------------------------------------------------------------

function H:Layout()
	if not S.made then
		return
	end
	if InCombatLockdown() then
		S.pending = true
		return
	end
	S.pending = false
	for kind in pairs(headers) do
		Attributes(kind)
	end
	SizeButtons()
	Each(Button.Refresh)
	PlaceParty()
	SoloUpdate()
	MelloUI:Fire("groupframes", "layout")
end

function H:Repaint()
	for _, b in ipairs(buttons) do
		Button.Lay(b)
		if b.unit then
			Button.Refresh(b)
		end
	end
	-- (retail: the game's normal party members' fade as Out Of Range Opacity is now)
	if RetailParty() then
		PartyMembers(MemberRange)
	end
	-- (0.20.1) the made-up members too: the Designer's samples, the fake raid
	MelloUI:Fire("groupframes", "paint")
end

-- (0.21.3; the user, 2026-10-13: "when i do /reload it takes a second before
-- the party frames are loaded in" -- every header waited for the login's
-- settling seconds) `first`: only the header the group needs now -- the
-- party's few buttons, or the raid's 40 while in a raid -- made at once (the
-- module's first frame at login); the other with the rest after the login
-- (both together cost the login's frames too much: the game's 1000 ms
-- budget). `S.made`: a header made (what lays out loops over those there)
local KINDS = { "party", "raid" }

function H:Start(first)
	S.on = true
	Listen()
	Later(function()
		if not S.on then
			return
		end
		local had = S.made
		for _, kind in ipairs(first and { IsInRaid() and "raid" or "party" } or KINDS) do
			if not headers[kind] then
				MakeHeader(kind)
			end
		end
		S.made = true
		if had then
			H:Layout()
		end
		Drive(true)
		H:Blizzard()
		PartyHosts()
		PlaceParty()
		SoloUpdate()
	end, first and "Group Frames: the group's header" or "Group Frames: the headers")
end

function H:Stop()
	S.on = false
	Later(function()
		if S.on then
			return
		end
		Drive(false)
		PlaceParty()
		SoloUpdate()
		if S.hidden then
			ShowGame()
		end
		MembersBack()
	end, "Group Frames: the headers off")
end

-- (the tests')
H.S = S
H.headers, H.containers, H.byUnit = headers, containers, byUnit
H.loose = loose
H.ranged = ranged

--------------------------------------------------------------------------------
-- /run MelloUI.GroupFrames.DumpParty() (the user, 2026-10-24: on the Portraits
-- look the name's and the level's size "dont work"): every normal party frame
-- -- the game's members, your solo one, the Designer's replica -- its name and
-- level as they are (font, size, place), the parts the Designer keeps for
-- them, its alpha and range, its buff row. Into the copy window, opened;
-- nothing changed. (No slash command of its own: a dump is a mode of a shared
-- one -- Tools/lint/check_panels.py's dump-slash -- and the shared one is
-- Oldschool's, which retail has not)
--------------------------------------------------------------------------------
function RD.DumpParty()
	MelloUI:ClearLog()
	local function S_(v)
		if MelloUI.Safe.IsSecret(v) then
			return "<secret>"
		end
		return tostring(v)
	end
	local function Font(fs)
		if type(fs) ~= "table" or type(fs.GetFont) ~= "function" then
			return "none"
		end
		local ok, file, size, flags = pcall(fs.GetFont, fs)
		local okP, p, rel, rp, x, y = pcall(fs.GetPoint, fs, 1)
		local relName = okP and type(rel) == "table" and rel.GetName and rel:GetName() or "?"
		local face = ok and (MelloUI.Safe.IsSecret(file) and "<secret>" or tostring(file):match("[^\\/]+$")) or "?"
		return string.format("%s size %s %s | %s>%s:%s(%s,%s) shown %s alpha %s", face,
			ok and S_(size) or "?", ok and S_(flags) or "", okP and S_(p) or "?", S_(relName), okP and S_(rp) or "?",
			okP and S_(x) or "?", okP and S_(y) or "?", S_(fs:IsShown()), S_(fs:GetAlpha()))
	end
	local function Part(key)
		local P = ns.Parts
		local t = P and P:Of(key)
		if type(t) ~= "table" then
			return "default"
		end
		return string.format("%s %s,%s size %s show %s", S_(t.point), S_(t.x), S_(t.y), S_(t.size), S_(t.show))
	end
	local db = DB()
	MelloUI:Print("Group Frames on %s  retail %s  In A Party %s  solo %s  Out Of Range Opacity %s  buff box hooked %s",
		S_(S.on), S_(RD.Retail()), S_(db.partyStyle), S_(db.solo), S_(db.rangeAlpha), S_(tipHooked))
	MelloUI:Print("parts: name [%s]  level [%s]  buffs [%s]", Part("party.name"), Part("party.level"), Part("party.buffs"))
	local uf = MelloUI:GetModule("UnitFrames")
	local function One(label, f)
		if type(f) ~= "table" then
			MelloUI:Print("%s: none", label)
			return
		end
		local unit = rawget(f, "unit")
		local okR, inRange, checked = false, nil, nil
		if type(unit) == "string" then
			okR, inRange, checked = pcall(UnitInRange, unit)
		end
		MelloUI:Print("%s: unit %s shown %s alpha %s range %s/%s ours %s", label, S_(unit), S_(f:IsShown()), S_(f:GetAlpha()),
			okR and S_(inRange) or "-", okR and S_(checked) or "-", S_(ranged[f] or false))
		MelloUI:Print("   name: %s", Font(rawget(f, "Name")))
		local level = uf and uf.PartyLevelText and uf:PartyLevelText(f)
		MelloUI:Print("   level: %s", level and Font(level) or "not made (Unit Frames' party level)")
		local row = ns.Solo and ns.Solo.buffRows and ns.Solo.buffRows[f]
		local own = ns.Solo and ns.Solo.ownBuffs and ns.Solo.ownBuffs[f]
		MelloUI:Print("   buff row: %s", row and ("shown " .. S_(row:IsShown())) or (own and "in its debuff row") or "none")
	end
	local n = 0
	PartyMembers(function(f)
		n = n + 1
		One("member " .. n, f)
	end)
	if n == 0 then
		MelloUI:Print("the game's party members: none in its pool")
	end
	One("solo", ns.Solo and ns.Solo.frame)
	local replica = RD.Page and RD.Page.samples and RD.Page.samples.portrait
	One("Designer replica", replica)
	-- (2026-10-24, the user: the preview "a accurate representation of the actual unitframes") the replica against
	-- each real frame, part by part, in the frame's own units: "same" within half a unit. A member shows the game's
	-- own place for a part you never moved (its default in the replica): a difference there is the default's
	local function Against(label, f)
		if type(f) ~= "table" or not ns.Parts then
			return
		end
		MelloUI:Print("replica against %s:", label)
		for _, row in ipairs(ns.Parts.Compare(replica, f)) do
			local a, b = row.a, row.b
			local function At(w)
				return w and string.format("%s %.1f,%.1f %.0fx%.0f%s", w.point, w.x, w.y, w.w, w.h, w.shown and "" or " hidden")
					or "none"
			end
			local verdict = not row.diff and "-" or (row.diff <= 0.5 and "same" or string.format("OFF by %.1f", row.diff))
			MelloUI:Print("   %s: %s | replica %s | %s %s", row.label, verdict, At(a), label, At(b))
		end
	end
	if replica then
		local m = 0
		PartyMembers(function(f)
			m = m + 1
			Against("member " .. m, f)
		end)
		Against("solo", ns.Solo and ns.Solo.frame)
	else
		MelloUI:Print("replica against the frames: open the Designer's Party > Portraits first")
	end
	MelloUI:ShowLog("Group Frames: the party frames")
end
