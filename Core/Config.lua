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
-- A module's tile shows the `icon` (texture path) and `flavour` (one line)
-- it gives RegisterModule (the registry: audit, 2026-09-24, rank 4 -- they
-- were a hand list here), else a question mark and its description.
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Config")
local hooksecurefunc = Perf.hooksecurefunc

local TEXTURE_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Textures\\"
local LOGO = TEXTURE_PATH .. "LogoIcon.tga"   -- the round emblem of the logo (user, 2026-09-24: new logo, "round_inner")
local LOGO_FULL = TEXTURE_PATH .. "LogoFull.tga"   -- the whole logo, for the home page's header
local ICON = "Interface\\Icons\\"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local ROCK = "Interface\\FrameGeneral\\UI-Background-Rock"
local ICON_FRAME = "UI-HUD-ActionBar-IconFrame"        -- the action button bevel
local ICON_MASK = "UI-HUD-ActionBar-IconFrame-Mask"    -- its rounded corners

-- The soft clicks ("page", "tab", "check_on", "check_off"): MelloUI:PlayUISound,
-- in Core.lua since the other windows share them (audit, 2026-09-24)
local function Click(kind)
	MelloUI:PlayUISound(kind)
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

local HOME_FLAVOUR = "Module based interface tweaks for World of Warcraft: Forever."
local PROFILES_META = { icon = ICON .. "INV_Scroll_06", title = "Profiles",
	flavour = "Your whole setup under one name. Save it, load it, or make it the default for a fresh install." }
local DEFAULT_ICON = ICON .. "INV_Misc_QuestionMark"

-- Shown on the Home page under "What's new". A short list in a player's
-- words; CHANGELOG.md has the whole release.
local CHANGELOG = {
	{ version = "0.13.7", lines = {
		"Lighter artwork: the textures now take 28 MB instead of 96 MB, and a look loads about 12.6 MB during the loading screen instead of 45.8 MB, so loading screens and first opens are quicker.",
		"A new logo: the MelloUI emblem in the AddOn list and on this window, the whole logo on its home page.",
		"No more stalls opening this window, the friends window, the group finder, parchment windows or a flight master. The bags and the spell book do less on their first open, and rarely used windows are dressed then, for a faster login.",
		"Route's road data now lives in a second folder, MelloUI_Companion, loaded only when you route somewhere: copy both folders into AddOns and restart the game once. /route status says whether it is loaded.",
		"Less memory and smoother play: hidden parts stay quiet, and the Services bar, custom sounds, cooldown numbers, tooltips, the Quest List and the bags rest while nothing changes. /melloperf shows what MelloUI costs.",
		"Text on parchment no longer flickers white when something passes behind a window, and tooltips can have a parchment sheet too, their lines in dark ink.",
		"The rest of the game's windows in the painted look, each with its own switch (UI Modifications, Windows): macros, Edit Mode, the AddOn list, quest dialogs, merchants, the auction house, mail, the bank, popup dialogs and more.",
		"Easier on the eyes: text-heavy areas lie on a dark panel, every window's title sits on its plate, fewer red gems, and one colour palette with Kit Colours (Warm iron, Bronze, Original) for the whole interface.",
		"A simpler configurator: switches and sliders on eight tabs, and Dynamic UI Modification as the one place for the look: borders, backgrounds, parchment sheets and the minimap's shape.",
		"Also new: smooth scrolling in the chat and here, eleven fonts and six Font Styles, Names In Chat, a square minimap merged with the Services bar, and routes to another continent by boat or zeppelin.",
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
-- The commands a player uses. The dump and diagnostic commands for tuning
-- the addon stay out of this list (/mello help prints a few of them below it).
local COMMANDS = {
	{ "/mello", "open or close this window" },
	{ "/mello <module>", "open a module's page" },
	{ "/mello list", "modules and their state" },
	{ "/mello enable <module>", "turn a module on" },
	{ "/mello disable <module>", "turn a module off" },
	{ "/mello profile ...", "save, load, share or delete profiles, set the default" },
	{ "/mello status", "where your settings came from, and their backup" },
	{ "/mello layout apply", "use the Edit Mode layout the reskin is made for" },
	{ "/mello tutorial", "the guided tour of this window" },
	{ "/melloperf", "what MelloUI costs: its time per frame, its slowest frames" },
	{ "/melloperf record", "measure while you play (30 s, or /melloperf record 60)" },
	{ "/melloperf report", "the last recording's report again, to copy" },
	{ "/melloperf load", "how long each part took to load, and its memory" },
	{ "/mellolog", "MelloUI's recent messages in a window to copy" },
	{ "/sfx", "Custom Sounds: its state and the slowest sounds" },
	{ "/sfx play <name>", "hear one custom sound (/sfx list names them)" },
	{ "/vo stop | pause | skip", "stop, pause or skip the voice that is reading" },
	{ "/vo read", "read the quest selected in the quest log aloud" },
	{ "/vo test", "a test line in the targeted NPC's voice" },
	{ "/vo packs", "which voice packs are installed" },
	{ "/vo reset", "the Voice Over window back to its place" },
	{ "/route status", "the route, its road data and your flight points" },
	{ "/route clear", "stop the route" },
	{ "/route arrow reset", "the direction arrow back to the top of the screen" },
	{ "/services", "the list of the nearest services" },
	{ "/services <service>", "route to the nearest one, e.g. /services repair" },
}

local function Meta(module)
	return module.icon or DEFAULT_ICON, module.flavour or module.desc or ""
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

-- The handlers the pages' rows and controls share (user, 2026-09-24: a page
-- of two hundred rows made a dozen functions per row, each wrapped and
-- named by the profiler as it was set): one function each, wrapped once
-- (Perf.Shared), reading what it shows from the frame it runs on.
local Shared = Perf.Shared or function(_, fn) return fn end

local TipLeave = Shared("OnLeave on the configurator's rows and controls", function()
	GameTooltip:Hide()
end, "script")
-- a row's tooltip: its label and description (`tipTitle`, `tipBody`)
local RowTipEnter = Shared("OnEnter on the configurator's rows (tooltip)", function(self)
	ShowTooltip(self, self.tipTitle, self.tipBody)
end, "script")
-- a row's switch or button: the row's tooltip, on the row, when the option
-- has a description
local ControlTipEnter = Shared("OnEnter on the configurator's row controls", function(self)
	if self.tipBody then
		ShowTooltip(self.tipOwner, self.tipTitle, self.tipBody)
	end
end, "script")

-- A framed icon: the client's action button bevel around a rounded icon.
-- Grey at rest, gold when selected, white while hovered.
local FRAME_GREY = PAL.mutedText
local FRAME_GOLD = PAL.selectedTrim
--------------------------------------------------------------------------------
-- The painted kit on the configurator itself (user, 2026-09-21; picks CT2 SI1
-- from kit_raw/config_catalog.png): its look switch is Kit:IsOn('config')
-- (the UI Modifications reskin), asked again at every show (audit,
-- 2026-09-24, rank 1: it was asked once, when the window was made, so a
-- change showed only after /reload). The look is built into the window, so
-- each look has a window of its own, made on its first show in that look
-- and shown again after (CreateWindow). Every piece goes through
-- Kit:Replace with the fixed looks' keys: the outer double rail, the title
-- plate on it, the page stone, the header plate under the icon strip, R1
-- rims on the icons, TB6 tabs, L1 boxes around the sections, plate rows
-- with a hover, the kit's check boxes, red buttons, D1 dropdowns, the kit
-- slider, the kit's title face on the titles.
--------------------------------------------------------------------------------

local KIT = nil
local kitSkin = { reps = {}, followers = {} }

-- (the Kit looked up when asked: this file loads before Kit.lua)
local function KitWanted()
	local kit = MelloUI.Kit
	if kit and kit.Replace and kit.IsOn and kit:IsOn("config") then
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
	if texture ~= LOGO and texture ~= LOGO_FULL then
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
	-- for an important module; under Reduce Motion a still glow at full
	-- strength, the pulse's end (Anim:PlayGroup; audit, 2026-09-24)
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
			MelloUI.Anim:PlayGroup(anim)
			self.glow, self.glowAnim = glow, anim
		elseif self.glow then
			self.glow:SetShown(on and true or false)
			if on then
				MelloUI.Anim:PlayGroup(self.glowAnim)
			else
				MelloUI.Anim:StopGroup(self.glowAnim)   -- not played again when Reduce Motion goes off
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
local function SwitchSetValue(self, on, silent)
	on = on and true or false
	-- a refresh that changes nothing leaves the box alone (the kit's check
	-- box redraws on every SetChecked; a tab's refresh set every box on it
	-- again -- user, 2026-09-24)
	if silent and on == self.value and (self:GetChecked() and true or false) == on then
		return
	end
	self.value = on
	self:SetChecked(on)
	if not silent and self.melloOnChange then
		self.melloOnChange(on)
	end
end
local SwitchClick = Shared("OnClick on the configurator's switches", function(self)
	local value = self:GetChecked() and true or false
	Click(value and "check_on" or "check_off")
	self:SetValue(value)
end, "script")

local function CreateSwitch(parent, onChange)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(26, 26)
	if cb.Text then
		cb.Text:Hide()
	end
	cb.value = false
	cb.melloOnChange = onChange
	cb.SetValue = SwitchSetValue
	Perf.SetScript(cb, "OnClick", SwitchClick)
	if KIT and KIT.SkinCheckButton then
		KIT:SkinCheckButton(cb, KitReplace, "UI-CheckBox-Up")
	end
	return cb
end

-- Smooth hover glow: a bronze wash that fades in while the mouse is over the
-- frame and out again after it leaves. Runs an OnUpdate only while animating.
-- Under Reduce Motion it is there at once and gone on the frame the mouse
-- leaves, its OnUpdate with it (audit, 2026-09-24: it faded regardless).
local HOVER_SPEED = 6   -- full fade in about 1/6 s
local HoverEnter = Shared("OnEnter on the configurator's hover washes", function(self)
	Perf.SetScript(self, "OnUpdate", self.hoverStep)
	if MelloUI.Anim.reduceMotion then
		self.hoverStep(self, 0)
	end
end, "script")
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
		local move = MelloUI.Anim.reduceMotion and 1 or dt * HOVER_SPEED
		if level < target then
			level = math.min(1, level + move)
		elseif level > target then
			level = math.max(0, level - move)
		end
		glow:SetAlpha(level * alphaMax)
		edge:SetAlpha(level)
		if level == 0 then
			Perf.SetScript(self, "OnUpdate", nil)
		end
	end
	frame.hoverStep = Step
	Perf.HookScript(frame, "OnEnter", HoverEnter)
	frame.hoverGlow = glow
end

-- the dropdown's text: gold at rest, the text colour under the mouse
local DropdownGold = Shared("OnButtonStateChanged / OnLeave on the configurator's dropdowns", function(self)
	Colour(self.Text, C.accent)
end, "hook")
local DropdownLit = Shared("OnEnter on the configurator's dropdowns", function(self)
	Colour(self.Text, C.text)
end, "script")

-- A dropdown's list as it stands: its length and its last entry (a list
-- filled again makes new entries, so either differs)
local function ListMark(values)
	local count = values and #values or 0
	return count, count > 0 and values[count] or nil
end

-- The text the box shows for `value` (nil when the list has no such entry:
-- the box then shows its default text, and the menu is made again on every
-- refresh, as before)
local function ChoiceLabel(values, value)
	if values then
		for i = 1, #values do
			local entry = values[i]
			if entry.value == value then
				return entry.label or tostring(entry.value)
			end
		end
	end
	return nil
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
		DropdownGold(dd)
		if dd.OnButtonStateChanged then
			hooksecurefunc(dd, "OnButtonStateChanged", DropdownGold)
		end
		Perf.HookScript(dd, "OnEnter", DropdownLit)
		Perf.HookScript(dd, "OnLeave", DropdownGold)
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
	-- the menu is made again only when it is out of date (user, 2026-09-24:
	-- a tab's refresh made every dropdown's menu again, the font lists'
	-- dozens of entries each time -- 19 ms and a heap of garbage per click on
	-- the Text tab): the box not naming the setting's choice, or the list
	-- filled again since the menu was made (the Voice Over voices, listed
	-- once the game has them, in the same table: the box must then name the
	-- chosen voice and the menu hold them all)
	dd.menuCount, dd.menuLast = ListMark(opt.values)
	function dd:Refresh()
		local values = opt.values
		local count, last = ListMark(values)
		if count == self.menuCount and last == self.menuLast then
			local label = ChoiceLabel(values, db[opt.key])
			local text = self.Text
			if label and text and text:GetText() == label then
				return
			end
		end
		self.menuCount, self.menuLast = count, last
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

-- L1: the single rail with the list-box stone around a section. Made with
-- the section's first rows (a tab not open yet costs nothing until its rows
-- are made: user, 2026-09-24), or at once for a section made whole
local function SectionBox(sec)
	if sec.needsBox then
		sec.needsBox = nil
		KitReplace(KitAnchor(sec), { as = "Professions-background-summarylist", rect = sec, parent = sec, level = -1 })
		-- depth (user, 2026-09-24: "everything is just too brown ... add the
		-- checkbox section a darker tone from our color palette"): the L1
		-- box lays the palette's inner panel over its stone itself (its
		-- rule's `dim`, WINDOW-RULES 2e), the rows on that darker ground
	end
end

local function NewSection(page, name)
	local sec = CreateFrame("Frame", nil, page)
	sec.name = name
	sec.page = page
	sec.y = KIT and SEC_INSET or 0
	sec.rows = 0
	sec.refreshers = {}
	sec:SetWidth(page.width - PAD * 2)
	sec:SetHeight(10)
	sec:Hide()
	sec.needsBox = KIT and true or nil   -- (SectionBox)
	function sec:Refresh()
		for _, fn in ipairs(self.refreshers) do
			fn()
		end
	end
	-- (as tall as its rows will be while some are still to be made, when
	-- their heights are known: the scroll bar does not jump as they come)
	function sec:Finish()
		local y = (self.jobs and self.plannedY) or self.y
		self:SetHeight(math.max(y + (KIT and SEC_INSET or 0), 10))
	end
	page.sections[#page.sections + 1] = sec
	return sec
end

--------------------------------------------------------------------------------
-- A page made a little at a time (user, 2026-09-24: "clean up the spikes";
-- the first click on a module tile built its page in 170 ms in one frame):
-- a section's rows are jobs, made in order. The rows that show at once --
-- the open tab down to the bottom of the view -- are made with the page;
-- the rest a few milliseconds a frame after it, the open tab first, then the
-- other tabs in their order; a tab opened or a scroll that reaches rows not
-- made yet makes them there and then, before they are drawn (only those in
-- view when the rows above them are not made either). A section is
-- as tall as its rows will be from the start. Built pages are kept, as
-- before. The frames that make them belong to the window, so nothing is
-- made while it is closed.
--------------------------------------------------------------------------------

local BUILD_BUDGET = 2.5   -- ms of rows a frame after the first (and the one row under way past it)
-- a row's height by its option type (the builders below make them so)
local ROW_HEIGHTS = { toggle = ROW_HEIGHT, slider = SLIDER_ROW_HEIGHT, dropdown = ROW_HEIGHT, button = ROW_HEIGHT, subheader = ROW_HEIGHT - 6 }

local building = {}   -- pages with rows still to make, in the order they were opened
local worker          -- the window's frame whose OnUpdate makes them

-- A job for the section: `run(sec, job)` makes it; `height`, when given,
-- is the row's height (one row; 0: none), added to the section's planned
-- height, and where the row goes is kept with the job: a section whose jobs
-- all have one can make the rows in view before those above them
local function Queue(sec, job, run, height)
	local jobs = sec.jobs
	if not jobs then
		jobs = {}
		sec.jobs, sec.nextJob = jobs, 1
		sec.jobY, sec.jobRow, sec.plannedRows, sec.unsized = {}, {}, sec.rows, nil
	end
	local n = #jobs + 1
	jobs[n] = job
	sec.runJob = run
	if height then
		local y = sec.plannedY or sec.y
		sec.jobY[n], sec.jobRow[n] = y, sec.plannedRows
		sec.plannedY = y + height
		if height > 0 then
			sec.plannedRows = sec.plannedRows + 1
		end
	else
		sec.unsized = true
	end
end

-- The rows in view made out of turn (user, 2026-09-24: a tab opened, or the
-- scroll bar dragged, far down the page before the worker came to it made
-- every row above the view as well -- 24 ms in one click): the jobs whose
-- rows reach into [minY, maxY), each at its own place and zebra band; those
-- above are left to the worker, which steps over the rows made here
local function RunInView(sec, minY, maxY)
	local jobs, ys, rowsAt = sec.jobs, sec.jobY, sec.jobRow
	for n = sec.nextJob, #jobs do
		local top = ys[n]
		if top >= maxY then
			break
		end
		local job = jobs[n]
		if job and (ys[n + 1] or sec.plannedY) > minY then
			jobs[n] = false
			sec.y, sec.rows = top, rowsAt[n]
			sec.runJob(sec, job)
		end
	end
end
local function MakeRowsInView(sec, minY, maxY)
	-- (the section's cursor put back whatever happens: the worker goes on
	-- from it; a scroll set while these rows are made leaves its view in
	-- `viewMin` / `viewMax`, made after them)
	local cursorY, cursorRows = sec.y, sec.rows
	sec.outOfTurn = true
	local ok, err
	repeat
		sec.viewMin, sec.viewMax = nil, nil
		ok, err = pcall(RunInView, sec, minY, maxY)
		minY, maxY = sec.viewMin, sec.viewMax
	until not (ok and minY)
	sec.y, sec.rows = cursorY, cursorRows
	sec.outOfTurn, sec.viewMin, sec.viewMax = nil, nil, nil
	if not ok then
		error(err, 0)
	end
end

-- Make the section's rows, in order: all of them, those above `maxY` (in
-- the section's own units), or as many as fit before `deadline` (a
-- debugprofilestop time; the row under way is finished). With `minY` (the
-- top of the view) and the rows above it not made yet, only the rows in
-- view are made (MakeRowsInView). True once the section is complete.
local function MakeRows(sec, maxY, deadline, minY)
	local jobs = sec.jobs
	if not jobs then
		return true
	end
	if sec.outOfTurn then
		-- (a scroll set while the rows in view are made: its view is made
		-- after them, MakeRowsInView)
		if minY and maxY then
			sec.viewMin, sec.viewMax = minY, maxY
		end
		return false
	end
	SectionBox(sec)
	local page = sec.page
	local refreshers = sec.refreshers
	local first = #refreshers + 1
	local count = #jobs
	if minY and maxY and not sec.unsized and sec.y < minY then
		MakeRowsInView(sec, minY, maxY)
		maxY = sec.y   -- (only the made rows at the cursor stepped over below)
	end
	-- (the cursor is the section's own, read again for every row: a scroll
	-- set while a row is made -- the game's scroll bar answering a new
	-- range -- may make rows itself, or even finish the section)
	while sec.jobs == jobs and sec.nextJob <= count do
		local n = sec.nextJob
		local job = jobs[n]
		if not job then
			-- made out of turn: the cursor steps over its place
			sec.nextJob = n + 1
			sec.y = sec.jobY[n + 1] or sec.plannedY or sec.y
			sec.rows = sec.jobRow[n + 1] or sec.plannedRows or sec.rows
		elseif maxY and sec.y >= maxY then
			break
		else
			jobs[n] = false
			sec.nextJob = n + 1
			sec.runJob(sec, job)
			if deadline and debugprofilestop() >= deadline then
				break
			end
		end
	end
	-- rows made on the open tab take their values before they are drawn
	-- (a tab's own refresh does the rest when it opens)
	if page.current == sec then
		for i = first, #refreshers do
			refreshers[i]()
		end
	end
	if sec.jobs ~= jobs then
		return true
	end
	if sec.nextJob <= count then
		return false
	end
	sec.jobs, sec.nextJob, sec.runJob, sec.jobY, sec.jobRow = nil, nil, nil, nil, nil
	sec:Finish()
	if page.current == sec then
		page:SetHeight(page.headerHeight + sec:GetHeight() + PAD)
	end
	if page.onSectionDone then
		page.onSectionDone(sec)
	end
	return true
end

-- The top and the bottom of the view in a tab's section units: the rows it
-- needs before it is drawn (plus one above and one below), at the scroll it
-- will show at (the game's scroll bar brings the offset down to the end of
-- a tab shorter than the one before)
local function ViewRange(page, sec)
	local scroll = window.scroll
	local height = scroll:GetHeight()
	if not (type(height) == "number" and height > 0) then
		height = WINDOW_HEIGHT
	end
	local offset = 0
	if scroll:GetScrollChild() == page then
		offset = scroll:GetVerticalScroll() or 0
		local most = page.headerHeight + sec:GetHeight() + PAD - height
		if offset > most then
			offset = math.max(0, most)
		end
	end
	local top = offset - page.headerHeight
	return top - ROW_HEIGHT, top + height + ROW_HEIGHT
end

-- The next section to make rows for: the open page's open tab, its other
-- tabs in their order, then the pages opened before it
local function NextSection()
	local page = currentPage and pages[currentPage]
	if page then
		if page.current and page.current.jobs then
			return page.current
		end
		for _, sec in ipairs(page.sections) do
			if sec.jobs then
				return sec
			end
		end
	end
	for _, p in ipairs(building) do
		for _, sec in ipairs(p.sections) do
			if sec.jobs then
				return sec
			end
		end
	end
	return nil
end

local function Work(self)
	local deadline = debugprofilestop() + BUILD_BUDGET
	repeat
		local sec = NextSection()
		if not sec then
			for i = #building, 1, -1 do
				building[i] = nil
			end
			self:Hide()
			return
		end
		MakeRows(sec, nil, deadline)
	until debugprofilestop() >= deadline
end

-- rows still to make: the worker on (it stops by itself when all are made)
local function Kick()
	if worker and not worker:IsShown() and NextSection() then
		worker:Show()
	end
end

-- the kit's hover plate of a row (`hoverPlate`), shown while the mouse is
-- on it (not on a heading: its `hover` is taken away)
local RowPlateEnter = Shared("OnEnter on the configurator's rows (plate)", function(self)
	if self.hover then
		self.hoverPlate:Show()
	end
end, "script")
local RowPlateLeave = Shared("OnLeave on the configurator's rows (plate)", function(self)
	self.hoverPlate:Hide()
end, "script")

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
			row.hover, row.hoverPlate = hover.object, hover.object
			hover.object:Hide()
			Perf.HookScript(row, "OnEnter", RowPlateEnter)
			Perf.HookScript(row, "OnLeave", RowPlateLeave)
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
		row.tipTitle, row.tipBody = label, desc
		Perf.HookScript(row, "OnEnter", RowTipEnter)
		Perf.HookScript(row, "OnLeave", TipLeave)
	end
	sec.y = sec.y + height
	sec.rows = sec.rows + 1
	return row
end

local IMPORTANT_GOLD = { 1, 0.82, 0 }

local function AddToggle(sec, module, db, opt)
	local row = Row(sec, ROW_HEIGHT, opt.name, opt.important and "IMPORTANT" or opt.hint, opt.desc)
	if opt.important then
		Colour(row.label, IMPORTANT_GOLD)
		if row.hint then
			Colour(row.hint, IMPORTANT_GOLD)
		end
	end
	local switch = CreateSwitch(row, function(value)
		MelloUI:NotifySettingChanged(module.name, opt.key, value)
		-- the rows that hang on this switch wake or grey at once
		sec:Refresh()
	end)
	switch:SetPoint("RIGHT", -12, 0)
	switch.tipOwner, switch.tipTitle, switch.tipBody = row, opt.name, opt.desc
	Perf.HookScript(switch, "OnEnter", ControlTipEnter)
	Perf.HookScript(switch, "OnLeave", TipLeave)
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
-- the cover's tooltip: the row's label, and the switch that wakes it (the
-- line per switch made once, not a new string per hover)
local CoverEnter = Shared("OnEnter on the configurator's sleeping rows", function(self)
	local _, why = self.gate()
	local line = nil
	if why then
		local lines = self.gateLines
		if not lines then
			lines = {}
			self.gateLines = lines
		end
		line = lines[why]
		if not line then
			line = "Switch on \"" .. why .. "\" first."
			lines[why] = line
		end
	end
	local row = self.gateRow
	ShowTooltip(self, row.label and row.label:GetText() or "", line)
end, "script")

local function AddGate(sec, row, gate)
	local cover = CreateFrame("Frame", nil, row)
	cover:SetAllPoints(row)
	cover:SetFrameLevel(row:GetFrameLevel() + 30)
	cover:EnableMouse(true)
	cover.gate, cover.gateRow = gate, row
	Perf.SetScript(cover, "OnEnter", CoverEnter)
	Perf.SetScript(cover, "OnLeave", TipLeave)
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
local RowButtonClick = Shared("OnClick on the configurator's row buttons", function(self)
	local opt = self.melloOpt
	if opt.onClick then
		opt.onClick(self.melloModule, self.melloDb)
	end
end, "script")

local function AddButton(sec, module, db, opt)
	local row = Row(sec, ROW_HEIGHT, opt.name, opt.hint, opt.desc)
	local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	button:SetSize(opt.width or 70, 22)
	button:SetPoint("RIGHT", -12, 0)
	button:SetText(opt.text or "Run")
	button.melloOpt, button.melloModule, button.melloDb = opt, module, db
	Perf.SetScript(button, "OnClick", RowButtonClick)
	button.tipOwner, button.tipTitle, button.tipBody = row, opt.name, opt.desc
	Perf.HookScript(button, "OnEnter", ControlTipEnter)
	Perf.HookScript(button, "OnLeave", TipLeave)
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

-- a page's tab: its section's page opens it
local function TabSetSelected(self, selected)
	if selected then
		PanelTemplates_SelectTab(self)
	else
		PanelTemplates_DeselectTab(self)
	end
end
local TabClick = Shared("OnClick on the configurator's tabs", function(self)
	Click("tab")
	self.section.page:Select(self.section)
end, "script")

local function NewPage(name, width)
	local page = CreateFrame("Frame", nil, window.scroll)
	page.name = name
	page.width = width
	page.sections = {}
	page.refreshers = {}
	page.headerHeight = 0
	page.current = nil
	page:SetSize(width, 10)
	building[#building + 1] = page   -- its rows still to make, if any (the worker drops it when none are)

	function page:Refresh()
		for _, fn in ipairs(self.refreshers) do
			fn()
		end
		if self.current then
			self.current:Refresh()
		end
	end

	function page:Select(sec)
		-- the tab's rows down to the bottom of the view, made before it
		-- shows; the rest follow a few a frame
		if sec.jobs then
			local top, bottom = ViewRange(self, sec)
			MakeRows(sec, bottom, nil, top)
		end
		for _, other in ipairs(self.sections) do
			other:SetShown(other == sec)
		end
		self.current = sec
		for _, tab in ipairs(self.tabs or {}) do
			tab:SetSelected(tab.section == sec)
		end
		sec:Refresh()
		self:SetHeight(self.headerHeight + sec:GetHeight() + PAD)
		Kick()
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
				tab.SetSelected = TabSetSelected
				Perf.SetScript(tab, "OnClick", TabClick)
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
			if not sec.jobs then
				SectionBox(sec)   -- (a tab with no rows to make)
			end
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
		Perf.SetScript(defaults, "OnClick", function()
			for key, value in pairs(module.defaults) do
				-- a character's own data and one-time steps stay (the module's
				-- keep list: flight points, borrowed game settings, "layout
				-- already applied"); Defaults puts back settings only
				if not MelloUI:IsPersonalKey(module.name, key) then
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
			end
			MelloUI:Print("%s: settings back to their defaults.", module.title)
			MelloUI:RefreshConfig()
		end)
		Perf.SetScript(defaults, "OnEnter", function(self) ShowTooltip(self, "Defaults", "Put every option of this module back to its default value. The module stays on or off as it is.") end)
		Perf.SetScript(defaults, "OnLeave", function() GameTooltip:Hide() end)
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
				Perf.HookScript(hswitch, "OnEnter", function() ShowTooltip(hswitch, ht.name or ht.key, ht.desc) end)
				Perf.HookScript(hswitch, "OnLeave", function() GameTooltip:Hide() end)
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
				Perf.SetScript(button, "OnClick", function()
					hb.onClick()
					MelloUI:RefreshConfig()
				end)
				if hb.desc then
					Perf.SetScript(button, "OnEnter", function(self) ShowTooltip(self, hb.name or "Reset", hb.desc) end)
					Perf.SetScript(button, "OnLeave", function() GameTooltip:Hide() end)
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
	-- the header's controls dressed now (Defaults and the like, red plates);
	-- the tabs dress themselves and every row is dressed as it is made, so
	-- the page is not walked whole afterwards
	if KIT and KIT.SweepControls then
		KIT:SweepControls(page, KitReplace, kitSkin)
	end
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
	-- an option's row, made from its job: the builder, its indent, its gate,
	-- and its controls dressed (dropdowns, red plate buttons)
	local function MakeOption(s, job)
		local owner, ownerDb, opt, area = job[1], job[2], job[3], job[4]
		local builder = builders[opt.type]
		if not builder then
			MelloUI:Print("Unknown option type '%s' in module %s", tostring(opt.type), owner.name)
			return
		end
		s.indent = opt.type ~= "subheader" and ((area and 1 or 0) + Depth(owner, opt)) or 0
		local row = builder(s, owner, ownerDb, opt)
		s.indent = 0
		local gate = row and opt.type ~= "subheader" and GateOf(owner, ownerDb, opt, area)
		if gate then
			AddGate(s, row, gate)
		end
		if row and KIT and KIT.SweepControls then
			KIT:SweepControls(row, KitReplace, kitSkin, nil, 2)   -- (at the depth a sweep of the page reaches a row)
		end
	end
	-- an option may belong to ANOTHER module (`opt.module`), built against
	-- that module and its settings; `include` lays out another module's
	-- options in place (all of them, its headers as subheaders, or only
	-- `keys`, in their order, with inline rows between), under the tab's
	-- area switch (`area`, a key of this page's module: the rows indented
	-- one step and live only while it is on). Here the option's setting is
	-- filled in and its row queued on the tab; MakeRows makes it.
	local function Build(owner, ownerDb, opt, area)
		if not sec then
			sec = NewSection(page, "General")
		end
		if builders[opt.type] and opt.key and ownerDb[opt.key] == nil then
			ownerDb[opt.key] = owner.defaults[opt.key]
		end
		Queue(sec, { owner, ownerDb, opt, area }, MakeOption, ROW_HEIGHTS[opt.type] or 0)
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
		SectionBox(sec)
		local fs = Text(sec, "GameFontDisable", "This module has no options. The switch above is all there is to it.")
		fs:SetPoint("TOPLEFT", 14, -8)
		sec.y = 30
	end
	-- the tabs, and the first tab's rows down to the bottom of the view
	-- (page:Select)
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

-- a Home tile (`important`, `tipTitle`, `tipBody`, its border's rest colour)
-- and its "Open page" link (`pageName`)
local TileEnter = Shared("OnEnter on the configurator's Home tiles", function(self)
	if not KIT then
		if self.important then
			self:SetBackdropBorderColor(C.text[1], C.text[2], C.text[3], 1)
		else
			self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
		end
	end
	ShowTooltip(self, self.tipTitle, self.tipBody)
end, "script")
local TileLeave = Shared("OnLeave on the configurator's Home tiles", function(self)
	if not KIT then
		self:SetBackdropBorderColor(self.restR, self.restG, self.restB, 1)
	end
	GameTooltip:Hide()
end, "script")
local TileOpenEnter = Shared("OnEnter on the configurator's Open page links", function(self)
	Colour(self.label, C.accent)
end, "script")
local TileOpenLeave = Shared("OnLeave on the configurator's Open page links", function(self)
	Colour(self.label, C.accent2)
end, "script")
local TileOpenClick = Shared("OnClick on the configurator's Open page links", function(self)
	Click("page")
	SelectPage(self.pageName)
end, "script")

local function BuildHomePage(width)
	local page = NewPage("Home", width)
	BuildPageHeader(page, LOGO_FULL, "MelloUI", HOME_FLAVOUR, nil)
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
	Perf.SetScript(tour, "OnClick", function()
		Click("page")
		if MelloUI.Tutorial then
			MelloUI.Tutorial:Start()
		end
	end)
	Perf.SetScript(tour, "OnEnter", function(self) ShowTooltip(self, "Tutorial", "A short tour of this window: where every feature lives, step by step, on the game's help tips. Also /mello tutorial.") end)
	Perf.SetScript(tour, "OnLeave", function() GameTooltip:Hide() end)
	page.tutorialButton = tour

	-- Modules: a tile per module.
	local tiles = NewSection(page, "Modules")
	SectionBox(tiles)
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
		open.pageName = module.name
		Perf.SetScript(open, "OnEnter", TileOpenEnter)
		Perf.SetScript(open, "OnLeave", TileOpenLeave)
		Perf.SetScript(open, "OnClick", TileOpenClick)
		tile:EnableMouse(true)
		AttachHover(tile, 0.06)
		tile.important, tile.tipTitle, tile.tipBody = module.important, module.title, flavour
		tile.restR, tile.restG, tile.restB = restR, restG, restB
		Perf.HookScript(tile, "OnEnter", TileEnter)
		Perf.HookScript(tile, "OnLeave", TileLeave)
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

	-- What's new and Help, tabs that are not open at first: their texts are
	-- made after the tiles, a version or a block a job (MakeRows), when
	-- their tab opens or a frame or two later, whichever comes first
	local news = NewSection(page, "What's new")
	news.y = 6
	local function Version(sec, entry)
		local y = sec.y
		local head = Text(sec, "GameFontNormal", "Version " .. entry.version, C.accent)
		head:SetPoint("TOPLEFT", 4, -y)
		y = y + 24
		for _, line in ipairs(entry.lines) do
			local dot = Solid(sec, "ARTWORK", C.accent2, 1)
			dot:SetSize(6, 6)
			dot:SetPoint("TOPLEFT", 10, -(y + 6))
			local fs = Text(sec, "GameFontHighlight", line, C.text)
			fs:SetPoint("TOPLEFT", 24, -y)
			fs:SetWidth(sec:GetWidth() - 30)
			fs:SetWordWrap(true)
			y = y + WrappedHeight(fs, 14) + 8
		end
		sec.y = y + 10
	end
	for _, entry in ipairs(CHANGELOG) do
		Queue(news, entry, Version)
	end
	page.news = news   -- the tour points at it

	-- Help: commands and links.
	local help = NewSection(page, "Help")
	help.y = 6
	local function HelpBlock(sec, block)
		block(sec)
	end
	Queue(help, function(sec)
		local y = sec.y
		local head = Text(sec, "GameFontNormal", "Slash commands", C.accent)
		head:SetPoint("TOPLEFT", 4, -y)
		y = y + 24
		for _, cmd in ipairs(COMMANDS) do
			local c = Text(sec, "GameFontHighlight", cmd[1], C.text)
			c:SetPoint("TOPLEFT", 10, -y)
			local what = Text(sec, "GameFontHighlightSmall", cmd[2], C.sub)
			what:SetPoint("TOPLEFT", 230, -(y + 1))
			y = y + 20
		end
		sec.y = y + 10
	end, HelpBlock)
	Queue(help, function(sec)
		local y = sec.y
		local head2 = Text(sec, "GameFontNormal", "Links (select the text and copy it)", C.accent)
		head2:SetPoint("TOPLEFT", 4, -y)
		y = y + 24
		for _, link in ipairs(LINKS) do
			local lbl = Text(sec, "GameFontHighlight", link[1], C.text)
			lbl:SetPoint("TOPLEFT", 10, -(y + 4))
			local box = CreateFrame("EditBox", nil, sec, "InputBoxTemplate")
			box:SetSize(420, 22)
			box:SetPoint("TOPLEFT", 130, -y)
			box:SetAutoFocus(false)
			box:SetText(link[2])
			box:SetCursorPosition(0)
			Perf.SetScript(box, "OnTextChanged", function(self, user) if user then self:SetText(link[2]) end end)
			Perf.SetScript(box, "OnEscapePressed", function(self) self:ClearFocus() end)
			Perf.SetScript(box, "OnEditFocusGained", function(self) self:HighlightText() end)
			y = y + 28
		end
		sec.y = y + 10
	end, HelpBlock)
	Queue(help, function(sec)
		local y = sec.y
		local note = Text(sec, "GameFontHighlightSmall", nil, C.sub)
		note:SetPoint("TOPLEFT", 4, -y)
		note:SetWidth(sec:GetWidth() - 8)
		note:SetWordWrap(true)
		note:SetText("Settings are mirrored into account macros because this client does not read its saved variables back; /mello status shows the state of that backup. The voice pack (MelloUI_VoiceOverData) is a separate download from the releases page and goes next to the MelloUI folder.")
		sec.y = y + WrappedHeight(note, 14) + 8
	end, HelpBlock)
	page.helpSection = help

	page:Finish()
	if KIT and KIT.SweepControls then
		KIT:SweepControls(page, KitReplace, kitSkin)   -- the Tutorial button on the kit's plate
	end
	-- a tab made later: what it holds dressed as the page's sweep would have
	page.onSectionDone = function(sec)
		if KIT and KIT.SweepControls then
			KIT:SweepControls(sec, KitReplace, kitSkin, nil, 1)
		end
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
		-- a profile saved here lives in the saved variables, which this client
		-- drops at a full restart; one shipped in the addon's files comes back
		row.baked:SetText(builtIn and "built in" or (MelloUI:IsProfileBaked(name) and "comes with MelloUI" or "kept until restart"))
		row.delete:SetEnabled(not builtIn)
		Perf.SetScript(row.load, "OnClick", function()
			if MelloUI:LoadProfile(name) then
				MelloUI:Print("Profile '%s' loaded.", name)
			end
			MelloUI:RefreshConfig()
		end)
		Perf.SetScript(row.default, "OnClick", function()
			MelloUI:SetDefaultProfile(isDefault and nil or name)
			if MelloUI.ScheduleBackup then
				MelloUI:ScheduleBackup("profile default")
			end
			RefreshProfilesPage()
		end)
		Perf.SetScript(row.delete, "OnClick", function()
			MelloUI:DeleteProfile(name)
			RefreshProfilesPage()
		end)
		Perf.SetScript(row.share, "OnClick", function()
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
	SectionBox(sec)
	profilesSection = sec
	sec.rowFrames = {}

	local desc = Text(sec, "GameFontHighlightSmall", nil, C.sub)
	desc:SetPoint("TOPLEFT", 4, -4)
	desc:SetWidth(sec:GetWidth() - 8)
	desc:SetWordWrap(true)
	-- what is true for a player: saved profiles last until a full restart;
	-- the settings in use are kept by the macro backup (Core/Backup.lua)
	desc:SetText("A profile is a copy of every setting of every module. It leaves out what belongs to your characters: the flight points they know, game settings MelloUI borrowed, and steps done once; loading a profile never touches those. The one marked default is applied when MelloUI starts with no settings at all, such as on a fresh install. Profiles you save here are kept until the game fully restarts (a /reload keeps them): to keep one for longer, click Share, keep its string and bring it back with Import as. Your settings themselves are kept over restarts by a backup in hidden account macros (/mello status shows it), and the profiles that come with MelloUI are always here.")
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
			MelloUI:Print("Profile '%s' saved. It is kept until the game fully restarts; its Share string keeps it for longer.", name:gsub("^%s+", ""):gsub("%s+$", ""))
			sec.nameBox:SetText("")
			sec.nameBox:ClearFocus()
		else
			MelloUI:Print(err)
		end
		RefreshProfilesPage()
	end
	Perf.SetScript(sec.save, "OnClick", Save)
	page.saveButton = sec.save
	-- a share string from someone else, stored under the name typed
	sec.import = CreateFrame("Button", nil, sec, "UIPanelButtonTemplate")
	sec.import:SetSize(150, 22)
	sec.import:SetPoint("LEFT", sec.save, "RIGHT", 6, 0)
	sec.import:SetText("Import as")
	Perf.SetScript(sec.import, "OnClick", function()
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
	Perf.SetScript(sec.nameBox, "OnEnterPressed", Save)
	Perf.SetScript(sec.nameBox, "OnEscapePressed", function(self) self:ClearFocus() end)
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

-- the strip's buttons (`pageName`, the icon `box`, the tooltip's `tipTitle`
-- and `tipBody`)
local StripClick = Shared("OnClick on the configurator's icon strip", function(self)
	if currentPage ~= self.pageName then
		Click("page")
	end
	SelectPage(self.pageName)
end, "script")
local StripEnter = Shared("OnEnter on the configurator's icon strip", function(self)
	self.box:SetHovered(true)
	ShowTooltip(self, self.tipTitle, self.tipBody)
end, "script")
local StripLeave = Shared("OnLeave on the configurator's icon strip", function(self)
	self.box:SetHovered(false)
	self.box:SetPressed(false)
	GameTooltip:Hide()
end, "script")
local StripDown = Shared("OnMouseDown on the configurator's icon strip", function(self)
	self.box:SetPressed(true)
end, "script")
local StripUp = Shared("OnMouseUp on the configurator's icon strip", function(self)
	self.box:SetPressed(false)
end, "script")

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
	btn.pageName, btn.tipTitle, btn.tipBody = name, title, flavour
	Perf.SetScript(btn, "OnClick", StripClick)
	Perf.SetScript(btn, "OnEnter", StripEnter)
	Perf.SetScript(btn, "OnLeave", StripLeave)
	Perf.SetScript(btn, "OnMouseDown", StripDown)
	Perf.SetScript(btn, "OnMouseUp", StripUp)
	stripButtons[name] = btn
	return btn
end

-- Each look's window ([true] the kit's, [false] the plain one) and what
-- belongs to it, kept while the other look's is the one in use: made on
-- its first show in that look, shown again after, never made twice (audit,
-- 2026-09-24, rank 1: the look is asked at every show; a window's parts are
-- built once and only switched after)
local looks = {}
local windowsMade = 0

local function PutLookAside()
	local kept = looks[KIT ~= nil]
	if not kept then
		kept = {}
		looks[KIT ~= nil] = kept
	end
	kept.window, kept.pages, kept.stripButtons, kept.currentPage = window, pages, stripButtons, currentPage
	kept.KIT, kept.kitSkin, kept.building, kept.worker = KIT, kitSkin, building, worker
	kept.profilesSection = profilesSection
end

local function TakeLookUp(kept)
	window, pages, stripButtons, currentPage = kept.window, kept.pages, kept.stripButtons, kept.currentPage
	KIT, kitSkin, building, worker = kept.KIT, kept.kitSkin, kept.building, kept.worker
	profilesSection = kept.profilesSection
	-- (the name the game's Escape, the mover and Dynamic UI look it up by)
	_G.MelloUIConfigFrame = window
end

-- the window coming in hangs where the one going out was, at its scale
local function TakePlace(to, from)
	local n = from:GetNumPoints() or 0
	if n > 0 then
		to:ClearAllPoints()
		for i = 1, n do
			local point, rel, relPoint, x, y = from:GetPoint(i)
			if point then
				to:SetPoint(point, rel, relPoint, x, y)
			end
		end
	end
	local scale = from:GetScale() or 1
	if math.abs((to:GetScale() or 1) - scale) > 0.001 then
		local Kit = MelloUI.Kit
		if Kit and Kit.SetFrameScale then
			Kit:SetFrameScale(to, scale)
		else
			to:SetScale(scale)
		end
	end
end

-- the open window's placement switches follow the settings, however they
-- change (the unlock banner's "click here to lock them" too): the bus's
-- 'setting' (audit, 2026-09-24, rank 5: this hooked NotifySettingChanged,
-- run for every setting of every module and never let go)
local function PlacementFollows(module, key)
	if module == "UIModifications" and (key == "unlock" or key == "autoSnap") and window and window.RefreshPlacement then
		window.RefreshPlacement()
	end
end

local function CreateWindow()
	local want = KitWanted()
	local from
	if window then
		-- made for the look wanted, or open now (an open window keeps its
		-- look until it is closed: the switch is usually flipped in it)
		if (want ~= nil) == (KIT ~= nil) or window:IsShown() then
			return
		end
		from = window
		PutLookAside()
		local kept = looks[want ~= nil]
		if kept then
			TakeLookUp(kept)
			TakePlace(window, from)
			return
		end
		-- the other look's first show: a window of its own
		window, pages, stripButtons, currentPage = nil, {}, {}, nil
		kitSkin, building, worker, profilesSection = { reps = {}, followers = {} }, {}, nil, nil
	end
	KIT = want
	windowsMade = windowsMade + 1
	window = CreateFrame("Frame", "MelloUIConfigFrame", UIParent, "BackdropTemplate")
	window:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
	window:SetPoint("CENTER")
	window:SetFrameStrata("HIGH")
	window:SetToplevel(true)
	window:SetMovable(true)
	window:EnableMouse(true)
	window:SetClampedToScreen(true)
	window:Hide()
	if windowsMade == 1 then
		tinsert(UISpecialFrames, "MelloUIConfigFrame")
	end

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
	Perf.SetScript(band, "OnDragStart", function() window:StartMoving() end)
	Perf.SetScript(band, "OnDragStop", function() window:StopMovingOrSizing() end)
	window.band = band

	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -10, -12)
	Perf.SetScript(close, "OnClick", function() window:Hide() end)
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
	Perf.SetScript(dynamic, "OnClick", function()
		if MelloUI.StartDynamicUI then
			MelloUI:StartDynamicUI()
		end
	end)
	Perf.SetScript(dynamic, "OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Dynamic UI Modification", C.accent[1], C.accent[2], C.accent[3])
		GameTooltip:AddLine("The look of the reskin, all in one place: the borders and Kit Colours of every window, the parchment sheets, "
			.. "and the backgrounds of the action bars, micro menu, bag bar, bags, character window, minimap and professions, "
			.. "chosen on the interface itself with a picture of each choice. Closes the configurator while you pick.", C.text[1], C.text[2], C.text[3], true)
		GameTooltip:Show()
	end)
	Perf.SetScript(dynamic, "OnLeave", function() GameTooltip:Hide() end)
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
			Perf.HookScript(owner, "OnEnter", function(self) ShowTooltip(self, t.name, t.desc) end)
			Perf.HookScript(owner, "OnLeave", function() GameTooltip:Hide() end)
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
	Perf.SetScript(reset, "OnClick", function()
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
	window.RefreshPlacement = RefreshPlacement
	Perf.HookScript(window, "OnShow", RefreshPlacement)
	MelloUI:On("setting", PlacementFollows, "Config placement")
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

	-- Scrolling page area. (The other look's window, when there is one, has
	-- a scroll frame of its own name: its template's parts are named after
	-- it.)
	window.scroll = CreateFrame("ScrollFrame", "MelloUIConfigScroll" .. (windowsMade > 1 and windowsMade or ""), window,
		"UIPanelScrollFrameTemplate")
	window.scroll:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, -4)
	window.scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -34, 16)
	if window.scroll.ScrollBar then
		window.scroll.ScrollBar:ClearAllPoints()
		window.scroll.ScrollBar:SetPoint("TOPLEFT", window.scroll, "TOPRIGHT", 6, -16)
		window.scroll.ScrollBar:SetPoint("BOTTOMLEFT", window.scroll, "BOTTOMRIGHT", 6, 16)
	end
	window.pageWidth = WINDOW_WIDTH - 8 - 34

	-- the pages' rows still to make, a few a frame while the window is open
	worker = CreateFrame("Frame", nil, window)
	worker:Hide()
	Perf.SetScript(worker, "OnUpdate", Work)

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
	Perf.SetScript(glider, "OnUpdate", function(self, elapsed)
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
		-- rows scrolled into view before the worker came to them: made now
		local page = currentPage and pages[currentPage]
		local sec = page and page.current
		if sec and sec.jobs and scroll:GetScrollChild() == page then
			local top, bottom = ViewRange(page, sec)
			MakeRows(sec, bottom, nil, top)
		end
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
	Perf.SetScript(scroll, "OnMouseWheel", function(self, delta)
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
			-- (the backgrounds in the window laid again, not every one in the
			-- UI -- audit, 2026-09-24)
			local Kit = MelloUI.Kit
			if Kit and Kit.SetFrameScale then
				Kit:SetFrameScale(self, fit)
			else
				self:SetScale(fit)
			end
		end
	end
	-- (once, with the first window: it fits whichever window is in use,
	-- so the other look's window adds none of its own -- review, 2026-09-25)
	if windowsMade == 1 and MelloUI.Kit and MelloUI.Kit.OnUIScaleChanged then
		MelloUI.Kit:OnUIScaleChanged(function(reason)
			if reason == "uiscale" and window:IsShown() then
				window:FitToScreen()
			end
		end)
	end
	Perf.SetScript(window, "OnShow", function(self)
		self:FitToScreen()
		MelloUI:PlayUISound("window_open")
		MelloUI:RefreshConfig()
	end)
	Perf.SetScript(window, "OnHide", function()
		MelloUI:PlayUISound("window_close")
	end)
	if from then
		TakePlace(window, from)
	end
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
	Kick()
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
		MelloUI:PlayUISound("menu_button")
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
	Perf.SetScript(waiter, "OnEvent", function(self)
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

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local IsSecret = MelloUI.Safe.IsSecret

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
		Perf.SetScript(probe, "OnEvent", function(self)
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
			MelloUI:Print(ok and ("Profile '" .. name .. "' saved. It is kept until the game fully restarts; /mello profile export " .. name .. " gives a string that keeps it for longer.") or err)
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
				print("   " .. n .. (MelloUI:IsProfileBaked(n) and "" or "  (kept until the game restarts)"))
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
				MelloUI:Print("Edit Mode layout '%s' (%d chars), the game's share string, ready to copy:", tostring(name), #text)
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
			MelloUI:Print("/mello layout export (the active layout's share string, to copy) | apply (MelloUI's layout into Edit Mode, made active)")
		end
	elseif cmd == "perf" then
		SlashCmdList.MELLOPERF(rest or "")
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
		-- /melloperf is in COMMANDS now; these are the tuning ones
		print("   /mello dump [m]            print the stored settings of all modules or one module")
		print("   /mello cpu                 CPU time per handler (old; needs scriptProfile)")
		print("   /mello preload             how much of the artwork is preloaded")
		print("   /mello secrets             which secret-value tools this client has, and what a secret allows")
		print("   /mello auras               what this client's aura container offers (for MelloUI's own aura rows)")
	elseif cmd ~= "" and not ModuleByName(cmd) and cmd ~= "profiles" then
		MelloUI:Print("Unknown command or module '%s'. /mello help lists the commands, /mello list the modules.", cmd)
	else
		MelloUI:OpenConfig(cmd ~= "" and cmd or nil)
	end
end
