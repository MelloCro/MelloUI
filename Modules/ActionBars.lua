--------------------------------------------------------------------------------
-- MelloUI - Action Bars: the action bars' backdrops and Hide Page Arrows
--
-- (onelook stage D4, docs/plans/onelook-cd-plans/D4.md: function out of the
-- skin) What the action bars' painted skin (Modules/ActionBarPanel.lua) kept
-- to itself until then, in the core: it works whether the skin is on or off.
--   Backdrops (0.18.5; user, 2026-09-23, sketched on the bars: "make a
--   backdrop border behind the action bar"; 2026-10-04, docs/plans/
--   dynamic-backdrops.md: "give the users more freedom to snap more random
--   Elements together and form a unified backdrop"). Every element in
--   ELEMENTS can wear one, by its own switch (off on a new install).
--   Elements that stand together share ONE backdrop: their pads (the
--   buttons' rect grown by the drawer's pad and a gap, PadOf) that touch or
--   overlap make a group, drawn in its leader's look (the first in
--   ELEMENTS). Its outline is MelloUI.Outline's (Core/Outline.lua). A status
--   bar in a group with others is fitted to their width (SetFit). Drawn on a
--   holder of the leader's (its moves, scale and hiding followed) through
--   MelloUI.Backdrop's drawers (Core/Backdrop.lua): MelloUI's own soft shade
--   (the user's pick B, 2026-10-15), or a dressing's (the painted skin's
--   gems: M.SetDressing). Laid out out of combat after a change
--   (ScheduleBackdrop).
--   Hide Page Arrows (user, 2026-09-21; on for everyone since onelook stage
--   D4): the main bar's page number and its up / down arrows faded and
--   their mouse off; the bar still pages with the keybinds.
--   Hide Bar Art (0.25.0; user, 2026-10-15, on by default): Action Bar 1
--   without the game's bar art, like the other bars, through the game's own
--   Edit Mode setting saved into the player's own active layout
--   (Core/EditModeLayout.lua; shows from the next reload; never a preset);
--   off: the game's value back where MelloUI changed it. Its section below.
-- Hidden and always on (no switch of its own: each row switches one thing);
-- the installer's role "look" (Reskin only takes Full's backdrops, as it
-- took the skin's). Nothing at login while every backdrop is off and no skin
-- dresses them: no hook on a game frame, no holder, no layout.
--   M.ELEMENTS               the elements, in order (read only)
--   M.BarButtons(bar)        a bar's buttons
--   M.Anchor(id)             where a group's own buttons hang: "bars",
--                            "micro" or "bags"
--   M.SetDressing(d | nil)   the skin's dressing on (laid out at once) or
--                            off (laid out a moment later, in MelloUI's own
--                            look): { drawer = "<registered id>",
--                            Look(group) -> its look for the drawer,
--                            Holder(f, root) (a holder made or kept),
--                            Before() (ahead of each layout's measure),
--                            After() (behind its drawing) }
--   M.Layout(), M.Schedule() every backdrop laid out now / a moment later
--   M.DumpBackdrops()        /abdump backdrops' lines
--   M.kept                   holders, fits, covered, inShape, members (read
--                            only: the dumps, the skin's rim shade, the tests)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("ActionBars")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
local Kit = MelloUI.Kit
local Backdrop = MelloUI.Backdrop
local Outline = MelloUI.Outline
-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret
local ScreenRect = Backdrop.ScreenRect   -- (the backdrops' one rect reader: MelloUI.Safe.ScreenRect's)
-- what the kit keeps beside the game's frames (weak-keyed, never keys on them)
local repOf = MelloUI.Kept.repOf

-- The elements that can wear a backdrop (user, 2026-10-04: "Everything
-- should have the option to have a backdrop, but not on by Default"), each
-- by its own switch, in the order that makes a joined backdrop's leader
-- (whose look it takes: Action Bar 1, then the other bars, the micro menu,
-- the bag bar; the experience and reputation bars wear the action bars'
-- look). `frame`: the element's frame; `group`: whose look it wears.
local ELEMENTS = {
	{ key = "backdropBar1", frame = "MainActionBar", name = "Action Bar 1", what = "Action Bar 1", group = "bars" },
	{ key = "backdropBar2", frame = "MultiBarBottomLeft", name = "Action Bar 2", what = "Action Bar 2", group = "bars" },
	{ key = "backdropBar3", frame = "MultiBarBottomRight", name = "Action Bar 3", what = "Action Bar 3", group = "bars" },
	{ key = "backdropBar4", frame = "MultiBarRight", name = "Action Bar 4", what = "Action Bar 4", group = "bars" },
	{ key = "backdropBar5", frame = "MultiBarLeft", name = "Action Bar 5", what = "Action Bar 5", group = "bars" },
	{ key = "backdropBar6", frame = "MultiBar5", name = "Action Bar 6", what = "Action Bar 6", group = "bars" },
	{ key = "backdropBar7", frame = "MultiBar6", name = "Action Bar 7", what = "Action Bar 7", group = "bars" },
	{ key = "backdropBar8", frame = "MultiBar7", name = "Action Bar 8", what = "Action Bar 8", group = "bars" },
	{ key = "backdropStance", frame = "StanceBar", name = "Stance Bar", what = "the stance bar", group = "bars" },
	{ key = "backdropPet", frame = "PetActionBar", name = "Pet Bar", what = "the pet bar", group = "bars" },
	{ key = "backdropPossess", frame = "PossessActionBar", name = "Possess Bar", what = "the possess bar", group = "bars" },
	-- (0.20.2, the user: "The Totem Bar is missing from the Checkbox menus") the shaman's totem bar
	-- (Blizzard_ActionBar/Shared/MultiCastActionBarFrame.xml, Edit Mode's Totem Bar): no bar of the kit's, so its
	-- rect is its shown buttons' -- the summon button, the four slots (the page's action buttons lie on them) and
	-- the recall button
	{ key = "backdropTotem", frame = "MultiCastActionBarFrame", name = "Totem Bar", what = "the totem bar", group = "bars",
	  buttons = { "MultiCastSummonSpellButton", "MultiCastSlotButton1", "MultiCastSlotButton2",
		"MultiCastSlotButton3", "MultiCastSlotButton4", "MultiCastRecallSpellButton" } },
	{ key = "backdropMicro", frame = "MicroMenu", name = "Micro Menu", what = "the micro menu", group = "micro" },
	{ key = "backdropBags", frame = "BagsBar", name = "Bag Bar", what = "the bag bar", group = "bags" },
	{ key = "backdropXP", frame = "MainStatusTrackingBarContainer", name = "Experience Bar", status = true, group = "bars",
	  what = "the experience bar (the reputation bar in its place at the top level)" },
	{ key = "backdropXP2", frame = "SecondaryStatusTrackingBarContainer", name = "Reputation Bar", status = true, group = "bars",
	  what = "the second status bar (a watched reputation while you level)" },
}

local defaults = { hidePageArrows = true, hideBarArt = true }
local options = {
	{ type = "toggle", key = "hidePageArrows", name = "Hide Page Arrows",
	  desc = "Hide the main bar's page number and its up / down arrows (the bar still pages with the keybinds)." },
	-- (0.25.0; the user, 2026-10-15: "MelloUI hides it") the game's own Edit Mode setting (Hide Bar Art, below)
	{ type = "toggle", key = "hideBarArt", name = "Hide Bar Art", new = "0.25.0",
	  desc = "Action Bar 1 without the game's bar art (its frame, dividers and the art of empty slots), like "
		.. "the other bars: MelloUI ticks Edit Mode's own Hide Bar Art for it. Only on your own Edit Mode layouts: a "
		.. "preset such as Modern can't be changed. Shows after a /reload. Off: the art back on the layouts MelloUI "
		.. "changed (or set it yourself in Edit Mode)." },
}
for _, e in ipairs(ELEMENTS) do
	defaults[e.key] = false
	-- (0.20.2, the user: "Checkbox on, the Bar gets its backdrop and merges seamlessly, Checkbox off, no backdrop and
	-- no merging")
	options[#options + 1] = { type = "toggle", key = e.key, name = e.name, new = e.new,
		desc = "A backdrop round " .. e.what .. ", merged into one with the other switched-on elements placed next to it"
			.. (e.status and " (this bar then takes their width, within a limit)" or "") .. ". Off: no backdrop, and it "
			.. "joins none." }
end

local M = MelloUI:RegisterModule("ActionBars", {
	title = "Action Bars",
	desc = "The backdrops round the action bars, the micro menu, the bag bar and the experience bars, and the main bar's "
		.. "page arrows and bar art hidden, whatever their look.",
	-- (always on: no switch of its own, each of its rows switches one thing)
	hidden = true,
	role = "look",
	enabledByDefault = true,
	defaults = defaults,
	options = options,
	-- the per-element switches taken over once (MigrateBackdrops): this
	-- machine's step, never in a profile; (0.25.0) Hide Bar Art's records:
	-- the game's values MelloUI replaced, to give back
	keep = { "backdropsMigrated", "barArtWas" },
})
M.ELEMENTS = ELEMENTS

local ELEMENT_KEY = {}    -- an element's backdrop switch -> the element
for _, e in ipairs(ELEMENTS) do
	ELEMENT_KEY[e.key] = e
end

local BAG_BUTTONS = { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
	"CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton" }

local on = false   -- running (OnEnable .. OnDisable)

--------------------------------------------------------------------------------
-- Measuring: the members' rects on the screen
--------------------------------------------------------------------------------

-- A bar's buttons: its own list (the game's), else its numbered ones
local function BarButtons(bar)
	if type(bar.actionButtons) == "table" and #bar.actionButtons > 0 then
		return bar.actionButtons
	end
	local list = {}
	local prefix = bar:GetName()
	prefix = prefix and prefix:gsub("ActionBar$", "") or ""
	for i = 1, 12 do
		local button = _G[prefix .. "Button" .. i]
		if button then
			list[#list + 1] = button
		end
	end
	return list
end
M.BarButtons = BarButtons

-- [bar] = { buttons = its buttons }, kept once it has any (a table of ours:
-- never a key on the game's bar)
local barEntries = setmetatable({}, { __mode = "k" })
local function Entry(bar)
	local entry = barEntries[bar]
	if not entry then
		local buttons = BarButtons(bar)
		if #buttons == 0 then
			return nil
		end
		entry = { buttons = buttons }
		barEntries[bar] = entry
	end
	return entry
end

-- The buttons' rect of a bar (the ones its layout shows, in screen px, into
-- `into` or a new table), and one button's size.
local function ButtonsRect(bar, into)
	local entry = Entry(bar)
	if not entry then
		return nil
	end
	local showable = bar.numButtonsShowable
	local count = (not Secret(showable) and tonumber(showable)) or #entry.buttons
	-- the stance / pet / possess bars keep buttons for forms and spells the
	-- character does not have, hidden: only the shown ones count there (an
	-- action bar's empty buttons hide too, so its layout's count is used)
	local shownOnly = bar == _G.StanceBar or bar == _G.PetActionBar or bar == _G.PossessActionBar
	local rl, rb, rr, rt, size
	for i, button in ipairs(entry.buttons) do
		if i <= count and (not shownOnly or button:IsShown()) then
			local l, b, r, t = ScreenRect(button)
			if l then
				size = size or (r - l)
				if rl then
					rl, rb, rr, rt = math.min(rl, l), math.min(rb, b), math.max(rr, r), math.max(rt, t)
				else
					rl, rb, rr, rt = l, b, r, t
				end
			end
		end
	end
	if not rl then
		return nil, size
	end
	local rect = into or {}
	rect[1], rect[2], rect[3], rect[4] = rl, rb, rr, rt
	return rect, size
end

-- The rect of a set of buttons (the shown ones, screen px, into `into` or a
-- new table) and the size of the smallest one's shorter side.
local function ShownRect(buttons, into)
	local rl, rb, rr, rt, size
	for _, button in ipairs(buttons) do
		if button:IsShown() then
			-- the rim's rect where a skin dressed it with one (a micro
			-- button's rim is a square on a taller button: the backdrop keeps
			-- the same distance to the rims on every bar)
			local rim = repOf[button] and repOf[button].object
			local l, b, r, t
			if rim and rim.IsShown and rim:IsShown() then
				l, b, r, t = ScreenRect(rim)
			end
			if not l then
				l, b, r, t = ScreenRect(button)
			end
			if l then
				local side = math.min(r - l, t - b)
				size = size and math.min(size, side) or side
				if rl then
					rl, rb, rr, rt = math.min(rl, l), math.min(rb, b), math.max(rr, r), math.max(rt, t)
				else
					rl, rb, rr, rt = l, b, r, t
				end
			end
		end
	end
	if not rl then
		return nil, size
	end
	local rect = into or {}
	rect[1], rect[2], rect[3], rect[4] = rl, rb, rr, rt
	return rect, size
end

-- The micro menu's buttons (its children with a plate: the game's micro
-- buttons, read as varargs -- no table -- once, by the first measure that
-- finds them, as the skin dressed them once) and the bag bar's slots (filled
-- again by each measure); lists of ours
local microList, bagList, totemList = {}, {}, {}
local function CollectMicro(n, button, ...)
	if not button then
		return n
	end
	if type(button.Background) == "table" then
		n = n + 1
		microList[n] = button
	end
	return CollectMicro(n, ...)
end

local function MicroButtons()
	if microList[1] == nil then
		local menu = rawget(_G, "MicroMenu")
		if type(menu) == "table" and menu.GetChildren then
			CollectMicro(0, menu:GetChildren())
		end
	end
	return microList
end

local function BagButtons()
	local n = 0
	for _, name in ipairs(BAG_BUTTONS) do
		local button = rawget(_G, name)
		if type(button) == "table" and button.icon and button.GetNormalTexture then
			n = n + 1
			bagList[n] = button
		end
	end
	for i = #bagList, n + 1, -1 do
		bagList[i] = nil
	end
	return bagList
end

-- Where each group's own buttons hang
local ANCHORS = {
	bars = function() return rawget(_G, "MainActionBar") or rawget(_G, "MainMenuBar") end,
	micro = function() return rawget(_G, "MicroMenu") end,
	bags = function() return rawget(_G, "BagsBar") end,
}

function M.Anchor(id)
	local fn = ANCHORS[id]
	return fn and fn() or nil
end

-- The unit every pad and drawer follows: an action button's side in screen
-- px, Action Bar 1's (so the backdrops match wherever two elements meet --
-- user, 2026-09-23: the bag bar's rails, on its larger buttons, came out
-- thicker than the micro menu's where the two joined); without it, the first
-- member's. Nil when nothing can be measured.
local SCRATCH = {}   -- (Action Bar 1's rect, not needed: a table of ours filled)
local function Unit(list, n)
	local main = ANCHORS.bars()
	if type(main) == "table" then
		local _, size = ButtonsRect(main, SCRATCH)
		if size and size > 0 then
			return size
		end
	end
	for i = 1, n do
		if list[i].size then
			return list[i].size
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- The experience and reputation bars fitted (user, 2026-10-04: they "should
-- follow and adjust their width to fit the border and not strech it too
-- much"). A status bar in a drawn backdrop with other elements takes the
-- width of their buttons above or below it, by its scale: the container's
-- plain SetScale (Edit Mode's *Base). Its width is Edit Mode's Size, which
-- the bars inside follow only through the game's own layout functions,
-- never run from here. Within 0.85 - 1.25 only; past that it keeps its own
-- size and the outline takes it as it is. A change keeps its anchor where
-- it stands on the screen by the game's own rule (EditModeSystemMixin:
-- SetScaleOverride: the offsets times old / new). The game's later anchors
-- carry the scale themselves (ApplySystemAnchor: offset / scale), except the
-- bottom stack's for a bar in its default place (EditModeManagerFrame:
-- UpdateBottomActionBarPositions: plain offsets), which KeepFitPlaces puts on
-- the scale again. Never in a fight; the bar's own scale back when it
-- leaves its backdrop, the backdrop goes, or the module goes off.
--------------------------------------------------------------------------------

local FIT_MIN, FIT_MAX = 0.85, 1.25
local fits = {}      -- [container] = { base = its scale before, k = the factor on it, x, y = its first point's offsets as set here }
local fitSeen = {}   -- [container] = true: fitted by this layout (filled by each)

local function Protected(f)
	return MelloUI.Safe.Call(f, "IsProtected") == true
end

-- the container's anchors, their offsets times `by` (Edit Mode's *Base),
-- and its first point's offsets remembered; false when one cannot be read
local function ScaleAnchors(container, by, fit)
	local n = MelloUI.Safe.Call(container, "GetNumPoints")
	if type(n) ~= "number" or n < 1 then
		return false
	end
	local points = {}
	for i = 1, n do
		local ok, point, rel, relPoint, x, y = pcall(container.GetPoint, container, i)
		x, y = ok and MelloUI.Safe.Finite(x), ok and MelloUI.Safe.Finite(y)
		if not (x and y) then
			return false
		end
		points[i] = { point, rel, relPoint, x * by, y * by }
	end
	local setPoint = container.SetPointBase or container.SetPoint
	for _, pt in ipairs(points) do
		setPoint(container, pt[1], pt[2], pt[3], pt[4], pt[5])
	end
	if fit then
		fit.x, fit.y = points[1][4], points[1][5]
	end
	return true
end

-- The fit `k` on a status bar's container (1: its own scale back); true when
-- its scale changed. Never in a fight.
local function SetFit(container, k)
	local fit = fits[container]
	local have = fit and fit.k or 1
	if math.abs(have - k) < 0.001 or InCombatLockdown() then
		return false
	end
	local base = fit and fit.base
	if not base then
		local ok, v = pcall(container.GetScale, container)
		base = ok and MelloUI.Safe.Finite(v) or 1
		if base <= 0 then
			base = 1
		end
	end
	local setScale = container.SetScaleBase or container.SetScale
	setScale(container, base * k)
	if k == 1 then
		fits[container] = nil
		ScaleAnchors(container, have / k)
	else
		fit = fit or { base = base }
		fit.k = k
		fits[container] = fit
		ScaleAnchors(container, have / k, fit)
	end
	return true
end

-- After the game's bottom stack laid a fitted bar in its default place (its
-- offsets plain, for the bar's own scale; their change from the ones set
-- here tells it did): its offsets on the fit again, at once. Counted
-- (MelloUI.Perf.WriteBack): the stack is laid when a bar shows, hides or
-- moves, never per frame. A protected one in a fight waits for the next
-- layout (Layout runs this first).
local function KeepFitPlaces()
	for container, fit in pairs(fits) do
		local okD, default = pcall(container.IsInDefaultPosition, container)
		local ok, _, _, _, x, y = pcall(container.GetPoint, container, 1)
		x, y = ok and MelloUI.Safe.Finite(x), ok and MelloUI.Safe.Finite(y)
		if okD and default == true and x and y and (math.abs(x - (fit.x or 0)) > 1e-4 or math.abs(y - (fit.y or 0)) > 1e-4)
			and not (InCombatLockdown() and Protected(container)) then
			ScaleAnchors(container, 1 / fit.k, fit)
			MelloUI.Perf.WriteBack("ActionBars: a fitted status bar's place")
		end
	end
end

-- Every fit taken off (the module off): out of combat
local function RestoreFits()
	for container in pairs(fits) do
		SetFit(container, 1)
	end
end

--------------------------------------------------------------------------------
-- The members and their groups
--------------------------------------------------------------------------------

local FRAME_GAP = 0.12   -- of a button's size: the space round the members' buttons inside the backdrop

-- an element shown on the screen (a micro menu parked by Tweaks' Hide Micro
-- Menu reads shown under its hidden holder: left out)
local function OnScreen(f)
	local ok, v = pcall(f.IsVisible, f)
	return ok and not Secret(v) and v == true
end

-- An element's rect (its buttons', screen px, into `into`) and a button's
-- size; a status bar's is its container's as it stands (fitted or not), with
-- no size
local function MemberRect(e, root, into)
	if e.buttons then
		local n = 0
		for _, name in ipairs(e.buttons) do
			local button = rawget(_G, name)
			if type(button) == "table" and button.IsShown then
				n = n + 1
				totemList[n] = button
			end
		end
		for i = #totemList, n + 1, -1 do
			totemList[i] = nil
		end
		return ShownRect(totemList, into)
	end
	if e.status then
		local l, b, r, t = ScreenRect(root)
		if not l then
			return nil
		end
		local rect = into or {}
		rect[1], rect[2], rect[3], rect[4] = l, b, r, t
		return rect
	elseif e.group == "bars" then
		return ButtonsRect(root, into)
	end
	local rect, size = ShownRect(e.group == "micro" and MicroButtons() or BagButtons(), into)
	-- the bag bar's fold arrow (Tweaks' Collapse Arrow) inside it while it
	-- shows: in the rect, never the size (the gap is a button's share)
	local toggle = e.group == "bags" and rawget(_G, "BagBarExpandToggle")
	if rect and toggle and toggle:IsShown() then
		local l, b, r, t = ScreenRect(toggle)
		if l then
			rect[1], rect[2] = math.min(rect[1], l), math.min(rect[2], b)
			rect[3], rect[4] = math.max(rect[3], r), math.max(rect[4], t)
		end
	end
	return rect, size
end

-- A member's pad: its rect grown by the drawer's pad (the gems' frame's
-- rails, at `unit`) and the gap (a share of its button, else of `unit`,
-- Action Bar 1's), kept in m.pad
local function PadOf(m, unit, drawer)
	m.pad = drawer.Pad(m.rect, unit, FRAME_GAP * (m.size or unit), m.pad)
	return m.pad
end

-- The elements on the screen now, in ELEMENTS' order: { e, root, rect,
-- size, on, pad } (the entries kept and filled again by each layout)
local members = {}
local function Members()
	local n = 0
	local db = M.db
	for _, e in ipairs(ELEMENTS) do
		local root = rawget(_G, e.frame)
		if type(root) == "table" and root.GetObjectType and OnScreen(root) then
			local m = members[n + 1]
			local rect, size = MemberRect(e, root, m and m.rect)
			if rect then
				n = n + 1
				m = m or {}
				members[n] = m
				m.e, m.root, m.rect = e, root, rect
				m.size = size and size > 0 and size or nil
				m.on = db ~= nil and db[e.key] == true
			end
		end
	end
	for i = #members, n + 1, -1 do
		members[i] = nil
	end
	return members, n
end

-- The factor that fits status bar m to the buttons of the others of its
-- group above or below it (at least half of one across the other: a bar
-- that only meets its end, the micro menu snapped beside, is not one); 1
-- when there are none or it falls outside the limits
local function FitFor(m, group, list)
	local l, r
	for _, i in ipairs(group) do
		local o = list[i]
		if not o.e.status then
			local ox0, ox1 = o.rect[1], o.rect[3]
			local over = math.min(ox1, m.rect[3]) - math.max(ox0, m.rect[1])
			if over > 0.5 * math.min(ox1 - ox0, m.rect[3] - m.rect[1]) then
				l = l and math.min(l, ox0) or ox0
				r = r and math.max(r, ox1) or ox1
			end
		end
	end
	local fit = fits[m.root]
	local natural = (m.rect[3] - m.rect[1]) / (fit and fit.k or 1)
	if not l or natural <= 0 then
		return 1
	end
	local k = (r - l) / natural
	if k < FIT_MIN or k > FIT_MAX then
		return 1
	end
	return math.floor(k * 1000 + 0.5) / 1000
end

--------------------------------------------------------------------------------
-- The drawing: a holder per leader, drawn by the drawer of the look
--------------------------------------------------------------------------------

local holders = {}      -- [element key] = the holder of the backdrop that element leads (made the first time it leads one)
local inShape = {}      -- [root] = true: in a drawn backdrop (filled by each layout; a status bar's bracket gives way)
local covered = {}      -- [root] = true while a shown backdrop covers that element (the skin's rim shade reads it)
local holderUsed = {}   -- [holder] = true: drawn by this layout
local dressing = nil    -- the skin's (M.SetDressing), else nil: MelloUI's own look

-- the drawer of the look now: the dressing's, else MelloUI's own
local function Current()
	return Backdrop.Drawer(dressing and dressing.drawer)
end

-- a holder on the leader (Core/Backdrop.lua), the dressing's parts on it
local function NewHolder(root)
	local f = Backdrop.Holder(root)
	if dressing and dressing.Holder then
		dressing.Holder(f, root)
	end
	return f
end

local padList = {}   -- (the members' pads in their order: Outline.Clusters' input, kept)
local onList = {}    -- (the switched-on members, padList's order: kept)

-- Every backdrop laid out: the members, their groups, the status bars'
-- fits, each drawn group on its leader's holder; the holders no group
-- needs hidden
local function LayoutBackdrops()
	wipe(fitSeen)
	wipe(holderUsed)
	local drawer = Current()
	local list, n = Members()
	local unit = Unit(list, n)
	if unit and n > 0 then
		-- (0.20.2, the user: "Checkbox on, the Bar gets its backdrop and merges seamlessly, Checkbox off, no
		-- backdrop and no merging") only the switched-on elements make backdrops and join them: a bar switched off
		-- beside one switched on stays out of its backdrop
		local count = 0
		for i = 1, n do
			if list[i].on then
				count = count + 1
				onList[count] = list[i]
				padList[count] = PadOf(list[i], unit, drawer)
			end
		end
		for i = #padList, count + 1, -1 do
			padList[i], onList[i] = nil, nil
		end
		list = onList
		local groups = Outline.Clusters(padList, drawer.reach or 0)
		for _, group in ipairs(groups) do
			group.drawn = true
			-- the status bars of a drawn group fitted first: their pads again
			for _, i in ipairs(group) do
				local m = list[i]
				if m.e.status then
					local k = group.drawn and FitFor(m, group, list) or 1
					if k ~= 1 then
						fitSeen[m.root] = true
					end
					if SetFit(m.root, k) then
						local l, b, r, t = ScreenRect(m.root)
						if l then
							m.rect[1], m.rect[2], m.rect[3], m.rect[4] = l, b, r, t
							PadOf(m, unit, drawer)
						end
					end
				end
			end
		end
		for _, group in ipairs(groups) do
			if group.drawn then
				local leader = list[group[1]]
				local f = holders[leader.e.key]
				if not f and not InCombatLockdown() then
					-- (never made in a fight: the leader can be protected; the
					-- layout after it makes it)
					f = NewHolder(leader.root)
					holders[leader.e.key] = f
				end
				if f then
					-- (the group's pads: a list of the holder's own, filled again)
					local pads = f.pads or {}
					f.pads = pads
					for k, i in ipairs(group) do
						pads[k] = list[i].pad
					end
					for k = #pads, #group + 1, -1 do
						pads[k] = nil
					end
					local look = dressing and dressing.Look and dressing.Look(leader.e.group)
					if drawer.Draw(f, pads, unit, look) then
						holderUsed[f] = true
						for _, i in ipairs(group) do
							covered[list[i].root] = true
							inShape[list[i].root] = true
						end
					end
				end
			end
		end
	end
	-- a fitted bar no longer in a drawn group: its own size back
	for container in pairs(fits) do
		if not fitSeen[container] then
			SetFit(container, 1)
		end
	end
	for _, f in pairs(holders) do
		if not holderUsed[f] then
			f:Hide()
		end
	end
end

--------------------------------------------------------------------------------
-- When: a layout wanted, the elements watched, the layout run
--------------------------------------------------------------------------------

local switchesOn = 0   -- the switched-on elements (Count)

local function Count()
	local n = 0
	local db = M.db
	for _, e in ipairs(ELEMENTS) do
		if db and db[e.key] == true then
			n = n + 1
		end
	end
	switchesOn = n
end

local function AnyShown()
	for _, f in pairs(holders) do
		if f:IsShown() then
			return true
		end
	end
	return false
end

-- anything to lay out: a dressing (it lays its rims' shade by every layout),
-- a switch on, or what an earlier layout left (a fit, a shown backdrop)
local function Wanted()
	return on and (dressing ~= nil or switchesOn > 0 or next(fits) ~= nil or AnyShown())
end

local ScheduleBackdrop   -- (below)

-- What moves a backdrop: an element re-laid, shown or hidden, resized,
-- dragged in Edit Mode, Edit Mode closed. (The watched ones in a table of
-- ours: never a key on the game's frames.)
local watched = setmetatable({}, { __mode = "k" })
local function WatchForBackdrop(bar)
	if not bar or watched[bar] then
		return
	end
	watched[bar] = true
	Perf.HookScript(bar, "OnShow", ScheduleBackdrop)
	Perf.HookScript(bar, "OnHide", ScheduleBackdrop)
	Perf.HookScript(bar, "OnSizeChanged", ScheduleBackdrop)
	for _, method in ipairs({ "UpdateGridLayout", "Layout", "OnDragStop", "OnSystemPositionChange" }) do
		if type(bar[method]) == "function" then
			hooksecurefunc(bar, method, ScheduleBackdrop)
		end
	end
end

-- (0.20.2) the totem bar: watched as a bar, and its slots shown or hidden as
-- the shaman's totems change (MultiCastActionBarFrame_Update, a post-hook)
local function WatchTotemBar()
	local bar = rawget(_G, "MultiCastActionBarFrame")
	if type(bar) ~= "table" or watched[bar] then
		return
	end
	WatchForBackdrop(bar)
	if type(rawget(_G, "MultiCastActionBarFrame_Update")) == "function" then
		hooksecurefunc("MultiCastActionBarFrame_Update", ScheduleBackdrop)
	end
end

-- the game's bottom stack laid its bars in their default places: a fitted
-- status bar's offsets on its fit again (KeepFitPlaces)
local function OnBottomStack()
	if next(fits) then
		KeepFitPlaces()
	end
end

-- Every element watched, once, by the first layout wanted (never at login
-- while every backdrop is off and no skin dresses them)
local watching = false
local function Watch()
	if watching then
		return
	end
	watching = true
	WatchTotemBar()
	for _, e in ipairs(ELEMENTS) do
		local f = rawget(_G, e.frame)
		if type(f) == "table" and f.GetObjectType then
			WatchForBackdrop(f)
		end
	end
	local em = rawget(_G, "EditModeManagerFrame")
	if type(em) == "table" and type(em.UpdateBottomActionBarPositions) == "function" then
		hooksecurefunc(em, "UpdateBottomActionBarPositions", OnBottomStack)
	end
end

local LAYOUT_KEY = "Action bars: layout"   -- (Kit:WhenOutOfCombat's key: one layout waits at a time)
local function Layout()
	if not Wanted() then
		return
	end
	Watch()
	wipe(covered)
	wipe(inShape)
	local d = dressing
	if d and d.Before then
		d.Before()
	end
	KeepFitPlaces()
	LayoutBackdrops()
	if d and d.After then
		d.After()
	end
	-- in a fight (a setting changed): laid out again after it, for what a
	-- protected bar could not get now (a holder, a status bar's fit, the
	-- dressing's frames)
	if InCombatLockdown() then
		Kit:WhenOutOfCombat(Layout, LAYOUT_KEY)
	end
end
M.Layout = Layout

-- Laid out again a moment after a change, out of combat (the bars' rects
-- settle after Edit Mode's layout).
local backdropPending = false
local function RunPending()
	backdropPending = false
	Kit:WhenOutOfCombat(Layout, LAYOUT_KEY)
end
function ScheduleBackdrop()
	if backdropPending or not Wanted() then
		return
	end
	backdropPending = true
	C_Timer.After(0.1, RunPending)
end
M.Schedule = ScheduleBackdrop

function M.SetDressing(d)
	dressing = d
	if d then
		if d.Holder then
			for _, f in pairs(holders) do
				d.Holder(f, f.root)
			end
		end
		Layout()
	else
		-- (a moment later: a restart switches the skin off and on again at
		-- once, and draws nothing in between)
		ScheduleBackdrop()
	end
end

--------------------------------------------------------------------------------
-- Hide Page Arrows
--------------------------------------------------------------------------------

local PAGE_BUTTONS = { "UpButton", "DownButton" }
local pageHidden = false   -- (the page faded here: only a change is written)

-- The main bar's page number and arrows hidden (user, 2026-09-21): faded and
-- their mouse off, put back when the option or the module goes off.
local function ApplyPageArrows()
	local bar = rawget(_G, "MainActionBar")
	local page = type(bar) == "table" and bar.ActionBarPageNumber
	if type(page) ~= "table" then
		return
	end
	local hide = (on and M.db and M.db.hidePageArrows) and true or false
	if hide == pageHidden then
		return
	end
	pageHidden = hide
	if hide then
		Kit:Fade(page)
	else
		Kit:Unfade(page)
	end
	for _, key in ipairs(PAGE_BUTTONS) do
		local button = page[key]
		if button and button.EnableMouse then
			button:EnableMouse(not hide)
		end
	end
end

--------------------------------------------------------------------------------
-- Hide Bar Art (0.25.0; the user, 2026-10-15: Action Bar 1 wore the game's bar
-- art -- UI-HUD-ActionBar-Frame, the dividers, the winged empty slots -- and
-- the other bars none; asked, "MelloUI hides it"). Not the gryphons: on this
-- client they are a system of their own (MainActionBarEndCap, its own Hidden;
-- Camelot's MAIN_ACTION_BAR_MANAGE_END_CAPS false), which Hide Bar Art reaches
-- only through the bar's OnShow (gone after the bar is shown again, back at a
-- reload): left to the game here (the user's look decision). Steered with
-- the game's OWN Edit Mode setting, Hide Bar Art of the main bar
-- (Enum.EditModeActionBarSetting.HideBarArt; the game draws it in
-- EditModeActionBarSystemMixin:UpdateSystemSettingHideBarArt), saved into the
-- player's active layout through Core/EditModeLayout.lua: C_EditMode only,
-- never the manager's methods, never laid out from here (its synchronous
-- re-layout ran on MelloUI's script budget, 0.19.9): the game shows it from the
-- next reload. Only the player's own layouts: a preset cannot be changed, and
-- nothing is copied or made active for it (the active layout is never
-- switched). Never in a fight (the core's combat queue), never while Edit Mode
-- is open (it would save its own copy over ours): its close runs it again.
--   when     the start-up pass (once every module is on), the game's
--            EDIT_MODE_LAYOUTS_UPDATED (the layouts loaded, another layout
--            made active), a spec change, Edit Mode closed: a frame later, one
--            pass at a time. Silent, but for a switch the player threw: the
--            /reload line once a session, the preset's line
--   records  barArtWas[owner][layout name] = the value MelloUI replaced, or
--            false: the player unchecked it in Edit Mode since (the art hidden
--            on the screen as Edit Mode opened, 0 saved on THAT layout as it
--            closed, read by name: another may be active by then): left alone
--            from then on. A save of Edit Mode's stale copy (MelloUI's value
--            saved, the art still showing until a reload) is written over
--            again. The owner: "account" for an account layout (every
--            character sees it), the character's own key (its GUID) for one of
--            its character layouts (no other character sees those; the saved
--            settings are the account's). Personal (`keep`): a game setting
--            borrowed, to give back
--   off      the game's value back on every layout MelloUI changed that this
--            character sees (the account's and its own, by name and type, in
--            one save), those records gone; another character's kept for its
--            own next pass. The module switched off (a restart) leaves the
--            layouts as they are; enabled with the option off and records of
--            its own kept (a profile loaded), they are given back
--------------------------------------------------------------------------------

local Art = {}   -- Start, Stop, Changed, EditMode (below)
do
	local InCombat, EditModeOpen = MelloUI.InCombat, MelloUI.EditModeOpen
	local PASS_KEY = "Action bars: bar art"           -- (Kit:NextFrame's key)
	local COMBAT_KEY = "Action bars: bar art, after the fight"   -- (Kit:WhenOutOfCombat's)
	local TEXT = {
		preset = "Hide Bar Art: your Edit Mode layout '%s' is one of the game's presets, which can't be changed; "
			.. "pick or copy a layout of your own in Edit Mode.",
	}
	local pending = false   -- a pass asked for
	local say = false       -- the player threw the switch: the lines, if something comes of it
	local entered           -- { name, kind, owner, live }: the active layout and the art on the screen as Edit Mode opened
	local events            -- the listener (made with the first wish, at the module's enable)
	local ACCOUNT = "account"   -- (the owner of an account layout's records)

	-- the main bar's system, its index and the setting (nil on a client without them)
	local function Ids()
		local E = rawget(_G, "Enum")
		local sys = type(E) == "table" and type(E.EditModeSystem) == "table" and E.EditModeSystem.ActionBar
		local bars = type(E) == "table" and E.EditModeActionBarSystemIndices
		local settings = type(E) == "table" and E.EditModeActionBarSetting
		local index = type(bars) == "table" and bars.MainBar
		local setting = type(settings) == "table" and settings.HideBarArt
		if type(sys) ~= "number" or type(index) ~= "number" or type(setting) ~= "number"
			or not MelloUI.EditModeSystemSettings then
			return nil
		end
		return sys, index, setting
	end

	local function ArtWanted()
		return M.db ~= nil and M.db.hideBarArt == true
	end

	-- this character's own key (its GUID; nil while unreadable)
	local function CharKey()
		local ok, guid = pcall(UnitGUID, "player")
		if not ok or Secret(guid) or type(guid) ~= "string" or guid == "" then
			return nil
		end
		return "char_" .. (guid:gsub("[^%w]", ""))
	end

	-- whose records a layout's are (see the header): the account's or this
	-- character's; nil for a type MelloUI leaves alone (none it knows) or
	-- while the character is unreadable
	local function Owner(kind)
		local E = rawget(_G, "Enum")
		local types = type(E) == "table" and E.EditModeLayoutType
		if type(types) ~= "table" or kind == nil then
			return nil
		end
		if kind == types.Account then
			return ACCOUNT
		elseif kind == types.Character then
			return CharKey()
		end
		return nil
	end

	-- one owner's records (made when asked)
	local function Records(owner, make)
		local db = M.db
		if not (db and owner) then
			return nil
		end
		local all = db.barArtWas
		local t = type(all) == "table" and all[owner] or nil
		if type(t) ~= "table" then
			if not make then
				return nil
			end
			if type(all) ~= "table" then
				all = {}
				db.barArtWas = all
			end
			t = {}
			all[owner] = t
		end
		return t
	end

	-- records this character can give back (the account's, its own)
	local function Mine()
		local rec, own = Records(ACCOUNT), Records(CharKey())
		return (rec ~= nil and next(rec) ~= nil) or (own ~= nil and next(own) ~= nil)
	end

	-- the art hidden on the screen now: the game's own flag on its bar (read only)
	local function LiveHidden()
		local bar = rawget(_G, "MainActionBar")
		local v = type(bar) == "table" and rawget(bar, "hideBarArt") or nil
		if Secret(v) then
			return false
		end
		return v == true
	end

	-- the active layout: its main bar's values, preset or not, its name and
	-- type (nil while unread)
	local function ActiveBar()
		local sys, index = Ids()
		if not sys then
			return nil
		end
		local values, preset, name, kind = MelloUI:EditModeSystemSettings(sys, index)
		if type(values) ~= "table" or type(name) ~= "string" then
			return nil   -- (unread: the layouts not loaded yet -- their event comes)
		end
		return values, preset, name, kind
	end

	-- Edit Mode closed with the art hidden on the screen as it opened: the
	-- layout active THEN, read by name (the player may have picked another
	-- since, or saved and switched), 0 saved there: the player's own untick
	local function Unticked(was)
		local sys, index, setting = Ids()
		local values = sys and MelloUI:EditModeLayoutSystemSettings(was.name, sys, index, was.kind)
		local v = type(values) == "table" and values[setting] or nil
		if type(v) == "number" and v ~= 1 then
			Records(was.owner, true)[was.name] = false
		end
	end

	local function Apply()
		local values, preset, name, kind = ActiveBar()
		local was = entered
		entered = nil
		if was and was.live then
			Unticked(was)
		end
		if not values then
			return
		end
		if preset then
			if say then
				MelloUI:Announce(TEXT.preset:format(name), "info")
			end
			return
		end
		local sys, index, setting = Ids()
		local now = values[setting]
		local owner = Owner(kind)
		if type(now) ~= "number" or now == 1 or not owner then
			return   -- (hidden already; or a layout of no type MelloUI knows: left alone)
		end
		local rec = Records(owner, true)
		if rec[name] == false then
			return   -- (the player's own: unchecked in Edit Mode since)
		end
		local ok, _, saved = MelloUI:SetEditModeSystemSettings(sys, index, { [setting] = 1 })
		if ok and saved then
			if rec[name] == nil then
				rec[name] = now
			end
			if say then
				MelloUI:SayEditModeReload()
			end
		end
	end

	-- the game's values back on the layouts this character sees (the
	-- account's, its own), by name and type, in one save; those records
	-- gone, another character's kept for its own pass
	local function Restore()
		local sys, index, setting = Ids()
		local all = M.db and M.db.barArtWas
		local E = rawget(_G, "Enum")
		local types = type(E) == "table" and E.EditModeLayoutType
		if not (sys and type(all) == "table" and type(types) == "table") then
			return
		end
		local entries, owners = {}, {}
		local function Add(owner, kind)
			local rec = owner and all[owner]
			if type(rec) ~= "table" then
				return
			end
			owners[#owners + 1] = owner
			for name, was in pairs(rec) do
				if type(name) == "string" and type(was) == "number" and was ~= 1 then
					entries[#entries + 1] = { layout = name, layoutType = kind, system = sys, index = index,
						values = { [setting] = was } }
				end
			end
		end
		Add(ACCOUNT, types.Account)
		Add(CharKey(), types.Character)
		local ok, saved = true, false
		if #entries > 0 then
			local _
			ok, _, saved = MelloUI:SetEditModeLayoutSettings(entries)
		end
		if ok then
			for _, owner in ipairs(owners) do
				all[owner] = nil
			end
			for owner, rec in pairs(all) do
				if type(rec) ~= "table" or next(rec) == nil then
					all[owner] = nil   -- (nothing kept there)
				end
			end
			if next(all) == nil then
				M.db.barArtWas = nil
			end
			if saved and say then
				MelloUI:SayEditModeReload()
			end
		end
	end

	local Pass
	Pass = function()
		pending = false
		if not on then
			return
		end
		if InCombat() then
			Kit:WhenOutOfCombat(Pass, COMBAT_KEY)
			return
		end
		if EditModeOpen() then
			return   -- (its close asks again)
		end
		if ArtWanted() then
			Apply()
		else
			Restore()
		end
		say = false
	end

	local function Schedule()
		if pending or not Ids() then
			return   -- (asked already; or a client without Edit Mode's layouts: nothing to do)
		end
		pending = true
		Kit:NextFrame(PASS_KEY, Pass)
	end

	local function OnEvent()
		Schedule()
	end

	local function Listen(want)
		if want and not events then
			events = CreateFrame("Frame")
			Perf.SetScript(events, "OnEvent", OnEvent)
		end
		if not events then
			return
		end
		if want then
			pcall(events.RegisterEvent, events, "EDIT_MODE_LAYOUTS_UPDATED")
			pcall(events.RegisterUnitEvent, events, "PLAYER_SPECIALIZATION_CHANGED", "player")
		else
			events:UnregisterAllEvents()
		end
	end

	-- the module on: listening while wanted; a pass once every module is on
	-- (the start-up pass), when wanted or something is to be given back.
	-- Nothing at all on a client without Edit Mode's layouts
	function Art.Start()
		if not Ids() then
			return
		end
		Listen(ArtWanted())
		if ArtWanted() or Mine() then
			MelloUI:WhenModulesOn(Schedule)
		end
	end

	-- the module off: nothing given back (a restart switches it off and on)
	function Art.Stop()
		Listen(false)
		entered = nil
	end

	-- the player threw the switch
	function Art.Changed()
		Listen(ArtWanted() and Ids() ~= nil)
		entered = nil
		say = true
		Schedule()
	end

	-- Edit Mode opened (the active layout and the art on the screen noted) or
	-- closed (a pass)
	function Art.EditMode(entering)
		if not on then
			return
		end
		if entering then
			entered = nil
			if ArtWanted() then
				local values, preset, name, kind = ActiveBar()
				local owner = values and not preset and Owner(kind)
				if owner then
					entered = { name = name, kind = kind, owner = owner, live = LiveHidden() }
				end
			end
		elseif ArtWanted() or Mine() then
			Schedule()
		end
	end
end

--------------------------------------------------------------------------------
-- The module
--------------------------------------------------------------------------------

local function OnEditMode(entering)
	if not entering then
		ScheduleBackdrop()
	end
	Art.EditMode(entering)
end

local hooked = false
local function Hook()
	if hooked then
		return
	end
	hooked = true
	-- Edit Mode closed: the bars may have been snapped together or apart
	-- (the kit's one Edit Mode registration, the bus's 'editmode')
	MelloUI:On("editmode", OnEditMode, M)
	-- the bag bar folded or opened (Tweaks' Collapse Arrow): its backdrop
	-- round what shows
	MelloUI:On("bagbar", ScheduleBackdrop, M)
	-- the UI Scale changed, or a bar's Size in Edit Mode (user, 2026-09-24:
	-- "UI Scaling Break the UI"): the backdrops are measured from the
	-- buttons' rects ON THE SCREEN, and a new UI scale moves the bars that
	-- hang from different edges of the screen against each other without
	-- re-laying or re-sizing any bar, so none of the bars' hooks fires. Laid
	-- out again, out of combat, like any change.
	MelloUI:On("scale", ScheduleBackdrop, M)
end

-- (0.18.5) a Backdrop switch per element took over from the skin's Backdrop
-- None: a player who had a group's backdrop keeps it (Action Bar 1's, the
-- micro menu's, the bag bar's switch on), None became off. Once
-- (`backdropsMigrated`: this machine's, never in a profile). A new player
-- (no earlier login: UI Modifications' welcomeAsked and seenVersion unset)
-- starts with none. The looks are read from the skin's saved table as it is
-- (Modules/ActionBarPanel.lua's, never written here): its Action Bar Border
-- of earlier the same day, where it is still there, decides the bars'.
-- Only where the skin is the one running (until D4 the step was its own, run
-- from its OnEnable; UI Modifications sets its flag in the start-up pass,
-- before this): a player whose skin never ran saw no backdrop, so gets none
-- now either (No reskin and Everything Off stay as they were), the step done.
local MIGRATE_ON = { bars = "backdropBar1", micro = "backdropMicro", bags = "backdropBags" }
local LOOK_KEY = { bars = "barBackdrop", micro = "microBackdrop", bags = "bagBackdrop" }
local function MigrateBackdrops(db)
	if db.backdropsMigrated then
		return
	end
	db.backdropsMigrated = true
	if not MelloUI:IsModuleEnabled("ActionBarPanel") then
		return
	end
	local um = MelloUI.GetModuleDB and MelloUI:GetModuleDB("UIModifications")
	if not (type(um) == "table" and (um.welcomeAsked == true or um.seenVersion ~= nil)) then
		return
	end
	local mods = MelloUI.db and MelloUI.db.modules
	local skin = type(mods) == "table" and type(mods.ActionBarPanel) == "table" and mods.ActionBarPanel or nil
	for group, key in pairs(LOOK_KEY) do
		local look = skin and skin[key]
		local border = skin and skin.border
		if group == "bars" and border ~= nil then
			look = (border == "backdrop" and "red") or (border == "backdrop_iron" and "iron") or "none"
		end
		if look ~= "none" then
			db[MIGRATE_ON[group]] = true
		end
	end
end

function M:OnEnable(db)
	self.db = db
	on = true
	MigrateBackdrops(db)
	Count()
	Hook()
	ApplyPageArrows()
	-- (the first layout once every module is up: the skin's dressing first,
	-- so a player with the skin on never sees MelloUI's own look first)
	MelloUI:WhenModulesOn(ScheduleBackdrop)
	-- (0.25.0) Hide Bar Art: its listener, its first pass once every module is on
	Art.Start()
end

function M:OnDisable()
	on = false
	Art.Stop()
	for _, f in pairs(holders) do
		f:Hide()
	end
	if next(fits) then
		Kit:WhenOutOfCombat(RestoreFits)
	end
	ApplyPageArrows()
end

function M:OnSettingChanged(key, _, db)
	self.db = db
	if key == "hidePageArrows" then
		ApplyPageArrows()
	elseif key == "hideBarArt" then
		Art.Changed()
	elseif ELEMENT_KEY[key] then
		-- an element's backdrop switched on or off: the backdrops again
		Count()
		Layout()
	end
end

-- /abdump backdrops (Modules/ActionBarPanel.lua's /abdump): the members
-- (screen rects, switches), the holders and what each draws, the fits
function M.DumpBackdrops()
	local list, n = Members()
	local unit = Unit(list, n)
	MelloUI:Print("unit %s (Action Bar 1's button, screen px), drawer %s, %d members", tostring(unit),
		tostring(dressing and dressing.drawer or Backdrop.MODERN), n)
	for i = 1, n do
		local m = list[i]
		local r = m.rect
		MelloUI:Print("%d %s: %s  %.0f,%.0f - %.0f,%.0f  size %s  in a backdrop %s", i, m.e.name, m.on and "on" or "off",
			r[1], r[2], r[3], r[4], m.size and string.format("%.1f", m.size) or "-", tostring(inShape[m.root] == true))
	end
	for _, e in ipairs(ELEMENTS) do
		local f = holders[e.key]
		if f then
			local counts = {}
			for kind, pool in pairs(f.pools) do
				counts[#counts + 1] = kind .. " " .. pool.used
			end
			local o = f.shadeOutline
			if o then
				for kind, pool in pairs(o.pools) do
					counts[#counts + 1] = "shade " .. kind .. " " .. pool.used
				end
			end
			table.sort(counts)
			MelloUI:Print("holder of %s: shown=%s  %s", e.name, tostring(f:IsShown()), table.concat(counts, ", "))
		end
	end
	for container, fit in pairs(fits) do
		MelloUI:Print("fit %s: x%.3f on %.3f, default place %s", container:GetName() or "?", fit.k, fit.base,
			tostring(select(2, pcall(container.IsInDefaultPosition, container))))
	end
end

-- What this module keeps beside the game's frames (hard rule 1: tables of
-- ours, never keys on the frames), for the dumps, the skin and the tests:
-- read only
M.kept = { holders = holders, fits = fits, covered = covered, inShape = inShape, members = members }
