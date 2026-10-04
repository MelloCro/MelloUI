--------------------------------------------------------------------------------
-- MelloUI - Core
--
-- Module registry, saved variables and lifecycle.
--
-- A module is a plain table registered through MelloUI:RegisterModule(name, tbl).
-- Supported fields:
--   title            display name shown in the config panel
--   desc             tooltip / description text
--   defaults         table of default settings for the module
--   enabledByDefault boolean (default true)
--   options          declarative list used by Core/Config.lua to build controls
--   OnAddonLoaded(db) called at ADDON_LOADED (only if the module is enabled)
--   OnInit(db)       called once after saved variables are available
--   OnEnable(db)     called when the module is switched on (and at login if enabled)
--   OnDisable(db)    called when the module is switched off
--   applyWhenDisabled  true: OnDisable is called at start-up too when the
--                    module is off, for a module that drives others
--   OnSettingChanged(key, value, db)  called when one of its options changes
--   hidden           true: not listed in the configurator (driven by another
--                    module: the kit panels by Painted UI); /mello list shows it
--   slash            a short word /mello finds the module by besides its key
--                    and title (0.17.1: "swing" for Swing Timers: /mello swing log)
--   important        true: the configurator's tile keeps a gold border, a glowing
--                    icon and an IMPORTANT badge (the UI Modifications entry)
--   keep             the settings that are this player's own, not choices
--                    (learned flight points, a borrowed game setting, a
--                    one-time flag): exact keys, or Lua patterns starting
--                    with ^. Profiles and share strings leave them out and
--                    loading one never touches them (IsPersonalKey below)
--   options entries may carry `module = "<name>"` (the option belongs to that
--   module: built against its settings) or be `{ type = "include", module = }`
--   (that module's whole option list laid out in place); a toggle with
--   `important = true` is drawn gold with an IMPORTANT hint; every entry
--   with a control (toggle, slider, dropdown, button, any kind) names the
--   update it came with, `new = "<version>"`: its New tag while that update
--   runs (MelloUI:IsNew below; the user's rule of 2026-09-26)
-- The registry's own fields (audit, 2026-09-24, rank 4: one place that says
-- what a module is, for the configurator, the installer and UI
-- Modifications). All optional, kept on the module as given. UI
-- Modifications builds its rows, the movable game windows and the switches'
-- defaults from `window` and `tweak` (UIModifications.lua's header); the
-- configurator reads `icon` and `flavour` (its tiles) and `group` and
-- `navOrder` (its side list); the installer reads `role`; `area` and the
-- window's `addon` and `firstOpen` are facts nothing reads yet:
--   icon             texture path (or file id) of its tile
--   flavour          one line under its title
--   group            the side-list group its entry sits in: "The look",
--                    "Quests and travel", "Chat and sound" or "Frames and
--                    bars" (Home and Profiles are the configurator's own
--                    pages). A module shown in the configurator is a page
--                    entry; a hidden one a shortcut to its qol_ switch on UI
--                    Modifications' tabs. No group: no entry (a folded
--                    feature is found on UI Modifications' tabs only)
--   navOrder         a number: its place in that group, 1 first; entries
--                    without one come after, in the order they registered
--   new              a brand-new module or page: the update it came with
--                    ("<version>"), its side-list entry and page title tagged
--                    New while that update runs (its options carry their own)
--   window           a window (or HUD part) the reskin dresses: { label, desc,
--                    tab = "Windows" | "HUD", order = n (rows with one lead
--                    their tab, lowest first), switch = "<UI Modifications
--                    setting>" (the row is that setting, not a module switch:
--                    the Quest Tracker's questTrackerKit), frames = { frame
--                    names }, addon = "Blizzard_..." (loaded on demand),
--                    plainGrab = true (its frames move in Edit Layout),
--                    firstOpen = true (dressed on its first show),
--                    include = true | { keys } (its own options laid out
--                    under its row, indented and live only while it is on;
--                    { keys }: only those, in that order) }
--   tweak            a feature folded under UI Modifications: { label, desc,
--                    order = n (as window's), off = true (off until switched
--                    on), always = true (no switch: its rows each switch one
--                    thing) }
--   area             an own window's look switch: { key = "questTracker",
--                    follows = nil | "<module whose switch it follows>" }
--   role             what the installer's setups do with it: "core" (UI
--                    Modifications, the switchboard), "look" (restyles the
--                    game's art, fonts or sounds), "feature" (MelloUI's own
--                    tools), "adds" (adds information or automation to the
--                    game's UI without restyling it), "replaces" (replaces or
--                    restyles a game part). A hidden kit panel (it carries
--                    `window`) needs none: it is look.
--   installer        false: a feature, adds or replaces module NOT offered on
--                    the installer's Features step (0.17.1: its two columns are
--                    full; the Swing Timers are switched on in the settings)
-- One of the wrong type (or a role not in that list) goes to the error
-- handler and is left off the module; the module itself still registers.
-- MelloUI:ModulesInOrder() lists the modules in the order they registered.
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...

local MelloUI = CreateFrame("Frame")
ns.MelloUI = MelloUI
_G.MelloUI = MelloUI

MelloUI.name = ADDON_NAME
MelloUI.version = C_AddOns and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"
MelloUI.modules = {}

--------------------------------------------------------------------------------
-- New tags (the user's rule, 2026-09-26: "every new Dropdown menu, every new
-- slider, every new checkbox etc needs to get a "New" tag ... every next
-- update, the old "New" tags are being removed and reapplied to the new
-- stuff"). An option names the update it came with -- `new` on its schema
-- entry, the same in a hand-built row's options (WINDOW-RULES 6) -- and its
-- tag shows only while that update is the one running, so the next update
-- hides it by itself. The release check (Tools/lint/check_new_tags.py) fails
-- on a new option without one and takes the old ones out of the files.
--   MelloUI:ReleaseVersion() -> "0.14.0"   the running update: the TOC's
--       Version as three numbers (a test build's "0.14.0-rc5" or "0.14.0
--       RC5" is 0.14.0); nil when it names none ("dev"). The tests' probe:
--       IsNew below is what the tags ask
--   MelloUI:IsNew(v) -> true while `v` names the running update ("0.14" is
--       0.14.0); false for nil or anything else
--------------------------------------------------------------------------------

do
	local seen = {}   -- [a version as written] = its three numbers, or false
	local function ThreeNumbers(v)
		if type(v) ~= "string" then
			return nil
		end
		local known = seen[v]
		if known == nil then
			local a, b, c = v:match("^%s*[vV]?(%d+)%.(%d+)%.?(%d*)")
			known = a and string.format("%d.%d.%d", tonumber(a), tonumber(b), tonumber(c) or 0) or false
			seen[v] = known
		end
		return known or nil
	end
	function MelloUI:ReleaseVersion()
		return ThreeNumbers(self.version)
	end
	function MelloUI:IsNew(v)
		if v == nil then
			return false
		end
		local running = ThreeNumbers(self.version)
		return running ~= nil and ThreeNumbers(v) == running
	end
end

--------------------------------------------------------------------------------
-- The palette (user, 2026-09-23: "a Color Palette that i would like us to hold
-- as a rule in this UI"; the hex of each is the colour of its swatch -- "match
-- the hex code with the actual color" -- not the label written under it).
-- Every colour MelloUI draws itself -- fills, lines, text, selection, hover --
-- comes from here; the painted kit art is tuned to sit with it. { r, g, b } in
-- 0..1. Contrast on mainWindow: text 8.0:1, selectedTrim 5.1:1, mutedText
-- 3.2:1 (large or bold labels only, never small body text).
--   mainWindow    #1F1B16  a window's ground
--   innerPanel    #11100D  a panel sunk into the window (lists, insets)
--   raisedPanel   #2E1F14  a panel standing out of it (cards, plates)
--   border        #3D342A  rules and plain borders
--   trim          #8D642F  ornamental trim
--   text          #C6AF85  body text
--   mutedText     #7F6846  secondary text: labels, hints
--   selectedTab   #4E1812  the selected tab or row
--   selectedTrim  #AE8546  the selected tab's trim, gold highlights, headings
--   hover         #5A3C24  what the pointer is over
-- Those are Ember's, the palette MelloUI shipped with and the default. Six
-- more came with 0.14.0 (user, 2026-09-26: "Obsidian, Royal Azure and Fel
-- Ember, each with a Vibrant version"; their colours from
-- MelloUI-BuildData/palette/additions_0.14.0/palettes_0.14.0.json, the same
-- values as Tools/palettes.json, which the art tools read):
--   MelloUI.Palettes      { [id] = { id, name, blurb, roles = { [role] =
--                         { r, g, b, hex = "RRGGBB" } } }, order = { ids } }
--                         ids: ember, emberVibrant (0.19.1), obsidian,
--                         obsidianVibrant, royalAzure, royalAzureVibrant,
--                         felEmber, felEmberVibrant
--   MelloUI.Palette       THE palette in use: one palette's roles table, so
--                         a switch always puts another table there (read it
--                         when painting, never hold it from load)
--   MelloUI:PaletteId()   the id of the palette in use ("ember" for any
--                         table that is none of these)
--   MelloUI:KnownPalette(id) -> id   a palette id as the setting is read:
--                         one of the registry's, any other value (nil, "order",
--                         a number, an unknown name) "ember". The one rule for
--                         it: the switch below, the kit's folders, UI
--                         Modifications' Kit Colours, the widgets and the
--                         installer ask here
--   MelloUI:SetPalette(id) (below, with the settings) the setting
--                         UIModifications.palette; nil or unknown: ember
--   MelloUI.Meaning       the few FIXED meaning colours, the same under every
--                         palette (a 0.14.0 build decision, like the game's
--                         own can't-use red): cannotUse, #4E1812, what the
--                         player cannot use or learn (the merchant's and
--                         trade's red cards, the trainer's unlearnable rows);
--                         threatClose (amber) and threatAggro (red), the
--                         threat line's and the Threat widget's (0.16.0,
--                         Core/Threat.lua); bagFamily, a special bag's
--                         slot rims by its bag type (0.16.0); routeTrail
--                         and routeBeam, Route's red on the map and in the
--                         world (0.16.0). Read when drawing.
-- Every palette passes the palette's hard rules: text on mainWindow 8:1 or
-- more, text on hover 4.65:1 or more (Ember's 4.69 is the lowest), so muted
-- text never sits on hover.
--------------------------------------------------------------------------------
local function Hex(hex)
	return { tonumber(hex:sub(2, 3), 16) / 255, tonumber(hex:sub(4, 5), 16) / 255, tonumber(hex:sub(6, 7), 16) / 255, hex = hex:sub(2) }
end
MelloUI.Palettes = { order = {} }
do
	-- each palette's ten swatches in this order
	local ROLES = { "mainWindow", "innerPanel", "raisedPanel", "border", "trim", "text", "mutedText", "selectedTab",
		"selectedTrim", "hover" }
	-- `looks` (0.19.1): "ember" for a palette with Ember's two kit looks (Warm iron, Bronze) rather than one kit of
	-- its own (Modules/Kit.lua: Kit:LookFolder; Tools/palettes.json, the same field)
	local function Add(id, name, blurb, hexes, looks)
		local roles = {}
		for i = 1, #ROLES do
			roles[ROLES[i]] = Hex(hexes[i])
		end
		local palettes = MelloUI.Palettes
		palettes[id] = { id = id, name = name, blurb = blurb, roles = roles, looks = looks }
		palettes.order[#palettes.order + 1] = id
	end
	--   id, name, blurb, { mainWindow, innerPanel, raisedPanel, border, trim, text, mutedText, selectedTab, selectedTrim, hover }
	Add("ember", "Ember", "MelloUI's first palette: warm dark brown, bronze-gold trim, a deep red for the selection.",
		{ "#1F1B16", "#11100D", "#2E1F14", "#3D342A", "#8D642F", "#C6AF85", "#7F6846", "#4E1812", "#AE8546", "#5A3C24" })
	-- (0.19.1, user 2026-10-04: "a more Vivid and Vibrant Variation of the Ember Profile, both Bronze and Warm Iron":
	-- the vivid of two samples; Ember's two looks made from its roles, Media\KitEmberVibrant and KitEmberVibrantBronze)
	Add("emberVibrant", "Ember Vibrant",
		"Ember, lit: ember-black panels, vivid bronze trim, bright cream-gold text, a jewel ember red for the selection.",
		{ "#23190A", "#110F06", "#401F03", "#4E3B24", "#C27F18", "#FEE0AA", "#AF8E5D", "#730201", "#F3AF3C", "#683602" }, "ember")
	Add("obsidian", "Obsidian",
		"Neutral black glass and pewter, cold white text, one crimson accent. The calmest, highest-contrast base.",
		{ "#18191B", "#0D0E10", "#212326", "#353739", "#72767D", "#BEC1C5", "#75797E", "#54040A", "#9A9FA5", "#3B3F44" })
	Add("obsidianVibrant", "Obsidian Vibrant",
		"Black glass, deeper and crisper: blued-steel trim, silver titles, ice-white text, a jewel crimson for the selection.",
		{ "#121418", "#07090C", "#21252A", "#3B4047", "#5481C3", "#E8EDF4", "#8E99A9", "#9E0018", "#ACCFFC", "#3D444F" })
	Add("royalAzure", "Royal Azure", "Throne room: deep navy, polished gold trim, cream text, royal blue selection.",
		{ "#0F1A2A", "#050E1E", "#10233E", "#27374F", "#90712B", "#CBC0A4", "#867852", "#012169", "#BF9840", "#28405E" })
	Add("royalAzureVibrant", "Royal Azure Vibrant",
		"Throne room, lit: deep sapphire navy, polished gold trim, crisp cream text, a jewel-blue royal selection.",
		{ "#011942", "#000D2C", "#02275D", "#1B3E6F", "#B8871B", "#F1E7D0", "#B29859", "#022988", "#ECB33C", "#174885" })
	Add("felEmber", "Fel Ember", "Fel and void: charred black, fel-green trim and titles, void purple for the selection.",
		{ "#1E1815", "#130D0A", "#2B201B", "#3E3430", "#59843F", "#C4C1B3", "#797A6A", "#361851", "#7AB146", "#384232" })
	Add("felEmberVibrant", "Fel Ember Vibrant",
		"Fel and void, stronger: ember-charred black, vivid fel-green trim and titles, deep void purple for the selection.",
		{ "#1C0F08", "#0F0704", "#301C13", "#422F27", "#58982A", "#E7E3D2", "#8E916F", "#400568", "#85C545", "#254804" })
end
MelloUI.Palette = MelloUI.Palettes.ember.roles

-- the id of the palette in use, found by its table (worked out again only
-- when MelloUI.Palette is another table: no table made, a loop per switch)
do
	local seen, seenId = nil, "ember"
	function MelloUI:PaletteId()
		local current = self.Palette
		if current ~= seen then
			seen, seenId = current, "ember"
			local palettes = self.Palettes
			for _, id in ipairs(palettes.order) do
				if palettes[id].roles == current then
					seenId = id
					break
				end
			end
		end
		return seenId
	end
end

-- a palette id as the setting is read (the registry's `order` list is no
-- palette; a table read by self, so a test world's own registry answers)
function MelloUI:KnownPalette(id)
	local palettes = self.Palettes
	if type(id) == "string" and id ~= "order" and type(palettes) == "table" and type(palettes[id]) == "table" then
		return id
	end
	return "ember"
end

-- A palette colour as a chat / font-string colour code: "|cffAE8546"
-- (docs/plans/game-look.md wave 4: the palette as MelloUI.Look shows it --
-- the game's own colours by the same keys with the reskin off)
function MelloUI:PaletteCode(role)
	local Look = self.Look
	local c = (type(Look) == "table" and type(Look.Palette) == "function" and Look.Palette() or self.Palette)[role]
	return "|cff" .. (c and c.hex or "FFFFFF")
end

-- the fixed meaning colours (the header above): { r, g, b } in 0..1
MelloUI.Meaning = {
	cannotUse = { 0.306, 0.094, 0.071 },   -- #4E1812, an item the player cannot use, a spell not to be learned (meaning colour)
	-- (0.16.0, the threat line and the Threat widget, Core/Threat.lua: close to
	-- pulling, and the mob on you -- a loose mob for a tank)
	threatClose = { 0.878, 0.541, 0.118, hex = "E08A1E" },   -- #E08A1E, amber (meaning colour)
	threatAggro = { 0.816, 0.188, 0.118, hex = "D0301E" },   -- #D0301E, red (meaning colour)
	-- (0.16.0, the user's pick C of bag_family_sketch: a special bag's slots
	-- wear their bag type's colour on the rim) [bag family bit] = colour;
	-- Modules/BackpackPanel.lua reads it
	bagFamily = {
		[0x0001] = Hex("#E1C850"),   -- quiver (meaning colour)
		[0x0002] = Hex("#E1C850"),   -- ammo pouch (meaning colour)
		[0x0004] = Hex("#8246C8"),   -- soul bag (meaning colour)
		[0x0008] = Hex("#C8A06E"),   -- leatherworking (meaning colour)
		[0x0010] = Hex("#6482E6"),   -- inscription (meaning colour)
		[0x0020] = Hex("#46BE46"),   -- herbs (meaning colour)
		[0x0040] = Hex("#BE5ADC"),   -- enchanting (meaning colour)
		[0x0080] = Hex("#DC963C"),   -- engineering (meaning colour)
		[0x0200] = Hex("#3CBED7"),   -- gems (meaning colour)
		[0x0400] = Hex("#CD8442"),   -- mining (meaning colour)
		[0x8000] = Hex("#46AAAA"),   -- fishing (meaning colour)
		[0x10000] = Hex("#DC6446"),  -- cooking (meaning colour)
	},
	-- (0.16.0, the user's picks of route_marks_sketch: Route's red, the way
	-- and the destination -- the trail's dots on the map and the minimap, the
	-- World Marker's beam with the light at its foot; Modules/Route.lua)
	routeTrail = Hex("#CD261C"),   -- the trail's dots (meaning colour)
	routeBeam = Hex("#FF291A"),    -- the beam, its ring and glow, the lit gem (meaning colour)
	-- (0.17.0, Combat Text's lines, the user's sketch combat_text_looks: the
	-- damage you take, the healing you get, the resources you gain; softened
	-- to sit with the palette. Modules/CombatText.lua)
	combatTaken = Hex("#E25C48"),      -- (meaning colour)
	combatHeal = Hex("#7AC860"),       -- (meaning colour)
	combatResource = Hex("#609CE6"),   -- (meaning colour)
	-- (Your Damage: a spell's hit on an enemy, as the game tells them apart)
	combatSpell = Hex("#BE96E6"),      -- (meaning colour)
	-- (0.17.1, the swing timers, the user's picks of swing_looks: the shot
	-- reloading in cream, a melee swing pale; Modules/SwingTimers.lua)
	swingShot = Hex("#E9DCAA"),        -- (meaning colour)
	swingMelee = Hex("#EFEBE3"),       -- (meaning colour)
	-- (the shot's aim, the red of the picked swing_looks: stand still)
	swingAim = Hex("#D63428"),         -- (meaning colour)
	-- (0.18.5, the Rare Alert, the user's pick A of rare_alert_sketch: a rare's
	-- name in the game's silver, as its crest's metal; a rare elite's stays gold)
	rareSilver = Hex("#D2D6DC"),       -- (meaning colour)
}
MelloUI.moduleOrder = {}

local DB_VERSION = 1

local DB_DEFAULTS = {
	version = DB_VERSION,
	enabled = {},   -- [moduleName] = boolean
	modules = {},   -- [moduleName] = { settings }
	profiles = {},  -- [name] = serialised settings (see Profiles below)
}

--------------------------------------------------------------------------------
-- Secret-safe reads: one set for the whole addon (audit, 2026-09-24: 59 files
-- carried their own Secret / IsSecret, in 4 bodies, and 11 their own Plain,
-- with 6 meanings). This client hands some values over SECRET
-- (issecretvalue): comparing one -- even with nil --, joining it into text or
-- doing arithmetic on it is refused, so each helper asks issecretvalue FIRST,
-- before any other test of the value. None of them makes a table.
-- A file binds the ones it needs once, at load, as upvalues (a call costs
-- what its own copy did):
--   local Secret = MelloUI.Safe.IsSecret
-- Core is first in the TOC, so Safe is always there; a test world that loads
-- a file without Core runs this block itself (wave 3, 2026-09-25: the
-- `MelloUI.Safe and ... or <stand-in>` bindings went with that).
--------------------------------------------------------------------------------

local Safe = {}
MelloUI.Safe = Safe

-- true when v is secret; always a boolean (false on a client without secrets)
function Safe.IsSecret(v)
	return issecretvalue and issecretvalue(v) or false
end

-- v, or nil when v is secret (or nil)
function Safe.Value(v)
	if issecretvalue and issecretvalue(v) then
		return nil
	end
	return v
end

-- v when it is a plain number, else nil (secret, nil or not a number)
function Safe.Number(v)
	if (issecretvalue and issecretvalue(v)) or type(v) ~= "number" then
		return nil
	end
	return v
end

-- v when it is a plain, finite number, else nil (secret, not a number, NaN
-- or infinite): for anything that becomes a size, a place, a scale or a
-- loop's step (a player's game froze opening the map, 2026-09-26)
function Safe.Finite(v)
	if (issecretvalue and issecretvalue(v)) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	return v
end

-- v when it is a plain string, else nil (secret, nil or not a string)
function Safe.Text(v)
	if (issecretvalue and issecretvalue(v)) or type(v) ~= "string" then
		return nil
	end
	return v
end

-- a pcall's results, or nil when it raised or its first result is secret
local function Checked(ok, first, ...)
	if not ok or (issecretvalue and issecretvalue(first)) then
		return nil
	end
	return first, ...
end

-- obj:method(...) guarded: its results, or nil when obj has no such method,
-- the call raised or the first result is secret. Only the first is tested;
-- any further results are the caller's to test.
function Safe.Call(obj, method, ...)
	local fn = type(obj) == "table" and obj[method]
	if type(fn) ~= "function" then
		return nil
	end
	return Checked(pcall(fn, obj, ...))
end

-- Where a frame or region lies on the screen, in pixels (its effective scale
-- applied): left, bottom, right, top -- or nil when it cannot be read
-- plainly: no GetRect or GetEffectiveScale, either one raised (not laid out
-- yet, a restricted region), a value secret or not a number, or an edge that
-- comes out not a number (NaN). The one screen-rect reader (0.14.0: four
-- copies with four return shapes went); a caller that needs a size tests
-- r > l and t > b itself. Makes no table.
function Safe.ScreenRect(region)
	if type(region) ~= "table" then
		return nil
	end
	local getRect, getScale = region.GetRect, region.GetEffectiveScale
	if type(getRect) ~= "function" or type(getScale) ~= "function" then
		return nil
	end
	local ok, l, b, w, h = pcall(getRect, region)
	if not ok then
		return nil
	end
	local okS, s = pcall(getScale, region)
	if not okS then
		return nil
	end
	local Num = Safe.Number
	l, b, w, h, s = Num(l), Num(b), Num(w), Num(h), Num(s)
	if not (l and b and w and h and s) then
		return nil
	end
	local left, bottom, right, top = l * s, b * s, (l + w) * s, (b + h) * s
	if left ~= left or bottom ~= bottom or right ~= right or top ~= top then
		return nil   -- (not a number: no place on the screen)
	end
	return left, bottom, right, top
end

--------------------------------------------------------------------------------
-- Frames made in a game window while the game's Gamepad UI is on (0.14.0
-- RC6: a player's game froze opening the world map with a gamepad, "insecure
-- scripts exceeded execution limit for addon MelloUI", 2026-09-26).
-- The game's gamepad navigation (Blizzard_GamepadSmartNavigation) hooks
-- CreateFrame: for every frame made with a parent that lies in a window it
-- has open (SmartNavigation.activePanels: a window opened by ShowUIPanel --
-- the world map, the character window, the spell book ... --, a bag, a menu;
-- only while the Gamepad UI is on) it walks that WHOLE window again, every
-- frame in it, hidden ones too, looking for its buttons. The walk runs in the
-- maker's own run, so its time counts against the maker's script time, which
-- the engine limits per addon: K frames made one by one in the open map (a
-- row dressed a frame, a pin, a list's row) are K walks of the whole map.
-- The hook passes over a frame made with no parent, and SetParent is not
-- hooked. So:
--   Safe.CreateFrame(frameType, name, parent, ...) -> the frame: the game's
--       CreateFrame itself, unless `parent` lies in a window the navigation
--       has open: then it is made with no parent and put on `parent` at once,
--       at its parent's strata and one level over it, where CreateFrame puts
--       a child. With the Gamepad UI off no window is ever open for the
--       navigation: always the game's call, as before (a length read more).
--       Every file that dresses a window binds it once, in the game's place:
--           local CreateFrame = MelloUI.Safe.CreateFrame
--       (the ratchet's window-createframe check holds that)
--   Safe.UnderOpenWindow(frame) -> true when a frame made in `frame` would
--       make the navigation walk a window (the climb its hook does)
--   Safe.GamepadUI() -> true while the game's Gamepad UI is on
--------------------------------------------------------------------------------

function Safe.GamepadUI()
	local util = InputUtil
	local fn = type(util) == "table" and util.IsGamepadUIEnabled
	if type(fn) ~= "function" then
		return false
	end
	local ok, on = pcall(fn)
	if not ok or (issecretvalue and issecretvalue(on)) then
		return false
	end
	return on == true
end

do
	-- (the navigation's own climb: the parent and each of its parents up to
	-- UIParent, against every window it has open)
	local function InOpenWindow(frame, panels, n)
		local top = UIParent
		local f = frame
		for _ = 1, 200 do
			if f == nil or f == top then
				return false
			end
			for i = 1, n do
				local info = panels[i]
				if type(info) == "table" and info.frame == f then
					return true
				end
			end
			f = f:GetParent()
		end
		return false
	end

	function Safe.UnderOpenWindow(frame)
		if type(frame) ~= "table" then
			return false
		end
		local nav = SmartNavigation
		if type(nav) ~= "table" then
			return false
		end
		local panels = nav.activePanels
		if type(panels) ~= "table" then
			-- (a build that keeps its open windows elsewhere: in the Gamepad UI
			-- every parent counts)
			return Safe.GamepadUI()
		end
		local n = #panels
		if n == 0 then
			return false
		end
		local ok, under = pcall(InOpenWindow, frame, panels, n)
		return ok and under or false
	end
end

function Safe.CreateFrame(frameType, name, parent, ...)
	if parent == nil or not Safe.UnderOpenWindow(parent) then
		return CreateFrame(frameType, name, parent, ...)
	end
	local frame = CreateFrame(frameType, name, nil, ...)
	frame:SetParent(parent)
	local strata = parent:GetFrameStrata()
	if frame:GetFrameStrata() ~= strata then
		frame:SetFrameStrata(strata)
	end
	local level = math.min(parent:GetFrameLevel() + 1, 10000)
	if frame:GetFrameLevel() ~= level then
		frame:SetFrameLevel(level)
	end
	return frame
end

-- The screen as a player names it: its size in pixels and its aspect ratio
-- ("32:9", "21:9", "16:9", "16:10", "3:2", "4:3", "5:4": the nearest one,
-- and no label when none is within 4 %, as a triple screen or a 32:10), from
-- GetPhysicalScreenSize read through Safe.Number. One helper for the
-- configurator's Your setup and the installer's Screen step. Returns width,
-- height, label (nil when none is close); nothing while the client does not
-- say. Makes no table.
function MelloUI:ScreenInfo()
	if not GetPhysicalScreenSize then
		return nil
	end
	local ok, w, h = pcall(GetPhysicalScreenSize)
	if not ok then
		return nil
	end
	w, h = Safe.Number(w), Safe.Number(h)
	if not (w and h and w > 0 and h > 0) then
		return nil
	end
	-- (the nearest ratio: each bound is half way between two neighbours;
	-- "21:9" as the screens sold under it measure, 2560 x 1080 and 3440 x
	-- 1440, about 2.37)
	local ratio = w / h
	local label, target
	if ratio >= 2.96 then
		label, target = "32:9", 32 / 9
	elseif ratio >= 2.07 then
		label, target = "21:9", 2.37
	elseif ratio >= 1.689 then
		label, target = "16:9", 16 / 9
	elseif ratio >= 1.55 then
		label, target = "16:10", 1.6
	elseif ratio >= 1.417 then
		label, target = "3:2", 1.5
	elseif ratio >= 1.29 then
		label, target = "4:3", 4 / 3
	else
		label, target = "5:4", 1.25
	end
	local off = ratio / target - 1
	if off > 0.04 or off < -0.04 then
		label = nil   -- (nothing close: no label rather than a wrong one)
	end
	return w, h, label
end

-- The screen as the texts show it: "3440 × 1440 (21:9)" (no label: the size
-- alone), and the aspect as a word ("21:9", else "2.39:1"); nil while
-- ScreenInfo says nothing. Made again only when the size changes: the one
-- formatter for the configurator's Your setup and the installer's lines.
do
	local memo = { w = false, h = false, text = nil, ratio = nil }
	function MelloUI:ScreenText()
		local w, h, label = self:ScreenInfo()
		if not w then
			return nil
		end
		if memo.w ~= w or memo.h ~= h then
			memo.w, memo.h = w, h
			local size = string.format("%d \195\151 %d", math.floor(w + 0.5), math.floor(h + 0.5))
			memo.text = label and (size .. " (" .. label .. ")") or size
			memo.ratio = label or string.format("%.2f:1", w / h)
		end
		return memo.text, memo.ratio
	end
end

-- Two reads MelloUI's own engines share (the installer, its window, the Edit
-- Mode layout; one reader each, plain functions a file binds once):
--   MelloUI.InCombat()      in combat (the game's lockdown)
--   MelloUI.EditModeOpen()  Edit Mode open, read only: its manager shown, or
--                           still active while a game panel hides it for a
--                           moment (its own flag: it leaves Edit Mode, and
--                           tells so, only on a real exit)
function MelloUI.InCombat()
	return InCombatLockdown and InCombatLockdown() and true or false
end

function MelloUI.EditModeOpen()
	local manager = EditModeManagerFrame
	if type(manager) ~= "table" or type(manager.IsShown) ~= "function" then
		return false
	end
	local active = manager.editModeActive
	if not Safe.IsSecret(active) and active == true then
		return true
	end
	local ok, shown = pcall(manager.IsShown, manager)
	if not ok or Safe.IsSecret(shown) then
		return false
	end
	return shown and true or false
end

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------

local PREFIX = "|cff9b8cffMello|rUI: "

-- Everything printed is also kept (the last LOG_MAX lines, colour codes
-- stripped) for the copy window: /mellolog shows it in a text box that can
-- be selected and copied, so a dump travels as text instead of screenshots.
local LOG_MAX = 2000
local log = {}

-- MelloUI.printHold: while this counter is above 0, printed lines go to the
-- log only (/mellolog), not to the chat. The installer holds them while it
-- applies a setup, so a new player's chat gets its one summary line instead
-- of each module's own ("Font Style: ...", "Custom Sounds switched on ...").
-- Whoever raises it lowers it again, also on an error.
MelloUI.printHold = 0

-- A secret value (this client) prints as "[secret]": a format with one
-- secret argument would make the whole message secret and unindexable.
local function Printable(v)
	if Safe.IsSecret(v) then
		return "[secret]"
	end
	return v
end

function MelloUI:Print(msg, ...)
	local n = select("#", ...)
	if n > 0 then
		local args = { ... }
		for i = 1, n do
			local v = Printable(args[i])
			-- a nil argument prints as nothing, never as a stray "%s ... nil"
			if v == nil then v = "" end
			args[i] = v
		end
		local ok, formatted = pcall(string.format, Printable(msg), unpack(args, 1, n))
		if ok then
			msg = formatted
		else
			-- a "[secret]" where a number was expected: the pieces, joined
			local parts = { tostring(Printable(msg)) }
			for i = 1, n do
				parts[#parts + 1] = tostring(args[i])
			end
			msg = table.concat(parts, " ")
		end
	end
	msg = tostring(Printable(msg))
	local hold = MelloUI.printHold
	if not (type(hold) == "number" and hold > 0) then
		print(PREFIX .. msg)
	end
	log[#log + 1] = (msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
	if #log > LOG_MAX then
		table.remove(log, 1)
	end
end

function MelloUI:ClearLog()
	wipe(log)
end

-- One game setting (a CVar) held at `want` while `on`, and the player's own
-- value given back when not (0.17.1, lifted from the damage meter's when the
-- swing timers needed the same: one way for every module that steps in for
-- a part of the game). The player's value is noted in db[savedKey] the first
-- time it is changed; keep savedKey in the module's `keep` (never in a
-- profile). Ask out of combat: the caller waits for the fight's end. Returns
-- true when it wrote the CVar.
--   MelloUI:HoldCVar(db, name, savedKey, on, want)
--   MelloUI:CVarText(name) -> the CVar's value as text (nil: unknown)
function MelloUI:CVarText(name)
	local api = C_CVar
	if not (api and api.GetCVar) then
		return nil
	end
	local ok, v = pcall(api.GetCVar, name)
	return ok and Safe.Text(v) or nil
end

function MelloUI:HoldCVar(db, name, savedKey, on, want)
	local api = C_CVar
	if not (db and api and api.SetCVar) then
		return false
	end
	if on then
		local now = self:CVarText(name)
		if now ~= nil and now ~= want then
			if db[savedKey] == nil then
				db[savedKey] = now
			end
			pcall(api.SetCVar, name, want)
			return true
		end
	elseif db[savedKey] ~= nil then
		local saved = db[savedKey]
		db[savedKey] = nil
		pcall(api.SetCVar, name, saved)
		return true
	end
	return false
end

-- an error in a listener or a callback: to the game's error handler, and on
local function Report(err)
	local handler = geterrorhandler and geterrorhandler()
	if type(handler) == "function" then
		handler(err)
	end
end

--------------------------------------------------------------------------------
-- The settings bus (audit, 2026-09-24, rank 5): one path for "this changed",
-- where files hooked MelloUI's own functions (NotifySettingChanged,
-- SetModuleEnabled, Kit.SetParchment: a hook runs for every setting of every
-- module and can never be taken off) or kept a listener list per subject.
--
--   MelloUI:On(topic, fn, owner)  fn(...) is called with what the topic is
--                                 fired with (not the topic). One listener per
--                                 owner and topic: On again with the same
--                                 owner replaces its fn where it stands.
--                                 owner defaults to fn. Listeners run in the
--                                 order they came.
--   MelloUI:Off(owner[, topic])   that owner's listeners, of one topic or all
--   MelloUI:Fire(topic, ...)      every listener of the topic, each in its own
--                                 pcall: one that raises goes to the error
--                                 handler and the others still run. No table
--                                 is made per Fire. One added during a Fire
--                                 first runs on the next; one taken off
--                                 during it is not called any more.
--   MelloUI:Batch(fn, ...)        fn(...), with the 'setting' Fires raised
--                                 meanwhile held and fired after it, one per
--                                 module and key (its last value), in the
--                                 order first raised; the settings backup is
--                                 scheduled once at the end, not per setting
--                                 (the installer's apply engine). Batches
--                                 nest. fn's results are returned; an error
--                                 in fn is raised again once the held Fires
--                                 went out.
--   MelloUI:InBatch()             true while a Batch runs (its 'setting'
--                                 Fires held)
-- Topics, with what they carry:
--   "setting"      moduleName, key, value  end of NotifySettingChanged
--   "module"       moduleName, enabled     end of SetModuleEnabled (not before
--                                          login's start-up: the flag only)
--   "restart"      -                       end of RestartModules
--   "look:<area>"  on                      an area's kit look switched
--   "cover"        area, on                Kit:Cover
--   "parchment"    area, on                Kit:SetParchment
--   "border"       kind                    a Button / window Border changed
--   "fonts"        -                       the Font Style or a face changed
--   "scale"        reason                  "uiscale" | "editmode" (Kit's watcher)
--   "editmode"     entering                Edit Mode entered (true) / left
--   "shell"        window                  a kit window shell was built
--   "palette"      -                       MelloUI.Palette or the Kit Colours changed
--                                          (fired after both are in place; a new
--                                          palette is a new table; a palette
--                                          switch fires it once, after 'border':
--                                          MelloUI:SetPalette)
--   "shade"        area, on, strength      an area's UI Shade switched or its
--                                          strength changed (Modules/KitShade.lua),
--                                          once its partners follow
--   "column"       -                     the column under the minimap re-laid
--   "where"        cont, x, y              the player's place for Route:WantWhere's
--                                          owners, from Route's tick every 2 s while
--                                          wanted, after 10 yd moved or a continent
--                                          change (all nil when lost)
--   "reminder"     key, active, up         a reminder's state changed
--                                          (Core/Reminders.lua): active =
--                                          wanted now, up = on the widget
--   "meter"        what, fight             the damage meter's history changed
--                                          (Modules/Meter.lua): "fight", the
--                                          new record / "clear"
--   "editmodelayout" what, name            a layout went into Edit Mode
--                                          (Core/EditModeLayout.lua): "put",
--                                          name (put in, made active) /
--                                          "active", name (a saved one made
--                                          active)
--   "backup"       -                       the macro backup changed by itself
--                                          (Core/Backup.lua: a delayed or
--                                          held write or delete, the login's
--                                          look at the macros)
--   "editlayout"   showing, state          Edit Layout shown or not (Core/EditLayout.lua):
--                                          state "open" | "paused" | "closed"; on every
--                                          change of showing and on its close
--   "configurator" shown                   the configurator window shown or hidden
--                                          (0.17.0: the Fader shows every element
--                                          while it is open)
--   "mover"        what, entry, ...        the mover registry (the window places
--                                          below): ("registered", entry),
--                                          ("shown", entry, shown), ("released",
--                                          entry) when an Edit Layout session lets
--                                          go of an entry it held
--   "installer"    what, ...               the installer (Core/Installer.lua):
--                    "installed", setupKey, needsReload   a setup went in
--                    "countdown", seconds, paused, why    the Keep countdown
--                    "kept", needsReload                  Keep pressed
--                    "reverted", reason, reloadOwed       back to 'Before
--                                          install' (reason "button",
--                                          "timeout" or "error")
--                    "revertFailed", reason, why          it could not be
--                                          put back (the restore point stays)
--------------------------------------------------------------------------------

-- the settings backup through the bus's Batch: held there, scheduled once at
-- its end (set below)
local Backup

do
	local topics = {}   -- [topic] = { fn = {}, owner = {}, n = 0, depth = 0, dirty = false }
	local batch = 0     -- Batch depth
	local backupWanted = false

	-- the slots taken off during a Fire are false until it ends: then the
	-- list closes up, in order
	local function Compact(t)
		local fns, owners, j = t.fn, t.owner, 0
		for i = 1, t.n do
			local fn = fns[i]
			if fn then
				j = j + 1
				fns[j], owners[j] = fn, owners[i]
			end
		end
		for i = j + 1, t.n do
			fns[i], owners[i] = nil, nil
		end
		t.n, t.dirty = j, false
	end

	function MelloUI:On(topic, fn, owner)
		assert(topic ~= nil and type(fn) == "function", "MelloUI:On(topic, fn, owner) needs a topic and a function")
		if owner == nil then
			owner = fn
		end
		local t = topics[topic]
		if not t then
			t = { fn = {}, owner = {}, n = 0, depth = 0, dirty = false }
			topics[topic] = t
		end
		local fns, owners = t.fn, t.owner
		for i = 1, t.n do
			if fns[i] and owners[i] == owner then
				fns[i] = fn
				return
			end
		end
		local n = t.n + 1
		t.n = n
		fns[n], owners[n] = fn, owner
	end

	local function OffIn(t, owner)
		local fns, owners = t.fn, t.owner
		for i = 1, t.n do
			if fns[i] and owners[i] == owner then
				fns[i], owners[i] = false, false
				t.dirty = true
			end
		end
		if t.dirty and t.depth == 0 then
			Compact(t)
		end
	end

	function MelloUI:Off(owner, topic)
		if owner == nil then
			return
		end
		if topic ~= nil then
			local t = topics[topic]
			if t then
				OffIn(t, owner)
			end
			return
		end
		for _, t in pairs(topics) do
			OffIn(t, owner)
		end
	end

	-- a Batch's held 'setting' Fires: parallel lists, and at[module][key] =
	-- its slot. Two kept (one filling while the other goes out), their
	-- tables reused from batch to batch.
	local function NewHold()
		return { n = 0, mod = {}, key = {}, val = {}, at = {} }
	end
	local held, spare = NewHold(), nil

	local function Hold(module, key, value)
		local h = held
		local byKey
		if module ~= nil and key ~= nil then
			byKey = h.at[module]
			if not byKey then
				byKey = {}
				h.at[module] = byKey
			end
			local i = byKey[key]
			if i then
				h.val[i] = value
				return
			end
		end
		local i = h.n + 1
		h.n = i
		h.mod[i], h.key[i], h.val[i] = module, key, value
		if byKey then
			byKey[key] = i
		end
	end

	function MelloUI:Fire(topic, ...)
		if batch > 0 and topic == "setting" then
			Hold(...)
			return
		end
		local t = topics[topic]
		if not t or t.n == 0 then
			return
		end
		t.depth = t.depth + 1
		local fns = t.fn
		for i = 1, t.n do   -- (the count as it was when the Fire began)
			local fn = fns[i]
			if fn then
				local ok, err = pcall(fn, ...)
				if not ok then
					Report(err)
				end
			end
		end
		t.depth = t.depth - 1
		if t.dirty and t.depth == 0 then
			Compact(t)
		end
	end

	local function Flush()
		local h = held
		if h.n == 0 then
			return
		end
		-- a listener may start a Batch of its own: it fills the other list
		held = spare or NewHold()
		spare = nil
		for i = 1, h.n do
			local module, key, value = h.mod[i], h.key[i], h.val[i]
			h.mod[i], h.key[i], h.val[i] = nil, nil, nil
			MelloUI:Fire("setting", module, key, value)
		end
		h.n = 0
		for _, byKey in pairs(h.at) do
			wipe(byKey)
		end
		spare = h
	end

	local function EndBatch(ok, ...)
		batch = batch - 1
		if batch == 0 then
			Flush()
			if backupWanted then
				backupWanted = false
				if MelloUI.ScheduleBackup then
					MelloUI:ScheduleBackup("batch")
				end
			end
		end
		if not ok then
			error((...), 0)
		end
		return ...
	end

	function MelloUI:Batch(fn, ...)
		batch = batch + 1
		return EndBatch(pcall(fn, ...))
	end

	function MelloUI:InBatch()
		return batch > 0
	end

	-- NotifySettingChanged, SetModuleEnabled and the profile loads ask for
	-- the backup here: "setting <key>" as before, or once for a whole Batch
	Backup = function(self, reason, detail)
		if batch > 0 then
			backupWanted = true
			return
		end
		if self.ScheduleBackup then
			self:ScheduleBackup(detail ~= nil and (reason .. tostring(detail)) or reason)
		end
	end
end

--------------------------------------------------------------------------------
-- UI sounds (moved from the configurator, audit 2026-09-24: its sounds are
-- for every MelloUI window, and the configurator is being rebuilt). The soft
-- clicks made by Tools\make_ui_sounds.py; the game's own sounds if a file is
-- missing; the Custom Sounds module's own click when it is on.
--   MelloUI:PlayUISound(kind)
--     the soft clicks:  "page", "tab", "check_on", "check_off"
--     the game's own:   "option_on", "option_off" (its checkbox clicks),
--                       "menu_open", "menu_close", "menu_button" (the game
--                       menu's), "window_open", "window_close", "tick" (the
--                       chat's scroll button), "waypoint_set", "waypoint_clear",
--                       "bags_open", "bags_close" (the bag window by kind)
--     the notice's:    "notice_track", "notice_arrive", "notice_learn",
--                       "notice_fail" (MelloUI:Announce, on the Master channel)
--     the user's own:   "marker" (Route's World Marker as it changes), "rare"
--                       (the Rare Alert: a rare spotted, on the Master channel)
-- Every MelloUI window plays its UI sounds through here, never PlaySound
-- itself (audit, 2026-09-24: Dynamic UI, Voice Over, the Quest List and the
-- mover each called it directly; Tools/lint/check_panels.py holds it).
--------------------------------------------------------------------------------

do
	local SOUND_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Sounds\\"
	-- file: MelloUI's own click, played first. kit: the SOUNDKIT name (alt:
	-- the one for a client without it), looked up when played -- played when
	-- there is no file or the file is missing. A kit-only kind is the game's
	-- sound the window played before, id for id; Custom Sounds' PlaySound hook
	-- swaps it as it does any game click.
	local SOUNDS = {
		check_on  = { file = "check_on.ogg",  kit = "IG_MAINMENU_OPTION_CHECKBOX_ON" },
		check_off = { file = "check_off.ogg", kit = "IG_MAINMENU_OPTION_CHECKBOX_OFF" },
		tab       = { file = "tab.ogg",       kit = "IG_CHARACTER_INFO_TAB" },
		page      = { file = "page.ogg",      kit = "IG_MAINMENU_OPTION" },
		option_on      = { kit = "IG_MAINMENU_OPTION_CHECKBOX_ON" },
		option_off     = { kit = "IG_MAINMENU_OPTION_CHECKBOX_OFF" },
		menu_open      = { kit = "IG_MAINMENU_OPEN" },
		menu_close     = { kit = "IG_MAINMENU_CLOSE" },
		menu_button    = { kit = "IG_MAINMENU_OPTION" },
		window_open    = { kit = "IG_CHARACTER_INFO_OPEN" },
		window_close   = { kit = "IG_CHARACTER_INFO_CLOSE" },
		tick           = { kit = "U_CHAT_SCROLL_BUTTON" },
		waypoint_set   = { kit = "UI_MAP_WAYPOINT_CLICK_TO_PLACE", alt = "IG_MAINMENU_OPTION_CHECKBOX_ON" },
		waypoint_clear = { kit = "UI_MAP_WAYPOINT_REMOVE", alt = "IG_MAINMENU_OPTION_CHECKBOX_OFF" },
		-- the on-screen notice's chimes (Core/Notice.lua): Route's own from
		-- before, on the Master channel as they were
		notice_track   = { kit = "UI_MAP_WAYPOINT_SUPER_TRACK_ON", alt = "UI_MAP_WAYPOINT_CLICK_TO_PLACE", channel = "Master" },
		notice_arrive  = { kit = "UI_MAP_WAYPOINT_SUPER_TRACK_OFF", alt = "IG_QUEST_LIST_COMPLETE", channel = "Master" },
		notice_learn   = { kit = "UI_MAP_WAYPOINT_CLICK_TO_PLACE", alt = "IG_MAINMENU_OPTION_CHECKBOX_ON", channel = "Master" },
		notice_fail    = { kit = "UI_MAP_WAYPOINT_REMOVE", alt = "IG_QUEST_LOG_ABANDON_QUEST", channel = "Master" },
		-- Route's World Marker as it changes (0.18.4, user 2026-10-04): a new
		-- destination, the far beacon into the near look over the place and
		-- back -- the user's own sound (their SFX library: Quest_TrackChange_01)
		marker         = { file = "SFX\\Quest_TrackChange.ogg", kit = "UI_RUNECARVING_CLOSE_MAIN_WINDOW", alt = "UI_MAP_WAYPOINT_CLICK_TO_PLACE" },
		-- the Rare Alert (0.18.5, user 2026-10-04): a rare just spotted -- the
		-- user's own sound (their SFX library: Alert/RareMob/RareMob_Ward_01),
		-- on the Master channel as the notice's chimes, so it is heard
		rare           = { file = "SFX\\RareMob_Ward.ogg", kit = "RAID_WARNING", alt = "UI_MAP_WAYPOINT_SUPER_TRACK_ON", channel = "Master" },
		-- the bag window by kind (0.19.0): the game's own bag sounds, as its
		-- bag window played them
		bags_open      = { kit = "IG_BACKPACK_OPEN" },
		bags_close     = { kit = "IG_BACKPACK_CLOSE" },
	}
	for _, sound in pairs(SOUNDS) do
		if sound.file then
			sound.path = SOUND_PATH .. sound.file
		end
	end

	function MelloUI:PlayUISound(kind)
		local sound = SOUNDS[kind]
		if not sound then
			return
		end
		-- the Custom Sounds module, when it is on, plays its own click instead
		if self.PlayCustomUISound and self:PlayCustomUISound(kind) then
			return
		end
		if sound.path then
			local ok, played = pcall(PlaySoundFile, sound.path, "SFX")
			if ok and played then
				return
			end
		end
		local kit = SOUNDKIT and (SOUNDKIT[sound.kit] or (sound.alt and SOUNDKIT[sound.alt]))
		if kit and sound.channel then
			PlaySound(kit, sound.channel)
		elseif kit then
			PlaySound(kit)
		end
	end
end

--------------------------------------------------------------------------------
-- Window places: one store, one mover registry and one keep-on-screen for
-- every element MelloUI moves (audit, 2026-09-24, rank 6: the whisper popups,
-- the Route arrow, the Voice Over overlay and the copy window each dragged
-- themselves and kept their place their own way). Core keeps the
-- registration, the store, the put-backs and the pending changes of an Edit
-- Layout session (0.15.0: Edit Layout, Core/EditLayout.lua and its files, is
-- THE one place to move things; the old Unlock the Windows mode and its
-- provider went with it), so all of it works with UI Modifications off.
--
--   MelloUI:RegisterMover(frame, handle, opts) -> entry
--       handle (default: the frame) is what the plain drag takes. opts, all
--       optional:
--         key        its place in the store (default: the frame's name; no
--                    key, no saved place)
--         anchor     the frame's point that is saved, held to the same point
--                    of the screen ("TOPRIGHT": it grows down and left from
--                    there); nil: BOTTOMLEFT to the screen's CENTER
--         default    function(frame) -> placed[, line]: lays its standard
--                    place (a Reset's preview, a window with no anchor);
--                    false and a line when it cannot (a Reset prints it)
--         save       function(frame[, pos]): a window that keeps its own
--                    place (the Quest Tracker): called on a plain drag's
--                    release and at Edit Layout's Save (with the pending
--                    place, its anchor's form), the store untouched
--         reset      function(): its own settings back, for such a window
--         min, max   the wheel's scale range; base: its 100 %
--         with       a frame, a list of frames, or a function returning
--                    either (looked up when needed: the Quest List beside
--                    the world map is made on the map's first show), kept on
--                    the screen with it (they move with it)
--         plainDrag  "always": dragged by its handle at any time (while
--                    Edit Layout shows only a "tool"'s); false (default; the
--                    old "unlocked" too): moved in Edit Layout only
--       and Edit Layout's (0.15.0):
--         label      the plate's name ("Quest Tracker"); default: the key,
--                    else the frame's name
--         page       the Configurator page its "All options >" opens (a
--                    module name, as MelloUI:OpenConfig takes)
--         group      "own" (default) | "window" | "hud" | "tool" (never a
--                    plate, never in Reset all or the change count)
--         placeholder true (its own size) or { w, h } (UI units): a plate
--                    even while it is hidden or 0 x 0, at its anchored place
--         visible    function(entry) -> shown: the plate's own test (default:
--                    the frame shown)
--         follow     true: the game lays it out again (the panel manager,
--                    the bag layout, Edit Mode): its place is put back after
--                    anyone else's SetPoint / SetScale and after
--                    UpdateUIPanelPositions / UpdateContainerFrameAnchors
--                    (post-hooks only), a protected one in combat after the
--                    fight; its own scale noted as its 100 % (base) at the
--                    registration and whenever someone else scales it
--         resize     false: no size change in Edit Layout
--         settings   (0.17.0) { "Module.key", ... }: the element's own settings
--                    as sliders in its Edit Layout box -- shortcuts to the
--                    configurator's (the same setting: the module's schema
--                    gives the name and range, a change goes through
--                    NotifySettingChanged); a slider entry only (the race
--                    bar's Width and Height; user, 2026-10-01)
--         locked     function(entry) -> reason | nil: shown, not movable
--                    (in Edit Layout, and by its plain drag)
--         note       function(entry) -> text | nil: a line in its box
--         resetLabel its box's Reset text (default "Reset")
--         when       function(entry) -> live: its place kept and its plate
--                    shown only while true (a module's element: while that
--                    module is on)
--         waiting    function(entry) -> waits: true while it stands on a
--                    place of its own the store has not taken in yet (the
--                    Route arrow's from before 0.14): Reset all resets it
--                    too, so its reset lets that place go
--       The entry holds all of these (resize a boolean, group always set,
--       label always a string when it has a key or a name) and `moving`
--       ("plain" or Edit Layout's "layout"), `placing` and `scaling` (held
--       while Core or Edit Layout lays it: its post-hooks stand back). A
--       frame registered again gets its first entry back. A saved place is
--       put back at once and on every show (not for a `save` window), and on
--       a UI Scale change for the shown ones ("scale" topic, reason
--       "uiscale"). Every entry's OnShow / OnHide are hooked, so set them
--       BEFORE registering (SetScript drops hooks).
--   MelloUI:SavePosition(key, frame[, scale]) -> saved
--       the frame's place under key, by its entry's anchor; scale: a number
--       is kept with it (to a hundredth), false drops it, nil leaves it.
--       Always the store; a key an Edit Layout session holds leaves the
--       session (the outside write wins: LayoutSession.Release)
--   MelloUI:ForgetPosition(key)          the same rule
--   MelloUI:RestorePosition(key, frame) -> placed[, "combat"]
--       the saved scale, then the place, kept on the screen; false when
--       nothing is saved, or for a protected frame in combat
--   MelloUI:GetPosition(key) -> { point, relPoint, x, y, scale } or nil
--       point nil = BOTTOMLEFT, relPoint nil = CENTER; x, y in the frame's
--       own units. While a session holds the key: its pending place (nil
--       for a pending reset), so every put-back places pending values
--       without knowing it. Read only: change it through Save / Forget.
--       (A reset is Edit Layout's: LayoutSession.Reset, then Commit.)
--   MelloUI:MoverEntries()             the entries, in registration order
--   MelloUI:AddMoverHandle(frame, handle) -> added
--       one more handle a registered plainDrag "always" frame is dragged by
--       (the widget column's rows, 0.16.0); its drag as the first handle's
--   MelloUI:MoverEntry(frame) -> entry | nil
--   MelloUI:EntryLive(entry) -> live       its `when` true, the frame not forbidden
--   MelloUI:EntryWaiting(entry) -> waits   its `waiting` true
--   MelloUI:EntryShown(entry) -> shown     its `visible`, else IsShown (secret: false)
--   MelloUI:EntryRect(entry) -> l, b, w, h
--       UIParent units, nil when anything reads secret or not finite. A
--       hidden frame with no rect (and a 0 x 0 one with a placeholder) is
--       measured from its first anchor: the relative frame's rect (the
--       screen, or any frame whose rect reads plainly), the offsets and its
--       size (the placeholder's when 0), in its scale
--   MelloUI:EntryBase(entry) -> scale      its 100 %: base when a plain positive number, else 1
--   MelloUI:MoveEntry(entry, l, b) -> ok   BOTTOMLEFT to the screen's BOTTOMLEFT
--       at l, b (UI units), in the frame's own units; the Raw methods,
--       `placing` held; false (nothing done) for a protected frame in combat
--   MelloUI:ScaleEntry(entry, scale) -> ok the scale (Kit:SetFrameScale with
--       the Raw SetScale), `scaling` held; the same combat rule
--   MelloUI:PlaceEntryAt(entry, point, relTo, relPoint, x, y) -> ok
--       any anchor (Edit Mode's place), the Raw methods, `placing` held
--   MelloUI:AddMoverSource(fn)            fn() registers what its owner has
--       that is not registered yet (idempotent; Edit Layout runs every
--       source at each open and resume: the first-open rule, nothing made
--       at login); MelloUI:MoverSources() -> the list, in the order they came
--   MelloUI:EditingLayout() -> false      Core/EditLayout.lua's own answers
--       while Edit Layout shows; the plain drags wait meanwhile (not a
--       "tool"'s)
--   MelloUI:FitOnScreen(frame, extraRects) -> moved, dx, dy
--       a laid-out frame moved (its points shifted) just enough to be on
--       the screen, together with extraRects (a frame or a list of frames
--       that move with it; hidden ones do not count); one larger than the
--       screen keeps its top-left corner on it. dx, dy in its own units.
--   MelloUI.LayoutSession                 Edit Layout's pending changes (below)
-- Edit Mode's systems are moved and scaled only through their plain
-- <Method>Base methods (Raw), their SetPoint / SetScale post-hooked.
-- The bus's "mover" topic: ("registered", entry) at a registration,
-- ("shown", entry, shown) from each entry's OnShow / OnHide, ("released",
-- entry) when a session lets go of an entry it held (Save, Discard,
-- Abandon, Drop, Release): an owner that waited re-lays it then.
-- The store is UI Modifications' `positions` setting, which is in its
-- settings whether the module is on or off, so profiles, share strings and
-- the macro backup (when on) carry every place. Nothing is made or hooked
-- until an element registers (the 'scale' listener aside: one entry on the
-- bus); the follow hooks' after-combat frame is made the first time a put-
-- back waits for a fight's end.
--
-- The session (MelloUI.LayoutSession; in memory only, never saved). Only Edit
-- Layout's own paths write it (Set, Reset); SavePosition and ForgetPosition
-- always write the store.
--   Begin(onEnd) -> began                 a session on the store table as it
--                                         is now; onEnd(reason, n) once at its
--                                         end: "saved" (n changes), "discarded",
--                                         "abandoned" (n: why)
--   Active() -> active                    false once the store table is not the
--                                         one it began on (abandoned first)
--   Touch(entry) -> rec                   the first touch: its snapshot (every
--                                         point, the scale, shown), its follow
--                                         hook; entries of one key share a record
--                                         (each element's own snapshot kept)
--   Set(entry[, scale])                   its rect now, by its anchor, as its
--                                         pending place (scale as SavePosition's:
--                                         nil keeps the one it has; dropped at
--                                         exactly the 100 % it names)
--   Hang(entry)                           hung by its anchor from the pending
--                                         place, kept on the screen
--   Reset(entry)                          the pending reset: its base scale, the
--                                         preview (its default; a followed game
--                                         window without one closed), its reset
--                                         called only at Save
--   ResetAll() -> n                       Reset for every live entry but a "tool"'s
--                                         with a stored, pending or waiting place,
--                                         and every live `save` entry, once per key
--   Holds(entry), Pos(entry), IsReset(entry), Count(), Touched() -> entries
--   Differs(entry) -> bool                its change counts in Count() (a reset,
--                                         or a place unlike the stored one, else
--                                         its snapshot's; moved back: false)
--   Drop(entry)                           out of it, put back from its snapshot
--   Release(entry)                        out of it, not put back
--   Commit() -> saved, n                  Save: the session off FIRST, then in
--                                         one Batch the keyed places into the
--                                         store (a reset forgets and calls its
--                                         reset), each `save`'s save(frame, pos)
--                                         or reset; "released" for each
--   Discard()                             put back from the snapshots, the last
--                                         touched first (unreadable: the store,
--                                         else its default); no 'setting'
--   Abandon(reason)                       ended with NO put-back from the
--                                         snapshots where the store can place:
--                                         a profile load (RestartModules), the
--                                         installer, a replaced store
-- Every touched entry is held where its pending place says while the session
-- is active: its SetPoint / SetScale post-hooks hang it again after anyone
-- else's call (idle outside a session, guarded by `placing`). Owners that lay
-- their element from their own settings wait while it Holds it and lay it
-- again on "released".
--------------------------------------------------------------------------------

do
	local Num = Safe.Number
	local Finite = Safe.Finite
	local Secret = Safe.IsSecret
	local POSITIONS_MODULE = "UIModifications"

	-- where a point sits on its frame: 0 left / bottom .. 1 right / top
	local POINT_X = { TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0, TOP = 0.5, CENTER = 0.5, BOTTOM = 0.5,
		TOPRIGHT = 1, RIGHT = 1, BOTTOMRIGHT = 1 }
	local POINT_Y = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5,
		BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0 }
	local GROUPS = { own = true, window = true, hud = true, tool = true }

	local entries = {}                 -- in registration order
	local byFrame, byKey, byHandle = {}, {}, {}
	local sources = {}                 -- MelloUI:AddMoverSource's, in the order they came

	local LayoutSession = {}
	MelloUI.LayoutSession = LayoutSession
	-- the session while one runs: { store = the positions table it began on,
	-- onEnd, recs = { rec, ... } (first touch first), byEntry = { [entry] =
	-- rec }, byKey = { [key] = rec } }; rec = { entry, pos, reset, snap }
	local session = nil
	local Held, Later   -- (below)

	-- the one table of places, looked up each time (a profile load puts a
	-- new one there); create: made when missing
	local function Positions(create)
		local db = MelloUI.db
		local modules = db and db.modules
		if type(modules) ~= "table" then
			return nil
		end
		local um = modules[POSITIONS_MODULE]
		if type(um) ~= "table" then
			if not create then
				return nil
			end
			if MelloUI.modules[POSITIONS_MODULE] then
				um = MelloUI:GetModuleDB(POSITIONS_MODULE)
			else
				um = {}
				modules[POSITIONS_MODULE] = um
			end
		end
		local positions = um.positions
		if type(positions) ~= "table" then
			if not create then
				return nil
			end
			positions = {}
			um.positions = positions
		end
		return positions
	end

	-- the store's own entry for a key (never the pending one)
	local function Stored(key)
		local positions = key ~= nil and Positions(false)
		local pos = positions and positions[key]
		return type(pos) == "table" and pos or nil
	end

	-- written through the setting path, as every setting (the macro backup,
	-- when on, is written from there)
	local function Written(positions)
		MelloUI:NotifySettingChanged(POSITIONS_MODULE, "positions", positions)
	end

	-- Edit Mode's own SetPoint / ClearAllPoints / SetScale / Hide on its
	-- systems leave tainted state behind when called from here (the damage
	-- meter's fight timer then failed on its secret combat duration, user
	-- 2026-09-23); the plain methods it kept aside (<Method>Base) are used
	-- where a frame has them. A frame without the overrides answers with its own.
	local function Raw(frame, method)
		return frame[method .. "Base"] or frame[method]
	end

	-- a protected frame in combat cannot be moved or scaled by an addon
	local function Locked(frame)
		if not (InCombatLockdown and InCombatLockdown()) then
			return false
		end
		local ok, protected = pcall(frame.IsProtected, frame)
		return ok and not Secret(protected) and protected and true or false
	end

	-- left, bottom, width, height in the frame's own units; nil when any
	-- reads secret or is missing
	local function Rect(frame)
		local ok, l, b, w, h = pcall(frame.GetRect, frame)
		if not ok then
			return nil
		end
		l, b, w, h = Num(l), Num(b), Num(w), Num(h)
		if not (l and b and w and h) then
			return nil
		end
		return l, b, w, h
	end

	local function Size(frame)
		local ok, w, h = pcall(frame.GetSize, frame)
		if not ok then
			return nil
		end
		return Num(w), Num(h)
	end

	-- the frame's effective scale, and the screen's scale and size (in its
	-- units); nil when any cannot be read plainly
	local function Screen(frame)
		local okS, fs = pcall(frame.GetEffectiveScale, frame)
		local okU, us = pcall(UIParent.GetEffectiveScale, UIParent)
		local okP, sw, sh = pcall(UIParent.GetSize, UIParent)
		fs, us = okS and Num(fs), okU and Num(us)
		sw, sh = okP and Num(sw), okP and Num(sh)
		if not (fs and us and sw and sh) or fs <= 0 or us <= 0 or sw <= 0 or sh <= 0 then
			return nil
		end
		return fs, us, sw, sh
	end

	-- How far a box (in pixels) must move to be on a screen of sw x sh
	-- pixels (user 2026-09-24: "UI Scaling Break the UI"): past the right or
	-- the bottom it comes in; one larger than the screen keeps its left and
	-- top edges on it.
	local function Pull(left, bottom, right, top, sw, sh)
		local dx, dy = 0, 0
		if right > sw then
			dx = sw - right
		end
		if left + dx < 0 then
			dx = -left
		end
		if bottom < 0 then
			dy = -bottom
		end
		if top + dy > sh then
			dy = sh - top
		end
		return dx, dy
	end

	-- a box (pixels) grown by a shown frame's rect
	local function Grow(extra, left, bottom, right, top)
		if type(extra) ~= "table" or not extra.GetRect then
			return left, bottom, right, top
		end
		local okV, shown = pcall(extra.IsShown, extra)
		if not okV or Secret(shown) or not shown then
			return left, bottom, right, top
		end
		local okS, es = pcall(extra.GetEffectiveScale, extra)
		es = okS and Num(es)
		local l, b, w, h = Rect(extra)
		if not (es and l) or es <= 0 or w <= 0 or h <= 0 then
			return left, bottom, right, top
		end
		l, b = l * es, b * es
		return math.min(left, l), math.min(bottom, b), math.max(right, l + w * es), math.max(top, b + h * es)
	end

	-- extras: a frame, or a list of frames
	local function Union(extras, left, bottom, right, top)
		if type(extras) ~= "table" then
			return left, bottom, right, top
		end
		if extras.GetRect then
			return Grow(extras, left, bottom, right, top)
		end
		for i = 1, #extras do
			left, bottom, right, top = Grow(extras[i], left, bottom, right, top)
		end
		return left, bottom, right, top
	end

	-- an entry's `with`: a frame or a list, or a function's answer (looked up
	-- now: the Quest List is made on the map's first show)
	local function WithOf(entry)
		local with = entry and entry.with
		if type(with) == "function" then
			local ok, got = pcall(with, entry)
			return (ok and type(got) == "table") and got or nil
		end
		return with
	end

	-- The offsets that keep a frame of w x h (its own units) on the screen
	-- when it is hung by `point` from the screen's `relPoint` at x, y. Its
	-- extras are measured where they are now, against the frame where it is
	-- now (they move with it), before its anchors go.
	local function FitOffsets(frame, point, relPoint, x, y, w, h, extras)
		local fs, us, sw, sh = Screen(frame)
		if not fs or not w or not h or w <= 0 or h <= 0 then
			return x, y
		end
		local SW, SH = sw * us, sh * us
		local left = POINT_X[relPoint] * SW + (x - POINT_X[point] * w) * fs
		local bottom = POINT_Y[relPoint] * SH + (y - POINT_Y[point] * h) * fs
		local right, top = left + w * fs, bottom + h * fs
		if extras ~= nil then
			local l, b, cw, ch = Rect(frame)
			if l and cw > 0 and ch > 0 then
				local cl, cb = l * fs, b * fs
				local cr, ct = cl + cw * fs, cb + ch * fs
				local ul, ub, ur, ut = Union(extras, cl, cb, cr, ct)
				left, bottom, right, top = left + (ul - cl), bottom + (ub - cb), right + (ur - cr), top + (ut - ct)
			end
		end
		local dx, dy = Pull(left, bottom, right, top, SW, SH)
		return x + dx / fs, y + dy / fs
	end

	-- every point of a frame moved by dx, dy (its own units), its anchoring
	-- kept; the points read into these lists, emptied after
	local sP, sRel, sRP, sX, sY = {}, {}, {}, {}, {}
	local function Shift(frame, dx, dy)
		local okN, n = pcall(frame.GetNumPoints, frame)
		n = okN and Num(n)
		if not n or n < 1 then
			return false
		end
		local plain = true
		for i = 1, n do
			local ok, p, rel, rp, x, y = pcall(frame.GetPoint, frame, i)
			if not ok or Secret(p) or Secret(rel) or Secret(rp) or Secret(x) or Secret(y) then
				plain = false
			else
				sP[i], sRel[i], sRP[i], sX[i], sY[i] = p, rel, rp, Num(x) or 0, Num(y) or 0
			end
		end
		local ok = false
		if plain then
			ok = pcall(Raw(frame, "ClearAllPoints"), frame)
			if ok then
				local set = Raw(frame, "SetPoint")
				for i = 1, n do
					pcall(set, frame, sP[i], sRel[i], sRP[i], sX[i] + dx, sY[i] + dy)
				end
			end
		end
		for i = 1, n do
			sP[i], sRel[i], sRP[i], sX[i], sY[i] = nil, nil, nil, nil, nil
		end
		return ok
	end

	function MelloUI:FitOnScreen(frame, extraRects)
		if type(frame) ~= "table" or not frame.GetRect then
			return false
		end
		local fs, us, sw, sh = Screen(frame)
		local l, b, w, h = Rect(frame)
		if not (fs and l) or w <= 0 or h <= 0 then
			return false
		end
		local left, bottom = l * fs, b * fs
		local right, top
		left, bottom, right, top = Union(extraRects, left, bottom, left + w * fs, bottom + h * fs)
		local dx, dy = Pull(left, bottom, right, top, sw * us, sh * us)
		if (dx == 0 and dy == 0) or Locked(frame) then
			return false
		end
		dx, dy = dx / fs, dy / fs
		return Shift(frame, dx, dy), dx, dy
	end

	local function Round(v, step)
		return math.floor(v * step + 0.5) / step
	end

	-- where a frame sits, by `anchor`: point, relPoint, x, y (its own units,
	-- to a tenth; the store's measure); nil when it cannot be read
	local function Measure(frame, anchor)
		local point, relPoint = anchor or "BOTTOMLEFT", anchor or "CENTER"
		local fs, us, sw, sh = Screen(frame)
		local l, b, w, h = Rect(frame)
		if not (fs and l) then
			return nil
		end
		-- the screen in the frame's own units
		local k = us / fs
		local x = l + POINT_X[point] * w - POINT_X[relPoint] * sw * k
		local y = b + POINT_Y[point] * h - POINT_Y[relPoint] * sh * k
		return point, relPoint, Round(x, 10), Round(y, 10)
	end

	-- the scale set with its plain SetScale (Raw), its backgrounds laid
	-- again only when its scale really changed (Kit:SetFrameScale; the kit
	-- looked up now: it loads after this file)
	local function SetFrameScale(frame, scale)
		local Kit = MelloUI.Kit
		if Kit and Kit.SetFrameScale then
			Kit:SetFrameScale(frame, scale, Raw(frame, "SetScale"))
		else
			Raw(frame, "SetScale")(frame, scale)
		end
	end

	-- a place laid on a frame: its scale first, while it still hangs where
	-- it was, then its anchor, kept on the screen with its `with`
	local function PlaceNow(frame, entry, point, relPoint, pos)
		local scale = Finite(tonumber(pos.scale))
		if scale and scale > 0 then
			SetFrameScale(frame, scale)
		end
		-- measured before the anchors go: a window sized by them reads 0
		-- wide after
		local w, h = Size(frame)
		local x, y = FitOffsets(frame, point, relPoint, Finite(tonumber(pos.x)) or 0, Finite(tonumber(pos.y)) or 0, w, h,
			entry and WithOf(entry))
		Raw(frame, "ClearAllPoints")(frame)
		Raw(frame, "SetPoint")(frame, point, UIParent, relPoint, x, y)
	end

	-- RestorePosition's and Hang's placing: `placing` held on its entry (its
	-- post-hooks stand back); placed, or false[, "combat"]
	local function Place(frame, entry, pos)
		local point, relPoint = pos.point or "BOTTOMLEFT", pos.relPoint or "CENTER"
		if not (POINT_X[point] and POINT_X[relPoint]) then
			return false
		end
		if Locked(frame) then
			return false, "combat"
		end
		local was = entry and entry.placing
		if entry then
			entry.placing = true
		end
		local ok, err = pcall(PlaceNow, frame, entry, point, relPoint, pos)
		if entry then
			entry.placing = was
		end
		if not ok then
			Report(err)
			return false
		end
		return true
	end

	-- whether an entry is live (MelloUI:EntryLive) and shown (EntryShown)
	local function Live(entry)
		local frame = entry.frame
		if frame.IsForbidden then
			local ok, forbidden = pcall(frame.IsForbidden, frame)
			if not ok or Secret(forbidden) or forbidden then
				return false
			end
		end
		local when = entry.when
		if when then
			local ok, live = pcall(when, entry)
			if not ok then
				Report(live)
				return false
			end
			return (not Secret(live) and live) and true or false
		end
		return true
	end

	-- a place of its own the store has not taken in yet (its `waiting`)
	local function Waiting(entry)
		local waiting = entry.waiting
		if not waiting then
			return false
		end
		local ok, waits = pcall(waiting, entry)
		if not ok then
			Report(waits)
			return false
		end
		return (not Secret(waits) and waits) and true or false
	end

	local function Shown(entry)
		local visible = entry.visible
		if visible then
			local ok, shown = pcall(visible, entry)
			return (ok and not Secret(shown) and shown) and true or false
		end
		local frame = entry.frame
		local ok, shown = pcall(frame.IsShown, frame)
		return (ok and not Secret(shown) and shown) and true or false
	end

	function MelloUI:GetPosition(key)
		if key == nil then
			return nil
		end
		local rec = session and session.byKey[key]
		if rec and LayoutSession.Active() then
			if rec.reset then
				return nil
			end
			if rec.pos then
				return rec.pos
			end
		end
		return Stored(key)
	end

	function MelloUI:SavePosition(key, frame, scale)
		if key == nil or type(frame) ~= "table" then
			return false
		end
		local entry = byKey[key]
		local point, relPoint, x, y = Measure(frame, entry and entry.anchor)
		if not point then
			return false
		end
		local positions = Positions(true)
		if not positions then
			return false
		end
		local pos = positions[key]
		if type(pos) ~= "table" then
			pos = {}
			positions[key] = pos
		end
		-- compact: a tenth of a unit, the scale to a hundredth, the points
		-- only when not the mover's own
		pos.point = point ~= "BOTTOMLEFT" and point or nil
		pos.relPoint = relPoint ~= "CENTER" and relPoint or nil
		pos.x, pos.y = x, y
		if scale == false then
			pos.scale = nil
		elseif Num(scale) and scale > 0 then
			pos.scale = Round(scale, 100)
		end
		Written(positions)
		-- (an Edit Layout session that held it lets it go: this write wins)
		local rec = session and session.byKey[key]
		if rec then
			LayoutSession.Release(rec.entry)
		end
		return true
	end

	function MelloUI:ForgetPosition(key)
		local positions = key ~= nil and Positions(false)
		if positions and positions[key] ~= nil then
			positions[key] = nil
			Written(positions)
		end
		local rec = key ~= nil and session and session.byKey[key]
		if rec then
			LayoutSession.Release(rec.entry)
		end
	end

	function MelloUI:RestorePosition(key, frame)
		local pos = self:GetPosition(key)
		if not pos or type(frame) ~= "table" then
			return false
		end
		return Place(frame, byFrame[frame], pos)
	end

	-- Core's handlers go through a /melloperf scope of their own, one handler
	-- for every frame (Shared). Core loads before Perf.lua, so its scope is
	-- opened by Anim.lua while the files load (MelloUI.CorePerf): one asked
	-- for here after login would open a file load that never closes
	-- (review, 2026-09-25). Without it, plain hooks.
	local wrapped = {}
	local function Wrap(label, fn, kind)
		local scope = MelloUI.CorePerf
		if not (scope and scope.Shared) then
			return fn
		end
		local w = wrapped[fn]
		if not w then
			w = scope.Shared(label, fn, kind)
			wrapped[fn] = w
		end
		return w
	end

	local function Hook(frame, script, label, fn)
		local scope = MelloUI.CorePerf
		if scope and scope.Shared and scope.HookScript then
			return scope.HookScript(frame, script, Wrap(label, fn, "script"))
		end
		return frame:HookScript(script, fn)
	end

	--------------------------------------------------------------------------
	-- The follow put-back and the session's hold: one post-hook pair per
	-- frame (SetPoint, SetScale), made at a `follow` registration or a first
	-- touch; idle for an entry that is neither followed nor held
	--------------------------------------------------------------------------

	-- a followed entry put back from the store (its pending place while held)
	local function Follow(entry)
		if entry.save or entry.key == nil or not Live(entry) then
			return
		end
		local pos = MelloUI:GetPosition(entry.key)
		if not pos then
			return
		end
		local placed, why = Place(entry.frame, entry, pos)
		if not placed and why == "combat" then
			Later(entry)
		end
	end

	-- held by the session: hung from its pending place; else followed
	local function Keep(entry)
		local rec = Held(entry)
		if rec then
			if rec.pos then
				LayoutSession.Hang(entry)
			end
		elseif entry.follow then
			Follow(entry)
		end
	end

	local OnSetPoint = function(frame)
		local entry = byFrame[frame]
		if not entry or entry.placing or entry.scaling or entry.moving then
			return
		end
		if entry.follow or session then
			local wb = MelloUI.Perf and MelloUI.Perf.WriteBack
			if wb then
				wb("mover: a window put back after the game moved it")
			end
			Keep(entry)
		end
	end

	local OnSetScale = function(frame)
		local entry = byFrame[frame]
		if not entry or entry.placing or entry.scaling or entry.moving then
			return
		end
		-- someone else scaled it (Edit Mode's Size, the panel manager's fit):
		-- that is the game's scale for it, its 100 %
		if entry.follow then
			local ok, scale = pcall(frame.GetScale, frame)
			scale = ok and Finite(scale)
			if scale and scale > 0 then
				entry.base = scale
			end
		end
		local rec = Held(entry)
		if rec then
			if rec.pos then
				LayoutSession.Hang(entry)
			end
			return
		end
		if entry.follow then
			local pos = entry.key ~= nil and Stored(entry.key)
			if pos and pos.scale then
				Follow(entry)
			end
		end
	end

	local hooked = setmetatable({}, { __mode = "k" })   -- [frame] = true: its pair of post-hooks made
	local function HookFrame(frame)
		if hooked[frame] then
			return
		end
		hooked[frame] = true
		if type(frame.SetPoint) == "function" then
			hooksecurefunc(frame, "SetPoint", Wrap("mover: put back after a SetPoint", OnSetPoint, "hook"))
		end
		if type(frame.SetScale) == "function" then
			hooksecurefunc(frame, "SetScale", Wrap("mover: put back after a SetScale", OnSetScale, "hook"))
		end
	end

	-- the game lays its panels out again on every show / hide of one, and the
	-- bags on every open (UpdateContainerFrameAnchors): the followed ones
	-- that show go back where they were put after each of those
	local function PutBackShown()
		for i = 1, #entries do
			local entry = entries[i]
			if entry.follow and not (entry.moving or entry.placing) and Shown(entry) then
				Keep(entry)
			end
		end
	end
	local panelHooks = false
	local function HookPanelLayout()
		if panelHooks then
			return
		end
		panelHooks = true
		for _, name in ipairs({ "UpdateUIPanelPositions", "UpdateContainerFrameAnchors" }) do
			if type(_G[name]) == "function" then
				hooksecurefunc(name, Wrap("mover: put back after the panel layout", PutBackShown, "hook"))
			end
		end
	end

	-- a put-back refused in combat (a protected window): once the fight is
	-- over, for the ones that show then. The frame is made the first time.
	local waiting = {}   -- [entry] = true
	local combatFrame
	local function AfterCombat()
		combatFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
		for entry in pairs(waiting) do
			waiting[entry] = nil
			if Shown(entry) then
				Keep(entry)
			end
		end
	end
	Later = function(entry)
		waiting[entry] = true
		if not combatFrame then
			combatFrame = CreateFrame("Frame")
			combatFrame:SetScript("OnEvent", Wrap("mover: put back after the fight", AfterCombat, "script"))
		end
		combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	end

	--------------------------------------------------------------------------
	-- The plain drag ("always"): the frame's own StartMoving, saved at once
	--------------------------------------------------------------------------

	-- a plain drag let go: saved in the store (or by the window itself) and
	-- hung by its own anchor again, kept on the screen
	local function SaveEntry(entry)
		local frame = entry.frame
		if entry.save then
			local ok, err = pcall(entry.save, frame)
			if not ok then
				Report(err)
			end
		elseif entry.key ~= nil and MelloUI:SavePosition(entry.key, frame) then
			MelloUI:RestorePosition(entry.key, frame)
		end
	end

	-- a plain drag over: let go (saved, hung by its anchor again; stale: a
	-- drag left over from before a hide, only stopped). Edit Layout's own
	-- drag ("layout") is its to end.
	local function EndDrag(entry, stale)
		if entry.moving ~= "plain" then
			return
		end
		entry.moving = nil
		entry.frame:StopMovingOrSizing()
		if not stale then
			SaveEntry(entry)
		end
	end

	local function DragStart(handle)
		local entry = byHandle[handle]
		if not entry then
			return
		end
		-- a drag that never saw its OnDragStop (its window hidden while it
		-- was held): ended first, or the window could never be dragged or
		-- put back again (review, 2026-09-25); this drag saves its place
		if entry.moving == "plain" then
			EndDrag(entry, true)
		elseif entry.moving then
			return   -- (Edit Layout's)
		end
		if entry.plainDrag ~= "always" then
			return
		end
		-- while Edit Layout shows, its plate is the one way to move an
		-- element: only its tools (its own bar, the Configurator, the
		-- installer window) are dragged by themselves then
		if entry.group ~= "tool" and MelloUI:EditingLayout() then
			return
		end
		local frame = entry.frame
		if Locked(frame) then
			return
		end
		-- (locked in place by its own switch: the widget column's lock)
		if entry.locked then
			local ok, reason = pcall(entry.locked, entry)
			if not ok or reason then
				return
			end
		end
		frame:SetMovable(true)
		frame:StartMoving()
		entry.moving = "plain"
	end

	local function DragStop(handle)
		local entry = byHandle[handle]
		if entry and entry.moving == "plain" then
			EndDrag(entry)
		end
	end

	-- a window hidden while it is dragged (Esc, its close key) gets no
	-- OnDragStop: its drag ends here, where it was let go
	local function OnHide(frame)
		local entry = byFrame[frame]
		if not entry then
			return
		end
		if entry.moving == "plain" then
			EndDrag(entry)
		end
		MelloUI:Fire("mover", "shown", entry, false)
	end

	-- a saved place put back on every show (the window may have been laid
	-- elsewhere, or the screen changed, while it was hidden); a drag still
	-- marked from before it was hidden is over, its place not taken
	local function OnShow(frame)
		local entry = byFrame[frame]
		if not entry then
			return
		end
		if entry.moving == "plain" then
			EndDrag(entry, true)
		end
		if not entry.save and entry.key ~= nil and Live(entry) then
			local placed, why = MelloUI:RestorePosition(entry.key, frame)
			if not placed and why == "combat" and entry.follow then
				Later(entry)
			end
		end
		MelloUI:Fire("mover", "shown", entry, true)
	end

	function MelloUI:RegisterMover(frame, handle, opts)
		if type(frame) ~= "table" then
			return nil
		end
		local entry = byFrame[frame]
		if entry then
			return entry
		end
		if type(opts) ~= "table" then
			opts = {}
		end
		handle = type(handle) == "table" and handle or frame
		local key, name = opts.key, nil
		if frame.GetName then
			local ok, n = pcall(frame.GetName, frame)
			name = ok and Safe.Text(n) or nil
		end
		if key == nil then
			key = name
		end
		local anchor = opts.anchor
		local placeholder = opts.placeholder
		if placeholder ~= true and not (type(placeholder) == "table" and Finite(placeholder[1]) and Finite(placeholder[2])) then
			placeholder = nil
		end
		local label = opts.label
		if type(label) ~= "string" then
			label = type(key) == "string" and key or name
		end
		entry = {
			frame = frame, handle = handle, key = key,
			anchor = POINT_X[anchor] and anchor or nil,
			default = opts.default, save = opts.save, reset = opts.reset,
			min = opts.min, max = opts.max, base = opts.base, with = opts.with,
			-- (the old "unlocked" mode is gone: such a window moves in Edit
			-- Layout only)
			plainDrag = opts.plainDrag == "always" and "always" or false,
			label = label,
			page = type(opts.page) == "string" and opts.page or nil,
			group = GROUPS[opts.group] and opts.group or "own",
			placeholder = placeholder,
			visible = type(opts.visible) == "function" and opts.visible or nil,
			follow = opts.follow and true or nil,
			resize = opts.resize ~= false,
			settings = type(opts.settings) == "table" and opts.settings or nil,
			locked = type(opts.locked) == "function" and opts.locked or nil,
			note = type(opts.note) == "function" and opts.note or nil,
			resetLabel = type(opts.resetLabel) == "string" and opts.resetLabel or nil,
			when = type(opts.when) == "function" and opts.when or nil,
			waiting = type(opts.waiting) == "function" and opts.waiting or nil,
		}
		entries[#entries + 1] = entry
		byFrame[frame] = entry
		if key ~= nil and byKey[key] == nil then
			byKey[key] = entry
		end
		-- the handle's plain drag is Core's (a game window the game lays out
		-- keeps its handle as it is: it moves in Edit Layout only)
		if not entry.follow and not byHandle[handle] then
			byHandle[handle] = entry
			if handle.RegisterForDrag and entry.plainDrag then
				handle:RegisterForDrag("LeftButton")
			end
			if entry.plainDrag == "always" and handle.EnableMouse then
				handle:EnableMouse(true)
			end
			Hook(handle, "OnDragStart", "mover: drag start", DragStart)
			Hook(handle, "OnDragStop", "mover: drag stop", DragStop)
		end
		Hook(frame, "OnHide", "mover: hidden", OnHide)
		Hook(frame, "OnShow", "mover: shown (its saved place)", OnShow)
		if entry.follow then
			-- its 100 %: the game's own scale for it now, before a saved one
			-- is put on it
			if not (Num(entry.base) and entry.base > 0) then
				local ok, scale = pcall(frame.GetScale, frame)
				scale = ok and Finite(scale)
				entry.base = (scale and scale > 0) and scale or nil
			end
			HookFrame(frame)
			HookPanelLayout()
		end
		if not entry.save and key ~= nil and Live(entry) then
			local placed, why = MelloUI:RestorePosition(key, frame)
			if not placed and why == "combat" and entry.follow then
				Later(entry)
			end
		end
		-- no saved place and no anchor of its own: its default place (the game
		-- draws nothing for a frame with no anchor; user, 2026-09-26: the new
		-- Restock List never showed until it had been placed once)
		if entry.default and frame.GetNumPoints and not Locked(frame) then
			local okN, n = pcall(frame.GetNumPoints, frame)
			if okN and not Secret(n) and n == 0 then
				local okD, err = pcall(entry.default, frame)
				if not okD then
					Report(err)
				end
			end
		end
		MelloUI:Fire("mover", "registered", entry)
		return entry
	end

	function MelloUI:MoverEntries()
		return entries
	end

	function MelloUI:AddMoverHandle(frame, handle)
		local entry = byFrame[frame]
		if not (entry and entry.plainDrag == "always" and type(handle) == "table") or byHandle[handle] then
			return false
		end
		byHandle[handle] = entry
		if handle.RegisterForDrag then
			handle:RegisterForDrag("LeftButton")
		end
		Hook(handle, "OnDragStart", "mover: drag start", DragStart)
		Hook(handle, "OnDragStop", "mover: drag stop", DragStop)
		return true
	end

	function MelloUI:MoverEntry(frame)
		return frame ~= nil and byFrame[frame] or nil
	end

	function MelloUI:EntryLive(entry)
		if type(entry) ~= "table" or type(entry.frame) ~= "table" then
			return false
		end
		return Live(entry)
	end

	function MelloUI:EntryWaiting(entry)
		if type(entry) ~= "table" then
			return false
		end
		return Waiting(entry)
	end

	function MelloUI:EntryShown(entry)
		if type(entry) ~= "table" or type(entry.frame) ~= "table" then
			return false
		end
		return Shown(entry)
	end

	-- a hidden frame's rect from its first anchor, UI units (EntryRect); k:
	-- its scale against the screen's
	local function AnchorRect(entry, frame, k)
		local okP, p, rel, rp, x, y = pcall(frame.GetPoint, frame, 1)
		if not okP or Secret(p) or Secret(rel) or Secret(rp) or Secret(x) or Secret(y) then
			return nil
		end
		rp = rp or p
		if not (POINT_X[p] and POINT_X[rp]) then
			return nil
		end
		local rl, rb, rw, rh
		if rel == nil or rel == UIParent then
			local ok, sw, sh = pcall(UIParent.GetSize, UIParent)
			sw, sh = ok and Finite(sw), ok and Finite(sh)
			if not (sw and sh) then
				return nil
			end
			rl, rb, rw, rh = 0, 0, sw, sh
		else
			-- any frame whose rect reads plainly (the one screen-rect reader)
			local left, bottom, right, top = Safe.ScreenRect(rel)
			local okU, us = pcall(UIParent.GetEffectiveScale, UIParent)
			us = okU and Finite(us)
			if not (left and us) or us <= 0 then
				return nil
			end
			rl, rb, rw, rh = left / us, bottom / us, (right - left) / us, (top - bottom) / us
		end
		local w, h = Size(frame)
		w, h = (Finite(w) or 0) * k, (Finite(h) or 0) * k
		local ph = entry.placeholder
		if (w <= 0 or h <= 0) and type(ph) == "table" then
			w, h = ph[1], ph[2]
		end
		local ax = rl + POINT_X[rp] * rw + (Finite(x) or 0) * k
		local ay = rb + POINT_Y[rp] * rh + (Finite(y) or 0) * k
		return ax - POINT_X[p] * w, ay - POINT_Y[p] * h, w, h
	end

	function MelloUI:EntryRect(entry)
		local frame = type(entry) == "table" and entry.frame
		if type(frame) ~= "table" or not frame.GetRect then
			return nil
		end
		local okS, fs = pcall(frame.GetEffectiveScale, frame)
		local okU, us = pcall(UIParent.GetEffectiveScale, UIParent)
		fs, us = okS and Finite(fs), okU and Finite(us)
		if not (fs and us) or fs <= 0 or us <= 0 then
			return nil
		end
		local k = fs / us
		local ok, l, b, w, h = pcall(frame.GetRect, frame)
		if not ok or Secret(l) or Secret(b) or Secret(w) or Secret(h) then
			return nil
		end
		if l ~= nil then
			l, b, w, h = Finite(l), Finite(b), Finite(w), Finite(h)
			if not (l and b and w and h) then
				return nil
			end
			if (w > 0 and h > 0) or not entry.placeholder then
				return l * k, b * k, w * k, h * k
			end
		end
		return AnchorRect(entry, frame, k)
	end

	function MelloUI:EntryBase(entry)
		local base = type(entry) == "table" and entry.base
		return (Finite(base) and base > 0) and base or 1
	end

	local function MovePoints(frame, x, y)
		Raw(frame, "ClearAllPoints")(frame)
		Raw(frame, "SetPoint")(frame, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
	end

	function MelloUI:MoveEntry(entry, l, b)
		local frame = type(entry) == "table" and entry.frame
		l, b = Finite(l), Finite(b)
		if type(frame) ~= "table" or not (l and b) or Locked(frame) then
			return false
		end
		local okS, fs = pcall(frame.GetEffectiveScale, frame)
		local okU, us = pcall(UIParent.GetEffectiveScale, UIParent)
		fs, us = okS and Finite(fs), okU and Finite(us)
		if not (fs and us) or fs <= 0 or us <= 0 then
			return false
		end
		local k = us / fs
		local was = entry.placing
		entry.placing = true
		local ok, err = pcall(MovePoints, frame, l * k, b * k)
		entry.placing = was
		if not ok then
			Report(err)
			return false
		end
		return true
	end

	function MelloUI:ScaleEntry(entry, scale)
		local frame = type(entry) == "table" and entry.frame
		scale = Finite(scale)
		if type(frame) ~= "table" or not scale or scale <= 0 or Locked(frame) then
			return false
		end
		local was = entry.scaling
		entry.scaling = true
		local ok, err = pcall(SetFrameScale, frame, scale)
		entry.scaling = was
		if not ok then
			Report(err)
			return false
		end
		return true
	end

	local function PlaceAt(frame, point, relTo, relPoint, x, y)
		Raw(frame, "ClearAllPoints")(frame)
		Raw(frame, "SetPoint")(frame, point, relTo, relPoint, x, y)
	end

	function MelloUI:PlaceEntryAt(entry, point, relTo, relPoint, x, y)
		local frame = type(entry) == "table" and entry.frame
		if type(frame) ~= "table" or not (POINT_X[point] and POINT_X[relPoint]) or Locked(frame) then
			return false
		end
		relTo = type(relTo) == "table" and relTo or UIParent
		local was = entry.placing
		entry.placing = true
		local ok, err = pcall(PlaceAt, frame, point, relTo, relPoint, Finite(x) or 0, Finite(y) or 0)
		entry.placing = was
		if not ok then
			Report(err)
			return false
		end
		return true
	end

	function MelloUI:AddMoverSource(fn)
		if type(fn) ~= "function" then
			return
		end
		for i = 1, #sources do
			if sources[i] == fn then
				return
			end
		end
		sources[#sources + 1] = fn
	end

	function MelloUI:MoverSources()
		return sources
	end

	-- (Core/EditLayout.lua replaces it: true while Edit Layout shows)
	function MelloUI:EditingLayout()
		return false
	end

	--------------------------------------------------------------------------
	-- The session (the API in the block's header)
	--------------------------------------------------------------------------

	-- the record of an entry the active session holds (the store replaced
	-- meanwhile: the session is abandoned first, nil)
	Held = function(entry)
		local s = session
		if not s then
			return nil
		end
		local rec = s.byEntry[entry] or (entry.key ~= nil and s.byKey[entry.key]) or nil
		if rec and LayoutSession.Active() then
			return rec
		end
		return nil
	end

	-- the frame as it is now: every point (plain reads; a secret one, or
	-- none, makes it unreadable), the scale, shown, and its place measured
	-- by its anchor (the change count's reference for a `save` window)
	local function Snapshot(entry)
		local frame = entry.frame
		local snap = { points = {} }
		local okN, n = pcall(frame.GetNumPoints, frame)
		n = okN and Num(n)
		if not n or n < 1 then
			snap.unreadable = true
		else
			for i = 1, n do
				local ok, p, rel, rp, x, y = pcall(frame.GetPoint, frame, i)
				if not ok or Secret(p) or Secret(rel) or Secret(rp) or Secret(x) or Secret(y) or type(p) ~= "string" then
					snap.unreadable = true
					break
				end
				snap.points[i] = { p, rel, rp, Num(x) or 0, Num(y) or 0 }
			end
		end
		local okS, scale = pcall(frame.GetScale, frame)
		snap.scale = okS and Finite(scale) or nil
		snap.shown = Shown(entry)
		local point, relPoint, x, y = Measure(frame, entry.anchor)
		if point then
			snap.pos = { point = point ~= "BOTTOMLEFT" and point or nil, relPoint = relPoint ~= "CENTER" and relPoint or nil,
				x = x, y = y }
			local base = MelloUI:EntryBase(entry)
			if snap.scale and math.abs(snap.scale - base) > 0.001 then
				snap.pos.scale = Round(snap.scale, 100)
			end
		end
		return snap
	end

	-- a frame back where its snapshot had it; false when it has no readable one
	local function Unwind(rec)
		local entry, snap = rec.entry, rec.snap
		local frame = entry.frame
		if snap.unreadable then
			return false
		end
		if Locked(frame) then
			if entry.follow then
				Later(entry)
			end
			return true
		end
		local was = entry.placing
		entry.placing = true
		local ok, err = pcall(function()
			if snap.scale and snap.scale > 0 then
				SetFrameScale(frame, snap.scale)
			end
			Raw(frame, "ClearAllPoints")(frame)
			local set = Raw(frame, "SetPoint")
			for i = 1, #snap.points do
				local pt = snap.points[i]
				set(frame, pt[1], pt[2], pt[3], pt[4], pt[5])
			end
		end)
		entry.placing = was
		if not ok then
			Report(err)
		end
		return true
	end

	local function Default(entry)
		if not entry.default then
			return false
		end
		local was = entry.placing
		entry.placing = true
		local ok, placed, line = pcall(entry.default, entry.frame)
		entry.placing = was
		if not ok then
			Report(placed)
			return false
		end
		return placed ~= false, line
	end

	-- a record's elements put back: the first touched from its snapshot
	-- (unreadable: the store, else its default), then every other element of
	-- its key from its own
	local function Undo(rec)
		local entry = rec.entry
		if not Unwind(rec) and not (entry.key ~= nil and not entry.save and MelloUI:RestorePosition(entry.key, entry.frame)) then
			Default(entry)
		end
		local more = rec.more
		for i = 1, more and #more or 0 do
			Unwind(more[i])
		end
	end

	local function Remove(s, rec)
		local recs = s.recs
		for i = #recs, 1, -1 do
			if recs[i] == rec then
				table.remove(recs, i)
			end
		end
		for e, r in pairs(s.byEntry) do
			if r == rec then
				s.byEntry[e] = nil
			end
		end
		for k, r in pairs(s.byKey) do
			if r == rec then
				s.byKey[k] = nil
			end
		end
	end

	local function Released(recs)
		for i = 1, #recs do
			MelloUI:Fire("mover", "released", recs[i].entry)
		end
	end

	local function Ended(s, reason, extra)
		if s.onEnd then
			local ok, err = pcall(s.onEnd, reason, extra)
			if not ok then
				Report(err)
			end
		end
	end

	-- two places alike: the same anchor, x and y within 0.05 units, the
	-- scale within 0.005 (none: its 100 %)
	local function Alike(a, b, base)
		if a == nil or b == nil then
			return a == b
		end
		if (a.point or "BOTTOMLEFT") ~= (b.point or "BOTTOMLEFT") or (a.relPoint or "CENTER") ~= (b.relPoint or "CENTER") then
			return false
		end
		if math.abs((Num(a.x) or 0) - (Num(b.x) or 0)) > 0.05 or math.abs((Num(a.y) or 0) - (Num(b.y) or 0)) > 0.05 then
			return false
		end
		return math.abs((Num(a.scale) or base) - (Num(b.scale) or base)) <= 0.005
	end

	local function Copy(pos)
		return { point = pos.point, relPoint = pos.relPoint, x = pos.x, y = pos.y, scale = pos.scale }
	end

	function LayoutSession.Begin(onEnd)
		if session and LayoutSession.Active() then
			return false
		end
		local store = Positions(true)
		if not store then
			return false
		end
		session = { store = store, onEnd = type(onEnd) == "function" and onEnd or nil, recs = {}, byEntry = {}, byKey = {} }
		return true
	end

	function LayoutSession.Active()
		local s = session
		if not s then
			return false
		end
		if Positions(false) ~= s.store then
			LayoutSession.Abandon("store")
			return false
		end
		return true
	end

	function LayoutSession.Touch(entry)
		if type(entry) ~= "table" or byFrame[entry.frame] == nil or not LayoutSession.Active() then
			return nil
		end
		local s = session
		local rec = s.byEntry[entry] or (entry.key ~= nil and s.byKey[entry.key]) or nil
		if rec then
			if s.byEntry[entry] == nil then
				-- another element of the key (a whisper popup after the
				-- stand-in): its own snapshot, so Discard and Drop put it
				-- back too
				rec.more = rec.more or {}
				rec.more[#rec.more + 1] = { entry = entry, snap = Snapshot(entry) }
			end
			s.byEntry[entry] = rec
			return rec
		end
		rec = { entry = entry, reset = false, snap = Snapshot(entry) }
		s.recs[#s.recs + 1] = rec
		s.byEntry[entry] = rec
		if entry.key ~= nil then
			s.byKey[entry.key] = rec
		end
		HookFrame(entry.frame)
		return rec
	end

	-- the frame's place now, by its anchor, as the pending place; scale as
	-- SavePosition's (nil: the one it has kept -- the pending one, else the
	-- stored one, else a `save` element's own from its snapshot, which its
	-- owner set; none after a reset that laid no place: Reset scaled it to
	-- its 100 %, and the store's old scale is no longer it), dropped at
	-- exactly the 100 % its entry names
	local function Measured(rec, entry, scale, wasReset)
		local point, relPoint, x, y = Measure(entry.frame, entry.anchor)
		if not point then
			return false
		end
		local pos = { point = point ~= "BOTTOMLEFT" and point or nil, relPoint = relPoint ~= "CENTER" and relPoint or nil,
			x = x, y = y }
		if scale == nil then
			local was = rec.pos
			if not (was or wasReset) then
				was = (entry.key ~= nil and not entry.save and Stored(entry.key)) or (entry.save and rec.snap.pos) or nil
			end
			pos.scale = was and Finite(was.scale) or nil
		elseif Finite(scale) and scale > 0 then
			local base = entry.base
			if not (Finite(base) and base > 0 and math.abs(scale - base) <= 0.001) then
				pos.scale = Round(scale, 100)
			end
		end
		rec.pos = pos
		return true
	end

	function LayoutSession.Set(entry, scale)
		local rec = LayoutSession.Touch(entry)
		if not rec then
			return false
		end
		local wasReset = rec.reset
		rec.reset = false
		return Measured(rec, entry, scale, wasReset)
	end

	function LayoutSession.Hang(entry)
		local rec = type(entry) == "table" and Held(entry)
		if not (rec and rec.pos) then
			return false
		end
		local placed, why = Place(entry.frame, entry, rec.pos)
		if not placed and why == "combat" then
			Later(entry)
		end
		return placed
	end

	function LayoutSession.Reset(entry)
		local rec = LayoutSession.Touch(entry)
		if not rec then
			return false
		end
		rec.reset, rec.pos = true, nil
		local frame = entry.frame
		-- its standard size (one whose size is set elsewhere keeps it)
		if entry.resize ~= false then
			MelloUI:ScaleEntry(entry, MelloUI:EntryBase(entry))
		end
		-- the preview of its standard place: its default; a game window the
		-- game lays out closed (it opens afresh at the game's place; never
		-- from here while the Gamepad UI is on, the freeze rule)
		if entry.default then
			local placed, line = Default(entry)
			if placed then
				Measured(rec, entry, false)
			elseif type(line) == "string" then
				MelloUI:Print(line)
			end
		elseif entry.follow and Shown(entry) and not Locked(frame) and not Safe.GamepadUI() then
			local was = entry.placing
			entry.placing = true
			local ok, err = pcall(Raw(frame, "Hide"), frame)
			entry.placing = was
			if not ok then
				Report(err)
			end
		end
		return true
	end

	function LayoutSession.ResetAll()
		if not LayoutSession.Active() then
			return 0
		end
		local n, done = 0, {}
		for i = 1, #entries do
			local entry = entries[i]
			local key = entry.key
			if entry.group ~= "tool" and not (key ~= nil and done[key]) and Live(entry) then
				local rec = Held(entry)
				if entry.save or (key ~= nil and (Stored(key) ~= nil or (rec and rec.pos ~= nil))) or Waiting(entry) then
					if key ~= nil then
						done[key] = true
					end
					if LayoutSession.Reset(entry) then
						n = n + 1
					end
				end
			end
		end
		return n
	end

	function LayoutSession.Holds(entry)
		return type(entry) == "table" and Held(entry) ~= nil
	end

	function LayoutSession.Pos(entry)
		local rec = type(entry) == "table" and Held(entry)
		return (rec and not rec.reset) and rec.pos or nil
	end

	function LayoutSession.IsReset(entry)
		local rec = type(entry) == "table" and Held(entry)
		return (rec and rec.reset) and true or false
	end

	-- one record counts: a reset, or a pending place unlike the stored one
	-- (keyed, not `save`), else the snapshot's; a place moved back exactly is
	-- none
	local function Counts(rec)
		if rec.reset then
			return true
		end
		if not rec.pos then
			return false
		end
		local entry = rec.entry
		local was = (entry.key ~= nil and not entry.save and Stored(entry.key)) or rec.snap.pos
		return not Alike(rec.pos, was, MelloUI:EntryBase(entry))
	end

	function LayoutSession.Count()
		if not LayoutSession.Active() then
			return 0
		end
		local n = 0
		local recs = session.recs
		for i = 1, #recs do
			if Counts(recs[i]) then
				n = n + 1
			end
		end
		return n
	end

	-- this element's change counts (its plate's pending mark: Count's rule)
	function LayoutSession.Differs(entry)
		if not LayoutSession.Active() then
			return false
		end
		local rec = type(entry) == "table" and Held(entry) or nil
		return rec ~= nil and Counts(rec)
	end

	function LayoutSession.Touched()
		local list = {}
		if LayoutSession.Active() then
			for i, rec in ipairs(session.recs) do
				list[i] = rec.entry
			end
		end
		return list
	end

	function LayoutSession.Drop(entry)
		local rec = type(entry) == "table" and Held(entry)
		if not rec then
			return false
		end
		Remove(session, rec)
		Undo(rec)
		MelloUI:Fire("mover", "released", rec.entry)
		return true
	end

	function LayoutSession.Release(entry)
		local s = session
		local rec = s and type(entry) == "table" and (s.byEntry[entry] or (entry.key ~= nil and s.byKey[entry.key])) or nil
		if not rec then
			return false
		end
		Remove(s, rec)
		MelloUI:Fire("mover", "released", rec.entry)
		return true
	end

	-- Save's writes, each record in its own pcall (one that raises is
	-- reported; the rest still commit); true when a keyed place was written
	local function CommitOne(rec, positions)
		local entry = rec.entry
		if entry.save then
			if rec.reset then
				if entry.reset then
					entry.reset()
				end
			elseif rec.pos then
				entry.save(entry.frame, Copy(rec.pos))
			end
			return false
		end
		if rec.reset then
			local wrote = entry.key ~= nil and positions[entry.key] ~= nil
			if entry.key ~= nil then
				positions[entry.key] = nil
			end
			if entry.reset then
				entry.reset()
			end
			return wrote
		end
		if entry.key ~= nil and rec.pos then
			positions[entry.key] = Copy(rec.pos)
			return true
		end
		return false
	end

	local function CommitAll(recs)
		local positions = Positions(true)
		local wrote = false
		for i = 1, #recs do
			local ok, did = pcall(CommitOne, recs[i], positions)
			if not ok then
				Report(did)
			elseif did then
				wrote = true
			end
		end
		if wrote then
			Written(positions)
		end
	end

	function LayoutSession.Commit()
		if not LayoutSession.Active() then
			return false
		end
		local s = session
		local n = LayoutSession.Count()
		-- off FIRST: every read and write below is the store's, and the
		-- owners' own saves (through SavePosition) land there
		session = nil
		local ok, err = pcall(MelloUI.Batch, MelloUI, CommitAll, s.recs)
		if not ok then
			Report(err)
		end
		Released(s.recs)
		Ended(s, "saved", n)
		return true, n
	end

	function LayoutSession.Discard()
		if not LayoutSession.Active() then
			return false
		end
		local s = session
		session = nil
		local recs = s.recs
		-- (a window the reset closed stays closed: its stored place applies
		-- on its next show)
		for i = #recs, 1, -1 do
			Undo(recs[i])
		end
		Released(recs)
		Ended(s, "discarded")
		return true
	end

	function LayoutSession.Abandon(reason)
		local s = session
		if not s then
			return false
		end
		session = nil
		-- the store now (a profile's, about to be the installer's) is the
		-- truth: nothing put back over it from the snapshots
		local recs = s.recs
		for i = 1, #recs do
			local rec = recs[i]
			local entry = rec.entry
			if not entry.save then
				local live = Live(entry)
				local placed = live and entry.key ~= nil and Stored(entry.key) ~= nil and MelloUI:RestorePosition(entry.key, entry.frame)
				if not placed and not (live and Default(entry)) then
					Unwind(rec)
				end
			end
		end
		Released(recs)
		Ended(s, "abandoned", reason)
		return true
	end

	-- a new UI Scale or resolution: the shown elements with a saved place put
	-- back, so they stay on the new screen (the hidden ones on their next
	-- show); a pending place is the place here
	MelloUI:On("scale", function(reason)
		if reason ~= "uiscale" then
			return
		end
		for i = 1, #entries do
			local entry = entries[i]
			if not entry.moving and Shown(entry) and Live(entry) then
				local rec = Held(entry)
				if rec then
					if rec.pos then
						LayoutSession.Hang(entry)
					end
				elseif not entry.save and entry.key ~= nil then
					local placed, why = MelloUI:RestorePosition(entry.key, entry.frame)
					if not placed and why == "combat" and entry.follow then
						Later(entry)
					end
				end
			end
		end
	end, "Core mover")
end

local copyFrame

-- The copy window (/mellolog, the dumps, a profile's share string): a large
-- text box to select and copy from. In PASTE mode (MelloUI:ShowPaste) the
-- box takes typing and Import hands the text on; otherwise whatever is typed
-- is put back at once. An own window on the one shell (WINDOW-RULES 6; the
-- audit of 2026-09-29: it was the last one on the game's templates), built on
-- its first open: the corner ring, its title on the plate in the title face,
-- the flat close, Escape, its place in the one mover (the store's 'copy',
-- dragged by its top at any time, back in the middle with its Reset in Edit
-- Layout), the text on the dark inner panel (the eye strain rule) and the
-- widget set's Import. The look is the 'copy' area's (Kit.Areas).
local COPY_W, COPY_H = 760, 480
local COPY_TITLE = "MelloUI: "   -- (plain: the plate paints its title)
local COPY_TOP = -64      -- the text's panel under the corner ring
local COPY_EDGE = 28      -- the panel's margin (on the calm ground, clear of its band)
local COPY_FOOT = 56      -- the band under the panel: the hint and Import
local COPY_BUTTON_W, COPY_BUTTON_H = 120, 24

local function CopyFrame()
	if copyFrame then
		return copyFrame
	end
	local W = MelloUI.Widgets
	local f = CreateFrame("Frame", "MelloUICopyFrame", UIParent)
	f:SetSize(COPY_W, COPY_H)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:Hide()
	-- (its own script before the shell's and the mover's hooks: SetScript
	-- drops hooks; review, 2026-09-25)
	f:SetScript("OnHide", function() f.onAccept = nil end)
	local shell = MelloUI.Kit:OwnWindow(f, { area = "copy", ring = { at = "tl" }, plate = "rail", title = "MelloUI",
		close = true, escape = true, fit = true, sounds = true, calm = true,
		mover = { key = "copy", plainDrag = "always", label = "Copy window" } })
	f.shell, f.title = shell, shell.title
	local body = W.Panel(f)
	body:SetPoint("TOPLEFT", f, "TOPLEFT", COPY_EDGE, COPY_TOP)
	body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -COPY_EDGE, COPY_FOOT)
	f.body = body
	-- (the scroll bar inside the panel, on its right)
	local scroll = CreateFrame("ScrollFrame", "MelloUICopyScroll", body, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 10, -8)
	scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -30, 8)
	f.scroll = scroll
	local edit = CreateFrame("EditBox", "MelloUICopyEdit", scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal)
	W.Paint(edit, "text", "text")
	edit:SetWidth(COPY_W - 2 * COPY_EDGE - 44)
	edit:SetScript("OnEscapePressed", function() f:Hide() end)
	edit:SetScript("OnEditFocusGained", function(self)
		if not f.onAccept then
			self:HighlightText()
		end
	end)
	-- typing must not change the text: put it back (not while pasting)
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput and not f.onAccept then
			self:SetText(f.text or "")
			self:HighlightText()
		end
	end)
	scroll:SetScrollChild(edit)
	f.edit = edit
	-- the band under the panel: what the keys do (full-size text: no small
	-- text on the window's ground), and Import while pasting
	f.hint = W.Text(f, "GameFontHighlight", nil, "text")
	f.hint:SetPoint("LEFT", f, "BOTTOMLEFT", COPY_EDGE + 4, COPY_FOOT / 2)
	f.accept = W.Button(f, "Import", COPY_BUTTON_W, shell, { height = COPY_BUTTON_H, gold = true, onClick = function()
		local fn = f.onAccept
		if fn and fn(f.edit:GetText()) then
			f:Hide()
		end
	end })
	f.accept:SetPoint("RIGHT", f, "BOTTOMRIGHT", -COPY_EDGE, COPY_FOOT / 2)
	copyFrame = f
	return f
end

-- Show `text` to be selected and copied.
function MelloUI:ShowText(title, text)
	local f = CopyFrame()
	f.onAccept = nil
	f.accept:Hide()
	f.hint:SetText("Ctrl+A, Ctrl+C to copy  -  Esc closes")
	f.title:SetText(COPY_TITLE .. (title or ""))
	f.text = text or ""
	f.edit:SetText(f.text)
	f:Show()
	f.edit:SetFocus()
	f.edit:HighlightText()
end

-- An empty box to paste into; Import calls onAccept(text), and the window
-- closes when it returns true.
function MelloUI:ShowPaste(title, onAccept)
	local f = CopyFrame()
	f.onAccept = onAccept
	f.accept:Show()
	f.hint:SetText("Ctrl+V to paste  -  Esc closes")
	f.title:SetText(COPY_TITLE .. (title or ""))
	f.text = ""
	f.edit:SetText("")
	f:Show()
	f.edit:SetFocus()
end

function MelloUI:ShowLog(title)
	self:ShowText((title or "log") .. string.format("  (%d lines)", #log), table.concat(log, "\n"))
end

SLASH_MELLOLOG1 = "/mellolog"
SlashCmdList.MELLOLOG = function(msg)
	if msg == "clear" then
		MelloUI:ClearLog()
		MelloUI:Print("Log cleared.")
		return
	end
	MelloUI:ShowLog("log")
end

-- Chat lines nobody asked for: something learned, settings restored late, a
-- hint. Replies to slash commands use Print and always show; these can be
-- turned off with Tweaks > Chat Notices.
function MelloUI:Notice(msg, ...)
	local tweaks = self.db and self.db.modules and self.db.modules.Tweaks
	if tweaks and tweaks.chatNotices == false then
		return
	end
	self:Print(msg, ...)
end

-- One-time hint after the update that moved the settings out of Options > AddOns.
-- The flag lives in the Tweaks settings (a personal key: kept by the saved
-- variables, never by a profile). It
-- yields to the installer (its window shows, its countdown runs, or its
-- first-login check has not decided yet): the installer marks the tip shown
-- when it opens, and its Done page says where the settings live.
function MelloUI:ShowMenuButtonTip()
	local tweaks = self.db and self.db.modules and self.db.modules.Tweaks
	if not tweaks or tweaks.menuTipShown then
		return
	end
	local installer = self.Installer
	if type(installer) == "table" and type(installer.Busy) == "function" and installer:Busy() then
		return
	end
	tweaks.menuTipShown = true
	Backup(self, "menu tip")
	self:Notice("The settings have their own window now: the MelloUI button in the game menu (Escape), or /mello.")
end

-- Fill missing keys of tbl from defaults (shallow, one nested level for tables).
local function ApplyDefaults(tbl, defaults)
	for k, v in pairs(defaults) do
		if type(v) == "table" then
			if type(tbl[k]) ~= "table" then
				tbl[k] = {}
			end
			ApplyDefaults(tbl[k], v)
		elseif tbl[k] == nil then
			tbl[k] = v
		end
	end
	return tbl
end
MelloUI.ApplyDefaults = ApplyDefaults

-- Safe call wrapper so one broken module cannot take the whole addon down.
local function SafeCall(module, method, ...)
	local fn = module[method]
	if type(fn) ~= "function" then
		return true
	end
	local perf = MelloUI.Perf
	local t0, m0 = perf and debugprofilestop(), perf and collectgarbage("count")
	local ok, err = pcall(fn, module, ...)
	if perf then
		perf:ModuleCall(module.name, method, debugprofilestop() - t0, collectgarbage("count") - m0)
	end
	if not ok then
		MelloUI:Print("|cffff4040Error|r in module '%s' (%s): %s", module.name, method, tostring(err))
	end
	return ok
end

--------------------------------------------------------------------------------
-- Module registry
--------------------------------------------------------------------------------

-- the modules as registered (MelloUI:ModulesInOrder), and the types of the
-- registry's own fields (see the header): checked, kept as given
MelloUI.moduleList = {}
local REGISTRY_FIELDS = { flavour = "string", group = "string", window = "table", tweak = "table", area = "table",
	role = "string", navOrder = "number" }
REGISTRY_FIELDS.new = "string"   -- (0.14.0: a new module's New tag, the update it came with)
REGISTRY_FIELDS.slash = "string"   -- (0.17.1: its short /mello word)
-- (0.17.1: false -- a feature not offered on the installer's Features step,
-- whose two columns are full; switched on in the settings window)
REGISTRY_FIELDS.installer = "boolean"
local ROLES = { core = true, look = true, feature = true, adds = true, replaces = true }

function MelloUI:RegisterModule(name, module)
	assert(type(name) == "string" and name ~= "", "MelloUI:RegisterModule requires a name")
	assert(not self.modules[name], "MelloUI module '" .. name .. "' is already registered")

	module = module or {}
	module.name = name
	module.title = module.title or name
	module.desc = module.desc or ""
	module.defaults = module.defaults or {}
	module.options = module.options or {}
	assert(module.keep == nil or type(module.keep) == "table", "MelloUI module '" .. name .. "': keep must be a list of keys")
	-- a registry field of the wrong type: reported and left off, so only the
	-- tile or row that would read it goes without; an error here would take
	-- the whole module (and the rest of its file) out (review, 2026-09-25)
	local icon = module.icon
	if icon ~= nil and type(icon) ~= "string" and type(icon) ~= "number" then
		Report("MelloUI module '" .. name .. "': icon must be a texture path or a file id")
		module.icon = nil
	end
	for field, kind in pairs(REGISTRY_FIELDS) do
		if module[field] ~= nil and type(module[field]) ~= kind then
			Report("MelloUI module '" .. name .. "': " .. field .. " must be a " .. kind)
			module[field] = nil
		end
	end
	if module.role ~= nil and not ROLES[module.role] then
		Report("MelloUI module '" .. name .. "': role must be core, look, feature, adds or replaces")
		module.role = nil
	end
	if module.enabledByDefault == nil then
		module.enabledByDefault = true
	end
	module.isEnabled = false

	self.modules[name] = module
	table.insert(self.moduleOrder, name)
	self.moduleList[#self.moduleList + 1] = module

	-- Late registration (after login) still gets initialised.
	if self.initialized then
		self:InitModule(module)
	end

	return module
end

function MelloUI:GetModule(name)
	return self.modules[name]
end

function MelloUI:IterateModules()
	local i = 0
	return function()
		i = i + 1
		local name = self.moduleOrder[i]
		if name then
			return name, self.modules[name]
		end
	end
end

-- The modules in the order they registered (the TOC's): the list kept as
-- they come, not a copy, so read it and do not change it (for the lists
-- the configurator and the installer make from the registry's fields).
function MelloUI:ModulesInOrder()
	return self.moduleList
end

--------------------------------------------------------------------------------
-- CPU profiling (/mello cpu, needs the scriptProfile CVar)
--------------------------------------------------------------------------------

MelloUI.profiled = {}

-- Register a frame (its script handlers) or a function so that /mello cpu can
-- report how much CPU it used. Costs nothing while profiling is off.
function MelloUI:Profile(moduleName, label, target)
	if target ~= nil then
		self.profiled[#self.profiled + 1] = { module = moduleName, label = label, target = target }
	end
	return target
end

function MelloUI:GetModuleDB(name)
	local module = self.modules[name]
	if not module then
		return nil
	end
	self.db.modules[name] = self.db.modules[name] or {}
	return ApplyDefaults(self.db.modules[name], module.defaults)
end

function MelloUI:IsModuleEnabled(name)
	local module = self.modules[name]
	if not module then
		return false
	end
	local flag = self.db.enabled[name]
	if flag == nil then
		return module.enabledByDefault
	end
	return flag
end

function MelloUI:SetModuleEnabled(name, enabled)
	local module = self.modules[name]
	if not module then
		return
	end
	enabled = not not enabled
	self.db.enabled[name] = enabled

	if not self.initialized then
		return
	end
	Backup(self, "module ", name)

	if enabled and not module.isEnabled then
		module.isEnabled = true
		SafeCall(module, "OnEnable", self:GetModuleDB(name))
	elseif not enabled and module.isEnabled then
		module.isEnabled = false
		SafeCall(module, "OnDisable", self:GetModuleDB(name))
	end
	self:Fire("module", name, enabled)
end

-- Called by the config panel when a module setting changes.
function MelloUI:NotifySettingChanged(name, key, value)
	local module = self.modules[name]
	if not module then
		return
	end
	local db = self:GetModuleDB(name)
	db[key] = value
	if module.isEnabled then
		SafeCall(module, "OnSettingChanged", key, value, db)
	end
	Backup(self, "setting ", key)
	-- last, after everything above (held until the end of a Batch)
	self:Fire("setting", name, key, value)
end

function MelloUI:InitModule(module)
	if module.initialized then
		return
	end
	module.initialized = true
	local db = self:GetModuleDB(module.name)
	SafeCall(module, "OnInit", db)
	if self:IsModuleEnabled(module.name) then
		module.isEnabled = true
		SafeCall(module, "OnEnable", db)
	elseif module.applyWhenDisabled then
		-- A module that DRIVES other modules has to be obeyed while it is off
		-- as well. OnDisable otherwise only runs on the switch being thrown,
		-- never at login, so what it drives came up from its own saved flags
		-- and the screen disagreed with the switch (UI Modifications off with
		-- the whole reskin still on screen, 2026-09-22).
		SafeCall(module, "OnDisable", db)
	end
end

--------------------------------------------------------------------------------
-- The login's own frames (0.14.0): from PLAYER_LOGIN (the modules dress the
-- HUD there) until LOGIN_SETTLE seconds after the first PLAYER_ENTERING_WORLD
-- (a /reload's too). Work that can wait for them waits, so the login makes no
-- more than 0.13.7's did (Modules/KitShade.lua: the UI shade's partners of
-- the HUD, whose first show is the login).
--   MelloUI:LoggingIn() -> true while they last
--   MelloUI:AfterLogin(fn)  fn() once they are over (at once outside them);
--                           each fn once however often asked, in the order
--                           they came, each in its own pcall
-- One timer (C_Timer.After) per session; nothing polls.
--------------------------------------------------------------------------------

local LOGIN_SETTLE = 3
local login = { going = false, timed = false, waiting = {} }

function MelloUI:LoggingIn()
	return login.going
end

function MelloUI:AfterLogin(fn)
	if not login.going then
		fn()
		return
	end
	local waiting = login.waiting
	for i = 1, #waiting do
		if waiting[i] == fn then
			return
		end
	end
	waiting[#waiting + 1] = fn
end

local function LoginSettled()
	login.going = false
	local waiting = login.waiting
	for i = 1, #waiting do
		local fn = waiting[i]
		waiting[i] = nil
		local ok, err = pcall(fn)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function MelloUI:InitDB()
	if type(MelloUIDB) == "table" then
		self.db = MelloUIDB
		self.dbIsTemporary = false
		self.savedVariablesStage = "ADDON_LOADED"
	else
		-- Saved variables are not in place yet. Forever loads them late and
		-- will NOT overwrite a global that already exists, so the global must
		-- stay untouched until the real data shows up. Work on a private
		-- table meanwhile and adopt the real one as soon as it appears.
		self.db = {}
		self.dbIsTemporary = true
	end
	ApplyDefaults(self.db, DB_DEFAULTS)
	self.db.version = DB_VERSION
end

-- Called at every later lifecycle point. If the client replaced the global
-- with the loaded saved variables after we initialised, switch to that table.
-- If it replaced it with something else, keep ours and make sure ours is what
-- gets saved.
function MelloUI:AdoptSavedVariables(stage)
	if self.dbIsTemporary then
		if type(MelloUIDB) ~= "table" then
			return false -- still not loaded; keep waiting
		end
		local temp = self.db
		ApplyDefaults(MelloUIDB, DB_DEFAULTS)
		MelloUIDB.version = DB_VERSION
		self.db = MelloUIDB
		self.dbIsTemporary = false
		self.savedVariablesStage = stage or "late"
		-- Carry over anything changed while the temporary table was in use
		-- (this includes values the player brought back from the macro
		-- backup: RestoreMacroBackup, Core/Backup.lua).
		for name, values in pairs(temp.modules or {}) do
			local module = self.modules[name]
			if module then
				local real = self:GetModuleDB(name)
				for k, v in pairs(values) do
					if module.defaults[k] ~= v and real[k] == module.defaults[k] then
						real[k] = v
					end
				end
			end
		end
		for name, flag in pairs(temp.enabled or {}) do
			if self.db.enabled[name] == nil then
				self.db.enabled[name] = flag
			end
		end
		self.db.profiles = self.db.profiles or {}
		for name, text in pairs(temp.profiles or {}) do
			if self.db.profiles[name] == nil then
				self.db.profiles[name] = text
			end
		end
		-- (a baked copy carried over stays known as one: it follows a newer
		-- baked text, see Profiles)
		if type(temp.profilesShipped) == "table" then
			local record = type(self.db.profilesShipped) == "table" and self.db.profilesShipped or {}
			for name, text in pairs(temp.profilesShipped) do
				if self.db.profiles[name] == text and record[name] == nil then
					record[name] = text
				end
			end
			if next(record) ~= nil then
				self.db.profilesShipped = record
			end
		end
		if self.db.defaultProfile == nil then
			self.db.defaultProfile = temp.defaultProfile
		end
		if self.db.activeProfile == nil then
			self.db.activeProfile = temp.activeProfile
		end
		-- the macro backup's own state (Core/Backup.lua: top-level keys, in
		-- no profile): switched on before these came in. A copy 'found'
		-- meanwhile is not carried: the real settings came, so nothing was
		-- found (the mark would keep the switch refused and the old macros
		-- for good)
		if temp.macroBackup == true then
			self.db.macroBackup = true
		end
		-- The kit editor writes straight into the db rather than through a
		-- module, so it was not on this list and every edit made before the
		-- client got round to loading its saved variables was thrown away
		-- here (they load late on this client). What was edited THIS session
		-- is the newer of the two, so it wins.
		local function Graft(into, from)
			for key, value in pairs(from) do
				if type(value) ~= "table" then
					into[key] = value
				elseif value[1] ~= nil or type(into[key]) ~= "table" then
					-- an array (a tint, a crop) is replaced whole, never
					-- merged index by index
					into[key] = value
				else
					Graft(into[key], value)
				end
			end
		end
		for _, key in ipairs({ "kitTuning", "kitEditor" }) do
			if type(temp[key]) == "table" then
				if type(self.db[key]) ~= "table" then
					self.db[key] = temp[key]
				else
					Graft(self.db[key], temp[key])
				end
			end
		end
		if self.KitTuning then
			self.KitTuning:Reload()
		end
		-- Modules that acted on the temporary table get a second pass.
		for _, module in self:IterateModules() do
			module.db = nil
			if self:IsModuleEnabled(module.name) and type(module.OnAddonLoaded) == "function" then
				SafeCall(module, "OnAddonLoaded", self:GetModuleDB(module.name))
			end
		end
		return true
	end
	if type(MelloUIDB) == "table" and not rawequal(MelloUIDB, self.db) then
		MelloUIDB = self.db
	end
	return false
end

--------------------------------------------------------------------------------
-- The palette switch (0.14.0). The setting is UI Modifications' `palette`
-- (an id of MelloUI.Palettes; nil or an unknown one is Ember): profiles,
-- share strings and the installer's setups carry it; it is no personal key.
-- Applied at login (after the default profile, before the modules start:
-- nothing is drawn yet, so only the table is put in place), when the
-- settings are replaced (RestartModules: a profile load, a late settings
-- load; before the modules restart and before its 'restart'. A profile
-- load puts the table in place before it switches modules on or off, so
-- those start in the new palette, and holds the kit's walk for its
-- RestartModules: the one walk then reads the loaded Kit Colours through
-- the umbrella's settings, bound by then) and when the setting changes
-- (UI Modifications hands its bus 'setting' to SetPalette, the module on
-- or off). A switch, in this order: MelloUI.Palette becomes
-- the palette's table; the kit's art follows (Kit:ApplyBorder("colours"):
-- the folder for this palette and the Kit Colours, one walk over the kit's
-- textures), which fires 'border', then exactly one 'palette'. Without the
-- kit (a test world) the one 'palette' goes out from here.
--   MelloUI:SetPalette(id) -> switched
--       the palette in use, and the setting written when it names another
--       (its 'setting' comes back here and finds the palette in place);
--       the palette already in use: nothing at all
--------------------------------------------------------------------------------
-- (self, switch): the palette the settings name, put in place. switch:
-- false, only the table (the login); "hold", the table now and the kit's
-- walk held for the next switch (a profile load, before its module
-- switches); true, the whole switch (or the walk that was held)
local ApplyStoredPalette
do
	local walkHeld = false

	local function Put(id, switch)
		local roles = MelloUI.Palettes[id].roles
		if MelloUI.Palette ~= roles then
			MelloUI.Palette = roles
			if switch == "hold" then
				walkHeld = true
			end
		elseif not (switch == true and walkHeld) then
			return
		end
		if switch ~= true then
			return
		end
		walkHeld = false
		local Kit = MelloUI.Kit
		if type(Kit) == "table" and type(Kit.ApplyBorder) == "function" then
			Kit:ApplyBorder("colours")   -- (fires 'border', then the one 'palette')
		else
			MelloUI:Fire("palette")
		end
	end

	-- the palette the settings name, read as stored (the module's defaults
	-- not laid on, so a world without UI Modifications reads Ember)
	local function Stored(self)
		local modules = self.db and self.db.modules
		local um = type(modules) == "table" and modules.UIModifications
		return self:KnownPalette(type(um) == "table" and um.palette or nil)
	end

	ApplyStoredPalette = function(self, switch)
		Put(Stored(self), switch)
	end

	function MelloUI:SetPalette(id)
		id = self:KnownPalette(id)
		local before = self.Palette
		if self.db and self.modules.UIModifications and Stored(self) ~= id then
			self:NotifySettingChanged("UIModifications", "palette", id)
		end
		Put(id, true)
		return self.Palette ~= before
	end
end

-- Runs fn(self) with restartingModules set, and puts the outer value back
-- even when fn raises (the error goes on after it): a flag left set would
-- keep the reskin's own reactions out for the rest of the session.
local function WhileRestarting(self, fn)
	local outer = self.restartingModules
	self.restartingModules = true
	local ok, err = pcall(fn, self)
	self.restartingModules = outer
	if not ok then
		error(err, 0)
	end
end

local function RestartEach(self)
	for _, module in self:IterateModules() do
		if module.isEnabled then
			local db = self:GetModuleDB(module.name)
			SafeCall(module, "OnDisable", db)
			SafeCall(module, "OnEnable", db)
		end
	end
end

--------------------------------------------------------------------------------
-- Merged settings (0.16.0; the user, 2026-09-29: twelve of the Configurator
-- spec's same-meaning groups, docs/plans/next-update.md section 4). One key
-- lives on for each: a saved value of an old key is carried to it while
-- that key still holds its default, then the old key goes, so every
-- player keeps what they had. Run on the raw saved tables before the
-- modules come up (MelloUI:OnInitialize's pass) and before they come up
-- again after a profile, a share string or the backup is taken in
-- (RestartModules): a settings text from before the merge is carried too.
-- Reads and writes only MelloUI.db; makes nothing when there is nothing to
-- carry. (The Voice Over widget's padlock and old place: Modules/VoiceOver
-- OnInit; the Route arrow's size needs its frame: Route's PlaceArrow.)
--------------------------------------------------------------------------------

do
	local function Raw(self, name)
		local mods = self.db and self.db.modules
		local t = type(mods) == "table" and mods[name]
		return type(t) == "table" and t or nil
	end

	local function Own(self, name)
		local mods = self.db and self.db.modules
		if type(mods) ~= "table" then
			return nil
		end
		if type(mods[name]) ~= "table" then
			mods[name] = {}
		end
		return mods[name]
	end

	local MERGES = {
		-- 1: Chat's Names In Chat into Show Names As (its "full" is "both")
		function(self)
			local chat = Raw(self, "Chat")
			local style = chat and chat.nameStyle
			if style == nil then
				return
			end
			chat.nameStyle = nil
			local ui = Own(self, "UIModifications")
			if ui and (ui.nameFormat == nil or ui.nameFormat == "both") and type(style) == "string" and style ~= "full" then
				ui.nameFormat = style
			end
		end,
		-- 2: the Route's, the zone text's and the centre texts' shades into
		-- one Text Shade (off only when all three were off)
		function(self)
			local route, tweaks = Raw(self, "Route"), Raw(self, "Tweaks")
			local r = route and route.textShade
			local z, c = tweaks and tweaks.zoneTextShade, tweaks and tweaks.centreTextShade
			if r == nil and z == nil and c == nil then
				return
			end
			if route then
				route.textShade = nil
			end
			if tweaks then
				tweaks.zoneTextShade, tweaks.centreTextShade = nil, nil
			end
			if r ~= true and z ~= true and c ~= true then
				local t = Own(self, "Tweaks")
				if t and t.textShade ~= false then
					t.textShade = false
				end
			end
		end,
		-- 3: the nameplates' own Shade Strength: they follow the UI Shade's
		function(self)
			local np = Raw(self, "NameplatePanel")
			if np then
				np.shadeStrength = nil
			end
		end,
		-- 4: the UI Shade's Nameplates switch into Name Shade (Whole plate
		-- needed both: one that was off is a Name shade now)
		function(self)
			local ui = Raw(self, "UIModifications")
			local on = ui and ui.shade_nameplates
			if on == nil then
				return
			end
			ui.shade_nameplates = nil
			local np = on == false and Raw(self, "NameplatePanel")
			if np and np.nameShade == "plate" then
				np.nameShade = "name"
			end
		end,
		-- 6: chat's and the tooltip's Class Coloured Names into one (off
		-- when either was off: the player's no)
		function(self)
			local chat, tip = Raw(self, "Chat"), Raw(self, "Tooltip")
			local a, b = chat and chat.classColors, tip and tip.classNames
			if a == nil and b == nil then
				return
			end
			if chat then
				chat.classColors = nil
			end
			if tip then
				tip.classNames = nil
			end
			if a == false or b == false then
				local ui = Own(self, "UIModifications")
				if ui then
					ui.classNames = false
				end
			end
		end,
		-- 7: the tooltip's Use Bar Texture into Bar Textures' Tooltip area
		function(self)
			local tip = Raw(self, "Tooltip")
			local v = tip and tip.barTexture
			if v == nil then
				return
			end
			tip.barTexture = nil
			if v == false then
				local bt = Own(self, "BarTextures")
				if bt then
					bt.tooltip = false
				end
			end
		end,
		-- 10: Dark Mode's Icon Border: part of the aura border now
		function(self)
			local dm = Raw(self, "DarkMode")
			if dm then
				dm.auraIconBorder = nil
			end
		end,
		-- 12: Route Announces and Announce Sound: the notice's own switches
		function(self)
			local route = Raw(self, "Route")
			if route then
				route.notice, route.noticeSound = nil, nil
			end
		end,
		-- 17: the Restock reminder's switch: the Restock switch itself
		function(self)
			local rem = Raw(self, "Reminders")
			if rem then
				rem.remind_restock = nil
			end
		end,
		-- 0.17.0: Unit Frames' Fade Out Of Combat into the Fader (Modules/
		-- Fader.lua): on (with Unit Frames on) -> the Fader on and the Player
		-- Frame's Show "In Combat"; Faded Opacity and Pet Frame Too as they were
		function(self)
			local uf = Raw(self, "UnitFrames")
			if not uf then
				return
			end
			local on, alpha, pet = uf.fadeOutOfCombat, uf.fadeAlpha, uf.fadePet
			if on == nil and alpha == nil and pet == nil then
				return
			end
			uf.fadeOutOfCombat, uf.fadeAlpha, uf.fadePet = nil, nil, nil
			local fd = Own(self, "Fader")
			if not fd then
				return
			end
			local enabled = self.db.enabled
			if on == true and not (type(enabled) == "table" and enabled.UnitFrames == false) then
				if fd.show_player == nil then
					fd.show_player = "combat"
				end
				if type(enabled) == "table" and enabled.Fader == nil then
					enabled.Fader = true
				end
			end
			if type(alpha) == "number" and fd.alpha == nil then
				fd.alpha = alpha
			end
			if pet == false and fd.petToo == nil then
				fd.petToo = false
			end
		end,
	}

	function MelloUI:MergeSettings()
		for i = 1, #MERGES do
			local ok, err = pcall(MERGES[i], self)
			if not ok then
				geterrorhandler()(err)
			end
		end
	end
end

-- After a (late) adoption, modules that are already running must re-read
-- their settings.
-- (restartingModules while it runs: a module's own reaction to a switch --
-- UI Modifications' reskin bringing Custom Sounds and the Edit Mode layout --
-- is the player's switch only, never a restart's or a profile load's)
function MelloUI:RestartModules()
	-- an Edit Layout session ends first, nothing of it put back over the
	-- settings now in place (a profile load, the macro backup's restore):
	-- every OnEnable below places from the store as it is
	self.LayoutSession.Abandon("restart")
	-- the palette the settings now name first (or a profile load's held
	-- walk): the modules come back up in it, and the kit's own look check
	-- on 'restart' finds its art in place
	ApplyStoredPalette(self, true)
	-- (a settings text from before 0.16.0's merged settings: carried first)
	self:MergeSettings()
	WhileRestarting(self, RestartEach)
	if self.RefreshConfig then
		self:RefreshConfig()
	end
	self:Fire("restart")
end

--------------------------------------------------------------------------------
-- Unit names on this client have a first name and a surname (user,
-- 2026-09-22: "only show the character's first name, last name or both").
-- The game's NameUtil (C side) gives the display name with or without the
-- surname and the first name alone; the surname is the rest of the full
-- name. A unit token or a name can be a secret value here (nameplates): a
-- secret first or full name is still handed back (SetText takes it), only
-- the surname needs string work and is nil when it cannot be done.
-- mode: "first", "last", "both" (the full name), "initial" ("P. Skillybones")
-- or "firstinitial" ("Professor S."; 0.16.0: Show Names As took Names In
-- Chat's forms). nil when nothing could be read.
-- A pcall's first result, secret or not; nil when it raised. The value is
-- never compared: a secret refuses even the nil test (audit, 2026-09-24).
local function PlainOrSecret(ok, value)
	if not ok then
		return nil
	end
	return value
end

function MelloUI:UnitNameAs(unit, mode)
	if not unit then
		return nil
	end
	local util = NameUtil
	local full, first
	if type(util) == "table" and util.FormatUnitNameForDisplay then
		full = PlainOrSecret(pcall(util.FormatUnitNameForDisplay, unit, true))
		if util.GetUnitFirstName then
			first = PlainOrSecret(pcall(util.GetUnitFirstName, unit))
		end
	end
	-- (each name asked for secret before its nil test)
	if not Safe.IsSecret(full) and full == nil then
		full = PlainOrSecret(pcall(UnitName, unit))
	end
	local secretFull = Safe.IsSecret(full)
	if not secretFull and full == nil then
		return nil
	end
	local secretFirst = Safe.IsSecret(first)
	if not (secretFull or secretFirst) and first == nil then
		first = full:match("^(%S+)") or full
	end
	if mode == "both" then
		return full
	elseif mode == "first" then
		return first
	elseif mode == "last" or mode == "initial" or mode == "firstinitial" then
		if secretFull or secretFirst or first == nil then
			return nil
		end
		local rest = full:sub(#first + 1):gsub("^%s+", "")
		if rest == "" then
			return full   -- no surname: the name as it is
		end
		if mode == "last" then
			return rest
		end
		-- (a letter is a UTF-8 character, not a byte)
		if mode == "initial" then
			return (first:match("^[%z\1-\127\194-\244][\128-\191]*") or first:sub(1, 1)) .. ". " .. rest
		end
		return first .. " " .. (rest:match("^[%z\1-\127\194-\244][\128-\191]*") or rest:sub(1, 1)) .. "."
	end
	return nil
end

-- Profiles
--
-- A profile is the settings serialised the way the macro backup does it
-- (only values that differ from the defaults). Profiles live in
-- MelloUIDB.profiles; Tools\bake_routes.py bakes them into Media\Profiles.lua
-- (MelloUI_Profiles) so they ship with the addon,
-- and the one marked default is applied on a fresh install, that is when no
-- setting differs from the defaults after login.
--------------------------------------------------------------------------------

-- The built-in profile with every module off (user, 2026-09-22: "when the
-- addon is installed for the first time, everything should be off"): the
-- default for a fresh install, made from the module list at every login so
-- a module added later is off in it too. Not baked, not deletable, not
-- overwritable.
MelloUI.FRESH_PROFILE = "Everything Off"

function MelloUI:FreshProfileText()
	local parts = {}
	for name, module in self:IterateModules() do
		if module.enabledByDefault and not module.hidden then
			parts[#parts + 1] = "!" .. name .. "=b0"
		end
		-- the tweak modules folded under UI Modifications follow its qol_
		-- switches: those off too, so switching the umbrella on brings the
		-- reskin alone (user, 2026-09-22: "it should only auto enable the
		-- full reskin and the custom sounds")
		local keys = {}
		for key, value in pairs(module.defaults) do
			if type(key) == "string" and key:sub(1, 4) == "qol_" and value == true then
				keys[#keys + 1] = key
			end
		end
		table.sort(keys)
		for _, key in ipairs(keys) do
			parts[#parts + 1] = name .. "." .. key .. "=b0"
		end
	end
	return table.concat(parts, ";")
end

-- the baked text copied into the player's list, recorded (db.profilesShipped)
local function RecordShipped(db, name, text)
	if type(db.profilesShipped) ~= "table" then
		db.profilesShipped = {}
	end
	db.profilesShipped[name] = text
end

-- The player's profiles, the baked ones (MelloUI_Profiles) copied in while
-- the name is free. db.profilesShipped[name] records the baked text copied,
-- so a copy the player never changed follows a newer baked text (a release's
-- new "MelloUI"); a copy they saved over, or an older copy that was never
-- recorded, stays theirs.
function MelloUI:Profiles()
	local db = self.db
	db.profiles = db.profiles or {}
	local profiles = db.profiles
	local baked = type(MelloUI_Profiles) == "table" and MelloUI_Profiles.profiles
	if type(baked) == "table" then
		for name, text in pairs(baked) do
			if type(text) == "string" and name ~= self.FRESH_PROFILE then
				local have = profiles[name]
				local copied = type(db.profilesShipped) == "table" and db.profilesShipped[name] or nil
				if have == nil or (copied ~= nil and have == copied and have ~= text) then
					profiles[name] = text
					RecordShipped(db, name, text)
				elseif have == text and copied ~= text then
					RecordShipped(db, name, text)   -- (a copy equal to the baked text follows it from now on)
				end
			end
		end
	end
	profiles[self.FRESH_PROFILE] = self:FreshProfileText()
	if self.db.defaultProfile == nil then
		self.db.defaultProfile = self.FRESH_PROFILE
	end
	return self.db.profiles
end

function MelloUI:IsProfileBaked(name)
	if name == self.FRESH_PROFILE then
		return true
	end
	return type(MelloUI_Profiles) == "table" and type(MelloUI_Profiles.profiles) == "table"
		and MelloUI_Profiles.profiles[name] == self:Profiles()[name]
end

-- Personal keys (audit, 2026-09-24). Some settings are no choice at all but
-- this player's own: the flight points a character has learned (Route's
-- flights_<character>), a game setting MelloUI borrowed and must give back
-- (Chat's savedWhisperMode), a one-time step that was done (UI
-- Modifications' layoutApplied). A module names them in `keep` when it
-- registers. A profile or a share string never carries them: a posted
-- string held the sharer's character IDs, and a layoutApplied in it kept
-- the importer's reskin from ever placing its layout. Loading a profile
-- leaves them as they are: it used to wipe every character's flight points.
-- The macro backup, when it is switched on, still writes them, and a copy
-- brought back (/mello backup restore) brings them back with the rest.
function MelloUI:IsPersonalKey(moduleName, key)
	local module = self.modules[moduleName]
	local keep = module and module.keep
	if not keep or type(key) ~= "string" then
		return false
	end
	for i = 1, #keep do
		local entry = keep[i]
		if entry == key or (entry:sub(1, 1) == "^" and key:find(entry)) then
			return true
		end
	end
	return false
end

-- Serialised settings without their personal entries ("Module.key=value",
-- parsed as DeserializeSettings does); the text itself when it holds none.
local function StripPersonal(self, text)
	if type(text) ~= "string" or text == "" then
		return text
	end
	local parts, dropped = {}, false
	for entry in text:gmatch("[^;]+") do
		local moduleName, key = entry:match("^([^=.]+)%.([^=]+)=")
		if moduleName and self:IsPersonalKey(moduleName, key) then
			dropped = true
		else
			parts[#parts + 1] = entry
		end
	end
	return dropped and table.concat(parts, ";") or text
end

function MelloUI:SaveProfile(name)
	name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
	if name == "" then
		return false, "a profile needs a name"
	end
	if name == self.FRESH_PROFILE then
		return false, "'" .. name .. "' is built in"
	end
	self:Profiles()[name] = StripPersonal(self, self:SerializeSettings())
	self.db.activeProfile = name
	return true
end

function MelloUI:DeleteProfile(name)
	local profiles = self:Profiles()
	if profiles[name] == nil or name == self.FRESH_PROFILE then
		return false
	end
	profiles[name] = nil
	if self.db.defaultProfile == name then
		self.db.defaultProfile = nil
	end
	if self.db.activeProfile == name then
		self.db.activeProfile = nil
	end
	return true
end

function MelloUI:SetDefaultProfile(name)
	if name ~= nil and self:Profiles()[name] == nil then
		return false
	end
	-- false, not nil: "none" chosen, as against never set (Profiles() makes
	-- the built-in profile the default when nothing was chosen)
	self.db.defaultProfile = name or false
	return true
end

-- Replace every setting with the serialised ones: defaults first, then the
-- profile, then the running modules pick the new values up. The personal
-- keys stay as they are, whatever the text holds (IsPersonalKey). The
-- tables are emptied in place: a module holding its db (Route's cached
-- flight points read from it) keeps reading the same one.
-- The modules UI Modifications drives (hidden) are its to switch, never the
-- profile's flags: their flags were cleared with the rest (so each would
-- read as its enabledByDefault), and an old text may carry one ("!DarkMode"
-- lands in the flags, Dark Mode's switch being off until switched on). The
-- umbrella switched on or off by the load drives them from its OnEnable /
-- OnDisable; one off before and after is obeyed as at login (InitModule's
-- applyWhenDisabled), so what it drives stays off (a load with UI
-- Modifications off left Dark Mode and every panel running, 2026-09-26).
local function SwitchForProfile(self)
	for name, module in self:IterateModules() do
		if not module.hidden then
			local want = self:IsModuleEnabled(name)
			if want ~= (module.isEnabled or false) then
				self:SetModuleEnabled(name, want)
			elseif not want and module.applyWhenDisabled then
				SafeCall(module, "OnDisable", self:GetModuleDB(name))
			end
		end
	end
	self:RestartModules()
end

-- withPersonal: the text's personal keys are taken in as well (the player's
-- own copy brought back: MelloUI:RestoreMacroBackup, Core/Backup.lua); a
-- personal key the text does not hold stays as it is either way.
function MelloUI:ApplySettingsText(text, withPersonal)
	for name, module in self:IterateModules() do
		local db = self:GetModuleDB(name)
		for k in pairs(db) do
			if not (module.keep and self:IsPersonalKey(name, k)) then
				db[k] = nil
			end
		end
		ApplyDefaults(db, module.defaults)
	end
	for name in pairs(self.db.enabled) do
		self.db.enabled[name] = nil
	end
	local applied = self:DeserializeSettings(withPersonal and text or StripPersonal(self, text))
	if self.initialized then
		-- the loaded palette's table before any module is switched on or off
		-- (they start in it); the kit's one walk in RestartModules, below
		ApplyStoredPalette(self, "hold")
		-- (a module's switch here is the profile's, not the player's: the
		-- reskin's own reactions stay out, as in RestartModules)
		WhileRestarting(self, SwitchForProfile)
		if self.RefreshConfig then
			self:RefreshConfig()
		end
		Backup(self, "profile")
	end
	return applied
end

--------------------------------------------------------------------------------
-- Share strings (user, 2026-09-23: "Profile share strings with the game's own
-- encoders"). A profile is already its settings' differences from the
-- defaults, as text; to share it, that text is compressed and turned into
-- plain letters by the game's own encoders (C_EncodingUtil: Deflate, then
-- Base64) behind a tag naming the format:
--
--   !MelloUI1!<base64 of the deflated profile text>
--
-- An import is decoded back and checked -- every entry "key=value", at least
-- one for a module this addon has -- before it becomes a profile. It is only
-- stored under the name given: nothing changes until it is loaded.
--------------------------------------------------------------------------------

local SHARE_TAG = "!MelloUI1!"

local function Deflate()
	return Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate
end

function MelloUI:ExportProfile(name)
	local text = self:Profiles()[name]
	if type(text) ~= "string" then
		return nil, "no profile '" .. tostring(name) .. "'"
	end
	-- a profile saved before they were left out may still hold personal keys
	text = StripPersonal(self, text)
	local enc = C_EncodingUtil
	if not (enc and enc.CompressString and enc.EncodeBase64) then
		return nil, "this client cannot make share strings"
	end
	local method = Deflate()
	local okC, packed
	if method then
		okC, packed = pcall(enc.CompressString, text, method)
	else
		okC, packed = pcall(enc.CompressString, text)
	end
	if not (okC and type(packed) == "string") then
		return nil, "the profile could not be compressed"
	end
	local okB, letters = pcall(enc.EncodeBase64, packed)
	if not (okB and type(letters) == "string") then
		return nil, "the profile could not be encoded"
	end
	return SHARE_TAG .. letters
end

-- The profile text inside a share string, and how many of its entries are for
-- modules this addon has; nil and the reason when it is not one.
function MelloUI:DecodeProfileString(str)
	if type(str) ~= "string" then
		return nil, "nothing to import"
	end
	-- copied from a chat or a web page it may have gained spaces or line breaks
	str = str:gsub("%s+", "")
	if str:sub(1, #SHARE_TAG) ~= SHARE_TAG then
		return nil, "not a MelloUI profile string (it starts with " .. SHARE_TAG .. ")"
	end
	local enc = C_EncodingUtil
	if not (enc and enc.DecodeBase64 and enc.DecompressString) then
		return nil, "this client cannot read share strings"
	end
	local okB, packed = pcall(enc.DecodeBase64, str:sub(#SHARE_TAG + 1))
	if not (okB and type(packed) == "string" and packed ~= "") then
		return nil, "the string is damaged (cut short while copying?)"
	end
	local method = Deflate()
	local okD, text
	if method then
		okD, text = pcall(enc.DecompressString, packed, method)
	else
		okD, text = pcall(enc.DecompressString, packed)
	end
	if not (okD and type(text) == "string") then
		return nil, "the string is damaged (cut short while copying?)"
	end
	-- never taken in: another player's personal keys (their characters' flight
	-- points, a game setting of theirs to give back, their one-time flags),
	-- which strings posted before profiles left them out still carry
	local stripped = StripPersonal(self, text)
	if stripped == "" and text ~= "" then
		return nil, "it holds no settings, only one player's own data, which profiles never carry"
	end
	text = stripped
	local total, known = 0, 0
	for entry in text:gmatch("[^;]+") do
		total = total + 1
		local key = entry:match("^([^=]+)=.")
		if not key then
			return nil, "the string holds something that is not a MelloUI setting"
		end
		local module = key:match("^!?([^.]+)")
		if module and self.modules[module] then
			known = known + 1
		end
	end
	if text ~= "" and known == 0 then
		return nil, "none of its settings belong to a MelloUI module"
	end
	return text, known, total
end

-- Store a share string as the profile `name` (replacing one of that name).
function MelloUI:ImportProfile(name, str)
	name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
	if name == "" then
		return false, "type a name for the profile first"
	end
	if name == self.FRESH_PROFILE then
		return false, "'" .. name .. "' is built in"
	end
	local text, known, total = self:DecodeProfileString(str)
	if not text then
		return false, known
	end
	self:Profiles()[name] = text
	Backup(self, "profile import")
	return true, known, total
end

function MelloUI:LoadProfile(name)
	local text = self:Profiles()[name]
	if type(text) ~= "string" then
		return false
	end
	self:ApplySettingsText(text)
	self.db.activeProfile = name
	return true
end

-- Nothing configured at all (a fresh install, or the saved variables missing:
-- a copy in the macro backup is never read back by itself): apply the
-- default profile.
function MelloUI:ApplyDefaultProfileIfFresh()
	if self:SerializeSettings() ~= "" then
		return false
	end
	local profiles = self:Profiles()
	local name = self.db.defaultProfile
	if not name or type(profiles[name]) ~= "string" then
		return false
	end
	-- as a loaded one: its personal keys never land (a profile saved before
	-- they were left out could carry one that would stand in for the player's own)
	self:DeserializeSettings(StripPersonal(self, profiles[name]))
	self.db.activeProfile = name
	self.profileAppliedAtLogin = name
	return true
end

MelloUI:RegisterEvent("ADDON_LOADED")
MelloUI:RegisterEvent("VARIABLES_LOADED")
MelloUI:RegisterEvent("PLAYER_LOGIN")
MelloUI:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		self:UnregisterEvent("ADDON_LOADED")
		self:InitDB()
		self:RegisterEvent("PLAYER_LOGOUT")
		-- Early hook for modules that must act before PLAYER_LOGIN (e.g. world fonts).
		for _, module in self:IterateModules() do
			if self:IsModuleEnabled(module.name) and type(module.OnAddonLoaded) == "function" then
				SafeCall(module, "OnAddonLoaded", self:GetModuleDB(module.name))
			end
		end
	elseif event == "VARIABLES_LOADED" then
		self:UnregisterEvent("VARIABLES_LOADED")
		if not self.db then
			self:InitDB()
		end
		self:AdoptSavedVariables("VARIABLES_LOADED")
	elseif event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		login.going = true   -- (the login's frames: MelloUI:LoggingIn)
		if not self.db then
			self:InitDB()
		end
		self:AdoptSavedVariables("PLAYER_LOGIN")
		-- (saved variables still missing here: the settings are a new
		-- player's. The macro backup is never read back by itself any more
		-- (0.14.0): a copy found there is said once and brought back only
		-- when the player asks, /mello backup restore; Core/Backup.lua)
		-- (no line for it: a new player gets the installer a few seconds in,
		-- Core/Installer.lua's one login check)
		self:ApplyDefaultProfileIfFresh()
		-- the palette the settings name, before any module draws (only the
		-- table: nothing is on the screen to repaint yet)
		ApplyStoredPalette(self, false)
		self.initialized = true
		-- the modules come up in TOC order; a module that drives others
		-- (UI Modifications) must not pull them forward out of that order
		-- during this pass (the unit frame panel read the bars' layers
		-- before Bar Textures had set them, 2026-09-21): it sets their
		-- flags and lets this loop enable them in their turn
		-- (0.16.0's merged settings carried before any module reads its own)
		self:MergeSettings()
		self.initializingModules = true
		for _, module in self:IterateModules() do
			self:InitModule(module)
		end
		self.initializingModules = nil
		if self.BuildConfig then
			self:BuildConfig()
		end
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
	elseif event == "PLAYER_LOGOUT" then
		-- Whatever table we have been editing is the one that must be saved.
		self:AdoptSavedVariables("PLAYER_LOGOUT")
		MelloUIDB = self.db
		if self.WriteBackup then
			self:WriteBackup("logout")
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- (first: the login's frames end LOGIN_SETTLE s from now, whatever
		-- the rest of this does)
		if login.going and not login.timed then
			login.timed = true
			C_Timer.After(LOGIN_SETTLE, LoginSettled)
		end
		if self:AdoptSavedVariables("PLAYER_ENTERING_WORLD") then
			self:RestartModules()
			if self.BackupAfterAdopt then
				self:BackupAfterAdopt()
			end
		end
		if not self.menuTipTimer then
			-- a few seconds in, after the login spam and a possible late settings load
			self.menuTipTimer = C_Timer.NewTimer(8, function() self:ShowMenuButtonTip() end)
		end
		-- Saved variables may still be on their way: keep checking for a while.
		if self.dbIsTemporary and not self.adoptTicker then
			local ticks = 0
			self.adoptTicker = C_Timer.NewTicker(1, function(ticker)
				ticks = ticks + 1
				if not self.dbIsTemporary then
					ticker:Cancel()
					self.adoptTicker = nil
					return
				end
				if self:AdoptSavedVariables("late poll " .. ticks .. "s") then
					self:RestartModules()
					self:Notice("Settings loaded late by the client and applied.")
					ticker:Cancel()
					self.adoptTicker = nil
					if self.BackupAfterAdopt then
						self:BackupAfterAdopt()
					end
				elseif ticks >= 60 then
					ticker:Cancel()
					self.adoptTicker = nil
					-- none came: a fresh start (/mello status says so)
					self.savedVariablesNone = true
					if self.BackupAfterAdopt then
						self:BackupAfterAdopt()
					end
				end
			end)
		end
	end
end)
