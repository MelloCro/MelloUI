--------------------------------------------------------------------------------
-- MelloUI Map in the Gamepad UI (2.1.49; docs/plans/gamepad.md; the user, 2026-11-12, testing with a controller:
-- "opening the map, opens the game map, not melloui map" -- opened from the Start menu wheel, whose "Quest & Maps"
-- clicks the game's quest log button -- then the picks of BuildData/output/gamepad_map_sketch: "Cover the game's
-- map", "1, B, but make sure that the map looks the same as the map that we already have")
--
-- In the Gamepad UI the game's map keeps opening as the game opens it (the wheel, its keys): MelloUI cannot send that
-- to its own map without closing the game's from its code, which taints the game's pad code. So MelloUI's map covers
-- it at once -- the window as it is (its title row, search, rail, quest column, its line under the map), as tall as
-- the game's window with its prompts under it, on their middle, a plain panel of the palette's over all of them.
--
-- The pad is MelloUI's map's own while it covers (MelloUI.Gamepad's G.Own), with the game's own buttons for its map
-- (the user's videos of the game's map with the pad, then "Map controls": MelloUI's follows the game's exactly; its
-- footers: quests "Select, More, Map (D-pad left), Back"; the map "Change Map (A / X), More, Quests (D-pad right),
-- Fullscreen Map (D-pad down), Marker (L3), Zoom (right stick), Back"). Two views, as the game's:
--   the quests (it opens on them): the column walked as any MelloUI window (MelloUI.Gamepad's spec.nav: the D-pad,
--     the gold frame, A clicks, LB / RB its tabs, the right stick scrolls); Y "More": a quest's page, the focus on its
--     buttons (Show, Route, Share, Tracked, Abandon); the D-pad off the column's left edge: the map; B: a page back to
--     the list, on the list both maps closed. The left stick walks the player here, as in the game's quest view
--   the map: the left stick moves the crosshair (pick 1: thin gold lines across it, a small ring where they meet; at
--     the canvas's edges it pushes the map on; the pin under it shows its tooltip -- the user's test: "my character
--     keeps moving while i navigate the map": the sticks are held here, MelloUI.Gamepad's stick catcher); the right
--     stick zooms about it (Canvas:ZoomAt), LB / RB a notch out / in; A the pin under it (its click; a pin of several
--     spread), else into the map there (Canvas:Deeper); X one map out; Y "More": the map's options (the column's
--     layers' page, walked; B back to the map); the D-pad right: the quests; down: the map as big as the screen
--     (again: back); up: you in the middle; L3 your pin at the crosshair (Ctrl-click's: Route's way there); B both
--     maps closed
--   B closes with the game's own close button's click (a binding click: the game's secure click); a B that steps back
--   acts on its release (B the close again then: a click binding fires as the key comes up)
--   the prompts (pick b): the line under the map is a strip of MelloUI.Gamepad's coins for the view's keys
-- The map also takes the triggers (the game's jumps to its other windows) and the key of the game's own UI focus
-- switch while it covers. The game's map is unseen meanwhile (the user: "the games own map is still visible
-- behind MelloUI Map" -- in the Gamepad UI parts of it stand outside its window: its quest search box over its quest
-- list, its focus glow): its alpha 0, written again only when the game set its own, given back as the cover goes. M
-- (outside the cover) opens MelloUI's map as before, driven as any MelloUI window (the D-pad's focus).
--
--   /mellomap dump   the map's dump ends with the cover's state (Pad.Dump)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_Map (Gamepad)")
local Shared = Perf.Shared
local Safe = MelloUI.Safe
local Finite = Safe.Finite
local W = MelloUI.Widgets
local pcall, type, ipairs, rawget, math, abs = pcall, type, ipairs, rawget, math, math.abs
local min, max = math.min, math.max

local Pad = { on = false, hooked = false }
ns.Pad = Pad

local T = {
	HOVER = 0.1,       -- s between two looks for the pin under the crosshair
	PLACE = 0.25,      -- s between two looks at the game's window and its prompts (the cover laid again on a change)
	RING = 18,         -- the crosshair's ring
	LINE_A = 0.75,     -- its lines' alpha
	SHADE = 3,         -- the dark band under each line
	COIN_GAP = 4, ITEM_GAP = 14,
	STRIP_H = 20,      -- the strip's least height (it grows to its coins: MelloUI.Gamepad sizes them by screen pixels)
	PINS = 400,        -- (MapPins' layer over the canvas's root, when the pins are not made yet)
	OVER_PINS = 60,    -- the crosshair over the pins
	DEAD = 0.18,       -- the sticks' dead zone
	CURVE = 1.6,       -- their answer past it: fine near the middle, fast at full tilt
	SPEED = 0.6,       -- the crosshair at full tilt: canvas widths a second
	EDGE = 0.08,       -- the share of the canvas at each edge where the crosshair pushes the map on
	ZOOM = 3,          -- the right stick at full tilt: the wheel's notches a second
	SETTLE = 0.2,      -- s: a column's page laid and faded in before the focus goes onto its first entry
}
Pad.T = T

-- the strip's actions in each view (key, words: the game's own where it has them); a D-pad key: its arm's coin
local STRIPS = {
	map = {
		{ "PAD1", "Select" }, { "PAD3", "Out" }, { "PAD4", "More" }, { "PADDRIGHT", "Quests" },
		{ "PADDDOWN", "Full Screen" }, { "PADDUP", "You" }, { "PADLSTICK", "Marker" }, { "PADRSTICK", "Zoom" },
		{ "PAD2", "Back" },
	},
	quests = {
		{ "PAD1", "Select" }, { "PAD4", "More" }, { "PADDLEFT", "Map" }, { "PAD2", "Back" },
	},
}

local function Game()
	return rawget(_G, "WorldMapFrame")
end

local function L(s)
	local Lang = MelloUI.Lang
	return (Lang and Lang.T and Lang.T(s)) or s
end

--------------------------------------------------------------------------------
-- The pieces (made the first time the cover is on)
--------------------------------------------------------------------------------

local function Build(win)
	if Pad.back then
		return
	end
	-- the plain panel over the game's window and its prompts (what the map window does not cover)
	local back = CreateFrame("Frame", nil, UIParent)
	back:EnableMouse(true)   -- (no click falls through to the game's map under it)
	back:Hide()
	W.Solid(back, "BACKGROUND", "mainWindow", 1):SetAllPoints(back)
	Pad.back = back
	-- the crosshair on the canvas: two lines (each on a dark band) and a ring where they meet
	local cf = win.canvas.frame
	local x = CreateFrame("Frame", nil, cf)
	x:SetAllPoints(cf)
	-- (over the pins: the canvas's maps take levels up to its root's + twice their count, the pins the root's + 400 --
	-- under them the lines were drawn and never seen, the user's first test in game)
	local pinsLevel = win.pins and win.pins.frame and Finite(win.pins.frame:GetFrameLevel())
	x:SetFrameLevel(min(9000, (pinsLevel or ((Finite(cf:GetFrameLevel()) or 0) + T.PINS)) + T.OVER_PINS))
	x:EnableMouse(false)
	x:Hide()
	x.hShade = W.Solid(x, "ARTWORK", "innerPanel", 0.35)
	x.vShade = W.Solid(x, "ARTWORK", "innerPanel", 0.35)
	x.h = W.Solid(x, "OVERLAY", "selectedTrim", T.LINE_A)
	x.v = W.Solid(x, "OVERLAY", "selectedTrim", T.LINE_A)
	x.hShade:SetHeight(T.SHADE)
	x.vShade:SetWidth(T.SHADE)
	x.h:SetHeight(1)
	x.v:SetWidth(1)
	x.ringShade = x:CreateTexture(nil, "OVERLAY", nil, 1)
	x.ring = x:CreateTexture(nil, "OVERLAY", nil, 2)
	MelloUI.Icons.Set(x.ringShade, "badge_edge", T.RING + 4)
	MelloUI.Icons.Set(x.ring, "badge_edge", T.RING)
	x.ringShade:SetSize(T.RING + 4, T.RING + 4)
	x.ring:SetSize(T.RING, T.RING)
	W.Paint(x.ringShade, "innerPanel", "vertex", 0.6)
	W.Paint(x.ring, "selectedTrim", "vertex", 1)
	Pad.cross = x
	-- the strip of prompts over the line under the map (the name and the hint; the coordinates stay at its right)
	local strip = CreateFrame("Frame", nil, win.body)
	strip:SetPoint("BOTTOMLEFT", win.body, "BOTTOMLEFT", 4, 2)
	strip:SetPoint("RIGHT", win.coords, "LEFT", -8, 0)
	strip:SetHeight(T.STRIP_H)
	strip:SetFrameLevel(cf:GetFrameLevel() + 45)
	W.Solid(strip, "BACKGROUND", "innerPanel", 1):SetAllPoints(strip)
	strip:Hide()
	strip.items = {}
	local G = MelloUI.Gamepad
	local prev
	for i = 1, max(#STRIPS.map, #STRIPS.quests) do
		local coin = G.Coin()
		coin:SetParent(strip)
		coin:SetFrameLevel(strip:GetFrameLevel() + 2)
		if prev then
			coin:SetPoint("LEFT", prev, "RIGHT", T.ITEM_GAP, 0)
		else
			coin:SetPoint("LEFT", strip, "LEFT", 4, 0)
		end
		local words = W.Text(strip, "GameFontHighlight", "", "text")
		words:SetPoint("LEFT", coin, "RIGHT", T.COIN_GAP, 0)
		words:SetJustifyV("MIDDLE")
		strip.items[i] = { coin = coin, words = words }
		prev = words
	end
	Pad.strip = strip
end

-- the strip for a mode: its keys' coins (sized for the screen as it is now) and words; as tall as its coins
local function Strip(mode)
	local strip, list = Pad.strip, STRIPS[mode] or STRIPS.map
	local tall = T.STRIP_H
	for i, item in ipairs(strip.items) do
		local spec = list[i]
		item.key = spec and spec[1] or nil
		if spec then
			MelloUI.Gamepad.SetCoin(item.coin, spec[1])
			item.words:SetText(L(spec[2]))
			item.coin:Show()
			item.words:Show()
			local h = (Finite(item.coin:GetHeight()) or 0) * (Finite(item.coin:GetScale()) or 1)
			tall = max(tall, h + 4)
		else
			item.coin:Hide()
			item.words:Hide()
		end
	end
	strip:SetHeight(tall)
	strip:Show()
end

--------------------------------------------------------------------------------
-- The crosshair (its canvas point Pad.px, Pad.py: canvas units from its top left)
--------------------------------------------------------------------------------

local function Lay(c)
	local x = Pad.cross
	local px, py = Pad.px, Pad.py
	if not (x and px and c.cw) then
		return
	end
	local cf = c.frame
	x.h:ClearAllPoints()
	x.h:SetPoint("LEFT", cf, "TOPLEFT", 0, -py)
	x.h:SetPoint("RIGHT", cf, "TOPRIGHT", 0, -py)
	x.hShade:ClearAllPoints()
	x.hShade:SetPoint("LEFT", cf, "TOPLEFT", 0, -py)
	x.hShade:SetPoint("RIGHT", cf, "TOPRIGHT", 0, -py)
	x.v:ClearAllPoints()
	x.v:SetPoint("TOP", cf, "TOPLEFT", px, 0)
	x.v:SetPoint("BOTTOM", cf, "BOTTOMLEFT", px, 0)
	x.vShade:ClearAllPoints()
	x.vShade:SetPoint("TOP", cf, "TOPLEFT", px, 0)
	x.vShade:SetPoint("BOTTOM", cf, "BOTTOMLEFT", px, 0)
	x.ring:ClearAllPoints()
	x.ring:SetPoint("CENTER", cf, "TOPLEFT", px, -py)
	x.ringShade:ClearAllPoints()
	x.ringShade:SetPoint("CENTER", cf, "TOPLEFT", px, -py)
	x:Show()
end

-- the crosshair kept on the canvas (its middle at the first look; within its size, which a new window size moves)
local function Keep(c)
	if not c.cw then
		return false
	end
	if not Pad.px then
		Pad.px, Pad.py = c.cw / 2, c.ch / 2
	end
	Pad.px, Pad.py = min(max(Pad.px, 0), c.cw), min(max(Pad.py, 0), c.ch)
	return true
end

-- a stick's tilt past the dead zone, on the curve (-1..1)
local function Tilt(v)
	local a = abs(Finite(v) or 0)
	if a <= T.DEAD then
		return 0
	end
	a = min(1, (a - T.DEAD) / (1 - T.DEAD)) ^ T.CURVE
	return v < 0 and -a or a
end
Pad.Tilt = Tilt

--------------------------------------------------------------------------------
-- The pad (G.Own's spec while the cover is on)
--------------------------------------------------------------------------------

local hoverIn = 0
local Mode, Place   -- (below)

local function CloseKey()
	return rawget(_G, "WorldMapFrameCloseButton") and "click:WorldMapFrameCloseButton" or "CLOSE"
end

-- each frame while the map has the pad (MelloUI.Gamepad's driver): on the map the sticks and the crosshair; in the
-- quests' view B kept as the game's (a page over the list: a step back; the list: both maps closed)
local function Sticks(lx, ly, rx, ry, dt)
	local M = ns.Map
	local c = M and M:Canvas()
	if not (Pad.on and c and c.cx and Keep(c)) then
		return
	end
	if Pad.mode == "quests" then
		if not (Pad.nav and Pad.nav:IsVisible()) then
			Mode("map")   -- (the column folded away: the map)
			return
		end
		local want = M.PadOnPage() and "BACK" or CloseKey()
		if Pad.b ~= want then
			Pad.b = want
			MelloUI.Gamepad.OwnKey("PAD2", want)
		end
		return
	end
	dt = Finite(dt) or 0
	local mx, my = Tilt(lx), Tilt(ly)
	if mx ~= 0 or my ~= 0 then
		local v = T.SPEED * c.cw * dt
		local x, y = Pad.px + mx * v, Pad.py - my * v   -- (the stick up: up on the screen, the canvas's y down)
		-- (past the edge band the crosshair stays and the map moves on under it, as the game's own map cursor does)
		local ex, ey = c.cw * T.EDGE, c.ch * T.EDGE
		local ox = (x < ex and x - ex) or (x > c.cw - ex and x - (c.cw - ex)) or 0
		local oy = (y < ey and y - ey) or (y > c.ch - ey and y - (c.ch - ey)) or 0
		Pad.px, Pad.py = x - ox, y - oy
		if ox ~= 0 or oy ~= 0 then
			local wx, wy = c:Point(Pad.px, Pad.py)
			local k = c.k1 * c.z
			c:Hold(wx + ox / k, wy + oy / k, Pad.px, Pad.py)
		end
	end
	local zoom = Tilt(ry)
	if zoom ~= 0 then
		c:ZoomAt(Pad.px, Pad.py, zoom * T.ZOOM * dt)
	end
	Lay(c)
	-- (the pin under the crosshair: its tooltip)
	hoverIn = hoverIn - dt
	if hoverIn <= 0 then
		hoverIn = T.HOVER
		M.PadHover(Pad.px, Pad.py)
	end
end
Pad.Sticks = Sticks

-- a key of the map's (MelloUI.Gamepad's key button, the name bound to it); in the quests' view the D-pad, A and the
-- tabs are MelloUI.Gamepad's navigation's, the rest come here
local function Press(name, down, dir)
	local M = ns.Map
	if not (Pad.on and M) then
		return
	end
	if name == "QUESTS" then
		if down then
			Mode("quests")
		end
		return
	elseif name == "BACK" then
		-- (B over a page in the column: on its release -- B is the game's close again then, which a click binding fires
		-- as the key comes up; back on the list the focus on the quest it came from)
		if not down then
			local to, row = M.PadBack()
			if to == "map" then
				Mode("map")
			elseif row and Pad.nav then
				MelloUI.Gamepad.Focus(row, Pad.nav)
			end
		end
		return
	elseif name == "EDGE" then
		if dir == "LEFT" then
			Mode("map")   -- (the column's left edge: the map beside it, the game's "Map" on the D-pad's left)
		end
		return
	elseif name == "MORE" then
		if down and Pad.mode == "quests" then
			local G = MelloUI.Gamepad
			local b = M.PadMore(G.Current())
			if b and Pad.nav then
				G.Focus(b, Pad.nav)
			end
		elseif down then
			Mode("quests", "layers")   -- (the map's options)
		end
		return
	elseif name == "FULL" then
		if down then
			Pad.full = not Pad.full
			local game, f = Game(), M:Window().frame
			if game and f then
				Place(game, f)
			end
		end
		return
	end
	local c = M:Canvas()
	if not (down and c and c.cx and Keep(c)) then
		return
	end
	local px, py = Pad.px, Pad.py
	if name == "SELECT" then
		if not M.PadPress(px, py) then
			c:Deeper(px, py)
		end
	elseif name == "OUT" then
		c:Out()
	elseif name == "ME" then
		if M.PadMe() then
			Pad.px, Pad.py = c.cw / 2, c.ch / 2   -- (on you as the map comes to rest)
			Lay(c)
		end
	elseif name == "PIN" then
		M.PadPin(px, py)
	elseif name == "ZOOMIN" or name == "ZOOMOUT" then
		c:ZoomAt(px, py, name == "ZOOMIN" and 1 or -1)
	elseif name == "CLOSE" then
		local f = M:Window().frame
		if f then
			f:Hide()
		end
	end
end
Pad.Press = Press

-- the keys the map takes while it covers, by view (the game's own map's): on the map its own, the game's close
-- button for B; in the quests' view the navigation's names (MelloUI.Gamepad's), B a step back over a page, else the
-- close. In both the keys that would reach the game's map under it bound to nothing: its jumps to other windows on
-- the triggers, its UI focus switch on the key the player gave it
local function Keys(mode)
	local keys
	if mode == "quests" then
		local M = ns.Map
		keys = {
			PADDUP = "UP", PADDDOWN = "DOWN", PADDLEFT = "LEFT", PADDRIGHT = "RIGHT", PAD1 = "A", PAD4 = "MORE",
			PAD2 = (M and M.PadOnPage() and "BACK") or CloseKey(),
			PAD3 = "NONE", PADLSTICK = "NONE", PADRSTICK = "NONE",
			PADLSHOULDER = "NONE", PADRSHOULDER = "NONE",   -- (LB / RB the column's tabs: MelloUI.Gamepad binds them)
		}
	else
		keys = {
			PAD1 = "SELECT", PAD3 = "OUT", PAD4 = "MORE", PADLSTICK = "PIN", PADRSTICK = "NONE",
			PADLSHOULDER = "ZOOMOUT", PADRSHOULDER = "ZOOMIN",
			PADDUP = "ME", PADDDOWN = "FULL", PADDLEFT = "NONE", PADDRIGHT = "QUESTS", PAD2 = CloseKey(),
		}
	end
	keys.PADBACK, keys.PADLTRIGGER, keys.PADRTRIGGER = "NONE", "NONE", "NONE"
	local ok, a, b = pcall(GetBindingKey, "TOGGLEUIFOCUS")
	for _, key in ipairs({ ok and a or false, ok and b or false }) do
		if type(key) == "string" and key ~= "" and not keys[key] then
			keys[key] = "NONE"
		end
	end
	return keys
end
Pad.Keys = Keys

-- the map's pad in a view ("map": the crosshair, the sticks held; "quests": the column walked, `nav` its frame, the
-- left stick the player's as in the game's quest view)
local function Spec(mode, nav)
	return { keys = Keys(mode), press = Press, sticks = Sticks, over = true, nav = nav, walk = mode == "quests" or nil }
end

-- a view (and in the quests' one the column's page: "log", the default; "layers", the map's options)
Mode = function(mode, page)
	if not Pad.on or (Pad.mode == mode and not page) then
		return
	end
	local M = ns.Map
	local f = M and M:Window().frame
	if not f then
		return
	end
	local nav
	if mode == "quests" then
		nav = M.PadQuests(page)   -- (out, on that page)
		if not nav then
			return
		end
		M.PadHover(nil)
		Pad.cross:Hide()
	end
	Pad.mode, Pad.nav = mode, nav
	Strip(mode)
	local spec = Spec(mode, nav)
	Pad.b = spec.keys.PAD2
	local G = MelloUI.Gamepad
	G.Own(f, spec)
	local c = mode == "map" and M:Canvas()
	if c and Keep(c) then
		Lay(c)
	end
	if nav then
		-- (the page laid and faded in: the focus on its first entry, as the game's quest view opens -- unless the
		-- player has moved it meanwhile)
		local was = G.Current()
		Perf.C_Timer.After(T.SETTLE, function()
			if Pad.mode ~= "quests" or Pad.nav ~= nav or G.Current() ~= was then
				return
			end
			local first = M.PadFirst()
			if first then
				G.Focus(first, nav)
			end
		end)
	end
end
Pad.Mode = Mode

--------------------------------------------------------------------------------
-- The cover's place: the game's window and its prompts under it (screen pixels)
--------------------------------------------------------------------------------

local FOOTERS = { "questLogFooter", "questDetailsFooter", "worldMapFooter" }

-- the game's window and its shown prompts together (reads only): l, b, r, t or nil
local function Union(game)
	local l, b, r, t = Safe.ScreenRect(game)
	if not l then
		return nil
	end
	for _, key in ipairs(FOOTERS) do
		local footer = rawget(game, key)
		local legend = type(footer) == "table" and rawget(footer, "inputLegend")
		if type(legend) == "table" and legend.IsVisible and legend:IsVisible() then
			local ll, lb, lr, lt = Safe.ScreenRect(legend)
			if ll then
				l, b, r, t = min(l, ll), min(b, lb), max(r, lr), max(t, lt)
			end
		end
	end
	return l, b, r, t
end

local function Up(strata)
	local up = MelloUI.STRATA_UP
	return type(up) == "table" and up[strata] or "DIALOG"
end

-- the panel over the game's window and its prompts, the map window as tall as they are, on their middle; the map as
-- big as the screen (the D-pad down, the game's "Fullscreen Map"): the panel over the whole screen, the window in it
Place = function(game, f)
	local l, b, r, t
	if Pad.full then
		l, b, r, t = Safe.ScreenRect(UIParent)
	else
		l, b, r, t = Union(game)
	end
	local fs, bs = Finite(f:GetEffectiveScale()), Finite(Pad.back:GetEffectiveScale())
	if not (l and fs and bs) or fs <= 0 or bs <= 0 or r <= l or t <= b then
		return
	end
	local p = Pad.placed or {}
	Pad.placed = p
	if p[1] == l and p[2] == b and p[3] == r and p[4] == t and p.f == fs and p.full == Pad.full then
		return
	end
	p[1], p[2], p[3], p[4], p.f, p.full = l, b, r, t, fs, Pad.full
	local back = Pad.back
	back:ClearAllPoints()
	back:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l / bs, b / bs)
	back:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", r / bs, t / bs)
	local M = ns.Map
	M.Grip.Apply(M.MapWidthFor((t - b) / fs))
	p.cx, p.cy = (l + r) / 2 / fs, (b + t) / 2 / fs
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.cx, p.cy)
end

-- the game's map unseen while covered: its alpha 0 (its own kept to give back), written again only when the game set
-- its own (its fade while moving)
local function Unseen(game)
	local a = Finite(game:GetAlpha())
	if a and a > 0 then
		if Pad.alpha == nil then
			Pad.alpha = a
		end
		game:SetAlpha(0)
	end
end

local function Seen()
	local game, a = Game(), Pad.alpha
	Pad.alpha = nil
	if game and a then
		game:SetAlpha(a)
	end
end

local placeIn = 0
local Back_OnUpdate = Shared("OnUpdate on MelloUI Map's cover of the game's map (only while it covers)",
	function(_, elapsed)
		local game, M = Game(), ns.Map
		local f = M and M:Window().frame
		if not (game and f and Pad.on) then
			return
		end
		Unseen(game)
		-- (the game's prompts may show after its window; the quest column's reveal moves the window as it widens)
		placeIn = placeIn - (elapsed or 0)
		local p = Pad.placed
		local moved = false
		if p and p.cx and f:GetNumPoints() == 1 then
			local _, rel, _, x, y = f:GetPoint(1)
			x, y = Finite(x), Finite(y)
			moved = rel ~= UIParent or (x and abs(x - p.cx) > 0.5) or (y and abs(y - p.cy) > 0.5)
		end
		if placeIn <= 0 or moved then
			placeIn = T.PLACE
			if moved and p then
				p.f = nil   -- (laid again even where the game's rects did not move)
			end
			Place(game, f)
		end
	end, "script")

--------------------------------------------------------------------------------
-- On and off
--------------------------------------------------------------------------------

function Pad.On()
	local game, M = Game(), ns.Map
	if not (game and M and M.isEnabled) then
		return
	end
	if not M:Window().frame or not M:Window().frame:IsShown() then
		M:ToggleLog()   -- (the map with your quests beside it: the wheel's entry is the game's map and quest log)
	end
	local win = M:Window()
	local f = win.frame
	if not (f and f:IsShown()) then
		return
	end
	Build(win)
	Pad.HookWindow(f)
	Pad.on = true
	Pad.px, Pad.py, Pad.placed, Pad.mode, Pad.nav, Pad.full = nil, nil, nil, nil, nil, nil
	-- a strata over the game's map and over the layer the game's map has over it (the Quest List's page there)
	local strata = Up(Up(game:GetFrameStrata()))
	Pad.strata = f:GetFrameStrata()
	f:SetFrameStrata(strata)
	local back = Pad.back
	back:SetFrameStrata(strata)
	back:SetFrameLevel(max(0, (Finite(f:GetFrameLevel()) or 2) - 1))
	Place(game, f)
	back:Show()
	Unseen(game)
	placeIn = T.PLACE
	Perf.SetScript(back, "OnUpdate", Back_OnUpdate)
	-- the pad the map's own while it covers: on the quests first, as the game's map opens
	Mode("quests")
	if not Pad.mode then
		Mode("map")
	end
end

-- the cover's pieces gone; the window back at its own strata, size and place, driven as any window again
local function Uncover(f)
	Perf.SetScript(Pad.back, "OnUpdate", nil)
	Pad.back:Hide()
	Pad.cross:Hide()
	Pad.strip:Hide()
	Seen()
	Pad.px, Pad.py, Pad.mode, Pad.nav, Pad.full = nil, nil, nil, nil, nil
	local M = ns.Map
	if M then
		M.PadHover(nil)
	end
	if f then
		f:SetFrameStrata(Pad.strata or "HIGH")
		MelloUI.Gamepad.Own(f, nil)
	end
end

function Pad.Off()
	if not Pad.on then
		return
	end
	Pad.on = false
	local M = ns.Map
	local f = M and M:Window().frame
	if f and f:IsShown() then
		f:Hide()
	end
	Uncover(f)
	if f then
		M.PlaceBack()
	end
end

-- the game's map shown or hidden (post-hooks: nothing written on it)
local GameShown = Shared("OnShow on the game's world map (MelloUI Map covers it in the Gamepad UI)", function()
	local G = MelloUI.Gamepad
	if G and G.On() then
		Pad.On()
	end
end, "script")

local GameHidden = Shared("OnHide on the game's world map (MelloUI Map's cover goes with it)", function()
	Pad.Off()
end, "script")

function Pad.Hook()
	local game = Game()
	if Pad.hooked or not game then
		return
	end
	Pad.hooked = true
	Perf.HookScript(game, "OnShow", GameShown)
	Perf.HookScript(game, "OnHide", GameHidden)
	-- (the map window closed by its own close button or Escape: the cover goes too)
	local M = ns.Map
	local win = M and M:Window()
	if win and win.frame then
		Pad.HookWindow(win.frame)
	end
end

local windowHooked = false
local MapHidden = Shared("OnHide on MelloUI Map's window (its cover of the game's map goes too)", function()
	if Pad.on then
		Pad.on = false   -- (Off without hiding the window again)
		local M = ns.Map
		local f = M and M:Window().frame
		Uncover(f)
		if f then
			M.PlaceBack()
		end
	end
end, "script")

function Pad.HookWindow(frame)
	if not windowHooked and frame then
		windowHooked = true
		Perf.HookScript(frame, "OnHide", MapHidden)
	end
end

-- the hooks at the first time the Gamepad UI is on (at the login in it, or switched to); the game's map may load
-- later than MelloUI (then at its own ADDON_LOADED)
local function Ready()
	local G = MelloUI.Gamepad
	if not (G and G.On()) or Pad.hooked then
		return
	end
	if Game() then
		Pad.Hook()
	end
end

local events = CreateFrame("Frame")
Perf.SetScript(events, "OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" and name == "Blizzard_WorldMap" then
		Ready()
	elseif event == "PLAYER_LOGIN" then
		Ready()
	end
end)
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
MelloUI:On("gamepad", Ready, "MelloUI Map: the Gamepad UI's cover of the game's map")

function Pad.Dump(out)
	out = out or print
	local G = MelloUI.Gamepad
	out(("Map in the Gamepad UI: hooked %s, covering %s (%s), the pad the map's %s, crosshair %s, the game's map's "
		.. "alpha kept %s"):format(tostring(Pad.hooked), tostring(Pad.on), tostring(Pad.mode or "-"),
		tostring(G and G.Holding and G.Holding() or false), Pad.px and ("%.0f, %.0f"):format(Pad.px, Pad.py) or "-",
		tostring(Pad.alpha)))
	local p = Pad.placed
	if p and p[1] then
		out(("  the game's window and its prompts on the screen %.0f %.0f %.0f %.0f"):format(p[1], p[2], p[3], p[4]))
	end
	if Pad.on then
		local keys = {}
		for key, what in pairs(Keys(Pad.mode)) do
			keys[#keys + 1] = key .. "=" .. what
		end
		table.sort(keys)
		out("  keys: " .. table.concat(keys, " "))
	end
end
