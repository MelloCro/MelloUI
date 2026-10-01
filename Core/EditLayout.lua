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
--   E:Shows(group)  whether the bar's Show filter shows that group ("own",
--                   "window", "hud", "editmode")
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
	show = "Show", snap = "Snap",
	resetAll = "Reset all", discard = "Discard", save = "Save", done = "Done", cancel = "Cancel",
	keep = "Keep editing",
	one = "1 unsaved change", many = "%d unsaved changes",
	confirm = "Reset every element to its standard place and size?",
	askOne = "You have 1 unsaved change.", askMany = "You have %d unsaved changes.",
	size = "Size", position = "Position", snapTo = "Snap to", reset = "Reset", options = "All options >",
	sizeOff = "Its size is set on its page.",
	paused = "Edit Layout is paused for combat. It comes back when the fight is over.",
	queuedCombat = "Edit Layout opens when the fight is over.",
	queuedEditMode = "Edit Layout opens when you close Edit Mode.",
	queuedLogin = "Edit Layout opens once you are in the world.",
	savedOne = "Edit Layout: 1 change saved.", savedMany = "Edit Layout: %d changes saved.",
	discarded = "Edit Layout: changes discarded.",
	abandoned = "Edit Layout closed: a profile or the installer changed the layout, so your unsaved changes were "
		.. "dropped.",
}
E.TEXTS = TEXT

local FILTERS = {
	{ value = "all", label = "All" },
	{ value = "own", label = "MelloUI" },
	{ value = "window", label = "Windows" },
	{ value = "hud", label = "HUD" },
	{ value = "editmode", label = "Edit Mode" },
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
local BAR_KEY = "editLayoutBar"
local BAR_Y = -150            -- its place: the screen's top centre, this far down (where the unlock banner was)
local PAD, GAP = 12, 10       -- the bar's inset and the room between its parts
local ROW_H, LINE_H = 32, 16  -- the bar's row, and each of its hint lines
local BOX_W, BOX_ROW, BOX_LABEL = 280, 28, 80   -- the box's width, a row's height, the controls' left
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
	filter = "all",
	ending = 0,         -- the count at Save (its chat line)
	quiet = false,      -- a close with nothing changed: no chat line
	first = false,      -- the first Open's set-up done
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

function E:Shows(group)
	return S.filter == "all" or S.filter == group
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
-- The control bar (SPEC 2.10): one row -- the title, Show, Snap, the change
-- count, Reset all, then Done or Discard and Save -- and the hint lines under
-- it. The row turns into Reset all's confirm or the leave prompt. A W.Panel
-- plate with the UI shade; a "tool" mover (dragged by itself at any time, its
-- place saved at once: D10).
--------------------------------------------------------------------------------

local bar

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
	frame:SetPoint("TOP", UIParent, "TOP", 0, BAR_Y)
end

-- a button of the bar, its width from its text
local function BarButton(parent, text, onClick, gold)
	local b = W.Button(parent, text, 80, nil, { onClick = onClick, gold = gold })
	local fs = b:GetFontString()
	b:SetWidth(math.max(72, math.ceil((fs and TextWidth(fs) or 0) + 24)))
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

local function GetFilter()
	return S.filter
end
local function SetFilter(v)
	S.filter = v or "all"
	local P = Movers()
	if P and E:IsShowing() then
		P.SyncAll()
	end
end
local function GetSnap()
	return E:SnapOn()
end
local function SetSnap(on)
	if UIModDB() then
		MelloUI:NotifySettingChanged(UIMOD, "autoSnap", on and true or false)
	end
end

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

local function MakeBar()
	bar = CreateFrame("Frame", "MelloUIEditLayoutBar", UIParent)
	bar:Hide()
	bar:SetFrameStrata("FULLSCREEN_DIALOG")
	bar:SetFrameLevel(BAR_LEVEL)
	bar:SetClampedToScreen(true)
	bar:EnableMouse(true)
	bar:SetSize(600, ROW_H + LINE_H + 2 * 8)
	W.Panel(bar, { on = true })
	-- (the UI shade: the square partner of a plain plate)
	local Kit = MelloUI.Kit
	Kit:ShadeElement(bar, "windows"):Add(bar, SQUARE_SHADE)
	-- the main row
	local row = CreateFrame("Frame", nil, bar)
	row:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
	row:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
	row:SetHeight(ROW_H)
	bar.row = row
	bar.title = W.Text(row, "GameFontNormalLarge", E.TEXT.name, "selectedTrim")
	Kit:TitleFont(bar.title, true)
	bar.divider = W.Solid(row, "ARTWORK", "border", 1)
	bar.divider:SetSize(1, 18)
	bar.showLabel = W.Text(row, "GameFontHighlight", TEXT.show, "text")
	bar.filter = W.Dropdown(row, 110, GetFilter, SetFilter, FILTERS)
	bar.snap = W.Switch(row, GetSnap, SetSnap)
	bar.snapLabel = W.Text(row, "GameFontHighlight", TEXT.snap, "text")
	bar.count = W.Text(row, "GameFontHighlight", nil, "text")
	bar.count:SetText(string.format(TEXT.many, 99))
	bar.countW = TextWidth(bar.count)
	bar.resetAll = BarButton(row, TEXT.resetAll, ResetAllClick)
	bar.done = BarButton(row, TEXT.done, DoneClick, true)
	bar.discard = BarButton(row, TEXT.discard, DiscardClick)
	bar.save = BarButton(row, TEXT.save, SaveClick, true)
	-- Reset all's confirm
	local confirm = CreateFrame("Frame", nil, bar)
	confirm:SetAllPoints(row)
	confirm:Hide()
	bar.confirmRow = confirm
	bar.confirmText = W.Text(confirm, "GameFontHighlight", TEXT.confirm, "text")
	bar.confirmReset = BarButton(confirm, TEXT.resetAll, ConfirmResetClick, true)
	bar.confirmCancel = BarButton(confirm, TEXT.cancel, CancelClick)
	-- the leave prompt
	local prompt = CreateFrame("Frame", nil, bar)
	prompt:SetAllPoints(row)
	prompt:Hide()
	bar.promptRow = prompt
	bar.promptText = W.Text(prompt, "GameFontHighlight", nil, "text")
	bar.promptSave = BarButton(prompt, TEXT.save, SaveClick, true)
	bar.promptDiscard = BarButton(prompt, TEXT.discard, DiscardClick)
	bar.promptKeep = BarButton(prompt, TEXT.keep, KeepClick)
	-- the hint lines (full body size on the panel: the no-eye-strain rule)
	bar.hints = {}
	for i = 1, 3 do
		local fs = W.Text(bar, "GameFontHighlight", nil, "text")
		fs:SetWordWrap(false)
		bar.hints[i] = fs
	end
	bar.hints[1]:SetText(TEXT.hint)
	-- its place: Core's store, dragged by itself at any time (a "tool")
	-- (hung by its top centre, as its default: its hint lines come and go
	-- under the row, which stays where the player put it)
	MelloUI:RegisterMover(bar, bar, { key = BAR_KEY, group = "tool", plainDrag = "always", label = E.TEXT.name,
		anchor = "TOP", default = BarDefault })
	if bar:GetNumPoints() == 0 then
		BarDefault(bar)
	end
end

-- the change count on the bar and which of Done / Discard + Save shows
local function RefreshBar()
	if not bar then
		return
	end
	local n = E:Pending()
	bar.count:SetShown(n > 0)
	if n > 0 then
		bar.count:SetText(n == 1 and TEXT.one or string.format(TEXT.many, n))
	end
	bar.done:SetShown(n == 0)
	bar.discard:SetShown(n > 0)
	bar.save:SetShown(n > 0)
	bar.promptText:SetText(n == 1 and TEXT.askOne or string.format(TEXT.askMany, n))
	bar.snap:Refresh()
	bar.filter:Refresh()
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
	local width
	if asking then
		local row = bar.promptRow
		local n = Put(1, bar.promptText, row, TextWidth(bar.promptText), GAP * 2)
		n = Put(n + 1, bar.promptSave, row, bar.promptSave:GetWidth())
		n = Put(n + 1, bar.promptDiscard, row, bar.promptDiscard:GetWidth())
		n = Put(n + 1, bar.promptKeep, row, bar.promptKeep:GetWidth(), 0)
		width = Lay(laid, n, PAD)
	elseif confirm then
		local row = bar.confirmRow
		local n = Put(1, bar.confirmText, row, TextWidth(bar.confirmText), GAP * 2)
		n = Put(n + 1, bar.confirmReset, row, bar.confirmReset:GetWidth())
		n = Put(n + 1, bar.confirmCancel, row, bar.confirmCancel:GetWidth(), 0)
		width = Lay(laid, n, PAD)
	else
		local row = bar.row
		local pending = E:Pending() > 0
		local n = Put(1, bar.title, row, TextWidth(bar.title))
		n = Put(n + 1, bar.divider, row, 1)
		n = Put(n + 1, bar.showLabel, row, TextWidth(bar.showLabel), 6)
		n = Put(n + 1, bar.filter, row, bar.filter:GetWidth())
		n = Put(n + 1, bar.snap, row, bar.snap:GetWidth(), 2)
		n = Put(n + 1, bar.snapLabel, row, TextWidth(bar.snapLabel))
		-- (the count in the row only while it shows; its room then the
		-- widest count's, so the buttons stay put as it counts)
		if pending then
			n = Put(n + 1, bar.count, row, bar.countW)
		end
		n = Put(n + 1, bar.resetAll, row, bar.resetAll:GetWidth())
		if pending then
			n = Put(n + 1, bar.discard, row, bar.discard:GetWidth())
			n = Put(n + 1, bar.save, row, bar.save:GetWidth(), 0)
		else
			n = Put(n + 1, bar.done, row, bar.done:GetWidth(), 0)
		end
		width = Lay(laid, n, PAD)
	end
	for i = 1, #laid do
		laid[i].part, laid[i].row = nil, nil
	end
	-- the hint lines: always the first; UI Modifications off (D6); the
	-- bridge's hidden elements
	local P = Movers()
	bar.hints[2]:SetText(TEXT.moduleOff)
	bar.hints[3]:SetText(TEXT.bridgeHidden)
	local off = not MelloUI:IsModuleEnabled(UIMOD)
	local bridged = P and P.BridgeCount and P.BridgeCount() > 0
	bar.hints[2]:SetShown(off)
	bar.hints[3]:SetShown(bridged and true or false)
	local y = -(ROW_H + 2)
	width = width + PAD
	for i = 1, 3 do
		local fs = bar.hints[i]
		if fs:IsShown() then
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD, y)
			y = y - LINE_H
			width = math.max(width, PAD + TextWidth(fs) + PAD)
		end
	end
	bar:SetSize(math.ceil(math.max(width, 200)), 8 - y)
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

-- an element's own settings (its mover's `settings`, 0.17.0): a slider row
-- per "Module.key", the module's schema giving its name and range, the value
-- the module's setting itself (a shortcut: the configurator's row and this
-- one are the same setting). Rows made as needed, bound to a setting per open
local settingRows = {}

local function SettingOption(spec)
	if type(spec) ~= "string" then
		return nil
	end
	local name, key = spec:match("^([%w_]+)%.([%w_]+)$")
	local module = name and MelloUI:GetModule(name)
	for _, opt in ipairs(module and module.options or {}) do
		if opt.key == key and opt.type == "slider" then
			return opt, name, key, module
		end
	end
	return nil
end

local function SettingRow(i)
	local row = settingRows[i]
	if row then
		return row
	end
	row = BoxRow(box, "")
	local function Get()
		local s = row.setting
		if not s then
			return 0
		end
		local v = MelloUI:GetModuleDB(s.module)[s.key]
		if v == nil then
			v = s.default
		end
		return Num(v) or 0
	end
	local function Set(v)
		local s = row.setting
		if s and Num(v) then
			MelloUI:NotifySettingChanged(s.module, s.key, v)
			-- (the element's new size on its plate)
			local P = Movers()
			if P and P.SyncSoon then
				P.SyncSoon()
			end
		end
	end
	row.slider = W.Slider(row, BOX_W - BOX_LABEL - PAD, Get, Set, { min = 0, max = 1, step = 1 })
	row.slider:SetPoint("LEFT", row, "LEFT", BOX_LABEL, 0)
	settingRows[i] = row
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
	Dim(box.size, locked ~= nil or entry.resize == false, locked or TEXT.sizeOff, dimSize)
	box.pos:Show()
	Dim(box.pos, locked ~= nil, locked, dimPos)
	box.pos.x:Refresh()
	box.pos.y:Refresh()
	-- the element's own settings, under Size (its mover's `settings`)
	local rows = { box.size }
	local n = 0
	for _, spec in ipairs(entry.settings or {}) do
		local opt, module, key, mod = SettingOption(spec)
		if opt then
			n = n + 1
			local row = SettingRow(n)
			row.setting = { module = module, key = key, default = mod.defaults and mod.defaults[key] }
			row.label:SetText(opt.name or key)
			row.slider:SetRange(opt.min or 0, opt.max or 1, opt.step or 1, opt.percent and true or false)
			row.slider:Refresh()
			Dim(row, locked ~= nil, locked, { row.slider })
			row:Show()
			rows[#rows + 1] = row
		end
	end
	for i = n + 1, #settingRows do
		settingRows[i]:Hide()
		settingRows[i].setting = nil
	end
	rows[#rows + 1] = box.pos
	rows[#rows + 1] = box.snap
	box.rows = rows
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
	for i = 1, #settingRows do
		settingRows[i]:Hide()
		settingRows[i].setting = nil
	end
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
		for i = 1, #settingRows do
			if settingRows[i].setting then
				settingRows[i].slider:Refresh()
			end
		end
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

-- Escape, one step each press: the box, the confirm or the prompt, the
-- selection, then leaving
local function Escape()
	local P = Movers()
	if E:BoxOpen() then
		CloseBox()
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

local KeyDown = Shared("OnKeyDown on Edit Layout's keys", function(self, key)
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
	if InCombat() or not E:IsShowing() then
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

--------------------------------------------------------------------------------
-- Showing and hiding every piece
--------------------------------------------------------------------------------

local events   -- the event frame (below)

local function ShowPieces()
	RunSources()
	local P = Movers()
	if P then
		P.ShowAll()
	end
	ShowBar()
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
	local n, quiet = (reason == "saved" and Num(extra)) or S.ending, S.quiet
	-- (every piece away while the state still says what it was: the
	-- keyboard's last call is made before it is closed)
	HidePieces(reason ~= "abandoned")
	local P = Movers()
	if P then
		P.Deselect()
	end
	S.open, S.asking, S.confirm, S.quiet, S.ending = false, false, false, false, 0
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
end

local function Begin()
	local LS = Session()
	if not (LS and LS.Begin) then
		return
	end
	S.ending, S.quiet, S.asking, S.confirm = 0, false, false, false
	S.filter = "all"   -- (the Show filter lasts one session)
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
	return ok and Num(n) or 0
end

function E:Open()
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

function E:Close()
	CancelQueue()
	if not S.open then
		return
	end
	if E:Pending() > 0 then
		Ask()
	else
		S.quiet = true
		Finish("discard")
	end
end

function MelloUI:StartEditLayout(source)
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
		MelloUI:Print("Edit Layout: %s%s, filter %s, %d pending, queued %s", S.open and "open" or "closed",
			#reasons > 0 and (" (paused: " .. table.concat(reasons, ", ") .. ")") or "", S.filter, E:Pending(),
			tostring(S.queued))
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
