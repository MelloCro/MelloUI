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
local Perf = MelloUI.Perf:Scope("CharacterPanel")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
-- one handler for every object it is hooked on, wrapped once
local Shared = Perf.Shared or function(_, fn) return fn end
local Kit = MelloUI.Kit

local LOOKS = Kit.buttonLooks

-- Window Background: the window's own stone, or one of the button
-- backgrounds over the whole window (not None: the world would show through)
local WINDOW_BACKGROUNDS = { { value = "window", label = "Window stone", piece = "window/frame_body" } }
for _, v in ipairs(LOOKS.backgrounds) do
	if v.value ~= "none" then
		WINDOW_BACKGROUNDS[#WINDOW_BACKGROUNDS + 1] = v
	end
end

-- (movable and statRows have no switch on the page: dragging is UI
-- Modifications' Unlock the Windows, the stat plates stay on)
local M = MelloUI:RegisterModule("CharacterPanel", {
	title = "Character Panel",
	desc = "The character window dressed in the painted kit: stone frame, slot rims, framed panes and stats, all on the game's own layout.",
	enabledByDefault = true,
	defaults = {
		movable = false,
		statRows = true,
		windowBackground = "window",
		repBarBorder = "frame",
	},
	options = {
		{ type = "dropdown", key = "windowBackground", name = "Window Background", values = WINDOW_BACKGROUNDS,
		  desc = "What the character window shows behind everything: its own stone, or stone, cracked concrete, iron plate, parchment, leather or dark. The equipment slots, the progress bars and the side tabs wear UI Modifications' borders (every window's)." },
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
local listsDirty = false  -- a tab picked while the window was closed: its OnShow re-reads the lists
local layHeld = nil       -- GetTime() of the window's OnShow, which lays the parchment's rects once, at its end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- A value the client hides from addons (secret): never do arithmetic on it.
-- The test is MelloUI.Safe's (Core.lua), one set for the addon.
local Secret = MelloUI.Safe and MelloUI.Safe.IsSecret or issecretvalue

-- Window Background Parchment chosen: the whole window on parchment, so the
-- right pane's own Parchment sheet stands down (one parchment per surface).
local function WindowParchment()
	return (M.db and M.db.windowBackground == "parchment") and true or false
end

-- Where a frame or region lies on the screen (left, right, top, bottom in
-- screen px), nil while it is hidden or has no usable rect yet.
local function ScreenRect(obj)
	if not (obj and obj.GetRect and obj.GetEffectiveScale) or (obj.IsShown and not obj:IsShown()) then
		return nil
	end
	local ok, l, b, w, h = pcall(obj.GetRect, obj)
	if not (ok and l and b and w and h) or Secret(l) or Secret(b) or Secret(w) or Secret(h) or w <= 0 or h <= 0 then
		return nil
	end
	local s = obj:GetEffectiveScale()
	return l * s, (l + w) * s, (b + h) * s, b * s
end

-- A parchment sheet's rect laid on the part of its base that nothing painted
-- covers (user, 2026-09-24: "Character Pane parchment does not have the
-- visible mask effect on it like the quest log has" -- the right pane's sheet
-- lay on the pane's whole rect, and its painted edge ran under the divider,
-- the window's rails and the title plate, where no stroke shows). `c.frame`
-- is the rect (a child anchored inside `c.base`); c.covers() names, per side
-- (l, r, t, b), what may lie over that side: each one that overlaps the base
-- from that side pushes the side in to its own inner edge. Laid again when the
-- window shows, resizes or the UI scale changes (the sheet then re-tiles and
-- re-fits its masks on the rect's new size).
local SIDES = { "l", "r", "t", "b" }
local NONE = {}   -- an empty list, never written to
local function LayClear(c)
	local frame = c and c.frame
	local bl, br, bt, bb = ScreenRect(c and c.base)
	if not (frame and bl) then
		return
	end
	local l, r, t, b = bl, br, bt, bb
	local cx, cy = (bl + br) / 2, (bt + bb) / 2
	-- the rails, the divider and the title plate are the same objects for
	-- good once the skin is built: their lists are made once, not on every lay
	local covers = c.coverList
	if not covers then
		covers = c.covers() or NONE
		if skin and skin.built then
			c.coverList = covers
		end
	end
	for _, side in ipairs(SIDES) do
		for _, cover in ipairs(covers[side] or NONE) do
			local x1, x2, y1, y2 = ScreenRect(cover)   -- left, right, top, bottom
			if x1 then
				local across = y1 > b and y2 < t      -- overlaps the rect's height
				local along = x2 > l and x1 < r      -- overlaps the rect's width
				if side == "l" and across and (x1 + x2) / 2 < cx then
					l = math.max(l, x2)
				elseif side == "r" and across and (x1 + x2) / 2 > cx then
					r = math.min(r, x1)
				elseif side == "t" and along and (y1 + y2) / 2 > cy then
					t = math.min(t, y2)
				elseif side == "b" and along and (y1 + y2) / 2 < cy then
					b = math.max(b, y1)
				end
			end
		end
	end
	frame:ClearAllPoints()
	if r - l < 8 or t - b < 8 then
		frame:SetAllPoints(c.base)
		return
	end
	-- offsets in the rect's own units
	local s = frame:GetEffectiveScale()
	frame:SetPoint("TOPLEFT", c.base, "TOPLEFT", (l - bl) / s, -(bt - t) / s)
	frame:SetPoint("BOTTOMRIGHT", c.base, "BOTTOMRIGHT", -(br - r) / s, (b - bb) / s)
end

-- The eye strain rule (user, 2026-09-24: "too much small text over a plain
-- brown border is just an eye strain" / "apply the eye strain rule to all
-- existing windows"; docs/WINDOW-RULES.md 2e): a pane of text lies on the
-- palette's inner panel at this alpha over the window's stone, never on the
-- bare stone.
local DIM_ALPHA = 0.8

local SkinProgressBar     -- defined with the list code below; the detail panes use it (SkinSidePanes)

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
--
-- The skin is made of parts, made in this order (frame levels and draw order
-- follow it). The window's first open used to make every one of them in its
-- OnShow, one hitch of 63 ms (/melloperf, 2026-09-24); they are made ahead
-- now, a few per frame while the game is idle after login (Building ahead),
-- and whatever is left when the window first opens is made there at once, as
-- before. Every part is made with the skin off, as it always was (Activate
-- turns it on after building): nothing of it shows and no game art is faded
-- until the window opens. Two are still made at that first open, not ahead
-- (SkinOnParts): the divider's junctions and the side tabs.
--------------------------------------------------------------------------------

local PARTS = {}
local function Part(fn)
	PARTS[#PARTS + 1] = fn
end

local WindowSheet               -- below, with the settings; made ahead as the last part but one
local ScrollBarsAt, BarsWalked  -- below, with the scroll bars; the last part walks them

-- The detail panes of the reputation, skills, PvP and currency tabs and the
-- PvP tab's line under the rank name, each made once: with the rest of the
-- skin, and again as the skin comes on for any the game has made since (the
-- skin is made ahead of the first open now; it was made at that open).
local panesDone = setmetatable({}, { __mode = "k" })
-- A side pane the game has laid out (every Refresh: a faction or skill
-- picked, an update) or shown empty: its texts that carry no ink yet (a row
-- the pane's pool made just now, its empty text) inked before it is drawn,
-- not at the next pass (user, 2026-09-24: the Reputation, Skill and PvP
-- text flickered). LayoutRows, not Refresh: the panes' selection callbacks
-- hold Refresh as it was at load; Refresh always lays the rows
local LOOK_CALLS = { "LayoutRows", "SetEmpty" }
local LookPane = Shared("LayoutRows / SetEmpty on side panes", function(pane)
	local QI = active and MelloUI.QuestInk
	if QI and QI.LookRow then
		QI.LookRow("character", pane)
	end
end)

local function SkinSidePanes()
	-- the detail panes of the reputation, currency, skills and PvP tabs: their
	-- divider line, hidden by the game when the pane is empty
	local sidePanes = {
		_G.ReputationFrame and _G.ReputationFrame.ReputationDetailFrame,
		_G.SkillsFrame and _G.SkillsFrame.SkillDetailFrame,
		_G.PVPRankFrame and _G.PVPRankFrame.DetailFrame,
		_G.TokenFrame and _G.TokenFrame.DetailFrame,
	}
	for i = 1, 4 do
		local pane = sidePanes[i]
		if pane and not panesDone[pane] then
			panesDone[pane] = true
			-- the standing / rank bar of the reputation and skill detail panes;
			-- only those two tabs' bars take the smaller border art (user,
			-- 2026-09-24), a bar on another tab's pane (PvP, currency) keeps it
			local tabBar = pane == sidePanes[1] or pane == sidePanes[2]
			if pane.StandingBar then
				SkinProgressBar(pane.StandingBar, tabBar and "rep" or "pane")
			else
				SkinProgressBar(pane.RankBar, tabBar and "skill" or "pane")
			end
			SkinCheckboxes(pane)
			for _, method in ipairs(LOOK_CALLS) do
				if pane[method] then
					hooksecurefunc(pane, method, LookPane)
				end
			end
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
	end

	-- the PvP tab: the line under the rank name
	local pvp = _G.PVPRankFrame
	local line = pvp and pvp.MainInfoFrame and pvp.MainInfoFrame.Line
	if line and not panesDone[line] then
		panesDone[line] = true
		Replace(line, { as = "UI-Character-Info-Honor-LevelBG" })
	end
end

-- the window: its nine-slice frame, plus the backdrop texture that frame draws
Part(function(cf)
	if cf.NineSlice then
		-- no gem corner at the top-left: the portrait ring is that corner
		skin.window = Replace(cf.NineSlice, { as = "NineSlicePanelTemplate", parent = cf, rect = cf, alsoFade = { cf.Bg }, skip = "tl" })
	end
	if cf.TopTileStreaks then
		Replace(cf.TopTileStreaks, { as = "_UI-Frame-TopTileStreaks", parent = cf })
	end
end)

-- the ring around the game's portrait (the nine-slice's portrait corner)
Part(function(cf)
	local portrait = cf.PortraitContainer and cf.PortraitContainer.portrait
	local corner = cf.NineSlice and cf.NineSlice.TopLeftCorner
	if portrait and corner then
		skin.ring = Replace(corner, { as = "UI-Frame-PortraitMetal-CornerTopLeft", parent = cf.PortraitContainer, center = portrait })
		skin.portrait = portrait
	end
end)

Part(function(cf)
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
end)

-- the panes' backdrop pictures and the divider between them: the
-- pictures are faded (Kit's one-stone-per-surface rule), the window's
-- own stone runs on under both panes
Part(function(cf)
	if cf.LeftPaneHost then
		Replace(FirstTexture(cf.LeftPaneHost), { as = "UI-Character-Info-General-BG" })
	end
	local host = cf.RightPaneHost
	if host then
		local bg = FirstTexture(host)
		if bg and bg ~= host.StoneBg then
			local stone = Replace(bg, { as = "UI-Character-Info-Stat-BG" })
			-- a parchment sheet on the right pane (on the window's stone; the
			-- replacement's holder carries it), behind every tab
			-- that shows there (stats, the reputation / skill / honor /
			-- currency details, statistics), filling nearly the whole pane so
			-- the text sits ON the parchment, its edge in the FINE strokes
			-- that end before the first letters (user, 2026-09-23: "make sure
			-- that the text is inside of the parchment itself"). A region of
			-- the stone's holder, one sublevel above the stone: it comes and
			-- goes with the skin.
			-- (user, 2026-09-24: "Character Pane parchment does not have the
			-- visible mask effect on it like the quest log has"): the FINE
			-- strokes, a few units deep, lay on the pane's whole rect, whose
			-- edges run under the divider, the window's rails and the title
			-- plate: nothing of them showed. The sheet now lies on the part of
			-- the pane nothing covers (LayClear) and ends in the quest log's
			-- own strokes; it stands down while the Window Background is
			-- Parchment (that sheet covers the whole window, this pane with it).
			if stone and stone.object and stone.object ~= stone.tex and Kit.ParchmentSheet then
				local clear = CreateFrame("Frame", nil, stone.object)
				clear:EnableMouse(false)
				clear:SetAllPoints(stone.object)
				skin.paneClear = { frame = clear, base = stone.object, covers = function()
					-- (`or false`: a nil would end the list early)
					local rails = skin.window and skin.window.skin or {}
					return {
						l = { skin.divider and skin.divider.tex or false },
						r = { rails.r or false },
						t = { rails.t or false, skin.title and skin.title.object or false },
						b = { rails.b or false },
					}
				end }
				Kit:ParchmentSheet(stone.object, clear, { rect = clear, margin = 1, sublevel = 1, area = "character",
					alive = function() return not WindowParchment() end })
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
end)

-- the stats scroll boxes: their inset frame and the class picture under the stats
-- (the inset's rule lays the inner panel over its stone, WINDOW-RULES 2e;
-- kept in skin.insetDims so the panel stands down on parchment, RefreshDims)
Part(function()
	skin.insetDims = {}
	for _, box in ipairs({ CharacterStatsPaneScrollBox, CharacterStatsPanePetScrollBox }) do
		if box and box.Border then
			local inset = Replace(box.Border, { as = "common-insideframe", alsoFade = box.ClassBackground and { box.ClassBackground } or nil })
			if inset then
				skin.insetDims[#skin.insetDims + 1] = inset
			end
		end
	end
end)

-- The two panes' text on the palette's inner panel (WINDOW-RULES 2e; user,
-- 2026-09-24: "apply the eye strain rule to all existing windows"). On
-- every tab but the character's own, the left pane holds a list (the
-- reputations, the skills, the currencies, the honor ranks) and the right
-- pane its details or the statistics, all small text straight on the
-- window's stone, with no inset of the game's to dress. So each pane gets
-- the panel as a tint over that stone (never a second stone: one stone
-- per surface), laid on the part of the pane nothing painted covers, the
-- same way the parchment sheet is (LayClear: the rails, the title plate,
-- the divider). A frame of ours one level under the pane's host, as the
-- kit's holders and the right pane's parchment are, so the pane's rows
-- and texts stay above it; shown by RefreshDims. The character tab keeps
-- its stone: its left pane is the model (a picture), its right pane the
-- stats and the equipment manager, whose insets carry the panel already.
Part(function(cf)
	skin.dims, skin.dimClears = {}, {}
	local function PaneDim(key, pane, covers)
		if not pane then
			return
		end
		local f = CreateFrame("Frame", nil, pane)
		f:EnableMouse(false)
		f:SetFrameLevel(math.max(pane:GetFrameLevel() - 1, 0))
		f:SetAllPoints(pane)
		local tex = f:CreateTexture(nil, "BACKGROUND")
		-- a couple of px in from the rails and the divider, so their
		-- painted edge shadows stay on the stone
		tex:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
		tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
		local c = MelloUI.Palette and MelloUI.Palette.innerPanel or { 0.067, 0.063, 0.051 }
		tex:SetColorTexture(c[1], c[2], c[3], DIM_ALPHA)
		tex.kitPiece = true   -- ours: never faded with the game's art
		f:Hide()
		skin.dims[key] = f
		skin.dimClears[#skin.dimClears + 1] = { frame = f, base = pane, covers = covers }
	end
	local function Rails()
		return skin.window and skin.window.skin or {}
	end
	-- (`or false` in the cover lists: a nil would end the list early)
	PaneDim("left", cf.LeftPaneHost, function()
		local rails = Rails()
		return {
			l = { rails.l or false },
			r = { skin.divider and skin.divider.tex or false },
			t = { rails.t or false, skin.title and skin.title.object or false },
			b = { rails.b or false },
		}
	end)
	PaneDim("right", cf.RightPaneHost, function()
		local rails = Rails()
		return {
			l = { skin.divider and skin.divider.tex or false },
			r = { rails.r or false },
			t = { rails.t or false, skin.title and skin.title.object or false },
			b = { rails.b or false },
		}
	end)
end)

-- the divider's junctions (an agreed addition, the user's pick K): where
-- it leaves the title plate, where the stats inset's top rail meets it,
-- and where it ends on the window's bottom rail. The covers live on the
-- divider's frame (level 505 in the game's layout, above both panes) so
-- they go with it; the stats ones show with their box.
-- Made as the skin first comes on (SkinOnParts), not ahead: each cover
-- takes its place across the divider from the divider's width, measured
-- once, and a window never shown yet may have none to measure (the
-- divider's width comes from its anchors): the covers would sit on the
-- divider's left edge for good.
local function SkinJoints()
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
end

Part(function()
	-- the plate under "Level N Class"
	if _G.CharacterLevelTextBackground then
		Replace(_G.CharacterLevelTextBackground, { as = "UI-Character-Info-ItemLevel-Bounce" })
	end

	-- the model's backdrop: four landscape quadrants (race pictures) under the
	-- character. All four are faded (their union the replacement's rect), so
	-- the window's own stone runs on behind the model: one stone, no second
	-- tile with its own seam; the game's vignette overlay stays on top.
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
end)

-- every equipment slot (its game frame art is a picture inside its 1 x 1
-- BorderFrame), one part each
-- (user, 2026-09-23: "onto the Character Pane next"): the action bars'
-- thin rim on the slot button itself, in the look Item Border names, the
-- icon fitted into it, the game's frame art faded; an empty slot keeps
-- the game's silhouette of what goes there
for _, name in ipairs(SLOT_NAMES) do
	Part(function()
		local slot = _G[name]
		if slot and slot.BorderFrame then
			local border = FirstTexture(slot.BorderFrame)
			if border then
				Replace(border, { as = "UI-Character-Info-GearSlot" })
			end
			if Kit:SkinActionButton(slot, Replace, nil, { as = Kit:ButtonRimRule(), qualityBorder = slot.IconBorder }) then
				skin.slots[#skin.slots + 1] = slot
			end
		end
	end)
end

-- the side tabs: the tab's background, selected when the game's selectedTab is this one
-- Made as the skin first comes on (SkinOnParts), not ahead: dressing a tab
-- lights the selected one's glow (drawn on the game's tab itself) and, in
-- a Side Tab Border other than the default, fits its icon into the rim at
-- once; a skin made ahead and never turned on (the module switched off
-- before the first open) would have left the game's tabs so.
local function SkinSideTabs(cf)
	local tabs = cf.ModeTabs and cf.ModeTabs.Tabs
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
end

-- The divider's junctions and the side tabs (above), each made once, as the
-- skin first comes on (Activate: the game places the window just before it
-- shows it, so it is laid out for the screen by then). They were made there
-- before as well, with every other part.
local function SkinOnParts(cf)
	if not skin.jointsDone then
		skin.jointsDone = true
		SkinJoints()
	end
	if not skin.tabsDone then
		skin.tabsDone = true
		SkinSideTabs(cf)
	end
end

-- the button that folds the right pane away: the game swaps its arrow
-- with the state (UpdateRightPaneToggleButton: PrevPage open, NextPage
-- collapsed), so one replacement per texture, the current one shown
Part(function(cf)
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
end)

-- the detail panes and the PvP tab's line (SkinSidePanes)
Part(function()
	SkinSidePanes()
end)

-- the Window Background's parchment sheet: made here with the rest (it
-- was made on the skin's first coming on), shown by ApplyWindowBackground
Part(function()
	WindowSheet()
end)

-- every scroll bar in the window (M:RefreshScrollBars), the window's
-- children one per run of this part: the walk down every frame of the
-- window is the largest piece of the build
Part(function(cf)
	local roots = skin.barRoots
	if not roots then
		roots = { cf:GetChildren() }
		skin.barRoots, skin.barNext = roots, 1
	end
	local child = roots[skin.barNext]
	skin.barNext = skin.barNext + 1
	if child then
		ScrollBarsAt(child, 0)
	end
	if skin.barNext <= #roots then
		return true   -- more of this part
	end
	skin.barRoots, skin.barNext = nil, nil
	BarsWalked(cf, #roots)
end)

-- Makes the parts not made yet: all of them, or (`budget`, in ms) parts
-- until that much time has gone, at least one; `skin.built` once every part
-- is made. A part that raises is not tried again (a skin that failed half
-- way stayed so before as well).
local function BuildSkin(budget)
	if skin and skin.built then
		return skin
	end
	local cf = CharacterFrame
	if not skin then
		skin = CreateFrame("Frame", "MelloUICharacterSkin", cf)
		skin:SetAllPoints()
		skin:SetFrameLevel(cf:GetFrameLevel())
		skin.reps = {}         -- every replacement, for enable / disable
		skin.followers = {}    -- replacements of art the game shows and hides itself: { rep, region }
		skin.slots = {}
		skin.tabReps = {}      -- the side tabs' (SkinSideTabs, as the skin first comes on)
		skin.offFrom = 1       -- the first replacement made while the skin is off and not put back since (Deactivate)

		-- drag handle for the unlocked window
		skin:EnableMouse(true)
		skin:RegisterForDrag("LeftButton")
		Perf.SetScript(skin, "OnDragStart", function()
			if M.db.movable then
				cf:StartMoving()
			end
		end)
		Perf.SetScript(skin, "OnDragStop", function()
			cf:StopMovingOrSizing()
		end)
		-- (hidden until the skin comes on, also while its parts are still
		-- being made over several frames)
		skin:Hide()
		skin.part = 1
	end
	local t0 = budget and debugprofilestop()
	while skin.part <= #PARTS do
		local part = PARTS[skin.part]
		skin.part = skin.part + 1
		if part(cf) then
			skin.part = skin.part - 1
		end
		if budget and debugprofilestop() - t0 >= budget then
			break
		end
	end
	skin.built = skin.part > #PARTS
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
-- The game's own portrait (the player's face, a spec icon: ClassIcons off)
-- is brought to the same size (user, 2026-09-24, WINDOW-RULES 2b / 2c: the
-- portrait in the ring is always at the medallion size, on every window --
-- it kept the game's size here before); a round picture, it fills the
-- ring's opening, so no disc behind it.
--------------------------------------------------------------------------------

local MEDALLION_TO_RING = 0.66 * 1.15   -- 0.759: the user's fit from the screenshot (+15 % over the rim-inside-opening size)
local portraitSaved = nil

function M:FitPortrait()
	local portrait, ring = skin and skin.portrait, skin and skin.ring
	if not (portrait and ring and ring.tex) then
		return
	end
	if active then
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
			Perf.HookScript(frame, "OnEnter", function(self) if active then self.melloRep:SetState("hover") end end)
			Perf.HookScript(frame, "OnLeave", function(self) if active then self.melloRep:SetState("plain") end end)
		end
	end
	return frame.melloRep or nil
end

-- (run on every stats update of the game's while the paper doll is up: no
-- table or function made per run)
local STAT_CATEGORIES = { "ItemLevelCategory", "AttributesCategory", "EnhancementsCategory" }
local statTops = {}
local function Higher(a, b)
	return a > b
end

function M:RefreshStats()
	if not (skin and active and CharacterStatsPane) then
		return
	end
	local pane = CharacterStatsPane
	for _, key in ipairs(STAT_CATEGORIES) do
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
		local tops, pitch = wipe(statTops), nil
		for row in pane.statsFramePool:EnumerateActive() do
			local ok, top = pcall(row.GetTop, row)
			if ok and top and not (issecretvalue and issecretvalue(top)) then
				tops[#tops + 1] = top
			end
		end
		table.sort(tops, Higher)
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
		-- the same conditions the game uses for its highlight (no closure
		-- per call: this runs on every hover of every row)
		local okS, selected = pcall(frame.IsSelected, frame)
		local okW, atWar = true, nil
		if frame.IsAtWar then
			okW, atWar = pcall(frame.IsAtWar, frame)
		end
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
	Perf.HookScript(thumb, "OnSizeChanged", function()
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

-- The equipment manager's pane (PaperDollFrame's), dressed when it first
-- shows (SkinEquipmentManager)
local function EquipmentPane()
	return _G.PaperDollFrame and _G.PaperDollFrame.EquipmentManagerPane
end

-- Every MinimalScrollBar under `root` (the stats boxes, the reputation,
-- skills, currency and statistics lists, the side panes' description).
-- The equipment manager's own is SkinEquipmentManager's, as it always was.
local function ScrollBarsIn(root, depth)
	depth = depth or 0
	if depth > 7 or root == skin then
		return
	end
	local pane = EquipmentPane()
	if pane and root == pane and not pane.melloKitHooked then
		return
	end
	for _, child in ipairs({ root:GetChildren() }) do
		ScrollBarsAt(child, depth)
	end
end

-- one child of a frame `depth` below the window
ScrollBarsAt = function(child, depth)
	if child.Track and child.Track.Thumb and child.Back and child.Forward then
		SkinScrollBar(child)
	else
		ScrollBarsIn(child, depth + 1)
	end
end

-- The walk down every frame of the window was made on every tab switch and
-- every open (/melloperf, 2026-09-24: ~1 ms and a table per frame walked);
-- the bars are the game's, made with their windows. So the whole window is
-- walked once (the build's last part), again only when the window has a
-- child more or less than then, and a tab the game made after that walk is
-- walked the first time it shows.
local walkedTabs = setmetatable({}, { __mode = "k" })
-- `count`: how many children the window had when the walk began
BarsWalked = function(cf, count)
	skin.barsWalked = count or cf:GetNumChildren()
	for _, name in pairs(_G.CHARACTERFRAME_SUBFRAMES or NONE) do
		local tab = type(name) == "string" and _G[name]
		if tab then
			walkedTabs[tab] = true
		end
	end
end

function M:RefreshScrollBars()
	if not (skin and active) then
		return
	end
	local cf = CharacterFrame
	if skin.barsWalked ~= cf:GetNumChildren() then
		ScrollBarsIn(cf)
		BarsWalked(cf)
	end
	local tab = type(cf.activeSubframe) == "string" and _G[cf.activeSubframe]
	if tab and not walkedTabs[tab] and tab.GetParent then
		walkedTabs[tab] = true
		-- as deep as the whole window's walk reaches under it
		local depth, f = 0, tab
		while f and f ~= cf do
			depth = depth + 1
			f = f:GetParent()
		end
		if f == cf then
			ScrollBarsIn(tab, depth)
		end
	end
end

-- A ColoredProgressBar (Blizzard_SharedXML/Camelot/ProgressBars): the
-- background atlas on the whole 160 x 29 frame, a 15 px Fill the game sizes
-- (SetFillWidth = percent x the frame's width) and tints, a Mask rounding
-- the fill's ends, the Text over it. The bracket replaces the background;
-- the fill and its mask are moved INTO the bracket's opening (the opening is
-- where the background's bar was), and put back when the skin is off.
-- `kind`: "rep" (a reputation bar) or "skill"; both wear Progress Bar Border
-- and draw its art smaller (TAB_BAR_ART); any other kind (a bar on another
-- tab's detail pane) wears it at the default size
local TAB_BAR_ART = 0.85
function SkinProgressBar(bar, kind)
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
	-- the reputation and skill bars share one Progress Bar Border (user,
	-- 2026-09-23: "Skills should reflect the Reputation Bar Changes as one");
	-- the setting keeps its first key
	-- `artScale`: the Reputation and Skills tabs' bars (rows and detail
	-- panes) draw the border art 15 % smaller than the fit gives, in every
	-- Progress Bar Border look (user, 2026-09-24: "the Reputation and Skill
	-- tab Progress bars Need to have their border textures scaled down by
	-- 15%"), on top of the rule's heightScale 0.85 (2026-09-21), which every
	-- look already honoured; per bar, so no other window's bars change. The
	-- fill follows through rep:GetOpening (FitFill, the hooks below)
	local artScale = (kind == "rep" or kind == "skill") and TAB_BAR_ART or nil
	local rep = bg and Replace(bg, { as = "common-stat-bar-BG", rect = bar, artScale = artScale })
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
	-- a new Progress Bar Border (every window's): the fill into the new opening
	rep.onBarChanged = FitFill
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
		if frame.Content.ReputationBar then
			SkinProgressBar(frame.Content.ReputationBar, "rep")
		else
			SkinProgressBar(frame.Content.SkillsBar, "skill")
		end
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

-- Each list's row plates that follow the game's state (their `refresh`), in
-- the order they were made: RefreshLists re-reads the ones of the list on
-- show, not every list's. [scrollBox] = { rep, ... }
local listReps = setmetatable({}, { __mode = "k" })

local function HookList(scrollBox, rowSkin)
	if not (scrollBox and ScrollUtil and ScrollUtil.AddAcquiredFrameCallback) or scrollBox.melloKitHooked then
		return
	end
	scrollBox.melloKitHooked = true
	rowSkin = rowSkin or SkinListFrame
	local reps = {}
	listReps[scrollBox] = reps
	local function SkinRow(frame)
		rowSkin(frame)
		local rep = frame.melloRep
		if rep and rep.refresh and not rep.melloListed then
			rep.melloListed = true
			reps[#reps + 1] = rep
		end
	end
	SkinScrollLines(scrollBox)
	ScrollUtil.AddAcquiredFrameCallback(scrollBox, function(_, frame)
		if active then
			SkinRow(frame)
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
				SkinRow(frame)
			end
		end)
	end
end

-- The equipment manager's icons (user, 2026-09-24: "Equipment Manager Border
-- Slot Needs a Change"): every square icon there -- a set card's icon, the
-- set-icon picker's grid and its current icon, the flyout's item and
-- ignore-slot buttons -- wears every window's Button Border, as the
-- equipment slots, the professions' and the configurator's icons do. The
-- game's frame round the icon is faded; the rim hugs the icon (its edge
-- 2 px under the rim's inner edge, on the icon's centre) and the icon stays
-- where the game puts it, so the game's own layout of its pooled, re-used
-- buttons is never fought. The rim lights with the button's hover and press
-- and turns gold (its checked look) while the game shows the icon selected.
-- A holder { melloRep = the rim, icon } stands for the icon in the Kit's
-- rim registry, since a set card's own melloRep is its plate.
local iconRims = {}
local function FitIconRim(holder)
	local rim = holder.melloRep and holder.melloRep.object
	local icon = holder.icon
	if not (rim and rim.base and icon) then
		return
	end
	local name = rim.base .. "_normal"
	local p = Kit:Piece(name)
	local l, r, t, b = Kit:Insets(name, 1)
	local ok, iw, ih = pcall(icon.GetSize, icon)
	if not (p and l and ok and iw and ih) or Secret(iw) or Secret(ih) or iw <= 0 or ih <= 0 then
		return
	end
	rim:ClearAllPoints()
	rim:SetPoint("CENTER", icon, "CENTER")
	rim:SetSize((iw - 4) * p.w / (p.w - l - r), (ih - 4) * p.h / (p.h - t - b))
end

-- a new Button Border has a new opening: every icon's rim fitted again
Kit:OnBorderChanged("button", function()
	for _, holder in ipairs(iconRims) do
		FitIconRim(holder)
	end
end)

-- The rim on `button` in place of `art` (the game's frame round `icon`);
-- `checked`: function() -> true while the icon is the selected one;
-- `extra`: the game's own hover / selection glows, which the rim replaces.
local function SkinIconRim(button, art, icon, checked, extra)
	local rep = Replace(art, { as = Kit:ButtonRimRule(), button = button, parent = button, checked = checked, alsoFade = extra })
	if not rep then
		return nil
	end
	local holder = { melloRep = rep, icon = icon }
	iconRims[#iconRims + 1] = holder
	Kit:RegisterButtonRim(holder)
	FitIconRim(holder)
	return holder
end

-- The texture the game shows / hides for the selection (a card's
-- SelectedBar, a picker icon's SelectedTexture): the rim re-read with it,
-- so the gold follows the game's own selection as soon as it changes.
local function FollowSelection(holder, tex)
	local function Update()
		local rim = holder.melloRep.object
		if active and rim and rim.Update then
			rim:Update()
		end
	end
	hooksecurefunc(tex, "Show", Update)
	hooksecurefunc(tex, "Hide", Update)
	hooksecurefunc(tex, "SetShown", Update)
end

-- An icon of the set-icon picker (GearManagerPopupFrame, an icon selector
-- popup): a grid button (SelectorButtonTemplate, pooled by its scroll box)
-- or the current icon beside the name box. Its frame is the unnamed
-- BACKGROUND square (UI-EmptySlot-Disabled) behind the Icon; the hover
-- square and, on a grid button, the selection glow (SelectedTexture) give
-- way to the rim's hover and checked looks.
local function SkinPickerIcon(button, selectable)
	if not button or button.melloRep ~= nil then
		return
	end
	button.melloRep = false
	local icon = button.Icon
	local back
	for _, region in ipairs({ button:GetRegions() }) do
		if region ~= icon and region:GetObjectType() == "Texture" and not region.kitPiece and region:GetDrawLayer() == "BACKGROUND" then
			back = region
			break
		end
	end
	if not (icon and back) then
		return
	end
	local extra = {}
	local glow = button.Highlight or (button.GetHighlightTexture and button:GetHighlightTexture())
	if glow then
		extra[#extra + 1] = glow
	end
	local sel = selectable and button.SelectedTexture or nil
	local checked
	if sel then
		extra[#extra + 1] = sel
		checked = function() return sel:IsShown() end
	end
	local holder = SkinIconRim(button, back, icon, checked, extra)
	button.melloRep = holder and holder.melloRep or false
	if holder and sel then
		FollowSelection(holder, sel)
	end
end

-- The picker's current icon now, its grid's buttons as the scroll box
-- acquires them (the grid is laid out on the popup's first show: before
-- that the scroll box has no view to walk).
local function SkinIconPopup()
	local popup = _G.GearManagerPopupFrame
	if not popup or popup.melloKitHooked then
		return
	end
	popup.melloKitHooked = true
	local area = popup.BorderBox and popup.BorderBox.SelectedIconArea
	SkinPickerIcon(area and area.SelectedIconButton, false)
	local box = popup.IconSelector and popup.IconSelector.ScrollBox
	if box and ScrollUtil and ScrollUtil.AddAcquiredFrameCallback then
		ScrollUtil.AddAcquiredFrameCallback(box, function(_, frame)
			if active then
				SkinPickerIcon(frame, true)
			end
		end, M, false)
		if box.HasView and box:HasView() and box.ForEachFrame then
			box:ForEachFrame(function(frame)
				SkinPickerIcon(frame, true)
			end)
		end
	end
end

-- The equipment flyout's buttons (EquipmentFlyoutFrame.buttons: the items
-- that fit a slot, and while a set is edited the ignore / un-ignore /
-- place-in-bags buttons): item buttons like the equipment slots, so the
-- same rim on the button with the icon fitted into it. The game makes them
-- as the flyout first needs them; each is skinned once, after the game's
-- EquipmentFlyout_UpdateItems has laid them out.
local function SkinFlyoutButtons()
	local flyout = _G.EquipmentFlyoutFrame
	if not (active and flyout and flyout.buttons) then
		return
	end
	for _, button in ipairs(flyout.buttons) do
		if button.melloRep == nil then
			Kit:SkinActionButton(button, Replace, nil, { as = Kit:ButtonRimRule(), qualityBorder = button.IconBorder })
		end
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
	-- the card behind the set's name: the single iron rail on dark stone
	-- (user, 2026-09-24, option 4 of the set card looks; the gemless plate
	-- read as a bad border there) -- the kit's tall list row card (the
	-- communities list's, the group finder's results): brighter under the
	-- mouse, its iron lit gold while the set is the selected one. The game's
	-- hover and selected bars give way to those two looks.
	local sel = card.SelectedBar
	if bg then
		local rep = Replace(bg, { as = "CommunitiesListEntry", rect = bg, button = card,
			checked = sel and function() return sel:IsShown() end or nil,
			alsoFade = { card.HighlightBar, card.SelectedBar } })
		card.melloRep = rep or false
		if rep and sel then
			local function Follow()
				if active and rep.Update then
					rep.Update()
				end
			end
			hooksecurefunc(sel, "Show", Follow)
			hooksecurefunc(sel, "Hide", Follow)
			hooksecurefunc(sel, "SetShown", Follow)
		end
	end
	-- the set's icon: the Button Border in place of the game's icon frame
	-- (UI-Character-Info-OutfitIcon-Frame), gold while the set is the
	-- selected one (the SelectedBar the game shows / hides on re-use)
	if card.icon then
		local art
		for _, region in ipairs({ card:GetRegions() }) do
			if region:GetObjectType() == "Texture" and not region.kitPiece and Kit:ArtKey(region) == "UI-Character-Info-OutfitIcon-Frame" then
				art = region
				break
			end
		end
		local holder = art and SkinIconRim(card, art, card.icon, sel and function() return sel:IsShown() end or nil)
		if holder and sel then
			FollowSelection(holder, sel)
		end
		card.melloIconRim = holder or nil
	end
end

-- Made when the pane first shows (RefreshLists: at once when it is up as
-- the skin comes on, else from the pane's own OnShow, which runs before the
-- frame is drawn, so it never shows undressed), not with the rest of the
-- skin on the window's first open. The equipment flyout is the paper
-- doll's as well (SkinFlyouts).
local function SkinEquipmentManager()
	local pane = EquipmentPane()
	if not pane or pane.melloKitHooked then
		return
	end
	pane.melloKitHooked = true
	if pane.Border then
		-- the inset's inner panel stands down on parchment with the stats' (RefreshDims)
		local inset = Replace(pane.Border, { as = "common-insideframe" })
		if inset then
			skin.insetDims[#skin.insetDims + 1] = inset
			M:RefreshDims()
		end
	end
	-- the set-icon picker: its icons in the Button Border, like the set
	-- cards' (SkinIconRim above)
	SkinIconPopup()
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
				Perf.HookScript(new, "OnShow", Centre)
				Perf.HookScript(new, "OnSizeChanged", Centre)
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

-- The equipment flyout (the items that fit a slot, from the paper doll or
-- the equipment manager): its icons in the Button Border, like the set
-- cards'; hooked once, when the skin first comes on
local flyoutsHooked = false
local function SkinFlyouts()
	if flyoutsHooked then
		return
	end
	flyoutsHooked = true
	if _G.EquipmentFlyout_UpdateItems then
		hooksecurefunc("EquipmentFlyout_UpdateItems", SkinFlyoutButtons)
	end
	SkinFlyoutButtons()
end

-- `frame` and every frame above it up to the window shown, by their own
-- flags (the answer holds while the window itself is still opening); a
-- frame outside the window counts as shown when its own chain is
local function ShownInWindow(frame)
	local cf = CharacterFrame
	while frame and frame ~= cf do
		if not frame:IsShown() then
			return false
		end
		frame = frame:GetParent()
	end
	return true
end

-- `all`: every row plate of every list re-read (the skin coming on); else
-- only the rows of the list on show, as a tab switch or an open needs
-- (/melloperf, 2026-09-24: every row of the four lists re-fitted on each)
local managerHooked = false
function M:RefreshLists(all)
	if not (skin and active) then
		return
	end
	listsDirty = false
	HookList(_G.ReputationFrame and _G.ReputationFrame.ScrollBox)
	HookList(_G.SkillsFrame and _G.SkillsFrame.ScrollBox)
	HookList(_G.TokenFrame and _G.TokenFrame.ScrollBox)
	HookList(_G.StatisticsFrame and _G.StatisticsFrame.ScrollBox)
	SkinFlyouts()
	local pane = EquipmentPane()
	if pane then
		if not managerHooked then
			managerHooked = true
			Perf.HookScript(pane, "OnShow", function()
				if active then
					SkinEquipmentManager()
				end
			end)
		end
		if pane:IsShown() then
			SkinEquipmentManager()
		end
	end
	M:RefreshScrollBars()
	if all then
		for _, rep in ipairs(skin.reps) do
			if rep.refresh then
				rep:Enable()
				rep.refresh()
			end
		end
		return
	end
	for box, reps in pairs(listReps) do
		if ShownInWindow(box) then
			for i = 1, #reps do
				local rep = reps[i]
				rep:Enable()
				rep.refresh()
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Turning the skin on and off
--------------------------------------------------------------------------------

local ApplyWindowBackground   -- below, with the settings

local InkSurface -- below
-- (true when it turned the skin on)
local function Activate()
	if active then
		return false
	end
	BuildSkin()
	-- a detail pane the game has made since the skin was built (it is built
	-- ahead of the first open now)
	SkinSidePanes()
	SkinOnParts(CharacterFrame)
	active = true
	skin:Show()
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	M:RefreshFollowers()
	M:FitPortrait()
	M:RefreshTabs()
	M:RefreshStats()
	M:RefreshLists(true)
	if skin.toggleIcons then
		skin.toggleIcons()
	end
	ApplyWindowBackground()
	M:RefreshDims()
	-- the parchment's rects laid before the ink reads what lies on the
	-- parchment (the window's OnShow holds them until here: laid once)
	if layHeld then
		layHeld = nil
		M:LayParchment()
	end
	if InkSurface then
		InkSurface()
	end
	return true
end

local function Deactivate()
	if not active then
		-- a skin made ahead and never turned on (the module switched off
		-- before the window's first open): its pieces put back as turning
		-- the skin off puts them back, what they fitted of the game's own
		-- art with them (a Button Border chosen since has fitted the slots'
		-- icons into its rims)
		if skin then
			for i = skin.offFrom, #skin.reps do
				skin.reps[i]:Disable()
			end
			skin.offFrom = #skin.reps + 1
		end
		return
	end
	active = false
	skin:Hide()
	M:RefreshDims()
	M:FitPortrait()
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	skin.offFrom = #skin.reps + 1
	if CharacterStatsPane and CharacterStatsPane.statsFramePool then
		for row in CharacterStatsPane.statsFramePool:EnumerateActive() do
			Kit:Unfade(row.Background)
		end
	end
	if InkSurface then
		InkSurface()
	end
end

-- (true when it turned the skin on)
local function Sync()
	if M.isEnabled and CharacterFrame then
		return Activate()
	end
	Deactivate()
	return false
end

--------------------------------------------------------------------------------
-- Building ahead (/melloperf, 2026-09-24: the window's first open cost 63 ms,
-- the whole skin made in its OnShow): a few seconds after login -- and again
-- after a fight, or once the settings are in -- the skin's parts are made
-- while the game is idle, a few ms of them per frame; never in a fight, and
-- never while the window is open (its OnShow makes what is left at once, as
-- it always did). The skin stays off while it is made (Activate turns it on
-- as the window opens), so nothing of it shows and the game looks the same
-- until then. The settings must be in first: the parts read some of them
-- (the Button Border, the kit's tuning) as they are made, and they load late
-- on this client (OnEnable comes again when they are).
--------------------------------------------------------------------------------

local PREBUILD_DELAY = 5     -- s: past the login's own burst of work
local PREBUILD_BUDGET = 2    -- ms of parts per frame (one part may run past it)

local prebuilder = CreateFrame("Frame")
local prebuildQueued = false
local QueuePrebuild   -- below

local function PrebuildTick()
	local cf = CharacterFrame
	if (skin and skin.built) or not M.isEnabled or not cf or cf:IsShown() then
		Perf.SetScript(prebuilder, "OnUpdate", nil)
		return
	end
	if InCombatLockdown() then
		Perf.SetScript(prebuilder, "OnUpdate", nil)
		prebuilder:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	-- the kit's queue still working through a fight's refits: never in the
	-- same frames as its few ms (audit, 2026-09-24: the two budgets stacked
	-- after a fight); on again a little after it is through
	if Kit:IsQueueBusy() then
		Perf.SetScript(prebuilder, "OnUpdate", nil)
		Kit:WhenQueueIdle(QueuePrebuild)
		return
	end
	BuildSkin(PREBUILD_BUDGET)
end

local function StartPrebuild()
	if (skin and skin.built) or not (M.isEnabled and CharacterFrame) then
		return
	end
	if MelloUI.dbIsTemporary and not MelloUI.restoredFromBackup then
		return
	end
	Perf.SetScript(prebuilder, "OnUpdate", PrebuildTick)
end

local function PrebuildDue()
	prebuildQueued = false
	StartPrebuild()
end

QueuePrebuild = function()
	if prebuildQueued or (skin and skin.built) then
		return
	end
	prebuildQueued = true
	C_Timer.After(PREBUILD_DELAY, PrebuildDue)
end

-- a fight ended: on again a little later (not in the frame the fight ends
-- in), counted from when the kit's queue is through with the fight's refits
Perf.SetScript(prebuilder, "OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	Kit:WhenQueueIdle(QueuePrebuild)
end)

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
	-- (the window opening: the game picks the tab before it shows the
	-- window, and the window's OnShow below refreshes all of this then)
	hooksecurefunc(CharacterFrame, "ShowSubFrame", function()
		if not CharacterFrame:IsShown() then
			listsDirty = true
			return
		end
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
	Perf.HookScript(CharacterFrame, "OnShow", function()
		-- the parchment's rects laid once, at the end, on what all of this
		-- has shown (each refresh below would lay them again: LayParchment)
		layHeld = GetTime()
		-- (a skin coming on now has had every refresh below, and the lay,
		-- in Activate)
		if active or not Sync() then
			M:RefreshFollowers()
			M:FitPortrait()
			M:RefreshTabs()
			M:RefreshStats()
			if listsDirty then
				M:RefreshLists()
			end
			M:RefreshDims()
			layHeld = nil
			M:LayParchment()
		end
		layHeld = nil
	end)
	-- the panes' inner panels come and go with the character tab (the paper
	-- doll shown: the model and the stats; any other tab: a list and its
	-- details), and with the right pane's Parchment sheet (UI Modifications'
	-- switch, or a Parchment Window Background: both go through SetParchment)
	local paper = _G.PaperDollFrame
	if paper then
		Perf.HookScript(paper, "OnShow", function() M:RefreshDims() end)
		Perf.HookScript(paper, "OnHide", function() M:RefreshDims() end)
	end
	if Kit.SetParchment then
		hooksecurefunc(Kit, "SetParchment", function(_, area)
			if area == "character" then
				M:RefreshDims()
			end
		end)
	end
	-- the parchment sheets' rects follow the window's size and the UI scale
	-- (the rails and the divider keep their size in UI units; what they
	-- cover is measured again)
	Perf.HookScript(CharacterFrame, "OnSizeChanged", function()
		M:LayParchment()
	end)
	local scaleWatch = CreateFrame("Frame")
	scaleWatch:RegisterEvent("UI_SCALE_CHANGED")
	scaleWatch:RegisterEvent("DISPLAY_SIZE_CHANGED")
	Perf.SetScript(scaleWatch, "OnEvent", function()
		M:LayParchment()
	end)
end

function M:OnEnable(db)
	self.db = db
	Hook()
	if CharacterFrame and CharacterFrame:IsShown() then
		Sync()
	end
	QueuePrebuild()
end

function M:OnDisable()
	Deactivate()
end

-- The parchment sheets' rects laid again on what the rails, the divider and
-- the title plate leave free: now, and once more a frame later (a window
-- just shown lays itself out after its OnShow). While the window's OnShow
-- runs (`layHeld`) they are laid once, at its end.
-- (the panes' inner panels on the same free rects, RefreshDims)
local function LayAll()
	LayClear(skin.paneClear)
	LayClear(skin.windowClear)
	for _, c in ipairs(skin.dimClears or NONE) do
		LayClear(c)
	end
end

local function LayAgain()
	skin.layPending = nil
	if CharacterFrame:IsVisible() then
		LayAll()
	end
end

function M:LayParchment()
	if not (skin and CharacterFrame and CharacterFrame:IsVisible()) or layHeld == GetTime() then
		return
	end
	LayAll()
	if C_Timer and not skin.layPending then
		skin.layPending = true
		C_Timer.After(0, LayAgain)
	end
end

-- The panes' inner panels (WINDOW-RULES 2e, BuildSkin's PaneDim) and the
-- insets' own (the stats, the equipment manager), shown where their text
-- lies on stone. Not on parchment (user, 2026-09-24: text on parchment
-- follows the ink rule instead): the right pane's Parchment sheet takes the
-- right pane's panel and the insets' with it (their texts are inked there);
-- a Parchment Window Background takes both panes'. Not on a Dark Window
-- Background either: that window is dark already. The panes' only off the
-- character tab (the model and the stats' insets are there). The paper
-- doll's own shown flag, not its visibility, so the answer holds while the
-- window is closed.
function M:RefreshDims()
	if not (skin and skin.dims) then
		return
	end
	local bg = M.db and M.db.windowBackground or "window"
	local paper = _G.PaperDollFrame
	local onDoll = paper and paper:IsShown() and true or false
	local rightParchment = WindowParchment() or Kit:ParchmentOn("character")
	local stone = active and bg ~= "parchment" and bg ~= "dark"
	local left, right = stone and not onDoll, stone and not onDoll and not rightParchment
	for key, f in pairs(skin.dims) do
		f:SetShown(((key == "left" and left) or (key == "right" and right)) and true or false)
	end
	for _, rep in ipairs(skin.insetDims or {}) do
		local fill = rep.skin and rep.skin.dimFill
		if fill then
			fill:SetShown(not rightParchment)
		end
	end
	if left or right then
		M:LayParchment()
	end
end

-- Window Background Parchment as a parchment SHEET on the window's stone,
-- inside its rails, ending in the quest log's painted strokes on every side
-- (user, 2026-09-24: the character window's parchment without the quest
-- log's edge). The body under the rails stays the window's stone, so the
-- gaps between the strokes show stone, as the quest log's do, and never a
-- straight edge; the sheet shows the Parchment tile at its own tone and the
-- UI's one background resolution (Kit:ParchmentSheet re-tiles it and re-fits
-- its masks whenever its rect changes size). A region of the window's frame
-- skin, one sublevel above the body: only the parchment is masked, never the
-- model, the slots or the text. Made with the skin's parts (BuildSkin).
WindowSheet = function()
	if skin.windowSheet ~= nil then
		return skin.windowSheet
	end
	skin.windowSheet = false
	local ws = skin.window and skin.window.skin
	if not (ws and ws.CreateTexture and Kit.ParchmentSheet) then
		return false
	end
	local clear = CreateFrame("Frame", nil, ws)
	clear:EnableMouse(false)
	clear:SetAllPoints(ws)
	local sheet = Kit:ParchmentSheet(ws, clear, { rect = clear, margin = 2, sublevel = 1,
		piece = LOOKS.backgroundPiece.parchment, tint = { 1, 1, 1 } })
	if not sheet then
		return false
	end
	-- the window skin reaches out past the window (the rails' outset): its
	-- rails bound the sheet, the title plate standing on the top rail too.
	-- The portrait ring is left over the sheet's top-left corner, as it
	-- sits over the rails' corner: cutting the whole top or left side back
	-- to clear it would leave a wide band of bare stone.
	skin.windowClear = { frame = clear, base = ws, covers = function()
		return {
			l = { ws.l or false },
			r = { ws.r or false },
			t = { ws.t or false, skin.title and skin.title.object or false },
			b = { ws.b or false },
		}
	end }
	skin.windowSheet = sheet
	return sheet
end

-- Window Background on the window's stone body (the frame skin's `body`,
-- under both panes: one surface); Parchment as a sheet on that stone
-- (WindowSheet)
ApplyWindowBackground = function()
	local body = skin and skin.window and skin.window.skin and skin.window.skin.body
	if not body then
		return
	end
	local value = M.db and M.db.windowBackground or "window"
	local sheet = WindowSheet()
	if sheet then
		sheet:SetShown(value == "parchment")
	end
	local piece = (value == "window" or (value == "parchment" and sheet)) and "window/frame_body" or LOOKS.backgroundPiece[value]
	-- the right pane's own Parchment sheet stands down under a parchment
	-- window and comes back with any other background
	if Kit.SetParchment then
		Kit:SetParchment("character", Kit:ParchmentOn("character"))
	end
	M:LayParchment()
	if piece then
		if body.kitName ~= piece then
			body:SetVertexColor(1, 1, 1, 1)
			Kit:Apply(body, piece)
		end
		Kit:Retile(body)
	elseif value == "dark" then
		body:SetColorTexture(0.05, 0.045, 0.04, 0.95)
		body.kitPiece, body.kitName = true, nil   -- still ours (a plain mark): never faded with the game's art
	end
end

-- The right pane on parchment (its Parchment sheet, or Window Background
-- Parchment): its texts in ink (QuestInk's rule, user 2026-09-23); the
-- category and header plates, the bars and the icons as they are
InkSurface = function()
	local QI = MelloUI.QuestInk
	if not QI then
		return
	end
	if QI.surfaces.character then
		QI.RefreshSurface("character")
		return
	end
	QI.Surface("character", {
		roots = function()
			local rep, token = _G.ReputationFrame, _G.TokenFrame
			-- the stats' rows live in their scroll boxes (user, 2026-09-23: the
			-- stats stayed light while the reputation pane was inked)
			-- the whole window: every pane and detail pane whatever this client
			-- names them (the reputation's detail was missed, user 2026-09-23);
			-- the skip below keeps what is not on the parchment as it is
			return CharacterFrame, CharacterStatsPane, _G.CharacterStatsPaneScrollBox, _G.CharacterStatsPanePetScrollBox,
				_G.ReputationDetailFrame,
				rep, _G.SkillsFrame, _G.StatisticsFrame, token, _G.PVPRankFrame, _G.HonorFrame, _G.PVPFrame,
				rep and rep.ReputationDetailFrame, token and token.DetailFrame,
				_G.SkillsFrame and _G.SkillsFrame.DetailFrame, _G.SkillDetailFrame
		end,
		on = function()
			if not (active and M.isEnabled) then
				return false
			end
			local bg = M.db and M.db.windowBackground
			return Kit:ParchmentOn("character") or bg == "parchment"
		end,
		-- a Parchment window background is under everything; the Parchment
		-- sheet only under the right pane: a string elsewhere (the Skills
		-- tab's rows beside it) keeps its colours
		skip = function(fs)
			local plate = QI.DefaultSkip(fs)
			if plate == nil then
				return nil   -- not laid out yet: left as it is
			elseif plate then
				return true
			end
			if M.db and M.db.windowBackground == "parchment" then
				return false
			end
			local on = QI.OnSheet(fs, "character")
			if on == nil then
				return nil   -- not laid out yet (a tab switching): left as it is
			end
			return not on
		end,
	})
end

function M:OnSettingChanged(key)
	if key == "statRows" then
		self:RefreshStats()
	elseif key == "windowBackground" then
		ApplyWindowBackground()
		InkSurface()
	end
end

--------------------------------------------------------------------------------
-- For the Dynamic UI Modification picker (Modules/DynamicUI.lua): the
-- character window is one group; the picker opens it while it runs when it
-- is closed, and closes it again after.
--------------------------------------------------------------------------------

local openedForPicker = false

function M:PickerGroups()
	return { { id = "character", title = "Character", hint = "Click to choose the window's background.", sections = {
		{ key = "windowBackground", title = "Window Background", kind = "tile", choices = WINDOW_BACKGROUNDS },
	} } }
end

-- The character window's rect (screen px), nil while it is closed
function M:BarOutline()
	local cf = CharacterFrame
	if not (active and cf and cf:IsShown()) then
		return nil
	end
	local ok, l, b, w, h = pcall(cf.GetRect, cf)
	if not (ok and l and w) or Secret(l) or Secret(w) or w <= 0 then
		return nil
	end
	local sc = cf:GetEffectiveScale()
	return { { l * sc, b * sc, (l + w) * sc, (b + h) * sc } }
end

function M:PickerStart()
	openedForPicker = false
	local cf = CharacterFrame
	if cf and not cf:IsShown() and ShowUIPanel then
		ShowUIPanel(cf)
		openedForPicker = true
	end
end

function M:PickerStop()
	if openedForPicker and CharacterFrame and HideUIPanel then
		HideUIPanel(CharacterFrame)
	end
	openedForPicker = false
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
