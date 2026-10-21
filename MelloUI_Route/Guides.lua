--------------------------------------------------------------------------------
-- MelloUI's Route: following a guide addon's step.
--
-- RestedXP Guides first (the user, 2026-10-18: "if our world marker could read
-- those coordinates and places a mark on that spot, that could work"), the
-- others since 2026-10-21 (the user: "add compatibility like we did with
-- restedxp for ... Follow the Arrow, TUGs Leveling Guidelime Guide ... and some
-- other"): one core for every guide, one reader per addon. While a guide runs:
--   * its step's spot gets the game's map pin, tracked, so the route and the
--     World Marker lead there (Guide.Step, read by Route's ReadWaypoint on the
--     pin's USER_WAYPOINT_UPDATED). A pin of the player's own is never moved,
--     and a step laid once is not laid again: a pin the player clears, or a
--     quest tracked instead (by the player, or by the guide: APR tracks its
--     quest steps' quests), stays so until the next step;
--   * its step's lines go to the Quest Tracker (the bus's "guide",
--     Guide.Publish), its items to the quest item widget ("guideitem",
--     Guide.PublishItems);
--   * its own arrow and window are veiled (Guide.Veil).
-- Several running: the one whose step changed last is followed, a guide with
-- steps before TomTom's bare arrow. Read only, post-hooks only, every read
-- guarded: an addon of another shape does nothing. /route guide (or /route rxp)
-- turns following off and on.
--
-- Guidelime keeps its steps to itself (no global state); its own "Use TomTom
-- arrow" option hands its spot to TomTom, which is followed. QuestMaster,
-- Shortest Path, Adventure Guide and ForeverWisp's marker mode lay the game's
-- pin themselves: Route follows them with no reader.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local CreateFrame = MelloUI.Safe.CreateFrame
local Perf = MelloUI.Perf:Scope("MelloUI_Route (Guides)")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
local Plain, Text, Finite = MelloUI.Safe.Value, MelloUI.Safe.Text, MelloUI.Safe.Finite
local M = MelloUI:GetModule("Route")

local Guide = { readers = {} }   -- mapID, x, y: the step laid last; active: the reader followed
M.Guide = Guide

local SKIP = "Skip this step"   -- (a guide that skips whole steps: the box under its lines)

local function Following()
	return M.isEnabled and M.db and M.db.followGuide ~= false or false
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
	Guide.sig, Guide.itemSig = nil, nil
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
	return table.concat(parts, "\n")
end

-- the guide followed: the active one while it runs; else a running guide with steps, else TomTom's arrow
local function Choose()
	if Guide.active and Guide.active.runs then
		return Guide.active
	end
	local arrow
	for _, reader in ipairs(Guide.readers) do
		if reader.runs then
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
end

-- a reader's post-hook: its step read again; one whose step changed takes over, a guide with steps over a bare arrow
function Guide.Changed(reader)
	if not (Following() and reader.hooked) then
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

function Guide.Step(force)   -- force: a click on the step (laid again, over the player's own pin too); true when laid
	local reader = Following() and Guide.active
	local zone, x, y = reader and reader.mapID, reader and reader.x, reader and reader.y
	if not (zone and x and y) then
		return
	end
	if not force and Same(zone, x, y, Guide.mapID, Guide.x, Guide.y) then
		return   -- this step was laid already
	end
	local okH, has = pcall(C_Map.HasUserWaypoint)
	if not force and okH and Plain(has) and not Ours() then
		return   -- the player's own pin stays (followed again once it is gone)
	end
	if not (C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
		return
	end
	Guide.mapID, Guide.x, Guide.y = zone, x, y
	if not pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(zone, x, y)) then
		return false
	end
	if M.db then
		M.db.guidePin = { zone, x, y }   -- (known for ours after a /reload: Laid)
	end
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
		pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
	end
	return true
end

-- the followed guide's step for the Quest Tracker (the user, 2026-10-18: its steps "shown in the quest tracker", with
-- "the manual checkbox to skip certain steps"), on the bus's "guide": a line per step line, done when completed or
-- skipped, a box when it can be skipped (line.Toggle, the guide's own skip). Published only when a line changed
-- (Guide.sig); nil once there is no guide or it is off.
function Guide.Publish()
	local reader = Following() and Guide.active
	local steps = reader and reader.steps
	local parts = { reader and reader.key or "" }
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

-- a click on the step in the Quest Tracker (the user, 2026-10-18: the World Marker missing, "click on that current
-- step and re-check the pin"): its spot laid and tracked again; a step with no spot says so
function Guide.Repin()
	if not Guide.Step(true) then
		MelloUI:Announce("This guide step has no place to mark on the map.", "info")
	end
end

-- a right-click on the step (the user, 2026-10-18: "a way to remove the waypoint, by right clicking on the
-- step"): the pin laid for it taken off, the route and the World Marker with it; the step stays laid (Guide.mapID),
-- so following does not put it back before the next step or a click. A pin of the player's own stays.
function Guide.Unpin()
	local okH, has = pcall(C_Map.HasUserWaypoint)
	if not (okH and Plain(has)) then
		return
	end
	if not Ours() then
		MelloUI:Announce("The map pin is your own, not this step's: it stays.", "info")
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
-- "item" or "spell", id, known } }; Frames() its own arrow and windows.
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
		return { title = (type(name) == "string" and name or "RestedXP") .. (n and (" - step " .. n) or ""),
			lines = lines,
			cog = { Left = menu and function() menu() end or settings, Right = settings, tip = "RestedXP Guides",
				hint = "Click: its menu (guides, settings)  -  Right-click: its settings" } }
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
		return { title = (name or "Follow The Arrow") .. (n and (" - step " .. n) or ""), lines = lines,
			cog = { Left = Guides, Right = Settings, tip = "Follow The Arrow",
				hint = "Click: its guides  -  Right-click: its settings" } }
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
		return { title = (route or "Azeroth Pilot") .. (n and (" - step " .. n .. (total and ("/" .. total) or "")) or ""),
			lines = lines,
			cog = { Left = Own, Right = Settings, tip = "Azeroth Pilot Reloaded",
				hint = "Click: its menu  -  Right-click: its settings" } }
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

	Guide.readers[#Guide.readers + 1] = apr
end

-- TomTom: its arrow's waypoint (SetCrazyArrow's uid: uiMapID, x, y in 0..1), followed whoever set it (a /way, a
-- quest addon, Guidelime with its "Use TomTom arrow"); an arrow only, no steps; its waypoint gone (arrived, removed),
-- the pin laid for it goes too (clears)
do
	local tomtom = { key = "tomtom", name = "TomTom", clears = true }
	local target   -- the uid its arrow points at (TomTom's own table, read only)

	function tomtom.Hook(changed)
		local T = rawget(_G, "TomTom")
		if type(T) ~= "table" or type(T.SetCrazyArrow) ~= "function" then
			return false
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
		MelloUI:Announce("The other guides are switched off for this character: type /reload to finish.", "info")
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
