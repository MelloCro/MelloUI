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
-- Name Shade (0.13.7): a soft dark band behind the name (MelloUI.Shade), as
-- long as the name itself, or on "Whole plate" also a shadow partner under
-- each piece (Kit:Shadow).
-- Covers the group "nameplates". /npdump [frames|reps] (the target's plate).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("NameplatePanel")
local hooksecurefunc = Perf.hooksecurefunc
local Kit = MelloUI.Kit

local SHADE_STRENGTH = 0.7   -- the Shade Strength slider's default

local M = MelloUI:RegisterModule("NameplatePanel", {
	title = "Nameplate Kit",
	desc = "Nameplates dressed in the painted kit: the health bar in the bracket, the cast bar on the single rail, the level circle on the orb.",
	-- (include: the options below sit under this row on UI Modifications' HUD tab)
	window = { label = "Nameplates", desc = "Nameplate health and cast bars in the kit.", tab = "HUD", include = true },
	enabledByDefault = true,
	defaults = { nameShade = "name", shadeStrength = SHADE_STRENGTH },
	options = {
		{ type = "dropdown", key = "nameShade", name = "Name Shade", values = {
			{ value = "name", label = "Name" },
			{ value = "plate", label = "Whole plate" },
			{ value = "off", label = "Off" },
		}, desc = "A soft dark shade behind each nameplate's name, so it reads on bright ground. Whole plate: the shade also follows the plate's own shape, round the level circle, the end gems and along the bar. Off: no shade." },
		{ type = "slider", key = "shadeStrength", name = "Shade Strength", min = 0.3, max = 0.9, step = 0.05, percent = true,
		  desc = "How dark the shade behind the names (and the plates) is." },
	},
})

local skin = nil
local active = false

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number

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
	-- the orb's scale (UI units per painted px), for its shadow partner's
	-- reach on "Whole plate" (the name shade, below)
	local piece = tex.kitName and Kit:Piece(tex.kitName)
	if piece and piece.w > 0 then
		uf.melloOrbScale = h * ratio / piece.w
		Kit:ShadowFit(tex, uf.melloOrbScale)
	end
end

--------------------------------------------------------------------------------
-- The name shade (user, 2026-09-25, sketches A and B): the shared soft band
-- (MelloUI.Shade) behind each plate's name and, on "Whole plate", a shadow
-- partner (Kit:Shadow) under each of the plate's own pieces -- the bracket's
-- caps and rail, the level orb -- so the shade follows the plate's shape:
-- round the orb, a diamond round each end gem, a soft rim along the rail.
-- Made once per plate frame when the kit first dresses it (or when the
-- setting first asks for them; a crowd's a few plates a frame) and kept as
-- the plates recycle. Anchors only:
-- every size under a plate reads secret. The band hugs the name's own text
-- (user, 2026-09-25: "cant it scale according to the name length?"): it
-- hangs on the name's MEASURE, an unseen copy of the name's text with no
-- width of its own, so the engine sizes it to the text. The name's text is
-- handed on as it is (a secret one too: nothing is read or compared), and
-- the name's own anchors, justify and truncation stay the game's. Where the
-- measure cannot take a name, the band lies on the name's whole span as
-- before (CentreName: the left cap to the level orb's outer edge). The band
-- follows the name's own show and hide (hooked); the partners follow their
-- pieces. No script, no per-frame work: the strength is one pass over the
-- dressed plates, on the setting.
--------------------------------------------------------------------------------

local SHADE_MODES = { name = true, plate = true, off = true }
-- the band on the name's line, in plate units: its full middle 4 past the
-- text's own ends (never inside them, so a band is never narrower than its
-- two soft ends), its soft ends 20 long, 5 above and below the text (the
-- band's own top and bottom fade: the text's edges at about 80 %); under all
-- that the name's frame draws (BACKGROUND -8). SPAN_PAD_X: on the name's
-- whole span (the measure refused a name), its middle 10 inside the span's
-- ends, so the soft ends reach 10 past the gem and the orb
local BAND = { colour = "innerPanel", feather = 20, layer = "BACKGROUND", sublevel = -8 }
local BAND_PAD_X, BAND_PAD_Y, SPAN_PAD_X = 4, 5, -10
local PARTNER = { colour = "innerPanel" }   -- Kit:Shadow's options (read once: one table for all)

local function ShadeMode()
	local mode = M.db and M.db.nameShade
	return SHADE_MODES[mode] and mode or "name"
end

local function ShadeStrength()
	local v = M.db and Num(M.db.shadeStrength)
	if not v then
		return SHADE_STRENGTH
	end
	return v < 0 and 0 or v > 1 and 1 or v
end

-- the band shows while the kit is on, the shade wanted, the name on the
-- bracket (centred by us: not inside the bar) and shown by the game
local function SyncBand(uf)
	local band = uf.melloNameShade
	if not band then
		return
	end
	local name = uf.name
	local want = (active and ShadeMode() ~= "off" and name.melloCentred ~= nil and name.melloNameShown) and true or false
	if band:IsShown() ~= want then
		band:SetShown(want)
	end
end

local function NameShown(name, shown)
	name.melloNameShown = shown
	local uf = name.melloShadeOf
	if uf then
		SyncBand(uf)
	end
end
local OnNameShow = Perf.Shared("Show on a nameplate's name (its shade)", function(name)
	NameShown(name, true)
end)
local OnNameHide = Perf.Shared("Hide on a nameplate's name (its shade)", function(name)
	NameShown(name, false)
end)
local OnNameSetShown = Perf.Shared("SetShown on a nameplate's name (its shade)", function(name, shown)
	-- (asked for secret first: a secret answer counts as shown)
	NameShown(name, Secret(shown) or (shown and true or false))
end)

-- The measure's font as the name's: its font object, then its face, size
-- and flags and its text scale (the game sets the name's height per plate
-- size). Values are handed on as they come; a secret or refused one leaves
-- the font object's
local function CopyFont(name, measure)
	local okO, object = pcall(name.GetFontObject, name)
	if okO and not Secret(object) and type(object) == "table" then
		pcall(measure.SetFontObject, measure, object)
	end
	local okF, face, size, flags = pcall(name.GetFont, name)
	if okF and not Secret(face) and type(face) == "string" then
		pcall(measure.SetFont, measure, face, size, flags)
	end
	local okS, scale = pcall(name.GetTextScale, name)
	if okS and not Secret(scale) and type(scale) == "number" then
		pcall(measure.SetTextScale, measure, scale)
	end
end

-- the band on the measure (true: it holds the name's text) or on the name's
-- whole span (false: it refused the name); re-anchored on a change only
local function HangBand(uf, measured)
	local band = uf.melloNameShade
	if not band or uf.melloNameMeasured == measured then
		return
	end
	uf.melloNameMeasured = measured
	if measured then
		band:Anchor(uf.melloNameMeasure, BAND_PAD_X, BAND_PAD_Y)
	else
		band:Anchor(uf.name, SPAN_PAD_X, BAND_PAD_Y)
	end
end

-- the name's text handed on to its measure, untouched (the call answers
-- whether the measure took it: a client that refuses a secret text there
-- leaves that plate's band on the span)
local OnNameText = Perf.Shared("SetText on a nameplate's name (its shade's measure)", function(name, text)
	local uf = name.melloShadeOf
	local measure = uf and uf.melloNameMeasure
	if measure then
		HangBand(uf, (pcall(measure.SetText, measure, text)))
	end
end)
local OnNameFormatted = Perf.Shared("SetFormattedText on a nameplate's name (its shade's measure)", function(name, ...)
	local uf = name.melloShadeOf
	local measure = uf and uf.melloNameMeasure
	if measure then
		HangBand(uf, (pcall(measure.SetFormattedText, measure, ...)))
	end
end)

-- a new font (Font Style, the faces): each measure takes its name's again
-- (one listener, taken with the first measure)
local fontsHeard = false
local function RefontAll()
	if not skin then
		return
	end
	for _, uf in ipairs(skin.plates) do
		local measure = uf.melloNameMeasure
		if measure then
			CopyFont(uf.name, measure)
		end
	end
end

-- the name's measure: an unseen font string with no width of its own, on
-- one point at the name's centre (the name is centred on the span while the
-- band shows), sized by the engine to the text (none where the name's frame
-- makes no text: the band then lies on the span)
local function MakeMeasure(uf, host, name)
	if type(host.CreateFontString) ~= "function" then
		return nil
	end
	local measure = host:CreateFontString(nil, "BACKGROUND")
	measure:SetAlpha(0)
	measure:SetWordWrap(false)
	measure:SetPoint("CENTER", name, "CENTER", 0, 0)
	CopyFont(name, measure)
	uf.melloNameMeasure = measure
	if not fontsHeard then
		fontsHeard = true
		MelloUI:On("fonts", RefontAll, "Nameplate name shade")
	end
	return measure
end

local function MakeBand(uf)
	local name = uf.name
	if not name then
		return nil
	end
	-- on the frame that draws the name, under it: over the world, under the bar
	local okP, host = pcall(name.GetParent, name)
	if not okP or type(host) ~= "table" or not host.CreateTexture then
		host = uf
	end
	BAND.alpha = ShadeStrength()
	local band = MelloUI.Shade:Band(host, BAND)
	if not band then
		return nil
	end
	uf.melloNameShade = band
	local measure = MakeMeasure(uf, host, name)
	local okT, text = pcall(name.GetText, name)
	HangBand(uf, measure and okT and (pcall(measure.SetText, measure, text)) or false)
	local okS, shown = pcall(name.IsShown, name)
	name.melloNameShown = not okS or Secret(shown) or (shown and true or false)
	name.melloShadeOf = uf
	hooksecurefunc(name, "Show", OnNameShow)
	hooksecurefunc(name, "Hide", OnNameHide)
	hooksecurefunc(name, "SetShown", OnNameSetShown)
	hooksecurefunc(name, "SetText", OnNameText)
	hooksecurefunc(name, "SetFormattedText", OnNameFormatted)
	return band
end

-- the plate's pieces that get a partner: the bracket's caps and rail, the orb
local function PlatePieces(uf)
	local strip = uf.melloBracket and uf.melloBracket.strip
	local orb = uf.melloLevelOrb and uf.melloLevelOrb.tex
	if strip then
		return strip.capL, strip.mid, strip.capR, orb
	end
	return nil, nil, nil, orb
end

-- does the plate still lack a part its mode wants (the band; on Whole plate
-- a partner)?
local function Lacks(uf, mode)
	if mode == "off" then
		return false
	end
	if uf.name and not uf.melloNameShade then
		return true
	end
	if mode ~= "plate" then
		return false
	end
	local capL, mid, capR, orb = PlatePieces(uf)
	return (capL and not capL.kitShadow) or (mid and not mid.kitShadow) or (capR and not capR.kitShadow)
		or (orb and not orb.kitShadow) or false
end

-- A crowd's shades are made a few plates a frame (review, 2026-09-25: the
-- first Whole plate, or a reload among many plates, made every plate's band
-- and partners -- up to 7 textures and 19 hooks a plate -- in one frame): at
-- most MAKE_PER_FRAME plates get theirs made in one frame (GetTime: the
-- frame's time), the rest by a sweep over the dressed plates on the next
-- frames (Kit:NextFrame), each plate tried once a sweep. Showing, hiding and
-- the strength of what is there already are never held back.
local MAKE_PER_FRAME = 6
local madeAt, madeCount = nil, 0
local sweepFrom = nil   -- the first dressed plate (its index) the sweep takes up
local ShadeSweep        -- (below)

local function MayMake()
	local now = GetTime()
	if now ~= madeAt then
		madeAt, madeCount = now, 0
	end
	if madeCount >= MAKE_PER_FRAME then
		return false
	end
	madeCount = madeCount + 1
	return true
end

local function Hold(uf)
	local at = uf.melloShadeAt
	if at and (not sweepFrom or at < sweepFrom) then
		sweepFrom = at
	end
	Kit:NextFrame(skin, ShadeSweep)
end

local function ShadePiece(tex, plate, strength, make, scale)
	if not tex then
		return
	end
	if tex.kitShadow then
		Kit:ShadowSet(tex, plate, strength)
	elseif plate and make then
		PARTNER.alpha, PARTNER.scale = strength or ShadeStrength(), scale
		Kit:Shadow(tex, PARTNER)
	end
end

-- The plate's shade as the setting has it: the band made when first wanted,
-- the partners when Whole plate is first chosen (this frame, or held for the
-- sweep). `strength`: set it on what is there already too (the setting);
-- nil leaves it
local function ShadePlate(uf, strength)
	local mode = ShadeMode()
	local make = true
	if Lacks(uf, mode) and not MayMake() then
		make = false
		Hold(uf)
	end
	local band = uf.melloNameShade
	if band then
		if strength then
			band:SetStrength(strength)
		end
	elseif make and mode ~= "off" then
		MakeBand(uf)
	end
	SyncBand(uf)
	local plate = mode == "plate"
	local capL, mid, capR, orb = PlatePieces(uf)
	ShadePiece(capL, plate, strength, make)
	ShadePiece(mid, plate, strength, make)
	ShadePiece(capR, plate, strength, make)
	ShadePiece(orb, plate, strength, make, uf.melloOrbScale)
end

-- the held plates, from the first one on, until this frame's making is spent
-- again (a plate still lacking after its try -- no sheet before the restart
-- -- is not tried again by this sweep)
function ShadeSweep(key)
	local from = sweepFrom
	sweepFrom = nil
	if key ~= skin or not from or not active then
		return   -- (off: Activate goes over every plate again)
	end
	local plates, mode, strength = skin.plates, ShadeMode(), ShadeStrength()
	for n = from, #plates do
		local uf = plates[n]
		if Lacks(uf, mode) then
			ShadePlate(uf, strength)
			if sweepFrom then
				return   -- (held again: on from there the next frame)
			end
		end
	end
end

-- after the game laid the plate out: the partners' reach at the bracket's
-- new scale (the orb's: FitLevelOrb), the measure in the name's font (the
-- game sets it with the layout), the band shown or not
local function FitShade(uf)
	local capL, mid, capR = PlatePieces(uf)
	if capL and capL.kitShadow then
		Kit:ShadowFit(capL)
		Kit:ShadowFit(mid)
		Kit:ShadowFit(capR)
	end
	local measure = uf.melloNameMeasure
	if measure then
		CopyFont(uf.name, measure)
	end
	SyncBand(uf)
end

local function ShadeAll(strength)
	if not skin then
		return
	end
	for _, uf in ipairs(skin.plates) do
		ShadePlate(uf, strength)
	end
end

-- the Nameplate Border swapped live (Kit:ApplyBorder -> rep:SetBar, then
-- this): the new bracket's partners at its new scale
local function OnBarChanged(rep)
	if rep.melloPlate then
		FitShade(rep.melloPlate)
	end
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
			rep.melloPlate, rep.onBarChanged = uf, OnBarChanged
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
				FitShade(uf)
			end)
			local enable = rep.onEnable
			rep.onEnable = function(...)
				if enable then
					enable(...)
				end
				InsetHealthBar(hb, rep)
				CentreName(uf, hb, rep)
				FitShade(uf)
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
				SyncBand(uf)
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
	-- the name shade, made with the dress (or a frame or so later in a
	-- crowd: ShadePlate) and kept as the plate recycles
	skin.plates[#skin.plates + 1] = uf
	uf.melloShadeAt = #skin.plates
	ShadePlate(uf)
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
	skin = { reps = {}, followers = {}, plates = {} }
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
	local built = skin ~= nil
	Build()
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	SkinAll()
	Kit:Cover("nameplates")
	if built then
		-- the shade as the settings are now (a profile load switches the
		-- module off and on again; a new build made it so already)
		ShadeAll(ShadeStrength())
	end
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

function M:OnSettingChanged(key)
	if key == "nameShade" then
		ShadeAll(nil)
	elseif key == "shadeStrength" then
		ShadeAll(ShadeStrength())
	end
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
			if uf.melloNameShade then
				MelloUI:Print("name shade: %s, %s", uf.melloNameShade:IsShown() and "shown" or "hidden",
					uf.melloNameMeasured and "as long as the name" or "along the whole bracket")
			end
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
