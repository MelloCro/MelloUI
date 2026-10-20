--------------------------------------------------------------------------------
-- MelloUI - Kit borders, the painted reskin's part (one look, stage I: KitBorders.lua's two OLDSCHOOL blocks)
--
-- (A) the configurator's pictures, the Button Border library, Raid Frame
-- Border and the bar library (Unit Frame, Cast Bar, Personal Display, Swing
-- Timer); (B) the bars' fit, the personal resource display's frame, the bar
-- pictures, the rings and the Portrait Ring / Level Orb. On the core's border
-- library (Modules/KitBorders.lua, loaded before this file): public tables
-- only, its two constants from Kit.__. Their kinds register where they stand
-- (Kit:AddBorderKind's `after`), so Kit.borderKinds keeps its order.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Kit = MelloUI.Kit
-- what the kit keeps beside the game's frames (Kit.lua: weak-keyed, never keys on them)
local pieceNameOf = MelloUI.Kept.pieceNameOf
local W = MelloUI.Widgets
-- the darken as the engine's vertex colour, the glow's strength (KitBorders.lua's)
local DARK, GLOW_ALPHA = Kit.__.BorderDark, Kit.__.BorderGlowAlpha

-- OLDSCHOOL BEGIN (A): the pictures, the Button Border library, Raid Frame Border and the bar library (moves to
-- MelloUI_Oldschool at stage I; it uses only the header's locals and public tables)
do
local repOf = MelloUI.Kept.repOf

--------------------------------------------------------------------------------
-- The configurator's picture of a library style (Kit:ChoicePicture's "rim":
-- KitWindow.lua asks here for a choice with a `style`): the style round the
-- sample icon on the stone, at the light weight, as on a button
--------------------------------------------------------------------------------
local pictures = setmetatable({}, { __mode = "k" })   -- [tile] = its border
function Kit:BorderPicture(tile, choice, icon)
	local b = pictures[tile]
	if not b then
		b = self:NewBorder({ rect = tile.pic, place = "on", layer = "ARTWORK", sub = 3, level = 2 })
		pictures[tile] = b
	end
	local x, y = 0, 0
	if b:Lay(choice.style, "light") then
		x, y = b:Inset()
	end
	if icon then
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", tile.pic, "TOPLEFT", x, -y)
		icon:SetPoint("BOTTOMRIGHT", tile.pic, "BOTTOMRIGHT", -x, y)
	end
end
-- a picture tile showing no library style (another kind's choice drawn on it)
function Kit:BorderPictureOff(tile)
	local b = pictures[tile]
	if b then
		b:SetShown(false)
	end
end

--------------------------------------------------------------------------------
-- Button Border's library styles (Single rail, Backdrop): on a skinned button
-- (its slot rim, rep.object), the library's border laid on the rim's own rect,
-- in its layer, shown and hidden with it, and the rim put out (alpha 0: its
-- states are still read by Kit.lua's Slot_Update, which hands them to the
-- border, rim.libraryBorder). The five thin rims keep their own art and
-- baked states (stage 5 of the plan moves them). Geometry on a protected
-- button waits for the fight's end.
--------------------------------------------------------------------------------
local Secret = MelloUI.Safe.IsSecret
local Perf = MelloUI.Perf:Scope("KitBorders")
local buttonBorders = setmetatable({}, { __mode = "k" })   -- [rim] = its border
local Rim_Follow = Perf.Shared("Show / Hide on a rim a library border stands in for", function(rim)
	local b = buttonBorders[rim]
	if b and rim.libraryBorder == b then
		b:SetShown(rim:IsShown())
	end
end)

local function LibraryOnly(self, style)
	return self.BorderStyles[style] ~= nil and self.buttonLooks.rimKind[style] == nil
end

local LAYER_RANK = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }

function Kit:ButtonLibraryBorder(button, style)
	local rep = button and repOf[button]
	local rim = type(rep) == "table" and rep.object
	if type(rim) ~= "table" or not rim.base then
		return false   -- (no slot rim: nothing of the library's to lay)
	end
	local b = buttonBorders[rim]
	if not LibraryOnly(self, style) then
		if b and rim.libraryBorder then
			rim.libraryBorder = nil
			b:SetShown(false)
			rim:SetAlpha(1)
		end
		return false
	end
	if InCombatLockdown() then
		self:WhenOutOfCombat(function()
			self:SetButtonBorder(button, self:BorderValue("button"))
		end, "Button Border")
		return true
	end
	if not b then
		local layer, sub = "OVERLAY", 3
		local ok, l, s = pcall(rim.GetDrawLayer, rim)
		if ok and not Secret(l) and type(l) == "string" then
			layer, sub = l, (not Secret(s) and tonumber(s)) or 0
		end
		-- (0.20.1) the rails over the icon, whatever layer the slot rim stood in: an item button's icon (the bag
		-- buttons') is BORDER, an action button's BACKGROUND -- under the rim of a bag slot they hid under it
		if LAYER_RANK[layer] and LAYER_RANK[layer] < LAYER_RANK.OVERLAY then
			layer, sub = "OVERLAY", 1
		end
		b = self:NewBorder({ rect = rim, owner = rim:GetParent(), place = "on", layer = layer, sub = sub })
		buttonBorders[rim] = b
		Perf.hooksecurefunc(rim, "Show", Rim_Follow)
		Perf.hooksecurefunc(rim, "Hide", Rim_Follow)
		Perf.hooksecurefunc(rim, "SetShown", Rim_Follow)
	end
	rim.libraryBorder = b
	rim:SetAlpha(0)
	b:Lay(style, "light")
	b:SetShown(rim:IsShown())
	return true
end

--------------------------------------------------------------------------------
-- Raid Frame Border (0.19.8, NEW: the library's first own row): the border on
-- each compact raid / party frame. The Single rail is today's F1 itself (Raid
-- Frames Kit's rail, kept as it is); another style lays the library's border
-- on the frame's rect as regions of the frame (the rails' layer as F1's: over
-- the fills, under the icons and the name) and puts F1's rails out (its stone
-- stays). Modules/RaidFramePanel.lua registers each frame it dresses.
--------------------------------------------------------------------------------
Kit:AddBorderKind({ kind = "raid", key = "raidFrameBorder", default = "single",
	name = "Raid Frame Border", values = Kit.squareLooks, preview = "rim",
	desc = "The border on each raid frame and raid-style party frame: the Single rail they wear today, one of the thin rims the buttons wear, or the Backdrop, its corner gems in the colour of the action bars' Backdrop." }, "aura")

Kit.raidBorders = setmetatable({}, { __mode = "k" })   -- [compact frame] = { border = , rails = F1's skin }

-- F1's rails (its skin's textures but its stone and dim fill) shown or put out
local function RailsAlpha(skin, a)
	if not (skin and skin.all) then
		return
	end
	for _, tex in ipairs(skin.all) do
		if tex ~= skin.body and tex ~= skin.dimFill then
			tex:SetAlpha(a)
		end
	end
end

-- Stage 3 (0.19.8, the plan's decision 7): where the border goes, UI
-- Modifications' Raid Border Placement -- "frame" on each frame, "group"
-- round each raid group (the game's group border, `borderFrame`, shown by
-- Edit Mode's Display Border: G1 the Single rail on it today), "both" (as
-- today, the default)
local function RaidPlace()
	local um = MelloUI:GetModule("UIModifications")
	local v = um and um.db and um.db.raidBorderPlace
	if v == "frame" or v == "group" then
		return v
	end
	return "both"
end

function Kit:RaidBorder(frame, skin)
	local e = self.raidBorders[frame]
	if not e then
		e = { skin = skin, on = true }
		self.raidBorders[frame] = e
	end
	local value = self:BorderValue("raid")
	local frameOn = e.on and RaidPlace() ~= "group"
	if not frameOn or value == "single" or not self.BorderStyles[value] then
		-- F1 as it is (its Single rail; the skin off: back as the game had
		-- it), or put out for "Round the group" (its stone kept)
		RailsAlpha(skin, (e.on and not frameOn) and 0 or 1)
		if skin then
			skin.libraryArt = nil
		end
		if e.border then
			e.border:SetShown(false)
		end
		return
	end
	if not e.border then
		e.border = self:NewBorder({ rect = frame, owner = frame, place = "on", layer = "ARTWORK", sub = -1 })
	end
	if e.border:Lay(value, "light") then
		RailsAlpha(skin, 0)
		-- (Healer Frames' debuff colour on the rails reaches these instead: Kit:TintSkin)
		if skin then
			skin.libraryArt = e.border:Art()
		end
	end
end

-- (0.20.0) How far a raid frame's border reaches into it, x and y in UI
-- units: the library style's opening, else the Single rail's inner edge at
-- the raid frames' weight (Kit.Replacements' "raidframe-hp-bg-white" scale);
-- 0, 0 while the kit draws none round it. MelloUI's own Group Frames lay
-- their bars inside it (the user, 2026-10-09: "the power bar however should
-- be inside of the borders, and fitting the width of the hp bar").
function Kit:RaidFrameInset(frame)
	local e = self.raidBorders[frame]
	if not (e and e.on) or RaidPlace() == "group" then
		return 0, 0
	end
	if e.border and e.border.shown then
		return e.border:Inset()
	end
	local rule = self.Replacements["raidframe-hp-bg-white"]
	local sc = (self.scale or 1) * (rule and rule.scale or 0.8)
	local l, t = self:Piece(self.framePrefix .. "_l"), self:Piece(self.framePrefix .. "_t")
	return (l and l.box) and l.box[3] * sc or 0, (t and t.box) and t.box[4] * sc or 0
end

-- A raid group's border (G1's frame: `holder`, the Single rail at 1.6 on
-- the game's borderFrame, Raid Frames Kit's SkinGroup): the style round the
-- group at the medium weight (a raid group's outline, the weights' table),
-- on a holder of the borderFrame's own, so it shows and hides with the game's
-- group border; G1 faded out under it. "On each frame": no group border
Kit.raidGroups = setmetatable({}, { __mode = "k" })   -- [borderFrame] = { holder = G1's frame, border = }

function Kit:RaidGroupBorder(border, holder)
	local e = self.raidGroups[border]
	if not e then
		e = { holder = holder, on = true }
		self.raidGroups[border] = e
	end
	local value = self:BorderValue("raid")
	local groupOn = e.on and RaidPlace() ~= "frame"
	if not groupOn or value == "single" or not self.BorderStyles[value] then
		if e.holder then
			e.holder:SetAlpha((e.on and not groupOn) and 0 or 1)
		end
		if e.border then
			e.border:SetShown(false)
		end
		return
	end
	if not e.border then
		e.border = self:NewBorder({ rect = border, place = "on", level = 1 })
	end
	if e.border:Lay(value, "medium") and e.holder then
		e.holder:SetAlpha(0)
	end
end

-- Raid Frames Kit on or off: every registered frame's and group's border
-- shown with it
function Kit:RaidBordersShown(on)
	for _, e in pairs(self.raidBorders) do
		e.on = on and true or false
		if not on then
			RailsAlpha(e.skin, 1)
			if e.border then
				e.border:SetShown(false)
			end
		end
	end
	for _, e in pairs(self.raidGroups) do
		e.on = on and true or false
		if not on then
			if e.holder then
				e.holder:SetAlpha(1)
			end
			if e.border then
				e.border:SetShown(false)
			end
		end
	end
	if on then
		self:ApplyRaidBorders()
	end
end

-- every frame and group of the kind again (Kit:ApplyBorder("raid"), Raid
-- Border Placement): a compact frame is protected, so its regions are laid
-- out of combat (at the fight's end)
local function ApplyRaid()
	for frame, e in pairs(Kit.raidBorders) do
		Kit:RaidBorder(frame, e.skin)
	end
	for border, e in pairs(Kit.raidGroups) do
		Kit:RaidGroupBorder(border, e.holder)
	end
	-- (0.20.0) the frames' insides changed with their border: Group Frames lays
	-- its bars again (Kit:RaidFrameInset)
	MelloUI:Fire("raidborder")
end
function Kit:ApplyRaidBorders()
	self:WhenOutOfCombat(ApplyRaid, "Raid Frame Border")
end

--------------------------------------------------------------------------------
-- Stage 2 (0.19.8, the bar shape): the bars' rows take the library's styles
-- too. A bar's bracket (Kit.lua's "bar" replacement: a strip of caps and a
-- middle, the thin looks baked as bars/<look>_*) stays for its own looks; a
-- library style (Single rail, Backdrop) puts the strip out (alpha 0, so it
-- keeps following the bar's show / hide) and lays the library's border ROUND
-- the bar at the light weight, as regions of the bar in the bracket's layer:
-- no arm takes the bar's width (rep:GetArms 0, the cast bar is not
-- narrowed), the fill has the whole rect (rep:GetOpening). The rows:
--   Progress Bar Border   every window's progress bar (no longer the unit
--                         frames': rule 9)
--   Unit Frame Border     (NEW) the unit frames' bars; a Progress Bar Border
--                         chosen before is its start (Core's MergeSettings)
--   Nameplate Border      the nameplates' health bar
--   Cast Bar Border       (NEW) the cast bar: every bar look but Ornate,
--                         today's Cast bar first
--   Personal Resource     (0.21.0, the user: the Personal Display's borders
--   Border                "should reflect the changes made in the Look ->
--                         Borders") MelloUI's Personal Display: each of its bars
--                         and its shield column in any bar look (Ornate first,
--                         today's) or None; the game's own display, seen while
--                         MelloUI's is off, one frame round its bars in the
--                         library's styles alone (a bracket look: none)
--------------------------------------------------------------------------------
local function CastLooks()
	local out = {}
	for _, v in ipairs(Kit.buttonLooks.barBorders) do
		if v.value ~= "frame" then
			out[#out + 1] = v
		end
	end
	return out
end

Kit:AddBorderKind({ kind = "unitframe", key = "unitFrameBorder", default = "frame", name = "Unit Frame Border",
	values = Kit.buttonLooks.barBorders, preview = "bar",
	desc = "The frame round the unit frames' health and power bars (player, target, focus, pet, party): the Ornate bracket they wear by default, the cast bar's, a thin rim, the Single rail or the Backdrop." }, "bar")
Kit:AddBorderKind({ kind = "castbar", key = "castBarBorder", default = "castbar", name = "Cast Bar Border",
	values = CastLooks(), preview = "bar",
	desc = "The frame round your cast bar: the Cast bar bracket with its gem clusters (today's), a thin rim, the Single rail or the Backdrop. A frame laid round the bar leaves it its whole width." }, "nameplate")

local PERSONAL_LOOKS = {}
for _, v in ipairs(Kit.buttonLooks.barBorders) do
	PERSONAL_LOOKS[#PERSONAL_LOOKS + 1] = v
end
PERSONAL_LOOKS[#PERSONAL_LOOKS + 1] = { value = "none", label = "None" }
Kit.personalLooks = PERSONAL_LOOKS
-- (0.21.0: a key of its own -- the old personalBorder's default "none" kept in every player's settings would have
-- left the Personal Display bare; Core's MergeSettings carries a pick made there)
Kit:AddBorderKind({ kind = "personal", key = "personalBarBorder", default = "frame", name = "Personal Display Border",
	values = PERSONAL_LOOKS, preview = "bar",
	desc = "The frame round the Personal Display's bars and its shield column (the bars under your character): the Ornate bracket the unit frames wear (the default), the cast bar's, a thin rim, the Single rail, the Stone rail, the Backdrop or none. The game's own personal resource display, while the Personal Display is off and the unit frames wear their Painted Skin, takes one frame round its bars: a thin rim or one of the library's styles." }, "castbar")
-- (0.20.1, the user: "our swing timers, also need to be able to change their borders to the library selection") the
-- swing timers' frame a choice of its own (their Framed look). (one look, stage B: the swing timers wear the round
-- rim and a flat bar, no frame, so nothing reads this any more: a removal candidate for the options audit, stage H)
Kit:AddBorderKind({ kind = "swing", key = "swingTimerBorder", default = "castbar", name = "Swing Timer Border",
	values = CastLooks(), preview = "bar",
	desc = "No longer used: the swing timers have a round rim and a flat bar and wear no frame, so this changes nothing." }, "personal")

-- (0.20.1, /abdump xp in game: the experience bar's bracket caps back at alpha 1 under its library border -- the
-- ornate bracket over the Stone rail -- something writing our pieces after the library hid them) the caps kept
-- see-through while a library style stands in for them: a post-hook on our own three pieces (never a game region),
-- the writer's stack, count and time kept in Kit.capWrite for /abdump xp
local capRepOf = setmetatable({}, { __mode = "k" })   -- [cap piece] = its bar rep
local function Cap_OnSetAlpha(tex, a)
	local rep = capRepOf[tex]
	if not (rep and rep.libraryStyle) or Secret(a) or a == 0 then
		return
	end
	local w = Kit.capWrite or { n = 0 }
	Kit.capWrite = w
	w.n = w.n + 1
	w.at = GetTime()
	local ds = rawget(_G, "debugstack")
	w.stack = ds and ds(2, 6, 0) or "?"
	tex:SetAlpha(0)
end
local function GuardCaps(rep, strip)
	for _, t in ipairs({ strip.capL, strip.mid, strip.capR }) do
		if capRepOf[t] == nil then
			hooksecurefunc(t, "SetAlpha", Cap_OnSetAlpha)
		end
		capRepOf[t] = rep
	end
end

-- a bar's bracket in a library style, or put back (rep: Kit.lua's bar
-- replacement; true when the library took it)
function Kit:BarLibraryBorder(rep, style)
	local strip = rep and rep.strip
	if not (strip and strip.capL and strip.mid and strip.capR) then
		return false
	end
	if not LibraryOnly(self, style) then
		if rep.libraryStyle then
			rep.libraryStyle, strip.capsOff = nil, nil
			rep.libraryBorder:SetShown(false)
			strip.capL:SetAlpha(1)
			strip.mid:SetAlpha(1)
			strip.capR:SetAlpha(1)
			-- (shown again as the strip shows them: with an owner, only while the strip is shown)
			local vis = rawget(strip, "kitOwner") == nil or strip:IsShown()
			strip.capL:SetShown(vis and (not strip.noL or strip.endL) and true or false)
			strip.mid:SetShown(vis)
			strip.capR:SetShown(vis and (not strip.noR or strip.endR) and true or false)
			rep:Refit()
		end
		return false
	end
	-- (0.20.1, the user: "sometimes the nameplates just randomly change their appearence back to other borders") a
	-- protected bar's border waits for the fight's end -- each bar its own place in the queue (one shared key let
	-- each plate dressed in a fight cancel the one before: only the last got its border) -- and a bar on a frame
	-- that is not protected (a nameplate's) takes it at once
	if InCombatLockdown() then
		local parent = rep.barParent
		local okP, protected = false, nil
		if parent and parent.IsProtected then
			okP, protected = pcall(parent.IsProtected, parent)
		end
		if not okP or Secret(protected) or protected then
			self:WhenOutOfCombat(function()
				rep:SetBar(style)
			end, rep)
			return true
		end
	end
	if not rep.libraryBorder then
		local layer, sub = "BORDER", 1
		local ok, l, s = pcall(strip.capL.GetDrawLayer, strip.capL)
		if ok and not Secret(l) and type(l) == "string" then
			layer, sub = l, (not Secret(s) and tonumber(s)) or 0
		end
		-- (0.20.1) a bar keeps its own trough under its fill -- wherever that fill is drawn, on a lower strata too --
		-- and its Bar Background settings (Unit Frames): a style's background is not laid on a bar; the bar's dropped
		-- cap kept open (the ring side of a unit frame's bar)
		-- (0.20.1) round the bar's own band, not the whole rect: the share of its height the bracket fits to
		-- (rule.heightScale x the panel's artScale -- the Reputation and Skills tabs' 29 px bars, a 15 px fill),
		-- an empty region of the bar's frame laid by Kit:BarLibraryFit
		rep.libBand = rep.libBand or rep.barParent:CreateTexture(nil, "BACKGROUND")
		rep.libBand:ClearAllPoints()
		rep.libBand:SetPoint("LEFT", rep.rect, "LEFT")
		rep.libBand:SetPoint("RIGHT", rep.rect, "RIGHT")
		rep.libraryBorder = self:NewBorder({ rect = rep.libBand, owner = rep.barParent, place = "round", layer = layer, sub = sub,
			noBg = true, open = strip.dropCap })
	end
	-- (0.20.1, /abdump xp after a fresh login: the style noted, the caps never hidden, no guard on them -- a half-done
	-- apply) the caps hidden first, shown off as well as see-through (capsOff: the strip's own Show and fit keep them
	-- off), guarded, and only then the style noted
	strip.capsOff = true
	strip.capL:SetAlpha(0)
	strip.mid:SetAlpha(0)
	strip.capR:SetAlpha(0)
	strip.capL:Hide()
	strip.mid:Hide()
	strip.capR:Hide()
	GuardCaps(rep, strip)
	rep.libraryStyle = style
	self:BarLibraryFit(rep)
	rep.libraryBorder:Lay(style, "light")
	rep.libraryBorder:SetShown(strip:IsShown())
	rep:Refit()
	return true
end
end
-- OLDSCHOOL END

-- OLDSCHOOL BEGIN (B): the bars' fit, the personal resource display's frame, the bar pictures, the rings, the Portrait
-- Ring and the Level Orb (moves to MelloUI_Oldschool at stage I; it uses only the header's locals and public tables)
do
local Secret = MelloUI.Safe.IsSecret
local Perf = MelloUI.Perf:Scope("KitBorders")

function Kit:BarLibraryFit(rep, h)
	local b = rep and rep.libraryBorder
	if not (b and rep.libBand) then
		return
	end
	h = h or rep:RectSize("GetHeight")
	if not (h and h > 0) then
		h = rep.fitHeight
	end
	if not (h and h > 0) then
		return
	end
	local share = rep:LibraryShare()
	local band = h * share
	rep.libBand:SetHeight(band)
	b:SetFit(band * Kit.BorderBandRail, rep:ArtScale())
	-- (0.20.5, the user: the Stone rail apart from the bar, "there is the background, but not attached") the bar's
	-- trough run half a rail under the border on each railed side: the rail's inner edge, its art drawn far smaller
	-- than painted, is soft, and with no style background on a bar (noBg) the world showed through it. Every style's
	-- rail is solid to its opening, so the tucked trough stays hidden under it
	local trough = rep.trough
	if trough and rep.libraryStyle then
		Kit:TuckTrough(trough, rep.rect, b, rep:GetOpening())
	end
end

-- The personal resource display's frame: shown while Unit Frames Kit dresses
-- the unit frames (the display is the Unit Frames page's Personal pick; its
-- Activate / Deactivate: Kit:PersonalBordersShown) and a style is chosen;
-- made on the display's first show (never at login, and no listener of its
-- own: the skin's switch is the one), round its health bars and power bar
local personal = { hooked = false, seen = false, on = false }

local function PersonalLay()
	local prd = rawget(_G, "PersonalResourceDisplayFrame")
	if not (prd and personal.seen) then
		return
	end
	-- (0.21.0: the row offers the bar looks -- a thin rim by its bar name, the library's own name for it found back;
	-- a bracket look has no frame of the library's: none)
	local value = Kit:BorderValue("personal")
	if not Kit.BorderStyles[value] then
		for style, bar in pairs(Kit.buttonLooks.rimKind or {}) do
			if bar == value then
				value = style
			end
		end
	end
	local on = personal.on and value ~= "none" and Kit.BorderStyles[value] ~= nil
	if not on then
		if personal.border then
			personal.border:SetShown(false)
		end
		return
	end
	local top = prd.HealthBarsContainer
	local bottom = prd.PowerBar or top
	if not (top and bottom) then
		return
	end
	if not personal.anchor then
		local a = CreateFrame("Frame", nil, prd)
		a:EnableMouse(false)
		personal.anchor = a
		-- (no piece of the game's under it to keep a shade: the UI shade's unit
		-- frames area round its own outline)
		personal.border = Kit:NewBorder({ rect = a, place = "round", layer = "OVERLAY", sub = 3, level = 2,
			shade = { root = prd, area = "unitframes" } })
	end
	personal.anchor:ClearAllPoints()
	personal.anchor:SetPoint("TOPLEFT", top, "TOPLEFT")
	personal.anchor:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT")
	personal.border:Lay(value, "light")
	personal.border:SetShown(true)
end

local Personal_OnShow = Perf.Shared("OnShow on the personal resource display", function()
	if not personal.seen then
		personal.seen = true
		PersonalLay()
	end
end, "script")

local function PersonalHook()
	local prd = rawget(_G, "PersonalResourceDisplayFrame")
	if personal.hooked or not (prd and prd.HookScript) then
		return
	end
	personal.hooked = true
	Perf.HookScript(prd, "OnShow", Personal_OnShow)
	if prd:IsShown() then
		Personal_OnShow()
	end
end

function Kit:ApplyPersonalBorder()
	if personal.on then
		PersonalHook()
	end
	if personal.seen then
		self:WhenOutOfCombat(PersonalLay, "Personal Resource Border")
	end
end

-- Unit Frames Kit on or off: the display hooked (nothing made: its frame on
-- the first show), the frame shown or put away with the skin
function Kit:PersonalBordersShown(on)
	personal.on = on and true or false
	if personal.on then
		PersonalHook()
	end
	if personal.seen then
		self:WhenOutOfCombat(PersonalLay, "Personal Resource Border")
	end
end

-- the configurator's picture of a library style on a bar row: a sample fill
-- (the palette's gold, as the bar pictures') with the style round it
local barPictures = setmetatable({}, { __mode = "k" })
function Kit:BorderBarPicture(tile, choice, fill, size)
	local b = barPictures[tile]
	if not b then
		b = { anchor = tile.pic:CreateTexture(nil, "BACKGROUND") }
		b.border = self:NewBorder({ rect = b.anchor, owner = tile.pic, place = "round", layer = "ARTWORK", sub = 3 })
		barPictures[tile] = b
	end
	b.anchor:ClearAllPoints()
	b.anchor:SetPoint("LEFT", tile.pic, "LEFT", 6, 0)
	b.anchor:SetPoint("RIGHT", tile.pic, "RIGHT", -6, 0)
	b.anchor:SetHeight(size * 0.22)
	if fill then
		fill:ClearAllPoints()
		fill:SetPoint("TOPLEFT", b.anchor, "TOPLEFT")
		fill:SetPoint("BOTTOMLEFT", b.anchor, "BOTTOMLEFT")
		fill:SetWidth((size - 12) * 0.66)
	end
	b.border:Lay(choice.style, "light")
end
function Kit:BorderBarPictureOff(tile)
	local b = barPictures[tile]
	if b then
		b.border:SetShown(false)
	end
end

--------------------------------------------------------------------------------
-- The rings (0.19.8, the border library's stage 4; the user, 2026-10-06: "Do
-- them now", the NewUI2 rings of decision 10): R1 four diamond studs and R3
-- the plain heavy ring (rings/r1, rings/r3, Tools/make_newui2_borders.py),
-- one normal piece each, their states the library's (the shared glow under
-- the mouse: the ring added again as light in the palette's hover; a darken
-- pressed or disabled; checked: the Active look, Kit:SetActive's round one).
--   Round Border: a round rim (Kit:Slot "roundslot") in a ring style is put
--     out (alpha 0: its states are still read by Kit.lua's Slot_Update, which
--     hands them to rim.libraryBorder) and the ring stands on the rim's own
--     rect, in its layer, shown and hidden with it (its opening a little wider
--     than the gem ring's, as the thin rings' are).
--   Portrait Ring (decision 8: a row of its own, the gem ring by default):
--     the unit frames' portrait ring in a ring style, its opening on the
--     portrait as the gem ring's; its elite / rare / boss twins are the ring
--     in the marks' metals (Tools/kit_marks.py marks/<ring>_<kind>,
--     Modules/KitMarks.lua). Modules/UnitFramePanel.lua registers each ring.
--   (0.19.9, the user's pick 4c 2026-10-08) R5, the NewUI2 winged border
--     (rings/r5, Tools/make_newui2_glyphs.py): a Portrait Ring choice only
--     (`portraitOnly`: its wings would reach past a round button), and the
--     windows' corner ring (Kit.lua's UI-Frame-PortraitMetal-CornerTopLeft).
--------------------------------------------------------------------------------
-- (2026-10-14) `small`: the ring's 64 px copy (Tools/kit_sharp.py via build_kit.py), its thin lines widened -- the one a
-- Round Border draws on round buttons (20-48 UI units), where the big ring shrunk 7-9 times showed as dots; the
-- portrait rings keep `piece`
Kit.RingStyles = {
	r1 = { label = "Four diamond studs", piece = "rings/r1", small = "rings/r1_s" },
	r3 = { label = "Plain heavy ring", piece = "rings/r3", small = "rings/r3_s" },
	r5 = { label = "Winged border", piece = "rings/r5", portraitOnly = true },
	-- (0.20.1, the user: the RPG pack's portrait ring "with its background as a reusable thing", Tools/
	-- make_rpg_frames.py) `bg` its dark ground, drawn under the round element's content (Kit:RoundLibraryRing)
	rpg = { label = "Stone ring", piece = "rings/rpg", bg = "rings/rpg_disc", small = "rings/rpg_s" },
}
Kit.RingStyleOrder = { "r1", "r3", "r5", "rpg" }
for _, id in ipairs(Kit.RingStyleOrder) do
	local st = Kit.RingStyles[id]
	if not st.portraitOnly then
		Kit.roundLooks[#Kit.roundLooks + 1] = { value = id, label = st.label, piece = st.piece }
	end
end

local Ring = {}
Ring.__index = Ring

function Ring:SetShown(on)
	self.shown = on and true or false
	self.tex:SetShown(self.shown)
	if self.bg then
		self.bg:SetShown(self.shown and self.bgPiece ~= nil)
	end
	if self.glow then
		self.glow:SetShown(self.shown and self.lit == "hover")
	end
end

function Ring:SetLit(hover, pressed, disabled)
	local state = disabled and "disabled" or pressed and "pressed" or hover and "hover" or "normal"
	if state == self.lit then
		return
	end
	self.lit = state
	local d = DARK[state] or 1
	self.tex:SetVertexColor(d, d, d)
	if state == "hover" and not self.glow then
		local layer, sub = self.tex:GetDrawLayer()
		self.glow = self.tex:GetParent():CreateTexture(nil, layer, nil, math.min((sub or 0) + 1, 7))
		self.glow:SetAllPoints(self.tex)
		Kit:Apply(self.glow, self.piece)
		self.glow:SetBlendMode("ADD")
		W.Paint(self.glow, "hover", "vertex", GLOW_ALPHA)
	end
	if self.glow then
		if pieceNameOf[self.glow] ~= self.piece then
			Kit:Apply(self.glow, self.piece)
		end
		self.glow:SetShown(self.shown and state == "hover")
	end
end

local ringRims = setmetatable({}, { __mode = "k" })   -- [rim] = its ring
local RingRim_Follow = Perf.Shared("Show / Hide on a round rim a ring stands in for", function(rim)
	local r = ringRims[rim]
	if r and rim.libraryBorder == r then
		r:SetShown(rim:IsShown())
	end
end)

-- Round Border's choice on one round rim: a ring style (true), or none (the
-- rim back as itself: false, Kit.lua's RoundLook lays the baked look)
function Kit:RoundLibraryRing(rim, value)
	local st = value and self.RingStyles[value]
	local r = ringRims[rim]
	if not st then
		if r and rim.libraryBorder == r then
			rim.libraryBorder = nil
			r:SetShown(false)
			rim:SetAlpha(1)
		end
		return false
	end
	if not r then
		local layer, sub = "OVERLAY", 3
		local ok, l, s = pcall(rim.GetDrawLayer, rim)
		if ok and not Secret(l) and type(l) == "string" then
			layer, sub = l, (not Secret(s) and tonumber(s)) or 0
		end
		local host = rim.owner or rim:GetParent()
		r = setmetatable({ rim = rim, tex = host:CreateTexture(nil, layer, nil, sub) }, Ring)
		r.tex:SetAllPoints(rim)
		ringRims[rim] = r
		Perf.hooksecurefunc(rim, "Show", RingRim_Follow)
		Perf.hooksecurefunc(rim, "Hide", RingRim_Follow)
		Perf.hooksecurefunc(rim, "SetShown", RingRim_Follow)
	end
	local piece = (st.small and self:Piece(st.small)) and st.small or st.piece   -- (the small copy on a round button)
	if r.piece ~= piece then
		r.piece = piece
		self:Apply(r.tex, piece)
		r.lit = nil
	end
	-- (0.20.1) the style's ground under the element's content (BACKGROUND -7: under a round button's icon)
	r.bgPiece = st.bg
	if st.bg then
		if not r.bg then
			r.bg = (rim.owner or rim:GetParent()):CreateTexture(nil, "BACKGROUND", nil, -7)
			r.bg:SetAllPoints(rim)
		end
		if pieceNameOf[r.bg] ~= st.bg then
			self:Apply(r.bg, st.bg)
		end
	end
	rim.libraryBorder = r
	rim:SetAlpha(0)
	-- (the rim's own glow, a lit card's, shows the ring as light too)
	if rim.glow and pieceNameOf[rim.glow] ~= piece then
		self:Apply(rim.glow, piece)
	end
	r:SetShown(rim:IsShown())
	r:SetLit(rim.hover, rim.pressed, rim.lastDisabled)
	return true
end

-- The Portrait Ring's row: the gem ring, or a ring style (after Round Border)
Kit.portraitLooks = { { value = "gem", label = "Gem ring", piece = "window/portrait_ring" } }
for _, id in ipairs(Kit.RingStyleOrder) do
	local st = Kit.RingStyles[id]
	Kit.portraitLooks[#Kit.portraitLooks + 1] = { value = id, label = st.label, piece = st.piece }
end
Kit:AddBorderKind({ kind = "portrait", key = "portraitRing", default = "gem", name = "Portrait Ring",
	values = Kit.portraitLooks, preview = "rim",
	desc = "The ring round the portraits of the unit frames: the player, target, focus, pet, target of target and "
		.. "party. The gem ring, a ring with four diamond studs, a plain heavy ring, or the winged border the windows "
		.. "wear. An elite, rare or boss shows the ring in its metal with its crest (Elite and Rare Marks)." }, "round")

-- (0.20.1, the user: "the around the skull border and its background for us to use for unitframes and nameplates, we
-- dont need the skull we have our own" -- Tools/make_rpg_frames.py) Level Orb: the kit's orb, or the RPG pack's stone
-- badge with its own ground (buttons/orb_rpg, _disc) round the level number, on the unit frames and the nameplates
-- (Kit.lua's UI-HUD-UnitFrame-SmallCircle and ui-hud-nameplates-levelindicator rules take its piece as they are
-- dressed, Kit:RuleFor: a frame already dressed keeps its orb until a /reload; the ground: Kit:OrbDisc). A rank shows
-- by its crest (Elite and Rare Marks): the stone badge has no metal twins (Kit:MarkPiece) and stays stone.
Kit.orbLooks = {
	{ value = "kit", label = "Kit orb", piece = "buttons/orb_normal" },
	{ value = "rpg", label = "Stone badge", piece = "buttons/orb_rpg", disc = "buttons/orb_rpg_disc" },
}
Kit:AddBorderKind({ kind = "orb", key = "levelOrb", default = "kit", name = "Level Orb", values = Kit.orbLooks,
	preview = "rim",
	desc = "The round badge round the level on the unit frames and the nameplates: the kit's orb, or a stone badge "
		.. "with its own dark ground. Frames already shown change after a /reload." }, "portrait")

function Kit:OrbLook()
	local v = self:BorderValue("orb")
	for _, look in ipairs(self.orbLooks) do
		if look.value == v then
			return look
		end
	end
	return self.orbLooks[1]
end

-- the portrait ring's piece now (the gem ring's elsewhere: windows keep theirs)
function Kit:PortraitRingPiece()
	local st = self.RingStyles[self:BorderValue("portrait") or ""]
	return st and st.piece or "window/portrait_ring"
end

-- [rep] = its frame's change (a function: the portrait fitted again, the
-- marks, the bars' tuck, the cover), for every unit frame ring
Kit.portraitRings = setmetatable({}, { __mode = "k" })

-- One ring in the chosen piece: the texture re-pieced and re-sized by its
-- opening (rep.Resquare, Kit.lua's texture replacement) and its frame told;
-- a region of a protected frame, laid out of combat. True when it changed.
function Kit:LayPortraitRing(rep)
	local piece = self:PortraitRingPiece()
	local was = rep.ringPiece or (rep.rule and rep.rule.piece)
	if was == piece or not rep.tex then
		rep.ringPiece = piece
		return false
	end
	if InCombatLockdown() then
		self:WhenOutOfCombat(function() self:ApplyPortraitRings() end, "Portrait Ring")
		return false
	end
	rep.ringPiece = piece
	self:Apply(rep.tex, piece)
	if rep.Resquare then
		rep.Resquare(was)
	end
	local changed = self.portraitRings[rep]
	if type(changed) == "function" then
		pcall(changed, rep)
	end
	return true
end

function Kit:PortraitRing(rep, changed)
	if type(rep) ~= "table" then
		return
	end
	self.portraitRings[rep] = changed or true
	self:LayPortraitRing(rep)
end

function Kit:ApplyPortraitRings()
	for rep in pairs(self.portraitRings) do
		self:LayPortraitRing(rep)
	end
end
end
-- OLDSCHOOL END
