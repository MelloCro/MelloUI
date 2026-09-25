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
local Perf = MelloUI.Perf:Scope("SocialPanel")
local hooksecurefunc = Perf.hooksecurefunc
-- one handler for every frame it is hooked on, wrapped once (user,
-- 2026-09-24: the shared handlers)
local Shared = Perf.Shared or function(_, fn) return fn end
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("SocialPanel", {
	title = "Social Panel Kit",
	desc = "The social window (contacts, raid, quick join) dressed in the painted kit on the game's own layout.",
	window = { label = "Social window", desc = "Contacts, raid and quick join in the kit.", tab = "Windows", order = 10,
		frames = { "FriendsFrame" }, plainGrab = true, firstOpen = true },
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local skin = nil
local active = false
local hooked = false

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

--------------------------------------------------------------------------------
-- Dressing in steps (/melloperf, 2026-09-24: the window's first open cost
-- 26 ms in one frame: every page, the ignore list window, the raid pane and
-- each friend row's hover plate were made in its OnShow, most of them
-- hidden). The first open now dresses what that first frame shows: the
-- shell, the tabs, the page on show and the controls on it. The rest (the
-- other pages, the ignore list and raid info windows, popups, a row's invite
-- and summon buttons while the game hides them, the rows' hover plates) is
-- made after it, a few ms per frame while the game is idle, and at once
-- where a part shows (or a row is hovered) before its turn: nothing ever
-- shows the game's look for a frame, and the finished window is the same.
-- The sweep (`Kit:SweepControls`) walks what is shown; a hidden part is
-- swept when it shows or in its idle turn.
--------------------------------------------------------------------------------

local IDLE_BUDGET = 2       -- ms of parts per idle frame (one part may run past it)

local swept = setmetatable({}, { __mode = "k" })     -- [frame] = GetTime() of its last sweep
local pending = setmetatable({}, { __mode = "k" })   -- [frame] = depth: a hidden part not swept yet
local jobs = setmetatable({}, { __mode = "k" })      -- [frame] = what is still to be made for it
local queued = setmetatable({}, { __mode = "k" })    -- [frame] = true while it waits in the queue
local watched = setmetatable({}, { __mode = "k" })   -- [frame] = true: its OnShow makes what it waits for
local pages = setmetatable({}, { __mode = "k" })     -- [page] = { depth, dress }: re-swept on every show
local rowBoxes = setmetatable({}, { __mode = "k" })  -- [scroll box] = true: its rows are ours (SkinFriendRow...)
local secure = setmetatable({}, { __mode = "k" })    -- [frame] = true: a secure frame, swept once, in an idle turn (the raid's members)
local queue, head = {}, 1                            -- the parts, in the order they are made when idle
local openedAt = nil                                 -- GetTime() of the window's last open
local idle = CreateFrame("Frame")
local idling = false

local SweepShown, DressPage, Run, IdleTick

local function StartIdle()
	if not idling and active and head <= #queue then
		idling = true
		Perf.SetScript(idle, "OnUpdate", IdleTick)
	end
end

local function Queue(frame, job)
	if job then
		jobs[frame] = job
	end
	if not queued[frame] then
		queued[frame] = true
		queue[#queue + 1] = frame
	end
	StartIdle()
end

-- The kit gives some parts their onEnable after making them (a search box's
-- text inset past the plate's cap): the parts a step made are switched on
-- once more after it, as the first open's all are (Dress), and, as there, the
-- plates that follow the game's art (a tab's plain and open plates) are then
-- shown as that art is: Enable shows every plate, and the game shows or hides
-- a header tab's art through SetShown, which runs none of the kit's Show /
-- Hide hooks (review, 2026-09-24: a tab made after the first open showed both
-- of its plates for the session). `n`, `f`: the reps and followers before it.
local function EnableFrom(n, f)
	if active then
		local reps = skin.reps
		for i = n + 1, #reps do
			reps[i]:Enable()
		end
		local followers = skin.followers
		for i = f + 1, #followers do
			local entry = followers[i]
			entry.rep:SetShown(entry.region:IsShown())
		end
	end
end

-- a part's OnShow (hooked once, one handler for all): what it waits for is
-- made now, in the frame it shows; a page is swept again on every show (its
-- pooled rows and tabs come and go)
local PartShown = Shared("OnShow on a hidden part", function(frame)
	if not (active and skin and skin.built) then
		return
	end
	local n, f = #skin.reps, #skin.followers
	Run(frame)
	if pages[frame] then
		DressPage(frame)
	end
	EnableFrom(n, f)
end, "script")

local function Watch(frame)
	if not watched[frame] then
		watched[frame] = true
		Perf.HookScript(frame, "OnShow", PartShown)
	end
end

-- a hidden part: made on its first show, or in its idle turn (a page: its
-- own dress, then the sweep of what it shows)
local function Later(frame, depth, job)
	if depth then
		local d = pending[frame]
		pending[frame] = d and math.min(d, depth) or depth
	end
	local page = pages[frame]
	if page and page.dress and not job and depth then
		job = page.dress
	end
	-- (never a hook on a secure frame, the raid's member buttons: they hold
	-- no control, their idle turn is enough)
	if not watched[frame] and not (frame.IsProtected and frame:IsProtected()) then
		Watch(frame)
	end
	Queue(frame, job)
end

-- what a part waits for, made now; in an idle turn one step at a time (a
-- page's sweep waits for the next turn after its own dress)
function Run(frame, idleTurn)
	queued[frame] = nil
	local job = jobs[frame]
	if job then
		jobs[frame] = nil
		job(frame)
		if idleTurn and pending[frame] then
			Queue(frame)
			return
		end
	end
	local depth = pending[frame]
	if depth then
		SweepShown(frame, pages[frame] and pages[frame].depth or depth)
	end
end

-- the kit's sweep over `frame`'s own children only (at the kit's depth
-- limit it classifies them and walks no further): the walk below it is ours,
-- into the shown children only
local function Classify(frame)
	Kit:SweepControls(frame, Replace, skin, nil, 8)
end

local function Walk(depth, now, ...)
	for i = 1, select("#", ...) do
		local child = select(i, ...)
		-- (as the kit's sweep: never into a scroll bar, never past depth 8).
		-- A list whose rows are dressed by the row skin below is swept once,
		-- in an idle turn: the row skin makes all a row shows. A secure frame
		-- (a raid member's button) holds no control (its own look, if any, is
		-- its parent's sweep's): swept once, in its idle turn, never in the
		-- frame the window opens in (review, 2026-09-24: the raid's 40 members
		-- were 1.3 ms of the Raid tab's first open, and 1 ms of one idle turn)
		if depth <= 8 and not (child.Track and child.Track.Thumb) and not secure[child] then
			if swept[child] == nil and not pages[child] and child.IsProtected and child:IsProtected() then
				secure[child] = true
				pending[child] = depth
				Queue(child)
			elseif child:IsShown() and not rowBoxes[child] then
				if pages[child] then
					DressPage(child)
				else
					SweepShown(child, depth, now)
				end
			elseif swept[child] == nil then
				Later(child, depth)
			end
		end
	end
end

function SweepShown(frame, depth, now)
	now = now or GetTime()
	if swept[frame] == now then
		return
	end
	swept[frame] = now
	pending[frame] = nil
	Classify(frame)
	Walk(depth + 1, now, frame:GetChildren())
end

-- a page: its own dress (each step made once; cheap once made), then the
-- sweep of what it shows. `depth` is the page's in the kit's sweep: 1 under
-- the window, 0 for the raid pane and the raid info window, which were
-- swept on their own
function DressPage(page)
	local p = pages[page]
	if p.dress then
		p.dress(page)
	end
	SweepShown(page, p.depth)
end

-- the idle turns: a few ms of parts per frame while the window is open (on
-- again at its next open: nothing of it runs while it is closed, WINDOW-RULES
-- 2f), never in the frame it opened in, never in a fight (on again when it
-- ends). A page (its own dress, or the sweep of all it holds: the raid pane's
-- is ~2.7 ms) is the largest part: it starts a frame, it never follows other
-- parts in one (review, 2026-09-24: small parts to just under the budget,
-- then the raid pane, made one idle frame 5.8 ms)
function IdleTick()
	if not (active and skin and skin.built) or head > #queue or not FriendsFrame:IsShown() then
		idling = false
		Perf.SetScript(idle, "OnUpdate", nil)
		if head > #queue then
			queue, head = {}, 1
		end
		return
	end
	if InCombatLockdown() then
		idling = false
		Perf.SetScript(idle, "OnUpdate", nil)
		idle:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	if GetTime() == openedAt then
		return
	end
	local t0 = debugprofilestop()
	local ran = false
	while head <= #queue do
		local frame = queue[head]
		if ran and queued[frame] and pages[frame] then
			break
		end
		queue[head] = false
		head = head + 1
		if queued[frame] then
			ran = true
			local n, f = #skin.reps, #skin.followers
			Run(frame, true)
			EnableFrom(n, f)
			if debugprofilestop() - t0 >= IDLE_BUDGET then
				break
			end
		end
	end
end

Perf.SetScript(idle, "OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	StartIdle()
end)

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

-- A plate that stands in for a row's highlight: the hover look, shown while
-- the mouse is over the row (the game's highlight texture draws itself on
-- hover; a replacement region must be shown by hand). Made on the row's
-- first hover or in an idle turn (it shows on hover only): the row's
-- OnEnter makes it before the frame the highlight would show in. The game's
-- highlight is faded at once all the same: the game locks it on the selected
-- friend / ignored name (LockHighlight), where it draws without a hover
-- (review, 2026-09-24: the stock bar showed on the first frame, and all
-- fight long, until the plate was made); the plate's own fade takes over
-- once it is made.
local plates = setmetatable({}, { __mode = "k" })    -- [row] = its hover plate
local plateOf = setmetatable({}, { __mode = "k" })   -- [row] = the highlight a plate is still to be made for (faded by hand while on)
local hovered = setmetatable({}, { __mode = "k" })   -- [row] = true while the mouse is over it

local function SyncPlate(row)
	local rep = plates[row]
	if active and rep then
		rep.object:SetShown(hovered[row] == true)
	end
end

local function MakePlate(row)
	local highlight = plateOf[row]
	if not (highlight and active) then
		return
	end
	plateOf[row] = nil
	local rep = Replace(highlight, { as = "FriendsRowHighlight", rect = row, button = row })
	row.melloRep = rep or false
	if not rep then
		-- (no piece for it, the tuning's "leave this one alone": the game's own)
		Kit:Unfade(highlight)
		return
	end
	plates[row] = rep
	local enable = rep.Enable
	rep.Enable = function(self)
		enable(self)
		SyncPlate(row)
	end
	SyncPlate(row)
end

local RowEnter = Shared("OnEnter on a list row", function(row)
	hovered[row] = true
	MakePlate(row)
	SyncPlate(row)
end, "script")
local RowLeave = Shared("OnLeave on a list row", function(row)
	hovered[row] = nil
	SyncPlate(row)
end, "script")

local function HoverPlate(row, highlight)
	if not (row and highlight) or row.melloRep ~= nil then
		return
	end
	row.melloRep = false
	plateOf[row] = highlight
	if active then
		Kit:Fade(highlight)
	end
	Perf.HookScript(row, "OnEnter", RowEnter)
	Perf.HookScript(row, "OnLeave", RowLeave)
	Queue(row, MakePlate)
end

-- the invite button (shown by the game for a Battle.net friend in the game):
-- on the cog, made when it shows
local function MakeInvite(invite)
	if invite.melloRep == nil and invite:GetNormalTexture() then
		invite.melloRep = Replace(invite:GetNormalTexture(), { as = "friendslist-invitebutton-default-normal", button = invite, noFade = true }) or false
	end
end

-- the summon button (hidden unless a recruit can be summoned): the sweep
-- gives it its look by its art. While hidden it carries the kit's "nothing to
-- do" mark, so the sweep passes it; on its first show (or in its idle turn)
-- the mark goes and the sweep of its row makes its look
local function Unclaim(button)
	if button.melloRep == false then
		button.melloRep = nil
		local row = button:GetParent()
		if row then
			Classify(row)
		end
	end
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
			if invite:IsShown() then
				MakeInvite(invite)
			else
				Later(invite, nil, MakeInvite)
			end
		end
		local summon = row.summonButton
		if summon and summon.melloRep == nil then
			if summon:IsShown() then
				Classify(row)
			else
				summon.melloRep = false
				Later(summon, nil, Unclaim)
			end
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

local function SkinListRow(row)
	local highlight = row.GetHighlightTexture and row:GetHighlightTexture()
	HoverPlate(row, highlight)
end

--------------------------------------------------------------------------------
-- The window's parts
--------------------------------------------------------------------------------

-- A tab the game hides (by game mode, or the header's recruit tab) carries
-- the kit's "nothing to do" mark while hidden, so neither this nor the sweep
-- makes its two plates yet; they are made on its first show or in its idle
-- turn
local function MakeTab(tab)
	if tab.melloRep == false then
		tab.melloRep = nil
		Kit:SkinPanelTab(tab, Replace, skin)
	end
end

local function SkinTab(tab)
	if tab.melloRep ~= nil then
		return
	end
	if tab:IsShown() then
		Kit:SkinPanelTab(tab, Replace, skin)
	else
		tab.melloRep = false
		Later(tab, nil, MakeTab)
	end
end

local BOTTOM_TABS = { "FriendsFrameTab1", "FriendsFrameTab2", "FriendsFrameTab3", "FriendsFrameTab4" }

local function SkinBottomTabs()
	for _, name in ipairs(BOTTOM_TABS) do
		local tab = _G[name]
		if tab then
			SkinTab(tab)
		end
	end
end

-- the header (Contacts): its top tabs (they come and go: again on every
-- show) and the Battle.net band
local function SkinHeader(header)
	local system = header.TabSystem
	if system then
		for _, tab in ipairs({ system:GetChildren() }) do
			if tab.Left then
				SkinTab(tab)
			end
		end
	end
	local bnet = header.BattlenetFrame
	if bnet then
		local bg = Kit:FirstTexture(bnet)
		if bg and bnet.melloRep == nil then
			bnet.melloRep = Replace(bg, { as = "battlenet-friends-main", rect = bnet }) or false
		end
	end
end

local function SkinFriendsList(list)
	if list.ScrollBox then
		rowBoxes[list.ScrollBox] = true
		Kit:HookScrollBoxRows(list.ScrollBox, SkinFriendRow, IsActive, true)
	end
end

local function SkinIgnoreList(ignore)
	if skin.ignore then
		return
	end
	skin.ignore = true
	Kit:SkinWindowShell(ignore, Replace, skin, { noRing = true, bg = "UI-Background-Rock" })
	if ignore.Inset then
		Kit:SkinInset(ignore.Inset, Replace, ignore, true)
	end
	if ignore.ScrollBox then
		rowBoxes[ignore.ScrollBox] = true
		Kit:HookScrollBoxRows(ignore.ScrollBox, SkinListRow, IsActive, true)
	end
end

-- A box lying on the dimmed inset (a raid group's five names) takes the main
-- window's tone over its stone: a step lighter than the inner panel around
-- it, as WINDOW-RULES 2e stripes rows (user, 2026-09-24: "too much small text
-- over a plain brown border is just an eye strain").
local BOX_TONE = MelloUI.Palette and MelloUI.Palette.mainWindow

-- The raid pane: the group boxes (G), made again on every show (the raid UI
-- makes them when it loads, in a raid)
local function SkinRaidGroups()
	for i = 1, 8 do
		local group = _G["RaidGroup" .. i]
		if group and group.melloRep == nil then
			local outline = Kit:FirstTexture(group)
			group.melloRep = outline and Replace(outline, { as = "UI-RaidFrame-GroupOutline", rect = group,
				dim = BOX_TONE and 0.85 or nil, dimColor = BOX_TONE }) or false
		end
	end
end

-- The raid info popup: column headers GC1, rows' hover, header and footer
local function SkinRaidInfo(info)
	if skin.raidInfo then
		return
	end
	skin.raidInfo = true
	for _, name in ipairs({ "RaidInfoInstanceLabel", "RaidInfoIDLabel" }) do
		local label = _G[name]
		local middle = label and _G[name .. "Middle"]
		if label and middle then
			Replace(middle, { as = "ColumnDisplayButton", rect = label, alsoFade = { _G[name .. "Left"], _G[name .. "Right"] } })
		end
	end
	if info.ScrollBox then
		rowBoxes[info.ScrollBox] = true
		Kit:HookScrollBoxRows(info.ScrollBox, SkinListRow, IsActive, true)
	end
	for _, key in ipairs({ "RaidInfoDetailHeader", "RaidInfoDetailFooter" }) do
		if _G[key] then
			Replace(_G[key], { as = "UI-RaidInfo-Header" })
		end
	end
end

-- the window's pages: each one's own dress and its depth in the kit's sweep
local function Pages(ff)
	local function Page(frame, depth, dress)
		if frame then
			pages[frame] = { depth = depth, dress = dress }
			Watch(frame)
		end
	end
	Page(ff.FriendsTabHeader, 1, SkinHeader)
	Page(FriendsListFrame, 1, SkinFriendsList)
	Page(ff.IgnoreListWindow, 1, SkinIgnoreList)
	Page(_G.RecentAlliesFrame, 1)
	Page(_G.QuickJoinFrame, 1)
	Page(_G.RecruitAFriendFrame, 1)
	Page(RaidFrame, 0, SkinRaidGroups)
	Page(RaidInfoFrame, 0, SkinRaidInfo)
end

-- the raid pane and its info window (the pane is the window's only while the
-- raid tab has claimed it): swept on their own, as they always were
local function SkinRaidPages()
	for _, frame in ipairs({ RaidFrame, RaidInfoFrame }) do
		if frame and pages[frame] then
			if frame:IsVisible() then
				DressPage(frame)
			elseif swept[frame] == nil then
				Later(frame, pages[frame].depth)
			end
		end
	end
end

-- The look of what the window shows now; what it hides waits (above).
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
	openedAt = GetTime()
	local ring = Kit:SkinWindowShell(ff, Replace, skin, { portrait = FriendsFrameIcon, bg = "UI-Background-Rock" })
	if ring and FriendsFrameIcon then
		-- 2b: the icons the game swaps in per tab (the two heads, the raid
		-- helm) at the class medallion's size, on the dark disc, as every
		-- other window's portrait (the spell book, the bags, the guild, the
		-- group finder); re-fitted on every swap. They were blown up to 1.3 x
		-- the medallion (2026-09-21, the heads read small), which made this
		-- the one window whose icon was 0.99 x the ring: wider than the ring's
		-- metal itself, so it no longer sat in its opening (user, 2026-09-24:
		-- "there is a rule for this on the size so that it fits"). An icon
		-- that does not cover the opening sits on the disc, it is not grown.
		local function Fit()
			pcall(Kit.FitPortrait, Kit, FriendsFrameIcon, ring)
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
	-- the lists (friends, recent allies, quick join, the raid) on the dark
	-- list stone, under the palette's inner panel (the inset rule's `dim`,
	-- WINDOW-RULES 2e: nothing else here lays a panel over it, so it is not
	-- doubled); the ignore list's inset the same (SkinIgnoreList)
	if ff.Inset then
		Kit:SkinInset(ff.Inset, Replace, ff, true)
	end
	SkinBottomTabs()
	Pages(ff)
	-- the page on show and every control shown; the rest waits
	SweepShown(ff, 0)
	SkinRaidPages()
end

-- Dressed on the window's first open (user, 2026-09-24: "dress rarely used
-- windows on first open"): the social window exists from login, but nothing
-- of the look is built while it has never been shown. Its OnShow (Hook)
-- builds what it shows before the first frame is drawn, the rest in the
-- frames after (Dressing in steps), and it then stays built for the session,
-- switched with the module. In combat too: the skin adds frames and textures
-- of ours and fits the tab icon in the ring; the raid pane's secure member
-- buttons are never touched, its group boxes only get a card of ours (the
-- idle turns wait for the fight to end; a part that shows is made at once).
local function Dress()
	local ff = FriendsFrame
	if not (active and ff) then
		return
	end
	if not (skin and skin.built) then
		if not ff:IsShown() then
			return
		end
		Build()
	end
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	for _, entry in ipairs(skin.followers) do
		entry.rep:SetShown(entry.region:IsShown())
	end
	-- the rows' highlights whose plates are still to be made (HoverPlate)
	for _, highlight in pairs(plateOf) do
		Kit:Fade(highlight)
	end
	StartIdle()
end

local function Hook()
	local ff = FriendsFrame
	if hooked or not ff then
		return
	end
	hooked = true
	Perf.HookScript(ff, "OnShow", function()
		if not active then
			return
		end
		openedAt = GetTime()
		if skin and skin.built then
			-- tabs and pooled frames come and go with the window: what it
			-- shows is swept again on show (its pages again as they show)
			local n, f = #skin.reps, #skin.followers
			SkinBottomTabs()
			SweepShown(ff, 0)
			SkinRaidPages()
			EnableFrom(n, f)
			StartIdle()
		else
			Dress()
		end
	end)
end

local function Activate()
	if active then
		return
	end
	active = true
	Dress()
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
	for _, highlight in pairs(plateOf) do
		Kit:Unfade(highlight)
	end
	Kit:Uncover("social")
end

function M:OnEnable(db)
	self.db = db
	if FriendsFrame then
		Hook()
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
		if not (skin and skin.built) then
			MelloUI:Print("Social window not dressed yet (it is dressed on its first open): the game's own art only.")
		end
		Kit:DumpWindow(FriendsFrame, skin, msg ~= "" and msg or nil)
	end
	MelloUI:ShowLog("socdump " .. msg)
end
