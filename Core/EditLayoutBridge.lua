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
--   TEXT (its in-game strings), Label(frame) (a system's plate name)
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
	note = "Its place and size are set in the game's Edit Mode.",
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

local enumNames   -- [Enum.EditModeSystem value] = its name (made at the first use)

local function SystemName(value)
	if not enumNames then
		enumNames = {}
		local enum = type(Enum) == "table" and Enum.EditModeSystem
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

-- one system: why it gets no plate, else nil and its rect (UI units)
local function Look(frame)
	if type(frame) ~= "table" then
		return "not a frame"
	end
	local entry = MelloUI:MoverEntry(frame)
	if entry and MelloUI:EntryLive(entry) then
		return "moved in Edit Layout"
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
	local list = E:Shows("editmode") and Systems() or nil
	if not list then
		DropAll()
		return
	end
	SPEC.line = SlashOK() and TEXT.line or TEXT.fallback
	for i = 1, #list do
		local frame = list[i]
		local why, l, b, w, h = Look(frame)
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

-- the media data files load next (MelloUI.toc): their time is counted from
-- here, under one name (/melloperf load; none of them opens a scope of its own)
MelloUI.Perf:Scope("Media data files")
