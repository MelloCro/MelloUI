--------------------------------------------------------------------------------
-- MelloUI - Quest List: the panel
--
-- The list attached to the right of the world map. Shares its data and helpers
-- with QuestList.lua through ns.QuestList (QL).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
-- frames made in a game window: Core's maker, so the game's gamepad
-- navigation never walks an open window for each one (MelloUI.Safe.CreateFrame)
local CreateFrame = MelloUI.Safe.CreateFrame
local Perf = MelloUI.Perf:Scope("QuestListPanel")
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
local LEVEL_SHORTCUT = 4   -- the level check box under the Filter button: hide quests more than 4 (so 5 or more) levels above
local PIN_SIZE = 14        -- the map pin on the pinned quest's icon
-- a quest row's height: the log's spacing round its two fonts as the list
-- was last laid (Update), the list view's extent and each row's own height
local rowHeight = QI.RowHeight(12, 12)
local FILTERS = {
	{ key = "all", label = "All" }, { key = "continent", label = "Continent" }, { key = "zone", label = "Zone" }, { key = "class", label = "Class" },
	{ key = "dungeons", label = "Dungeons" }, { key = "raids", label = "Raids" }, { key = "attunements", label = "Attunements" }, { key = "events", label = "Events" },
}
local BUTTONS_PER_ROW = 4

local function HeaderClick(self)
	if self.entry and self.entry.header then
		QL.collapsed[self.entry.key] = not QL.collapsed[self.entry.key] or nil
		MelloUI:PlayUISound(QL.collapsed[self.entry.key] and "option_off" or "option_on")
		QL.Panel:Update()
	end
end

local function RowClick(self)
	if not (self.entry and self.entry.row) then
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
	else
		Line(tip, string.format("Needs level %d", row[QL.F_REQ]), "text")
	end
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
		if self.melloBand then
			self.melloBand:Show()
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
	if self.melloBand then
		self.melloBand:Hide()
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
	-- the right slot, where the log has its tracking box: a region the pips
	-- and the lines are laid by, never drawn; the Classic or Forever stamp
	-- stands in it (user, 2026-09-23 / 2026-09-27)
	button.slot = button:CreateTexture(nil, "BACKGROUND")
	button.slot:Hide()
	button.origin = button:CreateTexture(nil, "OVERLAY")
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
	button.origin:Hide()
	if button.melloBand then
		button.melloBand:Hide()
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
	button.plus:SetAtlas(QL.collapsed[entry.key] and "common-button-list-plus" or "common-button-list-minus", true)
	button.label:SetText(entry.name)
	KeyColour(button.label, "text")
	button.count:SetText(string.format("%d/%d", entry.done, entry.total))
	KeyColour(button.count, "text", (entry.done == entry.total and entry.total > 0) and QL.DONE_ALPHA or 1)
end

-- The right slot's width: the Classic / Forever stamps' (as wide as each
-- other since 0.15.0, user 2026-09-29: the Classic one shrunk to the Forever
-- one's, every title about 24 px wider; the widest, should they ever
-- differ), so every row's stamp, pips and title stand in one column each,
-- whatever its stamp and whether its quest is pinned (user, 2026-09-27:
-- "fixed columns")
local slotWidth = nil
local function SlotWidth()
	if not slotWidth then
		slotWidth = 0
		for _, logo in pairs(MelloUI.QUEST_ORIGIN_LOGOS or {}) do
			slotWidth = math.max(slotWidth, logo.height * logo.w / logo.h)
		end
	end
	return slotWidth
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
	-- the right slot on the title's line, the Classic / Forever stamp in its
	-- middle, where the log has its tracking box: level with the pips and
	-- with the gem at the end of the hover plate, inside its band (user,
	-- 2026-09-23 / 2026-09-27); an ink stamp on parchment
	local slot = SlotWidth()
	button.slot:SetSize(math.max(slot, 1), titleSize)
	button.slot:ClearAllPoints()
	button.slot:SetPoint("TOPRIGHT", button, "TOPRIGHT", -ROW.edge, -ROW.top)
	button.origin:ClearAllPoints()
	button.origin:SetPoint("CENTER", button.slot, "CENTER")
	MelloUI:ApplyQuestOriginLogo(button.origin, entry.row[QL.F_ID])
	QI.Stamp(button.origin, QI.onParchment)
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

--------------------------------------------------------------------------------
-- The panel stands beside the world map, outside the map's own frames
-- (0.15.0, the map's freeze in the Gamepad UI). As the map's child it was in
-- every walk the game's gamepad navigation makes of the map (as it opens, on
-- each focus change, for each frame made in it): the panel, its list and its
-- rows, and the list's ScrollTarget read on the way, a field MelloUI's list
-- wrote, so the rest of the walk and the navigation's state after it ran on
-- MelloUI's time. It hangs in a holder of its own under UIParent instead,
-- which stands in for the map as the panel's window: it shows and hides
-- with the map, takes the map's alpha as the map takes it (one flat
-- picture: the map is a frame buffer, and so is the holder), its scale,
-- and the strata and level the panel had as its child (on each show, and
-- each time the map is raised), and it rises when the panel is clicked (a
-- toplevel window, as the map). The kit's window mover drags the map by
-- the panel's title plate, as it did while the panel was the map's child
-- (melloWindowOf: the window the kit files the holder's plate and rail
-- under, Kit.lua's WindowOf). The panel keeps its own shown state for the
-- module (Apply, the module's OnDisable), and its OnShow / OnHide come with
-- the map's as before. Its rows are made as the list needs them: the
-- navigation's climb from a new frame stops at UIParent, so a row made
-- later walks no window.
--------------------------------------------------------------------------------

-- a scale on the holder: the panel's backgrounds laid again at the UI's one
-- density with it (Kit:SetFrameScale; only when the scale really changed)
local function HolderScale(holder, scale)
	local Kit = MelloUI.Kit
	if Kit and Kit.SetFrameScale then
		Kit:SetFrameScale(holder, scale)
	else
		holder:SetScale(scale)
	end
end

-- The map's look and place on the holder, by post-hooks only: nothing is
-- written on the map. Its alpha comes from the game's fade while the player
-- moves (PlayerMovementFrameFader sets it on every frame while the map is
-- open and the player has moved) and from UI Modifications' fade-in: one
-- call on to the holder each time. Its scale from UI Modifications' saved
-- scale and the mouse wheel on its mover. Its level: the map is a toplevel
-- window, raised by a click in it and by the panel manager (Raise, as the
-- panels are laid out), and as its child the panel rose with it.
local function FollowMap(holder, frame)
	local map = WorldMapFrame
	-- the map's strata, the holder at the map's level and the panel five
	-- over it, where it stood as the map's child; `up`: only ever lifted (a
	-- click on the panel raised it over the map, and there it stays)
	local function Level(up)
		local strata = map:GetFrameStrata()
		if holder:GetFrameStrata() ~= strata then
			holder:SetFrameStrata(strata)
		end
		if frame:GetFrameStrata() ~= strata then
			frame:SetFrameStrata(strata)
		end
		local level = map:GetFrameLevel()
		if up and holder:GetFrameLevel() >= level then
			return
		end
		if holder:GetFrameLevel() ~= level then
			holder:SetFrameLevel(level)
		end
		if frame:GetFrameLevel() ~= level + 5 then
			frame:SetFrameLevel(level + 5)
		end
	end
	local function Sync()
		holder:SetAlpha(map:GetAlpha())
		HolderScale(holder, map:GetScale())
		Level(false)
	end
	-- a click raises the map in the game's own code, no call to hook: the
	-- panel is lifted after it as the button is let go, while the map shows
	Perf.SetScript(holder, "OnEvent", function()
		Level(true)
	end)
	Sync()
	if map:IsShown() then
		holder:RegisterEvent("GLOBAL_MOUSE_UP")
	end
	Perf.HookScript(map, "OnShow", function()
		Sync()
		holder:Show()
		holder:RegisterEvent("GLOBAL_MOUSE_UP")
	end)
	Perf.HookScript(map, "OnHide", function()
		holder:UnregisterEvent("GLOBAL_MOUSE_UP")
		holder:Hide()
	end)
	Perf.hooksecurefunc(map, "Raise", function()
		Level(true)
	end)
	Perf.hooksecurefunc(map, "SetAlpha", function(_, alpha)
		holder:SetAlpha(alpha)
	end)
	Perf.hooksecurefunc(map, "SetScale", function(_, scale)
		HolderScale(holder, scale)
	end)
end

function QL.Panel:Create()
	if self.frame then
		return
	end
	-- (the holder: the whole screen, no mouse, shown while the map is; at
	-- the map's strata and level, so the panel and its template's frames are
	-- made where they were made as the map's children. A frame buffer, as
	-- the map: the map's fade dims the panel as one picture, not each of its
	-- layers over the others; the whole screen, so no rail or shade that
	-- reaches past the panel is cut. Toplevel, as the map: a click on the
	-- panel raises it. And the map's for the kit: melloWindowOf)
	local holder = CreateFrame("Frame", nil, UIParent)
	holder:SetAllPoints(UIParent)
	holder:SetFrameStrata(WorldMapFrame:GetFrameStrata())
	holder:SetFrameLevel(WorldMapFrame:GetFrameLevel())
	holder:SetShown(WorldMapFrame:IsShown())
	if holder.SetIsFrameBuffer then
		holder:SetIsFrameBuffer(true)
	end
	holder:SetToplevel(true)
	holder.melloWindowOf = WorldMapFrame
	local frame = CreateFrame("Frame", "MelloUIQuestListPanel", holder, "PortraitFrameTemplate")
	self.frame = frame
	frame:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT", 2, 0)
	frame:SetPoint("BOTTOMLEFT", WorldMapFrame, "BOTTOMRIGHT", 2, 0)
	frame:SetWidth(tonumber(M.db.width) or QL.PANEL_WIDTH)
	-- (the map's strata, five levels over the map, its alpha and scale: now,
	-- on each show and as the map is raised)
	FollowMap(holder, frame)
	frame:EnableMouse(true)
	if frame.SetTitle then
		frame:SetTitle("Quests")
	end
	if frame.CloseButton then
		frame.CloseButton:Hide()
	end
	-- Drop the portrait ring: the border art without the circle is a separate
	-- layout that Blizzard's own helper switches to.
	if not (ButtonFrameTemplate_HidePortrait and pcall(ButtonFrameTemplate_HidePortrait, frame)) then
		if frame.PortraitContainer then
			frame.PortraitContainer:Hide()
		end
		if NineSliceUtil and frame.NineSlice then
			pcall(NineSliceUtil.ApplyLayoutByName, frame.NineSlice, "PortraitFrameTemplateNoPortrait")
		end
	end

	-- The quest log's dark book background inside the border.
	frame.bg = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	frame.bg:SetPoint("TOPLEFT", 8, -26)
	frame.bg:SetPoint("BOTTOMRIGHT", -8, 8)
	if not pcall(frame.bg.SetAtlas, frame.bg, "QuestLog-main-background") then
		MelloUI.Widgets.Paint(frame.bg, "innerPanel", "fill", 1)
	end

	-- Filter by what a quest starts from (user, 2026-09-23): a quest giver, a
	-- mob drop, an item picked up, or not known. Top right, beside the title.
	local okF, filterButton = pcall(CreateFrame, "DropdownButton", nil, frame, "WowStyle1FilterDropdownTemplate")
	if not okF then
		filterButton = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
		if filterButton.SetDefaultText then
			filterButton:SetDefaultText("Filter")
		end
	end
	filterButton:SetSize(94, 22)
	filterButton:SetPoint("TOPRIGHT", -18, -34)
	if filterButton.Text and filterButton.Text.SetText then
		filterButton.Text:SetText("Filter")
	end
	filterButton:SetupMenu(function(_, root)
		root:CreateTitle("Quests that start from")
		for _, k in ipairs(QL.START_KINDS) do
			root:CreateCheckbox(QL.StarterIconMarkup(k.key, 18) .. " " .. k.label,
				function() return M.db[k.setting] ~= false end,
				function()
					MelloUI:NotifySettingChanged(M.name, k.setting, M.db[k.setting] == false)
				end)
		end
	end)
	-- the funnel button's reset (the red X) shows when any kind is hidden
	if filterButton.SetIsDefaultCallback then
		filterButton:SetIsDefaultCallback(function()
			for _, k in ipairs(QL.START_KINDS) do
				if M.db[k.setting] == false then
					return false
				end
			end
			return true
		end)
	end
	if filterButton.SetDefaultCallback then
		filterButton:SetDefaultCallback(function()
			for _, k in ipairs(QL.START_KINDS) do
				M.db[k.setting] = true
			end
			MelloUI:NotifySettingChanged(M.name, "startGiver", true)
		end)
	end
	frame.filterButton = filterButton

	-- Under the Filter button (user, 2026-09-23): a shortcut to the "Hide
	-- Quests More Than N Levels Above Me" setting. Checked sets it to
	-- LEVEL_SHORTCUT (hiding quests 5 or more levels above, the red ones);
	-- unchecked puts it back to no limit. Any other value set in the settings
	-- shows it unchecked.
	local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	check:SetSize(22, 22)
	check:SetPoint("TOPRIGHT", filterButton, "BOTTOMRIGHT", 2, -2)
	check.label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	check.label:SetPoint("RIGHT", check, "LEFT", -1, 1)
	check.label:SetText("Hide 5+ levels above me")
	check:SetHitRectInsets(-(check.label:GetStringWidth() + 4), 0, 0, 0)
	Perf.SetScript(check, "OnClick", function(self)
		MelloUI:NotifySettingChanged(M.name, "levelAbove", self:GetChecked() and LEVEL_SHORTCUT or 0)
		MelloUI:PlayUISound(self:GetChecked() and "option_on" or "option_off")
	end)
	Perf.SetScript(check, "OnEnter", function(self)
		-- (MelloUI's one tooltip: the palette's gold and text)
		MelloUI.Widgets.ShowTooltip(self, "Hide quests 5+ levels above me",
			"Leaves out the quests 5 or more levels above your character (the red ones) in the Quests list and on the map. "
			.. "The same as Hide Quests More Than N Levels Above Me set to +4 in the settings; unchecked, no limit.", nil, "ANCHOR_RIGHT")
	end)
	Perf.SetScript(check, "OnLeave", function() GameTooltip:Hide() end)
	frame.levelCheck = check
	-- and under it Hide completed (user, 2026-09-23: "should also be somewhere
	-- there"; it sat under the filter buttons)
	frame.hide = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	frame.hide:SetSize(22, 22)
	frame.hide:SetPoint("TOPRIGHT", check, "BOTTOMRIGHT", 0, 2)
	frame.hide.text = frame.hide:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.hide.text:SetPoint("RIGHT", frame.hide, "LEFT", -1, 1)
	frame.hide.text:SetText("Hide completed")
	frame.hide:SetHitRectInsets(-(frame.hide.text:GetStringWidth() + 4), 0, 0, 0)
	Perf.SetScript(frame.hide, "OnClick", function(self)
		M.db.hideCompleted = self:GetChecked() and true or false
		MelloUI:NotifySettingChanged(M.name, "hideCompleted", M.db.hideCompleted)
		QL.Panel:Update()
	end)

	frame.zone = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
	frame.zone:SetPoint("TOPLEFT", 18, -36)
	frame.zone:SetPoint("RIGHT", filterButton, "LEFT", -8, 0)
	frame.zone:SetJustifyH("LEFT")
	frame.zone:SetWordWrap(false)
	frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.count:SetPoint("TOPLEFT", frame.zone, "BOTTOMLEFT", 0, -3)
	frame.count:SetJustifyH("LEFT")

	frame.divider = frame:CreateTexture(nil, "ARTWORK")
	-- below the count and the two check boxes under the Filter button
	frame.divider:SetPoint("LEFT", 12, 0)
	frame.divider:SetPoint("TOP", frame.hide, "BOTTOM", 0, -2)
	frame.divider:SetPoint("RIGHT", -12, 0)
	frame.divider:SetHeight(8)
	if not pcall(frame.divider.SetAtlas, frame.divider, "QuestLog-frame-devider") then
		MelloUI.Widgets.Paint(frame.divider, "trim", "fill", 0.6)
		frame.divider:SetHeight(1)
	end

	-- Search box in the quest log's style. Typing searches every zone.
	local search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	search:SetPoint("TOPLEFT", frame.divider, "BOTTOMLEFT", 10, -6)
	search:SetPoint("RIGHT", -16, 0)
	search:SetHeight(ROW.searchHeight)   -- the log's box (QI.ROW)
	search:SetAutoFocus(false)
	if search.Instructions then
		search.Instructions:SetText("Search quests")
	end
	Perf.HookScript(search, "OnTextChanged", function(self, userInput)
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

	-- Filter buttons.
	frame.filters = {}
	for i, f in ipairs(FILTERS) do
		local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		b:SetSize(84, 22)
		local column, row = (i - 1) % BUTTONS_PER_ROW, math.floor((i - 1) / BUTTONS_PER_ROW)
		if column > 0 then
			b:SetPoint("LEFT", frame.filters[i - 1], "RIGHT", 3, 0)
		elseif row > 0 then
			b:SetPoint("TOPLEFT", frame.filters[i - BUTTONS_PER_ROW], "BOTTOMLEFT", 0, -3)
		else
			b:SetPoint("TOPLEFT", frame.search, "BOTTOMLEFT", -4, -5)
		end
		b:SetText(f.label)
		b.key = f.key
		Perf.SetScript(b, "OnClick", function(self)
			M.db.filter = self.key
			MelloUI:NotifySettingChanged(M.name, "filter", self.key)
			QL.Panel:Update()
		end)
		frame.filters[i] = b
	end
	-- Virtualised list with headers and rows, below the last row of buttons.
	local lastRowFirst = frame.filters[#frame.filters - ((#frame.filters - 1) % BUTTONS_PER_ROW)]
	frame.scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
	frame.scrollBox:SetPoint("TOPLEFT", lastRowFirst, "BOTTOMLEFT", 2, -6)
	frame.scrollBox:SetPoint("BOTTOMRIGHT", -30, 14)
	frame.scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
	QI.RowScrollBar(frame.scrollBar, frame.scrollBox)   -- where the log has its own
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
	frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	frame.empty:SetPoint("CENTER", frame.scrollBox, "CENTER")
	frame.empty:SetWidth(240)
	frame.empty:Hide()

	-- the quest log's and the player's casts counted while the panel shows
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
	-- a new palette: the rows laid again in it while the panel shows (a
	-- hidden panel is laid afresh on its next show). Only a palette TABLE
	-- the list was not laid in: 'palette' goes out for a Kit Colours change
	-- too, the palette unchanged
	MelloUI:On("palette", function()
		if laid.palette ~= MelloUI.Palette then
			QL.Panel:Update()
		end
	end, "Quest List panel")
	-- new fonts (the Fonts module: a face, a size, the outline): the rows laid
	-- again in them while the panel shows -- their height comes from the
	-- fonts as the list was laid, and a row a scroll brings into view takes
	-- the fonts as they are now (no quest event need follow a size change)
	MelloUI:On("fonts", function()
		if laid.font ~= ListFont() then
			QL.Panel:Update()
		end
	end, "Quest List panel")
end

function QL.Panel:Apply()
	if not self.frame then
		return
	end
	self.frame:SetWidth(tonumber(M.db.width) or QL.PANEL_WIDTH)
	self.frame:SetShown(M.isEnabled)
	self.frame.levelCheck:SetChecked(tonumber(M.db.levelAbove) == LEVEL_SHORTCUT)
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
				group.rows[#group.rows + 1] = {
					row = row, completed = completed, onQuest = onQuest, showZone = showZone,
					ready = onQuest and QL.IsReadyForTurnIn(row[QL.F_ID]) or false,
					available = not onQuest and row[QL.F_REQ] <= level,
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
				for _, e in ipairs(group.rows) do
					entries[#entries + 1] = e
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
			or x.available ~= y.available or x.showZone ~= y.showZone or x.step ~= y.step then
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
	if not frame or not frame:IsShown() or not QL.byZone then
		return
	end
	local db, data = M.db, QL.Data()
	QL.SyncTracked()
	for _, b in ipairs(frame.filters) do
		-- on the kit (QuestLogPanel) the selection is a plate, not a dimming
		b:SetAlpha((b.melloKitPlate or b.key == db.filter) and 1 or 0.6)
	end
	frame.hide:SetChecked(db.hideCompleted and true or false)
	if frame.filterButton.ValidateResetState then
		frame.filterButton:ValidateResetState()
	end

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
	frame.zone:SetText(title)
	frame.count:SetText(string.format("%d of %d completed", done, total))
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
	-- zone, its count, the two check boxes, the empty list's line)
	if not inkLabels then
		inkLabels = { { frame.zone, "title" }, { frame.count, "text" }, { frame.empty, "text" },
			{ frame.levelCheck and frame.levelCheck.label, "text" }, { frame.hide and frame.hide.text, "text" } }
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

-- Show one group (a dungeon, a raid, a chain) after a click elsewhere: switch
-- the list, fold the other groups, scroll to it and pulse the title and the
-- group's header so the change is seen.
function QL.Panel:Reveal(key, filter)
	local frame = self.frame
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
	-- the title block (zone name and count), not the whole panel
	if not frame.titleArea then
		frame.titleArea = CreateFrame("Frame", nil, frame)
		frame.titleArea:SetPoint("TOPLEFT", frame.zone, "TOPLEFT", -6, 4)
		frame.titleArea:SetPoint("BOTTOM", frame.count, "BOTTOM", 0, -4)
		frame.titleArea:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
	end
	Pulse(frame.titleArea, 0)
	return index ~= nil
end

MelloUI:Profile("QuestList", "panel rebuild", QL.Panel.Update)
