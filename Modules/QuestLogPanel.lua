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
		local rep = Replace(button.HighlightTexture, { as = "questlog-quest-glow-yellow", rect = button.HighlightTexture })
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

local function SkinList()
	local sf = QuestScrollFrame
	if not (sf and sf.titleFramePool) then
		return
	end
	for title in sf.titleFramePool:EnumerateActive() do
		SkinTitle(title)
	end
	for header in sf.headerFramePool:EnumerateActive() do
		SkinHeader(header)
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
local function SkinQuestListEntry(button)
	-- a header or a row: told apart after its Init by the normal texture
	local normal = button:GetNormalTexture()
	local highlight = button:GetHighlightTexture()
	local isHeader = normal and Kit:ArtKey(normal) == "common-button-list-collapseExpand"
	if isHeader and not button.melloHeader then
		button.melloHeader = Replace(normal, { as = "common-button-list-collapseExpand", rect = button, button = button,
			alsoFade = highlight and { highlight } or nil }) or false
	end
	if not button.melloRow then
		-- a row's hover: the plate's hover look, shown while the mouse is on it
		button.melloRow = Replace(highlight, { as = "questlog-quest-glow-yellow", rect = button }) or false
		if button.melloRow then
			button.melloRow:SetShown(false)
		end
	end
	if button.melloRow then
		-- the panel's Init SETS the OnEnter / OnLeave scripts on every refresh,
		-- which drops earlier hooks: hook again after each Init
		button:HookScript("OnEnter", function(b)
			if active and b.melloRow and not b.melloIsHeader then
				b.melloRow:SetShown(true)
			end
		end)
		button:HookScript("OnLeave", function(b)
			if b.melloRow then
				b.melloRow:SetShown(false)
			end
		end)
	end
	if button.pin then
		SkinPinTexture(button.pin)      -- the tracked quest's pin: the gem (I7)
	end
	button.melloIsHeader = isHeader
	if button.melloHeader then
		button.melloHeader:SetShown(isHeader and true or false)
	end
	if button.melloRow and isHeader then
		button.melloRow:SetShown(false)
	end
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
	Kit:HookScrollBoxRows(frame.scrollBox, SkinQuestListEntry, function() return active end, true)
	Kit:SkinScrollBarsIn(frame, Replace)
	-- the shade under the list's text, as the tracker has it (user, 2026-09-22)
	if not skin.listShade then
		skin.listShade = Kit:CentreShade(frame, frame.scrollBox, { inset = 0 })
		skin.listShade:SetShown(active)
	end
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
			-- the shade under the quest text, as the tracker has it (user, 2026-09-22)
			if not skin.questShade then
				skin.questShade = Kit:CentreShade(sf, sf, { inset = 6 })
				skin.questShade:SetShown(active)
			end
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
	for _, key in ipairs({ "questShade", "listShade" }) do
		if skin[key] then
			skin[key]:Show()
		end
	end
	M:RefreshFollowers()
	SkinList()
	SkinExistingPins()
	RefreshPins()
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
	for _, key in ipairs({ "questShade", "listShade" }) do
		if skin[key] then
			skin[key]:Hide()
		end
	end
	Kit:UnfitPortrait(Portrait())
	RefreshPins()
	if skin.questListDock then
		skin.questListDock(2)
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
	WorldMapFrame:HookScript("OnShow", function()
		Sync()
		M:RefreshFollowers()
	end)
	QuestMapFrame:HookScript("OnShow", function()
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
eventFrame:SetScript("OnEvent", function()
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
