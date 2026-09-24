--------------------------------------------------------------------------------
-- MelloUI - Cast Bar Panel
--
-- The cast bars (the player's PlayerCastingBarFrame in both Edit Mode looks,
-- the overlay one, the pet's, the target's and focus' spell bars) dressed in
-- the painted kit (Modules/Kit.lua) on the game's own layout: the bar's
-- Border becomes the kit's cast bar bracket (gem-cluster caps) as regions of
-- the bar in the layer over its fill, its Background the bracket's trough,
-- the text box under the standalone bar a header plate, every glow / flake /
-- wisp effect faded and its animation stopped. User's picks
-- (kit_raw/castbar_catalog.png, 2026-09-21): C1 T1.
--   C1  the caps INSIDE the bar's width: the bracket's opening is the game's
--       bar, its caps stand outside it, and the bar is narrowed by the caps'
--       arms after each of the game's SetLook calls, so the whole still reads
--       the game's width (208 / 150). The spell icon moves out past the cap.
--   T1  lists/header on the 12 px under the bar (the text box's lower part).
-- Rules: docs/WINDOW-RULES.md 2d, docs/plans/hud_kit_plan.md section 1.
-- Covers the Dark Mode group "castbar" while on. /cbdump [player|pet|target|
-- focus|overlay] [frames|reps] prints a bar's art into the copy window.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("CastBarPanel")
local hooksecurefunc = Perf.hooksecurefunc
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("CastBarPanel", {
	title = "Cast Bars Kit",
	desc = "The cast bars dressed in the painted kit on the game's own layout.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local skin = nil
local active = false

local BARS = {
	player = function() return PlayerCastingBarFrame end,
	pet = function() return PetCastingBarFrame end,
	target = function() return TargetFrame and TargetFrame.spellbar end,
	focus = function() return FocusFrame and FocusFrame.spellbar end,
	overlay = function() return OverlayPlayerCastingBarFrame end,
}

-- The sizes the templates state, for the bars whose rects read SECRET under
-- a unit frame (TargetSpellBarTemplate: 150 x 10, the text box 12 px under)
local KNOWN = {
	target = { w = 150, h = 10, box = 12 },
	focus = { w = 150, h = 10, box = 12 },
}

-- the effect regions (parentKeys), all faded; their animation groups stopped
local FX_KEYS = { "InterruptGlow", "ChargeGlow", "EnergyGlow", "Flakes01", "Flakes02", "Flakes03", "BaseGlow", "WispGlow",
	"Sparkles01", "Sparkles02", "Shine", "StandardGlow", "CraftGlow", "ChannelShadow", "ChargeFlash" }
-- (not InterruptSparkAnim: the game fills an interrupted bar in that
-- animation's OnFinished, which a Stop never reaches; audit 2026-09-22)
local ANIM_KEYS = { "FlashLoopingAnim", "FlashAnim", "StageFlash", "StageFinish", "StandardFinish", "CraftingFinish",
	"ChannelFinish", "InterruptGlowAnim" }

local function Secret(v)
	return issecretvalue and issecretvalue(v) or false
end

local function Replace(region, opts)
	if not region then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Cast bars: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

local function Follow(rep, region)
	if not (rep and region) then
		return
	end
	local function Sync()
		if active then
			rep:SetShown(region:IsShown())
		end
	end
	hooksecurefunc(region, "Show", Sync)
	hooksecurefunc(region, "Hide", Sync)
	hooksecurefunc(region, "SetShown", Sync)
	skin.followers[#skin.followers + 1] = { rep = rep, region = region }
	Sync()
end

-- The bar narrowed by the bracket's arms (C1) after the game sizes it; the
-- icon moved out past the cap; both put back on disable.
local function Narrow(bar, rep, known)
	if not (active and rep and rep.GetArms) then
		return
	end
	pcall(function()
		local armL, armR = rep:GetArms()
		local okW, w = pcall(bar.GetWidth, bar)
		if not okW or Secret(w) or not (w and w > 0) then
			w = known and known.w
			if not w then
				return
			end
		end
		if bar.melloNarrow == nil then
			bar.melloNarrow = { width = w }
		elseif bar.melloNarrowed then
			-- already narrowed from this game width: measure from the saved one
			w = bar.melloNarrow.width
		end
		bar.melloNarrow.width = w
		bar.melloNarrowed = true
		bar:SetWidth(math.max(w - armL - armR, 20))
		if bar.Icon then
			if not bar.melloNarrow.icon then
				local points = {}
				for i = 1, bar.Icon:GetNumPoints() do
					points[i] = { bar.Icon:GetPoint(i) }
				end
				bar.melloNarrow.icon = points
			end
			-- from the game's own anchor (saved), never from the moved one
			local pt = bar.melloNarrow.icon[1]
			if pt and pt[1] and not Secret(pt[4]) then
				bar.Icon:ClearAllPoints()
				bar.Icon:SetPoint(pt[1], pt[2], pt[3], (pt[4] or 0) - armL, pt[5] or 0)
			end
		end
	end)
end

local function Widen(bar)
	local saved = bar.melloNarrow
	if not saved then
		return
	end
	local ok = pcall(function()
		bar:SetWidth(saved.width)
		if bar.Icon and saved.icon then
			bar.Icon:ClearAllPoints()
			for _, pt in ipairs(saved.icon) do
				bar.Icon:SetPoint(unpack(pt, 1, 5))
			end
		end
	end)
	if ok then
		bar.melloNarrow, bar.melloNarrowed = nil, nil
	end
end

local function SkinCastBar(bar, known)
	if not bar or skin.bars[bar] then
		return
	end
	if not (bar.Border and bar.GetStatusBarTexture) then
		return
	end
	skin.bars[bar] = true
	local first = #skin.reps + 1
	local layer, sublevel, troughLayer, troughSub = Kit:BracketLayers(bar)
	-- the bracket as regions of the bar on the bar's own rect (its opening),
	-- the caps outside; the Border faded; Bar Textures drops its mask
	local rep = Replace(bar.Border, { as = "ui-castingbar-frame", parent = bar, rect = bar,
		layer = layer, sublevel = sublevel, troughLayer = troughLayer, troughSub = troughSub,
		fitHeight = known and known.h, fitWidth = known and known.w })
	bar.melloRep = rep or false
	if rep then
		local textures = MelloUI:GetModule("BarTextures")
		rep.onEnable = function()
			bar.melloKitBracket = true
			if textures and textures.RefreshMask then
				textures:RefreshMask(bar)
			end
			Narrow(bar, rep, known)
		end
		rep.onDisable = function()
			bar.melloKitBracket = nil
			if textures and textures.RefreshMask then
				textures:RefreshMask(bar)
			end
			Widen(bar)
		end
		if active then
			rep.onEnable()
		end
		-- the game sizes the bar in SetLook (the two Edit Mode looks, the
		-- overlay look): narrow it again, refit the bracket
		if bar.SetLook then
			hooksecurefunc(bar, "SetLook", function()
				if active then
					bar.melloNarrowed = nil
					Kit:WhenOutOfCombat(function()
						Narrow(bar, rep, known)
						rep:Refit()
					end)
				end
			end)
		end
		Perf.HookScript(bar, "OnSizeChanged", function()
			if active and not bar.melloRefitting then
				bar.melloRefitting = true
				rep:Refit()
				bar.melloRefitting = nil
			end
		end)
	end
	Replace(bar.Background, { as = "ui-castingbar-background" })
	Replace(bar.Flash, { as = "ui-castingbar-full-glow-standard" })
	Replace(bar.DropShadow, { as = "castbar_shadow_embedded" })
	for _, key in ipairs(FX_KEYS) do
		Replace(bar[key], { as = "CastBarFX" })
	end
	-- the effects' animations set alpha through the animation system, past
	-- the fade hook: stopped as soon as the game plays them
	for _, key in ipairs(ANIM_KEYS) do
		local anim = bar[key]
		if anim and anim.Play and not anim.melloStopHook then
			anim.melloStopHook = true
			hooksecurefunc(anim, "Play", function(a)
				if active then
					a:Stop()
				end
			end)
		end
	end
	-- T1: the text box's lower part (from the bar's bottom to the box's
	-- bottom) as the header plate, following the game's show / hide of the box
	if bar.TextBorder then
		local sizer = CreateFrame("Frame", nil, bar)
		sizer:EnableMouse(false)
		sizer:SetPoint("TOPLEFT", bar, "BOTTOMLEFT")
		sizer:SetPoint("BOTTOMRIGHT", bar.TextBorder, "BOTTOMRIGHT")
		local plate = Replace(bar.TextBorder, { as = "ui-castingbar-textbox", rect = sizer,
			fitHeight = known and known.box, fitWidth = known and known.w })
		Follow(plate, bar.TextBorder)
	end
	-- the bar is hidden at load and its regions have no rect until it first
	-- shows: fit this bar's pieces again whenever it shows
	local last = #skin.reps
	Perf.HookScript(bar, "OnShow", function()
		if active then
			Kit:WhenOutOfCombat(function()
				for i = first, last do
					local piece = skin.reps[i]
					if piece and piece.Refit then
						piece:Refit()
					end
				end
			end)
		end
	end)
end

local function Build()
	if not skin then
		skin = { reps = {}, followers = {}, bars = {} }
	end
	for key, getter in pairs(BARS) do
		SkinCastBar(getter(), KNOWN[key])
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
	for _, entry in ipairs(skin.followers) do
		entry.rep:SetShown(entry.region:IsShown())
	end
	Kit:Cover("castbar")
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	Kit:Uncover("castbar")
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

function M:OnEnable(db)
	self.db = db
	if PlayerCastingBarFrame then
		Kit:WhenOutOfCombat(Activate)
	end
end

function M:OnDisable()
	Kit:WhenOutOfCombat(Deactivate)
end

--------------------------------------------------------------------------------
-- /cbdump [player|pet|target|focus|overlay] [frames|reps]: a bar's art
-- (regions by default). Opens the copy window.
--------------------------------------------------------------------------------
SLASH_MELLOCBDUMP1 = "/cbdump"
SlashCmdList.MELLOCBDUMP = function(msg)
	msg = (msg or ""):lower()
	local which, mode = msg:match("^(%a*)%s*(%a*)$")
	if which == "frames" or which == "reps" then
		which, mode = "", which
	end
	local keys = which ~= "" and { which } or { "player", "target" }
	MelloUI:ClearLog()
	for _, key in ipairs(keys) do
		local getter = BARS[key]
		local bar = getter and getter()
		if not bar then
			MelloUI:Print("%s: no such bar (player, pet, target, focus, overlay)", key)
		else
			local ok, w, h = pcall(bar.GetSize, bar)
			MelloUI:Print("== %s (%s) %s x %s  %s L%d %s look=%s", key, bar:GetName() or "?", ok and not Secret(w) and string.format("%.0f", w) or "?",
				ok and not Secret(h) and string.format("%.0f", h) or "?", bar:GetFrameStrata(), bar:GetFrameLevel(), bar:IsShown() and "shown" or "hidden", tostring(bar.look))
			Kit:DumpWindow(bar, skin, mode ~= "" and mode or nil)
		end
	end
	MelloUI:ShowLog("cbdump " .. msg)
end
