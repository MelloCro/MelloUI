--------------------------------------------------------------------------------
-- MelloUI - Config
--
-- The configuration window, opened from its own MelloUI button in the game
-- menu (Escape) or with /mello. Nothing is registered with the Blizzard
-- Settings panel, so there is no entry under Options > AddOns.
--
-- Layout (charcoal and muted bronze):
--   title band          "MelloUI", close button, drag handle
--   icon strip          Home, one icon per module, Profiles; the selected one
--                       is framed and named, the others name themselves on hover
--   page                header (icon, title, flavour, Enabled switch, Defaults)
--                       tabs built from the module's option headers
--                       a striped ledger of options: label left, control right
--   Home                a tile per module with its switch, plus What's new and Help
--
-- Module options are declared as a list, e.g.
--   options = {
--     { type = "header", name = "Components" },          -- becomes a tab
--     { type = "toggle", key = "unitframes", name = "Unit Frames", desc = "..." },
--     { type = "slider", key = "shade", name = "Brightness", min = 0, max = 1, step = 0.05, percent = true },
--     { type = "dropdown", key = "style", name = "Style", values = { {value="a", label="A"}, ... } },
--     { type = "button", name = "Click, light", hint = "checkboxes, tabs", text = "Play", onClick = function(module, db) ... end },
--   }
-- A module may set `icon` (texture path) and `flavour` (one line) in
-- RegisterModule; otherwise MODULE_META below supplies them.
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI

local TEXTURE_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Textures\\"
local LOGO = TEXTURE_PATH .. "LogoIcon.tga"   -- the emblem cropped from docs/logo.jpg
local ICON = "Interface\\Icons\\"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local ROCK = "Interface\\FrameGeneral\\UI-Background-Rock"
local SOUND_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Sounds\\"
local ICON_FRAME = "UI-HUD-ActionBar-IconFrame"        -- the action button bevel
local ICON_MASK = "UI-HUD-ActionBar-IconFrame-Mask"    -- its rounded corners

-- Soft clicks made by Tools\make_ui_sounds.py; falls back to the game's own
-- sounds if a file is missing.
local SOUNDS = {
	check_on  = { file = "check_on.ogg",  fallback = SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON },
	check_off = { file = "check_off.ogg", fallback = SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF },
	tab       = { file = "tab.ogg",       fallback = SOUNDKIT.IG_CHARACTER_INFO_TAB },
	page      = { file = "page.ogg",      fallback = SOUNDKIT.IG_MAINMENU_OPTION },
}
local function Click(kind)
	local sound = SOUNDS[kind]
	if not sound then
		return
	end
	-- the Custom Sounds module, when it is on, plays its own click instead
	if MelloUI.PlayCustomUISound and MelloUI:PlayCustomUISound(kind) then
		return
	end
	local ok, played = pcall(PlaySoundFile, SOUND_PATH .. sound.file, "SFX")
	if not (ok and played) and sound.fallback then
		PlaySound(sound.fallback)
	end
end

-- The same sounds for other modules: "page", "tab", "check_on", "check_off".
function MelloUI:PlayUISound(kind)
	Click(kind)
end

local WINDOW_WIDTH, WINDOW_HEIGHT = 1000, 760
local BAND_HEIGHT = 40
local STRIP_HEIGHT = 74
-- the icon strip on the kit (user, 2026-09-21): icons 1.5 x, packed with a
-- small gap and centred, the strip grown to hold them
local STRIP_ICON, STRIP_GAP, STRIP_HEIGHT_KIT = 66, 8, 118   -- the strip's icons at 1.15 x (user, 2026-09-22: 57 -> 66), the strip 10 taller for them
local PAD = 22
local ROW_HEIGHT = 34
local SLIDER_ROW_HEIGHT = 40

-- Palette
-- The configurator's colours, all from the palette (Core.lua, the user's
-- rule of 2026-09-23). Small reading text (hints, tooltips, flavour) is in
-- `text`, told apart from the labels by its size; muted text only marks what
-- is switched off (the palette's muted is 3.2:1, too faint for small text).
local PAL = MelloUI.Palette
local C = {
	bg      = PAL.mainWindow,
	band    = PAL.innerPanel,
	panel   = PAL.raisedPanel,
	stripe  = PAL.mainWindow,   -- on the sections' dark inner panel (user, 2026-09-24: "everything is just too brown")
	line    = PAL.border,
	hover   = PAL.hover,
	accent  = PAL.selectedTrim,
	accent2 = PAL.trim,
	text    = PAL.text,
	sub     = PAL.text,
	dim     = PAL.mutedText,
	on      = PAL.selectedTrim,
	off     = PAL.mutedText,
	knob    = PAL.text,
}

local MODULE_META = {
	UIModifications = { icon = ICON .. "INV_Misc_Gem_Ruby_02",      flavour = "The painted reskin, area by area, and the quality-of-life tweaks on nameplates, tooltips, chat and unit frames. Start here." },
	DarkMode     = { icon = ICON .. "Spell_Shadow_Twilight",       flavour = "Dim the gold and the glare. The interface steps back, the world steps forward." },
	CharacterPanel = { icon = ICON .. "INV_Chest_Plate04",         flavour = "Stone, iron and a window on the world. Your character, framed the way it deserves." },
	GameMenuPanel = { icon = ICON .. "INV_Misc_Key_10",             flavour = "Nine red plates under a gold header. The way out, in stone and iron." },
	SpellBookPanel = { icon = ICON .. "INV_Misc_Book_09",            flavour = "The spell book in the painted kit, on the game's own layout." },
	ProfessionsPanel = { icon = ICON .. "Trade_BlackSmithing",        flavour = "The professions window in the painted kit, on the game's own layout." },
	BarTextures  = { icon = ICON .. "Spell_Holy_Renew",            flavour = "Health and mana bars in the finish you like: flat, smooth, glossy or minimalist." },
	BarText      = { icon = ICON .. "INV_Misc_Note_02",            flavour = "Numbers where they belong. Health and power values, always in view." },
	Tweaks       = { icon = ICON .. "INV_Misc_Wrench_01",          flavour = "Small knobs with a big effect. Hide what you never click, scale what you never see." },
	Chat         = { icon = ICON .. "Ability_Warrior_BattleShout", flavour = "Less frame, more talk. Short channel tags and class colours keep the log readable." },
	Nameplates   = { icon = ICON .. "Ability_Hunter_SniperShot",   flavour = "Know who is stunned, who is your quest target, and who is about to be a problem." },
	Vendor       = { icon = ICON .. "INV_Misc_Coin_02",            flavour = "Sell the grey, mend the steel. Every merchant visit handled before the window opens." },
	Fonts        = { icon = ICON .. "INV_Scroll_03",               flavour = "One font for all of Azeroth. Pick it, scale it, outline it." },
	Tooltip      = { icon = ICON .. "INV_Misc_Book_09",            flavour = "Dark, flat and out of the way, with names in the colour of their class." },
	CooldownText = { icon = ICON .. "Spell_Nature_TimeStop",       flavour = "Countdowns on every cooldown, coloured by how long you still have to wait." },
	Stats        = { icon = ICON .. "Spell_Nature_Lightning",      flavour = "Frames per second and latency in the corner. Blame the server with confidence." },
	UnitFrames   = { icon = ICON .. "INV_Misc_GroupLooking",       flavour = "Player, target and focus, centred and calm. Frame art at the opacity you choose." },
	VoiceOver    = { icon = ICON .. "INV_Misc_Horn_01",            flavour = "Every quest giver speaks. Recorded voices with the pack, text-to-speech without it." },
	QuestList    = { icon = ICON .. "INV_Misc_Map_01",             flavour = "Every quest of the zone beside the map: who gives it, where, and what is left to do." },
	Auras = { icon = ICON .. "Spell_Holy_WordFortitude",           flavour = "Buffs and debuffs in rows of your own, drawn by the game itself, so they never go dark in a fight." },
	ErrorFilter = { icon = ICON .. "Spell_Holy_Silence",            flavour = "Quiet, please. The red shouts in the middle of the screen, a kind at a time." },
	QuestTracker = { icon = ICON .. "INV_Misc_Book_08",            flavour = "Every watched quest within reach: the tracker scrolls when the list runs long." },
	Route        = { icon = ICON .. "Ability_Tracking",            flavour = "A trail of gems from here to there, along the roads you have walked before." },
	Services     = { icon = ICON .. "Ability_Repair",              flavour = "Repair, mailbox, innkeeper, bank... the nearest one is a click under the minimap." },
	PartyMarkers = { icon = ICON .. "INV_Misc_GroupNeedMore",      flavour = "A class medallion over every party member's head, ringed in their role's colour: the healer, found at a glance." },
	CustomSounds = { icon = ICON .. "INV_Misc_Bell_01",            flavour = "Iron, leather, parchment and stone. Every click, page, pouch and buckle of the interface, re-recorded." },
	ClassIcons   = { icon = ICON .. "INV_Misc_Rune_01",            flavour = "Painted medallions for every class, on the character sheet and on every portrait." },
}
local HOME_FLAVOUR = "Module based interface tweaks for World of Warcraft: Forever."
local PROFILES_META = { icon = ICON .. "INV_Scroll_06", title = "Profiles",
	flavour = "Your whole setup under one name. Save it, load it, or make it the default for a fresh install." }
local DEFAULT_ICON = ICON .. "INV_Misc_QuestionMark"

-- Shown on the Home page under "What's new".
local CHANGELOG = {
	{ version = "0.13.7", lines = {
		"A simpler configurator: UI Modifications is switches and sliders on eight tabs (General, Windows, HUD, Combat, Unit Frames & Bars, Chat & Tooltips, Text, Dark Mode / Other); a feature's options sit under its switch and wake when it is on.",
		"Dynamic UI Modification is the one place for the look: borders, Kit Colours, every background and backdrop, the parchment sheets and the minimap's shape, picked on the interface with pictures.",
		"Buffs & Debuffs and Error Messages moved into UI Modifications' Combat tab, keeping whether they were on.",
		"Kit Colours: Warm iron (the default), Bronze or the original painted grey, for every frame, the game menu included. A colour palette for the whole interface, the configurator first.",
		"Borders, one choice per kind for every window: buttons, side tabs, progress bars, nameplates, round icons and auras. Thin rims on the action bars, bags, character slots, spells, professions and this window's icons.",
		"Window headers ride the frame's top rail and slip behind the round portrait ring; fewer red gems, red kept where it means something.",
		"Text on parchment is dark ink everywhere; quest difficulty shows as 1 to 5 diamonds beside the title.",
		"Fonts: eleven new families with italics, six Font Styles in one click, and a Chat text face for the chat and the whisper windows.",
		"Square minimap with a border of your choosing, merged with the Services bar in one frame.",
		"Route: a destination on another continent leads to the boat or zeppelin that leaves yours.",
		"Smooth scrolling here; quieter profession pictures; readable contacts lists; a Header Text Size for the Quest Tracker.",
	} },
	{ version = "0.13.6", lines = {
		"New modules, off until you switch them on: Quest Tracker (a scrolling tracker), Error Messages and Buffs & Debuffs.",
		"Route: World Marker and Light Beam over the destination, routes to a quest's objectives themselves, roads across zone borders, only flight points you know.",
		"Quests: the Classic or Forever logo on every quest, 5,882 quests, item and object starters with their own map icons, and filters by what a quest starts from.",
		"Whisper Popup Window, Windows Fade In, Reduce Motion, Preload Artwork, and parchment sheets as a choice.",
		"Profiles can be shared as a short string; Bar Textures gained By health colours and an Execute Range.",
		"Painted brush-stroke edges on the parchment and stone pages; combat fixes for the damage meter and moved windows.",
	} },
	{ version = "0.13.5", lines = {
		"A Discord for MelloUI: help, bug reports and every new release (the link is in the release notes).",
		"Unlock the Windows leaves the chat and the damage meter clickable, shows every drag area as a gold band and puts a plate on screen while unlocked.",
		"Settings changed in the first moments of a session are no longer lost; UI Modifications says when every area is off.",
	} },
	{ version = "0.13.4", lines = {
		"The painted kit reskin: every window and the whole HUD dressed in the painted art, one switch and one toggle per area under UI Modifications.",
		"Unlock the Windows: drag any window, the minimap, the tracker, the meter and the chat; the wheel scales; positions stay.",
		"A guided tour of this window (the Tutorial button, /mello tutorial), offered on the first login; a fresh install starts with everything off (the built-in Everything Off profile).",
		"Voice Over reads the right quest once the panel has settled, plays old recordings for renumbered quests, and lists the vanilla lines the pack never had.",
		"Bar Textures: the game's own textures as a choice and a health colour that overrides threat; Fonts: one font per role; Dark Mode darkens the reskin.",
		"Settings: a larger macro backup, window positions kept, profile names as typed; dozens of fixes from a full audit.",
		"Custom Sounds, a new module (off until you turn it on): the interface's clicks, pages, pouches, buckles, coins, whispers and the group finder bell re-recorded in iron, leather, parchment and stone.",
	} },
	{ version = "0.13.3", lines = {
		"Chat notices can be turned off under Tweaks; replies to slash commands always show.",
		"Report a problem link on this page; the addon list shows the MelloUI icon.",
		"Lighter minimap stand texture; the Quest List code is in three files.",
	} },
	{ version = "0.13", lines = {
		"Configuration window with its own button in the game menu.",
		"Bag slots dock under the bag window while the bag bar is hidden.",
		"Dungeon and raid doors are learned on the way in and on the way out.",
		"Services bar under the minimap: nearest repair, mailbox, innkeeper, bank and more.",
		"Route arrow, tracking notices and objective routing for the tracked quest.",
		"Profiles, with a bundled default applied on a fresh install.",
		"Voice Over: quest log read-aloud, paged subtitles, lock button on the overlay.",
	} },
}
local LINKS = {
	{ "GitHub", "https://github.com/MelloCro/MelloUI" },
	{ "Report a problem", "https://github.com/MelloCro/MelloUI/issues" },
	{ "CurseForge", "https://www.curseforge.com/wow/addons/melloui" },
	{ "Voice pack", "https://github.com/MelloCro/MelloUI/releases" },
}
local COMMANDS = {
	{ "/mello", "open or close this window" },
	{ "/mello <module>", "open a module's page" },
	{ "/mello list", "modules and their state" },
	{ "/mello enable <module>", "turn a module on" },
	{ "/mello disable <module>", "turn a module off" },
	{ "/mello profile ...", "save, load, delete or set the default profile" },
	{ "/mello status", "where the settings came from" },
	{ "/mello layout ...", "the Edit Mode layout the reskin is made for: apply, export" },
	{ "/mello tutorial", "the guided tour of this window" },
	{ "/vo", "Voice Over commands" },
	{ "/route", "route commands, /route clear to stop" },
	{ "/services", "track the nearest service" },
	{ "/qlmap", "quest map diagnostics and manual pins" },
}

local function Meta(module)
	local meta = MODULE_META[module.name] or {}
	return module.icon or meta.icon or DEFAULT_ICON, module.flavour or meta.flavour or module.desc or ""
end

local window
local pages = {}
local stripButtons = {}
local currentPage = nil

--------------------------------------------------------------------------------
-- Drawing helpers
--------------------------------------------------------------------------------

local function Colour(fs, c)
	fs:SetTextColor(c[1], c[2], c[3])
end

local function Text(parent, font, text, colour)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	if text then
		fs:SetText(text)
	end
	if colour then
		Colour(fs, colour)
	end
	return fs
end

local function Solid(parent, layer, c, alpha)
	local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
	tex:SetTexture(WHITE)
	tex:SetVertexColor(c[1], c[2], c[3], alpha or 1)
	return tex
end

local function Box(parent, bg, border, alpha)
	local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	f:SetBackdropColor(bg[1], bg[2], bg[3], alpha or 1)
	f:SetBackdropBorderColor(border[1], border[2], border[3], 1)
	return f
end

local function WrappedHeight(fs, fallback)
	local ok, h = pcall(fs.GetStringHeight, fs)
	if ok and type(h) == "number" and h > 0 then
		return h
	end
	return fallback or 14
end

local function Round(value, step)
	if not step or step <= 0 then
		return value
	end
	local n = math.floor(value / step + 0.5) * step
	local digits, s = 0, step
	while s < 1 and digits < 6 do
		s = s * 10
		digits = digits + 1
	end
	local mult = 10 ^ digits
	return math.floor(n * mult + 0.5) / mult
end

local function ModuleByName(name)
	if not name then
		return nil
	end
	local module = MelloUI.modules[name]
	if module then
		return module
	end
	local wanted = name:lower()
	for key, m in MelloUI:IterateModules() do
		if key:lower() == wanted or m.title:lower() == wanted then
			return m
		end
	end
	return nil
end

local function ShowTooltip(owner, title, body)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(title, C.accent[1], C.accent[2], C.accent[3])
	if body and body ~= "" then
		GameTooltip:AddLine(body, C.sub[1], C.sub[2], C.sub[3], true)
	end
	GameTooltip:Show()
end

-- A framed icon: the client's action button bevel around a rounded icon.
-- Grey at rest, gold when selected, white while hovered.
local FRAME_GREY = PAL.mutedText
local FRAME_GOLD = PAL.selectedTrim
--------------------------------------------------------------------------------
-- The painted kit on the configurator itself (user, 2026-09-21; picks CT2 SI1
-- from kit_raw/config_catalog.png): decided once, when the window is made,
-- from the UI Modifications reskin switch (a change there shows after
-- /reload). Every piece goes through Kit:Replace with the fixed looks' keys:
-- the outer double rail, the title plate on it, the page stone, the header
-- plate under the icon strip, R1 rims on the icons, TB6 tabs, L1 boxes
-- around the sections, plate rows with a hover, the kit's check boxes, red
-- buttons, D1 dropdowns, the kit slider, the kit's title face on the titles.
--------------------------------------------------------------------------------

local KIT = nil
local kitSkin = { reps = {}, followers = {} }

local function KitWanted()
	local kit = MelloUI.Kit
	if not (kit and kit.Replace) or not MelloUI:IsModuleEnabled("UIModifications") then
		return nil
	end
	local db = MelloUI:GetModuleDB("UIModifications")
	if db and db.reskin ~= false then
		return kit
	end
	return nil
end

local function KitReplace(region, opts)
	if not (KIT and region) then
		return nil
	end
	local rep = KIT:Replace(region, opts)
	if rep then
		kitSkin.reps[#kitSkin.reps + 1] = rep
		rep:Enable()
	end
	return rep
end

-- A region to hand to Kit:Replace where the configurator has none: an
-- invisible solid on the frame, faded by the replacement like game art.
local function KitAnchor(parent, layer)
	local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
	tex:SetAllPoints(parent)
	tex:SetColorTexture(0, 0, 0, 0)
	return tex
end

local RIM_GROW = 1.1   -- the kit rim's rect: the icon box grown about its centre

local function IconBox(parent, size, texture, button)
	local box = CreateFrame("Frame", nil, parent)
	box:SetSize(size, size)
	box.icon = box:CreateTexture(nil, "ARTWORK")
	if KIT then
		-- the icon at 0.9 of the box, centred, until the rim fits it into
		-- its opening (below)
		box.icon:SetPoint("CENTER", box, "CENTER")
		box.icon:SetSize(size * 0.9, size * 0.9)
	else
		box.icon:SetAllPoints()
	end
	box.icon:SetTexture(texture)
	if texture ~= LOGO then
		box.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
	end
	-- Same construction as an action button (45 px icon, 46 x 45 bevel on
	-- its top left corner, the corner mask at its native size centred on the
	-- icon), scaled to this size.
	local k = size / 45
	box.frame = box:CreateTexture(nil, "OVERLAY")
	box.frame:SetAtlas(ICON_FRAME)
	box.frame:SetSize(46 * k, 45 * k)
	box.frame:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
	local mask = box:CreateMaskTexture()
	mask:SetAtlas(ICON_MASK)
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(ICON_MASK)
	if info and info.width and info.height then
		local ik = KIT and k * 0.9 or k   -- the corner mask at the icon's size
		mask:SetSize(info.width * ik, info.height * ik)
		mask:SetPoint("CENTER", box.icon, "CENTER")
	else
		mask:SetAllPoints(box.icon)
	end
	if not KIT then
		box.icon:AddMaskTexture(mask)
	end
	if KIT then
		-- the rim every window's buttons wear (user, 2026-09-24: the icons
		-- follow the Dynamic UI Modification settings): UI Modifications'
		-- Button Border (thin iron, hairline, rounded, gold line, sunk),
		-- swapped live with it, in the Kit Colours look -- as regions of the
		-- BOX (the icon's own frame) so it draws over the icon; the hover is
		-- handed on from the strip button (SetHovered). The icon fills the
		-- rim's square opening (no rounded mask), as on the action bars; the
		-- rim's rect is the box grown by 10 % about its centre.
		local rimRect = CreateFrame("Frame", nil, box)
		rimRect:SetPoint("CENTER", box, "CENTER")
		rimRect:SetSize(size * RIM_GROW, size * RIM_GROW)
		rimRect:EnableMouse(false)
		-- the rim shows the box's states: gold (checked) for the current
		-- page, pressed while the strip button is held, hover from the
		-- button (user, 2026-09-22: no feedback on the strip but the text)
		local rep = KitReplace(box.frame, { as = KIT:ButtonRimRule(), rect = rimRect, button = box, icon = box.icon,
			checked = function() return box.selected end })
		box.rim = rep and rep.object or nil
		if rep then
			box.melloRep = rep
			KIT:RegisterButtonRim(box)
		end
	end
	box.selected = false
	function box:SetSelected(selected)
		self.selected = selected and true or false
		local c = self.selected and FRAME_GOLD or FRAME_GREY
		self.frame:SetVertexColor(c[1], c[2], c[3], 1)
		if self.rim and self.rim.Update then
			self.rim:Update()
		end
	end
	function box:SetPressed(pressed)
		if self.rim and self.rim.Update then
			self.rim.pressed = pressed and true or nil
			self.rim:Update()
		end
	end
	function box:SetHovered(hovered)
		if hovered then
			self.frame:SetVertexColor(1, 1, 1, 1)
		else
			self:SetSelected(self.selected)
		end
		if self.rim and self.rim.Update then
			self.rim.hover = hovered and true or nil
			self.rim:Update()
		end
	end
	function box:SetOn(on)
		self.icon:SetDesaturated(not on)
		self.icon:SetAlpha(on and 1 or 0.45)
	end
	-- a pulsing gold glow over the rim (the action button's proc glow,
	-- additive light on top of the iron, not behind it — user, 2026-09-22),
	-- for an important module
	function box:SetGlow(on)
		if on and not self.glow then
			local glow = self:CreateTexture(nil, "OVERLAY", nil, 7)
			glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
			glow:SetBlendMode("ADD")
			glow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
			-- centred on the BOX (the rim's centre; the icon sits inset in it)
			-- and sized from the rim, so the light is symmetric around the
			-- iron (user, 2026-09-22: the glow placed correctly)
			local rimSize = KIT and size * RIM_GROW or size
			glow:SetSize(rimSize * 1.45, rimSize * 1.45)
			glow:SetPoint("CENTER", self, "CENTER", 0, 0)
			local anim = glow:CreateAnimationGroup()
			anim:SetLooping("BOUNCE")
			local a = anim:CreateAnimation("Alpha")
			a:SetFromAlpha(0.45)
			a:SetToAlpha(1)
			a:SetDuration(0.9)
			anim:Play()
			self.glow, self.glowAnim = glow, anim
		elseif self.glow then
			self.glow:SetShown(on and true or false)
			if on then
				self.glowAnim:Play()
			else
				self.glowAnim:Stop()
			end
		end
	end
	box:SetSelected(false)
	return box
end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

-- On/off control: the standard WoW checkbox. SetValue(on, silent) sets it
-- without (silent) or with the change callback.
local function CreateSwitch(parent, onChange)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(26, 26)
	if cb.Text then
		cb.Text:Hide()
	end
	cb.value = false
	function cb:SetValue(on, silent)
		self.value = on and true or false
		self:SetChecked(self.value)
		if not silent and onChange then
			onChange(self.value)
		end
	end
	cb:SetScript("OnClick", function(self)
		local value = self:GetChecked() and true or false
		Click(value and "check_on" or "check_off")
		self:SetValue(value)
	end)
	if KIT and KIT.SkinCheckButton then
		KIT:SkinCheckButton(cb, KitReplace, "UI-CheckBox-Up")
	end
	return cb
end

-- Smooth hover glow: a bronze wash that fades in while the mouse is over the
-- frame and out again after it leaves. Runs an OnUpdate only while animating.
local HOVER_SPEED = 6   -- full fade in about 1/6 s
local function AttachHover(frame, alphaMax)
	-- the palette's hover is a fill colour (dark bronze), not a light: it
	-- shows at about half strength where the old gold wash showed at a tenth
	alphaMax = (alphaMax or 0.10) * 5
	local glow = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	glow:SetTexture(WHITE)
	glow:SetAllPoints()
	glow:SetVertexColor(C.hover[1], C.hover[2], C.hover[3], 1)
	glow:SetAlpha(0)
	local edge = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
	edge:SetTexture(WHITE)
	edge:SetWidth(2)
	edge:SetPoint("TOPLEFT")
	edge:SetPoint("BOTTOMLEFT")
	edge:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
	edge:SetAlpha(0)
	local level = 0
	local function Step(self, dt)
		local target = self:IsMouseOver() and 1 or 0
		if level < target then
			level = math.min(1, level + dt * HOVER_SPEED)
		elseif level > target then
			level = math.max(0, level - dt * HOVER_SPEED)
		end
		glow:SetAlpha(level * alphaMax)
		edge:SetAlpha(level)
		if level == 0 then
			self:SetScript("OnUpdate", nil)
		end
	end
	frame:HookScript("OnEnter", function(self)
		self:SetScript("OnUpdate", Step)
	end)
	frame.hoverGlow = glow
end

local function CreateDropdown(parent, width, db, module, opt)
	local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dd:SetWidth(width)
	dd:SetHeight(25)
	-- Settings panel look: the text holder alone, gold text in the middle.
	if dd.Arrow then
		dd.Arrow:Hide()
	end
	if dd.Text then
		dd.Text:ClearAllPoints()
		dd.Text:SetPoint("LEFT", 10, -1)
		dd.Text:SetPoint("RIGHT", -10, -1)
		dd.Text:SetJustifyH("CENTER")
		local function Gold()
			Colour(dd.Text, C.accent)
		end
		Gold()
		if dd.OnButtonStateChanged then
			hooksecurefunc(dd, "OnButtonStateChanged", Gold)
		end
		dd:HookScript("OnEnter", function() Colour(dd.Text, C.text) end)
		dd:HookScript("OnLeave", Gold)
	end
	if dd.SetDefaultText then
		dd:SetDefaultText(opt.name)
	end
	dd:SetupMenu(function(_, root)
		for _, entry in ipairs(opt.values or {}) do
			local radio = root:CreateRadio(entry.label or tostring(entry.value),
				function() return db[opt.key] == entry.value end,
				function() MelloUI:NotifySettingChanged(module.name, opt.key, entry.value) end,
				entry.value)
			if entry.tooltip and radio and radio.SetTooltip then
				pcall(radio.SetTooltip, radio, function(tooltip)
					GameTooltip_SetTitle(tooltip, entry.label or tostring(entry.value))
					GameTooltip_AddNormalLine(tooltip, entry.tooltip)
				end)
			end
		end
	end)
	function dd:Refresh()
		if self.GenerateMenu then
			pcall(self.GenerateMenu, self)
		end
	end
	return dd
end

local function SliderFormatter(opt)
	if opt.format then
		return opt.format
	elseif opt.percent then
		return function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end
	end
	return function(v)
		if math.abs(v - math.floor(v + 0.5)) < 0.001 then
			return tostring(math.floor(v + 0.5))
		end
		return string.format("%.2f", v)
	end
end

local function CreateSlider(parent, width, db, module, opt)
	local min, max, step = opt.min or 0, opt.max or 1, opt.step or 0.05
	local steps = math.max(1, math.floor((max - min) / step + 0.5))
	local slider = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
	slider:SetWidth(width)
	slider:Init(db[opt.key] or min, min, max, steps, { [MinimalSliderWithSteppersMixin.Label.Right] = SliderFormatter(opt) })
	if slider.Slider and slider.Slider.SetObeyStepOnDrag then
		slider.Slider:SetObeyStepOnDrag(true)
	end
	if slider.RightText then
		slider.RightText:SetTextColor(C.text[1], C.text[2], C.text[3])
	end
	slider.refreshing = false
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		if slider.refreshing then
			return
		end
		value = Round(value, step)
		if db[opt.key] ~= value then
			MelloUI:NotifySettingChanged(module.name, opt.key, value)
		end
	end, slider)
	function slider:Refresh()
		self.refreshing = true
		self:SetValue(db[opt.key] or min)
		self.refreshing = false
	end
	if KIT and slider.Slider then
		local track = slider.Slider
		if track.Middle then
			-- SL1: the track at the kit piece's own thickness (fitted to the
			-- slider frame it came out as two fat stripes — user, 2026-09-21)
			local layout = MelloUI_KitLayout and MelloUI_KitLayout.pieces and MelloUI_KitLayout.pieces["inputs/slider_mid"]
			local natural = layout and layout.box and (layout.box[4] - layout.box[2]) * KIT.scale or nil
			KitReplace(track.Middle, { as = "_Minimal_SliderBar_Middle", rect = track, fitHeight = natural, alsoFade = { track.Left, track.Right } })
		end
		if track.Thumb then
			KitReplace(track.Thumb, { as = "Minimal_SliderBar_Button", rect = track.Thumb, button = track })
		end
		for _, entry in ipairs({ { slider.Back, "Minimal_SliderBar_Button_Left" }, { slider.Forward, "Minimal_SliderBar_Button_Right" } }) do
			local b, key = entry[1], entry[2]
			if b and b.GetNormalTexture and b:GetNormalTexture() then
				KitReplace(b:GetNormalTexture(), { as = key, button = b, alsoFade = KIT:OtherTextures(b, b:GetNormalTexture()) })
			end
		end
	end
	return slider
end

--------------------------------------------------------------------------------
-- Sections and rows
--
-- A page owns sections; a section is a frame holding rows. Sections map to
-- tabs when there is more than one.
--------------------------------------------------------------------------------

local RefreshStrip, SelectPage  -- forward declarations

local SEC_INSET = 10   -- the rows' margin inside a section's L1 box (kit)
local INDENT = 22      -- a sub-option's label, per level, right of its parent's

local function NewSection(page, name)
	local sec = CreateFrame("Frame", nil, page)
	sec.name = name
	sec.y = KIT and SEC_INSET or 0
	sec.rows = 0
	sec.refreshers = {}
	sec:SetWidth(page.width - PAD * 2)
	sec:SetHeight(10)
	sec:Hide()
	if KIT then
		-- L1: the single rail with the list-box stone around the section
		KitReplace(KitAnchor(sec), { as = "Professions-background-summarylist", rect = sec, parent = sec, level = -1 })
		-- depth (user, 2026-09-24: "everything is just too brown ... add the
		-- checkbox section a darker tone from our color palette"): the L1
		-- box lays the palette's inner panel over its stone itself (its
		-- rule's `dim`, WINDOW-RULES 2e), the rows on that darker ground
	end
	function sec:Refresh()
		for _, fn in ipairs(self.refreshers) do
			fn()
		end
	end
	function sec:Finish()
		self:SetHeight(math.max(self.y + (KIT and SEC_INSET or 0), 10))
	end
	page.sections[#page.sections + 1] = sec
	return sec
end

-- A ledger row: stripe, label, optional grey hint, tooltip with the description.
local function Row(sec, height, label, hint, desc)
	local row = CreateFrame("Frame", nil, sec)
	row:SetHeight(height)
	row:SetPoint("TOPLEFT", KIT and SEC_INSET or 0, -sec.y)
	row:SetPoint("RIGHT", sec, "RIGHT", KIT and -SEC_INSET or 0, 0)
	row:EnableMouse(true)
	if KIT then
		-- CR4 (user, 2026-09-21): a faint band on every other row, the
		-- plate's hover look on the row under the mouse only
		if sec.rows % 2 == 0 then
			row.band = row:CreateTexture(nil, "BACKGROUND")
			row.band:SetAllPoints(row)
			row.band:SetColorTexture(C.stripe[1], C.stripe[2], C.stripe[3], 0.85)
		end
		local hover = KitReplace(KitAnchor(row), { as = "FriendsRowHighlight", rect = row })
		if hover and hover.object then
			row.hover = hover.object
			hover.object:Hide()
			row:HookScript("OnEnter", function() if row.hover then hover.object:Show() end end)
			row:HookScript("OnLeave", function() hover.object:Hide() end)
		end
	else
		local line = Solid(row, "BORDER", C.line, 0.6)
		line:SetHeight(1)
		line:SetPoint("BOTTOMLEFT")
		line:SetPoint("BOTTOMRIGHT")
		AttachHover(row)
	end
	row.label = Text(row, "GameFontHighlight", label, C.text)
	row.label:SetPoint("LEFT", 14 + (sec.indent or 0) * INDENT, 0)
	row.label:SetWordWrap(false)
	if hint and hint ~= "" then
		row.hint = Text(row, "GameFontHighlightSmall", hint, C.sub)
		row.hint:SetPoint("LEFT", row.label, "RIGHT", 10, 0)
		row.hint:SetWordWrap(false)
	end
	if desc and desc ~= "" then
		row:HookScript("OnEnter", function(self) ShowTooltip(self, label, desc) end)
		row:HookScript("OnLeave", function() GameTooltip:Hide() end)
	end
	sec.y = sec.y + height
	sec.rows = sec.rows + 1
	return row
end

local function AddToggle(sec, module, db, opt)
	local row = Row(sec, ROW_HEIGHT, opt.name, opt.important and "IMPORTANT" or opt.hint, opt.desc)
	if opt.important then
		Colour(row.label, { 1, 0.82, 0 })
		if row.hint then
			Colour(row.hint, { 1, 0.82, 0 })
		end
	end
	local switch = CreateSwitch(row, function(value)
		MelloUI:NotifySettingChanged(module.name, opt.key, value)
		-- the rows that hang on this switch wake or grey at once
		sec:Refresh()
	end)
	switch:SetPoint("RIGHT", -12, 0)
	switch:HookScript("OnEnter", function() if opt.desc then ShowTooltip(row, opt.name, opt.desc) end end)
	switch:HookScript("OnLeave", function() GameTooltip:Hide() end)
	sec.refreshers[#sec.refreshers + 1] = function()
		switch:SetValue(db[opt.key] and true or false, true)
	end
	return row
end

local function AddSlider(sec, module, db, opt)
	local row = Row(sec, SLIDER_ROW_HEIGHT, opt.name, opt.hint, opt.desc)
	local slider = CreateSlider(row, 200, db, module, opt)
	slider:SetPoint("RIGHT", -70, 0)
	sec.refreshers[#sec.refreshers + 1] = function() slider:Refresh() end
	return row
end

local function AddDropdown(sec, module, db, opt)
	local row = Row(sec, ROW_HEIGHT, opt.name, opt.hint, opt.desc)
	local dd = CreateDropdown(row, 200, db, module, opt)
	dd:SetPoint("RIGHT", -14, 0)
	sec.refreshers[#sec.refreshers + 1] = function() dd:Refresh() end
	return row
end

-- A row that only means something while a switch is on (user, 2026-09-24:
-- "people will get overwhelmed by all the options"): `gate()` returns
-- whether it is live and, when not, the switch to turn on. Off, the row is
-- dimmed and a cover over it takes the clicks and says which switch wakes it.
local function AddGate(sec, row, gate)
	local cover = CreateFrame("Frame", nil, row)
	cover:SetAllPoints(row)
	cover:SetFrameLevel(row:GetFrameLevel() + 30)
	cover:EnableMouse(true)
	cover:SetScript("OnEnter", function(self)
		local _, why = gate()
		ShowTooltip(self, row.label and row.label:GetText() or "", why and ("Switch on \"" .. why .. "\" first.") or nil)
	end)
	cover:SetScript("OnLeave", function() GameTooltip:Hide() end)
	cover:Hide()
	sec.refreshers[#sec.refreshers + 1] = function()
		local live = gate()
		row:SetAlpha(live and 1 or 0.4)
		cover:SetShown(not live)
	end
end

-- A row with a button on the right (user, 2026-09-22: "a preview button on
-- each sound effect"): the label, a grey hint, and the kit's red plate
-- button with `opt.text`; `opt.onClick(module, db)` on the click.
local function AddButton(sec, module, db, opt)
	local row = Row(sec, ROW_HEIGHT, opt.name, opt.hint, opt.desc)
	local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	button:SetSize(opt.width or 70, 22)
	button:SetPoint("RIGHT", -12, 0)
	button:SetText(opt.text or "Run")
	button:SetScript("OnClick", function()
		if opt.onClick then
			opt.onClick(module, db)
		end
	end)
	button:HookScript("OnEnter", function() if opt.desc then ShowTooltip(row, opt.name, opt.desc) end end)
	button:HookScript("OnLeave", function() GameTooltip:Hide() end)
	row.button = button
	return row
end

-- A heading inside a tab (a `header` opens a new tab; the reskin's
-- "Windows" / "HUD" groups and a folded module's own headers stay inside
-- their area's tab — user, 2026-09-21)
local function AddSubheader(sec, module, db, opt)
	local row = Row(sec, ROW_HEIGHT - 6, opt.name, nil, nil)
	Colour(row.label, C.accent)
	if KIT then
		-- SH3 (user, 2026-09-21): the header plate, the text past its gem cap
		-- (no band, no hover plate on a heading)
		row:EnableMouse(false)
		if row.band then
			row.band:Hide()
		end
		row.hover = nil
		KitReplace(KitAnchor(row), { as = "GuildFrame-Header", rect = row })
		row.label:SetPoint("LEFT", 34, 0)
		return
	end
	row.label:SetPoint("LEFT", 8, -4)
	local line = Solid(row, "ARTWORK", C.line, 1)
	line:SetPoint("BOTTOMLEFT", 8, 0)
	line:SetPoint("BOTTOMRIGHT", -8, 0)
end

local builders = {
	toggle = AddToggle,
	slider = AddSlider,
	dropdown = AddDropdown,
	subheader = AddSubheader,
	button = AddButton,
}

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------

local function NewPage(name, width)
	local page = CreateFrame("Frame", nil, window.scroll)
	page.name = name
	page.width = width
	page.sections = {}
	page.refreshers = {}
	page.headerHeight = 0
	page.current = nil
	page:SetSize(width, 10)

	function page:Refresh()
		for _, fn in ipairs(self.refreshers) do
			fn()
		end
		if self.current then
			self.current:Refresh()
		end
	end

	function page:Select(sec)
		for _, other in ipairs(self.sections) do
			other:SetShown(other == sec)
		end
		self.current = sec
		for _, tab in ipairs(self.tabs or {}) do
			tab:SetSelected(tab.section == sec)
		end
		sec:Refresh()
		self:SetHeight(self.headerHeight + sec:GetHeight() + PAD)
	end

	-- Lay out the tab row (if more than one section) and anchor the sections.
	function page:Finish()
		local y = self.headerHeight
		if self.headerShade then
			-- the header's panel down to just above the tabs / the first section
			self.headerShade:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", -(PAD - 10), -(y - 8))
		end
		if #self.sections > 1 then
			self.tabs = {}
			local x, rowY = 0, y
			local artHeight = 24
			for _, sec in ipairs(self.sections) do
				local tab = CreateFrame("Button", nil, self, "PanelTopTabButtonTemplate")
				tab:SetText(sec.name)
				PanelTemplates_TabResize(tab, 8)
				if tab.MiddleActive then
					artHeight = math.floor(tab.MiddleActive:GetHeight() + 0.5)
				end
				local w = tab:GetWidth()
				if x + w > self.width - PAD * 2 and x > 0 then
					x = 0
					rowY = rowY + artHeight + 2
				end
				tab:SetPoint("TOPLEFT", PAD + x, -rowY)
				tab.section = sec
				if KIT and KIT.SkinPanelTab then
					KIT:SkinPanelTab(tab, KitReplace, kitSkin)
				end
				function tab:SetSelected(selected)
					if selected then
						PanelTemplates_SelectTab(self)
					else
						PanelTemplates_DeselectTab(self)
					end
				end
				tab:SetScript("OnClick", function(self)
					Click("tab")
					page:Select(self.section)
				end)
				self.tabs[#self.tabs + 1] = tab
				x = x + w - 6
			end
			y = rowY + artHeight - 1
			if not KIT then
				local line = Solid(self, "ARTWORK", C.accent2, 1)
				line:SetHeight(1)
				line:SetPoint("TOPLEFT", PAD, -y)
				line:SetPoint("RIGHT", self, "RIGHT", -PAD, 0)
			end
			y = y + 12
		end
		self.headerHeight = y
		for _, sec in ipairs(self.sections) do
			sec:ClearAllPoints()
			sec:SetPoint("TOPLEFT", PAD, -y)
			sec:SetWidth(self.width - PAD * 2)
			sec:Finish()
		end
		self:Select(self.sections[1])
	end
	return page
end

-- Page header: framed icon, title, flavour line and, for modules, the Enabled
-- switch and the Defaults button.
local function BuildPageHeader(page, icon, title, flavour, module)
	local box = IconBox(page, 50, icon)
	box:SetPoint("TOPLEFT", PAD, -PAD)

	local titleFS = Text(page, "GameFontNormalHuge", title, C.accent)
	titleFS:SetPoint("TOPLEFT", box, "TOPRIGHT", 14, 0)
	if KIT and KIT.TitleFont then
		KIT:TitleFont(titleFS, true)
	end

	local rightWidth = module and 200 or 0
	local flavourFS = Text(page, "GameFontHighlightSmall", nil, C.sub)
	if KIT then
		-- on the page stone the dim grey drowned (user, 2026-09-21): light
		-- text with a thin outline
		flavourFS:SetFontObject("GameFontHighlightSmallOutline")
		Colour(flavourFS, C.text)
	end
	flavourFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 2, -6)
	flavourFS:SetWidth(page.width - PAD * 2 - 64 - rightWidth)
	flavourFS:SetWordWrap(true)
	flavourFS:SetText(flavour)
	page.flavour = flavourFS
	if KIT then
		-- the header on the palette's inner panel (user, 2026-09-24: "apply
		-- the eye strain rule to all existing windows"; WINDOW-RULES 2e): the
		-- title, the flavour, the status line AND the switches' labels on the
		-- right ("Enabled", "Unlock the Windows") lay on the plain brown --
		-- the black backing that faded out to the right (2026-09-22) left the
		-- right-hand labels on the stone. A page region under everything
		-- else, across the header's whole width; its bottom follows the
		-- header's final height (page:Finish)
		local shade = page:CreateTexture(nil, "BACKGROUND", nil, 1)
		shade:SetColorTexture(C.band[1], C.band[2], C.band[3], 0.8)
		shade:SetPoint("TOPLEFT", page, "TOPLEFT", PAD - 10, -(PAD - 10))
		page.headerShade = shade
	end

	if module then
		local lbl = Text(page, "GameFontNormal", "Enabled", C.text)
		local switch = CreateSwitch(page, function(value)
			MelloUI:SetModuleEnabled(module.name, value)
			MelloUI:RefreshConfig()
		end)
		switch:SetPoint("TOPRIGHT", page, "TOPRIGHT", -PAD, -PAD)
		lbl:SetPoint("RIGHT", switch, "LEFT", -4, 0)
		page.switch = switch
		local defaults = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
		defaults:SetSize(90, 22)
		defaults:SetPoint("TOPRIGHT", switch, "BOTTOMRIGHT", 0, -10)
		defaults:SetText("Defaults")
		defaults:SetScript("OnClick", function()
			for key, value in pairs(module.defaults) do
				if type(value) == "table" then
					-- a copy: the live table must not BE the defaults table
					-- (the window positions were written into it)
					local copy = {}
					for k, v in pairs(value) do
						copy[k] = v
					end
					value = copy
				end
				MelloUI:NotifySettingChanged(module.name, key, value)
			end
			MelloUI:Print("%s: settings back to their defaults.", module.title)
			MelloUI:RefreshConfig()
		end)
		defaults:SetScript("OnEnter", function(self) ShowTooltip(self, "Defaults", "Put every option of this module back to its default value. The module stays on or off as it is.") end)
		defaults:SetScript("OnLeave", function() GameTooltip:Hide() end)
		page.refreshers[#page.refreshers + 1] = function()
			switch:SetValue(MelloUI:IsModuleEnabled(module.name), true)
		end
		-- `module.headerToggle`: one of the module's toggles shown up here
		-- under Defaults (UI Modifications' "Unlock the Windows")
		local ht = module.headerToggle
		if ht and ht.key then
			local hlbl = Text(page, "GameFontNormal", ht.name or ht.key, C.text)
			local hswitch = CreateSwitch(page, function(value)
				MelloUI:NotifySettingChanged(module.name, ht.key, value)
				MelloUI:RefreshConfig()
			end)
			hswitch:SetPoint("TOPRIGHT", defaults, "BOTTOMRIGHT", 0, -10)
			hlbl:SetPoint("RIGHT", hswitch, "LEFT", -4, 0)
			page.headerSwitch = hswitch
			if ht.desc then
				hswitch:HookScript("OnEnter", function() ShowTooltip(hswitch, ht.name or ht.key, ht.desc) end)
				hswitch:HookScript("OnLeave", function() GameTooltip:Hide() end)
			end
			page.refreshers[#page.refreshers + 1] = function()
				local db = MelloUI:GetModuleDB(module.name)
				hswitch:SetValue(db[ht.key] and true or false, true)
			end
			-- `module.headerButton`: a button under that switch
			-- (UI Modifications' "Reset positions")
			local hb = module.headerButton
			if hb and hb.onClick then
				local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
				button:SetSize(110, 22)
				button:SetPoint("TOPRIGHT", hswitch, "BOTTOMRIGHT", 0, -10)
				button:SetText(hb.name or "Reset")
				page.headerButton = button
				button:SetScript("OnClick", function()
					hb.onClick()
					MelloUI:RefreshConfig()
				end)
				if hb.desc then
					button:SetScript("OnEnter", function(self) ShowTooltip(self, hb.name or "Reset", hb.desc) end)
					button:SetScript("OnLeave", function() GameTooltip:Hide() end)
				end
			end
		end
	end

	page.headerHeight = PAD + math.max(50, 26 + 6 + WrappedHeight(flavourFS, 14)) + 18
		+ (module and module.headerToggle and 30 or 0) + (module and module.headerButton and 32 or 0)
end

local function BuildModulePage(module, width)
	local page = NewPage(module.name, width)
	local icon, flavour = Meta(module)
	BuildPageHeader(page, icon, module.title, flavour, module)
	local db = MelloUI:GetModuleDB(module.name)
	local sec = nil
	-- an option's row by its key, in a module's options
	local function OptionOf(owner, key)
		for _, o in ipairs(owner.options) do
			if o.key == key then
				return o
			end
		end
		return nil
	end
	-- how deep an option hangs under its parents (`opt.parent`, a switch of
	-- the same module): one indent per level
	local function Depth(owner, opt)
		local depth, seen = 0, {}
		local p = opt.parent and OptionOf(owner, opt.parent)
		while p and not seen[p] and depth < 4 do
			seen[p] = true
			depth = depth + 1
			p = p.parent and OptionOf(owner, p.parent)
		end
		return depth
	end
	-- the switches a row hangs on, as one gate: `opt.parent` (indented under
	-- it) and `opt.requires` (not indented), keys of the same module's
	-- settings, and `area`: { db, key, name } of the tab's area switch
	local function GateOf(owner, ownerDb, opt, area)
		local needs = {}
		for _, key in ipairs({ opt.parent, opt.requires }) do
			if key then
				local o = OptionOf(owner, key)
				needs[#needs + 1] = { db = ownerDb, key = key, name = o and o.name or key }
			end
		end
		if area then
			table.insert(needs, 1, area)
		end
		if #needs == 0 then
			return nil
		end
		return function()
			for _, n in ipairs(needs) do
				if not n.db[n.key] then
					return false, n.name
				end
			end
			return true
		end
	end
	-- an option may belong to ANOTHER module (`opt.module`), built against
	-- that module and its settings; `include` lays out another module's
	-- options in place (all of them, its headers as subheaders, or only
	-- `keys`, in their order, with inline rows between), under the tab's
	-- area switch (`area`, a key of this page's module: the rows indented
	-- one step and live only while it is on)
	local function Build(owner, ownerDb, opt, area)
		if not sec then
			sec = NewSection(page, "General")
		end
		local builder = builders[opt.type]
		if builder then
			if opt.key and ownerDb[opt.key] == nil then
				ownerDb[opt.key] = owner.defaults[opt.key]
			end
			sec.indent = opt.type ~= "subheader" and ((area and 1 or 0) + Depth(owner, opt)) or 0
			local row = builder(sec, owner, ownerDb, opt)
			sec.indent = 0
			local gate = row and opt.type ~= "subheader" and GateOf(owner, ownerDb, opt, area)
			if gate then
				AddGate(sec, row, gate)
			end
		else
			MelloUI:Print("Unknown option type '%s' in module %s", tostring(opt.type), owner.name)
		end
	end
	for _, opt in ipairs(module.options) do
		if opt.type == "header" then
			sec = NewSection(page, opt.name)
		elseif opt.type == "include" then
			local inc = MelloUI:GetModule(opt.module)
			if inc then
				local incDb = MelloUI:GetModuleDB(inc.name)
				local area = nil
				if opt.area then
					local o = OptionOf(module, opt.area)
					area = { db = db, key = opt.area, name = o and o.name or opt.area }
				end
				if opt.keys then
					for _, entry in ipairs(opt.keys) do
						local sub = type(entry) == "table" and entry or OptionOf(inc, entry)
						if sub then
							Build(inc, incDb, sub, sub.type ~= "subheader" and area or nil)
						end
					end
				else
					for _, sub in ipairs(inc.options) do
						if sub.type == "header" then
							if not opt.flat then
								Build(inc, incDb, { type = "subheader", name = sub.name })
							end
						else
							Build(inc, incDb, sub, area)
						end
					end
				end
			end
		elseif opt.module then
			local owner = MelloUI:GetModule(opt.module)
			if owner then
				Build(owner, MelloUI:GetModuleDB(owner.name), opt)
			end
		else
			Build(module, db, opt)
		end
	end
	if #page.sections == 0 then
		sec = NewSection(page, "Options")
		local fs = Text(sec, "GameFontDisable", "This module has no options. The switch above is all there is to it.")
		fs:SetPoint("TOPLEFT", 14, -8)
		sec.y = 30
	end
	page:Finish()
	if KIT and KIT.SweepControls then
		KIT:SweepControls(page, KitReplace, kitSkin)
	end
	return page
end

--------------------------------------------------------------------------------
-- Home page: tiles, what's new, help
--------------------------------------------------------------------------------

local function VoicePackInstalled()
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		for _, name in ipairs({ "MelloUI_VoiceOverData", "AI_VoiceOverData_Forever", "AI_VoiceOverData_Vanilla" }) do
			local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
			if ok and loaded then
				return true
			end
		end
	end
	return false
end

local function StatusLine()
	local on, total = 0, 0
	for name, module in MelloUI:IterateModules() do
		if not module.hidden then
			total = total + 1
			if MelloUI:IsModuleEnabled(name) then
				on = on + 1
			end
		end
	end
	local profile = MelloUI.db and MelloUI.db.activeProfile or nil
	return string.format("Version %s   -   %d of %d modules on   -   %s   -   voice pack %s",
		tostring(MelloUI.version), on, total,
		profile and ("profile " .. profile) or "no profile loaded",
		VoicePackInstalled() and "installed" or "not installed")
end

local function BuildHomePage(width)
	local page = NewPage("Home", width)
	BuildPageHeader(page, LOGO, "MelloUI", HOME_FLAVOUR, nil)
	local status = Text(page, "GameFontHighlightSmall", nil, C.sub)
	if KIT then
		status:SetFontObject("GameFontHighlightSmallOutline")
		Colour(status, C.text)
	end
	status:SetPoint("TOPLEFT", page.flavour, "BOTTOMLEFT", 0, -4)
	page.refreshers[#page.refreshers + 1] = function() status:SetText(StatusLine()) end
	page.headerHeight = page.headerHeight + 16

	-- the guided tour (Core/Tutorial.lua), where a module page has its switch
	local tour = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	tour:SetSize(110, 22)
	tour:SetPoint("TOPRIGHT", page, "TOPRIGHT", -PAD, -PAD)
	tour:SetText("Tutorial")
	tour:SetScript("OnClick", function()
		Click("page")
		if MelloUI.Tutorial then
			MelloUI.Tutorial:Start()
		end
	end)
	tour:SetScript("OnEnter", function(self) ShowTooltip(self, "Tutorial", "A short tour of this window: where every feature lives, step by step, on the game's help tips. Also /mello tutorial.") end)
	tour:SetScript("OnLeave", function() GameTooltip:Hide() end)
	page.tutorialButton = tour

	-- Modules: a tile per module.
	local tiles = NewSection(page, "Modules")
	page.tiles = {}
	local columns, gap = 4, 10
	local tileWidth = (tiles:GetWidth() - gap * (columns - 1)) / columns
	local tileHeight = 92
	local i = 0
	for _, module in MelloUI:IterateModules() do
		if not module.hidden then
		local col, row = i % columns, math.floor(i / columns)
		local tile = CreateFrame("Frame", nil, tiles, "BackdropTemplate")
		if KIT then
			-- CT2: the L1 box (single rail + list-box stone)
			-- (one level under the tile, so its own texts stay above the stone)
			KitReplace(KitAnchor(tile), { as = "Professions-background-summarylist", rect = tile, parent = tile, level = -1 })
		else
			tile:SetBackdrop({
				bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 },
			})
			tile:SetBackdropColor(C.band[1], C.band[2], C.band[3], 0.92)
		end
		-- an important module (the painted interface's one entry) keeps the
		-- gold border at rest and wears a badge, so it stands out among the
		-- tiles (user, 2026-09-21)
		local restR, restG, restB = C.accent2[1], C.accent2[2], C.accent2[3]
		if module.important then
			restR, restG, restB = C.accent[1], C.accent[2], C.accent[3]
		end
		if not KIT then
			tile:SetBackdropBorderColor(restR, restG, restB, 1)
		end
		tile:SetSize(tileWidth, tileHeight)
		tile:SetPoint("TOPLEFT", col * (tileWidth + gap), -(row * (tileHeight + gap)))
		page.tiles[module.name] = tile
		local icon, flavour = Meta(module)
		local box = IconBox(tile, 42, icon)
		box:SetPoint("TOPLEFT", 12, -12)
		-- (no glow on the tile: the gold border and the badge mark the
		-- important module — user, 2026-09-22)
		local title = Text(tile, "GameFontNormal", module.title, C.text)
		title:SetPoint("TOPLEFT", box, "TOPRIGHT", 12, -2)
		title:SetPoint("RIGHT", tile, "RIGHT", -8, 0)
		title:SetWordWrap(false)
		if module.important then
			local badge = Text(tile, "GameFontNormalSmall", "IMPORTANT", C.accent)
			badge:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -12, -12)
			title:SetPoint("RIGHT", badge, "LEFT", -6, 0)
		end
		local state = Text(tile, "GameFontHighlightSmall", nil, C.dim)
		state:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
		local open = CreateFrame("Button", nil, tile)
		open:SetPoint("BOTTOMLEFT", 12, 10)
		open:SetSize(90, 16)
		open.label = Text(open, "GameFontHighlightSmall", "Open page  >", C.accent2)
		open.label:SetPoint("LEFT")
		open:SetScript("OnEnter", function(self) Colour(self.label, C.accent) end)
		open:SetScript("OnLeave", function(self) Colour(self.label, C.accent2) end)
		open:SetScript("OnClick", function()
			Click("page")
			SelectPage(module.name)
		end)
		tile:EnableMouse(true)
		AttachHover(tile, 0.06)
		tile:HookScript("OnEnter", function(self)
			if not KIT then
				if module.important then
					self:SetBackdropBorderColor(C.text[1], C.text[2], C.text[3], 1)
				else
					self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
				end
			end
			ShowTooltip(self, module.title, flavour)
		end)
		tile:HookScript("OnLeave", function(self)
			if not KIT then
				self:SetBackdropBorderColor(restR, restG, restB, 1)
			end
			GameTooltip:Hide()
		end)
		local switch = CreateSwitch(tile, function(value)
			MelloUI:SetModuleEnabled(module.name, value)
			MelloUI:RefreshConfig()
		end)
		switch:SetPoint("BOTTOMRIGHT", -12, 10)
		tiles.refreshers[#tiles.refreshers + 1] = function()
			local on = MelloUI:IsModuleEnabled(module.name)
			switch:SetValue(on, true)
			box:SetOn(on)
			state:SetText(on and "on" or "off")
			if on then
				Colour(state, C.on)
				Colour(title, C.text)
			else
				Colour(state, C.dim)
				Colour(title, C.dim)
			end
		end
		i = i + 1
		end
	end
	tiles.y = math.ceil(i / columns) * (tileHeight + gap)

	-- What's new.
	local news = NewSection(page, "What's new")
	local y = 6
	for _, entry in ipairs(CHANGELOG) do
		local head = Text(news, "GameFontNormal", "Version " .. entry.version, C.accent)
		head:SetPoint("TOPLEFT", 4, -y)
		y = y + 24
		for _, line in ipairs(entry.lines) do
			local dot = Solid(news, "ARTWORK", C.accent2, 1)
			dot:SetSize(6, 6)
			dot:SetPoint("TOPLEFT", 10, -(y + 6))
			local fs = Text(news, "GameFontHighlight", line, C.text)
			fs:SetPoint("TOPLEFT", 24, -y)
			fs:SetWidth(news:GetWidth() - 30)
			fs:SetWordWrap(true)
			y = y + WrappedHeight(fs, 14) + 8
		end
		y = y + 10
	end
	news.y = y
	page.news = news   -- the tour points at it

	-- Help: commands and links.
	local help = NewSection(page, "Help")
	y = 6
	local head = Text(help, "GameFontNormal", "Slash commands", C.accent)
	head:SetPoint("TOPLEFT", 4, -y)
	y = y + 24
	for _, cmd in ipairs(COMMANDS) do
		local c = Text(help, "GameFontHighlight", cmd[1], C.text)
		c:SetPoint("TOPLEFT", 10, -y)
		local what = Text(help, "GameFontHighlightSmall", cmd[2], C.sub)
		what:SetPoint("TOPLEFT", 230, -(y + 1))
		y = y + 20
	end
	y = y + 10
	local head2 = Text(help, "GameFontNormal", "Links (select the text and copy it)", C.accent)
	head2:SetPoint("TOPLEFT", 4, -y)
	y = y + 24
	for _, link in ipairs(LINKS) do
		local lbl = Text(help, "GameFontHighlight", link[1], C.text)
		lbl:SetPoint("TOPLEFT", 10, -(y + 4))
		local box = CreateFrame("EditBox", nil, help, "InputBoxTemplate")
		box:SetSize(420, 22)
		box:SetPoint("TOPLEFT", 130, -y)
		box:SetAutoFocus(false)
		box:SetText(link[2])
		box:SetCursorPosition(0)
		box:SetScript("OnTextChanged", function(self, user) if user then self:SetText(link[2]) end end)
		box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
		y = y + 28
	end
	y = y + 10
	local note = Text(help, "GameFontHighlightSmall", nil, C.sub)
	note:SetPoint("TOPLEFT", 4, -y)
	note:SetWidth(help:GetWidth() - 8)
	note:SetWordWrap(true)
	note:SetText("Settings are mirrored into account macros because this client does not read its saved variables back; /mello status shows the state of that backup. The voice pack (MelloUI_VoiceOverData) is a separate download from the releases page and goes next to the MelloUI folder.")
	y = y + WrappedHeight(note, 14) + 8
	help.y = y
	page.helpSection = help

	page:Finish()
	if KIT and KIT.SweepControls then
		KIT:SweepControls(page, KitReplace, kitSkin)   -- the Tutorial button on the kit's plate
	end
	return page
end

--------------------------------------------------------------------------------
-- Profiles page
--------------------------------------------------------------------------------

local profilesSection

local function ProfileNames()
	local names = {}
	for name in pairs(MelloUI:Profiles()) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

local function RefreshProfilesPage()
	local sec = profilesSection
	if not sec then
		return
	end
	local db = MelloUI.db
	local gold, muted = MelloUI:PaletteCode("selectedTrim"), MelloUI:PaletteCode("mutedText")
	local active = db.activeProfile and (gold .. db.activeProfile .. "|r") or (muted .. "none|r")
	local default = db.defaultProfile and (gold .. db.defaultProfile .. "|r") or (muted .. "none|r")
	sec.status:SetText(string.format("Active: %s      Default on a fresh install: %s", active, default))
	local names = ProfileNames()
	for i, name in ipairs(names) do
		local row = sec.rowFrames[i]
		if not row then
			row = CreateFrame("Frame", nil, sec)
			row:SetHeight(30)
			row:SetPoint("TOPLEFT", sec.list, "TOPLEFT", 0, -(i - 1) * 32)
			row:SetPoint("RIGHT", sec.list, "RIGHT")
			local line = Solid(row, "BORDER", C.line, 0.6)
			line:SetHeight(1)
			line:SetPoint("BOTTOMLEFT")
			line:SetPoint("BOTTOMRIGHT")
			row:EnableMouse(true)
			AttachHover(row)
			row.name = Text(row, "GameFontHighlight", nil, C.text)
			row.name:SetPoint("LEFT", 14, 0)
			row.name:SetWidth(200)
			row.name:SetWordWrap(false)
			row.load = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
			row.load:SetSize(60, 22)
			row.load:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
			row.load:SetText("Load")
			row.default = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
			row.default:SetSize(100, 22)
			row.default:SetPoint("LEFT", row.load, "RIGHT", 4, 0)
			row.delete = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
			row.delete:SetSize(60, 22)
			row.delete:SetPoint("LEFT", row.default, "RIGHT", 4, 0)
			row.delete:SetText("Delete")
			row.share = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
			row.share:SetSize(60, 22)
			row.share:SetPoint("LEFT", row.delete, "RIGHT", 4, 0)
			row.share:SetText("Share")
			row.baked = Text(row, "GameFontHighlightSmall", nil, C.sub)
			row.baked:SetPoint("LEFT", row.share, "RIGHT", 10, 0)
			sec.rowFrames[i] = row
		end
		row.name:SetText(name)
		local isDefault = db.defaultProfile == name
		row.default:SetText(isDefault and ("Default  " .. MelloUI:PaletteCode("selectedTrim") .. "*|r") or "Set default")
		local builtIn = name == MelloUI.FRESH_PROFILE
		row.baked:SetText(builtIn and "built in" or (MelloUI:IsProfileBaked(name) and "baked" or "not baked yet"))
		row.delete:SetEnabled(not builtIn)
		row.load:SetScript("OnClick", function()
			if MelloUI:LoadProfile(name) then
				MelloUI:Print("Profile '%s' loaded.", name)
			end
			MelloUI:RefreshConfig()
		end)
		row.default:SetScript("OnClick", function()
			MelloUI:SetDefaultProfile(isDefault and nil or name)
			if MelloUI.ScheduleBackup then
				MelloUI:ScheduleBackup("profile default")
			end
			RefreshProfilesPage()
		end)
		row.delete:SetScript("OnClick", function()
			MelloUI:DeleteProfile(name)
			RefreshProfilesPage()
		end)
		row.share:SetScript("OnClick", function()
			local str, err = MelloUI:ExportProfile(name)
			if str then
				MelloUI:ShowText(string.format("share string of '%s' (%d characters)", name, #str), str)
			else
				MelloUI:Print("Could not share '%s': %s.", name, err)
			end
		end)
		row:Show()
	end
	for i = #names + 1, #sec.rowFrames do
		sec.rowFrames[i]:Hide()
	end
	sec.empty:SetShown(#names == 0)
	sec.y = sec.listTop + math.max(#names, 1) * 32 + 10
	sec:Finish()
	local page = pages.Profiles
	if page and page.current == sec then
		page:SetHeight(page.headerHeight + sec:GetHeight() + PAD)
	end
end

local function BuildProfilesPage(width)
	local page = NewPage("Profiles", width)
	BuildPageHeader(page, PROFILES_META.icon, PROFILES_META.title, PROFILES_META.flavour, nil)
	local sec = NewSection(page, "Profiles")
	profilesSection = sec
	sec.rowFrames = {}

	local desc = Text(sec, "GameFontHighlightSmall", nil, C.sub)
	desc:SetPoint("TOPLEFT", 4, -4)
	desc:SetWidth(sec:GetWidth() - 8)
	desc:SetWordWrap(true)
	desc:SetText("A profile is a copy of every setting of every module. The one marked default is applied when the addon starts with no settings at all, such as on a fresh install. Profiles are baked into the addon's own files by Tools\\bake_routes.py after a /reload, which is what makes them survive this client's saved-variable handling.")
	local y = 4 + WrappedHeight(desc, 14) + 16

	sec.nameBox = CreateFrame("EditBox", nil, sec, "InputBoxTemplate")
	sec.nameBox:SetSize(220, 22)
	sec.nameBox:SetPoint("TOPLEFT", 12, -y)
	sec.nameBox:SetAutoFocus(false)
	sec.nameBox:SetMaxLetters(40)
	sec.save = CreateFrame("Button", nil, sec, "UIPanelButtonTemplate")
	sec.save:SetSize(150, 22)
	sec.save:SetPoint("LEFT", sec.nameBox, "RIGHT", 8, 0)
	sec.save:SetText("Save current as")
	local function Save()
		local name = sec.nameBox:GetText()
		local ok, err = MelloUI:SaveProfile(name)
		if ok then
			MelloUI:Print("Profile '%s' saved. /reload writes it out for the baker.", name:gsub("^%s+", ""):gsub("%s+$", ""))
			sec.nameBox:SetText("")
			sec.nameBox:ClearFocus()
		else
			MelloUI:Print(err)
		end
		RefreshProfilesPage()
	end
	sec.save:SetScript("OnClick", Save)
	page.saveButton = sec.save
	-- a share string from someone else, stored under the name typed
	sec.import = CreateFrame("Button", nil, sec, "UIPanelButtonTemplate")
	sec.import:SetSize(150, 22)
	sec.import:SetPoint("LEFT", sec.save, "RIGHT", 6, 0)
	sec.import:SetText("Import as")
	sec.import:SetScript("OnClick", function()
		local name = sec.nameBox:GetText():gsub("^%s+", ""):gsub("%s+$", "")
		if name == "" then
			MelloUI:Print("Type a name for the imported profile first, then click Import as.")
			sec.nameBox:SetFocus()
			return
		end
		MelloUI:ShowPaste(string.format("paste a MelloUI profile string for '%s'", name), function(text)
			local ok, known, total = MelloUI:ImportProfile(name, text)
			if not ok then
				MelloUI:Print("Not imported: %s.", known)
				return false
			end
			MelloUI:Print("Profile '%s' imported (%d settings). Load it from the list to use it.", name, total)
			sec.nameBox:SetText("")
			sec.nameBox:ClearFocus()
			RefreshProfilesPage()
			return true
		end)
	end)
	sec.nameBox:SetScript("OnEnterPressed", Save)
	sec.nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	y = y + 22 + 14

	sec.status = Text(sec, "GameFontHighlight", nil, C.text)
	sec.status:SetPoint("TOPLEFT", 4, -y)
	y = y + 16 + 12

	sec.list = CreateFrame("Frame", nil, sec)
	sec.list:SetPoint("TOPLEFT", 0, -y)
	sec.list:SetPoint("RIGHT", sec, "RIGHT", 0, 0)
	sec.list:SetHeight(1)
	sec.listTop = y

	sec.empty = Text(sec, "GameFontDisable", "No profiles yet. Type a name above and save the current settings.")
	sec.empty:SetPoint("TOPLEFT", sec.list, "TOPLEFT", 14, -8)

	sec.refreshers[#sec.refreshers + 1] = RefreshProfilesPage
	sec.y = y + 42
	page:Finish()
	return page
end

--------------------------------------------------------------------------------
-- Window: band, strip, scroll area
--------------------------------------------------------------------------------

local function StripButton(name, icon, title, flavour)
	local btn = CreateFrame("Button", nil, window.strip)
	local size = KIT and STRIP_ICON or 38
	btn:SetSize(size + 2, size + 2)
	btn.box = IconBox(btn, size, icon, btn)
	btn.box:SetPoint("TOP", 0, 0)
	btn.box:EnableMouse(false)
	local owner = MelloUI:GetModule(name)
	btn.important = owner and owner.important or false   -- the glow, while its page is open only (user, 2026-09-22)
	btn.label = Text(btn, "GameFontHighlightSmall", title, C.accent)
	btn.label:SetPoint("TOP", btn.box, "BOTTOM", 0, -4)
	btn.label:SetJustifyH("CENTER")
	if KIT then
		-- every icon carries its name (user, 2026-09-21); the current page's
		-- in gold, the others in the full text colour (user, 2026-09-23: the
		-- palette's muted text was too faint at this size)
		btn.label:SetWidth(STRIP_ICON + STRIP_GAP + 6)
		btn.label:SetWordWrap(true)
		btn.label:SetMaxLines(2)
		Colour(btn.label, C.sub)
	else
		btn.label:Hide()
	end
	btn:SetScript("OnClick", function()
		if currentPage ~= name then
			Click("page")
		end
		SelectPage(name)
	end)
	btn:SetScript("OnEnter", function(self)
		self.box:SetHovered(true)
		ShowTooltip(self, title, flavour)
	end)
	btn:SetScript("OnLeave", function(self)
		self.box:SetHovered(false)
		self.box:SetPressed(false)
		GameTooltip:Hide()
	end)
	btn:SetScript("OnMouseDown", function(self) self.box:SetPressed(true) end)
	btn:SetScript("OnMouseUp", function(self) self.box:SetPressed(false) end)
	stripButtons[name] = btn
	return btn
end

local function CreateWindow()
	if window then
		return
	end
	KIT = KitWanted()
	window = CreateFrame("Frame", "MelloUIConfigFrame", UIParent, "BackdropTemplate")
	window:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
	window:SetPoint("CENTER")
	window:SetFrameStrata("HIGH")
	window:SetToplevel(true)
	window:SetMovable(true)
	window:EnableMouse(true)
	window:SetClampedToScreen(true)
	window:Hide()
	tinsert(UISpecialFrames, "MelloUIConfigFrame")

	-- Charcoal background: the rock texture tinted dark.
	local bg = window:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(ROCK, "REPEAT", "REPEAT")
	bg:SetHorizTile(true)
	bg:SetVertTile(true)
	bg:SetPoint("TOPLEFT", 6, -6)
	bg:SetPoint("BOTTOMRIGHT", -6, 6)
	bg:SetVertexColor(C.line[1], C.line[2], C.line[3])
	local tint = Solid(window, "BACKGROUND", C.bg, 0.45)
	tint:SetPoint("TOPLEFT", 6, -6)
	tint:SetPoint("BOTTOMRIGHT", -6, 6)
	if KIT then
		-- the kit: the page stone in place of the rock (inside the outer
		-- rail), the outer double rail with its gems grown outward
		KitReplace(bg, { as = "UI-Background-Rock", parent = window, rect = window, inset = KIT:OuterRailInset(), alsoFade = { tint } })
		-- (body = false: the page stone above is the window's one background;
		-- the rail's own stone tile tied with it and won at random, user 2026-09-22)
		KitReplace(KitAnchor(window, "BORDER"), { as = "NineSlicePanelTemplate", parent = window, rect = window, body = false })
	end

	-- Metal frame from the client's own nine-slice art, or a plain border.
	local framed = KIT and true or false
	if not KIT and NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
		local nine = CreateFrame("Frame", nil, window, "NineSlicePanelTemplate")
		nine:SetAllPoints()
		local ok = pcall(NineSliceUtil.ApplyLayoutByName, nine, "GenericMetal")
		framed = ok
		if not ok then
			nine:Hide()
		end
	end
	if not framed then
		window:SetBackdrop({ edgeFile = WHITE, edgeSize = 2 })
		window:SetBackdropBorderColor(C.line[1], C.line[2], C.line[3], 1)
	end
	local innerLine = Box(window, C.bg, C.accent2, 0)
	innerLine:SetPoint("TOPLEFT", 7, -7)
	innerLine:SetPoint("BOTTOMRIGHT", -7, 7)
	innerLine:EnableMouse(false)
	if KIT then
		innerLine:Hide()
	end

	-- Title band, also the drag handle.
	local band = CreateFrame("Frame", nil, window)
	band:SetPoint("TOPLEFT", 8, -16)
	band:SetPoint("TOPRIGHT", -8, -16)
	band:SetHeight(BAND_HEIGHT)
	local bandBg = Solid(band, "BACKGROUND", C.band, 1)
	bandBg:SetAllPoints()
	local bandLine = Solid(band, "BORDER", C.accent2, 1)
	bandLine:SetHeight(1)
	bandLine:SetPoint("BOTTOMLEFT")
	bandLine:SetPoint("BOTTOMRIGHT")
	band.title = Text(band, "GameFontNormalLarge", "MelloUI", C.accent)
	band.title:SetPoint("CENTER", 0, 0)
	if KIT then
		-- the title plate on the outer rail, the title on it (the TitleBar
		-- look centres `TitleText`); the band's own paint goes
		band.TitleText = band.title
		-- fitted to a game window's 20 px title container, not to the band
		-- (the plate came out at the band's full height — user, 2026-09-21)
		band.title:SetFontObject("GameFontNormal")
		KitReplace(bandBg, { as = "TitleBar", parent = band, rect = band, fitHeight = 20, alsoFade = { bandLine } })
		-- the band itself (its paint gone with the title on the plate) holds
		-- the placement switches' labels and the two buttons: the palette's
		-- inner panel under them (user, 2026-09-24: "apply the eye strain
		-- rule to all existing windows"; WINDOW-RULES 2e), a region of the
		-- WINDOW over its page stone, so it can never tie with the band's
		-- controls (frames above it) and the outer rail stays in front
		if KIT.StoneDim then
			KIT:StoneDim(window, { rect = band, layer = "BORDER", sublevel = 1 })
		end
	end
	band:EnableMouse(true)
	band:RegisterForDrag("LeftButton")
	band:SetScript("OnDragStart", function() window:StartMoving() end)
	band:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
	window.band = band

	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -10, -12)
	close:SetScript("OnClick", function() window:Hide() end)
	if KIT and close.GetNormalTexture and close:GetNormalTexture() then
		KitReplace(close:GetNormalTexture(), { as = "RedButton-Exit", button = close, alsoFade = KIT:OtherTextures(close, close:GetNormalTexture()) })
	end

	-- Dynamic UI Modification (user, 2026-09-23/24): the look of the whole
	-- reskin, the one place it is chosen -- borders, Kit Colours, parchment,
	-- every background and backdrop, picked on the interface itself with
	-- previews (Modules/DynamicUI.lua); it closes this window
	local dynamic = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	dynamic:SetSize(190, 22)
	dynamic:SetPoint("RIGHT", close, "LEFT", -8, 0)
	dynamic:SetFrameLevel(close:GetFrameLevel())
	dynamic:SetText("Dynamic UI Modification")
	window.dynamicButton = dynamic
	dynamic:SetScript("OnClick", function()
		if MelloUI.StartDynamicUI then
			MelloUI:StartDynamicUI()
		end
	end)
	dynamic:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Dynamic UI Modification", C.accent[1], C.accent[2], C.accent[3])
		GameTooltip:AddLine("The look of the reskin, all in one place: the borders and Kit Colours of every window, the parchment sheets, "
			.. "and the backgrounds of the action bars, micro menu, bag bar, bags, character window, minimap and professions, "
			.. "chosen on the interface itself with a picture of each choice. Closes the configurator while you pick.", C.text[1], C.text[2], C.text[3], true)
		GameTooltip:Show()
	end)
	dynamic:SetScript("OnLeave", function() GameTooltip:Hide() end)
	if KIT and KIT.SkinRedButton then
		pcall(KIT.SkinRedButton, KIT, dynamic, KitReplace)
	end
	window.dynamic = dynamic

	-- Window placement (user, 2026-09-23: "Unlock the Window, Reset Position
	-- and Turn off Auto Snapping should be placed along with as the main
	-- options on top of that window"): on the band's left, as Dynamic UI
	-- Modification is on its right. UI Modifications' settings.
	local texts = (MelloUI:GetModule("UIModifications") or {}).placementTexts or {}
	local function PlacementTip(owner, key)
		local t = texts[key]
		if t then
			owner:HookScript("OnEnter", function(self) ShowTooltip(self, t.name, t.desc) end)
			owner:HookScript("OnLeave", function() GameTooltip:Hide() end)
		end
	end
	local function PlacementSwitch(key, label, anchor, gap)
		local sw = CreateSwitch(window, function(value)
			MelloUI:NotifySettingChanged("UIModifications", key, value)
			MelloUI:RefreshConfig()
		end)
		sw:SetFrameLevel(close:GetFrameLevel())
		if anchor then
			sw:SetPoint("LEFT", anchor, "RIGHT", gap, 0)
		else
			sw:SetPoint("LEFT", band, "LEFT", 34, 0)   -- as far in from the left as Dynamic UI Modification is from the right
		end
		local text = Text(sw, "GameFontNormalSmall", label, C.text)
		text:SetPoint("LEFT", sw, "RIGHT", 2, 0)
		PlacementTip(sw, key)
		return sw, text
	end
	local unlock, unlockText = PlacementSwitch("unlock", (texts.unlock and texts.unlock.name) or "Unlock the Windows")
	local snap, snapText = PlacementSwitch("autoSnap", (texts.autoSnap and texts.autoSnap.name) or "Auto Snapping", unlockText, 12)
	local reset = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	reset:SetSize(120, 22)
	reset:SetPoint("LEFT", snapText, "RIGHT", 12, 0)
	reset:SetFrameLevel(close:GetFrameLevel())
	reset:SetText((texts.reset and texts.reset.name) or "Reset positions")
	reset:SetScript("OnClick", function()
		local um = MelloUI:GetModule("UIModifications")
		if um and um.ResetPositions then
			um.ResetPositions()
		end
		MelloUI:RefreshConfig()
	end)
	PlacementTip(reset, "reset")
	if KIT and KIT.SkinRedButton then
		pcall(KIT.SkinRedButton, KIT, reset, KitReplace)
	end
	-- the switches follow the settings, however they change (the unlock
	-- banner's "click here to lock them" too)
	local function RefreshPlacement()
		local db = MelloUI:GetModuleDB("UIModifications")
		unlock:SetValue(db and db.unlock and true or false, true)
		snap:SetValue(not (db and db.autoSnap == false), true)
	end
	window.placementUnlock = unlock   -- the tour points at it
	window:HookScript("OnShow", RefreshPlacement)
	hooksecurefunc(MelloUI, "NotifySettingChanged", function(_, name, key)
		if name == "UIModifications" and (key == "unlock" or key == "autoSnap") then
			RefreshPlacement()
		end
	end)
	RefreshPlacement()

	-- Icon strip.
	local strip = CreateFrame("Frame", nil, window)
	strip:SetPoint("TOPLEFT", band, "BOTTOMLEFT", 0, 0)
	strip:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT", 0, 0)
	strip:SetHeight(KIT and STRIP_HEIGHT_KIT or STRIP_HEIGHT)
	local stripBg = Solid(strip, "BACKGROUND", C.band, 0.8)
	stripBg:SetAllPoints()
	local stripLine = Solid(strip, "BORDER", C.accent2, 1)
	stripLine:SetHeight(1)
	stripLine:SetPoint("BOTTOMLEFT")
	stripLine:SetPoint("BOTTOMRIGHT")
	if KIT then
		-- ST5 (user, 2026-09-21): the L1 box (single rail + list-box stone)
		-- under the icon strip, one level under the strip so the buttons
		-- and their rims stay above it
		-- (at the strip's own level: one under it tied with the window's page
		-- stone and the box's dark body did not show — user, 2026-09-21)
		KitReplace(stripBg, { as = "Professions-background-summarylist", rect = strip, parent = strip, level = 0, alsoFade = { stripLine } })
	end
	window.strip = strip

	local entries = { { "Home", LOGO, "Home", HOME_FLAVOUR } }
	for _, module in MelloUI:IterateModules() do
		if not module.hidden then
			local icon, flavour = Meta(module)
			entries[#entries + 1] = { module.name, icon, module.title, flavour }
		end
	end
	entries[#entries + 1] = { "Profiles", PROFILES_META.icon, "Profiles", PROFILES_META.flavour }
	local spacing = (WINDOW_WIDTH - 16 - PAD * 2) / #entries
	local left = PAD
	if KIT then
		-- packed and centred: a button's width plus the gap per entry
		spacing = STRIP_ICON + 2 + STRIP_GAP
		left = (WINDOW_WIDTH - 16 - spacing * #entries) / 2
	end
	for i, e in ipairs(entries) do
		local btn = StripButton(e[1], e[2], e[3], e[4])
		btn:SetPoint("TOP", strip, "TOPLEFT", left + spacing * (i - 1) + spacing / 2, -(KIT and 12 or 8))
		if (i == 2 or i == #entries) and not KIT then
			local sep = Solid(strip, "ARTWORK", C.line, 1)
			sep:SetWidth(1)
			sep:SetPoint("TOP", strip, "TOPLEFT", PAD + spacing * (i - 1), -14)
			sep:SetHeight(STRIP_HEIGHT - 28)
		end
	end

	-- Scrolling page area.
	window.scroll = CreateFrame("ScrollFrame", "MelloUIConfigScroll", window, "UIPanelScrollFrameTemplate")
	window.scroll:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, -4)
	window.scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -34, 16)
	if window.scroll.ScrollBar then
		window.scroll.ScrollBar:ClearAllPoints()
		window.scroll.ScrollBar:SetPoint("TOPLEFT", window.scroll, "TOPRIGHT", 6, -16)
		window.scroll.ScrollBar:SetPoint("BOTTOMLEFT", window.scroll, "BOTTOMRIGHT", 6, 16)
	end
	window.pageWidth = WINDOW_WIDTH - 8 - 34

	-- Smooth scrolling (user, 2026-09-23): the wheel moves a target and the
	-- page glides to it, quick at first and easing in (each notch adds to
	-- the target, so a fast spin runs on smoothly); a scroll set any other
	-- way (the scroll bar dragged, a page opened, a jump) stops the glide
	-- where it is. Reduce Motion (UI Modifications) jumps as before.
	local scroll = window.scroll
	local WHEEL_STEP = 80      -- UI px a notch
	local GLIDE_RATE = 14      -- how fast the gap closes (per second, exponential)
	local glider = CreateFrame("Frame", nil, scroll)
	glider:Hide()
	scroll.target = 0
	local gliding = false
	local function SetScroll(v)
		gliding = true
		scroll:SetVerticalScroll(v)
		gliding = false
	end
	glider:SetScript("OnUpdate", function(self, elapsed)
		local cur = scroll:GetVerticalScroll() or 0
		local diff = scroll.target - cur
		if math.abs(diff) < 0.5 then
			SetScroll(scroll.target)
			self:Hide()
			return
		end
		SetScroll(cur + diff * math.min(1, elapsed * GLIDE_RATE))
	end)
	hooksecurefunc(scroll, "SetVerticalScroll", function(_, v)
		if not gliding then
			scroll.target = v or 0
			glider:Hide()
		end
	end)
	-- glide to an offset (the wheel, a jump to a section)
	function scroll:GlideTo(offset)
		local range = self:GetVerticalScrollRange() or 0
		self.target = math.max(0, math.min(range, offset))
		if MelloUI.Anim and MelloUI.Anim.reduceMotion then
			self:SetVerticalScroll(self.target)
			return
		end
		glider:Show()
	end
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local base = glider:IsShown() and self.target or (self:GetVerticalScroll() or 0)
		self:GlideTo(base - delta * WHEEL_STEP)
	end)

	-- The window kept inside the screen (user, 2026-09-24: "UI Scaling Break
	-- the UI"): it is 1000 x 760 UI units, and the screen is 768 / UI Scale
	-- units tall, so from a UI Scale of about 1 up (or in a small game
	-- window) its top and bottom ran off the screen, the tabs and the close
	-- button out of reach. Scaled down to fit, never up; again whenever the
	-- UI scale changes. A scale given with the window mover's wheel stands
	-- (it is the user's), and the backgrounds keep the UI's one resolution.
	window.FitToScreen = function(self)
		local um = MelloUI:GetModuleDB("UIModifications")
		local pos = um and um.positions and um.positions.MelloUIConfigFrame
		if pos and pos.scale then
			return
		end
		local ok, sw, sh = pcall(UIParent.GetSize, UIParent)
		if not (ok and type(sw) == "number" and type(sh) == "number") or sw <= 0 or sh <= 0 then
			return
		end
		local fit = math.min(1, (sw - 16) / WINDOW_WIDTH, (sh - 16) / WINDOW_HEIGHT)
		if math.abs((self:GetScale() or 1) - fit) > 0.001 then
			self:SetScale(fit)
			if MelloUI.Kit and MelloUI.Kit.RetileBackgrounds then
				MelloUI.Kit:RetileBackgrounds()
			end
		end
	end
	if MelloUI.Kit and MelloUI.Kit.OnUIScaleChanged then
		MelloUI.Kit:OnUIScaleChanged(function(reason)
			if reason == "uiscale" and window:IsShown() then
				window:FitToScreen()
			end
		end)
	end
	window:SetScript("OnShow", function(self)
		self:FitToScreen()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
		MelloUI:RefreshConfig()
	end)
	window:SetScript("OnHide", function()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
	end)
end

local function GetPage(name)
	local page = pages[name]
	if page then
		return page
	end
	if name == "Home" then
		page = BuildHomePage(window.pageWidth)
	elseif name == "Profiles" then
		page = BuildProfilesPage(window.pageWidth)
	else
		local module = MelloUI.modules[name]
		if not module then
			return nil
		end
		page = BuildModulePage(module, window.pageWidth)
	end
	pages[name] = page
	return page
end

function RefreshStrip()
	for name, btn in pairs(stripButtons) do
		local selected = name == currentPage
		btn.box:SetSelected(selected)
		if btn.important then
			btn.box:SetGlow(selected)
		end
		if KIT then
			btn.label:Show()
			Colour(btn.label, selected and C.accent or C.sub)
		else
			btn.label:SetShown(selected)
		end
		local module = MelloUI.modules[name]
		if module then
			btn.box:SetOn(MelloUI:IsModuleEnabled(name))
		end
	end
end

function SelectPage(name)
	if not window then
		return
	end
	local page = GetPage(name)
	if not page then
		page = GetPage("Home")
		name = "Home"
	end
	if currentPage and pages[currentPage] and pages[currentPage] ~= page then
		pages[currentPage]:Hide()
	end
	currentPage = name
	page:SetWidth(window.pageWidth)
	window.scroll:SetScrollChild(page)
	window.scroll:SetVerticalScroll(0)
	page:Show()
	page:Refresh()
	RefreshStrip()
end

-- Bring every visible value in line with the settings (after a profile load,
-- a slash command, or a switch flipped elsewhere).
function MelloUI:RefreshConfig()
	if not window then
		return
	end
	RefreshStrip()
	if currentPage and pages[currentPage] then
		pages[currentPage]:Refresh()
	end
	if pages.Home and currentPage ~= "Home" then
		pages.Home:Refresh()
	end
end

function MelloUI:BuildConfig()
	-- Nothing to register up front; the window is built on first use.
end

function MelloUI:OpenConfig(moduleName)
	CreateWindow()
	local module = ModuleByName(moduleName)
	local target = module and module.name or (moduleName and moduleName:lower() == "profiles" and "Profiles") or nil
	if window:IsShown() and not target then
		window:Hide()
		return
	end
	window:Show()
	SelectPage(target or currentPage or "Home")
end

-- The window's parts for the guided tour (Core/Tutorial.lua): the frames
-- its steps point at, page selection, and a scroll that brings a part of
-- the current page into view.
function MelloUI:ConfigTour()
	CreateWindow()
	return {
		window = window,
		band = window.band,
		strip = window.strip,
		stripButton = function(name) return stripButtons[name] end,
		select = function(name) SelectPage(name) end,
		page = function(name) return pages[name] end,
		scrollTo = function(target)
			local page = currentPage and pages[currentPage]
			if not (page and target and target.GetTop and window.scroll) then
				return
			end
			local pageTop, top = page:GetTop(), target:GetTop()
			if not (pageTop and top) then
				return
			end
			local offset = math.max(0, pageTop - top - 60)
			window.scroll:GlideTo(offset)
		end,
	}
end

--------------------------------------------------------------------------------
-- Game menu button (Escape > MelloUI), in its own section above Logout.
--------------------------------------------------------------------------------

local gameMenuHooked = false

local function AddGameMenuButton(menu)
	local button = menu:AddButton("MelloUI", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
		HideUIPanel(menu)
		MelloUI:OpenConfig()
	end)
	local logoutText = LOG_OUT
	if menu.GetLogoutText then
		local ok, text = pcall(menu.GetLogoutText, menu)
		if ok and text then
			logoutText = text
		end
	end
	local logoutIndex
	for _, other in ipairs(menu.buttons or {}) do
		if other ~= button and other:GetText() == logoutText then
			logoutIndex = other.layoutIndex
			break
		end
	end
	if logoutIndex then
		for _, other in ipairs(menu.buttons) do
			if other ~= button and other.layoutIndex and other.layoutIndex >= logoutIndex then
				other.layoutIndex = other.layoutIndex + 1
			end
		end
		button.layoutIndex = logoutIndex
		button.topPadding = 20
	end
	if menu.MarkDirty then
		menu:MarkDirty()
	end
end

local function HookGameMenu()
	if gameMenuHooked or not GameMenuFrame then
		return
	end
	if GameMenuFrame.InitButtons then
		gameMenuHooked = true
		hooksecurefunc(GameMenuFrame, "InitButtons", AddGameMenuButton)
	end
end

HookGameMenu()
if not gameMenuHooked then
	local waiter = CreateFrame("Frame")
	waiter:RegisterEvent("PLAYER_LOGIN")
	waiter:SetScript("OnEvent", function(self)
		HookGameMenu()
		self:UnregisterAllEvents()
	end)
end

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- /mello secrets: what this client offers for SECRET values (user, 2026-09-23:
-- "test the secret value tools on the client first"). Part 1, at once: which
-- of the secret-value APIs and widget methods exist. Part 2, armed until a
-- secret shows up (fight something with a target): what the client allows
-- with one -- concatenation, format, compare, arithmetic, SetText, SetAlpha,
-- a status bar. Every test runs in pcall on MelloUI's own throwaway widgets;
-- a secret is never printed, only "ok" / the error / whether the result is
-- itself secret.
--------------------------------------------------------------------------------

local probe

local function IsSecret(v)
	return issecretvalue and issecretvalue(v) or false
end

local function Lookup(path)
	local v = _G
	for part in path:gmatch("[^%.]+") do
		if type(v) ~= "table" then
			return nil
		end
		v = v[part]
	end
	return v
end

-- "ok" (and whether the result is secret), or the error, first line only
local function Try(fn, ...)
	local ok, result = pcall(fn, ...)
	if not ok then
		local text = tostring(result):gsub("^[^:]*:%d+: ", ""):match("^[^\n]*") or "?"
		return "|cffff6060error|r " .. text:sub(1, 110)
	end
	if IsSecret(result) then
		return "|cff60ff60ok|r, result SECRET"
	end
	if result == nil then
		return "|cff60ff60ok|r (nil)"
	end
	return "|cff60ff60ok|r, result plain"
end

local API = {
	"issecretvalue", "canaccessvalue", "hasanysecretvalues", "issecrettable",
	"C_Secrets.HasSecretRestrictions", "C_Secrets.ShouldAurasBeSecret", "C_Secrets.ShouldUnitIdentityBeSecret",
	"C_Secrets.ShouldCooldownsBeSecret", "C_Secrets.GetSpellAuraSecrecy", "C_Secrets.CanCompareUnitTokens",
	"C_RestrictedActions.IsAddOnRestrictionActive", "C_RestrictedActions.GetAddOnRestrictionState",
	"C_CurveUtil.CreateCurve", "C_CurveUtil.CreateColorCurve", "C_CurveUtil.EvaluateColorValueFromBoolean",
	"CurveConstants.ScaleTo100", "Enum.LuaCurveType",
	"UnitHealthPercent", "UnitHealthMissing", "UnitGetDetailedHealPrediction", "CreateUnitHealPredictionCalculator",
	"UnitCastingDuration", "UnitChannelDuration", "C_UnitAuras.GetAuraDuration", "C_UnitAuras.GetAuraDispelTypeColor",
	"AbbreviateNumbers", "CreateAbbreviateConfig",
	"C_StringUtil.TruncateWhenZero", "C_StringUtil.RoundToNearestString", "C_StringUtil.CreateNumericRuleFormatter",
	"C_DurationUtil.CreateDurationTextBinding", "Enum.StatusBarInterpolation",
	"C_EncodingUtil.SerializeCBOR", "C_EncodingUtil.CompressString", "C_EncodingUtil.EncodeBase64",
	"C_Navigation.GetFrame", "C_Navigation.GetDistance", "C_SuperTrack.SetSuperTrackedUserWaypoint",
}

local function ProbeAPIs()
	MelloUI:Print("Secret-value tools on this client (part 1 of 2):")
	local have, missing = {}, {}
	for _, path in ipairs(API) do
		if Lookup(path) ~= nil then
			have[#have + 1] = path
		else
			missing[#missing + 1] = path
		end
	end
	MelloUI:Print("  present (%d): %s", #have, table.concat(have, ", "))
	MelloUI:Print("  MISSING (%d): %s", #missing, #missing > 0 and table.concat(missing, ", ") or "none")

	-- widget methods, on throwaway widgets of our own
	local f = CreateFrame("Frame")
	local sb = CreateFrame("StatusBar", nil, f)
	local tex = f:CreateTexture()
	local methods = {
		{ "StatusBar:SetTimerDuration", sb.SetTimerDuration },
		{ "Region:SetAlphaFromBoolean", tex.SetAlphaFromBoolean },
		{ "Texture:SetVertexColorFromBoolean", tex.SetVertexColorFromBoolean },
		{ "Region:SetShownFromBoolean", tex.SetShownFromBoolean },
	}
	for _, m in ipairs(methods) do
		MelloUI:Print("  %s: %s", m[1], m[2] and "present" or "MISSING")
	end
	MelloUI:Print("  StatusBar:SetValue with smoothing: %s", Try(function()
		sb:SetMinMaxValues(0, 10)
		sb:SetValue(5, Enum.StatusBarInterpolation.ExponentialEaseOut)
		return true
	end))
	MelloUI:Print("  AuraContainer frame type: %s",
		Try(function() return CreateFrame("AuraContainer", nil, f, "CustomAuraContainerTemplate") end))
	if C_EventUtils and C_EventUtils.IsEventValid then
		MelloUI:Print("  event ADDON_RESTRICTION_STATE_CHANGED: %s",
			C_EventUtils.IsEventValid("ADDON_RESTRICTION_STATE_CHANGED") and "present" or "MISSING")
	end
	if C_Secrets and C_Secrets.HasSecretRestrictions then
		local ok, on = pcall(C_Secrets.HasSecretRestrictions)
		MelloUI:Print("  secret restrictions active on this client: %s", ok and not IsSecret(on) and tostring(on) or "?")
	end
	-- a colour curve on the player's own health (the player's is never secret)
	if C_CurveUtil and C_CurveUtil.CreateColorCurve and UnitHealthPercent then
		MelloUI:Print("  colour curve through UnitHealthPercent: %s", Try(function()
			local curve = C_CurveUtil.CreateColorCurve()
			if Enum.LuaCurveType then
				curve:SetType(Enum.LuaCurveType.Step)
			end
			curve:AddPoint(0, CreateColor(1, 0, 0, 1))
			curve:AddPoint(0.5, CreateColor(0, 1, 0, 1))
			local color = UnitHealthPercent("player", true, curve)
			return color and color.GetRGB and select(2, color:GetRGB())
		end))
	end
	f:Hide()
end

-- the first secret the game hands us: a health / power number of a unit in
-- reach, or a name
local UNITS = { "target", "focus", "mouseover", "nameplate1", "nameplate2", "nameplate3", "boss1", "party1" }
local function FindSecret()
	for _, unit in ipairs(UNITS) do
		for _, fn in ipairs({ UnitHealth, UnitHealthMax, UnitPower }) do
			local ok, v = pcall(fn, unit)
			if ok and IsSecret(v) then
				return v, unit, "number"
			end
		end
	end
	for _, unit in ipairs(UNITS) do
		local ok, v = pcall(UnitName, unit)
		if ok and IsSecret(v) then
			return v, unit, "name"
		end
	end
end

local function ProbeSecret(v, unit, kind)
	MelloUI:Print("Secret found (part 2 of 2): a %s of %s. What this client allows with it:", kind, unit)
	local f = CreateFrame("Frame")
	local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	local tex = f:CreateTexture()
	local sb = CreateFrame("StatusBar", nil, f)
	local tests = {
		{ "concatenate  \"x\" .. v", function() return "x" .. v end },
		{ "string.format(\"%s\", v)", function() return string.format("%s", v) end },
		{ "tostring(v)", function() return tostring(v) end },
		{ "compare  v == v", function() return v == v end },
		{ "boolean test  if v then", function() if v then return true end return false end },
		{ "table key  t[v]", function() return rawset({}, v, 1) ~= nil end },
		{ "fs:SetText(v)", function() fs:SetText(v); return fs:GetText() end },
		{ "fs:SetText(\"x\" .. v)", function() fs:SetText("x" .. v); return fs:GetText() end },
		{ "fs:SetFormattedText(\"%s\", v)", function() fs:SetFormattedText("%s", v); return fs:GetText() end },
	}
	if kind == "number" then
		local numeric = {
			{ "compare  v > 0", function() return v > 0 end },
			{ "arithmetic  v + 1", function() return v + 1 end },
			{ "string.format(\"%d\", v)", function() return string.format("%d", v) end },
			{ "AbbreviateNumbers(v)", function() return AbbreviateNumbers(v) end },
			{ "C_StringUtil.TruncateWhenZero(v)", function() return C_StringUtil.TruncateWhenZero(v) end },
			{ "tex:SetAlpha(v)", function() tex:SetAlpha(v); return tex:GetAlpha() end },
			{ "StatusBar SetMinMaxValues / SetValue", function() sb:SetMinMaxValues(0, UnitHealthMax(unit)); sb:SetValue(v); return true end },
			{ "UnitHealthPercent(unit, true, ScaleTo100)", function() return UnitHealthPercent(unit, true, CurveConstants.ScaleTo100) end },
		}
		for _, t in ipairs(numeric) do
			tests[#tests + 1] = t
		end
	end
	for _, t in ipairs(tests) do
		MelloUI:Print("  %-42s %s", t[1], Try(t[2]))
	end
	f:Hide()
	MelloUI:ShowLog("mello secrets")
end

local function ArmProbe()
	if not probe then
		probe = CreateFrame("Frame")
		probe:SetScript("OnEvent", function(self)
			local v, unit, kind = FindSecret()
			if IsSecret(v) then
				self:UnregisterAllEvents()
				ProbeSecret(v, unit, kind)
			end
		end)
	end
	probe:RegisterEvent("PLAYER_TARGET_CHANGED")
	probe:RegisterEvent("PLAYER_REGEN_DISABLED")
	probe:RegisterEvent("UNIT_HEALTH")
	probe:RegisterEvent("NAME_PLATE_UNIT_ADDED")
end

function MelloUI:SecretProbe()
	self:ClearLog()
	ProbeAPIs()
	local v, unit, kind = FindSecret()
	if IsSecret(v) then
		ProbeSecret(v, unit, kind)
		return
	end
	ArmProbe()
	self:Print("No secret value in reach right now. Part 2 runs by itself as soon as the game hands one out: target an enemy and fight it. /mello secrets again re-runs part 1.")
	self:ShowLog("mello secrets")
end

--------------------------------------------------------------------------------
-- /mello auras: what this client's aura container offers (user, 2026-09-23:
-- MelloUI's own buff / debuff rows on the target frame, enemy nameplates and
-- the player's buffs, drawn by the game's AuraContainer so no aura data is
-- ever read). The retail 12.1 API is the guide; this lists what Forever
-- really has, and what the game's own aura frames are made of, before any
-- of it is used.
--------------------------------------------------------------------------------

local AURA_CONTAINER_METHODS = {
	"SetUnit", "GetUnit", "SetEnabled", "IsEnabled", "UpdateAllAuras",
	"AddAuraGroup", "AddAuraSlot", "GetAuraGroupFrame", "GetAuraGroupFrameCount", "HasAuraGroup",
	"SetAuraGroupFilterString", "SetAuraGroupLayout", "SetAuraGroupMaxFrameCount", "SetAuraGroupSortMethod",
	"SetAuraGroupCandidateFilters", "SetAuraGroupEnabled", "AddItemEnchantment",
	"SetFlowLayoutAnchorPoint", "SetFlowLayoutAxis", "SetFlowLayoutGrowthDirection",
	"SetFlowLayoutMaximumLineSize", "SetFlowLayoutPadding", "ResetFlowLayoutOptions",
	"SetAuraProcessingPolicy", "SetEditModePreviewEnabled",
}
local AURA_BUTTON_METHODS = {
	"SetIcon", "SetDurationCooldown", "SetDurationText", "SetApplicationCount", "SetApplicationBar",
	"AddDispelTypeTexture", "SetAuraBorder", "SetAuraSymbol", "SetCancelAuraButtons",
	"SetTooltipAnchorPoint", "SetHideTooltipInCombat", "SetRadialPandemicIndicator",
}
local AURA_GLOBALS = {
	"AuraContainerSortMethod", "AuraContainerSortDirection", "CustomAuraContainerAuraProcessingPolicy",
	"Enum.CustomAuraButtonDispelTypeTextureStyle", "Enum.CustomAuraButtonDispelTypeStealableFilter",
	"AnchorUtil.FlowLayoutAxis", "C_AuraContainerUtil", "GenerateClosure",
}

local function Keys(t, match)
	local out = {}
	if type(t) == "table" then
		for k in pairs(t) do
			if type(k) == "string" and (not match or k:lower():find(match, 1, true)) then
				out[#out + 1] = k
			end
		end
	end
	table.sort(out)
	return table.concat(out, ", ")
end

function MelloUI:AuraProbe()
	self:ClearLog()
	local P = function(...) self:Print(...) end
	local okC, c = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
	if not (okC and c) then
		P("AuraContainer: cannot be created here (%s). Nothing else to probe.", tostring(c))
		self:ShowLog("mello auras")
		return
	end
	c:Hide()
	local have, miss = {}, {}
	for _, m in ipairs(AURA_CONTAINER_METHODS) do
		if type(c[m]) == "function" then have[#have + 1] = m else miss[#miss + 1] = m end
	end
	P("Container methods present (%d): %s", #have, table.concat(have, ", "))
	P("Container methods MISSING (%d): %s", #miss, #miss > 0 and table.concat(miss, ", ") or "none")
	for _, g in ipairs(AURA_GLOBALS) do
		local v = Lookup(g)
		P("  %s: %s%s", g, type(v), type(v) == "table" and (" { " .. Keys(v) .. " }") or "")
	end
	-- a group on the player's auras: every button it makes is looked at
	local buttons, initErr = {}, nil
	local okG, errG = pcall(function()
		c:SetSize(200, 40)
		c:SetPoint("CENTER")
		c:SetUnit("player")
		c:AddAuraGroup("melloProbe", "HELPFUL", {
			maxFrameCount = 4,
			initializeFrame = function(button)
				buttons[#buttons + 1] = button
				local ok, e = pcall(function()
					button:SetSize(24, 24)
					local icon = button:CreateTexture(nil, "BORDER")
					icon:SetAllPoints()
					button:SetIcon(icon)
				end)
				if not ok then initErr = e end
			end,
		})
		c:Show()
		c:UpdateAllAuras()
	end)
	P("AddAuraGroup on your buffs: %s%s", okG and "ok" or "FAILED", okG and "" or (": " .. tostring(errG)))
	local okN, n = pcall(c.GetAuraGroupFrameCount, c, "melloProbe")
	P("  buttons in the group: %s (you have to have a buff for any)", tostring(okN and n or n))
	if initErr then
		P("  a button's set-up failed: %s", tostring(initErr))
	end
	local b = buttons[1]
	if b then
		P("  a button is a %s", tostring(b.GetObjectType and b:GetObjectType()))
		local bh, bm = {}, {}
		for _, m in ipairs(AURA_BUTTON_METHODS) do
			if type(b[m]) == "function" then bh[#bh + 1] = m else bm[#bm + 1] = m end
		end
		P("Button methods present (%d): %s", #bh, table.concat(bh, ", "))
		P("Button methods MISSING (%d): %s", #bm, #bm > 0 and table.concat(bm, ", ") or "none")
	else
		P("  no button was made: buff yourself (or have any buff) and run /mello auras again for the button methods.")
	end
	pcall(c.SetEnabled, c, false)
	c:Hide()
	-- the game's own aura frames: what they are made of on this client
	local function Kind(f)
		return f and f.GetObjectType and f:GetObjectType() or type(f)
	end
	P("Game's buff frame: BuffFrame %s, DebuffFrame %s; aura keys: %s", Kind(BuffFrame), Kind(DebuffFrame), Keys(BuffFrame, "aura"))
	P("  BuffFrame.AuraContainer: %s", Kind(BuffFrame and BuffFrame.AuraContainer))
	P("Game's target frame: aura keys %s", Keys(TargetFrame, "aura"))
	P("  TargetFrame.auraPools: %s, TargetFrame.AurasContainer: %s", Kind(TargetFrame and TargetFrame.auraPools), Kind(TargetFrame and TargetFrame.AurasContainer))
	local okP, plates = pcall(C_NamePlate.GetNamePlates)
	local uf = okP and type(plates) == "table" and plates[1] and plates[1].UnitFrame
	if uf then
		P("A nameplate's unit frame: aura keys %s", Keys(uf, "aura"))
		P("  UnitFrame.AurasFrame: %s; its keys: %s", Kind(uf.AurasFrame), Keys(uf.AurasFrame))
	else
		P("No nameplate on screen: stand near an enemy for the nameplate part.")
	end
	self:ShowLog("mello auras")
end

SLASH_MELLOUI1 = "/mello"
SLASH_MELLOUI2 = "/melloui"
SlashCmdList.MELLOUI = function(msg)
	local raw = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	msg = raw:lower()
	local cmd, rest = msg:match("^(%S+)%s*(.-)$")
	-- profile names keep their case (a name saved from the window is
	-- stored as typed; lowercasing here found none of them)
	local rawRest = raw:match("^%S+%s*(.-)$") or ""

	if cmd == "list" then
		MelloUI:Print("Modules:")
		for name, module in MelloUI:IterateModules() do
			local state = MelloUI:IsModuleEnabled(name) and "|cff40ff40on|r" or "|cffff4040off|r"
			print(string.format("   %s  -  %s (%s)", state, module.title, name))
		end
	elseif cmd == "enable" or cmd == "disable" then
		local module = ModuleByName(rest)
		if module then
			MelloUI:SetModuleEnabled(module.name, cmd == "enable")
			MelloUI:RefreshConfig()
			MelloUI:Print("%s %s", module.title, cmd == "enable" and "enabled" or "disabled")
		else
			MelloUI:Print("Unknown module '%s'. Use /mello list.", rest)
		end
	elseif cmd == "profile" or cmd == "profiles" then
		local sub, name = rest:match("^(%S+)%s*(.-)$")
		if sub then
			name = rawRest:match("^%S+%s*(.-)$") or name
		end
		if sub == "save" and name ~= "" then
			local ok, err = MelloUI:SaveProfile(name)
			MelloUI:Print(ok and ("Profile '" .. name .. "' saved. /reload writes it out for the baker.") or err)
		elseif sub == "load" and name ~= "" then
			MelloUI:Print(MelloUI:LoadProfile(name) and ("Profile '" .. name .. "' loaded.") or ("No profile '" .. name .. "'."))
		elseif sub == "delete" and name ~= "" then
			MelloUI:Print(MelloUI:DeleteProfile(name) and ("Profile '" .. name .. "' deleted.") or ("No profile '" .. name .. "'."))
		elseif sub == "default" then
			if name == "" or name == "none" then
				MelloUI:SetDefaultProfile(nil)
				MelloUI:Print("No default profile.")
			else
				MelloUI:Print(MelloUI:SetDefaultProfile(name) and ("'" .. name .. "' is applied on a fresh install.") or ("No profile '" .. name .. "'."))
			end
		elseif sub == "export" and name ~= "" then
			local str, err = MelloUI:ExportProfile(name)
			if str then
				MelloUI:ShowText(string.format("share string of '%s' (%d characters)", name, #str), str)
			else
				MelloUI:Print("Could not share '%s': %s.", name, err)
			end
		elseif sub == "import" and name ~= "" then
			MelloUI:ShowPaste(string.format("paste a MelloUI profile string for '%s'", name), function(text)
				local ok, known, total = MelloUI:ImportProfile(name, text)
				if not ok then
					MelloUI:Print("Not imported: %s.", known)
					return false
				end
				MelloUI:Print("Profile '%s' imported (%d settings). /mello profile load %s to use it.", name, total, name)
				MelloUI:RefreshConfig()
				return true
			end)
		elseif sub == "list" or sub == nil then
			local names = ProfileNames()
			MelloUI:Print("Profiles (%d). Active: %s, default: %s.", #names, tostring(MelloUI.db.activeProfile or "none"), tostring(MelloUI.db.defaultProfile or "none"))
			for _, n in ipairs(names) do
				print("   " .. n .. (MelloUI:IsProfileBaked(n) and "" or "  (not baked yet)"))
			end
		else
			MelloUI:Print("/mello profile save <name> | load <name> | delete <name> | default <name|none> | export <name> | import <name> | list")
		end
		MelloUI:RefreshConfig()
	elseif cmd == "layout" then
		if rest == "export" then
			local text, name = MelloUI:ExportEditModeLayout()
			if text then
				MelloUI:ClearLog()
				MelloUI:Print("Edit Mode layout '%s' (%d chars), the game's share string; paste it into Media/EditModeLayout.lua as `layout`:", tostring(name), #text)
				MelloUI:Print("%s", text)
				MelloUI:ShowLog("Edit Mode layout")
			else
				MelloUI:Print("Edit Mode layout: %s", tostring(name))
			end
		elseif rest == "apply" then
			local ok, why = MelloUI:ApplyEditModeLayout()
			if not ok then
				MelloUI:Print("Edit Mode layout: %s", tostring(why))
			end
		else
			MelloUI:Print("Edit Mode layout: %s", MelloUI:EditModeLayoutStatus())
			MelloUI:Print("/mello layout export (the active layout's share string, for baking) | apply (the baked layout into Edit Mode, made active)")
		end
	elseif cmd == "cpu" then
		if not (GetCVar and GetCVar("scriptProfile") == "1") then
			MelloUI:Print("CPU profiling is off. Run  /console scriptProfile 1  then /reload, and /mello cpu again. Turn it off afterwards with  /console scriptProfile 0  (profiling itself costs a little performance).")
			return
		end
		if rest == "reset" then
			ResetCPUUsage()
			MelloUI:Print("CPU counters reset. Play a while, then /mello cpu.")
			return
		end
		UpdateAddOnCPUUsage()
		local total = GetAddOnCPUUsage(ADDON_NAME) or 0
		local rows = {}
		for _, entry in ipairs(MelloUI.profiled) do
			local ms, calls
			if type(entry.target) == "function" then
				ms, calls = GetFunctionCPUUsage(entry.target, true)
			elseif type(entry.target) == "table" then
				ms, calls = GetFrameCPUUsage(entry.target, true)
			end
			if ms and ms > 0 then
				rows[#rows + 1] = { module = entry.module, label = entry.label, ms = ms, calls = calls or 0 }
			end
		end
		table.sort(rows, function(a, b) return a.ms > b.ms end)
		MelloUI:Print("CPU since login or the last reset: %.0f ms in MelloUI in total.", total)
		for i, row in ipairs(rows) do
			if i > 25 or row.ms < 0.5 then
				break
			end
			print(string.format("   %8.1f ms  %6d calls  %s: %s", row.ms, row.calls, row.module, row.label))
		end
		print("   Hooks and handlers not listed used less than half a millisecond. /mello cpu reset clears the counters.")
	elseif cmd == "secrets" then
		MelloUI:SecretProbe()
	elseif cmd == "auras" then
		MelloUI:AuraProbe()
	elseif cmd == "preload" then
		-- Preload Artwork (UI Modifications): how many files are held, and how
		-- many the client says are in memory already
		local Kit = MelloUI.Kit
		local held, loaded = 0, nil
		if Kit and Kit.PreloadStatus then
			held, loaded = Kit:PreloadStatus()
		end
		if held == 0 then
			MelloUI:Print("Preload Artwork: nothing held (the option, the reskin or UI Modifications is off).")
		elseif loaded then
			MelloUI:Print("Preload Artwork: %d files held, %d of them loaded.", held, loaded)
		else
			MelloUI:Print("Preload Artwork: %d files held (this client does not report which are loaded).", held)
		end
	elseif cmd == "dump" then
		-- printed through MelloUI:Print (kept for the copy window), nested
		-- tables written out one level deep (the window positions), and the
		-- copy window opened at the end (user, 2026-09-21)
		MelloUI:ClearLog()
		local function Value(v)
			if type(v) == "table" then
				local parts, keys = {}, {}
				for k in pairs(v) do keys[#keys + 1] = tostring(k) end
				table.sort(keys)
				for _, k in ipairs(keys) do
					local inner = v[k]
					if type(inner) == "table" then
						local fields = {}
						for ik, iv in pairs(inner) do fields[#fields + 1] = tostring(ik) .. "=" .. tostring(iv) end
						table.sort(fields)
						inner = "{ " .. table.concat(fields, ", ") .. " }"
					end
					parts[#parts + 1] = k .. " = " .. tostring(inner)
				end
				return #parts > 0 and ("{ " .. table.concat(parts, "; ") .. " }") or "{}"
			end
			return tostring(v)
		end
		local function DumpModule(name, module)
			local db = MelloUI:GetModuleDB(name)
			local state = MelloUI:IsModuleEnabled(name) and "on" or "off"
			MelloUI:Print("%s (%s)", module.title, state)
			local keys = {}
			for k in pairs(db) do keys[#keys + 1] = tostring(k) end
			table.sort(keys)
			for _, k in ipairs(keys) do
				MelloUI:Print("   %s = %s", k, Value(db[k]))
			end
		end
		local target = ModuleByName(rest)
		if target then
			DumpModule(target.name, target)
		else
			for name, module in MelloUI:IterateModules() do
				DumpModule(name, module)
			end
		end
		MelloUI:ShowLog("dump " .. tostring(rest or ""))
	elseif cmd == "status" then
		local green, red, yellow = "|cff40ff40", "|cffff4040", "|cffffff00"
		MelloUI:Print("Status (v%s):", tostring(MelloUI.version))
		if not MelloUI.dbIsTemporary then
			print(string.format("   Saved variables: %sloaded by the client|r (at %s)", green, tostring(MelloUI.savedVariablesStage or "?")))
		else
			print(string.format("   Saved variables: %snot loaded by the client|r (still waiting; the file is only written, never read back)", red))
		end
		local source
		if MelloUI.restoredFromBackup then
			source = string.format("%smacro backup|r (%d values restored at %s)", yellow,
				tonumber(MelloUI.backupRestoredCount) or 0, tostring(MelloUI.backupRestoredStage or "?"))
		elseif not MelloUI.dbIsTemporary then
			source = green .. "saved variables|r"
		else
			source = red .. "defaults|r (nothing to restore from)"
		end
		print("   Settings in use come from: " .. source)
		if type(MelloUI.GetBackupStatus) == "function" then
			local b = MelloUI:GetBackupStatus()
			if b.paused then
				print("   Macro backup: " .. yellow .. "PAUSED in Core/Backup.lua (nothing read or written)|r")
			elseif not b.available then
				print("   Macro backup: " .. red .. "macro API not available|r")
			else
				local when = b.lastWrite and date("%H:%M:%S", b.lastWrite) or "not yet this session"
				print(string.format("   Macro backup: %d macro(s), %d of %d characters, %s", b.chunks, b.length, b.capacity or 0,
					b.inSync and (green .. "in sync with current settings|r") or (yellow .. "differs from current settings|r")))
				print(string.format("   Last write: %s%s%s", when,
					b.lastReason and (" (" .. tostring(b.lastReason) .. ")") or "",
					b.pending and ", write scheduled" or (b.deferredForCombat and ", waiting for combat to end" or "")))
				if b.lastError then
					print("   Last error: " .. red .. tostring(b.lastError) .. "|r")
				end
			end
		end
	elseif cmd == "tutorial" or cmd == "tour" then
		if MelloUI.Tutorial then
			MelloUI.Tutorial:Start()
		end
	elseif cmd == "help" then
		MelloUI:Print("Commands:")
		for _, c in ipairs(COMMANDS) do
			print(string.format("   %-26s %s", c[1], c[2]))
		end
		print("   /mello dump [m]            print the stored settings of all modules or one module")
		print("   /mello cpu                 CPU time per handler (needs scriptProfile)")
		print("   /mello preload             how much of the artwork is preloaded")
		print("   /mello secrets             which secret-value tools this client has, and what a secret allows")
		print("   /mello auras               what this client's aura container offers (for MelloUI's own aura rows)")
	elseif cmd ~= "" and not ModuleByName(cmd) and cmd ~= "profiles" then
		MelloUI:Print("Unknown command or module '%s'. /mello help lists the commands, /mello list the modules.", cmd)
	else
		MelloUI:OpenConfig(cmd ~= "" and cmd or nil)
	end
end
