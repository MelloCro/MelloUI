--------------------------------------------------------------------------------
-- MelloUI - Group Frames: the indicators on the frames
--
-- Each host -- a member's frame of ours (GroupHeaders.lua's buttons), or the
-- game's normal party member while those are chosen in a party -- gets
-- two of the game's aura containers (CustomAuraContainerTemplate,
-- Blizzard_AuraContainer: it reads the unit's auras itself, secret or not,
-- and fills the regions handed to its buttons):
--   top     the icons, squares and bars, above the frame
--   tint    the health colours, at the frame's own level: their tint drawn
--           over the health fill (BORDER 4) and under the name (ARTWORK)
-- One slot per indicator, keyed by its id: AddAuraSlot(id, filter,
-- { candidateFilters }) -- a buff by its spell IDs (every rank:
-- includeSpellIDs, which the game allows for helpful auras on you and your
-- group, in a fight too), a debuff by the game's filter words and its kind.
-- A slot holds all of an indicator's regions (GroupLooks.lua); a change of
-- look hands it others, never a new slot. An indicator taken out: its slot
-- switched off (the game has no way to remove one).
-- A host's containers are made the first time it has a unit, out of a fight
-- (a raid's unused buttons never get any); a unit the containers cannot take
-- in a fight is handed to them when it ends. Nothing per frame: the game's own
-- aura events.
--   Indicators:Start() / Stop()   on and off (the module, its switch)
--   Indicators:Host(frame, unit, healthFill)   a frame of ours as a host
--   Indicators:SetUnit(frame, unit)            its unit now
--   Indicators:Apply()           every host laid again from the list
-- (1.2.4, GroupSpellGroups.lua) A spell group: a container of its own on each
-- host, at the group's spot, the game laying, filling and sorting its buttons
-- the group's way (its flow); in your order a slot per spell laid here. Made
-- and added to out of a fight only (the game refuses a new container or group
-- in one): asked in a fight, made when it ends.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_GroupFrames (indicators)")
local Shared = Perf.Shared
local RD = ns.RD
local Looks = ns.Looks

local I = { errors = {} }
ns.Indicators = I

local TOP_LEVEL = 4    -- the top container above its frame
local TINT_SUB = 4     -- the tint's sublevel in BORDER (the fill 0, the heal prediction 5 and 6)

local holders = {}     -- [host] = { host, top, tint, slots = { [id] = slot }, unit, health }
local list = {}        -- the holders in the order made
local active = false
local hooked = false

local function Try(label, fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a = pcall(fn, ...)
	if not ok then
		if #I.errors < 20 then
			I.errors[#I.errors + 1] = label .. ": " .. tostring(a)
		end
		return nil
	end
	return a == nil and true or a
end

local function NewContainer(parent)
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
	if not ok or type(c) ~= "table" or type(c.SetUnit) ~= "function" or type(c.AddAuraSlot) ~= "function" then
		if #I.errors < 20 then
			I.errors[#I.errors + 1] = "container: " .. tostring(ok and "no AuraContainer with SetUnit / AddAuraSlot" or c)
		end
		return nil
	end
	return c
end

--------------------------------------------------------------------------------
-- An indicator's filter and candidates
--------------------------------------------------------------------------------

local function Filter(ind)
	if ind.kind == "buff" then
		return ind.whose == "any" and "HELPFUL" or "HELPFUL|PLAYER"
	end
	local k = RD.KIND[ind.what]
	return k and k.filter or "HARMFUL"
end

-- the candidates and a short signature of them (set again only on a change)
local function Candidates(ind)
	if ind.kind == "buff" then
		local ids = RD:Ids(ind.name, ind.spell)
		local keys = {}
		for id in pairs(ids) do
			keys[#keys + 1] = id
		end
		table.sort(keys)
		return { includeSpellIDs = ids }, "ids:" .. table.concat(keys, ",")
	end
	local k = RD.KIND[ind.what]
	if k and k.candidates then
		local c = {}
		for key, v in pairs(k.candidates) do
			c[key] = type(v) == "table" and RD.Copy(v) or v
		end
		return c, "kind:" .. ind.what
	end
	return nil, "kind:" .. tostring(ind.what)
end

-- what the regions are handed for (a new hand-over only when it changed)
local function HandSig(ind)
	return table.concat({ ind.look, ind.colourBy, tostring(ind.text and ind.text.show),
		tostring(ind.count and ind.count.show) }, "|")
end

--------------------------------------------------------------------------------
-- Holders and slots
--------------------------------------------------------------------------------

local hosts = {}       -- [frame] = { health = its fill }: frames that may hold indicators
local later = {}       -- [frame] = unit: handed to its containers when the fight ends

local function TryUnit(h, unit)
	local all = true
	for _, c in ipairs({ h.top, h.tint }) do
		if unit then
			local ok = pcall(c.SetUnit, c, unit)
			all = all and ok
		end
	end
	for _, g in pairs(h.groups) do
		if unit then
			local ok = pcall(g.c.SetUnit, g.c, unit)
			all = all and ok
		end
	end
	if all then
		h.unit = unit
	end
	return all
end

-- (a frame kind's health tint: ours drawn at the frame's own level between
-- the fill (BORDER 0) and the name (ARTWORK); on a normal party frame the
-- health bar is a frame of its own: the tint at its level, over its fill)
local PARTY_TINT = { layer = "ARTWORK", sub = 7 }

local function MakeHolder(host, health, kind)
	local top = NewContainer(host)
	if not top then
		return nil
	end
	top:SetAllPoints(host)
	top:SetFrameLevel(host:GetFrameLevel() + TOP_LEVEL)
	local tint = NewContainer(host)
	if not tint then
		return nil
	end
	tint:SetAllPoints(host)
	local bar = kind == "party" and health and health.GetParent and health:GetParent()
	if bar and bar.GetFrameLevel then
		tint:SetFrameLevel(bar:GetFrameLevel())
	else
		Looks.ParentLevel(tint, true)
	end
	local h = { host = host, top = top, tint = tint, slots = {}, groups = {}, health = health, kind = kind or "group" }
	holders[host] = h
	list[#list + 1] = h
	return h
end

-- the slot of an indicator on a holder (made on its first need)
local function Slot(h, ind)
	local s = h.slots[ind.id]
	if s then
		return s
	end
	local c = ind.look == "health" and h.tint or h.top
	local made = {}
	local function Dress(b)
		local ok, p = pcall(Looks.Make, b)
		if ok then
			made.p = p
		elseif #I.errors < 20 then
			I.errors[#I.errors + 1] = "dress: " .. tostring(p)
		end
	end
	local cand, csig = Candidates(ind)
	local b = Try("slot " .. ind.id, c.AddAuraSlot, c, ind.id, Filter(ind), { initializeFrame = Dress, candidateFilters = cand })
	if type(b) ~= "table" then
		return nil
	end
	if not made.p then
		Dress(b)
	end
	if not made.p then
		return nil
	end
	if c == h.tint then
		Looks.ParentLevel(b, true)
		if h.kind == "party" then
			made.p.tint:SetDrawLayer(PARTY_TINT.layer, PARTY_TINT.sub)
		else
			made.p.tint:SetDrawLayer("BORDER", TINT_SUB)
		end
	end
	s = { b = b, p = made.p, c = c, filter = Filter(ind), csig = csig, hsig = nil, health = c == h.tint, on = true }
	h.slots[ind.id] = s
	return s
end

local function SlotOn(s, id, on)
	if s.on ~= on then
		s.on = on
		Try("enable", s.c.SetAuraSlotEnabled, s.c, id, on)
	end
end

-- an indicator laid on a holder
local function LayOne(h, ind, fighting)
	local s = h.slots[ind.id]
	-- (a look that moves between the two containers: the old slot off, and the
	-- indicator a new key, its slot made in the other container -- on every
	-- holder, whose old slot is then not wanted)
	if s and s.health ~= (ind.look == "health") then
		SlotOn(s, ind.id, false)
		ind.id = RD.NewId()
		s = nil
	end
	s = s or Slot(h, ind)
	if not s then
		return
	end
	local filter = Filter(ind)
	if filter ~= s.filter then
		s.filter = filter
		Try("filter", s.c.SetAuraSlotFilterString, s.c, ind.id, filter)
	end
	local cand, csig = Candidates(ind)
	if csig ~= s.csig then
		s.csig = csig
		Try("candidates", s.c.SetAuraSlotCandidateFilters, s.c, ind.id, cand)
	end
	Looks.Lay(s.b, s.p, ind, h.host, h.health or Looks.Fill(rawget(h.host, "healthBar")))
	local hsig = HandSig(ind)
	if hsig ~= s.hsig then
		s.hsig = hsig
		Looks.Hand(s.b, s.p, ind)
	end
	SlotOn(s, ind.id, ind.when ~= "combat" or fighting)
end

--------------------------------------------------------------------------------
-- Spell groups (1.2.4)
--------------------------------------------------------------------------------

local SG = ns.SpellGroups
local GROUP = "g"           -- a container's one flowing group

-- a group's flow: along its Grow, the lines away from the edge it stands on
-- (Looks.Way); the corner its buttons start from
local function Flow(ind)
	local dir, wx, wy = Looks.Way(ind)
	local across = dir[1] ~= 0
	local h = (across and dir[1] or wx) < 0 and "Left" or "Right"
	local v = (across and wy or dir[2]) < 0 and "Up" or "Down"
	return across, h, v, (v == "Up" and "BOTTOM" or "TOP") .. (h == "Left" and "RIGHT" or "LEFT")
end

-- an item's size on a host (a bar: as long as the host is wide, Length's share)
local function ItemSize(ind, host)
	if ind.look == "bar" then
		local w = tonumber(host:GetWidth()) or 72
		return math.max(1, (w - 2) * math.max(0.1, math.min(1, ind.length or 1))), ind.size or 2
	end
	return ind.size or 10, ind.size or 10
end

local function LayMade(h, ind, m, rgb)
	Try("group lay", Looks.Lay, m.b, m.p, ind, h.host, h.health or Looks.Fill(rawget(h.host, "healthBar")), true, rgb)
	if ind.look == "health" then
		Looks.ParentLevel(m.b, true)
		if h.kind == "party" then
			m.p.tint:SetDrawLayer(PARTY_TINT.layer, PARTY_TINT.sub)
		else
			m.p.tint:SetDrawLayer("BORDER", TINT_SUB)
		end
	end
	Try("group hand", Looks.Hand, m.b, m.p, ind)
end

-- a group's container on a holder (made on its first need, out of a fight)
local function GroupOf(h, ind)
	local g = h.groups[ind.id]
	if g then
		return g
	end
	if InCombatLockdown() then
		I.waiting = true
		return nil
	end
	local c = NewContainer(h.host)
	if not c then
		return nil
	end
	g = { c = c, made = {}, slots = {}, on = nil }
	h.groups[ind.id] = g
	if h.unit then
		pcall(c.SetUnit, c, h.unit)
	end
	return g
end

local function GroupEnable(g, flowing, slotsOn)
	if g.flowOn ~= flowing and g.added then
		g.flowOn = flowing
		Try("group enable", g.c.SetAuraGroupEnabled, g.c, GROUP, flowing)
	end
	for key, s in pairs(g.slots) do
		local on = slotsOn and slotsOn[key] or false
		if s.on ~= on then
			s.on = on
			Try("group slot", g.c.SetAuraSlotEnabled, g.c, key, on)
		end
	end
	Try("group shown", g.c.SetShown, g.c, flowing or (slotsOn and next(slotsOn) ~= nil) or false)
end

-- your order: a slot per spell, each laid here and in its own colour
local scratch = {}
local function LaySlots(h, g, ind, filter)
	local spells = SG.SlotEntries(ind)
	local iw, ih = ItemSize(ind, h.host)
	local bw, bh, at = Looks.Block(ind, #spells, iw, ih, scratch)
	local wanted = {}
	for i, se in ipairs(spells) do
		local key = "s" .. tostring(se.e.main)
		local s = g.slots[key]
		if not s and not InCombatLockdown() then
			local made = {}
			local b = Try("group slot " .. key, g.c.AddAuraSlot, g.c, key, filter, { initializeFrame = function(btn)
				local ok, p = pcall(Looks.Make, btn)
				made.p = ok and p or nil
			end, candidateFilters = se.cand })
			if type(b) == "table" then
				if not made.p then
					local ok, p = pcall(Looks.Make, b)
					made.p = ok and p or nil
				end
				if made.p then
					s = { m = { b = b, p = made.p }, filter = filter, csig = se.sig, on = true }
					g.slots[key] = s
				end
			end
		elseif not s then
			I.waiting = true
		end
		if s then
			if s.filter ~= filter then
				s.filter = filter
				Try("group slot filter", g.c.SetAuraSlotFilterString, g.c, key, filter)
			end
			if s.csig ~= se.sig then
				s.csig = se.sig
				Try("group slot candidates", g.c.SetAuraSlotCandidateFilters, g.c, key, se.cand)
			end
			LayMade(h, ind, s.m, SG.ColourOf(ind, se.e))
			Try("group slot place", Looks.AtBlock, s.m.b, h.host, ind, bw, bh, at[i], iw, ih)
			wanted[key] = true
		end
	end
	return wanted
end

local function LayGroup(h, ind, fighting)
	local g = GroupOf(h, ind)
	if not g then
		return
	end
	local c = g.c
	local health = ind.look == "health"
	c:SetFrameLevel(health and h.tint:GetFrameLevel() or (h.host:GetFrameLevel() + TOP_LEVEL))
	local filter = SG.Filter(ind)
	local cand, csig = SG.Candidates(ind)
	local listMode = ind.order == "list" and SG.DEF[ind.group].scope ~= "debuff"
	local shown = ind.when ~= "combat" or fighting
	-- the container at the group's spot (hung by its first button, Looks.Pin), its flow the group's way
	local iw, ih = ItemSize(ind, h.host)
	local gap = ind.spacing or 1
	local across, hd, vd, corner = Flow(ind)
	local per = math.max(1, ind.perLine or 4)
	local place = table.concat({ ind.point, ind.x, ind.y, tostring(across), hd, vd, iw, ih, gap, per }, "|")
	if place ~= g.place then
		g.place = place
		local pin, px, py = Looks.Pin(ind, iw, ih)
		c:ClearAllPoints()
		c:SetPoint(pin, h.host, ind.point or "TOPRIGHT", px, py)
		local AU = rawget(_G, "AnchorUtil")
		local A, D = type(AU) == "table" and AU.FlowLayoutAxis, type(AU) == "table" and AU.FlowDirection
		if A and D then
			Try("group axis", c.SetFlowLayoutAxis, c, across and A.Horizontal or A.Vertical)
			Try("group corner", c.SetFlowLayoutAnchorPoint, c, corner)
			Try("group growth", c.SetFlowLayoutGrowthDirection, c, D[hd], D[vd])
		end
		Try("group line", c.SetFlowLayoutMaximumLineSize, c, per * ((across and iw or ih) + gap))
		if g.added then
			Try("group layout", c.SetAuraGroupLayout, c, GROUP, { elementSpacing = gap, lineSpacing = gap })
		end
	end
	-- the flowing group: added once (out of a fight), then changed in place
	if not g.added then
		if InCombatLockdown() then
			I.waiting = true
		else
			g.ind = ind
			local ok = Try("group " .. tostring(ind.id), c.AddAuraGroup, c, GROUP, filter, {
				initializeFrame = function(b)
					local okMake, p = pcall(Looks.Make, b)
					if okMake then
						local m = { b = b, p = p }
						g.made[#g.made + 1] = m
						LayMade(h, g.ind or ind, m)
					end
				end,
				candidateFilters = cand, maxFrameCount = ind.max or 3, sortMethod = SG.Sort(ind),
				layout = { elementSpacing = gap, lineSpacing = gap } })
			if ok then
				g.added, g.flowOn = true, true
				g.filter, g.csig, g.max, g.sort = filter, csig, ind.max, ind.order
			end
		end
	else
		if g.filter ~= filter then
			g.filter = filter
			Try("group filter", c.SetAuraGroupFilterString, c, GROUP, filter)
		end
		if g.csig ~= csig then
			g.csig = csig
			Try("group candidates", c.SetAuraGroupCandidateFilters, c, GROUP, cand)
		end
		if g.max ~= ind.max then
			g.max = ind.max
			Try("group most", c.SetAuraGroupMaxFrameCount, c, GROUP, ind.max or 3)
		end
		if g.sort ~= ind.order then
			g.sort = ind.order
			local M = rawget(_G, "AuraContainerSortDirection")
			Try("group order", c.SetAuraGroupSortMethod, c, GROUP, SG.Sort(ind), M and M.Normal or 0)
		end
	end
	g.ind = ind
	-- its buttons in the group's look (the ones made so far; a new one is laid as it comes)
	local laid = table.concat({ ind.look, iw, ih, ind.r, ind.g, ind.b, ind.alpha, ind.colourBy, tostring(ind.text and ind.text.show),
		tostring(ind.count and ind.count.show), ind.text and ind.text.size, ind.count and ind.count.size,
		ind.text and ind.text.point, ind.count and ind.count.point }, "|")
	if laid ~= g.laid or g.count ~= #g.made then
		g.laid, g.count = laid, #g.made
		for _, m in ipairs(g.made) do
			LayMade(h, ind, m)
		end
	end
	-- (kept for a fight's start and end: In A Fight shows and hides them)
	g.slotKeys = listMode and LaySlots(h, g, ind, filter) or nil
	GroupEnable(g, g.added and shown and not listMode or false, shown and g.slotKeys or nil)
end

local function ApplyHolder(h, inds, fighting)
	local wanted = {}
	for _, ind in ipairs(inds) do
		if ind.kind == "group" and SG then
			LayGroup(h, ind, fighting)
		else
			LayOne(h, ind, fighting)
		end
		wanted[ind.id] = true
	end
	for id, s in pairs(h.slots) do
		if not wanted[id] then
			SlotOn(s, id, false)
		end
	end
	for id, g in pairs(h.groups) do
		if not wanted[id] then
			GroupEnable(g, false, nil)
		end
	end
end

local function On()
	local db = RD.DB()
	return active and db.indicators
end

-- a holder's list: its frame kind's for the spec playing (none while off)
local NONE = {}
local function ListOf(h)
	return On() and RD:List(nil, h.kind) or NONE
end

function I:Apply()
	local fighting = InCombatLockdown()
	for _, h in ipairs(list) do
		ApplyHolder(h, ListOf(h), fighting)
	end
end

-- a frame's containers made and given its unit (out of a fight; in one: when
-- it ends)
local function Ensure(frame, unit)
	local reg = hosts[frame]
	if not (reg and On() and unit) then
		return
	end
	local h = holders[frame]
	if not h then
		if InCombatLockdown() then
			later[frame] = unit
			return
		end
		h = MakeHolder(frame, reg.health, reg.kind)
		if not h then
			return
		end
		ApplyHolder(h, ListOf(h), false)
	end
	if h.unit ~= unit and not TryUnit(h, unit) then
		later[frame] = unit
	end
end

-- a frame as a host (its containers come with its first unit): kind "group"
-- (our raid frames), "groupParty" (our Group Frames party: its own list, one
-- look C9b) or "party" (the game's normal party member)
function I:Host(frame, unit, health, kind)
	hosts[frame] = { health = health, kind = kind or "group" }
	Ensure(frame, unit)
	return holders[frame]
end

function I:SetUnit(frame, unit)
	if not hosts[frame] then
		return
	end
	later[frame] = nil
	Ensure(frame, unit)
end

local events = nil
local OnEvent = Shared("the group frames' indicator events", function(_, event)
	if not active then
		return
	end
	if event == "PLAYER_REGEN_ENABLED" then
		for frame, unit in pairs(later) do
			later[frame] = nil
			Ensure(frame, unit)
		end
		-- (a spell group's container or group asked for in the fight)
		if I.waiting then
			I.waiting = nil
			I:Apply()
		end
	end
	if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
		-- (the indicators shown only in a fight)
		local fighting = event == "PLAYER_REGEN_DISABLED"
		for _, h in ipairs(list) do
			for _, ind in ipairs(ListOf(h)) do
				local s = ind.when == "combat" and h.slots[ind.id]
				local g = ind.when == "combat" and h.groups[ind.id]
				if s then
					SlotOn(s, ind.id, fighting)
				elseif g then
					GroupEnable(g, g.added and fighting and g.slotKeys == nil or false, fighting and g.slotKeys or nil)
				end
			end
		end
	end
end, "script")

local function Hook()
	if hooked then
		return
	end
	hooked = true
	events = CreateFrame("Frame")
	for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
		pcall(events.RegisterEvent, events, e)
	end
	Perf.SetScript(events, "OnEvent", OnEvent)
	-- the list changed (the Designer), another spec, a name's ranks found
	MelloUI:On("groupframes", function(what)
		if active and (what == "list" or what == "spec" or what == "ids") then
			I:Apply()
		end
	end, "GroupFrames.indicators")
end

function I:Start()
	if not (RD.module.isEnabled and RD.DB().indicators) then
		return
	end
	active = true
	Hook()
	for frame in pairs(hosts) do
		local unit = rawget(frame, "unit")
		if unit then
			Ensure(frame, unit)
		end
	end
	self:Apply()
end

function I:Stop()
	active = false
	self:Apply()
end

-- (the tests')
I.holders = holders
