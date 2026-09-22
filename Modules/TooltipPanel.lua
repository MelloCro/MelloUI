--------------------------------------------------------------------------------
-- MelloUI - Tooltip Panel
--
-- Every tooltip built on SharedTooltipTemplate (GameTooltip, ItemRefTooltip,
-- the shopping / comparison tooltips, embedded item tooltips ...) dressed in
-- the painted kit (Modules/Kit.lua) on the game's own layout, by the user's
-- pick (kit_raw/tooltip_catalog.png, 2026-09-21):
--   TT1: the tooltip's NineSlice (the TooltipDefaultLayout pieces, and
--   whatever layout the game swaps in) -> the single rail with the list-box
--   stone, as REGIONS of the NineSlice in its own layers; the texts, item
--   icons and comparison headers stay the game's.
--   The unit health bar under a unit tooltip (GameTooltipStatusBar, a
--   StatusBar with no border art of its own): the P1 bracket around it with
--   the caps outside, the bar set in by the arms — an agreed addition, as the
--   catalogue showed it.
-- Tooltips are styled by the game on every show (SharedTooltip_SetBackdropStyle):
-- that call is the hook that catches every tooltip the first time.
-- Covers the group "tooltip": the Tooltip tweak module's backdrop colouring
-- acts only while this module is off. /ttdump [frames|reps].
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("TooltipPanel", {
	title = "Tooltip Kit",
	desc = "Tooltips dressed in the painted kit: the stone box with the single rail, the unit health bar in the bracket.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local skin = nil
local active = false

local function Secret(v)
	return issecretvalue and issecretvalue(v)
end

local function Replace(region, opts)
	if not region then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Tooltip: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

local PIECES = { "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" }

-- The health bar set in from its anchors by the bracket's arms (a
-- StatusBar's fill cannot be re-anchored): once per game layout.
local function InsetBar(bar, rep)
	if not (bar and rep and rep.GetArms) or bar.melloInset then
		return
	end
	local okN, n = pcall(bar.GetNumPoints, bar)
	if not okN or Secret(n) or not n then
		return
	end
	local points = {}
	for i = 1, n do
		local ok, point, rel, relPoint, x, y = pcall(bar.GetPoint, bar, i)
		if not ok or Secret(point) or Secret(x) or Secret(y) or not point then
			return
		end
		points[i] = { point, rel, relPoint, x or 0, y or 0 }
	end
	bar.melloInset = points
	local armL, armR = rep:GetArms()
	bar:ClearAllPoints()
	for _, pt in ipairs(points) do
		local point, rel, relPoint, x, y = unpack(pt)
		if point:find("LEFT") then
			x = x + armL
		elseif point:find("RIGHT") then
			x = x - armR
		end
		bar:SetPoint(point, rel, relPoint, x, y)
	end
end

local function RestoreBar(bar)
	local points = bar and bar.melloInset
	if not points then
		return
	end
	bar.melloInset = nil
	bar:ClearAllPoints()
	for _, pt in ipairs(points) do
		bar:SetPoint(unpack(pt))
	end
end

local function SkinTooltip(tip)
	if not (tip and tip.NineSlice) or tip.melloKit then
		return
	end
	tip.melloKit = true
	local nine = tip.NineSlice
	local corner = nine.TopLeftCorner
	if corner then
		local others = {}
		for _, key in ipairs(PIECES) do
			others[#others + 1] = nine[key]
		end
		Replace(corner, { as = "Tooltip-NineSlice-CornerTopLeft", rect = nine, alsoFade = others })
	end
	local bar = tip.StatusBar
	if bar and bar.GetStatusBarTexture then
		local layer, sublevel, troughLayer, troughSub = Kit:BracketLayers(bar)
		local rep = Replace(bar, { as = "TooltipStatusBar", parent = bar, rect = bar, noFade = true,
			layer = layer, sublevel = sublevel, troughLayer = troughLayer, troughSub = troughSub })
		if rep then
			local enable, disable = rep.onEnable, rep.onDisable
			rep.onEnable = function(...)
				if enable then
					enable(...)
				end
				InsetBar(bar, rep)
			end
			rep.onDisable = function(...)
				if disable then
					disable(...)
				end
				RestoreBar(bar)
			end
			bar:HookScript("OnShow", function()
				if active then
					InsetBar(bar, rep)
					rep:Refit()
				end
			end)
			if active then
				InsetBar(bar, rep)
			end
		end
	end
end

local KNOWN = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2",
	"EmbeddedItemTooltip", "GameSmallHeaderTooltip", "FriendsTooltip" }

local function Build()
	if skin then
		return
	end
	skin = { reps = {}, followers = {} }
	for _, name in ipairs(KNOWN) do
		local tip = _G[name]
		if tip then
			SkinTooltip(tip)
			if tip.Tooltip then
				SkinTooltip(tip.Tooltip)
			end
		end
	end
	if SharedTooltip_SetBackdropStyle then
		hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tip)
			if active then
				SkinTooltip(tip)
			end
		end)
	end
end

local function Activate()
	if active then
		return
	end
	active = true
	Build()
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	Kit:Cover("tooltip")
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	Kit:Uncover("tooltip")
end

function M:OnEnable(db)
	self.db = db
	Activate()
end

function M:OnDisable()
	Deactivate()
end

--------------------------------------------------------------------------------
-- /ttdump [frames|reps]: the GameTooltip's art (hover something, then type
-- it: the tooltip is dumped as last shown). Opens the copy window.
--------------------------------------------------------------------------------
SLASH_MELLOTTDUMP1 = "/ttdump"
SlashCmdList.MELLOTTDUMP = function(msg)
	msg = (msg or ""):lower()
	MelloUI:ClearLog()
	if not GameTooltip then
		MelloUI:Print("No tooltip.")
	else
		Kit:DumpWindow(GameTooltip, skin, msg ~= "" and msg or nil)
	end
	MelloUI:ShowLog("ttdump " .. msg)
end
