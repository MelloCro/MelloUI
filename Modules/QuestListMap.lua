--------------------------------------------------------------------------------
-- MelloUI - Quest List: map pins
--
-- Quest giver pins and zone badges, instance entrances and transports, how
-- entrances are learned, and the click hooks on the client's flight master
-- pins. Shares its data and helpers with QuestList.lua through ns.QuestList (QL).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("QuestListMap")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
local QL = ns.QuestList
local M = QL.M
-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Finite = MelloUI.Safe.Finite
-- (the marks' layer is made while the map is open: Core's maker, WINDOW-RULES)
local CreateFrame = MelloUI.Safe.CreateFrame

--------------------------------------------------------------------------------
-- Map pins
--
-- Zone maps: one pin per quest giver location, showing what you can do there
-- (yellow ! pick up, yellow ? turn in, grey ? in progress, grey ! too low,
-- grey tick all done). Continent maps: a done/total badge on every zone.
-- Laid by the map's own data provider system (its refresh, its zoom), drawn
-- on MelloUI's own layer on the canvas (0.16.0: "The marks' own layer",
-- below), so they pan and zoom with the map in both modes.
--------------------------------------------------------------------------------

local MAP_ZONE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
local MAP_CONTINENT = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2

-- Priority of what a giver offers, highest wins the icon.
local STATE_RANK = { ready = 5, available = 4, progress = 3, locked = 2, done = 1 }
-- (a state's words, and its colour's name for QL.TipColour: the quest gold
-- for what can be done now, the body text for the rest)
local STATE_TEXT = {
	ready = { "Ready to turn in", "questGold" },
	available = { "Available", "questGold" },
	progress = { "In progress", "text" },
	locked = { "Level too low", "text" },
	done = { "Completed", "text" },
}

local TRANSPORT_ATLAS = {
	[0] = { "taxinode_continent_neutral_timed", "TaxiNode_Neutral" },
	[1] = { "taxinode_continent_alliance_timed", "TaxiNode_Alliance" },
	[2] = { "taxinode_continent_horde_timed", "TaxiNode_Horde" },
}

-- A quest found only inside a dungeon or raid is pinned beside its entrance.
local BESIDE_DOOR_X, BESIDE_DOOR_Y = 20, 10   -- pixels: off the entrance pin's own icon

-- Not every atlas of the retail engine is in this client's art; try in turn.
local function SetFirstAtlas(tex, list)
	for _, atlas in ipairs(list) do
		if pcall(tex.SetAtlas, tex, atlas) and tex:GetAtlas() then
			return true
		end
	end
	tex:SetTexture("Interface/Minimap/Tracking/None")
	tex:SetTexCoord(0, 1, 0, 1)
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

--------------------------------------------------------------------------------
-- The marks' own layer (0.16.0; the gamepad freeze plan's F3, the user's
-- "bring the Quest List map markers back in the Gamepad UI"). The marks are
-- MelloUI's own frames, never pins in the map's pools (the game's gamepad
-- cursor, pan and zoom go over the pools every frame, and pool calls made
-- from MelloUI's code wrote the map's scroll state: the 0.15.0 freeze), and
-- not among the map's own frames either (the navigation walks those): they
-- hang in the Quest List's holder beside the map (QL.MapHolder, the
-- panel's), which follows the map's show, alpha, scale, strata and level.
--   the anchors  one invisible 1-unit texture per mark on the map's canvas,
--                at its map spot in the canvas's own units: the canvas's pan
--                and zoom move them with no code at all (textures, not
--                frames: nothing for the navigation to walk). Laid when the
--                marks are, and when the canvas changes size
--   the clip     a frame over the map's scroll area in the holder (it clips
--                what lies outside it), laid over the map's own pins
--   the marks    buttons in the clip, each hung on its anchor: one size on
--                the screen at every zoom, and no work of ours per frame
-- The mouse: each mark is a button (hover: its tooltip; click: its action;
-- a zone badge that opens its zone leaves its click to the map). The Gamepad
-- UI: the marks take no mouse (nothing for the navigation to walk to); while
-- the map is focused a light check (THROTTLE s) finds the mark nearest the
-- soft cursor (the map's own normalized position of it, against the marks'
-- spots worked out when they were laid) and shows its tooltip, and the A
-- press (a post-hook on the map's GamepadMapClick: it runs after the game's
-- click and move, and does its work on the next frame) is its click. One
-- system for both: made with the map's first refresh, nothing at login.
--------------------------------------------------------------------------------

local Marks = { list = {}, n = 0, anchors = {}, buttons = {}, xs = {}, ys = {}, clip = nil, hovered = nil,
	gamepad = false, wait = 0, hooked = false }
QL.Marks = Marks
local THROTTLE = 0.1             -- s between two gamepad hover checks
local HOVER_PX = 16              -- the soft cursor's reach round a mark, in screen pixels
local ANCHOR_SIZE = 1

-- a mark as the pools had it: its kind and data (a giver's group, a badge's
-- counts, an entrance, a transport), laid by Marks.End
function Marks.Add(kind, data)
	local n = Marks.n + 1
	local m = Marks.list[n]
	if not m then
		m = {}
		Marks.list[n] = m
	end
	m.kind, m.data = kind, data
	Marks.n = n
end

-- the marks now, for /qlmap and the tests: { kind, x, y } each (read only)
function QL.MarkList()
	local out = {}
	for i = 1, Marks.n do
		local m = Marks.list[i]
		out[i] = { kind = m.kind, x = m.data.x, y = m.data.y, data = m.data }
	end
	return out
end

local MarkEnter, MarkLeave, MarkClick   -- (below)
local Level   -- (below)

local function Clip(map)
	local clip = Marks.clip
	if clip then
		return clip
	end
	local holder = QL.MapHolder()
	clip = CreateFrame("Frame", nil, holder)
	clip:SetAllPoints(map.ScrollContainer or map:GetCanvas())
	if clip.SetClipsChildren then
		clip:SetClipsChildren(true)
	end
	Marks.clip = clip
	holder.onLevel = function()
		Level(map)
	end
	Perf.SetScript(clip, "OnHide", function()
		MarkLeave()
	end)
	return clip
end

-- above the map's own pins (their levels are the map's: read at each lay)
local function TopLevel(...)
	local top = 0
	for i = 1, select("#", ...) do
		local child = select(i, ...)
		local ok, lv = pcall(child.GetFrameLevel, child)
		if ok and type(lv) == "number" and lv > top then
			top = lv
		end
	end
	return top
end

local function MarkButton(i)
	local b = Marks.buttons[i]
	if b then
		return b
	end
	b = CreateFrame("Button", nil, Marks.clip)
	b:SetSize(22, 22)
	b:RegisterForClicks("LeftButtonUp")
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(b)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(b)
	local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetJustifyH("CENTER")
	label:SetPoint("CENTER")
	b.Bg, b.Icon, b.Label = bg, icon, label
	Perf.SetScript(b, "OnEnter", MarkEnter)
	Perf.SetScript(b, "OnLeave", MarkLeave)
	Perf.SetScript(b, "OnClick", MarkClick)
	Marks.buttons[i] = b
	return b
end

-- (an anchor: an empty texture on the canvas, never drawn)
local function Anchor(map, i)
	local a = Marks.anchors[i]
	if not a then
		a = map:GetCanvas():CreateTexture(nil, "BACKGROUND")
		a:SetSize(ANCHOR_SIZE, ANCHOR_SIZE)
		Marks.anchors[i] = a
	end
	return a
end

-- the anchors at the marks' map spots, in the canvas's own units, and the
-- spots kept for the hover check (a finite place only: a learned or badge
-- place read from saved data is never handed on as NaN or endless)
function Marks.Anchor(map)
	local canvas = map:GetCanvas()
	local W, H = QL.Plain(canvas:GetWidth()), QL.Plain(canvas:GetHeight())
	if not (W and H and W > 0 and H > 0 and W < math.huge and H < math.huge) then
		return
	end
	local xs, ys = Marks.xs, Marks.ys
	for i = 1, Marks.n do
		local d = Marks.list[i].data
		local x, y = Finite(d.x), Finite(d.y)
		local b = Marks.buttons[i]
		xs[i], ys[i] = x or false, y or false
		if x and y then
			local a = Anchor(map, i)
			a:ClearAllPoints()
			a:SetPoint("CENTER", canvas, "TOPLEFT", x * W, -y * H)
		elseif b then
			b:Hide()
		end
	end
end

-- the clip over the map's own pins, at the map's strata (their levels are the
-- map's: read at each lay, and when the map is raised)
Level = function(map)
	local clip = Marks.clip
	if not clip then
		return
	end
	local strata = map:GetFrameStrata()
	if clip:GetFrameStrata() ~= strata then
		clip:SetFrameStrata(strata)
	end
	local level = TopLevel(map:GetCanvas():GetChildren()) + 1
	if clip:GetFrameLevel() ~= level then
		clip:SetFrameLevel(level)
	end
end

-- the mouse to the marks (off in the Gamepad UI: the soft cursor's check,
-- below, stands for it); a badge that opens its zone leaves its click to the
-- map under it
local function Mouse(b)
	local on = not Marks.gamepad
	b:EnableMouse(on)
	if on and b.SetMouseClickEnabled then
		b:SetMouseClickEnabled(b.kind ~= "badge" or not b.data.opens)
	end
end

local Watch   -- (the gamepad hover check, below)

-- the marks laid on the map: every mark added since Marks.Begin
function Marks.End(map)
	Clip(map)
	Level(map)
	Marks.gamepad = MelloUI.Safe.GamepadUI()
	Marks.Anchor(map)
	for i = 1, Marks.n do
		local m, b = Marks.list[i], MarkButton(i)
		b.kind, b.data = m.kind, m.data
		QL.DressMark(b, m.kind, m.data)
		b:ClearAllPoints()
		if Marks.xs[i] then
			b:SetPoint("CENTER", Marks.anchors[i], "CENTER", 0, 0)
			Mouse(b)
			b:Show()
		else
			b:Hide()
		end
	end
	for i = Marks.n + 1, #Marks.buttons do
		local b = Marks.buttons[i]
		b.kind, b.data = nil, nil
		b:Hide()
	end
	Watch()
end

function Marks.Begin()
	for i = 1, Marks.n do
		Marks.list[i].data = nil
	end
	Marks.n = 0
end

function Marks.Clear()
	Marks.Begin()
	MarkLeave()
	for i = 1, #Marks.buttons do
		local b = Marks.buttons[i]
		b.kind, b.data = nil, nil
		b:Hide()
	end
	Watch()
end

-- The Gamepad UI's hover: while the map shows and is focused, every THROTTLE
-- seconds, the mark nearest the soft cursor (the map's own normalized
-- position of it) within HOVER_PX shows its tooltip: plain sums over the
-- spots kept at the lay, the canvas's screen size read once. Our own frame's
-- script, never the map's per-frame work; set only while there are marks.
local function Nearest()
	local map = WorldMapFrame
	local ok, cx, cy = pcall(map.GetNormalizedCursorPosition, map)
	cx, cy = ok and QL.Plain(cx) or nil, ok and QL.Plain(cy) or nil
	local canvas = map:GetCanvas()
	local W, H = QL.Plain(canvas:GetWidth()), QL.Plain(canvas:GetHeight())
	local s = QL.Plain(canvas:GetEffectiveScale())
	if not (cx and cy and W and H and s) then
		return nil
	end
	local pw, ph = W * s, H * s   -- the canvas in screen pixels
	local xs, ys = Marks.xs, Marks.ys
	local best, bestD = nil, HOVER_PX * HOVER_PX
	for i = 1, Marks.n do
		local x, y = xs[i], ys[i]
		if x then
			local dx, dy = (x - cx) * pw, (y - cy) * ph
			local dist = dx * dx + dy * dy
			if dist <= bestD then
				best, bestD = Marks.buttons[i], dist
			end
		end
	end
	return best
end

local function HoverTick(self, elapsed)
	Marks.wait = Marks.wait - elapsed
	if Marks.wait > 0 then
		return
	end
	Marks.wait = THROTTLE
	local map = WorldMapFrame
	local focused = map and map.IsMapFocused and map:IsMapFocused()
	local b = focused and Nearest() or nil
	if b ~= Marks.hovered then
		MarkLeave()
		if b then
			MarkEnter(b)
		end
	end
end

Watch = function()
	local clip = Marks.clip
	if not clip then
		return
	end
	if Marks.gamepad and Marks.n > 0 then
		if not clip:GetScript("OnUpdate") then
			Marks.wait = 0
			Perf.SetScript(clip, "OnUpdate", HoverTick)
		end
	elseif clip:GetScript("OnUpdate") then
		Perf.SetScript(clip, "OnUpdate", nil)
		MarkLeave()
	end
end

-- the A press on the map (after the game's own click and move): the hovered
-- mark's click, on the next frame
local function GamepadClick()
	local b = Marks.hovered
	if b and Marks.gamepad and b.data then
		C_Timer.After(0, function()
			if b.data and b:IsVisible() then
				MarkClick(b, "LeftButton")
			end
		end)
	end
end

function Marks.Hook(map)
	if Marks.hooked or not map then
		return
	end
	local name = map.GamepadMapClick and "GamepadMapClick" or (map.ClickHoveredPins and "ClickHoveredPins")
	if name then
		Marks.hooked = true
		hooksecurefunc(map, name, GamepadClick)
	end
end

-- A mark dressed for its kind and data. (A zone badge leaves its click to the
-- map under it, Marks' Mouse: the map's own click opens that zone. A map
-- changed from MelloUI's code stays MelloUI's for the session, the map's id
-- and zoom read by every later change.)
function QL.DressMark(self, kind, data)
	self.Label:ClearAllPoints()
	self.Icon:ClearAllPoints()
	self.Icon:SetAllPoints()
	self:SetHitRectInsets(0, 0, 0, 0)
	if kind == "giver" then
		self.Bg:Hide()
		self.Icon:Show()
		self:SetSize(22, 22)
		local state = data.state
		if data.item == "dungeon" or data.item == "raid" then
			-- the icon (and where it takes the mouse) moved beside the entrance's door
			self.Icon:ClearAllPoints()
			self.Icon:SetPoint("CENTER", BESIDE_DOOR_X, BESIDE_DOOR_Y)
			self.Icon:SetSize(22, 22)
			self:SetHitRectInsets(BESIDE_DOOR_X, -BESIDE_DOOR_X, -BESIDE_DOOR_Y, BESIDE_DOOR_Y)
		end
		if data.item then
			-- a quest begun by an item or object: crossed swords where it drops
			-- from creatures, a chest where it is picked up, the entrance icon
			-- for an instance, instead of the "!"
			self:SetSize(20, 20)
			QL.SetStarterIcon(self.Icon, data.item)
			self.Icon:SetDesaturated(state ~= "available")
			self.Icon:SetAlpha(state == "available" and 1 or 0.75)
		elseif state == "done" then
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
		self.Label:SetPoint("TOP", self.Icon, "BOTTOM", 0, 2)
		self.Label:SetText(data.tracked and data.giver or "")
		-- the tracked giver's pale blue, as its tooltip hint: the map's
		-- quest-giver blue, a fixed meaning colour (QL.MEANING)
		self.Label:SetTextColor(QL.TipColour("pinHint"))
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
		-- a zone's badge in the palette as it is now (the pins are laid
		-- again on a new palette: QL.CreateProvider): its inner panel under
		-- the count, the count in its gold; once all are done, in its text
		-- colour a step down (QL.DONE_ALPHA, as the list's done quests:
		-- small text is never muted text)
		local palette = MelloUI.Palette
		local ground = palette.innerPanel
		local done = data.done >= data.total
		local ink = done and palette.text or palette.selectedTrim
		self.Icon:Hide()
		self.Bg:Show()
		self.Bg:SetColorTexture(ground[1], ground[2], ground[3], 0.7)
		self.Label:SetPoint("CENTER")
		self.Label:SetText(string.format("%d/%d", data.done, data.total))
		self.Label:SetTextColor(ink[1], ink[2], ink[3], done and QL.DONE_ALPHA or 1)
		self.Label:Show()
		self:SetSize((self.Label:GetStringWidth() or 30) + 10, 15)
	end
end

MarkEnter = function(self)
	local data = self.data
	if not data then
		return
	end
	Marks.hovered = self
	-- (the lines' colours by name, QL.TipLine: the palette's, or the Quest
	-- List's fixed meaning colours)
	local tip, Line = GameTooltip, QL.TipLine
	tip:SetOwner(self, "ANCHOR_RIGHT")
	if self.kind == "giver" then
		QL.TipTitle(tip, data.giver ~= "" and data.giver or "Quest giver")
		if data.item == "drop" then
			Line(tip, "Item that begins a quest, dropped by the creatures around here", "text", true)
		elseif data.item == "pickup" then
			Line(tip, "Item that begins a quest, picked up around here", "text", true)
		elseif data.item then
			Line(tip, string.format("Quests that begin with something found inside this %s:", data.item), "text", true)
		end
		for _, q in ipairs(data.quests) do
			local row = q.row
			local r, g, b = QL.DifficultyColor(row[QL.F_LEVEL])
			local text = STATE_TEXT[q.state]
			local sr, sg, sb = QL.TipColour(text[2])
			tip:AddDoubleLine(string.format("%s (%d)", row[QL.F_TITLE], row[QL.F_LEVEL]), text[1], r, g, b, sr, sg, sb)
			if data.item == "dungeon" or data.item == "raid" then
				local what = QL.IsItemStart(row) and "drops inside" or "is inside"
				Line(tip, string.format("   %s %s", row[QL.F_GIVER], what), "text", true)
			end
			local step, total, nextRow = QL.ChainInfo(row)
			if step then
				local chain = QL.Data().chains[row[QL.F_CHAIN]] or "chain"
				local line = string.format("   Step %d of %d in %s", step, total, chain)
				if nextRow and q.state ~= "done" then
					line = line .. ", next: " .. nextRow[QL.F_TITLE]
				end
				Line(tip, line, "text", true)
			end
		end
		if data.tracked then
			Line(tip, "Tracked. Click to remove the waypoint.", "pinHint")
		else
			local where = (data.item == "dungeon" or data.item == "raid") and ("Click to route to the " .. data.item .. " entrance.")
				or data.item and "Click to set a waypoint here." or "Click to set a waypoint on this giver."
			Line(tip, where, "pinHint")
		end
	elseif self.kind == "entrance" then
		QL.TipTitle(tip, data.name)
		local lv = data.dungeonID ~= 0 and QL.Data().dungeonLevel and QL.Data().dungeonLevel[data.dungeonID]
		local what = data.raid and "Raid" or "Dungeon"
		if lv and lv[1] > 0 then
			Line(tip, string.format("%s, level %d to %d", what, lv[1], lv[2] > 0 and lv[2] or lv[1]), "text")
		else
			Line(tip, what, "text")
		end
		if data.dungeonID ~= 0 then
			local done, total = DungeonProgress(data.dungeonID)
			if total > 0 then
				-- (the count in gold, in the body text once all are done: as the zone badge)
				Line(tip, string.format("%d of %d quests completed", done, total), done >= total and "text" or "selectedTrim")
				Line(tip, "Click to list its quests. Shift-click to route there.", "pinHint")
			else
				Line(tip, "No quests known for it yet.", "text")
				Line(tip, "Shift-click to route there.", "pinHint")
			end
		end
		if data.source == "learned" then
			Line(tip, "Position learned when you walked in.", "text")
		elseif data.source == "client" then
			Line(tip, "Position from the client's own entrance list.", "text")
		end
	elseif self.kind == "transport" then
		QL.TipTitle(tip, data.label)
		Line(tip, (data.kind == 2 and "Zeppelin tower" or "Dock") .. " at " .. data.dock, "text")
		if data.faction == 1 then
			Line(tip, "Alliance", "alliance")
		elseif data.faction == 2 then
			Line(tip, "Horde", "horde")
		else
			Line(tip, "Neutral, both factions", "text")
		end
		if data.destMapID or data.destCont then
			Line(tip, "Click to route to it. Shift-click to open the destination's map.", "pinHint")
		end
		if data.learned then
			Line(tip, "Recorded with /qlmap dock. Remove with /qlmap remove.", "text")
		end
	else
		QL.TipTitle(tip, data.name)
		Line(tip, string.format("%d of %d quests completed", data.done, data.total), "text")
		if data.lo > 0 then
			Line(tip, string.format("Quest levels %d to %d", data.lo, data.hi), "text")
		end
		if data.available > 0 then
			Line(tip, string.format("%d you could pick up now", data.available), "questGold")
		end
		if data.inLog > 0 then
			Line(tip, string.format("%d in your quest log", data.inLog), "text")
		end
		if data.opens then
			Line(tip, "Click to open the zone map.", "pinHint")
		end
	end
	tip:Show()
end

-- (only the mark's own tooltip; no mark: the one hovered now)
MarkLeave = function(self)
	self = self or Marks.hovered
	if Marks.hovered == self then
		Marks.hovered = nil
	end
	if self and GameTooltip:GetOwner() == self then
		GameTooltip:Hide()
	end
end

-- What a click changes on the map is done on the next frame: a map opened
-- from here would come before the game's own move to the cursor (the Gamepad
-- UI's A), which then opens the map under the cursor on top of it.
local function RelayAfterClick()
	QL.Panel:Update()
	QL.RefreshPins()
end

-- (a transport's Shift-click only, with the mouse: the one map change made
-- from MelloUI's code. The map keeps it as MelloUI's until a /reload, so a
-- switch to the Gamepad UI after one wants a /reload first; a zone badge
-- leaves its click to the map, OnAcquired)
local function OpenMapAfterClick(map, mapID)
	C_Timer.After(0, function()
		if map:IsShown() then   -- (closed in between: left as it is)
			map:SetMapID(mapID)
		end
	end)
end

MarkClick = function(self, button)
	local data = self.data
	if not data or button ~= "LeftButton" then
		return
	end
	if self.kind == "giver" then
		if data.tracked then
			QL.ClearWaypoint()
			MelloUI:PlayUISound("waypoint_clear")
		else
			-- (through Route its notice chimes instead: one sound, not two)
			local set, chimed = QL.SetWaypoint(data.quests[1].row, data.quests[1].state == "ready")
			if set and not chimed then
				MelloUI:PlayUISound("waypoint_set")
			end
		end
		C_Timer.After(0, RelayAfterClick)
	elseif self.kind == "entrance" then
		if IsShiftKeyDown() then
			-- Shift-click routes to the door; a plain click lists its quests.
			local map = WorldMapFrame
			local mapID = map and QL.Plain(map:GetMapID())
			local icon = data.raid and "|A:Raid:16:16|a " or "|A:Dungeon:16:16|a "
			local what = data.raid and "raid" or "dungeon"
			local set, chimed = QL.RouteToPoint(mapID, data.x, data.y, icon .. data.name,
				string.format("%sTracking the %s entrance of %s, {dist} away", icon, what, data.name))
			if set and not chimed then   -- (Route's notice chimes when it can)
				MelloUI:PlayUISound("waypoint_set")
			end
		elseif data.dungeonID ~= 0 and QL.byDungeon and QL.byDungeon[data.dungeonID] then
			-- Show the instance's quests: switch the panel, fold the others,
			-- scroll to it, and say so with a sound and a notice.
			for id in pairs(QL.Data().dungeons or {}) do
				QL.collapsed["dungeon" .. id] = (id ~= data.dungeonID) or nil
			end
			QL.Panel:Reveal("dungeon" .. data.dungeonID, data.raid and "raids" or "dungeons")
			MelloUI:PlayUISound("page")
			local done, total = DungeonProgress(data.dungeonID)
			local icon = data.raid and "|A:Raid:18:18|a " or "|A:Dungeon:18:18|a "
			local text = string.format("%s%s: %d quests listed, %d done", icon, data.name, total or 0, done or 0)
			-- MelloUI's one on-screen notice (Core/Notice.lua), Route on or off
			MelloUI:Announce(text, "silent")
		end
	elseif self.kind == "transport" and not IsShiftKeyDown() then
		local map = WorldMapFrame
		local mapID = map and QL.Plain(map:GetMapID())
		local what = data.kind == 2 and "zeppelin" or "boat"
		local icon = "|A:TaxiNode_Neutral:16:16|a "
		local set, chimed = QL.RouteToPoint(mapID, data.x, data.y, icon .. data.label,
			string.format("%sTracking the %s to %s, {dist} away", icon, what, data.label))
		if set and not chimed then   -- (Route's notice chimes when it can)
			MelloUI:PlayUISound("waypoint_set")
		end
	elseif self.kind == "transport" then
		local map = WorldMapFrame
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
			OpenMapAfterClick(map, target)
		end
	end
end

QL.Provider = nil

-- "drop" / "pickup" for a quest begun by an item, nil for an NPC or object giver.
local function ItemKind(row)
	local kind = row[QL.F_KIND]
	return kind == QL.KIND_DROP and "drop" or kind == QL.KIND_PICKUP and "pickup" or nil
end

-- A quest begun by an item is pinned where the item is found only while it
-- can still be picked up; once in the log that spot means nothing.
local function ItemPinWanted(row, state)
	return not QL.IsItemStart(row) or state == "available" or state == "locked"
end

-- The panel's "starts from" filter hides the pins of quests not taken yet;
-- a quest in the log keeps its turn-in pin whatever it started from.
local function StartWanted(row, state)
	return QL.StartShown(row) or not (state == "available" or state == "locked")
end

local function AddGiverPins(map, mapID, mapName)
	local level = QL.Plain(UnitLevel("player")) or 60
	local groups, order = {}, {}
	local function Consider(row, x, y, who, state, item)
		local key = string.format("%s|%.3f|%.3f|%s", who, x, y, item or "")
		local group = groups[key]
		if not group then
			group = { giver = who, x = x, y = y, quests = {}, state = "done", tracked = false, item = item }
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
		if not StartWanted(row, state) then
			return
		end
		local x, y, who, item
		if state == "ready" and QL.resolvedEnd[row] then
			x, y = QL.ProjectOnMap(mapID, QL.Placement(QL.resolvedEnd[row]))
			who = row[QL.F_ENDER]
		elseif not endOnly and QL.resolved[row] and ItemPinWanted(row, state) then
			x, y = QL.ProjectOnMap(mapID, QL.Placement(QL.resolved[row]))
			who, item = row[QL.F_GIVER], ItemKind(row)
		end
		if x then
			seen[row] = true
			Consider(row, x, y, who, state, item)
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
		if not seen[row] and not (QL.resolved and QL.resolved[row]) and (row[QL.F_X] ~= 0 or row[QL.F_Y] ~= 0)
			and QL.Eligible(row) then
			local state = QuestState(row, level)
			if ItemPinWanted(row, state) and StartWanted(row, state) then
				seen[row] = true
				Consider(row, row[QL.F_X] / 100, row[QL.F_Y] / 100, row[QL.F_GIVER], state, ItemKind(row))
			end
		end
	end
	for _, group in ipairs(order) do
		if group.state ~= "done" or M.db.pinCompleted or group.tracked then
			table.sort(group.quests, function(a, b) return QL.ByLevel(a.row, b.row) end)
			Marks.Add("giver", group)
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
				local x, y = (minX + maxX) / 2, (minY + maxY) / 2
				-- the map's own click at the badge's spot opens this zone (it
				-- goes through the badge, OnAcquired): the map it would open
				local zoneID = QL.Plain(child.mapID)
				local okA, under = pcall(C_Map.GetMapInfoAtPosition, continentMapID, x, y)
				local opens = zoneID ~= nil and okA and type(under) == "table" and QL.Plain(under.mapID) == zoneID
				Marks.Add("badge", {
					name = name, done = done, total = total, available = available, inLog = inLog,
					lo = lo, hi = hi, x = x, y = y, opens = opens,
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
	local placedMap, cx, cy, contMapID = QL.ResolveWorld(cont, wx, wy)
	if placedMap then
		local x, y = QL.ProjectOnMap(mapID, placedMap, cx, cy, contMapID)
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
			Marks.Add("entrance", { dungeonID = e[1], name = e[2], raid = e[9] == 2, x = x, y = y, source = "data" })
		end
	end
	-- Entrances learned by walking in (Forever's new instances).
	for name, l in pairs(QL.LearnedStore("entrances")) do
		if l.mapID == mapID and not names[name:lower()] then
			names[name:lower()] = true
			Marks.Add("entrance", { dungeonID = DungeonIDByName(name), name = name, raid = l.raid == true, x = l.x, y = l.y, source = "learned" })
		end
	end
	-- The client's own entrance list for the map, when this build has one.
	for _, e in ipairs(QL.ClientEntrances(mapID)) do
		if not names[e.name:lower()] then
			names[e.name:lower()] = true
			Marks.Add("entrance", { dungeonID = DungeonIDByName(e.name), name = e.name, raid = e.raid, x = e.x, y = e.y, source = "client" })
		end
	end
	-- Points of interest that are instance doors.
	for _, poi in ipairs(QL.ClientPOIs(mapID)) do
		if QL.IsEntrancePOI(poi) and not names[poi.name:lower()] then
			names[poi.name:lower()] = true
			local id = DungeonIDByName(poi.name)
			Marks.Add("entrance", { dungeonID = id, name = poi.name, raid = (id ~= 0 and QL.Data().raids[id] == true) or poi.atlas:lower():find("raid") ~= nil, x = poi.x, y = poi.y, source = "client" })
		end
	end
end

-- Quests begun by an item or object found only inside a dungeon or raid: one
-- pin per instance with the entrance's own icon, beside its door, while any
-- of them can still be picked up. A click routes to the entrance.
local function AddInstanceStartPins(map, mapID, mapName)
	local level = QL.Plain(UnitLevel("player")) or 60
	local groups = {}
	local rows = {}
	for id in pairs(QL.Data().dungeons or {}) do   -- such a quest is listed under its instance
		for _, row in ipairs(QL.byZone[id] or {}) do
			rows[#rows + 1] = row
		end
	end
	for _, row in ipairs(rows) do
		local id = QL.InstanceStart(row)
		if id and QL.Eligible(row) and QL.StartShown(row) then
			local state = QuestState(row, level)
			if state == "available" or state == "locked" then
				local group = groups[id]
				if not group then
					group = { quests = {}, state = "locked", tracked = false, dungeonID = id, giver = QL.Data().dungeons[id],
						item = QL.IsRaid(id) and "raid" or "dungeon" }
					groups[id] = group
				end
				group.quests[#group.quests + 1] = { row = row, state = state }
				if state == "available" then
					group.state = "available"
				end
				if QL.trackedQuestID == row[QL.F_ID] then
					group.tracked = true
				end
			end
		end
	end
	if not next(groups) then
		return
	end
	local data = QL.Data()
	local placed = {}
	for _, e in ipairs(data.entrances or {}) do
		local group = groups[e[1]]
		if group and not placed[e[1]] then
			local x, y = WorldPointOnMap(mapID, mapName, e[3], e[4], e[5], e[6], e[7], e[8])
			if x then
				placed[e[1]] = true
				group.x, group.y = x, y
			end
		end
	end
	-- Entrances learned by walking in (Forever's new instances).
	for name, l in pairs(QL.LearnedStore("entrances") or {}) do
		local id = DungeonIDByName(name)
		if groups[id] and not placed[id] and l.mapID == mapID then
			placed[id] = true
			groups[id].x, groups[id].y = l.x, l.y
		end
	end
	for id, group in pairs(groups) do
		if placed[id] then
			table.sort(group.quests, function(a, b) return QL.ByLevel(a.row, b.row) end)
			Marks.Add("giver", group)
		end
	end
end

local function AddTransportPins(map, mapID, mapName)
	for _, t in ipairs(QL.Data().transports or {}) do
		local x, y = WorldPointOnMap(mapID, mapName, t[5], t[6], t[7], t[8], t[9], t[10])
		if x then
			Marks.Add("transport", {
				kind = t[1], faction = t[2], label = t[3], dock = t[4], x = x, y = y,
				destCont = t[11], destX = t[12], destY = t[13],
			})
		end
	end
	-- Docks recorded with /qlmap dock (routes the vanilla data cannot know).
	for label, l in pairs(QL.LearnedStore("transports")) do
		if l.mapID == mapID then
			Marks.Add("transport", {
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
-- One table, its fields renewed on every look.
local lastOutside = nil

-- The position is taken on every zone change and when the world is left (the
-- loading screen). That last look is the door, but the game cannot always
-- say where the player is at that moment, so the position is also refreshed
-- on a slow ticker; but only where it can matter (user, 2026-09-24: no idle
-- work): after a zone change or a loading screen, while an instance door is
-- within reach, and it stops once none is. A position is only trusted as the
-- door when it came from the last look before the loading screen or from the
-- ticker just before it; an older one (a zone change minutes back, before a
-- long walk) is not, and that entrance is learned on the way out instead.
-- The doors are every entrance the map pins know: the data's, the learned
-- ones, the client's own list and its door points of interest.
local OUTSIDE_EVERY = 3     -- seconds between two looks while a door is near
local DOOR_REACH = 500      -- yards: a door this near keeps the looks going
local DOOR_REACH_MAP = 0.12 -- the same as a share of the map, where the client cannot size the map
local outsideTicker = nil
local outsideOn = false     -- the module is on (the ticker may run)
local outsideAskedAt = nil  -- the last outdoor look, whether it could read the position or not
local doorMap = nil         -- the map the door list is for (nil: none made yet)
local doorX, doorY, doorCount = {}, {}, 0
local doorW, doorH = nil, nil   -- that map's size in yards (nil: unknown)
-- the data's doors placed once a session (the client's maps do not change
-- while playing, and a map change then costs no placing), by the data's own
-- entry: the map, the continent position and the continent map; false where
-- the client cannot place the door
local BY_ENTRY = { __mode = "k" }
local doorPlaced, doorCont = setmetatable({}, BY_ENTRY), setmetatable({}, BY_ENTRY)
local doorCX, doorCY = setmetatable({}, BY_ENTRY), setmetatable({}, BY_ENTRY)

local function AddDoor(x, y)
	if x and y then
		doorCount = doorCount + 1
		doorX[doorCount], doorY[doorCount] = x, y
	end
end

-- The doors on a map, made again only when the map changes (or a door is
-- learned); the data's are placed as the map pins place them. The list is
-- marked as made only once it is whole: one that failed halfway is made
-- again on the next look.
local function DoorsOn(mapID)
	doorMap, doorCount = nil, 0
	local okI, info = pcall(C_Map.GetMapInfo, mapID)
	local mapName = (okI and type(info) == "table" and QL.Plain(info.name)) or ""
	for _, e in ipairs(QL.Data().entrances or {}) do
		if doorPlaced[e] == nil then
			local placed, cx, cy, contMapID = QL.ResolveWorld(e[3], e[4], e[5])
			doorPlaced[e], doorCX[e], doorCY[e], doorCont[e] = placed or false, cx, cy, contMapID
		end
		local placed = doorPlaced[e]
		if placed then
			AddDoor(QL.ProjectOnMap(mapID, placed, doorCX[e], doorCY[e], doorCont[e]))
		elseif e[6] ~= 0 and QL.zoneByName and QL.zoneByName[mapName:lower()] == e[6] then
			AddDoor(e[7] / 100, e[8] / 100)
		end
	end
	for _, l in pairs(QL.LearnedStore("entrances")) do
		if l.mapID == mapID then
			AddDoor(l.x, l.y)
		end
	end
	for _, e in ipairs(QL.ClientEntrances(mapID)) do
		AddDoor(e.x, e.y)
	end
	for _, poi in ipairs(QL.ClientPOIs(mapID)) do
		if QL.IsEntrancePOI(poi) then
			AddDoor(poi.x, poi.y)
		end
	end
	doorW, doorH = nil, nil
	if C_Map.GetMapWorldSize then
		local okS, w, h = pcall(C_Map.GetMapWorldSize, mapID)
		w, h = okS and QL.Plain(w) or nil, okS and QL.Plain(h) or nil
		if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
			doorW, doorH = w, h
		end
	end
	doorMap = mapID
end

local function DoorNear(mapID, x, y)
	if mapID ~= doorMap then
		DoorsOn(mapID)
	end
	for i = 1, doorCount do
		local dx, dy = doorX[i] - x, doorY[i] - y
		if doorW then
			dx, dy = dx * doorW, dy * doorH
			if dx * dx + dy * dy <= DOOR_REACH * DOOR_REACH then
				return true
			end
		elseif dx * dx + dy * dy <= DOOR_REACH_MAP * DOOR_REACH_MAP then
			return true
		end
	end
	return false
end

local function StopOutsideLooks()
	if outsideTicker then
		outsideTicker:Cancel()
		outsideTicker = nil
	end
end

-- Takes the outdoor position (the zone events, the ticker, a loading screen)
-- and starts or stops the ticker by whether a door is near.
function QL.RememberOutside()
	local okI, inInstance = pcall(IsInInstance)
	if not okI or inInstance then
		StopOutsideLooks()
		return
	end
	-- noted read or not: a look that cannot read the position (leaving the
	-- world, say) leaves the one before it standing, and that one is then
	-- no longer where the player went in
	outsideAskedAt = GetTime()
	local okM, mapID = pcall(C_Map.GetBestMapForUnit, "player")
	mapID = okM and QL.Plain(mapID) or nil
	if not mapID then
		StopOutsideLooks()
		return
	end
	local okP, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
	local x, y
	if okP then
		x, y = QL.VectorXY(pos)   -- pos.x is a secret value on this client; VectorXY falls back to GetXY
	end
	if not (x and y and x > 0 and y > 0) then
		StopOutsideLooks()
		return
	end
	lastOutside = lastOutside or {}
	lastOutside.mapID, lastOutside.x, lastOutside.y, lastOutside.at = mapID, x, y, GetTime()
	-- guarded: a door list that cannot be made means no ticker, never an
	-- error in the zone events' handler
	local okD, near = false, false
	if outsideOn and C_Timer.NewTicker then
		okD, near = pcall(DoorNear, mapID, x, y)
	end
	if okD and near then
		if not outsideTicker then
			outsideTicker = C_Timer.NewTicker(OUTSIDE_EVERY, QL.RememberOutside)
		end
	else
		StopOutsideLooks()
	end
end

-- The module on: the looks may run from the next zone change or loading
-- screen on (nothing is looked at here, at login).
function QL.StartOutsideTicker()
	outsideOn = true
end

function QL.StopOutsideTicker()
	outsideOn = false
	StopOutsideLooks()
end

local learnFailed = nil   -- instance name already reported this session
QL.pendingExit = nil   -- { name, raid }: instance to learn from where the player exits it

-- where a learned entrance shows, said in its notice (0.16.0: the marks
-- show in the Gamepad UI too)
local function EntranceShows()
	return "it is on the zone map now"
end

-- Returns true when done (learned, already known, or not applicable); false
-- when the instance is not readable yet and a retry is worth it.
function QL.LearnEntrance()
	-- asked after every loading screen (a /reload too, where no zone event
	-- comes): outdoors that decides the ticker, inside it stops it (guarded:
	-- the dungeon summary comes after this on the same timer)
	pcall(QL.RememberOutside)
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
	if not lastOutside or GetTime() - lastOutside.at > 180
		or lastOutside.at < (outsideAskedAt or 0) - OUTSIDE_EVERY - 1 then
		-- No position from just before the loading screen (reloaded inside,
		-- or the last look before it could not read one and the position
		-- kept is from further back). Leaving the instance puts the player
		-- at its door, so the entrance is learned on the way out instead.
		QL.pendingExit = { name = name, raid = kind == "raid" }
		if learnFailed ~= name then
			learnFailed = name
			-- (0.16.0: the marks show in the Gamepad UI too: one line for both)
			MelloUI:Notice("Quest List: the entrance of %s will be put on the map when you walk out of it.", name)
		end
		return true
	end
	learned[name] = { mapID = lastOutside.mapID, x = lastOutside.x, y = lastOutside.y, raid = kind == "raid" }
	doorMap = nil   -- a door more: the list is made again
	MelloUI:Notice("Quest List: learned where the entrance of %s is; %s.", name, EntranceShows())
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
	doorMap = nil   -- a door more: the list is made again
	MelloUI:Notice("Quest List: learned where the entrance of %s is; %s.", pending.name, EntranceShows())
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
	-- the flight point pin keeps its node as taxiNodeData (and name) on this
	-- client's data provider; poiInfo was the older field
	local info = pin.taxiNodeData or pin.poiInfo
	local name = QL.Plain(pin.name) or (info and QL.Plain(info.name)) or "Flight master"
	if mapID and x and y then
		local icon = "|T" .. "Interface/Minimap/Tracking/FlightMaster" .. ":16:16|t "
		QL.RouteToPoint(mapID, x, y, icon .. name, string.format("%sTracking the flight master at %s, {dist} away", icon, name))
	end
end

-- the flight pins hooked: kept here, never as a key on the game's own pins
-- (a pin the pool hands out again keeps its hook, and stays in here)
local flightHooked = setmetatable({}, { __mode = "k" })

local function HookFlightPins(map)
	if map and map.EnumeratePinsByTemplate then
		-- EnumeratePinsByTemplate hands back a generic-for triple (next, set, nil)
		local ok, f, state, init = pcall(map.EnumeratePinsByTemplate, map, "FlightPointPinTemplate")
		if ok and type(f) == "function" then
			for pin in f, state, init do
				if not flightHooked[pin] and pin.OnMouseClickAction then
					flightHooked[pin] = true
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
	QL.Provider = CreateFromMixins(MapCanvasDataProviderMixin)
	-- (the marks are MelloUI's own frames: no pool call is ever made from here)
	function QL.Provider:RemoveAllData()
		Marks.Clear()
	end
	-- (the zoom and the pan move the marks' anchors with the canvas: nothing
	-- of ours runs for them; a new canvas size lays the anchors again)
	function QL.Provider:OnCanvasSizeChanged()
		if Marks.n > 0 then
			Marks.Anchor(self:GetMap())
		end
	end
	-- the pins laid again: on the map's own refresh (fromMap, below) and on
	-- the Quest List's (QL.RefreshPins: a switch-on with the map open too)
	function QL.Provider:LayPins(fromMap)
		self:RemoveAllData()
		self.palette = MelloUI.Palette   -- the palette the pins are laid in
		if not (M.isEnabled and QL.byZone) then
			return
		end
		local map = self:GetMap()
		-- Blizzard's flight points, hooked a frame later (their provider has
		-- made the pins for the map by then): a post-hook, on the map's own
		-- refresh, or on the Quest List's outside the Gamepad UI
		if fromMap or not MelloUI.Safe.GamepadUI() then
			C_Timer.After(0, function() HookFlightPins(map) end)
		end
		-- (the Gamepad UI's A press: the hovered mark's click, one post-hook)
		Marks.Hook(map)
		local mapID = QL.Plain(map:GetMapID())
		local okI, info = pcall(C_Map.GetMapInfo, mapID)
		if not mapID or not okI or type(info) ~= "table" then
			return
		end
		local mapType, name = QL.Plain(info.mapType), QL.Plain(info.name)
		Marks.Begin()
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
				Try("instance quest items", AddInstanceStartPins, map, mapID, name)
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
		Try("the marks' layer", Marks.End, map)
	end
	-- the map's refresh (it opens, it changes map): every provider lays its
	-- pins again
	function QL.Provider:RefreshAllData()
		self:LayPins(true)
	end
	WorldMapFrame:AddDataProvider(QL.Provider)
	-- a new palette: the pins laid again while the map shows (a hidden map
	-- lays them on its next show). Only a new palette TABLE: 'palette' goes
	-- out for a Kit Colours change too, the palette unchanged
	MelloUI:On("palette", function()
		if QL.Provider.palette ~= MelloUI.Palette then
			QL.RefreshPins()
		end
	end, "Quest List pins")
end

QL.RefreshPins = function()
	if QL.Provider and WorldMapFrame and WorldMapFrame:IsShown() then
		QL.Provider:LayPins()
	end
end

MelloUI:Profile("QuestList", "map pins", QL.RefreshPins)
