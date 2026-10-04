--------------------------------------------------------------------------------
-- MelloUI - Action Bar Panel
--
-- The action bars (main bar, the multi bars, stance / pet / possess bars),
-- the micro menu, the bag bar and the experience / reputation / honour bars
-- dressed in the painted kit (Modules/Kit.lua) on the game's own layout.
-- The rule book's fixed looks and the user's picks (kit_raw/actionbar_catalog.png,
-- 2026-09-21: X2 M1, "no custom icons on the micro bar"):
--   R1  every action-style button: the slot rim on its NormalTexture, sized
--       to the bar's pitch so neighbours share a gem, the icon filling the
--       opening, empty slots on stone, the equipped border tinting the rim
--       green; the bar's own frame art lies under the rims and is faded
--   X2  the main bar's gryphon end caps → the rail's orb caps at their height
--   M1  a micro button's plate → the cog plate, the game's glyph on it
--   P1  the status bars' frame → the bracket with the caps outside the bar,
--       the fill behind it on the whole width
-- Bars are re-laid by Edit Mode (UpdateGridLayout): the rims re-size to the
-- new pitch from that post-hook, out of combat. Covers the Dark Mode groups
-- "actionbars", "micromenu", "bagbar" and "statusbars". The UI shade's Action
-- Bars area (0.14.0): the backdrops' outline, the end caps, the status bars'
-- brackets, and the rims where no backdrop covers a bar (below Replace).
-- /abdump [bar|micro|bags|xp|icons] [frames|reps].
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("ActionBarPanel")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
local Shared = Perf.Shared or function(_, fn) return fn end
local Kit = MelloUI.Kit

-- The looks a group of buttons can take (action bars, micro menu, bag bar;
-- the rims are UI Modifications' Button Border, every window's). No "None"
-- since 0.18.5: each element's backdrop has its own switch (ELEMENTS).
local BACKDROP_VALUES = {
	{ value = "red", label = "Red gems" },
	{ value = "iron", label = "Iron gems" },
}
local BACKGROUND_VALUES = Kit.buttonLooks.backgrounds

-- The groups (user, 2026-09-23: the action bars first, then "onto the micro
-- bar and bag buttons next"): each its own four choices
local GROUPS = {
	{ id = "bars", title = "Action Bars", keys = { backdrop = "barBackdrop", background = "barBackground", buttonBackground = "buttonBackground" } },
	{ id = "micro", title = "Micro Menu", keys = { backdrop = "microBackdrop", background = "microBackground", buttonBackground = "microButtonBackground" } },
	{ id = "bags", title = "Bag Bar", keys = { backdrop = "bagBackdrop", background = "bagBackground", buttonBackground = "bagButtonBackground" } },
}

-- The elements that can wear a backdrop (user, 2026-10-04: "Everything
-- should have the option to have a backdrop, but not on by Default"), each
-- by its own switch, in the order that makes a joined backdrop's leader
-- (whose look it takes: Action Bar 1, then the other bars, the micro menu,
-- the bag bar; the experience and reputation bars wear the action bars'
-- look). `frame`: the element's frame; `group`: whose look it wears.
local ELEMENTS = {
	{ key = "backdropBar1", frame = "MainActionBar", name = "Action Bar 1", what = "Action Bar 1", group = "bars" },
	{ key = "backdropBar2", frame = "MultiBarBottomLeft", name = "Action Bar 2", what = "Action Bar 2", group = "bars" },
	{ key = "backdropBar3", frame = "MultiBarBottomRight", name = "Action Bar 3", what = "Action Bar 3", group = "bars" },
	{ key = "backdropBar4", frame = "MultiBarRight", name = "Action Bar 4", what = "Action Bar 4", group = "bars" },
	{ key = "backdropBar5", frame = "MultiBarLeft", name = "Action Bar 5", what = "Action Bar 5", group = "bars" },
	{ key = "backdropBar6", frame = "MultiBar5", name = "Action Bar 6", what = "Action Bar 6", group = "bars" },
	{ key = "backdropBar7", frame = "MultiBar6", name = "Action Bar 7", what = "Action Bar 7", group = "bars" },
	{ key = "backdropBar8", frame = "MultiBar7", name = "Action Bar 8", what = "Action Bar 8", group = "bars" },
	{ key = "backdropStance", frame = "StanceBar", name = "Stance Bar", what = "the stance bar", group = "bars" },
	{ key = "backdropPet", frame = "PetActionBar", name = "Pet Bar", what = "the pet bar", group = "bars" },
	{ key = "backdropPossess", frame = "PossessActionBar", name = "Possess Bar", what = "the possess bar", group = "bars" },
	{ key = "backdropMicro", frame = "MicroMenu", name = "Micro Menu", what = "the micro menu", group = "micro" },
	{ key = "backdropBags", frame = "BagsBar", name = "Bag Bar", what = "the bag bar", group = "bags" },
	{ key = "backdropXP", frame = "MainStatusTrackingBarContainer", name = "Experience Bar", status = true, group = "bars",
	  what = "the experience bar (the reputation bar in its place at the top level)" },
	{ key = "backdropXP2", frame = "SecondaryStatusTrackingBarContainer", name = "Reputation Bar", status = true, group = "bars",
	  what = "the second status bar (a watched reputation while you level)" },
}

local defaults = { hidePageArrows = true }
local options = {
	{ type = "toggle", key = "hidePageArrows", name = "Hide Page Arrows",
	  desc = "Hide the main bar's page number and its up / down arrows (the bar still pages with the keybinds)." },
}
for _, g in ipairs(GROUPS) do
	defaults[g.keys.backdrop] = "red"
	defaults[g.keys.background], defaults[g.keys.buttonBackground] = "stone", "stone"
	if g.id ~= "bars" then
		options[#options + 1] = { type = "subheader", name = g.title }
	end
	local what = g.id == "bars" and "the action bars (and the experience and reputation bars)"
		or (g.id == "micro" and "the micro menu" or "the bag bar")
	-- (the buttons' rim: UI Modifications' Button Border, every window's)
	options[#options + 1] = { type = "dropdown", key = g.keys.backdrop, name = "Backdrop", values = BACKDROP_VALUES,
		desc = "The gems on the corners of the backdrop round " .. what .. ". Elements placed together share one backdrop, "
			.. "in the look of the first of them: Action Bar 1, the other bars, the micro menu, the bag bar. Each element's "
			.. "backdrop is switched on under Backdrops." }
	options[#options + 1] = { type = "dropdown", key = g.keys.background, name = "Backdrop Background", values = BACKGROUND_VALUES,
		desc = "What lies behind the buttons inside the backdrop. All three are chosen with pictures on Action Bars > Bars." }
	options[#options + 1] = { type = "dropdown", key = g.keys.buttonBackground, name = "Button Background", values = BACKGROUND_VALUES,
		desc = "What a button shows inside its rim where it has no icon." }
end
options[#options + 1] = { type = "subheader", name = "Backdrops" }
for _, e in ipairs(ELEMENTS) do
	defaults[e.key] = false
	options[#options + 1] = { type = "toggle", key = e.key, name = e.name, new = "0.18.5",
		desc = "A backdrop round " .. e.what .. ". Elements placed together share one backdrop, shown when one of them has it "
			.. "on" .. (e.status and "; this bar then takes their width, within a limit." or ".") }
end

local M = MelloUI:RegisterModule("ActionBarPanel", {
	title = "Action Bars Kit",
	desc = "The action bars, micro menu, bag bar and experience bars dressed in the painted kit on the game's own layout.",
	window = { label = "Action bars", desc = "Action bars, stance and pet bars, micro menu, bag bar, experience and reputation bars in the kit.", tab = "HUD" },
	enabledByDefault = true,
	defaults = defaults,
	options = options,
	-- the per-element switches taken over once (MigrateBackdrops): this
	-- machine's step, never in a profile
	keep = { "backdropsMigrated" },
})

local skin = nil
local active = false
local hooked = false

local BAR_NAMES = { "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
	"MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar", "PossessActionBar" }
local BAG_BUTTONS = { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
	"CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton" }

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret
local SafeScreenRect = MelloUI.Safe.ScreenRect

local function Replace(region, opts)
	if not region then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Action bars: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

--------------------------------------------------------------------------------
-- The shade (0.14.0: the whole UI's soft shade, Modules/KitShade.lua, the
-- Action Bars area). What stands against the world casts it: each backdrop's
-- rails and gems (each piece its own part of the nine's shadow, ShadePiece),
-- the end caps, the status bars' brackets, and where no backdrop covers a
-- bar (its backdrop off, a bar standing apart) its buttons' rims. A
-- group's shadows lie on its shade frame: BACKGROUND strata, kept there (the
-- game lifts the bars to TOOLTIP while a spell is dragged), level 0 whatever
-- its bar's, under the end caps and every backdrop (the status bars' too: no
-- shadow of this area falls on another bar's art). Rims' shadows lie on a
-- frame of the bar's own like it, shown only while no backdrop covers the
-- bar. Made as the parts are dressed (the bars show from the login), the
-- rims' the first time they are wanted (a bar shown only in a fight: while
-- it is hidden), never in a fight: a layout there runs again after it.
--------------------------------------------------------------------------------

local SHADE_AREA = "actionbars"
-- (level: KitShade lays the shade frame at the root's level plus this, never
-- under 0: so at 0, whatever the bar's level)
local SHADE_OPTS = { strata = "BACKGROUND", level = -10000 }
local CAP_OPTS = { drawn = true }   -- the end caps: drawn to the gryphon's height, not at their kitScale

-- the roots whose shade frame draws shadows (a group's anchor bar, the bar
-- with the end caps, a status bar's container): kept at level 0. `anchor`: a
-- frame of ours the shade frame lies on (the backdrop, a cap's holder, the
-- trough's holder), read when the root's element is made (its first call):
-- never the bar itself, an Edit Mode system
local shadeRoots = {}
local function Shade(root, drawsHere, anchor)
	if drawsHere then
		shadeRoots[root] = true
	end
	SHADE_OPTS.anchor = anchor
	local el = Kit:ShadeElement(root, SHADE_AREA, SHADE_OPTS)
	SHADE_OPTS.anchor = nil
	return el
end

-- a shade frame of ours at level 0 and kept there (a frame the game
-- re-levels takes its children's levels along; fixed where the client can)
local function KeepLow(f)
	if f:GetFrameLevel() ~= 0 then
		f:SetFrameLevel(0)
	end
	if not f.melloLevelFixed and f.SetFixedFrameLevel then
		f.melloLevelFixed = true
		f:SetFixedFrameLevel(true)
	end
end

-- every shade frame that draws shadows back at level 0, after a layout (one
-- made here with its first shadow: never while the area is off, and only out
-- of combat, a bar being protected). One the shade makes as the area is
-- switched on lies at level 0 already, fixed there from the next layout.
local function KeepShadesLow()
	if not Kit:ShadeOn(SHADE_AREA) or InCombatLockdown() then
		return
	end
	for root in pairs(shadeRoots) do
		KeepLow(Shade(root):Host())
	end
end

-- The part of the backdrop's piece each part of its nine shows (Kit:CutNine,
-- piece px), as the options its partner is made with: that part of the
-- piece's shadow, reaching past the piece's outer sides only. Made once per
-- piece (red and iron gems: one geometry today, each its own all the same).
local FRAME_CORNER = 40      -- piece px: the corner square (the gem and the mitre) of the nine-slice
local partCut = {}   -- [piece name] = { [part key] = { cut = { x0, x1, y0, y1 } } }
local function PartCuts(name, p, c)
	local cuts = partCut[name]
	if not cuts then
		local w, h = p.w, p.h
		cuts = {
			tl = { cut = { 0, c, 0, c } }, tr = { cut = { w - c, w, 0, c } },
			bl = { cut = { 0, c, h - c, h } }, br = { cut = { w - c, w, h - c, h } },
			t = { cut = { c, w - c, 0, c } }, b = { cut = { c, w - c, h - c, h } },
			l = { cut = { 0, c, c, h - c } }, r = { cut = { w - c, w, c, h - c } },
		}
		partCut[name] = cuts
	end
	return cuts
end

-- A piece of a backdrop (a rail or a gem, ShapeOn) shaded: its part of the
-- piece's shadow, at the holder's scale. Added to the holder's shade once,
-- with options read when its partner is made; a piece the pool hands out
-- again takes its new part on its partner (Kit:ShadowCut) or, still
-- waiting for one, in those options.
local SEG_PART = { top = "t", bottom = "b", left = "l", right = "r" }
local function ShadePiece(f, tex, name, part)
	tex.kitScale = f.k   -- (drawn at k: its shadow reaches as far)
	local p = f.shade and Kit:Piece(name)
	if not p then
		return
	end
	local cut = PartCuts(name, p, FRAME_CORNER)[part].cut
	if tex.kitShadow then
		Kit:ShadowCut(tex, cut[1], cut[2], cut[3], cut[4])
	else
		local o = tex.melloShadeOpts
		if o then
			local oc = o.cut
			oc[1], oc[2], oc[3], oc[4] = cut[1], cut[2], cut[3], cut[4]
		else
			tex.melloShadeOpts = { cut = { cut[1], cut[2], cut[3], cut[4] } }
			f.shade:Add(tex, tex.melloShadeOpts)
		end
	end
end

-- [root] = true while a shown backdrop covers that element (every member of
-- a drawn backdrop): filled by each layout
local covered = {}

-- A rim drawn at another size than its partner was made at (a micro
-- button's, sized to the bag slots; an action button's at Edit Mode's new
-- Icon Size or Padding): its shadow reaches as far (UI units per painted px;
-- the fit reads its button's scale against the rim frame's again)
local function RimRefit(rep)
	local rim = rep and rep.object
	if not (rim and rim.kitShadow and rim.kitName) then
		return
	end
	local w = MelloUI.Safe.Call(rim, "GetWidth")
	local pw = Kit:Size(rim.kitName, 1)
	if type(w) == "number" and w > 0 and pw and pw > 0 then
		Kit:ShadowFit(rim, w / pw)
	end
end

-- A bar Edit Mode shows only in a fight (Bar Visible: In Combat): hidden at
-- every layout, which all run out of combat, so its rims are shaded while it
-- is hidden (any other hidden bar -- the unused ones, the pet bar with no
-- pet -- the first time it shows)
local function ShowsInCombat(bar)
	local v = bar.visibility
	return not Secret(v) and v == "InCombat"
end

-- A bar's (the micro menu's, the bag bar's) rims as its outline: their
-- shadows on a frame of the bar's own at BACKGROUND level 0, shown while no
-- backdrop covers it (and hidden with the bar, its child); made the first
-- time the bar is shown or wanted in a fight, out of combat (a bar can be
-- protected: a layout in a fight is run again after it, LayoutAll), its
-- rims' partners with it
local function ShadeRims(root, buttons)
	local rs = skin.rims[root]
	if not (active and not covered[root] and #buttons > 0) then
		if rs then
			rs.host:Hide()
		end
		return
	end
	if not rs then
		if InCombatLockdown() or not (root:IsShown() or ShowsInCombat(root)) then
			return
		end
		local host = CreateFrame("Frame", nil, root)
		host.ignoreInLayout = true   -- (never part of the bar's size: see NewFrame)
		host:EnableMouse(false)
		host:SetFrameStrata("BACKGROUND")
		if host.SetFixedFrameStrata then
			host:SetFixedFrameStrata(true)
		end
		-- (on the first button's rim, never on the bar, an Edit Mode system;
		-- only its level counts: the partners lie on their rims)
		local first = buttons[1]
		local firstRep = first.melloRep
		local at = firstRep and rawget(firstRep, "object")
		host:SetAllPoints((type(at) == "table" and at.GetObjectType) and at or first)
		rs = { host = host, opts = { host = host, drawn = true } }
		skin.rims[root] = rs
		local el = Shade(root, nil, host)
		for _, button in ipairs(buttons) do
			if button.melloRep then
				el:Add(button.melloRep, rs.opts)
			end
		end
	end
	KeepLow(rs.host)
	rs.host:Show()
end

--------------------------------------------------------------------------------
-- Action bars
--------------------------------------------------------------------------------

-- The bar's button pitch { x, y }: the first button's size plus the bar's
-- padding (Edit Mode's), secret-safe.
local function BarPitch(bar, button)
	local ok, w, h = pcall(button.GetSize, button)
	if not ok or Secret(w) or Secret(h) or not (w and w > 0 and h and h > 0) then
		return nil
	end
	local pad = tonumber(bar.buttonPadding) or 0
	if Secret(pad) then
		pad = 0
	end
	return { w + pad, h + pad }
end

local function BarButtons(bar)
	if type(bar.actionButtons) == "table" and #bar.actionButtons > 0 then
		return bar.actionButtons
	end
	local list = {}
	local prefix = bar:GetName()
	prefix = prefix and prefix:gsub("ActionBar$", "") or ""
	for i = 1, 12 do
		local button = _G[prefix .. "Button" .. i]
		if button then
			list[#list + 1] = button
		end
	end
	return list
end

local function RefitBar(bar)
	local entry = skin.bars[bar]
	if not (active and entry) then
		return
	end
	local first = entry.buttons[1]
	local pitch = first and BarPitch(bar, first)
	if pitch then
		for _, button in ipairs(entry.buttons) do
			local rep = button.melloRep
			if rep and rep.SetPitch then
				rep:SetPitch(pitch[1], pitch[2])
				RimRefit(rep)   -- (a shaded rim's shadow at its new size and its button's scale)
			end
		end
	end
end

local WatchForBackdrop   -- below: the backdrop round Action Bar 1 follows every bar's layout

-- Bar / Button Background -> the tile behind the buttons or in an empty
-- button ("dark": a near-black fill, none: nothing)
local BACKGROUND_PIECES = Kit.buttonLooks.backgroundPiece

local GROUP = {}          -- id -> group
local KEY_GROUP = {}      -- setting key -> group, role
local ELEMENT_KEY = {}    -- an element's backdrop switch -> the element
for _, e in ipairs(ELEMENTS) do
	ELEMENT_KEY[e.key] = e
end
for _, g in ipairs(GROUPS) do
	GROUP[g.id] = g
	for role, key in pairs(g.keys) do
		KEY_GROUP[key] = { group = g, role = role }
	end
end

local function Setting(g, role)
	return M.db and M.db[g.keys[role]]
end

-- A group's skinned buttons (registered as they are skinned)
local function GroupButtons(g)
	return skin and skin.groups[g.id] and skin.groups[g.id].buttons or {}
end

-- Button Background: the texture in a button's opening where it shows no
-- icon (the stone by default), swapped on every button of the group at once
-- (Kit:SetButtonBackground)
local function ApplyButtonBackground(g, value)
	if not skin then
		return
	end
	for _, button in ipairs(GroupButtons(g)) do
		Kit:SetButtonBackground(button, value)
	end
end

local function AddToGroup(id, button)
	local list = skin.groups[id].buttons
	list[#list + 1] = button
end

local function SkinBar(bar)
	if not bar or skin.bars[bar] then
		return
	end
	local buttons = BarButtons(bar)
	if #buttons == 0 then
		return
	end
	skin.bars[bar] = { buttons = buttons }
	local pitch = BarPitch(bar, buttons[1])
	-- the thin rim on each button, in the look every window's Button Border
	-- names (UI Modifications)
	for _, button in ipairs(buttons) do
		Kit:SkinActionButton(button, Replace, pitch, { as = Kit:ButtonRimRule() })
		AddToGroup("bars", button)
	end
	if bar.UpdateGridLayout then
		hooksecurefunc(bar, "UpdateGridLayout", function()
			Kit:WhenOutOfCombat(function() RefitBar(bar) end)
		end)
	end
	WatchForBackdrop(bar)
	-- the bar's own art (the main bar's frame, the gryphons, the page arrows,
	-- the pooled dividers between its buttons)
	if bar.BorderArt then
		Replace(bar.BorderArt, { as = "UI-HUD-ActionBar-Frame" })
	end
	local function FadeDividers()
		for _, key in ipairs({ "HorizontalDividersPool", "VerticalDividersPool" }) do
			local pool = bar[key]
			if pool then
				for divider in pool:EnumerateActive() do
					if divider.melloRep == nil then
						divider.melloRep = true
						for _, region in ipairs({ divider:GetRegions() }) do
							if region:GetObjectType() == "Texture" then
								Replace(region, { as = Kit:ArtKey(region) })
							end
						end
					end
				end
			end
		end
	end
	if bar.UpdateDividers then
		hooksecurefunc(bar, "UpdateDividers", function()
			if active then
				Kit:WhenOutOfCombat(FadeDividers)
			end
		end)
	end
	FadeDividers()
	-- the end caps: on holders at the BACKGROUND strata (under every bar and
	-- the status bars, whatever their strata and level — user, 2026-09-21:
	-- the caps behind all the bars), following the caps' rects and the
	-- EndCaps frame's show / hide (Edit Mode's 'hide bar art')
	if bar.EndCaps then
		local caps = bar.EndCaps
		local reps = {}   -- { rep, cap }
		local left, right = caps.LeftEndCap, caps.RightEndCap
		if left and left.Texture then
			local rep = Replace(left.Texture, { as = "ui-hud-actionbar-gryphon-left", parent = bar, level = 0, strata = "BACKGROUND" })
			if rep then
				reps[#reps + 1] = { rep = rep, cap = left }
			end
		end
		if right and right.Texture then
			local rep = Replace(right.Texture, { as = "ui-hud-actionbar-gryphon-right", parent = bar, level = 0, strata = "BACKGROUND" })
			if rep then
				reps[#reps + 1] = { rep = rep, cap = right }
			end
		end
		-- each orb shows only while its gryphon would: the EndCaps frame, the
		-- cap frame itself AND its texture (player report, 2026-09-23: "the
		-- new gryphons Icons dont want to Hide in edit mode" -- Edit Mode's
		-- Hide Bar Art did not only hide the EndCaps frame, so the orbs,
		-- which followed that frame alone, stayed)
		local function Wanted(cap)
			if not caps:IsShown() then
				return false
			end
			if cap.IsShown and not cap:IsShown() then
				return false
			end
			if cap.Texture and cap.Texture.IsShown and not cap.Texture:IsShown() then
				return false
			end
			return true
		end
		local function Sync()
			if active then
				for _, entry in ipairs(reps) do
					entry.rep:SetShown(Wanted(entry.cap))
				end
			end
		end
		local function Watch(obj)
			if obj then
				for _, method in ipairs({ "Show", "Hide", "SetShown" }) do
					if type(obj[method]) == "function" then
						hooksecurefunc(obj, method, Sync)
					end
				end
			end
		end
		Watch(caps)
		for _, entry in ipairs(reps) do
			Watch(entry.cap)
			Watch(entry.cap.Texture)
		end
		-- the bar's own updates of its art (Edit Mode's setting applied)
		for _, method in ipairs({ "UpdateEndCaps", "UpdateSystemSettingHideBarArt" }) do
			if type(bar[method]) == "function" then
				hooksecurefunc(bar, method, Sync)
			end
		end
		skin.capSync[#skin.capSync + 1] = Sync
		-- the caps stand against the world at the bar's ends: their shadows
		-- on the bar's shade frame, under them and the backdrop
		local el = Shade(bar, true, reps[1] and rawget(reps[1].rep, "object"))
		for _, entry in ipairs(reps) do
			el:Add(entry.rep, CAP_OPTS)
		end
	end
	local page = bar.ActionBarPageNumber
	if page then
		skin.page = page
		for key, art in pairs({ UpButton = "ui-hud-actionbar-pageuparrow-up", DownButton = "ui-hud-actionbar-pagedownarrow-up" }) do
			local button = page[key]
			if button and button.GetNormalTexture and button:GetNormalTexture() then
				Replace(button:GetNormalTexture(), { as = art, button = button,
					alsoFade = { button:GetPushedTexture(), button:GetHighlightTexture(), button:GetDisabledTexture() } })
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The backdrops (user, 2026-09-23, sketched on the bars: "make a backdrop
-- border behind the action bar ... the whole action bar only has 4 gems and
-- they are on the backdrop ... a concrete texture which stands behind the
-- actionbar buttons"; 2026-10-04, docs/plans/dynamic-backdrops.md: "give the
-- users more freedom to snap more random Elements together and form a
-- unified backdrop"). Every element in ELEMENTS can wear one, by its own
-- switch (off on a new install). Elements that stand together share ONE
-- backdrop: their pads (the buttons' rect grown by the rim and the gap,
-- PadOf) that touch or overlap make a group, drawn when one of them is
-- switched on (the others join it all the same) in its leader's look (the
-- first in ELEMENTS). Its outline is MelloUI.Outline's (Core/Outline.lua):
-- the nine's rails along each side, a gem on each outer corner, the L joint
-- (deco/barjoin) in each inner one, the background through the whole shape
-- from the screen's origin. A status bar in a group with others is fitted
-- to their width (SetFit) and its bracket gives way to the rails. Drawn on a
-- holder of the leader's (its moves, scale and hiding followed), from pools:
-- the same counts again make nothing new. Laid out out of combat after a
-- change (ScheduleBackdrop).
--------------------------------------------------------------------------------

-- Backdrop -> the border piece: the slot rim with heavier top and bottom rails
-- (Tools/build_kit.py heavy_frame), its gems red or iron (one geometry)
local FRAME_PIECES = { red = "deco/barframe_red", iron = "deco/barframe_iron" }
local FRAME_PIECE = FRAME_PIECES.red

-- The choices as the Configurator shows them, in its picture rows too
-- (label, and the piece a preview is drawn with)
M.choices = {
	barBackdrop = {
		{ value = "red", label = "Red gems", piece = FRAME_PIECES.red },
		{ value = "iron", label = "Iron gems", piece = FRAME_PIECES.iron },
	},
	barBackground = BACKGROUND_VALUES,
}
-- the buttons' own backing: the same textures
M.choices.buttonBackground = M.choices.barBackground
local FRAME_GAP = 0.12       -- of a button's size: stone between the buttons' rims and the frame's inner edge
local FRAME_OPEN = { 29, 34, 106, 96 }   -- (the piece's opening when the layout gives none: deco/barframe_red's)
local JOIN_PIECE = "deco/barjoin"        -- an inner corner, its own face turned up and left
local Outline = MelloUI.Outline

-- A frame's rect in screen px (l, b, r, t), nil while it has no size: the
-- addon's one reader (MelloUI.Safe.ScreenRect, Core.lua: secret-safe) with
-- the size the backdrops need. Four numbers, no table.
local function ScreenRect(f)
	local l, b, r, t = SafeScreenRect(f)
	if l and r > l and t > b then
		return l, b, r, t
	end
	return nil
end

-- The buttons' rect of a bar (the ones its layout shows, in screen px), and
-- one button's size.
local function ButtonsRect(bar)
	local entry = skin.bars[bar]
	if not entry then
		return nil
	end
	local count = tonumber(bar.numButtonsShowable) or #entry.buttons
	-- the stance / pet / possess bars keep buttons for forms and spells the
	-- character does not have, hidden: only the shown ones count there (an
	-- action bar's empty buttons hide too, so its layout's count is used)
	local shownOnly = bar == _G.StanceBar or bar == _G.PetActionBar or bar == _G.PossessActionBar
	local rl, rb, rr, rt, size
	for i, button in ipairs(entry.buttons) do
		if i <= count and (not shownOnly or button:IsShown()) then
			local l, b, r, t = ScreenRect(button)
			if l then
				size = size or (r - l)
				if rl then
					rl, rb, rr, rt = math.min(rl, l), math.min(rb, b), math.max(rr, r), math.max(rt, t)
				else
					rl, rb, rr, rt = l, b, r, t
				end
			end
		end
	end
	if not rl then
		return nil, size
	end
	return { rl, rb, rr, rt }, size
end

-- The rect of a set of buttons (the shown ones, screen px) and the size of
-- the smallest one's shorter side.
local function ShownRect(buttons)
	local rl, rb, rr, rt, size
	for _, button in ipairs(buttons) do
		if button:IsShown() then
			-- the rim's rect where it has one (a micro button's rim is a
			-- square on a taller button: the backdrop keeps the same distance
			-- to the rims on every bar)
			local rim = button.melloRep and button.melloRep.object
			local l, b, r, t
			if rim and rim.IsShown and rim:IsShown() then
				l, b, r, t = ScreenRect(rim)
			end
			if not l then
				l, b, r, t = ScreenRect(button)
			end
			if l then
				local side = math.min(r - l, t - b)
				size = size and math.min(size, side) or side
				if rl then
					rl, rb, rr, rt = math.min(rl, l), math.min(rb, b), math.max(rr, r), math.max(rt, t)
				else
					rl, rb, rr, rt = l, b, r, t
				end
			end
		end
	end
	if not rl then
		return nil, size
	end
	return { rl, rb, rr, rt }, size
end

-- Where each group's own buttons hang
local ANCHORS = {
	bars = function() return _G.MainActionBar or _G.MainMenuBar end,
	micro = function() return _G.MicroMenu end,
	bags = function() return _G.BagsBar end,
}

-- The rails' scale for every backdrop (screen px per piece px): the rim as
-- the slot rims were drawn (97 px of the slot = one pitch) on Action Bar 1's
-- buttons, so the rails match wherever two elements meet (user, 2026-09-23:
-- the bag bar's rails, on its larger buttons, came out thicker than the
-- micro menu's where the two joined). Nil without Action Bar 1.
local function RailScale()
	local main = ANCHORS.bars()
	if skin and main and skin.bars[main] then
		local _, size = ButtonsRect(main)
		if size and size > 0 then
			return size / 97
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- The experience and reputation bars fitted (user, 2026-10-04: they "should
-- follow and adjust their width to fit the border and not strech it too
-- much"). A status bar in a drawn backdrop with other elements takes the
-- width of their buttons above or below it, by its scale: the container's
-- plain SetScale (Edit Mode's *Base). Its width is Edit Mode's Size, which
-- the bars inside follow only through the game's own layout functions,
-- never run from here. Within 0.85 - 1.25 only; past that it keeps its own
-- size and the outline takes it as it is. A change keeps its anchor where
-- it stands on the screen by the game's own rule (EditModeSystemMixin:
-- SetScaleOverride: the offsets times old / new). The game's later anchors
-- carry the scale themselves (ApplySystemAnchor: offset / scale), except the
-- bottom stack's for a bar in its default place (EditModeManagerFrame:
-- UpdateBottomActionBarPositions: plain offsets), which KeepFitPlaces puts on
-- the scale again. Never in a fight; the bar's own scale back when it
-- leaves its backdrop, the backdrop goes, or the reskin goes off.
--------------------------------------------------------------------------------

local FIT_MIN, FIT_MAX = 0.85, 1.25
local fits = {}      -- [container] = { base = its scale before, k = the factor on it, x, y = its first point's offsets as set here }
local fitSeen = {}   -- [container] = true: fitted by this layout (filled by each)

local function Protected(f)
	local ok, v = pcall(f.IsProtected, f)
	return ok and not Secret(v) and v and true or false
end

-- the container's anchors, their offsets times `by` (Edit Mode's *Base),
-- and its first point's offsets remembered; false when one cannot be read
local function ScaleAnchors(container, by, fit)
	local n = MelloUI.Safe.Call(container, "GetNumPoints")
	if type(n) ~= "number" or n < 1 then
		return false
	end
	local points = {}
	for i = 1, n do
		local ok, point, rel, relPoint, x, y = pcall(container.GetPoint, container, i)
		x, y = ok and MelloUI.Safe.Finite(x), ok and MelloUI.Safe.Finite(y)
		if not (x and y) then
			return false
		end
		points[i] = { point, rel, relPoint, x * by, y * by }
	end
	local setPoint = container.SetPointBase or container.SetPoint
	for _, pt in ipairs(points) do
		setPoint(container, pt[1], pt[2], pt[3], pt[4], pt[5])
	end
	if fit then
		fit.x, fit.y = points[1][4], points[1][5]
	end
	return true
end

-- The fit `k` on a status bar's container (1: its own scale back); true when
-- its scale changed. Never in a fight.
local function SetFit(container, k)
	local fit = fits[container]
	local have = fit and fit.k or 1
	if math.abs(have - k) < 0.001 or InCombatLockdown() then
		return false
	end
	local base = fit and fit.base
	if not base then
		local ok, v = pcall(container.GetScale, container)
		base = ok and MelloUI.Safe.Finite(v) or 1
		if base <= 0 then
			base = 1
		end
	end
	local setScale = container.SetScaleBase or container.SetScale
	setScale(container, base * k)
	if k == 1 then
		fits[container] = nil
		ScaleAnchors(container, have / k)
	else
		fit = fit or { base = base }
		fit.k = k
		fits[container] = fit
		ScaleAnchors(container, have / k, fit)
	end
	return true
end

-- After the game's bottom stack laid a fitted bar in its default place (its
-- offsets plain, for the bar's own scale; their change from the ones set
-- here tells it did): its offsets on the fit again, at once. Counted
-- (MelloUI.Perf.WriteBack): the stack is laid when a bar shows, hides or
-- moves, never per frame. A protected one in a fight waits for the next
-- layout (LayoutAll runs this first).
local function KeepFitPlaces()
	for container, fit in pairs(fits) do
		local okD, default = pcall(container.IsInDefaultPosition, container)
		local ok, _, _, _, x, y = pcall(container.GetPoint, container, 1)
		x, y = ok and MelloUI.Safe.Finite(x), ok and MelloUI.Safe.Finite(y)
		if okD and default == true and x and y and (math.abs(x - (fit.x or 0)) > 1e-4 or math.abs(y - (fit.y or 0)) > 1e-4)
			and not (InCombatLockdown() and Protected(container)) then
			ScaleAnchors(container, 1 / fit.k, fit)
			MelloUI.Perf.WriteBack("ActionBarPanel: a fitted status bar's place")
		end
	end
end

-- Every fit taken off (the reskin off): out of combat
local function RestoreFits()
	for container in pairs(fits) do
		SetFit(container, 1)
	end
end

--------------------------------------------------------------------------------
-- The members and their groups
--------------------------------------------------------------------------------

-- an element shown on the screen (a micro menu parked by Tweaks' Hide Micro
-- Menu reads shown under its hidden holder: left out)
local function OnScreen(f)
	local ok, v = pcall(f.IsVisible, f)
	return ok and not Secret(v) and v == true
end

-- An element's rect (its buttons', screen px) and a button's size; a status
-- bar's is its container's as it stands (fitted or not), with no size
local function MemberRect(e, root)
	if e.status then
		if not skin.status[root] then
			return nil
		end
		local l, b, r, t = ScreenRect(root)
		if not l then
			return nil
		end
		return { l, b, r, t }
	elseif e.group == "bars" then
		if not skin.bars[root] then
			return nil
		end
		return ButtonsRect(root)
	end
	return ShownRect(GroupButtons(GROUP[e.group]))
end

-- A member's pad: its rect grown by the rim (the piece's, at ks screen px
-- per piece px) and the gap (a share of its button, else of `size`, Action
-- Bar 1's), kept in m.pad
local function PadOf(m, ks, size)
	local p = Kit:Piece(FRAME_PIECE)
	local open = p and p.open or FRAME_OPEN
	local w, h = p and p.w or 135, p and p.h or 130
	local gap = FRAME_GAP * (m.size or size)
	local r, pad = m.rect, m.pad or {}
	pad[1], pad[2] = r[1] - open[1] * ks - gap, r[2] - (h - open[4]) * ks - gap
	pad[3], pad[4] = r[3] + (w - open[3]) * ks + gap, r[4] + open[2] * ks + gap
	m.pad = pad
	return pad
end

-- The elements on the screen now, in ELEMENTS' order: { e, root, rect,
-- size, on, pad } (the entries kept and filled again by each layout)
local members = {}
local function Members()
	local n = 0
	for _, e in ipairs(ELEMENTS) do
		local root = _G[e.frame]
		if type(root) == "table" and root.GetObjectType and OnScreen(root) then
			local rect, size = MemberRect(e, root)
			if rect then
				n = n + 1
				local m = members[n] or {}
				members[n] = m
				m.e, m.root, m.rect = e, root, rect
				m.size = size and size > 0 and size or nil
				m.on = M.db ~= nil and M.db[e.key] == true
			end
		end
	end
	for i = #members, n + 1, -1 do
		members[i] = nil
	end
	return members, n
end

-- The factor that fits status bar m to the buttons of the others of its
-- group above or below it (at least half of one across the other: a bar
-- that only meets its end, the micro menu snapped beside, is not one); 1
-- when there are none or it falls outside the limits
local function FitFor(m, group, list)
	local l, r
	for _, i in ipairs(group) do
		local o = list[i]
		if not o.e.status then
			local ox0, ox1 = o.rect[1], o.rect[3]
			local over = math.min(ox1, m.rect[3]) - math.max(ox0, m.rect[1])
			if over > 0.5 * math.min(ox1 - ox0, m.rect[3] - m.rect[1]) then
				l = l and math.min(l, ox0) or ox0
				r = r and math.max(r, ox1) or ox1
			end
		end
	end
	local fit = fits[m.root]
	local natural = (m.rect[3] - m.rect[1]) / (fit and fit.k or 1)
	if not l or natural <= 0 then
		return 1
	end
	local k = (r - l) / natural
	if k < FIT_MIN or k > FIT_MAX then
		return 1
	end
	return math.floor(k * 1000 + 0.5) / 1000
end

--------------------------------------------------------------------------------
-- The drawing: a holder per leader, its pieces from pools
--------------------------------------------------------------------------------

local holders = {}   -- [element key] = the holder of the backdrop that element leads (made the first time it leads one)
local inShape = {}   -- [root] = true: in a drawn backdrop (filled by each layout; a status bar's bracket gives way)
local holderUsed = {}   -- [holder] = true: drawn by this layout

-- the pools' layers: the background under the rails, the gems and joints
-- over their ends
local POOLS = { stone = { "BACKGROUND", 0 }, rail = { "ARTWORK", 0 }, gem = { "ARTWORK", 1 }, joint = { "ARTWORK", 1 } }

-- the background tiled at one on-screen size and from the screen's origin
-- (user, 2026-09-23: with the micro menu scaled up in Edit Mode its stone
-- came out stretched next to the bag bar's sharper one), so the pieces of a
-- shape show one surface
local function RetileStones(f)
	local pool = f.pools.stone
	for i = 1, pool.used do
		Kit:Retile(pool[i])
	end
end

local function NewHolder(root)
	local f = CreateFrame("Frame", nil, root)
	-- not part of the bar's size: an action bar is a layout frame that grows
	-- round its shown children, so a backdrop (a child reaching past the
	-- buttons) made it grow, which grew the backdrop ... until a relog (user,
	-- 2026-09-23, Edit Mode's Icon Size 100% -> 110%)
	f.ignoreInLayout = true
	f:EnableMouse(false)
	f:SetFrameStrata("BACKGROUND")
	-- and KEPT there: the game raises the action bars to TOOLTIP while a
	-- spell is dragged from the spell book (above the window), and a child
	-- follows its parent's strata -- the backdrop rose with its bar, one
	-- level over the buttons, and its background covered their icons, their
	-- own backgrounds and the stance bar (user, 2026-09-23, /abdump icons:
	-- the buttons TOOLTIP L3, the backdrops TOOLTIP L3 / L4)
	if f.SetFixedFrameStrata then
		f:SetFixedFrameStrata(true)
	end
	f.root = root
	-- its rails' and gems' shadows on the root's shade frame (ShadePiece)
	f.shade = Shade(root, true, f)
	f.pools = {}
	for kind in pairs(POOLS) do
		f.pools[kind] = { used = 0 }
	end
	Perf.SetScript(f, "OnSizeChanged", RetileStones)
	f:Hide()
	return f
end

-- the next texture of a pool (made the first time), showing `piece`
local function Take(f, kind, piece)
	local pool = f.pools[kind]
	local i = pool.used + 1
	pool.used = i
	local tex = pool[i]
	if not tex then
		local layer = POOLS[kind]
		tex = f:CreateTexture(nil, layer[1], nil, layer[2])
		pool[i] = tex
	end
	if piece and tex.kitName ~= piece then
		Kit:Apply(tex, piece)
	end
	tex:ClearAllPoints()
	tex:Show()
	return tex
end

-- a texture over the screen rect x0, y0 - x1, y1 (in f's units from its corner)
local function Lay(f, tex, x0, y0, x1, y1)
	local s = f.s
	tex:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", (x0 - f.ox) / s, (y0 - f.oy) / s)
	tex:SetSize((x1 - x0) / s, (y1 - y0) / s)
end

-- Backdrop Background on a piece of the background: a tile, or the dark
-- fill (the palette's inner panel by its key, as the buttons' Dark
-- background, Kit:SetButtonBackground: a new palette paints it again)
local function PaintStone(tex, choice)
	local bg = BACKGROUND_PIECES[choice]
	if bg then
		if tex.kitName ~= bg then
			Kit:Unpaint(tex)   -- (the dark fill's palette colour no longer on it)
			tex.kitScale = Kit.scale
			Kit:Apply(tex, bg)
		end
		tex:SetVertexColor(1, 1, 1)
		tex.darkFill = nil
	elseif tex.kitName ~= nil or not tex.darkFill then
		Kit:Paint(tex, "innerPanel", "fill", 0.88)
		tex.kitPiece, tex.kitName, tex.darkFill = true, nil, true   -- still ours (a plain mark): never faded with the game's art
	end
	if not tex.melloRegistered then
		tex.melloRegistered = true
		if Kit.RegisterTexture then
			Kit:RegisterTexture(tex)
		end
	end
end

-- a convex corner's gem by the turn (the shape on the loop's left), and
-- where its square lies from the corner (in corner squares)
local GEM = { right = { up = "br" }, up = { left = "tr" }, left = { down = "tl" }, down = { right = "bl" } }
-- each rail's painted band in the nine (piece px from the piece's outer
-- edge): its outer line here (the margin outside it is clear), its inner line
-- the piece's opening (the top and bottom rails heavier)
local RAIL_OUTER = { top = 6, bottom = 5, left = 7, right = 7 }
local function RailInner(p, side)
	local open = p.open or FRAME_OPEN
	if side == "top" then
		return open[2]
	elseif side == "bottom" then
		return p.h - open[4]
	elseif side == "left" then
		return open[1]
	end
	return p.w - open[3]
end
local GEM_AT = { tl = { 0, -1 }, tr = { -1, -1 }, bl = { 0, 0 }, br = { -1, 0 } }
local STEP = { right = { 1, 0 }, up = { 0, 1 }, left = { -1, 0 }, down = { 0, -1 } }
local STONE_INSET = { 0, 0, 0, 0 }   -- (left, bottom, right, top: filled per shape)

-- The outline a holder drew last, kept with its pads and its tolerance (the
-- rail scale's): the same pads again (a setting, a show, a size that moved
-- nothing) reuse it and its background's cut, so such a relayout makes no
-- new shape (Outline.Shape builds its grid afresh: some KB a call)
local function KeptShape(f, pads, tol)
	local key = f.shapeKey
	if not (key and key[1] == tol and #key == 1 + 4 * #pads) then
		return nil
	end
	local k = 1
	for _, r in ipairs(pads) do
		for c = 1, 4 do
			k = k + 1
			if key[k] ~= r[c] then
				return nil
			end
		end
	end
	return f.shape
end

local function KeepShape(f, pads, tol, shape)
	local key = f.shapeKey or {}
	key[1] = tol
	local k = 1
	for _, r in ipairs(pads) do
		for c = 1, 4 do
			k = k + 1
			key[k] = r[c]
		end
	end
	for i = #key, k + 1, -1 do
		key[i] = nil
	end
	f.shapeKey, f.shape, f.fill = key, shape, nil
end

-- One backdrop on holder f: the outline round `pads` (screen px), with the
-- rails and gems of `piece`, the background `choice`, at ks screen px per
-- piece px. False when its leader cannot be read on the screen.
local function DrawShape(f, pads, piece, choice, ks)
	local baseL, baseB = ScreenRect(f.root)
	local s = MelloUI.Safe.Finite(MelloUI.Safe.Call(f.root, "GetEffectiveScale"))
	local p, tc = Kit:Piece(piece), Kit:NineCoords(piece, FRAME_CORNER)
	local jp = Kit:Piece(JOIN_PIECE)
	if not (baseL and s and s > 0 and p and tc and jp) then
		return false
	end
	local C = FRAME_CORNER * ks
	-- (edges closer than half a rail lined up: no notch of a few px)
	local shape = KeptShape(f, pads, C / 2)
	if not shape then
		shape = Outline.Shape(pads, C / 2)
		KeepShape(f, pads, C / 2, shape)
	end
	local X, Y = shape.X, shape.Y
	if not (X and #X >= 2 and #Y >= 2) then
		return false
	end
	f.s, f.k, f.ox, f.oy = s, ks / s, X[1], Y[1]
	f:ClearAllPoints()
	f:SetPoint("BOTTOMLEFT", f.root, "BOTTOMLEFT", (X[1] - baseL) / s, (Y[1] - baseB) / s)
	f:SetSize((X[#X] - X[1]) / s, (Y[#Y] - Y[1]) / s)
	f:SetFrameLevel(3)
	f:Show()
	for _, pool in pairs(f.pools) do
		pool.used = 0
	end
	-- the background, just under the rails' inner edges
	if BACKGROUND_PIECES[choice] or choice == "dark" then
		local open = p.open or FRAME_OPEN
		STONE_INSET[1], STONE_INSET[2] = (open[1] - 3) * ks, (p.h - open[4] - 3) * ks
		STONE_INSET[3], STONE_INSET[4] = (p.w - open[3] - 3) * ks, (open[2] - 3) * ks
		-- (its cut kept with the shape: the insets follow the rail scale, as
		-- the shape's tolerance does)
		f.fill = f.fill or Outline.Fill(shape, STONE_INSET)
		for _, r in ipairs(f.fill) do
			local tex = Take(f, "stone")
			PaintStone(tex, choice)
			Lay(f, tex, r[1], r[2], r[3], r[4])
			tex.kitAlign = "screen"
			Kit:Retile(tex)
		end
	end
	local ju0, ju1, jv0, jv1 = jp.uv[1], jp.uv[2], jp.uv[3], jp.uv[4]
	for _, loop in ipairs(shape.loops) do
		local m = #loop
		-- the rails: each side from corner to corner, short of a gem's square
		-- at an outer corner; at an inner one on past it by the other rail's
		-- clear margin, up to that rail's outer line (as the joins of before:
		-- the two rails' lines meet, the joint where their bands cross)
		for i = 1, m do
			local a, b = loop[i], loop[i % m + 1]
			local side = Outline.SideOf(a.dout)
			local ta = a.convex and C or -RAIL_OUTER[Outline.SideOf(a.din)] * ks
			local tb = b.convex and C or -RAIL_OUTER[Outline.SideOf(b.dout)] * ks
			local x0, y0, x1, y1
			if side == "top" or side == "bottom" then
				if a.x < b.x then
					x0, x1 = a.x + ta, b.x - tb
				else
					x0, x1 = b.x + tb, a.x - ta
				end
				if side == "top" then
					y0, y1 = a.y - C, a.y
				else
					y0, y1 = a.y, a.y + C
				end
			else
				if a.y < b.y then
					y0, y1 = a.y + ta, b.y - tb
				else
					y0, y1 = b.y + tb, a.y - ta
				end
				if side == "right" then
					x0, x1 = a.x - C, a.x
				else
					x0, x1 = a.x, a.x + C
				end
			end
			if x1 > x0 and y1 > y0 then
				local tex = Take(f, "rail", piece)
				local t = tc[side]
				tex:SetTexCoord(t[1], t[2], t[3], t[4])
				Lay(f, tex, x0, y0, x1, y1)
				ShadePiece(f, tex, piece, SEG_PART[side])
			end
		end
		-- the corners: a gem on each outer one, the L joint in each inner one,
		-- over the square where the two rails' bands cross (turned to face the
		-- empty side: mirrored when it lies right of the corner, flipped when
		-- below)
		for i = 1, m do
			local c = loop[i]
			if c.convex then
				local which = GEM[c.din] and GEM[c.din][c.dout]
				if which then
					local at, t = GEM_AT[which], tc[which]
					local tex = Take(f, "gem", piece)
					tex:SetTexCoord(t[1], t[2], t[3], t[4])
					local x, y = c.x + at[1] * C, c.y + at[2] * C
					Lay(f, tex, x, y, x + C, y + C)
					ShadePiece(f, tex, piece, which)
				end
			else
				local ex = STEP[c.dout][1] - STEP[c.din][1]
				local ey = STEP[c.dout][2] - STEP[c.din][2]
				-- the rail along the corner's row (top or bottom) and the one
				-- along its column (left or right), each band from the corner
				local across = (c.din == "left" or c.din == "right") and c.din or c.dout
				local hs = Outline.SideOf(across)
				local vs = Outline.SideOf(across == c.din and c.dout or c.din)
				local ho, hi = RAIL_OUTER[hs] * ks, RailInner(p, hs) * ks
				local vo, vi = RAIL_OUTER[vs] * ks, RailInner(p, vs) * ks
				local y0, y1, x0, x1
				if hs == "top" then
					y0, y1 = c.y - hi, c.y - ho
				else
					y0, y1 = c.y + ho, c.y + hi
				end
				if vs == "left" then
					x0, x1 = c.x + vo, c.x + vi
				else
					x0, x1 = c.x - vi, c.x - vo
				end
				local tex = Take(f, "joint", JOIN_PIECE)
				local u0, u1, v0, v1 = ju0, ju1, jv0, jv1
				if ex > 0 then
					u0, u1 = u1, u0
				end
				if ey < 0 then
					v0, v1 = v1, v0
				end
				tex:SetTexCoord(u0, u1, v0, v1)
				Lay(f, tex, x0, y0, x1, y1)
			end
		end
	end
	-- the pools' textures this shape did not need put away
	for _, pool in pairs(f.pools) do
		for i = pool.used + 1, #pool do
			pool[i]:Hide()
		end
	end
	return true
end

local padList = {}   -- (the members' pads in their order: Outline.Clusters' input, kept)

-- Every backdrop laid out: the members, their groups, the status bars'
-- fits, each drawn group on its leader's holder; the holders no group
-- needs hidden
local function LayoutBackdrops()
	wipe(fitSeen)
	wipe(holderUsed)
	local list, n = Members()
	local ks = RailScale()
	for i = 1, n do
		if ks then
			break
		end
		ks = list[i].size and list[i].size / 97
	end
	if ks and n > 0 then
		local size = ks * 97
		for i = 1, n do
			padList[i] = PadOf(list[i], ks, size)
		end
		for i = #padList, n + 1, -1 do
			padList[i] = nil
		end
		local groups = Outline.Clusters(padList, 0)
		for _, group in ipairs(groups) do
			for _, i in ipairs(group) do
				if list[i].on then
					group.drawn = true
					break
				end
			end
			-- the status bars of a drawn group fitted first: their pads again
			for _, i in ipairs(group) do
				local m = list[i]
				if m.e.status then
					local k = group.drawn and FitFor(m, group, list) or 1
					if k ~= 1 then
						fitSeen[m.root] = true
					end
					if SetFit(m.root, k) then
						local l, b, r, t = ScreenRect(m.root)
						if l then
							m.rect[1], m.rect[2], m.rect[3], m.rect[4] = l, b, r, t
							PadOf(m, ks, size)
						end
					end
				end
			end
		end
		for _, group in ipairs(groups) do
			if group.drawn then
				local leader = list[group[1]]
				local g = GROUP[leader.e.group]
				local f = holders[leader.e.key]
				if not f and not InCombatLockdown() then
					-- (never made in a fight: the leader can be protected; the
					-- layout after it makes it)
					f = NewHolder(leader.root)
					holders[leader.e.key] = f
				end
				local pads = f and {}
				for k, i in ipairs(pads and group or {}) do
					pads[k] = list[i].pad
				end
				local piece = FRAME_PIECES[Setting(g, "backdrop")] or FRAME_PIECE
				if f and DrawShape(f, pads, piece, Setting(g, "background") or "stone", ks) then
					holderUsed[f] = true
					for _, i in ipairs(group) do
						covered[list[i].root] = true
						inShape[list[i].root] = true
					end
				end
			end
		end
	end
	-- a fitted bar no longer in a drawn group: its own size back
	for container in pairs(fits) do
		if not fitSeen[container] then
			SetFit(container, 1)
		end
	end
	for _, f in pairs(holders) do
		if not holderUsed[f] then
			f:Hide()
		end
	end
end

--------------------------------------------------------------------------------
-- The micro menu matched to the bag bar (user, 2026-09-23: "make the microbar
-- buttons match the bag button slots in size and have the same distance to
-- borders as the Bag buttons are"): each micro rim is the bag slots' size and
-- the buttons are spaced as the bag slots are, through the micro menu's own
-- layout padding (the game's is -5: 32 px buttons 27 apart). Both measured
-- without their Edit Mode Size, so at the same Size the two bars match; the
-- game's padding comes back when the reskin goes off.
--------------------------------------------------------------------------------

local microPadding = nil   -- the game's { x, y } padding, while ours is set

-- The bag slots' size and the gap between them, in the bag bar's own units
-- (Edit Mode Size 100 %)
local function BagMetrics()
	local bar = BagsBar
	if not (bar and bar:IsShown()) then
		return nil
	end
	local size, lefts, tops = nil, {}, {}
	for _, name in ipairs(BAG_BUTTONS) do
		local b = _G[name]
		if b and b:IsShown() and b.melloRep then
			local ok, w, l, t = pcall(function() return b:GetWidth(), b:GetLeft(), b:GetTop() end)
			if ok and w and l and t and not (Secret(w) or Secret(l) or Secret(t)) and w > 0 then
				if name == "MainMenuBarBackpackButton" or not size then
					size = w
				end
				lefts[#lefts + 1], tops[#tops + 1] = l, t
			end
		end
	end
	if not size then
		return nil
	end
	local function Pitch(list)
		table.sort(list)
		local best
		for i = 2, #list do
			local d = list[i] - list[i - 1]
			if d > 1 and (not best or d < best) then
				best = d
			end
		end
		return best
	end
	local pitch = Pitch(lefts) or Pitch(tops) or size
	-- already at Size 100 %: a button's width and its neighbours' distance
	-- are read in the bar's own units, which its Edit Mode scale does not
	-- change (multiplied by that scale they made the micro menu grow with
	-- the bag bar -- user, 2026-09-23: "when i scale the bags, the micromenu
	-- also scaled with it")
	return size, math.max(0, pitch - size)
end

local function MatchMicroToBags()
	local menu = MicroMenu
	if not (active and skin and skin.micro and menu) then
		return
	end
	local size, gap = BagMetrics()
	if not size then
		return
	end
	-- in the micro menu's units at its Size 100 % (MicroMenu:UpdateScale:
	-- normalScale = Edit Mode Size, times the game rule's feature scale,
	-- which the micro buttons keep)
	local normal = menu.normalScale and menu.normalScale > 0 and menu.normalScale or 1
	local feature = menu:GetScale() / normal
	if not feature or feature <= 0 then
		feature = 1
	end
	local S, G = size / feature, gap / feature
	local bw, bh
	for _, button in ipairs(GroupButtons(GROUP.micro)) do
		local rep = button.melloRep
		if rep and rep.SetPitch then
			rep:SetPitch(S, S)
			RimRefit(rep)   -- (a shaded rim's shadow reaches as far at its new size)
		end
		if not bw then
			local ok, w, h = pcall(button.GetSize, button)
			if ok and w and h and not (Secret(w) or Secret(h)) then
				bw, bh = w, h
			end
		end
	end
	if not bw then
		return
	end
	local px, py = S + G - bw, S + G - bh
	if math.abs((menu.childXPadding or 0) - px) < 0.01 and math.abs((menu.childYPadding or 0) - py) < 0.01 then
		return
	end
	microPadding = microPadding or { menu.childXPadding, menu.childYPadding }
	Kit:WhenOutOfCombat(function()
		if not active then
			return
		end
		menu.childXPadding, menu.childYPadding = px, py
		if MicroMenuContainer and MicroMenuContainer.Layout then
			MicroMenuContainer:Layout()
		elseif menu.Layout then
			menu:Layout()
		end
	end)
end

-- The game's micro menu padding back (the reskin off)
local function RestoreMicroSpacing()
	local menu = MicroMenu
	if not (menu and microPadding) then
		return
	end
	local saved = microPadding
	microPadding = nil
	Kit:WhenOutOfCombat(function()
		menu.childXPadding, menu.childYPadding = saved[1], saved[2]
		if MicroMenuContainer and MicroMenuContainer.Layout then
			MicroMenuContainer:Layout()
		elseif menu.Layout then
			menu:Layout()
		end
	end)
end

-- Every bar's rims shaded or not (ShadeRims): after a layout, which says
-- what the backdrops cover
local RIM_GROUPS = { "micro", "bags" }   -- (the action bars: each bar its own)
local function SyncRims()
	for bar, entry in pairs(skin.bars) do
		ShadeRims(bar, entry.buttons)
	end
	for _, id in ipairs(RIM_GROUPS) do
		local root = ANCHORS[id]()
		if root and skin[id] then
			ShadeRims(root, GroupButtons(GROUP[id]))
		end
	end
end

-- The status bars' brackets (P1) give way to the rails of a backdrop they
-- are in: one outline, no bracket inside it
local function SyncBrackets()
	for container, rep in pairs(skin.statusReps) do
		rep:SetShown(not inShape[container])
	end
end

local LAYOUT_KEY = "Action bars: layout"   -- (Kit:WhenOutOfCombat's key: one layout waits at a time)
local function LayoutAll()
	if not (active and skin) then
		return
	end
	wipe(covered)
	wipe(inShape)
	MatchMicroToBags()
	KeepFitPlaces()
	LayoutBackdrops()
	SyncRims()
	SyncBrackets()
	KeepShadesLow()
	-- in a fight (a setting changed): laid out again after it, for what a
	-- protected bar could not get now (a holder, a rim frame, a status bar's
	-- fit) and the shade frames' level
	if InCombatLockdown() then
		Kit:WhenOutOfCombat(LayoutAll, LAYOUT_KEY)
	end
end

local function HideAll()
	if not skin then
		return
	end
	for _, f in pairs(holders) do
		f:Hide()
	end
	for _, rs in pairs(skin.rims) do
		rs.host:Hide()
	end
	if next(fits) then
		Kit:WhenOutOfCombat(RestoreFits)
	end
end

-- Laid out again a moment after a change, out of combat (the bars' rects
-- settle after Edit Mode's layout).
local backdropPending = false
local function ScheduleBackdrop()
	if backdropPending or not active then
		return
	end
	backdropPending = true
	C_Timer.After(0.1, function()
		backdropPending = false
		Kit:WhenOutOfCombat(LayoutAll, LAYOUT_KEY)
	end)
end

-- What moves a backdrop: an element re-laid, shown or hidden, resized,
-- dragged in Edit Mode, Edit Mode closed. (The watched ones in a table of
-- ours: never a key on the game's frames.)
local watched = setmetatable({}, { __mode = "k" })
WatchForBackdrop = function(bar)
	if not bar or watched[bar] then
		return
	end
	watched[bar] = true
	Perf.HookScript(bar, "OnShow", ScheduleBackdrop)
	Perf.HookScript(bar, "OnHide", ScheduleBackdrop)
	Perf.HookScript(bar, "OnSizeChanged", ScheduleBackdrop)
	for _, method in ipairs({ "UpdateGridLayout", "Layout", "OnDragStop", "OnSystemPositionChange" }) do
		if type(bar[method]) == "function" then
			hooksecurefunc(bar, method, ScheduleBackdrop)
		end
	end
end

-- A micro button's glyph follow-ups while it cannot be seen (Tweaks' Hide
-- Micro Menu parks the menu under a hidden frame, where IsShown() stays
-- true): the game keeps re-setting the buttons' state atlases (every
-- QUEST_LOG_UPDATE runs UpdateMicroButtons: SetNormal / SetPushed ->
-- SetHighlightAtlas on each), and re-anchoring invisible textures was all
-- that did (the 2026-09-24 review). [button] = its refit, run once when the
-- button shows again (its OnShow: the menu moved back for Edit Mode or the
-- option off; Edit Mode's opening as well, a frame later).
local microStale = setmetatable({}, { __mode = "k" })

local RefitStaleMicro = Shared("OnShow on micro buttons", function(button)
	local refit = microStale[button]
	if refit then
		microStale[button] = nil
		refit()
	end
end, "script")

local function RefitStaleMicros()
	for button, refit in pairs(microStale) do
		if button:IsVisible() then
			microStale[button] = nil
			refit()
		end
	end
end

-- A micro button's window open, a bag slot's bag open: their active state
-- (0.15.0, the active look on every button that can be active). Neither has
-- a checked flag: the game shows a region of the button while it is (a micro
-- button's PushedBackground, SetPushed / SetNormal, the button's state set
-- first; a bag slot's SlotHighlightTexture, UpdateBagButtonHighlight: the
-- bag slots are item buttons, no check buttons), so the rim reads that
-- region and its own Show / Hide read the rim again. [region] = the rim's rep.
local openRep = setmetatable({}, { __mode = "k" })

local Open_OnShown = Shared("Show / Hide on a micro button's pushed background or a bag slot's highlight", function(region)
	local rep = openRep[region]
	if rep and active then
		rep:SetState()
	end
end)

-- the rim's checked() for the region (nil: the button has none)
local function OpenReader(region)
	if not (region and region.IsShown) then
		return nil
	end
	return function()
		return region:IsShown() and true or false
	end
end

-- ... and the rim read again as the game shows or hides it
local function FollowOpen(region, rep)
	if region and region.Show and openRep[region] == nil then
		openRep[region] = rep
		hooksecurefunc(region, "Show", Open_OnShown)
		hooksecurefunc(region, "Hide", Open_OnShown)
		hooksecurefunc(region, "SetShown", Open_OnShown)
	end
end

local function SkinMicroMenu()
	local menu = MicroMenu
	if not menu or skin.micro then
		return
	end
	skin.micro = true
	if menu.BorderArt then
		Replace(menu.BorderArt, { as = "UI-HUD-ActionBar-Frame" })
	end
	if menu.BackgroundArt then
		Replace(menu.BackgroundArt, { as = "MicroMenuBackgroundArt" })
	end
	-- every button in a SQUARE thin rim a little inside the bar's PITCH (the
	-- distance between neighbouring buttons: the game's plates overlap, 32 px
	-- wide buttons 27 px apart); the gems on the backdrop round the bar (user,
	-- 2026-09-23: the micro bar like the action bars); the game's glyph
	-- fitted inside
	local shown = {}
	for _, button in ipairs({ menu:GetChildren() }) do
		if button.Background and button:IsShown() then
			local okL, left = pcall(button.GetLeft, button)
			if okL and left and not Secret(left) then
				shown[#shown + 1] = left
			end
		end
	end
	table.sort(shown)
	local spacing = nil
	for i = 2, #shown do
		local d = shown[i] - shown[i - 1]
		if d > 1 and (not spacing or d < spacing) then
			spacing = d   -- the smallest gap between neighbours: the pitch
		end
	end
	for _, button in ipairs({ menu:GetChildren() }) do
		if button.Background and button.melloRep == nil then
			local ok, w = pcall(button.GetSize, button)
			local step = spacing or ((ok and not Secret(w) and w and w > 0) and w or nil)
			local pitch = step and { step * 0.94, step * 0.94 } or nil   -- until MatchMicroToBags sizes it
			-- the glyph (the normal texture) fitted into the rim's opening the
			-- way an action button's icon is (user, 2026-09-22: "they don't
			-- fit"); its other states and the character button's portrait
			-- follow it
			local glyph = button.GetNormalTexture and button:GetNormalTexture() or nil
			-- the character button has no atlas glyph: its portrait is the
			-- icon fitted into the opening (user, 2026-09-22: the stone for
			-- it too)
			local isPortrait = false
			if not glyph and button.Portrait then
				glyph, isPortrait = button.Portrait, true
			end
			-- the character button's portrait shadow art (atlas-sized, centred)
			-- would show outside the rim: faded with the plate
			local rep = Replace(button.Background, { as = "MicroButtonRim", button = button, rect = button,
				pitch = pitch, icon = glyph, checked = OpenReader(button.PushedBackground),
				alsoFade = { button.PushedBackground, button.Shadow, button.PushedShadow } })
			button.melloRep = rep or false
			if rep then
				AddToGroup("micro", button)
				Kit:RegisterButtonRim(button)
				-- its window opened or closed: the active look follows
				FollowOpen(button.PushedBackground, rep)
			end
			if rep and glyph then
				-- the state textures that follow the glyph, and which atlas
				-- setter moves each
				local others, states = {}, {}
				for _, entry in ipairs({
					{ "SetPushedAtlas", button.GetPushedTexture and button:GetPushedTexture() },
					{ "SetHighlightAtlas", button.GetHighlightTexture and button:GetHighlightTexture() },
					{ "SetDisabledAtlas", button.GetDisabledTexture and button:GetDisabledTexture() },
					{ "portrait", (not isPortrait) and button.Portrait or nil },
				}) do
					local tex = entry[2]
					if tex and tex ~= glyph then
						others[#others + 1] = tex
						states[entry[1]] = tex
					end
				end
				-- Only what the game moved is anchored again (the 2026-09-24
				-- review: each SetNormal / SetPushed re-sets the highlight
				-- atlas alone, yet every state texture, the glyph and the
				-- stone were re-anchored on some 13 buttons per quest log
				-- update): a texture still on the glyph, a glyph still in the
				-- rim's opening, is left as it is (its anchors read, not set)
				local function OnGlyph(tex)
					if tex:GetNumPoints() == 2 then
						local _, rel1 = tex:GetPoint(1)
						local _, rel2 = tex:GetPoint(2)
						if rel1 == glyph and rel2 == glyph then
							return
						end
					end
					tex:ClearAllPoints()
					tex:SetAllPoints(glyph)
				end
				local function Follow()
					for _, tex in ipairs(others) do
						OnGlyph(tex)
					end
				end
				-- the glyph in the rim's opening (Kit:SlotPlaceIcon anchors
				-- it by two points to the rim)
				local function Placed()
					if glyph:GetNumPoints() ~= 2 then
						return false
					end
					local _, rel1 = glyph:GetPoint(1)
					local _, rel2 = glyph:GetPoint(2)
					return rel1 == rep.object and rel2 == rep.object
				end
				Follow()
				-- setting a button's state texture anchors it to fill the
				-- button again, and the game sets the glyph atlas after load
				-- (LoadMicroButtonTextures: the spellbook button on its
				-- update, the guild one on a tabard change; the game menu
				-- one on every net-stats tick): the glyph back into the rim's
				-- opening after each (user, 2026-09-22: "they still don't
				-- fit"). The character button re-anchors its portrait (its
				-- glyph) on press and release (CharacterMicroButtonMixin:
				-- SetPushed / SetNormal): the same, after those. A button
				-- that cannot be seen is done once it shows (all of it).
				local Refit
				function Refit()
					if not (active and rep.object) then
						return
					end
					if not rep.object:IsVisible() then
						microStale[button] = Refit
						return
					end
					local current = button:GetNormalTexture()
					local moved = false
					if current and current ~= glyph then
						glyph = current   -- a new texture object: the rim follows it
						rep.object.icon = current
						moved = true
					end
					if moved or not Placed() then
						Kit:SlotPlaceIcon(rep.object)
					end
					Follow()
					if moved and button.melloStone then
						button.melloStone:ClearAllPoints()
						button.melloStone:SetAllPoints(glyph)   -- the stone stays on the new glyph
					end
				end
				-- a pushed / highlight / disabled atlas set moves that texture
				-- alone (the game's SetNormal / SetPushed set the highlight
				-- atlas: the one texture a quest log update moves)
				local function StateHook(tex)
					return function()
						if not (active and rep.object) then
							return
						end
						if not rep.object:IsVisible() then
							microStale[button] = Refit
							return
						end
						OnGlyph(tex)
					end
				end
				for _, m in ipairs({ "SetNormalAtlas", "SetNormalTexture", "SetPushedAtlas", "SetHighlightAtlas", "SetDisabledAtlas" }) do
					if type(button[m]) == "function" then
						hooksecurefunc(button, m, states[m] and StateHook(states[m]) or Refit)
					end
				end
				-- only the character button's own SetPushed / SetNormal move a
				-- texture of ours (its portrait); the others' only set the
				-- highlight atlas, seen above
				if isPortrait then
					for _, m in ipairs({ "SetPushed", "SetNormal" }) do
						if type(button[m]) == "function" then
							hooksecurefunc(button, m, Refit)
						end
					end
				end
				Perf.HookScript(button, "OnShow", RefitStaleMicro)
				-- the stone in the rim's opening under the glyph, as an empty
				-- action slot has it (user, 2026-09-22: "a background to those
				-- icons"); a region of the button under the ARTWORK glyph, on
				-- the glyph's rect (the opening), shown and hidden with the rim
				local stone = button:CreateTexture(nil, "BACKGROUND", nil, 1)
				stone.kitScale = Kit.scale
				Kit:Apply(stone, "tiles/stone")
				stone:SetAllPoints(glyph)
				Kit:Retile(stone)
				stone:SetShown(rep.object:IsShown())
				local enable1, disable1 = rep.onEnable, rep.onDisable
				rep.onEnable = function(...)
					if enable1 then
						enable1(...)
					end
					stone:Show()
					Kit:Retile(stone)
				end
				rep.onDisable = function(...)
					if disable1 then
						disable1(...)
					end
					stone:Hide()
				end
				if Kit.RegisterTexture then
					Kit:RegisterTexture(stone)   -- Dark Mode's shade
				end
				button.melloStone = stone
				local enable0 = rep.onEnable
				rep.onEnable = function(...)
					if enable0 then
						enable0(...)   -- the glyph into the opening
					end
					Follow()   -- the game may have re-anchored the portrait while the skin was off
				end
				local disable0 = rep.onDisable
				rep.onDisable = function(...)
					if disable0 then
						disable0(...)
					end
					-- the game's anchors: the state textures fill the button,
					-- the portrait sits 7 px in (its XML)
					for _, tex in ipairs(others) do
						tex:ClearAllPoints()
						if tex == button.Portrait then
							tex:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -7)
							tex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -7, 7)
						else
							tex:SetAllPoints(button)
						end
					end
					if isPortrait then
						-- (the slot's own onDisable put the icon's saved points
						-- back; the game's 7 px inset is what those were)
						glyph:ClearAllPoints()
						glyph:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -7)
						glyph:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -7, 7)
					end
				end
			end
		end
	end
	-- the backdrop following the bar (the rims follow every window's Button
	-- Border: registered as they are made)
	WatchForBackdrop(menu)
end

local function SkinBagBar()
	local bar = BagsBar
	if not bar or skin.bags then
		return
	end
	skin.bags = true
	if bar.BorderArt then
		Replace(bar.BorderArt, { as = "UI-HUD-ActionBar-Frame" })
	end
	for _, name in ipairs(BAG_BUTTONS) do
		local button = _G[name]
		if button and button.icon and button.GetNormalTexture then
			local ok, w, h = pcall(button.GetSize, button)
			local pitch = (ok and not Secret(w) and w and w > 0) and { w, h } or nil
			-- the thin rim in the bag bar's Button Border look; the gems on the
			-- backdrop round the bar (user, 2026-09-23). Its bag open is the
			-- game's highlight region shown: the rim's checked state, the
			-- highlight faded (the active look stands in for it)
			local open = button.SlotHighlightTexture
			if type(open) ~= "table" then
				open = nil   -- (a slot without one: no open state, nothing faded)
			end
			local rep = Kit:SkinActionButton(button, Replace, pitch, { as = Kit:ButtonRimRule(), checked = OpenReader(open),
				alsoFade = open and { open } or nil })
			if rep then
				AddToGroup("bags", button)
				FollowOpen(open, rep)
			end
		end
	end
	WatchForBackdrop(bar)
end

--------------------------------------------------------------------------------
-- Status bars (P1 on each container's frame; the shown bar's fill behind it)
--------------------------------------------------------------------------------

local function SkinStatusContainer(container)
	if not (container and container.BarFrameTexture) or skin.status[container] then
		return
	end
	skin.status[container] = true
	-- the fill is a LOW-strata status bar under the MEDIUM container: the
	-- bracket as the container's OVERLAY regions (over the fill, as the
	-- game's hollow frame art was), the trough on a holder at LOW one level
	-- under the status bar
	local shown = container.GetShownBar and container:GetShownBar()
	local fill = shown and shown.StatusBar
	if not fill then
		for _, bar in pairs(container.bars or {}) do
			fill = fill or bar.StatusBar
		end
	end
	local under = CreateFrame("Frame", nil, container)
	under:EnableMouse(false)
	under:SetAllPoints(container)
	under:SetFrameStrata(fill and fill:GetFrameStrata() or "LOW")
	under:SetFrameLevel(math.max((fill and fill:GetFrameLevel() or 1) - 1, 0))
	local rep = Replace(container.BarFrameTexture, { as = "UI-HUD-ExperienceBar-Frame", parent = container, rect = container,
		layer = "OVERLAY", sublevel = 1, troughParent = under, troughLayer = "ARTWORK", troughSub = 0 })
	local textures = MelloUI:GetModule("BarTextures")
	local function Flag(on)
		for _, bar in pairs(container.bars or {}) do
			if bar.StatusBar then
				bar.StatusBar.melloKitBracket = on or nil
				if textures and textures.RefreshMask then
					textures:RefreshMask(bar.StatusBar)
				end
			end
		end
	end
	if rep then
		skin.statusReps[container] = rep   -- (hidden while the bar is in a backdrop: SyncBrackets)
		rep.onEnable = function() Flag(true) end
		rep.onDisable = function() Flag(false) end
		if active then
			Flag(true)
		end
		Perf.HookScript(container, "OnSizeChanged", function()
			if active then
				Kit:WhenOutOfCombat(function() rep:Refit() end)
			end
		end)
		-- the bracket's shadow on the container's shade frame (BACKGROUND,
		-- level 0: under the trough, the fill and the action bars' backdrops,
		-- over the world)
		Shade(container, true, under):Add(rep)
	end
	for _, bar in pairs(container.bars or {}) do
		if bar.StatusBar and bar.StatusBar.Background then
			Replace(bar.StatusBar.Background, { as = "UI-HUD-ExperienceBar-Background" })
		end
	end
	-- a member of the backdrops (its own switch; fitted to the others)
	WatchForBackdrop(container)
end

-- The container's pooled segment dividers → ticks (re-acquired on every
-- UpdateDividers: skinned once per divider frame)
local function SkinDividers(container)
	local pool = container.HorizontalDividersPool
	if not pool then
		return
	end
	for divider in pool:EnumerateActive() do
		if divider.BarDividerTexture and divider.melloRep == nil then
			divider.melloRep = Replace(divider.BarDividerTexture, { as = "UI-HUD-ExperienceBar-Divider" }) or false
		end
	end
end

local function SkinStatusBars()
	local manager = StatusTrackingBarManager
	if not manager then
		return
	end
	local containers = {}
	for _, container in ipairs(manager.barContainers or {}) do
		containers[#containers + 1] = container
	end
	for _, name in ipairs({ "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }) do
		if _G[name] then
			containers[#containers + 1] = _G[name]
		end
	end
	for _, container in ipairs(containers) do
		SkinStatusContainer(container)
		SkinDividers(container)
		if container.UpdateDividers and not container.melloDividerHook then
			container.melloDividerHook = true
			hooksecurefunc(container, "UpdateDividers", function(c)
				if active then
					Kit:WhenOutOfCombat(function() SkinDividers(c) end)
				end
			end)
		end
	end
end

-- The check buttons the kit leaves in the game's own art (0.15.0): the extra
-- action button and the vehicle bar's. A toggled ability there wears the
-- active look while the game checks it, as on every bar (Kit's rule
-- "ActionButtonActiveLook", in place of the button's checked art; where it
-- has none, an agreed addition). Nothing is drawn until one is checked.
local ACTIVE_ONLY = { "ExtraActionButton1", "OverrideActionBarButton1", "OverrideActionBarButton2", "OverrideActionBarButton3",
	"OverrideActionBarButton4", "OverrideActionBarButton5", "OverrideActionBarButton6" }

local function SkinActiveOnly()
	for _, name in ipairs(ACTIVE_ONLY) do
		local button = _G[name]
		if type(button) == "table" and button.SetChecked and button.melloActive == nil then
			local art = button.GetCheckedTexture and button:GetCheckedTexture() or nil
			button.melloActive = Replace(art or button.icon or button, { as = "ActionButtonActiveLook", button = button, icon = button.icon,
				noFade = art == nil }) or false
		end
	end
end

--------------------------------------------------------------------------------
-- Build / lifecycle
--------------------------------------------------------------------------------

local function Build()
	if not skin then
		skin = { reps = {}, bars = {}, status = {}, statusReps = {}, capSync = {}, groups = {}, rims = {} }
		for _, g in ipairs(GROUPS) do
			skin.groups[g.id] = { buttons = {} }
		end
	end
	-- each part on its own, so one failing part reports and the rest builds
	local function Try(label, fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok then
			MelloUI:Print("Action bars: %s failed: %s", label, tostring(err))
		end
	end
	for _, name in ipairs(BAR_NAMES) do
		Try(name, SkinBar, _G[name])
	end
	Try("micro menu", SkinMicroMenu)
	Try("bag bar", SkinBagBar)
	Try("status bars", SkinStatusBars)
	Try("extra and vehicle buttons", SkinActiveOnly)
end

-- The main bar's page number and arrows hidden (user, 2026-09-21): faded
-- and their mouse off, put back on disable or when the option goes off.
local function ApplyPageArrows()
	local page = skin and skin.page
	if not page then
		return
	end
	local hide = active and M.db and M.db.hidePageArrows
	if hide then
		Kit:Fade(page)
	else
		Kit:Unfade(page)
	end
	for _, key in ipairs({ "UpButton", "DownButton" }) do
		local button = page[key]
		if button and button.EnableMouse then
			button:EnableMouse(not hide)
		end
	end
end

local function Activate()
	if active then
		return
	end
	active = true
	Build()
	ApplyPageArrows()
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	for bar in pairs(skin.bars) do
		RefitBar(bar)
	end
	for _, sync in ipairs(skin.capSync) do
		sync()
	end
	LayoutAll()
	for _, g in ipairs(GROUPS) do
		local value = Setting(g, "buttonBackground")
		if value and value ~= "stone" then
			ApplyButtonBackground(g, value)   -- the chosen backing (the buttons were skinned on stone)
		end
	end
	for _, group in ipairs({ "actionbars", "micromenu", "bagbar", "statusbars" }) do
		Kit:Cover(group)
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
	HideAll()
	RestoreMicroSpacing()
	for _, group in ipairs({ "actionbars", "micromenu", "bagbar", "statusbars" }) do
		Kit:Uncover(group)
	end
	ApplyPageArrows()
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "hidePageArrows" then
		ApplyPageArrows()
		return
	end
	-- an element's backdrop switched on or off: the backdrops again
	if ELEMENT_KEY[key] then
		if active then
			LayoutAll()
		end
		return
	end
	-- a group's choice, live
	local owner = KEY_GROUP[key]
	if not owner then
		return
	end
	local g, role = owner.group, owner.role
	if role == "buttonBackground" then
		ApplyButtonBackground(g, value)
	elseif active then
		LayoutAll()               -- its gems or its background (on every backdrop it leads)
	end
end

-- For the Configurator's picture rows (PickerGroups, Core/Config.lua). The
-- groups there are to pick from: { id, title, sections = { { key, title,
-- kind, choices } } }, in order.
function M:PickerGroups()
	local out = {}
	for _, g in ipairs(GROUPS) do
		out[#out + 1] = { id = g.id, title = g.title, sections = {
			{ key = g.keys.backdrop, title = "Backdrop", kind = "frame", choices = M.choices.barBackdrop },
			{ key = g.keys.background, title = "Backdrop Background", kind = "tile", choices = M.choices.barBackground },
			{ key = g.keys.buttonBackground, title = "Button Background", kind = "tile", choices = M.choices.buttonBackground },
		} }
	end
	return out
end

local function Hook()
	if hooked then
		return
	end
	hooked = true
	-- Edit Mode closed: the bars may have been snapped together or apart.
	-- Edit Mode opened: Tweaks brings a hidden micro menu back for it; its
	-- buttons' glyphs fitted once, a frame later (after that move). Told
	-- through the kit's one Edit Mode registration (the bus's 'editmode',
	-- audit 2026-09-24)
	MelloUI:On("editmode", function(entering)
		if not entering then
			ScheduleBackdrop()
		elseif active and next(microStale) then
			C_Timer.After(0, RefitStaleMicros)
		end
	end, M)
	-- the UI Scale changed, or a bar's Size in Edit Mode (user, 2026-09-24:
	-- "UI Scaling Break the UI"): the backdrops are measured from the
	-- buttons' rects ON THE SCREEN, and a new UI scale moves the bars that
	-- hang from different edges of the screen against each other (Edit Mode
	-- also re-scales and re-places the right-hand bars to fit the new
	-- height) without re-laying or re-sizing any bar, so none of the hooks
	-- above fires: the backdrops, their tabs and joins stayed where the old
	-- scale had put them. Laid out again, out of combat, like any change.
	if Kit.OnUIScaleChanged then
		Kit:OnUIScaleChanged(function()
			if active then
				ScheduleBackdrop()
			end
		end)
	end
	-- the game's bottom stack laid its bars in their default places: a
	-- fitted status bar's offsets on its fit again (KeepFitPlaces)
	if EditModeManagerFrame and type(EditModeManagerFrame.UpdateBottomActionBarPositions) == "function" then
		hooksecurefunc(EditModeManagerFrame, "UpdateBottomActionBarPositions", function()
			if next(fits) then
				KeepFitPlaces()
			end
		end)
	end
	-- the status bars appear and stack at runtime (a reputation watched, a
	-- level gained): skin whatever the manager lays out
	if StatusTrackingBarManager then
		for _, method in ipairs({ "LayoutBars", "UpdateBarsShown" }) do
			if StatusTrackingBarManager[method] then
				hooksecurefunc(StatusTrackingBarManager, method, function()
					if active then
						Kit:WhenOutOfCombat(function()
							SkinStatusBars()
							for container in pairs(skin.status) do
								for _, rep in ipairs(skin.reps) do
									if rep.kind == "bar" and rep.rect == container then
										rep:Refit()
									end
								end
							end
						end)
					end
				end)
			end
		end
	end
end

-- (0.18.5) a Backdrop switch per element took over from Backdrop None: a
-- player who had a group's backdrop keeps it (Action Bar 1's, the micro
-- menu's, the bag bar's switch on); None became off, the gems back on red
-- for when it is switched on again. Once (`backdropsMigrated`: this
-- machine's, never in a profile). A new player (no earlier login: UI
-- Modifications' welcomeAsked and seenVersion unset) starts with none.
local MIGRATE_ON = { bars = "backdropBar1", micro = "backdropMicro", bags = "backdropBags" }
local function MigrateBackdrops(db)
	if db.backdropsMigrated then
		return
	end
	db.backdropsMigrated = true
	local um = MelloUI.GetModuleDB and MelloUI:GetModuleDB("UIModifications")
	local existing = type(um) == "table" and (um.welcomeAsked == true or um.seenVersion ~= nil)
	for _, g in ipairs(GROUPS) do
		local key = g.keys.backdrop
		if db[key] == "none" then
			db[key] = "red"
		elseif existing then
			db[MIGRATE_ON[g.id]] = true
		end
	end
end

function M:OnEnable(db)
	self.db = db
	-- the one Action Bar Border choice of earlier the same day, split in two
	local old = db.border
	if old ~= nil then
		db.barBackdrop = (old == "backdrop" and "red") or (old == "backdrop_iron" and "iron") or "none"
		db.border = nil
	end
	MigrateBackdrops(db)
	-- the groups' own button borders gave way to UI Modifications' Button
	-- Border, every window's (read from here once by its migration, which
	-- runs first): the old keys go
	db.buttonBorder, db.microBorder, db.bagBorder = nil, nil, nil
	Hook()
	Kit:WhenOutOfCombat(Activate)
end

function M:OnDisable()
	Deactivate()
end

--------------------------------------------------------------------------------
-- /abdump [bar|micro|bags|xp] [frames|reps]: the art of the main bar (or
-- the micro menu, the bag bar, the main status bar); /abdump backdrops: the
-- backdrops' members, groups and fits. Opens the copy window.
--------------------------------------------------------------------------------
SLASH_MELLOABDUMP1 = "/abdump"
SlashCmdList.MELLOABDUMP = function(msg)
	msg = (msg or ""):lower()
	local which, mode = msg:match("^(%a*)%s*(%a*)$")
	if which == "frames" or which == "reps" then
		which, mode = "", which
	end
	MelloUI:ClearLog()
	if which == "icons" then
		-- every bar button's icon, background and rim, as they are drawn now
		-- (user, 2026-09-23: after dragging a spell the icons and the
		-- backgrounds of a whole bar and the stance bar were gone)
		local function Num(v)
			return (type(v) == "number" and not Secret(v)) and string.format("%.1f", v) or tostring(v)
		end
		local function Region(label, r)
			if not r then
				return label .. " none"
			end
			local okW, w, h = pcall(r.GetSize, r)
			local masks = r.GetNumMaskTextures and r:GetNumMaskTextures() or 0
			local tex = r.GetTexture and r:GetTexture()
			return string.format("%s shown=%s vis=%s a=%s %sx%s masks=%d tex=%s", label, tostring(r:IsShown()), tostring(r:IsVisible()),
				Num(r:GetAlpha()), okW and Num(w) or "?", okW and Num(h) or "?", masks, tostring(tex))
		end
		for _, prefix in ipairs({ "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "StanceButton" }) do
			for i = 1, 12 do
				local button = _G[prefix .. i]
				if button and button:IsShown() then
					local rep = button.melloRep
					local stone = button.melloSlotStone
					MelloUI:Print("%s: shown a=%s eff=%s %s L%d", button:GetName(), Num(button:GetAlpha()), Num(button:GetEffectiveAlpha()),
						button:GetFrameStrata(), button:GetFrameLevel())
					MelloUI:Print("    %s", Region("icon", button.icon))
					MelloUI:Print("    %s", Region("stone", stone and stone.tex))
					MelloUI:Print("    %s", Region("rim", rep and rep.object))
				end
			end
		end
		for _, e in ipairs(ELEMENTS) do
			local f = holders[e.key]
			if f then
				MelloUI:Print("backdrop %s: shown=%s %s L%d", e.key, tostring(f:IsShown()), f:GetFrameStrata(), f:GetFrameLevel())
				-- its shade frame: under every backdrop
				local host = f.shade and f.shade:Host()
				if host then
					MelloUI:Print("shade %s: shown=%s %s L%d", e.key, tostring(host:IsVisible()), host:GetFrameStrata(), host:GetFrameLevel())
				end
			end
		end
		for root, rs in pairs(skin and skin.rims or {}) do
			MelloUI:Print("rim shade %s: shown=%s %s L%d", root:GetName() or "?", tostring(rs.host:IsVisible()), rs.host:GetFrameStrata(), rs.host:GetFrameLevel())
		end
		MelloUI:ShowLog("abdump icons")
		return
	end
	if which == "backdrops" then
		-- the members (screen rects, switches), their groups and leaders, the
		-- pieces each holder draws, the status bars' fits
		local list, n = Members()
		local ks = RailScale()
		MelloUI:Print("rail scale %s (screen px per piece px), %d members", tostring(ks), n)
		for i = 1, n do
			local m = list[i]
			local r = m.rect
			MelloUI:Print("%d %s: %s  %.0f,%.0f - %.0f,%.0f  size %s  in a backdrop %s", i, m.e.name, m.on and "on" or "off",
				r[1], r[2], r[3], r[4], m.size and string.format("%.1f", m.size) or "-", tostring(inShape[m.root] == true))
		end
		for _, e in ipairs(ELEMENTS) do
			local f = holders[e.key]
			if f then
				local counts = {}
				for kind, pool in pairs(f.pools) do
					counts[#counts + 1] = kind .. " " .. pool.used
				end
				table.sort(counts)
				MelloUI:Print("holder of %s: shown=%s  %s", e.name, tostring(f:IsShown()), table.concat(counts, ", "))
			end
		end
		for container, fit in pairs(fits) do
			MelloUI:Print("fit %s: x%.3f on %.3f, default place %s", container:GetName() or "?", fit.k, fit.base,
				tostring(select(2, pcall(container.IsInDefaultPosition, container))))
		end
		MelloUI:ShowLog("abdump backdrops")
		return
	end
	if which == "states" then
		-- every action button's rim against the button's own state (user,
		-- 2026-09-22: rims that looked pressed at rest)
		for _, prefix in ipairs({ "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }) do
			for i = 1, 12 do
				local button = _G[prefix .. i]
				local rep = button and button.melloRep
				local rim = rep and rep.object
				if rim and rim.state and button:IsShown() then
					local okS, state = pcall(button.GetButtonState, button)
					local okC, checked = pcall(button.GetChecked, button)
					local okO, over = pcall(button.IsMouseOver, button)
					local okE, enabled = pcall(button.IsEnabled, button)
					local hk = button.HotKey and button.HotKey.GetText and button.HotKey:GetText() or ""
					if rim.state ~= "normal" then
						MelloUI:Print("%s [%s]: rim %s (hover=%s pressed=%s) | button state=%s checked=%s mouseover=%s enabled=%s",
							button:GetName(), tostring(hk), tostring(rim.state), tostring(rim.hover), tostring(rim.pressed),
							okS and tostring(state) or "?", okC and tostring(checked) or "?", okO and tostring(over) or "?", okE and tostring(enabled) or "?")
					end
				end
			end
		end
		MelloUI:ShowLog("abdump states")
		return
	end
	local roots = { bar = MainActionBar, micro = MicroMenu, bags = BagsBar, xp = MainStatusTrackingBarContainer }
	local root = roots[which ~= "" and which or "bar"]
	if root == MicroMenu and root then
		-- every micro button: the rim's own rect against the glyph's (the
		-- glyph should sit inside the rim's opening, user 2026-09-22)
		for _, button in ipairs({ root:GetChildren() }) do
			local rep = button.melloRep
			local rim = rep and rep.object
			local glyph = button.GetNormalTexture and button:GetNormalTexture()
			if rim and glyph then
				local rl, rb, rw, rh = rim:GetRect()
				local gl, gb, gw, gh = glyph:GetRect()
				local n = glyph:GetNumPoints()
				local p1, rel1 = glyph:GetPoint(1)
				MelloUI:Print("%s: rim %s..%s x %s..%s (%sx%s)  glyph %s..%s x %s..%s (%sx%s)  glyph points=%d first=%s to %s  atlas=%s",
					button:GetName() or "?", rl and math.floor(rl) or "?", rl and math.floor(rl + rw) or "?", rb and math.floor(rb) or "?", rb and math.floor(rb + rh) or "?",
					rw and math.floor(rw) or "?", rh and math.floor(rh) or "?",
					gl and math.floor(gl) or "?", gl and math.floor(gl + gw) or "?", gb and math.floor(gb) or "?", gb and math.floor(gb + gh) or "?",
					gw and math.floor(gw) or "?", gh and math.floor(gh) or "?",
					n or 0, tostring(p1), tostring(rel1 == rim and "rim" or rel1 == button and "button" or rel1 and rel1:GetName() or rel1),
					tostring(glyph.GetAtlas and glyph:GetAtlas()))
			end
		end
	end
	if not root then
		MelloUI:Print("%s: no such frame (bar, micro, bags, xp)", which)
	else
		MelloUI:Print("== %s  %s L%d %s", root:GetName() or "?", root:GetFrameStrata(), root:GetFrameLevel(), root:IsShown() and "shown" or "hidden")
		Kit:DumpWindow(root, skin, mode ~= "" and mode or nil)
		if root == MainStatusTrackingBarContainer then
			MelloUI:Print("status container skinned: %s; bars: %d; manager containers: %d; container %s L%d alpha=%.2f", tostring(skin and skin.status[root]),
				root.bars and #root.bars or 0, StatusTrackingBarManager and StatusTrackingBarManager.barContainers and #StatusTrackingBarManager.barContainers or -1,
				root:GetFrameStrata(), root:GetFrameLevel(), root:GetAlpha())
			local shown = root.GetShownBar and root:GetShownBar()
			local sb = shown and shown.StatusBar
			if sb then
				local tex = sb:GetStatusBarTexture()
				local r, g, b, a = tex:GetVertexColor()
				local l, sl = tex:GetDrawLayer()
				local okT, file = pcall(tex.GetTexture, tex)
				local okA, atlas = pcall(tex.GetAtlas, tex)
				MelloUI:Print("shown bar %s L%d alpha=%.2f; StatusBar %s L%d alpha=%.2f shown=%s; fill %s/%s alpha=%.2f rgb=%.2f %.2f %.2f a=%.2f tex=%s atlas=%s min/max/val=%s/%s/%s",
					shown:GetName() or "?", shown:GetFrameLevel(), shown:GetAlpha(), sb:GetFrameStrata(), sb:GetFrameLevel(), sb:GetAlpha(), tostring(sb:IsShown()),
					tostring(l), tostring(sl), tex:GetAlpha(), r or 0, g or 0, b or 0, a or 0, okT and tostring(file) or "?", okA and tostring(atlas) or "?",
					tostring(select(1, sb:GetMinMaxValues())), tostring(select(2, sb:GetMinMaxValues())), tostring(sb:GetValue()))
			end
		end
		if root == MainActionBar and ActionButton1 and ActionButton2 then
			local ok1, l1 = pcall(ActionButton1.GetLeft, ActionButton1)
			local ok2, l2 = pcall(ActionButton2.GetLeft, ActionButton2)
			if ok1 and ok2 and l1 and l2 and not Secret(l1) and not Secret(l2) then
				MelloUI:Print("button pitch x=%.1f padding=%s", l2 - l1, tostring(MainActionBar.buttonPadding))
			end
		end
	end
	MelloUI:ShowLog("abdump " .. msg)
end
