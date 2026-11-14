--------------------------------------------------------------------------------
-- MelloUI's Route: following a guide addon's step.
--
-- RestedXP Guides first (the user, 2026-10-18: "if our world marker could read
-- those coordinates and places a mark on that spot, that could work"), the
-- others since 2026-10-21 (the user: "add compatibility like we did with
-- restedxp for ... Follow the Arrow, TUGs Leveling Guidelime Guide ... and some
-- other"), Polestar since 2.1.0, Zygor's opt-in since 2.1.10 (its reader, below): one core for every guide,
-- one reader per addon. While a guide runs:
--   * its step's spot gets the game's map pin, tracked, so the route and the
--     World Marker lead there (Guide.Step, read by Route's ReadWaypoint on the
--     pin's USER_WAYPOINT_UPDATED). A pin of the player's own is never moved,
--     and a step laid once is not laid again: a pin the player clears, or a
--     quest tracked instead (by the player, or by the guide: APR tracks its
--     quest steps' quests), stays so until the next step;
--   * its step's lines go to the Quest Tracker (the bus's "guide",
--     Guide.Publish), its items to the quest item widget ("guideitem",
--     Guide.PublishItems);
--   * its own arrow and window are veiled (Guide.Veil); (2.1.51) its arrow left showing while its card on the
--     Addons page says so (Guide.ArrowShown).
-- Several running: the one whose step changed last is followed, a guide with
-- steps before TomTom's bare arrow. Read only, post-hooks only, every read
-- guarded: an addon of another shape does nothing. /route guide (or /route rxp)
-- turns following off and on.
--
-- Guidelime keeps its steps to itself (no global state); its own "Use TomTom
-- arrow" option hands its spot to TomTom, which is followed. QuestMaster,
-- Shortest Path, Adventure Guide, ForeverWisp's marker mode and (2.1.51) FlowUp lay the game's
-- pin themselves: Route follows them with no reader.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local CreateFrame = MelloUI.Safe.CreateFrame
local W = MelloUI.Widgets
local Perf = MelloUI.Perf:Scope("MelloUI_Route (Guides)")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
local Plain, Text, Finite = MelloUI.Safe.Value, MelloUI.Safe.Text, MelloUI.Safe.Finite
local M = MelloUI:GetModule("Route")

-- mapID, x, y: the pin laid last, as the game keeps it; stepMap, stepX, stepY: the step it was laid for (2.1.30: apart --
-- a step whose map takes no pin is laid on a map above it); active: the reader followed
local Guide = { readers = {} }
M.Guide = Guide

local SKIP = W.Tr("Skip this step")   -- (a guide that skips whole steps: the box under its lines)

local function Following()
	return M.isEnabled and M.db and M.db.followGuide ~= false or false
end

-- (2.1.51; the user: "a checkbox if people want to see the 'Arrow' of that specific addon aswell as the MelloUI
-- Navigation World Marker") a guide's own arrow left showing beside the World Marker while it is followed (its window
-- still veiled): the switch on its card of the Addons page (Core/AddonsPage.lua), Route's setting
-- guideArrow_<reader key>, in the profile with Route's others; off by default, as before
function Guide.ArrowShown(key)
	return (M.db and M.db["guideArrow_" .. tostring(key)] == true) and true or false
end

function Guide.SetArrowShown(key, on)
	if not (M.db and type(key) == "string") then
		return
	end
	M.db["guideArrow_" .. key] = on and true or nil
	if Guide.Veil then
		Guide.Veil()   -- (a frame holding secure buttons waits for the fight's end there)
	end
end

-- fn(...)'s first result, guarded: nil when fn is missing, raised, or that result is secret
local function Pcall(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, v = pcall(fn, ...)
	return ok and Plain(v) or nil
end

-- the frames among the arguments (a guide's own arrow and windows; one not made yet is skipped)
local function List(...)
	local t = {}
	for i = 1, select("#", ...) do
		local f = select(i, ...)
		if type(f) == "table" then
			t[#t + 1] = f
		end
	end
	return t
end

-- an item's id from an id, a link or a name the client knows
local function ItemID(v)
	if type(v) == "number" then
		return v
	end
	v = Text(v)
	if not v then
		return nil
	end
	local id = tonumber(v:match("item:(%d+)"))
	if id then
		return id
	end
	local CI = rawget(_G, "C_Item")
	return tonumber(Pcall(CI and CI.GetItemInfoInstant or rawget(_G, "GetItemInfoInstant"), v))
end

local function Same(mapID, x, y, m2, x2, y2)
	return mapID == m2 and x2 and y2 and math.abs(x - x2) < 0.0005 and math.abs(y - y2) < 0.0005 or false
end

-- the pin laid last: this session's, else the one kept from before a /reload or a new login (the game keeps the
-- pin over both; the sim, 2026-10-21: a pin of ours from before read as the player's own and the following stopped)
local function Laid()
	if Guide.mapID then
		return Guide.mapID, Guide.x, Guide.y
	end
	local p = M.db and M.db.guidePin
	if type(p) == "table" then
		return tonumber(p[1]), tonumber(p[2]), tonumber(p[3])
	end
end

-- the pin on the map is the one laid for a step
local function Ours()
	local okH, has = pcall(C_Map.HasUserWaypoint)
	if not (okH and Plain(has)) or not C_Map.GetUserWaypoint then
		return false
	end
	local ok, point = pcall(C_Map.GetUserWaypoint)
	if not ok or type(point) ~= "table" then
		return false
	end
	local px, py = M.VectorXY(point.position)
	local m, x, y = Laid()
	return m and x and y and px and py and Same(m, x, y, Plain(point.uiMapID), px, py) or false
end

function Guide.Forget()
	Guide.mapID, Guide.x, Guide.y = nil, nil, nil
	Guide.stepMap, Guide.stepX, Guide.stepY = nil, nil, nil
	Guide.sig, Guide.itemSig, Guide.goalSig = nil, nil, nil
	for _, reader in ipairs(Guide.readers) do
		reader.sig, reader.quick, reader.lastKey = nil, nil, nil
	end
end

--------------------------------------------------------------------------------
-- Veiling a guide's own arrow and window while its guide runs here (the user,
-- 2026-10-18: "when this compatibility is enabled, the restedxp arrow and its
-- window is hidden"). Not hidden: a guide reads their being shown as state
-- (RestedXP's window hidden pauses the whole guide; Follow The Arrow's and
-- APR's arrows find the arrival only while shown; TomTom's re-picks its
-- waypoint). A scale far below a pixel instead, nothing to see or click, alpha
-- 0 too; laid again after the guide's own SetScale or SetAlpha (a Window Scale
-- setting, a fade); off, what it last asked for comes back. Only the followed
-- guide's: another running beside it keeps its own showing.
--------------------------------------------------------------------------------
do
	local veil = {}   -- [frame] = { alpha, scale } its guide's own while veiled; false: watched
	local veiling = false
	local regen   -- (frames holding secure buttons: in a fight veiled or not after it, PLAYER_REGEN_ENABLED)

	local function Later()
		if not regen then
			regen = CreateFrame("Frame")
			regen:SetScript("OnEvent", function(self)
				self:UnregisterEvent("PLAYER_REGEN_ENABLED")
				Guide.Veil()
			end)
		end
		regen:RegisterEvent("PLAYER_REGEN_ENABLED")
	end

	local function Locked(frame)
		return InCombatLockdown() and frame.IsProtected and frame:IsProtected() and true or false
	end

	local function Lay(frame)
		veiling = true
		frame:SetAlpha(0)
		frame:SetScale(0.001)
		veiling = false
	end

	-- the guide set its own scale or alpha while veiled: kept for later, the veil laid again
	local function Rewritten(self, key, value)
		local v = veil[self]
		if v and not veiling then
			v[key] = value
			if Locked(self) then
				Later()
			else
				Lay(self)
			end
		end
	end

	local function Watch(frame)
		veil[frame] = false
		hooksecurefunc(frame, "SetScale", function(self, s) Rewritten(self, "scale", s) end)
		hooksecurefunc(frame, "SetAlpha", function(self, a) Rewritten(self, "alpha", a) end)
	end

	-- (2.1.51, /route guide dump) a guide's frame under the veil: "veiled", "given back" (watched, not veiled) or
	-- "never veiled"
	function Guide.VeilState(frame)
		local v = veil[frame]
		return v and "veiled" or v == false and "given back" or "never veiled"
	end

	-- every watched frame veiled when it is the followed guide's, given back otherwise
	function Guide.Veil()
		local want = {}
		local reader = Following() and Guide.active
		if reader and reader.Frames then
			local ok, frames = pcall(reader.Frames)
			for _, frame in ipairs(ok and type(frames) == "table" and frames or {}) do
				if frame.SetScale and frame.GetScale and frame.SetAlpha and frame.GetAlpha then
					want[frame] = true
					if veil[frame] == nil then
						Watch(frame)
					end
				end
			end
			-- (2.1.51) its own arrow shown beside the World Marker: left out of the veil (given back if veiled)
			if reader.Arrows and Guide.ArrowShown(reader.key) then
				local okA, arrows = pcall(reader.Arrows)
				for _, frame in ipairs(okA and type(arrows) == "table" and arrows or {}) do
					want[frame] = nil
				end
			end
		end
		-- (a guide's drawings on no frame of its own, Polestar's on the minimap: quieted through its own setting, Quiet)
		for _, r in ipairs(Guide.readers) do
			if r.Quiet then
				pcall(r.Quiet, r == reader)
			end
		end
		for frame, v in pairs(veil) do
			local on = want[frame] or false
			if on ~= (v and true or false) then
				if Locked(frame) then
					Later()
				elseif on then
					veil[frame] = { alpha = frame:GetAlpha(), scale = frame:GetScale() }
					Lay(frame)
				else
					veil[frame] = false
					veiling = true
					frame:SetScale(v.scale or 1)
					frame:SetAlpha(v.alpha or 1)
					veiling = false
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The core: a reader's step read on its post-hook, the guide to follow chosen,
-- its spot, lines and items handed on.
--------------------------------------------------------------------------------

-- a reader's state: its spot, its step (title, lines, cog) and their signature
local function Read(reader)
	local m, x, y
	local ok, rm, rx, ry = pcall(reader.Point)
	if ok then
		m, x, y = tonumber(Plain(rm)), Finite(rx), Finite(ry)
	end
	if not (m and x and y) then
		m, x, y = nil, nil, nil
	end
	local steps
	if reader.Steps then
		-- (a reader with a cheap signature of its step, Quick: its lines built again only when that changed -- RestedXP's
		-- update runs a few times a second)
		local quick = reader.Quick and Pcall(reader.Quick)
		if quick and quick == reader.quick then
			steps = reader.steps
		else
			local okS, s = pcall(reader.Steps)
			steps = okS and type(s) == "table" and type(s.lines) == "table" and #s.lines > 0 and s or nil
			reader.quick = quick
		end
	end
	local parts = { m and string.format("%d:%.4f:%.4f", m, x, y) or "-" }
	for _, line in ipairs(steps and steps.lines or {}) do
		parts[#parts + 1] = tostring(line.text) .. (line.done and "+" or "-")
	end
	reader.mapID, reader.x, reader.y, reader.steps = m, x, y, steps
	reader.runs = (m or steps) and true or false
	-- (its step itself -- the guide, the step's number in its title, the spot -- not its lines' progress: what takes over)
	reader.stepKey = parts[1] .. "|" .. tostring(steps and steps.title)
	-- (2.1.0: its title too -- a new step whose lines read as the last one's is a change: its number in its title)
	return reader.stepKey .. "\n" .. table.concat(parts, "\n", 2)
end

-- the guide followed: the active one while it runs; else a running guide with steps, else TomTom's arrow
-- (2.1.44) a guide whose switch on the Addons page, Use with MelloUI, is off is never followed (Core/Integrations.lua)
local INTEGRATION = { rxp = "RestedXP", zygor = "Zygor", tomtom = "TomTom", polestar = "Polestar",
	fta = "FollowTheArrow", apr = "APR" }   -- (2.1.51: these two on the Addons page too)
local function Allowed(reader)
	local I = rawget(MelloUI, "Integrations")
	local key = INTEGRATION[reader.key]
	return not (I and key and not I.Use(key))
end
Guide.Allowed = Allowed

local function Choose()
	if Guide.active and Guide.active.runs and Allowed(Guide.active) then
		return Guide.active
	end
	local arrow
	for _, reader in ipairs(Guide.readers) do
		if reader.runs and Allowed(reader) then
			if reader.Steps then
				return reader
			end
			arrow = arrow or reader
		end
	end
	return arrow
end

local function Apply()
	Guide.Veil()
	Guide.Step()
	Guide.Publish()
	Guide.PublishItems()
	Guide.PublishGoals()
end

-- a reader's post-hook: its step read again; one whose step changed takes over, a guide with steps over a bare arrow
function Guide.Changed(reader)
	if not (Following() and reader.hooked and Allowed(reader)) then
		return
	end
	local sig = Read(reader)
	if sig == reader.sig and reader ~= Guide.active then
		return   -- (a guide not followed, its step as it was: RestedXP's update runs a few times a second)
	elseif sig == reader.sig then
		Guide.Veil()   -- (the followed guide's step as it was: a frame it made late veiled, its items' counts)
		Guide.PublishItems()
		return
	end
	reader.sig = sig
	-- (the user's in-game look, 2026-10-21, four guides running: a kill moved every guide's progress lines and each
	-- took over in turn; a new step takes over, progress only updates the followed guide's lines)
	local moved = reader.stepKey ~= reader.lastKey
	reader.lastKey = reader.stepKey
	local active = Guide.active
	if reader.runs and (not (active and active.runs) or moved and (reader.Steps or not active.Steps)) then
		Guide.active = reader
	end
	local before = Guide.active
	Guide.active = Choose()
	if before ~= Guide.active and before and before.clears and Ours() then
		pcall(C_Map.ClearUserWaypoint)   -- (TomTom's waypoint gone: the pin laid for it with it)
	end
	Apply()
end

-- every hooked reader read again (following turned on, a login)
function Guide.Refresh()
	for _, reader in ipairs(Guide.readers) do
		if reader.hooked and Following() then
			reader.sig = Read(reader)
			reader.lastKey = reader.stepKey
		else
			reader.runs = false
		end
	end
	Guide.active = Following() and Choose() or nil
	Apply()
end

-- (2.1.30) where the game takes the pin for a step's spot: its own map when that map may hold one, else the first map up
-- its parents that may, the spot carried over through the world (C_Map.CanSetUserWaypointOnMap -- Polestar's own
-- bridge asks it too: a dungeon's or a building's map refuses the pin); nil when none does
function Guide.Pinnable(zone, x, y)
	local CM = C_Map
	local can = CM.CanSetUserWaypointOnMap
	if type(can) ~= "function" then
		return zone, x, y
	end
	local ok, yes = pcall(can, zone)
	if ok and Plain(yes) == true then
		return zone, x, y
	end
	local V2 = rawget(_G, "CreateVector2D")
	if not (V2 and CM.GetWorldPosFromMapPos and CM.GetMapPosFromWorldPos and CM.GetMapInfo) then
		return nil
	end
	local okW, cont, pos = pcall(CM.GetWorldPosFromMapPos, zone, V2(x, y))
	cont = okW and tonumber(Plain(cont)) or nil
	if not (cont and pos) then
		return nil
	end
	local map = zone
	for _ = 1, 8 do
		local okI, info = pcall(CM.GetMapInfo, map)
		local parent = okI and type(info) == "table" and tonumber(Plain(info.parentMapID)) or nil
		if not parent or parent == 0 or parent == map then
			return nil
		end
		map = parent
		local okC, takes = pcall(can, map)
		if okC and Plain(takes) == true then
			local okP, _, mpos = pcall(CM.GetMapPosFromWorldPos, cont, pos, map)
			local px, py
			if okP and mpos then
				px, py = M.VectorXY(mpos)
			end
			if px and py and px >= 0 and px <= 1 and py >= 0 and py <= 1 then
				return map, px, py
			end
		end
	end
	return nil
end

-- (2.1.30; a player, 2026-11-09, following Polestar: "it bugs out after awhile", "It sent me from org to UC, then I got
-- to UC It wanted to send me to org again until I pop out and reload") the step was noted as laid before the game took
-- its pin: a refused pin left the step before's on the map, no longer known for ours -- kept as the player's own, every
-- later step was left unlaid and the route led to the old spot until a /reload. Now a step is laid only once the game
-- holds its pin, known as the game keeps it (read back); a step no map takes a pin for clears ours instead
local function Unlaid(had)
	if had and Ours() then
		pcall(C_Map.ClearUserWaypoint)
	end
	Guide.mapID, Guide.x, Guide.y = nil, nil, nil
	if M.db then
		M.db.guidePin = nil
	end
	return false
end

function Guide.Step(force)   -- force: a click on the step (laid again, over the player's own pin too); true when laid
	local reader = Following() and Guide.active
	local zone, x, y = reader and reader.mapID, reader and reader.x, reader and reader.y
	if not (zone and x and y) then
		return
	end
	if not force and Same(zone, x, y, Guide.stepMap, Guide.stepX, Guide.stepY) then
		return   -- this step was laid already
	end
	local okH, has = pcall(C_Map.HasUserWaypoint)
	has = okH and Plain(has) and true or false
	if not force and has and not Ours() then
		return   -- the player's own pin stays (followed again once it is gone)
	end
	if not (C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
		return
	end
	Guide.stepMap, Guide.stepX, Guide.stepY = zone, x, y
	local pm, px, py = Guide.Pinnable(zone, x, y)
	if not pm or not pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(pm, px, py)) then
		return Unlaid(has)
	end
	-- (the pin as the game keeps it: a client that moves it to another map or rounds it still knows it for ours)
	local okG, point = pcall(C_Map.GetUserWaypoint)
	local gm, gx, gy
	if okG and type(point) == "table" then
		gm = tonumber(Plain(point.uiMapID))
		gx, gy = M.VectorXY(point.position)
	end
	if not (gm and gx and gy) then
		return Unlaid(has)   -- (taken without a word and not there: nothing of ours stands)
	end
	Guide.mapID, Guide.x, Guide.y = gm, gx, gy
	if M.db then
		M.db.guidePin = { gm, gx, gy }   -- (known for ours after a /reload: Laid)
	end
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
		pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
	end
	return true
end

-- (2.1.30; a player, following Polestar: "It sent me from org to UC, then I got to UC It wanted to send me to org
-- again") /route guide dump: what the following holds now -- the guide followed and its spot, the step laid, the pin
-- as the game keeps it and whether it is ours, each hooked guide's own state (a reader's Dump). say(fmt, ...) prints
local function Spot(m, x, y)
	m, x, y = tonumber(m), tonumber(x), tonumber(y)
	return (m and x and y) and string.format("map %d at %.4f, %.4f", m, x, y) or "none"
end
function Guide.Dump(say)
	say("Following guides: %s", W.Tr(Following() and "on" or "off (/route guide turns it on)"))
	local active = Guide.active
	for _, r in ipairs(Guide.readers) do
		if r.hooked then
			say("   %s: hooked, %s%s", r.name, r.runs and "has a step" or "no step", r == active and ", FOLLOWED" or "")
		end
	end
	if active then
		say("   its step: %s", tostring(active.steps and active.steps.title or "-"))
		say("   its spot: %s", Spot(active.mapID, active.x, active.y))
	end
	-- (2.1.51; the user: "I have enabled the Rested XP arrow, but its not showing ingame") each hooked guide's own
	-- arrow: its Show its own arrow too switch, shown by the guide or not, its alpha, scale and place, MelloUI's veil
	for _, r in ipairs(Guide.readers) do
		if r.hooked and r.Arrows then
			local ok, arrows = pcall(r.Arrows)
			for _, f in ipairs(ok and type(arrows) == "table" and arrows or {}) do
				local okR, l, b = pcall(f.GetRect, f)
				l, b = okR and Finite(l), okR and Finite(b)
				say("   %s's arrow (%s): switch %s, %s by it, alpha %s, scale %s, at %s, %s", r.name,
					tostring(f.GetName and f:GetName() or "-"), Guide.ArrowShown(r.key) and "on" or "off",
					f:IsShown() and "shown" or "hidden", tostring(Finite(f:GetAlpha())), tostring(Finite(f:GetScale())),
					(l and b) and string.format("%d, %d", l, b) or "nowhere", Guide.VeilState(f))
			end
		end
	end
	say("   the step laid: %s", Spot(Guide.stepMap, Guide.stepX, Guide.stepY))
	if Guide.stepMap then
		local can = C_Map.CanSetUserWaypointOnMap
		local okC, takes = pcall(can, Guide.stepMap)
		local pm, px, py = Guide.Pinnable(Guide.stepMap, Guide.stepX, Guide.stepY)
		say("   its map takes a pin: %s; the pin goes on: %s", tostring(okC and Plain(takes)),
			pm and Spot(pm, px, py) or "no map takes one")
	end
	local kept = M.db and M.db.guidePin
	say("   the pin laid (as the game keeps it): %s; kept over a /reload: %s", Spot(Guide.mapID, Guide.x, Guide.y),
		type(kept) == "table" and Spot(kept[1], kept[2], kept[3]) or "none")
	local okH, has = pcall(C_Map.HasUserWaypoint)
	if okH and Plain(has) then
		local ok, point = pcall(C_Map.GetUserWaypoint)
		local px, py
		if ok and type(point) == "table" then
			px, py = M.VectorXY(point.position)
		end
		say("   the game's map pin: %s, ours: %s", Spot(ok and type(point) == "table" and Plain(point.uiMapID), px, py),
			tostring(Ours()))
	else
		say("   the game's map pin: none")
	end
	for _, r in ipairs(Guide.readers) do
		if r.hooked and r.Dump then
			local ok, err = pcall(r.Dump, say)
			if not ok then
				say("   %s: its dump failed (%s)", r.name, tostring(err))
			end
		end
	end
end

-- the followed guide's step for the Quest Tracker (the user, 2026-10-18: its steps "shown in the quest tracker", with
-- "the manual checkbox to skip certain steps"), on the bus's "guide": a line per step line, done when completed or
-- skipped, a box when it can be skipped (line.Toggle, the guide's own skip). Published only when its title or a line
-- changed (Guide.sig; 2.1.0: the title too, so a new step shows its own even when its lines read as the last one's);
-- nil once there is no guide or it is off.
function Guide.Publish()
	local reader = Following() and Guide.active
	local steps = reader and reader.steps
	local parts = { (reader and reader.key or "") .. "|" .. tostring(steps and steps.title) }
	for _, line in ipairs(steps and steps.lines or {}) do
		parts[#parts + 1] = tostring(line.text) .. (line.done and "+" or "-") .. (line.box and "b" or "")
	end
	local sig = steps and table.concat(parts, "\n") or ""
	if sig == Guide.sig then
		return
	end
	Guide.sig = sig
	if not steps then
		Guide.title, Guide.stepText = nil, nil
		MelloUI:Fire("guide", nil)
		return
	end
	Guide.title = steps.title or reader.name
	Guide.stepText = nil
	for _, line in ipairs(steps.lines) do
		if not line.done and not line.skip then
			Guide.stepText = line.text
			break
		end
	end
	MelloUI:Fire("guide", { section = reader.section or reader.name, lines = steps.lines, Repin = Guide.Repin,
		Unpin = Guide.Unpin, title = Guide.title, cog = steps.cog })
end

-- the followed guide's items for its step on the bus's "guideitem" (the user, 2026-10-18: "when you need to use an
-- item in certain spots and steps ... a hearthstone, mage teleports/portals", in MelloUI's quest item widget, the
-- guide's own item frame veiled): the items it names that the bags hold, then the spells it names the player knows;
-- published only when the list changed, nil once there are none or it is off
function Guide.PublishItems()
	local reader = Following() and Guide.active
	local items = {}
	if reader and reader.Items then
		local CI, CS = rawget(_G, "C_Item"), rawget(_G, "C_Spell")
		local count = CI and CI.GetItemCount or rawget(_G, "GetItemCount")
		local known = rawget(_G, "IsPlayerSpell")
		local ok, list = pcall(reader.Items)
		for _, e in ipairs(ok and type(list) == "table" and list or {}) do
			local id = type(e) == "table" and tonumber(e.id)
			if id and e.kind == "item" then
				local have = tonumber(Pcall(count, id)) or 0
				if have > 0 then
					items[#items + 1] = { kind = "item", id = id, count = have, name = Pcall(CI and CI.GetItemNameByID, id),
						icon = Pcall(CI and CI.GetItemIconByID, id) }
				end
			elseif id and e.kind == "spell" and (e.known or Pcall(known, id)) and CS and CS.GetSpellInfo then
				local okI, info = pcall(CS.GetSpellInfo, id)
				if okI and type(info) == "table" and type(info.name) == "string" then
					items[#items + 1] = { kind = "spell", id = id, name = info.name, icon = info.iconID }
				end
			end
		end
		table.sort(items, function(a, b)
			if a.kind ~= b.kind then
				return a.kind == "item"
			end
			return a.id < b.id
		end)
	end
	local parts = {}
	for i, e in ipairs(items) do
		parts[i] = e.kind .. e.id .. ":" .. (e.count or 0) .. ":" .. tostring(e.name)
	end
	local sig = table.concat(parts, ",")
	if sig == Guide.itemSig then
		return
	end
	Guide.itemSig = sig
	MelloUI:Fire("guideitem", #items > 0 and { title = Guide.title, step = Guide.stepText, items = items } or nil)
end

-- the followed guide's goals for MelloUI's map (2.1.0; the user's pick P1 of qu05_polestar_sketch, 2026-10-31: "MelloUI's
-- marks"; the map lays the ones it does not show already, MapObjectives): Guide.goals and the bus's "guidegoals", { title,
-- goals = { { key, kind (the objective data's: 1 creature, 2 object, 3 item, 4 a place), text, quest, verb ("accept",
-- "turnin", "objective" or nil), cont, places = { x1, y1, ... } (the client's world yards), lines, Aim } } };
-- published only when one changed, nil once there are none or it is off
function Guide.PublishGoals()
	local reader = Following() and Guide.active
	local goals
	if reader and reader.Goals then
		local ok, list = pcall(reader.Goals)
		goals = ok and type(list) == "table" and #list > 0 and list or nil
	end
	local parts = {}
	for i, g in ipairs(goals or {}) do
		parts[i] = tostring(g.key) .. ":" .. tostring(g.text) .. ":" .. tostring(g.cont) .. ":"
			.. table.concat(g.places or {}, ",") .. ":" .. table.concat(g.lines or {}, "|")
	end
	local sig = table.concat(parts, "\n")
	if sig == Guide.goalSig then
		return
	end
	Guide.goalSig = sig
	Guide.goals = goals and { title = Guide.title, goals = goals } or nil
	MelloUI:Fire("guidegoals", Guide.goals)
end

-- a click on the step in the Quest Tracker (the user, 2026-10-18: the World Marker missing, "click on that current
-- step and re-check the pin"): its spot laid and tracked again; a step with no spot says so
function Guide.Repin()
	if not Guide.Step(true) then
		MelloUI:Announce(W.Tr("This guide step has no place to mark on the map."), "info")
	end
end

-- a right-click on the step (the user, 2026-10-18: "a way to remove the waypoint, by right clicking on the
-- step"): the pin laid for it taken off, the route and the World Marker with it; the step stays laid (Guide.stepMap),
-- so following does not put it back before the next step or a click. A pin of the player's own stays.
function Guide.Unpin()
	local okH, has = pcall(C_Map.HasUserWaypoint)
	if not (okH and Plain(has)) then
		return
	end
	if not Ours() then
		MelloUI:Announce(W.Tr("The map pin is your own, not this step's: it stays."), "info")
		return
	end
	if C_Map.ClearUserWaypoint then
		pcall(C_Map.ClearUserWaypoint)
	end
end

-- once, after every addon is loaded (PLAYER_ENTERING_WORLD): each reader's post-hooks, then every guide read
function Guide.Hook()
	for _, reader in ipairs(Guide.readers) do
		if not reader.hooked then
			local ok, hooked = pcall(reader.Hook, function()
				Guide.Changed(reader)
			end)
			reader.hooked = ok and hooked and true or nil
		end
	end
	Guide.Refresh()
	-- (several guides loaded: which to keep, asked once a session, after the login's own work)
	if not Guide.askLater then
		Guide.askLater = true
		C_Timer.After(8, function() Guide.Ask() end)
	end
end

-- a context menu at the cursor (a guide's own list of guides, its settings); the gamepad's UI has none
local function Menu(build)
	if MelloUI.Safe.GamepadUI() or not (MenuUtil and MenuUtil.CreateContextMenu) then
		return false
	end
	MenuUtil.CreateContextMenu(UIParent, build)
	return true
end

--------------------------------------------------------------------------------
-- The readers. Each: key, name, section (the Quest Tracker's heading; none for
-- an arrow alone); Hook(changed) post-hooks the addon's step update, true when
-- hooked; Point() its step's spot: uiMapID, x, y in 0..1; Steps() { title,
-- lines = { { text, done, box, Toggle } }, cog } or nil; Items() { { kind
-- "item" or "spell", id, known } }; Frames() its own arrow and windows;
-- Quiet(on), optional, its drawings on no frame of its own, through its own
-- setting (on: followed); Goals(), optional, its step's goals with places
-- for MelloUI's map (Guide.PublishGoals).
--------------------------------------------------------------------------------

-- RestedXP Guides: its table RXP; its arrow's element (zone the map, x / y 0..100) after its UpdateGotoSteps
do
	local rxp = { key = "rxp", name = "RestedXP", section = "RestedXP Guide" }

	local function Usable(el)
		return type(el) == "table" and type(el.text) == "string" and el.text ~= "" and el.text ~= " "
	end

	-- its step's signature: the guide, the step, each element's text and done (Read: Steps only when it changed)
	function rxp.Quick()
		local rframe, cdata, R = rawget(_G, "RXPFrame"), rawget(_G, "RXPCData"), rawget(_G, "RXP")
		local steps = type(rframe) == "table" and rawget(rframe, "activeSteps")
		if type(steps) ~= "table" then
			return ""
		end
		local guide = type(R) == "table" and rawget(R, "currentGuide")
		local parts = { tostring(type(guide) == "table" and guide.name), tostring(type(cdata) == "table" and cdata.currentStep) }
		for _, step in ipairs(steps) do
			for _, el in ipairs(type(step) == "table" and type(step.elements) == "table" and step.elements or {}) do
				if Usable(el) then
					parts[#parts + 1] = el.text .. ((el.completed or el.skip) and "+" or "-")
				end
			end
		end
		return table.concat(parts, "\n")
	end

	function rxp.Hook(changed)
		local R = rawget(_G, "RXP")
		if type(R) ~= "table" or type(rawget(R, "UpdateGotoSteps")) ~= "function" then
			return false
		end
		hooksecurefunc(R, "UpdateGotoSteps", changed)
		return true
	end

	function rxp.Point()
		local R = rawget(_G, "RXP")
		local af = type(R) == "table" and rawget(R, "arrowFrame")
		local el = type(af) == "table" and rawget(af, "element")
		if type(el) ~= "table" or not (af.IsShown and af:IsShown()) then
			return nil
		end
		local zone, x, y = el.zone, tonumber(el.x), tonumber(el.y)
		if type(zone) == "string" and type(R.GetMapId) == "function" then
			zone = Pcall(R.GetMapId, zone)
		end
		zone = tonumber(zone)
		if not (zone and x and y) then
			return nil
		end
		return zone, x / 100, y / 100
	end

	-- its active steps: a line per element, its text as RestedXP shows it (ReplaceNpcIds), done when completed or
	-- skipped, a box unless text-only or optional; ticking one runs RestedXP's own checkbox
	-- (ActiveStepElementPostClick, the guide's skip)
	function rxp.Steps()
		local R, rframe = rawget(_G, "RXP"), rawget(_G, "RXPFrame")
		local steps = type(R) == "table" and type(rframe) == "table" and rawget(rframe, "activeSteps")
		if type(steps) ~= "table" then
			return nil
		end
		local lines = {}
		for _, step in ipairs(steps) do
			for _, el in ipairs(type(step) == "table" and type(step.elements) == "table" and step.elements or {}) do
				if Usable(el) then
					local text = el.text
					if type(R.ReplaceNpcIds) == "function" then
						local ok, s = pcall(R.ReplaceNpcIds, text)
						text = ok and type(s) == "string" and s or text
					end
					local line = { text = text, done = (el.completed or el.skip) and true or false,
						box = not (el.textOnly or el.optional) }
					line.Toggle = function(skip)
						-- (RestedXP's checkbox, as its own guide window clicks it)
						local button = { GetChecked = function() return skip end, GetParent = function() return { element = el } end }
						pcall(R.ActiveStepElementPostClick, button)
						Guide.Changed(rxp)
					end
					lines[#lines + 1] = line
				end
			end
		end
		if #lines == 0 then
			return nil   -- (no guide running: RestedXP's update runs on regardless)
		end
		local guide = rawget(R, "currentGuide")
		local name = type(guide) == "table" and (guide.displayName or guide.name) or nil
		local cdata = rawget(_G, "RXPCData")
		local n = type(cdata) == "table" and tonumber(cdata.currentStep) or nil
		-- (the section's cog, the user, 2026-10-18: its left click RestedXP's own cog menu -- "choose the active
		-- leveling guide" or its settings; at the cursor, so not under the veil -- its right click the settings,
		-- as RestedXP's /rxp opens them)
		local open = type(R.settings) == "table" and R.settings.OpenSettings
		local menu = type(rframe.DropDownMenu) == "function" and rframe.DropDownMenu
		local settings = type(open) == "function" and function() open() end or nil
		local title = type(name) == "string" and name or "RestedXP"
		return { title = n and W.Tr("%s - step %s"):format(title, n) or title,
			lines = lines,
			cog = { Left = menu and function() menu() end or settings, Right = settings, tip = "RestedXP Guides",
				hint = W.Tr("Click: its menu (guides, settings)  -  Right-click: its settings") } }
	end

	-- the items it names that the bags hold (RXP.activeItems), the spells it names (RXP.activeSpells; "p": known)
	function rxp.Items()
		local R = rawget(_G, "RXP")
		local list = {}
		for key in pairs(type(R) == "table" and type(R.activeItems) == "table" and R.activeItems or {}) do
			list[#list + 1] = { kind = "item", id = tonumber(key) }
		end
		for key, arg in pairs(type(R) == "table" and type(R.activeSpells) == "table" and R.activeSpells or {}) do
			list[#list + 1] = { kind = "spell", id = tonumber(key), known = arg == "p" }
		end
		return list
	end

	function rxp.Frames()
		return List(rawget(_G, "RXPFrame"), rawget(_G, "RXPG_ARROW"), rawget(_G, "RXPItemFrame"))
	end

	function rxp.Arrows()   -- (2.1.51: Guide.ArrowShown)
		return List(rawget(_G, "RXPG_ARROW"))
	end

	-- (2.1.51, /route guide dump) what RestedXP itself decides about its arrow: its Disable arrow option, its own hiding
	-- (no waypoint, in an instance), its window shown or not, its guide and the arrow's target
	function rxp.Dump(say)
		local R = rawget(_G, "RXP")
		local profile = type(R) == "table" and type(R.settings) == "table" and type(R.settings.profile) == "table"
			and R.settings.profile or {}
		local af = type(R) == "table" and rawget(R, "arrowFrame")
		local el = type(af) == "table" and rawget(af, "element")
		local guide = type(R) == "table" and rawget(R, "currentGuide")
		say("   RestedXP: its guide %s; its Disable arrow %s, its arrow hidden by it %s, its window shown %s, other "
			.. "continent %s; the arrow's target %s", tostring(type(guide) == "table" and guide.name),
			tostring(profile.disableArrow), tostring(type(R) == "table" and rawget(R, "hideArrow")),
			tostring(profile.showEnabled), tostring(type(af) == "table" and rawget(af, "wrongContinent")),
			type(el) == "table" and string.format("%s %s, %s", tostring(el.zone), tostring(el.x), tostring(el.y)) or "none")
	end

	Guide.readers[#Guide.readers + 1] = rxp
end

-- Follow The Arrow: its table FollowTheArrow; its own messages (FollowTheArrow:On, STEP_CHANGED and UPDATE: a new
-- step, a hotspot reached, a quest's progress); its step's point (0..100 on the guide's map, Map:Resolve the
-- client's), its lines ({ text, done }); it skips whole steps (SkipStep)
do
	local fta = { key = "fta", name = "Follow The Arrow", section = "Follow The Arrow" }

	local function F()
		local t = rawget(_G, "FollowTheArrow")
		return type(t) == "table" and t or nil
	end

	function fta.Hook(changed)
		local t = F()
		if not (t and type(t.On) == "function" and type(t.CurrentStep) == "function") then
			return false
		end
		t:On("STEP_CHANGED", changed)
		t:On("UPDATE", changed)
		return true
	end

	function fta.Point()
		local t = F()
		if not (t and type(t.ActiveTarget) == "function") then
			return nil
		end
		local ok, pt = pcall(t.ActiveTarget, t)   -- (not ArrowTarget: the corpse is the game's own to show)
		if not ok or type(pt) ~= "table" then
			return nil
		end
		local m, x, y = Plain(pt.m), Finite(pt.x), Finite(pt.y)
		local map = rawget(t, "Map")
		if m and type(map) == "table" and type(map.Resolve) == "function" then
			m = Pcall(map.Resolve, map, m) or m
		end
		m = tonumber(m)
		if not (m and x and y) then
			return nil
		end
		return m, x / 100, y / 100
	end

	-- its step: what to do (StepTitle), its lines (StepLines: turn-ins, accepts, objectives), and a box to skip it
	function fta.Steps()
		local t = F()
		local ok, step = pcall(t and t.CurrentStep, t)
		if not ok or type(step) ~= "table" then
			return nil
		end
		local lines = {}
		local head = Text(Pcall(t.StepTitle, t, step))
		if head and head ~= "" then
			lines[1] = { text = head, done = false }
		end
		local okL, list = pcall(t.StepLines, t, step)
		for _, l in ipairs(okL and type(list) == "table" and list or {}) do
			local text = type(l) == "table" and Text(l.text)
			if text and text ~= "" then
				lines[#lines + 1] = { text = text, done = l.done and true or false }
			end
		end
		if #lines == 0 then
			return nil
		end
		lines[#lines + 1] = { text = SKIP, done = false, box = true, skip = true, Toggle = function(skip)
			if skip then
				pcall(t.SkipStep, t)
			end
		end }
		local guide = Pcall(t.GetGuide, t)
		local char = rawget(t, "char")
		local n = type(char) == "table" and tonumber(Plain(char.step)) or nil
		local name = type(guide) == "table" and Text(guide.name) or nil
		-- (the cog: its guides to pick, as its own window lists them, and its settings)
		local function Settings()
			pcall(t.OpenOptions, t)
		end
		local function Guides()
			local order, guides = rawget(t, "guideOrder"), rawget(t, "guides")
			if type(order) ~= "table" or type(guides) ~= "table" or not Menu(function(_, root)
				root:CreateTitle("Follow The Arrow")
				local current = type(char) == "table" and char.guide
				for _, id in ipairs(order) do
					local g = guides[id]
					local label = type(g) == "table" and Text(g.name)
					if label then
						root:CreateRadio(label, function() return current == id end, function()
							pcall(t.SelectGuide, t, id)
						end)
					end
				end
				root:CreateDivider()
				root:CreateButton("Settings", Settings)
			end) then
				Settings()
			end
		end
		local title = name or "Follow The Arrow"
		return { title = n and W.Tr("%s - step %s"):format(title, n) or title, lines = lines,
			cog = { Left = Guides, Right = Settings, tip = "Follow The Arrow",
				hint = W.Tr("Click: its guides  -  Right-click: its settings") } }
	end

	-- the item its step needs (StepItem: the step's own, or a quest's special item): by id, link or name
	function fta.Items()
		local t = F()
		local ok, name, _, link = pcall(t and t.StepItem, t)
		local id = ok and (ItemID(link) or ItemID(name)) or nil
		return id and { { kind = "item", id = id } } or {}
	end

	function fta.Frames()
		return List(rawget(_G, "FollowTheArrowGuide"), rawget(_G, "FollowTheArrowArrow"),
			rawget(_G, "FollowTheArrowItemButton"), rawget(_G, "FollowTheArrowTargetButton"))
	end

	function fta.Arrows()   -- (2.1.51: Guide.ArrowShown)
		return List(rawget(_G, "FollowTheArrowArrow"))
	end

	Guide.readers[#Guide.readers + 1] = fta
end

-- Azeroth Pilot Reloaded: its table APR; its step panel's render (APR.currentStep:EndContentUpdate); its step read
-- without side effects (PeekCurrentStep: GetCurrentStep starts a step's actions); the step's destination as its own
-- pathfinder takes it (farstrider:GetDestination: uiMapID, x, y in 0..1), not its arrow's (a leg of that path);
-- the panel's lines (GetCurrentStepDetails, rendered: outstanding ones only); it skips whole steps (SkipQuestStep)
do
	local apr = { key = "apr", name = "Azeroth Pilot Reloaded", section = "Azeroth Pilot" }

	local function A()
		local t = rawget(_G, "APR")
		return type(t) == "table" and t or nil
	end

	local function Panel()
		local t = A()
		local cs = t and rawget(t, "currentStep")
		return type(cs) == "table" and cs or nil
	end

	function apr.Hook(changed)
		local cs = Panel()
		if not (cs and type(cs.EndContentUpdate) == "function") then
			return false
		end
		hooksecurefunc(cs, "EndContentUpdate", changed)
		return true
	end

	function apr.Point()
		local t = A()
		local fs = t and rawget(t, "farstrider")
		if type(fs) ~= "table" or type(fs.GetDestination) ~= "function" or type(t.PeekCurrentStep) ~= "function" then
			return nil
		end
		local ok, step = pcall(t.PeekCurrentStep, t)
		if not ok or type(step) ~= "table" or step.NoArrow then
			return nil
		end
		local okR, _, routeMap = pcall(t.GetCurrentRouteMapIDsAndName, t)
		local okD, d = pcall(fs.GetDestination, fs, step, okR and Plain(routeMap) or nil)
		if not okD or type(d) ~= "table" or d.worldCoord == nil then
			return nil   -- (a step with a zone only: its middle, no place to mark)
		end
		local m, x, y = tonumber(Plain(d.mapID)), Finite(d.x), Finite(d.y)
		if not (m and x and y) or (x == 0.5 and y == 0.5 and d.mapID == d.zone) then
			return nil   -- (its spot not found on the zone's map: the zone's middle)
		end
		return m, x, y
	end

	-- the panel's rows in its order, top first (its details come unordered); a row's quest's steps under it
	local function Rows(cs, details)
		local rows = {}
		local function Add(list, key, text, top)
			text = Text(text)
			local row = type(list) == "table" and list[key]
			if not text or text == "" or (type(row) == "table" and row.IsShown and not row:IsShown()) then
				return
			end
			if not top then
				local okT, t = pcall(row and row.GetTop, row)
				top = okT and Finite(t) or 0
			end
			rows[#rows + 1] = { text = text, top = top, n = #rows }
			return top
		end
		for _, e in ipairs(type(details.extraLines) == "table" and details.extraLines or {}) do
			Add(cs.questsExtraTextList, e.key, e.text)
		end
		for _, e in ipairs(type(details.questSteps) == "table" and details.questSteps or {}) do
			local top = Add(cs.questsList, e.key, e.text)
			for i, sub in ipairs(top and type(e.subSteps) == "table" and e.subSteps or {}) do
				Add(nil, nil, type(sub) == "table" and Text(sub.text) and ("   " .. sub.text), top - i * 0.001)
			end
		end
		for _, e in ipairs(type(details.fillerSteps) == "table" and details.fillerSteps or {}) do
			Add(cs.fillersList, e.key, e.text)
		end
		table.sort(rows, function(a, b)
			if a.top ~= b.top then
				return a.top > b.top
			end
			return a.n < b.n
		end)
		return rows
	end

	function apr.Steps()
		local t, cs = A(), Panel()
		local ok, details = pcall(cs and cs.GetCurrentStepDetails, cs)
		if not ok or type(details) ~= "table" then
			return nil
		end
		local lines = {}
		for _, row in ipairs(Rows(cs, details)) do
			lines[#lines + 1] = { text = row.text, done = false }
		end
		if #lines == 0 then
			return nil
		end
		lines[#lines + 1] = { text = SKIP, done = false, box = true, skip = true, Toggle = function(skip)
			if skip then
				pcall(t.SkipQuestStep, t)
				pcall(t.UpdateMapId, t)   -- (as its own /apr skip)
			end
		end }
		local progress = type(details.progress) == "table" and details.progress or {}
		local n, total = tonumber(Plain(progress.step)), tonumber(Plain(progress.total))
		local route = Text(rawget(t, "ActiveRoute"))
		if route and type(t.GetRouteDisplayName) == "function" then
			route = Text(Pcall(t.GetRouteDisplayName, t, route)) or route
		end
		local function Settings()
			local s = rawget(t, "settings")
			if type(s) == "table" and type(s.OpenSettings) == "function" then
				pcall(s.OpenSettings, s, rawget(t, "title"))
			end
		end
		-- (the cog: its own menu -- the routes, its options -- at the cursor, as its panel's button opens it)
		local function Own()
			if type(t.GetMenu) ~= "function" or not Menu(t.GetMenu) then
				Settings()
			end
		end
		local title = route or "Azeroth Pilot"
		return { title = n and W.Tr("%s - step %s%s"):format(title, n, total and ("/" .. total) or "") or title,
			lines = lines,
			cog = { Left = Own, Right = Settings, tip = "Azeroth Pilot Reloaded",
				hint = W.Tr("Click: its menu  -  Right-click: its settings") } }
	end

	-- the buttons on its step's rows: items (itemID) and spells (attribute "spell", the id once it knew the name)
	function apr.Items()
		local cs = Panel()
		local list = {}
		for _, rows in ipairs(List(cs and cs.questsList, cs and cs.fillersList)) do
			for _, row in pairs(type(rows) == "table" and rows or {}) do
				local b = type(row) == "table" and row.IconButton
				local id = type(b) == "table" and tonumber(Plain(b.itemID))
				if id and (b.attribute == nil or b.attribute == "item") then
					list[#list + 1] = { kind = "item", id = id }
				elseif id and b.attribute == "spell" then
					list[#list + 1] = { kind = "spell", id = id }
				end
			end
		end
		return list
	end

	function apr.Frames()
		local t = A()
		return List(t and rawget(t, "ArrowFrame"), rawget(_G, "CurrentStepScreenPanel"))
	end

	function apr.Arrows()   -- (2.1.51: Guide.ArrowShown)
		local t = A()
		return List(t and rawget(t, "ArrowFrame"))
	end

	Guide.readers[#Guide.readers + 1] = apr
end

-- Polestar (2.1.0; the user, 2026-10-31: "did we add Polestar to our compatibility?"): its namespace Polestar; its
-- own messages (Polestar.On: a new step, a goal's progress, its arrow's target, a new guide), read a frame later --
-- its step changes before its target does (STEP_CHANGED, then WAYPOINT_CHANGED); its arrow's target (Nav.GetTarget,
-- 0..100 on its map in the guide's frame, Nav.LiveCoords the client's), its step's goals (Engine.GetStepView); a
-- goal ticked as its window ticks it (Engine.ToggleGoal); it skips whole steps (Engine.Skip). Its arrow is its own,
-- or TomTom's while it hands the arrow to TomTom.
do
	local polestar = { key = "polestar", name = "Polestar", section = "Polestar" }
	local MESSAGES = { "STEP_CHANGED", "STEP_UPDATED", "WAYPOINT_CHANGED", "GUIDE_CHANGED", "SETTING_CHANGED" }

	local function P()
		local t = rawget(_G, "Polestar")
		return type(t) == "table" and t or nil
	end

	local function Engine()
		local t = P()
		local e = t and rawget(t, "Engine")
		return type(e) == "table" and e or nil
	end

	local function Nav()
		local t = P()
		local n = t and rawget(t, "Nav")
		return type(n) == "table" and n or nil
	end

	function polestar.Hook(changed)
		local t, e = P(), Engine()
		if not (t and type(t.On) == "function" and e and type(e.GetStepIndex) == "function") then
			return false
		end
		-- (several messages in one evaluation, one read: the next frame's, with its target settled)
		local pending = false
		local function Run()
			pending = false
			changed()
		end
		local function Soon()
			if not pending then
				pending = true
				C_Timer.After(0, Run)
			end
		end
		for _, msg in ipairs(MESSAGES) do
			t.On(msg, Soon)
		end
		return true
	end

	function polestar.Point()
		local nav = Nav()
		if not (nav and type(nav.GetTarget) == "function" and type(nav.LiveCoords) == "function") then
			return nil
		end
		local target = Pcall(nav.GetTarget)
		if type(target) == "table" and Pcall(nav.IsOverride) and Pcall(rawget(_G, "UnitIsGhost"), "player") then
			local e = Engine()   -- (a ghost's: its death helper's corpse or Spirit Healer, the game's own to show)
			target = e and Pcall(e.GetWaypoint)
		end
		if type(target) ~= "table" then
			return nil
		end
		local ok, m, x, y = pcall(nav.LiveCoords, target)
		m, x, y = ok and tonumber(Plain(m)), ok and Finite(x), ok and Finite(y)
		if not (m and x and y) then
			return nil
		end
		return m, x / 100, y / 100
	end

	-- its step: a line per goal as its window words it (UI.PlainGoalText, the count after it), done when done or
	-- skipped, a box on the goals it lets the player tick; then a box to skip the step
	local seen   -- { step, view }: the step's view Steps read, for Goals right after it (one view a read)
	function polestar.Steps()
		local t, e = P(), Engine()
		local i = e and tonumber(Pcall(e.GetStepIndex))
		local ok, view = pcall(i and e.GetStepView, i)
		seen = ok and type(view) == "table" and { i, view } or nil
		if not ok or type(view) ~= "table" or type(view.goals) ~= "table" then
			return nil
		end
		local ui = rawget(t, "UI")
		local word = type(ui) == "table" and ui.PlainGoalText
		local count = type(ui) == "table" and ui.GoalProgress
		local lines = {}
		for _, gv in ipairs(view.goals) do
			if type(gv) == "table" and gv.status ~= "na" and not gv.folded and not gv.header then
				local text = Text(Pcall(word, gv)) or Text(gv.text)
				local n = gv.status ~= "skipped" and Text(Pcall(count, gv))
				if text and text ~= "" then
					local g = tonumber(gv.index)
					lines[#lines + 1] = { text = n and (text .. " (" .. n .. ")") or text,
						done = (gv.status == "done" or gv.status == "skipped") and true or false,
						box = gv.tickable and g and true or false, Toggle = function(tick)
							-- (its window's tick: on for a goal not done, off for one the player ticked)
							if tick ~= (gv.status == "done") and (tick or gv.ticked) then
								pcall(e.ToggleGoal, i, g)
							end
						end }
				end
			end
		end
		if #lines == 0 then
			return nil
		end
		lines[#lines + 1] = { text = SKIP, done = false, box = true, skip = true, Toggle = function(skip)
			if skip then
				pcall(e.Skip)
			end
		end }
		local guide = Pcall(e.GetGuide)
		local name = type(guide) == "table" and Text(guide.title) or nil
		local total = tonumber(Pcall(e.GetStepCount))
		-- (the cog: its guide picker and its settings, as /polestar guides and /polestar options open them)
		local function Picker()
			pcall(t.Fire, "SHOW_PICKER")
		end
		local function Settings()
			pcall(t.Fire, "SHOW_OPTIONS")
		end
		return { title = W.Tr("%s - step %s%s"):format(name or "Polestar", i, total and ("/" .. total) or ""), lines = lines,
			cog = { Left = Picker, Right = Settings, tip = "Polestar",
				hint = W.Tr("Click: its guides  -  Right-click: its settings") } }
	end

	-- what its buttons would hold: the step's quest item (QoL.Buttons.ChooseQuestItem), the Hearthstone for a hearth goal
	function polestar.Items()
		local t = P()
		local qol = t and rawget(t, "QoL")
		local buttons = type(qol) == "table" and rawget(qol, "Buttons")
		if type(buttons) ~= "table" then
			return {}
		end
		local list = {}
		local item = tonumber(Pcall(buttons.ChooseQuestItem))
		if item then
			list[#list + 1] = { kind = "item", id = item }
		end
		local client = rawget(qol, "Client")
		local hearth = type(client) == "table" and tonumber(client.HEARTHSTONE)
		if hearth and Pcall(buttons.WantsHearth) then
			list[#list + 1] = { kind = "item", id = hearth }
		end
		return list
	end

	-- its step's goals with a place, for MelloUI's map (Guide.PublishGoals): where a goal's mobs or objects spawn (its
	-- guide's own spots), else its one place (its NPC, its spot), each in the client's frame (Nav.LiveCoords) and world
	-- yards; its count after its words; a click aims its own arrow there (Engine.AimGoal: Route follows it)
	local KIND = { kill = 1, click = 2, interact = 2, collect = 3, use = 3, loot = 3 }
	local VERB = { accept = "accept", turnin = "turnin", kill = "objective", collect = "objective", use = "objective",
		click = "objective", complete = "objective" }
	function polestar.Goals()
		local t, e, nav = P(), Engine(), Nav()
		local i = e and tonumber(Pcall(e.GetStepIndex))
		local okV, view = true, seen and seen[1] == i and seen[2]
		seen = nil
		if not view then
			okV, view = pcall(i and e.GetStepView, i)
		end
		local guide = i and Pcall(e.GetGuide)
		local step = type(guide) == "table" and type(guide.steps) == "table" and guide.steps[i]
		local CM, V2 = rawget(_G, "C_Map"), rawget(_G, "CreateVector2D")
		if not (okV and type(view) == "table" and type(view.goals) == "table" and type(step) == "table"
			and type(step.goals) == "table" and nav and type(nav.LiveCoords) == "function" and type(CM) == "table"
			and type(CM.GetWorldPosFromMapPos) == "function" and type(V2) == "function") then
			return nil
		end
		local ui = rawget(t, "UI")
		local word = type(ui) == "table" and ui.PlainGoalText
		local count = type(ui) == "table" and ui.GoalProgress
		local total = tonumber(Pcall(e.GetStepCount))
		local head = "Polestar, step " .. i .. (total and ("/" .. total) or "")
		local out = {}
		for _, gv in ipairs(view.goals) do
			local g = type(gv) == "table" and tonumber(gv.index)
			local raw = g and step.goals[g]
			if type(raw) == "table" and (gv.status == "active" or gv.status == "pending") and not gv.folded
				and not gv.header and gv.t ~= "note" then
				-- (its spawn spots on its own map, else the place its window shows: a chosen NPC's, a spot's)
				local many = type(raw.spots) == "table" and #raw.spots > 0
				local spots = many and raw.spots or { { x = gv.x, y = gv.y } }
				local map, f = many and raw.map or gv.map, many and raw.f or gv.f
				local cont, places = nil, {}
				for _, s in ipairs(spots) do
					local okL, m, x, y = pcall(nav.LiveCoords, { map = map, x = s.x, y = s.y, f = f })
					m, x, y = okL and tonumber(Plain(m)), okL and Finite(x), okL and Finite(y)
					local okW, c, pos
					if m and x and y then
						okW, c, pos = pcall(CM.GetWorldPosFromMapPos, m, V2(x / 100, y / 100))
					end
					c = okW and tonumber(Plain(c)) or nil
					local wx, wy
					if c then
						wx, wy = M.VectorXY(pos)
					end
					if c and wx and wy and (cont == nil or c == cont) then
						cont = c
						places[#places + 1], places[#places + 2] = wx, wy
					end
				end
				local text = Text(Pcall(word, gv)) or Text(gv.text)
				if cont and text and text ~= "" then
					local n = Text(Pcall(count, gv))
					local lines = { head }
					local who, lvl = Text(gv.npcName), type(gv.lvl) == "table" and gv.lvl
					if who and lvl then
						local lo, hi = tonumber(lvl[1] or lvl.min), tonumber(lvl[2] or lvl.max)
						lines[#lines + 1] = "From " .. who .. ((lo and hi and lo ~= hi) and (" (level " .. lo .. "-" .. hi .. ")")
							or (lo and (" (level " .. lo .. ")") or ""))
					end
					lines[#lines + 1] = W.Tr("Click: the way there")
					local si, gi = i, g
					out[#out + 1] = { key = "polestar:" .. tostring(guide.id) .. ":" .. i .. ":" .. g, kind = KIND[gv.t] or 4,
						text = n and (text .. " (" .. n .. ")") or text, quest = tonumber(Plain(gv.quest)), verb = VERB[gv.t],
						cont = cont, places = places, lines = lines,
						Aim = function() pcall(e.AimGoal, si, gi) end }
				end
			end
		end
		return out
	end

	-- (2.1.30, /route guide dump) its own state: the guide and step its engine is on, its arrow's target and whatever took
	-- it over (a goal or map click, a trip to a service), the places it hands the target to, a guide choice waiting
	function polestar.Dump(say)
		-- (a call's answer as words: yes / no for true / false -- Pcall's nil for false would read as "nothing")
		local function Said(fn, ...)
			if type(fn) ~= "function" then
				return "-"
			end
			local ok, v = pcall(fn, ...)
			v = ok and Plain(v)
			if not ok then
				return "error"
			elseif v == true then
				return "yes"
			elseif v == false or v == nil then
				return "no"
			end
			return tostring(v)
		end
		local t, e, nav = P(), Engine(), Nav()
		if not (t and e) then
			say("   Polestar: not loaded")
			return
		end
		local guide = Pcall(e.GetGuide)
		say("   Polestar's guide: %s (id %s), step %s of %s", tostring(type(guide) == "table" and Text(guide.title) or "none"),
			tostring(type(guide) == "table" and Plain(guide.id)), tostring(Pcall(e.GetStepIndex)), tostring(Pcall(e.GetStepCount)))
		local target = nav and Pcall(nav.GetTarget)
		if type(target) == "table" then
			local ok, m, x, y = pcall(nav.LiveCoords, target)
			x, y = ok and Finite(x), ok and Finite(y)
			say("   its arrow's target: %s (zone %s); the client's frame: %s", tostring(Text(target.label) or Text(target.name)
				or Text(target.title) or "-"), tostring(Pcall(nav.GetTargetZoneName)),
				(x and y) and Spot(Plain(m), x / 100, y / 100) or "unknown")
			local nb = rawget(nav, "nearby")
			local trip = type(nb) == "table" and Pcall(nb.Trip)
			say("   taken over (a goal or map click, a trip): %s%s", Said(nav.IsOverride),
				type(trip) == "table" and (", a trip to " .. tostring(Text(trip.name)) .. " (" .. tostring(Text(trip.label)) .. ")")
				or "")
		else
			say("   its arrow's target: none")
		end
		say("   handed to Shortest Path: %s; its own map pin: %s; TomTom's arrow: %s; a guide choice waiting: %s",
			Said(nav and nav.HandedOff), Said(t.Get, "nav.blizzardWaypoint"), Said(nav and nav.UsingTomTomArrow),
			Said(e.PendingRouteChoice))
	end

	-- its arrow: its own, or TomTom's when it hands its arrow there
	local function Arrow()
		local nav = Nav()
		if nav and Pcall(nav.UsingTomTomArrow) then
			return rawget(_G, "TomTomCrazyArrow")   -- (its arrow handed to TomTom's: that one)
		end
		return rawget(_G, "PolestarNavArrow")
	end

	function polestar.Frames()
		return List(Arrow(), rawget(_G, "PolestarGuideFrame"), rawget(_G, "PolestarQuestItemButton"),
			rawget(_G, "PolestarHearthButton"))
	end

	function polestar.Arrows()   -- (2.1.51: Guide.ArrowShown)
		return List(Arrow())
	end

	-- its minimap route, trail and target pin (the user's pick, 2026-10-31: "one route"), on frames with no name: off
	-- through its own nav.minimapPins while it is followed, for the session only -- given back when it is not and before
	-- the logout writes its saved settings, so its options never change. Turned on again in its options meanwhile: the
	-- player's, left so for the session.
	local held, theirs, leaving, logout
	function polestar.Quiet(on)
		local t = P()
		if not (t and type(t.Get) == "function" and type(t.Set) == "function") then
			return
		end
		local shown = Pcall(t.Get, "nav.minimapPins") and true or false
		if held and shown then
			held, theirs = false, true
		elseif on and not held and not theirs and not leaving and shown then
			held = true
			pcall(t.Set, "nav.minimapPins", false)
			if not logout then
				logout = CreateFrame("Frame")
				logout:SetScript("OnEvent", function()
					leaving = true   -- (its SETTING_CHANGED reads the guide again: nothing held after this)
					polestar.Quiet(false)
				end)
				logout:RegisterEvent("PLAYER_LOGOUT")
			end
		elseif not on and held then
			held = false
			pcall(t.Set, "nav.minimapPins", true)
		end
	end

	Guide.readers[#Guide.readers + 1] = polestar
end

-- Zygor Guides (2.1.9; the user, 2026-11-06, a friend's screenshot: its window and arrow beside the Quest Tracker: "should
-- be integrated into quest tracker exactly like restedxp is"). A paid addon with no copy here to read: its shape from its
-- own forum's error dumps and memory of its older versions (ZGV: CurrentGuide, CurrentStep, a step's goals, a goal's
-- GetText and IsComplete, SkipStep): NOT YET SEEN ON THE REAL ADDON. /route zygor lists what is really there. Its frames
-- are veiled only while its lines read: a Zygor of another shape keeps its own window and nothing is lost.
do
	local zygor = { key = "zygor", name = "Zygor", section = "Zygor Guide" }

	local function Z()
		local t = rawget(_G, "ZGV") or rawget(_G, "ZygorGuidesViewer")
		return type(t) == "table" and t or nil
	end

	local function Goals(z)
		local step = z and z.CurrentStep
		local goals = type(step) == "table" and step.goals
		return type(goals) == "table" and goals or nil, step
	end

	-- a goal's line as its window shows it, in the tracker's own look: no colour codes or pictures
	local function Clean(s)
		s = Text(s)
		if not s then
			return nil
		end
		s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|n", " ")
		s = s:gsub("^%s+", ""):gsub("%s+$", "")
		return s ~= "" and s or nil
	end

	local function Ask(goal, method, ...)
		if type(goal) ~= "table" or type(goal[method]) ~= "function" then
			return nil
		end
		return Pcall(goal[method], goal, ...)
	end

	local function GoalDone(goal)
		return Ask(goal, "IsComplete") == true
	end

	-- a goal's place, on the map's 0..1 (Zygor's own may be 0..100)
	local function Place(t)
		if type(t) ~= "table" then
			return nil
		end
		local m, x, y = tonumber(Plain(t.map or t.m)), Finite(t.x), Finite(t.y)
		if not (m and x and y) then
			return nil
		end
		if x > 1 or y > 1 then
			x, y = x / 100, y / 100
		end
		return m, x, y
	end

	-- NO POST-HOOK ON ANY METHOD OF ITS (2.1.10; a friend's error, 2026-11-06: 2.1.9's hooks stopped Zygor starting at all,
	-- "ERROR in startup frame 32: attempt to yield across metamethod/C-call boundary", through "[C]: in function
	-- 'SetGuide'"): its startup is a coroutine and SetGuide yields inside it; hooksecurefunc's wrapper is a C function, and
	-- nothing yields through one. Read on a slow ticker instead (Zygor checks its own goals once a second, its
	-- completioninterval), a line built again only when its step reads otherwise (Quick).
	-- OPT-IN until it is proven on the real addon (2.1.9 shipped it unproven and broke Zygor): for every player Zygor is left
	-- alone -- no ticker, nothing read, its own window. /route zygor on follows it, for the test.
	function zygor.Hook(changed)
		if not (Z() and M.db and M.db.zygorFollow) then
			return false
		end
		if not zygor.ticker then
			zygor.ticker = C_Timer.NewTicker(0.5, function()
				changed()
			end)
		end
		return true
	end

	-- /route zygor on | off (the test's): off, its own window and arrow back at once
	function Guide.ZygorFollow(on)
		if not M.db then
			return
		end
		M.db.zygorFollow = on and true or nil
		if on then
			Guide.Hook()
		else
			if zygor.ticker then
				zygor.ticker:Cancel()
				zygor.ticker = nil
			end
			zygor.hooked = nil
			Guide.Forget()
			Guide.Refresh()
		end
		MelloUI:Print("Following Zygor Guides: %s.", W.Tr(on and "on (a test)" or "off"))
	end

	-- its step's signature (Read: Steps only when it changed)
	function zygor.Quick()
		local z = Z()
		local goals = Goals(z)
		if not goals then
			return ""
		end
		local guide = z.CurrentGuide
		local parts = { tostring(Plain(z.CurrentStepNum)), tostring(type(guide) == "table" and guide.title) }
		for _, goal in ipairs(goals) do
			parts[#parts + 1] = tostring(Ask(goal, "GetText", true)) .. (GoalDone(goal) and "+" or "-")
		end
		return table.concat(parts, "\n")
	end

	-- the first open goal with a place, else its arrow's waypoint
	function zygor.Point()
		local z = Z()
		local goals = Goals(z)
		for _, goal in ipairs(goals or {}) do
			if not GoalDone(goal) then
				local m, x, y = Place(goal)
				if m then
					return m, x, y
				end
			end
		end
		local pointer = z and z.Pointer
		local arrow = type(pointer) == "table" and pointer.ArrowFrame
		return Place(type(arrow) == "table" and arrow.waypoint or nil)
	end

	function zygor.Steps()
		local z = Z()
		local goals, step = Goals(z)
		if not goals then
			return nil
		end
		local lines = {}
		for _, goal in ipairs(goals) do
			if Ask(goal, "IsVisible") ~= false then
				local text = Clean(Ask(goal, "GetText", true))
				if text then
					lines[#lines + 1] = { text = text, done = GoalDone(goal) }
				end
			end
		end
		if #lines == 0 then
			return nil
		end
		if type(z.SkipStep) == "function" then
			lines[#lines + 1] = { text = SKIP, done = false, box = true, skip = true, Toggle = function(skip)
				if skip then
					pcall(z.SkipStep, z)
				end
			end }
		end
		local guide = z.CurrentGuide
		local name = type(guide) == "table" and (Text(guide.title_short) or Text(guide.title)) or nil
		name = name and (name:match("([^\\/]+)$") or name) or "Zygor"
		local n = tonumber(Plain(z.CurrentStepNum)) or tonumber(Plain(step.num))
		-- (the cog: its guide menu at its own place, its settings: its window is veiled)
		local menu = z.GuideMenu
		local pick = type(menu) == "table" and type(menu.Show) == "function" and function() pcall(menu.Show, menu) end or nil
		local settings = type(z.OpenOptions) == "function" and function() pcall(z.OpenOptions, z) end or nil
		return { title = n and W.Tr("%s - step %s"):format(name, n) or name, lines = lines,
			cog = (pick or settings) and { Left = pick or settings, Right = settings or pick, tip = "Zygor Guides",
				hint = W.Tr("Click: its guides  -  Right-click: its settings") } or nil }
	end

	-- only while its lines read (zygor.steps: Read's): no step in the tracker, its own window stays
	function zygor.Frames()
		if not zygor.steps then
			return {}
		end
		local z = Z()
		local pointer = z and z.Pointer
		return List(z and z.Frame, z and z.MasterFrame, rawget(_G, "ZygorGuidesViewerFrame"),
			type(pointer) == "table" and pointer.ArrowFrame or nil, type(pointer) == "table" and pointer.arrow or nil)
	end

	function zygor.Arrows()   -- (2.1.51: Guide.ArrowShown)
		local z = Z()
		local pointer = z and z.Pointer
		return List(type(pointer) == "table" and pointer.ArrowFrame or nil, type(pointer) == "table" and pointer.arrow or nil)
	end

	-- /route zygor (2.1.9): what is really there, in the copy window, for a reader written without the addon at hand
	function Guide.DumpZygor()
		MelloUI:ClearLog()
		local function Say(...)
			MelloUI:Print(...)
		end
		local function Show(v)
			if MelloUI.Safe.IsSecret(v) then
				return "<secret>"
			end
			local kind = type(v)
			if kind == "table" then
				local okN, name = pcall(function() return v.GetObjectType and v:GetObjectType() end)
				return okN and name and ("frame " .. tostring(name)) or "table"
			end
			return kind == "function" and "function" or tostring(v)
		end
		local function Fields(label, t, limit)
			if type(t) ~= "table" then
				Say("%s: %s", label, Show(t))
				return
			end
			local keys = {}
			for k in pairs(t) do
				if type(k) == "string" then
					keys[#keys + 1] = k
				end
			end
			table.sort(keys)
			local parts = {}
			for i = 1, math.min(#keys, limit or 60) do
				local okV, v = pcall(function() return t[keys[i]] end)
				parts[#parts + 1] = keys[i] .. "=" .. (okV and Show(v) or "<error>")
			end
			Say("%s (%d keys): %s", label, #keys, table.concat(parts, "  "))
		end
		local CA = rawget(_G, "C_AddOns")
		for i = 1, tonumber(Pcall(CA and CA.GetNumAddOns)) or 0 do
			local name = Text(Pcall(CA.GetAddOnInfo, i))
			if name and name:find("Zygor") then
				Say("addon: %s, loaded %s", name, tostring(Pcall(CA.IsAddOnLoaded, name)))
			end
		end
		local z = Z()
		Say("ZGV %s, ZygorGuidesViewer %s", type(rawget(_G, "ZGV")), type(rawget(_G, "ZygorGuidesViewer")))
		Say("reader: hooked %s, runs %s, followed %s, lines %s, spot %s %s %s", tostring(zygor.hooked), tostring(zygor.runs),
			tostring(Guide.active == zygor), tostring(zygor.steps and #zygor.steps.lines), tostring(zygor.mapID),
			tostring(zygor.x), tostring(zygor.y))
		if z then
			for _, name in ipairs({ "FocusStep", "UpdateFrame", "TryToCompleteStep", "SetGuide", "SkipStep", "PreviousStep",
				"OpenOptions", "RegisterMessage", "SendMessage" }) do
				Say("method %s: %s", name, type(z[name]))
			end
			-- its frames and its big tables by name (it holds thousands of keys)
			local top = {}
			for k, v in pairs(z) do
				if type(k) == "string" and (k:find("Frame") or k:find("Pointer") or k:find("Menu") or k:find("Guide")
					or k:find("Step") or k:find("Arrow") or k:find("Action") or k:find("Item")) then
					top[k] = v
				end
			end
			Fields("ZGV", top, 80)
			Fields("CurrentGuide", z.CurrentGuide, 40)
			local goals, step = Goals(z)
			Fields("CurrentStep", step, 40)
			for i, goal in ipairs(goals or {}) do
				if i > 8 then
					break
				end
				Fields("goal " .. i, goal, 40)
				Say("goal %d: text [%s], complete %s, visible %s", i, tostring(Ask(goal, "GetText", true)),
					tostring(Ask(goal, "IsComplete")), tostring(Ask(goal, "IsVisible")))
			end
			local pointer = z.Pointer
			Fields("Pointer", pointer, 60)
			if type(pointer) == "table" then
				Fields("Pointer.ArrowFrame", pointer.ArrowFrame, 40)
				Fields("Pointer.ArrowFrame.waypoint", type(pointer.ArrowFrame) == "table" and pointer.ArrowFrame.waypoint or nil, 30)
			end
			Fields("GuideMenu", z.GuideMenu, 30)
		end
		-- its named frames on the screen
		local enum, count = rawget(_G, "EnumerateFrames"), 0
		local f = type(enum) == "function" and enum() or nil
		while f and count < 40 do
			local okN, name = pcall(f.GetName, f)
			if okN and type(name) == "string" and (name:find("^Zygor") or name:find("^ZGV")) then
				count = count + 1
				local okP, parent = pcall(f.GetParent, f)
				local okPN, pn = pcall(function() return parent and parent:GetName() end)
				Say("frame %s: shown %s, parent %s", name, tostring(Pcall(f.IsShown, f)), tostring(okP and okPN and pn))
			end
			f = enum(f)
		end
		MelloUI:ShowLog("Zygor Guides")
	end

	Guide.readers[#Guide.readers + 1] = zygor
end

-- TomTom: its arrow's waypoint (SetCrazyArrow's uid: uiMapID, x, y in 0..1), followed whoever set it (a /way, a
-- quest addon, Guidelime with its "Use TomTom arrow"); an arrow only, no steps; its waypoint gone (arrived, removed),
-- the pin laid for it goes too (clears)
do
	local tomtom = { key = "tomtom", name = "TomTom", clears = true }
	local target   -- the uid its arrow points at (TomTom's own table, read only)

	function tomtom.Hook(changed)
		local T = rawget(_G, "TomTom")
		local ps = rawget(_G, "Polestar")
		local nav = type(ps) == "table" and rawget(ps, "Nav")
		if type(T) ~= "table" or type(T.SetCrazyArrow) ~= "function"
			or (type(nav) == "table" and T == rawget(nav, "tomtomShim")) then
			return false   -- (Polestar's stand-in, TomTom not installed: it points Polestar's arrow, followed there)
		end
		hooksecurefunc(T, "SetCrazyArrow", function(_, uid)
			target = type(uid) == "table" and uid or nil
			changed()
		end)
		for _, name in ipairs({ "ClearCrazyArrowPoint", "RemoveWaypoint", "ClearWaypoint" }) do
			if type(T[name]) == "function" then
				hooksecurefunc(T, name, function()
					if Pcall(T.IsCrazyArrowEmpty, T) then
						target = nil
					end
					changed()
				end)
			end
		end
		-- (the sim, 2026-10-21: a waypoint removed -- Guidelime's step done, an arrival -- leaves its arrow pointing on;
		-- the arrow's own OnUpdate then finds it gone, empties itself in a local and hides: its hiding, the waypoint gone)
		local arrow = rawget(_G, "TomTomCrazyArrow")
		if type(arrow) == "table" and arrow.HookScript then
			Perf.HookScript(arrow, "OnHide", function()
				if target and Pcall(T.IsCrazyArrowEmpty, T) then
					target = nil
					changed()
				end
			end)
		end
		return true
	end

	function tomtom.Point()
		local T = rawget(_G, "TomTom")
		if type(target) ~= "table" or target.corpse or type(T) ~= "table" or Pcall(T.IsCrazyArrowEmpty, T) then
			return nil
		end
		return Plain(target[1]), Plain(target[2]), Plain(target[3])
	end

	function tomtom.Frames()
		return List(rawget(_G, "TomTomCrazyArrow"))
	end

	function tomtom.Arrows()   -- (2.1.51: Guide.ArrowShown; Guidelime's arrow through it too)
		return List(rawget(_G, "TomTomCrazyArrow"))
	end

	Guide.readers[#Guide.readers + 1] = tomtom
end

--------------------------------------------------------------------------------
-- More than one guide (the user, 2026-10-21, four guides running at once in
-- the game: "make a prompt at login, which detects addon conflicts and prompts
-- the user the choose only 1, the others get disabled in "AddOns""): once a
-- session, with two or more levelling guides loaded, MelloUI's question asks
-- which to keep. The others are switched off in the AddOns list for this
-- character (still installed: ticked again there they come back), with the
-- addons that need them (a guide's packs: TUGs needs Guidelime), and a /reload
-- finishes it (the game lets no addon reload the UI). "Keep them all" is
-- remembered for this character and these guides; "Not now" (or Escape) asks
-- again at the next login. Nothing is asked in a fight, over the installer or
-- with the Gamepad UI on (the question dialog's rule), or with following off.
--------------------------------------------------------------------------------
do
	local GUIDES = {   -- the levelling guides: folder (as the AddOns list knows it), name
		{ "RXPGuides", "RestedXP Guides" },
		{ "FollowTheArrow", "Follow The Arrow" },
		{ "APR", "Azeroth Pilot Reloaded" },
		{ "Guidelime", "Guidelime" },
		{ "ForeverWisp", "ForeverWisp" },
		{ "Polestar", "Polestar" },
		-- (2.1.51; the user installed it) FlowUp: its own map pin, followed with no reader; another guide's pin
		-- tracked stops it laying its own (it takes a tracked pin for the player's), so one guide at a time
		{ "FlowUp", "FlowUp" },
	}

	local function AddOns()
		local CA = rawget(_G, "C_AddOns")
		return type(CA) == "table" and CA or nil
	end

	-- the addons that need it (its guide packs), by folder
	local function Packs(folder)
		local CA = AddOns()
		local packs = {}
		for i = 1, tonumber(Pcall(CA and CA.GetNumAddOns)) or 0 do
			local deps = { pcall(CA.GetAddOnDependencies, i) }
			for j = 2, #deps do
				if deps[j] == folder then
					local name = Text(Pcall(CA.GetAddOnInfo, i))
					if name then
						packs[#packs + 1] = name
					end
					break
				end
			end
		end
		return packs
	end

	-- the one kept; the others (and their packs) switched off for this character, saved as the AddOns list saves them
	local function KeepOnly(kept, running, who)
		local CA = AddOns()
		for _, g in ipairs(running) do
			if g[1] ~= kept[1] then
				pcall(CA.DisableAddOn, g[1], who)
				for _, pack in ipairs(Packs(g[1])) do
					pcall(CA.DisableAddOn, pack, who)
				end
			end
		end
		pcall(CA.SaveAddOns)
		MelloUI:Announce(W.Tr("The other guides are switched off for this character: type /reload to finish."), "info")
	end

	function Guide.Ask()
		local CA = AddOns()
		local who = Text(Pcall(rawget(_G, "UnitGUID"), "player"))
		local inst = rawget(_G, "MelloUIInstallerFrame")
		if not (Following() and CA and CA.DisableAddOn and who and type(MelloUI.Confirm) == "function")
			or InCombatLockdown() or MelloUI.Safe.GamepadUI() or (type(inst) == "table" and inst:IsShown()) then
			return
		end
		local running, names = {}, {}
		for _, g in ipairs(GUIDES) do
			if Pcall(CA.IsAddOnLoaded, g[1]) then
				running[#running + 1] = g
				names[#names + 1] = g[2]
			end
		end
		if #running < 2 then
			return
		end
		local sig = table.concat(names, ",")
		local kept = M.db and type(M.db.guidesKept) == "table" and M.db.guidesKept[who]
		if kept == sig then
			return   -- ("Keep them all", for these guides)
		end
		local choices = {}
		for i, g in ipairs(running) do
			choices[i] = { label = g[2], onClick = function() KeepOnly(g, running, who) end }
		end
		choices[#choices + 1] = { label = "Keep them all", onClick = function()
			M.db.guidesKept = type(M.db.guidesKept) == "table" and M.db.guidesKept or {}
			M.db.guidesKept[who] = sig
		end }
		local list = table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
		MelloUI:Confirm({ text = list .. " are all on. MelloUI's Route follows one guide at a time, so the others get in "
			.. "its way. Which one do you keep? The others are switched off in the AddOns list for this character.",
			cancel = "Not now", choices = choices })
	end
end
