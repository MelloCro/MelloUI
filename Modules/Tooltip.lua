--------------------------------------------------------------------------------
-- MelloUI - Tooltip
--
-- Flat dark tooltip backdrop, class / reaction coloured border and unit names,
-- the Bar Textures fill on the tooltip health bar, and placement options.
--
-- Blizzard resets the backdrop colour in SharedTooltip_SetBackdropStyle every
-- time a tooltip hides, so the colours are re-applied from a hook on it. Unit
-- details are applied from a TooltipDataProcessor post call. Nothing writes
-- fields on Blizzard's tooltip health bar: its update path compares secret
-- health values and must stay untainted.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Tooltip")
local hooksecurefunc = Perf.hooksecurefunc
local Num = MelloUI.Safe.Number

local Background   -- (the Background dropdown's reading: below, 0.16.0)

local M = MelloUI:RegisterModule("Tooltip", {
	title = "Tooltip",
	desc = "Dark flat tooltips with class coloured names and borders, plus placement options.",
	icon = "Interface\\Icons\\INV_Misc_Book_09",
	flavour = "Dark, flat and out of the way, with names in the colour of their class.",
	group = "Frames and bars", navOrder = 3,
	role = "replaces",
	tweak = { label = "Tooltip Tweaks", desc = "Class and reaction colours, the health bar and placement of tooltips. The dark backdrop only applies while the tooltip reskin is off.", order = 10 },
	defaults = {
		darkBackdrop = true,
		backdropAlpha = 0.9,
		darkBorder = true,
		classBorder = false,
		classHealth = true,
		hideHealthBar = true,
		anchor = "default",
		hideInCombat = false,
		scale = 1,
		fadeDelay = 0.4,
	},
	options = {
		{ type = "header", name = "Backdrop" },
		-- (0.16.0: the tooltips' look in one: the painted skin, its
		-- parchment, the dark backdrop and border, or the game's; the
		-- settings it sets keep their own keys -- UI Modifications'
		-- TooltipPanel and parchment_tooltip, darkBackdrop and darkBorder --
		-- read by `get`, written by OnSettingChanged)
		{ type = "dropdown", key = "background", name = "Background", values = {
			{ value = "painted", label = "Painted" },
			{ value = "parchment", label = "Parchment" },
			{ value = "dark", label = "Dark" },
			{ value = "game", label = "Game" },
		  }, get = function(db) return Background(db) end,
		  desc = "The tooltips' background: the painted kit (Painted), the kit with a parchment sheet whose text is dark ink (Parchment), a flat near-black box with a dark border in your palette's colours (Dark), or the game's own. Painted and Parchment need the reskin on (Look)." },
		{ type = "slider", key = "backdropAlpha", name = "Backdrop Opacity", min = 0.3, max = 1, step = 0.05, percent = true,
		  desc = "Opacity of the Dark background." },
		{ type = "toggle", key = "classBorder", name = "Class / Reaction Border",
		  desc = "Colour the border of unit tooltips by class (players) or reaction (NPCs)." },
		{ type = "header", name = "Units" },
		{ type = "toggle", key = "classHealth", name = "Class / Reaction Health Colour",
		  desc = "Colour the tooltip health bar by class or reaction instead of green." },
		{ type = "toggle", key = "hideHealthBar", name = "Hide Health Bar", desc = "Hide the health bar under unit tooltips (on by default). The two options above only matter when the bar is shown." },
		{ type = "toggle", key = "hideInCombat", name = "Hide Unit Tooltips In Combat", desc = "Do not show tooltips for units while in combat." },
		{ type = "slider", key = "fadeDelay", name = "Fade Delay", min = 0.1, max = 1, step = 0.05, new = "0.18.3",
		  format = function(v) return string.format("%.2f s", v) end,
		  desc = "How long the tooltip of a creature or an object stays fully visible after your cursor leaves it, before it fades out (the fade itself takes a quarter of a second)." },
		{ type = "header", name = "Placement" },
		{ type = "dropdown", key = "anchor", name = "Anchor", desc = "Where tooltips appear.",
		  values = {
			{ value = "default", label = "Default (Edit Mode position)" },
			{ value = "cursor", label = "At the cursor" },
			{ value = "cursor_right", label = "Right of the cursor" },
		  } },
		{ type = "slider", key = "scale", name = "Scale", min = 0.5, max = 1.5, step = 0.05, percent = true,
		  desc = "Scale of the game tooltip." },
	},
})

-- The plain look's colours (Dark Backdrop, Dark Border): the palette's inner
-- panel and border, read each time they are laid; a new palette lays them
-- again (OnPalette, heard while the module is on)
local BACKDROP, BORDER = "innerPanel", "border"
local PALETTE_OWNER = "Tooltip palette"   -- (the bus owner)

local hooksInstalled = false
local Follow   -- (At the cursor: Placement, below)
local Fade     -- (Fade Delay: below Placement)
local unitColor = nil            -- { r, g, b } of the unit currently shown, or nil
local applyingBarColor = false
local originalBarTexture = nil
local barHidden = false          -- the health bar at alpha 0 (Hide Health Bar): nobody sees its colour

-- a module's settings as saved (nil before there are any)
local function Saved(module)
	local mods = MelloUI.db and MelloUI.db.modules
	local t = type(mods) == "table" and mods[module]
	return type(t) == "table" and t or nil
end

-- Class Coloured Names (0.16.0: UI Modifications' one switch for the chat
-- and the tooltip, as saved; on while not saved)
local function ClassNames()
	local ui = Saved("UIModifications")
	return not (ui and ui.classNames == false)
end

-- The Background dropdown (0.16.0): what the settings it stands for say now,
-- and setting them. The painted skin is UI Modifications' TooltipPanel (on
-- while not saved off), its parchment parchment_tooltip, Dark this module's
-- darkBackdrop and darkBorder.
Background = function(db)
	local ui = Saved("UIModifications")
	if not (ui and ui.TooltipPanel == false) then
		return (ui and ui.parchment_tooltip == true) and "parchment" or "painted"
	end
	return (db and db.darkBackdrop) and "dark" or "game"
end
M.Background = Background   -- (read only: the tests)

local function Put(module, key, value)
	local t = Saved(module)
	if t and t[key] == value then
		return
	end
	MelloUI:NotifySettingChanged(module, key, value)
end

local function SetBackground(value)
	local painted = value == "painted" or value == "parchment"
	Put("UIModifications", "TooltipPanel", painted)
	if painted then
		Put("UIModifications", "parchment_tooltip", value == "parchment")
	end
	local dark = value == "dark"
	if M.db then
		M.db.darkBackdrop, M.db.darkBorder = dark, dark
	end
end

local function TooltipList()
	local list = {}
	local names = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
		"EmbeddedItemTooltip", "GameNoHeaderTooltip", "GameSmallHeaderTooltip", "BuffFrameTooltip",
		"ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "WorldMapTooltip", "QuestScrollFrame" }
	for _, name in ipairs(names) do
		local frame = _G[name]
		if frame and frame.NineSlice then
			list[#list + 1] = frame
		end
	end
	return list
end

--------------------------------------------------------------------------------
-- Backdrop
--------------------------------------------------------------------------------

local function StyleBackdrop(tooltip)
	if not M.isEnabled or not tooltip or not tooltip.NineSlice then
		return
	end
	-- the kit's tooltip (TooltipPanel) stands in for the backdrop colouring
	-- while it covers the group (user, 2026-09-21: tweaks apply only while
	-- the kit module for the group is off)
	local Kit = MelloUI.Kit
	if Kit and Kit.IsCovered and Kit:IsCovered("tooltip") then
		return
	end
	local db = M.db
	local nine = tooltip.NineSlice
	if db.darkBackdrop and nine.SetCenterColor then
		local c = MelloUI.Palette[BACKDROP]
		nine:SetCenterColor(c[1], c[2], c[3], db.backdropAlpha or 0.9)
	end
	if nine.SetBorderColor then
		if unitColor and db.classBorder and tooltip == GameTooltip then
			nine:SetBorderColor(unitColor[1], unitColor[2], unitColor[3], 1)
		elseif db.darkBorder then
			local c = MelloUI.Palette[BORDER]
			nine:SetBorderColor(c[1], c[2], c[3], 1)
		end
	end
end

-- a new palette: the plain look laid again on every tooltip (StyleBackdrop
-- leaves them alone while the kit's tooltip covers the group)
local function OnPalette()
	for _, tooltip in ipairs(TooltipList()) do
		StyleBackdrop(tooltip)
	end
end

local function RestoreBackdrop(tooltip)
	if not tooltip or not tooltip.NineSlice then
		return
	end
	local nine = tooltip.NineSlice
	if nine.SetCenterColor and TOOLTIP_DEFAULT_BACKGROUND_COLOR then
		local r, g, b = TOOLTIP_DEFAULT_BACKGROUND_COLOR:GetRGB()
		nine:SetCenterColor(r, g, b, 1)
	end
	if nine.SetBorderColor then
		nine:SetBorderColor(1, 1, 1, 1)
	end
end

--------------------------------------------------------------------------------
-- Units
--------------------------------------------------------------------------------

local function UnitColorFor(unit)
	-- Everything here may touch secret values; the caller wraps it in pcall.
	if UnitIsPlayer(unit) then
		local _, class = UnitClass(unit)
		local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if color then
			return color.r, color.g, color.b
		end
	end
	if GameTooltip_UnitColor then
		return GameTooltip_UnitColor(unit)
	end
	return nil
end

local function ColorHealthBar()
	local bar = GameTooltipStatusBar
	if barHidden or not bar or not unitColor or not M.db.classHealth then
		return
	end
	applyingBarColor = true
	bar:SetStatusBarColor(unitColor[1], unitColor[2], unitColor[3])
	applyingBarColor = false
end

local function OnUnitTooltip(tooltip, data)
	if not M.isEnabled or tooltip ~= GameTooltip then
		return
	end
	local db = M.db
	if db.hideInCombat and InCombatLockdown and InCombatLockdown() then
		tooltip:Hide()
		return
	end
	local ok, unit = pcall(function()
		local guid = data and data.guid
		return guid and UnitTokenFromGUID and UnitTokenFromGUID(guid)
	end)
	if not ok or not unit then
		return
	end
	local okColor, r, g, b = pcall(UnitColorFor, unit)
	unitColor = (okColor and r) and { r, g, b } or nil

	if ClassNames() and unitColor then
		local okPlayer, isPlayer = pcall(UnitIsPlayer, unit)
		local line = _G[tooltip:GetName() .. "TextLeft1"]
		if okPlayer and isPlayer and line then
			line:SetTextColor(unitColor[1], unitColor[2], unitColor[3])
		end
	end
	StyleBackdrop(tooltip)
	ColorHealthBar()
end

local function OnTooltipHidden(tooltip)
	if tooltip == GameTooltip then
		unitColor = nil
		Follow.on = false
		Fade.Stop(true)
	end
end

--------------------------------------------------------------------------------
-- Health bar
--------------------------------------------------------------------------------

local function ApplyHealthBar()
	local bar = GameTooltipStatusBar
	if not bar then
		return
	end
	local db = M.db
	if originalBarTexture == nil then
		local tex = bar:GetStatusBarTexture()
		local file = tex and tex.GetTexture and tex:GetTexture()
		originalBarTexture = type(file) == "string" and file or false
	end
	local wanted = nil
	-- (0.16.0: Bar Textures' Tooltip area, its Apply To switch)
	local textures = MelloUI:IsModuleEnabled("BarTextures") and MelloUI:GetModuleDB("BarTextures")
	if M.isEnabled and textures and textures.tooltip ~= false then
		wanted = textures.texture
		if wanted == "default" then
			wanted = nil   -- Bar Textures' "Default (Blizzard)": the game's own bar
		end
	end
	if wanted then
		bar:SetStatusBarTexture(wanted)
	elseif originalBarTexture then
		bar:SetStatusBarTexture(originalBarTexture)
	end
	local hide = (M.isEnabled and db.hideHealthBar) and true or false
	local was = barHidden
	barHidden = hide
	bar:SetAlpha(hide and 0 or 1)
	if was and not hide then
		ColorHealthBar()   -- shown again: the unit's colour at once, not at its next health change
	end
end

--------------------------------------------------------------------------------
-- Placement
--------------------------------------------------------------------------------

-- At the cursor (user, 2026-10-03: "as soon as i move the tooltip over an
-- enemy and then move it away, the tooltip disappears instantly, it should
-- slowly fade out so that its still readable for a second like the default
-- behaves"): the game fades a world tooltip out only while its anchor stays
-- the game's own -- moving off, it lays the tooltip again through
-- GameTooltip_SetDefaultAnchor (SetOwner ... "ANCHOR_NONE"), and a tooltip
-- the engine had anchored to the cursor (SetOwner ... "ANCHOR_CURSOR", as
-- this module did) changed anchor there and went at once. So the game's
-- anchor is kept and the tooltip is laid at the cursor here: after the
-- game's own placing, then followed while it shows (its OnUpdate, a post-hook:
-- it runs only while the tooltip shows, and moves it only when the cursor
-- moved), and left where it is while it fades (its alpha under 1). Any other
-- SetOwner (a frame placing the tooltip itself) ends the following.
-- (One table: the place, its offsets.)
Follow = { on = false, x = nil, y = nil,
	-- the anchor's point of the tooltip and its offset from the cursor's tip
	-- (in the tooltip's own units): above it, or to the right of its arrow
	AT = { cursor = { "BOTTOMLEFT", 4, 4 }, cursor_right = { "TOPLEFT", 22, -2 } } }

function Follow.Place(tip, force)
	local spec = Follow.AT[M.db and M.db.anchor]
	if not spec then
		return
	end
	local x, y = GetCursorPosition()
	if not force and x == Follow.x and y == Follow.y then
		return
	end
	local scale = tip:GetEffectiveScale()
	if not (scale and scale > 0) then
		return
	end
	Follow.x, Follow.y = x, y
	tip:ClearAllPoints()
	tip:SetPoint(spec[1], UIParent, "BOTTOMLEFT", x / scale + spec[2], y / scale + spec[3])
end

-- followed while it shows, at full alpha (fading: left where it is)
function Follow.OnUpdate(tip)
	if Follow.on and M.isEnabled then
		local alpha = Num(tip:GetAlpha())
		if alpha and alpha >= 0.99 then
			Follow.Place(tip)
		end
	end
end

-- a SetOwner not the game's default placing (that one is followed by the
-- post-hook below, which takes the tooltip again): not ours to move
function Follow.OnSetOwner()
	Follow.on = false
end

local function OnDefaultAnchor(tooltip, parent)
	if not M.isEnabled or tooltip ~= GameTooltip then
		return
	end
	if Follow.AT[M.db.anchor] then
		Follow.on = true
		Follow.Place(tooltip, true)
	end
end

--------------------------------------------------------------------------------
-- Fade Delay (user, 2026-10-03: "Can we make that fade custom and give users a
-- slider from 0.1 - 1 second, default should be 0.4 seconds before starting
-- to fade"): a world tooltip the game fades out (the cursor left a creature or
-- an object: GameTooltip:FadeOut, the engine's, its time not settable) stays
-- whole for Fade Delay, then fades in Fade.SPAN and hides. When the engine's
-- fade starts (a post-hook on FadeOut) the tooltip is shown once more -- Show
-- ends a tooltip's fade -- and ours runs on a frame of our own, only while it
-- holds and fades. Each frame checks that the engine let go: an alpha fallen
-- under what we set is the engine's still, and ours stands down for the
-- session, the game's fade used (nothing fights the engine frame by frame:
-- WINDOW-RULES section 6); /ttdump fade says which. Anything that takes the
-- tooltip again (a new unit, an item: any SetOwner) or hides it ends ours,
-- the tooltip whole again.
-- (One table: the state, the driver, what this session found.)
--------------------------------------------------------------------------------
Fade = { SPAN = 0.25, MIN = 0.1, MAX = 1, on = false, start = 0, set = 1, driver = nil,
	engine = false, runs = 0, last = nil }

function Fade.Delay()
	local d = tonumber(M.db and M.db.fadeDelay) or 0.4
	return math.min(Fade.MAX, math.max(Fade.MIN, d))
end

function Fade.Stop(whole)
	if not Fade.on then
		return
	end
	Fade.on = false
	if Fade.driver then
		Fade.driver:Hide()
	end
	if whole and GameTooltip then
		GameTooltip:SetAlpha(1)
	end
end

function Fade.OnUpdate()
	local tip = GameTooltip
	local alpha = Num(tip:GetAlpha())
	if alpha and alpha < Fade.set - 0.02 then
		-- the engine's fade still runs: it is left to it, for the session
		Fade.engine, Fade.on = true, false
		Fade.last = string.format("the game's fade went on after Show (alpha %.2f, ours %.2f): the game's own fade is used this session", alpha, Fade.set)
		Fade.driver:Hide()
		return
	end
	local hold, t = Fade.Delay(), GetTime() - Fade.start
	if t < hold then
		return
	end
	local a = 1 - (t - hold) / Fade.SPAN
	if a <= 0 then
		Fade.last = string.format("faded: %.2f s whole, then %.2f s fading (run %d)", hold, Fade.SPAN, Fade.runs)
		Fade.on = false
		Fade.driver:Hide()
		tip:Hide()
		tip:SetAlpha(1)
		return
	end
	Fade.set = a
	tip:SetAlpha(a)
end

function Fade.OnFadeOut(tip)
	if tip ~= GameTooltip or not M.isEnabled or Fade.engine then
		return
	end
	-- (as the game's fade: left where it is, not followed)
	Follow.on = false
	if not Fade.driver then
		Fade.driver = CreateFrame("Frame")
		Fade.driver:Hide()
		Perf.SetScript(Fade.driver, "OnUpdate", Fade.OnUpdate)
	end
	Fade.runs = Fade.runs + 1
	Fade.start, Fade.set, Fade.on = GetTime(), 1, true
	tip:Show()
	tip:SetAlpha(1)
	Fade.driver:Show()
end

-- what this session's fades did (/ttdump fade)
function M.FadeReport()
	return string.format("Fade Delay %.2f s (fade %.2f s); %s; %d fades taken over; last: %s",
		Fade.Delay(), Fade.SPAN, Fade.engine and "the game's own fade (ours stood down)" or (M.isEnabled and "ours" or "module off"),
		Fade.runs, tostring(Fade.last or "none yet"))
end

-- any SetOwner: the tooltip taken again (ours ends) and no longer the game's
-- default placing to follow (that one is taken again by OnDefaultAnchor)
local function OnSetOwner()
	Follow.OnSetOwner()
	Fade.Stop(true)
end

-- (its backgrounds laid again at the UI's one resolution whatever the scale:
-- those in the tooltip, and only when its scale really changed -- audit,
-- 2026-09-24: each setting of this module laid every background in the UI)
local function ApplyScale()
	if GameTooltip then
		local scale = M.isEnabled and (tonumber(M.db.scale) or 1) or 1
		local Kit = MelloUI.Kit
		if Kit and Kit.SetFrameScale then
			Kit:SetFrameScale(GameTooltip, scale)
		else
			GameTooltip:SetScale(scale)
		end
	end
end

--------------------------------------------------------------------------------
-- Hooks
--------------------------------------------------------------------------------

local function InstallHooks()
	if hooksInstalled then
		return
	end
	hooksInstalled = true

	if type(SharedTooltip_SetBackdropStyle) == "function" then
		hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tooltip)
			StyleBackdrop(tooltip)
		end)
	end
	if type(GameTooltip_SetDefaultAnchor) == "function" then
		hooksecurefunc("GameTooltip_SetDefaultAnchor", OnDefaultAnchor)
	end
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
	end
	if GameTooltip then
		Perf.HookScript(GameTooltip, "OnHide", OnTooltipHidden)
		-- (At the cursor: below Placement)
		hooksecurefunc(GameTooltip, "SetOwner", OnSetOwner)
		Perf.HookScript(GameTooltip, "OnUpdate", Follow.OnUpdate)
		-- (Fade Delay: the engine's fade taken over when it starts)
		if type(GameTooltip.FadeOut) == "function" then
			hooksecurefunc(GameTooltip, "FadeOut", Fade.OnFadeOut)
		end
	end
	if GameTooltipStatusBar then
		-- Blizzard recolours the bar green on every value change; put the unit
		-- colour back afterwards. Only the colour call is touched, never the
		-- bar's fields. While the bar is hidden (Hide Health Bar, the
		-- default) it is left at once: a bar nobody sees is not recoloured
		-- (the 2026-09-24 review); shown again, it is coloured then.
		hooksecurefunc(GameTooltipStatusBar, "SetStatusBarColor", function()
			if barHidden or applyingBarColor then
				return
			end
			if M.isEnabled and unitColor and M.db.classHealth then
				ColorHealthBar()
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

local function ApplyAll()
	for _, tooltip in ipairs(TooltipList()) do
		StyleBackdrop(tooltip)
	end
	ApplyHealthBar()
	ApplyScale()
end

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	InstallHooks()
	MelloUI:On("palette", OnPalette, PALETTE_OWNER)
	ApplyAll()
end

function M:OnDisable()
	MelloUI:Off(PALETTE_OWNER, "palette")
	unitColor = nil
	Fade.Stop(true)
	for _, tooltip in ipairs(TooltipList()) do
		RestoreBackdrop(tooltip)
	end
	ApplyHealthBar()
	ApplyScale()
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "background" then
		SetBackground(value)
		if MelloUI.RefreshConfig then
			MelloUI:RefreshConfig()
		end
	end
	ApplyAll()
end

MelloUI:Profile("Tooltip", "unit tooltips", OnUnitTooltip)
MelloUI:Profile("Tooltip", "health bar colour", ColorHealthBar)
