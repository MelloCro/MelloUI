--------------------------------------------------------------------------------
-- MelloUI - Edit Layout (0.15.0)
--
-- ONE place to move things (the user's decisions of 2026-09-27/28: U1-U7).
-- It merges Unlock the Windows, Auto Snapping and Reset positions with the
-- way into the game's Edit Mode: every element Core's mover registry knows
-- gets a plate (Core/EditLayoutMovers.lua) to drag, wheel and right-click;
-- the game's own Edit Mode systems get a plate that opens Edit Mode (the
-- bridge, Core/EditLayoutBridge.lua, a layer of this mode). Changes wait in
-- Core's session (MelloUI.LayoutSession) until the player leaves: Save or
-- Discard. This file is the mode itself: its states, the control bar, the
-- right-click box, the keyboard and the pauses. The spec is
-- v150/editspec/SPEC.md (sections 2.1, 2.2, 2.9-2.13).
--
--   MelloUI:StartEditLayout(source)   THE entry point. source "configurator"
--       | "slash" | "editmode". Closed: the configurator hidden when it
--       shows, then Open(). Paused for the configurator: it is hidden again
--       (the mode comes back; while the installer shows, the mode waits for
--       its close). Showing and "slash": Close().
--   MelloUI:EditingLayout() -> true while the mode shows (replaces Core's,
--       which answers false before this file loads)
--   E = MelloUI.EditLayout
--   E:Open()        enter; comes back when paused only for the configurator;
--                   in combat, while Edit Mode is open or while logging in the
--                   open waits for that to end (one line says so)
--   E:Close()       leave: the bar asks Save / Discard / Keep editing when
--                   there are changes, else it closes at once
--   E:IsOpen()      a session exists (showing, paused or asking)
--   E:IsShowing()   open and not paused
--   E:Pending()     the change count (the session's)
--   E:Dump()        /mello edit dump: every entry, plate and layer to the log
--   E.TEXT          { name, desc }: the configurator button's tooltip
--   For the bridge (Core/EditLayoutBridge.lua):
--   E:AddLayer(layer)   a layer of plates of its own: layer:Sync() (lay them;
--                   at every open, resume and resync), layer:Hide() (every
--                   piece of it away: a pause or the end), layer:Dump(print)
--   E:Suspend(reason) / E:Resume(reason)   a pause by reason ("combat",
--                   "editmode", "options"); the mode shows again only when no
--                   reason is left. The pending changes are kept throughout
--   E.NewPlate()    a plate from the movers' pool (Core/EditLayoutMovers.lua)
--   E:Tooltip(owner, title, body, line[, anchor])   the mode's tooltip, shown
--                   after a short hover; E:TooltipHide(owner)
--   E:OpenBox(spec)   the right-click box for a plate that is no entry: spec
--                   = { title, note, plate, button = { text, onHover =
--                   fn(button) }, link = { text, page } }
--   E:Shows(entry)  (1.2.4) whether its plate shows: the Elements list's
--                   eyes and solo (Core/EditLayoutPicker.lua); a layer's
--                   group name ("editmode") unless a solo holds the screen
-- The states (SPEC 2.1): CLOSED; OPEN (showing: plates, the bar, the scrim
-- and the key frame); PAUSED by one or more reasons (everything hidden, the
-- session kept); ASKING (the bar is the leave prompt); a queued open. Core
-- ends a session by itself when a profile, the installer or a new store
-- replaces the layout (LayoutSession.Abandon): the onEnd handed to Begin then
-- hides everything at once and says so in one line.
-- The keyboard (SPEC 2.13): one key frame, its keyboard on only while the
-- mode shows and out of combat, every key handed on to the game but Escape
-- (the box, the confirm or prompt, the selection, then leaving; with a
-- dropdown's list open it is the game's, which closes the list) and the
-- arrows while a plate is selected (the nudge). The game menu never opens
-- from Escape while the mode shows. MelloUI's one keyboard handler (the
-- ratchet's key-propagate row holds it to this file).
-- Nothing at load (WINDOW-RULES 2f): no frame, no listener; everything is
-- made and registered at the first Open, a player's action. Everything else
-- MelloUI calls here goes through Core's API (MelloUI:EditingLayout, the
-- session, the 'editlayout' and 'mover' topics): an update adds this file,
-- and the game loads a new file only after a full restart.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("EditLayout")
local Shared = Perf.Shared
local C_Timer = Perf.C_Timer
local Safe = MelloUI.Safe
local Secret = Safe.IsSecret
local Num = Safe.Number
local W = MelloUI.Widgets

local E = {
	TEXT = {
		name = "Edit Layout",
		desc = "Move and resize the interface: MelloUI's own windows and trackers, the game's windows, the minimap, "
			.. "chat and the damage meter. Drag, wheel to resize, right-click for options. Your changes wait until you "
			.. "leave, then you choose Save or Discard. Action bars, unit frames and the rest the game places open the "
			.. "game's Edit Mode from there. Closes this window while you edit.",
	},
}
MelloUI.EditLayout = E

-- the in-game texts (SPEC 9)
local TEXT = {
	hint = "Drag to move \194\183 Wheel to resize \194\183 Right-click for options \194\183 Ctrl+right-click resets "
		.. "\194\183 Shift keeps a straight line \194\183 Arrow keys nudge the one you clicked",
	moduleOff = "UI Modifications is off: the game's windows keep the game's places, and the minimap, chat and "
		.. "trackers move in Edit Mode.",
	bridgeHidden = "Hidden elements (party frames and others) show in Edit Mode.",
	snap = "Snap", gap = "Gap", keybind = "Keybind Mode",
	resetAll = "Reset all", discard = "Discard", save = "Save", done = "Done", cancel = "Cancel",
	keep = "Keep editing",
	one = "1 unsaved change", many = "%d unsaved changes",
	confirm = "Reset every element to its standard place and size?",
	askOne = "You have 1 unsaved change.", askMany = "You have %d unsaved changes.",
	size = "Size", position = "Position", snapTo = "Snap to", reset = "Reset", options = "Design >",
	sizeOff = "Its size is set on its page.",
	sizeEditMode = "Its size is among its Edit Mode settings below.",
	paused = "Edit Layout is paused for combat. It comes back when the fight is over.",
	queuedCombat = "Edit Layout opens when the fight is over.",
	queuedEditMode = "Edit Layout opens when you close Edit Mode.",
	queuedLogin = "Edit Layout opens once you are in the world.",
	savedOne = "Edit Layout: 1 change saved.", savedMany = "Edit Layout: %d changes saved.",
	discarded = "Edit Layout: changes discarded.",
	abandoned = "Edit Layout closed: a profile or the installer changed the layout, so your unsaved changes were "
		.. "dropped.",
}

-- (1.2.4) the dock: its measures, its toggles and their texts
local DOCK = {
	logo = "Interface\\AddOns\\MelloUI\\Media\\Textures\\LogoIcon.tga",
	-- (UI units, as the sketch has them) the dock's height and its corners' radius, the crest hanging below it and
	-- its lock's badge, a round button and its glyph, a text button, a pill under the dock and the room above it, the
	-- room between round buttons
	height = 46, radius = 14, crest = 52, badge = 20, toggleSize = 32, glyph = 17, buttonH = 30, pillH = 26,
	underGap = 8, roundGap = 6, popW = 240,
	order = { "grid", "snap", "dim", "coords" },
	default = { grid = false, dim = true, coords = true, help = false },
	gridMin = 10, gridMax = 100, gridDefault = 50,
	toggle = {
		grid = { glyph = "grid", title = "Grid",
			on = "The grid shows. Click to hide it; right-click for its spacing.",
			off = "Click to show the grid (Snap to Grid follows it); right-click for its spacing." },
		snap = { glyph = "magnet", title = "Snap",
			on = "What you drag snaps to the other elements and the screen's edges and centre. Click to turn it "
				.. "off; right-click for the gap kept between snapped elements.",
			off = "Click to snap what you drag to the other elements and the screen's edges and centre." },
		dim = { glyph = "moon", title = "Dim the world",
			on = "The world is dimmed under the plates. Click to see it as it is.",
			off = "Click to dim the world under the plates." },
		coords = { glyph = "crosshair", title = "Coordinates",
			on = "The picked element's place and size show under the bar. Click to hide them.",
			off = "Click to show the picked element's place and size under the bar." },
	},
	crestTip = "Click for the Elements list: which plates show, which are locked.",
	elements = "Elements", elementsOf = "/ %d", elementsTitle = "Elements",
	elementsTip = "Every element you can move, in groups. Show or hide their plates, lock them, find one by name, "
		.. "or show one group alone.",
	keybindTip = "Bind keys to your action buttons: hover a button and press a key. Leaves Edit Layout first.",
	resetTip = "Every element back to its standard place and size (it asks first).",
	helpTitle = "How it works", helpTip = "Shows the mouse and keyboard controls under the bar.",
	exit = "Exit", saveExit = "Save & Exit",
	unsoloTitle = "Show all again", unsoloTip = "Back to the plates your Elements list shows.",
	gridSize = "Grid spacing", gapSize = "Gap between snapped elements",
	gridUnits = "%d", gapUnits = "%d px",
	coordsLine = "%s  \194\183  X %d  Y %d  \194\183  %d \195\151 %d",
}
local SNAP_FIXED = {
	{ value = "nearest", label = "Nearest element" },
	{ value = "screen", label = "Screen edges and centre" },
	{ value = "grid", label = "Grid" },
	{ value = "off", label = "No snapping" },
}

-- the mode's own pieces on FULLSCREEN_DIALOG: over the plates (FULLSCREEN,
-- and 2-9 there for elements that stand that high themselves)
local KEYS_LEVEL, CATCH_LEVEL, BOX_LEVEL, BAR_LEVEL = 1, 20, 30, 40
local PAD, GAP = 12, 10       -- the bar's inset and the room between its parts
local LINE_H = 16             -- each of the dock's lines under it
local BOX_W, BOX_ROW, BOX_LABEL = 360, 28, 80   -- the box's width (280 until 1.2.4's Edit Mode settings), a row's
                                                -- height, the controls' left
local GATE = 0.4              -- a dimmed row
local TIP_DELAY = 0.4         -- s: a hover before the tooltip
local BAR_FADE = 0.15
local SQUARE_SHADE = { shape = "shade/square" }
local UIMOD = "UIModifications"

local S = {
	open = false,       -- a session exists
	reasons = {},       -- [reason] = true: paused for it
	nReasons = 0,
	asking = false,     -- the bar is the leave prompt
	confirm = false,    -- the bar is Reset all's confirm
	queued = nil,       -- "combat" | "editmode" | "login": an open that waits
	ending = 0,         -- the count at Save (its chat line)
	quiet = false,      -- a close with nothing changed: no chat line
	first = false,      -- the first Open's set-up done
	after = nil,        -- (0.19.9) E:Close's "then": run once the session is over
}
E.state = S

local layers = {}

-- an error in a callback: to the game's error handler, and on
local function Report(err)
	local handler = geterrorhandler and geterrorhandler()
	if type(handler) == "function" then
		handler(err)
	end
end

local function Session()
	return MelloUI.LayoutSession
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

local function ConfigFrame()
	local f = _G["MelloUIConfigFrame"]
	return type(f) == "table" and f or nil
end

-- the installer's window (Core/InstallerWindow.lua; named for its Escape)
local function InstallerFrame()
	local f = _G["MelloUIInstallerFrame"]
	return type(f) == "table" and f or nil
end

-- MelloUI's own windows the mode steps aside for (the "options" pause): the
-- configurator, and the installer its Install... opens (which hides the
-- configurator as it shows)
local function ToolFrame(frame)
	return frame ~= nil and (frame == ConfigFrame() or frame == InstallerFrame())
end

local function ToolShown()
	return Shown(ConfigFrame()) or Shown(InstallerFrame())
end

--------------------------------------------------------------------------------
-- Settings: UI Modifications' autoSnap (the bar's Snap switch) and
-- snapTargets (the box's Snap to: a saved choice, written at once -- D8)
--------------------------------------------------------------------------------

local function UIModDB()
	return MelloUI.modules[UIMOD] and MelloUI:GetModuleDB(UIMOD) or nil
end

function E:SnapOn()
	local db = UIModDB()
	return not (db and db.autoSnap == false)
end

-- (0.19.9) the bar's Gap: the pixels kept between elements snapped side by
-- side (UI Modifications' snapGap, 0 - 10; 0: edge to edge, as ever)
local GAP_MAX = 10
function E:SnapGap()
	local db = UIModDB()
	local v = db and tonumber(db.snapGap) or 0
	if v ~= v or v < 0 then
		return 0
	end
	return math.min(GAP_MAX, math.floor(v + 0.5))
end

-- this element's own snap target: "screen" | "grid" | "off" | another key |
-- nil (the nearest element)
function E:SnapTarget(key)
	local db = UIModDB()
	local t = db and db.snapTargets
	if key == nil or type(t) ~= "table" then
		return nil
	end
	local v = t[key]
	return type(v) == "string" and v or nil
end

function E:SetSnapTarget(key, value)
	local db = UIModDB()
	if key == nil or not db then
		return
	end
	local t = type(db.snapTargets) == "table" and db.snapTargets or {}
	t[key] = value
	MelloUI:NotifySettingChanged(UIMOD, "snapTargets", t)
end

-- (1.2.4) whether an element's plate shows now: the Elements list's eyes and
-- solo (Core/EditLayoutPicker.lua); a layer's group name (the bridge's
-- "editmode") unless a solo holds the screen
function E:Shows(entry)
	local K = E.Picker
	return not K or K.Shows(entry)
end

--------------------------------------------------------------------------------
-- The tooltip (SPEC 2.4: after a short hover)
--------------------------------------------------------------------------------

local tip = { owner = nil, title = nil, body = nil, line = nil, anchor = nil, timer = nil }

local function TipShow()
	tip.timer = nil
	local owner = tip.owner
	if owner and owner:IsVisible() then
		W.ShowTooltip(owner, tip.title, tip.body, tip.line, tip.anchor)
	end
end

function E:Tooltip(owner, title, body, line, anchor)
	if tip.timer then
		tip.timer:Cancel()
	end
	tip.owner, tip.title, tip.body, tip.line, tip.anchor = owner, title, body, line, anchor
	tip.timer = C_Timer.NewTimer(TIP_DELAY, TipShow)
end

function E:TooltipHide(owner)
	if owner ~= nil and tip.owner ~= owner then
		return
	end
	if tip.timer then
		tip.timer:Cancel()
		tip.timer = nil
	end
	if tip.owner and GameTooltip:IsOwned(tip.owner) then
		GameTooltip:Hide()
	end
	tip.owner = nil
end

--------------------------------------------------------------------------------
-- Layers (the bridge's plates)
--------------------------------------------------------------------------------

function E:AddLayer(layer)
	if type(layer) ~= "table" then
		return
	end
	for i = 1, #layers do
		if layers[i] == layer then
			return
		end
	end
	layers[#layers + 1] = layer
end

-- every layer's `method`, each in its own pcall
function E.EachLayer(method, ...)
	for i = 1, #layers do
		local layer = layers[i]
		local fn = layer[method]
		if type(fn) == "function" then
			local ok, err = pcall(fn, layer, ...)
			if not ok then
				Report(err)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The sources: every owner registers what it has not registered yet (the
-- arrow, the Voice Over overlay, a whisper stand-in ...), at every Open and
-- Resume (Core's list: MelloUI:AddMoverSource)
--------------------------------------------------------------------------------

local function RunSources()
	local list = MelloUI.MoverSources and MelloUI:MoverSources()
	if type(list) ~= "table" then
		return
	end
	for i = 1, #list do
		local fn = list[i]
		if type(fn) == "function" then
			local ok, err = pcall(fn)
			if not ok then
				Report(err)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The dock (1.2.4; SPEC 2.10's control bar until then): the user's pick A of
-- MelloUI-BuildData/output/editlayout_dock_sketch, drawn as the sketch draws
-- it -- one slim tab hanging from the screen's top centre (its bottom
-- corners round, no top edge: W.RoundPlate), the crest in its gold ring
-- hanging below it with the lock's badge, the title, Elements (the picker,
-- Core/EditLayoutPicker.lua: the layers glyph, the plates shown in gold of
-- all), the round toggles (Grid, Snap, Dim, Coordinates: a gold ring and
-- glyph on the selected fill while on; a right-click on Grid or Snap sets the
-- grid's spacing or the gap kept), Keybind Mode, Reset all, How it works, the
-- change count, Exit and Save & Exit (filled gold). Under it, centred, the
-- pills that apply (the solo with its way back, the picked element's place)
-- and a small panel with the lines that apply (how it works, UI
-- Modifications off, the bridge's hidden elements). The row turns into Reset
-- all's confirm or the leave prompt. Never moved (a "tool" mover until 1.2.4).
--------------------------------------------------------------------------------

local bar, pop

local function Bar()
	return bar
end
E.Bar = Bar

local function TextWidth(fs)
	local get = fs.GetUnboundedStringWidth or fs.GetStringWidth
	local ok, w = pcall(get, fs)
	return ok and Num(w) or 0
end

local function BarDefault(frame)
	frame:ClearAllPoints()
	frame:SetPoint("TOP", UIParent, "TOP", 0, 0)
end

-- a button of the bar, its width from its text
local function BarButton(parent, text, onClick, gold, filled)
	local b = W.Button(parent, text, 80, nil, { onClick = onClick, gold = gold, filled = filled, height = DOCK.buttonH })
	local fs = b:GetFontString()
	b:SetWidth(math.max(72, math.ceil((fs and TextWidth(fs) or 0) + 28)))
	return b
end

local Save, Discard, Done, Ask, KeepEditing, ResetAll   -- below

local SaveClick = Shared("OnClick on Edit Layout's Save", function()
	Save()
end, "script")
local DiscardClick = Shared("OnClick on Edit Layout's Discard", function()
	Discard()
end, "script")
local DoneClick = Shared("OnClick on Edit Layout's Done", function()
	Done()
end, "script")
local KeepClick = Shared("OnClick on Edit Layout's Keep editing", function()
	KeepEditing()
end, "script")
-- (1.2.4) Save & Exit: what changed saved, or (nothing changed) a quiet close
local SaveExitClick = Shared("OnClick on Edit Layout's Save & Exit", function()
	if E:Pending() > 0 then
		Save()
	else
		Done()
	end
end, "script")
-- (0.19.9) Keybind Mode: it closes Edit Layout first (its question if anything is unsaved)
local KeybindClick = Shared("OnClick on Edit Layout's Keybind Mode", function()
	local K = MelloUI.KeybindMode
	if K then
		K:Start("editlayout")
	end
end, "script")

local LayBar   -- below

local ResetAllClick = Shared("OnClick on Edit Layout's Reset all", function()
	S.confirm = true
	LayBar()
end, "script")
local ConfirmResetClick = Shared("OnClick on Edit Layout's Reset all (confirmed)", function()
	S.confirm = false
	ResetAll()
	LayBar()
end, "script")
local CancelClick = Shared("OnClick on Edit Layout's Cancel", function()
	S.confirm = false
	LayBar()
end, "script")

local function GetSnap()
	return E:SnapOn()
end
local function SetSnap(on)
	if UIModDB() then
		MelloUI:NotifySettingChanged(UIMOD, "autoSnap", on and true or false)
	end
end
local function GetGap()
	return E:SnapGap()
end
local function SetGap(v)
	v = tonumber(v)
	if UIModDB() and v and v == v then
		MelloUI:NotifySettingChanged(UIMOD, "snapGap", math.max(0, math.min(GAP_MAX, math.floor(v + 0.5))))
	end
end

-- the dock's toggles, kept with the Elements list's choices (Picker.Prefs);
-- Snap is UI Modifications' autoSnap, as it always was
local function Toggle(name)
	if name == "snap" then
		return GetSnap()
	end
	local K = E.Picker
	local v = K and K.Prefs()[name]
	if v == nil then
		return DOCK.default[name] and true or false
	end
	return v and true or false
end

local function GridSize()
	local K = E.Picker
	local v = K and Num(K.Prefs().gridSize)
	if not v or v ~= v then
		return DOCK.gridDefault
	end
	return math.max(DOCK.gridMin, math.min(DOCK.gridMax, math.floor(v + 0.5)))
end

local function SetToggle(name, on)
	if name == "snap" then
		SetSnap(on)
		return
	end
	local K = E.Picker
	local t = K and K.EditPrefs()
	if t then
		t[name] = on and true or false
		K.SavePrefs(t)
	end
end

-- the toggles put to work: the plates' grid and the world's dim
local function ApplyToggles()
	local P = Movers()
	if P then
		P.SetGrid(Toggle("grid"), GridSize())
		P.SetDim(Toggle("dim"))
	end
end
E.ApplyToggles = ApplyToggles

-- a round button's look: its fill and ring, its glyph -- gold on the selected
-- fill while on, the hover fill under the mouse
local function RoundLook(b)
	local on, hover = b.melloOn, b.melloHover
	b.plate:Paint((hover and "hover") or (on and "selectedTab") or "raisedPanel", on and "selectedTrim" or "border")
	W.Paint(b.icon, (on and "selectedTrim") or (hover and "text") or "mutedText", "vertex")
end

-- the dock's tooltips: a toggle's line says what a click does now
local DockEnter = Shared("OnEnter on Edit Layout's dock", function(self)
	if self.plate and self.icon then
		self.melloHover = true
		RoundLook(self)
	end
	local name = self.melloToggle
	if name then
		local t = DOCK.toggle[name]
		E:Tooltip(self, t.title, Toggle(name) and t.on or t.off)
	elseif self.melloTitle then
		E:Tooltip(self, self.melloTitle, self.melloBody)
	end
end, "script")
local DockLeave = Shared("OnLeave on Edit Layout's dock", function(self)
	if self.plate and self.icon then
		self.melloHover = nil
		RoundLook(self)
	end
	E:TooltipHide(self)
end, "script")

-- Grid's spacing and Snap's gap: a small panel under the toggle
local function PopGet()
	return pop and pop.kind == "grid" and GridSize() or GetGap()
end
local function PopSet(v)
	v = Num(v)
	if not (pop and v) then
		return
	end
	if pop.kind == "grid" then
		local K = E.Picker
		local t = K and K.EditPrefs()
		if t then
			t.gridSize = math.max(DOCK.gridMin, math.min(DOCK.gridMax, math.floor(v + 0.5)))
			K.SavePrefs(t)
		end
		ApplyToggles()
	else
		SetGap(v)
	end
end
local function GridText(v)
	return string.format(DOCK.gridUnits, Num(v) or 0)
end
local function GapText(v)
	return string.format(DOCK.gapUnits, Num(v) or 0)
end

local function ClosePop()
	if pop and pop:IsShown() then
		pop:Hide()
		return true
	end
	return false
end

local function OpenPop(button, kind)
	if not pop then
		pop = CreateFrame("Frame", nil, UIParent)
		pop:Hide()
		pop:SetFrameStrata("FULLSCREEN_DIALOG")
		pop:SetFrameLevel(BAR_LEVEL + 4)
		pop:SetClampedToScreen(true)
		pop:EnableMouse(true)
		pop:SetSize(DOCK.popW, 64)
		pop.plate = W.RoundPlate(pop, { radius = 8, fill = "mainWindow", edge = "trim" })
		MelloUI.Kit:ShadeElement(pop, "windows"):Add(pop, SQUARE_SHADE)
		pop.title = W.Text(pop, "GameFontHighlight", nil, "text")
		pop.title:SetPoint("TOPLEFT", pop, "TOPLEFT", PAD, -10)
		pop.slider = W.Slider(pop, DOCK.popW - 2 * PAD, PopGet, PopSet, { min = 0, max = GAP_MAX, step = 1 })
		pop.slider:SetPoint("TOPLEFT", pop, "TOPLEFT", PAD, -32)
	end
	if pop:IsShown() and pop.kind == kind then
		pop:Hide()
		return
	end
	pop.kind = kind
	if kind == "grid" then
		pop.title:SetText(DOCK.gridSize)
		pop.slider:SetRange(DOCK.gridMin, DOCK.gridMax, 5, false, GridText)
	else
		pop.title:SetText(DOCK.gapSize)
		pop.slider:SetRange(0, GAP_MAX, 1, false, GapText)
	end
	pop.slider:Refresh()
	pop:ClearAllPoints()
	pop:SetPoint("TOP", button, "BOTTOM", 0, -12)
	pop:Show()
end

local ToggleClick = Shared("OnClick on Edit Layout's dock toggles", function(self, button)
	local name = self.melloToggle
	if button == "RightButton" then
		if name == "grid" or name == "snap" then
			OpenPop(self, name)
		end
		return
	end
	SetToggle(name, not Toggle(name))
	MelloUI:PlayUISound("tick")
	ApplyToggles()
	LayBar()
	if self:IsMouseOver() then
		local t = DOCK.toggle[name]
		W.ShowTooltip(self, t.title, Toggle(name) and t.on or t.off)
	end
end, "script")

local ElementsClick = Shared("OnClick on Edit Layout's Elements", function()
	local K = E.Picker
	if K then
		K.Toggle()
	end
end, "script")

local HelpClick = Shared("OnClick on Edit Layout's How it works", function()
	SetToggle("help", not Toggle("help"))
	MelloUI:PlayUISound("tick")
	LayBar()
end, "script")

local UnsoloClick = Shared("OnClick on Edit Layout's solo pill", function()
	local K = E.Picker
	if K then
		K.Unsolo()
	end
end, "script")

-- the bar's parts laid left to right from x; the row's width
local function Lay(parts, n, x)
	for i = 1, n do
		local p = parts[i]
		p.part:ClearAllPoints()
		p.part:SetPoint("LEFT", p.row, "LEFT", x, 0)
		x = x + p.w + (p.gap or GAP)
	end
	return x
end

local laid = {}   -- (reused: the parts of the row being laid)
local function Put(i, part, row, w, gap)
	local p = laid[i]
	if not p then
		p = {}
		laid[i] = p
	end
	p.part, p.row, p.w, p.gap = part, row, w, gap
	return i
end

-- a round button of the dock: a circle (W.RoundPlate) and its glyph
local function RoundButton(parent, glyph, title, body, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(DOCK.toggleSize, DOCK.toggleSize)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b.plate = W.RoundPlate(b, { shape = "circle" })
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(DOCK.glyph, DOCK.glyph)
	b.icon:SetPoint("CENTER")
	W.Glyph(b.icon, glyph)
	b.melloTitle, b.melloBody = title, body
	Perf.SetScript(b, "OnClick", onClick)
	Perf.SetScript(b, "OnEnter", DockEnter)
	Perf.SetScript(b, "OnLeave", DockLeave)
	RoundLook(b)
	return b
end

-- the crest: the logo's emblem in its gold ring, hanging below the dock, the
-- lock's badge on it (open: the layout is being edited); a click opens Elements
local function MakeCrest(parent)
	local c = CreateFrame("Button", nil, parent)
	c:SetSize(DOCK.crest, DOCK.crest)
	c:SetFrameLevel(parent:GetFrameLevel() + 3)
	c.plate = W.RoundPlate(c, { shape = "circle", fill = "innerPanel", edge = "trim", edgeWidth = 2 })
	c.logo = c:CreateTexture(nil, "ARTWORK")
	c.logo:SetSize(DOCK.crest - 12, DOCK.crest - 12)
	c.logo:SetPoint("CENTER")
	c.logo:SetTexture(DOCK.logo)
	local badge = CreateFrame("Frame", nil, c)
	badge:SetSize(DOCK.badge, DOCK.badge)
	badge:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 3, -2)
	badge:SetFrameLevel(c:GetFrameLevel() + 2)
	badge.plate = W.RoundPlate(badge, { shape = "circle", fill = "selectedTab", edge = "selectedTrim" })
	badge.icon = badge:CreateTexture(nil, "ARTWORK")
	badge.icon:SetSize(DOCK.badge - 8, DOCK.badge - 8)
	badge.icon:SetPoint("CENTER")
	W.Glyph(badge.icon, "padlockOpen")
	W.Paint(badge.icon, "selectedTrim", "vertex")
	c.badge = badge
	c.melloTitle, c.melloBody = E.TEXT.name, DOCK.crestTip
	Perf.SetScript(c, "OnClick", ElementsClick)
	Perf.SetScript(c, "OnEnter", DockEnter)
	Perf.SetScript(c, "OnLeave", DockLeave)
	return c
end

-- Elements: the layers glyph, its word, the plates shown in gold and of how many
local function MakeElements(row)
	local b = W.Button(row, "", 120, nil, { onClick = ElementsClick, height = DOCK.buttonH })
	b.glyph = b:CreateTexture(nil, "ARTWORK")
	b.glyph:SetSize(15, 15)
	W.Glyph(b.glyph, "layers")
	W.Paint(b.glyph, "text", "vertex")
	b.word = W.Text(b, "GameFontHighlight", DOCK.elements, "text")
	b.count = W.Text(b, "GameFontHighlight", nil, "selectedTrim")
	b.total = W.Text(b, "GameFontHighlight", nil, "mutedText")
	b.glyph:SetPoint("LEFT", b, "LEFT", 10, 0)
	b.word:SetPoint("LEFT", b.glyph, "RIGHT", 6, 0)
	b.count:SetPoint("LEFT", b.word, "RIGHT", 6, 0)
	b.total:SetPoint("LEFT", b.count, "RIGHT", 4, 0)
	b.melloTitle, b.melloBody = DOCK.elementsTitle, DOCK.elementsTip
	Perf.HookScript(b, "OnEnter", DockEnter)
	Perf.HookScript(b, "OnLeave", DockLeave)
	return b
end

-- a pill under the dock: its plate, its text (and the solo's cross)
local function MakePill(parent, onClick)
	local p = CreateFrame("Button", nil, parent)
	p:SetSize(100, DOCK.pillH)
	p.plate = W.RoundPlate(p, { shape = "pill", fill = "innerPanel", edge = "border", fillAlpha = 0.94 })
	p.text = W.Text(p, "GameFontHighlight", nil, "text")
	p.text:SetPoint("LEFT", p, "LEFT", 12, 0)
	if onClick then
		p.cross = p:CreateTexture(nil, "ARTWORK")
		p.cross:SetSize(10, 10)
		p.cross:SetPoint("RIGHT", p, "RIGHT", -10, 0)
		W.Glyph(p.cross, "cross")
		W.Paint(p.cross, "text", "vertex")
		p.melloTitle, p.melloBody = DOCK.unsoloTitle, DOCK.unsoloTip
		Perf.SetScript(p, "OnClick", onClick)
		Perf.SetScript(p, "OnEnter", DockEnter)
		Perf.SetScript(p, "OnLeave", DockLeave)
	else
		p:EnableMouse(false)
	end
	return p
end

local function MakeBar()
	bar = CreateFrame("Frame", "MelloUIEditLayoutBar", UIParent)
	bar:Hide()
	bar:SetFrameStrata("FULLSCREEN_DIALOG")
	bar:SetFrameLevel(BAR_LEVEL)
	bar:SetClampedToScreen(true)
	bar:EnableMouse(true)
	bar:SetSize(600, DOCK.height)
	-- the tab: flush with the screen's top, its bottom corners round, its
	-- edge the trim (its shade the square partner of a plain plate)
	bar.plate = W.RoundPlate(bar, { shape = "bottom", radius = DOCK.radius, fill = "mainWindow", edge = "trim" })
	local Kit = MelloUI.Kit
	Kit:ShadeElement(bar, "windows"):Add(bar, SQUARE_SHADE)
	-- the main row
	local row = CreateFrame("Frame", nil, bar)
	row:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
	row:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
	bar.row = row
	bar.crest = MakeCrest(bar)
	bar.crest:SetPoint("TOPLEFT", bar, "TOPLEFT", 8, -2)
	bar.title = W.Text(row, "GameFontNormalLarge", E.TEXT.name, "text")
	Kit:TitleFont(bar.title, true)
	bar.dividers = {}
	for i = 1, 4 do
		local d = W.Solid(row, "ARTWORK", "trim", 0.45)
		d:SetSize(1, 24)
		bar.dividers[i] = d
	end
	bar.elements = MakeElements(row)
	bar.toggles = {}
	for i, name in ipairs(DOCK.order) do
		local t = DOCK.toggle[name]
		local b = RoundButton(row, t.glyph, t.title, nil, ToggleClick)
		b.melloToggle = name
		bar.toggles[i] = b
	end
	bar.keybind = RoundButton(row, "keys", TEXT.keybind, DOCK.keybindTip, KeybindClick)
	bar.resetAll = RoundButton(row, "reset", TEXT.resetAll, DOCK.resetTip, ResetAllClick)
	bar.help = RoundButton(row, "question", DOCK.helpTitle, DOCK.helpTip, HelpClick)
	bar.count = W.Text(row, "GameFontHighlight", nil, "text")
	bar.count:SetText(string.format(TEXT.many, 99))
	bar.countW = TextWidth(bar.count)
	bar.exit = BarButton(row, DOCK.exit, DoneClick)
	bar.saveExit = BarButton(row, DOCK.saveExit, SaveExitClick, true, true)
	-- (the check before its words, the pair centred)
	local fs = bar.saveExit:GetFontString()
	bar.saveExit.check = bar.saveExit:CreateTexture(nil, "ARTWORK")
	bar.saveExit.check:SetSize(13, 13)
	W.Glyph(bar.saveExit.check, "check")
	W.Paint(bar.saveExit.check, "text", "vertex")
	if fs then
		fs:ClearAllPoints()
		fs:SetPoint("CENTER", bar.saveExit, "CENTER", 9, 0)
		bar.saveExit.check:SetPoint("RIGHT", fs, "LEFT", -6, 0)
	end
	bar.saveExit:SetWidth(bar.saveExit:GetWidth() + 18)
	-- Reset all's confirm
	local confirm = CreateFrame("Frame", nil, bar)
	confirm:SetAllPoints(row)
	confirm:Hide()
	bar.confirmRow = confirm
	bar.confirmText = W.Text(confirm, "GameFontHighlight", TEXT.confirm, "text")
	bar.confirmReset = BarButton(confirm, TEXT.resetAll, ConfirmResetClick, true, true)
	bar.confirmCancel = BarButton(confirm, TEXT.cancel, CancelClick)
	-- the leave prompt
	local prompt = CreateFrame("Frame", nil, bar)
	prompt:SetAllPoints(row)
	prompt:Hide()
	bar.promptRow = prompt
	bar.promptText = W.Text(prompt, "GameFontHighlight", nil, "text")
	bar.promptSave = BarButton(prompt, TEXT.save, SaveClick, true, true)
	bar.promptDiscard = BarButton(prompt, TEXT.discard, DiscardClick)
	bar.promptKeep = BarButton(prompt, TEXT.keep, KeepClick)
	-- under the dock: the pills (the solo with its way back, the picked
	-- element's place), then the lines on a small panel (full body size: the
	-- no-eye-strain rule)
	local under = CreateFrame("Frame", nil, bar)
	under:SetSize(1, 1)
	under:SetPoint("TOP", bar, "BOTTOM", 0, -DOCK.underGap)
	bar.under = under
	bar.solo = MakePill(under, UnsoloClick)
	bar.solo.plate:Paint(nil, "selectedTrim")
	bar.coords = MakePill(under)
	local notes = CreateFrame("Frame", nil, under)
	notes:SetSize(200, 40)
	notes.plate = W.RoundPlate(notes, { radius = 8, fill = "innerPanel", edge = "border", fillAlpha = 0.94 })
	bar.notes = notes
	bar.hints = {}
	for i = 1, 3 do
		local hint = W.Text(notes, "GameFontHighlight", nil, "text")
		hint:SetWordWrap(false)
		bar.hints[i] = hint
	end
	bar.hints[1]:SetText(TEXT.hint)
	BarDefault(bar)
end

-- the change count, the Elements count, the toggles' looks
local function RefreshBar()
	if not bar then
		return
	end
	local n = E:Pending()
	bar.count:SetShown(n > 0)
	if n > 0 then
		bar.count:SetText(n == 1 and TEXT.one or string.format(TEXT.many, n))
	end
	bar.promptText:SetText(n == 1 and TEXT.askOne or string.format(TEXT.askMany, n))
	local K = E.Picker
	if K then
		local shown, total = K.Counts()
		local b = bar.elements
		b.count:SetText(tostring(shown))
		b.total:SetText(string.format(DOCK.elementsOf, total))
		b:SetWidth(math.ceil(10 + 15 + 6 + TextWidth(b.word) + 6 + TextWidth(b.count) + 4 + TextWidth(b.total) + 14))
		W.FlatGold(b, K.IsOpen())
		local open = K.IsOpen()
		bar.crest.plate:Paint(nil, open and "selectedTrim" or "trim")
	end
	for i, name in ipairs(DOCK.order) do
		local b = bar.toggles[i]
		b.melloOn = Toggle(name)
		RoundLook(b)
	end
	bar.help.melloOn = Toggle("help")
	RoundLook(bar.help)
end

-- the picked element's place: its centre from the screen's centre, its size
local function CoordsText()
	local P = Movers()
	local entry = P and P.Selected()
	if not (entry and Toggle("coords")) then
		return nil
	end
	local x, y = P.CentreOffset(entry)
	local _, _, w, h = MelloUI:EntryRect(entry)
	if not (x and y and w and h) then
		return nil
	end
	return string.format(DOCK.coordsLine, P.Label(entry), math.floor(x + 0.5), math.floor(y + 0.5),
		math.floor(w + 0.5), math.floor(h + 0.5))
end

-- under the dock: the pills that apply side by side, centred, the lines that
-- apply on their panel under them; the whole hidden when none applies
local function LayUnder(asking, confirm)
	local K = E.Picker
	local soloText = not asking and not confirm and K and K.SoloLabel() or nil
	local coords = not asking and not confirm and CoordsText() or nil
	local under = bar.under
	local pills, width, y = 0, 0, 0
	for _, pair in ipairs({ { bar.solo, soloText, 30 }, { bar.coords, coords, 24 } }) do
		local p, text, room = pair[1], pair[2], pair[3]
		p:SetShown(text ~= nil)
		if text then
			p.text:SetText(text)
			p:SetWidth(math.ceil(12 + TextWidth(p.text) + room))
			width = width + (pills > 0 and 8 or 0) + p:GetWidth()
			pills = pills + 1
		end
	end
	local x = -width / 2
	for _, p in ipairs({ bar.solo, bar.coords }) do
		if p:IsShown() then
			p:ClearAllPoints()
			p:SetPoint("TOPLEFT", under, "TOP", x, 0)
			x = x + p:GetWidth() + 8
		end
	end
	if pills > 0 then
		y = DOCK.pillH + 6
	end
	-- the lines: how it works (the help toggle); UI Modifications off (D6);
	-- the bridge's hidden elements
	local P = Movers()
	bar.hints[2]:SetText(TEXT.moduleOff)
	bar.hints[3]:SetText(TEXT.bridgeHidden)
	local off = not MelloUI:IsModuleEnabled(UIMOD)
	local bridged = P and P.BridgeCount and P.BridgeCount() > 0
	bar.hints[1]:SetShown(Toggle("help") and not asking and not confirm)
	bar.hints[2]:SetShown(off)
	bar.hints[3]:SetShown(bridged and true or false)
	local notes = bar.notes
	local ny, nw = 8, 0
	for i = 1, 3 do
		local fs = bar.hints[i]
		if fs:IsShown() then
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", notes, "TOPLEFT", PAD, -ny)
			ny = ny + LINE_H + 2
			nw = math.max(nw, TextWidth(fs))
		end
	end
	notes:SetShown(nw > 0)
	if nw > 0 then
		notes:SetSize(math.ceil(nw + 2 * PAD), ny + 6)
		notes:ClearAllPoints()
		notes:SetPoint("TOP", under, "TOP", 0, -y)
		y = y + ny + 6
		width = math.max(width, nw + 2 * PAD)
	end
	under:SetSize(math.max(1, width), math.max(1, y))
	under:SetShown(y > 0)
end

LayBar = function()
	if not bar then
		return
	end
	RefreshBar()
	local asking, confirm = S.asking, S.confirm and not S.asking
	bar.row:SetShown(not asking and not confirm)
	bar.confirmRow:SetShown(confirm)
	bar.promptRow:SetShown(asking)
	local left = 8 + DOCK.crest + 10   -- (the crest's room)
	local width
	if asking then
		local row = bar.promptRow
		local n = Put(1, bar.promptText, row, TextWidth(bar.promptText), GAP * 2)
		n = Put(n + 1, bar.promptSave, row, bar.promptSave:GetWidth())
		n = Put(n + 1, bar.promptDiscard, row, bar.promptDiscard:GetWidth())
		n = Put(n + 1, bar.promptKeep, row, bar.promptKeep:GetWidth(), 0)
		width = Lay(laid, n, left)
	elseif confirm then
		local row = bar.confirmRow
		local n = Put(1, bar.confirmText, row, TextWidth(bar.confirmText), GAP * 2)
		n = Put(n + 1, bar.confirmReset, row, bar.confirmReset:GetWidth())
		n = Put(n + 1, bar.confirmCancel, row, bar.confirmCancel:GetWidth(), 0)
		width = Lay(laid, n, left)
	else
		local row = bar.row
		local d = bar.dividers
		local n = Put(1, bar.title, row, TextWidth(bar.title))
		n = Put(n + 1, d[1], row, 1)
		n = Put(n + 1, bar.elements, row, bar.elements:GetWidth())
		n = Put(n + 1, d[2], row, 1)
		for i = 1, #bar.toggles do
			n = Put(n + 1, bar.toggles[i], row, DOCK.toggleSize, i < #bar.toggles and DOCK.roundGap or nil)
		end
		n = Put(n + 1, d[3], row, 1)
		n = Put(n + 1, bar.keybind, row, DOCK.toggleSize, DOCK.roundGap)
		n = Put(n + 1, bar.resetAll, row, DOCK.toggleSize, DOCK.roundGap)
		n = Put(n + 1, bar.help, row, DOCK.toggleSize)
		n = Put(n + 1, d[4], row, 1)
		-- (the count in the row only while it shows; its room then the
		-- widest count's, so the buttons stay put as it counts)
		if E:Pending() > 0 then
			n = Put(n + 1, bar.count, row, bar.countW)
		end
		n = Put(n + 1, bar.exit, row, bar.exit:GetWidth(), 8)
		n = Put(n + 1, bar.saveExit, row, bar.saveExit:GetWidth(), 0)
		width = Lay(laid, n, left)
	end
	for i = 1, #laid do
		laid[i].part, laid[i].row = nil, nil
	end
	bar:SetSize(math.ceil(math.max(width + PAD, 200)), DOCK.height)
	LayUnder(asking, confirm)
	-- (the Elements list hangs under the dock and what shows under it)
	local K = E.Picker
	if K and K.Place then
		K.Place()
	end
end

-- (the Elements list's place: under the dock, under its pills and lines too)
function E.DockDepth()
	if not bar then
		return 0
	end
	local under = bar.under
	local d = Num(bar:GetHeight()) or 0
	if under:IsShown() then
		d = d + DOCK.underGap + (Num(under:GetHeight()) or 0)
	end
	return d
end

local function ShowBar()
	if not bar then
		MakeBar()
	end
	LayBar()
	-- (hidden, or still fading out from a close a moment ago: it turns back)
	if not bar:IsShown() or MelloUI.Anim:IsRunning(bar, "alpha") then
		MelloUI.Anim:FadeIn(bar, BAR_FADE)
	end
end

local function HideBar(fade)
	ClosePop()
	if not bar or not bar:IsShown() then
		return
	end
	if fade then
		MelloUI.Anim:FadeOut(bar, BAR_FADE)
	else
		MelloUI.Anim:Stop(bar, "alpha")
		bar:SetAlpha(1)
		bar:Hide()
	end
end

function E:Refresh()
	if bar and bar:IsShown() then
		LayBar()
	end
	-- (the picked element's row in the Elements list follows a pick)
	if E.Picker then
		E.Picker.MarkSelected()
	end
end

--------------------------------------------------------------------------------
-- The right-click box (SPEC 2.9): the element's size, its exact place, what
-- it snaps to, Reset and a link to its settings. One box, reused; a catcher
-- under it closes it on a click elsewhere (a right-click on another plate
-- moves it there).
--------------------------------------------------------------------------------

local box, catcher

local function BoxEntry()
	return box and box:IsShown() and box.entry or nil
end

local CloseBox   -- below

-- the size as a fraction of its standard size (the slider's value)
local function SizeGet()
	local P, entry = Movers(), box and box.entry
	return entry and P.Fraction(entry) or 1
end
local function SizeSet(v)
	local P, entry = Movers(), box and box.entry
	if entry and v then
		P.ScaleTo(entry, v)
	end
end
local function XGet()
	local P, entry = Movers(), box and box.entry
	local x = entry and P.CentreOffset(entry)
	return x or 0
end
local function YGet()
	local P, entry = Movers(), box and box.entry
	local _, y = nil, nil
	if entry then
		_, y = P.CentreOffset(entry)
	end
	return y or 0
end
-- (the axis typed only: the other keeps its place, never the whole units
-- its field shows)
local function XSet(v)
	local P, entry = Movers(), box and box.entry
	if entry then
		P.MoveCentreTo(entry, v, nil)
	end
end
local function YSet(v)
	local P, entry = Movers(), box and box.entry
	if entry then
		P.MoveCentreTo(entry, nil, v)
	end
end
-- the saved target when it is one of this open's choices; else the nearest
-- element, which is what a drag then snaps to (a window closed since, a
-- plate the filter hides)
local function SnapGet()
	local entry = box and box.entry
	local v = entry and E:SnapTarget(entry.key)
	local values = v ~= nil and box.snap and box.snap.values
	if values then
		for i = 1, #values do
			if values[i].value == v then
				return v
			end
		end
	end
	return "nearest"
end
local function SnapSet(v)
	local entry = box and box.entry
	if entry and entry.key ~= nil then
		E:SetSnapTarget(entry.key, v ~= "nearest" and v or nil)
	end
end

local BoxReset = Shared("OnClick on Edit Layout's box Reset", function()
	local entry = box and box.entry
	if entry then
		E:ResetEntry(entry)
		CloseBox()
	end
end, "script")

local LinkClick = Shared("OnClick on Edit Layout's box All options >", function(self)
	local page = self.page
	CloseBox()
	if page then
		MelloUI:OpenConfig(page)
	end
end, "script")
local LinkEnter = Shared("OnEnter on Edit Layout's box All options >", function(self)
	self.underline:Show()
end, "script")
local LinkLeave = Shared("OnLeave on Edit Layout's box All options >", function(self)
	self.underline:Hide()
end, "script")

-- the bridge's button: its secure overlay laid over it on hover (the
-- bridge's own onHover)
local BridgeEnter = Shared("OnEnter on Edit Layout's box Move via Edit Mode", function(self)
	local hover = self.melloHover
	if hover then
		local ok, err = pcall(hover, self)
		if not ok then
			Report(err)
		end
	end
end, "script")

local RowTip = Shared("OnEnter on a dimmed row of Edit Layout's box", function(self)
	if self.tipBody then
		W.ShowTooltip(self, self.tipTitle, self.tipBody)
	end
end, "script")

-- a right-click on the catcher: on another plate the box goes there, else
-- the box closes (the click is eaten either way)
local CatcherDown = Shared("OnMouseDown on Edit Layout's box catcher", function(_, button)
	local P = Movers()
	if button == "RightButton" and P then
		local plate = P.PlateAtCursor()
		if plate then
			P.RightClick(plate)
			return
		end
	end
	CloseBox()
end, "script")

local function BoxRow(parent, label)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(BOX_W, BOX_ROW)
	row.label = W.Text(row, "GameFontHighlight", label, "text")
	row.label:SetPoint("LEFT", row, "LEFT", PAD, 0)
	Perf.SetScript(row, "OnEnter", RowTip)
	Perf.SetScript(row, "OnLeave", W.TipLeave)
	return row
end

local function MakeBox()
	catcher = CreateFrame("Frame", nil, UIParent)
	catcher:Hide()
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	catcher:SetFrameLevel(CATCH_LEVEL)
	catcher:EnableMouse(true)
	Perf.SetScript(catcher, "OnMouseDown", CatcherDown)

	box = CreateFrame("Frame", "MelloUIEditLayoutBox", UIParent)
	box:Hide()
	box:SetFrameStrata("FULLSCREEN_DIALOG")
	box:SetFrameLevel(BOX_LEVEL)
	box:SetClampedToScreen(true)
	box:EnableMouse(true)
	box:SetSize(BOX_W, 200)
	W.Panel(box, { on = true })
	local Kit = MelloUI.Kit
	Kit:ShadeElement(box, "windows"):Add(box, SQUARE_SHADE)
	box.header = W.Header(box, 6, "")
	Kit:TitleFont(box.header.label, true)
	box.note = W.Text(box, "GameFontHighlight", nil, "text")
	box.note:SetWidth(BOX_W - 2 * PAD)
	box.note:SetWordWrap(true)
	-- Size
	local size = BoxRow(box, TEXT.size)
	size.slider = W.Slider(size, BOX_W - BOX_LABEL - PAD, SizeGet, SizeSet,
		{ min = 0.5, max = 2, step = 0.01, percent = true })
	size.slider:SetPoint("LEFT", size, "LEFT", BOX_LABEL, 0)
	box.size = size
	-- Position (the element's centre from the screen's centre, whole units)
	local pos = BoxRow(box, TEXT.position)
	pos.xl = W.Text(pos, "GameFontHighlight", "X", "text")
	pos.xl:SetPoint("LEFT", pos, "LEFT", BOX_LABEL, 0)
	pos.x = W.NumberBox(pos, 64, XGet, XSet, { step = 1 })
	pos.x:SetPoint("LEFT", pos.xl, "RIGHT", 6, 0)
	pos.yl = W.Text(pos, "GameFontHighlight", "Y", "text")
	pos.yl:SetPoint("LEFT", pos.x, "RIGHT", 12, 0)
	pos.y = W.NumberBox(pos, 64, YGet, YSet, { step = 1 })
	pos.y:SetPoint("LEFT", pos.yl, "RIGHT", 6, 0)
	-- Tab: X -> Y -> Size
	pos.x.melloNext, pos.y.melloNext = pos.y, size.slider.box
	box.pos = pos
	-- Snap to
	local snap = BoxRow(box, TEXT.snapTo)
	snap.dd = W.Dropdown(snap, BOX_W - BOX_LABEL - PAD, SnapGet, SnapSet, SNAP_FIXED)
	snap.dd:SetPoint("LEFT", snap, "LEFT", BOX_LABEL, 0)
	box.snap = snap
	box.rows = { size, pos, snap }
	-- Reset, and the link to its page
	box.reset = W.Button(box, TEXT.reset, 90, nil, { onClick = BoxReset })
	local link = CreateFrame("Button", nil, box)
	link:SetSize(100, 20)
	link.text = W.Text(link, "GameFontHighlight", TEXT.options, "selectedTrim")
	link.text:SetPoint("RIGHT", link, "RIGHT", 0, 0)
	link:SetWidth(math.ceil(TextWidth(link.text)) + 4)
	link.underline = W.Solid(link, "ARTWORK", "selectedTrim", 1)
	link.underline:SetHeight(1)
	link.underline:SetPoint("TOPLEFT", link.text, "BOTTOMLEFT", 0, -1)
	link.underline:SetPoint("TOPRIGHT", link.text, "BOTTOMRIGHT", 0, -1)
	link.underline:Hide()
	Perf.SetScript(link, "OnClick", LinkClick)
	Perf.SetScript(link, "OnEnter", LinkEnter)
	Perf.SetScript(link, "OnLeave", LinkLeave)
	box.link = link
	-- the bridge's button (a plate that is no entry)
	box.bridge = W.Button(box, "", 160, nil, { gold = true })
	Perf.HookScript(box.bridge, "OnEnter", BridgeEnter)
end

-- a row dimmed: its controls take no mouse, the row gives the reason
local function Dim(row, dim, why, controls)
	row:SetAlpha(dim and GATE or 1)
	row:EnableMouse(dim and true or false)
	row.tipTitle, row.tipBody = row.label:GetText(), dim and why or nil
	for i = 1, #controls do
		local c = controls[i]
		if c.EnableMouse then
			c:EnableMouse(not dim)
		end
	end
end

local dimSize, dimPos = {}, {}   -- (the controls each row dims, filled once)
local bridgeTarget = {}          -- (1.2.4: a bridge plate's system, as the Edit Mode settings read an element)

-- the box laid from the top: the header, the note, the rows shown, then
-- Reset / the bridge's button and the link
local function LayBox()
	local y = 6 + W.HEADER_HEIGHT + 2
	local note = box.note
	if note:IsShown() then
		note:ClearAllPoints()
		note:SetPoint("TOPLEFT", box, "TOPLEFT", PAD, -y)
		y = y + math.ceil(Num(note:GetStringHeight()) or 14) + 8
	end
	for i = 1, #box.rows do
		local row = box.rows[i]
		if row:IsShown() then
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y)
			y = y + BOX_ROW
		end
	end
	-- (1.2.4) an Edit Mode system's own settings (Core/EditLayoutSettings.lua): an element's, or the system a
	-- bridge plate ("Move via Edit Mode") stands over
	local ES = E.Settings
	if ES then
		local target = box.entry
		local plate = not target and box.spec and box.spec.plate
		if plate and type(plate.frame) == "table" then
			bridgeTarget.frame = plate.frame
			target = bridgeTarget
		end
		if target then
			y = ES.Lay(box, target, y, BOX_W)
		else
			ES.Hide()
		end
	end
	y = y + 8
	box.reset:ClearAllPoints()
	box.reset:SetPoint("TOPLEFT", box, "TOPLEFT", PAD, -y)
	box.bridge:ClearAllPoints()
	box.bridge:SetPoint("TOPLEFT", box, "TOPLEFT", PAD, -y)
	box.link:ClearAllPoints()
	box.link:SetPoint("TOPRIGHT", box, "TOPRIGHT", -PAD, -y - 1)
	box:SetHeight(y + 22 + 10)
end

-- beside the plate: on its right when there is room, else its left; kept on
-- the screen
local function PlaceBox(plate)
	local sw, sh = Num(UIParent:GetWidth()) or 0, Num(UIParent:GetHeight()) or 0
	local bw, bh = BOX_W, Num(box:GetHeight()) or 200
	local x, top
	if plate and plate.l then
		x = plate.l + plate.w + 8
		if x + bw > sw then
			x = plate.l - 8 - bw
		end
		top = plate.b + plate.h
	else
		local cx, cy = GetCursorPosition()
		local us = Num(UIParent:GetEffectiveScale()) or 1
		x, top = (Num(cx) or 0) / us + 12, (Num(cy) or 0) / us
	end
	x = math.max(0, math.min(x, sw - bw))
	top = math.max(bh, math.min(top, sh))
	box:ClearAllPoints()
	box:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, top)
end

-- the box made once; open on another plate, its fields let go first (a
-- half-typed number is dropped, never taken for the new element)
local function ReadyBox()
	if not box then
		MakeBox()
		dimSize[1], dimSize[2], dimSize[3] = box.size.slider, box.size.slider.Slider, box.size.slider.box
		dimPos[1], dimPos[2] = box.pos.x, box.pos.y
	elseif box:IsShown() then
		box:Hide()
	end
	E:TooltipHide()
end

local function ShowBox(plate)
	LayBox()
	PlaceBox(plate)
	catcher:Show()
	box:Show()
end

-- an entry's box
local function OpenBoxFor(plate)
	local entry = plate and plate.entry
	if not entry then
		return
	end
	ReadyBox()
	local P = Movers()
	box.entry, box.plate, box.spec = entry, plate, nil
	box.header.label:SetText(P.Label(entry))
	local locked = P.LockedReason(entry)
	local note = locked or P.Note(entry)
	box.note:SetText(note or "")
	box.note:SetShown(note ~= nil)
	-- Size: the entry's range as fractions of its standard size
	local base = MelloUI.EntryBase and MelloUI:EntryBase(entry) or 1
	local min = (Num(entry.min) or 0.5 * base) / base
	local max = (Num(entry.max) or 2 * base) / base
	box.size.slider:SetRange(min, max, 0.01, true)
	box.size:Show()
	local ES = E.Settings
	local sizeWhy = (ES and ES.For(entry) and TEXT.sizeEditMode) or TEXT.sizeOff
	Dim(box.size, locked ~= nil or entry.resize == false, locked or sizeWhy, dimSize)
	box.pos:Show()
	Dim(box.pos, locked ~= nil, locked, dimPos)
	box.pos.x:Refresh()
	box.pos.y:Refresh()
	-- (one look C4: an element's own settings are its designer's, "Design >";
	-- the box keeps Size, Position and Snap to)
	box.rows = { box.size, box.pos, box.snap }
	-- Snap to: the four fixed choices, then every other live keyed plate (a
	-- new list each open: the box names the choice from it)
	local values = {}
	for i = 1, #SNAP_FIXED do
		values[i] = SNAP_FIXED[i]
	end
	P.SnapChoices(entry, values)
	box.snap:SetShown(entry.key ~= nil)
	box.snap.values = values
	box.snap.dd:SetValues(values)
	-- Reset (its own label for the shared four) and the link
	box.reset:SetText(entry.resetLabel or TEXT.reset)
	local fs = box.reset:GetFontString()
	box.reset:SetWidth(math.max(90, math.ceil((fs and TextWidth(fs) or 0) + 24)))
	box.reset:Show()
	box.reset:SetEnabled(locked == nil)
	box.bridge:Hide()
	box.link.page = entry.page
	box.link:SetShown(entry.page ~= nil)
	ShowBox(plate)
end

function E:OpenBoxForPlate(plate)
	if E:IsShowing() then
		OpenBoxFor(plate)
	end
end

-- the box for a plate that is no entry (the bridge's)
function E:OpenBox(spec)
	if type(spec) ~= "table" or not E:IsShowing() then
		return
	end
	ReadyBox()
	box.entry, box.plate, box.spec = nil, spec.plate, spec
	box.header.label:SetText(spec.title or "")
	box.note:SetText(spec.note or "")
	box.note:SetShown(spec.note ~= nil)
	box.size:Hide()
	box.pos:Hide()
	box.snap:Hide()
	box.reset:Hide()
	local button = spec.button
	if type(button) == "table" then
		box.bridge:SetText(button.text or "")
		local fs = box.bridge:GetFontString()
		box.bridge:SetWidth(math.max(120, math.ceil((fs and TextWidth(fs) or 0) + 24)))
		box.bridge.melloHover = button.onHover
		box.bridge:Show()
	else
		box.bridge:Hide()
	end
	local link = spec.link
	box.link.page = type(link) == "table" and link.page or nil
	if type(link) == "table" and link.text then
		box.link.text:SetText(link.text)
	else
		box.link.text:SetText(TEXT.options)
	end
	box.link:SetShown(box.link.page ~= nil)
	ShowBox(spec.plate)
end

-- the box's button (the bridge lays its secure overlay over it)
function E:BoxButton()
	return box and box.bridge
end

CloseBox = function()
	if E.Settings then
		E.Settings.Hide()
	end
	if box and box:IsShown() then
		box:Hide()   -- (a field's own OnHide puts its value back: a half-typed number is dropped)
		box.entry, box.plate, box.spec = nil, nil, nil
		if box.link then
			box.link.text:SetText(TEXT.options)
		end
	end
	if catcher then
		catcher:Hide()
	end
end

function E:CloseBox()
	CloseBox()
end

-- (1.2.4) the box laid again where it stands (a switch among its Edit Mode
-- settings brought another in or out)
function E.RelayBox()
	if box and box:IsShown() then
		local top = box:GetTop()
		LayBox()
		if Num(top) then
			box:ClearAllPoints()
			box:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", Num(box:GetLeft()) or 0, top)
		end
	end
end

function E:BoxOpen()
	return box ~= nil and box:IsShown()
end

-- the fields follow a drag or a nudge of the element the box is for (the
-- one typed in left alone)
function E:BoxFollow(entry)
	if entry ~= nil and BoxEntry() == entry then
		box.size.slider:Refresh()
		box.pos.x:Refresh()
		box.pos.y:Refresh()
	end
end

--------------------------------------------------------------------------------
-- Changes: one element's reset, Reset all (SPEC 2.11)
--------------------------------------------------------------------------------

function E:ResetEntry(entry)
	local LS, P = Session(), Movers()
	if not (LS and S.open and entry) or P.LockedReason(entry) then
		return
	end
	local ok, err = pcall(LS.Reset, entry)
	if not ok then
		Report(err)
	end
	MelloUI:PlayUISound("tick")
	E:BoxFollow(entry)
	P.SyncSoon()
	E:Refresh()
end

-- every live element that is no tool and has a stored, pending or waiting
-- place (its `waiting`: the Route arrow's from before 0.14, which its reset
-- lets go), and every live `save` element (a key once)
ResetAll = function()
	local LS, P = Session(), Movers()
	if not (LS and S.open) then
		return
	end
	local list = MelloUI:MoverEntries()
	local seen = {}
	for i = 1, #list do
		local entry = list[i]
		local key = entry.key
		if entry.group ~= "tool" and (key == nil or not seen[key]) and MelloUI:EntryLive(entry)
			and not P.LockedReason(entry) then
			local placed = entry.save ~= nil or (key ~= nil and MelloUI:GetPosition(key) ~= nil)
				or LS.Pos(entry) ~= nil or MelloUI:EntryWaiting(entry)
			if placed then
				if key ~= nil then
					seen[key] = true
				end
				local ok, err = pcall(LS.Reset, entry)
				if not ok then
					Report(err)
				end
			end
		end
	end
	MelloUI:PlayUISound("tick")
	P.SyncSoon()
	E:Refresh()
end

--------------------------------------------------------------------------------
-- The keyboard (SPEC 2.13)
--------------------------------------------------------------------------------

local keys

local ARROWS = { UP = true, DOWN = true, LEFT = true, RIGHT = true }

-- Escape, one step each press: the dock's small panel, the box, the
-- Elements list, the confirm or the prompt, the selection, then leaving
local function Escape()
	local P = Movers()
	local K = E.Picker
	if ClosePop() then
		return
	elseif E:BoxOpen() then
		CloseBox()
	elseif K and K.IsOpen() then
		K.Close()
	elseif S.confirm then
		S.confirm = false
		LayBar()
	elseif S.asking then
		KeepEditing()
	elseif P and P.Selected() then
		P.Deselect()
	else
		E:Close()
	end
end

-- a game menu open (a context menu). It has no keys of its own: the game's
-- Escape closes it, and its Menu step then answers, so the game menu does
-- not open. A plain read. (A dropdown's list -- the bar's Show, the box's
-- Snap to -- is MelloUI's own flyout since 0.15.0: W.CloseFlyouts, below.)
local function AnyMenuOpen()
	return Menu.GetManager():IsAnyMenuOpen()
end
local function MenuOpen()
	local ok, open = pcall(AnyMenuOpen)
	return ok and not Secret(open) and open and true or false
end

-- (0.19.9) the key frame lent to another mode of MelloUI's while Edit Layout
-- is closed (Keybind Mode): the addon's one keyboard frame (check_panels'
-- key-propagate). The borrower's handler(key) answers true to keep a key;
-- anything else goes on to the game. (One look C6) a borrower taken over by
-- another is told (its onLost); a polite one (the designer stage) never takes
-- the keys from another
local lentTo, lentLost = nil, nil

local KeyDown = Shared("OnKeyDown on Edit Layout's keys", function(self, key)
	if lentTo then
		if not InCombat() then
			self:SetPropagateKeyboardInput(not lentTo(key))
		end
		return
	end
	if InCombat() or not E:IsShowing() then
		return
	end
	if key == "ESCAPE" then
		-- (an open list first, one step: MelloUI's own closed here, the key
		-- ours -- the game's Escape never reaches it past these keys; a game
		-- menu by the game's Escape, nothing of ours)
		if W.CloseFlyouts() then
			self:SetPropagateKeyboardInput(false)
			return
		end
		if MenuOpen() then
			self:SetPropagateKeyboardInput(true)
			return
		end
		self:SetPropagateKeyboardInput(false)
		Escape()
		return
	end
	local P = Movers()
	if ARROWS[key] and P and P.CanNudge() then
		self:SetPropagateKeyboardInput(false)
		P.KeyDown(key)
		return
	end
	self:SetPropagateKeyboardInput(true)
end, "script")

local KeyUp = Shared("OnKeyUp on Edit Layout's keys", function(self, key)
	local P = Movers()
	if P then
		P.KeyUp(key)
	end
	if InCombat() or not (lentTo or E:IsShowing()) then
		return
	end
	self:SetPropagateKeyboardInput(true)
end, "script")

local function MakeKeys()
	keys = CreateFrame("Frame", nil, UIParent)
	keys:Hide()
	keys:SetFrameStrata("FULLSCREEN_DIALOG")
	keys:SetFrameLevel(KEYS_LEVEL)
	keys:SetSize(1, 1)
	keys:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
	keys:EnableMouse(false)
	Perf.SetScript(keys, "OnKeyDown", KeyDown)
	Perf.SetScript(keys, "OnKeyUp", KeyUp)
end

-- on only while the mode shows, never in combat (the fight's own pause turns
-- it off before the lockdown)
local function KeyboardOn()
	if InCombat() then
		return
	end
	if not keys then
		MakeKeys()
	end
	keys:Show()
	keys:SetPropagateKeyboardInput(true)
	keys:EnableKeyboard(true)
end

local function KeyboardOff()
	if not keys then
		return
	end
	local P = Movers()
	if P then
		P.KeyUp()
	end
	if not InCombat() and keys:IsShown() then
		keys:EnableKeyboard(false)
	end
	keys:Hide()
end

-- (0.19.9) the key frame lent (above): never in a fight, never while Edit
-- Layout itself is open; false when it cannot be had. `opts` (one look C6):
-- { polite = true } (refused while another borrower has it), onLost = fn
-- (told once when another borrower takes it over)
function MelloUI:LendKeyboard(handler, opts)
	if InCombat() or S.open or type(handler) ~= "function" then
		return false
	end
	opts = type(opts) == "table" and opts or nil
	if lentTo and lentTo ~= handler then
		if opts and opts.polite then
			return false
		end
		local lost = lentLost
		lentTo, lentLost = nil, nil
		if lost then
			pcall(lost)
		end
	end
	lentTo = handler
	lentLost = opts and type(opts.onLost) == "function" and opts.onLost or nil
	KeyboardOn()
	return true
end

-- (the key frame off unless Edit Layout's pieces show: a session paused for
-- the configurator keeps no key frame of its own -- one look C6's review)
function MelloUI:TakeBackKeyboard(handler)
	if handler == nil or lentTo ~= handler then
		return
	end
	lentTo, lentLost = nil, nil
	if not E:IsShowing() then
		KeyboardOff()
	end
end

-- the borrower holding the keys now (nil: none)
function MelloUI:KeyboardLentTo()
	return lentTo
end

--------------------------------------------------------------------------------
-- Showing and hiding every piece
--------------------------------------------------------------------------------

local events   -- the event frame (below)

local function ShowPieces()
	RunSources()
	ApplyToggles()
	local P = Movers()
	if P then
		P.ShowAll()
	end
	-- (one look C6) the plate StartEditLayout's caller named, picked once
	if S.focus ~= nil then
		if P and P.SelectKey then
			P.SelectKey(S.focus)
		end
		S.focus = nil
	end
	ShowBar()
	if E.Picker then
		E.Picker.Resume()
	end
	KeyboardOn()
	if events then
		pcall(events.RegisterEvent, events, "GLOBAL_MOUSE_DOWN")
	end
end

-- a drag ends where it is, a held arrow stops, the box closes (a half-typed
-- value dropped), and every piece goes at once
local function HidePieces(fade)
	local P = Movers()
	KeyboardOff()
	if P then
		P.HideAll()
	end
	E.EachLayer("Hide")
	CloseBox()
	if E.Picker then
		E.Picker.Hide()
	end
	E:TooltipHide()
	HideBar(fade)
	if events then
		pcall(events.UnregisterEvent, events, "GLOBAL_MOUSE_DOWN")
	end
end

local function Fire(showing, state)
	MelloUI:Fire("editlayout", showing, state)
end

--------------------------------------------------------------------------------
-- Pauses (SPEC 2.1, 2.12)
--------------------------------------------------------------------------------

function E:Suspend(reason)
	if not S.open or reason == nil or S.reasons[reason] then
		return
	end
	local was = E:IsShowing()
	if was then
		HidePieces()
	end
	S.reasons[reason] = true
	S.nReasons = S.nReasons + 1
	if was then
		Fire(false, "paused")
		if reason == "combat" then
			MelloUI:Announce(TEXT.paused, "info")
		end
	end
end

function E:Resume(reason)
	if not S.open or reason == nil or not S.reasons[reason] then
		return
	end
	S.reasons[reason] = nil
	S.nReasons = S.nReasons - 1
	if S.nReasons > 0 then
		return
	end
	-- (a reason cleared in a fight whose own event was missed: it waits)
	if InCombat() then
		S.reasons.combat = true
		S.nReasons = 1
		return
	end
	ShowPieces()
	Fire(true, "open")
end

--------------------------------------------------------------------------------
-- Events, the configurator's pause and the bus (registered at the first Open)
--------------------------------------------------------------------------------

local TryQueued   -- below

local function OnEvent(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		E:Suspend("combat")
	elseif event == "PLAYER_REGEN_ENABLED" then
		if S.open then
			E:Resume("combat")
		end
		if S.queued == "combat" then
			TryQueued()
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		local P = Movers()
		if P and E:IsShowing() then
			P.SyncSoon()
		end
	elseif event == "GLOBAL_MOUSE_DOWN" then
		local P = Movers()
		if P and E:IsShowing() then
			P.ClickedElsewhere()
			-- (1.2.4) the Elements list closes on a click outside it, unless kept open
			if E.Picker then
				E.Picker.ClickedOutside()
			end
		end
	end
end

local function SessionEvents(on)
	if not events then
		return
	end
	if on then
		events:RegisterEvent("PLAYER_REGEN_DISABLED")
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
		events:RegisterEvent("PLAYER_ENTERING_WORLD")
	else
		events:UnregisterEvent("PLAYER_REGEN_DISABLED")
		events:UnregisterEvent("PLAYER_ENTERING_WORLD")
		pcall(events.UnregisterEvent, events, "GLOBAL_MOUSE_DOWN")
		if S.queued ~= "combat" then
			events:UnregisterEvent("PLAYER_REGEN_ENABLED")
		end
	end
end

local ToolOnShow = Shared("OnShow on the configurator or the installer (Edit Layout pauses)", function()
	if S.open then
		E:Suspend("options")
	end
end, "script")

-- back when neither window shows, a frame later: the installer opened from
-- the configurator hides it before it shows itself, and its "open the
-- settings" hides itself before the configurator shows (no show and hide
-- of every piece in between). A hide of the whole UI (Alt+Z) leaves both
-- shown: the mode waits.
local TOOLS_KEY = "EditLayout tools"
local function ToolsGone()
	if S.open and S.reasons.options and not ToolShown() then
		E:Resume("options")
	end
end
local ToolOnHide = Shared("OnHide on the configurator or the installer (Edit Layout comes back)", function()
	if S.open and S.reasons.options then
		MelloUI.Kit:NextFrame(TOOLS_KEY, ToolsGone)
	end
end, "script")

local toolHooked = setmetatable({}, { __mode = "k" })

-- the configurator's and the installer's OnShow / OnHide, post-hooked once
-- on our own frames
local function HookTool(frame)
	if type(frame) ~= "table" or toolHooked[frame] or not ToolFrame(frame) then
		return
	end
	toolHooked[frame] = true
	Perf.HookScript(frame, "OnShow", ToolOnShow)
	Perf.HookScript(frame, "OnHide", ToolOnHide)
end

-- the configurator gives way (hidden) and the mode comes back; the
-- installer does not (an answer it waits for is the player's to give): its
-- own close brings the mode back
local function ConfigAside()
	local cfg = ConfigFrame()
	if Shown(cfg) then
		cfg:Hide()
	end
	if not ToolShown() then
		E:Resume("options")
	end
end

local function OnEditMode(entering)
	if entering then
		E:Suspend("editmode")
	else
		E:Resume("editmode")
		if S.queued == "editmode" then
			TryQueued()
		end
	end
end

-- an element registered, shown or hidden, or let go by the session: the
-- plates follow (one sync a frame); the configurator or the installer made
-- after the first Open gets its hooks here
local function OnMover(what, entry, shown)
	local frame = type(entry) == "table" and entry.frame or nil
	if frame ~= nil and (what == "registered" or what == "shown") and not toolHooked[frame] and ToolFrame(frame) then
		HookTool(frame)
		if what == "shown" and shown and S.open then
			E:Suspend("options")
		end
	end
	if not E:IsShowing() then
		return
	end
	local P = Movers()
	if not P then
		return
	end
	if what == "shown" and not shown and P.Dragging() == entry then
		P.EndDrag()
	end
	P.SyncSoon()
end

local function OnScale()
	local P = Movers()
	if P and E:IsShowing() then
		P.Redraw()
		P.SyncSoon()
	end
end

local function FirstOpen()
	if S.first then
		return
	end
	S.first = true
	events = CreateFrame("Frame")
	Perf.SetScript(events, "OnEvent", OnEvent)
	MelloUI:On("editmode", OnEditMode, "Edit Layout")
	MelloUI:On("mover", OnMover, "Edit Layout")
	MelloUI:On("scale", OnScale, "Edit Layout")
	HookTool(ConfigFrame())
	HookTool(InstallerFrame())
	local P = Movers()
	if P then
		P.Setup()
	end
end

--------------------------------------------------------------------------------
-- The session: begin, end, Save, Discard, the leave prompt
--------------------------------------------------------------------------------

-- Core's end of the session: reason "saved" (extra: the count saved),
-- "discarded" or "abandoned"
local function OnEnd(reason, extra)
	if not S.open then
		return
	end
	local n, quiet = (reason == "saved" and math.max(Num(extra) or 0, S.ending)) or S.ending, S.quiet
	if reason == "abandoned" and E.Settings then
		E.Settings.Discard()
	end
	-- (every piece away while the state still says what it was: the
	-- keyboard's last call is made before it is closed)
	HidePieces(reason ~= "abandoned")
	local P = Movers()
	if P then
		P.Deselect()
	end
	S.open, S.asking, S.confirm, S.quiet, S.ending = false, false, false, false, 0
	if E.Picker then
		E.Picker.EndSession()
	end
	wipe(S.reasons)
	S.nReasons = 0
	SessionEvents(false)
	if reason == "saved" then
		MelloUI:Print(n == 1 and TEXT.savedOne or string.format(TEXT.savedMany, n))
	elseif reason == "discarded" then
		if not quiet then
			MelloUI:Print(TEXT.discarded)
		end
	elseif reason == "abandoned" then
		MelloUI:Print(TEXT.abandoned)
	end
	MelloUI:PlayUISound("window_close")
	Fire(false, "closed")
	-- (0.19.9) what E:Close was asked to do once the session is over (Keybind
	-- Mode, started from the bar); the next frame, Edit Layout all put away
	local after = S.after
	S.after = nil
	if after and reason ~= "abandoned" then
		C_Timer.After(0, after)
	end
end

local function Begin()
	local LS = Session()
	if not (LS and LS.Begin) then
		return
	end
	S.ending, S.quiet, S.asking, S.confirm = 0, false, false, false
	wipe(S.reasons)
	S.nReasons = 0
	-- (Core refuses a session only with no settings to hold the places)
	if LS.Begin(OnEnd) == false then
		return
	end
	S.open = true
	SessionEvents(true)
	MelloUI:PlayUISound("window_open")
	-- (the configurator or the installer on show: the session starts paused
	-- for it)
	if ToolShown() then
		S.reasons.options = true
		S.nReasons = 1
		return
	end
	ShowPieces()
	Fire(true, "open")
end

-- the session over one way or another (Core calls OnEnd; a session that did
-- not is ended here)
local function Finish(how)
	local LS = Session()
	local P = Movers()
	CloseBox()
	if P then
		P.EndDrag()
	end
	-- (1.2.4) the Edit Mode settings held: written (the active layout, from the next reload) or dropped
	local ES = E.Settings
	if ES then
		if how == "save" then
			ES.Save()
		else
			ES.Discard()
		end
	end
	local fn = LS and ((how == "save" and LS.Commit) or LS.Discard)
	if fn then
		local ok, err = pcall(fn)
		if not ok then
			Report(err)
		end
	end
	if S.open then
		OnEnd(how == "save" and "saved" or "discarded")
	end
end

Save = function()
	if not S.open then
		return
	end
	S.ending = E:Pending()
	Finish("save")
end

Discard = function()
	if not S.open then
		return
	end
	S.quiet = E:Pending() == 0
	Finish("discard")
end

-- Done: nothing changed (what was moved and moved back exactly goes back
-- quietly)
Done = function()
	if not S.open then
		return
	end
	if E:Pending() > 0 then
		Ask()
		return
	end
	S.quiet = true
	Finish("discard")
end

Ask = function()
	S.asking, S.confirm = true, false
	CloseBox()
	if E:IsShowing() then
		LayBar()
	end
end

KeepEditing = function()
	S.asking = false
	S.after = nil
	if E:IsShowing() then
		LayBar()
	end
end

--------------------------------------------------------------------------------
-- A queued open (SPEC 2.1): in combat, while Edit Mode is open or while
-- logging in; one at a time, Close() cancels it
--------------------------------------------------------------------------------

local LoginQueued = function()
	if S.queued == "login" then
		TryQueued()
	end
end

local function Queue(why)
	local was = S.queued
	S.queued = why
	if why == "combat" and events then
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
	elseif why == "login" then
		MelloUI:AfterLogin(LoginQueued)
	end
	if was ~= why then
		MelloUI:Announce(why == "combat" and TEXT.queuedCombat or why == "editmode" and TEXT.queuedEditMode
			or TEXT.queuedLogin, "info")
	end
end

TryQueued = function()
	S.queued = nil
	if not S.open and events then
		events:UnregisterEvent("PLAYER_REGEN_ENABLED")
	end
	E:Open()
end

local function CancelQueue()
	if S.queued == "combat" and events and not S.open then
		events:UnregisterEvent("PLAYER_REGEN_ENABLED")
	end
	S.queued = nil
	S.focus = nil
end

--------------------------------------------------------------------------------
-- The public API (SPEC 2.2)
--------------------------------------------------------------------------------

function E:IsOpen()
	return S.open
end

function E:IsShowing()
	return S.open and S.nReasons == 0
end

function E:Pending()
	local LS = Session()
	if not (S.open and LS and LS.Count) then
		return 0
	end
	local ok, n = pcall(LS.Count)
	local ES = E.Settings
	return (ok and Num(n) or 0) + (ES and ES.Count() or 0)
end

function E:Open()
	-- (0.19.9) Keybind Mode gives way, its keys saved: the key frame is Edit Layout's again
	local KB = MelloUI.KeybindMode
	if KB and KB:IsActive() then
		KB:Finish(true)
	end
	FirstOpen()
	if S.open then
		if S.reasons.options then
			ConfigAside()
		end
		return
	end
	if InCombat() then
		Queue("combat")
	elseif MelloUI.EditModeOpen() then
		Queue("editmode")
	elseif MelloUI:LoggingIn() then
		Queue("login")
	else
		S.queued = nil
		Begin()
	end
end

-- `after` (0.19.9): run once the session is over -- after the leave question
-- when something is unsaved; Keep editing forgets it
function E:Close(after)
	CancelQueue()
	if not S.open then
		if after then
			after()
		end
		return
	end
	S.after = after
	if E:Pending() > 0 then
		Ask()
	else
		S.quiet = true
		Finish("discard")
	end
end

-- `focus` (one look C6: a designer stage's Place on screen): a mover's key,
-- its plate picked as the pieces show (kept through a queued open)
function MelloUI:StartEditLayout(source, focus)
	S.focus = focus
	local cfg = ConfigFrame()
	if not S.open then
		if Shown(cfg) then
			cfg:Hide()
		end
		E:Open()
		return
	end
	if S.reasons.options then
		-- (the configurator's own button, a slash or Edit Mode's button while
		-- the configurator stands over the paused mode: it gives way)
		ConfigAside()
		return
	end
	if source == "editmode" then
		E:Resume("editmode")
	elseif source == "slash" and E:IsShowing() then
		E:Close()
	end
end

function MelloUI:EditingLayout()
	return E:IsShowing()
end

-- /mello edit dump: the state, every entry and why it has a plate or not,
-- and the layers', into the log (the copy window shows it)
function E:Dump()
	MelloUI:ClearLog()
	MelloUI.printHold = (tonumber(MelloUI.printHold) or 0) + 1
	local ok, err = pcall(function()
		local reasons = {}
		for r in pairs(S.reasons) do
			reasons[#reasons + 1] = r
		end
		table.sort(reasons)
		local K = E.Picker
		MelloUI:Print("Edit Layout: %s%s, %s, %d pending, queued %s", S.open and "open" or "closed",
			#reasons > 0 and (" (paused: " .. table.concat(reasons, ", ") .. ")") or "",
			K and K.SoloLabel() or "no solo", E:Pending(), tostring(S.queued))
		local P = Movers()
		if P then
			P.Dump(function(...)
				MelloUI:Print(...)
			end)
		end
		E.EachLayer("Dump", function(...)
			MelloUI:Print(...)
		end)
	end)
	MelloUI.printHold = (tonumber(MelloUI.printHold) or 1) - 1
	if not ok then
		Report(err)
	end
	MelloUI:ShowLog("Edit Layout")
end
