--------------------------------------------------------------------------------
-- MelloUI - Legacy Panel
--
-- The Legacy window (LegacySystemFrame: the Reward Track, Challenges and
-- Legacy Tree pages) dressed in the painted kit (Modules/Kit.lua) on the
-- game's own layout, as the character, professions and spell book windows
-- are: every kit piece stands in for one of the game's art regions, on that
-- region's rectangle, as a child (or region) of its frame, faded in place of
-- it (docs/WINDOW-RULES.md).
--
-- State (2026-09-21): the window shell, side tabs, page backdrops, dividers,
-- progress bars (P1), search / filter, category list, criteria rows, icon
-- rims, glyphs, red buttons and scroll bars are on the kit, and the user's
-- catalogue picks (kit_raw/legacy_catalog.png): LC1 challenge cards (rail +
-- stone, header-plate ribbon), LR1 reward cards (rail + stone), LD2 level
-- diamonds (the large gem), LT4 tree cards (the rim only, lit when checked),
-- LS1 spent-points circle (the large gem). The tree's nodes are talent
-- buttons and stay the game's, as the talents page does. /legdump lists the art.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("LegacyPanel")
local hooksecurefunc = Perf.hooksecurefunc
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("LegacyPanel", {
	title = "Legacy Panel",
	desc = "The Legacy window dressed in the painted kit on the game's own layout.",
	window = { label = "Legacy window", desc = "Rewards, challenges and the tree in the kit.", tab = "Windows", order = 4,
		frames = { "LegacySystemFrame" }, plainGrab = true, addon = "Blizzard_LegacySystem", firstOpen = true },
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

-- The eye strain rule (user, 2026-09-24: "too much small text over a plain
-- brown border is just an eye strain" / "apply the eye strain rule to all
-- existing windows"; docs/WINDOW-RULES.md 2e): text lies on the palette's
-- inner panel at this alpha over the page's stone, never on the bare stone.
local DIM_ALPHA = 0.8

-- The inner panel behind a list that has no card or inset of its own (the
-- challenges' category list, the tree selection column): a region of the
-- list's own frame, low in its BACKGROUND layer, so every row, text and
-- control of the list (its children) is drawn over it and it goes wherever
-- the list goes; on `rect` (the rows' area), `pad` px out from it. A tint
-- over the page's stone, not a second stone (one stone per surface). Shown
-- while the skin is on (Activate / Deactivate).
local function ListDim(owner, rect, pad)
	if not (owner and owner.CreateTexture and rect) then
		return
	end
	pad = pad or 0
	local tex = owner:CreateTexture(nil, "BACKGROUND", nil, 7)
	tex:SetPoint("TOPLEFT", rect, "TOPLEFT", -pad, pad)
	tex:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", pad, -pad)
	local c = MelloUI.Palette.innerPanel
	tex:SetColorTexture(c[1], c[2], c[3], DIM_ALPHA)
	tex.kitPiece = true   -- ours: never faded with the game's art
	tex:SetShown(active)
	skin.dims[#skin.dims + 1] = tex
end

local function Replace(region, opts)
	if not region then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Legacy panel: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

-- A rep shown while the game shows `region` (art the game toggles itself).
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

-- A region the game re-atlases with a state: one rep per atlas seen on it,
-- the current one shown; the rep is built on `rect` (the button's rect for
-- a plate, the region's for a glyph), `button` follows hover.
local function StateReps(owner, region, rect, button, extra)
	if not (owner and region) then
		return
	end
	owner.melloStates = owner.melloStates or {}
	local key = Kit:ArtKey(region)
	if key and Kit.Replacements[key] and owner.melloStates[key] == nil then
		owner.melloStates[key] = Replace(region, { as = key, button = button, rect = rect or region, alsoFade = extra }) or false
	end
	for k, rep in pairs(owner.melloStates) do
		if rep then
			rep:SetShown(k == key)
		end
	end
end

-- The portrait: the game's shield (Legacy-up-c60, 45 x 62 at the corner)
-- fitted into the ring's opening like the class medallion (Kit:FitPortrait).
local function Portrait()
	local lf = LegacySystemFrame
	return lf and lf.GetPortrait and lf:GetPortrait()
end

--------------------------------------------------------------------------------
-- The challenges page: the category list (headers and leaves, re-atlased
-- with the selection), the challenge cards (pooled by the detail pane's
-- ScrollBox) and their criteria rows (pooled under LegacyChallengeObjectives).
--------------------------------------------------------------------------------

-- A category row (LegacyChallengeCategoryTemplate = ListHeaderVisualTemplate):
-- a header's plate is the category plate (the game's atlas), a leaf's the
-- plain / selected plate; the header's +/- glyph is the kit's.
local function SkinCategoryRow(row)
	if not (row.GetNormalTexture and row:GetNormalTexture()) then
		return
	end
	local normal = row:GetNormalTexture()
	local highlight = row.GetHighlightTexture and row:GetHighlightTexture()
	StateReps(row, normal, row, row, highlight and { highlight } or nil)
	local collapse = row.CollapseButton or (row.GetCollapseButton and row:GetCollapseButton())
	Kit:SkinCollapseButton(collapse, Replace)
	if not row.melloKitHooked then
		row.melloKitHooked = true
		hooksecurefunc(row, "RefreshCardArt", function(r)
			if active then
				SkinCategoryRow(r)
			end
		end)
		if collapse and collapse.UpdateCollapsedState then
			hooksecurefunc(collapse, "UpdateCollapsedState", function()
				if active then
					Kit:SkinCollapseButton(collapse, Replace)
				end
			end)
		end
	end
end

-- A criteria row (LegacyChallengeCriteriaTemplate): the plain plate for its
-- Background (shown by the game when no progress bar is), P1 on its bar.
local function SkinCriteria(criteria)
	if criteria.melloRep ~= nil then
		return
	end
	criteria.melloRep = false
	if criteria.Background then
		local rep = Replace(criteria.Background, { as = "Legacy-Challenge-Cards-Bar", rect = criteria })
		criteria.melloRep = rep or false
		Follow(rep, criteria.Background)
	end
	local bar = criteria.ProgressBar
	if bar and bar.ProgressBarFrame and criteria.ProgressBarBackground then
		Kit:SkinStatusBar(bar, bar.ProgressBarFrame, criteria.ProgressBarBackground, Replace, "Legacy-Progressbar-Frame")
	end
end

local function SkinCriteriaIn(objectives)
	for _, child in ipairs({ objectives:GetChildren() }) do
		if child.Background and child.Name then
			SkinCriteria(child)
		end
	end
end

-- A challenge card (LegacyChallengeTemplate; LC1): single rail + stone on
-- the card's rect for its body (collapsed picture or expanded tiled trio),
-- the header plate for its title ribbon (one rep per atlas the game puts
-- there), the round rim on its icon frame, the +/- glyph, the tracking check
-- box; the selection overlay stays the game's.
local function SkinChallengeCard(card)
	if card.melloRep == nil then
		card.melloRep = false
		if card.Background then
			-- `dim`: the card's text (its description, the criteria) on the
			-- palette's inner panel inside its rail, not on the bare stone
			-- (user, 2026-09-24: "apply the eye strain rule to all existing
			-- windows", WINDOW-RULES 2e)
			Replace(card.Background, { as = "Legacy-Challenge-Cards", rect = card, dim = DIM_ALPHA,
				alsoFade = { card.BackgroundTop, card.BackgroundMiddle, card.BackgroundBottom } })
		end
		if card.TitleBar then
			for _, m in ipairs({ "Saturate", "Desaturate" }) do
				if card[m] then
					hooksecurefunc(card, m, function(c)
						if active then
							StateReps(c, c.TitleBar, c.TitleBar, nil)
						end
					end)
				end
			end
		end
		if card.Icon and card.Icon.frame and card.Icon.texture then
			-- the rim's opening is the 50 px masked icon, on the icon's centre
			local rect = Kit:RimRect(card.Icon, "roundslot", card.Icon.texture:GetWidth(), card.Icon.texture)
			card.melloRep = Replace(card.Icon.frame, { as = "Legacy-Tree-Frame-icon-frame", button = card.Icon, rect = rect }) or false
		end
		local tracked = card.Tracked
		if tracked and tracked.GetNormalTexture and tracked:GetNormalTexture() then
			local key = Kit:ArtKey(tracked:GetNormalTexture())
			if not (key and Kit.Replacements[key]) then
				key = "UI-CheckBox-Up"
			end
			Kit:SkinCheckButton(tracked, Replace, key)
		end
		hooksecurefunc(card, "UpdatePlusMinusArt", function(c)
			if active and c.PlusMinus then
				Kit:StateIconReps(c, c.PlusMinus, c, Replace)
			end
		end)
	end
	if card.PlusMinus then
		Kit:StateIconReps(card, card.PlusMinus, card, Replace)
	end
	if card.TitleBar then
		StateReps(card, card.TitleBar, card.TitleBar, nil)
	end
end

--------------------------------------------------------------------------------
-- The reward track page: its cards (RenownLevelMixin, re-atlased per Refresh)
-- get the square rim on their icon border; the card's body and level diamond
-- stay the game's until the user picks (catalogue).
--------------------------------------------------------------------------------
local function SkinRewardCard(card)
	if card.melloKitHooked then
		return
	end
	card.melloKitHooked = true
	local function Rims(c)
		if not active then
			return
		end
		if c.RewardCardBG and c.melloBody == nil then
			-- the card's body (LR1): the rail + stone, whatever the game atlases
			-- the BG to; the reward's name and level on the inner panel over
			-- that stone (WINDOW-RULES 2e, user 2026-09-24)
			c.melloBody = Replace(c.RewardCardBG, { as = "Legacy-Rewards-Tracker-Cards", rect = c, dim = DIM_ALPHA }) or false
		end
		if c.IconBorder and c.Icon then
			-- the rim's opening is the 64 px icon (the game's border is 80 on it)
			c.melloRim = c.melloRim or Kit:RimRect(c, "slot", c.Icon:GetWidth(), c.Icon)
			StateReps(c, c.IconBorder, c.melloRim, nil)
		end
		if c.LevelSquare then
			-- the level diamond (LD2): the large gem, one rep per atlas
			c.melloLevels = c.melloLevels or {}
			local key = Kit:ArtKey(c.LevelSquare)
			if key and Kit.Replacements[key] and c.melloLevels[key] == nil then
				c.melloLevels[key] = Replace(c.LevelSquare, { as = key, rect = c.LevelSquare }) or false
			end
			for k, rep in pairs(c.melloLevels) do
				if rep then
					rep:SetShown(k == key)
				end
			end
		end
	end
	hooksecurefunc(card, "Refresh", Rims)
	Rims(card)
end

--------------------------------------------------------------------------------
-- The tree page: the selection cards (pooled), the selected tree's big ring,
-- the points plate, Apply, the search box; the trait nodes stay the game's.
--------------------------------------------------------------------------------
-- A tree selection card (LT4): no card — the round rim on the icon, lit
-- while the card is checked (the game's card picture and glow faded).
local function SkinTreeCard(button)
	if button.melloRep ~= nil then
		return
	end
	button.melloRep = false
	if button.Background then
		Replace(button.Background, { as = "Legacy-Tree-Frame-Card" })
	end
	if button.SelectedGlow then
		Replace(button.SelectedGlow, { as = "Legacy-Tree-Frame-Card-Glow" })
	end
	if button.Ring then
		-- the ring's opening is the button's masked icon (67 px; the game's ring is 70 on it)
		local rect = Kit:RimRect(button, "roundslot", button:GetWidth(), button)
		button.melloRep = Replace(button.Ring, { as = "Legacy-Tree-Frame-Card-Ring", button = button, rect = rect,
			checked = function() return button:GetChecked() and true or false end,
			alsoFade = { button.HighlightTexture } }) or false
		if button.melloRep and button.RefreshSelectionVisuals then
			hooksecurefunc(button, "RefreshSelectionVisuals", function()
				if active and button.melloRep.object.Update then
					button.melloRep.object:Update()
				end
			end)
		end
	end
end

local function SkinTreeCards(panel)
	local layout = panel and panel.TreeSelections
	if not layout then
		return
	end
	for _, child in ipairs({ layout:GetChildren() }) do
		if child.Ring then
			SkinTreeCard(child)
		end
	end
end

--------------------------------------------------------------------------------
-- Building the skin
--------------------------------------------------------------------------------
local function BuildSkin()
	if skin then
		return skin
	end
	local lf = LegacySystemFrame
	skin = CreateFrame("Frame", "MelloUILegacySkin", lf)
	skin:SetAllPoints()
	skin:SetFrameLevel(lf:GetFrameLevel())
	skin:EnableMouse(false)
	skin.reps = {}
	skin.followers = {}
	skin.dims = {}         -- the lists' inner panels (ListDim)
	skin.Replace = Replace

	-- the window: outer rail, streaks, the ring on the shield's corner, title, close
	Kit:SkinWindowShell(lf, Replace, skin, { portrait = Portrait() })
	-- the shield does not fill the ring: a dark disc behind it (agreed addition, user 2026-09-21)
	Kit:RingDisc(skin.ring)
	-- the side tabs (Reward Track / Challenges / Tree)
	for _, tab in ipairs(lf.Tabs or {}) do
		Kit:SkinSideTab(tab, Replace)
	end

	-- the pages' backdrops are all fitted to the WINDOW's rect (the pages'
	-- own rects differ by a few px): one picture, in one place, on every page,
	-- stopping at the outer rail's inner bevel so the rail is in front of it
	-- (user, 2026-09-21)
	-- the reward track page
	local rt = lf.RewardTrackPage
	if rt then
		if rt.Background then
			Replace(rt.Background, { as = "Legacy-Rewards-Tracker-background", rect = lf, inset = Kit:OuterRailInset() })
		end
		local bar = rt.LegacyRewardProgressBar
		if bar and bar.ProgressBarFrame and rt.ProgressBarBackground then
			Kit:SkinStatusBar(bar, bar.ProgressBarFrame, rt.ProgressBarBackground, Replace, "Legacy-Progressbar-Frame")
		end
		local track = rt.LegacyRewardProgressFrame
		if track then
			for _, entry in ipairs({ { track.LeftButton, "ui-journeys-delve-arrow-small-left" }, { track.JumpLeftButton, "ui-journeys-delve-arrow-small-left" },
				{ track.RightButton, "ui-journeys-delve-arrow-small-right" }, { track.JumpRightButton, "ui-journeys-delve-arrow-small-right" } }) do
				local b, key = entry[1], entry[2]
				if b and b.GetNormalTexture and b:GetNormalTexture() then
					local art = Kit:ArtKey(b:GetNormalTexture())
					Replace(b:GetNormalTexture(), { as = (art and Kit.Replacements[art]) and art or key, button = b,
						alsoFade = Kit:OtherTextures(b, b:GetNormalTexture()) })
				end
			end
			if track.GetElements then
				for _, card in ipairs(track:GetElements() or {}) do
					SkinRewardCard(card)
				end
			end
		end
	end

	-- the challenges page
	local cp = lf.ChallengesPage
	if cp then
		if cp.Background then
			Replace(cp.Background, { as = "Legacy-Challenge-BG", rect = lf, inset = Kit:OuterRailInset() })
		end
		local list = cp.CategoryList
		if list then
			local filter = list.FilterDropdown
			if filter and filter.Background then
				Replace(filter.Background, { as = "common-dropdown-b-button", rect = filter, button = filter, parent = filter })
			end
			Kit:SkinSearchBox(list.SearchBox, Replace)
			Kit:HookScrollBoxRows(list.ScrollBox, SkinCategoryRow, IsActive)
			-- the category rows (a column of small names) on the inner panel
			ListDim(list, list.ScrollBox, 4)
		end
		local detail = cp.DetailPane
		if detail then
			Kit:HookScrollBoxRows(detail.ScrollBox, SkinChallengeCard, IsActive)
		end
		local summary = cp.LegacyChallengePointSummary
		if summary and summary.PointsBar and summary.PointsBar.ProgressBarFrame and summary.ProgressBarBackground then
			Kit:SkinStatusBar(summary.PointsBar, summary.PointsBar.ProgressBarFrame, summary.ProgressBarBackground, Replace, "Legacy-Progressbar-Frame")
		end
		local divider = cp.VerticalDivider and Kit:FirstTexture(cp.VerticalDivider)
		if divider then
			Replace(divider, { as = "Legacy-Tree-Frame-divider-Vertical" })
		end
		if LegacyChallengeObjectives and LegacyChallengeObjectives.Display then
			hooksecurefunc(LegacyChallengeObjectives, "Display", function(o)
				if active then
					SkinCriteriaIn(o)
				end
			end)
			SkinCriteriaIn(LegacyChallengeObjectives)
		end
	end

	-- the tree page
	local tp = lf.TreePage
	if tp then
		if tp.Background then
			Replace(tp.Background, { as = "Legacy-Tree-Frame-background", rect = lf, inset = Kit:OuterRailInset() })
		end
		local sel = tp.LegacyTreeSelectionPanel
		if sel then
			-- the tree selection column (the trees' names and texts beside
			-- their rings) on the inner panel; the trait panel beside it is
			-- the talent tree itself, a picture of nodes, and keeps the stone
			ListDim(sel, sel, 0)
			SkinTreeCards(sel)
			if sel.RefreshTreeButtons then
				hooksecurefunc(sel, "RefreshTreeButtons", function(s)
					if active then
						SkinTreeCards(s)
					end
				end)
			end
		end
		local summary = tp.LegacyTreePointSummary
		if summary and summary.Border then
			Replace(summary.Border, { as = "Legacy-Tree-Frame-Points-Bar", rect = summary.Border })
		end
		local trait = tp.LegacyTreeTraitPanel
		if trait then
			local spent = trait.SpentPointsFrame
			if spent and spent.Background then
				Replace(spent.Background, { as = "Legacy-Tree-Frame-level-circle", rect = spent.Background })   -- LS1
			end
			local icon = trait.SelectedTreeIcon
			if icon and icon.Ring then
				-- the ring's opening is the 110 px masked icon (the game's ring is 130 on it)
				local rect = Kit:RimRect(icon, "roundslot", icon:GetWidth(), icon)
				Replace(icon.Ring, { as = "Legacy-Tree-Frame-Ring-big", button = icon, rect = rect, alsoFade = { icon.HighlightTexture } })
			end
			Kit:SkinRedButton(trait.ApplyButton, Replace)
			Kit:SkinSearchBox(trait.SearchBox, Replace)
		end
		local divider = tp.VerticalDivider and (tp.VerticalDivider.VerticalDivider or Kit:FirstTexture(tp.VerticalDivider))
		if divider then
			Replace(divider, { as = "Legacy-Tree-Frame-divider-Vertical" })
		end
	end

	Kit:SkinScrollBarsIn(lf, Replace, skin)
	return skin
end

function M:RefreshFollowers()
	if not (skin and active) then
		return
	end
	for _, f in ipairs(skin.followers) do
		f.rep:SetShown(f.region:IsShown())
	end
	Kit:SkinScrollBarsIn(LegacySystemFrame, Replace, skin)
	Kit:FitPortrait(Portrait(), skin.ring)
end

local function Activate()
	if active or not LegacySystemFrame then
		return
	end
	BuildSkin()
	active = true
	skin:Show()
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	for _, tex in ipairs(skin.dims) do
		tex:Show()
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
	for _, tex in ipairs(skin.dims) do
		tex:Hide()
	end
	Kit:UnfitPortrait(Portrait())
end

-- Dressed on the window's first open (user, 2026-09-24: "dress rarely used
-- windows on first open"): Blizzard_LegacySystem loads on demand (the micro
-- button), and even once it is loaded nothing of the look is built while the
-- window has never been shown. Its OnShow (Hook) builds it before the first
-- frame is drawn, and it then stays built for the session, switched with the
-- module. In combat too: the skin adds frames and textures of ours, fits the
-- shield, sizes the side tabs and lays the progress bars into their
-- brackets, none of it secure.
local function Sync()
	local lf = LegacySystemFrame
	if M.isEnabled and lf and (skin or lf:IsShown()) then
		Activate()
	else
		Deactivate()
	end
end

local function Hook()
	if hooked or not LegacySystemFrame then
		return
	end
	hooked = true
	Perf.HookScript(LegacySystemFrame, "OnShow", function()
		Sync()
		M:RefreshFollowers()
	end)
	for _, page in ipairs(LegacySystemFrame.Pages or {}) do
		Perf.HookScript(page, "OnShow", function()
			M:RefreshFollowers()
		end)
	end
end

-- Blizzard_LegacySystem is loaded on demand: wait for it.
local eventFrame = CreateFrame("Frame")
Perf.SetScript(eventFrame, "OnEvent", function(_, _, addon)
	if addon == "Blizzard_LegacySystem" and M.isEnabled then
		Hook()
		Sync()
	end
end)

function M:OnEnable(db)
	self.db = db
	if LegacySystemFrame then
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
-- /legdump: the window's art (regions by default; "frames", "reps"). Opens
-- the copy window.
--------------------------------------------------------------------------------
SLASH_MELLOLEGDUMP1 = "/legdump"
SlashCmdList.MELLOLEGDUMP = function(msg)
	if not LegacySystemFrame then
		MelloUI:Print("Legacy window not loaded.")
		return
	end
	MelloUI:ClearLog()
	if not skin then
		MelloUI:Print("Legacy window not dressed yet (it is dressed on its first open): the game's own art only.")
	end
	Kit:DumpWindow(LegacySystemFrame, skin, msg)
	MelloUI:ShowLog("legdump " .. (msg or ""))
end
