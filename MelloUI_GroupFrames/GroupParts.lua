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
--   Parts:Of(key) -> settings    a part's own settings (nil: its default)
--   Parts:Shown(key) -> settings as it shows (its own, else its default)
--   Parts:Set(key, field, value), Parts:SetSpot(key, point), Parts:Reset(key)
--   Parts:Lay(frame, kind, own)  a frame's parts laid (kind "party": a normal
--                                party frame's; `own`: one of ours built as one)
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
Parts.SIZE = { textMin = 6, textMax = 24, iconMin = 6, iconMax = 40 }

local JUSTIFY = { TOPLEFT = "LEFT", LEFT = "LEFT", BOTTOMLEFT = "LEFT", TOPRIGHT = "RIGHT", RIGHT = "RIGHT",
	BOTTOMRIGHT = "RIGHT" }
local TEXT_INSET = 3   -- a text's room from the frame's sides (the game's 3 px)

local faded = setmetatable({}, { __mode = "k" })   -- [region] = true: faded by us (put back once shown again)

function Parts:Of(key)
	local all = RD.DB().parts
	local s = type(all) == "table" and all[key]
	return type(s) == "table" and s.set and s or nil
end

-- a part's settings as they show: the player's, else its default
function Parts:Shown(key)
	local p = Parts.BY[key]
	local s = self:Of(key)
	if s then
		return s
	end
	local g = p.home
	return { show = true, point = g.point, x = g.x, y = g.y, size = g.size }
end

local function Region(frame, p, key)
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
		return
	end
	for _, p in ipairs(Parts.LIST) do
		pcall(LayOne, frame, p, self:Shown(p.key))
	end
end

local function Later(fn)
	local K = MelloUI.Kit
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

local function Changed(key)
	MelloUI:NotifySettingChanged(RD.module.name, "parts", RD.DB().parts)
	MelloUI:Fire("groupframes", "part", key)
	LayAll()
end

function Parts:Set(key, field, value)
	local db = RD.DB()
	db.parts = type(db.parts) == "table" and db.parts or {}
	local s = db.parts[key]
	if not (type(s) == "table" and s.set) then
		s = self:Shown(key)
		s.set = true
		db.parts[key] = s
	end
	s[field] = value
	Changed(key)
end

-- a spot picked: the part's own point on it, no offset
function Parts:SetSpot(key, point)
	self:Set(key, "point", point)
	local s = self:Of(key)
	s.x, s.y = 0, 0
	Changed(key)
end

function Parts:Reset(key)
	local db = RD.DB()
	if type(db.parts) == "table" then
		db.parts[key] = nil
	end
	Changed(key)
end
