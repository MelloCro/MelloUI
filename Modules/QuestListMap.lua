--------------------------------------------------------------------------------
-- MelloUI - Quest List: map pins
--
-- Quest giver pins and zone badges, instance entrances and transports, how
-- entrances are learned, and the click hooks on the client's flight master
-- pins. Shares its data and helpers with QuestList.lua through ns.QuestList (QL).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local QL = ns.QuestList
local M = QL.M

--------------------------------------------------------------------------------
-- Map pins
--
-- Zone maps: one pin per quest giver location, showing what you can do there
-- (yellow ! pick up, yellow ? turn in, grey ? in progress, grey ! too low,
-- grey tick all done). Continent maps: a done/total badge on every zone.
-- Built on the map's own data provider system, so the pins pan and zoom with
-- the canvas like Blizzard's.
--------------------------------------------------------------------------------

QL.PIN_TEMPLATE = "MelloUIQuestPinTemplate"
local MAP_ZONE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
local MAP_CONTINENT = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2

-- Priority of what a giver offers, highest wins the icon.
local STATE_RANK = { ready = 5, available = 4, progress = 3, locked = 2, done = 1 }
local STATE_TEXT = {
	ready = { "Ready to turn in", 1, 0.82, 0 },
	available = { "Available", 1, 0.82, 0 },
	progress = { "In progress", 0.7, 0.7, 0.7 },
	locked = { "Level too low", 0.6, 0.6, 0.6 },
	done = { "Completed", 0.5, 0.5, 0.5 },
}

local TRANSPORT_ATLAS = {
	[0] = { "taxinode_continent_neutral_timed", "TaxiNode_Neutral" },
	[1] = { "taxinode_continent_alliance_timed", "TaxiNode_Alliance" },
	[2] = { "taxinode_continent_horde_timed", "TaxiNode_Horde" },
}

-- Not every atlas of the retail engine is in this client's art; try in turn.
local function SetFirstAtlas(tex, list)
	for _, atlas in ipairs(list) do
		if pcall(tex.SetAtlas, tex, atlas) and tex:GetAtlas() then
			return true
		end
	end
	tex:SetTexture("Interface/Minimap/Tracking/None")
	return false
end

local function DungeonIDByName(name)
	if not name then
		return 0
	end
	for id, dname in pairs(QL.Data().dungeons or {}) do
		if dname:lower() == name:lower() then
			return id
		end
	end
	return 0
end

-- Done / total of a dungeon's quests for this character.
local function DungeonProgress(dungeonID)
	local done, total = 0, 0
	for _, row in ipairs(QL.byDungeon and QL.byDungeon[dungeonID] or {}) do
		if QL.Eligible(row) then
			total = total + 1
			if QL.IsCompleted(row[QL.F_ID]) then
				done = done + 1
			end
		end
	end
	return done, total
end

local function QuestState(row, level)
	if QL.IsCompleted(row[QL.F_ID]) then
		return "done"
	end
	if QL.IsOnQuest(row[QL.F_ID]) then
		return QL.IsReadyForTurnIn(row[QL.F_ID]) and "ready" or "progress"
	end
	return row[QL.F_REQ] <= level and "available" or "locked"
end

MelloUI_QuestPinMixin = MelloUI_QuestPinMixin or {}
QL.PinMixin = MelloUI_QuestPinMixin
local PinMethods = {}

function PinMethods:OnLoad()
	-- Constant on-screen size whatever the zoom, layered with the map's POIs.
	self:SetScalingLimits(1, 1.0, 1.0)
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
end

function PinMethods:OnAcquired(kind, data)
	self.kind, self.data = kind, data
	self.Label:ClearAllPoints()
	if kind == "giver" then
		self.Bg:Hide()
		self.Icon:Show()
		self:SetSize(22, 22)
		local state = data.state
		if state == "done" then
			self.Icon:SetAtlas("questlog-icon-checkmark-yellow")
			self.Icon:SetDesaturated(true)
			self.Icon:SetAlpha(0.7)
		elseif state == "ready" or state == "progress" then
			self.Icon:SetAtlas("QuestTurnin")
			self.Icon:SetDesaturated(state ~= "ready")
			self.Icon:SetAlpha(state == "ready" and 1 or 0.75)
		else
			self.Icon:SetAtlas("QuestNormal")
			self.Icon:SetDesaturated(state ~= "available")
			self.Icon:SetAlpha(state == "available" and 1 or 0.75)
		end
		self.Label:SetPoint("TOP", self, "BOTTOM", 0, 2)
		self.Label:SetText(data.tracked and data.giver or "")
		self.Label:SetTextColor(0.6, 0.8, 1)
		self.Label:SetShown(data.tracked)
	elseif kind == "entrance" or kind == "transport" then
		self.Bg:Hide()
		self.Label:Hide()
		self.Icon:Show()
		self.Icon:SetDesaturated(false)
		self.Icon:SetAlpha(1)
		if kind == "entrance" then
			self:SetSize(30, 30)
			SetFirstAtlas(self.Icon, data.raid and { "Raid", "DungeonSkull" } or { "Dungeon", "DungeonSkull" })
		else
			self:SetSize(26, 26)
			SetFirstAtlas(self.Icon, TRANSPORT_ATLAS[data.faction] or TRANSPORT_ATLAS[0])
		end
	else
		self.Icon:Hide()
		self.Bg:Show()
		self.Bg:SetColorTexture(0, 0, 0, 0.7)
		self.Label:SetPoint("CENTER")
		self.Label:SetText(string.format("%d/%d", data.done, data.total))
		if data.done >= data.total then
			self.Label:SetTextColor(0.55, 0.55, 0.55)
		else
			self.Label:SetTextColor(1, 0.82, 0)
		end
		self.Label:Show()
		self:SetSize((self.Label:GetStringWidth() or 30) + 10, 15)
	end
	self:SetPosition(data.x, data.y)
end

function PinMethods:OnReleased()
	if self.widgetContainer then
		self.widgetContainer:UnregisterForWidgetSet()
	end
	if self.RemoveAllTags then
		self:RemoveAllTags()
	end
	if GameTooltip:GetOwner() == self then
		GameTooltip:Hide()
	end
end

function PinMethods:OnMouseEnter()
	local data = self.data
	if not data then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if self.kind == "giver" then
		GameTooltip:SetText(data.giver ~= "" and data.giver or "Quest giver", 1, 0.82, 0)
		for _, q in ipairs(data.quests) do
			local row = q.row
			local r, g, b = QL.DifficultyColor(row[QL.F_LEVEL])
			local text = STATE_TEXT[q.state]
			GameTooltip:AddDoubleLine(string.format("%s (%d)", row[QL.F_TITLE], row[QL.F_LEVEL]), text[1], r, g, b, text[2], text[3], text[4])
			local step, total, nextRow = QL.ChainInfo(row)
			if step then
				local chain = QL.Data().chains[row[QL.F_CHAIN]] or "chain"
				local line = string.format("   Step %d of %d in %s", step, total, chain)
				if nextRow and q.state ~= "done" then
					line = line .. ", next: " .. nextRow[QL.F_TITLE]
				end
				GameTooltip:AddLine(line, 0.6, 0.6, 0.6, true)
			end
		end
		if data.tracked then
			GameTooltip:AddLine("Tracked. Click to remove the waypoint.", 0.6, 0.8, 1)
		else
			GameTooltip:AddLine("Click to set a waypoint on this giver.", 0.6, 0.8, 1)
		end
	elseif self.kind == "entrance" then
		GameTooltip:SetText(data.name, 1, 0.82, 0)
		local lv = data.dungeonID ~= 0 and QL.Data().dungeonLevel and QL.Data().dungeonLevel[data.dungeonID]
		local what = data.raid and "Raid" or "Dungeon"
		if lv and lv[1] > 0 then
			GameTooltip:AddLine(string.format("%s, level %d to %d", what, lv[1], lv[2] > 0 and lv[2] or lv[1]), 0.8, 0.8, 0.8)
		else
			GameTooltip:AddLine(what, 0.8, 0.8, 0.8)
		end
		if data.dungeonID ~= 0 then
			local done, total = DungeonProgress(data.dungeonID)
			if total > 0 then
				GameTooltip:AddLine(string.format("%d of %d quests completed", done, total), done >= total and 0.5 or 1, done >= total and 0.5 or 0.82, done >= total and 0.5 or 0)
				GameTooltip:AddLine("Click to list its quests. Shift-click to route there.", 0.6, 0.8, 1)
			else
				GameTooltip:AddLine("No quests known for it yet.", 0.6, 0.6, 0.6)
				GameTooltip:AddLine("Shift-click to route there.", 0.6, 0.8, 1)
			end
		end
		if data.source == "learned" then
			GameTooltip:AddLine("Position learned when you walked in.", 0.6, 0.6, 0.6)
		elseif data.source == "client" then
			GameTooltip:AddLine("Position from the client's own entrance list.", 0.6, 0.6, 0.6)
		end
	elseif self.kind == "transport" then
		GameTooltip:SetText(data.label, 1, 0.82, 0)
		GameTooltip:AddLine((data.kind == 2 and "Zeppelin tower" or "Dock") .. " at " .. data.dock, 0.8, 0.8, 0.8)
		if data.faction == 1 then
			GameTooltip:AddLine("Alliance", 0.3, 0.6, 1)
		elseif data.faction == 2 then
			GameTooltip:AddLine("Horde", 1, 0.3, 0.3)
		else
			GameTooltip:AddLine("Neutral, both factions", 0.8, 0.8, 0.8)
		end
		if data.destMapID or data.destCont then
			GameTooltip:AddLine("Click to route to it. Shift-click to open the destination's map.", 0.6, 0.8, 1)
		end
		if data.learned then
			GameTooltip:AddLine("Recorded with /qlmap dock. Remove with /qlmap remove.", 0.6, 0.6, 0.6)
		end
	else
		GameTooltip:SetText(data.name, 1, 0.82, 0)
		GameTooltip:AddLine(string.format("%d of %d quests completed", data.done, data.total), 0.9, 0.9, 0.9)
		if data.lo > 0 then
			GameTooltip:AddLine(string.format("Quest levels %d to %d", data.lo, data.hi), 0.8, 0.8, 0.8)
		end
		if data.available > 0 then
			GameTooltip:AddLine(string.format("%d you could pick up now", data.available), 1, 0.82, 0)
		end
		if data.inLog > 0 then
			GameTooltip:AddLine(string.format("%d in your quest log", data.inLog), 0.7, 0.7, 0.7)
		end
		GameTooltip:AddLine("Click to open the zone map.", 0.6, 0.8, 1)
	end
	GameTooltip:Show()
end

function PinMethods:OnMouseLeave()
	GameTooltip:Hide()
end

function PinMethods:OnMouseClickAction(button)
	local data = self.data
	if not data or button ~= "LeftButton" then
		return
	end
	if self.kind == "giver" then
		if data.tracked then
			QL.ClearWaypoint()
			PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_REMOVE or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		elseif QL.SetWaypoint(data.quests[1].row, data.quests[1].state == "ready") then
			PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_CLICK_TO_PLACE or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		end
		QL.Panel:Update()
		QL.RefreshPins()
	elseif self.kind == "entrance" then
		if IsShiftKeyDown() then
			-- Shift-click routes to the door; a plain click lists its quests.
			local map = self:GetMap()
			local mapID = map and QL.Plain(map:GetMapID())
			local icon = data.raid and "|A:Raid:16:16|a " or "|A:Dungeon:16:16|a "
			local what = data.raid and "raid" or "dungeon"
			if QL.RouteToPoint(mapID, data.x, data.y, icon .. data.name,
				string.format("%sTracking the %s entrance of %s, {dist} away", icon, what, data.name)) then
				PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_CLICK_TO_PLACE or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			end
		elseif data.dungeonID ~= 0 and QL.byDungeon and QL.byDungeon[data.dungeonID] then
			-- Show the instance's quests: switch the panel, fold the others,
			-- scroll to it, and say so with a sound and a notice.
			for id in pairs(QL.Data().dungeons or {}) do
				QL.collapsed["dungeon" .. id] = (id ~= data.dungeonID) or nil
			end
			QL.Panel:Reveal("dungeon" .. data.dungeonID, data.raid and "raids" or "dungeons")
			if MelloUI.PlayUISound then
				MelloUI:PlayUISound("page")
			end
			local done, total = DungeonProgress(data.dungeonID)
			local icon = data.raid and "|A:Raid:18:18|a " or "|A:Dungeon:18:18|a "
			local text = string.format("%s%s: %d quests listed, %d done", icon, data.name, total or 0, done or 0)
			local R = MelloUI.Route
			if R and R.isEnabled and R.Notify then
				R:Notify(text, "silent")
			end
		end
	elseif self.kind == "transport" and not IsShiftKeyDown() then
		local map = self:GetMap()
		local mapID = map and QL.Plain(map:GetMapID())
		local what = data.kind == 2 and "zeppelin" or "boat"
		local icon = "|A:TaxiNode_Neutral:16:16|a "
		if QL.RouteToPoint(mapID, data.x, data.y, icon .. data.label,
			string.format("%sTracking the %s to %s, {dist} away", icon, what, data.label)) then
			PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_CLICK_TO_PLACE or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		end
	elseif self.kind == "transport" then
		local map = self:GetMap()
		local target = data.destMapID
		if not target and data.destCont and C_Map.GetMapPosFromWorldPos and CreateVector2D then
			local ok, contMapID, pos = pcall(C_Map.GetMapPosFromWorldPos, data.destCont, CreateVector2D(data.destX, data.destY))
			contMapID = ok and QL.Plain(contMapID) or nil
			local cx, cy = QL.VectorXY(pos)
			target = contMapID
			if contMapID and cx and cy and C_Map.GetMapInfoAtPosition then
				local okZ, zinfo = pcall(C_Map.GetMapInfoAtPosition, contMapID, cx, cy)
				local zoneMapID = okZ and type(zinfo) == "table" and QL.Plain(zinfo.mapID) or nil
				if zoneMapID then
					target = zoneMapID
				end
			end
		end
		if map and map.SetMapID and target then
			map:SetMapID(target)
		end
	elseif data.mapID then
		local map = self:GetMap()
		if map and map.SetMapID then
			map:SetMapID(data.mapID)
		end
	end
end

local function PreparePinMixin()
	if QL.PinMixin.SetPosition and QL.PinMixin.OnMouseClickAction then
		return true
	end
	if not MapCanvasPinMixin then
		return false
	end
	Mixin(QL.PinMixin, MapCanvasPinMixin, PinMethods)
	return true
end
PreparePinMixin()

QL.Provider = nil

local function AddGiverPins(map, mapID, mapName)
	local level = QL.Plain(UnitLevel("player")) or 60
	local groups, order = {}, {}
	local function Consider(row, x, y, who, state)
		local key = string.format("%s|%.3f|%.3f", who, x, y)
		local group = groups[key]
		if not group then
			group = { giver = who, x = x, y = y, quests = {}, state = "done", tracked = false }
			groups[key] = group
			order[#order + 1] = group
		end
		group.quests[#group.quests + 1] = { row = row, state = state }
		if STATE_RANK[state] > STATE_RANK[group.state] then
			group.state = state
		end
		if QL.trackedQuestID == row[QL.F_ID] then
			group.tracked = true
		end
	end
	local seen = {}
	-- A quest ready to hand in is pinned at its turn-in, everything else at its giver.
	local function Place(row, endOnly)
		if seen[row] or not QL.Eligible(row) then
			return
		end
		local state = QuestState(row, level)
		local x, y, who
		if state == "ready" and QL.resolvedEnd[row] then
			x, y = QL.ProjectOnMap(QL.resolvedEnd[row], mapID)
			who = row[QL.F_ENDER]
		elseif not endOnly and QL.resolved[row] then
			x, y = QL.ProjectOnMap(QL.resolved[row], mapID)
			who = row[QL.F_GIVER]
		end
		if x then
			seen[row] = true
			Consider(row, x, y, who, state)
		end
	end
	-- Rows the client placed on this map or on a city inside it.
	local maps = { mapID }
	local okC, children = pcall(C_Map.GetMapChildrenInfo, mapID)
	if okC and type(children) == "table" then
		for _, child in ipairs(children) do
			if QL.Plain(child.mapID) then
				maps[#maps + 1] = child.mapID
			end
		end
	end
	for _, id in ipairs(maps) do
		for _, row in ipairs(QL.rowsByMap and QL.rowsByMap[id] or {}) do
			Place(row, false)
		end
		for _, row in ipairs(QL.endRowsByMap and QL.endRowsByMap[id] or {}) do
			Place(row, true)
		end
	end
	-- Givers with a map percentage only (collected in game on this zone).
	local areaID = QL.zoneByName[mapName:lower()]
	for _, row in ipairs(areaID and QL.byZone[areaID] or {}) do
		if not seen[row] and not (QL.resolved and QL.resolved[row]) and (row[QL.F_X] ~= 0 or row[QL.F_Y] ~= 0) and QL.Eligible(row) then
			seen[row] = true
			Consider(row, row[QL.F_X] / 100, row[QL.F_Y] / 100, row[QL.F_GIVER], QuestState(row, level))
		end
	end
	for _, group in ipairs(order) do
		if group.state ~= "done" or M.db.pinCompleted or group.tracked then
			table.sort(group.quests, function(a, b) return QL.ByLevel(a.row, b.row) end)
			map:AcquirePin(QL.PIN_TEMPLATE, "giver", group)
		end
	end
end

local function AddZoneBadges(map, continentMapID)
	local ok, children = pcall(C_Map.GetMapChildrenInfo, continentMapID, MAP_ZONE, false)
	if not ok or type(children) ~= "table" then
		return
	end
	local level = QL.Plain(UnitLevel("player")) or 60
	for _, child in ipairs(children) do
		local name = QL.Plain(child.name)
		local areaID = name and QL.zoneByName[name:lower()]
		local rows = areaID and QL.byZone[areaID]
		if rows then
			local done, total, available, inLog, lo, hi = 0, 0, 0, 0, 0, 0
			for _, row in ipairs(rows) do
				if QL.Eligible(row) then
					total = total + 1
					local state = QuestState(row, level)
					if state == "done" then
						done = done + 1
					elseif state == "available" then
						available = available + 1
					elseif state == "ready" or state == "progress" then
						inLog = inLog + 1
					end
					local lv = row[QL.F_LEVEL]
					if lv > 0 then
						if lo == 0 or lv < lo then lo = lv end
						if lv > hi then hi = lv end
					end
				end
			end
			local okR, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, child.mapID, continentMapID)
			if total > 0 and okR and QL.Plain(minX) and QL.Plain(maxX) and QL.Plain(minY) and QL.Plain(maxY) then
				map:AcquirePin(QL.PIN_TEMPLATE, "badge", {
					mapID = child.mapID, name = name, done = done, total = total, available = available, inLog = inLog,
					lo = lo, hi = hi, x = (minX + maxX) / 2, y = (minY + maxY) / 2,
				})
			end
		end
	end
end


--------------------------------------------------------------------------------
-- Instance entrances and transports
--------------------------------------------------------------------------------

-- Where a world point lies on the map shown. The client's own map assignment
-- is used when it has the API; else the build-time zone guess.
QL.lastPointTrace = {}

local function WorldPointOnMap(mapID, mapName, cont, wx, wy, zoneArea, px, py)
	local res = QL.ResolveWorld(cont, wx, wy)
	if res then
		local x, y = QL.ProjectOnMap(res, mapID)
		if x then
			return x, y
		end
		return nil
	end
	if C_Map.GetMapPosFromWorldPos then
		QL.lastPointTrace[#QL.lastPointTrace + 1] = string.format("point (%d, %.0f, %.0f): the client could not place it", cont, wx, wy)
	end
	if zoneArea ~= 0 and QL.zoneByName[mapName:lower()] == zoneArea then
		return px / 100, py / 100
	end
	return nil
end

-- Dungeon entrances the client itself knows for a map (retail-style API).
function QL.ClientEntrances(mapID)
	local out = {}
	if not (C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap) then
		return out
	end
	local ok, list = pcall(C_EncounterJournal.GetDungeonEntrancesForMap, mapID)
	if not ok or type(list) ~= "table" then
		return out
	end
	for _, info in ipairs(list) do
		local name = QL.Plain(info.name)
		local x, y = QL.VectorXY(info.position)
		if name and x and y then
			local atlas = QL.Plain(info.atlasName) or ""
			out[#out + 1] = { name = name, x = x, y = y, raid = atlas:lower():find("raid") ~= nil }
		end
	end
	return out
end

-- Points of interest the map itself shows, with name, position and icon.
function QL.ClientPOIs(mapID)
	local out = {}
	if not (C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap and C_AreaPoiInfo.GetAreaPOIInfo) then
		return out
	end
	local ok, ids = pcall(C_AreaPoiInfo.GetAreaPOIForMap, mapID)
	if not ok or type(ids) ~= "table" then
		return out
	end
	for _, poiID in ipairs(ids) do
		local okI, info = pcall(C_AreaPoiInfo.GetAreaPOIInfo, mapID, poiID)
		if okI and type(info) == "table" then
			local name = QL.Plain(info.name)
			local x, y = QL.VectorXY(info.position)
			if name and x and y then
				out[#out + 1] = { name = name, x = x, y = y, atlas = QL.Plain(info.atlasName) or "", description = QL.Plain(info.description) or "" }
			end
		end
	end
	return out
end

-- A point of interest that is an instance door: named like one of our
-- dungeons, or drawn with the dungeon / raid icon.
function QL.IsEntrancePOI(poi)
	if DungeonIDByName(poi.name) ~= 0 then
		return true
	end
	local atlas = poi.atlas:lower()
	return atlas:find("dungeon") ~= nil or atlas:find("raid") ~= nil
end

local function AddEntrancePins(map, mapID, mapName)
	local data = QL.Data()
	local names = {}
	for _, e in ipairs(data.entrances or {}) do
		names[e[2]:lower()] = true
		local x, y = WorldPointOnMap(mapID, mapName, e[3], e[4], e[5], e[6], e[7], e[8])
		if x then
			map:AcquirePin(QL.PIN_TEMPLATE, "entrance", { dungeonID = e[1], name = e[2], raid = e[9] == 2, x = x, y = y, source = "data" })
		end
	end
	-- Entrances learned by walking in (Forever's new instances).
	for name, l in pairs(QL.LearnedStore("entrances")) do
		if l.mapID == mapID and not names[name:lower()] then
			names[name:lower()] = true
			map:AcquirePin(QL.PIN_TEMPLATE, "entrance", { dungeonID = DungeonIDByName(name), name = name, raid = l.raid == true, x = l.x, y = l.y, source = "learned" })
		end
	end
	-- The client's own entrance list for the map, when this build has one.
	for _, e in ipairs(QL.ClientEntrances(mapID)) do
		if not names[e.name:lower()] then
			names[e.name:lower()] = true
			map:AcquirePin(QL.PIN_TEMPLATE, "entrance", { dungeonID = DungeonIDByName(e.name), name = e.name, raid = e.raid, x = e.x, y = e.y, source = "client" })
		end
	end
	-- Points of interest that are instance doors.
	for _, poi in ipairs(QL.ClientPOIs(mapID)) do
		if QL.IsEntrancePOI(poi) and not names[poi.name:lower()] then
			names[poi.name:lower()] = true
			local id = DungeonIDByName(poi.name)
			map:AcquirePin(QL.PIN_TEMPLATE, "entrance", { dungeonID = id, name = poi.name, raid = (id ~= 0 and QL.Data().raids[id] == true) or poi.atlas:lower():find("raid") ~= nil, x = poi.x, y = poi.y, source = "client" })
		end
	end
end

local function AddTransportPins(map, mapID, mapName)
	for _, t in ipairs(QL.Data().transports or {}) do
		local x, y = WorldPointOnMap(mapID, mapName, t[5], t[6], t[7], t[8], t[9], t[10])
		if x then
			map:AcquirePin(QL.PIN_TEMPLATE, "transport", {
				kind = t[1], faction = t[2], label = t[3], dock = t[4], x = x, y = y,
				destCont = t[11], destX = t[12], destY = t[13],
			})
		end
	end
	-- Docks recorded with /qlmap dock (routes the vanilla data cannot know).
	for label, l in pairs(QL.LearnedStore("transports")) do
		if l.mapID == mapID then
			map:AcquirePin(QL.PIN_TEMPLATE, "transport", {
				kind = l.kind or 1, faction = l.faction or 0, label = label, dock = l.dock or mapName, x = l.x, y = l.y,
				destMapID = l.destMapID, learned = true,
			})
		end
	end
end

-- Player's map and position, for recording pins by hand.
function QL.PlayerMapPoint()
	local okM, mapID = pcall(C_Map.GetBestMapForUnit, "player")
	mapID = okM and QL.Plain(mapID) or nil
	if not mapID then
		return nil
	end
	local okP, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
	local x, y
	if okP then
		x, y = QL.VectorXY(pos)
	end
	if not (x and y) then
		return nil
	end
	local subzone = QL.Plain(GetSubZoneText and GetSubZoneText()) or ""
	return mapID, x, y, subzone ~= "" and subzone or (QL.ZoneNameForMap(mapID) or "here")
end

-- The last outdoor position seen before a loading screen: when the next map
-- is a dungeon or raid the data has no entrance for, that is where it is.
local lastOutside = nil

function QL.RememberOutside()
	local okI, inInstance = pcall(IsInInstance)
	if not okI or inInstance then
		return
	end
	local okM, mapID = pcall(C_Map.GetBestMapForUnit, "player")
	mapID = okM and QL.Plain(mapID) or nil
	if not mapID then
		return
	end
	local okP, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
	local x, y
	if okP then
		x, y = QL.VectorXY(pos)   -- pos.x is a secret value on this client; VectorXY falls back to GetXY
	end
	if x and y and x > 0 and y > 0 then
		lastOutside = { mapID = mapID, x = x, y = y, at = GetTime() }
	end
end

-- Zone events alone are too sparse (a fight in one subzone can last minutes),
-- so the outdoor position is also refreshed on a slow ticker.
local outsideTicker = nil
function QL.StartOutsideTicker()
	if outsideTicker or not C_Timer.NewTicker then
		return
	end
	outsideTicker = C_Timer.NewTicker(3, QL.RememberOutside)
end

local learnFailed = nil   -- instance name already reported this session
QL.pendingExit = nil   -- { name, raid }: instance to learn from where the player exits it

-- Returns true when done (learned, already known, or not applicable); false
-- when the instance is not readable yet and a retry is worth it.
function QL.LearnEntrance()
	local okI, inInstance, kind = pcall(IsInInstance)
	if not okI or not inInstance or (kind ~= "party" and kind ~= "raid") then
		return true
	end
	local okN, name = pcall(GetInstanceInfo)
	name = okN and QL.Plain(name) or nil
	if not name or name == "" then
		return false
	end
	for _, e in ipairs(QL.Data().entrances or {}) do
		if e[2]:lower() == name:lower() then
			return true
		end
	end
	local learned = QL.LearnedStore("entrances")
	if learned[name] then
		return true
	end
	if not lastOutside or GetTime() - lastOutside.at > 180 then
		-- No position from before the loading screen (reloaded inside, for
		-- instance). Leaving the instance puts the player at its door, so the
		-- entrance is learned on the way out instead.
		QL.pendingExit = { name = name, raid = kind == "raid" }
		if learnFailed ~= name then
			learnFailed = name
			MelloUI:Notice("Quest List: the entrance of %s will be put on the map when you walk out of it.", name)
		end
		return true
	end
	learned[name] = { mapID = lastOutside.mapID, x = lastOutside.x, y = lastOutside.y, raid = kind == "raid" }
	MelloUI:Notice("Quest List: learned where the entrance of %s is; it is on the zone map now.", name)
	QL.RefreshPins()
	return true
end

-- After leaving an instance whose entrance is unknown, the first readable
-- outdoor position is the door. Polls for a few seconds because the position
-- is not readable right after the loading screen.
function QL.LearnEntranceOnExit(attempt)
	local pending = QL.pendingExit
	if not pending then
		return
	end
	local okI, inInstance = pcall(IsInInstance)
	if not okI or inInstance then
		return
	end
	local mapID, x, y = QL.PlayerMapPoint()
	if not mapID then
		if (attempt or 1) < 10 then
			C_Timer.After(1, function() QL.LearnEntranceOnExit((attempt or 1) + 1) end)
		end
		return
	end
	QL.pendingExit = nil
	local learned = QL.LearnedStore("entrances")
	if learned[pending.name] then
		return
	end
	learned[pending.name] = { mapID = mapID, x = x, y = y, raid = pending.raid }
	MelloUI:Notice("Quest List: learned where the entrance of %s is; it is on the zone map now.", pending.name)
	QL.RefreshPins()
end

QL.lastPinErrors, QL.lastPinInfo = {}, nil

-- Blizzard's flight point pins: a click also routes to the flight master.
-- Each pin is hooked once, a frame after the map refreshed (its provider has
-- made the pins for the map by then).
local function FlightPinClicked(pin, button)
	if button ~= "LeftButton" or IsShiftKeyDown() or not M.isEnabled then
		return
	end
	local map = pin.GetMap and pin:GetMap()
	local mapID = map and QL.Plain(map:GetMapID())
	local okP, x, y = pcall(pin.GetPosition, pin)
	x, y = okP and QL.Plain(x) or nil, okP and QL.Plain(y) or nil
	local info = pin.poiInfo
	local name = info and QL.Plain(info.name) or "Flight master"
	if mapID and x and y then
		local icon = "|T" .. "Interface/Minimap/Tracking/FlightMaster" .. ":16:16|t "
		QL.RouteToPoint(mapID, x, y, icon .. name, string.format("%sTracking the flight master at %s, {dist} away", icon, name))
	end
end

local function HookFlightPins(map)
	if map and map.EnumeratePinsByTemplate then
		-- EnumeratePinsByTemplate hands back a generic-for triple (next, set, nil)
		local ok, f, state, init = pcall(map.EnumeratePinsByTemplate, map, "FlightPointPinTemplate")
		if ok and type(f) == "function" then
			for pin in f, state, init do
				if not pin.melloFlightHooked and pin.OnMouseClickAction then
					pin.melloFlightHooked = true
					hooksecurefunc(pin, "OnMouseClickAction", FlightPinClicked)
				end
			end
		end
	end
end

function QL.CreateProvider()
	if QL.Provider or not (MapCanvasDataProviderMixin and WorldMapFrame and WorldMapFrame.AddDataProvider) then
		return
	end
	if not PreparePinMixin() then
		return
	end
	QL.Provider = CreateFromMixins(MapCanvasDataProviderMixin)
	function QL.Provider:RemoveAllData()
		self:GetMap():RemoveAllPinsByTemplate(QL.PIN_TEMPLATE)
	end
	function QL.Provider:RefreshAllData()
		self:RemoveAllData()
		if not (M.isEnabled and QL.byZone) then
			return
		end
		local map = self:GetMap()
		C_Timer.After(0, function() HookFlightPins(map) end)
		local mapID = QL.Plain(map:GetMapID())
		local okI, info = pcall(C_Map.GetMapInfo, mapID)
		if not mapID or not okI or type(info) ~= "table" then
			return
		end
		local mapType, name = QL.Plain(info.mapType), QL.Plain(info.name)
		wipe(QL.lastPointTrace)
		QL.lastPinErrors = {}
		QL.lastPinInfo = { mapID = mapID, name = name, mapType = mapType }
		local function Try(label, fn, ...)
			local ok, err = pcall(fn, ...)
			if not ok then
				QL.lastPinErrors[#QL.lastPinErrors + 1] = label .. ": " .. tostring(err)
			end
		end
		if mapType == MAP_ZONE and name then
			if M.db.mapPins then
				Try("quest givers", AddGiverPins, map, mapID, name)
			end
			if M.db.entrancePins then
				Try("entrances", AddEntrancePins, map, mapID, name)
			end
			if M.db.transportPins then
				Try("transports", AddTransportPins, map, mapID, name)
			end
		elseif mapType == MAP_CONTINENT and M.db.zoneBadges then
			Try("zone badges", AddZoneBadges, map, mapID)
		end
	end
	WorldMapFrame:AddDataProvider(QL.Provider)
end

QL.RefreshPins = function()
	if QL.Provider and WorldMapFrame and WorldMapFrame:IsShown() then
		QL.Provider:RefreshAllData()
	end
end

MelloUI:Profile("QuestList", "map pins", QL.RefreshPins)
