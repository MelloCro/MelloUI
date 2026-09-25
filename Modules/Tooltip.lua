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

local M = MelloUI:RegisterModule("Tooltip", {
	title = "Tooltip",
	desc = "Dark flat tooltips with class coloured names and borders, plus placement options.",
	defaults = {
		darkBackdrop = true,
		backdropAlpha = 0.9,
		darkBorder = true,
		classBorder = false,
		classNames = true,
		barTexture = true,
		classHealth = true,
		hideHealthBar = true,
		anchor = "default",
		hideInCombat = false,
		scale = 1,
	},
	options = {
		{ type = "header", name = "Backdrop" },
		{ type = "toggle", key = "darkBackdrop", name = "Dark Backdrop", desc = "Flat, near-black tooltip background." },
		{ type = "slider", key = "backdropAlpha", parent = "darkBackdrop", name = "Backdrop Opacity", min = 0.3, max = 1, step = 0.05, percent = true,
		  desc = "Opacity of the tooltip background." },
		{ type = "toggle", key = "darkBorder", name = "Dark Border", desc = "Dark grey tooltip border instead of the gold one." },
		{ type = "toggle", key = "classBorder", name = "Class / Reaction Border",
		  desc = "Colour the border of unit tooltips by class (players) or reaction (NPCs)." },
		{ type = "header", name = "Units" },
		{ type = "toggle", key = "classNames", name = "Class Coloured Names", desc = "Colour player names in the tooltip by class." },
		{ type = "toggle", key = "barTexture", name = "Use Bar Texture", desc = "Use the Bar Textures fill on the tooltip health bar." },
		{ type = "toggle", key = "classHealth", name = "Class / Reaction Health Colour",
		  desc = "Colour the tooltip health bar by class or reaction instead of green." },
		{ type = "toggle", key = "hideHealthBar", name = "Hide Health Bar", desc = "Hide the health bar under unit tooltips (on by default). The two options above only matter when the bar is shown." },
		{ type = "toggle", key = "hideInCombat", name = "Hide Unit Tooltips In Combat", desc = "Do not show tooltips for units while in combat." },
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

local BACKDROP = { 0.06, 0.06, 0.06 }
local BORDER = { 0.22, 0.22, 0.22 }

local hooksInstalled = false
local unitColor = nil            -- { r, g, b } of the unit currently shown, or nil
local applyingBarColor = false
local originalBarTexture = nil
local barHidden = false          -- the health bar at alpha 0 (Hide Health Bar): nobody sees its colour

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
		nine:SetCenterColor(BACKDROP[1], BACKDROP[2], BACKDROP[3], db.backdropAlpha or 0.9)
	end
	if nine.SetBorderColor then
		if unitColor and db.classBorder and tooltip == GameTooltip then
			nine:SetBorderColor(unitColor[1], unitColor[2], unitColor[3], 1)
		elseif db.darkBorder then
			nine:SetBorderColor(BORDER[1], BORDER[2], BORDER[3], 1)
		end
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

	if db.classNames and unitColor then
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
	if M.isEnabled and db.barTexture and MelloUI:IsModuleEnabled("BarTextures") then
		local textures = MelloUI:GetModuleDB("BarTextures")
		wanted = textures and textures.texture
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

local function OnDefaultAnchor(tooltip, parent)
	if not M.isEnabled or tooltip ~= GameTooltip then
		return
	end
	local anchor = M.db.anchor
	if anchor == "cursor" then
		tooltip:SetOwner(parent or UIParent, "ANCHOR_CURSOR")
	elseif anchor == "cursor_right" then
		tooltip:SetOwner(parent or UIParent, "ANCHOR_CURSOR_RIGHT", 16, 0)
	end
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
	ApplyAll()
end

function M:OnDisable()
	unitColor = nil
	for _, tooltip in ipairs(TooltipList()) do
		RestoreBackdrop(tooltip)
	end
	ApplyHealthBar()
	ApplyScale()
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	ApplyAll()
end

MelloUI:Profile("Tooltip", "unit tooltips", OnUnitTooltip)
MelloUI:Profile("Tooltip", "health bar colour", ColorHealthBar)
