--------------------------------------------------------------------------------
-- MelloUI - Gamepad (2.1.49, stage A of docs/plans/gamepad.md; the user, 2026-11-12: "blizzard ui changes to a
-- different controller layout when its enabled, making almost all ui elements interactable with it ... i want full
-- support")
--
-- The one system for the pad (rule 5): every MelloUI window and feature asks it, none reads the pad itself.
--
--   local G = MelloUI.Gamepad
--   G.On()                  true while the game's Gamepad UI is on (live: read when asked)
--   bus "gamepad" (on)      the mode switched (INPUT_DEVICE_INTERFACE_TRANSITION): every part that decided something
--                           by the mode at its start looks again
--   G.Window(frame, opts)   a MelloUI window the pad drives while it shows in the Gamepad UI (Kit:OwnWindow does
--                           it for every shell: KitWindow.lua). opts:
--                             shell  its Kit shell (B clicks its close button)
--                             back   fn(frame) -> true when it handled B itself (else the close button, else Hide)
--                             first  fn(frame) -> the control focused first (else the last one, else the top left)
--   G.Popup(frame, opts)    a list or flyout over a window (W.Dropdown's): the pad inside it until it hides; opts
--                           as G.Window's (back: how it closes)
--   G.Own(frame, spec)      a window that reads the pad itself while it shows on top (MelloUI_Map's map over the
--                           game's): no focus nor coins of the look; spec:
--                             keys    { [pad key] = name } bound to MelloUI's key button (spec.press gets the name),
--                                     or "click:<Button>": bound to that button's own click (the game's secure click)
--                             press   fn(name, down, dir) (dir: "EDGE"'s way, below)
--                             sticks  fn(lx, ly, rx, ry, elapsed) each frame (the left stick's, the right one's: -1..1);
--                                     the sticks are then held from the player and the camera (the stick catcher)
--                             over    true: the game's pad UI open under it (its map) is no reason to give the pad back
--                             nav     a part of the window (a frame) the D-pad walks as any window's: the names "UP",
--                                     "DOWN", "LEFT", "RIGHT", "A" (and LB / RB on its tab row) go to the navigation, the
--                                     focus in its gold frame, the right stick scrolls its page; a move with nothing
--                                     that way: press("EDGE", true, dir)
--                             walk    true: the left stick left to the player (the game's quest view: it walks you)
--                             direct  true: A (and X, keys PAD3 = "X") on a focused named button bound to its own left
--                                     (right) click, not only on a protected one (the bag window's item buttons)
--   G.Holder()              the window holding the pad's buttons now, or nil
--   bus "gamepad:focus" (c) the focus moved onto control c (a window's own prompts follow it)
--                           G.Own again on the same window (another spec: another mode of it) binds its keys at once;
--                           G.OwnKey(key, what) one of its keys anew
--   G.Skip(frame)           never focused, nor anything in it (a drag strip, a click catcher)
--   G.Focusable(frame)      focusable though not a button (a frame of ours with its own click)
--   G.Current()             the focused control (nil: none)
--   /run MelloUI.Gamepad.Dump(print)
--
-- Why MelloUI's own navigation and not the game's window manager (GamepadMode.FrameControlsManager:FrameShown, the
-- plan's first idea): that call from addon code runs the game's manager in MelloUI's run -- its frame list, its focus
-- and the binding buttons it re-scripts are all written tainted (hard rule 1: never write onto the game's tables),
-- and the game's next pad click on its own windows (a spell, an item) would then be blocked. So MelloUI keeps a
-- navigation of its own that behaves as the game's does (game: Blizzard_GamepadSmartNavigation):
--   * D-pad: the focus to the nearest control that way (a Button, a check box, a text box, a slider's track, or one
--     marked Focusable); off the edge of a scrolling page or list, the page scrolls on; on a slider, left and right
--     move its value.
--   * A: clicks the focused control (a protected button -- an item -- is bound directly, the game's own secure click;
--     a text box takes the typing). B: closes the list on top, else the window. Right stick: scrolls the page.
--   * LB / RB: the window's tabs (a W.FlatTab row), the one before or after the selected one.
--   * The focused control shows as under the pointer (its own OnEnter: its hover look and its tooltip), in a gold
--     frame, and the pad's buttons show as coins where they act (A beside the focus, B by the close button, LB / RB at
--     the tab row's ends, RS on the page that scrolls), in the pad's own faces: "The look", below.
-- The pad's buttons are taken with override bindings on an owner of MelloUI's own (never the game's binding stack):
-- only while a MelloUI window shows in the Gamepad UI, out of a fight (given back as one starts, taken again after),
-- and never while the game's own pad UI is in use (one of its windows focused, its HUD mode, its radial, its
-- action bar editor, its item cursor): the pad is the game's then, MelloUI's again once that is gone.
--
-- Nothing at login: the mode's event frame only. The owner, the key button and the driver are made at the first
-- MelloUI window shown in the Gamepad UI; the driver's OnUpdate runs only while such a window shows.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Gamepad")
local Shared = Perf.Shared

local Safe = MelloUI.Safe
local ScreenRect = Safe.ScreenRect
local pcall, type, select, rawget, math, wipe = pcall, type, select, rawget, math, wipe
local GetTime = GetTime

local G = {
	T = {
		REPEAT_START = 0.35,   -- s: a held direction's first repeat
		REPEAT = 0.09,         -- s: then every this
		LOOK = 0.15,           -- s: how often the driver checks whether the game's pad UI is in use
		STICK = 900,           -- px a second: the right stick's scroll at full tilt
		DEAD = 0.25,           -- the stick's dead zone
		STEP = 48,             -- px: a page scrolled on past its edge
		NEAR = 2.5,            -- the sideways distance's weight against the forward one
		SETTLE = 0.1,          -- s: a new tab's page laid out before the focus goes onto it
	},
	-- (the pad's key names: game, Blizzard_SharedXML/Shared/GamepadConstants.lua)
	KEYS = {
		PADDUP = "UP", PADDDOWN = "DOWN", PADDLEFT = "LEFT", PADDRIGHT = "RIGHT",
		PAD1 = "A", PAD2 = "B",
	},
}
MelloUI.Gamepad = G

local DIRS = {
	UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 },
}

-- the windows and popups the pad drives: their opts; the shown ones in order (the last on top)
local windows = setmetatable({}, { __mode = "k" })
local stack = {}
local last = setmetatable({}, { __mode = "k" })   -- [scope] = its control focused last
local S = {
	owner = nil, key = nil, driver = nil,   -- (made at the first window shown in the Gamepad UI)
	holding = false,                         -- the pad's buttons ours (override bindings set)
	focus = nil,                             -- the focused control
	bound = nil,                             -- the protected button A is bound to (nil: the key button)
	held = nil, nextAt = 0,                  -- a held direction and when it repeats
	lookAt = 0, stickBusy = false, soon = false,
	ring = nil, coins = nil, tabsBound = nil,   -- (the look: made at the first window shown in the Gamepad UI)
	catcher = nil,                           -- (the stick catcher: made at the first window reading the sticks)
}
local LayLook, HideLook   -- (the look: below)

-- a window's own pad (G.Own's spec), or nil
local function OwnOf(scope)
	local opts = scope and windows[scope]
	return opts and opts.own or nil
end

-- the frame the navigation walks for a scope: the scope, or the part of a window reading the pad itself its spec's
-- `nav` names (nil: none -- that window takes every key itself)
local function Nav(scope)
	local own = OwnOf(scope)
	if own then
		return own.nav
	end
	return scope
end

local function Num(v)
	return Safe.Number(v)
end

function G.On()
	return Safe.GamepadUI()
end

function G.Current()
	return S.focus
end

function G.Skip(frame)
	if frame then
		frame.melloPadSkip = true
	end
end

function G.Focusable(frame)
	if frame then
		frame.melloPadFocus = true
	end
end

--------------------------------------------------------------------------------
-- The game's own pad UI in use (read only: nothing of the game's is written)
--------------------------------------------------------------------------------

-- (not GamepadItemPickupCursor: the game's picture of an item on the cursor, shown whenever one is in the Gamepad UI --
-- it holds no key; counted, an item picked up in MelloUI's bag window gave the pad back, and nothing could put it
-- down: the user's report, 2026-11-12, "picking up the item with X leads to me not being able to drop it anymore")
local GAME_PAD_FRAMES = { "GamepadHudMode", "GamepadRadial", "GamepadActionBarEditFrame" }

local function Shown(frame)
	if type(frame) ~= "table" or type(frame.IsVisible) ~= "function" then
		return false
	end
	local ok, on = pcall(frame.IsVisible, frame)
	return ok and on == true
end

function G.GameHasPad()
	local mode = rawget(_G, "GamepadMode")
	local fcm = type(mode) == "table" and rawget(mode, "FrameControlsManager") or nil
	if type(fcm) == "table" and rawget(fcm, "isUIFocused") == true and Shown(rawget(fcm, "focusedFrame")) then
		return true
	end
	for i = 1, #GAME_PAD_FRAMES do
		if Shown(rawget(_G, GAME_PAD_FRAMES[i])) then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- The controls in a window: what can take the focus, where it stands
--------------------------------------------------------------------------------

local function Is(frame, kind)
	local ok, is = pcall(frame.IsObjectType, frame, kind)
	return ok and is == true
end

-- a slider's own text box is never a stop (its track is: left and right move the value)
local function SliderBox(frame)
	local parent = frame:GetParent()
	return parent and parent.box == frame and parent.Slider ~= nil
end

local function CanFocus(frame)
	if frame.melloPadFocus then
		return true
	end
	if not (Is(frame, "Button") or Is(frame, "EditBox") or Is(frame, "Slider")) then
		return false
	end
	if Is(frame, "EditBox") and SliderBox(frame) then
		return false
	end
	-- (a page's or a list's scroll bar is no stop: the stick and the D-pad past the edge scroll it)
	if Is(frame, "Slider") and frame:GetOrientation() == "VERTICAL" then
		return false
	end
	if frame.IsEnabled and not frame:IsEnabled() then
		return false
	end
	if frame.IsMouseEnabled and not frame:IsMouseEnabled() then
		return false
	end
	local alpha = Num(frame:GetEffectiveAlpha())
	return alpha ~= nil and alpha > 0.05
end

-- every focusable control shown in `root` (a hidden frame's children skipped whole), into `out` with its rect
-- (only what shows: a control inside every frame that clips it -- a page's or a list's view -- at least in part;
-- one scrolled out of it is reached by the D-pad past the edge, which scrolls on)
local found, inView, tabs = {}, {}, {}   -- (tabs: a tab row's tabs, W.FlatTab's, the selected one too)
local function Walk(cl, cb, cr, ct, ...)
	for i = 1, select("#", ...) do
		local f = select(i, ...)
		if f and not f.melloPadSkip and f:IsVisible() then
			local l, b, r, t = ScreenRect(f)
			local shows = l and r > l and t > b and l < cr and r > cl and b < ct and t > cb
			if shows and CanFocus(f) then
				found[#found + 1] = f
				inView[f] = true
				f.melloPadL, f.melloPadB, f.melloPadR, f.melloPadT = l, b, r, t
			end
			if shows and f.melloLine then
				tabs[#tabs + 1] = f
				f.melloPadL, f.melloPadB, f.melloPadR, f.melloPadT = l, b, r, t
			end
			if shows and f.melloClose and (not S.close or t > S.close.melloPadT) then
				-- (W.CloseButton: the window's close, the B coin's place -- its topmost one, not a panel's inside it)
				S.close = f
				f.melloPadL, f.melloPadB, f.melloPadR, f.melloPadT = l, b, r, t
			end
			local clips = f.DoesClipChildren and f:DoesClipChildren()
			if not clips then
				Walk(cl, cb, cr, ct, f:GetChildren())
			elseif shows then
				Walk(math.max(cl, l), math.max(cb, b), math.min(cr, r), math.min(ct, t), f:GetChildren())
			end
		end
	end
end

local HUGE = math.huge
local function Controls(scope)
	wipe(found)
	wipe(inView)
	wipe(tabs)
	S.close = nil
	if scope and scope:IsVisible() then
		Walk(-HUGE, -HUGE, HUGE, HUGE, scope:GetChildren())
	end
	return found
end
G.Controls = Controls

local function Inside(frame, scope)
	local f = frame
	while f do
		if f == scope then
			return true
		end
		f = f:GetParent()
	end
	return false
end

-- the control nearest the scope's top left corner (the way across plus the way down: a window's rail or first row,
-- not a button alone at its top right)
local function TopLeft(list, scope)
	local sl, _, _, st = ScreenRect(scope)
	local best, bestD
	for i = 1, #list do
		local c = list[i]
		local d = (c.melloPadL - (sl or 0)) + ((st or c.melloPadT) - c.melloPadT)
		if not bestD or d < bestD then
			best, bestD = c, d
		end
	end
	return best
end

-- the nearest control from `from` toward `dir`: only one lying past the focused control's edge that way (a few
-- pixels of overlap allowed); straight ahead first (one overlapping it across the way counts as straight), then the
-- gap plus the sideways distance weighted (the game's smart navigation). With none past the edge (controls laid over
-- each other), the centres decide.
local EDGE = 3
local function Toward(list, from, dir, centres)
	local d = DIRS[dir]
	local fl, fb, fr, ft = from.melloPadL, from.melloPadB, from.melloPadR, from.melloPadT
	if not fl then
		return nil
	end
	local fx, fy = (fl + fr) / 2, (fb + ft) / 2
	local best, bestScore
	for i = 1, #list do
		local c = list[i]
		if c ~= from then
			local cl, cb, cr, ct = c.melloPadL, c.melloPadB, c.melloPadR, c.melloPadT
			local cx, cy = (cl + cr) / 2, (cb + ct) / 2
			local gap
			if centres then
				gap = (cx - fx) * d[1] + (cy - fy) * d[2]
				gap = gap > 1 and gap or nil
			elseif dir == "RIGHT" then
				gap = cl >= fr - EDGE and (cl - fr) or nil
			elseif dir == "LEFT" then
				gap = cr <= fl + EDGE and (fl - cr) or nil
			elseif dir == "UP" then
				gap = cb >= ft - EDGE and (cb - ft) or nil
			else
				gap = ct <= fb + EDGE and (fb - ct) or nil
			end
			if gap then
				local side = math.abs((cx - fx) * d[2] - (cy - fy) * d[1])
				local overlap
				if d[1] == 0 then
					overlap = cl < fr and cr > fl
				else
					overlap = cb < ft and ct > fb
				end
				local score = math.max(gap, 0) + (overlap and 0 or side * G.T.NEAR)
				if not bestScore or score < bestScore then
					best, bestScore = c, score
				end
			end
		end
	end
	if not best and not centres then
		return Toward(list, from, dir, true)
	end
	return best
end
G.Toward = Toward

--------------------------------------------------------------------------------
-- Scrolling: the page a control lies on
--------------------------------------------------------------------------------

-- the ScrollFrame `frame` lies in, inside `scope` (nil: none)
local function ScrollOf(frame, scope)
	local f = frame and frame:GetParent()
	while f and f ~= scope do
		if Is(f, "ScrollFrame") then
			return f
		end
		f = f:GetParent()
	end
	if scope and Is(scope, "ScrollFrame") then
		return scope
	end
	return nil
end

-- a ScrollFrame moved by `px` screen pixels (down: positive); true when it moved
local function ScrollBy(scroll, px)
	local cur = Num(scroll:GetVerticalScroll()) or 0
	local range = Num(scroll:GetVerticalScrollRange()) or 0
	local scale = Num(scroll:GetEffectiveScale()) or 1
	local to = math.max(0, math.min(range, cur + px / (scale > 0 and scale or 1)))
	if math.abs(to - cur) < 0.5 then
		return false
	end
	scroll:SetVerticalScroll(to)
	return true
end

-- the frame from `frame` up to `scope` that scrolls by the wheel (a list of ours: the dropdown's)
local function WheelOf(frame, scope)
	local f = frame
	while f do
		if f.GetScript and f:GetScript("OnMouseWheel") and (not f.IsMouseWheelEnabled or f:IsMouseWheelEnabled()) then
			return f
		end
		if f == scope then
			return nil
		end
		f = f:GetParent()
	end
	return nil
end

-- the focused control's page moved on one step toward `dir` (UP / DOWN): "scroll" (a ScrollFrame, by pixels),
-- "wheel" (a list of ours scrolled by its wheel: one entry, its rows filled again in place) or nil (nothing to scroll)
local function ScrollOn(from, scope, dir)
	local down = dir == "DOWN"
	local scroll = ScrollOf(from, scope)
	if scroll then
		return ScrollBy(scroll, down and G.T.STEP or -G.T.STEP) and "scroll" or nil
	end
	local wheel = WheelOf(from, scope)
	if wheel then
		local ok = pcall(wheel:GetScript("OnMouseWheel"), wheel, down and -1 or 1)
		return ok and "wheel" or nil
	end
	return nil
end

-- the view `frame` shows in: the nearest frame clipping it inside `scope` (a page's ScrollFrame, a list's box)
local function ViewOf(frame, scope)
	local f = frame and frame:GetParent()
	while f and f ~= scope do
		if f.DoesClipChildren and f:DoesClipChildren() then
			return f
		end
		f = f:GetParent()
	end
	return nil
end

-- what shows in a view, as text (the controls just scanned in it: which, where, their first words), to tell whether a
-- wheel moved it (rows moved under the focus, or the same rows with other entries on them)
local function Words(c)
	for i = 1, select("#", c:GetRegions()) do
		local r = select(i, c:GetRegions())
		if r:IsObjectType("FontString") then
			local t = Safe.Text(r:GetText())
			if t and t ~= "" then
				return t
			end
		end
	end
	return ""
end

local shown = {}
local function Showing(view)
	wipe(shown)
	for i = 1, #found do
		local c = found[i]
		if Inside(c, view) then
			shown[#shown + 1] = tostring(c) .. math.floor(c.melloPadT + 0.5) .. Words(c)
		end
	end
	return table.concat(shown, "|")
end

-- a control off its page's view brought into it (its whole height, a little room around it)
local function IntoView(c, scope)
	local scroll = ScrollOf(c, scope)
	if not scroll then
		return
	end
	local _, cb, _, ct = ScreenRect(c)
	local _, sb, _, st = ScreenRect(scroll)
	if not (cb and sb) then
		return
	end
	local room = 6
	if ct > st then
		ScrollBy(scroll, -(ct - st + room))
	elseif cb < sb then
		ScrollBy(scroll, sb - cb + room)
	end
end

--------------------------------------------------------------------------------
-- The pad's buttons: taken and given back (override bindings on our own owner)
--------------------------------------------------------------------------------

local Key_OnClick   -- (below)

local function Make()
	if S.owner then
		return
	end
	S.owner = CreateFrame("Frame", nil, UIParent)
	local key = CreateFrame("Button", "MelloUIGamepadKey", UIParent)
	key:Hide()
	key:RegisterForClicks("AnyDown", "AnyUp")
	Perf.SetScript(key, "OnClick", Key_OnClick)
	S.key = key
end

local function Top()
	return stack[#stack]
end

-- A on the focused control: a protected one bound directly (the game's own click, out of a fight), else our key
-- what the client names for a key now, kept (a window reading the pad itself: Reassert's record of its keys)
local function NoteSeen(key)
	local read = rawget(_G, "GetBindingAction")
	if S.ownSeen and read then
		local ok, action = pcall(read, key, true)
		S.ownSeen[key] = ok and action or nil
	end
end

-- (a window reading the pad itself with spec.direct -- MelloUI's bag window: its slots are the game's item buttons,
-- not protected, whose use and sell the game allows only from a click of the player's) any named button the focus is
-- on clicked through the binding too, never from our code
local function Direct(c)
	if not (c and Is(c, "Button")) then
		return nil
	end
	local protected = c.IsProtected and c:IsProtected()
	if protected or (S.own and S.own.direct) then
		return c:GetName()
	end
	return nil
end

-- a pad key down now, as the client reads it (nil when it cannot tell: false)
local function KeyHeld(key)
	local fn = rawget(_G, "IsKeyDown")
	if type(fn) ~= "function" then
		return false
	end
	local ok, down = pcall(fn, key)
	return ok and down == true
end

-- (the simulator, 2026-11-12: the A that closed a question over the bag window -- its More menu's Cancel -- picked up
-- the focused slot's whole stack: the window bound A straight to the slot as the question went, and the slot takes its
-- click on the release, that same press's) a control's own click is bound only with its key up; while it is still
-- down the key stays MelloUI's (its release does nothing there), the driver binding the control at its next look
local function BindA()
	if not S.holding or InCombatLockdown() then
		return
	end
	local c = S.focus
	local name = Direct(c)
	if name then
		if S.bound ~= c then
			if KeyHeld("PAD1") then
				S.waitA = true
				return
			end
			S.waitA = nil
			SetOverrideBindingClick(S.owner, true, "PAD1", name, "LeftButton")
			S.bound = c
			NoteSeen("PAD1")
		end
	elseif S.bound then
		SetOverrideBindingClick(S.owner, true, "PAD1", "MelloUIGamepadKey", "A")
		S.bound = nil
		NoteSeen("PAD1")
	end
end

-- X (a window reading the pad itself whose keys name PAD3 "X"): the focused button's right click, its own (the bag's
-- slots: use, equip, sell at a vendor); elsewhere MelloUI's key ("X" to the window's press)
local function BindX()
	if not S.holding or InCombatLockdown() or not (S.own and S.own.keys and S.own.keys.PAD3 == "X") then
		return
	end
	local c = S.focus
	local name = Direct(c)
	if name then
		if S.boundX ~= c then
			if KeyHeld("PAD3") then
				S.waitX = true
				return
			end
			S.waitX = nil
			SetOverrideBindingClick(S.owner, true, "PAD3", name, "RightButton")
			S.boundX = c
			NoteSeen("PAD3")
		end
	elseif S.boundX then
		SetOverrideBindingClick(S.owner, true, "PAD3", "MelloUIGamepadKey", "X")
		S.boundX = nil
		NoteSeen("PAD3")
	end
end

-- a key of a window reading the pad itself bound (to MelloUI's key button, or "click:<Button>" to that button's own
-- click); what the client then names for it kept (S.ownSeen), so a key the game sets again is noticed (Reassert)
local function BindOwn(key, what)
	local button = what:match("^click:(.+)$")
	if button then
		SetOverrideBindingClick(S.owner, true, key, button, "LeftButton")
	else
		SetOverrideBindingClick(S.owner, true, key, "MelloUIGamepadKey", what)
	end
	local read = rawget(_G, "GetBindingAction")
	local ok, action = false, nil
	if read then
		ok, action = pcall(read, key, true)
	end
	S.ownSeen[key] = ok and action or nil
end

-- (the game's map under MelloUI's: the game sets its own map keys again whenever its binding stack changes -- its
-- keys would then win over the map's) a key no longer naming what it named once bound: bound again, once; one the game
-- still holds after that is left (no fight over it every look)
local function Reassert()
	local own, seen = S.own, S.ownSeen
	local read = rawget(_G, "GetBindingAction")
	if not (own and seen and read) or InCombatLockdown() then
		return
	end
	for key, what in pairs(own.keys or {}) do
		local ok, action = pcall(read, key, true)
		-- (not the shoulders while they switch a tab row)
		local onTabs = S.tabsBound and (key == "PADLSHOULDER" or key == "PADRSHOULDER")
		if ok and seen[key] ~= nil and action ~= seen[key] and not onTabs then
			BindOwn(key, what)
			-- (A or X that was on a control's own click: on it again)
			if key == "PAD1" and S.bound then
				S.bound = nil
				BindA()
			elseif key == "PAD3" and S.boundX then
				S.boundX = nil
				BindX()
			end
		end
	end
end

-- (the user's test with the pad, 2026-11-12: "when i move the cursor on the map with the left analog ... my character
-- keeps moving") the sticks held while a window reads them itself, the game's own way: a frame taking the stick input
-- whose handler does not hand it on (game: Blizzard_GamepadSoftCursor/SoftCursor.lua, its map cursor's; a handler
-- returning true hands the stick on to the player and the camera). Shown and enabled only while held (out of a fight:
-- hidden, it takes nothing); what it reads kept for the driver where the mapped state reads nothing meanwhile
local caught = { 0, 0, 0, 0 }   -- lx, ly, rx, ry
local Catcher_OnStick = Shared("OnGamePadStick on the gamepad's stick catcher (only while a MelloUI window reads the sticks)",
	function(_, stick, x, y)
		if stick == "Left" or stick == "Movement" then
			if S.own and S.own.walk then
				caught[1], caught[2] = 0, 0
				return true   -- (handed on: it walks the player)
			end
			caught[1], caught[2] = Num(x) or 0, Num(y) or 0
		elseif stick == "Right" or stick == "Camera" then
			caught[3], caught[4] = Num(x) or 0, Num(y) or 0
		end
		return false
	end, "script")

local function Catch(on)
	local f = S.catcher
	if on then
		if not f then
			f = CreateFrame("Frame", nil, UIParent)
			f:SetFrameStrata("FULLSCREEN_DIALOG")
			f:SetSize(1, 1)
			f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
			f:EnableMouse(false)
			f:Hide()
			Perf.SetScript(f, "OnGamePadStick", Catcher_OnStick)
			S.catcher = f
		end
		caught[1], caught[2], caught[3], caught[4] = 0, 0, 0, 0
		f:Show()
		if not InCombatLockdown() and f.EnableGamePadStick then
			S.catching = pcall(f.EnableGamePadStick, f, true)
		end
	elseif f and f:IsShown() then
		f:Hide()
		S.catching = false
		if not InCombatLockdown() and f.EnableGamePadStick then
			pcall(f.EnableGamePadStick, f, false)
		end
	end
end

-- a window reading the pad itself: its own keys (a "click:" one the named button's own click), its sticks held
local function TakeOwn(own)
	S.ownSeen = {}
	for key, what in pairs(own.keys or {}) do
		BindOwn(key, what)
	end
	Catch(own.sticks and true or false)
end

local function Take()
	if S.holding or #stack == 0 or InCombatLockdown() or not G.On() then
		return false
	end
	local own = OwnOf(Top())
	if not (own and own.over) and G.GameHasPad() then
		return false
	end
	Make()
	if own then
		TakeOwn(own)
	else
		for key, what in pairs(G.KEYS) do
			SetOverrideBindingClick(S.owner, true, key, "MelloUIGamepadKey", what)
		end
	end
	S.holding, S.bound, S.own = true, nil, own
	if not own then
		BindA()
	end
	MelloUI:Fire("gamepad:nav", true)   -- (the bus: a window of ours took the pad -- the bag window's strip)
	return true
end
G.Take = Take

-- true while a MelloUI window holds the pad's buttons
function G.Holding()
	return S.holding
end

-- the window holding the pad's buttons now (the one on top while they are held), or nil
function G.Holder()
	return S.holding and Top() or nil
end

-- `starting`: a fight starting (PLAYER_REGEN_DISABLED, still allowed then)
local function Release(starting)
	S.held = nil
	if not S.holding then
		return
	end
	Catch(false)   -- (the sticks the player's again at once, in a fight too: a hidden frame takes nothing)
	if InCombatLockdown() and not starting then
		return
	end
	pcall(ClearOverrideBindings, S.owner)
	S.holding, S.bound, S.boundX, S.tabsBound, S.own, S.ownSeen = false, nil, nil, nil, nil, nil
	S.waitA, S.waitX = nil, nil
	HideLook()
	MelloUI:Fire("gamepad:nav", false, starting and true or false)
end
G.Release = Release

--------------------------------------------------------------------------------
-- The focus
--------------------------------------------------------------------------------

local function RunScript(c, which)
	-- (a protected control's scripts are the game's template's: never run from here)
	if c.IsProtected and c:IsProtected() then
		return
	end
	-- (the script with its hooks: the flat controls' hover look is a hook)
	local run = rawget(_G, "ExecuteFrameScript")
	if type(run) == "function" then
		pcall(run, c, which, false)
		return
	end
	local fn = c:GetScript(which)
	if fn then
		pcall(fn, c, false)
	end
end

local function Unfocus()
	local c = S.focus
	S.focus = nil
	if S.ring then
		S.ring:Hide()
		S.coins.A:Hide()
	end
	if c then
		RunScript(c, "OnLeave")
	end
end

local function Focus(c, scope)
	if S.focus == c then
		RunScript(c, "OnEnter")   -- (its content moved under it: a list scrolled on; its look and tooltip again)
		LayLook(scope)
		return
	end
	Unfocus()
	if not c then
		return
	end
	IntoView(c, scope)
	S.focus = c
	last[scope] = c
	RunScript(c, "OnEnter")
	BindA()
	BindX()
	LayLook(scope)
	MelloUI:Fire("gamepad:focus", c)   -- (a window's own prompts follow it: the bag window's)
end
G.Focus = Focus

-- the control a scope starts on: its own pick, the one focused last, else the top left
local function First(scope)
	local list = Controls(scope)
	if #list == 0 then
		return nil
	end
	local opts = windows[scope]
	local pick = opts and opts.first and opts.first(scope)
	if not (pick and inView[pick]) then
		pick = last[scope]
		if not (pick and inView[pick]) then
			pick = nil
		end
	end
	return pick or TopLeft(list, scope)
end

-- the focus still valid (showing in the scope on top: in its controls just scanned), else the scope's first
local function Valid(scope)
	local nav = Nav(scope)
	if scope and not nav then
		-- (a window reading the pad itself, no part of it walked: no focus, no look)
		Unfocus()
		HideLook()
		return nil
	end
	scope = nav
	Controls(scope)
	local c = S.focus
	if c and inView[c] then
		return c
	end
	local f = First(scope)
	Focus(f, scope)
	return f
end

--------------------------------------------------------------------------------
-- The look (the user's picks of BuildData/output/gamepad_sketch, 2026-11-12: "1. a, 2. 1 b"): the focus in a gold
-- frame -- 2 px of selectedTrim RING_OUT outside the control, MelloUI.Shade's soft light of the same gold round it --
-- and the pad's buttons as coins (badge_disc in innerPanel, badge_edge in selectedTrim, the face in text: a letter,
-- or a shape of MelloUI's icon set; a bumper or trigger on a pill) where they act: A beside the focused control (its
-- left, else its right where the left holds another control, else inside its right end), B under the window's close
-- button, LB / RB at the ends of its tab row (and they switch its tabs), RS at the top of the page that scrolls. The
-- faces follow the pad in use (G.Style). One frame and one set of coins for every window, made at the first window
-- shown in the Gamepad UI, laid on the one on top; shown only while the pad is MelloUI's.
--------------------------------------------------------------------------------

local COIN, PILL_W, RING_OUT, GAP = 16, 32, 3, 5
-- a coin's least size on the screen, in pixels: the game's own prompts' (the map test in game, 2026-11-12: at 16 units
-- a 1440p screen drew a coin 8 to 12 px, its ring -- 5/64 of it -- under a pixel, its dark disc lost on dark ground)
local COIN_PX = 20
local coinSet = setmetatable({}, { __mode = "k" })

-- a coin scaled up to COIN_PX on its parent (never down): after each SetCoin and each move onto another frame
local function FitCoin(c)
	local Icons = rawget(MelloUI, "Icons")
	local parent = c:GetParent()
	local k = 1
	if parent and type(Icons) == "table" and Icons.FloorScale then
		k = math.max(1, Num(Icons.FloorScale(parent, COIN, COIN_PX)) or 1)
	end
	if c.melloFit ~= k then
		c.melloFit = k
		c:SetScale(k)
	end
end

-- (the UI's scale, a setting -- a window's own scale -- or a place changed: every coin fitted again)
local function FitCoins()
	for c in pairs(coinSet) do
		FitCoin(c)
	end
end
MelloUI:On("scale", FitCoins, "Gamepad: coins")
MelloUI:On("setting", FitCoins, "Gamepad: coins")
MelloUI:On("mover", FitCoins, "Gamepad: coins")

-- the pad's faces by its label style (the game's own prompts read it from C_GamePad's mapped state): Letters (Xbox and
-- most pads), Shapes (PlayStation), Reverse (Nintendo: A and B, X and Y the other way); "@name": a shape
local FACES = {
	Letters = { PAD1 = "A", PAD2 = "B", PAD3 = "X", PAD4 = "Y", PADLSHOULDER = "LB", PADRSHOULDER = "RB",
		PADLTRIGGER = "LT", PADRTRIGGER = "RT" },
	Shapes = { PAD1 = "@cross", PAD2 = "@circle", PAD3 = "@square", PAD4 = "@triangle", PADLSHOULDER = "L1",
		PADRSHOULDER = "R1", PADLTRIGGER = "L2", PADRTRIGGER = "R2" },
	Reverse = { PAD1 = "B", PAD2 = "A", PAD3 = "Y", PAD4 = "X", PADLSHOULDER = "L", PADRSHOULDER = "R",
		PADLTRIGGER = "ZL", PADRTRIGGER = "ZR" },
}
local PILLS = { PADLSHOULDER = true, PADRSHOULDER = true, PADLTRIGGER = true, PADRTRIGGER = true }
local STICKS = { PADLSTICK = "L", PADRSTICK = "R" }
local ARMS = { PADDUP = 0, PADDLEFT = math.pi / 2, PADDDOWN = math.pi, PADDRIGHT = -math.pi / 2 }
G.FACES = FACES

-- a pad's label style, or nil
local function StyleOf(C, id)
	local ok, state = pcall(C.GetDeviceMappedState, id)
	local style = ok and type(state) == "table" and Safe.Text(state.labelStyle)
	return style and FACES[style] and style or nil
end

-- the pad in use's label style: the active pad's (as the game's own prompts read it); none active -- after a reload,
-- before the pad is touched, the coins read A / B on a PlayStation pad (the test in game, 2026-11-12) -- a connected
-- pad's, else the last one seen, else "Letters"
local lastStyle
function G.Style()
	local C = rawget(_G, "C_GamePad")
	if type(C) == "table" and C.GetActiveDeviceID and C.GetDeviceMappedState then
		local okID, id = pcall(C.GetActiveDeviceID)
		local style = StyleOf(C, okID and Num(id) or nil)
		if not style and C.GetAllDeviceIDs then
			local okAll, ids = pcall(C.GetAllDeviceIDs)
			if okAll and type(ids) == "table" then
				for i = 1, #ids do
					style = StyleOf(C, Num(ids[i]))
					if style then
						break
					end
				end
			end
		end
		if style then
			lastStyle = style
			return style
		end
	end
	return lastStyle or "Letters"
end

-- (the test in game, 2026-11-12: Dark Mode at its Brightness 0.2 dimmed the coins on the bars to a fifth -- their gold
-- ring dark brown, lost) the prompts and the focus frame are signals, never a surface: full brightness as words are
-- (Modules/DarkMode.lua's M.Signal), marked before they are painted
local function Signal(tex, key, how, alpha)
	local modules = rawget(MelloUI, "modules")
	local dark = type(modules) == "table" and modules.DarkMode
	if type(dark) == "table" and dark.Signal then
		dark.Signal(tex, true)
	end
	MelloUI.Widgets.Paint(tex, key, how, alpha)
end

local function Coin()
	local W = MelloUI.Widgets
	local c = CreateFrame("Frame", nil, UIParent)
	c:EnableMouse(false)
	c:Hide()
	c.disc = c:CreateTexture(nil, "OVERLAY", nil, 1)
	c.edge = c:CreateTexture(nil, "OVERLAY", nil, 2)
	c.shape = c:CreateTexture(nil, "OVERLAY", nil, 3)
	c.disc:SetAllPoints(c)
	c.edge:SetAllPoints(c)
	c.shape:SetPoint("CENTER", c, "CENTER", 0, 0)
	c.shape:SetSize(COIN, COIN)
	Signal(c.disc, "innerPanel", "vertex", 1)
	Signal(c.edge, "selectedTrim", "vertex", 1)
	Signal(c.shape, "text", "vertex", 1)
	c.label = W.Text(c, "GameFontHighlightSmall", nil, "text")
	c.label:SetDrawLayer("OVERLAY", 7)   -- (over the disc and its edge)
	c.label:SetJustifyH("CENTER")
	c.label:SetJustifyV("MIDDLE")
	c.label:SetPoint("CENTER", c, "CENTER", 0, 0)
	coinSet[c] = true
	return c
end

-- a coin showing the pad's `key` (PAD1, PADLSHOULDER, PADDUP, PADRSTICK ...) in the pad's faces
function G.SetCoin(c, key)
	local style = G.Style()
	FitCoin(c)
	if c.key == key and c.style == style then
		return
	end
	c.key, c.style = key, style
	local Icons = MelloUI.Icons
	local pill = PILLS[key]
	local w = pill and PILL_W or COIN
	c:SetSize(w, COIN)
	Icons.Set(c.disc, pill and "pad_pill_disc" or "badge_disc", w)
	Icons.Set(c.edge, pill and "pad_pill_edge" or "badge_edge", w)
	local face = FACES[style][key]
	local shape, words
	if STICKS[key] then
		shape, words = "pad_stick", STICKS[key]
	elseif ARMS[key] then
		shape = "pad_arrow"
	elseif key == "DIRPAD" then
		shape = "pad_dpad"   -- (the whole D-pad: its up and down, MelloUI Map's quest column)
	elseif face and face:sub(1, 1) == "@" then
		shape = "pad_" .. face:sub(2)
	else
		words = face or key
	end
	if shape then
		Icons.Set(c.shape, shape, COIN)
		c.shape:SetRotation(ARMS[key] or 0)
		c.shape:Show()
	else
		c.shape:Hide()
	end
	c.label:SetText(words or "")
end
G.Coin = Coin

local function MakeLook()
	if S.ring then
		return
	end
	local W = MelloUI.Widgets
	local ring = CreateFrame("Frame", nil, UIParent)
	ring:EnableMouse(false)
	ring:Hide()
	local inner = CreateFrame("Frame", nil, ring)
	inner:SetPoint("TOPLEFT", ring, "TOPLEFT", 1, -1)
	inner:SetPoint("BOTTOMRIGHT", ring, "BOTTOMRIGHT", -1, 1)
	for _, f in ipairs({ ring, inner }) do
		for _, edge in ipairs(W.Edges(f, "selectedTrim", "OVERLAY")) do
			Signal(edge, "selectedTrim", "fill", 1)   -- (painted again, now a signal)
		end
	end
	local Shade = rawget(MelloUI, "Shade")
	if type(Shade) == "table" and Shade.Band then
		ring.glow = Shade:Band(ring, { colour = "selectedTrim", alpha = 0.5, feather = 6, blend = "ADD", hollow = true })
		ring.glow:Anchor(ring, 0, 0)
	end
	S.ring = ring
	S.coins = { A = Coin(), B = Coin(), LB = Coin(), RB = Coin(), RS = Coin() }
	G.SetCoin(S.coins.A, "PAD1")
	G.SetCoin(S.coins.B, "PAD2")
	G.SetCoin(S.coins.LB, "PADLSHOULDER")
	G.SetCoin(S.coins.RB, "PADRSHOULDER")
	G.SetCoin(S.coins.RS, "PADRSTICK")
end

-- a piece of the look onto `host` (the scope on top, or the focused control), over `level`
local function Onto(f, host, level)
	if f:GetParent() ~= host then
		f:SetParent(host)
	end
	if coinSet[f] then
		FitCoin(f)
	end
	f:SetFrameStrata(host:GetFrameStrata())
	f:SetFrameLevel(math.min(level, 9000))
	f:ClearAllPoints()
end

HideLook = function()
	if S.ring then
		S.ring:Hide()
		for _, c in pairs(S.coins) do
			c:Hide()
		end
	end
end
G.HideLook = HideLook

-- the shoulders bound while the scope on top has a tab row (LB / RB switch it), given back without one
local function BindTabs(on)
	if not S.holding or InCombatLockdown() or S.tabsBound == on then
		return
	end
	S.tabsBound = on
	if on then
		SetOverrideBindingClick(S.owner, true, "PADLSHOULDER", "MelloUIGamepadKey", "LB")
		SetOverrideBindingClick(S.owner, true, "PADRSHOULDER", "MelloUIGamepadKey", "RB")
	else
		-- (a window reading the pad itself gets its own shoulders back)
		local keys = S.own and S.own.keys
		for _, key in ipairs({ "PADLSHOULDER", "PADRSHOULDER" }) do
			if keys and keys[key] then
				BindOwn(key, keys[key])
			else
				SetOverrideBinding(S.owner, true, key, nil)
			end
		end
	end
end

-- a box (screen units) is free: inside the scope, over no control but `except`
local function FreeBox(scope, except, l, b, r, t)
	local sl, sb, sr, st = ScreenRect(scope)
	if not sl or l < sl or r > sr or b < sb or t > st then
		return false
	end
	for i = 1, #found do
		local o = found[i]
		if o ~= except and o.melloPadL < r and o.melloPadR > l and o.melloPadB < t and o.melloPadT > b then
			return false
		end
	end
	return true
end

-- a box (screen units) `w` x `h` beside the control on `side` is free: inside the scope, over no other control
local function Free(c, scope, side, w, h)
	local cy = (c.melloPadB + c.melloPadT) / 2
	local l = side == "left" and (c.melloPadL - GAP - w) or (c.melloPadR + GAP)
	return FreeBox(scope, c, l, cy - h / 2, l + w, cy + h / 2)
end

-- LB / RB at the ends of the tab row (`firstTab`, `lastTab` its tabs): outside them where that is free. LB, the row's left
-- taken (the test in game, 2026-11-12: MelloUI's map's rail stands at its row's left -- the L1 coin lay on the rail's
-- first button; its search box above), over that end, else beside RB after the row ("L1 R1"); where nothing is free,
-- inside the row's ends
local function TabCoins(lb, rb, firstTab, lastTab, scope, scale)
	local k = (lb.melloFit or 1) * scale
	local w, h = PILL_W * k, COIN * k
	local fy = (firstTab.melloPadB + firstTab.melloPadT) / 2
	local ly = (lastTab.melloPadB + lastTab.melloPadT) / 2
	local fl, lr = firstTab.melloPadL, lastTab.melloPadR
	local rbOut = FreeBox(scope, nil, lr + 4, ly - h / 2, lr + 4 + w, ly + h / 2)
	if FreeBox(scope, nil, fl - 4 - w, fy - h / 2, fl - 4, fy + h / 2) then
		lb:SetPoint("RIGHT", firstTab, "LEFT", -4, 0)
	elseif FreeBox(scope, nil, fl, firstTab.melloPadT + 2, fl + w, firstTab.melloPadT + 2 + h) then
		lb:SetPoint("BOTTOMLEFT", firstTab, "TOPLEFT", 0, 2)
	elseif FreeBox(scope, nil, lr + 4, ly - h / 2, lr + 8 + 2 * w, ly + h / 2) then
		lb:SetPoint("LEFT", lastTab, "RIGHT", 4, 0)
		rb:SetPoint("LEFT", lb, "RIGHT", 4, 0)
		return
	else
		lb:SetPoint("LEFT", firstTab, "LEFT", 2, 0)
	end
	if rbOut then
		rb:SetPoint("LEFT", lastTab, "RIGHT", 4, 0)
	else
		rb:SetPoint("RIGHT", lastTab, "RIGHT", -2, 0)
	end
end

-- the frame round the focus and the coins where they act, on the scope on top (scanned again first)
LayLook = function(scope)
	scope = Nav(scope)
	if not (S.holding and scope) then
		HideLook()
		return
	end
	MakeLook()
	Controls(scope)   -- (the scope as it now stands: the focus may have scrolled its page into view)
	local c, coins = S.focus, S.coins
	local base = Num(scope:GetFrameLevel()) or 0
	local scale = Num(scope:GetEffectiveScale()) or 1
	if c and c.melloPadL then
		-- (the frame and A ride on the control itself: hidden with it, clipped by its page's view; a protected one's
		-- -- an item's -- on the window)
		local host = (c.IsProtected and c:IsProtected()) and scope or c
		local level = (Num(c:GetFrameLevel()) or base) + 8
		Onto(S.ring, host, level)
		S.ring:SetPoint("TOPLEFT", c, "TOPLEFT", -RING_OUT, RING_OUT)
		S.ring:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", RING_OUT, -RING_OUT)
		S.ring:Show()
		local a = coins.A
		G.SetCoin(a, "PAD1")
		Onto(a, host, level + 1)
		local k = a.melloFit or 1
		local w, h = COIN * k * scale + RING_OUT, COIN * k * scale
		if Free(c, scope, "left", w, h) then
			a:SetPoint("RIGHT", c, "LEFT", -GAP - RING_OUT, 0)
		elseif Free(c, scope, "right", w, h) then
			a:SetPoint("LEFT", c, "RIGHT", GAP + RING_OUT, 0)
		else
			a:SetPoint("RIGHT", c, "RIGHT", -GAP, 0)
		end
		a:Show()
	else
		S.ring:Hide()
		coins.A:Hide()
	end
	-- B: under the close button; a list's at its top right; a window without one at its own top right
	-- (none on the part of a window reading the pad itself: its own prompts say what B does there)
	local b = coins.B
	local opts = windows[scope]
	local close = S.close or (opts and opts.shell and opts.shell.close)
	if opts then
		G.SetCoin(b, "PAD2")
		Onto(b, scope, base + 40)
		if close and close:IsVisible() then
			b:SetPoint("TOP", close, "BOTTOM", 0, -3)
		elseif opts.popup then
			b:SetPoint("LEFT", scope, "TOPRIGHT", 4, -COIN)
		else
			b:SetPoint("TOPRIGHT", scope, "TOPRIGHT", -8, -8)
		end
		b:Show()
	else
		b:Hide()
	end
	-- LB / RB: the tab row's ends
	local lb, rb = coins.LB, coins.RB
	if #tabs >= 2 then
		table.sort(tabs, function(x, y) return x.melloPadL < y.melloPadL end)
		G.SetCoin(lb, "PADLSHOULDER")
		G.SetCoin(rb, "PADRSHOULDER")
		Onto(lb, scope, base + 40)
		Onto(rb, scope, base + 40)
		TabCoins(lb, rb, tabs[1], tabs[#tabs], scope, scale)
		lb:Show()
		rb:Show()
		BindTabs(true)
	else
		lb:Hide()
		rb:Hide()
		BindTabs(false)
	end
	-- RS: the top of the page the focus scrolls in (while it can scroll)
	local rs = coins.RS
	local scroll = c and ScrollOf(c, scope)
	if scroll and (Num(scroll:GetVerticalScrollRange()) or 0) > 0 then
		G.SetCoin(rs, "PADRSTICK")
		Onto(rs, scope, base + 40)
		rs:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -2, -2)
		rs:Show()
	else
		rs:Hide()
	end
end
G.LayLook = LayLook

-- LB / RB: the tab before or after the selected one in the scope on top's tab row (the selected one: disabled, as
-- W.FlatTab's select makes it); the focus then on the new page, under the tab
function G.Tab(step)
	local scope = Nav(Top())
	if not scope then
		return
	end
	Controls(scope)
	if #tabs < 2 then
		return
	end
	table.sort(tabs, function(x, y) return x.melloPadL < y.melloPadL end)
	local at
	for i = 1, #tabs do
		if not tabs[i]:IsEnabled() then
			at = i
		end
	end
	local to = tabs[(at or 0) + step]
	if not to then
		return
	end
	to:Click("LeftButton")
	-- (the new page lays itself out over a frame or two: then the focus on its first control under the tab)
	Perf.C_Timer.After(G.T.SETTLE, function()
		local top = Nav(Top())
		if top ~= scope or not S.holding then
			return
		end
		local list = Controls(top)
		local l, b, r, t = ScreenRect(to)
		to.melloPadL, to.melloPadB, to.melloPadR, to.melloPadT = l, b, r, t
		local c = l and Toward(list, to, "DOWN") or nil
		if c then
			Focus(c, top)
		else
			Valid(top)
		end
	end)
end

--------------------------------------------------------------------------------
-- The buttons' work
--------------------------------------------------------------------------------

local function StepSlider(c, dir)
	local ok, v = pcall(c.GetValue, c)
	local lo, hi = c:GetMinMaxValues()
	local step = Num(c:GetValueStep()) or 0
	v, lo, hi = Num(ok and v), Num(lo), Num(hi)
	if not (v and lo and hi) then
		return
	end
	if step <= 0 then
		step = (hi - lo) / 20
	end
	c:SetValue(math.max(lo, math.min(hi, v + (dir == "RIGHT" and step or -step))))
end

function G.Move(dir)
	local top = Top()
	local scope = Nav(top)
	if not scope then
		return
	end
	local from = Valid(scope)
	if not from then
		return
	end
	if (dir == "LEFT" or dir == "RIGHT") and Is(from, "Slider") then
		StepSlider(from, dir)
		return
	end
	local list = found   -- (Valid has just scanned the scope)
	local to = Toward(list, from, dir)
	local view = (dir == "UP" or dir == "DOWN") and ViewOf(from, scope)
	if view and not (to and Inside(to, view)) then
		-- past the edge of the page or list the focus is in: it scrolls on before the focus leaves it (a page a step
		-- at a time until the next control shows; a list of ours one entry -- its rows moved under the focus, or the
		-- same row frame with the next entry on it, which stays focused); at its end the focus moves on out of it
		for _ = 1, 8 do
			local before = Showing(view)
			local how = ScrollOn(from, scope, dir)
			if not how then
				break
			end
			list = Controls(scope)
			if how == "wheel" and Showing(view) == before then
				break   -- (the list's end: nothing moved)
			end
			local ahead = inView[from] and Toward(list, from, dir) or nil
			if ahead and Inside(ahead, view) then
				to = ahead
				break
			end
			if how == "wheel" or not inView[from] then
				to = inView[from] and from or nil
				break
			end
		end
		if not to then
			Focus(inView[from] and from or First(scope), scope)
			return
		end
	end
	if to then
		Focus(to, scope)
	else
		-- (nothing that way in the part a window reading the pad itself lets walk: its own say -- the map's column's
		-- left edge, the map beside it)
		local own = OwnOf(top)
		if own and own.press then
			own.press("EDGE", true, dir)
		end
	end
end

function G.Press()
	local scope = Top()
	local c = scope and Valid(scope)
	if not c then
		return
	end
	if Is(c, "EditBox") then
		c:SetFocus()
	elseif Is(c, "Button") then
		c:Click("LeftButton")
	elseif Is(c, "Slider") then
		return
	else
		local down, up = c:GetScript("OnMouseDown"), c:GetScript("OnMouseUp")
		if down then
			pcall(down, c, "LeftButton")
		end
		if up then
			pcall(up, c, "LeftButton")
		end
	end
end

function G.Back()
	local scope = Top()
	if not scope then
		return
	end
	-- (a text box typed in lets go first)
	local c = S.focus
	if c and Is(c, "EditBox") and c:HasFocus() then
		c:ClearFocus()
		return
	end
	local opts = windows[scope] or {}
	if opts.back and opts.back(scope) then
		return
	end
	local shell = opts.shell
	-- (as Escape: the window's own steps first -- its search's text, its cog panel, a picked part -- one a press)
	if shell and shell.steps then
		local ok, undone = pcall(shell.steps)
		if ok and undone then
			return
		end
	end
	local close = shell and shell.close
	if close and close:IsVisible() and close:IsEnabled() then
		close:Click("LeftButton")
		return
	end
	scope:Hide()
end

-- the names the navigation takes for a window reading the pad itself that lets a part of it be walked (spec.nav)
local NAV_NAMES = { UP = true, DOWN = true, LEFT = true, RIGHT = true, A = true, LB = true, RB = true }

Key_OnClick = Shared("OnClick on the gamepad's key button", function(_, what, down)
	local own = S.own
	if own and not (own.nav and NAV_NAMES[what]) then
		-- (a window reading the pad itself: its own press)
		if own.press then
			own.press(what, down and true or false)
		end
		return
	end
	if DIRS[what] then
		if down then
			S.held, S.nextAt = what, GetTime() + G.T.REPEAT_START
			G.Move(what)
		elseif S.held == what then
			S.held = nil
		end
	elseif down and what == "A" then
		G.Press()
	elseif down and what == "B" then
		G.Back()
	elseif down and (what == "LB" or what == "RB") then
		G.Tab(what == "LB" and -1 or 1)
	end
end, "script")

--------------------------------------------------------------------------------
-- The driver: while a MelloUI window shows in the Gamepad UI (a held direction's repeat, the right stick, the
-- game's pad UI noticed)
--------------------------------------------------------------------------------

-- the sticks as the game's own axis bindings read them (game: InputAxisBinding.lua): the left one by its config name
-- "Movement", the right one "Camera" -> lx, ly, rx, ry (-1..1; 0 unread)
local function Sticks()
	local lx, ly, rx, ry = 0, 0, 0, 0
	local C = rawget(_G, "C_GamePad")
	local ok, state = false, nil
	if type(C) == "table" and C.GetDeviceMappedState and C.StickIndexToConfigName then
		ok, state = pcall(C.GetDeviceMappedState)
	end
	if not (ok and type(state) == "table" and type(state.sticks) == "table") then
		state = { stickCount = 0 }
	end
	for i = 1, (Num(state.stickCount) or 0) do
		local okName, name = pcall(C.StickIndexToConfigName, i - 1)
		local stick = state.sticks[i]
		if okName and type(stick) == "table" then
			if name == "Movement" then
				lx, ly = Num(stick.x) or 0, Num(stick.y) or 0
			elseif name == "Camera" then
				rx, ry = Num(stick.x) or 0, Num(stick.y) or 0
			end
		end
	end
	-- (while the catcher holds them, what it was told where the mapped state says nothing)
	if S.catcher and S.catcher:IsShown() then
		if lx == 0 and ly == 0 then
			lx, ly = caught[1], caught[2]
		end
		if rx == 0 and ry == 0 then
			rx, ry = caught[3], caught[4]
		end
	end
	return lx, ly, rx, ry
end

-- the right stick's height (the page scroll)
local function Stick()
	local _, _, _, ry = Sticks()
	return ry
end

-- the right stick: the focused control's page in `scope` (up: toward its top)
local function PageStick(scope, elapsed)
	local y = Stick()
	if math.abs(y) > G.T.DEAD and scope then
		local c = S.focus or scope
		local scroll = ScrollOf(c, scope)
		if scroll then
			ScrollBy(scroll, -y * G.T.STICK * (elapsed or 0))
			S.stickBusy = true
		end
	elseif S.stickBusy then
		-- (the stick let go: a focus scrolled out of view moves to the nearest one in it)
		S.stickBusy = false
		local c = S.focus
		local scroll = c and ScrollOf(c, scope)
		if scroll then
			local _, cb, _, ct = ScreenRect(c)
			local _, sb, _, st = ScreenRect(scroll)
			if cb and sb and (ct > st or cb < sb) then
				local list = Controls(scope)
				local best, bestD
				for i = 1, #list do
					local o = list[i]
					if o.melloPadT <= st and o.melloPadB >= sb then
						local dd = math.abs((o.melloPadB + o.melloPadT) / 2 - (cb + ct) / 2)
						if not bestD or dd < bestD then
							best, bestD = o, dd
						end
					end
				end
				if best then
					Focus(best, scope)
				end
			end
		end
	end
end

local Driver_OnUpdate = Shared("OnUpdate on the gamepad's driver (only while a MelloUI window shows in the Gamepad UI)",
	function(_, elapsed)
		local now = GetTime()
		if now >= S.lookAt then
			S.lookAt = now + G.T.LOOK
			-- (A or X let go since a focus came under it: the control's own click bound now -- BindA)
			if S.waitA and not KeyHeld("PAD1") then
				S.waitA = nil
				BindA()
			end
			if S.waitX and not KeyHeld("PAD3") then
				S.waitX = nil
				BindX()
			end
			if S.holding and not (S.own and S.own.over) and G.GameHasPad() then
				Unfocus()
				Release()
			elseif not S.holding and Take() then
				Valid(Top())
			elseif S.holding and S.focus and not S.focus:IsVisible() then
				-- (its page changed under it: a tab, a section folded)
				Unfocus()
				Valid(Top())
			elseif S.holding and S.own then
				Reassert()
			end
		end
		if not S.holding then
			return
		end
		local own = S.own
		if own then
			-- (a window reading the pad itself: the sticks to it; a held direction in the part it lets walk)
			if own.nav and S.held and now >= S.nextAt then
				S.nextAt = now + G.T.REPEAT
				G.Move(S.held)
			end
			if own.nav then
				PageStick(own.nav, elapsed)   -- (the right stick scrolls the part's page)
			end
			if own.sticks then
				local lx, ly, rx, ry = Sticks()
				own.sticks(lx, ly, rx, ry, elapsed or 0)
			end
			return
		end
		if S.held and now >= S.nextAt then
			S.nextAt = now + G.T.REPEAT
			G.Move(S.held)
		end
		PageStick(Top(), elapsed)
	end, "script")

local events
local function Driving(on)
	if on then
		if not S.driver then
			S.driver = CreateFrame("Frame")
		end
		if not S.driver:GetScript("OnUpdate") then
			S.lookAt = 0
			Perf.SetScript(S.driver, "OnUpdate", Driver_OnUpdate)
			events:RegisterEvent("PLAYER_REGEN_DISABLED")
			events:RegisterEvent("PLAYER_REGEN_ENABLED")
		end
	elseif S.driver and S.driver:GetScript("OnUpdate") then
		Perf.SetScript(S.driver, "OnUpdate", nil)
		events:UnregisterEvent("PLAYER_REGEN_DISABLED")
		events:UnregisterEvent("PLAYER_REGEN_ENABLED")
	end
end

--------------------------------------------------------------------------------
-- The stack of shown windows and popups
--------------------------------------------------------------------------------

local function Index(frame)
	for i = #stack, 1, -1 do
		if stack[i] == frame then
			return i
		end
	end
	return nil
end

-- the window on top reads the pad another way than the keys now bound (one reading it itself over one MelloUI drives,
-- or the other way round): the keys given back and taken again for it (out of a fight)
local function Retake()
	if S.holding and S.own ~= OwnOf(Top()) and not InCombatLockdown() then
		Release()
		Take()
	end
end

local function Push(frame)
	if not G.On() then
		return
	end
	local at = Index(frame)
	if at then
		table.remove(stack, at)
	end
	stack[#stack + 1] = frame
	Make()
	Driving(true)
	-- (focused on the next frame: the window lays itself out in its own OnShow, which may come after this one)
	if not S.soon then
		S.soon = true
		Perf.C_Timer.After(0, function()
			S.soon = false
			local top = Top()
			Retake()
			if top and (Take() or S.holding) then
				Valid(top)
			end
		end)
	end
end

local function Pop(frame)
	local at = Index(frame)
	if not at then
		return
	end
	table.remove(stack, at)
	local c = S.focus
	if c and Inside(c, frame) then
		Unfocus()
	end
	if #stack == 0 then
		Unfocus()
		Release()
		Driving(false)
	else
		Retake()
		if S.holding then
			Valid(Top())
		end
	end
end
G.Pop = Pop

local Window_OnShow = Shared("OnShow on a window the gamepad drives", function(frame)
	Push(frame)
end, "script")

local Window_OnHide = Shared("OnHide on a window the gamepad drives", function(frame)
	Pop(frame)
end, "script")

local hooked = setmetatable({}, { __mode = "k" })
local function Hook(frame)
	if not hooked[frame] then
		hooked[frame] = true
		Perf.HookScript(frame, "OnShow", Window_OnShow)
		Perf.HookScript(frame, "OnHide", Window_OnHide)
	end
end

function G.Window(frame, opts)
	if not frame then
		return
	end
	windows[frame] = opts or {}
	Hook(frame)
	if frame:IsVisible() then
		Push(frame)
	end
end

-- (the user, 2026-11-12, MelloUI's map over the game's from the Start wheel: "i cant even move the cursor with left
-- analog, nor zoom in or out normally" -- the window's own navigation had taken the buttons, and the game's map under
-- it, in its quest view, had no cursor to follow) a window that reads the pad itself while it shows on top: see the
-- head of this file. `spec` nil: driven as any window again
function G.Own(frame, spec)
	if not frame then
		return
	end
	local opts = windows[frame] or {}
	local was = opts.own
	opts.own = spec
	windows[frame] = opts
	Hook(frame)
	if spec and was and S.holding and S.own == was and Top() == frame and not InCombatLockdown() then
		-- (the same window in another mode -- the map's crosshair or its quest column: its keys bound again at once,
		-- the pad never given back between; the focus on the part it now lets walk, or none)
		pcall(ClearOverrideBindings, S.owner)
		S.bound, S.boundX, S.tabsBound, S.held, S.own = nil, nil, nil, nil, spec
		TakeOwn(spec)
		Valid(frame)
		BindA()          -- (A on a protected control's own click again)
		BindX()
		LayLook(frame)   -- (the shoulders on the part's tab row again)
		return
	end
	if frame:IsVisible() then
		Push(frame)
	end
end

-- one key of the window reading the pad itself bound anew while it holds the pad (the map's B: a step back over a
-- page, else the game's close)
function G.OwnKey(key, what)
	local own = S.own
	if not (own and own.keys and S.holding) or InCombatLockdown() then
		return
	end
	own.keys[key] = what
	BindOwn(key, what)
end

function G.Popup(frame, opts)
	if not frame then
		return
	end
	opts = opts or {}
	opts.popup = true
	windows[frame] = opts
	Hook(frame)
	if frame:IsVisible() then
		Push(frame)
	end
end

--------------------------------------------------------------------------------
-- The mode and the fights
--------------------------------------------------------------------------------

local function OnEvent(_, event)
	if event == "INPUT_DEVICE_INTERFACE_TRANSITION" then
		local on = G.On()
		if on then
			-- (the windows already open: the pad drives the last one)
			for frame, opts in pairs(windows) do
				if frame:IsVisible() and not opts.popup then
					Push(frame)
				end
			end
		else
			Unfocus()
			Release()
			wipe(stack)
			Driving(false)
		end
		MelloUI:Fire("gamepad", on)
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- (still allowed in this handler: the pad back to the fight)
		Unfocus()
		Release(true)
	elseif event == "PLAYER_REGEN_ENABLED" then
		if #stack > 0 and Take() then
			Valid(Top())
		end
	elseif event == "GAME_PAD_ACTIVE_CHANGED" or event == "GAME_PAD_CONNECTED" then
		-- (another pad in use, or one plugged in: every coin's face as its pad labels it; a coin with the same face
		-- writes nothing, SetCoin)
		for c in pairs(coinSet) do
			if c.key then
				G.SetCoin(c, c.key)
			end
		end
	end
end

events = CreateFrame("Frame")
Perf.SetScript(events, "OnEvent", OnEvent)
events:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION")
events:RegisterEvent("GAME_PAD_ACTIVE_CHANGED")
events:RegisterEvent("GAME_PAD_CONNECTED")

--------------------------------------------------------------------------------
-- /run MelloUI.Gamepad.Dump(print)
--------------------------------------------------------------------------------

function G.Dump(out)
	out = out or print
	local function Name(f)
		return f and (f:GetName() or tostring(f)) or "-"
	end
	out(("Gamepad: on %s, holding %s, game's pad UI in use %s, in a fight %s"):format(tostring(G.On()),
		tostring(S.holding), tostring(G.GameHasPad()), tostring(InCombatLockdown() and true or false)))
	for i = 1, #stack do
		out(("  %d %s%s (%d controls)"):format(i, Name(stack[i]), windows[stack[i]] and windows[stack[i]].popup and " popup" or "",
			#Controls(stack[i])))
	end
	out("  (typed in the chat, the game's chat holds the pad meanwhile: /run C_Timer.After(5, function() "
		.. "MelloUI.Gamepad.Dump() end) reads it after it closes)")
	out("  focus " .. Name(S.focus) .. (S.bound and " (A bound to it)" or "") .. ", the pad's faces " .. G.Style()
		.. (S.tabsBound and ", LB / RB on a tab row" or ""))
	local f = S.catcher
	out(("  the sticks held %s (the catcher %s), last read %.2f %.2f / %.2f %.2f"):format(
		tostring(f and f:IsShown() or false), S.catching and "enabled" or "not enabled", caught[1], caught[2],
		caught[3], caught[4]))
end
