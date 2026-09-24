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
	  desc = "The chat windows and every number: bar values, cooldown counts, stack counts, damage on unit frames." },
	{ key = "fontTitle",  match = "morpheus", name = "Titles & headers (Morpheus)",
	  desc = "Window titles, quest and item names in dialogs, mail and book text, and the kit's title plates while the reskin is on. Enchanted Land unless you choose otherwise; Keep the game's puts Morpheus back everywhere, the plates included." },
	{ key = "fontDamage", match = "skurri",   name = "Damage numbers (Skurri)",
	  desc = "The floating combat text in the world (after /reload)." },
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
-- single slider, is folded into them once and kept at 1.
local SCALE_KEY = { fontText = "scaleText", fontChat = "scaleChat", fontTitle = "scaleTitle", fontDamage = "scaleDamage" }
local SCALE_NAME = { fontText = "Interface text size", fontChat = "Chat & numbers size", fontTitle = "Titles & headers size", fontDamage = "Damage numbers size" }
local SCALE_DESC = {
	fontText = "Every font drawn with the interface face, relative to its normal size.",
	fontChat = "The chat windows (on top of the game's own chat font size) and every number.",
	fontTitle = "Titles, headers, dialog names, mail and book text, and the kit's own title face on the painted plates.",
	fontDamage = "The numbers drawn with the damage face in the interface (the scrolling combat text over you). The floating numbers in the world keep the engine's size.",
}
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

-- What a style sets: { key = value }
local function StyleSettings(s)
	return {
		fontTitle = FONT_DIR .. s.title, scaleTitle = s.titleScale,
		fontText = FONT_DIR .. s.text, scaleText = s.textScale,
		fontChat = FONT_DIR .. NUMBERS, scaleChat = 1,
		fontChatText = FONT_DIR .. s.text,
		fontChatParchment = FONT_DIR .. s.paper,
	}
end

local defaults = { scale = 1, outline = "OUTLINE", style = "custom" }
local styleDesc = { "A preset: choosing a style changes every font at once -- the titles, the interface text, the chat and numbers, the chat text and the chat on parchment, with their sizes -- each pairing themed with readability first. Fine-tune any of them afterwards (the style then shows Custom). The damage numbers keep their own choice." }
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
	defaults[role.key] = role.key == "fontTitle" and TITLE_DEFAULT or KEEP
	defaults[SCALE_KEY[role.key]] = 1
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
		desc = "The chat windows' messages, the chat's input box and the whisper windows. The same face as the Interface text unless you choose otherwise (the Chat & numbers face while that is the game's), so the chat follows the Font Styles and your own choice of reading face." }
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
		desc = "The chat windows and whisper windows while they lie on their parchment sheet (Dynamic UI Modification, Parchment). By default the chat text's face in its semibold cut where it has one, heavier so the dark ink reads on the paper; each Font Style sets that cut of its reading face." }
end
options[#options + 1] = { type = "subheader", name = "Size and outline" }
for _, role in ipairs(ROLES) do
	options[#options + 1] = { type = "slider", key = SCALE_KEY[role.key], name = SCALE_NAME[role.key], min = 0.7, max = 1.5, step = 0.05, percent = true,
		desc = SCALE_DESC[role.key] }
end
options[#options + 1] = { type = "slider", key = "scaleChatParchment", name = "Chat on parchment size", min = 0.7, max = 1.5, step = 0.05, percent = true,
	desc = "The chat and whisper windows' text on their parchment sheet, relative to the chat's own size." }
options[#options + 1] = { type = "dropdown", key = "outline", name = "Outline", values = {
		{ value = "NONE", label = "Keep original" },
		{ value = "OUTLINE", label = "Thin outline" },
		{ value = "THICKOUTLINE", label = "Thick outline" },
	},
	desc = "Force an outline on every light-coloured font. Dark text on parchment (quests, spellbook, dialogs) keeps its original look." }

local M = MelloUI:RegisterModule("Fonts", {
	title = "Fonts",
	desc = "One font per role: interface text, chat and numbers, titles, damage numbers; plus size and outline.",
	enabledByDefault = true,   -- every role "default" changes nothing; UI Modifications drives the switch
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

-- The chat text's face (Chat text, else Chat & numbers), nil to keep the game's
local ScaleFor   -- (below)

-- The chat text's face, nil to keep the game's, and the size factor that
-- face needs: its own choice; else the interface text's face at the
-- interface text's size factor (a Font Style sizes its reading face to the
-- game's x-height with it); else the chat & numbers face
local function ChatTextFont()
	local own = ChosenFont("fontChatText")
	if own then
		return own, 1
	end
	local text = ChosenFont("fontText")
	if text then
		return text, ScaleFor("fontText")
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
	return fontObjects
end

local function Remember(object)
	if originals[object] then
		return originals[object]
	end
	local ok, path, size, flags = pcall(object.GetFont, object)
	if not ok or not path then
		return nil
	end
	originals[object] = { path = path, size = size or 12, flags = flags or "" }
	return originals[object]
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

-- The scale of a role, from its own slider.
function ScaleFor(roleKey)
	local db = M.db
	local value = db and tonumber(db[SCALE_KEY[roleKey] or ""])
	return value or 1
end

local function ApplyToObject(object)
	local original = Remember(object)
	if not original then
		return
	end
	local scale = ScaleFor(chatObjects[object] and "fontChat" or RoleFor(original.path))
	local size = math.max(6, math.floor(original.size * scale + 0.5))
	pcall(object.SetFont, object, FontFor(object), size, EffectiveFlags(object, original.flags))
end

local function RestoreObject(object)
	local original = originals[object]
	if original then
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

-- The chat windows follow the chat role (their own face is Arial Narrow).
-- A chat window's size is the game's own chat font size (its menu) times
-- the chat role's slider; the game's size is remembered per window.
local function ChatBaseSize(frame, original)
	if frame.melloChatBase then
		return frame.melloChatBase
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

local function ApplyChatWindow(frame)
	local original = Remember(frame)
	if not original then
		return
	end
	local _, _, flags = frame:GetFont()
	-- in ink on the paper (Chat.lua took its outline off): none, whatever
	-- the frame reports
	if frame.melloInkFont then
		flags = ""
	end
	local face, size = ChatWindowFace(frame, original, frame ~= _G.COMBATLOG and ChatOnParchment())
	pcall(frame.SetFont, frame, face, size, flags or original.flags)
end

local function ApplyChatWindows()
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. i]
		if frame and frame.GetFont then
			ApplyChatWindow(frame)
		end
	end
	if not chatHooked and type(FCF_SetChatWindowFontSize) == "function" then
		chatHooked = true
		hooksecurefunc("FCF_SetChatWindowFontSize", function(_, chatFrame, fontSize)
			if chatFrame and chatFrame.GetFont then
				if tonumber(fontSize) then
					chatFrame.melloChatBase = tonumber(fontSize)   -- the game's size, chosen by the player
				end
				if M.isEnabled then
					ApplyChatWindow(chatFrame)
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

local function RestoreChatWindows()
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. i]
		local original = frame and originals[frame]
		if original then
			local _, _, flags = frame:GetFont()
			pcall(frame.SetFont, frame, original.path, ChatBaseSize(frame, original), flags or original.flags)
		end
	end
end

-- The old single Font Size slider, folded into the four once.
local function MigrateScale(db)
	local old = tonumber(db.scale)
	if not old or math.abs(old - 1) < 0.001 then
		return
	end
	for _, key in pairs(SCALE_KEY) do
		if math.abs((tonumber(db[key]) or 1) - 1) < 0.001 then
			db[key] = old
		end
	end
	db.scale = 1
end

--------------------------------------------------------------------------------
-- For MelloUI's own strings
--
-- A string another module sizes itself (the Route's tracking notice, its
-- arrow and marker texts) is not drawn through a game font object, so the
-- retargeting above never reaches it (user, 2026-09-24: "The Tracking Notice
-- and the Arrow Text should respect the Changes in Font Changing"). Such a
-- module asks for a role's face, size factor and outline here and listens
-- for changes; it keeps its own base size and look.
--------------------------------------------------------------------------------

local changeListeners = {}

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
-- Font Style) and when the module is switched on or off.
function M:OnFontsChanged(fn)
	if type(fn) == "function" then
		changeListeners[#changeListeners + 1] = fn
	end
end

local function FireFontsChanged()
	for _, fn in ipairs(changeListeners) do
		local ok, err = pcall(fn)
		if not ok then
			geterrorhandler()(err)
		end
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
		MelloUI.Kit:SetTitleSizeFactor(ScaleFor("fontTitle"))
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
		MelloUI.Kit:SetTitleSizeFactor(1)
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
