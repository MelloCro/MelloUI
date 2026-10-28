--------------------------------------------------------------------------------
-- MelloUI - Installer: the window
--
-- The installer's window over the engine (Core/Installer.lua): a kit window
-- (Kit:OwnWindow, area "installer": always in the kit, user 2026-09-25) with
-- the steps rail on the left, the step pages on the right and the footer's
-- Back / Continue / Install. The paths:
--   the setup (1.2.4)              skin, layout, party, quests, combat, chat,
--                                  minimap, bags, sound, review, keep
--   Fit to this screen (refit)     fit, review, keep (its own entry only)
-- (the user, 2026-10-26: "the installer should also have the user go trough
-- every step and picking and choosing the look, i would start with the
-- look"; "everybody always goes trough the picking process, no more 1 button
-- full settings"; the sketch MelloUI-BuildData/output/installer_steps_sketch,
-- its steps kept with the user's three additions of 2026-10-27.)
--
-- Built from the shared parts, one system per job: the shell (the corner
-- ring with the emblem, the plate on the rail with the step's title, close,
-- Escape, the fit to the screen, the open and close sounds; ONE mover,
-- Core's, with no saved place: a drag moves it for the session and every
-- open puts it back in the centre), W.NavRail (the numbered steps), W.Pager
-- (a page per step, made on its first show, cross-faded 0.10 s out / 0.15 s
-- in with a 12 px slide; at once under Reduce Motion), W.Card (a step's
-- choices), W.ToggleRow (the switches), W.Button (flat plates; Install the
-- main action, its edge and label in gold), the shell's calm ground (0.15.0,
-- the cleaner look: one flat ground, the stone only as a band inside the
-- rail) with ONE W.Panel on it for the body (the dark inner panel: every
-- line of text on it, none small on the stone, WINDOW-RULES 2e; one
-- surface, one panel), Kit:RingDisc (the Keep page's ring),
-- MelloUI:StyleFont (the countdown's numeral in the title face),
-- MelloUI:ScreenText (the screen line), MelloUI:PlayUISound. Colours by
-- palette key only (W.Paint), so a new palette paints the window again.
--
-- Nothing of it exists at login: this file defines functions and data. The
-- window is built the first time it opens (WINDOW-RULES 2f), each page on
-- its first show; revisiting a page makes no frame. Its bus listeners are
-- taken when it is built, its combat events and the 'editmode' listener only
-- while it shows; nothing polls. It writes nothing but the setup's picks
-- until Install; the engine applies, counts down and reverts, and tells the
-- window on the bus ('installer'). The fit runs from the Layout step's first
-- show (a frame's share at a time, I:StartFit), again after a pick changes
-- what it reads, and Install waits for it. The UI scale is only shown, never
-- changed.
-- (1.2.4) Keep reloads the UI: the game's own /reload, run by the player's
-- click on a secure button laid over Keep (MelloUIInstallerReload, made at
-- Keep's first hover; never in a fight). Revert reloads nothing.
--
-- The setup's pages (SetupSteps, below) are all the same: a lead, one big
-- picture -- the choice's, in the skin picked (the Layout step's: the fit's
-- own drawing of this screen) -- and the choices under it, cards for one of
-- several and switches for several, each writing the picks (the engine's
-- I.SETUP says what each one sets; I:SetupDraft makes the draft). Pictures,
-- never a live preview: shipped in Media\Installer, loaded when their page
-- shows, let go when the window closes.
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
--   IW:Draft([optionKey]) -> draft the setup's draft (made from its picks,
--                                  I:SetupDraft), the refit's (the Screen
--                                  step's layout switch)
--   IW:Picks() -> picks            the setup's answers (I:DefaultPicks to
--                                  begin with: the recommended ones)
--   IW:Step(key, def)              a step's page put in or replaced (every
--                                  step has its own in this file): def = { build =
--                                  fn(page, IW) -> height, refresh =
--                                  fn(page, IW) -> height or nil, title,
--                                  label }; a step with no page shows a
--                                  line saying Continue keeps Mello's choice
--   IW:Refresh()                   the page on show and the footer again
--   IW.win                         the built window: frame, shell, rail,
--                                  pager, pages[step], foot
--   IW.state                       (read only) option, step, phase, picks,
--                                  drafts, fits; IW.PAGE_W: a page's width
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

local TEXTURE_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Textures\\"   -- look-ok: MelloUI's logo
local LOGO = TEXTURE_PATH .. "LogoIcon.tga"
-- (1.2.4) the steps' pictures (Media\Installer, Tools/make_installer_pictures.py, shipped by Tools/texture_pack.py),
-- each at the top left of a 1024 x 512 file: the Skin step's the whole screen, 910 x 512 (16:9); every other step's a
-- 2.5:1 band, 1024 x 410; drawn the text's width
local PICTURES = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Installer\\"   -- (the steps' pictures)
local SCREEN_UV, BAND_UV = { 910 / 1024, 1 }, { 1, 410 / 512 }
local TICK = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Icons\\ql_completed"   -- (0.25.0: the icon set's gold tick; the game's 1x ready check until then)
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local NAME = "MelloUIInstallerFrame"   -- (named: the shell's Escape)
local OWNER = "Installer window"            -- the bus owner while it exists
local OWNER_SHOWN = "Installer window shown"   -- ... and while it shows

-- geometry (UI units; 1.2.4: wider and taller for the steps' pictures)
local WIN_W, WIN_H = 860, 640
local EDGE = 16                 -- the window's margin
local TOP = -64                 -- the rail's and the body's top, under the corner ring
local RAIL_W = 160
local BODY_X = 190
local BODY_BOTTOM = 60          -- over the footer band (16 .. 48)
local FOOT_MID = 32
local PAGE_W = WIN_W - BODY_X - EDGE   -- 574
local PAD = 14                  -- a page's text margin
local TEXT_W = PAGE_W - 2 * PAD
local CARD_H, CARD_GAP_X = 78, 12
-- the pages' clip reaches this far past their left and right edges: a chosen
-- card wears the active look (Kit:SetActive), whose halo reaches 8 x 0.7
-- units past the card, and the cards lie flush with the page's edges (the
-- halo was cut off on their outer side; review, 2026-09-28)
local LOOK_BLEED = 6
-- a step's picture (the Layout and Screen steps' drawing of the fit too): the text's width, the pictures' shape
local PIC_W, PIC_M = TEXT_W, 8
local PIC_H = floor(PIC_W * 410 / 1024)
local SCREEN_H = floor(PIC_W * 9 / 16)   -- (the Skin step's picture: the whole screen)
local RING = 110
local BUTTON_W, BUTTON_H = 120, 24
local DONE_BUTTON_W = 124
local EYE_SHOWN = 3             -- the eye items listed under the picture (the rest counted)
IW.PAGE_W = PAGE_W   -- (a step's page; the tests lay a page's columns against it)

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
	suggest = "Your own Edit Mode layout suits this screen better.",
	-- (0.22.0) the way on when Edit Mode has no room for one more layout
	installWithout = "Install Without The Layout",
	deleteOld = "Delete '%s'",
	deleteAsk = "Delete the Edit Mode layout '%s'?\n\nIt is an older MelloUI layout, made for another screen. Your own layouts stay, and Edit Mode then has room for this screen's.",
	deleteYes = "Delete it",
	deleteNo = "Cancel",
	deleteFailed = "The Edit Mode layout '%s' was not deleted: %s.",
	reviewLead = "%s: this is what changes.",
	layoutRow = "Edit Mode layout '%s', fitted to %s",
	layoutWaits = "The Edit Mode layout, once your screen is fitted",
	noLayout = "No Edit Mode change: your own layout stays",
	scaleRow = "Your UI scale stays as it is",
	restore = "Your current setup is saved as the profile 'Before install' first, so you can go back to it later from the Profiles page. After Install you have 15 seconds to keep the new setup; Keep then reloads the UI.",
	keepQuestion = "Keep this setup?",
	keepLine = "If you don't answer, MelloUI goes back to 'Before install' when the timer runs out.",
	keepReload = "Keep reloads the UI, so everything takes the new setup.",
	keptReload = "Type /reload so everything takes the new setup.",   -- (a Keep with no reload: its secure button not laid)
	revertedTitle = "Back to 'Before install'.",
	revertedReload = "Type /reload to finish: the names above characters still use the installed font.",
	plateReverted = "Back as before",
	closedEarly = "Install... in /mello (or /mello install) sets MelloUI up any time.",
	placeholder = "Continue keeps Mello's own choice for this step.",
	continue = "Continue", back = "Back", install = "Install", keep = "Keep", revert = "Revert",
	again = "Choose again", close = "Close",
	paletteRow = "Palette: %s",
	-- the setup's steps (1.2.4)
	skinLead = "How everything looks: the game's frames and MelloUI's own windows and features alike. Every step after this one shows its pictures in this skin.",
	recommended = "Recommended",
	notInstalled = "Not installed",
	switchedOff = "Switched off",
	getOldschool = "MelloUI Oldschool is an addon of its own. Get it from CurseForge, then restart the game: this card turns on.",
	enableOldschool = "MelloUI Oldschool is installed but switched off: switch it on in the game's AddOn list, then type /reload.",
	copyHint = "The game can't open web pages: the link is selected in the box, Ctrl+C copies it.",
	layoutLead = "Where everything stands on your %s screen.",
	ownLayoutPicture = "Your own Edit Mode layout stays as it is.",
	useOwnLayout = "Keep My Layout",
	manyLead = "Pick what you want. Each one comes with Mello's settings for it; change them any time in /mello.",
	reviewSkin = "Skin: %s",
	reviewNone = "none",
	gamePalette = "Colours: the game's own",
	-- the names and lines of the skins, the layouts and each step's choices (I.SKINS, I.SETUP)
	choices = {
		default = { "Default", "The game's own look for everything, MelloUI's windows and features too." },
		modern = { "Modern", "MelloUI's own look for everything: slate panels, gold trim, one clean font." },
		oldschool = { "Oldschool", "The painted RPG look for everything: parchment, iron and stone." },
		mello = { "Mello's Layout", "Bars, frames, chat and the map column fitted to your screen; your own layouts stay in Edit Mode's list." },
		own = { "Keep My Layout", "Your Edit Mode layout stays exactly as it is; MelloUI only dresses it." },
		group = { "Group Frames", "MelloUI's own party and raid frames, the heal and cooldown effects across them." },
		portraits = { "Portraits", "The game's party frames with their portraits, in your skin." },
		yourself = { "Show Yourself In Your Party", "Your own frame on top of the group." },
		flip = { "Flip Horizontally", "Portraits on the right: for a party on the right side of the screen." },
		markers = { "Party Markers", "Your friends' class medallions over their heads, to find them in a crowd." },
		tracker = { "Quest Tracker", "Your quests by zone, in your skin." },
		questlist = { "Quest List", "Every quest near you, on the map and in a list." },
		route = { "Route", "The way to your next quest, over the real ground." },
		map = { "Map", "One seamless world map with your quests." },
		voice = { "Voice Over", "Quest givers speak their text." },
		services = { "Services", "Repair, innkeeper, flight master: one click routes there." },
		dungeon = { "Dungeon Info", "Every dungeon and raid on the map: its bosses, their loot, your wish list." },
		nameplates = { "Nameplates", "Enemy plates: names, debuffs, crowd control, threat." },
		combattext = { "Combat Text", "Your hits and heals, easy to read." },
		meter = { "Damage Meter", "Damage and healing, for you and your group." },
		effects = { "Heal And Cooldown Effects", "Heals fly to the frame and land on it; cooldowns show on it." },
		prd = { "Personal Display", "Your health, power and cooldowns under your character." },
		view = { "Chat View", "Channel tabs, readable lines, a whisper window." },
		plainchat = { "The Plain Chat", "The chat windows as the game has them." },
		column = { "Map Column", "The minimap as wide as the tracker, its buttons in groups." },
		reminders = { "Reminders", "A buff or food running out: a quiet card." },
		widgets = { "Widgets", "Small cards: your quest's step, a timer, a count." },
		kinds = { "Bags By Kind", "One window, sorted by kind, with search." },
		separate = { "Separate Bags", "One window a bag, as the game has them." },
		gains = { "Gains", "Short lines beside you: what you loot, receive and buy." },
		restock = { "Restock", "Drink, food, ammunition and reagents: a list to buy at the shop, bought on a click." },
		discard = { "Discard", "A button that sells or throws away your cheapest junk to free a slot." },
		melloSound = { "MelloUI Sounds", "The sounds of your skin: soft clicks, a chime for a waypoint, a quest done." },
		gameSound = { "The Game's Sounds", "The game's own interface sounds. The Default skin always uses them." },
	},
	leads = {
		party = "Which frames show your group, in your skin. Both can be clicked to heal.",
		chat = "Your chat window, in your skin.",
		bags = "Your bags, in your skin.",
		sound = "The interface's sounds.",
	},
}
IW.TEXT = TEXT

-- the Review step's palette line: the palette the setup puts in (the
-- engine's I:PaletteOf), its line made once per palette
local PaletteLine
do
	local lines = {}
	PaletteLine = function(option, draft)
		local id = I:PaletteOf(option, draft)
		local line = lines[id]
		if not line then
			line = MelloUI.Lang.F(TEXT.paletteRow, W.PaletteName(id))
			lines[id] = line
		end
		return line
	end
end

-- What the Review step lists per setup; true: the Edit Mode layout's line,
-- as the fit and the Screen step's switch make it; a function: fn(option,
-- draft) -> the line. The setup's rows are its steps' picks (SetupSteps sets
-- them); the refit keeps the player's palette: no line.
local REVIEW = {
	fit = { true, "Window places fitted to this screen", "Your other settings stay as they are", TEXT.scaleRow },
}
local REVIEW_ROWS = 12

-- The steps: each one's plate title and rail label, and its page's builder
-- and refresh (the setup's pages are set by SetupSteps, below)
local STEPS = {
	skin = { title = "Welcome to MelloUI", label = "Skin" },
	layout = { title = "Layout", label = "Layout" },
	party = { title = "Party and raid", label = "Party and raid" },
	quests = { title = "Quests and travel", label = "Quests" },
	combat = { title = "Combat", label = "Combat" },
	chat = { title = "Chat", label = "Chat" },
	minimap = { title = "Minimap and widgets", label = "Minimap" },
	bags = { title = "Bags", label = "Bags" },
	sound = { title = "Sound", label = "Sound" },
	fit = { title = "Fit to your screen", label = "Your screen" },
	review = { title = "Review and install", label = "Review" },
	keep = { title = "Keep this setup?", label = "Keep" },
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local win   -- the window, once built (IW.win)
local state = {
	option = "setup",    -- the setup's key (the refit's, "fit", from its own entry)
	step = "skin",       -- the step on show
	picks = nil,         -- the setup's answers (I:DefaultPicks, made at the first ask)
	phase = "choose",    -- "choose" (before Install) | "keep" (the answer owed) | "done" (reverted)
	doneMode = nil,      -- "reverted" (1.2.4: a kept setup reloads the UI, no Done page)
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

-- the setup's answers: the recommended ones to begin with
local function Picks()
	if not state.picks then
		state.picks = I:DefaultPicks()
	end
	return state.picks
end

-- a setup's draft: nothing but its own choices until Install. The setup's
-- is made from its picks (again after a pick: SetupSteps drops it), the
-- refit's holds the Screen step's layout switch
local function DraftFor(key)
	key = key or state.option
	local d = state.drafts[key]
	if not d then
		local option = Option(key)
		if option and option.base == "setup" then
			local ok, draft = pcall(I.SetupDraft, I, Picks())
			d = (ok and type(draft) == "table") and draft or {}
		else
			d = {}
		end
		state.drafts[key] = d
	end
	return d
end

-- whether the setup fits the screen (its window places or its layout: the
-- engine's own rule, NeedsFit)
local function HasFit(option)
	return option and (option.places or option.layout) and true or false
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
		footMemo.screen, footMemo.text = screen, MelloUI.Lang.F(TEXT.screen, screen)
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
		return MelloUI.Lang.F(TEXT.layoutRow, LayoutNameOf(fit), (ScreenText()))
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
-- default: the centre. A "tool" of Edit Layout's (0.15.0): never a plate
-- there, never in its Reset all; dragged by its strip at any time
local function NoPlace()
end

local function Centre(frame)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

local MOVER = { save = NoPlace, default = Centre, plainDrag = "always", group = "tool" }

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

-- Keep: the setup kept (the 'kept' Fire closes the window: no Done page, the user, 2026-10-28: "Drop it"). From the
-- secure button over Keep (`reloading`: Reload, below) the game's /reload follows; a plain click on Keep (that button
-- not laid) says to type /reload
function ACTIONS.keep(_, reloading)
	MelloUI:PlayUISound("menu_button")
	local kept, why = I:Keep()
	if why then
		state.keepLine = why
		RefreshKeep()
	elseif kept and not reloading then
		MelloUI:Print(TEXT.keptReload)
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
		title = TEXT.plateReverted   -- (the one Done page: a kept setup reloads the UI)
	else
		local def = STEPS[state.step]
		title = def and def.title or ""
	end
	local fs = win.shell.title
	if fs and fs:GetText() ~= title then
		fs:SetText(MelloUI.Lang.T(title))
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
		f.line:SetText(MelloUI.Lang.T(line))
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
	page.line = W.Text(page, "GameFontHighlight", MelloUI.Lang.T(TEXT.placeholder), "text")
	page.line:SetWidth(TEXT_W)
	page.line:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, -12)
	return 60
end

function IW.RefreshPlaceholder()
	return 60
end

--------------------------------------------------------------------------------
-- The Screen step: the detected screen, the fitted picture, the
-- aspect and the UI scale (read only), the layout switch
--------------------------------------------------------------------------------

-- a box with a label, a value in gold and a line (the aspect, the UI scale)
local function InfoPanel(page, label)
	local box = W.Box(page, "mainWindow", "border", 0.85)
	box:SetSize((PAGE_W - 10) / 2, 70)
	box.label = W.Text(box, "GameFontHighlight", MelloUI.Lang.T(label), "text")
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

-- (0.22.0; a player's report, 2026-10-14: Edit Mode already kept the five account layouts it allows, the switch was
-- on, and the installer could not go on) The way on from the Screen step's line: without the layout (the switch
-- off), or an older MelloUI layout for another screen deleted, asked first in MelloUI's own dialog -- deleted at once,
-- as Edit Mode's own Delete does it (MelloUI:DeleteEditModeLayout), never part of the install or its Revert
function ACTIONS.noLayout()
	if state.phase ~= "choose" then
		return
	end
	MelloUI:PlayUISound("tab")
	LayoutSet(false)
end

local function DeleteOld(name)
	local ok, why = MelloUI:DeleteEditModeLayout(name)
	if not ok then
		MelloUI:Print(TEXT.deleteFailed, name, tostring(why))
	end
	for _, fit in pairs(state.fits) do
		fit.room, fit.most, fit.old = nil, nil, nil
	end
	RefreshPage()
	RefreshFooter()
end

function ACTIONS.deleteOld(button)
	local name = button.melloOld
	if state.phase ~= "choose" or type(name) ~= "string" or type(MelloUI.DeleteEditModeLayout) ~= "function" then
		return
	end
	MelloUI:Confirm({ text = MelloUI.Lang.F(TEXT.deleteAsk, name), accept = TEXT.deleteYes, cancel = TEXT.deleteNo,
		onAccept = function()
			DeleteOld(name)
		end })
end

-- the older MelloUI layouts in Edit Mode's list (kept on the fit as its room is: the list is a whole tree of tables)
local function OldLayouts(fit)
	if fit.old == nil then
		fit.old = type(MelloUI.OldMelloLayouts) == "function" and MelloUI:OldMelloLayouts(LayoutNameOf(fit)) or {}
	end
	return fit.old
end

-- the fit's picture: the screen, and the pieces in palette solids (a pool of
-- textures made on the first draw and reused): the Screen step's, and the
-- setup's Layout step's (1.2.4)
local function FitPicture(page)
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
	pic.msg = W.Text(box, "GameFontHighlight", MelloUI.Lang.T(TEXT.fitting), "text")
	pic.msg:SetJustifyH("CENTER")
	pic.msg:SetPoint("CENTER", box, "CENTER", 0, 0)
	pic.msg:SetWidth(PIC_W - 40)
	page.pic = pic
	return box
end

local function BuildFit(page)
	local shell = win.shell
	page.detected = W.Text(page, "GameFontHighlight", nil, "text")
	page.detected:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, -8)
	FitPicture(page)
	-- under it: the FAIL line or the eye items, and the suggestion
	page.note = W.Text(page, "GameFontHighlight", nil, "text")
	page.note:SetWidth(TEXT_W)
	page.aspect = InfoPanel(page, TEXT.aspect)
	page.scale = InfoPanel(page, TEXT.scale)
	page.scale.line:SetText(MelloUI.Lang.T(TEXT.scaleLine))
	local row = W.ToggleRow(page, 0, MelloUI.Lang.F(TEXT.switch, "MelloUI"), nil, TEXT.switchDesc, LayoutGet, LayoutSet,
		{ skin = shell, look = "palette", zebra = true })
	page.switchRow = row
	page.how = W.Text(page, "GameFontHighlight", MelloUI.Lang.T(TEXT.how), "text")
	page.how:SetWidth(TEXT_W)
	page.room = W.Text(page, "GameFontHighlight", nil, "selectedTrim")
	page.room:SetWidth(TEXT_W)
	-- (0.22.0) the way on from that line
	page.noLayout = Button(page, TEXT.installWithout, 210, "noLayout")
	page.deleteOld = Button(page, "", 230, "deleteOld")
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
		text = MelloUI.Lang.T((type(report.why) == "string" and report.why) or TEXT.notFitted)
		if report.tooSmall then
			text = text .. "\n" .. MelloUI.Lang.T(TEXT.suggest)
		end
	elseif report and type(report.eye) == "table" and #report.eye > 0 then
		local lines = { MelloUI.Lang.T(TEXT.eyeHead) }
		for i = 1, min(#report.eye, EYE_SHOWN) do
			lines[#lines + 1] = "- " .. tostring(report.eye[i])
		end
		if #report.eye > EYE_SHOWN then
			lines[#lines + 1] = MelloUI.Lang.F(TEXT.eyeMore, #report.eye - EYE_SHOWN)
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
	page.detected:SetText(MelloUI.Lang.F(TEXT.detected, screen))
	-- the picture, or the line while the fit runs
	page.pic.msg:SetShown(not done)
	DrawPicture(page, report)
	local y = 30 + PIC_H + 10
	-- the FAIL line or the eye items, and the suggestion
	local note = NoteText(page, report)
	page.note:SetText(MelloUI.Lang.T(note or ""))
	page.note:SetShown(note ~= nil)
	if note then
		Place(page.note, page, PAD, y)
		y = y + (Num(page.note:GetStringHeight()) or 14) + 8
	end
	-- the aspect and the UI scale
	local aspect = page.aspect
	aspect.value:SetText(MelloUI.Lang.T(ratio or "?"))
	local LayoutFit = MelloUI.LayoutFit
	local design = report and LayoutFit and abs((Num(report.W) or 0) - (LayoutFit.DESIGN_W or 0)) < 0.5
		and abs((Num(report.H) or 0) - (LayoutFit.DESIGN_H or 0)) < 0.5
	aspect.line:SetText(MelloUI.Lang.T(not done and TEXT.beingFitted or (report and not report.pass and TEXT.ownStays)
		or (design and TEXT.asMade) or TEXT.fittedTo))
	Place(aspect, page, 0, y)
	page.scale.value:SetText(MelloUI.Lang.T(ScaleText()))
	Place(page.scale, page, (PAGE_W + 10) / 2, y)
	y = y + 70 + 10
	-- the layout switch, named as the fit names this screen's layout
	local row = page.switchRow
	local label = MelloUI.Lang.F(TEXT.switch, LayoutNameOf(done))
	if row.label:GetText() ~= label then
		row.label:SetText(MelloUI.Lang.T(label))
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
			page.room:SetText(MelloUI.Lang.F(I.TEXT.noRoom, most))
		end
	end
	page.room:SetShown(not room)
	page.noLayout:SetShown(not room)
	local old = not room and OldLayouts(done)[1] or nil
	page.deleteOld:SetShown(old ~= nil)
	if not room then
		Place(page.room, page, PAD, y)
		y = y + (Num(page.room:GetStringHeight()) or 28) + 8
		Place(page.noLayout, page, PAD, y)
		if old then
			page.deleteOld.melloOld = old
			page.deleteOld:SetText(MelloUI.Lang.F(TEXT.deleteOld, old))
			Place(page.deleteOld, page, PAD + 210 + 10, y)
		end
		y = y + BUTTON_H + 10
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
		MelloUI.Icons.Set(tick, TICK, 16)   -- (the set's gold tick, its own colours: its copy for its size)
		row.tick = tick
		row.label:SetPoint("RIGHT", tick, "LEFT", -10, 0)
		page.rows[i] = row
	end
	page.restore = W.Text(page, "GameFontHighlight", MelloUI.Lang.T(TEXT.restore), "text")
	page.restore:SetWidth(TEXT_W)
	return 1
end

local leadMemo = {}   -- [setup key] = its lead line
local function RefreshReview(page)
	local option = Option()
	local lead = leadMemo[option.key]
	if not lead then
		lead = MelloUI.Lang.F(TEXT.reviewLead, option.title)
		leadMemo[option.key] = lead
	end
	page.lead:SetText(MelloUI.Lang.T(lead))
	-- (the Screen step's fit: started again here when the screen changed
	-- since, so Install waits for the new one)
	EnsureFit(option.key)
	local y = 10 + (Num(page.lead:GetStringHeight()) or 14) + 10
	local lines = REVIEW[option.key] or REVIEW.setup
	for i, row in ipairs(page.rows) do
		local text = lines[i]
		if text == true then
			text = LayoutLine(option)
		elseif type(text) == "function" then
			text = text(option, DraftFor(option.key))
		end
		row:SetShown(text ~= nil)
		if text then
			row.label:SetText(MelloUI.Lang.T(text))
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
	MelloUI.Kept.pieceOf[emblem] = true
	emblem:SetTexture(LOGO)
	emblem:SetAllPoints(disc or rep.tex)
	emblem:SetAlpha(page.emblemAlpha or 0.35)
	local mask = holder:CreateMaskTexture()
	mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(emblem)
	emblem:AddMaskTexture(mask)
	page.emblem = emblem
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

--------------------------------------------------------------------------------
-- Keep reloads the UI (1.2.4; the user, 2026-10-28: "after the installer process is done, it should automatically
-- after the last step do a /reload for everything to update"). The game blocks a reload MelloUI's code asks for
-- ("MelloUI blocked by the game: Reload()", 0.19.9), so it is the game's own /reload, run by the player's click on a
-- secure button: MelloUIInstallerReload (made at the first hover, out of combat), laid over Keep while the pointer is
-- on it, its macro "/stopmacro [combat]" then "/reload" (Edit Layout's bridge reaches /editmode the same way). Its
-- PreClick, ours and run before the macro, keeps the setup (ACTIONS.keep); a click Keep cannot take sets no action,
-- so nothing reloads. It acts on the release, as every button (useOnKeyDown false). In a fight it is never laid and
-- Keep is held, as Revert; one laid before the fight does nothing on a click (no attribute is set in a fight, and the
-- macro stops itself). Gone when the pointer leaves, the Keep page ends or the window closes (in a fight: when it
-- ends); the countdown's refresh lays it again where Keep stands (the window dragged, the pointer resting on Keep as a
-- fight ended). Revert reloads nothing: in the session of the install it puts everything back as it was.
--------------------------------------------------------------------------------

local Reload = {}
do
	local MACRO = "/stopmacro [combat]\n/reload"
	local OVER_LEVEL = 10   -- over Keep's own level
	local HIDE_KEY = "Installer: Keep's reload button"
	local button            -- the secure button, once made
	local clicking = false  -- a click under way: the button stays for its PostClick
	local forwarding = false   -- Keep's own hover scripts run from here: our hooks on Keep stay out

	local function KeepButton()
		local page = win and win.pages.keep
		return page and page.count and page.count.keep or nil
	end

	-- Keep can be taken now: its page on show, an answer owed that can be kept, Keep not held
	local function Keepable(keep)
		local pending = Pending()
		return (keep and state.phase == "keep" and keep:IsVisible() and keep:IsEnabled() and pending
			and not pending.failed) and true or false
	end

	-- Keep's hover look run as if the pointer came or went (the pointer is on the secure button over it)
	local function Forward(script)
		local keep = KeepButton()
		if not keep then
			return
		end
		forwarding = true
		local run = _G.ExecuteFrameScript
		local ok, err = true, nil
		if type(run) == "function" then
			ok, err = pcall(run, keep, script)
		else
			local fn = keep:GetScript(script)
			if fn then
				ok, err = pcall(fn, keep)
			end
		end
		forwarding = false
		local handler = not ok and geterrorhandler and geterrorhandler()
		if handler then
			handler(err)
		end
	end

	local function HideNow()
		Reload.Sync()
	end

	function Reload.Hide()
		if not button or clicking or not button:IsShown() then
			return
		end
		if InCombat() then
			MelloUI.Schedule:WhenOutOfCombat(HideNow, HIDE_KEY)
			return
		end
		button:Hide()
		button:ClearAllPoints()
	end

	local PreClick = Shared("PreClick on MelloUIInstallerReload", function(self)
		if InCombat() then
			return
		end
		clicking = true
		local go = Keepable(KeepButton())
		local action = go and "macro" or nil
		if self:GetAttribute("type1") ~= action then
			self:SetAttribute("type1", action)
		end
		if go then
			ACTIONS.keep(nil, true)
		end
	end, "script")

	local PostClick = Shared("PostClick on MelloUIInstallerReload", function()
		clicking = false
		Reload.Sync()
	end, "script")

	local Enter = Shared("OnEnter on MelloUIInstallerReload", function()
		Forward("OnEnter")
	end, "script")

	local Leave = Shared("OnLeave on MelloUIInstallerReload", function()
		Forward("OnLeave")
		Reload.Hide()
	end, "script")

	local function Make()
		if button then
			return button
		elseif InCombat() then
			return nil
		end
		button = CreateFrame("Button", "MelloUIInstallerReload", UIParent, "SecureActionButtonTemplate")
		button:Hide()
		button:RegisterForClicks("LeftButtonUp")
		button:SetAttribute("useOnKeyDown", false)
		button:SetAttribute("type1", "macro")
		button:SetAttribute("macrotext1", MACRO)
		Perf.SetScript(button, "PreClick", PreClick)
		Perf.SetScript(button, "PostClick", PostClick)
		Perf.SetScript(button, "OnEnter", Enter)
		Perf.SetScript(button, "OnLeave", Leave)
		return button
	end

	-- laid over Keep above it, and shown: by measure on UIParent, out of combat only (Reminders.OverlayPlace, the one
	-- way a secure overlay is laid over a button of ours)
	local function Lay(keep)
		local place = MelloUI.Reminders and MelloUI.Reminders.OverlayPlace
		local o = place and Make()
		if not (o and place(o, keep)) then
			return
		end
		if o:GetAttribute("type1") ~= "macro" then
			o:SetAttribute("type1", "macro")
		end
		o:SetFrameStrata(keep:GetFrameStrata())
		o:SetFrameLevel(keep:GetFrameLevel() + OVER_LEVEL)
		o:Show()
	end

	-- the pointer on Keep: the secure button over it
	Reload.KeepEnter = Shared("OnEnter on the installer's Keep (its reload button)", function(keep)
		if not forwarding and Keepable(keep) then
			Lay(keep)
		end
	end, "script")

	-- the pointer gone from Keep: the secure button too, unless the pointer went onto it
	Reload.KeepLeave = Shared("OnLeave on the installer's Keep (its reload button)", function()
		if forwarding or (button and button:IsShown() and button:IsMouseOver()) then
			return
		end
		Reload.Hide()
	end, "script")

	-- (the countdown's refresh, a fight's or Edit Mode's end) laid again where Keep stands while the pointer is on
	-- it; hidden once Keep cannot be taken or the pointer is gone
	function Reload.Sync()
		if clicking or InCombat() then
			return
		end
		local keep = KeepButton()
		if Keepable(keep) and (keep:IsMouseOver() or (button and button:IsShown() and button:IsMouseOver())) then
			Lay(keep)
		else
			Reload.Hide()
		end
	end
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
	page.numeral = top:CreateFontString(nil, "OVERLAY", "MelloUIFont_GameFontNormalHuge")   -- (a font from the start; StyleFont sets its own)
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
	count.question = W.Text(count, "GameFontHighlightLarge", MelloUI.Lang.T(TEXT.keepQuestion), "text")
	count.question:SetJustifyH("CENTER")
	count.question:SetPoint("TOP", page, "TOP", 0, -(20 + RING + 12))
	-- (1.2.4) the line, and that Keep reloads the UI while Keep is there (RefreshKeep picks)
	count.lineKeep = MelloUI.Lang.T(TEXT.keepLine) .. "\n" .. MelloUI.Lang.T(TEXT.keepReload)
	count.lineOnly = MelloUI.Lang.T(TEXT.keepLine)
	count.line = W.Text(count, "GameFontHighlight", count.lineKeep, "text")
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
	-- (1.2.4) Keep reloads the UI: the secure button over it while the pointer is on it (Reload, above)
	Perf.HookScript(count.keep, "OnEnter", Reload.KeepEnter)
	Perf.HookScript(count.keep, "OnLeave", Reload.KeepLeave)
	return 20 + RING + 12 + 144
end

-- the Done content (after a revert), made the first time it is needed (no
-- Reload button: the game blocks a reload MelloUI's code asks for, "MelloUI
-- blocked by the game: Reload()", 0.19.9; the line says to type /reload)
local DONE_ACTS = { "again", "close" }
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
	page.done = done
	return done
end

-- the countdown's number, its pause, Revert and Keep held in combat and while
-- Edit Mode is open (1.2.4: Keep reloads the UI), Keep gone for an install
-- that could not be put back or a revert that only partly worked (the
-- engine's `failed`); Keep's reload button laid again or gone
RefreshKeep = function()
	local page = win and win.pages.keep
	if not page or state.phase ~= "keep" then
		return
	end
	local count = page.count
	local running, seconds, paused, why = I:Countdown()
	page.numeral:SetShown(running)
	if running then
		page.numeral:SetText(MelloUI.Lang.T(NUMS[seconds] or tostring(seconds)))
	end
	local line = state.keepLine
	local held = false
	if paused then
		line = why == "combat" and I.TEXT.pausedCombat or I.TEXT.pausedEditMode
		held = true
	elseif InCombat() then
		line, held = I.TEXT.pausedCombat, true
	end
	count.status:SetText(MelloUI.Lang.T(line or ""))
	count.revert:SetEnabled(not held)
	count.keep:SetEnabled(not held)
	local pending = Pending()
	local keepable = not (pending and pending.failed)
	count.keep:SetShown(keepable)
	local text = keepable and count.lineKeep or count.lineOnly
	if count.line:GetText() ~= text then
		count.line:SetText(text)
	end
	-- only Keep or Revert while the countdown runs
	SetClosable(not running)
	Reload.Sync()
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

-- Done, on the Keep page, after a revert (1.2.4: a kept setup reloads the
-- UI, so this is the one Done page; the user, 2026-10-28: "Drop it"): back
-- to 'Before install', Type /reload to finish when owed; Choose again, Close
ShowDone = function()
	state.phase, state.step = "done", "keep"
	Reload.Hide()   -- (Keep's reload button: after its own click, at its PostClick)
	local page = PageOf("keep")
	page.count:Hide()
	page.numeral:Hide()
	page.emblemAlpha = 1
	if page.emblem then
		page.emblem:SetAlpha(1)
	end
	local done = DoneGroup(page)
	local lines = {}
	done.title:SetText(MelloUI.Lang.T(TEXT.revertedTitle))
	if state.reason == "error" then
		lines[#lines + 1] = I.TEXT.failed
	end
	if state.reloadOwed then
		lines[#lines + 1] = TEXT.revertedReload
	end
	for i = 1, #lines do
		lines[i] = MelloUI.Lang.T(lines[i])
	end
	done.lines:SetText(concat(lines, "\n"))
	-- its buttons, in a centred row
	local total = #DONE_ACTS * DONE_BUTTON_W + (#DONE_ACTS - 1) * 8
	for i, act in ipairs(DONE_ACTS) do
		local b = done.buttons[act]
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
-- The setup's steps (1.2.4): Skin, Layout, Party and raid, Quests and
-- travel, Combat, Chat, Minimap and widgets, Bags, Sound, and their Review
-- rows. Every page the same: its lead, ONE picture (the choice's, in the
-- skin picked; the Layout step's the fit's own drawing of this screen), the
-- choices under it -- cards for one of several, switches for several. A
-- pick changes the picks and nothing else (the draft is made from them
-- again, DraftFor; the fit is dropped, as the fitter reads what the picks
-- switch, and runs again on the Layout or Review step); Install writes them.
-- What each choice sets is the engine's (I.SETUP, I:SetupDraft); a choice
-- whose feature addon is off is not offered, and a step left with nothing to
-- offer is not on the path (IW.PruneSteps, as the window is made).
--------------------------------------------------------------------------------

-- (a function's own scope: the file's main chunk is close to Lua's 200
-- locals; defined and run once while the file loads, making no frame)
local function SetupSteps()
	local SETUP = "setup"
	local CURSEFORGE = "https://www.curseforge.com/wow/addons/melloui-oldschool"
	local OLDSCHOOL = "MelloUI_Oldschool"
	local SKIN_CARD_H = 88
	local SWITCH_W = floor((PAGE_W - CARD_GAP_X) / 2)   -- two columns of switches
	-- a step's picture, by the choice shown (a name ending in "_" is the skin's: "<name><skin>"); a step named by a
	-- string has one picture whatever its choices; the Sound step has none
	local PICTURE = {
		skin = { default = "look_default", modern = "look_modern", oldschool = "look_oldschool" },
		party = { group = "party_group_", portraits = "party_portraits_" },
		quests = "quests_", combat = "combat_", minimap = "column_",
		chat = { view = "chat_", plainchat = "chatgame_" },
		bags = { kinds = "bags_", separate = "bagsgame_" },
	}
	local STEP_OF = {}   -- [step key] = its step in I.SETUP
	for _, st in ipairs(I.SETUP) do
		STEP_OF[st.key] = st
	end
	local loaded = {}    -- [picture texture] = true while it holds a picture (let go on close)

	local function Choice(key)
		return TEXT.choices[key] or { key, "" }
	end

	-- the skin picked, as the engine takes it (Oldschool only with MelloUI_Oldschool there)
	local function Skin()
		return I.SkinOf(Picks())
	end

	-- MelloUI_Oldschool: "loaded", "off" (installed, switched off in the AddOn list) or "missing"
	local function OldschoolState()
		if MelloUI:OldschoolShipped() then
			return "loaded"
		end
		local api = rawget(_G, "C_AddOns")
		local info = type(api) == "table" and api.GetAddOnInfo or rawget(_G, "GetAddOnInfo")
		local ok, name = false, nil
		if type(info) == "function" then
			ok, name = pcall(info, OLDSCHOOL)
		end
		return (ok and type(name) == "string" and not Secret(name)) and "off" or "missing"
	end

	-- the picks changed: the draft is made again; the fit dropped (keepFit: the Layout step's own pick, which the
	-- fitter does not read), the page on show and the footer again
	local function Changed(keepFit)
		state.drafts[SETUP] = nil
		local fit = state.fits[SETUP]
		if fit and not keepFit then
			I:CancelFit(fit)
			state.fits[SETUP] = nil
		end
		state.footLine = nil
		RefreshPage()
		RefreshFooter()
	end

	function IW:Picks()
		return Picks()
	end

	--------------------------------------------------------------------------------
	-- The parts every page has: the lead, the picture, a row of cards, the switches
	--------------------------------------------------------------------------------

	local function Lead(page, text)
		page.lead = W.Text(page, "GameFontHighlight", text and MelloUI.Lang.T(text) or nil, "text")
		page.lead:SetWidth(TEXT_W)
		page.lead:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, -8)
		return page.lead
	end

	-- the picture box, its picture a texture inside its 1 px edge; screen: the whole screen's shape (the Skin step's)
	local function PictureBox(page, screen)
		local box = W.Box(page, "innerPanel", "border", 1)
		box:SetSize(PIC_W, screen and SCREEN_H or PIC_H)
		box.uv = screen and SCREEN_UV or BAND_UV
		box.tex = box:CreateTexture(nil, "ARTWORK")
		box.tex:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
		box.tex:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1)
		page.picture = box
		return box
	end

	local function PictureOf(stepKey, choiceKey)
		local name = PICTURE[stepKey]
		if type(name) == "table" then
			name = name[choiceKey]
		end
		if type(name) ~= "string" then
			return nil
		end
		if name:sub(-1) == "_" then
			name = name .. Skin()
		end
		return PICTURES .. name
	end

	-- the picture set, written only when it is another (loaded on its page's show, let go on close)
	local function ShowPicture(box, file)
		if box.file ~= file then
			box.file = file
			box.tex:SetTexture(file)
			box.tex:SetTexCoord(0, box.uv[1], 0, box.uv[2])
			loaded[box.tex] = file and true or nil
		end
	end

	function IW.ReleasePictures()
		for tex in pairs(loaded) do
			tex:SetTexture(nil)
			loaded[tex] = nil
		end
		for _, page in pairs(win and win.pages or EMPTY) do
			if page.picture then
				page.picture.file = nil
			end
		end
	end

	-- a row of cards across the page (each card knows its step: card.melloStep); tags: [key] = its tag's text
	local function CardRow(page, stepKey, keys, height, tags, onClick)
		local n = #keys
		local w = floor((PAGE_W - (n - 1) * CARD_GAP_X) / n)
		page.cards = {}
		for i, key in ipairs(keys) do
			local c = Choice(key)
			local card = W.Card(page, { width = w, height = height, title = c[1], text = c[2], key = key,
				tag = tags[key], onClick = onClick }, win.shell)
			card.melloStep = stepKey
			page.cards[i] = card
		end
	end

	local function LayCards(page, y, picked)
		local x = 0
		for _, card in ipairs(page.cards) do
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y)
			card:SetSelected(card.key == picked)
			x = x + card:GetWidth() + CARD_GAP_X
		end
		return y + (page.cards[1] and page.cards[1]:GetHeight() or 0)
	end

	-- a switch (a "many" step's choice, an extra under the cards): get and set the picks' answer
	local function Switch(page, key, get, set)
		local c = Choice(key)
		local row = W.ToggleRow(page, 0, c[1], nil, c[2], get, set, { skin = win.shell, look = "palette", zebra = true })
		row:SetWidth(SWITCH_W)
		row.melloKey = key
		page.switches[#page.switches + 1] = row
		return row
	end

	-- the switches shown in two columns from y, each read again; -> the y under them
	local function LaySwitches(page, y, shown)
		local n = 0
		for _, row in ipairs(page.switches) do
			local on = shown == nil or shown(row)
			row:SetShown(on)
			if on then
				local col, line = n % 2, floor(n / 2)
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", page, "TOPLEFT", col * (SWITCH_W + CARD_GAP_X), -(y + line * W.ROW_HEIGHT))
				row:Refresh()
				n = n + 1
			end
		end
		return y + floor((n + 1) / 2) * W.ROW_HEIGHT
	end

	local function LeadHeight(page)
		return Num(page.lead:GetStringHeight()) or 14
	end

	--------------------------------------------------------------------------------
	-- Skin: Default, Modern (recommended), Oldschool (with MelloUI_Oldschool; else its link to copy)
	--------------------------------------------------------------------------------

	local function SkinPick(card)
		if state.phase ~= "choose" then
			return
		end
		local page = win.pages.skin
		if card.key == "oldschool" and OldschoolState() ~= "loaded" then
			page.getShown = true
			RefreshPage()
			if page.get.box:IsShown() then
				page.get.box:SetFocus()
				page.get.box:HighlightText()
			end
			return
		end
		page.getShown = false
		local was = Skin()
		Picks().skin = card.key
		I:SkinPicked(Picks(), was)   -- (an answer that follows the skin, the sound step's, moves along)
		Changed()
	end

	-- the link box: CurseForge's page for MelloUI Oldschool, selected to copy (the game opens no web page); its text
	-- put back if typed over
	local Link_OnTextChanged = Shared("OnTextChanged on the installer's link box", function(box, user)
		if user and box:GetText() ~= CURSEFORGE then
			box:SetText(CURSEFORGE)
			box:HighlightText()
		end
	end, "script")
	local Link_OnFocus = Shared("OnEditFocusGained on the installer's link box", function(box)
		box:HighlightText()
	end, "script")
	local Link_OnEscape = Shared("OnEscapePressed on the installer's link box", function(box)
		box:ClearFocus()
	end, "script")

	local function BuildSkin(page)
		Lead(page, TEXT.skinLead)
		PictureBox(page, true)
		local old = OldschoolState()
		local tags = { modern = TEXT.recommended }
		if old ~= "loaded" then
			tags.oldschool = old == "off" and TEXT.switchedOff or TEXT.notInstalled
		end
		CardRow(page, "skin", { "default", "modern", "oldschool" }, SKIN_CARD_H, tags, SkinPick)
		if old ~= "loaded" then
			page.cards[3]:SetAlpha(0.55)   -- (dimmed: a click shows the way to it)
		end
		-- the way to MelloUI Oldschool (shown after a click on its card)
		local get = CreateFrame("Frame", nil, page)
		get:SetSize(PAGE_W, 1)
		get.line = W.Text(get, "GameFontHighlight", nil, "text")
		get.line:SetWidth(TEXT_W)
		get.line:SetPoint("TOPLEFT", get, "TOPLEFT", PAD, 0)
		local box = CreateFrame("EditBox", nil, get)
		box:SetSize(TEXT_W - 40, 22)
		box:SetAutoFocus(false)
		box:SetFontObject("MelloUIFont_GameFontHighlight")
		box:SetText(CURSEFORGE)
		W.Field(box)
		Perf.SetScript(box, "OnTextChanged", Link_OnTextChanged)
		Perf.SetScript(box, "OnEditFocusGained", Link_OnFocus)
		Perf.SetScript(box, "OnEscapePressed", Link_OnEscape)
		get.box = box
		get.hint = W.Text(get, "GameFontHighlight", MelloUI.Lang.T(TEXT.copyHint), "text")
		get.hint:SetWidth(TEXT_W)
		page.get = get
		page.oldschool = old
		return 1
	end

	local function RefreshSkin(page)
		local y = 8 + LeadHeight(page) + 10
		page.picture:ClearAllPoints()
		page.picture:SetPoint("TOPLEFT", page, "TOPLEFT", (PAGE_W - PIC_W) / 2, -y)
		ShowPicture(page.picture, PictureOf("skin", Skin()))
		y = y + SCREEN_H + 12
		y = LayCards(page, y, Skin())
		local get = page.get
		get:SetShown(page.getShown and page.oldschool ~= "loaded" or false)
		if get:IsShown() then
			y = y + 12
			get:ClearAllPoints()
			get:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
			local missing = page.oldschool == "missing"
			get.line:SetText(MelloUI.Lang.T(missing and TEXT.getOldschool or TEXT.enableOldschool))
			local h = Num(get.line:GetStringHeight()) or 28
			get.box:SetShown(missing)
			get.hint:SetShown(missing)
			if missing then
				get.box:ClearAllPoints()
				get.box:SetPoint("TOPLEFT", get, "TOPLEFT", PAD + 6, -(h + 8))
				get.hint:ClearAllPoints()
				get.hint:SetPoint("TOPLEFT", get, "TOPLEFT", PAD, -(h + 8 + 22 + 6))
				h = h + 8 + 22 + 6 + (Num(get.hint:GetStringHeight()) or 14)
			end
			y = y + h
		end
		return y + 8
	end

	STEPS.skin.build, STEPS.skin.refresh = BuildSkin, RefreshSkin

	--------------------------------------------------------------------------------
	-- Layout: Mello's layout, fitted to this screen (the fit's own drawing), or the player's own
	--------------------------------------------------------------------------------

	local function LayoutPick(card)
		if state.phase ~= "choose" or Picks().layout == card.key then
			return
		end
		Picks().layout = card.key
		Changed(true)
	end

	-- the way on when the fit says the layout cannot go in: keep the player's own (the Screen step's own action is
	-- the refit's switch)
	local fitNoLayout = ACTIONS.noLayout
	function ACTIONS.noLayout(button)
		if Option().base ~= SETUP then
			return fitNoLayout(button)
		end
		if state.phase == "choose" then
			MelloUI:PlayUISound("tab")
			Picks().layout = "own"
			Changed(true)
		end
	end

	local function BuildLayout(page)
		Lead(page)
		FitPicture(page)
		CardRow(page, "layout", { "mello", "own" }, CARD_H, { mello = TEXT.recommended }, LayoutPick)
		page.note = W.Text(page, "GameFontHighlight", nil, "text")
		page.note:SetWidth(TEXT_W)
		page.room = W.Text(page, "GameFontHighlight", nil, "selectedTrim")
		page.room:SetWidth(TEXT_W)
		page.ownButton = Button(page, TEXT.useOwnLayout, 170, "noLayout")
		page.deleteOld = Button(page, "", 230, "deleteOld")
		return 1
	end

	local function RefreshLayout(page)
		local option = Option()
		local mello = Picks().layout ~= "own"
		page.lead:SetText(MelloUI.Lang.F(TEXT.layoutLead, (ScreenText())))
		local y = 8 + LeadHeight(page) + 10
		page.box:ClearAllPoints()
		page.box:SetPoint("TOPLEFT", page, "TOPLEFT", (PAGE_W - PIC_W) / 2, -y)
		-- the fit (it runs from here; Install waits for it): Mello's layout drawn on this screen, or the player's own
		local fit = EnsureFit(option.key)
		local done = fit and fit.done and fit
		local report = done and type(done.report) == "table" and done.report or nil
		DrawPicture(page, mello and report or nil)
		page.pic.msg:SetText(MelloUI.Lang.T(not mello and TEXT.ownLayoutPicture or TEXT.fitting))
		page.pic.msg:SetShown(not mello or not done)
		y = y + PIC_H + 12
		y = LayCards(page, y, mello and "mello" or "own") + 10
		-- the fit's line (why it does not fit, or what is worth a look), the way on, the room in Edit Mode
		local note = mello and NoteText(page, report) or nil
		page.note:SetShown(note ~= nil)
		if note then
			page.note:SetText(note)
			Place(page.note, page, PAD, y)
			y = y + (Num(page.note:GetStringHeight()) or 14) + 8
		end
		local room, old = true, nil
		if mello and done and I:LayoutOn(option, DraftFor(option.key), done) then
			local ok, most = I:LayoutRoom(done)
			room = ok
			if not ok then
				page.room:SetText(MelloUI.Lang.F(I.TEXT.noRoom, most))
				old = OldLayouts(done)[1]
			end
		end
		page.room:SetShown(not room)
		if not room then
			Place(page.room, page, PAD, y)
			y = y + (Num(page.room:GetStringHeight()) or 28) + 8
		end
		local way = mello and ((report and report.tooSmall) or not room) and true or false
		page.ownButton:SetShown(way)
		page.deleteOld:SetShown(old ~= nil)
		if way then
			Place(page.ownButton, page, PAD, y)
			if old then
				page.deleteOld.melloOld = old
				page.deleteOld:SetText(MelloUI.Lang.F(TEXT.deleteOld, old))
				Place(page.deleteOld, page, PAD + 170 + 10, y)
			end
			y = y + BUTTON_H + 10
		end
		return y + 4
	end

	STEPS.layout.build, STEPS.layout.refresh = BuildLayout, RefreshLayout

	--------------------------------------------------------------------------------
	-- The steps of one choice (Party and raid, Chat, Bags, Sound) and of several (Quests and travel, Combat, Minimap
	-- and widgets): their pages made from I.SETUP
	--------------------------------------------------------------------------------

	local function OnePick(card)
		if state.phase ~= "choose" or Picks()[card.melloStep] == card.key then
			return
		end
		Picks()[card.melloStep] = card.key
		Changed()
	end

	local function Offered(list)
		local out = {}
		for _, c in ipairs(list or EMPTY) do
			if I:Offered(c) then
				out[#out + 1] = c
			end
		end
		return out
	end

	local function BuildStep(page, key)
		local st = STEP_OF[key]
		Lead(page, st.kind == "many" and TEXT.manyLead or TEXT.leads[key])
		if PICTURE[key] then
			PictureBox(page)
		end
		page.switches = {}
		local picks = Picks()
		if st.kind == "many" then
			for _, c in ipairs(Offered(st.choices)) do
				Switch(page, c.key, function()
					return picks[key][c.key] and true or false
				end, function(on)
					picks[key][c.key] = on and true or false
					Changed()
				end)
			end
		else
			local keys = {}
			for _, c in ipairs(Offered(st.choices)) do
				keys[#keys + 1] = c.key
			end
			local tags = { [st.pick] = TEXT.recommended }
			if st.pickFor then
				-- (a recommendation that follows the skin: every card has the tag, RefreshStep shows one)
				for _, k in ipairs(keys) do
					tags[k] = TEXT.recommended
				end
			end
			CardRow(page, key, keys, CARD_H, tags, OnePick)
			for _, e in ipairs(Offered(st.extras)) do
				local row = Switch(page, e.key, function()
					return picks.x[e.key] and true or false
				end, function(on)
					picks.x[e.key] = on and true or false
					-- (a pick this one needs, ticked with it: Restock's Reminders)
					local need = e.needs
					if on and need and type(picks[need[1]]) == "table" then
						picks[need[1]][need[2]] = true
					end
					Changed()
				end)
				row.melloOnly = e.only
			end
		end
		return 1
	end

	local function RefreshStep(page, key)
		local st = STEP_OF[key]
		local picks = Picks()
		local y = 8 + LeadHeight(page) + 10
		if page.picture then
			page.picture:ClearAllPoints()
			page.picture:SetPoint("TOPLEFT", page, "TOPLEFT", (PAGE_W - PIC_W) / 2, -y)
			ShowPicture(page.picture, PictureOf(key, picks[key]))
			y = y + PIC_H + 12
		end
		if st.kind == "many" then
			y = LaySwitches(page, y)
		else
			y = LayCards(page, y, picks[key]) + 10
			if st.pickFor then
				local recommended = I:RecommendedPick(st, Skin())
				for _, card in ipairs(page.cards) do
					W.TagShown(card.tag, card.key == recommended)
				end
			end
			local picked = picks[key]
			y = LaySwitches(page, y, function(row)
				return row.melloOnly == nil or row.melloOnly == picked
			end)
		end
		return y + 8
	end

	for _, st in ipairs(I.SETUP) do
		local key = st.key
		STEPS[key].build = function(page)
			return BuildStep(page, key)
		end
		STEPS[key].refresh = function(page)
			return RefreshStep(page, key)
		end
	end

	-- the steps the setup's path keeps: a step with nothing to offer (its feature addons switched off) is left out,
	-- once, as the window is made (a feature addon comes in only with a reload)
	function IW.PruneSteps()
		local option = I:Option(SETUP)
		if not option then
			return
		end
		for i = #option.steps, 1, -1 do
			local st = STEP_OF[option.steps[i]]
			if st and #Offered(st.choices) == 0 then
				table.remove(option.steps, i)
			end
		end
	end

	--------------------------------------------------------------------------------
	-- The Review step's rows for the setup: a line a step, the layout's, the colours'
	--------------------------------------------------------------------------------

	local reviewMemo = {}   -- [step key] = { sig, text }: a line made again only when its picks changed

	local function Line(key, sig, make)
		local m = reviewMemo[key]
		if m and m.sig == sig then
			return m.text
		end
		local text = make()
		reviewMemo[key] = { sig = sig, text = text }
		return text
	end

	local function SkinRow()
		local skin = Skin()
		return Line("skin", skin, function()
			return MelloUI.Lang.F(TEXT.reviewSkin, MelloUI.Lang.T(Choice(skin)[1]))
		end)
	end

	local function StepRow(key)
		local st = STEP_OF[key]
		return function()
			local option = I:Option(SETUP)
			if not (option and IndexOf(option.steps, key)) then
				return nil
			end
			local picks = Picks()
			local names, sig = {}, ""
			if st.kind == "many" then
				for _, c in ipairs(Offered(st.choices)) do
					if picks[key][c.key] then
						names[#names + 1] = Choice(c.key)[1]
						sig = sig .. c.key .. ";"
					end
				end
			else
				names[1] = Choice(picks[key])[1]
				sig = tostring(picks[key]) .. ";"
				for _, e in ipairs(Offered(st.extras)) do
					if picks.x[e.key] and not (e.only and e.only ~= picks[key]) then
						names[#names + 1] = Choice(e.key)[1]
						sig = sig .. e.key .. ";"
					end
				end
			end
			return Line(key, sig, function()
				local list = {}
				for i, name in ipairs(names) do
					list[i] = MelloUI.Lang.T(name)
				end
				local text = #list == 0 and MelloUI.Lang.T(TEXT.reviewNone) or concat(list, ", ")
				return MelloUI.Lang.T(STEPS[key].title) .. ": " .. text
			end)
		end
	end

	local function ColoursRow(option, draft)
		if Skin() == "default" then
			return TEXT.gamePalette
		end
		return PaletteLine(option, draft)
	end

	local rows = { SkinRow, true }
	for _, st in ipairs(I.SETUP) do
		rows[#rows + 1] = StepRow(st.key)
	end
	rows[#rows + 1] = ColoursRow
	rows[#rows + 1] = TEXT.scaleRow
	REVIEW.setup = rows
end
SetupSteps()

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
		if shown and what == "reverted" then
			state.doneMode, state.reason, state.reloadOwed, state.keepLine = "reverted", a, b and true or false, nil
			ShowDone()
			return
		end
		-- (kept: the window closes, no Done page -- the user, 2026-10-28: "Drop it" -- as the UI reloads through
		-- Keep's secure button; closed while the Keep page is still the phase, so no "closed early" line)
		if shown then
			win.frame:Hide()
		end
		state.phase, state.step, state.doneMode, state.keepLine, state.footLine = "choose", Option().steps[1], nil, nil, nil
		state.installed = false
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
		fit.room, fit.most, fit.old = nil, nil, nil
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
	Reload.Hide()   -- (Keep's reload button goes with the window)
	-- (its first run over: from now on its look is the reskin's)
	if MelloUI.Kit and MelloUI.Kit.Showcase then
		MelloUI.Kit:Showcase(false)
	end
	-- the steps' pictures let go; loaded again when their page next shows
	IW.ReleasePictures()
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
	-- (the languages: the table of the language in use, loaded once, at the first open of a window that speaks it)
	MelloUI.Lang:Load()
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
	win = { frame = frame, pages = {}, foot = {} }
	IW.win = win
	-- the shell: the corner ring with the emblem, the plate on the rail,
	-- close, Escape, the fit, the sounds; its one mover keeps no place; the
	-- calm ground (0.15.0: one flat ground, the stone only as a band inside
	-- the rail); the modern look (onelook, the user's pick C): the strip (the
	-- step titles are too long for a brand row in the steps rail), its ends on
	-- the window's margin
	win.shell = Kit:OwnWindow(frame, { area = "installer", ring = { at = "tl", texture = LOGO }, plate = "rail",
		title = MelloUI.Lang.T(STEPS.skin.title), close = true, escape = true, fit = true, sounds = true, mover = MOVER, calm = true,
		inset = EDGE })
	state.escape = true
	-- (1.2.4) the setup's steps with nothing to offer (their feature addons off) left out, before the rail is made
	IW.PruneSteps()
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
	-- the body: ONE panel on the calm ground (the dark inner panel, 2e; one
	-- surface, one panel), and the pages on it: the pager a child of the
	-- panel, so they always lie over it (the clip LOOK_BLEED wider each side
	-- than the pages, which stay where they were, as the panel under them)
	local body = W.Panel(frame)
	body:SetPoint("TOPLEFT", frame, "TOPLEFT", BODY_X, TOP)
	body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -EDGE, BODY_BOTTOM)
	win.body = body
	win.pager = W.Pager(body, { step = 80, bleed = LOOK_BLEED })
	local scroll = win.pager.scroll
	scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", BODY_X - LOOK_BLEED, TOP)
	scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -EDGE + LOOK_BLEED, BODY_BOTTOM)
	-- (the rail's and the body's top where the shell's look has it: under the
	-- corner ring, or under the modern shell's strip; again at every switch)
	local function ShellLay(sh)
		local _, top = sh:Inset(EDGE, TOP)
		win.rail.box:SetPoint("TOPLEFT", frame, "TOPLEFT", EDGE, top)
		body:SetPoint("TOPLEFT", frame, "TOPLEFT", BODY_X, top)
		scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", BODY_X - LOOK_BLEED, top)
	end
	ShellLay(win.shell)
	win.shell:OnKit(ShellLay)
	-- the footer: the screen line (or why Install waits), Back, Continue or
	-- Install (the way forward is the main action: gold, as Install)
	local f = win.foot
	f.next = Button(frame, TEXT.continue, BUTTON_W, "next", true)
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
	-- the configurator steps aside, as it does for Edit Layout
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
	elseif not shown or page == "fit" then
		-- every open starts on its setup's first step (the picks made are
		-- kept); the refit (Fit to this screen) is chosen by its own entry
		-- only and starts on the Screen step
		if page == "fit" and I:Option("fit") then
			state.option = "fit"
		elseif Option().hidden then
			state.option = "setup"
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
