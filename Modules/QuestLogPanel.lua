--------------------------------------------------------------------------------
-- MelloUI - Quest Log Panel
--
-- The quest log (QuestMapFrame, the side panel of the world map window
-- WorldMapFrame) and the window it lives in dressed in the painted kit
-- (Modules/Kit.lua) on the game's own layout, as the character, professions
-- and spell book windows are: every kit piece stands in for one of the
-- game's art regions, on that region's rectangle, as a child (or region) of
-- its frame, faded in place of it (docs/WINDOW-RULES.md).
--
-- State (2026-09-21): the window shell (outer rail, title, close, maximize /
-- minimize, the ring on the book icon), the Quests side tab, the list's
-- page and border, the search box and settings button, the headers (category
-- plate, +/- glyphs, dividers), the quest rows (plate highlight, kit tick
-- boxes), the details page (page, border, red buttons) and the scroll bars
-- are on the kit. Pending the user's picks (kit_raw/questlog_catalog.png):
-- the page (stone or parchment), the story header, the rewards box, the
-- campaign headers. The map canvas and its own controls (nav bar, tracking
-- and filter buttons) are the map's and untouched. /qldump lists the art.
--
-- (onelook D8, 2026-10-15) The 0.24.0 touches -- the chat's headings, the
-- difficulty gems, the Quests panel's round rims, the ink and the rows-out-
-- of-view scheduler -- are core's, on for every player (Modules/QuestPages.lua,
-- MelloUI.QuestPages). This file paints the window, the page (and turns the
-- ink on with it: QP.SetPaper), the tick boxes, the hover plates, the +/-
-- glyphs (its dresser, QP.Dresser), the pins and the edges.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
-- frames made in a game window: Core's maker, so the game's gamepad
-- navigation never walks an open window for each one (MelloUI.Safe.CreateFrame)
local CreateFrame = MelloUI.Safe.CreateFrame
local Perf = MelloUI.Perf:Scope("QuestLogPanel")
local hooksecurefunc = Perf.hooksecurefunc
local Kit = MelloUI.Kit
-- what the kit keeps beside the game's frames (Kit.lua: weak-keyed, never keys on them)
local kitHookedOf = MelloUI.Kept.kitHookedOf
local pieceNameOf = MelloUI.Kept.pieceNameOf
local pieceOf = MelloUI.Kept.pieceOf
local repOf = MelloUI.Kept.repOf
local stateIconsOf = MelloUI.Kept.stateIconsOf

local M = MelloUI:RegisterModule("QuestLogPanel", {
	title = "Quest Log Panel",
	desc = "The quest log and its window dressed in the painted kit on the game's own layout.",
	window = { label = "Quest log", desc = "The quest log in the world map window and MelloUI's quest list in the kit.", tab = "Windows", order = 5 },
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
			MelloUI:Notice("Quest log panel: no kit piece mapped for %s", tostring(key))
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

local function Portrait()
	local bf = WorldMapFrame and WorldMapFrame.BorderFrame
	return bf and bf.PortraitContainer and bf.PortraitContainer.portrait
end

-- A quest row's hover plate, one code path for the quest log's titles and
-- the Quests panel's rows, so both show the very same border (user,
-- 2026-09-24: "Quest List Module Mouseover Border resize" -- it must be the
-- quest log's own): the plate's hover look (questlog-quest-glow-yellow ->
-- lists/plate hover) as regions of the row, fitted to `rect` with its caps
-- at the art's scale and only the middle tiled. Both lists pool their rows
-- and a pooled row changes height (a header becomes a quest row, a quest
-- with more objectives takes a title), while a strip refits on its rect's
-- size only while it is shown -- and the plate is hidden until hovered. So a
-- plate kept the size of whatever the row showed first (the 24 px header's
-- border on a 36 px quest row) and a middle stretched across a width set
-- while it was hidden (0.18.0's Panel Width setting). It is refitted each time it
-- is shown instead: it always fits the row the mouse is on.
local function ShowPlate(rep, shown)
	rep.object:SetShown(shown and true or false)
	if shown then
		rep:Refit()      -- shown first: a hidden strip's parts may read no size
	end
end

local function HoverPlate(region, rect)
	local rep = Replace(region, { as = "questlog-quest-glow-yellow", rect = rect })
	if rep then
		rep.SetShown = ShowPlate
	end
	return rep
end

--------------------------------------------------------------------------------
-- The list: pooled title rows and headers (QuestLogQuests_Update rebuilds
-- them from pools under QuestScrollFrame.Contents).
--------------------------------------------------------------------------------

-- A quest title (QuestLogTitleTemplate): the plate's hover look on its
-- highlight (the game shows it on hover and on the called-out quest), the
-- kit tick box on its tracking check box (a Frame: the tick square, the
-- CheckMark the game shows / hides, a hover copy).
local function SkinTitle(button)
	if repOf[button] ~= nil then
		return
	end
	repOf[button] = false
	if button.HighlightTexture then
		local rep = HoverPlate(button.HighlightTexture, button.HighlightTexture)
		repOf[button] = rep or false
		Follow(rep, button.HighlightTexture)
	end
	local cb = button.Checkbox
	if cb and cb.CheckMark then
		local tick, extra = nil, { cb.CheckMark }
		for _, region in ipairs({ cb:GetRegions() }) do
			if region:GetObjectType() == "Texture" and region ~= cb.CheckMark and not pieceOf[region] then
				if not tick and region:GetDrawLayer() ~= "HIGHLIGHT" then
					tick = region
				else
					extra[#extra + 1] = region
				end
			end
		end
		if tick then
			local rep = Replace(tick, { as = "questlog-icon-ticksquare", button = cb, rect = tick, alsoFade = extra,
				checked = function() return cb.CheckMark:IsShown() end })
			if rep then
				-- (SetState: the rule's own re-read -- a rim's Update, the flat
				-- box's driver)
				local function Update()
					if active then
						rep:SetState()
					end
				end
				hooksecurefunc(cb.CheckMark, "SetShown", Update)
				hooksecurefunc(cb.CheckMark, "Show", Update)
				hooksecurefunc(cb.CheckMark, "Hide", Update)
			end
		end
	end
end

-- A header (QuestLogHeaderTemplate = ListHeaderVisualTemplate): the +/- glyph
-- on its collapse button (its plate, its highlight and its name: the core's
-- chat heading, MelloUI.QuestPages)
local function SkinHeader(button)
	if repOf[button] == nil then
		repOf[button] = false
		local collapse = button.CollapseButton
		if collapse and collapse.UpdateCollapsedState then
			hooksecurefunc(collapse, "UpdateCollapsedState", function()
				if active then
					Kit:SkinCollapseButton(collapse, Replace)
				end
			end)
		end
	end
	Kit:SkinCollapseButton(button.CollapseButton, Replace)
end

-- The skin's part of a log row, on the core's one scheduler (QP.Dresser:
-- after the core's dressing of the row, in view at once, the rest a few ms a
-- frame or as the list scrolls)
local function DressLogRow(row, kind)
	if not active then
		return
	end
	if kind == "title" then
		SkinTitle(row)
	elseif kind == "header" then
		SkinHeader(row)
	end
end

--------------------------------------------------------------------------------
-- The map's waypoint pin (WaypointLocationPinTemplate, pooled by the map:
-- Icon re-atlased Untracked / Tracked on acquire, a Highlight on hover):
-- the slider thumb's gem stands in (user's picks, 2026-09-21: I6 untracked,
-- I7 tracked and hover), applied to the game's own textures after each
-- atlas change and put back on disable.
--------------------------------------------------------------------------------
-- (0.19.1, the user 2026-10-04: "very pixelated": the pins' own pieces, cut at the sheet's native 74 px, where the
-- slider thumb's 20 texels were stretched)
local PIN_PIECES = {
	["Waypoint-MapPin-Untracked"] = "inputs/mappin_normal",
	["Waypoint-MapPin-Tracked"] = "inputs/mappin_hover",
	["Waypoint-MapPin-Highlight"] = "inputs/mappin_hover",
	["Waypoint-MapPin-Minimap-Tracked"] = "inputs/mappin_hover",
	["Waypoint-MapPin-Minimap-Untracked"] = "inputs/mappin_normal",
}
local pinTextures = {}

local pinApply = setmetatable({}, { __mode = "k" })   -- [pin texture] = its Apply
local pinAtlas = setmetatable({}, { __mode = "k" })   -- [pin texture] = the atlas the game gave it
local pinHooked = setmetatable({}, { __mode = "k" })   -- [pin texture] = true: SetAtlas hooked
-- `tex` shows the kit piece for its current atlas while the skin is on; the
-- atlas is remembered and put back by RestorePins.
local function SkinPinTexture(tex)
	if not tex or pinHooked[tex] then
		return
	end
	pinHooked[tex] = true
	pinTextures[#pinTextures + 1] = tex
	local function Apply()
		local atlas = pinAtlas[tex]
		local piece = atlas and PIN_PIECES[atlas]
		if active and piece and Kit:Piece(piece) then
			Kit:Apply(tex, piece)          -- after every SetAtlas: the game's call replaced our file
		elseif pieceOf[tex] and atlas then
			pieceOf[tex], pieceNameOf[tex] = nil, nil
			tex:SetAtlas(atlas)
		end
	end
	pinAtlas[tex] = Kit:ArtKey(tex)
	pinApply[tex] = Apply
	hooksecurefunc(tex, "SetAtlas", function(t, atlas)
		pinAtlas[t] = atlas
		Apply()
	end)
	Apply()
end

local function SkinWaypointPin(pin)
	SkinPinTexture(pin.Icon)
	SkinPinTexture(pin.Highlight)
end

local function RefreshPins()
	for _, tex in ipairs(pinTextures) do
		pinApply[tex]()
	end
end

local function HookWaypointPins()
	if WaypointLocationPinMixin and WaypointLocationPinMixin.OnAcquired then
		hooksecurefunc(WaypointLocationPinMixin, "OnAcquired", function(pin)
			if active then
				SkinWaypointPin(pin)
			end
		end)
	end
end

local function SkinExistingPins()
	if WorldMapFrame and WorldMapFrame.EnumeratePinsByTemplate then
		for pin in WorldMapFrame:EnumeratePinsByTemplate("WaypointLocationPinTemplate") do
			SkinWaypointPin(pin)
		end
	end
end

--------------------------------------------------------------------------------
-- The edges (0.20.1, the user's pick 2026-10-10: "Move them inward", as the spell book's). The controls the game
-- parks at the window's edge moved in, clear of the double rail that lies over the content (Kit:ClearRails,
-- KitWindow.lua's nudges): the quest log's gear -- its search box narrower by what the count box beside it (the Quest
-- List's switch stands on it) needs (Kit:Shrink) -- its scroll bar and its bottom edge (the last row clear of the
-- bottom rail); a quest's details: its scroll bar, its Abandon / Share / Track row and the rewards box above it moved
-- up together, the text area shorter by as much (nothing under the box); the map's side panel toggle. MelloUI's Quest
-- List page stands on the log's parts and follows them; its own scroll bar moved as the log's. Laid on each show and
-- size change of the window, the log, the details and the page; without the skin, the game's own places back.
--------------------------------------------------------------------------------
local COUNT_GAP = 3   -- the count box's gap to the gear (as the game's from the search box to the count box)
local ScreenRect = MelloUI.Safe.ScreenRect

-- the search box narrower by what the count box beside it needs to clear the gear (moved in first)
local function SearchEdge(sf)
	local search, dd = sf.SearchBox, sf.SettingsDropdown
	if not search then
		return
	end
	Kit:Shrink(search, "rails", 0, 0)
	if not (active and skin and skin.window) then
		return
	end
	local _, _, countR = ScreenRect(_G.QuestLogCount or search)
	local gearL = dd and ScreenRect(dd)
	if countR and gearL and countR > gearL - COUNT_GAP then
		Kit:Shrink(search, "rails", (countR - gearL + COUNT_GAP) / search:GetEffectiveScale(), 0)
	end
end

local function LayEdges()
	local wm, qm = WorldMapFrame, QuestMapFrame
	if not (wm and qm and Kit.ClearRails) then
		return
	end
	local on = active and skin and skin.window or nil
	local qf = qm.QuestsFrame
	local sf = qf and qf.ScrollFrame
	if sf then
		Kit:ClearRails(on, sf, sf, "y", "BOTTOMRIGHT")
		if sf.SettingsDropdown then
			Kit:ClearRails(on, sf.SettingsDropdown)
		end
		SearchEdge(sf)
		if sf.ScrollBar then
			Kit:ClearRails(on, sf.ScrollBar, nil, "x")
		end
	end
	local details = qf and qf.DetailsFrame
	if details then
		local dsf, box = details.ScrollFrame, details.RewardsFrameContainer
		if dsf and dsf.ScrollBar then
			Kit:ClearRails(on, dsf.ScrollBar, nil, "x")
		end
		if box then
			Kit:Nudge(box, "rails", 0, 0)
		end
		if dsf then
			Kit:Shrink(dsf, "rails", 0, 0)
		end
		if details.AbandonButton then
			local _, dy = Kit:ClearRails(on, details.AbandonButton, nil, "y")
			if dy > 0 then
				if box then
					Kit:Nudge(box, "rails", 0, dy)
				end
				if dsf then
					Kit:Shrink(dsf, "rails", 0, dy)
				end
			end
		end
	end
	if wm.SidePanelToggle then
		Kit:ClearRails(on, wm.SidePanelToggle)
	end
	local ql = MelloUI.QuestList
	local page = ql and ql.Panel and ql.Panel.frame
	if page and page.scrollBar then
		Kit:ClearRails(on, page.scrollBar, nil, "x")
	end
end

--------------------------------------------------------------------------------
-- MelloUI's own quest list page (Modules/QuestListPanel.lua: the Quest List
-- in the map's quest log column, over the log's own parts and built from the
-- game's templates -- the quest log's page, border and divider, a search box,
-- the gear's icon dropdown, a text dropdown, a UIPanelButton switch, a
-- MinimalScrollBar list whose one pool of buttons serves as headers AND
-- rows). Skinned with the same rules as the game's quest log (user, 2026-09-21).
--------------------------------------------------------------------------------
local function MouseOver(b)
	local ok, over = pcall(b.IsMouseOver, b)
	return ok and over == true
end

local locked = setmetatable({}, { __mode = "k" })   -- [row button] = true while its highlight is locked
local isHeaderRow = setmetatable({}, { __mode = "k" })   -- [row button] = true: a header
local rowPlateOf = setmetatable({}, { __mode = "k" })   -- [row button] = its hover plate (false: none)
-- The hover look follows the mouse: a quest row's plate (the quest log's
-- own, HoverPlate). (A header has no plate since 0.24.0: the chat's heading,
-- core's -- MelloUI.QuestPages -- with nothing lit on hover.)
local function QuestListHover(b, over)
	if rowPlateOf[b] then
		rowPlateOf[b]:SetShown(active and over and not isHeaderRow[b])
	end
end

local lockHooked = setmetatable({}, { __mode = "k" })   -- [row button] = true: LockHighlight hooked
-- (after the panel's own Init, which dressed the button's heading or rim
-- through the core: QP.Header / QP.Row)
local function SkinQuestListEntry(button)
	-- a header or a row: told apart after its Init by the normal texture
	local normal = button:GetNormalTexture()
	local isHeader = normal and Kit:ArtKey(normal) == "common-button-list-collapseExpand"
	local band = MelloUI.QuestInk and MelloUI.QuestInk.bandOf[button]
	if not rowPlateOf[button] and band then
		-- a row's hover: the quest log's hover plate on the row's hover band
		-- (QuestInk's QI.RowBand: the title's line, 4 px over and under it,
		-- across the row -- the rect the log's own plate has), under the
		-- text, shown while the mouse is on the row; the band itself faded
		-- (a row has no highlight of its own: the Quests panel clears it)
		rowPlateOf[button] = HoverPlate(band, band) or false
		if rowPlateOf[button] then
			rowPlateOf[button]:SetShown(false)
		end
	end
	-- (the hover itself: the panel's OnRowHover, SkinQuestList below)
	if not lockHooked[button] then
		lockHooked[button] = true
		hooksecurefunc(button, "LockHighlight", function(b)
			locked[b] = true
			QuestListHover(b, true)
		end)
		hooksecurefunc(button, "UnlockHighlight", function(b)
			locked[b] = nil
			QuestListHover(b, MouseOver(b))
		end)
	end
	if button.pin then
		SkinPinTexture(button.pin)      -- the tracked quest's pin: the gem (I7)
	end
	isHeaderRow[button] = isHeader
	-- a row re-used under the mouse keeps its plate (fitted to its new
	-- height), a row re-used elsewhere drops it
	QuestListHover(button, MouseOver(button))
	if isHeader and button.plus then
		Kit:StateIconReps(button, button.plus, button, Replace)
	elseif stateIconsOf[button] then
		for _, rep in pairs(stateIconsOf[button]) do
			if rep then
				rep:SetShown(false)
			end
		end
	end
end

local function SkinQuestList()
	local ql = MelloUI.QuestList
	local frame = ql and ql.Panel and ql.Panel.frame
	if not frame or kitHookedOf[frame] then
		return
	end
	kitHookedOf[frame] = true
	-- the page dressed as the log's column it lies on (BuildSkin's quest log
	-- side panel, below): its page, its border, the search box, the gear
	if frame.bg then
		Replace(frame.bg, { as = "QuestLog-main-background" })
	end
	local border = frame.border
	if border and border.Border then
		Replace(border.Border, { as = "questlog-frame", parent = border, rect = border, alsoFade = { border.TopDetail, border.Shadow } })
	end
	if frame.divider then
		Replace(frame.divider, { as = "QuestLog-frame-devider", rect = frame.divider })
	end
	Kit:SkinSearchBox(frame.search, Replace)
	local menu = frame.menu
	if menu and menu.Icon then
		Replace(menu.Icon, { as = "questlog-icon-setting", button = menu, rect = menu.Icon, alsoFade = Kit:OtherTextures(menu, menu.Icon) })
	end
	-- the group dropdown: the dropdown plate (D1), as every text dropdown's
	local group = frame.group
	if group and group.Background then
		repOf[group] = Replace(group.Background, { as = "common-dropdown-textholder", rect = group, button = group,
			alsoFade = { group.Arrow } }) or false
	end
	-- the switch on the count box: the list's plain plate (F7), hover from
	-- the button
	local b = frame.switch
	if b and b.Middle then
		local extra = { b.Left, b.Right }
		for _, region in ipairs({ b:GetRegions() }) do
			if region:GetObjectType() == "Texture" and region ~= b.Middle and region ~= b.Left and region ~= b.Right
				and not pieceOf[region] and region:GetDrawLayer() == "HIGHLIGHT" then
				extra[#extra + 1] = region
			end
		end
		Replace(b.Middle, { as = "QuestListFilter", rect = b, button = b, alsoFade = extra })
	end
	-- the rows' hover, told by the page (its buttons' scripts are set once
	-- and call it; audit, 2026-09-24, rank 18: they were set on every Init,
	-- and this hooked them again after each one)
	ql.Panel.OnRowHover = QuestListHover
	Kit:HookScrollBoxRows(frame.scrollBox, SkinQuestListEntry, function() return active end, true)
	Kit:SkinScrollBarsIn(frame, Replace)
	Perf.HookScript(frame, "OnShow", LayEdges)   -- (its scroll bar off the rail: The edges)
end

--------------------------------------------------------------------------------
-- Building the skin
--------------------------------------------------------------------------------
local function BuildSkin()
	if skin then
		return skin
	end
	local wm = WorldMapFrame
	local qm = QuestMapFrame
	skin = CreateFrame("Frame", "MelloUIQuestLogSkin", wm)
	skin:SetAllPoints()
	skin:SetFrameLevel(wm:GetFrameLevel())
	skin:EnableMouse(false)
	skin.reps = {}
	skin.followers = {}
	skin.Replace = Replace

	-- the window (WorldMapFrame.BorderFrame, PortraitFrameTemplateMinimizable)
	local bf = wm.BorderFrame
	if bf then
		-- edges only: the frame's body would cover the map canvas (the border
		-- frame sits above the canvas, in the HIGH strata)
		Kit:SkinWindowShell(bf, Replace, skin, { portrait = Portrait(), body = false })
		-- (the window's rail: the edges' measure, LayEdges)
		for _, rep in ipairs(skin.reps) do
			if rep.key == "NineSlicePanelTemplate" then
				skin.window = rep
			end
		end
		-- the title band (window top to the title container's bottom) is bare
		-- with the body off: the page stone there, inside the outer rail
		if bf.TitleContainer then
			local ins = Kit:OuterRailInset()
			local band = CreateFrame("Frame", nil, bf)
			band:EnableMouse(false)
			band:SetPoint("TOPLEFT", bf, "TOPLEFT", ins[1], -ins[3])
			band:SetPoint("TOPRIGHT", bf, "TOPRIGHT", -ins[2], -ins[3])
			band:SetPoint("BOTTOM", bf.TitleContainer, "BOTTOM", 0, -4)
			Replace(band, { as = "MapTitleBand", parent = bf, rect = band, noFade = true })
		end
	end

	-- the quest log side panel
	if qm then
		Kit:SkinSideTab(qm.QuestsTab, Replace)
		local qf = qm.QuestsFrame
		local sf = qf and qf.ScrollFrame
		if sf then
			if sf.Background then
				Replace(sf.Background, { as = "QuestLog-main-background" })
			end
			Kit:SkinSearchBox(sf.SearchBox, Replace)
			local dd = sf.SettingsDropdown
			if dd and dd.Icon then
				Replace(dd.Icon, { as = "questlog-icon-setting", button = dd, rect = dd.Icon, alsoFade = Kit:OtherTextures(dd, dd.Icon) })
			end
			local border = sf.BorderFrame
			if border and border.Border then
				Replace(border.Border, { as = "questlog-frame", parent = border, rect = border, alsoFade = { border.TopDetail, border.Shadow } })
			end
			-- (the shade under the quest text, 2026-09-22, is gone: the page is
			-- one even parchment -- user, 2026-09-23: "remove it")
			local contents = sf.Contents
			if contents then
				local sep = contents.Separator
				if sep and sep.Divider then
					Replace(sep.Divider, { as = "QuestLog-frame-devider", rect = sep.Divider })
				end
				local story = contents.StoryHeader
				if story and story.Divider then
					Replace(story.Divider, { as = "QuestLog-frame-devider", rect = story.Divider })
				end
			end
		end
		local details = qf and qf.DetailsFrame
		if details then
			if details.Bg then
				Replace(details.Bg, { as = "QuestDetailsBackgrounds" })
			end
			local border = details.BorderFrame
			if border and border.Border then
				Replace(border.Border, { as = "questlog-frame", parent = border, rect = border, alsoFade = { border.TopDetail } })
			end
			if details.BackFrame then
				Kit:SkinRedButton(details.BackFrame.BackButton, Replace)
			end
			for _, key in ipairs({ "AbandonButton", "ShareButton", "TrackButton" }) do
				Kit:SkinRedButton(details[key], Replace)
			end
		end
	end

	Kit:SkinScrollBarsIn(wm, Replace, wm.ScrollContainer)
	SkinQuestList()
	HookWaypointPins()
	return skin
end

function M:RefreshFollowers()
	if not (skin and active) then
		return
	end
	for _, f in ipairs(skin.followers) do
		f.rep:SetShown(f.region:IsShown())
	end
	Kit:SkinScrollBarsIn(WorldMapFrame, Replace, WorldMapFrame.ScrollContainer)
	Kit:FitPortrait(Portrait(), skin.ring)
	SkinQuestList()
	-- the Quests panel's plates: Enable shows every rep, but a row's hover
	-- plate belongs only on the row the mouse is on
	local ql = MelloUI.QuestList
	local sb = ql and ql.Panel and ql.Panel.frame and ql.Panel.frame.scrollBox
	if sb and sb.ForEachFrame then
		sb:ForEachFrame(function(b)
			QuestListHover(b, MouseOver(b))
		end)
	end
end

local function Activate()
	if active or not (WorldMapFrame and QuestMapFrame) then
		return
	end
	BuildSkin()
	active = true
	skin:Show()
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	M:RefreshFollowers()
	-- the page's ink on the quest log and the Quests panel, and every log row
	-- dressed again (the core's, MelloUI.QuestPages: this skin's dresser with it)
	local QP = MelloUI.QuestPages
	if QP then
		QP.SetPaper(true)
	end
	SkinExistingPins()
	RefreshPins()
	LayEdges()
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
	Kit:UnfitPortrait(Portrait())
	RefreshPins()
	LayEdges()   -- (the game's own places back)
	-- the quest log and the quest list off the page: the game's colours again
	-- (the core's headings, gems and rims stay: MelloUI.QuestPages)
	local QP = MelloUI.QuestPages
	if QP then
		QP.SetPaper(false)
	end
end

local function Sync()
	if M.isEnabled and WorldMapFrame and QuestMapFrame then
		Activate()
	else
		Deactivate()
	end
end

local function Hook()
	if hooked or not (WorldMapFrame and QuestMapFrame) then
		return
	end
	hooked = true
	-- the skin's part of each log row on the core's scheduler (MelloUI.QuestPages:
	-- the core hooks the log's update and its scroll)
	local QP = MelloUI.QuestPages
	if QP then
		QP.Dresser(DressLogRow)
	end
	Perf.HookScript(WorldMapFrame, "OnShow", function()
		Sync()
		M:RefreshFollowers()
		LayEdges()
	end)
	-- (maximized and back: the rails elsewhere)
	Perf.HookScript(WorldMapFrame, "OnSizeChanged", LayEdges)
	Perf.HookScript(QuestMapFrame, "OnShow", function()
		M:RefreshFollowers()
		LayEdges()
	end)
	local details = QuestMapFrame.QuestsFrame and QuestMapFrame.QuestsFrame.DetailsFrame
	if details then
		Perf.HookScript(details, "OnShow", LayEdges)
	end
	-- (the game sizes its search box again with each count, Camelot's QuestMapFrameUtils: taken as the game's, the
	-- box narrowed again -- The edges)
	if type(QuestLogQuests_ShowQuestCount) == "function" then
		hooksecurefunc("QuestLogQuests_ShowQuestCount", function()
			local qf = QuestMapFrame.QuestsFrame
			local sf = qf and qf.ScrollFrame
			if sf and sf.SearchBox and Kit.ShrinkTaken then
				Kit:ShrinkTaken(sf.SearchBox)
				SearchEdge(sf)
			end
		end)
	end
	local sf = QuestScrollFrame
	if sf and sf.HookScript then
		Perf.HookScript(sf, "OnShow", LayEdges)   -- (Back from a quest's details)
	end
	-- MelloUI's quest list window is created on demand
	if MelloUI.QuestList and MelloUI.QuestList.Panel and MelloUI.QuestList.Panel.Create then
		hooksecurefunc(MelloUI.QuestList.Panel, "Create", function()
			if active then
				SkinQuestList()
			end
		end)
	end
	if QuestMapFrame_ShowQuestDetails then
		hooksecurefunc("QuestMapFrame_ShowQuestDetails", function()
			M:RefreshFollowers()
		end)
	end
end

-- The map and quest log frames load with the UI; wait for them if not.
local eventFrame = CreateFrame("Frame")
Perf.SetScript(eventFrame, "OnEvent", function()
	if WorldMapFrame and QuestMapFrame and M.isEnabled then
		eventFrame:UnregisterAllEvents()
		Hook()
		Sync()
	end
end)

function M:OnEnable(db)
	self.db = db
	if WorldMapFrame and QuestMapFrame then
		Hook()
		Sync()
	else
		eventFrame:RegisterEvent("ADDON_LOADED")
		eventFrame:RegisterEvent("PLAYER_LOGIN")
	end
end

function M:OnDisable()
	eventFrame:UnregisterAllEvents()
	Deactivate()
end

--------------------------------------------------------------------------------
-- /qldump: the window's art (regions by default; "frames", "reps"; "log" for
-- the quest log panel alone). Opens the copy window.
--------------------------------------------------------------------------------
SLASH_MELLOQLDUMP1 = "/qldump"
SlashCmdList.MELLOQLDUMP = function(msg)
	if not WorldMapFrame then
		MelloUI:Print("World map not loaded.")
		return
	end
	MelloUI:ClearLog()
	if msg == "log" or msg == "log frames" then
		Kit:DumpWindow(QuestMapFrame, skin, msg == "log frames" and "frames" or nil)
	else
		Kit:DumpWindow(WorldMapFrame, skin, msg)
	end
	MelloUI:ShowLog("qldump " .. (msg or ""))
end

-- What this module keeps beside the game's frames (hard rule 1: weak-keyed
-- tables, never keys on the frames), for the dumps and the tests: read only
-- (onelook D8: the headings, rims and the scheduler's tables are the core's, MelloUI.QuestPages.kept)
M.kept = { isHeaderRow = isHeaderRow, lockHooked = lockHooked, locked = locked, pinApply = pinApply,
	pinAtlas = pinAtlas, pinHooked = pinHooked, rowPlateOf = rowPlateOf }
