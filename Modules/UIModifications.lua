--------------------------------------------------------------------------------
-- MelloUI - UI Modifications
--
-- One entry in the configurator for everything that changes how the
-- interface looks and behaves per area (user, 2026-09-21): the painted-kit
-- RESKIN (the first, important option: on or off as a whole, then one
-- toggle per area) and the per-area quality-of-life tweaks (nameplates,
-- tooltips, chat, unit frames), which work whether the reskin is on or
-- off. The only thing that matters is that this module is enabled: off,
-- every reskin panel and every folded tweak goes with it.
--
-- The kit panels (Modules/*Panel.lua) and the folded tweak modules stay
-- separate modules in the code, each with its own /xxdump; they are HIDDEN
-- from the configurator and switched from here. A tweak module's own
-- options are shown on this page under its area (`include`), routed to that
-- module's settings by the configurator.
--
-- Folded in as well (user, 2026-09-21/22/24): Tweaks, Vendor, FPS / Latency,
-- Fonts, Bar Textures, Bar Text, Class Icons, Cooldown Timers, Dark Mode,
-- Buffs & Debuffs and Error Messages. Only the feature modules (Quest List,
-- Route, Services, Party Markers, Custom Sounds, Voice Over, Quest Tracker)
-- keep tiles of their own.
--
-- The page (2026-09-24) is switches and sliders on eight tabs: General,
-- Windows, HUD, Combat, Unit Frames & Bars, Chat & Tooltips, Text, Dark
-- Mode / Other. The look is chosen in Dynamic UI Modification only.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("UIModifications")
local hooksecurefunc = Perf.hooksecurefunc

-- The reskin's rows (the Windows and HUD tabs) and the folded features come
-- from the module registry (audit, 2026-09-24, rank 4: they were hand lists
-- here, beside PLAIN_WINDOWS below and the configurator's icons, and had
-- drifted from the modules). Each kit panel gives its row as `window` in its
-- RegisterModule, each folded feature as `tweak` (Core's header):
--   window  { label, desc, tab = "Windows" | "HUD", order, switch, frames,
--             plainGrab, addon, firstOpen }
--   tweak   { label, desc, order, off, always }
--   order   rows with one lead their list (their tab), lowest first; the
--           rest follow in the TOC's order
--   switch  the row is not a kit module's but the look switch of one of
--           MelloUI's own windows: that setting of this module, which
--           Kit:IsOn reads (the Quest Tracker's questTrackerKit; audit,
--           2026-09-24, rank 1)
-- Made into the lists the code below reads, in the order the user sees:
--   PANELS  { module name (or the switch), label, description, tab =,
--           setting = true for a switch: no module goes by that name, and
--           the module paths below pass it by }
--   TWEAKS  { module name, label, description, off =, always = }, each
--           switched by `qol_<name>` here (`off`: off until switched on, as
--           the module was before it moved here; `always`: no switch, its
--           rows each switch one thing and are spread over the tabs)
-- The look of each area (backgrounds, backdrops, the minimap's shape) is
-- chosen in Dynamic UI Modification; here only whether it is reskinned.
-- This file loads before those modules (see the TOC), so the lists, the
-- switches' defaults and their rows on the page are made once every module
-- is in: at the addon's own ADDON_LOADED, before the saved settings are
-- read (Lists, by the plain windows' sweep below).
local PANELS, TWEAKS = {}, {}

-- welcomeAsked: the first-login question (take the tour) was asked
-- (Core/Tutorial.lua); layoutApplied: the Edit Mode layout was put in place
-- when the reskin came on (ReskinOn below); flags without option rows
-- defined further down, next to the rest of the switching; declared here so
-- the button on the page can reach them
local Apply, RestoreAreas, NothingWanted, TweakWanted

-- The page (user, 2026-09-24: "the Dynamic UI Modification is going to be
-- the Main Tool people are going to use when configuring the Look of the UI
-- ... the UI Modification Section is going to be mostly sliders checkboxes
-- etc, we need to reconstruct it a bit and simplify the approach"): eight
-- tabs of switches and sliders. The look (borders, Kit Colours, every
-- background and backdrop, parchment, the minimap's shape) is only in
-- Dynamic UI Modification; its keys stay in these settings. A feature's
-- rows sit under its switch, dimmed while it is off; a sub-option under
-- the switch it needs (`parent` in the modules' options).
local defaults, options = { reskin = true, preloadArt = true, fadeWindows = true, reduceMotion = false,
	parchment_tracker = false, parchment_questTracker = false, parchment_chat = false,
	parchment_whisper = false, parchment_meter = false, parchment_character = false, parchment_tooltip = false, parchment_dialog = false,
	unlock = false, autoSnap = true, positions = {}, welcomeAsked = false, layoutApplied = false, nameFormat = "both" }, {}
for _, k in ipairs(MelloUI.Kit and MelloUI.Kit.borderKinds or {}) do
	defaults[k.key] = k.default
end
-- (each area's and feature's switch is added to these by Lists, below)

local function Add(opt)
	options[#options + 1] = opt
end
local function Tab(name)
	Add({ type = "header", name = name })
end
local function Sub(name)
	Add({ type = "subheader", name = name })
end
-- rows made from the registry: a slot on the page for now, filled in its
-- place by Lists once every module is in (`fill` adds that slot's rows)
local function Slot(fill)
	Add({ slot = fill })
end
-- a feature: its heading, its switch, then its rows (`keys`: which, in
-- order; nil: all of them) under the switch
local function Feature(name, keys, heading)
	Slot(function()
		local tweak
		for _, t in ipairs(TWEAKS) do
			if t[1] == name then
				tweak = t
			end
		end
		if not tweak then
			return   -- (its module is not there)
		end
		if heading ~= false then
			Sub(heading or tweak[2])
		end
		local area = nil
		if not tweak.always then
			area = "qol_" .. name
			Add({ type = "toggle", key = area, name = tweak[2], desc = tweak[3] })
		end
		Add({ type = "include", module = name, area = area, keys = keys, flat = true })
	end)
end
local function Panels(tab)
	Slot(function()
		for _, area in ipairs(PANELS) do
			if area.tab == tab then
				Add({ type = "toggle", key = area[1], name = area[2], desc = area[3], requires = "reskin" })
			end
		end
	end)
end

-- General
Tab("General")
Add({ type = "toggle", key = "reskin", name = "Painted kit reskin", important = true,
	desc = "The whole interface dressed in the painted kit. Off: every area shows the game's own art; the other tabs' features keep working." })
Add({ type = "button", name = "Dynamic UI Modification", hint = "borders, colours, backgrounds, parchment",
	text = "Open", width = 90, requires = "reskin",
	desc = "Choose the look of the reskin on the interface itself: the borders of every window, the Kit Colours, the backgrounds and backdrops of the bars and windows, the parchment sheets and the minimap's shape, with previews.",
	onClick = function()
		if MelloUI.StartDynamicUI then
			MelloUI:StartDynamicUI()
		end
	end })
Add({ type = "toggle", key = "fadeWindows", name = "Windows Fade In",
	desc = "Every window fades in over a fifth of a second when it opens, instead of appearing at once: the character window, talents and spells, professions, the bags, social, guild, group finder, collections, the map, the game menu and the rest. Works with the reskin on or off." })
Add({ type = "toggle", key = "reduceMotion", name = "Reduce Motion",
	desc = "Every MelloUI animation ends at once: windows open without fading, the whisper popup appears in place, the quest tracker's lines do not flash, the configurator jumps instead of gliding. For anyone who finds moving interface parts distracting. Works with UI Modifications switched off as well." })
Add({ type = "toggle", key = "preloadArt", name = "Preload Artwork", requires = "reskin",
	desc = "Load all of the reskin's artwork during the loading screen, so a window opened for the first time after a reload shows its art at once instead of a moment later. Keeps about 13 MB of artwork in memory for the whole session, including for windows you never open. Off: each piece loads the first time a window needs it." })
-- Names (user, 2026-09-22: "make that option global for all of the 3
-- things at the same time"): one dropdown for the unit frames, the
-- nameplates and the name over your own head. Characters here have a first
-- name and a surname. The unit frames and nameplates are re-set by their
-- modules (their `nameFormat`, driven from here); the name the engine draws
-- over heads has ONE setting, the client's `UnitSurnameOwn` cvar ("show
-- player surname over head", the binary's only surname cvar): your own
-- name follows, other players' overhead names are the engine's and have
-- no setting (nameplates on shows them in the chosen form).
Add({ type = "dropdown", key = "nameFormat", name = "Show Names As", values = {
	{ value = "first", label = "First name" },
	{ value = "last", label = "Last name" },
	{ value = "both", label = "First and last name" },
}, desc = "Which part of a character's name is shown, everywhere at once: the player, target, focus, pet, party and raid frames, the nameplates, and the name over your own head (the game's own setting for it; Last name shows both there). A character with no surname shows the name it has. Names over other players' heads without a nameplate are the engine's and have no setting." })
Add({ type = "button", name = "Switch every area on", hint = "when nothing is reskinned any more",
	text = "Switch on", requires = "reskin",
	desc = "Every window and HUD area of the reskin back on, and every feature on these tabs that is on by default.",
	onClick = function(_, db)
		local count = RestoreAreas(db)
		if count == 0 then
			MelloUI:Print("Every area is on already.")
			return
		end
		Apply(db, true)
		MelloUI:Print("%d area%s switched back on.", count, count == 1 and "" or "s")
		if MelloUI.RefreshConfig then
			MelloUI:RefreshConfig()
		end
	end })

-- Windows: which windows the reskin dresses
Tab("Windows")
Panels("Windows")

-- HUD: which parts of the HUD, and what to hide
Tab("HUD")
Panels("HUD")
Sub("Hide")
Feature("Tweaks", { "hideMicroMenu", "hideBagBar", "bagSlotsOnBags", "hideMinimapCoords" }, false)

-- Combat
Tab("Combat")
Feature("Auras")
Feature("ErrorFilter")
Feature("CooldownText")
Feature("Nameplates")
Sub("Combat Text")
Feature("Tweaks", { "worldTextScale" }, false)

-- Unit frames and bars
Tab("Unit Frames & Bars")
Feature("UnitFrames")
Feature("BarText")
Feature("BarTextures")
Feature("ClassIcons")

-- Chat and tooltips
Tab("Chat & Tooltips")
Feature("Chat")
Feature("Tweaks", { "chatNotices" }, false)
Feature("Tooltip")

-- Text: the style and sizes first, the single faces under Advanced
Tab("Text")
Feature("Fonts", { "style", "scaleText", "scaleChat", "scaleTitle", "scaleDamage", "outline",
	{ type = "subheader", name = "Chat on parchment" }, "fontChatParchment", "scaleChatParchment",
	{ type = "subheader", name = "Advanced: one face per role" },
	"fontText", "fontChat", "fontChatText", "fontTitle", "fontDamage" }, false)

-- Dark Mode and the rest
Tab("Dark Mode / Other")
Feature("DarkMode")
Feature("Vendor")
Feature("Stats")

local M = MelloUI:RegisterModule("UIModifications", {
	title = "UI Modifications",
	desc = "The painted kit reskin, area by area, and the interface's features: buffs and debuffs, error messages, cooldowns, unit frames, chat, tooltips, fonts, dark mode and more. The look itself is chosen in Dynamic UI Modification.",
	enabledByDefault = true,
	important = true,
	-- it drives every reskin panel and folded tweak, so its OFF state has to
	-- be applied at start-up too, not only when the switch is thrown
	applyWhenDisabled = true,
	keep = { "savedSurnameOwn", "layoutApplied", "welcomeAsked", "bordersMigrated", "featuresFolded" },   -- a borrowed game setting and one-time steps: never in a profile
	defaults = defaults,
	options = options,
	icon = "Interface\\Icons\\INV_Misc_Gem_Ruby_02",
	flavour = "The painted reskin, area by area, and the quality-of-life tweaks on nameplates, tooltips, chat and unit frames. Start here.",
	group = "The look",
})

-- Unlock the Windows, Auto Snapping and Reset positions sit in the
-- configurator's top bar (user, 2026-09-23: "should be placed along with as
-- the main options on top of that window"): their texts, for its tooltips
M.placementTexts = {
	unlock = { name = "Unlock the Windows",
		desc = "Every window can be dragged by its title strip (the kit's title plate when the reskin is on), the minimap by its zone band, the trackers by their headers, the damage meter by grabbing it and a chat window by a strip along its top edge (so its links and buttons keep working); the border lights up while it moves, the screen darkens with a grid on it, and the mouse wheel while dragging scales it. Every drag area shows as a gold band while this is on, brighter under the mouse. Positions and scales stay, reloads included, and win over Edit Mode's for those elements. Works with the reskin off as well." },
	autoSnap = { name = "Auto Snapping",
		desc = "While a window is dragged, the grid lines near its bottom-left corner light up, and on release the corner snaps onto them. Off: the window stays exactly where it is dropped." },
	reset = { name = "Reset positions",
		desc = "Forget every saved window position and scale: each window returns to the game's own place and size the next time it opens (open ones are closed now), and MelloUI's own windows, such as the Quest Tracker, go back to their standard place and size." },
}

--------------------------------------------------------------------------------
-- The window mover (user, 2026-09-21): while `unlock` is on, a kit window's
-- title plate is a drag handle; the outer rail is lit while it moves; the
-- position is saved and put back on every show and after the game's own
-- panel layout (UpdateUIPanelPositions), so it survives reloads.
-- MelloUI's own windows register with Core (MelloUI:RegisterMover), which
-- keeps their places; this module is the provider of that mover (below)
-- and gives them the same drag while the module is on (audit, 2026-09-24,
-- rank 6). A mover made for one of them carries its entry (mover.entry).
--------------------------------------------------------------------------------

local movers = {}   -- [frame] = mover

-- Edit Mode replaces SetPoint / ClearAllPoints / SetScale (and Hide / Show /
-- SetShown) on its system frames -- the damage meter, the minimap cluster, the
-- objective tracker, the chat -- with Lua overrides that keep its own
-- bookkeeping: frame snapping (self.snappedToFrame), OnEditModeSystemAnchorChanged,
-- ManageFramePositions(), the tracker's Update(). Called from MelloUI they run
-- tainted and leave tainted state behind, and Blizzard code reading it later
-- runs tainted too: the damage meter's fight timer then failed on its secret
-- combat duration on every refresh ("attempt to compare local 'durationSeconds'
-- (a secret number value, while execution tainted by 'MelloUI')", user
-- 2026-09-23). The mover's positions are MelloUI's own, not Edit Mode's, so it
-- calls the plain methods Edit Mode kept aside as <Method>Base and leaves Edit
-- Mode's state alone. A frame without the overrides answers with its own.
local function Raw(frame, method)
	return frame[method .. "Base"] or frame[method]
end

-- A window's scale set with its plain SetScale (Raw), its backgrounds kept at
-- the UI's one resolution: those in it, laid again only when its scale really
-- changed (Kit:SetFrameScale -- audit, 2026-09-24: each put-back and each
-- turn of the wheel laid every background in the UI). A kit without it (a
-- stand-in) lays them all, as before.
local function ScaleFrame(frame, scale)
	local Kit = MelloUI.Kit
	if Kit.SetFrameScale then
		Kit:SetFrameScale(frame, scale, Raw(frame, "SetScale"))
	else
		Raw(frame, "SetScale")(frame, scale)
		Kit:RetileBackgrounds()
	end
end

local function SavedPosition(frame)
	local name = frame.GetName and frame:GetName()
	local db = M.db
	return name and db and db.positions and db.positions[name] or nil, name
end

-- A protected window in combat cannot be moved or scaled by an addon: the
-- game refuses the call and says "ADDON BLOCKED" (player report, 2026-09-23:
-- the talents window opened in combat laid the panels out again, and the
-- mover put the chat window and the talents window back where they had been
-- saved -- ChatFrame1:ClearAllPointsBase(), PlayerSpellsFrame:ClearAllPoints()
-- and :SetScale(), all blocked). Such a put-back waits for the end of the
-- fight; a drag or a wheel turn is simply refused until then.
local function Locked(frame)
	if not (InCombatLockdown and InCombatLockdown()) then
		return false
	end
	local ok, protected = pcall(frame.IsProtected, frame)
	return ok and protected and true or false
end

local afterCombat = {}          -- [frame] = true: put back once the fight is over
local afterCombatFrame = CreateFrame("Frame")
local PutBack
Perf.SetScript(afterCombatFrame, "OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	for frame in pairs(afterCombat) do
		afterCombat[frame] = nil
		if frame:IsShown() then
			PutBack(frame)
		end
	end
end)

local combatNoticeShown = false
local function RefuseInCombat(frame)
	if not Locked(frame) then
		return false
	end
	if not combatNoticeShown then
		combatNoticeShown = true
		MelloUI:Print("This window cannot be moved during combat; it can be again once the fight is over.")
	end
	return true
end

-- A window that carries a neighbour of MelloUI's along: kept on the screen
-- together with it (audit, 2026-09-24, rank 18: the Quest List docked to the
-- world map's right edge went off the screen with a map placed at that
-- edge, as only the map was measured). [window name] = the neighbour's name,
-- looked up when needed (made on the map's first show).
local COMPANIONS = { WorldMapFrame = "MelloUIQuestListPanel" }

local function Companion(frame)
	local name = COMPANIONS[frame:GetName() or ""]
	return name and _G[name] or nil
end

-- The saved place and scale put on a window (PutBack, in a pcall). The
-- place is kept on the screen (user, 2026-09-24: "UI Scaling Break the UI"):
-- the offsets are in the window's own units from the screen's centre, so
-- they grow with the UI scale while the screen, in those units, shrinks, and
-- a window saved near an edge at a small UI scale landed partly or wholly
-- off the screen at a larger one (or after a change to a smaller
-- resolution). Core's MelloUI:FitOnScreen pulls it in just enough, its
-- neighbour with it, the top-left corner kept on the screen when it is
-- larger than the screen; the saved entry itself is not changed, so the old
-- place comes back with the old scale. Only the mover's own anchor
-- (BOTTOMLEFT to the screen's CENTER), and a window with a neighbour
-- whatever its anchor (fitted with it on its drop as well); a frame whose
-- rect or scale cannot be read is left as saved.
local function PlaceSaved(frame, pos, mover)
	if pos.scale and pos.scale > 0 and frame.SetScale then
		if mover then
			mover.scaling = true
		end
		ScaleFrame(frame, pos.scale)   -- (its backgrounds with it)
		if mover then
			mover.scaling = nil
		end
	end
	-- the mover anchors BOTTOMLEFT to the screen's CENTRE; an entry carries
	-- the anchor only when it differs
	Raw(frame, "ClearAllPoints")(frame)
	Raw(frame, "SetPoint")(frame, pos.point or "BOTTOMLEFT", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
	local companion = Companion(frame)
	if companion or (not pos.point and not pos.relPoint) then
		MelloUI:FitOnScreen(frame, companion)
	end
end

PutBack = function(frame)
	local mover = movers[frame]
	-- a window registered with Core: its place is Core's (put back on its
	-- show and after a UI Scale change there)
	if mover and mover.entry then
		return
	end
	local pos = SavedPosition(frame)
	if not pos or not M.isEnabled then
		return
	end
	if Locked(frame) then
		afterCombat[frame] = true
		afterCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	local was = mover and mover.placing
	if mover then
		mover.placing = true
	end
	-- (a function made once, not a closure per put-back: this runs on every
	-- show and every panel layout)
	local ok = pcall(PlaceSaved, frame, pos, mover)
	if mover then
		mover.placing = was
	end
	if not ok then
		MelloUI:Notice("UI Modifications: could not place %s.", tostring(frame:GetName()))
	end
end

-- The lit rail: a tint can only darken painted iron, so the rails are
-- drawn ADDITIVELY while the window moves (the art adds its own light
-- to what is under it: a real glow, gold) — user, 2026-09-21: "500 %"
-- ... and an outer glow around the window while it moves (user,
-- 2026-09-21): four additive gold bands outside the window's edges, each
-- fading out away from it. Made once per window, shown only while dragging.
local GLOW = 28
local SNAP = 16   -- px: the light snap to the nearest grid line on release (each axis on its own)
local SCALE_STEP, SCALE_MIN, SCALE_MAX = 0.05, 0.5, 2   -- the wheel while dragging
-- The grab areas SHOW while the windows are unlocked (user, 2026-09-22):
-- nothing said where a window could be taken hold of, least of all now that
-- a grab is a strip and not the whole window. Each one is a gold wash with a
-- thin edge, brighter under the mouse. (The wash was hidden on 2026-09-21,
-- when a grab covered a whole window and the wash covered it with it.)
local WASH, WASH_LIT = 0.12, 0.25
local EDGE, EDGE_LIT = 0.45, 0.9
local STRIP = 22   -- px: the height of a grab that is only a strip along a window's top edge

local function OuterGlow(frame, mover)
	if mover.glow then
		return mover.glow
	end
	local glow = CreateFrame("Frame", nil, frame)
	glow:SetFrameStrata(frame:GetFrameStrata())
	glow:SetFrameLevel(math.max((frame:GetFrameLevel() or 1) - 1, 0))
	glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -GLOW, GLOW)
	glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", GLOW, -GLOW)
	glow:EnableMouse(false)
	local inner = CreateColor(1, 0.8, 0.3, 0.7)
	local outer = CreateColor(1, 0.8, 0.3, 0)
	local function Band(point1, point2, orientation, fromInner)
		local tex = glow:CreateTexture(nil, "BACKGROUND")
		tex:SetColorTexture(1, 1, 1, 1)
		tex:SetBlendMode("ADD")
		tex:SetPoint(point1[1], frame, point1[2], point1[3], point1[4])
		tex:SetPoint(point2[1], frame, point2[2], point2[3], point2[4])
		if fromInner then
			tex:SetGradient(orientation, inner, outer)
		else
			tex:SetGradient(orientation, outer, inner)
		end
		return tex
	end
	-- top: from the window's top edge upward (VERTICAL runs bottom -> top)
	Band({ "BOTTOMLEFT", "TOPLEFT", 0, 0 }, { "TOPRIGHT", "TOPRIGHT", 0, GLOW }, "VERTICAL", true)
	-- bottom: downward
	Band({ "TOPLEFT", "BOTTOMLEFT", 0, 0 }, { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, -GLOW }, "VERTICAL", false)
	-- left: leftward (HORIZONTAL runs left -> right)
	Band({ "TOPRIGHT", "TOPLEFT", 0, 0 }, { "BOTTOMLEFT", "BOTTOMLEFT", -GLOW, 0 }, "HORIZONTAL", false)
	-- right: rightward
	Band({ "TOPLEFT", "TOPRIGHT", 0, 0 }, { "BOTTOMRIGHT", "BOTTOMRIGHT", GLOW, 0 }, "HORIZONTAL", true)
	glow:Hide()
	mover.glow = glow
	return glow
end

-- The rest of the screen darkens while a window moves, so the eye stays on
-- it (user, 2026-09-21): one black veil at the window's strata, at level 0
-- under everything drawn there — it dims the world and every lower strata.
local veil = nil

-- ... with a grid on it: a line every GRID px out from the screen's
-- centre, the two centre lines gold and brighter (user, 2026-09-21: "where
-- the middle of the screen is").
local GRID = 50

-- The lines are pooled on the veil and the grid drawn again whenever the
-- screen's size in UI units is no longer the one it was drawn for (user,
-- 2026-09-24: "UI Scaling Break the UI" -- drawn once, the grid kept the
-- old UI scale's screen: its centre lines off the centre, lines missing or
-- running past the edge, and the lit snap lines too short).
local function DrawGrid(parent)
	local w, h = UIParent:GetWidth(), UIParent:GetHeight()
	if not (w and h) or w <= 0 or h <= 0 then
		return
	end
	parent.gridLines = parent.gridLines or {}
	local pool, used = parent.gridLines, 0
	parent.gridW, parent.gridH = w, h
	local cx, cy = w / 2, h / 2
	local function Line(vertical, offset, centre)
		used = used + 1
		local tex = pool[used]
		if not tex then
			tex = parent:CreateTexture(nil, "BORDER")
			pool[used] = tex
		end
		tex:ClearAllPoints()
		tex:Show()
		if centre then
			tex:SetColorTexture(1, 0.82, 0, 0.55)
		else
			tex:SetColorTexture(1, 1, 1, 0.08)
		end
		if vertical then
			tex:SetSize(centre and 2 or 1, h)
			tex:SetPoint("TOP", parent, "TOPLEFT", cx + offset, 0)
		else
			tex:SetSize(w, centre and 2 or 1)
			tex:SetPoint("LEFT", parent, "BOTTOMLEFT", 0, cy + offset)
		end
	end
	local n = 1
	while n * GRID < cx do
		Line(true, n * GRID, false)
		Line(true, -n * GRID, false)
		n = n + 1
	end
	n = 1
	while n * GRID < cy do
		Line(false, n * GRID, false)
		Line(false, -n * GRID, false)
		n = n + 1
	end
	Line(true, 0, true)
	Line(false, 0, true)
	for i = used + 1, #pool do
		pool[i]:Hide()
	end
end

-- The window's centre relative to the screen's centre, in UIParent units
-- (a panel the manager scaled has its own scale: GetCenter answers in
-- that, the grid is in UIParent's — the first snap landed off-centre, user
-- 2026-09-21), and the factor that turns a UIParent offset into the
-- frame's own anchor units.
-- The window's BOTTOM-LEFT corner (user, 2026-09-21: the corner is what
-- snaps) relative to the screen's centre, in UIParent units ...
local function CornerOffset(frame)
	local left, bottom = frame:GetLeft(), frame:GetBottom()
	local fs, us = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	if not (left and bottom and fs and us and sw and sh) or fs <= 0 or us <= 0 then
		return nil
	end
	local dx = (left * fs - sw / 2 * us) / us
	local dy = (bottom * fs - sh / 2 * us) / us
	return dx, dy, us / fs
end

-- The grid line an offset would snap to (nil: none within SNAP)
local function SnapTarget(offset)
	local nearest = math.floor(offset / GRID + 0.5) * GRID
	if math.abs(offset - nearest) <= SNAP then
		return nearest
	end
	return nil
end

local function Veil(frame, on)
	if on then
		if not veil then
			veil = CreateFrame("Frame", nil, UIParent)
			veil:SetAllPoints(UIParent)
			veil:EnableMouse(false)
			local tex = veil:CreateTexture(nil, "BACKGROUND")
			tex:SetAllPoints()
			tex:SetColorTexture(0, 0, 0, 0.6)
			pcall(DrawGrid, veil)
			-- the lines the window would snap to, lit while it is near them
			veil.hlX = veil:CreateTexture(nil, "ARTWORK")
			veil.hlX:SetColorTexture(1, 0.9, 0.4, 0.9)
			veil.hlX:SetSize(3, UIParent:GetHeight())
			veil.hlY = veil:CreateTexture(nil, "ARTWORK")
			veil.hlY:SetColorTexture(1, 0.9, 0.4, 0.9)
			veil.hlY:SetSize(UIParent:GetWidth(), 3)
		end
		-- the screen is another size in UI units since the grid was drawn
		-- (the UI scale or the resolution changed): drawn again for it
		local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
		if screenW and screenH and (math.abs(screenW - (veil.gridW or 0)) > 0.5 or math.abs(screenH - (veil.gridH or 0)) > 0.5) then
			pcall(DrawGrid, veil)
			veil.hlX:SetSize(3, screenH)
			veil.hlY:SetSize(screenW, 3)
		end
		veil:SetFrameStrata(frame:GetFrameStrata() or "MEDIUM")
		veil:SetFrameLevel(0)
		veil.hlX:Hide()
		veil.hlY:Hide()
		-- the wheel is caught on the veil as well: a window scaled down
		-- slides out from under the cursor, which then no longer sits on
		-- the plate (user, 2026-09-21: could not scale back up)
		-- ... and the veil takes the mouse for the drag's duration: a wheel
		-- turn that reaches nothing zooms the camera (user, 2026-09-21); the
		-- button is held anyway, so no click is lost
		veil:EnableMouse(true)
		veil:EnableMouseWheel(true)
		Perf.SetScript(veil, "OnMouseWheel", function(_, delta)
			if veil.onWheel then
				veil.onWheel(delta)
			end
		end)
		Perf.SetScript(veil, "OnUpdate", function(self)
			local dx, dy = CornerOffset(frame)
			if not dx or not (M.db and M.db.autoSnap ~= false) then
				self.hlX:Hide()
				self.hlY:Hide()
				return
			end
			local tx, ty = SnapTarget(dx), SnapTarget(dy)
			local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
			if tx then
				self.hlX:ClearAllPoints()
				self.hlX:SetPoint("TOP", self, "TOPLEFT", sw / 2 + tx, 0)
				self.hlX:Show()
			else
				self.hlX:Hide()
			end
			if ty then
				self.hlY:ClearAllPoints()
				self.hlY:SetPoint("LEFT", self, "BOTTOMLEFT", 0, sh / 2 + ty)
				self.hlY:Show()
			else
				self.hlY:Hide()
			end
		end)
		veil:Show()
	elseif veil then
		Perf.SetScript(veil, "OnUpdate", nil)
		veil:EnableMouseWheel(false)
		veil:EnableMouse(false)
		veil.onWheel = nil
		veil:Hide()
	end
end

local function Light(shell, on, frame, mover)
	if frame then
		pcall(Veil, frame, on)
	end
	local outer = shell.outer
	if outer and outer.skin and outer.skin.art then
		for _, tex in ipairs(outer.skin.art) do
			if on then
				tex:SetBlendMode("ADD")
				tex:SetVertexColor(1, 0.85, 0.35)
			else
				tex:SetBlendMode("BLEND")
				tex:SetVertexColor(1, 1, 1)
			end
		end
	end
	if frame and mover then
		local ok, glow = pcall(OuterGlow, frame, mover)
		if ok and glow then
			glow:SetShown(on and true or false)
		end
	end
end

-- The size readout (user, 2026-09-24: "when i mouse scroll to resize it, it
-- should show me at which % of the standard UI scale that window currently
-- is, so that i know how to bring it back to normal"). While a window is
-- dragged, a small plate above it says how big it is against its STANDARD
-- size and how to get back there; it stays a moment after the release and
-- then fades (just goes, with Reduce Motion). Hovering a grab while the
-- windows are unlocked shows it as well, for a window that is not at 100 %.
-- 100 % is the size the window has without a scale of MelloUI's: its own
-- scale (GetScale, so the game's UI Scale does not count) divided by the scale
-- the game gives it -- 1 for most, Edit Mode's Size for the HUD, the panel
-- manager's fit on a small screen -- which the mover notes when it is made
-- and whenever something other than the mover scales the window (mover.base).
-- A window registered with Core (MelloUI's own: the quest tracker) is at
-- 100 % at scale 1, or at its entry's base (audit, 2026-09-25: read when its
-- mover was made, the quest tracker's 100 % was whatever Scale it had then).
-- The plate is anchored to the screen, never to the window: a frame
-- anchored to a protected window becomes protected itself and could no
-- longer be hidden in combat.
local SizeTip = {}
do
	local HOLD, FADE = 1.2, 0.4   -- s: shown after the release, then the fade
	local DETENT = 0.3            -- s: the wheel holds at 100 % for this long
	local tip, owner, hold

	-- v when it is a plain number, else nil: MelloUI.Safe (Core.lua), one set
	-- for the addon
	local PlainNumber = MelloUI.Safe.Number

	-- whether a registered window named its 100 % (its entry's base)
	function SizeTip.HasBase(entry)
		local base = entry.base
		return (PlainNumber(base) and base > 0) and true or false
	end

	-- a registered window's 100 %: its entry's base, or 1
	function SizeTip.EntryBase(entry)
		return SizeTip.HasBase(entry) and entry.base or 1
	end

	-- the scale that is 100 % for this mover's window
	function SizeTip.Base(mover)
		if mover.entry then
			return SizeTip.EntryBase(mover.entry)
		end
		local base = mover.base
		return (PlainNumber(base) and base > 0) and base or 1
	end

	-- the window's own scale, nil when it cannot be read
	function SizeTip.Scale(frame)
		local ok, scale = pcall(frame.GetScale, frame)
		return (ok and PlainNumber(scale) and scale > 0) and scale or nil
	end

	-- the next size for a wheel notch, in whole percent of the standard size:
	-- always a multiple of the step (so 100 % is never stepped over), and a
	-- wheel still spinning right after it landed on 100 % is held there a
	-- moment (a detent), so a quick turn back stops on the standard size.
	-- nil: the notch was held.
	function SizeTip.Step(mover, percent, delta, step)
		local now = GetTime and GetTime() or 0
		if mover.detent and now < mover.detent and (delta > 0) == mover.detentUp then
			return nil
		end
		local p = math.floor(percent + 0.5)
		local nextP
		if delta > 0 then
			nextP = math.floor(p / step) * step + step
		else
			nextP = math.ceil(p / step) * step - step
		end
		mover.detent, mover.landed = nil, nil
		if nextP == 100 and p ~= 100 then
			mover.detent, mover.detentUp, mover.landed = now + DETENT, delta > 0, true
		end
		return nextP
	end

	local function Percent(mover)
		local scale = SizeTip.Scale(mover.frame)
		return scale and math.floor(scale / SizeTip.Base(mover) * 100 + 0.5) or nil
	end

	-- above the window, centred; below it where there is no room above, and
	-- over its top when it fills the screen (the plate is clamped to the screen)
	local function Place()
		local f = owner and owner.frame
		if not f then
			return
		end
		local ok, left, bottom, w, h = pcall(f.GetRect, f)
		local okS, fs = pcall(f.GetEffectiveScale, f)
		local us, sh, th = UIParent:GetEffectiveScale(), UIParent:GetHeight(), tip:GetHeight()
		if not (ok and okS) then
			return
		end
		-- each asked in turn (a list of them stopped at the first nil, so a
		-- window not laid out yet reached the sums below; audit, 2026-09-24)
		local N = PlainNumber
		if not (N(left) and N(bottom) and N(w) and N(h) and N(fs) and N(us) and N(sh) and N(th)) then
			return
		end
		if us <= 0 then
			return
		end
		local k = fs / us
		local cx, top, low = (left + w / 2) * k, (bottom + h) * k, bottom * k
		tip:ClearAllPoints()
		if top + 8 + th <= sh then
			tip:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", cx, top + 8)
		elseif low - 8 - th >= 0 then
			tip:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx, low - 8)
		else
			tip:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx, top - 30)
		end
	end

	-- a plate in the palette: the window's ground, a trim edge (the selected
	-- trim at exactly 100 %), the size in the kit's title face and gold, the
	-- hint in body text; at the tooltip strata, over the darkened grid
	local function Build()
		local P = MelloUI.Palette
		tip = CreateFrame("Frame", nil, UIParent)
		tip:SetFrameStrata("TOOLTIP")
		tip:SetClampedToScreen(true)
		tip:EnableMouse(false)
		tip:Hide()
		local fill = tip:CreateTexture(nil, "BACKGROUND")
		fill:SetAllPoints()
		fill:SetColorTexture(P.mainWindow[1], P.mainWindow[2], P.mainWindow[3], 0.94)
		tip.edges = {}
		for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
			{ "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
			local t = tip:CreateTexture(nil, "BORDER")
			t:SetPoint(e[1], tip, e[1])
			t:SetPoint(e[2], tip, e[2])
			if e[3] then
				t:SetWidth(e[3])
			end
			if e[4] then
				t:SetHeight(e[4])
			end
			tip.edges[#tip.edges + 1] = t
		end
		tip.value = tip:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		tip.value:SetPoint("TOP", tip, "TOP", 0, -7)
		tip.value:SetTextColor(P.selectedTrim[1], P.selectedTrim[2], P.selectedTrim[3])
		if MelloUI.Kit and MelloUI.Kit.TitleFont then
			pcall(MelloUI.Kit.TitleFont, MelloUI.Kit, tip.value, true)
		end
		tip.hint = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		tip.hint:SetPoint("TOP", tip.value, "BOTTOM", 0, -4)
		tip.hint:SetTextColor(P.text[1], P.text[2], P.text[3])
		-- a line of its own, so each is measured on its own for the width
		tip.note = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		tip.note:SetPoint("TOP", tip.hint, "BOTTOM", 0, -2)
		tip.note:SetTextColor(P.text[1], P.text[2], P.text[3])
		Perf.SetScript(tip, "OnUpdate", function(self, elapsed)
			Place()
			if hold then
				hold = hold - elapsed
				if hold <= 0 then
					hold = nil
					if MelloUI.Anim then
						MelloUI.Anim:FadeOut(self, FADE)
					else
						self:Hide()
					end
				end
			end
		end)
	end

	local function Fill(mover, percent)
		local P = MelloUI.Palette
		local standard = percent == 100
		tip.value:SetFormattedText("Size %d%%", percent)
		local note = nil
		if standard then
			tip.hint:SetText("The standard size")
		elseif mover.moving then
			tip.hint:SetText("Wheel back to 100% for the standard size")
			note = "Reset positions puts every window back"
		else
			tip.hint:SetText("Drag it and wheel back to 100% for the standard size")
		end
		tip.note:SetText(note or "")
		tip.note:SetShown(note ~= nil)
		local edge = standard and P.selectedTrim or P.trim
		for _, t in ipairs(tip.edges) do
			t:SetColorTexture(edge[1], edge[2], edge[3], 1)
		end
		local w = math.max(tip.value:GetStringWidth() or 0, tip.hint:GetStringWidth() or 0, note and tip.note:GetStringWidth() or 0)
		local h = (tip.value:GetStringHeight() or 16) + (tip.hint:GetStringHeight() or 10) + (note and (tip.note:GetStringHeight() or 10) + 2 or 0)
		tip:SetSize(math.ceil(w) + 24, math.ceil(h) + 18)
	end

	-- shows (or refreshes) the readout for this mover's window; `hover`: only
	-- for a window that is not at its standard size
	function SizeTip.Show(mover, hover)
		local percent = Percent(mover)
		if not percent or (hover and percent == 100) then
			return
		end
		if not tip then
			Build()
		end
		owner, hold = mover, nil
		if MelloUI.Anim then
			MelloUI.Anim:Stop(tip, "alpha")
		end
		tip:SetAlpha(1)
		Fill(mover, percent)
		Place()
		tip:Show()
	end

	-- lets it go after `delay` s (then the fade); a drag in progress keeps it
	function SizeTip.Release(mover, delay)
		if tip and owner == mover and not mover.moving and tip:IsShown() and not hold then
			hold = delay or HOLD
		end
	end
end

local AddHandle   -- below

-- A window registered with Core let go (the Quest Tracker's `save`: it keeps
-- its own place and scale); one with a key in Core's store, which hangs it
-- by its own anchor again, kept on the screen with its companions (Core's
-- RestorePosition); one with neither stays where it was dropped.
-- The store's scale is written only when the wheel scaled the window in
-- this drag; otherwise the saved one stays, as Core's plain drag leaves it.
-- It is dropped only at a 100 % the window named (its entry's base): one
-- that named none may have a size of its own, laid before its place (the
-- Route arrow's Arrow Size), and wheeled back to scale 1 and dropped it came
-- back at that size and off its place (review, 2026-09-25).
local function SaveEntry(mover, entry)
	local frame = mover.frame
	if entry.save then
		local ok, err = pcall(entry.save, frame)
		if not ok then
			MelloUI:Notice("UI Modifications: %s", tostring(err))
		end
	elseif entry.key ~= nil then
		-- (a scale that cannot be read leaves the saved one as it is: nil)
		local scale = mover.scaled and SizeTip.Scale(frame) or nil
		if scale and SizeTip.HasBase(entry) and math.abs(scale - entry.base) <= 0.001 then
			scale = false
		end
		if MelloUI:SavePosition(entry.key, frame, scale) then
			MelloUI:RestorePosition(entry.key, frame)
		end
	end
end

-- shell.entry: a window registered with Core (the provider's Attach), its
-- handle shell.title
local function MakeMover(frame, shell)
	local handle = shell.title and (shell.title.object or shell.title)
	local entry = shell.entry
	local existing = movers[frame]
	if existing then
		-- a second registration for the window: the kit's shell for a
		-- window that already has its plain grab (its lit rail comes
		-- along), or the plain grab for a kit window — one mover, another
		-- handle (user, 2026-09-22: the mover works with the reskin off);
		-- or Core's registration of a window that had a grab here: its
		-- place is Core's from then on, and so is its handle's drag
		existing.shell.outer = shell.outer or existing.shell.outer
		existing.entry = existing.entry or entry
		AddHandle(existing, handle, entry)
		return
	end
	local usable = handle and handle.EnableMouse and handle.SetScript
	if not usable and not shell.outer then
		return
	end
	-- a shell may bring only its lit rail (`outer`) and leave the handle to
	-- the plain grab that the sweep makes: the mover is still built, and
	-- AddHandle below does nothing until there is one (user, 2026-09-22: the
	-- damage meter is dragged by its header, which only the sweep knows)
	local mover = { shell = shell, handles = {}, washes = {}, frame = frame, entry = entry }
	movers[frame] = mover
	-- the game's own scale for the window, before a saved one is put on it
	-- (PutBack at the end): the size readout's 100 % (user, 2026-09-24); a
	-- registered window's is its entry's (SizeTip.Base)
	if not entry then
		mover.base = SizeTip.Scale(frame)
	end
	-- the mouse wheel while dragging: the window's scale, 5 % a notch,
	-- 50 % .. 200 % (user, 2026-09-21), saved with the position
	local function Wheel(delta)
		-- a fight that starts in the middle of a drag: no scaling until it ends
		if not mover.moving or not frame.SetScale or Locked(frame) then
			return
		end
		local current = SizeTip.Scale(frame)
		if not current then
			return
		end
		-- (user, 2026-09-24: the size readout) a notch goes to the next
		-- round percentage of the window's STANDARD size, not the raw scale
		-- plus 5 %, so every step reads round and 100 % is always landed on
		-- (with a short hold there); the range is 50 .. 200 % of the standard
		-- size, or a registered window's own absolute range (its entry's
		-- min / max)
		local range = mover.entry
		local base = SizeTip.Base(mover)
		local percent = SizeTip.Step(mover, current / base * 100, delta, SCALE_STEP * 100)
		if not percent then
			return
		end
		local scale = math.max(range and range.min or SCALE_MIN * base, math.min(range and range.max or SCALE_MAX * base, base * percent / 100))
		if math.abs(scale - current) < 0.001 then
			mover.landed = nil
			return
		end
		-- the window stays glued to the cursor (user, 2026-09-21): the
		-- point under the cursor is kept under it — the drag is paused,
		-- the frame scaled, re-anchored so that point is back under the
		-- cursor, and the drag resumed (the button is still held)
		local okC, cx, cy = pcall(GetCursorPosition)
		local okR, left, bottom, w, h = pcall(frame.GetRect, frame)
		local fs = frame:GetEffectiveScale()
		mover.scaling = true
		-- (its backgrounds keep the UI's one resolution as it is scaled: more
		-- of them shows -- ScaleFrame)
		if okC and okR and cx and left and w and h and w > 0 and h > 0 and fs and fs > 0 then
			local fx, fy = (cx / fs - left) / w, (cy / fs - bottom) / h
			frame:StopMovingOrSizing()
			ScaleFrame(frame, scale)
			local fs2 = frame:GetEffectiveScale()
			if fs2 and fs2 > 0 then
				Raw(frame, "ClearAllPoints")(frame)
				Raw(frame, "SetPoint")(frame, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / fs2 - fx * w, cy / fs2 - fy * h)
			end
			frame:StartMoving()
		else
			ScaleFrame(frame, scale)
		end
		mover.scaling = nil
		mover.scaled = scale   -- (this drag scaled it: SaveEntry)
		-- the readout follows the new size; landing on the standard size
		-- gives a soft tick (the chat's scroll click)
		SizeTip.Show(mover)
		if mover.landed then
			MelloUI:PlayUISound("tick")
		end
		mover.landed = nil
	end
	mover.Wheel = Wheel
	-- true: the drag is under way (the provider's answer to Core)
	mover.DragStart = function()
		if not (M.isEnabled and M.db and M.db.unlock) or RefuseInCombat(frame) then
			return false
		end
		frame:SetMovable(true)
		frame:SetClampedToScreen(true)
		frame:StartMoving()
		mover.moving, mover.scaled = true, nil
		Light(shell, true, frame, mover)
		if veil then
			veil.onWheel = Wheel
		end
		SizeTip.Show(mover)
		return true
	end
	mover.DragStop = function()
		if not mover.moving then
			return
		end
		frame:StopMovingOrSizing()
		Light(shell, false, frame, mover)
		-- still "moving" through the snap and the save: the SetPoint hook
		-- below would otherwise put the window back to its PREVIOUS saved
		-- place the moment the snap anchors it (user, 2026-09-21: "does not
		-- snap on that spot")
		-- light snapping: a window released with its centre within SNAP px
		-- of a screen centre line is put on that line (each axis on its own)
		pcall(function()
			local dx, dy, k = CornerOffset(frame)
			if not dx or not (M.db and M.db.autoSnap ~= false) then
				return
			end
			local tx, ty = SnapTarget(dx), SnapTarget(dy)
			if tx or ty then
				-- the corner onto the lit lines: anchored from the screen's
				-- centre by the snapped offsets, in the window's own units
				Raw(frame, "ClearAllPoints")(frame)
				Raw(frame, "SetPoint")(frame, "BOTTOMLEFT", UIParent, "CENTER", (tx or dx) * k, (ty or dy) * k)
			end
		end)
		-- a window registered with Core (MelloUI's own): saved by itself or
		-- in the store under its key (SaveEntry)
		if mover.entry then
			SaveEntry(mover, mover.entry)
			mover.moving = nil
			SizeTip.Release(mover)
			return
		end
		local _, name = SavedPosition(frame)
		if name and M.db then
			M.db.positions = M.db.positions or {}
			local ok, point, _, relPoint, x, y = pcall(frame.GetPoint, frame, 1)
			if ok and point and x and y then
				local okS, scale = pcall(frame.GetScale, frame)
				-- compact: the backup holds a few thousand characters for
				-- everything and a raw float took a third of a window's entry.
				-- A tenth of a pixel, the scale to a hundredth, the anchor
				-- only when it is not the mover's own BOTTOMLEFT to CENTER.
				-- No scale is kept for a window at its standard size (user,
				-- 2026-09-24: the size readout's 100 %, the game's own scale
				-- for it -- not always 1), so the game's scale stays its own
				M.db.positions[name] = { point = point ~= "BOTTOMLEFT" and point or nil,
					relPoint = relPoint ~= "CENTER" and relPoint or nil,
					x = math.floor(x * 10 + 0.5) / 10, y = math.floor(y * 10 + 0.5) / 10,
					scale = (okS and type(scale) == "number" and math.abs(scale - SizeTip.Base(mover)) > 0.001) and (math.floor(scale * 100 + 0.5) / 100) or nil }
				-- the entries saved before this rounding, once
				for _, pos in pairs(M.db.positions) do
					if type(pos) == "table" then
						if type(pos.x) == "number" then pos.x = math.floor(pos.x * 10 + 0.5) / 10 end
						if type(pos.y) == "number" then pos.y = math.floor(pos.y * 10 + 0.5) / 10 end
						if type(pos.scale) == "number" then pos.scale = math.floor(pos.scale * 100 + 0.5) / 100 end
						if pos.point == "BOTTOMLEFT" then pos.point = nil end
						if pos.relPoint == "CENTER" then pos.relPoint = nil end
					end
				end
				-- through the setting path, so the backup this client's saved
				-- variables rely on is written (a plain write was lost on
				-- reload — user, 2026-09-21)
				MelloUI:NotifySettingChanged(M.name, "positions", M.db.positions)
			end
		end
		-- the world map with the Quest List beside it: the pair kept on the
		-- screen from the drop on (the map alone is clamped while it moves);
		-- the place saved is where it was dropped, as for the put-back
		local companion = Companion(frame)
		if companion then
			MelloUI:FitOnScreen(frame, companion)
		end
		mover.moving = nil
		SizeTip.Release(mover)
	end
	-- a registered window's place is Core's (its show, the UI Scale): the
	-- put-back hooks are for the game's windows only
	if not entry then
		Perf.HookScript(frame, "OnShow", function()
			PutBack(frame)
		end)
		-- whoever re-anchors the window (the panel manager on show, the bag
		-- layout, a page's own code), it goes back where it was put — right
		-- after that SetPoint, never during a drag or our own placing
		hooksecurefunc(frame, "SetPoint", function()
			if mover.moving or mover.placing then
				return
			end
			if SavedPosition(frame) then
				mover.placing = true
				PutBack(frame)
				mover.placing = nil
			end
		end)
		if frame.SetScale then
			hooksecurefunc(frame, "SetScale", function()
				if mover.moving or mover.placing or mover.scaling then
					return
				end
				-- someone else scaled it (Edit Mode's Size, the panel manager's
				-- fit): that is the game's scale for it, the size readout's 100 %
				if not mover.entry then
					mover.base = SizeTip.Scale(frame) or mover.base
				end
				local pos = SavedPosition(frame)
				if pos and pos.scale then
					mover.placing = true
					PutBack(frame)
					mover.placing = nil
				end
			end)
		end
	end
	mover.SetUnlocked = function(on)
		mover.unlocked = on and true or false
		-- (what each handle switches with it: HANDLE_SWITCHES)
		for h, switches in pairs(mover.handles) do
			if switches.mouse then
				h:EnableMouse(mover.unlocked)
			end
			if switches.wheel then
				h:EnableMouseWheel(mover.unlocked)
			end
		end
		for _, wash in ipairs(mover.washes) do
			wash:SetShown(mover.unlocked)
		end
		if not mover.unlocked then
			SizeTip.Release(mover, 0)
		end
	end
	AddHandle(mover, handle, entry)
	mover.SetUnlocked(M.isEnabled and M.db and M.db.unlock)
	PutBack(frame)
end

-- What a grab area looks like while the windows are unlocked: a gold wash
-- inside a thin gold edge, both brighter while the mouse is on it. The
-- textures are made once and shown with the unlocked state. A handle that
-- is the whole window (a registered window dragged by itself: the Voice Over
-- overlay, the Route arrow) gets the edge alone: a wash over a whole window
-- is what was taken away on 2026-09-21 (review, 2026-09-25).
local function HandleWash(mover, handle)
	local fill
	if handle ~= mover.frame then
		fill = handle:CreateTexture(nil, "OVERLAY", nil, 7)
		fill:SetAllPoints(handle)
		fill:SetColorTexture(1, 0.82, 0, WASH)
	end
	local edges = {}
	local function Edge(a, b, w, h)
		local t = handle:CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetColorTexture(1, 0.82, 0, EDGE)
		t:SetPoint(a, handle, a)
		t:SetPoint(b, handle, b)
		if w then
			t:SetWidth(w)
		end
		if h then
			t:SetHeight(h)
		end
		edges[#edges + 1] = t
	end
	Edge("TOPLEFT", "TOPRIGHT", nil, 1)
	Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
	Edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
	Edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
	local function Lit(on)
		if fill then
			fill:SetColorTexture(1, 0.82, 0, on and WASH_LIT or WASH)
		end
		for _, edge in ipairs(edges) do
			edge:SetColorTexture(1, 0.82, 0, on and EDGE_LIT or EDGE)
		end
	end
	-- hooked, not set: a handle that is a kit plate has its own scripts
	-- ... and the size readout while the mouse is on it, for a window that
	-- is not at its standard size (user, 2026-09-24)
	pcall(handle.HookScript, handle, "OnEnter", function()
		Lit(mover.unlocked)
		if mover.unlocked and not mover.moving then
			SizeTip.Show(mover, true)
		end
	end)
	pcall(handle.HookScript, handle, "OnLeave", function()
		SizeTip.Release(mover, 0)
		Lit(false)
	end)
	if fill then
		fill:Hide()
		mover.washes[#mover.washes + 1] = fill
	end
	for _, edge in ipairs(edges) do
		edge:Hide()
		mover.washes[#mover.washes + 1] = edge
	end
end

-- What a handle switches with the unlocked state (mover.handles[handle]):
-- a grab of this module's takes the mouse and the wheel only while
-- unlocked. A registered window's handle keeps the mouse when it was
-- registered to be dragged at any time (KeepsMouse), and keeps the wheel
-- when it has one of its own.
local HANDLE_SWITCHES = {
	both = { mouse = true, wheel = true },
	mouse = { mouse = true },
	wheel = { wheel = true },
	none = {},
}

-- Whether a registered window's handle keeps its mouse: registered to be
-- dragged at any time (plainDrag "always": Core turned its mouse on, and its
-- clicks and tooltip live there). Read once, when Core first tells the
-- provider of the entry -- at its registration, as the provider is set from
-- this file's load on (below) -- and kept: a window may change its entry's
-- plainDrag later (Voice Over's padlock), and read then, the whole overlay
-- lost its mouse while the windows were locked (review, 2026-09-25).
local KeepsMouse
do
	local keeps = setmetatable({}, { __mode = "k" })
	KeepsMouse = function(entry)
		local keep = keeps[entry]
		if keep == nil then
			keep = entry.plainDrag == "always"
			keeps[entry] = keep
		end
		return keep
	end
end

-- the wheel on a handle while its window is not dragged: the window's (a
-- chat frame scrolls on it — user, 2026-09-22: could not scroll the chat
-- while unlocked)
local function WheelToWindow(target, delta)
	local script = target and target.GetScript and target:GetScript("OnMouseWheel")
	if script then
		pcall(script, target, delta)
	end
end

-- A drag handle of a mover: the drag and wheel scripts on it, the mouse
-- only while unlocked. `entry`: the handle a window registered with Core
-- (MelloUI:RegisterMover): its OnDragStart / OnDragStop are Core's, which
-- hooks them and asks the provider first, so nothing is set on it; the
-- wheel is hooked (the scale while it is dragged; otherwise handed to the
-- window when the handle has no wheel of its own).
AddHandle = function(mover, handle, entry)
	if not (handle and handle.EnableMouse and handle.SetScript) or mover.handles[handle] then
		return
	end
	handle:RegisterForDrag("LeftButton")
	if entry then
		local ownWheel = handle:GetScript("OnMouseWheel") ~= nil
		if KeepsMouse(entry) then
			mover.handles[handle] = ownWheel and HANDLE_SWITCHES.none or HANDLE_SWITCHES.wheel
		else
			mover.handles[handle] = ownWheel and HANDLE_SWITCHES.mouse or HANDLE_SWITCHES.both
		end
		-- (a handle that is the window itself hands nothing on: to itself)
		local target = not ownWheel and handle ~= mover.frame and mover.frame or nil
		Perf.HookScript(handle, "OnMouseWheel", function(_, delta)
			if mover.moving then
				mover.Wheel(delta)
			elseif target then
				WheelToWindow(target, delta)
			end
		end)
	else
		mover.handles[handle] = HANDLE_SWITCHES.both
		Perf.SetScript(handle, "OnMouseWheel", function(_, delta)
			if mover.moving then
				mover.Wheel(delta)
				return
			end
			WheelToWindow(mover.frame, delta)
		end)
		Perf.SetScript(handle, "OnDragStart", mover.DragStart)
		Perf.SetScript(handle, "OnDragStop", mover.DragStop)
	end
	HandleWash(mover, handle)
	local on = mover.unlocked and true or false
	local switches = mover.handles[handle]
	if switches.mouse then
		handle:EnableMouse(on)
	end
	if switches.wheel then
		handle:EnableMouseWheel(on)
	end
	for _, wash in ipairs(mover.washes) do
		wash:SetShown(on)
	end
end

--------------------------------------------------------------------------------
-- Plain windows (user, 2026-09-22): the mover works with the reskin off.
-- Every window the kit dresses, the interaction windows and the HUD elements
-- get a grab area of their own whether or not a kit panel is on: an
-- invisible frame over the game's title strip (the HUD's band / header /
-- body), mouse-enabled only while unlocked. A kit shell registered for the
-- same window adds its lit rail and its plate as a second handle. Windows
-- loaded on demand are picked up when the game lays its panels out.
--------------------------------------------------------------------------------

-- The windows with a plain grab: the frames a module's `window` names with
-- `plainGrab` (the windows dressed on their first show got their mover only
-- from the kit's shell before, so theirs is plain from login like the
-- others -- user, 2026-09-24), then the windows no module registers: the
-- configurator (Core/Config.lua is not a module). Made by Lists; the order
-- is of no account (each window's grab is its own).
local PLAIN_WINDOWS = {}
local LOOSE_WINDOWS = { "MelloUIConfigFrame" }

-- The lists made from the registry (PANELS and TWEAKS: see the top), the
-- switches' defaults and their rows on the page, once: at the addon's own
-- ADDON_LOADED, when every module is in (the sweep's event, below), so the
-- defaults are complete before Core reads the saved settings against them
-- at login; OnInit makes sure of it. The registry does not change after.
local listed = false
local TAB_RANK = { Windows = 1, HUD = 2 }

local function InOrder(entries, into)
	table.sort(entries, function(a, b)
		if a.tab ~= b.tab then
			return a.tab < b.tab
		elseif a.order ~= b.order then
			return a.order < b.order
		end
		return a.at < b.at
	end)
	for i, entry in ipairs(entries) do
		into[i] = entry.row
	end
end

local function Lists()
	if listed then
		return
	end
	listed = true
	local panels, tweaks = {}, {}
	for at, module in ipairs(MelloUI:ModulesInOrder()) do
		local w, t = module.window, module.tweak
		if w and w.label then
			panels[#panels + 1] = { at = at, tab = TAB_RANK[w.tab] or 3, order = type(w.order) == "number" and w.order or math.huge,
				row = { w.switch or module.name, w.label, w.desc or "", tab = w.tab, setting = w.switch and true or nil } }
		end
		if w and w.plainGrab and type(w.frames) == "table" then
			for _, name in ipairs(w.frames) do
				PLAIN_WINDOWS[#PLAIN_WINDOWS + 1] = name
			end
		end
		if t and t.label then
			tweaks[#tweaks + 1] = { at = at, tab = 0, order = type(t.order) == "number" and t.order or math.huge,
				row = { module.name, t.label, t.desc or "", off = t.off and true or nil, always = t.always and true or nil } }
		end
	end
	InOrder(panels, PANELS)
	InOrder(tweaks, TWEAKS)
	for _, name in ipairs(LOOSE_WINDOWS) do
		PLAIN_WINDOWS[#PLAIN_WINDOWS + 1] = name
	end
	for _, area in ipairs(PANELS) do
		defaults[area[1]] = true
	end
	for _, tweak in ipairs(TWEAKS) do
		if not tweak.off then
			defaults["qol_" .. tweak[1]] = true
		end
	end
	-- the page's slots filled in their places (the same table the
	-- configurator was given)
	local page = {}
	for i = #options, 1, -1 do
		page[i] = options[i]
		options[i] = nil
	end
	for _, opt in ipairs(page) do
		if opt.slot then
			opt.slot()
		else
			Add(opt)
		end
	end
end

-- HUD elements: the frame, the region its grab covers, a control to stop
-- short of, and how the grab sits on the region ("strip" = the top edge only)
local PLAIN_HUD = {
	{ "MinimapCluster", function(f) return f.BorderTop or f end },
	{ "ObjectiveTrackerFrame", function(f) return f.Header or f end, function(f) return f.Header and f.Header.MinimizeButton end },
	-- the damage meter is dragged by its HEADER, not by its list (user,
	-- 2026-09-22: "the damage meter should be dragable by the windows
	-- header, not the Bar"). The header's controls sit at both ends of the
	-- band -- the timer and the type dropdown on the left, the session
	-- dropdown, the cog and the minimize button on the right -- so the grab
	-- is the span BETWEEN them, over the title, and every control keeps its
	-- clicks (2026-09-21).
	{ "DamageMeter", function(f)
		local win = f.GetPrimarySessionWindow and f:GetPrimarySessionWindow()
		return win and win.Header or nil
	end, function(f)
		local win = f.GetPrimarySessionWindow and f:GetPrimarySessionWindow()
		if not win then
			return nil
		end
		return { left = win.DamageMeterTypeDropdown or win.SessionTimer,
			right = win.SessionDropdown or win.SettingsDropdown or win.MinimizeButton }
	end, "between" },
}
local plainGrabs = {}   -- [frame] = grab

local function PlainGrab(frame, region, avoid, avoidSide)
	local grab = CreateFrame("Frame", nil, frame)
	if avoidSide == "between" and type(avoid) == "table" then
		-- the span between two controls, over the region's full height: a
		-- header band whose ends are buttons is grabbed in the middle
		local band = region or frame
		grab:SetPoint("TOP", band, "TOP")
		grab:SetPoint("BOTTOM", band, "BOTTOM")
		grab:SetPoint("LEFT", avoid.left or band, avoid.left and "RIGHT" or "LEFT", avoid.left and 2 or 0, 0)
		grab:SetPoint("RIGHT", avoid.right or band, avoid.right and "LEFT" or "RIGHT", avoid.right and -2 or 0, 0)
	elseif avoidSide == "strip" then
		-- a strip along the top edge and nothing more: a grab over a whole
		-- window body takes every click and wheel turn under it while the
		-- windows are unlocked, and a chat window's links, scroll buttons and
		-- wheel die with it (user, 2026-09-22; the wheel alone was forwarded
		-- once before, the clicks could not be)
		grab:SetPoint("TOPLEFT", region or frame, "TOPLEFT")
		grab:SetPoint("TOPRIGHT", region or frame, "TOPRIGHT")
		grab:SetHeight(STRIP)
	elseif region and region ~= frame or (region == frame and avoid) then
		grab:SetAllPoints(region)
		if avoid then
			-- a button on the region keeps its clicks while unlocked: the
			-- grab stops short of it — at its left edge (the tracker's
			-- minimize, at the header's right end) or above its top (the
			-- chat's scroll arrow, in the bottom-right corner: the bottom
			-- strip is left out) — user, 2026-09-22
			grab:ClearAllPoints()
			if avoidSide == "bottom" then
				grab:SetPoint("TOPLEFT", region, "TOPLEFT")
				grab:SetPoint("BOTTOMRIGHT", avoid, "TOPRIGHT", 0, 2)   -- no edge set twice
			else
				grab:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT")
				grab:SetPoint("TOPRIGHT", avoid, "TOPLEFT", -2, 0)
			end
		end
	elseif frame.TitleContainer then
		grab:SetAllPoints(frame.TitleContainer)   -- the game's title strip, short of the close button
	elseif region == frame then
		grab:SetAllPoints(frame)
	else
		grab:SetPoint("TOPLEFT", frame, "TOPLEFT", 60, 0)
		grab:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -28, -24)
	end
	grab:SetFrameLevel((frame:GetFrameLevel() or 1) + 10)
	grab:EnableMouse(false)
	plainGrabs[frame] = grab
	return grab
end

-- (the sweep runs on every panel shown or hidden: user, 2026-09-24 -- the
-- functions and names it made on each run are made once here)
local function AttachPlain(frame, region, avoid, avoidSide)
	if type(frame) == "table" and type(frame.GetObjectType) == "function" and not plainGrabs[frame]
		and not (frame.IsForbidden and frame:IsForbidden()) then
		local ok, grab = pcall(PlainGrab, frame, region, avoid, avoidSide)
		if ok and grab then
			MakeMover(frame, { title = grab })
		end
	end
end
local function NoAvoid()
	return nil
end
local CHAT_FRAMES = {}
for i = 1, (NUM_CHAT_WINDOWS or 10) do
	CHAT_FRAMES[i] = "ChatFrame" .. i
end

local function SweepPlain()
	if not M.isEnabled then
		return
	end
	for _, name in ipairs(PLAIN_WINDOWS) do
		AttachPlain(_G[name], nil)
	end
	for _, entry in ipairs(PLAIN_HUD) do
		local frame = _G[entry[1]]
		if frame and not plainGrabs[frame] then   -- (its region and controls looked up only until it has its grab)
			local ok, region = pcall(entry[2], frame)
			local okA, avoid = pcall(entry[3] or NoAvoid, frame)
			if ok and region then
				AttachPlain(frame, region, okA and avoid or nil, entry[4])
			end
		end
	end
	for _, name in ipairs(CHAT_FRAMES) do
		local frame = _G[name]
		if frame then
			AttachPlain(frame, frame, nil, "strip")   -- a chat window is grabbed by a strip along its top edge; the messages under it keep their links, buttons and wheel
		end
	end
end

local sweepFrame = CreateFrame("Frame")
sweepFrame:RegisterEvent("ADDON_LOADED")
sweepFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
Perf.SetScript(sweepFrame, "OnEvent", function(_, event, addon)
	if event == "ADDON_LOADED" and addon == MelloUI.name then
		Lists()   -- every file of the addon has run: every module is in
	end
	SweepPlain()
end)

--------------------------------------------------------------------------------
-- The unlocked state has to say so (user, 2026-09-22): it is kept across
-- sessions, nothing on screen showed it, and the grab areas take the mouse
-- while it is on -- a UI that quietly stops answering the mouse in places.
-- A plate at the top of the screen names the state and locks again when it
-- is clicked.
--------------------------------------------------------------------------------

local ApplyUnlock   -- below
local banner

local function UnlockBanner(on)
	if not on then
		if banner then
			banner:Hide()
		end
		return
	end
	if not banner then
		banner = CreateFrame("Button", "MelloUIUnlockedNotice", UIParent)
		banner:SetSize(420, 32)
		banner:SetPoint("TOP", UIParent, "TOP", 0, -150)
		banner:SetFrameStrata("DIALOG")
		banner:SetClampedToScreen(true)
		local back = banner:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints(banner)
		back:SetColorTexture(0, 0, 0, 0.75)
		-- drawn from plain textures, never a backdrop: this sits over the HUD
		local function Line(a, b, w, h)
			local t = banner:CreateTexture(nil, "BORDER")
			t:SetColorTexture(1, 0.82, 0, 0.5)
			t:SetPoint(a, banner, a)
			t:SetPoint(b, banner, b)
			if w then
				t:SetWidth(w)
			end
			if h then
				t:SetHeight(h)
			end
		end
		Line("TOPLEFT", "TOPRIGHT", nil, 1)
		Line("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
		Line("TOPLEFT", "BOTTOMLEFT", 1, nil)
		Line("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
		local text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		text:SetPoint("CENTER", banner, "CENTER", 0, 0)
		text:SetText("Windows unlocked: drag a gold band, wheel to scale.  |cffffd200Click here to lock them|r")
		Perf.SetScript(banner, "OnClick", function()
			-- the setting itself is changed, so the configurator's toggle and
			-- the grabs follow through OnSettingChanged
			MelloUI:NotifySettingChanged(M.name, "unlock", false)
			if MelloUI.RefreshConfig then
				MelloUI:RefreshConfig()
			end
			MelloUI:Print("Windows locked.")
		end)
	end
	banner:Show()
end

local function Unlocked()
	return (M.isEnabled and M.db and M.db.unlock) and true or false
end

-- A window registered with Core gets its mover (its grab's edge, its hooks)
-- on the first need -- the windows unlocked, or registered while they are --
-- never at its registration while they are locked: the Route arrow and the
-- Voice Over overlay are made at login, and a mover for each was new work
-- there (WINDOW-RULES 2f; review, 2026-09-25). Until then its handle is as
-- a locked mover leaves it (LetGo, the provider's Attach). A window that has
-- a grab here already takes the entry into that one mover.
local function EntryMover(entry)
	local frame = entry.frame
	local mover = movers[frame]
	if not (mover and mover.entry == entry) then
		-- (one window's failure does not stop the others: said, as the save's)
		local ok, err = pcall(MakeMover, frame, { title = entry.handle, entry = entry })
		if not ok then
			MelloUI:Notice("UI Modifications: %s", tostring(err))
		end
		mover = movers[frame]
	end
	return (mover and mover.entry == entry) and mover or nil
end

ApplyUnlock = function(on)
	if on and M.isEnabled and MelloUI.MoverEntries then
		local entries = MelloUI:MoverEntries()
		for i = 1, #entries do
			EntryMover(entries[i])
		end
	end
	for _, mover in pairs(movers) do
		mover.SetUnlocked(on)
	end
	UnlockBanner(on and M.isEnabled and true or false)
end

-- Reset positions (the header button): the saved places and scales are
-- forgotten, every moved window goes back to its standard scale (the game's
-- own for it, the size readout's 100 % -- 1 for most; user, 2026-09-24) and,
-- if open, is closed so the game lays it out afresh on its next show. Every
-- window registered with Core goes back too (audit, 2026-09-24, rank 6: the
-- reset reached only the game's windows and the Quest Tracker), dragged here
-- or by Core alone: a saved scale taken off, its place forgotten, then its
-- own reset and default (MelloUI:ResetMover). In one Batch: one change of
-- the positions on the bus and one backup, however many windows went back.
local function ResetAll()
	local positions = M.db.positions or {}
	for frame, mover in pairs(movers) do
		local name = not mover.entry and frame.GetName and frame:GetName()
		if name and positions[name] then
			mover.placing = true
			pcall(function()
				if frame.SetScale then
					mover.scaling = true
					Raw(frame, "SetScale")(frame, SizeTip.Base(mover))
					mover.scaling = nil
				end
				if frame:IsShown() then
					Raw(frame, "Hide")(frame)
				end
			end)
			mover.placing = nil
		end
	end
	local entries = MelloUI:MoverEntries()
	for i = 1, #entries do
		local entry = entries[i]
		local frame = entry.frame
		local pos = not entry.save and MelloUI:GetPosition(entry.key)
		if pos and pos.scale and frame.SetScale and not Locked(frame) then
			pcall(ScaleFrame, frame, SizeTip.EntryBase(entry))
		end
		MelloUI:ResetMover(entry)
	end
	M.db.positions = {}
	MelloUI:NotifySettingChanged(M.name, "positions", M.db.positions)
end

local function ResetPositions()
	if not M.db then
		return
	end
	MelloUI:Batch(ResetAll)
	MelloUI:Print("UI Modifications: window positions and scales reset.")
end
M.ResetPositions = ResetPositions

--------------------------------------------------------------------------------
-- The provider of Core's mover (audit, 2026-09-24, rank 6). Every window
-- registered with MelloUI:RegisterMover -- the Quest Tracker, and MelloUI's
-- other own windows as they register -- gets the drag the windows here get
-- while they are unlocked (user, 2026-09-23: the All Objectives tracker
-- "does not have the same darkening ... also the mousewheel does not
-- increase its scale"): the darkened screen with its grid, the lit snap
-- lines and the corner's snap, the glow, the wheel's scale with the size
-- plate and its stop at 100 %, and its place saved on the drop (SaveEntry).
-- Core keeps the registration, the handle's drag scripts and the saved
-- places, and asks here first at each drag start. Set from this file's load
-- on (below); with the module off it takes no drag and says the windows are
-- locked, so Core's plain drag is all there is.
--------------------------------------------------------------------------------
local Provider = {}

-- a registered window's handle with no mover made for it yet, as a locked
-- mover leaves it: a handle whose mouse is the provider's (the Quest
-- Tracker's header) lets the mouse go, so its strip does not take the
-- clicks meant for the world under it -- the module on or off, as when the
-- mover was made at once (review, 2026-09-25)
local function LetGo(entry)
	local handle = entry.handle
	if KeepsMouse(entry) or type(handle) ~= "table" or not (handle.EnableMouse and handle.GetScript) then
		return
	end
	handle:EnableMouse(false)
	if handle.EnableMouseWheel and handle:GetScript("OnMouseWheel") == nil then
		handle:EnableMouseWheel(false)
	end
end

-- told of every entry, at its registration (and again should the provider
-- be set again): its mover when the windows are unlocked or the window has
-- a grab here, else its handle let go; a mover already made only follows
-- the state
function Provider:Attach(entry)
	KeepsMouse(entry)   -- (its mode as registered, noted now)
	if movers[entry.frame] or Unlocked() then
		local mover = EntryMover(entry)
		if mover then
			mover.SetUnlocked(Unlocked())
		end
	else
		LetGo(entry)
	end
end

-- true takes the drag: while the windows are unlocked, out of combat for a
-- protected window
function Provider:DragStart(entry)
	if not Unlocked() then
		return false
	end
	local mover = EntryMover(entry)
	if mover then
		return mover.DragStart()
	end
	return false
end

-- the drop, or the window hidden while it was dragged (Core's OnHide)
function Provider:DragStop(entry)
	local mover = movers[entry.frame]
	if mover and mover.entry == entry then
		mover.DragStop()
	end
end

function Provider:IsUnlocked()
	return Unlocked()
end

-- Set once, from the load on, the module on or off (review, 2026-09-25):
-- each window is then told to the provider at its registration, before it
-- can change its entry (KeepsMouse), and the Quest Tracker's header is let
-- go of the mouse with the module off as well. Off, the provider answers
-- as if there were none (no drag taken, the windows locked).
if MelloUI.SetMoverProvider then
	MelloUI:SetMoverProvider(Provider)
end

local Kit = MelloUI.Kit
if Kit and Kit.OnShell then
	Kit:OnShell(function(frame, shell)
		MakeMover(frame, shell)
	end)
end

-- The UI Scale or the resolution changed (user, 2026-09-24: "UI Scaling
-- Break the UI"): every open window with a saved place is put back, so it is
-- kept on the new screen (PutBack's FitOnScreen); a protected one in combat
-- waits for the fight's end as always. A closed window is put back when it
-- next opens. The drag grid redraws itself on the next drag. The windows
-- registered with Core are put back by Core, UI Modifications on or off.
if Kit and Kit.OnUIScaleChanged then
	Kit:OnUIScaleChanged(function(reason)
		if reason ~= "uiscale" or not M.isEnabled then
			return
		end
		for frame, mover in pairs(movers) do
			local ok, shown = pcall(frame.IsShown, frame)
			if ok and shown and not mover.moving and not mover.entry and SavedPosition(frame) then
				PutBack(frame)
			end
		end
	end)
end

-- Windows Fade In (user, 2026-09-23: "can we do that effect with all of the
-- UI elements that open, the character tab, backpack, talents, professions
-- tab etc?"): every window the game opens as a panel -- the ones it lists in
-- UIPanelWindows: character, talents and spells, professions, social, guild,
-- group finder, collections, map, game menu ... -- and every bag window fades
-- in when it opens, reskin on or off (Core/Anim.lua). Windows of addons the
-- game loads on demand join that list when they load, so the sweep runs again
-- on every ADDON_LOADED, before such a window's first show. Only the window's
-- alpha is touched, which the game allows on any window, in combat too; the
-- hooks are post-hooks and nothing is written onto the windows.
local fadeHooked = setmetatable({}, { __mode = "k" })
local EXTRA_WINDOWS = { "ContainerFrameCombinedBags", "BankFrame", "SettingsPanel", "AddonList" }
for i = 1, 13 do
	EXTRA_WINDOWS[#EXTRA_WINDOWS + 1] = "ContainerFrame" .. i
end

local function FadeOnShow(self)
	if M.isEnabled and M.db and M.db.fadeWindows and MelloUI.Anim
		and not (self.IsForbidden and self:IsForbidden()) then
		MelloUI.Anim:FadeIn(self, 0.2)
	end
end

local function HookFade(frame)
	if type(frame) ~= "table" or fadeHooked[frame] or not frame.HookScript then
		return
	end
	if frame.IsForbidden and frame:IsForbidden() then
		return
	end
	fadeHooked[frame] = true
	Perf.HookScript(frame, "OnShow", FadeOnShow)
end

local function SweepFade()
	if type(UIPanelWindows) == "table" then
		for name in pairs(UIPanelWindows) do
			if type(name) == "string" then
				HookFade(_G[name])
			end
		end
	end
	for _, name in ipairs(EXTRA_WINDOWS) do
		HookFade(_G[name])
	end
end

local fadeWatcher = CreateFrame("Frame")
fadeWatcher:RegisterEvent("PLAYER_LOGIN")
fadeWatcher:RegisterEvent("ADDON_LOADED")
Perf.SetScript(fadeWatcher, "OnEvent", SweepFade)

-- the plain grabs first, so the kit's plate is the second handle and the
-- plain one stays when the kit goes off
-- the game lays its panels out again on every show / hide of one, and the
-- bags on every open (UpdateContainerFrameAnchors — the backpack went back
-- to its default place after a reload, user 2026-09-21): ours go back where
-- they were put after each of those
local function PutBackShown()
	SweepPlain()   -- a window loaded on demand gets its grab here
	for frame in pairs(movers) do
		if frame:IsShown() then
			PutBack(frame)
		end
	end
end
for _, fn in ipairs({ "UpdateUIPanelPositions", "UpdateContainerFrameAnchors" }) do
	if type(_G[fn]) == "function" then
		hooksecurefunc(fn, PutBackShown)
	end
end

local function PanelWanted(db, name)
	return db.reskin ~= false and db[name] ~= false
end

-- During Core's start-up pass the driven modules must come up in TOC order
-- (Bar Textures before the unit frame panel, and so on): only their flags
-- are set then, and Core enables each in its turn; afterwards (a switch on
-- the page) they are switched at once.
local function Want(name, wanted)
	if MelloUI.initializingModules then
		MelloUI.db.enabled[name] = wanted and true or false
	else
		MelloUI:SetModuleEnabled(name, wanted)
	end
end

-- A folded feature's switch: on unless switched off (`off`: off unless
-- switched on; `always`: no switch)
function TweakWanted(db, tweak)
	if tweak.always then
		return true
	end
	local v = db["qol_" .. tweak[1]]
	if tweak.off then
		return v == true
	end
	return v ~= false
end

-- Is there anything at all for the umbrella to do? Every area and every
-- tweak switched off is a real choice (the window mover and the name format
-- work without the reskin), so it is never undone behind your back -- but it
-- is worth saying, because the switch then looks like it does nothing.
function NothingWanted(db)
	for _, area in ipairs(PANELS) do
		if db[area[1]] ~= false then
			return false
		end
	end
	for _, tweak in ipairs(TWEAKS) do
		if not tweak.always and TweakWanted(db, tweak) then
			return false
		end
	end
	return true
end

-- Put every area and tweak back on, for the button on the page. Returns how
-- many were off.
function RestoreAreas(db)
	local count = 0
	local function put(key)
		if db[key] == false then
			db[key] = true
			count = count + 1
			MelloUI:NotifySettingChanged(M.name, key, true)
		end
	end
	for _, area in ipairs(PANELS) do
		put(area[1])
	end
	for _, tweak in ipairs(TWEAKS) do
		if not (tweak.off or tweak.always) then
			put("qol_" .. tweak[1])
		end
	end
	return count
end

function Apply(db, on)
	local wanted = {}
	for _, area in ipairs(PANELS) do
		local name = area[1]
		if MelloUI:GetModule(name) then
			wanted[name] = on and PanelWanted(db, name) or false
		end
	end
	for _, tweak in ipairs(TWEAKS) do
		local name = tweak[1]
		if MelloUI:GetModule(name) then
			wanted[name] = on and TweakWanted(db, tweak) or false
		end
	end
	-- in TOC order on every path (Bar Textures before the unit frame panel
	-- when the umbrella is switched on from its tile as well, not only in
	-- Core's start-up pass; audit, 2026-09-22)
	for name in MelloUI:IterateModules() do
		if wanted[name] ~= nil then
			Want(name, wanted[name])
		end
	end
end

-- The driven modules are hidden from the configurator; done once every
-- module is registered (this file loads before them, see the TOC).
function M:OnInit()
	Lists()   -- (made at the addon's ADDON_LOADED already)
	for _, area in ipairs(PANELS) do
		local module = MelloUI:GetModule(area[1])
		if module then
			module.hidden = true
		end
	end
	for _, tweak in ipairs(TWEAKS) do
		local module = MelloUI:GetModule(tweak[1])
		if module then
			module.hidden = true
		end
	end
end

-- The name form to the two modules and the engine's own-name cvar.
local SURNAME_CVAR = "UnitSurnameOwn"

local function HasCVar(name)
	if not (C_CVar and C_CVar.GetCVarInfo) then
		return false
	end
	local ok, value = pcall(C_CVar.GetCVarInfo, name)
	return ok and value ~= nil
end

local function ApplyNameFormat(db, on)
	local mode = on and (db.nameFormat or "both") or "both"
	for _, name in ipairs({ "UnitFrames", "Nameplates" }) do
		local module = MelloUI:GetModule(name)
		if module then
			MelloUI:NotifySettingChanged(name, "nameFormat", mode)
		end
	end
	if HasCVar(SURNAME_CVAR) then
		if on then
			if db.savedSurnameOwn == nil then
				local ok, current = pcall(C_CVar.GetCVar, SURNAME_CVAR)
				db.savedSurnameOwn = (ok and current) and tostring(current) or "1"
			end
			pcall(C_CVar.SetCVar, SURNAME_CVAR, mode == "first" and "0" or "1")
		elseif db.savedSurnameOwn ~= nil then
			pcall(C_CVar.SetCVar, SURNAME_CVAR, db.savedSurnameOwn)
			db.savedSurnameOwn = nil
		end
	end
end

-- Preload Artwork (Kit:Preload): the kit's files while the reskin is on, the
-- class medallions with them; all let go when either is off or the module is.
local function ApplyPreload(db, on)
	if not (Kit and Kit.Preload) then
		return
	end
	local files = {}
	if on and db.preloadArt ~= false and db.reskin ~= false then
		files = Kit:KitFiles()
		local function Walk(t)
			for _, v in pairs(t) do
				if type(v) == "string" then
					files[#files + 1] = v
				elseif type(v) == "table" then
					Walk(v)
				end
			end
		end
		if type(MelloUI_ClassIcons) == "table" then
			Walk(MelloUI_ClassIcons)
		end
	end
	Kit:Preload(files)
end

-- The reskin switched on by the user (the umbrella from its tile or the
-- reskin toggle; not Core's start-up pass): Custom Sounds comes on with it,
-- and the Edit Mode layout the reskin is drawn for is put in place once
-- (user, 2026-09-22: "if people enable the reskin, it should only auto
-- enable the full reskin and the custom sounds, but it needs to load my
-- current UI layout").
local function ReskinOn(db)
	if MelloUI.initializingModules or not MelloUI.initialized or not db.reskin then
		return
	end
	if MelloUI:GetModule("CustomSounds") and not MelloUI:IsModuleEnabled("CustomSounds") then
		MelloUI:SetModuleEnabled("CustomSounds", true)
		MelloUI:Print("Custom Sounds switched on with the reskin.")
	end
	if not db.layoutApplied and MelloUI.ApplyEditModeLayout then
		local ok, why = MelloUI:ApplyEditModeLayout()
		if ok then
			db.layoutApplied = true
			MelloUI:NotifySettingChanged(M.name, "layoutApplied", true)
		elseif why and not why:find("no layout is baked", 1, true) then
			MelloUI:Print("Edit Mode layout: %s", why)
		end
	end
	if MelloUI.RefreshConfig then
		MelloUI:RefreshConfig()
	end
end

-- Reduce Motion: the animation engine finishes every tween and group at once.
-- An accessibility switch for the whole addon, not part of the reskin: it
-- follows the saved setting with this module on or off (Chat's smooth scroll
-- reads it, and the Fresh start profile turns this module off; audit,
-- 2026-09-24). Read at start-up (OnEnable, or OnDisable for a module that is
-- off), on a change and after a profile load; the switch stays on this page.
local function ApplyMotion(db)
	if MelloUI.Anim and db then
		MelloUI.Anim:SetReduceMotion(db.reduceMotion)
	end
end
-- a change reaches OnSettingChanged, and a profile load OnEnable, only while
-- the module is on: the bus's 'setting' and 'restart' (fired at the end of
-- NotifySettingChanged and RestartModules, where the hooks on them ran;
-- audit, 2026-09-24, rank 5) reach it with the module off as well
MelloUI:On("setting", Perf.Shared("'setting' on the bus", function(name, key)
	if name == "UIModifications" and key == "reduceMotion" then
		ApplyMotion(MelloUI:GetModuleDB("UIModifications"))
	end
end), M)
MelloUI:On("restart", Perf.Shared("'restart' on the bus", function()
	ApplyMotion(MelloUI:GetModuleDB("UIModifications"))
end), M)

function M:OnEnable(db)
	self.db = db
	-- the borders moved here from the panels (one choice per kind for every
	-- window, 2026-09-23): the action bars' Button Border and the character
	-- window's progress bar look carry over, once
	if not db.bordersMigrated then
		local ab = MelloUI:GetModuleDB("ActionBarPanel")
		if ab and ab.buttonBorder then
			db.buttonBorder = ab.buttonBorder
		end
		local cp = MelloUI:GetModuleDB("CharacterPanel")
		if cp and cp.repBarBorder then
			db.barBorder = cp.repBarBorder
		end
		db.bordersMigrated = true
	end
	-- Buffs & Debuffs and Error Messages moved here from pages of their own,
	-- and Tweaks lost its switch (its rows each switch one thing; user,
	-- 2026-09-24): each keeps the state it had, once
	if not db.featuresFolded then
		for _, tweak in ipairs(TWEAKS) do
			local key = "qol_" .. tweak[1]
			if tweak.off and db[key] == nil then
				db[key] = MelloUI.db.enabled[tweak[1]] == true
			end
		end
		if db.qol_Tweaks == false then
			local tw = MelloUI:GetModuleDB("Tweaks")
			if tw then
				tw.hideMicroMenu, tw.hideBagBar, tw.hideMinimapCoords, tw.chatNotices = false, false, false, false
				tw.worldTextScale = 1
			end
		end
		db.qol_Tweaks = nil
		db.featuresFolded = true
	end
	-- MelloUI's Quest Tracker has a kit switch of its own now (audit,
	-- 2026-09-24, rank 1); it wore the kit with the Objective tracker's until
	-- then, so it starts as that one is set, once, and no look changes. The
	-- flag is not a kept key but travels with the settings: loading a
	-- profile saved before it clears it, and the restart after the load
	-- takes that profile over the same way; one saved after carries both.
	if not db.questTrackerKitMigrated then
		db.questTrackerKit = db.TrackerPanel ~= false
		db.questTrackerKitMigrated = true
	end
	ApplyMotion(db)
	if db.reskin ~= false and NothingWanted(db) then
		MelloUI:Notice("UI Modifications is on, but every area of the reskin is switched off, so the game's own art is what you see. Its page has a \"Switch every area on\" button.")
	end
	Apply(db, true)
	SweepPlain()
	-- (the windows registered with Core are dragged the way the windows here
	-- are while the module is on: the provider, above, answers again, and
	-- their movers are made here when the windows are unlocked)
	ApplyUnlock(db.unlock)
	for frame in pairs(movers) do
		PutBack(frame)
	end
	ApplyNameFormat(db, true)
	ApplyPreload(db, true)
	ReskinOn(db)
end

function M:OnDisable(db)
	db = db or self.db or {}
	ApplyMotion(db)   -- kept: Reduce Motion is not the module's
	Apply(db, false)
	-- a drag of this module's still under way is let go where it is (the
	-- veil off, the place saved); the registered windows are back to Core's
	-- plain drag (the provider takes no drag while the module is off)
	for _, mover in pairs(movers) do
		if mover.moving then
			pcall(mover.DragStop)
		end
	end
	ApplyUnlock(false)
	ApplyNameFormat(db, false)
	ApplyPreload(db, false)
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "unlock" then
		ApplyUnlock(value)
		return
	elseif key == "reduceMotion" then
		return   -- applied from the bus's 'setting', module on or off
	elseif key == "questTrackerKit" or key == "questTrackerKitMigrated" then
		-- read live by Kit:IsOn("questTracker"), which looks again on the
		-- bus's 'setting' of this module (and tells 'look:questTracker')
		return
	elseif key:sub(1, 10) == "parchment_" then
		if MelloUI.Kit and MelloUI.Kit.SetParchment then
			MelloUI.Kit:SetParchment(key:sub(11), value and true or false)
		end
		return
	elseif MelloUI.Kit and MelloUI.Kit.borderKinds then
		for _, k in ipairs(MelloUI.Kit.borderKinds) do
			if key == k.key then
				MelloUI.Kit:ApplyBorder(k.kind)
				return
			end
		end
	end
	if key == "autoSnap" or key == "positions" or key == "layoutApplied" or key == "welcomeAsked" or key == "savedSurnameOwn" or key == "featuresFolded" then
		return
	elseif key == "nameFormat" then
		ApplyNameFormat(db, true)
		return
	elseif key == "preloadArt" then
		ApplyPreload(db, true)
		return
	elseif key == "reskin" then
		Apply(db, true)
		ApplyPreload(db, true)
		if value then
			ReskinOn(db)
		end
	elseif key:sub(1, 4) == "qol_" then
		local name = key:sub(5)
		if MelloUI:GetModule(name) then
			MelloUI:SetModuleEnabled(name, value and true or false)
		end
	elseif MelloUI:GetModule(key) then
		MelloUI:SetModuleEnabled(key, PanelWanted(db, key))
	end
end
