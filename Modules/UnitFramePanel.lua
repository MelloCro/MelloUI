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
--   N3  the tabs/top title plate on the name band -- retired 2026-10-03
--       (user: longer names did not fit it): the name centred on the band's
--       rect as before, the nameplates' soft shade behind it (below), on
--       every unit frame's name
--   the level orb's dark ground under the number, as the nameplates' (user,
--       2026-10-03: Kit:OrbDisc)
-- The game's elite / rare / boss rings are faded; the Elite / Rare / Rare
-- Elite / Boss marks (0.15.0, Modules/KitMarks.lua, the option `marks`) put
-- the target's and focus's ring and level orb in the unit's metal with a
-- crest on the ring's top gem instead (below). Bar Textures drops its shaped
-- mask on a bracketed bar (`melloKitBracket`) so the flat fill spans the rect
-- under the rails.
-- Covers the Dark Mode group "unitframes" while on (Kit:Cover).
-- The UI shade (0.14.0, Modules/KitShade.lua, its area "unitframes"): each
-- unit frame is one element whose shade lies under the whole frame (below).
-- M:ReminderAnchor() -> region, side, reach, far | nil: where the Reminder
-- widget (Core/Reminders.lua) hangs, beside the player's portrait ring (below).
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
	-- (include: the option below sits under this row on UI Modifications' HUD tab)
	window = { label = "Unit frames", desc = "Player, target, focus, pet and party frames in the kit.", tab = "HUD", include = true },
	enabledByDefault = true,
	defaults = { marks = true, barBackground = "kit", barBackgroundAlpha = 100 },
	options = {
		{ type = "toggle", key = "marks", name = "Elite and Rare Marks",
		  desc = "The target's and focus's portrait ring and level circle in gold for an elite, silver for a rare or rare elite and red-bronze for a boss, with a small crest on the ring's top gem: a crown, a silver star, a gold star or a skull. Their target's ring too." },
		{ type = "dropdown", key = "barBackground", name = "Bar Background", values = {
			{ value = "kit", label = "Painted Trough" },
			{ value = "dark", label = "Dark" },
			{ value = "texture", label = "Bar Texture, Dark" },
			{ value = "none", label = "None" },
		  },
		  desc = "What lies behind the health and power bars, under the fill, the heals coming in and the bars' borders: the painted dark trough, a flat dark, the Bar Texture's finish in the dark, or nothing. Every unit frame: the player, target, focus, pet, target of target and party." },
		{ type = "slider", key = "barBackgroundAlpha", name = "Bar Background Opacity", min = 0, max = 100, step = 5,
		  format = function(v) return math.floor(v + 0.5) .. "%" end,
		  desc = "How solid the bars' background is: lower lets the world show through the empty part of a bar." },
	},
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
local Num = MelloUI.Safe.Number

--------------------------------------------------------------------------------
-- The UI shade (0.14.0; the one shade system, Modules/KitShade.lua, its area
-- "unitframes"; user, 2026-09-26: on by default, outline pieces only). Each
-- unit frame is ONE element -- the player, the pet, the target, the focus,
-- the target of target, each party member with its pet -- drawn by a
-- shade frame one level under the frame the unit's art stands on: every
-- partner lies under the whole frame (a health bar's under the name band and
-- the ring, which are regions of frames below the bar's), over the world.
-- The shade frame is never anchored on an Edit Mode system: the player's,
-- target's and focus's element is rooted on their container (the frame
-- under their content, one level above the unit's button), the party
-- backdrop's on the backdrop; the pet frame (a system with no container,
-- its art on its own button; Edit Mode may move it off the player frame,
-- to UIParent) gets a shade frame of its own (KitShade's opts.host), its
-- child one level under it, anchored on its picture. The target of target
-- stands five levels over its target frame (the game's) and over that
-- frame's bottom edge, under its ring: its shade frame sits at the target
-- frame's own level, so its shade never lies on the target's art. Only the
-- pieces on the frame's outline get one: the portrait ring, the bars'
-- brackets (a bracket running capless into the ring fades
-- out softly on that side: the left on the player's, the right on the
-- mirrored target's), the level / PvP orbs, and the party backdrop's rail.
-- Never the trough, the ring's cover over the bars' ends (a crop) or a faded
-- picture. The party members lie on that backdrop's stone while Edit Mode
-- shows it: their own shade is put away then (never a dark halo on a
-- surface). Each unit's shade is made on its frame's FIRST SHOW, never
-- before (nothing built at login for a frame nobody sees: a focus never
-- set, the party pool's hidden members -- the game keeps four --, the
-- backdrop Edit Mode shows only when asked); its parts wait in order.
--------------------------------------------------------------------------------
local SHADE_AREA = "unitframes"
local DUE_KEY = "Unit frames: shade on first show"   -- (Kit:WhenOutOfCombat's key)
-- a square piece drawn at its rect's size, not at its kit scale (the ring
-- round its portrait, the orb on its circle): KitShade reads its shade's
-- scale from the width it is drawn at (one table for every such part)
local DRAWN = { drawn = true }

-- the unit frame's element (nil where the shade system is not loaded);
-- opts: KitShade's (read once, on the element's first ask)
local function ShadeOf(root, opts)
	if not (root and Kit.ShadeElement) then
		return nil
	end
	local ok, el = pcall(Kit.ShadeElement, Kit, root, SHADE_AREA, opts)
	return ok and el or nil
end

-- the pet frame's element: its own shade frame, a child of the pet's button
-- one level under it (hidden, scaled and moved with it wherever Edit Mode
-- puts it), anchored on its picture -- never on the pet frame itself (made
-- once, out of combat: MakeUnit's)
local function PetShade(pf, picture)
	if not (Kit.ShadeElement and pf and picture) then
		return nil
	end
	local host = CreateFrame("Frame", nil, pf)
	host:SetFrameLevel(math.max(pf:GetFrameLevel() - 1, 0))
	host:EnableMouse(false)
	host:SetAllPoints(picture)
	host.ignoreInLayout = true
	host.kitShadeHost = true
	return ShadeOf(pf, { host = host })
end

-- a drawn piece re-sized (a rect laid out after the piece was made, its
-- sizer): its shade reaches as far at the new size -- from the size set, no
-- read; nothing when the size is the same (Kit:ShadowFit). KitShade's
-- DrawnScale's measure (the piece's painted width, Kit:Size)
local Drawn_OnSetSize = Perf.Shared("SetSize on a unit frame's ring or orb: its shade", function(tex, w)
	w = Num(w)
	local pw = w and w > 0 and tex.kitShadow and tex.kitName and Kit:Size(tex.kitName, 1)
	if pw and pw > 0 then
		Kit:ShadowFit(tex, w / pw)
	end
end)

-- one outline part added to a made element
local function AddPart(el, rep, drawn)
	if not el then
		return
	end
	if drawn then
		local tex = rawget(rep, "tex")
		if tex and not tex.melloShadeSized then
			tex.melloShadeSized = true
			hooksecurefunc(tex, "SetSize", Drawn_OnSetSize)
		end
		el:Add(rep, DRAWN)
	else
		el:Add(rep)
	end
end

-- A unit: its shade's element and parts, made on its frame's first show.
--   { watch = the frame whose first show makes it, root = the element's
--     root, picture = (the pet) its own shade frame's anchor, party = (a
--     party member) its shade frame put away with the backdrop, under = (a
--     target of target) the frame whose level its shade frame takes, el =
--     the element once made, made, due, n, [2i - 1] = rep, [2i] = drawn }
local function Unit(watch, root)
	if not (watch and root) then
		return nil
	end
	return { watch = watch, root = root, n = 0 }
end

-- one outline part of the unit: a rep (its strip, skin or texture);
-- `drawn` for a square piece fitted to its rect. Kept until the unit is made
local function Shade(u, rep, drawn)
	if not (u and rep) then
		return
	end
	if u.made then
		AddPart(u.el, rep, drawn)
		return
	end
	local n = u.n + 2
	u[n - 1], u[n], u.n = rep, drawn and true or false, n
end

-- The party backdrop (Edit Mode's "Show Party Frame Background") shown: the
-- members lie on its stone, so their shade frames are hidden and the
-- backdrop's rail carries the group's shade; hidden: each member's own.
-- Shade frames are ours (never protected): shown and hidden in a fight too.
local function PartyShadeSync()
	local bg = PartyFrame and PartyFrame.Background
	if not (skin and bg) then
		return
	end
	-- (a secret or refused answer: the backdrop counted as hidden, each
	-- member keeping its shade)
	local ok, shown = pcall(bg.IsShown, bg)
	local own = not (ok and not Secret(shown) and shown)
	for _, u in pairs(skin.party) do
		local el = u.el
		local host = el and el.host
		if host then
			host:SetShown(own)
		end
	end
end

-- the unit's element made and its parts added, in order (out of combat: a
-- shade frame is a unit frame's child)
local function MakeUnit(u)
	if u.made then
		return
	end
	u.made = true
	local el
	if u.picture then
		el = PetShade(u.root, u.picture)
	else
		local opts = nil
		local under = u.under
		if under then
			local okU, lu = pcall(under.GetFrameLevel, under)
			local okR, lr = pcall(u.root.GetFrameLevel, u.root)
			lu, lr = okU and Num(lu), okR and Num(lr)
			if lu and lr and lu - lr < -1 then
				opts = { level = lu - lr }
			end
		end
		el = ShadeOf(u.root, opts)
	end
	u.el = el
	-- (a member's shade frame first, so the backdrop's state reaches it
	-- before its parts are made)
	if el and u.party then
		el:Host()
	end
	for i = 1, u.n, 2 do
		AddPart(el, u[i], u[i + 1])
		u[i], u[i + 1] = nil, nil
	end
	u.n = 0
	if u.party then
		PartyShadeSync()
	end
end

-- the units shown for the first time, made (out of combat)
local function MakeDue()
	local list = skin and skin.due
	if not list then
		return
	end
	-- (each on its own: one unit's error never strands the rest)
	for i = 1, #list do
		local u = list[i]
		list[i] = nil
		local ok, err = pcall(MakeUnit, u)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

local function Due(u)
	if u.made or u.due then
		return
	end
	u.due = true
	local list = skin.due
	list[#list + 1] = u
	Kit:WhenOutOfCombat(MakeDue, DUE_KEY)
end

-- a watched frame's show: its unit made the first time (after it, a lookup)
local Unit_OnShow = Perf.Shared("OnShow on a unit frame: its shade, the first time", function(frame)
	local u = skin and skin.units[frame]
	if u then
		skin.units[frame] = nil
		Due(u)
	end
end, "script")

-- the unit made now when its frame is seen (a secret or refused answer
-- too), else on its first show
local function Watch(u)
	if not u then
		return
	end
	local watch = u.watch
	local ok, seen = pcall(watch.IsVisible, watch)
	if ok and not Secret(seen) and not seen then
		skin.units[watch] = u
		Perf.HookScript(watch, "OnShow", Unit_OnShow)
	else
		Due(u)
	end
end

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

-- Bar Background (0.19.0; user, 2026-10-04: "i need a option to change the
-- unitframe background"): what lies in a bracket's opening under the fill,
-- the heals coming in (HealerFrames) and the rails -- the bracket's trough.
-- One look for every bracketed bar here (the player, target, focus, pet,
-- target of target, party members, the preview's stand-ins): "kit" the
-- painted trough as before, "dark" a flat innerPanel, "texture" the Bar
-- Texture's finish in mainWindow, "none" nothing; its opacity. Set on the
-- trough itself (MelloUI's region): a palette paint follows the palette and
-- the dark-mode shade, the painted trough the kit's colours.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local BACKGROUND_KEY = { dark = "innerPanel", texture = "mainWindow" }

local function TroughFile(look)
	if look == "texture" then
		local bt = MelloUI:GetModule("BarTextures")
		local file = bt and bt.PreviewTexture and bt.PreviewTexture("unitframes")
		return file or MelloUI.Widgets.BarFill()
	end
	return WHITE
end

local function DressTrough(rep)
	local trough = rep and rep.trough
	if not trough then
		return
	end
	local db = M.db or {}
	local look = db.barBackground
	local key = BACKGROUND_KEY[look]
	if key then
		Kit:Apply(trough, nil)   -- (no piece: out of the kit's colours and tiling)
		trough:SetTexture(TroughFile(look))
		trough:SetTexCoord(0, 1, 0, 1)
		Kit:Paint(trough, key, "vertex")
	elseif trough.kitName ~= "bars/trough" then
		Kit:Unpaint(trough, "vertex")
		trough:SetVertexColor(1, 1, 1)
		Kit:Apply(trough, "bars/trough")
	end
	local alpha = Num(db.barBackgroundAlpha) or 100
	trough:SetAlpha(look == "none" and 0 or math.max(0, math.min(1, alpha / 100)))
end

local function DressTroughs()
	if not skin then
		return
	end
	for _, rep in ipairs(skin.reps) do
		if rep.kind == "bar" then
			DressTrough(rep)
		end
	end
end

-- the Bar Texture changed: the "texture" troughs take the new finish
local function OnBarSetting(module, key)
	if module == "BarTextures" and (key == "texture" or key == "unitframes") and M.db and M.db.barBackground == "texture" then
		DressTroughs()
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
	DressTrough(rep)
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
-- (0.19.0) [portrait] = the rep of the ring round it, for M:RingOf
local ringOf = setmetatable({}, { __mode = "k" })

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
	ringOf[portrait] = rep
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

-- (one function for every bar, called protected: nothing made per call)
local function TuckBarNow(bar, tex, mirrored)
	do
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
	end
end

local function TuckBar(bar, ring, mirrored)
	local tex = ring and ring.tex
	if not (bar and tex) then
		return
	end
	local ok = pcall(TuckBarNow, bar, tex, mirrored)
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
	-- the crop, as fractions of the ring (Lay's), and the ring's piece on the
	-- cover: again when the ring wears another piece (an Elite / Rare mark's
	-- metal twin, the same shape): texture calls only, so in a fight too
	local fx0, fx1, fy0, fy1
	local function Crop()
		if cover.kitName ~= tex.kitName then
			Kit:Apply(cover, tex.kitName)
		end
		local piece = tex.kitPiece
		if not (piece and fx0) then
			return
		end
		local u1, u2, v1, v2 = piece.uv[1], piece.uv[2], piece.uv[3], piece.uv[4]
		cover:SetTexCoord(u1 + (u2 - u1) * fx0, u1 + (u2 - u1) * fx1, v1 + (v2 - v1) * fy0, v1 + (v2 - v1) * fy1)
	end
	-- (laid protected: one function per cover, nothing made per call)
	local function Lay()
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
		fx0, fx1 = (cl - rl) / rw, (cr - rl) / rw
		fy0, fy1 = (rb + rh - ct) / rh, (rb + rh - cb) / rh
		Crop()
		local r, g, b = tex:GetVertexColor()
		cover:SetVertexColor(r or 1, g or 1, b or 1)
		holder:Show()
	end
	local function Refit()
		if not (active and tex:IsShown()) then
			holder:Hide()
			return
		end
		local ok = pcall(Lay)
		if not ok then
			holder:Hide()
		end
	end
	for _, bar in ipairs(bars) do
		Perf.HookScript(bar, "OnSizeChanged", function()
			Kit:WhenOutOfCombat(Refit)
		end)
	end
	local function Paint()
		local r, g, b = tex:GetVertexColor()
		cover:SetVertexColor(r or 1, g or 1, b or 1)
	end
	hooksecurefunc(tex, "SetVertexColor", function()
		if holder:IsShown() then
			pcall(Paint)
		end
	end)
	ring.cover = { holder = holder, Refit = Refit, Repiece = Crop }
	skin.covers[#skin.covers + 1] = ring.cover
	Refit()
	return ring.cover
end

-- The name centred on its band's rect (as a window's title on its plate;
-- the plate itself retired 2026-10-03, the soft shade behind the name
-- instead: NameShade): the game's anchors saved and put back on disable.
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

--------------------------------------------------------------------------------
-- The name shade (user, 2026-10-03: "most of the longer names dont fit into
-- the texture, why dont we just remove that texture and instead use the same
-- shadow effect under the names that we have behind the names on the
-- Nameplates. (For all Unitframes)"): the name plate (N3) is gone; behind
-- each unit frame's name -- the player's, the target's and the focus's,
-- their targets', the pet's, each party member's -- lies the shared soft band
-- (MelloUI.Shade) the nameplates have, as long as the name's text: hung on
-- the name's measure (Shade:Measure, an unseen copy of the name that the
-- engine sizes to its text; the text handed on from the name's own SetText
-- as it comes, a secret one too: nothing is read or compared). Where the
-- measure refuses a name, the band lies on the name's whole line. It draws
-- on the frame under the unit's art (the player's, target's and focus's
-- container; the others' own frame) at the bottom of its stack: under the
-- ring, the bars and the name. Its strength is the UI Shade's Shade Strength
-- (the bus's 'shade'); it shows while the skin is on and the game shows the
-- name. Made once per name, with its frame's dressing: no script, no work
-- per frame.
--------------------------------------------------------------------------------

-- the nameplates' band: its full middle 4 past the text's ends, its soft ends
-- 20 long, 5 above and below the text; on the name's line (the measure
-- refused the name): its middle 10 inside the line's ends
local NAME_BAND = { colour = "innerPanel", feather = 20, layer = "BACKGROUND", sublevel = -8 }
local NAME_PAD = { x = 4, y = 5, lineX = -10 }

local function NameStrength()
	local v = Kit.ShadeStrength and Num(Kit:ShadeStrength())
	if not v then
		return 0.7
	end
	return v < 0 and 0 or v > 1 and 1 or v
end

-- shown while the skin is on and the game shows the name
local function SyncNameShade(entry)
	local want = (active and entry.shown) and true or false
	if entry.band:IsShown() ~= want then
		entry.band:SetShown(want)
	end
end

-- on the measure (it took the name's text) or on the name's line; anchored
-- again on a change only
local function HangNameShade(entry, measured)
	measured = measured and true or false
	if entry.measured ~= measured then
		entry.measured = measured
		if measured then
			entry.band:Anchor(entry.measure, NAME_PAD.x, NAME_PAD.y)
		else
			entry.band:Anchor(entry.fs, NAME_PAD.lineX, NAME_PAD.y)
		end
	end
end

-- the name's band on `host` (once per name; after CenterName, so a centred
-- name's measure hangs on its centre, a left-justified one's on its left)
local function NameShade(fs, host)
	local Soft = MelloUI.Shade   -- (the shared bands; Shade here is the UI shade's)
	if type(fs) ~= "table" or type(fs.SetText) ~= "function" or type(host) ~= "table" or not (skin and Soft)
		or skin.nameShades[fs] then
		return
	end
	NAME_BAND.alpha = NameStrength()
	local band = Soft:Band(host, NAME_BAND)
	if not band then
		return
	end
	local okJ, justify = pcall(fs.GetJustifyH, fs)
	local point = (okJ and (justify == "LEFT" or justify == "RIGHT")) and justify or "CENTER"
	local entry = { fs = fs, band = band, measure = Soft:Measure(host, fs, point) }
	skin.nameShades[fs] = entry
	local okT, text = pcall(fs.GetText, fs)
	HangNameShade(entry, entry.measure and okT and Soft:MeasureText(entry.measure, text))
	local okS, shown = pcall(fs.IsShown, fs)
	entry.shown = not okS or Secret(shown) or (shown and true or false)
	hooksecurefunc(fs, "SetText", function(_, t)
		HangNameShade(entry, entry.measure and Soft:MeasureText(entry.measure, t))
	end)
	hooksecurefunc(fs, "SetFormattedText", function(_, ...)
		HangNameShade(entry, entry.measure and Soft:MeasureFormatted(entry.measure, ...))
	end)
	local function Shown(on)
		entry.shown = on
		SyncNameShade(entry)
	end
	hooksecurefunc(fs, "Show", function()
		Shown(true)
	end)
	hooksecurefunc(fs, "Hide", function()
		Shown(false)
	end)
	hooksecurefunc(fs, "SetShown", function(_, on)
		-- (asked for secret first: a secret answer counts as shown)
		Shown(Secret(on) or (on and true or false))
	end)
	SyncNameShade(entry)
end

-- every name's band: shown or hidden with the skin, at the Shade Strength
local function SyncNameShades(strength)
	if not skin then
		return
	end
	for _, entry in pairs(skin.nameShades) do
		if strength then
			entry.band:SetStrength(strength)
		end
		SyncNameShade(entry)
	end
end

-- UI Shade switched or its strength moved: the bus's 'shade' for the unit
-- frames' area (Modules/KitShade.lua)
local function OnShade(area)
	if area == SHADE_AREA then
		SyncNameShades(NameStrength())
	end
end

-- The level / PvP circle (L1): the orb under the frame's own text, following
-- the game's show / hide. `number`: the level text -- the level circle's orb
-- gets the nameplates' dark ground under it (user, 2026-10-03: "make it the
-- same as on the nameplates, circle with a black background";
-- Kit:OrbDisc, which also lifts the number over it: the two share OVERLAY).
-- Returns the rep.
local function SkinCircle(circle, number)
	if not circle then
		return nil
	end
	local rep = Replace(circle, { as = "UI-HUD-UnitFrame-SmallCircle" })
	Follow(rep, circle)
	if rep and number and Kit.OrbDisc then
		local okP, host = pcall(circle.GetParent, circle)
		Kit:OrbDisc(rep, okP and host or nil, number)
	end
	return rep
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
-- The Elite / Rare / Rare Elite / Boss marks (0.15.0; user, 2026-09-28: the
-- approved sketch's style B): the target's and the focus's portrait ring in
-- the unit's metal with a crest on its top gem (a crown, a silver star, a
-- gold star, a skull), their level orb in the metal, and
-- their target of target's ring. One system with the nameplates' (Modules/
-- KitMarks.lua): the ring's and the orb's piece swapped for its baked twin of
-- the same shape, so nothing is laid out again and the shade follows; the
-- ring's cover over the bars' ends takes the twin too. Texture calls only: a
-- target changed in a fight is marked at once. Told by the events that change
-- what a frame shows -- a new target or focus, their target's target, a
-- changed classification, an encounter's boss units changed (a boss unit is
-- a boss) -- registered only while the kit and the option are on. The
-- player, pet and party frames show players: never marked.
--------------------------------------------------------------------------------
local TOT_UNIT = { target = "targettarget", focus = "focustarget" }
local marksFrame = nil   -- the events' frame (made the first time the marks are on)

-- the unit a target-style frame shows (the game's own field, else its name's)
local function MarkUnitOf(frame)
	local unit = frame.unit
	if type(unit) == "string" and not Secret(unit) and TOT_UNIT[unit] then
		return unit
	end
	return frame == FocusFrame and "focus" or "target"
end

-- (Kit.WearMark: the marks' system, Modules/KitMarks.lua, is loaded -- a
-- world without it, as a test's, shows no marks)
local function MarksOn()
	return active and Kit.WearMark ~= nil and M.db ~= nil and M.db.marks ~= false
end

-- one marked frame: its ring (and the ring's cover) and level orb in the
-- metal of what its unit is now; plain with the marks off or no unit
local function MarkUnit(entry)
	if not (entry and Kit.WearMark) then
		return
	end
	local kind = MarksOn() and Kit:MarkOf(entry.unit) or nil
	entry.kind = kind
	local ring = entry.ring
	if ring and ring.tex then
		Kit:WearMark(ring.tex, ring.rule.piece, kind)
		if ring.cover then
			ring.cover.Repiece()
		end
	end
	local orb = entry.orb
	if orb and orb.tex then
		Kit:WearMark(orb.tex, orb.rule.piece, kind)
	end
end

-- every marked frame as its unit is now
local function MarkAll()
	local marks = skin and skin.marks
	if marks then
		for _, entry in pairs(marks) do
			MarkUnit(entry)
		end
	end
end

local function OnMarksEvent(_, event, unit)
	local marks = skin and skin.marks
	if not marks then
		return
	end
	if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
		-- the boss units changed (a pull, a boss gone, the encounter over):
		-- a frame's unit may have become a boss or stopped being one. The
		-- burst at a pull marks once, a frame later
		Kit:NextFrame(MarkAll, MarkAll)
	elseif event == "PLAYER_TARGET_CHANGED" then
		MarkUnit(marks.target)
		MarkUnit(marks.targettarget)
	elseif event == "PLAYER_FOCUS_CHANGED" then
		MarkUnit(marks.focus)
		MarkUnit(marks.focustarget)
	elseif type(unit) == "string" and not Secret(unit) then
		if event == "UNIT_TARGET" then
			local tot = TOT_UNIT[unit]
			MarkUnit(tot and marks[tot])
		else
			MarkUnit(marks[unit])   -- UNIT_CLASSIFICATION_CHANGED
		end
	end
end

-- the events wanted while the kit and the option are on, none else; every
-- marked frame as its unit is now
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
			marksFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
			marksFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
			marksFrame:RegisterUnitEvent("UNIT_TARGET", "target", "focus")
			marksFrame:RegisterUnitEvent("UNIT_CLASSIFICATION_CHANGED", "target", "focus")
			marksFrame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
		else
			marksFrame:UnregisterAllEvents()
		end
	end
	MarkAll()
end

--------------------------------------------------------------------------------
-- The target's combo points outside the ring (a player's screenshot via the
-- user, 2026-10-04: "the combopoints are on top of the Portrait Border and
-- hide the artwork, can you move them a bit more to the right side so that
-- they appear outside of the borders"). The game's ComboFrame (Camelot's, at
-- the target frame's top right) lays its ComboPoint frames on an arc that
-- hugs the game's own portrait ring; the kit's ring (R1) is wider, so the arc
-- lay on its bezel. While the kit dresses the frame each point stands on its
-- own angle of the game's arc, out from the ring's centre past its rim: hung
-- on the ring itself, so wherever the game puts the ComboFrame (it anchors it
-- again on every update, ComboFrame_ApplyOverrides) the points stay round the
-- ring, and nothing here runs per update (the game never anchors a point).
-- Laid when the kit comes on and when the target frame shows (the ring's size
-- known then), again only when the ring's width changed; the game's own
-- anchors back when the kit goes off.
--------------------------------------------------------------------------------

local Combo = {
	GAP = 2,          -- UI px between the ring's rim and a point
	saved = nil,      -- [i] = the point's own anchor, as the game laid it
	angles = nil,     -- [i] = its angle on the game's arc
	width = nil,      -- the ring's width the points were laid for
}

-- the game's arc: the circle through three of its points (their centres in
-- the ComboFrame's top-right corner's terms, y up), and each point's angle on it
function Combo.Read(points)
	local saved, centres = {}, {}
	for i, p in ipairs(points) do
		local ok, pt, rel, rp, x, y = pcall(p.GetPoint, p, 1)
		local okS, w, h = pcall(p.GetSize, p)
		if not (ok and okS and pt == "TOPRIGHT" and rp == "TOPRIGHT" and not Secret(x) and not Secret(y)
			and not Secret(w) and not Secret(h) and type(x) == "number" and type(y) == "number"
			and type(w) == "number" and type(h) == "number") then
			return false
		end
		saved[i] = { pt, rel, rp, x, y }
		centres[i] = { x - w / 2, y - h / 2 }
	end
	local a, b, c = centres[2], centres[4], centres[6]
	if not (a and b and c) then
		return false
	end
	local d = 2 * (a[1] * (b[2] - c[2]) + b[1] * (c[2] - a[2]) + c[1] * (a[2] - b[2]))
	if math.abs(d) < 1e-6 then
		return false
	end
	local a2, b2, c2 = a[1] ^ 2 + a[2] ^ 2, b[1] ^ 2 + b[2] ^ 2, c[1] ^ 2 + c[2] ^ 2
	local ux = (a2 * (b[2] - c[2]) + b2 * (c[2] - a[2]) + c2 * (a[2] - b[2])) / d
	local uy = (a2 * (c[1] - b[1]) + b2 * (a[1] - c[1]) + c2 * (b[1] - a[1])) / d
	local angles = {}
	for i, ce in ipairs(centres) do
		angles[i] = math.atan2(ce[2] - uy, ce[1] - ux)
	end
	Combo.saved, Combo.angles = saved, angles
	return true
end

function Combo.Lay()
	local cf = _G.ComboFrame
	local points = cf and cf.ComboPoints
	local entry = skin and TargetFrame and skin.targets[TargetFrame]
	local ring = type(entry) == "table" and entry.ring
	if not (active and type(points) == "table" and ring and ring.tex) then
		return
	end
	local okW, w = pcall(ring.tex.GetWidth, ring.tex)
	if not okW or Secret(w) or type(w) ~= "number" or w <= 0 or w == Combo.width then
		return
	end
	if not (Combo.angles or Combo.Read(points)) then
		return   -- (the game's anchors unreadable: its own arc stays)
	end
	Combo.width = w
	for i, p in ipairs(points) do
		local okS, pw = pcall(p.GetWidth, p)
		local half = (okS and not Secret(pw) and type(pw) == "number") and pw / 2 or 6
		local r = w / 2 + half + Combo.GAP
		local t = Combo.angles[i]
		if t then
			p:ClearAllPoints()
			p:SetPoint("CENTER", ring.tex, "CENTER", r * math.cos(t), r * math.sin(t))
		end
	end
end

function Combo.Restore()
	local cf = _G.ComboFrame
	local points = cf and cf.ComboPoints
	if not (Combo.width and type(points) == "table" and Combo.saved) then
		return
	end
	Combo.width = nil
	for i, p in ipairs(points) do
		local a = Combo.saved[i]
		if a then
			p:ClearAllPoints()
			p:SetPoint(a[1], a[2], a[3], a[4], a[5])
		end
	end
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
	-- (its shade: the outline's parts, under the whole frame)
	local u = Unit(pf, container)
	-- the name centred on the band's rect, its shade behind it
	local band = PlayerBandRect(container)
	CenterName(PlayerName, band)
	NameShade(PlayerName, container)
	skin.playerRing = SkinRing(picture, container.PlayerPortrait, container.PlayerPortraitMask)
	Shade(u, skin.playerRing, true)
	local health = main.HealthBarsContainer and main.HealthBarsContainer.HealthBar
	Shade(u, SkinBar(health, health, picture, false, true))
	local mana = main.ManaBarArea and main.ManaBarArea.ManaBar
	Shade(u, SkinBar(mana, mana, picture, false))
	TuckBars(skin.playerRing, { health, mana }, false)
	RingCover(skin.playerRing, { health, mana }, false, container)
	Shade(u, SkinCircle(main.LevelBackgroundCircle, _G.PlayerLevelText), true)
	Shade(u, SkinCircle(main.PvpBackgroundCircle), true)
	Watch(u)
end

-- A target-style frame (TargetFrame, FocusFrame): mirrored, the reaction
-- strip is the name band, its ring and level orb marked (above).
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
	-- (its shade: the outline's parts, under the whole frame; the brackets'
	-- soft ends on the right, the ring's side)
	local u = Unit(frame, container)
	if main.ReputationColor then
		Replace(main.ReputationColor, { as = "UI-HUD-UnitFrame-Target-PortraitOn-Type" })
		CenterName(main.Name, main.ReputationColor)
		NameShade(main.Name, container)
	end
	local ring = SkinRing(picture, container.Portrait)   -- its mask follows the portrait's anchors
	Shade(u, ring, true)
	local health = main.HealthBarsContainer and main.HealthBarsContainer.HealthBar
	Shade(u, SkinBar(health, health, picture, true, true))
	Shade(u, SkinBar(main.ManaBar, main.ManaBar, picture, true))
	TuckBars(ring, { health, main.ManaBar }, true)
	RingCover(ring, { health, main.ManaBar }, true, container)
	local level = SkinCircle(main.LevelBackgroundCircle, main.LevelText)
	Shade(u, level, true)
	Shade(u, SkinCircle(contextual and contextual.PvpBackgroundCircle), true)
	Watch(u)
	skin.targets[frame] = { ring = ring }
	-- its marks: the ring and the level orb in the unit's metal (the game's
	-- own elite / rare / boss ring, BossPortraitFrameTexture, stays faded)
	local unit = MarkUnitOf(frame)
	skin.marks[unit] = { unit = unit, ring = ring, orb = level }
	-- the game re-anchors the health container and re-atlases the art on
	-- every target change (CheckClassification): re-fit the brackets and
	-- re-lay the ring cover (the bars' positions moved)
	-- (each made once: nothing made per target change)
	local function Reclassify()
		RetuckAll()
		for _, rep in ipairs(skin.reps) do
			if rep.kind == "bar" and rep.object:GetParent() and rep.rect and rep.object:GetParent():IsShown() then
				rep:Refit()
			end
		end
		for _, cover in ipairs(skin.covers) do
			cover.Refit()
		end
	end
	local function Relay()
		RetuckAll()
		for _, cover in ipairs(skin.covers) do
			cover.Refit()
		end
		-- (the target's combo points round its ring, above: a lookup when laid)
		if frame == TargetFrame then
			Combo.Lay()
		end
	end
	if frame.CheckClassification then
		hooksecurefunc(frame, "CheckClassification", function()
			Kit:WhenOutOfCombat(Reclassify)
		end)
	end
	Perf.HookScript(frame, "OnShow", function()
		Kit:WhenOutOfCombat(Relay)
	end)
	-- the target of target: a small frame with the same parts
	local tot = frame.totFrame
	if tot and tot.FrameTexture and not skin.targets[tot] then
		skin.targets[tot] = true
		FadeArt({
			{ tot.FrameTexture, "UI-HUD-UnitFrame-TargetofTarget-PortraitOn" },
		})
		-- (its shade frame at the target frame's level: under that whole frame)
		local totU = Unit(tot, tot)
		totU.under = frame
		local totRing = SkinRing(tot.FrameTexture, tot.Portrait)
		Shade(totU, totRing, true)
		Shade(totU, SkinBar(tot.HealthBar, tot.HealthBar, tot.FrameTexture, false, true))
		Shade(totU, SkinBar(tot.ManaBar, tot.ManaBar, tot.FrameTexture, false))
		TuckBars(totRing, { tot.HealthBar, tot.ManaBar }, false)
		RingCover(totRing, { tot.HealthBar, tot.ManaBar }, false, tot)
		Watch(totU)
		NameShade(tot.Name, tot)
		-- (its ring marked as its unit is: it has no level orb)
		local totUnit = TOT_UNIT[unit]
		if totUnit then
			skin.marks[totUnit] = { unit = totUnit, ring = totRing }
		end
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
	-- (its shade: a shade frame of its own, anchored on its picture)
	local u = Unit(pf, pf)
	u.picture = PetFrameTexture
	local petRing = SkinRing(PetFrameTexture, pf.Portrait)
	Shade(u, petRing, true)
	Shade(u, SkinBar(PetFrameHealthBar, PetFrameHealthBar, PetFrameTexture, false, true))
	Shade(u, SkinBar(PetFrameManaBar, PetFrameManaBar, PetFrameTexture, false))
	TuckBars(petRing, { PetFrameHealthBar, PetFrameManaBar }, false)
	RingCover(petRing, { PetFrameHealthBar, PetFrameManaBar }, false, pf)
	Watch(u)
	NameShade(_G.PetName or pf.name, pf)
end

--------------------------------------------------------------------------------
-- The party frames (PartyFrame's pooled PartyMemberFrameTemplate, 120 x 53:
-- the picture is a region of the member frame at ARTWORK 0 with the name
-- after it, the portrait at BACKGROUND; the ring goes to BACKGROUND above
-- the portrait, under the name, the name's shade under both; the bars as on the player
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

-- the party backdrop shown or hidden: the members' shade frames put away or
-- back (PartyShadeSync, above)
local PartyBackdrop_OnShowHide = Perf.Shared("OnShow / OnHide on the party backdrop: the members' shade", function()
	PartyShadeSync()
end, "script")

-- a member's name re-anchored or its art swapped: every name re-centred,
-- the bars re-tucked, the covers re-laid (made once: nothing per call)
local function RelayParty()
	RetuckAll()
	for _, entry in ipairs(skin.names) do
		entry.place()
	end
	for _, cover in ipairs(skin.covers) do
		cover.Refit()
	end
end
local Party_Relayout = Perf.Shared("UpdateNameTextAnchors / UpdateArt on a party member: the kit re-laid", function()
	if active then
		Kit:WhenOutOfCombat(RelayParty)
	end
end)

local function SkinPartyMember(frame)
	if not frame or skin.party[frame] then
		return
	end
	local picture = frame.Texture
	local portrait = frame.Portrait
	if not (picture and portrait and frame.HealthBarContainer and frame.ManaBar) then
		return
	end
	-- (its shade: the member and its pet one element, under the member's
	-- frame, made on its first show -- the pool keeps four members, the
	-- empty ones hidden; skin.party keeps it for the backdrop's switch)
	local u = Unit(frame, frame)
	u.party = true
	skin.party[frame] = u
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
		CenterName(frame.Name, band)
	end
	NameShade(frame.Name, frame)
	local ring = SkinRing(picture, portrait, nil, "UnitFramePortraitRingParty")
	Shade(u, ring, true)
	Shade(u, SkinBar(health, health, picture, false, true))
	Shade(u, SkinBar(frame.ManaBar, frame.ManaBar, picture, false))
	TuckBars(ring, { health, frame.ManaBar }, false)
	RingCover(ring, { health, frame.ManaBar }, false, frame)
	-- the member's pet: the same at half size (its name has no shade: the pet's
	-- frame shows none)
	local pet = frame.PetFrame
	if pet and pet.Texture and pet.Portrait and pet.HealthBar then
		FadeArt({
			{ pet.Texture, "UI-HUD-UnitFrame-Party-PortraitOn" },
			{ pet.Flash, "UI-HUD-UnitFrame-Party-PortraitOn-InCombat" },
		})
		local petRing = SkinRing(pet.Texture, pet.Portrait, nil, "UnitFramePortraitRingParty")
		Shade(u, petRing, true)
		Shade(u, SkinBar(pet.HealthBar, pet.HealthBar, pet.Texture, false, true))
		TuckBars(petRing, { pet.HealthBar }, false)
		RingCover(petRing, { pet.HealthBar }, false, pet)
	end
	-- (made on its first show: its shade frame first, put away while the
	-- party backdrop stands -- MakeUnit)
	Watch(u)
	-- the game re-anchors the name and swaps the art (player / vehicle):
	-- re-centre, re-tuck, re-fit (one handler for every member)
	if frame.UpdateNameTextAnchors then
		hooksecurefunc(frame, "UpdateNameTextAnchors", Party_Relayout)
	end
	if frame.UpdateArt then
		hooksecurefunc(frame, "UpdateArt", Party_Relayout)
	end
end

-- a party member's replica (Core/ConfigPreview.lua's, the preview's stand-ins:
-- the game's member frame's keys and geometry) dressed as a member while the
-- look is on (0.17.0; the user: "not a 1-1 replica"). Once per frame; the
-- skin's switch off and on takes it along with the members
function M:DressStandIn(frame)
	if active and skin then
		SkinPartyMember(frame)
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
		local rep = Replace(bg, { as = "PartyFrameBackground", parent = bg, rect = bg, level = 0, noFade = true, alsoFade = extra })
		-- its rail's shade (outside only) under the whole party, hidden with
		-- it (its own element: the party frame is an Edit Mode system), made
		-- on its first show (Edit Mode's setting is off by default); the
		-- members' own shade put away while it shows (PartyShadeSync)
		local u = Unit(bg, bg)
		Shade(u, rep)
		Perf.HookScript(bg, "OnShow", PartyBackdrop_OnShowHide)
		Perf.HookScript(bg, "OnHide", PartyBackdrop_OnShowHide)
		Watch(u)
		PartyShadeSync()
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
		-- (units / due: the shade's units waiting for a first show, and those
		-- shown, made out of combat; marks: the marked frames by their unit)
		-- nameShades: [name] = its shade (NameShade)
		skin = { reps = {}, followers = {}, targets = {}, names = {}, covers = {}, party = {}, units = {}, due = {}, marks = {},
			nameShades = {} }
		-- (taken with the first dressing, once)
		MelloUI:On("shade", OnShade, "Unit Frames Kit name shade")
		MelloUI:On("setting", OnBarSetting, "Unit Frames Kit bar background")
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
	-- (the marks as the targets are now, their events on)
	MarksSync()
	for _, entry in ipairs(skin.names) do
		entry.place()
	end
	SyncNameShades(NameStrength())
	RetuckAll()
	for _, cover in ipairs(skin.covers) do
		cover.Refit()
	end
	Combo.Lay()
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
	SyncNameShades()
	UntuckBars()
	for _, cover in ipairs(skin.covers) do
		cover.holder:Hide()
	end
	-- (the plain pieces back, the marks' events off)
	MarksSync()
	Combo.Restore()
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
	-- and its name: refit the brackets, re-centre the names (made once:
	-- nothing per call)
	local function RelayPlayer()
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
	end
	local function ArtSwapped()
		if active then
			Kit:WhenOutOfCombat(RelayPlayer)
		end
	end
	for _, fname in ipairs({ "PlayerFrame_ToPlayerArt", "PlayerFrame_ToVehicleArt", "PlayerFrame_UpdateArt", "PlayerFrame_UpdatePlayerNameTextAnchor" }) do
		if type(_G[fname]) == "function" then
			hooksecurefunc(fname, ArtSwapped)
		end
	end
end

--------------------------------------------------------------------------------
-- The Reminder widget's anchor (Core/Reminders.lua: its one round button
-- hangs beside the player's portrait ring; user, 2026-09-26: "left of the
-- player ring", Above and Right as options, its own mover when the player
-- frame is hidden).
--   M:ReminderAnchor() -> region, side, reach, far | nil
--     region  what to hang from: the kit's portrait ring while the unit
--             frames wear the kit (a texture whose rect is the ring's whole
--             outline, the compass gems on its edges), else the game's own
--             portrait (PlayerFrame.PlayerFrameContainer.PlayerPortrait)
--     side    the ring's free side, away from the frame's bars and name band
--             (the widget's default place, the approved sketch's): "LEFT",
--             the player frame's portrait standing at its left end
--     reach   how far the frame's art stands past `region`'s edges, in UI
--             units of region's scale: 0 on the kit ring (its rect is the
--             whole ring; the kit's PvP orb stands about 4 px past its
--             left edge, inside the widget's 6 px gap), 4 on
--             the game's portrait (its own ring round it), 13 there while
--             the game's PvP badge shows (its circle over the ring's left
--             rim); add it to the gap. Read at each call (ask again at each
--             raise)
--     far     the frame's other end, for the "Right" place (right of the
--             ring lie the name band and the bars): the health bar's kit
--             bracket while it is on (its rect reaches the far cap's gem),
--             else the game's health bar; nil when there is none
--   nil while the player frame is hidden (none, or not shown): the widget
--   takes its own mover then. The kit coming or going is told on the bus's
--   'cover' (area "unitframes", Kit:Cover / Kit:Uncover): anchor again then.
--   Reads no size and makes nothing (no garbage per call).
--------------------------------------------------------------------------------
local GAME_RING_REACH = 4    -- the game's ring round its 60 px portrait, past the portrait's edges
local GAME_BADGE_REACH = 13  -- the game's PvP badge circle (26 px, its top at the portrait's left edge) past it

-- the player frame's health bar, or the kit's bracket on it while shown
local function FarEnd(main)
	local bars = main and main.HealthBarsContainer
	local health = bars and bars.HealthBar or nil
	local rep = active and health and health.melloRep
	local strip = rep and rawget(rep, "strip")
	if strip and strip:IsShown() then
		return strip
	end
	return health
end

-- (0.19.0) the kit's ring texture round a portrait (a unit frame's, a party
-- member's, a stand-in's) while the look is on and the ring shows, else nil:
-- HealerFrames' debuff glow hugs its rim (Kit:RingRim)
function M:RingOf(portrait)
	local rep = active and portrait and ringOf[portrait]
	local tex = rep and rep.tex
	if not (tex and tex.kitPiece) then
		return nil
	end
	-- (a secret or refused answer counts as shown)
	local ok, shown = pcall(tex.IsShown, tex)
	if ok and not Secret(shown) and not shown then
		return nil
	end
	return tex
end

function M:ReminderAnchor()
	local pf = PlayerFrame
	if not pf then
		return nil
	end
	-- (a secret or refused answer counts as shown)
	local ok, shown = pcall(pf.IsShown, pf)
	if ok and not Secret(shown) and not shown then
		return nil
	end
	local content = pf.PlayerFrameContent
	local main = content and content.PlayerFrameContentMain
	local ring = active and skin and skin.playerRing
	local tex = ring and ring.tex
	if tex and tex.kitPiece and tex:IsShown() then
		return tex, "LEFT", 0, FarEnd(main)
	end
	local container = pf.PlayerFrameContainer
	local portrait = container and container.PlayerPortrait
	if not portrait then
		return nil
	end
	-- the game's PvP badge over the ring's left rim: the widget clears it
	-- (a secret or refused answer: the ring's reach)
	local reach = GAME_RING_REACH
	local badge = main and main.PvpBackgroundCircle
	if badge then
		local okB, on = pcall(badge.IsShown, badge)
		if okB and not Secret(on) and on then
			reach = GAME_BADGE_REACH
		end
	end
	return portrait, "LEFT", reach, FarEnd(main)
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

function M:OnSettingChanged(key)
	if key == "marks" then
		MarksSync()
	elseif key == "barBackground" or key == "barBackgroundAlpha" then
		DressTroughs()
	end
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
-- /ufdump [player|target|focus|pet|tot|party|party1] [frames|reps|names]: the
-- frame's art (regions by default). Opens the copy window. Secret-safe
-- (Kit:DumpWindow guards every read). "names" (2026-10-03, a player's party
-- frame showed two names over each other): every line of text under the
-- frame, six frames deep -- its frame, the text, shown / seen, its alpha, its
-- draw layer, where it lies on the screen and what it hangs on; a name
-- shade's measure is marked (it must never be seen: alpha 0).
--------------------------------------------------------------------------------
local function DumpNames(root)
	local measures = {}
	for name, entry in pairs(skin and skin.nameShades or {}) do
		if entry.measure then
			measures[entry.measure] = name
		end
	end
	local function Show(v)
		if Secret(v) then
			return "<secret>"
		end
		return tostring(v)
	end
	local function Label(f)
		local ok, n = pcall(f.GetDebugName, f)
		if ok and type(n) == "string" and not Secret(n) then
			return (n:gsub("^UIParent%.", ""))
		end
		return tostring(f:GetName() or f)
	end
	local count = 0
	-- one region: a line of text with something in it is printed
	local function Line(f, r)
		if r.GetObjectType and r:GetObjectType() == "FontString" then
			local okT, text = pcall(r.GetText, r)
			if okT and text ~= nil and (Secret(text) or text ~= "") then
				count = count + 1
				local okA, alpha = pcall(r.GetAlpha, r)
				-- (what is seen: its own alpha times its frame's -- a measure's frame is at 0)
				local okE, frameAlpha = pcall(f.GetEffectiveAlpha, f)
				if okA and okE and not Secret(alpha) and not Secret(frameAlpha) and type(frameAlpha) == "number" then
					alpha = string.format("%.2f (seen %.2f)", alpha, alpha * frameAlpha)
				end
				local layer, sub = r:GetDrawLayer()
				local l, b, rr, t
				if MelloUI.Safe.ScreenRect then
					l, b, rr, t = MelloUI.Safe.ScreenRect(r)
				end
				local okP, point, rel = pcall(r.GetPoint, r, 1)
				MelloUI:Print("%s  \"%s\"  %s%s  alpha %s  %s %s  at %s  on %s %s%s", Label(f), Show(text),
					r:IsShown() and "shown" or "hidden", r:IsVisible() and " seen" or "",
					okA and Show(alpha) or "?", tostring(layer), tostring(sub),
					l and string.format("%.0f,%.0f-%.0f,%.0f", l, b, rr, t) or "?",
					okP and tostring(point) or "?", okP and rel and Label(rel) or "-",
					measures[r] and "  [a name shade's measure]" or "")
			end
		end
	end
	local Walk
	local function Regions(f, ...)
		for i = 1, select("#", ...) do
			Line(f, (select(i, ...)))
		end
	end
	local function Children(depth, ...)
		for i = 1, select("#", ...) do
			Walk((select(i, ...)), depth)
		end
	end
	Walk = function(f, depth)
		if depth > 6 or not f.GetRegions then
			return
		end
		Regions(f, f:GetRegions())
		Children(depth + 1, f:GetChildren())
	end
	Walk(root, 0)
	MelloUI:Print("%d lines of text", count)
end

SLASH_MELLOUFDUMP1 = "/ufdump"
SlashCmdList.MELLOUFDUMP = function(msg)
	msg = (msg or ""):lower()
	local which, mode = msg:match("^(%w*)%s*(%a*)$")
	if which == "frames" or which == "reps" or which == "names" then
		which, mode = "", which
	end
	which, mode = which or "", mode or ""
	MelloUI:ClearLog()
	if which == "heals" then
		-- (0.19.0) incoming heals and the debuff glow on every frame (HealerFrames)
		local healer = MelloUI:GetModule("HealerFrames")
		if healer and healer.Dump then
			healer:Dump(function(...) MelloUI:Print(...) end)
		end
		MelloUI:ShowLog("ufdump heals")
		return
	end
	local keys = which ~= "" and { which } or { "player", "target" }
	for _, key in ipairs(keys) do
		local getter = FRAMES[key]
		local frame = getter and getter()
		if not frame then
			MelloUI:Print("%s: no such frame (player, target, focus, pet, tot, party, party1)", key)
		else
			local ok, w, h = pcall(frame.GetSize, frame)
			MelloUI:Print("== %s (%s) %s x %s  %s L%d %s", key, frame:GetName() or "?", ok and not Secret(w) and string.format("%.0f", w) or "?",
				ok and not Secret(h) and string.format("%.0f", h) or "?", frame:GetFrameStrata(), frame:GetFrameLevel(), frame:IsShown() and "shown" or "hidden")
			-- its mark (Elite / Rare ...: the metal twin its ring wears)
			local mark = skin and skin.marks[key == "tot" and "targettarget" or key]
			if mark then
				MelloUI:Print("mark: %s, ring %s", tostring(mark.kind or "none"), tostring(mark.ring and mark.ring.tex and mark.ring.tex.kitName))
			end
			if mode == "names" then
				DumpNames(frame)
			else
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
	end
	MelloUI:ShowLog("ufdump " .. msg)
end
