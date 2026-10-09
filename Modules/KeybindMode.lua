--------------------------------------------------------------------------------
-- MelloUI - Keybind Mode (0.19.9; the user, 2026-10-07: "MelloUI's own
-- mode", look K2 of keybind_layout_sketch). Point at an action button and
-- press a key to bind it. The game's own mode (QuickKeybindFrame) is never
-- opened: its OnShow sets "showgrid" on every secure action button, which
-- from MelloUI's click would taint them (hard rule 1).
--
-- Binding as the game's listener does (Blizzard_Settings_Shared/
-- Blizzard_Keybindings.lua, ProcessInput), with the game's own pure helpers
-- only: the key converted (GetConvertedKeyOrButton), a lone modifier passed
-- by (IsKeyPressIgnoredForBinding), the chord built with Alt / Ctrl / Shift
-- (CreateKeyChordStringUsingMetaKeyState), the chord taken from any other
-- action, the new key first and the button's old first key kept as its
-- second. Done saves the binding set in use (SaveBindings), Cancel loads it
-- back (LoadBindings).
--   the buttons   every bar's (Action Buttons' BarButtons: the eleven bars),
--                 each with the game's own commandName (ActionBar.lua:
--                 ACTIONBUTTON3, MULTIACTIONBAR1BUTTON5, SHAPESHIFTBUTTON2,
--                 BONUSACTIONBUTTON4 ...)
--   the catcher   one frame over the button under the mouse, placed by its
--                 screen rect (never anchored to the secure button): mouse
--                 buttons 3 - 5 and the wheel; right-click clears the
--                 button's keys. The keys come through MelloUI's one key
--                 frame, Edit Layout's, lent while the mode is on
--                 (MelloUI:LendKeyboard): Escape cancels, as the bar's
--                 Cancel (the user, 2026-10-09)
--   the look      every bindable button lit softly in the palette, the one
--                 under the mouse in Action Buttons' press light, every key
--                 shown big in the middle while the mode is on
--   the bar       dressed as Edit Layout's: what to do, what the button
--                 under the mouse holds or what just changed, which binding
--                 set is saved to, Cancel and Done
-- Started from the Action Bars page (its header's Keybind Mode button),
-- Edit Layout's bar and /mello keybind; never in a fight (it opens after
-- it), and a fight ends it (what was bound is kept). Nothing at login: the
-- bar, the catcher, the hooks and each button's regions on the first start.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("KeybindMode")
local Shared = Perf.Shared
local W = MelloUI.Widgets
local Plain = MelloUI.Safe.Value

local K = {}
MelloUI.KeybindMode = K

local TEXT = {
	name = "Keybind Mode",
	hint = "Point at an action button and press a key, a mouse button or the wheel, with Shift, Ctrl or Alt if you "
		.. "like. Right-click clears its keys. Escape cancels.",
	account = "Saving to your account's key bindings.",
	character = "Saving to this character's own key bindings.",
	none = "Point at an action button.",
	keys = "%s: %s",
	noKey = "%s: no key yet",
	bound = "%s is on %s now.",
	took = "%s is on %s now (it was on %s).",
	cleared = "%s: its keys cleared.",
	refused = "%s cannot be bound.",
	left = "Left-click presses the button: it cannot be bound.",
	cancel = "Cancel", done = "Done",
	combat = "Keybind Mode opens when the fight is over.",
	editMode = "Close Edit Mode first: Keybind Mode works on your bars as they stand.",
	ended = "Keybind Mode ended for the fight. Your keys are saved.",
	saved = "Keybind Mode: your key bindings are saved.",
	cancelled = "Keybind Mode: the changes are undone.",
}
K.TEXT = TEXT

local BAR_KEY = "keybindBar"
local BAR_Y = -150                -- the screen's top centre, where Edit Layout's bar stands too
local PAD, GAP, ROW_H = 12, 10, 34
local BAR_W = 640
local SOFT = 0.12                 -- every bindable button's light (selectedTrim), under the press light's
local FLAT = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Flat"
local SQUARE_SHADE = { shape = "shade/square" }

local S = { active = false, queued = nil, from = nil, current = nil, changed = false }
K.state = S
local soft = setmetatable({}, { __mode = "k" })     -- [button] = its soft light
local label = setmetatable({}, { __mode = "k" })    -- [button] = its big key
local hooked = setmetatable({}, { __mode = "k" })   -- [button] = true: its OnEnter hooked
local list = {}                                     -- the bindable buttons of this start
local bar, catcher, events

--------------------------------------------------------------------------------
-- The game's bindings, read secret-safe
--------------------------------------------------------------------------------
local function CommandOf(button)
	local c = type(button) == "table" and rawget(button, "commandName")
	return type(c) == "string" and c ~= "" and c or nil
end

local function Context(command)
	local api = C_KeyBindings and C_KeyBindings.GetBindingContextForAction
	if api then
		local ok, ctx = pcall(api, command)
		if ok then
			return Plain(ctx)
		end
	end
	return nil
end

local function KeysOf(command)
	local ok, k1, k2 = pcall(GetBindingKey, command, nil, Context(command))
	if not ok then
		return nil, nil
	end
	k1, k2 = Plain(k1), Plain(k2)
	return type(k1) == "string" and k1 or nil, type(k2) == "string" and k2 or nil
end

-- a key as the game writes it: in full (the bar's lines) or short (the buttons')
local function KeyText(key, short)
	local ok, t = pcall(GetBindingText, key, short or nil)
	t = ok and Plain(t)
	return type(t) == "string" and t or tostring(key)
end

local function NameOf(command)
	local n = rawget(_G, "BINDING_NAME_" .. command)
	return type(n) == "string" and n or command
end

local function Set(key, command, ctx)
	local ok, done = pcall(SetBinding, key, command, ctx)
	return ok and done and true or false
end

local function CharacterSet()
	local ok, set = pcall(GetCurrentBindingSet)
	local character = Enum and Enum.BindingSet and Enum.BindingSet.Character or 2
	return ok and Plain(set) == character
end

--------------------------------------------------------------------------------
-- The look: the soft light, the press light, the big keys
--------------------------------------------------------------------------------
local function Say(text)
	if bar then
		bar.status:SetText(text or "")
	end
end

local function Light(button, on)
	local AB = MelloUI:GetModule("ActionButtons")
	if AB and AB.Light then
		AB:Light(button, on)
	end
end

local function Soft(button)
	local t = soft[button]
	if not t then
		t = button:CreateTexture(nil, "OVERLAY", nil, 4)
		t:SetTexture(FLAT)
		t:SetAllPoints(button)
		t:SetBlendMode("ADD")
		W.Paint(t, "selectedTrim", "vertex", SOFT)
		soft[button] = t
	end
	return t
end

local function Label(button)
	local fs = label[button]
	if not fs then
		fs = W.Text(button, "GameFontHighlightLarge", nil, "text")
		fs:SetDrawLayer("OVERLAY", 7)
		local path, size = fs:GetFont()
		if path then
			fs:SetFont(path, math.max(16, (tonumber(size) or 14) + 4), "OUTLINE")
		end
		fs:SetJustifyH("CENTER")
		fs:SetPoint("CENTER", button, "CENTER", 0, 0)
		label[button] = fs
	end
	return fs
end

local function ShowKeys()
	for _, button in ipairs(list) do
		local k1 = KeysOf(CommandOf(button))
		Label(button):SetText(k1 and KeyText(k1, true) or "")
	end
end

local function Dress(on)
	for _, button in ipairs(list) do
		if on then
			Soft(button):Show()
			Label(button):Show()
		else
			if soft[button] then
				soft[button]:Hide()
			end
			if label[button] then
				label[button]:Hide()
			end
		end
	end
	if on then
		ShowKeys()
	end
end

local function Describe(command)
	local k1, k2 = KeysOf(command)
	if k1 then
		Say(string.format(TEXT.keys, NameOf(command), k2 and (KeyText(k1) .. ", " .. KeyText(k2)) or KeyText(k1)))
	else
		Say(string.format(TEXT.noKey, NameOf(command)))
	end
end

--------------------------------------------------------------------------------
-- Binding (the game's listener's steps)
--------------------------------------------------------------------------------
local function Bind(command, input)
	local key = GetConvertedKeyOrButton and GetConvertedKeyOrButton(input) or input
	if IsKeyPressIgnoredForBinding and IsKeyPressIgnoredForBinding(key) then
		return   -- (a lone Shift / Ctrl / Alt: the chord comes with the key)
	end
	local chord = CreateKeyChordStringUsingMetaKeyState and CreateKeyChordStringUsingMetaKeyState(key) or key
	local ctx = Context(command)
	local k1, k2 = KeysOf(command)
	if k1 == chord then
		Describe(command)
		return
	end
	local okA, was = pcall(GetBindingAction, chord, nil, ctx)
	was = okA and Plain(was) or nil
	-- the button's keys off, the chord off whatever had it, then on the button
	if k1 then
		Set(k1, nil, ctx)
	end
	if k2 then
		Set(k2, nil, ctx)
	end
	Set(chord, nil, ctx)
	if not Set(chord, command, ctx) then
		if k1 then
			Set(k1, command, ctx)
		end
		if k2 then
			Set(k2, command, ctx)
		end
		Say(string.format(TEXT.refused, KeyText(chord)))
		return
	end
	-- its old first key kept as its second
	local keep = (k1 and k1 ~= chord and k1) or (k2 and k2 ~= chord and k2) or nil
	if keep then
		Set(keep, command, ctx)
	end
	S.changed = true
	MelloUI:PlayUISound("option_on")
	if type(was) == "string" and was ~= "" and was ~= command then
		Say(string.format(TEXT.took, KeyText(chord), NameOf(command), NameOf(was)))
	else
		Say(string.format(TEXT.bound, KeyText(chord), NameOf(command)))
	end
	ShowKeys()
end

local function Clear(command)
	local ctx = Context(command)
	local k1, k2 = KeysOf(command)
	if k1 then
		Set(k1, nil, ctx)
	end
	if k2 then
		Set(k2, nil, ctx)
	end
	if k1 or k2 then
		S.changed = true
		MelloUI:PlayUISound("option_off")
	end
	Say(string.format(TEXT.cleared, NameOf(command)))
	ShowKeys()
end

--------------------------------------------------------------------------------
-- The catcher: over the button under the mouse
--------------------------------------------------------------------------------
local function Leave()
	if S.current then
		Light(S.current, false)
	end
	S.current = nil
	if catcher then
		catcher:Hide()
	end
	if S.active then
		Say(TEXT.none)
	end
end

local function Place(button)
	local l, b, r, t = MelloUI.Safe.ScreenRect(button)
	local s = MelloUI.Safe.Number(UIParent:GetEffectiveScale())
	if not (l and s and s > 0) then
		return false
	end
	catcher:ClearAllPoints()
	catcher:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l / s, b / s)
	catcher:SetSize((r - l) / s, (t - b) / s)
	catcher:Show()
	return true
end

-- a key, through MelloUI's one key frame (Edit Layout's, lent while the
-- mode is on): true keeps it from the game. Escape cancels; over a button
-- every key binds; else the game has it (a screenshot key always)
local function KeyHandler(key)
	local okB, action = pcall(GetBindingFromClick, key)
	if okB and Plain(action) == "SCREENSHOT" then
		return false
	end
	if key == "ESCAPE" then
		-- (as Cancel: the changes undone; the user, 2026-10-09)
		K:Finish(false)
		return true
	end
	local command = S.current and CommandOf(S.current)
	if command then
		Bind(command, key)
		return true
	end
	return false
end

local CatchMouse = Shared("OnMouseDown on Keybind Mode's catcher", function(_, mouse)
	local command = S.current and CommandOf(S.current)
	if not command then
		return
	end
	if mouse == "RightButton" then
		Clear(command)
	elseif mouse == "LeftButton" then
		Say(TEXT.left)
	else
		Bind(command, mouse)
	end
end)

local CatchWheel = Shared("OnMouseWheel on Keybind Mode's catcher", function(_, delta)
	local command = S.current and CommandOf(S.current)
	if command then
		Bind(command, (tonumber(delta) or 0) > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
	end
end)

local CatchLeave = Shared("OnLeave on Keybind Mode's catcher", function()
	Leave()
end)

local function MakeCatcher()
	if catcher then
		return
	end
	catcher = CreateFrame("Frame", nil, UIParent)
	catcher:Hide()
	catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	catcher:SetFrameLevel(100)   -- (over the bar: its keys first while a button is under the mouse)
	catcher:EnableMouse(true)
	catcher:EnableMouseWheel(true)
	catcher:SetScript("OnMouseDown", CatchMouse)
	catcher:SetScript("OnMouseWheel", CatchWheel)
	catcher:SetScript("OnLeave", CatchLeave)
end

-- an action button under the mouse while the mode is on: the catcher over it
local ButtonEnter = Shared("OnEnter on an action button (Keybind Mode)", function(button)
	if not S.active then
		return
	end
	local command = CommandOf(button)
	if not command then
		return
	end
	if S.current and S.current ~= button then
		Light(S.current, false)
	end
	S.current = button
	if Place(button) then
		Light(button, true)
		Describe(command)
	else
		S.current = nil
	end
end)

--------------------------------------------------------------------------------
-- The bar
--------------------------------------------------------------------------------
local CancelClick = Shared("OnClick on Keybind Mode's Cancel", function()
	K:Finish(false)
end, "script")
local DoneClick = Shared("OnClick on Keybind Mode's Done", function()
	K:Finish(true)
end, "script")

local function BarDefault(frame)
	frame:ClearAllPoints()
	frame:SetPoint("TOP", UIParent, "TOP", 0, BAR_Y)
end

local function LayBar()
	local Num = MelloUI.Safe.Number
	local y = ROW_H + 4
	for _, fs in ipairs({ bar.hint, bar.status, bar.set }) do
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD, -y)
		fs:SetPoint("RIGHT", bar, "RIGHT", -PAD, 0)
		y = y + math.ceil(Num(fs:GetStringHeight()) or 16) + 6
	end
	bar:SetHeight(y + 6)
end

local function MakeBar()
	if bar then
		return
	end
	bar = CreateFrame("Frame", "MelloUIKeybindBar", UIParent)
	bar:Hide()
	bar:SetFrameStrata("FULLSCREEN_DIALOG")
	bar:SetClampedToScreen(true)
	bar:EnableMouse(true)
	bar:SetSize(BAR_W, 120)
	W.Panel(bar, { on = true })
	local Kit = MelloUI.Kit
	if Kit and Kit.ShadeElement then
		Kit:ShadeElement(bar, "windows"):Add(bar, SQUARE_SHADE)
	end
	bar.title = W.Text(bar, "GameFontNormalLarge", TEXT.name, "selectedTrim")
	if Kit and Kit.TitleFont then
		Kit:TitleFont(bar.title, true)
	end
	bar.title:SetPoint("LEFT", bar, "TOPLEFT", PAD, -ROW_H / 2 - 2)
	bar.done = W.Button(bar, TEXT.done, 90, nil, { onClick = DoneClick, gold = true })
	bar.done:SetPoint("RIGHT", bar, "TOPRIGHT", -PAD, -ROW_H / 2 - 2)
	bar.cancel = W.Button(bar, TEXT.cancel, 90, nil, { onClick = CancelClick })
	bar.cancel:SetPoint("RIGHT", bar.done, "LEFT", -GAP, 0)
	for _, key in ipairs({ "hint", "status", "set" }) do
		local fs = W.Text(bar, "GameFontHighlight", nil, "text")
		fs:SetWordWrap(true)
		bar[key] = fs
	end
	bar.hint:SetText(TEXT.hint)
	-- its place: Core's store, dragged by itself at any time (a tool, as Edit Layout's bar)
	MelloUI:RegisterMover(bar, bar, { key = BAR_KEY, group = "tool", plainDrag = "always", label = TEXT.name,
		anchor = "TOP", default = BarDefault })
	if bar:GetNumPoints() == 0 then
		BarDefault(bar)
	end
end

--------------------------------------------------------------------------------
-- Start and finish
--------------------------------------------------------------------------------
local OnEvent = Shared("OnEvent on Keybind Mode", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		-- (still out of lockdown in this event: what was bound is saved)
		if S.active then
			K:Finish(true, true)
			MelloUI:Announce(TEXT.ended, "info")
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		events:UnregisterEvent("PLAYER_REGEN_ENABLED")
		local from = S.queued
		S.queued = nil
		if from then
			K:Start(from)
		end
	elseif event == "UPDATE_BINDINGS" then
		if S.active then
			ShowKeys()
			if S.current then
				Describe(CommandOf(S.current))
			end
		end
	end
end)

local function MakeEvents()
	if not events then
		events = CreateFrame("Frame")
		events:SetScript("OnEvent", OnEvent)
	end
end

function K:IsActive()
	return S.active
end

-- `from`: "config" (the Action Bars page: it comes back after), "editlayout", "slash"
function K:Start(from)
	if S.active then
		return
	end
	if InCombatLockdown() then
		MakeEvents()
		S.queued = from or "slash"
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
		MelloUI:Announce(TEXT.combat, "info")
		return
	end
	if MelloUI.EditModeOpen and MelloUI.EditModeOpen() then
		MelloUI:Announce(TEXT.editMode, "info")
		return
	end
	local E = MelloUI.EditLayout
	if E and E.IsOpen and E:IsOpen() then
		-- (Edit Layout first: its own leave, its question if anything is unsaved)
		E:Close(function()
			K:Start(from)
		end)
		return
	end
	wipe(list)
	local AB = MelloUI:GetModule("ActionButtons")
	local all = AB and AB.BarButtons and AB.BarButtons() or {}
	for _, button in ipairs(all) do
		if CommandOf(button) then
			list[#list + 1] = button
		end
	end
	MakeBar()
	MakeCatcher()
	MakeEvents()
	for _, button in ipairs(list) do
		if not hooked[button] then
			hooked[button] = true
			Perf.HookScript(button, "OnEnter", ButtonEnter)
		end
	end
	S.active, S.from, S.changed, S.current = true, from, false, nil
	local cfg = rawget(_G, "MelloUIConfigFrame")
	S.reopen = from == "config" and cfg and cfg:IsShown() or nil
	if S.reopen then
		cfg:Hide()
	end
	Dress(true)
	bar.set:SetText(CharacterSet() and TEXT.character or TEXT.account)
	Say(TEXT.none)
	LayBar()
	bar:Show()
	MelloUI:LendKeyboard(KeyHandler)
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:RegisterEvent("UPDATE_BINDINGS")
	MelloUI:PlayUISound("window_open")
end

-- save: Done (the binding set in use saved), else Cancel (loaded back)
function K:Finish(save, quiet)
	if not S.active then
		return
	end
	local changed = S.changed
	if changed then
		local ok, set = pcall(GetCurrentBindingSet)
		set = ok and Plain(set) or nil
		if set then
			pcall(save and SaveBindings or LoadBindings, set)
		end
	end
	Leave()
	S.active = false
	MelloUI:TakeBackKeyboard(KeyHandler)
	Dress(false)
	bar:Hide()
	events:UnregisterEvent("PLAYER_REGEN_DISABLED")
	events:UnregisterEvent("UPDATE_BINDINGS")
	MelloUI:PlayUISound("window_close")
	if changed and not quiet then
		MelloUI:Print(save and TEXT.saved or TEXT.cancelled)
	end
	if S.reopen then
		S.reopen = nil
		MelloUI:OpenConfig()
	end
end

-- for the tests
K.soft, K.label, K.list = soft, label, list
K.Bind, K.Clear, K.CommandOf, K.KeyHandler = Bind, Clear, CommandOf, KeyHandler
function K.Frames()
	return bar, catcher, events
end
