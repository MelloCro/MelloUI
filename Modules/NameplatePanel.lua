--------------------------------------------------------------------------------
-- MelloUI - Nameplate Panel
--
-- The nameplates (Blizzard_NamePlates: each NamePlateN's UnitFrame with its
-- health bar, cast bar and level indicator; Camelot's own health bar has no
-- border lines, only its backing) dressed in the painted kit
-- (Modules/Kit.lua) on the game's own layout, by the user's picks
-- (kit_raw/nameplate_catalog.png, 2026-09-21):
--   NP1 = P1: the health bar's backing -> the gem-capped bracket as the
--   bar's regions above the fill, the caps OUTSIDE the bar, the bar set in
--   by the arms after each of the game's own re-anchors (UpdateAnchors: the
--   fill cannot be re-anchored, so the bar ends where the gems begin); the
--   trough under the fill.
--   NC2: the cast bar's background -> the single rail at the raid frames'
--   0.8 with the stone body, as the bar's regions; its optional border faded.
--   Fixed: the level indicator's circle -> the orb (as the unit frames'
--   level circle); the name, texts, icons, target highlight, aggro FX and
--   auras stay the game's (the Nameplates tweak module keeps working).
-- Every size under a nameplate reads secret on this client: the brackets
-- are fitted from NamePlateSetupOptions, never from the frames.
-- Covers the group "nameplates". /npdump [frames|reps] (the target's plate).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("NameplatePanel")
local hooksecurefunc = Perf.hooksecurefunc
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("NameplatePanel", {
	title = "Nameplate Kit",
	desc = "Nameplates dressed in the painted kit: the health bar in the bracket, the cast bar on the single rail, the level circle on the orb.",
	window = { label = "Nameplates", desc = "Nameplate health and cast bars in the kit.", tab = "HUD" },
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local skin = nil
local active = false

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret

local function Replace(region, opts)
	if not region then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Nameplates: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

local function Option(key, fallback)
	local opts = NamePlateSetupOptions
	local v = opts and opts[key]
	if type(v) == "number" and not Secret(v) then
		return v
	end
	return fallback
end

-- The health bar set in by the bracket's arms from the anchors the game
-- just gave it (UpdateAnchors runs on every acquire and option change, in
-- combat too — it is not a protected frame).
local function InsetHealthBar(hb, rep)
	-- once per game layout: melloInset holds the game's anchors until the
	-- game's next UpdateAnchors clears it (a second pass inset the bar twice)
	if not (active and rep.GetArms) or hb.melloInsetting or hb.melloInset then
		return
	end
	local okN, n = pcall(hb.GetNumPoints, hb)
	if not okN or Secret(n) or not n or n == 0 then
		return
	end
	local points = {}
	for i = 1, n do
		local ok, point, rel, relPoint, x, y = pcall(hb.GetPoint, hb, i)
		if not ok or Secret(point) or Secret(x) or Secret(y) or not point then
			return
		end
		points[i] = { point, rel, relPoint, x or 0, y or 0 }
	end
	hb.melloInset = points
	local armL, armR = rep:GetArms()
	hb.melloInsetting = true
	hb:ClearAllPoints()
	for _, pt in ipairs(points) do
		local point, rel, relPoint, x, y = unpack(pt)
		if point:find("LEFT") then
			x = x + armL
		elseif point:find("RIGHT") then
			x = x - armR
		end
		hb:SetPoint(point, rel, relPoint, x, y)
	end
	hb.melloInsetting = nil
end

-- The name centred on the bracket (user, 2026-09-22: it sat to the right):
-- the game centres it on the whole health container, but with the classic
-- bar style it insets the bar itself unevenly (3.5 px left, 20.75 px right,
-- room for the level circle) and the bracket sits on the bar. Only the
-- name-above-the-bar layout is touched; the game's anchors are kept for
-- the restore.
local function CentreName(uf, hb, rep)
	local name = uf.name
	if not (active and name and rep.GetArms) then
		return
	end
	-- the game's layout comes from its setup options (plain values); the
	-- name's own anchors read SECRET on this client (user, 2026-09-22,
	-- /npdump: "first=? to ?", so the earlier read-then-move never ran)
	local styles = NamePlateConstants and NamePlateConstants.NAME_ANCHOR_STYLES
	local style = Option("unitNameAnchorStyle", styles and styles.InsideHealthBar or 1)
	if not styles or style == styles.InsideHealthBar then
		return   -- the name inside the bar: the game's
	end
	-- the artwork's ends: the bracket's two caps (they stand outside the
	-- bar); the name spans them, centred, so it sits on the painted
	-- middle whatever the arms and the bar's own insets are
	local strip = rep.strip
	local capL, capR = strip and strip.capL, strip and strip.capR
	if not (capL and capR) then
		return
	end
	-- the name stands on the mid's painted rail, not on the caps' canvas top:
	-- the gems reach above the rail by a share of the bracket's scale, so a
	-- fixed nudge (-10, user 2026-09-22) fitted one plate size only and sank
	-- the name into the bar on the small ones (user, 2026-09-23: size 1)
	local mid = Kit:Piece(Kit:StripPieceName(strip.base, "mid", strip.state))
	local railTop = (mid and mid.box and mid.box[2] or 14) * (strip.scale or 1)
	local y = Option("healthBarToNameAboveSpacing", 2) - railTop
	name.melloCentred = style   -- what to put back (the style's own anchors)
	-- the span the name is centred on: from the left cap to the level
	-- orb's outer edge where the game shows the orb (it stands past the
	-- right cap; user, 2026-09-22: "centre it on the bracket plus orb"),
	-- else to the right cap. A helper frame carries the span (its top is
	-- the cap's top, its right the orb's right: no edge set twice).
	local span = uf.melloNameSpan
	if not span then
		span = CreateFrame("Frame", nil, uf)
		span:EnableMouse(false)
		uf.melloNameSpan = span
	end
	local lf = uf.PlayerLevelDiffFrame
	local okS, shown = pcall(lf and lf.IsShown, lf)
	span:ClearAllPoints()
	span:SetPoint("TOPLEFT", capL, "TOPLEFT", 0, 0)
	if lf and okS and not Secret(shown) and shown then
		span:SetPoint("RIGHT", lf, "RIGHT", 0, 0)
	else
		span:SetPoint("RIGHT", capR, "RIGHT", 0, 0)
	end
	name:ClearAllPoints()
	name:SetPoint("BOTTOMLEFT", span, "TOPLEFT", 0, y)
	name:SetPoint("BOTTOMRIGHT", span, "TOPRIGHT", 0, y)
	name:SetJustifyH("CENTER")
end

-- The game's anchors for the style back (as UpdateAnchors lays them; the
-- game's next UpdateAnchors on the plate lays them itself anyway).
local function UncentreName(uf)
	local name = uf.name
	local style = name and name.melloCentred
	if not style then
		return
	end
	name.melloCentred = nil
	local styles = NamePlateConstants and NamePlateConstants.NAME_ANCHOR_STYLES
	local container = uf.HealthBarsContainer
	local y = Option("healthBarToNameAboveSpacing", 2)
	name:ClearAllPoints()
	if styles and style == styles.CenteredAboveHealthBar then
		name:SetJustifyH("CENTER")
		name:SetPoint("BOTTOM", container, "TOP", 0, y)
	else
		name:SetJustifyH(NamePlateSetupOptions and NamePlateSetupOptions.nameJustificationWhenAboveHealthBar or "LEFT")
		name:SetPoint("BOTTOMLEFT", container, "TOPLEFT", 0, y)
		local lf = uf.PlayerLevelDiffFrame
		local hbText = container and container.healthBar and container.healthBar.Text
		if lf and lf:IsShown() then
			name:SetPoint("RIGHT", lf, "RIGHT", 0, 0)
		elseif hbText then
			name:SetPoint("RIGHT", hbText, "LEFT", -2, 0)
		end
	end
end

-- The level circle as tall as the bracket, gem to gem (user, 2026-09-23:
-- "cap the level circle to the bar height"): the game grows its level frame
-- faster than the bar with each nameplate size, so the orb dwarfed the bar
-- on the large sizes. Sized from the bracket's own height (a plain number,
-- where a plate's frames read secret), across any scale between the bar and
-- the level frame; again on each of the game's layouts.
local function FitLevelOrb(uf)
	local orb, bracket = uf.melloLevelOrb, uf.melloBracket
	local strip = bracket and bracket.strip
	local tex = orb and orb.tex
	local h = strip and strip.height
	if not (tex and type(h) == "number" and h > 0) then
		return
	end
	local ratio = 1
	local ok, sb, so = pcall(function()
		return strip:GetEffectiveScale(), tex:GetParent():GetEffectiveScale()
	end)
	if ok and type(sb) == "number" and type(so) == "number" and not Secret(sb) and not Secret(so) and so > 0 then
		ratio = sb / so
	end
	tex:SetSize(h * ratio, h * ratio)
end

local function SkinUnitFrame(uf)
	if not uf or uf.melloKit then
		return
	end
	uf.melloKit = true
	local container = uf.HealthBarsContainer
	local hb = container and container.healthBar
	if hb and hb.bgTexture then
		local layer, sublevel, troughLayer, troughSub = Kit:BracketLayers(hb)
		-- the game's dimming band over every plate that is not the target
		-- (deselectedOverlay, a soft dark middle) read as a mask on the kit's
		-- flat fill; the target is the gold iron here, so it is faded with
		-- the backing (user, 2026-09-22)
		local rep = Replace(hb.bgTexture, { as = "NamePlateHealthBarBG", parent = hb, rect = hb,
			layer = layer, sublevel = sublevel, troughLayer = troughLayer, troughSub = troughSub,
			fitHeight = Option("healthBarHeight", 12), alsoFade = { hb.deselectedOverlay } })
		if rep then
			uf.melloBracket = rep
			-- the target / focus highlight: the game's white outline around the
			-- bar (selectedBorder) is faded, and the bracket's own iron shines
			-- gold instead while the game shows it (user, 2026-09-21)
			local sel = hb.selectedBorder
			if sel then
				Replace(sel, { as = "UI-HUD-Nameplates-Selected" })
				local function Shine()
					local strip = rep.strip
					if not strip then
						return
					end
					local on = active and sel:IsShown()
					local r, g, b = 1, 1, 1
					if on then
						r, g, b = 1, 0.5, 0   -- the full orange-gold the iron can take (user, 2026-09-21: "increase it more", twice)
					end
					for _, tex in ipairs({ strip.capL, strip.mid, strip.capR }) do
						tex:SetVertexColor(r, g, b)
					end
				end
				hooksecurefunc(sel, "Show", Shine)
				hooksecurefunc(sel, "Hide", Shine)
				hooksecurefunc(sel, "SetShown", Shine)
				local enable0, disable0 = rep.onEnable, rep.onDisable
				rep.onEnable = function(...)
					if enable0 then
						enable0(...)
					end
					Shine()
				end
				rep.onDisable = function(...)
					if disable0 then
						disable0(...)
					end
					local strip = rep.strip
					if strip then
						for _, tex in ipairs({ strip.capL, strip.mid, strip.capR }) do
							tex:SetVertexColor(1, 1, 1)
						end
					end
				end
			end
			hooksecurefunc(uf, "UpdateAnchors", function()
				hb.melloInset = nil   -- the game re-anchored the bar from scratch
				if uf.name then
					uf.name.melloCentred = nil   -- the game re-anchored the name too
				end
				InsetHealthBar(hb, rep)
				rep:Refit()
				CentreName(uf, hb, rep)
				FitLevelOrb(uf)
			end)
			local enable = rep.onEnable
			rep.onEnable = function(...)
				if enable then
					enable(...)
				end
				InsetHealthBar(hb, rep)
				CentreName(uf, hb, rep)
				-- the bracket's left edge, for what stands beside the bar (the
				-- Nameplates module's quest icon goes left of the gem cap)
				uf.melloBracketLeft = rep.strip and rep.strip.capL or nil
			end
			local disable = rep.onDisable
			rep.onDisable = function(...)
				if disable then
					disable(...)
				end
				uf.melloBracketLeft = nil
				UncentreName(uf)
				local points = hb.melloInset
				if points then
					hb.melloInset = nil
					hb.melloInsetting = true
					hb:ClearAllPoints()
					for _, pt in ipairs(points) do
						hb:SetPoint(unpack(pt, 1, 5))
					end
					hb.melloInsetting = nil
				end
			end
			if active then
				InsetHealthBar(hb, rep)
				CentreName(uf, hb, rep)
				uf.melloBracketLeft = rep.strip and rep.strip.capL or nil
			end
		end
	end
	local cb = uf.CastBarsContainer and uf.CastBarsContainer.castBar
	if cb and cb.Background then
		Replace(cb.Background, { as = "NamePlateCastBarBackground", rect = cb, alsoFade = { cb.Border }, fitHeight = Option("castBarHeight", 16) })
	end
	local lf = uf.PlayerLevelDiffFrame
	if lf and lf.playerLevelDiffIcon then
		uf.melloLevelOrb = Replace(lf.playerLevelDiffIcon, { as = "ui-hud-nameplates-levelindicator", rect = lf.playerLevelDiffIcon })
		FitLevelOrb(uf)
		-- the game's target ring around the level circle: faded (the bar's
		-- gold iron is the highlight — user, 2026-09-21)
		if lf.selectedBorder then
			Replace(lf.selectedBorder, { as = "ui-hud-nameplates-levelindicator-selected" })
		end
	end
end

local function SkinAll()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then
		return
	end
	local ok, plates = pcall(C_NamePlate.GetNamePlates)
	if ok and type(plates) == "table" then
		for _, base in ipairs(plates) do
			if base.UnitFrame then
				SkinUnitFrame(base.UnitFrame)
			end
		end
	end
end

local function Build()
	if skin then
		return
	end
	skin = { reps = {}, followers = {} }
	SkinAll()
	if NamePlateDriverFrame then
		hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", function(driver, unit)
			if not active then
				return
			end
			local ok, base = pcall(driver.GetNamePlateForUnit, driver, unit)
			if ok and base and base.UnitFrame then
				SkinUnitFrame(base.UnitFrame)
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
	SkinAll()
	Kit:Cover("nameplates")
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	Kit:Uncover("nameplates")
end

function M:OnEnable(db)
	self.db = db
	Activate()
end

function M:OnDisable()
	Deactivate()
end

--------------------------------------------------------------------------------
-- /npdump [frames|reps]: the target's nameplate. Opens the copy window.
--------------------------------------------------------------------------------
SLASH_MELLONPDUMP1 = "/npdump"
SlashCmdList.MELLONPDUMP = function(msg)
	msg = (msg or ""):lower()
	MelloUI:ClearLog()
	local ok, base = pcall(C_NamePlate.GetNamePlateForUnit, "target")
	if not (ok and base and base.UnitFrame) then
		MelloUI:Print("No nameplate on the target (target something with a nameplate first).")
	else
		local uf = base.UnitFrame
		local name = uf.name
		local hb = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
		if name then
			-- the name against the bracket (user, 2026-09-22: centred on the
			-- artwork?); every measurement on a nameplate can be refused
			-- (restricted regions) or secret: pcall'd and checked
			local function Centre(region)
				local okR, l, _, w = pcall(region.GetRect, region)
				if okR and l and w and not Secret(l) and not Secret(w) then
					return string.format("%.0f", l + w / 2)
				end
				return "unreadable"
			end
			local okN, n = pcall(name.GetNumPoints, name)
			n = (okN and not Secret(n)) and n or 0
			local okP, point, rel = pcall(name.GetPoint, name, 1)
			local relName = "?"
			if okP and rel and not Secret(rel) then
				relName = (rel == hb and "healthBar") or (rel == uf.HealthBarsContainer and "container") or (rel.GetName and rel:GetName()) or "unnamed"
			end
			local okJ, justify = pcall(name.GetJustifyH, name)
			local okT, text = pcall(name.GetText, name)
			MelloUI:Print("name %s: centre x=%s (%d points, first=%s to %s)  bar centre x=%s  justify=%s  centred by us=%s",
				(okT and not Secret(text)) and string.format("%q", tostring(text)) or "(secret)", Centre(name), n,
				tostring(okP and not Secret(point) and point or "?"), relName,
				hb and Centre(hb) or "?", tostring(okJ and not Secret(justify) and justify or "?"), tostring(name.melloCentred ~= nil))
			for _, rep in ipairs(skin and skin.reps or {}) do
				if hb and rep.region == hb.bgTexture and rep.strip and rep.strip.capL then
					local okL, cl = pcall(rep.strip.capL.GetLeft, rep.strip.capL)
					local okR, rl, _, rw = pcall(rep.strip.capR.GetRect, rep.strip.capR)
					if okL and okR and cl and rl and rw and not Secret(cl) and not Secret(rl) and not Secret(rw) then
						MelloUI:Print("bracket caps: %.0f..%.0f, centre x=%.0f", cl, rl + rw, (cl + rl + rw) / 2)
					else
						MelloUI:Print("bracket caps: unreadable on this plate")
					end
				end
			end
		end
		Kit:DumpWindow(uf, skin, msg ~= "" and msg or nil)
	end
	MelloUI:ShowLog("npdump " .. msg)
end
