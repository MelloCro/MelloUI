--------------------------------------------------------------------------------
-- MelloUI - Road recorder (2026-10-02): the capitals' streets, walked by hand
--
-- A developer tool, not a feature: /route record opens it, and it is in
-- neither the configurator nor the guide. Route's roads were traced from the
-- zone maps' art, and the capitals' own maps draw no roads: Route had no
-- street inside Stormwind and went round its walls (the user's drawn route
-- runs through the Trade District and the Mage Quarter). The user runs each
-- city's main streets with this open, from the gate on; the stretches are
-- kept in MelloUIRoadRecords and handed over as text from the copy window,
-- which Tools/roads_import.py turns into roads for the bake
-- (Tools/trace_roads.py). docs/plans/city-road-recorder.md.
--
--   the cities   one row each: a switch for "done", the name, what is
--                recorded; a click picks the city recorded into
--   Start/Pause  the place read every EVERY s while recording, through
--                Route:Where() (continent yards); a point on the straight
--                line past it dropped (every read checked). A jump,
--                a taxi, no place (an instance) or another continent ends the
--                stretch; the next place read starts a new one
--   marks        Gate (where the streets meet the road outside: the bake
--                joins them there), Elevator, Tram, Door and Note (a line
--                typed in the paste box) at the player's place
--   Undo         the last stretch or mark, whichever came last
--   Export       the city as text in the copy window
--   the trace    the city's stretches on the world map while the window
--                shows or a recording runs: the layer over the map
--                (QL.MapLayer), one invisible anchor per point on the
--                canvas (pan and zoom move them) and lines between them
-- Nothing at login: the window is built on its first open, the place is read
-- only while recording (a hidden frame's OnUpdate, shown only then).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local CreateFrame = MelloUI.Safe.CreateFrame
local Perf = MelloUI.Perf:Scope("Road recorder")
local Num = MelloUI.Safe.Number
local Secret = MelloUI.Safe.IsSecret
local W = MelloUI.Widgets
local Route = MelloUI:GetModule("Route")
local QL = ns.QuestList

local CITIES = {
	{ 1453, "Stormwind City" }, { 1455, "Ironforge" }, { 1457, "Darnassus" },
	{ 1454, "Orgrimmar" }, { 1456, "Thunder Bluff" }, { 1458, "Undercity" },
}
local NAME = {}
for _, c in ipairs(CITIES) do
	NAME[c[1]] = c[2]
end
-- (Gate, 2026-10-03: where the city's streets meet the road outside -- the bake joins a street's end there to the
-- world's roads wherever it lies on the city's map, Tools/trace_roads.py join_gates)
local KINDS = { "Gate", "Elevator", "Tram", "Door", "Note" }
local LETTER = { Gate = "G", Elevator = "E", Tram = "T", Door = "D", Note = "N" }

local EVERY = 0.2       -- s between two reads of the place while recording
local STILL = 0.5       -- yd: a read nearer than this to the last is the player standing
local JUMP = 40         -- yd in one read: a port, a load screen (a new stretch)
local STRAIGHT = 0.75   -- yd: reads this close to the line past them are dropped
local RUN = 80          -- yd: the longest straight line one pair of points stands for
local REDRAW = 1        -- s: the map's trace laid again at most this often while recording
local SCALE = 1000000   -- the export's continent fractions as whole numbers (0.035 yd)
local NOTE_MAX = 80

local LINE_PX, MARK_PX = 3, 10
local WIN_W, WIN_H = 440, 440
local TOP, EDGE = -64, 28
local ROW_Y, ROW_H = 36, 26
local BUTTON_H, BUTTON_GAP = 24, 8

local R = { city = nil, recording = false, current = nil, raw = {}, wait = 0, dirty = false }
Route.Recorder = R

--------------------------------------------------------------------------------
-- The saved recordings
--------------------------------------------------------------------------------

local function Store()
	if type(MelloUIRoadRecords) ~= "table" then
		MelloUIRoadRecords = { version = 1 }
	end
	local s = MelloUIRoadRecords
	if type(s.cities) ~= "table" then
		s.cities = {}
	end
	return s
end

-- the city's record (nil for none yet: a look makes nothing)
local function Peek(id)
	local c = id and Store().cities[id]
	return type(c) == "table" and c or nil
end

local function City(id)
	local cities = Store().cities
	local c = Peek(id)
	if not c then
		c = { done = false, seq = 0, stretches = {}, marks = {} }
		cities[id] = c
	end
	c.stretches = type(c.stretches) == "table" and c.stretches or {}
	c.marks = type(c.marks) == "table" and c.marks or {}
	return c
end

local function Next(city)
	city.seq = (tonumber(city.seq) or 0) + 1
	return city.seq
end

local function Dist(ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	return math.sqrt(dx * dx + dy * dy)
end

-- how far (px, py) lies from the line a-b
local function OffLine(ax, ay, bx, by, px, py)
	local dx, dy = bx - ax, by - ay
	local len2 = dx * dx + dy * dy
	if len2 <= 0 then
		return Dist(ax, ay, px, py)
	end
	local t = ((px - ax) * dx + (py - ay) * dy) / len2
	t = t < 0 and 0 or (t > 1 and 1 or t)
	return Dist(ax + t * dx, ay + t * dy, px, py)
end

local function Length(s)
	local p, d = s.p, 0
	for j = 3, #p - 1, 2 do
		d = d + Dist(p[j - 2], p[j - 1], p[j], p[j + 1])
	end
	return d
end

local function YardsText(d)
	return Route:YardsText(d) or string.format("%d yd", d)
end

--------------------------------------------------------------------------------
-- Recording
--------------------------------------------------------------------------------

local Changed   -- (below: the window and the trace told)

-- the stretch being recorded ends; one point is no road and goes
local function EndStretch()
	local s = R.current
	R.current = nil
	wipe(R.raw)
	if s and #s.p < 4 and R.city then
		local list = City(R.city).stretches
		for i = #list, 1, -1 do
			if list[i] == s then
				table.remove(list, i)
				break
			end
		end
	end
end

-- a place read: true when the stretch changed. The last point stands for
-- every read since the one before it (R.raw) while they all lie on the line
-- to it: a straight street is two points, a corner keeps its point.
local function Take(cont, x, y)
	local s = R.current
	if s and s.cont ~= cont then
		EndStretch()
		s = nil
	end
	if not s then
		local city = City(R.city)
		s = { cont = cont, seq = Next(city), p = { x, y } }
		city.stretches[#city.stretches + 1] = s
		R.current = s
		return true
	end
	local p, raw = s.p, R.raw
	local n = #p
	local lx, ly = p[n - 1], p[n]
	local d = Dist(lx, ly, x, y)
	if d > JUMP then
		EndStretch()
		return Take(cont, x, y)
	end
	if d < STILL then
		return false
	end
	if n >= 4 then
		local ax, ay = p[n - 3], p[n - 2]
		local straight = Dist(ax, ay, x, y) <= RUN and OffLine(ax, ay, x, y, lx, ly) <= STRAIGHT
		for j = 1, #raw - 1, 2 do
			if not straight then
				break
			end
			straight = OffLine(ax, ay, x, y, raw[j], raw[j + 1]) <= STRAIGHT
		end
		if straight then
			raw[#raw + 1], raw[#raw + 2] = lx, ly
			p[n - 1], p[n] = x, y
			return true
		end
	end
	wipe(raw)
	p[n + 1], p[n + 2] = x, y
	return true
end

local function OnTaxi()
	local ok, on = pcall(UnitOnTaxi, "player")
	if not ok or Secret(on) then
		return false
	end
	return on and true or false
end

-- the player's place in continent yards (nil on a taxi, in an instance)
local function Here()
	if OnTaxi() then
		return nil
	end
	local cont, x, y = Route:Where()
	cont, x, y = Num(cont), Num(x), Num(y)
	if cont and x and y then
		return cont, x, y
	end
	return nil
end

local Map = { anchors = {}, lines = {}, marks = {}, clip = nil, provider = nil, at = 0 }

local function Tick()
	local cont, x, y = Here()
	if not cont then
		if R.current then
			EndStretch()
			Changed()
		end
	elseif Take(cont, x, y) then
		Changed()
	end
	if R.dirty and GetTime() - Map.at >= REDRAW then
		Map.Draw()
	end
end

local ticker = nil
local function Ticker()
	if not ticker then
		ticker = CreateFrame("Frame")
		ticker:Hide()
		Perf.SetScript(ticker, "OnUpdate", function(_, elapsed)
			R.wait = R.wait + elapsed
			if R.wait >= EVERY then
				R.wait = 0
				Tick()
			end
		end)
	end
	return ticker
end

local function SetRecording(on)
	on = on and R.city and true or false
	if on == R.recording then
		return
	end
	R.recording = on
	if not on then
		EndStretch()
	end
	R.wait = 0
	Ticker():SetShown(on)
	MelloUI:Print(on and "Recording roads into %s." or "Road recording paused (%s).", NAME[R.city] or "?")
	Changed(true)
end

local function Select(id)
	if id == R.city then
		return
	end
	EndStretch()
	R.city = id
	Store().last = id
	Changed(true)
end

local function AddMark(kind, note)
	local cont, x, y = Here()
	if not (cont and R.city) then
		MelloUI:Print("No place to mark here.")
		return
	end
	local city = City(R.city)
	city.marks[#city.marks + 1] = { kind = kind, cont = cont, x = x, y = y, note = note, seq = Next(city) }
	Changed(true)
end

local function Mark(kind)
	if kind ~= "Note" then
		AddMark(kind)
		return
	end
	MelloUI:ShowPaste("road note", function(text)
		text = tostring(text or ""):gsub("[\r\n|]", " "):gsub("^%s+", ""):gsub("%s+$", "")
		if text == "" then
			return false
		end
		AddMark("Note", text:sub(1, NOTE_MAX))
		return true
	end)
end

-- the last stretch or mark, whichever came last (the stretch being recorded
-- too: the next place read starts a new one)
local function Undo()
	local city = Peek(R.city)
	if not city then
		return
	end
	EndStretch()
	local s, m = city.stretches[#city.stretches], city.marks[#city.marks]
	if s and (not m or (tonumber(s.seq) or 0) > (tonumber(m.seq) or 0)) then
		city.stretches[#city.stretches] = nil
		MelloUI:Print("Removed the last stretch (%s).", YardsText(Length(s)))
	elseif m then
		city.marks[#city.marks] = nil
		MelloUI:Print("Removed the last mark (%s).", tostring(m.kind))
	end
	Changed(true)
end

local function Clear()
	local id = R.city
	if not Peek(id) then
		return
	end
	MelloUI:Confirm({
		text = string.format("Clear every stretch and mark recorded in %s?", NAME[id] or "?"),
		accept = "Clear",
		onAccept = function()
			EndStretch()
			local city = City(id)
			wipe(city.stretches)
			wipe(city.marks)
			Changed(true)
		end,
	})
end

--------------------------------------------------------------------------------
-- The export
--------------------------------------------------------------------------------

local function Frac(cont, x, y)
	local fx, fy = Route.OnMap(cont, cont, x, y)
	if not (fx and fy) then
		return nil
	end
	return string.format("%d,%d", math.floor(fx * SCALE + 0.5), math.floor(fy * SCALE + 0.5))
end

local function ExportText(id)
	local city = Peek(id) or { stretches = {}, marks = {} }
	local out = { "MelloUI road recording 1", string.format("city %d %s", id, NAME[id] or "?"),
		"done " .. (city.done and "yes" or "no") }
	for _, s in ipairs(city.stretches) do
		local parts = { "stretch", tostring(s.cont) }
		local p = s.p
		for j = 1, #p - 1, 2 do
			parts[#parts + 1] = Frac(s.cont, p[j], p[j + 1])
		end
		out[#out + 1] = table.concat(parts, " ")
	end
	for _, m in ipairs(city.marks) do
		local at = Frac(m.cont, m.x, m.y)
		if at then
			out[#out + 1] = string.format("mark %s %d %s%s", m.kind, m.cont, at, m.note and (" " .. m.note) or "")
		end
	end
	out[#out + 1] = "end"
	return table.concat(out, "\n")
end

--------------------------------------------------------------------------------
-- The trace on the world map
--------------------------------------------------------------------------------

function Map.Clip(map)
	local clip = Map.clip
	if not clip then
		clip = CreateFrame("Frame", nil, QL.MapLayer())
		clip:SetAllPoints(map.ScrollContainer or map:GetCanvas())
		if clip.SetClipsChildren then
			clip:SetClipsChildren(true)
		end
		Map.clip = clip
	end
	QL.SyncMapLayer()
	local strata = QL.mapLayer:GetFrameStrata()
	if clip:GetFrameStrata() ~= strata then
		clip:SetFrameStrata(strata)
	end
	return clip
end

-- (an anchor: an empty texture on the canvas, never drawn)
function Map.Anchor(canvas, i, x, y)
	local a = Map.anchors[i]
	if not a then
		a = canvas:CreateTexture(nil, "BACKGROUND")
		a:SetSize(1, 1)
		Map.anchors[i] = a
	end
	a:ClearAllPoints()
	a:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
	return a
end

-- a recorded stretch in Route's red, the one being recorded in the trim's gold
local function LineColour(line, live)
	if line.live == live then
		return
	end
	line.live = live
	if live then
		W.Paint(line, "selectedTrim", "fill", 1)
	else
		local Kit = MelloUI.Kit
		if Kit and Kit.Unpaint then
			Kit:Unpaint(line, "fill")
		end
		local c = MelloUI.Meaning.routeTrail
		line:SetColorTexture(c[1], c[2], c[3], 1)
	end
end

function Map.Line(clip, i, a, b, live)
	local line = Map.lines[i]
	if not line then
		line = clip:CreateLine(nil, "ARTWORK")
		line:SetThickness(LINE_PX)
		Map.lines[i] = line
	end
	LineColour(line, live)
	line:SetStartPoint("CENTER", a)
	line:SetEndPoint("CENTER", b)
	line:Show()
end

-- a mark: a square and its letter, in dark ink on the map's parchment
function Map.Mark(clip, i, a, kind)
	local m = Map.marks[i]
	if not m then
		m = clip:CreateTexture(nil, "OVERLAY")
		m:SetSize(MARK_PX, MARK_PX)
		W.Paint(m, "mainWindow", "fill", 1)
		m.label = W.Text(clip, "GameFontNormal", nil, "mainWindow")
		m.label:SetPoint("LEFT", m, "RIGHT", 3, 0)
		Map.marks[i] = m
	end
	m:ClearAllPoints()
	m:SetPoint("CENTER", a, "CENTER", 0, 0)
	m.label:SetText(LETTER[kind] or "?")
	m:Show()
	m.label:Show()
end

-- (closing: from the window's OnHide, whatever IsShown says there)
function Map.Draw(closing)
	Map.at = GetTime()
	R.dirty = false
	local map = WorldMapFrame
	local lines, marks = 0, 0
	local open = R.window and R.window:IsShown() and not closing
	local want = R.city and map and map:IsShown() and (R.recording or open)
	local city = want and Peek(R.city)
	local mapID = city and Num(map:GetMapID())
	local canvas = mapID and map:GetCanvas()
	local w, h = canvas and Num(canvas:GetWidth()), canvas and Num(canvas:GetHeight())
	if w and h and w > 0 and h > 0 and w < math.huge and h < math.huge then
		local clip = Map.Clip(map)
		local n = 0
		for _, s in ipairs(city.stretches) do
			local p, prev = s.p, nil
			local live = s == R.current
			for j = 1, #p - 1, 2 do
				local fx, fy = Route.OnMap(mapID, s.cont, p[j], p[j + 1])
				local a = nil
				if fx and fy then
					n = n + 1
					a = Map.Anchor(canvas, n, fx * w, fy * h)
				end
				if a and prev then
					lines = lines + 1
					Map.Line(clip, lines, prev, a, live)
				end
				prev = a
			end
		end
		for _, m in ipairs(city.marks) do
			local fx, fy = Route.OnMap(mapID, m.cont, m.x, m.y)
			if fx and fy then
				n = n + 1
				marks = marks + 1
				Map.Mark(clip, marks, Map.Anchor(canvas, n, fx * w, fy * h), m.kind)
			end
		end
	end
	for i = lines + 1, #Map.lines do
		Map.lines[i]:Hide()
	end
	for i = marks + 1, #Map.marks do
		Map.marks[i]:Hide()
		Map.marks[i].label:Hide()
	end
end

-- laid with the map's own refreshes (a show, another map, a new size)
local function Provider()
	if Map.provider or not (MapCanvasDataProviderMixin and WorldMapFrame and WorldMapFrame.AddDataProvider) then
		return
	end
	local p = CreateFromMixins(MapCanvasDataProviderMixin)
	function p:RefreshAllData()
		Map.Draw()
	end
	function p:OnCanvasSizeChanged()
		Map.Draw()
	end
	WorldMapFrame:AddDataProvider(p)
	Map.provider = p
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local function CityText(id)
	local city = Peek(id)
	if not city or (#city.stretches == 0 and #city.marks == 0) then
		return "nothing yet"
	end
	local d = 0
	for _, s in ipairs(city.stretches) do
		d = d + Length(s)
	end
	return string.format("%s, %d marks", YardsText(d), #city.marks)
end

local function Refresh()
	local f = R.window
	if not (f and f:IsShown()) then
		return
	end
	for _, row in ipairs(f.rows) do
		row.sel:SetShown(row.id == R.city)
		row.info:SetText(CityText(row.id))
		row.done:Refresh()
	end
	local name = NAME[R.city] or "?"
	local city = Peek(R.city)
	local s = R.current
	if R.recording then
		f.status:SetText(string.format("Recording %s: this stretch %s.", name, s and YardsText(Length(s)) or "waiting for a place"))
	else
		f.status:SetText(string.format("Paused. Start records into %s.", name))
	end
	f.status2:SetText(string.format("%d stretches and %d marks in %s.", city and #city.stretches or 0, city and #city.marks or 0, name))
	f.start:SetText(R.recording and "Pause" or "Start")
end

Changed = function(redraw)
	R.dirty = true
	Refresh()
	if redraw then
		Map.Draw()
	end
end

local function Window()
	if R.window then
		return R.window
	end
	local f = CreateFrame("Frame", "MelloUIRoadRecorder", UIParent)
	f:SetSize(WIN_W, WIN_H)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:Hide()
	-- (its own scripts before the shell's and the mover's hooks)
	f:SetScript("OnShow", function()
		Refresh()
		Map.Draw()
	end)
	f:SetScript("OnHide", function()
		Map.Draw(true)
	end)
	local shell = MelloUI.Kit:OwnWindow(f, { area = "copy", ring = { at = "tl" }, plate = "rail", title = "Road recorder",
		close = true, escape = true, fit = true, sounds = true, calm = true,
		mover = { key = "roadRecorder", plainDrag = "always", label = "Road recorder" } })
	f.shell = shell
	local body = W.Panel(f)
	body:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE, TOP)
	body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -EDGE, EDGE)
	W.Header(body, 4, "Cities  (the switch: done)", { inset = 4 })
	f.rows = {}
	for i, c in ipairs(CITIES) do
		local id = c[1]
		local row = CreateFrame("Button", nil, body)
		row:SetPoint("TOPLEFT", body, "TOPLEFT", 44, -(ROW_Y + (i - 1) * ROW_H))
		row:SetPoint("RIGHT", body, "RIGHT", -10, 0)
		row:SetHeight(ROW_H - 2)
		row.id = id
		row.sel = W.Solid(row, "BACKGROUND", "selectedTab", 1)
		row.sel:SetAllPoints(row)
		local hover = W.Solid(row, "HIGHLIGHT", "hover", 1)
		hover:SetAllPoints(row)
		local name = W.Text(row, "GameFontHighlight", c[2], "text")
		name:SetPoint("LEFT", row, "LEFT", 8, 0)
		row.info = W.Text(row, "GameFontHighlight", "", "text")
		row.info:SetJustifyH("RIGHT")
		row.info:SetPoint("RIGHT", row, "RIGHT", -8, 0)
		Perf.SetScript(row, "OnClick", function()
			MelloUI:PlayUISound("tab")
			Select(id)
		end)
		row.done = W.Switch(body, function()
			local city = Peek(id)
			return city and city.done or false
		end, function(on)
			City(id).done = on and true or false
			Changed()
		end, { skin = shell })
		row.done:SetPoint("RIGHT", row, "LEFT", -8, 0)
		f.rows[i] = row
	end
	local y = ROW_Y + #CITIES * ROW_H + 10
	f.status = W.Text(body, "GameFontHighlight", "", "text")
	f.status:SetPoint("TOPLEFT", body, "TOPLEFT", 14, -y)
	f.status:SetPoint("RIGHT", body, "RIGHT", -14, 0)
	f.status2 = W.Text(body, "GameFontHighlight", "", "text")
	f.status2:SetPoint("TOPLEFT", f.status, "BOTTOMLEFT", 0, -6)
	f.status2:SetPoint("RIGHT", body, "RIGHT", -14, 0)
	y = y + 50
	local inner = WIN_W - 2 * EDGE - 28
	local function Row(list, top)
		local bw = (inner - (#list - 1) * BUTTON_GAP) / #list
		local made = {}
		for i, entry in ipairs(list) do
			local b = W.Button(body, entry[1], bw, shell, { height = BUTTON_H, gold = entry.gold, onClick = entry[2] })
			b:SetPoint("TOPLEFT", body, "TOPLEFT", 14 + (i - 1) * (bw + BUTTON_GAP), -top)
			made[i] = b
		end
		return made
	end
	f.start = Row({
		{ "Start", function() SetRecording(not R.recording) end, gold = true },
		{ "Undo", Undo },
		{ "Export", function()
			MelloUI:ShowText("road recording, " .. (NAME[R.city] or "?"), ExportText(R.city))
		end },
	}, y)[1]
	local marks = {}
	for i, kind in ipairs(KINDS) do
		marks[i] = { kind, function() Mark(kind) end }
	end
	Row(marks, y + BUTTON_H + BUTTON_GAP)
	Row({ { "Clear city", Clear } }, y + 2 * (BUTTON_H + BUTTON_GAP))
	R.window = f
	return f
end

-- /route record: the window, on the city the player stands in (else the one
-- picked before, else Stormwind; a recording keeps its city)
function R.Open()
	local store = Store()
	if not R.recording then
		local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
		mapID = ok and Num(mapID) or nil
		R.city = (mapID and NAME[mapID] and mapID) or R.city or (NAME[store.last] and store.last) or CITIES[1][1]
	end
	Provider()
	local f = Window()
	f:Show()
	Refresh()
end
