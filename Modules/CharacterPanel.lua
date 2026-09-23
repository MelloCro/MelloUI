--------------------------------------------------------------------------------
-- MelloUI - Character Panel
--
-- Dresses Blizzard's default character window in the painted kit without
-- changing its layout. The game keeps every size and position; each piece
-- of game art is handed to the kit's replacement library (Kit:Replace,
-- Modules/Kit.lua: the game's atlas -> the kit piece), which puts the mapped
-- piece on the art's own rectangle as a child of the art's frame and fades
-- the original. This module only says WHICH game art to replace and mirrors
-- the game's own state onto the pieces (collapsed headers, selected rows,
-- the selected side tab, art the game shows and hides itself).
--
-- Rules (docs/HANDOVER.md 3.9, docs/KIT-MAPPING.md):
--   * replace, never add: no piece without a game element under it (one
--     agreed exception: the single-rail frame around the character viewport)
--   * the piece takes the element's rectangle, size and visibility
--   * the piece is a child of the element's frame (never of our skin), so
--     it shows, hides, moves and collapses with the game's window
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("CharacterPanel", {
	title = "Character Panel",
	desc = "The character window dressed in the painted kit: stone frame, slot rims, framed panes and stats, all on the game's own layout.",
	enabledByDefault = true,
	defaults = {
		movable = false,
		statRows = true,
	},
	options = {
		{ type = "header", name = "Window" },
		{ type = "toggle", key = "movable", name = "Unlocked",
		  desc = "Drag the window anywhere by its frame." },
		{ type = "toggle", key = "statRows", name = "Stat row plates",
		  desc = "A painted plate where the game draws its row background (every other stat row)." },
	},
})

local SLOT_NAMES = { "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
	"CharacterChestSlot", "CharacterShirtSlot", "CharacterTabardSlot", "CharacterWristSlot",
	"CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
	"CharacterFinger0Slot", "CharacterFinger1Slot", "CharacterTrinket0Slot", "CharacterTrinket1Slot",
	"CharacterMainHandSlot", "CharacterSecondaryHandSlot", "CharacterRangedSlot", "CharacterAmmoSlot" }

local skin = nil        -- our frame under the window (drag handle) and the registry of replacements
local active = false
local hooked = false

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- A value the client hides from addons (secret): never do arithmetic on it.
local function Secret(v)
	return issecretvalue and issecretvalue(v)
end

local SkinProgressBar     -- defined with the list code below; the detail panes use it in BuildSkin

-- The first game texture of a frame (the picture a Blizzard frame paints).
local function FirstTexture(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece then
			return region
		end
	end
end

-- A replacement the library knows; registered so enable/disable reach it
-- (and shown at once when made after activation: a late row, a glyph).
local function Replace(region, opts)
	if not region then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Character panel: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

-- Every check box under `frame` whose art is the game's minimal check box.
local function SkinCheckboxes(frame)
	for _, child in ipairs({ frame:GetChildren() }) do
		if child:GetObjectType() == "CheckButton" and child.GetNormalTexture and child:GetNormalTexture() and child.melloRep == nil then
			local normal = child:GetNormalTexture()
			if Kit:ArtKey(normal) == "checkbox-minimal" then
				child.melloRep = Replace(normal, { as = "checkbox-minimal", button = child,
					alsoFade = { child:GetPushedTexture(), child:GetCheckedTexture(), child:GetHighlightTexture(), child:GetDisabledTexture() } }) or false
			end
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
	local cf = CharacterFrame
	skin = CreateFrame("Frame", "MelloUICharacterSkin", cf)
	skin:SetAllPoints()
	skin:SetFrameLevel(cf:GetFrameLevel())
	skin.reps = {}         -- every replacement, for enable / disable
	skin.followers = {}    -- replacements of art the game shows and hides itself: { rep, region }

	-- drag handle for the unlocked window
	skin:EnableMouse(true)
	skin:RegisterForDrag("LeftButton")
	skin:SetScript("OnDragStart", function()
		if M.db.movable then
			cf:StartMoving()
		end
	end)
	skin:SetScript("OnDragStop", function()
		cf:StopMovingOrSizing()
	end)

	-- the window: its nine-slice frame, plus the backdrop texture that frame draws
	if cf.NineSlice then
		-- no gem corner at the top-left: the portrait ring is that corner
		skin.window = Replace(cf.NineSlice, { as = "NineSlicePanelTemplate", parent = cf, rect = cf, alsoFade = { cf.Bg }, skip = "tl" })
	end
	if cf.TopTileStreaks then
		Replace(cf.TopTileStreaks, { as = "_UI-Frame-TopTileStreaks", parent = cf })
	end

	-- the ring around the game's portrait (the nine-slice's portrait corner)
	local portrait = cf.PortraitContainer and cf.PortraitContainer.portrait
	local corner = cf.NineSlice and cf.NineSlice.TopLeftCorner
	if portrait and corner then
		skin.ring = Replace(corner, { as = "UI-Frame-PortraitMetal-CornerTopLeft", parent = cf.PortraitContainer, center = portrait })
		skin.portrait = portrait
	end

	-- the title bar: in this client the container holds only the text (no
	-- background art, /cpdump title), so the plate is an agreed addition on
	-- the container's rectangle, under the text
	local tc = cf.TitleContainer
	if tc then
		local bg = FirstTexture(tc)
		if bg then
			skin.title = Replace(bg, { as = "TitleBar", parent = tc, rect = tc })
		else
			skin.title = Replace(tc, { as = "TitleBar", parent = tc, rect = tc, noFade = true })
		end
	end
	local close = cf.CloseButton
	if close and close.GetNormalTexture and close:GetNormalTexture() then
		local extra = {}
		for _, region in ipairs({ close:GetRegions() }) do
			if region:GetObjectType() == "Texture" and region ~= close:GetNormalTexture() then
				extra[#extra + 1] = region
			end
		end
		Replace(close:GetNormalTexture(), { as = "RedButton-Exit", button = close, alsoFade = extra })
	end

	-- the panes' backdrop pictures and the divider between them
	if cf.LeftPaneHost then
		Replace(FirstTexture(cf.LeftPaneHost), { as = "UI-Character-Info-General-BG" })
	end
	local host = cf.RightPaneHost
	if host then
		local bg = FirstTexture(host)
		if bg and bg ~= host.StoneBg then
			local stone = Replace(bg, { as = "UI-Character-Info-Stat-BG" })
			-- a parchment sheet on the right pane's stone, behind every tab
			-- that shows there (stats, the reputation / skill / honor /
			-- currency details, statistics), filling nearly the whole pane so
			-- the text sits ON the parchment, its edge in the FINE strokes
			-- that end before the first letters (user, 2026-09-23: "make sure
			-- that the text is inside of the parchment itself"). A region of
			-- the stone's holder, one sublevel above the stone: it comes and
			-- goes with the skin.
			if stone and stone.object and stone.object ~= stone.tex and Kit.ParchmentSheet then
				Kit:ParchmentSheet(stone.object, stone.object, { rect = stone.object, margin = 2, fine = true, sublevel = 1, area = "character" })
			end
		end
		if host.StoneBg then
			-- shown by the game on the paper doll only
			local plate = Replace(host.StoneBg, { as = "UI-Character-Info-Stat-StoneBG" })
			if plate then
				skin.followers[#skin.followers + 1] = { rep = plate, region = host.StoneBg }
			end
		end
		-- the divider is the unnamed child that paints the divider atlas (the
		-- host has other unnamed children without any texture)
		for _, child in ipairs({ host:GetChildren() }) do
			local tex = not child:GetName() and FirstTexture(child)
			if tex and not skin.divider then
				skin.divider = Replace(tex, { as = "common-framedivider", level = 0 })
				skin.dividerFrame = skin.divider and child
			end
		end
	end

	-- the stats scroll boxes: their inset frame and the class picture under the stats
	for _, box in ipairs({ CharacterStatsPaneScrollBox, CharacterStatsPanePetScrollBox }) do
		if box and box.Border then
			Replace(box.Border, { as = "common-insideframe", alsoFade = box.ClassBackground and { box.ClassBackground } or nil })
		end
	end

	-- the divider's junctions (an agreed addition, the user's pick K): where
	-- it leaves the title plate, where the stats inset's top rail meets it,
	-- and where it ends on the window's bottom rail. The covers live on the
	-- divider's frame (level 505 in the game's layout, above both panes) so
	-- they go with it; the stats ones show with their box.
	if skin.divider and skin.dividerFrame then
		local function Joint(opts)
			local rep = Kit:Joint(skin.dividerFrame, opts)
			if rep then
				skin.reps[#skin.reps + 1] = rep
			end
			return rep
		end
		local strip = skin.title and skin.title.strip
		local mid = strip and Kit:Piece(strip.base .. "_mid_" .. strip.state)
		if mid and mid.box then
			-- the plate's bottom rail band is rows 75-86 of the 89 px canvas
			-- (its box ends at 86): the centre line, 5.5 px up from the box
			Joint({ x = skin.divider, y = strip, dy = (mid.h - mid.box[4] + 5.5) * strip.scale })
		end
		for _, box in ipairs({ CharacterStatsPaneScrollBox, CharacterStatsPanePetScrollBox }) do
			if box and box.Border then
				-- the inset's top rail (Border is 1 px inside the box) and the
				-- stone plate's bottom rail above it both meet the divider at
				-- the box's top edge; one cover, on that edge
				local rep = Joint({ x = skin.divider, y = box, yPoint = "TOP" })
				if rep then
					skin.followers[#skin.followers + 1] = { rep = rep, region = box }
				end
			end
		end
		-- the window's bottom rail lies outside the window (outset): its own centre line
		local bottomRail = skin.window and skin.window.skin and skin.window.skin.b
		if bottomRail then
			Joint({ x = skin.divider, y = bottomRail, yPoint = "CENTER" })
		end
	end

	-- the plate under "Level N Class"
	if _G.CharacterLevelTextBackground then
		Replace(_G.CharacterLevelTextBackground, { as = "UI-Character-Info-ItemLevel-Bounce" })
	end

	-- the model's backdrop: four landscape quadrants (race pictures) under the
	-- character. One stone tile stands in for all four, on their union, at the
	-- scene's own level; the game's vignette overlay stays on top as it is.
	local scene = CharacterModelScene
	if scene and scene.BackgroundTopLeft and scene.BackgroundBotRight then
		local union = CreateFrame("Frame", nil, scene)
		union:EnableMouse(false)
		union:SetPoint("TOPLEFT", scene.BackgroundTopLeft, "TOPLEFT")
		union:SetPoint("BOTTOMRIGHT", scene.BackgroundBotRight, "BOTTOMRIGHT")
		Replace(scene.BackgroundTopLeft, { as = "ModelSceneBackground", parent = scene, rect = union, level = 0,
			alsoFade = { scene.BackgroundTopRight, scene.BackgroundBotLeft, scene.BackgroundBotRight } })
		-- the agreed exception to "replace, never add": a frame around the
		-- viewport, hugging the scene's rectangle, over the backdrop
		Replace(scene, { as = "ViewportFrame", parent = scene, rect = scene, noFade = true })
	end

	-- every equipment slot: the gear-slot border picture inside its 1 x 1
	-- BorderFrame. The game's pictures overlap so neighbouring slots share
	-- their corner diamonds; the rim is sized to the slot pitch for the same.
	local function Pitch(a, b, axis)
		if not (a and b) then
			return 0
		end
		local ok, d = pcall(function()
			local ax, ay = a:GetCenter()
			local bx, by = b:GetCenter()
			return math.abs(axis == "x" and (ax - bx) or (ay - by))
		end)
		return (ok and d and not (issecretvalue and issecretvalue(d))) and d or 0
	end
	local pitch = { Pitch(_G.CharacterMainHandSlot, _G.CharacterSecondaryHandSlot, "x"), Pitch(_G.CharacterHeadSlot, _G.CharacterNeckSlot, "y") }
	if pitch[1] <= 0 then
		pitch[1] = pitch[2]
	end
	for _, name in ipairs(SLOT_NAMES) do
		local slot = _G[name]
		if slot and slot.BorderFrame then
			local border = FirstTexture(slot.BorderFrame)
			if border then
				Replace(border, { as = "UI-Character-Info-GearSlot", button = slot, parent = slot, pitch = pitch })
			end
		end
	end

	-- the side tabs: the tab's background, selected when the game's selectedTab is this one
	local tabs = cf.ModeTabs and cf.ModeTabs.Tabs
	skin.tabReps = {}
	if tabs then
		for _, tab in ipairs(tabs) do
			if tab.Background then
				local id = tab:GetID()
				local rep = Replace(tab.Background, { as = "common-sidetab", button = tab, parent = tab, icon = tab.Icon,
					checked = function() return cf.selectedTab == id end,
					alsoFade = { tab.SelectedTexture, tab.TabGlow, tab.HighlightTexture } })
				if rep then
					skin.tabReps[#skin.tabReps + 1] = rep
				end
			end
		end
	end

	-- the detail panes of the reputation, currency, skills and PvP tabs: their
	-- divider line, hidden by the game when the pane is empty
	local sidePanes = {
		_G.ReputationFrame and _G.ReputationFrame.ReputationDetailFrame,
		_G.SkillsFrame and _G.SkillsFrame.SkillDetailFrame,
		_G.PVPRankFrame and _G.PVPRankFrame.DetailFrame,
		_G.TokenFrame and _G.TokenFrame.DetailFrame,
	}
	-- the button that folds the right pane away: the game swaps its arrow
	-- with the state (UpdateRightPaneToggleButton: PrevPage open, NextPage
	-- collapsed), so one replacement per texture, the current one shown
	local toggle = cf.RightPaneToggleButton
	if toggle and toggle.GetNormalTexture and toggle:GetNormalTexture() then
		-- file textures read back as numeric ids here, so the key comes from
		-- the game's own state flag, not from the texture
		local normal = toggle:GetNormalTexture()
		local extra = { toggle:GetPushedTexture(), toggle:GetHighlightTexture() }
		local icons = {}
		local function Icons()
			if not active then
				return
			end
			local key = cf:IsRightPaneCollapsed() and "UI-SpellbookIcon-NextPage-Up" or "UI-SpellbookIcon-PrevPage-Up"
			if icons[key] == nil then
				icons[key] = Replace(normal, { as = key, button = toggle, rect = toggle, alsoFade = extra }) or false
			end
			for k, rep in pairs(icons) do
				if rep then
					rep:SetShown(k == key)
				end
			end
		end
		if cf.UpdateRightPaneToggleButton then
			hooksecurefunc(cf, "UpdateRightPaneToggleButton", Icons)
		end
		skin.toggleIcons = Icons
	end
	for _, pane in pairs(sidePanes) do
		-- the standing / rank bar of the reputation and skill detail panes
		SkinProgressBar(pane.StandingBar or pane.RankBar)
		SkinCheckboxes(pane)
		if pane.Divider then
			local rep = Replace(pane.Divider, { as = "UI-Character-Info-ScrollLine" })
			if rep then
				skin.followers[#skin.followers + 1] = { rep = rep, region = pane.Divider }
				for _, method in ipairs({ "SetEmpty", "ClearEmpty" }) do
					if pane[method] then
						hooksecurefunc(pane, method, function()
							if active then
								rep:SetShown(pane.Divider:IsShown())
							end
						end)
					end
				end
			end
		end
	end

	-- the PvP tab: the line under the rank name
	local pvp = _G.PVPRankFrame
	if pvp and pvp.MainInfoFrame and pvp.MainInfoFrame.Line then
		Replace(pvp.MainInfoFrame.Line, { as = "UI-Character-Info-Honor-LevelBG" })
	end

	skin:Hide()
	return skin
end

--------------------------------------------------------------------------------
-- The portrait: when it shows the painted class medallion (Modules/ClassIcons),
-- it is sized so the medallion's gold rim sits just inside the ring's opening.
-- Measured on the art: the ring's opening radius is 0.304 of the ring, the
-- medallion's rim radius 0.473 of the medallion, so rim-inside-opening means
-- medallion <= 0.643 x ring; the rim's outer band then tucks under the rail.
-- Set to 0.759 (0.66 + 15 %) by the user's eye in the client: the medallion's
-- gold rim shows inside the opening with the diamonds' former place under the rail.
-- (The ring's gems start 0.356 out, the medallion's diamond tip is 0.438 in:
-- the diamond would need medallion >= 0.813 x ring to reach the gem, which
-- contradicts the rim constraint; closing that gap is an art change.)
-- The game's own (square) portrait keeps the game's size.
--------------------------------------------------------------------------------

local MEDALLION_TO_RING = 0.66 * 1.15   -- 0.759: the user's fit from the screenshot (+15 % over the rim-inside-opening size)
local portraitSaved = nil

function M:FitPortrait()
	local portrait, ring = skin and skin.portrait, skin and skin.ring
	if not (portrait and ring and ring.tex) then
		return
	end
	if active and portrait.melloClassIcon then
		if not portraitSaved then
			local points = {}
			for i = 1, portrait:GetNumPoints() do
				points[i] = { portrait:GetPoint(i) }
			end
			local cx, cy = portrait:GetCenter()
			local px, py = portrait:GetParent():GetLeft(), portrait:GetParent():GetTop()
			if not (cx and px) then
				return   -- not laid out yet: the next refresh fits it
			end
			portraitSaved = { points = points, w = portrait:GetWidth(), h = portrait:GetHeight(),
				cx = cx - px, cy = cy - py }
		end
		local size = ring.tex:GetWidth() * MEDALLION_TO_RING
		if size > 0 and portraitSaved.cx then
			portrait:ClearAllPoints()
			portrait:SetPoint("CENTER", portrait:GetParent(), "TOPLEFT", portraitSaved.cx, portraitSaved.cy)
			portrait:SetSize(size, size)
		end
	elseif portraitSaved then
		portrait:ClearAllPoints()
		for _, pt in ipairs(portraitSaved.points) do
			portrait:SetPoint(unpack(pt))
		end
		portrait:SetSize(portraitSaved.w, portraitSaved.h)
		portraitSaved = nil
	end
end

--------------------------------------------------------------------------------
-- Art the game shows and hides itself: mirror its visibility
--------------------------------------------------------------------------------

function M:RefreshFollowers()
	if not (skin and active) then
		return
	end
	for _, f in ipairs(skin.followers) do
		f.rep:SetShown(f.region:IsShown())
	end
end

function M:RefreshTabs()
	if not (skin and active) then
		return
	end
	for _, rep in ipairs(skin.tabReps) do
		rep:SetState()
	end
end

--------------------------------------------------------------------------------
-- The stats pane: the game rebuilds its rows from a pool on every update
-- (PaperDollFrame_UpdateStats); each row is replaced once, then shown as
-- the game shows its own background (every other row).
--------------------------------------------------------------------------------

local function StatRep(frame, key)
	if frame.melloRep == nil then
		frame.melloRep = Replace(frame.Background, { as = key }) or false
		if frame.melloRep and key == "UI-Character-Info-Line-Bounce" then
			frame:HookScript("OnEnter", function(self) if active then self.melloRep:SetState("hover") end end)
			frame:HookScript("OnLeave", function(self) if active then self.melloRep:SetState("plain") end end)
		end
	end
	return frame.melloRep or nil
end

function M:RefreshStats()
	if not (skin and active and CharacterStatsPane) then
		return
	end
	local pane = CharacterStatsPane
	for _, key in ipairs({ "ItemLevelCategory", "AttributesCategory", "EnhancementsCategory" }) do
		local cat = pane[key]
		if cat and cat.Background then
			local rep = StatRep(cat, "UI-Character-Info-Title")
			if rep then
				rep:Enable()
			end
		end
	end
	if pane.ItemLevelFrame and pane.ItemLevelFrame.Background then
		local rep = StatRep(pane.ItemLevelFrame, "UI-Character-Info-Line-Bounce")
		if rep then
			rep:Enable()
		end
	end
	if pane.statsFramePool then
		-- the rows' pitch: the plates are fitted to it so stacked plates butt
		-- exactly, with no gap and no overlap
		local tops, pitch = {}, nil
		for row in pane.statsFramePool:EnumerateActive() do
			local ok, top = pcall(row.GetTop, row)
			if ok and top and not (issecretvalue and issecretvalue(top)) then
				tops[#tops + 1] = top
			end
		end
		table.sort(tops, function(a, b) return a > b end)
		for i = 2, #tops do
			local d = tops[i - 1] - tops[i]
			if d > 0 and (not pitch or d < pitch) then
				pitch = d                 -- the smallest step: rows within one category
			end
		end
		for row in pane.statsFramePool:EnumerateActive() do
			local rep = StatRep(row, "UI-Character-Info-Line-Bounce")
			if rep then
				Kit:Fade(row.Background)
				if pitch then
					rep:SetFitHeight(pitch)
				end
				rep:Refit()
				rep:SetShown(M.db.statRows and row.Background:IsShown())
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The reputation, currency, skills and statistics lists (one template family,
-- verified in Blizzard_UIPanels_Game, Blizzard_TokenUI and Blizzard_Statistics):
-- rows come from the scroll boxes' pools,
-- are replaced once when first acquired, and follow the game's own methods
-- (Initialize -> collapsed state, RefreshBackgroundHighlightOpacity ->
-- highlight state) through post-hooks.
--------------------------------------------------------------------------------

local function ListHeaderRep(frame)
	local bg, extra = nil, {}
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece then
			local layer = region:GetDrawLayer()
			if layer == "BACKGROUND" and not bg then
				bg = region
			elseif layer == "HIGHLIGHT" then
				extra[#extra + 1] = region
			end
		end
	end
	if not bg then
		return nil
	end
	local rep = Replace(bg, { as = "common-button-list-collapseExpand", alsoFade = extra })
	if not rep then
		return nil
	end
	-- the game's header art does not change with the collapse state (only the
	-- +/- glyph does), so the plate keeps one look; the glyph gets the kit's
	-- plus / minus plate for whichever atlas the game has put on it
	rep.refresh = function()
		if not active then
			return
		end
		rep:Refit()
		rep:SetShown(true)
		if frame.StateIcon then
			Kit:StateIconReps(frame, frame.StateIcon, frame, Replace)
		end
	end
	if frame.Initialize then
		hooksecurefunc(frame, "Initialize", rep.refresh)
	end
	return rep
end

local function ListEntryRep(frame)
	local bh = frame.Content.BackgroundHighlight
	local middle, extra = bh.Middle, {}
	for _, region in ipairs(bh.TextureRegions or { bh:GetRegions() }) do
		if region ~= middle then
			extra[#extra + 1] = region
		end
	end
	local rep = Replace(middle or FirstTexture(bh), { as = "charactercreate-customize-dropdown-linemouseover-middle",
		parent = frame.Content, rect = bh, level = 0, alsoFade = extra })
	if not rep then
		return nil
	end
	rep.object:SetFrameLevel(bh:GetFrameLevel())
	rep.refresh = function()
		if not active then
			return
		end
		rep:Refit()
		-- the same conditions the game uses for its highlight
		local okS, selected = pcall(frame.IsSelected, frame)
		local okW, atWar = pcall(function() return frame.IsAtWar and frame:IsAtWar() end)
		local over = frame:IsMouseOver()
		selected = okS and selected
		atWar = okW and atWar
		if bh:IsShown() and (selected or over or atWar) then
			rep:SetState(selected and "selected" or over and "hover" or "plain")
			rep:SetShown(true)
		else
			rep:SetShown(false)
		end
	end
	if frame.RefreshBackgroundHighlightOpacity then
		hooksecurefunc(frame, "RefreshBackgroundHighlightOpacity", rep.refresh)
	end
	return rep
end

-- A MinimalScrollBar (Blizzard_SharedXML/Shared/Scroll/MinimalScrollBar.xml):
-- Track with Begin / Middle / End textures and the Thumb button (its own
-- Begin / Middle / End, re-atlased on hover / press), Back and Forward
-- stepper buttons with one Texture each. The game shows and hides the bar,
-- the track and the thumb itself; our pieces are children of theirs.
local function SkinScrollBar(bar)
	if bar.melloRep ~= nil then
		return
	end
	local track, thumb = bar.Track, bar.Track and bar.Track.Thumb
	if not (track and thumb and track.Middle and thumb.Middle) then
		bar.melloRep = false
		return
	end
	local reps = {}
	reps[#reps + 1] = Replace(track.Middle, { as = "minimal-scrollbar-track-middle", rect = track, alsoFade = { track.Begin, track.End } })
	reps[#reps + 1] = Replace(thumb.Middle, { as = "minimal-scrollbar-small-thumb-middle", rect = thumb, button = thumb, alsoFade = { thumb.Begin, thumb.End } })
	if bar.Back and bar.Back.Texture then
		reps[#reps + 1] = Replace(bar.Back.Texture, { as = "minimal-scrollbar-arrow-top", button = bar.Back })
	end
	if bar.Forward and bar.Forward.Texture then
		reps[#reps + 1] = Replace(bar.Forward.Texture, { as = "minimal-scrollbar-arrow-bottom", button = bar.Forward })
	end
	-- the thumb's height follows the content: refit when it changes
	thumb:HookScript("OnSizeChanged", function()
		if active then
			for _, rep in ipairs(reps) do
				if rep.vstrip then
					rep:Refit()
				end
			end
		end
	end)
	bar.melloRep = reps
	if active then
		for _, rep in ipairs(reps) do
			rep:Enable()
		end
	end
end

-- Every MinimalScrollBar under `root` (the stats boxes, the reputation,
-- skills, currency and statistics lists, the side panes' description).
local function ScrollBarsIn(root, depth)
	depth = depth or 0
	if depth > 7 or root == skin then
		return
	end
	for _, child in ipairs({ root:GetChildren() }) do
		if child.Track and child.Track.Thumb and child.Back and child.Forward then
			SkinScrollBar(child)
		else
			ScrollBarsIn(child, depth + 1)
		end
	end
end

function M:RefreshScrollBars()
	if not (skin and active) then
		return
	end
	ScrollBarsIn(CharacterFrame)
end

-- A ColoredProgressBar (Blizzard_SharedXML/Camelot/ProgressBars): the
-- background atlas on the whole 160 x 29 frame, a 15 px Fill the game sizes
-- (SetFillWidth = percent x the frame's width) and tints, a Mask rounding
-- the fill's ends, the Text over it. The bracket replaces the background;
-- the fill and its mask are moved INTO the bracket's opening (the opening is
-- where the background's bar was), and put back when the skin is off.
function SkinProgressBar(bar)
	if not bar or bar.melloRep ~= nil then
		return
	end
	local bg
	for _, region in ipairs({ bar:GetRegions() }) do
		if region:GetObjectType() == "Texture" and region ~= bar.Fill and not region.kitPiece and region:GetDrawLayer() == "BACKGROUND" then
			bg = region
			break
		end
	end
	local rep = bg and Replace(bg, { as = "common-stat-bar-BG", rect = bar })
	bar.melloRep = rep or false
	if not rep then
		return
	end
	local fill, mask = bar.Fill, bar.Mask
	local function SavePoints(region)
		local saved = { h = region:GetHeight() }
		for i = 1, region:GetNumPoints() do
			saved[i] = { region:GetPoint(i) }
		end
		return saved
	end
	local function RestorePoints(region, saved)
		region:ClearAllPoints()
		for i = 1, #saved do
			region:SetPoint(unpack(saved[i]))
		end
		if saved.h and saved.h > 0 then
			region:SetHeight(saved.h)
		end
	end
	local savedFill = fill and SavePoints(fill)
	local savedMask = mask and SavePoints(mask)
	local function FitFill()
		if not (active and fill) then
			return
		end
		local l, r, t, b = rep:GetOpening()
		local w, h = bar:GetSize()
		if not (w and w > 0) then
			return
		end
		local openW, openH = w - l - r, h - t - b
		local okW, fw = pcall(fill.GetWidth, fill)
		local pct = (okW and fw and not Secret(fw) and w > 0) and (fw / w) or 0
		fill:ClearAllPoints()
		fill:SetPoint("LEFT", bar, "LEFT", l, (b - t) / 2)
		fill:SetHeight(openH)
		fill.melloFitting = true
		fill:SetWidth(math.max(pct * openW, 0.001))
		fill.melloFitting = nil
		if mask then
			-- the mask clips the fill to ITS height (the atlas's 15 px):
			-- it must be as tall as the fill area, or the fill stays thin
			mask:ClearAllPoints()
			mask:SetPoint("LEFT", bar, "LEFT", l, (b - t) / 2)
			mask:SetPoint("RIGHT", bar, "RIGHT", -r, (b - t) / 2)
			mask:SetHeight(openH)
		end
	end
	rep.onEnable = function()
		rep:Refit()
		FitFill()
	end
	rep.onDisable = function()
		if savedFill then
			RestorePoints(fill, savedFill)
		end
		if savedMask then
			RestorePoints(mask, savedMask)
		end
	end
	-- SetFillTextureByColorType re-atlases the fill WITH the atlas size
	-- (the skill rows do it on every initialisation): put our height back
	if fill and fill.SetAtlas then
		hooksecurefunc(fill, "SetAtlas", function()
			if active and not fill.melloFitting then
				local _, _, t, b = rep:GetOpening()
				local h = bar:GetHeight()
				if h and h > 0 and not Secret(h) then
					fill:SetHeight(h - t - b)
					if mask then
						mask:SetHeight(h - t - b)
					end
				end
			end
		end)
	end
	-- the game sets the fill to percent x the frame's width: scale that to
	-- the opening's width right after (a post-hook, the game's own value
	-- is what it reads back for the percentage)
	if bar.SetFillWidth then
		hooksecurefunc(bar, "SetFillWidth", function(self, width)
			if active and fill and not fill.melloFitting then
				local l, r = rep:GetOpening()
				local w = self:GetWidth()
				if w and w > 0 and not Secret(width) then
					fill.melloFitting = true
					fill:SetWidth(math.max(width / w * (w - l - r), 0.001))
					fill.melloFitting = nil
				end
			end
		end)
	end
	if active then
		rep:Enable()
	end
end

local function SkinListFrame(frame)
	if frame.melloRep ~= nil then
		return
	end
	local rep
	if frame.Content and frame.Content.BackgroundHighlight then
		rep = ListEntryRep(frame)
	elseif frame.StateIcon and frame.Name then
		rep = ListHeaderRep(frame)
	end
	frame.melloRep = rep or false
	-- a sub-header's open / closed toggle (its art is re-atlased by RefreshIcon)
	local toggle = frame.ToggleCollapseButton
	if toggle and toggle.GetNormalTexture and toggle:GetNormalTexture() then
		local function Icons()
			if active then
				Kit:StateIconReps(toggle, toggle:GetNormalTexture(), toggle, Replace, { toggle:GetPushedTexture(), toggle:GetHighlightTexture() })
			end
		end
		if toggle.RefreshIcon then
			hooksecurefunc(toggle, "RefreshIcon", Icons)
		end
		Icons()
	end
	if rep then
		rep:Enable()
		rep.refresh()
	end
	if frame.Content then
		SkinProgressBar(frame.Content.ReputationBar or frame.Content.SkillsBar)
	end
end

-- the two lines the scroll box draws above and below its rows
local function SkinScrollLines(scrollBox)
	for _, child in ipairs({ scrollBox:GetChildren() }) do
		if not child:GetName() and child:GetWidth() <= 1 and child:GetNumRegions() == 1 and child.melloRep == nil then
			local line = child:GetRegions()
			local rep = line and line:GetObjectType() == "Texture" and Replace(line, { as = "UI-Character-Info-ScrollLine-Long" })
			child.melloRep = rep or false
			if rep then
				rep:Enable()
			end
		end
	end
end

local function HookList(scrollBox, rowSkin)
	if not (scrollBox and ScrollUtil and ScrollUtil.AddAcquiredFrameCallback) or scrollBox.melloKitHooked then
		return
	end
	scrollBox.melloKitHooked = true
	rowSkin = rowSkin or SkinListFrame
	SkinScrollLines(scrollBox)
	ScrollUtil.AddAcquiredFrameCallback(scrollBox, function(_, frame)
		if active then
			rowSkin(frame)
		end
	end, M, false)
	-- initialisation runs after the layout pass: the row has its height now
	if ScrollUtil.AddInitializedFrameCallback then
		ScrollUtil.AddInitializedFrameCallback(scrollBox, function(_, frame)
			if active and frame.melloRep and frame.melloRep.refresh then
				frame.melloRep.refresh()
			end
		end, M, false)
	end
	if scrollBox.ForEachFrame then
		scrollBox:ForEachFrame(function(frame)
			if active then
				rowSkin(frame)
			end
		end)
	end
end

-- The equipment manager (PaperDollFrame.EquipmentManagerPane, shown on demand):
-- its inset frame, the outfit cards (a plate; hover and selected bars the
-- game shows / hides), Equip / Save (the 128-RedButton three-slice, as the
-- crafting page's Create) and New Set (a tertiary button re-atlased with its
-- state: one plate, its state from the button).
local function SkinOutfitCard(card)
	if card.melloRep ~= nil then
		return
	end
	card.melloRep = false
	local bg
	for _, region in ipairs({ card:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece and Kit:ArtKey(region) == "UI-Character-Info-OutfitCard" then
			bg = region
			break
		end
	end
	if bg then
		card.melloRep = Replace(bg, { as = "UI-Character-Info-OutfitCard", rect = bg }) or false
	end
	for key, bar in pairs({ ["UI-Character-Info-OutfitCard-Hover"] = card.HighlightBar, ["UI-Character-Info-OutfitCard-Selected"] = card.SelectedBar }) do
		if bar then
			local rep = Replace(bar, { as = key, rect = bar })
			if rep then
				local function Follow()
					if active then
						rep:SetShown(bar:IsShown())
					end
				end
				hooksecurefunc(bar, "Show", Follow)
				hooksecurefunc(bar, "Hide", Follow)
				hooksecurefunc(bar, "SetShown", Follow)
				skin.followers[#skin.followers + 1] = { rep = rep, region = bar }
				Follow()
			end
		end
	end
end

local function SkinEquipmentManager()
	local pane = _G.PaperDollFrame and _G.PaperDollFrame.EquipmentManagerPane
	if not pane or pane.melloKitHooked then
		return
	end
	pane.melloKitHooked = true
	if pane.Border then
		Replace(pane.Border, { as = "common-insideframe" })
	end
	for _, button in ipairs({ pane.EquipSet, pane.SaveSet }) do
		if button and button.Center then
			local extra = { button.Left, button.Right }
			for _, region in ipairs({ button:GetRegions() }) do
				if region:GetObjectType() == "Texture" and region ~= button.Center and region ~= button.Left and region ~= button.Right and region:GetDrawLayer() == "HIGHLIGHT" then
					extra[#extra + 1] = region
				end
			end
			Replace(button.Center, { as = "_128-RedButton-Center", rect = button, button = button, alsoFade = extra })
		end
	end
	local new = pane.NewSet
	if new and new.StateTexture then
		local rep = Replace(new.StateTexture, { as = "common-button-tertiary-normal", rect = new, button = new })
		if rep and new.OnButtonStateChanged and rep.Update then
			hooksecurefunc(new, "OnButtonStateChanged", function() rep.Update() end)   -- disabled comes only this way
		end
		-- the game sets the + icon at LEFT 13 and the label LEFT 35 (left-
		-- justified across the button); the pair is centred on the button
		-- instead (user, 2026-09-21), keeping their spacing; put back on disable
		if rep then
			local icon, label
			for _, region in ipairs({ new:GetRegions() }) do
				if region:GetObjectType() == "Texture" and Kit:ArtKey(region) == "UI-Character-Info-Icon-Add" then
					icon = region
				elseif region:GetObjectType() == "FontString" then
					label = region
				end
			end
			if icon and label then
				local saved = {}
				for _, r in ipairs({ icon, label }) do
					local points = {}
					for i = 1, r:GetNumPoints() do
						points[i] = { r:GetPoint(i) }
					end
					saved[r] = points
				end
				local enable, disable = rep.onEnable, rep.onDisable
				local function Centre()
					if not active then
						return
					end
					local iw = icon:GetWidth()
					local ok, tw = pcall(label.GetStringWidth, label)
					if not (ok and tw and not Secret(tw) and tw > 0) then
						return                 -- not laid out yet: again on show
					end
					local gap = 22 - iw          -- the game's 13 -> 35: the icon's width plus this
					local total = iw + gap + tw
					icon:ClearAllPoints()
					icon:SetPoint("LEFT", new, "CENTER", -total / 2, 0)
					label:ClearAllPoints()
					label:SetPoint("LEFT", icon, "RIGHT", gap, 0)
					label:SetJustifyH("LEFT")
				end
				new:HookScript("OnShow", Centre)
				new:HookScript("OnSizeChanged", Centre)
				rep.onEnable = function(...)
					if enable then enable(...) end
					Centre()
				end
				rep.onDisable = function(...)
					if disable then disable(...) end
					for r, points in pairs(saved) do
						r:ClearAllPoints()
						for _, pt in ipairs(points) do
							r:SetPoint(unpack(pt))
						end
					end
				end
			end
		end
	end
	HookList(pane.ScrollBox, SkinOutfitCard)
	Kit:SkinScrollBarsIn(pane, Replace, skin)
end

function M:RefreshLists()
	if not (skin and active) then
		return
	end
	HookList(_G.ReputationFrame and _G.ReputationFrame.ScrollBox)
	HookList(_G.SkillsFrame and _G.SkillsFrame.ScrollBox)
	HookList(_G.TokenFrame and _G.TokenFrame.ScrollBox)
	HookList(_G.StatisticsFrame and _G.StatisticsFrame.ScrollBox)
	SkinEquipmentManager()
	M:RefreshScrollBars()
	for _, rep in ipairs(skin.reps) do
		if rep.refresh then
			rep:Enable()
			rep.refresh()
		end
	end
end

--------------------------------------------------------------------------------
-- Turning the skin on and off
--------------------------------------------------------------------------------

local function Activate()
	if active then
		return
	end
	BuildSkin()
	active = true
	skin:Show()
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	M:RefreshFollowers()
	M:FitPortrait()
	M:RefreshTabs()
	M:RefreshStats()
	M:RefreshLists()
	if skin.toggleIcons then
		skin.toggleIcons()
	end
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	skin:Hide()
	M:FitPortrait()
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	if CharacterStatsPane and CharacterStatsPane.statsFramePool then
		for row in CharacterStatsPane.statsFramePool:EnumerateActive() do
			Kit:Unfade(row.Background)
		end
	end
end

local function Sync()
	if M.isEnabled and CharacterFrame then
		Activate()
	else
		Deactivate()
	end
end

local function Hook()
	if hooked or not CharacterFrame then
		return
	end
	hooked = true
	if PaperDollFrame_UpdateStats then
		hooksecurefunc("PaperDollFrame_UpdateStats", function()
			if active then
				M:RefreshStats()
			end
		end)
	end
	if CharacterFrame.SetSelectedModeTabByFrame then
		hooksecurefunc(CharacterFrame, "SetSelectedModeTabByFrame", function()
			M:RefreshTabs()
		end)
	end
	hooksecurefunc(CharacterFrame, "ShowSubFrame", function()
		M:RefreshTabs()
		M:RefreshFollowers()
		M:RefreshLists()
	end)
	hooksecurefunc(CharacterFrame, "RefreshDisplay", function()
		M:RefreshFollowers()
		M:FitPortrait()
	end)
	if CharacterFrame.SetPortraitToSpecIcon then
		hooksecurefunc(CharacterFrame, "SetPortraitToSpecIcon", function()
			M:FitPortrait()
		end)
	end
	if CharacterFrame.SetPortraitToUnit then
		hooksecurefunc(CharacterFrame, "SetPortraitToUnit", function()
			M:FitPortrait()
		end)
	end
	CharacterFrame:HookScript("OnShow", function()
		Sync()
		M:RefreshFollowers()
		M:FitPortrait()
		M:RefreshTabs()
		M:RefreshStats()
	end)
end

function M:OnEnable(db)
	self.db = db
	Hook()
	if CharacterFrame and CharacterFrame:IsShown() then
		Sync()
	end
end

function M:OnDisable()
	Deactivate()
end

function M:OnSettingChanged(key)
	if key == "statRows" then
		self:RefreshStats()
	end
end

--------------------------------------------------------------------------------
-- /cpdump: the replacements and their rectangles; "regions": every visible
-- game texture under the window; "slot": everything drawn on the head slot.
--------------------------------------------------------------------------------

SLASH_MELLOCPDUMP1 = "/cpdump"
local function CpDump(msg)
	if not (skin and active) then
		MelloUI:Print("Character panel skin is not active.")
		return
	end
	local function Rect(label, f, extra)
		if not f then
			return
		end
		local ok, l, b, w, h = pcall(function() return f:GetRect() end)
		if ok and l and not Secret(l) then
			MelloUI:Print("%-28s x=%.0f y=%.0f w=%.0f h=%.0f %s", label, l, b, w, h, extra or "")
		end
	end
	if msg == "slot" then
		local slot = _G.CharacterHeadSlot
		local function list(frame, label)
			for _, region in ipairs({ frame:GetRegions() }) do
				if region:GetObjectType() == "Texture" and region:IsShown() then
					local okA, alpha = pcall(region.GetAlpha, region)
					Rect(label .. " " .. (region:GetName() or region:GetDebugName()) .. (region.kitPiece and " [KIT]" or ""), region,
						string.format("layer=%s alpha=%s art=%s", tostring(region:GetDrawLayer()), okA and tostring(alpha) or "?", tostring(Kit:ArtKey(region))))
				end
			end
		end
		if slot then
			list(slot, "slot")
			for _, child in ipairs({ slot:GetChildren() }) do
				list(child, "child " .. (child:GetName() or child:GetDebugName()))
			end
		end
		return
	end
	if msg == "regions" then
		local n = 0
		local function walk(frame, depth)
			if depth > 6 or frame == skin then
				return
			end
			for _, region in ipairs({ frame:GetRegions() }) do
				if region:GetObjectType() == "Texture" and not region.kitPiece and region:IsVisible() then
					local ok, alpha = pcall(region.GetAlpha, region)
					if ok and alpha and not Secret(alpha) and alpha > 0 then
						n = n + 1
						Rect(string.format("%d %s/%s", n, frame:GetName() or frame:GetDebugName(), region:GetName() or region:GetDebugName()), region, tostring(Kit:ArtKey(region)))
					end
				end
			end
			for _, child in ipairs({ frame:GetChildren() }) do
				walk(child, depth + 1)
			end
		end
		walk(CharacterFrame, 0)
		MelloUI:Print("%d visible game textures", n)
		return
	end
	-- "bars": the skill / reputation bars' bracket, opening and fill, for the
	-- first few visible rows (the fill spilling past the rails, 2026-09-23)
	if msg == "bars" then
		local n = 0
		local function Bars(scrollBox)
			if not (scrollBox and scrollBox.GetFrames) then
				return
			end
			for _, row in ipairs(scrollBox:GetFrames()) do
				local bar = row.Content and (row.Content.ReputationBar or row.Content.SkillsBar)
				local rep = bar and bar.melloRep
				if rep and n < 3 and bar:IsVisible() then
					n = n + 1
					local l, r, t, b = rep:GetOpening()
					Rect(string.format("%d bar", n), bar, string.format("rect=%s proxy=%s active=%s", tostring(rep.rect == bar), tostring(rep.proxy ~= nil), tostring(active)))
					Rect(string.format("%d rep.rect", n), rep.rect)
					Rect(string.format("%d strip", n), rep.strip, string.format("scale=%.3f height=%.1f off=%.1f", rep.strip.scale or 0, rep.strip.height or 0, rep.stripOffset or 0))
					Rect(string.format("%d trough", n), rep.trough)
					MelloUI:Print("%d opening l=%.1f r=%.1f t=%.1f b=%.1f", n, l, r, t, b)
					local fill, mask = bar.Fill, bar.Mask
					if fill then
						Rect(string.format("%d fill", n), fill, string.format("layer=%s points=%d atlas=%s", tostring(fill:GetDrawLayer()), fill:GetNumPoints(), tostring(fill.GetAtlas and fill:GetAtlas())))
						for i = 1, fill:GetNumPoints() do
							local p, rel, rp, x, y = fill:GetPoint(i)
							MelloUI:Print("   fill point %s -> %s %s %.1f %.1f", tostring(p), rel == bar and "bar" or tostring(rel and (rel:GetName() or rel:GetDebugName())), tostring(rp), x or 0, y or 0)
						end
					end
					Rect(string.format("%d mask", n), mask)
					for _, region in ipairs({ bar:GetRegions() }) do
						if region:GetObjectType() == "Texture" and region:IsShown() and region ~= fill then
							Rect(string.format("   %s", region:GetDebugName()), region, string.format("layer=%s kit=%s art=%s", tostring(region:GetDrawLayer()), tostring(region.kitPiece ~= nil), tostring(Kit:ArtKey(region))))
						end
					end
				end
			end
		end
		Bars(_G.SkillsFrame and _G.SkillsFrame.ScrollBox)
		Bars(_G.ReputationFrame and _G.ReputationFrame.ScrollBox)
		MelloUI:Print("%d bars", n)
		return
	end
	if msg == "joints" then
		Rect("divider rect", skin.divider and skin.divider.rect)
		Rect("divider frame", skin.dividerFrame, skin.dividerFrame and string.format("level=%d shown=%s", skin.dividerFrame:GetFrameLevel(), tostring(skin.dividerFrame:IsVisible())))
		Rect("title strip", skin.title and skin.title.strip)
		local n = 0
		for _, rep in ipairs(skin.reps) do
			if rep.key == "RailJoint" then
				n = n + 1
				Rect(string.format("joint %d helper", n), rep.rect)
				Rect(string.format("joint %d holder", n), rep.object, string.format("level=%d visible=%s", rep.object:GetFrameLevel(), tostring(rep.object:IsVisible())))
				Rect(string.format("joint %d tex", n), rep.tex, string.format("visible=%s alpha=%.2f layer=%s art=%s", tostring(rep.tex:IsVisible()), rep.tex:GetAlpha(), tostring(rep.tex:GetDrawLayer()), tostring(rep.tex:GetTexture())))
			end
		end
		MelloUI:Print("%d joints", n)
		return
	end
	Rect("frame", CharacterFrame)
	Rect("nineSlice", CharacterFrame.NineSlice)
	Rect("leftHost", CharacterFrame.LeftPaneHost)
	Rect("rightHost", CharacterFrame.RightPaneHost)
	Rect("headSlot", _G.CharacterHeadSlot)
	Rect("neckSlot", _G.CharacterNeckSlot)
	if msg == "title" then
		local tc = CharacterFrame.TitleContainer
		MelloUI:Print("TitleContainer: %s, regions: %d", tc and "yes" or "no", tc and select("#", tc:GetRegions()) or 0)
		if tc then
			for _, region in ipairs({ tc:GetRegions() }) do
				MelloUI:Print("  %s %s art=%s", region:GetObjectType(), region:GetName() or region:GetDebugName(), tostring(Kit:ArtKey(region)))
			end
		end
		for i, rep in ipairs(skin.reps) do
			if rep.key == "TitleBar" then
				Rect(string.format("%d TitleBar strip base=%s state=%s", i, rep.strip and rep.strip.base or "?", tostring(rep.strip and rep.strip.state)), rep.object, rep.object:IsShown() and "" or "(hidden)")
			end
		end
		return
	end
	for i, rep in ipairs(skin.reps) do
		Rect(string.format("%d %s %s", i, rep.kind, tostring(rep.key)), rep.object, rep.object:IsShown() and "" or "(hidden)")
	end
end

-- the dump goes to chat and to the copy window (/mellolog), as text
SlashCmdList.MELLOCPDUMP = function(msg)
	MelloUI:ClearLog()
	CpDump(msg)
	MelloUI:ShowLog("cpdump " .. (msg or ""))
end
