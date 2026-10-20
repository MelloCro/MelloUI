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
-- written only when the button's state changes; a multiply ignores alpha, so
-- on a bar the Fader has faded no cover is drawn (0.21.2, the user: the faded
-- bars "still shows the highlights"; the Fader's "fade" on the bus lays them
-- again as a bar fades or comes back); the game's own icon colour
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
local Num = MelloUI.Safe.Number

local M = MelloUI:RegisterModule("ActionButtons", {
	title = "Action Buttons",
	desc = "Lights an action button while its key is held, and colours its icon by range and resources.",
	icon = "Interface\\Icons\\Ability_Warrior_Riposte",
	flavour = "See which button you press, and which spell cannot reach its target.",
	role = "adds",
	-- (not on the installer's Features step: its two columns are full, as for
	-- the Swing Timers and Discard; on by default, its switches on Bars > Action Bars > Button)
	installer = false,
	enabledByDefault = true,
	defaults = {
		pressLight = true,
		rangeColours = true,
		frames = true,
		readyFlash = true,
	},
	options = {
		{ type = "toggle", key = "frames", name = "MelloUI Frames", new = "0.25.0",
		  desc = "Every action button in MelloUI's frame: a dark iron rim with a gold line, brighter under the pointer, "
			.. "bright gold while its aura or stance is on, red out of range, a dark slot when the button is empty. "
			.. "Off: the game's own frames. The painted skin's bars keep their own (Oldschool)." },
		-- (2026-10-20, the user: the golden frame animation "to notify when something comes off cooldown")
		{ type = "toggle", key = "readyFlash", name = "Cooldown Ready Flash", new = "0.25.0",
		  desc = "When an action's cooldown runs out, a golden light runs once round its button, so you see it is "
			.. "ready again. Never for the global cooldown." },
		{ type = "toggle", key = "pressLight", name = "Light While Pressed",
		  desc = "While you hold an action button's key, or press it with the mouse, the whole button lights up in "
			.. "the colour scheme's highlight colour, so you can see which button you are pressing." },
		{ type = "toggle", key = "rangeColours", name = "Range And Resource Colours",
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
-- The frame (2026-10-20, the user's sheet, "a custom action bar ... border to fit"; ChatGPT Batch 23): MelloUI's
-- frame on every button while the painted skin is off on the action bars (Kit area "actionbars"). One texture on
-- the button's OVERLAY (under the light), a nine-slice of the set's frame (Media/Textures/Icons/frame_<state>, 128
-- texels, its band FRAME.M texels each side drawn FRAME.BAND units wide; the whole picture where the client cannot
-- cut a texture), in its state: empty (no action), active (checked: its aura or stance on), pressed (held), range
-- (out of range), hover (the pointer on it), else normal -- laid again only when that changes. The game's own frame,
-- pressed, hover and checked art (its NormalTexture, PushedTexture, HighlightTexture, CheckedTexture) unseen while
-- it shows (alpha, written once each way, never on the game's per-frame paths), back when it goes. Made with the
-- hooks: the bars show from the login, a texture a button.
--------------------------------------------------------------------------------
local FRAME = { M = 22, BAND = 5, SUB = 2,
	GAME = { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture" } }
local frameOf = setmetatable({}, { __mode = "k" })   -- [button] = its frame texture
local framed = setmetatable({}, { __mode = "k" })    -- [button] = the state it shows ("off": the game's art back)
local hover = setmetatable({}, { __mode = "k" })     -- [button] = true while the pointer is on it

local function FramesOn()
	if not (M.isEnabled and M.db and M.db.frames ~= false) then
		return false
	end
	local K = MelloUI.Kit
	return not (type(K) == "table" and type(K.IsOn) == "function" and K:IsOn("actionbars"))
end

local function FrameState(button)
	local action = button.action
	local hasAction = C_ActionBar and C_ActionBar.HasAction
	if type(action) == "number" and not Secret(action) and type(hasAction) == "function" then
		local ok, has = pcall(hasAction, action)
		if ok and not Secret(has) and not has then
			return "empty"
		end
	end
	local ok, checked = pcall(button.GetChecked, button)
	if ok and checked and not Secret(checked) then
		return "active"
	end
	if pressed[button] then
		return "pressed"
	end
	if outOfRange[button] then
		return "range"
	end
	return hover[button] and "hover" or "normal"
end

-- the game's frame art seen (true) or not
local function GameArt(button, on)
	for _, getter in ipairs(FRAME.GAME) do
		local get = button[getter]
		local tex = type(get) == "function" and get(button)
		if tex and tex.SetAlpha then
			tex:SetAlpha(on and 1 or 0)
		end
	end
end

local function LayFrame(button)
	local t = frameOf[button]
	if not FramesOn() then
		if t and framed[button] ~= "off" then
			t:Hide()
			framed[button] = "off"
			GameArt(button, true)
		end
		return
	end
	if not t then
		t = button:CreateTexture(nil, "OVERLAY", nil, FRAME.SUB)
		t:SetAllPoints(button)
		frameOf[button] = t
	end
	local state = FrameState(button)
	if framed[button] == state then
		return
	end
	if framed[button] == nil or framed[button] == "off" then
		GameArt(button, false)
		t:Show()
	end
	framed[button] = state
	t:SetTexture(W.IconPath("frame_" .. state))   -- (the set's: Media/Textures/Icons/frame_<state>)
	if t.SetTextureSliceMargins and t.SetTextureSliceMode and t.SetScale then
		local m = FRAME.M
		t:SetTextureSliceMargins(m, m, m, m)
		t:SetTextureSliceMode(Enum and Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched or 0)
		t:SetScale(FRAME.BAND / m)
	end
end

local OnFrameEnter = Shared("OnEnter on an action button (its frame)", function(button)
	hover[button] = true
	LayFrame(button)
end, "script")
local OnFrameLeave = Shared("OnLeave on an action button (its frame)", function(button)
	hover[button] = nil
	LayFrame(button)
end, "script")
local OnFrameState = Shared("SetChecked / Update on an action button (its frame)", function(button)
	LayFrame(button)
end)

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
		LayFrame(button)
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

-- (0.21.2) the button on a bar the Fader has faded now
local function OnFadedBar(button)
	local F = MelloUI.Fader
	return F and F.Faded and F:Faded(button) or false
end

local function LayCover(button)
	local state = ColoursOn() and (outOfRange[button] and "range" or short[button] and "mana") or nil
	if state and OnFadedBar(button) then
		state = nil   -- (a MOD cover ignores the bar's alpha: none while it is faded)
	end
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
	if not (ColoursOn() or FramesOn()) or type(button) ~= "table" or not button.icon then
		return
	end
	if Secret(checksRange) or Secret(inRange) then
		return
	end
	outOfRange[button] = (checksRange and not inRange) and true or nil
	LayCover(button)
	LayFrame(button)
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
-- Cooldown Ready (2026-10-20, the user: "this animation can be reused on the Action bars to notify when something
-- comes off cooldown"; the golden frame flipbook, Media/Textures/Icons/fx_cooldown, Tools/make_icons.py FB_SQUARED).
-- As a button's cooldown runs out -- the game's Clear() on its Cooldown frame or the frame's OnCooldownDone,
-- post-hooked -- a golden square runs its glint once round the button, its square on the button's edge. Only after a
-- cooldown that ran longer than READY.MIN (never the global cooldown): its start read by recency, the first SetCooldown since the last ran out
-- (its numbers never compared unless plain: they may be secret); its end the game's Clear() or the frame's
-- OnCooldownDone, on the action it began on (a zero SetCooldown ends it unseen). One texture a button, made on its
-- first flash, over the frame (OVERLAY 7); driven by MelloUI.Anim; while the button shows.
--------------------------------------------------------------------------------
local READY = { MIN = 2.5, TIME = 0.6, SIZE = 1 / 0.8, FADE = 0.85 }   -- (SIZE: the square is 0.8 of each frame)
local readyOf = setmetatable({}, { __mode = "k" })     -- [button] = { tex }: its flash
local since = setmetatable({}, { __mode = "k" })       -- [cooldown] = when it began
local cooldownOf = setmetatable({}, { __mode = "k" })  -- [cooldown] = its button

local function ReadyOn()
	return M.isEnabled and M.db and M.db.readyFlash ~= false
end

local function ReadyStep(job, u)
	local f = math.min(7, math.floor(u * 8))
	job.tex:SetTexCoord(f / 8, (f + 1) / 8, 0, 1)
	job.tex:SetAlpha(u < READY.FADE and 1 or (1 - u) / (1 - READY.FADE))
end

local function ReadyOver(job)
	job.tex:Hide()
end

local function Flash(button)
	local r = readyOf[button]
	if not r then
		local t = button:CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetTexture(W.IconPath("fx_cooldown"))
		t:SetBlendMode("ADD")
		t:SetPoint("CENTER", button, "CENTER", 0, 0)
		t:Hide()
		r = { tex = t }
		readyOf[button] = r
	end
	local w, h = Num(button:GetWidth()) or 36, Num(button:GetHeight()) or 36
	r.tex:SetSize(w * READY.SIZE, h * READY.SIZE)
	ReadyStep(r, 0)
	r.tex:Show()
	MelloUI.Anim:Drive(r, ReadyStep, READY.TIME, "linear", ReadyOver)
end

-- (the action the button holds: a page turned or another action dropped on it ends what ran there unseen)
local function ActionOf(button)
	return Num(rawget(button, "action"))
end

local OnCooldownSet = Shared("SetCooldown on an action button's cooldown (Cooldown Ready)", function(cd, _, duration)
	local d = Num(duration)
	local button = cooldownOf[cd]
	if d and d <= 0 then
		since[cd] = nil
	elseif not since[cd] and button then
		since[cd] = { at = GetTime(), action = ActionOf(button) }
	end
end)

-- the cooldown over: the game's Clear() as its action's cooldown stops being active (ActionButton_ApplyCooldown, on
-- the cooldown events: it comes before the frame's own OnCooldownDone, the user's test of 2026-10-20) or the frame's
-- OnCooldownDone, whichever first; a flash when it ran long enough on the same action
local OnCooldownEnd = Shared("Clear / OnCooldownDone on an action button's cooldown (Cooldown Ready)", function(cd)
	local began, button = since[cd], cooldownOf[cd]
	if not began then
		return
	end
	since[cd] = nil
	if button and ReadyOn() and GetTime() - began.at >= READY.MIN and began.action == ActionOf(button)
		and button:IsVisible() then
		Flash(button)
	end
end)

local function HookReady(button)
	local cd = rawget(button, "cooldown")
	if type(cd) ~= "table" or type(cd.SetCooldown) ~= "function" then
		return
	end
	cooldownOf[cd] = button
	hooksecurefunc(cd, "SetCooldown", OnCooldownSet)
	if type(cd.Clear) == "function" then
		hooksecurefunc(cd, "Clear", OnCooldownEnd)
	end
	Perf.HookScript(cd, "OnCooldownDone", OnCooldownEnd)
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
	-- (the frame) the pointer, the checked state, a new or cleared action
	Perf.HookScript(button, "OnEnter", OnFrameEnter)
	Perf.HookScript(button, "OnLeave", OnFrameLeave)
	if type(button.SetChecked) == "function" then
		hooksecurefunc(button, "SetChecked", OnFrameState)
	end
	if type(button.Update) == "function" then
		hooksecurefunc(button, "Update", OnFrameState)
	end
	HookReady(button)   -- (Cooldown Ready: its cooldown frame)
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
	-- (the frame) the painted skin's action bars on or off: the frames given way or back
	MelloUI:On("look:actionbars", function()
		for _, button in ipairs(buttons) do
			LayFrame(button)
		end
	end, "Action Buttons' frames")
	-- (0.21.2) a bar faded or back: its covers laid again (at the change only)
	MelloUI:On("fade", function()
		if ColoursOn() then
			for _, button in ipairs(buttons) do
				LayCover(button)
			end
		end
	end, "Action Buttons' covers")
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
		LayFrame(button)
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
M.light, M.cover = light, cover
M.Buttons = function()
	return buttons
end

-- (0.19.9) every bar's buttons now, read from the bars themselves (Keybind
-- Mode's: it needs them with this module off too), into `out`
function M.BarButtons(out)
	out = out or {}
	for _, name in ipairs(BARS) do
		local bar = rawget(_G, name)
		local list = type(bar) == "table" and rawget(bar, "actionButtons")
		if type(list) == "table" then
			for _, button in ipairs(list) do
				out[#out + 1] = button
			end
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- The configurator's stage (one look stage G, the Bars designer: the user's
-- pick A of bars_looks.jpg, "strips beside"): the 'actionbar' wide kind of
-- Core/ConfigPreview.lua, Bars > Action Bars. Every bar Bar Layout can set
-- (Tweaks' Which Bar: Action Bars 1 to 8, the stance and pet bars) is a strip
-- on the left; a click on one makes it the bar the Layout rows set (Which
-- Bar is the strips now) and the large bar on the right shows it as the
-- game lays it -- its rows, icons, icon size and padding from your Edit Mode
-- layout, the game's own button art (the slot, the frame, the pressed frame;
-- the end caps and the page arrows on Action Bar 1, faint while Hide Bar Art
-- / Hide Page Arrows hide them) -- with MelloUI's parts on it from the saved
-- settings: Cooldown Timers' countdown, Range And Resource Colours, Light
-- While Pressed (states Cooldown | Out of range | Pressed). Every part is
-- picked, never moved. Made with the page, never at login; no action is read
-- (the icons, the keys and the countdown are made up).
--------------------------------------------------------------------------------

do
	local CP = MelloUI.ConfigPreview
	local Fin = MelloUI.Safe.Finite
	local Stage = {
		BARS = { { 1, "Bar 1" }, { 2, "Bar 2" }, { 3, "Bar 3" }, { 4, "Bar 4" }, { 5, "Bar 5" }, { 6, "Bar 6" },
			{ 7, "Bar 7" }, { 8, "Bar 8" }, { 11, "Stance" }, { 12, "Pet" } },
		ICONS = { "Ability_Warrior_BattleShout", "Ability_CriticalStrike", "Ability_Warrior_Riposte", "Ability_Defend",
			"Ability_Warrior_ShieldWall", "Spell_Holy_DevotionAura", "Ability_GhoulFrenzy", "Spell_Nature_Regeneration",
			"Ability_Druid_ChallangingRoar", "Ability_Racial_BearForm", "Spell_Holy_SealOfProtection", "Spell_Fire_FlameBolt" },
		KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=" },
		-- the game's: a button 45, its pad 2; Camelot's end caps 154 x 95 (MainMenuBarEndCaps.xml), their paws 20
		-- over the bar's ends and 8 under it; the page arrows 17 x 14
		N = 12, SIZE = 45, CAP_W = 154, CAP_H = 95, CAP_IN = 20, CAP_DROP = 8, ARROW_W = 17, ARROW_H = 14,
		PAD = 6, GHOST = 0.3, CD_AT = 5, CD_LEFT = "4", RANGE = { [2] = true, [3] = true, [8] = true },
		STRIP_W = 124, STRIP_H = 13, STRIP_GAP = 1.5, STRIP_TOP = 28, ROOM_TOP = 34, ROOM_BOTTOM = 26,
		STATES = { { key = "cooldown", label = "Cooldown" }, { key = "range", label = "Out of range" },
			{ key = "pressed", label = "Pressed" } },
		TEXT = { pick = "Click a strip to pick a bar; click a part of it for its settings.", bars = "Your bars" },
		EMPTY = {},
		shape = {},
		parts = nil,
	}

	function Stage.DB(name)
		return MelloUI:GetModuleDB(name) or Stage.EMPTY
	end

	function Stage.Running(name)
		local m = MelloUI.modules and MelloUI.modules[name]
		return m ~= nil and m.isEnabled and true or false
	end

	-- the bar Which Bar names (Tweaks' Bar Layout)
	function Stage.Bar()
		return Num(Stage.DB("Tweaks").barLayoutBar) or 1
	end

	-- the bar's shape from the Edit Mode layout (Tweaks' Layout.BarShape's
	-- reading), the game's defaults where it says nothing
	function Stage.Shape(bar)
		local S = Enum and Enum.EditModeActionBarSetting
		local system = Enum and Enum.EditModeSystem and Enum.EditModeSystem.ActionBar
		local ok, values = false, nil
		if S and system and MelloUI.EditModeSystemSettings then
			ok, values = pcall(MelloUI.EditModeSystemSettings, MelloUI, system, bar)
		end
		values = ok and type(values) == "table" and values or Stage.EMPTY
		local shape = Stage.shape
		shape.rows = math.max(1, math.min(4, S and Num(values[S.NumRows]) or 1))
		shape.icons = math.max(1, math.min(Stage.N, S and Num(values[S.NumIcons]) or (bar >= 11 and 10 or Stage.N)))
		local size = S and Num(values[S.IconSize])
		shape.size = size and (size * 10 + 50) or 100
		shape.padding = S and Num(values[S.IconPadding]) or 2
		local vertical = Enum.ActionBarOrientation and Enum.ActionBarOrientation.Vertical
		shape.vertical = S ~= nil and vertical ~= nil and values[S.Orientation] == vertical
		return shape
	end

	-- a strip clicked: its bar is Which Bar now (the Layout rows set it)
	function Stage.Pick(strip)
		if Stage.Bar() == strip.bar then
			return
		end
		MelloUI:PlayUISound("tab")
		MelloUI:NotifySettingChanged("Tweaks", "barLayoutBar", strip.bar)
		if MelloUI.RefreshConfig then
			MelloUI:RefreshConfig()
		end
	end
	local OnStripClick = Shared("OnClick on a Bars stage strip", function(strip)
		Stage.Pick(strip)
	end, "script")

	-- the strips: a bar's name and its buttons in small (made with the stage)
	function Stage.Furnish(stage, holder)
		local title = W.Text(holder, "GameFontHighlightSmall", Stage.TEXT.bars, "mutedText")
		title:SetPoint("TOPLEFT", holder, "TOPLEFT", 10, -12)
		local line = W.Solid(holder, "BORDER", "border", 1)
		line:SetPoint("TOPLEFT", holder, "TOPLEFT", Stage.STRIP_W + 18, -10)
		line:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", Stage.STRIP_W + 18, 10)
		line:SetWidth(1)
		stage.strips = {}
		local sq = (Stage.STRIP_W - 50) / (Stage.N * 1.25)
		for i, b in ipairs(Stage.BARS) do
			local strip = CreateFrame("Button", nil, holder)
			strip:SetSize(Stage.STRIP_W, Stage.STRIP_H)
			strip:SetPoint("TOPLEFT", holder, "TOPLEFT", 8, -(Stage.STRIP_TOP + (i - 1) * (Stage.STRIP_H + Stage.STRIP_GAP)))
			strip:SetFrameLevel(holder:GetFrameLevel() + 5)
			strip.bar = b[1]
			strip.ground = W.Solid(strip, "BACKGROUND", "raisedPanel", 1)
			strip.ground:SetAllPoints(strip)
			strip.edge = CreateFrame("Frame", nil, strip)
			strip.edge:SetAllPoints(strip)
			W.Edges(strip.edge, "selectedTrim", "BORDER")
			strip.label = W.Text(strip, "GameFontHighlightSmall", b[2], "text")
			strip.label:SetPoint("LEFT", strip, "LEFT", 5, 0)
			strip.squares = {}
			for k = 1, b[1] >= 11 and 10 or Stage.N do
				local t = W.Solid(strip, "ARTWORK", "border", 1)
				t:SetSize(sq, sq)
				t:SetPoint("LEFT", strip, "LEFT", 46 + (k - 1) * sq * 1.25, 0)
				strip.squares[k] = t
			end
			strip:SetScript("OnClick", OnStripClick)
			stage.strips[i] = strip
		end
	end

	-- the strips as Which Bar stands
	function Stage.Refresh(stage)
		local bar = Stage.Bar()
		for _, strip in ipairs(stage.strips or Stage.EMPTY) do
			local on = strip.bar == bar
			strip.ground:SetShown(on)
			strip.edge:SetShown(on)
			W.Paint(strip.label, on and "selectedTrim" or "text", "text")
			for _, t in ipairs(strip.squares) do
				W.Paint(t, on and "trim" or "border", "vertex", 1)
			end
		end
	end

	-- the room right of the strips, under the state chips, over the caption
	function Stage.Room(stage)
		local w, h = Fin(stage:GetWidth()) or 0, Fin(stage:GetHeight()) or 0
		local left = Stage.STRIP_W + 26
		return left, Stage.ROOM_TOP, w - left - 8, h - Stage.ROOM_TOP - Stage.ROOM_BOTTOM
	end

	function Stage.Button(f, i)
		local b = CreateFrame("Frame", nil, f)
		b:SetSize(Stage.SIZE, Stage.SIZE)
		b.slot = b:CreateTexture(nil, "BACKGROUND")
		b.slot:SetAtlas("UI-HUD-ActionBar-IconFrame-Slot")
		b.slot:SetAllPoints(b)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetTexture("Interface\\Icons\\" .. Stage.ICONS[i])
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
		b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
		-- (Range And Resource Colours' cover, as LayCover makes it)
		b.cover = b:CreateTexture(nil, "BACKGROUND", nil, COVER_SUB)
		b.cover:SetTexture(FLAT)
		b.cover:SetAllPoints(b.icon)
		b.cover:SetBlendMode("MOD")
		b.cover:Hide()
		b.frame = b:CreateTexture(nil, "OVERLAY")
		b.frame:SetAtlas("UI-HUD-ActionBar-IconFrame")
		b.frame:SetAllPoints(b)
		b.pushed = b:CreateTexture(nil, "OVERLAY", nil, 1)
		b.pushed:SetAtlas("UI-HUD-ActionBar-IconFrame-Down")
		b.pushed:SetAllPoints(b)
		b.pushed:Hide()
		-- (Light While Pressed's light, as ShowLight makes it)
		b.light = b:CreateTexture(nil, "OVERLAY", nil, LIGHT.SUB)
		b.light:SetTexture(FLAT)
		b.light:SetAllPoints(b)
		b.light:SetBlendMode("ADD")
		W.Paint(b.light, "selectedTrim", "vertex", LIGHT.ALPHA)
		b.light:Hide()
		b.hotkey = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
		b.hotkey:SetPoint("TOPRIGHT", b, "TOPRIGHT", -3, -3)
		b.hotkey:SetJustifyH("RIGHT")
		return b
	end

	function Stage.Main(stage)
		local f = CreateFrame("Frame", nil, stage.holder)
		f:SetSize(600, 100)
		f:EnableMouse(false)
		f.buttons = {}
		for i = 1, Stage.N do
			f.buttons[i] = Stage.Button(f, i)
		end
		-- the cooldown on one button: the game's swipe, held still (no countdown of the game's or of Cooldown
		-- Timers' own hook: noCooldownCount), and Cooldown Timers' countdown drawn as its look would be
		local cdb = f.buttons[Stage.CD_AT]
		local ok, cd = pcall(CreateFrame, "Cooldown", nil, cdb, "CooldownFrameTemplate")
		if ok and cd then
			cd.noCooldownCount = true
			cd:SetAllPoints(cdb.icon)
			pcall(cd.SetHideCountdownNumbers, cd, true)
			pcall(cd.SetCooldown, cd, GetTime() - 6, 10)
			pcall(cd.Pause, cd)
			cd:Hide()
			f.cd = cd
		end
		f.timerHost = CreateFrame("Frame", nil, cdb)
		f.timerHost:SetAllPoints(cdb)
		f.timerHost:SetFrameLevel(cdb:GetFrameLevel() + 5)
		f.timer = f.timerHost:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
		f.timer:SetPoint("CENTER", cdb, "CENTER", 0, 0)
		f.timer:SetText(Stage.CD_LEFT)
		f.timer:Hide()
		f.timerFace = f.timer:GetFont()
		-- the end caps and the page arrows (Action Bar 1's)
		f.capL = f:CreateTexture(nil, "OVERLAY", nil, 5)
		f.capL:SetAtlas("ui-hud-actionbar-gryphon-left")
		f.capL:SetSize(Stage.CAP_W, Stage.CAP_H)
		f.capR = f:CreateTexture(nil, "OVERLAY", nil, 5)
		f.capR:SetAtlas("ui-hud-actionbar-gryphon-right")
		f.capR:SetSize(Stage.CAP_W, Stage.CAP_H)
		f.arrows = CreateFrame("Frame", nil, f)
		f.arrows:SetSize(Stage.ARROW_W + 14, Stage.SIZE)
		f.arrows.up = f.arrows:CreateTexture(nil, "ARTWORK")
		f.arrows.up:SetAtlas("ui-hud-actionbar-pageuparrow-up")
		f.arrows.up:SetSize(Stage.ARROW_W, Stage.ARROW_H)
		f.arrows.up:SetPoint("TOPLEFT", f.arrows, "TOPLEFT", 0, -2)
		f.arrows.down = f.arrows:CreateTexture(nil, "ARTWORK")
		f.arrows.down:SetAtlas("ui-hud-actionbar-pagedownarrow-up")
		f.arrows.down:SetSize(Stage.ARROW_W, Stage.ARROW_H)
		f.arrows.down:SetPoint("BOTTOMLEFT", f.arrows, "BOTTOMLEFT", 0, 2)
		f.arrows.page = f.arrows:CreateFontString(nil, "ARTWORK", "MelloUIFont_GameFontNormal")
		f.arrows.page:SetPoint("LEFT", f.arrows, "LEFT", Stage.ARROW_W + 3, 0)
		f.arrows.page:SetText("1")
		return f
	end

	function Stage.Paint(f, _, _, ctx)
		local state = ctx and ctx.state
		local bar = Stage.Bar()
		local shape = Stage.Shape(bar)
		local size = Stage.SIZE * shape.size / 100
		local pad = shape.padding
		local icons, rows = shape.icons, shape.rows
		local cols = math.ceil(icons / rows)
		local main = bar == 1
		local left = main and (Stage.CAP_W - Stage.CAP_IN) or Stage.PAD
		local top = Stage.PAD
		local gridW = (shape.vertical and rows or cols) * (size + pad) - pad
		local gridH = (shape.vertical and cols or rows) * (size + pad) - pad
		local ab = Stage.Running("ActionButtons") and Stage.DB("ActionButtons") or Stage.EMPTY
		local range = ab.rangeColours ~= false and ab ~= Stage.EMPTY
		local lit = ab.pressLight ~= false and ab ~= Stage.EMPTY
		local m = MelloUI.Meaning
		for i, b in ipairs(f.buttons) do
			local on = i <= icons
			b:SetShown(on)
			if on then
				local idx = i - 1
				local r, c = math.floor(idx / cols), idx % cols
				local x, y = c, r
				if shape.vertical then
					x, y = r, c
				end
				b:SetSize(size, size)
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", f, "TOPLEFT", left + x * (size + pad), -(top + y * (size + pad)))
				b.hotkey:SetText(main and Stage.KEYS[i] or "")
				local out = state == "range" and Stage.RANGE[i]
				b.cover:SetShown(out and range or false)
				if out and range then
					b.cover:SetVertexColor(m.actionRange[1], m.actionRange[2], m.actionRange[3])
				end
				-- (the game's own sign of a key out of range: its hotkey red)
				local hk = rawget(_G, out and "RED_FONT_COLOR" or "WHITE_FONT_COLOR")
				if type(hk) == "table" and hk.r then
					b.hotkey:SetVertexColor(hk.r, hk.g, hk.b)
				end
				local down = state == "pressed" and i == 1
				b.pushed:SetShown(down)
				b.frame:SetShown(not down)
				b.light:SetShown(down and lit)
			end
		end
		-- the cooldown and Cooldown Timers' countdown (its colour and size by the time left: under 5 s)
		local cdOn = state == "cooldown" and icons >= Stage.CD_AT
		if f.cd then
			f.cd:SetShown(cdOn)
		end
		local ct = Stage.DB("CooldownText")
		local timers = cdOn and Stage.Running("CooldownText") and ct.actionBars ~= false
		f.timer:SetShown(timers)
		if timers then
			local byTime = ct.colorByTime ~= false
			local px = math.max(6, size * (Num(ct.fontRatio) or 0.5) * (byTime and 1.3 or 1))
			if f.timerFace then
				f.timer:SetFont(f.timerFace, px, "OUTLINE")
			end
			-- (off: every timer white at the Text Size -- the game's white)
			local white = rawget(_G, "WHITE_FONT_COLOR")
			if byTime then
				f.timer:SetTextColor(m.cooldownSoon[1], m.cooldownSoon[2], m.cooldownSoon[3])
			elseif type(white) == "table" and white.r then
				f.timer:SetTextColor(white.r, white.g, white.b)
			end
		end
		-- Action Bar 1's end caps and page arrows: faint while MelloUI hides them (Hide Bar Art, Hide Page Arrows)
		local bars = Stage.DB("ActionBars")
		f.capL:SetShown(main)
		f.capR:SetShown(main)
		f.arrows:SetShown(main)
		local right = Stage.PAD
		if main then
			local caps = (Stage.Running("ActionBars") and bars.hideBarArt ~= false) and Stage.GHOST or 1
			local arrows = (Stage.Running("ActionBars") and bars.hidePageArrows ~= false) and Stage.GHOST or 1
			f.capL:SetAlpha(caps)
			f.capR:SetAlpha(caps)
			f.arrows:SetAlpha(arrows)
			f.capL:ClearAllPoints()
			f.capL:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", left + Stage.CAP_IN, -(top + gridH + Stage.CAP_DROP))
			f.arrows:SetSize(Stage.ARROW_W + 14, math.min(size, gridH))
			f.arrows:ClearAllPoints()
			f.arrows:SetPoint("TOPLEFT", f, "TOPLEFT", left + gridW + 4, -top)
			f.capR:ClearAllPoints()
			f.capR:SetPoint("BOTTOMLEFT", f, "TOPLEFT", left + gridW + Stage.ARROW_W + 18, -(top + gridH + Stage.CAP_DROP))
			right = Stage.ARROW_W + 18 + Stage.CAP_W
		end
		local h = main and math.max(gridH + top + Stage.CAP_DROP, Stage.CAP_H + Stage.PAD) or (gridH + top * 2)
		f:SetSize(left + gridW + right, h + Stage.PAD)
	end

	-- the parts, each picked and never moved; one that does not show takes no click
	function Stage.Part(key, label, region, extra)
		local part = { key = key, label = label, drag = false, region = function(f)
			local r = region(f)
			return r and r:IsShown() and r or nil
		end }
		for k, v in pairs(extra or Stage.EMPTY) do
			part[k] = v
		end
		return part
	end

	function Stage.Parts()
		if not Stage.parts then
			Stage.parts = {
				Stage.Part("button", "Button", function(f) return f.buttons[1] end),
				Stage.Part("cooldown", "Cooldown timer", function(f) return f.timer end, { text = true }),
				Stage.Part("caps", "End caps", function(f) return f.capL end),
				Stage.Part("arrows", "Page arrows", function(f) return f.arrows end),
				Stage.Part("keybind", "Keybind text", function(f) return f.buttons[1].hotkey end,
					{ text = true, locked = "Nothing to set yet: the game's text" }),
			}
		end
		return Stage.parts
	end

	if CP and CP.Register then
		CP.Register("actionbar", {
			place = "wide", height = 236, maxScale = 1.5,
			picks = { bars = true }, first = "bars",
			watch = { Tweaks = true, ActionBars = true, ActionButtons = true, CooldownText = true },
			states = Stage.STATES, pickText = Stage.TEXT.pick,
			Furnish = Stage.Furnish, Main = Stage.Main, Paint = Stage.Paint, Refresh = Stage.Refresh, Room = Stage.Room,
			parts = Stage.Parts,
		})
	end
	M.Stage = Stage
end
