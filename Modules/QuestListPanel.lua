--------------------------------------------------------------------------------
-- MelloUI - Quest List: the panel
--
-- The list attached to the right of the world map. Shares its data and helpers
-- with QuestList.lua through ns.QuestList (QL).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("QuestListPanel")
local C_Timer = Perf.C_Timer
local QL = ns.QuestList
local M = QL.M

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------

QL.Panel = {}
local ROW_HEIGHT = 36   -- a 13 px title over a 12 px line, as the quest log sets them
local HEADER_HEIGHT = 24
local LEVEL_SHORTCUT = 4   -- the level check box under the Filter button: hide quests more than 4 (so 5 or more) levels above
local ICON_SIZE = 18   -- the row's quest icon ("!", "?", tick, swords, chest, door); 14 was too small
local FILTERS = {
	{ key = "all", label = "All" }, { key = "continent", label = "Continent" }, { key = "zone", label = "Zone" }, { key = "class", label = "Class" },
	{ key = "dungeons", label = "Dungeons" }, { key = "raids", label = "Raids" }, { key = "attunements", label = "Attunements" }, { key = "events", label = "Events" },
}
local BUTTONS_PER_ROW = 4

local function HeaderClick(self)
	if self.entry and self.entry.header then
		QL.collapsed[self.entry.key] = not QL.collapsed[self.entry.key] or nil
		PlaySound(QL.collapsed[self.entry.key] and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		QL.Panel:Update()
	end
end

local function RowClick(self)
	if not (self.entry and self.entry.row) then
		return
	end
	if QL.trackedQuestID == self.entry.row[QL.F_ID] then
		QL.ClearWaypoint()
		PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_REMOVE or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
	elseif QL.SetWaypoint(self.entry.row, self.entry.ready) then
		PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_CLICK_TO_PLACE or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
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
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	local r, g, b = QL.DifficultyColor(row[QL.F_LEVEL])
	GameTooltip:SetText(row[QL.F_TITLE], r, g, b)
	GameTooltip:AddLine(string.format("Level %d, requires level %d", row[QL.F_LEVEL], row[QL.F_REQ]), 0.8, 0.8, 0.8)
	if row[QL.F_DUNGEON] ~= 0 and QL.Data().dungeons[row[QL.F_DUNGEON]] then
		local what = QL.IsRaid(row[QL.F_DUNGEON]) and "Raid quest: " or "Dungeon quest: "
		GameTooltip:AddLine(what .. QL.Data().dungeons[row[QL.F_DUNGEON]], 0.75, 0.61, 0)
	end
	if row[QL.F_CHAIN] ~= 0 and QL.Data().chains[row[QL.F_CHAIN]] then
		local step, total, nextRow = QL.ChainInfo(row)
		GameTooltip:AddLine(string.format("Step %d of %d in the chain: %s", step, total, QL.Data().chains[row[QL.F_CHAIN]]), 0.75, 0.61, 0)
		if nextRow then
			GameTooltip:AddLine("Next: " .. nextRow[QL.F_TITLE], 0.6, 0.6, 0.6)
		end
	end
	if row[QL.F_GIVER] ~= "" then
		local giverZone = QL.Data().zones[QL.ZoneOf(row)]
		local instance = QL.InstanceStart(row)
		if instance then
			local kind = QL.IsRaid(instance) and "raid" or "dungeon"
			local name = QL.Data().dungeons[instance]
			if QL.IsItemStart(row) then
				GameTooltip:AddLine(string.format("Begins with the item %s, which drops inside the %s %s", row[QL.F_GIVER], kind, name), 0.8, 0.8, 0.8, true)
			else
				GameTooltip:AddLine(string.format("Begins at %s inside the %s %s", row[QL.F_GIVER], kind, name), 0.8, 0.8, 0.8, true)
			end
		elseif QL.IsItemStart(row) then
			local how = row[QL.F_KIND] == QL.KIND_PICKUP and ", picked up in " or ", dropped by creatures in "
			GameTooltip:AddLine("Begins with the item " .. row[QL.F_GIVER] .. (giverZone and (how .. giverZone) or ""), 0.8, 0.8, 0.8)
		else
			GameTooltip:AddLine("From " .. row[QL.F_GIVER] .. (giverZone and (" in " .. giverZone) or ""), 0.8, 0.8, 0.8)
		end
		local _, gx, gy = QL.GiverPoint(row)
		if gx then
			GameTooltip:AddLine(string.format("   at %.1f, %.1f", gx * 100, gy * 100), 0.6, 0.6, 0.6)
		end
	end
	if (row[QL.F_ENDER] or "") ~= "" then
		if QL.SameEnder(row) then
			GameTooltip:AddLine("Turn in to the same NPC", 0.6, 0.6, 0.6)
		else
			local endZone = QL.EnderZoneName(row)
			GameTooltip:AddLine("Turn in to " .. row[QL.F_ENDER] .. (endZone and (" in " .. endZone) or ""), 0.8, 0.8, 0.8)
			local _, ex, ey = QL.EndPoint(row)
			if ex then
				GameTooltip:AddLine(string.format("   at %.1f, %.1f", ex * 100, ey * 100), 0.6, 0.6, 0.6)
			end
		end
	end
	if e.completed then
		GameTooltip:AddLine("Completed", 0.5, 0.5, 0.5)
	elseif e.onQuest and e.ready then
		GameTooltip:AddLine("In your quest log, ready to turn in", 1, 0.82, 0)
	elseif e.onQuest then
		GameTooltip:AddLine("In your quest log, objectives not done", 0.7, 0.7, 0.7)
	elseif e.available then
		GameTooltip:AddLine("Available to pick up", 1, 0.82, 0)
	else
		GameTooltip:AddLine(string.format("Needs level %d", row[QL.F_REQ]), 0.7, 0.7, 0.7)
	end
	if QL.trackedQuestID == row[QL.F_ID] then
		GameTooltip:AddLine("Map pin set on this quest giver. Click to remove it.", 0.6, 0.8, 1)
	elseif e.ready and QL.EndPoint(row) then
		GameTooltip:AddLine("Click to place a map pin on the turn-in NPC.", 0.6, 0.8, 1)
	elseif select(2, QL.GiverPoint(row)) then
		local target = row[QL.F_KIND] == QL.KIND_DROP and "where the item drops most"
			or row[QL.F_KIND] == QL.KIND_PICKUP and "where the item is picked up" or "on the quest giver"
		GameTooltip:AddLine("Click to place a map pin " .. target .. ".", 0.6, 0.8, 1)
	elseif QL.InstanceStart(row) and QL.EntrancePoint(QL.InstanceStart(row)) then
		GameTooltip:AddLine(string.format("Click to route to the %s entrance.", QL.IsRaid(QL.InstanceStart(row)) and "raid" or "dungeon"), 0.6, 0.8, 1)
	else
		GameTooltip:AddLine("Location not known yet.", 0.6, 0.6, 0.6)
	end
	ShowTipIcon(row)
	GameTooltip:Show()
end

local function Leave()
	GameTooltip:Hide()
end

-- One button pool serves headers and rows, so every widget is created once
-- and each init sets up the button completely for the kind it shows.
-- The quest log's look (user, 2026-09-23: "why is there a difference in
-- text between the Default Quest log, and the MelloUI Quest Module"): the
-- game's face and outline as the Fonts module sets them, the title and the
-- line under it at the quest log's 12 (13 read larger than the log, user
-- screenshot 2026-09-23). Set on every row, so a Fonts change reaches it.
local TITLE_SIZE, LINE_SIZE = 12, 12   -- the quest log sets both lines the same size
local function QuestLogFonts(button)
	local object = GameFontNormal
	if not (object and object.GetFont) then
		return
	end
	local ok, path, _, flags = pcall(object.GetFont, object)
	if ok and path then
		pcall(button.title.SetFont, button.title, path, TITLE_SIZE, flags or "")
		pcall(button.where.SetFont, button.where, path, LINE_SIZE, flags or "")
	end
end

local function EnsureWidgets(button)
	if button.title then
		return
	end
	button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	if Game15Font_Shadow then
		button.label:SetFontObject(Game15Font_Shadow)
	end
	button.label:SetPoint("LEFT", 9, 0)
	button.label:SetPoint("RIGHT", -70, 0)
	button.label:SetJustifyH("LEFT")
	button.label:SetWordWrap(false)
	button.count = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.count:SetPoint("RIGHT", -30, 0)
	button.count:SetJustifyH("RIGHT")
	button.plus = button:CreateTexture(nil, "OVERLAY")
	button.plus:SetPoint("RIGHT", -6, 0)
	button.check = button:CreateTexture(nil, "ARTWORK")
	button.check:SetSize(ICON_SIZE, ICON_SIZE)
	button.check:SetPoint("CENTER", button, "LEFT", 21, 0)   -- same middle as before, clear of the title at 34
	button.title = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	button.title:SetPoint("TOPLEFT", 34, -3)
	button.title:SetPoint("RIGHT", -8, 0)
	button.title:SetJustifyH("LEFT")
	button.title:SetWordWrap(false)
	button.where = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.where:SetPoint("BOTTOMLEFT", 34, 4)
	button.where:SetPoint("RIGHT", -8, 0)
	button.where:SetJustifyH("LEFT")
	button.where:SetWordWrap(false)
	-- Classic or Forever, top right (user, 2026-09-23)
	button.origin = button:CreateTexture(nil, "OVERLAY")
	button.pin = button:CreateTexture(nil, "OVERLAY")
	button.pin:SetSize(20, 20)
	button.pin:SetPoint("RIGHT", -6, 0)
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
end

-- A gold pulse over a frame: bright at once, gone within a second. Under
-- Reduce Motion it ends at once: no flash (Anim:PlayGroup; audit, 2026-09-24).
local function Pulse(owner, inset)
	local flash = owner.pulse
	if not flash then
		flash = owner:CreateTexture(nil, "OVERLAY", nil, 7)
		flash:SetColorTexture(1, 0.82, 0.2, 1)
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
	button:SetHeight(HEADER_HEIGHT)
	button.check:Hide()
	button.title:Hide()
	button.where:Hide()
	button.label:Show()
	button.count:Show()
	button.plus:Show()
	button.pin:Hide()
	button.origin:Hide()
	button:SetNormalAtlas("common-button-list-collapseExpand")
	button:SetHighlightAtlas("common-button-list-collapseExpand", "ADD")
	button:GetHighlightTexture():SetAlpha(0.4)
	button.plus:SetAtlas(QL.collapsed[entry.key] and "common-button-list-plus" or "common-button-list-minus", true)
	Perf.SetScript(button, "OnClick", HeaderClick)
	Perf.SetScript(button, "OnEnter", nil)
	Perf.SetScript(button, "OnLeave", nil)
	button.label:SetText(entry.name)
	button.label:SetTextColor(0.9, 0.9, 0.9)
	button.count:SetText(string.format("%d/%d", entry.done, entry.total))
	if entry.done == entry.total and entry.total > 0 then
		button.count:SetTextColor(0.5, 0.5, 0.5)
	else
		button.count:SetTextColor(1, 1, 1)
	end
end

local function InitRow(button, entry)
	EnsureWidgets(button)
	button.entry = entry
	button:SetHeight(ROW_HEIGHT)
	button.label:Hide()
	button.count:Hide()
	button.plus:Hide()
	button.title:Show()
	button.where:Show()
	local tracked = QL.trackedQuestID ~= nil and entry.row[QL.F_ID] == QL.trackedQuestID
	button.pin:SetShown(tracked)
	-- the logo at the top right (left of the pin on the tracked quest), both
	-- logos centred on one column whatever their widths (user, 2026-09-23:
	-- "where is the middle" -- hung by their right edge, the wider Classic
	-- one sat left of the Forever one), the title stopping short of it
	local right = tracked and -32 or -8
	-- and its middle on the row's middle, level with the gem at the end of the
	-- row's plate (user, 2026-09-23); both lines stop short of it
	local LOGO_COLUMN = 44   -- the column's centre from the right edge
	button.origin:ClearAllPoints()
	button.origin:SetPoint("CENTER", button, "RIGHT", right - LOGO_COLUMN, 0)
	local logoWidth = MelloUI:ApplyQuestOriginLogo(button.origin, entry.row[QL.F_ID])
	local tagRoom = logoWidth and (LOGO_COLUMN + logoWidth / 2 + 6) or 0
	button.title:SetPoint("RIGHT", right - tagRoom, 0)
	button.where:SetPoint("RIGHT", right - tagRoom, 0)
	button.titleRight = right - tagRoom   -- the title's right edge (the pips stand in front of it on parchment)
	button:ClearNormalTexture()
	button:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]], "ADD")
	button:GetHighlightTexture():SetAlpha(0.6)
	Perf.SetScript(button, "OnClick", RowClick)
	Perf.SetScript(button, "OnEnter", RowEnter)
	Perf.SetScript(button, "OnLeave", Leave)
	local row = entry.row
	local r, g, b = QL.DifficultyColor(QL.ColourLevel(row))
	-- the game's trivial grey (0.5) reads as near black over the list's
	-- shade (user, 2026-09-22: "why are the quest names so dark"): the
	-- panel lifts it; the colour still says trivial
	if r == g and g == b and r <= 0.5 then
		r, g, b = 0.72, 0.72, 0.72
	end
	-- "[12] Title", as the quest log writes it
	QuestLogFonts(button)
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
		button.title:SetTextColor(0.6, 0.6, 0.6)   -- done: a step under the trivial grey
	elseif entry.onQuest then
		button.check:SetAtlas("QuestTurnin")
		button.check:SetDesaturated(not entry.ready)
		button.check:SetAlpha(entry.ready and 1 or 0.6)
		button.title:SetTextColor(r, g, b)
	else
		-- not taken yet: the "!", or what the quest begins from (swords, chest, instance door)
		local starter = QL.StarterKind(row)
		if not (starter and QL.SetStarterIcon(button.check, starter)) then
			button.check:SetAtlas("QuestNormal")
		end
		button.check:SetDesaturated(not entry.available)
		button.check:SetAlpha(entry.available and 1 or 0.6)
		button.title:SetTextColor(r, g, b)
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
	-- as a quest log objective line: a dash, white; grey once done
	button.where:SetText("- " .. where)
	if entry.completed then
		button.where:SetTextColor(0.55, 0.55, 0.55)
	else
		button.where:SetTextColor(0.95, 0.95, 0.95)
	end
	-- on the reskin's parchment: both lines in ink, the difficulty in pips at
	-- the title's right (QuestInk; user, 2026-09-23); a done quest faded, no pips
	local QI = MelloUI.QuestInk
	local titleRight = button.titleRight or -8
	if QI and QI.onParchment then
		local level = QL.ColourLevel(row)
		local tier = nil
		if not entry.completed and level > 0 then
			tier = QI.TierForQuest(row[QL.F_ID], level) or QI.TierOfColour(QL.DifficultyColor(level))
		end
		button.pips = button.pips or QI.Pips(button, 10)
		local pipsRoom = tier and (QI.PipsWidth(10) + 6) or 0
		button.title:SetPoint("RIGHT", titleRight - pipsRoom, 0)
		button.pips:ClearAllPoints()
		button.pips:SetPoint("TOPLEFT", button, "TOPRIGHT", titleRight - pipsRoom + 4, -4)
		button.pips:SetTier(tier)
		local faded = entry.completed or tier == 1
		QI.Ink(button.title, faded and "faded" or "title")
		QI.Ink(button.where, faded and "faded" or "text")
	elseif QI then
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

-- The quest log's font (the Fonts module) as the rows take it
local function ListFont()
	if GameFontNormal and GameFontNormal.GetFont then
		local ok, path, _, flags = pcall(GameFontNormal.GetFont, GameFontNormal)
		if ok then
			return path, flags
		end
	end
	return nil, nil
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

-- the log read by C_QuestLog (true), the older calls (false) or not at all (nil)
local function LogCalls()
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetQuestIDForLogIndex then
		return true
	elseif _G.GetNumQuestLogEntries and _G.GetQuestLogTitle then
		return false
	end
	return nil
end

-- the log's lines (headers too) and quests, nil when it cannot be read
local function LogSize(modern)
	local ok, lines, quests
	if modern then
		ok, lines, quests = pcall(C_QuestLog.GetNumQuestLogEntries)
	elseif modern == false then
		ok, lines, quests = pcall(_G.GetNumQuestLogEntries)
	end
	if not ok then
		return nil
	end
	lines, quests = QL.Plain(lines), QL.Plain(quests)
	if type(lines) ~= "number" or type(quests) ~= "number" then
		return nil
	end
	return lines, quests
end

-- the quest id on a log line, nil for a header
local function LogQuestID(modern, i)
	local ok, id
	if modern then
		ok, id = pcall(C_QuestLog.GetQuestIDForLogIndex, i)
	else
		local _, isHeader
		ok, _, _, _, isHeader, _, _, _, id = pcall(_G.GetQuestLogTitle, i)
		if ok and QL.Plain(isHeader) then
			return nil
		end
	end
	id = ok and QL.Plain(id) or nil
	return (type(id) == "number" and id > 0) and id or nil
end

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
	local face, flags = ListFont()
	if pins or face ~= laid.face or flags ~= laid.flags then
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

function QL.Panel:Create()
	if self.frame then
		return
	end
	local frame = CreateFrame("Frame", "MelloUIQuestListPanel", WorldMapFrame, "PortraitFrameTemplate")
	self.frame = frame
	frame:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT", 2, 0)
	frame:SetPoint("BOTTOMLEFT", WorldMapFrame, "BOTTOMRIGHT", 2, 0)
	frame:SetWidth(tonumber(M.db.width) or 340)
	frame:SetFrameStrata(WorldMapFrame:GetFrameStrata())
	frame:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 5)
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
		frame.bg:SetColorTexture(0.08, 0.06, 0.05, 1)
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
		PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
	end)
	Perf.SetScript(check, "OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Hide quests 5+ levels above me", 1, 0.82, 0)
		GameTooltip:AddLine("Leaves out the quests 5 or more levels above your character (the red ones) in the Quests list and on the map. "
			.. "The same as Hide Quests More Than N Levels Above Me set to +4 in the settings; unchecked, no limit.", 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
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
		frame.divider:SetColorTexture(0.4, 0.32, 0.12, 0.6)
		frame.divider:SetHeight(1)
	end

	-- Search box in the quest log's style. Typing searches every zone.
	local search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	search:SetPoint("TOPLEFT", frame.divider, "BOTTOMLEFT", 10, -6)
	search:SetPoint("RIGHT", -16, 0)
	search:SetHeight(22)
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
	frame.scrollBar:SetPoint("TOPLEFT", frame.scrollBox, "TOPRIGHT", 6, 0)
	frame.scrollBar:SetPoint("BOTTOMLEFT", frame.scrollBox, "BOTTOMRIGHT", 6, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtentCalculator(function(_, entry)
		return entry.header and HEADER_HEIGHT or ROW_HEIGHT
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

end

function QL.Panel:Apply()
	if not self.frame then
		return
	end
	self.frame:SetWidth(tonumber(M.db.width) or 340)
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

-- `quiet` (a rebuild an event asked for): the list is laid out again only
-- when what it would show differs from what it shows (every row's button
-- set up anew and the kit's rows skinned again, for the same list, was the
-- bulk of a rebuild's time -- /melloperf, 2026-09-24). A click, a filter, a
-- map change, a setting or showing the panel always lay it out.
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
			name = string.format("%s |cff888888(%d-%d)|r", name, lv[1], lv[2] > 0 and lv[2] or lv[1])
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
	-- the level (the difficulty colours), the parchment (the ink) and the
	-- quest log's font (the Fonts module)
	local level = QL.Plain(UnitLevel("player"))
	local QI = MelloUI.QuestInk
	local paper = QI and QI.onParchment and true or false
	local face, flags = ListFont()
	if quiet and not (revealKey and GetTime() < revealUntil) and laid.title == title and laid.done == done
		and laid.total == total and laid.tracked == QL.trackedQuestID and laid.level == level and laid.paper == paper
		and laid.face == face and laid.flags == flags and SameEntries(laid.entries, entries) then
		return
	end
	laid.entries, laid.title, laid.done, laid.total, laid.tracked = entries, title, done, total, QL.trackedQuestID
	laid.level, laid.paper, laid.face, laid.flags = level, paper, face, flags
	frame.zone:SetText(title)
	frame.count:SetText(string.format("%d of %d completed", done, total))
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
	if QI then
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
