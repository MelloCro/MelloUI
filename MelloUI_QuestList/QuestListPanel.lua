--------------------------------------------------------------------------------
-- MelloUI - Quest List: the page
--
-- The list as a page of the world map's quest log column, switched with the
-- log by a button on the column's top row. Shares its data and helpers with
-- QuestList.lua through ns.QuestList (QL).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
-- frames made in a game window: Core's maker, so the game's gamepad
-- navigation never walks an open window for each one (MelloUI.Safe.CreateFrame)
local CreateFrame = MelloUI.Safe.CreateFrame
local Perf = MelloUI.Perf:Scope("MelloUI_QuestList (QuestListPanel)")
local C_Timer = Perf.C_Timer
local QL = ns.QuestList
local M = QL.M

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------

QL.Panel = {}
-- The rows, headers, search box and scroll bar are the quest log's (user,
-- 2026-09-27: the two lists "look like they belong together"): QuestInk's
-- Quest rows, the one row both lists share -- its numbers (QI.ROW), fonts,
-- spacing, columns, hover band and the Classic / Forever stamp
local QI = MelloUI.QuestInk
local ROW = QI.ROW
local bandOf = QI.bandOf   -- [row] = its hover band (QI.RowBand)
local LEVEL_SHORTCUT = 4   -- the gear menu's level check: hide quests more than 4 (so 5 or more) levels above
local PIN_SIZE = 14        -- the map pin on the pinned quest's icon
-- (0.19.9) a group's Done section's header; the header's progress bar's texture
local DONE_SECTION = "Done (%d)"
QL.doneOpen = QL.doneOpen or {}   -- (QuestList.lua's; here too for a panel loaded on its own)
local FLAT = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Flat"
-- a quest row's height: the log's spacing round its two fonts as the list
-- was last laid (Update), the list view's extent and each row's own height
local rowHeight = QI.RowHeight(12, 12)
-- the groups the list shows, in the group dropdown's order (the module's
-- Show Quests For setting, db.filter)
local FILTERS = {
	{ key = "zone", label = "Current zone" }, { key = "continent", label = "Current continent" }, { key = "all", label = "All quests" },
	{ key = "class", label = "Class quests" }, { key = "dungeons", label = "Dungeons" }, { key = "raids", label = "Raids" },
	{ key = "attunements", label = "Attunements" }, { key = "events", label = "Events" },
}

local function HeaderClick(self)
	local entry = self.entry
	if entry and entry.header then
		if entry.sub then
			-- (0.19.9) a group's Done section: shut by default, opened here
			QL.doneOpen[entry.parent] = not QL.doneOpen[entry.parent] or nil
			MelloUI:PlayUISound(QL.doneOpen[entry.parent] and "option_on" or "option_off")
		else
			QL.collapsed[self.entry.key] = not QL.collapsed[self.entry.key] or nil
			MelloUI:PlayUISound(QL.collapsed[self.entry.key] and "option_off" or "option_on")
		end
		QL.Panel:Update()
	end
end

local function RowClick(self)
	if not (self.entry and self.entry.row) then
		return
	end
	if IsAltKeyDown() then
		QL.ToggleHidden(self.entry.row)   -- (0.19.5: hidden for this character, or shown again)
		return
	end
	if QL.trackedQuestID == self.entry.row[QL.F_ID] then
		QL.ClearWaypoint()
		MelloUI:PlayUISound("waypoint_clear")
	else
		-- (through Route its notice chimes instead: one sound, not two)
		local set, chimed = QL.SetWaypoint(self.entry.row, self.entry.ready)
		if set and not chimed then
			MelloUI:PlayUISound("waypoint_set")
		end
	end
	QL.Panel:Update()
	if QL.RefreshPins then
		QL.RefreshPins()
	end
end

-- The quest's icon in colour at the tooltip's top right (user, 2026-09-23):
-- the dungeon or raid door for an instance quest, so the two tell apart at a
-- glance, else what it starts from ("!", swords, chest). Our own frame on the
-- tooltip, hidden again whenever the tooltip is cleared or hidden.
local TIP_ICON_SIZE = 52
local tipIcon

local function HideTipIcon()
	if tipIcon and tipIcon:IsShown() then
		tipIcon:Hide()
		if GameTooltip.SetPadding then
			GameTooltip:SetPadding(0, 0)
		end
	end
end

local function ShowTipIcon(row)
	if not tipIcon then
		tipIcon = CreateFrame("Frame", nil, GameTooltip)
		tipIcon:SetSize(TIP_ICON_SIZE, TIP_ICON_SIZE)
		tipIcon:SetPoint("TOPRIGHT", -7, -7)
		tipIcon.tex = tipIcon:CreateTexture(nil, "ARTWORK")
		tipIcon.tex:SetAllPoints()
		tipIcon:Hide()
		Perf.HookScript(GameTooltip, "OnHide", HideTipIcon)
		Perf.HookScript(GameTooltip, "OnTooltipCleared", HideTipIcon)
	end
	local dungeon = row[QL.F_DUNGEON]
	local key = (dungeon ~= 0 and QL.Data().dungeons[dungeon]) and (QL.IsRaid(dungeon) and "raid" or "dungeon")
		or QL.StarterKind(row)
	if not (key and QL.SetStarterIcon(tipIcon.tex, key)) then
		tipIcon.tex:SetAtlas("QuestNormal")
	end
	tipIcon.tex:SetDesaturated(false)
	tipIcon:Show()
	if GameTooltip.SetPadding then
		GameTooltip:SetPadding(TIP_ICON_SIZE + 4, 0)   -- keep the lines clear of it
	end
end

local function RowEnter(self)
	local e = self.entry
	if not e or not e.row then return end
	local row = e.row
	-- (the lines' colours by name, QL.TipLine: the palette's, or the Quest
	-- List's fixed meaning colours; the title in the quest's difficulty
	-- colour, as the quest log shows it)
	local tip, Line = GameTooltip, QL.TipLine
	tip:SetOwner(self, "ANCHOR_LEFT")
	local r, g, b = QL.DifficultyColor(row[QL.F_LEVEL])
	tip:SetText(row[QL.F_TITLE], r, g, b)
	Line(tip, string.format("Level %d, requires level %d", row[QL.F_LEVEL], row[QL.F_REQ]), "text")
	if row[QL.F_DUNGEON] ~= 0 and QL.Data().dungeons[row[QL.F_DUNGEON]] then
		local what = QL.IsRaid(row[QL.F_DUNGEON]) and "Raid quest: " or "Dungeon quest: "
		Line(tip, what .. QL.Data().dungeons[row[QL.F_DUNGEON]], "selectedTrim")
	end
	if row[QL.F_CHAIN] ~= 0 and QL.Data().chains[row[QL.F_CHAIN]] then
		local step, total, nextRow = QL.ChainInfo(row)
		Line(tip, string.format("Step %d of %d in the chain: %s", step, total, QL.Data().chains[row[QL.F_CHAIN]]), "selectedTrim")
		if nextRow then
			Line(tip, "Next: " .. nextRow[QL.F_TITLE], "text")
		end
	end
	if row[QL.F_GIVER] ~= "" then
		local giverZone = QL.Data().zones[QL.ZoneOf(row)]
		local instance = QL.InstanceStart(row)
		if instance then
			local kind = QL.IsRaid(instance) and "raid" or "dungeon"
			local name = QL.Data().dungeons[instance]
			if QL.IsItemStart(row) then
				Line(tip, string.format("Begins with the item %s, which drops inside the %s %s", row[QL.F_GIVER], kind, name), "text", true)
			else
				Line(tip, string.format("Begins at %s inside the %s %s", row[QL.F_GIVER], kind, name), "text", true)
			end
		elseif QL.IsItemStart(row) then
			local how = row[QL.F_KIND] == QL.KIND_PICKUP and ", picked up in " or ", dropped by creatures in "
			Line(tip, "Begins with the item " .. row[QL.F_GIVER] .. (giverZone and (how .. giverZone) or ""), "text")
		else
			Line(tip, "From " .. row[QL.F_GIVER] .. (giverZone and (" in " .. giverZone) or ""), "text")
		end
		local _, gx, gy = QL.GiverPoint(row)
		if gx then
			Line(tip, string.format("   at %.1f, %.1f", gx * 100, gy * 100), "text")
		end
	end
	if (row[QL.F_ENDER] or "") ~= "" then
		if QL.SameEnder(row) then
			Line(tip, "Turn in to the same NPC", "text")
		else
			local endZone = QL.EnderZoneName(row)
			Line(tip, "Turn in to " .. row[QL.F_ENDER] .. (endZone and (" in " .. endZone) or ""), "text")
			local _, ex, ey = QL.EndPoint(row)
			if ex then
				Line(tip, string.format("   at %.1f, %.1f", ex * 100, ey * 100), "text")
			end
		end
	end
	if e.completed then
		Line(tip, "Completed", "text")
	elseif e.onQuest and e.ready then
		Line(tip, "In your quest log, ready to turn in", "questGold")
	elseif e.onQuest then
		Line(tip, "In your quest log, objectives not done", "text")
	elseif e.available then
		Line(tip, "Available to pick up", "questGold")
	elseif e.unmet then
		Line(tip, QL.UnmetText(QL.Unmet(row)) or "Not offered yet", "text", true)
		if row[QL.F_REQ] > (QL.Plain(UnitLevel("player")) or 60) then
			Line(tip, string.format("Needs level %d", row[QL.F_REQ]), "text")
		end
	else
		Line(tip, string.format("Needs level %d", row[QL.F_REQ]), "text")
	end
	if row[QL.F_EVENT] ~= 0 and not (e.completed or e.onQuest) then
		local event = QL.Data().events[row[QL.F_EVENT]]
		Line(tip, "Only while " .. (event or "its event") .. " runs", "text")
	end
	-- (0.19.9) your other characters: done it, or have it in their log (QL.Record)
	QL.RecordLines(tip, row[QL.F_ID])
	if QL.trackedQuestID == row[QL.F_ID] then
		Line(tip, "Map pin set on this quest giver. Click to remove it.", "pinHint")
	elseif e.ready and QL.EndPoint(row) then
		Line(tip, "Click to place a map pin on the turn-in NPC.", "pinHint")
	elseif select(2, QL.GiverPoint(row)) then
		local target = row[QL.F_KIND] == QL.KIND_DROP and "where the item drops most"
			or row[QL.F_KIND] == QL.KIND_PICKUP and "where the item is picked up" or "on the quest giver"
		Line(tip, "Click to place a map pin " .. target .. ".", "pinHint")
	elseif QL.InstanceStart(row) and QL.EntrancePoint(QL.InstanceStart(row)) then
		Line(tip, string.format("Click to route to the %s entrance.", QL.IsRaid(QL.InstanceStart(row)) and "raid" or "dungeon"), "pinHint")
	else
		Line(tip, "Location not known yet.", "text")
	end
	if e.hidden then
		Line(tip, "Hidden for this character. Alt-click to show it again.", "pinHint")
	elseif not (e.completed or e.onQuest) then
		Line(tip, "Alt-click to hide it from the map and the list (this character).", "pinHint")
	end
	ShowTipIcon(row)
	tip:Show()
end

local function Leave()
	GameTooltip:Hide()
end

-- The pool's buttons serve as headers and as rows. Their scripts are set
-- once, when a button is first set up (EnsureWidgets), and look at what it
-- shows now (audit, 2026-09-24, rank 18: each Init set them again, which
-- dropped every hook on the button, and the quest log's dresser hooked them
-- again after every Init). A dresser of the rows (QuestLogPanel, the kit) is
-- told of the hover instead: QL.Panel.OnRowHover(button, over), for headers
-- and rows alike, after the panel's own handling; nil while none listens.
local function EntryClick(self)
	local e = self.entry
	if e and e.header then
		HeaderClick(self)
	else
		RowClick(self)
	end
end

local function EntryEnter(self)
	local e = self.entry
	if e and e.row then
		RowEnter(self)
		-- the hover band UNDER the text (QI.RowBand), as the quest log's
		if bandOf[self] then
			bandOf[self]:Show()
		end
	end
	local hover = QL.Panel.OnRowHover
	if hover then
		hover(self, true)
	end
end

local function EntryLeave(self)
	local e = self.entry
	if e and e.row then
		Leave()
	end
	if bandOf[self] then
		bandOf[self]:Hide()
	end
	local hover = QL.Panel.OnRowHover
	if hover then
		hover(self, false)
	end
end

-- A button's art for what it shows (a header's plate and its lit copy; a
-- row has none: its hover is a band under its text, QI.RowBand): set when
-- it turns from one to the other and when the list is laid out afresh
-- (Update) -- not on every Init: a scroll inits the rows coming into view
-- with the art they already have (audit, 2026-09-24, rank 18). A layout
-- sets it again as before (a highlight the quest log's kit let go of comes
-- back at full alpha; the next layout puts it back).
local artLaid = 1   -- counts the layouts (Update)
local function NewArt(button, kind)
	if button.artKind == kind and button.artLaid == artLaid then
		return false
	end
	button.artKind, button.artLaid = kind, artLaid
	return true
end

-- One button pool serves headers and rows: its widgets and scripts are made
-- once (EnsureWidgets), its art when it turns from header to row or back and
-- on a fresh layout (NewArt), and everything else on each Init.
-- The quest log's look (user, 2026-09-23: "why is there a difference in
-- text between the Default Quest log, and the MelloUI Quest Module"; again
-- 2026-09-27): a header and a row are laid as the log lays its own (QuestInk's
-- Quest rows): a header by QI.RowHeader, a row's title and the line under it
-- in the log's two fonts at their own sizes as the Fonts module sets them
-- (QI.RowFonts, on every row, so a Fonts change reaches it), 8 under the
-- row's top and 3 apart, the icon, pips and stamp in their columns.
local function EnsureWidgets(button)
	if button.title then
		return
	end
	-- a header's label, its count and its +/- (placed by QI.RowHeader)
	button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	if Game15Font_Shadow then
		button.label:SetFontObject(Game15Font_Shadow)
	end
	button.label:SetJustifyH("LEFT")
	button.label:SetWordWrap(false)
	button.count = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.count:SetJustifyH("RIGHT")
	button.plus = button:CreateTexture(nil, "OVERLAY")
	-- where a header's plate lies (and its highlight, the kit's plate), as far
	-- right of the rows' left as the log's: a region, never drawn
	button.plateArea = button:CreateTexture(nil, "BACKGROUND")
	button.plateArea:Hide()
	-- (0.19.9) a header's progress, done of total: a thin bar along its plate's foot
	local bar = CreateFrame("StatusBar", nil, button)
	bar:SetStatusBarTexture(FLAT)
	bar:SetHeight(3)
	bar:SetPoint("BOTTOMLEFT", button.plateArea, "BOTTOMLEFT", 6, 2)
	bar:SetPoint("BOTTOMRIGHT", button.plateArea, "BOTTOMRIGHT", -6, 2)
	bar.track = bar:CreateTexture(nil, "BACKGROUND")
	bar.track:SetAllPoints(bar)
	bar.track:SetTexture(FLAT)
	MelloUI.Widgets.Paint(bar.track, "border", "vertex", 0.6)
	local fill = bar:GetStatusBarTexture()
	if fill then
		MelloUI.Widgets.Paint(fill, "selectedTrim", "vertex", 0.95)
	end
	bar:Hide()
	button.progress = bar
	-- a row's icon (placed on the title's line as the row is laid), its title
	-- and the line under it (their right ends by the columns, InitRow)
	button.check = button:CreateTexture(nil, "ARTWORK")
	button.check:SetSize(ROW.iconSize, ROW.iconSize)
	button.title = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	button.title:SetPoint("TOPLEFT", ROW.titleX, -ROW.top)
	button.title:SetJustifyH("LEFT")
	button.title:SetWordWrap(false)
	button.where = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.where:SetPoint("TOPLEFT", button.title, "BOTTOMLEFT", 0, -ROW.gap)
	button.where:SetJustifyH("LEFT")
	button.where:SetWordWrap(false)
	-- the right slot, at the row's right edge: a region the pips and the
	-- lines are laid by, never drawn (the Classic / Forever stamp that stood
	-- in it went: the user, 2026-10-09)
	button.slot = button:CreateTexture(nil, "BACKGROUND")
	button.slot:Hide()
	-- the map pin on the pinned quest: on its icon's corner, as the log marks
	-- the quest it follows on its POI button (the columns never move for it)
	button.pin = button:CreateTexture(nil, "OVERLAY", nil, 1)
	button.pin:SetSize(PIN_SIZE, PIN_SIZE)
	button.pin:SetPoint("CENTER", button.check, "BOTTOMRIGHT", -3, 3)
	-- The map's own pin art, not the small chat icon version.
	local pinned = false
	for _, atlas in ipairs({ "Waypoint-MapPin-Minimap-Tracked", "Waypoint-MapPin-Tracked", "Waypoint-MapPin-Untracked" }) do
		if pcall(button.pin.SetAtlas, button.pin, atlas) and button.pin:GetAtlas() then
			pinned = true
			break
		end
	end
	if not pinned then
		button.pin:SetTexture([[Interface\MINIMAP\TRACKING\None]])
	end
	button.pin:Hide()
	-- its scripts, once (EntryClick above)
	Perf.SetScript(button, "OnClick", EntryClick)
	Perf.SetScript(button, "OnEnter", EntryEnter)
	Perf.SetScript(button, "OnLeave", EntryLeave)
end

-- The palette's colours (0.14.0: the palettes). A region painted once by its
-- key goes through Core's W.Paint (MelloUI.Widgets.Paint: the kit's one
-- registry, which paints it again on 'palette'); a string whose colour
-- follows its row (a header's, a quest's) takes the palette as it is when the
-- row is laid, and the list is laid again on a new palette (QL.Panel:Create).
-- A done quest's text (its title and line, a finished count; on the map a
-- finished zone's badge) is the text colour a step down, at DONE_ALPHA: small
-- text is never the muted text (the palette rule), and at 0.75 the text
-- colour still reads at about 5.4 : 1 on the inner panel (Ember).
QL.DONE_ALPHA = 0.75

local function KeyColour(fs, key, alpha)
	local c = MelloUI.Palette[key]
	fs:SetTextColor(c[1], c[2], c[3], alpha or 1)
end

-- A gold pulse over a frame: bright at once, gone within a second. Under
-- Reduce Motion it ends at once: no flash (Anim:PlayGroup; audit, 2026-09-24).
local function Pulse(owner, inset)
	local flash = owner.pulse
	if not flash then
		flash = owner:CreateTexture(nil, "OVERLAY", nil, 7)
		-- the palette's gold, by its key (W.Paint; the pulse stands on its
		-- own: a world without Core's widgets leaves it unpainted)
		local W = MelloUI.Widgets
		if W then
			W.Paint(flash, "selectedTrim", "fill", 1)
		end
		flash:SetBlendMode("ADD")
		flash:SetPoint("TOPLEFT", inset or 0, -(inset or 0))
		flash:SetPoint("BOTTOMRIGHT", -(inset or 0), inset or 0)
		flash:SetAlpha(0)
		flash.anim = flash:CreateAnimationGroup()
		local up = flash.anim:CreateAnimation("Alpha")
		up:SetOrder(1)
		up:SetFromAlpha(0)
		up:SetToAlpha(0.55)
		up:SetDuration(0.12)
		local down = flash.anim:CreateAnimation("Alpha")
		down:SetOrder(2)
		down:SetFromAlpha(0.55)
		down:SetToAlpha(0)
		down:SetDuration(0.9)
		Perf.SetScript(flash.anim, "OnFinished", function() flash:SetAlpha(0) end)
		owner.pulse = flash
	end
	flash.anim:Stop()
	if MelloUI.Anim then
		MelloUI.Anim:PlayGroup(flash.anim)
	else
		flash.anim:Play()
	end
end

local revealKey = nil     -- group header to pulse when it is laid out
local revealUntil = 0

local function InitHeader(button, entry)
	if button.pips then
		button.pips:SetTier(nil)
	end
	EnsureWidgets(button)
	button.entry = entry
	if revealKey == entry.key and GetTime() < revealUntil then
		revealKey = nil
		Pulse(button, 1)
		button:LockHighlight()
		C_Timer.After(1.5, function()
			button:UnlockHighlight()
		end)
	end
	-- the log's section header (QI.RowHeader: its height, its plate's place,
	-- label and +/-), with the list's count
	QI.RowHeader(button, button.label, button.plus, button.count, button.plateArea)
	button.check:Hide()
	button.title:Hide()
	button.where:Hide()
	button.label:Show()
	button.count:Show()
	button.plus:Show()
	button.pin:Hide()
	if bandOf[button] then
		bandOf[button]:Hide()
	end
	if NewArt(button, "header") then
		button:SetNormalAtlas("common-button-list-collapseExpand")
		button:SetHighlightAtlas("common-button-list-collapseExpand", "ADD")
		button:GetHighlightTexture():SetAlpha(0.4)
		-- both on the plate's place (QI.RowHeader)
		local normal, highlight = button:GetNormalTexture(), button:GetHighlightTexture()
		normal:ClearAllPoints()
		normal:SetAllPoints(button.plateArea)
		highlight:ClearAllPoints()
		highlight:SetAllPoints(button.plateArea)
	end
	button.plus:SetAtlas(entry.collapsed and "common-button-list-plus" or "common-button-list-minus", true)
	button.label:SetText(entry.name)
	KeyColour(button.label, "text")
	local bar = button.progress
	if entry.sub then
		-- (0.19.9) a group's Done section: its count in its name, no bar
		button.count:SetText("")
		bar:Hide()
		return
	end
	-- (0.19.9, the user's pick B) done / total, its share and a bar
	local share = entry.total > 0 and entry.done / entry.total or 0
	button.count:SetText(string.format("%d/%d  %d%%", entry.done, entry.total, math.floor(share * 100 + 0.5)))
	KeyColour(button.count, "text", (entry.done == entry.total and entry.total > 0) and QL.DONE_ALPHA or 1)
	bar:SetMinMaxValues(0, math.max(1, entry.total))
	bar:SetValue(entry.done)
	bar:SetShown(entry.total > 0)
end

local function MouseOver(b)
	local ok, over = pcall(b.IsMouseOver, b)
	return ok and over == true
end

local function InitRow(button, entry)
	EnsureWidgets(button)
	button.entry = entry
	button.label:Hide()
	button.count:Hide()
	button.plus:Hide()
	button.progress:Hide()
	button.title:Show()
	button.where:Show()
	if NewArt(button, "row") then
		-- no highlight of its own: its hover is the band under the text
		-- (QI.RowBand), as the quest log's (an additive glow over the text
		-- greyed the ink on parchment -- user, 2026-09-27)
		button:ClearNormalTexture()
		button:ClearHighlightTexture()
	end
	-- the quest log's two fonts and its spacing (the row's height from them,
	-- as the list was laid)
	local titleSize = QI.RowFonts(button.title, button.where)
	button:SetHeight(rowHeight)
	-- the icon in the icon column, on the title's line
	button.check:ClearAllPoints()
	button.check:SetPoint("CENTER", button, "TOPLEFT", ROW.iconX, -(ROW.top + titleSize / 2))
	-- the right slot on the title's line at the row's right edge: the pips
	-- just left of it, level with the gem at the end of the hover plate,
	-- inside its band (user, 2026-09-23 / 2026-09-27); the same column on
	-- every row (user, 2026-09-27: "fixed columns")
	button.slot:SetSize(1, titleSize)
	button.slot:ClearAllPoints()
	button.slot:SetPoint("TOPRIGHT", button, "TOPRIGHT", -ROW.edge, -ROW.top)
	-- the hover band (hidden but on the row under the mouse)
	QI.RowBand(button, titleSize):SetShown(MouseOver(button))
	button.pin:SetShown(QL.trackedQuestID ~= nil and entry.row[QL.F_ID] == QL.trackedQuestID)
	local row = entry.row
	local r, g, b = QL.DifficultyColor(QL.ColourLevel(row))
	-- the game's trivial grey (0.5) reads as near black over the list's
	-- shade (user, 2026-09-22: "why are the quest names so dark"): the
	-- panel lifts it; the colour still says trivial
	if r == g and g == b and r <= 0.5 then
		r, g, b = 0.72, 0.72, 0.72
	end
	-- "[12] Title", as the quest log writes it
	local levelText = row[QL.F_LEVEL] > 0 and string.format("[%d] ", row[QL.F_LEVEL]) or ""
	local stepText = entry.step and string.format("%d. ", entry.step) or ""
	button.title:SetText(stepText .. levelText .. row[QL.F_TITLE])
	-- Icon: tick = done before; yellow ? = in log and finished; grey ? = in log,
	-- not finished; yellow ! = can be picked up; grey ! = not yet (level).
	button.check:Show()
	if entry.completed then
		button.check:SetAtlas("questlog-icon-checkmark-yellow")
		button.check:SetDesaturated(true)
		button.check:SetAlpha(0.7)
		KeyColour(button.title, "text", QL.DONE_ALPHA)   -- done: the text colour a step down
	elseif entry.onQuest then
		button.check:SetAtlas("QuestTurnin")
		button.check:SetDesaturated(not entry.ready)
		button.check:SetAlpha(entry.ready and 1 or 0.6)
		button.title:SetTextColor(r, g, b, 1)   -- (a row laid done before comes back to full)
	else
		-- not taken yet: the "!", or what the quest begins from (swords, chest, instance door)
		local starter = QL.StarterKind(row)
		if not (starter and QL.SetStarterIcon(button.check, starter)) then
			button.check:SetAtlas("QuestNormal")
		end
		button.check:SetDesaturated(not entry.available)
		button.check:SetAlpha(entry.available and 1 or 0.6)
		button.title:SetTextColor(r, g, b, 1)
		if entry.hidden then
			-- (0.19.5: hidden by hand, listed while Show Hidden Quests is on)
			button.title:SetText(button.title:GetText() .. "  (hidden)")
			button.check:SetDesaturated(true)
			button.check:SetAlpha(0.45)
			KeyColour(button.title, "text", QL.DONE_ALPHA)
		end
	end
	local where
	if entry.ready and (row[QL.F_ENDER] or "") ~= "" then
		-- no coordinates on the row (they ran under the Classic / Forever logo);
		-- the tooltip has them
		where = "Turn in: " .. row[QL.F_ENDER]
		if entry.showZone then
			local endZone = QL.EnderZoneName(row) or QL.Data().zones[QL.ZoneOf(row)]
			if endZone then
				where = endZone .. "  -  " .. where
			end
		end
	elseif row[QL.F_GIVER] ~= "" then
		where = QL.GiverLabel(row)
		if QL.InstanceStart(row) then
			where = where .. " - found inside"
		end
		if entry.showZone then
			local giverZone = QL.Data().zones[QL.ZoneOf(row)]
			if giverZone then
				where = giverZone .. "  -  " .. where
			end
		end
	else
		where = entry.showZone and (QL.Data().zones[row[QL.F_ZONE]] or "") or "quest giver unknown"
	end
	-- as a quest log objective line: its small round bullet (QI.RowBullet),
	-- in the text colour; a step down once done
	button.where:SetText(QI.RowBullet(button.where) .. where)
	KeyColour(button.where, "text", entry.completed and QL.DONE_ALPHA or 1)
	-- on the reskin's parchment the difficulty in pips (QuestInk; user,
	-- 2026-09-23); a done quest has none
	local tier = nil
	if QI.onParchment then
		local level = QL.ColourLevel(row)
		if not entry.completed and level > 0 then
			tier = QI.TierForQuest(row[QL.F_ID], level) or QI.TierOfColour(QL.DifficultyColor(level))
		end
	end
	-- the title stops short of the pips' column on a row with pips, else of
	-- the slot, as off parchment (a done quest keeps its room: the columns
	-- stay where they are); the line under it short of the slot (both edges
	-- from the title's own)
	local pipsRoom = tier and (QI.PipsWidth(ROW.pipsSize) + ROW.pipsGap + 4) or 6
	button.title:SetPoint("TOPRIGHT", button.slot, "TOPLEFT", -pipsRoom, 0)
	button.where:SetPoint("TOPRIGHT", button.title, "BOTTOMRIGHT", pipsRoom - 6, -ROW.gap)
	-- on the reskin's parchment: both lines in ink, the pips in their column;
	-- a done quest faded
	if QI.onParchment then
		button.pips = button.pips or QI.Pips(button, ROW.pipsSize)
		QI.RowPips(button.pips, button.slot)
		button.pips:SetTier(tier)
		local faded = entry.completed or tier == 1
		QI.Ink(button.title, faded and "faded" or "title")
		QI.Ink(button.where, faded and "faded" or "text")
	else
		QI.Plain(button.title)
		QI.Plain(button.where)
		if button.pips then
			button.pips:SetTier(nil)
		end
	end
end

--------------------------------------------------------------------------------
-- Rebuilds asked for by events
--
-- QUEST_LOG_UPDATE arrives in bursts (a dozen times on a turn-in) and every
-- keystroke in the search box counts too: fold them into one rebuild, made
-- QUIET seconds after the last of them (MAX_WAIT at most after the first; a
-- keystroke's at most QUIET after the first, so the list follows the typing
-- as it always did).
-- QuestList.lua asks on each of its events: on every spell the player casts
-- (its hearthstone check) and on every QUEST_LOG_UPDATE, which comes for
-- each kill and item towards an objective. Most of those change nothing the
-- list or the map pins show, and a rebuild redrew every pin on the map
-- (/melloperf, 2026-09-24). What both show of the quests is summed up below
-- (in the log, ready, done; the level and the pinned quest): a rebuild asked
-- for by the quest log and the casts alone (heard here too while the panel
-- shows, the same events) lays the list out and redraws the pins only when
-- those sums moved. Any other ask (a zone, a level, a loading screen, a
-- quest handed in, whatever QuestList.lua asks on later) rebuilds both as
-- before. The search text is the list's alone: the pins are not redrawn
-- for it.
--------------------------------------------------------------------------------

local QUIET, MAX_WAIT = 0.15, 0.5
local updatePending = false
local firstAsked, lastAsked = 0, 0
local asks = 0           -- rebuilds asked for since the last one
local logAsks = 0        -- of them, by QUEST_LOG_UPDATE
local casts = 0          -- of them, by the player's casts
local searched = false   -- the search text changed since the last rebuild
local handedIn = false   -- a quest handed in since the last rebuild

-- What the list was last laid out from, for the quiet pass (Update below)
local laid = {}

-- The quest log's two fonts (the Fonts module) as the rows take them
-- (QI.RowFonts), as one key: their faces, sizes and outlines -- a change
-- lays the list again (a size changes the rows' height too). Each object's
-- key is made again only when its font changed: a key made on every ask
-- was garbage once the collector ran, and an unchanged rebuild makes none.
local fontKeys = {}   -- [font object] = { path, size, flags, key }
local IsSecret = MelloUI.Safe.IsSecret
local function FontKey(object)
	if object and object.GetFont then
		local ok, path, size, flags = pcall(object.GetFont, object)
		if ok and path and not (IsSecret(path) or IsSecret(size) or IsSecret(flags)) then
			local k = fontKeys[object]
			if not (k and k[1] == path and k[2] == size and k[3] == flags) then
				k = { path, size, flags, string.format("%s|%s|%s", tostring(path), tostring(size), tostring(flags)) }
				fontKeys[object] = k
			end
			return k[4]
		end
	end
	return "?"
end

local function ListFont()
	local title, line = QI.RowFontObjects()
	return string.format("%s/%s", FontKey(title), FontKey(line))
end

-- The quests' sums. The log is walked (how many quests, their ids and their
-- squares, the ready ones' ids: no list made), and every quest seen in it
-- stays watched once it left until its done flag lands (that can come a
-- moment after it left the log) or WATCH_WALKS walks have passed. When the
-- log cannot be read whole (a folded header hides its quests, or no calls
-- for it), the sums are unknown: every ask but a cast rebuilds, as before.
local WATCH_WALKS = 40
local walks = 0
local watched = {}   -- [questID] = the walk it was last seen in the log on
local landed = 0     -- watched quests found done
local sums = {}      -- the sums of the last walk

-- the log read by C_QuestLog, its size and a line's quest id: the Quest
-- List's one log walk (QuestList.lua, 0.14.0)
local LogCalls, LogSize, LogQuestID = QL.LogCalls, QL.LogSize, QL.LogQuestID

-- true when what the list and the pins show of the quests moved since the
-- last walk (the new sums kept for the next); nil when the log could not be
-- read whole and the level and the pinned quest are as they were
local function QuestsMoved()
	walks = walks + 1
	local count, ids, squares, ready = 0, 0, 0, 0
	local modern = LogCalls()
	local lines, quests = LogSize(modern)
	for i = 1, lines or 0 do
		local id = LogQuestID(modern, i)
		if id then
			count, ids, squares = count + 1, ids + id, squares + id * id
			if QL.IsReadyForTurnIn(id) then
				ready = ready + id
			end
			watched[id] = walks
		end
	end
	for id, walk in pairs(watched) do
		if walk ~= walks then
			if QL.IsCompleted(id) then
				watched[id] = nil
				landed = landed + 1
			elseif walks - walk > WATCH_WALKS then
				watched[id] = nil
			end
		end
	end
	local level = QL.Plain(UnitLevel("player"))
	local known = lines ~= nil and count >= quests
	local moved = level ~= sums.level or QL.trackedQuestID ~= sums.tracked
		or (known and (count ~= sums.count or ids ~= sums.ids or squares ~= sums.squares or ready ~= sums.ready
		or landed ~= sums.landed))
	sums.count, sums.ids, sums.squares, sums.ready, sums.landed = count, ids, squares, ready, landed
	sums.level, sums.tracked = level, QL.trackedQuestID
	if not (known or moved) then
		return nil
	end
	return moved
end

local watcher = CreateFrame("Frame")
Perf.SetScript(watcher, "OnEvent", function(_, event, questID)
	if event == "QUEST_TURNED_IN" then
		-- drawn again, and its done flag watched (it may land after this)
		handedIn = true
		questID = QL.Plain(questID)
		if type(questID) == "number" then
			watched[questID] = walks
		end
	elseif event == "QUEST_LOG_UPDATE" then
		logAsks = logAsks + 1
	else
		casts = casts + 1
	end
end)

local function Rebuild()
	local wait = math.min(lastAsked + QUIET, firstAsked + (searched and QUIET or MAX_WAIT)) - GetTime()
	if wait > 0.01 then
		C_Timer.After(wait, Rebuild)
		return
	end
	updatePending = false
	local pins = asks > logAsks + casts or handedIn
	local list = searched
	local logged = logAsks > 0
	asks, logAsks, casts, searched, handedIn = 0, 0, 0, false, false
	-- the map pin removed on the map itself: the row's pin goes too (the
	-- sums hold the pinned quest)
	QL.SyncTracked()
	local moved = QuestsMoved()
	if moved or (moved == nil and logged) then
		pins = true
	end
	if pins or ListFont() ~= laid.font then
		list = true
	end
	if list then
		QL.Panel:Update(true)
	end
	if pins and QL.RefreshPins then
		QL.RefreshPins()
	end
end

local function Ask()
	lastAsked = GetTime()
	if updatePending then
		return
	end
	updatePending = true
	firstAsked = lastAsked
	C_Timer.After(QUIET, Rebuild)
end

-- (0.19.9) the layer over the map is the core's (Core/MapLayer.lua: Route's
-- trails hang in it too, and the Quest List is an addon of its own): the
-- names this list's files use
QL.MapLayer = MelloUI.MapLayer
QL.STRATA_UP = MelloUI.STRATA_UP

--------------------------------------------------------------------------------
-- The page in the quest log's column (user, 2026-10-02: the Quest List as
-- "this huge window next to the World map" went; "the quest list merge with
-- the quest log" -- docs/plans/quest-list-in-log.md). The map's quest column
-- shows the quest log or the Quest List, switched by one button on the
-- column's top row where the game has its count box: "Quest List" over the
-- log, "Quest Log" over the list, the log's count it covers in its tooltip.
-- The list is a page of MelloUI's own in the layer over the map (above), over
-- the column's content, and each of its parts stands where the game's stands,
-- anchored to it: the search box on the game's, the switch on the count box,
-- the menu button on the gear, the page and its border on the log's scroll
-- frame and border, the scroll bar where the log has its own
-- (QI.RowScrollBar). Under the search row: the group dropdown (its text the
-- list's title) with the done count, a divider and the rows -- the log's own
-- rows (QuestInk's QI.ROW). It shows while the module is on, the list is
-- chosen (db.view) and the game shows its quest list: a quest's details (the
-- game hides its list for them) or a map without the quest log hide it, and
-- Back brings it again. While it shows, the game's list is faded (its alpha
-- 0, given back the moment the page goes): no log text through the page while
-- the map fades as the player moves. The game's frames get nothing else from
-- it: no key, no anchor of theirs, no script; post-hooks on their show and
-- hide.
--------------------------------------------------------------------------------

-- the column's frames: the quest log side panel and its list (the scroll
-- frame the search row, the count box, the gear and the border hang in)
local function Column()
	local qm = QuestMapFrame
	local qf = qm and qm.QuestsFrame
	return qm, (qf and qf.ScrollFrame) or QuestScrollFrame
end

-- the game shows its quest list (their own shown flags: the map's show and
-- hide reach the page through the layer)
local function ColumnShown()
	local qm, sf = Column()
	return qm ~= nil and sf ~= nil and qm:IsShown() and sf:IsShown()
end

local faded = false   -- the game's list faded under the page

-- the page, the switch and the fade as the module, the view and the column
-- say; `off`: the module is going off (its flag may not have moved yet)
function QL.Panel:Sync(off)
	local frame = self.frame
	if not frame then
		return
	end
	local column = (not off and M.isEnabled and ColumnShown()) and true or false
	local list = column and M.db.view == "list"
	frame:SetShown(list)
	local switch = frame.switch
	switch:SetShown(column)
	switch:SetText(list and "Quest Log" or "Quest List")
	local _, sf = Column()
	if sf and faded ~= list then
		faded = list
		sf:SetAlpha(list and 0 or 1)
	end
end

-- the column's show and hide (the map opening, a quest's details, Back)
local SyncColumn = Perf.Shared("the quest log column's show and hide (the Quest List's page)", function()
	QL.Panel:Sync()
end, "script")

local SwitchClick = Perf.Shared("OnClick on the Quest List's switch", function()
	M.db.view = M.db.view == "list" and "log" or "list"
	MelloUI:PlayUISound("tab")
	QL.Panel:Sync()
end, "script")

-- the log's count as the game's count box under the switch says it
local function LogCount()
	local fs = _G.QuestLogQuestCount
	local text = fs and fs.GetText and MelloUI.Safe.Text(fs:GetText())
	return (text and text ~= "") and text or nil
end

local SwitchEnter = Perf.Shared("OnEnter on the Quest List's switch", function(self)
	local count = LogCount()
	local more = count and ("\n" .. count) or ""
	if M.db.view == "list" then
		MelloUI.Widgets.ShowTooltip(self, "Quest Log", "Back to the quests you have taken." .. more, nil, "ANCHOR_RIGHT")
	else
		MelloUI.Widgets.ShowTooltip(self, "Quest List", "The quests you can pick up here: who gives them, where, "
			.. "and how many of them you have done." .. more, nil, "ANCHOR_RIGHT")
	end
end, "script")

local SwitchLeave = Perf.Shared("OnLeave on the Quest List's switch", function(self)
	if GameTooltip:GetOwner() == self then
		GameTooltip:Hide()
	end
end, "script")

-- the game's list lies under the page (faded): its wheel stops on the page
local Swallow = Perf.Shared("OnMouseWheel on the Quest List's page", function() end, "script")

-- the gear's menu: what the quests start from (they apply to the map pins
-- too), and the two hides that stood as check boxes beside the side window's
-- Filter button (user, 2026-09-23)
local function MenuSetup(_, root)
	root:CreateTitle("Quests that start from")
	for _, k in ipairs(QL.START_KINDS) do
		root:CreateCheckbox(QL.StarterIconMarkup(k.key, 18) .. " " .. k.label,
			function() return M.db[k.setting] ~= false end,
			function()
				MelloUI:NotifySettingChanged(M.name, k.setting, M.db[k.setting] == false)
			end)
	end
	root:CreateDivider()
	-- the "Hide Quests More Than N Levels Above Me" setting at +4 (the red
	-- ones); off puts it back to no limit, any other value reads as off
	root:CreateCheckbox("Hide quests 5+ levels above me",
		function() return tonumber(M.db.levelAbove) == LEVEL_SHORTCUT end,
		function()
			MelloUI:NotifySettingChanged(M.name, "levelAbove", tonumber(M.db.levelAbove) ~= LEVEL_SHORTCUT and LEVEL_SHORTCUT or 0)
		end)
	root:CreateCheckbox("Hide completed quests",
		function() return M.db.hideCompleted and true or false end,
		function()
			MelloUI:NotifySettingChanged(M.name, "hideCompleted", not M.db.hideCompleted)
		end)
	-- (0.19.5) the quests hidden by hand, listed dimmed to Alt-click back
	root:CreateCheckbox(string.format("Show hidden quests (%d)", QL.HiddenCount()),
		function() return M.db.showHidden and true or false end,
		function()
			MelloUI:NotifySettingChanged(M.name, "showHidden", not M.db.showHidden)
		end)
end

-- the group dropdown's list: the module's Show Quests For
local function GroupSetup(_, root)
	for _, f in ipairs(FILTERS) do
		root:CreateRadio(f.label, function() return M.db.filter == f.key end, function()
			MelloUI:NotifySettingChanged(M.name, "filter", f.key)
		end)
	end
end

function QL.Panel:Create()
	if self.frame then
		return
	end
	local qm, sf = Column()
	if not (qm and sf) then
		return
	end
	local layer = QL.MapLayer()
	local frame = CreateFrame("Frame", "MelloUIQuestListPanel", layer)
	self.frame = frame
	frame:Hide()   -- (Sync shows it)
	local area = qm.ContentsAnchor or qm
	frame:SetPoint("TOPLEFT", area, "TOPLEFT")
	frame:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT")
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	Perf.SetScript(frame, "OnMouseWheel", Swallow)

	-- the list's area: the log's scroll frame, with its border. The page
	-- itself, the divider and the count are the page frame's OWN regions,
	-- under every frame of the page whatever its level (in the game, 2026-10-02:
	-- on a frame at the rows' and the dropdown's level, the kit's parchment,
	-- drawn as a region of that frame, covered the rows and the dropdown's
	-- plate -- "they are there and clickable, just dont see them")
	local list = CreateFrame("Frame", nil, frame)
	list:SetAllPoints(sf)
	frame.list = list
	frame.bg = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	frame.bg:SetAllPoints(sf.Background or list)
	if not pcall(frame.bg.SetAtlas, frame.bg, "QuestLog-main-background") then
		MelloUI.Widgets.Paint(frame.bg, "innerPanel", "fill", 1)
	end
	local okB, border = pcall(CreateFrame, "Frame", nil, list, "QuestLogBorderFrameTemplate")
	frame.border = okB and border or nil

	-- the search row: the box on the game's (typing searches every zone), the
	-- menu on the gear
	local search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	if sf.SearchBox then
		search:SetAllPoints(sf.SearchBox)
	else
		search:SetPoint("BOTTOMLEFT", sf, "TOPLEFT", 6, 7)
		search:SetSize(200, ROW.searchHeight)
	end
	search:SetAutoFocus(false)
	if search.Instructions then
		search.Instructions:SetText("Search quests")
	end
	Perf.HookScript(search, "OnTextChanged", function(_, userInput)
		if userInput then
			searched = true
			Ask()
		end
	end)
	Perf.SetScript(search, "OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
		QL.Panel:Update()
	end)
	frame.search = search
	local okM, menu = pcall(CreateFrame, "DropdownButton", nil, frame, "UIPanelIconDropdownButtonTemplate")
	if not okM then
		menu = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
		menu:SetSize(94, 22)
		if menu.SetDefaultText then
			menu:SetDefaultText("Filter")
		end
	end
	if sf.SettingsDropdown then
		menu:SetPoint("CENTER", sf.SettingsDropdown, "CENTER")
	else
		menu:SetPoint("BOTTOMRIGHT", sf, "TOPRIGHT", 19, 7)
	end
	menu:SetupMenu(MenuSetup)
	frame.menu = menu

	-- the switch on the count box: in the layer, not the page (it shows over
	-- the log too), over the page's border
	local switch = CreateFrame("Button", nil, layer, "UIPanelButtonTemplate")
	local box = _G.QuestLogCount
	if box then
		switch:SetAllPoints(box)
	else
		switch:SetSize(100, 20)
		switch:SetPoint("LEFT", search, "RIGHT", 3, 0)
	end
	local over = frame.border or frame
	switch:SetFrameLevel(over:GetFrameLevel() + 10)
	switch:SetText("Quest List")
	Perf.SetScript(switch, "OnClick", SwitchClick)
	Perf.HookScript(switch, "OnEnter", SwitchEnter)
	Perf.HookScript(switch, "OnLeave", SwitchLeave)
	switch:Hide()
	frame.switch = switch

	-- on the page, under the search row: the group the list shows (its text
	-- the list's title: the zone, "Dungeons", the search) and how many of its
	-- quests are done, then a divider
	frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.count:SetPoint("RIGHT", list, "TOPRIGHT", -10, -21)
	frame.count:SetJustifyH("RIGHT")
	local group = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
	group:SetHeight(22)
	group:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -10)
	group:SetPoint("RIGHT", frame.count, "LEFT", -8, 0)
	group:SetupMenu(GroupSetup)
	frame.group = group
	frame.divider = frame:CreateTexture(nil, "ARTWORK")
	frame.divider:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -36)
	frame.divider:SetPoint("TOPRIGHT", list, "TOPRIGHT", -4, -36)
	frame.divider:SetHeight(8)
	if not pcall(frame.divider.SetAtlas, frame.divider, "QuestLog-frame-devider") then
		MelloUI.Widgets.Paint(frame.divider, "trim", "fill", 0.6)
		frame.divider:SetHeight(1)
	end

	-- the rows (headers and quests: one pool), the scroll bar where the log
	-- has its own
	frame.scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
	frame.scrollBox:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -46)
	frame.scrollBox:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT")
	frame.scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
	QI.RowScrollBar(frame.scrollBar, frame.scrollBox)
	local view = CreateScrollBoxListLinearView()
	-- (a row's height from the log's fonts as they are when the list is laid:
	-- Update)
	view:SetElementExtentCalculator(function(_, entry)
		return entry.header and ROW.headerHeight or rowHeight
	end)
	view:SetElementFactory(function(factory, entry)
		if entry.header then
			factory("Button", InitHeader)
		else
			factory("Button", InitRow)
		end
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(frame.scrollBox, frame.scrollBar, view)
	-- the rows and the dropdown over the list frame and the kit's frames on
	-- the page (its parchment's painted edges), under the border (the
	-- template's level 100) and the switch
	local rowsLevel = frame:GetFrameLevel() + 3
	frame.scrollBox:SetFrameLevel(rowsLevel)
	group:SetFrameLevel(rowsLevel)
	frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	frame.empty:SetPoint("CENTER", frame.scrollBox, "CENTER")
	frame.empty:SetWidth(240)
	frame.empty:Hide()

	-- the quest log's and the player's casts counted while the page shows
	-- (QuestList.lua asks only while the map shows, registered the same way);
	-- laid out afresh each time it shows, the sums taken then (the map draws
	-- its pins afresh on showing too)
	Perf.SetScript(frame, "OnShow", function()
		asks, logAsks, casts, searched, handedIn = 0, 0, 0, false, false
		watcher:RegisterEvent("QUEST_LOG_UPDATE")
		watcher:RegisterEvent("QUEST_TURNED_IN")
		if watcher.RegisterUnitEvent then
			watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		else
			watcher:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
		end
		QuestsMoved()
		QL.Panel:Update()
	end)
	Perf.HookScript(frame, "OnHide", function()
		watcher:UnregisterAllEvents()
		asks, logAsks, casts, searched, handedIn = 0, 0, 0, false, false
	end)
	-- a new palette: the rows laid again in it while the page shows (a hidden
	-- page is laid afresh on its next show). Only a palette TABLE the list
	-- was not laid in: 'palette' goes out for a Kit Colours change too, the
	-- palette unchanged
	MelloUI:On("palette", function()
		if laid.palette ~= MelloUI.Palette then
			QL.Panel:Update()
		end
	end, "Quest List panel")
	-- new fonts (the Fonts module: a face, a size, the outline): the rows laid
	-- again in them while the page shows -- their height comes from the
	-- fonts as the list was laid, and a row a scroll brings into view takes
	-- the fonts as they are now (no quest event need follow a size change)
	MelloUI:On("fonts", function()
		if laid.font ~= ListFont() then
			QL.Panel:Update()
		end
	end, "Quest List panel")

	-- the page follows the column: its show and hide, the map's included
	Perf.HookScript(qm, "OnShow", SyncColumn)
	Perf.HookScript(qm, "OnHide", SyncColumn)
	Perf.HookScript(sf, "OnShow", SyncColumn)
	Perf.HookScript(sf, "OnHide", SyncColumn)
end

function QL.Panel:Apply()
	if not self.frame then
		return
	end
	self:Sync()
	self:Update()
end

-- Turn a flat list of rows into header + row entries.
-- groupOf(row) -> key, name; groups are ordered by the level of their first quest.
local function BuildEntries(rows, groupOf, showZone)
	local db = M.db
	local groups, order = {}, {}
	local done, total = 0, 0
	local level = QL.Plain(UnitLevel("player")) or 60
	for _, row in ipairs(rows) do
		if QL.Eligible(row) and QL.StartShown(row) then
			local completed = QL.IsCompleted(row[QL.F_ID])
			total = total + 1
			if completed then
				done = done + 1
			end
			local key, name, sortLevel = groupOf(row)
			local group = groups[key]
			if not group then
				group = { key = key, name = name, rows = {}, done = 0, total = 0, level = sortLevel or row[QL.F_LEVEL], single = key == "single" }
				groups[key] = group
				order[#order + 1] = group
			end
			group.total = group.total + 1
			if completed then
				group.done = group.done + 1
			end
			if not (completed and db.hideCompleted) then
				local onQuest = not completed and QL.IsOnQuest(row[QL.F_ID])
				-- (what the game asks first -- another quest, a skill, a standing --
				-- keeps a quest from being one to pick up now: QL.Unmet)
				local unmet = not (completed or onQuest) and QL.Unmet(row) or nil
				group.rows[#group.rows + 1] = {
					row = row, completed = completed, onQuest = onQuest, showZone = showZone,
					ready = onQuest and QL.IsReadyForTurnIn(row[QL.F_ID]) or false,
					available = not onQuest and not unmet and row[QL.F_REQ] <= level,
					unmet = unmet,
					hidden = not (completed or onQuest) and QL.IsHidden(row[QL.F_ID]) or nil,
					step = (key:sub(1, 5) == "chain") and QL.chainStep and QL.chainStep[row] or nil,
				}
			end
		end
	end
	table.sort(order, function(a, b)
		if a.level ~= b.level then return a.level < b.level end
		return a.name < b.name
	end)
	-- Chain groups read top to bottom in chain order.
	for _, group in ipairs(order) do
		if group.key:sub(1, 5) == "chain" then
			table.sort(group.rows, function(a, b)
				if (a.step or 0) ~= (b.step or 0) then return (a.step or 0) < (b.step or 0) end
				return QL.ByLevel(a.row, b.row)
			end)
		end
	end
	local entries = {}
	for _, group in ipairs(order) do
		if #group.rows > 0 or not db.hideCompleted then
			entries[#entries + 1] = { header = true, key = group.key, name = group.name, done = group.done, total = group.total,
				collapsed = QL.collapsed[group.key] and true or false }
			if not QL.collapsed[group.key] then
				-- (0.19.9, the user's pick B) the quests left first; the done ones
				-- in a Done section under them, shut until opened (Hide
				-- Completed leaves them out above: no section)
				local nDone = 0
				for _, e in ipairs(group.rows) do
					if e.completed then
						nDone = nDone + 1
					else
						entries[#entries + 1] = e
					end
				end
				if nDone > 0 then
					local open = QL.doneOpen[group.key] and true or false
					entries[#entries + 1] = { header = true, sub = true, key = group.key .. "#done", parent = group.key,
						name = string.format(DONE_SECTION, nDone), done = nDone, total = nDone, collapsed = not open }
					if open then
						for _, e in ipairs(group.rows) do
							if e.completed then
								entries[#entries + 1] = e
							end
						end
					end
				end
			end
		end
	end
	return entries, done, total
end

function QL.Panel:Schedule()
	asks = asks + 1
	Ask()
end

-- Two lists hold the same when every header and row says the same (the
-- rows' quest data are shared tables, so the same quest is the same table)
local function SameEntries(a, b)
	if not (a and b) or #a ~= #b then
		return false
	end
	for i = 1, #a do
		local x, y = a[i], b[i]
		if x.header then
			if not (y.header and x.key == y.key and x.name == y.name and x.done == y.done and x.total == y.total
				and x.collapsed == y.collapsed) then
				return false
			end
		elseif y.header or x.row ~= y.row or x.completed ~= y.completed or x.onQuest ~= y.onQuest or x.ready ~= y.ready
			or x.available ~= y.available or x.unmet ~= y.unmet or x.showZone ~= y.showZone or x.step ~= y.step
			or x.hidden ~= y.hidden then
			return false
		end
	end
	return true
end

local inkLabels = nil   -- the page's own texts and their inks, listed once

-- `quiet` (a rebuild an event or a map change asked for): the list is laid
-- out again only when what it would show differs from what it shows (every
-- row's button set up anew and the kit's rows skinned again, for the same
-- list, was the bulk of a rebuild's time -- /melloperf, 2026-09-24). A
-- click, a filter, a setting or showing the panel always lay it out.
function QL.Panel:Update(quiet)
	local frame = self.frame
	if not frame or not QL.byZone then
		return
	end
	-- laid while the page shows (the log shown instead: laid afresh as the
	-- page shows)
	if not frame:IsShown() then
		return
	end
	local db, data = M.db, QL.Data()
	QL.SyncTracked()

	local rows, title, groupOf, showZone
	local term = frame.search and frame.search:GetText() or ""
	term = term:lower():gsub("^%s+", ""):gsub("%s+$", "")

	local function ByZoneGroup(row)
		local zone = QL.ZoneOf(row)
		return "zone" .. zone, data.zones[zone] or "Unknown zone"
	end
	local function DungeonLevel(id)
		-- Instances Wowhead has no level for (Forever's new ones) sort by
		-- their lowest quest instead.
		local lv = data.dungeonLevel and data.dungeonLevel[id]
		return (lv and lv[1] > 0) and lv[1] or nil
	end
	local function DungeonName(id)
		local name = data.dungeons[id] or "Dungeon"
		local lv = data.dungeonLevel and data.dungeonLevel[id]
		if lv and lv[1] > 0 then
			-- the level range in the header's own colour (a grey code of its
			-- own before 0.14.0: small text is never the muted text)
			name = string.format("%s (%d-%d)", name, lv[1], lv[2] > 0 and lv[2] or lv[1])
		end
		return name
	end
	local function ByChainGroup(row)
		if row[QL.F_DUNGEON] ~= 0 and data.dungeons[row[QL.F_DUNGEON]] then
			return "dungeon" .. row[QL.F_DUNGEON], DungeonName(row[QL.F_DUNGEON]), DungeonLevel(row[QL.F_DUNGEON])
		end
		if row[QL.F_CHAIN] ~= 0 and data.chains[row[QL.F_CHAIN]] then
			return "chain" .. row[QL.F_CHAIN], data.chains[row[QL.F_CHAIN]]
		end
		return "single", "Single quests"
	end
	-- allRows is already sorted by level; filtering keeps that order.
	local function AllRows(include)
		if not include then
			return QL.allRows
		end
		local list = {}
		for _, row in ipairs(QL.allRows) do
			if include(row) then list[#list + 1] = row end
		end
		return list
	end

	if term ~= "" then
		local function Matches(row)
			local text = QL.searchText[row]
			return text ~= nil and text:find(term, 1, true) ~= nil
		end
		rows, title, showZone = AllRows(Matches), "Search: " .. term, false
		for _, row in ipairs(QL.eventRows) do
			if Matches(row) then rows[#rows + 1] = row end
		end
		table.sort(rows, QL.ByLevel)
		groupOf = function(row)
			if row[QL.F_EVENT] ~= 0 then
				return "event" .. row[QL.F_EVENT], data.events[row[QL.F_EVENT]] or "Event"
			end
			return ByZoneGroup(row)
		end
	elseif db.filter == "all" then
		rows, title, showZone, groupOf = AllRows(), "All quests", false, ByZoneGroup
	elseif db.filter == "continent" then
		local c, cname = QL.CurrentContinent()
		title = cname or "Unknown continent"
		rows, showZone, groupOf = AllRows(function(row) return c ~= nil and (data.zoneContinent[QL.ZoneOf(row)] == c) end), false, ByZoneGroup
	elseif db.filter == "class" then
		title, showZone = "Class quests", true
		rows = AllRows(function(row) return row[QL.F_CLASS] ~= 0 end)
		groupOf = function(row)
			if row[QL.F_CHAIN] ~= 0 and data.chains[row[QL.F_CHAIN]] then
				return "chain" .. row[QL.F_CHAIN], data.chains[row[QL.F_CHAIN]]
			end
			return ByZoneGroup(row)
		end
	elseif db.filter == "dungeons" or db.filter == "raids" then
		local wantRaid = db.filter == "raids"
		title, showZone = wantRaid and "Raids" or "Dungeons", true
		rows = AllRows(function(row)
			return row[QL.F_DUNGEON] ~= 0 and ((data.raids[row[QL.F_DUNGEON]] == true) == wantRaid)
		end)
		groupOf = function(row)
			return "dungeon" .. row[QL.F_DUNGEON], DungeonName(row[QL.F_DUNGEON]), DungeonLevel(row[QL.F_DUNGEON])
		end
	elseif db.filter == "attunements" then
		title, showZone = "Attunements", true
		rows = AllRows(function(row) return row[QL.F_ATTUNE] == 1 end)
		groupOf = function(row)
			if row[QL.F_CHAIN] ~= 0 and data.chains[row[QL.F_CHAIN]] then
				return "chain" .. row[QL.F_CHAIN], data.chains[row[QL.F_CHAIN]]
			end
			return "single", row[QL.F_TITLE]
		end
	elseif db.filter == "events" then
		rows, title, showZone = QL.eventRows, "Holidays and world events", false
		groupOf = function(row)
			return "event" .. row[QL.F_EVENT], data.events[row[QL.F_EVENT]] or "Event"
		end
	else
		local areaID, name = QL.CurrentAreaID()
		title = name or "Unknown zone"
		rows, showZone, groupOf = areaID and QL.byZone[areaID] or {}, false, ByChainGroup
	end

	local entries, done, total = BuildEntries(rows, groupOf, showZone)
	-- besides the entries, a row's look follows the tracked quest (its pin),
	-- the level (the difficulty colours), the parchment (the ink and the
	-- stamp) and the quest log's fonts (the Fonts module)
	local level = QL.Plain(UnitLevel("player"))
	local paper = QI.onParchment and true or false
	local font = ListFont()
	-- and the palette (the text colours: a pass after a switch lays it again)
	local palette = MelloUI.Palette
	if quiet and not (revealKey and GetTime() < revealUntil) and laid.title == title and laid.done == done
		and laid.total == total and laid.tracked == QL.trackedQuestID and laid.level == level and laid.paper == paper
		and laid.font == font and laid.palette == palette and SameEntries(laid.entries, entries) then
		return
	end
	laid.entries, laid.title, laid.done, laid.total, laid.tracked = entries, title, done, total, QL.trackedQuestID
	laid.level, laid.paper, laid.font, laid.palette = level, paper, font, palette
	rowHeight = QI.RowHeight(QI.RowFonts())
	-- the title on the group dropdown (kept over its selection's label)
	if frame.group.OverrideText then
		frame.group:OverrideText(title)
	end
	frame.count:SetText(string.format("%d of %d done", done, total))
	artLaid = artLaid + 1   -- (each row's art set again as it is laid: NewArt)
	frame.scrollBox:SetDataProvider(CreateDataProvider(entries), ScrollBoxConstants.RetainScrollPosition)
	if #entries == 0 then
		local filtered = false
		for _, k in ipairs(QL.START_KINDS) do
			filtered = filtered or db[k.setting] == false
		end
		frame.empty:SetText(term ~= "" and "Nothing found." or (total == 0 and (filtered and "No quests match the filter."
			or "No quests known for this zone.") or "All completed."))
		frame.empty:Show()
	else
		frame.empty:Hide()
	end
	-- the page's own texts in ink on the parchment too (user, 2026-09-23: the
	-- count, the empty list's line)
	if not inkLabels then
		inkLabels = { { frame.count, "text" }, { frame.empty, "text" } }
	end
	for _, l in ipairs(inkLabels) do
		if l[1] then
			if QI.onParchment then
				QI.Ink(l[1], l[2])
			else
				QI.Plain(l[1], true)
			end
		end
	end
end

-- Show one group (a dungeon, a raid, a chain) after a click elsewhere: the
-- column on the list, the list switched, the other groups folded, scrolled to
-- it, and the title and the group's header pulsed so the change is seen.
function QL.Panel:Reveal(key, filter)
	local frame = self.frame
	if M.db.view ~= "list" then
		M.db.view = "list"
		self:Sync()
	end
	if filter and M.db.filter ~= filter then
		M.db.filter = filter
		MelloUI:NotifySettingChanged(M.name, "filter", filter)
	end
	revealKey, revealUntil = key, GetTime() + 2
	self:Update()
	if not (frame and frame:IsShown()) then
		return false
	end
	local provider = frame.scrollBox.GetDataProvider and frame.scrollBox:GetDataProvider()
	local index = nil
	if provider and provider.Enumerate then
		for i, entry in provider:Enumerate() do
			if entry.header and entry.key == key then
				index = i
				break
			end
		end
	end
	if index and frame.scrollBox.ScrollToElementDataIndex then
		pcall(frame.scrollBox.ScrollToElementDataIndex, frame.scrollBox, index,
			ScrollBoxConstants and ScrollBoxConstants.AlignBegin or 0, 0)
	end
	-- the title row (the group dropdown and the count), not the whole page
	if not frame.titleArea then
		frame.titleArea = CreateFrame("Frame", nil, frame)
		frame.titleArea:SetPoint("TOPLEFT", frame.group, "TOPLEFT", -4, 3)
		frame.titleArea:SetPoint("BOTTOM", frame.group, "BOTTOM", 0, -3)
		frame.titleArea:SetPoint("RIGHT", frame.list, "RIGHT", -4, 0)
	end
	Pulse(frame.titleArea, 0)
	return index ~= nil
end

MelloUI:Profile("QuestList", "panel rebuild", QL.Panel.Update)
