--------------------------------------------------------------------------------
-- MelloUI - Edit Layout: the Edit Mode bridge (0.15.0)
--
-- Edit Layout (Core/EditLayout.lua) is MelloUI's one place to move things
-- (U1); what the game's Edit Mode places -- the action bars, the unit frames,
-- the cast bar, the buffs and every other Edit Mode system -- stays the
-- game's. This file is the way between the two (SPEC 2.14):
--   A. From Edit Layout to Edit Mode: a layer of plates (the movers' own,
--      E.NewPlate: the "game-owned" look) over every shown Edit Mode system
--      no live mover entry holds (the minimap, the chat, the objective
--      tracker and the damage meter are MelloUI's while UI Modifications is
--      on, D1; with it off they are bridged like the rest, D6). On hover a
--      plate reads "Move via Edit Mode", and a secure button of ours,
--      MelloUIEditModeOpen (a macro "/editmode"), lies over that line: the
--      player's own click opens Edit Mode -- never an insecure call to the
--      manager (D5). Edit Layout pauses for it ("editmode", the changes
--      kept) and comes back when Edit Mode closes; a right-click on that
--      line is the plate's. The right-click box has the same button, and
--      "All options >" where a MelloUI page dresses the element.
--   C. From Edit Mode to Edit Layout: a "MelloUI Edit Layout" button under
--      Edit Mode's window (ours, parented to UIParent, only anchored to the
--      manager: its bottom, or its top when the window was dragged too low
--      for it), with a second secure button, MelloUIEditModeClose
--      (a click on Edit Mode's own close button), laid over it: the player's
--      click closes Edit Mode as its close button does (the game asks first
--      when Edit Mode has unsaved changes), and Edit Layout opens once it
--      has closed.
--   (B, Edit Mode's place of the shared four for their reset, is
--   Core/EditModeLayout.lua's MelloUI:EditModeSystemAnchor.)
--   D. (0.20.2; the user, 2026-10-11: "Edit Layout should from now on be
--      able to move Unit Frames, Cast Bars, Party Frames, Raid Frames ...
--      and all action bars, pet bars, totem bars, stance etc"; the pick
--      "Edit Mode's layout"; docs/plans/edit-layout-systems.md) every Edit
--      Mode system no MelloUI mover holds is a mover of Edit Layout's own:
--      dragged on its plate, its place held by Core's store and written
--      into the active Edit Mode layout too, which the game places it from
--      after the next reload; A's "Move via Edit Mode" plate is left for a
--      system nobody can register (none read, a forbidden frame).
--
-- Taint (SPEC 5). MelloUI frames are never Edit Mode systems. Edit Mode is
-- only read: EditModeManagerFrame.registeredSystemFrames (never written,
-- never walked with the game's own functions), each system's system /
-- systemIndex and rect, the manager's CloseButton (an attribute's value).
-- No manager method is called; opening and closing Edit Mode happen only in
-- the two secure buttons, on the player's click. Everything of ours is
-- laid on UIParent by rect (the plates, both secure buttons), the visible
-- button on Edit Mode alone hangs from the manager (it is not its child and
-- nothing reads it). The secure buttons are made lazily, out of combat, have
-- no regions, take their strata and level from what they cover (level + 5),
-- and are laid, shown and hidden only out of combat. Their PreClick /
-- PostClick act on one click phase: the one the secure action runs on
-- (ActionButtonUseKeyDown: the press, else the release). Hooks only: the
-- manager's OnShow / OnHide / OnDragStop and the unsaved-changes dialog's
-- OnHide (HookScript, their bodies in pcall).
--
-- Nothing at login (WINDOW-RULES 2f): at load one bus listener ('editmode',
-- which makes the button on Edit Mode at Edit Mode's first open) and one
-- layer handed to Edit Layout (a table). The plates come from the movers'
-- pool at Edit Layout's opens; the secure buttons at their first hover. No
-- OnUpdate: the layer is laid again by Edit Layout's syncs (its open and
-- resume, 'mover', 'scale', a drop) and one frame after Edit Mode closes.
--
--   E.Bridge (MelloUI.EditLayout.Bridge): the layer ({ Sync, Hide, Dump }),
--   TEXT (its in-game strings), Label(frame) (a system's plate name),
--   Gate(system, index) -> { cvar, inverted, label } | nil (1.2.4: the
--   game's switch of a system, for its box); (2.1.0) DefaultFor(entry),
--   MarkDefault(entry, on), ClearDefaults(): Edit Mode's Reset To Default
--   Position for the box's "Default place" (section D); Moved(entry,
--   dropped, onto), AttachedTo(entry) -> name, soon | nil, Detach(entry),
--   DropAttach(entry | nil), AttachHeld(entry), AttachCount(): one game
--   element attached to another, as Edit Mode does (section D, ATTACH)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local E = MelloUI.EditLayout
if not E then
	return   -- (Edit Layout's own file did not load: nothing to bridge)
end
local Perf = MelloUI.Perf:Scope("EditLayoutBridge")
local Shared = Perf.Shared
local Safe = MelloUI.Safe
local Secret = Safe.IsSecret
local Num = Safe.Number
local Finite = Safe.Finite
local W = MelloUI.Widgets

local B = {}
E.Bridge = B

-- the in-game texts (SPEC 9)
local TEXT = {
	line = "Move via Edit Mode",
	fallback = "Set in Edit Mode (game menu)",
	tip = "Its place is set in the game's Edit Mode.",
	note = "Its place is set in the game's Edit Mode: the button below.",
	-- (0.20.2: D)
	sysNote = "Moved here, its place goes into your Edit Mode layout too; the game shows it there after a /reload.",
	sysReset = "Edit Mode's place",
	sysLater = "It goes back to Edit Mode's place after a /reload.",
	-- (2.1.0, el-14) Edit Mode's Reset To Default Position
	sysDefaultLater = "It goes to the game's default place after a /reload.",
	button = "Move via Edit Mode",
	side = "MelloUI Edit Layout",
	sideTip = "Close Edit Mode and open Edit Layout, where you move and resize MelloUI's windows and trackers, the "
		.. "game's windows, the minimap, chat and the damage meter. Edit Mode keeps the action bars, unit frames and "
		.. "the rest. If Edit Mode has unsaved changes, it asks you first.",
	afterFight = "After the fight.",
}
B.TEXT = TEXT

local MIN_SIZE = 8          -- units: a smaller system gets no plate
local SIDE_GAP = 24         -- units under Edit Mode's window: clear of the kit's rail when EditModePanel dresses it
local SIDE_MIN_W = 160
local OVER_LEVEL = 5        -- a secure button's level over what it covers
local HIGH_STRATA = { FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true }
local OWNER = "Edit Layout bridge"   -- (the bus owner; Kit:NextFrame's keys below)
local SYNC_KEY, OPEN_KEY = "Edit Layout bridge: Edit Mode closed", "Edit Layout bridge: open from Edit Mode"
local SYS_KEY = "Edit Layout bridge: systems after Edit Mode"
local REFUSED_KEY, DISARM_KEY = "Edit Layout bridge: Edit Mode refused", "Edit Layout bridge: disarm"

-- Each system's plate name, by its Enum.EditModeSystem NAME (the numbers
-- are the game's to change): a string, or a table by its systemIndex
local LABELS = {
	ActionBar = { "Action bar 1", "Action bar 2", "Action bar 3", "Action bar 4", "Action bar 5", "Action bar 6",
		"Action bar 7", "Action bar 8", [11] = "Stance bar", [12] = "Pet bar", [13] = "Possess bar" },
	UnitFrame = { "Player", "Target", "Focus", "Party", "Raid", "Boss", "Arena", "Pet" },
	CastBar = "Cast bar",
	AuraFrame = { "Buffs", "Debuffs", "External defensives" },
	Minimap = "Minimap",
	ChatFrame = "Chat",
	ObjectiveTracker = "Objective tracker",
	DamageMeter = "Damage meter",
	MicroMenu = "Micro menu",
	Bags = "Bags",
	StatusTrackingBar = { "Experience and reputation", "Experience and reputation 2" },
	ExtraAbilities = "Extra abilities",
	VehicleLeaveButton = "Vehicle exit",
	TalkingHeadFrame = "Talking head",
	DurabilityFrame = "Durability",
	LootFrame = "Loot window",
	EncounterBar = "Encounter bar",
	ArchaeologyBar = "Archaeology bar",
	CooldownViewer = { "Cooldowns: essential", "Cooldowns: utility", "Cooldowns: buff icons", "Cooldowns: buff bars" },
	HudTooltip = "Tooltip",
	TimerBars = "Timer bars",
	VehicleSeatIndicator = "Vehicle seats",
	PersonalResourceDisplay = "Personal resource display",
	EncounterEvents = "Encounter events",
	RaidWarning = "Raid warnings",
	TotemActionBar = "Totem bar",
	MainActionBarEndCap = "Action bar end caps",
	GroupFinder = "Group finder",
	LossOfControl = "Loss of control",
	SwingTimer = "Swing timer",
}

-- The MelloUI page that dresses a system (the box's "All options >"): the
-- module that owns those settings, as MelloUI:OpenConfig takes it; a table
-- by systemIndex where one index has another owner (the raid frames)
local PAGES = {
	ActionBar = "ActionBarPanel",
	UnitFrame = { "UnitFramePanel", "UnitFramePanel", "UnitFramePanel", "UnitFramePanel", "RaidFramePanel",
		"UnitFramePanel", "UnitFramePanel", "UnitFramePanel" },
	CastBar = "CastBarPanel",
	AuraFrame = "Auras",
	Minimap = "MinimapPanel",
	ChatFrame = "Chat",
	-- (the Objective tracker's options: as UI Modifications' own plate of it)
	ObjectiveTracker = "TrackerPanel",
	DamageMeter = "DamageMeterPanel",
	LootFrame = "LootPanel",
	HudTooltip = "TooltipPanel",
}

local function Report(err)
	local handler = geterrorhandler and geterrorhandler()
	if type(handler) == "function" then
		handler(err)
	end
end

local function Kit()
	return MelloUI.Kit
end

local function Movers()
	return E.Movers
end

local function InCombat()
	return InCombatLockdown() and true or false
end

-- a frame shown, read plainly (false when it cannot be read)
local function Shown(frame)
	if type(frame) ~= "table" or type(frame.IsShown) ~= "function" then
		return false
	end
	local ok, shown = pcall(frame.IsShown, frame)
	return ok and not Secret(shown) and shown and true or false
end

-- a strata read plainly, else `default`
local function StrataOf(frame, default)
	local ok, strata = pcall(frame.GetFrameStrata, frame)
	if ok and not Secret(strata) and type(strata) == "string" then
		return strata
	end
	return default
end

local function LevelOf(frame)
	local ok, level = pcall(frame.GetFrameLevel, frame)
	return ok and Num(level) or 0
end

-- UIParent's scale against the screen (1 when it cannot be read)
local function UIScale()
	local ok, us = pcall(UIParent.GetEffectiveScale, UIParent)
	us = ok and Num(us)
	return (us and us > 0) and us or 1
end

-- a frame's rect in UI units (UIParent's), nil when it cannot be read
-- plainly (the one screen-rect reader)
local function RectOf(frame)
	local l, b, r, t = Safe.ScreenRect(frame)
	if not l then
		return nil
	end
	local us = UIScale()
	return l / us, b / us, (r - l) / us, (t - b) / us
end

-- Whether the game has its /editmode slash (the macro's way in); missing,
-- a plate says where Edit Mode is instead and its click only shows the tip
local function SlashOK()
	local list = _G.SlashCmdList
	if type(list) == "table" and type(list.EDITMODE) == "function" then
		return true
	end
	local hashed = _G.hash_SlashCmdList
	if type(hashed) == "table" and type(hashed["/EDITMODE"]) == "function" then
		return true
	end
	return type(_G.SLASH_EDITMODE1) == "string"
end

-- The click phase the secure action runs on: the press while Cast Action
-- Keybinds On Key Down (ActionButtonUseKeyDown) is on, else the release. Our
-- PreClick / PostClick act on that one only (they run on both).
local function Acting(down)
	local fn = _G.GetCVarBool
	local keyDown = false
	if type(fn) == "function" then
		local ok, on = pcall(fn, "ActionButtonUseKeyDown")
		keyDown = ok and not Secret(on) and on and true or false
	end
	return (down and true or false) == keyDown
end

-- a script of ours run on a button as if the pointer had come or gone (its
-- hover look, forwarded from the secure button over it); `forwarding` keeps
-- our own hooks out of it
local forwarding = false
local function Forward(button, script)
	if type(button) ~= "table" then
		return
	end
	forwarding = true
	local run = _G.ExecuteFrameScript
	local ok, err
	if type(run) == "function" then
		ok, err = pcall(run, button, script)
	else
		local fn = button:GetScript(script)
		ok, err = true, nil
		if fn then
			ok, err = pcall(fn, button)
		end
	end
	forwarding = false
	if not ok then
		Report(err)
	end
end

--------------------------------------------------------------------------------
-- The systems read (read only: the list, their fields, their rects)
--------------------------------------------------------------------------------

local enumNames, enumOf   -- [Enum.EditModeSystem value] = its name, made at the first use (again for another table)

local function SystemName(value)
	local enum = type(Enum) == "table" and Enum.EditModeSystem or nil
	if not enumNames or enumOf ~= enum then
		enumNames, enumOf = {}, enum
		if type(enum) == "table" then
			for name, v in pairs(enum) do
				enumNames[v] = name
			end
		end
	end
	return value ~= nil and enumNames[value] or nil
end

-- (plain field reads, each in a pcall: a forbidden frame's table may refuse)
local function ReadSystem(frame)
	return frame.system, frame.systemIndex
end

local function ReadField(t, key)
	return t[key]
end

-- a system frame's system and systemIndex, plain numbers or nil
local function SystemOf(frame)
	local ok, system, index = pcall(ReadSystem, frame)
	if not ok then
		return nil, nil
	end
	return Num(system), Num(index)
end

local function ByIndex(t, index)
	if type(t) == "table" then
		return index and t[index] or nil
	end
	return t
end

function B.Label(frame)
	local system, index = SystemOf(frame)
	local label = ByIndex(LABELS[SystemName(system)], index)
	if type(label) == "string" then
		return label
	end
	local ok, name = pcall(frame.GetName, frame)
	name = ok and Safe.Text(name) or nil
	return name or "?"
end

-- the page that dresses it, when that module is there
local function PageOf(frame)
	local system, index = SystemOf(frame)
	local page = ByIndex(PAGES[SystemName(system)], index)
	if type(page) == "string" and MelloUI:GetModule(page) then
		return page
	end
	return nil
end

-- Edit Mode's list of its systems (read only), or nil
local function Systems()
	local manager = _G.EditModeManagerFrame
	if type(manager) ~= "table" then
		return nil
	end
	local ok, list = pcall(ReadField, manager, "registeredSystemFrames")
	return (ok and type(list) == "table") and list or nil
end

--------------------------------------------------------------------------------
-- A. "Move via Edit Mode": MelloUIEditModeOpen, over a plate's hover line
-- or the box's button (SPEC 2.14 A)
--------------------------------------------------------------------------------

local open        -- the secure button (made at the first hover, out of combat)
-- what it lies over now: target (a plate or the box's button), kind ("plate"
-- | "button"); clicking: a click of it under way (nothing hides it then)
local over = { target = nil, kind = nil, clicking = false }

local HideOpen   -- (below)

local function HideOpenNow()
	HideOpen()
end

HideOpen = function()
	if not open or over.clicking then
		return
	end
	if InCombat() then
		-- (a secure button is laid and hidden only out of combat)
		local K = Kit()
		if K and K.WhenOutOfCombat then
			K:WhenOutOfCombat(HideOpenNow, "Edit Layout bridge: Move via Edit Mode")
		end
		return
	end
	local t, kind = over.target, over.kind
	over.target, over.kind = nil, nil
	if open:IsShown() then
		open:Hide()
		open:ClearAllPoints()
	end
	E:TooltipHide(open)
	-- (the hover look it held given back)
	if kind == "plate" and t and t.inUse then
		t:SetLit(false)
	elseif kind == "button" and t then
		Forward(t, "OnLeave")
	end
end

-- a secure button laid over a rect (UI units) on `strata`, `level`, and
-- shown: out of combat, finite numbers only (never handed to it otherwise)
local function LayOver(o, l, b, w, h, strata, level)
	if InCombat() then
		return false
	end
	l, b, w, h = Finite(l), Finite(b), Finite(w), Finite(h)
	if not (l and b and w and h) or w <= 0 or h <= 0 then
		return false
	end
	o:ClearAllPoints()
	o:SetSize(w, h)
	o:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
	o:SetFrameStrata(strata)
	o:SetFrameLevel(level + OVER_LEVEL)
	o:Show()
	return true
end

-- the pointer on it: the hover look of what it covers forwarded (the plate
-- lit, its line kept; the box's button), and the plate's tooltip
local OpenEnter = Shared("OnEnter on MelloUIEditModeOpen", function(self)
	local t, kind = over.target, over.kind
	if kind == "plate" and t then
		t:SetLit(true)
		E:Tooltip(self, t.label, TEXT.tip)
	elseif kind == "button" and t then
		Forward(t, "OnEnter")
	end
end, "script")

local OpenLeave = Shared("OnLeave on MelloUIEditModeOpen", function()
	HideOpen()
end, "script")

-- after a click: when the game did not open Edit Mode ("cannot enter Edit
-- Mode" now), Edit Layout comes back at once
local function Refused()
	if not MelloUI.EditModeOpen() then
		E:Resume("editmode")
	end
end

-- PreClick (ours, before the secure action): Edit Layout paused for Edit
-- Mode, its changes kept, every piece hidden (this button stays for its
-- click: PostClick hides it)
local OpenPreClick = Shared("PreClick on MelloUIEditModeOpen", function(_, mouse, down)
	if mouse ~= "LeftButton" or not Acting(down) then
		return
	end
	over.clicking = true
	local ok, err = pcall(E.Suspend, E, "editmode")
	if not ok then
		Report(err)
	end
end, "script")

-- a right-click on it over a plate's line is the plate's own (its box, or
-- with Ctrl its tooltip: the plate's OnMouseUp, on the release as the plate
-- takes it); the secure action has none for that button (review,
-- 2026-09-29: the plate's most visible spot was the one that did nothing)
local function PlateRight(down)
	local plate = over.target
	if down or over.kind ~= "plate" or not (plate and plate.inUse) then
		return
	end
	local run = _G.ExecuteFrameScript
	local ok, err
	if type(run) == "function" then
		ok, err = pcall(run, plate, "OnMouseUp", "RightButton")
	else
		local fn = plate:GetScript("OnMouseUp")
		ok, err = true, nil
		if fn then
			ok, err = pcall(fn, plate, "RightButton")
		end
	end
	if not ok then
		Report(err)
	end
end

local OpenPostClick = Shared("PostClick on MelloUIEditModeOpen", function(_, mouse, down)
	if mouse == "RightButton" then
		PlateRight(down)
		return
	end
	if mouse ~= "LeftButton" or not Acting(down) then
		return
	end
	over.clicking = false
	HideOpen()
	local K = Kit()
	if K and K.NextFrame then
		K:NextFrame(REFUSED_KEY, Refused)
	end
end, "script")

local function MakeOpen()
	if open then
		return open
	end
	if InCombat() then
		return nil
	end
	open = CreateFrame("Button", "MelloUIEditModeOpen", UIParent, "SecureActionButtonTemplate")
	open:Hide()
	open:RegisterForClicks("AnyUp", "AnyDown")
	open:SetAttribute("type1", "macro")
	open:SetAttribute("macrotext1", "/editmode")
	Perf.SetScript(open, "PreClick", OpenPreClick)
	Perf.SetScript(open, "PostClick", OpenPostClick)
	Perf.SetScript(open, "OnEnter", OpenEnter)
	Perf.SetScript(open, "OnLeave", OpenLeave)
	return open
end

-- the pointer on a bridge plate: the secure button over its hover line
-- ("Move via Edit Mode", shown now: the plate is hovered)
local function PlateEnter(plate)
	if forwarding or InCombat() or not SlashOK() then
		return
	end
	local o = MakeOpen()
	if not o then
		return
	end
	local l, b, w, h = plate:LineRect()
	if not l then
		return   -- (a plate too small for its line: the box's button is the way)
	end
	if LayOver(o, l, b, w, h, StrataOf(plate, "FULLSCREEN"), LevelOf(plate.chip or plate)) then
		over.target, over.kind = plate, "plate"
	end
end

-- the pointer gone from the plate: the secure button goes too, unless the
-- pointer went onto it (it lies over the plate's line)
local function PlateLeave(plate)
	if over.target == plate and not (open and open:IsMouseOver()) then
		HideOpen()
	end
end

-- the box's "Move via Edit Mode": the secure button over it; the box closing
-- takes it away (hooked once on the box, our own frame)
local boxHooked = false
local BoxHidden = Shared("OnHide on Edit Layout's box (the bridge's secure button)", function()
	if over.kind == "button" then
		HideOpen()
	end
end, "script")

local function BoxHover(button)
	if forwarding or InCombat() or not SlashOK() then
		return
	end
	local o = MakeOpen()
	if not o then
		return
	end
	local box = button:GetParent()
	if not boxHooked and type(box) == "table" then
		boxHooked = true
		Perf.HookScript(box, "OnHide", BoxHidden)
	end
	local l, b, w, h = RectOf(button)
	if l and LayOver(o, l, b, w, h, StrataOf(button, "FULLSCREEN_DIALOG"), LevelOf(button)) then
		over.target, over.kind = button, "button"
	end
end

-- a right-click on a bridge plate: the box's bridge form
local function PlateRightClick(plate)
	local page = plate.frame and PageOf(plate.frame)
	E:OpenBox({
		title = plate.label,
		note = TEXT.note,
		plate = plate,
		button = SlashOK() and { text = TEXT.button, onHover = BoxHover } or nil,
		link = page and { page = page } or nil,
	})
end

--------------------------------------------------------------------------------
-- The layer (E:AddLayer): the plates over Edit Mode's systems
--------------------------------------------------------------------------------

local layer = {}
B.layer = layer
local plates = {}                              -- [system frame] = its plate, while it has one
local keep = {}                                -- (Sync's: the frames laid this time)
local skipped = {}                             -- the last Sync's systems with no plate: { label, why } (the dump)
local SPEC = { line = TEXT.line, tip = TEXT.tip, onEnter = PlateEnter, onLeave = PlateLeave,
	onRightClick = PlateRightClick }            -- (every bridge plate's: plate:SetBridge)

local function Skip(frame, why)
	skipped[#skipped + 1] = { B.Label(frame), why }
end

local function Drop(frame)
	local plate = plates[frame]
	plates[frame] = nil
	if plate then
		if over.target == plate then
			HideOpen()
		end
		plate:Release()
	end
end

local function DropAll()
	for frame in pairs(plates) do
		Drop(frame)
	end
end

-- (fr-18d) a system MelloUI's own stand in for (MelloUI.OwnBars: the experience / reputation bars and the bag bar --
-- their own movers and plates): the game's frame stays shown under ours, kept away, at their very rect, so a plate of
-- the game's there lay over ours and took every press (the user, 2026-11-01: "i cant move the bag bars and exp /
-- reputation bar"). Registering such a system is refused already (Others); its plate is refused here
local OWN_HELD = "MelloUI's own stand in for it"
local function OwnHolds(frame)
	local own = MelloUI.OwnBars
	if not own then
		return false
	end
	local system, index = SystemOf(frame)
	return system ~= nil and own.Holds(SystemName(system), index) and true or false
end

-- one system: why it gets no plate, else nil and its rect (UI units)
local function Look(frame)
	if type(frame) ~= "table" then
		return "not a frame"
	end
	local entry = MelloUI:MoverEntry(frame)
	if entry and MelloUI:EntryLive(entry) then
		return "moved in Edit Layout"
	end
	if OwnHolds(frame) then
		return OWN_HELD
	end
	if frame.IsForbidden then
		local ok, forbidden = pcall(frame.IsForbidden, frame)
		if not ok or Secret(forbidden) or forbidden then
			return "forbidden"
		end
	end
	if not Shown(frame) then
		return "hidden"
	end
	local l, b, w, h = RectOf(frame)
	if not l then
		return "no readable rect (secret or not laid out)"
	end
	if w < MIN_SIZE or h < MIN_SIZE then
		return "under 8 x 8"
	end
	return nil, l, b, w, h
end

function layer:Sync()
	for i = #skipped, 1, -1 do
		skipped[i] = nil
	end
	local list = Systems()
	if not list then
		DropAll()
		return
	end
	SPEC.line = SlashOK() and TEXT.line or TEXT.fallback
	for i = 1, #list do
		local frame = list[i]
		local why, l, b, w, h = Look(frame)
		-- (1.2.4) a plate the Elements list hides (its eye, a solo): none, as an element's
		if not why and not E:Shows(B.StandIn(frame)) then
			why = "hidden in the Elements list"
		end
		if why then
			Skip(frame, why)
		else
			local plate = plates[frame]
			if not plate then
				plate = E.NewPlate()
			end
			if not plate then
				Skip(frame, "no plate (the pool is full)")
			else
				plates[frame] = plate
				keep[frame] = true
				plate.frame = frame   -- (the drag's "hangs on" check, a snap candidate)
				plate:SetBridge(SPEC)
				plate:SetLabel(B.Label(frame))
				plate.dialog = HIGH_STRATA[StrataOf(frame, "")] or nil
				plate:Lay(l, b, w, h)
				plate:Show()
			end
		end
	end
	for frame in pairs(plates) do
		if not keep[frame] then
			Drop(frame)
		end
	end
	wipe(keep)
end

-- a pause or the end: every plate given back, the secure button gone (not
-- while its own click runs: that click is what paused the mode)
function layer:Hide()
	HideOpen()
	DropAll()
end

function layer:Dump(print)
	local list = Systems()
	local n = 0
	for _ in pairs(plates) do
		n = n + 1
	end
	print("Edit Mode bridge: %s systems read, %d plates, the /editmode slash %s", list and tostring(#list) or "no",
		n, SlashOK() and "there" or "missing")
	for frame, plate in pairs(plates) do
		local system, index = SystemOf(frame)
		print("  %s [system %s, %s]: plate%s", tostring(plate.label), tostring(system), tostring(index),
			plate.dialog and " dialog" or "")
	end
	for i = 1, #skipped do
		print("  %s: %s", tostring(skipped[i][1]), tostring(skipped[i][2]))
	end
end

E:AddLayer(layer)

--------------------------------------------------------------------------------
-- C. The button on Edit Mode: "MelloUI Edit Layout", MelloUIEditModeClose
-- over it (SPEC 2.14 C)
--------------------------------------------------------------------------------

local side     -- the visible button (made at Edit Mode's first open)
local close    -- its secure button (made at its first hover, out of combat)
-- armed: the player's click closed (or is closing) Edit Mode through it:
-- Edit Layout opens when Edit Mode has closed; disarmed when Edit Mode
-- stayed open (the player kept it, or chose to stay at the game's question)
local S = { armed = false, dialogHooked = false }
B.state = S

local function Manager()
	local m = _G.EditModeManagerFrame
	return type(m) == "table" and m or nil
end

-- Edit Mode's own close button (a read: the secure click's target)
local function CloseButtonOf()
	local m = Manager()
	if not m then
		return nil
	end
	local ok, button = pcall(ReadField, m, "CloseButton")
	return (ok and type(button) == "table") and button or nil
end

local function HideCloseNow()
	if not close then
		return
	end
	if InCombat() then
		return
	end
	if close:IsShown() then
		close:Hide()
		close:ClearAllPoints()
	end
end

local function HideClose()
	if close and InCombat() then
		-- (an overlay shown before the fight stays usable; hidden after it)
		local K = Kit()
		if K and K.WhenOutOfCombat then
			K:WhenOutOfCombat(HideCloseNow, "Edit Layout bridge: the button on Edit Mode")
		end
		return
	end
	HideCloseNow()
end

local CloseEnter = Shared("OnEnter on MelloUIEditModeClose", function(self)
	Forward(side, "OnEnter")
	W.ShowTooltip(self, TEXT.side, TEXT.sideTip)
end, "script")

local CloseLeave = Shared("OnLeave on MelloUIEditModeClose", function(self)
	Forward(side, "OnLeave")
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
	HideClose()
end, "script")

-- the game's question closed and Edit Mode is still open: the player chose
-- to stay
local function DialogGone()
	if S.armed and MelloUI.EditModeOpen() then
		S.armed = false
	end
end

local function AfterDialog()
	if S.armed then
		local K = Kit()
		if K and K.NextFrame then
			K:NextFrame(DISARM_KEY, DialogGone)
		end
	end
end

local DialogHidden = Shared("OnHide on Edit Mode's unsaved-changes question (the bridge)", function()
	local ok, err = pcall(AfterDialog)
	if not ok then
		Report(err)
	end
end, "script")

-- the frame after the click: Edit Mode still open with no question up (the
-- click did not close it) -> disarmed; the question up -> disarmed when it
-- closes with Edit Mode still open
local function Disarm()
	if not (S.armed and MelloUI.EditModeOpen()) then
		return
	end
	local dialog = _G.EditModeUnsavedChangesDialog
	if Shown(dialog) then
		if not S.dialogHooked and type(dialog.HookScript) == "function" then
			S.dialogHooked = true
			Perf.HookScript(dialog, "OnHide", DialogHidden)
		end
		return
	end
	S.armed = false
end

-- Armed in the PreClick of the acting phase: the secure click closes Edit
-- Mode at once (its 'editmode' false comes inside the click, before any
-- PostClick), so the arm has to be there first
local ClosePreClick = Shared("PreClick on MelloUIEditModeClose", function(_, mouse, down)
	if mouse == "LeftButton" and Acting(down) then
		S.armed = true
	end
end, "script")

local ClosePostClick = Shared("PostClick on MelloUIEditModeClose", function(_, mouse, down)
	if mouse ~= "LeftButton" or not Acting(down) then
		return
	end
	local K = Kit()
	if K and K.NextFrame then
		K:NextFrame(DISARM_KEY, Disarm)
	end
end, "script")

local function MakeClose()
	if close then
		return close
	end
	if InCombat() then
		return nil
	end
	close = CreateFrame("Button", "MelloUIEditModeClose", UIParent, "SecureActionButtonTemplate")
	close:Hide()
	close:RegisterForClicks("AnyUp", "AnyDown")
	close:SetAttribute("type1", "click")
	Perf.SetScript(close, "PreClick", ClosePreClick)
	Perf.SetScript(close, "PostClick", ClosePostClick)
	Perf.SetScript(close, "OnEnter", CloseEnter)
	Perf.SetScript(close, "OnLeave", CloseLeave)
	return close
end

-- the secure button over the visible one (out of combat): its target read
-- again each time (the attribute set here, never in a fight)
local function LayClose()
	local target = CloseButtonOf()
	if not (side and target) or InCombat() then
		return false
	end
	local o = MakeClose()
	if not o then
		return false
	end
	o:SetAttribute("clickbutton1", target)
	local l, b, w, h = RectOf(side)
	if not l then
		return false
	end
	return LayOver(o, l, b, w, h, StrataOf(side, "DIALOG"), LevelOf(side))
end

local SideEnter = Shared("OnEnter on the Edit Layout button on Edit Mode", function(self)
	if forwarding then
		return
	end
	if InCombat() then
		W.ShowTooltip(self, TEXT.side, TEXT.sideTip, TEXT.afterFight)
		return
	end
	if not LayClose() then
		W.ShowTooltip(self, TEXT.side, TEXT.sideTip)
	end
end, "script")

local SideLeave = Shared("OnLeave on the Edit Layout button on Edit Mode", function(self)
	if forwarding then
		return
	end
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
end, "script")

-- Under Edit Mode's window, or over it when the player dragged the window
-- so low that the button would leave the screen (the window is movable and
-- kept on the screen; the button is not its child, review 2026-09-29): laid
-- at each show and at the end of each drag of it (ours, not secure: in a
-- fight too). A window that cannot be read keeps it under.
local sideBelow = nil   -- (where it hangs now: nil until laid)
local function LaySide()
	local manager = Manager()
	if not (side and manager) then
		return
	end
	local _, mb = RectOf(manager)
	local h = Num(side:GetHeight()) or 0
	local below = not mb or mb - SIDE_GAP - h >= 0
	if below == sideBelow then
		return
	end
	sideBelow = below
	side:ClearAllPoints()
	if below then
		side:SetPoint("TOP", manager, "BOTTOM", 0, -SIDE_GAP)
	else
		side:SetPoint("BOTTOM", manager, "TOP", 0, SIDE_GAP)
	end
end

-- with Edit Mode's window (post-hooks on the manager, bodies in pcall)
local function SideFollow(on)
	if not side then
		return
	end
	if on then
		LaySide()
		side:Show()
	else
		side:Hide()
		HideClose()
	end
end

local ManagerShown = Shared("OnShow on Edit Mode's window (the Edit Layout button)", function()
	local ok, err = pcall(SideFollow, true)
	if not ok then
		Report(err)
	end
end, "script")

local ManagerHidden = Shared("OnHide on Edit Mode's window (the Edit Layout button)", function()
	local ok, err = pcall(SideFollow, false)
	if not ok then
		Report(err)
	end
end, "script")

local ManagerMoved = Shared("OnDragStop on Edit Mode's window (the Edit Layout button)", function()
	local ok, err = pcall(LaySide)
	if not ok then
		Report(err)
	end
end, "script")

-- made at Edit Mode's first open (never at login): parented to UIParent and
-- only anchored to the manager (its bottom, else its top: LaySide; it is not
-- the manager's child, so the manager's own layout never counts it); nothing
-- is written on the manager
local function MakeSide()
	local manager = Manager()
	if side or not manager then
		return
	end
	side = W.Button(UIParent, TEXT.side, SIDE_MIN_W, nil, { gold = true })
	side:Hide()
	local fs = side:GetFontString()
	local tw = fs and Num(fs:GetStringWidth()) or nil
	if tw then
		side:SetWidth(math.max(SIDE_MIN_W, math.ceil(tw) + 24))
	end
	side:SetFrameStrata(StrataOf(manager, "DIALOG"))
	LaySide()
	Perf.HookScript(side, "OnEnter", SideEnter)
	Perf.HookScript(side, "OnLeave", SideLeave)
	Perf.HookScript(manager, "OnShow", ManagerShown)
	Perf.HookScript(manager, "OnHide", ManagerHidden)
	Perf.HookScript(manager, "OnDragStop", ManagerMoved)
end

--------------------------------------------------------------------------------
-- D. Edit Mode's systems moved by Edit Layout (0.20.2, see the header and
-- docs/plans/edit-layout-systems.md). Registered as movers when Edit Layout
-- opens (a mover source: nothing at login) -- every system in Edit Mode's
-- list (read only) that no mover holds yet (the four of
-- Core/EditLayoutWindows.lua, live while UI Modifications is on, keep
-- theirs): key "EditMode.<system>.<index>", group "hud", `follow` (Core's
-- store holds the place and puts it back after the game lays the frame out:
-- a saved Edit Mode layout shows from the next reload only), resize false
-- (its size is Edit Mode's), its plate's name and page from LABELS / PAGES,
-- Reset: Edit Mode's saved place. Moved only through the *Base methods
-- (Core's Raw), never in a fight (Edit Layout pauses).
--   After an Edit Layout session, every EditMode.* place new or changed in
--   the store goes into the active Edit Mode layout as well
--   (MelloUI:EditModeAnchorSoon: offsets at scale 1, as Edit Mode keeps them).
--   At login (AfterLogin) a stored place Edit Mode's saved layout holds now
--   is let go (Edit Mode owns it from then on); one it does not (a preset's
--   copy refused) is registered and held.
--   While Edit Mode is open the store stands back (`when`); a frame Edit Mode
--   moved there is Edit Mode's again (its stored place forgotten when it
--   closes).
--------------------------------------------------------------------------------

local SYS_PREFIX = "EditMode."
local EMPTY = {}
local Listen   -- (below: the 'editlayout' listener, made at Edit Layout's first open -- nothing at load)
local sysOf = setmetatable({}, { __mode = "k" })   -- [entry] = { system, index }
local SYS = { snap = nil, atOpen = nil }           -- the store's EditMode.* places at an Edit Layout open; frames' points at Edit Mode's open

local function SysKey(system, index)
	return SYS_PREFIX .. tostring(system) .. "." .. tostring(index or 0)
end

local function ParseKey(key)
	if type(key) ~= "string" then
		return nil
	end
	local system, index = key:match("^EditMode%.(%-?%d+)%.(%-?%d+)$")
	system, index = tonumber(system), tonumber(index)
	if not system then
		return nil
	end
	return system, (index ~= 0) and index or nil
end

-- the store of places (Core's, UI Modifications' saved settings), or nil
local function Store()
	local db = MelloUI:GetModuleDB("UIModifications")
	local store = type(db) == "table" and db.positions
	return type(store) == "table" and store or nil
end

local function EditModeOpen()
	local ok, shown = pcall(Shown, Manager())
	return ok and shown == true
end

-- the frame of a system (Edit Mode's list), or nil
local function FrameOf(system, index)
	for _, frame in ipairs(Systems() or EMPTY) do
		local s, i = SystemOf(frame)
		if s == system and (i or nil) == (index or nil) then
			return frame
		end
	end
	return nil
end

-- a frame's own scale, plain (1 when unreadable)
local function ScaleOf(frame)
	local ok, s = pcall(frame.GetScale, frame)
	s = ok and Finite(s)
	return (s and s > 0) and s or 1
end

-- Core's place (its anchor's form: point nil = BOTTOMLEFT, relPoint nil =
-- CENTER, the offsets in the frame's units on UIParent) as Edit Mode's anchor
-- (the offsets at scale 1). Its form as stored: a place saved since 1.2.4
-- (el-12) is held from the side of the screen its frame stands in, the
-- frame's point the screen's (Core's Measure), as Edit Mode keeps a frame it
-- moved, so the layout's record follows any screen's shape; an older copy
-- (from the screen's centre) is written as it is
local function AnchorOf(pos, frame)
	local x, y = Finite(pos.x), Finite(pos.y)
	if not (x and y) then
		return nil
	end
	local s = ScaleOf(frame)
	return { point = pos.point or "BOTTOMLEFT", relativeTo = "UIParent", relativePoint = pos.relPoint or "CENTER",
		offsetX = x * s, offsetY = y * s }
end

-- Edit Mode's saved place equal to the stored one (half a unit)
local function SameAsEditMode(system, index, pos, frame)
	local p, to, rp, x, y = MelloUI:EditModeSystemAnchor(system, index)
	local want = p and AnchorOf(pos, frame)
	return want ~= nil and p == want.point and to == "UIParent" and rp == want.relativePoint
		and math.abs(x - want.offsetX) < 0.5 and math.abs(y - want.offsetY) < 0.5
end

-- (2.1.0, el-14; the user's rule: everything Edit Mode does in Edit Layout -- Edit Mode's own "Reset To Default
-- Position", EditModeSystemMixin:ResetToDefaultPosition) a system put back where the game itself puts it: the game's
-- default preset's anchor (EditModePresetLayoutManager.presetLayoutInfo, the preset C_EditMode.GetEditModeDefaultLayout
-- names; read only, plain values), no second anchor, in its default place -- so the game's containers lay it again
-- where they lay it (the boss frames, durability ... in their column; the bottom and side action bars in their
-- stacks). Picked in the box ("Default place"), it is a reset of the session (Core's LayoutSession.Reset: counted,
-- Discard undoes it), previewed at that anchor where the game lays the frame by its anchor alone; at Save the store's
-- place goes (as any reset) and the layout gets the default (MelloUI:EditModeAnchorSoon with `inDefault`), the cast
-- bar unlocked from the player frame as Edit Mode's own reset does (EditModeCastBarSystemMixin). The game shows it
-- from the next /reload.
local DEFAULT = { keys = {} }   -- [key] = true: this session's resets to the game's default place
do
	-- the bars and frames the game lays itself while in their default place (EditModeSystemMixin:ApplySystemAnchor:
	-- the managed containers; EditModeUtil's bottom and right action bars, Camelot's list): no preview of ours
	local STACKED = { "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
		"StanceBar", "PetActionBar", "PossessActionBar", "MainMenuBarVehicleLeaveButton",
		"MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }

	local function Field(t, key)
		local ok, v = pcall(ReadField, t, key)
		if not ok or Secret(v) then
			return nil
		end
		return v
	end

	-- the default preset's systems (read only), or nil
	local function PresetSystems()
		local manager = rawget(_G, "EditModePresetLayoutManager")
		local list = type(manager) == "table" and Field(manager, "presetLayoutInfo")
		if type(list) ~= "table" then
			return nil
		end
		local api = _G.C_EditMode
		local want = nil
		if type(api) == "table" and type(api.GetEditModeDefaultLayout) == "function" then
			local ok, v = pcall(api.GetEditModeDefaultLayout)
			want = ok and Num(v) or nil
		end
		local first
		for _, preset in ipairs(list) do
			if type(preset) == "table" then
				first = first or preset
				if want ~= nil and Field(preset, "layoutIndex") == want then
					return Field(preset, "systems")
				end
			end
		end
		return first and Field(first, "systems") or nil
	end

	-- the game's default anchor of a system: { point, relativeTo (a frame's name), relativePoint, offsetX, offsetY }
	-- at scale 1, or nil when it cannot be read plainly
	function DEFAULT.Anchor(system, index)
		for _, s in ipairs(PresetSystems() or EMPTY) do
			if type(s) == "table" and Field(s, "system") == system and (Field(s, "systemIndex") or nil) == (index or nil) then
				local a = Field(s, "anchorInfo")
				if type(a) ~= "table" then
					return nil
				end
				local p, to, rp = Field(a, "point"), Field(a, "relativeTo"), Field(a, "relativePoint")
				local x, y = Finite(Field(a, "offsetX")), Finite(Field(a, "offsetY"))
				if type(p) ~= "string" or type(rp) ~= "string" or not (x and y) then
					return nil
				end
				return { point = p, relativeTo = (type(to) == "string" and to ~= "") and to or "UIParent", relativePoint = rp,
					offsetX = x, offsetY = y }
			end
		end
		return nil
	end

	-- whether the game lays this frame itself in its default place (no preview of ours: it goes there after a reload)
	function DEFAULT.SelfLaid(frame)
		local ok, managed = pcall(ReadField, frame, "isManagedFrame")
		if ok and not Secret(managed) and managed then
			return true
		end
		for _, name in ipairs(STACKED) do
			if rawget(_G, name) == frame then
				return true
			end
		end
		return false
	end
end

-- Reset's preview: the frame at Edit Mode's saved place (none readable -- a
-- preset active, a place the game's containers lay -- false: it goes back
-- with the game's next layout, the latest the next reload). (el-14) A reset to
-- the game's default place: at the default preset's anchor, where the game
-- lays the frame by its anchor alone (else false and the line)
local function SysHome(system, index)
	local key = SysKey(system, index)
	return function(frame)
		local entry = MelloUI:MoverEntry(frame)
		if DEFAULT.keys[key] then
			local a = DEFAULT.Anchor(system, index)
			if not (entry and a) or DEFAULT.SelfLaid(frame) then
				return false, TEXT.sysDefaultLater
			end
			local s = ScaleOf(frame)
			return MelloUI:PlaceEntryAt(entry, a.point, _G[a.relativeTo] or UIParent, a.relativePoint, a.offsetX / s,
				a.offsetY / s)
		end
		local p, to, rp, x, y, inDefault = MelloUI:EditModeSystemAnchor(system, index)
		if not (entry and p) or inDefault then
			return false, TEXT.sysLater
		end
		local s = ScaleOf(frame)
		return MelloUI:PlaceEntryAt(entry, p, _G[to] or UIParent, rp, x / s, y / s)
	end
end

local function SysLive()
	return not EditModeOpen()
end

local function SysNote()
	return TEXT.sysNote
end

-- systems another MelloUI mover lays (never registered here): the four of Core/EditLayoutWindows.lua (their own
-- movers and store, registered while UI Modifications is on; with it off, A's plate as before), and the game's party
-- and raid frames while Group Frames is on (its "Party Frames" / "Raid Frames" plates lay them)
local OTHERS = { Minimap = true, ChatFrame = true, ObjectiveTracker = true, DamageMeter = true }
local GROUP_INDEX = { [4] = true, [5] = true }   -- (UnitFrame: Party, Raid -- LABELS)

-- (the user, 2026-10-11: "where is the cast bar? i dont see it in Edit layout") the systems that show only at times
-- -- a cast, a target or focus, a pet, a stance, a possessed unit, totems -- get their plate at their place even while
-- hidden (Core's `placeholder`), so they can be moved whenever, as Edit Mode shows its own while it is open
local AT_TIMES = { CastBar = true, TotemActionBar = true, ActionBar = { [11] = true, [12] = true, [13] = true },
	UnitFrame = { [2] = true, [3] = true, [8] = true } }

local function AtTimes(system, index)
	local v = AT_TIMES[SystemName(system)]
	if type(v) == "table" then
		return v[index or 0] == true
	end
	return v == true
end

-- (1.2.4, el-03; the user, 2026-10-28: "The Edit Layout, still does have some elements from the Blizzard Edit Mode
-- which are not shown and cant be shown or modified in the Edit Layout") every system the game's own Edit Mode lets
-- the player show while the game hides it: its "Show" list, read at each Edit Layout open from the manager (read
-- only: EditModeManagerFrame.AccountSettings.settingsCheckButtons, each one's shouldHide -- the client's own choice
-- -- and its CVar gate, plain fields), so each client follows itself. Such a system gets its plate at its place while
-- hidden (Core's `placeholder`); AT_TIMES above is the list while the manager cannot be read. Its plate shows (the
-- Elements list's eye, its default) while the game shows the system or the player's own Edit Mode box for it is on
-- (C_EditMode.GetAccountSettings, read); AT_TIMES's systems keep showing theirs as before. The game's previews of a
-- hidden system (sample members, a loot window) are its own code on its frame (hard rule 1): the plate stands in for
-- them, named, at the system's size -- its own while hidden, else its members' (the party's, the bosses'), else a
-- stand-in. A gated one (B.Gate: its CVar, `shouldEnableCVarName`) is switched in its box (EditLayoutSettings.lua).
local HIDDEN = {}
do
	-- the game's show-list names, to its systems: { enum name, its indices (none: every index) }
	local SHOW_LIST = {
		TargetAndFocus = { "UnitFrame", 2, 3 }, PetFrame = { "UnitFrame", 8 }, PartyFrames = { "UnitFrame", 4 },
		BossFrames = { "UnitFrame", 6 }, RaidFrames = { "UnitFrame", 5 }, ArenaFrames = { "UnitFrame", 7 },
		BuffsAndDebuffs = { "AuraFrame", 1, 2 }, ExternalDefensives = { "AuraFrame", 3 }, CastBar = { "CastBar" },
		StanceBar = { "ActionBar", 11 }, PetActionBar = { "ActionBar", 12 }, PossessActionBar = { "ActionBar", 13 },
		ExtraAbilities = { "ExtraAbilities" }, EncounterBar = { "EncounterBar" }, CooldownViewer = { "CooldownViewer" },
		PersonalResourceDisplay = { "PersonalResourceDisplay" }, EncounterEvents = { "EncounterEvents" },
		DamageMeter = { "DamageMeter" }, TotemActionBar = { "TotemActionBar" }, LossOfControl = { "LossOfControl" },
		SwingTimer = { "SwingTimer" }, TalkingHeadFrame = { "TalkingHeadFrame" },
		StatusTrackingBar2 = { "StatusTrackingBar", 2 }, VehicleLeaveButton = { "VehicleLeaveButton" },
		HudTooltip = { "HudTooltip" }, DurabilityFrame = { "DurabilityFrame" }, TimerBars = { "TimerBars" },
		VehicleSeatIndicator = { "VehicleSeatIndicator" }, ArchaeologyBar = { "ArchaeologyBar" },
		LootFrame = { "LootFrame" }, RaidWarning = { "RaidWarning" }, GroupFinder = { "GroupFinder" },
	}
	local listed = nil   -- [enum name] = { [index or 0] = spec, any = spec }; nil: the manager not read
	local account = {}   -- [Enum.EditModeAccountSetting value] = its value (the player's own Edit Mode boxes)

	local function Field(t, key)
		local ok, v = pcall(ReadField, t, key)
		return ok and v or nil
	end

	-- the show-list and the account settings, read again (each Edit Layout open)
	function HIDDEN.Read()
		local manager = _G.EditModeManagerFrame
		local settings = type(manager) == "table" and Field(manager, "AccountSettings")
		local checks = type(settings) == "table" and Field(settings, "settingsCheckButtons")
		if type(checks) ~= "table" then
			listed = nil
			return
		end
		listed = {}
		local enum = type(Enum) == "table" and Enum.EditModeAccountSetting or nil
		for name, sys in pairs(SHOW_LIST) do
			local check = Field(checks, name)
			if type(check) == "table" and Field(check, "shouldHide") ~= true then
				local cvar = Field(check, "shouldEnableCVarName")
				local label = Field(check, "labelText")
				local spec = { check = name, setting = enum and enum["Show" .. name] or nil,
					cvar = type(cvar) == "string" and not Secret(cvar) and cvar or nil,
					inverted = Field(check, "shouldEnableCVarInverted") == true,
					label = type(label) == "string" and not Secret(label) and label or nil }
				local t = listed[sys[1]] or {}
				listed[sys[1]] = t
				if #sys == 1 then
					t.any = spec
				end
				for i = 2, #sys do
					t[sys[i]] = spec
				end
			end
		end
		wipe(account)
		local api = _G.C_EditMode
		local ok, list = false, nil
		if type(api) == "table" and type(api.GetAccountSettings) == "function" then
			ok, list = pcall(api.GetAccountSettings)
		end
		for _, a in ipairs(ok and type(list) == "table" and list or EMPTY) do
			if type(a) == "table" and Num(a.setting) and Num(a.value) then
				account[a.setting] = a.value
			end
		end
	end

	-- a system's entry on the client's show-list, or nil (not on it, or the list not read)
	function HIDDEN.Spec(system, index)
		local t = listed and listed[SystemName(system)]
		return t and (t[index or 0] or t.any) or nil
	end

	-- a frame's own size in UI units, plain and at least MIN_SIZE each way, else nil
	local function SizeOf(frame)
		if type(frame) ~= "table" then
			return nil
		end
		local ok, w, h = pcall(frame.GetSize, frame)
		w, h = ok and Finite(w), ok and Finite(h)
		local okS, fs = pcall(frame.GetEffectiveScale, frame)
		fs = okS and Finite(fs)
		if not (w and h and fs) or w < MIN_SIZE or h < MIN_SIZE or fs <= 0 then
			return nil
		end
		local k = fs / UIScale()
		return w * k, h * k
	end
	HIDDEN.SizeOf = SizeOf

	-- members stacked one under the other (the layout containers, laid by the game only while they show)
	local function Stack(frames, n)
		local w, h = 0, 0
		for i = 1, n do
			local fw, fh = SizeOf(frames[i] or frames[1])
			if fw then
				w, h = math.max(w, fw), h + fh
			end
		end
		if w > 0 then
			return w, h
		end
		return nil
	end
	local function Members(frame, prefix, n)
		local out = {}
		for i = 1, n do
			out[i] = Field(frame, prefix .. i)
		end
		return out
	end
	local function Globals(pattern, n)
		local out = {}
		for i = 1, n do
			out[i] = rawget(_G, pattern:format(i))
		end
		return out
	end
	local function Count(name, default)
		local n = Num(rawget(_G, name))
		return (n and n >= 1 and n <= 40) and math.floor(n) or default
	end
	-- a container's size from its members (by its enum name and index), when it has none of its own while hidden
	local MEMBERS = {
		UnitFrame = {
			[4] = function(frame) return Stack(Members(frame, "MemberFrame", 4), 4) end,
			[5] = function() return Stack({ rawget(_G, "CompactPartyFrameMember1") }, Count("MEMBERS_PER_RAID_GROUP", 5)) end,
			[6] = function() local n = Count("MAX_BOSS_FRAMES", 5) return Stack(Globals("Boss%dTargetFrame", n), n) end,
			[7] = function() return Stack({ rawget(_G, "CompactPartyFrameMember1") }, Count("MAX_ARENA_ENEMIES", 3)) end,
		},
	}
	local STAND_IN = { 200, 40 }   -- UI units: a system with no size to read (an empty bar, a cooldown viewer)

	-- the size its plate stands at while the game hides it (UI units)
	function HIDDEN.Size(frame, system, index)
		local w, h = SizeOf(frame)
		if w then
			return w, h
		end
		local kind = MEMBERS[SystemName(system)]
		local fn = kind and kind[index or 0]
		if fn then
			local ok, mw, mh = pcall(fn, frame)
			if ok and Finite(mw) and Finite(mh) then
				return mw, mh
			end
		end
		return STAND_IN[1], STAND_IN[2]
	end

	-- a frame of some size, yet smaller than a plate (an empty container the game laid a pixel or two): its plate is
	-- laid by `box` from its own anchor point at the placeholder's size (a frame of no size is Core's placeholder's)
	function HIDDEN.Tiny(frame)
		local ok, w, h = pcall(frame.GetSize, frame)
		w, h = ok and Finite(w), ok and Finite(h)
		return (w and h and w > 0 and h > 0 and (w < MIN_SIZE or h < MIN_SIZE)) and true or false
	end

	local POINT_X = { TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0, TOP = 0.5, CENTER = 0.5, BOTTOM = 0.5,
		TOPRIGHT = 1, RIGHT = 1, BOTTOMRIGHT = 1 }
	local POINT_Y = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5,
		BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0 }

	-- Core's `box` (screen px): the placeholder's size grown from the frame's own anchor point, while the frame is
	-- tiny; nil otherwise (its own rect, or Core's placeholder for a frame of no size)
	function HIDDEN.Box(entry)
		local frame, ph = entry.frame, entry.placeholder
		if type(ph) ~= "table" or not HIDDEN.Tiny(frame) then
			return nil
		end
		local l, b, r, t = Safe.ScreenRect(frame)
		if not l then
			return nil
		end
		local ok, p = pcall(frame.GetPoint, frame, 1)
		if not ok or Secret(p) or POINT_X[p] == nil then
			p = "TOPLEFT"
		end
		local us = UIScale()
		local w, h = ph[1] * us, ph[2] * us
		local ax, ay = l + POINT_X[p] * (r - l), b + POINT_Y[p] * (t - b)
		local bl, bb = ax - POINT_X[p] * w, ay - POINT_Y[p] * h
		return bl, bb, bl + w, bb + h
	end

	-- shown by the game and of a size (an empty container the game shows at no size -- the encounter bar, the timer
	-- bars, the party frame while alone -- is hidden as far as a plate goes)
	function HIDDEN.Visible(entry)
		return Shown(entry.frame) and SizeOf(entry.frame) ~= nil
	end

	-- the Elements list's default for its plate (D1): shown while the game shows it, or while the player's own Edit
	-- Mode box for it is on
	function HIDDEN.DefaultShows(entry, system, index)
		if HIDDEN.Visible(entry) then
			return true
		end
		local spec = HIDDEN.Spec(system, index)
		return spec ~= nil and spec.setting ~= nil and account[spec.setting] == 1
	end
end

-- (1.2.4, el-03) a system's CVar gate on this client, for its box's switch (EditLayoutSettings.lua): { cvar,
-- inverted, label } from the game's own show-list box, or nil
function B.Gate(system, index)
	local spec = HIDDEN.Spec(system, index)
	if not (spec and spec.cvar) then
		return nil
	end
	return spec
end

local function Others(system, index)
	local name = SystemName(system)
	if OTHERS[name] then
		return true
	end
	-- (fr-18) the experience / reputation bars and the bag bar while MelloUI's own stand in for them (MelloUI.OwnBars:
	-- their own movers and places; the game's frames kept away)
	local own = MelloUI.OwnBars
	if own and own.Holds(name, index) then
		return true
	end
	if name == "UnitFrame" and GROUP_INDEX[index or 0] then
		local gf = MelloUI:GetModule("GroupFrames")
		return gf ~= nil and gf.isEnabled and true or false
	end
	return false
end

-- (1.2.4) each system's group in Edit Layout's Elements list (Core/EditLayoutPicker.lua), by its enum name; one
-- not named here is "misc"
local CATEGORY_OF = {
	UnitFrame = "frames",
	ActionBar = "bars", ExtraAbilities = "bars", VehicleLeaveButton = "bars", StatusTrackingBar = "bars",
	TotemActionBar = "bars", MainActionBarEndCap = "bars", GamepadMainActionBar = "bars",
	CastBar = "combat", EncounterBar = "combat", AuraFrame = "combat", CooldownViewer = "combat",
	PersonalResourceDisplay = "combat", EncounterEvents = "combat", DamageMeter = "combat", LossOfControl = "combat",
	SwingTimer = "combat",
	TalkingHeadFrame = "text", RaidWarning = "text",
	Minimap = "quests", ObjectiveTracker = "quests",
	ChatFrame = "chat",
}

-- (1.2.4) a system Edit Layout bridges (no mover of its own: A's "Move via Edit Mode" plate) as the Elements list
-- reads an element: its key, group, name, and whether the game shows it; one stand-in a frame, kept
local standIns = setmetatable({}, { __mode = "k" })
function B.StandIn(frame)
	local p = standIns[frame]
	if not p then
		p = { group = "hud", bridged = true, frame = frame }
		standIns[frame] = p
	end
	local system, index = SystemOf(frame)
	p.key = system and SysKey(system, index) or nil
	p.category = system and CATEGORY_OF[SystemName(system)] or nil
	p.label = B.Label(frame)
	p.shown = Shown(frame)
	return p
end

-- every bridged system's stand-in into `out` (the Elements list): no live mover holds it, it is not forbidden, and
-- (fr-18d) MelloUI's own do not stand in for it (their own rows are theirs)
function B.StandIns(out)
	for _, frame in ipairs(Systems() or EMPTY) do
		local entry = MelloUI:MoverEntry(frame)
		local why = Look(frame)
		if not (entry and MelloUI:EntryLive(entry)) and why ~= "forbidden" and why ~= "not a frame" and why ~= OWN_HELD then
			out[#out + 1] = B.StandIn(frame)
		end
	end
	return out
end

-- (1.2.4) a MelloUI part standing in for a system the game hides for it (MelloUI's own buff rows where the game's
-- Buffs stood -- the user: "Our Custom Buffs and Debuffs in the Edit Layout cant be selected or edited"): the
-- system's plate lies over the part (its `box`, shown by its `visible`), named for it, its lock and its page the
-- part's; dragged, it moves the system, which the part hangs from. The system's own Edit Mode settings are not shown
-- for it (they are the game's hidden frame's). MelloUI:EditLayoutCover(frame, spec): spec { label, page,
-- visible = fn(entry) -> shown, box = fn(entry) -> l, b, r, t (screen px) | nil, locked = fn(entry) -> reason | nil,
-- shows = fn(entry) -> the Elements list's eye default (2.1.30; else the game's show-list's) }
local covers = setmetatable({}, { __mode = "k" })

local function ApplyCover(entry, cover)
	entry.label = cover.label or entry.label
	entry.page = cover.page or entry.page
	entry.visible = cover.visible
	entry.box = cover.box
	entry.locked = cover.locked
	entry.covered = true
end

function MelloUI:EditLayoutCover(frame, spec)
	if type(frame) ~= "table" or type(spec) ~= "table" then
		return
	end
	covers[frame] = spec
	local entry = MelloUI:MoverEntry(frame)
	if entry then
		ApplyCover(entry, spec)
	end
end

-- (1.2.4, el-03) a system's placeholder now: on the client's show-list (or AT_TIMES while it cannot be read), its
-- size (UI units) in the entry's own table, kept by Core and laid again at each Edit Layout open; shown as far as a
-- plate goes while shown and of a size (`visible`); its plate's default (D1) for the newly listed ones --
-- AT_TIMES's keep theirs shown, as the user asked for the cast bar. Also on the movers of the four
-- (EditLayoutWindows: the game's damage meter while it hides), fields of ours only, none of a cover's
local showOf = setmetatable({}, { __mode = "k" })   -- [entry] = { system, index }: the entries set up here

local function DefaultShows(entry)
	local s = showOf[entry]
	if not s then
		return false
	end
	-- (2.1.30; the user: MelloUI's own buff rows set free "should automatically have them Visible") a cover's own
	-- default (spec.shows), where it has one: its part stands in for the game's hidden system
	local cover = entry.covered and covers[entry.frame]
	if cover and type(cover.shows) == "function" then
		local ok, shows = pcall(cover.shows, entry)
		if ok and not Secret(shows) then
			return shows and true or false
		end
	end
	return HIDDEN.DefaultShows(entry, s.system, s.index)
end

local function Placeholder(entry, frame, system, index)
	local listed = HIDDEN.Spec(system, index) ~= nil
	local before = AtTimes(system, index)
	if not (listed or before) then
		if showOf[entry] then
			showOf[entry] = nil
			entry.placeholder, entry.showDefault = nil, nil
			if not entry.covered then
				entry.visible = nil
			end
		end
		return
	end
	local s = showOf[entry] or {}
	s.system, s.index = system, index
	showOf[entry] = s
	local ph = type(entry.placeholder) == "table" and entry.placeholder or {}
	ph[1], ph[2] = HIDDEN.Size(frame, system, index)
	entry.placeholder = ph
	entry.showDefault = (listed and not before) and DefaultShows or nil
	if not entry.covered then
		entry.visible = HIDDEN.Visible
	end
end

-- (el-03) a mover of the four's, set up as it registers (EditLayoutWindows loads after this file: its movers come
-- after this file's mover source has run)
function B.Placeholder(entry)
	local frame = type(entry) == "table" and entry.frame
	if type(frame) ~= "table" then
		return
	end
	local system, index = SystemOf(frame)
	if system and OTHERS[SystemName(system)] then
		Placeholder(entry, frame, system, index)
	end
end

-- (el-14) a reset saved (Core's session at Save): one to the game's default place goes into the active layout as
-- Edit Mode's own reset keeps it; any other leaves the layout's place as it is (the store's copy gone)
local Unlock   -- (below)
local function SysReset(system, index)
	local key = SysKey(system, index)
	return function()
		if not DEFAULT.keys[key] then
			return
		end
		local a = DEFAULT.Anchor(system, index)
		if a and MelloUI.EditModeAnchorSoon then
			a.inDefault = true
			MelloUI:EditModeAnchorSoon(system, index, a)
			if SystemName(system) == "CastBar" then
				Unlock(system)
			end
		end
	end
end

-- (el-14) the box's "Default place": an Edit Mode system's mover whose default anchor reads plainly
function B.DefaultFor(entry)
	local s = type(entry) == "table" and sysOf[entry] or nil
	return s ~= nil and DEFAULT.Anchor(s.system, s.index) ~= nil
end

-- (el-14) the next reset of this entry is to the game's default place (on) or Edit Mode's saved place (off)
function B.MarkDefault(entry, on)
	if type(entry) == "table" and sysOf[entry] and entry.key ~= nil then
		DEFAULT.keys[entry.key] = on and true or nil
	end
end

function B.ClearDefaults()
	wipe(DEFAULT.keys)
end

-- (2.1.0, el-14; the user's pick of 2026-10-30, "A: like Edit Mode": one of the game's elements dropped snapped
-- against another of them attaches to it, its box says "Attached to <name>" with a Detach button, and it follows the
-- other element after a /reload; MelloUI's own windows keep fixed places) Edit Mode's own attaching -- its drag's
-- snap to another system's edge (EditModeMagnetismManager) keeps the anchor on that frame, by its name, and
-- BreakFrameSnap lets go to a screen place -- through the saved layout only. A drop of an Edit Mode system's mover
-- whose snap took another Edit Mode system's edge (that plate lit), the two side by side within the bar's gap and
-- overlapping along that edge (never corner to corner), is held as an attach of the session: the anchor from the
-- side they meet on (LEFT on RIGHT, TOP on BOTTOM ...; along the edge the edges or centres lined up, else the
-- centres), its offsets from the two frames' own rects, so it names the place it was dropped at. At Save it goes
-- into the active layout on that frame (MelloUI:EditModeAnchorSoon in WriteChanged): the game lays it there, on the
-- other frame, from the next /reload (the login's Handover then lets go of the store's screen copy). A later change
-- of it keeps the attach while it still stands against that frame (fresh offsets), else lets it go; Revert, Reset,
-- Default place and Reset all drop it. Detach (the box): its place on the screen pended (EditLayout.lua) and written
-- as a screen place at Save, as Edit Mode's break does. The game's own rules: never one Edit Mode lays from a corner
-- of the screen once moved (alwaysUseTopLeftAnchor / alwaysUseTopRightAnchor: the party, raid, boss and arena
-- frames), never onto one whose snapped frames it lets go at its save (breakSnappedFramesOnSave: those and the
-- objective tracker), never onto one that hangs on it already (Edit Mode's IsFrameAnchoredToMe, with this session's
-- attaches and the saved layout's anchors), only onto a frame with a global name (the layout keeps the name).
local ATTACH = { keys = {} }   -- [key] = { entry, frame (the other one), anchor } | { entry, detach = true }
do
	local EPS_PX = 1.5   -- physical px: two edges meet within this (a drop lands on the pixel grid)
	local STEPS = 12     -- an anchor chain followed this far

	local function Field(t, key)
		local ok, v = pcall(ReadField, t, key)
		if not ok or Secret(v) then
			return nil
		end
		return v
	end

	-- a frame's global name, when that name is this very frame (the layout keeps the name)
	local function NameOf(frame)
		local ok, name = pcall(frame.GetName, frame)
		if ok and not Secret(name) and type(name) == "string" and name ~= "" and rawget(_G, name) == frame then
			return name
		end
		return nil
	end

	-- the rect Edit Layout shows for a frame (its plate's: its mover's rect, a box with it), else its own (UI units)
	local function ShownRect(frame)
		local entry = MelloUI:MoverEntry(frame)
		if entry and MelloUI.EntryRect then
			local ok, l, b, w, h = pcall(MelloUI.EntryRect, MelloUI, entry)
			if ok and Finite(l) and Finite(b) and Finite(w) and Finite(h) then
				return l, b, w, h
			end
		end
		return RectOf(frame)
	end

	-- a frame's own rect (the anchor's offsets), else the shown one
	local function OwnRect(frame)
		local l, b, w, h = RectOf(frame)
		if l then
			return l, b, w, h
		end
		return ShownRect(frame)
	end

	-- the snap's measures in UI units: two edges meet within `eps`; the bar's gap kept between snapped elements
	local function Measures()
		local ok, _, ph = pcall(GetPhysicalScreenSize)
		local okH, uh = pcall(UIParent.GetHeight, UIParent)
		local per = MelloUI.EditLayoutSnap.PerUnit(ok and Num(ph) or nil, okH and Num(uh) or nil)
		local gap = E.SnapGap and Num(E:SnapGap()) or 0
		return EPS_PX / per, math.max(0, gap) / per
	end

	-- the point a rect's parts name: x "LEFT" / "RIGHT" / "" (its centre), y "BOTTOM" / "TOP" / ""
	local function At(l, b, w, h, xp, yp)
		local x = (xp == "LEFT" and l) or (xp == "RIGHT" and l + w) or l + w / 2
		local y = (yp == "BOTTOM" and b) or (yp == "TOP" and b + h) or b + h / 2
		return x, y
	end

	local function PointOf(yp, xp)
		local p = yp .. xp
		return p ~= "" and p or "CENTER"
	end

	-- along the edge they meet on: the centres lined up, else the low or the high edges, else the centres (offset)
	local function Along(dlo, dsize, tlo, tsize, eps, low, high)
		if math.abs((dlo + dsize / 2) - (tlo + tsize / 2)) <= eps then
			return "", ""
		elseif math.abs(dlo - tlo) <= eps then
			return low, low
		elseif math.abs((dlo + dsize) - (tlo + tsize)) <= eps then
			return high, high
		end
		return "", ""
	end

	-- how rect d stands against rect t: its x and y parts, then t's; nil when it does not stand against it (side by
	-- side, the room between the facing edges within the gap, overlapping along them)
	local function Relation(dl, db, dw, dh, tl, tb, tw, th, eps, gap)
		local dr, dt, tr, tt = dl + dw, db + dh, tl + tw, tb + th
		if math.min(dt, tt) - math.max(db, tb) > eps then
			local left, right = tl - dr, dl - tr   -- (the room with d on t's left, on its right)
			local xp, txp
			if left >= -eps and left <= gap + eps then
				xp, txp = "RIGHT", "LEFT"
			elseif right >= -eps and right <= gap + eps then
				xp, txp = "LEFT", "RIGHT"
			end
			if xp then
				local yp, typ = Along(db, dh, tb, th, eps, "BOTTOM", "TOP")
				return xp, yp, txp, typ
			end
		end
		if math.min(dr, tr) - math.max(dl, tl) > eps then
			local below, above = tb - dt, db - tt
			local yp, typ
			if below >= -eps and below <= gap + eps then
				yp, typ = "TOP", "BOTTOM"
			elseif above >= -eps and above <= gap + eps then
				yp, typ = "BOTTOM", "TOP"
			end
			if yp then
				local xp, txp = Along(dl, dw, tl, tw, eps, "LEFT", "RIGHT")
				return xp, yp, txp, typ
			end
		end
		return nil
	end

	local function Hundredth(v)
		return math.floor(v * 100 + 0.5) / 100
	end

	-- the anchor of `frame` on `to` as they stand now (offsets at scale 1: UI units, as Edit Mode keeps them), or nil
	-- when it does not stand against it
	local function AnchorOn(frame, to)
		local name = NameOf(to)
		local dl, db, dw, dh = ShownRect(frame)
		local tl, tb, tw, th = ShownRect(to)
		if not (name and dl and tl) then
			return nil
		end
		local eps, gap = Measures()
		local xp, yp, txp, typ = Relation(dl, db, dw, dh, tl, tb, tw, th, eps, gap)
		if not xp then
			return nil
		end
		local fl, fb, fw, fh = OwnRect(frame)
		local ol, ob, ow, oh = OwnRect(to)
		if not (fl and ol) then
			return nil
		end
		local fx, fy = At(fl, fb, fw, fh, xp, yp)
		local ox, oy = At(ol, ob, ow, oh, txp, typ)
		return { point = PointOf(yp, xp), relativeTo = name, relativePoint = PointOf(typ, txp),
			offsetX = Hundredth(fx - ox), offsetY = Hundredth(fy - oy) }
	end

	-- a system's place as saved now: a place held to be written, else the active layout's
	local function SavedAnchor(system, index)
		if MelloUI.EditModeHeldAnchor then
			local p, to, rp, x, y, inDefault = MelloUI:EditModeHeldAnchor(system, index)
			if p then
				return p, to, rp, x, y, inDefault
			end
		end
		return MelloUI:EditModeSystemAnchor(system, index)
	end

	-- the frame a system's mover is attached to in the saved layout (none: a screen place, in the game's default
	-- place, or reset to it in this session)
	local function SavedOn(entry, s)
		if DEFAULT.keys[entry.key] then
			return nil
		end
		local p, to, _, _, _, inDefault = SavedAnchor(s.system, s.index)
		if not p or inDefault or to == "UIParent" then
			return nil
		end
		local frame = rawget(_G, to)
		return type(frame) == "table" and frame or nil
	end

	-- moved in this session (a pending place: a screen place at Save unless attached)
	local function Moved(entry)
		local LS = MelloUI.LayoutSession
		return entry ~= nil and LS ~= nil and LS.Pos ~= nil and LS.Pos(entry) ~= nil
	end

	-- the frame another hangs on after the next /reload: this session's attach (a detach, a move: none), else the
	-- saved layout's anchor (an Edit Mode system), else its live first anchor
	local function Parent(frame)
		local system, index = SystemOf(frame)
		if system then
			local rec = ATTACH.keys[SysKey(system, index)]
			if rec then
				return rec.frame
			end
			if Moved(MelloUI:MoverEntry(frame)) then
				return nil
			end
			local p, to = SavedAnchor(system, index)
			if p then
				return to ~= "UIParent" and rawget(_G, to) or nil
			end
		end
		local ok, _, rel = pcall(frame.GetPoint, frame, 1)
		if ok and type(rel) == "table" and not Secret(rel) then
			return rel
		end
		return nil
	end

	-- `frame` hangs on `on`, a few steps up
	local function HangsOn(frame, on)
		local f = frame
		for _ = 1, STEPS do
			f = Parent(f)
			if type(f) ~= "table" or f == UIParent then
				return false
			elseif f == on then
				return true
			end
		end
		return false
	end

	-- the game keeps it attached (never one it lays from a corner of the screen once moved) ...
	local function CanHang(frame)
		return not (Field(frame, "alwaysUseTopLeftAnchor") or Field(frame, "alwaysUseTopRightAnchor"))
	end

	-- ... onto an Edit Mode system with a name whose snapped frames it keeps, which Edit Mode places (a bridged one
	-- or one of these movers): never one a MelloUI mover of its own holds at a place of MelloUI's (the minimap, chat,
	-- objective tracker and damage meter while UI Modifications is on) -- MelloUI's places stay fixed
	local function CanHold(frame)
		local mover = MelloUI:MoverEntry(frame)
		return SystemOf(frame) ~= nil and NameOf(frame) ~= nil and not Field(frame, "breakSnappedFramesOnSave")
			and (mover == nil or sysOf[mover] ~= nil)
	end

	-- an Edit Mode system's mover changed in this session (EditLayoutMovers: a drop -- `onto`, the plate its snap
	-- lit, or nil -- or a nudge, a typed place, a size): attached to the frame it stands against now (a drop: the lit
	-- one; else the one it was attached to), else a screen place (one attached in the saved layout lets go at Save)
	function B.Moved(entry, dropped, onto)
		local s = type(entry) == "table" and sysOf[entry] or nil
		if not s or entry.key == nil then
			return
		end
		local key, frame = entry.key, entry.frame
		local rec, saved = ATTACH.keys[key], SavedOn(entry, s)
		local to
		if dropped then
			to = type(onto) == "table" and onto.frame or nil
		elseif rec then
			to = rec.frame
		else
			to = saved
		end
		local anchor = nil
		if type(to) == "table" and to ~= frame and CanHang(frame) and CanHold(to) and not HangsOn(to, frame) then
			anchor = AnchorOn(frame, to)
		end
		if anchor then
			ATTACH.keys[key] = { entry = entry, frame = to, anchor = anchor }
		elseif saved then
			ATTACH.keys[key] = { entry = entry, detach = true }
		else
			ATTACH.keys[key] = nil
		end
	end

	-- the box's "Attached to": the other element's name and whether it is this session's (saved with Save), or nil
	function B.AttachedTo(entry)
		local s = type(entry) == "table" and sysOf[entry] or nil
		if not s or entry.key == nil then
			return nil
		end
		local rec = ATTACH.keys[entry.key]
		local to, soon = nil, false
		if rec then
			to, soon = rec.frame, true
		elseif not Moved(entry) then
			to = SavedOn(entry, s)
		end
		if type(to) ~= "table" then
			return nil
		end
		local mover, P = MelloUI:MoverEntry(to), Movers()
		return (mover and P and P.Label(mover)) or B.Label(to), soon
	end

	-- the box's Detach (its screen place pended by EditLayout.lua): written as a screen place at Save
	function B.Detach(entry)
		local s = type(entry) == "table" and sysOf[entry] or nil
		if not s or entry.key == nil then
			return false
		end
		ATTACH.keys[entry.key] = SavedOn(entry, s) and { entry = entry, detach = true } or nil
		return true
	end

	-- this session's attach of an entry (or, with none, every one) let go: Revert, Reset, Default place, Reset all,
	-- a session discarded
	function B.DropAttach(entry)
		if entry == nil then
			wipe(ATTACH.keys)
		elseif type(entry) == "table" and entry.key ~= nil and sysOf[entry] then
			ATTACH.keys[entry.key] = nil
		end
	end

	-- an attach or detach of this session (its plate's pending mark)
	function B.AttachHeld(entry)
		return type(entry) == "table" and entry.key ~= nil and sysOf[entry] ~= nil and ATTACH.keys[entry.key] ~= nil
	end

	-- the changes the count misses: an attach or detach of an element whose place Core's session does not count
	function B.AttachCount()
		local LS, n = MelloUI.LayoutSession, 0
		for _, rec in pairs(ATTACH.keys) do
			local ok, counted = pcall(LS.Differs, rec.entry)
			if not (ok and counted) then
				n = n + 1
			end
		end
		return n
	end
end

local function RegisterSystem(frame)
	local had = MelloUI:MoverEntry(frame)
	local system, index = SystemOf(frame)
	if had then
		if system and (sysOf[had] or OTHERS[SystemName(system)]) then
			Placeholder(had, frame, system, index)
		end
		return nil
	end
	if not system or Others(system, index) then
		return nil
	end
	local listed = HIDDEN.Spec(system, index) ~= nil or AtTimes(system, index)
	local entry = MelloUI:RegisterMover(frame, frame, { key = SysKey(system, index), group = "hud", follow = true,
		resize = false, label = B.Label(frame), page = PageOf(frame), default = SysHome(system, index),
		reset = SysReset(system, index), resetLabel = TEXT.sysReset, note = SysNote, when = SysLive,
		placeholder = listed and { HIDDEN.Size(frame, system, index) } or nil,
		box = (listed and HIDDEN.Tiny(frame)) and HIDDEN.Box or nil,
		category = CATEGORY_OF[SystemName(system)] })
	if entry then
		sysOf[entry] = { system = system, index = index }
		Placeholder(entry, frame, system, index)
		if covers[frame] then
			ApplyCover(entry, covers[frame])
		end
	end
	return entry
end

-- the mover source: every system no mover holds (Edit Layout's open and resume); the session's "before" taken at
-- its open (the store's EditMode.* places), and its listener made the first time
local StoredSystems
local function RegisterSystems()
	if Listen then
		Listen()
	end
	if not SYS.snap and StoredSystems then
		SYS.snap = StoredSystems()
	end
	local okR, errR = pcall(HIDDEN.Read)   -- (el-03: the game's show-list and the player's own boxes, read again)
	if not okR then
		Report(errR)
	end
	for _, frame in ipairs(Systems() or EMPTY) do
		local ok, err = pcall(RegisterSystem, frame)
		if not ok then
			Report(err)
		end
	end
end
B.RegisterSystems = RegisterSystems

-- the store's EditMode.* places (copies)
StoredSystems = function()
	local out = {}
	for key, pos in pairs(Store() or EMPTY) do
		if ParseKey(key) and type(pos) == "table" then
			out[key] = { point = pos.point, relPoint = pos.relPoint, x = pos.x, y = pos.y }
		end
	end
	return out
end

-- the cast bar moved: Edit Mode's Lock To Player Frame off with it, and its mirror on the player frame (Cast Bar
-- Underneath; EditModeSettingDisplayInfo's mirroredSettings) -- locked, the game hangs it under the player frame
-- whatever its place says (EditModeCastBarSystemMixin:ApplySystemAnchor); Edit Mode's own drag turns it off too
Unlock = function(system)
	local E2 = type(Enum) == "table" and Enum or nil
	local cs, us = E2 and E2.EditModeCastBarSetting, E2 and E2.EditModeUnitFrameSetting
	if cs and cs.LockToPlayerFrame ~= nil then
		MelloUI:EditModeSettingsSoon(system, nil, { [cs.LockToPlayerFrame] = 0 })
	end
	local unit = E2 and E2.EditModeSystem and E2.EditModeSystem.UnitFrame
	local player = E2 and E2.EditModeUnitFrameSystemIndices and E2.EditModeUnitFrameSystemIndices.Player or 1
	if us and us.CastBarUnderneath ~= nil and unit ~= nil then
		MelloUI:EditModeSettingsSoon(unit, player, { [us.CastBarUnderneath] = 0 })
	end
end

-- after an Edit Layout session: the places new or changed since it opened,
-- into the active Edit Mode layout. (el-14) An element attached in it goes in
-- on the other frame (ATTACH's anchor), one detached as its screen place
local function WriteChanged(before)
	if not MelloUI.EditModeAnchorSoon then
		return
	end
	local function Put(system, index, anchor)
		MelloUI:EditModeAnchorSoon(system, index, anchor)
		if SystemName(system) == "CastBar" then
			Unlock(system)
		end
	end
	local done = {}
	for key, pos in pairs(StoredSystems()) do
		local was = before and before[key]
		local rec = ATTACH.keys[key]
		if rec or not (was and was.point == pos.point and was.relPoint == pos.relPoint and was.x == pos.x and was.y == pos.y) then
			local system, index = ParseKey(key)
			local frame = FrameOf(system, index)
			local anchor = frame and ((rec and rec.anchor) or AnchorOf(pos, frame))
			if anchor then
				Put(system, index, anchor)
				done[key] = true
			end
		end
	end
	-- (an attach whose element left no place in the store: Core keeps one for every drop, so none is expected)
	for key, rec in pairs(ATTACH.keys) do
		if rec.anchor and not done[key] then
			local system, index = ParseKey(key)
			Put(system, index, rec.anchor)
		end
	end
end
B.WriteChanged = WriteChanged

-- the login's handover: a place Edit Mode holds now let go, the others held
-- (1.0; the user, 2026-10-20: "on /reload my Action bars return to their default position instead of my
-- modification") a place the active custom layout holds otherwise is the layout's: Edit Layout writes its places into
-- a custom layout (WriteChanged), so one that differs was changed in Edit Mode since -- the stale copy goes and the
-- frame, if it is a mover already, goes to the layout's place. Only a preset (no saved layout to read:
-- EditModeSystemAnchor answers nil) refuses the write: there the copy is held, as before.
-- (B.handedOver[key]: what the login did with each stored place, for /mello layout places)
B.handedOver = {}
local function Handover()
	for key, pos in pairs(StoredSystems()) do
		local system, index = ParseKey(key)
		local frame = FrameOf(system, index)
		if not frame then
			B.handedOver[key] = "no frame"
		elseif MelloUI:EditModeSystemAnchor(system, index) == nil then
			B.handedOver[key] = RegisterSystem(frame) and "held (a preset or no saved place: the copy kept)"
				or "held (already a mover)"
		elseif SameAsEditMode(system, index, pos, frame) then
			MelloUI:ForgetPosition(key)
			B.handedOver[key] = "let go (Edit Mode holds it)"
		else
			MelloUI:ForgetPosition(key)
			B.handedOver[key] = "let go (the layout's own place is newer)"
			if MelloUI:MoverEntry(frame) then
				local ok, err = pcall(SysHome(system, index), frame)
				if not ok then
					Report(err)
				end
			end
		end
	end
end
B.Handover = Handover
-- (2.1.0, el-15) Edit Mode's list of its systems, read only: /mello layout check reads it too
B.Systems = Systems

-- Edit Mode opened: each held frame's point noted; closed (a frame later: its
-- exit lays them again): one Edit Mode moved is its own again
local function PointOf(frame)
	local ok, p, _, rp, x, y = pcall(frame.GetPoint, frame, 1)
	if not ok or Secret(x) or Secret(y) then
		return nil
	end
	return tostring(p) .. tostring(rp) .. string.format("%.1f %.1f", Finite(x) or 0, Finite(y) or 0)
end

-- (1.0) a system's place in the active saved layout as text (nil: none readable -- a preset active)
local function LayoutPlace(system, index)
	local p, to, rp, x, y = MelloUI:EditModeSystemAnchor(system, index)
	if not p then
		return nil
	end
	return string.format("%s %s %s %.1f %.1f", tostring(p), tostring(to), tostring(rp), Finite(x) or 0, Finite(y) or 0)
end

local function SysEditMode(entering)
	if entering then
		SYS.atOpen, SYS.layoutAtOpen = {}, {}
		for entry in pairs(sysOf) do
			if entry.key ~= nil and MelloUI:GetPosition(entry.key) then
				SYS.atOpen[entry] = PointOf(entry.frame)
			end
		end
		for key in pairs(StoredSystems()) do
			local system, index = ParseKey(key)
			SYS.layoutAtOpen[key] = LayoutPlace(system, index) or false
		end
		return
	end
	local at, layoutAt = SYS.atOpen, SYS.layoutAtOpen
	SYS.atOpen, SYS.layoutAtOpen = nil, nil
	for entry, was in pairs(at or EMPTY) do
		if PointOf(entry.frame) ~= was then
			MelloUI:ForgetPosition(entry.key)
		end
	end
	-- (1.0) a place Edit Mode's saved layout changed while it was open is Edit Mode's again: read from the layout,
	-- since the follow put-back sets the frame's own point back before the compare above (the user's bars went back)
	for key, was in pairs(layoutAt or EMPTY) do
		local system, index = ParseKey(key)
		if (LayoutPlace(system, index) or false) ~= was then
			MelloUI:ForgetPosition(key)
		end
	end
end

local function SysEditLayout(showing, state)
	if showing then
		if not SYS.snap then
			SYS.snap = StoredSystems()
		end
		return
	end
	if state == "closed" then
		local before = SYS.snap
		SYS.snap = nil
		local ok, err = pcall(WriteChanged, before)
		if not ok then
			Report(err)
		end
		-- (el-14: the session's resets to the default place and its attaches, written at its Save or dropped --
		-- EditLayout.lua lets the attaches go before this when the session was not saved)
		wipe(DEFAULT.keys)
		wipe(ATTACH.keys)
	end
end

local listening = false
Listen = function()
	if not listening then
		listening = true
		MelloUI:On("editlayout", SysEditLayout, OWNER .. ": systems")
	end
end

if MelloUI.AddMoverSource then
	MelloUI:AddMoverSource(RegisterSystems)
end
-- (1.0) after the login: asked from Core's own PLAYER_LOGIN (a post-hook on its OnEvent: Core's login pass under
-- way then, its saved settings in; no frame of the bridge's at load), never at this file's load -- AfterLogin runs at
-- once outside a login, and the store was not read yet: every place stayed "not handed over" (the user's /mello
-- layout places)
do
	local asked = false
	local function HandoverNow()
		local ok, err = pcall(Handover)
		if not ok then
			Report(err)
		end
	end
	Perf.HookScript(MelloUI, "OnEvent", function(_, event)
		if event == "PLAYER_LOGIN" and not asked then
			asked = true
			if MelloUI.AfterLogin then
				MelloUI:AfterLogin(HandoverNow)
			else
				HandoverNow()
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- E. (2.1.0, el-15) "Reload now": MelloUIEditModeReload, over a button of ours (the Layout list's Reload now)
-- The real client does not take info.activeLayout from SaveLayouts (the user's switch test, 2026-10-31: "'Classic'
-- saved as the active one", then "the game kept 'Modern (MelloUI)' active"). A layout MelloUI saved as the active one
-- waits (Core/EditModeLayout.lua: MelloUI:EditModeActivePending) and is made active right before the reload: in this
-- button's PreClick (MelloUI:EditModeActivateNow), then the game's own /reload runs from its macro -- the installer's
-- Keep's way (Core/InstallerWindow.lua, MelloUIInstallerReload): the manager's synchronous re-layout runs in a session
-- the reload ends at once, never in a live one. Like Keep's (el-08, el-10), it lies over its button for as long as
-- that button shows (laid at each of the list's lays and at the pointer's arrival), never only on a hover; made
-- lazily, laid and hidden out of combat only; the macro stops itself in a fight, where the PreClick does nothing; one
-- click phase (Acting).
--   B.ReloadSync(button)   laid over `button` while it shows (and a layout waits), else hidden
--   B.ReloadHide()
--------------------------------------------------------------------------------
local reload   -- the secure button, once made
local reloadOver = { target = nil, clicking = false }
local RELOAD_MACRO = "/stopmacro [combat]\n/reload"
local RELOAD_KEY = "Edit Layout bridge: Reload now"

local function ReloadHideNow()
	B.ReloadHide()
end

function B.ReloadHide()
	if not reload or reloadOver.clicking or not reload:IsShown() then
		return
	end
	if InCombat() then
		local K = Kit()
		if K and K.WhenOutOfCombat then
			K:WhenOutOfCombat(ReloadHideNow, RELOAD_KEY)
		end
		return
	end
	reloadOver.target = nil
	reload:Hide()
	reload:ClearAllPoints()
end

local ReloadPreClick = Shared("PreClick on MelloUIEditModeReload", function(_, mouse, down)
	if mouse ~= "LeftButton" or not Acting(down) or InCombat() then
		return
	end
	reloadOver.clicking = true
	local ok, err = pcall(MelloUI.EditModeActivateNow, MelloUI)
	if not ok then
		Report(err)
	end
end, "script")

local ReloadPostClick = Shared("PostClick on MelloUIEditModeReload", function(_, mouse, down)
	if mouse ~= "LeftButton" or not Acting(down) then
		return
	end
	reloadOver.clicking = false
end, "script")

-- the pointer on it: the hover look (and tooltip) of the button it covers
local ReloadEnter = Shared("OnEnter on MelloUIEditModeReload", function()
	Forward(reloadOver.target, "OnEnter")
end, "script")

local ReloadLeave = Shared("OnLeave on MelloUIEditModeReload", function()
	Forward(reloadOver.target, "OnLeave")
end, "script")

local function MakeReload()
	if reload then
		return reload
	end
	if InCombat() then
		return nil
	end
	reload = CreateFrame("Button", "MelloUIEditModeReload", UIParent, "SecureActionButtonTemplate")
	reload:Hide()
	reload:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
	reload:SetAttribute("type1", "macro")
	reload:SetAttribute("macrotext1", RELOAD_MACRO)
	Perf.SetScript(reload, "PreClick", ReloadPreClick)
	Perf.SetScript(reload, "PostClick", ReloadPostClick)
	Perf.SetScript(reload, "OnEnter", ReloadEnter)
	Perf.SetScript(reload, "OnLeave", ReloadLeave)
	return reload
end

function B.ReloadSync(button)
	if reloadOver.clicking or InCombat() then
		return
	end
	local wanted = MelloUI.EditModeActivePending and MelloUI:EditModeActivePending()
	local visible = type(button) == "table" and button.IsVisible and button:IsVisible()
	if not (wanted and visible) then
		B.ReloadHide()
		return
	end
	local o = MakeReload()
	if not o then
		return
	end
	local l, b, w, h = RectOf(button)
	if not l then
		return
	end
	local shown = o:IsShown()
	if LayOver(o, l, b, w, h, StrataOf(button, "FULLSCREEN_DIALOG"), LevelOf(button)) then
		reloadOver.target = button
		if not shown then
			o:Raise()
		end
	end
end

--------------------------------------------------------------------------------
-- The bus: 'editmode' (the one listener at load)
--------------------------------------------------------------------------------

-- Edit Mode closed: a click of ours opens Edit Layout (or brings it back
-- from its pause); either way the systems' rects are read again a frame
-- later (Edit Mode's exit lays them again)
local function OpenFromEditMode()
	if MelloUI.StartEditLayout then
		MelloUI:StartEditLayout("editmode")
	end
end

local function SyncAfter()
	local P = Movers()
	if P and E:IsShowing() then
		P.SyncAll()
	end
end

MelloUI:On("editmode", function(entering)
	local K = Kit()
	if not entering and K and K.NextFrame then
		K:NextFrame(SYS_KEY, function()
			SysEditMode(false)
		end)
	elseif entering then
		SysEditMode(true)
	end
	if entering then
		local ok, err = pcall(MakeSide)
		if not ok then
			Report(err)
		end
		if Shown(Manager()) then
			SideFollow(true)
		end
		return
	end
	if S.armed then
		S.armed = false
		if K and K.NextFrame then
			K:NextFrame(OPEN_KEY, OpenFromEditMode)
		end
	end
	if K and K.NextFrame then
		K:NextFrame(SYNC_KEY, SyncAfter)
	end
end, OWNER)

-- /mello layout places (1.0; the user, 2026-10-20: "on /reload my Action bars return to their default position
-- instead of my modification"): each Edit Mode place Edit Layout keeps -- the stored place, the active layout's, the
-- frame's now -- and what the login's handover did with it, into the log (/mellolog to copy). Reads only
function B.Dump()
	MelloUI:ClearLog()
	local n = 0
	for key, pos in pairs(StoredSystems()) do
		n = n + 1
		local system, index = ParseKey(key)
		local frame = FrameOf(system, index)
		local name = frame and frame.GetName and Safe.Text(frame:GetName()) or "?"
		local p, to, rp, x, y, inDefault = MelloUI:EditModeSystemAnchor(system, index)
		local entry = frame and MelloUI:MoverEntry(frame)
		MelloUI:Print("%s %s: stored %s/%s %.1f %.1f | layout %s %s/%s %s %s%s | now %s | %s, %s%s", key, name,
			tostring(pos.point), tostring(pos.relPoint), Finite(pos.x) or 0, Finite(pos.y) or 0,
			tostring(p), tostring(to), tostring(rp), tostring(Finite(x)), tostring(Finite(y)),
			inDefault and " (default)" or "", frame and tostring(PointOf(frame)) or "-",
			B.handedOver[key] or "not handed over", entry and "a mover" or "no mover",
			(frame and p) and (SameAsEditMode(system, index, pos, frame) and ", same as the layout" or ", not the layout's") or "")
	end
	MelloUI:Print("%d stored Edit Mode place(s); Edit Mode %s", n, EditModeOpen() and "open" or "closed")
	MelloUI:ShowLog("Edit Mode places")
end

-- (the media data files' load time is counted from the end of the next file,
-- Core/EditLayoutWindows.lua: the last Core file before them in MelloUI.toc
-- since onelook D2)
