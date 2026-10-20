--------------------------------------------------------------------------------
-- MelloUI - Quest ink, the painted reskin's part (one look, stage I:
-- QuestInk.lua's OLDSCHOOL block): the kit's plates under a string -- its
-- strips, its replacements and the game's plate art it knows -- handed to the
-- ink through MelloUI.QuestInk's provider.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI

-- OLDSCHOOL BEGIN: the kit's plates under a string -- its strips, its replacements and the game's plate art it knows, in
-- a grid over the screen -- the provider QI.plates (onelook D10; moves to MelloUI_Oldschool at stage I). It uses only
-- the header's locals and public tables: the ink's state and helpers through MelloUI.QuestInk.__ (read only).
do
local Ink = MelloUI.QuestInk
local P, H = Ink.plates, Ink.__
local St = H.S   -- (St.stamp, St.noForce: the core's)
local HBatch, HCentre, HPack, HKindOf, HAddRect = H.Batch, H.Centre, H.Pack, H.KindOf, H.AddRect
local RectOf = MelloUI.Safe.ScreenRect   -- (the addon's one reader of a screen rect, Core.lua)
local WEAK_K = { __mode = "k" }

-- a replacement that is a plate behind text (a header, a row's plate, a
-- bar's bracket, a slot, a flat control's dark plate -- 0.19.1); not a
-- line (a divider) nor a picture or tile
local PLATE_KIND = { strip = true, frame = true, bar = true, slot = true, flat = true }
-- the kit's plates a string may lie over wherever they were put (OverPlate)
local GLOBAL_PLATE = { strip = true, bar = true, slot = true, flat = true }

-- a replacement's painted base ("" when it has none)
local function PlateBase(rep)
	return (rep.strip and rep.strip.base) or (rep.rule and rep.rule.base) or ""
end

-- a flat control with a body (its fill: a button, a field, a tab); one
-- that is an edge alone (body = false) or a knob is no plate
local function FlatBody(rep)
	if rep.kind ~= "flat" then
		return true
	end
	local parts = rep.flat
	-- (0.20.1: a text field's body is its W.Field, the Stone rail's dark trough)
	return (parts and (parts.fill or parts.field) and not parts.noBody) and true or false
end

-- The kit's replacements, taken in as the kit makes them (Kit.repList only
-- grows): each by its region, and those of the kinds above for OverPlate
-- (a divider's line never: its base is the kit's rule, fixed when made)
local regionRep, repCount = setmetatable({}, WEAK_K), 0
local plateReps = {}
local function SyncReps()
	local Kit = MelloUI.Kit
	local list = Kit and Kit.repList
	if not list or #list == repCount then
		return
	end
	for i = repCount + 1, #list do
		local rep = list[i]
		if rep then
			if rep.region then
				regionRep[rep.region] = rep
			end
			if GLOBAL_PLATE[rep.kind] and FlatBody(rep) and not PlateBase(rep):find("divider", 1, true) then
				plateReps[#plateReps + 1] = rep
			end
		end
	end
	repCount = #list
end

-- The kit's replacement for a region
local function RepOf(region)
	SyncReps()
	return regionRep[region]
end

-- a texture of the game's that is a plate (its atlas a kit rule's strip,
-- bar, frame or flat control), shown and solid
local GAME_PLATE_KIND = { strip = true, bar = true, frame = true, flat = true }
local function GamePlate(region)
	local Kit = MelloUI.Kit
	if HKindOf(region) ~= "Texture" or (Kit and Kit.pieceNameOf and Kit.pieceNameOf[region]) or not region:IsShown() then
		return false
	end
	local okA, alpha = pcall(region.GetAlpha, region)
	if not okA or not alpha or alpha < 0.3 then
		return false
	end
	local okT, atlas = pcall(region.GetAtlas, region)
	if not (okT and type(atlas) == "string") then
		return false
	end
	local rule = Kit and Kit.Replacements and Kit.Replacements[atlas]
	if not (rule and GAME_PLATE_KIND[rule.kind]) then
		return false
	end
	-- the game's row bands (UI-Character-Info-Line-Bounce and the like) are
	-- faint see-through stripes on the paper, not plates: the stats' every
	-- other row kept its yellow (user, 2026-09-23: "changing colors from
	-- Yellow to Black randomly")
	local base = tostring(rule.base or rule.prefix or "")
	if base:find("divider", 1, true) or base:find("^lists/plate") or base:find("^lists/row") then
		return false
	end
	return true
end

local function IsPlate(rep)
	if not (rep and PLATE_KIND[rep.kind] and FlatBody(rep)) then
		return false
	end
	return not PlateBase(rep):find("divider", 1, true)
end

-- The kit's plates shown now: the strips (headers, row plates, a row's
-- hover or selection), the bars' brackets and the slot rims -- not the
-- dividers (lines), nor the frames (a window's frame lies under everything
-- in it). A string over one keeps its colours, however the plate was put
-- there (user, 2026-09-23: the stats' category plates belong to another
-- frame than their names). Measured into a coarse grid of the screen: a
-- string's centre looks only at the plates of its cell (the first in the
-- kit's order that holds it, as when every plate was asked). As the list
-- of them always was, the plates that show are taken once a pass (a pass
-- asks for them as it begins, a change and a row a list fills as they are
-- then): every replacement asked whether it shows, many and more as the
-- evening goes on, so in slices within the pass's time. Where each lies is
-- measured again for each frame the pass goes on in (a list scrolled, a
-- window dragged: the old passes asked every plate's place as they went),
-- those that showed only; one found under a string that was measured in an
-- earlier batch is asked again as it is now.
local CELL, CELLS_X, CELLS_Y = 64, 64, 16
local PLATE_AGE = 0.2   -- s: a pass that runs longer takes the plates that show again
local members, memberN = {}, 0   -- the plates that showed when every one was last asked
local plateObj, plateL, plateB, plateR, plateT = {}, {}, {}, {}, {}   -- the grid's plates, where each lay
local plateSeen, nowL, nowB, nowR, nowT = {}, {}, {}, {}, {}   -- one asked again: the stamp, its rect then
local cells, gen, gridGen = {}, 0, nil
local gridWant, gridHave, gridBegan = 1, 0, nil   -- every plate asked: the asking wanted, the one done (begun then)
local placedTime, placedStamp, placedUsed = nil, nil, false   -- the grid's places: measured then, read since
local building, buildNo, buildAt, buildN, buildBegan, buildStamp = nil, nil, 1, 0, nil, nil   -- a grid being measured

local function CellOf(v, last)
	local c = math.floor(v / CELL)
	return (c < 0 and 0) or (c > last and last) or c
end

-- Every plate asked again, begun at `t` or later; nil: begun now (a change)
local function WantPlates(t)
	local began
	if building == "all" and buildNo == gridWant then
		began = buildBegan
	elseif gridHave == gridWant then
		began = gridBegan
	else
		return   -- asked for already, not begun: it begins now or later
	end
	if t == nil or not began or began < t then
		gridWant = gridWant + 1
	end
end

-- The grid measured, on until `deadline` (debugprofilestop; nil: to the
-- end): every plate asked when that is wanted; else the plates that showed
-- measured where they lie, when their places were measured before `since`
-- (a pass: this frame's, once the last places were read -- a slice at
-- least between two) or at `since` (`after`: a row filled then). True once
-- the grid is there.
local function BuildPlates(deadline, since, after)
	local all = gridHave ~= gridWant
	if not (all or building == "place") then
		local older = since and (not placedTime or placedTime < since or (after and placedTime == since))
		if not (older and (placedUsed or after)) then
			return true
		end
	end
	SyncReps()
	local kind = all and "all" or "place"
	if building ~= kind or (all and buildNo ~= gridWant) then
		HBatch()
		gen = gen + 1
		building, buildNo, buildAt, buildN, buildBegan, buildStamp = kind, gridWant, 1, 0, GetTime(), St.stamp
		if all then
			memberN = 0
		end
	end
	local n, count = buildN, 0
	for i = buildAt, all and #plateReps or memberN do
		if deadline and count >= 16 then
			count = 0
			if debugprofilestop() >= deadline then
				buildAt, buildN = i, n
				return false
			end
		end
		count = count + 1
		local obj
		if all then
			local rep = plateReps[i]
			obj = rep.object
			if obj and obj.IsVisible and not PlateBase(rep):find("divider", 1, true) and obj:IsVisible() then
				memberN = memberN + 1
				members[memberN] = obj
			else
				obj = nil
			end
		else
			obj = members[i]
			if not obj:IsVisible() then
				obj = nil
			end
		end
		local l, b, r, t
		if obj then
			l, b, r, t = RectOf(obj)
		end
		if l then
			n = n + 1
			plateObj[n], plateL[n], plateB[n], plateR[n], plateT[n] = obj, l, b, r, t
			plateSeen[n] = nil
			for cx = CellOf(l, CELLS_X - 1), CellOf(r, CELLS_X - 1) do
				for cy = CellOf(b, CELLS_Y - 1), CellOf(t, CELLS_Y - 1) do
					local key = cx * CELLS_Y + cy + 1
					local cell = cells[key]
					if not cell then
						cell = { n = 0 }
						cells[key] = cell
					end
					if cell.gen ~= gen then
						cell.gen, cell.n = gen, 0
					end
					cell.n = cell.n + 1
					cell[cell.n] = n
				end
			end
		end
	end
	if all then
		gridHave, gridBegan = buildNo, buildBegan
	end
	gridGen, placedTime, placedStamp, placedUsed, building = gen, buildBegan, buildStamp, false, nil
	return true
end

-- The window a widget lies in: its ancestor just under UIParent (or under
-- WorldFrame: a nameplate). A plate of another window or of the HUD (a
-- nameplate's or a unit frame's bar, the tooltip's, an action slot) is drawn
-- under or over this window, never between its paper and its text: it once
-- put a line's game colour back for a second or two whenever one passed
-- behind it (user, 2026-09-24: the Reputation, Skill and PvP text "flickers
-- White then black every now and then"). Kept per widget with the parent it
-- was found through (walked again when that changes; all of them again when
-- a surface changes, StartPass: Reset)
local topOf, topVia = setmetatable({}, WEAK_K), setmetatable({}, WEAK_K)
local function TopOf(obj)
	local up = obj:GetParent()
	local top = topOf[obj]
	if top and topVia[obj] == up then
		return top
	end
	top = obj
	local p = up
	while p and p ~= UIParent and p ~= WorldFrame and not (p.IsForbidden and p:IsForbidden()) do
		top, p = p, p:GetParent()
	end
	topOf[obj], topVia[obj] = top, up
	return top
end

local function OverPlate(fs)
	HBatch()
	if building or gridHave ~= gridWant then
		-- a pane the game has just refreshed never waits on every plate being
		-- asked (a whole grid in the frame it shows: a hitch); its own plates
		-- it has from its frames, the next pass the rest
		if St.noForce and (building == "all" or gridHave ~= gridWant) then
			return nil
		end
		BuildPlates(nil)   -- (a pass or a row list has it measured before it asks)
	end
	placedUsed = true
	local x, y = HCentre(fs)
	if not x then
		return nil
	end
	local cell = cells[CellOf(x, CELLS_X - 1) * CELLS_Y + CellOf(y, CELLS_Y - 1) + 1]
	if cell and cell.gen == gridGen then
		local stamp = St.stamp
		local stale = placedStamp ~= stamp
		local win = nil   -- fs's window, asked at the first plate under it
		for j = 1, cell.n do
			local i = cell[j]
			if x >= plateL[i] and x <= plateR[i] and y >= plateB[i] and y <= plateT[i] then
				win = win or TopOf(fs)
				-- only a plate of its own window
				if TopOf(plateObj[i]) == win then
					if not stale then
						return plateObj[i]
					end
					-- measured in an earlier batch: shown and there now?
					if plateSeen[i] ~= stamp then
						plateSeen[i] = stamp
						local obj, l, b, r, t = plateObj[i], nil, nil, nil, nil
						if obj:IsVisible() then
							l, b, r, t = RectOf(obj)
						end
						nowL[i], nowB[i], nowR[i], nowT[i] = l or false, b, r, t
					end
					local l = nowL[i]
					if l and x >= l and x <= nowR[i] and y >= nowB[i] and y <= nowT[i] then
						return plateObj[i]
					end
				end
			end
		end
	end
	return nil
end

-- A frame's own plates (Info, DefaultSkip): the kit's plate tables kept
-- beside the frames, its children that are kit strips, its regions
local OWN_PLATES = { "repOf", "headerPlateOf", "plateOf" }   -- (Kit's tables)
local stripsOf = setmetatable({}, WEAK_K)
local kidScratch, regionScratch = {}, {}

-- A frame's children that are kit strips (a Kit:Strip: `base`, `mid`), read
-- again only when its children change (UIParent has hundreds)
local function StripsOf(f)
	local list = stripsOf[f]
	local count = f:GetNumChildren()
	if list and list.count == count then
		return list
	end
	if not list then
		list = { n = 0 }
		stripsOf[f] = list
	end
	local n = 0
	for i = 1, HPack(kidScratch, f:GetChildren()) do
		local child = kidScratch[i]
		if rawget(child, "base") ~= nil or rawget(child, "mid") ~= nil then
			n = n + 1
			list[n] = child
		end
	end
	for i = n + 1, list.n do
		list[i] = nil
	end
	list.n, list.count = n, count
	return list
end

-- the provider (QI.plates, the core's table: filled here)
P.Want = WantPlates
P.Build = BuildPlates
P.Over = OverPlate
function P.Age(now)
	if gridHave == gridWant and gridBegan and gridBegan < now - PLATE_AGE then
		for _, def in pairs(Ink.surfaces) do
			if def.job and def.job.running then
				gridWant = gridWant + 1
				break
			end
		end
	end
end
function P.Reset()
	wipe(topOf)
end
-- a painted plate of the kit (a Kit:Strip: a header, a row's hover or
-- selection, a bar's bracket) shown behind f's strings
function P.Strips(f, out)
	local list, n = StripsOf(f), 0
	for i = 1, list.n do
		local child = list[i]
		local base = rawget(child, "base")
		if base and rawget(child, "mid") and child:IsShown() and not tostring(base):find("divider", 1, true) then
			n = HAddRect(out, n, child)
		end
	end
	return n
end
function P.Regions(f, out)
	local n = 0
	for i = 1, HPack(regionScratch, f:GetRegions()) do
		local region = regionScratch[i]
		-- the row's own art replaced by a kit plate drawn elsewhere (the
		-- stats' category headers: their Background, the plate on another
		-- frame)
		local rep = RepOf(region)
		if IsPlate(rep) and rep.object and rep.object.IsShown and rep.object:IsShown() then
			n = HAddRect(out, n, rep.object)
		end
		-- the game's own plate art, not reskinned (a pooled row made after
		-- the reskin: the PvP tab's "Next Rewards" header, user 2026-09-23):
		-- a shown texture whose atlas the kit knows as a plate
		if GamePlate(region) then
			n = HAddRect(out, n, region)
		end
	end
	return n
end
-- a plate of the frame's own (the kit's tables beside it) that shows
function P.Own(f, out, n)
	local Kit = MelloUI.Kit
	for i = 1, Kit and #OWN_PLATES or 0 do
		local plates = Kit[OWN_PLATES[i]]
		local rep = plates and plates[f]
		local obj = type(rep) == "table" and rep.object
		if obj and obj.IsShown and obj:IsShown() then
			n = HAddRect(out, n, obj)
		end
	end
	return n
end
end
-- OLDSCHOOL END
