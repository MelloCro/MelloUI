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
local PAD = 22
local ROW_HEIGHT = 34
local SLIDER_ROW_HEIGHT = 40

-- Palette
local C = {
	bg      = { 0.14, 0.14, 0.15 },
	band    = { 0.09, 0.09, 0.10 },
	panel   = { 0.17, 0.17, 0.18 },
	stripe  = { 0.19, 0.19, 0.20 },
	line    = { 0.30, 0.29, 0.27 },
	hover   = { 0.74, 0.63, 0.38 },
	accent  = { 0.74, 0.63, 0.38 },
	accent2 = { 0.47, 0.41, 0.26 },
	text    = { 0.88, 0.87, 0.83 },
	dim     = { 0.59, 0.58, 0.56 },
	on      = { 0.33, 0.55, 0.50 },
	off     = { 0.27, 0.27, 0.29 },
	knob    = { 0.87, 0.84, 0.77 },
}

local MODULE_META = {
	DarkMode     = { icon = ICON .. "Spell_Shadow_Twilight",       flavour = "Dim the gold and the glare. The interface steps back, the world steps forward." },
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
	Route        = { icon = ICON .. "Ability_Tracking",            flavour = "A trail of gems from here to there, along the roads you have walked before." },
	Services     = { icon = ICON .. "Ability_Repair",              flavour = "Repair, mailbox, innkeeper, bank... the nearest one is a click under the minimap." },
}
local HOME_FLAVOUR = "Module based interface tweaks for World of Warcraft: Forever."
local PROFILES_META = { icon = ICON .. "INV_Scroll_06", title = "Profiles",
	flavour = "Your whole setup under one name. Save it, load it, or make it the default for a fresh install." }
local DEFAULT_ICON = ICON .. "INV_Misc_QuestionMark"

-- Shown on the Home page under "What's new".
local CHANGELOG = {
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
	GameTooltip:SetText(title, 1, 1, 1)
	if body and body ~= "" then
		GameTooltip:AddLine(body, C.dim[1], C.dim[2], C.dim[3], true)
	end
	GameTooltip:Show()
end

-- A framed icon: the client's action button bevel around a rounded icon.
-- Grey at rest, gold when selected, white while hovered.
local FRAME_GREY = { 0.72, 0.72, 0.74 }
local FRAME_GOLD = { 1.0, 0.84, 0.36 }
local function IconBox(parent, size, texture)
	local box = CreateFrame("Frame", nil, parent)
	box:SetSize(size, size)
	box.icon = box:CreateTexture(nil, "ARTWORK")
	box.icon:SetAllPoints()
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
		mask:SetSize(info.width * k, info.height * k)
		mask:SetPoint("CENTER", box.icon, "CENTER")
	else
		mask:SetAllPoints(box.icon)
	end
	box.icon:AddMaskTexture(mask)
	box.selected = false
	function box:SetSelected(selected)
		self.selected = selected and true or false
		local c = self.selected and FRAME_GOLD or FRAME_GREY
		self.frame:SetVertexColor(c[1], c[2], c[3], 1)
	end
	function box:SetHovered(hovered)
		if hovered then
			self.frame:SetVertexColor(1, 1, 1, 1)
		else
			self:SetSelected(self.selected)
		end
	end
	function box:SetOn(on)
		self.icon:SetDesaturated(not on)
		self.icon:SetAlpha(on and 1 or 0.45)
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
	return cb
end

-- Smooth hover glow: a bronze wash that fades in while the mouse is over the
-- frame and out again after it leaves. Runs an OnUpdate only while animating.
local HOVER_SPEED = 6   -- full fade in about 1/6 s
local function AttachHover(frame, alphaMax)
	alphaMax = alphaMax or 0.10
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
			dd.Text:SetTextColor(1, 0.82, 0)
		end
		Gold()
		if dd.OnButtonStateChanged then
			hooksecurefunc(dd, "OnButtonStateChanged", Gold)
		end
		dd:HookScript("OnEnter", function() dd.Text:SetTextColor(1, 1, 1) end)
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
	return slider
end

--------------------------------------------------------------------------------
-- Sections and rows
--
-- A page owns sections; a section is a frame holding rows. Sections map to
-- tabs when there is more than one.
--------------------------------------------------------------------------------

local RefreshStrip, SelectPage  -- forward declarations

local function NewSection(page, name)
	local sec = CreateFrame("Frame", nil, page)
	sec.name = name
	sec.y = 0
	sec.rows = 0
	sec.refreshers = {}
	sec:SetWidth(page.width - PAD * 2)
	sec:SetHeight(10)
	sec:Hide()
	function sec:Refresh()
		for _, fn in ipairs(self.refreshers) do
			fn()
		end
	end
	function sec:Finish()
		self:SetHeight(math.max(self.y, 10))
	end
	page.sections[#page.sections + 1] = sec
	return sec
end

-- A ledger row: stripe, label, optional grey hint, tooltip with the description.
local function Row(sec, height, label, hint, desc)
	local row = CreateFrame("Frame", nil, sec)
	row:SetHeight(height)
	row:SetPoint("TOPLEFT", 0, -sec.y)
	row:SetPoint("RIGHT", sec, "RIGHT", 0, 0)
	local line = Solid(row, "BORDER", C.line, 0.6)
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	row:EnableMouse(true)
	AttachHover(row)
	row.label = Text(row, "GameFontHighlight", label, C.text)
	row.label:SetPoint("LEFT", 14, 0)
	row.label:SetWordWrap(false)
	if hint and hint ~= "" then
		row.hint = Text(row, "GameFontHighlightSmall", hint, C.dim)
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
	local row = Row(sec, ROW_HEIGHT, opt.name, opt.hint, opt.desc)
	local switch = CreateSwitch(row, function(value)
		MelloUI:NotifySettingChanged(module.name, opt.key, value)
	end)
	switch:SetPoint("RIGHT", -12, 0)
	switch:HookScript("OnEnter", function() if opt.desc then ShowTooltip(row, opt.name, opt.desc) end end)
	switch:HookScript("OnLeave", function() GameTooltip:Hide() end)
	sec.refreshers[#sec.refreshers + 1] = function()
		switch:SetValue(db[opt.key] and true or false, true)
	end
end

local function AddSlider(sec, module, db, opt)
	local row = Row(sec, SLIDER_ROW_HEIGHT, opt.name, opt.hint, opt.desc)
	local slider = CreateSlider(row, 200, db, module, opt)
	slider:SetPoint("RIGHT", -70, 0)
	sec.refreshers[#sec.refreshers + 1] = function() slider:Refresh() end
end

local function AddDropdown(sec, module, db, opt)
	local row = Row(sec, ROW_HEIGHT, opt.name, opt.hint, opt.desc)
	local dd = CreateDropdown(row, 200, db, module, opt)
	dd:SetPoint("RIGHT", -14, 0)
	sec.refreshers[#sec.refreshers + 1] = function() dd:Refresh() end
end

local builders = {
	toggle = AddToggle,
	slider = AddSlider,
	dropdown = AddDropdown,
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
			local line = Solid(self, "ARTWORK", C.accent2, 1)
			line:SetHeight(1)
			line:SetPoint("TOPLEFT", PAD, -y)
			line:SetPoint("RIGHT", self, "RIGHT", -PAD, 0)
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

	local rightWidth = module and 200 or 0
	local flavourFS = Text(page, "GameFontHighlightSmall", nil, C.dim)
	flavourFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 2, -6)
	flavourFS:SetWidth(page.width - PAD * 2 - 64 - rightWidth)
	flavourFS:SetWordWrap(true)
	flavourFS:SetText(flavour)
	page.flavour = flavourFS

	if module then
		local lbl = Text(page, "GameFontNormal", "Enabled", C.text)
		local switch = CreateSwitch(page, function(value)
			MelloUI:SetModuleEnabled(module.name, value)
			MelloUI:RefreshConfig()
		end)
		switch:SetPoint("TOPRIGHT", page, "TOPRIGHT", -PAD, -PAD)
		lbl:SetPoint("RIGHT", switch, "LEFT", -4, 0)
		local defaults = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
		defaults:SetSize(90, 22)
		defaults:SetPoint("TOPRIGHT", switch, "BOTTOMRIGHT", 0, -10)
		defaults:SetText("Defaults")
		defaults:SetScript("OnClick", function()
			for key, value in pairs(module.defaults) do
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
	end

	page.headerHeight = PAD + math.max(50, 26 + 6 + WrappedHeight(flavourFS, 14)) + 18
end

local function BuildModulePage(module, width)
	local page = NewPage(module.name, width)
	local icon, flavour = Meta(module)
	BuildPageHeader(page, icon, module.title, flavour, module)
	local db = MelloUI:GetModuleDB(module.name)
	local sec = nil
	for _, opt in ipairs(module.options) do
		if opt.type == "header" then
			sec = NewSection(page, opt.name)
		else
			if not sec then
				sec = NewSection(page, "General")
			end
			local builder = builders[opt.type]
			if builder then
				if db[opt.key] == nil then
					db[opt.key] = module.defaults[opt.key]
				end
				builder(sec, module, db, opt)
			else
				MelloUI:Print("Unknown option type '%s' in module %s", tostring(opt.type), module.name)
			end
		end
	end
	if #page.sections == 0 then
		sec = NewSection(page, "Options")
		local fs = Text(sec, "GameFontDisable", "This module has no options. The switch above is all there is to it.")
		fs:SetPoint("TOPLEFT", 14, -8)
		sec.y = 30
	end
	page:Finish()
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
	for name in MelloUI:IterateModules() do
		total = total + 1
		if MelloUI:IsModuleEnabled(name) then
			on = on + 1
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
	local status = Text(page, "GameFontHighlightSmall", nil, C.dim)
	status:SetPoint("TOPLEFT", page.flavour, "BOTTOMLEFT", 0, -4)
	page.refreshers[#page.refreshers + 1] = function() status:SetText(StatusLine()) end
	page.headerHeight = page.headerHeight + 16

	-- Modules: a tile per module.
	local tiles = NewSection(page, "Modules")
	local columns, gap = 4, 10
	local tileWidth = (tiles:GetWidth() - gap * (columns - 1)) / columns
	local tileHeight = 92
	local i = 0
	for _, module in MelloUI:IterateModules() do
		local col, row = i % columns, math.floor(i / columns)
		local tile = CreateFrame("Frame", nil, tiles, "BackdropTemplate")
		tile:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		tile:SetBackdropColor(0.07, 0.07, 0.08, 0.92)
		tile:SetBackdropBorderColor(0.55, 0.47, 0.30, 1)
		tile:SetSize(tileWidth, tileHeight)
		tile:SetPoint("TOPLEFT", col * (tileWidth + gap), -(row * (tileHeight + gap)))
		local icon, flavour = Meta(module)
		local box = IconBox(tile, 42, icon)
		box:SetPoint("TOPLEFT", 12, -12)
		local title = Text(tile, "GameFontNormal", module.title, C.text)
		title:SetPoint("TOPLEFT", box, "TOPRIGHT", 12, -2)
		title:SetPoint("RIGHT", tile, "RIGHT", -8, 0)
		title:SetWordWrap(false)
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
			self:SetBackdropBorderColor(1, 0.82, 0, 1)
			ShowTooltip(self, module.title, flavour)
		end)
		tile:HookScript("OnLeave", function(self)
			self:SetBackdropBorderColor(0.55, 0.47, 0.30, 1)
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

	-- Help: commands and links.
	local help = NewSection(page, "Help")
	y = 6
	local head = Text(help, "GameFontNormal", "Slash commands", C.accent)
	head:SetPoint("TOPLEFT", 4, -y)
	y = y + 24
	for _, cmd in ipairs(COMMANDS) do
		local c = Text(help, "GameFontHighlight", cmd[1], C.text)
		c:SetPoint("TOPLEFT", 10, -y)
		local what = Text(help, "GameFontHighlightSmall", cmd[2], C.dim)
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
	local note = Text(help, "GameFontHighlightSmall", nil, C.dim)
	note:SetPoint("TOPLEFT", 4, -y)
	note:SetWidth(help:GetWidth() - 8)
	note:SetWordWrap(true)
	note:SetText("Settings are mirrored into account macros because this client does not read its saved variables back; /mello status shows the state of that backup. The voice pack (MelloUI_VoiceOverData) is a separate download from the releases page and goes next to the MelloUI folder.")
	y = y + WrappedHeight(note, 14) + 8
	help.y = y

	page:Finish()
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
	local active = db.activeProfile and ("|cffffd200" .. db.activeProfile .. "|r") or "|cff888888none|r"
	local default = db.defaultProfile and ("|cffffd200" .. db.defaultProfile .. "|r") or "|cff888888none|r"
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
			row.baked = Text(row, "GameFontHighlightSmall", nil, C.dim)
			row.baked:SetPoint("LEFT", row.delete, "RIGHT", 10, 0)
			sec.rowFrames[i] = row
		end
		row.name:SetText(name)
		local isDefault = db.defaultProfile == name
		row.default:SetText(isDefault and "Default  |cff40ff40*|r" or "Set default")
		row.baked:SetText(MelloUI:IsProfileBaked(name) and "baked" or "not baked yet")
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

	local desc = Text(sec, "GameFontHighlightSmall", nil, C.dim)
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
	btn:SetSize(40, 40)
	btn.box = IconBox(btn, 38, icon)
	btn.box:SetPoint("TOP", 0, 0)
	btn.box:EnableMouse(false)
	btn.label = Text(btn, "GameFontHighlightSmall", title, C.accent)
	btn.label:SetPoint("TOP", btn.box, "BOTTOM", 0, -4)
	btn.label:SetJustifyH("CENTER")
	btn.label:Hide()
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
		GameTooltip:Hide()
	end)
	stripButtons[name] = btn
	return btn
end

local function CreateWindow()
	if window then
		return
	end
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
	bg:SetVertexColor(0.40, 0.40, 0.42)
	local tint = Solid(window, "BACKGROUND", C.bg, 0.45)
	tint:SetPoint("TOPLEFT", 6, -6)
	tint:SetPoint("BOTTOMRIGHT", -6, 6)

	-- Metal frame from the client's own nine-slice art, or a plain border.
	local framed = false
	if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
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
		window:SetBackdropBorderColor(0.35, 0.35, 0.36, 1)
	end
	local innerLine = Box(window, C.bg, C.accent2, 0)
	innerLine:SetPoint("TOPLEFT", 7, -7)
	innerLine:SetPoint("BOTTOMRIGHT", -7, 7)
	innerLine:EnableMouse(false)

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
	band:EnableMouse(true)
	band:RegisterForDrag("LeftButton")
	band:SetScript("OnDragStart", function() window:StartMoving() end)
	band:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
	window.band = band

	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -10, -12)
	close:SetScript("OnClick", function() window:Hide() end)

	-- Icon strip.
	local strip = CreateFrame("Frame", nil, window)
	strip:SetPoint("TOPLEFT", band, "BOTTOMLEFT", 0, 0)
	strip:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT", 0, 0)
	strip:SetHeight(STRIP_HEIGHT)
	local stripBg = Solid(strip, "BACKGROUND", C.band, 0.8)
	stripBg:SetAllPoints()
	local stripLine = Solid(strip, "BORDER", C.accent2, 1)
	stripLine:SetHeight(1)
	stripLine:SetPoint("BOTTOMLEFT")
	stripLine:SetPoint("BOTTOMRIGHT")
	window.strip = strip

	local entries = { { "Home", LOGO, "Home", HOME_FLAVOUR } }
	for _, module in MelloUI:IterateModules() do
		local icon, flavour = Meta(module)
		entries[#entries + 1] = { module.name, icon, module.title, flavour }
	end
	entries[#entries + 1] = { "Profiles", PROFILES_META.icon, "Profiles", PROFILES_META.flavour }
	local spacing = (WINDOW_WIDTH - 16 - PAD * 2) / #entries
	for i, e in ipairs(entries) do
		local btn = StripButton(e[1], e[2], e[3], e[4])
		btn:SetPoint("TOP", strip, "TOPLEFT", PAD + spacing * (i - 1) + spacing / 2, -8)
		if i == 2 or i == #entries then
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

	window:SetScript("OnShow", function()
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
		btn.label:SetShown(selected)
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

function MelloUI:CloseConfig()
	if window then
		window:Hide()
	end
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

SLASH_MELLOUI1 = "/mello"
SLASH_MELLOUI2 = "/melloui"
SlashCmdList.MELLOUI = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, rest = msg:match("^(%S+)%s*(.-)$")

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
		elseif sub == "list" or sub == nil then
			local names = ProfileNames()
			MelloUI:Print("Profiles (%d). Active: %s, default: %s.", #names, tostring(MelloUI.db.activeProfile or "none"), tostring(MelloUI.db.defaultProfile or "none"))
			for _, n in ipairs(names) do
				print("   " .. n .. (MelloUI:IsProfileBaked(n) and "" or "  (not baked yet)"))
			end
		else
			MelloUI:Print("/mello profile save <name> | load <name> | delete <name> | default <name|none> | list")
		end
		MelloUI:RefreshConfig()
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
	elseif cmd == "dump" then
		local function DumpModule(name, module)
			local db = MelloUI:GetModuleDB(name)
			local state = MelloUI:IsModuleEnabled(name) and "|cff40ff40on|r" or "|cffff4040off|r"
			print(string.format("|cff9b8cff%s|r (%s)", module.title, state))
			local keys = {}
			for k in pairs(db) do keys[#keys + 1] = tostring(k) end
			table.sort(keys)
			for _, k in ipairs(keys) do
				print(string.format("   %s = %s", k, tostring(db[k])))
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
			if not b.available then
				print("   Macro backup: " .. red .. "macro API not available|r")
			else
				local when = b.lastWrite and date("%H:%M:%S", b.lastWrite) or "not yet this session"
				print(string.format("   Macro backup: %d macro(s), %d characters, %s", b.chunks, b.length,
					b.inSync and (green .. "in sync with current settings|r") or (yellow .. "differs from current settings|r")))
				print(string.format("   Last write: %s%s%s", when,
					b.lastReason and (" (" .. tostring(b.lastReason) .. ")") or "",
					b.pending and ", write scheduled" or (b.deferredForCombat and ", waiting for combat to end" or "")))
				if b.lastError then
					print("   Last error: " .. red .. tostring(b.lastError) .. "|r")
				end
			end
		end
	elseif cmd == "help" then
		MelloUI:Print("Commands:")
		for _, c in ipairs(COMMANDS) do
			print(string.format("   %-26s %s", c[1], c[2]))
		end
		print("   /mello dump [m]            print the stored settings of all modules or one module")
		print("   /mello cpu                 CPU time per handler (needs scriptProfile)")
	else
		MelloUI:OpenConfig(cmd ~= "" and cmd or nil)
	end
end
