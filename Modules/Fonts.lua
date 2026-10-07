--------------------------------------------------------------------------------
-- MelloUI - Fonts
--
-- Replaces the font used by every global font object (GameFontNormal,
-- SystemFont_*, NumberFont*, ChatFont*, ...) and the chat windows with the
-- chosen font, optionally scaled. Original fonts are remembered so the module
-- can be switched off again without a reload.
--
-- Available fonts: the four fonts shipped with the game, any font registered
-- with LibSharedMedia-3.0 by another addon, and custom .ttf files listed in
-- Media\CustomFonts.lua.
--
-- Not covered: floating combat text in the world and the 3D name text above
-- characters. Those are read from the Fonts folder at startup and cannot be
-- changed by an addon at runtime.
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Fonts")
local hooksecurefunc = Perf.hooksecurefunc

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua): what
-- MelloUI:StyleFont reads from a font object and takes from its callers
local SafeText = MelloUI.Safe.Text
local SafeNumber = MelloUI.Safe.Number

local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"

local BUILTIN_FONTS = {
	{ value = DEFAULT_FONT,            label = "Friz Quadrata (default)" },
	{ value = "Fonts\\ARIALN.TTF",     label = "Arial Narrow" },
	{ value = "Fonts\\MORPHEUS.TTF",   label = "Morpheus" },
	{ value = "Fonts\\SKURRI.TTF",     label = "Skurri" },
}

local function BuildFontList()
	local list = {}
	local seen = {}
	local function Add(value, label)
		if value and not seen[value] then
			seen[value] = true
			list[#list + 1] = { value = value, label = label or value }
		end
	end

	for _, entry in ipairs(BUILTIN_FONTS) do
		Add(entry.value, entry.label)
	end

	-- Custom fonts dropped into Media\Fonts and listed in Media\CustomFonts.lua.
	if type(MelloUI_CustomFonts) == "table" then
		for _, entry in ipairs(MelloUI_CustomFonts) do
			if type(entry) == "table" and entry.file then
				Add("Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Fonts\\" .. entry.file, entry.name or entry.file)
			end
		end
	end

	-- Fonts shared by other addons through LibSharedMedia-3.0.
	local LSM = LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
	if LSM then
		for _, name in ipairs(LSM:List("font")) do
			Add(LSM:Fetch("font", name), name)
		end
	end

	table.sort(list, function(a, b)
		if a.value == DEFAULT_FONT then return true end
		if b.value == DEFAULT_FONT then return false end
		return a.label:lower() < b.label:lower()
	end)
	return list
end

-- The game draws its text with four faces; every font object descends from
-- one of them, and each role gets its own choice here (user, 2026-09-21):
--   text    Friz Quadrata  interface text: windows, buttons, tooltips, quest
--                          log, nameplate names, character names in the world
--   chat    Arial Narrow   chat windows and the numbers: bar values, cooldown
--                          counts, stack counts, damage on unit frames
--   title   Morpheus       window titles, quest and item names in dialogs,
--                          mail and book text
--   damage  Skurri         floating combat text in the world
-- "Keep the game's" leaves a role on its own face. The world faces (names
-- above characters, floating combat text) are read once at start-up: a
-- change there shows after /reload.
local ROLES = {
	{ key = "fontText",   match = "frizqt",   name = "Interface text (Friz Quadrata)",
	  desc = "Window text, buttons, tooltips, the quest log, nameplate names and the names above characters in the world (those after /reload)." },
	{ key = "fontChat",   match = "arialn",   name = "Chat & numbers (Arial Narrow)",
	  desc = "The numbers: cooldown counts, stack counts; and the chat windows while Chat text and Interface text both keep the game's. The value text on the unit frames' bars follows the Interface text, the hit numbers on the portraits the Game Numbers Font." },
	{ key = "fontTitle",  match = "morpheus", name = "Titles & headers (Morpheus)",
	  desc = "Window titles, quest and item names in dialogs, mail and book text, and the kit's title plates and headers while the reskin is on. Enchanted Land unless you choose otherwise. Keep the game's leaves each string in the game's own face: Morpheus where the game uses it, the interface face on the strings that start in it (the Quest Tracker's headers, Combat Text's notices)." },
	{ key = "fontDamage", match = "skurri",   name = "Game Numbers Font (Skurri)",
	  desc = "The numbers over the enemies: the game's own (after /reload) and Your Damage's (at once); and the hit numbers on the unit frames' portraits. The game's text around you (Combat Text's Game style) and MelloUI's are drawn in the Interface text face." },
}

local KEEP = "default"

local function RoleFor(path)
	local lower = type(path) == "string" and path:lower() or ""
	for _, role in ipairs(ROLES) do
		if lower:find(role.match, 1, true) then
			return role.key
		end
	end
	return "fontText"
end

local function BuildRoleList()
	local list = { { value = KEEP, label = "Keep the game's" } }
	for _, entry in ipairs(BuildFontList()) do
		list[#list + 1] = entry
	end
	return list
end

-- Each role has its own size slider (user, 2026-09-22); `scale`, the old
-- single slider, is folded into them once and taken out (MigrateScale).
-- The player's own size only (0.19.4, the options audit: Size Title and
-- Size Text took over Scale Title and Scale Text, which a Font Style also
-- used for its faces' correction, FaceFactor below; MelloUI:MergeSettings
-- carries an old save). The damage numbers have no size here: the game
-- sizes its text around you itself (Scale Damage, gone in 0.19.4).
local SCALE_KEY = { fontText = "sizeText", fontChat = "scaleChat", fontTitle = "sizeTitle" }
local IS_ROLE = {}   -- [roleKey] = true, filled from ROLES
-- The title role's default is the kit's face (user, 2026-09-22: "make it
-- Enchanted Land as default"); the other roles keep the game's.
local TITLE_DEFAULT = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Fonts\\EnchantedLand.ttf"

-- Font Styles (user, 2026-09-23: "make all 6 as presets in the Fonts
-- options"): the six pairings of the font study (themed, readability first),
-- each a face for the titles, the interface text and the chat and numbers,
-- with sizes that give every body face the same x-height as the game's own
-- and the titles a size like Enchanted Land's. The damage numbers keep their
-- own choice. Choosing a style sets those six options; changing any of them
-- afterwards shows Custom.
local FONT_DIR = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Fonts\\"
local NUMBERS = "NotoSans\\NotoSans_Condensed-Bold.ttf"   -- narrow, clear figures, in every style
local STYLES = {
	{ value = "scriptorium", paper = "Alegreya\\Alegreya-SemiBold.ttf", label = "Scriptorium", title = "Cinzel\\Cinzel-Bold.ttf", titleScale = 0.7,
	  text = "Alegreya\\Alegreya-Regular.ttf", textScale = 1.1, desc = "Cinzel's carved capitals over Alegreya, a warm book face." },
	{ value = "chronicle", paper = "SourceSerif4\\SourceSerif4-SemiBold.ttf", label = "Chronicle", title = "AlegreyaSC\\AlegreyaSC-Bold.ttf", titleScale = 0.75,
	  text = "SourceSerif4\\SourceSerif4-Regular.ttf", textScale = 1.05, desc = "Alegreya SC's small capitals over Source Serif 4, the most readable serif." },
	{ value = "oldtome", paper = "Spectral\\Spectral-SemiBold.ttf", label = "Old Tome", title = "IMFellEnglish\\IMFellEnglish-Regular.ttf", titleScale = 0.8,
	  text = "Spectral\\Spectral-Regular.ttf", textScale = 1.2, desc = "IM Fell English's aged print over Spectral." },
	{ value = "warband", paper = "CrimsonPro\\CrimsonPro-SemiBold.ttf", label = "Warband", title = "PirataOne\\PirataOne-Regular.ttf", titleScale = 0.85,
	  text = "CrimsonPro\\CrimsonPro-SemiBold.ttf", textScale = 1.25, desc = "Pirata One's blackletter over Crimson Pro SemiBold: the boldest look." },
	{ value = "clarity", paper = "NotoSans\\NotoSans-SemiBold.ttf", label = "Clarity", title = "Cinzel\\Cinzel-Bold.ttf", titleScale = 0.7,
	  text = "NotoSans\\NotoSans-Regular.ttf", textScale = 1, desc = "Cinzel titles, Noto Sans everywhere else: the easiest to read at small sizes." },
	{ value = "gothic", paper = "Alegreya\\Alegreya-SemiBold.ttf", label = "Gothic", title = "EnchantedLand.ttf", titleScale = 1,
	  text = "Alegreya\\Alegreya-Regular.ttf", textScale = 1.1, desc = "Enchanted Land's gothic titles kept, over Alegreya." },
}
local STYLE = {}
local styleValues = { { value = "custom", label = "Custom" } }
for _, s in ipairs(STYLES) do
	STYLE[s.value] = s
	styleValues[#styleValues + 1] = { value = s.value, label = s.label }
end

-- A face's own size correction in a role (0.19.4, the options audit): the
-- styles' titleScale for a title face, textScale for an interface text face;
-- 1 for a face no style names (the game's, Enchanted Land, the numbers' and
-- every other role's). Applied whenever the face is in use, as the kit's 1.5
-- is; the player's size (SCALE_KEY) comes on top, except on text with a size
-- of its own (the Quest Tracker's headers, Combat Text, the chat's borrowed
-- interface face), which takes the face's correction alone.
local FACE_FACTOR = { fontTitle = {}, fontText = {} }
for _, s in ipairs(STYLES) do
	local title, text = FACE_FACTOR.fontTitle, FACE_FACTOR.fontText
	title[FONT_DIR .. s.title] = title[FONT_DIR .. s.title] or s.titleScale
	text[FONT_DIR .. s.text] = text[FONT_DIR .. s.text] or s.textScale
end

-- The correction of a face in a role; a path nil, "" or "Keep the game's":
-- the role's default face (the title's Enchanted Land, the game's
-- elsewhere: both 1). For the installer's samples and MelloUI:MergeSettings
-- too (MelloUI.FontFaceFactor; M.FaceFactor once the module is made).
local function FaceFactor(roleKey, path)
	local byPath = FACE_FACTOR[roleKey]
	local f = byPath and type(path) == "string" and byPath[path]
	return type(f) == "number" and f or 1
end
MelloUI.FontFaceFactor = FaceFactor

-- What a style sets: { key = value }. The sizes back to 100%: the faces
-- bring their own correction (FaceFactor)
local function StyleSettings(s)
	return {
		fontTitle = FONT_DIR .. s.title, sizeTitle = 1,
		fontText = FONT_DIR .. s.text, sizeText = 1,
		fontChat = FONT_DIR .. NUMBERS, scaleChat = 1,
		fontChatText = FONT_DIR .. s.text,
		fontChatParchment = FONT_DIR .. s.paper,
	}
end

-- The styles and what one sets, for the installer: its Fresh start writes a
-- chosen style's faces and sizes with the style itself (here they are filled
-- in only when the style is picked while this module is on)
MelloUI.FontStyles = STYLES
MelloUI.FontStyleSettings = function(value)
	local s = STYLE[value]
	return s and StyleSettings(s) or nil
end

local defaults = { outline = "OUTLINE", style = "custom" }
local styleDesc = { "A preset: choosing a style changes every font at once -- the titles, the interface text, the chat and numbers, the chat text and the chat on parchment, the sizes back to 100% (each face brings its own size correction) -- each pairing themed with readability first. Fine-tune any of them afterwards (the style then shows Custom). The damage numbers keep their own choice." }
for _, s in ipairs(STYLES) do
	styleDesc[#styleDesc + 1] = s.label .. ": " .. s.desc
end
local options = {
	{ type = "header", name = "Fonts" },
	-- the row says it is a preset (user, 2026-09-24: "needs a comment to let
	-- the user know that this is a Font Style Preset and changes everything
	-- at once"): the grey hint beside its name, the tooltip in full
	{ type = "dropdown", key = "style", name = "Font Style", hint = "preset: changes every font at once", values = styleValues, desc = table.concat(styleDesc, "\n") },
}
for _, role in ipairs(ROLES) do
	IS_ROLE[role.key] = true
	defaults[role.key] = role.key == "fontTitle" and TITLE_DEFAULT or KEEP
	if SCALE_KEY[role.key] then
		defaults[SCALE_KEY[role.key]] = 1
	end
	options[#options + 1] = { type = "dropdown", key = role.key, name = role.name, values = BuildRoleList(), desc = role.desc }
end
-- Chat text (user, 2026-09-23: the Font Decisions should take over the chat's
-- messages and its input box): the chat windows, the chat's font objects
-- (the input box) and the whisper windows (they copy the chat) in a face of
-- their own. By default the interface text's face (user, 2026-09-24: the
-- chat stayed in the numbers' narrow face under a Custom style, /chatink),
-- else the chat & numbers one. A Font Style sets it to its reading face.
defaults.fontChatText = KEEP
do
	local values = BuildRoleList()
	values[1] = { value = KEEP, label = "Same as Interface text" }
	options[#options + 1] = { type = "dropdown", key = "fontChatText", name = "Chat text", values = values,
		desc = "The chat windows' messages, the chat's input box and the whisper windows. The same face as the Interface text unless you choose otherwise (the Chat & numbers face while that is the game's), so the chat follows the Font Styles and your own choice of reading face. The size stays the chat's own (Chat & numbers size)." }
end
-- Chat on parchment (user, 2026-09-24: the chat's font did not fit the
-- parchment): the chat windows and the whisper windows lying on their
-- parchment sheet take a face of their own, a semibold serif by default --
-- dark ink on the paper's grain reads best with some weight -- and a size
-- of their own; back to the chat's the moment the sheet goes.
-- (user, 2026-09-24: "make sure that the chat also respects the Font
-- Changes and should be included into Font Style"): the same as Chat text
-- until chosen; each Font Style sets its reading face's semibold cut
defaults.fontChatParchment = KEEP
defaults.scaleChatParchment = 1
do
	local values = BuildRoleList()
	values[1] = { value = KEEP, label = "Chat text, semibold" }
	options[#options + 1] = { type = "dropdown", key = "fontChatParchment", name = "Chat on parchment", values = values,
		desc = "The chat windows and whisper windows while they lie on their parchment sheet (Look > Parchment). By default the chat text's face in its semibold cut where it has one, heavier so the dark ink reads on the paper; each Font Style sets that cut of its reading face." }
end
options[#options + 1] = { type = "subheader", name = "Size and outline" }
options[#options + 1] = { type = "slider", key = "sizeText", name = "Interface text size", min = 0.7, max = 1.5, step = 0.05, percent = true,
	desc = "Every font drawn with the interface face, relative to its normal size; a Font Style puts it back to 100% (its faces bring their own correction). Not the text with a size of its own: the Quest Tracker, Combat Text, the chat (Chat & numbers size), FPS / Latency, Cooldown Timers, and the bar values while their size is set." }
options[#options + 1] = { type = "slider", key = "scaleChat", name = "Chat & numbers size", min = 0.7, max = 1.5, step = 0.05, percent = true,
	desc = "The chat windows (on top of the game's own chat font size) and every number." }
options[#options + 1] = { type = "slider", key = "sizeTitle", name = "Titles & headers size", min = 0.7, max = 1.5, step = 0.05, percent = true,
	desc = "Titles, headers, dialog names, mail and book text, and the kit's title face on the painted plates; a Font Style puts it back to 100% (its faces bring their own correction). Not the Quest Tracker's title and section headers or Combat Text's notices: they have sizes of their own." }
options[#options + 1] = { type = "slider", key = "scaleChatParchment", name = "Chat on parchment size", min = 0.7, max = 1.5, step = 0.05, percent = true,
	desc = "The chat and whisper windows' text on their parchment sheet, relative to the chat's own size." }
options[#options + 1] = { type = "dropdown", key = "outline", name = "Outline", values = {
		{ value = "NONE", label = "Keep original" },
		{ value = "OUTLINE", label = "Thin outline" },
		{ value = "THICKOUTLINE", label = "Thick outline" },
	},
	desc = "Force an outline on every light-coloured font. Dark text on parchment (quests, spellbook, dialogs) keeps its original look. MelloUI's own text in the world (notices, combat text, Gains lines) takes its outline from Notices: Outlined Text; this sets only how thick it is." }

local M = MelloUI:RegisterModule("Fonts", {
	title = "Fonts",
	desc = "One font per role: interface text, chat and numbers, titles, damage numbers; plus size and outline.",
	icon = "Interface\\Icons\\INV_Scroll_03",
	flavour = "One font for all of Azeroth. Pick it, scale it, outline it.",
	group = "The look", navOrder = 3,
	role = "look",
	tweak = { label = "Custom Fonts", desc = "The fonts and sizes used by the whole interface. Off: the game's own fonts.", order = 11 },
	enabledByDefault = true,   -- every role "default" changes nothing; UI Modifications drives the switch
	keep = { "paperFollows" },   -- a one-time step that was done: never in a profile
	defaults = defaults,
	options = options,
})

-- The face chosen for a role, or nil to keep the game's.
local function ChosenFont(roleKey)
	local db = M.db
	local value = db and db[roleKey]
	if type(value) == "string" and value ~= "" and value ~= KEEP then
		return value
	end
	return nil
end

M.FaceFactor = FaceFactor

-- The correction of the face a role draws in now (FaceFactor): all a text
-- with a size of its own takes from this module
local function FaceScale(roleKey)
	return FaceFactor(roleKey, ChosenFont(roleKey))
end

-- The chat text's face, nil to keep the game's, and the size factor that
-- face needs: its own choice; else the interface text's face with that
-- face's correction (a Font Style sizes its reading face to the game's
-- x-height with it; the chat's size stays its own, never Interface text
-- size's: 0.19.4); else the chat & numbers face
local function ChatTextFont()
	local own = ChosenFont("fontChatText")
	if own then
		return own, 1
	end
	local text = ChosenFont("fontText")
	if text then
		return text, FaceScale("fontText")
	end
	return ChosenFont("fontChat"), 1
end

-- A face's semibold cut, when the font list has one ("...-Regular.ttf" ->
-- "...-SemiBold.ttf"): the chat's face on the parchment by default
local knownFonts = nil
local function Semibold(path)
	if type(path) ~= "string" then
		return nil
	end
	local semi = path:gsub("%-Regular%.ttf$", "-SemiBold.ttf")
	if semi == path then
		return nil
	end
	if not knownFonts then
		knownFonts = {}
		for _, entry in ipairs(BuildFontList()) do
			knownFonts[entry.value] = true
		end
	end
	return knownFonts[semi] and semi or nil
end

--------------------------------------------------------------------------------
-- Font object discovery
--------------------------------------------------------------------------------

-- [fontObject] = { path, size, flags } captured before the first change.
local originals = setmetatable({}, { __mode = "k" })
local fontObjects = nil  -- list of { object = Font, name = string }
local chatObjects = setmetatable({}, { __mode = "k" })   -- the chat's own font objects (ChatFontNormal, ...): Chat text

local function IsFontObject(value)
	if type(value) ~= "table" or type(value.GetObjectType) ~= "function" or type(value.SetFont) ~= "function" then
		return false
	end
	local ok, objectType = pcall(value.GetObjectType, value)
	return ok and objectType == "Font"
end

local Remember   -- (below)

local function DiscoverFontObjects()
	if fontObjects then
		return fontObjects
	end
	fontObjects = {}
	for name, value in pairs(_G) do
		-- MelloUI's own font objects are left as they are made: the voice-over
		-- window's are dark ink on parchment, coloured per line, and the font
		-- object itself is white -- so the outline was forced onto them and
		-- the letters came out as smudges (player report, 2026-09-23: "the
		-- font shadow default on the overlay for voiceover looks absolutely
		-- wretched")
		if type(name) == "string" and not name:find("^MelloUI") and IsFontObject(value) then
			fontObjects[#fontObjects + 1] = { object = value, name = name }
			if name:find("^ChatFont") then
				chatObjects[value] = true
			end
		end
	end
	-- every one read before any is changed (the first ApplyAll / RestoreAll
	-- asks): a family's members as the game made them, and which members two
	-- objects share (Font families, below). The light fonts first, then the
	-- dark ink ones, the chat's last: a member they share is a light font's
	-- (the outline and the face most of its sharers want)
	local function Pass(object)
		if chatObjects[object] then
			return 3
		end
		local ok, r, g, b = pcall(object.GetTextColor, object)
		r, g, b = ok and SafeNumber(r), ok and SafeNumber(g), ok and SafeNumber(b)
		return (r and g and b and 0.299 * r + 0.587 * g + 0.114 * b < 0.5) and 2 or 1
	end
	for pass = 1, 3 do
		for _, entry in ipairs(fontObjects) do
			if Pass(entry.object) == pass then
				Remember(entry.object)
			end
		end
	end
	return fontObjects
end

--------------------------------------------------------------------------------
-- Font families (users' report, 2026-10-02: Chinese in the chat drawn as
-- boxes with this module on)
--
-- The game's fonts are font FAMILIES: a face per alphabet (Latin, Korean,
-- Simplified and Traditional Chinese, Cyrillic), and the client draws each
-- letter in its alphabet's member -- a Chinese name in an English client in
-- the Chinese face. SetFont with one file, the game's own included, makes a
-- font that one face, and the letters it lacks are boxes (the test card in
-- game: a family made with CreateFontFamily, or a family with only its Latin
-- member changed, keeps them). So:
--   a game font object  its Latin member takes the face, and its Cyrillic one
--                       when the face has Cyrillic letters (the game's own
--                       Cyrillic member draws them spaced out); every member
--                       the size and the outline; nothing else is touched.
--                       Many game fonts SHARE their members (one inherits
--                       another's): such a font follows the one it shares
--                       with, and takes a family of its own only when it
--                       wants another face, size or outline (the chat's font
--                       beside the numbers' one, a dark ink font), with its
--                       own alignment, indent, spacing, colour and shadow put
--                       back (the first cut gave every sharing font one with
--                       the chat's left alignment: the Game Menu's buttons
--                       and the cast bar's text went left -- user, 2026-10-02)
--   a frame of the chat a family of our own (a chat window, a whisper window
--                       and its answer box): the face for Latin (and
--                       Cyrillic), the chat font's own faces for the other
--                       alphabets, each member's shadow and colour as the
--                       chat font's; made once per face, size, flags and
--                       shadow (FitLineFonts asks after every redraw: a
--                       lookup, nothing made)
-- A client without families (no GetFontObjectForAlphabet / CreateFontFamily)
-- keeps SetFont. (Korean letters are boxes in this client with or without
-- MelloUI: it has no Korean face.)
--------------------------------------------------------------------------------

local Family = {
	ALPHABETS = { "roman", "korean", "simplifiedchinese", "traditionalchinese", "russian" },
	-- faces with Cyrillic letters: the fonts MelloUI ships (read from their
	-- files, 2026-10-02) and the game's Arial Narrow (its own Cyrillic member)
	CYRILLIC = { "notosans", "alegreya", "ebgaramond", "sourceserif4", "spectral", "prototype", "arialn" },
	made = setmetatable({}, { __mode = "k" }),      -- [base members][face][size][flags][1 shadow / 2 none] = family
	owner = setmetatable({}, { __mode = "k" }),     -- [member] = the game font object it was first read from
	count = 0,
}

function Family.Cyrillic(path)
	local lower = type(path) == "string" and path:lower() or ""
	for _, name in ipairs(Family.CYRILLIC) do
		if lower:find(name, 1, true) then
			return true
		end
	end
	return false
end

-- a font's members as they are now, by alphabet: { member, path, size,
-- flags }; nil for a font of one face (a member the font hands out for every
-- alphabet is that one face: kept once, as Latin), or a client without
-- families
function Family.Read(object)
	if type(object) ~= "table" or type(object.GetFontObjectForAlphabet) ~= "function" then
		return nil
	end
	local list, seen
	for _, alphabet in ipairs(Family.ALPHABETS) do
		local ok, member = pcall(object.GetFontObjectForAlphabet, object, alphabet)
		if ok and type(member) == "table" and member ~= object and type(member.GetFont) == "function"
			and not (seen and seen[member]) then
			local okF, path, size, flags = pcall(member.GetFont, member)
			path = okF and SafeText(path) or nil
			size = okF and SafeNumber(size) or nil
			if path and size then
				list, seen = list or {}, seen or {}
				seen[member] = true
				list[alphabet] = { member = member, path = path, size = size, flags = okF and SafeText(flags) or "" }
			end
		end
	end
	-- (one member only: a font of one face)
	if not (list and list.roman) or not (list.korean or list.simplifiedchinese or list.traditionalchinese or list.russian) then
		return nil
	end
	return list
end

-- each member's shadow and colour, read when a family is made from them
-- (only then: most fonts never need them)
function Family.Looks(members)
	for _, m in pairs(members) do
		if not m.shadow then
			local member = m.member
			local okO, x, y = pcall(member.GetShadowOffset, member)
			local okS, sr, sg, sb, sa = pcall(member.GetShadowColor, member)
			local okC, r, g, b, a = pcall(member.GetTextColor, member)
			m.shadow = { okO and SafeNumber(x) or 0, okO and SafeNumber(y) or 0, okS and SafeNumber(sr) or 0,
				okS and SafeNumber(sg) or 0, okS and SafeNumber(sb) or 0, okS and SafeNumber(sa) or 0 }
			m.colour = { okC and SafeNumber(r) or 1, okC and SafeNumber(g) or 1, okC and SafeNumber(b) or 1,
				okC and SafeNumber(a) or 1 }
		end
	end
end

-- the file a member takes: the face for Latin, and for Cyrillic when the face
-- (not the game's own Latin face) has those letters; else its own
function Family.FileFor(alphabet, own, face, roman)
	if alphabet == "roman" then
		return face
	end
	if alphabet == "russian" and face ~= roman and Family.Cyrillic(face) then
		return face
	end
	return own
end

-- a game font object's members: the face, the size share and the flags
function Family.Set(members, face, scale, FlagsOf)
	local roman = members.roman.path
	for alphabet, m in pairs(members) do
		pcall(m.member.SetFont, m.member, Family.FileFor(alphabet, m.path, face, roman),
			math.max(6, math.floor(m.size * scale + 0.5)), FlagsOf(m.flags))
	end
end

function Family.Restore(members)
	for _, m in pairs(members) do
		pcall(m.member.SetFont, m.member, m.path, m.size, m.flags)
	end
end

local function Slot(t, k)
	local v = t[k]
	if not v then
		v = {}
		t[k] = v
	end
	return v
end

-- a family of our own from a base's members: the face on Latin (and
-- Cyrillic), `size` for Latin and each other member at its own share of it,
-- the flags on all, each member's shadow and colour as the base's (noShadow:
-- none), and the region's own alignment, wrapped-line indent and line
-- spacing (the chat window keeps them on its font object: a font object's
-- own is centred -- the chat's lines came out centred, user 2026-10-02).
-- nil without families.
function Family.Make(base, face, size, flags, noShadow, justifyH, justifyV, indent, spacing)
	if type(CreateFontFamily) ~= "function" or not (base and base.roman) or type(face) ~= "string" then
		return nil
	end
	size = math.max(6, math.floor((tonumber(size) or base.roman.size) + 0.5))
	flags = flags or ""
	-- (false: left unset -- the font's default, which a region using it does
	-- not take over its own: Family.Own)
	if justifyH ~= false then
		justifyH = type(justifyH) == "string" and justifyH or "LEFT"
	end
	if justifyV ~= false then
		justifyV = type(justifyV) == "string" and justifyV or "MIDDLE"
	end
	indent = indent and true or false
	spacing = type(spacing) == "number" and spacing or 0
	local slot = Slot(Slot(Slot(Family.made, base), face), size)
	slot = Slot(Slot(Slot(Slot(Slot(slot, flags), justifyH), justifyV), indent), spacing)
	local kind = noShadow and 2 or 1
	if slot[kind] then
		return slot[kind]
	end
	Family.Looks(base)
	local list = {}
	for _, alphabet in ipairs(Family.ALPHABETS) do
		local m = base[alphabet]
		if m then
			list[#list + 1] = { alphabet = alphabet, file = Family.FileFor(alphabet, m.path, face, base.roman.path),
				height = math.max(6, math.floor(size * m.size / base.roman.size + 0.5)), flags = flags }
		end
	end
	Family.count = Family.count + 1
	local ok, fam = pcall(CreateFontFamily, "MelloUIFontFamily" .. Family.count, list)
	if not (ok and type(fam) == "table") then
		return nil
	end
	if justifyH then
		pcall(fam.SetJustifyH, fam, justifyH)
	end
	if justifyV then
		pcall(fam.SetJustifyV, fam, justifyV)
	end
	pcall(fam.SetIndentedWordWrap, fam, indent)
	pcall(fam.SetSpacing, fam, spacing)
	for _, alphabet in ipairs(Family.ALPHABETS) do
		local m = base[alphabet]
		local okM, member = pcall(fam.GetFontObjectForAlphabet, fam, alphabet)
		if m and okM and type(member) == "table" then
			local sh, c = m.shadow, m.colour
			pcall(member.SetShadowOffset, member, sh[1], sh[2])
			pcall(member.SetShadowColor, member, sh[3], sh[4], sh[5], noShadow and 0 or sh[6])
			pcall(member.SetTextColor, member, c[1], c[2], c[3], c[4])
			if justifyH then
				pcall(member.SetJustifyH, member, justifyH)
			end
			if justifyV then
				pcall(member.SetJustifyV, member, justifyV)
			end
			pcall(member.SetIndentedWordWrap, member, indent)
			pcall(member.SetSpacing, member, spacing)
		end
	end
	slot[kind] = fam
	return fam
end

Remember = function(object)
	if originals[object] then
		return originals[object]
	end
	local ok, path, size, flags = pcall(object.GetFont, object)
	if not ok or not path then
		return nil
	end
	local members = Family.Read(object)
	local shared = false
	if members then
		-- (its Latin member another font's already: it follows that one)
		local first = Family.owner[members.roman.member]
		shared = first ~= nil and first ~= object
		for _, m in pairs(members) do
			if not Family.owner[m.member] then
				Family.owner[m.member] = object
			end
		end
	end
	originals[object] = { path = path, size = size or 12, flags = flags or "", members = members, shared = shared,
		owner = shared and Family.owner[members.roman.member] or nil }
	return originals[object]
end

-- the chat font's members as the game made them: the base of the chat's own
-- families
function Family.ChatBase()
	local chat = _G.ChatFontNormal
	local original = chat and Remember(chat)
	return original and original.members
end

-- a font object's own look, as the game made it: what a family put on it
-- would replace (read once, the first time it needs a family)
function Family.Look(object)
	local okC, r, g, b, a = pcall(object.GetTextColor, object)
	local okO, x, y = pcall(object.GetShadowOffset, object)
	local okS, sr, sg, sb, sa = pcall(object.GetShadowColor, object)
	local okH, jh = pcall(object.GetJustifyH, object)
	local okV, jv = pcall(object.GetJustifyV, object)
	local okI, indent = pcall(object.GetIndentedWordWrap, object)
	local okP, spacing = pcall(object.GetSpacing, object)
	return { colour = okC and SafeNumber(r) and { r, g, b, SafeNumber(a) or 1 } or nil,
		offset = okO and SafeNumber(x) and SafeNumber(y) and { x, y } or nil,
		shadow = okS and SafeNumber(sr) and { sr, sg, sb, SafeNumber(sa) or 1 } or nil,
		justifyH = okH and SafeText(jh) or nil, justifyV = okV and SafeText(jv) or nil,
		indent = okI and indent == true, spacing = okP and SafeNumber(spacing) or nil }
end

-- a font object that shares its members and wants another face, size or
-- outline than the one it shares with: a family of its own, made with its
-- own alignment, indent and spacing, and its colour and shadow put back after
function Family.Own(object, original, face, size, flags)
	if type(object.SetFontObject) ~= "function" then
		return false
	end
	original.look = original.look or Family.Look(object)
	local l = original.look
	-- its alignment as read, but a default one (CENTER, MIDDLE: what a font
	-- object reads with none set) left unset: set, it is handed to every
	-- region using the font that has none of its own -- the chat's edit box
	-- began its text mid-line (2026-10-03, ChatFontNormal)
	local jh = (l.justifyH and l.justifyH ~= "CENTER") and l.justifyH or false
	local jv = (l.justifyV and l.justifyV ~= "MIDDLE") and l.justifyV or false
	local fam = Family.Make(original.members, face, size, flags, false, jh, jv, l.indent, l.spacing)
	if not fam then
		return false
	end
	pcall(object.SetFontObject, object, fam)
	if l.colour then
		pcall(object.SetTextColor, object, l.colour[1], l.colour[2], l.colour[3], l.colour[4])
	end
	if l.offset then
		pcall(object.SetShadowOffset, object, l.offset[1], l.offset[2])
	end
	if l.shadow then
		pcall(object.SetShadowColor, object, l.shadow[1], l.shadow[2], l.shadow[3], l.shadow[4])
	end
	if jh then
		pcall(object.SetJustifyH, object, jh)
	end
	if jv then
		pcall(object.SetJustifyV, object, jv)
	end
	if l.spacing then
		pcall(object.SetSpacing, object, l.spacing)
	end
	pcall(object.SetIndentedWordWrap, object, l.indent and true or false)
	return true
end

-- The face for a font object: its role's choice, else its own.
local function FontFor(object)
	local original = Remember(object)
	if not original then
		return nil
	end
	if chatObjects[object] then
		return ChatTextFont() or original.path
	end
	return ChosenFont(RoleFor(original.path)) or original.path
end

--------------------------------------------------------------------------------
-- Applying
--------------------------------------------------------------------------------

local function IsPlainNumber(v)
	return type(v) == "number" and not (issecretvalue and issecretvalue(v))
end

-- Dark text (quest text, spellbook names, dialog boxes, tooltips on parchment)
-- is drawn as ink on a light background. A black outline around it just
-- turns the letters into blobs, so those font objects keep their own flags.
local function IsDarkFont(object)
	local ok, r, g, b = pcall(object.GetTextColor, object)
	if not ok or not IsPlainNumber(r) or not IsPlainNumber(g) or not IsPlainNumber(b) then
		return false
	end
	local luminance = 0.299 * r + 0.587 * g + 0.114 * b
	return luminance < 0.5
end

local function EffectiveFlags(object, originalFlags)
	local outline = M.db and M.db.outline
	if outline and outline ~= "NONE" and not IsDarkFont(object) then
		return outline
	end
	return originalFlags
end

-- The scale of a role: its face's correction times its own slider.
local function ScaleFor(roleKey)
	local db = M.db
	local value = db and tonumber(db[SCALE_KEY[roleKey] or ""])
	return FaceScale(roleKey) * (value or 1)
end

local function ApplyToObject(object)
	local original = Remember(object)
	if not original then
		return
	end
	local scale = ScaleFor(chatObjects[object] and "fontChat" or RoleFor(original.path))
	local size = math.max(6, math.floor(original.size * scale + 0.5))
	local face = FontFor(object)
	local flags = EffectiveFlags(object, original.flags)
	-- a family: its members (Font families, above), else one face
	if original.members and not original.shared then
		Family.Set(original.members, face, scale, function(own)
			return EffectiveFlags(object, own)
		end)
		return
	end
	if original.members then
		-- sharing its members: it follows the font it shares them with, which
		-- changes them, unless it wants another face, size or outline
		local owner = original.owner
		local oo = owner and Remember(owner)
		if not original.own and oo and FontFor(owner) == face
			and ScaleFor(chatObjects[owner] and "fontChat" or RoleFor(oo.path)) == scale
			and EffectiveFlags(owner, oo.flags) == flags then
			return
		end
		original.own = Family.Own(object, original, face, size, flags) or nil
		if original.own then
			return
		end
	end
	pcall(object.SetFont, object, face, size, flags)
end

local function RestoreObject(object)
	local original = originals[object]
	if not original then
		return
	end
	if original.members and not original.shared then
		Family.Restore(original.members)
	elseif original.members then
		-- (a sharer back with its owner's members, unless it took a family of
		-- its own: that one in the game's faces then)
		if original.own then
			Family.Own(object, original, original.path, original.size, original.flags)
		end
	else
		pcall(object.SetFont, object, original.path, original.size, original.flags)
	end
end

--------------------------------------------------------------------------------
-- Parchment panels
--
-- Some Blizzard panels inherit a light font object (SystemFont_Large, ...) and
-- then recolour the individual FontString to dark ink. The font object check
-- above cannot see that, so those panels are walked after they update and any
-- dark FontString under them drops the forced outline again.
--------------------------------------------------------------------------------

-- [fontString] = { object = Font or nil } once we changed its flags.
local parchmentStrings = setmetatable({}, { __mode = "k" })

-- event: EventRegistry callback name; hook: global function to hooksecurefunc.
-- roots: frames to walk. all: strip every FontString, not only dark ones
-- (quest text switches to light colours with the Quest Text Contrast setting,
-- but is still parchment text and reads better without an outline).
local PARCHMENT_PANELS = {
	{
		event = "PlayerSpellsFrame.SpellBookFrame.DisplayedSpellsChanged",
		roots = function()
			return PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame
		end,
	},
	{
		hook = "QuestInfo_Display",
		all = true,
		roots = function()
			return QuestInfoFrame, QuestInfoObjectivesFrame, QuestInfoSpecialObjectivesFrame,
				QuestInfoTimerFrame, QuestInfoRequiredMoneyFrame, QuestInfoRewardsFrame,
				MapQuestInfoRewardsFrame
		end,
	},
}

local function FixParchmentString(fs, all)
	if not all and not IsDarkFont(fs) then
		return
	end
	local entry = parchmentStrings[fs]
	if not entry then
		local ok, object = pcall(fs.GetFontObject, fs)
		entry = { object = ok and object or nil }
		parchmentStrings[fs] = entry
	end
	if entry.object then
		-- Re-link to the (already retargeted) font object so path and size
		-- follow the current settings, then drop the outline only.
		pcall(fs.SetFontObject, fs, entry.object)
	end
	local ok, path, size, flags = pcall(fs.GetFont, fs)
	if ok and path and flags and flags ~= "" then
		pcall(fs.SetFont, fs, path, size, "")
	end
end

local function WalkParchment(frame, depth, all)
	if depth > 12 then
		return
	end
	if frame.GetRegions then
		for _, region in ipairs({ frame:GetRegions() }) do
			if region.GetObjectType and region:GetObjectType() == "FontString" then
				FixParchmentString(region, all)
			end
		end
	end
	if frame.GetChildren then
		for _, child in ipairs({ frame:GetChildren() }) do
			WalkParchment(child, depth + 1, all)
		end
	end
end

local function RestoreParchmentStrings()
	for fs, entry in pairs(parchmentStrings) do
		if entry.object then
			pcall(fs.SetFontObject, fs, entry.object)
		end
	end
	wipe(parchmentStrings)
end

local function WalkPanel(panel, shownOnly)
	for _, root in ipairs({ panel.roots() }) do
		if not shownOnly or not root.IsShown or root:IsShown() then
			WalkParchment(root, 0, panel.all)
		end
	end
end

local function ApplyParchmentPanels()
	if not M.isEnabled or not M.db or M.db.outline == "NONE" then
		-- Nothing to strip; let earlier fixes follow their font objects again.
		RestoreParchmentStrings()
		return
	end
	for _, panel in ipairs(PARCHMENT_PANELS) do
		WalkPanel(panel, false)
	end
end

-- One panel redrew itself: walk only that panel, and only while it is shown.
local function OnParchmentPanelUpdated(panel)
	if M.isEnabled and M.db and M.db.outline ~= "NONE" then
		WalkPanel(panel, true)
	end
end

local function HookParchmentPanels()
	for _, panel in ipairs(PARCHMENT_PANELS) do
		if not panel.hooked then
			local function Update()
				OnParchmentPanelUpdated(panel)
			end
			if panel.event and EventRegistry then
				EventRegistry:RegisterCallback(panel.event, Update, M)
				panel.hooked = true
			elseif panel.hook and type(_G[panel.hook]) == "function" then
				hooksecurefunc(panel.hook, Update)
				panel.hooked = true
			end
		end
	end
end

local chatHooked = false

local chatBaseOf = setmetatable({}, { __mode = "k" })   -- [chat frame] = the font size the player chose for it
-- The chat windows follow the chat role (their own face is Arial Narrow).
-- A chat window's size is the game's own chat font size (its menu) times
-- the chat role's slider; the game's size is remembered per window.
local function ChatBaseSize(frame, original)
	if chatBaseOf[frame] then
		return chatBaseOf[frame]
	end
	return original and original.size or 14
end

-- Is the chat on its parchment sheet (its lines in ink, Chat.lua)?
local function ChatOnParchment()
	local Kit = MelloUI.Kit
	return (MelloUI.QuestInk ~= nil and Kit and Kit.IsCovered and Kit:IsCovered("chat")
		and Kit.ParchmentOn and Kit:ParchmentOn("chat")) and true or false
end

-- A chat window's face and size on the stone (the chat's) or on the paper
-- (Chat on parchment and its size)
local function ChatWindowFace(frame, original, onPaper)
	local face, factor = ChatTextFont()
	local size = ChatBaseSize(frame, original) * ScaleFor("fontChat") * (factor or 1)
	if onPaper then
		face = ChosenFont("fontChatParchment") or Semibold(face) or face
		size = size * (tonumber(M.db and M.db.scaleChatParchment) or 1)
	end
	return face or original.path, math.max(6, math.floor(size + 0.5))
end

-- a chat window whose lines are ink (Chat.lua took its outline off: the
-- Chat module's inkFontOf), or nil
local function InkFont(frame)
	local chat = MelloUI:GetModule("Chat")
	return chat and chat.inkFontOf and chat.inkFontOf[frame]
end

local function ApplyChatWindow(frame)
	local original = Remember(frame)
	if not original then
		return
	end
	local _, _, flags = frame:GetFont()
	-- in ink on the paper (Chat.lua took its outline off): none, whatever
	-- the frame reports
	local inked = InkFont(frame) ~= nil
	if inked then
		flags = ""
	end
	local face, size = ChatWindowFace(frame, original, frame ~= _G.COMBATLOG and ChatOnParchment())
	M:ChatFace(frame, face, size, flags or original.flags, inked)
end

-- The chat windows' edit boxes LEFT, as the game has them (user, 2026-10-03,
-- /chdump edit: the line typed began mid-box, the box at CENTER): a box's
-- text font is a copy of ChatFontNormal, which takes a family of its own
-- here (Font families) -- a font made at runtime brings a CENTER of its own,
-- where the game's XML fonts leave it unset -- and the box took it over. Set
-- after each pass over the fonts (a later change of ChatFontNormal hands it
-- down again) and on each whisper window's box as it opens. Every chat
-- window's, the whisper windows' too (CHAT_FRAMES)
function Family.EditBoxesLeft()
	for _, name in ipairs(CHAT_FRAMES or {}) do
		local frame = _G[name]
		local box = frame and frame.editBox
		if box and box.SetJustifyH then
			pcall(box.SetJustifyH, box, "LEFT")
		end
	end
end

local function ApplyChatWindows()
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. i]
		if frame and frame.GetFont then
			ApplyChatWindow(frame)
		end
	end
	Family.EditBoxesLeft()
	if not Family.whisperHooked and type(FCF_OpenTemporaryWindow) == "function" then
		Family.whisperHooked = true
		hooksecurefunc("FCF_OpenTemporaryWindow", Family.EditBoxesLeft)
	end
	if not chatHooked and type(FCF_SetChatWindowFontSize) == "function" then
		chatHooked = true
		hooksecurefunc("FCF_SetChatWindowFontSize", function(_, chatFrame, fontSize)
			if chatFrame and chatFrame.GetFont then
				if tonumber(fontSize) then
					chatBaseOf[chatFrame] = tonumber(fontSize)   -- the game's size, chosen by the player
				end
				if M.isEnabled then
					ApplyChatWindow(chatFrame)
					-- (the chat's family on: the whisper windows follow, Chat.lua)
					MelloUI:Fire("fonts")
				end
			end
		end)
	end
end

-- For Chat.lua: the chat windows again (the parchment switched), and the
-- face and size a whisper window takes after a chat window, on the stone or
-- on the paper
function M:RefreshChatWindows()
	ApplyChatWindows()
end

function M:ChatWindowFont(frame, onPaper)
	local original = frame and Remember(frame)
	if not original then
		return nil
	end
	return ChatWindowFace(frame, original, onPaper)
end

-- The chat's face on one of its frames (a chat window, a whisper window, its
-- answer box: Chat.lua too, with this module on or off): a family of our own
-- (Font families, above), the game's faces kept for the other alphabets; one
-- face by SetFont where the client has no families. True when a family was
-- put on.
function M:ChatFamily(face, size, flags, noShadow, justifyH, justifyV, indent, spacing)
	return Family.Make(Family.ChatBase(), face, size, flags, noShadow, justifyH, justifyV, indent, spacing)
end

-- whether the client has families (and the chat font is one)
function M:HasFamilies()
	return type(CreateFontFamily) == "function" and Family.ChatBase() ~= nil
end

function M:ChatFace(region, face, size, flags, noShadow)
	if not (region and face and size) then
		return false
	end
	-- (the region's alignment, indent and spacing kept: the chat window's
	-- are LEFT and indented, on the copy of its font object the game made
	-- for it -- ChatFrameOverrides.lua's OnLoad)
	local okH, justifyH = pcall(region.GetJustifyH, region)
	local okV, justifyV = pcall(region.GetJustifyV, region)
	local okI, indent = pcall(region.GetIndentedWordWrap, region)
	local okS, spacing = pcall(region.GetSpacing, region)
	local fam = type(region.SetFontObject) == "function"
		and self:ChatFamily(face, size, flags, noShadow, okH and SafeText(justifyH), okV and SafeText(justifyV),
			okI and indent == true, okS and SafeNumber(spacing))
	if fam then
		local okO, now = pcall(region.GetFontObject, region)
		if not (okO and now == fam) then
			pcall(region.SetFontObject, region, fam)
		end
		return true
	end
	pcall(region.SetFont, region, face, size, flags or "")
	return false
end

local function RestoreChatWindows()
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. i]
		local original = frame and originals[frame]
		if original then
			local _, _, flags = frame:GetFont()
			M:ChatFace(frame, original.path, ChatBaseSize(frame, original), flags or original.flags, InkFont(frame) ~= nil)
		end
	end
	Family.EditBoxesLeft()   -- (ChatFontNormal keeps a family of its own: its CENTER still there)
end

-- The old single Font Size slider, folded into the role sizes once and taken out
-- of the save (0.15.0: its default is gone, so the 1 every older save holds
-- would otherwise go into every profile and the settings backup). At the
-- first load (OnInit) and whenever the fonts are applied (a profile loaded
-- with an old slider in it).
local function MigrateScale(db)
	local old = tonumber(db.scale)
	db.scale = nil
	if not old or math.abs(old - 1) < 0.001 then
		return
	end
	for _, key in pairs(SCALE_KEY) do
		if math.abs((tonumber(db[key]) or 1) - 1) < 0.001 then
			db[key] = old
		end
	end
end

--------------------------------------------------------------------------------
-- For MelloUI's own strings
--
-- A string another module sizes itself (the Route's tracking notice, its
-- arrow and marker texts) is not drawn through a game font object, so the
-- retargeting above never reaches it (user, 2026-09-24: "The Tracking Notice
-- and the Arrow Text should respect the Changes in Font Changing"). Such a
-- string is handed to MelloUI:StyleFont (below), which gives it its role's
-- face, size factor and outline and follows every change; it keeps its own
-- base size and look.
--------------------------------------------------------------------------------

-- The face, size factor and flags for a string of the given role whose own
-- face and flags (without this module) are fallbackPath and fallbackFlags.
-- Off, or a role on "Keep the game's", gives the string's own face back; the
-- size factor and the Outline apply as they do to the game's font objects.
function M:FaceFor(roleKey, fallbackPath, fallbackFlags)
	if not (self.isEnabled and self.db) then
		return fallbackPath, 1, fallbackFlags
	end
	local outline = self.db.outline
	local flags = (outline and outline ~= "NONE") and outline or fallbackFlags
	return ChosenFont(roleKey) or fallbackPath, ScaleFor(roleKey), flags
end

-- A game font object's own face, size and flags, as they were before this
-- module changed it: the base for a string that started from that object.
function M:BaseFont(object)
	local original = object and Remember(object)
	if original then
		return original.path, original.size, original.flags
	end
	return nil
end

-- fn() runs after every change of the fonts (a face, a size, the Outline, a
-- Font Style) and when the module is switched on or off: an alias of the
-- bus's 'fonts' topic (audit, 2026-09-24, rank 5), fired once the fonts are
-- applied; one that raises goes to the error handler, the others still run.
function M:OnFontsChanged(fn)
	if type(fn) == "function" then
		MelloUI:On("fonts", fn)
	end
end

local function FireFontsChanged()
	MelloUI:Fire("fonts")
end

--------------------------------------------------------------------------------
-- MelloUI:StyleFont: the one font path for MelloUI's own strings (audit #12,
-- 2026-09-25: lifted from the Route's own copy, which every new text would
-- otherwise have copied again)
--
-- MelloUI:StyleFont(fs, role, object, size, flags, outline)
--   fs       a FontString (or anything with SetFont, an EditBox). Kept in a
--            weak registry and re-applied at every 'fonts' Fire until it is
--            collected; styling it again replaces its entry where it stands.
--   role     "fontText", "fontChat", "fontTitle" or "fontDamage": the role
--            whose face and size slider the text follows. nil (or any other
--            value) takes the role of the object's own face, as the game's
--            font objects do (Friz Quadrata -> fontText, Arial Narrow ->
--            fontChat, Morpheus -> fontTitle, Skurri -> fontDamage).
--   object   the game font object the text starts from (GameFontNormal, ...):
--            its face, size and flags as they were before this module
--            changed them are the text's base. nil (or not a font object):
--            fs leaves the registry and keeps the font it has.
--   size     the text's own base size, in the object's terms (nil: the
--            object's), times the role's size slider
--   flags    the text's own base flags (nil: the object's; "": none)
--   outline  what the Outline setting does to the text:
--            nil    it follows it (the default, as the game's light fonts):
--                   Thin or Thick replaces the base flags while this module
--                   is on; "Keep original", or the module off, keeps them
--            false  never outlined: the base flags without OUTLINE or
--                   THICKOUTLINE, whatever the Outline says (ink on
--                   parchment, a soft text on its own shade)
--            true   always outlined: the Outline's own while it forces one,
--                   else a thin OUTLINE, with the module on or off (an
--                   "Outlined Text" switch: style the text again on a flip)
--   faceOnly what the role's size does to the text: nil, the face's
--            correction times the role's size slider; true, nothing (its
--            size is another setting's); "own", the face's correction
--            alone (a text with a size slider of its own: 0.19.4)
-- The font is set at once and again at every 'fonts' Fire (a face, a size,
-- the Outline, a Font Style, the module on or off). The listener is taken
-- when this file loads, so it runs before every listener taken later (the
-- files after this one, every window at its first open): such a listener
-- already measures the new size. Off, or a role on "Keep the game's", a text
-- has its base face and size exactly; a face the client cannot load leaves
-- it on its base face. Nothing is made per Fire. Defined here, after Core:
-- a file loaded before this one calls it at run time, never at file scope.
--------------------------------------------------------------------------------

do
	local styled = setmetatable({}, { __mode = "k" })   -- [fs] = { role, object, size, flags, outline }

	-- flags without their outline words, and an outline word joined to what
	-- is left: kept, so a Fire makes no string
	local bare, joined = {}, {}

	local function Bare(flags)
		local b = bare[flags]
		if b == nil then
			local words = {}
			for word in flags:gmatch("[^%s,]+") do
				if word:find("MONOCHROME", 1, true) then
					words[#words + 1] = "MONOCHROME"
				elseif not word:find("OUTLINE", 1, true) and word ~= "THICK" then
					words[#words + 1] = word
				end
			end
			b = table.concat(words, ",")
			bare[flags] = b
		end
		return b
	end

	local function Outlined(word, rest)
		if rest == "" then
			return word
		end
		local byWord = joined[rest]
		if not byWord then
			byWord = {}
			joined[rest] = byWord
		end
		local s = byWord[word]
		if not s then
			s = word .. "," .. rest
			byWord[word] = s
		end
		return s
	end

	-- the face, size and flags a text has without this module: its font
	-- object's own (as before this module changed it), with the text's own
	-- size and flags where it sets them
	local function Base(entry)
		local object = entry.object
		local path, size, flags
		local original = Remember(object)
		if original then
			path, size, flags = original.path, original.size, original.flags
		else
			local ok, p, s, f = pcall(object.GetFont, object)
			if ok then
				path, size, flags = p, s, f
			end
		end
		return SafeText(path), entry.size or SafeNumber(size), entry.flags or SafeText(flags) or ""
	end

	local function Apply(fs, entry)
		local basePath, baseSize, baseFlags = Base(entry)
		if not (basePath and baseSize) then
			return
		end
		local path, factor, forced = basePath, 1, nil
		local db = M.isEnabled and M.db
		if db then
			local role = entry.role
			if not IS_ROLE[role] then
				role = RoleFor(basePath)
			end
			path = ChosenFont(role) or basePath
			if entry.faceOnly == "own" then
				factor = FaceScale(role)   -- (a size of its own: the face's correction alone)
			elseif entry.faceOnly then
				factor = 1   -- (its size is another setting's: Your Damage's, Numbers Over Enemies)
			else
				factor = tonumber(ScaleFor(role)) or 1
			end
			local outline = db.outline
			forced = (outline and outline ~= "NONE") and outline or nil
		end
		local flags
		if entry.outline == nil then
			flags = forced or baseFlags
		elseif entry.outline then
			flags = Outlined((forced and forced ~= "") and forced or "OUTLINE", Bare(baseFlags))
		else
			flags = Bare(baseFlags)
		end
		-- the base size as it is at 100%, so the module off changes nothing
		local size = baseSize
		if math.abs(factor - 1) > 0.001 then
			size = math.max(6, math.floor(baseSize * factor + 0.5))
		end
		-- a face the client cannot load (a font file gone) leaves the text on its own
		local ok, set = pcall(fs.SetFont, fs, path, size, flags)
		if not ok or set == false then
			pcall(fs.SetFont, fs, basePath, size, flags)
		end
	end

	local function Refresh()
		for fs, entry in pairs(styled) do
			Apply(fs, entry)
		end
	end
	MelloUI:On("fonts", Refresh, "Fonts own strings")

	function MelloUI:StyleFont(fs, role, object, size, flags, outline, faceOnly)
		if not fs then
			return
		end
		if type(object) ~= "table" then
			styled[fs] = nil
			return
		end
		local entry = styled[fs]
		if not entry then
			entry = {}
			styled[fs] = entry
		end
		entry.role, entry.object, entry.size, entry.flags = role, object, SafeNumber(size), SafeText(flags)
		entry.faceOnly = faceOnly == "own" and "own" or (faceOnly and true or nil)
		if outline == nil then
			entry.outline = nil
		else
			entry.outline = outline and true or false
		end
		Apply(fs, entry)
	end
end

local function ApplyAll()
	MigrateScale(M.db)
	for _, entry in ipairs(DiscoverFontObjects()) do
		ApplyToObject(entry.object)
	end
	-- the kit's title plates follow the title role: its face (the game's
	-- own for "Keep the game's") and its size slider (set per string, not
	-- through a font object)
	if MelloUI.Kit and MelloUI.Kit.SetTitleFace then
		local value = M.db.fontTitle
		MelloUI.Kit:SetTitleFace((type(value) == "string" and value ~= "" and value ~= KEEP) and value or false)
	end
	if MelloUI.Kit and MelloUI.Kit.SetTitleSizeFactor then
		MelloUI.Kit:SetTitleSizeFactor(ScaleFor("fontTitle"), FaceScale("fontTitle"))
	end
	ApplyChatWindows()
	HookParchmentPanels()
	ApplyParchmentPanels()
	FireFontsChanged()
end

local function RestoreAll()
	for _, entry in ipairs(DiscoverFontObjects()) do
		RestoreObject(entry.object)
	end
	if MelloUI.Kit and MelloUI.Kit.SetTitleFace then
		MelloUI.Kit:SetTitleFace(nil)   -- the kit's default face with the module off
	end
	if MelloUI.Kit and MelloUI.Kit.SetTitleSizeFactor then
		MelloUI.Kit:SetTitleSizeFactor(1, 1)
	end
	RestoreChatWindows()
	RestoreParchmentStrings()
	FireFontsChanged()   -- isEnabled is already false: the strings take their own fonts back
end

--------------------------------------------------------------------------------
-- World fonts (read by the client itself, so they must be set early)
--------------------------------------------------------------------------------

-- The world faces follow their roles: names above characters are interface
-- text, the floating combat text is the damage face.
local WORLD_FONT_GLOBALS = {
	fontText = { "UNIT_NAME_FONT", "NAMEPLATE_FONT" },
	fontDamage = { "DAMAGE_TEXT_FONT" },
}

local worldOriginals = {}

local function ApplyWorldFonts(db)
	for roleKey, globals in pairs(WORLD_FONT_GLOBALS) do
		local value = db and db[roleKey]
		local face = (type(value) == "string" and value ~= "" and value ~= KEEP) and value or nil
		for _, name in ipairs(globals) do
			if worldOriginals[name] == nil and type(_G[name]) == "string" then
				worldOriginals[name] = _G[name]
			end
			if face then
				_G[name] = face
			elseif worldOriginals[name] then
				_G[name] = worldOriginals[name]
			end
		end
	end
end

-- A font object in the game's own numbers face (its DAMAGE_TEXT_FONT as the
-- game had it): the base of a string drawn as the numbers over the enemies
-- (0.17.0: Your Damage, the user's pick "one font for every number over
-- enemies"), styled with the "fontDamage" role -- the Game Numbers Font face
-- while one is chosen, the game's own on "Keep the game's" or this module off.
-- Made on the first ask.
local gameNumbers = nil
function MelloUI:GameNumbersFont()
	if not gameNumbers and type(CreateFont) == "function" then
		local face = worldOriginals.DAMAGE_TEXT_FONT or rawget(_G, "DAMAGE_TEXT_FONT")
		gameNumbers = CreateFont("MelloUIGameNumbersFont")
		if type(face) == "string" and face ~= "" then
			pcall(gameNumbers.SetFont, gameNumbers, face, 14, "")
		elseif _G.GameFontHighlight then
			gameNumbers:CopyFontObject(_G.GameFontHighlight)
		end
	end
	return gameNumbers
end

local function RestoreWorldFonts()
	for name, value in pairs(worldOriginals) do
		_G[name] = value
	end
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

function M:OnAddonLoaded(db)
	self.db = db
	ApplyWorldFonts(db)
end

function M:OnInit(db)
	self.db = db
	MigrateScale(db)
end

function M:OnEnable(db)
	self.db = db
	-- Chat on parchment had its own fixed default for a day (Source Serif 4
	-- SemiBold); it follows the chat's font and the Font Style now: the old
	-- default, never chosen, gives way once
	if not db.paperFollows then
		if db.fontChatParchment == FONT_DIR .. "SourceSerif4\\SourceSerif4-SemiBold.ttf" then
			local st = STYLE[db.style]
			db.fontChatParchment = st and (FONT_DIR .. st.paper) or KEEP
		end
		db.paperFollows = true
	end
	-- a Font Style named whose faces were never written (picked while this
	-- module was off: OnSettingChanged runs only while it is on): written
	-- now, so the style's name never stands over other faces (0.19.4)
	local st = STYLE[db.style]
	if st then
		local set, stale = StyleSettings(st), false
		for k, v in pairs(set) do
			if k:sub(1, 4) == "font" and db[k] ~= v then
				stale = true
			end
		end
		if stale then
			for k, v in pairs(set) do
				db[k] = v
			end
		end
	end
	ApplyWorldFonts(db)
	ApplyAll()
end

function M:OnDisable()
	RestoreAll()
	RestoreWorldFonts()
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "style" then
		local s = STYLE[value]
		if s then
			for k, v in pairs(StyleSettings(s)) do
				db[k] = v
			end
			ApplyAll()
			ApplyWorldFonts(db)
			MelloUI:Print("Font Style: %s. The names above characters follow after /reload.", s.label)
			if MelloUI.RefreshConfig then
				MelloUI:RefreshConfig()
			end
		end
		return
	end
	-- a font or size changed by hand: the style no longer describes it
	local s = STYLE[db.style]
	if s then
		local want = StyleSettings(s)[key]
		if want ~= nil and want ~= db[key] then
			db.style = "custom"
			if MelloUI.RefreshConfig then
				MelloUI:RefreshConfig()
			end
		end
	end
	ApplyAll()
	if key == "fontText" or key == "fontDamage" then
		ApplyWorldFonts(db)
		MelloUI:Print("The names above characters and the floating combat text follow after /reload.")
	end
end

MelloUI:Profile("Fonts", "parchment panel walk", OnParchmentPanelUpdated)

-- What this module keeps beside the game's frames (hard rule 1: weak-keyed
-- tables, never keys on the frames), for the dumps and the tests: read only
M.kept = { chatBaseOf = chatBaseOf }
