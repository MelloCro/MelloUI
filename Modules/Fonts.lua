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

local M = MelloUI:RegisterModule("Fonts", {
	title = "Fonts",
	desc = "Change the font and font size used by the whole interface.",
	enabledByDefault = false,
	defaults = {
		font = [[Interface\AddOns\]] .. ADDON_NAME .. [[\Media\Fonts\Prototype.ttf]],
		scale = 1,
		outline = "OUTLINE",
		numbers = true,
		chat = true,
		nameplates = true,
		worldNames = true,
		worldDamage = false,
	},
	options = {
		{ type = "header", name = "Font" },
		{ type = "dropdown", key = "font", name = "Font", values = BuildFontList(),
		  desc = "Font used for the interface. Custom .ttf files go into MelloUI\\Media\\Fonts and are listed in Media\\CustomFonts.lua." },
		{ type = "slider", key = "scale", name = "Font Size", min = 0.7, max = 1.5, step = 0.05, percent = true,
		  desc = "Scales every font relative to its normal size." },
		{ type = "dropdown", key = "outline", name = "Outline", values = {
			{ value = "NONE", label = "Keep original" },
			{ value = "OUTLINE", label = "Thin outline" },
			{ value = "THICKOUTLINE", label = "Thick outline" },
		  },
		  desc = "Force an outline on every light-coloured font. Dark text on parchment (quests, spellbook, dialogs) keeps its original look. Friz Quadrata with a thin outline is the look used by RougeUI." },
		{ type = "header", name = "Apply To" },
		{ type = "toggle", key = "numbers", name = "Number Fonts",
		  desc = "Also replace the number fonts (cooldown timers, stack counts, damage on unit frames). Turn off to keep Arial Narrow for numbers." },
		{ type = "toggle", key = "chat", name = "Chat Windows",
		  desc = "Also replace the font of the chat windows." },
		{ type = "toggle", key = "nameplates", name = "Nameplates",
		  desc = "Also replace the nameplate name, level and cast bar fonts." },
		{ type = "header", name = "World (needs /reload)" },
		{ type = "toggle", key = "worldNames", name = "3D Character Names",
		  desc = "Use the chosen font for the names floating above characters in the world. Takes effect after /reload." },
		{ type = "toggle", key = "worldDamage", name = "Floating Combat Text",
		  desc = "Use the chosen font for the damage and healing numbers in the world. Takes effect after /reload." },
	},
})

--------------------------------------------------------------------------------
-- Font object discovery
--------------------------------------------------------------------------------

-- [fontObject] = { path, size, flags } captured before the first change.
local originals = setmetatable({}, { __mode = "k" })
local fontObjects = nil  -- list of { object = Font, name = string }

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
		if type(name) == "string" and IsFontObject(value) then
			fontObjects[#fontObjects + 1] = { object = value, name = name }
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

local function IsNumberFont(name)
	return name:find("Number") ~= nil
end

local function IsNamePlateFont(name)
	return name:find("NamePlate") ~= nil or name:find("Nameplate") ~= nil
end

local function ShouldTouch(name)
	local db = M.db
	if not db.numbers and IsNumberFont(name) then
		return false
	end
	if not db.nameplates and IsNamePlateFont(name) then
		return false
	end
	return true
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

local function ApplyToObject(object, name, path, scale)
	local original = Remember(object)
	if not original then
		return
	end
	local size = math.max(6, math.floor(original.size * scale + 0.5))
	pcall(object.SetFont, object, path, size, EffectiveFlags(object, original.flags))
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

local function ApplyChatWindows(path, scale)
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. i]
		if frame and frame.GetFont then
			local original = Remember(frame)
			if original then
				-- Chat size is user configurable; keep Blizzard's size, only swap the face.
				local _, currentSize, flags = frame:GetFont()
				pcall(frame.SetFont, frame, path, currentSize or original.size, flags or original.flags)
			end
		end
	end
	if not chatHooked and type(FCF_SetChatWindowFontSize) == "function" then
		chatHooked = true
		hooksecurefunc("FCF_SetChatWindowFontSize", function(_, chatFrame, fontSize)
			if M.isEnabled and M.db.chat and chatFrame and chatFrame.GetFont then
				local _, size, flags = chatFrame:GetFont()
				pcall(chatFrame.SetFont, chatFrame, M.db.font, fontSize or size, flags)
			end
		end)
	end
end

local function RestoreChatWindows()
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. i]
		local original = frame and originals[frame]
		if original then
			local _, currentSize, flags = frame:GetFont()
			pcall(frame.SetFont, frame, original.path, currentSize or original.size, flags or original.flags)
		end
	end
end

local function ApplyAll()
	local db = M.db
	local path = db.font or DEFAULT_FONT
	local scale = tonumber(db.scale) or 1
	for _, entry in ipairs(DiscoverFontObjects()) do
		if ShouldTouch(entry.name) then
			ApplyToObject(entry.object, entry.name, path, scale)
		else
			RestoreObject(entry.object)
		end
	end
	if db.chat then
		ApplyChatWindows(path, scale)
	else
		RestoreChatWindows()
	end
	HookParchmentPanels()
	ApplyParchmentPanels()
end

local function RestoreAll()
	for _, entry in ipairs(DiscoverFontObjects()) do
		RestoreObject(entry.object)
	end
	RestoreChatWindows()
	RestoreParchmentStrings()
end

--------------------------------------------------------------------------------
-- World fonts (read by the client itself, so they must be set early)
--------------------------------------------------------------------------------

local WORLD_FONT_GLOBALS = {
	worldNames = { "UNIT_NAME_FONT", "NAMEPLATE_FONT" },
	worldDamage = { "DAMAGE_TEXT_FONT" },
}

local worldOriginals = {}

local function ApplyWorldFonts(db)
	for option, globals in pairs(WORLD_FONT_GLOBALS) do
		for _, name in ipairs(globals) do
			if worldOriginals[name] == nil and type(_G[name]) == "string" then
				worldOriginals[name] = _G[name]
			end
			if db[option] then
				_G[name] = db.font or DEFAULT_FONT
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
	ApplyWorldFonts(db)
	ApplyAll()
end

function M:OnDisable()
	RestoreAll()
	RestoreWorldFonts()
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	ApplyAll()
	if key == "font" or key == "worldNames" or key == "worldDamage" then
		ApplyWorldFonts(db)
		MelloUI:Print("World font changes take effect after /reload.")
	end
end

MelloUI:Profile("Fonts", "parchment panel walk", OnParchmentPanelUpdated)
