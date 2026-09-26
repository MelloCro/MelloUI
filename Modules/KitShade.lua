--------------------------------------------------------------------------------
-- MelloUI - Kit shade: the whole UI's shade (0.14.0)
--
-- Every kit element gets a soft dark shade that follows its own outline
-- (user, 2026-09-26: "on by default, strength 70% (slider 30-90%), outline
-- pieces only"; the ui-shade-plan memory): the shadow partners of the kit
-- (Kit:Shadow, Kit:ShadowNine, Modules/Kit.lua), laid under the pieces that
-- form an element's outline against the world, never under an inner piece
-- (that would only darken the window's own stone). One system for every area:
--
--   Kit.shadeAreas     the areas in the order the settings list them:
--                      { name, label, key = "shade_<name>" } each; windows,
--                      actionbars, castbars, unitframes, chat (and the
--                      whisper popups), bags, minimap (and the Services bar),
--                      tracker (the objective tracker and the Quest Tracker),
--                      buffs, widgets (the event widgets), nameplates
--   Kit:ShadeOn(area) -> the area's shade wanted: UI Shade on and the area's
--                      switch on (false for a name not in the list)
--   Kit:ShadeStrength() -> 0.3 .. 0.9 (0.7 by default)
--   Kit:ShadeElement(root, area, opts) -> element
--       one element of an area (a unit frame, an action bar group, a chat
--       window, a window): its partners drawn by ONE shade frame, a child of
--       `root` one level below it (under everything the element draws, over
--       the world), made with its first partner. The same root and area give
--       the same element. opts, read once:
--         host   a frame of the element's own to draw them instead (no shade
--                frame: a button that is its own element); a skin drawing
--                its own shade keeps its nine's corners (its gems' whole
--                shadow would darken its own stone)
--         level  the shade frame's level from root's (-1)
--         strata the shade frame's strata, kept there (SetFixedFrameStrata:
--                the action bars' backdrops, which the game lifts while a
--                spell is dragged)
--         mask   a mask of the host put on every partner
--         anchor a frame or region of ours the shade frame lies on instead
--                of root (a root that is an Edit Mode system: nothing is
--                anchored on one; only the frame's level counts, the
--                partners lie on their pieces)
--   element:Add(obj[, opts]) -> element
--       the partners of one outline part, made at once while the frame's
--       budget lasts and the area is on, else on a later frame (the rest of a
--       crowd, the next frame; an area off, when it is switched on); obj is
--       a replacement (Kit:Replace's rep: its skin, strip, upright strip or
--       texture), a strip (StripMixin), a skin (Kit:NineSlice), a kit
--       texture or a plain frame (with opts.shape; once per frame). Drawn by
--       another frame than the part's own, its partners are shown and hidden
--       with that frame too (the strip, the skin, the holder, the plain
--       frame: a hidden button or widget takes its shade along) and with the
--       rep's Enable / Disable. opts (kept until made): scale (a texture drawn at another
--       size than its kitScale; drawn = true: read from its width, a ring
--       drawn square to its rect -- never under a nameplate, where every size
--       reads secret: pass scale there), cut, shape ("shade/square" / "shade/capsule"
--       on a frame with no kit piece, "shade/round" on a texture), mask,
--       family and open (a skin's), host (another frame for this part's
--       partners: a skin's own, for its mask), ringCut (the window's ring
--       cut as mask)
--   element:Host() -> the frame that draws its partners (made when asked)
-- The settings are UI Modifications' (its defaults: uiShade on,
-- uiShadeStrength 0.7, every shade_<area> on), chosen in Dynamic UI
-- Modification: switched on the bus's 'setting' with the module on or off, and
-- read again on the frame after a 'restart' (a profile load writes them past
-- the setting's Fire, as the parchment). Each area's change goes out on the
-- bus's 'shade' (area, on, strength) once its partners follow.
-- Windows need no module's call: every window's shell (Kit:RegisterShell,
-- the bus's 'shell': the outer rail, title plate, portrait ring or crest of
-- SkinWindowShell's windows, the hand-made shells and Kit:OwnWindow, whose
-- crest and short plate come too) is shaded here -- each rail on its first
-- show, never before (a rare window adds nothing at login; WINDOW-RULES 2f),
-- as an element of the frame the rail was dressed on (a window; each bag
-- of the bags' shared container, each page of the group finder: every one
-- its own, hidden with it). The rail's shadow is a nine of the rail's own
-- skin frame (outside only), cut by the ring's corner mask; the gem
-- corners, the plate, the ring and the crest are drawn by that frame's shade
-- frame one level under it, so the inward half of their shadow lies under
-- the window's stone, never on it. The bags are the bags' area, every other
-- window the windows'.
-- Nothing is made at login (no frame, no texture: listeners only): the HUD,
-- whose first show is the login, adds its parts then, and they wait until the
-- login's frames are over (MelloUI:AfterLogin, Core.lua: 3 s after the first
-- PLAYER_ENTERING_WORLD), then are made at the frame's budget. Nothing
-- polls; a switch or a strength goes over the made partners in one pass and
-- allocates nothing; the partners are static (nothing for Reduce Motion) and
-- take the palette's colour (Kit.lua repaints them on 'palette').
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
-- frames made in a game window: Core's maker, so the game's gamepad
-- navigation never walks an open window for each one (MelloUI.Safe.CreateFrame)
local CreateFrame = MelloUI.Safe.CreateFrame
local Perf = MelloUI.Perf:Scope("KitShade")
local Shared = Perf.Shared
local Kit = MelloUI.Kit
local Num = MelloUI.Safe.Number

local SETTINGS = "UIModifications"         -- the module whose settings hold the switches
local MASTER_KEY, STRENGTH_KEY = "uiShade", "uiShadeStrength"
local DEFAULT, MIN, MAX = 0.7, 0.3, 0.9    -- the strength (the nameplates' and the notice's)
local OWNER = "Kit shade"                  -- the bus owner
local PUMP_KEY = "Kit shade: partners"     -- (Kit:NextFrame's keys; the pump's for Kit:WhenOutOfCombat too)
local WINDOW_KEY = "Kit shade: windows"
local RESTART_KEY = "Kit shade after a restart"
-- partner textures made in one frame (the nameplates' crowd rule,
-- NameplatePanel's MAKE_PER_FRAME, for every area): the rest on the next
-- frames; the first part a frame is always made, however many it needs
local MAKE_PER_FRAME = 24
local OUTER_KEY = "NineSlicePanelTemplate" -- a window's outer rail (Kit.Replacements)
local CORNERS = { "tl", "tr", "bl", "br" }
local WEAK = { __mode = "k" }

-- The areas, in the settings' order (Dynamic UI lists them so)
local AREAS = {
	{ "windows", "Windows" },
	{ "actionbars", "Action Bars" },
	{ "castbars", "Cast Bars" },
	{ "unitframes", "Unit Frames" },
	{ "chat", "Chat" },
	{ "bags", "Bags" },
	{ "minimap", "Minimap" },
	{ "tracker", "Tracker" },
	{ "buffs", "Buffs" },
	{ "widgets", "Event Widgets" },
	{ "nameplates", "Nameplates" },
}
local AREA, BY_KEY = {}, {}
for _, a in ipairs(AREAS) do
	a.name, a.label, a.key = a[1], a[2], "shade_" .. a[1]
	AREA[a.name], BY_KEY[a.key] = a, a
end
Kit.shadeAreas = AREAS
Kit.shadeSettings = { master = MASTER_KEY, strength = STRENGTH_KEY, default = DEFAULT, min = MIN, max = MAX, step = 0.05 }

-- UI Modifications' settings as saved, read straight (every switch here is on
-- by default, so a key not saved yet reads as on; no defaults written)
local function Settings()
	local db = MelloUI.db
	local modules = db and db.modules
	return modules and modules[SETTINGS]
end

function Kit:ShadeOn(area)
	local a = AREA[area]
	if not a then
		return false
	end
	local s = Settings()
	if s and (s[MASTER_KEY] == false or s[a.key] == false) then
		return false
	end
	return true
end

function Kit:ShadeStrength()
	local s = Settings()
	local v = s and Num(s[STRENGTH_KEY]) or DEFAULT
	return v < MIN and MIN or v > MAX and MAX or v
end

--------------------------------------------------------------------------------
-- The areas' state: what their made partners were last set to, and the parts
-- still to make (one queue per area, first in first out)
--------------------------------------------------------------------------------

local applied, appliedAt = {}, {}   -- [area] = on / the strength its partners have (made or set)
local queues = {}                   -- [area] = { head, tail, [i] = item }
local madeAt, madeCount = nil, 0    -- this frame's making (GetTime: the frame's time)
local made = {}                     -- [area] = partner textures made (the dump's and tests')
Kit.shadeState = { applied = applied, strength = appliedAt, queues = queues, made = made }

local Pump   -- (below)

-- the area's partners to its answer now, and the bus told; parts waiting in
-- an area switched on are made
local function Apply(a, strength)
	local on = Kit:ShadeOn(a.name)
	Kit:ShadowAreaSet(a.name, on, strength)
	applied[a.name], appliedAt[a.name] = on, strength
	MelloUI:Fire("shade", a.name, on, strength)
	local q = queues[a.name]
	if on and q and q.head <= q.tail then
		Pump()
	end
end

local function ApplyAll()
	local strength = Kit:ShadeStrength()
	for i = 1, #AREAS do
		Apply(AREAS[i], strength)
	end
end

-- a setting of UI Modifications: the master and the strength every area,
-- an area's switch that area (module on or off: the bus reaches both)
MelloUI:On("setting", Shared("'setting' on the bus: the UI shade", function(name, key)
	if name ~= SETTINGS then
		return
	end
	if key == MASTER_KEY or key == STRENGTH_KEY then
		ApplyAll()
	else
		local a = BY_KEY[key]
		if a then
			Apply(a, Kit:ShadeStrength())
		end
	end
end), OWNER)

-- a profile load (and the late settings at login) writes the switches past
-- the setting's Fire: on the frame after the 'restart', each area whose
-- partners stand otherwise than its settings say is switched, once, and what
-- waits in an area now on is made
local function RestartSync()
	local strength = Kit:ShadeStrength()
	for i = 1, #AREAS do
		local a = AREAS[i]
		local was = applied[a.name]
		if was ~= nil and (was ~= Kit:ShadeOn(a.name) or appliedAt[a.name] ~= strength) then
			Apply(a, strength)
		end
	end
	Pump()
end
MelloUI:On("restart", Shared("'restart' on the bus: the UI shade", function()
	Kit:NextFrame(RESTART_KEY, RestartSync)
end), OWNER)

--------------------------------------------------------------------------------
-- Making the partners
--------------------------------------------------------------------------------

-- one options table for the kit's calls (read once there, never kept)
local P = {}
local function Opts(el, rep, o)
	local host = o and o.host
	P.host, P.area, P.rep = (type(host) == "table" and host.CreateTexture) and host or el:Host(), el.area, rep
	P.alpha = Kit:ShadeStrength()
	P.colour = nil
	P.scale = o and Num(o.scale) or nil
	P.cut = o and o.cut or nil
	P.shape = o and o.shape or nil
	P.ends, P.open, P.skip, P.follow = nil, nil, nil, nil
	local mask = o and o.mask or el.mask
	if not mask and o and o.ringCut and el.cutRep then
		mask = el.cutRep.outerCut
	end
	P.mask = mask
	return P
end

local function IsTexture(obj)
	if type(obj) ~= "table" or type(obj.GetObjectType) ~= "function" then
		return false
	end
	local ok, kind = pcall(obj.GetObjectType, obj)
	return ok and kind == "Texture"
end

-- a replacement (Kit:Replace's rep: its rule and kind are its own fields)
local function IsRep(obj)
	return rawget(obj, "rule") ~= nil and rawget(obj, "kind") ~= nil
end

-- the drawn scale of a texture sized to its rect (a ring drawn square, not at
-- its kitScale): UI units per painted px, nil when it reads no size (secret,
-- not laid out yet)
local function DrawnScale(tex)
	local name = tex.kitName
	local pw = name and (Kit:Size(name, 1))
	local ok, w = pcall(tex.GetWidth, tex)
	w = ok and Num(w)
	if pw and pw > 0 and w and w > 0 then
		return w / pw
	end
	return nil
end

-- the frame that draws a part, when its partners are drawn by another: they
-- are shown and hidden with it too (a hidden holder, strip, skin, button or
-- widget takes its shade along; the root stays shown); nil on its own frame
local function Drawer(region, host)
	local ok, parent = pcall(region.GetParent, region)
	if ok and type(parent) == "table" and parent ~= host then
		return parent
	end
	return nil
end

-- a kit texture's partner (made before -- the nameplates', a plain corner's
-- twin -- it is kept as it is): 1 made, or 0
local function MakeTex(el, tex, o, rep)
	if tex.kitShadow or not Kit:ShadowShape(o and o.shape or tex.kitName) then
		return 0
	end
	local p = Opts(el, rep, o)
	if o and o.drawn then
		p.scale = DrawnScale(tex) or p.scale
	end
	p.ends = o and o.ends or nil
	p.follow = Drawer(tex, p.host)
	return Kit:Shadow(tex, p) and 1 or 0
end

-- a strip's parts (its caps, its middle with the soft ends where it runs
-- capless, an end piece)
local STRIP_PARTS = { "capL", "mid", "capR", "endL", "endR" }
local VSTRIP_PARTS = { "capT", "mid", "capB" }
local function MakeStrip(el, strip, o, rep, parts)
	local n = 0
	for i = 1, #parts do
		local key = parts[i]
		local part = rawget(strip, key)
		if IsTexture(part) and not part.kitShadow and Kit:ShadowShape(part.kitName) then
			local p = Opts(el, rep, o)
			p.ends = (key == "mid" and parts == STRIP_PARTS) or nil
			-- (drawn by another frame: shown and hidden with the strip)
			p.follow = strip ~= p.host and strip or nil
			if Kit:Shadow(part, p) then
				n = n + 1
			end
		end
	end
	return n
end

-- a skin's rails as its family's nine (outside only: dark past the rails'
-- outer edge, never inward); a gem corner (the gem stands past the rail's
-- corner) and a plain corner that took a gem's place (SetTopGems) get their
-- own piece's partners in the nine's corners -- only when these are drawn
-- by the element's shade frame, under everything the element draws: a whole
-- piece's shadow reaches inward too, and drawn by the skin itself it would
-- darken the stone inside the rails (a window's page), so there the nine
-- keeps its corners. Drawn by another frame, the nine and the gems' partners
-- are shown and hidden with the skin (a look swapped by hiding one skin)
local function MakeSkin(el, skin, o, rep)
	if skin.kitShadeNine then
		return 0
	end
	local family = o and o.family or skin.kitPrefix
	if not (family and Kit:ShadowShape(family)) then
		return 0
	end
	local gems, plains = skin.gemCorner, skin.plainCorner
	local under = el:Host() ~= skin
	local skip = ""
	if gems and under then
		for i = 1, #CORNERS do
			local c = CORNERS[i]
			if gems[c] then
				skip = skip .. c
			end
		end
	end
	local p = Opts(el, rep, o)
	p.scale = p.scale or Num(skin.kitScale)
	p.open = o and o.open or skin.kitOpen
	p.skip = skip
	-- (drawn by another frame than the skin: shown and hidden with the skin)
	p.follow = p.host ~= skin and skin or nil
	local nine = Kit:ShadowNine(p.host, skin, family, p)
	if not nine then
		return 0
	end
	skin.kitShadeNine = nine
	local n = #nine.kitParts
	if not (gems and under) then
		return n
	end
	for i = 1, #CORNERS do
		local c = CORNERS[i]
		local gem = gems[c]
		if gem and gem.tex then
			n = n + MakeTex(el, gem.tex, nil, rep)
		end
		local plain = plains and plains[c]
		if plain then
			n = n + MakeTex(el, plain, nil, rep)
		end
	end
	return n
end

-- a frame with no kit piece: a synthetic shape cut as a nine (its middle
-- filled), once per frame (a pooled widget dressed again adds nothing),
-- shown and hidden with the frame; a capsule's two corners are the rect's
-- height (read here unless opts.scale is given: give it under a nameplate,
-- where the height is secret)
local shaped = setmetatable({}, WEAK)   -- [a plain frame] = its nine
Kit.shadeState.shaped = shaped
local function MakeShape(el, rect, o, rep)
	local shape = o.shape
	local entry = Kit:ShadowShape(shape)
	if shaped[rect] or not (entry and entry.margins) then
		return 0
	end
	local p = Opts(el, rep, o)
	p.shape = nil
	if not p.scale and shape == "shade/capsule" then
		local corner = Num(entry.corner) or 0
		local ok, h = pcall(rect.GetHeight, rect)
		h = ok and Num(h)
		if h and h > 0 and corner > 0 then
			p.scale = h / (2 * corner)
		end
	end
	p.open = o.open
	p.follow = p.host ~= rect and rect or nil
	local nine = Kit:ShadowNine(p.host, rect, shape, p)
	if not nine then
		return 0
	end
	shaped[rect] = nine
	return #nine.kitParts
end

-- what one part makes (the budget's estimate: a nine 8, a strip 3 ...)
local function Cost(obj)
	if type(obj) ~= "table" then
		return 0
	end
	if IsRep(obj) then
		obj = rawget(obj, "skin") or rawget(obj, "strip") or rawget(obj, "vstrip") or rawget(obj, "tex") or rawget(obj, "object") or obj
	end
	if obj.melloSkin then
		return 12
	elseif rawget(obj, "mid") then
		return 3
	elseif IsTexture(obj) then
		return 1
	end
	return 8
end

-- one part's partners made: how many textures
local function Make(item)
	local el, obj, o = item.el, item.obj, item.opts
	local rep = nil
	if IsRep(obj) then
		rep = obj
		local skin, strip, vstrip = rawget(obj, "skin"), rawget(obj, "strip"), rawget(obj, "vstrip")
		if skin then
			return MakeSkin(el, skin, o, rep)
		elseif strip then
			return MakeStrip(el, strip, o, rep, STRIP_PARTS)
		elseif vstrip then
			return MakeStrip(el, vstrip, o, rep, VSTRIP_PARTS)
		end
		-- a texture, a picture, a slot rim or a state texture (never the
		-- holder of a fade: rawget, so none is made by asking)
		local tex = rawget(obj, "tex") or rawget(obj, "object")
		if IsTexture(tex) then
			return MakeTex(el, tex, o, rep)
		end
		return 0
	end
	if obj.melloSkin then
		return MakeSkin(el, obj, o, rep)
	elseif rawget(obj, "capL") and rawget(obj, "mid") then
		return MakeStrip(el, obj, o, rep, STRIP_PARTS)
	elseif IsTexture(obj) then
		return MakeTex(el, obj, o, rep)
	elseif o and o.shape then
		return MakeShape(el, obj, o, rep)
	end
	return 0
end

-- this frame's budget: `n` more textures, or no (the first part a frame
-- always goes)
local function Spend(n)
	local now = GetTime()
	if now ~= madeAt then
		madeAt, madeCount = now, 0
	end
	if madeCount > 0 and madeCount + n > MAKE_PER_FRAME then
		return false
	end
	madeCount = madeCount + n
	return true
end

local PumpSoon = Shared("next frame: the UI shade's partners", function()
	Pump()
end)
local PumpAfterFight = Shared("after combat: the UI shade's partners", function()
	Pump()
end)

-- the parts waiting in every area that is on, in order, while the frame's
-- budget lasts; the rest on the next frame. The first part of a protected
-- element waits for the end of a fight (its shade frame is a child of that
-- frame; once made, textures on it are ours to make at any time).
-- (never inside itself: an Add or a switch while it makes waits for it)
local pumping = false
local function PumpAreas()
	for i = 1, #AREAS do
		local name = AREAS[i].name
		local q = queues[name]
		if q and q.head <= q.tail and Kit:ShadeOn(name) then
			while q.head <= q.tail do
				local item = q[q.head]
				if item.el.guarded and not item.el.host and InCombatLockdown() then
					Kit:WhenOutOfCombat(PumpAfterFight, PUMP_KEY)
					break
				end
				if not Spend(Cost(item.obj)) then
					Kit:NextFrame(PUMP_KEY, PumpSoon)
					return
				end
				q[q.head] = nil
				q.head = q.head + 1
				local ok, n = pcall(Make, item)
				if not ok then
					geterrorhandler()(n)
				elseif n > 0 then
					made[name] = (made[name] or 0) + n
					-- (made at the strength and answer of now)
					if applied[name] == nil then
						applied[name], appliedAt[name] = true, Kit:ShadeStrength()
					end
				end
			end
			if q.head > q.tail then
				q.head, q.tail = 1, 0
			end
		end
	end
end

-- the login's frames make none: what is added meanwhile waits in its queue
-- until they are over (MelloUI:AfterLogin), once for all
local held = false
local Resume = Shared("after the login: the UI shade's partners", function()
	held = false
	Pump()
end)
local function Held()
	if held then
		return true
	end
	if MelloUI.LoggingIn and MelloUI:LoggingIn() then
		held = true
		MelloUI:AfterLogin(Resume)
		return true
	end
	return false
end

Pump = function()
	if Held() then
		return
	end
	if pumping then
		Kit:NextFrame(PUMP_KEY, PumpSoon)
		return
	end
	pumping = true
	local ok, err = pcall(PumpAreas)
	pumping = false
	if not ok then
		geterrorhandler()(err)
	end
end

--------------------------------------------------------------------------------
-- Elements
--------------------------------------------------------------------------------

local Element = {}
Element.__index = Element
local elements = setmetatable({}, WEAK)   -- [root] = { [area] = element }

function Element:Host()
	local host = self.host
	if host then
		return host
	end
	local root = self.root
	host = CreateFrame("Frame", nil, root)
	local strata = self.strata
	if strata then
		host:SetFrameStrata(strata)
		if host.SetFixedFrameStrata then
			host:SetFixedFrameStrata(true)
		end
	end
	host:SetFrameLevel(math.max(root:GetFrameLevel() + self.level, 0))
	host:EnableMouse(false)
	host:SetAllPoints(self.anchor or root)
	host.ignoreInLayout = true   -- (never part of a layout frame's size, as the kit's holders)
	host.kitShadeHost = true
	self.host = host
	return host
end

function Element:Add(obj, opts)
	if type(obj) ~= "table" then
		return self
	end
	local q = queues[self.area]
	if not q then
		q = { head = 1, tail = 0 }
		queues[self.area] = q
	end
	q.tail = q.tail + 1
	q[q.tail] = { el = self, obj = obj, opts = opts }
	if Kit:ShadeOn(self.area) then
		Pump()
	end
	return self
end

function Kit:ShadeElement(root, area, opts)
	if not AREA[area] then
		error("Kit:ShadeElement: no shade area " .. tostring(area), 2)
	end
	if type(root) ~= "table" or not root.CreateTexture then
		error("Kit:ShadeElement: the root must be a frame", 2)
	end
	local byArea = elements[root]
	local el = byArea and byArea[area]
	if el then
		return el
	end
	if not byArea then
		byArea = {}
		elements[root] = byArea
	end
	opts = opts or {}
	local anchor = opts.anchor
	if not (type(anchor) == "table" and type(anchor.GetObjectType) == "function") then
		anchor = nil
	end
	el = setmetatable({ root = root, area = area, level = Num(opts.level) or -1, strata = opts.strata, mask = opts.mask,
		anchor = anchor }, Element)
	local host = opts.host
	if type(host) == "table" and host.CreateTexture then
		el.host = host
	else
		-- (its shade frame a child of a protected root: made out of combat)
		local okP, protected = pcall(root.IsProtected, root)
		el.guarded = (okP and protected == true) or nil
	end
	byArea[area] = el
	return el
end

--------------------------------------------------------------------------------
-- Windows: every kit window's rail (the bus's 'shell'), shaded on its first
-- show. One record per rail, on the frame the rail was dressed on (rep
-- .kitParent): a window, but also each bag of the bags' shared container,
-- each page of the group finder, the ignore list beside the friends window
-- (Kit.shells keeps one entry per TOP window, whose outer is the last rail
-- told). A plate, ring, crest or short plate goes to the record of the rail
-- it sits in (the first record up its frames, else the top window's), so
-- each hides with its own bag or page.
--------------------------------------------------------------------------------

local windows = setmetatable({}, WEAK)   -- [a rail's frame] = { el, top, root, area, outer, skin, rail, title, ring, crest, plate, cut, cutRep, live, parts }
local kindOf = setmetatable({}, WEAK)    -- [a shell part] = "outer" / "title" / "ring" / "crest" / "plate", once told
local recOf = setmetatable({}, WEAK)     -- [a shell part] = the record it went to
local waiting = setmetatable({}, WEAK)   -- [a rail's skin] = its record (the first show awaited)
local strays = setmetatable({}, WEAK)    -- [a part] = its top window: no rail of its own known yet
local told, toldTop = {}, {}             -- the parts told since the last pass, in order, and their top windows
local fresh = {}                         -- (the pass's new records)
local dirty = {}                         -- [top window] = true: told of since the last pass
local KINDS = { "outer", "title", "ring", "crest", "plate" }

-- the bags' windows are the bags' area
local function WindowArea(frame)
	local ok, name = pcall(frame.GetName, frame)
	if ok and type(name) == "string" and name:find("^ContainerFrame") then
		return "bags"
	end
	return "windows"
end

local RING = { drawn = true }   -- the ring and the crest: drawn square to their rect

-- the ring's corner cut (Kit:TitleBehindRing, once a plate and a ring are
-- both there): on the rail's partners, made or to make
local function Cut(rec)
	local title = rec.title
	local cut = title and rawget(title, "outerCut")
	if cut and rec.cut ~= cut then
		rec.cut, rec.cutRep = cut, title
		if rec.el then
			rec.el.cutRep = title
		end
		Kit:ShadowMask(rec.skin.kitShadeNine, cut)
	end
end

local function AddPart(el, part, kind)
	el:Add(part, (kind == "ring" or kind == "crest") and RING or nil)
end

-- a rail's shade made (its window seen): the frame's shade frame, one level
-- under it (under its stone and every part of it), draws the parts; the
-- rail's nine is on the rail's own skin, whose mask the ring's corner cut is
-- (outside only, it never darkens the page inside the rails)
local function Live(rec)
	rec.live = true
	-- (its shade frame on the rail's skin, ours: a window can be an Edit
	-- Mode system, the loot window)
	local el = Kit:ShadeElement(rec.root, rec.area, { anchor = rec.skin })
	rec.el = el
	el.cutRep = rec.cutRep
	el:Add(rec.outer, rec.rail)
	local parts = rec.parts
	for i = 1, #parts do
		AddPart(el, parts[i], kindOf[parts[i]])
	end
end

local Skin_OnShow = Shared("OnShow on a window's rail: its first shade", function(skin)
	local rec = waiting[skin]
	if rec then
		waiting[skin] = nil
		Live(rec)
	end
end, "script")

-- a window's rail told: its record (a HUD element's outer -- a chat window,
-- the tracker -- is its own area's; a frame's first rail only)
local function NewRail(outer, top)
	local skin = rawget(outer, "skin")
	if not (skin and outer.key == OUTER_KEY) then
		return nil
	end
	local root = rawget(outer, "kitParent")
	if type(root) ~= "table" or not root.CreateTexture then
		root = top
	end
	if windows[root] then
		return nil
	end
	local rec = { top = top, root = root, area = WindowArea(root), outer = outer, skin = skin,
		rail = { host = skin, ringCut = true }, parts = {} }
	windows[root] = rec
	recOf[outer] = rec
	return rec
end

-- the record of the rail a part sits in: the first up its frames, else the
-- top window's (nil: none known yet)
local function RecordOf(part, top)
	local f = rawget(part, "kitParent")
	if f == nil and type(part.GetParent) == "function" then
		f = part   -- (a plain frame as a shell's handle)
	end
	for _ = 1, 12 do
		if type(f) ~= "table" or f == UIParent then
			break
		end
		local rec = windows[f]
		if rec then
			return rec
		end
		if f == top then
			break
		end
		local ok, up = pcall(f.GetParent, f)
		f = ok and up or nil
	end
	return windows[top]
end

local function Place(part, top)
	local rec = RecordOf(part, top)
	if not rec then
		strays[part] = top
		return
	end
	strays[part] = nil
	recOf[part] = rec
	local kind = kindOf[part]
	rec[kind] = part
	if kind == "title" then
		Cut(rec)
	end
	if rec.live then
		AddPart(rec.el, part, kind)
	else
		rec.parts[#rec.parts + 1] = part
	end
end

local WindowPass = Shared("next frame: the windows' shade", function()
	local n = #told
	-- the rails first: a part finds its rail's record by its frames
	local rails = 0
	for i = 1, n do
		local part = told[i]
		if kindOf[part] == "outer" then
			local rec = NewRail(part, toldTop[i])
			if rec then
				rails = rails + 1
				fresh[rails] = rec
			end
		end
	end
	for i = 1, n do
		local part = told[i]
		if kindOf[part] ~= "outer" then
			Place(part, toldTop[i])
		end
		told[i], toldTop[i] = nil, nil
	end
	-- parts told before their rail
	if rails > 0 then
		for part, top in pairs(strays) do
			Place(part, top)
		end
	end
	-- a ring's corner cut made as a shell's plate and ring met (on its
	-- latest plate: Kit:TitleBehindRing's)
	for top in pairs(dirty) do
		dirty[top] = nil
		local known = Kit.shells[top]
		local title = known and known.title
		local rec = title and recOf[title]
		if rec then
			Cut(rec)
		end
	end
	-- each new rail's shade: now when its window is seen, else on its first
	-- show (nothing before: a rare window adds nothing at login)
	for i = 1, rails do
		local rec = fresh[i]
		fresh[i] = nil
		local skin = rec.skin
		local okV, visible = pcall(skin.IsVisible, skin)
		if okV and visible then
			Live(rec)
		else
			waiting[skin] = rec
			if not skin.kitShadeHooked then
				skin.kitShadeHooked = true
				Perf.HookScript(skin, "OnShow", Skin_OnShow)
			end
		end
	end
end)

-- a shell told (each part as it is registered: Kit.shells holds the last of
-- each kind, so every one is taken in as it comes): looked at on the next
-- frame, once for all that came (a window's rail, ring and plate come in one
-- go; the bags' seven rails too)
MelloUI:On("shell", Shared("'shell' on the bus: the windows' shade", function(frame, known)
	if not frame then
		return
	end
	if type(known) == "table" then
		for i = 1, #KINDS do
			local kind = KINDS[i]
			local part = known[kind]
			if type(part) == "table" and kindOf[part] == nil then
				kindOf[part] = kind
				local n = #told + 1
				told[n], toldTop[n] = part, frame
			end
		end
	end
	dirty[frame] = true
	Kit:NextFrame(WINDOW_KEY, WindowPass)
end), OWNER)

Kit.shadeWindows = windows
