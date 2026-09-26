--------------------------------------------------------------------------------
-- MelloUI - Installer: the window
--
-- The installer's window over the engine (Core/Installer.lua): a kit window
-- (Kit:OwnWindow, area "installer": always in the kit, user 2026-09-25) with
-- the steps rail on the left, the step pages on the right and the footer's
-- Back / Continue / Install. The setups' paths:
--   Full experience, Reskin only   choose, fit, review, keep
--   No reskin, features on         choose, review, keep
--   Fresh start                    choose, look, map, parchment, fonts,
--                                  features, fit, chat, windows, review, keep
--   Fit to this screen (refit)     fit, review, keep (its own entry only)
-- (the approved sketch of 2026-09-24.)
--
-- Built from the shared parts, one system per job: the shell (the corner
-- ring with the emblem, the plate on the rail with the step's title, close,
-- Escape, the fit to the screen, the open and close sounds; ONE mover,
-- Core's, with no saved place: a drag moves it for the session and every
-- open puts it back in the centre), W.NavRail (the numbered steps; switching
-- setups takes its rows from the rail's pool), W.Pager (a page per step,
-- made on its first show, cross-faded 0.10 s out / 0.15 s in with a 12 px
-- slide; at once under Reduce Motion), W.Card (the four setups), the typed
-- rows, W.Button (Install in gold), Kit:StoneDim (the body on the dark inner
-- panel: every line of text on it, none small on the stone, WINDOW-RULES
-- 2e), Kit:RingDisc (the Keep page's ring), MelloUI:StyleFont (the
-- countdown's numeral in the title face), MelloUI:ScreenText (the screen
-- line), MelloUI:PlayUISound. Colours by palette key only (W.Paint), so a
-- new palette paints the window again.
--
-- Nothing of it exists at login: this file defines functions and data. The
-- window is built the first time it opens (WINDOW-RULES 2f), each page on
-- its first show; revisiting a page or switching setups makes no frame. Its
-- bus listeners are taken when it is built, its combat events and the
-- 'editmode' listener only while it shows; nothing polls. It writes nothing
-- but the setup's draft until Install; the engine applies, counts down and
-- reverts, and tells the window on the bus ('installer'). The fit runs on
-- the Screen step's first show (a frame's share at a time, I:StartFit) and
-- Install waits for it. The UI scale is only shown, never changed.
--
-- Fresh start's wizard (Look, Minimap, Parchment and dark mode, Fonts,
-- Features, Chat, Windows) is the same kind of page: its switches, choice
-- rows and cards read and write that setup's draft only, each starting at
-- Full's value (Dark mode at the player's own: a personal preference), so
-- Continue through every step gives Mello's look with the features off. A
-- feature switched on there comes with Mello's settings for it (the engine).
-- A change there drops the setup's fit (the fitter reads the reskin, The
-- HUD and Tweaks): Review fits again and Install waits for it. Pictures,
-- never a live preview (user, 2026-09-25: a Kit Colours switch walks every
-- kit texture): a colour card shows the kit's window frame from that look's
-- own folder, a font card its own faces.
--
--   MelloUI:OpenInstaller(from)    the entry (the configurator's Install...,
--                                  Install again and Fit to this screen,
--                                  /mello install): MelloUI.Installer:Open
--                                  when the login stage gives it one, else
--                                  IW:Open(); from "fit": the refit
--   IW:Open([page]) -> true        built on the first call, centred, on its
--                                  setup's first step (page "fit": the
--                                  refit on its Screen step); on the Keep
--                                  page whenever an answer is owed (after a
--                                  /reload or a restart the countdown runs
--                                  again with its 15 s, I:ResumePending)
--   IW:Close()   IW:IsShown()   IW:Busy() (shown, or a countdown runs)
--   IW:Draft([optionKey]) -> draft the setup's draft: the Screen step's
--                                  layout switch, and Fresh start's wizard
--                                  (Full's values to begin with; made when
--                                  Fresh start is picked)
--   IW:FontChoice([draft]) -> key  the Fonts step's card the draft names:
--                                  a Font Style's value, "mello" or "game"
--   IW:Step(key, def)              a step's page put in or replaced (every
--                                  step has its own in this file, the Fresh
--                                  start wizard's included): def = { build =
--                                  fn(page, IW) -> height, refresh =
--                                  fn(page, IW) -> height or nil, title,
--                                  label }; a step with no page shows a
--                                  line saying Continue keeps Mello's choice
--   IW:Refresh()                   the page on show and the footer again
--   IW.win                         the built window: frame, shell, rail,
--                                  pager, pages[step], foot
--   IW.state                       (read only) option, step, phase, drafts,
--                                  fits; IW.PAGE_W, IW.TEXT_W, IW.PAD: a
--                                  page's width, its text's width, margin
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Installer window")   -- this file's load time (/melloperf load) and its handlers
local Shared = Perf.Shared
local Num = MelloUI.Safe.Number
local Secret = MelloUI.Safe.IsSecret

local W = MelloUI.Widgets      -- (Core/Widgets.lua loads before this file)
local I = MelloUI.Installer    -- (Core/Installer.lua too; the Kit and Fonts load later: looked up when used)

local IW = {}
MelloUI.InstallerWindow = IW

local pairs, ipairs, type, tostring, tonumber, pcall = pairs, ipairs, type, tostring, tonumber, pcall
local floor, min, abs = math.floor, math.min, math.abs
local format, concat = string.format, table.concat
local EMPTY = {}

local TEXTURE_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Textures\\"
local LOGO = TEXTURE_PATH .. "LogoIcon.tga"
-- the approved banner (900 x 491) in a 1024 x 512 file: loaded when the
-- Setup page shows, released when the window closes (about 2 MB: the
-- texture build's quality gate keeps it a TGA, its DXT at 29.4 dB)
local BANNER = TEXTURE_PATH .. "InstallerBanner.tga"
local BANNER_U, BANNER_V = 900 / 1024, 491 / 512
local TICK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local NAME = "MelloUIInstallerFrame"   -- (named: the shell's Escape)
local OWNER = "Installer window"            -- the bus owner while it exists
local OWNER_SHOWN = "Installer window shown"   -- ... and while it shows

-- geometry (UI units, the approved sketch)
local WIN_W, WIN_H = 780, 600
local EDGE = 16                 -- the window's margin
local TOP = -64                 -- the rail's and the body's top, under the corner ring
local RAIL_W = 160
local BODY_X = 190
local BODY_BOTTOM = 60          -- over the footer band (16 .. 48)
local FOOT_MID = 32
local PAGE_W = WIN_W - BODY_X - EDGE   -- 574
local PAD = 14                  -- a page's text margin
local TEXT_W = PAGE_W - 2 * PAD
local CARD_W, CARD_H, CARD_GAP_X, CARD_GAP_Y = 279, 72, 16, 10
local BANNER_W, BANNER_H = 460, 251
local PIC_W, PIC_H, PIC_M = 520, 170, 8
local RING = 110
local BUTTON_W, BUTTON_H = 120, 24
local DONE_BUTTON_W = 124
local EYE_SHOWN = 3             -- the eye items listed under the picture (the rest counted)
IW.PAGE_W, IW.TEXT_W, IW.PAD = PAGE_W, TEXT_W, PAD   -- (a step's page: IW:Step's builders lay out on these)

-- the Screen step's picture: which pieces, and how (palette keys only):
-- the pieces that are on screen for real (always, with a
-- target, in or out of combat, while casting, on mouseover), not the ones
-- that come now and then
local DRAWN = { A = true, T = true, O = true, C = true, K = true, M = true }
local NOT_DRAWN = { ["FPS / latency text"] = true, ["Target auras (MelloUI row)"] = true, ["Chat tabs"] = true }
local MAIN_BARS = { ["Bar panel backdrop"] = true }
local MINIMAP = "Minimap (kit frame + zone plate)"
local BAR_UNITS = { core = true, bars = true, br = true }
-- draw layer sublevels, bottom to top
local SUB_SCREEN, SUB_MAIN, SUB_BAR, SUB_FRAME, SUB_RING, SUB_ZONE = -8, -6, -4, -3, -1, 1

-- The texts (in-game words: addon-only, no tool or other addon named)
local TEXT = {
	lead = "Choose how MelloUI starts. Nothing changes until you install, and you can go back right after.",
	screen = "Screen: %s",
	detected = "Detected screen: %s",
	fitting = "Fitting to your screen...",
	notFitted = "Mello's layout could not be fitted on this client; your own Edit Mode layout stays.",
	aspect = "Aspect ratio",
	asMade = "Mello's layout, as made",
	fittedTo = "Mello's layout, fitted to your screen",
	beingFitted = "Being fitted to your screen",
	ownStays = "Your own Edit Mode layout stays",
	scale = "UI scale: yours stays as it is",
	scaleLine = "MelloUI never changes it",
	switch = "Add the '%s' Edit Mode layout (your own layouts stay)",
	switchDesc = "Mello's layout, fitted to this screen, as an account layout of its own, made active. Your own layouts stay in the list, and Revert puts the one you use now back.",
	how = "Pieces at an edge keep their distance to it; the centre group tightens to fit; then everything is checked for overlaps.",
	eyeHead = "Worth a look in the game once it is in:",
	eyeMore = "... and %d more",
	suggest = "'No reskin, features on' suits this screen.",
	useNoReskin = "Use No reskin",
	reviewLead = "%s: this is what changes.",
	layoutRow = "Edit Mode layout '%s', fitted to %s",
	layoutWaits = "The Edit Mode layout, once your screen is fitted",
	noLayout = "No Edit Mode change: your own layout stays",
	scaleRow = "Your UI scale stays as it is",
	restore = "Your current setup is saved as the profile 'Before install' first, so you can go back to it later from the Profiles page. After Install you have 15 seconds to keep the new setup; one reload at the end, only if the fonts need it.",
	keepQuestion = "Keep this setup?",
	keepLine = "If you don't answer, MelloUI goes back to 'Before install' when the timer runs out.",
	doneTitle = "MelloUI is set up.",
	doneReload = "The names above characters use the new font after a reload.",
	doneWhere = "Every setting lives in /mello, and in the MelloUI button of the game menu.",
	doneFresh = "Features are off: switch them on in /mello.",
	doneFeatures = "The features you switched on start with Mello's settings. The rest wait in /mello.",
	revertedTitle = "Back to 'Before install'.",
	revertedReload = "Reload to finish: the names above characters still use the installed font.",
	plateDone = "All set",
	plateReverted = "Back as before",
	closedEarly = "Install... in /mello (or /mello install) sets MelloUI up any time.",
	placeholder = "Continue keeps Mello's own choice for this step.",
	continue = "Continue", back = "Back", install = "Install", keep = "Keep", revert = "Revert",
	reload = "Reload now", tour = "Take the tour", open = "Open MelloUI", again = "Choose again", close = "Close",
	-- Fresh start's wizard
	lookLead = "The painted kit and its colours. The pictures show each look; nothing changes until you install.",
	reskin = "Painted kit reskin",
	reskinDesc = "The whole interface dressed in the painted kit. Off: every area shows the game's own art; the features you switch on keep working.",
	colours = "Kit Colours",
	colourLine = { warm = "Iron in warm browns", bronze = "Browns with gold bevels", painted = "Grey iron, bright red" },
	classIcons = "Class icons in portraits",
	parchmentLead = "Parchment behind text, in dark ink. Each area has its own sheet.",
	parchment = "Parchment",
	darkMode = "Dark mode",
	brightness = "Default UI brightness",
	brightnessDesc = "How bright the game's own artwork is where Dark mode darkens it. Lower is darker.",
	fontsLead = "A font style is a preset: it changes every font at once. Each card shows its title face and its reading face.",
	fontTitleSample = "Quest log",
	fontTextSample = "The road to Westfall is long.",
	melloFonts = "Mello's fonts",
	melloFontsTip = "The faces and sizes of Mello's own setup, as Full experience has them.",
	gameFonts = "The game's fonts",
	gameFontsTip = "The game's own faces everywhere: the font options stay off.",
	chatLead = "How names read in chat.",
	chatTweaks = "Chat tweaks",
	names = "Names in chat",
	nameShade = "Shade behind names",
	windowsLead = "Which windows wear the painted kit.",
	windowsCount = "%d windows",
	hudCount = "%d parts",
	mapLead = "The minimap's shape. The pictures show each one; nothing changes until you install.",
	mapLine = { round = "The map in the painted ring.", square = "The whole map in the window frame." },
	mapMergeHint = "with Services on",
	mapPickSquare = "Pick \"%s\" first.",   -- (the merge row, round chosen: the square card's name)
	featuresLead = "MelloUI's own features. They all start off; one you switch on comes with Mello's settings for it.",
	allFeatures = "All features",
	allFeaturesDesc = "Every feature below on or off at once.",
	-- the Review step's lines for the two
	reviewChoices = "Your choices from each step",
	mapGame = "Minimap: the game's own",
	mapRoundRow = "Minimap: round, in the painted ring",
	mapSquareRow = "Minimap: square, in the window frame",
	mapMergedRow = "Minimap: square, the Services bar inside its frame",
	featuresNone = "Features stay off; switch them on in /mello any time",
	featuresRow = "Features on: %s",
	featuresMore = "%s and %d more",
}
IW.TEXT = TEXT

-- What the Review step lists per setup; true: the Edit Mode layout's line,
-- as the fit and the Screen step's switch make it; a function: fn(option,
-- draft) -> the line (Fresh start's Minimap and Features lines, set with
-- the wizard's pages below)
local REVIEW = {
	full = { "Mello's modules and their settings", "The painted look and the Dynamic UI looks", true, TEXT.scaleRow },
	noReskin = { "MelloUI's features and their settings", "The painted reskin is switched off; your bars and layout stay as they are",
		"No Edit Mode change", TEXT.scaleRow },
	reskinOnly = { "The painted look and the Dynamic UI looks", true,
		"Features stay off; chat on parchment needs Chat tweaks, so it stays off", TEXT.scaleRow },
	fresh = { TEXT.reviewChoices, true, TEXT.scaleRow },
	fit = { true, "Window places fitted to this screen", "Your other settings stay as they are", TEXT.scaleRow },
}
local REVIEW_ROWS = 5

-- The steps: each one's plate title and rail label, and its page's builder
-- and refresh (IW:Step: the Fresh start wizard's pages come that way)
local STEPS = {
	choose = { title = "Welcome to MelloUI", label = "Setup" },
	look = { title = "Look", label = "Look" },
	map = { title = "Minimap", label = "Minimap" },
	parchment = { title = "Parchment and dark mode", label = "Parchment" },
	fonts = { title = "Fonts", label = "Fonts" },
	features = { title = "Features", label = "Features" },
	fit = { title = "Fit to your screen", label = "Your screen" },
	chat = { title = "Chat", label = "Chat" },
	windows = { title = "Windows", label = "Windows" },
	review = { title = "Review and install", label = "Review" },
	keep = { title = "Keep this setup?", label = "Keep" },
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local win   -- the window, once built (IW.win)
local state = {
	option = "full",     -- the chosen setup's key (Full experience preselected)
	step = "choose",     -- the step on show
	phase = "choose",    -- "choose" (before Install) | "keep" (the answer owed) | "done"
	doneMode = nil,      -- "kept" | "reverted"
	needsReload = false, -- (kept) the fonts over heads changed
	reloadOwed = false,  -- (reverted) the game read the installed fonts since
	reason = nil,        -- (reverted) why: "button", "timeout", "error"
	keepLine = nil,      -- a line on the Keep page (a refusal, a failure)
	footLine = nil,      -- a line in the footer after a refused Install
	installed = false,   -- a setup went in while the window was open this time
	drafts = {},         -- [setup key] = its draft
	fits = {},           -- [setup key] = its fit (I:StartFit)
	escape = true,       -- the shell's Escape as last set
}
IW.state = state   -- (read only: /run and the tests)

local NUMS = {}   -- the countdown's numbers as text, made once
for i = 0, 60 do
	NUMS[i] = tostring(i)
end

local function Option(key)
	return I:Option(key or state.option)
end

local function IndexOf(list, value)
	for i = 1, #list do
		if list[i] == value then
			return i
		end
	end
	return nil
end

local InCombat = MelloUI.InCombat   -- (Core's reader)

-- a setup's draft: nothing but its own choices until Install. Fresh start's
-- begins at Full's values (every wizard control does), kept as they
-- began too (wizardFull: the Fonts step's "Mello's fonts")
local wizardFull = nil
local function DraftFor(key)
	key = key or state.option
	local d = state.drafts[key]
	if not d then
		local option = Option(key)
		if option and option.base == "fresh" then
			local ok, draft = pcall(I.DefaultDraft, I)
			d = (ok and type(draft) == "table") and draft or {}
			wizardFull = I.DeepCopy(d)
		else
			d = {}
		end
		state.drafts[key] = d
	end
	return d
end

-- whether the setup's path has the Screen step (the fit runs there)
local function HasFit(option)
	return option and IndexOf(option.steps, "fit") ~= nil
end

-- the pending answer on the restore point (nil: none owed)
local function Pending()
	local rp = MelloUI.db and MelloUI.db.installer
	local pending = type(rp) == "table" and rp.pending
	return type(pending) == "table" and pending or nil
end

--------------------------------------------------------------------------------
-- The screen, as the texts show it (MelloUI:ScreenText: Core's one formatter,
-- shared with the configurator's Your setup)
--------------------------------------------------------------------------------

-- "3440 x 1440 (21:9)", and the aspect's label; "?" while the client does
-- not say
local function ScreenText()
	local text, ratio = MelloUI:ScreenText()
	if not text then
		return "?", nil
	end
	return text, ratio
end

local scaleMemo = { v = nil, text = "?" }
local function ScaleText()
	local ok, s = pcall(UIParent.GetScale, UIParent)
	s = ok and Num(s) or nil
	if s and s ~= scaleMemo.v then
		scaleMemo.v, scaleMemo.text = s, format("%.2f", s)
	end
	return scaleMemo.text
end

local footMemo = { screen = nil, text = nil }
local function ScreenLine()
	local screen = ScreenText()
	if footMemo.screen ~= screen then
		footMemo.screen, footMemo.text = screen, TEXT.screen:format(screen)
	end
	return footMemo.text
end

--------------------------------------------------------------------------------
-- The fit (the Screen step's; one per setup, the last one kept)
--------------------------------------------------------------------------------

local RefreshPage, RefreshFooter

-- the fitter's answer: the page on show and the footer again (a fit of a
-- setup no longer chosen, or dropped, changes nothing)
local function FitDone(fit)
	if state.fits[fit.option] ~= fit or not (win and win.frame:IsShown()) then
		return
	end
	RefreshPage()
	RefreshFooter()
end

-- a finished fit made for another screen size than UIParent's now (the
-- engine then holds Install: "being fitted again")
local function Stale(fit)
	local LayoutFit = MelloUI.LayoutFit
	if not (fit.done and fit.W and fit.H and LayoutFit and LayoutFit.ScreenSize) then
		return false
	end
	local w, h = LayoutFit:ScreenSize()
	return (w and h and (abs(w - fit.W) > 0.5 or abs(h - fit.H) > 0.5)) and true or false
end

-- the setup's fit: the one made, or a new one (a fit of another setup
-- still solving is stopped: one at a time)
local function EnsureFit(key)
	local option = Option(key)
	if not HasFit(option) then
		return nil
	end
	local fit = state.fits[option.key]
	if fit and not fit.cancelled and not Stale(fit) then
		return fit
	end
	for k, f in pairs(state.fits) do
		if k ~= option.key and not f.done then
			I:CancelFit(f)
			state.fits[k] = nil
		end
	end
	fit = I:StartFit(option, DraftFor(option.key), FitDone)
	state.fits[option.key] = fit
	return fit
end

-- the fits still solving stopped (the window closed); all: every fit goes
-- (an install kept or reverted: the settings a fit read may have changed)
local function DropFits(all)
	for k, f in pairs(state.fits) do
		if not f.done then
			I:CancelFit(f)
			state.fits[k] = nil
		elseif all then
			state.fits[k] = nil
		end
	end
end

local function FitOf(key)
	local fit = state.fits[key or state.option]
	return (fit and fit.done) and fit or nil
end

local function LayoutNameOf(fit)
	local fitted = fit and fit.fitted
	local name = type(fitted) == "table" and fitted.layoutName
	return (type(name) == "string" and not Secret(name)) and name or "MelloUI"
end

-- the Review step's line for the Edit Mode layout
local function LayoutLine(option)
	local fit = FitOf(option.key)
	local draft = DraftFor(option.key)
	if not fit then
		if option.layout and draft.layout ~= false then
			return TEXT.layoutWaits
		end
		return TEXT.noLayout
	end
	if I:LayoutOn(option, draft, fit) then
		return TEXT.layoutRow:format(LayoutNameOf(fit), (ScreenText()))
	end
	return TEXT.noLayout
end

--------------------------------------------------------------------------------
-- The shared handlers and the actions
--------------------------------------------------------------------------------

local ACTIONS = {}
local Present, ShowKeep, ShowDone, RailRefresh, RefreshKeep

local ButtonClick = Shared("OnClick on the installer's buttons", function(button)
	local act = ACTIONS[button.melloAct]
	if act then
		act(button)
	end
end, "script")

-- the mover's save: no place is kept (every open is centred), and its
-- default: the centre
local function NoPlace()
end

local function Centre(frame)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

local MOVER = { save = NoPlace, default = Centre, plainDrag = "always" }

local function Button(parent, text, width, act, gold)
	local b = W.Button(parent, text, width, win.shell, { height = BUTTON_H, onClick = ButtonClick, gold = gold })
	b.melloAct = act
	return b
end

-- the shell's Escape and close button: only Keep or Revert while the
-- countdown runs
local function SetClosable(on)
	on = on and true or false
	if state.escape ~= on then
		state.escape = on
		win.shell:SetEscape(on)
	end
	if win.shell.close then
		win.shell.close:SetShown(on)
	end
end

local function GoTo(key, dir)
	if key == state.step then
		return
	end
	state.step, state.footLine = key, nil
	MelloUI:PlayUISound("page")
	Present(key, dir)
end

function ACTIONS.next()
	local steps = Option().steps
	local at = IndexOf(steps, state.step) or 1
	local key = steps[at + 1]
	if key and key ~= "keep" then
		GoTo(key, 1)
	end
end

function ACTIONS.back()
	local steps = Option().steps
	local at = IndexOf(steps, state.step) or 1
	if at > 1 then
		GoTo(steps[at - 1], -1)
	end
end

-- Install, in the click frame (the one long frame, measured). The engine's
-- 'installed' Fire shows the Keep page; a refusal is said in the footer. A
-- fault half way that could not be put back leaves the answer owed with
-- `failed`: the Keep page with Revert only and the engine's line.
function ACTIONS.install()
	MelloUI:PlayUISound("menu_button")
	local option = Option()
	local ok, why = I:Install(option, DraftFor(option.key), state.fits[option.key])
	if ok then
		return
	end
	if Pending() then
		state.installed, state.keepLine = true, why
		ShowKeep(1)
	elseif state.phase == "choose" then
		state.footLine = why
		RefreshFooter()
	end
end

function ACTIONS.keep()
	MelloUI:PlayUISound("menu_button")
	local _, why = I:Keep()
	if why then
		state.keepLine = why
		RefreshKeep()
	end
end

function ACTIONS.revert()
	MelloUI:PlayUISound("menu_button")
	local ok, why = I:Revert("button")
	if not ok and why then
		state.keepLine = why
		RefreshKeep()
	end
end

function ACTIONS.reload()
	local reload = _G.ReloadUI
	if type(reload) == "function" then
		reload()
	end
end

function ACTIONS.tour()
	MelloUI:PlayUISound("menu_button")
	win.frame:Hide()
	local tutorial = MelloUI.Tutorial
	if tutorial and tutorial.Start then
		tutorial:Start()
	end
end

-- (the configurator's open toggles: one already shown, opened during the
-- countdown under this window, stays)
function ACTIONS.open()
	MelloUI:PlayUISound("menu_button")
	win.frame:Hide()
	local config = _G.MelloUIConfigFrame
	if MelloUI.OpenConfig and not (config and config:IsShown()) then
		MelloUI:OpenConfig()
	end
end

function ACTIONS.close()
	win.frame:Hide()
end

-- after a revert: the setup's path again from its first step (the setups,
-- or the refit's Screen step); nothing is installed now
function ACTIONS.again()
	local first = Option().steps[1]
	state.phase, state.step, state.doneMode, state.keepLine, state.footLine = "choose", first, nil, nil, nil
	state.installed = false
	MelloUI:PlayUISound("page")
	SetClosable(true)
	Present(first, -1)
end

-- the Screen step's suggestion on a screen too small for Mello's layout
function ACTIONS.noReskin()
	if state.phase ~= "choose" then
		return
	end
	MelloUI:PlayUISound("tab")
	state.option = "noReskin"
	win.rail:SetGroups(IW.GroupsFor(Option()))
	state.step, state.footLine = "review", nil
	Present("review", 1)
end

--------------------------------------------------------------------------------
-- The rail
--------------------------------------------------------------------------------

local railGroups = {}   -- [setup key] = the rail's groups for its path (made once each)

function IW.GroupsFor(option)
	local g = railGroups[option.key]
	if not g then
		local entries = {}
		for i, key in ipairs(option.steps) do
			local def = STEPS[key]
			entries[i] = { key = key, text = def and def.label or key }
		end
		g = { { key = "steps", entries = entries } }
		railGroups[option.key] = g
	end
	return g
end

-- a step on the rail takes a click while it is done and nothing is installed
local function StepClickable(rail, key)
	if state.phase ~= "choose" then
		return false
	end
	local steps = Option().steps
	local at, i = IndexOf(steps, state.step), IndexOf(steps, key)
	return (at and i and i < at) and true or false
end

local function StepClick(rail, key)
	if StepClickable(rail, key) then
		GoTo(key, -1)
	end
end

-- the steps before the current one done (and clickable before Install),
-- the current one selected
RailRefresh = function()
	local rail = win.rail
	local steps = Option().steps
	local at = IndexOf(steps, state.step) or #steps
	for i, key in ipairs(steps) do
		rail:SetState(key, (i < at or state.phase == "done") and "done" or nil)
		local row = rail.rows[key]
		if row then
			row:EnableMouse(StepClickable(rail, key))
		end
	end
	rail:Select(state.step)
end

--------------------------------------------------------------------------------
-- Pages: made on their first show, refreshed on every show
--------------------------------------------------------------------------------

local function PageOf(key)
	local page = win.pages[key]
	if page then
		return page
	end
	page = win.pager:NewPage()
	page:SetWidth(PAGE_W)
	page:SetHeight(1)
	win.pages[key] = page
	local def = STEPS[key]
	local h = def and def.build and def.build(page, IW) or IW.BuildPlaceholder(page, IW)
	page.melloHeight = tonumber(h) or 1
	return page
end

RefreshPage = function(key)
	key = key or state.step
	local page = win and win.pages[key]
	if not page then
		return
	end
	local def = STEPS[key]
	local refresh = def and (def.refresh or (not def.build and IW.RefreshPlaceholder))
	local h = refresh and refresh(page, IW)
	if tonumber(h) then
		page.melloHeight = h
	end
	win.pager:SetPageHeight(page, page.melloHeight)
end

-- the title on the plate
local function SetTitle()
	local title
	if state.phase == "done" then
		title = state.doneMode == "reverted" and TEXT.plateReverted or TEXT.plateDone
	else
		local def = STEPS[state.step]
		title = def and def.title or ""
	end
	local fs = win.shell.title
	if fs and fs:GetText() ~= title then
		fs:SetText(title)
	end
end

-- The footer: the screen line, or why Install cannot run; Back (not on the
-- first step), then Continue, or Install on the Review step (disabled while
-- anything holds it: the fit not done, no room in Edit Mode, combat, ...)
RefreshFooter = function()
	if not win then
		return
	end
	local f = win.foot
	local line = ScreenLine()
	if state.phase == "choose" then
		local option = Option()
		local steps = option.steps
		local at = IndexOf(steps, state.step) or 1
		local last = state.step == "review"
		f.back:SetShown(at > 1)
		f.next:SetShown(not last)
		f.install:SetShown(last)
		if last then
			local why = I:InstallBlocked(option, DraftFor(option.key), state.fits[option.key])
			f.install:SetEnabled(why == nil)
			line = why or line
		end
		line = state.footLine or line
	else
		f.back:Hide()
		f.next:Hide()
		f.install:Hide()
	end
	if f.line:GetText() ~= line then
		f.line:SetText(line)
	end
end

-- a step's page shown: made if new, refreshed, cross-faded in (dir +1 from
-- the right, -1 from the left); the plate, the rail and the footer with it
Present = function(key, dir, instant)
	local page = PageOf(key)
	RefreshPage(key)
	win.pager:Show(page, dir or 0, instant)
	SetTitle()
	RailRefresh()
	RefreshFooter()
end

function IW:Step(key, def)
	local s = STEPS[key]
	if s and type(def) == "table" then
		s.build, s.refresh = def.build, def.refresh
		s.title, s.label = def.title or s.title, def.label or s.label
	end
end

function IW:Draft(key)
	return DraftFor(key)
end

function IW:Refresh()
	if win and win.frame:IsShown() then
		RefreshPage()
		RefreshFooter()
	end
end

-- a step with no page of its own (none today; a step IW:Step clears): one
-- line (Continue keeps the draft's value, Full's)
function IW.BuildPlaceholder(page)
	page.line = W.Text(page, "GameFontHighlight", TEXT.placeholder, "text")
	page.line:SetWidth(TEXT_W)
	page.line:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, -12)
	return 60
end

function IW.RefreshPlaceholder()
	return 60
end

--------------------------------------------------------------------------------
-- The Setup step: the banner, the lead, the four setups (the refit has no card)
--------------------------------------------------------------------------------

local function CardPick(card)
	if state.phase ~= "choose" or card.key == state.option then
		return
	end
	state.option, state.footLine = card.key, nil
	win.rail:SetGroups(IW.GroupsFor(Option()))
	RailRefresh()
	RefreshPage("choose")
	RefreshFooter()
	-- (Fresh start's draft made in this light frame, so the Look step's
	-- first show only builds its page)
	if Option().base == "fresh" then
		DraftFor()
	end
end

local function BuildChoose(page)
	local banner = page:CreateTexture(nil, "ARTWORK")
	banner:SetSize(BANNER_W, BANNER_H)
	banner:SetPoint("TOP", page, "TOP", 0, -8)
	page.banner = banner
	local lead = W.Text(page, "GameFontHighlight", TEXT.lead, "text")
	lead:SetWidth(TEXT_W)
	lead:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, -(8 + BANNER_H + 10))
	page.lead = lead
	-- the cards hang under the lead (a Font Style that makes it taller moves
	-- them with it)
	-- (a hidden setup, the refit, has no card: it has its own entry)
	page.cards = {}
	for _, option in ipairs(I.OPTIONS) do
		if not option.hidden then
			local i = #page.cards + 1
			local col, row = (i - 1) % 2, floor((i - 1) / 2)
			local card = W.Card(page, { width = CARD_W, height = CARD_H, title = option.title, text = option.desc,
				tag = option.tag, key = option.key, onClick = CardPick }, win.shell)
			card:SetPoint("TOPLEFT", lead, "BOTTOMLEFT", col * (CARD_W + CARD_GAP_X) - PAD, -12 - row * (CARD_H + CARD_GAP_Y))
			page.cards[i] = card
		end
	end
	return 1
end

local function RefreshChoose(page)
	if not win.bannerLoaded then
		page.banner:SetTexture(BANNER)
		page.banner:SetTexCoord(0, BANNER_U, 0, BANNER_V)
		win.bannerLoaded = true
	end
	for _, card in ipairs(page.cards) do
		card:SetSelected(card.key == state.option)
	end
	local lead = Num(page.lead:GetStringHeight()) or 30
	return 8 + BANNER_H + 10 + lead + 12 + 2 * CARD_H + CARD_GAP_Y + 8
end

STEPS.choose.build, STEPS.choose.refresh = BuildChoose, RefreshChoose

--------------------------------------------------------------------------------
-- The Screen step: the detected screen, the fitted picture, the
-- aspect and the UI scale (read only), the layout switch
--------------------------------------------------------------------------------

-- a box with a label, a value in gold and a line (the aspect, the UI scale)
local function InfoPanel(page, label)
	local box = W.Box(page, "mainWindow", "border", 0.85)
	box:SetSize((PAGE_W - 10) / 2, 70)
	box.label = W.Text(box, "GameFontHighlight", label, "text")
	box.label:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -9)
	box.value = W.Text(box, "GameFontNormalLarge", nil, "selectedTrim")
	box.value:SetPoint("TOPLEFT", box.label, "BOTTOMLEFT", 0, -4)
	box.line = W.Text(box, "GameFontHighlight", nil, "text")
	box.line:SetPoint("TOPLEFT", box.value, "BOTTOMLEFT", 0, -4)
	box.line:SetPoint("RIGHT", box, "RIGHT", -12, 0)
	box.line:SetWordWrap(false)
	return box
end

local function LayoutGet()
	local draft = DraftFor()
	if draft.layout ~= nil then
		return draft.layout
	end
	local fit = FitOf()
	return not (fit and type(fit.report) == "table" and not fit.report.pass)
end

local function LayoutSet(on)
	DraftFor().layout = on and true or false
	RefreshPage()
	RefreshFooter()
end

local function BuildFit(page)
	local shell = win.shell
	page.detected = W.Text(page, "GameFontHighlight", nil, "text")
	page.detected:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, -8)
	-- the picture: the screen, and the pieces in palette solids (a pool of
	-- textures made on the first draw and reused)
	local box = W.Box(page, "innerPanel", "border", 1)
	box:SetSize(PIC_W, PIC_H)
	box:SetPoint("TOP", page, "TOP", 0, -30)
	page.box = box
	local pic = { pool = {}, edges = {} }
	pic.screen = box:CreateTexture(nil, "ARTWORK", nil, SUB_SCREEN)
	W.Paint(pic.screen, "mainWindow", "fill", 1)
	for i = 1, 4 do
		pic.edges[i] = box:CreateTexture(nil, "ARTWORK", nil, SUB_SCREEN + 1)
		W.Paint(pic.edges[i], "mutedText", "fill", 1)
	end
	pic.msg = W.Text(box, "GameFontHighlight", TEXT.fitting, "text")
	pic.msg:SetJustifyH("CENTER")
	pic.msg:SetPoint("CENTER", box, "CENTER", 0, 0)
	page.pic = pic
	-- under it: the FAIL line or the eye items, and the suggestion
	page.note = W.Text(page, "GameFontHighlight", nil, "text")
	page.note:SetWidth(TEXT_W)
	page.suggest = Button(page, TEXT.useNoReskin, 150, "noReskin")
	page.aspect = InfoPanel(page, TEXT.aspect)
	page.scale = InfoPanel(page, TEXT.scale)
	page.scale.line:SetText(TEXT.scaleLine)
	local row = W.ToggleRow(page, 0, TEXT.switch:format("MelloUI"), nil, TEXT.switchDesc, LayoutGet, LayoutSet,
		{ skin = shell, look = "palette", zebra = true })
	page.switchRow = row
	page.how = W.Text(page, "GameFontHighlight", TEXT.how, "text")
	page.how:SetWidth(TEXT_W)
	page.room = W.Text(page, "GameFontHighlight", nil, "selectedTrim")
	page.room:SetWidth(TEXT_W)
	return 1
end

-- a texture of the picture's pool (made the first time the pool is short)
local function PicTex(page, i)
	local pic = page.pic
	local tex = pic.pool[i]
	if not tex then
		tex = page.box:CreateTexture(nil, "ARTWORK")
		pic.pool[i] = tex
	end
	return tex
end

local function Rect(tex, parent, x, y, w, h)
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	tex:SetSize(w > 1 and w or 1, h > 1 and h or 1)
	tex:Show()
end

-- the minimap's trim ring: a trim disc with the screen's colour inside
-- (two masked textures, made once)
local function Ring(page, x, y, d)
	local pic, box = page.pic, page.box
	if not pic.ring then
		pic.ring = box:CreateTexture(nil, "ARTWORK", nil, SUB_RING)
		pic.ringIn = box:CreateTexture(nil, "ARTWORK", nil, SUB_RING + 1)
		for _, tex in ipairs({ pic.ring, pic.ringIn }) do
			local mask = box:CreateMaskTexture()
			mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			mask:SetAllPoints(tex)
			tex:AddMaskTexture(mask)
		end
		W.Paint(pic.ring, "trim", "fill", 1)
		W.Paint(pic.ringIn, "mainWindow", "fill", 1)
	end
	local t = d > 12 and 2 or 1
	Rect(pic.ring, box, x, y, d, d)
	Rect(pic.ringIn, box, x + t, y + t, d - 2 * t, d - 2 * t)
end

-- The picture from the fit's report (the same model the fit checked: one
-- system): the screen scaled into the box, the persistent pieces in palette
-- solids -- the raised panel for frames, the border for bars, the selected
-- tab with a trim line for the main bars, a trim ring for the minimap, the
-- 21:9 zone's edges in trim on a wider screen
local function DrawPicture(page, report)
	local pic, box = page.pic, page.box
	local LayoutFit = MelloUI.LayoutFit
	local sw, sh = Num(report and report.W), Num(report and report.H)
	if not (sw and sh) and LayoutFit and LayoutFit.ScreenSize then
		sw, sh = LayoutFit:ScreenSize()
	end
	sw, sh = Num(sw) or 1920, Num(sh) or 1080
	local s = min((PIC_W - 2 * PIC_M) / sw, (PIC_H - 2 * PIC_M) / sh)
	local w, h = sw * s, sh * s
	local ox, oy = (PIC_W - w) / 2, (PIC_H - h) / 2
	Rect(pic.screen, box, ox, oy, w, h)
	local e = pic.edges
	Rect(e[1], box, ox, oy, w, 1)
	Rect(e[2], box, ox, oy + h - 1, w, 1)
	Rect(e[3], box, ox, oy, 1, h)
	Rect(e[4], box, ox + w - 1, oy, 1, h)
	local n = 0
	local pieces = report and type(report.pieces) == "table" and report.pieces or nil
	local ringShown = false
	for i = 1, pieces and #pieces or 0 do
		local p = pieces[i]
		if type(p) == "table" and DRAWN[p.cat] and not NOT_DRAWN[p.name] then
			local l, t = math.max(0, Num(p.l) or 0), math.max(0, Num(p.t) or 0)
			local r, b = min(sw, Num(p.r) or 0), min(sh, Num(p.b) or 0)
			if r > l and b > t then
				local x, y, pw, ph = ox + l * s, oy + t * s, (r - l) * s, (b - t) * s
				if p.name == MINIMAP then
					local d = min(pw, ph)
					Ring(page, x + (pw - d) / 2, y + (ph - d) / 2, d)
					ringShown = true
				elseif MAIN_BARS[p.name] then
					n = n + 1
					local fill = PicTex(page, n)
					fill:SetDrawLayer("ARTWORK", SUB_MAIN)
					W.Paint(fill, "selectedTab", "fill", 1)
					Rect(fill, box, x, y, pw, ph)
					n = n + 1
					local line = PicTex(page, n)
					line:SetDrawLayer("ARTWORK", SUB_MAIN + 1)
					W.Paint(line, "trim", "fill", 1)
					Rect(line, box, x, y, pw, 1)
				else
					n = n + 1
					local tex = PicTex(page, n)
					local bar = BAR_UNITS[p.unit]
					tex:SetDrawLayer("ARTWORK", bar and SUB_BAR or SUB_FRAME)
					W.Paint(tex, bar and "border" or "raisedPanel", "fill", 1)
					Rect(tex, box, x, y, pw, ph)
				end
			end
		end
	end
	-- the 21:9 zone's edges on a wider screen
	local inset = Num(report and report.inset) or 0
	if inset > 0.5 then
		for side = 0, 1 do
			n = n + 1
			local tex = PicTex(page, n)
			tex:SetDrawLayer("ARTWORK", SUB_ZONE)
			W.Paint(tex, "trim", "fill", 1)
			Rect(tex, box, ox + (side == 0 and inset or (sw - inset)) * s, oy, 1, h)
		end
	end
	for i = n + 1, #pic.pool do
		pic.pool[i]:Hide()
	end
	if pic.ring and not ringShown then
		pic.ring:Hide()
		pic.ringIn:Hide()
	end
end

-- the line under the picture: why the layout does not fit (and the
-- suggestion on a screen too small), or what is worth a look in the game
local function NoteText(page, report)
	if page.noteFor == report then
		return page.noteText
	end
	local text
	if report and not report.pass then
		text = (type(report.why) == "string" and report.why) or TEXT.notFitted
		if report.tooSmall then
			text = text .. "\n" .. TEXT.suggest
		end
	elseif report and type(report.eye) == "table" and #report.eye > 0 then
		local lines = { TEXT.eyeHead }
		for i = 1, min(#report.eye, EYE_SHOWN) do
			lines[#lines + 1] = "- " .. tostring(report.eye[i])
		end
		if #report.eye > EYE_SHOWN then
			lines[#lines + 1] = TEXT.eyeMore:format(#report.eye - EYE_SHOWN)
		end
		text = concat(lines, "\n")
	end
	page.noteFor, page.noteText = report, text
	return text
end

local function Place(region, page, x, y)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y)
end

local function RefreshFit(page)
	local option = Option()
	local fit = EnsureFit(option.key)
	local done = fit and fit.done and fit
	local report = done and type(done.report) == "table" and done.report or nil
	local screen, ratio = ScreenText()
	page.detected:SetText(TEXT.detected:format(screen))
	-- the picture, or the line while the fit runs
	page.pic.msg:SetShown(not done)
	DrawPicture(page, report)
	local y = 30 + PIC_H + 10
	-- the FAIL line or the eye items, and the suggestion
	local note = NoteText(page, report)
	page.note:SetText(note or "")
	page.note:SetShown(note ~= nil)
	if note then
		Place(page.note, page, PAD, y)
		y = y + (Num(page.note:GetStringHeight()) or 14) + 8
	end
	local suggest = report and report.tooSmall and option.key ~= "noReskin" and true or false
	page.suggest:SetShown(suggest)
	if suggest then
		Place(page.suggest, page, PAD, y)
		y = y + BUTTON_H + 10
	end
	-- the aspect and the UI scale
	local aspect = page.aspect
	aspect.value:SetText(ratio or "?")
	local LayoutFit = MelloUI.LayoutFit
	local design = report and LayoutFit and abs((Num(report.W) or 0) - (LayoutFit.DESIGN_W or 0)) < 0.5
		and abs((Num(report.H) or 0) - (LayoutFit.DESIGN_H or 0)) < 0.5
	aspect.line:SetText(not done and TEXT.beingFitted or (report and not report.pass and TEXT.ownStays)
		or (design and TEXT.asMade) or TEXT.fittedTo)
	Place(aspect, page, 0, y)
	page.scale.value:SetText(ScaleText())
	Place(page.scale, page, (PAGE_W + 10) / 2, y)
	y = y + 70 + 10
	-- the layout switch, named as the fit names this screen's layout
	local row = page.switchRow
	local label = TEXT.switch:format(LayoutNameOf(done))
	if row.label:GetText() ~= label then
		row.label:SetText(label)
		row.tipTitle = label
		W.ControlOf(row).tipTitle = label
	end
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
	row:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	row:Refresh()
	y = y + W.ROW_HEIGHT + 8
	Place(page.how, page, PAD, y)
	y = y + (Num(page.how:GetStringHeight()) or 28) + 8
	-- no room in Edit Mode for one more layout: said here, before Install
	local room = true
	if done and I:LayoutOn(option, DraftFor(option.key), done) then
		local ok, most
		ok, most = I:LayoutRoom(done)
		room = ok
		if not ok then
			page.room:SetText(I.TEXT.noRoom:format(most))
		end
	end
	page.room:SetShown(not room)
	if not room then
		Place(page.room, page, PAD, y)
		y = y + (Num(page.room:GetStringHeight()) or 28) + 8
	end
	return y + 4
end

STEPS.fit.build, STEPS.fit.refresh = BuildFit, RefreshFit

--------------------------------------------------------------------------------
-- The Review step: what changes, the restore point; Install in the
-- footer
--------------------------------------------------------------------------------

local function BuildReview(page)
	page.lead = W.Text(page, "GameFontHighlight", nil, "text")
	page.lead:SetWidth(TEXT_W)
	page.lead:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, -10)
	page.rows = {}
	for i = 1, REVIEW_ROWS do
		local row = W.Row(page, 0, W.ROW_HEIGHT, "", nil, nil, { zebra = i % 2 == 1 })
		local tick = row:CreateTexture(nil, "ARTWORK")
		tick:SetSize(16, 16)
		tick:SetPoint("RIGHT", row, "RIGHT", -14, 0)
		tick:SetTexture(TICK)
		tick:SetDesaturated(true)   -- (gold from the palette, not the art's own green)
		W.Paint(tick, "selectedTrim", "vertex", 1)
		row.tick = tick
		row.label:SetPoint("RIGHT", tick, "LEFT", -10, 0)
		page.rows[i] = row
	end
	page.restore = W.Text(page, "GameFontHighlight", TEXT.restore, "text")
	page.restore:SetWidth(TEXT_W)
	return 1
end

local leadMemo = {}   -- [setup key] = its lead line
local function RefreshReview(page)
	local option = Option()
	local lead = leadMemo[option.key]
	if not lead then
		lead = TEXT.reviewLead:format(option.title)
		leadMemo[option.key] = lead
	end
	page.lead:SetText(lead)
	-- (the Screen step's fit: started again here when the screen changed
	-- since, so Install waits for the new one)
	EnsureFit(option.key)
	local y = 10 + (Num(page.lead:GetStringHeight()) or 14) + 10
	local lines = REVIEW[option.key] or REVIEW.full
	for i, row in ipairs(page.rows) do
		local text = lines[i]
		if text == true then
			text = LayoutLine(option)
		elseif type(text) == "function" then
			text = text(option, DraftFor(option.key))
		end
		row:SetShown(text ~= nil)
		if text then
			row.label:SetText(text)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
			row:SetPoint("RIGHT", page, "RIGHT", 0, 0)
			y = y + W.ROW_HEIGHT
		end
	end
	y = y + 12
	Place(page.restore, page, PAD, y)
	return y + (Num(page.restore:GetStringHeight()) or 42) + 10
end

STEPS.review.build, STEPS.review.refresh = BuildReview, RefreshReview

--------------------------------------------------------------------------------
-- The Keep step and Done, on one page: the ring with the
-- emblem and the seconds, Keep or Revert; then, on the same page, what
-- happened and where to go
--------------------------------------------------------------------------------

-- the ring's kit look: the portrait ring piece on the box, its disc in the
-- inner panel, the emblem on the disc (through shell:Kit: now, the kit on)
local function DressRing(Kit, page, shell)
	local rep = shell:Replace(page.plainEmblem, { as = "MelloUI-Crest", rect = page.ringBox })
	if not rep then
		return
	end
	local holder = rep.object
	local disc = Kit:RingDisc(rep, "innerPanel", holder, 6)
	local emblem = holder:CreateTexture(nil, "ARTWORK", nil, 1)
	emblem.kitPiece = true
	emblem:SetTexture(LOGO)
	emblem:SetAllPoints(disc or rep.tex)
	emblem:SetAlpha(page.emblemAlpha or 0.35)
	local mask = holder:CreateMaskTexture()
	mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(emblem)
	emblem:AddMaskTexture(mask)
	page.ringRep, page.emblem = rep, emblem
end

-- The countdown's numeral in the title face (the Font Style's), sized so it
-- comes out right under every style: the title role's size slider is tuned
-- against Morpheus (a style's title scale is 0.7 to 1.0, so a Morpheus-sized
-- 48 is Cinzel's 34 under Scriptorium, the approved sketch), so its base is a
-- Morpheus font object of the game's at 48; a client without one: the huge
-- game font at 34
local MORPHEUS_OBJECTS = { "Fancy48Font", "Fancy40Font", "Fancy32Font", "Fancy30Font", "Fancy24Font", "Fancy22Font", "QuestTitleFont" }

-- a game font object's own face, as it was before the Fonts module
-- retargeted it (nil: none readable)
local function BaseFace(object)
	if type(object) ~= "table" or not object.GetFont then
		return nil
	end
	local fonts = MelloUI.GetModule and MelloUI:GetModule("Fonts")
	local path
	if fonts and fonts.BaseFont then
		local ok, p = pcall(fonts.BaseFont, fonts, object)
		path = ok and p or nil
	end
	if path == nil then
		local ok, p = pcall(object.GetFont, object)
		path = ok and p or nil
	end
	return (type(path) == "string" and not Secret(path)) and path or nil
end

-- the game's Morpheus font object (the title face's own), or nil
local function MorpheusObject()
	for _, name in ipairs(MORPHEUS_OBJECTS) do
		local object = _G[name]
		local path = BaseFace(object)
		if path and path:lower():find("morpheus", 1, true) then
			return object, path
		end
	end
	return nil
end

local function NumeralBase()
	local object = MorpheusObject()
	if object then
		return object, 48
	end
	return _G.GameFontNormalHuge, 34
end

local function BuildKeep(page)
	local shell = win.shell
	-- the ring (RING across) with the emblem, the seconds in gold over it
	local box = CreateFrame("Frame", nil, page)
	box:SetSize(RING, RING)
	box:SetPoint("TOP", page, "TOP", 0, -20)
	page.ringBox = box
	page.plainEmblem = box:CreateTexture(nil, "ARTWORK")
	page.plainEmblem:SetTexture(LOGO)
	page.plainEmblem:SetAllPoints(box)
	page.plainEmblem:SetAlpha(0.35)
	shell:Kit(DressRing, page, shell)
	local top = CreateFrame("Frame", nil, box)
	top:SetAllPoints(box)
	top:SetFrameLevel(box:GetFrameLevel() + 12)   -- (over the ring's holder)
	page.numeral = top:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")   -- (a font from the start; StyleFont sets its own)
	page.numeral:SetPoint("CENTER", top, "CENTER", 0, 0)
	local object, size = NumeralBase()
	if MelloUI.StyleFont and object then
		MelloUI:StyleFont(page.numeral, "fontTitle", object, size)
	else
		page.numeral:SetFontObject(object or "GameFontNormalLarge")
	end
	W.Paint(page.numeral, "selectedTrim", "text")
	-- the countdown's texts and its two buttons
	local count = CreateFrame("Frame", nil, page)
	count:SetAllPoints(page)
	page.count = count
	count.question = W.Text(count, "GameFontHighlightLarge", TEXT.keepQuestion, "text")
	count.question:SetJustifyH("CENTER")
	count.question:SetPoint("TOP", page, "TOP", 0, -(20 + RING + 12))
	count.line = W.Text(count, "GameFontHighlight", TEXT.keepLine, "text")
	count.line:SetJustifyH("CENTER")
	count.line:SetWidth(TEXT_W)
	count.line:SetPoint("TOP", count.question, "BOTTOM", 0, -8)
	count.status = W.Text(count, "GameFontHighlight", nil, "selectedTrim")
	count.status:SetJustifyH("CENTER")
	count.status:SetWidth(TEXT_W)
	count.status:SetPoint("TOP", count.line, "BOTTOM", 0, -10)
	count.revert = Button(count, TEXT.revert, BUTTON_W, "revert")
	count.keep = Button(count, TEXT.keep, BUTTON_W, "keep")
	count.revert:SetPoint("TOPRIGHT", count.status, "BOTTOM", -6, -12)
	count.keep:SetPoint("TOPLEFT", count.status, "BOTTOM", 6, -12)
	return 20 + RING + 12 + 130
end

-- the Done content, made the first time it is needed
local DONE_ACTS = { "reload", "tour", "open", "again", "close" }
local function DoneGroup(page)
	local done = page.done
	if done then
		return done
	end
	done = CreateFrame("Frame", nil, page)
	done:SetAllPoints(page)
	done.title = W.Text(done, "GameFontHighlightLarge", nil, "selectedTrim")
	done.title:SetJustifyH("CENTER")
	done.title:SetPoint("TOP", page, "TOP", 0, -(20 + RING + 12))
	done.lines = W.Text(done, "GameFontHighlight", nil, "text")
	done.lines:SetJustifyH("CENTER")
	done.lines:SetWidth(TEXT_W)
	done.lines:SetPoint("TOP", done.title, "BOTTOM", 0, -10)
	done.buttons = {}
	for _, act in ipairs(DONE_ACTS) do
		done.buttons[act] = Button(done, TEXT[act], DONE_BUTTON_W, act)
	end
	done.shown = {}
	page.done = done
	return done
end

-- the countdown's number, its pause, Revert held in combat and while Edit
-- Mode is open, Keep gone for an install that could not be put back or a
-- revert that only partly worked (the engine's `failed`)
RefreshKeep = function()
	local page = win and win.pages.keep
	if not page or state.phase ~= "keep" then
		return
	end
	local count = page.count
	local running, seconds, paused, why = I:Countdown()
	page.numeral:SetShown(running)
	if running then
		page.numeral:SetText(NUMS[seconds] or tostring(seconds))
	end
	local line = state.keepLine
	local held = false
	if paused then
		line = why == "combat" and I.TEXT.pausedCombat or I.TEXT.pausedEditMode
		held = true
	elseif InCombat() then
		line, held = I.TEXT.pausedCombat, true
	end
	count.status:SetText(line or "")
	count.revert:SetEnabled(not held)
	local pending = Pending()
	count.keep:SetShown(not (pending and pending.failed))
	-- only Keep or Revert while the countdown runs
	SetClosable(not running)
end

local function RefreshKeepPage(page)
	if state.phase == "done" then
		return nil
	end
	page.count:Show()
	if page.done then
		page.done:Hide()
	end
	page.emblemAlpha = 0.35
	if page.emblem then
		page.emblem:SetAlpha(0.35)
	end
	RefreshKeep()
	return nil
end

STEPS.keep.build, STEPS.keep.refresh = BuildKeep, RefreshKeepPage

-- The Keep page: after Install (the 'installed' Fire), after a /reload or a
-- restart with the answer still owed, or for an install that could not be
-- put back
ShowKeep = function(dir)
	state.phase, state.step, state.doneMode, state.footLine = "keep", "keep", nil, nil
	Present("keep", dir)
end

-- Done, on the Keep page: kept (Reload now when the fonts over heads
-- changed) or reverted (Reload to finish when owed); the tour, the
-- configurator, Choose again, Close
ShowDone = function()
	state.phase, state.step = "done", "keep"
	local page = PageOf("keep")
	page.count:Hide()
	page.numeral:Hide()
	page.emblemAlpha = 1
	if page.emblem then
		page.emblem:SetAlpha(1)
	end
	local done = DoneGroup(page)
	local kept = state.doneMode == "kept"
	local option = Option()
	local lines = {}
	if kept then
		done.title:SetText(TEXT.doneTitle)
		if state.needsReload then
			lines[#lines + 1] = TEXT.doneReload
		end
		if option.base == "fresh" then
			-- (read from the settings now, as the engine reads a state: kept
			-- after a /reload, the draft is gone)
			local now = { enabled = MelloUI.db.enabled, modules = { UIModifications = MelloUI:GetModuleDB("UIModifications") } }
			local any = false
			for _, group in ipairs(I.FEATURE_GROUPS) do
				for _, name in ipairs(group.members) do
					any = any or I:EffectiveOn(now, name)
				end
			end
			lines[#lines + 1] = any and TEXT.doneFeatures or TEXT.doneFresh
		end
		lines[#lines + 1] = TEXT.doneWhere
	else
		done.title:SetText(TEXT.revertedTitle)
		if state.reason == "error" then
			lines[#lines + 1] = I.TEXT.failed
		end
		if state.reloadOwed then
			lines[#lines + 1] = TEXT.revertedReload
		end
	end
	done.lines:SetText(concat(lines, "\n"))
	-- the buttons of this ending, in a centred row
	local shown = done.shown
	for i = #shown, 1, -1 do
		shown[i] = nil
	end
	local owed = kept and state.needsReload or (not kept and state.reloadOwed)
	for _, act in ipairs(DONE_ACTS) do
		local want
		if act == "reload" then
			want = owed
		elseif act == "tour" or act == "open" then
			want = kept
		elseif act == "again" then
			want = not kept
		else
			want = true
		end
		local b = done.buttons[act]
		b:SetShown(want and true or false)
		if want then
			shown[#shown + 1] = b
		end
	end
	local total = #shown * DONE_BUTTON_W + (#shown - 1) * 8
	for i, b in ipairs(shown) do
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", done.lines, "BOTTOM", -total / 2 + (i - 1) * (DONE_BUTTON_W + 8), -16)
	end
	done:Show()
	SetClosable(true)
	page.melloHeight = 20 + RING + 12 + 40 + (Num(done.lines:GetStringHeight()) or 30) + 16 + BUTTON_H + 12
	win.pager:SetPageHeight(page, page.melloHeight)
	win.pager:Show(page, 0)
	SetTitle()
	RailRefresh()
	RefreshFooter()
end

--------------------------------------------------------------------------------
-- The Fresh start wizard: the Look, Parchment and dark mode, Fonts,
-- Chat and Windows steps. Every control reads and writes Fresh start's
-- draft and nothing else: the settings are written by Install, in its one
-- Batch. Each starts at Full's value (I:DefaultDraft). The lists come from
-- where they live, one system each: the Kit Colours and the Button Border
-- looks from the kit (Kit.borderKinds, whose Kit Colours are
-- Kit.colourLooks), the parchment areas from Dynamic UI Modification
-- (MelloUI.ParchmentAreas), the Font Styles from Fonts (MelloUI.FontStyles,
-- MelloUI.FontStyleSettings), the name forms and the descriptions from the
-- modules' own registrations, the windows from the registry grouped by
-- I.WINDOW_GROUPS. A row (or the colour cards) that means nothing while a
-- switch is off sleeps, dimmed, and says which switch wakes it (W.Gate;
-- indented under a switch on its own page). UI Modifications itself is on
-- while anything the draft asks for runs under it. Pictures, never a live
-- preview (user, 2026-09-25: a Kit Colours switch walks every kit texture): a colour
-- card shows the kit's window frame as that look's folder holds it, a font
-- card its own faces. Each page is made on its first show, its rows (and
-- the font cards' faces) within one budget a frame; a click changes the
-- draft, drops the setup's fit and lays the page on show again (its
-- gates), nothing more.
--------------------------------------------------------------------------------

-- (a function's own scope: the file's main chunk is close to Lua's 200
-- locals; defined and run once while the file loads, making no frame)
local function WizardSteps()
	local FRESH = "fresh"
	local UMBRELLA_ON = "!UIModifications"
	local RESKIN = "UIModifications.reskin"
	local COLOURS_KEY, BORDER_KEY = "UIModifications.kitColours", "UIModifications.buttonBorder"
	local ICONS_ON, PORTRAITS = "UIModifications.qol_ClassIcons", "ClassIcons.portraits"
	local DARK_ON, SHADE = "UIModifications.qol_DarkMode", "DarkMode.shade"
	local FONTS_ON, FONT_STYLE = "UIModifications.qol_Fonts", "Fonts.style"
	local CHAT_ON, NAME_STYLE, NAME_SHADE = "UIModifications.qol_Chat", "Chat.nameStyle", "Chat.nameShade"
	-- the wizard's switches of what runs under UI Modifications: it is on while
	-- any of them is
	local UMBRELLA = { RESKIN, ICONS_ON, DARK_ON, FONTS_ON, CHAT_ON }
	-- the parchment sheets whose dark ink is Chat's (the engine's ink guard,
	-- I.INK, for the chat windows; the whisper popups are Chat's own)
	local CHAT_SHEETS = { parchment_chat = true, parchment_whisper = true }
	local KEEP_FACE = "default"   -- a Fonts role on "Keep the game's"
	local GATE_INDENT = 22        -- a row that sleeps under a switch on its own page
	local HEADING_H = 28          -- (the configurator's heading: a row's 34 less 6; W is not read at load)
	local COLOUR_GAP = 10
	local COLOUR_W = floor((PAGE_W - 2 * COLOUR_GAP) / 3)
	local COLOUR_H = 120
	local FRAME_PIC_H = 64        -- a colour card's picture: the kit's window frame on its body
	local FONT_H = 70
	local TITLE_BASE, TEXT_BASE = 20, 13   -- a font card's samples before their faces' size factors (Morpheus-, Friz-sized)
	local GAME_TITLE, GAME_TEXT = "Fonts\\MORPHEUS.TTF", "Fonts\\FRIZQT__.TTF"   -- (when the game's objects read nothing)

	local function Wizard()
		return DraftFor(FRESH)
	end

	-- a switch in the draft: on unless false, as the setting it stands for
	local function On(key)
		return Wizard()[key] ~= false
	end

	-- the Features step's switch keys (I.FEATURE_GROUPS, I.SwitchKey), and
	-- those of them that run under UI Modifications; read once, the first
	-- time asked (the modules register after this file)
	local featureKeys, featureUM = nil, nil
	local function FeatureKeys()
		if not featureKeys then
			featureKeys, featureUM = {}, {}
			for _, group in ipairs(I.FEATURE_GROUPS) do
				for _, name in ipairs(group.members) do
					local key = I.SwitchKey(MelloUI:GetModule(name))
					if key then
						featureKeys[#featureKeys + 1] = key
						if key:sub(1, 16) == "UIModifications." then
							featureUM[#featureUM + 1] = key
						end
					end
				end
			end
		end
		return featureKeys, featureUM
	end

	-- the draft changed: UI Modifications on while anything under it is
	-- wanted; the Screen step's fit dropped (the fitter reads the kit
	-- minimap column -- the reskin, The HUD -- and Tweaks, which the wizard
	-- changes after that step and on a way back: Review fits again, Install
	-- waits for it, and unchanged inputs answer from the fitter's last fit);
	-- then the page on show (its gates) and the footer again (quiet: not, for
	-- a slider's drag)
	local function DraftChanged(quiet)
		local d = Wizard()
		local want = false
		for i = 1, #UMBRELLA do
			if d[UMBRELLA[i]] ~= false then
				want = true
				break
			end
		end
		-- (a folded feature switched on keeps it on too: only a true counts,
		-- the Features step's switches begin false)
		local _, folded = FeatureKeys()
		for i = 1, want and 0 or #folded do
			if d[folded[i]] == true then
				want = true
				break
			end
		end
		d[UMBRELLA_ON] = want
		local fit = state.fits[FRESH]
		if fit then
			I:CancelFit(fit)
			state.fits[FRESH] = nil
		end
		if not quiet then
			IW:Refresh()
		end
	end

	local function Put(key, value, quiet)
		Wizard()[key] = value
		DraftChanged(quiet)
	end

	-- the gates: live, or the switch that wakes the row
	local function ReskinGate()
		if On(RESKIN) then
			return true
		end
		return false, TEXT.reskin
	end

	local function ChatGate()
		if On(CHAT_ON) then
			return true
		end
		return false, TEXT.chatTweaks
	end

	-- a chat sheet: the kit's, its ink Chat tweaks'
	local function ChatSheetGate()
		if not On(RESKIN) then
			return false, TEXT.reskin
		end
		return ChatGate()
	end

	local function DarkGate()
		if On(DARK_ON) then
			return true
		end
		return false, TEXT.darkMode
	end

	local function RowOpts(zebra, gate, indent)
		return { skin = win.shell, look = "palette", zebra = zebra, gate = gate, indent = indent }
	end

	-- a module's option by its key, and a folded feature's own description:
	-- read from the registration where they live
	local function OptionOf(name, key)
		local m = MelloUI:GetModule(name)
		local options = m and type(m.options) == "table" and m.options or EMPTY
		for i = 1, #options do
			local opt = options[i]
			if type(opt) == "table" and opt.key == key then
				return opt
			end
		end
		return nil
	end

	local function TweakDesc(name)
		local m = MelloUI:GetModule(name)
		return m and type(m.tweak) == "table" and m.tweak.desc or nil
	end

	-- a switch row over one draft key (`default`: its value while the draft
	-- has none)
	local function KeyRow(page, label, hint, desc, key, default, opts)
		local function Get()
			local v = Wizard()[key]
			if v == nil then
				return default
			end
			return v and true or false
		end
		local function Set(on)
			Put(key, on and true or false)
		end
		return (W.ToggleRow(page, 0, label, hint, desc, Get, Set, opts))
	end

	-- A page's parts, laid top to bottom on every refresh: x, the height (nil:
	-- a text's own), the gap under it, and whether it spans the page; a hidden
	-- part takes no room. Flow returns the page's height.
	local function Part(flow, region, x, h, gap, wide)
		flow[#flow + 1] = { region = region, x = x or 0, h = h, gap = gap or 0, wide = wide }
		return region
	end

	-- A row made once the page shows, within the frame's budget of rows (the
	-- configurator's: 3 ms of them in the frame the page first shows, 2.5 ms
	-- in each frame after while it fades in), in the page's order; its room
	-- kept from the start, so nothing moves when it comes. LaterWork: work
	-- with no room of its own (a font card's faces) in the same budget.
	local FIRST_ROWS, LATER_ROWS = 3, 2.5
	local function Owe(page, entry)
		local todo = page.todo
		if not todo then
			todo = {}
			page.todo, page.nextTodo = todo, 1
		end
		todo[#todo + 1] = entry
		page.owed = (page.owed or 0) + 1
	end

	local function LaterRow(page, make, h, gap)
		local part = { make = make, x = 0, h = h, gap = gap or 0, wide = true }
		page.flow[#page.flow + 1] = part
		Owe(page, part)
	end

	local function LaterWork(page, work, arg)
		Owe(page, { work = work, arg = arg })
	end

	local function Flow(page)
		local y = 10
		for _, part in ipairs(page.flow) do
			local r = part.region
			if not r then
				y = y + part.h + part.gap   -- (a row still to come)
			elseif r:IsShown() then
				r:ClearAllPoints()
				r:SetPoint("TOPLEFT", page, "TOPLEFT", part.x, -y)
				if part.wide then
					r:SetPoint("RIGHT", page, "RIGHT", 0, 0)
				end
				y = y + (part.h or Num(r:GetStringHeight()) or 14) + part.gap
			end
		end
		return y + 10
	end

	local function Clock()
		return Num(debugprofilestop and debugprofilestop()) or 0
	end

	local MoreRows   -- (below: the next frame's rows)

	-- the page's rows still to come, in order, until `ms` of this frame's
	-- rows are spent (a row under way is finished); the rest on the next
	-- frame, asked for first (a row that fails leaves the rest to it). A row
	-- is counted as made as it begins: one that fails is not owed for ever.
	-- One budget of rows a frame, whoever asks (the click that shows a page,
	-- a click on a row while rows are owed, the next frame's rows, the
	-- configurator's pages): the widget set's, W.RowBudget.
	local function MakeRows(page, ms)
		if (page.owed or 0) == 0 then
			return
		end
		local Kit = MelloUI.Kit
		if Kit and Kit.NextFrame then
			Kit:NextFrame(page, MoreRows)
		else
			ms = math.huge   -- (no next frame to wait for: all of them now)
		end
		local stop = W.RowBudget.Begin(ms)
		if not stop then
			return
		end
		local todo = page.todo
		repeat
			local n = page.nextTodo
			local entry = todo[n]
			todo[n] = false
			page.nextTodo, page.owed = n + 1, page.owed - 1
			if entry.work then
				entry.work(entry.arg)
			else
				local row = entry.make(page)
				entry.make, entry.region = nil, row
				page.rows[#page.rows + 1] = row
				row:Refresh()
			end
		until page.owed == 0 or Clock() >= stop
		W.RowBudget.End()
	end

	-- (a page no longer on show waits: its rows come when it shows again)
	MoreRows = function(page)
		if page.owed > 0 and win and win.frame:IsShown() and page:IsShown() then
			MakeRows(page, LATER_ROWS)
			Flow(page)
		end
	end

	local function RefreshRows(page)
		for _, row in ipairs(page.rows) do
			row:Refresh()
		end
	end

	local function RefreshWizard(page)
		RefreshRows(page)
		MakeRows(page, FIRST_ROWS)
		return Flow(page)
	end

	local function Lead(page, text)
		local fs = W.Text(page, "GameFontHighlight", text, "text")
		fs:SetWidth(TEXT_W)
		return fs
	end

	-- a heading over a group: the configurator's (the kit's header plate, the
	-- words past its gem, in gold; plain, a line under them)
	local function DressHeading(_, row, shell)
		if shell:Replace(shell:Anchor(row, "BACKGROUND"), { as = "GuildFrame-Header", rect = row }) then
			row.label:SetPoint("LEFT", row, "LEFT", 34, 0)
		end
	end

	local function Heading(page, text)
		local shell = win.shell
		local row = W.Row(page, 0, HEADING_H, text, nil, nil, { labelKey = "selectedTrim" })
		row:EnableMouse(false)
		local line = W.Solid(row, "ARTWORK", "border", 1)
		line:SetHeight(1)
		line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 0)
		line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 0)
		shell:Plain(line)
		shell:Kit(DressHeading, row, shell)
		return row
	end

	-- a card's tooltip (the Font Styles' own words)
	local CardTip = Shared("OnEnter on the installer's choice cards (tooltip)", function(card)
		if card.tipBody then
			W.ShowTooltip(card, card.tipTitle, card.tipBody)
		end
	end, "script")

	local function Tip(card, title, body)
		card.tipTitle, card.tipBody = title, body
		Perf.HookScript(card, "OnEnter", CardTip)
		Perf.HookScript(card, "OnLeave", W.TipLeave)
	end

	-- a grid of cards on a holder that spans the page, `across` to a line
	local function Grid(page, count, across, h, gapY)
		local grid = CreateFrame("Frame", nil, page)
		local lines = floor((count + across - 1) / across)
		grid.melloH = lines > 0 and (lines * h + (lines - 1) * gapY) or 0
		grid:SetHeight(grid.melloH > 0 and grid.melloH or 1)
		return grid
	end

	--------------------------------------------------------------------------------
	-- Look: the reskin, the Kit Colours (a picture each), Button Border, the
	-- class icons
	--------------------------------------------------------------------------------

	local function BorderKind(key)
		local Kit = MelloUI.Kit
		local kinds = Kit and type(Kit.borderKinds) == "table" and Kit.borderKinds or EMPTY
		for i = 1, #kinds do
			if kinds[i].key == key then
				return kinds[i]
			end
		end
		return nil
	end

	-- the window frame's one-texture picture (the kit's slices), when whole
	local function FrameSlice()
		local slices = _G.MelloUI_KitSlices
		local slice = type(slices) == "table" and slices["window/frame"]
		if type(slice) == "table" and type(slice.full) == "string" and type(slice.grid) == "table" and type(slice.size) == "table" then
			return slice
		end
		return nil
	end

	-- the folder a look's pieces are read from (the kit's own rule: the painted
	-- pieces in Media\Kit, each recoloured look's in a folder of the same files)
	local function LookRoot(look)
		local layout = MelloUI_KitLayout
		local root = type(layout) == "table" and layout.root
		if type(root) ~= "string" then
			return nil
		end
		return look.folder and (root:gsub("Kit\\$", look.folder .. "\\")) or root
	end

	-- A colour card's picture: the kit's window frame on the frame's own body,
	-- both from that look's folder, at the frame's own shape. Not kit
	-- textures, so the kit's colour switch never repaints them.
	local function ColourPicture(card, root, slice)
		local gw, gh = slice.grid[1], slice.grid[2]
		local pic = card.picture
		pic:ClearAllPoints()
		pic:SetPoint("TOP", card, "TOP", 0, -8)
		pic:SetSize(floor(FRAME_PIC_H * gw / gh + 0.5), FRAME_PIC_H)
		pic:SetTexCoord(0, gw / slice.size[1], 0, gh / slice.size[2])
		local pieces = MelloUI_KitLayout.pieces
		local body = type(pieces) == "table" and pieces["window/frame_body"]
		if type(body) == "table" and type(body.file) == "string" and body.w and body.h then
			local texel = slice.texel or 1
			local u, v = min(1, gw * texel / body.w), min(1, gh * texel / body.h)
			local uv = type(body.uv) == "table" and body.uv or nil
			local l, r, t, b = uv and uv[1] or 0, uv and uv[2] or 1, uv and uv[3] or 0, uv and uv[4] or 1
			local tex = card:CreateTexture(nil, "ARTWORK", nil, -1)
			tex:SetAllPoints(pic)
			tex:SetTexture(root .. body.file)
			tex:SetTexCoord(l, l + (r - l) * u, t, t + (b - t) * v)
			card.body = tex
		end
	end

	local function ColourPick(card)
		if On(RESKIN) then
			Put(COLOURS_KEY, card.key)
		end
	end

	local function IconsGet()
		return On(ICONS_ON) and On(PORTRAITS)
	end

	local function IconsSet(on)
		if on then
			Wizard()[PORTRAITS] = true
		end
		Put(ICONS_ON, on and true or false)
	end

	local function ReskinRow(page)
		return KeyRow(page, TEXT.reskin, nil, TEXT.reskinDesc, RESKIN, true, RowOpts(true))
	end

	local function IconsRow(page)
		return (W.ToggleRow(page, 0, TEXT.classIcons, nil, TweakDesc("ClassIcons"), IconsGet, IconsSet, RowOpts(false)))
	end

	-- Button Border: the kit's own choice row, under the reskin
	local function BorderGet()
		local border = BorderKind("buttonBorder")
		return Wizard()[BORDER_KEY] or (border and border.default)
	end

	local function BorderSet(value)
		Put(BORDER_KEY, value)
	end

	local function BorderRow(page)
		local border = BorderKind("buttonBorder")
		return (W.DropdownRow(page, 0, border.name, nil, border.desc, BorderGet, BorderSet, border.values,
			RowOpts(true, ReskinGate, GATE_INDENT)))
	end

	local function BuildLook(page)
		Wizard()
		local flow = {}
		page.flow, page.rows, page.colours = flow, {}, {}
		Part(flow, Lead(page, TEXT.lookLead), PAD, nil, 10)
		LaterRow(page, ReskinRow, W.ROW_HEIGHT, 10)
		-- the Kit Colours: a card each, three to a line, with its picture
		local heading = Part(flow, Heading(page, TEXT.colours), 0, HEADING_H, 8, true)
		local kind = BorderKind("kitColours")
		local looks = kind and type(kind.values) == "table" and kind.values or EMPTY
		local grid = Grid(page, #looks, 3, COLOUR_H, COLOUR_GAP)
		local slice = FrameSlice()
		for i, look in ipairs(looks) do
			local root = slice and LookRoot(look)
			local card = W.Card(grid, { width = COLOUR_W, height = COLOUR_H, title = look.label, text = TEXT.colourLine[look.value],
				key = look.value, picture = root and (root .. slice.full) or nil, pictureHeight = FRAME_PIC_H, onClick = ColourPick }, win.shell)
			card:SetPoint("TOPLEFT", grid, "TOPLEFT", ((i - 1) % 3) * (COLOUR_W + COLOUR_GAP), -floor((i - 1) / 3) * (COLOUR_H + COLOUR_GAP))
			if root then
				ColourPicture(card, root, slice)
			end
			page.colours[i] = card
		end
		Part(flow, grid, 0, grid.melloH, 6, true)
		-- asleep with the reskin off as a row is (W.Gate: dimmed, its cover
		-- taking the clicks with the tooltip; its line under the cards, on the
		-- page, read at full strength)
		local line = Part(flow, W.Text(page, "GameFontHighlight", nil, "text"), PAD, nil, 8)
		line:SetWidth(TEXT_W)
		line:Hide()
		grid.label, grid.hint = heading.label, line
		page.coloursGate, page.coloursCover = line, W.Gate(grid, ReskinGate)
		local border = BorderKind("buttonBorder")
		if border and type(border.values) == "table" then
			LaterRow(page, BorderRow, W.ROW_HEIGHT, 0)
		end
		LaterRow(page, IconsRow, W.ROW_HEIGHT, 0)
		return 1
	end

	local function RefreshLook(page)
		local chosen = Wizard()[COLOURS_KEY]
		if chosen == nil then
			local kind = BorderKind("kitColours")
			chosen = kind and kind.default
		end
		for _, card in ipairs(page.colours) do
			local on = card.key == chosen
			if card:IsSelected() ~= on then
				card:SetSelected(on)
			end
		end
		page.coloursCover:Refresh()
		return RefreshWizard(page)
	end

	STEPS.look.build, STEPS.look.refresh = BuildLook, RefreshLook

	--------------------------------------------------------------------------------
	-- Minimap: Round or Square, a card each with the kit piece of that shape
	-- (MinimapPanel's own list, its PickerGroups), and Merge With Services
	-- (square only). The page sleeps with the reskin off or the HUD's minimap
	-- off (the Windows step). Square carries Full's border and merge with it.
	--------------------------------------------------------------------------------

	local MAP_SHAPE, MAP_BORDER, MAP_MERGE = "MinimapPanel.shape", "MinimapPanel.squareBorder", "MinimapPanel.servicesMerge"
	local MAP_HUD = "UIModifications.MinimapPanel"
	local MAP_H, MAP_PIC = 118, 64   -- a shape card; its picture's height

	-- MinimapPanel's shapes (its picker's own list) and their heading
	local function MapChoices()
		local mm = MelloUI:GetModule("MinimapPanel")
		local ok, groups = false, nil
		if mm and mm.PickerGroups then
			ok, groups = pcall(mm.PickerGroups, mm)
		end
		local group = ok and type(groups) == "table" and groups[1]
		local sections = type(group) == "table" and type(group.sections) == "table" and group.sections or EMPTY
		for _, section in ipairs(sections) do
			if section.key == "shape" and type(section.choices) == "table" then
				return section.choices, section.title
			end
		end
		return EMPTY, nil
	end

	-- the HUD group's name on the Windows step (the switch that holds the minimap)
	local function HudLabel()
		for _, group in ipairs(I.WINDOW_GROUPS) do
			if group.key == "hud" then
				return group.label
			end
		end
		return nil
	end

	local function MapGate()
		if not On(RESKIN) then
			return false, TEXT.reskin
		elseif not On(MAP_HUD) then
			return false, HudLabel() or TEXT.reskin
		end
		return true
	end

	local function MapShape()
		local v = Wizard()[MAP_SHAPE]
		if v == nil then
			local mm = MelloUI:GetModule("MinimapPanel")
			v = mm and type(mm.defaults) == "table" and mm.defaults.shape or nil
		end
		return v
	end

	-- the merge row's line while round is chosen ('Pick "Square" first.',
	-- the square card's name): made once, the first time it shows (the
	-- picker's list is built on each call, so never read in a gate)
	local pickSquare = nil
	local function PickSquareLine()
		if not pickSquare then
			local label
			for _, choice in ipairs((MapChoices())) do
				if choice.value == "square" then
					label = choice.label
				end
			end
			pickSquare = TEXT.mapPickSquare:format(label or "square")
		end
		return pickSquare
	end

	-- (round chosen: asleep with no switch named -- a card is picked, not
	-- switched; the row's own Refresh, below, says which)
	local function MergeGate()
		local live, why = MapGate()
		if not live then
			return false, why
		elseif MapShape() ~= "square" then
			return false
		end
		return true
	end

	local function MapPick(card)
		if not MapGate() then
			return
		end
		if card.key == "square" then
			local d, full = Wizard(), wizardFull or EMPTY
			if d[MAP_BORDER] == nil then
				d[MAP_BORDER] = full[MAP_BORDER]
			end
			if d[MAP_MERGE] == nil then
				d[MAP_MERGE] = full[MAP_MERGE]
			end
		end
		Put(MAP_SHAPE, card.key)
	end

	-- A shape card's picture: the kit piece itself from the kit's own folder,
	-- at its own shape, the map's place in it (the piece's opening) in the
	-- window's colour. Not a kit texture: the kit never repaints it.
	local function MapPicture(card, name)
		local layout = MelloUI_KitLayout
		local pieces = type(layout) == "table" and layout.pieces
		local p = type(pieces) == "table" and pieces[name]
		if not (type(p) == "table" and type(p.file) == "string" and Num(p.w) and Num(p.h) and card.picture) then
			return
		end
		local pic = card.picture
		pic:ClearAllPoints()
		pic:SetPoint("TOP", card, "TOP", 0, -8)
		pic:SetSize(floor(MAP_PIC * p.w / p.h + 0.5), MAP_PIC)
		if type(p.uv) == "table" then
			pic:SetTexCoord(p.uv[1], p.uv[2], p.uv[3], p.uv[4])
		end
		if type(p.open) == "table" then
			local s = MAP_PIC / p.h
			local inside = card:CreateTexture(nil, "ARTWORK", nil, -1)
			inside:SetPoint("TOPLEFT", pic, "TOPLEFT", p.open[1] * s, -p.open[2] * s)
			inside:SetPoint("BOTTOMRIGHT", pic, "TOPLEFT", p.open[3] * s, -p.open[4] * s)
			W.Paint(inside, "mainWindow", "fill", 1)
			card.inside = inside
		end
	end

	-- the merge row's Refresh: the widget set's (its control, its gate),
	-- then, round chosen on a live page, the line that says to pick square
	local mergeRefresh = nil
	local function MergeRefresh(row)
		mergeRefresh(row)
		if row.hint and MapGate() and MapShape() ~= "square" then
			row.hint:SetText(PickSquareLine())
			row.hint:Show()
		end
	end

	local function MergeRow(page)
		local opt = OptionOf("MinimapPanel", "servicesMerge")
		local row = KeyRow(page, opt and opt.name or MAP_MERGE, TEXT.mapMergeHint, opt and opt.desc, MAP_MERGE, true,
			RowOpts(true, MergeGate, GATE_INDENT))
		mergeRefresh = mergeRefresh or row.Refresh
		row.Refresh = MergeRefresh
		return row
	end

	local function BuildMap(page)
		Wizard()
		local flow = {}
		page.flow, page.rows, page.shapes = flow, {}, {}
		Part(flow, Lead(page, TEXT.mapLead), PAD, nil, 10)
		local choices, title = MapChoices()
		local heading = Part(flow, Heading(page, title or STEPS.map.title), 0, HEADING_H, 8, true)
		local layout = MelloUI_KitLayout
		local root = type(layout) == "table" and type(layout.root) == "string" and layout.root or nil
		local pieces = type(layout) == "table" and type(layout.pieces) == "table" and layout.pieces or EMPTY
		local grid = Grid(page, #choices, 2, MAP_H, CARD_GAP_Y)
		for i, choice in ipairs(choices) do
			local p = choice.piece and pieces[choice.piece]
			local file = root and type(p) == "table" and type(p.file) == "string" and (root .. p.file) or nil
			local card = W.Card(grid, { width = CARD_W, height = MAP_H, title = choice.label, text = TEXT.mapLine[choice.value],
				key = choice.value, picture = file, pictureHeight = MAP_PIC, onClick = MapPick }, win.shell)
			card:SetPoint("TOPLEFT", grid, "TOPLEFT", ((i - 1) % 2) * (CARD_W + CARD_GAP_X), -floor((i - 1) / 2) * (MAP_H + CARD_GAP_Y))
			if file then
				MapPicture(card, choice.piece)
			end
			page.shapes[i] = card
		end
		Part(flow, grid, 0, grid.melloH, 6, true)
		-- asleep as the Look step's cards are (W.Gate; its line under them)
		local line = Part(flow, W.Text(page, "GameFontHighlight", nil, "text"), PAD, nil, 8)
		line:SetWidth(TEXT_W)
		line:Hide()
		grid.label, grid.hint = heading.label, line
		page.shapesGate, page.shapesCover = line, W.Gate(grid, MapGate)
		LaterRow(page, MergeRow, W.ROW_HEIGHT, 0)
		return 1
	end

	local function RefreshMap(page)
		local shape = MapShape()
		for _, card in ipairs(page.shapes) do
			local on = card.key == shape
			if card:IsSelected() ~= on then
				card:SetSelected(on)
			end
		end
		page.shapesCover:Refresh()
		return RefreshWizard(page)
	end

	STEPS.map.build, STEPS.map.refresh = BuildMap, RefreshMap

	--------------------------------------------------------------------------------
	-- Parchment and dark mode: a switch per parchment area (the kit's sheets:
	-- asleep with the reskin off; the chat's also with Chat tweaks off), Dark
	-- mode and its brightness
	--------------------------------------------------------------------------------

	-- an area's sheet switch
	local function SheetRow(key, label, zebra)
		local gate = CHAT_SHEETS[key] and ChatSheetGate or ReskinGate
		local draftKey = "UIModifications." .. key
		return function(page)
			return KeyRow(page, label, nil, nil, draftKey, false, RowOpts(zebra, gate))
		end
	end

	local function DarkRow(page)
		return KeyRow(page, TEXT.darkMode, nil, TweakDesc("DarkMode"), DARK_ON, false, RowOpts(true))
	end

	-- the brightness: the Dark Mode option's own range
	local function ShadeGet()
		local dark = MelloUI:GetModule("DarkMode")
		local default = dark and type(dark.defaults) == "table" and Num(dark.defaults.shade) or 0.25
		return Num(Wizard()[SHADE]) or default
	end

	local function ShadeSet(value)
		Put(SHADE, value, true)
	end

	local function ShadeRow(page)
		local opt = OptionOf("DarkMode", "shade")
		local sopts = RowOpts(false, DarkGate, GATE_INDENT)
		sopts.min, sopts.max = opt and opt.min or 0, opt and opt.max or 1
		sopts.step, sopts.percent = opt and opt.step or 0.05, (opt == nil or opt.percent) and true or false
		return (W.SliderRow(page, 0, TEXT.brightness, nil, TEXT.brightnessDesc, ShadeGet, ShadeSet, sopts))
	end

	local function BuildParchment(page)
		Wizard()
		local flow = {}
		page.flow, page.rows = flow, {}
		Part(flow, Lead(page, TEXT.parchmentLead), PAD, nil, 10)
		Part(flow, Heading(page, TEXT.parchment), 0, HEADING_H, 4, true)
		for i, area in ipairs(type(MelloUI.ParchmentAreas) == "table" and MelloUI.ParchmentAreas or EMPTY) do
			local key, label = area[1], area[2]
			if type(key) == "string" and type(label) == "string" then
				LaterRow(page, SheetRow(key, label, i % 2 == 1), W.ROW_HEIGHT, 0)
			end
		end
		flow[#flow].gap = 12
		LaterRow(page, DarkRow, W.ROW_HEIGHT, 0)
		LaterRow(page, ShadeRow, W.SLIDER_ROW_HEIGHT, 0)
		return 1
	end

	STEPS.parchment.build, STEPS.parchment.refresh = BuildParchment, RefreshWizard

	--------------------------------------------------------------------------------
	-- Fonts: a card per choice -- Mello's own faces (Full's), each Font Style,
	-- the game's -- each showing a title in its title face and a line in its
	-- reading face (set on the card's own texts: pictures of the faces, not
	-- the fonts in use)
	--------------------------------------------------------------------------------

	local gameFaces = nil   -- the game's own title and text faces (read on the Fonts step's first show)
	local function GameFaces()
		if not gameFaces then
			local _, title = MorpheusObject()
			gameFaces = { title = title or GAME_TITLE, text = BaseFace(_G.GameFontNormal) or GAME_TEXT }
		end
		return gameFaces
	end

	local function Face(path, fallback)
		if type(path) ~= "string" or path == "" or path == KEEP_FACE then
			return fallback
		end
		return path
	end

	local function IsStyle(value)
		for _, style in ipairs(type(MelloUI.FontStyles) == "table" and MelloUI.FontStyles or EMPTY) do
			if style.value == value then
				return true
			end
		end
		return false
	end

	-- the card the draft names: the game's with the Fonts switch off, a Font
	-- Style by name, else Mello's own
	-- Full's own Font Style, when it names one (the 2026-09-26 Full is Gothic):
	-- that style IS Mello's fonts, so it has no card of its own besides
	-- Mello's, and a draft naming it reads as Mello's
	local function FullStyle()
		local s = (wizardFull or EMPTY)[FONT_STYLE]
		return type(s) == "string" and IsStyle(s) and s or nil
	end

	local function FontChoice(d)
		if d[FONTS_ON] == false then
			return "game"
		end
		local style = d[FONT_STYLE]
		if type(style) == "string" and IsStyle(style) then
			return style == FullStyle() and "mello" or style
		end
		return "mello"
	end

	function IW:FontChoice(d)
		return FontChoice(type(d) == "table" and d or Wizard())
	end

	-- the cards: Mello's own faces (Full's), the Font Styles, the game's
	local function FontCards()
		local game, full = GameFaces(), wizardFull or EMPTY
		local settings = MelloUI.FontStyleSettings
		-- Mello's card: Full's own faces over its Font Style's (if it names one)
		local own = FullStyle()
		local base = own and type(settings) == "function" and settings(own)
		base = type(base) == "table" and base or EMPTY
		local list = { { key = "mello", tag = TEXT.melloFonts, tip = TEXT.melloFontsTip,
			title = Face(full["Fonts.fontTitle"], Face(base.fontTitle, game.title)),
			titleScale = Num(full["Fonts.scaleTitle"]) or Num(base.scaleTitle) or 1,
			text = Face(full["Fonts.fontText"], Face(base.fontText, game.text)),
			textScale = Num(full["Fonts.scaleText"]) or Num(base.scaleText) or 1 } }
		for _, style in ipairs(type(MelloUI.FontStyles) == "table" and MelloUI.FontStyles or EMPTY) do
			local set = style.value ~= own and type(settings) == "function" and settings(style.value)
			if type(set) == "table" then
				list[#list + 1] = { key = style.value, tag = style.label, tip = style.desc,
					title = Face(set.fontTitle, game.title), titleScale = Num(set.scaleTitle) or 1,
					text = Face(set.fontText, game.text), textScale = Num(set.scaleText) or 1 }
			end
		end
		list[#list + 1] = { key = "game", tag = TEXT.gameFonts, tip = TEXT.gameFontsTip,
			title = game.title, titleScale = 1, text = game.text, textScale = 1 }
		return list
	end

	-- a sample in a face of its own (a face the client cannot load: the game's)
	local function SampleFont(fs, face, size, fallback)
		size = floor(size + 0.5)
		local ok, set = pcall(fs.SetFont, fs, face, size, "")
		if not ok or set == false then
			pcall(fs.SetFont, fs, fallback, size, "")
		end
	end

	-- A pick: the game's switches the Fonts off; Mello's puts Full's font
	-- settings back; a Font Style puts Full's back, then names the style alone,
	-- its faces and sizes filled in from it when the setup is made (I:Draft:
	-- written after the faces, the style would read Custom)
	local function FontPick(card)
		local key = card.key
		if key == "game" then
			Put(FONTS_ON, false)
			return
		end
		local d = Wizard()
		for k, v in pairs(wizardFull or EMPTY) do
			if type(k) == "string" and k:sub(1, 6) == "Fonts." then
				d[k] = I.DeepCopy(v)
			end
		end
		if key ~= "mello" then
			local set = MelloUI.FontStyleSettings and MelloUI.FontStyleSettings(key)
			for k in pairs(type(set) == "table" and set or EMPTY) do
				d["Fonts." .. k] = nil
			end
			d[FONT_STYLE] = key
		end
		Put(FONTS_ON, true)
	end

	-- A card's samples in its faces: a face the client loads for the first
	-- time here (a new player's Fonts are off: none of them read yet) may
	-- take a while, so the faces come within the page's budget of rows, a
	-- card at a time, each card's samples shown once they have theirs
	local function CardFaces(card)
		local spec, game = card.faces, GameFaces()
		SampleFont(card.title, spec.title, TITLE_BASE * spec.titleScale, game.title)
		SampleFont(card.text, spec.text, TEXT_BASE * spec.textScale, game.text)
		card.title:Show()
		card.text:Show()
	end

	local function BuildFonts(page)
		Wizard()
		local flow = {}
		page.flow, page.rows, page.fonts = flow, {}, {}
		Part(flow, Lead(page, TEXT.fontsLead), PAD, nil, 10)
		local specs = FontCards()
		local grid = Grid(page, #specs, 2, FONT_H, CARD_GAP_Y)
		for i, spec in ipairs(specs) do
			local card = W.Card(grid, { width = CARD_W, height = FONT_H, title = TEXT.fontTitleSample, text = TEXT.fontTextSample,
				tag = spec.tag, key = spec.key, onClick = FontPick }, win.shell)
			card:SetPoint("TOPLEFT", grid, "TOPLEFT", ((i - 1) % 2) * (CARD_W + CARD_GAP_X), -floor((i - 1) / 2) * (FONT_H + CARD_GAP_Y))
			card.faces = spec
			card.title:Hide()
			card.text:Hide()
			LaterWork(page, CardFaces, card)
			Tip(card, spec.tag, spec.tip)
			page.fonts[i] = card
		end
		Part(flow, grid, 0, grid.melloH, 0, true)
		return 1
	end

	local function RefreshFonts(page)
		local choice = FontChoice(Wizard())
		for _, card in ipairs(page.fonts) do
			local on = card.key == choice
			if card:IsSelected() ~= on then
				card:SetSelected(on)
			end
		end
		MakeRows(page, FIRST_ROWS)
		return Flow(page)
	end

	STEPS.fonts.build, STEPS.fonts.refresh = BuildFonts, RefreshFonts

	--------------------------------------------------------------------------------
	-- Features: "All features" on top, then each feature's own switch in the
	-- two columns of I.FEATURE_GROUPS. Every one starts off (Fresh start's
	-- promise); one switched on comes with Mello's settings for it (the
	-- engine's Target). The All switch sets every row; it is on only while
	-- every row is.
	--------------------------------------------------------------------------------

	local FEATURE_GAP = 10
	local FEATURE_W = floor((PAGE_W - FEATURE_GAP) / 2)

	local function AllGet()
		local d, keys = Wizard(), FeatureKeys()
		for i = 1, #keys do
			if d[keys[i]] ~= true then
				return false
			end
		end
		return #keys > 0
	end

	local function AllSet(on)
		local d, keys = Wizard(), FeatureKeys()
		for i = 1, #keys do
			d[keys[i]] = on and true or false
		end
		DraftChanged()
	end

	local function AllRow(page)
		return (W.ToggleRow(page, 0, TEXT.allFeatures, nil, TEXT.allFeaturesDesc, AllGet, AllSet, RowOpts(true)))
	end

	-- the name a feature goes by: its switch's label, else its title
	local function FeatureLabel(m)
		return type(m.tweak) == "table" and m.tweak.label or m.title or m.name
	end
	IW.FeatureLabel = FeatureLabel   -- (the Review line; the tests)

	-- a feature's row in its column, in its place (made within the page's
	-- budget of rows, as every other row)
	local function FeatureRow(spec)
		local m = MelloUI:GetModule(spec.name)
		local row = KeyRow(spec.col, FeatureLabel(m), nil, TweakDesc(spec.name) or m.desc, I.SwitchKey(m), false,
			RowOpts(spec.i % 2 == 1))
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", spec.col, "TOPLEFT", 0, -(HEADING_H + 4 + (spec.i - 1) * W.ROW_HEIGHT))
		row:SetPoint("RIGHT", spec.col, "RIGHT", 0, 0)
		row.melloFeature = spec.name
		local page = spec.page
		page.rows[#page.rows + 1] = row
		row:Refresh()
	end

	local function BuildFeatures(page)
		Wizard()
		local flow = {}
		page.flow, page.rows, page.columns = flow, {}, {}
		Part(flow, Lead(page, TEXT.featuresLead), PAD, nil, 10)
		LaterRow(page, AllRow, W.ROW_HEIGHT, 10)
		local most = 0
		for _, group in ipairs(I.FEATURE_GROUPS) do
			most = math.max(most, #group.members)
		end
		local h = HEADING_H + 4 + most * W.ROW_HEIGHT
		local holder = CreateFrame("Frame", nil, page)
		holder:SetHeight(h)
		for c, group in ipairs(I.FEATURE_GROUPS) do
			local col = CreateFrame("Frame", nil, holder)
			col:SetSize(FEATURE_W, h)
			col:SetPoint("TOPLEFT", holder, "TOPLEFT", (c - 1) * (FEATURE_W + FEATURE_GAP), 0)
			local heading = Heading(col, group.label)
			heading:ClearAllPoints()
			heading:SetPoint("TOPLEFT", col, "TOPLEFT", 0, 0)
			heading:SetPoint("RIGHT", col, "RIGHT", 0, 0)
			col.heading = heading
			page.columns[c] = col
			local i = 0
			for _, name in ipairs(group.members) do
				if I.SwitchKey(MelloUI:GetModule(name)) then
					i = i + 1
					LaterWork(page, FeatureRow, { page = page, col = col, i = i, name = name })
				end
			end
		end
		Part(flow, holder, 0, h, 0, true)
		return 1
	end

	STEPS.features.build, STEPS.features.refresh = BuildFeatures, RefreshWizard

	--------------------------------------------------------------------------------
	-- Chat: Chat tweaks, the name forms (Chat's own list, one chosen) and the
	-- shade behind names, both asleep with Chat tweaks off
	--------------------------------------------------------------------------------

	-- a name form's row (one of them chosen: a click on the chosen one keeps it)
	local function NameRow(value, example, kind, zebra)
		local function Get()
			local v = Wizard()[NAME_STYLE]
			if v == nil then
				local chat = MelloUI:GetModule("Chat")
				v = chat and type(chat.defaults) == "table" and chat.defaults.nameStyle or nil
			end
			return v == value
		end
		local function Set(on)
			if on then
				Put(NAME_STYLE, value)
			else
				IW:Refresh()
			end
		end
		return function(page)
			return (W.ToggleRow(page, 0, example, kind, nil, Get, Set, RowOpts(zebra, ChatGate, GATE_INDENT)))
		end
	end

	local function ChatRow(page)
		return KeyRow(page, TEXT.chatTweaks, nil, TweakDesc("Chat"), CHAT_ON, true, RowOpts(true))
	end

	local function NameShadeRow(page)
		local shade = OptionOf("Chat", "nameShade")
		return KeyRow(page, TEXT.nameShade, nil, shade and shade.desc, NAME_SHADE, true, RowOpts(true, ChatGate, GATE_INDENT))
	end

	local function BuildChat(page)
		Wizard()
		local flow = {}
		page.flow, page.rows = flow, {}
		Part(flow, Lead(page, TEXT.chatLead), PAD, nil, 10)
		LaterRow(page, ChatRow, W.ROW_HEIGHT, 10)
		Part(flow, Heading(page, TEXT.names), 0, HEADING_H, 4, true)
		-- the name forms, each shown by its example ("Full name (Professor
		-- Skillybones)": the name on the row, the form beside it)
		local opt = OptionOf("Chat", "nameStyle")
		for i, entry in ipairs(opt and type(opt.values) == "table" and opt.values or EMPTY) do
			local label = tostring(entry.label or entry.value)
			local kind, example = label:match("^(.-) %((.+)%)$")
			LaterRow(page, NameRow(entry.value, example or label, example and kind or nil, i % 2 == 1), W.ROW_HEIGHT, 0)
		end
		flow[#flow].gap = 8
		LaterRow(page, NameShadeRow, W.ROW_HEIGHT, 0)
		return 1
	end

	STEPS.chat.build, STEPS.chat.refresh = BuildChat, RefreshWizard

	--------------------------------------------------------------------------------
	-- Windows: which windows wear the kit, a switch per group of
	-- I.WINDOW_GROUPS (on while every member is), asleep with the reskin off
	--------------------------------------------------------------------------------

	-- a group's row (nil: none of its windows is here)
	local function GroupRow(group, zebra)
		local keys, labels = {}, {}
		for _, name in ipairs(type(group.members) == "table" and group.members or EMPTY) do
			local m = MelloUI:GetModule(name)
			if m then
				keys[#keys + 1] = "UIModifications." .. name
				labels[#labels + 1] = type(m.window) == "table" and m.window.label or name
			end
		end
		if #keys == 0 then
			return nil
		end
		local function Get()
			local d = Wizard()
			for i = 1, #keys do
				if d[keys[i]] == false then
					return false
				end
			end
			return true
		end
		local function Set(on)
			local d = Wizard()
			for i = 1, #keys do
				d[keys[i]] = on and true or false
			end
			DraftChanged()
		end
		local hint = (group.key == "hud" and TEXT.hudCount or TEXT.windowsCount):format(#keys)
		local desc = concat(labels, ", ") .. "."
		return function(page)
			return (W.ToggleRow(page, 0, group.label, hint, desc, Get, Set, RowOpts(zebra, ReskinGate)))
		end
	end

	local function BuildWindows(page)
		Wizard()
		page.flow, page.rows = {}, {}
		Part(page.flow, Lead(page, TEXT.windowsLead), PAD, nil, 10)
		for i, group in ipairs(type(I.WINDOW_GROUPS) == "table" and I.WINDOW_GROUPS or EMPTY) do
			local make = GroupRow(group, i % 2 == 1)
			if make then
				LaterRow(page, make, W.ROW_HEIGHT, 0)
			end
		end
		return 1
	end

	STEPS.windows.build, STEPS.windows.refresh = BuildWindows, RefreshWizard

	--------------------------------------------------------------------------------
	-- Review: the Minimap's line and the Features' line (a short one: at most
	-- three names and how many more; a row is one line)
	--------------------------------------------------------------------------------

	local NAMES_SHOWN, NAMES_ROOM = 3, 46   -- the names listed, and the room for them (characters)

	-- (read once: the Services bar's switch key; false: none)
	local servicesKey = nil
	local function MapLine(_, d)
		if d[RESKIN] == false or d[MAP_HUD] == false or not MelloUI:GetModule("MinimapPanel") then
			return TEXT.mapGame
		end
		local shape = d[MAP_SHAPE]
		if shape == nil then
			shape = MapShape()
		end
		if shape ~= "square" then
			return TEXT.mapRoundRow
		end
		if servicesKey == nil then
			servicesKey = I.SwitchKey(MelloUI:GetModule("Services")) or false
		end
		if d[MAP_MERGE] ~= false and servicesKey and d[servicesKey] == true then
			return TEXT.mapMergedRow
		end
		return TEXT.mapSquareRow
	end

	-- the Features line, made again only when the switches on change (the
	-- Review page refreshes on a show, a fit, a scale change): which are on,
	-- as the bits of one number in the step's order
	local featuresMemo = { mask = nil, text = nil }
	local function FeaturesLine(_, d)
		local keys = FeatureKeys()
		local mask = 0
		for i = 1, #keys do
			mask = mask * 2 + (d[keys[i]] == true and 1 or 0)
		end
		if featuresMemo.mask == mask then
			return featuresMemo.text
		end
		local on = I:FeaturesOn(d)
		local text, shown = "", 0
		for i = 1, #on do
			local m = MelloUI:GetModule(on[i])
			local name = m and FeatureLabel(m) or on[i]
			if shown >= NAMES_SHOWN or (shown > 0 and #text + 2 + #name > NAMES_ROOM) then
				break
			end
			text = shown == 0 and name or (text .. ", " .. name)
			shown = shown + 1
		end
		if #on == 0 then
			text = TEXT.featuresNone
		else
			if shown < #on then
				text = TEXT.featuresMore:format(text, #on - shown)
			end
			text = TEXT.featuresRow:format(text)
		end
		featuresMemo.mask, featuresMemo.text = mask, text
		return text
	end

	REVIEW.fresh = { TEXT.reviewChoices, MapLine, FeaturesLine, true, TEXT.scaleRow }
end
WizardSteps()

--------------------------------------------------------------------------------
-- The engine's news (the bus's 'installer'), a screen change ('scale'), and
-- the fight and Edit Mode while the window shows
--------------------------------------------------------------------------------

-- (built but hidden -- a Revert from the configurator's Home, say -- the
-- state only: no page made, no fade run for a window nobody sees; the next
-- open shows what is owed, or starts over on the first step)
local function OnInstaller(what, a, b)
	if not win then
		return
	end
	local shown = win.frame:IsShown()
	if what == "countdown" then
		if shown then
			RefreshKeep()
		end
	elseif what == "installed" then
		state.installed, state.keepLine = true, nil
		if shown then
			ShowKeep(1)
		end
	elseif what == "kept" or what == "reverted" then
		DropFits(true)
		if not shown then
			state.phase, state.step, state.doneMode, state.keepLine, state.footLine = "choose", "choose", nil, nil, nil
			state.installed = false
		elseif what == "kept" then
			state.doneMode, state.needsReload, state.keepLine = "kept", a and true or false, nil
			ShowDone()
		else
			state.doneMode, state.reason, state.reloadOwed, state.keepLine = "reverted", a, b and true or false, nil
			ShowDone()
		end
	elseif what == "revertFailed" then
		state.keepLine = b
		if not shown then
			return
		elseif state.phase ~= "keep" then
			ShowKeep(0)
		else
			RefreshKeep()
		end
	end
end

-- a new UI scale: the fits made for the old size go (the picture and the
-- footer name the new one; the Screen and Review steps start a new fit)
local function OnScale(reason)
	if reason ~= "uiscale" or not win then
		return
	end
	DropFits(true)
	if win.frame:IsShown() then
		RefreshPage()
		RefreshFooter()
	end
end

-- (the fight and Edit Mode, while it shows: Install's footer, Revert)
local function Changed()
	if state.phase == "keep" then
		RefreshKeep()
	else
		RefreshFooter()
	end
end

local Window_OnEvent = Shared("OnEvent on the installer window (combat)", function()
	Changed()
end, "script")

-- the room in Edit Mode's list the fits keep (I:LayoutRoom) forgotten: a
-- layout may have been deleted or added meanwhile
local function ForgetRoom()
	for _, fit in pairs(state.fits) do
		fit.room, fit.most = nil, nil
	end
end

local function EditModeChanged()
	ForgetRoom()
	if state.phase == "keep" then
		RefreshKeep()
	else
		IW:Refresh()   -- (the Screen step's room line too)
	end
end

local Window_OnShow = Shared("OnShow on the installer window", function(frame)
	ForgetRoom()
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	MelloUI:On("editmode", EditModeChanged, OWNER_SHOWN)
end, "script")

-- (a real close only: OnHide also comes when just the parent hides -- the
-- UI hidden, Alt+Z -- with the window still shown; it is all there again
-- when the UI comes back, the fit still running, no line printed. In an
-- OnHide the window is never visible, so this is IsShown: true only when
-- the parent hid)
local Window_OnHide = Shared("OnHide on the installer window", function(frame)
	if frame:IsShown() and not frame:IsVisible() then
		return
	end
	frame:UnregisterAllEvents()
	MelloUI:Off(OWNER_SHOWN)
	-- the banner released (about 2 MB); loaded again on the Setup page's
	-- next show
	local choose = win.pages.choose
	if choose and win.bannerLoaded then
		choose.banner:SetTexture(nil)
	end
	win.bannerLoaded = false
	DropFits(false)
	-- (the refit closed early: nothing to set up, no line)
	if state.phase == "choose" and not state.installed and not Option().hidden then
		MelloUI:Print(TEXT.closedEarly)
	end
end, "script")

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local function Build()
	local Kit = MelloUI.Kit
	local frame = CreateFrame("Frame", NAME, UIParent)
	frame:SetSize(WIN_W, WIN_H)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:EnableMouse(true)
	frame:Hide()
	-- (its own scripts before the shell's hooks: SetScript drops hooks)
	Perf.SetScript(frame, "OnShow", Window_OnShow)
	Perf.SetScript(frame, "OnHide", Window_OnHide)
	Perf.SetScript(frame, "OnEvent", Window_OnEvent)
	win = { frame = frame, pages = {}, foot = {}, bannerLoaded = false }
	IW.win = win
	-- the shell: the corner ring with the emblem, the plate on the rail,
	-- close, Escape, the fit, the sounds; its one mover keeps no place
	win.shell = Kit:OwnWindow(frame, { area = "installer", ring = { at = "tl", texture = LOGO }, plate = "rail",
		title = STEPS.choose.title, close = true, escape = true, fit = true, sounds = true, mover = MOVER })
	state.escape = true
	-- the steps rail
	win.rail = W.NavRail(frame, { width = RAIL_W, rowHeight = 32, iconSize = 0, numbered = true, scroll = false,
		onSelect = StepClick, clickable = StepClickable, doneGlyph = "common-icon-checkmark", skin = win.shell })
	win.rail.box:SetPoint("TOPLEFT", frame, "TOPLEFT", EDGE, TOP)
	-- (the longest path's rows made now, so switching setups later takes
	-- every row from the rail's pool)
	local longest = Option()
	for _, option in ipairs(I.OPTIONS) do
		if #option.steps > #longest.steps then
			longest = option
		end
	end
	win.rail:SetGroups(IW.GroupsFor(longest))
	win.rail:SetGroups(IW.GroupsFor(Option()))
	-- the body: the pages on the dark inner panel over the window's stone
	win.pager = W.Pager(frame, { step = 80 })
	local scroll = win.pager.scroll
	scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", BODY_X, TOP)
	scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -EDGE, BODY_BOTTOM)
	Kit:StoneDim(frame, { rect = scroll, alpha = 0.8 })
	-- the footer: the screen line (or why Install waits), Back, Continue or
	-- Install
	local f = win.foot
	f.next = Button(frame, TEXT.continue, BUTTON_W, "next")
	f.next:SetPoint("RIGHT", frame, "BOTTOMRIGHT", -EDGE, FOOT_MID)
	f.install = Button(frame, TEXT.install, BUTTON_W, "install", true)
	f.install:SetPoint("RIGHT", frame, "BOTTOMRIGHT", -EDGE, FOOT_MID)
	f.back = Button(frame, TEXT.back, BUTTON_W, "back")
	f.back:SetPoint("RIGHT", frame, "BOTTOMRIGHT", -EDGE - BUTTON_W - 8, FOOT_MID)
	f.line = W.Text(frame, "GameFontHighlight", nil, "text")
	f.line:SetJustifyV("MIDDLE")
	f.line:SetPoint("LEFT", frame, "BOTTOMLEFT", EDGE + 4, FOOT_MID)
	f.line:SetPoint("RIGHT", f.back, "LEFT", -12, 0)
	-- the engine's news and the screen's size, for as long as it exists
	MelloUI:On("installer", OnInstaller, OWNER)
	MelloUI:On("scale", OnScale, OWNER)
end

function IW:Open(page)
	if not win then
		Build()
	end
	-- the configurator steps aside, as it does for Dynamic UI Modification
	local config = _G.MelloUIConfigFrame
	if config and config ~= win.frame and config:IsShown() then
		config:Hide()
	end
	local frame = win.frame
	local shown = frame:IsShown()
	local pending = Pending()
	if pending then
		-- an answer owed: from before this session (a /reload or a restart),
		-- the countdown again with its 15 s; one made in this session is as
		-- it stands (its countdown running, or Revert only for an install
		-- that could not be put back or a revert that only partly worked)
		if not state.installed then
			I:ResumePending()
		end
		if state.phase ~= "keep" then
			state.phase, state.step, state.doneMode = "keep", "keep", nil
			state.keepLine = pending.failed and (pending.revertFailed and I.TEXT.keepHalf or I.TEXT.keepFailed) or nil
			-- (the rail shows the path of the setup that went in)
			if I:Option(pending.option) and pending.option ~= state.option then
				state.option = pending.option
				win.rail:SetGroups(IW.GroupsFor(Option()))
			end
		end
	elseif not shown or page == "choose" or page == "fit" then
		-- every open starts on its setup's first step: the setup chosen is
		-- kept, the refit (Fit to this screen) is chosen by its own entry
		-- only and starts on the Screen step
		if page == "fit" and I:Option("fit") then
			state.option = "fit"
		elseif Option().hidden then
			state.option = "full"
		end
		state.phase, state.step, state.doneMode, state.keepLine, state.footLine = "choose", Option().steps[1], nil, nil, nil
		state.installed = false
		win.rail:SetGroups(IW.GroupsFor(Option()))
		SetClosable(true)
	end
	if not shown then
		Centre(frame)
		frame:Show()
	end
	Present(state.step, 0, true)
	return true
end

function IW:Close()
	if win and win.frame:IsShown() then
		win.frame:Hide()
	end
end

function IW:IsShown()
	return (win and win.frame:IsShown()) and true or false
end

function IW:Busy()
	return self:IsShown() or (I:Countdown() and true or false)
end

-- The entry every caller shares (the configurator's Install..., Install
-- again, Fit to this screen and Revert with an answer owed; /mello install):
-- the installer's own Open when the login stage has given it one (its
-- refusals: the settings still loading, combat, Edit Mode), else the window
-- at once. from "fit": the refit on its Screen step; an answer owed opens
-- the Keep page whoever asks.
function MelloUI:OpenInstaller(from)
	local page = from == "fit" and "fit" or nil
	local installer = self.Installer
	if type(installer) == "table" and type(installer.Open) == "function" then
		return installer:Open(page)
	end
	return IW:Open(page)
end
