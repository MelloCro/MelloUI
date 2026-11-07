--------------------------------------------------------------------------------
-- MelloUI - Group Frames: the headers (stage 1 of MelloUI's own group frames,
-- docs/plans/raid-frame-designer.md "Stage 1 design")
--
-- Two of the game's secure group headers (SecureGroupHeaderTemplate; their
-- unit buttons SecureUnitButtonTemplate -- a click targets, a right click
-- opens the unit's menu):
--   party   you (Show Yourself In Your Party) and your party; you alone while
--           solo (Show Yourself While Solo: the header's own SOLO) -- while In
--           A Party is Group Frames; under Party Frames our own portrait party
--           frames instead, you and your party (GroupSolo.lua)
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
-- The game's party and raid frames -- its normal party frames, its raid-style
-- party frames, its raid frames and its raid manager -- never show while ours
-- are on, in every style (fr-16; the user, 2026-10-31: "i dont want, under any
-- circumstance, when using our custom Party and Raid Frames, for the default
-- blizzard Party/Raid Frames to appear at all"): faded to nothing and
-- click-through, out of a fight, kept so (a write of their alpha faded again
-- at once, the parts that ignore their parent's alpha tied to it); given back
-- when the module goes off. Nothing of theirs is shown, hidden, moved, laid
-- out or rebuilt (a show from our code would run their own OnShow under our
-- taint). Under In A Party: Party Frames our portrait party frames show at the
-- party container's place (Edit Layout's "Party Frames": the party moves
-- there only, whichever frames show it).
--   Headers:Start([first]) / Stop()   on and off; `first`: only the header the
--                              group needs now (the login's first step)
--   Headers:Layout()           the layout settings again (a fight: later)
--   Headers:Repaint()          every button painted again (bus groupframes "paint": the made-up ones too)
--   Headers:Blizzard()         the game's frames hidden or given back
--   Headers:Buttons() -> list  every button made
--   Headers.Aside(on)          your own frame in the party's place (you while solo) away while the Preview's made-up
--                              raid shows, as in a raid; back after (fr-04)
-- The Preview's party host (Core/Preview.lua's PartyHost): the look your party wears, your own frame the portraits'
-- stand-ins stand under, the party's spacing, the first member's place.
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

local TEXT = { party = "Party Frames", raid = "Raid Frames" }
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

local S = { made = false, on = false, pending = false, hidden = false, started = false, gameUsed = false }
local containers, headers = {}, {}
local buttons = {}            -- every button made, in order
local byUnit = {}             -- [unit] = { [button] = true }
local mouseOff = setmetatable({}, { __mode = "k" })   -- [game frame] = true: its mouse turned off by us
local faded = setmetatable({}, { __mode = "k" })      -- [game holder] = its alpha before ours (fr-16)

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

-- (1.2.4; the user, 2026-10-28: one look for the raid and a party in raid frames) every button of ours, the party's
-- and the raid's, is laid by the raid's parts and shows the raid's list (its parts layout: the raid's when it has none)
local function Dress(b)
	if b.melloDressed then
		return
	end
	b.melloDressed = true
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
		ns.Indicators:Host(b, nil, Looks.Fill(b.healthBar))
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
-- unitframe while in a party") a portrait party frame's reach past its own rect (the game's member, 120 x 53, four
-- of them): under it, its pet's room while the game shows party pets (the showPartyPets CVar: the game's own 26
-- between members then, 10 without -- PartyFrame.lua)
local GAME_MEMBER = { w = 120, h = 53, n = 4, pet = 16 }
local function PetRoom()
	local get = type(C_CVar) == "table" and C_CVar.GetCVarBool
	local ok, on = false, nil
	if type(get) == "function" then
		ok, on = pcall(get, "showPartyPets")
	end
	return (ok and on == true) and GAME_MEMBER.pet or 0
end

-- (fr-16; the user, 2026-11-01: "the party frames are also too spread and i dont see the slider for vertical
-- spacing") the room under each portrait party frame, in the frames' units: Vertical Spacing (portraitSpacing: 2 by
-- default, the tight room MelloUI kept before fr-16, where the game's own is 10), and under a member its pet's room
-- while the game shows party pets (the game's 26 then is its 10 and that room)
local function PortraitSpacing()
	local sp = Num(DB().portraitSpacing)
	return ((sp and sp >= 0) and sp or 2) + PetRoom()
end
H.PortraitSpacing = PortraitSpacing

-- (fr-15; the user, 2026-10-31: "they randomly shift from picture 1 and 2") your own frame over the members (Show
-- Yourself In Your Party: GroupSolo.lua's Solo.Above) takes the place of one more member: its height and the room
-- under it, in the frames' units (0: you not there). The members stand that much lower, by the settings alone, so
-- nothing needs laying in a fight
local function SelfRoom()
	local Solo = ns.Solo
	if not (Solo and Solo.Above and Solo.Above()) then
		return 0
	end
	local me, okH, h = Solo.frame, false, nil
	if me then
		okH, h = pcall(me.GetHeight, me)
	end
	return (okH and Num(h) or GAME_MEMBER.h) + PortraitSpacing()
end

-- the portrait party frames' footprint in the party container's units (GroupSolo.lua): four members (the game's
-- PartyMemberFrameTemplate, 120 x 53) at the portraits' scale, Vertical Spacing between them (its pets' room in it)
-- and the last one's pet room under it -- and you on top with Show Yourself In Your Party (SelfRoom)
local function GameFootprint()
	local ratio = (ns.Solo and ns.Solo.Scale and ns.Solo.Scale()) or 1
	local n = GAME_MEMBER.n
	local h = n * GAME_MEMBER.h + (n - 1) * PortraitSpacing() + PetRoom() + SelfRoom()
	-- (1.2.4, fr-10: the damage meter's tab on each frame's plate end -- Modules/Meter.lua -- inside the plate too)
	local meter = MelloUI:GetModule("Meter")
	local ok, reach = false, nil
	if meter and meter.PartyReach then
		ok, reach = pcall(meter.PartyReach, meter)
	end
	reach = ok and Num(reach) or 0
	return (GAME_MEMBER.w + math.max(0, reach)) * ratio, h * ratio
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
		-- (the portrait party frames show at its place: the plate their size, Vertical Spacing between them --
		-- Party Spacing is the raid frames': its row says so)
		return GameFootprint()
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

-- (1.2.4, fr-03; the user, 2026-10-28: "switching between those options should only modify the Look but not the
-- placement of the Party Frames") a plate's place kept by the corner its frames hang from -- the raid's top left; the
-- party's top left, its top right while Flip Horizontally mirrors the portraits (Unit Frames' M:PartyFlipped) -- so
-- the plate's size, which the look and the layout settings change, never moves where the frames start
local movers = {}   -- [kind] = its mover entry (Core's RegisterMover: `key`, `anchor`)
local MIRROR = { TOPLEFT = "TOPRIGHT", TOPRIGHT = "TOPLEFT", BOTTOMLEFT = "BOTTOMRIGHT", BOTTOMRIGHT = "BOTTOMLEFT" }

local function Flipped()
	local uf = MelloUI:GetModule("UnitFrames")
	return (uf and uf.PartyFlipped and uf:PartyFlipped()) and true or false
end

local function Corner(kind)
	return (kind == "party" and Flipped()) and "TOPRIGHT" or "TOPLEFT"
end
H.Corner = Corner

-- a plate hung by `corner` where it stands now (its default place: nothing written)
local function AnchorInPlace(c, corner)
	local okP, p = pcall(c.GetPoint, c, 1)
	if okP and p == corner and c:GetNumPoints() == 1 then
		return
	end
	local l, _, r, t = ScreenRect(c)
	local us = UIParent:GetEffectiveScale()
	if not (l and t and us and us > 0) then
		return
	end
	c:ClearAllPoints()
	c:SetPoint(corner, UIParent, "BOTTOMLEFT", (corner == "TOPRIGHT" and r or l) / us, t / us)
end

-- A plate kept by its corner. A place stored by another -- a store from before 1.2.4 (its bottom left), the party's
-- other side after Flip changed -- measured again where the plate stands now and saved ONCE, then laid from the
-- store, so the look in use now keeps its place; after that it is kept by its corner (no write again). A plate never
-- moved keeps its default place, hung by its corner. Run after the frames' size is final (Attributes, PlaceParty),
-- out of a fight (the callers' Later), never inside an Edit Layout session (it holds the places it moves)
local function Recorner(kind)
	local entry, c = movers[kind], containers[kind]
	if not (entry and c) or InCombatLockdown() then
		return
	end
	local corner = Corner(kind)
	entry.anchor = corner
	local LS = MelloUI.LayoutSession
	if LS and LS.Active and LS.Active() then
		return
	end
	local pos = MelloUI:GetPosition(entry.key)
	if type(pos) ~= "table" then
		AnchorInPlace(c, corner)
		return
	end
	if (pos.point or "BOTTOMLEFT") == corner then
		return
	end
	if MelloUI:SavePosition(entry.key, c) then
		MelloUI:RestorePosition(entry.key, c)
	end
end
H.Recorner = Recorner

-- where the game's own frames stand (a place to start from), hung by the plate's corner
local function Home(kind)
	return function(c)
		c:ClearAllPoints()
		local us = UIParent:GetEffectiveScale()
		local corner = Corner(kind)
		local names = kind == "party" and { "CompactPartyFrame", "PartyFrame" } or { "CompactRaidFrameContainer" }
		for _, name in ipairs(names) do
			local f = rawget(_G, name)
			local l, _, r, t = ScreenRect(f)
			if l and t then
				c:SetPoint(corner, UIParent, "BOTTOMLEFT", (corner == "TOPRIGHT" and r or l) / us, t / us)
				return true
			end
		end
		local w = corner == "TOPRIGHT" and (c.GetWidth and c:GetWidth() or 0) or 0
		c:SetPoint(corner, UIParent, "LEFT", 20 + w, kind == "party" and 220 or 0)
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
	-- (fr-03: its place kept by its corner -- Recorner)
	movers[kind] = MelloUI:RegisterMover(c, c, { key = key, anchor = Corner(kind), default = Home(kind),
		label = TEXT[kind], page = RD.module.name, category = "frames", placeholder = true, when = function()
			return RD.module.isEnabled and true or false
		end })
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
		Set(h, "showSolo", (db.solo and not S.aside) and true or false)
		local point = (g == "DOWN" and "TOP") or (g == "UP" and "BOTTOM") or (g == "RIGHT" and "LEFT") or "RIGHT"
		Set(h, "point", point)
		Set(h, "xOffset", (g == "RIGHT" and sp) or (g == "LEFT" and -sp) or 0)
		Set(h, "yOffset", (g == "DOWN" and -sp) or (g == "UP" and sp) or 0)
		Set(h, "unitsPerColumn", 5)
		Set(h, "maxColumns", 1)
		h:ClearAllPoints()
		local a = ANCHOR[g] or "TOPLEFT"
		-- (fr-03: Flip Horizontally -- the plate kept by its top right -- the header from that side)
		if Corner("party") == "TOPRIGHT" then
			a = MIRROR[a] or a
		end
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
	-- (fr-03: the raid's size is final here; the party's after PlaceParty)
	if kind == "raid" then
		Recorner(kind)
	end
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
		Dress(b)
		i = i + 1
	end
	return h
end

-- (In A Party: Raid Frames -- ours in a party and solo -- or Party Frames: the
-- portrait party frames of ours, GroupSolo.lua: this header never)
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

-- (the raid-style party frames, CompactPartyFrame, are the game's party frame's child: faded with it)
local GAME_HOLDERS = { "CompactPartyFrame", "CompactRaidFrameContainer", "CompactRaidFrameManager", "PartyFrame" }
-- (fr-16) the game's party and raid frames' Edit Mode systems: their selection box ignores its frame's alpha
local GAME_SYSTEMS = { "PartyFrame", "CompactRaidFrameContainer" }

local function MouseOff(f)
	if type(f) == "table" and f.EnableMouse and f.IsMouseEnabled then
		local ok, on = pcall(f.IsMouseEnabled, f)
		if ok and on then
			pcall(f.EnableMouse, f, false)
			mouseOff[f] = true
		end
	end
end

-- A few parts of the game's frames ignore their parent's alpha (the game's templates: CompactUnitFrame.xml's target
-- highlight -- the yellow RaidFrame-TargetFrame box -- and its ready check icon; the normal party frame's
-- NotPresentIcon; fr-16: Edit Mode's selection box on the party and raid frames). With the holders at alpha 0 they
-- still showed where the game's hidden frame stands: the users' "random square" (2026-10-14), a yellow box whenever
-- that frame's unit was the target. While ours stand in they follow their parent's alpha; the template's own setting
-- comes back with the frames. (The game never sets it at run time: nothing it writes is undone, no write a frame.)
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

-- (fr-16) a holder's alpha written while ours stand in -- Edit Mode's Opacity setting as a layout is applied
-- (EditModeUnitFrameSystemMixin:UpdateSystemSettingOpacity), anyone's write -- faded again at once (a post-hook of
-- its SetAlpha: never per frame, the game writes it with its layout), the game's value kept to give back
local refading = false
local OnGameAlpha = Shared("SetAlpha on the game's party or raid frames: faded again", function(f, alpha)
	if refading or not (S.hidden and faded[f] ~= nil) then
		return
	end
	local a = Num(alpha)
	if a and a ~= 0 then
		faded[f] = a
		refading = true
		pcall(f.SetAlpha, f, 0)
		refading = false
	end
end)
local alphaHooked = setmetatable({}, { __mode = "k" })

local function Fade(f)
	if faded[f] == nil then
		local ok, a = pcall(f.GetAlpha, f)
		faded[f] = (ok and Num(a)) or 1
	end
	if not alphaHooked[f] then
		alphaHooked[f] = true
		hooksecurefunc(f, "SetAlpha", OnGameAlpha)
	end
	refading = true
	pcall(f.SetAlpha, f, 0)
	refading = false
end

-- their mouse off: the raid manager, every member, Edit Mode's selection boxes (protected frames: out of a fight)
-- (fr-16; the user's errors of 2026-10-31 23:49 -- the game's party members, faded, ran their own updates on regions
-- that had lost a method) the game's normal party members kept silent while ours stand in: the events their own code
-- listens to (PartyMemberFrame.lua's Setup, UnitFrame_Initialize, their bars, their pet's frame, the alternate power
-- bar, TextStatusBar) let go on each member and the frames in it, each one's own registrations (its units with it)
-- kept to give back exactly when ours go. A frame's event list, never a key of theirs: nothing written on them, no
-- method of theirs touched; out of a fight
local SILENT_EVENTS = { "CVAR_UPDATE", "GROUP_ROSTER_UPDATE", "INCOMING_SUMMON_CHANGED", "PARTY_LEADER_CHANGED",
	"PARTY_LOOT_METHOD_CHANGED", "PARTY_MEMBER_DISABLE", "PARTY_MEMBER_ENABLE", "PLAYER_ALIVE", "PLAYER_DEAD",
	"PLAYER_ENTERING_WORLD", "PLAYER_GAINS_VEHICLE_DATA", "PLAYER_LOSES_VEHICLE_DATA", "PLAYER_UNGHOST",
	"PORTRAITS_UPDATED", "READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED", "UNIT_ABSORB_AMOUNT_CHANGED",
	"UNIT_AURA", "UNIT_CONNECTION", "UNIT_CTR_OPTIONS", "UNIT_DISPLAYPOWER", "UNIT_ENTERED_VEHICLE",
	"UNIT_EXITED_VEHICLE", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_HEALTH", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
	"UNIT_HEAL_PREDICTION", "UNIT_MAXHEALTH", "UNIT_MAXPOWER", "UNIT_MAX_HEALTH_MODIFIERS_CHANGED", "UNIT_NAME_UPDATE",
	"UNIT_OTHER_PARTY_CHANGED", "UNIT_PET", "UNIT_PHASE", "UNIT_PORTRAIT_UPDATE", "UNIT_POWER_BAR_HIDE",
	"UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_TIMER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE",
	"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_THREAT_SITUATION_UPDATE", "UPDATE_ACTIVE_BATTLEFIELD", "VARIABLES_LOADED" }
-- (fr-17: the one copy, MelloUI.Units.Silence / Unsilence -- Modules/UnitFramesOwn.lua -- shared with the player frame
-- of ours; this owner's table the same as before: [game frame] = { { event, unit1, unit2 }, ... } it had)
local silenced = MelloUI.Units.Silenced("party")

-- (looked at again on every pass -- a roster change, the world entered: the game's UnitFrame_SetUnit may register a
-- bar's unit events again -- what it took again let go too, kept with what it had; the frames in it three deep)
local function SilenceMember(m)
	MelloUI.Units.Silence(m, SILENT_EVENTS, "party", 3)
end

local function Unsilence()
	MelloUI.Units.Unsilence("party")
end

local function MiceOff()
	MouseOff(rawget(_G, "CompactRaidFrameManager"))
	GameMembers(MouseOff)
	PartyMembers(MouseOff)
	for _, name in ipairs(GAME_SYSTEMS) do
		local f = rawget(_G, name)
		MouseOff(type(f) == "table" and rawget(f, "Selection") or nil)
	end
	PartyMembers(SilenceMember)
end

local function MiceLater()
	if S.hidden then
		MiceOff()
	end
end

-- the game's own frames give way to ours (the user, 2026-10-09: "i want these frames to be the main ones"; fr-16,
-- 2026-10-31: "under any circumstance"): its raid frames, its raid-style party frames, its raid manager and its
-- normal party frames, in every style (In A Party: Party Frames is our portrait party now). Their alpha and their
-- parts' at once, in a fight too (a login or /reload in one: an alpha and a region's setting are never protected);
-- their mouse out of a fight
local function HideGame()
	local was = S.hidden
	S.hidden = true
	for _, name in ipairs(GAME_HOLDERS) do
		local f = rawget(_G, name)
		if type(f) == "table" and f.SetAlpha then
			Fade(f)
		end
	end
	-- (the parts that ignore their parent's alpha: tied to it on every frame that is hidden; again on each roster
	-- change, the game's new frames with them; Edit Mode's selection boxes too)
	UntieLoose()
	GameMembers(TieLoose)
	PartyMembers(TieLoose)
	for _, name in ipairs(GAME_SYSTEMS) do
		local f = rawget(_G, name)
		Tie(type(f) == "table" and rawget(f, "Selection") or nil)
	end
	if InCombatLockdown() then
		Later(MiceLater, "Group Frames: the game's frames click-through")
	else
		MiceOff()
	end
	-- (told on the bus once: Unit Frames dresses the game's party members only while they show, the meter's tabs
	-- hang on the frames that show)
	if not was then
		MelloUI:Fire("groupframes", "game")
	end
end

local function ShowGame()
	S.hidden = false
	S.gameUsed = true   -- (in use again: dressed as before -- a reload asked for when Group Frames comes back on)
	for _, name in ipairs(GAME_HOLDERS) do
		local f = rawget(_G, name)
		if type(f) == "table" and f.SetAlpha then
			local a = faded[f]
			faded[f] = nil
			refading = true
			pcall(f.SetAlpha, f, a or 1)
			refading = false
		end
	end
	for f in pairs(mouseOff) do
		pcall(f.EnableMouse, f, true)
		mouseOff[f] = nil
	end
	UntieLoose()
	Unsilence()
	MelloUI:Fire("groupframes", "game")
end

--------------------------------------------------------------------------------
-- The party container's size and place (fr-03: the plate kept by its corner); the portrait party frames hang from
-- it (GroupSolo.lua). Out of a fight
--------------------------------------------------------------------------------
local PlaceParty = function()
	local c = containers.party
	if not c then
		return
	end
	c:SetSize(Footprint("party"))
	-- (the size final: the plate kept by its corner, before the frames hang from it)
	local ok, err = pcall(Recorner, "party")
	if not ok then
		geterrorhandler()(err)
	end
end

function H:Blizzard()
	if S.on then
		HideGame()
		return
	end
	Later(function()
		if not S.on and S.hidden then
			ShowGame()
		end
	end, "Group Frames: the game's frames")
end

-- each portrait party frame of ours -- you and your members (GroupSolo.lua), made or not shown (fn(frame, own): the
-- Designer's party parts; own: true, every one is ours)
function H:EachPartyMember(fn)
	if ns.Solo then
		ns.Solo:Each(function(f)
			fn(f, true)
		end)
	end
end

-- In A Party changed: the party header's rule, the game's frames, the portraits
function H:Style()
	Later(function()
		if S.on and S.made then
			Drive(true)
			HideGame()
		end
		PlaceParty()
		SoloUpdate()
	end, "Group Frames: In A Party")
end

-- a portrait party frame's health bar, portrait and the painted ring over it
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
-- unit: the raid-style buttons, and the portrait party frames while they are
-- the choice for a party (GroupSolo.lua) -- theirs also `portrait`, the
-- portrait texture, and `ring`, the painted ring over it while the unit frame
-- skin dresses it, else nil.
-- A fresh list each call: read it, never keep it
function H:Hosts()
	local out = {}
	for _, b in ipairs(buttons) do
		if b.unit and b:IsVisible() then
			out[#out + 1] = { frame = b, unit = b.unit, health = b.healthBar, kind = "group" }
		end
	end
	if ns.Solo then
		ns.Solo:Each(function(f, unit)
			if f:IsVisible() then
				out[#out + 1] = PartyEntry(f, unit)
			end
		end)
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
	local f = ns.Solo and ns.Solo:Of(unit)
	if f then
		return Found(f, unit, "party", PartyParts(f))
	end
	return nil
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local UNIT_PAINT = {
	UNIT_HEALTH = "Health", UNIT_MAXHEALTH = "Health", UNIT_CONNECTION = "Refresh", UNIT_FLAGS = "Health",
	PARTY_MEMBER_ENABLE = "Health", PARTY_MEMBER_DISABLE = "Health",
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

-- (2.1.0; docs/plans/group-range.md) the range of every frame shown read again as a fight starts or ends (the rule's
-- interact distance counts out of a fight only); the client's range and phase events read a member's own (UNIT_PAINT;
-- GroupSolo's members their own). The buttons and the portrait party's members (Solo.Range)
local function RangeShown(b)
	if b:IsShown() then
		Button.Range(b)
	end
end

local function SoloRange(f)
	if f:IsShown() and f.unit then
		ns.Solo.Range(f)
	end
end

local function RangeAll()
	Each(RangeShown)
	if ns.Solo and ns.Solo.Range then
		ns.Solo:Each(SoloRange)
	end
end

-- (2.1.16) a button's unit gone or back, on whatever told us first: Button.Health paints both bars
local function Life(b)
	if MelloUI.Units.Gone(b.unit) ~= (b.dead or false) then
		Button.Health(b)
		-- (2.1.17: Healer Frames' debuff glow, none round a gone member -- the user, 2026-11-07)
		local hf = MelloUI:GetModule("HealerFrames")
		if hf and hf.Update then
			pcall(hf.Update, hf, b)
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
				Life(b)   -- (any event of its unit may be the first to say)
				Button[paint](b)
			end
		end
		return
	end
	if event == "UNIT_DIED" or event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
		Each(Life)   -- (a death anywhere near, yours, your release and return; UNIT_DIED's payload not read)
		return
	end
	if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
		RangeAll()
		if event == "PLAYER_REGEN_DISABLED" then
			return
		end
		if S.pending then
			H:Layout()
		end
		H:Blizzard()
	elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "PLAYER_ENTERING_WORLD" then
		Each(Button.Refresh)
		if S.hidden then
			H:Blizzard()
		end
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
	"UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_IN_RANGE_UPDATE", "UNIT_PHASE", "UNIT_DIED", "PLAYER_DEAD",
	"PLAYER_ALIVE", "PLAYER_UNGHOST", "PARTY_MEMBER_ENABLE", "PARTY_MEMBER_DISABLE", "PLAYER_REGEN_ENABLED",
	"PLAYER_REGEN_DISABLED",
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
	-- the game's members made later (a raid formed, in a fight too): the parts that ignore their parent's alpha tied
	-- to it at once (a region's setting: never protected), click-through out of a fight
	if type(rawget(_G, "DefaultCompactUnitFrameSetup")) == "function" then
		hooksecurefunc("DefaultCompactUnitFrameSetup", function(frame)
			if S.hidden then
				TieLoose(frame)
				Later(function()
					if S.hidden then
						MouseOff(frame)
					end
				end)
			end
		end)
	end
	-- the UI's scale changed, Edit Mode closed: the portrait party's place again
	local function Replace()
		Later(function()
			PlaceParty()
			SoloUpdate()
		end, "Group Frames: the portrait party's place")
	end
	MelloUI:On("editmode", function(entering)
		if not entering then
			Replace()
		end
	end, "GroupFrames.party")
	MelloUI:On("scale", Replace, "GroupFrames.party")
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
	-- (fr-03) Flip Horizontally switched -- or Unit Frames, which flip the portraits: the party kept by its other
	-- corner from now on (measured where it stands, saved once: Recorner), its header and frames hung from it
	MelloUI:On("setting", function(module, key)
		if module == "UnitFrames" and key == "partyFlip" then
			H:Layout()
		end
	end, "GroupFrames.flip")
	MelloUI:On("module", function(name)
		if name == "UnitFrames" then
			H:Layout()
		end
	end, "GroupFrames.flip")
	-- the raid frames' border changed (Raid Frame Border, its placement): the
	-- bars inside it again (Kit:RaidFrameInset; the kit lays borders out of a fight)
	MelloUI:On("raidborder", function()
		for _, b in ipairs(buttons) do
			Button.Lay(b)
		end
	end, "GroupFrames.border")
	-- (1.2.4) the skin switched (MelloUI.Skin): the cells in its look (the Default skin's: the game's raid frame), the
	-- game's party frames and everything hung from them laid again (out of a fight)
	MelloUI:On("skin", function()
		H:Repaint()
		H:Layout()
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

-- (fr-16; the user, 2026-11-01: "Ask for reload") Group Frames on after the game's party frames were in use this
-- session -- off since the login, or given back since: what dressed them meanwhile (the painted skin, Class Icons, Unit
-- Frames) hooked their regions, and a hook can't be taken off. They stay faded and silent, hooked till a reload, which
-- is asked for (MelloUI:AskReload: once a session)
H.RELOAD_SAY = "Group Frames is on: type /reload to finish putting the game's party frames away."

function H:Start(first)
	if not S.on and not S.started and not (MelloUI.LoggingIn and MelloUI:LoggingIn()) then
		S.gameUsed = true   -- (on for the first time since the login: the game's were in use till now)
	end
	S.started = true
	S.on = true
	Listen()
	-- (fr-16: the game's frames away at once, in a fight too -- a /reload in one; ours are made after it)
	H:Blizzard()
	if S.gameUsed and MelloUI.AskReload then
		MelloUI:AskReload(H.RELOAD_SAY)
	end
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
	end, "Group Frames: the headers off")
end

-- (fr-04, the Preview's Raid Fight) a made-up raid shows: your own frame in the party's place steps aside, as it
-- does in a raid (the header's you while solo, the normal party frame of ours: GroupSolo.lua), and comes back after.
-- Out of a fight: the Preview plays out of one (a fight's start ends it; Layout waits for its end)
function H.Aside(on)
	on = on and true or false
	if (S.aside or false) == on then
		return
	end
	S.aside = on
	if ns.Solo then
		ns.Solo.aside = on
	end
	H:Layout()
end

-- the Preview's party (Core/Preview.lua's PartyHost), asked at a party scene's start: the look your party wears, and
-- while that is the portrait party frames of ours your own frame the stand-ins stand under, the room between them
-- (fr-16: our members' -- PortraitSpacing) and the first member's place (fr-16: our members' first slot -- the game's
-- party frame stands elsewhere, faded)
local function Portraits()
	return S.on and DB().partyStyle == "party"
end

-- the first member's top left in UIParent's units and its scale against UIParent's (nil: no party container)
local function Origin()
	local c = containers.party
	local l, _, r, t = ScreenRect(c)
	local us, cs = UIParent:GetEffectiveScale(), Scale(c)
	if not (l and t and us and us > 0 and cs) then
		return nil
	end
	local k = ((ns.Solo and ns.Solo.Scale and ns.Solo.Scale()) or 1) * cs / us
	local top = t / us - SelfRoom() * k
	if Corner("party") == "TOPRIGHT" then
		return r / us - GAME_MEMBER.w * k, top, k
	end
	return l / us, top, k
end

if MelloUI.Preview then
	MelloUI.Preview.PartyHost = {
		Look = function()
			return (S.on and DB().partyStyle ~= "party") and "groupparty" or "party"
		end,
		Top = function()
			return (Portraits() and ns.Solo and ns.Solo:Shown()) or nil
		end,
		Gap = function()
			return Portraits() and PortraitSpacing() or nil
		end,
		Origin = function()
			if Portraits() then
				return Origin()
			end
			return nil
		end,
	}
end

-- (the tests')
H.S = S
H.headers, H.containers, H.byUnit = headers, containers, byUnit
H.loose, H.faded, H.silenced = loose, faded, silenced

--------------------------------------------------------------------------------
-- /run MelloUI.GroupFrames.DumpParty() (the user, 2026-10-24: on the Portraits
-- look the name's and the level's size "dont work"): every portrait party frame
-- -- yours and your members' (ours), the Designer's replica -- its name and
-- level as they are (font, size, place), the parts the Designer keeps for
-- them, its alpha and range, its buff row; the game's own party frames' alpha. Into the copy window, opened;
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
	MelloUI:Print("Group Frames on %s  retail %s  In A Party %s  solo %s  Out Of Range Opacity %s  the game's hidden %s",
		S_(S.on), S_(RD.Retail()), S_(db.partyStyle), S_(db.solo), S_(db.rangeAlpha), S_(S.hidden))
	for _, name in ipairs(GAME_HOLDERS) do
		local g = rawget(_G, name)
		if type(g) == "table" and g.GetAlpha then
			MelloUI:Print("   the game's %s: shown %s alpha %s visible %s", name, S_(g:IsShown()), S_(g:GetAlpha()),
				S_(g:IsVisible()))
		end
	end
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
		MelloUI:Print("%s: unit %s shown %s alpha %s range %s/%s", label, S_(unit), S_(f:IsShown()), S_(f:GetAlpha()),
			okR and S_(inRange) or "-", okR and S_(checked) or "-")
		MelloUI:Print("   name: %s", Font(rawget(f, "Name")))
		local level = uf and uf.PartyLevelText and uf:PartyLevelText(f)
		MelloUI:Print("   level: %s", level and Font(level) or "not made (Unit Frames' party level)")
		local own = ns.Solo and ns.Solo.ownBuffs and ns.Solo.ownBuffs[f]
		MelloUI:Print("   buff row: %s", own and "in its debuff row" or "none")
	end
	One("you", ns.Solo and ns.Solo.frame)
	for i = 1, GAME_MEMBER.n do
		One("member " .. i, ns.Solo and ns.Solo:Member(i))
	end
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
		Against("you", ns.Solo and ns.Solo.frame)
		for i = 1, GAME_MEMBER.n do
			Against("member " .. i, ns.Solo and ns.Solo:Member(i))
		end
	else
		MelloUI:Print("replica against the frames: open the Designer's Party > Portraits first")
	end
	MelloUI:ShowLog("Group Frames: the party frames")
end
