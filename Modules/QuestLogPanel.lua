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
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("QuestLogPanel")
local hooksecurefunc = Perf.hooksecurefunc
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("QuestLogPanel", {
	title = "Quest Log Panel",
	desc = "The quest log and its window dressed in the painted kit on the game's own layout.",
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
-- while it was hidden (the Panel Width setting). It is refitted each time it
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

-- The rows' Init sets their art again on every refresh (SetHighlightTexture,
-- ClearNormalTexture + SetNormalAtlas); should the client hand back another
-- texture object than the one replaced, that one is faded with the plate
-- too, so the game's own highlight never shows beside ours.
local function KeepFaded(rep, region)
	if not (rep and region) or region == rep.region then
		return
	end
	for _, r in ipairs(rep.alsoFade) do
		if r == region then
			return
		end
	end
	rep.alsoFade[#rep.alsoFade + 1] = region
	if active then
		Kit:Fade(region)
	end
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
	if button.melloRep ~= nil then
		return
	end
	button.melloRep = false
	if button.HighlightTexture then
		local rep = HoverPlate(button.HighlightTexture, button.HighlightTexture)
		button.melloRep = rep or false
		Follow(rep, button.HighlightTexture)
	end
	local cb = button.Checkbox
	if cb and cb.CheckMark then
		local tick, extra = nil, { cb.CheckMark }
		for _, region in ipairs({ cb:GetRegions() }) do
			if region:GetObjectType() == "Texture" and region ~= cb.CheckMark and not region.kitPiece then
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
				local function Update()
					if active and rep.object.Update then
						rep.object:Update()
					end
				end
				hooksecurefunc(cb.CheckMark, "SetShown", Update)
				hooksecurefunc(cb.CheckMark, "Show", Update)
				hooksecurefunc(cb.CheckMark, "Hide", Update)
			end
		end
	end
end

-- A header (QuestLogHeaderTemplate = ListHeaderVisualTemplate): the category
-- plate on its normal texture, the +/- glyph on its collapse button.
local function SkinHeader(button)
	if button.melloRep == nil then
		button.melloRep = false
		local normal = button.GetNormalTexture and button:GetNormalTexture()
		if normal then
			local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
			button.melloRep = Replace(normal, { as = "common-button-list-collapseExpand", rect = button, button = button,
				alsoFade = highlight and { highlight } or nil }) or false
		end
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

-- On the reskin's parchment the quest titles and objectives are dark ink,
-- a quest's difficulty in pips left of its tracking box (QuestInk; user,
-- 2026-09-23: black text, "D"). The game colours them on each update; the
-- colour it gave an objective (grey once done) is watched, so inking again
-- never mistakes our own ink for it. Off: the game's look back.
local PIP_SIZE = 10

local function QuestLevel(questID)
	if not (questID and C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetInfo) then
		return nil
	end
	local ok, index = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
	if not (ok and index) then
		return nil
	end
	local okI, info = pcall(C_QuestLog.GetInfo, index)
	if not (okI and type(info) == "table") then
		return nil
	end
	local level = info.difficultyLevel or info.level
	if issecretvalue and issecretvalue(level) then
		return nil
	end
	return level
end

-- an objective's ink from the game's colour: grey once done
local function ObjectiveRole(r)
	return (r and r < 0.8) and "faded" or "text"
end

-- One title's ink and pips, one objective's ink (the game's look back while
-- the skin is off)
local function InkTitle(QI, title)
	local fs = title.Text
	if not fs then
		return
	end
	if active then
		local tier = QI.TierForQuest(title.questID, QuestLevel(title.questID))
		QI.Ink(fs, tier == 1 and "faded" or "title")
		title.melloPips = title.melloPips or QI.Pips(title, PIP_SIZE)
		title.melloPips:ClearAllPoints()
		if title.Checkbox then
			title.melloPips:SetPoint("RIGHT", title.Checkbox, "LEFT", -4, 0)
		else
			title.melloPips:SetPoint("TOPRIGHT", title, "TOPRIGHT", -4, -3)
		end
		title.melloPips:SetTier(tier)
	else
		QI.Plain(fs)
		if fs.melloColourWatched then
			fs:SetTextColor(QI.GameColour(fs))
		end
		if title.melloPips then
			title.melloPips:SetTier(nil)
		end
	end
end

local function InkObjective(QI, objective)
	local fs = objective.Text
	if fs then
		QI.WatchColour(fs, ObjectiveRole)
		if active then
			local r = QI.GameColour(fs)
			QI.Ink(fs, r < 0.8 and "faded" or "text")
		else
			QI.Plain(fs)
			fs:SetTextColor(QI.GameColour(fs))
		end
	end
end

--------------------------------------------------------------------------------
-- Rows out of view (/melloperf, user 2026-09-24: the first map open dressed
-- the whole quest log in one QuestLogQuests_Update -- every pooled row's
-- plate and tick box made, its pips made, its text inked -- 8.8 ms). A row
-- the list shows for the first time is dressed in the update only when it
-- lies in the list's view (the scroll frame's rect); the rows below or
-- above it wait, and are dressed a few ms per frame after, or at once as
-- the list scrolls, changes size or shows, before they can be seen. A row
-- dressed once is dressed and inked in every update, as before.
--------------------------------------------------------------------------------

local ROW_BUDGET = 2   -- ms of waiting rows per frame
local waiting = {}     -- the rows waiting, in the list's order (a row no longer waiting is passed over)
local waitingKind = setmetatable({}, { __mode = "k" })   -- [row] = "title" | "header" | "objective" while it waits
local waitAt = 1
local rowsFrame = CreateFrame("Frame")

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe and MelloUI.Safe.IsSecret or issecretvalue

-- The list's view: its top and bottom; false while it cannot be seen (every
-- new row waits); nil when its rect cannot be read (every row counts as seen)
local function ListView(sf)
	if not sf:IsVisible() then
		return false
	end
	local okT, top = pcall(sf.GetTop, sf)
	local okB, bottom = pcall(sf.GetBottom, sf)
	if okT and okB and top and bottom and not Secret(top) and not Secret(bottom) then
		return top, bottom
	end
	return nil
end

local function InView(row, top, bottom)
	if top == false then
		return false
	elseif top == nil then
		return true
	end
	local okT, t = pcall(row.GetTop, row)
	local okB, b = pcall(row.GetBottom, row)
	if not (okT and okB and t and b) or Secret(t) or Secret(b) then
		return true
	end
	return b < top and t > bottom
end

-- a row's whole dressing, as the list's update gives it
local function DressRow(row, kind)
	local QI = MelloUI.QuestInk
	if kind == "title" then
		SkinTitle(row)
		if row.Text then
			QI.WatchColour(row.Text)
		end
		InkTitle(QI, row)
	elseif kind == "header" then
		SkinHeader(row)
	else
		InkObjective(QI, row)
	end
end

local DressWaiting   -- below
local rowsTicking = false

local function RowsTick()
	DressWaiting(ROW_BUDGET)
end

local function Wait(row, kind)
	if not waitingKind[row] then
		waitingKind[row] = kind
		waiting[#waiting + 1] = row
		if not rowsTicking then
			rowsTicking = true
			Perf.SetScript(rowsFrame, "OnUpdate", RowsTick)
		end
	end
end

-- The waiting rows dressed: those in the list's view now (`inView`), or
-- (`budget`, in ms) in order until that much time has gone, or all of them.
-- A row the list no longer shows (released to its pool) is passed over:
-- the update that shows it again decides for it.
DressWaiting = function(budget, inView)
	local top, bottom
	if inView then
		top, bottom = ListView(QuestScrollFrame)
	end
	local t0 = budget and debugprofilestop()
	local i = inView and 1 or waitAt
	while i <= #waiting do
		local row = waiting[i]
		local kind = waitingKind[row]
		if not inView then
			waitAt = i + 1
		end
		if kind and (not inView or InView(row, top, bottom)) then
			waitingKind[row] = nil
			if active and row:IsShown() then
				DressRow(row, kind)
			end
		end
		i = i + 1
		if budget and debugprofilestop() - t0 >= budget then
			break
		end
	end
	if waitAt > #waiting then
		for n = #waiting, 1, -1 do
			waiting[n] = nil
		end
		waitAt = 1
		rowsTicking = false
		Perf.SetScript(rowsFrame, "OnUpdate", nil)
	end
end

local function StopWaiting()
	for n = #waiting, 1, -1 do
		waitingKind[waiting[n]] = nil
		waiting[n] = nil
	end
	waitAt = 1
	rowsTicking = false
	Perf.SetScript(rowsFrame, "OnUpdate", nil)
end

-- the list scrolled, sized or shown: the waiting rows it shows now, at once
local function DressShown()
	if waiting[waitAt] then
		DressWaiting(nil, true)
	end
end

-- `skipWaiting`: a row still waiting is inked when it is dressed
local function InkList(skipWaiting)
	local QI = MelloUI.QuestInk
	local sf = QuestScrollFrame
	if not (QI and sf and sf.titleFramePool) then
		return
	end
	for title in sf.titleFramePool:EnumerateActive() do
		if not (skipWaiting and waitingKind[title]) then
			InkTitle(QI, title)
		end
	end
	if sf.objectiveFramePool then
		for objective in sf.objectiveFramePool:EnumerateActive() do
			if not (skipWaiting and waitingKind[objective]) then
				InkObjective(QI, objective)
			end
		end
	end
end

local function SkinList()
	local sf = QuestScrollFrame
	if not (sf and sf.titleFramePool) then
		return
	end
	-- (with the skin off nothing waits: the rows are made and left off, as before)
	local top, bottom = true, nil
	if active then
		top, bottom = ListView(sf)
	end
	local QI = MelloUI.QuestInk
	for title in sf.titleFramePool:EnumerateActive() do
		if top ~= true and (title.melloRep == nil or (title.Text and not title.melloPips)) and not InView(title, top, bottom) then
			Wait(title, "title")
		else
			waitingKind[title] = nil
			SkinTitle(title)
			if title.Text then
				QI.WatchColour(title.Text)
			end
		end
	end
	for header in sf.headerFramePool:EnumerateActive() do
		if top ~= true and header.melloRep == nil and not InView(header, top, bottom) then
			Wait(header, "header")
		else
			waitingKind[header] = nil
			SkinHeader(header)
		end
	end
	if top ~= true and sf.objectiveFramePool then
		for objective in sf.objectiveFramePool:EnumerateActive() do
			local fs = objective.Text
			if fs and not fs.melloColourWatched and not InView(objective, top, bottom) then
				Wait(objective, "objective")
			else
				waitingKind[objective] = nil
			end
		end
	end
	InkList(true)
end

-- The quest list window (MelloUI's) follows: its rows drawn again
local function InkQuestListWindow()
	local QI = MelloUI.QuestInk
	if QI then
		QI.onParchment = active
	end
	local ql = ns.QuestList
	if ql and ql.Panel and ql.Panel.frame and ql.Panel.Update then
		pcall(ql.Panel.Update, ql.Panel)
	end
end

--------------------------------------------------------------------------------
-- The map's waypoint pin (WaypointLocationPinTemplate, pooled by the map:
-- Icon re-atlased Untracked / Tracked on acquire, a Highlight on hover):
-- the slider thumb's gem stands in (user's picks, 2026-09-21: I6 untracked,
-- I7 tracked and hover), applied to the game's own textures after each
-- atlas change and put back on disable.
--------------------------------------------------------------------------------
local PIN_PIECES = {
	["Waypoint-MapPin-Untracked"] = "inputs/slider_thumb_normal",
	["Waypoint-MapPin-Tracked"] = "inputs/slider_thumb_hover",
	["Waypoint-MapPin-Highlight"] = "inputs/slider_thumb_hover",
	["Waypoint-MapPin-Minimap-Tracked"] = "inputs/slider_thumb_hover",
	["Waypoint-MapPin-Minimap-Untracked"] = "inputs/slider_thumb_normal",
}
local pinTextures = {}

-- `tex` shows the kit piece for its current atlas while the skin is on; the
-- atlas is remembered and put back by RestorePins.
local function SkinPinTexture(tex)
	if not tex or tex.melloPinHooked then
		return
	end
	tex.melloPinHooked = true
	pinTextures[#pinTextures + 1] = tex
	local function Apply()
		local atlas = tex.melloAtlas
		local piece = atlas and PIN_PIECES[atlas]
		if active and piece and Kit:Piece(piece) then
			Kit:Apply(tex, piece)          -- after every SetAtlas: the game's call replaced our file
		elseif tex.kitPiece and atlas then
			tex.kitPiece, tex.kitName = nil, nil
			tex:SetAtlas(atlas)
		end
	end
	tex.melloAtlas = Kit:ArtKey(tex)
	tex.melloPinApply = Apply
	hooksecurefunc(tex, "SetAtlas", function(t, atlas)
		t.melloAtlas = atlas
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
		tex.melloPinApply()
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
-- MelloUI's own quest list window (Modules/QuestListPanel.lua: the "Quests"
-- panel docked to the map's right, built from the game's templates —
-- PortraitFrameTemplate without the portrait, the quest log's page and
-- divider, a search box, UIPanelButton filters, a check box, a
-- MinimalScrollBar list whose one pool of buttons serves as headers AND
-- rows). Skinned with the same rules as the game's quest log (user, 2026-09-21).
--------------------------------------------------------------------------------
local function MouseOver(b)
	local ok, over = pcall(b.IsMouseOver, b)
	return ok and over == true
end

-- The hover looks follow the mouse: a quest row's plate (the quest log's
-- own, HoverPlate), a header's plate in its lighter hover state. A header
-- the panel lights while it reveals a group (LockHighlight) keeps that look
-- too: the game's highlight is faded under the kit, so the lock showed
-- nothing but the pulse.
local function QuestListHover(b, over)
	if b.melloRow then
		b.melloRow:SetShown(active and over and not b.melloIsHeader)
	end
	local h = b.melloHeader
	if h and h.Update then
		h.hover = (over or b.melloLocked) and true or nil
		if not over then
			h.pressed = nil
		end
		h.Update()
	end
end

local function QuestListEnter(b)
	QuestListHover(b, true)
end

local function QuestListLeave(b)
	QuestListHover(b, false)
end

local function SkinQuestListEntry(button)
	-- a header or a row: told apart after its Init by the normal texture
	local normal = button:GetNormalTexture()
	local highlight = button:GetHighlightTexture()
	local isHeader = normal and Kit:ArtKey(normal) == "common-button-list-collapseExpand"
	if isHeader and not button.melloHeader then
		button.melloHeader = Replace(normal, { as = "common-button-list-collapseExpand", rect = button, button = button,
			alsoFade = highlight and { highlight } or nil }) or false
		if button.melloHeader then
			-- refitted when shown, as the hover plate: a width set while the
			-- button served as a quest row reaches the header's plate too
			button.melloHeader.SetShown = ShowPlate
		end
	end
	if not button.melloRow then
		-- a row's hover: the quest log's hover plate on the whole row (its
		-- clickable width inside the list, left of the scroll bar, and its
		-- height), shown while the mouse is on it
		button.melloRow = HoverPlate(highlight, button) or false
		if button.melloRow then
			button.melloRow:SetShown(false)
		end
	end
	KeepFaded(button.melloRow, highlight)
	if isHeader then
		KeepFaded(button.melloHeader, normal)
		KeepFaded(button.melloHeader, highlight)
	end
	-- the panel's Init SETS the OnEnter / OnLeave scripts on every refresh,
	-- which drops earlier hooks -- the header plate's own hover hooks from
	-- Kit:Replace among them (a header lit no more once re-used): hook again
	-- after each Init
	Perf.HookScript(button, "OnEnter", QuestListEnter)
	Perf.HookScript(button, "OnLeave", QuestListLeave)
	if not button.melloLockHooked then
		button.melloLockHooked = true
		hooksecurefunc(button, "LockHighlight", function(b)
			b.melloLocked = true
			QuestListHover(b, true)
		end)
		hooksecurefunc(button, "UnlockHighlight", function(b)
			b.melloLocked = nil
			QuestListHover(b, MouseOver(b))
		end)
	end
	if button.pin then
		SkinPinTexture(button.pin)      -- the tracked quest's pin: the gem (I7)
	end
	button.melloIsHeader = isHeader
	if button.melloHeader then
		button.melloHeader:SetShown(isHeader and true or false)
	end
	-- a row re-used under the mouse keeps its plate (fitted to its new
	-- height), a row re-used elsewhere drops it
	QuestListHover(button, MouseOver(button))
	if isHeader and button.plus then
		Kit:StateIconReps(button, button.plus, button, Replace)
	elseif button.melloIcons then
		for _, rep in pairs(button.melloIcons) do
			if rep then
				rep:SetShown(false)
			end
		end
	end
end

local function SkinQuestList()
	local ql = ns.QuestList
	local frame = ql and ql.Panel and ql.Panel.frame
	if not frame or frame.melloKitHooked then
		return
	end
	frame.melloKitHooked = true
	-- the panel is docked 2 px right of the map: with both outer rails
	-- growing outward they overlapped (user, 2026-09-21) — spread the two
	-- by both rails' growth while the skin is on (this window is MelloUI's own)
	local gap = 2 + 2 * Kit:OuterRailOutset()
	local function Dock(x)
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT", x, 0)
		frame:SetPoint("BOTTOMLEFT", WorldMapFrame, "BOTTOMRIGHT", x, 0)
	end
	skin.questListDock = Dock
	Dock(gap)
	Kit:SkinWindowShell(frame, Replace, skin, { noRing = true, body = false })
	if frame.bg then
		-- the page fills the window to the outer rail's bevel (the frame's
		-- body is off, as the page region sits under the frame's holders)
		Replace(frame.bg, { as = "QuestLog-main-background", rect = frame, inset = Kit:OuterRailInset() })
	end
	if frame.divider then
		Replace(frame.divider, { as = "QuestLog-frame-devider", rect = frame.divider })
	end
	Kit:SkinSearchBox(frame.search, Replace)
	-- the filter buttons (F7): the plain plate, the selected plate on the
	-- active filter; the panel's own alpha dimming is off while the skin is on
	for _, b in ipairs(frame.filters or {}) do
		if b.Middle then
			local extra = { b.Left, b.Right }
			for _, region in ipairs({ b:GetRegions() }) do
				if region:GetObjectType() == "Texture" and region ~= b.Middle and region ~= b.Left and region ~= b.Right
					and not region.kitPiece and region:GetDrawLayer() == "HIGHLIGHT" then
					extra[#extra + 1] = region
				end
			end
			b.melloPlain = Replace(b.Middle, { as = "QuestListFilter", rect = b, button = b, alsoFade = extra })
			b.melloSelected = Replace(b.Middle, { as = "QuestListFilter-Selected", rect = b, noFade = true })
			b.melloKitPlate = true
		end
	end
	local function RefreshFilters()
		if not active then
			return
		end
		local db = ql.M and ql.M.db
		for _, b in ipairs(frame.filters or {}) do
			if b.melloPlain then
				local selected = db and b.key == db.filter
				b.melloPlain:SetShown(not selected)
				b.melloSelected:SetShown(selected and true or false)
				b:SetAlpha(1)
			end
		end
	end
	skin.refreshFilters = RefreshFilters
	hooksecurefunc(ql.Panel, "Update", RefreshFilters)
	RefreshFilters()
	Kit:SkinCheckButton(frame.hide, Replace, "UI-CheckBox-Up")
	if frame.levelCheck then
		Kit:SkinCheckButton(frame.levelCheck, Replace, "UI-CheckBox-Up")   -- the map's "5+ levels above" shortcut
	end
	Kit:HookScrollBoxRows(frame.scrollBox, SkinQuestListEntry, function() return active end, true)
	Kit:SkinScrollBarsIn(frame, Replace)
	-- (the shade under the list's text, 2026-09-22, is gone: the page is one
	-- even parchment -- user, 2026-09-23: "remove it")
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
	SkinList()
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
	if skin.refreshFilters then
		skin.refreshFilters()
	end
	-- the Quests panel's plates: Enable shows every rep, but a row's hover
	-- plate belongs only on the row the mouse is on, a header's plate only
	-- on a button that shows a header now
	local ql = ns.QuestList
	local sb = ql and ql.Panel and ql.Panel.frame and ql.Panel.frame.scrollBox
	if sb and sb.ForEachFrame then
		sb:ForEachFrame(function(b)
			if b.melloHeader then
				b.melloHeader:SetShown(b.melloIsHeader and true or false)
			end
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
	if skin.questListDock then
		skin.questListDock(2 + 2 * Kit:OuterRailOutset())
	end
	skin:Show()
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	M:RefreshFollowers()
	SkinList()
	SkinExistingPins()
	RefreshPins()
	InkQuestListWindow()
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	StopWaiting()
	skin:Hide()
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	Kit:UnfitPortrait(Portrait())
	RefreshPins()
	if skin.questListDock then
		skin.questListDock(2)
	end
	-- the quest log and the quest list in the game's colours again
	InkList()
	if MelloUI.QuestInk then
		MelloUI.QuestInk.onParchment = false
	end
	local ql = ns.QuestList
	local frame = ql and ql.Panel and ql.Panel.frame
	for _, b in ipairs(frame and frame.filters or {}) do
		b.melloKitPlate = nil
	end
	if ql and ql.Panel and ql.Panel.Update and frame then
		ql.Panel:Update()
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
	Perf.HookScript(WorldMapFrame, "OnShow", function()
		Sync()
		M:RefreshFollowers()
	end)
	Perf.HookScript(QuestMapFrame, "OnShow", function()
		M:RefreshFollowers()
		SkinList()
	end)
	if QuestLogQuests_Update then
		hooksecurefunc("QuestLogQuests_Update", function()
			if active then
				SkinList()
			end
		end)
	end
	-- rows waiting out of view come into it (Rows out of view)
	local sf = QuestScrollFrame
	if sf and sf.HookScript then
		Perf.HookScript(sf, "OnVerticalScroll", DressShown)
		Perf.HookScript(sf, "OnSizeChanged", DressShown)
		Perf.HookScript(sf, "OnShow", DressShown)
	end
	-- MelloUI's quest list window is created on demand
	if ns.QuestList and ns.QuestList.Panel and ns.QuestList.Panel.Create then
		hooksecurefunc(ns.QuestList.Panel, "Create", function()
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
