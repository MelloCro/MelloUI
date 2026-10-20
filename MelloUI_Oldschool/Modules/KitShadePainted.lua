--------------------------------------------------------------------------------
-- MelloUI - Kit shade, the painted reskin's part (one look, stage I: KitShade.lua's OLDSCHOOL block)
--
-- The painted reskin's HUD and bag areas (Kit:AddShadeArea, between the
-- core's by their order) and its windows' rail shade (the bus's 'shell'), on
-- the core's shade engine (Modules/KitShade.lua, loaded before this file):
-- public tables only.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("KitShadePainted")
local Shared = Perf.Shared
local Kit = MelloUI.Kit
local OWNER = "Kit shade"   -- the bus owner (KitShade.lua's: one owner for the shade's listeners)
local WEAK = { __mode = "k" }

-- OLDSCHOOL BEGIN: the painted reskin's HUD areas and its windows' rail shade (moves to MelloUI_Oldschool at stage I;
-- it uses only the header's locals and public tables)
do
-- the areas of the reskin's HUD and bags, between the core's (Kit:AddShadeArea's order)
Kit:AddShadeArea("actionbars", "Action Bars", { order = 2 })
Kit:AddShadeArea("castbars", "Cast Bars", { order = 3 })
Kit:AddShadeArea("unitframes", "Unit Frames", { order = 4 })
Kit:AddShadeArea("chat", "Chat", { order = 5 })
Kit:AddShadeArea("bags", "Bags", { order = 6 })
Kit:AddShadeArea("widgets", "Event Widgets", { order = 10 })
-- (no switch of its own, 0.16.0: the nameplates' Name Shade = Whole plate is
-- its switch, NameplatePanel asks it with the UI Shade on)
Kit:AddShadeArea("nameplates", "Nameplates", { order = 11, noSwitch = true })

local WINDOW_KEY = "Kit shade: windows"      -- (Kit:NextFrame's key)
local OUTER_KEY = "NineSlicePanelTemplate"   -- a window's outer rail (Kit.Replacements)

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
-- both there; or the rail's own where the game's ring is the window's corner,
-- Kit:CutRailAtRing): on the rail's partners, made or to make
local function Cut(rec)
	local from = rec.title
	local cut = from and rawget(from, "outerCut")
	if not cut then
		from = rec.outer
		cut = from and rawget(from, "outerCut")
	end
	if cut and rec.cut ~= cut then
		rec.cut, rec.cutRep = cut, from
		if rec.el then
			rec.el.cutRep = from
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
	Cut(rec)   -- (the rail's own cut, made at its first enable: Kit:CutRailAtRing)
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
end
-- OLDSCHOOL END
