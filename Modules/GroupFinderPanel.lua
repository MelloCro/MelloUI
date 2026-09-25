--------------------------------------------------------------------------------
-- MelloUI - Group Finder Panel
--
-- The Looking For Group window this client uses (LFGParentFrame, the
-- vanilla-style group finder of Blizzard_GroupFinder_VanillaStyle: the
-- Listing, Browse and Who pages on side tabs, each page its own portrait
-- frame, the eye portrait the parent's) dressed in the painted kit
-- (Modules/Kit.lua) on the game's own layout, as the other windows are:
-- every kit piece stands in for one of the game's art regions, on that
-- region's rectangle, as a child (or region) of its frame, faded in place of
-- it (docs/WINDOW-RULES.md).
--
-- State (2026-09-21): the three pages' shells (one ring, on the eye), the
-- side tabs, the pages' backdrops, the role check boxes, the activity list
-- (kit check boxes, +/- glyphs), the browse list's rows (plate / selected
-- plate), the who list's rows and header band, the option cogs, and every
-- common control (`Kit:SweepControls`). Pending the user's pick: the four
-- painted category buttons (Dungeons / Quests & Zones / Battlegrounds /
-- Custom) stay the game's. /gfdump lists the window's art.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("GroupFinderPanel")
local hooksecurefunc = Perf.hooksecurefunc
-- one handler for every frame it is hooked on, wrapped once (user,
-- 2026-09-24: the shared handlers)
local Shared = Perf.Shared or function(_, fn) return fn end
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("GroupFinderPanel", {
	title = "Group Finder Panel",
	desc = "The looking-for-group window dressed in the painted kit on the game's own layout.",
	window = { label = "Looking for group", desc = "Listing, browse and who in the kit.", tab = "Windows", order = 8,
		frames = { "PVEFrame" }, plainGrab = true, addon = "Blizzard_GroupFinder_VanillaStyle", firstOpen = true },
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local skin = nil
local active = false
local hooked = false

local function Replace(region, opts)
	if not region then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Group finder panel: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

local function Follow(rep, region)
	if not (rep and region) then
		return
	end
	local function Sync()
		if active then
			rep:SetShown(region:IsShown())
		end
	end
	hooksecurefunc(region, "Show", Sync)
	hooksecurefunc(region, "Hide", Sync)
	hooksecurefunc(region, "SetShown", Sync)
	skin.followers[#skin.followers + 1] = { rep = rep, region = region }
	Sync()
end

--------------------------------------------------------------------------------
-- Dressing in steps (/melloperf, 2026-09-24: the window's first open cost
-- 17.5 ms in one frame, all three pages made in its OnShow, and every open
-- after it swept the whole window two or three times over). The first open
-- now dresses what that first frame shows: the parent's close button and
-- side tabs, the page on show and the controls on it. The other pages and
-- whatever the game hides (the bottom tabs of the old style, the activity
-- list until a category is picked, the group role buttons) are made after
-- it, a few ms per frame while the game is idle, and at once where a part
-- shows before its turn: nothing ever shows the game's look for a frame, and
-- the finished window is the same. The sweep (`Kit:SweepControls`) walks
-- what is shown, once per frame however many shows ask for it; a hidden part
-- is swept when it shows or in its idle turn.
--------------------------------------------------------------------------------

local IDLE_BUDGET = 2       -- ms of parts per idle frame (one part may run past it)

local swept = setmetatable({}, { __mode = "k" })     -- [frame] = GetTime() of its last sweep
local pending = setmetatable({}, { __mode = "k" })   -- [frame] = depth: a hidden part not swept yet
local jobs = setmetatable({}, { __mode = "k" })      -- [frame] = what is still to be made for it
local queued = setmetatable({}, { __mode = "k" })    -- [frame] = true while it waits in the queue
local watched = setmetatable({}, { __mode = "k" })   -- [frame] = true: its OnShow makes what it waits for
local pages = setmetatable({}, { __mode = "k" })     -- [page] = its own dress (the pages' OnShow: Hook)
local queue, head = {}, 1                            -- the parts, in the order they are made when idle
local openedAt = nil                                 -- GetTime() of the window's last open
local idle = CreateFrame("Frame")
local idling = false

local SweepShown, Run, IdleTick

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

-- The kit gives some parts their onEnable after making them (the who page's
-- search box: its text inset past the plate's cap): the parts a step made
-- are switched on once more after it, as the first open's all are (Activate),
-- and, as there (RefreshFollowers), the plates that follow the game's art (a
-- grouping header's + and - glyphs) are then shown as that art is: Enable
-- shows every plate (review, 2026-09-24: a header dressed on its show showed
-- both glyphs). `n`, `f`: the reps and followers before the step.
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
-- made now, in the frame it shows
local PartShown = Shared("OnShow on a hidden part", function(frame)
	if active and skin then
		local n, f = #skin.reps, #skin.followers
		Run(frame)
		EnableFrom(n, f)
	end
end, "script")

-- a hidden part: made on its first show, or in its idle turn (a page: its
-- own dress, then the sweep of what it shows; its OnShow is the page hook)
local function Later(frame, depth, job)
	if depth then
		local d = pending[frame]
		pending[frame] = d and math.min(d, depth) or depth
	end
	if pages[frame] and not job and depth then
		job = pages[frame]
	end
	if not watched[frame] then
		watched[frame] = true
		Perf.HookScript(frame, "OnShow", PartShown)
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
		job(frame, idleTurn)
		if idleTurn and pending[frame] then
			Queue(frame)
			return
		end
	end
	local depth = pending[frame]
	if depth then
		SweepShown(frame, depth)
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
		-- (as the kit's sweep: never into a scroll bar or our own frame,
		-- never past depth 8)
		if depth <= 8 and child ~= skin and not (child.Track and child.Track.Thumb) then
			if child:IsShown() then
				if pages[child] then
					pages[child](child)
				end
				SweepShown(child, depth, now)
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

-- the idle turns: a few ms of parts per frame while the window is open (on
-- again at its next open: nothing of it runs while it is closed, WINDOW-RULES
-- 2f), never in the frame it opened in, never in a fight (on again when it
-- ends). A page (its own dress, ~1.5-3.6 ms, or the sweep of all it holds)
-- is the largest part: it starts a frame, it never follows other parts in one
-- (review, 2026-09-24: small parts to just under the budget, then a page,
-- could make one idle frame over 5 ms)
function IdleTick()
	if not (active and skin) or head > #queue or not LFGParentFrame:IsShown() then
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

-- a control the game hides (the old style's bottom tabs) carries the kit's
-- "nothing to do" mark while hidden, so the sweep passes it; on its first
-- show (or in its idle turn) the mark goes and the sweep of its parent makes
-- its look
local function Unclaim(control)
	if control.melloRep == false then
		control.melloRep = nil
		local parent = control:GetParent()
		if parent then
			Classify(parent)
		end
	end
end

local function Claim(control)
	if control and control.melloRep == nil and not control:IsShown() then
		control.melloRep = false
		Later(control, nil, Unclaim)
	end
end

-- A list's rows, skinned as the game makes them (`Kit:HookScrollBoxRows`),
-- and the rows it holds already: at once, or, for a page dressed in an idle
-- turn, each row in a turn of its own (or on its show, with the page)
local holdRows = false
local function RowsActive()
	return active and not holdRows
end

local function HookRows(box, rowSkin, idleTurn)
	if not box then
		return
	end
	holdRows = idleTurn and true or false
	Kit:HookScrollBoxRows(box, rowSkin, RowsActive)
	holdRows = false
	if idleTurn and box.ForEachFrame then
		box:ForEachFrame(function(row)
			Later(row, nil, rowSkin)
		end)
	end
end

--------------------------------------------------------------------------------
-- The pages' parts
--------------------------------------------------------------------------------

-- The eye: each page's own portrait texture (the groupfinder-eye-frame
-- atlas is the eye itself in this client; the parent's LFGEyeTemplate frame
-- draws nothing), fitted into the page's ring (WINDOW-RULES 2b).
local function PagePortrait(page)
	return page and page.PortraitContainer and page.PortraitContainer.portrait
end

-- An expand / collapse button whose file the game swaps (UI-MinusButton-UP /
-- UI-PlusButton-UP) through SetNormalTexture: one plate per glyph, the
-- current shown, read from that call.
local function SkinFileToggle(toggle)
	if not (toggle and toggle.GetNormalTexture) or toggle.melloGlyphs then
		return
	end
	toggle.melloGlyphs = {}
	local function Apply(path)
		local key = type(path) == "string" and ((path:lower():find("minus") and "common-button-list-minus") or (path:lower():find("plus") and "common-button-list-plus"))
		if key and toggle.melloGlyphs[key] == nil and toggle:GetNormalTexture() then
			toggle.melloGlyphs[key] = Replace(toggle:GetNormalTexture(), { as = key, button = toggle, rect = toggle:GetNormalTexture(),
				alsoFade = { toggle:GetHighlightTexture() } }) or false
		end
		for k, rep in pairs(toggle.melloGlyphs) do
			if rep then
				rep:SetShown(k == key)
			end
		end
	end
	hooksecurefunc(toggle, "SetNormalTexture", function(_, path)
		if active then
			Apply(path)
		end
	end)
	local okT, tex = pcall(function() return toggle:GetNormalTexture():GetTexture() end)
	Apply(okT and tex or nil)
end

-- An options button (LFGOptionsButton: a gear icon): the cog plate (K2)
local function SkinOptionsButton(button)
	if button and button.Icon and button.melloRep == nil then
		button.melloRep = Replace(button.Icon, { as = "common-dropdown-a-button", button = button, rect = button.Icon, alsoFade = Kit:OtherTextures(button, button.Icon) }) or false
	end
end

-- A page's inset (InsetFrameTemplate with the CustomBG stone): the single
-- rail, edges only, on a holder ABOVE the page's content frame (`over`) so
-- the rail is not lost under it; the inset's own nine-slice art faded.
local function SkinPageInset(page, inset, over)
	if not (page and inset) or inset.melloRep ~= nil then
		return
	end
	-- well above the inset frame (whose stone region painted over a lower
	-- holder), its content and the page's own children: edges only, so
	-- nothing inside the rail is covered
	local level = 10
	local ok, a, c, b = pcall(function() return inset:GetFrameLevel(), (over or inset):GetFrameLevel(), page:GetFrameLevel() end)
	if ok and a and b and c then
		level = math.max(math.max(a, c) - b + 5, 10)
	end
	local extra = { inset.Bg }
	if inset.NineSlice then
		for _, region in ipairs({ inset.NineSlice:GetRegions() }) do
			if region:GetObjectType() == "Texture" then
				extra[#extra + 1] = region
			end
		end
	end
	inset.melloRep = Replace(inset, { as = "common-insideframe", parent = page, rect = inset, level = level, body = false, noFade = true, alsoFade = extra }) or false
end

-- The eye-strain panel (WINDOW-RULES 2e; user, 2026-09-24: "too much small
-- text over a plain brown border is just an eye strain" / "apply the eye
-- strain rule to all existing windows"): the palette's inner panel over the
-- darker list stone of a page's list, inside its rail (Kit:StoneDim), as a
-- REGION of the frame the stone itself is a region of, one sublevel above it:
-- it lies exactly where the stone lies in the draw order, so whatever the
-- game draws over the stone (the rows, the activity list, the comment box)
-- is drawn over the panel too. A tint over the one stone, never a second
-- stone; shown only while the skin is on.
local function EyePanel(host, opts)
	if not (host and Kit.StoneDim) or skin.eyePanels[host] ~= nil then
		return
	end
	local tex = Kit:StoneDim(host, opts)
	skin.eyePanels[host] = tex or false
	if tex then
		tex.kitPiece = true            -- ours: never taken for the game's art
		tex:SetShown(active)
	end
end

-- A card lying on a dimmed list (a browse result, a who row) takes the main
-- window's tone over its stone: a row a step lighter than the panel around
-- it, as 2e stripes rows.
local CARD_TONE = MelloUI.Palette and MelloUI.Palette.mainWindow

-- A page (LFGListingFrame / LFGBrowseFrame / LFGWhoListFrame, each a
-- PortraitFrameTemplateNoCloseButton): its shell, the ring on the parent's eye.
local function SkinPage(page)
	if not page or page.melloShell then
		return
	end
	page.melloShell = true
	Kit:SkinWindowShell(page, Replace, skin, { portrait = PagePortrait(page), body = false, bg = "UI-Background-Rock" })
	skin.rings = skin.rings or {}
	if skin.ring then
		skin.rings[#skin.rings + 1] = { ring = skin.ring, portrait = PagePortrait(page) }
	end
end

-- An activity row of the listing (LFGListingActivityRowTemplate)
local function SkinActivityRow(row)
	if row.melloRep ~= nil then
		return
	end
	row.melloRep = false
	Kit:SkinCheckButton(row.CheckButton, Replace, "UI-CheckBox-Up")
	SkinFileToggle(row.ExpandOrCollapseButton)
end

-- A tall row's card (R3) lights its iron while the game shows the row's
-- Selected bar: re-tint on the bar's Show / Hide.
local function LitOnSelect(row, bar)
	local function Sync()
		if active and row.melloRep and row.melloRep.SetState then
			row.melloRep:SetState()
		end
	end
	hooksecurefunc(bar, "Show", Sync)
	hooksecurefunc(bar, "Hide", Sync)
	hooksecurefunc(bar, "SetShown", Sync)
	Sync()
end

-- A browse result (LFGBrowseSearchEntryTemplate: a translucent ResultBG, a
-- yellow Selected bar, a blue Highlight) or a grouping header (the same
-- with expand / collapse icons): the plain plate (hover from the button),
-- the selected plate following the game; the header's glyphs.
local function SkinBrowseRow(row)
	if row.melloRep ~= nil then
		return
	end
	row.melloRep = false
	local isHeader = row.ExpandIcon ~= nil
	if row.ResultBG then
		-- a result's card in the main window's tone (2e: the leader, the
		-- activity and the comment must not lie on the plain stone; the
		-- grouping header is a plate and takes no `dim`)
		row.melloRep = Replace(row.ResultBG, { as = isHeader and "LFGBrowse-Grouping" or "LFGBrowse-Result", rect = row, button = row,
			dim = (CARD_TONE and not isHeader) and 0.85 or nil, dimColor = CARD_TONE,
			checked = function() return row.Selected and row.Selected:IsShown() or false end,
			alsoFade = { row.Highlight, row.GetHighlightTexture and row:GetHighlightTexture() or nil } }) or false
	end
	if row.Selected then
		Replace(row.Selected, { as = "groupfinder-highlightbar-yellow" })
		LitOnSelect(row, row.Selected)
	end
	if row.ExpandIcon then
		Follow(Replace(row.ExpandIcon, { as = "QuestLog-icon-Expand", button = row, rect = row.ExpandIcon }), row.ExpandIcon)
	end
	if row.CollapseIcon then
		Follow(Replace(row.CollapseIcon, { as = "QuestLog-icon-shrink", button = row, rect = row.CollapseIcon }), row.CollapseIcon)
	end
end

-- A who list row (LFGWhoListButtonTemplate: the large list plate atlases)
local function SkinWhoRow(row)
	if row.melloRep ~= nil then
		return
	end
	row.melloRep = false
	if row.Background then
		-- the row's card in the main window's tone (2e), as the browse results
		row.melloRep = Replace(row.Background, { as = "common-button-list-large", rect = row, button = row,
			dim = CARD_TONE and 0.85 or nil, dimColor = CARD_TONE,
			checked = function() return row.Selected and row.Selected:IsShown() or false end,
			alsoFade = { row.GetHighlightTexture and row:GetHighlightTexture() or nil } }) or false
	end
	if row.Selected then
		Replace(row.Selected, { as = "common-button-list-large-selected" })
		LitOnSelect(row, row.Selected)
	end
end

--------------------------------------------------------------------------------
-- The pages: each one's own dress, made once (on the page's first show, or
-- in an idle turn after the window's first open), before the sweep of what
-- it shows
--------------------------------------------------------------------------------

local dressed = setmetatable({}, { __mode = "k" })   -- [page] = true once its own dress is made

-- the listing page
local function SkinListing(listing, idleTurn)
	if dressed[listing] then
		return
	end
	dressed[listing] = true
	SkinPage(listing)
	local roles = listing.RolesSection
	local roleBg = roles and (_G[(listing:GetName() or "LFGListingFrame") .. "RoleBackground"] or Kit:FirstTexture(roles))
	if roleBg then
		Replace(roleBg, { as = "UI-LFG-BlueBG" })      -- faded: the window's page picture shows
	end
	if listing.Inset and listing.Inset.CustomBG then
		Replace(listing.Inset.CustomBG, { as = "groupfinder-background" })
		-- the activity list, its comment box (and the category page's
		-- banners, pictures over it) on the inner panel (2e): a region of
		-- the inset over the stone (BACKGROUND 0), inside the rail
		EyePanel(listing.Inset)
	end
	SkinPageInset(listing, listing.Inset, listing.CategoryView)
	for _, holder in ipairs({ listing.SoloRoleButtons, listing.GroupRoleButtons }) do
		for _, child in ipairs(holder and { holder:GetChildren() } or {}) do
			if child.CheckButton then
				Kit:SkinCheckButton(child.CheckButton, Replace, "UI-CheckBox-Up")
			end
		end
	end
	if listing.NewPlayerFriendlyButton and listing.NewPlayerFriendlyButton.CheckButton then
		Kit:SkinCheckButton(listing.NewPlayerFriendlyButton.CheckButton, Replace, "UI-CheckBox-Up")
	end
	SkinOptionsButton(listing.OptionsButton)
	-- the four painted category buttons (created by the game on the view's
	-- show, in CategoryView.CategoryButtons): the single rail for their cover
	local function SkinCategories(view)
		for _, button in ipairs(view and view.CategoryButtons or {}) do
			if button.Cover and button.melloRep == nil then
				-- on the PAINTING's rect (inset in the button), not the button's
				button.melloRep = Replace(button.Cover, { as = "groupfinder-button-cover", parent = button, rect = button.Icon or button }) or false
			end
		end
	end
	if LFGListingCategorySelection_UpdateCategoryButtons then
		hooksecurefunc("LFGListingCategorySelection_UpdateCategoryButtons", function(view)
			if active then
				SkinCategories(view)
			end
		end)
	end
	SkinCategories(listing.CategoryView)
	local activity = listing.ActivityView
	if activity then
		if activity.BarMiddle then
			Replace(activity.BarMiddle, { as = "shop-list-rule", rect = activity.BarMiddle })
		end
		HookRows(activity.ScrollBox, SkinActivityRow, idleTurn)
	end
end

-- the browse page
local function SkinBrowse(browse, idleTurn)
	if dressed[browse] then
		return
	end
	dressed[browse] = true
	SkinPage(browse)
	if browse.BackgroundArt then
		Replace(browse.BackgroundArt, { as = "groupfinder-background-page" })
	end
	if browse.Inset and browse.Inset.CustomBG then
		Replace(browse.Inset.CustomBG, { as = "groupfinder-background" })
		-- the results list on the inner panel (2e), as the listing's
		EyePanel(browse.Inset)
	end
	SkinPageInset(browse, browse.Inset, browse.ScrollBox)
	SkinOptionsButton(browse.OptionsButton)
	local refresh = browse.RefreshButton
	if refresh and refresh.GetNormalTexture and refresh:GetNormalTexture() then
		Replace(refresh:GetNormalTexture(), { as = "UI-SquareButton-Up", button = refresh, alsoFade = Kit:OtherTextures(refresh, refresh.Icon) })
	end
	HookRows(browse.ScrollBox, SkinBrowseRow, idleTurn)
end

-- the who page
local function SkinWho(who, idleTurn)
	if dressed[who] then
		return
	end
	dressed[who] = true
	SkinPage(who)
	if who.headerBackground then
		Replace(who.headerBackground, { as = "groupfinder-Stat-StoneBG" })
	end
	if who.insideFrame then
		-- the rail around the list, ABOVE the list's rows (a holder under
		-- the page would be hidden by the page's own stone region)
		local level = 3
		local ok, a, b = pcall(function() return who.ScrollBox:GetFrameLevel(), who:GetFrameLevel() end)
		if ok and a and b then
			level = math.max(a - b + 2, 1)
		end
		Replace(who.insideFrame, { as = "common-insideframe", parent = who, rect = who.insideFrame, level = level, body = false })
		-- ... and the darker list-box stone under the rows, as the other lists
		Replace(who.insideFrame, { as = "WhoListBody", noFade = true })
		-- ... under the inner panel (2e): a region of the page, one
		-- sublevel over the stone (which takes the inside frame's layer
		-- and sublevel), inside the rail
		local layer, sub = who.insideFrame:GetDrawLayer()
		EyePanel(who, { rect = who.insideFrame, margin = Kit:RailInset(Kit.framePrefix .. "_l", "l"),
			layer = layer or "BACKGROUND", sublevel = math.min((sub or 0) + 1, 7) })
	end
	if who.EditBox and who.EditBox.Backdrop then
		Replace(who.EditBox.Backdrop, { as = "glues-characterSelect-searchbar" })
	end
	local search = who.WhoSearch
	if search and search.GetNormalTexture and search:GetNormalTexture() then
		Replace(search:GetNormalTexture(), { as = "common-button-tertiary-square-normal", button = search, rect = search, alsoFade = { search:GetHighlightTexture() } })
	end
	HookRows(who.ScrollBox, SkinWhoRow, idleTurn)
end

--------------------------------------------------------------------------------
-- Building the skin
--------------------------------------------------------------------------------
local function BuildSkin()
	if skin then
		return skin
	end
	local pf = LFGParentFrame
	skin = CreateFrame("Frame", "MelloUIGroupFinderSkin", pf)
	skin:SetAllPoints()
	skin:SetFrameLevel(pf:GetFrameLevel())
	skin:EnableMouse(false)
	skin.reps = {}
	skin.followers = {}
	skin.eyePanels = setmetatable({}, { __mode = "k" })   -- [list frame] = its inner panel (EyePanel)
	skin.Replace = Replace
	openedAt = GetTime()

	-- the parent's close button and side tabs
	local close = _G[(pf:GetName() or "LFGParentFrame") .. "CloseButton"]
	if close and close.GetNormalTexture and close:GetNormalTexture() then
		Replace(close:GetNormalTexture(), { as = "RedButton-Exit", button = close, alsoFade = Kit:OtherTextures(close, close:GetNormalTexture()) })
	end
	for _, key in ipairs({ "ListingTab", "BrowsingTab", "WhoListingTab" }) do
		Kit:SkinSideTab(pf[key], Replace)
	end
	-- the bottom tabs, hidden in the style this client uses (side tabs)
	for _, key in ipairs({ "Tab1", "Tab2", "Tab3" }) do
		Claim(pf[key])
	end

	-- the page on show, then every control shown; the other pages wait
	SweepShown(pf, 0)
	return skin
end

function M:RefreshFollowers()
	if not (skin and active) then
		return
	end
	for _, f in ipairs(skin.followers) do
		f.rep:SetShown(f.region:IsShown())
	end
	local n, f = #skin.reps, #skin.followers
	SweepShown(LFGParentFrame, 0)
	EnableFrom(n, f)
	for _, entry in ipairs(skin.rings or {}) do
		Kit:FitPortrait(entry.portrait, entry.ring)
		-- the eye does not cover the ring's opening (its picture is clear
		-- round the eye): the dark disc under it (WINDOW-RULES 2b; user,
		-- 2026-09-25: "the Group Finder Icon does not have a background"),
		-- made once the page's ring is laid out, as the portrait is fitted
		local ring = entry.ring
		-- (Kit:DrawnSize: an atlas piece not laid out yet reads as its sheet)
		if ring.disc == nil and ring.tex and Kit.DrawnSize then
			local w = Kit:DrawnSize(ring.tex)
			if w and w > 0 then
				Kit:RingDisc(ring)
			end
		end
	end
end

local function Activate()
	if active or not LFGParentFrame then
		return
	end
	BuildSkin()
	active = true
	skin:Show()
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	for _, tex in pairs(skin.eyePanels) do
		if tex then
			tex:Show()
		end
	end
	M:RefreshFollowers()
	StartIdle()
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	skin:Hide()
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	for _, tex in pairs(skin.eyePanels) do
		if tex then
			tex:Hide()
		end
	end
	for _, entry in ipairs(skin.rings or {}) do
		Kit:UnfitPortrait(entry.portrait)
	end
end

-- Dressed on the window's first open (user, 2026-09-24: "dress rarely used
-- windows on first open"): the game loads the group finder as soon as the
-- tool is available (SetLookingForGroupUIAvailable, at login), but nothing
-- of the look is built while the window has never been shown. Its OnShow
-- (Hook) builds what it shows before the first frame is drawn, the rest in
-- the frames after (Dressing in steps; a page shown first is dressed in its
-- own OnShow), and it then stays built for the session, switched with the
-- module. In combat too: the skin adds frames and textures of ours, fits the
-- page portraits and sizes the side tabs, none of it secure (the idle turns
-- wait for the fight to end; a part that shows is made at once).
local function Sync()
	local pf = LFGParentFrame
	if M.isEnabled and pf and (skin or pf:IsShown()) then
		Activate()
	else
		Deactivate()
	end
end

local function Hook()
	if hooked or not LFGParentFrame then
		return
	end
	hooked = true
	Perf.HookScript(LFGParentFrame, "OnShow", function()
		openedAt = GetTime()
		Sync()
		M:RefreshFollowers()
		StartIdle()
	end)
	for _, entry in ipairs({ { LFGListingFrame, SkinListing }, { LFGBrowseFrame, SkinBrowse }, { LFGWhoListFrame, SkinWho } }) do
		local page, dress = entry[1], entry[2]
		if page then
			pages[page] = dress
			watched[page] = true        -- (its OnShow below makes what it waits for)
			Perf.HookScript(page, "OnShow", function()
				if skin and active then
					local n, f = #skin.reps, #skin.followers
					Run(page)
					dress(page)
					EnableFrom(n, f)
				end
				M:RefreshFollowers()
			end)
		end
	end
end

local eventFrame = CreateFrame("Frame")
Perf.SetScript(eventFrame, "OnEvent", function(_, _, addon)
	if addon == "Blizzard_GroupFinder_VanillaStyle" and M.isEnabled then
		Hook()
		Sync()
	end
end)

function M:OnEnable(db)
	self.db = db
	if LFGParentFrame then
		Hook()
		Sync()
	else
		eventFrame:RegisterEvent("ADDON_LOADED")
	end
end

function M:OnDisable()
	eventFrame:UnregisterAllEvents()
	Deactivate()
end

--------------------------------------------------------------------------------
-- /gfdump: the window's art (regions by default; "frames", "reps"). Opens
-- the copy window.
--------------------------------------------------------------------------------
SLASH_MELLOGFDUMP1 = "/gfdump"
SlashCmdList.MELLOGFDUMP = function(msg)
	if not LFGParentFrame then
		MelloUI:Print("Group finder window not loaded.")
		return
	end
	MelloUI:ClearLog()
	if not skin then
		MelloUI:Print("Group finder window not dressed yet (it is dressed on its first open): the game's own art only.")
	end
	Kit:DumpWindow(LFGParentFrame, skin, msg)
	MelloUI:ShowLog("gfdump " .. (msg or ""))
end
