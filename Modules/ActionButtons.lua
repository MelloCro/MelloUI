--------------------------------------------------------------------------------
-- MelloUI - Action Buttons
--
-- Two looks on every action button, with the painted skin or without it
-- (0.19.8; the user, 2026-10-06, from the addon study: "the nice keybind
-- press coloring of the whole action bar button, coloring the whole icon red
-- when out of range"; picks B and C of button_press_sketch, keys and clicks):
--   Light While Pressed   the whole button, rim and icon, lit while its key is
--                         held or the mouse holds it: one flat light added in
--                         the palette's selected trim
--   Range And Resource    the icon red out of range, deep blue short of mana,
--   Colours               drained of colour when it cannot be used (the hotkey
--                         turns red out of range as the game has it)
--
-- How (the client's Blizzard_ActionBar):
--   the press   every key path (ActionButtonDown, MultiActionButtonDown, the
--               pet and extra bars) sets the button's state through its
--               SetButtonState, a mouse press through OnMouseDown / Up: each
--               button's are post-hooked (visuals only). The light is a
--               texture of ours on the button's OVERLAY at sublevel 5: over
--               the kit's rims (3) and their glow (4), under the Active look
--               (6-7) and the cooldown's swipe, made on the button's first
--               press
--   the range   ACTION_RANGE_CHECK_UPDATE reaches the global
--               ActionButton_UpdateRangeIndicator(button, checksRange,
--               inRange) only when the range changes: one post-hook
--   usable      each action button's own UpdateUsable (the mixin's copy on
--               the button) colours its icon white, pale blue or grey on
--               every usable update: post-hooked per button
-- Cover, never overwrite (rule 1): the red and the deep blue are a cover of
-- ours over the icon, blended MOD (a multiply of what the game drew there),
-- written only when the button's state changes; the game's own icon colour
-- is never touched. The grey needs the icon desaturated, which no cover can
-- do: written only when it changes (the icon's own flag read first) and taken
-- back only from an icon greyed here (the game's own level-link grey stays;
-- its Update() clears the flag on a new action, the next usable update lays
-- it again). Nothing is made at login: the hooks, then each texture on its
-- first need.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("ActionButtons")
local hooksecurefunc = Perf.hooksecurefunc
local Shared = Perf.Shared
local W = MelloUI.Widgets

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret

local M = MelloUI:RegisterModule("ActionButtons", {
	title = "Action Buttons",
	desc = "Lights an action button while its key is held, and colours its icon by range and resources.",
	icon = "Interface\\Icons\\Ability_Warrior_Riposte",
	flavour = "See which button you press, and which spell cannot reach its target.",
	role = "adds",
	new = "0.19.8",
	-- (not on the installer's Features step: its two columns are full, as for
	-- the Swing Timers and Discard; on by default, its switches on Action Bars > Bars)
	installer = false,
	enabledByDefault = true,
	defaults = {
		pressLight = true,
		rangeColours = true,
	},
	options = {
		{ type = "toggle", key = "pressLight", name = "Light While Pressed", new = "0.19.8",
		  desc = "While you hold an action button's key, or press it with the mouse, the whole button lights up in "
			.. "the colour scheme's highlight colour, so you can see which button you are pressing." },
		{ type = "toggle", key = "rangeColours", name = "Range And Resource Colours", new = "0.19.8",
		  desc = "An action's icon turns red while your target is out of its range, deep blue while you lack the mana "
			.. "(or other resource) for it, and grey while it cannot be used. Its key already turns red out of range." },
	},
})

-- The bars whose buttons are lit (Blizzard_ActionBar: each bar's
-- actionButtons); the range and usable colours only on buttons that have an
-- action's usable update (the action bars' mixin)
local BARS = { "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
	"MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar", "PossessActionBar" }
local EXTRA = { "ExtraActionButton1" }
local FLAT = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Flat"
local LIGHT = { SUB = 5, ALPHA = 0.42 }   -- the light: OVERLAY sublevel, its strength (pick B)
local COVER_SUB = 7                       -- the cover: BACKGROUND sublevel, over the icon (at 0)

local light = setmetatable({}, { __mode = "k" })     -- [button] = its light texture
local held = setmetatable({}, { __mode = "k" })      -- [button] = true while pressed
-- (0.19.8) [button] = "key" | "mouse" while pressed, lit or not: what the bus tells (the topic "actionpress":
-- button, down) -- the Cooldown Manager's icons light with the button whose spell they show
local pressed = setmetatable({}, { __mode = "k" })
local cover = setmetatable({}, { __mode = "k" })     -- [button] = its cover texture
local covered = setmetatable({}, { __mode = "k" })   -- [button] = "range" / "mana" as the cover shows
local outOfRange = setmetatable({}, { __mode = "k" })   -- [button] = true out of range
local short = setmetatable({}, { __mode = "k" })     -- [button] = true short of resources
local greyed = setmetatable({}, { __mode = "k" })    -- [button] = true: its icon greyed here
local buttons = {}                                   -- every hooked button, in order
local hooked = false

local function PressOn()
	return M.isEnabled and M.db and M.db.pressLight
end
local function ColoursOn()
	return M.isEnabled and M.db and M.db.rangeColours
end

--------------------------------------------------------------------------------
-- The light
--------------------------------------------------------------------------------
local function ShowLight(button, on)
	local t = light[button]
	if on and not t then
		t = button:CreateTexture(nil, "OVERLAY", nil, LIGHT.SUB)
		t:SetTexture(FLAT)
		t:SetAllPoints(button)
		t:SetBlendMode("ADD")
		W.Paint(t, "selectedTrim", "vertex", LIGHT.ALPHA)
		t:Hide()
		light[button] = t
	end
	if t and t:IsShown() ~= on then
		t:SetShown(on)
	end
end

-- pressed by "key" or "mouse" (nil: let go): a mouse leaving the button lets
-- go of a mouse press only, never of a held key. Told on the bus as it
-- changes ("actionpress": button, down), Light While Pressed on or off
local function Press(button, by)
	if pressed[button] ~= by then
		pressed[button] = by
		MelloUI:Fire("actionpress", button, by ~= nil)
	end
	if by and not PressOn() then
		by = nil
	end
	if held[button] == by then
		return
	end
	held[button] = by
	ShowLight(button, by ~= nil)
end

local OnSetButtonState = Shared("SetButtonState on an action button", function(button, state)
	Press(button, state == "PUSHED" and "key" or nil)
end)
local OnMouseDown = Shared("OnMouseDown on an action button", function(button)
	Press(button, "mouse")
end, "script")
local OnMouseRelease = Shared("OnMouseUp / OnLeave on an action button", function(button)
	if pressed[button] == "mouse" then
		Press(button, nil)
	end
end, "script")
local OnHide = Shared("OnHide on an action button", function(button)
	Press(button, nil)
end, "script")

--------------------------------------------------------------------------------
-- The colours
--------------------------------------------------------------------------------
-- the cover's colour for a state: red over whatever the game drew; the deep
-- blue over the game's own pale blue (what multiplies the one into the other)
local function CoverColour(state)
	local m = MelloUI.Meaning
	if state == "range" then
		return m.actionRange[1], m.actionRange[2], m.actionRange[3]
	end
	local want, game = m.actionMana, m.gameMana
	return want[1] / game[1], want[2] / game[2], want[3] / game[3]
end

local function LayCover(button)
	local state = ColoursOn() and (outOfRange[button] and "range" or short[button] and "mana") or nil
	if covered[button] == state then
		return
	end
	covered[button] = state
	local t = cover[button]
	if not state then
		if t then
			t:Hide()
		end
		return
	end
	local icon = button.icon
	if not t then
		if not icon then
			return
		end
		t = button:CreateTexture(nil, "BACKGROUND", nil, COVER_SUB)
		t:SetTexture(FLAT)
		t:SetAllPoints(icon)
		t:SetBlendMode("MOD")
		cover[button] = t
	end
	t:SetVertexColor(CoverColour(state))
	t:Show()
end

-- the icon greyed (or not) here, written only on a change
local function Grey(button, on)
	local icon = button.icon
	if not (icon and icon.SetDesaturated and icon.IsDesaturated) then
		return
	end
	local ok, now = pcall(icon.IsDesaturated, icon)
	if not ok or Secret(now) then
		return
	end
	if on then
		if not now then
			icon:SetDesaturated(true)
		end
		greyed[button] = true
	elseif greyed[button] then
		greyed[button] = nil
		if now then
			icon:SetDesaturated(false)
		end
	end
end

-- after the game's UpdateUsable: its answer (the arguments, or asked again)
local OnUpdateUsable = Shared("UpdateUsable on an action button", function(button, _, isUsable, notEnoughMana)
	if not ColoursOn() then
		return
	end
	if isUsable == nil or notEnoughMana == nil then
		local action = button.action
		if Secret(action) or type(action) ~= "number" then
			return
		end
		local ok
		ok, isUsable, notEnoughMana = pcall(C_ActionBar.IsUsableAction, action)
		if not ok then
			return
		end
	end
	if Secret(isUsable) or Secret(notEnoughMana) then
		return   -- (cannot be told: the game's own colour stands)
	end
	short[button] = (not isUsable and notEnoughMana) and true or nil
	Grey(button, not isUsable and not notEnoughMana)
	LayCover(button)
end)

-- after the game's range indicator: out of range only when it checked
local OnRange = Shared("ActionButton_UpdateRangeIndicator", function(button, checksRange, inRange)
	if not ColoursOn() or type(button) ~= "table" or not button.icon then
		return
	end
	if Secret(checksRange) or Secret(inRange) then
		return
	end
	outOfRange[button] = (checksRange and not inRange) and true or nil
	LayCover(button)
end)

-- a button's range now (the colours switched on: the game tells it only on a
-- change), nil when it cannot be told (no target, no action)
local function ReadRange(button)
	local action = button.action
	if Secret(action) or type(action) ~= "number" or not (C_ActionBar and C_ActionBar.IsActionInRange) then
		return
	end
	local ok, inRange = pcall(C_ActionBar.IsActionInRange, action)
	if ok and not Secret(inRange) then
		outOfRange[button] = (inRange == false) and true or nil
	end
end

--------------------------------------------------------------------------------
-- Hooking the buttons (once)
--------------------------------------------------------------------------------
local function Hook(button)
	if type(button) ~= "table" or type(button.SetButtonState) ~= "function" then
		return
	end
	buttons[#buttons + 1] = button
	hooksecurefunc(button, "SetButtonState", OnSetButtonState)
	Perf.HookScript(button, "OnMouseDown", OnMouseDown)
	Perf.HookScript(button, "OnMouseUp", OnMouseRelease)
	Perf.HookScript(button, "OnLeave", OnMouseRelease)
	Perf.HookScript(button, "OnHide", OnHide)
	if type(button.UpdateUsable) == "function" then
		hooksecurefunc(button, "UpdateUsable", OnUpdateUsable)
	end
end

local function HookAll()
	if hooked then
		return
	end
	hooked = true
	for _, name in ipairs(BARS) do
		local bar = _G[name]
		local list = type(bar) == "table" and bar.actionButtons
		if type(list) == "table" then
			for _, button in ipairs(list) do
				Hook(button)
			end
		end
	end
	for _, name in ipairs(EXTRA) do
		Hook(_G[name])
	end
	if type(ActionButton_UpdateRangeIndicator) == "function" then
		hooksecurefunc("ActionButton_UpdateRangeIndicator", OnRange)
	end
end

-- everything laid again from the buttons' state (a switch moved)
local function Refresh()
	for _, button in ipairs(buttons) do
		if not PressOn() then
			Press(button, nil)
		end
		if ColoursOn() then
			if type(button.UpdateUsable) == "function" then
				ReadRange(button)
				OnUpdateUsable(button)
			end
		else
			short[button], outOfRange[button] = nil, nil
			Grey(button, false)
		end
		LayCover(button)
	end
end

-- (the light follows the palette by itself: W.Paint keeps it)

function M:OnEnable(db)
	self.db = db
	HookAll()
	Refresh()
end

function M:OnDisable()
	Refresh()
end

function M:OnSettingChanged(_, _, db)
	self.db = db
	Refresh()
end

-- (0.19.8) the light on any frame of the action bars' kind -- the Cooldown
-- Manager's icons (Modules/CooldownTweaks.lua): one light, one look
function M:Light(frame, on)
	ShowLight(frame, on and true or false)
end

-- for the tests
M.light, M.cover, M.covered, M.held, M.greyed, M.pressed = light, cover, covered, held, greyed, pressed
M.Buttons = function()
	return buttons
end
