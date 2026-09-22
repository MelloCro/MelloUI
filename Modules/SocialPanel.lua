--------------------------------------------------------------------------------
-- MelloUI - Social Panel
--
-- The social window (FriendsFrame: Contacts with its Friends / Ignore /
-- Recent Allies top tabs, the Raid pane, Quick Join; this client's Camelot
-- FriendsFrame.xml, the classic Blizzard_RaidUI raid pane) dressed in the
-- painted kit (Modules/Kit.lua) on the game's own layout, by the rule
-- book's fixed looks:
--   the window shell (outer rail, one page stone, the Battle.net icon at
--   the medallion size on the disc in the ring, title plate, close), the
--   inset rail, bottom and top tabs, the Battle.net band on the header
--   plate, friend rows' hover as the plate's hover look (shown on hover
--   only, as the game's highlight is), pending-invite headers on the
--   category plate, online / offline dividers, the invite icon button on
--   the cog, red buttons, dropdowns, check boxes and scroll bars by the
--   sweep; the ignore list window the same; the raid pane's group boxes per
--   the user's G pick (kit_raw/social_catalog.png), its raid info popup's
--   column headers GC1 and rows' hover.
-- Covers the Dark Mode group "social". /socdump [frames|reps].
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("SocialPanel", {
	title = "Social Panel Kit",
	desc = "The social window (contacts, raid, quick join) dressed in the painted kit on the game's own layout.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local skin = nil
local active = false

local function IsActive()
	return active
end

local function Replace(region, opts)
	if not region then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Social panel: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

-- A plate that stands in for a row's highlight: the hover look, shown while
-- the mouse is over the row (the game's highlight texture draws itself on
-- hover; a replacement region must be shown by hand).
local function HoverPlate(row, highlight)
	if not (row and highlight) or row.melloRep ~= nil then
		return
	end
	local rep = Replace(highlight, { as = "FriendsRowHighlight", rect = row, button = row })
	row.melloRep = rep or false
	if not rep then
		return
	end
	local function Sync()
		if active then
			rep.object:SetShown(row.melloHover == true)
		end
	end
	row:HookScript("OnEnter", function() row.melloHover = true; Sync() end)
	row:HookScript("OnLeave", function() row.melloHover = nil; Sync() end)
	local enable = rep.Enable
	rep.Enable = function(self)
		enable(self)
		Sync()
	end
	Sync()
end

-- A friends list element (FriendsListButtonTemplate rows, pending-invite
-- headers, the online / offline divider, invite rows).
local function SkinFriendRow(row)
	if row.melloRep ~= nil then
		return
	end
	if row.BG and row.RightArrow then
		row.melloRep = Replace(row.BG, { as = "FriendsPendingHeader", rect = row, alsoFade = { row.Flash } }) or false
		return
	end
	local highlight = row.highlight or (row.GetHighlightTexture and row:GetHighlightTexture())
	if highlight and row.name then
		HoverPlate(row, highlight)
		local invite = row.travelPassButton
		if invite and invite.GetNormalTexture and invite:GetNormalTexture() and invite.melloRep == nil then
			invite.melloRep = Replace(invite:GetNormalTexture(), { as = "friendslist-invitebutton-default-normal", button = invite, noFade = true }) or false
		end
		return
	end
	-- a divider: one texture, the online / offline line
	local regions = { row:GetRegions() }
	if #regions == 1 and regions[1]:GetObjectType() == "Texture" then
		row.melloRep = Replace(regions[1], { as = "UI-FriendsFrame-OnlineDivider", rect = row }) or false
		return
	end
	row.melloRep = false
end

local function SkinTabs(frame)
	local header = frame.FriendsTabHeader
	local system = header and header.TabSystem
	if system then
		for _, tab in ipairs({ system:GetChildren() }) do
			if tab.Left then
				Kit:SkinPanelTab(tab, Replace, skin)
			end
		end
	end
	for _, name in ipairs({ "FriendsFrameTab1", "FriendsFrameTab2", "FriendsFrameTab3", "FriendsFrameTab4" }) do
		local tab = _G[name]
		if tab then
			Kit:SkinPanelTab(tab, Replace, skin)
		end
	end
end

local function SkinContacts(frame)
	local header = frame.FriendsTabHeader
	local bnet = header and header.BattlenetFrame
	if bnet then
		local bg = Kit:FirstTexture(bnet)
		if bg and bnet.melloRep == nil then
			bnet.melloRep = Replace(bg, { as = "battlenet-friends-main", rect = bnet }) or false
		end
	end
	local list = FriendsListFrame
	if list and list.ScrollBox then
		Kit:HookScrollBoxRows(list.ScrollBox, SkinFriendRow, IsActive, true)
	end
	local ignore = frame.IgnoreListWindow
	if ignore and not skin.ignore then
		skin.ignore = true
		Kit:SkinWindowShell(ignore, Replace, skin, { noRing = true, bg = "UI-Background-Rock" })
		if ignore.Inset then
			Kit:SkinInset(ignore.Inset, Replace, ignore)
		end
		if ignore.ScrollBox then
			Kit:HookScrollBoxRows(ignore.ScrollBox, function(row)
				local highlight = row.GetHighlightTexture and row:GetHighlightTexture()
				HoverPlate(row, highlight)
			end, IsActive, true)
		end
	end
end

-- The raid pane: the group boxes (G) and the raid info popup.
local function SkinRaid()
	for i = 1, 8 do
		local group = _G["RaidGroup" .. i]
		if group and group.melloRep == nil then
			local outline = Kit:FirstTexture(group)
			group.melloRep = outline and Replace(outline, { as = "UI-RaidFrame-GroupOutline", rect = group }) or false
		end
	end
	local info = RaidInfoFrame
	if info and not skin.raidInfo then
		skin.raidInfo = true
		for _, name in ipairs({ "RaidInfoInstanceLabel", "RaidInfoIDLabel" }) do
			local label = _G[name]
			local middle = label and _G[name .. "Middle"]
			if label and middle then
				Replace(middle, { as = "ColumnDisplayButton", rect = label, alsoFade = { _G[name .. "Left"], _G[name .. "Right"] } })
			end
		end
		if info.ScrollBox then
			Kit:HookScrollBoxRows(info.ScrollBox, function(row)
				local highlight = row.GetHighlightTexture and row:GetHighlightTexture()
				HoverPlate(row, highlight)
			end, IsActive, true)
		end
		for _, key in ipairs({ "RaidInfoDetailHeader", "RaidInfoDetailFooter" }) do
			if _G[key] then
				Replace(_G[key], { as = "UI-RaidInfo-Header" })
			end
		end
	end
end

local function Build()
	local ff = FriendsFrame
	if not ff then
		return
	end
	if not skin then
		skin = { reps = {}, followers = {} }
	end
	if skin.built then
		return
	end
	skin.built = true
	local ring = Kit:SkinWindowShell(ff, Replace, skin, { portrait = FriendsFrameIcon, bg = "UI-Background-Rock" })
	if ring and FriendsFrameIcon then
		-- the icons the game swaps in per tab (the two heads, the raid helm)
		-- are painted with a wide margin: 1.3 x the medallion size (user,
		-- 2026-09-21: they did not fill the ring), re-fitted on every swap
		local function Fit()
			pcall(Kit.FitPortrait, Kit, FriendsFrameIcon, ring, 1.3)
		end
		ring.onEnable = Fit
		ring.onDisable = function()
			pcall(Kit.UnfitPortrait, Kit, FriendsFrameIcon)
		end
		Kit:RingDisc(ring, nil, ff, 0)   -- chains onto the fit above
		if active then
			Fit()
		end
		hooksecurefunc(FriendsFrameIcon, "SetTexture", function()
			if active then
				Fit()
			end
		end)
	end
	if ff.Inset then
		Kit:SkinInset(ff.Inset, Replace, ff)
	end
	SkinTabs(ff)
	SkinContacts(ff)
	SkinRaid()
	Kit:SweepControls(ff, Replace, skin)
	if RaidFrame then
		Kit:SweepControls(RaidFrame, Replace, skin)
	end
	if RaidInfoFrame then
		Kit:SweepControls(RaidInfoFrame, Replace, skin)
	end
	-- tabs and pooled frames come and go with the window: sweep again on show
	ff:HookScript("OnShow", function()
		if active then
			SkinTabs(ff)
			SkinRaid()
			Kit:SweepControls(ff, Replace, skin)
		end
	end)
end

local function Activate()
	if active then
		return
	end
	active = true
	Build()
	if skin then
		for _, rep in ipairs(skin.reps) do
			rep:Enable()
		end
		for _, entry in ipairs(skin.followers) do
			entry.rep:SetShown(entry.region:IsShown())
		end
	end
	Kit:Cover("social")
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	if skin then
		for _, rep in ipairs(skin.reps) do
			rep:Disable()
		end
	end
	Kit:Uncover("social")
end

function M:OnEnable(db)
	self.db = db
	if FriendsFrame then
		Activate()
	end
end

function M:OnDisable()
	Deactivate()
end

--------------------------------------------------------------------------------
-- /socdump [frames|reps]: the window's art. Opens the copy window.
--------------------------------------------------------------------------------
SLASH_MELLOSOCDUMP1 = "/socdump"
SlashCmdList.MELLOSOCDUMP = function(msg)
	msg = (msg or ""):lower()
	MelloUI:ClearLog()
	if not FriendsFrame then
		MelloUI:Print("No social window.")
	else
		Kit:DumpWindow(FriendsFrame, skin, msg ~= "" and msg or nil)
	end
	MelloUI:ShowLog("socdump " .. msg)
end
