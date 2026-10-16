--------------------------------------------------------------------------------
-- MelloUI - Group Frames: the frame's parts (the user, 2026-10-09:
-- "font sizes and positions is also very important")
--
-- The texts and icons of a member's frame of ours (GroupButton.lua: they keep
-- the game's raid frame's names) -- the name, the health text (statusText),
-- the role icon, the raid mark, the ready check, the centre icon -- shown or
-- not (a part hidden is faded: its alpha), at one of nine spots with an
-- offset, at a size (a text's font size, an icon's). A part the player left
-- alone sits at its default place (`home`). Every frame of ours is laid the
-- same way -- the secure ones and the Designer's preview -- so the preview is
-- the frame.
--   Parts.LIST                   the parts: key, label, short, region, text?, home
--   Parts.LAYOUTS (one look C9)  each layout's parts and table: "raid" (our
--                                raid frames: db.parts), "groupParty" (our
--                                Group Frames party: db.partyParts, split off
--                                the raid's once), "portrait" (the game's normal
--                                party frames: Parts.PARTY's keys in db.parts)
--   Parts:ListOfLayout(layout)   a layout's parts
--   Parts:Of(key[, layout]) -> settings    a part's own settings (nil: its
--                                default); no layout: "raid" for our parts,
--                                "portrait" for the party.* ones
--   Parts:Shown(key[, layout]) -> settings as it shows (its own, else its default)
--   Parts:Place(layout, key, t)  a part's whole settings (nil: back to its
--                                default): ONE write, ONE 'setting'
--   Parts:Set(key, field, value[, layout]), Parts:SetSpot(key, point[, layout]),
--   Parts:Reset(key[, layout]), Parts:ResetLayout(layout), Parts:Moved(layout)
--   Parts:Split(db)              the Group Frames party's own places, copied
--                                from the raid's once (then `split` marks it)
--   Parts:Lay(frame, kind, own)  a frame's parts laid (kind "party": a normal
--                                party frame's; `own`: one of ours built as one);
--                                one of ours by its frame.partsLayout ("raid"
--                                when it has none)
--   Parts.LayAll()               every frame laid again (GroupFrames.lua's
--                                OnSettingChanged for 'parts' / 'partyParts')
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_GroupFrames (parts)")
local hooksecurefunc = Perf.hooksecurefunc
local Num = MelloUI.Safe.Number
local RD = ns.RD

local Parts = {}
ns.Parts = Parts

-- the default places (the game's raid frame's: the role icon and the name
-- on the top line, the health text in the middle, the marks over it)
Parts.LIST = {
	{ key = "name", label = "Name", short = "Name", region = "name", text = true,
	  home = { point = "TOPLEFT", x = 15, y = -3, size = 10 } },
	{ key = "health", label = "Health Text", short = "Health", region = "statusText", text = true,
	  home = { point = "CENTER", x = 0, y = -4, size = 10 } },
	{ key = "role", label = "Role Icon", short = "Role", region = "roleIcon",
	  home = { point = "TOPLEFT", x = 3, y = -3, size = 11 } },
	{ key = "mark", label = "Raid Mark", short = "Mark", region = "raidIcon",
	  home = { point = "TOPRIGHT", x = -3, y = -3, size = 12 } },
	{ key = "ready", label = "Ready Check", short = "Ready", region = "readyCheckIcon",
	  home = { point = "CENTER", x = 0, y = 0, size = 18 } },
	{ key = "centre", label = "Centre Icon", short = "Centre", region = "centerStatusIcon",
	  home = { point = "CENTER", x = 0, y = 0, size = 20 } },
}
-- the normal party frames' parts (the game's party member: its own regions,
-- at its own places -- PartyFrameTemplates.xml, PartyMemberFrame.lua -- until
-- the player moves one; "Buffs & Debuffs" its aura row, scaled by its size;
-- `under`: the child frame the region is kept in -- the role and leader
-- icons are the member's overlay's, PartyMemberOverlay.RoleIcon / LeaderIcon;
-- `twin`: a region laid the same way -- the guide's icon, which the game shows
-- in the leader's place in a group from the dungeon finder)
Parts.PARTY = {
	{ key = "party.name", label = "Name", short = "Name", region = "Name", text = true, keepWidth = true,
	  home = { point = "TOPLEFT", x = 46, y = -6, size = 10 } },
	-- (one-look D5, the user's pick 6C: the member's level on its name line is
	-- the core's -- Modules/UnitFrames.lua, made while Unit Frame Tweaks are
	-- on and the painted skin is off -- so its region comes through the
	-- module's getter, `get`: the core writes no key on the game's frame;
	-- home: the core's own place, its right edge 101 in, the name's line;
	-- `line`: left alone, it shows on the Name part's line in the Name part's
	-- size -- as the core draws it -- so the Designer's slider and the first
	-- edit, which keeps what shows, never give it a size the name has not:
	-- the user's screenshot of 2026-10-15, a "17" at 10 beside a name at 7)
	{ key = "party.level", label = "Level", short = "Level", text = true, keepWidth = true, line = "party.name",
	  get = function(frame)
		local uf = MelloUI:GetModule("UnitFrames")
		return uf and uf.PartyLevelText and uf:PartyLevelText(frame) or nil
	  end,
	  home = { point = "TOPRIGHT", x = -19, y = -6, size = 10 } },
	{ key = "party.role", label = "Role Icon", short = "Role", region = "RoleIcon", under = "PartyMemberOverlay",
	  home = { point = "TOPRIGHT", x = -5, y = -5, size = 12 } },
	-- (the user, 2026-10-09: "i also need to be able to move the Leader Icon";
	-- the game's: its bottom on the frame's top, 10 left of the middle, 6 down
	-- -- 16 px: its top 10 above the frame's)
	{ key = "party.leader", label = "Leader Icon", short = "Leader", region = "LeaderIcon", twin = "GuideIcon",
	  under = "PartyMemberOverlay",
	  home = { point = "TOP", x = -10, y = 10, size = 16 } },
	{ key = "party.ready", label = "Ready Check", short = "Ready", region = "ReadyCheck",
	  home = { point = "LEFT", x = 13, y = 0, size = 25 } },
	{ key = "party.buffs", label = "Buffs & Debuffs", short = "Buffs", region = "AuraFrameContainer", scale = true,
	  home = { point = "TOPLEFT", x = 48, y = -43, size = 15 } },
}
Parts.BY = {}
for _, list in ipairs({ Parts.LIST, Parts.PARTY }) do
	for _, p in ipairs(list) do
		Parts.BY[p.key] = p
	end
end

-- a frame kind's parts ("group": ours, "party": the game's normal party frames)
function Parts:ListOf(kind)
	return kind == "party" and Parts.PARTY or Parts.LIST
end

-- (one look C9: the user's "party and raid keep their own places") the
-- layouts: our raid frames, our Group Frames party, the game's normal party
-- frames; 'party' keeps meaning the portrait frames everywhere
Parts.LAYOUTS = {
	raid = { list = Parts.LIST, store = "parts" },
	groupParty = { list = Parts.LIST, store = "partyParts" },
	portrait = { list = Parts.PARTY, store = "parts" },
}

function Parts:ListOfLayout(layout)
	local l = Parts.LAYOUTS[layout]
	return l and l.list or Parts.LIST
end

-- the layout a part is read in when none is named: the raid's for ours, the
-- portrait's for the party frames' (party.*)
local function LayoutOf(key, layout)
	if layout and Parts.LAYOUTS[layout] then
		return layout
	end
	return (type(key) == "string" and key:sub(1, 6) == "party.") and "portrait" or "raid"
end

-- the table a layout's parts are read from: the Group Frames party's own
-- once split off, the raid's before (a getter never writes)
local function StoreOf(db, layout)
	local t = db[Parts.LAYOUTS[layout].store]
	if layout == "groupParty" and not (type(t) == "table" and t.split == true) then
		t = db.parts
	end
	return type(t) == "table" and t or nil
end
Parts.SIZE = { textMin = 6, textMax = 24, iconMin = 6, iconMax = 40 }

local JUSTIFY = { TOPLEFT = "LEFT", LEFT = "LEFT", BOTTOMLEFT = "LEFT", TOPRIGHT = "RIGHT", RIGHT = "RIGHT",
	BOTTOMRIGHT = "RIGHT" }
local TEXT_INSET = 3   -- a text's room from the frame's sides (the game's 3 px)

local faded = setmetatable({}, { __mode = "k" })   -- [region] = true: faded by us (put back once shown again)

function Parts:Of(key, layout)
	local all = StoreOf(RD.DB(), LayoutOf(key, layout))
	local s = all and all[key]
	return type(s) == "table" and s.set and s or nil
end

-- a part's settings as they show: the player's, else its default (a part on
-- another's line, `line`: that part's size, and its point's row at its own
-- side -- the Level on the Name's: TOPRIGHT on a TOP name's y, RIGHT on a
-- LEFT / CENTER one's, BOTTOMRIGHT on a BOTTOM one's -- its own x)
function Parts:Shown(key, layout)
	local p = Parts.BY[key]
	local s = self:Of(key, layout)
	if s then
		return s
	end
	local g = p.home
	local point, y, size = g.point, g.y, g.size
	local on = p.line and self:Shown(p.line, layout)
	if on then
		-- (that part as LayRegion lays it: its home point and size, no offset,
		-- for a field its saved settings lack)
		local lh = Parts.BY[p.line].home
		local at = type(on.point) == "string" and on.point or lh.point
		local row = at:match("^TOP") or at:match("^BOTTOM") or ""
		local side = g.point:match("LEFT$") or g.point:match("RIGHT$") or ""
		point = (row .. side ~= "") and (row .. side) or "CENTER"
		y = type(on.y) == "number" and on.y or 0
		size = type(on.size) == "number" and on.size or lh.size
	end
	return { show = true, point = point, x = g.x, y = y, size = size }
end

local function Region(frame, p, key)
	if p.get and not key then
		-- (a region of the core's, asked of it: never a key on the frame)
		local r = p.get(frame)
		return type(r) == "table" and r.SetPoint and r or nil
	end
	local holder = p.under and rawget(frame, p.under) or frame
	local r = type(holder) == "table" and rawget(holder, key or p.region)
	return type(r) == "table" and r.SetPoint and r or nil
end

local function LayRegion(frame, p, s, r)
	if s.show == false then
		r:SetAlpha(0)
		faded[r] = true
	elseif faded[r] then
		faded[r] = nil
		r:SetAlpha(1)
	end
	local point = s.point or p.home.point
	r:ClearAllPoints()
	r:SetPoint(point, frame, point, s.x or 0, s.y or 0)
	local size = s.size or p.home.size
	if p.scale then
		-- (a row the game lays out itself: the whole of it scaled)
		r:SetScale(math.max(0.2, size / p.home.size))
	elseif p.text then
		local file, _, flags = r:GetFont()
		if file then
			r:SetFont(file, size, flags or "")
		end
		local w = Num(frame:GetWidth())
		if not p.keepWidth and w and w > 2 * TEXT_INSET then
			-- (as wide as the frame leaves it from where it starts)
			r:SetWidth(math.max(1, w - 2 * TEXT_INSET - math.abs(s.x or 0)))
		end
		r:SetJustifyH(JUSTIFY[point] or "CENTER")
	else
		r:SetSize(size, size)
	end
end

local function LayOne(frame, p, s)
	local r = Region(frame, p)
	if r then
		LayRegion(frame, p, s, r)
	end
	local twin = p.twin and Region(frame, p, p.twin)
	if twin then
		LayRegion(frame, p, s, twin)
	end
end

-- a frame's parts: ours every part (its default for one left alone); the
-- game's normal party member only the parts the player moved (the game's own
-- places otherwise); a normal party frame of ours (`own`: the solo frame, the
-- Designer's replicas) every part, as ours (its default the game's place)
function Parts:Lay(frame, kind, own)
	if type(frame) ~= "table" then
		return
	end
	if kind == "party" then
		for _, p in ipairs(Parts.PARTY) do
			local s = own and self:Shown(p.key) or self:Of(p.key)
			if s then
				pcall(LayOne, frame, p, s)
			end
		end
		-- (the core's soft band behind the name runs on to the level: on the
		-- name alone once the player has moved either; the level, a region of
		-- the core's, put back by it once reset -- Modules/UnitFrames.lua)
		local uf = MelloUI:GetModule("UnitFrames")
		if uf and uf.PartyLine then
			uf:PartyLine(frame, self:Of("party.name") ~= nil, self:Of("party.level") ~= nil)
		end
		return
	end
	local layout = rawget(frame, "partsLayout") or "raid"
	for _, p in ipairs(Parts.LIST) do
		pcall(LayOne, frame, p, self:Shown(p.key, layout))
	end
end

local function Later(fn)
	local K = MelloUI.Schedule or MelloUI.Kit
	if InCombatLockdown() and K and K.WhenOutOfCombat then
		K:WhenOutOfCombat(fn)
	elseif not InCombatLockdown() then
		fn()
	end
end

-- a game party member's name laid again after the game anchors it (its art
-- changing: PartyMemberFrameMixin:UpdateNameTextAnchors -- a post-hook on the
-- member, never per frame)
local hookedMember = setmetatable({}, { __mode = "k" })
function Parts:HookMember(member)
	if hookedMember[member] or type(member) ~= "table" or type(member.UpdateNameTextAnchors) ~= "function" then
		return
	end
	hookedMember[member] = true
	hooksecurefunc(member, "UpdateNameTextAnchors", function(m)
		if Parts:Of("party.name") then
			Later(function()
				Parts:Lay(m, "party")
			end)
		end
	end)
end

-- every frame laid again: ours, and the game's party members
local function LayAll()
	local H = ns.Headers
	if H and H.Buttons then
		for _, b in ipairs(H:Buttons()) do
			Parts:Lay(b)
		end
	end
	if H and H.EachPartyMember then
		Later(function()
			H:EachPartyMember(function(m, own)
				Parts:Lay(m, "party", own)
			end)
		end)
	end
end

Parts.LayAll = LayAll

-- one 'setting' for the layout's table (GroupFrames.lua lays every frame
-- again on it), and the bus's word for the part (`key` nil: the layout's every
-- part)
local function Changed(layout, key)
	local store = Parts.LAYOUTS[layout].store
	MelloUI:NotifySettingChanged(RD.module.name, store, RD.DB()[store])
	MelloUI:Fire("groupframes", "part", key)
end

-- (one look C9) the Group Frames party's own places, split off the raid's
-- once: each part the player moved copied whole (a copy: Place writes the
-- party's own), then marked; true when it split now. A profile loaded from
-- before (no marker) splits again on the module's next enable
function Parts:Split(db)
	db = db or RD.DB()
	local pp = db.partyParts
	if type(pp) ~= "table" then
		pp = {}
		db.partyParts = pp
	end
	if pp.split == true then
		return false
	end
	local from = type(db.parts) == "table" and db.parts or {}
	local Copy = RD.Copy
	for _, p in ipairs(Parts.LIST) do
		local s = from[p.key]
		if type(s) == "table" and s.set and Copy then
			pp[p.key] = Copy(s)
		end
	end
	pp.split = true
	return true
end

-- a part's whole settings in its layout (nil: back to its default): one
-- write, one 'setting' (the Group Frames party split off first)
function Parts:Place(layout, key, t)
	layout = LayoutOf(key, layout)
	local db = RD.DB()
	if layout == "groupParty" then
		self:Split(db)
	end
	local store = Parts.LAYOUTS[layout].store
	db[store] = type(db[store]) == "table" and db[store] or {}
	if type(t) == "table" then
		local s = {}
		for k, v in pairs(t) do
			s[k] = v
		end
		s.set = true
		db[store][key] = s
	else
		db[store][key] = nil
	end
	Changed(layout, key)
end

-- a part's settings as they show, a copy (to change and Place)
local function Copied(self, key, layout)
	local s, out = self:Shown(key, layout), {}
	for k, v in pairs(s) do
		out[k] = v
	end
	return out
end

function Parts:Set(key, field, value, layout)
	local s = Copied(self, key, layout)
	s[field] = value
	self:Place(layout, key, s)
end

-- a spot picked: the part's own point on it, no offset
function Parts:SetSpot(key, point, layout)
	local s = Copied(self, key, layout)
	s.point, s.x, s.y = point, 0, 0
	self:Place(layout, key, s)
end

function Parts:Reset(key, layout)
	self:Place(layout, key, nil)
end

-- every part of a layout back to its default: one write (the Group Frames
-- party keeps its split marker: never copied from the raid's again)
function Parts:ResetLayout(layout)
	layout = Parts.LAYOUTS[layout] and layout or "raid"
	local db = RD.DB()
	if layout == "groupParty" then
		self:Split(db)
	end
	local all = db[Parts.LAYOUTS[layout].store]
	if type(all) == "table" then
		for _, p in ipairs(Parts.LAYOUTS[layout].list) do
			all[p.key] = nil
		end
	end
	Changed(layout, nil)
end

-- how many of a layout's parts the player moved
function Parts:Moved(layout)
	layout = Parts.LAYOUTS[layout] and layout or "raid"
	local n = 0
	for _, p in ipairs(Parts.LAYOUTS[layout].list) do
		if self:Of(p.key, layout) then
			n = n + 1
		end
	end
	return n
end
