--------------------------------------------------------------------------------
-- MelloUI - Unit Frame Panel
--
-- The player, target, focus, pet and target-of-target frames dressed in the
-- painted kit (Modules/Kit.lua) on the game's own layout: the game's single
-- frame picture (UI-HUD-UnitFrame-*-PortraitOn: ring, name band, both bar
-- rims in one texture) is faded and kit pieces stand on the game's own
-- sub-rects, as regions / children of the frames they replace, so they follow
-- Edit Mode's scale and the game's art swaps (vehicle, elite / rare rings,
-- the minus-mob bar). Rules: docs/WINDOW-RULES.md + docs/plans/hud_kit_plan.md
-- section 1 (secure frames: geometry out of combat only; secret values: every
-- read guarded). User's picks (kit_raw/unitframe_catalog.png, 2026-09-21):
--   B3  the P1 bracket on each bar, capless on the ring side, the far gem cap
--       grown outward, the fill on the whole rect behind it
--   R1  window/portrait_ring with its OPENING on the game's portrait rect
--   L1  buttons/orb under the level number (and the PvP badge's circle)
--   N3  the tabs/top title plate on the name band (the target's reaction
--       strip; the player's band is that rect mirrored)
-- The elite / rare / boss rings are faded and the kit ring is tinted gold /
-- silver instead. Bar Textures drops its shaped mask on a bracketed bar
-- (`melloKitBracket`) so the flat fill spans the rect under the rails.
-- Covers the Dark Mode group "unitframes" while on (Kit:Cover).
-- /ufdump [player|target|focus|pet|tot|party|party1] [frames|reps] prints a frame's
-- art into the copy window.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("UnitFramePanel")
local hooksecurefunc = Perf.hooksecurefunc
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("UnitFramePanel", {
	title = "Unit Frames Kit",
	desc = "The player, target, focus and pet frames dressed in the painted kit on the game's own layout.",
	window = { label = "Unit frames", desc = "Player, target, focus, pet and party frames in the kit.", tab = "HUD" },
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local skin = nil
local active = false
local hooked = false

local FRAMES = {
	player = function() return PlayerFrame end,
	target = function() return TargetFrame end,
	focus = function() return FocusFrame end,
	pet = function() return PetFrame end,
	tot = function() return TargetFrame and TargetFrame.totFrame end,
	party = function() return PartyFrame end,
	party1 = function() return PartyFrame and PartyFrame.GetPartyMemberFrame and PartyFrame:GetPartyMemberFrame(1) end,
}

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret

local function Replace(region, opts)
	if not region then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Unit frames: no kit piece mapped for %s", tostring(key))
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

-- The game's frame picture and its decorative variants, faded (one rep each).
local function FadeArt(list)
	for _, entry in ipairs(list) do
		local region, key = entry[1], entry[2]
		if region then
			Replace(region, { as = key })
		end
	end
end

-- A bar's bracket (B3): regions of the bar itself in the layer over its
-- fill, fitted to `rect`; Bar Textures told to drop its mask.
local function SkinBar(bar, rect, picture, mirrored, health)
	if not (bar and rect and picture) or bar.melloRep ~= nil then
		return bar and bar.melloRep or nil
	end
	local layer, sublevel, troughLayer, troughSub = Kit:BracketLayers(bar)
	-- a health bar keeps its end gem red (UnitFrameHealthBar), the others are iron
	local key = (health and "UnitFrameHealthBar" or "UnitFrameBar") .. (mirrored and "Mirrored" or "")
	local rep = Replace(picture, { as = key, parent = bar, rect = rect, noFade = true,
		layer = layer, sublevel = sublevel, troughLayer = troughLayer, troughSub = troughSub })
	bar.melloRep = rep or false
	if not rep then
		return nil
	end
	local textures = MelloUI:GetModule("BarTextures")
	rep.onEnable = function()
		bar.melloKitBracket = true
		if textures and textures.RefreshMask then
			textures:RefreshMask(bar)
		end
	end
	rep.onDisable = function()
		bar.melloKitBracket = nil
		if textures and textures.RefreshMask then
			textures:RefreshMask(bar)
		end
	end
	if active then
		rep.onEnable()
	end
	-- the rect changes with the game's own re-layouts (the target's minus-mob bar)
	Perf.HookScript(rect, "OnSizeChanged", function()
		if active then
			Kit:WhenOutOfCombat(function() rep:Refit() end)
		end
	end)
	return rep
end

-- The ring's width and the portrait's size, as the client reads them back;
-- nothing where one is secret on this client
local function ReadFit(ring, portrait)
	local rw = ring.tex:GetWidth()
	local w, h = portrait:GetSize()
	if Secret(rw) or Secret(w) or Secret(h) then
		return nil
	end
	return rw, w, h
end

-- [portrait] = its refit, for the SetPortraitTexture hook (a side table: no
-- field of the game's portrait written)
local refits = setmetatable({}, { __mode = "k" })

-- The ring (R1) as a region in the faded picture's layer, its opening on the
-- portrait; the portrait (and a mask with its own anchors) then fitted to
-- the medallion size in the ring (rule 2b: 0.759 x the ring, so the class
-- medallion's disc fills the opening and a render sits under the rim), the
-- plain medallion variant asked of Class Icons. Returns the rep.
local function SkinRing(picture, portrait, mask, key)
	local rep = Replace(picture, { as = key or "UnitFramePortraitRing", rect = portrait, noFade = true })
	if not rep then
		return nil
	end
	local icons = MelloUI:GetModule("ClassIcons")
	-- the portrait (and a mask with its own anchors: the player's) fitted to
	-- the medallion size in the ring, 0.759 x the ring (rule 2b), the disc's
	-- edge tucked under the bezel — the user's choice on sight (2026-09-21;
	-- "the disc exactly the opening" was tried and put back). What the fit
	-- left is kept: the ring's width and the portrait's size as read back
	-- (a read-back compared with a read-back is exact)
	local fitRing, fitW, fitH
	local function Fit()
		pcall(Kit.FitPortrait, Kit, portrait, rep)
		if mask then
			pcall(Kit.FitPortrait, Kit, mask, rep)
		end
		fitRing, fitW, fitH = nil, nil, nil
		if portrait.melloSaved then
			local ok, rw, w, h = pcall(ReadFit, rep, portrait)
			if ok and rw then
				fitRing, fitW, fitH = rw, w, h
			end
		end
	end
	-- Still as the last fit left it: fitted (its mask too), the ring the
	-- same width, the portrait the same size. The size alone depends on the
	-- ring's width (Fit passes no mode: 0.759 x the ring whatever the
	-- texture, a render or the medallion), and the game never re-anchors a
	-- portrait (only its art swaps re-size it, which this sees)
	local function Fitted()
		if not (fitRing and portrait.melloSaved) or (mask and not mask.melloSaved) then
			return false
		end
		local ok, rw, w, h = pcall(ReadFit, rep, portrait)
		return ok and rw == fitRing and w == fitW and h == fitH
	end
	rep.onEnable = function()
		portrait.melloKitRing = true
		if icons and icons.RefreshPortraits then
			icons:RefreshPortraits({ portrait })
		end
		Fit()
	end
	rep.onDisable = function()
		portrait.melloKitRing = nil
		pcall(Kit.UnfitPortrait, Kit, portrait)
		if mask then
			pcall(Kit.UnfitPortrait, Kit, mask)
		end
		if icons and icons.RefreshPortraits then
			icons:RefreshPortraits({ portrait })
		end
	end
	if active then
		rep.onEnable()
	end
	-- the game re-sizes the portrait with its art swaps and re-sets its
	-- texture on every portrait update: fitted again when that moved it.
	-- The target of target re-sets its portrait on EVERY frame (its
	-- OnUpdate runs UnitFrame_Update, 41 a second in /melloperf 2026-09-24,
	-- and Class Icons' medallion re-sets it once more): nothing is made per
	-- call (one fit function per portrait, queued as it is in combat) and a
	-- portrait still as its last fit left it costs three reads. `fitting`
	-- covers the fit's own SetSize coming back through the hook, and a fit
	-- already queued for the fight's end.
	local fitting = false
	local function RefitNow()
		if active then
			Fit()
		end
		fitting = false
	end
	local function Refit()
		if active and not fitting and not Fitted() then
			fitting = true
			Kit:WhenOutOfCombat(RefitNow)
		end
	end
	hooksecurefunc(portrait, "SetSize", Refit)
	hooksecurefunc(portrait, "SetTexture", Refit)
	refits[portrait] = Refit
	return rep
end

-- The bars END UNDER THE RING'S RIM (user, 2026-09-21: "start on or end at
-- the border, the border covering a small portion"): the game runs a bar's
-- ring-side end into the ring's opening (the target's power bar 8 px past
-- its health bar, the DF art tucked it under its own ring), which would
-- draw over the portrait. Each bar's ring-side edge is re-anchored to a
-- point TUCK UI px under the rim's OUTER edge (2 px, so the fill stays
-- readable to its very end — user, 2026-09-21: an end hidden under the rim
-- hides the last per cent of health; the game's own start, 18 px under the
-- rim, did), its far edge
-- and height kept, relative to the frame its own anchor names (so it still
-- follows the game's re-anchoring of that frame); the bar's own anchors are
-- saved and put back on disable (part of the replaced element's geometry,
-- law 5). Re-applied after the game's art swaps.
local TUCK = 2
local tucked = {}          -- bars with saved anchors (re-anchored at least once)
local tuckable = {}        -- every bar registered (a hidden frame's bars get their first tuck later)

local function TuckBar(bar, ring, mirrored)
	local tex = ring and ring.tex
	if not (bar and tex) then
		return
	end
	local ok = pcall(function()
		local rl, rb, rw, rh = tex:GetRect()
		local piece = tex.kitPiece
		if not (rl and piece and piece.box) then
			return
		end
		local l, b, w, h = bar:GetRect()
		if not l then
			return
		end
		-- the ring is ROUND: its outer edge at the bar's height, taken at the
		-- bar's edge farthest from the ring's centre so the whole end is under
		-- the rim (the bars follow the curve, as the painting has them)
		local cx, cy = rl + rw / 2, rb + rh / 2
		-- the ring's BODY radius (KitLayout `radius`: measured off the compass
		-- gems, which stick out past the body), else the box
		local radius = rw * (piece.radius or (piece.box[3] - piece.box[1]) / 2) / piece.w
		local dy = math.max(math.abs(b - cy), math.abs(b + h - cy))
		if dy >= radius then
			return
		end
		local reach = math.sqrt(radius * radius - dy * dy)
		local tuckX = mirrored and (cx - reach + TUCK) or (cx + reach - TUCK)
		if not bar.melloTuck then
			local points = {}
			for i = 1, bar:GetNumPoints() do
				points[i] = { bar:GetPoint(i) }
			end
			bar.melloTuck = { points = points, w = w, h = h }
			tucked[#tucked + 1] = bar
		end
		local _, rel = bar:GetPoint(1)
		rel = rel or bar:GetParent()
		local pl, pb, _, ph = rel:GetRect()
		if not pl then
			return
		end
		local top = pb + ph
		local left, right = l, l + w
		if mirrored then
			right = math.min(right, tuckX)
		else
			left = math.max(left, tuckX)
		end
		if right - left < 4 then
			return
		end
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", rel, "TOPLEFT", left - pl, -(top - (b + h)))
		bar:SetPoint("BOTTOMRIGHT", rel, "TOPLEFT", right - pl, -(top - b))
	end)
	return ok
end

local function TuckBars(ring, bars, mirrored)
	if not ring then
		return
	end
	for _, bar in ipairs(bars) do
		if bar then
			bar.melloRetuck = function()
				if active then
					TuckBar(bar, ring, mirrored)
				end
			end
			tuckable[#tuckable + 1] = bar
			TuckBar(bar, ring, mirrored)
		end
	end
end

local function UntuckBars()
	local kept = {}
	for _, bar in ipairs(tucked) do
		local saved = bar.melloTuck
		if saved then
			local ok = pcall(function()
				bar:ClearAllPoints()
				for _, pt in ipairs(saved.points) do
					bar:SetPoint(unpack(pt, 1, 5))
				end
				bar:SetSize(saved.w, saved.h)
			end)
			if ok then
				bar.melloTuck = nil
			else
				-- refused (the bars are protected; in combat): the game's
				-- anchors stay saved for the next untuck
				kept[#kept + 1] = bar
			end
		end
	end
	tucked = kept
end

local function RetuckAll()
	for _, bar in ipairs(tuckable) do
		if bar.melloRetuck then
			bar.melloRetuck()
		end
	end
end

-- The ring drawn OVER the bars' ring-side ends (user, 2026-09-21: the bars
-- start under the border and the border covers a little of them). The ring
-- is a region under the bar frames, so its own pixels are drawn once more
-- on a holder one level above the bars, cropped to the strip where the bars
-- meet it (the bars' vertical span, from their ring-side edge to the ring's
-- far edge) — a stacking cover like the rail junction covers, not a new
-- element. Follows the ring's tint. Re-laid with the bars.
local function RingCover(ring, bars, mirrored, container)
	if not (ring and ring.tex and container and #bars > 0) then
		return nil
	end
	local tex = ring.tex
	local holder = CreateFrame("Frame", nil, container)
	holder:EnableMouse(false)
	local cover = holder:CreateTexture(nil, "ARTWORK")
	cover.kitPiece = true
	Kit:Apply(cover, tex.kitName)
	cover:SetAllPoints(holder)
	local function Refit()
		if not (active and tex:IsShown()) then
			holder:Hide()
			return
		end
		local ok = pcall(function()
			local level = 0
			for _, bar in ipairs(bars) do
				level = math.max(level, bar:GetFrameLevel())
			end
			holder:SetFrameLevel(level + 1)
			local rl, rb, rw, rh = tex:GetRect()
			local top, bottom, edge
			for _, bar in ipairs(bars) do
				local l, b, w, h = bar:GetRect()
				top = math.max(top or -math.huge, b + h)
				bottom = math.min(bottom or math.huge, b)
				local e = mirrored and (l + w) or l
				if edge == nil then
					edge = e
				else
					edge = mirrored and math.max(edge, e) or math.min(edge, e)
				end
			end
			local cl, cr
			if mirrored then
				cl, cr = rl, math.min(edge, rl + rw)
			else
				cl, cr = math.max(edge, rl), rl + rw
			end
			local ct, cb = math.min(top, rb + rh), math.max(bottom, rb)
			if cr <= cl or ct <= cb then
				holder:Hide()
				return
			end
			holder:ClearAllPoints()
			holder:SetPoint("TOPLEFT", tex, "TOPLEFT", cl - rl, -(rb + rh - ct))
			holder:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", -(rl + rw - cr), cb - rb)
			local piece = tex.kitPiece
			local u1, u2, v1, v2 = piece.uv[1], piece.uv[2], piece.uv[3], piece.uv[4]
			local fx0, fx1 = (cl - rl) / rw, (cr - rl) / rw
			local fy0, fy1 = (rb + rh - ct) / rh, (rb + rh - cb) / rh
			cover:SetTexCoord(u1 + (u2 - u1) * fx0, u1 + (u2 - u1) * fx1, v1 + (v2 - v1) * fy0, v1 + (v2 - v1) * fy1)
			local r, g, b = tex:GetVertexColor()
			cover:SetVertexColor(r or 1, g or 1, b or 1)
			holder:Show()
		end)
		if not ok then
			holder:Hide()
		end
	end
	for _, bar in ipairs(bars) do
		Perf.HookScript(bar, "OnSizeChanged", function()
			Kit:WhenOutOfCombat(Refit)
		end)
	end
	hooksecurefunc(tex, "SetVertexColor", function()
		if holder:IsShown() then
			pcall(function()
				local r, g, b = tex:GetVertexColor()
				cover:SetVertexColor(r or 1, g or 1, b or 1)
			end)
		end
	end)
	ring.cover = { holder = holder, Refit = Refit }
	skin.covers[#skin.covers + 1] = ring.cover
	Refit()
	return ring.cover
end

-- The name centred on its plate (N3, as the title on a window's title
-- plate): the game's anchors saved and put back on disable.
local function CenterName(fs, rect)
	if not (fs and rect) then
		return
	end
	if not fs.melloSavedName then
		local points = {}
		for i = 1, fs:GetNumPoints() do
			points[i] = { fs:GetPoint(i) }
		end
		fs.melloSavedName = { points = points, width = fs:GetWidth(), justify = fs:GetJustifyH() }
	end
	local function Place()
		if not active then
			return
		end
		fs:ClearAllPoints()
		fs:SetPoint("CENTER", rect, "CENTER", 0, 0)
		local ok, w = pcall(rect.GetWidth, rect)
		if ok and not Secret(w) and w and w > 0 then
			fs:SetWidth(w)
		end
		fs:SetJustifyH("CENTER")
	end
	Place()
	skin.names[#skin.names + 1] = { fs = fs, place = Place }
end

local function RestoreNames()
	for _, entry in ipairs(skin.names) do
		local fs, saved = entry.fs, entry.fs.melloSavedName
		if saved then
			fs:ClearAllPoints()
			for _, pt in ipairs(saved.points) do
				fs:SetPoint(unpack(pt))
			end
			if saved.width and saved.width > 0 then
				fs:SetWidth(saved.width)
			end
			fs:SetJustifyH(saved.justify or "LEFT")
			fs.melloSavedName = nil
		end
	end
end

-- The name band plate (N3) as a region in the faded picture's layer (so the
-- ring, made after it, draws over its end), on `rect`.
local function SkinBand(picture, rect)
	return Replace(picture, { as = "UnitFrameNameBand", rect = rect, noFade = true })
end

-- The level / PvP circle (L1): the orb under the frame's own text, following
-- the game's show / hide.
local function SkinCircle(circle)
	if not circle then
		return
	end
	Follow(Replace(circle, { as = "UI-HUD-UnitFrame-SmallCircle" }), circle)
end

-- The player's name band rect: the target's reaction strip mirrored (same
-- size, anchored from the left edge as the target's is from the right).
local function PlayerBandRect(container)
	local band = TargetFrame and TargetFrame.TargetFrameContent and TargetFrame.TargetFrameContent.TargetFrameContentMain
		and TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
	if not band then
		return nil
	end
	local ok, w, h = pcall(band.GetSize, band)
	if not ok or Secret(w) or Secret(h) or not (w and w > 0 and h and h > 0) then
		return nil
	end
	local okP, _, _, _, x, y = pcall(band.GetPoint, band, 1)
	if not okP or Secret(x) or Secret(y) then
		x, y = -75, -25
	end
	local f = CreateFrame("Frame", nil, container)
	f:EnableMouse(false)
	f:SetSize(w, h)
	f:SetPoint("TOPLEFT", container, "TOPLEFT", -x, y)
	return f
end

--------------------------------------------------------------------------------
-- The frames
--------------------------------------------------------------------------------

local function SkinPlayer()
	local pf = PlayerFrame
	if not pf or skin.player then
		return
	end
	local container = pf.PlayerFrameContainer
	local main = pf.PlayerFrameContent and pf.PlayerFrameContent.PlayerFrameContentMain
	local contextual = pf.PlayerFrameContent and pf.PlayerFrameContent.PlayerFrameContentContextual
	if not (container and main and container.FrameTexture) then
		return
	end
	skin.player = true
	local picture = container.FrameTexture
	FadeArt({
		{ picture, "UI-HUD-UnitFrame-Player-PortraitOn" },
		{ container.VehicleFrameTexture, "UI-HUD-UnitFrame-Player-PortraitOn-Vehicle" },
		{ container.AlternatePowerFrameTexture, "UI-HUD-UnitFrame-Player-PortraitOn-ClassResource" },
		{ container.FrameFlash, "UI-HUD-UnitFrame-Player-PortraitOn-InCombat" },
		{ main.StatusTexture, "UI-HUD-UnitFrame-Player-PortraitOn-Status" },
		{ contextual and contextual.PlayerPortraitCornerIcon, "UI-HUD-UnitFrame-Player-PortraitOn-CornerEmbellishment" },
	})
	-- the band before the ring: both in the picture's layer, the ring over it
	local band = PlayerBandRect(container)
	SkinBand(picture, band)
	CenterName(PlayerName, band)
	skin.playerRing = SkinRing(picture, container.PlayerPortrait, container.PlayerPortraitMask)
	local health = main.HealthBarsContainer and main.HealthBarsContainer.HealthBar
	SkinBar(health, health, picture, false, true)
	local mana = main.ManaBarArea and main.ManaBarArea.ManaBar
	SkinBar(mana, mana, picture, false)
	TuckBars(skin.playerRing, { health, mana }, false)
	RingCover(skin.playerRing, { health, mana }, false, container)
	SkinCircle(main.LevelBackgroundCircle)
	SkinCircle(main.PvpBackgroundCircle)
end

-- A target-style frame (TargetFrame, FocusFrame): mirrored, the reaction
-- strip is the name band, the boss ring tints the kit ring.
local function SkinTargetLike(frame)
	if not frame or (skin.targets[frame]) then
		return
	end
	local container = frame.TargetFrameContainer
	local main = frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentMain
	local contextual = frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentContextual
	if not (container and main and container.FrameTexture) then
		return
	end
	local picture = container.FrameTexture
	FadeArt({
		{ picture, "UI-HUD-UnitFrame-Target-PortraitOn" },
		{ container.Flash, "UI-HUD-UnitFrame-Target-PortraitOn-InCombat" },
		{ container.BossPortraitFrameTexture, "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold" },
	})
	if main.ReputationColor then
		Replace(main.ReputationColor, { as = "UI-HUD-UnitFrame-Target-PortraitOn-Type" })
		SkinBand(picture, main.ReputationColor)
		CenterName(main.Name, main.ReputationColor)
	end
	local ring = SkinRing(picture, container.Portrait)   -- its mask follows the portrait's anchors
	local health = main.HealthBarsContainer and main.HealthBarsContainer.HealthBar
	SkinBar(health, health, picture, true, true)
	SkinBar(main.ManaBar, main.ManaBar, picture, true)
	TuckBars(ring, { health, main.ManaBar }, true)
	RingCover(ring, { health, main.ManaBar }, true, container)
	SkinCircle(main.LevelBackgroundCircle)
	SkinCircle(contextual and contextual.PvpBackgroundCircle)
	skin.targets[frame] = { ring = ring, boss = container.BossPortraitFrameTexture }
	-- the boss ring's atlas (gold / silver) tints the kit ring; plain otherwise
	local function Tint()
		if not (active and ring and ring.tex) then
			return
		end
		local boss = container.BossPortraitFrameTexture
		local key = boss and boss:IsShown() and Kit:ArtKey(boss) or nil
		key = type(key) == "string" and key:lower() or ""
		if key:find("silver", 1, true) then
			ring.tex:SetVertexColor(0.85, 0.9, 1)
		elseif key:find("gold", 1, true) then
			ring.tex:SetVertexColor(1, 0.82, 0.35)
		else
			ring.tex:SetVertexColor(1, 1, 1)
		end
	end
	-- the game re-anchors the health container and re-atlases the art on
	-- every target change (CheckClassification): re-tint, re-fit the
	-- brackets and re-lay the ring cover (the bars' positions moved)
	if frame.CheckClassification then
		hooksecurefunc(frame, "CheckClassification", function()
			Kit:WhenOutOfCombat(function()
				Tint()
				RetuckAll()
				for _, rep in ipairs(skin.reps) do
					if rep.kind == "bar" and rep.object:GetParent() and rep.rect and rep.object:GetParent():IsShown() then
						rep:Refit()
					end
				end
				for _, cover in ipairs(skin.covers) do
					cover.Refit()
				end
			end)
		end)
	end
	Perf.HookScript(frame, "OnShow", function()
		Kit:WhenOutOfCombat(function()
			RetuckAll()
			for _, cover in ipairs(skin.covers) do
				cover.Refit()
			end
		end)
	end)
	Tint()
	skin.targets[frame].tint = Tint
	-- the target of target: a small frame with the same parts
	local tot = frame.totFrame
	if tot and tot.FrameTexture and not skin.targets[tot] then
		skin.targets[tot] = true
		FadeArt({
			{ tot.FrameTexture, "UI-HUD-UnitFrame-TargetofTarget-PortraitOn" },
		})
		local totRing = SkinRing(tot.FrameTexture, tot.Portrait)
		SkinBar(tot.HealthBar, tot.HealthBar, tot.FrameTexture, false, true)
		SkinBar(tot.ManaBar, tot.ManaBar, tot.FrameTexture, false)
		TuckBars(totRing, { tot.HealthBar, tot.ManaBar }, false)
		RingCover(totRing, { tot.HealthBar, tot.ManaBar }, false, tot)
	end
end

local function SkinPet()
	local pf = PetFrame
	if not pf or skin.pet or not (PetFrameTexture and pf.Portrait) then
		return
	end
	skin.pet = true
	FadeArt({
		{ PetFrameTexture, "UI-HUD-UnitFrame-TargetofTarget-PortraitOn" },
		{ PetFrameFlash, "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-InCombat" },
		{ PetAttackModeTexture, "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Status" },
	})
	local petRing = SkinRing(PetFrameTexture, pf.Portrait)
	SkinBar(PetFrameHealthBar, PetFrameHealthBar, PetFrameTexture, false, true)
	SkinBar(PetFrameManaBar, PetFrameManaBar, PetFrameTexture, false)
	TuckBars(petRing, { PetFrameHealthBar, PetFrameManaBar }, false)
	RingCover(petRing, { PetFrameHealthBar, PetFrameManaBar }, false, pf)
end

--------------------------------------------------------------------------------
-- The party frames (PartyFrame's pooled PartyMemberFrameTemplate, 120 x 53:
-- the picture is a region of the member frame at ARTWORK 0 with the name
-- after it, the portrait at BACKGROUND; the ring and the name plate go to
-- BACKGROUND above the portrait, under the name; the bars as on the player
-- frame; the member's pet frame the same at half size). The frames are
-- re-acquired from the pool on every show: skinned from that hook.
--------------------------------------------------------------------------------

-- The name band's rect: the player's band geometry on the member frame
-- (user, 2026-09-21: the same name background as on the player frame) —
-- the band's height (the target's reaction strip, 18 px), centred on the
-- name's line, from the name's left edge to the health bar's right edge.
local function NameBandRect(frame, name, health)
	local okP, point, _, _, x, y = pcall(name.GetPoint, name, 1)
	if not okP or Secret(point) or point ~= "TOPLEFT" or Secret(x) or Secret(y) then
		return nil
	end
	local ok, nameH = pcall(name.GetHeight, name)
	nameH = (ok and not Secret(nameH) and nameH and nameH > 0) and nameH or 12
	local band = TargetFrame and TargetFrame.TargetFrameContent and TargetFrame.TargetFrameContent.TargetFrameContentMain
		and TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
	local okB, bandH = pcall(function() return band and band:GetHeight() end)
	bandH = (okB and not Secret(bandH) and bandH and bandH > 0) and bandH or 18
	-- scaled to the frame: the party portrait (37) against the player's (60)
	local okR, ratio = pcall(function()
		local pp = PlayerFrame.PlayerFrameContainer.PlayerPortrait
		local saved = pp.melloSaved
		local pw = saved and saved.w or pp:GetWidth()
		local mine = frame.Portrait.melloSaved and frame.Portrait.melloSaved.w or frame.Portrait:GetWidth()
		return mine / pw
	end)
	if okR and ratio and not Secret(ratio) and ratio > 0 and ratio < 1 then
		bandH = bandH * ratio
	end
	bandH = bandH * 1.2       -- user, 2026-09-21: a fifth larger than the frame's proportion
	local f = CreateFrame("Frame", nil, frame)
	f:EnableMouse(false)
	-- the name's TOPLEFT (x, y) on the frame; the band centred on its line,
	-- at least as wide as the plate's two rune caps at that height (user,
	-- 2026-09-21: the caps must show, as on the player frame), else to the
	-- health bar's right edge
	local layout = MelloUI_KitLayout and MelloUI_KitLayout.pieces
	local mid = layout and layout[Kit:StripPieceName("tabs/top", "mid", "title")]
	local cap = layout and layout[Kit:StripPieceName("tabs/top", "cap_l", "title")]
	local needed = 0
	if mid and mid.box and cap then
		local scale = bandH / (mid.box[4] - mid.box[2])
		needed = 2 * cap.w * scale + 6
	end
	-- centred over the health bar (user, 2026-09-21: the name in the middle
	-- of the HP bar, the plate with it), on the name's line, as wide as the
	-- bar or the caps need
	local okW, hw = pcall(health.GetWidth, health)
	local width = needed
	if okW and hw and not Secret(hw) then
		width = math.max(needed, hw)
	end
	local okP2, _, _, _, _, hy = pcall(health.GetPoint, health, 1)
	hy = (okP2 and hy and not Secret(hy)) and hy or -19
	-- the band's centre line, from the health container's top
	local centreY = (y or 0) - nameH / 2
	f:SetPoint("CENTER", health, "TOP", 0, centreY - hy)
	f:SetSize(math.max(width, 1), bandH)
	return f
end

local function SkinPartyMember(frame)
	if not frame or skin.party[frame] then
		return
	end
	local picture = frame.Texture
	local portrait = frame.Portrait
	if not (picture and portrait and frame.HealthBarContainer and frame.ManaBar) then
		return
	end
	skin.party[frame] = true
	local overlay = frame.PartyMemberOverlay
	FadeArt({
		{ picture, "UI-HUD-UnitFrame-Party-PortraitOn" },
		{ frame.VehicleTexture, "UI-HUD-UnitFrame-Party-PortraitOn-Vehicle" },
		{ frame.Flash, "UI-HUD-UnitFrame-Party-PortraitOn-InCombat" },
		{ overlay and overlay.Status, "UI-HUD-UnitFrame-Party-PortraitOn-Status" },
	})
	local health = frame.HealthBarContainer.HealthBar
	local band = frame.Name and NameBandRect(frame, frame.Name, frame.HealthBarContainer)
	if band then
		SkinBand(picture, band)
		CenterName(frame.Name, band)
	end
	local ring = SkinRing(picture, portrait, nil, "UnitFramePortraitRingParty")
	SkinBar(health, health, picture, false, true)
	SkinBar(frame.ManaBar, frame.ManaBar, picture, false)
	TuckBars(ring, { health, frame.ManaBar }, false)
	RingCover(ring, { health, frame.ManaBar }, false, frame)
	-- the member's pet: the same at half size (no name plate: its name has no band)
	local pet = frame.PetFrame
	if pet and pet.Texture and pet.Portrait and pet.HealthBar then
		FadeArt({
			{ pet.Texture, "UI-HUD-UnitFrame-Party-PortraitOn" },
			{ pet.Flash, "UI-HUD-UnitFrame-Party-PortraitOn-InCombat" },
		})
		local petRing = SkinRing(pet.Texture, pet.Portrait, nil, "UnitFramePortraitRingParty")
		SkinBar(pet.HealthBar, pet.HealthBar, pet.Texture, false, true)
		TuckBars(petRing, { pet.HealthBar }, false)
		RingCover(petRing, { pet.HealthBar }, false, pet)
	end
	-- the game re-anchors the name and swaps the art (player / vehicle):
	-- re-centre, re-tuck, re-fit
	local function Relayout()
		if active then
			Kit:WhenOutOfCombat(function()
				RetuckAll()
				for _, entry in ipairs(skin.names) do
					entry.place()
				end
				for _, cover in ipairs(skin.covers) do
					cover.Refit()
				end
			end)
		end
	end
	if frame.UpdateNameTextAnchors then
		hooksecurefunc(frame, "UpdateNameTextAnchors", Relayout)
	end
	if frame.UpdateArt then
		hooksecurefunc(frame, "UpdateArt", Relayout)
	end
end

local function SkinParty()
	local pf = PartyFrame
	if not pf then
		return
	end
	if pf.PartyMemberFramePool then
		for frame in pf.PartyMemberFramePool:EnumerateActive() do
			SkinPartyMember(frame)
		end
	end
	if pf.Background and not skin.partyBackground then
		skin.partyBackground = true
		local bg = pf.Background
		local extra = {}
		for _, key in ipairs({ "Center", "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner" }) do
			if bg[key] then
				extra[#extra + 1] = bg[key]
			end
		end
		-- its child, so it shows, hides and fades with it (the opacity slider)
		Replace(bg, { as = "PartyFrameBackground", parent = bg, rect = bg, level = 0, noFade = true, alsoFade = extra })
	end
	if not skin.partyHooked and pf.InitializePartyMemberFrames then
		skin.partyHooked = true
		hooksecurefunc(pf, "InitializePartyMemberFrames", function()
			if active then
				Kit:WhenOutOfCombat(SkinParty)
			end
		end)
	end
end

local function Build()
	if not skin then
		skin = { reps = {}, followers = {}, targets = {}, names = {}, covers = {}, party = {} }
	end
	SkinPlayer()
	SkinTargetLike(TargetFrame)
	SkinTargetLike(FocusFrame)
	SkinPet()
	SkinParty()
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
	for _, t in pairs(skin.targets) do
		if type(t) == "table" and t.tint then
			t.tint()
		end
	end
	for _, entry in ipairs(skin.names) do
		entry.place()
	end
	RetuckAll()
	for _, cover in ipairs(skin.covers) do
		cover.Refit()
	end
	Kit:Cover("unitframes")
	Kit:Cover("partyframes")
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	RestoreNames()
	UntuckBars()
	for _, cover in ipairs(skin.covers) do
		cover.holder:Hide()
	end
	Kit:Uncover("unitframes")
	Kit:Uncover("partyframes")
end

local function Hook()
	if hooked then
		return
	end
	hooked = true
	-- a render put on a ringed portrait (the C-side SetPortraitTexture, which
	-- the texture's own SetTexture hook does not see): fit it again (a lookup
	-- for any other portrait; the refit itself leaves a fitted one at once)
	if type(SetPortraitTexture) == "function" then
		hooksecurefunc("SetPortraitTexture", function(texture)
			local refit = texture and refits[texture]
			if refit then
				refit()
			end
		end)
	end
	-- the player's art swaps (vehicle / class resource) re-anchor its bars
	-- and its name: refit the brackets, re-centre the names
	for _, fname in ipairs({ "PlayerFrame_ToPlayerArt", "PlayerFrame_ToVehicleArt", "PlayerFrame_UpdateArt", "PlayerFrame_UpdatePlayerNameTextAnchor" }) do
		if type(_G[fname]) == "function" then
			hooksecurefunc(fname, function()
				if active then
					Kit:WhenOutOfCombat(function()
						RetuckAll()
						for _, rep in ipairs(skin.reps) do
							if rep.kind == "bar" then
								rep:Refit()
							end
						end
						for _, entry in ipairs(skin.names) do
							entry.place()
						end
						for _, cover in ipairs(skin.covers) do
							cover.Refit()
						end
					end)
				end
			end)
		end
	end
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
Perf.SetScript(eventFrame, "OnEvent", function(self, event)
	if event == "PLAYER_ENTERING_WORLD" then
		self:UnregisterEvent(event)
		if M.isEnabled then
			Kit:WhenOutOfCombat(Activate)
		end
	end
end)

function M:OnEnable(db)
	self.db = db
	Hook()
	-- the frames exist at load; their portraits and bars are laid out once
	-- the player is in the world (a toggle from the options is already there)
	local portrait = PlayerFrame and PlayerFrame.PlayerFrameContainer and PlayerFrame.PlayerFrameContainer.PlayerPortrait
	local ok, w = pcall(function() return portrait and portrait:GetWidth() end)
	if ok and w and not Secret(w) and w > 0 then
		Kit:WhenOutOfCombat(Activate)
	else
		eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	end
end

function M:OnDisable()
	eventFrame:UnregisterAllEvents()
	-- the bars are protected: their anchors go back out of combat
	Kit:WhenOutOfCombat(Deactivate)
end

------------------------------------------------------------------------------------
-- /uftest: how to see a full party / raid without a group. Edit Mode's own
-- "Party Frames" / "Raid Frames" boxes fill the frames with the player as
-- every member; forcing them from addon code runs Blizzard's Edit Mode path
-- tainted and it trips on a secret value (CompactUnitFrame_UpdateHealthColor:
-- "attempt to compare a secret number while tainted by MelloUI"), so the
-- command only tells the way.
--------------------------------------------------------------------------------
SLASH_MELLOUFTEST1 = "/uftest"
SlashCmdList.MELLOUFTEST = function()
	MelloUI:Print("Test party / raid frames: Esc > Edit Mode, then tick 'Party Frames' and / or 'Raid Frames' in the Edit Mode window.")
	MelloUI:Print("The raid's size: click the raid frames > 'View Raid Size' (10 / 25 / 40). Untick them or leave Edit Mode when done.")
	MelloUI:Print("(An addon cannot switch these itself: Blizzard's Edit Mode code would run tainted and error on this client's secret values.)")
end

--------------------------------------------------------------------------------
-- /ufdump [player|target|focus|pet|tot|party|party1] [frames|reps]: the frame's art
-- (regions by default). Opens the copy window. Secret-safe (Kit:DumpWindow
-- guards every read).
--------------------------------------------------------------------------------
SLASH_MELLOUFDUMP1 = "/ufdump"
SlashCmdList.MELLOUFDUMP = function(msg)
	msg = (msg or ""):lower()
	local which, mode = msg:match("^(%a*)%s*(%a*)$")
	if which == "frames" or which == "reps" then
		which, mode = "", which
	end
	local keys = which ~= "" and { which } or { "player", "target" }
	MelloUI:ClearLog()
	for _, key in ipairs(keys) do
		local getter = FRAMES[key]
		local frame = getter and getter()
		if not frame then
			MelloUI:Print("%s: no such frame (player, target, focus, pet, tot, party, party1)", key)
		else
			local ok, w, h = pcall(frame.GetSize, frame)
			MelloUI:Print("== %s (%s) %s x %s  %s L%d %s", key, frame:GetName() or "?", ok and not Secret(w) and string.format("%.0f", w) or "?",
				ok and not Secret(h) and string.format("%.0f", h) or "?", frame:GetFrameStrata(), frame:GetFrameLevel(), frame:IsShown() and "shown" or "hidden")
			Kit:DumpWindow(frame, skin, mode ~= "" and mode or nil, function(m, Rect)
				if m == "reps" then
					-- the portraits and their masks, to check the ring's centring
					local container = frame.PlayerFrameContainer or frame.TargetFrameContainer or frame
					local portrait = container.PlayerPortrait or container.Portrait
					local mask = container.PlayerPortraitMask or container.PortraitMask
					if portrait then
						Rect("portrait", portrait)
					end
					if mask then
						Rect("portrait mask", mask)
					end
					-- the bars' and the ring cover's levels (the cover must be above)
					local main = frame.PlayerFrameContent and frame.PlayerFrameContent.PlayerFrameContentMain
						or frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentMain or frame
					local health = main.HealthBarsContainer and main.HealthBarsContainer.HealthBar or main.HealthBar
					local mana = main.ManaBarArea and main.ManaBarArea.ManaBar or main.ManaBar
					for _, entry in ipairs({ { "health bar", health }, { "power bar", mana } }) do
						if entry[2] then
							Rect(entry[1], entry[2], string.format("%s L%d", entry[2]:GetFrameStrata(), entry[2]:GetFrameLevel()))
						end
					end
					for _, cover in ipairs(skin and skin.covers or {}) do
						if cover.holder:GetParent() == (frame.PlayerFrameContainer or frame.TargetFrameContainer or frame) then
							Rect("ring cover", cover.holder, string.format("%s L%d %s", cover.holder:GetFrameStrata(), cover.holder:GetFrameLevel(), cover.holder:IsShown() and "shown" or "hidden"))
						end
					end
				end
				return false
			end)
		end
	end
	MelloUI:ShowLog("ufdump " .. msg)
end
