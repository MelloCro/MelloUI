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
	local h = { host = host, top = top, tint = tint, slots = {}, health = health, kind = kind or "group" }
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

local function ApplyHolder(h, inds, fighting)
	local wanted = {}
	for _, ind in ipairs(inds) do
		LayOne(h, ind, fighting)
		wanted[ind.id] = true
	end
	for id, s in pairs(h.slots) do
		if not wanted[id] then
			SlotOn(s, id, false)
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
-- (ours) or "party" (the game's normal party member)
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
	end
	if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
		-- (the indicators shown only in a fight)
		local fighting = event == "PLAYER_REGEN_DISABLED"
		for _, h in ipairs(list) do
			for _, ind in ipairs(ListOf(h)) do
				local s = ind.when == "combat" and h.slots[ind.id]
				if s then
					SlotOn(s, ind.id, fighting)
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
I.holders, I.hosts = holders, hosts
