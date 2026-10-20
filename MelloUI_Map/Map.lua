--------------------------------------------------------------------------------
-- MelloUI Map (docs/plans/seamless-map.md; the user, 2026-10-20: "i want our
-- map to function like that, just improved version of it")
--
-- One seamless map of the whole world in a window of MelloUI's own
-- (Kit:OwnWindow): the mouse wheel zooms toward the cursor from Azeroth down
-- to a zone, a drag pans, a left click glides into the map under the cursor
-- and a right click goes out one. The view is kept between sessions. It never
-- touches the game's world map: no hook, no key on a Blizzard frame, no
-- method replaced (hard rule 1); the game's map stays as it is, for the quest
-- log, the Gamepad UI and other addons.
--
-- Stage M0 (this file and MapCanvas.lua): the window, the world's places from
-- the client's own data, the art by file ID, zoom, pan and glide, culling,
-- the view saved, /melloperf map. Layers (the player, Route, quests ...), the
-- look of the edges and the close zoom come in the stages after.
--
-- Nothing at login: the module's switch and its slash command only; the
-- window and its canvas are made the first time the map opens.
--
--   /mellomap, /mmap        open or close it (also a key binding, unbound)
--   /mellomap dump          the places and the view, to copy
--   /melloperf map          the canvas's numbers: open, a view's Lua time, the
--                           frames while it moves, tiles made and shown
--------------------------------------------------------------------------------

local ADDON, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_Map (Map)")
local Finite = MelloUI.Safe.Finite
local W = MelloUI.Widgets
local Kit = MelloUI.Kit
local Canvas, Pins, Layers = ns.Canvas, ns.Pins, ns.Layers
local floor, max = math.floor, math.max

local ICON = "Interface\\Icons\\INV_Misc_Map_01"

local T = {
	SHARE = 0.72,      -- the window's width: this share of the screen's (its height from the world's 3 : 2)
	MIN_W = 640,
	PAD = 14, TOP = 34, FOOT = 24, IN = 1,
	HOVER = 0.1,       -- the name under the cursor read at most this often
	CLICK = 4,         -- a press that moved less than this is a click
}

local TEXT = {
	title = "Map",
	hint = "Wheel: zoom   Drag: look around   Click: in   Right-click: out   Middle-click: find me",
	open = "Open The Map",
	usage = "/mellomap: open or close the map | /mellomap dump: its places and the view, to copy",
	off = "The map is off: switch it on in /mello (Quests and travel > Map).",
}

local M   -- (the module: its button opens it)
M = MelloUI:RegisterModule("Map", {
	title = "Map",
	desc = "One seamless map of the whole world: zoom from Azeroth down to a zone with the mouse wheel and drag to look around.",
	icon = ICON,
	flavour = "The whole world on one sheet, from the continents down to a village.",
	group = "Quests and travel", navOrder = 4,
	role = "feature",
	enabledByDefault = true,
	defaults = {},
	options = {
		{ type = "button", name = TEXT.open, text = "Open", new = "0.25.0",
		  desc = "Open MelloUI's map: the wheel zooms toward the cursor, a drag looks around, a click glides into the zone under the cursor and a right-click goes out again. /mellomap opens it too, and you can give it a key in the game's Key Bindings (AddOns).",
		  onClick = function() M:Toggle(true) end },
	},
})

local win = {}

--------------------------------------------------------------------------------
-- The view kept: the centre on the world (0..1) and the zoom
--------------------------------------------------------------------------------

local function SaveView()
	local c = win.canvas
	if not (c and c.cx and M.db) then
		return
	end
	M.db.view = { x = c.cx / c.W, y = c.cy / c.H, z = c.z }
end

-- the view to open at: the one kept, else the player's zone (or the world)
local function StartView(c)
	local v = M.db and M.db.view
	if type(v) == "table" then
		local x, y, z = Finite(v.x), Finite(v.y), Finite(v.z)
		if x and y and z then
			return x * c.W, y * c.H, z
		end
	end
	local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
	id = ok and Finite(id) or nil
	local p = id and c.byID[id]
	if p then
		return c:FitOf(p)
	end
	return c.W / 2, c.H / 2, 1
end

--------------------------------------------------------------------------------
-- Input: the wheel, a drag, a click; the name under the cursor
--------------------------------------------------------------------------------

local function ShowName(name)
	if name ~= win.shownName then
		win.shownName = name
		win.name:SetText(name or TEXT.hint)
	end
end

-- a pin's tooltip (its spec's tip: a text, or fn(pin) -> title, body), or none
local function PinTip(pin)
	if pin == win.tipPin then
		return
	end
	win.tipPin = pin
	if not pin then
		GameTooltip:Hide()
		return
	end
	local fill = pin.spec.fillTip
	if fill then
		-- (a whole tooltip of its own: the Quest List's marks' lines)
		GameTooltip:SetOwner(win.canvas.frame, "ANCHOR_CURSOR")
		fill(GameTooltip, pin)
		GameTooltip:Show()
		return
	end
	local tip = pin.spec.tip
	local title, body = tip, nil
	if type(tip) == "function" then
		title, body = tip(pin)
	end
	if title then
		W.ShowTooltip(win.canvas.frame, title, body, nil, "ANCHOR_CURSOR")
	else
		GameTooltip:Hide()
	end
end

-- the deepest map under the cursor (names the footer), the pin under it (its tooltip)
local function Hover()
	local c = win.canvas
	local x, y = c:Cursor()
	if not x then
		ShowName(nil)
		PinTip(nil)
		return
	end
	PinTip(not win.drag.on and win.pins:At(x, y) or nil)
	local path = c:Path(x, y, win.path)
	local p = path[#path]
	ShowName(p and p.kind ~= "world" and p.name or nil)
end

-- one handler while the cursor is over the canvas or a drag runs: the drag's pan, the name (throttled)
local function Watch_OnUpdate(frame, elapsed)
	local c = win.canvas
	local d = win.drag.on and win.drag
	if d then
		local x, y = c:Cursor()
		if x then
			local dx, dy = x - d.x, y - d.y
			if not d.moved and (dx * dx + dy * dy) >= T.CLICK * T.CLICK then
				d.moved = true
				c.moving = true
				c.stats.lastAt = nil
			end
			if d.moved then
				local k = c.k1 * c.z
				c:SetView(d.cx - dx / k, d.cy - dy / k, c.z)
			end
		end
	end
	win.hoverIn = (win.hoverIn or 0) - elapsed
	if win.hoverIn <= 0 then
		win.hoverIn = T.HOVER
		Hover()
	end
	if not (d or win.over) then
		Perf.SetScript(frame, "OnUpdate", nil)
	end
end

local function Watch(on)
	local f = win.canvas.frame
	if on then
		Perf.SetScript(f, "OnUpdate", Watch_OnUpdate)
	end
end

local function Canvas_OnMouseWheel(_, delta)
	local c = win.canvas
	local x, y = c:Cursor()
	if not x then
		x, y = c.cw / 2, c.ch / 2
	end
	c:ZoomAt(x, y, delta > 0 and 1 or -1)
end

local function Canvas_OnMouseDown(_, button)
	local c = win.canvas
	if button ~= "LeftButton" then
		return
	end
	local x, y = c:Cursor()
	if not x then
		return
	end
	c:Stop()
	local d = win.drag
	d.on, d.x, d.y, d.cx, d.cy, d.moved = true, x, y, c.cx, c.cy, false
	Watch(true)
end

local function Canvas_OnMouseUp(_, button)
	local c = win.canvas
	if button == "RightButton" then
		c:Out()
		return
	elseif button == "MiddleButton" then
		Layers.FindMe()
		return
	end
	local d = win.drag
	if not d.on then
		return
	end
	d.on = false
	if d.moved then
		c.moving = false
		c.stats.lastAt = nil
		c:Refocus()
		SaveView()
	else
		-- (a click on a pin is the pin's; elsewhere a glide in)
		local pin = win.pins:At(d.x, d.y)
		if pin and pin.spec.click then
			pin.spec.click(pin, button)
		else
			c:Deeper(d.x, d.y)
		end
	end
end

local function Canvas_OnEnter()
	win.over = true
	win.hoverIn = 0
	Watch(true)
end

local function Canvas_OnLeave()
	win.over = false
	ShowName(nil)
	PinTip(nil)
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local function Size()
	local sw = Finite(UIParent:GetWidth()) or 1280
	local sh = Finite(UIParent:GetHeight()) or 720
	local w = max(T.MIN_W, floor(sw * T.SHARE))
	local h = floor(w * 668 / 1002) + T.TOP + T.FOOT + T.PAD
	if h > sh * 0.9 then
		h = floor(sh * 0.9)
		w = floor((h - T.TOP - T.FOOT - T.PAD) * 1002 / 668)
	end
	return w, h
end

-- the window's parts where the look puts them, at the build and at every switch (shell:OnKit)
local function Lay(sh)
	local body, f = win.body, win.frame
	local edge, top = sh:Inset(T.PAD, -T.TOP)
	body:ClearAllPoints()
	body:SetPoint("TOPLEFT", f, "TOPLEFT", edge, top)
	body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -edge, edge)
end

-- the view laid again on the canvas's size: the first one (the one kept, else your zone) the first time it has a
-- size -- at the show, or at a later size change when the show came before the layout
local function Refit()
	local c = win.canvas
	if not (c.places and c:Size()) then
		return
	end
	c.box[5] = nil
	if c.cx then
		c:SetView(c.cx, c.cy, c.z)
	else
		c:SetView(StartView(c))
	end
end

local function Canvas_OnSizeChanged()
	if win.frame:IsShown() then
		Refit()
	end
end

local function Shown()
	local c = win.canvas
	local t0 = debugprofilestop()
	c:Layout()
	Refit()
	Layers.Open()
	c.stats.openMs = debugprofilestop() - t0
	local f = win.frame
	f:RegisterEvent("MAP_EXPLORATION_UPDATED")
	f:RegisterEvent("TAXIMAP_OPENED")
	f:RegisterEvent("TAXI_NODE_STATUS_CHANGED")
end

local function Hidden()
	Layers.Close()
	win.drag.on = false
	PinTip(nil)
	win.over = false
	if win.canvas then
		win.canvas:Stop()
		win.canvas.moving = false
	end
	SaveView()
	local f = win.frame
	f:UnregisterEvent("MAP_EXPLORATION_UPDATED")
	f:UnregisterEvent("TAXIMAP_OPENED")
	f:UnregisterEvent("TAXI_NODE_STATUS_CHANGED")
end

-- the window's beat while it shows (the layers' positions; nothing runs while it is closed)
local function Frame_OnUpdate(_, elapsed)
	Layers.Tick(elapsed)
end

local function Frame_OnEvent(_, event)
	if event == "MAP_EXPLORATION_UPDATED" and win.canvas then
		win.canvas:Explored()
	elseif event == "TAXIMAP_OPENED" or event == "TAXI_NODE_STATUS_CHANGED" then
		Layers.Event()   -- (a flight point learned, or a flight master's map: the flights again)
	end
end

local function Build()
	local f = CreateFrame("Frame", "MelloUIMapFrame", UIParent)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetSize(Size())
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:Hide()
	win.frame = f
	win.path = {}
	win.drag = { on = false }
	win.shell = Kit:OwnWindow(f, {
		area = "config", ring = { at = "tl", texture = ICON }, plate = "rail",
		title = TEXT.title, close = true, escape = true, fit = true, sounds = true,
		mover = { key = "MelloUIMap", label = TEXT.title, page = "Map" },
	})
	local body = W.Panel(f)
	win.body = body
	-- the canvas over the body, the name under the cursor on the line below it (on the panel: dark ground)
	local canvas = Canvas.New(body)
	local cf = canvas.frame
	cf:SetPoint("TOPLEFT", body, "TOPLEFT", T.IN, -T.IN)
	cf:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -T.IN, T.FOOT)
	cf:EnableMouse(true)
	cf:EnableMouseWheel(true)
	win.canvas = canvas
	canvas.onRest = SaveView
	-- the pins over it (never scaled), laid with every view; the layers that feed them
	local pins = Pins.New(canvas)
	win.pins = pins
	canvas.onView = function()
		pins:Lay()
		Layers.Route()
	end
	Layers.Init(canvas, pins)
	local name = W.Text(body, "GameFontHighlight", nil, "text")
	name:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 8, 5)
	name:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -8, 5)
	name:SetJustifyV("BOTTOM")
	name:SetWordWrap(false)
	win.name = name
	ShowName(false)
	Perf.SetScript(cf, "OnMouseWheel", Canvas_OnMouseWheel)
	Perf.SetScript(cf, "OnMouseDown", Canvas_OnMouseDown)
	Perf.SetScript(cf, "OnMouseUp", Canvas_OnMouseUp)
	Perf.SetScript(cf, "OnEnter", Canvas_OnEnter)
	Perf.SetScript(cf, "OnLeave", Canvas_OnLeave)
	Perf.SetScript(cf, "OnSizeChanged", Canvas_OnSizeChanged)
	Perf.HookScript(f, "OnShow", Shown)
	Perf.HookScript(f, "OnHide", Hidden)
	Perf.SetScript(f, "OnEvent", Frame_OnEvent)
	Perf.SetScript(f, "OnUpdate", Frame_OnUpdate)
	Lay(win.shell)
	win.shell:OnKit(Lay)
end

-- the canvas and its pins (nil until the map first opens): the layers' and the tests' way in
function M:Canvas()
	return win.canvas, win.pins
end

function M:Toggle(show)
	if not self.isEnabled then
		MelloUI:Print(TEXT.off)
		return
	end
	if not win.frame then
		Build()
	end
	if show == nil then
		show = not win.frame:IsShown()
	end
	win.frame:SetShown(show and true or false)
end

--------------------------------------------------------------------------------
-- /mellomap dump and /melloperf map
--------------------------------------------------------------------------------

local function F(v)
	return v and string.format("%.4f", v) or "-"
end

local function Dump()
	local c = win.canvas
	if not (c and c.places) then
		return "The map has not been opened yet."
	end
	local out = {}
	out[#out + 1] = string.format("world %s x %s, view %s %s zoom %s (max %s), canvas %s x %s", F(c.W), F(c.H),
		F(c.cx), F(c.cy), F(c.z), F(c.zMax), F(c.cw), F(c.ch))
	c:EachPlace(function(p)
		out[#out + 1] = string.format("%5d %-9s %-24s %s %s %s %s alpha %s %s tiles %s", p.id, p.kind, p.name or "?",
			F(p.left / c.W), F(p.right / c.W), F(p.top / c.H), F(p.bottom / c.H), F(p.alpha), p.live and "live" or "-",
			p.tiles and #p.tiles or "-")
	end)
	return table.concat(out, "\n")
end

local function PerfReport()
	local c = win.canvas
	if not (c and c.places) then
		return "The map has not been opened yet: open it (/mellomap), move it about, then /melloperf map again."
	end
	local s = c:Stats()
	local avg = s.moveFrames > 0 and s.moveSum / s.moveFrames or 0
	local lines = {
		string.format("Places laid: %d (in %.2f ms, at the first open)", s.placed, s.layoutMs or 0),
		string.format("Last open: %.2f ms", s.openMs or 0),
		string.format("View set %d times: the last %.3f ms, the most %.3f ms of Lua", s.views, s.lastMs, s.maxMs),
		string.format("While it moved: %d frames, %.1f ms on average, %.1f ms the longest", s.moveFrames, avg, s.moveMax),
		string.format("Culled %d times; maps in view %d; tiles shown %d of %d known, %d made, %d files set, %d waiting",
			s.culls, s.live, s.shown, s.tiles, s.made, s.files, s.queued),
		"The numbers since the last /melloperf map reset.",
	}
	return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db or self.db
end

function M:OnDisable()
	if win.frame then
		win.frame:Hide()
	end
end

SLASH_MELLOMAP1 = "/mellomap"
SLASH_MELLOMAP2 = "/mmap"
SlashCmdList.MELLOMAP = function(msg)
	local cmd = strtrim(msg or ""):lower()
	if cmd == "dump" then
		MelloUI:ShowText("Map", Dump())
	elseif cmd == "" then
		M:Toggle()
	else
		MelloUI:Print(TEXT.usage)
	end
end

if MelloUI.Perf.AddReport then
	MelloUI.Perf:AddReport("map", "Performance: the map", function(arg)
		if arg == "reset" and win.canvas then
			win.canvas:ResetStats()
			return "The map's numbers start again."
		end
		return PerfReport()
	end)
end

-- the key binding's names (Bindings.xml)
BINDING_HEADER_MELLOUI = "MelloUI"
BINDING_NAME_MELLOUI_MAP_TOGGLE = "Open or close MelloUI's map"

ns.Map = M
ns.addon = ADDON
