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
--   level circle), the level number on a dark disc inside the orb's ring
--   (0.15.0: the palette's inner panel, readable on any art and colour); the
--   name, texts, icons, target highlight, aggro FX and auras stay the game's
--   (the Nameplates tweak module keeps working).
--   Marks (0.15.0, the approved sketch's style A; Modules/KitMarks.lua, the
--   option `marks`): an elite's, rare's, rare elite's or boss's plate wears
--   a small crest before its name and its left end cap and level orb in the
--   unit's metal (the game's own elite / rare icon faded meanwhile).
-- Every size under a nameplate reads secret on this client: the brackets
-- are fitted from NamePlateSetupOptions, never from the frames.
-- Name Shade (0.13.7): a soft dark band behind the name (MelloUI.Shade), as
-- long as the name itself, or on "Whole plate" also a shadow partner under
-- each piece (Kit:Shadow) while the UI Shade's Nameplates area is on
-- (0.14.0: Kit:ShadeOn("nameplates"), Dynamic UI Modification).
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
	defaults = { nameShade = "name", marks = true },
	options = {
		{ type = "dropdown", key = "nameShade", name = "Name Shade", values = {
			{ value = "name", label = "Name" },
			{ value = "plate", label = "Whole plate" },
			{ value = "off", label = "Off" },
		}, desc = "A soft dark shade behind each nameplate's name, so it reads on bright ground. Whole plate: the UI Shade also follows the plate's own shape, round the level circle, the end gems and along the bar (it needs the UI Shade on, Look). Off: no shade. How dark it is: the UI Shade's Shade Strength." },
		{ type = "toggle", key = "marks", name = "Elite and Rare Marks",
		  desc = "Elites, rares, rare elites and bosses stand out: a small crest before the name (a crown, a silver star, a gold star or a skull) and the left end cap and level circle in gold for an elite, silver for a rare or rare elite and red-bronze for a boss." },
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

-- The health bar set in by the bracket's arms (UpdateAnchors runs on every
-- acquire and option change, in combat too -- it is not a protected frame).
-- Its anchors are the game's own two (Blizzard_NamePlateUnitFrame.lua,
-- UpdateAnchors: TOPLEFT and BOTTOMRIGHT on the health container, offsets
-- from its setup options -- plain values), laid from those options, never
-- read back: a frame on a nameplate answers its anchors SECRET, and the
-- read-back gave up there, the bar keeping its whole width under the
-- bracket's caps (user, 2026-10-04: "the nameplate texture sometimes spills
-- under the border"; the name's anchors went the same way, CentreName).
-- (One table: the bars inset since the game's last layout, weak keys --
-- nothing written onto the game's bar.)
local Inset = { done = setmetatable({}, { __mode = "k" }) }

-- the game's offsets of the bar on its container: TOPLEFT x, y, BOTTOMRIGHT x, y
function Inset.GamePoints()
	local opts = NamePlateSetupOptions
	local classic = opts and opts.useClassicHealthBar
	if classic and not Secret(classic) then
		local h, v = Option("horizontalScale", 1), Option("verticalScale", 1)
		return 3.5 * h, 0.5 * v, -20.75 * h, 0.5 * v
	end
	return 0, 0, 0, 0
end

-- the bar on its container, the bracket's arms in from each end and `m` in
-- from its top and bottom (0, 0, 0: the game's own)
function Inset.Lay(hb, container, armL, armR, m)
	local x1, y1, x2, y2 = Inset.GamePoints()
	hb:ClearAllPoints()
	hb:SetPoint("TOPLEFT", container, "TOPLEFT", x1 + armL, y1 - m)
	hb:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", x2 - armR, y2 + m)
end

-- Pixel perfect (user, 2026-10-04: "the nameplate texture sometimes spills
-- under the border", "i want it to be pixel perfect"): the bracket's solid
-- outline is fitted to the bar's height, so the fill's top and bottom lay ON
-- the rails' outer rows -- the art's soft edge -- and a pixel's rounding
-- showed the fill past them. The fill is set in by half the thinner rail
-- (its edges at the rails' centres, under solid metal) and the bracket
-- thickened by the same twice, so the border keeps its size and place.
-- The bracket's own fallback height (a plate's size can read secret) is
-- the bar's set-in height too.
function Inset.Margin(rep, h)
	local mid = rep.base and Kit.StripPieceName and Kit:Piece(Kit:StripPieceName(rep.base, "mid"))
	local box, open = mid and mid.box, mid and mid.open
	if not (box and open and box[4] > box[2]) then
		return 0
	end
	local rail = math.min(open[2] - box[2], box[4] - open[4])
	return math.max(rail, 0) / 2 * h / (box[4] - box[2])
end

-- refit: the bracket refitted here (the game's layout refits it itself, just after)
local function InsetHealthBar(hb, rep, container, refit)
	-- once per game layout (the game's next UpdateAnchors clears it: a second
	-- pass would inset the bar twice)
	if not (active and rep.GetArms and container) or Inset.done[hb] then
		return
	end
	local armL, armR = rep:GetArms()
	if Secret(armL) or Secret(armR) or type(armL) ~= "number" or type(armR) ~= "number" then
		return
	end
	local h = Option("healthBarHeight", 12)
	local m = Inset.Margin(rep, h)
	Inset.done[hb] = true
	Inset.Lay(hb, container, armL, armR, m)
	rep.thicken, rep.fitHeight = 2 * m, h - 2 * m
	if refit then
		rep:Refit()
	end
end

--------------------------------------------------------------------------------
-- One pixel grid for the whole plate (user, 2026-10-04: "the Actual
-- Healthbar, the Border, the Round border, its background, the level text
-- and the name text are all separate entities and moving independently,
-- the Default one is static, and everything moves unified"). The game's
-- plate rounds its layout to the nearest pixel, every frame and region of
-- it, once, at its making (Blizzard_NamePlateUnitFrame.lua OnLoad:
-- PixelUtil.SetRoundLayoutToNearestPixelRecursively); what MelloUI adds to a
-- plate later -- the bracket and its trough, the level ring and its disc,
-- the name shade, the crest, the marks -- kept its own sub-pixel layout and
-- slid against the game's rounded parts as the plate moved. The plate's
-- tree is rounded again after the game lays it out (UpdateAnchors: its
-- acquire and option changes, never per frame), walked by varargs (no
-- table made), only what is not rounded yet set; a value read secret is
-- left alone.
--------------------------------------------------------------------------------
local Round = { DEPTH = 6 }

function Round.One(r)
	local ok, on = pcall(r.GetRoundLayoutToNearestPixel, r)
	if ok and not Secret(on) and on == false then
		pcall(r.SetRoundLayoutToNearestPixel, r, true)
	end
end

function Round.Regions(...)
	for i = 1, select("#", ...) do
		Round.One((select(i, ...)))
	end
end

function Round.Children(depth, ...)
	for i = 1, select("#", ...) do
		Round.Tree((select(i, ...)), depth)
	end
end

-- a call's results when it went through, else none
function Round.Ok(ok, ...)
	if ok then
		return ...
	end
end

-- (a forbidden frame -- the plate's aura icons, Blizzard_AuraContainerFrameProviders
-- -- is never touched: any call on it from our code raises, 2026-10-04)
function Round.Tree(frame, depth)
	if not (frame and frame.GetRoundLayoutToNearestPixel) then
		return
	end
	local okF, forbidden = pcall(frame.IsForbidden, frame)
	if not okF or Secret(forbidden) or forbidden then
		return
	end
	-- (nor a protected one: no secure frame's layout from here -- the hard rules)
	local okP, protected = pcall(frame.IsProtected, frame)
	if not okP or Secret(protected) or protected then
		return
	end
	Round.One(frame)
	if frame.GetRegions then
		Round.Regions(Round.Ok(pcall(frame.GetRegions, frame)))
	end
	if depth < Round.DEPTH and frame.GetChildren then
		Round.Children(depth + 1, Round.Ok(pcall(frame.GetChildren, frame)))
	end
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
	-- (0.16.0: the level circle sits on the right cap's diamond, HangLevel:
	-- the bracket is the whole plate, gem to gem)
	span:ClearAllPoints()
	span:SetPoint("TOPLEFT", capL, "TOPLEFT", 0, 0)
	span:SetPoint("RIGHT", capR, "RIGHT", 0, 0)
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

-- the bracket's units per the units of `region`'s frame (its scale against
-- the frame the region is drawn on: the level frame, the name's), 1 where a
-- scale raises or reads secret
local function StripRatio(strip, region)
	local okB, sb = pcall(strip.GetEffectiveScale, strip)
	local okP, parent = pcall(region.GetParent, region)
	local okO, so = false, nil
	if okP and type(parent) == "table" then
		okO, so = pcall(parent.GetEffectiveScale, parent)
	end
	if okB and okO and not Secret(sb) and not Secret(so) and type(sb) == "number" and type(so) == "number" and so > 0 then
		return sb / so
	end
	return 1
end

-- The level circle ON the right cap's diamond, covering it (user, 2026-09-30:
-- "the circle where the level is ... should be on top of the right diamond
-- exactly to cover it up"). The game's level frame stays where the game
-- lays it (its own layout reads that frame's anchor to size the bar); only
-- its parts move, which the game lays once from its template and never again
-- (Blizzard_NamePlates/Camelot/Blizzard_NamePlateLevelFrame.xml): the circle
-- centred on the diamond at the orb's size (the kit's orb and its disc
-- follow it, the skull hangs on it), the number on the circle, the target
-- ring round the circle as the template has it round the frame. The
-- template's places back when the kit comes off. The diamond's centre:
-- GEM_R of the right cap's width in from its right end (bars/frame_cap_r,
-- measured: its widest column), at the cap's middle height.
local GEM_R = 0.24

local function HangLevel(uf, on)
	local lf = uf.PlayerLevelDiffFrame
	local icon = lf and lf.playerLevelDiffIcon
	if not icon then
		return
	end
	local text, ring = lf.playerLevelDiffText, lf.selectedBorder
	local strip = uf.melloBracket and uf.melloBracket.strip
	local h = strip and strip.height
	if on and strip and strip.capR and type(strip.wr) == "number" and type(h) == "number" and h > 0 then
		local ratio = StripRatio(strip, icon)
		icon:ClearAllPoints()
		icon:SetPoint("CENTER", strip.capR, "RIGHT", -strip.wr * GEM_R * ratio, 0)
		icon:SetSize(h * ratio, h * ratio)
		if text then
			text:ClearAllPoints()
			text:SetPoint("CENTER", icon, "CENTER", 0, 0)
		end
		if ring then
			ring:ClearAllPoints()
			ring:SetPoint("TOPLEFT", icon, "TOPLEFT", -3, 4)
			ring:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 3, -4)
		end
		return
	end
	-- the template's places
	icon:ClearAllPoints()
	icon:SetPoint("TOPLEFT", lf, "TOPLEFT", 0, 0)
	icon:SetPoint("BOTTOMRIGHT", lf, "BOTTOMRIGHT", 0, 0)
	if text then
		text:ClearAllPoints()
		text:SetPoint("CENTER", lf, "CENTER", 0, 0)
	end
	if ring then
		ring:ClearAllPoints()
		ring:SetPoint("TOPLEFT", lf, "TOPLEFT", -3, 4)
		ring:SetPoint("BOTTOMRIGHT", lf, "BOTTOMRIGHT", 3, -4)
	end
end

-- The level circle as tall as the bracket, gem to gem (user, 2026-09-23:
-- "cap the level circle to the bar height"): the game grows its level frame
-- faster than the bar with each nameplate size, so the orb dwarfed the bar
-- on the large sizes. Sized from the bracket's own height (a plain number,
-- where a plate's frames read secret), across any scale between the bar and
-- the level frame; again on each of the game's layouts (each scale read on
-- its own pcall, no closure: no garbage per layout, backlog B11).
local function FitLevelOrb(uf)
	local orb, bracket = uf.melloLevelOrb, uf.melloBracket
	local strip = bracket and bracket.strip
	local tex = orb and orb.tex
	local h = strip and strip.height
	if not (tex and type(h) == "number" and h > 0) then
		return
	end
	local ratio = StripRatio(strip, tex)
	tex:SetSize(h * ratio, h * ratio)
	HangLevel(uf, active)
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

-- (0.16.0: the UI Shade's Shade Strength, one for the whole UI)
local function ShadeStrength()
	local v = Kit.ShadeStrength and Kit:ShadeStrength()
	v = Num(v)
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

--------------------------------------------------------------------------------
-- The marks (0.15.0; user, 2026-09-28: the approved sketch's style A): an
-- elite's, rare's, rare elite's or boss's plate wears a small crest before
-- its name (a crown, a silver star, a gold star, a skull) and its left end cap
-- and level orb in the unit's metal (gold, silver, red-bronze). One system
-- with the unit frames' (Modules/KitMarks.lua): the cap's and the orb's piece
-- swapped for its baked twin of the same shape, so nothing is laid out again
-- and their shade follows. The crest is the one piece added (the approved
-- addition; the game's own elite / rare icon faded meanwhile: one mark a
-- plate): a region of the name's frame made on the plate's first marked unit
-- (a crowd of plain units makes none), hung before the name's first letter
-- (on the name's measure, below) and sized from the bracket's height (a plain
-- number; every size under a plate reads secret). Told by the game's own
-- plate added (a recycled plate is marked again), UNIT_CLASSIFICATION_CHANGED
-- and INSTANCE_ENCOUNTER_ENGAGE_UNIT (an encounter's boss units changed: a
-- boss unit is a boss), registered only while the kit and the option are on.
--------------------------------------------------------------------------------
local CREST_SHARE = 0.7   -- the crest's height, of the bracket's (the level orb's): the sketch's 0.6, a touch larger to read
local CREST_GAP = 2       -- plate units between the crest and the name's first letter
-- the game's own icons for what the crest says (Blizzard_NamePlateClassificationFrame)
local GAME_MARKS = { ["nameplates-icon-elite-gold"] = true, ["nameplates-icon-elite-silver"] = true,
	["UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star"] = true }

-- (Kit.WearMark: the marks' system, Modules/KitMarks.lua, is loaded -- a
-- world without it, as a test's, shows no marks)
local function MarksOn()
	return active and Kit.WearMark ~= nil and M.db ~= nil and M.db.marks ~= false
end

-- the game's own elite / rare icon faded while the crest says it (put back
-- when the crest goes; a PvP icon in its place is left alone)
local function GameMark(uf, ours)
	local frame = uf.ClassificationFrame
	local icon = type(frame) == "table" and frame.classificationIndicator
	if type(icon) ~= "table" then
		return
	end
	if ours then
		local atlas = frame.classificationAtlasElement
		ours = type(atlas) == "string" and not Secret(atlas) and GAME_MARKS[atlas] or false
	end
	if ours then
		if not icon.melloMarkFaded then
			icon.melloMarkFaded = true
			icon:SetAlpha(0)
		end
	elseif icon.melloMarkFaded then
		icon.melloMarkFaded = nil
		icon:SetAlpha(1)
	end
end

-- the crest before the name's first letter: on the name's measure while it
-- holds the text and the name is centred on the bracket (by us), else on the
-- name's own left edge (a left-justified name, one inside the bar); anchored
-- again on a change only
local function HangCrest(uf)
	local crest = uf.melloCrest
	if not crest then
		return
	end
	local name = uf.name
	local on = (uf.melloNameMeasured and name.melloCentred ~= nil and uf.melloNameMeasure) or name
	if crest.melloOn ~= on then
		crest.melloOn = on
		crest:ClearAllPoints()
		crest:SetPoint("RIGHT", on, "LEFT", -CREST_GAP, 0)
	end
end

-- the crest shows while the kit and the option are on, the plate's unit is
-- marked and the game shows the name
local function SyncCrest(uf)
	local crest = uf.melloCrest
	if not crest then
		return
	end
	local want = (MarksOn() and uf.melloMark ~= nil and uf.name.melloNameShown) and true or false
	if crest:IsShown() ~= want then
		crest:SetShown(want)
	end
	GameMark(uf, want)
end

-- The game picks its icon in its own UNIT_CLASSIFICATION_CHANGED handler (the
-- plate's ClassificationFrame), which may run after ours and would show its
-- icon beside the crest; a raid mark taken off brings it back too. So the
-- fade is looked at again each time the game has picked it (hooked once, on
-- the plate's first crest: a plate without one has nothing to fade)
local OnGameClassification = Perf.Shared("UpdateClassificationIndicator on a nameplate (its crest)", function(frame)
	local uf = frame.melloPlate
	if uf then
		SyncCrest(uf)
	end
end)
local function WatchGameMark(uf)
	local frame = uf.ClassificationFrame
	if type(frame) == "table" and not frame.melloPlate and type(frame.UpdateClassificationIndicator) == "function" then
		frame.melloPlate = uf
		hooksecurefunc(frame, "UpdateClassificationIndicator", OnGameClassification)
	end
end

local function NameShown(name, shown)
	name.melloNameShown = shown
	local uf = name.melloShadeOf
	if uf then
		SyncBand(uf)
		SyncCrest(uf)
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

-- The name's measure is the shared one (MelloUI.Shade:Measure, Core/Shade.lua:
-- the centre texts' too; 0.14.0): an unseen font string in the name's font
-- (its font object, face, size, flags and text scale, each handed on as it
-- comes; a secret or refused one left as it was), again after each of the
-- game's layouts (FitShade) and, one frame after a new font (Font Style, the
-- faces), for every measure at once (Shade's one 'fonts' listener)
local Shade = MelloUI.Shade

-- the band on the measure (measured: it holds the name's text) or on the
-- name's whole span (it refused the name), and the crest before the name;
-- each re-anchored on a change only
local function Hang(uf)
	local measured = uf.melloNameMeasured == true
	local band = uf.melloNameShade
	if band and uf.melloBandMeasured ~= measured then
		uf.melloBandMeasured = measured
		if measured then
			band:Anchor(uf.melloNameMeasure, BAND_PAD_X, BAND_PAD_Y)
		else
			band:Anchor(uf.name, SPAN_PAD_X, BAND_PAD_Y)
		end
	end
	HangCrest(uf)
end

local function Measured(uf, measured)
	uf.melloNameMeasured = measured and true or false
	Hang(uf)
end

-- the name's text handed on to its measure, untouched (the call answers
-- whether the measure took it: a client that refuses a secret text there
-- leaves that plate's band on the span)
local OnNameText = Perf.Shared("SetText on a nameplate's name (its shade's measure)", function(name, text)
	local uf = name.melloShadeOf
	local measure = uf and uf.melloNameMeasure
	if measure then
		Measured(uf, Shade:MeasureText(measure, text))
	end
end)
local OnNameFormatted = Perf.Shared("SetFormattedText on a nameplate's name (its shade's measure)", function(name, ...)
	local uf = name.melloShadeOf
	local measure = uf and uf.melloNameMeasure
	if measure then
		Measured(uf, Shade:MeasureFormatted(measure, ...))
	end
end)

-- the frame that draws the name: the band lies under the name (over the
-- world, under the bar), the crest beside it
local function NameHost(uf)
	local name = uf.name
	local okP, host = pcall(name.GetParent, name)
	if not okP or type(host) ~= "table" or not host.CreateTexture then
		host = uf
	end
	return host
end

-- The name's measure and the name's hooks, made once per plate by whichever
-- wants them first: the band, or a mark's crest (hung before the text). The
-- measure: no width of its own, on one point at the name's centre (the name
-- is centred on the span while the band shows), sized by the engine to the
-- text (none where the name's frame makes no text: the band then lies on the
-- span, the crest on the name's left edge)
local function WatchName(uf)
	local name = uf.name
	if name.melloShadeOf then
		return
	end
	local measure = Shade:Measure(NameHost(uf), name, "CENTER")
	uf.melloNameMeasure = measure
	local okT, text = pcall(name.GetText, name)
	uf.melloNameMeasured = (measure and okT and Shade:MeasureText(measure, text)) and true or false
	local okS, shown = pcall(name.IsShown, name)
	name.melloNameShown = not okS or Secret(shown) or (shown and true or false)
	name.melloShadeOf = uf
	hooksecurefunc(name, "Show", OnNameShow)
	hooksecurefunc(name, "Hide", OnNameHide)
	hooksecurefunc(name, "SetShown", OnNameSetShown)
	hooksecurefunc(name, "SetText", OnNameText)
	hooksecurefunc(name, "SetFormattedText", OnNameFormatted)
end

local function MakeBand(uf)
	if not uf.name then
		return nil
	end
	BAND.alpha = ShadeStrength()
	local band = Shade:Band(NameHost(uf), BAND)
	if not band then
		return nil
	end
	uf.melloNameShade = band
	WatchName(uf)
	Hang(uf)
	return band
end

-- the plate's pieces that get a partner: the bracket's caps and rail, the
-- orb, a mark's crest (once the plate has one)
local function PlatePieces(uf)
	local strip = uf.melloBracket and uf.melloBracket.strip
	local orb = uf.melloLevelOrb and uf.melloLevelOrb.tex
	if strip then
		return strip.capL, strip.mid, strip.capR, orb, uf.melloCrest
	end
	return nil, nil, nil, orb, uf.melloCrest
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
	if mode ~= "plate" or not Kit:ShadeOn("nameplates") then
		return false
	end
	local capL, mid, capR, orb, crest = PlatePieces(uf)
	return (capL and not capL.kitShadow) or (mid and not mid.kitShadow) or (capR and not capR.kitShadow)
		or (orb and not orb.kitShadow) or (crest and not crest.kitShadow) or false
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
	-- the partners: Whole plate, and the UI Shade's Nameplates area on
	local plate = mode == "plate" and Kit:ShadeOn("nameplates")
	local capL, mid, capR, orb, crest = PlatePieces(uf)
	ShadePiece(capL, plate, strength, make)
	ShadePiece(mid, plate, strength, make)
	ShadePiece(capR, plate, strength, make)
	ShadePiece(orb, plate, strength, make, uf.melloOrbScale)
	ShadePiece(crest, plate, strength, make, uf.melloCrestScale)
	-- (what was just made, on the plate's one pixel grid: One pixel grid, above)
	if make and active then
		Round.Tree(uf, 0)
	end
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
		Shade:MeasureFont(measure)
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

-- The crest as tall as CREST_SHARE of the bracket (from the bracket's own
-- height, a plain number, across any scale between the bracket and the
-- name's frame), at its piece's aspect (every crest square, the rare elite's
-- too: no wings); its partner's reach with it
local function FitCrest(uf)
	local crest = uf.melloCrest
	local strip = uf.melloBracket and uf.melloBracket.strip
	local h = strip and strip.height
	local piece = crest and crest.kitName and Kit:Piece(crest.kitName)
	if not (piece and piece.h > 0 and type(h) == "number" and h > 0) then
		return
	end
	local ch = h * CREST_SHARE * StripRatio(strip, crest)
	crest:SetSize(ch * piece.w / piece.h, ch)
	uf.melloCrestScale = ch / piece.h
	if crest.kitShadow then
		Kit:ShadowFit(crest, uf.melloCrestScale)
	end
end

-- the unit the plate shows now (the game's own field; none on a plate put
-- away)
local function PlateUnit(uf)
	local unit = uf.unit
	if type(unit) == "string" and not Secret(unit) then
		return unit
	end
	return nil
end

-- The plate's marks as its unit is now (`unit`: the plate just added; else
-- the plate's own): the left cap and the level orb in the metal or plain, the
-- crest made on the plate's first marked unit (and shaded as the plate is),
-- showing that unit's mark. Nothing made for a plain unit, nothing made per
-- call once a plate has its crest
local function MarkPlate(uf, unit)
	if not Kit.WearMark then
		return
	end
	local kind = MarksOn() and Kit:MarkOf(unit or PlateUnit(uf)) or nil
	local was = uf.melloMark
	uf.melloMark = kind
	local strip = uf.melloBracket and uf.melloBracket.strip
	if strip then
		Kit:WearMark(strip.capL, Kit:StripPieceName(strip.base, "cap_l", strip.state), kind)
		-- (the target's highlight leaves a metal cap as it is: again when a
		-- mark comes or goes)
		if (was == nil) ~= (kind == nil) and uf.melloBracket.melloShine then
			uf.melloBracket.melloShine()
		end
	end
	local orb = uf.melloLevelOrb
	if orb and orb.tex then
		Kit:WearMark(orb.tex, orb.rule.piece, kind)
	end
	local crest = uf.melloCrest
	local made = false
	if kind and not crest and uf.name then
		WatchName(uf)
		crest = NameHost(uf):CreateTexture(nil, "ARTWORK")
		crest:Hide()
		uf.melloCrest = crest
		made = true
		WatchGameMark(uf)
	end
	if not crest then
		return
	end
	local piece = kind and Kit:MarkCrest(kind)
	if piece and crest.kitName ~= piece then
		Kit:Apply(crest, piece)
		FitCrest(uf)
	end
	HangCrest(uf)
	SyncCrest(uf)
	if made then
		ShadePlate(uf)   -- (its partner on Whole plate, as the plate's other pieces)
	end
end

-- every dressed plate as its unit is now
local function MarkAll()
	if skin then
		for _, uf in ipairs(skin.plates) do
			MarkPlate(uf)
		end
	end
end

-- UNIT_CLASSIFICATION_CHANGED: a shown plate's unit changed what it is;
-- INSTANCE_ENCOUNTER_ENGAGE_UNIT: the boss units changed (a pull, a boss
-- gone, the encounter over), so a plate's unit may have become a boss or
-- stopped being one (the burst at a pull marks once, a frame later)
local function OnMarksEvent(_, event, unit)
	if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
		if active then
			Kit:NextFrame(MarkAll, MarkAll)
		end
		return
	end
	if not active or type(unit) ~= "string" or Secret(unit) or not unit:find("^nameplate") then
		return
	end
	local ok, base = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	local uf = ok and type(base) == "table" and base.UnitFrame
	if type(uf) == "table" and uf.melloKit then
		MarkPlate(uf, unit)
	end
end

-- the event wanted while the kit and the option are on, none else; every
-- dressed plate as its unit is now
local marksFrame = nil   -- (made the first time the marks are on)
local function MarksSync()
	if not skin then
		return
	end
	local on = MarksOn()
	if on and not marksFrame then
		marksFrame = CreateFrame("Frame")
		Perf.SetScript(marksFrame, "OnEvent", OnMarksEvent)
	end
	if marksFrame then
		if on then
			marksFrame:RegisterEvent("UNIT_CLASSIFICATION_CHANGED")
			marksFrame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
		else
			marksFrame:UnregisterEvent("UNIT_CLASSIFICATION_CHANGED")
			marksFrame:UnregisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
		end
	end
	MarkAll()
end

-- the Nameplate Border swapped live (Kit:ApplyBorder -> rep:SetBar, then
-- this): the new bracket's partners at its new scale, its left cap marked,
-- the crest at the new bracket's height
local function OnBarChanged(rep)
	local uf = rep.melloPlate
	if uf then
		FitShade(uf)
		MarkPlate(uf)
		FitCrest(uf)
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
				-- (run on every Show / Hide / SetShown of every plate's highlight:
				-- the three pieces coloured directly, no list made per call;
				-- a shown state that reads secret counts as not shown)
				local function Shine()
					local strip = rep.strip
					if not strip then
						return
					end
					local shown = sel:IsShown()
					local r, g, b = 1, 1, 1
					if active and not Secret(shown) and shown then
						r, g, b = 1, 0.5, 0   -- the full orange-gold the iron can take (user, 2026-09-21: "increase it more", twice)
					end
					-- a marked plate's left cap is its metal (the marks): the
					-- orange would turn gold, silver and red-bronze alike
					if uf.melloMark then
						strip.capL:SetVertexColor(1, 1, 1)
					else
						strip.capL:SetVertexColor(r, g, b)
					end
					strip.mid:SetVertexColor(r, g, b)
					strip.capR:SetVertexColor(r, g, b)
				end
				rep.melloShine = Shine
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
						strip.capL:SetVertexColor(1, 1, 1)
						strip.mid:SetVertexColor(1, 1, 1)
						strip.capR:SetVertexColor(1, 1, 1)
					end
				end
			end
			hooksecurefunc(uf, "UpdateAnchors", function()
				Inset.done[hb] = nil   -- the game re-anchored the bar from scratch
				if uf.name then
					uf.name.melloCentred = nil   -- the game re-anchored the name too
				end
				InsetHealthBar(hb, rep, container)
				rep:Refit()
				CentreName(uf, hb, rep)
				FitLevelOrb(uf)
				FitShade(uf)
				FitCrest(uf)
				HangCrest(uf)
				-- (every part on the plate on the game's one pixel grid)
				if active then
					Round.Tree(uf, 0)
				end
			end)
			local enable = rep.onEnable
			rep.onEnable = function(...)
				if enable then
					enable(...)
				end
				InsetHealthBar(hb, rep, container, true)
				CentreName(uf, hb, rep)
				FitShade(uf)
				HangCrest(uf)
				Round.Tree(uf, 0)
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
				HangCrest(uf)
				-- the game's anchors back (its own layout, no arms, no margin)
				if Inset.done[hb] and container then
					Inset.done[hb] = nil
					Inset.Lay(hb, container, 0, 0, 0)
				end
				rep.thicken, rep.fitHeight = nil, Option("healthBarHeight", 12)
			end
			if active then
				InsetHealthBar(hb, rep, container, true)
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
		-- the level number's dark ground (the unit frames' too: Kit:OrbDisc)
		if Kit.OrbDisc then
			Kit:OrbDisc(uf.melloLevelOrb, lf)
		end
		local orb = uf.melloLevelOrb
		if orb then
			local enable, disable = orb.onEnable, orb.onDisable
			orb.onEnable = function(...)
				if enable then
					enable(...)
				end
				HangLevel(uf, true)
			end
			orb.onDisable = function(...)
				if disable then
					disable(...)
				end
				HangLevel(uf, false)
			end
		end
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
	-- (the dressed plate on the game's one pixel grid)
	if active then
		Round.Tree(uf, 0)
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

-- UI Shade switched or its strength moved: the bus's 'shade' for the
-- Nameplates area (Modules/KitShade.lua; the area has no switch of its own
-- since 0.16.0). The Whole plate partners follow it, and the bands take the
-- strength
local function OnShade(area)
	if area == "nameplates" and active then
		ShadeAll(ShadeStrength())
	end
end

local function Build()
	if skin then
		return
	end
	skin = { reps = {}, followers = {}, plates = {} }
	-- (taken with the first dressing, once)
	MelloUI:On("shade", OnShade, "Nameplate Kit shade")
	SkinAll()
	if NamePlateDriverFrame then
		hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", function(driver, unit)
			if not active then
				return
			end
			local ok, base = pcall(driver.GetNamePlateForUnit, driver, unit)
			if ok and base and base.UnitFrame then
				SkinUnitFrame(base.UnitFrame)
				-- (a recycled plate too: the last unit's marks go)
				MarkPlate(base.UnitFrame, unit)
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
	-- (the marks as the plates' units are now, their event on)
	MarksSync()
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	-- (the plain pieces back, the crests hidden, the marks' event off)
	MarksSync()
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
	elseif key == "marks" then
		MarksSync()
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
			local strip = uf.melloBracket and uf.melloBracket.strip
			MelloUI:Print("mark: %s (cap %s, crest %s)", tostring(uf.melloMark or "none"), tostring(strip and strip.capL.kitName),
				uf.melloCrest and (uf.melloCrest:IsShown() and "shown" or "hidden") or "none")
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
