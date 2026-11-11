--------------------------------------------------------------------------------
-- MelloUI.Coords (2.1.41; players: "Enable Map and minimap Coordinates"; the
-- user, 2026-11-11: "So basically your Current Character Coordinates, and the
-- Coordinates where your mouse is"; the picks of Workspace/BuildData/output/
-- coords_sketch: A on the map -- words in its footer -- and A on the minimap,
-- a line under it that turns gold while the mouse is over the minimap)
--
-- The one place coordinates are read and written as text: the map's footer
-- (MelloUI_Map/Map.lua) and the minimap's line (Tweaks' Coordinates):
--   Coords.Text(x, y)          "42.6, 67.1" for a place on a map (0..1), as
--                              the game writes its own: tenths, or whole
--                              numbers (its coordsByTenths)
--   Coords.Player()            mapID, x, y: you, on the map the game counts
--                              you on; nil in an instance or when unread
--   Coords.MinimapMouse(area)  mapID, x, y under the mouse while it is over
--                              `area` (the minimap's shown part), or nil
--   Coords.Minimap(on)         the minimap's line on or off
--   Coords.MinimapLineHeight() the line's height while it is on (the
--                              minimap's column counts it), else nil
--   Coords.MinimapLineWidth()  the room it takes beside Route's distance
-- The line stands right under the map picture, in Route's distance line's
-- place (Modules/MinimapPanel.lua's column, M:ColumnSlot("coords"): with the
-- Services row in the frame, at the right end of its rail; the user's pick,
-- 2026-11-11: "Right under the map picture"), just left of Route's distance
-- while that shows; placed again on every 'column' and on its beat. The
-- game's own line stays hidden (Tweaks): never two.
--
-- Nothing at login: the line is made the first time it is switched on; its
-- beat (BEAT, the game's own line's pace) runs only while it shows.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Coords")

local Finite = MelloUI.Safe.Finite
local floor, format = math.floor, string.format

local Coords = {}
MelloUI.Coords = Coords

local T = {
	BEAT = 0.1,      -- the line read again at most this often (the game's own minimap line's pace)
	ICON = 12,       -- the pointer before the mouse's place
	POINTER = "btn_way",
	GOLD = "selectedTrim",
	GAP = 8,         -- between the line and Route's distance beside it
	WIDEST = "88.8, 88.8",   -- (the room it keeps beside Route's distance)
}

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

-- the game's own choice: tenths (42.6) or whole numbers (43)
local function Tenths()
	local ok, on = pcall(GetCVarBool, "coordsByTenths")
	return not (ok and on == false)
end

function Coords.Text(x, y)
	x, y = Finite(x), Finite(y)
	if not (x and y) then
		return nil
	end
	if Tenths() then
		return format("%.1f, %.1f", x * 100, y * 100)
	end
	return format("%d, %d", floor(x * 100 + 0.5), floor(y * 100 + 0.5))
end

function Coords.Player()
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then
		return nil
	end
	local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
	mapID = ok and Finite(mapID) or nil
	if not mapID then
		return nil
	end
	local okP, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
	if not (okP and type(pos) == "table") then
		return nil
	end
	local okXY, x, y = pcall(pos.GetXY, pos)
	if not okXY then
		return nil
	end
	x, y = Finite(x), Finite(y)
	-- (0, 0: the game's answer where it has no place for you)
	if not (x and y) or (x == 0 and y == 0) then
		return nil
	end
	return mapID, x, y
end

-- the place under the mouse on the minimap: the mouse's distance from the
-- map's middle (you) in yards -- the map's half width is its view radius --
-- turned with the map while it turns, then on your map by its size in yards
function Coords.MinimapMouse(area)
	local map = Minimap
	if not (map and area and area:IsMouseOver()) then
		return nil
	end
	local mapID, px, py = Coords.Player()
	local CM = rawget(_G, "C_Minimap")
	if not mapID or not (CM and CM.GetViewRadius and C_Map.GetMapWorldSize) then
		return nil
	end
	local okR, radius = pcall(CM.GetViewRadius)
	local okW, ww, wh = pcall(C_Map.GetMapWorldSize, mapID)
	local okC, cx, cy = pcall(map.GetCenter, map)
	local okS, side = pcall(map.GetWidth, map)
	local okE, scale = pcall(map.GetEffectiveScale, map)
	radius = okR and Finite(radius) or nil
	ww, wh = okW and Finite(ww) or nil, okW and Finite(wh) or nil
	cx, cy = okC and Finite(cx) or nil, okC and Finite(cy) or nil
	side, scale = okS and Finite(side) or nil, okE and Finite(scale) or nil
	if not (radius and ww and wh and cx and cy and side and scale) or radius <= 0 or ww <= 0 or wh <= 0
		or side <= 0 or scale <= 0 then
		return nil
	end
	local mx, my = GetCursorPosition()
	local yards = radius / (side / 2)
	local east, north = (mx / scale - cx) * yards, (my / scale - cy) * yards
	-- (Rotate Minimap: your facing is up; the facing counts from north toward west)
	if GetCVar("rotateMinimap") == "1" then
		local f = Finite(GetPlayerFacing and GetPlayerFacing())
		if not f then
			return nil
		end
		local c, s = math.cos(f), math.sin(f)
		east, north = east * c - north * s, east * s + north * c
	end
	local x, y = px + east / ww, py - north / wh
	if x < 0 or x > 1 or y < 0 or y > 1 then
		return nil
	end
	return mapID, x, y
end

--------------------------------------------------------------------------------
-- The minimap's line
--------------------------------------------------------------------------------

local line   -- { frame, text, on, wait, shown, at } (made the first time it is switched on)

local function Panel()
	local mp = MelloUI.GetModule and MelloUI:GetModule("MinimapPanel")
	return type(mp) == "table" and mp.ColumnSlot and mp or nil
end

-- the minimap's shown part (MelloUI's square crop), else the game's map
local function Area()
	local mp = Panel()
	return (mp and mp.MapFrame and mp:MapFrame()) or Minimap
end

function Coords.MinimapLineHeight()
	local fs = line and line.on and line.text
	if not fs then
		return nil
	end
	local ok, _, size = pcall(fs.GetFont, fs)
	size = ok and Finite(size) or nil
	return (size and size > 0) and math.ceil(size) + 2 or 12
end

-- the room the line takes beside Route's distance (MinimapPanel keeps Route's text to the rest of the rail): its widest
-- form, the pointer and "88.8, 88.8", measured on a spare string in its font; nil while it is off
function Coords.MinimapLineWidth()
	if not (line and line.on) then
		return nil
	end
	local probe = line.probe
	if not probe then
		probe = line.frame:CreateFontString(nil, "OVERLAY")
		probe:Hide()
		line.probe = probe
	end
	local ok, file, size, flags = pcall(line.text.GetFont, line.text)
	if ok and file then
		probe:SetFont(file, size, flags)
	end
	probe:SetText(MelloUI.Icons.Markup(T.POINTER, T.ICON, line.text) .. " " .. T.WIDEST)
	local okW, w = pcall(probe.GetStringWidth, probe)
	w = okW and Finite(w) or nil
	return w and (math.ceil(w) + T.GAP) or nil
end

-- Route's distance line while it shows its text (the coordinates stand just left of it), and the width of that text
-- as it shows (cut to the room it has)
local function RouteText()
	local R = MelloUI.GetModule and MelloUI:GetModule("Route")
	local fs = R and R.isEnabled and R.DistanceLineText and R:DistanceLineText()
	if not (fs and R:DistanceLineShown()) then
		return nil
	end
	local okS, w = pcall(fs.GetStringWidth, fs)
	local okW, box = pcall(fs.GetWidth, fs)
	w, box = okS and Finite(w) or nil, okW and Finite(box) or nil
	if not (w and w > 0) then
		return nil
	end
	if box and box > 0 and box < w then
		w = box
	end
	return fs, math.floor(w + 0.5)
end

-- (the user's pick, 2026-11-11: "Right under the map picture") its place: Route's distance line's, right under the
-- map (on the Services rail at its right end where the Services row is in the frame; nothing under the map moves);
-- while Route's line shows, just left of it on the same line. Set again only when it moved (on 'column' and on the beat:
-- Route's text comes, goes and changes width)
local function Place()
	if not (line and line.on) then
		return
	end
	local rel, point, x, y, justify
	local route, rw = RouteText()
	if route then
		rel, point, x, y, justify = route, "TOPRIGHT", -(rw + T.GAP), 0, "RIGHT"
	else
		local mp = Panel()
		if mp then
			rel, point, x, y, justify = mp:ColumnSlot("coords")
		end
		rel, point, x, y = rel or Minimap, point or "BOTTOM", x or 0, y or -2
	end
	local at = line.at
	if at[1] == rel and at[2] == point and at[3] == x and at[4] == y and at[5] == justify then
		return
	end
	at[1], at[2], at[3], at[4], at[5] = rel, point, x, y, justify
	local fs = line.text
	fs:ClearAllPoints()
	if justify == "RIGHT" then
		fs:SetPoint("TOPRIGHT", rel, point, x, y)
		fs:SetJustifyH("RIGHT")
	else
		fs:SetPoint("TOP", rel, point, x, y)
		fs:SetJustifyH("CENTER")
	end
end

local function Beat(_, elapsed)
	line.wait = line.wait - elapsed
	if line.wait > 0 then
		return
	end
	line.wait = T.BEAT
	local text
	local _, x, y = Coords.MinimapMouse(Area())
	local mouse = x and Coords.Text(x, y)
	if mouse then
		text = MelloUI.Icons.Markup(T.POINTER, T.ICON, line.text) .. " " .. MelloUI:PaletteCode(T.GOLD) .. mouse .. "|r"
	else
		local _, px, py = Coords.Player()
		text = (px and Coords.Text(px, py)) or ""
	end
	if text ~= line.shown then
		line.shown = text
		line.text:SetText(text)
	end
	Place()
end

local function Make()
	local W = MelloUI.Widgets
	local f = CreateFrame("Frame", nil, Minimap)
	f:SetAllPoints(Minimap)
	f:EnableMouse(false)
	f:SetFrameLevel(Minimap:GetFrameLevel() + 6)
	local fs = W.Text(f, "GameFontHighlightSmall", nil, "text")
	fs:SetJustifyH("CENTER")
	fs:SetWordWrap(false)
	line = { frame = f, text = fs, on = false, wait = 0, shown = nil, at = {} }
	MelloUI:On("column", Place, "Coords: the minimap's line")
end

function Coords.Minimap(on)
	on = on and Minimap and true or false
	if not line then
		if not on then
			return
		end
		Make()
	end
	if line.on == on then
		return
	end
	line.on = on
	line.frame:SetShown(on)
	if on then
		line.wait, line.shown = 0, nil
		wipe(line.at)
		Place()
		Perf.SetScript(line.frame, "OnUpdate", Beat)
	else
		Perf.SetScript(line.frame, "OnUpdate", nil)
	end
	-- (the column laid again: Route's text keeps room beside it; under a map with nothing else there, what hangs
	-- under the map makes room for it)
	local mp = Panel()
	if mp and mp.LayColumn then
		mp:LayColumn()
	end
	-- (the rail's name to its left end while the coordinates stand at its right end)
	if mp and mp.RailName then
		mp.RailName()
	end
end

-- (the tests' and the dump's way in)
function Coords.MinimapLine()
	return line
end
