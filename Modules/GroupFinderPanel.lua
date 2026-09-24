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
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("GroupFinderPanel", {
	title = "Group Finder Panel",
	desc = "The looking-for-group window dressed in the painted kit on the game's own layout.",
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

	-- the parent's close button and side tabs
	local close = _G[(pf:GetName() or "LFGParentFrame") .. "CloseButton"]
	if close and close.GetNormalTexture and close:GetNormalTexture() then
		Replace(close:GetNormalTexture(), { as = "RedButton-Exit", button = close, alsoFade = Kit:OtherTextures(close, close:GetNormalTexture()) })
	end
	for _, key in ipairs({ "ListingTab", "BrowsingTab", "WhoListingTab" }) do
		Kit:SkinSideTab(pf[key], Replace)
	end

	-- the listing page
	local listing = LFGListingFrame
	if listing then
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
			Kit:HookScrollBoxRows(activity.ScrollBox, SkinActivityRow, IsActive)
		end
	end

	-- the browse page
	local browse = LFGBrowseFrame
	if browse then
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
		Kit:HookScrollBoxRows(browse.ScrollBox, SkinBrowseRow, IsActive)
	end

	-- the who page
	local who = LFGWhoListFrame
	if who then
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
		Kit:HookScrollBoxRows(who.ScrollBox, SkinWhoRow, IsActive)
	end

	Kit:SweepControls(pf, Replace, skin)
	return skin
end

function M:RefreshFollowers()
	if not (skin and active) then
		return
	end
	for _, f in ipairs(skin.followers) do
		f.rep:SetShown(f.region:IsShown())
	end
	Kit:SweepControls(LFGParentFrame, Replace, skin)
	for _, entry in ipairs(skin.rings or {}) do
		Kit:FitPortrait(entry.portrait, entry.ring)
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

local function Sync()
	if M.isEnabled and LFGParentFrame then
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
	LFGParentFrame:HookScript("OnShow", function()
		Sync()
		M:RefreshFollowers()
	end)
	for _, page in ipairs({ LFGListingFrame, LFGBrowseFrame, LFGWhoListFrame }) do
		if page then
			page:HookScript("OnShow", function() M:RefreshFollowers() end)
		end
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, _, addon)
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
	Kit:DumpWindow(LFGParentFrame, skin, msg)
	MelloUI:ShowLog("gfdump " .. (msg or ""))
end
